extends "dedicated_state.gd"

## Middle sections of the dedicated suite: game change, services, moderation, live tools, combat, hunters, hazards.


func _test_game_change() -> void:
	_section("changing the game")

	# The id, NOT the node: changing the game frees the old world, and a lambda that captured it
	# compared against null once freed. An int cannot be freed; nothing here may hold the old world.
	var before_id := _world().get_instance_id()

	var changed: DotResult = await _server.games.change_game(
		HungryModule.GAME_FRENZY, "test"
	)

	_check(changed.ok, "the server changes to frenzy", str(changed.error))

	var replaced := await _until(func() -> bool:
		var now := _world()
		return now != null and now.get_instance_id() != before_id
	)

	_check(replaced, "and the world is replaced rather than merely present")

	# Fails if somebody captures the world again: the old world really is freed, not
	# unregistered and left alive.
	_check(
		instance_from_id(before_id) == null,
		"and the old one is freed, not left alive and unregistered"
	)

	var after := _world()

	_check(
		after != null and after.get_instance_id() != before_id,
		"a new world is registered"
	)
	_check(
		after != null and String(after.preset.id) == "frenzy",
		"under the frenzy preset"
	)
	_check(
		_module().world == after,
		"and the module rebound onto it"
	)
	_check(
		_module().bridge.world == after,
		"and so did the bridge"
	)
	await _test_game_change_kept(after)
	_done()


func _test_game_change_kept(after: HungryWorld) -> void:
	# The manager survives on purpose: rebuilding it would reset the message ids, the peer
	# records and the clock, which is a disconnect for everybody — precisely what changing
	# the map is supposed to avoid.
	_check(
		_module().net != null and _module().net.is_running(),
		"and the netcode manager survived the change"
	)

	await _until(func() -> bool:
		return after != null and after.field.food_count() > 0
	)

	_check(
		after != null and after.field.food_count() > 0,
		"the new world has its own field (%d)"
			% (after.field.food_count() if after != null else 0)
	)
	await _test_game_change_modes()


func _test_game_change_modes() -> void:
	# [b]The newest mode, reached the way an operator reaches it[/b]: `changelevel` at the
	# console, which is the path a map nobody can reach would fail on. Then back to
	# frenzy, so everything after this section runs on the world it always has.
	var frenzy_id := _world().get_instance_id()
	_server.console.execute("changelevel %s" % HungryModule.GAME_SHALLOWS)
	var to_shallows := await _until(func() -> bool:
		var now := _world()
		return now != null and now.get_instance_id() != frenzy_id and now.layout != null \
			and now.layout.count() > 0
	)
	var shallows := _world()
	_check(
		to_shallows and String(shallows.preset.id) == "shallows"
			and shallows.layout.id == HungryLayout.SHALLOWS
			and shallows.layout.chains.size() == HungryLayout.SHALLOWS_LINES,
		"`changelevel %s` reaches the shallows, five lines of posts" % HungryModule.GAME_SHALLOWS,
		"%s, %d posts" % [
			String(shallows.preset.id) if shallows != null else "no world",
			shallows.layout.count() if shallows != null and shallows.layout != null else -1
		]
	)
	_check(
		_module().world == shallows and _module().bridge.world == shallows,
		"and the module and the bridge rebound onto it"
	)

	var shallows_id := shallows.get_instance_id() if shallows != null else 0
	var back: DotResult = await _server.games.change_game(HungryModule.GAME_FRENZY, "test")
	var returned := await _until(func() -> bool:
		var now := _world()
		return now != null and now.get_instance_id() != shallows_id
	)
	_check(
		back.ok and returned and String(_world().preset.id) == "frenzy",
		"and back to frenzy for the rest of the suite"
	)


