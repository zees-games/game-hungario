extends "headless_round_base.gd"

## The level-by-level sections of the headless round suite.


## The Gauntlet: a five-to-one corridor, and the first non-square world this game runs.
##
## [b]The mode is the point and the shape is the reason it is worth a section.[/b] Classic
## and Frenzy are the same square at two sizes, so every place that reads `world_size.x`
## where it meant `.y` — or derives one bound from one component — gives the right answer
## and is invisible. A corridor is where the two components disagree, so it is the only
## arrangement in which those are findable at all.
##
## Every check below would pass on a square world whether or not the code were right.
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
	# [b]The same food per unit of WALKABLE floor, which stopped being the same number
	# as the target the day this mode got a level.[/b] Five slalom rocks stand on about
	# an eighth of the corridor. Whatever the scatter puts inside one is culled and the
	# field then REFILLS to its target on open floor, so the target is the food standing
	# on the floor and the density is the target over the floor that is left.
	#
	# [b]This line used to multiply by the floor instead of dividing by it[/b] — the
	# arithmetic of a cull that is a permanent loss, which it is not — and the preset
	# had been tuned to the same backwards arithmetic, so the two agreed about a corridor
	# 27% richer than the square. "food on the floor that is left" measures the living
	# field now, which is the check that caught it; this one is the arithmetic, kept
	# because a preset argued in a comment should be checked in the same terms.
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

	# It reached the far end. A corridor whose length nothing can cross is a corridor
	# nobody meets anybody in, and the run above is the only thing that would say so.
	#
	# [b]Sixty seconds, not twenty, and twenty only ever passed by accident.[/b] A starting
	# monster moves about 130 units a second and this one starts at the west wall with
	# five rocks to slide round. The old budget passed because the section settled before
	# anybody had joined, the round went live on the first tick after, and the reset put
	# the monster wherever the safe spawn liked — usually most of the way there already.
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
## [b]A gate is a gap between two things, and until now both of them were rocks.[/b] The
## warrens is a ring, so every gate in it is rock-to-rock and `narrowest_gap` is the whole
## answer. A slalom rock stands off one wall of a corridor: its narrow lane is against
## that wall and its wide one against the other, and neither is a gap between two rocks at
## all. Asked the old question the slalom answers 646 units — two rocks a thousand apart —
## which is not a gate, is not the level, and would have passed every threshold a reviewer
## would think to write.
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

	# Five rocks and, since 2026-09-25, a harbour fence across each end; the fences are
	# the harbours section's, and everything below about lanes asks the five rocks alone.
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

	_check(
		alternates,
		"and they alternate sides, so the inside line changes wall at every rock"
	)

	# --- The two lanes, which are the level ---------------------------------

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

	# [b]And the long way round is open to it, which the ring did not have to prove.[/b]
	# A ring is escapable by construction — the middle is the part you are shut out of. A
	# corridor is not: a rock whose wide lane is also too narrow is a cork, and the mode
	# ends with the leader parked against it. This is the check that says the slalom is a
	# level rather than a cage.
	var widest := world.layout.widest_way_past(bounds)
	_check(
		widest * 0.5 > rules.radius_for(preset.win_mass),
		"and the way round is open even to one that has already won",
		"%.0f unit lane against a radius of %.0f"
			% [widest, rules.radius_for(preset.win_mass)]
	)

	# --- A rock stops somebody ----------------------------------------------

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

	# [b]Aimed, not moved.[/b] This drive used to set `command.move` and nothing else, and
	# this game steers by `aim` and `reach` — `move` is carried through to the motor and
	# ignored by it. The monster never moved; the section settled before the player
	# joined, the first tick after reset the round and respawned it, and "it gets past
	# the rock" was measuring where the respawn had put it.
	#
	# Two legs, because driven for real a pointer held on a line through a disc's centre
	# holds the monster against that disc's face for ever — the push-out takes the normal
	# component and there is no tangent left to slide on. So: four seconds straight at
	# the rock, which is the push-out's test, and then the pointer moves to the middle of
	# the far lane beyond it, which is what a player going past does.
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

	# Eight ring, four corner and four den rocks. The den was added 2026-09-24 and appended
	# last, so blocks 0 and 1 below are still the ring's.
	if not _check(
		layout != null and layout.count() == HungryLayout.RING_COUNT + 4 + HungryLayout.DEN_COUNT,
		"sixteen rocks stand in it: the ring, the corners and the den",
		"%d" % (layout.count() if layout != null else -1)
	):
		_drop(world)
		_done()
		return

	# [b]Derived and not stored, which is what makes it free on the wire.[/b] The same id
	# and the same rectangle have to produce the same discs every time, because that is the
	# only reason a client can be told a name instead of a hundred and forty-four bytes of
	# circles.
	var again := HungryLayout.for_id(HungryLayout.WARRENS, bounds)
	var identical := again.count() == layout.count()

	for index in range(mini(again.count(), layout.count())):
		if not again.blocks[index].is_equal_approx(layout.blocks[index]):
			identical = false

	_check(identical, "and a second build of the same layout is the same rocks")

	# Everything is inside the arena. A rock half outside the wall is a rock a player is
	# pushed through the boundary by. A rock TOUCHING a wall is not crossing it — the open
	# corners stand a hundredth of a unit into theirs so the gap is shut rather than a
	# gate a hair wide — hence the twentieth of a unit allowed.
	var inside := true

	for block in layout.blocks:
		var at := Vector2(block.x, block.y)

		if not bounds.grow(-block.z + 0.05).has_point(at):
			inside = false

	_check(inside, "and every one of them is wholly inside the arena")

	# --- The gate, which is the level ---------------------------------------

	# [b]The one number the design rests on.[/b] Mass IS radius here, so a gap is a mass
	# limit: `radius_for` inverted says who fits. The gates are meant to be open to a
	# player who is behind and shut to the player who is ahead, and a constant changed
	# without meaning to would quietly make the middle open to everybody or to nobody.
	var rules := world.tunables.mass_rules
	# [method HungryLayout.narrowest_gate] rather than `fits_through`, which measures rock
	# against rock alone. It is the same answer here — the corner rocks stand further off
	# the wall than the ring rocks stand from each other — and it is deliberately the same
	# call the slalom section makes, because a level whose gates are against a wall gets a
	# meaningless number out of the other one and nothing says so.
	#
	# [b]The RING's gate, since the den (2026-09-24).[/b] The narrowest gate on the map is
	# the den's now, a third of this one's mass limit; asked of the whole layout this check
	# would have been asserting the den was the warrens' ring. `ring_gates(0)` asks the
	# ring; the den has its own section.
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

	# --- A rock stops somebody ----------------------------------------------


	var ring: Vector3 = layout.blocks[0]
	var ring_at := Vector2(ring.x, ring.y)
	# Outside the ring, driving inward AT the rock — four degrees off its centre line,
	# which at this range is 80 units: well inside the rock's face, so the drive still
	# meets it, and not exactly on its centre, which no pointer ever is. Dead centre on a
	# disc is the one approach with no side to slide off to, and a monster held there
	# stops against the face for good; see the note on the slide below.
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

	# [b]Sampled every tick, not read at the end.[/b] A push-out that let somebody through
	# for one frame and recovered is indistinguishable from one that never failed if the
	# only reading is the last one — and one frame inside a rock is one frame of eating
	# through a wall, which is the whole reason [HungryHazards] resolves before eating too.
	var deepest := INF

	for _i in range(TICK_RATE * 20):
		world.tick({1: _aim_at(monster.centre(), bounds.get_center())})
		deepest = minf(deepest, monster.centre().distance_to(ring_at))

	_check(
		deepest > ring.z - 2.0,
		"and driving straight at a rock never puts it inside one, on any tick",
		"closest approach %.0f to the middle of a %.0f rock" % [deepest, ring.z]
	)

	# [b]And it gets past anyway, which is the level working rather than failing.[/b] A
	# starting monster driven at a rock slides along its face, arrives at a gate and goes
	# through. That is what a ring with gates in it is FOR.
	#
	# [b]This check was rewritten once to match a monster that had been teleported.[/b]
	# The first version asserted the monster stayed outside the ring, failed, and was
	# turned round on the reading that the monster had slid in through a gate. It had not:
	# the section settled before the player joined, the round went live on the first tick
	# after, and the reset respawned the monster wherever the safe spawn liked. Driven for
	# real and dead on the rock's centre it stays against the face for ever — the first
	# version was right about that approach. Four degrees off, it slides in.
	_check(
		monster.centre().distance_to(bounds.get_center()) < ring_at.length() * 0.5,
		"but slides round the face of it and in through a gate",
		"%.0f from the centre, the ring is at %.0f"
			% [monster.centre().distance_to(bounds.get_center()), ring_at.length()]
	)

	# --- The same push on the prediction path -------------------------------

	# [b]The one thing a client does for itself.[/b] A client predicts by calling
	# `simulate_piece` and a reconciliation replays it, so a push-out that only the
	# authority's loop applied would make every tick spent against a rock a misprediction —
	# and the correction would ease the player back into the rock they are standing
	# against. It reads as packet loss, which sends the next person to the netcode.
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

	# --- A small monster gets through, a big one does not -------------------

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
	# [b]Just short of the winning mass, not at it.[/b] Reaching it wins the round, the round
	# ends, and the next one respawns every player as a starter at its spawn: the grown
	# monster is then a small one that walks through the channel, and this check read that
	# as the reef letting a grown monster through. The width is the same to within a
	# percent, which is all the next check asks of it.
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

	# --- Nothing edible is buried -------------------------------------------

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

	# --- And nobody spawns inside one ---------------------------------------

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


