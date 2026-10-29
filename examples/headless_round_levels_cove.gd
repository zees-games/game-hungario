extends "headless_round_levels_atoll.gd"

## The level-by-level sections of the headless round suite (4 of 7).


## The reef's fifth part: a cove against the open-end wall, a refuge for the tight channel's tier.
##
## It is a room and not a wall: a leader is driven past it, and one that has eaten is pressed into a door to measure the depth behind.
func _test_the_cove() -> void:
	_section("the cove")

	var preset := HungryPreset.reef()
	var leader_mass := preset.win_mass
	# Lifted for the spits' reason: the leader below would end the round by eating on its
	# walk, and the reset would respawn it somewhere else.
	preset.win_mass = 1000000.0
	var world := _make_world(preset, SEED + 251)
	world.add_player(1, "Cov")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout
	var rules := world.tunables.mass_rules
	var first_cove := HungryLayout.REEF_COUNT * 2 + HungryLayout.ATOLL_COUNT \
		+ HungryLayout.SPIT_COUNT * 2

	if not _check(
		layout != null and layout.coves.size() == 1
			and layout.coves[0] == Vector2i(first_cove, 2)
			and layout.count() == first_cove + 2
			and layout.chains.size() == 2 and layout.rings.size() == 1 and layout.spits.size() == 2,
		"the reef has one cove of two posts after the spits, and is still two barriers, one ring and two spits",
		"coves %s, %d rocks" % [
			str(layout.coves) if layout != null else "none", layout.count() if layout != null else -1
		]
	):
		_drop(world)
		_done()
		return

	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var fore := layout.channels(0)
	var back := layout.channels(1)
	var across: Vector2 = fore[0]["normal"]

	if (Vector2(back[0]["mouth"]) - Vector2(fore[0]["mouth"])).dot(across) < 0.0:
		across = -across

	var chain_axis := Vector2(-across.y, across.x)
	# The open end: the side of the chain its widest channel is on.
	var open_side := signf(Vector2(fore[fore.size() - 1]["mouth"]).dot(chain_axis))
	var outward := chain_axis * open_side
	var wall := maxf(bounds.position.dot(outward), bounds.end.dot(outward))
	var fore_line := Vector2(fore[0]["mouth"]).dot(across)
	var sea := layout.blocks[first_cove]
	var reefward := layout.blocks[first_cove + 1]
	var sea_at := Vector2(sea.x, sea.y)
	var reef_at := Vector2(reefward.x, reefward.y)
	var won := rules.radius_for(leader_mass)
	var start := rules.radius_for(HungryContent.START_MASS)

	_the_cove_the_doors_which_are_the_leve(leader_mass, world, bounds, layout, rules, short_half, fore, across, outward, wall, fore_line, sea, reefward, sea_at, reef_at, won, start)


## The doors, which are the level.
func _the_cove_the_doors_which_are_the_leve(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, short_half: float, fore: Array[Dictionary], across: Vector2, outward: Vector2, wall: float, fore_line: float, sea: Vector3, reefward: Vector3, sea_at: Vector2, reef_at: Vector2, won: float, start: float) -> void:
	var door := HungryLayout.cove_door(short_half)
	var doors := PackedFloat32Array([
		wall - sea_at.dot(outward) - sea.z,
		sea_at.distance_to(reef_at) - sea.z - reefward.z,
		wall - reef_at.dot(outward) - reefward.z,
	])
	_check(
		absf(door - float(fore[0]["width"])) < 0.5
			and float(Array(doors).max()) - door < 0.5 and door - float(Array(doors).min()) < 0.5,
		"its three doors, measured off the discs, are each the fore reef's tight channel",
		"built %s, the tight channel %.0f" % [_widths(doors), float(fore[0]["width"])]
	)

	var mouth := (sea_at + reef_at) * 0.5
	_check(
		sea_at.dot(outward) > 0.0 and absf(sea_at.dot(outward) - reef_at.dot(outward)) < 0.5
			and sea_at.dot(across) < reef_at.dot(across)
			and reef_at.dot(across) + reefward.z < fore_line - layout.blocks[0].z,
		"it stands against the open-end wall, in front of the fore reef, sea-side post first",
		"posts %.0f off the wall, %.0f and %.0f in front of the fore reef"
			% [wall - sea_at.dot(outward), fore_line - sea_at.dot(across), fore_line - reef_at.dot(across)]
	)

	# A leader's water, round the outside

	var to_spit := INF
	var to_reef := INF

	for post in [sea, reefward]:
		var at := Vector2(post.x, post.y)

		for spit in layout.spits:
			for index in range(spit.x, spit.x + spit.y):
				var o := layout.blocks[index]
				to_spit = minf(to_spit, at.distance_to(Vector2(o.x, o.y)) - post.z - o.z)

		for index in range(layout.chains[0].x, layout.chains[0].x + layout.chains[0].y):
			var o := layout.blocks[index]
			to_reef = minf(to_reef, at.distance_to(Vector2(o.x, o.y)) - post.z - o.z)

	_check(
		to_spit > won * 2.0 + 40.0 and to_reef > won * 2.0 + 40.0,
		"the water between it and the spit, and between it and the fore reef, is wider than a leader",
		"%.0f to the spit, %.0f to the fore reef, a leader %.0f across" % [to_spit, to_reef, won * 2.0]
	)
	_check(
		absf(layout.narrowest_gate(bounds) - float(fore[0]["width"])) < 1.0,
		"and nothing on the map is tighter than the fore reef's tight channel",
		"narrowest %.0f" % layout.narrowest_gate(bounds)
	)

	_the_cove_a_room_it_holds_more_than_it(leader_mass, world, bounds, layout, rules, fore, across, outward, wall, sea, reefward, sea_at, reef_at, won, start, door, mouth, to_spit, to_reef)


