extends "headless_round_levels.gd"

## Plays whole rounds of the game with nobody watching, and checks that they work.
##
## [codeblock]
## godot --headless --path . res://examples/headless_round.tscn
## [/codeblock]
##
## Exits non-zero on any failure, so it works as a smoke test as-is.
##
## [b]This is the file that finds the bugs.[/b] Everything here parses cleanly whether it
## is right or wrong: a monster that grows outside the wall, a field that hands out the
## same slot twice, a burst that quietly does nothing because the piece cap was already
## reached. None of those produce an error, and none of them are visible by reading the
## code. They are visible by running eight monsters for two minutes and measuring.

const CHECKS := 477

func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-hungario: a round")
	print("")

	_test_setup()
	_test_food_tiers()
	_test_growing()
	_test_fruit()
	_test_items_and_throwing()
	_test_lure()
	_test_splitting()
	_test_merging()
	_test_devouring()
	_test_interest()
	_test_round_reset()
	_test_determinism()
	_test_full_round()
	_test_what_a_bot_travels_at()
	_test_sound()
	_test_ejecting()
	_test_loadout()
	_test_rider()
	_test_interface()
	_test_the_gauntlet()
	_test_the_warrens()
	_test_the_slalom()
	_test_the_reef()
	_test_the_lagoon()
	_test_the_atoll()
	_test_the_spits()
	_test_the_cove()
	_test_the_shallows()
	_test_the_rock_pools()
	_test_the_groynes()
	_test_the_inlet()
	_test_the_sills()
	_test_the_den()
	_test_the_harbours()
	_test_hunter_round_a_rock()
	_test_where_a_hunter_appears()
	_test_a_lurker_on_the_shared_graph()
	_test_the_reach()
	_test_food_on_the_floor()
	_test_spectating()

	print("")
	_check(
		_completed == _entered,
		"every section ran to its last line (%d of %d)" % [_completed, _entered],
		"a section that aborted stops adding checks and the total cannot show it"
	)

	_report(CHECKS)


func _test_setup() -> void:
	_section("setting up")

	var world := _make_world()

	_check(world.arena != null, "the arena exists")
	_check(
		world.field.food_count() == HungryContent.FOOD_TARGET,
		"the food field is full (%d)" % world.field.food_count()
	)
	_check(
		world.field.fruit_count() == HungryContent.FRUIT_TARGET,
		"and the fruit is out (%d)" % world.field.fruit_count()
	)
	_check(
		world.field.item_count() == HungryContent.ITEM_TARGET,
		"and the item drops (%d)" % world.field.item_count()
	)

	# Everything alive has to be in the grid, or it cannot be eaten and nothing says so.
	var indexed := 0

	for grid_id in world.field.alive_ids():
		if world.arena.grid.has(grid_id):
			indexed += 1

	_check(
		indexed == world.field.alive_count(),
		"every slot is indexed into the grid",
		"%d of %d" % [indexed, world.field.alive_count()]
	)

	var added := world.add_player(1, "Ada")
	_check(added.ok, "a player joins")

	world.spawn(1)
	var monster := world.monster_for(1)

	_check(monster != null and monster.alive, "and is in the world")
	# The starting mass is the constant *times the trait's*: a loadout that traded nothing
	# on the way in would be a choice with no consequence until much later.
	_check(
		monster != null and is_equal_approx(
			monster.mass(),
			HungryContent.START_MASS * HungryContent.trait_mass(monster.trait_id)
		),
		"at the starting mass their trait gives them (%.1f)"
			% (monster.mass() if monster != null else 0.0)
	)
	_check(
		monster != null and monster.carried.size() == 1
			and monster.carried[0] == monster.starter_item(),
		"holding the throwable their loadout chose (%s)"
			% (String(monster.starter_item()) if monster != null else "-")
	)
	_check(
		monster != null and monster.piece_count() == 1,
		"as a single piece"
	)
	_check(
		monster != null and monster.rider_piece() != null
			and monster.rider_piece().state.has_flag(HungryContent.FLAG_RIDER),
		"whose one piece carries the rider"
	)

	_drop(world)
	_done()


func _test_food_tiers() -> void:
	_section("food comes in sizes")

	var world := _make_world()
	var counts := [0, 0, 0, 0]

	for grid_id in world.field.alive_ids():
		if HungryField.kind_of(grid_id) != HungryField.Kind.FOOD:
			continue

		counts[world.field.tier_of(grid_id)] += 1

	for tier in range(4):
		_check(
			counts[tier] > 0,
			"tier %d (%s) appears %d times" % [
				tier, HungryContent.FOOD_TIER_NAMES[tier], counts[tier]
			]
		)

	# The rarest tier must actually be rare, or "different sizes" is four names for the
	# same thing. The weights say 4%; anything over a tenth means the cutoffs are wrong.
	var total: int = counts[0] + counts[1] + counts[2] + counts[3]
	var rarest := float(counts[3]) / maxf(1.0, float(total))

	_check(
		rarest > 0.01 and rarest < 0.10,
		"haunches are rare (%.1f%%)" % (rarest * 100.0)
	)
	_check(
		counts[0] > counts[1] and counts[1] > counts[2] and counts[2] > counts[3],
		"and the tiers get rarer in order",
		str(counts)
	)

	# The size a client draws and the size the server eats at must be the same function
	# of the same slot, or a crumb is eaten from somewhere it is not drawn.
	var sample := world.field.alive_ids()[0]
	_check(
		is_equal_approx(
			world.field.radius_of(sample),
			HungryContent.FOOD_TIER_RADIUS[world.field.tier_of(sample)]
		),
		"radius and tier agree"
	)

	_drop(world)


# --- Growing ---------------------------------------------------------------
	_done()

func _test_growing() -> void:
	_section("growing")

	var world := _make_world()
	world.add_player(1, "Ada")
	_settle(world)

	# Somewhere with food around it, rather than wherever the safe spawn picked.
	world.spawn(1, Vector2.ZERO)

	var monster := world.monster_for(1)
	var before := monster.mass()
	var eaten := [0]

	world.food_eaten.connect(func(_p: int, _g: int, _m: float) -> void:
		eaten[0] += 1
	)

	# Chase the nearest crumb for a few seconds. A monster that simply sat still would
	# prove nothing: the field has a margin and the centre may be empty.
	for _i in range(600):
		var head := monster.rider_piece()
		var target := _nearest_food(world, head.position())
		world.tick({1: _aim_at(head.position(), target)})

	_check(eaten[0] > 0, "a monster eats what it runs over (%d)" % eaten[0])
	_check(
		monster.mass() > before,
		"and gets bigger (%.0f -> %.0f)" % [before, monster.mass()]
	)
	_check(
		monster.food_eaten == eaten[0],
		"and the counter agrees with the signal"
	)

	# Radius must follow mass through the same function the eat check uses.
	var rules := world.tunables.mass_rules
	_check(
		is_equal_approx(
			monster.rider_piece().radius(), rules.radius_for(monster.rider_piece().mass())
		),
		"the radius follows the mass"
	)

	# Growing is a move. A monster pinned against a wall that eats gets wider, and only a
	# *moving* entity is clamped by the motor — this is the check that catches it.
	_check(_furthest_edge(world) <= 0.5, "nothing has grown through a wall")

	_drop(world)


## The distance the furthest monster edge sticks out past the arena, or zero.
	_done()
func _furthest_edge(world: HungryWorld) -> float:
	var bounds := world.arena.bounds
	var worst := 0.0

	for piece in world.pieces():
		var at := piece.position()
		var radius := piece.radius()

		worst = maxf(worst, bounds.position.x - (at.x - radius))
		worst = maxf(worst, bounds.position.y - (at.y - radius))
		worst = maxf(worst, (at.x + radius) - bounds.end.x)
		worst = maxf(worst, (at.y + radius) - bounds.end.y)

	return worst


func _nearest_food(world: HungryWorld, from: Vector2) -> Vector2:
	var best := from + Vector2.RIGHT * 100.0
	var best_distance := INF

	for grid_id in world.field.alive_ids():
		if HungryField.kind_of(grid_id) == HungryField.Kind.ITEM:
			continue

		var at := world.field.position_of(grid_id)
		var distance := from.distance_squared_to(at)

		if distance < best_distance:
			best_distance = distance
			best = at

	return best


# --- Fruit -----------------------------------------------------------------

func _test_fruit() -> void:
	_section("fruit")

	var world := _make_world()
	world.add_player(1, "Ada")
	_settle(world)
	world.spawn(1, Vector2.ZERO)

	var monster := world.monster_for(1)
	var kinds := {}

	for grid_id in world.field.alive_ids():
		if HungryField.kind_of(grid_id) == HungryField.Kind.FRUIT:
			kinds[world.field.fruit_kind_of(grid_id)] = true

	_check(kinds.size() >= 2, "several kinds of fruit are out (%d)" % kinds.size())

	# Put a known fruit under the monster rather than hunting one down: what is being
	# tested is the effect, not the pathfinding.
	var fruit_id := _first_of(world, HungryField.Kind.FRUIT)
	var kind := world.field.fruit_kind_of(fruit_id)
	var at := world.field.position_of(fruit_id)

	world.spawn(1, at)
	var before := monster.mass()
	world.tick({})

	_check(
		monster.mass() > before + HungryContent.FRUIT_MASS * 0.5,
		"eating one is worth a lot of mass (%.0f -> %.0f)" % [before, monster.mass()]
	)

	var flag: int = [
		HungryContent.FLAG_RUSH, HungryContent.FLAG_MAW, HungryContent.FLAG_RIND
	][int(kind)]

	_check(
		monster.has_effect(flag, world.current_tick()),
		"and applies its effect (%s)" % HungryContent.FRUIT_NAMES[int(kind)]
	)
	_check(
		(monster.rider_piece().state.flags & flag) != 0,
		"which is on the piece's flags, so a client can draw it"
	)

	if kind == HungryContent.Fruit.RUSH:
		_check(
			monster.speed_multiplier(world.current_tick())
				> HungryContent.RUSH_SPEED_MULTIPLIER - 0.01,
			"and rush makes them faster"
		)

	# Effects are counted in ticks and must actually run out. An effect that never
	# expired would be invisible for eight seconds and permanent afterwards.
	_run_ticks(world, int(HungryContent.FRUIT_EFFECT_SEC * TICK_RATE) + 2)
	_check(
		not monster.has_effect(flag, world.current_tick()),
		"and it expires on time"
	)
	_check(
		is_equal_approx(
			monster.speed_multiplier(world.current_tick()),
			HungryContent.trait_speed(monster.trait_id)
		),
		"leaving the monster at whatever its trait gives it (%.2f)"
			% monster.speed_multiplier(world.current_tick())
	)

	_drop(world)
	_done()


func _first_of(world: HungryWorld, kind: HungryField.Kind) -> int:
	for grid_id in world.field.alive_ids():
		if HungryField.kind_of(grid_id) == kind:
			return grid_id

	return 0


# --- Items -----------------------------------------------------------------