## The reef: a barrier whose channels widen along it, driven through at two sizes.
##
## [b]The question this section asks that the other two levels cannot.[/b] Warrens and
## Slalom both have one gate width, so "can this monster get through" is a single number
## and every check over them is a comparison against it. The reef's channels are 248, 442,
## 635 and 828 units, so the interesting property is not whether a monster fits — it is
## *which* channels it fits, and therefore how far along the barrier it has to travel
## before it can cross. That is a list rather than a number, and it is what
## [method HungryLayout.channel_widths] exists to be asked for.
##
## [b]Driven rather than asserted, at both ends of the size range.[/b] Every level check
## in this file that only compares radii would pass over a barrier that had been built
## with its rocks in the wrong order, or overlapping, or with the whole chain outside the
## world: the arithmetic is the same either way. A small monster is driven at the tight
## channel and has to come out the far side; a monster at the winning mass is driven at
## the same channel and has to still be on the near side when the clock runs out.
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

	# --- The channels, which are the level ----------------------------------

	# [b]The rocks are walked rather than the constants re-read.[/b] This is the same rule
	# the 3D maps in this family follow: one description, more than one representation,
	# and every representation derived from the description rather than restated. The
	# widths below come from `channel_widths`; the gaps come from the discs the world
	# actually built. A chain laid out in the wrong order, or with a sign flipped, agrees
	# with the constants and disagrees here.
	#
	# [b]Per barrier, not pairwise down the array.[/b] This loop walked `blocks` two at a
	# time while there was one chain; with the back reef behind it, the last rock of the
	# fore reef and the first of the back are neighbours in the array and 1,500 units apart
	# on the map, and the pairwise walk reported a fifth "channel" that is not one.
	# `channels(0)` is the fore reef's four; the lagoon section asks for the back's.
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

	# [b]The end run-round is what stops this being the warrens with fewer gates.[/b] It
	# has to sit between the tight channel and the two open ones: wider and the tight
	# channel is decoration because everybody can walk round instead, narrower and it is a
	# slot nothing can use and the barrier is really a wall with four holes.
	# Asked of the fore reef's own rocks: the spits' first rocks stand the tight channel's
	# width off the sea wall, and over every block this read that as the run-round.
	var gate := layout.narrowest_gate(bounds)
	var run_round := INF

	for index in range(layout.chains[0].x, layout.chains[0].x + layout.chains[0].y):
		var block := layout.blocks[index]
		run_round = minf(run_round, minf(
			minf(block.x - bounds.position.x, bounds.end.x - block.x),
			minf(block.y - bounds.position.y, bounds.end.y - block.y)
		) - block.z)

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

	# --- Not a cage ---------------------------------------------------------

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

	# --- Driven through, small ----------------------------------------------

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

	# --- Driven at the same channel, grown ----------------------------------

	# [b]Nothing changes but the radius.[/b] Same seed, same world, same channel, same
	# commands, twice the ticks — so the only thing that can make the second run end on
	# the near side is the size of the thing running it.
	world.spawn(1, start)
	_run_ticks(world, 2)
	# [b]Just short of the winning mass, not at it.[/b] Reaching it wins the round, the round
	# ends, and the next one respawns every player as a starter at its spawn: the grown
	# monster is then a small one that walks through the channel, and this check read that
	# as the reef letting a grown monster through. The width is the same to within a
	# percent, which is all the next check asks of it.
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

	# --- Nothing edible is buried, and nobody spawns in a rock --------------

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
## [b]What this section is about is a DISTANCE a grown monster is made to travel, so it
## drives one along it.[/b] The back reef's door is behind the fore reef's tight end and
## the two fore channels a grown monster fits are both at the other end, so the lagoon
## between them is a walk that only the big pay. Every arithmetic check below would pass
## over a back reef built on the wrong side, the wrong way round, or so close to the fore
## reef that nothing fits between them; the drive would not.
##
## [b]It is driven along [method HungryLayout.route_across][/b], the layout's own answer
## to "where do I steer to get across", rather than along waypoints written here — so the
## route a check follows is derived from the same discs the world pushes a monster out of,
## and a waypoint inside a rock is a failure of the layout rather than of the test.
func _test_the_lagoon() -> void:
	_section("the lagoon")

	var preset := HungryPreset.reef()
	# [b]The leader's size is read BEFORE the round is told it cannot end.[/b] A leader
	# walks this route for over a minute at a fifth of full speed, eating the whole way,
	# and the first version of this section fed it to the winning mass and drove it: it
	# ate its way past the mass that ends the round a little way up the lagoon, the world
	# reset under it, and the "leader" that came out behind the back reef was a freshly
	# spawned monster somewhere else. The check is about the walk, so the round is
	# lifted out of the way and the size stays the one the mode is played at.
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

	_check(
		door_at * tight_at > 0.0 and door_at * wide_at < 0.0 and door_at * third_at < 0.0,
		"and the door is behind the fore reef's tight end, away from both its open channels",
		"door at %.0f, tight %.0f, third %.0f, widest %.0f along the reef"
			% [door_at, tight_at, third_at, wide_at]
	)

	# --- The lagoon, sized by the monster that has to walk it -----------------

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

	# --- Who walks it, from the routes the layout gives ----------------------

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

	# --- Driven: a leader walks the lagoon to the door ------------------------

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

	# --- The straight line: the same start, the same commands, two sizes -----

	# From in front of the fore reef's widest channel, straight across. A starting monster
	# goes through the fore reef and a gate of the back one; a leader goes through the
	# fore reef and meets gates it does not fit, and is still in the lagoon when the clock
	# runs out. Nothing but the radius differs between the two runs.
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


