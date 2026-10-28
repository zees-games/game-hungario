extends "res://examples/headless_net_predict.gd"

func _test_field_replication() -> void:
	_section("food")

	# Put the monster on a crumb and let it eat. What has to arrive is not the crumb but
	# the fact that it is gone.
	var target := 0

	for grid_id in _server_world.field.alive_ids():
		if HungryField.kind_of(grid_id) == HungryField.Kind.FOOD:
			target = grid_id
			break

	_server_world.spawn(7, _server_world.field.position_of(target))
	_steps(4)

	_check(
		not _server_world.field.food.is_alive(HungryField.index_of(target)),
		"the server ate a crumb"
	)
	_check(
		not _client_world.field.food.is_alive(HungryField.index_of(target)),
		"and the client was told"
	)
	_check(
		absi(_client_world.field.alive_count() - _server_world.field.alive_count()) <= 8,
		"and the two fields stay in step (%d vs %d)" % [
			_client_world.field.alive_count(), _server_world.field.alive_count()
		]
	)

	# The refill also has to travel, or a client's world empties over a long round while
	# the server's stays full.
	var before := _client_world.field.alive_count()
	_steps(30)
	_check(
		_client_world.field.alive_count() >= before,
		"and the refill arrives too"
	)
	_done()

func _test_splitting_replicates() -> void:
	_section("splitting, over the wire")

	var monster := _server_world.monster_for(7)
	monster.rider_piece().set_mass(500.0, _server_world.tunables.mass_rules)
	monster.clear_effect(HungryContent.FLAG_PROTECTED)

	var before := _client_bridge.piece_count()

	var split := Dot2DCommand.new()
	split.aim = Vector2.RIGHT
	split.reach = 700.0
	split.set_button(Dot2DCommand.BUTTON_SPLIT, true)

	_step(split)

	var release := Dot2DCommand.new()
	release.aim = Vector2.RIGHT
	release.reach = 700.0
	_steps(10, release)

	_check(
		_server_world.monster_for(7).piece_count() > 1,
		"the server split them (%d pieces)"
			% _server_world.monster_for(7).piece_count()
	)
	_check(
		_client_bridge.piece_count() > before,
		"and the client mirrored the new piece (%d -> %d)" % [
			before, _client_bridge.piece_count()
		]
	)
	_check(
		_client_world.monster_for(7).piece_count()
			== _server_world.monster_for(7).piece_count(),
		"and holds the same number of them"
	)

	# Both ends must agree which piece the rider is on, or the avatar is drawn on a
	# different fragment on every machine.
	var server_rider := _server_world.monster_for(7).rider_piece()
	var client_rider := _client_world.monster_for(7).rider_piece()
	_check(
		server_rider != null and client_rider != null
			and server_rider.id == client_rider.id,
		"and on the same piece the rider is on"
	)

	# And a merge has to take the entity away again, or a client accumulates ghosts.
	var pieces_before := _client_bridge.piece_count()
	_server_world.forget_piece(server_rider.id)
	_flush()
	_check(
		_client_bridge.piece_count() < pieces_before,
		"a piece that goes away is despawned everywhere"
	)
	_done()

## A death goes the same way on every screen: DIED carries the server's pick, last and optional.
## Armed by dropping the fall from `write_died`, and by reading it unconditionally.
func _test_death_carries_its_fall() -> void:
	_section("a death carries its fall")

	var fall := DotPlayerDeath.new()
	fall.reaction = DotPlayerDeathReactions.CRUMPLE
	fall.roll_seed = 4242
	fall.damage = 37.0
	fall.direction = Vector3(0.0, 0.0, -1.0)
	var read := HungryEvents.read_died(DotNetReader.new(HungryEvents.write_died(9, 3, fall)))
	var carried: DotPlayerDeath = read.get("death")
	_check(bool(read["ok"]) and int(read["first"]) == 9 and int(read["second"]) == 3
			and carried != null and carried.reaction == fall.reaction and carried.roll_seed == 4242
			and carried.direction.distance_to(fall.direction) < 0.05,
		"DIED round-trips the victim, the eater and the fall", str(read))
	var bare := HungryEvents.read_died(DotNetReader.new(HungryEvents.write_pair(9, 3)))
	_check(bool(bare["ok"]) and int(bare["first"]) == 9 and not bare.has("death"),
		"and an older server's pair reads as a death with no fall", str(bare))

	var heard: Array[Dictionary] = []
	var on_cue := func(kind: int, data: Dictionary) -> void:
		if kind == HungryEvents.Kind.DIED:
			heard.append(data)
	_client_bridge.cue.connect(on_cue)
	var monster := _server_world.monster_for(7)
	var before: DotPlayerDeath = monster.death
	monster.death = fall
	_server_bridge._on_player_died(7, 0)
	_steps(2)
	monster.death = before
	_client_bridge.cue.disconnect(on_cue)
	_check(heard.size() == 1 and int(heard[0].get("first", -1)) == 7,
		"the death reaches the client", str(heard))
	_check(heard.size() == 1 and heard[0].get("death") != null
			and (heard[0]["death"] as DotPlayerDeath).reaction == DotPlayerDeathReactions.CRUMPLE,
		"with the server's reaction, so every client draws the same fall")
	_done()

