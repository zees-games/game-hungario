extends "headless_round_levels_inlet.gd"

## The level-by-level sections of the headless round suite (7 of 7).


## The corridor's ends: a fence of posts across each, with a harbour behind it that a starting monster walks into and one that has fed is held out of.
##
## Asked at the size each side of the fence is for, like the den, then driven along a [method HungryLayout.route_to] route.
func _test_the_harbours() -> void:
	_section("the harbours")

	var preset := HungryPreset.gauntlet()
	var world := _make_world(preset, SEED + 223)
	world.add_player(1, "Ada")
	_settle(world)

	var bounds := world.arena.bounds
	var centre := bounds.get_center()
	var layout := world.layout
	var rules := world.tunables.mass_rules

	if not _check(
		layout != null and layout.chains.size() == 2,
		"the corridor has a fence across each end",
		"%d fences" % (layout.chains.size() if layout != null else -1)
	):
		_drop(world)
		_done()
		return

	# The doors, measured off the discs: the gaps between posts and the two gaps between
	# the end posts and the side walls. One description, two representations — the
	# constant says 0.3 of the half-width, and this is what the world built.
	var doors := PackedFloat32Array()
	var fences_in_line := true

	for chain in range(layout.chains.size()):
		var run: Vector2i = layout.chains[chain]
		var first := layout.blocks[run.x]
		var last := layout.blocks[run.x + run.y - 1]

		if run.y != HungryLayout.HARBOUR_POSTS:
			fences_in_line = false

		for index in range(run.y):
			if absf(layout.blocks[run.x + index].x - first.x) > 0.5:
				fences_in_line = false

		doors.append(first.y - first.z - bounds.position.y)

		for channel in layout.channels(chain):
			doors.append(float(channel["width"]))

		doors.append(bounds.end.y - last.y - last.z)

	_check(
		fences_in_line,
		"each fence is three posts standing square across the corridor"
	)

	var door: float = Array(doors).min()
	_check(
		doors.size() == (HungryLayout.HARBOUR_POSTS + 1) * 2
			and float(Array(doors).max()) - door < 0.5,
		"with four doors in each, all the same width",
		_widths(doors)
	)

	_the_harbours_part2(preset, world, bounds, centre, layout, rules, door)


func _the_harbours_part2(preset: HungryPreset, world: HungryWorld, bounds: Rect2, centre: Vector2, layout: HungryLayout, rules: Dot2DMassRules, door: float) -> void:
	# [b]The design number.[/b] A sixth of the winning mass: past a starting monster,
	# short of anybody who has eaten for a minute, and a tier below the slalom's near lane.
	var door_admits := rules.mass_for(door * 0.5)
	var rocks := layout.part(0, HungryLayout.SLALOM_COUNT)
	var lane := rocks.narrowest_gate(bounds)
	_check(
		door_admits > preset.win_mass * 0.1 and door_admits < preset.win_mass * 0.25,
		"a door admits about a sixth of the winning mass",
		"%.0f of %.0f, through %.0f" % [door_admits, preset.win_mass, door]
	)
	_check(
		rules.radius_for(HungryContent.START_MASS) * 2.0 < door * 0.5,
		"a starting monster fits with room to spare",
		"a radius of %.0f through a half-door of %.0f"
			% [rules.radius_for(HungryContent.START_MASS), door * 0.5]
	)
	_check(
		door < lane * 0.8 and absf(layout.narrowest_gate(bounds) - door) < 0.5,
		"and it is a tier below the slalom's near lane, and the tightest thing on the map",
		"%.0f against the near lane's %.0f; narrowest %.0f"
			% [door, lane, layout.narrowest_gate(bounds)]
	)

	# The water in front of each fence: the end slalom rock's face to the nearest post.
	# Narrower than the slalom's own near lane and it would be a second, hidden gate that
	# only showed itself to a monster already at the corridor's end.
	var moat := INF

	for chain in range(layout.chains.size()):
		var run: Vector2i = layout.chains[chain]

		for index in range(run.y):
			var post := layout.blocks[run.x + index]

			for rock in rocks.blocks:
				moat = minf(
					moat,
					Vector2(post.x, post.y).distance_to(Vector2(rock.x, rock.y)) - post.z - rock.z
				)

	_check(
		moat > lane + 20.0,
		"the water in front of each fence is wider than the slalom's near lane",
		"%.0f against %.0f" % [moat, lane]
	)

	_the_harbours_reach_just_too_big_for_a_doo(world, bounds, centre, layout, rules, door)