## How far a route runs along the reef between leaving the first barrier and reaching the
## second: the walk the lagoon charges. Waypoints 2 and 3 are the fore exit and the back
## approach — see [method HungryLayout.route_across].
func _lagoon_walk(route: PackedVector2Array, chain_axis: Vector2) -> float:
	if route.size() < 6:
		return INF

	return absf((route[3] - route[2]).dot(chain_axis))


## A command at full reach toward [param to].
## [bot-drive-1]: what a route drive covered, printed beside the checks that ask where it
## got to — how far it went against the route it was given, and how fast against the ground
## speed its mass allowed. A drive that "arrived" by being respawned past the gate, or that
## crawled, reads differently here from one that drove there.
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


## Respawns [param player] at [param from], grows it to [param mass] if that is above
## where it starts, and drives it at [param to] for twenty-four seconds — a starting
## monster covers about 130 units a second, so this is room for about 3000. Returns how far it got
## along the line.
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


## The reef's third part: an atoll in the open sea, whose gates widen from the wall side
## to the reef side.
##
## [b]What this section is about is WHICH SIDE a monster has to come in from, so it
## drives one round to it.[/b] Every arithmetic check about the four gates would pass
## over an atoll built with its wide gate facing the wall, or so close to the reef that a
## leader could not walk past it to the open end; the drive and the leader's leg would not.
## Asked at the sizes each gate is FOR, like the den and the harbours: a starting monster
## through the tight gate, one between the flank and the reef-side limits round to the
## reef side, one between the tight and flank limits held at the tight gate, and one past
## the widest held at it.
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

	# --- The gates, which are the level --------------------------------------

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

	# --- An island, not a plug ------------------------------------------------

	# The water either side, measured off the discs: the ring's rocks to the fore reef's,
	# and the ring's rocks to the wall behind it. Both wider than a leader, so the atoll
	# is walked round from either side and nothing behind it is a pocket for any size up
	# to the one that ends the round.
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

	# --- Reach, at the size each side is for ---------------------------------

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

	# --- Driven: round to the reef side --------------------------------------

	# Between the flank limit and the reef-side one, so the only way in is the gate that
	# faces the reef; started behind the atoll on the wall side, off the axis, so the
	# route has to go round it rather than straight in.
	# Fed to just over the flank limit rather than to the middle of the band: a monster
	# fed in one step swallows whatever its new disc covers on the next tick (97 mass,
	# here), and it has to arrive planned 24 wider than itself and still fit the reef-side
	# gate and the 232 of room inside. The band it actually arrived in is asserted.
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

	# --- Straight at a gate, at three sizes ----------------------------------

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


