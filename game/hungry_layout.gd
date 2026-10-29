extends RefCounted

const HungryLayout := preload("hungry_layout.gd")

## The solid geometry a level is built out of, derived rather than replicated.

# No CHANNEL: a pure function of an id and a rectangle, with nothing at runtime to report.

## Nothing standing in the arena. What `classic` and `frenzy` use.
const NONE := &""

## A ring of gates around a middle, with cover in the corners.
const WARRENS := &"warrens"

## A line of rocks down a corridor, alternately near one wall and the other, and a fence of
## posts across each end of it with a harbour behind. See [method _slalom] and
## [method _append_harbours].
const SLALOM := &"slalom"

## The reef: a barrier whose channels widen, a one-door barrier behind it, an atoll, spits and a cove.
## See [method _reef], [method _append_atoll], [method _append_spits] and [method _append_cove].
const REEF := &"reef"

## The shallows: five lines of posts whose gaps widen away from the open water, plus pools, groynes, an inlet and sills.
## See [method _shallows] and the [method _append_pools]/[method _append_groynes]/[method _append_inlet]/[method _append_sills] helpers.
const SHALLOWS := &"shallows"


## A subscribed pack's map (solo only): `workshop:<entry id>`, its rocks read from a document
## [HungryWorkshop] registered in [member documents]. Not in [method ids]: it has no design
## rules to measure, a pack author's rocks are theirs.
const WORKSHOP := &"workshop"

## Entry id -> `PackedVector3Array` of `(x, y, r)` as FRACTIONS of the arena's smaller
## half-extent, like every layout here is proportional so it fits whatever world it is in.
static var documents: Dictionary = {}


static func _workshop(bounds: Rect2, entry: String) -> HungryLayout:
	var out := HungryLayout.new()
	out.id = StringName("%s:%s" % [WORKSHOP, entry])
	var rocks: PackedVector3Array = documents.get(entry, PackedVector3Array())
	var half := minf(bounds.size.x, bounds.size.y) * 0.5
	var centre := bounds.get_center()

	for rock in rocks:
		out.blocks.append(Vector3(centre.x + rock.x * half, centre.y + rock.y * half, rock.z * half))

	return out


## Every layout that is a level, so a check can ask all of them the same question.
static func ids() -> Array[StringName]:
	return [WARRENS, SLALOM, REEF, SHALLOWS]


## What is solid, as `(x, y, radius)` in world units.
var blocks: PackedVector3Array = PackedVector3Array()

var id: StringName = NONE

## Which runs of [member blocks] are one CLOSED ring, as `(first, count)`.
var rings: Array[Vector2i] = []

## Which runs of [member blocks] are one barrier, as `(first, count)`.
var chains: Array[Vector2i] = []

## Which runs of [member blocks] are one of the reef's spits, as `(first, count)`, each
## laid out from the sea wall out. See [method _append_spits].
var spits: Array[Vector2i] = []

## Which runs of [member blocks] are the reef's cove, as `(first, count)`: two posts, sea
## side first. See [method _append_cove] and [method in_cove].
var coves: Array[Vector2i] = []

## The shallows' rock pools, as `(first, count)`: one post each, standing off a corner of
## the open water. See [method _append_pools] and [method in_pool].
var pools: Array[Vector2i] = []

## The shallows' groynes, as `(first, count)`: two posts each, laid out from the last
## line toward the open wall. See [method _append_groynes] and [method bay_of].
var groynes: Array[Vector2i] = []

## The shallows' inlet, as `(first, count)`: two posts off the open wall in the middle
## bay, the short axis's low side first. See [method _append_inlet] and [method in_inlet].
var inlets: Array[Vector2i] = []

## The shallows' sills, as `(first, count)`: one post each, across a band from a post of
## the line inside it. See [method _append_sills].
var sills: Array[Vector2i] = []


static func none() -> HungryLayout:
	return HungryLayout.new()


## The layout of a level, laid out inside the rectangle that level actually has.
static func for_id(layout_id: StringName, bounds: Rect2) -> HungryLayout:
	# `<layout>:<variant>`: the variant rides in the same string the hello already carries,
	# so a client builds exactly the rocks its server has. See [method variant_of].
	var base := base_of(layout_id)

	match base:
		WARRENS:
			var built := _warrens(bounds, variant_of(layout_id))
			built.id = layout_id
			return built
		SLALOM:
			return _slalom(bounds)
		REEF:
			return _reef(bounds)
		SHALLOWS:
			return _shallows(bounds)
		WORKSHOP:
			return _workshop(bounds, variant_of(layout_id))
		_:
			return none()



## The layout a `<layout>:<variant>` id names.
static func base_of(layout_id: StringName) -> StringName:
	var text := String(layout_id)
	var colon := text.find(":")
	return StringName(text.substr(0, colon)) if colon >= 0 else layout_id


## The variant a `<layout>:<variant>` id names, or "" for the layout's default.
static func variant_of(layout_id: StringName) -> String:
	var text := String(layout_id)
	var colon := text.find(":")
	return text.substr(colon + 1).strip_edges().to_lower() if colon >= 0 else ""


## A layout id with [param variant] applied: the default spelled plainly, anything else as
## `<layout>:<variant>`.
static func with_variant(layout_id: StringName, variant: String) -> StringName:
	var base := base_of(layout_id)
	var v := variant.strip_edges().to_lower()
	return base if v == "" else StringName("%s:%s" % [base, v])



## How far out the ring of gate rocks stands, as a fraction of the smaller half-extent.
const RING_AT := 0.548

## How big one gate rock is, as a fraction of the smaller half-extent.
const RING_RADIUS := 0.124

## How many rocks the ring is made of. Eight gives eight gates, which is enough that
## being locked out of the middle is a detour rather than a wall.
const RING_COUNT := 8

## The corner cover: one rock per quadrant, as layout data. A variant is
## `[distance out along each axis, radius]`, both as fractions of the smaller half-extent.
const CORNER_VARIANTS := {
	"open": {"shape": "wall", "along": 0.575, "radius": 0.09},
	"quartered": {"shape": "diagonal", "at": 0.657, "radius": 0.114},
}
const CORNER_DEFAULT := "open"

## The den: how many rocks, how far out, and how big, same fraction as the ring.
const DEN_COUNT := 4
const DEN_AT := 0.16
const DEN_RADIUS := 0.065


