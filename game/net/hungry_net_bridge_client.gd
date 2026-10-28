extends "res://game/net/hungry_net_bridge_state.gd"

## Mirrors the match entity on a client. Called once, from the first HELLO.
func _mirror_match_entity(net_id: int) -> DotResult:
	if _match_identity != null:
		return DotResult.success(_match_identity)

	var root := Node2D.new()
	root.name = "Match"
	_entities.add_child(root)

	_match_behaviour = HungryMatchNet.new()
	_match_behaviour.name = "Net"
	_match_behaviour.world = world
	_match_behaviour.bridge = self
	root.add_child(_match_behaviour)

	_match_identity = DotNetIdentity.new()
	_match_identity.name = "Identity"
	_match_identity.owner_peer_id = 1
	_match_identity.always_relevant = true
	root.add_child(_match_identity)

	return net.registry.register(_match_identity, net_id, net.clock.tick, net.config)

## Builds the node, behaviour and identity that make a piece replicate.
func _build_piece_entity(piece: HungryPiece, peer_id: int) -> DotNetIdentity:
	var root := Node2D.new()
	root.name = "Piece%d" % piece.id
	root.position = piece.position()
	_entities.add_child(root)

	var behaviour := HungryPieceNet.new()
	behaviour.name = "Net"
	behaviour.piece = piece
	behaviour.bridge = self
	root.add_child(behaviour)

	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = peer_id
	# SHARED, not SERVER: the server stays authoritative and corrects, and the owning
	# client predicts. `DotNetIdentity.is_predicted()` is false for any other authority,
	# so SERVER would mean a player seeing their own monster a full round trip late —
	# noticeable at 80 ms and unplayable at 150.
	identity.authority = DotNetIdentity.Authority.SHARED
	identity.interest_tags = PackedStringArray(["piece"])
	root.add_child(identity)

	piece.net = behaviour
	_behaviours[piece.id] = behaviour

	return identity

## One client tick: record the local command, predict, separate.
##
## The command is recorded into the manager's input history [i]before[/i] predicting,
## because reconciliation replays that history — an input the buffer never saw is a tick
## the replay cannot reproduce, and the correction is then measured against a state the
## server never computed.
func client_tick(tick: int, command: Dot2DCommand) -> void:
	if net == null or net.is_server or world == null:
		return

	_tick = tick

	if _client_ticked_for != tick:
		_client_ticked_for = tick
		world.client_tick(tick)

	var monster := local_monster()

	if monster != null and command != null:
		monster.last_command = command.duplicate_command()

	var packet := HungryNetCommand.new()
	packet.tick = tick
	packet.delta = net.clock.tick_duration()
	packet.command = command if command != null else Dot2DCommand.new()

	net.local_inputs().push(packet)

	if link != null:
		# The acknowledgement goes in front because it is fixed width. A bit-packed
		# command is not, so a reader that had to skip it would have to decode it first.
		var payload := net.encode_ack()
		var writer := DotNetWriter.new()
		DotNetInput.write_batch(writer, _input_copies(packet))
		payload.append_array(writer.to_bytes())
		link.send_input(payload)

	for identity in net.registry.predicted():
		for behaviour in identity.behaviours:
			behaviour._net_simulate(tick, net.clock.tick_duration())

	world.separate_local(monster, net.clock.tick_duration())

## Advances one predicted piece. Called from [method HungryPieceNet._net_simulate].
func predict_piece(piece: HungryPiece, tick: int, delta: float) -> void:
	if _live_world() == null or piece == null:
		return

	var monster := world.monster_for(piece.owner_id)
	world.simulate_piece(
		piece,
		monster,
		monster.last_command if monster != null else null,
		delta,
		tick
	)


