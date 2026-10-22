extends Node

const HungryBot := preload("../game/hungry_bot.gd")
const HungryPreset := preload("../game/hungry_preset.gd")
const HungryWorld := preload("../game/hungry_world.gd")

## Bot soak on the real simulation: N HungryBots play rounds back to back in one mode for M
## simulated minutes through dot-bot's DotBotSoak, fed by dot-spawn's DotSpawnWatch.
##
## [codeblock]
## ./game.sh soak [mode] [minutes]
## godot --headless --path . res://tools/soak.tscn -- --map frenzy --bots 8 --minutes 5
## [/codeblock]
##
## The "map" is the mode id (classic, frenzy, gauntlet, warrens, reef, shallows). Takes the
## harness's own flags too. Writes .godot/test-logs/soak-<mode>.json, prints the SOAK line,
## exits 1 when the run fails. A bot between rounds or dead has no goal; there is no
## navigation query for a monster, so off-nav and unreachable are off.

const DEFAULT_MODE := &"classic"
const DEFAULT_MINUTES := 2.0
const DEFAULT_BOTS := 8
const TICK_RATE := 60

var _world: HungryWorld
var _tick := 0
var _deaths := 0
var _rounds := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--" + name)
	if at >= 0 and at + 1 < args.size():
		return args[at + 1]
	return fallback


func _run() -> void:
	var mode := _arg("map", String(DEFAULT_MODE))
	var cfg := DotBotSoakConfig.new()
	cfg.minutes = DEFAULT_MINUTES
	cfg.bots = DEFAULT_BOTS
	# Warrens' gate ring locks a big monster out of the middle and the bot has no route
	# finding, so it can lean on a rock for a while; a longer stretch than this is a trap.
	if mode == "warrens":
		cfg.max_stuck_sec = 20.0
	cfg.apply_cli()
	cfg.minutes = float(_arg("minutes", str(cfg.minutes)))
	cfg.bots = int(_arg("bots", str(cfg.bots)))
	# Eating each other is the game working, not a soak signal.
	cfg.require_kills_after_sec = -1.0

	_world = HungryWorld.new()
	_world.is_authority = true
	_world.name = "World"
	_world.preset = HungryPreset.for_id(StringName(mode))
	_world.tick_rate = TICK_RATE
	_world.world_seed = cfg.seed_value
	_world.register_service = false
	add_child(_world)
	var ready_result := _world.setup()
	if not ready_result.ok:
		_fail("setup: %s" % ready_result.error)
		return
	_world.start(0)
	_world.player_died.connect(func(_p: int, _k: int) -> void: _deaths += 1)
	_world.match_node.round_ended.connect(
		func(_n: int, _w: int, _o: DotMatchRules.Outcome) -> void: _rounds += 1)
	for i in range(cfg.bots):
		_world.add_player(i + 1, "Bot %d" % (i + 1))

	var watch := DotSpawnWatch.new()
	watch.rules.enabled = true
	watch.rules.kill_y = -INF

	var soak := DotBotSoak.new(cfg)
	soak.watch = watch
	soak.movers_fn = _movers
	soak.object_count_fn = func() -> int: return int(Performance.get_monitor(Performance.OBJECT_COUNT))
	soak.step_fn = _step

	var delta := 1.0 / float(TICK_RATE)
	while not soak.is_done():
		soak.advance(delta)
		if soak.ticks % 64 == 0:
			await get_tree().process_frame

	var report := soak.finish()
	report["map"] = mode
	report["deaths"] = _deaths
	report["rounds"] = _rounds
	print(DotBotSoak.summary(report))
	print(DotBotSoak.report_line(report))
	var path := ProjectSettings.globalize_path("res://.godot/test-logs/soak-%s.json" % mode)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if soak.write_report(report, path) != OK:
		push_error("could not write %s" % path)
	await _release_world()
	get_tree().quit(0 if report["ok"] else 1)


## Frees the world before quitting so nothing is still loaded at exit.
func _release_world() -> void:
	_world.queue_free()
	for _i in range(3):
		await get_tree().process_frame


func _step(_delta: float) -> void:
	var commands: Dictionary = {}
	for monster in _world.monsters():
		commands[monster.id] = HungryBot.command_for(_world, monster, _tick)
	_world.tick(commands)
	_tick += 1


func _movers() -> Array:
	var out: Array = []
	var live: bool = _world.match_node.is_live()
	for monster in _world.monsters():
		var head = monster.rider_piece()
		if head == null:
			continue
		out.append({"id": monster.id, "position": Vector3(head.position().x, 0.0, head.position().y),
			"kind": &"bot", "has_goal": live and monster.alive})
	return out


func _fail(why: String) -> void:
	printerr("SOAK setup failed: ", why)
	get_tree().quit(2)