func _test_throw_replicates() -> void:
	_section("throwing, over the wire")

	var monster := _server_world.monster_for(7)
	_server_world.spawn(7, Vector2.ZERO)
	monster.clear_effect(HungryContent.FLAG_PROTECTED)
	monster.carried.clear()
	monster.take_item(HungryContent.ITEM_PEPPER)
	monster.throw_ready_tick = _server_world.current_tick()

	var thrown: Array[int] = []
	_client_bridge.cue.connect(func(kind: int, _data: Dictionary) -> void:
		thrown.append(kind)
	)

	var throw_command := Dot2DCommand.new()
	throw_command.aim = Vector2.RIGHT
	throw_command.reach = 600.0
	throw_command.set_button(Dot2DCommand.BUTTON_ACTION, true)

	# Inputs are stamped ahead of the server, so the press lands a couple of ticks later.
	_steps(INPUT_LEAD + 2, throw_command)

	_check(
		_client_world.projectiles().size() == 1,
		"the client sees the pepper in flight (%d)"
			% _client_world.projectiles().size()
	)

	# The flight is a straight line from a start tick, so both ends draw it in the same
	# place without another byte.
	if _client_world.projectiles().size() == 1 \
			and _server_world.projectiles().size() == 1:
		var here := _client_world.projectiles()[0].position_at(_tick + 20, TICK_RATE)
		var there := _server_world.projectiles()[0].position_at(_tick + 20, TICK_RATE)
		_check(
			here.distance_to(there) < 2.0,
			"and in the same place twenty ticks on (%.2f apart)" % here.distance_to(there)
		)

	var release := Dot2DCommand.new()
	_steps(120, release)

	_check(
		_server_world.projectiles().is_empty(),
		"the server resolves it"
	)
	_check(
		_client_world.projectiles().is_empty(),
		"and the client stops drawing it"
	)
	_check(
		thrown.has(HungryEvents.Kind.THROW) and thrown.has(HungryEvents.Kind.IMPACT),
		"and both cues arrived"
	)

	# Owner-only: what you are carrying is not something an opponent should be told.
	_check(
		_client_world.monster_for(7).carried.size()
			== _server_world.monster_for(7).carried.size(),
		"and the carry list reached its owner"
	)
	_done()

func _test_interest() -> void:
	_section("interest")

	var interest := _server_net.interest as HungryInterest
	_check(interest != null, "the server uses this game's interest rule")

	if interest == null:
		_done()
		return

	var rect := interest.view_rect(CLIENT_PEER)
	_check(rect.size.x > 0.0, "which knows where the observer is")

	# A monster wide enough to fill the screen has to see further, or it can never find
	# anything worth eating.
	var small := interest.view_rect(CLIENT_PEER).size
	_server_world.monster_for(7).rider_piece().set_mass(
		9000.0, _server_world.tunables.mass_rules
	)
	var large := interest.view_rect(CLIENT_PEER).size

	_check(
		large.x > small.x,
		"and grows with the monster (%.0f -> %.0f)" % [small.x, large.x]
	)

	_server_world.monster_for(7).rider_piece().set_mass(
		HungryContent.START_MASS, _server_world.tunables.mass_rules
	)

	# Somebody on the far side of the world must not be in the snapshot at all. This is
	# the anti-cheat that works: data never sent cannot be drawn on a wallhack.
	_server_bridge.add_player(0, 99, "Far Away")
	_server_world.spawn(99, _server_world.arena.bounds.position + Vector2(60.0, 60.0))
	_server_world.spawn(7, _server_world.arena.bounds.end - Vector2(60.0, 60.0))
	_steps(20)

	var far_identity: DotNetIdentity = null

	for identity in _server_net.registry.all():
		for behaviour in identity.behaviours:
			var piece := behaviour as HungryPieceNet

			if piece != null and piece.piece != null and piece.piece.owner_id == 99:
				far_identity = identity

	_check(far_identity != null, "there is somebody on the far side of the world")

	if far_identity != null:
		_check(
			not interest._is_relevant(
				_server_net._observer_for(CLIENT_PEER), far_identity, {}
			),
			"and they are not relevant to a player at the other end"
		)
	_done()

