extends "dedicated_base.gd"

## Boot-up and first sections of the dedicated suite: world, module, commands, stats, bots, loadouts, reporting, netcode.


func _test_world() -> void:
	_section("the world")

	var world := _world()

	_check(world != null, "the mode scene registered one")

	if world == null:
		_done()
		return

	_check(world.is_authority, "and it is the authority")
	_check(
		world.field.food_count() > 0,
		"with food in it (%d)" % world.field.food_count()
	)
	_check(
		String(world.preset.id) == "classic",
		"under the classic preset (%s)" % world.preset.id
	)
	_done()


func _test_module() -> void:
	_section("the module")

	_check(_server.modules.has_module("hungry"), "is listed among the server's modules")

	var module := _module()
	_check(module != null and module.world == _world(), "and holds the world")

	for command in [
		"hungry_status", "hungry_top", "hungry_net", "hungry_restart",
		"hungry_give", "hungry_burst", "hungry_loadouts",
	]:
		_check(
			_server.console.find_command(command) != null, "registered %s" % command
		)

	for cvar in ["hungry_bots", "hungry_avatar_pack", "hungry_pepper_damage", "hungry_hunters_on", "hungry_fruit_effect_sec"]:
		_check(_server.console.find_cvar(cvar) != null, "and its %s cvar" % cvar)

	_check(module.workbench != null and module.workbench.api != null, "and the workbench over its config")
	var amb: DotResult = module.workbench.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "set", "kind": "ambience", "id": DotGameWorkbench.CVAR_SET_ID, "key": "hungry_ambient_volume", "value": 0.2})
	_check(amb.ok and is_equal_approx(_server.console.get_float("hungry_ambient_volume"), 0.2), "the hungry_ambient* cvars are a workbench set and an edit moves the cvar", "" if amb.ok else amb.error.message)
	var _amb_back := _server.console.set_cvar("hungry_ambient_volume", "0.3")
	var respawn := _server.console.find_cvar("hungry_respawn_delay_sec")
	var _set := respawn.set_value("7")
	_check(is_equal_approx(_world().match_node.rules.respawn_delay_sec, 7.0), "a config cvar changes the live match rules")
	var _back := respawn.set_value("3")

	# The cosmetics manifest is a cvar rather than a constant because a community server
	# may ship its own parts, and it reaches joining clients through the hello — a client
	# that had to be told out of band is a client that will not be.
	_check(
		module.bridge.avatar_pack_url == "",
		"with no rider content configured by default"
	)
	_check(
		_server.console.execute(
			"hungry_avatar_pack https://cdn.example/hungry/manifest.json"
		).ok,
		"setting one is accepted"
	)
	_check(
		module.bridge.avatar_pack_url == "https://cdn.example/hungry/manifest.json",
		"and reaches the bridge, which is what tells a client (%s)"
			% module.bridge.avatar_pack_url
	)
	_server.console.execute("hungry_avatar_pack \"\"")

	for game_id in [HungryModule.GAME_CLASSIC, HungryModule.GAME_FRENZY]:
		_check(
			_server.games.find_game(game_id) != null,
			"and the %s descriptor is registered" % game_id
		)
	_done()


func _test_commands() -> void:
	_section("its commands")

	for command in [
		"hungry_status", "hungry_top", "hungry_net", "hungry_restart",
		"hungry_loadouts",
	]:
		_check(_server.console.execute(command).ok, "%s runs" % command)

	# The cheat commands are gated by a permission rather than by a flag on the handler,
	# and a console context is trusted — so what is checked here is that they run, and
	# that their argument handling refuses rather than crashes.
	_check(
		_server.console.execute("hungry_give nobody pepper").ok,
		"hungry_give runs and reports a missing target"
	)
	_check(
		_server.console.execute("hungry_give").ok,
		"and with no arguments prints its usage"
	)
	_check(
		_server.console.execute("hungry_burst nobody").ok,
		"hungry_burst runs and reports a missing target"
	)


	_done()