## A ring of eight rocks around an open middle, and a rock in each quadrant.
static func _warrens(bounds: Rect2, variant: String = "") -> HungryLayout:
	var out := HungryLayout.new()
	out.id = WARRENS

	# The SMALLER half-extent, so a layout asked for inside a non-square world scales to
	# the axis that actually constrains it. Against `.x` alone a corridor would get a ring
	# wider than the corridor is, and every rock would be clamped into the walls.
	var half := minf(bounds.size.x, bounds.size.y) * 0.5
	var centre := bounds.get_center()

	var ring_at := half * RING_AT
	var ring_radius := half * RING_RADIUS

	for step in range(RING_COUNT):
		# Offset by half a step: the rocks sit off the axes so the gates sit on them, every 45 degrees.
		# The den's straight run in from each wall depends on it.
		var angle := TAU * (float(step) + 0.5) / float(RING_COUNT)
		out.blocks.append(Vector3(
			centre.x + cos(angle) * ring_at,
			centre.y + sin(angle) * ring_at,
			ring_radius
		))

	out.rings.append(Vector2i(0, RING_COUNT))

	var corners: Dictionary = CORNER_VARIANTS.get(variant, CORNER_VARIANTS[CORNER_DEFAULT])
	var corner_radius := half * float(corners["radius"])

	if str(corners["shape"]) == "wall":
		# A pinwheel: each quadrant's rock is the last one turned a quarter, so every
		# corner plays the same and none is the safe one. Written out rather than rotated:
		# a rotation's rounding would leave a gap to the wall a hair wide, which is a gate.
		var along := half * float(corners["along"])
		var off := half - corner_radius + 0.01
		for p: Vector2 in [Vector2(off, -along), Vector2(along, off), Vector2(-off, along), Vector2(-along, -off)]:
			out.blocks.append(Vector3(centre.x + p.x, centre.y + p.y, corner_radius))
	else:
		var corner_at := half * float(corners["at"])
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				out.blocks.append(Vector3(
					centre.x + sx * corner_at, centre.y + sy * corner_at, corner_radius
				))

	# [b]The den, appended LAST[/b], so the ring is still blocks 0-7 and the corners 8-11
	# for everything that was written against the warrens before it had a middle's middle.
	_append_den(out, centre, half)

	return out


## The warrens' second half: a ring inside the ring.
static func _append_den(layout: HungryLayout, centre: Vector2, half: float) -> void:
	var den_at := half * DEN_AT
	var den_radius := half * DEN_RADIUS
	var first := layout.blocks.size()

	for step in range(DEN_COUNT):
		var angle := TAU * (float(step) + 0.5) / float(DEN_COUNT)
		layout.blocks.append(Vector3(
			centre.x + cos(angle) * den_at, centre.y + sin(angle) * den_at, den_radius
		))

	layout.rings.append(Vector2i(first, DEN_COUNT))



## How many rocks the slalom is made of.
const SLALOM_COUNT := 5

## How big one slalom rock is, as a fraction of the corridor's HALF-WIDTH.
const SLALOM_RADIUS := 0.38

## How far off the corridor's centre line each rock stands, same fraction.
const SLALOM_OFFSET := 0.22


## A line of rocks down a corridor, alternately near one wall and the other.
static func _slalom(bounds: Rect2) -> HungryLayout:
	var out := HungryLayout.new()
	out.id = SLALOM

	# [b]Which way the corridor runs is read from the rectangle, not assumed.[/b]
	var along_x := bounds.size.x >= bounds.size.y
	var long_extent := maxf(bounds.size.x, bounds.size.y)
	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var centre := bounds.get_center()

	var radius := short_half * SLALOM_RADIUS
	var offset := short_half * SLALOM_OFFSET

	for step in range(SLALOM_COUNT):
		# Evenly spaced with a half-station of clear floor at each end, so neither spawn
		# end opens straight onto a rock.
		var along := (float(step + 1) / float(SLALOM_COUNT + 1) - 0.5) * long_extent
		var across := offset if step % 2 == 0 else -offset

		out.blocks.append(
			Vector3(centre.x + along, centre.y + across, radius) if along_x
			else Vector3(centre.x + across, centre.y + along, radius)
		)

	# [b]The harbours, appended AFTER the slalom[/b], so the slalom is still blocks 0-4 for
	# everything written against it before the corridor had ends.
	_append_harbours(out, bounds)

	return out


## How many posts stand in each harbour's fence. Three leaves four doors: two against the
## walls and two between posts, and the middle post stands on the centre line.
const HARBOUR_POSTS := 3

## How wide one door is, as a fraction of the corridor's HALF-WIDTH.
const HARBOUR_DOOR := 0.3

## How far each fence stands from its end wall, centre line to wall, same fraction.
const HARBOUR_AT := 0.575


## The corridor's ends: a fence of posts across each, with four doors a monster outgrows.
static func _append_harbours(layout: HungryLayout, bounds: Rect2) -> void:
	var along_x := bounds.size.x >= bounds.size.y
	var long_half := maxf(bounds.size.x, bounds.size.y) * 0.5
	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var centre := bounds.get_center()
	var door := short_half * HARBOUR_DOOR
	var post := harbour_post_radius(short_half)
	var at := long_half - short_half * HARBOUR_AT

	# West (or north) end first, then east; each fence laid out from the short axis's low
	# end, so its first channel is the door next to the first post.
	for side in [-1.0, 1.0]:
		var fence := PackedVector3Array()

		for step in range(HARBOUR_POSTS):
			var across := -short_half + door * float(step + 1) + post * float(step * 2 + 1)
			var along: float = side * at
			fence.append(
				Vector3(centre.x + along, centre.y + across, post) if along_x
				else Vector3(centre.x + across, centre.y + along, post)
			)

		_append_chain(layout, fence)


## The radius of one harbour post: whatever is left of the corridor's width once the four
## doors are taken out, shared between the posts. Derived, so the doors are the number
## that was chosen and the posts are what that choice leaves.
static func harbour_post_radius(short_half: float) -> float:
	return (short_half * 2.0 - short_half * HARBOUR_DOOR * float(HARBOUR_POSTS + 1)) \
		/ float(HARBOUR_POSTS * 2)


## Which harbour [param at] stands in (index into [member chains]), or -1; only the slalom has harbours.
## "Behind" is past the fence's front face, so a point between two posts counts as inside.
func harbour_of(at: Vector2, bounds: Rect2) -> int:
	if id != SLALOM:
		return -1

	var along_x := bounds.size.x >= bounds.size.y
	var centre := bounds.get_center()
	var here := (at.x - centre.x) if along_x else (at.y - centre.y)

	for chain in range(chains.size()):
		var first := blocks[chains[chain].x]
		var fence := (first.x - centre.x) if along_x else (first.y - centre.y)

		if here * fence > 0.0 and absf(here) > absf(fence) - first.z:
			return chain

	return -1


## The rocks of runs [param first] to [param first] + [param count] as a layout of their own, so a check can ask about one part of a level.
func part(first: int, count: int) -> HungryLayout:
	var out := HungryLayout.new()
	out.id = id
	out.blocks = blocks.slice(first, first + count)
	return out



## How many rocks the barrier is made of. Five leaves four channels through it.
const REEF_COUNT := 5

## How big one reef rock is, as a fraction of the SHORT half-extent.
const REEF_RADIUS := 0.075

## The narrowest channel, edge to edge, as the same fraction.
const REEF_TIGHT := 0.108

## The widest channel, same units.
const REEF_WIDE := 0.36

## How far behind the fore reef the back reef stands, as a fraction of the short
## half-extent, centre to centre.
const LAGOON_AT := 0.55


