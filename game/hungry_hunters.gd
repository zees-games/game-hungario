extends Node

const HungryPaths := preload("hungry_paths.gd")

const HungryMonster := preload("hungry_monster.gd")
const HungryWorld := preload("hungry_world.gd")
const HungryLayout := preload("hungry_layout.gd")

## NPC monsters that roam the arena, eat what they can and run from what they cannot.

const CHANNEL := "hungry.hunters"

## The scene every hunter is. Bare: a hunter has no art and is drawn by the client from
## its kind and its radius, exactly as a piece of food is.
static var HUNTER_SCENE := HungryPaths.rebase("res://game/hungry_hunter_body.tscn")

## The brain, named by PATH. See the note at the top of `hunter_brain.gd`.
static var HUNTER_BRAIN := HungryPaths.rebase("res://game/hungry_hunter_brain.gd")

## Candidate id prefix for a player, so a hunter's target id can be turned back into one.
const PLAYER_PREFIX := "p"

## How often a hunter's state goes out, in ticks.
const BROADCAST_EVERY := 12


## A hunter appeared, moved, or is gone. Both ends.
signal hunter_changed(hunter_id: int)

## A hunter ate somebody's piece. Server side.
signal piece_hunted(player_id: int, mass: float)


var spawner: DotNpcSpawner = null

## How good the hunters are, server-wide. Handed in by the module, which owns the cvars;
## attached to the spawner before the first hunter thinks. Null leaves them as authored.
var npc_skill: DotNpcAiSkill = null
var director: DotNpcDirector = null

## The world this hunts in. Set before [method setup].
var world: HungryWorld = null

## Whether this end actually runs hunters. A client mirrors and never spawns.
var authoritative: bool = false

## hunter id -> {"kind": StringName, "at": Vector2, "radius": float, "alive": bool}
var _hunters: Dictionary = {}

## instance id -> wire id, and back. Authority only.
var _wire_of_instance: Dictionary = {}
var _instance_of_wire: Dictionary = {}
var _next_wire_id: int = 1

var _tick: int = 0

## The layout the spawner's navigation was built from, so a game change — a new world
## with a new layout — is noticed on the next tick rather than by a hook somebody has to
## remember to call. Identity, not equality: the world builds its layout once.
var _nav_layout: HungryLayout = null
var _nav_built: bool = false
var _static_catalogue: DotNpcCatalogue = null



## What a hunter can be. Three kinds, and each is a different problem for a player.
static func catalogue() -> DotNpcCatalogue:
	var out := DotNpcCatalogue.new()

	# Small, fast, and only a threat to somebody who has just spawned or just split. The
	# thing that makes splitting a commitment rather than a free move.
	_add(out, &"swarmling", "Swarmling", 45.0, 320.0, 900.0, 1, 30.0, "normal")

	# The middle one. Fast enough to catch a careless player and small enough to be worth
	# eating, which is what makes hunting them a strategy rather than a hazard.
	_add(out, &"stalker", "Stalker", 220.0, 240.0, 1400.0, 3, 90.0, "hard")

	# Slow and enormous. Nothing about outrunning it is hard; the problem is that it is
	# sitting on the food.
	_add(out, &"lurker", "Lurker", 900.0, 120.0, 1100.0, 8, 220.0, "easy")

	return out


static func _add(
	into: DotNpcCatalogue,
	id: StringName,
	display: String,
	mass: float,
	speed: float,
	sight: float,
	cost: int,
	health: float,
	skill: String
) -> void:
	var def := DotNpcDef.make(id, HUNTER_SCENE)
	def.display_name = display
	def.brain_script_path = HUNTER_BRAIN
	def.category = &"hunter"
	def.faction = &"hunter"
	def.cost = cost
	def.max_health = health
	def.sight_range = sight
	# Hearing is deliberately shorter than sight in an arena where nothing is opaque: it
	# is what lets a hunter notice somebody who split behind it.
	def.hearing_range = sight * 0.4
	# Off, as it has to be for a 2D NPC: there is no 3D physics world to cast through and this arena has no walls.
	def.require_line_of_sight = false
	# `skill` names the hunter's character — dot-npc-ai's brain reads it from here. Until
	# this was added no hunter had one, so `has_reacted()` answered true on the tick a
	# hunter first saw somebody: the reaction time this file's header promised was zero.
	def.meta = {"mass": mass, "speed": speed, "skill": skill}
	into.add(def)


