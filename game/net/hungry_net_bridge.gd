extends "res://game/net/hungry_net_bridge_server.gd"

## Binds a world and a manager to each other and puts the link where RPCs will find it.
##
## [param link_parent] is [DotServer] on a server and [DotClientLink] on a client, and
## both of them are named [code]Server[/code] — see [HungryNetLink] for why that is the
## whole of the routing.
func attach(
	p_world: HungryWorld,
	p_net: DotNetManager,
	link_parent: Node
) -> DotResult:
	if p_world == null or p_net == null or link_parent == null:
		return DotResult.fail(DotError.CODE_INVALID, "A bridge needs all three.")

	if p_world.is_authority != p_net.is_server:
		# A world that thinks it is authoritative behind a client manager would resolve
		# its own eating; a server whose world is not authoritative would resolve
		# nobody's. Both are silent, and both are unplayable.
		return DotResult.fail(
			DotError.CODE_STATE,
			"The world and the manager disagree about who is authoritative.",
			"world.is_authority=%s, net.is_server=%s"
				% [p_world.is_authority, p_net.is_server]
		)

	world = p_world
	net = p_net
	avatar_schema = HungryContent.avatar_schema()

	var schema_valid := avatar_schema.validate_schema()

	if not schema_valid.ok:
		return schema_valid.wrap("The rider schema is not usable")

	loadout_schema = HungryContent.loadout_schema()

	var loadout_valid := loadout_schema.validate()

	if not loadout_valid.ok:
		return loadout_valid.wrap("The loadout schema is not usable")

	_entities = Node.new()
	_entities.name = "Entities"
	add_child(_entities)

	var interest := HungryInterest.new()
	interest.bridge = self
	net.interest = interest

	# Snapshots and messages both leave through `send_fn`, and the only thing that
	# distinguishes them there is the delivery: dot-net sends state unreliably and
	# nothing else, and every message this game defines is reliable. Routing on that is
	# exact rather than a heuristic, and it is why neither message type may ever be
	# declared unreliable.
	net.send_fn = _send
	profile_link = DotNetProfileLink.attach(net, ensure_runtime())

	var registered := _register_messages()

	if not registered.ok:
		return registered

	if net.is_server:
		_connect_world()

	link = HungryNetLink.attached_to(self, net.is_server)
	# Not link_parent.add_child: the link sits under the server (RPCs route by path) but must
	# die with this bridge. A bare add_child left a second link after a module reload and
	# Godot renamed the live one `@Node@n`, so RPCs to clients were lost. DotGameLink frees it
	# with the bridge without remove_child, which errors on a busy parent.
	DotGameLink.attach(link, link_parent, self, HungryNetLink.NODE_NAME)

	if net.is_server:
		var built := _build_match_entity()

		if not built.ok:
			return built

	return DotResult.success(self)

## Moves this bridge onto a new world, keeping every connection. Server side.
##
## [b]What a game change is, from the netcode's point of view.[/b] The world is a scene
## that [DotGameManager] frees and replaces; the manager, its peers, its message ids and
## its clock are not, because rebuilding those would disconnect everybody — which is
## precisely what changing the map is supposed to avoid.
##
## So every replicated piece is despawned, the new world is populated with the same
## players, and everyone is resynchronised. The [i]match entity survives[/i]: its net id is
## already known to every client and re-spawning it would make each of them mirror a
## second one.
func rebind(new_world: HungryWorld) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server rebinds.")

	if new_world == null or not new_world.is_authority:
		return DotResult.fail(
			DotError.CODE_INVALID, "A bridge rebinds onto an authoritative world."
		)

	# Who is here, before the old world goes. The peer map survives a game change; the
	# monsters do not, and their names and avatars are the only thing in them worth
	# carrying across.
	var carried: Array[Dictionary] = []

	for peer_key in _player_of_peer.keys():
		var peer_id := int(peer_key)
		var player_id := int(_player_of_peer[peer_key])
		var monster := world.monster_for(player_id) if world != null else null

		carried.append({
			"peer": peer_id,
			"player": player_id,
			"name": monster.display_name if monster != null else "Player %d" % player_id,
			"avatar": monster.avatar if monster != null else null,
		})

	for piece_id in _behaviours.keys():
		_release_piece_entity(int(piece_id), true)

	_behaviours.clear()
	_commands.clear()

	if world != null:
		_disconnect_world()

	world = new_world
	_connect_world()

	if _match_behaviour != null:
		_match_behaviour.world = world

	for row in carried:
		var added := world.add_player(int(row["player"]), String(row["name"]))

		if not added.ok:
			continue

		var monster: HungryMonster = added.value
		var avatar: Variant = row["avatar"]

		if avatar is DotAvatar:
			monster.avatar = avatar

		var peer_id := int(row["peer"])

		if _ready_peers.has(peer_id):
			_send_hello(peer_id, int(row["player"]))
			_send_roster(peer_id)
			_send_full_field(peer_id)

		world.spawn(int(row["player"]))

	_world_ticked_for = -1
	return DotResult.success(world)

