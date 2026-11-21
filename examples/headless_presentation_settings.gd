extends "headless_presentation_checks.gd"
## The settings checks of the presentation suite: the schema read from HungryConfig, and the one-time
## migration of the files dot-ui's screens wrote. Split out of headless_presentation.gd, which extends this.


func _test_schema_is_the_config() -> void:
	_section("The schema is HungryConfig, read rather than repeated, beside dot-menu's stock")

	var config := HungryConfig.new()
	var schema := HungrySettings.schema_for()

	_check(schema.validate().ok, "the document's schema validates")
	var missing := PackedStringArray()
	for key in config.config_keys():
		if not schema.has(StringName(key)):
			missing.append(key)
	_check(missing.is_empty(), "with every config key in it (%s)" % ", ".join(missing))

	var follow := schema.find(&"follow_sec")
	_check(
		follow != null and is_equal_approx(follow.max_value, 0.5),
		"and its bounds come from the @export_range, so tightening the config tightens "
		+ "the slider and the console at once"
	)
	_check(
		schema.find(&"show_names").scope == GSSettingsDef.Scope.ACCOUNT,
		"the scope is the one thing a config cannot say, so it is passed in"
	)
	_check(
		schema.find(&"follow_sec").scope == GSSettingsDef.Scope.DEVICE,
		"and a camera follow time stays with the machine, because it is about this screen"
	)
	_check(schema.has(&"master_volume") and schema.has(&"ui_theme") and schema.has(&"window_mode"),
		"the stock settings are dot-menu's: the volumes, the theme, the window")
	var applied_to_nothing := PackedStringArray()
	for key in HungrySettings.NOT_APPLIED:
		if schema.has(key):
			applied_to_nothing.append(String(key))
	_check(applied_to_nothing.is_empty() and not schema.has(&"volume_db"),
		"and none this game cannot apply, nor a second volume (%s)" % ", ".join(applied_to_nothing))

	var p := _make()
	p.settings.set_value(&"follow_sec", 0.3)
	_check(
		is_equal_approx(p.config.follow_sec, 0.3),
		"a setting written through dot-settings reaches the config the game actually reads"
	)
	p.settings.set_value(&"master_volume", 0.25)
	_check(
		is_equal_approx(p.audio.mixer.master, 0.25),
		"and the master volume reaches dot-audio's mixer, which is the value a player can hear"
	)
	p.queue_free()

	# The voice settings are the stock ones and reach the player's voice: the client's HungryVoice publishes its manager as dot_voice_client and dot-menu's applier binds it by that name.
	# Armed: drop the publish and the mode never reaches the manager.
	_check(schema.has(&"voice_mode") and schema.has(&"voice_input_device") and schema.has(&"voice_volume"),
		"the stock voice settings are declared: talk mode, microphone, voice volume")
	var voice := HungryVoice.new()
	voice.name = "VoiceP%d" % _entered
	add_child(voice)
	var _v := voice.setup(false)
	var q := _make()
	q.settings.set_value(&"voice_mode", &"open_mic")
	_check(voice.manager != null and voice.manager.open_mic,
		"an open microphone chosen on the Audio page reaches the client's published voice")
	q.settings.set_value(&"voice_mode", &"push_to_talk")
	_check(voice.manager != null and not voice.manager.open_mic, "and push to talk turns it back")
	q.settings.set_value(&"voice_volume", 0.3)
	_check(is_equal_approx(q.audio.mixer.voice, 0.3), "and the voice volume reaches the mixer's voice bus")
	q.queue_free()
	voice.queue_free()
	_done()