## The reef's spits: two rocks from the sea wall either side of the atoll, which a
## middling monster goes through and a leader has to go round.
##
## [b]What the spits are about is the DIFFERENCE between two routes across one line[/b],
## so this section drives both: a monster between the wall gap's limit and the rock gap's
## through the gap between the rocks, and a leader from the same start to the same goal
## round the spit's reef end, in the lane along the fore reef. Every arithmetic check
## about two gaps would pass over a spit that reached the reef and made the sea three
## rooms nobody could leave, or one that stood on the leg a leader walks to the open end;
## the leader's drive and the leg would not. Then straight at each gap at the size it is
## FOR, like the atoll: a starting monster through the wall gap, a middling one held at
## it, and one past the rock gap held at that.
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

	# --- The gaps, which are the level ---------------------------------------

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

	# --- Round the end: a lane, not a wall ------------------------------------

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

	# --- Two routes across one spit -------------------------------------------

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

	# --- Driven: a middling monster through, a leader round -------------------

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

	# --- Straight at a gap, at the size each is for ---------------------------

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


## The reef's fifth part: a cove against the open-end wall, a refuge for the tight
## channel's tier at the end of the map where every crossing admits the chaser too.
##
## [b]What this section is about is that the cove is a ROOM and not a wall[/b]: three
## doors that admit exactly who the tight channel admits, floor behind them that nobody
## bigger can reach or reach into, and water round the outside that a leader still walks
## through at its ground speed. Every arithmetic check would pass over a cove whose posts
## stood in a leader's way, so a leader is driven past it; and every one would pass over
## a cove too shallow to shelter anybody, so one that has eaten is pressed into a door and
## the gap between its front and a starting monster at the back is measured.
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

	# --- The doors, which are the level ---------------------------------------

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

	# --- A leader's water, round the outside ----------------------------------

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

	# --- A room: it holds more than it lets out -------------------------------

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

	# --- Reach: just too big for a door ---------------------------------------

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

	# --- Hunters: refused, as a harbour is --------------------------------------

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

	# --- Driven: a starting monster in, a leader past -------------------------

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

	# --- Straight at the door between the posts -------------------------------

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


