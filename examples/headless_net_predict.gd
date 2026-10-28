extends "res://examples/headless_net_wire.gd"

func _test_handshake() -> void:
	_section("a client joins")

	# The client asking is what admits it. Between dot-server's signon finishing and the
	# client building its scene there is a window in which it has no node for an RPC to
	# land on, so everything sent in it is lost and logged as a missing node.
	#
	# Asked FIRST, as over ENet with loss: a client is PLAYING by its own reckoning once it
	# has sent `loaded`, on another channel, so its READY can reach the server before its
	# seat. The server sends nothing on it, keeps it, and answers it when the seat comes; a
	# bridge that dropped it never told this client anything.
	_client_bridge.ask_for_world()
	_flush()
	_flush()
	_check(
		not _server_net.peers().has(CLIENT_PEER) and _client_bridge.local_player_id != 7,
		"a READY before the seat admits nothing yet"
	)

	var added := _server_bridge.add_player(CLIENT_PEER, 7, "Ada")
	_check(added.ok, "the server adds them", str(added.error))
	_flush()
	_flush()

	_check(_server_net.peers().has(CLIENT_PEER), "asking admits them")

	_check(
		_client_bridge.local_player_id == 7,
		"and the client learns who it is (%d)" % _client_bridge.local_player_id
	)
	_check(
		_client_world.monster_for(7) != null,
		"and has a monster for itself"
	)
	_check(
		_client_world.field.seed_value() == _server_world.field.seed_value(),
		"and the same field seed"
	)
	_check(
		_client_bridge.avatar_pack_url == _server_bridge.avatar_pack_url,
		"and the same rider content, if there is any (%s)"
			% ("none" if _client_bridge.avatar_pack_url == ""
				else _client_bridge.avatar_pack_url)
	)
	_check(
		_client_world.field.alive_count() == _server_world.field.alive_count(),
		"and the same food (%d vs %d)" % [
			_client_world.field.alive_count(), _server_world.field.alive_count()
		]
	)

	_handshake_field_matches()

	_steps(4)

	_check(
		_client_bridge.piece_count() == _server_bridge.piece_count(),
		"the piece is mirrored (%d vs %d)" % [
			_client_bridge.piece_count(), _server_bridge.piece_count()
		]
	)

	var mine := _client_world.monster_for(7)
	_check(mine != null and mine.alive, "and the client's monster is alive")

	var predicted := _client_net.registry.predicted()
	_check(
		predicted.size() == mine.piece_count(),
		"and the client predicts every piece it owns (%d)" % predicted.size()
	)
	_done()

func _handshake_field_matches() -> void:
	# The whole point of a seed: a client that received eleven hundred positions would
	# have paid about 5 kB for what an integer bought.
	var mismatched := 0

	for grid_id in _server_world.field.alive_ids():
		if _client_world.field.position_of(grid_id).distance_to(
			_server_world.field.position_of(grid_id)
		) > 0.001:
			mismatched += 1

	_check(
		mismatched == 0,
		"and every crumb is in the same place without a position being sent"
	)

func _test_replication() -> void:
	_section("state")

	var command := Dot2DCommand.new()
	command.aim = Vector2.RIGHT
	command.reach = 800.0

	var before := _server_world.monster_for(7).centre()
	_steps(90, command)

	var server_at := _server_world.monster_for(7).centre()
	var client_at := _client_world.monster_for(7).centre()

	_check(
		server_at.distance_to(before) > 100.0,
		"the server simulated movement (%.0f units)" % server_at.distance_to(before)
	)
	_check(
		client_at.distance_to(server_at) < 6.0,
		"and the client agrees within six units (%.2f)"
			% client_at.distance_to(server_at)
	)

	# The radius is derived from the received mass, never replicated: two copies of one
	# number eventually disagree by a rounding error, and then a monster's eat radius and
	# its drawn radius are in different places.
	var server_piece := _server_world.monster_for(7).rider_piece()
	var client_piece := _client_world.monster_for(7).rider_piece()

	_check(
		client_piece != null
			and absf(client_piece.radius() - server_piece.radius()) < 0.5,
		"and the radius follows the mass on both ends"
	)
	_check(
		client_piece != null
			and (client_piece.state.flags & HungryContent.FLAG_RIDER) != 0,
		"and the rider flag arrived"
	)
	_done()