static func shared_catalogue() -> DotNpcCatalogue:
	return _shared if _shared != null else _make_shared()


static var _shared: DotNpcCatalogue = null

static func _make_shared() -> DotNpcCatalogue:
	_shared = catalogue()
	return _shared


## The catalogue's ids, sorted as [String], so an index can travel instead of a name.
static func wire_ids() -> PackedStringArray:
	var out := PackedStringArray()

	for def in shared_catalogue().npcs:
		out.append(String(def.id))

	out.sort()
	return out


static func index_of(id: StringName) -> int:
	return wire_ids().find(String(id))


static func id_at(index: int) -> StringName:
	var ids := wire_ids()
	return StringName(ids[index]) if index >= 0 and index < ids.size() else &""


static func mass_of(id: StringName) -> float:
	var def := shared_catalogue().get_npc(id)
	return float(def.meta.get("mass", 0.0)) if def != null else 0.0


static func radius_of(id: StringName) -> float:
	# Drawn from the mass, exactly as a monster's piece is — so a hunter that is half the
	# mass of your monster looks half the area of it, which is the one comparison a player
	# makes constantly and the whole reason the rings exist.
	return sqrt(maxf(mass_of(id), 1.0) / PI) * 4.0



## Builds the spawner and the director on the authority, and nothing on a client.
func setup(p_authoritative: bool, p_world: HungryWorld) -> DotResult:
	authoritative = p_authoritative
	world = p_world

	if not authoritative:
		return DotResult.success(null)

	var limits := DotNpcLimits.new()
	limits.world_budget = 40
	limits.per_kind_cap = 12
	limits.spawn_interval = 0.0
	# No navigable-spawn requirement: this arena has no navigation graph, and "no navigation" is not "off the navigation" to dot-npc.
	# Requiring a graph would refuse every spawn.
	limits.require_navigable_spawn = false
	# Longer than the addon's default, because being chased across an arena is the
	# experience and a hunter reclaimed after six seconds of it is a hunter that gives up.
	limits.reclaim_grace = 25.0
	# The path's snap in world units: dot-npc's default of 4 is metres, and a snap that found no grid point would mean a path that is never found.
	limits.spawn_snap_radius = 100.0

	var problem := limits.validate()

	if not problem.ok:
		return problem.wrap("The hunter limits are not usable")

	spawner = DotNpcSpawner.new()
	spawner.name = "Spawner"
	spawner.catalogue = shared_catalogue()
	spawner.limits = limits
	spawner.authoritative = true
	# One flag says this spawner serves a 2D world; `spawn_group` and the director both
	# read it, so neither needs a 2D twin.
	spawner.two_dimensional = true
	# A target moves every tick and dot-npc's default drift is 2.5 metres, which would repath every tick for every hunter.
	# Three grid steps and at most once a second: a whole-map search costs 15-40 ms in GDScript.
	spawner.repath_drift = NAV_SPACING * 3.0
	spawner.repath_interval = 1.0
	if npc_skill != null:
		npc_skill.attach(spawner)
	add_child(spawner)

	spawner.spawned.connect(_on_spawned)
	spawner.removed.connect(_on_removed)

	return _build_director()


