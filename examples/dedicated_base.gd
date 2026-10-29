extends "exit_probe.gd"

const HungryBrowser := preload("../game/client/hungry_browser.gd")
const HungryContent := preload("../game/hungry_content.gd")
const HungryEvents := preload("../game/net/hungry_events.gd")
const HungryHunters := preload("../game/hungry_hunters.gd")
const HungryInterest := preload("../game/net/hungry_interest.gd")
const HungryLayout := preload("../game/hungry_layout.gd")
const HungryMaps := preload("../game/hungry_maps.gd")
const HungryModule := preload("../game/hungry_module.gd")
const HungryMonster := preload("../game/hungry_monster.gd")
const HungryNetLink := preload("../game/net/hungry_net_link.gd")
const HungryPreset := preload("../game/hungry_preset.gd")
const HungryProgress := preload("../game/hungry_progress.gd")
const HungryServices := preload("../game/hungry_services.gd")
const HungryTuning := preload("../game/hungry_tuning.gd")
const HungryWorld := preload("../game/hungry_world.gd")

const PORT := 27081
const SERVER_DIR := "user://hungry_dedicated"

## The app's URL segment on the website (this game's code name); display only, never proof.
const APP_URL := "hungario"
var _server: DotServer = null


## Sections entered, and sections that ran to their last line.
## A check count is not coverage: a section that aborts stops adding checks silently.
var _entered := 0
var _completed := 0


## Opens a section. Pair with [method _done] on every path out of it.
func _section(title: String) -> void:
	_entered += 1
	print("")
	print(title)


func _done() -> void:
	_completed += 1


## Waits for a condition, or gives up; returns whether it happened.
## A deadline, not a frame count: how long the module takes depends on machine load.
func _until(condition: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)

	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true

		await get_tree().physics_frame

	return false


func _module() -> HungryModule:
	return _server.modules.get_module("hungry") as HungryModule


func _world() -> HungryWorld:
	return DotRegistry.get_node_service(HungryWorld.SERVICE) as HungryWorld


func _build(serving: bool) -> bool:
	print("booting")

	var config := DotServerConfig.new()
	config.hostname = "hungry dedicated"
	config.port = PORT
	config.bind_address = "127.0.0.1" if not serving else "0.0.0.0"
	config.rcon_password = ""
	config.admins_path = "%s/admins.json" % SERVER_DIR
	config.bans_path = "%s/bans.json" % SERVER_DIR
	config.audit_log_path = "%s/audit.jsonl" % SERVER_DIR
	config.hibernate_when_empty = false
	# The addon ships a default `server.cfg` that the search path would find, which is
	# correct layering and would make this test assert against whatever that file says.
	config.startup_config = ""
	config.autoexec_config = ""
	# The query listeners are on by default on a real server; named here so a suite that
	# stopped exercising them fails rather than skipping.
	config.query_enabled = true
	config.query_port = PORT + 1
	# A self-test takes no commands, and a console reader blocked on an open stdin pipe keeps the
	# process from ever exiting (the exit probe's copy held such a pipe). `--serve` keeps it.
	config.stdin_console_enabled = serving

	_server = DotServer.new()
	_server.name = "Server"
	_server.config = config
	_server.config_file = ""
	_server.auto_boot = false
	add_child(_server)

	# Answering a query is its own addon, and a server only answers if a host is plugged
	# in. Added before boot() so the listener opens with everything else.
	var query_host := DotQueryHost.new()
	query_host.name = "QueryHost"
	query_host.app_url = APP_URL
	query_host.server_ref = DotNodeRef.of_path(NodePath("../Server"))
	add_child(query_host)

	var booted: DotResult = await _server.boot()

	if not _check(booted.ok, "the server boots and listens on %d" % PORT, str(booted.error)):
		return false

	# Both modes are registered before the first one is loaded, because
	# [DotGameManager.change_game] can only change to a game it already knows about and
	# the module cannot load until there is a world for it to bind to.
	for descriptor in HungryModule.game_descriptors():
		_server.games.add_game(descriptor)

	var loaded: DotResult = await _server.games.change_game(
		HungryModule.GAME_CLASSIC, "boot"
	)

	if not _check(loaded.ok, "the classic mode loads", str(loaded.error)):
		return false

	# Into this run's own directory, which is deleted on the way in and out. The default is
	# the store a `--serve` of this same scene enforces, and a self-test gag written there
	# is a real record against a real (if made-up) uid.
	if not serving:
		HungryModule.punishments_path = "%s/punishments.json" % SERVER_DIR

	var module: DotResult = await _server.modules.load_module(
		"res://game/hungry_module.gd"
	)
	return _check(module.ok, "and the module loads into it", str(module.error))


func _teardown() -> void:
	if _server == null or not is_instance_valid(_server):
		return

	_server.shutdown("test over")
	remove_child(_server)

	# Freed, not queued: a queue_free on the last line before `quit()` never happens, and every
	# node under it is then reported leaked at exit.
	_server.free()
## Whether every piece of [param monster] has [param property] at [param want] on the
## entity the netcode sends — and, for the beacon, whether each is always relevant to match,
## because the two are one decision and a beacon without the relevance fails far away.
func _pieces_carry(monster: HungryMonster, property: String, want: bool) -> bool:
	if monster.piece_count() == 0:
		return false

	for piece in monster.pieces:
		if piece.net == null or bool(piece.net.get(property)) != want:
			return false

		if property == "net_beacon":
			var identity := piece.net.get("identity") as DotNetIdentity
			if identity == null or identity.always_relevant != want:
				return false

	return true


func _live(line: String) -> PackedStringArray:
	var captured: Array[String] = []
	var context := DotCmdContext.console("", PackedStringArray())
	context.reply_sink = func(text: String) -> void: captured.append(text)
	_server.console.execute(line, context)
	await get_tree().process_frame
	await get_tree().process_frame
	return PackedStringArray(captured)


func _said_any(lines: PackedStringArray, text: String) -> bool:
	for line in lines:
		if line.findn(text) >= 0:
			return true
	return false
func _line_with(text: String, needle: String) -> String:
	for line in text.split("\n"):
		if line.contains(needle):
			return line.strip_edges()
	return ""


func _last_lines(text: String, count: int) -> String:
	var lines := text.strip_edges().split("\n")
	return "\n".join(lines.slice(maxi(0, lines.size() - count)))


func _exit_probe_scene() -> String:
	return "res://examples/dedicated.tscn"
