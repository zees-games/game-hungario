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


func _process(_delta: float) -> bool:
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
		return true
	return false