## The shallows: five lines of posts whose gaps widen toward the open water, so how far in
## a monster can go is a function of its size.
##
## [b]Asked at the sizes each line is FOR, and driven rather than compared.[/b] Every
## arithmetic check over the lines would pass on lines built in the wrong order, or so
## close together that a band is a slot: so the gaps are measured off the discs against
## the description, the water between every two lines against the gap that lets you in,
## the floor swept at just over each line's limit, and then three monsters are driven — a
## starting one along a route to the shallow wall, a middling one to the band its size
## allows, and a leader straight in until its tree line holds it.
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

	# --- The lines, measured off the discs ------------------------------------

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

	# --- The bands: never narrower than the gap that lets you in ----------------

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

	# --- Reach: the floor recedes one band per line as a monster grows ----------

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

	# --- Hunters: the deepest band is refused them ------------------------------

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

	# --- Driven: a starting monster to the shallow wall -------------------------

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

	# --- A middling monster: as far as its size allows -------------------------

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

	# --- The leader: through the last line and held at its tree line ------------

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


## The shallows' rock pools: one post off each corner of the open water, two doors each
## the tightest line's width, and a room behind it.
##
## [b]The cove's questions, asked in a corner.[/b] The doors measured off the discs; the
## water between a pool and the last line wider than a leader; the room holding more
## than a door lets out; a monster just too big for a door reaching everything but the
## pools and the deepest band; hunters refused; and then driven — a starting monster from
## the open water into the south pool, a leader along the open wall to the floor beside
## it, both at their ground speed, and straight along the south wall at the door: a
## starting monster comes in, one at 1.6 times the door's limit is held.
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

	# --- The doors, which are the level ---------------------------------------

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

	# --- A room: it holds more than it lets out -------------------------------

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

	# --- Reach: just too big for a door ---------------------------------------

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

	# --- Hunters: refused, as the cove is -------------------------------------

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

	# --- Driven: a starting monster in, a leader beside it --------------------

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

	# --- Straight along the south wall at the west door -----------------------

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

	# --- Outgrown: a monster too big for the room stays inside the arena ----------
	# `[refuge-outgrown-1]`: the post's push-out used to put it through the wall (113
	# units past the edge at 825 mass, steering or not). It overlaps the post instead.
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

	# --- The three rules a server can choose (`hungry_outgrown`) ----------------------
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


