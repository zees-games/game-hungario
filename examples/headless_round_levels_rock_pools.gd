extends "headless_round_levels_cove.gd"

## The level-by-level sections of the headless round suite (5 of 7).


## The shallows' rock pools: one post off each corner of the open water, two doors each the tightest line's width, and a room behind it.
##
## The cove's questions asked in a corner: doors, water, room, hunters refused, then driven at the size each door is for.
func _test_the_rock_pools() -> void:
	_section("the rock pools")

	var preset := HungryPreset.shallows()
	var leader_mass := preset.win_mass
	# Lifted for the cove's reason: the leader eats on its walk.
	preset.win_mass = 1000000.0
	var world := _make_world(preset, SEED + 271)
	world.add_player(1, "Poo")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout
	var rules := world.tunables.mass_rules
	var lines := HungryLayout.SHALLOWS_LINES
	var line_posts := 0

	for run in layout.chains:
		line_posts += run.y

	if not _check(
		layout != null and layout.pools.size() == 2 and layout.chains.size() == lines
			and layout.pools[0] == Vector2i(line_posts, 1) and layout.pools[1] == Vector2i(line_posts + 1, 1)
			and layout.count() == line_posts + 2 + layout.groynes.size() * 2 + layout.inlets.size() * 2 + layout.sills.size(),
		"the shallows have two rock pools of one post each, after the five lines",
		"pools %s, %d posts in the lines, %d in all" % [
			str(layout.pools) if layout != null else "none", line_posts, layout.count() if layout != null else -1
		]
	):
		_drop(world)
		_done()
		return

	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var door := HungryLayout.pool_door(short_half)
	var widths := HungryLayout.shallows_widths(short_half)
	var won := rules.radius_for(leader_mass)
	var start := rules.radius_for(HungryContent.START_MASS)
	var centre := bounds.get_center()
	var last_line := layout.chains[lines - 1]

	_the_rock_pools_the_doors_which_are_the_leve(leader_mass, world, bounds, layout, rules, lines, door, widths, won, start, centre, last_line)


## The doors, which are the level.
func _the_rock_pools_the_doors_which_are_the_leve(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, lines: int, door: float, widths: PackedFloat32Array, won: float, start: float, centre: Vector2, last_line: Vector2i) -> void:
	var doors := PackedFloat32Array()
	var placed := true
	var to_line := INF

	for run in layout.pools:
		var post := layout.blocks[run.x]
		var at := Vector2(post.x, post.y)
		var corner := Vector2(signf(post.x - centre.x), signf(post.y - centre.y))
		var wall_x := bounds.end.x if corner.x > 0.0 else bounds.position.x
		var wall_y := bounds.end.y if corner.y > 0.0 else bounds.position.y
		doors.append(absf(wall_x - post.x) - post.z)
		doors.append(absf(wall_y - post.y) - post.z)
		placed = placed and corner.x > 0.0 and layout.shallows_band(at, bounds) == lines

		for index in range(last_line.x, last_line.x + last_line.y):
			var o := layout.blocks[index]
			to_line = minf(to_line, at.distance_to(Vector2(o.x, o.y)) - post.z - o.z)

		# And the open wall's own face of the last line, which is where a leader walks.
		var face := layout.blocks[last_line.x].x + layout.blocks[last_line.x].z
		to_line = minf(to_line, post.x - post.z - face)

	_check(
		absf(door - widths[0]) < 0.5
			and float(Array(doors).max()) - door < 0.5 and door - float(Array(doors).min()) < 0.5,
		"all four doors, measured off the discs, are the tightest line's gap",
		"built %s, the tightest line %.0f" % [_widths(doors), widths[0]]
	)
	_check(
		placed and to_line > won * 2.0 + 40.0,
		"both pools stand in the open water's corners, past the last line by more than a leader",
		"%.0f of water between a pool and the last line, a leader %.0f across" % [to_line, won * 2.0]
	)
	_check(
		absf(layout.narrowest_gate(bounds) - widths[0]) < 1.0,
		"and nothing on the map is tighter than the tightest line",
		"narrowest %.0f" % layout.narrowest_gate(bounds)
	)

	# A room: it holds more than it lets out

	var south := layout.blocks[layout.pools[1].x]
	var south_at := Vector2(south.x, south.y)
	# The corner's inscribed circle against the post, on the diagonal.
	var diagonal := Vector2(1.0, 1.0).normalized()
	var to_corner := bounds.end - south_at
	var holds := (to_corner.x * sqrt(2.0) - south.z) / (1.0 + sqrt(2.0))
	var inside := bounds.end - Vector2(holds, holds)
	var clear := minf(
		minf(bounds.end.x - inside.x, bounds.end.y - inside.y), inside.distance_to(south_at) - south.z
	)
	_check(
		layout.in_pool(inside, bounds) and layout.pool_of(inside, bounds) == 1
			and not layout.in_pool(south_at - diagonal * (south.z + 1.0), bounds)
			and absf(clear - holds) < 0.5 and holds > door * 0.5 + 24.0 and holds < won,
		"it is a room: its corner holds a radius wider than a door lets out, and nothing a leader's size",
		"holds %.0f (%.0f mass), lets out %.0f (%.0f mass), a leader %.0f"
			% [holds, rules.mass_for(holds), door * 0.5, rules.mass_for(door * 0.5), won]
	)

	_the_rock_pools_reach_just_too_big_for_a_doo(leader_mass, world, bounds, layout, rules, door, won, start, to_line, south, diagonal, holds, inside)