func _connect_world() -> void:
	world.piece_created.connect(_on_piece_created)
	world.piece_destroyed.connect(_on_piece_destroyed)
	world.field_changed.connect(_on_field_changed)
	world.projectile_thrown.connect(_on_projectile_thrown)
	world.projectile_impact.connect(_on_projectile_impact)
	world.monster_burst.connect(_on_monster_burst)
	world.player_died.connect(_on_player_died)
	world.item_taken.connect(_on_item_taken)
	world.match_state_changed.connect(_on_match_state_changed)

func _disconnect_world() -> void:
	for pair in [
		[world.piece_created, _on_piece_created],
		[world.piece_destroyed, _on_piece_destroyed],
		[world.field_changed, _on_field_changed],
		[world.projectile_thrown, _on_projectile_thrown],
		[world.projectile_impact, _on_projectile_impact],
		[world.monster_burst, _on_monster_burst],
		[world.player_died, _on_player_died],
		[world.item_taken, _on_item_taken],
		[world.match_state_changed, _on_match_state_changed],
	]:
		var source: Signal = pair[0]
		var handler: Callable = pair[1]

		if source.is_connected(handler):
			source.disconnect(handler)

## Unregisters and frees one piece's entity. Returns its net id, or zero.
func _release_piece_entity(piece_id: int, announce: bool) -> int:
	var behaviour: HungryPieceNet = _behaviours.get(piece_id)

	if behaviour == null or behaviour.identity == null:
		return 0

	var net_id := behaviour.identity.net_id
	_piece_of_net.erase(net_id)

	if announce:
		_broadcast(HungryEvents.Kind.DESPAWN, HungryEvents.write_despawn(net_id))

	net.registry.unregister(net_id)

	var node := behaviour.identity.entity

	if node != null and is_instance_valid(node):
		node.queue_free()

	return net_id

func _register_messages() -> DotResult:
	var event := net.messages.register(
		HungryEvent.NAME,
		HungryEvent,
		DotNetMessage.Delivery.RELIABLE,
		DotNetMessage.Direction.TO_CLIENT
	)

	if not event.ok:
		return event

	var request := net.messages.register(
		HungryRequest.NAME,
		HungryRequest,
		DotNetMessage.Delivery.RELIABLE,
		DotNetMessage.Direction.TO_SERVER
	)

	if not request.ok:
		return request

	net.messages.on(HungryEvent.NAME, _on_event)
	net.messages.on(HungryRequest.NAME, _on_request)
	return DotResult.success(true)

## The always-relevant entity that carries the match clock.
##
## Also the thing that keeps an empty server ticking: with no players there are no piece
## entities, no behaviour runs, and the warmup of a freshly booted server would never end.
func _build_match_entity() -> DotResult:
	var root := Node2D.new()
	root.name = "Match"
	_entities.add_child(root)

	_match_behaviour = HungryMatchNet.new()
	_match_behaviour.name = "Net"
	_match_behaviour.world = world
	_match_behaviour.bridge = self
	root.add_child(_match_behaviour)

	# After the behaviour: [DotNetIdentity] collects behaviours in `_ready` by walking the
	# entity's subtree, and one added afterwards would never be found — the entity would
	# register with nothing to replicate and simply never update on any other machine.
	_match_identity = DotNetIdentity.new()
	_match_identity.name = "Identity"
	_match_identity.owner_peer_id = net.local_peer_id
	_match_identity.always_relevant = true
	_match_identity.priority = 10.0
	root.add_child(_match_identity)

	return net.registry.register(_match_identity, 0, net.clock.tick, net.config)