func _test_prediction() -> void:
	_section("prediction")

	# [b]It is not zero in this game, and that is correct.[/b] A client predicts where its
	# monster went; it does not predict what its monster ate, because eating is the
	# authority's and a client that resolved its own would be a client that decides what
	# it weighs. Every crumb swallowed is therefore a mass the client did not have, a
	# speed it did not use, and a small correction on the next snapshot.
	#
	# What it must not be is [i]most[/i] snapshots. This read 0.500 while the bridge was
	# reconciling a second time on top of the reconciliation
	# [method DotNetManager.receive_snapshot] had already done — replaying the same inputs
	# twice against values that had already been rewound. Removing that pass took it to
	# 0.03, and neither number produced an error or a failed check anywhere else.
	var rate := _client_net.predictor.correction_rate()
	_check(
		rate < 0.25,
		"corrections stay rare (%.3f of snapshots)" % rate,
		"consistently high means the two simulations disagree, and no smoothing fixes that"
	)

	# The client's own monster must respond on the tick the input is given, not a round
	# trip later. Measured against the client's own previous position, because that is
	# what the player sees.
	var command := Dot2DCommand.new()
	command.aim = Vector2.UP
	command.reach = 900.0

	var before := _client_world.monster_for(7).centre()
	_client_step(command)
	var after := _client_world.monster_for(7).centre()

	_check(
		after.distance_to(before) > 0.5,
		"the client moves on the tick it presses (%.2f units)"
			% after.distance_to(before)
	)

	_steps(30, command)
	_check(
		_client_world.monster_for(7).centre().distance_to(
			_server_world.monster_for(7).centre()
		) < 8.0,
		"and stays with the server afterwards"
	)

	_prediction_same_tick(command)
	_done()

func _prediction_same_tick(command: Dot2DCommand) -> void:
	# Tick N against tick N: the correction rate cannot see a client a whole tick ahead, because a
	# constant offset reconciles to itself. One tick of this monster's motion is 2 units.
	var server_at := {}
	var client_at := {}

	for _i in range(30):
		_tick += 1
		_server_bridge.server_tick(_tick)
		server_at[_tick] = _server_world.monster_for(7).centre()
		_flush()
		var predicted := _client_step(command)
		client_at[predicted] = _client_world.monster_for(7).centre()
		_flush()

	var gaps: Array[float] = []

	for tick: int in client_at.keys():
		if server_at.has(tick):
			gaps.append((client_at[tick] as Vector2).distance_to(server_at[tick] as Vector2))

	gaps.sort()
	var median := gaps[gaps.size() / 2] if not gaps.is_empty() else INF
	_check(
		gaps.size() >= 20 and median < 0.5,
		"and predicts tick N where the server simulated tick N (median %.3f over %d ticks)"
			% [median, gaps.size()]
	)

