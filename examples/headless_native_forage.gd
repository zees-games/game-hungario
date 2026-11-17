extends DotGameCheckSuite

const HungryBot := preload("../game/hungry_bot.gd")
const HungryGrid := preload("../game/hungry_grid.gd")
const HungryPreset := preload("../game/hungry_preset.gd")
const HungryWorld := preload("../game/hungry_world.gd")

## What a bot sees ([method HungryBot.look_for]) is asked of dot-sim's `DotSimGrid2D` when the library is there, and it
## must answer as the script does: on every preset, mid-round with bots playing, every monster's head and seeded origins
## and sights give the same threat, prey, enemy and snack to the bit, and the native grid holds the same ids in the same
## query order; a world with [member HungryBot.native_forage] off steers its bots identically tick for tick; and a bot
## round with [member HungryBot.forage_verify] on re-runs the script beside every live ask with no difference.
## With no library the native half is skipped; [code]GS_SIM_REQUIRE_NATIVE=1[/code] (CI) fails instead.

const PRESETS := [&"classic", &"frenzy", &"gauntlet", &"warrens", &"reef", &"shallows", &"famine", &"feast"]
const SECTIONS := 5
const CHECKS := 11
const TICK_RATE := 60
const SEED := 9157
const BOTS := 12
## Ticks played before and between the seeded asks, and how many times.
const WARM_TICKS := 240
const SPELLS := 4
const SPELL_TICKS := 90
## Seeded asks per spell besides every head.
const ASKS := 40
## Ticks the lockstep and the live round play.
const LOCKSTEP_TICKS := 900
const LIVE_TICKS := 1800
## The per-tick bench: ticks, each one's bot commands timed both ways on the same state, alternated.
const BENCH_TICKS := 600

var _entered := 0
var _finished := 0
var _tick := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("Hungario native bot forage")
	print("")
	_entered += 1
	print("the library has the grid")
	if not DotSim.has(&"grid2d"):
		print("  dot-sim's grid2d module is not loaded: the native half is skipped")
		var required := (OS.get_environment("GS_SIM_REQUIRE_NATIVE") if OS.has_environment("GS_SIM_REQUIRE_NATIVE") else OS.get_environment("DOT_SIM_REQUIRE_NATIVE")) == "1"
		_check(not required, "the library is loaded (GS_SIM_REQUIRE_NATIVE=1)")
		_finished += 1
		_report_sections(_entered, _finished, 1, 1)
		return
	_check(HungryBot.native_forage, "HungryBot.native_forage is on without the game turning it on")
	var probe := _world(&"classic")
	_check(probe.arena.grid is HungryGrid, "the world builds a HungryGrid")
	_drop(probe)
	_finished += 1

	_entered += 1
	print("every preset mid-round: heads and seeded origins, native against the script")
	var asked := 0
	var snacks := 0
	var pieces := 0
	var differ: Array[String] = []
	var grids: Array[String] = []
	var unbuilt: Array[String] = []
	for id: StringName in PRESETS:
		var world := _world(id)
		_tick = 0
		_play(world, WARM_TICKS)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id) ^ 0x5eed
		for spell in range(SPELLS):
			var grid := world.arena.grid as HungryGrid
			if grid.native() == null:
				unbuilt.append(String(id))
				break
			var why := _same_grid(grid, rng)
			if why != "" and grids.size() < 8:
				grids.append("%s spell %d: %s" % [id, spell, why])
			var monsters: Array = world.monsters()
			for monster in monsters:
				var head = monster.rider_piece()
				if not monster.alive or head == null:
					continue
				var asks := [[head.position(), HungryBot.SIGHT]]
				if monster == monsters[0]:
					for _ask in range(ASKS):
						asks.append([head.position() + Vector2(rng.randf_range(-1500.0, 1500.0), rng.randf_range(-1500.0, 1500.0)), rng.randf_range(50.0, 1800.0)])
				for ask: Array in asks:
					var native := HungryBot.look_for(world, monster, head, ask[0], ask[1])
					var script := HungryBot.look_script(world, monster, head, ask[0], ask[1])
					asked += 1
					if script.snack_score > -INF:
						snacks += 1
					if script.enemy != null:
						pieces += 1
					if not native.same_as(script) and differ.size() < 8:
						differ.append("%s spell %d: native %s; script %s" % [id, spell, native.describe(), script.describe()])
			_play(world, SPELL_TICKS)
		_drop(world)
	_check(unbuilt.is_empty(), "every preset's grid has a native copy", ", ".join(unbuilt))
	_check(grids.is_empty(), "the native grid holds the script's ids in the script's order", "; ".join(grids))
	_check(differ.is_empty(), "every ask sees the same", "; ".join(differ))
	_check(asked > 0 and snacks > asked / 4 and pieces > 0 and pieces < asked, "the asks saw food and monsters, and missed them", "%d asks, %d with a snack, %d with an enemy" % [asked, snacks, pieces])
	print("  %d asks, %d with a snack, %d with an enemy" % [asked, snacks, pieces])
	_finished += 1

	_entered += 1
	print("native_forage off steers the same, tick for tick")
	var on_world := _world(&"frenzy")
	var off_world := _world(&"frenzy")
	var first_differ := -1
	var commands := 0
	for tick in range(LOCKSTEP_TICKS):
		HungryBot.native_forage = true
		var on_commands := _commands(on_world, tick)
		HungryBot.native_forage = false
		var off_commands := _commands(off_world, tick)
		HungryBot.native_forage = true
		commands += on_commands.size()
		if first_differ < 0 and not _same_commands(on_commands, off_commands):
			first_differ = tick
		on_world.tick(on_commands)
		off_world.tick(off_commands)
	_check((on_world.arena.grid as HungryGrid)._native != null and (off_world.arena.grid as HungryGrid)._native == null, "only the native world made a native copy")
	_check(first_differ < 0 and commands > LOCKSTEP_TICKS, "every bot command is the same", "first differ at tick %d of %d (%d commands)" % [first_differ, LOCKSTEP_TICKS, commands])
	_drop(on_world)
	_drop(off_world)
	_finished += 1

	_entered += 1
	print("a bot round with forage_verify: the script beside every live ask")
	HungryBot.forage_checked = 0
	HungryBot.forage_differ = 0
	HungryBot.forage_verify = true
	var live := _world(&"classic")
	_tick = 0
	_play(live, LIVE_TICKS)
	HungryBot.forage_verify = false
	_drop(live)
	_check(HungryBot.forage_checked > LIVE_TICKS, "the bots looked", "%d asks" % HungryBot.forage_checked)
	_check(HungryBot.forage_differ == 0, "no live ask differed", "%d of %d" % [HungryBot.forage_differ, HungryBot.forage_checked])
	print("  %d live asks checked, %d differed" % [HungryBot.forage_checked, HungryBot.forage_differ])
	_finished += 1

	_entered += 1
	print("the cost: every bot's command each tick, script and native on the same state, alternated")
	var bench := _world(&"classic")
	_play(bench, WARM_TICKS)
	var spent := {"native": 0, "script": 0}
	for tick in range(BENCH_TICKS):
		var cmds := {}
		for mode: String in (["native", "script"] if tick % 2 == 0 else ["script", "native"]):
			HungryBot.native_forage = mode == "native"
			var start := Time.get_ticks_usec()
			cmds = _commands(bench, tick)
			spent[mode] += Time.get_ticks_usec() - start
		HungryBot.native_forage = true
		bench.tick(cmds)
	var grid_size: int = bench.arena.grid.size()
	_drop(bench)
	var per_tick := {"native": spent["native"] / 1000.0 / BENCH_TICKS, "script": spent["script"] / 1000.0 / BENCH_TICKS}
	print("  %d bots, %d ids, %d ticks: script %.3f ms, native %.3f ms of bot commands per tick" % [BOTS, grid_size, BENCH_TICKS, per_tick["script"], per_tick["native"]])
	_check(spent["native"] > 0 and spent["script"] > 0, "both ways were timed")
	_finished += 1

	_report_sections(_entered, _finished, SECTIONS, CHECKS)


