extends "headless_round_levels_rock_pools.gd"

## The level-by-level sections of the headless round suite (6 of 7).


## The shallows' inlet: two posts off the open wall in the middle bay, three doors each the tightest line's gap, the middle bay's room.
##
## The cove's questions asked in the bay that had no room, plus the water beside it being wider than the fourth line; then driven, with [HungryBot]s playing from the middle bay.
func _test_the_inlet() -> void:
	_section("the inlet")

	var preset := HungryPreset.shallows()
	var leader_mass := preset.win_mass
	# Lifted for the cove's reason: the leader eats on its walk.
	preset.win_mass = 1000000.0
	var world := _make_world(preset, SEED + 283)
	world.add_player(1, "Inl")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout
	var rules := world.tunables.mass_rules
	var lines := HungryLayout.SHALLOWS_LINES
	var line_posts := 0

	for run in layout.chains:
		line_posts += run.y

	if not _check(
		layout != null and layout.inlets.size() == 1 and layout.chains.size() == lines
			and layout.inlets[0] == Vector2i(line_posts + 6, 2) and layout.count() == line_posts + 8 + layout.sills.size(),
		"the shallows have an inlet of two posts, after the lines, the pools and the groynes",
		"inlets %s, %d posts in the lines, %d in all" % [
			str(layout.inlets) if layout != null else "none", line_posts, layout.count() if layout != null else -1
		]
	):
		_drop(world)
		_done()
		return

	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var door := HungryLayout.inlet_door(short_half)
	var widths := HungryLayout.shallows_widths(short_half)
	var won := rules.radius_for(leader_mass)
	var last_line := layout.chains[lines - 1]
	var a := layout.blocks[layout.inlets[0].x]
	var b := layout.blocks[layout.inlets[0].x + 1]
	var a_at := Vector2(a.x, a.y)
	var b_at := Vector2(b.x, b.y)

	# The doors, which are the level

	var built := PackedFloat32Array([
		bounds.end.x - a.x - a.z, a_at.distance_to(b_at) - a.z - b.z, bounds.end.x - b.x - b.z,
	])
	var mismatch := 0.0

	for gap in built:
		mismatch = maxf(mismatch, absf(gap - door))

	_check(
		mismatch < 0.5 and absf(door - widths[0]) < 0.01 and absf(door - HungryLayout.pool_door(short_half)) < 0.01,
		"its three doors, measured off the discs, are the tightest line's gap, a rock pool's door",
		"built %s, the tightest line %.0f" % [_widths(built), widths[0]]
	)

	_the_inlet_placed_in_the_middle_bay_a_l(preset, leader_mass, world, bounds, layout, rules, lines, door, widths, won, last_line, a, b, a_at, b_at, built)


