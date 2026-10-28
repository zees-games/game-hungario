extends DotModule

const HungryAmbience := preload("hungry_ambience.gd")

const HungryMapConfig := preload("hungry_map_config.gd")

const HungryPaths := preload("hungry_paths.gd")

const HungryBot := preload("hungry_bot.gd")

const HungryCombat := preload("hungry_combat.gd")

const HungryContent := preload("hungry_content.gd")

const HungryHazards := preload("hungry_hazards.gd")

const HungryHunters := preload("hungry_hunters.gd")

const HungryMaps := preload("hungry_maps.gd")

const HungryModTools := preload("hungry_mod_tools.gd")

const HungryMonster := preload("hungry_monster.gd")

const HungryNetBridge := preload("net/hungry_net_bridge.gd")

const HungryProgress := preload("hungry_progress.gd")

const HungryServices := preload("hungry_services.gd")

const HungryTuning := preload("hungry_tuning.gd")

const HungryModes := preload("hungry_modes.gd")

const HungryWorld := preload("hungry_world.gd")

## The workbench kind of the ambience cvar set (saved to cfg/.../ambience/server.yml).
const AMBIENT_KIND := "ambience"

## Binds a [HungryWorld] and its netcode to a [DotServer].
##
## The only file in this project that names dot-server, and the whole of the dedicated
## server integration: the tick, the join, the console surface, the bots, and the two game
## descriptors that make `changegame` mean something.
##
## [codeblock]
## server.modules.load_module("res://game/hungry_module.gd")
## [/codeblock]
##
## [b]The manager outlives the world, and that is the point.[/b] A game change frees the
## scene the world lives in and instantiates the next one; rebuilding the
## [DotNetManager] with it would reset the message ids, the peer records and the clock,
## which is a disconnect for everybody — exactly what changing the map is supposed to
## avoid. So the manager and the bridge are the module's, and the bridge is rebound.

const CHANNEL := "hungry.module"

## The drawn mode ballot's notice topic. The client shell draws one menu per topic, and a
## server running several games sends its own `game_ballot` beside this one.
const MAP_BALLOT_TOPIC := &"map_ballot"

## Snapshots a second. Twenty is the number [Dot2DNetSync.estimated_bits] was sized
## against: a hundred visible pieces at 104 bits each is about 1.3 kB a snapshot, so 20 Hz
## is 26 kB/s to a player in a crowd and a great deal less to everybody else.
const SNAPSHOT_RATE := 20

## Ids at or above this belong to bots. Well clear of anything [DotServer] hands out,
## which counts up from 1.
const BOT_ID_BASE := 900001

## The modes this server can switch between.
const GAME_CLASSIC := "hungry_classic"

const GAME_FRENZY := "hungry_frenzy"

const GAME_GAUNTLET := "hungry_gauntlet"

const GAME_WARRENS := "hungry_warrens"

const GAME_REEF := "hungry_reef"

const GAME_SHALLOWS := "hungry_shallows"

var world: HungryWorld = null

var net: DotNetManager = null

var bridge: HungryNetBridge = null

## What players may bring in, and where their choices are kept.
##
## Backed by memory, which is the right default for a dedicated server: a loadout that
## outlives a session is a profile, and a profile is dot-user's. An operator who wants
## them to persist points the config at the local backend, or subclasses
## [DotLoadoutStore] and points it at their own service — that is the seam, and it is why
## this is a manager rather than a dictionary.
var loadouts: DotLoadoutManager = null

## Chat, moderation and voice. Built here rather than in the world, because they are about
## the people connected rather than about the arena — a game change frees the world and
## these have to survive it, exactly as the netcode manager does.
var services: HungryServices = null

## Where the services write punishments. [constant HungryServices.PUNISHMENTS_PATH] — the
## store a real server enforces — unless a host says otherwise before this loads.
##
## [b]Static, because nothing holds this module before it exists[/b]: dot-server constructs
## it from a path inside `load_module`, so there is no instance for a host to set a field on
## first. The suites point it at a directory of their own; before they could, every run of
## `dedicated` and `sandbox` wrote a test gag and the live tools' warnings to the real
## store, 417 records by the time anybody counted.
static var punishments_path: String = HungryServices.PUNISHMENTS_PATH