## The director, and the one number in it that is this game rather than the genre.
func _build_director() -> DotResult:
	var rules := DotNpcDirectorRules.new()
	# An arena has no critical path to spawn ahead along, so the distances are the arena's and `spawn_ahead` is zero:
	# far enough away not to be a jump scare, near enough to arrive.
	rules.spawn_min_distance = 600.0
	rules.spawn_max_distance = 2200.0
	rules.spawn_ahead = 0.0
	rules.spawn_out_of_sight = false
	rules.behind_fraction = 0.0
	rules.peak_per_player = 6.0
	rules.build_up_per_player = 3.0
	rules.relax_per_player = 1.0
	rules.absolute_cap = 30
	rules.spawn_burst = 2
	rules.spawn_interval = 1.5
	rules.reclaim_interval = 4.0
	# Zero would mean "never" here and "every tick" for `spawn_interval`, so this is set explicitly rather than left.
	rules.relax_distance = 1200.0
	rules.stress_decay = 0.10
	rules.stress_per_damage = 0.9
	rules.stress_per_threat = 0.05
	rules.stress_threat_radius = 500.0

	var problem := rules.validate()

	if not problem.ok:
		return problem.wrap("The director rules are not usable")

	director = DotNpcDirector.new()
	director.name = "Director"
	director.rules = rules
	director.spawner_ref = DotNodeRef.of_path(^"../Spawner")
	# Round-robin through this list, so the mix is exact rather than approached — a random
	# pick from three gives three lurkers in a row often enough for a player to notice and
	# conclude the director is broken.
	director.population = [&"swarmling", &"stalker", &"swarmling", &"lurker"]
	director.enabled = false
	add_child(director)

	# Somewhere to put them: [method spawn_points_for], seeded by [method _keep_nav_current]
	# on the first tick of every layout rather than once here, because the world this was
	# set up with is not the world a game change leaves it with.
	return DotResult.success(null)


func _seed_spawn_points() -> void:
	if world == null or world.arena == null or director == null:
		return

	var points := PackedVector3Array()

	for at in spawn_points_for(world.layout, world.arena.bounds):
		points.append(DotNpcInstance.to_plane(at))

	director.spawn_points = points


## The radius a spawn point is chosen for: the biggest hunter's, because the director's
## points are shared by every kind and a point that suits a lurker suits all three.
static func largest_radius() -> float:
	var out := 0.0

	for def in shared_catalogue().npcs:
		out = maxf(out, radius_of(def.id))

	return out


## Where a hunter may appear in [param layout] inside [param bounds].
static func spawn_points_for(layout: HungryLayout, bounds: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var centre := bounds.get_center()
	var radius := largest_radius()
	var solid := layout != null and not layout.is_empty()
	var region := layout.main_region(bounds, radius) if solid else {}

	for ring in [0.35, 0.6, 0.85]:
		for step in range(12):
			var angle := TAU * float(step) / 12.0
			var at := centre + Vector2(cos(angle), sin(angle)) \
				* bounds.size * 0.5 * float(ring)

			if solid:
				at = layout.nearest_clear(at, radius, bounds)

				if not spawnable(layout, bounds, at, region):
					continue

			out.append(at)

	return out


## Whether a hunter may appear at [param at]: not behind a harbour's fence, in the reef's cove, the shallows' tightest line, a rock pool or the inlet,
## and inside [param region] ([method HungryLayout.main_region] at the size being placed).
static func spawnable(layout: HungryLayout, bounds: Rect2, at: Vector2, region: Dictionary) -> bool:
	if layout == null or layout.is_empty():
		return bounds.has_point(at)

	if layout.harbour_of(at, bounds) >= 0 or layout.in_cove(at, bounds) \
			or layout.shallows_band(at, bounds) == 0 or layout.in_pool(at, bounds) \
			or layout.in_inlet(at, bounds):
		return false

	return HungryLayout.in_region(region, bounds, at)


## Whether the director is releasing hunters.
func set_enabled(on: bool) -> void:
	# INFO on the edge only: an operator turned the mode into a different game, and that is
	# worth keeping. The cvar may be re-applied with the same value on every game change.
	if director != null and director.enabled != on:
		DotLog.info(CHANNEL, "hunters switched %s" % ("on" if on else "off"), {
			"hunters": _hunters.size(),
		})

	if director != null:
		director.enabled = on

	if not on and spawner != null:
		spawner.clear_all()


func is_enabled() -> bool:
	return director != null and director.enabled



## One authoritative step. Called from the module's tick, inside the netcode's.
func tick(delta: float) -> void:
	if not authoritative or spawner == null or world == null:
		return

	_tick += 1
	_keep_nav_current()

	# The candidate list is built once per tick, before the hunters run: once rather than per hunter to save allocations, and before so it holds where everybody is, not was.
	spawner.set_candidates(_candidates())
	_report_stress()

	spawner.tick(delta)
	director.tick(delta)

	# After the steering and before the eating, so a hunter is stopped by a rock before it is asked whether it has reached anybody.
	# [HungryWorld.tick] makes the same ordering argument about players.
	_keep_out_of_the_level()

	_resolve_eating()

	if _tick % BROADCAST_EVERY == 0:
		_broadcast_all()



## The navigation grid's step, in world units.
const NAV_SPACING := 64.0

## How far off a rock a navigation point stands.
const NAV_CLEARANCE := 40.0


## Navigation for [param layout] inside [param bounds], or null for an empty one.
static func nav_for(layout: HungryLayout, bounds: Rect2) -> DotNpcNavData:
	if layout == null or layout.is_empty():
		return null

	var data := DotNpcNavData.new()
	# A variant's colon is not a file-name character everywhere.
	data.map_id = StringName("hungry_%s" % String(layout.id).replace(":", "_"))
	data.grid_spacing = NAV_SPACING
	data.point_radius = NAV_SPACING
	data.source_digest = DotNpcNavData.digest_of([
		String(layout.id), bounds.position, bounds.size, NAV_SPACING, NAV_CLEARANCE,
		layout.blocks,
	])

	var inner := bounds.grow(-NAV_CLEARANCE)
	var columns := int(floor(inner.size.x / NAV_SPACING)) + 1
	var rows := int(floor(inner.size.y / NAV_SPACING)) + 1
	var index_at := PackedInt32Array()
	index_at.resize(columns * rows)
	index_at.fill(-1)

	for row in range(rows):
		for column in range(columns):
			var at := inner.position + Vector2(column, row) * NAV_SPACING

			if not layout.blocked(at, NAV_CLEARANCE):
				index_at[row * columns + column] = data.add_point(DotNpcInstance.to_plane(at))

	# Four of the eight directions from each point, so each edge is added once; the graph
	# makes every edge two-way.
	var steps := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]

	for row in range(rows):
		for column in range(columns):
			var here := index_at[row * columns + column]

			if here < 0:
				continue

			for step in steps:
				var c: int = column + step.x
				var r: int = row + step.y

				if c < 0 or c >= columns or r >= rows:
					continue

				var there := index_at[r * columns + c]

				if there < 0:
					continue

				if layout._clear_line(
					DotNpcInstance.from_plane(data.points[here]),
					DotNpcInstance.from_plane(data.points[there]),
					NAV_CLEARANCE, NAV_SPACING * 0.5
				):
					data.connect_points(here, there)

	return data