## Chat, voice and the join between them.
func _test_services() -> void:
	_section("chat and voice")

	var module := _module()
	var services := module.hservices

	_check(services != null, "the services are up")
	_check(
		services.chat != null and services.chat.channel_ids().size() == 4,
		"with four chat channels (%d)"
			% (services.chat.channel_ids().size() if services.chat != null else -1)
	)
	_check(
		services.chat.channel(HungryServices.CHANNEL_NEAR).scope
			== DotChatChannel.Scope.RADIUS,
		"one of which is a radius, because an arena is bigger than a screen"
	)

	# [b]THE join.[/b] dot-chat consults a `dot_mute_source` and dot-moderation publishes
	# one, and neither imports the other — so the only thing that makes a gag work is that
	# something is registered under that name.
	_check(
		DotRegistry.has(DotModerationManager.MUTE_SERVICE),
		"a mute source is registered, which is the only thing that makes a gag work"
	)
	_check(
		DotRegistry.has(DotModerationManager.BAN_SERVICE),
		"and a ban source, which dot-server's admission check consults"
	)

	# [b]Proximity voice, which is where this game and the lobby part company.[/b] Hearing
	# somebody creeping up on you is information in an arena and noise in a room.
	_check(
		services.voice != null
			and services.voice.default_channel == DotVoiceRouter.Channel.PROXIMITY,
		"voice is proximity here rather than the whole server"
	)
	_check(
		services.voice.config.format_fingerprint()
			== HungryServices.voice_config().format_fingerprint(),
		"and its format is the one a client builds from the same file"
	)

	# The operator's switch: registered by the module, replicated so clients hide their key,
	# and enforced on the router.
	var voice_cvar: DotConVar = _server.console.find_cvar("sv_voice_enable")
	_check(voice_cvar != null and DotConsole.is_replicated(voice_cvar),
		"sv_voice_enable is registered and replicated to clients")
	var off_enabled := true
	if voice_cvar != null:
		var _off := voice_cvar.set_value("0")
		off_enabled = services.voice.enabled
		var _on := voice_cvar.set_value("1")
	_check(not off_enabled and services.voice.enabled, "and turns the router off and on")

	# dot-server's own chat is cancelled rather than run beside the router.
	var legacy := _server.events.fire("player_chat", {
		"userid": 1, "name": "Nobody", "text": "hello", "team_only": false,
	})
	_check(
		legacy.cancelled,
		"dot-server's own chat broadcast is cancelled, so there is exactly one path"
	)
	_done()


## A gag, written and read back.
func _test_moderation() -> void:
	_section("moderation")

	var services := _module().services
	var subject := DotPunishmentSubject.for_uid("uid-hungry-test")

	# [b]The store, and that it is empty before this run writes to it.[/b] The second is
	# what says the first worked on THIS run: a path that is right and a directory that was
	# not wiped is a suite carrying the last run's gag into this one.
	_check(services.punishments_path.begins_with(SERVER_DIR),
		"punishments go to this run's own store, not the one a real server enforces",
		services.punishments_path)
	_check(services.moderation.count() == 0,
		"and it starts empty, so nothing a previous run did is in it",
		"%d records" % services.moderation.count())

	var gagged: DotResult = await services.moderation.issue(
		DotPunishment.Kind.GAG, subject, "testing", "console", 60
	)
	_check(gagged.ok, "a gag is issued and stored", str(gagged.error))

	# Round-tripped through the store: dot-moderation once shipped a voice mute that loaded back
	# as a WARN, and a punishment surviving a reconnect is the point of the addon.
	var reloaded := DotModerationManager.new()
	reloaded.store = DotPunishmentStoreFile.new(services.punishments_path)
	reloaded.register_mute_source = false
	reloaded.register_ban_source = false
	add_child(reloaded)
	reloaded.load_all()

	var found := reloaded.active_of_kind(subject, DotPunishment.Kind.GAG)
	_check(
		found != null and found.kind == DotPunishment.Kind.GAG,
		"and comes back off disk as a GAG rather than as a WARN"
	)

	var muted: DotResult = await services.moderation.issue(
		DotPunishment.Kind.VOICE_MUTE, subject, "testing", "console", 60
	)
	_check(muted.ok, "a voice mute is issued", str(muted.error))
	_check(
		services.moderation.is_voice_muted_key(subject),
		"and reads back as a voice mute rather than as a warning"
	)
	reloaded.queue_free()
	_done()


