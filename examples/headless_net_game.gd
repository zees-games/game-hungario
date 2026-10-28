extends "res://examples/headless_net_field.gd"

func _test_loadout() -> void:
	_section("loadouts")

	var schema := _server_bridge.loadout_schema
	_check(schema != null and schema.validate().ok, "both ends hold the same schema")

	var mine := DotLoadout.empty(schema.id)
	mine.set_item(HungryContent.SLOT_STARTER, HungryContent.ITEM_LURE)
	mine.set_item(HungryContent.SLOT_TRAIT, HungryContent.TRAIT_STURDY)

	_client_bridge.publish_loadout(mine)
	_flush()
	_flush()

	var server_monster := _server_world.monster_for(7)
	_check(
		server_monster.trait_id == HungryContent.TRAIT_STURDY,
		"a published loadout reaches the server (%s)" % server_monster.trait_id
	)
	_check(
		server_monster.starter_item() == HungryContent.ITEM_LURE,
		"with both slots (%s)" % server_monster.starter_item()
	)

	# It comes back in the join, because the trait changes how fast a monster moves and
	# the owning client predicts that movement. Two ends computing speed from different
	# loadouts is a permanent mispredict, not a rounding error.
	var client_monster := _client_world.monster_for(7)
	_check(
		client_monster.trait_id == HungryContent.TRAIT_STURDY,
		"and comes back to every client (%s)" % client_monster.trait_id
	)
	_check(
		is_equal_approx(
			client_monster.speed_multiplier(), server_monster.speed_multiplier()
		),
		"so both ends agree how fast they move (%.3f vs %.3f)" % [
			client_monster.speed_multiplier(), server_monster.speed_multiplier()
		]
	)

	# And the trade is real, on the next spawn rather than immediately: a player who could
	# change their trait mid-fight would change it the moment they were losing.
	_server_world.spawn(7)
	_check(
		_server_world.monster_for(7).mass()
			> HungryContent.START_MASS * HungryContent.trait_mass(
				HungryContent.TRAIT_NIMBLE
			),
		"and sturdy spawns bigger (%.1f)" % _server_world.monster_for(7).mass()
	)
	_check(
		_server_world.monster_for(7).carried.has(HungryContent.ITEM_LURE),
		"holding what they asked for"
	)

	_loadout_refusals(schema)
	_done()

func _loadout_refusals(schema: DotLoadoutSchema) -> void:
	# Nobody owns the greedy trait, so the server must refuse it — a client that could
	# make the server repair its way to a legal loadout can put anything in any slot.
	var cheating := DotLoadout.empty(schema.id)
	cheating.set_item(HungryContent.SLOT_STARTER, HungryContent.ITEM_PEPPER)
	cheating.set_item(HungryContent.SLOT_TRAIT, HungryContent.TRAIT_GREEDY)

	_client_bridge.publish_loadout(cheating)
	_flush()
	_flush()

	_check(
		_server_world.monster_for(7).trait_id == HungryContent.TRAIT_STURDY,
		"an unowned trait is refused rather than repaired (%s)"
			% _server_world.monster_for(7).trait_id
	)

	# A trait in the throwable slot is a different refusal for a different reason, and a
	# loadout screen shows them differently.
	var muddled := DotLoadout.empty(schema.id)
	muddled.set_item(HungryContent.SLOT_STARTER, HungryContent.TRAIT_NIMBLE)
	muddled.set_item(HungryContent.SLOT_TRAIT, HungryContent.TRAIT_NIMBLE)

	_client_bridge.publish_loadout(muddled)
	_flush()
	_flush()

	_check(
		_server_world.monster_for(7).starter_item() == HungryContent.ITEM_LURE,
		"and so is an item in the wrong slot"
	)

