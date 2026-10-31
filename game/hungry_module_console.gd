extends "res://game/hungry_module_state.gd"

func _register_console() -> void:
	_register_commands()
	_register_bots()
	_register_tuning()

func _register_commands() -> void:
	# `.with_chat()` keeps a command typable from chat on a server whose operator turned sv_chat_commands off;
	# the flag still decides who may run it. `.no_chat()` marks one about the operation, not the asker.
	# Marked here are the player-facing and moderation commands.
	add_command(
		"hungry_status", _cmd_status, "Show the world", DotAdminFlags.GENERIC
	).with_chat()
	add_command("hungry_top", _cmd_top, "Show the leaderboard", "").with_chat()
	add_command(
		"hungry_loadouts", _cmd_loadouts, "Show what players brought in",
		DotAdminFlags.GENERIC
	)
	add_command("hungry_net", _cmd_net, "Show the netcode", DotAdminFlags.GENERIC)
	add_command(
		"hungry_restart", _cmd_restart, "Restart the round", DotAdminFlags.CHANGEMAP
	)
	add_command(
		"hungry_rotation", _cmd_rotation,
		"hungry_rotation [name] — switch to a rotation in maps.yml, or list them",
		DotAdminFlags.CHANGEMAP
	)
	add_command(
		"hungry_maps_reload", _cmd_maps_reload, "Re-read maps.yml", DotAdminFlags.CHANGEMAP
	)
	add_command(
		"hungry_give",
		_cmd_give,
		"hungry_give <player> <pepper|frost|lure> — hand somebody a throwable",
		DotAdminFlags.CHEATS
	)
	add_command(
		"hungry_burst",
		_cmd_burst,
		"hungry_burst <player> — blow somebody apart",
		DotAdminFlags.CHEATS
	)

	add_command(
		"hungry_services", _cmd_services,
		"Show chat, voice and moderation", DotAdminFlags.GENERIC
	).with_chat()
	add_command(
		"hungry_hunters", _cmd_hunters,
		"hungry_hunters [on|off|clear] — the NPC monsters", DotAdminFlags.GENERIC
	).with_chat()
	add_command(
		"hungry_hazards", _cmd_hazards,
		"hungry_hazards [scatter <n>|clear] — rocks, spikes and lures",
		DotAdminFlags.CHANGEMAP
	)
	add_command(
		"hungry_boards", _cmd_boards,
		"hungry_boards [board] — the persistent leaderboards", ""
	).with_chat()
	add_command(
		"hungry_vote", _cmd_vote,
		"hungry_vote [open|status|next] — what plays next", DotAdminFlags.CHANGEMAP
	).with_chat()
	# MUTE rather than BAN: quieting somebody and removing them are different powers, and
	# dot-server's own flags are what distinguish them.
	add_command(
		"hungry_gag", _cmd_gag,
		"hungry_gag <who> <seconds> [reason]", DotAdminFlags.MUTE
	).with_chat()
	add_command(
		"hungry_mute", _cmd_mute,
		"hungry_mute <who> <seconds> [reason]", DotAdminFlags.MUTE
	).with_chat()

func _register_bots() -> void:
	# How many bots is dot-server's DotBotQuota, so bot_quota means the same on every server.
	# The fill default of six gives a lone player the game they get offline less one bot.
	_quota = DotBotQuota.install(self, HungryTuning.settings().bot_fill)

	# How well they play: dot-bot's `bot_difficulty` and its `bot_*` settings, on the world
	# [HungryBot] reads them from (sight, reaction, throw aim).
	var _bot_cvars := DotBotSettings.of(world).bind_cvars(add_cvar, DotConVar.FLAG_NOTIFY, add_command)

	# [b]Deprecated: `hungry_bots` was a FIXED count[/b], and it is kept as an alias that
	# means exactly that — `bot_quota N` in `fixed` mode — so a config or an operator who
	# typed it gets what they always got, with one cvar still deciding the count.
	_cv_bots = add_cvar("hungry_bots", "0", "Deprecated: sets bot_quota to this and bot_quota_mode to fixed.")
	_cv_bots.changed.connect(func(_old: String, _value: String) -> void:
		if _quota == null or _quota.quota_cvar == null or _quota.mode_cvar == null:
			return
		var _mode := _quota.mode_cvar.set_value("fixed")
		var _count := _quota.quota_cvar.set_value(str(maxi(_cv_bots.get_int(), 0))))

