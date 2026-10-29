extends "headless_round_levels_corridor.gd"

## The level-by-level sections of the headless round suite (2 of 7).


## The reef: a barrier whose channels widen along it, driven through at two sizes.
##
## The interesting property is which channels a monster fits, a list rather than a number (see [method HungryLayout.channel_widths]). It is driven at both ends of the size range, because radius arithmetic passes over a chain built in the wrong order.
func _test_the_reef() -> void:
	_section("the reef")

	var preset := HungryPreset.reef()

	if not _check(preset.validate().ok, "the reef preset is usable"):
		_done()
		return

	_check(
		preset.layout == HungryLayout.REEF,
		"and it is the third mode with geometry in it",
		"layout %s" % String(preset.layout)
	)

	var world := _make_world(preset, SEED + 131)
	world.add_player(1, "Ada")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout

	if not _check(
		layout != null
			and layout.count() == HungryLayout.REEF_COUNT * 2 + HungryLayout.ATOLL_COUNT
				+ HungryLayout.SPIT_COUNT * 2 + 2
			and layout.chains.size() == 2,
		"ten rocks stand across it, in two barriers, four in the atoll, two in each spit and two in the cove (%d)"
			% (layout.count() if layout != null else -1)
	):
		_drop(world)
		_done()
		return

	var again := HungryLayout.for_id(HungryLayout.REEF, bounds)
	var identical := again.count() == layout.count()

	for index in range(mini(again.count(), layout.count())):
		if not again.blocks[index].is_equal_approx(layout.blocks[index]):
			identical = false

	_check(identical, "and a second build of the same layout is the same rocks")

	var inside := true

	for block in layout.blocks:
		if not bounds.grow(-block.z).has_point(Vector2(block.x, block.y)):
			inside = false

	_check(inside, "and every one of them is wholly inside the world")

	_the_reef_the_channels_which_are_the_l(preset, world, bounds, layout)


## The channels, which are the level.
func _the_reef_the_channels_which_are_the_l(preset: HungryPreset, world: HungryWorld, bounds: Rect2, layout: HungryLayout) -> void:
	# The rocks are walked, not the constants re-read, so a flipped sign shows here.
	# Per barrier, not pairwise: the fore reef's last rock and the back's first are
	# neighbours in `blocks` and 1,500 units apart.
	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var wanted := HungryLayout.channel_widths(short_half)
	var measured := PackedFloat32Array()

	for channel in layout.channels(0):
		measured.append(float(channel["width"]))

	var agree := wanted.size() == measured.size()

	for index in range(mini(wanted.size(), measured.size())):
		if absf(wanted[index] - measured[index]) > 1.0:
			agree = false

	_check(
		agree,
		"the four channels it builds are the four channels it describes",
		"built %s, described %s" % [_widths(measured), _widths(wanted)]
	)

	var widens := measured.size() >= 2

	for index in range(measured.size() - 1):
		if measured[index + 1] <= measured[index] + 1.0:
			widens = false

	_check(
		widens,
		"and every one of them is wider than the one before it",
		"%s" % _widths(measured)
	)

	# The end run-round must sit between the tight channel and the two open ones: wider and
	# the tight channel is decoration, narrower and it is a wall with four holes. Asked of
	# the fore reef's own rocks, since the spits' first rocks would be read as the run-round.
	var gate := layout.narrowest_gate(bounds)
	var run_round := INF

	for index in range(layout.chains[0].x, layout.chains[0].x + layout.chains[0].y):
		var block := layout.blocks[index]
		run_round = minf(run_round, minf(
			minf(block.x - bounds.position.x, bounds.end.x - block.x),
			minf(block.y - bounds.position.y, bounds.end.y - block.y)
		) - block.z)

	_the_reef_part3(preset, world, bounds, layout, short_half, measured, gate, run_round)


