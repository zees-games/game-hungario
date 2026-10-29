extends "dedicated_vote.gd"

## A real [DotServer] with the game loaded, listening for browser clients; exits non-zero on failure.
## [code]godot --headless --path . res://examples/dedicated.tscn[/code], plus `-- --serve` to run one.
## It connects no client ([code]sandbox[/code] does); the point is the WebSocket listener browsers need.

const CHECKS := 263


func _ready() -> void:
	# Quiet by default so the checks are readable; `-- --verbose` when one of them
	# fails and the reason is in a log line rather than in the assertion.
	DotLog.set_level(
		DotLog.Level.DEBUG if "--verbose" in OS.get_cmdline_user_args()
		else DotLog.Level.ERROR
	)
	_run.call_deferred()


func _run() -> void:
	var serving := "--serve" in OS.get_cmdline_user_args()

	print("game-hungario dedicated server")
	print("")

	var probe: Array = []
	if not (serving or _is_exit_probe()):
		probe = await _run_exit_probe()

	if not serving:
		DotPaths.remove_tree(SERVER_DIR)

	var built := await _build(serving)

	if serving:
		if built:
			print("")
			print("listening on ws://0.0.0.0:%d — ctrl-c to stop" % PORT)
			for line in _server.status_lines():
				print("  %s" % line)
		return

	if built:
		_test_world()
		_test_module()
		_test_commands()
		await _test_bots()
		# Awaited: a suspending section called without `await` drops everything after its first
		# suspension, including its own `_done()`; the completion count at the end catches that.
		await _test_loadouts()
		_test_reporting()
		await _test_stats()
		_test_netcode()
		_test_services()
		await _test_moderation()
		await _test_live_tools()
		await _test_disconnect()
		_test_combat()
		_test_hunters()
		_test_hunters_hunt()
		_test_hazards()
		await _test_progress()
		_test_query()
		_test_vote()
		_test_rotation_file()
		_test_finish_round_waits_for_a_live_round()
		await _test_game_change()
		_test_transport()
		_test_unload()
		_test_no_message_preloads_itself()

	if not probe.is_empty():
		_test_exits_clean(probe)

	_teardown()
	DotPaths.remove_tree(SERVER_DIR)

	print("")
	_check(
		_completed == _entered,
		"every section ran to its last line (%d of %d)" % [_completed, _entered],
		"a section that aborted stops adding checks and the total cannot show it"
	)

	_report(CHECKS - (EXIT_PROBE_CHECKS if _is_exit_probe() else 0))


## The server half of this game's own server browser, asked by a real [DotServer] running it.
func _test_query() -> void:
	_section("the server browser's half")

	var module := _module()

	if module == null:
		_done()
		return

	_check(_server.query_source != null, "the server has a query source to contribute to")

	var snapshot := DotQuerySnapshot.new()

	for provider in module._query_providers:
		provider.call("_contribute", snapshot)

	_check(snapshot.game.has("mode"), "the query says which mode is being played")
	_check(snapshot.game.has("map"), "and what a player would call the map")
	_check(snapshot.game.has("state"), "and how far through the round it is")
	_check(
		String(snapshot.game.get("mode", "")) == String(_world().preset.id),
		"and the mode it names is the one that is running",
		str(snapshot.game.get("mode", ""))
	)
	# The two cvars that make this a different server. A list that cannot show them sends
	# somebody into a game about being hunted when they wanted a game about eating.
	_check(snapshot.game.has("hunters"), "and whether hunters are on")
	_check(
		int(snapshot.game.get("players", -1)) == module._joined.size(),
		"the player count is the module's own rather than a second tally",
		str(snapshot.game.get("players", -1))
	)

	# The client half's other source: the site's listing, off unless a site is named.
	var env_key := "DOT_BROWSER_BACKBONE_URL"
	var had := OS.get_environment(env_key)
	OS.unset_environment(env_key)
	var off: DotResult = HungryBrowser.site_listing()
	_check(off.ok and off.value == null, "the browser reads no site listing when none is configured")

	OS.set_environment(env_key, "http://127.0.0.1:9")
	var on: DotResult = HungryBrowser.site_listing()
	var listing: DotBrowserSourceBackbone = on.value if on.ok else null
	_check(listing != null, "and does when one is", str(on.error) if not on.ok else "")
	_check(
		listing != null and listing.config.page_url(1).contains("app=hungario"),
		"asking for this game's servers",
		listing.config.page_url(1) if listing != null else ""
	)
	_test_query_site(env_key, had)
	_done()


