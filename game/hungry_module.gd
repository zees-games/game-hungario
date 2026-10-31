extends "res://game/hungry_module_events.gd"

func _game_service() -> StringName:
	return HungryWorld.SERVICE

func _game_missing_hint() -> String:
	return "load a mode scene first, or set DotGameManager.initial_game to '%s'" % GAME_CLASSIC

func _net_config() -> DotNetConfig:
	var config := DotNetConfig.new()
	config.tick_rate = (game as HungryWorld).tick_rate
	config.snapshot_rate = SNAPSHOT_RATE
	config.enable_prediction = true
	config.enable_lag_compensation = false
	# The pieces are what a snapshot is made of, and a crowded fight is a lot of them.
	config.max_entities_per_snapshot = 120
	config.world_extent = Dot2DNetSync.WORLD_EXTENT
	config.reconcile_position_epsilon = HungryNetBridge.RECONCILE_EPSILON
	return config

func _make_bridge() -> Node:
	return HungryNetBridge.new()

func _wants_platform_module() -> bool:
	return false

func _make_services() -> Node:
	var made := HungryServices.new()
	made.bridge = bridge as HungryNetBridge
	made.world = world
	made.server = server
	made.punishments_path = punishments_path
	return made

func _map_config_keys() -> Dictionary:
	return HungryMapConfig.KEYS

func _map_config_game() -> String:
	return HungryMapConfig.GAME_ID

func _game_load() -> DotResult:
	# Strict on a dedicated server: a typo in cfg/ stops the boot instead of being ignored.
	var tuned := HungryTuning.result()

	if tuned.ok:
		tuned = HungryModes.result()

	if not tuned.ok:
		DotGameConfigBinder.fail_boot(get_tree(), tuned)
		return tuned

	world.ragdoll_rules = ragdoll_rules
	world.loading_fn = is_loading

	var loadouts_ready := _build_loadouts()

	if not loadouts_ready.ok:
		return loadouts_ready

	if hservices == null:
		return DotResult.fail(DotError.CODE_STATE, "The services could not be set up")

	hbridge.peer_admitted.connect(_on_peer_admitted)
	hbridge.say_requested.connect(_on_say_requested)
	hbridge.voice_requested.connect(_on_voice_requested)
	hbridge.vote_requested.connect(_on_vote_requested)
	hservices.command_entered.connect(_on_chat_command)
	# The server's own view of a bubble, off the signal that fires after a line was accepted.
	hservices.chat.message_accepted.connect(_on_chat_accepted)
	_build_mod_tools()

	# dot-server's own chat is cancelled in a pre-hook: dot-chat has the rules, and two paths
	# would let the one that skipped the filter leak admin chat.
	hook_pre("player_chat", _on_player_chat)

	# dot-chat makes the join and leave notices now.
	if server.chat != null:
		server.chat.announce_joins = false

	_register_games()
	_register_console()
	# The cvars exist only now, so the first map's file can apply.
	var _reported := report_map(String(world.preset.id))
	_build_query_provider()

	_build_reporting()
	_build_stats()

	var fought := _build_combat()

	if not fought.ok:
		return fought

	var hunted := _build_hunters()

	if not hunted.ok:
		return hunted

	var earned := _build_progress()

	if not earned.ok:
		return earned

	var mapped := _build_maps()

	if not mapped.ok:
		return mapped

	if Engine.physics_ticks_per_second != world.tick_rate:
		# Not corrected: `sv_tickrate` is the operator's. Loud, because the symptom is a game at the wrong speed.
		log_warn("sv_tickrate does not match the world's tick rate", {
			"engine": Engine.physics_ticks_per_second,
			"world": world.tick_rate,
		})

	world.start(0)
	_start_workbench()

	if maps != null:
		maps.note_playing(game_id_of(world.preset.id))

	log_info("hungry loaded", {
		"preset": String(world.preset.id),
		"world": world.world_size,
		"food": world.field.food_count(),
	})

	return DotResult.success(null)

