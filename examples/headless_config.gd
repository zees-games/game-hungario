extends DotGameCheckSuite

## The server config and the mode configs through DotGameConfigBinder: fields, cvars, the simulation reading them, strict refusal, the diff, the yml round trip and the workbench.
##
## [codeblock]
## godot --headless --path . res://examples/headless_config.tscn
## [/codeblock]

const HungryCombat := preload("../game/hungry_combat.gd")
const HungryContent := preload("../game/hungry_content.gd")
const HungryModes := preload("../game/hungry_modes.gd")
const HungryServerConfig := preload("../game/hungry_server_config.gd")
const HungryTuning := preload("../game/hungry_tuning.gd")
const ROOT := "user://hungry_cfgtest"
const GAME := "game-hungario"
const CHECKS := 50


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _run() -> void:
	if OS.get_cmdline_user_args().has("--probe"):
		_probe()
		return
	print("game-hungario: config binder")
	_server_config()
	_modes()
	_yml_round_trip()
	_workbench()
	_layers()
	_templates()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _server_config() -> void:
	HungryTuning.reset()
	_check(HungryTuning.result().ok, "the server config loads at its defaults")
	var binder := HungryTuning.binder
	_check(binder.diff().is_empty(), "no diff at the code defaults")
	var keys := PackedStringArray()
	for e: Dictionary in binder.schema():
		keys.append(e["key"])
	for k in ["fruit_effect_sec", "frost_sec", "pepper_damage", "lure_food_count", "throw_cooldown_ticks", "respawn_delay_sec", "spawn_protection_sec", "friendly_fire", "hunter_speed_scale", "max_players", "bot_fill", "hunters_on", "hazards_count", "outgrown", "warrens_corners", "avatar_pack", "backbone_config"]:
		_check(keys.has(k), "%s is exposed" % k)

	var console := DotConsole.new()
	add_child(console)
	var made := binder.bind_cvars(console.cvar, DotConVar.FLAG_ARCHIVE)
	_check(made.size() == keys.size() and console.has_name("hungry_hunters_on") and console.has_name("hungry_outgrown"),
		"every field is a cvar, the hand-written names included")
	console.set_cvar("hungry_pepper_damage", "250")
	var tuning := HungryTuning.settings()
	_check(tuning.pepper_damage == 250.0 and binder.source_of("pepper_damage") == "cvar", "a cvar writes the field")
	_check(is_equal_approx(HungryCombat.damage_rules().maximum, 250.0), "the damage rules read the field")
	console.set_cvar("hungry_respawn_delay_sec", "6")
	_check(is_equal_approx(HungryContent.rules().respawn_delay_sec, 6.0), "the match rules read the field")
	_check(binder.diff_yaml().contains("pepper_damage: 250"), "the diff names the edit")
	var schema_path := "user://hungry_config_schema.json"
	_check(binder.write_schema(schema_path).ok and FileAccess.file_exists(schema_path), "write_schema writes the schema")
	DirAccess.remove_absolute(schema_path)
	console.free()

	var bad := FileAccess.open("user://hungry_config_bad.json", FileAccess.WRITE)
	bad.store_string('{"no_such_field": 1}')
	bad.close()
	var strict := HungryServerConfig.make_binder(HungryServerConfig.new(), "user://hungry_config_bad.json")
	strict.strict = true
	_check(not strict.load_layers().ok, "strict: an unknown key is refused")
	DirAccess.remove_absolute("user://hungry_config_bad.json")
	var wrong := HungryServerConfig.new()
	wrong.outgrown = "nonsense"
	_check(not wrong.validate().ok, "an outgrown rule that does not exist is refused")
	HungryTuning.reset()