## Placed: in the middle bay, a leader's water in front, no hidden gate.
func _the_inlet_placed_in_the_middle_bay_a_l(preset: HungryPreset, leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, lines: int, door: float, widths: PackedFloat32Array, won: float, last_line: Vector2i, a: Vector3, b: Vector3, a_at: Vector2, b_at: Vector2, built: PackedFloat32Array) -> void:
	var face := layout.blocks[last_line.x].x + layout.blocks[last_line.x].z
	var front := minf(a.x - a.z, b.x - b.z)
	var to_line := front - face

	for index in range(last_line.x, last_line.x + last_line.y):
		var o := layout.blocks[index]
		to_line = minf(to_line, minf(a_at.distance_to(Vector2(o.x, o.y)) - a.z - o.z,
			b_at.distance_to(Vector2(o.x, o.y)) - b.z - o.z))

	var to_groyne := INF

	for run in layout.groynes:
		for index in range(run.x, run.x + run.y):
			var g := layout.blocks[index]
			to_groyne = minf(to_groyne, minf(a_at.distance_to(Vector2(g.x, g.y)) - a.z - g.z,
				b_at.distance_to(Vector2(g.x, g.y)) - b.z - g.z))

	_check(
		layout.bay_of(a_at, bounds) == 1 and layout.bay_of(b_at, bounds) == 1
			and to_line > won * 2.0 + 40.0 and to_groyne > widths[lines - 2],
		"it stands in the middle bay with more than a leader's water in front of it, and the water beside it is wider than the fourth line",
		"bays %d and %d; %.0f of water to the last line (a leader %.0f across), %.0f to a groyne (the fourth line %.0f)"
			% [layout.bay_of(a_at, bounds), layout.bay_of(b_at, bounds), to_line, won * 2.0, to_groyne, widths[lines - 2]]
	)
	_check(
		absf(layout.narrowest_gate(bounds) - widths[0]) < 1.0,
		"and nothing on the map is tighter than the tightest line",
		"narrowest %.0f" % layout.narrowest_gate(bounds)
	)

	# A room: it holds more than it lets out

	# The circle against the open wall on the inlet's centre line, touching both posts.
	var mid_y := (a.y + b.y) * 0.5
	var off := bounds.end.x - a.x
	var half_span := (b.y - a.y) * 0.5
	var holds := (off * off + half_span * half_span - a.z * a.z) / (2.0 * off + 2.0 * a.z)
	var inside := Vector2(bounds.end.x - holds, mid_y)
	var clear := minf(bounds.end.x - inside.x,
		minf(inside.distance_to(a_at) - a.z, inside.distance_to(b_at) - b.z))
	_check(
		layout.in_inlet(inside, bounds) and not layout.in_inlet(Vector2(front - 1.0, mid_y), bounds)
			and absf(clear - holds) < 0.5 and holds > door * 0.5 + 24.0 and holds < won,
		"it is a room: it holds a radius wider than a door lets out, and nothing a leader's size",
		"holds %.0f (%.0f mass), lets out %.0f (%.0f mass), a leader %.0f"
			% [holds, rules.mass_for(holds), door * 0.5, rules.mass_for(door * 0.5), won]
	)

	# Reach: the tier it is for

	var bay := Vector2((face + front) * 0.5, mid_y)
	_check(
		layout.route_to(bounds, bay, inside, door * 0.5 + 16.0).is_empty()
			and not layout.route_to(bounds, bay, inside, door * 0.5 - 16.0).is_empty(),
		"one just over its door has no route in from the bay, and one just under has",
		"radii %.0f / %.0f" % [door * 0.5 + 16.0, door * 0.5 - 16.0]
	)

	_the_inlet_hunters_refused_as_the_pools(preset, leader_mass, world, bounds, layout, rules, door, won, a, b, built, face, front, to_line, to_groyne, mid_y, holds, inside, bay)


## Hunters: refused, as the pools are.
func _the_inlet_hunters_refused_as_the_pools(preset: HungryPreset, leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, door: float, won: float, a: Vector3, b: Vector3, built: PackedFloat32Array, face: float, front: float, to_line: float, to_groyne: float, mid_y: float, holds: float, inside: Vector2, bay: Vector2) -> void:
	var lurker := HungryHunters.largest_radius()
	var region := layout.main_region(bounds, lurker)
	var seeded := 0

	for at in HungryHunters.spawn_points_for(layout, bounds):
		if layout.in_inlet(at, bounds):
			seeded += 1

	_check(
		HungryLayout.in_region(region, bounds, inside)
			and not HungryHunters.spawnable(layout, bounds, inside, region) and seeded == 0
			and HungryHunters.spawnable(layout, bounds, bay, region),
		"a lurker fits its doors, and a hunter may not appear inside it, only in the bay in front",
		"lurker radius %.1f; %d seeded points inside" % [lurker, seeded]
	)

	_the_inlet_driven_a_starting_monster_in(preset, leader_mass, world, bounds, layout, rules, door, won, a, b, built, face, front, to_line, to_groyne, mid_y, holds, inside, bay)