func _game_unload() -> void:
	if stats != null:
		DotRegistry.unregister_instance(DotGameStatsFeed.SERVICE, stats)

	if workbench != null:
		workbench.queue_free()
		workbench = null

	if world != null and is_instance_valid(world):
		world.loading_fn = Callable()

	if server != null and server.client_disconnected.is_connected(_on_client_disconnected):
		server.client_disconnected.disconnect(_on_client_disconnected)

	# Every player this module put in the world comes out with it, or the world keeps
	# monsters whose sessions no longer exist.
	if hbridge != null and is_instance_valid(hbridge):
		for userid in _joined.keys():
			hbridge.remove_peer(hbridge.peer_for_player(int(userid)))

	if world != null and is_instance_valid(world):
		for bot_id in _bots.keys():
			world.remove_player(int(bot_id))

	_bots.clear()

	if backbone != null and is_instance_valid(backbone):
		# A try only: `report_offline` suspends and this is not a coroutine, so the request is
		# issued and the node freed with the reply unread; the listing's staleness window covers the rest.
		backbone.report_offline()
		backbone.queue_free()
		backbone = null

## Rebinds onto the world the new mode brought with it.
##
## Called by [DotModuleHost] after [DotGameManager] has swapped the scene. The world is a
## different object; every player and every connection is the same one.
func _module_game_changed(content_key: String) -> void:
	var next := DotRegistry.get_node_service(HungryWorld.SERVICE) as HungryWorld

	if next == null:
		log_warn("the new game registered no world; the module is now idle", {
			"content_key": content_key
		})
		world = null
		return

	# The world and its loading hook are set before report_map, which marks the seats
	# loading on a new map and notifies listeners that ask the world whether it can harm them.
	var changed := next != world
	if changed:
		world = next
		world.ragdoll_rules = ragdoll_rules
		world.loading_fn = is_loading

	# Before the same-world check, not after it: the game manager forgets the map every
	# time it unloads a scene, so this has to be said again on every change.
	report_map(String(next.preset.id))

	if not changed:
		return

	# Every client covers for the new mode and says so when it lifts; until it does nobody is
	# harmed, and one that never re-covers is released after the roster's grace.
	mark_reloading()

	# Everything that holds a world holds the new one. A layer left pointing at a freed
	# scene is a use-after-free on the next tick, and the ones that hold *placements*
	# rather than nodes have to be told to forget them — the arena is a different shape
	# now and a rock from the last mode would be a rock in the wall.
	if hunters != null:
		hunters.world = world
		hunters.spawner.clear_all()

	if hazards != null:
		hazards.world = world
		hazards.clear_all()

	if hservices != null:
		hservices.world = world

	_watch_spawns(world)

	# The moderator's return history goes too, for everybody. Every position in it is a point
	# in the arena that was just freed, so `return <player>` after a change put them where
	# they had stood in a different mode — inside a rock of the reef, or past the edge of a
	# smaller arena. [method DotModTools.respawned] keeps the history on purpose, because a
	# respawn in the same arena leaves a return meaningful; a game change is the one case
	# where none of it can be, and that includes players who left before the change.
	if mod_tools != null:
		mod_tools.clear_history()

	if combat != null:
		world.damage_gate = combat.gate

	if progress != null:
		progress.mode_id = StringName(next.preset.id)

	if maps != null:
		maps.note_playing(game_id_of(next.preset.id))

	var rebound := hbridge.rebind(world)

	if not rebound.ok:
		log_warn("could not rebind the bridge", {"error": str(rebound.error)})
		return

	# The bots are the old world's. Their ids are not reused, because a client that still
	# holds the old monster under that id would otherwise be handed a new one silently.
	_bots.clear()

	world.start(tick)

	log_info("rebound onto a new world", {
		"preset": String(world.preset.id), "content_key": content_key
	})