## dot-moderation's live tools, as an operator types them, against a monster that joined
## the way a client's does. The subset this game supports acts on the world; the rest is
## refused with the reason `HungryModTools` gives.
func _test_live_tools() -> void:
	_section("the moderator's live tools")

	_check(
		_server.console.find_command("slay") != null and _server.console.find_command("noclip") != null,
		"the live tools' commands are on the console"
	)

	var session := DotClientSession.new()
	session.peer_id = 3131
	session.userid = 313
	session.display_name = "Chomp"
	var _adopted := _server.adopt_session(session)
	_server.events.fire("client_spawn", {"userid": 313, "name": "Chomp"})

	var world := _world()
	var monster := world.monster_for(313)
	_check(monster != null, "a player joins as a monster")

	# Who the vote treats as an admin, which gates the wire's `extend`: CHANGEMAP, not
	# `is_admin()` — "holds any flag at all" — under which a reserved slot extended the mode.
	var hungry: Object = _module()
	session.permissions = PackedStringArray(["reservation", "chat"])
	var slot_only: bool = hungry.call("_voter_is_admin", &"313")
	session.permissions = PackedStringArray(["changemap"])
	var changer: bool = hungry.call("_voter_is_admin", &"313")
	session.permissions = PackedStringArray()
	_check(not slot_only and changer,
		"a reserved slot is not a vote admin, and changemap is",
		"slot %s, changemap %s" % [slot_only, changer])

	# A peer with nobody in the world yet votes as nobody. They all answered as player 0,
	# so every such peer rocked, nominated and voted as one voter.
	var director: DotVoteDirector = hungry.get("maps").director if hungry.get("maps") != null else null
	var rocks_before := director.clock.rtv_votes() if director != null else -1
	hungry.call("_on_vote_requested", 987654, "rtv")
	_check(director != null and director.clock.rtv_votes() == rocks_before
			and not director.clock.has_rocked(&"0"),
		"a peer with nobody in the world yet cannot rock the vote as player 0")

	if monster == null:
		for what in ["slay", "respawn", "give", "noclip", "freeze", "speed", "clean", "refusal", "rename",
				"blind", "blind entity", "blind spell", "beacon", "beacon entity", "beacon kept",
				"beacon off", "modtools"]:
			_check(false, what)
		_done()
		return
	await _test_live_tools_acts(world, monster, session)
	_done()


func _test_live_tools_acts(world: HungryWorld, monster: HungryMonster, session: DotClientSession) -> void:
	if monster.piece_count() == 0:
		world.spawn(313)
		monster.alive = true

	var slain := await _live("slay Chomp")
	_check(monster.piece_count() == 0 and not monster.alive,
		"`slay Chomp` devours every piece, the world's own death", " | ".join(slain))

	var back := await _live("respawn Chomp")
	_check(monster.piece_count() > 0 and monster.alive,
		"`respawn Chomp` puts them back at a safe spawn", " | ".join(back))

	var item := String(world.items.ids()[0]) if world.items != null and not world.items.ids().is_empty() else "pepper"
	monster.carried.clear()
	var given := await _live("give Chomp %s" % item)
	_check(monster.carried.has(StringName(item)), "`give Chomp %s` puts it in their hands" % item,
		" | ".join(given))

	# Noclip, freeze and speed are dot-2d's admin modifiers now: on the monster, and in every
	# piece's replicated state, which is what the owning client predicts. `headless_net` is
	# where the prediction itself is measured; this is the console reaching it.
	var clipped := await _live("noclip Chomp")
	_check(
		Dot2DAdminModifiers.bits_noclip(monster.admin)
			and monster.pieces.all(func(p: Variant) -> bool: return Dot2DAdminModifiers.is_noclipped(p.state)),
		"`noclip Chomp` reaches the monster and every piece's state", " | ".join(clipped))

	var held := await _live("freeze Chomp")
	_check(
		Dot2DAdminModifiers.bits_frozen(monster.admin)
			and monster.pieces.all(func(p: Variant) -> bool: return Dot2DAdminModifiers.is_frozen(p.state)),
		"`freeze Chomp` holds every piece", " | ".join(held))

	var quick := await _live("speed Chomp 2.2")
	_check(
		is_equal_approx(Dot2DAdminModifiers.bits_speed(monster.admin), 2.0)
			and _said_any(quick, "2×") and not _said_any(quick, "2.2"),
		"`speed Chomp 2.2` lands on the 2x step, and says so", " | ".join(quick))

	# A respawn is a new body: dot-moderation switches noclip and freeze off through the
	# handlers, off HungryWorld.player_spawned. Without that hook the bits would ride the
	# monster — which outlives its pieces — into the next life.
	var _again := await _live("respawn Chomp")
	_check(
		not Dot2DAdminModifiers.bits_noclip(monster.admin)
			and not Dot2DAdminModifiers.bits_frozen(monster.admin)
			and monster.pieces.all(func(p: Variant) -> bool: return (p.state as Dot2DState).admin == 0),
		"and a respawn arrives clean: no noclip, no freeze, normal speed",
		str(Dot2DAdminModifiers.words(monster.admin)))
	await _test_live_tools_flags(monster, session)