func _test_items_and_throwing() -> void:
	_section("throwables")

	var world := _make_world()
	world.add_player(1, "Ada")
	world.add_player(2, "Bo")
	_settle(world)

	var thrower := world.monster_for(1)
	var victim := world.monster_for(2)

	var drop := _first_of(world, HungryField.Kind.ITEM)
	world.spawn(1, world.field.position_of(drop))

	# One already, from the loadout. What is being checked is that running over a drop
	# adds to it.
	var held := thrower.carried.size()
	world.tick({})

	_check(
		thrower.carried.size() == held + 1,
		"running over a drop picks it up (%d -> %d)" % [held, thrower.carried.size()]
	)

	# The cap has to refuse rather than swallow. An item that vanished because you were
	# full reads as a bug every single time.
	thrower.carried.clear()

	for _i in range(HungryContent.MAX_CARRIED):
		thrower.take_item(HungryContent.ITEM_PEPPER)

	var another := _first_of(world, HungryField.Kind.ITEM)
	var still_there := world.field.take(another)
	_check(still_there, "a full monster leaves the drop where it is")

	# Now the pepper. A victim large enough to be worth bursting, right in front.
	world.spawn(1, Vector2(-300.0, 0.0))
	world.spawn(2, Vector2(100.0, 0.0))

	# Spawn protection stops a thrown pepper too, and that rule has its own check in
	# `_test_devouring`. Cleared here rather than waited out, so that four seconds of
	# ticks do not move either of them somewhere else first.
	thrower.clear_effect(HungryContent.FLAG_PROTECTED)
	victim.clear_effect(HungryContent.FLAG_PROTECTED)

	thrower.carried.clear()
	thrower.take_item(HungryContent.ITEM_PEPPER)
	thrower.throw_ready_tick = world.current_tick()

	var grown := victim.rider_piece()
	grown.set_mass(HungryContent.MIN_BURST_MASS * 3.0, world.tunables.mass_rules)

	var pieces_before := victim.piece_count()
	var burst_seen := [0]
	world.monster_burst.connect(func(_p: int, _b: int, count: int) -> void:
		burst_seen[0] += count
	)

	var throw_command := _aim_at(
		thrower.rider_piece().position(),
		victim.rider_piece().position(),
		Dot2DCommand.BUTTON_ACTION
	)
	# Held still, so the two do not drift into each other while the pepper is in flight.
	var hold := Dot2DCommand.new()

	world.tick({1: throw_command, 2: hold})
	_check(world.projectiles().size() == 1, "throwing puts a pepper in flight")
	_check(thrower.carried.is_empty(), "and spends the charge")

	for _i in range(90):
		world.tick({1: hold, 2: hold})

		if victim.piece_count() > pieces_before:
			break

	_check(
		victim.piece_count() > pieces_before,
		"the pepper bursts them (%d -> %d pieces)" % [
			pieces_before, victim.piece_count()
		]
	)
	_check(burst_seen[0] > 0, "and says so")
	_check(world.projectiles().is_empty(), "and the pepper is gone")

	# You still control the pieces, and they still all belong to you.
	var mine := true

	for piece in victim.pieces:
		mine = mine and piece.owner_id == victim.id

	_check(mine, "and every piece is still theirs")

	# A burst piece cannot re-merge immediately, or a burst heals itself instantly and
	# is not a threat at all.
	var delayed := true

	for piece in victim.pieces:
		delayed = delayed and not piece.can_merge(world.current_tick())

	_check(delayed, "and none of them may merge yet")

	# The rind fruit eats a burst outright. Not "reduces": a fruit whose effect is
	# invisible is a fruit nobody picks up on purpose.
	victim.apply_effect(
		HungryContent.FLAG_RIND, world.current_tick() + TICK_RATE * 10
	)
	var protected_before := victim.piece_count()
	var made := world.burst(victim, 1)

	_check(made == 0, "a rind absorbs a burst entirely")
	_check(
		victim.piece_count() == protected_before,
		"leaving the monster whole"
	)
	_check(
		not victim.has_effect(HungryContent.FLAG_RIND, world.current_tick()),
		"and is spent doing it"
	)

	# Frost.
	thrower.carried.clear()
	thrower.take_item(HungryContent.ITEM_FROST)
	var frost_command := _aim_at(
		thrower.rider_piece().position(),
		victim.rider_piece().position(),
		Dot2DCommand.BUTTON_ACTION
	)
	thrower.throw_ready_tick = world.current_tick()
	world.tick({1: frost_command, 2: hold})

	for _i in range(90):
		world.tick({1: hold, 2: hold})

		if victim.has_effect(HungryContent.FLAG_FROSTED, world.current_tick()):
			break

	_check(
		victim.has_effect(HungryContent.FLAG_FROSTED, world.current_tick()),
		"a frostberry slows its target"
	)
	_check(
		victim.speed_multiplier(world.current_tick()) < 1.0,
		"which is a real speed change (%.2f)"
			% victim.speed_multiplier(world.current_tick())
	)

	_drop(world)
	_done()


func _test_lure() -> void:
	_section("the lure")

	var world := _make_world()
	world.add_player(1, "Ada")
	_settle(world)
	world.spawn(1, Vector2(-800.0, 0.0))

	var monster := world.monster_for(1)
	# After the spawn, because a spawn hands out the loadout's charge and clears whatever
	# was there.
	monster.carried.clear()
	monster.take_item(HungryContent.ITEM_LURE)
	monster.throw_ready_tick = world.current_tick()

	var planted_before := world.field.planted_count()
	var head := monster.rider_piece()

	world.tick({
		1: _aim_at(
			head.position(),
			head.position() + Vector2.RIGHT * 400.0,
			Dot2DCommand.BUTTON_ACTION
		)
	})

	var hold := Dot2DCommand.new()

	for _i in range(180):
		world.tick({1: hold})

		if world.field.planted_count() > planted_before:
			break

	_check(
		world.field.planted_count() >= HungryContent.LURE_FOOD_COUNT,
		"a lure plants a ring of food (%d)" % world.field.planted_count()
	)

	# Planted food is the one kind whose position is *sent* rather than derived, so it
	# has to be in the grid at the position the field reports.
	var mismatched := 0
	var planted_ids: Array[int] = []

	for grid_id in world.field.alive_ids():
		if HungryField.kind_of(grid_id) != HungryField.Kind.PLANTED:
			continue

		planted_ids.append(grid_id)

		if not world.arena.grid.has(grid_id) \
				or world.arena.grid.position_of(grid_id).distance_to(
					world.field.position_of(grid_id)
				) > 0.01:
			mismatched += 1

	_check(mismatched == 0, "and every crumb of it is in the grid where it says")

	var rows := world.field.planted_rows(planted_ids)
	_check(
		rows.size() == planted_ids.size(),
		"and each one has a position to send"
	)

	# Inside the world, including near a wall. A ring clamped badly is food nobody can
	# reach.
	var outside := 0

	for grid_id in planted_ids:
		if not world.arena.bounds.has_point(world.field.position_of(grid_id)):
			outside += 1

	_check(outside == 0, "and none of it is outside the arena")

	_drop(world)


# --- Splitting and merging -------------------------------------------------
	_done()

func _test_splitting() -> void:
	_section("splitting")

	var world := _make_world()
	world.add_player(1, "Ada")
	_settle(world)
	world.spawn(1, Vector2.ZERO)

	var monster := world.monster_for(1)
	monster.rider_piece().set_mass(400.0, world.tunables.mass_rules)
	monster.clear_effect(HungryContent.FLAG_PROTECTED)

	var mass_before := monster.mass()
	var split := _aim_at(Vector2.ZERO, Vector2.RIGHT * 500.0, Dot2DCommand.BUTTON_SPLIT)
	var release := _aim_at(Vector2.ZERO, Vector2.RIGHT * 500.0)

	world.tick({1: split})

	_check(monster.piece_count() == 2, "a split makes two pieces")
	# Not exactly: a monster this wide covers a lot of ground and eats whatever it is
	# sitting on during the same tick. What a split must not do is lose mass.
	_check(
		monster.mass() >= mass_before * 0.98,
		"and conserves mass (%.1f -> %.1f)" % [mass_before, monster.mass()]
	)

	var halves := monster.pieces
	_check(
		absf(halves[0].mass() - halves[1].mass()) < mass_before * 0.15,
		"into two roughly equal halves (%.0f and %.0f)"
			% [halves[0].mass(), halves[1].mass()]
	)

	# Both halves, not just the new one. A parent that could re-absorb its child at once
	# makes splitting free, and splitting is supposed to be a risk.
	var both_delayed := true

	for piece in monster.pieces:
		both_delayed = both_delayed and not piece.can_merge(world.current_tick())

	_check(both_delayed, "and both halves have to wait to merge")

	# Held down, a split must not fire every tick. Without a cooldown the piece cap is
	# reached in a fifth of a second, which is a stutter rather than a decision.
	var after_one := monster.piece_count()
	world.tick({1: split})
	_check(
		monster.piece_count() == after_one,
		"a held key does not split again (edge-triggered)"
	)

	# Released and pressed again, but still inside the cooldown.
	world.tick({1: release})
	world.tick({1: split})
	_check(
		monster.piece_count() == after_one,
		"and the cooldown holds even after a release"
	)

	# Past the cooldown it works again.
	for _i in range(HungryContent.SPLIT_COOLDOWN_TICKS + 2):
		world.tick({1: release})

	world.tick({1: split})
	_check(monster.piece_count() > after_one, "and works again once it has passed")

	# The cap. Splitting repeatedly must stop at max_pieces rather than growing for ever.
	for _i in range(40):
		for _j in range(HungryContent.SPLIT_COOLDOWN_TICKS + 1):
			world.tick({1: release})

		world.tick({1: split})

	_check(
		monster.piece_count() <= world.tunables.mass_rules.max_pieces,
		"the piece cap holds (%d of %d)" % [
			monster.piece_count(), world.tunables.mass_rules.max_pieces
		]
	)

	# Separation. Pieces that cannot merge must not sit inside each other, or a split
	# collapses back into a pile and stops meaning anything.
	var overlapping := 0

	for a in range(monster.pieces.size()):
		for b in range(a + 1, monster.pieces.size()):
			var first := monster.pieces[a]
			var second := monster.pieces[b]
			var gap := first.position().distance_to(second.position())

			if gap < (first.radius() + second.radius()) * 0.5:
				overlapping += 1

	_check(overlapping == 0, "and the pieces push apart (%d piles)" % overlapping)
	_check(_furthest_edge(world) <= 0.5, "and stay inside the world")

	_drop(world)
	_done()


func _test_merging() -> void:
	_section("merging back")

	# A preset with a short delay, so this does not take sixteen seconds of ticks.
	var preset := HungryPreset.classic()
	preset.merge_delay_sec = 1.0

	var world := _make_world(preset)
	world.add_player(1, "Ada")
	_settle(world)
	world.spawn(1, Vector2.ZERO)

	var monster := world.monster_for(1)
	monster.rider_piece().set_mass(600.0, world.tunables.mass_rules)
	monster.clear_effect(HungryContent.FLAG_PROTECTED)

	var split := _aim_at(Vector2.ZERO, Vector2.RIGHT * 500.0, Dot2DCommand.BUTTON_SPLIT)
	var release := _aim_at(Vector2.ZERO, Vector2.RIGHT * 500.0)

	# Twice, with the cooldown in between, so there are three or four pieces rather than
	# two. Three in a pile is what the repeated pass in `_resolve_merges` exists for: a
	# single pass a tick merges two of them and leaves the third, which reads as a merge
	# that stutters.
	world.tick({1: split})

	for _i in range(HungryContent.SPLIT_COOLDOWN_TICKS + 2):
		world.tick({1: release})

	world.tick({1: split})

	var most := monster.piece_count()
	_check(most >= 3, "there are pieces to merge (%d)" % most)

	var mass_before := monster.mass()

	# Pull everything to one point: merging needs the delay *and* proximity.
	var gather := Dot2DCommand.new()

	for _i in range(TICK_RATE * 6):
		world.tick({1: gather})

		if monster.piece_count() == 1:
			break

	_check(
		monster.piece_count() == 1,
		"they come back together (%d -> %d)" % [most, monster.piece_count()]
	)
	_check(
		monster.mass() > mass_before * 0.9,
		"keeping the mass (%.0f -> %.0f)" % [mass_before, monster.mass()]
	)

	# Three pieces in a pile merge two at a time, so a single pass a tick would leave the
	# third behind and look like a merge that stutters. The loop in `_resolve_merges` is
	# what this checks — it only shows up above two pieces.
	_check(most > 2, "and this ran with more than two pieces (%d)" % most)

	_drop(world)


# --- Eating each other -----------------------------------------------------
	_done()

