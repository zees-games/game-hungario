extends "headless_round_levels_reef.gd"

## The level-by-level sections of the headless round suite (3 of 7).


## The reef's third part: an atoll in the open sea, whose gates widen from the wall side to the reef side.
##
## It is about which side a monster comes in from, so each gate is driven at the size it is for, like the den and the harbours.
func _test_the_atoll() -> void:
	_section("the atoll")

	var preset := HungryPreset.reef()
	# Lifted for the same reason as the lagoon's: the fed monsters below eat on their way,
	# and a round that ended under one would respawn it somewhere else.
	var leader_mass := preset.win_mass
	preset.win_mass = 1000000.0
	var world := _make_world(preset, SEED + 227)
	world.add_player(1, "Ata")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout
	var rules := world.tunables.mass_rules

	if not _check(
		layout != null and layout.rings.size() == 1
			and layout.rings[0] == Vector2i(HungryLayout.REEF_COUNT * 2, HungryLayout.ATOLL_COUNT),
		"the reef has an atoll: one ring of four rocks after both barriers",
		"rings %s" % (str(layout.rings) if layout != null else "none")
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

	var fore_line := Vector2(fore[0]["mouth"]).dot(across)
	var reef_rock := layout.blocks[0].z
	var middle := layout.atoll_centre()
	var run := layout.rings[0]

	_check(
		middle.dot(across) < fore_line - reef_rock,
		"and it stands in the open sea in front of the fore reef, not in the lagoon",
		"%.0f in front of the fore reef" % (fore_line - middle.dot(across))
	)

	_the_atoll_the_gates_which_are_the_leve(leader_mass, world, bounds, layout, rules, short_half, fore, back, across, fore_line, reef_rock, middle, run)


## The gates, which are the level.
func _the_atoll_the_gates_which_are_the_leve(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, short_half: float, fore: Array[Dictionary], back: Array[Dictionary], across: Vector2, fore_line: float, reef_rock: float, middle: Vector2, run: Vector2i) -> void:
	var wanted := HungryLayout.atoll_widths(short_half)
	var measured := layout.ring_gates(0)
	var agree := wanted.size() == measured.size()

	for index in range(mini(wanted.size(), measured.size())):
		if absf(wanted[index] - measured[index]) > 1.0:
			agree = false

	_check(
		agree,
		"the atoll builds the four gates it describes",
		"built %s, described %s" % [_widths(measured), _widths(wanted)]
	)

	# Each gate's mouth, measured off the discs: gate k is between ring rocks k and k+1.
	var mouths: Array[Vector2] = []

	for step in range(run.y):
		var a := layout.blocks[run.x + step]
		var b := layout.blocks[run.x + (step + 1) % run.y]
		var at := Vector2(a.x, a.y)
		var towards := (Vector2(b.x, b.y) - at).normalized()
		mouths.append(at + towards * (a.z + measured[step] * 0.5))

	var wall_gate := mouths[0].dot(across)
	var reef_gate := mouths[2].dot(across)
	_check(
		measured[0] < measured[1] and measured[1] < measured[2]
			and absf(measured[1] - measured[3]) < 1.0
			and wall_gate < middle.dot(across) and reef_gate > middle.dot(across),
		"its gates widen from the wall side to the reef side, the flanks between",
		"%.0f facing the wall, %.0f and %.0f on the flanks, %.0f facing the reef"
			% [measured[0], measured[1], measured[3], measured[2]]
	)

	# [b]One band, sorted by side.[/b] The reef-side gate is the back reef's gate, so the
	# atoll shuts out exactly who the back reef shuts out everywhere but its door; and its
	# tightest is the fore reef's tight channel, so nothing on the map got tighter.
	var won := rules.radius_for(leader_mass)
	var back_gate := float(back[1]["width"])
	_check(
		absf(measured[2] - back_gate) < 1.0 and won > measured[2] * 0.5
			and absf(measured[0] - float(fore[0]["width"])) < 1.0
			and absf(layout.narrowest_gate(bounds) - float(fore[0]["width"])) < 1.0,
		"it admits exactly the back reef's band, and nothing on the map is tighter than before",
		"reef side admits %.0f mass (the back reef's gate %.0f), a leader is %.0f across; tightest %.0f"
			% [rules.mass_for(measured[2] * 0.5), back_gate, won * 2.0, layout.narrowest_gate(bounds)]
	)

	var inside := INF

	for step in range(run.y):
		var rock := layout.blocks[run.x + step]
		inside = minf(inside, Vector2(rock.x, rock.y).distance_to(middle) - rock.z)

	_check(
		inside > measured[2] * 0.5,
		"inside, a monster at the reef-side gate's limit has room to stand",
		"%.0f clear of every rock from the centre, against a radius of %.0f"
			% [inside, measured[2] * 0.5]
	)

	_the_atoll_an_island_not_a_plug(world, bounds, layout, rules, fore, across, fore_line, reef_rock, middle, run, measured, wall_gate, reef_gate, won, inside)


## An island, not a plug.
func _the_atoll_an_island_not_a_plug(world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, fore: Array[Dictionary], across: Vector2, fore_line: float, reef_rock: float, middle: Vector2, run: Vector2i, measured: PackedFloat32Array, wall_gate: float, reef_gate: float, won: float, inside: float) -> void:
	# The water either side, measured off the discs: wider than a leader, so the atoll is
	# walked round from either side and nothing behind it is a pocket.
	var to_reef := INF
	var to_wall := INF
	var sea_wall := minf(bounds.position.dot(across), bounds.end.dot(across))

	for step in range(run.y):
		var rock := layout.blocks[run.x + step]
		var at := Vector2(rock.x, rock.y)
		to_wall = minf(to_wall, at.dot(across) - sea_wall - rock.z)

		for index in range(layout.chains[0].x, layout.chains[0].x + layout.chains[0].y):
			var other := layout.blocks[index]
			to_reef = minf(to_reef, at.distance_to(Vector2(other.x, other.y)) - rock.z - other.z)

	_check(
		to_reef > won * 2.0 and to_wall > won * 2.0,
		"the water between it and the reef, and between it and the wall, is wider than a leader",
		"%.0f to the reef, %.0f to the wall, a leader %.0f across" % [to_reef, to_wall, won * 2.0]
	)

	# [b]The constraint that placed it.[/b] A leader walks from in front of the tight end
	# to the open end along the fore reef — the lagoon section drives exactly that leg —
	# and an atoll in the middle of the sea stood on it.
	var west: Vector2 = Vector2(fore[0]["mouth"]) - across * 900.0
	var leg := layout.route_across(west, won)
	var clear_of_leg := INF

	if leg.size() > 0:
		for step in range(run.y):
			var rock := layout.blocks[run.x + step]
			var at := Vector2(rock.x, rock.y)
			clear_of_leg = minf(
				clear_of_leg,
				at.distance_to(Geometry2D.get_closest_point_to_segment(at, west, leg[0]))
					- rock.z - won
			)

	_check(
		leg.size() > 0 and clear_of_leg > 24.0,
		"and it stands off the line a leader walks from the tight end to the open end",
		"%.0f clear of a leader on that leg" % clear_of_leg
	)

	# Reach, at the size each side is for

	var over := measured[2] * 0.5 + 16.0
	var open_water := middle + across * (fore_line - reef_rock - middle.dot(across)) * 0.5
	var sweep := layout.reach(bounds, open_water, over)
	var elsewhere := 0

	for point in sweep["stranded"]:
		if point.distance_to(middle) > inside:
			elsewhere += 1

	_check(
		sweep["free"] - sweep["reached"] > 0 and elsewhere == 0,
		"one 16 over the reef-side limit reaches everything but the atoll's inside",
		"radius %.0f: %d of %d reached, %d stranded outside the atoll"
			% [over, sweep["reached"], sweep["free"], elsewhere]
	)

	_the_atoll_driven_round_to_the_reef_sid(world, bounds, layout, rules, across, middle, measured, wall_gate, reef_gate, inside, to_reef, to_wall)


## Driven: round to the reef side.
func _the_atoll_driven_round_to_the_reef_sid(world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, across: Vector2, middle: Vector2, measured: PackedFloat32Array, wall_gate: float, reef_gate: float, inside: float, to_reef: float, to_wall: float) -> void:
	# Between the flank and reef-side limits, so the only way in faces the reef; started
	# behind the atoll, off the axis. Fed to just over the flank limit, not the band's
	# middle, so the 97 mass swallowed on arrival still fits; the band reached is asserted.
	var middling := measured[1] * 0.5 + 2.0
	var start := middle - across * (to_wall * 0.5 + 200.0) \
		+ Vector2(-across.y, across.x) * 700.0
	world.spawn(1, start)
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a monster spawns behind the atoll"):
		_drop(world)
		_done()
		return

	world.feed_player(1, rules.mass_for(middling) - monster.mass())
	_run_ticks(world, 2)

	# On a 12-unit grid rather than 24: planned 24 wider than the monster, the reef-side
	# gate leaves 16 either side of its throat, and a 24-unit grid steps straight over a
	# band that narrow and reports no route at all.
	var route := layout.route_to(
		bounds, monster.centre(), middle, monster.pieces[0].radius() + 24.0, 12.0
	)
	var planned := 0.0
	var previous := monster.centre()

	for point in route:
		planned += previous.distance_to(point)
		previous = point

	var arrived := monster.pieces[0].radius()
	_check(
		arrived > measured[1] * 0.5 and arrived + 24.0 < measured[2] * 0.5
			and route.size() >= 2 and planned > monster.centre().distance_to(middle) * 1.5,
		"one too wide for the flanks has a route in, and it goes round to the reef side",
		"radius %.0f (%.0f mass) between the flank's %.0f and the reef side's %.0f: %d waypoints, %.0f long against %.0f straight"
			% [arrived, monster.mass(), measured[1] * 0.5, measured[2] * 0.5,
				route.size(), planned, monster.centre().distance_to(middle)]
	)

	var reached := 0
	var deepest := INF
	var entered_from := -INF

	var drive_from := monster.centre()
	var drive_covered := 0.0
	var drive_ground := 0.0
	var drive_ticks := 0

	_the_atoll_part5(world, layout, rules, across, middle, measured, wall_gate, reef_gate, inside, to_reef, to_wall, monster, route, reached, deepest, entered_from, drive_from, drive_covered, drive_ground, drive_ticks)


func _the_atoll_part5(world: HungryWorld, layout: HungryLayout, rules: Dot2DMassRules, across: Vector2, middle: Vector2, measured: PackedFloat32Array, wall_gate: float, reef_gate: float, inside: float, to_reef: float, to_wall: float, monster: HungryMonster, route: PackedVector2Array, reached: int, deepest: float, entered_from: float, drive_from: Vector2, drive_covered: float, drive_ground: float, drive_ticks: int) -> void:
	for _i in range(TICK_RATE * 40):
		if reached >= route.size():
			break

		if monster.centre().distance_to(route[reached]) < 40.0:
			reached += 1
			continue

		var was_outside := monster.centre().distance_to(middle) > inside + 40.0
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

		if was_outside and monster.centre().distance_to(middle) <= inside + 40.0:
			entered_from = (monster.centre() - middle).dot(across)

	_drive_report(drive_from, route, drive_covered, drive_ticks, drive_ground)
	_check(
		deepest > -2.0,
		"driven along it, it never overlaps a rock on any tick",
		"deepest %.1f into a face" % deepest
	)
	_check(
		reached == route.size() and monster.centre().distance_to(middle) < inside
			and entered_from > 0.0,
		"and it comes in through the gate that faces the reef",
		"%d of %d waypoints, %.0f from the centre, crossed the ring %.0f on the reef side"
			% [reached, route.size(), monster.centre().distance_to(middle), entered_from]
	)

	_the_atoll_straight_at_a_gate_at_three_(world, rules, across, middle, measured, wall_gate, reef_gate, inside, to_reef, to_wall, monster)


## Straight at a gate, at three sizes.
func _the_atoll_straight_at_a_gate_at_three_(world: HungryWorld, rules: Dot2DMassRules, across: Vector2, middle: Vector2, measured: PackedFloat32Array, wall_gate: float, reef_gate: float, inside: float, to_reef: float, to_wall: float, monster: HungryMonster) -> void:
	# From the wall side, straight at the centre: the line runs through the tight gate.
	var behind := middle - across * (to_wall * 0.5 + 100.0)
	_straight_run(world, 1, behind, middle, 0.0)
	monster = world.monster_for(1)
	_check(
		monster != null and monster.alive and monster.centre().distance_to(middle) < inside,
		"a starting monster driven straight in from the wall side comes through the tight gate",
		"stopped %.0f from the centre"
			% (monster.centre().distance_to(middle) if monster != null else -1.0)
	)

	var flanker := rules.mass_for((measured[0] * 0.5 + measured[1] * 0.5) * 0.5)
	_straight_run(world, 1, behind, middle, flanker)
	monster = world.monster_for(1)
	_check(
		monster != null and monster.alive
			and (monster.centre() - middle).dot(across) < wall_gate - middle.dot(across),
		"one of %.0f mass on the same line is held at the tight gate — it fits the flanks" % flanker,
		"stopped %.0f from the centre, the tight gate is %.0f"
			% [monster.centre().distance_to(middle) if monster != null else -1.0,
				middle.dot(across) - wall_gate]
	)

	# From the reef side, straight at the centre through the widest gate.
	var fed := rules.mass_for(measured[2] * 0.5) * 1.6
	_straight_run(world, 1, middle + across * (to_reef * 0.5 + 200.0), middle, fed)
	monster = world.monster_for(1)
	_check(
		monster != null and monster.alive
			and (monster.centre() - middle).dot(across) > reef_gate - middle.dot(across),
		"and one at %.0f mass driven through the reef-side gate is held outside it" % fed,
		"stopped %.0f from the centre, the gate is %.0f"
			% [monster.centre().distance_to(middle) if monster != null else -1.0,
				reef_gate - middle.dot(across)]
	)

	_drop(world)
	_done()


## The reef's spits: two rocks from the sea wall either side of the atoll, which a middling monster goes through and a leader has to go round.
##
## It is about the difference between two routes across one line, so both are driven, then each gap is driven at the size it is for.
func _test_the_spits() -> void:
	_section("the spits")

	var preset := HungryPreset.reef()
	# Lifted for the lagoon's reason: the leader below eats on a 2500-unit walk, and a
	# round that ended under it would respawn it somewhere else.
	var leader_mass := preset.win_mass
	preset.win_mass = 1000000.0
	var world := _make_world(preset, SEED + 241)
	world.add_player(1, "Spi")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout
	var rules := world.tunables.mass_rules
	var first_spit := HungryLayout.REEF_COUNT * 2 + HungryLayout.ATOLL_COUNT

	if not _check(
		layout != null and layout.spits.size() == 2
			and layout.spits[0] == Vector2i(first_spit, HungryLayout.SPIT_COUNT)
			and layout.spits[1] == Vector2i(first_spit + HungryLayout.SPIT_COUNT, HungryLayout.SPIT_COUNT)
			and layout.chains.size() == 2 and layout.rings.size() == 1,
		"the reef has two spits of two rocks after the atoll, and is still two barriers and one ring",
		"spits %s" % (str(layout.spits) if layout != null else "none")
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
	var fore_line := Vector2(fore[0]["mouth"]).dot(across)
	var reef_rock := layout.blocks[0].z
	var middle := layout.atoll_centre()
	var sea_wall := minf(bounds.position.dot(across), bounds.end.dot(across))
	var won := rules.radius_for(leader_mass)

	_the_spits_the_gaps_which_are_the_level(leader_mass, world, bounds, layout, rules, short_half, fore, across, chain_axis, fore_line, reef_rock, middle, sea_wall, won)


## The gaps, which are the level.
func _the_spits_the_gaps_which_are_the_level(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, short_half: float, fore: Array[Dictionary], across: Vector2, chain_axis: Vector2, fore_line: float, reef_rock: float, middle: Vector2, sea_wall: float, won: float) -> void:
	var wanted := HungryLayout.spit_widths(short_half)
	var agree := true
	var built := PackedStringArray()

	for spit in range(layout.spits.size()):
		var measured := layout.spit_gaps(spit, bounds)
		built.append(_widths(measured))

		if measured.size() != wanted.size():
			agree = false
			continue

		for index in range(wanted.size()):
			if absf(wanted[index] - measured[index]) > 1.0:
				agree = false

	_check(
		agree and wanted[0] < wanted[1],
		"each spit builds the two gaps it describes, the tight one against the wall",
		"built %s, described %s" % [" and ".join(built), _widths(wanted)]
	)

	# In the open sea, from the sea wall toward the reef, one either side of the atoll.
	var placed := true
	var sides := PackedFloat32Array()
	var reef_end := -INF

	for spit in range(layout.spits.size()):
		var run := layout.spits[spit]
		var previous := -INF

		for index in range(run.x, run.x + run.y):
			var rock := layout.blocks[index]
			var at := Vector2(rock.x, rock.y)

			if at.dot(across) + rock.z > fore_line - reef_rock or at.dot(across) < previous:
				placed = false

			previous = at.dot(across)
			reef_end = maxf(reef_end, at.dot(across) + rock.z)

		var first := layout.blocks[run.x]
		sides.append((Vector2(first.x, first.y) - middle).dot(chain_axis))

	_check(
		placed and sides.size() == 2 and sides[0] * sides[1] < 0.0,
		"they run from the sea wall toward the fore reef, one on each side of the atoll",
		"%.0f and %.0f either side of the atoll, reaching %.0f from the sea wall"
			% [sides[0], sides[1], reef_end - sea_wall]
	)

	_the_spits_round_the_end_a_lane_not_a_w(leader_mass, world, bounds, layout, rules, fore, across, chain_axis, middle, sea_wall, won, wanted)


## Round the end: a lane, not a wall.
func _the_spits_round_the_end_a_lane_not_a_w(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, fore: Array[Dictionary], across: Vector2, chain_axis: Vector2, middle: Vector2, sea_wall: float, won: float, wanted: PackedFloat32Array) -> void:
	var to_reef := INF
	var to_atoll := INF
	var clear_of_leg := INF
	var west: Vector2 = Vector2(fore[0]["mouth"]) - across * 900.0
	var leg := layout.route_across(west, won)
	var atoll := layout.rings[0]

	for spit in range(layout.spits.size()):
		var run := layout.spits[spit]

		for index in range(run.x, run.x + run.y):
			var rock := layout.blocks[index]
			var at := Vector2(rock.x, rock.y)

			for other in range(layout.chains[0].x, layout.chains[0].x + layout.chains[0].y):
				var o := layout.blocks[other]
				to_reef = minf(to_reef, at.distance_to(Vector2(o.x, o.y)) - rock.z - o.z)

			for other in range(atoll.x, atoll.x + atoll.y):
				var o := layout.blocks[other]
				to_atoll = minf(to_atoll, at.distance_to(Vector2(o.x, o.y)) - rock.z - o.z)

			if leg.size() > 0:
				clear_of_leg = minf(
					clear_of_leg,
					at.distance_to(Geometry2D.get_closest_point_to_segment(at, west, leg[0]))
						- rock.z - won
				)

	_check(
		to_reef > won * 2.0 and to_atoll > won * 2.0,
		"the water round a spit's end, and between it and the atoll, is wider than a leader",
		"%.0f to the fore reef, %.0f to the atoll, a leader %.0f across"
			% [to_reef, to_atoll, won * 2.0]
	)
	_check(
		leg.size() > 0 and clear_of_leg > 24.0,
		"and neither spit stands on the line a leader walks from the tight end to the open end",
		"%.0f clear of a leader on that leg" % clear_of_leg
	)
	_check(
		absf(layout.narrowest_gate(bounds) - float(fore[0]["width"])) < 1.0,
		"nothing on the map is tighter than the fore reef's tight channel",
		"narrowest %.0f, the tight channel %.0f"
			% [layout.narrowest_gate(bounds), float(fore[0]["width"])]
	)

	# [b]It encloses nothing[/b], so there is no refuge here a hunter has to be refused
	# the way the harbours are: the biggest floor a lurker can move about in is all of the
	# floor it can stand on, and so is a monster's 16 under the rock gap's limit.
	var lurker := HungryHunters.largest_radius()
	var region := layout.main_region(bounds, lurker)
	var under := wanted[1] * 0.5 - 16.0
	var sweep := layout.reach(
		bounds, across * (sea_wall + won + 30.0) + chain_axis * middle.dot(chain_axis), under
	)
	_check(
		region["reached"] == region["free"] and sweep["reached"] == sweep["free"],
		"they enclose nothing: a lurker's floor and a monster's 16 under the rock gap are each one region",
		"lurker (radius %.0f) %d of %d; radius %.0f reaches %d of %d"
			% [lurker, region["reached"], region["free"], under, sweep["reached"], sweep["free"]]
	)

	_the_spits_two_routes_across_one_spit(leader_mass, world, bounds, layout, rules, across, chain_axis, middle, won, wanted)


## Two routes across one spit.
func _the_spits_two_routes_across_one_spit(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, across: Vector2, chain_axis: Vector2, middle: Vector2, won: float, wanted: PackedFloat32Array) -> void:
	var run0 := layout.spits[0]
	var near := layout.blocks[run0.x]
	var far := layout.blocks[run0.x + 1]
	var gap_mouth := (Vector2(near.x, near.y) + Vector2(far.x, far.y)) * 0.5
	var outward := chain_axis if (gap_mouth - middle).dot(chain_axis) > 0.0 else -chain_axis
	var bay := gap_mouth + outward * 550.0
	var sheltered := gap_mouth - outward * 550.0
	var spit_end := layout.blocks[run0.x + run0.y - 1]
	var end_face := Vector2(spit_end.x, spit_end.y).dot(across) + spit_end.z

	var leader_route := layout.route_to(bounds, bay, sheltered, won + 24.0)
	var leader_length := _route_length(bay, leader_route)
	var furthest := -INF

	for point in leader_route:
		furthest = maxf(furthest, point.dot(across))

	_check(
		leader_route.size() >= 2 and leader_length > bay.distance_to(sheltered) * 1.5
			and furthest > end_face + won,
		"a leader has a way from the sea in front of the tight end to the atoll's water, and it is round the spit's reef end",
		"%d waypoints, %.0f long against %.0f straight, out to %.0f past the end"
			% [leader_route.size(), leader_length, bay.distance_to(sheltered), furthest - end_face]
	)

	_the_spits_driven_a_middling_monster_th(leader_mass, world, bounds, layout, rules, across, won, wanted, near, far, gap_mouth, outward, bay, sheltered, end_face)


## Driven: a middling monster through, a leader round.
func _the_spits_driven_a_middling_monster_th(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, rules: Dot2DMassRules, across: Vector2, won: float, wanted: PackedFloat32Array, near: Vector3, far: Vector3, gap_mouth: Vector2, outward: Vector2, bay: Vector2, sheltered: Vector2, end_face: float) -> void:
	world.spawn(1, bay)
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a monster spawns in the sea beyond a spit"):
		_drop(world)
		_done()
		return

	# Fed to a little over the wall gap's limit: it swallows what its new disc covers on
	# the next tick, and has to arrive planned 24 wider than itself and still fit the gap
	# between the rocks. The band it actually arrived in is asserted.
	world.feed_player(1, rules.mass_for(wanted[0] * 0.5 + 20.0) - monster.mass())
	_run_ticks(world, 2)

	var middling := monster.pieces[0].radius()
	var through := layout.route_to(bounds, monster.centre(), sheltered, middling + 24.0, 12.0)
	var through_length := _route_length(monster.centre(), through)
	_check(
		middling > wanted[0] * 0.5 and middling + 24.0 < wanted[1] * 0.5
			and through.size() >= 1 and through_length < monster.centre().distance_to(sheltered) * 1.2,
		"one too wide for the wall gap goes almost straight across, between the rocks",
		"radius %.0f (%.0f mass) between the wall gap's %.0f and the rock gap's %.0f: %.0f long against %.0f straight"
			% [middling, monster.mass(), wanted[0] * 0.5, wanted[1] * 0.5, through_length,
				monster.centre().distance_to(sheltered)]
	)

	var middling_drive := _drive_route(world, monster, through, across, TICK_RATE * 30)
	_check(
		middling_drive["deepest"] > -2.0,
		"driven along it, it never overlaps a rock on any tick",
		"deepest %.1f into a face" % middling_drive["deepest"]
	)
	_check(
		middling_drive["reached"] == through.size()
			and (monster.centre() - gap_mouth).dot(outward) < -far.z,
		"and comes out on the atoll's side of the spit",
		"%d of %d waypoints, %.0f past the spit's line"
			% [middling_drive["reached"], through.size(), -(monster.centre() - gap_mouth).dot(outward)]
	)

	world.spawn(1, bay)
	_run_ticks(world, 2)
	monster = world.monster_for(1)
	world.feed_player(1, leader_mass - monster.mass())
	_run_ticks(world, 2)

	var round_route := layout.route_to(bounds, monster.centre(), sheltered, monster.pieces[0].radius() + 24.0)
	var leader_drive := _drive_route(world, monster, round_route, across, TICK_RATE * 90)
	_check(
		leader_drive["deepest"] > -2.0,
		"a leader driven round it never overlaps a rock on any tick",
		"deepest %.1f into a face" % leader_drive["deepest"]
	)
	_check(
		leader_drive["reached"] == round_route.size() and leader_drive["furthest"] > end_face + won
			and (monster.centre() - gap_mouth).dot(outward) < -far.z,
		"and gets to the atoll's side of the spit only by the lane past its reef end",
		"%d of %d waypoints, out to %.0f past the end"
			% [leader_drive["reached"], round_route.size(), leader_drive["furthest"] - end_face]
	)

	_the_spits_part6(world, rules, across, wanted, near, far, gap_mouth, outward, middling_drive, leader_drive)


func _the_spits_part6(world: HungryWorld, rules: Dot2DMassRules, across: Vector2, wanted: PackedFloat32Array, near: Vector3, far: Vector3, gap_mouth: Vector2, outward: Vector2, middling_drive: Dictionary, leader_drive: Dictionary) -> void:
	# [b]Both drives at full pace[/b] (`[bot-drive-1]`): covering the route, at the ground
	# speed the game gives a monster that size. A drive that crawled would pass every check
	# above given a long enough budget.
	_check(
		middling_drive["covered"] > middling_drive["length"] * 0.9
			and leader_drive["covered"] > leader_drive["length"] * 0.9
			and middling_drive["pace"] > 0.95 and leader_drive["pace"] > 0.95,
		"and both covered their routes at their ground speed",
		"through %.0f of %.0f at %.2f of ground speed; round %.0f of %.0f at %.2f"
			% [middling_drive["covered"], middling_drive["length"], middling_drive["pace"],
				leader_drive["covered"], leader_drive["length"], leader_drive["pace"]]
	)

	# Straight at a gap, at the size each is for

	var wall_mouth := Vector2(near.x, near.y) - across * (near.z + wanted[0] * 0.5)
	var from_bay := wall_mouth + outward * 500.0
	var to_shelter := wall_mouth - outward * 1000.0
	var small_got := _straight_run(world, 1, from_bay, to_shelter, 0.0)
	var line := gap_mouth.dot(-outward)
	_check(
		small_got > line + near.z,
		"a starting monster driven straight at the wall gap comes through it",
		"reached %.0f, the spit's line is %.0f" % [small_got, line]
	)

	var between := rules.mass_for((wanted[0] * 0.5 + wanted[1] * 0.5) * 0.5)
	var middling_got := _straight_run(world, 1, from_bay, to_shelter, between)
	_check(
		middling_got < line - near.z,
		"one of %.0f mass on the same line is held at the wall gap" % between,
		"reached %.0f, the spit's line is %.0f" % [middling_got, line]
	)

	var fed := rules.mass_for(wanted[1] * 0.5) * 1.6
	var big_got := _straight_run(
		world, 1, gap_mouth + outward * 600.0, gap_mouth - outward * 1000.0, fed
	)
	_check(
		big_got < line - far.z,
		"and one of %.0f mass driven straight at the gap between the rocks is held at it" % fed,
		"reached %.0f, the spit's line is %.0f" % [big_got, line]
	)

	_drop(world)
	_done()
