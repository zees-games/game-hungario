extends SceneTree

## Renders the loading cover the platform (DotGameClient) puts up, then the game once it lifts.
## Through tools/screenshot_cover.sh: a null renderer saves an empty image.

const OUT_DIR := "res://screenshots"

var _client: Node = null
var _frames := 0
var _stage := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed := load("res://game/client/hungry_client.tscn") as PackedScene
	_client = packed.instantiate()
	_client.set("force_offline", true)
	_client.set("offline_bots", 4)
	root.add_child(_client)


func _save(name: String) -> void:
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(name))
	var err := root.get_texture().get_image().save_png(path)
	print("saved %s: %s" % [path, error_string(err)])


func _process(_delta: float) -> bool:
	_frames += 1
	var platform: DotGameClient = _client.get("platform")
	if _stage == 0 and _frames == 2:
		print("cover %s" % ("lifted" if platform.is_shown() else "up"))
		_save("cover.png")
		_stage = 1
	elif _stage == 1 and platform.is_shown():
		_stage = 2
		_frames = 0
	elif _stage == 2 and _frames == 90:
		_save("game.png")
		return true
	elif _frames > 1500:
		print("cover never lifted")
		_save("game.png")
		return true
	return false
