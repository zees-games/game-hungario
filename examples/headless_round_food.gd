extends "headless_round_checks.gd"
## The food checks of the headless round suite: tiers, food on the floor, feast and famine, fruit, the lure
## and growing. Split out of headless_round.gd, which extends this and runs them in its own order.


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


	_done()


## Food per unit of the floor that is left, MEASURED, for every mode with a level in it.
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


## The Famine mode, driven by bots: scarce food and plentiful throwables, a round that still ends with a winner.
func _test_famine() -> void:
	_section("famine, eight bots")

	var preset := HungryPreset.for_id(&"famine")
	var classic := HungryPreset.classic()
	_check(
		preset.id == &"famine" and preset.layout == HungryLayout.NONE and preset.validate().ok,
		"famine is a valid mode with no rocks"
	)
	_check(
		preset.food_target < classic.food_target and preset.fruit_target > classic.fruit_target
			and preset.item_target > classic.item_target,
		"with less food than Classic and more fruit and items"
	)

	var world := _make_world(preset, SEED + 11)
	var ended := [false]
	world.match_node.round_ended.connect(
		func(_round_number: int, _winner: int, _outcome: DotMatchRules.Outcome) -> void: ended[0] = true
	)

	for id in range(1, 9):
		world.add_player(id, "Bot %d" % id)

	_settle(world)

	var throws := [0]
	world.projectile_thrown.connect(func(_s: HungryProjectile) -> void: throws[0] += 1)
	var ticks := 0
	var limit := TICK_RATE * 300

	while not ended[0] and ticks < limit:
		var commands: Dictionary = {}

		for monster in world.monsters():
			commands[monster.id] = HungryBot.command_for(world, monster, ticks)

		world.tick(commands)
		ticks += 1

	_check(ended[0], "the round ends (%d ticks, %.0fs)" % [ticks, float(ticks) / TICK_RATE])
	var top := world.leaderboard(1)
	_check(
		not top.is_empty() and top[0].mass() > HungryContent.START_MASS * 3.0,
		"somebody grew (%.0f)" % (top[0].mass() if not top.is_empty() else 0.0)
	)
	_check(throws[0] > 0, "and the bots threw things (%d)" % throws[0])
	_check(_furthest_edge(world) <= 0.5, "and nothing ended up outside the world")
	_drop(world)

	_done()


## The Feast mode, driven by bots: dense food and a high winning mass, a round that still ends with a winner.
func _test_feast() -> void:
	_section("feast, eight bots")

	var preset := HungryPreset.for_id(&"feast")
	var classic := HungryPreset.classic()
	_check(
		preset.id == &"feast" and preset.layout == HungryLayout.NONE and preset.validate().ok,
		"feast is a valid mode with no rocks"
	)
	_check(
		float(preset.food_target) / (preset.world_size.x * preset.world_size.y)
			> float(classic.food_target) / (classic.world_size.x * classic.world_size.y)
			and preset.merge_delay_sec > classic.merge_delay_sec,
		"with a denser field than Classic and a longer merge delay"
	)

	var world := _make_world(preset, SEED + 12)
	var ended := [false]
	world.match_node.round_ended.connect(
		func(_round_number: int, _winner: int, _outcome: DotMatchRules.Outcome) -> void: ended[0] = true
	)

	for id in range(1, 9):
		world.add_player(id, "Bot %d" % id)

	_settle(world)

	var ticks := 0
	var limit := TICK_RATE * 480

	while not ended[0] and ticks < limit:
		var commands: Dictionary = {}

		for monster in world.monsters():
			commands[monster.id] = HungryBot.command_for(world, monster, ticks)

		world.tick(commands)
		ticks += 1

	_check(ended[0], "the round ends (%d ticks, %.0fs)" % [ticks, float(ticks) / TICK_RATE])
	var top := world.leaderboard(1)
	_check(
		not top.is_empty() and top[0].mass() > HungryContent.START_MASS * 3.0,
		"somebody grew (%.0f)" % (top[0].mass() if not top.is_empty() else 0.0)
	)
	_check(_furthest_edge(world) <= 0.5, "and nothing ended up outside the world")
	_drop(world)

	_done()
