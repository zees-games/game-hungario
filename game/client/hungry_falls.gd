extends Node2D

const HungryFall := preload("hungry_fall.gd")
const HungryPiece := preload("../hungry_piece.gd")

## Where this client's eaten monsters go down: the 2D counterpart of dot-player-char's
## [DotPlayerRagdolls]. It remembers the last piece each player lost (the eaten one is gone
## from the world before the death is announced), builds a [HungryFall] from it when the death
## arrives, keeps no more than the cap, and passes the sounds on.
##
## The renderer's first child, so a fall draws over the arena and under every rider.
##
## [b]The server picks, every client draws[/b], exactly as in 3D: the reaction and its seed
## come with the death (`HungryWorld.decide_death`, on DIED), and nothing here calls
## [code]randf()[/code]. A client that never saw the piece (out of its interest range) draws
## nothing, which is right: it was off this client's screen.

const CHANNEL := "hungry.fall"

## How long a lost piece is remembered for a death that has not arrived yet. DESPAWN and DIED
## leave the server in the same tick, in that order, on one reliable channel.
const REMEMBER_MSEC := 2000

## How long an evicted fall takes to fade.
const EVICT_FADE := 0.3

## A body's sound: [code](id, where, volume)[/code].
signal sound(id: StringName, at: Vector2, volume: float)

var rules: DotPlayerRagdollRules = DotPlayerRagdollRules.new()

## The reactions a death's id is looked up in; only the poses and sounds matter here.
var reactions: DotPlayerDeathReactions = DotPlayerDeathReactions.stock()

## This machine's own limit, or -1 for dot-player-char's default.
var local_cap: int = -1

## [code]rider_fn.call(player_id) -> Node2D[/code]: the rider the renderer drew for them.
var rider_fn: Callable = Callable()

## [code]alive_fn.call(player_id) -> bool[/code]: whether they are back.
var alive_fn: Callable = Callable()

## [code]colour_fn.call(player_id) -> Color[/code]: their monster's colour.
var colour_fn: Callable = Callable()

## player id -> {at, radius, msec}
var _lost: Dictionary = {}
var _live: Array = []


## A piece left the world: remember where it was, in case it was somebody's last.
func note_piece(piece: HungryPiece) -> void:
	if piece == null:
		return
	_lost[piece.owner_id] = {
		"at": piece.position(), "radius": piece.radius(), "msec": Time.get_ticks_msec(),
	}


## The cap in force: the server's and this machine's, the lower.
func cap() -> int:
	var mine := local_cap if local_cap > 0 else DotPlayerRagdolls.default_local_cap()
	return mini(rules.max_count if rules != null else 8, mine)


## [param player_id] was eaten: their last piece goes down the way [param death] says (null
## is a plain limp fall). Returns the fall, or null when the style hides bodies or this client
## never drew that piece.
func fall(player_id: int, death: DotPlayerDeath) -> Node2D:
	var rider: Node2D = rider_fn.call(player_id) if rider_fn.is_valid() else null
	var style := rules.effective_style() if rules != null else DotPlayerRagdollRules.Style.RAGDOLL
	if style == DotPlayerRagdollRules.Style.HIDE:
		if rider != null:
			rider.visible = false
		return null

	var lost: Dictionary = _lost.get(player_id, {})
	_lost.erase(player_id)
	if lost.is_empty() or Time.get_ticks_msec() - int(lost["msec"]) > REMEMBER_MSEC:
		return null

	_reap()
	var standing := _standing()
	while standing.size() > cap() - 1 and not standing.is_empty():
		(standing.pop_front() as HungryFall).expire(EVICT_FADE)

	var made := HungryFall.new()
	made.name = "Fall%d" % player_id
	made.player_id = player_id
	made.death = death if death != null else DotPlayerDeath.new()
	made.reaction = reactions.find(made.death.reaction) if reactions != null else null
	if made.reaction == null:
		made.reaction = DotPlayerDeathReactions.stock().find(DotPlayerDeathReactions.LIMP)
	made.at = lost["at"]
	made.radius = float(lost["radius"])
	made.colour = colour_fn.call(player_id) if colour_fn.is_valid() else Color.WHITE
	made.rider = rider
	made.alive_fn = alive_fn
	made.sound.connect(_on_sound)
	add_child(made)
	made.start(rules)
	_live.append(made)
	return made


func _standing() -> Array:
	var out: Array = []
	for body: Variant in _live:
		if is_instance_valid(body) and not (body as HungryFall).expiring:
			out.append(body)
	return out


func _reap() -> void:
	var kept: Array = []
	for body: Variant in _live:
		if is_instance_valid(body) and not (body as Node).is_queued_for_deletion():
			kept.append(body)
	_live = kept


## Falls on screen now, fading ones included.
func live() -> Array:
	_reap()
	return _live.duplicate()


## Every fall gone at once: a round reset, a mode change.
func clear() -> void:
	for body: Variant in _live:
		if is_instance_valid(body):
			(body as HungryFall)._release_rider(true)
			(body as Node).queue_free()
	_live.clear()
	_lost.clear()


func _on_sound(id: StringName, at: Vector2, volume: float) -> void:
	sound.emit(id, at, volume)


func describe() -> Dictionary:
	return {"live": live().size(), "remembered": _lost.size(), "cap": cap(),
		"style": DotPlayerRagdollRules.style_name(rules.effective_style()) if rules != null else "-"}