## Applies a snapshot. Client side.
##
## [b]Reconciliation is [DotNetManager]'s, not this file's.[/b]
## [method DotNetManager.receive_snapshot] already routes a predicted entity's state to
## [method DotNetPredictor.reconcile] instead of applying it — applying it directly would
## undo everything predicted since — and acknowledges the inputs it covers. A second pass
## here would reconcile against values that had already been reconciled and replay the
## same inputs twice, turning one correction into two.
func receive_snapshot(payload: PackedByteArray) -> DotResult:
	if net == null or net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only a client receives these.")

	if rtt_source.is_valid():
		net.stats.note_rtt(float(rtt_source.call()))

	return net.receive_snapshot(payload)

## [param packet] and the commands before it from the local replay history, oldest first,
## for one input packet. See [constant INPUT_COPIES].
func _input_copies(packet: DotNetInput) -> Array:
	var batch: Array = Array(net.local_inputs().recent(INPUT_COPIES, packet.tick - 1))
	batch = batch.slice(maxi(0, batch.size() - (INPUT_COPIES - 1)))
	batch.append(packet)
	return batch

func _on_event(message: DotNetMessage) -> void:
	var event := message as HungryEvent

	if event == null or world == null:
		return

	var reader := event.reader()

	match event.kind:
		HungryEvents.Kind.HELLO:
			_apply_hello(reader)

		HungryEvents.Kind.JOIN:
			_apply_join(reader)

		HungryEvents.Kind.LEAVE:
			var player_id := HungryEvents.read_player(reader)
			world.remove_player(player_id)
			roster_changed.emit(player_id)

		HungryEvents.Kind.CHAT:
			var wire := HungryEvents.read_chat(reader)

			if bool(wire["ok"]):
				chat_received.emit(wire)

		HungryEvents.Kind.HUNTER:
			var hunter := HungryEvents.read_hunter(reader)

			if bool(hunter["ok"]):
				hunter_received.emit(hunter)

		HungryEvents.Kind.HAZARD:
			var hazard := HungryEvents.read_hazard(reader)

			if bool(hazard["ok"]):
				hazard_received.emit(hazard)

		HungryEvents.Kind.PROGRESS:
			var earned := HungryEvents.read_progress(reader)

			if bool(earned["ok"]):
				progress_received.emit(earned)

		HungryEvents.Kind.VOTE:
			var voted := HungryEvents.read_vote_cue(reader)

			if bool(voted["ok"]):
				vote_cue_received.emit(voted)

		_:
			_on_event_world(event.kind, reader)

func _on_event_world(kind: int, reader: DotNetReader) -> void:
	match kind:
		HungryEvents.Kind.SPAWN:
			_apply_spawn(reader)

		HungryEvents.Kind.DESPAWN:
			_apply_despawn(reader)

		HungryEvents.Kind.FIELD:
			var delta := HungryEvents.read_field(reader)
			if bool(delta["ok"]):
				world.apply_field_delta(
					delta["added"], delta["removed"], delta["planted"]
				)

		HungryEvents.Kind.FIELD_RESET:
			world.adopt_field_seed(reader.read_varint())

		HungryEvents.Kind.THROW:
			_apply_throw(reader)

		HungryEvents.Kind.IMPACT:
			_apply_impact(reader)

		HungryEvents.Kind.BURST:
			var pair := HungryEvents.read_pair(reader)
			if bool(pair["ok"]):
				cue.emit(kind, pair)

		HungryEvents.Kind.DIED:
			var died := HungryEvents.read_died(reader)
			if bool(died["ok"]):
				cue.emit(kind, died)

		HungryEvents.Kind.BOARD:
			board = HungryEvents.read_board(reader)
			cue.emit(kind, {"rows": board})

		HungryEvents.Kind.CARRY:
			var monster := local_monster()
			var carried := HungryEvents.read_carry(reader)
			if monster != null:
				monster.carried.clear()
				for item in carried:
					monster.carried.append(item)
			cue.emit(kind, {"carried": carried})

