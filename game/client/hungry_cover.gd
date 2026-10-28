class_name HungryCover
extends DotLoadingCover

## The loading cover: the game's title and a tip over the arena's own sky and gold, with the
## stock status line and bar below. Handed to the platform as `cover`.

const TITLE := "Hungario"
const TIP := "Eat the small, split to catch, and stay out of the way of anything bigger."

const GOLD := Color(1.0, 0.70, 0.12)

var _title: Label = null
var _tip: Label = null


func _init() -> void:
	super()
	background = Color(0.16, 0.18, 0.40)
	text_color = Color(0.92, 0.94, 1.0)


func _build() -> void:
	_root = ColorRect.new()
	(_root as ColorRect).color = background
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(480, 0)
	box.add_theme_constant_override("separation", 14)
	_root.add_child(box)

	_title = _label(TITLE, 72, GOLD)
	_title.add_theme_color_override("font_outline_color", Color(0.20, 0.12, 0.02))
	_title.add_theme_constant_override("outline_size", 8)
	box.add_child(_title)

	_tip = _label(TIP, 16, text_color.darkened(0.15))
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_tip)

	_status = _label("", 20, text_color)
	box.add_child(_status)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(480, 8)
	_bar.show_percentage = false
	_bar.max_value = 100.0
	_bar.indeterminate = true
	box.add_child(_bar)


func title() -> String:
	return _title.text if _title != null else ""


func tip() -> String:
	return _tip.text if _tip != null else ""


func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label
