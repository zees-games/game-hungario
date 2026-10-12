extends Node2D

## One eaten monster going down, in 2D: the last piece and its rider doing what the server's
## death reaction says (dot-player-char's [DotPlayerDeath] and [DotPlayerDeathReaction]),
## drawn the way the renderer draws a living piece. Built by [HungryFalls]; client only.
##
## [b]The 3D ragdoll does not apply, and its rule does.[/b] dot-player-char's bodies are rigid
## bodies under gravity, and this arena is seen from above with nothing to fall onto. What
## carries over is everything a viewer reads: which reaction (the server's pick, the same
## ids), which way (the push), how hard (the damage), the sounds and when they play, and that
## no frame of it calls [code]randf()[/code] (the seed is the death's, so every client draws
## the same fall). What does not carry over is the physics: each pose is a short scripted
## motion, sized by the piece's own radius because a crumb-sized monster and one that fills
## the screen must both read.
##
## By pose, so a reaction a game adds with a stock pose draws too:
##
## - [b]LIMP[/b]: the cell deflates and slides on along the push; the rider rolls off it.
## - [b]CRUMPLE[/b]: the cell folds in on itself where it was; the rider sinks into it.
## - [b]FACE_PLANT[/b]: the cell slams flat along the push, the smack on the slam; the rider
##   goes flat with it.
## - [b]LAUNCH[/b]: the cell bursts into pieces and the rider is thrown, rising toward the
##   viewer (drawn bigger, its shadow left behind) and coming down [member
##   DotPlayerDeathReaction.launch_along] further on: a headshot launch goes high and short,
##   a power launch long and flat, scattering the pieces along with it.
##
## The styles map the same way: STIFF moves the cell and rider as one disc (no folding, no
## pieces); TOPPLE, the `sv_ragdoll 0` fallback, shrinks it where it was with no motion at
## all; HIDE never builds one ([HungryFalls] hides the rider instead).

const CHANNEL := "hungry.fall"

## A dead body's sound: [code](id, where, volume)[/code].
signal sound(id: StringName, at: Vector2, volume: float)

## How long the motion itself takes. Short: an eaten cell is gone into its eater a tick
## later, and the arena has moved on.
const MOTION_SEC := 1.1

## How long the remains lie at most, whatever `sv_ragdoll_time` says. A 3D body lies on a
## floor nobody needs; a splat on this floor is under the next fight within seconds.
const REMAINS_MAX_SEC := 4.0

## The smallest radius a fall is sized from, so a crumb's death is still visible.
const MIN_RADIUS := 26.0

var reaction: DotPlayerDeathReaction = null
var death: DotPlayerDeath = null
var style: int = DotPlayerRagdollRules.Style.RAGDOLL
var player_id: int = 0

## Where the piece was, how big, and its colour.
var at: Vector2 = Vector2.ZERO
var radius: float = MIN_RADIUS
var colour: Color = Color.WHITE

## The rider the renderer drew on that piece, moved by this fall until the player is back.
var rider: Node2D = null

## Whether the player is alive again: the rider is the renderer's then. Set by [HungryFalls].
var alive_fn: Callable = Callable()

var force: float = 1.0
var lifetime: float = 3.0
var fade: float = 1.0

## Seconds since the death.
var age: float = 0.0

## Fading out: evicted, or past its time.
var expiring: bool = false

var _dir: Vector2 = Vector2.RIGHT
var _rng := RandomNumberGenerator.new()
var _bits: Array[Dictionary] = []
var _folds: PackedFloat32Array = PackedFloat32Array()
var _rider_spin: float = 0.0
var _rider_base: Vector2 = Vector2.ONE
var _landed: bool = false
var _fade_from: float = -1.0
var _fade_sec: float = 1.0
var _released: bool = false


