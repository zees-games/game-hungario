extends "res://game/client/hungry_client_state.gd"

## The playable client: a world, a camera, a renderer, a HUD and a socket.
##
## [b]This is the scene a [DotClientLink] loads.[/b] dot-server's signon gets a player
## from "typed an address" to "in the world" and then hands over by instantiating the
## descriptor's client scene under the client's game root; everything from that point is
## this file's.
##
## [codeblock]
## HungryClient
##   World      HungryWorld, not authoritative
##   Net        DotNetManager, a client
##   Bridge     HungryNetBridge — creates the link under the DotClientLink
##   Renderer   HungryRenderer
##   Camera     HungryCamera
##   Input      HungryInput
##   UI         CanvasLayer
##     Screens  DotScreenStack — the held Tab scoreboard
##     Hud      HungryHud
## [/codeblock]
##
## [b]It also runs standalone.[/b] With no [DotClientLink] to be found it builds an
## authoritative world with bots in it and plays that, which is what
## [code]--offline[/code] is for and what makes the controls testable without a server.

const CHANNEL := "hungry.client"

## Solo, the map menu changed the mode: [param fresh] is the client now playing it, in this
## one's place. Whatever held this client holds that one instead.
signal replaced(fresh: Node)


func _ready() -> void:
	DotLog.info(CHANNEL, "client starting")

	# First, so the cover is up before anything below draws. A 2D game: no camera node to
	# wait for, and the player is a monster in the world, not a node, so nothing is frozen;
	# the sampler is held and the offline tick waits instead. The cursor is the control, so
	# the platform never captures it.
	platform = DotGameClient.new()
	platform.name = "Platform"
	platform.map_config_keys = HungryMapConfig.KEYS
	platform.map_config_game = HungryMapConfig.GAME_ID
	platform.map_config_get_fn = _map_cvar_get
	platform.map_config_set_fn = _map_cvar_set
	platform.force_offline = force_offline
	platform.require_camera = false
	platform.capture_pointer = false
	platform.scoreboard_action = HungryBindings.SCOREBOARD
	platform.spawned_text = "Joining"
	platform.spawned_fn = _local_monster_exists
	platform.cover = HungryCover.new()
	add_child(platform)
	link = platform.link
	_offline = platform.offline

	# A client that outlives a server-side mode change (the standalone play scene) covers
	# again, as the offline change does by building a fresh client. The shell frees the whole
	# client on a change, whose new gate is closed from the start, so this only ever acts on
	# a client that stays. The server's world is rebuilt and its hello sent again; that and
	# the link's `spawned` lift the hold. Nothing is frozen: a monster is not a node and the sampler already
	# waits on the platform.
	if not _offline and link != null and link.has_signal("game_changed"):
		link.connect("game_changed", _on_game_changed_online)
		if link.has_signal("spawned"):
			link.connect("spawned", _release_map_hold)

	var built := _build()

	if not built.ok:
		DotLog.result(CHANNEL, "the client could not start", built)
		return

	if _offline:
		_start_offline()
	elif link.has_method("is_playing") and bool(link.call("is_playing")):
		_ask_world()
	elif link.has_signal("spawned"):
		# The scene can legitimately exist before the signon finishes — a host that
		# instantiates it up front, an editor run — and asking a server that has not
		# admitted this peer yet is a request it will drop. Waiting for `spawned` is the
		# same wait [DotClientLink] already does.
		link.connect("spawned", _ask_world, CONNECT_ONE_SHOT)
	else:
		_ask_world()


## Asks for the world and, online, whether this player may edit the server (sv_workbench_remote).
func _ask_world() -> void:
	if workbench_remote != null:
		workbench_remote.ask()
	bridge.ask_for_world()


## The subscribed maps this solo client lists and plays; null online.
var workshop: HungryWorkshop = null


func _local_monster_exists() -> bool:
	return world != null and world.monster_for(_local_player()) != null


## The map-config cvars a client has are whatever its local console carries; the rest are the server's.
func _map_cvar_get(key: String) -> Variant:
	var console: Object = presentation.local_console if presentation != null else null
	var cv: Object = console.call("find_cvar", key) if console != null else null
	return cv.call("get_string") if cv != null else null


func _map_cvar_set(key: String, value: Variant) -> bool:
	var console: Object = presentation.local_console if presentation != null else null
	if console == null:
		return false
	var res: Variant = console.call("set_cvar", key, str(value))
	return res != null and bool(res.get("ok"))


func _build() -> DotResult:
	world = HungryWorld.new()
	world.name = "World"
	world.preset = HungryPreset.classic()
	if _offline:
		# A subscribed pack map (solo only) is a layout of rocks over one of the game's presets.
		workshop = HungryWorkshop.new()
		workshop.follow()
		world.preset = workshop.preset_for(offline_preset)
		if world.preset == null:
			world.preset = HungryModes.preset_for(offline_preset)
	world.tick_rate = HungryContent.TICK_RATE
	# Authoritative only when there is nobody else to be. A client that resolved its own
	# eating would be a client that decides what it weighs.
	world.is_authority = _offline
	world.register_service = true
	world.service_scope = &"client"
	add_child(world)

	var ready_result := world.setup()

	if not ready_result.ok:
		return ready_result

	if _offline:
		world.start(0)
	else:
		var netted := _build_netcode()

		if not netted.ok:
			return netted
		_start_remote_workbench()

	_build_client_services()
	_build_view()
	_build_ui()
	return DotResult.success(self)