## Reach: just too big for a door.
func _the_rock_pools_reach_just_too_big_for_a_doo(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, door: float, won: float, start: float, to_line: float, south: Vector3, diagonal: Vector2, holds: float, inside: Vector2) -> void:
	var open_water := _shallows_open_water(layout, bounds)
	var outgrown := door * 0.5 + 16.0
	var sweep := layout.reach(bounds, open_water, outgrown)
	var loose := 0
	var pool_points := PackedInt32Array([0, 0])

	for point: Vector2 in sweep["stranded"]:
		var which := layout.pool_of(point, bounds)

		if which >= 0:
			pool_points[which] += 1
		elif layout.shallows_band(point, bounds) != 0 and not layout.in_inlet(point, bounds):
			# The inlet's doors are a pool's; its own section asks it.
			loose += 1

	_check(
		loose == 0 and pool_points[0] > 0 and pool_points[1] > 0,
		"one just too big for a door reaches everything but the pools, the inlet and the deepest band",
		"radius %.0f: %d of %d reached; %d stranded elsewhere, %d and %d in the pools"
			% [outgrown, sweep["reached"], sweep["free"], loose, pool_points[0], pool_points[1]]
	)
	_check(
		layout.route_to(bounds, open_water, inside, outgrown).is_empty()
			and not layout.route_to(bounds, open_water, inside, door * 0.5 - 16.0).is_empty(),
		"so it has no route into a pool, and one just under a door has"
	)

	# Hunters: refused, as the cove is

	var lurker := HungryHunters.largest_radius()
	var region := layout.main_region(bounds, lurker)
	var seeded := 0

	for at in HungryHunters.spawn_points_for(layout, bounds):
		if layout.in_pool(at, bounds):
			seeded += 1

	_check(
		HungryLayout.in_region(region, bounds, inside)
			and not HungryHunters.spawnable(layout, bounds, inside, region) and seeded == 0,
		"a lurker fits its doors, and a hunter still may not appear inside it",
		"lurker radius %.1f; %d seeded points inside" % [lurker, seeded]
	)

	_the_rock_pools_driven_a_starting_monster_in(leader_mass, world, bounds, layout, rules, door, won, start, to_line, south, diagonal, holds, inside, open_water)