func _the_reef_part3(preset: HungryPreset, world: HungryWorld, bounds: Rect2, layout: HungryLayout, short_half: float, measured: PackedFloat32Array, gate: float, run_round: float) -> void:
	_check(
		absf(gate - measured[0]) <= 1.0,
		"the tightest thing on the map is the tight channel, walls included",
		"%.0f, against %.0f round the end" % [gate, run_round]
	)
	_check(
		run_round > measured[0] and run_round < measured[2],
		"and the way round the end is better than the tight channel and worse than the third",
		"%.0f, between %.0f and %.0f" % [run_round, measured[0], measured[2]]
	)
	# The layout's own arithmetic for the same distance, which is what the design is
	# argued in. Two ways to the one number: if they ever disagree, the reasoning in
	# `_reef`'s docs is about a map that is not the one being built.
	_check(
		absf(run_round - short_half * HungryLayout.reef_end_fraction()) <= 1.0,
		"and it is the distance the layout says it leaves",
		"%.0f measured, %.0f derived"
			% [run_round, short_half * HungryLayout.reef_end_fraction()]
	)

	# Not a cage

	var rules := world.tunables.mass_rules
	var won := rules.radius_for(preset.win_mass)

	_check(
		measured[measured.size() - 1] * 0.5 > won,
		"a monster at the winning mass still fits the open end",
		"a radius of %.0f through a %.0f channel" % [won, measured[measured.size() - 1]]
	)
	_check(
		measured[0] * 0.5 < won and run_round * 0.5 < won,
		"and it fits neither the tight channel nor the way round, so it has to travel",
		"%.0f against a %.0f channel and a %.0f run-round"
			% [won, measured[0], run_round]
	)

	_the_reef_driven_through_small(preset, world, bounds, layout, measured)


## Driven through, small.
func _the_reef_driven_through_small(preset: HungryPreset, world: HungryWorld, bounds: Rect2, layout: HungryLayout, measured: PackedFloat32Array) -> void:
	# The tight channel's middle, and the two points either side of the barrier on its own
	# line. The barrier runs along the shorter axis, so crossing it is a move along the
	# other one.
	var mouth: Vector2 = layout.channels(0)[0]["mouth"]
	var across := Vector2(0.0, 1.0) if bounds.size.x < bounds.size.y \
		else Vector2(1.0, 0.0)
	var start := mouth - across * 600.0
	var target := mouth + across * 900.0

	world.spawn(1, start)
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a monster spawns short of the reef"):
		_drop(world)
		_done()
		return

	# [b]Sampled every tick.[/b] A push-out that fails for one frame and recovers is
	# invisible to a reading taken at the end, and one frame inside a rock is one frame of
	# eating through a wall.
	var deepest := INF
	var small_progress := 0.0

	for _i in range(TICK_RATE * 12):
		world.tick({1: _aim_at(monster.centre(), target)})

		for block in layout.blocks:
			deepest = minf(
				deepest,
				monster.centre().distance_to(Vector2(block.x, block.y)) - block.z
			)

		small_progress = maxf(small_progress, (monster.centre() - mouth).dot(across))

	_check(
		deepest > -2.0,
		"driving a monster through the tight channel never puts it inside a rock",
		"closest approach to a face %.0f" % deepest
	)
	_check(
		small_progress > 400.0,
		"and a starting monster comes out the far side of it",
		"%.0f past the mouth of a %.0f channel" % [small_progress, measured[0]]
	)

	_the_reef_driven_at_the_same_channel_g(preset, world, bounds, layout, measured, mouth, across, start, target, monster, small_progress)


## Driven at the same channel, grown.
func _the_reef_driven_at_the_same_channel_g(preset: HungryPreset, world: HungryWorld, bounds: Rect2, layout: HungryLayout, measured: PackedFloat32Array, mouth: Vector2, across: Vector2, start: Vector2, target: Vector2, monster: HungryMonster, small_progress: float) -> void:
	# [b]Nothing changes but the radius.[/b] Same seed, same world, same channel, same
	# commands, twice the ticks — so the only thing that can make the second run end on
	# the near side is the size of the thing running it.
	world.spawn(1, start)
	_run_ticks(world, 2)
	# Just short of the winning mass: reaching it ends the round and the next respawns every
	# player as a starter, which this check would read as the grown monster getting through.
	world.feed_player(1, preset.win_mass * 0.97 - monster.mass())
	_run_ticks(world, 2)

	var grown := monster.pieces[0].radius()
	var big_progress := -INF

	for _i in range(TICK_RATE * 24):
		world.tick({1: _aim_at(monster.centre(), target)})
		big_progress = maxf(big_progress, (monster.centre() - mouth).dot(across))

	_check(
		grown * 2.0 > measured[0],
		"a monster at the winning mass is wider than the tight channel",
		"%.0f across, against a %.0f channel" % [grown * 2.0, measured[0]]
	)
	_check(
		big_progress < small_progress - 200.0,
		"and the same run leaves it on the near side of the reef",
		"%.0f past the mouth, where the small one reached %.0f"
			% [big_progress, small_progress]
	)

	_the_reef_nothing_edible_is_buried_and(preset, world, bounds, layout)


