extends "headless_round_base.gd"

## The level-by-level sections of the headless round suite (1 of 7).


## How far a route runs along the reef between leaving the first barrier and reaching the
## second: the walk the lagoon charges. Waypoints 2 and 3 are the fore exit and the back
## approach — see [method HungryLayout.route_across].
func _lagoon_walk(route: PackedVector2Array, chain_axis: Vector2) -> float:
	if route.size() < 6:
		return INF

	return absf((route[3] - route[2]).dot(chain_axis))


## A command at full reach toward [param to].
## [bot-drive-1]: what a route drive covered, printed beside the checks that ask where it
## got to, so a drive that was respawned past the gate or crawled reads differently.
func _drive_report(from: Vector2, route: PackedVector2Array, covered: float, ticks: int, ground: float) -> void:
	var length := 0.0
	var previous := from

	for point in route:
		length += previous.distance_to(point)
		previous = point

	var seconds := float(maxi(ticks, 1)) / float(TICK_RATE)
	print("        driven: covered %.0f of a %.0f-unit route (%.0f%%) in %d ticks, %.1f u/s against a ground speed of %.1f"
		% [covered, length, covered / maxf(length, 1.0) * 100.0, ticks, covered / seconds, ground / seconds])


## How far [param monster]'s ground speed takes it in one tick, at its first piece's mass.
func _ground_step(world: HungryWorld, monster: HungryMonster) -> float:
	if monster == null or monster.pieces.is_empty():
		return 0.0

	return world.tunables.max_speed \
		* world.tunables.mass_rules.speed_scale(monster.pieces[0].mass()) \
		* monster.speed_multiplier() \
		/ float(TICK_RATE)


## Respawns [param player] at [param from], grows it to [param mass] if that is above its
## start, and drives it at [param to] for twenty-four seconds (room for about 3000 units).
## Returns how far it got along the line.
func _straight_run(
	world: HungryWorld, player: int, from: Vector2, to: Vector2, mass: float
) -> float:
	world.spawn(player, from)
	_run_ticks(world, 2)

	var monster := world.monster_for(player)

	if monster == null or not monster.alive:
		return -INF

	if mass > monster.mass():
		world.feed_player(player, mass - monster.mass())
		_run_ticks(world, 2)

	var direction := (to - from).normalized()
	var furthest := -INF

	for _i in range(TICK_RATE * 24):
		world.tick({player: _full_reach(monster.centre(), to)})
		furthest = maxf(furthest, monster.centre().dot(direction))

	return furthest