## Adds a player and makes their pieces replicated entities. Server side.
##
## [param session_id] is the id everything downstream uses — the scoreboard key, the
## monster's identity, the colour seed. [b]It is not the peer id.[/b] A peer id is
## reassigned the moment somebody reconnects, and everything keyed by one would be handed
## to the next player to join.
func add_player(
	peer_id: int,
	session_id: int,
	display_name: String,
	avatar: DotAvatar = null
) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server adds players.")

	var added := world.add_player(session_id, display_name)

	if not added.ok:
		return added

	var monster: HungryMonster = added.value

	if avatar != null:
		monster.avatar = avatar

	# Before anything is registered to it, not after: the manager only builds snapshots
	# for peers it knows about and only holds an input buffer for those, so an entity
	# registered to an unknown peer is one nothing is ever sent about and nothing can
	# drive. It is silent — the server simulates it perfectly and alone.
	#
	# A bot has no connection and arrives with peer 0. Registering that as a peer would
	# give the manager a peer whose snapshots go to the broadcast address, so every real
	# client would receive a second snapshot built against the bot's interest rectangle
	# — a client's own view then arrives interleaved with somebody else's, and the
	# symptom is a monster that jumps between two positions.
	if peer_id > 0:
		_player_of_peer[peer_id] = session_id
		_peer_of_player[session_id] = peer_id

	_announce(monster)
	world.spawn(session_id)
	roster_changed.emit(session_id)

	if peer_id > 0 and _ready_unseated.has(peer_id):
		_ready_unseated.erase(peer_id)
		_admit(peer_id, session_id)

	return DotResult.success(monster)

## Drops a peer's player from the world and from replication. Server side.
func remove_peer(peer_id: int) -> void:
	_ready_unseated.erase(peer_id)

	if not _player_of_peer.has(peer_id):
		return

	var session_id := int(_player_of_peer[peer_id])
	_player_of_peer.erase(peer_id)
	_peer_of_player.erase(session_id)
	_ready_peers.erase(peer_id)
	_commands.erase(session_id)

	# Before the world removes their pieces, so `piece_destroyed` still finds the
	# behaviours and every client is told each entity is gone.
	#
	# [b]Guarded, because the world may already be gone.[/b] A game change frees the scene
	# the world lives in and THEN the module that owned it is unloaded — and unloading is
	# what takes everybody out. So on the way out of hungry this ran against a freed
	# HungryWorld: "Invalid call. Nonexistent function 'remove_player' in base 'previously
	# freed'", and with a real client attached and different timing, a segfault.
	#
	# The rest of the teardown still has to happen: the peer's entities, its input buffer
	# and its acknowledgement record are the netcode's and outlive the scene. Returning
	# early here would leak all three into the next game.
	var live := _live_world()

	if live != null:
		live.remove_player(session_id)

	if net != null:
		# [b]Asked of the manager, not of `_ready_peers`.[/b] A real disconnect calls
		# [method mark_not_ready] first, so by the time it gets here the ready set no longer
		# has the peer — and gating on it skipped this on every disconnect there was. The
		# manager kept the peer, built it a snapshot every interval and sent it to a socket
		# that had gone: "Attempt to call RPC with unknown peer ID", once per snapshot, for
		# the life of the server. `_admit` is the only place a peer joins the manager, so
		# the manager's own list is the one that says whether there is anything to release.
		if net.peers().has(peer_id):
			# Releases the peer's remaining entities, its input buffer and its
			# acknowledgement record in one place, so nothing is left keyed by a peer id
			# the next player to connect will be given.
			net.remove_peer(peer_id)

		net.interest.forget_peer(peer_id)

	_broadcast(HungryEvents.Kind.LEAVE, HungryEvents.write_player(session_id))
	roster_changed.emit(session_id)

func _on_piece_created(piece: HungryPiece) -> void:
	var identity := _build_piece_entity(piece, peer_for_player(piece.owner_id))
	var registered := net.registry.register(identity, 0, net.clock.tick, net.config)

	if not registered.ok:
		DotLog.error(CHANNEL, "could not register a piece", {
			"piece": piece.id, "error": str(registered.error)
		})
		return

	_piece_of_net[identity.net_id] = piece.id

	# Immediately, and reliably. A client that meets an entity it has not been told to
	# spawn abandons the rest of that snapshot — it cannot skip a variable-length body
	# without the declarations — so a spawn that arrived late would cost every other
	# entity in that packet as well.
	_broadcast(
		HungryEvents.Kind.SPAWN,
		HungryEvents.write_spawn(
			identity.net_id,
			identity.owner_peer_id,
			piece.owner_id,
			piece.id,
			piece.position(),
			piece.mass()
		)
	)

func _on_piece_destroyed(piece: HungryPiece) -> void:
	_release_piece_entity(piece.id, true)
	_behaviours.erase(piece.id)