func _test_live_tools_flags(monster: HungryMonster, session: DotClientSession) -> void:
	# Blind and beacon are two flags on the monster, carried on every piece's entity (blind to its
	# owner alone, the beacon to everybody); this is the console reaching them.
	var dark := await _live("blind Chomp")
	_check(monster.blinded, "`blind Chomp` blacks their screen out", " | ".join(dark))
	_check(
		await _until(func() -> bool: return _pieces_carry(monster, "net_blind", true)),
		"and it is on every piece's entity the netcode sends them"
	)

	# A blind is a spell. dot-moderation lifts it through the same handler when the time is
	# up, so what is checked is the flag, not the timer.
	var _lift := await _live("blind Chomp off")
	var spell := await _live("blind Chomp 0.2")
	var was_on := monster.blinded
	await get_tree().create_timer(0.4).timeout
	_check(was_on and not monster.blinded, "`blind Chomp 0.2` lifts on its own when the time is up",
		" | ".join(spell))

	var lit := await _live("beacon Chomp")
	_check(monster.beacon, "`beacon Chomp` marks them on every screen", " | ".join(lit))
	_check(
		await _until(func() -> bool: return _pieces_carry(monster, "net_beacon", true)),
		"and every piece of a beaconed monster is relevant to everybody, however far away"
	)

	# Both are about the person, not the body: being eaten is what a player being punished
	# would otherwise use to end one, and in this game that takes no effort at all.
	var _dark_again := await _live("blind Chomp")
	var _eaten := await _live("slay Chomp")
	var _reborn := await _live("respawn Chomp")
	_check(
		monster.alive and monster.blinded and monster.beacon,
		"a respawn keeps blind and beacon, where it ends a noclip and a freeze"
	)

	var _dark_off := await _live("blind Chomp off")
	var _unlit := await _live("beacon Chomp off")
	_check(
		await _until(func() -> bool: return _pieces_carry(monster, "net_beacon", false))
			and not monster.blinded and not monster.beacon,
		"`beacon Chomp off` puts them back under the ordinary interest rules"
	)

	var listed := await _live("modtools")
	_check(
		_said_any(listed, "blind") and _said_any(listed, "beacon")
			and not _said_any(listed, "draws no"),
		"`modtools` lists blind and beacon as supported, and no longer refuses them",
		" | ".join(listed)
	)

	var refused := await _live("god Chomp")
	_check(_said_any(refused, "being eaten"), "`god` is refused, and says being eaten is the game",
		" | ".join(refused))

	var _renamed := await _live("rename Chomp Nibbles")
	_check(monster.display_name == "Nibbles" and session.display_name == "Nibbles",
		"`rename` reaches the monster and the session")

	var _released := _server.release_session(session.peer_id)


