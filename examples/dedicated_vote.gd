extends "dedicated_play.gd"

## Last sections of the dedicated suite: progress, rotation file, disconnect, the vote.


## Boards and achievements over the numbers this game already counts.
func _test_progress() -> void:
	_section("boards and achievements")

	var progress := _module().progress

	_check(progress != null, "the progress layer is up")
	_check(
		progress.boards != null and progress.boards.definitions().size() == 3,
		"with three boards (%d)"
			% (progress.boards.definitions().size() if progress.boards != null else -1)
	)
	_check(
		progress.achievements != null and progress.achievements.catalogue.size() >= 8,
		"and a catalogue of achievements (%d)"
			% (progress.achievements.catalogue.size() if progress.achievements != null else -1)
	)

	# Every stat an achievement watches has to be one the game reports, or it never unlocks and
	# nothing errors.
	var schema := HungryModule.stats_schema()
	var missing := PackedStringArray()

	for stat in progress.achievements.catalogue.watched_stats():
		if not schema.has(stat) and stat != &"hunted":
			missing.append(String(stat))

	_check(
		missing.is_empty(),
		"every watched stat is one the game declares",
		"missing: %s" % str(missing)
	)

	var problems := progress.achievements.catalogue.validate()
	_check(problems.ok, "the catalogue validates", str(problems.error))

	# The link is the whole integration and it is a signal connection.
	_check(progress.link != null, "the stats link is wired")
	await _test_progress_board(progress)
	_done()


func _test_progress_board(progress: HungryProgress) -> void:
	# A key that differs every run: DotAchievementStoreFile writes to `user://`, so a fixed key
	# accumulates across runs and "not the second tier" eventually fails on an unchanged tree.
	# Clearing the directory instead would be a suite deleting a player's progress.
	var player := "test-player-%d" % Time.get_ticks_usec()

	progress.begin(player)

	for _bite in range(120):
		progress.achievements.record(player, &"food", 1.0)

	_check(
		progress.achievements.is_unlocked(player, &"eat_100"),
		"a hundred bites unlocks the first tier"
	)
	_check(
		not progress.achievements.is_unlocked(player, &"eat_1000"),
		"and not the second"
	)

	# A board, and the PENALTY ordering — the half of `beats()` a SCORE board never runs.
	var monster := HungryMonster.new()
	monster.id = 7
	monster.display_name = "Tester"
	monster.best_mass = 4200.0
	monster.players_eaten = 3

	await progress.file_round(player, monster, 2)
	await progress.file_round(player, monster, 5)

	var deaths: Array = await progress.page(&"fewest_deaths", 5)
	_check(deaths.size() == 1, "a board holds one entry per player (%d)" % deaths.size())
	_check(
		deaths.size() == 1 and is_equal_approx((deaths[0] as DotLeaderboardEntry).value, 2.0),
		"and keeps the BETTER of two rounds, which on a penalty board is the lower",
		"%.0f" % ((deaths[0] as DotLeaderboardEntry).value if deaths.size() == 1 else -1.0)
	)

	_check(progress.boards.backend == "memory", "the boards backend defaults to memory")
	await _test_progress_remote(progress)


func _test_progress_remote(progress: HungryProgress) -> void:
	# The same round through a remote store: a fake site with a frame of latency, so a
	# caller that does not await is caught, and the plain forms must refuse it.
	var site := DotLeaderboardFakeSite.new(get_tree())
	var remote := DotLeaderboardManager.new()
	remote.backend = "backbone"
	remote.backbone_client = site
	add_child(remote)
	for board in progress.board_defs():
		remote.define(board)
	var scope := {"mode": String(progress.mode_id)}
	_check(not remote.page(&"top_mass", scope, 0, 5).ok, "the synchronous form refuses a remote store")
	var filed: DotResult = await remote.submit_async(&"top_mass", scope, &"remote_p", "Tester", 4200.0)
	_check(filed.ok, "a round files on a remote board", str(filed.error))
	var rpage: DotResult = await remote.page_async(&"top_mass", scope, 0, 5)
	_check(
		rpage.ok and (rpage.value as Array).size() == 1
		and ((rpage.value as Array)[0] as DotLeaderboardEntry).value == 4200.0,
		"and reads back through page_async", str(rpage.error) if not rpage.ok else ""
	)
	_check(site.posts() > 0, "the fake site received the declare and the submit")
	remove_child(remote)
	remote.queue_free()

	var progressed: DotResult = await progress.achievements.flush()
	_check(progressed.ok, "progress writes to disk", str(progressed.error))


