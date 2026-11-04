@tool
extends Control

const HungryTouch := preload("hungry_touch.gd")

## The buttons a phone needs: split and throw, plus eject and boost, as a dot-ui [DotTouchButtons].
##
## [b]This game is nearly playable on a phone by accident.[/b] There is nothing to aim and
## nothing to select: a drag is the pointer, near is slow, far is fast, and
## [HungryInput] already treats a finger as one. What a touchscreen has no way to express
## is the two edge-triggered actions — splitting and throwing — and that is all this is.
##
## [b]Buttons, not a gesture.[/b] A double-tap to split would fight the drag that steers,
## and a two-finger tap is undiscoverable. Two large targets in the corners cost a little
## screen and are the only control here anybody has to be told about once.
##
## [DotTouchButtons] handles the touch in `_input`, so pressing a button does not also reach
## [method Node._unhandled_input] and drag the monster across the screen.

# No CHANNEL: buttons that emit signals; what they cause is logged where it happens.

const EDGE_MARGIN := 28.0

signal split_pressed()
signal throw_pressed()

## Whether the buttons are held right now. Read by [HungryInput] each tick.
var split_held: bool = false
var throw_held: bool = false
var eject_held: bool = false
var boost_held: bool = false

var buttons: DotTouchButtons = null

## What the throw button says it will throw. Set from the carry list.
var _carried: StringName = &""


## Whether this device wants them. `--touch` forces them on so the layout can be looked at on
## a desktop and a headless run can build and drive it.
static func wanted() -> bool:
	return DotPlatform.has_touch() or "--touch" in OS.get_cmdline_user_args()


static func make() -> HungryTouch:
	var touch := HungryTouch.new()
	touch.name = "Touch"
	touch.build()
	return touch


## Offsets are from the bottom-right corner (see [DotTouchButtons]). Placed to leave the leaderboard's text columns and the minimap clear. Throw is disabled
## (drawn as its label only) until something is carried.
static func layout(throw_label: String) -> Array[Dictionary]:
	return [
		{"id": &"split", "label": "SPLIT", "offset": Vector2(80, 80), "radius": 46.0},
		{"id": &"throw", "label": throw_label, "offset": Vector2(176, 52), "radius": 34.0},
		{"id": &"eject", "label": "EJECT", "offset": Vector2(120, 170), "radius": 30.0},
		{"id": &"boost", "label": "BOOST", "offset": Vector2(244, 52), "radius": 32.0},
	]


func build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Must not eat touches that are not on a button, or steering stops.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	buttons = DotTouchButtons.new()
	buttons.name = "Buttons"
	buttons.only_on_touch = false
	buttons.margin = EDGE_MARGIN
	buttons.set_anchors_preset(Control.PRESET_FULL_RECT)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.set_buttons(layout("THROW"))
	buttons.button_down.connect(_on_down)
	buttons.button_up.connect(_on_up)
	add_child(buttons)


## Whether a screen position is on a button, so steering can leave that touch alone.
func contains_point(screen_pos: Vector2) -> bool:
	return buttons != null and buttons.contains_point(screen_pos)


func _on_down(id: StringName) -> void:
	match id:
		&"split":
			split_held = true
			split_pressed.emit()
		&"throw":
			# Nothing to throw until something is picked up.
			if _carried == &"":
				return
			throw_held = true
			throw_pressed.emit()
		&"eject":
			eject_held = true
		&"boost":
			boost_held = true


func _on_up(id: StringName) -> void:
	match id:
		&"split":
			split_held = false
		&"throw":
			throw_held = false
		&"eject":
			eject_held = false
		&"boost":
			boost_held = false


## Keeps the throw button's label in step with what is being carried, because three items do
## very different things and a plain "Throw" gives no way to tell a lure from a pepper.
func show_carried(items: PackedStringArray) -> void:
	var next := StringName(items[0]) if not items.is_empty() else &""

	if next == _carried:
		return

	_carried = next

	if _carried == &"":
		throw_held = false

	if buttons != null:
		buttons.set_buttons(layout(throw_label()))


## What the throw button says.
func throw_label() -> String:
	return "THROW" if _carried == &"" else String(_carried).to_upper()


## True while something is carried and the throw button therefore acts.
func can_throw() -> bool:
	return _carried != &""


## Safe-area insets, so a button is not under a notch or a home indicator.
func apply_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var full := DisplayServer.window_get_size()

	if safe.size == Vector2i.ZERO or safe.size == full:
		return

	buttons.margin = EDGE_MARGIN + maxf(float(full.y - safe.end.y), float(full.x - safe.end.x))
	buttons.queue_redraw()


func describe() -> Dictionary:
	return {
		"split": split_held,
		"throw": throw_held,
		"eject": eject_held,
		"boost": boost_held,
		"carried": String(_carried),
	}