## Nothing edible is buried, and nobody spawns in a rock.
func _the_reef_nothing_edible_is_buried_and(preset: HungryPreset, world: HungryWorld, bounds: Rect2, layout: HungryLayout) -> void:
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

	# A client is TOLD which layout, and builds it. Nothing about the rocks travels.
	var predicted := _make_world(preset, SEED + 131)
	predicted.is_authority = false
	predicted.add_player(2, "Bo")
	_settle(predicted)
	predicted.adopt_layout(HungryLayout.REEF)
	_check(
		predicted.layout.count() == layout.count()
			and predicted.layout.narrowest_gate(bounds) == layout.narrowest_gate(bounds),
		"and a client builds the same fourteen from one name in the hello"
	)
	_drop(predicted)

	_drop(world)
	_done()


## The reef's second half: a lagoon, and a back reef with one door in it.
##
## It is about a distance a grown monster is made to travel, so it drives one along [method HungryLayout.route_across]; arithmetic would pass over a back reef on the wrong side, and the drive would not.
func _test_the_lagoon() -> void:
	_section("the lagoon")

	var preset := HungryPreset.reef()
	# The leader's size is read before the round is told it cannot end: a leader eating
	# along this route would reach the winning mass, reset the world and leave a fresh spawn.
	var leader_mass := preset.win_mass
	preset.win_mass = 1000000.0
	var world := _make_world(preset, SEED + 173)
	world.add_player(1, "Lea")
	_settle(world)

	var bounds := world.arena.bounds
	var layout := world.layout

	if not _check(
		layout != null and layout.chains.size() == 2,
		"the reef has a second barrier behind the first (%d)"
			% (layout.chains.size() if layout != null else -1)
	):
		_drop(world)
		_done()
		return

	var short_half := minf(bounds.size.x, bounds.size.y) * 0.5
	var fore := layout.channels(0)
	var back := layout.channels(1)
	var wanted := HungryLayout.back_reef_widths(short_half)
	var measured := PackedFloat32Array()

	for channel in back:
		measured.append(float(channel["width"]))

	var agree := wanted.size() == measured.size()

	for index in range(mini(wanted.size(), measured.size())):
		if absf(wanted[index] - measured[index]) > 1.0:
			agree = false

	_check(
		agree,
		"the back reef builds the door and three gates it describes",
		"built %s, described %s" % [_widths(measured), _widths(wanted)]
	)

	# [b]The door is behind the fore reef's TIGHT end.[/b] That one relation is the whole
	# level: the other way round, a grown monster comes through the fore reef's open end
	# and finds the door straight ahead of it, and the lagoon is a corridor nobody walks.
	var chain_axis: Vector2 = (
		Vector2(fore[fore.size() - 1]["mouth"]) - Vector2(fore[0]["mouth"])
	).normalized()
	var centre := bounds.get_center()
	var door_at := (Vector2(back[0]["mouth"]) - centre).dot(chain_axis)
	var tight_at := (Vector2(fore[0]["mouth"]) - centre).dot(chain_axis)
	var third_at := (Vector2(fore[2]["mouth"]) - centre).dot(chain_axis)
	var wide_at := (Vector2(fore[3]["mouth"]) - centre).dot(chain_axis)

	_the_lagoon_part2(leader_mass, world, bounds, layout, fore, back, wanted, chain_axis, centre, door_at, tight_at, third_at, wide_at)