## Stands in for the module a vote's commands are registered on, recording the names.
class CommandHost extends Node:
	var added: Dictionary = {}

	func add_command(full: String, fn: Callable, _help: String, _permission: String) -> Object:
		added[full] = fn
		return null


## `cfg/maps.yml`: which modes rotate. The format is dot-map's selftest's; this is what the
## GAME does with it: a mode left out is installed and loadable and is never drawn, never on a
## ballot, never nominated; a switch of rotation takes effect; a renamed command answers.
func _test_rotation_file() -> void:
	_section("rotation file")

	var maps = _module().maps
	var ids: Array[StringName] = []
	for map: DotMapDef in maps.catalogue.maps:
		ids.append(map.id)
	_check(ids.size() >= 4, "the catalogue holds the modes (%d)" % ids.size())
	var keep_a: Array = [String(ids[0]), String(ids[1])]
	var keep_b: Array = [String(ids[2]), String(ids[3])]
	var outside: Array[StringName] = []
	for id in ids:
		if not keep_a.has(String(id)):
			outside.append(id)

	var parsed := DotMapRotationFile.from_trees([{"defaults": {
		"rotation": "a",
		"rotations": {"a": {"maps": keep_a, "mode": "random"}, "b": {"maps": keep_b, "mode": "cycle"}},
		"commands": {"names": {"rtv": "rockit"}},
	}}], "game-hungario")
	_check(parsed.ok, "a rotation file parses", str(parsed.error))
	var kept_file = maps.rotation_file
	maps.rotation_file = parsed.value
	maps.apply_rotation()

	var drawn := {}
	for _i in 40:
		var chosen: DotMapDef = maps.rotation.choose(6)
		if chosen == null:
			break
		drawn[chosen.id] = true
		maps.rotation.note_played(chosen.id)
	var strays := []
	for id in drawn:
		if not keep_a.has(String(id)):
			strays.append(id)
	_check(not drawn.is_empty() and strays.is_empty(),
		"a mode outside the rotation is never drawn", str(strays))
	_check(maps.catalogue.size() == ids.size() and maps.catalogue.has(outside[0]),
		"and stays installed in the catalogue")

	var ballot: Array[StringName] = []
	for choice in maps.director.source.choices():
		ballot.append(choice.id)
	var leaked := ballot.filter(func(id: StringName) -> bool: return not keep_a.has(String(id)))
	_check(not ballot.is_empty() and leaked.is_empty(),
		"never on a ballot", "%s offered" % str(leaked))

	var refused: DotResult = maps.director.nominate(&"9001", outside[0])
	_check(not refused.ok, "and refused by nominate")
	_test_rotation_file_switch(maps, ids, keep_b, kept_file)
	_done()