## dot-moderation's live tools with this game's verbs (`HungryModTools`), and their
## commands. Built here rather than in the services layer because the world they act on is
## replaced by a game change and this module is what knows the current one.
var mod_tools: DotModTools = null

var mod_commands: DotModToolCommands = null

## NPC monsters, and the director that decides when they arrive.
var hunters: HungryHunters = null

## How good the hunters are, server-wide: `npc_skill`, `npc_reaction_scale`,
## `npc_reaction_min`. Here rather than on [member hunters] because the console is
## registered before the hunters are built, and the value has to be there to hand them.
var npc_skill: DotNpcAiSkill = DotNpcAiSkill.new()

## Rocks, spikes and lures.
var hazards: HungryHazards = null

## What a throwable does to somebody, through dot-combat's rules.
var combat: HungryCombat = null

## Boards and achievements over the numbers this game already counts.
var progress: HungryProgress = null

## The modes as maps, the rotation, and the vote over them.
var maps: HungryMaps = null

## Reports this server to its site listing, when an operator has configured one.
##
## Null on a server with no integration token, which is every LAN game and every test.
var backbone: DotBackboneClient = null

## Counts what every monster did, and reports it through [member backbone].
##
## Always built, because the session figures are the game's own (a match summary
## reads them) and counting costs nothing; reporting happens only when there is a
## backbone to report through. Players are keyed by the scoped id dot-platform
## resolved, never the account id — a session with no scoped key, which is every
## guest on a LAN server, is counted under nothing and reported nowhere.
var stats: DotStatsTracker = null

## userid -> the scoped key the tracker knows them by.
var _stat_keys: Dictionary = {}

## userid -> true, for the humans this module put in the world.
var _joined: Dictionary = {}

## Who is still behind their loading cover, from dot-game's roster used for that alone: this
## module is not on DotGameModule, so it seats people itself and only borrows the bookkeeping
## (joined until the client says its cover lifted, again from a mode change). A player id is
## the userid, so [method HungryWorld.can_be_harmed] asks it by that.
var loading: DotGameRoster = null

var _handles_cover: bool = false

## player id -> display name, for the bots.
var _bots: Dictionary = {}

var _next_bot_id: int = BOT_ID_BASE

## Gets the bots from the number there are to the number [DotBotQuota] wants, named.
var _roster := DotBotRoster.new()

var _tick: int = 0

## `hungry_bots`, the old fixed count, kept only as an alias. See [method _register_console].
var _cv_bots: DotConVar = null

## How many bots, from how many people: dot-server's one rule for every game.
var _quota: DotBotQuota = null

var _cv_pack: DotConVar = null

var _cv_auth_config: DotConVar = null

var _cv_hunters: DotConVar = null

var _map_config: DotGameMapConfig = null

## dot-workbench over the config and the modes; null until the load finishes.
var workbench: DotGameWorkbench = null

## The admins' permission check the workbench runtime asks through [method _runtime_permit].
var _admin_permit := Callable()

## dot-player-char's `sv_ragdoll*` set: how an eaten monster goes down. The module's, because
## the cvars outlive a mode change and the world does not; each world is handed this one.
var ragdoll_rules: DotPlayerRagdollRules = DotPlayerRagdollRules.new()

## The ambience cvars (`hungry_ambient*`): REPLICATED, because each client plays its own ambience under the server's intent.
var ambient_rules: DotAmbienceRules = HungryAmbience.make_rules()

var _cv_hazards: DotConVar = null

## Who last said something. What `hungry_status` reports, off the accepted line.
var _last_spoke: String = ""

func _module_name() -> String:
	return "hungry"

func _module_version() -> String:
	return "0.1.0"

func _module_description() -> String:
	return "Monsters that eat: food, fruit, throwables, and each other."

func _module_author() -> String:
	return "dot"


## What a player owns.
##
## [b]Nothing, by default, and deliberately.[/b] A server that granted everything would
## work perfectly in every test, ship, and quietly be a game where every unlock is free —
## and nobody reports that as a bug. Only items marked free are permitted until something
## says otherwise, and the something is dot-platform: an entitlement source there is
## whatever a deployment's store or backbone says.
func _entitlements_for_key(user_key: String) -> DotLoadoutEntitlements:
	var granted := DotLoadoutEntitlements.none()
	var platform: Object = server.modules.get_module("platform")

	if platform == null or not platform.has_method("entitlements_for"):
		return granted

	var owned: Variant = platform.call("entitlements_for", user_key)

	if owned is PackedStringArray or owned is Array:
		for id in (owned as Array if owned is Array else Array(owned)):
			granted.grant(StringName(str(id)))

	return granted

