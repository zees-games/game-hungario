extends "res://game/net/hungry_net_bridge_client.gd"

## Marks a peer able to receive, and gives it everything it has missed.
##
## Also where the peer joins the manager: a peer registered before it can receive is a
## peer the server builds and sends a snapshot to every tick, into a node that does not
## exist yet.
func _admit(peer_id: int, player_id: int) -> void:
	if peer_id <= 0:
		return

	var first := not _ready_peers.has(peer_id)
	_ready_peers[peer_id] = true

	if not net.peers().has(peer_id):
		net.add_peer(peer_id)

	if profile_link != null:
		profile_link.peer_joined(peer_id)

	_send_hello(peer_id, player_id)
	_send_roster(peer_id)
	_send_full_field(peer_id)
	send_carry(player_id)

	if first:
		peer_admitted.emit(peer_id, player_id)


func _send_hello(peer_id: int, player_id: int) -> void:
	_tell(
		peer_id,
		HungryEvents.Kind.HELLO,
		HungryEvents.write_hello(
			world.field.seed_value(),
			world.tick_rate,
			player_id,
			peer_id,
			net.clock.tick,
			world.world_size,
			avatar_pack_url,
			world.layout.id if world.layout != null else &""
		)
	)

	# The match entity's id travels in its own spawn, so a joining client can mirror it
	# before the first snapshot mentions it.
	if _match_identity != null:
		_tell(
			peer_id,
			HungryEvents.Kind.SPAWN,
			HungryEvents.write_spawn(
				_match_identity.net_id, 1, 0, 0, Vector2.ZERO, 0.0
			)
		)

## Everybody already here, and every piece already in the world.
func _send_roster(peer_id: int) -> void:
	for monster in world.monsters():
		_tell(peer_id, HungryEvents.Kind.JOIN, _join_body(monster))

	for piece in world.pieces():
		var behaviour: HungryPieceNet = _behaviours.get(piece.id)

		if behaviour == null or behaviour.identity == null:
			continue

		_tell(
			peer_id,
			HungryEvents.Kind.SPAWN,
			HungryEvents.write_spawn(
				behaviour.identity.net_id,
				behaviour.identity.owner_peer_id,
				piece.owner_id,
				piece.id,
				piece.position(),
				piece.mass()
			)
		)

## The whole field, in chunks.
##
## [b]Chunked, and that is not premature.[/b] A full field is eleven hundred food slots
## plus fruit and drops, and one reliable packet of that size fragments on a UDP transport
## and blocks the head of the line on a WebSocket one — which is the transport a browser
## client is on, always.
func _send_full_field(peer_id: int) -> void:
	_tell(
		peer_id,
		HungryEvents.Kind.FIELD_RESET,
		HungryEvents.write_field_reset(world.field.seed_value())
	)

	var alive := world.field.alive_ids()
	var index := 0

	while index < alive.size():
		var chunk := alive.slice(index, index + HungryEvents.FIELD_CHUNK)
		index += HungryEvents.FIELD_CHUNK

		_tell(
			peer_id,
			HungryEvents.Kind.FIELD,
			HungryEvents.write_field(chunk, [], world.field.planted_rows(chunk))
		)

## One player, as everybody else needs to know them.
func _join_body(monster: HungryMonster) -> PackedByteArray:
	return HungryEvents.write_join(
		monster.id,
		peer_for_player(monster.id),
		monster.display_name,
		monster.avatar,
		avatar_schema,
		monster.loadout
	)

## Tells everybody about a player whose name, avatar or loadout has changed.
func _announce(monster: HungryMonster) -> void:
	if monster != null:
		_broadcast(HungryEvents.Kind.JOIN, _join_body(monster))

func _on_field_changed() -> void:
	_field_dirty = true