func _build_netcode() -> DotResult:
	net = DotNetManager.new()
	net.name = "Net"
	net.is_server = false
	net.local_peer_id = multiplayer.get_unique_id() if multiplayer != null else 2
	net.service_scope = &"client"
	# The tick is driven here, because the input has to be recorded before the prediction
	# that replays it. See [method _physics_process].
	net.auto_tick = false
	net.config_file = ""

	var config := DotNetConfig.new()
	config.tick_rate = world.tick_rate
	config.snapshot_rate = 20
	config.enable_prediction = true
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 120
	config.world_extent = Dot2DNetSync.WORLD_EXTENT
	config.reconcile_position_epsilon = HungryNetBridge.RECONCILE_EPSILON
	net.config = config
	add_child(net)

	var ready_result := net.setup()

	if not ready_result.ok:
		return ready_result

	bridge = HungryNetBridge.new()
	bridge.name = "Bridge"
	add_child(bridge)

	# Parented to the link, which is named to match the server's node, because Godot
	# routes an RPC by the receiver's path relative to its MultiplayerAPI root. See
	# [HungryNetLink].
	var attached := bridge.attach(world, net, link)

	if not attached.ok:
		return attached

	# The server's order again (after the bridge): the remote workbench's frame.
	workbench_remote = DotGameWorkbenchRemoteClient.attach(net)
	net.messages.seal()

	bridge.hello_received.connect(_on_hello)
	bridge.cue.connect(_on_cue)
	bridge.roster_changed.connect(_on_roster_changed)

	# [b]dot-server's own `chat_received` is deliberately NOT connected.[/b] The server
	# cancels that path — see [method HungryModule._on_player_chat] — and routes every
	# line through [DotChatRouter] onto this game's own wire instead. Connecting both
	# would draw a line twice on a server running the old path and once on one running the
	# new, which is the sort of difference that survives every test.
	bridge.chat_received.connect(_on_chat_wire)
	bridge.hunter_received.connect(_on_hunter)
	bridge.hazard_received.connect(_on_hazard)
	bridge.progress_received.connect(_on_progress)
	bridge.vote_cue_received.connect(_on_vote_cue)

	if link.has_method("ping_ms"):
		bridge.rtt_source = func() -> float:
			return float(maxi(0, int(link.call("ping_ms"))))

	return net.start()


## Chat, voice, and the two things the arena has in it that nobody steers.
##
## Built after the bridge, because both halves need somewhere to send.
func _build_client_services() -> void:
	chat = DotChatClient.new()
	chat.name = "Chat"
	# The same channel definitions the server routes with — shared rather than sent, for
	# the arena-size reason: a client holding a different set would show a line on a
	# channel it has no colour or prefix for.
	chat.channels = HungryServices.chat_channels()
	chat.rules = HungryServices.chat_rules()
	chat.history_limit = 300
	# Two clients in one process — `examples/sandbox.tscn` — would otherwise collide on
	# the registry name and one of them would be invisible to whatever asked.
	chat.register_as = &""
	add_child(chat)
	chat.start()
	chat.message_received.connect(_on_chat_message)

	hunters = HungryHunters.new()
	hunters.name = "Hunters"
	add_child(hunters)
	hunters.setup(false, world)

	hazards = HungryHazards.new()
	hazards.name = "Hazards"
	add_child(hazards)
	hazards.setup(false, world)



	if bridge == null:
		return

	voice = HungryVoice.new()
	voice.name = "Voice"
	voice.send_fn = func(bytes: PackedByteArray) -> void:
		if bridge != null and bridge.link != null:
			# Passed as 1 rather than 0: the peer is ignored on a client, and in this
			# family zero has meant "everybody" often enough to be worth never writing by
			# accident.
			bridge.link.send_voice(1, bytes)
	add_child(voice)

	voice.setup(not DotPlatform.is_headless())
	bridge.voice_arrived.connect(voice.receive)


func _build_view() -> void:
	camera = HungryCamera.framing(_me_source(), world.arena)

	# Where a dead player looks. Without it the camera stays exactly where the monster
	# died — parked on the patch of arena that ate you while the game happens somewhere
	# else — which is what this game did from the day it was written.
	camera.position_source = func() -> Variant:
		if world.spectate == null:
			return null
		return world.spectate.camera_position(_local_player())

	add_child(camera)
	camera.make_current()

	renderer = HungryRenderer.new()
	renderer.name = "Renderer"
	add_child(renderer)
	renderer.bind(world, camera, _local_player())
	# The renderer reads the same objects the simulation resolves against, once, rather
	# than being handed a copy on every change. There is nothing to keep in step because
	# there is only one list — which is the whole argument this game's arena size makes.
	renderer.hunters = hunters
	renderer.hazards = hazards
	# The ping an administrator's beacon makes, wherever its ripple goes out. The renderer
	# decides WHEN, because it is what advances the ripple; the presentation layer decides
	# whether it is heard.
	renderer.beacon_pulsed.connect(_on_beacon_pulsed)

	sampler = HungryInput.measuring(_me_source(), camera)
	add_child(sampler)

	sound = HungrySound.make()
	add_child(sound)

	# The presentation layer, after the bank exists so the sink has something behind it.
	# `HungrySound` is still what makes the noise; dot-audio is what decides whether it
	# should, how many at once, how far away it stops mattering and how loud -- none of
	# which this game had, and all of which a bank called directly has no way to acquire.
	_build_presentation()

	# The world's own signals fire only where this process is the authority, which for a
	# netted client is nowhere. Eating is therefore *watched* rather than listened for —
	# see [method _watch_mass] — and these three are the ones an offline game needs and a
	# netted one gets as cues instead.
	world.projectile_thrown.connect(_on_projectile_thrown)
	world.player_died.connect(_on_player_died)
	world.monster_burst.connect(_on_monster_burst)

	_wire_falls()


## How an eaten monster goes down here: the renderer's [HungryFalls] under the server's
## `sv_ragdoll*` rules (followed through the link; offline the world's own), its sounds through
## the presentation layer. The deaths come from [method _on_player_died] offline and from the
## DIED cue connected; either way the reaction is the authority's pick.
func _wire_falls() -> void:
	if renderer == null or renderer.falls == null:
		return
	if bridge == null:
		renderer.falls.rules = world.ragdoll_rules
	else:
		renderer.falls.rules = ragdoll_rules
		if link != null:
			var _following := ragdoll_rules.follow_cvars(link)
	renderer.falls.sound.connect(func(id: StringName, at: Vector2, volume: float) -> void:
		if presentation != null:
			var _played := presentation.on_body(id, at, volume)
	)