func _test_rotation_file_switch(maps: Variant, ids: Array[StringName], keep_b: Array, kept_file: Variant) -> void:
	var switched: DotResult = maps.switch_rotation("b")
	var pool_ids: Array = maps.rotation.pool(6).map(func(m: DotMapDef) -> String: return String(m.id))
	pool_ids.sort()
	var want := keep_b.duplicate()
	want.sort()
	_check(switched.ok and pool_ids == want, "a rotation switch takes effect", str(pool_ids))
	_check(not maps.switch_rotation("nowhere").ok, "and an unknown rotation changes nothing")

	var host := CommandHost.new()
	var fresh: Variant = maps.commands
	var bound: DotResult = maps.install_commands(host)
	_check(bound.ok and host.added.has("rockit") and not host.added.has("rtv"),
		"a renamed rtv is registered under its new name", ", ".join(host.added.keys().slice(0, 6)))
	if host.added.has("rockit"):
		var ctx := DotCmdContext.new()
		(host.added["rockit"] as Callable).call(ctx)
		_check(not ctx.output.is_empty(), "and answers", str(ctx.output))
		maps.director.clock.unrock(&"console")
	else:
		_check(false, "and answers")
	host.free()
	maps.commands = fresh

	# No file: nothing changes -- every mode rotates, in the order it always did.
	maps.rotation_file = null
	maps.apply_rotation()
	var all_in := true
	for map: DotMapDef in maps.catalogue.maps:
		all_in = all_in and map.in_rotation
	_check(all_in and maps.director.source.choices().size() >= ids.size() - 1 and maps.rotation.order.is_empty(),
		"with no file every mode is back in the rotation and the order is the catalogue's")

	# Never twice in a row survives the file: a cycle after a voted mode skips what just played.
	var cycle := DotMapRotationFile.from_trees([{"defaults": {"rotations": {"c": {
		"maps": keep_b, "mode": "cycle"}}}}], "game-hungario")
	maps.rotation_file = cycle.value
	maps.apply_rotation()
	var before: Array = maps.rotation.history.duplicate()
	maps.rotation.note_played(StringName(keep_b[0]))
	maps.rotation.note_played(StringName(keep_b[1]))
	var after_one: DotMapDef = maps.rotation.choose(6)
	_check(after_one != null and after_one.id != StringName(keep_b[1]),
		"and a cycle never offers the mode just played")
	maps.rotation.history = before
	maps.rotation_file = kept_file
	maps.apply_rotation()


## Somebody leaves while somebody else stays. dot-net builds the stayer's snapshot from every
## remaining entity and writes each int var through `int(value)`, a SCRIPT ERROR on a null while
## the suite stays green; so every var of every remaining entity is read as the snapshot does.
func _test_disconnect() -> void:
	_section("a disconnect")

	var sessions: Array[DotClientSession] = []

	for n in 2:
		var session := DotClientSession.new()
		session.peer_id = 4101 + n
		session.userid = 411 + n
		session.display_name = "Leaver%d" % n
		var _adopted := _server.adopt_session(session)
		_server.events.fire("client_spawn", {"userid": session.userid, "name": session.display_name})
		sessions.append(session)

	var bridge: Object = _module().bridge
	_check(bridge.player_for_peer(4101) > 0 and bridge.player_for_peer(4102) > 0, "two players joined")

	for _i in 5:
		await get_tree().physics_frame

	_server.client_disconnected.emit(sessions[0], "test")
	_check(bridge.player_for_peer(4101) == 0, "and one left")

	for _i in 10:
		await get_tree().physics_frame

	var bad: PackedStringArray = []
	var seen := 0

	for identity in bridge.net.registry.all():
		for behaviour in identity.behaviours:
			for declaration in behaviour.net_vars:
				seen += 1
				var value: Variant = behaviour._net_read_property(declaration.property)

				if declaration.type in [DotNetVar.Type.INT, DotNetVar.Type.UINT, DotNetVar.Type.VARINT] \
						and typeof(value) != TYPE_INT:
					bad.append("%s.%s=%s" % [identity.net_id, declaration.property, str(value)])

	_check(seen > 0 and bad.is_empty(), "every int net var left reads as an int (%d read)" % seen,
		", ".join(bad.slice(0, 5)))

	_server.client_disconnected.emit(sessions[1], "test")
	_done()