func _build_mod_tools() -> void:
	var world_fn := func() -> HungryWorld: return world

	mod_tools = DotModTools.new()
	mod_tools.name = "ModTools"
	mod_tools.register_service = false
	mod_tools.manager = hservices.moderation
	mod_tools.immunity_fn = func(id: StringName) -> int:
		var session := server.session_by_userid(String(id).to_int()) if String(id).is_valid_int() else null
		return session.immunity if session != null else 0
	mod_tools.position_fn = func(id: StringName) -> Variant:
		return HungryModTools.position_of(world_fn, id)
	mod_tools.teleport_fn = func(id: StringName, to: Variant) -> void:
		HungryModTools.teleport(world_fn, id, to)
	# A monster's stand-off is its radius, not a person's arm's length: a moderator who
	# goes to a big one lands inside it at 1.5.
	mod_tools.goto_standoff = 120.0

	var table := HungryModTools.handlers(world_fn)
	for action: Variant in table:
		mod_tools.handlers[action] = table[action]

	var refusals := HungryModTools.unsupported()
	for action: Variant in refusals:
		mod_tools.unsupported_reasons[action] = refusals[action]

	for action in HungryModTools.PERSIST_ON_RESPAWN:
		if not mod_tools.persist_on_respawn.has(action):
			mod_tools.persist_on_respawn.append(action)

	add_child(mod_tools)

	_watch_spawns(world)

	mod_commands = DotModToolCommands.install(self, mod_tools, server)
	mod_commands.alive_fn = func(id: StringName) -> bool:
		var monster := world.monster_for(String(id).to_int()) if world != null else null
		return monster != null and monster.alive
	mod_commands.items_fn = func() -> PackedStringArray:
		return HungryModTools.item_ids(world_fn)

## A spawn is a new body, and dot-moderation has to be told: it switches noclip and freeze
## off through the handlers and keeps what persists (god, buddha, and here blind and beacon,
## which it re-applies through the same handlers). Without this an admin's
## noclip would ride a monster through its death into the next life — the bits live on
## [HungryMonster], which outlives its pieces — where every other game starts a new body
## clean. Arena does this from its own spawn path; this game's spawn path is
## [signal HungryWorld.player_spawned].
func _watch_spawns(target: HungryWorld) -> void:
	if target == null or mod_tools == null:
		return

	if not target.player_spawned.is_connected(_on_player_spawned_for_tools):
		target.player_spawned.connect(_on_player_spawned_for_tools)

func _on_player_spawned_for_tools(player_id: int) -> void:
	if mod_tools != null:
		mod_tools.respawned(StringName(str(player_id)))

func _build_combat() -> DotResult:
	combat = HungryCombat.new()
	combat.name = "Combat"
	add_child(combat)

	var ready := combat.setup()

	if not ready.ok:
		return ready.wrap("The combat rules could not be set up")

	# The world asks and dot-combat answers. Unset — which is what every deployment
	# without this addon has — leaves the constants this game has always used.
	world.damage_gate = combat.gate

	return DotResult.success(null)

func _build_hunters() -> DotResult:
	hunters = HungryHunters.new()
	hunters.name = "Hunters"
	hunters.npc_skill = npc_skill
	add_child(hunters)

	var ready := hunters.setup(true, world)

	if not ready.ok:
		return ready.wrap("The hunters could not be set up")

	hazards = HungryHazards.new()
	hazards.name = "Hazards"
	add_child(hazards)

	var placed := hazards.setup(true, world)

	if not placed.ok:
		return placed.wrap("The hazards could not be set up")

	hunters.set_enabled(_cv_hunters != null and _cv_hunters.get_int() != 0)
	hunters.hunter_changed.connect(_on_hunter_changed)
	hunters.piece_hunted.connect(_on_piece_hunted)
	hazards.placed.connect(_on_hazard_placed)
	hazards.cleared.connect(_on_hazard_cleared)
	hazards.struck.connect(_on_hazard_struck)

	return DotResult.success(null)