## Your own monster is drawn between its ticks at the clock's render alpha, and a physics
## frame the clock's drift leaves with no tick, or with two, is drawn through: frames drawn a
## third of the way through a tick, with one of each forced, beside a control drawn at that
## third alone (the engine's fraction, how it would be drawn without the clock). A frame is
## stalled under half the steady step, doubled over one and a half.
func _test_drawn_through_a_slip() -> void:
	_section("your own monster is drawn through a frame with no tick, or two")
	var command := Dot2DCommand.new()
	command.aim = Vector2.RIGHT
	command.reach = 900.0
	_steps(20, command)

	var clock := _client_net.clock
	var dt := 1.0 / float(TICK_RATE)
	var piece := _client_world.monster_for(7).rider_piece()
	var drawn: Array[Vector2] = []
	var control: Array[Vector2] = []
	var frame := func() -> void:
		drawn.append(piece.drawn_position(clock.render_alpha(0.33, dt)))
		control.append(piece.drawn_position(0.33))

	for _i in range(6):
		_step(command)
		frame.call()
	# A physics frame with no tick: the clock's time comes up short of one.
	var _none := clock.advance(0.0)
	frame.call()
	for _i in range(6):
		_step(command)
		frame.call()
	# A physics frame with two: the server runs its extra tick, and the client's clock is
	# handed a tick's time more before the frame's own.
	_tick += 1
	_server_bridge.server_tick(_tick)
	_flush()
	clock.set(&"_accumulator", float(clock.get(&"_accumulator")) + dt)
	_step(command)
	frame.call()
	for _i in range(6):
		_step(command)
		frame.call()

	var judge := func(points: Array[Vector2]) -> Array:
		var steps: Array[float] = []
		for i in range(1, points.size()):
			steps.append(points[i].distance_to(points[i - 1]))
		var sorted := steps.duplicate()
		sorted.sort()
		var steady: float = sorted[sorted.size() / 2]
		var stalled := 0
		var doubled := 0
		for s in steps:
			if s < steady * 0.5:
				stalled += 1
			elif s > steady * 1.5:
				doubled += 1
		return [stalled, doubled, steady]

	var on_clock: Array = judge.call(drawn)
	var alone: Array = judge.call(control)
	_check(
		int(alone[0]) >= 1 and int(alone[1]) >= 1,
		"the control (a fraction alone) stalls on the frame with no tick and doubles on the one with two",
		"%d stalled, %d doubled" % [alone[0], alone[1]]
	)
	_check(
		int(on_clock[0]) == 0 and int(on_clock[1]) == 0,
		"drawn at the clock's render alpha, no frame stalls or doubles (steady %.2f units a frame)" % float(on_clock[2]),
		"%d stalled, %d doubled" % [on_clock[0], on_clock[1]]
	)
	# Standing still while the clock takes the forced tick back up, so the next section
	# starts from a settled clock.
	_steps(90)
	_done()

