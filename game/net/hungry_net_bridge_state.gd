extends Node

const HungryContent := preload("../hungry_content.gd")

const HungryEvent := preload("hungry_event.gd")

const HungryEvents := preload("hungry_events.gd")

const HungryInterest := preload("hungry_interest.gd")

const HungryMatchNet := preload("hungry_match_net.gd")

const HungryMonster := preload("../hungry_monster.gd")

const HungryNetCommand := preload("hungry_net_command.gd")

const HungryNetLink := preload("hungry_net_link.gd")

const HungryPiece := preload("../hungry_piece.gd")

const HungryPieceNet := preload("hungry_piece_net.gd")

const HungryProjectile := preload("../hungry_projectile.gd")

const HungryRequest := preload("hungry_request.gd")

const HungryWorld := preload("../hungry_world.gd")

## How far a reconcile has to move the owning client's monster before dot-net counts it
## as a correction, in [b]pixels[/b]. [member DotNetConfig.reconcile_position_epsilon]
## defaults to 0.01, a centimetre in the 3D games it was written for and a hundredth of a
## pixel here -- below the 1/128 the wire quantises a position to, so every replay from
## a snapshot read as a correction (0.02 to 0.04 px apart). Half a pixel is the least a
## screen can show. Every DotNetConfig this game builds sets it.
const RECONCILE_EPSILON := 0.5

## Joins a [HungryWorld] to a [DotNetManager]. The netcode seam, and the only file in
## this project that names both.
##
## [b]Every other join here is a few lines because the addons refuse to know about each
## other; this one is a file because the ordering is the hard part.[/b] dot-net drives
## simulation per entity, and this game's tick order is a whole-world property —
## everybody moves, then eating is resolved against the world as it is afterwards, then
## merges, then projectiles, then the match. Reconciling those two facts is what
## [method ensure_world_ticked] is.
##
## [codeblock]
## # server
## bridge.attach(world, net, server)          # `server` is the node the link mirrors
## bridge.add_player(peer_id, session_id, "Ada", avatar)
## bridge.server_tick(tick)                   # instead of world.tick()
##
## # client
## bridge.attach(world, net, client_link)
## bridge.ask_for_world()
## bridge.client_tick(tick, command)
## [/codeblock]

const CHANNEL := "hungry.net"

## Bytes [method DotNetManager.encode_ack] produces, and the prefix of every input
## packet. Fixed width, so the command that follows starts at a known offset.
const ACK_BYTES := 4

## Commands in every input packet: this tick's and the four before it, so a lost packet
## costs the server no tick unless the next four are lost too. Over WebSocket nothing is
## ever lost; over ENet (the desktop client, since servers went dual-stack) one command a
## packet was a tick the server ran on the previous command for every packet dropped.
## game-arena measured it first: 80% of ticks with the right command at 20% loss with one
## copy, 99-100% with three, and five closed the rest (2026-10-09).
const INPUT_COPIES := 5

## Ticks between two leaderboard broadcasts. Twice a second: it is a list of numbers that
## change slowly and nobody reads it at 20 Hz.
const BOARD_INTERVAL_TICKS := 30

## The client has been told who it is and what the world is.
signal hello_received(player_id: int)

## A peer said it can receive, for the first time on this connection. Server side.
##
## The moment anything a join owes somebody can be sent — the chat backlog, the join
## notice, the hunters and the hazards already standing in the arena. dot-server's
## `client_spawn` is too early for all of them, because the client builds its scene only
## after signon and has nowhere for an RPC to land until it says so.
signal peer_admitted(peer_id: int, player_id: int)

## A player joined or left, or their avatar changed.
signal roster_changed(player_id: int)

## Something worth a line in the feed or a noise. [param kind] is a
## [enum HungryEvents.Kind].
signal cue(kind: int, data: Dictionary)

## Somebody pressed Enter. Server side, and the only thing this bridge does with chat.
##
## [b]The bridge carries chat and decides nothing about it.[/b] Who may say what, on which
## channel, how often and who hears it are [DotChatRouter]'s, and [HungryModule] joins the
## two. A netcode that also held the chat rules would be a netcode somebody had to change
## to add a channel.
signal say_requested(peer_id: int, channel_id: StringName, text: String)

## Somebody typed a vote command. Server side; the token is resolved by a [DotVoteSource].
signal vote_requested(peer_id: int, token: String)

## A voice frame arrived. Server side; the payload has not been parsed and must not be
## trusted — [method DotVoiceRouter.relay] is what stamps the speaker.
signal voice_requested(peer_id: int, payload: PackedByteArray)

## A chat line landed. Client side, for [DotChatClient].
signal chat_received(wire: Dictionary)

## A voice frame landed. Client side, for [DotVoiceManager].
signal voice_arrived(payload: PackedByteArray)

## A hunter's state landed. Client side; see [HungryHunters].
signal hunter_received(state: Dictionary)