## What the module counts and for whom: that world signals reach a tracker keyed by the SCOPED
## id, and that an account id can never be what a stat is filed under (dot-stats has its own
## suite).
func _test_stats() -> void:
	_section("statistics")

	var module := _module()

	_check(module.stats != null, "the module built a tracker")

	if module.stats == null:
		_done()
		return

	var schema := module.stats.schema

	_check(schema != null and schema.validate().ok, "its schema validates")
	_check(
		schema.find(&"top_mass") != null
			and schema.find(&"top_mass").kind == DotStatsDef.Kind.BEST,
		"a biggest-ever is a BEST, so shrinking does not lose the record"
	)
	_check(
		schema.find(&"mass_eaten") != null
			and schema.find(&"mass_eaten").kind == DotStatsDef.Kind.COUNTER,
		"and mass eaten is a counter"
	)
	_check(
		schema.published().size() == schema.size(),
		"every stat is published; this game counts nothing privately"
	)

	# No integration token in a test, so nothing reports — and the tracker still
	# counts, because the session figures are the game's own.
	_check(
		not module.stats.report_to_backbone,
		"reporting is off without a backbone to report through"
	)

	# The bots from the previous section are eating right now. None of them has a
	# scoped key, so none of them is counted: a bot is not a player, and a stat
	# filed for one would be filed under nothing.
	_check(
		module.stats.players().is_empty(),
		"bots are counted for nobody (%d)" % module.stats.players().size()
	)
	_test_stats_wiring(module)
	_done()


func _test_stats_wiring(module: HungryModule) -> void:
	# The wiring, driven directly. Ids are past any real player and POSITIVE: dot-net's varint
	# writer refuses a negative id.
	const ME := 900001
	const THEM := 900002

	var key := &"AAAAAAAAAAAAAAAAAAAAAA"
	module.stats.begin(key, "Test")
	module._stat_keys[ME] = key

	module.world.food_eaten.emit(ME, 0, 4.0)
	module.world.food_eaten.emit(ME, 1, 6.0)
	module.world.piece_eaten.emit(ME, THEM, 10.0)
	module.world.player_died.emit(THEM, ME)
	module.world.monster_burst.emit(THEM, ME, 3)

	var values := module.stats.session_values(key)

	_check(values.get_value(&"food") == 2.0, "eating food counts it")
	_check(
		values.get_value(&"mass_eaten") == 20.0,
		"and its mass adds across food and pieces (%.1f)" % values.get_value(&"mass_eaten")
	)
	_check(values.get_value(&"pieces_eaten") == 1.0, "eating a piece counts it")
	_check(values.get_value(&"kills") == 1.0, "a kill is credited to the killer")
	_check(values.get_value(&"bursts") == 1.0, "and a burst to whoever caused it")

	# A player who kills themselves is not credited with a kill.
	module.world.player_died.emit(ME, ME)
	_check(
		values.get_value(&"kills") == 1.0 and values.get_value(&"deaths") == 1.0,
		"but a self-kill is only a death"
	)

	# THE check. `_begin_stats` asks dot-platform for a SCOPED key and files
	# nothing without one; the account id the identity carries must never be what
	# a figure is filed under, and the reporter refuses one as a second line.
	_check(
		not DotStatsReporter.is_player_id("backbone:clx8f2k0000"),
		"an account id is refused as a player key"
	)
	_check(
		DotStatsReporter.is_player_id(String(key)),
		"and a scoped key is not"
	)

	module.stats.end(key)
	module._stat_keys.erase(ME)

	_check(
		not module.stats.has_player(key),
		"a player who leaves is forgotten"
	)


func _test_bots() -> void:
	_section("bots")

	var module := _module()
	var world := _world()

	_check(module.bot_count() == 0, "there are none before the first tick")

	# The default is DotBotQuota's fill: a person joins through the bridge (peer 0, as a bot is) and
	# `_drive_bots` is called directly, so the count is exact.
	# The sv_ragdoll* set: replicated, and what the world decides deaths from.
	var weights := _server.console.find_cvar("sv_ragdoll_reactions")
	_check(weights != null and weights.has_flag(DotConVar.FLAG_REPLICATED)
			and module.world.ragdoll_rules == module.ragdoll_rules,
		"sv_ragdoll_reactions is replicated, and the world picks deaths from the module's rules")

	var quota := _server.console.find_cvar("bot_quota")
	var quota_mode := _server.console.find_cvar("bot_quota_mode")
	_check(
		quota != null and quota_mode != null and quota.get_int() == HungryTuning.settings().bot_fill
			and quota_mode.get_string() == "fill",
		"the shared bot_quota is %d, in fill mode" % HungryTuning.settings().bot_fill
	)

	var people := world.player_ids().size()
	var wanted := maxi(HungryTuning.settings().bot_fill - people, 0)
	var defaulted := await _until(func() -> bool: return module.bot_count() == wanted)
	_check(defaulted, "an empty server fills itself to the quota (%d of %d)" % [module.bot_count(), wanted])

	var names: Array = []
	for id in world.player_ids():
		if world.monster_for(id) != null and id >= HungryModule.BOT_ID_BASE:
			names.append(world.monster_for(id).display_name)
	_check(not names.is_empty() and names.all(func(n: String) -> bool: return DotBotNames.POOL.has(n)),
		"bots are named from dot-bot's pool, never numbered", str(names))
	var difficulty := _server.console.execute("bot_difficulty hard")
	var reached := DotBotSettings.of(world).difficulty() == "hard"
	var _back := _server.console.execute("bot_difficulty medium")
	_check(difficulty.ok and reached, "bot_difficulty is a cvar, and reaches the world the bots read it from")
	await _test_bots_quota(module, world, quota, quota_mode)
	_done()


