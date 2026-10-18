extends SceneTree

const HungryConfig := preload("../game/hungry_config.gd")
const HungryMenus := preload("../game/client/hungry_menus.gd")
const HungrySettings := preload("../game/client/hungry_settings.gd")
const HungryWorld := preload("../game/hungry_world.gd")
const HungryPresentation := preload("../game/client/hungry_presentation.gd")
const HungrySound := preload("../game/client/hungry_sound.gd")

## Renders this game's own screens to `screenshots/` so a person can look at them.
##
## [b]This game had no screenshot tool at all[/b], and it is the one with the most screens:
## the Escape menu's pages (Loadout first), the help screen, the held scoreboard and the
## console. It is also where two of the family's table bugs were sitting — its browser and
## its HUD leaderboard both declared columns with no width, and a column with no width used
## to collapse to nothing, so the mass, the pieces, the rank and the ping had never been
## drawn.
##
## The menu is the real one: the presentation layer's [HungrySettings], over a memory store
## so nothing this draws is written to this machine's settings.
##
## Run through `tools/screenshot_menus.sh`. [b]Not `--headless`[/b]: that gives a null
## renderer, a 64 x 64 viewport, and every frame it saves is empty — which is worse than no
## screenshot because it looks like one.

const OUT_DIR := "res://screenshots"
const SETTLE := 3

var _world: HungryWorld = null
var _seeded := false
var _shots: Array[Dictionary] = []
var _presentation: HungryPresentation = null
var _menu: DotMenu = null
var _at := 0
var _wait := SETTLE
var _done := false


func _initialize() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	# A world with monsters of a spread of masses, through the real world rather than a
	# hand-built row list: a picture of a dictionary is a picture of a dictionary.
	var world := HungryWorld.new()
	world.is_authority = true
	world.register_service = false
	root.add_child(world)
	world.setup()

	_world = world

	_shots = [
		{"page": &"loadout", "file": "menu_loadout.png"},
		{"page": &"general", "file": "menu_general.png"},
		{"page": &"game", "file": "menu_game.png"},
		{"page": &"audio", "file": "menu_audio.png"},
		{"page": &"controls", "file": "menu_controls.png"},
		{"help": true, "file": "menu_help.png"},
		{"board": true, "file": "menu_scoreboard.png"},
		# The console, open: the kit's panel, on the layer it puts it on.
		{"console": true, "file": "console.png"},
	]


## The presentation layer, with its menu and console, built on the first frame rather than in
## `_initialize`, where nothing is in the tree yet.
func _build_presentation() -> void:
	_presentation = HungryPresentation.new()
	_presentation.name = "Presentation"
	_presentation.config = HungryConfig.new()
	_presentation.sound = HungrySound.make()
	_presentation.menu_settings = HungrySettings.new()
	_presentation.menu_settings.store = DotSettingsStoreMemory.new()
	_presentation.menu_settings.legacy_config_path = ""
	_presentation.menu_settings.legacy_bindings_path = ""
	root.add_child(_presentation.sound)
	root.add_child(_presentation)
	DotLog.result("screenshot", "the presentation", _presentation.setup())
	_menu = _presentation.menu_settings.menu
	if _menu != null:
		var _l := _menu.add_page(HungryMenus.loadout_page(null).page, &"general")


func _process(_delta: float) -> bool:
	if _done:
		return true

	# The monsters are added on the FIRST FRAME, not in `_initialize`.
	#
	# `HungryWorld.setup()` creates its `DotMatch` and adds it as a child, and a node added
	# from `SceneTree._initialize` does not get its `_ready` until the first frame -- so the
	# match's scoreboard does not exist yet and `add_player` dies on it. The error is
	# "Nonexistent function 'join' in base 'Nil'", which reads like a missing method rather
	# than like a node that has not started. It is written down because it is
	# easy to hit.
	if not _seeded:
		_seeded = true

		var names := [
			"gamemann", "a_very_long_display_name", "bo", "quiet_one", "newcomer",
		]

		for i in names.size():
			var added := _world.add_player(i + 1, names[i])

			if not added.ok:
				push_error("could not add %s: %s" % [names[i], added.error.message])

		_build_presentation()
		return false

	if _at >= _shots.size():
		_done = true
		return false

	var shot: Dictionary = _shots[_at]

	if _wait == SETTLE:
		_presentation.platform.board.call(&"close")
		if _menu != null:
			_menu.close_all()
		if _presentation.console.is_open():
			_presentation.console.close()

		if shot.has("console"):
			# `help` only: a setting typed here would be a setting.
			var _ran := _presentation.console.submit("help")
			var _opened := _presentation.console.open()
		elif shot.has("help"):
			_menu.open_help()
		elif shot.has("page"):
			_menu.open(StringName(shot["page"]))
		elif shot.has("board"):
			# The Tab board, as the platform holds it: dressed for this game, fed by the world.
			var board := _presentation.platform.board as DotMenuScoreboard
			HungryMenus.dress_board(board, _world, null)
			board.source = HungryMenus.solo_snapshot
			board.open()

	if _wait > 0:
		_wait -= 1
		return false

	var image := root.get_texture().get_image()
	var path := OUT_DIR.path_join(str(shot["file"]))
	image.save_png(path)
	print("wrote %s (%d x %d)" % [path, image.get_width(), image.get_height()])

	_at += 1
	_wait = SETTLE
	return false