## An administrator's blind and beacon, through the real handlers, over the link.
## A blind is its owner's screen only (7's arrives, bot 99's must not); a beacon is everybody's and
## must arrive although 99 is outside the view. Asserted on the client's own copy of each monster.
func _test_blind_and_beacon() -> void:
	_section("an admin's blind and beacon: who is told")

	var server_fn := func() -> HungryWorld: return _server_world
	var tools := HungryModTools.handlers(server_fn)
	var blind: Callable = tools[DotModTools.ACTION_BLIND]
	var beacon: Callable = tools[DotModTools.ACTION_BEACON]

	var far_monster := _server_world.monster_for(99)
	var far_piece := far_monster.pieces[0].id if far_monster != null and far_monster.piece_count() > 0 else 0
	var mine := _client_bridge.behaviour_for(_server_world.monster_for(7).pieces[0].id)
	var far_on_client := _client_bridge.behaviour_for(far_piece)

	_check(
		mine != null and mine.find_var(&"net_blind").audience == DotNetVar.Audience.OWNER
			and mine.find_var(&"net_beacon").audience == DotNetVar.Audience.EVERYONE,
		"the blind is declared owner-only and the beacon for everybody"
	)
	_check(
		far_on_client != null and _client_world.monster_for(99) != null,
		"the client knows the far player exists, from their spawn"
	)

	if mine == null or far_on_client == null or _client_world.monster_for(99) == null:
		for what in ["control", "owner", "not told", "far beacon", "relevant", "own", "off", "irrelevant"]:
			_check(false, what)
		_done()
		return

	# The negative control first: out of view, the far player's state never arrives.
	var quiet_since := far_on_client.last_state_tick
	_steps(20)
	_check(
		far_on_client.last_state_tick == quiet_since,
		"before a beacon the far player's state never reaches the client",
		"last state tick %d -> %d" % [quiet_since, far_on_client.last_state_tick]
	)

	var on_mine: DotResult = blind.call(&"7", {"on": true, "actor": "1"})
	var on_far: DotResult = blind.call(&"99", {"on": true, "actor": "1"})
	var lit: DotResult = beacon.call(&"99", {"on": true, "actor": "1"})
	_steps(30)

	_check(
		on_mine.ok and _client_world.monster_for(7).blinded,
		"the owner's client blacks its own screen out"
	)
	_check(
		on_far.ok and _server_world.monster_for(99).blinded
			and not _client_world.monster_for(99).blinded and not far_on_client.net_blind,
		"and a blind on somebody else is never sent to it",
		"the client received net_blind = %s for player 99" % str(far_on_client.net_blind)
	)
	_check(
		lit.ok and _client_world.monster_for(99).beacon,
		"while a beacon on the far player reaches it, across the arena"
	)
	_check(
		_server_bridge.behaviour_for(far_piece).identity.always_relevant
			and far_on_client.last_state_tick > quiet_since,
		"because a beaconed monster is relevant to everybody, however far away",
		"last state tick %d" % far_on_client.last_state_tick
	)
	_check(
		not _client_world.monster_for(7).beacon,
		"and the beacon lands on nobody else"
	)

	_blind_beacon_off(blind, beacon, far_piece)
	_done()

func _blind_beacon_off(blind: Callable, beacon: Callable, far_piece: int) -> void:
	var _off_mine: DotResult = blind.call(&"7", {"on": false, "actor": "1"})
	var _off_far: DotResult = blind.call(&"99", {"on": false, "actor": "1"})
	var _unlit: DotResult = beacon.call(&"99", {"on": false, "actor": "1"})
	_steps(30)

	_check(
		not _client_world.monster_for(7).blinded and not _client_world.monster_for(99).beacon,
		"turning both off reaches the client"
	)
	_check(
		not _server_bridge.behaviour_for(far_piece).identity.always_relevant,
		"and puts the far player back under the ordinary interest rules"
	)