## Driven: a starting monster in, a leader beside it.
func _the_rock_pools_driven_a_starting_monster_in(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, door: float, won: float, start: float, to_line: float, south: Vector3, diagonal: Vector2, holds: float, inside: Vector2, open_water: Vector2) -> void:
	world.spawn(1, open_water)
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a starting monster spawns in the open water"):
		_drop(world)
		_done()
		return

	var small := monster.pieces[0].radius()
	# Planned 48 wide: from the middle bay the route crosses a groyne door on the slant.
	var into := layout.route_to(bounds, monster.centre(), inside, small + 48.0, 12.0)
	var small_drive := _drive_route(world, monster, into, diagonal, TICK_RATE * 30)
	# -3, not -2: it eats in the corner, and eating resolves after the push-out.
	_check(
		into.size() >= 1 and small_drive["deepest"] > -3.0
			and small_drive["reached"] == into.size() and layout.pool_of(monster.centre(), bounds) == 1,
		"driven along its route from the open water, it never overlaps a post and stands inside the south pool",
		"%d of %d waypoints, deepest %.1f into a face, at %s"
			% [small_drive["reached"], into.size(), small_drive["deepest"], str(monster.centre())]
	)

	# A leader along the open wall to the floor in front of the pool's west door: the
	# water between the pool and the last line is the way, and has to still be one.
	world.spawn(1, open_water)
	_run_ticks(world, 2)
	monster = world.monster_for(1)
	world.feed_player(1, leader_mass - monster.mass())
	_run_ticks(world, 2)

	var leader := monster.pieces[0].radius()
	# 16 off the wall, not 8: the route is planned 12 wide, and a goal closer to the wall
	# than that is a blocked cell whenever the leader ate a little on its way.
	var beside := Vector2(south.x - south.z - leader - 40.0, bounds.end.y - leader - 16.0)
	var past := layout.route_to(bounds, monster.centre(), beside, leader + 12.0, 12.0)
	var leader_drive := _drive_route(world, monster, past, Vector2.DOWN, TICK_RATE * 60)
	_check(
		monster.pieces.size() == 1 and leader > won - 2.0 and past.size() >= 1
			and leader_drive["deepest"] > -2.0 and leader_drive["reached"] == past.size()
			and not layout.in_pool(monster.centre(), bounds),
		"a leader driven along the open water to the south wall beside the pool never overlaps a post",
		"radius %.0f of %.0f in %d pieces, %d of %d waypoints, deepest %.1f, at %s"
			% [leader, won, monster.pieces.size(), leader_drive["reached"], past.size(),
				leader_drive["deepest"], str(monster.centre())]
	)
	_check(
		small_drive["covered"] > small_drive["length"] * 0.9
			and leader_drive["covered"] > leader_drive["length"] * 0.9
			and small_drive["pace"] > 0.95 and leader_drive["pace"] > 0.95,
		"and both covered their routes at their ground speed",
		"in %.0f of %.0f at %.2f of ground speed; beside %.0f of %.0f at %.2f"
			% [small_drive["covered"], small_drive["length"], small_drive["pace"],
				leader_drive["covered"], leader_drive["length"], leader_drive["pace"]]
	)

	_the_rock_pools_straight_along_the_south_wal(world, bounds, layout, rules, door, won, start, to_line, south, holds, monster)


## Straight along the south wall at the west door.
func _the_rock_pools_straight_along_the_south_wal(world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, door: float, won: float, start: float, to_line: float, south: Vector3, holds: float, monster: HungryMonster) -> void:
	var hug := bounds.end.y - door * 0.5
	var from_west := Vector2(south.x - 900.0, hug)
	var to_east := Vector2(bounds.end.x + 400.0, hug)
	var door_line := south.x
	var small_got := _straight_run(world, 1, from_west, to_east, 0.0)
	_check(
		small_got > door_line + 24.0,
		"a starting monster driven straight along the south wall comes in through the door",
		"reached %.0f, the door is at %.0f" % [small_got, door_line]
	)

	var fed := rules.mass_for(door * 0.5) * 1.6
	var big_got := _straight_run(world, 1, from_west, to_east, fed)
	monster = world.monster_for(1)
	var big_r := monster.pieces[0].radius() if monster != null else 0.0
	# Its front against a starting monster tucked into the corner at the back.
	var short_by := (bounds.end.x - start * 2.0) - (big_got + big_r)
	_check(
		monster != null and big_got < door_line and not layout.in_pool(monster.centre(), bounds) and short_by > 0.0,
		"one of %.0f mass on the same line is held at the door, its front short of a starting monster in the corner" % fed,
		"reached %.0f, the door at %.0f, its front %.0f short" % [big_got, door_line, short_by]
	)
	print("        the room holds %.0f, the doors let out %.0f; %.0f of water to the last line, a leader %.0f across; the held one's front %.0f short of the corner"
		% [holds, door * 0.5, to_line, won * 2.0, short_by])

	# Outgrown: a monster too big for the room stays inside the arena
	# `[refuge-outgrown-1]`: the post's push-out must not put it through the wall
	# (it once went 113 units past the edge at 825 mass). It overlaps the post instead.
	var og_corner := bounds.end - Vector2(holds, holds)
	world.spawn(1, og_corner)
	world.tick({})
	monster = world.monster_for(1)
	var og_outgrown := rules.mass_for(holds * 1.4)
	world.feed_player(1, og_outgrown - monster.mass())
	var og_past := 0.0

	for _i in range(world.tick_rate):
		world.tick({1: _aim_at(monster.centre(), bounds.end)})
		var og_piece := monster.pieces[0]
		var og_inside := bounds.grow(-og_piece.radius())
		var og_at := og_piece.position()
		og_past = maxf(og_past, maxf(
			maxf(og_inside.position.x - og_at.x, og_at.x - og_inside.end.x),
			maxf(og_inside.position.y - og_at.y, og_at.y - og_inside.end.y)
		))

	var og_overlap := 0.0

	for block in layout.blocks:
		og_overlap = maxf(og_overlap, block.z + monster.pieces[0].radius()
			- monster.centre().distance_to(Vector2(block.x, block.y)))

	_check(
		layout.in_pool(og_corner, bounds) and og_past <= 0.5,
		"a monster grown past a pool's room, held into the corner, is never pushed through the arena's wall",
		"%.0f mass (radius %.0f, the room holds %.0f): %.1f past the wall at worst, %.1f into the post"
			% [monster.mass(), monster.pieces[0].radius(), holds, og_past, og_overlap]
	)
	print("        outgrown: %.0f mass in a room holding %.0f overlaps the post by %.0f and stands %.1f past the wall"
		% [monster.mass(), holds, og_overlap, og_past])

	_the_rock_pools_the_three_rules_a_server_can(world, bounds, monster, og_corner, og_outgrown, og_overlap)


