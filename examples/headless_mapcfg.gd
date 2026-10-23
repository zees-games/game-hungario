extends Node

const HungryMapConfig := preload("../game/hungry_map_config.gd")

## A mode's map file sets its rule cvars and the next mode puts them back. The files are written
## to a temporary config root, because the shipped starter is all comments.
##
## [codeblock]
## godot --headless --path . res://examples/headless_mapcfg.tscn
## [/codeblock]

const CHECKS := 8

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-hungario: per-map cvars from cfg/game/game-hungario/dot_map/map")
	if not ResourceLoader.exists("res://addons/dot_map/config/dot_map_config.gd"):
		print("SKIPPED: dot-map is not linked at addons/dot_map")
		get_tree().quit(0)
		return
	var root := ProjectSettings.globalize_path("user://mapcfg_test")
	var dir := root.path_join("cfg/game/%s/dot_map/map" % HungryMapConfig.GAME_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("warrens.yml"), "hungry_hazards_count: 6\nhungry_warrens_corners: quartered\nhungry_hunters_on: 1\nbot_quota: 99\n")

	var console := DotConsole.new()
	add_child(console)
	console.cvar("hungry_hazards_count", "0", "", DotConVar.FLAG_ARCHIVE)
	console.cvar("hungry_warrens_corners", "", "", DotConVar.FLAG_ARCHIVE)
	console.cvar("hungry_hunters_on", "0", "", DotConVar.FLAG_ARCHIVE)
	console.cvar("bot_quota", "6", "", DotConVar.FLAG_ARCHIVE)
	var cfg := HungryMapConfig.build(console)
	cfg.config_dir = root.path_join("cfg")

	var got := cfg.apply("warrens")
	_check(got.size() == 3, "warrens applies its three whitelisted keys (%s)" % [got])
	_check(console.find_cvar("hungry_hazards_count").get_int() == 6, "hazards count is 6 on warrens")
	_check(console.find_cvar("hungry_warrens_corners").get_string() == "quartered", "corners are quartered on warrens")
	_check(console.find_cvar("hungry_hunters_on").get_int() == 1, "hunters are on in warrens")
	_check(console.find_cvar("bot_quota").get_int() == 6, "a cvar outside the whitelist is refused")

	cfg.apply("frenzy")
	_check(console.find_cvar("hungry_hazards_count").get_int() == 0, "the next mode has the hazards count back")
	_check(console.find_cvar("hungry_warrens_corners").get_string() == "", "and the corners")
	_check(cfg.applied().is_empty(), "a mode without a file applies nothing")

	DirAccess.remove_absolute(dir.path_join("warrens.yml"))
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what)
		print("  FAIL  %s" % what)