## Hands the spawner navigation for whatever layout the world has now.
func _keep_nav_current() -> void:
	if spawner == null or world == null:
		return

	var layout := world.layout

	if _nav_built and layout == _nav_layout:
		return

	_nav_layout = layout
	_nav_built = true
	var bounds := world.arena.bounds if world.arena != null else Rect2()
	spawner.set_nav_data(nav_for(layout, bounds))
	# The spawn points are the level's as much as the graph is, so they are rebuilt on a game change.
	# Seeded once from the boot world, a director placed hunters on the last map's rings ([hunter-nav-1]).
	_seed_spawn_points()


## Pushes every hunter out of the level's own geometry.
func _keep_out_of_the_level() -> void:
	if world == null or world.layout == null or world.layout.is_empty():
		return

	var bounds := world.arena.bounds if world.arena != null else Rect2()

	for npc in spawner.all_npcs():
		if not npc.is_alive() or not (npc.node is Node2D):
			continue

		var body := npc.node as Node2D
		var radius := radius_of(npc.def.id) if npc.def != null else 0.0
		var clear := world.layout.nearest_clear(body.global_position, radius, bounds)

		if not clear.is_equal_approx(body.global_position):
			body.global_position = clear


## Everybody a hunter might notice, as dot-npc's candidates.
func _candidates() -> Array:
	var out: Array = []

	for monster in world.monsters():
		if not monster.alive or monster.piece_count() == 0:
			continue

		out.append(DotNpcSenses.Candidate.new(
			StringName("%s%d" % [PLAYER_PREFIX, monster.id]),
			DotNpcInstance.to_plane(monster.centre()),
			&"player",
			# Loudness: a bigger monster is harder to miss. It is what makes a hunter
			# notice the leader from across the arena and a newly spawned player not at
			# all, which is the pacing this game wants and costs one number.
			clampf(monster.mass() / 4000.0, 0.0, 1.0)
		))

	return out


