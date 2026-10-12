extends RefCounted

## Drives the local monster for dot-audio's loudness capture (addons/dot_audio/tools/loudness.sh
## finds this file by name; run it with `-- --offline`, the main scene is the browser).
##
## [b]Why the stand-in is not enough here.[/b] It holds W and turns a mouse that steers
## nothing: every piece here steers toward the pointer's world point, the pointer under xvfb
## sits at the middle of the window, and the camera keeps the monster there, so the monster
## sat still and ate nothing. The recording was the bed alone (-26.1 LUFS) and no cue at all.
##
## So the pointer steers as a player does: at the nearest food, away from any monster big
## enough to eat this one, and round in a circle when there is nothing to choose; boost and a
## throw come in between, a split and an eject only with mass to spare. All of it goes
## through the capture's [code]point[/code] and [code]key[/code], which are a real pointer
## and real key events, so [code]HungryInput[/code] and the bindings read them as
## they read a player. Nothing here moves the monster.

var _client: Node = null
var _start_ms := 0
var _angle := 0.0
var _last := Vector2.INF
var _travelled := 0.0
var _mass_start := -1.0
var _mass_max := 0.0
var _mass_end := 0.0
var _splits := 0
var _ejects := 0
var _throws := 0
var _phase := -1
var _aim := Vector2.INF
var _aim_ms := 0


func drive(capture: SceneTree, ms: int) -> bool:
	if _client == null or not is_instance_valid(_client):
		_client = _find(capture.root)
		if _client == null:
			return false

	var world: Object = _client.get(&"world")
	if world == null:
		return true
	var monster: Object = world.call(&"monster_for", _client.call(&"_local_player"))
	if monster == null:
		return true

	if _start_ms == 0:
		_start_ms = ms
	var centre: Vector2 = monster.call(&"centre")
	var mass := float(monster.call(&"mass"))
	if _mass_start < 0.0:
		_mass_start = mass
	_mass_max = maxf(_mass_max, mass)
	_mass_end = mass
	if _last != Vector2.INF:
		_travelled += centre.distance_to(_last)
	_last = centre

	var dt := float(ms - _start_ms) / 1000.0
	var size := Vector2(capture.root.size)
	if ms - _aim_ms >= 250:
		_aim_ms = ms
		_aim = _choose(world, monster, centre, mass)
	var camera: Node2D = _client.get(&"camera")
	if _aim != Vector2.INF and camera != null and camera.is_inside_tree():
		var screen: Vector2 = camera.get_canvas_transform() * _aim
		var from_middle := (screen - size * 0.5).limit_length(minf(size.x, size.y) * 0.45)
		capture.call(&"point", size * 0.5 + from_middle)
	else:
		_angle += 0.012
		capture.call(&"point", size * 0.5 + Vector2.from_angle(_angle) * minf(size.x, size.y) * 0.33)

	# A second-by-second plan over a ten-second loop: boost, split, eject, throw.
	var t := fmod(dt, 10.0)
	capture.call(&"key", KEY_SHIFT, t >= 1.0 and t < 2.5)
	# Splitting and ejecting cost mass, so only a monster with mass to spare does either.
	var spare := mass > 80.0
	capture.call(&"key", KEY_SPACE, spare and t >= 4.0 and t < 4.1)
	capture.call(&"key", KEY_W, spare and t >= 6.0 and t < 6.3)
	capture.call(&"key", KEY_Q, t >= 8.0 and t < 8.1)
	var phase := int(t)
	if phase != _phase:
		_phase = phase
		match phase:
			4:
				_splits += 1 if spare else 0
			6:
				_ejects += 1 if spare else 0
			8:
				_throws += 1
	return true


func describe() -> String:
	var cues := "?"
	var presentation: Object = _client.get(&"presentation") if _client != null and is_instance_valid(_client) else null
	var audio: Object = presentation.get(&"audio") if presentation != null else null
	var sink: Object = audio.get(&"sink") if audio != null else null
	if sink != null and sink.has_method(&"played_ids"):
		var counts := {}
		for id: String in sink.call(&"played_ids"):
			counts[id] = int(counts.get(id, 0)) + 1
		cues = str(counts)
	return "local monster travelled %.0f units, mass %.0f -> %.0f (max %.0f), %d splits, %d ejects, %d throws; cues %s" % [
		_travelled, maxf(_mass_start, 0.0), _mass_end, _mass_max, _splits, _ejects, _throws, cues,
	]


## Where a player would steer: away from the nearest monster that could eat this one, else
## at the nearest food, as somebody playing it does.
func _choose(world: Object, me: Object, centre: Vector2, mass: float) -> Vector2:
	var threat := Vector2.INF
	var threat_d := 600.0
	for other: Object in world.call(&"monsters"):
		if other == me or float(other.call(&"mass")) < mass * 1.25:
			continue
		var d := centre.distance_to(other.call(&"centre"))
		if d < threat_d:
			threat_d = d
			threat = other.call(&"centre")
	if threat != Vector2.INF:
		return centre + (centre - threat).normalized() * 400.0
	var field: Object = world.get(&"field")
	if field == null:
		return Vector2.INF
	var best := Vector2.INF
	var best_d := INF
	for id: int in field.call(&"alive_ids"):
		var at: Vector2 = field.call(&"position_of", id)
		var d := centre.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = at
	return best


func _find(n: Node) -> Node:
	if n.get(&"world") != null and n.has_method(&"_local_player"):
		return n
	for child in n.get_children():
		var hit := _find(child)
		if hit != null:
			return hit
	return null