func _entitlements_for_player(player_id: int) -> DotLoadoutEntitlements:
	return _entitlements_for_key(HungryContent.loadout_key(player_id))

## Saves a published loadout, so it survives a respawn and a mode change.
##
## Through the manager rather than straight to the store, because the manager is the trust
## boundary: rate limit, per-player cap, schema membership, entitlements and key
## usability, in that order. The bridge has already validated the document against the
## schema; doing it twice costs nothing and means neither half can be the only check.
func _store_loadout(player_id: int, loadout: DotLoadout) -> DotResult:
	# Awaited: a store write may be slow — the whole reason DotLoadoutStore is pluggable
	# is that somebody will point it at a database — and the cache must not be updated
	# before the write succeeds. A player who sees their change, plays with it and loses
	# it at the next load with no explanation is worse than a refusal.
	return await loadouts.publish(HungryContent.loadout_key(player_id), loadout, 0)

## The loadout a player spawns with, loaded from the store.
##
## Awaited, and therefore not on the join path: a store may be slow and a join may not be.
## The player is in the world with the schema's default and their own arrives a moment
## later, which is the same trade game-arena makes for the same reason.
func _apply_stored_loadout(player_id: int) -> void:
	var active: DotResult = await loadouts.active_for(
		HungryContent.loadout_key(player_id)
	)

	if not active.ok or world == null:
		return

	var monster := world.monster_for(player_id)

	if monster == null:
		return

	monster.wear_loadout(active.value)
	bridge._announce(monster)


## Starts reporting this server to its listing, if an operator has configured one.
##
## [b]The token comes from a config file and from nowhere else.[/b] `DotAuthConfig` lists
## `integration_token` in its sensitive keys, so the layered loader refuses it from the
## environment and from argv — both are readable by other processes on the box and both
## end up in `ps` output and in pasted bug reports. A cvar would be worse still: it is
## settable over RCON and printable by anybody with the `cvar` flag.
##
## Absent one, nothing here runs and the server is simply not listed, which is the correct
## behaviour for a LAN game and for every test.
func _build_reporting() -> void:
	var config := DotAuthConfig.new()
	var path := _cv_auth_config.get_string() if _cv_auth_config != null else ""

	if path != "" and FileAccess.file_exists(path):
		var loaded := config.load_layered(path)

		if not loaded.ok:
			log_warn("could not read the backbone configuration", {
				"path": path, "error": str(loaded.error)
			})
			return

	if config.integration_token.strip_edges() == "":
		log_info("no integration token; this server will not appear in a listing", {
			"config": path
		})
		return

	backbone = DotBackboneClient.new()
	backbone.name = "Backbone"
	backbone.config = config
	# Sampled when they are sent rather than pushed when they change, which is the whole
	# reason these are callables: a report is a snapshot of now, not of the last time
	# somebody joined.
	backbone.stats_provider = stats_report
	backbone.roster_provider = roster_report
	add_child(backbone)

	var started := backbone.start()

	if not started.ok:
		log_warn("backbone reporting did not start", {"error": str(started.error)})
		remove_child(backbone)
		backbone.queue_free()
		backbone = null
		return

	log_info("reporting to the site listing", {"url": config.backbone_url})

## What this server looks like from outside.
##
## [b]dot-server's own report says `bots: 0` unconditionally[/b], because dot-server has no
## bots and no way to know a game has any. This one does, and a listing that shows eight
## players on a server holding one human is a listing that stops being trusted. The map is
## the mode rather than the content id for the same reason: `hungry_frenzy` means something
## to somebody reading a server browser.
##
## Public so it can be checked without a token, which is the only way it is ever checked
## here — nothing in this repository has a backbone to send it to.
func stats_report() -> Dictionary:
	var report := server.to_stats_report()

	report["bots"] = bot_count()
	report["curUsers"] = _joined.size()
	report["gameMode"] = "ffa"

	if world != null and world.preset != null:
		report["map"] = String(world.preset.id)

	return report

