extends GSGameVisualQaCapture

## Hungario's visual QA capture (the loop is gs-game's docs/visual-qa.md). Hungario is a 2D game, so the three views are
## three 2D cameras over the real renderer, not a person with a first-person camera and two outside ones. Every frame of
## every clip is saved at --fps in three views (the file prefixes are the harness's):
##   f  the player's own view: the game's real camera (HungryCamera, zoom following the monster's size), the window.
##   t  a teammate's view: the same world a few times wider, so the subject reads as it does on a crowded screen.
##   o  a rival's close look: the subject large and centred, to judge the rider's art, outline, tint and any trail or hat.
## Two kinds of item:
##   rider_<look>   a monster wearing one of the avatar looks (the guest riders, and two dressed in every slot), through the
##                  real HungryRenderer and HungryRider: idle, move (the monster steering a circle), grow (fed to a big
##                  monster, the rider resizing), split (a burst into pieces).
##   hunter_<kind>  one NPC hunter as the renderer draws it, idle and rolling about, beside a big rival monster so the
##                  prey and threat rings are checked too.
## A hazard has no animation of its own and is drawn by the same renderer; tools/screenshot_map.sh covers it.
## There is no skeleton in a 2D game: the T-pose, foot slide and floor rows report as skipped, and the verdict is the eye's.
## Renders, so it runs on a GPU box or under xvfb, never in the headless suites.

const HungryCamera := preload("../game/client/hungry_camera.gd")
const HungryContent := preload("../game/hungry_content.gd")
const HungryHunters := preload("../game/hungry_hunters.gd")
const HungryPreset := preload("../game/hungry_preset.gd")
const HungryRenderer := preload("../game/client/hungry_renderer.gd")
const HungryWorld := preload("../game/hungry_world.gd")

const PLAYER := 1
const RIVAL := 2
const RIDER_CLIPS: PackedStringArray = ["idle", "move", "grow", "split"]
const HUNTER_CLIPS: PackedStringArray = ["idle", "roll"]
const SECONDS := {"idle": 2.0, "move": 3.0, "grow": 3.0, "split": 2.5, "roll": 3.0}
## The teammate view shows this much more of the world than the player's own; the rival view is zoomed in this much.
const WIDE_FACTOR := 0.4
const CLOSE_FACTOR := 3.0
const MODE := &"classic"

## A look is an avatar built from the schema: [body part, hat part or "", trail part or "", colour id, trim colour].
const LOOKS := {
	"guest_odd": [&"rider_blob", &"", &"", 3, Color.WHITE],
	"guest_even": [&"rider_pip", &"", &"", 2, Color.WHITE],
	"spike_crown_ember": [&"rider_spike", &"hat_crown", &"trail_ember", 5, Color(1.0, 0.85, 0.2)],
	"blob_cap_dust": [&"rider_blob", &"hat_cap", &"trail_dust", 7, Color(0.1, 0.1, 0.2)],
}

var _world: HungryWorld = null
var _renderer: HungryRenderer = null
var _camera: HungryCamera = null
var _hunters: HungryHunters = null
var _shown_kind := ""
var _shown_item := ""
var _views_2d: Views2D = null
var _hunter_at := Vector2.ZERO
var _split_done := false


## The three views as 2D cameras of the game's own canvas (GSGameVisualQaViews is the 3D pair).
class Views2D extends GSGameVisualQaViews:
	var wide_view: SubViewport = null
	var wide_camera: Camera2D = null
	var close_view: SubViewport = null
	var close_camera: Camera2D = null

	## The harness calls this with the 3D world; the 2D views draw the root's canvas instead.
	func setup(host: Node, _world: World3D, _environment: Environment = null) -> void:
		var world := host.get_viewport().world_2d
		wide_view = _view_2d(host, world)
		wide_camera = wide_view.get_child(0) as Camera2D
		close_view = _view_2d(host, world)
		close_camera = close_view.get_child(0) as Camera2D

	func look_2d(at: Vector2, base_zoom: float, wide: float, close: float) -> void:
		wide_camera.global_position = at
		wide_camera.zoom = Vector2.ONE * base_zoom * wide
		close_camera.global_position = at
		close_camera.zoom = Vector2.ONE * base_zoom * close

	func save(dir: String, index: int, first_person: Viewport) -> GSResult:
		var shots := {"f": first_person, "t": wide_view, "o": close_view}
		for prefix: String in shots:
			var path := "%s/%s_%03d.jpg" % [dir, prefix, index]
			var err := (shots[prefix] as Viewport).get_texture().get_image().save_jpg(path, jpg_quality)
			if err != OK:
				return GSResult.fail(GSError.CODE_IO, "visual QA frame not saved", "%s: %s" % [path, error_string(err)])
		return GSResult.success(index)

	func _view_2d(host: Node, world: World2D) -> SubViewport:
		var view := SubViewport.new()
		view.size = size
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.world_2d = world
		host.add_child(view)
		var cam := Camera2D.new()
		view.add_child(cam)
		cam.make_current()
		return view


func _items() -> PackedStringArray:
	var items := PackedStringArray()
	for look: String in LOOKS:
		items.append("rider_" + look)
	for id in HungryHunters.wire_ids():
		items.append("hunter_" + id)
	return items


func _clips(item: String) -> PackedStringArray:
	return RIDER_CLIPS if item.begins_with("rider_") else HUNTER_CLIPS