## A hazard appeared or is gone. Client side.
signal hazard_received(state: Dictionary)

## Somebody earned something. Client side.
signal progress_received(state: Dictionary)

## The mode vote's cue and countdown second, from [method HungryEvents.read_vote_cue].
## Client side.
signal vote_cue_received(state: Dictionary)

var world: HungryWorld = null

## Where the clock learns how long the link is, in milliseconds. dot-net never
## touches a transport and cannot measure it; dot-server's heartbeat already does
## (`DotClientLink.ping_ms()`), and a client that feeds nothing has a clock that
## assumes an instant connection and stamps every command for a tick the server has
## already simulated. Read on every snapshot.
var rtt_source: Callable = Callable()

var net: DotNetManager = null

var link: HungryNetLink = null

## The schema both ends dress a rider from. Content, delivered like the meshes are.
var avatar_schema: DotAvatarSchema = null

## What a player may bring in. The same schema on both ends, and the whole of what a
## server checks a loadout against.
var loadout_schema: DotLoadoutSchema = null

## `func(player_id: int, loadout: DotLoadout) -> DotResult`. Where a published loadout
## goes. Server side.
##
## A [Callable] rather than a [DotLoadoutManager] reference, because a manager needs a
## store and a store is a deployment decision — a LAN server keeps loadouts in memory, a
## community server puts them behind its own service, and this file has no business
## knowing which. Unset, a published loadout is validated against the schema and applied
## for the session without being saved anywhere, which is what a server with no store
## should do.
var loadout_sink: Callable = Callable()

## What each player is entitled to. Server side.
##
## `func(player_id: int) -> DotLoadoutEntitlements`. Unset, nobody owns anything and only
## items marked free are permitted — which is the safe default and the one that is wrong
## within thirty seconds rather than shipping a game where every unlock is free.
var entitlement_source: Callable = Callable()

## Where this server's cosmetics live, as a manifest URL. Empty for "whatever you
## shipped with", which is every deployment that has not published a pack.
##
## Set on the server by [HungryModule] from a cvar and sent in the hello; set on a client
## from the hello it received. A client with no dot-cloud installed ignores it entirely.
var avatar_pack_url: String = ""

## Which player this process is. Zero on a server.
var local_player_id: int = 0

## The leaderboard as the authority last described it. Client side; rows are
## `{id, mass}`.
var board: Array = []

## Where the replicated entities live. One node, so a scene tree inspector shows the
## netcode's footprint in one place.
var _entities: Node = null

var _match_behaviour: HungryMatchNet = null

var _match_identity: DotNetIdentity = null

## peer id -> player id, and back.
var _player_of_peer: Dictionary = {}

var _peer_of_player: Dictionary = {}

## Peers that have asked for the world, and can therefore receive it.
##
## [b]Nothing is sent to a peer before it asks.[/b] dot-server's signon finishes and
## [i]then[/i] the client builds its scene, so between those two moments the client has no
## node for an RPC to land on — Godot answers every one of them with "Node not found",
## once per call, and the events themselves are simply lost. Waiting for
## [constant HungryEvents.Ask.READY] is the client saying it has somewhere to put them.
var _ready_peers: Dictionary = {}

## Server: peers whose READY came before their seat ([method add_player]). A client sends READY
## when its link says PLAYING, which the link decides itself after sending `loaded` on another
## channel; over ENet with loss the READY can overtake `loaded`, and a READY dropped here left
## that client waiting for a world for ever. Admitted when seated.
var _ready_unseated: Dictionary = {}

## piece id -> [HungryPieceNet].
var _behaviours: Dictionary = {}

## net id -> piece id.
var _piece_of_net: Dictionary = {}

## player id -> the [Dot2DCommand] their last input carried. Server side.
var _commands: Dictionary = {}

var _tick: int = 0

var _world_ticked_for: int = -1

var _client_ticked_for: int = -1

var _board_countdown: int = 0

var _field_dirty: bool = false


## Carries the workbench's profile runtime over this manager (rows down, for a remote admin's panel).
var profile_link: DotNetProfileLink = null

## The workbench's rows, made on first ask: the link must exist before the netcode seals, the workbench after.
var profile_runtime: DotProfileRuntime = null

func ensure_runtime() -> DotProfileRuntime:
	if profile_runtime == null:
		profile_runtime = DotProfileRuntime.new()
		profile_runtime.permit = func(actor: Variant, _flag: String) -> bool:
			return typeof(actor) == TYPE_STRING_NAME and actor == &"local"
	return profile_runtime

func _exit_tree() -> void:
	# The link and the runtime hold each other through broadcast.
	if profile_link != null:
		profile_link.release()
		profile_link = null

func mass_rules() -> Dot2DMassRules:
	var live := _live_world()
	return live.tunables.mass_rules if live != null and live.tunables != null else null

func match_behaviour() -> HungryMatchNet:
	return _match_behaviour