## The server's `sv_ragdoll*` set on a connected client: this end draws the falls.
var ragdoll_rules: DotPlayerRagdollRules = DotPlayerRagdollRules.new()

## The server's `hungry_ambient*` set on a connected client; offline the defaults.
var ambient_rules: DotAmbienceRules = HungryAmbience.make_rules()


## Settings, audio, effects and the console, over the config and the bank this game has.
func _build_presentation() -> void:
	# The platform's settings and console first: the presentation binds audio and effects to
	# the document it builds and adds this game's commands to the console it builds.
	platform.settings = HungrySettings.new()
	platform.busy_fn = func() -> bool: return presentation != null and presentation.swallows_input()
	platform.board_snapshot_fn = HungryMenus.solo_snapshot
	# M: the six modes. Solo a choice starts that mode now; connected the server decides, by
	# the owner's `sv_map_menu_flag`, and anybody without it gets a vote instead.
	platform.maps_rows_fn = mode_rows
	platform.maps_change_fn = change_mode_offline
	platform.maps_title = "Change mode"
	platform.maps_noun = "modes"
	# Look-to-gag: the cursor, not a view axis, says who is looked at.
	if voice != null:
		platform.look_voice = voice.manager
		platform.look_chat = chat
		platform.look_target_fn = _look_target
	DotLog.result(CHANNEL, "the platform", platform.setup())
	if _offline:
		_add_workbench()
	if world != null and world.preset != null:
		platform.map_changed(String(world.preset.id))
	platform.input_blocked_changed.connect(_suspend_input)
	_suspend_input(platform.is_input_blocked())

	presentation = HungryPresentation.new()
	presentation.name = "Presentation"
	presentation.client = self
	presentation.platform = platform
	presentation.sound = sound
	# The SAME config object the rest of the client reads, not a copy. dot-settings owns
	# the persistence and the scopes; `HungryConfig` stays the declaration, so there is
	# one list rather than two that drift.
	presentation.config = settings if settings != null else HungryConfig.new()
	add_child(presentation)
	DotLog.result(CHANNEL, "the presentation layer", presentation.setup())
	if link != null and not _offline:
		var _ambient := ambient_rules.follow_cvars(link)
	if presentation.ambient != null:
		presentation.ambient.follow_settings(presentation.settings, ambient_rules)
		if world != null and world.preset != null:
			presentation.on_map(world.preset.id)

	if settings == null:
		settings = presentation.config


## The F9 tuning panel over the server settings and the modes, where this process hosts the game (solo). A mode's edit applies from the next mode change.
func _add_workbench() -> void:
	HungryTuning.load_all()
	HungryModes.load_all()
	var wb := DotGameWorkbench.new()
	wb.name = "Workbench"
	wb.listen_host_fn = func() -> bool: return true
	for set: DotProfileSet in HungryTuning.binder.profile_sets():
		wb.add_set(set, "Server settings: %s" % set.rel_path.trim_prefix("config_"))
	for id in HungryModes.IDS:
		wb.add_set(HungryModes.binders[id].profile_set(), "Mode: %s" % id)
	add_child(wb)
	var rt := DotProfileRuntime.new()
	var started := wb.start(rt)
	DotLog.result(CHANNEL, "the workbench", started)
	if started.ok:
		HungryTuning.binder.attach(rt)
		for id in HungryModes.IDS:
			HungryModes.binders[id].attach(rt)
	workbench = wb
	platform.add_workbench(wb)


## Online: no local trust and no panel until the server names this player an admin. The rows are the server's, through the bridge's profile link.
func _start_remote_workbench() -> void:
	if workbench_remote == null:
		return
	HungryTuning.load_all()
	HungryModes.load_all()
	var wb := DotGameWorkbench.new()
	wb.name = "Workbench"
	wb.remote_client = workbench_remote
	wb.remote_fn = func() -> bool: return true
	wb.config = {"enabled": false}
	for set: DotProfileSet in HungryTuning.binder.profile_sets():
		wb.add_set(set, "Server settings: %s" % set.rel_path.trim_prefix("config_"))
	for id in HungryModes.IDS:
		wb.add_set(HungryModes.binders[id].profile_set(), "Mode: %s" % id)
	add_child(wb)
	var started := wb.start(bridge.ensure_runtime())
	DotLog.result(CHANNEL, "the remote workbench", started)
	if not started.ok:
		wb.queue_free()
		return
	workbench = wb
	platform.add_workbench(wb)


## The six modes, as the map menu (M) lists them solo: `{id, name, detail, current}`.
func mode_rows() -> Array:
	var out: Array = []
	for id in MODE_IDS:
		var preset := HungryPreset.for_id(id)
		out.append({"id": String(id), "name": preset.display_name, "detail": MODE_BLURBS.get(id, ""),
			"current": world != null and world.preset != null and world.preset.id == id \
			and world.preset.layout != HungryLayout.WORKSHOP})
	if workshop != null:
		var playing: String = world.preset.layout_variant if world != null and world.preset != null \
			and world.preset.layout == HungryLayout.WORKSHOP else ""
		out.append_array(workshop.rows(playing))
	return out


## The preset ids, in the order the help screen describes them.
const MODE_IDS: Array[StringName] = [&"classic", &"frenzy", &"gauntlet", &"warrens", &"reef", &"shallows"]
const MODE_BLURBS := {
	&"classic": "The square arena.", &"frenzy": "Small and fast.", &"gauntlet": "A long narrow corridor.",
	&"warrens": "Rocks and refuges.", &"reef": "A wall with four channels.",
	&"shallows": "Posts whose gaps narrow toward the middle.",
}