func _test_devouring() -> void:
	_section("eating each other")

	var world := _make_world()
	world.add_player(1, "Big")
	world.add_player(2, "Small")
	_settle(world)

	world.spawn(1, Vector2(0.0, 0.0))
	world.spawn(2, Vector2(40.0, 0.0))

	var big := world.monster_for(1)
	var small := world.monster_for(2)

	big.rider_piece().set_mass(500.0, world.tunables.mass_rules)

	# Spawn protection first: this is a rule, and a test that cleared it would never
	# notice if it stopped working.
	var eaten := [0]
	world.piece_eaten.connect(func(_e: int, _v: int, _m: float) -> void:
		eaten[0] += 1
	)

	world.tick({})
	_check(eaten[0] == 0, "spawn protection stops an instant kill")

	# Cleared rather than waited out. Four seconds of ticks with a 500-mass monster forty
	# units from a 22-mass one is four seconds in which the kill happens on its own — and
	# then the chase below starts by asking a dead monster where it is, which is a runtime
	# error that aborts the rest of this function while every check that already ran still
	# says ok. That is how eight checks stopped running without the count going down.
	big.clear_effect(HungryContent.FLAG_PROTECTED)
	small.clear_effect(HungryContent.FLAG_PROTECTED)

	var deaths := [0]
	world.player_died.connect(func(_p: int, _k: int) -> void: deaths[0] += 1)

	var stand := Dot2DCommand.new()
	var chase := _aim_at(
		big.rider_piece().position(), small.rider_piece().position()
	)

	for _i in range(180):
		world.tick({1: chase, 2: stand})

		if not small.alive:
			break

		var hunter := big.rider_piece()
		var prey := small.rider_piece()

		if hunter == null or prey == null:
			break

		chase = _aim_at(hunter.position(), prey.position())

	_check(not small.alive, "a bigger monster devours a smaller one")
	_check(deaths[0] == 1, "and it is reported once")
	_check(big.players_eaten == 1, "and counted")
	_check(
		big.mass() > 500.0,
		"and the eater keeps the mass (%.0f)" % big.mass()
	)
	_check(
		world.match_node.scoreboard.find("1").kills == 1,
		"and dot-match recorded the kill"
	)

	# How the last piece goes down on every screen: picked here, once (dot-player-char's
	# rule over the server's weights), and pushed away from the eater. Armed by deciding
	# nothing in `_absorb` (null) and by measuring power the wrong way round (the shares).
	_check(
		small.death != null and DotPlayerDeathReactions.stock().find(small.death.reaction) != null
			and small.death.direction.length() > 0.9 and small.death.damage > 0.0,
		"the eaten monster's fall is the server's pick, with a push",
		str(small.death.describe()) if small.death != null else "none"
	)
	world.ragdoll_rules.reaction_weights = "limp=0,face_plant=0,crumple=0,headshot_launch=0"
	var thrown := world.decide_death(5, false, HungryWorld.power_of(12.0), 30.0, Vector2.RIGHT)
	var nudged := world.decide_death(5, false, HungryWorld.power_of(3.0), 30.0, Vector2.RIGHT)
	_check(
		thrown.reaction == DotPlayerDeathReactions.POWER_LAUNCH
			and nudged.reaction == DotPlayerDeathReactions.LIMP,
		"a monster ten times your size can throw you, one three times cannot",
		"%s / %s" % [thrown.reaction, nudged.reaction]
	)
	world.ragdoll_rules.reaction_weights = "limp=0,face_plant=0,crumple=0,power_launch=0"
	var whole := world.decide_death(5, true, 0.0, 30.0, Vector2.RIGHT)
	_check(
		whole.reaction == DotPlayerDeathReactions.HEADSHOT_LAUNCH
			and world.decide_death(5, false, 0.0, 30.0, Vector2.RIGHT).reaction == DotPlayerDeathReactions.LIMP,
		"swallowed whole is this game's headshot",
	)
	world.ragdoll_rules.reaction_weights = ""

	# Respawning is dot-match's, driven from a tick count rather than a timer.
	for _i in range(int(TICK_RATE * 5)):
		world.tick({})

		if small.alive:
			break

	_check(small.alive, "and the victim comes back")
	_check(
		is_equal_approx(
			small.mass(),
			HungryContent.START_MASS * HungryContent.trait_mass(small.trait_id)
		),
		"at the starting mass their trait gives them again (%.1f)" % small.mass()
	)

	# Two monsters of equal size must never eat each other, whichever is resolved first.
	# That is what an eat ratio above 1 is for, and it is the difference between a rule
	# and a coin flip.
	world.spawn(1, Vector2(0.0, 500.0))
	world.spawn(2, Vector2(10.0, 500.0))
	big.rider_piece().set_mass(200.0, world.tunables.mass_rules)
	small.rider_piece().set_mass(200.0, world.tunables.mass_rules)
	big.clear_effect(HungryContent.FLAG_PROTECTED)
	small.clear_effect(HungryContent.FLAG_PROTECTED)

	_run_ticks(world, 30)
	_check(
		big.alive and small.alive,
		"two equal monsters cannot eat each other"
	)

	_drop(world)


# --- Interest --------------------------------------------------------------
	_done()

## Where a dead monster's owner looks.
func _test_spectating() -> void:
	_section("spectating")

	var world := _make_world()
	world.add_player(1, "Eaten")
	world.add_player(2, "Eater")
	_settle(world)

	world.spawn(1, Vector2(0.0, 0.0))
	world.spawn(2, Vector2(300.0, 0.0))

	if not _check(world.spectate != null, "the world builds a spectate layer"):
		_done()
		return

	var rules := world.spectate.manager.rules
	_check(rules.force_camera == 0, "a free-for-all restricts the camera to nobody")
	_check(
		not rules.allow_while_alive,
		"and a LIVING player may not watch: knowing where the biggest monster is "
		+ "standing is the whole skill of this game"
	)
	_check(
		not rules.allow_roaming,
		"nor roam, because a free camera over a 2D arena is the entire map"
	)

	_check(
		not world.spectate.is_spectating(1),
		"a living player is not watching anything"
	)

	# Killing them the way the world does it.
	var monster := world.monster_for(1)
	monster.alive = false
	world.player_died.emit(1, 2)

	_check(world.spectate.is_spectating(1), "a dead one is")

	# The death camera first, then a real target — the hand-over every game that writes
	# this itself gets wrong.
	_run_ticks(world, world.tick_rate * 3)

	_check(
		world.spectate.watching(1) == 2,
		"and ends up watching the player who is still alive",
		str(world.spectate.watching(1))
	)

	var where: Variant = world.spectate.camera_position(1)
	_check(where != null, "with a camera position rather than null")

	if where is Vector2:
		var target := world.monster_for(2)
		_check(
			(where as Vector2).distance_to(target.centre()) < 1.0,
			"which is where that player's monster actually is, on the XZ plane the "
			+ "whole family maps 2D onto",
			"%v against %v" % [where as Vector2, target.centre()]
		)

	# And coming back stops it.
	world.spawn(1, Vector2(0.0, 0.0))
	_check(
		not world.spectate.is_spectating(1),
		"and respawning puts them back in their own view"
	)

	# A client's world is a MIRROR, and it emits `player_died` too. The chain is the
	# server's: dot-spectate refuses `on_death` on a mirror with a `push_error`, which goes
	# to stderr and changes no exit code — so it is counted here rather than left to be
	# read. Armed: with the authority guard in `HungrySpectate._on_died` removed, the second
	# check fails with dot-spectate's "on a mirror" error.
	var mirror := _make_world(null, SEED, false)
	mirror.add_player(1, "Eaten")
	mirror.add_player(2, "Eater")
	_check(
		mirror.spectate != null and not mirror.spectate.manager.authoritative,
		"a client's world builds a mirror, not a second authority"
	)

	var errors := EngineErrors.new()
	OS.add_logger(errors)
	mirror.player_died.emit(1, 2)
	OS.remove_logger(errors)

	var seen := errors.seen()
	_check(
		seen.is_empty(),
		"and a death on it starts no chain of its own, so the engine reports no error",
		" | ".join(seen)
	)

	_drop(mirror)
	_done()