## One authoritative tick. Server side, and it replaces [method HungryWorld.tick].
##
## [method DotNetManager.server_tick] hands each peer's input to the entities it owns,
## simulates every behaviour, records history and sends snapshots — in that order, and
## the world tick has to happen between the first two. It does, from
## [method HungryPieceNet._net_simulate] and [method HungryMatchNet._net_simulate],
## through [method ensure_world_ticked].
##
## The call afterwards is not redundant. It is what covers the tick on which the match
## entity has not yet been registered, and it costs one integer comparison when the
## world has already run.
func server_tick(tick: int) -> void:
	_tick = tick
	_world_ticked_for = -1

	if net != null:
		net.server_tick(tick)

	ensure_world_ticked(tick)
	_flush_field()
	_flush_board(tick)

## Runs the whole world for a tick, at most once.
##
## Called from every replicated behaviour's [code]_net_simulate[/code]; the first one
## through does the work and the rest find it done.
func ensure_world_ticked(tick: int) -> void:
	var live := _live_world()

	if _world_ticked_for == tick or live == null:
		return

	_world_ticked_for = tick
	live.tick(_commands)

## Takes one tick of a player's intent, on its way from an input packet to the world.
##
## Kept per player rather than per piece: a monster's command belongs to the monster, and
## sixteen pieces each holding their own copy of it is fifteen chances for them to
## disagree.
func note_command(player_id: int, command: Dot2DCommand) -> void:
	if command != null:
		_commands[player_id] = command


## Takes one input packet. Server side.
##
## The acknowledgement is applied even when the command is refused: they are independent
## claims, and a duplicate or late input says nothing about which snapshots arrived.
func receive_input(peer_id: int, payload: PackedByteArray) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server takes input.")

	if not _player_of_peer.has(peer_id):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "That peer has no player.")

	if payload.size() <= ACK_BYTES:
		return DotResult.fail(DotError.CODE_PARSE, "Input packet is too short.")

	net.receive_ack_payload(peer_id, payload.slice(0, ACK_BYTES))

	# A batch: this tick's command and the ones before it (see [constant INPUT_COPIES]).
	# Copies of ticks already simulated are skipped rather than pushed, or each would count
	# as a late input; the packet's own tick is always pushed, so a late one still counts.
	var batch := DotNetInput.read_batch(
		DotNetReader.new(payload.slice(ACK_BYTES)),
		func() -> DotNetInput: return HungryNetCommand.new()
	)
	if batch.is_empty():
		return DotResult.fail(DotError.CODE_PARSE, "Input packet carries no command.")
	var buffer := net.input_buffer_for(peer_id)
	var newest := batch[batch.size() - 1]
	var pushed := DotResult.success(false)
	for input in batch:
		if input != newest and input.tick <= buffer.last_consumed_tick():
			continue
		pushed = buffer.push(input)
	return pushed

## A voice frame off [method HungryNetLink.send_voice], in whichever direction this is.
##
## [b]Not a [HungryEvent].[/b] Voice is fifty packets a second and every HungryEvent is
## reliable, so a talk spurt would put a hundred retransmittable messages in front of a
## spawn. It also does not go through [DotNetManager]: the registry seals a message set and
## hashes it, and adding a fifty-hertz opaque blob to that buys nothing — the packet has
## its own header, its own sequence and its own validation in [DotVoicePacket].
func receive_voice(peer_id: int, payload: PackedByteArray) -> DotResult:
	if payload.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "An empty voice frame.")

	if net != null and net.is_server:
		if peer_id <= 0 or not _player_of_peer.has(peer_id):
			# A peer with nobody in the arena. Refused rather than relayed: the router
			# stamps the speaker from this id, so relaying one that belongs to nobody
			# puts a voice in the game with no name on it.
			return DotResult.fail(
				DotError.CODE_FORBIDDEN, "That peer has nobody in the game."
			)

		voice_requested.emit(peer_id, payload)
		return DotResult.success(null)

	voice_arrived.emit(payload)
	return DotResult.success(null)

func receive_event(payload: PackedByteArray) -> DotResult:
	if net == null:
		return DotResult.fail(DotError.CODE_STATE, "No manager.")

	return net.receive(payload, 1)

func receive_request(peer_id: int, payload: PackedByteArray) -> DotResult:
	if net == null:
		return DotResult.fail(DotError.CODE_STATE, "No manager.")

	return net.receive(payload, peer_id)