## Driven: a starting monster in, a leader across in front.
func _the_inlet_driven_a_starting_monster_in(preset: HungryPreset, leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, door: float, won: float, a: Vector3, b: Vector3, built: PackedFloat32Array, face: float, front: float, to_line: float, to_groyne: float, mid_y: float, holds: float, inside: Vector2, bay: Vector2) -> void:
	world.spawn(1, bay)
	_run_ticks(world, 2)
	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a monster spawns in the middle bay"):
		_drop(world)
		_done()
		return

	var middling := monster.pieces[0].radius()
	var into := layout.route_to(bounds, monster.centre(), inside, middling + 24.0)
	var middling_drive := _drive_route(world, monster, into, Vector2.RIGHT, TICK_RATE * 20)
	_check(
		into.size() >= 1 and middling_drive["deepest"] > -2.0
			and middling_drive["reached"] == into.size() and layout.in_inlet(monster.centre(), bounds),
		"a starting monster driven along its route from the bay never overlaps a post and stands inside",
		"radius %.0f (the doors let in %.0f), %d of %d waypoints, deepest %.1f, at %s"
			% [middling, door * 0.5, middling_drive["reached"], into.size(),
				middling_drive["deepest"], str(monster.centre())]
	)

	var groyne_low := layout.blocks[layout.groynes[0].x]
	var groyne_high := layout.blocks[layout.groynes[1].x]
	world.spawn(1, bay)
	_run_ticks(world, 2)
	monster = world.monster_for(1)
	world.feed_player(1, leader_mass - monster.mass())
	_run_ticks(world, 2)
	var leader := monster.pieces[0].radius()
	var from := Vector2(bay.x, groyne_low.y + groyne_low.z + leader + 40.0)
	var to := Vector2(bay.x, groyne_high.y - groyne_high.z - leader - 40.0)
	var leader_route := layout.route_to(bounds, from, to, leader + 12.0, 12.0)
	leader_route.insert(0, from)
	var leader_drive := _drive_route(world, monster, leader_route, Vector2.DOWN, TICK_RATE * 30)
	var stayed := true

	for point in leader_route:
		stayed = stayed and layout.bay_of(point, bounds) == 1

	_check(
		monster.pieces.size() == 1 and leader > won - 2.0 and leader_route.size() >= 2 and stayed
			and leader_drive["deepest"] > -2.0 and leader_drive["reached"] == leader_route.size()
			and not layout.in_inlet(monster.centre(), bounds),
		"a leader driven across the middle bay in front of it stays in the bay and never overlaps a post",
		"radius %.0f of %.0f, %d of %d waypoints, deepest %.1f, at %s"
			% [leader, won, leader_drive["reached"], leader_route.size(), leader_drive["deepest"], str(monster.centre())]
	)
	_check(
		middling_drive["covered"] > middling_drive["length"] * 0.9
			and leader_drive["covered"] > leader_drive["length"] * 0.9
			and middling_drive["pace"] > 0.95 and leader_drive["pace"] > 0.95,
		"and both covered their routes at their ground speed",
		"in %.0f of %.0f at %.2f; across %.0f of %.0f at %.2f"
			% [middling_drive["covered"], middling_drive["length"], middling_drive["pace"],
				leader_drive["covered"], leader_drive["length"], leader_drive["pace"]]
	)

	_the_inlet_straight_at_the_middle_door(preset, world, bounds, layout, rules, door, a, b, built, face, front, to_line, to_groyne, mid_y, holds, bay, monster)


## Straight at the middle door.
func _the_inlet_straight_at_the_middle_door(preset: HungryPreset, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, door: float, a: Vector3, b: Vector3, built: PackedFloat32Array, face: float, front: float, to_line: float, to_groyne: float, mid_y: float, holds: float, bay: Vector2, monster: HungryMonster) -> void:
	var run_from := Vector2(face + 200.0, mid_y)
	var run_to := Vector2(bounds.end.x + 400.0, mid_y)
	var fits := rules.mass_for(door * 0.5 - 16.0)
	var fit_got := _straight_run(world, 1, run_from, run_to, fits)
	_check(
		fit_got > a.x + 24.0,
		"one of %.0f mass driven straight at the middle door comes in through it" % fits,
		"reached %.0f, the door at %.0f" % [fit_got, a.x]
	)

	var held := rules.mass_for(door * 0.5) * 1.6
	var held_got := _straight_run(world, 1, run_from, run_to, held)
	monster = world.monster_for(1)
	_check(
		monster != null and held_got < front and not layout.in_inlet(monster.centre(), bounds),
		"one of %.0f mass on the same line is held at it" % held,
		"reached %.0f, the posts' front at %.0f" % [held_got, front]
	)
	print("        doors %s, posts %.1f; the room holds %.0f, lets out %.0f; %.0f of water to the last line, %.0f to a groyne"
		% [_widths(built), a.z, holds, door * 0.5, to_line, to_groyne])
	_drop(world)

	_the_inlet_bots_playing_on_their_own(preset, bounds, layout, rules, door, a, b, front, mid_y, bay, held)