## A barrier across the world with four channels through it, tight at one end and open at
## the other.
static func _reef(bounds: Rect2) -> HungryLayout:
	var out := HungryLayout.new()
	out.id = REEF

	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5

	# The fore reef, through the middle of the world, tight end first. Unchanged since the
	# reef was one barrier, deliberately: the lagoon is a second half added behind it, and
	# a first half that moved to make room would be a different level wearing its name.
	_append_chain(out, _reef_chain(bounds, 0.0, channel_widths(short_half)))
	# The back reef, LAGOON_AT behind it: one door at the end behind the fore reef's tight
	# channel, and three equal gates. See [method back_reef_widths].
	_append_chain(out, _reef_chain(
		bounds, short_half * LAGOON_AT, back_reef_widths(short_half)
	))
	# [b]The atoll, appended after both barriers[/b], so the two barriers are still blocks
	# 0-9 for everything written against the reef before its open sea had anything in it.
	_append_atoll(out, bounds)
	# [b]The spits, appended LAST[/b], so the atoll is still blocks 10-13 and still
	# `rings[0]`. They are neither chains nor rings: see [member spits].
	_append_spits(out, bounds)
	# [b]The cove, appended after the spits[/b], so the spits are still blocks 14-17. It
	# is its own list, [member coves]: two posts and a wall, not a barrier or a ring.
	_append_cove(out, bounds)

	return out


## How many rocks the atoll is made of: four, two on the wall side and two on the reef
## side, which is what makes its gates a gradient — see [method atoll_widths].
const ATOLL_COUNT := 4

## How big one atoll rock is, as a fraction of the short half-extent. Smaller than a reef
## rock (0.075): the gates are the design number and the rocks are what holds them apart.
const ATOLL_RADIUS := 0.025

## How far in front of the fore reef the atoll's centre stands, as the same fraction.
const ATOLL_AT := 0.595


## The reef's third part: an atoll in the open sea in front of the fore reef.
static func _append_atoll(layout: HungryLayout, bounds: Rect2) -> void:
	# The crossing axis is the one the reef is NOT built along; the lagoon is on its
	# positive side, so the open sea — and the atoll — is on its negative side.
	var chain_along_x := bounds.size.x < bounds.size.y
	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var centre := bounds.get_center()
	var along := Vector2(1.0, 0.0) if chain_along_x else Vector2(0.0, 1.0)
	var toward_reef := Vector2(0.0, 1.0) if chain_along_x else Vector2(1.0, 0.0)
	var middle := centre - toward_reef * short_half * ATOLL_AT

	var gates := atoll_widths(short_half)
	var radius := short_half * ATOLL_RADIUS
	var wall_half := gates[0] * 0.5 + radius
	var reef_half := gates[2] * 0.5 + radius
	var flank := gates[1] + radius * 2.0
	var depth := sqrt(flank * flank - (reef_half - wall_half) * (reef_half - wall_half)) * 0.5
	var first := layout.blocks.size()

	for rock in [
		Vector2(-depth, -wall_half), Vector2(-depth, wall_half),
		Vector2(depth, reef_half), Vector2(depth, -reef_half),
	]:
		var at: Vector2 = middle + toward_reef * rock.x + along * rock.y
		layout.blocks.append(Vector3(at.x, at.y, radius))

	layout.rings.append(Vector2i(first, ATOLL_COUNT))


## The atoll's four gates in ring order — wall side, flank, reef side, flank — in world
## units.
static func atoll_widths(short_half: float) -> PackedFloat32Array:
	var fore := channel_widths(short_half)
	var flank := (fore[0] + fore[1]) * 0.5
	return PackedFloat32Array([fore[0], flank, fore[1], flank])


## The atoll's centre, the point its gates are measured toward. Only the reef has one.
func atoll_centre() -> Vector2:
	if id != REEF or rings.is_empty():
		return Vector2.INF

	var total := Vector2.ZERO
	var run := rings[0]

	for index in range(run.x, run.x + run.y):
		total += Vector2(blocks[index].x, blocks[index].y)

	return total / float(run.y)


## How many rocks one spit is made of. Two leave two gaps: one against the sea wall and
## one between the rocks — see [method spit_widths].
const SPIT_COUNT := 2

## How far either side of the crossing axis each spit stands, as a fraction of the short
## half-extent: half way from the atoll's line to the wall, 1150 at `reef`'s size.
const SPIT_AT := 0.5

## How big one spit rock is, same fraction. 92 at `reef`'s size.
const SPIT_RADIUS := 0.04


## The reef's fourth part: a spit from the sea wall on each side of the atoll.
static func _append_spits(layout: HungryLayout, bounds: Rect2) -> void:
	var chain_along_x := bounds.size.x < bounds.size.y
	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var centre := bounds.get_center()
	var along := Vector2(1.0, 0.0) if chain_along_x else Vector2(0.0, 1.0)
	var toward_reef := Vector2(0.0, 1.0) if chain_along_x else Vector2(1.0, 0.0)
	# The sea wall is the crossing axis's low wall, which in a non-square world is the
	# LONG half-extent away: the reef is built across the short axis.
	var sea_half := (bounds.size.y if chain_along_x else bounds.size.x) * 0.5
	var gaps := spit_widths(short_half)
	var radius := short_half * SPIT_RADIUS

	for side in [-1.0, 1.0]:
		var first := layout.blocks.size()
		var from_wall := 0.0

		for step in range(SPIT_COUNT):
			from_wall += gaps[step] + radius * (1.0 if step == 0 else 2.0)
			var at: Vector2 = centre - toward_reef * (sea_half - from_wall) \
				+ along * (side * short_half * SPIT_AT)
			layout.blocks.append(Vector3(at.x, at.y, radius))

		layout.spits.append(Vector2i(first, SPIT_COUNT))


## A spit's gaps, from the sea wall out, in world units: the fore reef's tight channel
## against the wall and its second channel between the rocks.
static func spit_widths(short_half: float) -> PackedFloat32Array:
	var fore := channel_widths(short_half)
	return PackedFloat32Array([fore[0], fore[1]])


## One spit's gaps as the rocks the world built leave them, from the sea wall out: the
## first rock to the wall along the crossing axis, then rock to rock. Measured off the
## discs, like [method channels], so the section compares two representations.
func spit_gaps(spit: int, bounds: Rect2) -> PackedFloat32Array:
	var out := PackedFloat32Array()

	if id != REEF or spit < 0 or spit >= spits.size():
		return out

	var chain_along_x := bounds.size.x < bounds.size.y
	var run := spits[spit]
	var first := blocks[run.x]
	out.append(
		(first.y - bounds.position.y if chain_along_x else first.x - bounds.position.x) - first.z
	)

	for index in range(run.x, run.x + run.y - 1):
		var a := blocks[index]
		var b := blocks[index + 1]
		out.append(Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) - a.z - b.z)

	return out


## How far in front of the fore reef the cove stands, along the crossing axis, as a
## fraction of the short half-extent: 1150 at `reef`'s size, the spits' own distance
## turned onto the other axis.
const COVE_AT := 0.5

## How big one cove post is, as a fraction of the short half-extent. 59.8 at `reef`'s
## size.
const COVE_RADIUS := 0.026


## The reef's fifth part: a cove against the open-end wall, a refuge in the open sea.
static func _append_cove(layout: HungryLayout, bounds: Rect2) -> void:
	var chain_along_x := bounds.size.x < bounds.size.y
	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var centre := bounds.get_center()
	var along := Vector2(1.0, 0.0) if chain_along_x else Vector2(0.0, 1.0)
	var toward_reef := Vector2(0.0, 1.0) if chain_along_x else Vector2(1.0, 0.0)
	# The open end is the chain's HIGH end: `_reef_chain` lays the channels out tight
	# first from the low end, so the wall the cove stands on is the one past the widest.
	var wall_half := (bounds.size.x if chain_along_x else bounds.size.y) * 0.5
	var door := cove_door(short_half)
	var radius := short_half * COVE_RADIUS
	var middle := centre - toward_reef * short_half * COVE_AT \
		+ along * (wall_half - door - radius)
	var first := layout.blocks.size()

	# Sea side first, then reef side.
	for side in [-1.0, 1.0]:
		var at: Vector2 = middle + toward_reef * (side * (door * 0.5 + radius))
		layout.blocks.append(Vector3(at.x, at.y, radius))

	layout.coves.append(Vector2i(first, 2))