func _the_lagoon_part2(leader_mass: float, world: HungryWorld, bounds: Rect2, layout: HungryLayout, fore: Array[Dictionary], back: Array[Dictionary], wanted: PackedFloat32Array, chain_axis: Vector2, centre: Vector2, door_at: float, tight_at: float, third_at: float, wide_at: float) -> void:
	_check(
		door_at * tight_at > 0.0 and door_at * wide_at < 0.0 and door_at * third_at < 0.0,
		"and the door is behind the fore reef's tight end, away from both its open channels",
		"door at %.0f, tight %.0f, third %.0f, widest %.0f along the reef"
			% [door_at, tight_at, third_at, wide_at]
	)

	# The lagoon, sized by the monster that has to walk it

	var rules := world.tunables.mass_rules
	var won := rules.radius_for(leader_mass)
	var small := rules.radius_for(HungryContent.START_MASS)
	var rock := layout.blocks[0].z
	var across: Vector2 = fore[0]["normal"]

	if (Vector2(back[0]["mouth"]) - Vector2(fore[0]["mouth"])).dot(across) < 0.0:
		across = -across

	var fore_line := Vector2(fore[0]["mouth"]).dot(across)
	var back_line := Vector2(back[0]["mouth"]).dot(across)
	var far_wall := maxf(bounds.position.dot(across), bounds.end.dot(across))
	var lagoon := back_line - fore_line - rock * 2.0
	var strip := far_wall - back_line - rock

	_check(
		lagoon > won * 2.0 * 1.3 and strip > won * 2.0 * 1.3,
		"a monster at the winning mass has room to travel the lagoon and the strip behind it",
		"lagoon %.0f, strip %.0f, against a leader %.0f across" % [lagoon, strip, won * 2.0]
	)
	_check(
		lagoon < won * 4.0,
		"and not room to be passed in it: two leaders cannot stand abreast",
		"lagoon %.0f against two leaders %.0f" % [lagoon, won * 4.0]
	)

	_the_lagoon_who_walks_it_from_the_routes(leader_mass, world, layout, fore, wanted, chain_axis, centre, rules, won, small, rock, across, fore_line, back_line)


## Who walks it, from the routes the layout gives.
func _the_lagoon_who_walks_it_from_the_routes(leader_mass: float, world: HungryWorld, layout: HungryLayout, fore: Array[Dictionary], wanted: PackedFloat32Array, chain_axis: Vector2, centre: Vector2, rules: Dot2DMassRules, won: float, small: float, rock: float, across: Vector2, fore_line: float, back_line: float) -> void:
	# From in front of the fore reef's tight channel, which is the end the door is behind:
	# the cheapest place to start for everybody, so the walk measured is the tax and not
	# the approach.
	var west: Vector2 = Vector2(fore[0]["mouth"]) - across * 900.0
	var middling := rules.radius_for(1000.0)

	_check(
		_lagoon_walk(layout.route_across(west, small), chain_axis) < 400.0,
		"a starting monster crosses both barriers almost on one line",
		"walks %.0f along the lagoon" % _lagoon_walk(layout.route_across(west, small), chain_axis)
	)
	_check(
		_lagoon_walk(layout.route_across(west, middling), chain_axis) > 1000.0,
		"one of 1000 mass has to walk the lagoon from the third channel to the door",
		"walks %.0f along the lagoon"
			% _lagoon_walk(layout.route_across(west, middling), chain_axis)
	)
	_check(
		_lagoon_walk(layout.route_across(west, won), chain_axis) > 2000.0,
		"and one at the winning mass walks nearly all of it",
		"walks %.0f along the lagoon" % _lagoon_walk(layout.route_across(west, won), chain_axis)
	)

	# [b]Not a cage, from either side.[/b] A leader in the strip behind the back reef has to
	# have a way home, or the far side is a place the round ends with somebody parked in.
	var behind := centre + across * (back_line - centre.dot(across) + rock + won + 100.0)
	_check(
		layout.route_across(behind, won).size() == 6,
		"a leader behind the back reef has a way back across both",
		"%d waypoints" % layout.route_across(behind, won).size()
	)
	_check(
		layout.route_across(west, float(wanted[0]) * 0.5 + 1.0).is_empty(),
		"and something too wide for the door has no route at all, rather than a wrong one"
	)

	_the_lagoon_driven_a_leader_walks_the_la(leader_mass, world, layout, fore, chain_axis, rock, across, fore_line, back_line, west)