func _apply_hello(reader: DotNetReader) -> void:
	var hello := HungryEvents.read_hello(reader)

	if not bool(hello["ok"]):
		DotLog.warn(CHANNEL, "a truncated hello")
		return

	local_player_id = int(hello["player_id"])
	avatar_pack_url = String(hello["pack_url"])
	world.tick_rate = int(hello["tick_rate"])
	world.set_tick(int(hello["tick"]))
	# Size before seed. The field is hashed into the arena rectangle, so a seed adopted
	# against the wrong one lays every crumb out somewhere else.
	world.adopt_world_size(hello["world_size"])
	# After the size, because the discs are laid out proportionally inside the arena
	# rectangle — the same ordering rule the seed above obeys, and for the same reason.
	world.adopt_layout(StringName(String(hello["layout"])))
	world.adopt_field_seed(int(hello["seed"]))

	hello_received.emit(local_player_id)

func _apply_join(reader: DotNetReader) -> void:
	var join := HungryEvents.read_join(reader, avatar_schema)

	if not bool(join["ok"]):
		return

	var player_id := int(join["player_id"])
	var monster := _ensure_monster(player_id, String(join["name"]))

	if monster == null:
		return

	monster.display_name = String(join["name"])

	var avatar: Variant = join["avatar"]

	if avatar is DotAvatar:
		monster.avatar = avatar

	var carried: Variant = join["loadout"]

	if carried is DotLoadout:
		# Adopted without validating: this came from the authority, which validated it,
		# and a client that second-guessed it would disagree with the server about how
		# fast its own monster moves.
		monster.wear_loadout(carried)

	roster_changed.emit(player_id)

func _apply_spawn(reader: DotNetReader) -> void:
	var spawn := HungryEvents.read_spawn(reader)

	if not bool(spawn["ok"]):
		return

	var net_id := int(spawn["net_id"])

	if net.registry.has(net_id):
		return

	# A piece id of zero is the match entity, which has no piece and no owner.
	if int(spawn["piece_id"]) == 0:
		_mirror_match_entity(net_id)
		return

	var monster := _ensure_monster(int(spawn["owner_id"]), "")

	if monster == null:
		return

	var piece := world.attach_piece(
		monster, spawn["position"], float(spawn["mass"]), int(spawn["piece_id"])
	)

	var identity := _build_piece_entity(piece, int(spawn["peer_id"]))
	var registered := net.registry.register(
		identity, net_id, net.clock.tick, net.config
	)

	if not registered.ok:
		DotLog.warn(CHANNEL, "could not mirror a piece", {
			"net_id": net_id, "error": str(registered.error)
		})
		world.forget_piece(piece.id)
		return

	_piece_of_net[net_id] = piece.id

func _apply_despawn(reader: DotNetReader) -> void:
	var net_id := reader.read_varint()

	if not reader.ok() or not _piece_of_net.has(net_id):
		return

	var piece_id := int(_piece_of_net[net_id])
	_piece_of_net.erase(net_id)

	var behaviour: HungryPieceNet = _behaviours.get(piece_id)
	_behaviours.erase(piece_id)

	net.registry.unregister(net_id)

	if behaviour != null and behaviour.identity != null:
		var node := behaviour.identity.entity

		if node != null and is_instance_valid(node):
			node.queue_free()

	world.forget_piece(piece_id)

func _apply_throw(reader: DotNetReader) -> void:
	var row := HungryEvents.read_throw(reader)

	if not bool(row["ok"]):
		return

	var shot := HungryProjectile.make(
		int(row["id"]),
		int(row["thrower"]),
		HungryContent.ITEM_IDS[int(row["item_index"])],
		row["origin"],
		row["direction"],
		int(row["tick"])
	)

	world.adopt_projectile(shot)
	cue.emit(HungryEvents.Kind.THROW, {"shot": shot})

func _apply_impact(reader: DotNetReader) -> void:
	var row := HungryEvents.read_impact(reader)

	if not bool(row["ok"]):
		return

	world.drop_projectile(int(row["id"]))
	cue.emit(HungryEvents.Kind.IMPACT, row)