## A room: it holds more than it lets out.
func _the_cove_a_room_it_holds_more_than_it(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, fore: Array[Dictionary], across: Vector2, outward: Vector2, wall: float, sea: Vector3, reefward: Vector3, sea_at: Vector2, reef_at: Vector2, won: float, start: float, door: float, mouth: Vector2, to_spit: float, to_reef: float) -> void:
	var inside := mouth + outward * ((wall - mouth.dot(outward)) * 0.5)
	var holds := minf(
		wall - inside.dot(outward),
		minf(inside.distance_to(sea_at) - sea.z, inside.distance_to(reef_at) - reefward.z)
	)
	_check(
		layout.in_cove(inside, bounds) and not layout.in_cove(mouth - outward * (sea.z + 1.0), bounds)
			and holds > door * 0.5 + 24.0 and holds < won,
		"it is a room: its middle holds a radius wider than a door lets out, and nothing a leader's size",
		"holds %.0f (%.0f mass), lets out %.0f (%.0f mass), a leader %.0f"
			% [holds, rules.mass_for(holds), door * 0.5, rules.mass_for(door * 0.5), won]
	)

	# Reach: just too big for a door

	var open_sea := Vector2(fore[fore.size() - 1]["mouth"]) - across * 600.0
	var outgrown := door * 0.5 + 16.0
	var sweep := layout.reach(bounds, open_sea, outgrown)
	var loose := 0
	var cove_points := 0

	for point: Vector2 in sweep["stranded"]:
		if layout.in_cove(point, bounds):
			cove_points += 1
		else:
			loose += 1

	_check(
		loose == 0 and cove_points > 0,
		"one just too big for a door reaches everything but the cove",
		"radius %.0f: %d of %d reached; %d stranded outside the cove, %d in it"
			% [outgrown, sweep["reached"], sweep["free"], loose, cove_points]
	)
	_check(
		layout.route_to(bounds, open_sea, inside, outgrown).is_empty()
			and not layout.route_to(bounds, open_sea, inside, door * 0.5 - 16.0).is_empty(),
		"so it has no route into the cove, and one just under a door has"
	)

	# Hunters: refused, as a harbour is

	var lurker := HungryHunters.largest_radius()
	var region := layout.main_region(bounds, lurker)
	var seeded := 0

	for at in HungryHunters.spawn_points_for(layout, bounds):
		if layout.in_cove(at, bounds):
			seeded += 1

	_check(
		HungryLayout.in_region(region, bounds, inside)
			and not HungryHunters.spawnable(layout, bounds, inside, region) and seeded == 0,
		"a lurker fits its doors, and a hunter still may not appear inside it",
		"lurker radius %.1f; %d seeded points inside" % [lurker, seeded]
	)

	_the_cove_driven_a_starting_monster_in(leader_mass, world, bounds, layout, rules, across, outward, wall, sea, reefward, reef_at, won, start, door, mouth, to_spit, to_reef, inside, holds, open_sea)