## Sends a tick's worth of field change, once, after the world has run.
func _flush_field() -> void:
	if not _field_dirty:
		return

	_field_dirty = false

	if not world.field.has_delta():
		return

	var delta := world.field.drain_delta()
	var added: Array = delta["added"]
	var removed: Array = delta["removed"]
	var planted := world.field.planted_rows(added)

	var index := 0

	while index < added.size() or index == 0:
		var chunk: Array = added.slice(index, index + HungryEvents.FIELD_CHUNK)
		var gone: Array = removed if index == 0 else []
		index += HungryEvents.FIELD_CHUNK

		_broadcast(
			HungryEvents.Kind.FIELD, HungryEvents.write_field(chunk, gone, planted)
		)

		if index >= added.size():
			break

func _flush_board(tick: int) -> void:
	_board_countdown -= 1

	if _board_countdown > 0:
		return

	_board_countdown = BOARD_INTERVAL_TICKS
	_tick = tick

	var rows: Array = []

	for monster in world.leaderboard(10):
		rows.append({"id": monster.id, "mass": int(monster.mass())})

	_broadcast(HungryEvents.Kind.BOARD, HungryEvents.write_board(rows))

func _on_projectile_thrown(shot: HungryProjectile) -> void:
	_broadcast(HungryEvents.Kind.THROW, HungryEvents.write_throw(shot))
	send_carry(shot.thrower_id)

func _on_projectile_impact(
	shot: HungryProjectile,
	at: Vector2,
	hit_player: int
) -> void:
	_broadcast(
		HungryEvents.Kind.IMPACT, HungryEvents.write_impact(shot.id, at, hit_player)
	)

func _on_monster_burst(player_id: int, by_player: int, count: int) -> void:
	_broadcast(
		HungryEvents.Kind.BURST, HungryEvents.write_pair(player_id, by_player, count)
	)

func _on_player_died(player_id: int, killer_id: int) -> void:
	var monster := world.monster_for(player_id) if world != null else null
	_broadcast(
		HungryEvents.Kind.DIED,
		HungryEvents.write_died(player_id, killer_id, monster.death if monster != null else null)
	)

## What a player is carrying, sent only to that player.
##
## Owner-only because it is information an opponent should not have: knowing that the
## monster bearing down on you is out of peppers is worth a great deal, and data never
## sent cannot be read out of a modified client.
func _on_item_taken(player_id: int, _grid_id: int, _item: StringName) -> void:
	send_carry(player_id)

## The mode vote's cue or countdown second, to every ready peer. Server side.
func broadcast_vote_cue(cue: StringName, seconds_left: int, runoff: bool) -> void:
	_broadcast(
		HungryEvents.Kind.VOTE, HungryEvents.write_vote_cue(String(cue), seconds_left, runoff)
	)

func send_carry(player_id: int) -> void:
	var monster := world.monster_for(player_id)
	var peer_id := peer_for_player(player_id)

	if monster == null or peer_id == 0:
		return

	_tell(peer_id, HungryEvents.Kind.CARRY, HungryEvents.write_carry(monster.carried))

func _on_match_state_changed(_from: DotMatch.State, to: DotMatch.State) -> void:
	if to != DotMatch.State.LIVE:
		return

	# A new round has replaced the field wholesale. Nobody can derive that from a delta,
	# so everybody is resynchronised.
	for peer_id in _ready_peers.keys():
		_send_full_field(int(peer_id))

	# And the delta the reset produced is superseded by what was just sent. Left pending
	# it would go out again a tick later as a second copy of the same field, which costs
	# a few kilobytes to every client and tells them nothing.
	world.field.drain_delta()
	_field_dirty = false