## The files dot-ui's screens wrote are migrated into the document once, so nobody's settings
## or keys go back to the defaults; and never again.
func _test_migration() -> void:
	_section("The old settings and keys are migrated once, and nothing is lost")
	var config_path := "user://hungry_migration_test.json"
	var keys_path := "user://hungry_migration_keys_test.json"
	var _c := GSPaths.write_json(config_path, {
		"volume_db": -14.0, "muted": false, "follow_sec": 0.25, "zoom_with_size": false,
		"show_names": false, "feed_lines": 3,
	})
	var _k := GSPaths.write_json(keys_path, {"bindings": {
		"hungry_split": [{"type": "key", "code": KEY_E, "physical": true}, {"type": "mouse", "button": MOUSE_BUTTON_MIDDLE}],
		"hungry_eject": [{"type": "key", "code": KEY_R, "physical": true}],
	}})
	var store := GSSettingsStoreMemory.new()
	# A version-1 document, as the old client left one: the console had set the feed length
	# and net_stat, and that value was the one in force.
	var _d := store.save_document(HungrySettings.APP_NAMESPACE, &"local", {"version": 1, "values": {"feed_lines": 5, "net_stat": 2}})

	var s := HungrySettings.new()
	s.store = store
	s.legacy_config_path = config_path
	s.legacy_bindings_path = keys_path
	add_child(s)
	var res := s.setup(null, false)
	_check(res.ok, "a document migrates and loads", str(res.error) if not res.ok else "")
	var m := s.settings
	_check(is_equal_approx(m.get_float(&"follow_sec"), 0.25) and not m.get_bool(&"zoom_with_size", true)
		and not m.get_bool(&"show_names", true), "the camera and interface choices come over")
	_check(m.get_int(&"feed_lines") == 5 and m.get_int(&"net_stat") == 2,
		"and the document wins where it had a value, which is what the player saw")
	_check(is_equal_approx(m.get_float(&"master_volume"), db_to_linear(2.0 * -14.0 + 8.0)),
		"the volume becomes the master volume at the loudness it had (%.3f)" % m.get_float(&"master_volume"))
	_check(m.get_string(&"bind_split") == "E" and m.get_string(&"bind_split_click") == "Mouse 3"
		and m.get_string(&"bind_eject") == "R", "the keys and the button come over, each to its own row",
		"%s %s %s" % [m.get_string(&"bind_split"), m.get_string(&"bind_split_click"), m.get_string(&"bind_eject")])
	var saved: Dictionary = store.load_document(HungrySettings.APP_NAMESPACE, &"local").value
	_check(int(saved.get("version", 0)) == HungrySettings.SCHEMA_VERSION, "the document is saved at version 2")
	s.queue_free()

	# A second start, after the player put the camera back: the old file must not win again.
	var _back := store.save_document(HungrySettings.APP_NAMESPACE, &"local", {"version": 2, "values": {"follow_sec": 0.1}})
	var again := HungrySettings.migrate_store(store, HungrySettings.APP_NAMESPACE, config_path, keys_path)
	_check(again.is_empty(), "and it never runs twice")
	_check(FileAccess.file_exists(config_path) and FileAccess.file_exists(keys_path), "the old files are read, never deleted")

	# A first run: nothing to migrate, nothing written.
	var fresh := GSSettingsStoreMemory.new()
	var none := HungrySettings.migrate_store(fresh, HungrySettings.APP_NAMESPACE, "", "")
	_check(none.is_empty() and (fresh.load_document(HungrySettings.APP_NAMESPACE, &"local").value as Dictionary).is_empty(),
		"a first run migrates nothing and writes nothing")
	GSPaths.remove_tree(config_path)
	GSPaths.remove_tree(keys_path)

	# The spec's own doing: a first run's defaults, the game page, the corner plates and the help screen.
	var d := HungrySettings.new()
	d.store = GSSettingsStoreMemory.new()
	d.legacy_config_path = ""
	d.legacy_bindings_path = ""
	add_child(d)
	var made := d.setup(null, true)
	_check(made.ok and d.menu != null and is_equal_approx(d.settings.get_float(&"master_volume"), HungrySettings.DEFAULT_MASTER),
		"a first run starts the master volume at this game's 0.4")
	_check(not d.schema.has(&"field_of_view") and d.schema.has(&"net_stat") and d.schema.has(&"ambient"),
		"no field of view (a 2D game), but net_stat and the ambience")
	_check(d.menu.page(&"game") != null and d.config.help_hint == &"top_left" and d.config.menu_button_corner == &"top_left" and not d.manage_pointer,
		"the Game page, the corner plates and the client's own pointer")
	_check(d.menu.help.about.begins_with("Steer a monster"), "and the help screen's goal")
	d.queue_free()
	_done()