## The three rules a server can choose (`hungry_outgrown`).
func _the_rock_pools_the_three_rules_a_server_can(world: HungryWorld, bounds: Rect2, monster: HungryMonster, og_corner: Vector2, og_outgrown: float, og_overlap: float) -> void:
	# accept is what was just measured. cap: in the same corner, fed the same, it stops
	# growing where it would wedge. eject: grown wedged, it sheds food until it fits.
	_check(world.outgrown == HungryWorld.Outgrown.ACCEPT and og_overlap > HungryWorld.WEDGED_DEPTH,
		"accept, the default: the outgrown monster stays wedged in the post", "%.0f into it" % og_overlap)

	world.outgrown = HungryWorld.Outgrown.CAP
	world.spawn(1, og_corner)
	world.tick({})
	monster = world.monster_for(1)
	world.feed_player(1, og_outgrown - monster.mass())
	for _i in range(world.tick_rate / 2):
		world.tick({1: _aim_at(monster.centre(), bounds.end)})
	var capped_depth := world.wedged_depth(monster.pieces[0])
	_check(monster.mass() < og_outgrown * 0.9 and capped_depth <= HungryWorld.WEDGED_DEPTH + 0.5,
		"cap: fed the same, it stops growing where it would wedge",
		"%.0f mass of %.0f fed, %.1f into the post" % [monster.mass(), og_outgrown, capped_depth])

	world.outgrown = HungryWorld.Outgrown.ACCEPT
	world.spawn(1, og_corner)
	world.tick({})
	monster = world.monster_for(1)
	world.feed_player(1, og_outgrown - monster.mass())
	world.tick({})
	world.outgrown = HungryWorld.Outgrown.EJECT
	var start_mass := monster.mass()
	for _i in range(world.tick_rate * 4):
		world.tick({1: _aim_at(monster.centre(), bounds.end)})
	var ejected_depth := world.wedged_depth(monster.pieces[0])
	_check(monster.mass() < start_mass and ejected_depth <= HungryWorld.WEDGED_DEPTH + 0.5,
		"eject: grown wedged, it sheds the excess until it fits",
		"%.0f mass from %.0f, %.1f into the post" % [monster.mass(), start_mass, ejected_depth])
	print("        outgrown rules: cap holds it at %.0f mass; eject sheds it from %.0f to %.0f" % [world.monster_for(1).mass(), start_mass, monster.mass()])
	world.outgrown = HungryWorld.Outgrown.ACCEPT

	_drop(world)
	_done()


