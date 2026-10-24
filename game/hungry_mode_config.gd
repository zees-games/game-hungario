@tool
extends DotConfig

## One mode's dials as a config, so `cfg/game/game-hungario/mode_<id>/<id>.yml` and the workbench can change them. Built from the mode's code values by [HungryTuning]; the preset takes them back in [method HungryPreset.for_id].
##
## A mode's top speed and merge delay are not here: a client predicts with them from its own copy of the mode.

var _mode_id := "classic"

## Arena width in world units. It travels in the join, so a client follows.
@export_range(400.0, 20000.0, 10.0) var world_width: float = 4000.0

## Arena height in world units.
@export_range(400.0, 20000.0, 10.0) var world_height: float = 4000.0

## Crumbs the field keeps up.
@export_range(0, 20000, 50) var food_target: int = 0

## Fruit lying about at once.
@export_range(0, 200, 1) var fruit_target: int = 0

## Throwables lying about at once.
@export_range(0, 200, 1) var item_target: int = 0

## Mass that wins the round.
@export_range(10.0, 1000000.0, 10.0) var win_mass: float = 0.0

## Seconds a round lasts. Zero is no limit.
@export_range(0.0, 7200.0, 10.0) var time_limit_sec: float = 0.0

## What a monster wedged in a refuge it outgrew does: accept, cap or eject.
@export_enum("accept", "cap", "eject") var outgrown: int = 0


func env_prefix() -> String:
	return "HUNGRY_MODE_%s_" % _mode_id.to_upper()


func cli_prefix() -> String:
	return "--hungry-mode-%s-" % _mode_id


func validate() -> DotResult:
	if minf(world_width, world_height) < 400.0:
		return DotResult.fail(DotError.CODE_INVALID, "A world smaller than 400 units is smaller than a grown monster.")
	return DotResult.success(null)
