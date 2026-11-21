@tool
extends Node
## The world's shape and the calls a client uses to adopt the server's copy of it: layout,
## predicted rules and projectiles. [code]hungry_world.gd[/code] extends this.

const HungryContent := preload("hungry_content.gd")
const HungryGrid := preload("hungry_grid.gd")
const HungryField := preload("hungry_field.gd")
const HungryLayout := preload("hungry_layout.gd")
const HungryPredicted := preload("hungry_predicted.gd")
const HungryProjectile := preload("hungry_projectile.gd")
const CHANNEL := "hungry"
var arena: GS2DArena = null
## What is solid in this world: the level's own geometry.
var layout: HungryLayout = HungryLayout.none()
var field: HungryField = null
var tunables: GS2DTunables = null
## What a client predicts with: built from the server's config and mode, sent in the hello, adopted by clients. Shared with every monster.
var predicted: HungryPredicted = HungryPredicted.new()
## projectile id -> [HungryProjectile].
var _shots: Dictionary = {}
var _next_shot_id: int = 1


## Adopts the authority's layout. Client side, from the hello.
func adopt_layout(layout_id: StringName) -> void:
	layout = HungryLayout.for_id(layout_id, arena.bounds)

	GSLog.debug(CHANNEL, "adopted the authority's layout", {
		"layout": String(layout_id), "blocks": layout.count(),
	})


## Adopts the numbers the authority predicts with. Client side, from the hello.
func adopt_predicted(carried: HungryPredicted) -> void:
	if carried == null or not carried.is_sane():
		return

	predicted.adopt(carried)
	tunables.max_speed = carried.max_speed
	tunables.mass_rules.merge_delay_sec = carried.merge_delay_sec


func projectiles() -> Array[HungryProjectile]:
	var out: Array[HungryProjectile] = []
	var keys := _shots.keys()
	keys.sort()
	for key in keys:
		out.append(_shots[key])
	return out


## Mirrors a throw the authority has announced. Client side.
func adopt_projectile(shot: HungryProjectile) -> void:
	if shot == null or shot.id <= 0:
		return

	_shots[shot.id] = shot
	_next_shot_id = maxi(_next_shot_id, shot.id + 1)


## Removes a projectile the authority says has landed. Client side.
func drop_projectile(shot_id: int) -> void:
	_shots.erase(shot_id)


## With dot-sim's grid2d the bots' neighbour loop runs natively over a copy of the arena's grid
## (HungryGrid, made on the first bot ask); without it, dot-2d's own grid.
func _use_native_grid() -> void:
	if not GSSim.has(&"grid2d"):
		return

	var grid := HungryGrid.new(HungryContent.CELL_SIZE)
	grid.worth_of = _grid_worth
	arena.grid = grid


## What eating grid id [param grid_id] is worth, for [HungryGrid]'s native copy.
func _grid_worth(grid_id: int) -> float:
	return field.mass_of(grid_id) if field != null else 0.0