## Driven: a starting monster in, a leader past.
func _the_cove_driven_a_starting_monster_in(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, across: Vector2, outward: Vector2, wall: float, sea: Vector3, reefward: Vector3, reef_at: Vector2, won: float, start: float, door: float, mouth: Vector2, to_spit: float, to_reef: float, inside: Vector2, holds: float, open_sea: Vector2) -> void:
	world.spawn(1, open_sea)
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a starting monster spawns in the sea in front of the open end"):
		_drop(world)
		_done()
		return

	var small := monster.pieces[0].radius()
	var into := layout.route_to(bounds, monster.centre(), inside, small + 24.0)
	var small_drive := _drive_route(world, monster, into, outward, TICK_RATE * 30)
	_check(
		into.size() >= 1 and small_drive["deepest"] > -2.0,
		"driven along its route into the cove, it never overlaps a rock on any tick",
		"%d waypoints, deepest %.1f into a face" % [into.size(), small_drive["deepest"]]
	)
	_check(
		small_drive["reached"] == into.size() and layout.in_cove(monster.centre(), bounds),
		"and stands inside it",
		"%d of %d waypoints, at %s" % [small_drive["reached"], into.size(), str(monster.centre())]
	)

	# A leader from the bay behind the northern spit to the run-round's water: the one
	# way between is between the cove and the spit, and it has to still be a way.
	var spit_run := layout.spits[0] if Vector2(layout.blocks[layout.spits[0].x].x, layout.blocks[layout.spits[0].x].y).dot(outward) > 0.0 else layout.spits[1]
	var spit_near := layout.blocks[spit_run.x]
	var bay := Vector2(spit_near.x, spit_near.y) + outward * (spit_near.z + won + 60.0)
	var beyond := reef_at + across * 400.0 - outward * 200.0
	world.spawn(1, bay)
	_run_ticks(world, 2)
	monster = world.monster_for(1)
	world.feed_player(1, leader_mass - monster.mass())
	_run_ticks(world, 2)

	# A 12-unit margin on a 12-unit grid: the water between the cove and the spit leaves a
	# leader 70 to spare, and 24 either side on a 24-unit grid is a band a grid can miss.
	var leader := monster.pieces[0].radius()
	var past := layout.route_to(bounds, monster.centre(), beyond, leader + 12.0, 12.0)
	var leader_drive := _drive_route(world, monster, past, across, TICK_RATE * 60)
	_check(
		monster.pieces.size() == 1 and leader > won - 2.0
			and past.size() >= 1 and leader_drive["deepest"] > -2.0,
		"a leader driven from the bay behind the spit past the cove never overlaps a rock",
		"radius %.0f of %.0f in %d pieces, %d waypoints, deepest %.1f into a face"
			% [leader, won, monster.pieces.size(), past.size(), leader_drive["deepest"]]
	)
	_check(
		leader_drive["reached"] == past.size() and monster.centre().dot(across) > reef_at.dot(across) + reefward.z,
		"and comes out on the reef side of the cove",
		"%d of %d waypoints, at %s" % [leader_drive["reached"], past.size(), str(monster.centre())]
	)
	_check(
		small_drive["covered"] > small_drive["length"] * 0.9
			and leader_drive["covered"] > leader_drive["length"] * 0.9
			and small_drive["pace"] > 0.95 and leader_drive["pace"] > 0.95,
		"and both covered their routes at their ground speed",
		"in %.0f of %.0f at %.2f of ground speed; past %.0f of %.0f at %.2f"
			% [small_drive["covered"], small_drive["length"], small_drive["pace"],
				leader_drive["covered"], leader_drive["length"], leader_drive["pace"]]
	)

	_the_cove_straight_at_the_door_between(world, bounds, layout, rules, outward, wall, sea, won, start, door, mouth, to_spit, to_reef, holds, monster)