## Bots, playing on their own.
func _the_inlet_bots_playing_on_their_own(preset: HungryPreset, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, door: float, a: Vector3, b: Vector3, front: float, mid_y: float, bay: Vector2, held: float) -> void:
	# Four HungryBots from the middle bay, steering themselves for thirty seconds: the
	# inlet is a place they go into and come out of by its doors, and the push-out holds
	# them at every tick. A grown one among them never gets in.
	var bots := _make_world(preset, SEED + 284)
	var bot_ids := [1, 2, 3, 4, 5]

	for id in bot_ids:
		bots.add_player(id, "Bot %d" % id)

	_settle(bots)
	# One at each door's mouth, outside, and one out in the bay.
	var starts := [
		Vector2(front - 80.0, mid_y), Vector2(a.x + a.z + door * 0.5, a.y - a.z - 80.0),
		Vector2(b.x + b.z + door * 0.5, b.y + b.z + 80.0), Vector2(bay.x, mid_y - 300.0),
	]

	for i in range(starts.size()):
		bots.spawn(bot_ids[i], starts[i])

	bots.spawn(5, Vector2(front - rules.radius_for(held) - 60.0, mid_y))
	_run_ticks(bots, 2)
	bots.feed_player(5, held - bots.monster_for(5).mass())
	_run_ticks(bots, 2)

	var entered := {}
	var left := {}
	var deepest := INF
	var grown_in := 0
	var grown_mass := 0.0
	var inlet_posts := [a, b]

	for tick in range(TICK_RATE * 30):
		var commands := {}

		for m in bots.monsters():
			commands[m.id] = HungryBot.command_for(bots, m, tick)

		bots.tick(commands)

		for m in bots.monsters():
			if not m.alive:
				continue

			var inside_now := layout.in_inlet(m.centre(), bounds)

			if m.id == 5:
				grown_mass = m.mass()
				if inside_now:
					grown_in += 1
				continue

			if inside_now:
				entered[m.id] = true
			elif entered.has(m.id):
				left[m.id] = true

			for piece in m.pieces:
				for post: Vector3 in inlet_posts:
					deepest = minf(deepest,
						piece.position().distance_to(Vector2(post.x, post.y)) - post.z - piece.radius())

	_the_inlet_part7(rules, door, bots, entered, left, deepest, grown_in, grown_mass)


func _the_inlet_part7(rules: Dot2DMassRules, door: float, bots: HungryWorld, entered: Dictionary, left: Dictionary, deepest: float, grown_in: int, grown_mass: float) -> void:
	_check(
		entered.size() >= 2 and left.size() >= 1 and deepest > -2.0,
		"HungryBots playing from the middle bay go into the inlet and out again, never into a post",
		"%d of 4 went in (%s), %d came out, deepest %.1f into a post"
			% [entered.size(), str(entered.keys()), left.size(), deepest]
	)
	_check(
		grown_in == 0 and grown_mass > rules.mass_for(door * 0.5),
		"and a grown one beside them, over the door's limit, is never inside",
		"%d ticks inside at %.0f mass (the door lets in %.0f)" % [grown_in, grown_mass, rules.mass_for(door * 0.5)]
	)
	print("        bots: %d of 4 went into the inlet, %d came out again; the grown one (%.0f mass) %d ticks inside"
		% [entered.size(), left.size(), grown_mass, grown_in])

	_drop(bots)
	_done()


## The shallows' sills: a post across the second line's band and two across the third's, each the tightest line's gap off its neighbours.
##
## A sill is a detour inside a band, so the crossing is planned just under and over a door's limit, then driven. Not a refuge: a hunter may appear beside every sill.
func _test_the_sills() -> void:
	_section("the sills")

	var preset := HungryPreset.shallows()
	# Lifted for the cove's reason: the fed monsters below eat on their way.
	preset.win_mass = 1000000.0
	var world := _make_world(preset, SEED + 281)
	world.add_player(1, "Sil")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout
	var rules := world.tunables.mass_rules
	var lines := HungryLayout.SHALLOWS_LINES
	var line_posts := 0

	for run in layout.chains:
		line_posts += run.y

	var first := line_posts + 8

	if not _check(
		layout != null and layout.sills.size() == 3 and layout.sills[0] == Vector2i(first, 1)
			and layout.sills[2] == Vector2i(first + 2, 1) and layout.count() == first + 3,
		"the shallows have three sills of one post each, after the inlet",
		"sills %s, %d posts in the lines, %d in all" % [
			str(layout.sills) if layout != null else "none", line_posts, layout.count() if layout != null else -1
		]
	):
		_drop(world)
		_done()
		return

	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var widths := HungryLayout.shallows_widths(short_half)
	var door := HungryLayout.sill_door(short_half)

	_the_sills_the_doors_which_are_the_leve(world, bounds, layout, rules, lines, widths, door)