func _seconds(_item: String, clip: String) -> float:
	return float(SECONDS.get(clip, 2.0))


func _warmup_frames(_item: String, _clip: String) -> int:
	return 4


## No 3D stage: the world, the renderer and the camera are built per item in [method _stage].
func _build() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_views_2d = Views2D.new()
	views = _views_2d


func _stage(item: String, clip: String) -> GSResult:
	_teardown()
	_world = HungryWorld.new()
	_world.name = "World"
	_world.preset = HungryPreset.for_id(MODE)
	_world.register_service = false
	_world.world_seed = 20260913
	root.add_child(_world)
	var built := _world.setup()
	if not built.ok:
		return built
	_world.start(0)
	_world.add_player(PLAYER, "Subject")
	for _i in range(_world.tick_rate * 5):
		if _world.match_node.is_live():
			break
		_world.tick({})
	var spot := Vector2(0.0, _world.arena.bounds.size.y * 0.36)
	_world.spawn(PLAYER, spot)
	_world.tick({})
	_split_done = false
	_shown_item = item
	_shown_kind = "rider" if item.begins_with("rider_") else "hunter"
	_camera = HungryCamera.framing(func() -> Object: return _world.monster_for(PLAYER), _world.arena)
	_camera.zoom_sec = 0.0
	_camera.follow_sec = 0.0
	root.add_child(_camera)
	_camera.make_current()
	_renderer = HungryRenderer.new()
	_renderer.name = "Renderer"
	root.add_child(_renderer)
	_renderer.bind(_world, _camera, PLAYER)
	if _shown_kind == "rider":
		return _stage_rider(item.trim_prefix("rider_"), clip)
	return _stage_hunter(item.trim_prefix("hunter_"), clip, spot)


func _stage_rider(look: String, clip: String) -> GSResult:
	var recipe: Array = LOOKS[look]
	var avatar := GSAvatar.make(&"hungry_rider")
	avatar.set_part(&"body", recipe[0])
	if recipe[1] != &"":
		avatar.set_part(&"hat", recipe[1])
	if recipe[2] != &"":
		avatar.set_part(&"trail", recipe[2])
	avatar.set_colour(&"body", 0, HungryContent.colour_for(int(recipe[3])))
	avatar.set_colour(&"body", 1, recipe[4])
	_world.monster_for(PLAYER).avatar = avatar
	if clip == "split":
		_world.feed_player(PLAYER, 60.0)
	return GSResult.success(clip)


func _stage_hunter(kind: String, clip: String, spot: Vector2) -> GSResult:
	if HungryHunters.mass_of(StringName(kind)) <= 0.0:
		return GSResult.fail(GSError.CODE_INVALID, "hunter %s has no mass" % kind)
	# The player's monster is the small one: the hunter is drawn beside it with a ring, and a big rival stands behind.
	_hunters = HungryHunters.new()
	_hunters.name = "Hunters"
	root.add_child(_hunters)
	_renderer.hunters = _hunters
	_hunter_at = spot + Vector2(150.0, 0.0)
	_adopt_hunter(kind, _hunter_at)
	_world.add_player(RIVAL, "Rival")
	_world.spawn(RIVAL, spot + Vector2(-220.0, 60.0))
	_world.feed_player(RIVAL, 400.0)
	_world.tick({})
	return GSResult.success(clip)


func _adopt_hunter(kind: String, at: Vector2) -> void:
	var id := StringName(kind)
	_hunters.adopt(1, id, at, HungryHunters.radius_of(id), true)


func _teardown() -> void:
	for node: Node in [_renderer, _camera, _hunters, _world]:
		if node != null and is_instance_valid(node):
			root.remove_child(node)
			node.free()
	_renderer = null
	_camera = null
	_hunters = null
	_world = null


func _drive(_item: String, clip: String, t: float, _frame: int) -> void:
	if _shown_kind == "rider":
		_drive_rider(clip, t)
	else:
		_drive_hunter(clip, t)
	_renderer.queue_redraw()


func _drive_rider(clip: String, t: float) -> void:
	var command := GS2DCommand.new()
	match clip:
		"move":
			command.aim = Vector2.from_angle(t * 1.6)
			command.reach = 600.0
		"grow":
			# Fed a little every frame: the radius, the rider's size and the camera zoom all change smoothly.
			_world.feed_player(PLAYER, _world.preset.win_mass * 0.5 / (float(SECONDS["grow"]) * float(fps)))
		"split":
			command.aim = Vector2.RIGHT
			command.reach = 400.0
			if t >= 0.4 and not _split_done:
				_split_done = true
				command.set_button(GS2DCommand.BUTTON_SPLIT, true)
	_world.tick({PLAYER: command})


func _drive_hunter(clip: String, t: float) -> void:
	_world.tick({})
	if clip == "roll":
		var kind := _shown_item.trim_prefix("hunter_")
		_adopt_hunter(kind, _hunter_at + Vector2.from_angle(t * 2.0) * 90.0)


## The player's own camera is the game's: it follows the monster at the monster's zoom. The other two read from it.
func _place_first_person(_item: String) -> void:
	var monster := _world.monster_for(PLAYER)
	if monster == null:
		return
	var at := monster.centre()
	_camera.global_position = at
	_views_2d.look_2d(at, _camera.zoom.x, WIDE_FACTOR, CLOSE_FACTOR)
