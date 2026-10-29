extends Node

const HungryNetBridge := preload("net/hungry_net_bridge.gd")
const HungryWorld := preload("hungry_world.gd")

## Chat, moderation and voice, wired to this arena's people and this game's wire.

const CHANNEL := "hungry.services"

## Where the chat relay reads its own settings from, when the host assigned none.
const RELAY_CONFIG_PATH := "user://chat_relay.json"

const CHANNEL_ALL := &"all"
const CHANNEL_NEAR := &"near"
const CHANNEL_ADMIN := &"admin"
const CHANNEL_WHISPER := &"whisper"

## How far "near" reaches, in world units.
const NEAR_RANGE := 900.0

const PUNISHMENTS_PATH := "user://hungry_punishments.json"


signal command_entered(peer_id: int, command: String, args: PackedStringArray)


var chat: DotChatRouter = null
var moderation: DotModerationManager = null
var voice: DotVoiceRouter = null
## The website chat relay, when one is configured. See [method _build_relay].
var relay: DotChatRelay = null

## The relay's configuration. Left null, a default is built and the relay stays OFF.
@export var relay_config: DotChatRelayConfig = null

## The backbone client the relay posts through, assigned by the host BEFORE setup.
var backbone: Object = null


var bridge: HungryNetBridge = null
var world: HungryWorld = null
var server: DotServer = null

var service_scope: StringName = &""
var punishments_path: String = PUNISHMENTS_PATH
var punishments_loaded: bool = false


## Builds all three.
func setup() -> DotResult:
	if bridge == null or world == null:
		return DotResult.fail(
			DotError.CODE_STATE, "The services need a bridge and a world."
		)

	# Moderation first, because it is what registers `dot_mute_source` and
	# [method DotChatRouter.start] warns once — and then never again — when there is
	# nothing under that name.
	var punished := _build_moderation()

	if not punished.ok:
		return punished

	var talking := _build_chat()

	if not talking.ok:
		return talking

	# After chat, because it needs the router; not fatal, because a relay that cannot
	# start is a server that still runs a perfectly good match.
	var relayed := _build_relay()
	DotLog.result(CHANNEL, "the website chat relay", relayed)

	return _build_voice()


func _build_moderation() -> DotResult:
	moderation = DotModerationManager.new()
	moderation.name = "Moderation"
	moderation.store = DotPunishmentStoreFile.new(punishments_path)
	# No scope: the unconfigured case is the only case a single-server community is ever
	# in, and it is the one dot-moderation shipped a bug about — a server with no scope
	# saw no scoped punishments and silently enforced nothing.
	moderation.server_scope = ""
	moderation.register_mute_source = true
	moderation.register_ban_source = true
	# Zero means "no immunity to respect", not "the highest rank there is".
	moderation.equal_immunity_may_act = true
	moderation.key_for_peer = _subject_for_peer
	add_child(moderation)

	# A bare statement call: [method DotModerationManager.load_all] is a coroutine only because a store may be an HTTP one; [DotPunishmentStoreFile] is not, so it completes before the next line. It cannot be awaited from a module load; see [method setup].
	moderation.load_all()
	punishments_loaded = true

	return DotResult.success(null)


## Who a peer is, for a punishment: the durable account uid.
func _subject_for_peer(peer_id: int) -> String:
	var session := _session_for(peer_id)

	if session != null:
		return DotPunishmentSubject.for_uid(session.uid())

	var player_id := _player_for(peer_id)
	return DotPunishmentSubject.for_uid("local:%d" % player_id) if player_id != 0 else ""


func _build_chat() -> DotResult:
	chat = DotChatRouter.new()
	chat.name = "Chat"
	chat.rules = chat_rules()
	chat.rules_file = ""
	chat.install_default_channels = false
	chat.handle_me_command = true
	chat.register_as = _scoped(DotChatRouter.SERVICE)
	chat.mute_service = DotModerationManager.MUTE_SERVICE

	chat.send_fn = _send_chat
	chat.peers_fn = _chat_peers
	chat.name_fn = _name_of
	chat.key_fn = _key_of
	chat.position_fn = _position_of
	chat.is_admin_fn = _is_admin

	add_child(chat)

	var started := chat.start()

	if not started.ok:
		return started.wrap("The chat router could not start")

	for channel in chat_channels():
		var added := chat.add_channel(channel)

		if not added.ok:
			return added.wrap("A chat channel was refused")

	chat.command_entered.connect(func(
		peer: int, command: String, args: PackedStringArray, _raw: String
	) -> void:
		command_entered.emit(peer, command, args)
	)

	return DotResult.success(null)