## What a throwable does, through dot-combat rather than through a constant.
func _test_combat() -> void:
	_section("combat")

	var combat := _module().combat

	_check(combat != null, "the combat rules are up")
	_check(
		_module().world.damage_gate.is_valid(),
		"and the world asks them before a throwable does anything"
	)

	# Point blank against maximum range. [b]The whole reason falloff is worth having[/b]:
	# a pepper thrown across the arena has to be worth less than one thrown in somebody's
	# face, or throwing is a button rather than a decision.
	var close := combat.resolve_throw(1, 2, HungryContent.ITEM_PEPPER, 10.0)
	var far := combat.resolve_throw(1, 2, HungryContent.ITEM_PEPPER, 5000.0)

	_check(close != null and not close.refused, "a point-blank hit lands")
	_check(
		close != null and far != null and far.amount < close.amount,
		"and one from across the arena does less (%.0f against %.0f)"
			% [far.amount if far != null else -1.0, close.amount if close != null else -1.0]
	)
	_check(
		combat.pieces_for(close) > combat.pieces_for(far),
		"which is fewer pieces (%d against %d)"
			% [combat.pieces_for(close), combat.pieces_for(far)]
	)

	# [b]Self damage is off, and a monster bursting itself is the world's own eject.[/b] A
	# scaled self hit would be a second, worse way to do a thing this game already has.
	var own := combat.resolve_throw(1, 1, HungryContent.ITEM_PEPPER, 10.0)
	_check(own != null and own.refused, "throwing at yourself is refused, not scaled")

	# An item the combat layer has no type for passes through untouched. Refusing it would
	# silently disable a throwable by installing an addon.
	var lure := combat.gate(1, 2, HungryContent.ITEM_LURE, 100.0)
	_check(
		bool(lure.get("allowed", false)),
		"a lure is not combat and is left alone"
	)
	_done()


## The NPC monsters, and the director that decides when they arrive.
func _test_hunters() -> void:
	_section("hunters")

	var hunters := _module().hunters

	_check(hunters != null, "the hunter layer is up")
	_check(
		hunters.spawner != null and hunters.spawner.two_dimensional,
		"and its spawner knows the world is 2D"
	)
	_check(
		not hunters.is_enabled(),
		"with the director off by default",
		"a mode about eating food and a mode about being hunted are different games"
	)

	# The wire order has to be stable and has to be sorted as String — `Array.sort()` on a
	# StringName compares interned pointers, and dot-net shipped exactly that bug.
	var ids := HungryHunters.wire_ids()
	var sorted := ids.duplicate()
	sorted.sort()
	_check(
		Array(ids) == Array(sorted),
		"the wire order is lexicographic, not interned-pointer order"
	)
	_check(
		HungryHunters.id_at(HungryHunters.index_of(&"stalker")) == &"stalker",
		"and an id round-trips through its index"
	)

	# [b]The plane, which is the whole of the 2D mapping.[/b] Get it wrong and a sight
	# range of 1400 is a sight range of nothing, silently.
	_check(
		DotNpcInstance.from_plane(DotNpcInstance.to_plane(Vector2(3.0, -7.0)))
			== Vector2(3.0, -7.0),
		"a 2D point round-trips through dot-npc's plane"
	)

	_server.console.execute("hungry_hunters on")
	_check(hunters.is_enabled(), "the console turns them on")
	_test_hunters_run(hunters)
	_done()


func _test_hunters_run(hunters: HungryHunters) -> void:
	# The director needs somebody to be stressed about before it releases anything.
	var world := _module().world
	world.add_player(4242, "Bait")
	world.spawn(4242)

	for _step in range(240):
		hunters.tick(1.0 / 60.0)

	_check(
		hunters.count() > 0,
		"and the director releases some (%d)" % hunters.count()
	)

	var kinds: Dictionary = {}

	for state in hunters.hunters().values():
		kinds[(state as Dictionary)["kind"]] = true

	_check(
		kinds.size() >= 1,
		"of the kinds in its population list (%s)" % str(kinds.keys())
	)

	# The candidate has to be a monster rather than a piece: a hunter chasing one fragment
	# of a split player walks past the other seven.
	_check(
		hunters.position_of(&"p4242") != Vector3.INF,
		"a player resolves as a candidate"
	)
	_check(
		hunters.position_of(&"p999999") == Vector3.INF,
		"and somebody who has gone resolves as INF rather than as the origin",
		"zero is the middle of the arena, so a hunter whose target left would sprint "
		+ "to the centre and mill about — which reads as a pathfinding bug"
	)

	_server.console.execute("hungry_hunters off")
	_check(hunters.count() == 0, "turning them off clears the arena")

	world.remove_player(4242)