## The shallows' groynes: two posts each from a quarter post of the last line to the
## open wall, three doors each the shallows' first three gaps, tightest at the line.
##
## [b]What a groyne is for is a detour, so the section measures one.[/b] The doors
## measured off the discs and joined to the line; the open water cut into three bays;
## the same crossing planned for a starting monster (straight through the wall door)
## and for a leader (back through the last line and round), and both DRIVEN at their
## ground speed; straight at the wall door, one just under its limit comes through and
## one at 1.6 times it is held. And because `[refuge-outgrown-1]` asks it of every
## enclosed room: a bay is not one — a hunter may appear in every bay, and a monster
## grown past the tightest door while standing in it ends up in a bay, touching nothing.
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

	# --- The doors, which are the level ---------------------------------------

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

	# --- Three bays -------------------------------------------------------------

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

	# --- The detour: one crossing, planned at both sizes --------------------------

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

	# --- Not a refuge -------------------------------------------------------------

	var lurker := HungryHunters.largest_radius()
	var region := layout.main_region(bounds, lurker)
	var allowed := 0

	for at: Vector2 in bay_centres:
		if HungryHunters.spawnable(layout, bounds, at, region):
			allowed += 1

	_check(allowed == 3, "no bay is a refuge: a hunter may appear in every one", "%d of 3" % allowed)

	# --- Driven: the same crossing, short way and long way -------------------------

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

	# --- Straight at the wall door ------------------------------------------------

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

	# --- Outgrown in a door: it is pushed into a bay, not held -------------------

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


## The shallows' inlet: two posts off the open wall in the middle bay, three doors each
## the tightest line's gap, the middle bay's room.
##
## [b]The cove's questions, asked in the bay that had no room[/b], and one more: the water
## beside the inlet must be wider than the fourth line, or it is a gate the lines do not
## have (the first design, a tier up, failed exactly that). The doors measured off the
## discs; a leader's water in front; a room that holds more than it lets out; hunters
## refused. Then driven: a starting monster along its route into the room, a leader across
## the bay in front of it, straight at the middle door one under the limit comes in and
## one at 1.6 times it is held; and [HungryBot]s playing on their own from the middle bay,
## which go in and out of it.
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

	# --- The doors, which are the level ---------------------------------------

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

	# --- Placed: in the middle bay, a leader's water in front, no hidden gate ----

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

	# --- A room: it holds more than it lets out -------------------------------

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

	# --- Reach: the tier it is for ----------------------------------------------

	var bay := Vector2((face + front) * 0.5, mid_y)
	_check(
		layout.route_to(bounds, bay, inside, door * 0.5 + 16.0).is_empty()
			and not layout.route_to(bounds, bay, inside, door * 0.5 - 16.0).is_empty(),
		"one just over its door has no route in from the bay, and one just under has",
		"radii %.0f / %.0f" % [door * 0.5 + 16.0, door * 0.5 - 16.0]
	)

	# --- Hunters: refused, as the pools are --------------------------------------

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

	# --- Driven: a starting monster in, a leader across in front -------------------

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

	# --- Straight at the middle door --------------------------------------------

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

	# --- Bots, playing on their own --------------------------------------------------
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