## Solo: plays [param id] now, as a fresh client on that preset in this one's place, which is
## what a server's mode change is (a game change). Deferred, because the menu that asked is
## this client's own child and is still handling the key.
func change_mode_offline(id: StringName) -> DotResult:
	if not _offline:
		return DotResult.fail(DotError.CODE_STATE, "The server changes the mode.")
	if not MODE_IDS.has(id) and not (workshop != null and workshop.has(id)):
		return DotResult.fail(DotError.CODE_INVALID, "There is no mode called '%s'." % id)
	_replace_with.call_deferred(id)
	DotLog.info(CHANNEL, "mode changed from the map menu", {"mode": String(id)})
	return DotResult.success(id)


func _replace_with(id: StringName) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var packed: Variant = load(scene_file_path) if scene_file_path != "" else null
	var fresh: Node = (packed as PackedScene).instantiate() if packed is PackedScene else (get_script() as GDScript).new()
	fresh.set(&"force_offline", true)
	fresh.set(&"offline_bots", offline_bots)
	fresh.set(&"offline_preset", id)
	var at := get_index()
	parent.remove_child(self)
	queue_free()
	parent.add_child(fresh)
	parent.move_child(fresh, at)
	replaced.emit(fresh)


func _build_ui() -> void:
	ui_config = DotUiConfig.new()
	ui_config.allow_pause = _offline

	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	screens = DotScreenStack.new()
	screens.name = "Screens"
	screens.config = ui_config
	screens.load_layered_config = false
	screens.register_service = true
	screens.service_scope = &"hungry"
	# A blob game is played with a visible cursor: the cursor is the control.
	screens.idle_mouse_mode = DotScreen.Mouse.VISIBLE
	screens.ui_theme = DotUiTheme.space()
	layer.add_child(screens)
	screens.setup()

	hud = HungryHud.new()
	hud.name = "Hud"
	hud.config = ui_config
	layer.add_child(hud)
	hud.build(world, bridge, _local_player())
	hud.bind_stack(screens)

	# The sampler reads the on-screen buttons directly. Built here rather than in the
	# sampler because whether a device wants them is a HUD question, and because the HUD
	# is what puts them inside the safe area.
	sampler.touch = hud.touch

	if platform.board is DotMenuScoreboard:
		HungryMenus.dress_board(platform.board as DotMenuScoreboard, world, bridge)

	# Escape, H and Leave are dot-menu's, built with the player's settings by the presentation
	# layer. What is this game's is the Loadout page, first, because Escape is where a player
	# goes to change what they bring in.
	menu = presentation.menu_settings.menu if presentation != null and presentation.menu_settings != null else null
	loadout_page = HungryMenus.loadout_page(bridge)
	loadout_page.on_chosen(_on_loadout_chosen)
	if menu != null:
		var _l := menu.add_page(loadout_page.page, &"general")
		# The HUD in the menu's theme and at the player's HUD size, live. The HUD is built after
		# the platform's setup, so it is handed over late.
		if hud != null:
			platform.set_hud(hud, HungryHud.accent_theme())
		loadout_page.on_redraw(menu.screen.refresh)

	# A value changed in the menu or at the console reaches the config first (the
	# presentation layer's handler is connected before this one), then what reads it.
	if presentation != null and presentation.settings != null:
		presentation.settings.changed.connect(func(_k: StringName, _v: Variant, _w: StringName) -> void: _apply_settings())

	_apply_settings()

	_wire_chat_window()

	hud.say(
		"Move with the mouse — near is slow, far is fast.",
		Color(0.70, 0.78, 0.90)
	)
	# The keys as they are bound now, from the table the Controls page rebinds.
	var keys := presentation.menu_settings.bindings if presentation != null and presentation.menu_settings != null else HungryBindings.make()
	hud.say(
		"%s splits, %s ejects, %s throws. Let go of the mouse to gather." % [
			keys.key_for(HungryBindings.SPLIT), keys.key_for(HungryBindings.EJECT),
			keys.key_for(HungryBindings.THROW),
		],
		Color(0.70, 0.78, 0.90)
	)
	hud.say(
		"%s is the board, %s is chat, %s is help, %s the modes, Escape is the menu and your loadout." % [
			keys.key_for(HungryBindings.SCOREBOARD), keys.key_for(HungryBindings.CHAT),
			keys.key_for(DotMenuBindings.HELP_ACTION), DotInputBinding.describe_action(&"dot_menu_maps"),
		],
		Color(0.62, 0.68, 0.78)
	)


## What the camera frames and the pointer is measured from.
##
## [b]Not always your own monster.[/b] Being eaten in this game means having nothing at
## all — no pieces, no position, nowhere for a camera to be — and a camera left where you
## died is a black rectangle for three seconds while the fight that killed you carries on
## somewhere else. So a dead player watches whoever ate them, and if that player has since
## been eaten too, the leader.
##
## The [i]input[/i] reads the same source, which is deliberate: a dead player's pointer is
## measured from the monster they are watching, so the mouse is not silently pointing at
## nothing when they respawn.
func _me_source() -> Callable:
	return func() -> Variant:
		return _watched()


## The monster this client is looking at.
func _watched() -> HungryMonster:
	if world == null:
		return null

	var mine := world.monster_for(_local_player())

	if mine != null and mine.alive:
		return mine

	var killer := world.monster_for(_watching)

	if killer != null and killer.alive:
		return killer

	var board := world.leaderboard(1)
	return board[0] if not board.is_empty() and board[0].alive else mine


## The peer of the other player whose piece is under the pointer, 0 for nobody. Roster rows
## carry the player id (`id`) and the peer; a monster's id is the player id.
func _look_target() -> int:
	if world == null or camera == null or chat == null or chat.self_mute == null:
		return 0

	var at := camera.get_global_mouse_position()
	var me := _local_player()
	var best_id := 0
	var best := 1.0

	for monster in world.monsters():
		if not monster.alive or monster.id == me:
			continue

		for piece in monster.pieces:
			var depth := piece.position().distance_to(at) / maxf(piece.radius(), 0.001)

			if depth < best:
				best = depth
				best_id = monster.id

	if best_id == 0:
		return 0

	for row in chat.self_mute.roster:
		if int(row.get("id", 0)) == best_id and not bool(row.get("bot", false)):
			return int(row.get("peer", 0))

	return 0