## A monster a client has been told about but does not have yet.
##
## Joins and spawns are independent messages on a reliable channel, and the ordering
## between "this player exists" and "this piece belongs to them" is guaranteed here but
## would not be after a reconnect or a mid-round join. Creating a placeholder is cheaper
## than dropping the piece: the next JOIN fills the name and the avatar in.
func _ensure_monster(player_id: int, display_name: String) -> HungryMonster:
	if player_id <= 0:
		return null

	var monster := world.monster_for(player_id)

	if monster != null:
		return monster

	var added := world.add_player(
		player_id, display_name if display_name != "" else "Player %d" % player_id
	)

	return added.value if added.ok else null


## Tells the authority this client has loaded and wants the world. Client side.
func ask_for_world() -> void:
	if net == null or net.is_server:
		return

	net.send(HungryRequest.new(HungryEvents.Ask.READY, PackedByteArray()), 0)

## Publishes this client's chosen loadout. Client side.
##
## It takes effect on the next spawn rather than immediately, which is dot-loadout's own
## rule and the right one: a player who could change their trait mid-fight would change it
## the moment they were losing.
func publish_loadout(loadout: DotLoadout) -> void:
	if net == null or net.is_server or loadout == null:
		return

	net.send(
		HungryRequest.new(
			HungryEvents.Ask.LOADOUT, HungryEvents.write_loadout(loadout)
		),
		0
	)

## One chat line to one peer. Server side, and what [member DotChatRouter.send_fn] points
## at.
##
## [b]Peer by peer, never a broadcast, and that is the router's decision rather than this
## one's.[/b] It has already worked out exactly who may hear a line — everybody, a radius,
## two people in a whisper — and handing the result to a broadcast would throw that away in
## the one place it matters most.
func send_chat(peer_id: int, wire: Dictionary) -> void:
	_tell(peer_id, HungryEvents.Kind.CHAT, HungryEvents.write_chat(wire))

## A hunter's state, to everybody who can receive one. Server side.
func broadcast_hunter(
	hunter_id: int, kind_index: int, at: Vector2, radius: float, alive: bool
) -> void:
	_broadcast(
		HungryEvents.Kind.HUNTER,
		HungryEvents.write_hunter(hunter_id, kind_index, at, radius, alive)
	)

## A hunter's state, to one peer. Server side, for somebody who has just joined.
func send_hunter(
	peer_id: int, hunter_id: int, kind_index: int, at: Vector2, radius: float, alive: bool
) -> void:
	_tell(
		peer_id,
		HungryEvents.Kind.HUNTER,
		HungryEvents.write_hunter(hunter_id, kind_index, at, radius, alive)
	)

func broadcast_hazard(
	place_id: int, kind_index: int, at: Vector2, present: bool
) -> void:
	_broadcast(
		HungryEvents.Kind.HAZARD,
		HungryEvents.write_hazard(place_id, kind_index, at, present)
	)

func send_hazard(
	peer_id: int, place_id: int, kind_index: int, at: Vector2, present: bool
) -> void:
	_tell(
		peer_id,
		HungryEvents.Kind.HAZARD,
		HungryEvents.write_hazard(place_id, kind_index, at, present)
	)

## Something somebody earned, to everybody. Server side.
func broadcast_progress(
	player_id: int, id: StringName, title: String, value: int
) -> void:
	_broadcast(
		HungryEvents.Kind.PROGRESS,
		HungryEvents.write_progress(player_id, id, title, value)
	)

## Client side: say something.
func say(channel_id: StringName, text: String) -> void:
	if net == null or net.is_server or text.strip_edges() == "":
		return

	net.send(
		HungryRequest.new(HungryEvents.Ask.SAY, HungryEvents.write_say(channel_id, text)),
		0
	)

## Client side: rock the vote, nominate, or cast one.
func vote(token: String) -> void:
	if net == null or net.is_server or token.strip_edges() == "":
		return

	net.send(
		HungryRequest.new(HungryEvents.Ask.VOTE, HungryEvents.write_vote(token)), 0
	)

## Publishes this client's avatar. Client side.
func publish_avatar(avatar: DotAvatar) -> void:
	if net == null or net.is_server or avatar == null:
		return

	net.send(
		HungryRequest.new(
			HungryEvents.Ask.AVATAR,
			HungryEvents.write_avatar(avatar, avatar_schema)
		),
		0
	)