## The shallows' groynes: two posts each from a quarter post of the last line to the open wall, three doors each the shallows' first three gaps.
##
## A groyne is for a detour, so the crossing is planned and driven for a starting monster and a leader; a bay is not a refuge, per `[refuge-outgrown-1]`.
func _test_the_groynes() -> void:
	_section("the groynes")

	var preset := HungryPreset.shallows()
	var leader_mass := preset.win_mass
	# Lifted for the cove's reason: the leader eats on its walk.
	preset.win_mass = 1000000.0
	var world := _make_world(preset, SEED + 277)
	world.add_player(1, "Gro")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout
	var rules := world.tunables.mass_rules
	var lines := HungryLayout.SHALLOWS_LINES
	var line_posts := 0

	for run in layout.chains:
		line_posts += run.y

	if not _check(
		layout != null and layout.groynes.size() == 2 and layout.chains.size() == lines
			and layout.groynes[0] == Vector2i(line_posts + 2, 2) and layout.groynes[1] == Vector2i(line_posts + 4, 2)
			and layout.count() == line_posts + 6 + layout.inlets.size() * 2 + layout.sills.size(),
		"the shallows have two groynes of two posts each, after the lines and the pools",
		"groynes %s, %d posts in the lines, %d in all" % [
			str(layout.groynes) if layout != null else "none", line_posts, layout.count() if layout != null else -1
		]
	):
		_drop(world)
		_done()
		return

	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var doors := HungryLayout.groyne_doors(short_half)
	var widths := HungryLayout.shallows_widths(short_half)
	var won := rules.radius_for(leader_mass)
	var last_line := layout.chains[lines - 1]

	_the_groynes_the_doors_which_are_the_leve(leader_mass, world, bounds, layout, rules, lines, doors, widths, won, last_line)


## The doors, which are the level.
func _the_groynes_the_doors_which_are_the_leve(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, lines: int, doors: PackedFloat32Array, widths: PackedFloat32Array, won: float, last_line: Vector2i) -> void:
	var built := PackedFloat32Array()
	var joined := true
	var mismatch := 0.0

	for g in range(layout.groynes.size()):
		var run := layout.groynes[g]
		var which := HungryLayout.GROYNE_JOINT if g == 0 else last_line.y - 1 - HungryLayout.GROYNE_JOINT
		var joint := layout.blocks[last_line.x + which]
		var a := layout.blocks[run.x]
		var b := layout.blocks[run.x + 1]
		joined = joined and absf(a.y - joint.y) < 0.01 and absf(b.y - joint.y) < 0.01 and joint.x < a.x and a.x < b.x
		built.append(Vector2(joint.x, joint.y).distance_to(Vector2(a.x, a.y)) - joint.z - a.z)
		built.append(Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) - a.z - b.z)
		built.append(bounds.end.x - b.x - b.z)

		for k in range(3):
			mismatch = maxf(mismatch, absf(built[g * 3 + k] - doors[k]))

	_check(
		joined and mismatch < 0.5 and absf(doors[0] - widths[0]) < 0.01 and absf(doors[2] - widths[2]) < 0.01
			and doors[2] < won * 2.0,
		"each groyne runs from a quarter post of the last line to the open wall, its doors the first three lines' gaps, tightest at the line",
		"built %s against %s; a leader %.0f across" % [_widths(built), _widths(doors), won * 2.0]
	)
	_check(
		absf(layout.narrowest_gate(bounds) - widths[0]) < 1.0,
		"and nothing on the map is tighter than the tightest line",
		"narrowest %.0f" % layout.narrowest_gate(bounds)
	)

	# Three bays

	var south := layout.blocks[layout.groynes[1].x]
	var gy := south.y
	var outer := layout.blocks[layout.groynes[1].x + 1]
	var face := layout.blocks[last_line.x].x + layout.blocks[last_line.x].z
	var water_x := (face + bounds.end.x) * 0.5
	var low_gy := layout.blocks[layout.groynes[0].x].y
	var bay_centres := [
		Vector2(water_x, (bounds.position.y + low_gy) * 0.5), Vector2(water_x, (low_gy + gy) * 0.5),
		Vector2(water_x, (gy + bounds.end.y) * 0.5),
	]
	var bays := PackedInt32Array()

	for at: Vector2 in bay_centres:
		bays.append(layout.bay_of(at, bounds))

	_check(
		bays == PackedInt32Array([0, 1, 2]) and layout.bay_of(Vector2(face - 300.0, 0.0), bounds) == -1,
		"they cut the open water into three bays, and behind the last line is none of them",
		"bays %s" % str(bays)
	)

	_the_groynes_the_detour_one_crossing_plan(leader_mass, world, bounds, layout, rules, lines, doors, won, last_line, south, gy, outer, bay_centres)