## What plays next, and who decides.
func _test_vote() -> void:
	_section("the vote")

	var maps := _module().maps

	_check(maps != null, "the map rotation is up")
	# Counted against the descriptor list, not a literal: the catalogue is built from
	# `game_descriptors`, and a restated number is a copy that goes stale.
	var modes := HungryModule.game_descriptors().size()

	_check(
		maps.catalogue != null and maps.catalogue.size() == modes,
		"with every one of the game's modes in the catalogue (%d of %d)"
			% [maps.catalogue.size() if maps.catalogue != null else -1, modes]
	)
	_check(
		maps.director != null and maps.director.source != null
			and maps.director.source.is_usable(),
		"and a vote source over dot-server's own games",
		"what a vote applies has to be the thing that actually changes the game"
	)

	# A server that runs other games beside this one offers only the modes on the mode
	# ballot. It offered every game it ran, and a win there changed the whole server.
	var other := DotGameDescriptor.new()
	other.game_id = "other_game"
	other.display_name = "Another Game"
	other.scene = "res://nowhere.tscn"
	_server.games.games.append(other)
	var offered: Array[StringName] = []
	if maps.director != null and maps.director.source != null:
		for choice in maps.director.source.choices():
			offered.append(choice.id)
	_server.games.games.erase(other)
	_check(
		offered.size() == modes and not offered.has(&"other_game"),
		"and only this game's modes are on its ballot, whatever else the server runs",
		str(offered)
	)
	_check(
		maps.director != null and _server.hibernation_changed.is_connected(maps.director.set_hibernating),
		"the vote's clock follows the server's hibernation: it waits while nobody is here"
	)

	# [b]`gauntlet` is off the ballot below three players, and that is what a catalogue
	# buys over a hard-coded list.[/b] A corridor with two people in it is a chase; with
	# nobody in it, it is not a mode worth voting for.
	_check(
		not maps.available(&"hungry_gauntlet"),
		"a corridor is unavailable at this head count"
	)
	_check(maps.available(&"hungry_classic"), "and a square is not")
	_test_vote_menu(maps, modes)
	_done()


func _test_vote_menu(maps: HungryMaps, modes: int) -> void:
	# The map menu's server half (M): the modes of this ballot, a player offered a vote and
	# staff the change (a mode change is `changegame`, the source's own apply, which this
	# suite does not run: it would replace the game under the rest of it).
	var menu_half: Object = maps.commands.get("map_menu") if maps.commands != null else null
	var player := DotCmdContext.new()
	player.source = DotCmdContext.Source.CHAT
	var staff := DotCmdContext.new()
	staff.source = DotCmdContext.Source.CHAT
	staff.permissions = PackedStringArray(["generic"])
	var offer: Dictionary = menu_half.call("offer", player) if menu_half != null else {"maps": []}
	_check(menu_half != null and _server.console.find_command("mapmenu") != null
		and (offer["maps"] as Array).size() == modes and not bool(offer.get("allowed", true)) and bool(offer.get("vote", false)),
		"M lists every mode, and a player is offered a vote", str((offer["maps"] as Array).map(func(r: Dictionary) -> String: return str(r["id"]))))
	_check(menu_half != null and bool((menu_half.call("offer", staff) as Dictionary)["allowed"]),
		"and staff (the default sv_map_menu_flag) the change")

	var next := maps.next_in_rotation()
	_check(next != &"", "something is next in the rotation (%s)" % String(next))
	# Against the game id, which is what the rotation holds. Against the preset id this
	# could never fail, and the vote was handed the preset id, so it never knew what ran.
	var playing := HungryModule.game_id_of(_module().world.preset.id)
	_check(
		next != playing,
		"and it is not what is playing now",
		"a cooldown of one over four modes is what stops the same one twice running"
	)
	_check(
		maps.director != null and maps.director.current_id() == playing,
		"the vote knows the running mode by its game id (%s)" % String(playing),
		"by the preset id it offered the running mode against itself: %s"
			% String(maps.director.current_id() if maps.director != null else &"")
	)
	_test_vote_rock(maps)