func _on_request(message: DotNetMessage) -> void:
	var ask := message as HungryRequest

	if ask == null or net == null or not net.is_server:
		return

	var peer_id := ask.sender_peer_id

	if not _player_of_peer.has(peer_id):
		# Kept, not dropped: see `_ready_unseated`.
		if ask.kind == HungryEvents.Ask.READY and peer_id > 0:
			_ready_unseated[peer_id] = true
		return

	var player_id := int(_player_of_peer[peer_id])

	match ask.kind:
		HungryEvents.Ask.READY:
			_admit(peer_id, player_id)

		HungryEvents.Ask.AVATAR:
			_apply_avatar(player_id, ask.reader())

		HungryEvents.Ask.LOADOUT:
			# Not awaited, and it suspends: the store write is the suspension, and
			# everything after it — applying the loadout and telling everybody — resumes
			# when the write returns. Nothing in this handler depends on it having
			# finished, which is the only reason dropping the await here is safe.
			_apply_loadout(player_id, ask.reader())

		HungryEvents.Ask.SAY:
			var said := HungryEvents.read_say(ask.reader())

			if bool(said["ok"]):
				# Emitted rather than acted on. Everything about what a line means — the
				# channel's audience, the gag, the rate limit, the command prefix — is
				# [DotChatRouter]'s, and the router is [HungryModule]'s.
				say_requested.emit(
					peer_id, StringName(str(said["channel"])), str(said["text"])
				)

		HungryEvents.Ask.VOTE:
			vote_requested.emit(peer_id, HungryEvents.read_vote(ask.reader()))

## Takes a client's avatar, through the schema.
##
## [b]The schema is the whole check, and it loads nothing.[/b] Every index is validated
## against the slot and part tables on the way in, so a document naming a part that does
## not exist is refused rather than clamped to whatever sits at the boundary — and a
## dedicated server holding none of the art can still say no.
func _apply_avatar(player_id: int, reader: DotNetReader) -> void:
	var monster := world.monster_for(player_id)

	if monster == null:
		return

	var decoded := HungryEvents.read_avatar(reader, avatar_schema)

	if not decoded.ok:
		DotLog.info(CHANNEL, "refused an avatar", {
			"player": player_id, "error": str(decoded.error)
		})
		return

	var avatar: DotAvatar = decoded.value
	var conformed := avatar_schema.conform(avatar, DotAvatarEntitlements.everything())

	if not conformed.ok:
		return

	monster.avatar = avatar

	_announce(monster)
	roster_changed.emit(player_id)

## Takes a client's loadout, through the schema.
##
## [b]Validated, never conformed.[/b] Conforming is right on the way out of a store, where
## the alternative is a player who cannot spawn. It is wrong here: a client that can make
## the server repair its way to a legal loadout can put anything in any slot and have the
## server pick the nearest legal thing for it, which is a different feature from the one
## being offered.
##
## Suspends on the store write. See the caller.
func _apply_loadout(player_id: int, reader: DotNetReader) -> void:
	var monster := world.monster_for(player_id)

	if monster == null:
		return

	var decoded := HungryEvents.read_loadout(reader)

	if not decoded.ok:
		DotLog.info(CHANNEL, "refused a malformed loadout", {
			"player": player_id, "error": str(decoded.error)
		})
		return

	var loadout: DotLoadout = decoded.value
	var owns := _entitlements_for(player_id)
	var valid := DotLoadoutValidator.validate(loadout, loadout_schema, owns)

	if not valid.ok:
		DotLog.info(CHANNEL, "refused a loadout", {
			"player": player_id, "error": str(valid.error)
		})
		return

	# The store, if there is one. A refused write must not leave the session wearing
	# something the store does not have: a player who sees their change, plays with it and
	# loses it at the next load with no explanation is worse than a refusal.
	if loadout_sink.is_valid():
		# Awaited, because a store may be slow. The sink is a Callable, so nothing here
		# knows statically whether it suspends — and a sink that writes to a database and
		# was called without `await` would have its result read before it had one.
		var stored: Variant = await loadout_sink.call(player_id, loadout)

		if stored is DotResult and not (stored as DotResult).ok:
			DotLog.info(CHANNEL, "a loadout was refused by the store", {
				"player": player_id, "error": str((stored as DotResult).error)
			})
			return

	monster.wear_loadout(loadout)
	_announce(monster)
	roster_changed.emit(player_id)
