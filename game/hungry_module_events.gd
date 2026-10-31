extends "res://game/hungry_module_console.gd"

## The module drives no clock of its own: the base ticks once, then this runs.
func _can_tick() -> bool:
	return hbridge != null and world != null

func _game_tick(_tick: int, _delta: float) -> void:
	_drive_bots()

	# After the world's own tick: hunters read where everybody is and hazards push pieces out of rocks,
	# both on positions the movement just produced, or they see a one-tick lag.
	if hunters != null and hunters.is_enabled():
		hunters.tick(1.0 / float(world.tick_rate))

	if hazards != null:
		hazards.resolve()

	if maps != null:
		maps.advance(1.0 / float(world.tick_rate))

## Our disconnect handler goes on the server before the roster's, so it still sees the player in the world.
func _build_roster() -> void:
	if server != null:
		server.client_disconnected.connect(_on_client_disconnected)

	super()
	# This module opens its own tracker sessions (see [method _begin_stats]).
	stats_feed.open_sessions = false
	roster.add_fn = _seat_player
	roster.remove_fn = _unseat_player
	roster.seated.connect(_on_seated)

## The session id, not the peer id: a peer id is reassigned on reconnect and the next
## player to join would inherit this one's monster.
func _seat_player(session: DotClientSession) -> Variant:
	return hbridge.add_player(
		session.peer_id, session.userid, session.display_name, _avatar_for(session)
	)

func _unseat_player(session: DotClientSession) -> void:
	hbridge.remove_peer(session.peer_id)

## The roster has added them to the world and told the services (so chat and voice have somewhere to put a frame).
func _on_seated(session: DotClientSession) -> void:
	_apply_stored_loadout(session.userid)
	_begin_stats(session)

	if progress != null:
		progress.begin(str(_stat_keys.get(session.userid, "")))

	# The welcome is not sent from here: `client_spawn` ends signon but the client builds its scene
	# after it, so the peer is never ready yet. See [method _on_peer_admitted].

## A peer said it can receive: now it can be welcomed.
func _on_peer_admitted(peer_id: int, player_id: int) -> void:
	var session := server.session_by_userid(player_id) if server != null else null

	if session == null or session.peer_id != peer_id or not _joined.has(session.userid):
		return

	_welcome(session)

## What somebody is told once they are in: the backlog, and what is already in the arena.
## After the admission, never before: sent before the client builds its scene it is lost, one
## "Node not found" per call.
func _welcome(session: DotClientSession) -> void:
	if not hbridge.peer_is_ready(session.peer_id):
		return

	if hservices != null:
		# The backlog: what was said before they walked in. dot-chat computes it per peer,
		# because a channel with `backlog = 0` — the proximity one — must not replay a
		# line somebody said quietly in a corner to a stranger who was not there.
		for line in hservices.chat.backlog_for(session.peer_id):
			hbridge.send_chat(session.peer_id, line)

		hservices.chat.join_notice(session.peer_id, HungryServices.CHANNEL_ALL)

	# The hunters and the hazards already in the arena. A client that joined mid-wave
	# would otherwise be told about a hunter only when it next moved, and would walk
	# through a rock in the meantime — both ends resolve the same list.
	if hunters != null:
		for row in hunters.wire_rows():
			hbridge.send_hunter(
				session.peer_id, row[0], row[1], row[2], row[3], row[4]
			)

	if hazards != null:
		for row in hazards.wire_rows():
			hbridge.send_hazard(session.peer_id, row[0], row[1], row[2], true)

func _on_client_disconnected(session: DotClientSession, _reason: String) -> void:
	if not _joined.has(session.userid):
		return

		# Off the broadcast set first: everything below announces this person to everybody else, and their
		# socket is gone ("Attempt to call RPC with unknown peer ID" in every disconnect log).
	hbridge.mark_not_ready(session.peer_id)

	if hservices != null:
		hservices.chat.leave_notice(session.peer_id, HungryServices.CHANNEL_ALL)

	if mod_tools != null:
		mod_tools.forget(StringName(str(session.userid)))

	if maps != null and maps.director != null:
		# The vote forgets them, or a rock-the-vote threshold counts a ballot from
		# somebody who has left, which is how a server ends up unable to change at all.
		maps.director.forget_voter(StringName(str(session.userid)))

	if progress != null:
		progress.end(str(_stat_keys.get(_player_of_session(session), "")))

	_end_stats(session)

## The world player id a session is in the arena under, or zero.
func _player_of_session(session: DotClientSession) -> int:
	return hbridge.player_for_peer(session.peer_id) if hbridge != null else 0