func _test_direction_enforced() -> void:
	_section("direction")

	# Without this any client could send every other client a spawn, a death or a
	# leaderboard. It is checked against the transport's view of the sender, never
	# against a peer id inside the payload.
	var writer := DotNetWriter.new()
	var event := HungryEvent.new(HungryEvents.Kind.DIED, HungryEvents.write_pair(7, 7))
	_server_net.messages.encode(event, writer)

	var before := _server_net.stats.direction_violations
	var refused := _server_net.receive(writer.to_bytes(), CLIENT_PEER)

	_check(not refused.ok, "a client may not send a server-to-client event")
	_check(
		_server_net.stats.direction_violations > before,
		"and it is counted as a violation"
	)
	_done()

func _test_loss() -> void:
	_section("packet loss")

	_server_world.spawn(7, Vector2.ZERO)
	_steps(10)

	# One snapshot in four on the floor. Position recovers on its own — a newer one
	# supersedes it — but anything that changes rarely would be stranded at a stale value
	# for ever without the acknowledgements the input packets carry.
	_drop_every = 4

	var command := Dot2DCommand.new()
	command.aim = Vector2(0.7, 0.7).normalized()
	command.reach = 900.0

	_steps(150, command)
	_drop_every = 0

	# Stopped, and standing on bare ground. Mass is authoritative and interpolated, so a
	# monster that is still eating is a monster whose two copies are always one crumb
	# apart — which says nothing about whether the loss was recovered from. Clearing the
	# ground under it is what makes the comparison mean "the value converged" rather than
	# "the value is moving".
	var head := _server_world.monster_for(7).rider_piece()

	for grid_id in _server_world.arena.grid.query_circle(
		head.position(), head.radius() * 6.0
	):
		if HungryField.is_edible(grid_id) and _server_world.field.take(grid_id):
			_server_world.arena.grid.remove(grid_id)

	_steps(40, Dot2DCommand.new())

	var apart := _client_world.monster_for(7).centre().distance_to(
		_server_world.monster_for(7).centre()
	)

	_check(
		_client_net.stats.snapshots_lost > 0,
		"loss was detected (%d snapshots)" % _client_net.stats.snapshots_lost
	)

	# Recovery above depends entirely on the ack header the input packets carry, and
	# the server degrades to a conservative view rather than failing when it never
	# arrives — so a bridge whose ACK_BYTES and encode_ack() disagree would still get
	# most of this section right. Ask the server whether the wiring took.
	_check(
		_server_net.peer_acks_wired(CLIENT_PEER),
		"because the client's acknowledgements are reaching the server",
		"without them the server keeps the conservative view and never re-sends"
	)
	_check(
		apart < 12.0,
		"and the client still tracks the server (%.2f units apart)" % apart
	)
	_check(
		_client_net.stats.decode_failures == 0,
		"with no decode failures"
	)

	var server_mass := _server_world.monster_for(7).mass()
	var client_mass := _client_world.monster_for(7).mass()

	_check(
		absf(server_mass - client_mass) < 1.0,
		"and the mass converged exactly once it stopped (%.1f vs %.1f)"
			% [server_mass, client_mass]
	)
	_done()

func _test_game_change() -> void:
	_section("changing the game underneath them")

	var before_pieces := _client_bridge.piece_count()
	_check(before_pieces > 0, "there is something to lose (%d pieces)" % before_pieces)

	var next := HungryWorld.new()
	next.name = "NextWorld"
	next.preset = HungryPreset.frenzy()
	next.tick_rate = TICK_RATE
	next.world_seed = SEED + 1
	next.is_authority = true
	next.register_service = false
	add_child(next)
	next.setup()
	next.start(_tick)

	var rebound := _server_bridge.rebind(next)
	_check(rebound.ok, "the bridge rebinds onto a new world", str(rebound.error))

	_flush()
	_steps(30)

	_check(
		_server_bridge.player_for_peer(CLIENT_PEER) == 7,
		"the peer is still here"
	)
	_check(
		next.monster_for(7) != null and next.monster_for(7).alive,
		"and has a monster in the new world"
	)
	_check(
		_client_world.field.seed_value() == next.field.seed_value(),
		"the client took the new field seed"
	)
	_check(
		absi(_client_world.field.alive_count() - next.field.alive_count()) <= 30,
		"and the new field (%d vs %d)" % [
			_client_world.field.alive_count(), next.field.alive_count()
		]
	)
	_check(
		_client_bridge.piece_count() == _server_bridge.piece_count(),
		"and the same pieces (%d vs %d)" % [
			_client_bridge.piece_count(), _server_bridge.piece_count()
		]
	)

	# The match entity survives a change on purpose: its net id is already known to every
	# client, and re-spawning it would make each of them mirror a second one.
	_check(
		_client_bridge.match_behaviour() != null,
		"and the match entity was not duplicated"
	)

	remove_child(next)
	next.queue_free()
	_done()