func _test_vote_rock(maps: HungryMaps) -> void:
	# Rocking the vote with one player, before `rtv_delay_sec` allows it, is refused; the refusal
	# arriving is the check, since dot-vote once refused it for ever.
	var rocked := maps.director.rock_the_vote(&"1")
	_check(
		rocked != null,
		"rocking the vote answers rather than doing nothing",
		str(rocked.error) if not rocked.ok else "accepted"
	)

	_check(
		not maps.director.begin_on_apply,
		"the director does not announce its own change",
		"the host announces it through `game_loaded`, which also fires for an operator "
		+ "typing `changegame` — both firing halves every cooldown"
	)

	# Once a tick. It self-advanced AND the module advanced it, so a fifteen-minute mode
	# was over in seven and a half.
	_check(
		not maps.director.self_advance and not maps.director.is_physics_processing(),
		"the vote's clock is advanced once a tick, by the module, and not also by itself"
	)

	# dot-vote's commands. None existed: a chat `!rtv` reached a console with no `rtv`.
	var absent := PackedStringArray()
	for name in [
		"rtv", "unrtv", "nominate", "vote", "timeleft", "nextmap",
		"setnextmap", "nominate_addmap", "forcertv", "votereload",
	]:
		if _server.console.find_command(name) == null:
			absent.append(name)
	_check(absent.is_empty(), "dot-vote's commands are on the console", ", ".join(absent))

	# The cues and the countdown leave the vote for the wire. The ids are the wire's own,
	# and nothing on the server had any to send before.
	var rules := maps.director.rules
	var cues: Array = []
	var on_cue := func(cue: StringName, seconds_left: int, _runoff: bool) -> void:
		cues.append([String(cue), seconds_left])
	maps.cue_due.connect(on_cue)
	var min_players := rules.min_players_to_vote
	rules.min_players_to_vote = 0
	var started := maps.director.start_vote()
	maps.cue_due.disconnect(on_cue)
	_check(
		started.ok and maps.director.is_counting_down()
			and cues.has([HungryEvents.CUE_VOTE_WARNING, 0]) and cues.has(["", int(rules.vote_warning_sec)]),
		"a ballot is counted down to, and its warning cue and first second go to the module (%s)"
			% str(cues),
		started.error.message if not started.ok else ""
	)
	maps.director.cancel_countdown()
	rules.min_players_to_vote = min_players
	_test_vote_score(maps, rules)


func _test_vote_score(maps: HungryMaps, rules: DotVoteRules) -> void:
	# The leading score — the biggest monster's mass — reaches the director, and a score
	# limit opens the ballot off it. Nothing called note_score before.
	var saved := [rules.trigger, rules.duration_sec, rules.score_limit, rules.vote_lead_score, rules.min_players_to_vote, rules.vote_warning_sec, rules.allow_single_voter_auto]
	var top := int(maps.score_fn.call()) if maps.score_fn.is_valid() else 0
	# No countdown for this one: it asks whether the score opens a ballot, and a countdown
	# in front of the ballot is the check above.
	rules.vote_warning_sec = 0.0
	rules.trigger = DotVoteRules.Trigger.SCORE_LIMIT
	rules.duration_sec = 0.0
	rules.score_limit = top + 3
	rules.vote_lead_score = 3
	rules.min_players_to_vote = 0
	# The guard (an automatic ballot needs two voters) is dot-vote's; this check is about the score.
	rules.allow_single_voter_auto = true
	maps.director.begin(maps.director.current_id())
	maps.advance(0.0)

	_check(
		top > 0 and maps.director.clock.top_score == top,
		"the biggest monster's mass is the vote's leading score (%d)" % top
	)
	_check(
		maps.director.is_voting(),
		"and a score limit %d short of it opens the ballot" % rules.vote_lead_score,
		maps.director.describe_lines()[0]
	)
	if maps.director.is_voting():
		maps.director.close_vote()

	# And a round end reaches it, from the match the module is running.
	var played := maps.director.clock.rounds_played
	_module().world.match_node.round_ended.emit(99, 0, DotMatchRules.Outcome.SCORE)
	_check(
		maps.director.clock.rounds_played == played + 1,
		"and dot-match's round end reaches the director (%d -> %d)"
			% [played, maps.director.clock.rounds_played]
	)

	rules.trigger = saved[0]
	rules.duration_sec = saved[1]
	rules.score_limit = saved[2]
	rules.vote_lead_score = saved[3]
	rules.min_players_to_vote = saved[4]
	rules.vote_warning_sec = saved[5]
	rules.allow_single_voter_auto = saved[6]
	maps.director.begin(maps.director.current_id())

	# [b]The `map time` line follows an extend.[/b] It was a `DotMapTimeLimit` built beside
	# the vote and advanced in step with it, which nothing extended: an operator reading
	# `hungry_vote status` after the players voted to extend saw the old limit.
	var before_line := _map_time_line(maps.describe_lines())
	var extended := maps.director.extend()
	var after_line := _map_time_line(maps.describe_lines())
	_check(
		extended.ok and after_line != before_line
			and after_line.ends_with(maps.director.clock.formatted_remaining()),
		"an extend moves the mode's time left where an operator reads it (%s -> %s)"
			% [before_line.strip_edges(), after_line.strip_edges()],
		"the descriptive clock would still say what it said before"
	)
	maps.director.begin(maps.director.current_id())


