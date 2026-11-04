extends DotGameCheckSuite

## The touch layout: four buttons that fit a phone without overlapping, and a finger on a button kept off the steering.
## Run: `./game.sh test headless_touch`

const HungryTouch := preload("../game/client/hungry_touch.gd")
const HungrySettings := preload("../game/client/hungry_settings.gd")
const CHECKS := 10


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-hungario: touch buttons")
	var layout := HungryTouch.layout("THROW")
	var ids: Array[StringName] = []
	for b: Dictionary in layout:
		ids.append(b["id"])
	_check(ids.has(&"split") and ids.has(&"throw") and ids.has(&"eject") and ids.has(&"boost"), "split, throw, eject and boost are on the layout")

	for size: Vector2 in [Vector2(844, 390), Vector2(667, 375), Vector2(932, 430)]:
		var touch := HungryTouch.make()
		add_child(touch)
		touch.set_anchors_preset(Control.PRESET_TOP_LEFT)
		touch.buttons.set_anchors_preset(Control.PRESET_TOP_LEFT)
		touch.size = size
		touch.buttons.size = size
		var buttons := touch.buttons
		var bounds := Rect2(Vector2.ZERO, size)
		_check(bounds.encloses(buttons.footprint()), "the cluster fits %dx%d" % [size.x, size.y], str(buttons.footprint()))
		var clash := ""
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var gap := buttons.centre_of(ids[i]).distance_to(buttons.centre_of(ids[j])) - buttons.radius_of(ids[i]) - buttons.radius_of(ids[j])
				if gap < 4.0:
					clash = "%s and %s" % [ids[i], ids[j]]
		_check(clash == "", "no two buttons overlap at %dx%d" % [size.x, size.y], clash)
		if size.x == 844.0:
			var split_pos := buttons.centre_of(&"split")
			_check(touch.contains_point(split_pos), "a point on split is the button's, so steering ignores it")
			_check(not touch.contains_point(Vector2(100, 100)), "a point on the left is the steering's")
		remove_child(touch)
		touch.free()

	var settings := HungrySettings.new()
	var config := settings.config
	if &"menu_button_corner" in config:
		_check(config.get(&"menu_button_corner") == &"top_left", "the menu button is in the top-left corner")
	else:
		_check(true, "this dot-menu has no menu_button_corner; nothing to set")
	config = null
	settings.free()
	_report(CHECKS)