func _local_player() -> int:
	return bridge.local_player_id if bridge != null else 1


# --- The loop --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if world == null:
		return

	if _offline:
		_tick_offline(delta)
		return

	if net == null or not net.is_running():
		return

	# The clock is what puts the input ahead of the server. A command for tick N has to be
	# in the server's hands *before* it simulates N, so a client running level with the
	# server has every input arrive one tick late — for ever, with no error, and the only
	# symptom a player who feels heavy.
	var ticks := net.clock.advance(delta)

	# [b]Each pass is its own tick.[/b] `advance` has already moved the clock by all of
	# them, so `input_tick()` is the LAST one on every pass: a frame worth two ticks sent
	# the second twice and the first never, the server repeated a stale command for the
	# one it never got, and the predictor's replay stopped at the hole and drew the player
	# short of where they were -- after every hitch, and on every frame the display and
	# the tick rate do not line up. Arithmetic here rather than a new dot-net call,
	# because a pack has to run on whatever client shell the player already has.
	for i in range(ticks):
		if not net.clock.is_synced():
			continue

		bridge.client_tick(net.clock.input_tick() - (ticks - 1 - i), _sample(delta))


func _process(delta: float) -> void:
	if net != null and net.is_running():
		# Interpolation runs at frame rate, not tick rate. Applying it on the tick would
		# quantise every remote monster's motion to 60 Hz and undo the point of it.
		net.interpolate_frame()

	# Your own monster is drawn between its ticks at the clock's render alpha, not the
	# engine's fraction: the clock stretches and shrinks its ticks while it settles on the
	# server, so a physics frame now and then runs no tick or two, and drawn at the engine's
	# fraction it stood still on one frame and moved double on the next. Offline every
	# physics frame is one tick and every monster, the bots too, is simulated here.
	var clock: Object = net.clock if not _offline and net != null and net.is_running() else null
	if renderer != null:
		renderer.render_clock = clock
		renderer.all_simulated_here = _offline
	if camera != null:
		camera.render_clock = clock

	_watch_mass()

	if presentation != null:
		# Once a frame, with where the camera is. dot-audio culls by distance from the
		# listener and dot-fx ages what it spawned, and neither ticks itself: `_process`
		# does not run while a tree is paused, and a pause menu is exactly when nothing
		# finishes.
		presentation.present(delta, _watched_centre())

	_board_accum += delta

	if _board_accum >= BOARD_INTERVAL_SEC:
		_board_accum = 0.0

		if hud != null:
			hud.refresh_leaderboard()

		var board := platform.board as DotMenuScoreboard

		if board != null and board.is_open():
			board.redraw()


## Where the camera is looking, which is where the listener is.
##
## The **watched** monster rather than the local one: a dead player is watching whoever ate
## them, and a listener left at the corpse would hear a patch of arena nobody is in — which
## is the same bug `HungrySpectate` exists to fix for the camera, one sense over.
func _watched_centre() -> Vector2:
	var monster := _watched()
	return monster.centre() if monster != null else Vector2.ZERO


# --- Offline ---------------------------------------------------------------

## Builds a world with bots in it, for playing without a server.
##
## Not a demo mode bolted on: it is the same world, the same motor and the same
## [HungryBot] the dedicated server runs, with the netcode taken out. That it plays
## identically is the useful property — a control that feels wrong offline is wrong, and
## debugging it does not need two processes.
func _start_offline() -> void:
	world.add_player(1, "You")

	# Named from dot-bot's pool, as a server's are; never "Bot 3".
	var roster := DotBotRoster.new()
	var taken: Array = ["You"]
	for index in range(offline_bots):
		var id := 100 + index
		var bot_name := roster.next_name(taken)
		taken.append(bot_name)
		world.add_player(id, bot_name)
		_bots.append(id)

	# How well they play: `bot_difficulty` (and every `bot_*`) at the console, or
	# `-- --bot_difficulty <preset>` at launch. The same settings a server binds as cvars.
	var skill := DotBotSettings.of(world)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--bot_difficulty")
	if at >= 0 and at + 1 < args.size():
		DotLog.result(CHANNEL, "bot difficulty from the command line", skill.set_difficulty(args[at + 1]))
	if presentation != null and presentation.local_console != null:
		var _bound := skill.bind_console(presentation.local_console)

	DotLog.info(CHANNEL, "playing offline", {"bots": _bots.size()})


## The sampler's command, remembering which of the two mass actions it asked for.
##
## Both are heard by watching the monster rather than the key, because pressing split
## while too small or on cooldown does nothing and a sound for it would be a lie. But a
## monster's piece count also rises when a pepper bursts it, and its mass also falls when
## a split's first half lands a snapshot before the second — so the change is only
## attributed to a key the player actually pressed a moment ago.
func _sample(delta: float = 0.0) -> Dot2DCommand:
	# Nothing is steered or split behind the cover: the sampler is suspended while the platform
	# blocks input, and hands back a neutral command, which the tick still needs to send.
	var command := sampler.sample(delta)
	var now := Time.get_ticks_msec()

	for button in [Dot2DCommand.BUTTON_SPLIT, Dot2DCommand.BUTTON_EJECT]:
		if command.is_pressed(int(button)):
			_asked_at[button] = now

	return command


func _asked_recently(button: int) -> bool:
	return _asked_at.has(button) \
		and Time.get_ticks_msec() - int(_asked_at[button]) <= ASKED_WINDOW_MSEC


func _tick_offline(_delta: float) -> void:
	# The bots do not wait for a cover: a round that ran while it was up would be a round
	# the player starts already losing.
	if not platform.is_shown():
		return

	_tick += 1

	var commands: Dictionary = {1: _sample()}

	for id in _bots:
		var monster := world.monster_for(id)

		if monster != null:
			commands[id] = HungryBot.command_for(world, monster, _tick)

	world.tick(commands)