## [warren-net-1]: a round of `warrens`, and a client predicting itself against one of its
## rocks.
##
## [b]The half of the layout no single-world check can see.[/b] `headless_round` proves a
## client world pushes itself out of the same rocks (`simulate_piece` runs `block_piece`),
## and the admin section above proves a noclip is predicted through a stand-in rock. What
## neither does is the thing a player meets: the server changed to a level, the client
## built the level from the name in the hello, and the client's own monster pressed
## against a rock face for seconds, reconciled against every snapshot. A push-out that the
## replay did not repeat — or a client whose layout differed by one disc — reads as
## rubber-banding along the face, which sends the next person to the netcode.
##
## [b]And its negative control.[/b] The same window with the rock missing from the CLIENT
## only must come apart, or the first half passes because nothing was ever asked to
## disagree.
##
## [b]A split monster against the rock is measured and bounded, not held to the same
## number.[/b] `_separate` is applied live on both ends and not replayed, so while two
## pieces overlap the replay and the shown positions differ by a fraction of the overlap;
## that is the named cost in docs/netcode.md, and this is where its size is written down.
func _test_warrens_rock_converges() -> void:
	_section("a round of warrens: a client predicting itself against a rock")

	var warrens := HungryWorld.new()
	warrens.name = "WarrensWorld"
	warrens.preset = HungryPreset.warrens()
	warrens.tick_rate = TICK_RATE
	warrens.world_seed = SEED + 2
	warrens.is_authority = true
	warrens.register_service = false
	add_child(warrens)
	warrens.setup()
	warrens.start(_tick)

	var rebound := _server_bridge.rebind(warrens)

	if not _check(rebound.ok, "the bridge rebinds onto a warrens world", str(rebound.error)):
		remove_child(warrens)
		warrens.queue_free()
		_done()
		return

	_flush()

	for _i in range(TICK_RATE * 10):
		if warrens.match_node.is_live():
			break
		_step()

	_steps(20)

	_check(
		_client_world.layout.id == HungryLayout.WARRENS
			and _client_world.layout.count() == warrens.layout.count(),
		"the client built the warrens from the name in the hello",
		"%s, %d rocks against %d" % [
			_client_world.layout.id, _client_world.layout.count(), warrens.layout.count()
		]
	)

	var monster := warrens.monster_for(7)

	if not _check(monster != null and monster.alive, "and player 7 is alive in it"):
		_server_bridge.rebind(_server_world)
		remove_child(warrens)
		warrens.queue_free()
		_done()
		return

	# Outside ring rock 0, driven dead at its centre: pressed against the face for the whole
	# window. Four degrees off, which the round suite uses to prove a monster slides in,
	# leaves the face after 41 ticks here, and a window mostly spent in the open measures
	# the open.
	var rock: Vector3 = warrens.layout.blocks[0]
	var rock_at := Vector2(rock.x, rock.y)
	var centre := warrens.arena.bounds.get_center()
	# Sixty units off the face, so the window is spent pressed rather than approaching.
	var start := rock_at + (rock_at - centre).normalized() * (rock.z + 60.0)
	var command := Dot2DCommand.new()
	command.aim = (rock_at - start).normalized()
	command.reach = 900.0

	_put(warrens, start)
	var pressed := _rock_pressed(warrens, start, command, rock)

	_rock_naive(warrens, start, command, rock, pressed)

	_rock_split(warrens, start, command, rock)

	# Back onto the world every later line of this file expects.
	_server_bridge.rebind(_server_world)
	_flush()
	remove_child(warrens)
	warrens.queue_free()
	_done()

