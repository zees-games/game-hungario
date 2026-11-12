extends SceneTree

## The real offline client on a phone-sized window with the touch layout, saved to screenshots/touch.png.
## Run through `tools/screenshot_touch.sh`.

var _frames := 0


func _initialize() -> void:
	DotPlatform.touch_override = 1
	root.add_child((load("res://examples/play.tscn") as PackedScene).instantiate())


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
	if _frames < 400:
		return false
	var shot := _save_shot  # one-shot, held as a Callable so it is not part of the per-frame path
	shot.call()
	_seq_end = true
	return false


func _save_shot() -> void:
	DirAccess.make_dir_recursive_absolute("res://screenshots")
	var path := ProjectSettings.globalize_path("res://screenshots/touch.png")
	var err := root.get_texture().get_image().save_png(path)
	for b in root.find_children("Buttons", "Control", true, false):
		print("path=%s margin=%s centre=%s gpos=%s" % [b.get_path(), b.get("margin"), b.call("centre_of", &"split"), b.global_position])
		print("buttons visible=%s scale=%s footprint=%s size=%s" % [b.is_visible_in_tree(), b.get("button_scale"), b.call("footprint"), b.size])
	print("saved %s (%s) window %s" % [path, error_string(err), root.size])
	_seq_begin(path)