## What the director measures its phases against.
func _report_stress() -> void:
	for monster in world.monsters():
		if not monster.alive or monster.piece_count() == 0:
			director.forget_player(StringName("%s%d" % [PLAYER_PREFIX, monster.id]))
			continue

		director.report_player(
			StringName("%s%d" % [PLAYER_PREFIX, monster.id]),
			DotNpcInstance.to_plane(monster.centre()),
			_pressure_on(monster)
		)


## One minus how hunted somebody is, in the range the director calls health.
func _pressure_on(monster: HungryMonster) -> float:
	var worst := 0.0
	var here := monster.centre()
	var ratio := eat_ratio()

	for entry in _hunters.values():
		var state: Dictionary = entry

		if not bool(state["alive"]):
			continue

		var kind: StringName = state["kind"]

		# Only something that could actually eat them. A lurker that a player is about to
		# swallow is not pressure, and counting it would make the director back off
		# exactly when the player is winning.
		if mass_of(kind) < monster.mass() * ratio:
			continue

		var distance: float = here.distance_to(state["at"])
		worst = maxf(worst, clampf(1.0 - distance / 1800.0, 0.0, 1.0))

	return 1.0 - worst



## A hunter and a monster meeting. The same ratio everything else in this game uses.
func _resolve_eating() -> void:
	var ratio := eat_ratio()

	for wire_id in _hunters.keys():
		var state: Dictionary = _hunters[wire_id]

		if not bool(state["alive"]):
			continue

		var kind: StringName = state["kind"]
		var hunter_mass := mass_of(kind)
		var at: Vector2 = state["at"]
		var reach: float = state["radius"]

		for monster in world.monsters():
			if not monster.alive or not world.can_be_harmed(monster.id):
				continue

			for piece in monster.pieces:
				if at.distance_to(piece.position()) > reach + piece.radius():
					continue

				if hunter_mass >= piece.mass() * ratio:
					# The hunter eats the piece. Reported rather than done here: what
					# "lose a piece" means — dying, splitting, respawning — is the
					# world's, exactly as [DotTimer] never moves a player.
					DotLog.debug(CHANNEL, "a hunter ate a piece", {
						"hunter": int(wire_id), "kind": String(kind),
						"player": monster.id, "mass": snappedf(piece.mass(), 0.1),
					})
					piece_hunted.emit(monster.id, piece.mass())
					world.devour_piece(piece.id, at)
					break
				elif piece.mass() >= hunter_mass * ratio:
					# The player eats the hunter through the spawner's own death path, so the population budget, the director's count and the removal event agree.
					DotLog.debug(CHANNEL, "a player ate a hunter", {
						"hunter": int(wire_id), "kind": String(kind), "player": monster.id,
					})
					var instance_id := int(_instance_of_wire.get(wire_id, 0))
					spawner.report_death(instance_id, StringName(str(monster.id)))
					world.feed_player(monster.id, hunter_mass)
					break



func _on_spawned(npc: DotNpcInstance) -> void:
	var wire_id := _next_wire_id
	_next_wire_id += 1

	# The brain reaches this object through `meta`, which is dot-npc's documented hook for
	# "anything the game keeps with an NPC". A brain that named [HungryHunters] directly
	# would be a brain that cannot be delivered in a pack.
	npc.meta["hunters"] = self

	# On the layout's `enemy` layer: `top_down_2d`'s `enemy` row differs from Godot's default layer 1, which would make a hunter solid against nothing it should be.
	# Most of this game is analytic, so a hunter body and a hazard body are nearly all there is to classify.
	if world != null and world.player_stack != null and npc.node != null:
		var _put := world.player_stack.classify(npc.node, &"enemy")

	_wire_of_instance[npc.instance_id] = wire_id
	_instance_of_wire[wire_id] = npc.instance_id
	_hunters[wire_id] = {
		"kind": npc.def.id,
		"at": npc.position_2d(),
		"radius": radius_of(npc.def.id),
		"alive": true,
	}

	DotLog.debug(CHANNEL, "a hunter spawned", {
		"hunter": wire_id, "kind": String(npc.def.id), "at": npc.position_2d(),
		"population": _hunters.size(),
	})
	hunter_changed.emit(wire_id)


