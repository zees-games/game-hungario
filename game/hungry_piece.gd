extends RefCounted

const HungryPiece := preload("hungry_piece.gd")

## One piece of one monster.
##
## A monster is a [i]set[/i] of these, not one of them, and that is the whole shape of
## the game: splitting is what lets a big monster catch a small one, bursting is what an
## enemy does to you against your will, and merging back is the cost of both. Everything
## else — the camera, the leaderboard, where the rider sits, being eaten — has to work on
## a set rather than on a point, which is why this class is small and [HungryMonster] is
## not.
##
## It holds a [Dot2DState] rather than a node. The state is what the simulation reads and
## writes, what the grid indexes and what goes on the wire; a node would be a fourth copy
## of a position that has to be kept in step with three others.

## Unique across the world. Also the grid id, the interest id and the wire id.
var id: int = 0

## Which player this belongs to.
var owner_id: int = 0

var state: Dot2DState = null

## Tick this piece may merge with its siblings on. Until then they push apart.
var merge_tick: int = 0

## Tick this piece was created, for diagnostics.
var born_tick: int = 0

## The replicating behaviour, on a process that has netcode. Null otherwise.
##
## [Variant] rather than [code]HungryPieceNet[/code] only so that reading this file does
## not imply reading the netcode; the assignment is done by [HungryNetBridge].
var net: Object = null


static func make(
	p_id: int,
	p_owner: int,
	at: Vector2,
	mass: float,
	rules: Dot2DMassRules,
	tick: int
) -> HungryPiece:
	var piece := HungryPiece.new()
	piece.id = p_id
	piece.owner_id = p_owner
	piece.born_tick = tick
	piece.merge_tick = tick
	piece.state = Dot2DState.at(at, rules.radius_for(mass))
	piece.state.mass = mass
	return piece


func mass() -> float:
	return state.mass


func radius() -> float:
	return state.radius


func position() -> Vector2:
	return state.position


## Where this piece stood when its last tick began, and the tick before that: what a frame is
## drawn between (see [method drawn_position]). Recorded by [method HungryWorld.simulate_piece],
## on a client only for its own predicted pieces; NAN until a tick has run.
var drawn_from: Vector2 = Vector2(NAN, NAN)
var drawn_two_back: Vector2 = Vector2(NAN, NAN)


## Where a frame [param alpha] of the way through this piece's last tick draws it, for a piece
## this machine simulates: between the last two ticks, on along the last step past 1 and
## between the two before below 0 (a connected client's alpha is dot-net's
## `DotNetClock.render_alpha`, -1 to 2 for a moment after a physics frame that ran no tick or
## two). The tick's own position when nothing has been recorded.
##
## [b]A predicted piece was drawn where its tick left it[/b], so at 144 Hz against 60 ticks it
## stood still on more than half the frames and jumped on the rest.
func drawn_position(alpha: float) -> Vector2:
	if not drawn_from.is_finite():
		return state.position
	var step := state.position - drawn_from
	# A jump of more than a body's width in one tick is a teleport (a respawn reusing the
	# piece, a correction), never motion to draw through.
	if step.length() > maxf(state.radius * 2.0, 64.0):
		return state.position
	if alpha > 1.0:
		return state.position + step * minf(alpha - 1.0, 1.0)
	if alpha < 0.0:
		if not drawn_two_back.is_finite():
			return drawn_from
		return drawn_two_back.lerp(drawn_from, maxf(alpha + 1.0, 0.0))
	return drawn_from.lerp(state.position, alpha)


## How far through its tick a frame drawn now is: [param clock]'s `render_alpha()` (dot-net's
## `DotNetClock`, asked by name so a shell older than it draws at the engine's fraction), else
## the engine's physics fraction, which is exact offline where every physics frame is a tick.
static func frame_alpha(clock: Object) -> float:
	if clock != null and is_instance_valid(clock) and clock.has_method(&"render_alpha"):
		return float(clock.call(&"render_alpha"))
	return clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)


## Sets the mass and the radius together.
##
## Going through [Dot2DMassRules] rather than assigning [member Dot2DState.mass] is not
## a style preference: assigning the mass leaves the radius describing the old one until
## the next tick, and anything that queries in between — an eat check, an interest
## rectangle — uses the stale one.
func set_mass(value: float, rules: Dot2DMassRules) -> void:
	state.mass = maxf(1.0, value)
	state.radius = rules.radius_for(state.mass)


func can_merge(tick: int) -> bool:
	return tick >= merge_tick


func describe() -> Dictionary:
	return {
		"id": id,
		"owner": owner_id,
		"mass": mass(),
		"radius": radius(),
		"position": position(),
		"merge_tick": merge_tick,
	}


func _to_string() -> String:
	return "HungryPiece(#%d of %d, %.0f)" % [id, owner_id, mass()]