## `time_up: finish_round` waits for a round being played, never for warmup. Run on a director of
## its own carrying the game's `round_in_progress_fn`, with the match's state set by hand and
## put back, so the real vote's clock is untouched.
func _test_finish_round_waits_for_a_live_round() -> void:
	_section("finish_round waits for a live round, not warmup")
	var module := _module()
	var director: DotVoteDirector = module.maps.director if module != null and module.maps != null else null
	var hook: Variant = director.get("round_in_progress_fn") if director != null else null
	_check(hook is Callable and (hook as Callable).is_valid(), "the game tells its vote whether a round is live")

	if not (hook is Callable and (hook as Callable).is_valid()) or module.world == null or module.world.match_node == null:
		_done()
		return

	var match_node: DotMatch = module.world.match_node
	var was := match_node.state
	match_node.state = DotMatch.State.WARMUP
	var warm_applied := []
	var warm := _finish_round_probe(hook, warm_applied)
	_check(warm_applied == [&"b"] and not warm.is_finishing_round(),
		"in warmup a time limit with finish_round changes at once", str(warm_applied))

	match_node.state = DotMatch.State.LIVE
	var live_applied := []
	var live := _finish_round_probe(hook, live_applied)
	_check(live_applied.is_empty() and live.is_finishing_round(),
		"during a live round it waits for the round", str(live_applied))

	match_node.state = DotMatch.State.INTERMISSION
	live.advance(0.1)
	_check(live_applied == [&"b"], "and the round ending is the change", str(live_applied))

	match_node.state = was
	warm.queue_free()
	live.queue_free()
	_done()


## A director under `time_up: finish_round` carrying [param hook], its clock run out with a
## winner already decided: what dot-vote's own suite builds, with the game's answer in it.
func _finish_round_probe(hook: Callable, applied: Array) -> DotVoteDirector:
	var source := DotVoteListSource.new()
	var _a := source.add(DotVoteChoice.of(&"a", "A"))
	var _b := source.add(DotVoteChoice.of(&"b", "B"))
	source.apply_fn = func(id: StringName) -> DotResult:
		applied.append(id)
		return DotResult.success(id)

	var rules := DotVoteRules.new()
	rules.apply_delay_sec = 0.0
	rules.duration_sec = 100.0
	rules.vote_lead_sec = 40.0
	rules.vote_duration_sec = 5.0
	rules.include_extend = false
	rules.apply = DotVoteRules.Apply.END_OF_TIME
	rules.cooldown = 0
	rules.time_up = DotVoteRules.TimeUp.FINISH_ROUND
	# For ever: only the hook may release it.
	rules.finish_round_max_sec = 0.0

	var probe := DotVoteDirector.new()
	probe.rules = rules
	probe.source = source
	probe.register_service = false
	probe.self_advance = false
	probe.round_based = true
	probe.player_count_fn = func() -> int: return 4
	probe.set(&"round_in_progress_fn", hook)
	add_child(probe)
	probe.begin(&"a")
	source.current = &"a"

	for i in range(61):
		probe.advance(1.0)

	probe.cast_one(&"p1", &"b")

	# The ballot closes, then the limit (100 s) runs out with the winner decided.
	for i in range(46):
		probe.advance(1.0)

	return probe


func _map_time_line(lines: PackedStringArray) -> String:
	for line in lines:
		if line.begins_with("map time"):
			return line
	return ""