## The detour: one crossing, planned at both sizes.
func _the_groynes_the_detour_one_crossing_plan(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, lines: int, doors: PackedFloat32Array, won: float, last_line: Vector2i, south: Vector3, gy: float, outer: Vector3, bay_centres: Array) -> void:
	# Far enough off the open wall that a leader clears the inlet's posts.
	var from := Vector2(bounds.end.x - won - 440.0, gy - won - 60.0)
	var to := Vector2(from.x, gy + won + 60.0)
	var start := rules.radius_for(HungryContent.START_MASS)
	var short_way := layout.route_to(bounds, from, to, start + 24.0)
	var long_way := layout.route_to(bounds, from, to, won + 12.0, 12.0)
	var under := layout.route_to(bounds, from, to, doors[2] * 0.5 - 16.0)
	var over := layout.route_to(bounds, from, to, doors[2] * 0.5 + 16.0)
	var behind := func(route: PackedVector2Array) -> bool:
		for point in route:
			if layout.shallows_band(point, bounds) < lines:
				return true
		return false
	var short_len := _route_length(from, short_way)
	var long_len := _route_length(from, long_way)
	_check(
		not under.is_empty() and not behind.call(under) and not over.is_empty() and behind.call(over)
			and not short_way.is_empty() and not long_way.is_empty() and behind.call(long_way)
			and long_len > short_len * 3.0,
		"bay to bay, one just under the wall door's limit stays in the open water and one just over goes back through the last line",
		"under %.0f: %d waypoints; over: %d; a starting monster %.0f, a leader %.0f (%.1fx)"
			% [_route_length(from, under), under.size(), over.size(), short_len, long_len, long_len / maxf(short_len, 1.0)]
	)

	# Not a refuge

	var lurker := HungryHunters.largest_radius()
	var region := layout.main_region(bounds, lurker)
	var allowed := 0

	for at: Vector2 in bay_centres:
		if HungryHunters.spawnable(layout, bounds, at, region):
			allowed += 1

	_check(allowed == 3, "no bay is a refuge: a hunter may appear in every one", "%d of 3" % allowed)

	_the_groynes_driven_the_same_crossing_sho(leader_mass, world, bounds, layout, rules, doors, won, last_line, south, gy, outer, from, to, behind, short_len, long_len)


## Driven: the same crossing, short way and long way.
func _the_groynes_driven_the_same_crossing_sho(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, doors: PackedFloat32Array, won: float, last_line: Vector2i, south: Vector3, gy: float, outer: Vector3, from: Vector2, to: Vector2, behind: Callable, short_len: float, long_len: float) -> void:
	world.spawn(1, from)
	_run_ticks(world, 2)
	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a starting monster spawns in the middle bay"):
		_drop(world)
		_done()
		return

	var small := monster.pieces[0].radius()
	var across := layout.route_to(bounds, monster.centre(), to, small + 24.0)
	var small_drive := _drive_route(world, monster, across, Vector2.DOWN, TICK_RATE * 20)
	_check(
		across.size() >= 1 and small_drive["deepest"] > -2.0 and small_drive["reached"] == across.size()
			and layout.bay_of(monster.centre(), bounds) == 2,
		"a starting monster driven across through the wall door never overlaps a post and stands in the next bay",
		"%d of %d waypoints, deepest %.1f, at %s"
			% [small_drive["reached"], across.size(), small_drive["deepest"], str(monster.centre())]
	)

	world.spawn(1, from)
	_run_ticks(world, 2)
	monster = world.monster_for(1)
	world.feed_player(1, leader_mass - monster.mass())
	_run_ticks(world, 2)
	var leader := monster.pieces[0].radius()
	var round_way := layout.route_to(bounds, monster.centre(), to, leader + 12.0, 12.0)
	var leader_drive := _drive_route(world, monster, round_way, Vector2.DOWN, TICK_RATE * 60)
	_check(
		monster.pieces.size() == 1 and leader > won - 2.0 and behind.call(round_way)
			and leader_drive["deepest"] > -2.0 and leader_drive["reached"] == round_way.size()
			and layout.bay_of(monster.centre(), bounds) == 2,
		"a leader driven to the same place goes back through the last line and round, never overlapping a post",
		"radius %.0f, %d of %d waypoints, deepest %.1f, at %s"
			% [leader, leader_drive["reached"], round_way.size(), leader_drive["deepest"], str(monster.centre())]
	)
	_check(
		small_drive["covered"] > small_drive["length"] * 0.9
			and leader_drive["covered"] > leader_drive["length"] * 0.9
			and small_drive["pace"] > 0.95 and leader_drive["pace"] > 0.95
			and leader_drive["covered"] > small_drive["covered"] * 3.0,
		"and both covered their routes at their ground speed, the leader three times as far",
		"across %.0f of %.0f at %.2f; round %.0f of %.0f at %.2f"
			% [small_drive["covered"], small_drive["length"], small_drive["pace"],
				leader_drive["covered"], leader_drive["length"], leader_drive["pace"]]
	)

	_the_groynes_straight_at_the_wall_door(world, bounds, layout, rules, doors, last_line, south, gy, outer, short_len, long_len, monster)


