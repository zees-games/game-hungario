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
	_seq_begin(path)


## Frame sequence after each still (DOT_SHOT_FRAMES, set by the .sh); see DotShotSeq. The state machine holds still while it records, and `_seq_end` defers the quit until it is done.
var _seq := DotShotSeq.new()
var _seq_active := false
var _seq_end := false


func _seq_begin(path: String) -> void:
	if _seq.enabled():
		_seq.begin(path)
		_seq_active = true



func _process(_delta: float) -> bool:
	if _seq_active:
		_seq_active = _seq.step(root)
		return false
	if _seq_end:
		return true
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
		_seq_end = true
		return false
	elif _frames > 1500:
		print("cover never lifted")
		_save("game.png")
		_seq_end = true
		return false
	return false
