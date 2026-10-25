extends DotMenuSettings

const HungryBindings := preload("hungry_bindings.gd")
const HungryConfig := preload("../hungry_config.gd")

## A player's settings and the Escape menu that changes them: dot-menu's, as in every game of
## the family, over one dot-settings document.
##
## [codeblock]
## var settings := HungrySettings.new()
## add_child(settings)
## settings.setup()                 # migrates once, loads, applies, builds the menu
## settings.bind_audio(audio)       # dot-audio's mixer: the stock volumes
## settings.bind_fx(fx)             # dot-fx: shake, flashes, effects quality
## [/codeblock]
##
## [b]The document holds this game's own settings beside the stock ones.[/b] The camera and
## interface keys are still declared by [HungryConfig] and read out of it with
## [method DotSettingsSchema.from_config], so a range tightened there tightens the slider and
## the console at once; the presentation layer writes each value back into the config the
## game reads. The keys are [HungryBindings]' table; help (H), the map menu (M) and Leave are
## dot-menu's stock.
##
## [b]Where it is stored did not move[/b]: the same directory and namespace as the
## dot-settings document this game kept since 2026-09 for the console, net_stat and the chat
## keys, so all of that carries over untouched. What moved is everything dot-ui's screens
## kept in files of their own until 2026-10-12, which [method migrate] reads once.

## This file's log channel. Not `CHANNEL`, which is DotMenuSettings' own ("menu.settings").
const SETTINGS_CHANNEL := "hungry.settings"

## 2 is the first document that holds everything. A version-1 document (or none) is migrated
## from the two files dot-ui's screens wrote; see [method migrate].
const SCHEMA_VERSION := 2

const SETTINGS_DIR := "user://hungry_settings"
const APP_NAMESPACE := &"game_hungario"

## What dot-ui's settings screen saved (`HungryConfig.save`, a flat JSON object).
const LEGACY_CONFIG_PATH := "user://cfg/hungry.json"
## What dot-ui's Controls screen saved (`DotBindingsPanel.save`, `{bindings: {action: [event]}}`).
const LEGACY_BINDINGS_PATH := "user://cfg/bindings.json"

## Which of the config's keys follow the person rather than the machine: the one thing
## `HungryConfig` cannot say about itself. A camera follow time is about this screen; a name
## plate preference and a feed length are about the person.
const SCOPES := {
	&"show_names": DotSettingsDef.Scope.ACCOUNT,
	&"show_threat": DotSettingsDef.Scope.ACCOUNT,
	&"feed_lines": DotSettingsDef.Scope.ACCOUNT,
	&"show_minimap": DotSettingsDef.Scope.ACCOUNT,
}

## Stock keys nothing here could apply, left out so no row is a switch that does nothing:
## the world is 2D (no 3D render scale, no field of view), the mouse is a pointer and not a
## look (no sensitivity, no invert). The voice settings (talk mode, microphone, voice volume)
## are declared: `HungryVoice` publishes its manager as `dot_voice_client`, which dot-menu's
## applier binds by that name. The talk key is a row of the table.
const NOT_APPLIED: Array[StringName] = [
	&"render_scale", &"field_of_view", &"sensitivity", &"invert_mouse",
]

## The master volume this game starts at: about the loudness the bank had when its own
## volume was applied twice (to every voice and to the Master bus, -8 dB each). The family's
## 0.8 is 6 dB louder than this game has ever been.
const DEFAULT_MASTER := 0.4

## The legacy key and its action, for [method migrate]: `[action, setting, mouse]`, where
## `mouse` says which kind of input the row takes out of the action's events.
const LEGACY_KEYS := [
	[&"hungry_split", &"bind_split", false],
	[&"hungry_split", &"bind_split_click", true],
	[&"hungry_throw", &"bind_throw", false],
	[&"hungry_throw", &"bind_throw_click", true],
	[&"hungry_eject", &"bind_eject", false],
	[&"hungry_boost", &"bind_boost", false],
]

## The store [method setup] uses when it is not handed one: a suite's memory store.
var store: DotSettingsStore = null
## Where [method migrate] looks. Empty skips that file (a suite).
var legacy_config_path: String = LEGACY_CONFIG_PATH
var legacy_bindings_path: String = LEGACY_BINDINGS_PATH

## What the migration did this start: the keys it carried over. Empty when there was
## nothing to migrate, or it had already run.
var migrated: PackedStringArray = PackedStringArray()