# --- Events ----------------------------------------------------------------

## Reason the gate is held under while the server rebuilds the world.
const REASON_MAP := &"map"
var _map_held: bool = false


func _on_game_changed_online(_game_id: String, _content_id: String, _name: String) -> void:
	if platform == null or platform.gate == null or not is_instance_valid(platform.gate):
		return
	_map_held = true
	platform.gate.hold(REASON_MAP, "Changing map")
	DotLog.debug(CHANNEL, "the server changed the game; covering until the new world arrives")


## The new world is in: the link has finished the game change (`spawned`, after
## `game_changed`), or its hello arrived while the hold was up.
func _release_map_hold() -> void:
	if not _map_held:
		return
	_map_held = false
	if presentation != null and world != null and world.preset != null:
		presentation.on_map(world.preset.id)
	if platform != null and platform.gate != null and is_instance_valid(platform.gate):
		platform.gate.release(REASON_MAP)


func _on_hello(player_id: int) -> void:
	DotLog.info(CHANNEL, "admitted", {"player": player_id})

	# The server sends this hello from its own rebind, which can arrive before the link has
	# announced the game change, so it cannot be the only release (the hold would then be
	# taken after it and wait for the gate's timeout). It releases a hold already taken.
	_release_map_hold()

	if hud != null:
		hud.follow(player_id)
		hud.watching_source = _watched

	if renderer != null:
		renderer.local_player_id = player_id

	# The page opens on what the player is actually wearing rather than on the schema's
	# default, which is what the server sent in the join.
	var monster := world.monster_for(player_id)

	if loadout_page != null and monster != null and monster.loadout != null:
		loadout_page.show_loadout(monster.loadout)

	_fetch_cosmetics(bridge.avatar_pack_url)

	# The rider goes up as soon as there is somebody to put one on. A stored avatar would
	# come from dot-user-avatar's manager; without one the deterministic guest is what
	# every other client already draws for this id, so publishing it costs nothing and
	# keeps one code path.
	bridge.publish_avatar(HungryContent.default_avatar(player_id))


## Downloads this server's rider content, if it has any and this build can.
##
## [b]Nothing waits for it.[/b] A rider whose parts have not arrived is drawn instead, so
## a player is in the world immediately and their cosmetics improve when they land. That
## ordering is the whole reason [HungryRider] draws a fallback: a cosmetic somebody else
## is wearing is not something you can be made to wait for.
##
## dot-cloud is duck-typed, so a build without it simply never has anything to ask.
func _fetch_cosmetics(manifest_url: String) -> void:
	if manifest_url == "":
		return

	var cloud := DotRegistry.get_service(HungryContentSource.CLOUD_SERVICE)

	if cloud == null or not cloud.has_method("acquire"):
		DotLog.info(CHANNEL, "the server has rider content and this build cannot fetch it")
		return

	DotLog.info(CHANNEL, "fetching rider content", {"url": manifest_url})

	var acquired: Variant = await cloud.call("acquire", manifest_url)

	if acquired is DotResult and not (acquired as DotResult).ok:
		# Not a failure worth interrupting anybody for: the parts fall back to being
		# drawn, which is what every client without the pack already sees.
		DotLog.info(CHANNEL, "rider content did not arrive", {
			"error": str((acquired as DotResult).error)
		})


func _on_cue(kind: int, data: Dictionary) -> void:
	if hud != null:
		hud.note(kind, data)

	# Every death on screen goes down the way the server picked, heard or not.
	if kind == HungryEvents.Kind.DIED and renderer != null and renderer.falls != null:
		var _fell := renderer.falls.fall(int(data.get("first", 0)), data.get("death"))

	if sound == null:
		return

	# Only what happened to somebody. A cue is the authority telling every client, so
	# playing all of them would mean hearing every death on the map — which at sixteen
	# players is a wall of noise that says nothing about your own game.
	var me := _local_player()

	if presentation == null:
		return

	match kind:
		HungryEvents.Kind.DIED:
			if int(data.get("first", 0)) == me:
				presentation.on_died()
				_watching = int(data.get("second", 0))
			elif int(data.get("second", 0)) == me:
				presentation.on_devour()

		HungryEvents.Kind.BURST:
			var first := int(data.get("first", 0))
			if first == me or int(data.get("second", 0)) == me:
				var burst_monster := world.monster_for(first) if world != null else null
				presentation.on_burst(
					burst_monster.centre() if burst_monster != null else Vector2.ZERO,
					first == me
				)

		HungryEvents.Kind.THROW:
			# Your own, as offline hears it through `_on_projectile_thrown`. The cue goes to
			# every client for every throw on the map, and the sound is flat rather than
			# placed, so without this a netted player heard somebody's pepper on the far
			# side of the arena as though they had thrown it themselves.
			var shot: Variant = data.get("shot")
			if shot is HungryProjectile and (shot as HungryProjectile).thrower_id == me:
				presentation.on_throw()


