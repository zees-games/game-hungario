extends SceneTree

## The real offline client on a phone-sized window with the touch layout, saved to screenshots/touch.png.
## Run through `tools/screenshot_touch.sh`.

var _frames := 0


func _initialize() -> void:
	DotPlatform.touch_override = 1
	root.add_child((load("res://examples/play.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 400:
		return false
	DirAccess.make_dir_recursive_absolute("res://screenshots")
	var path := ProjectSettings.globalize_path("res://screenshots/touch.png")
	var err := root.get_texture().get_image().save_png(path)
	for b in root.find_children("Buttons", "Control", true, false):
		print("path=%s margin=%s centre=%s gpos=%s" % [b.get_path(), b.get("margin"), b.call("centre_of", &"split"), b.global_position])
		print("buttons visible=%s scale=%s footprint=%s size=%s" % [b.is_visible_in_tree(), b.get("button_scale"), b.call("footprint"), b.size])
	print("saved %s (%s) window %s" % [path, error_string(err), root.size])
	return true