func roster_report() -> Array:
	return server.to_roster_report()


## What this game counts per player. Declared once; the site learns it at boot.
##
## Every stat is published: a grow-by-eating game has nothing to count privately.
## The kinds are the contract — `top_mass` is a BEST, so a monster that shrank
## keeps its record, and everything else adds.
static func stats_schema() -> DotStatsSchema:
	var schema := DotStatsSchema.new()
	for id in [&"food", &"fruit", &"pieces_eaten", &"kills", &"deaths", &"bursts", &"items"]:
		schema.define(id).publish = true
	var mass := schema.define(&"mass_eaten", DotStatsDef.Kind.COUNTER, "Mass eaten")
	mass.publish = true
	mass.decimals = 1
	var top := schema.define(&"top_mass", DotStatsDef.Kind.BEST, "Biggest")
	top.publish = true
	top.decimals = 1
	return schema

func _build_stats() -> void:
	stats = DotStatsTracker.new()
	stats.name = "Stats"
	stats.schema = stats_schema()
	stats.report_to_backbone = backbone != null
	stats.reporter.client = backbone
	add_child(stats)

	world.food_eaten.connect(_on_stat_food)
	world.fruit_eaten.connect(_on_stat_fruit)
	world.item_taken.connect(_on_stat_item)
	world.piece_eaten.connect(_on_stat_piece)
	world.player_died.connect(_on_stat_death)
	world.monster_burst.connect(_on_stat_burst)

## The tracker's key for a world player id, or empty for a bot or a keyless guest.
func _stat_key(player_id: int) -> StringName:
	return StringName(str(_stat_keys.get(player_id, "")))

func _note_mass(player_id: int) -> void:
	var key := _stat_key(player_id)
	if key == &"":
		return
	var monster := world.monster_for(player_id)
	if monster != null:
		stats.record(key, &"top_mass", monster.mass())

func _on_stat_food(player_id: int, _grid_id: int, mass: float) -> void:
	var key := _stat_key(player_id)
	if key == &"":
		return
	stats.record(key, &"food")
	stats.record(key, &"mass_eaten", mass)
	_note_mass(player_id)

func _on_stat_fruit(player_id: int, _grid_id: int, _kind: HungryContent.Fruit) -> void:
	var key := _stat_key(player_id)
	if key != &"":
		stats.record(key, &"fruit")

func _on_stat_item(player_id: int, _grid_id: int, _item: StringName) -> void:
	var key := _stat_key(player_id)
	if key != &"":
		stats.record(key, &"items")

func _on_stat_piece(eater_id: int, _victim: int, mass: float) -> void:
	var key := _stat_key(eater_id)
	if key == &"":
		return
	stats.record(key, &"pieces_eaten")
	stats.record(key, &"mass_eaten", mass)
	_note_mass(eater_id)

func _on_stat_death(player_id: int, killer_id: int) -> void:
	var victim := _stat_key(player_id)
	if victim != &"":
		stats.record(victim, &"deaths")
	var killer := _stat_key(killer_id)
	if killer != &"" and killer_id != player_id:
		stats.record(killer, &"kills")

func _on_stat_burst(_player_id: int, by_player: int, _pieces: int) -> void:
	var key := _stat_key(by_player)
	if key != &"":
		stats.record(key, &"bursts")

## Starts counting for a session, under the scoped key dot-platform resolved.
##
## Duck-typed like [method _avatar_for]: a LAN server has no platform module,
## and a session without a key is counted under nothing rather than under the
## account id the identity carries — which is the one thing that must never be
## filed. The tracker's reporter would refuse it anyway; not offering it is the
## first line.
func _begin_stats(session: DotClientSession) -> void:
	if stats == null:
		return
	var platform: Object = server.modules.get_module("platform")
	if platform == null or not platform.has_method("player_for"):
		return
	var player: Object = platform.call("player_for", session)
	if player == null or not player.has_method("key"):
		return
	var key := str(player.call("key"))
	if key == "":
		return
	_stat_keys[session.userid] = StringName(key)
	stats.begin(StringName(key), session.display_name)

