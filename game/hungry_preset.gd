@tool
extends Resource

const HungryContent := preload("hungry_content.gd")
const HungryLayout := preload("hungry_layout.gd")
const HungryPreset := preload("hungry_preset.gd")

## The handful of numbers that make one mode of this game different from another.

@export var id: StringName = &"classic"

@export var display_name: String = "Classic"

@export_group("World")

@export var world_size: Vector2 = HungryContent.WORLD_SIZE

@export_range(0, 20000, 50) var food_target: int = HungryContent.FOOD_TARGET
@export_range(0, 200, 1) var fruit_target: int = HungryContent.FRUIT_TARGET
@export_range(0, 200, 1) var item_target: int = HungryContent.ITEM_TARGET

## Which solid geometry stands in the world. Empty is an empty box.
@export var layout: StringName = HungryLayout.NONE

## A variant of [member layout], or "" for its default (`quartered` puts the warrens' corner rocks back on the diagonal). It travels with the layout's name (`warrens:quartered`).
## See [constant HungryLayout.CORNER_VARIANTS].
@export var layout_variant: String = ""

@export_group("Growing")

@export_range(10.0, 1000000.0, 10.0) var win_mass: float = HungryContent.WIN_MASS

@export_range(1.0, 5000.0, 5.0) var max_speed: float = 415.0

## Seconds before two pieces of the same monster merge back.
@export_range(0.0, 300.0, 0.5) var merge_delay_sec: float = 16.0

## What a monster that has outgrown a refuge's room does: `accept` (it sits in the post until it splits or ejects), `cap` (food stops counting while wedged) or `eject` (the excess is shed as food).
## See [member HungryWorld.outgrown]; the server's `hungry_outgrown` overrides a mode's.
@export_enum("accept", "cap", "eject") var outgrown: int = 0

@export_group("Round")

@export_range(0.0, 7200.0, 10.0) var time_limit_sec: float = 900.0


static func classic() -> HungryPreset:
	return HungryPreset.new()


## Small, fast, and over quickly. What a server switches to when six people are waiting.
static func frenzy() -> HungryPreset:
	var preset := HungryPreset.new()
	preset.id = &"frenzy"
	preset.display_name = "Frenzy"
	preset.world_size = Vector2(3000.0, 3000.0)
	preset.food_target = 700
	preset.fruit_target = 18
	preset.item_target = 26
	preset.win_mass = 900.0
	preset.max_speed = 520.0
	# Four seconds rather than sixteen. Splitting stops being a commitment and starts
	# being a move, which is the whole character of the mode.
	preset.merge_delay_sec = 4.0
	preset.time_limit_sec = 300.0
	return preset


## Long and narrow. A corridor rather than a square, which is a different game.
static func gauntlet() -> HungryPreset:
	var preset := HungryPreset.new()
	preset.id = &"gauntlet"
	preset.display_name = "Gauntlet"
	preset.layout = HungryLayout.SLALOM

	# Five to one, and the same area as Frenzy's square with the same food per unit of floor, so the mode is the shape and not the density.
	preset.world_size = Vector2(6708.0, 1342.0)

	# [b]Frenzy's density on the floor that is left, which is LOWER than Frenzy's
	# count.[/b] Five rocks and the two harbour fences' six posts cover 13.0% of the
	# corridor (the rocks alone were 11.3%, and the target 620, until the harbours).
	preset.food_target = 609
	preset.fruit_target = 18
	preset.item_target = 26
	preset.win_mass = 900.0
	preset.max_speed = 480.0

	# Between the other two. A corridor punishes a split harder than a square does —
	# there is nowhere to spread out to while the pieces are apart — so sixteen seconds
	# would make splitting never worth it and four would make it free.
	preset.merge_delay_sec = 9.0
	preset.time_limit_sec = 300.0
	return preset