## The four channels. Shared with the client, which builds the same list from this file.
static func chat_channels() -> Array[DotChatChannel]:
	var out: Array[DotChatChannel] = []

	var everyone := DotChatChannel.make(CHANNEL_ALL, "All", DotChatChannel.Scope.EVERYONE)
	everyone.colour = Color(0.93, 0.94, 0.96)
	everyone.backlog = 12
	everyone.history_limit = 200
	out.append(everyone)

	var near := DotChatChannel.make(CHANNEL_NEAR, "Near", DotChatChannel.Scope.RADIUS)
	near.prefix = "[near]"
	near.colour = Color(0.68, 0.83, 0.62)
	near.radius = NEAR_RANGE
	# [b]No backlog on a proximity channel.[/b] A backlog is handed to whoever joins, and
	# a line somebody said quietly in a corner is exactly the line that must not be
	# replayed to a stranger who was not there.
	near.backlog = 0
	near.history_limit = 100
	out.append(near)

	var admin := DotChatChannel.make(CHANNEL_ADMIN, "Admin", DotChatChannel.Scope.EVERYONE)
	admin.prefix = "[ADMIN]"
	admin.colour = Color(0.98, 0.72, 0.35)
	admin.admin_only = true
	admin.ignores_gag = true
	admin.backlog = 0
	out.append(admin)

	var whisper := DotChatChannel.make(
		CHANNEL_WHISPER, "Whisper", DotChatChannel.Scope.DIRECT
	)
	whisper.prefix = "[w]"
	whisper.colour = Color(0.78, 0.71, 0.93)
	whisper.backlog = 0
	out.append(whisper)

	return out


## What a line may be.
static func chat_rules() -> DotChatRules:
	var rules := DotChatRules.new()
	rules.max_length = 140
	rules.refuse_over_length = false
	rules.allow_newlines = false
	rules.escape_markup = true
	rules.strip_invisible = true
	rules.collapse_whitespace = true
	rules.rate_per_minute = 20
	rules.burst = 4.0
	rules.flood_penalty_sec = 8.0
	rules.duplicate_window_sec = 8.0
	rules.duplicate_depth = 3
	rules.command_prefixes = PackedStringArray(["!", "/"])
	rules.broadcast_unknown_commands = false
	rules.history_limit = 300
	return rules


func _send_chat(wire: Dictionary, recipients: PackedInt32Array) -> void:
	if bridge == null:
		return

	# The player id, lifted into the one meta field this game's wire carries, so a client
	# can colour a line by whose it is and put it over the right monster. The key IS the
	# player id — see [method _key_of].
	var addressed := wire.duplicate()
	var player_id := str(wire.get("s", ""))

	if player_id.is_valid_int() and player_id.to_int() > 0:
		addressed["x"] = {"p": player_id.to_int()}

	for peer_id in recipients:
		bridge.send_chat(int(peer_id), addressed)




## Joins this server's chat to its room on the website.
func _build_relay() -> DotResult:
	if relay_config == null:
		relay_config = DotChatRelayConfig.new()

		# Layered: a bare `DotConfig.new()` has only the exported defaults, so the environment and command line would do nothing and the relay could not be turned on by any documented route.
		# Only on the config this builds: a config the host handed over is the host's.
		var layered := relay_config.load_layered(RELAY_CONFIG_PATH)
		if not layered.ok:
			DotLog.warn(CHANNEL, "the chat relay configuration is not usable", {
				"why": str(layered.error),
			})
			return DotResult.success(null)

	if not relay_config.enabled:
		return DotResult.success(null)

	if backbone == null:
		# Found, not handed over: a backbone client is built by whatever owns the server's credential, after or before this module loads, so `DotBackboneClient` publishes itself under this name.
		backbone = DotRegistry.get_service(&"dot_backbone_client")

	if backbone == null:
		# Info and success, not a failure: a fleet-wide `DOT_CHAT_RELAY_ENABLED=1` with a credential for only some hosts is ordinary, and a red line on every boot of the others stops real ones being read.
		# The line names what to do.
		DotLog.info(
			CHANNEL,
			"the chat relay is on but there is no backbone client, so it will not start",
			{"fix": "put a server-scoped integration token in the listing configuration"}
		)
		return DotResult.success(null)

	relay = DotChatRelay.new()
	relay.name = "ChatRelay"
	relay.router = chat
	relay.config = relay_config
	relay.client = backbone
	relay.permission_fn = _uid_has_permission
	relay.command_fn = _run_relayed_command
	relay.commands_fn = _relay_command_document

	add_child(relay)

	var started := relay.start()

	if not started.ok:
		remove_child(relay)
		relay.queue_free()
		relay = null
		return started

	relay.site_command.connect(_on_site_command)

	# [b]Tell the clients.[/b] A player whose lines already reach a page they are looking
	# at does not need a chat box in front of the game, and a player whose lines reach
	# nothing but this server needs one badly. Only the server knows which.
	if server != null and server.chat != null:
		server.chat.watch_relay(relay)

	return DotResult.success(relay)