func _end_stats(session: DotClientSession) -> void:
	if stats == null or not _stat_keys.has(session.userid):
		return
	stats.end(_stat_keys[session.userid])
	_stat_keys.erase(session.userid)


## The avatar dot-platform resolved for this session, if there is a dot-platform.
##
## [b]Duck-typed on purpose.[/b] This game needs dot-user-avatar — the schema is what a
## rider is — but it does not need the whole identity stack, and naming
## [code]DotPlatformModule[/code] here would make a LAN server impossible without
## dot-auth, dot-user and a profile store. A module that answers to `player_for` is
## enough, which is the same contract dot-server uses for its admin sources.
func _avatar_for(session: DotClientSession) -> DotAvatar:
	var platform: Object = server.modules.get_module("platform")

	if platform == null or not platform.has_method("player_for"):
		return null

	var player: Variant = platform.call("player_for", session)

	if player == null or not (player is Object):
		return null

	var avatar: Variant = (player as Object).get("avatar")
	return avatar as DotAvatar if avatar is DotAvatar else null


## Keeps the bot population where [DotBotQuota] says and hands each one its command.
##
## Every tick rather than on an interval, as the population always was here: it is two
## counts and a comparison, and it means a person who joins takes a bot's place on the tick
## they arrive. People are everybody in the world who is not one of this module's bots; a
## leaver is out of the world before the next tick, so nobody half-disconnected counts.
func _drive_bots() -> void:
	var wanted := 0

	if _quota != null:
		var humans := maxi(world.player_ids().size() - _bots.size(), 0)
		var slots: int = server.config.max_players if server != null and server.config != null else -1
		wanted = _quota.wanted(humans, slots)

	# dot-bot's roster: named from its pool, never a person's name, newest out first.
	var taken: Array = []
	for id in world.player_ids():
		var someone := world.monster_for(id)
		if someone != null:
			taken.append(someone.display_name)
	var _kept := _roster.keep(wanted, _bots.keys(), _add_bot, _remove_bot, taken)

	for bot_id in _bots.keys():
		var monster := world.monster_for(int(bot_id))

		if monster == null:
			continue

		bridge.note_command(
			int(bot_id), HungryBot.command_for(world, monster, _tick)
		)

func _remove_bot(doomed: Variant) -> void:
	world.remove_player(int(doomed))
	var _gone := _bots.erase(doomed)

## Adds one bot called [param display_name]; its id, or 0 when the bridge refused.
func _add_bot(display_name: String) -> int:
	var bot_id := _next_bot_id
	_next_bot_id += 1

	var index := bot_id - BOT_ID_BASE
	var added := bridge.add_player(0, bot_id, display_name)

	if not added.ok:
		log_warn("could not add a bot", {"error": str(added.error)})
		return 0

	# Bots take turns through the traits and the throwables. Not for their sake — they
	# play the same either way — but so that an operator watching a server full of them
	# sees the loadout doing something, and so that the paths a human's choice takes are
	# exercised on a server nobody has joined yet.
	var monster: HungryMonster = added.value
	var loadout := DotLoadout.empty(bridge.loadout_schema.id)
	loadout.set_item(
		HungryContent.SLOT_STARTER,
		HungryContent.ITEM_IDS[index % HungryContent.ITEM_IDS.size()]
	)
	# Only the free ones: a bot is not entitled to anything either, and handing it an
	# unlock nobody has would be a server quietly deciding entitlements do not apply.
	loadout.set_item(
		HungryContent.SLOT_TRAIT,
		HungryContent.TRAIT_IDS[index % 2]
	)

	var legal := DotLoadoutValidator.validate(
		loadout, bridge.loadout_schema, DotLoadoutEntitlements.none()
	)

	if legal.ok:
		monster.wear_loadout(loadout)
	else:
		log_warn("a bot loadout was not legal", {"error": str(legal.error)})

	_bots[bot_id] = display_name
	return bot_id

func bot_count() -> int:
	return _bots.size()

## Pushes the cosmetics manifest URL onto the bridge, so joining clients are told it.
##
## Clients already connected are not re-told: the hello is sent once, on admission, and a
## cosmetic that arrives mid-session is a nicety rather than a requirement. An operator
## setting this on a running server means it from the next join.
func _sync_pack() -> void:
	if bridge != null and _cv_pack != null:
		bridge.avatar_pack_url = _cv_pack.get_string()