## The shallows' sills: a post across the second line's band and two across the third's,
## each the tightest line's gap off a post of the line inside it and off the line outside.
##
## [b]What a sill is for is a detour inside a band, so the section measures one.[/b] The
## doors measured off the discs; the same crossing planned just under and just over a
## door's limit; then driven past two of them at their ground speed, a starting monster
## through the door and one of the band's bigger residents out through a line beside it
## and back in; straight at a door one under the limit comes through and one at 1.6 times
## it is held. Not a refuge: a hunter may appear beside every sill.
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

	# --- The doors, which are the level ---------------------------------------

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

	# --- The detour: one crossing past each sill, planned either side of the door ---

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

	# --- Not a refuge -------------------------------------------------------------

	var lurker := HungryHunters.largest_radius()
	var region := layout.main_region(bounds, lurker)
	var allowed := 0

	for at in froms + tos:
		if HungryHunters.spawnable(layout, bounds, at, region):
			allowed += 1

	_check(allowed == froms.size() * 2, "no sill is a refuge: a hunter may appear either side of every one", "%d of %d" % [allowed, froms.size() * 2])

	# --- Driven: past the second band's sill and one of the third's ----------------

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

	# --- Straight at the second band's inner door -----------------------------------

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


## Drives [param monster] along [param route] at full reach, measuring what the level
## sections measure: how deep any piece went into any rock, how many waypoints it reached,
## how far it got along [param axis], and what it covered against the route's length and
## its ground speed. Prints the `[bot-drive-1]` line.
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


## The warrens' den: a ring inside the ring, driven into by a starting monster and refused
## to one that has eaten.
##
## [b]The warrens' section asks the ring its question; this asks the den its own.[/b] The
## den's gates admit about a tenth of the winning mass where the ring's admit about a
## third, so the map has three tiers now and each has to be proved at the size it is FOR:
## a starting monster from the wall gets through both, one between the two limits gets
## through the ring and no further, and nothing about the den may narrow the moat it
## stands in below the ring's own gate — that would be a hidden gate only a monster
## already inside could find.
##
## [b]Driven along a route found on the geometry[/b], `HungryLayout.route_to`, rather
## than along a line picked by hand: a line picked by hand is a claim about where the
## gates are, and the route is what the rocks the world built actually leave.
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

	# --- Reach, at the size each tier is for -------------------------------

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

	# --- Driven: a starting monster from the wall to the centre -------------

	world.spawn(1, wall)
	_run_ticks(world, 2)

	var monster := world.monster_for(1)

	if not _check(monster != null and monster.alive, "a starting monster spawns by the west wall, off the axis"):
		_drop(world)
		_done()
		return

	var small := monster.pieces[0].radius()
	# Planned 24 wider than the monster — `route_across`'s margin — because a monster
	# steered at a waypoint swings wide of the leg on every turn. At 12 it pressed a den
	# rock's face, ate on the same tick, and grew 2.3 units into it before the next
	# push-out.
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

	# --- And one that has eaten is held at the door --------------------------

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


## The corridor's ends: a fence of posts across each, with a harbour behind it that a
## starting monster walks into and one that has fed is held out of.
##
## [b]Asked at the size each side of the fence is FOR[/b], like the den: the doors'
## design number and their tier against the slalom's lanes, the water in front of the
## fence that must not be a hidden gate, a sweep in which a monster just too big for a
## door reaches everything but the two harbours, and then driven — a starting monster
## along a route [method HungryLayout.route_to] finds from the middle of the corridor
## into the west harbour, and one at 1.6 times the door limit straight at a door.
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

	# --- Reach, just too big for a door -------------------------------------

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

	# --- Driven: a starting monster from the corridor into the harbour ------

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

	# --- And one that has eaten is held at the door --------------------------

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