## Straight at the wall door.
func _the_groynes_straight_at_the_wall_door(world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, doors: PackedFloat32Array, last_line: Vector2i, south: Vector3, gy: float, outer: Vector3, short_len: float, long_len: float, monster: HungryMonster) -> void:
	var door_x := (outer.x + outer.z + bounds.end.x) * 0.5
	# From beside the inlet rather than in front of it: further along this line is the
	# inlet's room.
	var run_from := Vector2(door_x, gy - 330.0)
	var run_to := Vector2(door_x, gy + 1400.0)
	var fits := rules.mass_for(doors[2] * 0.5 - 16.0)
	var fit_got := _straight_run(world, 1, run_from, run_to, fits)
	_check(
		fit_got > gy + doors[2] * 0.5,
		"one of %.0f mass driven straight at the wall door comes through it" % fits,
		"reached %.0f, the groyne at %.0f" % [fit_got, gy]
	)

	var held := rules.mass_for(doors[2] * 0.5) * 1.6
	var held_got := _straight_run(world, 1, run_from, run_to, held)
	monster = world.monster_for(1)
	_check(
		monster != null and held_got < gy and layout.bay_of(monster.centre(), bounds) == 1,
		"one of %.0f mass on the same line is held at it" % held,
		"reached %.0f, the groyne at %.0f" % [held_got, gy]
	)

	_the_groynes_outgrown_in_a_door_it_is_pus(world, bounds, layout, rules, doors, last_line, south, gy, short_len, long_len, monster)


## Outgrown in a door: it is pushed into a bay, not held.
func _the_groynes_outgrown_in_a_door_it_is_pus(world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, doors: PackedFloat32Array, last_line: Vector2i, south: Vector3, gy: float, short_len: float, long_len: float, monster: HungryMonster) -> void:
	var joint_s := layout.blocks[last_line.x + last_line.y - 1 - HungryLayout.GROYNE_JOINT]
	var in_door := Vector2(joint_s.x + joint_s.z + doors[0] * 0.5, gy)
	world.spawn(1, in_door)
	world.tick({})
	monster = world.monster_for(1)
	world.feed_player(1, rules.mass_for(doors[0] * 0.5 * 1.4) - monster.mass())
	_run_ticks(world, TICK_RATE)
	var side := signf(monster.centre().y - gy)
	side = side if side != 0.0 else 1.0
	var away := Vector2(monster.centre().x, gy + side * 600.0)

	for _i in range(TICK_RATE * 3):
		world.tick({1: _aim_at(monster.centre(), away)})

	var overlap := -INF

	for piece in monster.pieces:
		for block in layout.blocks:
			overlap = maxf(overlap, block.z + piece.radius() - piece.position().distance_to(Vector2(block.x, block.y)))

	_check(
		overlap <= 0.5 and layout.bay_of(monster.centre(), bounds) >= 1,
		"a monster grown past the tightest door while standing in it steers out into a bay, touching nothing",
		"%.0f mass (radius %.0f, the door lets through %.0f): %.1f into a post, bay %d"
			% [monster.mass(), monster.pieces[0].radius(), doors[0] * 0.5, overlap, layout.bay_of(monster.centre(), bounds)]
	)
	print("        doors %s, posts %.1f; bay to bay a starting monster %.0f, a leader %.0f"
		% [_widths(doors), south.z, short_len, long_len])

	_drop(world)
	_done()