## Somebody said something through dot-server's own chat path.
## Taken and cancelled, not watched: [DotChatRouter] owns this game's rules, so cancelling keeps one
## path, and the line still reaches every player after sanitising, the gag check and hearing range.
func _on_player_chat(event: DotEvent) -> void:
	event.cancel("routed by the game's chat", _module_name())

	var session := event.get_session()

	if session == null or hservices == null or hservices.chat == null:
		return

	# A browser shell's own chat box has no way to name a channel, so the legacy path
	# lands on the room channel — which is the one they would have picked.
	_on_say_requested(
		session.peer_id, HungryServices.CHANNEL_ALL, event.get_string("text")
	)

func _on_say_requested(peer_id: int, channel_id: StringName, text: String) -> void:
	var said := hservices.chat.submit(peer_id, channel_id, text)

	if not said.ok and said.error != null:
		# Back to the sender and nowhere else. dot-chat is deliberate that a rate-limited
		# or gagged player must not be able to measure the difference from outside, and a
		# refusal broadcast to the room is exactly that measurement.
		hservices.chat.notice(peer_id, said.error.message, channel_id)

## A voice frame. Relayed, never inspected — the router stamps the speaker from the
## transport's own sender id, and without that any client can put words in any other
## player's mouth.
func _on_voice_requested(peer_id: int, payload: PackedByteArray) -> void:
	hservices.voice.relay(peer_id, payload)

func _on_chat_accepted(message: DotChatMessage, _recipients: PackedInt32Array) -> void:
	# Nothing to draw over a head here — a monster is not a nameplate — but the server's
	# own view of who last spoke is what `hungry_status` reports from, and it is taken off
	# the accepted line rather than off the request so a refused one is not counted.
	if message.sender_peer > 0:
		_last_spoke = message.sender_name

## An unclaimed `!command` from chat.
## Routed into dot-server's console with the player's permissions, not a second command table, so
## it is permission-checked and audited.
func _on_chat_command(peer_id: int, command: String, args: PackedStringArray) -> void:
	var session := server.session_of(peer_id)

	if session == null:
		return

	if server.console.find_command(command) == null:
		DotLog.debug(CHANNEL, "an unknown chat command was ignored", {
			"peer": peer_id, "command": command,
		})
		return

	var ctx := session.make_context(
		command,
		args,
		DotCmdContext.Source.CHAT,
		func(line: String) -> void:
			hservices.chat.notice(peer_id, line, HungryServices.CHANNEL_ALL)
	)

	var line := command

	for arg in args:
		line += " " + arg

	server.console.execute(line, ctx)

## `rtv`, `nominate <id>`, `vote <n>`, `extend` from this game's own wire.
## A token resolved here, not an enum on the wire: what can be voted for is a [DotVoteSource]'s
## business, so one engine drives games and maps.
func _on_vote_requested(peer_id: int, token: String) -> void:
	if maps == null or maps.director == null:
		return

	var player_id := hbridge.player_for_peer(peer_id)

	# Nobody in the world yet. `player_for_peer` answers 0 for every such peer, so they
	# would all rock, nominate and vote as the one voter "0" — each undoing the last.
	if player_id <= 0:
		return

	var voter := StringName(str(player_id))
	var parts := token.strip_edges().split(" ", false)

	if parts.is_empty():
		return

	var result: DotResult = null

	match parts[0].to_lower():
		"rtv":
			result = maps.director.rock_the_vote(voter)
		"nominate":
			if parts.size() > 1:
				result = maps.director.nominate(voter, StringName(parts[1]))
		"vote":
			if parts.size() > 1:
				result = maps.director.cast_one(voter, StringName(parts[1]))
		"extend":
			# An admin's, not a player's, as in game-playground: extending without a vote
			# is what the ballot's own "extend" option exists to make a decision of the
			# players. This line let anybody on the wire do it, as often as it allowed.
			if not _voter_is_admin(voter):
				result = DotResult.fail(
					DotError.CODE_FORBIDDEN, "Only an admin can extend without a vote."
				)
			else:
				result = maps.director.extend()

	if result != null and not result.ok and hservices != null:
		hservices.chat.notice(
			peer_id, result.error.message, HungryServices.CHANNEL_ALL
		)

func _voter_is_admin(voter: StringName) -> bool:
	var player_id := String(voter).to_int()
	var peer_id := hbridge.peer_for_player(player_id)
	var session := server.session_of(peer_id) if peer_id > 0 else null
	# CHANGEMAP, not any flag: `is_admin()` is "holds a flag at all", which a reserved slot
	# or admin chat satisfies, and this gates extending the map, an instant rtv and the
	# nomination bypasses. The console's own extend asks for CHANGEMAP; the wire must too.
	return session != null and session.has_permission(DotAdminFlags.CHANGEMAP)