func _send(peer_id: int, payload: PackedByteArray, delivery: int) -> void:
	if link == null:
		return

	if delivery == DotNetMessage.Delivery.UNRELIABLE:
		link.send_snapshot(peer_id, payload)
	elif net.is_server:
		link.send_event(peer_id, payload)
	else:
		link.send_request(payload)

## Sends an event to everybody who can receive one.
##
## Peer by peer rather than [method DotNetManager.send]'s broadcast, because a broadcast
## goes to every connected peer including the ones that have not built their scene yet —
## and every one of those is a "Node not found" in the log and an event nobody got. The
## cost is encoding the body once per peer, which for a reliable event at this scale is
## nothing next to knowing it arrived.
func _broadcast(kind: int, body: PackedByteArray) -> void:
	if net == null or not net.is_server:
		return

	for peer_id in _ready_peers.keys():
		net.send(HungryEvent.new(kind, body), int(peer_id))

## Sends an event to one peer.
##
## [b]A peer id of zero means "nobody", not "everybody".[/b] Bots are players with no
## connection and this game gives them peer 0, so a `_tell` that fell through to
## [method DotNetManager.send]'s broadcast would send every bot's private carry list, and
## every bot's hello, to every real client. Broadcasting is [method _broadcast]'s job and
## it says so.
func _tell(peer_id: int, kind: int, body: PackedByteArray) -> void:
	if net == null or not net.is_server or peer_id <= 0:
		return

	net.send(HungryEvent.new(kind, body), peer_id)

## The world, or null when there isn't one any more.
##
## [b]`world == null` is not the check.[/b] A game change frees the scene the world lives
## in, and a freed [Object] is not null — it is a reference that answers `is_instance_valid`
## with false and throws "Nonexistent function ... in base 'previously freed'" on the next
## call. Every read below can run while a change is in flight: interest management asks for
## a monster while building a snapshot, and the module asks for one while being unloaded.
func _live_world() -> HungryWorld:
	return world if world != null and is_instance_valid(world) else null

func monster_for_peer(peer_id: int) -> HungryMonster:
	var live := _live_world()

	if live == null or not _player_of_peer.has(peer_id):
		return null

	return live.monster_for(int(_player_of_peer[peer_id]))

func player_for_peer(peer_id: int) -> int:
	return int(_player_of_peer.get(peer_id, 0))

## Everybody who has said they can receive. Server side.
##
## [b]The set chat and voice are addressed against, and deliberately not
## [method DotServer.sessions].[/b] A session exists from the moment a socket connects; a
## ready peer is one that has built its scene and can be sent to. Routing a chat line to
## the first is a "Node not found" per recipient and a line nobody got.
func ready_peers() -> PackedInt32Array:
	var out := PackedInt32Array()

	for peer_id in _ready_peers.keys():
		out.append(int(peer_id))

	return out

## Whether a peer has already said it can receive. Server side.
##
## [b]What everything sent on a join has to check.[/b] dot-server's signon finishes and
## *then* the client builds its scene; anything sent in between lands on a node that does
## not exist and is lost, one "Node not found" per call.
func peer_is_ready(peer_id: int) -> bool:
	return _ready_peers.has(peer_id)

## Takes a peer off the broadcast set without touching anything else. Server side.
##
## What a disconnect does first: everything a leave then triggers announces something
## about that person to everybody else, and their socket has already gone.
func mark_not_ready(peer_id: int) -> void:
	_ready_peers.erase(peer_id)

func peer_for_player(player_id: int) -> int:
	return int(_peer_of_player.get(player_id, 0))

func local_monster() -> HungryMonster:
	var live := _live_world()
	return live.monster_for(local_player_id) if live != null else null


func behaviour_for(piece_id: int) -> HungryPieceNet:
	return _behaviours.get(piece_id)

func piece_count() -> int:
	return _behaviours.size()


func _entitlements_for(player_id: int) -> DotLoadoutEntitlements:
	if not entitlement_source.is_valid():
		return DotLoadoutEntitlements.none()

	var owned: Variant = entitlement_source.call(player_id)

	return owned as DotLoadoutEntitlements if owned is DotLoadoutEntitlements \
		else DotLoadoutEntitlements.none()

func describe() -> Dictionary:
	return {
		"server": net.is_server if net != null else false,
		"local_player": local_player_id,
		"peers": _player_of_peer.size(),
		"ready": _ready_peers.size(),
		"pieces": _behaviours.size(),
		"tick": _tick,
		"ticked_for": _world_ticked_for,
		"link": link.describe() if link != null else {},
	}

func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("net      %s, %d peers (%d ready), %d replicated pieces" % [
		"server" if net != null and net.is_server else "client",
		_player_of_peer.size(),
		_ready_peers.size(),
		_behaviours.size(),
	])

	if net != null:
		out.append_array(net.describe_lines())

	return out