## A square with things in it, and the things are the mode.
static func warrens() -> HungryPreset:
	var preset := HungryPreset.new()
	preset.id = &"warrens"
	preset.display_name = "Warrens"
	preset.layout = HungryLayout.WARRENS

	# Between Classic and Frenzy. Small enough that the ring is most of the map rather
	# than an ornament in the middle of it, and big enough that the perimeter lane is a
	# route rather than a corridor.
	preset.world_size = Vector2(4200.0, 4200.0)

	# Classic's food density over the floor that is actually left: the layout covers about an eighth of the rectangle and the world culls food landing in a rock (`HungryWorld._cull_blocked`).
	# 609 is Classic's 40.7 per million on the 14.98 million left.
	preset.food_target = 609

	# Above Classic's density, deliberately: Warrens is full of people you cannot reach, and a pepper that bursts somebody into halves small enough for a gate is both an attack and a door.
	preset.fruit_target = 14
	preset.item_target = 26

	# Reached through gates rather than across open ground, so it takes about as long as
	# Frenzy's despite the arena being twice the size.
	preset.win_mass = 1600.0
	preset.max_speed = 460.0

	# The gate tax: splitting to fit through the middle is the mode's signature move and the delay stops it being free (four seconds makes the ring irrelevant, sixteen makes the middle unreachable).
	preset.merge_delay_sec = 8.0
	preset.time_limit_sec = 360.0
	return preset


## A wall across the world with four channels through it, tight at one end and open at
## the other.
static func reef() -> HungryPreset:
	var preset := HungryPreset.new()
	preset.id = &"reef"
	preset.display_name = "Reef"
	preset.layout = HungryLayout.REEF

	# Between Warrens and Classic. Big enough that walking to the open end is a journey
	# rather than a step, and small enough that the tight end is somewhere a small
	# monster can still get to before it has outgrown it.
	preset.world_size = Vector2(4600.0, 4600.0)

	# Classic's density (40.7 per million square units) over the floor that is actually left, 20.06 million after twenty rocks; the field refills what `HungryWorld._cull_blocked` removes.
	# The suite measures the food alive (`headless_round`'s "food on the floor that is left") rather than repeating the arithmetic.
	preset.food_target = 816

	# Above density, like Warrens and sharper: a pepper splits somebody into halves that fit a channel they did not, so a throwable is a door opening where the victim did not choose.
	preset.fruit_target = 15
	preset.item_target = 26

	preset.win_mass = 1500.0
	preset.max_speed = 445.0

	# The crossing tax: splitting is how a grown monster uses a channel it does not fit, and a channel is a passage, so you are in two halves for its length.
	# Twelve seconds rather than Warrens' eight because the exposure is longer.
	preset.merge_delay_sec = 12.0
	preset.time_limit_sec = 420.0
	return preset


## Lines of posts across the world whose gaps widen from the west wall to the open water:
## the further in a monster wants to go, the smaller it has to be. See
## [method HungryLayout._shallows].
static func shallows() -> HungryPreset:
	var preset := HungryPreset.new()
	preset.id = &"shallows"
	preset.display_name = "Shallows"
	preset.layout = HungryLayout.SHALLOWS
	preset.world_size = Vector2(4600.0, 4600.0)

	# Classic's density over the floor that is actually left (see the reef's note): thirty-eight posts and the pools, groynes, inlet and sills leave 20.51 million square units, where it is 834.
	preset.food_target = 834

	# The reef's reason, once per line: a pepper splits somebody into halves that fit a
	# line they did not fit before, so a throwable here is a way further in, for them
	# or for the monster that threw it.
	preset.fruit_target = 15
	preset.item_target = 26

	preset.win_mass = 1500.0
	preset.max_speed = 445.0
	preset.merge_delay_sec = 12.0
	preset.time_limit_sec = 420.0
	return preset


static func for_id(preset_id: StringName) -> HungryPreset:
	match preset_id:
		&"frenzy":
			return frenzy()
		&"gauntlet":
			return gauntlet()
		&"warrens":
			return warrens()
		&"reef":
			return reef()
		&"shallows":
			return shallows()
		_:
			return classic()


func validate() -> DotResult:
	if minf(world_size.x, world_size.y) < 400.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A world smaller than 400 units is smaller than a grown monster."
		)

	if win_mass <= HungryContent.START_MASS:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A win mass of %.0f is at or below the starting mass, so the first player "
				% win_mass
			+ "to spawn has already won."
		)

	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name,
		"world": world_size,
		"food": food_target,
		"win": win_mass,
		"speed": max_speed,
		"merge": merge_delay_sec,
		"layout": String(layout),
	}


func _to_string() -> String:
	return "HungryPreset(%s)" % id