## Driven: a leader walks the lagoon to the door.
func _the_lagoon_driven_a_leader_walks_the_la(leader_mass: float, world: HungryWorld, layout: HungryLayout, fore: Array[Dictionary], chain_axis: Vector2, rock: float, across: Vector2, fore_line: float, back_line: float, west: Vector2) -> void:
	world.spawn(1, west)
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a monster spawns short of the reef"):
		_drop(world)
		_done()
		return

	world.feed_player(1, leader_mass - monster.mass())
	_run_ticks(world, 2)

	var route := layout.route_across(monster.centre(), monster.pieces[0].radius())
	var reached := 0
	var deepest := INF
	var lagoon_low := INF
	var lagoon_high := -INF
	var ticks := 0

	# Full reach toward the next waypoint and on to the one after it at 60 units: near is
	# slow in this game, and a monster steered with the reach it would get from the
	# distance to a point crawls the last hundred units of every leg.
	var drive_from := monster.centre()
	var drive_covered := 0.0
	var drive_ground := 0.0
	var drive_ticks := 0

	for _i in range(TICK_RATE * 120):
		if reached >= route.size():
			break

		if monster.centre().distance_to(route[reached]) < 60.0:
			reached += 1
			continue

		var was := monster.centre()
		drive_ground += _ground_step(world, monster)
		world.tick({1: _full_reach(monster.centre(), route[reached])})
		drive_covered += monster.centre().distance_to(was)
		drive_ticks += 1
		ticks += 1

		var piece := monster.pieces[0]

		for block in layout.blocks:
			deepest = minf(
				deepest,
				piece.position().distance_to(Vector2(block.x, block.y)) - block.z
					- piece.radius()
			)

		var here := monster.centre()

		if here.dot(across) > fore_line + rock and here.dot(across) < back_line - rock:
			lagoon_low = minf(lagoon_low, here.dot(chain_axis))
			lagoon_high = maxf(lagoon_high, here.dot(chain_axis))

	_the_lagoon_part5(leader_mass, world, fore, rock, across, fore_line, back_line, monster, route, reached, deepest, lagoon_low, lagoon_high, ticks, drive_from, drive_covered, drive_ground, drive_ticks)


func _the_lagoon_part5(leader_mass: float, world: HungryWorld, fore: Array[Dictionary], rock: float, across: Vector2, fore_line: float, back_line: float, monster: HungryMonster, route: PackedVector2Array, reached: int, deepest: float, lagoon_low: float, lagoon_high: float, ticks: int, drive_from: Vector2, drive_covered: float, drive_ground: float, drive_ticks: int) -> void:
	_drive_report(drive_from, route, drive_covered, drive_ticks, drive_ground)
	_check(
		deepest > -2.0,
		"a leader driven along its route never overlaps a rock, on any tick",
		"deepest %.0f into a face" % deepest
	)
	_check(
		reached == route.size() and monster.centre().dot(across) > back_line + rock,
		"and comes out behind the back reef",
		"%d of %d waypoints in %.1f s" % [reached, route.size(), float(ticks) / TICK_RATE]
	)
	_check(
		lagoon_high - lagoon_low > 2000.0,
		"having walked the lagoon from one end to the other to get there",
		"%.0f along the lagoon" % (lagoon_high - lagoon_low)
	)

	# The straight line: the same start, the same commands, two sizes

	# From in front of the fore reef's widest channel, straight across; only the radius
	# differs between the two runs.
	var straight_from: Vector2 = Vector2(fore[3]["mouth"]) - across * 700.0
	var straight_to := straight_from + across * 4000.0
	var small_far := _straight_run(world, 1, straight_from, straight_to, 0.0)
	var big_far := _straight_run(world, 1, straight_from, straight_to, leader_mass)

	_check(
		small_far > back_line + rock,
		"a starting monster driven straight across goes through both barriers",
		"reached %.0f, the back reef is at %.0f" % [small_far, back_line]
	)
	_check(
		big_far > fore_line + rock and big_far < back_line - rock,
		"and a leader on the same line is held in the lagoon",
		"reached %.0f, between %.0f and %.0f" % [big_far, fore_line, back_line]
	)

	_drop(world)
	_done()