## Sets the fall up. [param rules] are the ones in force on this client (the server's).
func start(rules: DotPlayerRagdollRules) -> void:
	_rng.seed = death.roll_seed if death != null else 0
	style = rules.effective_style() if rules != null else DotPlayerRagdollRules.Style.RAGDOLL
	force = rules.force_scale if rules != null else 1.0
	lifetime = minf(rules.lifetime if rules != null else REMAINS_MAX_SEC, REMAINS_MAX_SEC)
	fade = rules.fade if rules != null else 1.0
	radius = maxf(radius, MIN_RADIUS)
	position = Vector2.ZERO

	# The push, on the plane: a 2D world is dot-npc's XZ plane, so x is x and z is y. No
	# direction (a hunter's bite) is a direction from the seed, so it is still everybody's.
	var flat := Vector2(death.direction.x, death.direction.z) if death != null else Vector2.ZERO
	_dir = flat.normalized() if flat.length_squared() > 0.0001 else Vector2.RIGHT.rotated(_rng.randf() * TAU)

	_rider_spin = (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(0.8, 1.3)
	if rider != null:
		_rider_base = rider.scale

	_folds.resize(16)
	for i in range(_folds.size()):
		_folds[i] = _rng.randf_range(0.0, 1.0)

	if style == DotPlayerRagdollRules.Style.RAGDOLL and reaction != null \
			and reaction.pose == DotPlayerDeathReaction.Pose.LAUNCH:
		# The cell's pieces: thrown along the push, more of them the harder it was.
		var count := 6 + int(clampf(reaction.launch_along, 0.0, 9.0) * 0.45)
		for i in range(count):
			var out := Vector2.RIGHT.rotated(_rng.randf() * TAU)
			var speed := radius * force * _rng.randf_range(1.6, 3.0) * (0.45 + reaction.launch_along * 0.16)
			_bits.append({
				"pos": at + out * radius * 0.55,
				"vel": _dir.rotated(_rng.randf_range(-0.7, 0.7)) * speed + out * radius * force * 0.9,
				"r": radius * _rng.randf_range(0.11, 0.22),
			})

	if reaction != null and reaction.start_sound != &"" and style != DotPlayerRagdollRules.Style.TOPPLE:
		sound.emit.call_deferred(reaction.start_sound, at, 1.0)

	DotLog.debug(CHANNEL, "down", {
		"player": player_id, "reaction": String(reaction.id) if reaction != null else "-",
		"style": DotPlayerRagdollRules.style_name(style),
	})


## Fades out over [param seconds] from now: evicted to make room, or done.
func expire(seconds: float) -> void:
	if expiring:
		return
	expiring = true
	_fade_from = age
	_fade_sec = maxf(seconds, 0.05)


func _process(delta: float) -> void:
	advance(delta)


## One step of the fall. Public, so a suite can drive one without frames.
func advance(delta: float) -> void:
	age += delta
	if not expiring and age >= MOTION_SEC + lifetime:
		expire(fade)

	for bit in _bits:
		var damp := exp(-2.4 * delta)
		bit["vel"] = (bit["vel"] as Vector2) * damp
		bit["pos"] = (bit["pos"] as Vector2) + (bit["vel"] as Vector2) * delta

	var land_at := _land_time()
	if not _landed and age >= land_at:
		_landed = true
		if reaction != null and reaction.land_sound != &"":
			sound.emit(reaction.land_sound, _rider_point(), clampf(0.5 + (death.damage if death != null else 0.0) / 200.0, 0.5, 1.0))

	_drive_rider()
	queue_redraw()

	if expiring and age >= _fade_from + _fade_sec:
		_release_rider(true)
		queue_free()


## When the body is down: the moment its land sound plays.
func _land_time() -> float:
	if style == DotPlayerRagdollRules.Style.TOPPLE:
		return 0.3
	if style == DotPlayerRagdollRules.Style.STIFF or reaction == null:
		return 0.4
	match reaction.pose:
		DotPlayerDeathReaction.Pose.FACE_PLANT:
			return 0.22
		DotPlayerDeathReaction.Pose.CRUMPLE:
			return 0.55
		DotPlayerDeathReaction.Pose.LAUNCH:
			return _air_time()
	return 0.42


func _air_time() -> float:
	return 0.35 + (reaction.launch_up if reaction != null else 0.0) * 0.08


## 0 to 1 over [param seconds] from the death, eased out.
func _ease(seconds: float) -> float:
	var t := clampf(age / maxf(seconds, 0.001), 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 2.4)


## How opaque everything is: 1 until the fade, then down to 0.
func _alpha() -> float:
	if not expiring:
		return 1.0
	return clampf(1.0 - (age - _fade_from) / _fade_sec, 0.0, 1.0)


## How far the whole body slid along the push.
func _slide() -> float:
	var push := reaction.push if reaction != null else 1.0
	var hard := clampf((death.damage if death != null else 0.0) / 120.0, 0.3, 1.2)
	return radius * 0.45 * force * (0.6 + push * 0.4) * hard


func _launch_distance() -> float:
	if reaction == null:
		return 0.0
	return radius * force * (reaction.launch_along * 0.32 + reaction.hit_push * 0.08 + 0.4)


## Where the rider is now (and where its sound comes from).
func _rider_point() -> Vector2:
	if style == DotPlayerRagdollRules.Style.TOPPLE:
		return at
	if style == DotPlayerRagdollRules.Style.STIFF or reaction == null:
		return at + _dir * _slide() * _ease(0.5)
	match reaction.pose:
		DotPlayerDeathReaction.Pose.LIMP:
			return at + _dir * (_slide() + radius * 0.55) * _ease(0.5)
		DotPlayerDeathReaction.Pose.CRUMPLE:
			return at + _dir * radius * 0.1 * _ease(0.6)
		DotPlayerDeathReaction.Pose.FACE_PLANT:
			return at + _dir * radius * 0.35 * _ease(0.22)
		DotPlayerDeathReaction.Pose.LAUNCH:
			var u := clampf(age / _air_time(), 0.0, 1.0)
			var travelled := _launch_distance() * u + _slide() * 0.4 * _ease(_air_time() + 0.4) * float(age > _air_time())
			return at + _dir * travelled
	return at


## How high a launched rider is, 0 to 1: drawn as size, toward the viewer.
func _height() -> float:
	if style != DotPlayerRagdollRules.Style.RAGDOLL or reaction == null \
			or reaction.pose != DotPlayerDeathReaction.Pose.LAUNCH:
		return 0.0
	var u := clampf(age / _air_time(), 0.0, 1.0)
	return sin(u * PI) * clampf(reaction.launch_up / 6.5, 0.3, 1.2)


func _drive_rider() -> void:
	if rider == null or _released or not is_instance_valid(rider):
		return
	if alive_fn.is_valid() and bool(alive_fn.call(player_id)):
		# Back in the arena: the renderer draws them again.
		_release_rider(false)
		return

	var lie := _rider_spin * PI * 0.5
	var turn := 0.0
	var size := Vector2.ONE
	if style == DotPlayerRagdollRules.Style.TOPPLE:
		size = Vector2.ONE * lerpf(1.0, 0.6, _ease(0.3))
	elif style == DotPlayerRagdollRules.Style.STIFF or reaction == null:
		turn = lie * 0.6 * _ease(0.5)
		size = Vector2.ONE * lerpf(1.0, 0.85, _ease(0.5))
	else:
		match reaction.pose:
			DotPlayerDeathReaction.Pose.LIMP:
				turn = lie * _ease(0.5)
				size = Vector2.ONE * lerpf(1.0, 0.85, _ease(0.5))
			DotPlayerDeathReaction.Pose.CRUMPLE:
				turn = lie * 0.3 * _ease(0.7)
				size = Vector2.ONE * lerpf(1.0, 0.62, _ease(0.7))
			DotPlayerDeathReaction.Pose.FACE_PLANT:
				# Face down along the push: the rider's "up" turns to the push and flattens.
				turn = (_dir.angle() + PI * 0.5) * _ease(0.22)
				size = Vector2(lerpf(1.0, 1.2, _ease(0.22)), lerpf(1.0, 0.4, _ease(0.22)))
			DotPlayerDeathReaction.Pose.LAUNCH:
				var u := clampf(age / _air_time(), 0.0, 1.0)
				turn = _rider_spin * TAU * (0.6 + reaction.launch_up * 0.1) * (1.0 - pow(1.0 - u, 1.6))
				size = Vector2.ONE * (1.0 + _height() * 0.8) * lerpf(1.0, 0.85, u)

	rider.visible = true
	rider.position = _rider_point()
	rider.rotation = turn
	rider.scale = _rider_base * size
	rider.modulate = Color(1.0, 1.0, 1.0, _alpha())


## Gives the rider back: hidden while the player is still dead, untouched once they are back.
func _release_rider(hide: bool) -> void:
	if _released or rider == null or not is_instance_valid(rider):
		_released = true
		return
	_released = true
	rider.rotation = 0.0
	rider.scale = _rider_base
	rider.modulate = Color.WHITE
	if hide and not (alive_fn.is_valid() and bool(alive_fn.call(player_id))):
		rider.visible = false


func _draw() -> void:
	var a := _alpha()
	if a <= 0.0:
		return
	var body := Color(colour.r, colour.g, colour.b, colour.a * a)
	var rim := colour.darkened(0.45)
	rim.a *= a
	# The fade closes in on one point, as dot-player-char's does: the parts together.
	var closing := lerpf(1.0, 0.35, 1.0 - a) if expiring else 1.0

	if style == DotPlayerRagdollRules.Style.TOPPLE:
		_disc(at, radius * lerpf(1.0, 0.55, _ease(0.3)) * closing, body, rim, a)
		return
	if style == DotPlayerRagdollRules.Style.STIFF or reaction == null:
		_disc(at + _dir * _slide() * _ease(0.5), radius * lerpf(1.0, 0.8, _ease(0.5)) * closing, body, rim, a)
		return

	match reaction.pose:
		DotPlayerDeathReaction.Pose.LIMP:
			# Deflating: smaller, softer, slid on along the push.
			var r := radius * lerpf(1.0, 0.62, _ease(0.45)) * closing
			_disc(at + _dir * _slide() * _ease(0.5), r, body, rim, a)
		DotPlayerDeathReaction.Pose.CRUMPLE:
			_crumpled(at + _dir * radius * 0.1 * _ease(0.6), radius * lerpf(1.0, 0.55, _ease(0.7)) * closing, body, rim)
		DotPlayerDeathReaction.Pose.FACE_PLANT:
			_flattened(at + _dir * radius * 0.35 * _ease(0.22), radius * closing, body, rim)
		DotPlayerDeathReaction.Pose.LAUNCH:
			# The cell bursts: a ring going out, and its pieces thrown along the push.
			var pop := clampf(age / 0.3, 0.0, 1.0)
			if pop < 1.0:
				draw_arc(at, radius * (1.0 + pop * 0.8), 0.0, TAU, 48,
					Color(body.r, body.g, body.b, (1.0 - pop) * 0.7 * a), 4.0)
				_disc(at, radius * (1.0 - pop) * 0.9, body, rim, a)
			for bit in _bits:
				_disc(bit["pos"], float(bit["r"]) * lerpf(1.0, 0.6, _ease(1.0)) * closing, body, rim, a)
			# The thrown rider's shadow, left on the floor under where it is.
			var h := _height()
			if h > 0.02:
				draw_circle(_rider_point() + Vector2(h, h) * radius * 0.25,
					radius * 0.4, Color(0.10, 0.12, 0.30, 0.18 * a))


## A living piece's own look: corona, body, darker rim.
func _disc(centre: Vector2, r: float, body: Color, rim: Color, a: float) -> void:
	if r <= 0.5:
		return
	draw_circle(centre, r * 1.15, Color(body.r, body.g, body.b, 0.13 * a))
	draw_circle(centre, r, body)
	draw_arc(centre, r, 0.0, TAU, 40, rim, 2.0)


## Folded in on itself: the rim pulled in at the seed's folds.
func _crumpled(centre: Vector2, r: float, body: Color, rim: Color) -> void:
	var fold := _ease(0.7)
	var points := PackedVector2Array()
	for i in range(_folds.size()):
		var angle := TAU * float(i) / float(_folds.size()) + fold * 0.4
		var depth := 1.0 - _folds[i] * 0.38 * fold
		points.append(centre + Vector2.RIGHT.rotated(angle) * r * depth)
	draw_colored_polygon(points, body)
	points.append(points[0])
	draw_polyline(points, rim, 2.0)


## Slammed flat along the push: an ellipse long across it, short along it.
func _flattened(centre: Vector2, r: float, body: Color, rim: Color) -> void:
	var slam := _ease(0.22)
	var along := lerpf(1.0, 0.42, slam)
	var across := lerpf(1.0, 1.45, slam)
	var points := PackedVector2Array()
	var side := _dir.orthogonal()
	for i in range(32):
		var angle := TAU * float(i) / 32.0
		points.append(centre + _dir * cos(angle) * r * along + side * sin(angle) * r * across)
	draw_colored_polygon(points, body)
	points.append(points[0])
	draw_polyline(points, rim, 2.0)


func describe() -> Dictionary:
	return {
		"player": player_id,
		"reaction": String(reaction.id) if reaction != null else "-",
		"style": DotPlayerRagdollRules.style_name(style),
		"age": snappedf(age, 0.01),
		"pieces": _bits.size(),
		"landed": _landed,
		"expiring": expiring,
	}