func _on_vote_announced(line: String) -> void:
	if hservices != null and hservices.chat != null:
		hservices.chat.announce(line, HungryServices.CHANNEL_ALL)

## The vote picked something. dot-server changes the game; nothing here does.
func _on_change_due(game_id: StringName) -> void:
	if not maps.available(game_id):
		log_warn("the vote picked a mode this head count cannot play", {
			"game": String(game_id)
		})
		return

	server.games.change_game(game_id, "vote")


func _on_hunter_changed(hunter_id: int) -> void:
	var state := hunters.state_of(hunter_id)

	if state.is_empty():
		# Gone. Announced as not-alive so a client drops it, rather than simply stopping
		# being mentioned — which would leave it drawn for ever.
		hbridge.broadcast_hunter(hunter_id, 0, Vector2.ZERO, 0.0, false)
		return

	hbridge.broadcast_hunter(
		hunter_id,
		HungryHunters.index_of(state["kind"]),
		state["at"],
		float(state["radius"]),
		bool(state["alive"])
	)

## A hunter ate somebody's piece. Counted, so the secret achievement can be earned.
func _on_piece_hunted(player_id: int, _mass: float) -> void:
	var key := _stat_key(player_id)

	if key != &"":
		stats.record(key, &"hunted", 1.0)

func _on_hazard_placed(place_id: int, def: DotPropDef, at: Vector2) -> void:
	hbridge.broadcast_hazard(place_id, HungryHazards.index_of(def.id), at, true)

func _on_hazard_cleared(place_id: int) -> void:
	hbridge.broadcast_hazard(place_id, 0, Vector2.ZERO, false)

## A spike. What "burst" means is the world's; this is where it is asked for.
func _on_hazard_struck(player_id: int, _piece_id: int, effect: StringName) -> void:
	if effect == &"burst":
		world.burst(world.monster_for(player_id), 0)

func _on_earned(player_key: String, id: StringName, title: String, points: int) -> void:
	# The player id the key belongs to, so a client can colour the line. Linear over at
	# most a few dozen players, a few times a session.
	for player_id in _stat_keys.keys():
		if str(_stat_keys[player_id]) != player_key:
			continue

		hbridge.broadcast_progress(int(player_id), id, title, points)
		return


## The game id a preset is played under, which dot-server, the vote and the rotation call a mode.
## The preset id alone ("classic") is not one: the vote would not recognise the running mode.
static func game_id_of(preset_id: StringName) -> StringName:
	return StringName("hungry_%s" % preset_id)

## The modes, so `changegame` and a vote have something to change to.
## Both ship inside the build, so [member DotGameDescriptor.manifest_url] is empty; a game whose
## content lives on a CDN sets it instead.
static func game_descriptors() -> Array[DotGameDescriptor]:
	var out: Array[DotGameDescriptor] = []

	for row in [
		[GAME_CLASSIC, "Hungario: Classic", HungryPaths.rebase("res://game/modes/classic.tscn")],
		[GAME_FRENZY, "Hungario: Frenzy", HungryPaths.rebase("res://game/modes/frenzy.tscn")],
		[GAME_GAUNTLET, "Hungario: Gauntlet", HungryPaths.rebase("res://game/modes/gauntlet.tscn")],
		[GAME_WARRENS, "Hungario: Warrens", HungryPaths.rebase("res://game/modes/warrens.tscn")],
		[GAME_REEF, "Hungario: Reef", HungryPaths.rebase("res://game/modes/reef.tscn")],
		[GAME_SHALLOWS, "Hungario: Shallows", HungryPaths.rebase("res://game/modes/shallows.tscn")],
	]:
		var descriptor := DotGameDescriptor.new()
		descriptor.game_id = String(row[0])
		descriptor.display_name = String(row[1])
		descriptor.scene = String(row[2])
				# Deliberately empty: [DotClientLink] refuses an absolute scene path outside dot-cloud's mount
				# prefix, and this game ships inside the build, so the client owns its scene ([HungryClient]).
				# A game delivered through dot-cloud sets a relative path here.
		descriptor.client_scene = ""
		descriptor.min_players = 0
		out.append(descriptor)

	return out

## Registers both modes, unless the host already did.
## A host wanting one as [member DotGameManager.initial_game] adds them before the server boots, so
## registration here is idempotent; [method game_descriptors] is the same list for that case.
func _register_games() -> void:
	if server.games == null:
		return

	for descriptor in game_descriptors():
		if server.games.find_game(descriptor.game_id) != null:
			continue

		var added := server.games.add_game(descriptor)

		if not added.ok:
			log_warn("could not register a game", {
				"game": descriptor.game_id, "error": str(added.error)
			})