func _init() -> void:
	name = "Settings"
	directory = SETTINGS_DIR
	app_namespace = APP_NAMESPACE
	schema = schema_for()
	bindings = HungryBindings.make()
	# The pointer is the control in this game and the client keeps it visible.
	manage_pointer = false
	# M is the mode list (dot-menu's map menu, on by default): `HungryClient._build_ui` hands it
	# the six modes and the change.
	config = DotMenuConfig.new()
	config.brand_name = "Hungario"
	# Top left: the top right is the leaderboard's, the bottom corners the minimap's and the
	# mass bar's.
	config.help_hint = &"top_left"
	config.settings = {"master_volume": {"default": DEFAULT_MASTER}}
	var _layered := config.load_layered()


## This game's camera and interface keys out of [HungryConfig], net_stat in the top left,
## then the stock settings it applies.
static func schema_for() -> DotSettingsSchema:
	var s := DotSettingsSchema.from_config(HungryConfig.new(), SCOPES)
	s.version = SCHEMA_VERSION
	var _net := DotMenuStock.declare_net_stat(s, &"top_left")
	s.add(DotSettingsDef.boolean(&"ambient", true, &"audio").with_description("Quiet sounds under the arena."))
	s.add(DotSettingsDef.number(&"ambient_volume", 1.0, 0.0, 1.0, &"audio"))
	return DotMenuStock.declare(s, DotMenuStock.DEFAULT_GROUPS, null, NOT_APPLIED)


## Migrates the old files into the document first, then dot-menu's setup.
func setup(p_store: DotSettingsStore = null, with_menu: bool = true) -> DotResult:
	var where: DotSettingsStore = p_store if p_store != null else store
	if where == null:
		where = DotSettingsStoreFile.new(directory)
	migrated = migrate_store(where, app_namespace, legacy_config_path, legacy_bindings_path)
	var res := super.setup(where, with_menu)
	if res.ok and menu != null:
		var _g := menu.add_page(game_page(), &"video")
	return res


## Brings a version-1 document (or none) up to 2 in [param where], once: anything the old
## files hold that the document does not is written into it, and the document is saved at
## version 2 so this never runs again, whatever the player changes later. Returns the keys
## carried over. Nothing is deleted: the old files are read, never written.
##
## [b]The document wins over the old files.[/b] That is what the player saw: the old client
## loaded `hungry.json` and then laid the document over it, so a key the console had set was
## the one in force.
static func migrate_store(
	where: DotSettingsStore, app: StringName, config_path: String, bindings_path: String
) -> PackedStringArray:
	var loaded := where.load_document(app, &"local")
	if not loaded.ok:
		return PackedStringArray()
	var raw: Dictionary = loaded.value
	if int(raw.get("version", 1)) >= SCHEMA_VERSION:
		return PackedStringArray()

	var body: Dictionary = (raw.get("values", {}) as Dictionary).duplicate(true) if raw.has("values") else raw.duplicate(true)
	body.erase("version")
	var legacy_config := _read_object(config_path)
	var legacy_keys: Variant = _read_object(bindings_path).get("bindings", {})
	var out := migrate(body, legacy_config, legacy_keys if legacy_keys is Dictionary else {})
	var carried: PackedStringArray = out["carried"]
	if raw.is_empty() and carried.is_empty():
		# A first run: no document, nothing to bring. Nothing is written, so a player who
		# never changes anything leaves no file behind.
		return carried

	var saved := where.save_document(app, &"local", {"version": SCHEMA_VERSION, "values": out["values"]})
	if not saved.ok:
		DotLog.warn(SETTINGS_CHANNEL, "the migrated settings were not saved; they are migrated again next start",
			{"why": saved.error.message})
	else:
		DotLog.info(SETTINGS_CHANNEL, "settings migrated to dot-menu's document", {"carried": ", ".join(carried)})
	return carried


## The migration itself, on dictionaries: [param body] is the version-1 document's values,
## [param legacy_config] what `hungry.json` held, [param legacy_keys] the old bindings file's
## `bindings` object. Returns `{values, carried}`.
##
## - The camera and interface keys come over by name where the document has none.
## - The volume becomes the stock master volume. The old one was decibels, applied twice (to
##   the bank's voices and to the Master bus); the bank's own level is now fixed at its old
##   default, so the master that keeps a player's loudness is `2 * old + 8` dB, capped at
##   full. Muted is a master of 0.
## - Split and throw were a key and a mouse button on one action; each becomes its row's
##   binding, the key to `bind_*` and the button to `bind_*_click`.
static func migrate(body: Dictionary, legacy_config: Dictionary, legacy_keys: Dictionary) -> Dictionary:
	var values := body.duplicate(true)
	var carried := PackedStringArray()

	for key in HungryConfig.new().config_keys():
		if not values.has(key) and legacy_config.has(key):
			values[key] = legacy_config[key]
			carried.append(key)

	var had_volume := values.has("volume_db") or legacy_config.has("volume_db")
	var had_mute := values.has("muted") or legacy_config.has("muted")
	if not values.has("master_volume") and (had_volume or had_mute):
		var db := float(values.get("volume_db", legacy_config.get("volume_db", -8.0)))
		var muted := bool(values.get("muted", legacy_config.get("muted", false)))
		values["master_volume"] = 0.0 if muted else clampf(db_to_linear(2.0 * db + 8.0), 0.0, 1.0)
		carried.append("master_volume")
	values.erase("volume_db")
	values.erase("muted")

	for entry in LEGACY_KEYS:
		var setting := String(entry[1])
		if values.has(setting):
			continue
		var events: Variant = legacy_keys.get(String(entry[0]), [])
		if not (events is Array):
			continue
		for e in (events as Array):
			var event := _decode(e)
			if event == null or (event is InputEventMouseButton) != bool(entry[2]):
				continue
			values[setting] = DotInputBinding.to_text(event)
			carried.append(setting)
			break

	return {"values": values, "carried": carried}