func _register_tuning() -> void:
	# Hunters are off by default: that is an operator's decision, not an addon's.
	# How an eaten monster goes down on every screen: the server picks each death's reaction
	# from these (HungryWorld.decide_death); REPLICATED, because the clients draw the falls.
	var _ragdolls := ragdoll_rules.bind_cvars(
		add_cvar, DotConVar.FLAG_ARCHIVE | DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED
	)

	var _ambient := ambient_rules.bind_cvars(
		add_cvar, DotConVar.FLAG_ARCHIVE | DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED,
		DotConVar.FLAG_ARCHIVE | DotConVar.FLAG_NOTIFY
	)

		# Every server config field is a `hungry_<field>` cvar bound by the same call, so a yml key, a
		# workbench edit and a console `set` are one value.
	_bind_tuning()
	_cv_hunters = HungryTuning.binder.cvar_for("hunters_on")
	_cv_hunters.changed.connect(func(_old: String, value: String) -> void:
		if hunters != null:
			hunters.set_enabled(value != "0")
	)

	_cv_hazards = HungryTuning.binder.cvar_for("hazards_count")

	# What a monster that has outgrown a refuge does: accept (the default and the mode's
	# usual), cap or eject. Empty leaves the mode's own. Live: it applies from the next tick.
	var outgrown := HungryTuning.binder.cvar_for("outgrown")
	var apply_outgrown := func(_old: String, value: String) -> void:
		var rule := ["accept", "cap", "eject"].find(value.strip_edges().to_lower())
		if world != null and rule >= 0:
			world.outgrown = rule
		elif world != null and value.strip_edges() == "":
			world.outgrown = world.preset.outgrown if world.preset != null else 0
	outgrown.changed.connect(apply_outgrown)
	apply_outgrown.call("", outgrown.get_string())

		# `hungry_warrens_corners` applies from the next mode change (rocks do not move under a live round);
		# registered whether or not hunters are on, so config order does not matter.
	npc_skill.bind_cvars(add_cvar, DotConVar.FLAG_NOTIFY)

	# Where this server's rider cosmetics live. Empty means "whatever the client shipped
	# with", which is every deployment that has not published a pack — and a client with
	# no dot-cloud installed ignores it either way.
	_cv_pack = HungryTuning.binder.cvar_for("avatar_pack")
	_cv_pack.changed.connect(func(_old: String, _new: String) -> void: _sync_pack())
	_sync_pack()

	# A path, not the token. See [method _build_reporting].
	_cv_auth_config = HungryTuning.binder.cvar_for("backbone_config")

func _cmd_status(ctx: DotCmdContext) -> void:
	ctx.reply_lines(world.describe_lines())
	ctx.reply_lines(hbridge.describe_lines())

	if _last_spoke != "":
		ctx.reply("last spoke   %s" % _last_spoke)

	if hunters != null:
		ctx.reply_lines(hunters.describe_lines())

	if hazards != null:
		ctx.reply_lines(hazards.describe_lines())

	if maps != null:
		ctx.reply_lines(maps.describe_lines())

func _cmd_services(ctx: DotCmdContext) -> void:
	ctx.reply_lines(hservices.describe_lines())

	if combat != null:
		ctx.reply_lines(combat.describe_lines())

func _cmd_hunters(ctx: DotCmdContext) -> void:
	match ctx.arg(0):
		"on":
			hunters.set_enabled(true)
			ctx.reply("Hunters are on.")
		"off":
			hunters.set_enabled(false)
			ctx.reply("Hunters are off, and the arena is cleared of them.")
		"clear":
			var gone := hunters.spawner.clear_all()
			ctx.reply("Cleared %d." % gone)
		_:
			ctx.reply_lines(hunters.describe_lines())

func _cmd_hazards(ctx: DotCmdContext) -> void:
	match ctx.arg(0):
		"scatter":
			var count := maxi(1, ctx.arg_int(1, 8))
			# Seeded from the world rather than from a clock, so `hungry_hazards scatter`
			# twice on one world lays out the same arena twice. A server an operator can
			# reproduce is worth more than one that surprises them.
			var made := hazards.scatter(&"rock", count, world.field.seed_value())
			ctx.reply("Scattered %d rocks." % made)
		"clear":
			ctx.reply("Cleared %d." % hazards.clear_all())
		_:
			ctx.reply_lines(hazards.describe_lines())

func _cmd_boards(ctx: DotCmdContext) -> void:
	var board_id := StringName(ctx.arg(0, "top_mass"))
	if progress.boards != null and progress.boards.backend == "backbone":
		ctx.reply("Fetching the board...")

	var rows: Array = await progress.page(board_id, 10)

	if rows.is_empty():
		ctx.reply("Nothing on '%s' yet." % String(board_id))
		return

	var rank := 1

	for row in rows:
		var entry: DotLeaderboardEntry = row
		ctx.reply("%2d. %-24s %s" % [rank, entry.player_name, entry.value])
		rank += 1

func _cmd_vote(ctx: DotCmdContext) -> void:
	match ctx.arg(0):
		"open":
			var opened := maps.director.open_vote()
			ctx.reply_error(opened) if not opened.ok else ctx.reply("Vote opened.")
		"next":
			ctx.reply("Next in rotation: %s" % String(maps.next_in_rotation()))
		_:
			ctx.reply_lines(maps.describe_lines())

func _cmd_gag(ctx: DotCmdContext) -> void:
	await _punish(ctx, DotPunishment.Kind.GAG, "gagged")

func _cmd_mute(ctx: DotCmdContext) -> void:
	await _punish(ctx, DotPunishment.Kind.VOICE_MUTE, "muted")