func _modes() -> void:
	HungryModes.reset()
	_check(HungryModes.result().ok, "the mode configs load at their defaults")
	var frenzy := HungryModes.preset_for(&"frenzy")
	_check(frenzy.food_target == 700 and frenzy.world_size == Vector2(3000.0, 3000.0) and frenzy.win_mass == 900.0, "the defaults are the code's presets")
	var binder: DotGameConfigBinder = HungryModes.binders[&"frenzy"]
	_check(binder.diff().is_empty(), "a mode has no diff at its defaults")
	var edit := binder.config.apply_dictionary({"food_target": 321, "world_width": 2500.0}, "test")
	_check(not edit.is_empty(), "the field takes an edit")
	var after := HungryModes.preset_for(&"frenzy")
	_check(after.food_target == 321 and after.world_size == Vector2(2500.0, 3000.0), "the next preset carries the edit")
	_check(HungryModes.preset_for(&"classic").food_target == HungryPreset_classic_food(), "another mode is untouched")
	_check(binder.profile_kind == "mode_frenzy" and binder.profile_id == "frenzy", "a mode is its own profile kind")
	HungryModes.reset()


func HungryPreset_classic_food() -> int:
	return preload("../game/hungry_preset.gd").classic().food_target


func _yml_round_trip() -> void:
	var dir := "res://cfg/game/game-hungario/config_play"
	var arena := "res://cfg/game/game-hungario/config_arena/game.yml"
	var kept_play := FileAccess.get_file_as_string(dir + "/game.yml")
	var kept_arena := FileAccess.get_file_as_string(arena)
	_write_res(dir + "/game.yml", "pepper_damage: 140\nfriendly_fire: false\n")
	_write_res(arena, "hunters_on: true\n")
	DirAccess.make_dir_recursive_absolute("res://cfg/game/game-hungario/mode_reef")
	var mode_yml := FileAccess.open("res://cfg/game/game-hungario/mode_reef/reef.yml", FileAccess.WRITE)
	mode_yml.store_string("food_target: 111\n")
	mode_yml.close()
	HungryTuning.reset()
	HungryModes.reset()
	var settings := HungryTuning.settings()
	_check(HungryTuning.result().ok and settings.pepper_damage == 140.0 and not settings.friendly_fire and settings.hunters_on,
		"exported cfg/game/<game>/config_<file>/game.yml files load back as defaults", "" if HungryTuning.result().ok else HungryTuning.result().error.message)
	_check(HungryTuning.binder.source_of("pepper_damage") == "yml", "and says which layer it came from")
	_check(HungryModes.preset_for(&"reef").food_target == 111, "a mode yml loads back as the preset")
	_write_res(dir + "/game.yml", "no_such_field: 1\n")
	HungryTuning.reset()
	HungryTuning.load_all()
	var strict_binder := HungryServerConfig.make_binder(HungryServerConfig.new())
	strict_binder.strict = true
	_check(not strict_binder.load_layers().ok, "strict: an unknown yml key is refused")
	_write_res(dir + "/game.yml", kept_play)
	_write_res(arena, kept_arena)
	DirAccess.remove_absolute("res://cfg/game/game-hungario/mode_reef/reef.yml")
	DirAccess.remove_absolute("res://cfg/game/game-hungario/mode_reef")
	HungryTuning.reset()
	HungryModes.reset()


func _write_res(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _workbench() -> void:
	HungryTuning.reset()
	var binder := HungryTuning.binder if HungryTuning.settings() != null else null
	var wb := DotGameWorkbench.new()
	wb.panel_mode = 1
	wb.config = {"enabled": false}
	for s: DotProfileSet in binder.profile_sets():
		wb.add_set(s, s.rel_path)
	add_child(wb)
	_check(wb.start().ok, "the workbench starts")
	binder.attach(wb.api.runtime)
	var keys := PackedStringArray()
	for e: Dictionary in binder.schema():
		keys.append(e["key"])
	var listed := PackedStringArray()
	for kind: String in wb.api.kinds():
		var lg: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "get", "kind": kind, "id": binder.profile_id})
		if lg.ok:
			listed.append_array(PackedStringArray((lg.value as Dictionary).get("values", {}).keys()))
	var missing := PackedStringArray()
	for k in keys:
		if not listed.has(k):
			missing.append(k)
	_check(missing.is_empty() and binder.profile_sets().size() == 3, "the workbench lists all %d keys over %d files" % [keys.size(), binder.profile_sets().size()], ",".join(missing))
	var res: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "set", "kind": "config_play", "id": binder.profile_id, "key": "frost_sec", "value": 9.0})
	_check(res.ok and HungryTuning.settings().frost_sec == 9.0, "a workbench edit reaches the live config", "" if res.ok else res.error.message)
	var files: Dictionary = wb.exporter.call("collect")
	var text: String = files.get("cfg/game/game-hungario/config_play/game.yml", "")
	_check(text.contains("frost_sec: 9"), "the export holds the edit in the cfg layout")
	wb.free()
	HungryTuning.reset()