## The width of every cove door: the fore reef's tight channel.
static func cove_door(short_half: float) -> float:
	return channel_widths(short_half)[0]


## Whether [param at] is inside the cove: past the posts' front faces toward the wall,
## and between their outer faces along it. Only the reef has a cove.
func in_cove(at: Vector2, bounds: Rect2) -> bool:
	if id != REEF or coves.is_empty():
		return false

	var chain_along_x := bounds.size.x < bounds.size.y
	var along := Vector2(1.0, 0.0) if chain_along_x else Vector2(0.0, 1.0)
	var run := coves[0]
	var a := blocks[run.x]
	var b := blocks[run.x + 1]
	var line := Vector2(a.x, a.y).dot(along) - a.z
	var low := minf(a.x, b.x) - a.z if not chain_along_x else minf(a.y, b.y) - a.z
	var high := maxf(a.x, b.x) + a.z if not chain_along_x else maxf(a.y, b.y) + a.z
	var sideways := at.x if not chain_along_x else at.y

	return at.dot(along) > line and sideways > low and sideways < high



## How many lines of posts stand across the world. Five, so the range from a starting
## monster to the mass that ends the round is cut into six bands, one more than a line
## is wide for each tier of the other levels' gates.
const SHALLOWS_LINES := 5

## The tightest line's gap, as a fraction of the short half-extent: the reef's tight
## channel, 248 units at `shallows`' size, a radius of 124 and about 240 mass.
const SHALLOWS_TIGHT := 0.108

## The most open line's gap, same fraction: 690 units, radius 345, about 1860 mass.
## Past the mass that ends the round, so the outermost line is dodged round, never a wall.
const SHALLOWS_OPEN := 0.3

## How big a post is meant to be, same fraction: 69 units.
## The gaps are the design; the post radius is whatever makes each line meet both walls with every gap its width.
const SHALLOWS_POST := 0.03

## How much clear water stands between two lines, as a multiple of the OUTER line's gap.
const SHALLOWS_BAND := 1.2


## Lines of posts across the world whose gaps widen toward the open water.
static func _shallows(bounds: Rect2) -> HungryLayout:
	var out := HungryLayout.new()
	out.id = SHALLOWS

	var along_x := bounds.size.x >= bounds.size.y
	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var low := bounds.position.x if along_x else bounds.position.y
	var across_low := bounds.position.y if along_x else bounds.position.x
	var widths := shallows_widths(short_half)
	var previous := 0.0
	var at := low

	for line in range(widths.size()):
		var gap := widths[line]
		var radius := shallows_post_radius(short_half, gap)
		var posts := shallows_posts(short_half, gap)
		# The water on this line's shallow side is sized by THIS line's gap: it is the band
		# a monster that just came through the gap stands in. For the tightest line it is
		# the water against the shallow wall.
		at += gap * SHALLOWS_BAND + previous + radius
		var run := PackedVector3Array()

		for post in range(posts):
			var across := across_low + gap * float(post + 1) + radius * float(post * 2 + 1)
			run.append(
				Vector3(at, across, radius) if along_x else Vector3(across, at, radius)
			)

		_append_chain(out, run)
		previous = radius

	_append_pools(out, bounds)
	_append_groynes(out, bounds)
	_append_inlet(out, bounds)
	_append_sills(out, bounds)
	return out