## Straight at the door between the posts.
func _the_cove_straight_at_the_door_between(world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, outward: Vector2, wall: float, sea: Vector3, won: float, start: float, door: float, mouth: Vector2, to_spit: float, to_reef: float, holds: float, monster: HungryMonster) -> void:
	var from_sea := mouth - outward * 500.0
	var to_wall := mouth + outward * 1000.0
	var line := mouth.dot(outward)
	var small_got := _straight_run(world, 1, from_sea, to_wall, 0.0)
	_check(
		small_got > line + sea.z,
		"a starting monster driven straight at the door between the posts comes in",
		"reached %.0f, the posts' line is %.0f" % [small_got, line]
	)

	var fed := rules.mass_for(door * 0.5) * 1.6
	var big_got := _straight_run(world, 1, from_sea, to_wall, fed)
	monster = world.monster_for(1)
	# The reach that matters: how far its front gets toward a starting monster tucked
	# against the wall at the back of the cove.
	var tucked := mouth.dot(outward) + (wall - mouth.dot(outward)) - start
	var short_by := tucked - start - (big_got + (monster.pieces[0].radius() if monster != null else 0.0))
	_check(
		big_got < line - sea.z and not layout.in_cove(monster.centre(), bounds),
		"one of %.0f mass on the same line is held at it" % fed,
		"reached %.0f, the posts' line is %.0f" % [big_got, line]
	)
	print("        held at %.0f with its front %.0f short of a starting monster at the back; the room holds %.0f, the doors let out %.0f"
		% [big_got, short_by, holds, door * 0.5])
	print("        waters round it: %.0f to the spit, %.0f to the fore reef, a leader %.0f across"
		% [to_spit, to_reef, won * 2.0])
	_check(
		short_by > 0.0,
		"and its front stops short of a starting monster at the back of the cove",
		"%.0f short, a starting monster %.0f across" % [short_by, start * 2.0]
	)

	_drop(world)
	_done()


## The shallows: five lines of posts whose gaps widen toward the open water, so how far in a monster can go is a function of its size.
##
## Gaps are measured off the discs against the description, then three monsters are driven: a starting one to the shallow wall, a middling one to its band, a leader straight in.
func _test_the_shallows() -> void:
	_section("the shallows")

	var preset := HungryPreset.shallows()
	var leader_mass := preset.win_mass
	# Lifted for the cove's reason: the fed monsters below eat on their way, and a round
	# won mid-drive resets the world under them.
	preset.win_mass = 1000000.0
	var world := _make_world(preset, SEED + 263)
	world.add_player(1, "Sha")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout
	var rules := world.tunables.mass_rules
	var lines := HungryLayout.SHALLOWS_LINES

	if not _check(
		layout != null and layout.id == HungryLayout.SHALLOWS and layout.chains.size() == lines
			and layout.rings.is_empty() and bounds.size.x >= bounds.size.y,
		"the shallows are five lines of posts across a world wider than it is deep",
		"%d lines" % (layout.chains.size() if layout != null else -1)
	):
		_drop(world)
		_done()
		return

	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var widths := HungryLayout.shallows_widths(short_half)
	var won := rules.radius_for(leader_mass)
	var start := rules.radius_for(HungryContent.START_MASS)
	var line_x := PackedFloat32Array()
	var post_r := PackedFloat32Array()

	_the_shallows_the_lines_measured_off_the_d(leader_mass, world, bounds, layout, rules, lines, short_half, widths, won, line_x, post_r)


## The lines, measured off the discs.
func _the_shallows_the_lines_measured_off_the_d(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, lines: int, short_half: float, widths: PackedFloat32Array, won: float, line_x: PackedFloat32Array, post_r: PackedFloat32Array) -> void:
	var wrong := PackedStringArray()

	for line in range(lines):
		var run := layout.chains[line]
		var first := layout.blocks[run.x]
		var last := layout.blocks[run.x + run.y - 1]
		var gaps := PackedFloat32Array([first.y - first.z - bounds.position.y])

		for channel in layout.channels(line):
			gaps.append(float(channel["width"]))

		gaps.append(bounds.end.y - last.y - last.z)

		for index in range(run.x, run.x + run.y):
			if absf(layout.blocks[index].x - first.x) > 0.01:
				wrong.append("line %d is not straight" % line)

		for gap in gaps:
			if absf(gap - widths[line]) > 0.5:
				wrong.append("line %d: %.1f against %.1f" % [line, gap, widths[line]])

		line_x.append(first.x)
		post_r.append(first.z)

	_check(
		wrong.is_empty(),
		"every gap of every line, walls included, measured off the discs, is its line's width",
		"%s; widths %s" % [", ".join(wrong.slice(0, 3)), _widths(widths)]
	)

	var ordered := true

	for line in range(1, lines):
		ordered = ordered and widths[line] > widths[line - 1] and line_x[line] > line_x[line - 1]

	_check(
		ordered and absf(widths[0] - HungryLayout.channel_widths(short_half)[0]) < 0.5
			and widths[lines - 2] < won * 2.0 and widths[lines - 1] > won * 2.0 + 40.0,
		"they widen line by line from the shallow wall, the tightest is the reef's tight channel, and a leader fits only the last",
		"%s at x %s; a leader %.0f across" % [_widths(widths), _widths(line_x), won * 2.0]
	)

	_the_shallows_the_bands_never_narrower_tha(leader_mass, world, bounds, layout, rules, lines, short_half, widths, won, line_x, post_r)