## The shared half of gag and mute.
## One function because dot-moderation models both as one record, and two copies would each need the
## duration parsing and the immunity.
func _punish(ctx: DotCmdContext, kind: DotPunishment.Kind, verb: String) -> void:
	if ctx.args.size() < 2:
		ctx.reply("Usage: %s <who> <seconds, 0 for permanent> [reason]" % ctx.command)
		return

	var targets := server.find_sessions(ctx.args[0], ctx.session)

	if targets.is_empty():
		ctx.reply("Nobody matches '%s'." % ctx.args[0])
		return

	if targets.size() > 1:
		# Refused rather than applied to all of them: `@me` and a name prefix both match
		# more than one person, and a mute applied to four people by accident is a thing
		# an operator finds out about from the four people.
		ctx.reply("'%s' matches %d people. Be more specific." % [
			ctx.args[0], targets.size()
		])
		return

	var session := targets[0]
	var seconds := maxi(0, ctx.arg_int(1))
	var reason := ctx.rest(2) if ctx.args.size() > 2 else "No reason given."

	var issued: DotResult = await hservices.moderation.issue(
		kind,
		DotPunishmentSubject.for_uid(session.uid()),
		reason,
		ctx.caller_label(),
		seconds,
		ctx.immunity
	)

	if not issued.ok:
		ctx.reply("Refused: %s" % issued.error.message)
		return

	ctx.reply("%s %s: %s" % [
		session.display_name, verb, DotPunishment.format_duration(seconds)
	])

	# Told to the person it happened to, on the channel they are reading. A mute nobody is
	# told about is a microphone that has stopped working, which is what they report.
	hservices.chat.notice(
		session.peer_id,
		(issued.value as DotPunishment).player_message(),
		HungryServices.CHANNEL_ALL
	)

func _cmd_top(ctx: DotCmdContext) -> void:
	var rank := 1

	for monster in world.leaderboard(10):
		ctx.reply("%2d. %-18s %8.0f  %d pieces" % [
			rank, monster.display_name, monster.mass(), monster.piece_count()
		])
		rank += 1

func _cmd_loadouts(ctx: DotCmdContext) -> void:
	for monster in world.leaderboard(20):
		ctx.reply("%-18s %-8s %-8s" % [
			monster.display_name.substr(0, 18),
			String(monster.trait_id),
			String(monster.starter_item()),
		])

	ctx.reply_lines(loadouts.describe_lines())

func _cmd_net(ctx: DotCmdContext) -> void:
	ctx.reply_lines(net.describe_lines())
	ctx.reply("link     %s" % str(hbridge.link.describe()))

func _cmd_restart(ctx: DotCmdContext) -> void:
	world.start(tick)
	ctx.reply("Round restarted.")

func _cmd_rotation(ctx: DotCmdContext) -> void:
	if maps == null or maps.rotation_file == null:
		ctx.reply("There is no maps.yml; every mode rotates.")
		return

	if ctx.args.is_empty():
		ctx.reply("Rotations: %s (active: %s)" % [
			", ".join(maps.rotation_file.rotation_names()), maps.rotation_file.active_name(),
		])
		return

	var switched := maps.switch_rotation(ctx.arg(0))
	ctx.reply_error(switched) if not switched.ok else ctx.reply("Rotation: %s" % ctx.arg(0))

func _cmd_maps_reload(ctx: DotCmdContext) -> void:
	var read := maps.load_rotation() if maps != null else DotResult.fail(DotError.CODE_STATE, "No maps.")
	ctx.reply_error(read) if not read.ok else ctx.reply("maps.yml re-read.")

func _cmd_give(ctx: DotCmdContext) -> void:
	if ctx.args.size() < 2:
		ctx.reply("hungry_give <player> <pepper|frost|lure>")
		return

	var item := StringName(ctx.args[1])

	if world.items.find(item) == null:
		ctx.reply("There is no item called '%s'." % ctx.args[1])
		return

	var monster := _target(ctx, ctx.args[0])

	if monster == null:
		return

	if not monster.take_item(item):
		ctx.reply("%s is already carrying the maximum." % monster.display_name)
		return

	hbridge.send_carry(monster.id)
	ctx.reply("Gave %s a %s." % [monster.display_name, ctx.args[1]])

func _cmd_burst(ctx: DotCmdContext) -> void:
	if ctx.args.is_empty():
		ctx.reply("hungry_burst <player>")
		return

	var monster := _target(ctx, ctx.args[0])

	if monster == null:
		return

	var made := world.burst(monster, 0)
	ctx.reply("Burst %s into %d more pieces." % [monster.display_name, made])

## Resolves a console argument to a monster: a session (through [method DotServer.resolve_target], so
## `#userid`, partial names and `@all` work) or a bot by name.
func _target(ctx: DotCmdContext, needle: String) -> HungryMonster:
	var sessions := server.find_sessions(needle)

	if sessions.size() == 1:
		var monster := world.monster_for(sessions[0].userid)

		if monster != null:
			return monster

	var lowered := needle.to_lower()

	for bot_id in _bots.keys():
		if String(_bots[bot_id]).to_lower().contains(lowered):
			return world.monster_for(int(bot_id))

	ctx.reply(
		"No player matched '%s'." % needle if sessions.size() != 1
		else "That player is not in the world."
	)
	return null