func _build_progress() -> DotResult:
	progress = HungryProgress.new()
	progress.name = "Progress"
	progress.stats = stats
	progress.backbone = backbone
	progress.mode_id = StringName(world.preset.id)
	add_child(progress)

	var ready := progress.setup()

	if not ready.ok:
		return ready.wrap("Progress could not be set up")

	progress.earned.connect(_on_earned)

	return DotResult.success(null)

func _build_maps() -> DotResult:
	maps = HungryMaps.new()
	maps.name = "Maps"
	# People, not bots: a bot never votes, so counting one raised every threshold, and a server
	# of bots with nobody on it was never "empty" to the vote — its limit opened a ballot
	# nobody answered instead of moving on (DotVoteRules.empty_choice).
	maps.player_count_fn = func() -> int: return maxi(world.player_ids().size() - _bots.size(), 0)
	maps.is_admin_fn = _voter_is_admin

	# The drawn ballot, to each playing session with its own voter id — this game's voters
	# are the bare userid — so the client shell marks the player's own choice.
	maps.ballot_fn = func(state: Dictionary) -> void:
		for session in server.playing_sessions():
			var data := state.duplicate()
			data["you"] = str(session.userid)
			server.send_notice(session, DotNotice.make(
				&"", "", float(state.get("seconds", -1.0)), MAP_BALLOT_TOPIC, data
			))

	maps.people_fn = func(voter: StringName) -> Dictionary:
		var session := server.session_by_userid(String(voter).to_int())

		if session == null:
			return {}

		var avatar: Variant = session.identity.get("avatar_url") if session.identity != null else ""
		return {"name": session.display_name, "avatar": avatar if avatar is String else ""}

	add_child(maps)

	var ready := maps.setup(server.games)

	if not ready.ok:
		return ready.wrap("The map rotation could not be set up")

	maps.change_due.connect(_on_change_due)
	maps.announced.connect(_on_vote_announced)

	# The cues and the countdown, to every client. The ballot goes out as chat through
	# `announced`; a sound and a number a HUD counts are what chat cannot carry.
	maps.cue_due.connect(func(cue: StringName, seconds_left: int, runoff: bool) -> void:
		if hbridge != null:
			hbridge.broadcast_vote_cue(cue, seconds_left, runoff)
	)

	# The match a round ends in, and the leading score, for the vote. Callables, because a
	# mode change replaces the world and the match with it.
	maps.match_fn = func() -> DotMatch:
		return world.match_node if world != null else null
	maps.score_fn = func() -> int:
		var best := 0.0

		if world != null:
			for id in world.player_ids():
				var monster := world.monster_for(id)

				if monster != null:
					best = maxf(best, monster.mass())

		return int(best)

	var commanded := maps.install_commands(self)
	DotLog.result(CHANNEL, "the vote's commands", commanded)

	return DotResult.success(null)


func _build_loadouts() -> DotResult:
	loadouts = DotLoadoutManager.new()
	loadouts.name = "Loadouts"
	loadouts.schema = hbridge.loadout_schema
	loadouts.register_service = true
	loadouts.load_layered_config = false
	loadouts.config_file = ""

	var config := DotLoadoutConfig.new()
	config.backend = "memory"
	config.allow_default_loadout = true
	# Conform on the way out of the store, validate on the way in from a client. Retiring
	# an item or revoking an unlock makes a saved loadout invalid, and refusing it is a
	# player who has not played for a month loading into an error rather than into a
	# slightly different monster.
	config.conform_on_load = true
	config.enforce_entitlements = true
	# A player changing their trait mid-fight would change it the moment they were losing.
	# A published loadout takes effect on the next spawn.
	config.allow_live_changes = false
	loadouts.config = config

	add_child(loadouts)

	var ready_result := loadouts.setup()

	if not ready_result.ok:
		return ready_result.wrap("The loadout manager could not start")

	loadouts.entitlement_source = _entitlements_for_key
	hbridge.entitlement_source = _entitlements_for_player
	hbridge.loadout_sink = _store_loadout

	return DotResult.success(null)
