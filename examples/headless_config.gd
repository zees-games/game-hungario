extends Node

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
const CHECKS := 41

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _check(ok: bool, what: String, detail := "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what + (" | " + detail if detail != "" else ""))


func _run() -> void:
	print("game-hungario: config binder")
	_server_config()
	_modes()
	_yml_round_trip()
	_workbench()
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
	var strict := DotGameConfigBinder.create(HungryServerConfig.new(), "game-hungario", "hungry", "user://hungry_config_bad.json")
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
	var dir := "res://cfg/game/game-hungario/config"
	DirAccess.make_dir_recursive_absolute(dir)
	var yml := FileAccess.open(dir + "/game.yml", FileAccess.WRITE)
	yml.store_string("pepper_damage: 140\nfriendly_fire: false\nhunters_on: true\n")
	yml.close()
	DirAccess.make_dir_recursive_absolute("res://cfg/game/game-hungario/mode_reef")
	var mode_yml := FileAccess.open("res://cfg/game/game-hungario/mode_reef/reef.yml", FileAccess.WRITE)
	mode_yml.store_string("food_target: 111\n")
	mode_yml.close()
	HungryTuning.reset()
	HungryModes.reset()
	var settings := HungryTuning.settings()
	_check(HungryTuning.result().ok and settings.pepper_damage == 140.0 and not settings.friendly_fire and settings.hunters_on,
		"an exported cfg/game/<game>/config/game.yml loads back as defaults", "" if HungryTuning.result().ok else HungryTuning.result().error.message)
	_check(HungryTuning.binder.source_of("pepper_damage") == "yml", "and says which layer it came from")
	_check(HungryModes.preset_for(&"reef").food_target == 111, "a mode yml loads back as the preset")
	var bad := FileAccess.open(dir + "/game.yml", FileAccess.WRITE)
	bad.store_string("no_such_field: 1\n")
	bad.close()
	HungryTuning.reset()
	HungryTuning.load_all()
	var strict_binder := DotGameConfigBinder.create(HungryServerConfig.new(), "game-hungario", "hungry")
	strict_binder.strict = true
	_check(not strict_binder.load_layers().ok, "strict: an unknown yml key is refused")
	DirAccess.remove_absolute(dir + "/game.yml")
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute("res://cfg/game/game-hungario/mode_reef/reef.yml")
	DirAccess.remove_absolute("res://cfg/game/game-hungario/mode_reef")
	HungryTuning.reset()
	HungryModes.reset()


func _workbench() -> void:
	HungryTuning.reset()
	var binder := HungryTuning.binder if HungryTuning.settings() != null else null
	var wb := DotGameWorkbench.new()
	wb.panel_mode = 1
	wb.config = {"enabled": false}
	wb.add_set(binder.profile_set(), "Server settings")
	add_child(wb)
	_check(wb.start().ok, "the workbench starts")
	binder.attach(wb.api.runtime)
	var set: DotProfileSet = binder.profile_set()
	var res: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "set", "kind": set.rel_path, "id": binder.profile_id, "key": "frost_sec", "value": 9.0})
	_check(res.ok and HungryTuning.settings().frost_sec == 9.0, "a workbench edit reaches the live config")
	var files: Dictionary = wb.exporter.call("collect")
	var text: String = files.get("cfg/game/game-hungario/config/game.yml", "")
	_check(text.contains("frost_sec: 9"), "the export holds the edit in the cfg layout")
	wb.free()
	HungryTuning.reset()