## The doors, which are the level.
func _the_sills_the_doors_which_are_the_leve(world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, lines: int, widths: PackedFloat32Array, door: float) -> void:
	var built := PackedFloat32Array()
	var bands := PackedInt32Array()
	var joined := true

	for run in layout.sills:
		var post := layout.blocks[run.x]
		var at := Vector2(post.x, post.y)
		var band := layout.shallows_band(at, bounds)
		bands.append(band)

		if band < 1 or band >= lines:
			joined = false
			continue

		var inner := layout.chains[band - 1]
		var aligned := false

		for index in range(inner.x, inner.x + inner.y):
			aligned = aligned or (absf(layout.blocks[index].y - post.y) < 0.01 and layout.blocks[index].x < post.x)

		joined = joined and aligned
		built.append(layout.clearance(inner, at, post.z))
		built.append(layout.clearance(layout.chains[band], at, post.z))

	var off := 0.0

	for width in built:
		off = maxf(off, absf(width - door))

	_check(
		joined and bands == PackedInt32Array([2, 3, 3]) and built.size() == 6 and off < 0.5
			and absf(door - widths[0]) < 0.01,
		"one sill stands in the second line's band and two in the third's, each in line with a post of the line inside, every door the tightest line's gap",
		"bands %s, doors %s against %.0f" % [str(bands), _widths(built), door]
	)
	_check(
		absf(layout.narrowest_gate(bounds) - widths[0]) < 1.0,
		"and nothing on the map is tighter than the tightest line",
		"narrowest %.0f" % layout.narrowest_gate(bounds)
	)

	_the_sills_the_detour_one_crossing_past(world, bounds, layout, rules, widths, door, bands)


## The detour: one crossing past each sill, planned either side of the door.
func _the_sills_the_detour_one_crossing_past(world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, widths: PackedFloat32Array, door: float, bands: PackedInt32Array) -> void:
	var start := rules.radius_for(HungryContent.START_MASS)
	var froms: Array[Vector2] = []
	var tos: Array[Vector2] = []
	var planned := PackedStringArray()
	var wrong := PackedStringArray()

	for s in range(layout.sills.size()):
		var post := layout.blocks[layout.sills[s].x]
		var band := bands[s]
		var inner := layout.blocks[layout.chains[band - 1].x]
		var outer := layout.blocks[layout.chains[band].x]
		var middle := (inner.x + inner.z + outer.x - outer.z) * 0.5
		var big := widths[band] * 0.5 - 24.0
		var from := Vector2(middle, post.y - post.z - big - 80.0)
		var to := Vector2(middle, post.y + post.z + big + 80.0)
		froms.append(from)
		tos.append(to)
		var stays := func(route: PackedVector2Array) -> bool:
			return _bands_crossed(layout, bounds, from, route) == PackedInt32Array([band])
		var under := layout.route_to(bounds, from, to, door * 0.5 - 16.0, 12.0)
		var over := layout.route_to(bounds, from, to, door * 0.5 + 16.0, 12.0)
		var biggest := layout.route_to(bounds, from, to, big, 12.0)
		var short_len := _route_length(from, under)
		var long_len := _route_length(from, over)
		planned.append("band %d: %.0f under, %.0f over (%.1fx), %.0f its biggest"
			% [band, short_len, long_len, long_len / maxf(short_len, 1.0), _route_length(from, biggest)])

		if under.is_empty() or not stays.call(under) or over.is_empty() or stays.call(over) \
				or biggest.is_empty() or stays.call(biggest) or long_len < short_len * 1.3:
			wrong.append("sill %d" % s)

	_check(
		wrong.is_empty(),
		"past every sill, one just under the door's limit stays in its band and one just over goes out through a line beside it and back in",
		"%s; %s" % [", ".join(wrong), "; ".join(planned)]
	)

	# Not a refuge

	var lurker := HungryHunters.largest_radius()
	var region := layout.main_region(bounds, lurker)
	var allowed := 0

	for at in froms + tos:
		if HungryHunters.spawnable(layout, bounds, at, region):
			allowed += 1

	_check(allowed == froms.size() * 2, "no sill is a refuge: a hunter may appear either side of every one", "%d of %d" % [allowed, froms.size() * 2])

	_the_sills_driven_past_the_second_band_(world, bounds, layout, rules, widths, door, bands, froms, tos, planned)


