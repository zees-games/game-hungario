extends DotGameCheckSuite

const HungryContent := preload("../game/hungry_content.gd")

const HungryEvent := preload("../game/net/hungry_event.gd")

const HungryEvents := preload("../game/net/hungry_events.gd")

const HungryField := preload("../game/hungry_field.gd")

const HungryHazards := preload("../game/hungry_hazards.gd")

const HungryHunters := preload("../game/hungry_hunters.gd")

const HungryInterest := preload("../game/net/hungry_interest.gd")

const HungryLayout := preload("../game/hungry_layout.gd")

const HungryModTools := preload("../game/hungry_mod_tools.gd")

const HungryNetBridge := preload("../game/net/hungry_net_bridge.gd")

const HungryServerConfig := preload("../game/hungry_server_config.gd")

const HungryNetCommand := preload("../game/net/hungry_net_command.gd")

const HungryPieceNet := preload("../game/net/hungry_piece_net.gd")

const HungryPreset := preload("../game/hungry_preset.gd")

const HungryProjectile := preload("../game/hungry_projectile.gd")

const HungryServices := preload("../game/hungry_services.gd")

const HungryWorld := preload("../game/hungry_world.gd")

const HungryRequest := preload("../game/net/hungry_request.gd")

## Runs a server and a client in one process and checks the netcode works; exits non-zero on failure.
## Both halves share a loopback that can delay and drop packets, the only way to reproduce
## interpolation and loss twice. The real socket is `sandbox.tscn`'s job.

const TICK_RATE := 60

const SNAPSHOT_RATE := 20

const SEED := 20260828

const CLIENT_PEER := 2

var _server_world: HungryWorld = null

var _client_world: HungryWorld = null

var _server_net: DotNetManager = null

var _client_net: DotNetManager = null

var _server_bridge: HungryNetBridge = null

var _client_bridge: HungryNetBridge = null

## Payloads in flight, so loss and delay can be simulated.
var _to_client: Array[Dictionary] = []

var _to_server: Array[Dictionary] = []

## Drop one snapshot in this many. Zero drops nothing.
var _drop_every: int = 0

var _snapshot_count: int = 0

var _tick: int = 0

## Sections entered, and sections that ran to their last line.
## A runtime error aborts a section silently, so the check total alone cannot show a check that
## never ran.
var _entered := 0

var _completed := 0

## Opens a section. Pair with [method _done] on every path out of it.
func _section(title: String) -> void:
	_entered += 1
	print("")
	print(title)

func _done() -> void:
	_completed += 1

func _make_world(authority: bool, scope: StringName) -> HungryWorld:
	var world := HungryWorld.new()
	world.name = "World" if authority else "ClientWorld"
	world.preset = HungryPreset.classic()
	world.tick_rate = TICK_RATE
	world.world_seed = SEED
	world.is_authority = authority
	world.register_service = true
	world.service_scope = scope
	add_child(world)
	world.setup()

	if authority:
		world.start(0)

	return world

func _make_manager(server: bool, scope: StringName, peer_id: int) -> DotNetManager:
	var manager := DotNetManager.new()
	manager.name = "Server" if server else "Client"
	manager.is_server = server
	manager.local_peer_id = peer_id
	manager.service_scope = scope
	manager.auto_tick = false
	manager.config_file = ""

	var config := DotNetConfig.new()
	config.tick_rate = TICK_RATE
	config.snapshot_rate = SNAPSHOT_RATE
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 120
	config.world_extent = Dot2DNetSync.WORLD_EXTENT
	config.reconcile_position_epsilon = HungryNetBridge.RECONCILE_EPSILON
	manager.config = config

	add_child(manager)
	manager.setup()
	return manager