## The bands: never narrower than the gap that lets you in.
func _the_shallows_the_bands_never_narrower_tha(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, lines: int, short_half: float, widths: PackedFloat32Array, won: float, line_x: PackedFloat32Array, post_r: PackedFloat32Array) -> void:
	var waters := PackedFloat32Array()
	var slots := PackedStringArray()

	for line in range(lines):
		var water := line_x[line] - post_r[line] - bounds.position.x

		if line > 0:
			water = INF
			var inner := layout.chains[line - 1]
			var outer := layout.chains[line]

			for a in range(inner.x, inner.x + inner.y):
				for b in range(outer.x, outer.x + outer.y):
					var pa := layout.blocks[a]
					var pb := layout.blocks[b]
					water = minf(water, Vector2(pa.x, pa.y).distance_to(Vector2(pb.x, pb.y)) - pa.z - pb.z)

		waters.append(water)

		if water < widths[line] + 1.0:
			slots.append("band %d: %.0f against a gap of %.0f" % [line, water, widths[line]])

	_check(
		slots.is_empty() and waters[0] * 0.5 > widths[0] * 0.5 + 16.0,
		"no band is narrower than the gap into it, and the deepest holds more than its line lets out",
		"waters %s against gaps %s%s" % [_widths(waters), _widths(widths), "" if slots.is_empty() else "; " + ", ".join(slots)]
	)

	_the_shallows_reach_the_floor_recedes_one_(leader_mass, world, bounds, layout, rules, lines, short_half, widths, won, line_x, post_r, waters)


## Reach: the floor recedes one band per line as a monster grows.
func _the_shallows_reach_the_floor_recedes_one_(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, lines: int, short_half: float, widths: PackedFloat32Array, won: float, line_x: PackedFloat32Array, post_r: PackedFloat32Array, waters: PackedFloat32Array) -> void:
	# The middle bay in front of the inlet: the open wall's own middle is the inlet's room.
	var open_water := _shallows_open_water(layout, bounds)
	var all := layout.reach(bounds, open_water, widths[0] * 0.5 - 16.0)
	_check(
		all["reached"] == all["free"],
		"one just under the tightest line reaches all of the floor",
		"%d of %d" % [all["reached"], all["free"]]
	)

	var tiers := PackedStringArray()
	var leaks := PackedStringArray()
	var last_reached := 1 << 30
	var groyne_widest := HungryLayout.groyne_doors(short_half)[2]

	for line in range(lines):
		var over := widths[line] * 0.5 + 16.0
		# From the open wall at this size: just over the last line is wider than a leader,
		# and the leader's own start would be inside the wall for it.
		var sweep := layout.reach(bounds, open_water, over)
		var stranded: PackedVector2Array = sweep["stranded"]
		var outside := 0

		var start_bay := layout.bay_of(open_water, bounds)
		# Too big for every groyne door and for the last line, the bays it did not start
		# in are behind both; the groynes' own section asks them.
		var walled_in := over * 2.0 > groyne_widest and over * 2.0 > widths[lines - 1]

		for point: Vector2 in stranded:
			# The rock pools and the inlet are in the open water and shut to everybody
			# over the first and second lines' limits; their own sections ask them.
			if layout.shallows_band(point, bounds) > line and not layout.in_pool(point, bounds) \
					and not layout.in_inlet(point, bounds) \
					and not (walled_in and layout.bay_of(point, bounds) != start_bay):
				outside += 1

		tiers.append("%.0f mass: %d of %d" % [rules.mass_for(over), sweep["reached"], sweep["free"]])

		# Reached, not stranded: bigger monsters have less free floor, and the sills' posts
		# take more of the third band from the fourth line's size than from the third's.
		if outside > 0 or int(sweep["reached"]) >= last_reached:
			leaks.append("line %d: %d stranded in front of it, %d reached" % [line, outside, sweep["reached"]])

		last_reached = int(sweep["reached"])

	print("        reached from the open water just over each line: %s" % ", ".join(tiers))
	_check(
		leaks.is_empty(),
		"just over each line's limit, a monster reaches everything in front of that line and loses more floor at every line",
		", ".join(leaks)
	)

	_the_shallows_hunters_the_deepest_band_is_(leader_mass, world, bounds, layout, rules, lines, widths, won, line_x, post_r, waters, open_water)