## What a server browser is told about this game.
##
## [b]This game shipped a full server browser and answered no query at all.[/b]
## `HungryBrowser` is a real dot-browser list — DQP, DQP over a WebSocket, A2S,
## favourites, history and a mode filter — and a hungario server it was handed the address
## of could not answer it. The tracker in the middle is still missing and is written down
## as such; this is the half that was missing at *this* end, which nothing had noticed
## because the browser's own suite queries a server built by dot-browser.
##
## What goes in is what a person filtering a list filters on. The mode is the map here, so
## `map` is the preset rather than a file: a browser showing "hungry_classic" under Map is
## showing what a player would call the map, and showing the content id would be showing
## them dot-server's bookkeeping.
func _build_query_provider() -> void:
	var provider := HungryQueryProvider.new()
	provider.module = self

	# Logged rather than checked: a server with neither query protocol enabled is a
	# legitimate deployment — a peer-to-peer session has no listener to answer on — and
	# refusing to load the game over it would take the game down for a listing.
	DotLog.result(CHANNEL, "the query provider", add_query_provider(provider), DotLog.Level.DEBUG)

## A [DotQueryProvider] over this module. An inner class for game-arena's reason: it is
## one method and a reference, and a file for it would be a file about nothing else.
class HungryQueryProvider extends DotQueryProvider:
	## The module, held as an [Object] because this script has no [code]class_name[/code]
	## and an inner class cannot name the outer script it lives in. Every read off it is
	## typed on arrival instead.
	var module: Object = null

	func _provider_name() -> String:
		return "hungry"

	func _contribute(snapshot: DotQuerySnapshot) -> void:
		if module == null or module.world == null:
			return

		# Typed explicitly rather than inferred: this is an inner class of the script it
		# is reading, so the outer type is not yet resolved while this one is compiled and
		# `:=` cannot infer anything off it.
		var world: HungryWorld = module.world
		var preset: Object = world.preset
		var match_node: DotMatch = world.match_node

		var values := {
			"mode": String(preset.id) if preset != null else "",
			"mode_name": preset.display_name if preset != null else "",
			# The preset IS the map in this game. See above.
			"map": String(preset.id) if preset != null else "",
			"players": module._joined.size(),
			"bots": module._bots.size(),
			"world_size": "%dx%d" % [
				int(preset.world_size.x), int(preset.world_size.y)
			] if preset != null else "",
			"win_mass": preset.win_mass if preset != null else 0.0,
			"food": world.field.food_count() if world.field != null else 0,
			# The two cvars that make this a different game, which is exactly what a
			# person reading a server list wants to know before they join.
			"hunters": module.hunters != null and module.hunters.is_enabled(),
			"hazards": module.hazards != null,
		}

		if match_node != null:
			values["state"] = DotMatch.State.keys()[match_node.state]
			values["round"] = match_node.round_number

		var top: Array[HungryMonster] = world.leaderboard(1)

		if not top.is_empty():
			# The leader's mass rather than a name: a list filters on how far through a
			# round is, and a name in a query row is a name in somebody's scraper.
			values["top_mass"] = int(top[0].mass())

		for key: String in values:
			snapshot.game[key] = values[key]

func describe() -> Dictionary:
	var out := super.describe()
	out["players"] = _joined.size()
	out["bots"] = _bots.size()
	out["tick"] = _tick
	out["world"] = String(world.preset.id) if world != null else "<none>"
	out["loadouts"] = loadouts.describe() if loadouts != null else {}
	return out

## Disconnects a peer whose message schema this server cannot play with, with dot-net's
## sentence as the reason. See `peer_schema_refused` above.
func _refuse_peer(peer_id: int, error: DotError) -> void:
	var session: DotClientSession = server.session_of(peer_id) if server != null else null
	if session != null:
		server.kick(session, error.message, error)

## Binds the server config's cvars and commands, and keeps the live round in step with an edit.
func _bind_tuning() -> void:
	var binder := HungryTuning.binder
	var _made := binder.bind_cvars(add_cvar, DotConVar.FLAG_ARCHIVE | DotConVar.FLAG_NOTIFY)
	binder.bind_commands(add_command)
	binder.field_changed.connect(_on_tuning_changed)