## Reach, just too big for a door.
func _the_harbours_reach_just_too_big_for_a_doo(world: HungryWorld, bounds: Rect2, centre: Vector2, layout: HungryLayout, rules: Dot2DMassRules, door: float) -> void:
	var outgrown := door * 0.5 + 16.0
	var open_floor := Vector2(centre.x - bounds.size.x * 0.25, centre.y)
	var sweep := layout.reach(bounds, open_floor, outgrown)
	var stranded: PackedVector2Array = sweep["stranded"]
	var loose := 0
	var behind := [0, 0]

	for point in stranded:
		var harbour := layout.harbour_of(point, bounds)

		if harbour < 0:
			loose += 1
		else:
			behind[harbour] += 1

	_check(
		loose == 0 and behind[0] > 0 and behind[1] > 0,
		"one just too big for a door reaches everything but the two harbours",
		"radius %.0f: %d of %d reached; %d stranded in the corridor, %d and %d behind the fences"
			% [outgrown, sweep["reached"], sweep["free"], loose, behind[0], behind[1]]
	)

	var fence_at := layout.blocks[layout.chains[0].x]
	var inside := Vector2(
		(bounds.position.x + fence_at.x + fence_at.z) * 0.5, centre.y + door
	)
	_check(
		layout.harbour_of(inside, bounds) == 0
			and layout.route_to(bounds, open_floor, inside, outgrown).is_empty()
			and not layout.route_to(bounds, open_floor, inside, door * 0.5 - 16.0).is_empty(),
		"so it has no route into the west harbour, and one just under a door has",
		"inside at %s" % str(inside)
	)

	_the_harbours_driven_a_starting_monster_fr(world, bounds, centre, layout, rules, door, fence_at, inside)


## Driven: a starting monster from the corridor into the harbour.
func _the_harbours_driven_a_starting_monster_fr(world: HungryWorld, bounds: Rect2, centre: Vector2, layout: HungryLayout, rules: Dot2DMassRules, door: float, fence_at: Vector3, inside: Vector2) -> void:
	var from := Vector2(centre.x - bounds.size.x * 0.2, centre.y - bounds.size.y * 0.3)
	world.spawn(1, from)
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a starting monster spawns in the corridor"):
		_drop(world)
		_done()
		return

	var small := monster.pieces[0].radius()
	# The den's margin: a monster steered at a waypoint swings wide of the leg on a turn.
	var route := layout.route_to(bounds, monster.centre(), inside, small + 24.0)

	_check(
		route.size() >= 2,
		"and has a route into the west harbour that has to turn round rocks to get there",
		"%d waypoints" % route.size()
	)

	var reached := 0
	var deepest := INF

	var drive_from := monster.centre()
	var drive_covered := 0.0
	var drive_ground := 0.0
	var drive_ticks := 0

	for _i in range(TICK_RATE * 40):
		if reached >= route.size():
			break

		if monster.centre().distance_to(route[reached]) < 40.0:
			reached += 1
			continue

		var was := monster.centre()
		drive_ground += _ground_step(world, monster)
		world.tick({1: _full_reach(monster.centre(), route[reached])})
		drive_covered += monster.centre().distance_to(was)
		drive_ticks += 1

		for piece in monster.pieces:
			for block in layout.blocks:
				deepest = minf(
					deepest,
					piece.position().distance_to(Vector2(block.x, block.y)) - block.z
						- piece.radius()
				)

	_the_harbours_part5(world, bounds, layout, rules, door, fence_at, monster, route, reached, deepest, drive_from, drive_covered, drive_ground, drive_ticks)


func _the_harbours_part5(world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, door: float, fence_at: Vector3, monster: HungryMonster, route: PackedVector2Array, reached: int, deepest: float, drive_from: Vector2, drive_covered: float, drive_ground: float, drive_ticks: int) -> void:
	_drive_report(drive_from, route, drive_covered, drive_ticks, drive_ground)
	_check(
		deepest > -2.0,
		"driven along it, it never overlaps a rock or a post on any tick",
		"deepest %.1f into a face" % deepest
	)
	_check(
		reached == route.size() and layout.harbour_of(monster.centre(), bounds) == 0
			and monster.centre().x < fence_at.x - fence_at.z,
		"and it comes through a door to stand behind the fence",
		"%d of %d waypoints, at %s, the fence's back face at x %.0f"
			% [reached, route.size(), str(monster.centre()), fence_at.x - fence_at.z]
	)

	# And one that has eaten is held at the door

	# In front of the west fence's first gap between posts, driven straight through its
	# mouth at the end wall: the line runs through a DOOR, so the only thing that can stop
	# it is the door's width.
	var mouth: Vector2 = layout.channels(0)[0]["mouth"]
	var fed := rules.mass_for(door * 0.5) * 1.6
	_straight_run(
		world, 1, mouth + Vector2(260.0, 0.0), Vector2(bounds.position.x - 1000.0, mouth.y), fed
	)
	monster = world.monster_for(1)

	_check(
		monster != null and monster.alive and layout.harbour_of(monster.centre(), bounds) < 0,
		"one at %.0f mass driven through a door is held outside the harbour" % fed,
		"stopped at %s, the fence's front face at x %.0f"
			% [str(monster.centre()) if monster != null else "-", fence_at.x + fence_at.z]
	)

	_drop(world)
	_done()