## How far from its quarry the hunt section's stalker starts.
const GAP := 600.0


## A hunter on the real server chases what it can eat and runs from what can eat it.
## A stalker starts [constant GAP] from a monster, as far from every bot as the arena allows; the
## gap is measured over 1.5 s of the hunter tick, world not ticked, director off.
func _test_hunters_hunt() -> void:
	_section("hunters hunt")

	var hunters := _module().hunters
	var world := _module().world
	var id := 4243
	var tag := StringName("%s%d" % [HungryHunters.PLAYER_PREFIX, id])
	var bounds := world.arena.bounds
	var centre := bounds.get_center()

	# As far from every bot left over from `bots` as the arena allows. A hunter targets the
	# nearest thing it perceives, so a bot nearer than the monster placed here would be
	# what it chased — which the exit probe's copy found, with its bots elsewhere.
	var others: Array[Vector2] = []

	for monster in world.monsters():
		if monster.alive and monster.piece_count() > 0:
			others.append(monster.centre())

	var inner := bounds.grow(-500.0)
	var prey_at := centre
	var hunter_at := centre + Vector2.RIGHT * GAP
	var best := -INF

	for gx in range(9):
		for gy in range(9):
			var p := inner.position + inner.size * Vector2(gx / 8.0, gy / 8.0)

			for turn in range(8):
				var h := p + Vector2.from_angle(TAU * turn / 8.0) * GAP

				if not inner.has_point(h):
					continue

				var clearance := INF

				for other in others:
					clearance = minf(clearance, minf(other.distance_to(p), other.distance_to(h)))

				if clearance > best:
					best = clearance
					prey_at = p
					hunter_at = h
	_test_hunt_chase(hunters, world, id, tag, prey_at, hunter_at, best)
	_done()


func _test_hunt_chase(hunters: HungryHunters, world: HungryWorld, id: int, tag: StringName, prey_at: Vector2, hunter_at: Vector2, best: float) -> void:
	world.add_player(id, "Quarry")
	world.spawn(id, prey_at)
	var quarry := world.monster_for(id)
	var npc := hunters.spawner.spawn_2d(&"stalker", hunter_at)

	if not _check(
		npc != null and quarry != null and quarry.alive,
		"a stalker stands %.0f from a starting monster on the running server (nearest bot %.0f off)"
			% [GAP, best]
	):
		hunters.spawner.clear_all()
		world.remove_player(id)
		return

	var body := npc.node as Node2D
	var ticks := 90
	var step := 1.0 / 60.0

	# Chase: a starting monster (about 20) against a stalker (220). The clock starts when the
	# chase does and the stalker is put back first: the wander before its senses settle depends
	# on the instance id, which differs between processes.
	var noticed := 0
	var brain: Object = npc.brain

	while noticed < 120 and not (
		brain != null and brain.get(&"machine") != null
		and brain.machine.current() == &"chase"
	):
		hunters.tick(step)
		noticed += 1

	body.global_position = hunter_at
	var before := body.global_position.distance_to(quarry.centre())

	for _i in range(ticks):
		hunters.tick(step)

	var after := body.global_position.distance_to(quarry.centre()) \
		if npc.is_alive() else INF
	_check(
		String(npc.target_id) == String(tag) and after < before - 200.0,
		"it chases a monster it can eat: the gap shrinks over 1.5 s (%.0f -> %.0f, chasing after %d ticks)"
			% [before, after, noticed],
		"target %s, mass %.0f against %.0f"
			% [str(npc.target_id), HungryHunters.mass_of(&"stalker"), quarry.mass()]
	)
	_test_hunt_flee(hunters, world, id, tag, npc, quarry, body, hunter_at, ticks, step)