## Turns "I got bigger" into a noise.
##
## [b]Watched rather than listened for, and that is not a shortcut.[/b]
## [signal HungryWorld.food_eaten] fires on the authority, which on a netted client is
## somewhere else — so a client that hooked it would be silent for the entire game and
## perfectly noisy offline, which is exactly the kind of difference nothing catches. What
## a player actually perceives is their own mass going up, and that arrives either way.
##
## Several crumbs swallowed between two snapshots become one blip. That is the right
## trade: nine blips in the same frame is a click, and the pitch already says how much it
## was worth.
func _watch_mass() -> void:
	if sound == null:
		return

	var monster := world.monster_for(_local_player()) if world != null else null

	if monster == null or not monster.alive:
		_last_mass = 0.0
		_last_carried = 0
		_last_pieces = 0
		return

	var mass := monster.mass()
	var pieces := monster.piece_count()

	if _last_mass <= 0.0:
		# First look, or the first frame after a respawn. A monster appearing at its
		# starting mass has not eaten anything.
		_last_mass = mass
		_last_carried = monster.carried.size()
		_last_pieces = pieces
		return

	var gained := mass - _last_mass
	var more_pieces := pieces > _last_pieces
	_last_mass = mass
	_last_pieces = pieces

	# Split and eject had a voice each in the bank since the first commit, and a row each
	# in dot-audio's catalogue, and nothing ever played either: the one action this game
	# is about was silent.
	if more_pieces and _asked_recently(Dot2DCommand.BUTTON_SPLIT):
		presentation.on_split()
	elif not more_pieces and gained <= -HungryContent.EJECT_MASS * 0.6 \
			and _asked_recently(Dot2DCommand.BUTTON_EJECT):
		presentation.on_eject()

	# Through the presentation layer rather than straight at the bank. `HungrySound` still
	# makes the noise -- it is dot-audio's sink here -- but the cap, the cooldown and the
	# distance cull are the addon's, and a bank called directly is a bank with none of
	# them: a monster in a dense field eats several times a second and nine blips in one
	# frame is a click.
	var at := monster.centre()

	# Not while a piece is appearing. A split or a burst conserves mass only once both
	# halves are seen; over the network the new piece and its parent's halved mass need
	# not land on the same frame, and the gap reads as a mouthful worth half the monster.
	if more_pieces:
		pass
	elif gained >= HungryContent.FRUIT_MASS * 0.8:
		presentation.on_fruit_eaten(at)
	elif gained >= 0.5:
		# Pitched by how much it was worth, through the same curve the food tiers use, so
		# a haunch and a crumb are the same blip an octave apart.
		presentation.on_food_eaten(
			at, HungryContent.food_tier(clampf(gained / 30.0, 0.0, 0.999))
		)

	var carried := monster.carried.size()

	if carried > _last_carried:
		presentation.on_pickup()

	_last_carried = carried


func _on_projectile_thrown(shot: HungryProjectile) -> void:
	if presentation != null and shot.thrower_id == _local_player():
		presentation.on_throw()


func _on_player_died(player_id: int, killer_id: int) -> void:
	if renderer != null and renderer.falls != null:
		var monster := world.monster_for(player_id)
		var _fell := renderer.falls.fall(player_id, monster.death if monster != null else null)

	if sound == null:
		return

	if player_id == _local_player():
		presentation.on_died()
		_watching = killer_id
	elif killer_id == _local_player():
		presentation.on_devour()


func _on_monster_burst(player_id: int, by_player: int, _count: int) -> void:
	if presentation == null:
		return
	var mine := player_id == _local_player()
	if not mine and by_player != _local_player():
		return
	var monster := world.monster_for(player_id) if world != null else null
	presentation.on_burst(monster.centre() if monster != null else Vector2.ZERO, mine)


func _on_beacon_pulsed(_player_id: int, at: Vector2) -> void:
	if presentation != null:
		var _handle := presentation.on_beacon(at)


func _on_roster_changed(player_id: int) -> void:
	if renderer != null and world != null and world.monster_for(player_id) == null:
		renderer.forget(player_id)


## Pushes the player's settings at everything that reads one.
##
## [b]Pushed rather than read.[/b] The camera, the sound and the HUD each hold the value
## they were given; making them ask a config every frame would put a dictionary lookup in
## the draw path for something that changes when somebody opens a menu.
func _apply_settings() -> void:
	if settings == null:
		return

	if camera != null:
		camera.follow_sec = settings.follow_sec
		camera.zoom_with_size = settings.zoom_with_size

	if renderer != null:
		renderer.show_names = settings.show_names
		renderer.show_threat = settings.show_threat

	if hud != null:
		hud.set_minimap_visible(settings.show_minimap)

		if hud.feed != null:
			hud.feed.max_lines = settings.feed_lines


## Sends a chosen loadout, and says what happens next.
##
## The server validates it and it takes effect on the next spawn — a player who could
## change their trait mid-fight would change it the moment they were losing — so the feed
## says so rather than leaving them wondering whether the button did anything.
func _on_loadout_chosen(loadout: DotLoadout) -> void:
	if bridge != null:
		bridge.publish_loadout(loadout)

	if hud != null:
		hud.say(
			"Loadout sent. It takes effect the next time you spawn.",
			Color(0.70, 0.82, 0.95)
		)


## A routed line off this game's own wire. Filed by [DotChatClient], which drops a
## duplicate and reports a gap.
func _on_chat_wire(wire: Dictionary) -> void:
	if chat != null:
		chat.receive(wire)


## A line [DotChatClient] accepted: in sequence, not a duplicate, on a known channel.
func _on_chat_message(message: DotChatMessage, channel_id: StringName) -> void:
	if hud == null:
		return

	var chan := chat.channel(channel_id)
	var prefix := "%s " % chan.prefix if chan != null and chan.prefix != "" else ""

	# [b]The channel decides how a line is drawn, and the channel is a document.[/b] Its
	# prefix and colour come off the [DotChatChannel] both ends share, so adding a channel
	# is adding a definition rather than a branch somebody has to remember to extend.
	#
	# [b]In the chat box, and in the feed only when there is no box.[/b] Both drew every
	# line: a vote's ballot was printed twice, once in each corner, and the feed's copy ran
	# under the vote countdown at the top of the screen. The feed keeps what is the game's
	# (who ate whom).
	var window := _chat_window()

	# A join or leave notice is a name and no text (dot-chat's `_presence`): drawn by its
	# text it was an empty line in the box, and by name and text a bare "Guest 435:".
	# `describe()` words it ("Guest 435 joined"); every other kind is drawn by its text.
	var text := message.describe() \
		if message.kind in [DotChatMessage.Kind.JOIN, DotChatMessage.Kind.LEAVE] \
		else message.text

	if message.is_from_server() or message.sender_name == "":
		if window != null:
			window.add_text("%s%s" % [prefix, text], Color(0.80, 0.82, 0.86))
		else:
			hud.say(
				"%s%s" % [prefix, text],
				chan.colour if chan != null else Color(0.62, 0.78, 1.0)
			)

		return

	if window != null:
		window.add_said(
			"%s%s" % [prefix, message.sender_name],
			message.text,
			chan.colour if chan != null else Color(0.62, 0.78, 1.0)
		)
	else:
		hud.chat({
			"name": "%s%s" % [prefix, message.sender_name],
			"text": message.text,
		})


