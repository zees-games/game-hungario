extends DotGameCheckSuite

const HungryBot := preload("../game/hungry_bot.gd")
const HungryContent := preload("../game/hungry_content.gd")
const HungryContentSource := preload("../game/client/hungry_content_source.gd")
const HungryEvents := preload("../game/net/hungry_events.gd")
const HungryField := preload("../game/hungry_field.gd")
const HungryHud := preload("../game/client/hungry_hud.gd")
const HungryHunters := preload("../game/hungry_hunters.gd")
const HungryInput := preload("../game/client/hungry_input.gd")
const HungryMenus := preload("../game/client/hungry_menus.gd")
const HungryMonster := preload("../game/hungry_monster.gd")
const HungryNetCommand := preload("../game/net/hungry_net_command.gd")
const HungryLayout := preload("../game/hungry_layout.gd")
const HungryPreset := preload("../game/hungry_preset.gd")
const HungryProjectile := preload("../game/hungry_projectile.gd")
const HungryRenderer := preload("../game/client/hungry_renderer.gd")
const HungryRider := preload("../game/client/hungry_rider.gd")
const HungrySound := preload("../game/client/hungry_sound.gd")
const HungryTouch := preload("../game/client/hungry_touch.gd")
const HungryWorld := preload("../game/hungry_world.gd")

## Shared fixtures and constants for the headless round suite.

const SEED := 20260828
const TICK_RATE := 60

## Sections entered and completed: a runtime error aborts a section silently, so the
## totals cannot show it but this pair can.
var _entered := 0
var _completed := 0


## Opens a section. Pair with [method _done] on the last line.
func _section(title: String) -> void:
	_entered += 1
	print("")
	print(title)


## Closes a section. Anything that returns early has to call it before returning.
func _done() -> void:
	_completed += 1


# --- Fixtures --------------------------------------------------------------

## A world nobody else can see, so a test can do what it likes to it.
##
## `register_service` is off for every one of these: two worlds registered under the same
## name would displace each other, and several of these tests hold two at once.
func _make_world(
	preset: HungryPreset = null, world_seed: int = SEED, authority: bool = true
) -> HungryWorld:
	var world := HungryWorld.new()
	# Before setup, as the client sets it: the spectate layer reads it once, there.
	world.is_authority = authority
	world.name = "World"
	world.preset = preset if preset != null else HungryPreset.classic()
	world.tick_rate = TICK_RATE
	world.world_seed = world_seed
	world.register_service = false
	add_child(world)

	var ready_result := world.setup()

	if not ready_result.ok:
		push_error(str(ready_result.error))

	world.start(0)
	return world


func _drop(world: HungryWorld) -> void:
	if world != null and is_instance_valid(world):
		remove_child(world)
		world.free()


## Ticks a world, feeding every monster a fixed command.
func _run_ticks(world: HungryWorld, count: int, commands: Dictionary = {}) -> void:
	for _i in range(count):
		world.tick(commands)


## Ticks until the round is actually live.
##
## [b]Not optional, and the first thing every arrangement in this file learned.[/b] The
## transition into [constant DotMatch.State.LIVE] runs [method HungryWorld.reset_world] —
## that is what a new round [i]is[/i] — and it clears every piece, every carried item and
## every effect, then respawns everybody somewhere safe. A test that arranged the world
## before that happened had its arrangement thrown away, and the symptom was a monster
## standing a thousand units from where it was put, holding nothing.
##
## [b]And it has to be able to go live, which a world with nobody in it cannot.[/b]
## dot-match waits in warmup for its minimum head count, so a settle called before the
## first player is added runs out its five seconds and returns with the round still in
## warmup — and then the FIRST tick after somebody joins is the transition, which resets
## the world and respawns them wherever the safe spawn likes. Every level section here
## settled before adding its player, so every one of them arranged a monster in front of
## a rock or a gate, ticked twice, and drove whatever the reset had put somewhere else.
## The reef's "a starting monster comes out the far side of the tight channel" was
## measuring a monster respawned 900 units past it. A settle that gives up is a failure
## now, recorded without adding to the total so a passing run's count is unchanged.
func _settle(world: HungryWorld) -> void:
	# A client's round state arrives from the authority; its own match never advances,
	# and nothing it holds is reset by a transition it does not run.
	if not world.is_authority:
		return

	for _i in range(TICK_RATE * 5):
		if world.match_node.is_live():
			return

		world.tick({})

	if not world.match_node.is_live():
		_failed += 1
		_failures.append(
			"a world never went live, so anything arranged in it is thrown away at the "
			+ "first tick after a player joins (state %d, %d monsters)"
				% [world.match_node.state, world.monsters().size()]
		)
		print("  FAIL  a world never went live before its arrangement (%d monsters)"
			% world.monsters().size())


func _aim_at(from: Vector2, to: Vector2, buttons: int = 0) -> Dot2DCommand:
	var command := Dot2DCommand.new()
	var offset := to - from
	command.aim = offset.normalized() if offset.length_squared() > 0.000001 else Vector2.RIGHT
	command.reach = minf(offset.length(), HungryNetCommand.MAX_REACH)
	command.buttons = buttons
	return command


# --- Setup -----------------------------------------------------------------


## A list of gap widths, for a check's detail line.
func _widths(gaps: PackedFloat32Array) -> String:
	var parts := PackedStringArray()

	for gap in gaps:
		parts.append("%.0f" % gap)

	return "/".join(parts)


func _full_reach(from: Vector2, to: Vector2) -> Dot2DCommand:
	var command := Dot2DCommand.new()
	var offset := to - from
	command.aim = offset.normalized() if offset.length_squared() > 0.000001 else Vector2.RIGHT
	command.reach = HungryNetCommand.MAX_REACH
	return command


## The open water a shallows check starts from: the middle bay, halfway between the last
## line and the inlet's front, on the centre line. The open wall's own middle was it until
## the inlet stood there; this is 900 across, room for anything up to radius 450.
func _shallows_open_water(layout: HungryLayout, bounds: Rect2) -> Vector2:
	var last := layout.blocks[layout.chains[layout.chains.size() - 1].x]
	var front := bounds.end.x

	for run in layout.inlets:
		for index in range(run.x, run.x + run.y):
			front = minf(front, layout.blocks[index].x - layout.blocks[index].z)

	return Vector2((last.x + last.z + front) * 0.5, bounds.get_center().y)