func _build() -> bool:
	print("")
	print("bringing both halves up")

	# Two subtrees so the two link nodes are not siblings with the same name. Nothing here
	# touches the multiplayer API — the loopback stands in for it — but the tree still has
	# to be legal.
	var server_side := Node.new()
	server_side.name = "ServerSide"
	add_child(server_side)

	var client_side := Node.new()
	client_side.name = "ClientSide"
	add_child(client_side)

	_server_world = _make_world(true, &"server")
	_client_world = _make_world(false, &"client")

	_server_net = _make_manager(true, &"server", 1)
	_client_net = _make_manager(false, &"client", CLIENT_PEER)

	_server_bridge = HungryNetBridge.new()
	_server_bridge.name = "ServerBridge"
	add_child(_server_bridge)

	_client_bridge = HungryNetBridge.new()
	_client_bridge.name = "ClientBridge"
	add_child(_client_bridge)

	var server_attached := _server_bridge.attach(_server_world, _server_net, server_side)
	var client_attached := _client_bridge.attach(_client_world, _client_net, client_side)

	if not _check(server_attached.ok, "the server bridge attaches", str(server_attached.error)):
		return false

	if not _check(client_attached.ok, "the client bridge attaches", str(client_attached.error)):
		return false

	# A world and a manager that disagree about who is authoritative would resolve
	# everybody's eating or nobody's, silently. The bridge refuses instead.
	var wrong := HungryNetBridge.new()
	add_child(wrong)
	var refused := wrong.attach(_client_world, _server_net, server_side)
	_check(not refused.ok, "and a mismatched pair is refused")
	remove_child(wrong)
	wrong.queue_free()

	_server_net.messages.seal()
	_client_net.messages.seal()

	_check(
		_server_net.messages.schema_hash() == _client_net.messages.schema_hash(),
		"the two ends agree on the message schema",
		"%s vs %s" % [
			_server_net.messages.schema_hash(), _client_net.messages.schema_hash()
		]
	)

	_server_bridge.link.loopback = _on_server_send
	_client_bridge.link.loopback = _on_client_send

	_server_net.start()
	_client_net.start()

	return true

func _teardown() -> void:
	for node in [
		_server_bridge, _client_bridge, _server_net, _client_net,
		_server_world, _client_world,
	]:
		if node != null and is_instance_valid(node):
			remove_child(node)
			node.queue_free()


func _on_server_send(method: StringName, peer_id: int, payload: PackedByteArray) -> void:
	if method == &"snapshot":
		_snapshot_count += 1

		# Dropped rather than delayed: a lost snapshot is the case the acked baselines
		# exist for, and the only way to know they work is to lose some.
		if _drop_every > 0 and _snapshot_count % _drop_every == 0:
			return

	if peer_id != 0 and peer_id != CLIENT_PEER:
		return

	_to_client.append({"method": method, "payload": payload})

func _on_client_send(method: StringName, _peer_id: int, payload: PackedByteArray) -> void:
	_to_server.append({"method": method, "payload": payload})

func _flush() -> void:
	# Copied and cleared first: delivering an event can cause a reply, and appending to
	# the array being walked would deliver it inside the same flush.
	var to_client := _to_client.duplicate()
	var to_server := _to_server.duplicate()
	_to_client.clear()
	_to_server.clear()

	for entry in to_client:
		_client_bridge.link.deliver(entry["method"], 1, entry["payload"])

	for entry in to_server:
		_server_bridge.link.deliver(entry["method"], CLIENT_PEER, entry["payload"])

## How far ahead of the server the client stamps its inputs, roughly.
## A command for tick N must reach the server before it simulates N; [DotNetClock]'s input margin
## provides that, so the harness only drives the clock.
const INPUT_LEAD := 2

## One tick of both halves, with the wire drained in between.
func _step(command: Dot2DCommand = null) -> void:
	_tick += 1
	_server_bridge.server_tick(_tick)
	_flush()
	_client_step(command)
	_flush()

## One tick of the client, driven as `HungryClient._physics_process` drives it: advance the clock,
## predict and stamp every tick it moved through. Returns the last tick predicted, or -1.
func _client_step(command: Dot2DCommand = null) -> int:
	var clock := _client_net.clock
	var ticks := clock.advance(1.0 / float(TICK_RATE))
	var last := -1

	for i in range(ticks):
		if not clock.is_synced():
			continue
		last = clock.input_tick() - (ticks - 1 - i)
		_client_bridge.client_tick(
			last, command if command != null else Dot2DCommand.new()
		)

	return last

func _steps(count: int, command: Dot2DCommand = null) -> void:
	for _i in range(count):
		_step(command)