## Driven: past the second band's sill and one of the third's.
func _the_sills_driven_past_the_second_band_(world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, widths: PackedFloat32Array, door: float, bands: PackedInt32Array, froms: Array[Vector2], tos: Array[Vector2], planned: PackedStringArray) -> void:
	var resident := door * 0.5 + 40.0

	for s in [0, 1]:
		var band := bands[s]
		var post := layout.blocks[layout.sills[s].x]
		world.spawn(1, froms[s])
		_run_ticks(world, 2)
		var monster := world.monster_for(1)

		if not _check(monster != null and monster.alive, "a starting monster spawns beside sill %d" % s):
			_drop(world)
			_done()
			return

		var small := monster.pieces[0].radius()
		var through := layout.route_to(bounds, monster.centre(), tos[s], small + 24.0, 12.0)
		var small_drive := _drive_route(world, monster, through, Vector2.DOWN, TICK_RATE * 20)
		_check(
			through.size() >= 1 and small_drive["deepest"] > -2.0 and small_drive["reached"] == through.size()
				and layout.shallows_band(monster.centre(), bounds) == band and monster.centre().y > post.y,
			"band %d: a starting monster driven through the sill's door never overlaps a post and stands past it" % band,
			"%d of %d waypoints, deepest %.1f, at %s" % [small_drive["reached"], through.size(), small_drive["deepest"], str(monster.centre())]
		)

		world.spawn(1, froms[s])
		_run_ticks(world, 2)
		monster = world.monster_for(1)
		world.feed_player(1, rules.mass_for(resident) - monster.mass())
		_run_ticks(world, 2)
		var grown := monster.pieces[0].radius()
		# Planned 36 wide: it eats on the way, and the route crosses a line twice.
		var round_way := layout.route_to(bounds, monster.centre(), tos[s], grown + 36.0, 12.0)
		var crossed := _bands_crossed(layout, bounds, monster.centre(), round_way)
		var left_band := crossed.size() > 1

		var big_drive := _drive_route(world, monster, round_way, Vector2.DOWN, TICK_RATE * 40)
		_check(
			monster.pieces.size() == 1 and grown > door * 0.5 and grown < widths[band] * 0.5 and left_band
				and big_drive["deepest"] > -2.0 and big_drive["reached"] == round_way.size()
				and layout.shallows_band(monster.centre(), bounds) == band and monster.centre().y > post.y,
			"band %d: one of %.0f mass driven to the same place goes out through a line beside its band, round and back in" % [band, rules.mass_for(resident)],
			"radius %.0f in %d, %d of %d waypoints through bands %s, deepest %.1f, at %s, band %d"
				% [grown, monster.pieces.size(), big_drive["reached"], round_way.size(), str(crossed), big_drive["deepest"],
					str(monster.centre()), layout.shallows_band(monster.centre(), bounds)]
		)
		_check(
			small_drive["covered"] > small_drive["length"] * 0.9 and big_drive["covered"] > big_drive["length"] * 0.9
				and small_drive["pace"] > 0.95 and big_drive["pace"] > 0.95
				and big_drive["covered"] > small_drive["covered"] * 1.5,
			"band %d: and both covered their routes at their ground speed, the bigger one half as far again or more" % band,
			"through %.0f of %.0f at %.2f; round %.0f of %.0f at %.2f"
				% [small_drive["covered"], small_drive["length"], small_drive["pace"],
					big_drive["covered"], big_drive["length"], big_drive["pace"]]
		)

	_the_sills_straight_at_the_second_band_(world, bounds, layout, rules, door, bands, planned)