func _rock_pressed(warrens: HungryWorld, start: Vector2, command: Dot2DCommand, rock: Vector3) -> Dictionary:
	var pressed := _rock_window(warrens, 150, command, rock)
	print("  measured: against a rock, worst %.2f over %d ticks; %d in contact, worst %.2f and mean %.2f there; deepest %.2f" % [
		float(pressed["worst"]), int(pressed["ticks"]), int(pressed["contact"]),
		float(pressed["contact_worst"]), float(pressed["contact_mean"]), float(pressed["deepest"])
	])
	_check(
		int(pressed["contact"]) > 100,
		"the monster spent the window pressed against the rock",
		"%d ticks in contact" % int(pressed["contact"])
	)
	_check(
		float(pressed["deepest"]) > -2.0,
		"the server never let it into the rock",
		"deepest %.2f" % float(pressed["deepest"])
	)
	# [b]On the ticks in contact, because that is where a push-out that was not replayed
	# would show.[/b] Over the whole window both this and the control below are bounded by
	# the snapshot corrections — 3.6 and 7.5 units when this was first measured, too close
	# to call — while pressed against the face the replay either agrees with the server to
	# a rounding error or is corrected on every snapshot.
	_check(
		float(pressed["contact_mean"]) < 1.0,
		"and while it was pressed there the client agreed with the server to within a unit",
		"worst %.2f, mean %.2f in contact; %.2f over the whole window"
			% [float(pressed["contact_worst"]), float(pressed["contact_mean"]), float(pressed["worst"])]
	)
	return pressed

func _rock_naive(warrens: HungryWorld, start: Vector2, command: Dot2DCommand, rock: Vector3, pressed: Dictionary) -> void:
	# The negative control: the rock gone from the client's world only.
	_put(warrens, start)
	_client_world.layout = HungryLayout.none()
	var naive := _rock_window(warrens, 150, command, rock)
	_client_world.adopt_layout(HungryLayout.WARRENS)
	print("  measured: the rock missing from the client, %d in contact, worst %.2f and mean %.2f there" % [
		int(naive["contact"]), float(naive["contact_worst"]), float(naive["contact_mean"])
	])
	_check(
		float(naive["contact_mean"]) > 2.0
			and float(naive["contact_mean"]) > float(pressed["contact_mean"]) * 4.0 + 0.5,
		"a client that does not know the rock is corrected all along its face",
		"naive mean %.2f in contact against %.2f — if this passes quietly, the check above proves nothing"
			% [float(naive["contact_mean"]), float(pressed["contact_mean"])]
	)

func _rock_split(warrens: HungryWorld, start: Vector2, command: Dot2DCommand, rock: Vector3) -> void:
	# Split against the face: the pieces overlap, and `_separate` is not replayed.
	_put(warrens, start)
	warrens.feed_player(7, 200.0)
	_steps(10)
	var split := Dot2DCommand.new()
	split.aim = command.aim
	split.reach = command.reach
	split.buttons = Dot2DCommand.BUTTON_SPLIT
	_step(split)
	var halves := _rock_window(warrens, 120, command, rock)
	print("  measured: split against the rock, %d pieces, worst %.2f (%d ticks over 8), last %.2f" % [
		warrens.monster_for(7).piece_count(), float(halves["worst"]), int(halves["over"]),
		float(halves["final"])
	])
	_check(
		warrens.monster_for(7).piece_count() >= 2,
		"a monster that splits against the rock is in pieces",
		"%d" % warrens.monster_for(7).piece_count()
	)
	_check(
		float(halves["final"]) < 8.0,
		"and its client comes back to the server once the pieces are apart",
		"worst %.2f on the way, %.2f at the end" % [float(halves["worst"]), float(halves["final"])]
	)