func _test_avatar() -> void:
	_section("avatars")

	var schema := _client_bridge.avatar_schema
	_check(schema != null and schema.validate_schema().ok, "the rider schema is legal")

	var mine := DotAvatar.make(schema.id)
	mine.set_part(&"body", &"rider_blob")
	mine.set_part(&"hat", &"hat_cap")
	mine.set_colour(&"body", 0, Color(0.9, 0.2, 0.3))

	_client_bridge.publish_avatar(mine)
	_flush()
	_flush()

	var stored := _server_world.monster_for(7).avatar
	_check(
		stored != null and stored.part_in(&"body") == &"rider_blob",
		"a client's avatar reaches the server"
	)
	_check(
		stored != null and stored.digest() == mine.digest(),
		"unchanged",
		"%s vs %s" % [stored.digest() if stored != null else "-", mine.digest()]
	)

	# The server validates against the schema and loads nothing to do it. A part that is
	# not in the schema is refused rather than clamped to whatever is at the boundary.
	var forged := DotAvatar.make(schema.id)
	forged.set_part(&"body", &"rider_pip")
	forged.parts[&"cheat"] = &"nonexistent"

	var refused := schema.validate(forged, DotAvatarEntitlements.everything())
	_check(not refused.ok, "and a slot the schema does not have is refused")
	_done()

## A monster somebody else is steering has to move smoothly.
## The interpolated `net_position` must reach the simulation, not only the property, or every remote
## monster moves in 50 ms snapshot steps.
func _test_interpolation() -> void:
	_section("watching somebody else move")

	# A player with no peer: a bot, from the client's point of view an entity it does not
	# own and therefore does not predict — which is the only kind interpolation applies to.
	_server_bridge.add_player(0, 42, "Someone Else")

		# Both near the middle with room to move: a monster pushed into a wall gives identical samples
		# and an interpolation check that passes for the wrong reason.
	_server_world.spawn(7, Vector2.ZERO)
	_server_world.spawn(42, Vector2(220.0, 0.0))

	var drift := Dot2DCommand.new()
	drift.aim = Vector2.RIGHT
	drift.reach = 900.0

	for _i in range(40):
		_server_bridge.note_command(42, drift)
		_step()

	var mirrored := _client_world.monster_for(42)

	if not _check(
		mirrored != null and mirrored.piece_count() > 0,
		"the client mirrors a monster it does not own"
	):
		_done()
		return

	var behaviour: HungryPieceNet = mirrored.pieces[0].net

	_check(
		behaviour != null and behaviour.identity != null
			and not behaviour.identity.is_predicted(),
		"and does not predict it"
	)

	# The value the last snapshot carried, before any interpolation runs.
	var snapshotted := behaviour.net_position

	_client_net.interpolate_frame()
	var first := mirrored.pieces[0].position()

		# Behind the snapshot, not equal to it: rendering is one buffer in the past, so an exact match
		# would mean nothing interpolated.
	_check(
		first != snapshotted,
		"interpolation renders behind the newest snapshot (%.2f units)"
			% first.distance_to(snapshotted)
	)
	_check(
		first.distance_to(behaviour.net_position) < 0.01,
		"and reaches the piece, not just the property (%.3f apart)"
			% first.distance_to(behaviour.net_position)
	)

	_between_snapshots(mirrored, first)

	_server_bridge.remove_peer(0)
	_server_world.remove_player(42)
	_flush()
	_done()

func _between_snapshots(mirrored, first: Vector2) -> void:
	# Advance the clock without delivering a packet: render_tick comes from the clock's estimate of the
	# server tick, so the drawn position must keep moving between snapshots.
	for _i in range(6):
		_client_net.clock.advance(1.0 / float(TICK_RATE))

	_client_net.interpolate_frame()
	var second: Vector2 = mirrored.pieces[0].position()

	_check(
		second != first,
		"and keeps moving between snapshots (%.2f units)" % second.distance_to(first)
	)
	_check(
		second.distance_to(first) < 60.0,
		"by a plausible amount rather than extrapolating away (%.2f)"
			% second.distance_to(first)
	)