## Straight at the second band's inner door.
func _the_sills_straight_at_the_second_band_(world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, door: float, bands: PackedInt32Array, planned: PackedStringArray) -> void:
	var sill := layout.blocks[layout.sills[0].x]
	var door_x := sill.x - sill.z - door * 0.5
	var run_from := Vector2(door_x, sill.y - 400.0)
	var run_to := Vector2(door_x, sill.y + 1000.0)
	var fits := rules.mass_for(door * 0.5 - 16.0)
	var fit_got := _straight_run(world, 1, run_from, run_to, fits)
	_check(
		fit_got > sill.y + door * 0.5,
		"one of %.0f mass driven straight at the second band's sill door comes through it" % fits,
		"reached %.0f, the sill at %.0f" % [fit_got, sill.y]
	)

	var held := rules.mass_for(door * 0.5) * 1.6
	var held_got := _straight_run(world, 1, run_from, run_to, held)
	var monster := world.monster_for(1)
	_check(
		monster != null and held_got < sill.y and layout.shallows_band(monster.centre(), bounds) == 2,
		"one of %.0f mass on the same line is held at it" % held,
		"reached %.0f, the sill at %.0f" % [held_got, sill.y]
	)
	print("        sills %s, posts %s; %s" % [str(bands), _widths(PackedFloat32Array([sill.z, layout.blocks[layout.sills[1].x].z])), "; ".join(planned)])

	_drop(world)
	_done()


## The warrens' den: a ring inside the ring, driven into by a starting monster and refused a monster that has eaten.
##
## The map has three tiers, each proved at the size it is for, and the den must not narrow the moat below the ring's own gate. Driven along `HungryLayout.route_to`, which is what the built rocks leave.
func _test_the_den() -> void:
	_section("the den")

	var preset := HungryPreset.warrens()
	var world := _make_world(preset, SEED + 211)
	world.add_player(1, "Ada")
	_settle(world)

	var bounds := world.arena.bounds
	var centre := bounds.get_center()
	var layout := world.layout
	var rules := world.tunables.mass_rules

	if not _check(
		layout != null and layout.rings.size() == 2,
		"the warrens has two rings: the ring, and the den inside it",
		"%d rings" % (layout.rings.size() if layout != null else -1)
	):
		_drop(world)
		_done()
		return

	var ring_gates := layout.ring_gates(0)
	var den_gates := layout.ring_gates(1)
	var den_gate: float = Array(den_gates).min()
	var ring_gate: float = Array(ring_gates).min()

	_check(
		den_gates.size() == HungryLayout.DEN_COUNT
			and float(Array(den_gates).max()) - den_gate < 0.5,
		"the den has four gates, all the same width",
		_widths(den_gates)
	)

	# [b]The design number.[/b] Mass IS radius, so the gate is a mass limit, and this one
	# is meant for the players furthest behind: past a starting monster, short of anybody
	# who has fed for a minute.
	var den_admits := rules.mass_for(den_gate * 0.5)
	_check(
		den_admits > preset.win_mass * 0.05 and den_admits < preset.win_mass * 0.15,
		"its gates admit about a tenth of the winning mass",
		"%.0f of %.0f, through %.0f" % [den_admits, preset.win_mass, den_gate]
	)
	_check(
		rules.radius_for(HungryContent.START_MASS) * 2.0 < den_gate * 0.5,
		"a starting monster fits with room to spare",
		"a radius of %.0f through a half-gate of %.0f"
			% [rules.radius_for(HungryContent.START_MASS), den_gate * 0.5]
	)
	_check(
		den_gate < ring_gate * 0.6,
		"and it is a tier below the ring rather than another copy of it",
		"%.0f against the ring's %.0f" % [den_gate, ring_gate]
	)
	_check(
		is_equal_approx(layout.narrowest_gate(bounds), den_gate),
		"nothing else on the map is tighter than the den",
		"narrowest %.0f, the den %.0f" % [layout.narrowest_gate(bounds), den_gate]
	)

	_the_den_part2(world, bounds, centre, layout, rules, den_gate, ring_gate)