## An administrator noclips and freezes a monster on the server, and the monster's own
## client has to PREDICT both.
##
## [b]The symptom this exists for is rubber-banding, and no server-side check can see
## it.[/b] So each window records, tick by tick, where the client predicted its monster and
## where the server put it, and compares the two at the same tick — once the shipped way,
## through the moderator handlers and [Dot2DAdminModifiers], and once the naive way, a
## server-only change the client is never told about. The naive half has to DIVERGE: a
## window in which the client was never asked to disagree would pass the first half too.
## Game-arena's `headless_net` is the same shape for the first-person motor.
func _test_admin_is_predicted() -> void:
	_section("an admin's noclip and freeze, predicted by the client they happen to")

	var server_fn := func() -> HungryWorld: return _server_world
	var tools := HungryModTools.handlers(server_fn)
	var noclip: Callable = tools[DotModTools.ACTION_NOCLIP]
	var freeze: Callable = tools[DotModTools.ACTION_FREEZE]

	# A rock on the monster's path, in BOTH worlds — the client predicts around the level's
	# rocks, which is the whole reason a server-only noclip would disagree with it.
	var from := _server_world.monster_for(7).centre()
	var heading := (_server_world.arena.bounds.get_center() - from)
	heading = heading.normalized() if heading.length() > 400.0 else Vector2.RIGHT
	var rock := from + heading * 140.0
	_server_world.layout = _rock_at(rock)
	_client_world.layout = _rock_at(rock)

	var command := Dot2DCommand.new()
	command.aim = heading
	command.reach = 900.0

	var on: DotResult = noclip.call(&"7", {"on": true})
	_check(on.ok, "the moderator handler noclips player 7 on the server", str(on.error))

	var shipped := _admin_window(90, command)

	var client_piece := _client_world.monster_for(7).rider_piece()
	_check(
		client_piece != null and Dot2DAdminModifiers.is_noclipped(client_piece.state),
		"the client learned it from the snapshots"
	)
	# Past the rock's CENTRE, which a monster the rock stopped can never reach: it is held
	# the rock's radius plus its own short of it.
	var past := (_server_world.monster_for(7).centre() - rock).dot(heading)
	_check(past > 0.0, "the server's monster went through the rock", "%.1f units past its centre" % past)
	_check(
		float(shipped["worst"]) < 8.0,
		"and the client predicted it through, never more than eight units from the server",
		"worst %.2f" % float(shipped["worst"])
	)

	# The same move made the naive way: noclip off, and the rock taken out of the SERVER's
	# world only — a server that lets somebody through without telling the client why.
	var _off: DotResult = noclip.call(&"7", {"on": false})
	_back_to(from)
	_server_world.layout = HungryLayout.none()
	var naive := _admin_window(90, command)
	print("  measured: noclip shipped worst %.2f (%d ticks over 8); naive worst %.2f (%d ticks over 8)" % [
		float(shipped["worst"]), int(shipped["over"]), float(naive["worst"]), int(naive["over"])
	])
	_check(
		float(naive["worst"]) > 30.0,
		"a server-only noclip is one the client does not predict: the rubber band",
		"naive worst %.2f — if this passes quietly, the checks above prove nothing" % float(naive["worst"])
	)

	_server_world.layout = HungryLayout.none()
	_client_world.layout = HungryLayout.none()
	_back_to(from)

	_admin_freeze(freeze, command)

	_back_to(from)
	_done()

func _admin_freeze(freeze: Callable, command: Dot2DCommand) -> void:
	# Freeze: held still with the pointer at full reach, on both ends.
	var frozen: DotResult = freeze.call(&"7", {"on": true})
	_check(frozen.ok, "the moderator handler freezes player 7", str(frozen.error))
	var held_at := _server_world.monster_for(7).centre()
	var still := _admin_window(60, command)
	_check(
		_server_world.monster_for(7).centre().distance_to(held_at) < 1.0,
		"the server holds the monster where it was",
		"%.2f units" % _server_world.monster_for(7).centre().distance_to(held_at)
	)
	_check(
		float(still["worst"]) < 1.0,
		"and the client never predicted it moving",
		"worst %.2f" % float(still["worst"])
	)

	# Naive: the server alone refuses to move anybody. dot-net rewinds a predicted entity to the server's
	# whole state, so this is an ordinary rubber band: the client leads, every snapshot pulls it back.
	var _thaw: DotResult = freeze.call(&"7", {"on": false})
	var speed := _server_world.tunables.max_speed
	_server_world.tunables.max_speed = 0.0
	var naive_freeze := _admin_window(60, command)
	_server_world.tunables.max_speed = speed
	print("  measured: freeze shipped worst %.2f; naive worst %.2f (%d ticks over 8), pulled back to %.2f in the middle third and %.2f in the last" % [
		float(still["worst"]), float(naive_freeze["worst"]), int(naive_freeze["over"]),
		float(naive_freeze["early"]), float(naive_freeze["late"])
	])
	_check(
		float(naive_freeze["worst"]) > 2.0,
		"a server-only freeze is one the client predicts its way out of: the rubber band",
		"naive worst %.2f — if this passes quietly, the checks above prove nothing" % float(naive_freeze["worst"])
	)
	_check(
		float(naive_freeze["late"]) <= float(naive_freeze["early"]) + 1.0,
		"and one it is pulled back from, every snapshot, rather than walks away from",
		"pulled back to %.2f in the middle third, only to %.2f in the last" % [
			float(naive_freeze["early"]), float(naive_freeze["late"])
		]
	)