func _on_removed(npc: DotNpcInstance, reason: StringName) -> void:
	var wire_id := int(_wire_of_instance.get(npc.instance_id, 0))

	if wire_id == 0:
		return

	DotLog.debug(CHANNEL, "a hunter was removed", {
		"hunter": wire_id, "reason": String(reason),
	})

	_wire_of_instance.erase(npc.instance_id)
	_instance_of_wire.erase(wire_id)

	# Marked dead and kept for one broadcast rather than erased, so every client is told
	# it is gone. Erasing it here would simply stop mentioning it, and a client would draw
	# a hunter that no longer exists until something else happened to it.
	if _hunters.has(wire_id):
		(_hunters[wire_id] as Dictionary)["alive"] = false

	hunter_changed.emit(wire_id)


func _broadcast_all() -> void:
	for wire_id in _hunters.keys():
		var state: Dictionary = _hunters[wire_id]
		var instance_id := int(_instance_of_wire.get(wire_id, 0))
		var npc := spawner.get_npc(instance_id)

		if npc != null and npc.is_alive():
			state["at"] = npc.position_2d()

		hunter_changed.emit(int(wire_id))

	# The dead ones, once each. They have been announced now.
	for wire_id in _hunters.keys():
		if not bool((_hunters[wire_id] as Dictionary)["alive"]):
			_hunters.erase(wire_id)



## Takes a hunter's state the authority announced. Client side.
func adopt(wire_id: int, kind: StringName, at: Vector2, radius: float, alive: bool) -> void:
	if not alive:
		_hunters.erase(wire_id)
		hunter_changed.emit(wire_id)
		return

	_hunters[wire_id] = {
		"kind": kind, "at": at, "radius": radius, "alive": true,
	}
	hunter_changed.emit(wire_id)


func forget_all() -> void:
	_hunters.clear()



func hunters() -> Dictionary:
	return _hunters.duplicate()


## How many are actually in the arena.
func count() -> int:
	var alive := 0

	for entry in _hunters.values():
		if bool((entry as Dictionary)["alive"]):
			alive += 1

	return alive


func state_of(wire_id: int) -> Dictionary:
	return (_hunters.get(wire_id, {}) as Dictionary).duplicate()


## Everything the authority holds, as `[wire_id, kind_index, at, radius, alive]` rows.
func wire_rows() -> Array:
	var out: Array = []

	for wire_id in _hunters.keys():
		var state: Dictionary = _hunters[wire_id]
		out.append([
			int(wire_id),
			index_of(state["kind"]),
			state["at"],
			float(state["radius"]),
			bool(state["alive"]),
		])

	return out



## The world's eat ratio. Asked for rather than copied into the brain.
func eat_ratio() -> float:
	if world == null or world.tunables == null or world.tunables.mass_rules == null:
		return 1.25

	return world.tunables.mass_rules.eat_ratio


## Where a candidate is, in dot-npc's plane. `Vector3.INF` when it has gone.
func position_of(candidate_id: StringName) -> Vector3:
	var monster := _monster_for(candidate_id)

	if monster == null or not monster.alive:
		return Vector3.INF

	return DotNpcInstance.to_plane(monster.centre())


## What a candidate weighs, for the ratio. Zero when it has gone.
func mass_of_candidate(candidate_id: StringName) -> float:
	var monster := _monster_for(candidate_id)
	return monster.mass() if monster != null and monster.alive else 0.0


## Whether a point is close enough to the wall that a wanderer should turn round.
func is_near_edge(at: Vector2) -> bool:
	if world == null or world.arena == null:
		return false

	var bounds := world.arena.bounds
	var margin := 300.0

	return at.x < bounds.position.x + margin or at.x > bounds.end.x - margin \
		or at.y < bounds.position.y + margin or at.y > bounds.end.y - margin


func _monster_for(candidate_id: StringName) -> HungryMonster:
	var text := String(candidate_id)

	if not text.begins_with(PLAYER_PREFIX) or world == null:
		return null

	var id := text.substr(PLAYER_PREFIX.length())
	return world.monster_for(id.to_int()) if id.is_valid_int() else null


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	out.append("hunters      %d (%s)" % [
		_hunters.size(), "on" if is_enabled() else "off"
	])

	if authoritative and director != null:
		out.append_array(director.describe_lines())

	return out