## Every shallows band [param route] passes through from [param from], sampled every 12
## units: a planner's waypoints skip the stretch where a route bulges through a line.
func _bands_crossed(layout: HungryLayout, bounds: Rect2, from: Vector2, route: PackedVector2Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var previous := from

	for point in route:
		var steps := maxi(1, ceili(previous.distance_to(point) / 12.0))

		for k in range(steps + 1):
			var band := layout.shallows_band(previous.lerp(point, float(k) / float(steps)), bounds)

			if not band in out:
				out.append(band)

		previous = point

	out.sort()
	return out


## Drives [param monster] along [param route] at full reach, measuring depth into any rock,
## waypoints reached, progress along [param axis] and covered against ground speed.
## Prints the `[bot-drive-1]` line.
func _drive_route(
	world: HungryWorld, monster: HungryMonster, route: PackedVector2Array, axis: Vector2, budget: int
) -> Dictionary:
	var layout := world.layout
	var from := monster.centre()
	var reached := 0
	var deepest := INF
	var furthest := -INF
	var covered := 0.0
	var ground := 0.0
	var ticks := 0
	for _i in range(budget):
		if reached >= route.size():
			break

		if monster.centre().distance_to(route[reached]) < 40.0:
			reached += 1
			continue

		var was := monster.centre()
		ground += _ground_step(world, monster)
		world.tick({1: _full_reach(monster.centre(), route[reached])})
		covered += monster.centre().distance_to(was)
		ticks += 1
		furthest = maxf(furthest, monster.centre().dot(axis))

		for piece in monster.pieces:
			for block in layout.blocks:
				deepest = minf(
					deepest,
					piece.position().distance_to(Vector2(block.x, block.y)) - block.z - piece.radius()
				)

	_drive_report(from, route, covered, ticks, ground)
	return {
		"reached": reached, "deepest": deepest, "furthest": furthest, "covered": covered,
		"length": _route_length(from, route), "pace": covered / maxf(ground, 0.001),
	}


func _route_length(from: Vector2, route: PackedVector2Array) -> float:
	var length := 0.0
	var previous := from

	for point in route:
		length += previous.distance_to(point)
		previous = point

	return length


## The Gauntlet: a five-to-one corridor, and the first non-square world this game runs.
##
## A corridor is where the two world_size components disagree, so it is the only shape in which an `.x` read where `.y` was meant is findable; a square would pass every check below either way.
func _test_the_gauntlet() -> void:
	_section("the gauntlet")

	var preset := HungryPreset.gauntlet()

	if not _check(preset.validate().ok, "the preset is usable"):
		_done()
		return

	_check(
		preset.world_size.x > preset.world_size.y * 4.0,
		"and it is a corridor rather than a square",
		"%.0f by %.0f" % [preset.world_size.x, preset.world_size.y]
	)

	# The same area as Frenzy's square, so the mode is the SHAPE and not the density. A
	# corridor with the same food count in a quarter of the floor would be a starvation
	# mode as well, and there would be no telling which half was doing the work.
	var frenzy := HungryPreset.frenzy()
	var area := preset.world_size.x * preset.world_size.y
	var square := frenzy.world_size.x * frenzy.world_size.y

	_check(
		absf(area / square - 1.0) < 0.02,
		"with the same floor area as Frenzy",
		"%.0f against %.0f" % [area, square]
	)
	# The target is food standing on the floor, so the density is the target over the floor
	# that is left after the rocks; the living-field check measures the same thing, this one
	# is the arithmetic a preset argues in a comment.
	var covered := HungryLayout.for_id(
		preset.layout, Rect2(Vector2.ZERO, preset.world_size)
	).covered_area()
	var density := float(preset.food_target) / (area - covered)
	var frenzy_density := float(frenzy.food_target) / square

	_check(
		absf(density / frenzy_density - 1.0) < 0.03,
		"and the same amount of food on the floor that is left",
		"%.1f per million units against %.1f, with %.0f%% of it under rock"
			% [density * 1.0e6, frenzy_density * 1.0e6, covered / area * 100.0]
	)

	var world := _make_world(preset, SEED + 31)
	world.add_player(1, "Ada")
	_settle(world)

	var bounds := world.arena.bounds

	_check(
		absf(bounds.size.x - preset.world_size.x) < 0.5
			and absf(bounds.size.y - preset.world_size.y) < 0.5,
		"the arena is the shape the preset asked for",
		"%s" % str(bounds.size)
	)

	_the_gauntlet_part2(world, bounds)


func _the_gauntlet_part2(world: HungryWorld, bounds: Rect2) -> void:
	world.spawn(1, bounds.get_center())
	_settle(world)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a monster spawns in it"):
		_drop(world)
		_done()
		return

	# Walked into all four walls in turn, and it is the pair on the SHORT axis that a
	# square world can never test: a clamp using the wrong component would let a monster
	# out of the top and bottom of a corridor while the left and right looked perfect.
	var corners := {
		"east": Vector2(bounds.end.x + 4000.0, bounds.get_center().y),
		"west": Vector2(bounds.position.x - 4000.0, bounds.get_center().y),
		"north": Vector2(bounds.get_center().x, bounds.position.y - 4000.0),
		"south": Vector2(bounds.get_center().x, bounds.end.y + 4000.0),
	}

	for side in corners:
		var target: Vector2 = corners[side]

		for _i in range(TICK_RATE * 6):
			world.tick({1: _aim_at(monster.centre(), target)})

		var here := monster.centre()
		var out := (
			here.x < bounds.position.x - 1.0
			or here.x > bounds.end.x + 1.0
			or here.y < bounds.position.y - 1.0
			or here.y > bounds.end.y + 1.0
		)

		_check(not out, "and cannot walk out of the %s wall" % side, "at %s" % str(here))

	# It reached the far end. A corridor nothing can cross is one nobody meets anybody in.
	# Sixty seconds: a starting monster covers about 130 units a second with rocks to slide
	# round, and twenty passed only because the respawn put it most of the way there.
	for _i in range(TICK_RATE * 60):
		world.tick({1: _aim_at(monster.centre(), corners["east"])})

	_check(
		monster.centre().x > bounds.get_center().x + bounds.size.x * 0.3,
		"and can cross the length of it",
		"%.0f of %.0f" % [monster.centre().x - bounds.position.x, bounds.size.x]
	)

	# The food is spread over the whole corridor rather than bunched into the square the
	# generator would produce if it hashed into one component. Measured as the span of
	# what actually exists, because the count is right either way.
	var spread_x := 0.0
	var spread_y := 0.0
	var lowest := Vector2(INF, INF)
	var highest := Vector2(-INF, -INF)

	for grid_id in world.field.alive_ids():
		var at := world.field.position_of(grid_id)
		lowest = lowest.min(at)
		highest = highest.max(at)

	_the_gauntlet_part3(world, bounds, spread_x, spread_y, lowest, highest)


func _the_gauntlet_part3(world: HungryWorld, bounds: Rect2, spread_x: float, spread_y: float, lowest: Vector2, highest: Vector2) -> void:
	spread_x = highest.x - lowest.x
	spread_y = highest.y - lowest.y

	_check(
		spread_x > bounds.size.x * 0.8 and spread_y > bounds.size.y * 0.8,
		"and the food is spread over the whole of it",
		"%.0f by %.0f in a %.0f by %.0f room"
			% [spread_x, spread_y, bounds.size.x, bounds.size.y]
	)

	_drop(world)
	_done()


## The corridor's own level, and the question the warrens section could not ask.
##
## A slalom rock stands off one wall, so its lanes are wall-to-rock and neither is a rock-to-rock gap; asked the ring's `narrowest_gap` question it answers 646, which is not a gate.
func _test_the_slalom() -> void:
	_section("the slalom")

	var preset := HungryPreset.gauntlet()

	if not _check(preset.validate().ok, "the corridor preset is usable"):
		_done()
		return

	_check(
		preset.layout == HungryLayout.SLALOM,
		"and the corridor is not an empty box any more",
		"layout %s" % String(preset.layout)
	)

	var world := _make_world(preset, SEED + 83)
	world.add_player(1, "Bram")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout

	# Five rocks plus a harbour fence across each end; the fences are the harbours
	# section's, and everything below about lanes asks the five rocks alone.
	if not _check(
		layout != null
			and layout.count() == HungryLayout.SLALOM_COUNT + HungryLayout.HARBOUR_POSTS * 2,
		"five rocks stand down it, and a fence across each end (%d)"
			% (layout.count() if layout != null else -1)
	):
		_drop(world)
		_done()
		return

	# Derived, like the warrens: the same id and the same rectangle, twice.
	var again := HungryLayout.for_id(HungryLayout.SLALOM, bounds)
	var identical := again.count() == layout.count()

	for index in range(mini(again.count(), layout.count())):
		if not again.blocks[index].is_equal_approx(layout.blocks[index]):
			identical = false

	_check(identical, "and a second build of the same layout is the same rocks")

	var inside := true

	for block in layout.blocks:
		if not bounds.grow(-block.z).has_point(Vector2(block.x, block.y)):
			inside = false

	_check(inside, "and every one of them is wholly inside the corridor")

	# [b]They alternate, which is the whole of what makes the shortcut a decision.[/b]
	# Five rocks on the same side of the centre line is a wall with a corridor beside it,
	# and it is one constant's sign away at all times.
	var alternates := true
	var centre_across := bounds.get_center().y

	for index in range(HungryLayout.SLALOM_COUNT - 1):
		var here := layout.blocks[index].y - centre_across
		var next := layout.blocks[index + 1].y - centre_across

		if here * next >= 0.0:
			alternates = false

	_the_slalom_part2(preset, world, bounds, layout, alternates)


func _the_slalom_part2(preset: HungryPreset, world: HungryWorld, bounds: Rect2, layout: HungryLayout, alternates: bool) -> void:
	_check(
		alternates,
		"and they alternate sides, so the inside line changes wall at every rock"
	)

	# The two lanes, which are the level

	# The five rocks on their own: with the harbours on the map the narrowest gate
	# anywhere is a harbour door, which is a different tier and asked in its own section.
	var rocks := layout.part(0, HungryLayout.SLALOM_COUNT)
	var rules := world.tunables.mass_rules
	var gate := rocks.narrowest_gate(bounds)
	var fits := rocks.fits_through_gate(bounds)
	var admits := fits * fits / (rules.base_radius * rules.base_radius)

	_check(
		gate < rocks.narrowest_gap(),
		"the narrowest way past a rock is against a WALL, not against another rock",
		"%.0f against a wall, %.0f between two rocks" % [gate, rocks.narrowest_gap()]
	)
	_check(
		admits > preset.win_mass * 0.2 and admits < preset.win_mass * 0.45,
		"the inside lane admits a monster of about a third of the winning mass",
		"%.0f of %.0f, through a %.0f unit lane" % [admits, preset.win_mass, gate]
	)
	_check(
		rules.radius_for(preset.win_mass) > fits,
		"so a monster that has won has to take the long way round every rock",
		"%.0f against %.0f" % [rules.radius_for(preset.win_mass), fits]
	)

	# The long way round is open to it: a rock whose wide lane is also too narrow is a cork,
	# and the mode would end with the leader parked against it.
	var widest := world.layout.widest_way_past(bounds)
	_check(
		widest * 0.5 > rules.radius_for(preset.win_mass),
		"and the way round is open even to one that has already won",
		"%.0f unit lane against a radius of %.0f"
			% [widest, rules.radius_for(preset.win_mass)]
	)

	_the_slalom_a_rock_stops_somebody(world, bounds, layout)


## A rock stops somebody.
func _the_slalom_a_rock_stops_somebody(world: HungryWorld, bounds: Rect2, layout: HungryLayout) -> void:
	var rock: Vector3 = layout.blocks[0]
	var rock_at := Vector2(rock.x, rock.y)
	# Up the corridor from the first rock, on its own line, driving straight at it.
	world.spawn(1, Vector2(rock_at.x - rock.z * 3.0, rock_at.y))
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a monster spawns up the corridor"):
		_drop(world)
		_done()
		return

	# Aimed, not moved: this game steers by `aim` and `reach`, `move` is ignored.
	# Two legs, because a pointer held on a disc's centre holds the monster against its face:
	# four seconds at the rock, then the middle of the far lane beyond it.
	var piece_radius := monster.pieces[0].radius()
	var entered := false
	var lane_side := -signf(rock_at.y - bounds.get_center().y)
	var wall := bounds.position.y if lane_side < 0.0 else bounds.end.y
	var lane_mid := (rock_at.y + lane_side * rock.z + wall) * 0.5
	var legs := [
		[Vector2(rock_at.x + 4000.0, rock_at.y), TICK_RATE * 4],
		[Vector2(rock_at.x + rock.z * 3.0, lane_mid), TICK_RATE * 12],
	]

	for leg in legs:
		for _tick in range(int(leg[1])):
			_run_ticks(world, 1, {1: _full_reach(monster.centre(), leg[0])})

			if monster.alive and monster.pieces[0].state.position.distance_to(rock_at) \
					< rock.z + piece_radius - 1.0:
				entered = true

	_check(not entered, "and driving straight at a rock never puts it inside one")

	# Round it, rather than through it. The far side, reached at all, is the level
	# working: a walker that only ever gets pushed back is a wall, and the whole design
	# is that a rock is something you go past.
	_check(
		monster.alive and monster.pieces[0].state.position.x > rock_at.x + rock.z,
		"and it gets past the rock rather than stopping at it (%.0f past %.0f)"
			% [monster.pieces[0].state.position.x, rock_at.x + rock.z]
	)

	_drop(world)
	_done()


func _test_the_warrens() -> void:
	_section("the warrens")

	var preset := HungryPreset.warrens()

	if not _check(preset.validate().ok, "the preset is usable"):
		_done()
		return

	_check(
		preset.layout == HungryLayout.WARRENS,
		"and it is the first mode that asks for any geometry at all",
		"layout %s" % String(preset.layout)
	)
	_check(
		HungryPreset.classic().layout == HungryLayout.NONE
			and HungryPreset.frenzy().layout == HungryLayout.NONE,
		"and the two square modes are still empty boxes",
		"a layout nobody asked for would change every mode in the game"
	)

	var world := _make_world(preset, SEED + 57)
	world.add_player(1, "Ada")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout

	# Eight ring, four corner and four den rocks; the den is appended last, so blocks 0
	# and 1 below are still the ring's.
	if not _check(
		layout != null and layout.count() == HungryLayout.RING_COUNT + 4 + HungryLayout.DEN_COUNT,
		"sixteen rocks stand in it: the ring, the corners and the den",
		"%d" % (layout.count() if layout != null else -1)
	):
		_drop(world)
		_done()
		return

	# Derived and not stored: the same id and rectangle must give the same discs every time,
	# so a client can be told a name instead of a hundred and forty-four bytes of circles.
	var again := HungryLayout.for_id(HungryLayout.WARRENS, bounds)
	var identical := again.count() == layout.count()

	for index in range(mini(again.count(), layout.count())):
		if not again.blocks[index].is_equal_approx(layout.blocks[index]):
			identical = false

	_check(identical, "and a second build of the same layout is the same rocks")

	# Everything is inside the arena. A rock touching a wall is not crossing it, hence the
	# twentieth of a unit allowed: the open corners stand a hundredth into theirs.
	var inside := true

	for block in layout.blocks:
		var at := Vector2(block.x, block.y)

		if not bounds.grow(-block.z + 0.05).has_point(at):
			inside = false

	_check(inside, "and every one of them is wholly inside the arena")

	_the_warrens_the_gate_which_is_the_level(preset, world, bounds, layout)


## The gate, which is the level.
func _the_warrens_the_gate_which_is_the_level(preset: HungryPreset, world: HungryWorld, bounds: Rect2, layout: HungryLayout) -> void:
	# The one number the design rests on: mass is radius, so a gap is a mass limit
	# (`radius_for` inverted), and a changed constant would open the middle to everybody.
	var rules := world.tunables.mass_rules
	# [method HungryLayout.narrowest_gate], not `fits_through` (rock against rock alone): the
	# same call the slalom makes, since a gate against a wall gets nonsense from the other.
	# The RING's gate: the den's is narrower now, and `ring_gates(0)` asks the ring.
	var fits: float = Array(layout.ring_gates(0)).min() * 0.5
	var admits := fits * fits / (rules.base_radius * rules.base_radius)

	_check(
		admits > preset.win_mass * 0.2 and admits < preset.win_mass * 0.45,
		"the gates admit a monster of about a third of the winning mass",
		"%.0f of %.0f, through a %.0f unit gap" % [admits, preset.win_mass, fits * 2.0]
	)
	_check(
		rules.radius_for(preset.win_mass) > fits,
		"so a monster that has won cannot fit through one",
		"%.0f against %.0f" % [rules.radius_for(preset.win_mass), fits]
	)
	# [b]And splitting is the way through, which is the mode.[/b] Half the mass is
	# 1/sqrt(2) of the radius, so a monster up to twice the gate limit can halve itself and
	# fit — at the cost of the merge delay, in the most dangerous part of the map.
	_check(
		rules.radius_for(admits * 1.9 * 0.5) < fits,
		"and one twice that size fits by splitting",
		"%.0f mass halves to a radius of %.0f"
			% [admits * 1.9, rules.radius_for(admits * 1.9 * 0.5)]
	)

	_the_warrens_a_rock_stops_somebody(preset, world, bounds, layout, fits)


## A rock stops somebody.
func _the_warrens_a_rock_stops_somebody(preset: HungryPreset, world: HungryWorld, bounds: Rect2, layout: HungryLayout, fits: float) -> void:
	var ring: Vector3 = layout.blocks[0]
	var ring_at := Vector2(ring.x, ring.y)
	# Outside the ring, four degrees off the rock's centre line (80 units here): the drive
	# still meets the rock, and dead centre is the one approach with no side to slide off.
	var outside := bounds.get_center() \
		+ (ring_at - bounds.get_center()).rotated(deg_to_rad(4.0)) * 1.9

	world.spawn(1, outside)
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a monster spawns outside the ring"):
		_drop(world)
		_done()
		return

	var piece_radius := monster.pieces[0].radius()

	# Sampled every tick: a push-out that lets somebody through for one frame and recovers
	# is invisible in the last reading, and one frame in a rock is one frame of eating.
	var deepest := INF

	for _i in range(TICK_RATE * 20):
		world.tick({1: _aim_at(monster.centre(), bounds.get_center())})
		deepest = minf(deepest, monster.centre().distance_to(ring_at))

	_check(
		deepest > ring.z - 2.0,
		"and driving straight at a rock never puts it inside one, on any tick",
		"closest approach %.0f to the middle of a %.0f rock" % [deepest, ring.z]
	)

	# And it gets past anyway, which is the level working: a monster driven at a rock slides
	# along its face to a gate. Four degrees off it slides in; dead on the centre it stays.
	_check(
		monster.centre().distance_to(bounds.get_center()) < ring_at.length() * 0.5,
		"but slides round the face of it and in through a gate",
		"%.0f from the centre, the ring is at %.0f"
			% [monster.centre().distance_to(bounds.get_center()), ring_at.length()]
	)

	_the_warrens_the_same_push_on_the_predict(preset, world, bounds, layout, fits, ring, ring_at, monster, piece_radius)


## The same push on the prediction path.
func _the_warrens_the_same_push_on_the_predict(preset: HungryPreset, world: HungryWorld, bounds: Rect2, layout: HungryLayout, fits: float, ring: Vector3, ring_at: Vector2, monster: HungryMonster, piece_radius: float) -> void:
	# A client predicts with `simulate_piece` and a reconciliation replays it, so a push-out
	# only the authority applied would read as packet loss against every rock.
	var predicted := _make_world(preset, SEED + 57)
	predicted.is_authority = false
	predicted.add_player(2, "Bo")
	_settle(predicted)
	predicted.spawn(2, ring_at)
	_run_ticks(predicted, 1)

	var mirror := predicted.monster_for(2)
	var mirror_piece := mirror.pieces[0] if mirror != null and not mirror.pieces.is_empty() \
		else null

	if mirror_piece != null:
		mirror_piece.state.position = ring_at
		predicted.simulate_piece(
			mirror_piece, mirror, _aim_at(ring_at, bounds.get_center()), 1.0 / TICK_RATE, 1
		)

	_check(
		mirror_piece != null
			and mirror_piece.position().distance_to(ring_at) >= ring.z - 1.0,
		"a client predicting itself is pushed out by the same rocks",
		"%.0f from the middle of a %.0f rock"
			% [mirror_piece.position().distance_to(ring_at) if mirror_piece != null else -1.0,
				ring.z]
	)

	# A client is TOLD which layout, and builds it. Nothing about the rocks travels.
	predicted.adopt_layout(HungryLayout.WARRENS)
	_check(
		predicted.layout.count() == layout.count()
			and predicted.layout.narrowest_gate(bounds) == layout.narrowest_gate(bounds),
		"and builds the same sixteen from one name in the hello"
	)

	_drop(predicted)

	_the_warrens_a_small_monster_gets_through(preset, world, bounds, layout, fits, ring_at, monster, piece_radius)


## A small monster gets through, a big one does not.
func _the_warrens_a_small_monster_gets_through(preset: HungryPreset, world: HungryWorld, bounds: Rect2, layout: HungryLayout, fits: float, ring_at: Vector2, monster: HungryMonster, piece_radius: float) -> void:
	# The gate between the first two ring rocks, on the bearing halfway between them.
	var second: Vector3 = layout.blocks[1]
	var gate := (ring_at + Vector2(second.x, second.y)) * 0.5
	var approach := bounds.get_center() + (gate - bounds.get_center()) * 1.75

	world.spawn(1, approach)
	_run_ticks(world, 2)

	for _i in range(TICK_RATE * 14):
		world.tick({1: _aim_at(monster.centre(), bounds.get_center())})

	var small_reach := monster.centre().distance_to(bounds.get_center())

	_check(
		small_reach < Vector2(ring_at - bounds.get_center()).length() * 0.8,
		"a starting monster fits through a gate and reaches the middle",
		"%.0f from the centre, the ring is at %.0f"
			% [small_reach, Vector2(ring_at - bounds.get_center()).length()]
	)

	# The same journey at the winning mass. Nothing else changes — same seed, same gate,
	# same commands — so the only thing that can make the second run end somewhere else is
	# the radius.
	world.spawn(1, approach)
	_run_ticks(world, 2)
	# Just short of the winning mass: reaching it ends the round and the next respawns every
	# player as a starter, which this check would read as the grown monster getting through.
	world.feed_player(1, preset.win_mass * 0.97 - monster.mass())
	_run_ticks(world, 2)

	var grown := monster.pieces[0].radius()

	for _i in range(TICK_RATE * 14):
		world.tick({1: _aim_at(monster.centre(), bounds.get_center())})

	var big_reach := monster.centre().distance_to(bounds.get_center())

	_check(
		grown > fits,
		"a monster at the winning mass is too wide for the gate",
		"a radius of %.0f against %.0f" % [grown, fits]
	)
	_check(
		big_reach > small_reach + 100.0,
		"and the same run leaves it outside the ring",
		"%.0f from the centre, where the small one got to %.0f"
			% [big_reach, small_reach]
	)

	_the_warrens_nothing_edible_is_buried(preset, world, layout, piece_radius)


## Nothing edible is buried.
func _the_warrens_nothing_edible_is_buried(preset: HungryPreset, world: HungryWorld, layout: HungryLayout, piece_radius: float) -> void:
	# [b]A crumb inside a rock cannot be eaten and never expires.[/b] It holds its slot
	# against the field's budget for ever, so a mode with a layout would quietly run at
	# seven eighths of the food it claims with nothing anywhere saying so.
	var buried := 0

	for grid_id in world.field.alive_ids():
		if layout.blocked(world.field.position_of(grid_id), world.field.radius_of(grid_id)):
			buried += 1

	_check(buried == 0, "nothing edible is standing inside a rock", "%d buried" % buried)
	_check(
		world.field.alive_count() > preset.food_target,
		"and the field still fills to the target it asks for",
		"%d alive against a food target of %d"
			% [world.field.alive_count(), preset.food_target]
	)

	# And nobody spawns inside one

	var spawned_inside := 0

	for player in range(10, 30):
		world.add_player(player, "P%d" % player)
		world.spawn(player)

		var born := world.monster_for(player)

		if born != null and born.alive and layout.blocked(born.centre(), piece_radius):
			spawned_inside += 1

	_check(
		spawned_inside == 0,
		"and twenty spawns all land on floor rather than in a rock",
		"%d inside" % spawned_inside
	)

	_drop(world)
	_done()