## The rules object was built from the config at load; the fields that feed it follow an edit.
func _on_tuning_changed(key: String, _value: Variant, _source: String) -> void:
	if world == null or world.match_node == null or world.match_node.rules == null:
		return
	var rules: DotMatchRules = world.match_node.rules
	var tuning := HungryTuning.settings()
	match key:
		"respawn_delay_sec":
			rules.respawn_delay_sec = tuning.respawn_delay_sec
		"spawn_protection_sec":
			rules.spawn_protection_sec = tuning.spawn_protection_sec
		"intermission_sec":
			rules.intermission_sec = tuning.intermission_sec
		"match_end_sec":
			rules.match_end_sec = tuning.match_end_sec
		"friendly_fire", "pepper_damage":
			if combat != null and combat.rules != null:
				var fresh := HungryCombat.damage_rules()
				combat.rules.friendly_fire = fresh.friendly_fire
				combat.rules.minimum = fresh.minimum
				combat.rules.maximum = fresh.maximum

## dot-workbench over the server config and the six modes: the HTTP page only with `workbench.enabled` in cfg/server.yml, the F9 panel never on a dedicated server.
func _start_workbench() -> void:
	var rt: DotProfileRuntime = bridge.ensure_runtime() if bridge != null else DotProfileRuntime.new()
	var admin_permit := Callable()
	if server != null and server.admins != null:
		admin_permit = server.admins.uid_has_permission
	# Methods, not lambdas: the static HungryTuning.binder keeps rt past the tree, and a lambda
	# there holds this base script until the engine's exit walk frees it mid-walk (exit 134).
	_admin_permit = admin_permit
	rt.permit = _runtime_permit
	rt.actor_name = _runtime_actor_name
	workbench = DotGameWorkbench.new()
	workbench.name = "Workbench"
	workbench.dedicated = DisplayServer.get_name() == "headless"
	workbench.listen_host_fn = func() -> bool: return DisplayServer.get_name() != "headless"
	workbench.permit_fn = func(actor: Variant, flag: String) -> bool:
		return admin_permit.is_valid() and actor is String and bool(admin_permit.call(actor, flag))
	for set: DotProfileSet in HungryTuning.binder.profile_sets():
		workbench.add_set(set, "Server settings: %s" % set.rel_path.trim_prefix("config_"))
	var ambient_set: DotProfileSet = null
	if server != null and server.console != null:
		ambient_set = DotGameWorkbench.cvar_set(server.console, HungryAmbience.cvar_types(), AMBIENT_KIND)
	if ambient_set != null:
		workbench.add_set(ambient_set, "Ambience (hungry_ambient*)")
	for id in HungryModes.IDS:
		workbench.add_set(HungryModes.binders[id].profile_set(), "Mode: %s" % id)
	add_child(workbench)
	var started := workbench.start(rt)
	if not started.ok:
		DotLog.result(CHANNEL, "the workbench", started)
		return
	# Off until the owner sets sv_workbench_remote 1; then flagged admins edit from a client.
	if net != null:
		var _served := workbench.serve_remote(net)
	HungryTuning.binder.attach(rt)
	if ambient_set != null:
		var _applied := DotGameWorkbench.bind_cvar_set(ambient_set, rt, server.console)
	for id in HungryModes.IDS:
		HungryModes.binders[id].attach(rt)
	add_command("workbench", func(ctx: DotCmdContext) -> void: ctx.reply_lines(_workbench_lines()),
		"Show the admin workbench's state", DotAdminFlags.CVAR)

## [member DotProfileRuntime.permit]: the server's admin flags, by user id.
func _runtime_permit(actor: Variant, flag: String) -> bool:
	return _admin_permit.is_valid() and actor is String and bool(_admin_permit.call(actor, flag))

## [member DotProfileRuntime.actor_name].
func _runtime_actor_name(actor: Variant) -> String:
	return str(actor)

func _workbench_lines() -> PackedStringArray:
	if workbench == null:
		return PackedStringArray(["workbench    off"])
	if workbench.running_http:
		return PackedStringArray(["workbench    http " + JSON.stringify(workbench.http.call("describe"))])
	return PackedStringArray(["workbench    off (workbench.enabled in cfg/server.yml)"])
