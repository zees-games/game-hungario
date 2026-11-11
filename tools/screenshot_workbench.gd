extends SceneTree

## Renders dot-workbench's F9 panel over the server settings and the modes, solo, to screenshots/workbench_panel.png.
## Through tools/screenshot_workbench.sh: a null renderer saves an empty image.

const OUT_DIR := "res://screenshots"

var _client: Node = null
var _frames := 0
var _opened := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed := load("res://game/client/hungry_client.tscn") as PackedScene
	_client = packed.instantiate()
	_client.set("force_offline", true)
	_client.set("offline_bots", 2)
	root.add_child(_client)


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
	if not _opened and _frames > 30 and platform.is_shown():
		var wb := _client.get_node_or_null("Workbench") as DotGameWorkbench
		print("workbench: ", wb != null and wb.overlay != null)
		if wb == null:
			return true
		wb.open()
		_opened = true
		_frames = 0
	elif _opened and _frames == 15:
		var path := ProjectSettings.globalize_path(OUT_DIR.path_join("workbench_panel.png"))
		print("saved %s: %s" % [path, error_string(root.get_texture().get_image().save_png(path))])
		_seq_begin(path)
		_seq_end = true
		return false
	return false