func _test_query_site(env_key: String, had: String) -> void:
	# Where the site comes from with no flag: web ?backbone= > page origin; native argv > env >
	# exported default. Each result is one a reversed order gets wrong.
	OS.unset_environment(env_key)
	var web_both := HungryBrowser.resolve_default_site({
		"web": true, "origin": "https://site.example", "query": "https://other.example"
	})
	_check(web_both == "https://other.example", "on the web ?backbone= beats the page origin", web_both)
	var web_origin := HungryBrowser.resolve_default_site({"web": true, "origin": "https://site.example", "query": ""})
	_check(web_origin == "https://site.example", "and with no query the page's own origin is the site", web_origin)
	var web_file := HungryBrowser.resolve_default_site({"web": true, "origin": "null", "query": ""})
	_check(web_file == "", "and a page with no usable origin lists no site", web_file)
	var web_listing: DotResult = HungryBrowser.site_listing({"web": true, "origin": "https://site.example", "query": ""})
	_check(
		web_listing.ok and web_listing.value != null
			and web_listing.value.config.page_url(1).begins_with("https://site.example/api/content/server/list")
			and web_listing.value.config.page_url(1).contains("app=hungario"),
		"so a web client lists its own site's servers without a flag"
	)
	var saved_default := HungryBrowser.default_backbone_url
	HungryBrowser.default_backbone_url = "https://deploy.example"
	var native_default := HungryBrowser.resolve_default_site({"web": false, "origin": "https://site.example", "query": "https://other.example"})
	_check(native_default == "https://deploy.example", "on native the exported default is used and the page is never asked", native_default)
	OS.set_environment(env_key, "http://127.0.0.1:9")
	var env_wins: DotResult = HungryBrowser.site_listing({"web": false})
	_check(
		env_wins.ok and env_wins.value != null and env_wins.value.config.backbone_url == "http://127.0.0.1:9",
		"and the environment beats that default",
		str(env_wins.value.config.backbone_url) if env_wins.ok and env_wins.value != null else str(env_wins.error)
	)
	HungryBrowser.default_backbone_url = saved_default
	if had != "":
		OS.set_environment(env_key, had)
	else:
		OS.unset_environment(env_key)

## A browser client needs a WebSocket listener, and this build has to be able to make one.
func _test_transport() -> void:
	_section("browser clients")

	var transport := DotTransportWebSocket.new()
	_check(transport != null, "dot-core can build a WebSocket transport")
	_check(
		transport.supports_web_clients(),
		"which is the one browser clients can reach"
	)

	var available := transport._is_available()
	_check(
		available.ok,
		"and this engine build has the peer it needs",
		"a build without it cannot serve browser clients at all: %s"
			% str(available.error)
	)

	# The constraint that shapes the whole deployment: a browser cannot listen, so the web
	# build is a client and the server is somewhere else.
	_check(
		not DotPlatform.is_web(),
		"and this process can listen, because it is not a browser"
	)
	_done()


func _test_unload() -> void:
	_section("unloading")

	_check(_server.modules.unload_module("hungry").ok, "the module unloads")
	_check(
		_server.console.find_command("hungry_status") == null,
		"and takes its commands with it"
	)

	var world := _world()
	_check(
		world != null and world.monsters().is_empty(),
		"and its players, so the world is not left holding sessions that are gone"
	)

	_check(
		(await _server.modules.load_module("res://game/hungry_module.gd")).ok,
		"and loads again cleanly"
	)
	_done()


## A script that `extends DotNetMessage` and preloads ITSELF, first loaded from a module a running
## [DotServer] loads, leaves every loaded script alive at exit. Asserted on the source: the leak
## is reported after `quit()`, where no check runs, so this reads every message script in `game/`.
func _test_no_message_preloads_itself() -> void:
	_section("exiting clean")

	var messages := PackedStringArray()
	var offenders := PackedStringArray()
	var pending: Array[String] = ["res://game"]

	while not pending.is_empty():
		var dir_path: String = pending.pop_back()

		for sub in DirAccess.get_directories_at(dir_path):
			pending.append(dir_path.path_join(sub))

		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".gd"):
				continue

			var path := dir_path.path_join(file)
			var source := FileAccess.get_file_as_string(path)

			if not _extends_message(source):
				continue

			messages.append(path)

			if source.contains('preload("%s")' % file) or source.contains('preload("%s")' % path):
				offenders.append(path)

	_check(
		messages.size() >= 2,
		"this game's message scripts are found, so the next check is about something",
		", ".join(messages)
	)
	_check(
		offenders.is_empty(),
		"and none of them preloads itself, which leaks every script at exit",
		", ".join(offenders)
	)

	_done()


func _extends_message(source: String) -> bool:
	for line in source.split("\n"):
		if line.begins_with("extends "):
			return line.contains("DotNetMessage") or line.contains("dot_net_message.gd")
	return false


func _test_exits_clean(probe: Array) -> void:
	_section("exiting clean, as a second process saw it")

	var code: int = probe[0]
	var stdout: String = probe[1]
	var stderr: String = probe[2]
	var hung: bool = probe[3]
	var seconds: int = probe[4]
	# Every leak line is the engine's, written to stderr; both streams are searched, and shown
	# apart because their interleaving is lost.
	var text := stdout + "\n" + stderr
	var tail := "its last lines:\n%s\nand the last on stderr:\n%s" % [
		_last_lines(stdout, 15), _last_lines(stderr, 10)
	]

	# A copy that was killed never reached its exit, so neither of the last two was seen, and
	# passing them on an absence of lines would be passing them blind.
	var passes_detail := ""
	if hung:
		passes_detail = ("still running after %d s, so it was killed — a scene that failed to "
			+ "parse, or a thread still blocked when it quit; %s") % [seconds, tail]
	elif code != 0:
		passes_detail = "exit %d; %s" % [code, tail]
	_check(not hung and code == 0, "this suite, run again in a fresh process, passes",
		passes_detail)
	_check(not hung and not text.contains("leaked at exit"), "and leaves no object alive at exit",
		"it was killed before it reached its exit" if hung else _line_with(text, "leaked at exit"))
	_check(not hung and not text.contains("still in use at exit"), "and no resource",
		"it was killed before it reached its exit" if hung else _line_with(text, "still in use at exit"))
	_done()
