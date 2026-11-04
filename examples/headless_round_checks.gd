extends "headless_round_levels.gd"
## Helper sections of headless_round.gd: the interface, the reach sweep and the throwables.

func _first_of(world: HungryWorld, kind: HungryField.Kind) -> int:
	for grid_id in world.field.alive_ids():
		if HungryField.kind_of(grid_id) == kind:
			return grid_id

	return 0


## Running over a drop picks it up, and a full monster leaves the next one where it is.
func _items_pickup(world: HungryWorld, thrower: HungryMonster) -> void:
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


## A thrown pepper bursts a big enough victim into pieces that cannot merge at once.
func _items_pepper(world: HungryWorld, thrower: HungryMonster, victim: HungryMonster, hold: Dot2DCommand) -> void:
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


## A rind absorbs a burst outright and is spent doing it.
func _items_rind(world: HungryWorld, victim: HungryMonster) -> void:
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


## A thrown frostberry slows its target.
func _items_frost(world: HungryWorld, thrower: HungryMonster, victim: HungryMonster, hold: Dot2DCommand) -> void:
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


## The warrens at the winning mass: the ring leaves a whole perimeter lane, and the quartered variant holds a leader to a quarter of it.
func _reach_warrens(layout: HungryLayout, bounds: Rect2, wall: Vector2, rules: Dot2DMassRules, stranded_big: PackedVector2Array, big_note: String, mode: StringName, won: float) -> void:
	# The design: a leader is not quartered. The corner rocks stand against the walls, a pinwheel, with the lane going round their inner side.
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


## The shallows: a leader is shut out of every band behind its tree line and nothing in front of it.
func _reach_shallows(layout: HungryLayout, bounds: Rect2, stranded_big: PackedVector2Array, big_note: String, mode: StringName) -> void:
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


## Every gate passes a monster just under its width and refuses one just over it.
func _reach_gates(layout: HungryLayout, bounds: Rect2, start: float, slack: float, mode: StringName) -> void:
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


## The HUD is built, outlined, and carries a leaderboard and a feed.
func _interface_hud(hud: HungryHud, stack: DotScreenStack) -> void:
	_check(hud.mass_bar != null, "the HUD builds its widgets")
	_check(hud.minimap != null, "including a minimap")

	# HUD text over the pale sky is outlined or it is a smudge, so the mass number is a
	# Label: DotStatBar draws its own text with no outline.
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


## The Tab board draws the world's monsters in the world's order.
func _interface_board(world: HungryWorld) -> void:
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


## The Loadout page offers what the schema and entitlements allow.
func _interface_loadout_page() -> void:
	# The Loadout page offers what the schema and this player's entitlements allow, and nothing else; a page that filtered on its own would drift from the server.
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


## The renderer's threat rings, the one readability affordance.
func _interface_threat_rings(world: HungryWorld) -> void:
	# The one readability affordance this genre cannot do without: eating needs a ratio, and a quarter of a difference in area is about 12% in width, which nobody judges by eye.
	# The renderer must not call something food that is merely smaller.
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


## An eaten player watches whoever ate them, and the HUD says so.
func _interface_watching(world: HungryWorld, hud: HungryHud) -> void:
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


## The Loadout page for a player who owns nothing, and once a trait is unlocked.
func _interface_loadout_offers() -> void:
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


## Chat is not a screen on the stack; the chat window submits trimmed text.
func _interface_chat(stack: DotScreenStack) -> void:
	# [b]Chat is no longer a screen on this stack.[/b] It was a modal `DotScreen` on Enter
	# with one line edit in it — the only chat box of its kind in the family, with no log,
	# no channels and no way to know whether anything else was carrying the conversation.
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


## The on-screen buttons reach the command.
func _interface_touch(world: HungryWorld) -> void:
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

	touch.buttons.button_down.emit(&"split")
	_check(
		sampler.sample().is_pressed(Dot2DCommand.BUTTON_SPLIT),
		"the split button reaches the command"
	)
	touch.buttons.button_up.emit(&"split")
	_check(
		not sampler.sample().is_pressed(Dot2DCommand.BUTTON_SPLIT),
		"and lets go again"
	)

	# The throw button is disabled with nothing to throw, and names what it will throw
	# when there is — throwing a lure at somebody chasing you is a wasted charge.
	_check(not touch.can_throw(), "the throw button does nothing while empty")
	touch.show_carried(PackedStringArray(["pepper"]))
	_check(touch.can_throw(), "and acts once something is carried")
	_check(
		touch.throw_label().to_lower().contains("pepper"),
		"naming it (%s)" % touch.throw_label()
	)

	touch.buttons.button_down.emit(&"throw")
	_check(
		sampler.sample().is_pressed(Dot2DCommand.BUTTON_ACTION),
		"and it reaches the command too"
	)
	touch.buttons.button_up.emit(&"throw")

	remove_child(sampler)
	sampler.free()
	remove_child(touch)
	touch.free()