## Native and script grid agree: size, cells, and seeded rect queries id for id.
func _same_grid(grid: HungryGrid, rng: RandomNumberGenerator) -> String:
	var native: Variant = grid.native()
	if native.size() != grid.size() or native.cell_count() != grid.cell_count():
		return "size %d/%d cells %d/%d" % [native.size(), grid.size(), native.cell_count(), grid.cell_count()]
	for _q in range(20):
		var rect := Rect2(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0), rng.randf_range(0.0, 2500.0), rng.randf_range(0.0, 2500.0))
		var want := grid.query_rect(rect)
		var got: PackedInt64Array = native.query_rect(rect, 0)
		if PackedInt64Array(want) != got:
			return "rect %s: native %d ids, script %d" % [rect, got.size(), want.size()]
	return ""


func _world(id: StringName) -> HungryWorld:
	var world := HungryWorld.new()
	world.is_authority = true
	world.name = "World"
	world.preset = HungryPreset.for_id(id)
	world.tick_rate = TICK_RATE
	world.world_seed = SEED
	world.register_service = false
	add_child(world)
	var ready_result := world.setup()
	if not ready_result.ok:
		push_error(str(ready_result.error))
	world.start(0)
	for i in range(BOTS):
		world.add_player(i + 1, "Bot %d" % (i + 1))
	return world


func _drop(world: HungryWorld) -> void:
	if world != null and is_instance_valid(world):
		remove_child(world)
		world.free()


func _commands(world: HungryWorld, tick: int) -> Dictionary:
	var out := {}
	for monster in world.monsters():
		out[monster.id] = HungryBot.command_for(world, monster, tick)
	return out


func _play(world: HungryWorld, ticks: int) -> void:
	for _t in range(ticks):
		world.tick(_commands(world, _tick))
		_tick += 1


func _same_commands(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key):
			return false
		var x: Dot2DCommand = a[key]
		var y: Dot2DCommand = b[key]
		if x.aim != y.aim or x.reach != y.reach or x.buttons != y.buttons:
			return false
	return true
