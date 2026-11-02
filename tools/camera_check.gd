extends Node

## The framing camera flown round the real offline game: the monster, whole and burst, put at the
## centre, edges and corners; every piece must be in view, inside the arena. Armed by a camera that
## does not follow. 2D: no walls to probe, no mp_forceview, no mp_solidplayers body.

const HungryCamera := preload("../game/client/hungry_camera.gd")
const HungryClient := preload("../game/client/hungry_client.gd")
const CLIENT_SCENE := preload("../game/client/hungry_client.tscn")
const HungryMonster := preload("../game/hungry_monster.gd")
const HungryPiece := preload("../game/hungry_piece.gd")

const STEPS := 90
const STEP_SEC := 0.05

var _client: HungryClient = null
var _built := false
var _failed := false
var _checks := 0


func _process(_delta: float) -> void:
	if _built:
		return
	_built = true
	DotLog.set_level(DotLog.Level.ERROR)
	_client = CLIENT_SCENE.instantiate() as HungryClient
	_client.force_offline = true
	_client.offline_bots = 0
	add_child(_client)
	_run.call_deferred()


func _run() -> void:
	for i in 10:
		await get_tree().process_frame
	_client.world.spawn(1)
	var monster := _client.world.monster_for(1)
	_check(monster != null and _client.camera != null, "the offline game has a monster and a camera")
	if monster != null and _client.camera != null:
		_fly(monster, _client.camera, false)
		_fly(monster, _client.camera, true)
		_spectate(monster, _client.camera)
		_still_camera_loses(monster)
	print("%d checks, %s" % [_checks, "FAILED" if _failed else "all passed"])
	get_tree().quit(1 if _failed else 0)


func _places(bounds: Rect2, inset: float) -> Array[Vector2]:
	var box := bounds.grow(-inset)
	var out: Array[Vector2] = [bounds.get_center()]
	for x in [box.position.x, bounds.get_center().x, box.end.x]:
		for y in [box.position.y, bounds.get_center().y, box.end.y]:
			out.append(Vector2(x, y))
	return out


## Puts the monster at each place, runs the camera, and counts the frames a piece is out of view.
## [param burst] adds a second piece a long way off, so the camera must frame the spread.
func _fly(monster: HungryMonster, camera: HungryCamera, burst: bool) -> void:
	camera.position_source = Callable()
	var arena_bounds := _client.world.arena.bounds
	var hull := monster.pieces[0].radius()
	var extra: HungryPiece = null
	if burst:
		extra = HungryPiece.make(9001, 1, Vector2.ZERO, monster.pieces[0].mass() * 0.2, _client.world.tunables.mass_rules, 0)
		monster.add_piece(extra)
	var gap := arena_bounds.size.x * 0.12
	var out_of_view := 0
	var outside_arena := 0
	var worst_zoom := camera.zoom.x
	for at in _places(arena_bounds, hull + 2.0):
		_put(monster, at, extra, gap)
		for step in STEPS:
			camera._process(STEP_SEC)
		for piece in monster.pieces:
			var circle := Rect2(piece.position() - Vector2.ONE * piece.radius(), Vector2.ONE * piece.radius() * 2.0)
			if not camera.visible_rect().encloses(circle):
				out_of_view += 1
		var view := camera.visible_rect()
		if view.size.x <= arena_bounds.size.x and view.size.y <= arena_bounds.size.y and not arena_bounds.grow(0.5).encloses(view):
			outside_arena += 1
		worst_zoom = minf(worst_zoom, camera.zoom.x)
	var label := "burst" if burst else "whole"
	_check(out_of_view == 0, "%s monster, every piece in view at %d places (%d out of view; hull %.0f, gap %.0f)" % [label, _places(arena_bounds, hull + 2.0).size(), out_of_view, hull, gap])
	_check(outside_arena == 0, "%s monster, the view stays inside the arena (%d places outside)" % [label, outside_arena])
	_check(worst_zoom >= camera.min_zoom - 0.0001 and camera.zoom.x <= camera.max_zoom + 0.0001, "%s monster, zoom within [%.2f, %.2f] (smallest %.3f)" % [label, camera.min_zoom, camera.max_zoom, worst_zoom])
	if extra != null:
		monster.remove_piece(extra.id)


func _put(monster: HungryMonster, at: Vector2, extra: HungryPiece, gap: float) -> void:
	var main: HungryPiece = monster.pieces[0]
	main.state.position = at
	main.drawn_from = at
	main.drawn_two_back = at
	if extra != null:
		var bounds := _client.world.arena.bounds
		var spot := at + Vector2(gap if at.x < bounds.get_center().x else -gap, 0.0)
		extra.state.position = spot
		extra.drawn_from = spot
		extra.drawn_two_back = spot


## A dead player's camera frames the point it is handed, wherever it is.
func _spectate(monster: HungryMonster, camera: HungryCamera) -> void:
	var bounds := _client.world.arena.bounds
	var missed := 0
	var was_alive := monster.alive
	monster.alive = false
	for at in _places(bounds, 1.0):
		camera.position_source = func() -> Variant: return at
		for step in STEPS:
			camera._process(STEP_SEC)
		if not camera.visible_rect().grow(1.0).has_point(at):
			missed += 1
	monster.alive = was_alive
	camera.position_source = Callable()
	_check(missed == 0, "spectating a point at the centre, edges and corners keeps it in view (%d missed)" % missed)


## Armed: a camera that never moves must lose the monster at the arena's edges, or the flight above proves nothing.
func _still_camera_loses(monster: HungryMonster) -> void:
	var bounds := _client.world.arena.bounds
	var still := Rect2(bounds.get_center() - get_viewport().get_visible_rect().size * 0.5, get_viewport().get_visible_rect().size)
	var lost := 0
	for at in _places(bounds, monster.pieces[0].radius() + 2.0):
		if not still.has_point(at):
			lost += 1
	_check(lost > 0, "armed: a camera that does not follow loses the monster at %d places" % lost)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed = true