func _write_root(rel: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join(rel).get_base_dir())
	var f := FileAccess.open(ROOT.path_join(rel), FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Child process: loads the layers strictly over the test root and prints what the live config holds.
func _probe() -> void:
	var config := HungryServerConfig.new()
	var binder := HungryServerConfig.make_binder(config)
	binder.strict = true
	binder.roots = PackedStringArray([ProjectSettings.globalize_path(ROOT)])
	var loaded := binder.load_layers()
	var console := DotConsole.new()
	add_child(console)
	binder.bind_cvars(console.cvar, DotConVar.FLAG_ARCHIVE, console.has_name)
	print("PROBE ok=%s frost=%s frost_src=%s pepper=%s pepper_src=%s cvar=%s maxp=%s maxp_src=%s fruit=%s fruit_src=%s" % [
		loaded.ok, config.frost_sec, binder.source_of("frost_sec"), config.pepper_damage, binder.source_of("pepper_damage"),
		console.find_cvar("hungry_pepper_damage").get_string(), config.max_players, binder.source_of("max_players"),
		config.fruit_effect_sec, binder.source_of("fruit_effect_sec")])
	get_tree().quit(0)


func _child() -> String:
	var out: Array = []
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://examples/headless_config.tscn", "--", "--probe", "--hungry-server-max-players=17", "--hungry-server-fruit-effect-sec=7.5"], out, true)
	return "".join(PackedStringArray(out))


## A value set in a cfg file, the environment and argv each reaches the live config, and later layers win.
func _layers() -> void:
	_write_root("game/%s/config_play/game.yml" % GAME, "frost_sec: 9.0\npepper_damage: 40.0\n")
	OS.set_environment("HUNGRY_SERVER_PEPPER_DAMAGE", "33.0")
	var text := _child()
	_check(text.contains("PROBE ok=true"), "the layers load strictly in a fresh process", text.right(300))
	_check(text.contains("frost=9") and text.contains("frost_src=yml"), "a cfg file reaches the live config")
	_check(text.contains("pepper=33") and text.contains("pepper_src=env") and text.contains("cvar=33"), "the environment beats the file and reaches the cvar")
	_check(text.contains("fruit=7.5") and text.contains("fruit_src=argv"), "argv alone reaches the config")
	_check(text.contains("maxp=17") and text.contains("maxp_src=argv"), "a second argv flag reaches it too")
	OS.unset_environment("HUNGRY_SERVER_PEPPER_DAMAGE")
	_write_root("game/%s/config_play/game.yml" % GAME, "max_players: 9\n")
	_check(_child().contains("PROBE ok=false"), "strict: a key in the wrong file is refused")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT.path_join("game/%s/config_play/game.yml" % GAME)))


## The shipped cfg files hold every key, in step with the config, and change nothing as they are.
func _templates() -> void:
	var files := HungryServerConfig.make_binder(HungryServerConfig.new()).template_files()
	_check(files.size() == 3, "three shipped cfg files", str(files.size()))
	var stale := PackedStringArray()
	for path: String in files:
		if not FileAccess.file_exists("res://" + path) or FileAccess.get_file_as_string("res://" + path) != files[path]:
			stale.append(path)
	_check(stale.is_empty(), "the shipped files match the config (run addons/dot_game/qa/dot_game_cfg_templates.gd)", ",".join(stale))