## Every line's gap, tightest (nearest the shallow wall) first, in world units: evenly
## spaced from [constant SHALLOWS_TIGHT] to [constant SHALLOWS_OPEN]. Public because the
## level IS this list; `headless_round` measures the built lines against it.
static func shallows_widths(short_half: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()

	for line in range(SHALLOWS_LINES):
		out.append(short_half * lerpf(
			SHALLOWS_TIGHT, SHALLOWS_OPEN, float(line) / float(SHALLOWS_LINES - 1)
		))

	return out


## How many posts a line of [param gap] has: as many as come closest to posts of
## [constant SHALLOWS_POST] with every gap, walls included, exactly [param gap].
static func shallows_posts(short_half: float, gap: float) -> int:
	var span := short_half * 2.0
	return maxi(1, roundi((span - gap) / (gap + short_half * SHALLOWS_POST * 2.0)))


## The radius of one post in a line of [param gap]: what is left of the span once its
## gaps are taken out, shared between its posts. Derived, like a harbour post.
static func shallows_post_radius(short_half: float, gap: float) -> float:
	var posts := shallows_posts(short_half, gap)
	return (short_half * 2.0 - gap * float(posts + 1)) / float(posts * 2)


## Which band [param at] stands in: 0 behind the tightest line, [constant SHALLOWS_LINES] in the open water; -1 outside the shallows.
## Unlike a harbour, "behind" is past a line's back faces: the band behind is the room and the gap is the way in.
func shallows_band(at: Vector2, bounds: Rect2) -> int:
	if id != SHALLOWS:
		return -1

	var along_x := bounds.size.x >= bounds.size.y
	var here := at.x if along_x else at.y

	for line in range(chains.size()):
		var post := blocks[chains[line].x]
		var line_at := post.x if along_x else post.y

		if here < line_at - post.z:
			return line

	return chains.size()



## How big a rock pool's post is, as a fraction of the short half-extent: 103.5 units at
## `shallows`' size.
const POOL_RADIUS := 0.045


## The shallows' second part: a rock pool in each corner of the open water.
static func _append_pools(layout: HungryLayout, bounds: Rect2) -> void:
	var along_x := bounds.size.x >= bounds.size.y
	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var door := pool_door(short_half)
	var radius := short_half * POOL_RADIUS
	var off := door + radius

	for side in [-1.0, 1.0]:
		var corner := Vector2(bounds.end.x, bounds.position.y if side < 0.0 else bounds.end.y) \
			if along_x else Vector2(bounds.position.x if side < 0.0 else bounds.end.x, bounds.end.y)
		var at := corner - Vector2(off * signf(corner.x - bounds.get_center().x),
			off * signf(corner.y - bounds.get_center().y))
		layout.pools.append(Vector2i(layout.blocks.size(), 1))
		layout.blocks.append(Vector3(at.x, at.y, radius))


## The width of both of a rock pool's doors: the shallows' tightest line.
static func pool_door(short_half: float) -> float:
	return shallows_widths(short_half)[0]


## Which rock pool [param at] is inside, or -1: further into the corner than the post's
## centre on both axes. The doors are on those two lines, so a point in a doorway counts,
## as a point between two harbour posts does.
func pool_of(at: Vector2, bounds: Rect2) -> int:
	if id != SHALLOWS:
		return -1

	var centre := bounds.get_center()

	for index in range(pools.size()):
		var post := blocks[pools[index].x]
		var corner := Vector2(signf(post.x - centre.x), signf(post.y - centre.y))

		if (at.x - post.x) * corner.x > 0.0 and (at.y - post.y) * corner.y > 0.0:
			return index

	return -1


## Whether [param at] is inside either rock pool.
func in_pool(at: Vector2, bounds: Rect2) -> bool:
	return pool_of(at, bounds) >= 0



## Which of the last line's posts each groyne joins, counted in from each end: the second.
## With five posts the groynes cut the open water into a middle bay and two corner bays, each keeping its rock pool.
const GROYNE_JOINT := 1


## The shallows' third part: two groynes across the open water, from the last line to
## the open wall.
static func _append_groynes(layout: HungryLayout, bounds: Rect2) -> void:
	var along_x := bounds.size.x >= bounds.size.y
	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var doors := groyne_doors(short_half)
	var last := layout.chains[layout.chains.size() - 1]
	var open_wall := bounds.end.x if along_x else bounds.end.y

	for which in [GROYNE_JOINT, last.y - 1 - GROYNE_JOINT]:
		var joint := layout.blocks[last.x + which]
		var face := (joint.x if along_x else joint.y) + joint.z
		var across := joint.y if along_x else joint.x
		var radius := groyne_post_radius(open_wall - face, doors)
		var at := face
		layout.groynes.append(Vector2i(layout.blocks.size(), doors.size() - 1))

		for door in range(doors.size() - 1):
			at += doors[door] + radius
			layout.blocks.append(Vector3(at, across, radius) if along_x else Vector3(across, at, radius))
			at += radius


## A groyne's doors from the last line out to the open wall, in world units: the
## shallows' first three gaps, tightest first.
static func groyne_doors(short_half: float) -> PackedFloat32Array:
	return shallows_widths(short_half).slice(0, 3)


## The radius of a groyne's posts across [param span] of open water with [param doors]
## in it: what the doors leave, shared between the posts.
static func groyne_post_radius(span: float, doors: PackedFloat32Array) -> float:
	var total := 0.0

	for door in doors:
		total += door

	return (span - total) / float((doors.size() - 1) * 2)


## Which bay of the open water [param at] is in, counted from the short axis's low wall
## (0 south of the first groyne, 1 between them, 2 north of the second), or -1 if it is
## not in the open water at all — behind the last line, or anything but the shallows.
func bay_of(at: Vector2, bounds: Rect2) -> int:
	if id != SHALLOWS or groynes.is_empty() or shallows_band(at, bounds) != chains.size():
		return -1

	var along_x := bounds.size.x >= bounds.size.y
	var here := at.y if along_x else at.x
	var bay := 0

	for run in groynes:
		var post := blocks[run.x]

		if here > (post.y if along_x else post.x):
			bay += 1

	return bay



## How big one of the inlet's posts is, as a fraction of the short half-extent: 36.8 units
## at `shallows`' size, a groyne's post.
const INLET_RADIUS := 0.016


## The shallows' fourth part: an inlet in the middle of the open wall, the middle bay's
## room.
static func _append_inlet(layout: HungryLayout, bounds: Rect2) -> void:
	var along_x := bounds.size.x >= bounds.size.y
	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var door := inlet_door(short_half)
	var radius := short_half * INLET_RADIUS
	var open_wall := bounds.end.x if along_x else bounds.end.y
	var middle := bounds.get_center().y if along_x else bounds.get_center().x
	# The middle bay's centre across: halfway between the two groynes, which is the
	# world's centre line while the last line is symmetric, and the bay it stands in if
	# it ever is not.
	if layout.groynes.size() == 2:
		var a := layout.blocks[layout.groynes[0].x]
		var b := layout.blocks[layout.groynes[1].x]
		middle = ((a.y + b.y) if along_x else (a.x + b.x)) * 0.5

	var out_at := open_wall - door - radius
	var first := layout.blocks.size()

	for side in [-1.0, 1.0]:
		var across: float = middle + side * (door * 0.5 + radius)
		layout.blocks.append(Vector3(out_at, across, radius) if along_x else Vector3(across, out_at, radius))

	layout.inlets.append(Vector2i(first, 2))


## The width of every inlet door: the shallows' tightest line, a rock pool's door.
static func inlet_door(short_half: float) -> float:
	return shallows_widths(short_half)[0]


## Whether [param at] is inside the inlet: past the posts' front face toward the open
## wall, and between their outer faces along it. Past the FRONT face counts, as a cove's
## does: a point between the two posts is past the line a monster outgrows.
func in_inlet(at: Vector2, bounds: Rect2) -> bool:
	if id != SHALLOWS or inlets.is_empty():
		return false

	var along_x := bounds.size.x >= bounds.size.y
	var a := blocks[inlets[0].x]
	var b := blocks[inlets[0].x + 1]
	var front := (a.x if along_x else a.y) - a.z
	var low := (minf(a.y, b.y) if along_x else minf(a.x, b.x)) - a.z
	var high := (maxf(a.y, b.y) if along_x else maxf(a.x, b.x)) + a.z
	var here := at.x if along_x else at.y
	var sideways := at.y if along_x else at.x

	return here > front and sideways > low and sideways < high



## Where the sills stand: band, then the posts of the line inside it they are joined to,
## counted from that line's middle post. One in the second line's band, two in the third's,
## staggered so a detour round one never runs into the next.
const SILLS := {2: [0], 3: [-1, 1]}


## The shallows' fifth part: a post across a band, standing the tightest line's gap off a
## post of the line inside it and grown until its doors to the line outside close to that
## gap too.
static func _append_sills(layout: HungryLayout, bounds: Rect2) -> void:
	var along_x := bounds.size.x >= bounds.size.y
	var door := sill_door(minf(bounds.size.x, bounds.size.y) * 0.5)

	for band: int in SILLS:
		if band < 1 or band >= layout.chains.size():
			continue

		var inner := layout.chains[band - 1]
		var outer := layout.chains[band]

		for offset: int in SILLS[band]:
			var joint := layout.blocks[inner.x + int((inner.y - 1) * 0.5) + offset]
			var low := 0.0
			var high := door

			for _i in range(48):
				var radius := (low + high) * 0.5

				if layout.clearance(outer, _sill_at(joint, door, radius, along_x), radius) > door:
					low = radius
				else:
					high = radius

			var at := _sill_at(joint, door, low, along_x)
			layout.sills.append(Vector2i(layout.blocks.size(), 1))
			layout.blocks.append(Vector3(at.x, at.y, low))


static func _sill_at(joint: Vector3, door: float, radius: float, along_x: bool) -> Vector2:
	var off := joint.z + door + radius
	return Vector2(joint.x + off, joint.y) if along_x else Vector2(joint.x, joint.y + off)


## The width of every sill door: the shallows' tightest line.
static func sill_door(short_half: float) -> float:
	return shallows_widths(short_half)[0]


## The narrowest water between a disc of [param radius] at [param at] and the rocks of
## [param run] (`(first, count)` into [member blocks]).
func clearance(run: Vector2i, at: Vector2, radius: float) -> float:
	var out := INF

	for index in range(run.x, run.x + run.y):
		var rock := blocks[index]
		out = minf(out, at.distance_to(Vector2(rock.x, rock.y)) - rock.z - radius)

	return out



## One barrier of rocks [param behind] units along the crossing axis from the world's
## centre, leaving [param gaps] between them in order from the chain axis's low end.
static func _reef_chain(bounds: Rect2, behind: float, gaps: PackedFloat32Array) -> PackedVector3Array:
	var out := PackedVector3Array()

	# The chain runs along the SHORTER axis, so it is a barrier rather than a central
	# reservation. `slalom` reads the same rectangle and takes the opposite answer,
	# because a slalom is a thing you go along and a reef is a thing you go through.
	var along_x := bounds.size.x < bounds.size.y
	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var centre := bounds.get_center()

	var radius := short_half * REEF_RADIUS

	# Laid out from one end so the cumulative sum is the position, rather than from the
	# middle outward: the channels are not symmetric, so there is no middle to work from.
	var span := 0.0

	for gap in gaps:
		span += gap + radius * 2.0

	var along := -span * 0.5

	for step in range(gaps.size() + 1):
		if step > 0:
			along += gaps[step - 1] + radius * 2.0

		out.append(
			Vector3(centre.x + along, centre.y + behind, radius) if along_x
			else Vector3(centre.x + behind, centre.y + along, radius)
		)

	return out


static func _append_chain(layout: HungryLayout, chain: PackedVector3Array) -> void:
	layout.chains.append(Vector2i(layout.blocks.size(), chain.size()))
	layout.blocks.append_array(chain)


## The four channel widths, tight end first, in world units.
static func channel_widths(short_half: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()

	for step in range(REEF_COUNT - 1):
		out.append(short_half * lerpf(
			REEF_TIGHT, REEF_WIDE, float(step) / float(REEF_COUNT - 2)
		))

	return out


## The back reef's four gaps, door first, in world units.
static func back_reef_widths(short_half: float) -> PackedFloat32Array:
	var fore := channel_widths(short_half)
	var door := fore[fore.size() - 1]
	var rest := 0.0

	for index in range(fore.size() - 1):
		rest += fore[index]

	var gate := rest / float(fore.size() - 1)
	var out := PackedFloat32Array([door])

	for _step in range(fore.size() - 1):
		out.append(gate)

	return out


## How much clear floor the barrier leaves at each end, as a fraction of the short
## half-extent.
static func reef_end_fraction() -> float:
	var span := 0.0

	for gap in channel_widths(1.0):
		span += gap + REEF_RADIUS * 2.0

	return 1.0 - span * 0.5 - REEF_RADIUS



func is_empty() -> bool:
	return blocks.is_empty()


func count() -> int:
	return blocks.size()


## How much floor the rocks stand on, in square units.
func covered_area() -> float:
	var total := 0.0

	for block in blocks:
		total += PI * block.z * block.z

	return total


## Whether a circle of [param radius] at [param at] overlaps anything solid.
func blocked(at: Vector2, radius: float = 0.0) -> bool:
	for block in blocks:
		var clearance := block.z + radius

		if at.distance_squared_to(Vector2(block.x, block.y)) < clearance * clearance:
			return true

	return false


## The narrowest gap between two adjacent blocks, edge to edge.
func narrowest_gap() -> float:
	var narrowest := INF

	for i in range(blocks.size()):
		for j in range(i + 1, blocks.size()):
			var a := blocks[i]
			var b := blocks[j]
			var gap := (
				Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) - a.z - b.z
			)

			if gap < narrowest:
				narrowest = gap

	return narrowest


## The largest monster radius that fits through [method narrowest_gap].
func fits_through() -> float:
	var gap := narrowest_gap()
	return gap * 0.5 if is_finite(gap) else INF


## The narrowest way past anything solid, counting the arena's own walls.
func narrowest_gate(bounds: Rect2) -> float:
	var narrowest := narrowest_gap()

	for block in blocks:
		# A rock touching a wall closes that side: it is no gate at all, the same rule
		# [method gates] keeps (`width <= 0` is skipped). The warrens' open corners do this.
		for side in [
			block.x - bounds.position.x - block.z, bounds.end.x - block.x - block.z,
			block.y - bounds.position.y - block.z, bounds.end.y - block.y - block.z,
		]:
			if side > 0.0:
				narrowest = minf(narrowest, side)

	return narrowest


## The largest monster radius that fits through [method narrowest_gate].
func fits_through_gate(bounds: Rect2) -> float:
	var gap := narrowest_gate(bounds)
	return gap * 0.5 if is_finite(gap) else INF


## The WIDEST way past the tightest rock, counting the walls.
func widest_way_past(bounds: Rect2) -> float:
	if blocks.is_empty():
		return INF

	var tightest := INF

	for block in blocks:
		var widest := maxf(
			maxf(block.x - bounds.position.x, bounds.end.x - block.x),
			maxf(block.y - bounds.position.y, bounds.end.y - block.y)
		) - block.z
		tightest = minf(tightest, widest)

	return tightest


## The channels through one barrier, measured off the discs it is actually built of.
func channels(chain: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if chain < 0 or chain >= chains.size():
		return out

	var run := chains[chain]

	for index in range(run.x, run.x + run.y - 1):
		var here := blocks[index]
		var next := blocks[index + 1]
		var a := Vector2(here.x, here.y)
		var b := Vector2(next.x, next.y)
		var along := (b - a).normalized()
		var gap := a.distance_to(b) - here.z - next.z

		out.append({
			"mouth": a + along * (here.z + gap * 0.5),
			"width": gap,
			"normal": Vector2(-along.y, along.x),
		})

	return out


## Where to steer to get from [param from] to the far side of every barrier, for a
## monster of [param radius], or nothing when there is no way across for one that size.
func route_across(from: Vector2, radius: float, margin: float = 24.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var order: Array[int] = []

	for chain in range(chains.size()):
		order.append(chain)

	order.sort_custom(func(a: int, b: int) -> bool:
		return _chain_distance(a, from) < _chain_distance(b, from)
	)

	var here := from

	for chain in order:
		var best: Dictionary = {}
		var best_cost := INF

		for channel in channels(chain):
			if float(channel["width"]) < (radius + margin) * 2.0:
				continue

			var cost := here.distance_to(channel["mouth"])

			if cost < best_cost:
				best_cost = cost
				best = channel

		if best.is_empty():
			return PackedVector2Array()

		var mouth: Vector2 = best["mouth"]
		var normal: Vector2 = best["normal"]

		# Pointed from where the route is toward the far side of this barrier.
		if normal.dot(mouth - here) < 0.0:
			normal = -normal

		var standoff := blocks[chains[chain].x].z + radius + margin
		out.append(mouth - normal * standoff)
		out.append(mouth)
		out.append(mouth + normal * standoff)
		here = mouth + normal * standoff

	return out


## How far [param at] is from the line of one barrier's rocks.
func _chain_distance(chain: int, at: Vector2) -> float:
	var run := chains[chain]
	var first := blocks[run.x]
	var last := blocks[run.x + run.y - 1]
	var a := Vector2(first.x, first.y)
	var b := Vector2(last.x, last.y)
	var along := (b - a).normalized()
	return absf((at - a).dot(Vector2(-along.y, along.x)))


## The gaps between cyclic neighbours of one closed ring, edge to edge, in block order.
func ring_gates(ring: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()

	if ring < 0 or ring >= rings.size():
		return out

	var run := rings[ring]

	for step in range(run.y):
		var a := blocks[run.x + step]
		var b := blocks[run.x + (step + 1) % run.y]
		out.append(Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) - a.z - b.z)

	return out



## Every gap on the map a monster could be asked to pass through, rock to rock and rock to
## wall.
func gates(bounds: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	for i in range(blocks.size()):
		var a := blocks[i]
		var at := Vector2(a.x, a.y)

		for j in range(i + 1, blocks.size()):
			var b := blocks[j]
			var bt := Vector2(b.x, b.y)
			var across := (bt - at).normalized()
			var width := at.distance_to(bt) - a.z - b.z

			if width <= 0.0:
				continue

			var mouth := at + across * (a.z + width * 0.5)

			if not _gap_clear(bounds, mouth, width * 0.5, [i, j]):
				continue

			out.append({
				"a": i, "b": j, "mouth": mouth, "across": across,
				"normal": Vector2(-across.y, across.x), "width": width,
			})

		# The four walls: the perpendicular from the rock to each one.
		var walls := [
			[-1, Vector2.LEFT, at.x - bounds.position.x],
			[-2, Vector2.RIGHT, bounds.end.x - at.x],
			[-3, Vector2.UP, at.y - bounds.position.y],
			[-4, Vector2.DOWN, bounds.end.y - at.y],
		]

		for wall in walls:
			var across: Vector2 = wall[1]
			var width: float = float(wall[2]) - a.z

			if width <= 0.0:
				continue

			var mouth := at + across * (a.z + width * 0.5)

			if not _gap_clear(bounds, mouth, width * 0.5, [i]):
				continue

			out.append({
				"a": i, "b": int(wall[0]), "mouth": mouth, "across": across,
				"normal": Vector2(-across.y, across.x), "width": width,
			})

	return out


## Whether the circle across a gap is empty of everything but the gap's own two sides.
## The wall half stops the reef's end rock and the far wall being reported as a gate.
func _gap_clear(bounds: Rect2, mouth: Vector2, reach: float, except: Array) -> bool:
	if not bounds.grow(1.0).encloses(Rect2(mouth - Vector2(reach, reach), Vector2(reach, reach) * 2.0)):
		return false

	for k in range(blocks.size()):
		if except.has(k):
			continue

		var c := blocks[k]

		if mouth.distance_to(Vector2(c.x, c.y)) < reach + c.z:
			return false

	return true


## Whether a monster of [param radius] can get through one gap from [method gates], found
## by a flood fill on the geometry rather than by comparing its width.
func gate_passes(bounds: Rect2, gate: Dictionary, radius: float, cell: float = 6.0) -> bool:
	var mouth: Vector2 = gate["mouth"]
	var across: Vector2 = gate["across"]
	var normal: Vector2 = gate["normal"]
	var half_width := float(gate["width"]) * 0.5
	var half_rows := int(ceil((radius + cell * 3.0) / cell))
	var columns := int(ceil(half_width * 2.0 / cell)) + 1
	var rows := half_rows * 2 + 1
	var inner := bounds.grow(-radius)
	var free := PackedByteArray()
	free.resize(columns * rows)

	for row in range(rows):
		for column in range(columns):
			var at := mouth \
				+ across * (-half_width + float(column) * cell) \
				+ normal * (float(row - half_rows) * cell)
			free[row * columns + column] = 1 if inner.has_point(at) and not blocked(at, radius) else 0

	var seen := PackedByteArray()
	seen.resize(free.size())
	var queue := PackedInt32Array()

	for index in range(half_rows * columns):
		if free[index] == 1:
			seen[index] = 1
			queue.append(index)

	var head := 0

	while head < queue.size():
		var index := queue[head]
		head += 1

		if index / columns > half_rows:
			return true

		for next in _neighbours(index, columns, rows):
			if free[next] == 1 and seen[next] == 0:
				seen[next] = 1
				queue.append(next)

	return false


static func _neighbours(index: int, columns: int, rows: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var column := index % columns
	var row := index / columns

	if column > 0:
		out.append(index - 1)
	if column < columns - 1:
		out.append(index + 1)
	if row > 0:
		out.append(index - columns)
	if row < rows - 1:
		out.append(index + columns)

	return out


## The whole-world sweep: which of the floor a monster of [param radius] can get to from
## [param from], sampled on a grid of [param cell].
func reach(bounds: Rect2, from: Vector2, radius: float, cell: float = 24.0) -> Dictionary:
	var grid := _grid(bounds, radius, cell)
	var columns: int = grid["columns"]
	var rows: int = grid["rows"]
	var free: PackedByteArray = grid["free"]
	var start := _cell_of(bounds, from, cell, columns, rows)
	var seen := _fill(free, columns, rows, start, _diagonal_check(bounds, radius, cell, columns))
	var total := 0
	var reached := 0
	var stranded := PackedVector2Array()

	for index in range(free.size()):
		if free[index] == 0:
			continue

		total += 1

		if seen[index] == 1:
			reached += 1
		else:
			stranded.append(_centre_of(bounds, index, cell, columns))

	return {"free": total, "reached": reached, "stranded": stranded}


## The biggest stretch of floor a disc of [param radius] can move about in, as a Dictionary of the grid, the reached cells and counts.
## Used so a spawn never lands in a pocket the thing cannot leave; every free cell is flooded once.
func main_region(bounds: Rect2, radius: float, cell: float = 24.0) -> Dictionary:
	var grid := _grid(bounds, radius, cell)
	var columns: int = grid["columns"]
	var rows: int = grid["rows"]
	var free: PackedByteArray = grid["free"]
	var diagonal := _diagonal_check(bounds, radius, cell, columns)
	var taken := PackedByteArray()
	taken.resize(free.size())
	var best := PackedByteArray()
	best.resize(free.size())
	var best_count := 0
	var total := 0

	for index in range(free.size()):
		if free[index] == 1:
			total += 1

	for index in range(free.size()):
		if free[index] == 0 or taken[index] == 1:
			continue

		var seen := _fill(free, columns, rows, index, diagonal)
		var count := 0

		for at in range(seen.size()):
			if seen[at] == 1:
				taken[at] = 1
				count += 1

		if count > best_count:
			best_count = count
			best = seen

		# Past half, nothing left can be bigger.
		if best_count * 2 > total:
			break

	return {
		"columns": columns, "rows": rows, "cell": cell, "seen": best,
		"reached": best_count, "free": total,
	}


## Whether [param at] stands in [param region] ([method main_region]'s answer for the same bounds).
## The cell's eight neighbours count too, since a point at a rock's clearance can sit in a cell whose centre is just inside it.
static func in_region(region: Dictionary, bounds: Rect2, at: Vector2) -> bool:
	var columns: int = region["columns"]
	var rows: int = region["rows"]
	var seen: PackedByteArray = region["seen"]
	var home := _cell_of(bounds, at, float(region["cell"]), columns, rows)

	if home < 0:
		return false

	if seen[home] == 1:
		return true

	for next in _neighbours(home, columns, rows):
		if seen[next] == 1:
			return true

	var column := home % columns
	var row := home / columns

	for dy in [-1, 1]:
		for dx in [-1, 1]:
			var c: int = column + dx
			var r: int = row + dy

			if c >= 0 and r >= 0 and c < columns and r < rows and seen[r * columns + c] == 1:
				return true

	return false


## A route from [param from] to [param to] for a monster of [param radius], as waypoints
## no straight leg of which passes through a rock, or nothing when there is none.
func route_to(bounds: Rect2, from: Vector2, to: Vector2, radius: float, cell: float = 24.0) -> PackedVector2Array:
	var grid := _grid(bounds, radius, cell)
	var columns: int = grid["columns"]
	var rows: int = grid["rows"]
	var free: PackedByteArray = grid["free"]
	var start := _cell_of(bounds, from, cell, columns, rows)
	var goal := _cell_of(bounds, to, cell, columns, rows)

	if start < 0 or goal < 0 or free[start] == 0 or free[goal] == 0:
		return PackedVector2Array()

	var parent := PackedInt32Array()
	parent.resize(free.size())
	parent.fill(-1)
	parent[start] = start
	var queue := PackedInt32Array([start])
	var head := 0

	var diagonal := _diagonal_check(bounds, radius, cell, columns)

	while head < queue.size() and parent[goal] == -1:
		var index := queue[head]
		head += 1

		for next in _steps(index, columns, rows, free, diagonal):
			if free[next] == 1 and parent[next] == -1:
				parent[next] = index
				queue.append(next)

	if parent[goal] == -1:
		return PackedVector2Array()

	var path := PackedVector2Array([to])
	var walk := parent[goal]

	while walk != start:
		path.append(_centre_of(bounds, walk, cell, columns))
		walk = parent[walk]

	path.append(from)
	path.reverse()

	var out := PackedVector2Array()
	var here := 0

	while here < path.size() - 1:
		var furthest := here + 1

		for ahead in range(path.size() - 1, here, -1):
			if _clear_line(path[here], path[ahead], radius, cell * 0.5):
				furthest = ahead
				break

		out.append(path[furthest])
		here = furthest

	return out


func _clear_line(from: Vector2, to: Vector2, radius: float, step: float) -> bool:
	var steps := maxi(1, int(ceil(from.distance_to(to) / step)))

	for index in range(steps + 1):
		if blocked(from.lerp(to, float(index) / float(steps)), radius):
			return false

	return true


func _grid(bounds: Rect2, radius: float, cell: float) -> Dictionary:
	var columns := int(floor(bounds.size.x / cell))
	var rows := int(floor(bounds.size.y / cell))
	var inner := bounds.grow(-radius)
	var free := PackedByteArray()
	free.resize(columns * rows)

	for index in range(columns * rows):
		var at := _centre_of(bounds, index, cell, columns)
		free[index] = 1 if inner.has_point(at) and not blocked(at, radius) else 0

	return {"columns": columns, "rows": rows, "free": free}


static func _centre_of(bounds: Rect2, index: int, cell: float, columns: int) -> Vector2:
	return bounds.position + Vector2(
		(float(index % columns) + 0.5) * cell, (float(index / columns) + 0.5) * cell
	)


static func _cell_of(bounds: Rect2, at: Vector2, cell: float, columns: int, rows: int) -> int:
	var column := int(floor((at.x - bounds.position.x) / cell))
	var row := int(floor((at.y - bounds.position.y) / cell))

	if column < 0 or row < 0 or column >= columns or row >= rows:
		return -1

	return row * columns + column


## Eight ways out of a cell rather than four, because a diagonal gate's funnel can leave a free point with both orthogonal neighbours inside rocks.
## A diagonal step is taken when either orthogonal neighbour is free or the step's midpoint is clear, so it cannot hop between two rocks.
static func _steps(index: int, columns: int, rows: int, free: PackedByteArray, diagonal: Callable) -> PackedInt32Array:
	var out := _neighbours(index, columns, rows)
	var column := index % columns
	var row := index / columns

	for dy in [-1, 1]:
		for dx in [-1, 1]:
			var c: int = column + dx
			var r: int = row + dy

			if c < 0 or r < 0 or c >= columns or r >= rows:
				continue

			var next: int = r * columns + c

			if free[next] == 0:
				continue

			if free[row * columns + c] == 1 or free[r * columns + column] == 1 or diagonal.call(index, next):
				out.append(next)

	return out


func _diagonal_check(bounds: Rect2, radius: float, cell: float, columns: int) -> Callable:
	return func(from: int, to: int) -> bool:
		var mid := (_centre_of(bounds, from, cell, columns) + _centre_of(bounds, to, cell, columns)) * 0.5
		return not blocked(mid, radius)


static func _fill(free: PackedByteArray, columns: int, rows: int, start: int, diagonal: Callable) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(free.size())

	if start < 0 or free[start] == 0:
		return seen

	seen[start] = 1
	var queue := PackedInt32Array([start])
	var head := 0

	while head < queue.size():
		var index := queue[head]
		head += 1

		for next in _steps(index, columns, rows, free, diagonal):
			if free[next] == 1 and seen[next] == 0:
				seen[next] = 1
				queue.append(next)

	return seen



## Pushes one moving circle out of anything it is inside, and takes the velocity with it.
func depth_in_rocks(at: Vector2, radius: float) -> float:
	var deepest := 0.0
	for block in blocks:
		var depth := block.z + radius - at.distance_to(Vector2(block.x, block.y))
		deepest = maxf(deepest, depth)
	return deepest


func resolve_circle(state: Dot2DState, radius: float) -> bool:
	if state == null or blocks.is_empty():
		return false

	var moved := false

	for block in blocks:
		var at := Vector2(block.x, block.y)
		var clearance := block.z + radius
		var away := state.position - at
		var distance := away.length()

		if distance >= clearance:
			continue

		# Dead centre is unreachable in play and reachable by a spawn, a teleport or a
		# test. A fixed direction is arbitrary and correct; the alternative is a NaN
		# normal and a piece at infinity.
		var normal := away / distance if distance > 0.001 else Vector2.RIGHT
		state.position = at + normal * clearance
		moved = true

		var into := state.velocity.dot(normal)

		if into < 0.0:
			state.velocity -= normal * into

	return moved


## A point outside everything solid, searched outward from [param at].
func nearest_clear(at: Vector2, radius: float, bounds: Rect2) -> Vector2:
	var here := at

	# Bounded, because two overlapping rocks can hand a point back and forth. Twelve is
	# far more than the three or four a real layout needs and still terminates.
	for _attempt in range(12):
		var pushed := here
		var hit := false

		for block in blocks:
			var block_at := Vector2(block.x, block.y)
			var clearance := block.z + radius
			var away := pushed - block_at
			var distance := away.length()

			if distance >= clearance:
				continue

			var normal := away / distance if distance > 0.001 else Vector2.RIGHT
			pushed = block_at + normal * clearance
			hit = true

		here = Vector2(
			clampf(pushed.x, bounds.position.x + radius, bounds.end.x - radius),
			clampf(pushed.y, bounds.position.y + radius, bounds.end.y - radius)
		)

		if not hit:
			break

	return here


func describe() -> Dictionary:
	return {
		"id": String(id),
		"blocks": blocks.size(),
		"chains": chains.size(),
		"rings": rings.size(),
		"spits": spits.size(),
		"gap": narrowest_gap() if not blocks.is_empty() else 0.0,
	}


func _to_string() -> String:
	return "HungryLayout(%s, %d blocks)" % [id, blocks.size()]