func _test_hunt_flee(hunters: HungryHunters, world: HungryWorld, id: int, tag: StringName, npc: Variant, quarry: HungryMonster, body: Node2D, hunter_at: Vector2, ticks: int, step: float) -> void:
	# Flee: the same monster, fed past the eat ratio, from the same start.
	world.feed_player(id, 400.0)
	body.global_position = hunter_at
	var before := body.global_position.distance_to(quarry.centre())

	for _i in range(ticks):
		hunters.tick(step)

	var after := body.global_position.distance_to(quarry.centre()) if npc.is_alive() else -INF
	_check(
		String(npc.target_id) == String(tag) and after > before + 200.0,
		"and runs from one that can eat it: the gap grows over 1.5 s (%.0f -> %.0f)"
			% [before, after],
		"target %s, mass %.0f against %.0f"
			% [str(npc.target_id), HungryHunters.mass_of(&"stalker"), quarry.mass()]
	)

	hunters.spawner.clear_all()
	world.remove_player(id)

	_time_path_searches()


## Information, not a check: what one whole-map path search costs, as a hunter's repath
## does it (`find_smooth_path`, the spawner's snap, partial paths allowed), so the next
## run knows whether dot-npc's scan for the nearest point wants a spatial index.
func _time_path_searches() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260926

	for preset: HungryPreset in [HungryPreset.warrens(), HungryPreset.reef()]:
		var bounds := Rect2(-preset.world_size * 0.5, preset.world_size)
		var layout := HungryLayout.for_id(preset.layout, bounds)
		var built_at := Time.get_ticks_usec()
		var data := HungryHunters.nav_for(layout, bounds)
		var graph := DotNpcNavGraph.new()
		graph.rebuild(data)
		var build_ms := float(Time.get_ticks_usec() - built_at) / 1000.0

		var total := 0.0
		var worst := 0.0
		var found := 0
		var searches := 50

		for _i in range(searches):
			var a := data.points[rng.randi_range(0, data.point_count() - 1)]
			var b := data.points[rng.randi_range(0, data.point_count() - 1)]
			var started := Time.get_ticks_usec()
			var path := graph.find_smooth_path(a, b, 100.0, true)
			var ms := float(Time.get_ticks_usec() - started) / 1000.0
			total += ms
			worst = maxf(worst, ms)
			found += 1 if not path.is_empty() else 0

		print("  info  path search on %s (%d points, %d edges, built in %.0f ms): "
			% [String(preset.id), data.point_count(), data.edge_count(), build_ms]
			+ "average %.1f ms, worst %.1f ms over %d searches (%d found)"
			% [total / searches, worst, searches, found])


## Rocks, spikes and lures.
func _test_hazards() -> void:
	_section("hazards")

	var hazards := _module().hazards

	_check(hazards != null, "the hazard layer is up")

	var placed := hazards.place(0, &"rock", Vector2(200.0, 200.0))
	_check(placed.ok, "a rock goes down", str(placed.error))
	_check(hazards.count() == 1, "and the arena has one thing in it")
	_check(
		hazards.obstacles().size() == 1,
		"which is an obstacle both ends resolve against"
	)

	# A lure is a prop and is not an obstacle. The field is read rather than assumed:
	# dot-props' own sweep found two documented limits that limited nothing.
	var lure := hazards.place(0, &"lure", Vector2(-200.0, 0.0))
	_check(lure.ok, "a lure goes down too", str(lure.error))
	_check(
		hazards.obstacles().size() == 1,
		"and is NOT an obstacle (%d solid of %d placed)"
			% [hazards.obstacles().size(), hazards.count()]
	)
	_check(hazards.lures().size() == 1, "but it is a lure")

	# [b]Deterministic, because a round has to be reproducible.[/b] `randf()` here would
	# make two runs of the same seed lay out two different arenas, and the whole reason
	# `headless_round` can assert anything is that it does not.
	hazards.clear_all()
	var first := hazards.scatter(&"rock", 6, 4242)
	var layout: Array = []

	for entry in hazards.placements().values():
		layout.append((entry as Dictionary)["at"])

	hazards.clear_all()
	hazards.scatter(&"rock", 6, 4242)
	var again: Array = []

	for entry in hazards.placements().values():
		again.append((entry as Dictionary)["at"])

	layout.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	again.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	_check(first == 6, "a scatter places what it was asked for (%d)" % first)
	_check(
		layout == again,
		"and the same seed lays out the same arena twice"
	)

	hazards.clear_all()
	_check(hazards.count() == 0, "a clear empties it")
	_done()