# --- Chat ------------------------------------------------------------------

## The chat box, or null before the presentation layer exists.
func _chat_window() -> DotChatWindow:
	return presentation.chat_window if presentation != null else null


## Joins the chat box to the three things it needs.
##
## [b]The microphone closes with the keyboard, and that line moved rather than went.[/b]
## The old Enter handler released the talk gate before opening the box, because otherwise
## the key-up for the talk key lands in the chat box, the gate is never closed, and the
## player broadcasts whatever they say while typing. It belongs on `opened` now, where it
## fires however the box was opened rather than only from the one key that used to open it.
##
## [b]The sampler is suspended too.[/b] Steering here is the mouse, so typing does not walk
## anybody anywhere — but split, throw, boost and eject are keys, and "gg boost" splits you
## twice and ejects your mass.
func _wire_chat_window() -> void:
	var window := _chat_window()

	if window == null:
		return

	window.submitted.connect(_on_chat_submitted)

	window.opened.connect(func(_channel: StringName) -> void:
		if voice != null:
			voice.release()
	)

	var client_link := DotRegistry.get_service(&"dot_client_link")

	if client_link != null and client_link.has_signal("chat_received"):
		client_link.connect("chat_received", _on_server_chat_state)


## One handler for the sampler: the platform says when the cover, a menu, the console or the chat
## line has the keyboard. Split, throw, boost and eject are keys, and "gg boost" would eject
## the player's mass.
func _suspend_input(blocked: bool) -> void:
	if sampler != null:
		sampler.suspended = blocked


## dot-server's chat payload: what is carrying the conversation, and the server's own lines.
##
## A PLAYER's line is never drawn from here: this game routes those over its own wire, so
## drawing them here as well would be the same line twice. The server's own lines (`system`:
## a vote between games, "Ada joined the game."; `admin`: an admin's `say`) come only this
## way, and dropping them with the players' lines is how this game never showed one. The same
## drawing as dot-game's `DotGameChatClient.draw_server_line`, which this game does not link.
func _on_server_chat_state(payload: Dictionary) -> void:
	var kind := str(payload.get("kind", ""))

	if kind == "system" or kind == "admin":
		_draw_server_line(kind, str(payload.get("name", "")), str(payload.get("text", "")).strip_edges())
		return

	if kind != "state":
		return

	if presentation != null:
		presentation.set_chat_relayed(bool(payload.get("relay", false)))


func _draw_server_line(kind: String, speaker: String, text: String) -> void:
	var window := _chat_window()

	if window == null or text == "":
		return

	if kind == "system":
		window.add_text(text if speaker == "" else "%s %s" % [speaker, text], Color(0.98, 0.84, 0.40))
	else:
		window.add_said(speaker, text, Color(0.98, 0.72, 0.35))


func _on_chat_submitted(text: String, channel: StringName) -> void:
	_on_say(text, channel)


func _on_say(text: String, channel: StringName = HungryServices.CHANNEL_ALL) -> void:
	if bridge != null and not bridge.net.is_server:
		bridge.say(channel, text)
	elif hud != null:
		hud.say("(offline) %s" % text, Color(0.6, 0.62, 0.66))


# --- What is in the arena besides the players ------------------------------

func _on_hunter(state: Dictionary) -> void:
	if hunters == null:
		return

	hunters.adopt(
		int(state["hunter_id"]),
		HungryHunters.id_at(int(state["kind_index"])),
		state["position"],
		float(state["radius"]),
		bool(state["alive"])
	)


func _on_hazard(state: Dictionary) -> void:
	if hazards == null:
		return

	if bool(state["present"]):
		hazards.adopt(
			int(state["place_id"]),
			HungryHazards.id_at(int(state["kind_index"])),
			state["position"]
		)
	else:
		hazards.drop(int(state["place_id"]))


## The mode vote's cue and countdown. The ballot itself arrives as chat in the feed; this
## is what chat cannot carry.
func _on_vote_cue(info: Dictionary) -> void:
	var seconds_left := int(info.get("seconds_left", 0))

	if seconds_left > 0 and hud != null:
		hud.vote_countdown(seconds_left, bool(info.get("runoff", false)))

	if presentation != null:
		presentation.on_vote_cue(StringName(str(info.get("cue", ""))))


## Somebody earned something. Everybody is told, because an achievement nobody sees is a
## number in a file.
func _on_progress(state: Dictionary) -> void:
	if hud == null:
		return

	var mine: bool = bridge != null and int(state["player_id"]) == bridge.local_player_id

	hud.say(
		"%s %s (%d)" % [
			"You earned" if mine else "Somebody earned",
			str(state["title"]),
			int(state["value"]),
		],
		Color(1.0, 0.85, 0.40) if mine else Color(0.78, 0.72, 0.58)
	)


# --- Input -----------------------------------------------------------------

## The talk key. The held Tab board is the platform's. Escape, H and the menu's keys are dot-menu's
## ([HungrySettings]), which takes every key while anything of its is open.
func _unhandled_input(event: InputEvent) -> void:
	# [b]Voice first, and on both edges.[/b] Everything below this line is `is_pressed`,
	# so a release handled there would never arrive — and a talk gate opened by a key-down
	# and never closed is an open microphone for the rest of the session.
	if voice != null and voice.handle_event(event):
		get_viewport().set_input_as_handled()
		return


func describe() -> Dictionary:
	return {
		"offline": _offline,
		"player": _local_player(),
		"world": world.describe() if world != null else {},
		"bridge": bridge.describe() if bridge != null else {},
	}