func _test_bots_quota(module: HungryModule, world: HungryWorld, quota: DotConVar, quota_mode: DotConVar) -> void:
	var bots_before := module.bot_count()
	var joined := module.bridge.add_player(0, 777, "Person")
	module._drive_bots()
	var bots_with := module.bot_count()
	_check(
		joined.ok and bots_before > 0 and bots_with == bots_before - 1,
		"a person joining takes a bot's place (%d -> %d)" % [bots_before, bots_with]
	)

	world.remove_player(777)
	module._drive_bots()
	_check(
		module.bot_count() == bots_before,
		"and the bot comes back when they leave (%d -> %d)" % [bots_with, module.bot_count()]
	)

	var set_result := _server.console.execute("hungry_bots 4")
	_check(set_result.ok, "hungry_bots 4 is accepted")
	_check(
		quota != null and quota.get_int() == 4 and quota_mode.get_string() == "fixed",
		"and means what it always did: bot_quota 4, fixed (%s, %s)"
			% [quota.get_string() if quota != null else "-", quota_mode.get_string() if quota_mode != null else "-"]
	)
	await _test_bots_play(module, world)


func _test_bots_play(module: HungryModule, world: HungryWorld) -> void:
	# The module fills the population from `_physics_process`, so this needs real frames.
	var filled := await _until(func() -> bool: return module.bot_count() == 4)

	_check(filled, "four appear (%d)" % module.bot_count())
	_check(
		world.monsters().size() >= 4,
		"and they are in the world (%d)" % world.monsters().size()
	)

	var alive := 0

	for monster in world.monsters():
		if monster.alive:
			alive += 1

	_check(alive == 4, "and alive (%d)" % alive)

	# A bot with no peer must not be registered as one. A peer id of zero is the broadcast
	# address, so a bot registered as a peer would make the server build a snapshot
	# against the bot's interest rectangle and send it to every real client.
	_check(
		not module.bridge.net.peers().has(0),
		"and none of them is registered as a peer"
	)

	var before := 0.0

	for monster in world.monsters():
		before = maxf(before, monster.mass())

	var grown := await _until(func() -> bool:
		for monster in world.monsters():
			if monster.mass() > before:
				return true

		return false
	, 12.0)

	_check(grown, "they play the game and grow")

	# Lowered at the end of the loadout section instead, so that section runs with several
	# bots in the world and can see that they do not all bring the same thing.
	_check(module.bot_count() == 4, "and the population holds (%d)" % module.bot_count())


## What players may bring in, and who decides: a server with nothing wired grants nothing, and
## the schema's own defaults are still takeable (or a player cannot spawn).
func _test_loadouts() -> void:
	_section("loadouts")

	var module := _module()

	_check(module.loadouts != null, "the module runs a loadout manager")

	if module.loadouts == null:
		_done()
		return

	_check(
		module.loadouts.schema != null and module.loadouts.schema.validate().ok,
		"with a legal schema"
	)
	_check(
		DotRegistry.get_service(DotLoadoutManager.SERVICE) == module.loadouts,
		"registered where a loadout screen would look for it"
	)

	# Nothing, and deliberately. A server that granted everything by default would work
	# perfectly in every test, ship, and quietly be a game where every unlock is free —
	# and nobody reports that as a bug.
	var owned := module.loadouts.entitlements_for(HungryContent.loadout_key(1))
	_check(owned.count() == 0, "and grants nothing until something says otherwise")

	var default_loadout := module.loadouts.schema.default_loadout()
	_check(
		DotLoadoutValidator.validate(default_loadout, module.loadouts.schema, owned).ok,
		"while its own default is still takeable"
	)

	# The bots are in the world with a loadout, which is the only reason `hungry_loadouts`
	# has anything to print.
	var with_traits := 0

	for monster in _world().monsters():
		if monster.trait_id != &"":
			with_traits += 1

	_check(
		with_traits == _world().monsters().size(),
		"and everybody in the world has a trait (%d of %d)"
			% [with_traits, _world().monsters().size()]
	)
	await _test_loadouts_bots()
	_done()