func _rock_at(at: Vector2) -> HungryLayout:
	var layout := HungryLayout.none()
	layout.blocks = PackedVector3Array([Vector3(at.x, at.y, 40.0)])
	return layout

## Puts monster 7 back at [param at] on the server and lets both ends settle, so the next
## window starts from agreement rather than from the last one's disagreement.
func _back_to(at: Vector2) -> void:
	for piece in _server_world.monster_for(7).pieces:
		piece.state.position = at
		piece.state.velocity = Vector2.ZERO
	_steps(20)

## [param ticks] more ticks holding [param command], comparing where the client predicted
## its monster at each tick with where the server had it at the SAME tick:
## `{worst, over}`, the second counting ticks more than eight units apart.
func _admin_window(ticks: int, command: Dot2DCommand) -> Dictionary:
	var client_at := {}
	var server_at := {}

	for _i in range(ticks):
		_tick += 1
		_server_bridge.server_tick(_tick)
		server_at[_tick] = _server_world.monster_for(7).centre()
		_flush()
		var predicted := _client_step(command)
		client_at[predicted] = _client_world.monster_for(7).centre()
		_flush()

	var worst := 0.0
	var over := 0
		# The smallest gap in the last two thirds of the window is the floor a client returns to; a
		# client that walks away has a climbing floor, which the worst gap cannot tell from one late snapshot.
		# The first third is skipped: the client has not started moving.
	var early := INF
	var late := INF
	var ordered: Array = server_at.keys()
	ordered.sort()
	var third := ordered.size() / 3.0

	for index in range(ordered.size()):
		var tick: int = ordered[index]
		if not client_at.has(tick):
			continue
		var gap: float = (client_at[tick] as Vector2).distance_to(server_at[tick] as Vector2)
		worst = maxf(worst, gap)
		if index >= 2.0 * third:
			late = minf(late, gap)
		elif index >= third:
			early = minf(early, gap)
		if gap > 8.0:
			over += 1

	return {"worst": worst, "over": over, "early": early, "late": late}

## Puts monster 7 at [param at] in [param world], still, and lets both ends agree.
func _put(world: HungryWorld, at: Vector2) -> void:
	for piece in world.monster_for(7).pieces:
		piece.state.position = at
		piece.state.velocity = Vector2.ZERO
	_steps(30)

## [method _admin_window] against a named world and a rock: where the client predicted
## monster 7 at each tick against where [param world] had it at the SAME tick, and how many
## ticks the server's monster spent touching [param rock].
func _rock_window(world: HungryWorld, ticks: int, command: Dot2DCommand, rock: Vector3) -> Dictionary:
	var client_at := {}
	var server_at := {}
	var contact := 0
	var deepest := INF
	var at := Vector2(rock.x, rock.y)
	var touching := {}

	for _i in range(ticks):
		_tick += 1
		_server_bridge.server_tick(_tick)
		server_at[_tick] = world.monster_for(7).centre()

		for piece in world.monster_for(7).pieces:
			var gap := piece.position().distance_to(at) - rock.z - piece.radius()
			deepest = minf(deepest, gap)

			if gap < 1.0:
				contact += 1
				touching[_tick] = true
				break

		_flush()
		var predicted := _client_step(command)
		client_at[predicted] = _client_world.monster_for(7).centre()
		_flush()

	var worst := 0.0
	var over := 0
	var final := 0.0
	var measured := 0
	var contact_worst := 0.0
	var contact_sum := 0.0
	var contact_measured := 0

	for tick in server_at:
		if not client_at.has(tick):
			continue
		var gap: float = (client_at[tick] as Vector2).distance_to(server_at[tick] as Vector2)
		worst = maxf(worst, gap)
		final = gap
		measured += 1
		if gap > 8.0:
			over += 1
		if touching.has(tick):
			contact_worst = maxf(contact_worst, gap)
			contact_sum += gap
			contact_measured += 1

	return {
		"worst": worst, "over": over, "final": final, "ticks": measured,
		"contact": contact, "deepest": deepest, "contact_worst": contact_worst,
		"contact_mean": contact_sum / float(maxi(1, contact_measured)),
	}