## Counts the engine's own errors while installed. A `push_error` goes to stderr and
## changes no exit code, so without this a green run can print one on every death.
class EngineErrors extends Logger:
	var _lock := Mutex.new()
	var _seen := PackedStringArray()

	func _log_error(
		_function: String, _file: String, _line: int, code: String, _rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_lock.lock()
		_seen.append(code)
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func seen() -> PackedStringArray:
		_lock.lock()
		var out := _seen.duplicate()
		_lock.unlock()
		return out


func _test_interest() -> void:
	_section("what a client is told")

	var world := _make_world()
	world.add_player(1, "Ada")
	_settle(world)
	world.spawn(1, Vector2.ZERO)

	var monster := world.monster_for(1)
	var everything := world.field.alive_count() + world.piece_count()
	var seen := world.interest_for(1)

	_check(
		seen.size() < everything,
		"a player is not told about the whole world (%d of %d)" % [
			seen.size(), everything
		]
	)

	# The cap must bound *everything*, not only the food. Sixteen players at the piece
	# limit is two hundred and fifty-six pieces, and a cap that exempted them would not
	# be a cap.
	for id in range(2, 18):
		world.add_player(id, "Crowd %d" % id)
		world.spawn(id, Vector2(float(id) * 12.0, 0.0))

	world.tick({})
	var capped := world.interest_for(1, 6)
	_check(capped.size() <= 6, "the cap holds (%d)" % capped.size())

	var pieces_first := 0

	for grid_id in capped:
		if grid_id < HungryField.PIECE_ID_LIMIT:
			pieces_first += 1

	_check(
		pieces_first == capped.size(),
		"and pieces come before food when it bites (%d of %d)" % [
			pieces_first, capped.size()
		]
	)

	# A bigger monster fills more screen and must see further, or it cannot see anything
	# it might eat.
	var small_view := world.interest_for(1).size()
	monster.rider_piece().set_mass(4000.0, world.tunables.mass_rules)
	world.tick({})
	var big_view := world.interest_for(1).size()

	_check(
		big_view > small_view,
		"a huge monster sees further (%d -> %d)" % [small_view, big_view]
	)

	_drop(world)


# --- Rounds ----------------------------------------------------------------
	_done()

func _test_round_reset() -> void:
	_section("a new round")

	var world := _make_world()
	world.add_player(1, "Ada")
	_settle(world)
	world.spawn(1, Vector2.ZERO)

	var before_ids := world.field.alive_ids()
	world.reset_world()
	var after_ids := world.field.alive_ids()

	# Slot indices are never reused, so the new field's grid ids sit *beside* the old
	# field's. If the old ones are not removed, the grid ends up holding twice as much
	# food as exists — half of it phantoms at stale positions that `take()` refuses —
	# and eating quietly stops working. This is game-blob's bug, three fields wide.
	var overlap := 0
	var after_set := {}

	for grid_id in after_ids:
		after_set[grid_id] = true

	for grid_id in before_ids:
		if after_set.has(grid_id):
			overlap += 1

	_check(overlap == 0, "the new field reuses no slot from the old one")
	_check(
		world.arena.grid.size() == after_ids.size() + world.piece_count(),
		"and the grid holds exactly the new field",
		"grid %d, field %d, pieces %d" % [
			world.arena.grid.size(), after_ids.size(), world.piece_count()
		]
	)

	# Every id in the grid must be takeable. A phantom is an id the grid has and the
	# field does not, and its only symptom is food that cannot be eaten.
	var phantoms := 0

	for grid_id in world.arena.grid.ids():
		if grid_id < HungryField.PIECE_ID_LIMIT:
			continue

		if not after_set.has(grid_id):
			phantoms += 1

	_check(phantoms == 0, "and there are no phantoms (%d)" % phantoms)

	_drop(world)
	_done()


## [warren-nav-1]: a hunter whose target stands behind a rock goes round it.
##
## [b]Until 2026-09-25 it did not.[/b] dot-npc steers straight at a goal, every world here
## was an empty box when the hunters were written, and `_keep_out_of_the_level` only
## pushed a hunter OUT of a rock — so one with its target on the far side of a ring rock
## walked at the middle of the rock and stayed against its face for as long as the target
## did. `HungryHunters.nav_for` builds dot-npc navigation from the layout and the chase
## steers along it. The arrangement is the worst case for the old behaviour: hunter, rock
## centre and target on one line, so the push-out has no tangent to slide on.
func _test_hunter_round_a_rock() -> void:
	_section("a hunter goes round a rock")

	var world := _make_world(HungryPreset.warrens(), SEED + 227)
	world.add_player(1, "Ada")
	_settle(world)

	var hunters := HungryHunters.new()
	hunters.name = "Hunters"
	add_child(hunters)
	var ready := hunters.setup(true, world)

	if not _check(ready.ok, "a hunter layer stands over the warrens", str(ready)):
		_drop_hunters(hunters)
		_drop(world)
		_done()
		return

	var bounds := world.arena.bounds
	var centre := bounds.get_center()
	var rock: Vector3 = world.layout.blocks[0]
	var rock_at := Vector2(rock.x, rock.y)
	var out := (rock_at - centre).normalized()
	var ring_at := rock_at.distance_to(centre)
	var prey_at := centre + out * (ring_at - rock.z - 120.0)
	var hunter_at := centre + out * (ring_at + rock.z + 170.0)

	world.spawn(1, prey_at)
	_run_ticks(world, 2)

	var prey := world.monster_for(1)
	hunters.tick(1.0 / float(TICK_RATE))

	var nav := hunters.spawner.nav
	_check(
		hunters.spawner.has_nav() and nav.data.point_count() > 0 and nav.data.edge_count() > 0,
		"the spawner has navigation built from the layout",
		"%s" % (str(nav.data.describe()) if nav != null else "none")
	)
	_check(
		nav != null and nav.is_reachable(
			DotNpcInstance.to_plane(hunter_at), DotNpcInstance.to_plane(prey_at), 100.0
		) and not nav.can_walk_straight(
			DotNpcInstance.to_plane(hunter_at), DotNpcInstance.to_plane(prey_at)
		),
		"and it has a way from outside the ring rock to behind it, and not a straight one"
	)

	var npc := hunters.spawner.spawn_2d(&"stalker", hunter_at)

	if not _check(
		npc != null and prey != null and prey.alive,
		"a stalker stands outside a ring rock with a starting monster behind it"
	):
		_drop_hunters(hunters)
		_drop(world)
		_done()
		return

	var body := npc.node as Node2D
	var reach := HungryHunters.radius_of(&"stalker")
	var deepest := INF
	var ticks := 0

	# [b]Six seconds, and the budget is the check.[/b] Measured 2026-09-25 with the prey
	# standing still: along the path the stalker eats it in 252 ticks (4.2 s, about 1000
	# units at 240 a second). With the navigation taken away it still gets there — a
	# disc is convex, and pressed dead-centre on one the push-out eventually slips to a
	# side — but in 624 ticks, six of those seconds spent against the rock's face, which
	# is [warren-nav-1] exactly and what a player standing behind a rock sees. A budget
	# of twenty seconds passed both.
	for _i in range(TICK_RATE * 6):
		if not prey.alive:
			break

		hunters.tick(1.0 / float(TICK_RATE))
		ticks += 1

		if npc.is_alive():
			deepest = minf(deepest, body.global_position.distance_to(rock_at) - rock.z - reach)

	_check(
		not prey.alive,
		"it goes round the rock and eats the monster behind it inside six seconds",
		"%d ticks; the hunter at %s, the prey at %s"
			% [ticks, str(body.global_position) if npc.is_alive() else "-", str(prey_at)]
	)
	_check(
		deepest > -2.0,
		"and is never inside the rock on the way",
		"deepest %.1f into its face" % deepest
	)

	_drop_hunters(hunters)
	_drop(world)
	_done()


## [hunter-nav-1]: where the director may put a hunter.
##
## [b]Until 2026-09-27 the spawn points knew nothing about the level but its rocks[/b], and
## were seeded once from the world the server booted in: after a game change a director
## placed hunters on the last map's rings, and nothing refused a point behind a gauntlet
## harbour's fence — the refuge the corridor promises the players furthest behind. Now
## every point is out of the rocks at the biggest hunter's size, not in a harbour, and on
## the biggest floor that size can move about in, and the points follow the layout.
##
## The pocket half is checked independently of [method HungryLayout.main_region], which
## chose the points: one [method HungryLayout.reach] flood from the first point, which has
## to reach most of the floor, and no other point among what it stranded.
func _test_where_a_hunter_appears() -> void:
	_section("where a hunter may appear")

	var radius := HungryHunters.largest_radius()

	for mode: StringName in [&"classic", &"frenzy", &"gauntlet", &"warrens", &"reef", &"shallows"]:
		var preset := HungryPreset.for_id(mode)
		var bounds := Rect2(-preset.world_size * 0.5, preset.world_size)
		var layout := HungryLayout.for_id(preset.layout, bounds)
		var started := Time.get_ticks_usec()
		var points := HungryHunters.spawn_points_for(layout, bounds)
		var ms := float(Time.get_ticks_usec() - started) / 1000.0
		var bad := PackedStringArray()
		var stranded := {}
		var sweep := {}

		if not points.is_empty() and not layout.is_empty():
			sweep = layout.reach(bounds, points[0], radius)

			for at: Vector2 in sweep["stranded"]:
				stranded[Vector2i(at.floor())] = true

			if int(sweep["reached"]) * 2 <= int(sweep["free"]):
				bad.append("the first point reaches %d of %d" % [sweep["reached"], sweep["free"]])

		for at in points:
			if not bounds.grow(-radius + 0.5).has_point(at):
				bad.append("%s off the floor" % str(at))
			elif layout.blocked(at, radius - 0.5):
				bad.append("%s in a rock" % str(at))
			elif layout.harbour_of(at, bounds) >= 0:
				bad.append("%s in a harbour" % str(at))
			elif not layout.is_empty():
				# The reach grid's cell centres, 24 apart: a point is stranded when the cell
				# it stands in is.
				var cell := (at - bounds.position) / 24.0
				var centre_of := bounds.position + (cell.floor() + Vector2(0.5, 0.5)) * 24.0

				if stranded.has(Vector2i(centre_of.floor())):
					bad.append("%s in a pocket" % str(at))

		print("        %s: %d of 36 ring points kept for a radius of %.1f (%.0f ms)"
			% [mode, points.size(), radius, ms])
		_check(
			points.size() >= 12 and bad.is_empty(),
			"%s: every spawn point is on the floor, out of the rocks and harbours, and nowhere a lurker cannot leave"
				% mode,
			"%d points; %s" % [points.size(), ", ".join(bad.slice(0, 4))]
		)

	# The two refusals, asked directly: a check over the seeded points alone cannot fire on
	# a harbour or a pocket no ring point happens to fall in today.
	var g_bounds := Rect2(-HungryPreset.gauntlet().world_size * 0.5, HungryPreset.gauntlet().world_size)
	var gauntlet := HungryLayout.for_id(HungryLayout.SLALOM, g_bounds)
	var post := gauntlet.blocks[gauntlet.chains[0].x + 1]
	var behind := Vector2((g_bounds.position.x + post.x - post.z) * 0.5, post.y)
	var g_region := gauntlet.main_region(g_bounds, radius)
	_check(
		not gauntlet.blocked(behind, radius) and gauntlet.harbour_of(behind, g_bounds) == 0
			and HungryLayout.in_region(g_region, g_bounds, behind)
			and not HungryHunters.spawnable(gauntlet, g_bounds, behind, g_region),
		"a point behind the west harbour's fence, clear of every post and reachable, is refused",
		"at %s" % str(behind)
	)

	var w_bounds := Rect2(-HungryPreset.warrens().world_size * 0.5, HungryPreset.warrens().world_size)
	var warrens := HungryLayout.for_id(HungryLayout.WARRENS, w_bounds)
	var den_limit := warrens.ring_gates(1)[0] * 0.5
	var den := w_bounds.get_center()
	var too_big := warrens.main_region(w_bounds, den_limit + 8.0)
	var lurker := warrens.main_region(w_bounds, radius)
	_check(
		not HungryHunters.spawnable(warrens, w_bounds, den, too_big)
			and HungryHunters.spawnable(warrens, w_bounds, den, lurker),
		"the den's middle is refused to a radius 8 over its gate's half-width (%.0f), and allowed to a lurker's (%.1f)"
			% [den_limit, radius]
	)

	# A game change: the hunters are set up on one world and handed another, as
	# [HungryModule] does. The next tick has to seed the new level's points.
	var first := _make_world(HungryPreset.frenzy(), SEED + 331)
	var hunters := HungryHunters.new()
	hunters.name = "Hunters"
	add_child(hunters)
	var _ready := hunters.setup(true, first)
	hunters.tick(1.0 / float(TICK_RATE))
	var before := hunters.director.spawn_points.size()
	var second := _make_world(HungryPreset.gauntlet(), SEED + 332)
	hunters.world = second
	hunters.spawner.clear_all()
	hunters.tick(1.0 / float(TICK_RATE))
	var outside := 0

	for point in hunters.director.spawn_points:
		var at := DotNpcInstance.from_plane(point)

		if not second.arena.bounds.has_point(at) or second.layout.harbour_of(at, second.arena.bounds) >= 0:
			outside += 1

	var expected := HungryHunters.spawn_points_for(second.layout, second.arena.bounds).size()
	_check(
		outside == 0 and hunters.director.spawn_points.size() == expected,
		"a game change from frenzy to the gauntlet re-seeds the points on the corridor (%d -> %d)"
			% [before, hunters.director.spawn_points.size()],
		"%d outside the corridor or in a harbour; %d expected" % [outside, expected]
	)

	_drop_hunters(hunters)
	_drop(first)
	_drop(second)
	_done()


## [hunter-nav-1]'s size question, measured: one navigation graph serves every hunter kind,
## laid at the smallest's clearance (40). Does it hold a lurker at a gate?
##
## [b]Not on any map there is, because a lurker fits every gate.[/b] The item was written
## for a lurker 480 across — that is a MONSTER of 900 mass on this game's curve (radius
## 8 √mass) — and a hunter is drawn and pushed out at `4 √(mass / π)`, 67.7 for a lurker,
## 135 across, against a narrowest gate of 201 (a harbour door) and 202 (the den). So the
## shared graph only ever leads it along a face a little closer than it can stand, and the
## push-out slides it. Driven through both of the narrowest gates on the maps, it gets
## there; the stalker's time over the same arrangement is printed beside it.
func _test_a_lurker_on_the_shared_graph() -> void:
	_section("a lurker on the shared graph")

	var widest := HungryHunters.radius_of(&"lurker") * 2.0
	print("        a lurker is %.0f across; the narrowest gates are a harbour door and the den's" % widest)

	for arrangement in [&"den", &"harbour"]:
		var budget := TICK_RATE * 15
		var runs := {}

		for kind: StringName in [&"stalker", &"lurker"]:
			runs[kind] = _hunt_through(arrangement, kind, budget)

		var lurker: Dictionary = runs[&"lurker"]
		var stalker: Dictionary = runs[&"stalker"]
		print("        %s: stalker %d ticks, lurker %d ticks (%d of them held against a rock), gate %.0f"
			% [arrangement, stalker["ticks"], lurker["ticks"], lurker["held"], lurker["gate"]])
		_check(
			bool(lurker["eaten"]),
			"through the %s gate (%.0f): a lurker following the shared graph eats a monster behind it inside 15 s"
				% [arrangement, lurker["gate"]],
			"%d ticks, %d held; the lurker at %s, the prey at %s"
				% [lurker["ticks"], lurker["held"], str(lurker["at"]), str(lurker["prey"])]
		)

	_done()


## One hunt through the narrowest gate of [param arrangement]: `den` is the warrens' den,
## the hunter in the moat on a diagonal behind a den rock and the prey in the middle;
## `harbour` is the gauntlet's west fence, the hunter in front of the middle post and the
## prey behind it. Returns ticks, whether it ate, and how many ticks it moved less than a
## fifth of its speed while chasing ("held").
func _hunt_through(arrangement: StringName, kind: StringName, budget: int) -> Dictionary:
	var preset := HungryPreset.warrens() if arrangement == &"den" else HungryPreset.gauntlet()
	var world := _make_world(preset, SEED + 341)
	world.add_player(1, "Ada")
	_settle(world)
	var layout := world.layout
	var bounds := world.arena.bounds
	var centre := bounds.get_center()
	var reach := HungryHunters.radius_of(kind)
	var prey_at := centre
	var hunter_at := centre
	var gate := 0.0

	if arrangement == &"den":
		var rock := layout.blocks[layout.rings[1].x]
		var rock_at := Vector2(rock.x, rock.y)
		var out := (rock_at - centre).normalized()
		hunter_at = rock_at + out * (rock.z + reach + 60.0)
		gate = layout.ring_gates(1)[0]
	else:
		var post := layout.blocks[layout.chains[0].x + 1]
		prey_at = Vector2((bounds.position.x + post.x - post.z) * 0.5, post.y)
		hunter_at = Vector2(post.x + post.z + 400.0, post.y)
		gate = bounds.size.y * 0.5 * HungryLayout.HARBOUR_DOOR

	world.spawn(1, prey_at)
	_run_ticks(world, 2)
	var prey := world.monster_for(1)

	var hunters := HungryHunters.new()
	hunters.name = "Hunters"
	add_child(hunters)
	var _ready := hunters.setup(true, world)
	hunters.tick(1.0 / float(TICK_RATE))
	var npc := hunters.spawner.spawn_2d(kind, hunter_at)
	var out := {"eaten": false, "ticks": 0, "held": 0, "gate": gate, "at": hunter_at, "prey": prey_at}

	if npc == null or prey == null or not prey.alive:
		_drop_hunters(hunters)
		_drop(world)
		return out

	var body := npc.node as Node2D
	var speed := float(npc.def.meta.get("speed", 0.0))
	var step := 1.0 / float(TICK_RATE)
	var last := body.global_position

	for _i in range(budget):
		if not prey.alive:
			break

		hunters.tick(step)
		out["ticks"] = int(out["ticks"]) + 1

		if npc.is_alive():
			var brain: Object = npc.brain

			if brain != null and brain.machine.current() == &"chase" \
					and body.global_position.distance_to(last) < speed * step * 0.2:
				out["held"] = int(out["held"]) + 1

			last = body.global_position

	out["eaten"] = not prey.alive
	out["at"] = body.global_position if npc.is_alive() else Vector2.INF
	out["prey"] = prey.centre() if prey.alive else prey_at
	_drop_hunters(hunters)
	_drop(world)
	return out


func _drop_hunters(hunters: Node) -> void:
	if hunters != null and is_instance_valid(hunters):
		remove_child(hunters)
		hunters.free()


## [reach-1]: every level, swept. Every gap passes what it is meant to pass, and nothing on
## the floor is out of a starting monster's reach.
##
## [b]Two questions every level check before this one answered for its own level by
## hand[/b] — the warrens' gate, the slalom's lanes, the reef's channels — and none of
## them could see a pocket: floor a spawn can land on and never leave, or food the scatter
## puts where nobody can eat it. So this asks every mode the same two things, off the
## geometry alone:
##
## - [b]Every gate passes a monster just under its width and refuses one just over.[/b]
##   [method HungryLayout.gates] finds every gap on the map — rock to rock and rock to
##   wall, anything with no third rock standing in its mouth — and
##   [method HungryLayout.gate_passes] floods each one inside its own box, so the only way
##   through is through. A gap a neighbouring rock has narrowed fails the first half; one
##   that is not actually the limit its width says fails the second.
## - [b]A starting monster can reach every sampled point of the floor from the wall.[/b]
##   And a monster at the winning mass is kept out only where the level means it to be:
##   the warrens' ring, and nowhere at all on the corridor or the reef, whose designs
##   promise the leader a way everywhere (the corridor's harbours are too shallow for a
##   leader to stand in, so they are not part of its floor; see the harbours section).
func _test_the_reach() -> void:
	_section("the reach of every level")

	var modes: Array[StringName] = [&"classic", &"frenzy", &"gauntlet", &"warrens", &"reef", &"shallows"]
	var covered := {}

	for mode in modes:
		covered[HungryPreset.for_id(mode).layout] = true

	var missing := PackedStringArray()

	for layout_id in HungryLayout.ids():
		if not covered.has(layout_id):
			missing.append(String(layout_id))

	_check(missing.is_empty(), "every layout is swept here", "not swept: %s" % ", ".join(missing))

	var slack := 8.0
	var rules := HungryContent.mass_rules()

	for mode in modes:
		var preset := HungryPreset.for_id(mode)
		var bounds := Rect2(-preset.world_size * 0.5, preset.world_size)
		var layout := HungryLayout.for_id(preset.layout, bounds)
		var start := rules.radius_for(HungryContent.START_MASS)
		var won := rules.radius_for(preset.win_mass)
		var wall := Vector2(bounds.position.x + won + 30.0, bounds.get_center().y)

		# The shallows' west wall is the SHALLOW one, behind five lines a leader cannot
		# cross, so a fill from there measures a band rather than the floor. From the
		# open water in front of the inlet instead.
		if preset.layout == HungryLayout.SHALLOWS:
			wall = _shallows_open_water(layout, bounds)

		# [b]Off the wall until a leader can stand there.[/b] The gauntlet's west end is a
		# harbour now, and this point is behind its middle post — inside the post for a
		# starting monster and shut to a leader — so a fill from it would measure one
		# pocket rather than the floor. Walked east until the winning radius is clear,
		# which is the wall point itself for every mode without a harbour.
		while layout.blocked(wall, won) and wall.x < bounds.end.x - won:
			wall.x += 24.0

		var small := layout.reach(bounds, wall, start)
		var stranded_small: PackedVector2Array = small["stranded"]
		_check(
			small["free"] > 0 and small["reached"] == small["free"],
			"%s: a starting monster reaches all of the floor" % mode,
			"%d of %d sampled points, %d stranded%s"
				% [small["reached"], small["free"], small["free"] - small["reached"],
					"" if stranded_small.is_empty() else ", first at %s" % stranded_small[0]]
		)
		print("        %s: %d of %d points at radius %.0f" % [
			mode, small["reached"], small["free"], start
		])

		var big := layout.reach(bounds, wall, won)
		var stranded_big: PackedVector2Array = big["stranded"]
		var big_note := "%d of %d at the winning radius %.0f" % [big["reached"], big["free"], won]
		print("        %s: %s" % [mode, big_note])

		if preset.layout == HungryLayout.WARRENS:
			# [b]The design since 2026-10-07 (Christian's call): a leader is not quartered.[/b]
			# The corner rocks stood on the diagonal 481 off each wall, which shut anything
			# over about 903 mass into one quarter of the perimeter lane. They stand against
			# the walls now, a pinwheel, with the lane going round their inner side.
			var ring_block: Vector3 = layout.blocks[layout.rings[0].x]
			var ring_reach := Vector2(ring_block.x, ring_block.y).distance_to(bounds.get_center())
			var outside_big := 0
			for point in stranded_big:
				if point.distance_to(bounds.get_center()) > ring_reach:
					outside_big += 1
			_check(
				outside_big == 0,
				"%s: a monster at the winning mass reaches the whole perimeter lane" % mode,
				"%d stranded outside the ring at radius %.0f; %s" % [outside_big, won, big_note]
			)

			# [b]The original corners are a variant now (`hungry_warrens_corners quartered`),
			# and they still do what they did:[/b] whoever the ring shuts out has the whole
			# lane, and a leader is held in a quarter of it unless it splits.
			var quartered := HungryLayout.for_id(&"warrens:quartered", bounds)
			var corner_limit := INF

			for gate in quartered.gates(bounds):
				var a: int = gate["a"]
				var b: int = gate["b"]
				var corner_first := HungryLayout.RING_COUNT

				if (a >= corner_first and a < corner_first + 4) or (b >= corner_first and b < corner_first + 4):
					corner_limit = minf(corner_limit, float(gate["width"]) * 0.5)

			# Two grid cells under the limit: the sweep samples every 24 units, and the corner
			# gaps leave 17 to spare at 8 under, which a grid can step straight over.
			var lane := quartered.reach(bounds, wall, corner_limit - 48.0)
			var outside := 0

			for point in lane["stranded"]:
				if point.distance_to(bounds.get_center()) > ring_reach:
					outside += 1

			var held := 0
			for point in quartered.reach(bounds, wall, won)["stranded"]:
				if point.distance_to(bounds.get_center()) > ring_reach:
					held += 1

			var ring_admits := rules.mass_for(Array(quartered.ring_gates(0)).min() * 0.5)
			var lane_admits := rules.mass_for(corner_limit)
			_check(
				quartered.id == &"warrens:quartered" and outside == 0 and lane_admits > ring_admits * 1.5 and held > 0,
				"%s, quartered: whoever the ring shuts out has the whole lane, and a leader only a quarter of it" % mode,
				"whole up to %.0f mass (radius %.0f), the ring shuts out %.0f; %d stranded outside the ring below the limit; %d at the winning radius"
					% [lane_admits, corner_limit, ring_admits, outside, held]
			)
			print("        %s: open corners: %d stranded at the winning radius; quartered: the lane is quartered past %.0f mass" % [
				mode, stranded_big.size(), lane_admits
			])
		elif preset.layout == HungryLayout.SHALLOWS:
			# [b]The design, not a finding.[/b] A leader is shut out of every band behind
			# its tree line — the fourth line, whose 580 it does not fit — and of nothing
			# else. What it may not lose is floor in FRONT of that line.
			var in_front := 0

			for point: Vector2 in stranded_big:
				# The pools and the inlet are rooms in front of it, shut to a leader by design.
				if layout.shallows_band(point, bounds) >= HungryLayout.SHALLOWS_LINES - 1 \
						and not layout.in_pool(point, bounds) and not layout.in_inlet(point, bounds):
					in_front += 1

			_check(
				in_front == 0 and not stranded_big.is_empty(),
				"%s: a leader reaches everything in front of its tree line and nothing behind it" % mode,
				"%s; %d stranded in front of the line" % [big_note, in_front]
			)
		else:
			# The gauntlet's harbours do not show here, and that is measured rather than
			# missed: 296 deep behind the posts, they have no point a leader 480 across can
			# stand on, so they are not in its floor at all. What a door shuts out is asked
			# in the harbours section, at the size just over a door.
			_check(
				big["reached"] == big["free"],
				"%s: a leader can reach all of the floor too" % mode,
				big_note
			)

		if layout.is_empty():
			continue

		var gates := layout.gates(bounds)
		var shut := PackedStringArray()
		var leaky := PackedStringArray()
		var narrowest := INF

		for gate in gates:
			var width: float = gate["width"]
			narrowest = minf(narrowest, width)

			if width * 0.5 - slack > start and not layout.gate_passes(bounds, gate, width * 0.5 - slack):
				shut.append("%d-%d %.0f" % [gate["a"], gate["b"], width])

			if layout.gate_passes(bounds, gate, width * 0.5 + slack):
				leaky.append("%d-%d %.0f" % [gate["a"], gate["b"], width])

		print("        %s: %d gates, narrowest %.0f" % [mode, gates.size(), narrowest])
		_check(
			gates.size() > 0 and shut.is_empty(),
			"%s: every one of its %d gates passes a monster %.0f under its width" % [
				mode, gates.size(), slack * 2.0
			],
			"shut: %s" % ", ".join(shut)
		)
		_check(
			leaky.is_empty(),
			"%s: and refuses one %.0f over it" % [mode, slack * 2.0],
			"leaky: %s" % ", ".join(leaky)
		)

	_done()

## Food per unit of the floor that is left, MEASURED, for every mode with a level in it.
##
## [b]The arithmetic this replaces was backwards and a check agreed with it.[/b] The
## gauntlet's density check multiplied the target by the walkable fraction — the model of
## a cull that is a permanent loss — and the gauntlet's target had been raised to 790 by
## the same model. But [method HungryWorld._cull_blocked] takes a slot OUT of the field
## and the scatter tops the field back up to its target on the next ticks, so the target
## is what stands on the floor: 790 over the corridor's floor was 27% more food per unit
## than Frenzy, and the reef's 880 was 4.5% more than Classic. Warrens alone had it right,
## and the check and the preset agreeing with each other is exactly why nobody saw it.
##
## So this section counts the food that is alive in a settled world and divides it by the
## floor, which is the only version of the number a player eats. Each mode is compared
## with the empty square it was built to match.
func _test_food_on_the_floor() -> void:
	_section("food on the floor that is left")

	# The control each level claims to match, as its own preset comment argues it.
	var controls := {
		&"gauntlet": HungryPreset.frenzy(),
		&"warrens": HungryPreset.classic(),
		&"reef": HungryPreset.classic(),
		&"shallows": HungryPreset.classic(),
	}

	# Every layout is somebody's, so a sixth mode with rocks in it cannot arrive without
	# being asked this. A check named after the levels that existed when it was written is
	# the shape this project keeps finding.
	var covered_layouts := {}

	for mode in controls:
		covered_layouts[HungryPreset.for_id(mode).layout] = true

	var missing := PackedStringArray()

	for layout_id in HungryLayout.ids():
		if not covered_layouts.has(layout_id):
			missing.append(String(layout_id))

	_check(
		missing.is_empty(),
		"every layout is measured here against the square it claims to match",
		"not measured: %s" % ", ".join(missing)
	)

	for mode in controls:
		var preset := HungryPreset.for_id(mode)
		var control: HungryPreset = controls[mode]
		var world := _make_world(preset, SEED + 199)
		world.add_player(1, "Ada")
		_settle(world)
		_run_ticks(world, TICK_RATE * 2)

		var area := world.arena.bounds.size.x * world.arena.bounds.size.y
		var floor_area := area - world.layout.covered_area()
		var here := float(world.field.food.alive_count()) / floor_area
		var there := float(control.food_target) / (control.world_size.x * control.world_size.y)

		_check(
			absf(here / there - 1.0) < 0.03,
			"%s has %s's food per unit of open floor" % [mode, control.id],
			"%.1f per million against %.1f: %d alive on %.2f million, %.1f%% under rock"
				% [here * 1.0e6, there * 1.0e6, world.field.food.alive_count(),
					floor_area / 1.0e6, (1.0 - floor_area / area) * 100.0]
		)

		_drop(world)

	_done()


func _test_determinism() -> void:
	_section("determinism")

	# Two worlds, the same seed, the same commands. The property everything else in the
	# netcode rests on: a client predicting a move and a server re-running it have to
	# reach the same answer, and nothing else in this project can check that.
	var first := _make_world()
	var second := _make_world()

	for world in [first, second]:
		world.add_player(1, "Ada")
		world.add_player(2, "Bo")
		_settle(world)
		world.spawn(1, Vector2(-200.0, 0.0))
		world.spawn(2, Vector2(200.0, 60.0))

	var commands: Array[Dictionary] = []

	for step in range(240):
		var angle := float(step) * 0.11
		commands.append({
			1: _aim_at(
				Vector2.ZERO,
				Vector2.from_angle(angle) * 400.0,
				Dot2DCommand.BUTTON_SPLIT if step == 90 else 0
			),
			2: _aim_at(Vector2.ZERO, Vector2.from_angle(-angle) * 300.0),
		})

	for step in range(commands.size()):
		first.tick(commands[step])
		second.tick(commands[step])

	var exact := true
	var worst := 0.0

	for piece in first.pieces():
		var twin := second.piece_for(piece.id)

		if twin == null:
			exact = false
			break

		worst = maxf(worst, piece.position().distance_to(twin.position()))
		exact = exact and piece.position() == twin.position()

	_check(
		exact,
		"two worlds replaying the same commands are bit-identical (%.6f apart)" % worst
	)
	_check(
		first.field.alive_count() == second.field.alive_count(),
		"and ate exactly the same food"
	)

	# And it must not pass for a world that ignores its inputs.
	var third := _make_world()
	third.add_player(1, "Ada")
	third.add_player(2, "Bo")
	_settle(third)
	third.spawn(1, Vector2(-200.0, 0.0))
	third.spawn(2, Vector2(200.0, 60.0))

	for step in range(commands.size()):
		var changed := commands[step].duplicate()

		if step == 120:
			changed[1] = _aim_at(Vector2.ZERO, Vector2.LEFT * 400.0)

		third.tick(changed)

	var differs := false

	for piece in first.pieces():
		var twin := third.piece_for(piece.id)

		if twin == null or piece.position() != twin.position():
			differs = true
			break

	_check(differs, "and a different command produces a different world")

	_drop(first)
	_drop(second)
	_drop(third)


# --- The whole thing -------------------------------------------------------
	_done()

## [bot-drive-1]: what a bot actually travels at, against the speed the game gives it.
##
## [b]In the 3D games a bot held forward and jump and crawled at the air cap.[/b] This is a
## 2D game and has no jump; its motor is the cell-eating genre's, and the speed a monster is GIVEN is
## `max_speed` × `speed_scale(mass)` × its trait and effects — the ground speed below,
## worked per piece per tick. What it GETS is that times how hard the pointer is pushed:
## the wish ramps from nothing at `dead_reach` (7) to full at `full_speed_reach` (105), so
## pointing at a crumb 50 units away asks for half speed. [HungryBot] points at what it
## wants — the pointer on the crumb — so a bot slows as it arrives at every crumb, which is
## what a person steering with a mouse does too.
##
## So two numbers, both printed beside their assertion: a monster held at full reach
## travels at its ground speed (the level sections drive with [method _full_reach] for
## exactly this reason, and print what they covered), and eight bots playing a round
## travel at 0.94 of it (2026-09-27): unlike the 3D games', hungario's bots do cover
## ground at the speed the game gives them.
func _test_what_a_bot_travels_at() -> void:
	_section("what a bot actually travels at")

	# --- The control: full reach, one direction, an empty box ------------------
	var world := _make_world(HungryPreset.frenzy(), SEED + 401)
	world.add_player(1, "Ada")
	_settle(world)
	var bounds := world.arena.bounds
	world.spawn(1, bounds.get_center() - Vector2(bounds.size.x * 0.4, 0.0))
	_run_ticks(world, 2)
	var monster := world.monster_for(1)
	var held := _travel_ratio(world, {1: null}, TICK_RATE * 3, TICK_RATE,
		func(m: HungryMonster, _t: int) -> Dot2DCommand:
			return _full_reach(m.centre(), m.centre() + Vector2.RIGHT * 1000.0))
	print("        held at full reach: %.1f u/s against a ground speed of %.1f (%.3f), mass %.0f"
		% [held["actual"], held["ground"], held["ratio"], monster.mass() if monster != null else 0.0])
	_check(
		held["samples"] > 0 and absf(float(held["ratio"]) - 1.0) < 0.02,
		"a monster held at full reach travels at its ground speed (%.3f of it)" % held["ratio"],
		"%d samples" % held["samples"]
	)
	_drop(world)

	# --- Eight bots, a real round ----------------------------------------------
	world = _make_world(HungryPreset.classic(), SEED + 402)

	for id in range(1, 9):
		world.add_player(id, "Bot %d" % id)

	_settle(world)
	var ids := {}

	for id in range(1, 9):
		ids[id] = null

	var bots := _travel_ratio(world, ids, TICK_RATE * 30, TICK_RATE * 2,
		func(m: HungryMonster, t: int) -> Dot2DCommand:
			return HungryBot.command_for(world, m, t))
	print(("        eight bots over 28 s of classic: %.1f u/s against a ground speed of %.1f (%.3f); "
		+ "%.0f%% of piece-ticks at 95%% or more of it, %.0f%% under half")
		% [bots["actual"], bots["ground"], bots["ratio"], bots["full"] * 100.0, bots["crawl"] * 100.0])
	# [b]Measured 2026-09-27: 0.937, 65% of piece-ticks at ground speed, 3% under half.[/b]
	# The shortfall is the pointer landing on a crumb, by design; most of a bot's travel
	# is toward something further than 105 away. The floor is 0.85 and half the ticks at
	# ground speed: the 3D family's shape — a bot whose command asks for almost nothing
	# whatever it wants — fails both. Armed with the bot's reach capped at 40: 0.42, 1%.
	_check(
		bots["samples"] > 0 and float(bots["ratio"]) > 0.85 and float(bots["full"]) > 0.5,
		"eight bots travel at %.2f of their ground speed, %.0f%% of the time at all of it"
			% [bots["ratio"], bots["full"] * 100.0],
		"%d samples" % bots["samples"]
	)
	_drop(world)
	_done()


## Ticks [param world] for [param ticks], each monster in [param ids] steered by
## [param steer], and from [param warmup] on compares how far every piece moved in a tick
## with how far its ground speed would take it. Returns the mean actual and ground speeds,
## their ratio, and the fraction of piece-ticks at 95% or more and under 50%.
##
## A piece that appeared, vanished or jumped more than twice its ground step — a split, a
## merge, being eaten, a respawn — is not a sample: that is not travel.
func _travel_ratio(world: HungryWorld, ids: Dictionary, ticks: int, warmup: int, steer: Callable) -> Dictionary:
	var step := 1.0 / float(TICK_RATE)
	var rules := world.tunables.mass_rules
	var actual := 0.0
	var ground := 0.0
	var samples := 0
	var full := 0
	var crawl := 0

	for tick in range(ticks):
		var before := {}
		var allowed := {}
		var commands := {}

		for monster in world.monsters():
			if not ids.has(monster.id) or not monster.alive:
				continue

			commands[monster.id] = steer.call(monster, tick)

			for piece in monster.pieces:
				before[piece.id] = piece.position()
				allowed[piece.id] = world.tunables.max_speed * rules.speed_scale(piece.mass()) \
					* monster.speed_multiplier(tick)

		world.tick(commands)

		if tick < warmup:
			continue

		for monster in world.monsters():
			if not ids.has(monster.id) or not monster.alive:
				continue

			for piece in monster.pieces:
				if not before.has(piece.id):
					continue

				var moved: float = piece.position().distance_to(before[piece.id]) / step
				var limit: float = allowed[piece.id]

				if limit <= 0.0 or moved > limit * 2.0:
					continue

				actual += moved
				ground += limit
				samples += 1

				if moved >= limit * 0.95:
					full += 1
				elif moved < limit * 0.5:
					crawl += 1

	var n := float(maxi(samples, 1))
	return {
		"actual": actual / n, "ground": ground / n,
		"ratio": actual / ground if ground > 0.0 else 0.0,
		"full": float(full) / n, "crawl": float(crawl) / n, "samples": samples,
	}


func _test_full_round() -> void:
	_section("a whole round, eight bots")

	# Frenzy, because a classic round to 2400 mass is a very long time in ticks and this
	# is a smoke test rather than a soak.
	var world := _make_world(HungryPreset.frenzy(), SEED + 7)
	var ended := [false]
	var winner := [""]

	world.match_node.round_ended.connect(
		func(_round_number: int, _winner: int, _outcome: DotMatchRules.Outcome) -> void:
			ended[0] = true
			var leader := world.match_node.scoreboard.leader()
			winner[0] = leader.display_name if leader != null else ""
	)

	for id in range(1, 9):
		world.add_player(id, "Bot %d" % id)

	_settle(world)

	var burst_total := [0]
	var throws := [0]
	var deaths := [0]

	world.monster_burst.connect(func(_p: int, _b: int, c: int) -> void:
		burst_total[0] += c
	)
	world.projectile_thrown.connect(func(_s: HungryProjectile) -> void:
		throws[0] += 1
	)
	world.player_died.connect(func(_p: int, _k: int) -> void: deaths[0] += 1)

	var ticks := 0
	var limit := TICK_RATE * 240

	while not ended[0] and ticks < limit:
		var commands: Dictionary = {}

		for monster in world.monsters():
			commands[monster.id] = HungryBot.command_for(world, monster, ticks)

		world.tick(commands)
		ticks += 1

	_check(ended[0], "the round ends (%d ticks, %.0fs)" % [ticks, float(ticks) / TICK_RATE])
	_check(winner[0] != "", "and there is a winner: %s" % winner[0])

	var top := world.leaderboard(1)
	_check(
		not top.is_empty() and top[0].mass() > HungryContent.START_MASS * 5.0,
		"who actually grew (%.0f)" % (top[0].mass() if not top.is_empty() else 0.0)
	)

	_check(deaths[0] > 0, "monsters ate each other (%d deaths)" % deaths[0])
	_check(throws[0] > 0, "and threw things (%d)" % throws[0])
	_check(burst_total[0] > 0, "and burst each other (%d pieces)" % burst_total[0])

	# The two invariants that hold whatever happened.
	_check(_furthest_edge(world) <= 0.5, "nothing ended up outside the world")

	var stale := 0

	for grid_id in world.arena.grid.ids():
		if grid_id >= HungryField.PIECE_ID_LIMIT:
			if not world.field.food.is_alive(HungryField.index_of(grid_id)) \
					and HungryField.kind_of(grid_id) == HungryField.Kind.FOOD:
				stale += 1
		elif world.piece_for(grid_id) == null:
			stale += 1

	_check(stale == 0, "and the grid holds nothing that no longer exists (%d)" % stale)

	var over_cap := 0

	for monster in world.monsters():
		if monster.piece_count() > world.tunables.mass_rules.max_pieces:
			over_cap += 1

	_check(over_cap == 0, "and nobody exceeded the piece cap")

	print("")
	for line in world.describe_lines():
		print("  %s" % line)

	_drop(world)


# --- The rider -------------------------------------------------------------
	_done()

func _test_rider() -> void:
	_section("the rider")

	var schema := HungryContent.avatar_schema()
	var valid := schema.validate_schema()

	_check(valid.ok, "the rider schema is legal", str(valid.error))

	# A server decides whether an avatar is legal from ids alone. If this ever needs a
	# load(), a ResourceLoader.exists() or a scene path, that is the thing to push back
	# on — it is the whole reason an avatar is a document.
	var avatar := HungryContent.default_avatar(7)
	var checked := schema.validate(avatar, DotAvatarEntitlements.everything())
	_check(checked.ok, "and a default avatar passes it", str(checked.error))
	_check(
		avatar.has_slot(&"body"),
		"with the required slot filled, so nobody is invisible"
	)

	# Deterministic on the id: a client that has not been sent somebody's avatar draws
	# the same guest as everybody else rather than a different one per machine.
	_check(
		HungryContent.default_avatar(7).digest() == avatar.digest(),
		"and the same id always produces the same one"
	)
	_check(
		HungryContent.default_avatar(8).digest() != avatar.digest(),
		"while a different id does not"
	)

	# An entitlement set of nothing must still dress somebody. Every part that is not
	# free is refused, and conform fills the required slot from its default.
	var greedy := DotAvatar.make(schema.id)
	greedy.set_part(&"body", &"rider_spike")
	greedy.set_part(&"hat", &"hat_crown")

	var conformed := schema.conform(greedy, DotAvatarEntitlements.none())
	_check(conformed.ok, "conform repairs an avatar nobody owns", str(conformed.error))
	_check(
		greedy.part_in(&"body") == &"rider_pip",
		"back to the free body (%s)" % greedy.part_in(&"body")
	)
	_check(
		greedy.part_in(&"hat") != &"hat_crown",
		"and drops the hat they do not own"
	)

	# The rig. Parts resolve through HungryContentSource, which prefers a mounted pack and
	# falls back to what shipped in the build — which is the path taken here, because
	# nothing has mounted anything.
	var catalogue := DotAvatarCatalogue.new()
	var source := HungryContentSource.new()
	source.install(catalogue)

	var dressed := DotAvatar.make(schema.id)
	dressed.set_part(&"body", &"rider_blob")
	dressed.set_part(&"hat", &"hat_cap")
	dressed.set_colour(&"body", 0, Color(0.9, 0.3, 0.4))

	var rider := HungryRider.make(schema, catalogue)
	add_child(rider)
	rider.wear(dressed)

	_check(
		rider.built_slots() == 2,
		"both parts build from the content in this build (%d)" % rider.built_slots()
	)
	_check(rider.drawn_slots() == 0, "so none of them has to be drawn")
	_check(
		source.mount_prefix == "",
		"and none of it came from a pack, because none is mounted"
	)

	# The whole contract between this game and its content: a Node2D that answers
	# `hungry_dress`. A part that does not is still shown, which is why this is checked
	# rather than assumed.
	var body: Node2D = rider._built.get(&"body")
	_check(
		body != null and body.has_method(&"hungry_dress"),
		"the built part takes its colours through hungry_dress"
	)
	_check(
		body != null and (body.get("tint_a") as Color).is_equal_approx(
			DotAvatar.quantise(Color(0.9, 0.3, 0.4))
		),
		"and wears the colour the document asked for"
	)

	# Resizing is called every frame for every player on screen, so it must be cheap and
	# it must actually reach the part.
	rider.resize(64.0)
	_check(
		body != null and is_equal_approx(float(body.get("unit")), 64.0),
		"and follows the monster as it grows"
	)

	# Wearing the same document twice must be free.
	var before := rider.get_child_count()
	rider.wear(dressed)
	_check(
		rider.get_child_count() == before,
		"re-wearing the same document rebuilds nothing"
	)

	# A part with no content anywhere falls back to being drawn rather than to nothing.
	# A player you cannot see is a competitive advantage.
	var ghost := DotAvatar.make(schema.id)
	ghost.set_part(&"body", &"rider_pip")
	ghost.set_part(&"trail", &"trail_ember")

	var bare := DotAvatarCatalogue.new()
	bare.resolver = func(_part: DotAvatarPart) -> String: return ""

	var drawn := HungryRider.make(schema, bare)
	add_child(drawn)
	drawn.wear(ghost)

	_check(
		drawn.built_slots() == 0 and drawn.drawn_slots() == 2,
		"a rider whose content is missing is drawn instead (%d built, %d drawn)"
			% [drawn.built_slots(), drawn.drawn_slots()]
	)

	remove_child(drawn)
	drawn.free()
	remove_child(rider)
	rider.free()


# --- The interface ---------------------------------------------------------
	_done()

func _test_interface() -> void:
	_section("the interface")

	var world := _make_world()
	world.add_player(1, "Ada")
	_settle(world)

	var ui_config := DotUiConfig.new()
	ui_config.allow_pause = false

	var stack := DotScreenStack.new()
	stack.name = "Screens"
	stack.config = ui_config
	stack.load_layered_config = false
	stack.register_service = false
	stack.manage_mouse = false
	add_child(stack)
	stack.setup()

	var hud := HungryHud.new()
	hud.name = "Hud"
	hud.config = ui_config
	add_child(hud)
	hud.build(world, null, 1)
	hud.bind_stack(stack)

	_check(hud.mass_bar != null, "the HUD builds its widgets")
	_check(hud.minimap != null, "including a minimap")

	# HUD text over the pale sky is outlined, or it is a smudge ("20 mass" was, from the
	# look pass until 2026-10-11). The mass number is a Label for that reason: DotStatBar
	# draws its own text with no outline.
	_check(
		hud.mass_label != null and not hud.mass_bar.show_text,
		"the mass number is an outlined Label, not the bar's own text"
	)
	_check(
		hud.mass_label.get_theme_constant(&"outline_size") >= 3
			and hud.carry_label.get_theme_constant(&"outline_size") >= 3,
		"the HUD's labels carry an outline (%d)" % hud.mass_label.get_theme_constant(&"outline_size")
	)
	_check(
		hud.mass_label.get_theme_color(&"font_outline_color").get_luminance() < 0.3,
		"and the outline is dark"
	)
	_check(hud.feed.outline_size >= 3, "the feed is outlined too (%d)" % hud.feed.outline_size)

	hud.refresh_leaderboard()
	_check(
		hud.leaderboard.row_count() == 1,
		"and a leaderboard with a row in it (%d)" % hud.leaderboard.row_count()
	)

	# The feed takes coloured fragments, which is all dot-ui knows about this game.
	hud.say("hello")
	hud.chat({"name": "Bo", "text": "hi"})
	hud.note(HungryEvents.Kind.DIED, {"first": 1, "second": 0, "extra": 0})
	_check(hud.feed.line_count() >= 3, "the feed takes lines (%d)" % hud.feed.line_count())

	# Nothing of this game's is on the stack now: the pause, settings, controls and loadout
	# screens are dot-menu's Escape menu (HungrySettings), chat left the stack long before, when
	# it became a `DotChatWindow`, and the Tab board is dot-menu's own, held by the platform.
	_check(stack.registered_ids().is_empty(), "nothing of this game's is on the stack (%d)" % stack.registered_ids().size())

	# The Tab board: the world's monsters, in the world's order, dressed by the game and held
	# open by the platform while Tab is down (opened by hand here).
	var board := DotMenuScoreboard.new()
	add_child(board)
	HungryMenus.dress_board(board, world, null)
	board.source = HungryMenus.solo_snapshot
	board.open()
	var drawn: Array = board.rows()
	_check(board.is_open() and drawn.size() == world.leaderboard(20).size()
		and int(drawn[0].get("rank", 0)) == 1 if not drawn.is_empty() else false,
		"the Tab board draws every monster, ranked as the world ranks them", str(drawn))
	board.close()
	_check(not board.is_open(), "and goes when it is closed")
	board.queue_free()

	# The Loadout page offers what the schema and this player's entitlements allow, and
	# nothing else. A page that filtered on its own would drift from the server the first
	# time an unlock changed; one the server trusted would be a client choosing its own
	# stats.
	var lp := HungryMenus.loadout_page(null)
	var lp_schema := HungryContent.loadout_schema()
	var lp_offered := true
	for slot in lp_schema.ordered_slots():
		var lp_allowed := lp_schema.choices_for(slot.id, DotLoadoutEntitlements.none())
		lp_offered = lp_offered and (lp.page.find_row(StringName("loadout_%s" % slot.id)).options.size() == lp_allowed.size())
	_check(lp_offered, "the Loadout page offers exactly what the schema allows this player")
	var lp_sent: Array = []
	lp.on_chosen(func(l: DotLoadout) -> void: lp_sent.append(l))
	var lp_trait := lp.page.find_row(StringName("loadout_%s" % HungryContent.SLOT_TRAIT))
	var lp_other: Variant = lp_trait.options[-1][0] if lp_trait.options.size() > 1 else null
	if lp_other != null:
		lp_trait.setter.call(lp_other)
	_check(lp_other == null or (lp_sent.size() == 1 and (lp_sent[0] as DotLoadout).item_in(HungryContent.SLOT_TRAIT) == StringName(str(lp_other))),
		"and a choice is sent as it is made", str(lp_sent))
	_check(lp.summary().contains("speed"), "with what the trait does, in numbers", lp.summary())

	# The one readability affordance this genre cannot do without. Eating needs a ratio —
	# a quarter bigger — and a quarter of a difference in *area* is about 12% of a
	# difference in *width*, which nobody judges by eye under pressure. What the renderer
	# must not do is call something food that is merely smaller.
	var renderer := HungryRenderer.new()
	renderer.name = "Renderer"
	add_child(renderer)
	renderer.bind(world, null, 1)

	var rules := world.tunables.mass_rules
	var ours := 100.0

	_check(
		ours >= (ours / rules.eat_ratio - 1.0) * rules.eat_ratio,
		"something a quarter smaller is food"
	)
	_check(
		not (ours >= (ours * 0.9) * rules.eat_ratio),
		"and something merely smaller is not (%.2f ratio)" % rules.eat_ratio
	)
	_check(
		renderer.show_threat,
		"the rings are on by default, because judging it by eye is the failure mode"
	)

	remove_child(renderer)
	renderer.free()


	# Being eaten means having nothing at all — no pieces, no position, nowhere for a
	# camera to be. A camera left where you died is a black rectangle for three seconds
	# while the fight that killed you carries on somewhere else.
	world.add_player(2, "Bo")
	world.spawn(2, Vector2(300.0, 0.0))

	var me := world.monster_for(1)
	var them := world.monster_for(2)
	var watching := [0]

	var source := func() -> HungryMonster:
		var mine := world.monster_for(1)

		if mine != null and mine.alive:
			return mine

		var killer := world.monster_for(watching[0])
		return killer if killer != null and killer.alive else null

	_check(source.call() == me, "a living player watches themselves")

	for piece in me.pieces.duplicate():
		world.forget_piece(piece.id)

	watching[0] = 2

	_check(not me.alive, "and once eaten has nothing to watch from")
	_check(source.call() == them, "so they watch whoever ate them")

	hud.watching_source = source
	hud._refresh_status()
	_check(
		hud.status_label.text.contains(them.display_name),
		"and the HUD says whose eyes they are behind (%s)" % hud.status_label.text
	)

	var offered := HungryMenus.loadout_page(null).current()
	_check(
		offered.item_in(HungryContent.SLOT_TRAIT) != &"",
		"the Loadout page offers a trait to a player who owns nothing (%s)"
			% offered.item_in(HungryContent.SLOT_TRAIT)
	)
	_check(
		offered.item_in(HungryContent.SLOT_TRAIT) != HungryContent.TRAIT_GREEDY,
		"but not the one nobody has unlocked"
	)
	_check(
		DotLoadoutValidator.validate(
			offered, HungryContent.loadout_schema(), DotLoadoutEntitlements.none()
		).ok,
		"and what it produces is legal"
	)
	var unlocked := HungryMenus.loadout_page(null)
	unlocked.allow(DotLoadoutEntitlements.of([HungryContent.TRAIT_GREEDY_UNLOCK]))
	var greedy_offered := false
	for option in unlocked.page.find_row(StringName("loadout_%s" % HungryContent.SLOT_TRAIT)).options:
		greedy_offered = greedy_offered or option[0] == HungryContent.TRAIT_GREEDY
	_check(greedy_offered, "which appears once it is unlocked")

	# [b]Chat is no longer a screen on this stack.[/b] It was a modal `DotScreen` on Enter
	# with one line edit in it — the only chat box of its kind in the family, with no log,
	# no channels and no way to know whether anything else was carrying the conversation.
	# It is `DotChatWindow` now, tested in `headless_presentation` where the rest of the
	# client's interface is.
	_check(
		stack.screen(&"chat") == null,
		"chat is not a screen on the stack any more",
		"two chat boxes in one game is the shape this tree pays most for"
	)

	var chat := DotChatWindow.new()
	chat.register_actions = false
	add_child(chat)

	var said := [""]
	chat.submitted.connect(func(text: String, _c: StringName) -> void: said[0] = text)

	chat.open()
	_check(chat.is_open(), "the chat line opens")
	chat.entry().text = "  well then  "
	chat.entry().text_submitted.emit(chat.entry().text)
	_check(said[0] == "well then", "and submits trimmed text (%s)" % said[0])
	_check(not chat.is_open(), "and closes itself")
	chat.queue_free()

	# The on-screen buttons. Forced on, because a headless run has no touchscreen and a
	# control nothing exercises is a control that breaks quietly.
	var touch := HungryTouch.make()
	add_child(touch)

	var sampler := HungryInput.measuring(
		func() -> Variant: return world.monster_for(1), null
	)
	sampler.touch = touch
	add_child(sampler)

	_check(
		not sampler.sample().is_pressed(Dot2DCommand.BUTTON_SPLIT),
		"nothing is pressed to start with"
	)

	touch.split_button.button_down.emit()
	_check(
		sampler.sample().is_pressed(Dot2DCommand.BUTTON_SPLIT),
		"the split button reaches the command"
	)
	touch.split_button.button_up.emit()
	_check(
		not sampler.sample().is_pressed(Dot2DCommand.BUTTON_SPLIT),
		"and lets go again"
	)

	# The throw button is disabled with nothing to throw, and names what it will throw
	# when there is — throwing a lure at somebody chasing you is a wasted charge.
	_check(touch.throw_button.disabled, "the throw button is disabled while empty")
	touch.show_carried(PackedStringArray(["pepper"]))
	_check(not touch.throw_button.disabled, "and enabled once something is carried")
	_check(
		touch.throw_button.text.to_lower().contains("pepper"),
		"naming it (%s)" % touch.throw_button.text
	)

	touch.throw_button.button_down.emit()
	_check(
		sampler.sample().is_pressed(Dot2DCommand.BUTTON_ACTION),
		"and it reaches the command too"
	)
	touch.throw_button.button_up.emit()

	remove_child(sampler)
	sampler.free()
	remove_child(touch)
	touch.free()
	remove_child(hud)
	hud.free()
	remove_child(stack)
	stack.free()
	_drop(world)


# --- Sound -----------------------------------------------------------------

## Every noise this game makes is arithmetic, so all of it is checkable without a speaker.
##
## [b]That is the point of baking rather than streaming.[/b] A generator filling buffers on
## the main thread can only be judged by listening to it; a bank of streams built by a pure
## function is bytes, and bytes are something a headless run can assert about.
	_done()
func _test_sound() -> void:
	_section("sound")

	var blip := HungrySound.bake(520.0, 760.0, 0.07, 0.35, 0.0)

	_check(blip != null, "a voice bakes")
	_check(
		blip.format == AudioStreamWAV.FORMAT_16_BITS and not blip.stereo,
		"as 16-bit mono"
	)
	_check(
		blip.mix_rate == HungrySound.RATE,
		"at %d Hz (%d)" % [HungrySound.RATE, blip.mix_rate]
	)

	var frames := blip.data.size() / 2
	_check(
		absi(frames - int(0.07 * float(HungrySound.RATE))) <= 1,
		"of the length it was asked for (%d frames)" % frames
	)

	# Silence is what a synthesiser that does nothing produces, and it is indistinguishable
	# from one that works until somebody puts headphones on.
	var peak := 0

	for index in range(frames):
		var low := blip.data[index * 2]
		var high := blip.data[index * 2 + 1]
		var value := low | (high << 8)

		if value >= 32768:
			value -= 65536

		peak = maxi(peak, absi(value))

	_check(peak > 2000, "and is not silence (peak %d of 32767)" % peak)

	# Deterministic, because the noise comes from a hash rather than from randf. Two
	# machines produce byte-identical banks, which is what makes this checkable at all.
	var again := HungrySound.bake(520.0, 760.0, 0.07, 0.35, 0.0)
	_check(again.data == blip.data, "and the same arguments bake the same bytes")

	var noisy := HungrySound.bake(150.0, 60.0, 0.42, 0.55, 0.85)
	_check(noisy.data != blip.data, "while different ones do not")

	# The envelope has to end at silence or every cue clicks when it stops.
	var tail := noisy.data.size()
	_check(
		noisy.data[tail - 1] == 0 and noisy.data[tail - 2] == 0,
		"a voice ends at silence rather than clicking"
	)

	# Bigger food is lower. It is the one mapping nobody has to be taught.
	_check(
		HungrySound.food_pitch(0) > HungrySound.food_pitch(3),
		"and a crumb is pitched above a haunch (%.2f vs %.2f)" % [
			HungrySound.food_pitch(0), HungrySound.food_pitch(3)
		]
	)

	var bank := HungrySound.make()
	add_child(bank)
	bank.build()

	_check(
		bank.baked() == HungrySound.Cue.size(),
		"every cue has a voice (%d of %d)" % [bank.baked(), HungrySound.Cue.size()]
	)
	_check(bank.voices() == HungrySound.VOICES, "and there is a pool to play them in")

	# Playing must be safe with no audio device at all, which is what a headless server,
	# a CI run and a muted browser tab all are.
	bank.play(HungrySound.Cue.EAT, 1.2)
	bank.muted = true
	bank.play(HungrySound.Cue.DIE)
	_check(true, "and playing one without a device does not fail")

	remove_child(bank)
	bank.free()


# --- Ejecting --------------------------------------------------------------

## Spitting mass out, which is how a monster gets deliberately smaller.
##
## What it leaves is ordinary planted food, so it replicates, indexes and is eaten through
## the paths everything else already uses. What has to be true is that it costs something,
## that a small monster cannot do it, and that the ejector does not immediately swallow
## its own blob — which would make the whole thing a very expensive way to do nothing.
	_done()
func _test_ejecting() -> void:
	_section("ejecting")

	var world := _make_world()
	world.add_player(1, "Ada")
	_settle(world)
	world.spawn(1, Vector2.ZERO)

	var monster := world.monster_for(1)
	monster.clear_effect(HungryContent.FLAG_PROTECTED)

	var small := Dot2DCommand.new()
	small.aim = Vector2.RIGHT
	small.reach = 600.0
	small.set_button(Dot2DCommand.BUTTON_EJECT, true)

	var release := Dot2DCommand.new()
	release.aim = Vector2.RIGHT
	release.reach = 600.0

	var planted_before := world.field.planted_count()
	world.tick({1: small})

	_check(
		world.field.planted_count() == planted_before,
		"a monster too small to eject does not"
	)
	_check(monster.ejected == 0, "and is not charged for it")

	monster.rider_piece().set_mass(400.0, world.tunables.mass_rules)
	world.tick({1: release})

	var mass_before := monster.mass()
	world.tick({1: small})

	_check(
		world.field.planted_count() > planted_before,
		"a big one leaves a blob behind (%d)" % world.field.planted_count()
	)
	_check(
		monster.mass() < mass_before,
		"and pays for it (%.0f -> %.0f)" % [mass_before, monster.mass()]
	)
	_check(monster.ejected == 1, "and it is counted")

	# Held down must not spray. Edge-triggered plus a cooldown, the same as splitting.
	var after_one := world.field.planted_count()
	world.tick({1: small})
	_check(
		world.field.planted_count() == after_one,
		"a held key does not eject again"
	)

	# The blob has to survive the tick it was made on. It lands beyond the ejector's own
	# eat radius, so the ejector does not swallow it immediately.
	world.tick({1: release})
	_check(
		world.field.planted_count() >= after_one,
		"and the ejector does not eat its own blob back on the spot"
	)

	# Somebody else can. That is the whole point of it being ordinary food.
	var blob := 0

	for grid_id in world.field.alive_ids():
		if HungryField.kind_of(grid_id) == HungryField.Kind.PLANTED:
			blob = grid_id

	_check(blob != 0, "the blob is in the field")
	_check(
		world.arena.grid.has(blob),
		"and in the grid, where an eat check will find it"
	)
	_check(
		is_equal_approx(
			world.field.mass_of(blob),
			HungryContent.FOOD_TIER_MASS[HungryContent.EJECT_TIER]
		),
		"worth less than it cost (%.0f of %.0f)" % [
			world.field.mass_of(blob), HungryContent.EJECT_MASS
		]
	)

	_drop(world)


# --- The loadout -----------------------------------------------------------

## What a player brings in, and the checks the server makes on it.
##
## [b]Every one of these is something a hostile or buggy client does.[/b] dot-loadout's
## whole reason to exist is that a dedicated server has no content and still has to
## decide whether the thing a client just sent is legal — so all of this is answered from
## ids, and if any of it ever needs a `load()`, that is the thing to push back on.
	_done()
func _test_loadout() -> void:
	_section("what a player brings in")

	var schema := HungryContent.loadout_schema()
	var valid := schema.validate()

	_check(valid.ok, "the loadout schema is legal", str(valid.error))

	var default_loadout := schema.default_loadout()
	_check(
		default_loadout.item_in(HungryContent.SLOT_STARTER) == HungryContent.ITEM_PEPPER,
		"and its default is something you can actually spawn with"
	)
	_check(
		default_loadout.item_in(HungryContent.SLOT_TRAIT) == HungryContent.TRAIT_NIMBLE,
		"with a trait"
	)

	# A schema whose own defaults are not legal is refused at startup, because conform
	# never fails and a player would otherwise be unable to spawn at all.
	var owns_nothing := DotLoadoutEntitlements.none()
	var default_ok := DotLoadoutValidator.validate(default_loadout, schema, owns_nothing)
	_check(
		default_ok.ok,
		"which a player who owns nothing may still take",
		str(default_ok.error)
	)

	# The three things a slot refuses, each for a different reason and each with a
	# different right answer in a loadout screen.
	var wrong_slot := DotLoadout.empty(schema.id)
	wrong_slot.set_item(HungryContent.SLOT_STARTER, HungryContent.TRAIT_STURDY)
	wrong_slot.set_item(HungryContent.SLOT_TRAIT, HungryContent.TRAIT_NIMBLE)
	_check(
		not DotLoadoutValidator.validate(wrong_slot, schema, owns_nothing).ok,
		"a trait in the throwable slot is refused"
	)

	var no_such := DotLoadout.empty(schema.id)
	no_such.set_item(HungryContent.SLOT_STARTER, &"trebuchet")
	no_such.set_item(HungryContent.SLOT_TRAIT, HungryContent.TRAIT_NIMBLE)
	_check(
		not DotLoadoutValidator.validate(no_such, schema, owns_nothing).ok,
		"and so is an item the catalogue has never heard of"
	)

	var unowned := DotLoadout.empty(schema.id)
	unowned.set_item(HungryContent.SLOT_STARTER, HungryContent.ITEM_PEPPER)
	unowned.set_item(HungryContent.SLOT_TRAIT, HungryContent.TRAIT_GREEDY)
	_check(
		not DotLoadoutValidator.validate(unowned, schema, owns_nothing).ok,
		"and so is a trait nobody has unlocked"
	)

	# Granting it is what an unlock *is*. Entitlements default to nothing so that an
	# unwired server is wrong within thirty seconds rather than shipping a game where
	# every unlock is free — which nobody reports as a bug.
	var owner := DotLoadoutEntitlements.of([HungryContent.TRAIT_GREEDY_UNLOCK])
	_check(
		DotLoadoutValidator.validate(unowned, schema, owner).ok,
		"until they unlock it"
	)

	# Conform on the way out of a store, validate on the way in from a client. Retiring an
	# item or revoking an unlock makes a saved loadout invalid, and refusing it is a player
	# who has not logged in for a month loading into an error rather than into a slightly
	# different monster.
	var stale := unowned.duplicate_loadout()
	# conform never fails — it returns what it changed, not whether it worked. That is the
	# whole distinction: refusing here would be a player who cannot spawn.
	var changes := DotLoadoutValidator.conform(stale, schema, owns_nothing)
	_check(
		changes.size() > 0,
		"conform repairs one nobody owns any more (%d changes)" % changes.size()
	)
	_check(
		stale.item_in(HungryContent.SLOT_TRAIT) == HungryContent.TRAIT_NIMBLE,
		"back to the default trait (%s)" % stale.item_in(HungryContent.SLOT_TRAIT)
	)
	_check(
		DotLoadoutValidator.validate(stale, schema, owns_nothing).ok,
		"and what it produced is legal"
	)

	# The store key is padded, because DotLoadoutKey has a minimum length and the check
	# exists so a malformed key can never reach a filesystem path.
	_check(
		DotLoadoutKey.is_usable(HungryContent.loadout_key(7)),
		"a player key is usable (%s)" % HungryContent.loadout_key(7)
	)
	_check(not DotLoadoutKey.is_usable("7"), "and a bare id is not")

	# And the mechanical half: three traits that are three different games.
	var world := _make_world()
	world.add_player(1, "Nimble")
	world.add_player(2, "Sturdy")
	_settle(world)

	var nimble := world.monster_for(1)
	var sturdy := world.monster_for(2)

	var chosen := DotLoadout.empty(schema.id)
	chosen.set_item(HungryContent.SLOT_STARTER, HungryContent.ITEM_FROST)
	chosen.set_item(HungryContent.SLOT_TRAIT, HungryContent.TRAIT_STURDY)
	sturdy.wear_loadout(chosen)

	world.spawn(1)
	world.spawn(2)

	_check(
		sturdy.mass() > nimble.mass(),
		"sturdy spawns bigger than nimble (%.1f vs %.1f)" % [
			sturdy.mass(), nimble.mass()
		]
	)
	_check(
		sturdy.speed_multiplier() < nimble.speed_multiplier(),
		"and slower (%.2f vs %.2f)" % [
			sturdy.speed_multiplier(), nimble.speed_multiplier()
		]
	)
	_check(
		sturdy.carried.size() == 1 and sturdy.carried[0] == HungryContent.ITEM_FROST,
		"holding what they chose (%s)"
			% (String(sturdy.carried[0]) if not sturdy.carried.is_empty() else "-")
	)

	# Greedy is worth more food rather than more mass, so it compounds instead of being a
	# flat head start.
	_check(
		HungryContent.trait_food(HungryContent.TRAIT_GREEDY) > 1.0
			and HungryContent.trait_food(HungryContent.TRAIT_NIMBLE) == 1.0,
		"and greedy is paid in food rather than in mass"
	)

	_drop(world)
	_done()