func _the_den_part2(world: HungryWorld, bounds: Rect2, centre: Vector2, layout: HungryLayout, rules: Dot2DMassRules, den_gate: float, ring_gate: float) -> void:
	# The moat: the ring's inner face to the den's outer face.
	var ring_rock: Vector3 = layout.blocks[layout.rings[0].x]
	var den_rock: Vector3 = layout.blocks[layout.rings[1].x]
	var ring_at := Vector2(ring_rock.x, ring_rock.y).distance_to(centre)
	var den_at := Vector2(den_rock.x, den_rock.y).distance_to(centre)
	var moat := (ring_at - ring_rock.z) - (den_at + den_rock.z)
	_check(
		moat > ring_gate + 20.0,
		"the moat round the den is wider than the ring's gate",
		"%.0f against %.0f" % [moat, ring_gate]
	)

	# Reach, at the size each tier is for

	# Off the axis on purpose: from a wall's midpoint the line to the centre runs through a
	# ring gate AND a den gate (both are on the axes), and a route that is one straight leg
	# proves nothing about finding a way. From here it has to bend at both rings.
	var wall := Vector2(bounds.position.x + 200.0, centre.y - bounds.size.y * 0.22)
	var between := (den_gate * 0.5 + ring_gate * 0.5) * 0.5
	var tiers := layout.reach(bounds, wall, between)
	var outside_den := 0

	for point in tiers["stranded"]:
		if point.distance_to(centre) > den_at:
			outside_den += 1

	_check(
		tiers["free"] - tiers["reached"] > 0 and outside_den == 0,
		"one between the two limits reaches everything but the den",
		"radius %.0f: %d of %d reached, %d stranded outside the den"
			% [between, tiers["reached"], tiers["free"], outside_den]
	)
	_check(
		layout.route_to(bounds, wall, centre, between).is_empty()
			and not layout.route_to(
				bounds, wall, centre + Vector2(den_at + den_rock.z + moat * 0.5, 0.0), between
			).is_empty(),
		"so it has a route into the moat and none into the den"
	)

	_the_den_driven_a_starting_monster_fr(world, bounds, centre, layout, rules, den_gate, ring_rock, den_rock, ring_at, den_at, moat, wall)


## Driven: a starting monster from the wall to the centre.
func _the_den_driven_a_starting_monster_fr(world: HungryWorld, bounds: Rect2, centre: Vector2, layout: HungryLayout, rules: Dot2DMassRules, den_gate: float, ring_rock: Vector3, den_rock: Vector3, ring_at: float, den_at: float, moat: float, wall: Vector2) -> void:
	world.spawn(1, wall)
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a starting monster spawns by the west wall, off the axis"):
		_drop(world)
		_done()
		return

	var small := monster.pieces[0].radius()
	# Planned 24 wider than the monster (`route_across`'s margin): a monster steered at a
	# waypoint swings wide on every turn, and at 12 it pressed a den rock's face.
	var route := layout.route_to(bounds, monster.centre(), centre, small + 24.0)

	_check(
		route.size() >= 2,
		"and has a route to the centre that has to turn to find the gates",
		"%d waypoints" % route.size()
	)

	var reached := 0
	var deepest := INF
	var ring_crossed := false

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

		if monster.centre().distance_to(centre) < ring_at - ring_rock.z:
			ring_crossed = true

	_the_den_part4(world, centre, rules, den_gate, den_rock, den_at, moat, monster, route, reached, deepest, ring_crossed, drive_from, drive_covered, drive_ground, drive_ticks)


func _the_den_part4(world: HungryWorld, centre: Vector2, rules: Dot2DMassRules, den_gate: float, den_rock: Vector3, den_at: float, moat: float, monster: HungryMonster, route: PackedVector2Array, reached: int, deepest: float, ring_crossed: bool, drive_from: Vector2, drive_covered: float, drive_ground: float, drive_ticks: int) -> void:
	_drive_report(drive_from, route, drive_covered, drive_ticks, drive_ground)
	_check(
		deepest > -2.0,
		"driven along it, it never overlaps a rock on any tick",
		"deepest %.1f into a face" % deepest
	)
	_check(
		ring_crossed and reached == route.size()
			and monster.centre().distance_to(centre) < den_at - den_rock.z,
		"and it comes through the ring and the den to the middle of it",
		"%d of %d waypoints, %.0f from the centre, the den's inside is %.0f"
			% [reached, route.size(), monster.centre().distance_to(centre), den_at - den_rock.z]
	)

	# And one that has eaten is held at the door

	# In the moat on the east axis, driven straight at the centre: the line runs through a
	# den GATE, so the only thing that can stop it is the gate's width.
	var door := centre + Vector2(den_at + den_rock.z + moat * 0.5, 0.0)
	var fed := rules.mass_for(den_gate * 0.5) * 1.6
	_straight_run(world, 1, door, centre, fed)
	monster = world.monster_for(1)

	_check(
		monster != null and monster.alive and monster.centre().distance_to(centre) > den_at,
		"one at %.0f mass driven through a den gate is held outside it" % fed,
		"stopped %.0f from the centre, the den's rocks stand at %.0f"
			% [monster.centre().distance_to(centre) if monster != null else -1.0, den_at]
	)

	_drop(world)
	_done()