## Hunters: the deepest band is refused them.
func _the_shallows_hunters_the_deepest_band_is_(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, lines: int, widths: PackedFloat32Array, won: float, line_x: PackedFloat32Array, post_r: PackedFloat32Array, waters: PackedFloat32Array, open_water: Vector2) -> void:
	var lurker := HungryHunters.largest_radius()
	var region := layout.main_region(bounds, lurker)
	var deep := Vector2(bounds.position.x + waters[0] * 0.5, bounds.get_center().y)
	var seeded := 0
	var elsewhere := 0

	for at in HungryHunters.spawn_points_for(layout, bounds):
		if layout.shallows_band(at, bounds) == 0:
			seeded += 1
		else:
			elsewhere += 1

	_check(
		layout.shallows_band(deep, bounds) == 0 and HungryLayout.in_region(region, bounds, deep)
			and not HungryHunters.spawnable(layout, bounds, deep, region)
			and seeded == 0 and elsewhere >= 12,
		"a lurker fits every line, and a hunter may not appear behind the tightest",
		"lurker radius %.1f; %d seeded points behind it, %d elsewhere" % [lurker, seeded, elsewhere]
	)

	# Driven: a starting monster to the shallow wall

	world.spawn(1, open_water)
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a starting monster spawns in the open water"):
		_drop(world)
		_done()
		return

	var small := monster.pieces[0].radius()
	# Planned 48 wide rather than 24: the route crosses five lines in three legs, each
	# threading gaps on the slant, and a waypoint counts as reached 40 units short of it.
	var into := layout.route_to(bounds, monster.centre(), deep, small + 48.0, 12.0)
	var small_drive := _drive_route(world, monster, into, Vector2.LEFT, TICK_RATE * 60)
	_check(
		into.size() >= 1 and small_drive["deepest"] > -2.0
			and small_drive["reached"] == into.size() and layout.shallows_band(monster.centre(), bounds) == 0,
		"driven along its route through all five lines, it never overlaps a post and stands against the shallow wall",
		"radius %.0f, %d of %d waypoints, deepest %.1f into a face, band %d"
			% [monster.pieces[0].radius(), small_drive["reached"], into.size(), small_drive["deepest"],
				layout.shallows_band(monster.centre(), bounds)]
	)

	_the_shallows_a_middling_monster_as_far_as(leader_mass, world, bounds, layout, rules, lines, widths, won, line_x, post_r, open_water, monster, small_drive)