## dot-ui's own encoding of one event (`DotBindingsPanel._encode`), read back.
static func _decode(data: Variant) -> InputEvent:
	if not (data is Dictionary):
		return null
	match str((data as Dictionary).get("type", "")):
		"key":
			var code := int(data.get("code", 0))
			if code == 0:
				return null
			var key := InputEventKey.new()
			if bool(data.get("physical", true)):
				key.physical_keycode = code as Key
			else:
				key.keycode = code as Key
			return key
		"mouse":
			var button := int(data.get("button", 0))
			if button <= 0:
				return null
			var click := InputEventMouseButton.new()
			click.button_index = button as MouseButton
			return click
	return null


## A JSON object off disk, or empty: missing, unreadable and not-an-object are all "nothing
## to migrate", never a reason to refuse to start.
static func _read_object(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var read := DotPaths.read_json(path)
	if not read.ok or not (read.value is Dictionary):
		DotLog.warn(SETTINGS_CHANNEL, "an old settings file could not be read; it is not migrated",
			{"path": path, "why": read.error.message if not read.ok else "not an object"})
		return {}
	return read.value


# --- The menu ---------------------------------------------------------------------

## The goal and the rules; the keys come from [HungryBindings].
func _fill_help(help: DotMenuHelp) -> void:
	fill_help(help)


static func fill_help(help: DotMenuHelp) -> void:
	help.about = "Steer a monster with the mouse and grow by eating: food, and anybody smaller than you. Split to throw half of you at somebody, but your pieces cannot merge for a while, so each is easier to eat. When you are eaten you watch whoever ate you until you respawn."
	help.add_section("Mouse", [["Point", "Steer: the further the cursor, the faster; on yourself to pull your pieces together"]], &"keys")
	help.add_text("Fruit and throwables", "Fruit gives you eight seconds of something: rush (faster), maw (eat players closer to your size) or rind (absorbs one burst). A pepper bursts whoever it hits into five pieces, a frostberry slows them, and a lure drops a ring of food where it lands.")
	help.add_text("Loadout", "Escape, then Loadout: a starting throwable and a trait. The server checks it, and it takes effect the next time you spawn.")
	help.add_text("Modes", "Classic, the square arena. Frenzy, small and fast. Gauntlet, a long narrow corridor. Warrens, rocks and refuges. Reef, a wall with four channels. Shallows, posts whose gaps narrow toward the middle. The players vote for the next mode; M lists them (solo it changes now).")


## This game's own page: the camera and what is drawn over the arena, the keys
## [HungryConfig] declares.
static func game_page() -> DotMenuPage:
	var p := DotMenuPage.make(&"game", "Game", "The camera, and what is drawn over the arena.")
	p.section("Camera") \
		.add(DotMenuRow.slider(&"follow_sec", "Camera lag", "How long the camera takes to catch up with you. Off snaps.")
			.formatted(func(v: float) -> String: return "Off" if v <= 0.0 else "%.2f s" % v)) \
		.add(DotMenuRow.toggle(&"zoom_with_size", "Zoom out as you grow", "Off keeps one zoom: you see less, and react faster."))
	p.section("On the arena") \
		.add(DotMenuRow.toggle(&"show_threat", "Threat rings", "Rings every monster by whether you could eat it, or it you.")) \
		.add(DotMenuRow.toggle(&"show_names", "Names", "Everybody's name above their monster.")) \
		.add(DotMenuRow.toggle(&"show_minimap", "Minimap", "In the bottom-right corner.")) \
		.add(DotMenuRow.slider(&"feed_lines", "Message lines", "Lines the feed keeps on screen at once.")
			.formatted(func(v: float) -> String: return "Off" if v <= 0.0 else "%d" % roundi(v)))
	return p