func _uid_has_permission(uid: String, flag: String) -> bool:
	if server == null or server.admins == null:
		return false
	return server.admins.uid_has_permission(uid, flag)


func _run_relayed_command(
	uid: String, command: String, args: PackedStringArray, source: int
) -> void:
	if server == null:
		return

	for reply in server.run_command_as_uid(uid, command, args, source):
		DotLog.info(CHANNEL, "relayed command reply", {"uid": uid, "line": reply})


func _on_site_command(uid: String, command: String, allowed: bool) -> void:
	# Audited either way. A refusal is the half worth having a record of: it is somebody
	# trying to drive the server from a web page without the rights to.
	if server != null and server.audit != null:
		server.audit.record(
			"relay_command", "web:%s" % uid, command, {"allowed": allowed}
		)



func _build_voice() -> DotResult:
	var config := voice_config()
	var problem := config.validate()

	if not problem.ok:
		return problem.wrap("The voice configuration is not usable")

	voice = DotVoiceRouter.new()
	voice.name = "Voice"
	voice.config = config
	# Proximity, where this game and the lobby part company: an arena is bigger than a screen, hearing somebody creeping up is information, and hearing the whole server is noise.
	voice.default_channel = DotVoiceRouter.Channel.PROXIMITY
	voice.proximity_range = config.proximity_range
	voice.max_bytes_per_second = config.max_bytes_per_second
	voice.send_fn = _send_voice
	voice.position_fn = _position_of

	add_child(voice)

	return DotResult.success(null)


## The voice format, which both ends must agree on exactly.
static func voice_config() -> DotVoiceConfig:
	var config := DotVoiceConfig.new()
	config.sample_rate = 16000
	config.frame_ms = 20.0
	config.codec_id = &"adpcm"
	config.push_to_talk = true
	config.activation_rms = 0.02
	config.hangover_ms = 250.0
	config.jitter_ms = 60.0
	config.jitter_max_ms = 400.0
	config.proximity_range = NEAR_RANGE
	config.max_bytes_per_second = 6144
	return config


func _send_voice(peer_id: int, payload: PackedByteArray) -> void:
	if bridge != null and bridge.link != null:
		bridge.link.send_voice(peer_id, payload)



func add_peer(peer_id: int) -> void:
	if voice != null:
		voice.add_peer(peer_id)


func remove_peer(peer_id: int) -> void:
	if voice != null:
		voice.remove_peer(peer_id)

	if chat != null:
		# The rate limiter's and the repeat detector's memory of this peer. Without this a
		# reconnecting player inherits whatever the last holder of that peer id had been
		# saying, and is told they are repeating themselves on their first line.
		chat.forget(peer_id)


func _chat_peers() -> PackedInt32Array:
	return bridge.ready_peers() if bridge != null else PackedInt32Array()


func _session_for(peer_id: int) -> DotClientSession:
	return server.session_of(peer_id) if server != null else null


func _player_for(peer_id: int) -> int:
	return bridge.player_for_peer(peer_id) if bridge != null else 0


func _name_of(peer_id: int) -> String:
	var session := _session_for(peer_id)

	if session != null:
		return session.display_name

	var monster := world.monster_for(_player_for(peer_id)) if world != null else null
	return monster.display_name if monster != null else "player %d" % peer_id


## The key a chat line is attributed to: the speaker's player id.
func _key_of(peer_id: int) -> String:
	var player_id := _player_for(peer_id)
	return str(player_id) if player_id != 0 else ""


## Where somebody is, as dot-chat and dot-voice both ask for it.
func _position_of(peer_id: int) -> Vector3:
	if world == null:
		return Vector3.ZERO

	var monster := world.monster_for(_player_for(peer_id))

	# `alive` rather than a piece count: being eaten means having nothing, and a dead player is a spectator with no position.
	# They can still hear the room channel but must not be heard from where their monster died.
	if monster == null or not monster.alive:
		return Vector3.ZERO

	var at := monster.centre()
	return Vector3(at.x, at.y, 0.0)


func _is_admin(peer_id: int) -> bool:
	var session := _session_for(peer_id)
	return session != null and session.is_admin()


func _scoped(base: StringName) -> StringName:
	return base if service_scope == &"" else StringName("%s:%s" % [base, service_scope])


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	if chat != null:
		out.append_array(chat.describe_lines())

	if voice != null:
		out.append_array(voice.describe_lines())

	if moderation != null:
		out.append_array(moderation.describe_lines())
		out.append("punishments  %s" % (
			"loaded" if punishments_loaded else "STILL LOADING — nothing is enforced"
		))

	return out


## What this server accepts, for the site's `/` menu.
func _relay_command_document() -> Array[Dictionary]:
	if server == null or server.console == null:
		return []
	return server.console.command_document(relay_config.command_source as DotCmdContext.Source)