func _test_loadouts_bots() -> void:
	# The bots take turns through the traits and the throwables, so that a server nobody
	# has joined still exercises the paths a human's choice takes — and so an operator
	# watching one can see the loadout doing something.
	var traits := {}
	var starters := {}

	for monster in _world().monsters():
		traits[monster.trait_id] = true
		starters[monster.starter_item()] = true

	_check(
		traits.size() > 1 or _world().monsters().size() < 2,
		"the bots do not all bring the same one (%d traits)" % traits.size()
	)
	_check(
		not traits.has(HungryContent.TRAIT_GREEDY),
		"and none of them takes the trait nobody has unlocked"
	)
	_check(
		starters.size() > 1 or _world().monsters().size() < 2,
		"nor the same throwable (%d)" % starters.size()
	)

	_check(
		_server.console.execute("hungry_bots 1").ok, "the population can be lowered"
	)

	var lowered := await _until(func() -> bool: return _module().bot_count() == 1)
	_check(lowered, "and it is (%d)" % _module().bot_count())


## What this server tells its site listing: the shape of the report, and that an unconfigured
## server stays silent. Nothing is sent from here; the transport is dot-auth's.
func _test_reporting() -> void:
	_section("what the listing is told")

	var module := _module()

	_check(
		module.backbone == null,
		"a server with no integration token is not listed"
	)
	_check(
		_server.console.find_cvar("hungry_backbone_config") != null,
		"and the token comes from a config file, never a cvar"
	)

	var report := module.stats_report()

	_check(bool(report.get("online", false)), "the report says the server is up")
	_check(
		int(report.get("maxUsers", 0)) > 0,
		"with a slot count (%d)" % int(report.get("maxUsers", 0))
	)

	# dot-server's own report says bots: 0 unconditionally, because dot-server has no bots
	# and no way to know a game has any. A listing that shows eight players on a server
	# holding one human is a listing that stops being trusted.
	_check(
		int(report.get("bots", -1)) == module.bot_count(),
		"and the bots this game actually has (%d)" % int(report.get("bots", -1))
	)
	_check(
		int(report.get("curUsers", -1)) == 0,
		"counted apart from the humans (%d)" % int(report.get("curUsers", -1))
	)

	# The mode rather than the content id: `hungry_frenzy` means something to somebody
	# reading a server browser.
	_check(
		String(report.get("map", "")) == String(_world().preset.id),
		"and the mode as the map (%s)" % str(report.get("map", ""))
	)
	_check(
		_server.games.reported_map() == String(_world().preset.id),
		"and as the query's map, which A2S answers with (%s)" % _server.games.reported_map()
	)

	_check(module.roster_report().is_empty(), "the roster is empty with nobody on")

	_done()


func _test_netcode() -> void:
	_section("the netcode")

	var module := _module()

	_check(module.net != null and module.net.is_running(), "a manager is running")
	_check(module.net.is_server, "as the server")
	_check(module.bridge != null, "with a bridge")

	# The RPC node has to sit where a client's will look for it. Godot addresses an RPC by
	# the receiver's path relative to its MultiplayerAPI root, so the name and the parent
	# are the routing.
	var link := _server.get_node_or_null(NodePath(String(HungryNetLink.NODE_NAME)))
	_check(link != null, "and its link is a child of the server node")
	_check(
		link is HungryNetLink,
		"named %s, which is what a client's link is named" % HungryNetLink.NODE_NAME
	)

	_check(
		module.net.interest is HungryInterest,
		"and this game's interest rule is in place"
	)
	_check(
		module.net.messages.count() >= 2,
		"and both message types are registered (%d)" % module.net.messages.count()
	)
	_done()