## A middling monster: as far as its size allows.
func _the_shallows_a_middling_monster_as_far_as(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, lines: int, widths: PackedFloat32Array, won: float, line_x: PackedFloat32Array, post_r: PackedFloat32Array, open_water: Vector2, monster: HungryMonster, small_drive: Dictionary) -> void:
	# Just over the second line's limit rather than halfway to the third's: halfway leaves
	# 28 units a side in the third line's gaps, less than the 40 short of a waypoint that
	# counts as reaching it, and a route pulled tight past a post then clips it.
	var middling := widths[1] * 0.5 + 6.0
	# A quarter of the way up rather than the middle: the middle of this band is its sill.
	var band_two := Vector2(
		(line_x[1] + post_r[1] + line_x[2] - post_r[2]) * 0.5, bounds.get_center().y + bounds.size.y * 0.125
	)
	# From the leader's band, not the open water: a monster this size eats what it sweeps
	# on the way, and from the open wall it grew 36 units of radius — past the margin its
	# route was planned with — before it reached the band it was sent to.
	var band_four := Vector2(
		(line_x[lines - 2] + post_r[lines - 2] + line_x[lines - 1] - post_r[lines - 1]) * 0.5,
		bounds.get_center().y
	)
	world.spawn(1, band_four)
	_run_ticks(world, 2)
	monster = world.monster_for(1)
	world.feed_player(1, rules.mass_for(middling) - monster.mass())
	_run_ticks(world, 2)

	var mid := monster.pieces[0].radius()
	var mid_route := layout.route_to(bounds, monster.centre(), band_two, mid + 36.0, 12.0)
	var mid_drive := _drive_route(world, monster, mid_route, Vector2.LEFT, TICK_RATE * 60)
	_check(
		monster.pieces.size() == 1 and mid > widths[1] * 0.5 and mid < widths[2] * 0.5
			and mid_route.size() >= 1 and mid_drive["deepest"] > -2.0
			and mid_drive["reached"] == mid_route.size() and layout.shallows_band(monster.centre(), bounds) == 2,
		"one of %.0f mass, driven in from the leader's band, gets through two more lines to the band between the second and the third" % rules.mass_for(middling),
		"radius %.0f, %.0f on arrival, in %d pieces, %d of %d waypoints, deepest %.1f, band %d"
			% [mid, monster.pieces[0].radius(), monster.pieces.size(), mid_drive["reached"], mid_route.size(), mid_drive["deepest"],
				layout.shallows_band(monster.centre(), bounds)]
	)
	_check(
		small_drive["covered"] > small_drive["length"] * 0.9 and mid_drive["covered"] > mid_drive["length"] * 0.9
			and small_drive["pace"] > 0.95 and mid_drive["pace"] > 0.95,
		"and both covered their routes at their ground speed",
		"in %.0f of %.0f at %.2f of ground speed; to the band %.0f of %.0f at %.2f"
			% [small_drive["covered"], small_drive["length"], small_drive["pace"],
				mid_drive["covered"], mid_drive["length"], mid_drive["pace"]]
	)

	# Straight on from where it stands: the second line holds it.
	var from_band := monster.centre()
	var mid_mass := monster.mass()
	var mid_got := _straight_run(world, 1, from_band, Vector2(bounds.position.x, from_band.y), mid_mass)
	monster = world.monster_for(1)
	_check(
		monster != null and -mid_got > line_x[1] + post_r[1] - 1.0
			and layout.shallows_band(monster.centre(), bounds) == 2,
		"driven straight at the second line from there, it is held in front of it",
		"its furthest west %.0f, the second line's face %.0f" % [-mid_got, line_x[1] + post_r[1]]
	)

	_the_shallows_the_leader_through_the_last_(leader_mass, world, bounds, layout, lines, won, line_x, post_r, open_water, monster)


## The leader: through the last line and held at its tree line.
func _the_shallows_the_leader_through_the_last_(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, lines: int, won: float, line_x: PackedFloat32Array, post_r: PackedFloat32Array, open_water: Vector2, monster: HungryMonster) -> void:
	var gap_mouth: Vector2 = layout.channels(lines - 1)[2]["mouth"]
	var leader_from := Vector2(open_water.x, gap_mouth.y)
	var leader_got := _straight_run(
		world, 1, leader_from, Vector2(bounds.position.x, gap_mouth.y), leader_mass
	)
	monster = world.monster_for(1)
	var leader_band := layout.shallows_band(monster.centre(), bounds) if monster != null else -1
	_check(
		monster != null and monster.pieces.size() == 1 and monster.pieces[0].radius() > won - 2.0
			and -leader_got < line_x[lines - 1] - post_r[lines - 1]
			and -leader_got > line_x[lines - 2] + post_r[lines - 2] and leader_band == lines - 1,
		"a leader driven straight in goes through the last line and is held at the one inside it",
		"furthest west %.0f: the last line at %.0f, its tree line's face at %.0f; band %d"
			% [-leader_got, line_x[lines - 1], line_x[lines - 2] + post_r[lines - 2], leader_band]
	)
	print("        the leader's floor starts %.0f in from the open wall, %.0f%% of the width"
		% [bounds.end.x - (line_x[lines - 2] + post_r[lines - 2]),
			(bounds.end.x - (line_x[lines - 2] + post_r[lines - 2])) / bounds.size.x * 100.0])

	_drop(world)
	_done()
