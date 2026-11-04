extends DotSpectatorHost

const HungryWorld := preload("hungry_world.gd")

## Where a dead monster's owner looks.
##
## [b]Until this existed the camera stayed exactly where the monster died.[/b]
## `HungryCamera` follows an anchor at the mass-weighted centroid and, when there is
## nothing to follow, leaves the camera where it is — so the seconds between being eaten
## and coming back are spent looking at the patch of arena that ate you, while the game
## happens somewhere else.
##
## [b]A 2D world is the XZ plane, which is what makes this four lines rather than a
## second addon.[/b] dot-npc settled that convention and everything downstream inherited
## it; `DotSpectatorManager.camera_2d_of` gives a position and a facing back, so nothing
## here needs a 3D camera or a second code path.
##
## [b]The policy is the whole point, and this game's is its own.[/b] Hungario is a
## free-for-all, so "your own team only" would restrict the camera to a team of one and
## mean nothing — it is 0. But a living player may **not** watch, and that one is not a
## formality: this is a game where knowing where the biggest monster is standing is the
## entire skill, and a second monitor showing it would be worth more than playing well.

const CHANNEL := "hungry.spectate"

var world: HungryWorld = null

## Adds this host under [param p_world] and binds it; false (logged, and freed) when it cannot bind.
func attach_to(p_world: HungryWorld) -> bool:
	name = "Spectate"
	p_world.add_child(self)

	var watching := bind(p_world)

	if not watching.ok:
		# Not fatal: a world with no spectator camera is how this game ran before spectating existed.
		DotLog.warn(CHANNEL, "spectating is off", {"why": watching.error.message})
		p_world.remove_child(self)
		queue_free()
		return false

	return true


## Binds the world and builds the manager. [method setup] itself takes no world.
func bind(p_world: HungryWorld) -> DotResult:
	world = p_world
	authoritative = world.is_authority
	tick_rate = world.tick_rate
	death_cam_seconds = 1.0
	freeze_cam_seconds = 0.0
	chase_height = 0.8
	history_seconds = 4.0

	var res := setup()
	if not res.ok:
		return res.wrap("hungario spectate")

	if not world.player_died.is_connected(_on_died):
		world.player_died.connect(_on_died)
	if not world.player_spawned.is_connected(_on_spawned):
		world.player_spawned.connect(_on_spawned)

	return DotResult.success(null)


func _channel() -> String:
	return CHANNEL


func _tune_rules(r: DotSpectatorRules) -> DotSpectatorRules:
	# A free-for-all has no sides, so restricting the camera to one restricts it to a team of one.
	r.force_camera = 0
	# Knowing where the biggest monster stands is the skill; a living watcher would have it free.
	r.allow_while_alive = false
	r.allow_roaming = false
	r.cycle_includes_dead = false
	return r


func _participants() -> PackedStringArray:
	var out := PackedStringArray()
	var ids: Array = world.player_ids()
	ids.sort()
	for id: Variant in ids:
		out.append(str(id))
	return out


## The side they are actually on: dot-spectate reads 0 as "no team", and the stack is built
## before anything can spectate.
func _team_of(key: String) -> int:
	return world.player_stack.team_index_of(key) if world.player_stack != null else 0


func _is_alive(key: String) -> bool:
	var monster := world.monster_for(key.to_int())
	return monster != null and monster.alive


## The centroid rather than a piece: after a burst the pieces are most of a screen apart.
func _pose_of(key: String) -> Transform3D:
	var monster := world.monster_for(key.to_int())
	if monster == null or not monster.alive:
		return Transform3D.IDENTITY
	var at := monster.centre()
	return Transform3D(Basis.IDENTITY, Vector3(at.x, 0.0, at.y))


func _current_tick() -> int:
	return world.current_tick()


func tick(_delta: float) -> void:
	advance_live()


## Where a viewer's camera should be, in world units. Null when they are not watching.
##
## A [Variant]: "not spectating" and "spectating the origin" differ, and this arena is
## centred on the origin.
func camera_position(viewer: int) -> Variant:
	if not is_spectating(str(viewer)):
		return null
	var flat := manager.camera_2d_of(str(viewer))
	return flat[0] as Vector2


func _on_died(player_id: int, killer_id: int) -> void:
	# Only the server's chain: a mirror emits `player_died` too but runs no timers, so a
	# chain started there is a death camera nothing hands over.
	if manager == null or not manager.authoritative:
		return
	var monster := world.monster_for(player_id)
	var at := monster.centre() if monster != null else Vector2.ZERO
	death(str(player_id), Vector3(at.x, 0.0, at.y), str(killer_id) if killer_id != 0 else "")
	DotLog.debug(CHANNEL, "a dead player is spectating", {
		"player": player_id, "killer": killer_id, "watching": watching(str(player_id)),
	})


func _on_spawned(player_id: int) -> void:
	if is_spectating(str(player_id)):
		DotLog.debug(CHANNEL, "a respawn ends spectating", {"player": player_id})
	spawned(str(player_id))
