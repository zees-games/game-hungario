@tool
extends Node

const HungryContent := preload("hungry_content.gd")
const HungryField := preload("hungry_field.gd")
const HungryLayout := preload("hungry_layout.gd")
const HungryMonster := preload("hungry_monster.gd")
const HungryNetCommand := preload("net/hungry_net_command.gd")
const HungryPiece := preload("hungry_piece.gd")
const HungryPlayerStack := preload("hungry_player_stack.gd")
const HungryPreset := preload("hungry_preset.gd")
const HungryProjectile := preload("hungry_projectile.gd")
const HungryTuning := preload("hungry_tuning.gd")
const HungrySpectate := preload("hungry_spectate.gd")

## The game: an arena, four fields of food, a set of monsters, and the rules that
## connect them.

const CHANNEL := "hungry"
const SERVICE := &"hungry_world"

## A monster ate a piece of food or a planted crumb.
signal food_eaten(player_id: int, grid_id: int, mass: float)

## A monster ate a fruit.
signal fruit_eaten(player_id: int, grid_id: int, kind: HungryContent.Fruit)

## A monster picked a throwable up.
signal item_taken(player_id: int, grid_id: int, item: StringName)

## A piece ate another player's piece.
signal piece_eaten(eater_id: int, victim_player: int, mass: float)

## A player lost their last piece.
signal player_died(player_id: int, killer_id: int)

signal player_spawned(player_id: int)

## A piece came into or went out of existence. What the netcode bridge replicates.
signal piece_created(piece: HungryPiece)
signal piece_destroyed(piece: HungryPiece)

signal projectile_thrown(shot: HungryProjectile)
signal projectile_impact(shot: HungryProjectile, at: Vector2, hit_player: int)

## Somebody was burst by a pepper.
signal monster_burst(player_id: int, by_player: int, pieces: int)

signal match_state_changed(from: DotMatch.State, to: DotMatch.State)

## The food field changed and a delta is waiting in [member field].
signal field_changed()

@export_group("Simulation")

@export_range(1, 240, 1) var tick_rate: int = HungryContent.TICK_RATE

## Whether this instance decides who eats whom.
@export var is_authority: bool = true

@export_group("World")

## Which mode this is. Null means [method HungryPreset.classic].
@export var preset: HungryPreset = null

@export var world_size: Vector2 = HungryContent.WORLD_SIZE

## Two peers with the same seed lay the same fields out, so a client can place eleven
## hundred pieces of food from one integer rather than receiving eleven hundred
## positions.
@export_range(1, 2147483647, 1) var world_seed: int = 20260828

@export_group("Service")

@export var register_service: bool = true

@export var service_scope: StringName = &""

var arena: Dot2DArena = null

## What is solid in this world: the level's own geometry.
var layout: HungryLayout = HungryLayout.none()

## What a monster wedged in a refuge it has outgrown does (`[refuge-outgrown-1]`). Taken from
## the preset on setup and changed live by the server's `hungry_outgrown`.
enum Outgrown { ACCEPT, CAP, EJECT }
var outgrown: int = Outgrown.ACCEPT

## A layout variant set by whoever builds this world, over everything else. Empty: the
## operator's `hungry_warrens_corners`, then the preset's own. Read once, when the layout is
## built at setup — never mid-round: rocks moving under a monster are a different game.
var layout_variant: String = ""

## How deep into a rock counts as wedged, in units: less than this is a piece brushing one.
const WEDGED_DEPTH := 1.0

var field: HungryField = null
var match_node: DotMatch = null
var tunables: Dot2DTunables = null

## What an eaten monster does on every screen, and which death reactions the server allows:
## dot-player-char's `sv_ragdoll*` set. The module hands this world its own (bound to the
## cvars, which outlive a mode change); offline it is the stock set. See [method decide_death].
var ragdoll_rules: DotPlayerRagdollRules = DotPlayerRagdollRules.new()
var motor: Dot2DMotor = null

## The throwables a monster may carry. dot-loadout's, so the server can check one
## without loading anything.
var items: DotItemCatalogue = null

## What decides whether a thrown item does anything, and how much.
var damage_gate: Callable = Callable()

## Whether a player's client is still behind its loading cover: `func(player_id: int) -> bool`.
var loading_fn: Callable = Callable()

## Where a dead monster's owner looks. Built by [method setup] on the authority and on a
## client alike, because both ends need the camera to point somewhere.
var spectate: HungrySpectate = null

## Who is in the session, which side, which trait, where they appear, and the physics.
var player_stack: HungryPlayerStack = null

## player id -> [HungryMonster].
var _monsters: Dictionary = {}

## piece id -> [HungryPiece]. Every live piece in the world.
var _pieces: Dictionary = {}

## projectile id -> [HungryProjectile].
var _shots: Dictionary = {}

var _next_piece_id: int = 1
var _next_shot_id: int = 1
var _tick: int = 0
var _registered_name: StringName = &""

## Tunables with a monster's current speed multiplier folded in. One instance, reused:
## see [method _tunables_for].
var _scaled: Dot2DTunables = null

## One piece's view of its monster's command. One instance, reused: see
## [method command_for_piece].
var _piece_command: Dot2DCommand = Dot2DCommand.new()


func _exit_tree() -> void:
	if _registered_name != &"":
		DotRegistry.unregister_instance(_registered_name, self)
		_registered_name = &""


func setup() -> DotResult:
	if preset == null:
		preset = HungryPreset.classic()

	var preset_valid := preset.validate()

	if not preset_valid.ok:
		return preset_valid

	world_size = preset.world_size
	outgrown = preset.outgrown

	tunables = HungryContent.tunables()
	tunables.max_speed = preset.max_speed
	tunables.mass_rules.merge_delay_sec = preset.merge_delay_sec

	var valid := tunables.validate()

	if not valid.ok:
		return valid

	items = HungryContent.item_catalogue()

	var catalogue_valid := items.validate()

	if not catalogue_valid.ok:
		return catalogue_valid

	arena = Dot2DArena.new()
	arena.name = "Arena"
	arena.register_service = false
	arena.bounds = Rect2(-world_size * 0.5, world_size)
	arena.cell_size = HungryContent.CELL_SIZE
	arena.interest_extent = Vector2(1180.0, 760.0)
	arena.interest_scales_with_size = true
	add_child(arena)
	arena.setup()

	motor = Dot2DMotor.with_tunables(tunables)
	motor.body = arena.body

	_scaled = tunables.duplicate() as Dot2DTunables
	# The same rules object, not a copy of it: the eat ratio and the radius curve are
	# global, and two copies that drifted apart would put a monster's drawn radius and
	# its eat radius in different places.
	_scaled.mass_rules = tunables.mass_rules

	# Before the field, because the field is culled against it.
	layout = HungryLayout.for_id(
		HungryLayout.with_variant(preset.layout, _chosen_layout_variant()), arena.bounds
	)

	field = HungryField.over(arena.bounds, world_seed)
	field.food.target_count = preset.food_target
	field.fruit.target_count = preset.fruit_target
	field.items.target_count = preset.item_target
	_cull_blocked(field.fill_all())
	field.populate(arena.grid)

	var match_result := _build_match()

	if not match_result.ok:
		return match_result

	spectate = HungrySpectate.new()
	spectate.name = "Spectate"
	add_child(spectate)

	var watching := spectate.setup(self)

	if not watching.ok:
		# Not fatal. A world with no spectator camera is the world this game has had
		# since it was written; saying so and carrying on is better than refusing to
		# start a round over where a dead player's camera points.
		DotLog.warn(CHANNEL, "spectating is off", {"why": watching.error.message})
		remove_child(spectate)
		spectate.queue_free()
		spectate = null

	_build_player_stack()

	if register_service:
		_registered_name = (
			DotRegistry.scoped_name(SERVICE, service_scope)
			if service_scope != &""
			else SERVICE
		)
		DotRegistry.register(_registered_name, self)

	return DotResult.success(null)


## Stands up the player-facing addons and binds them to this world.
func _build_player_stack() -> void:
	player_stack = HungryPlayerStack.new()
	player_stack.name = "PlayerStack"
	# A client mirrors what the server decided. It never applies a physics profile: its
	# tick rate is the server's, and a client counting at a different one would predict
	# a monster's mass against a schedule the server does not use.
	player_stack.apply_physics = is_authority
	player_stack.register_service = register_service
	add_child(player_stack)

	var res := player_stack.setup(self)

	if not res.ok:
		DotLog.warn(CHANNEL, "the player stack is off", {"why": res.error.message})
		remove_child(player_stack)
		player_stack.queue_free()
		player_stack = null


func _build_match() -> DotResult:
	var rules := HungryContent.rules(tick_rate)
	rules.mass_to_win = preset.win_mass
	rules.time_limit_sec = preset.time_limit_sec
	# The win condition is mass, and dot-match cannot know what mass is. This is the
	# whole of that bridge.
	rules.mass_fn = func(key: String) -> float:
		var monster := monster_for(int(key))
		return monster.mass() if monster != null else 0.0

	match_node = DotMatch.new()
	match_node.name = "Match"
	match_node.rules = rules
	match_node.register_service = false
	# Its own point only. Left to look for itself the match collects every spawn point under
	# the current scene, and a solo mode change has the old client's world in the tree beside
	# this one, freed a moment later (dot-match's history: it crashed the engine).
	match_node.spawns_ref = DotNodeRef.of_self()

	var config := DotMatchConfig.new()
	config.tick_rate = tick_rate
	config.auto_start = false
	config.balance_between_rounds = false
	config.idle_seconds = 0.0
	match_node.config = config

	# Before the match node enters the tree: [method DotMatch.refresh_spawns] runs from
	# `_ready` and warns when it finds nothing, so a point added afterwards silences every
	# respawn but not the one at startup.
	_add_spawn_point()
	add_child(match_node)

	match_node.respawn_due.connect(_on_respawn_due)
	match_node.state_changed.connect(
		func(from: DotMatch.State, to: DotMatch.State) -> void:
			# Reset first, announce afterwards: a listener told the round started while the old field is still there sends clients a field about to be thrown away,
			# and the new one then arrives as a delta on top of it (clients hold double the food).
			if to == DotMatch.State.LIVE:
				reset_world()

			match_state_changed.emit(from, to)
	)

	return DotResult.success(null)


## Gives dot-match one spawn point, which this game then ignores.
func _add_spawn_point() -> void:
	var point := DotSpawnPoint.new()
	point.name = "Nominal"
	# No cooldown: with one point, a cooldown would make it unavailable for two seconds
	# after every respawn and put the warning straight back.
	point.cooldown_ticks = 0
	match_node.add_child(point)


func start(tick: int = 0) -> void:
	_tick = tick
	match_node.start(tick)


## Puts the world back to its starting state. What a new round does.
func reset_world() -> void:
	# Through `_destroy_piece`, not by clearing the dictionary: clearing never emits [signal piece_destroyed],
	# which the netcode bridge listens to, so entities stay registered and clients keep the old round's pieces.
	for piece_id in _sorted_piece_ids():
		var piece: HungryPiece = _pieces.get(piece_id)

		if piece != null:
			_destroy_piece(piece)

	_pieces.clear()
	_shots.clear()

	for monster in monsters():
		monster.clear_pieces()
		monster.carried.clear()
		monster.effects.clear()

	# The old field leaves the grid before the new one enters it.
	for grid_id in field.alive_ids():
		arena.grid.remove(grid_id)

	# A fresh seed per round, so a server that has been up all night is not laying the
	# same field out for the hundredth time and the regulars have not learnt it.
	field.reseed(world_seed + match_node.round_number)
	_cull_blocked(field.fill_all())
	field.populate(arena.grid)
	field_changed.emit()


## Adopts the authority's world size. Client side, from the hello.
func adopt_world_size(size: Vector2) -> void:
	if size.x <= 1.0 or size.y <= 1.0 or size.is_equal_approx(world_size):
		return

	world_size = size
	arena.bounds = Rect2(-size * 0.5, size)

	if arena.body != null:
		arena.body.bounds = arena.bounds

	field.set_bounds(arena.bounds)

	DotLog.debug(CHANNEL, "adopted the authority's world size", {"size": size})


## Which variant of the layout to build: this world's own, then the operator's cvar, then the preset's.
## The cvar is read through the registry (none offline) and registered after the first world, so it takes effect from the next mode change.
func _chosen_layout_variant() -> String:
	if layout_variant != "":
		return layout_variant
	var console: Object = DotRegistry.get_service(&"dot_console")
	if console != null and console.has_method("get_string"):
		var operator := str(console.call("get_string", "hungry_warrens_corners", "")).strip_edges().to_lower()
		if HungryLayout.CORNER_VARIANTS.has(operator):
			return "" if operator == HungryLayout.CORNER_DEFAULT else operator
	return preset.layout_variant


## Adopts the authority's layout. Client side, from the hello.
func adopt_layout(layout_id: StringName) -> void:
	layout = HungryLayout.for_id(layout_id, arena.bounds)

	DotLog.debug(CHANNEL, "adopted the authority's layout", {
		"layout": String(layout_id), "blocks": layout.count(),
	})


## Adopts the authority's field seed and empties the field. Client side.
func adopt_field_seed(new_seed: int) -> void:
	for grid_id in field.alive_ids():
		arena.grid.remove(grid_id)

	field.reseed(new_seed)
	field_changed.emit()


## Applies a field delta. Client side.
func apply_field_delta(
	added: Array,
	removed: Array,
	planted: Dictionary = {}
) -> void:
	for entry in removed:
		arena.grid.remove(int(entry))

	field.apply_delta(added, removed, planted)

	for entry in added:
		var grid_id := int(entry)
		arena.grid.place(grid_id, field.position_of(grid_id), field.radius_of(grid_id))

	# Drained rather than left to accumulate: a client has nobody to send it to, and a
	# delta nothing consumes is a dictionary that grows for the length of the session.
	field.drain_delta()
	field_changed.emit()



func add_player(id: int, display_name: String) -> DotResult:
	if _monsters.has(id):
		return DotResult.fail(DotError.CODE_STATE, "Player %d is already here." % id)

	var monster := HungryMonster.make(id, display_name)
	_monsters[id] = monster

	var added := match_node.add_player(str(id), display_name, _tick)

	if not added.ok:
		_monsters.erase(id)
		return added

	if player_stack != null:
		player_stack.add_player(id, display_name)

	return DotResult.success(monster)


func remove_player(id: int) -> void:
	var monster := monster_for(id)

	if monster == null:
		return

	for piece in monster.pieces.duplicate():
		_destroy_piece(piece)

	if player_stack != null:
		# Before dot-match forgets them: the stack reads the match for the records it
		# files, and after `remove_player` there is nothing there to read.
		player_stack.drop_player(id)

	match_node.remove_player(str(id))
	_monsters.erase(id)


func monster_for(id: int) -> HungryMonster:
	return _monsters.get(id)


func monsters() -> Array[HungryMonster]:
	var out: Array[HungryMonster] = []
	for key in _monsters.keys():
		out.append(_monsters[key])
	return out


func player_ids() -> Array[int]:
	var out: Array[int] = []
	for key in _monsters.keys():
		out.append(int(key))
	out.sort()
	return out


func piece_for(piece_id: int) -> HungryPiece:
	return _pieces.get(piece_id)


func pieces() -> Array[HungryPiece]:
	var out: Array[HungryPiece] = []
	for key in _sorted_piece_ids():
		out.append(_pieces[key])
	return out


func piece_count() -> int:
	return _pieces.size()


func projectiles() -> Array[HungryProjectile]:
	var out: Array[HungryProjectile] = []
	var keys := _shots.keys()
	keys.sort()
	for key in keys:
		out.append(_shots[key])
	return out


## Puts a player in the world with one piece.
func spawn(id: int, at: Vector2 = Vector2.INF) -> void:
	var monster := monster_for(id)

	if monster == null:
		return

	for piece in monster.pieces.duplicate():
		_destroy_piece(piece)

	monster.clear_pieces()
	monster.effects.clear()

	var position := at if at != Vector2.INF else _safe_spawn(id)
	# The trait trades starting mass against speed, so it is applied here rather than
	# folded into the constant: two players spawn at different sizes and the number a
	# reader looks up is still the one in HungryContent.
	var start := HungryContent.START_MASS * HungryContent.trait_mass(monster.trait_id)
	attach_piece(monster, position, start)

	monster.carried.clear()

	# Everybody spawns holding one of whatever they chose. It is the only mechanical thing
	# the loadout does on the way in, and it is what makes the choice visible in the first
	# ten seconds rather than the first ten minutes.
	monster.take_item(monster.starter_item())

	monster.best_mass = start
	monster.split_ready_tick = _tick
	monster.throw_ready_tick = _tick
	monster.eject_ready_tick = _tick
	monster.apply_effect(
		HungryContent.FLAG_PROTECTED,
		_tick + match_node.spawn_protection_ticks()
	)

	player_spawned.emit(id)


## A spawn position with nobody big enough to eat you standing on it.
func _safe_spawn(id: int) -> Vector2:
	# [b]The director first, and it is the same rule rather than a different one.[/b]
	if player_stack != null:
		var chosen := player_stack.choose_spawn(id)

		if chosen.ok:
			var at3 := (chosen.value as DotSpawnChoice).transform.origin
			return _clear_of_layout(Vector2(at3.x, at3.y))

	var start_radius := tunables.mass_rules.radius_for(HungryContent.START_MASS)

	for attempt in range(14):
		var candidate := arena.spawn_position(id * 977 + attempt + _tick, 240.0)
		var threats := arena.overlapping(candidate, start_radius * 7.0)
		var dangerous := false

		for other_id in threats:
			if other_id >= HungryField.PIECE_ID_LIMIT:
				continue

			var piece: HungryPiece = _pieces.get(other_id)

			if piece != null and piece.mass() > HungryContent.START_MASS:
				dangerous = true
				break

		if not dangerous:
			return _clear_of_layout(candidate)

	# Every candidate was dangerous, which on a very full server is possible. Spawning
	# somewhere bad beats not spawning: the alternative is a player who watches.
	return _clear_of_layout(arena.spawn_position(id, 240.0))


## Moves a spawn out of the level's geometry, if it landed in it.
func _clear_of_layout(at: Vector2) -> Vector2:
	if layout == null or layout.is_empty():
		return at

	var start_radius := tunables.mass_rules.radius_for(HungryContent.START_MASS)
	return layout.nearest_clear(at, start_radius, arena.bounds)



## Creates a piece and registers it with the arena.
func attach_piece(
	monster: HungryMonster,
	at: Vector2,
	mass: float,
	forced_id: int = 0
) -> HungryPiece:
	var piece_id := forced_id

	if piece_id <= 0:
		piece_id = _next_piece_id
		_next_piece_id += 1
	else:
		_next_piece_id = maxi(_next_piece_id, piece_id + 1)

	var piece := HungryPiece.make(
		piece_id, monster.id, at, mass, tunables.mass_rules, _tick
	)

	monster.add_piece(piece)
	_pieces[piece.id] = piece
	arena.register(piece.id, piece.state)

	if is_authority:
		monster.flags = monster.effect_flags(_tick)
		Dot2DAdminModifiers.adopt(piece.state, monster.admin)

	_apply_flags(monster, piece)

	piece_created.emit(piece)
	return piece


func _destroy_piece(piece: HungryPiece) -> void:
	arena.forget(piece.id)
	_pieces.erase(piece.id)

	var monster := monster_for(piece.owner_id)

	if monster != null:
		monster.remove_piece(piece.id)

	piece_destroyed.emit(piece)


## Changes a piece's mass and puts it back inside the world.
func _grow(piece: HungryPiece, mass: float) -> void:
	if outgrown == Outgrown.CAP and mass > piece.mass():
		mass = _mass_that_fits(piece, mass)

	piece.set_mass(mass, tunables.mass_rules)
	piece.state.position = arena.clamp_position(piece.state.position, piece.radius())


## How deep [param piece] would sit in a rock at [param mass], where it stands, after the
## push-out and the arena clamp a tick would give it. 0 when it fits.
func wedged_depth(piece: HungryPiece, mass: float = -1.0) -> float:
	if layout == null or layout.is_empty():
		return 0.0
	var radius := piece.radius() if mass < 0.0 else tunables.mass_rules.radius_for(mass)
	var probe := Dot2DState.new()
	probe.position = piece.state.position
	var _moved := layout.resolve_circle(probe, radius)
	probe.position = arena.clamp_position(probe.position, radius)
	return layout.depth_in_rocks(probe.position, radius)


## `cap`: the most of [param wanted] the piece can have and still fit where it stands, or its
## mass now if it is already wedged. Bisected, because growth is continuous and a piece in a
## room is not.
func _mass_that_fits(piece: HungryPiece, wanted: float) -> float:
	var now := piece.mass()
	if wedged_depth(piece, wanted) <= WEDGED_DEPTH:
		return wanted
	if wedged_depth(piece, now) > WEDGED_DEPTH:
		return now
	var low := now
	var high := wanted
	for i in 12:
		var mid := (low + high) * 0.5
		if wedged_depth(piece, mid) <= WEDGED_DEPTH:
			low = mid
		else:
			high = mid
	return low


## `eject`: every wedged piece sheds what it cannot fit as food behind it, down to what
## fits, a pellet's worth a tick so it reads as squeezing out rather than vanishing. On the
## authority, after the moves.
func _shed_outgrown() -> void:
	if outgrown != Outgrown.EJECT or not is_authority or layout == null or layout.is_empty():
		return

	for piece: HungryPiece in _pieces.values():
		if wedged_depth(piece) <= WEDGED_DEPTH or piece.mass() <= HungryContent.EJECT_MIN_MASS:
			continue
		# A pellet a tick for as long as it is wedged, not down to a size worked out once: a
		# player steering into the corner stays wedged at a size that would fit standing
		# still, and shedding stops only when it actually fits.
		var shed := minf(HungryContent.EJECT_MASS, piece.mass() - HungryContent.EJECT_MIN_MASS)
		if shed <= 0.0:
			continue
		_grow(piece, piece.mass() - shed)
		var placed := field.plant(
			arena.clamp_position(piece.position(), HungryContent.FOOD_TIER_RADIUS[HungryContent.EJECT_TIER]),
			1, HungryContent.EJECT_TIER, arena.bounds)
		for grid_id in placed:
			arena.grid.place(grid_id, field.position_of(grid_id), field.radius_of(grid_id))
		if not placed.is_empty():
			field_changed.emit()


## Takes a piece out of the world because something that is not a player ate it.
func devour_piece(piece_id: int, from: Vector2 = Vector2(NAN, NAN)) -> bool:
	var piece: HungryPiece = _pieces.get(piece_id)

	if piece == null:
		return false

	var monster := monster_for(piece.owner_id)
	var lost := piece.mass()
	var where := piece.position()

	_destroy_piece(piece)

	# The death is announced the same way an eat announces one. Without this a player
	# whose last piece a hunter took is `alive == false` with nothing having said so, so
	# the respawn queue never runs and they watch an empty arena for ever.
	if monster != null and monster.piece_count() == 0 and monster.alive:
		monster.alive = false
		# Away from whatever took it, when the caller said where that was (a hunter does);
		# an admin's slay has no direction and the seed picks one.
		var away := where - from if not is_nan(from.x) else Vector2.ZERO
		monster.death = decide_death(monster.id, false, 0.0, lost, away)
		player_died.emit(monster.id, 0)

	piece_eaten.emit(0, piece.owner_id, lost)
	return true


## Adds mass to somebody's biggest piece, because they ate something the world owns.
func feed_player(player_id: int, mass: float) -> bool:
	var monster := monster_for(player_id)

	if monster == null or not monster.alive:
		return false

	var biggest := monster.rider_piece()

	if biggest == null:
		return false

	_grow(biggest, biggest.mass() + mass)
	monster.best_mass = maxf(monster.best_mass, monster.mass())
	return true



## Advances the whole world one tick. The authority's entry point.
func tick(commands: Dictionary = {}) -> void:
	_tick += 1

	var delta := 1.0 / float(tick_rate)

	_expire_effects()
	_simulate_monsters(commands, delta)
	arena.sync_grid()

	if not is_authority:
		return

	_resolve_field()
	_resolve_pieces()
	_resolve_merges()
	_resolve_projectiles()
	_refill_field()

	_sync_flags()
	_sync_scores()

	# Before the match, which is where every per-tick observer in this world goes: the
	# camera has to be looking at where this tick left everybody, and a match that ended
	# the round first would have taken them all away.
	if spectate != null:
		spectate.tick(delta)

	if player_stack != null:
		player_stack.tick(_tick)

	match_node.tick(_tick)


## Advances the parts of the world a client owns. Called once a tick on a client.
func client_tick(tick_value: int) -> void:
	_tick = tick_value

	_expire_effects()
	arena.sync_grid()

	if spectate != null:
		spectate.tick(1.0 / float(tick_rate))

	for shot in projectiles():
		# A defensive prune only: every resolved projectile sends a reliable impact event, but a client that lost one would draw the shot flying for ever.
		if shot.distance_at(tick_value, tick_rate) > HungryContent.THROW_RANGE * 1.3:
			_shots.erase(shot.id)


## Advances one piece by one tick. The unit of client-side prediction.
func simulate_piece(
	piece: HungryPiece,
	monster: HungryMonster,
	command: Dot2DCommand,
	delta: float,
	tick_value: int
) -> void:
	if piece == null:
		return

	var used := command if command != null else Dot2DCommand.new()

	# What a frame is drawn between: where this tick starts, and where the last one did.
	# Here, on the prediction path, so a replay leaves them as the last replayed tick's.
	piece.drawn_two_back = piece.drawn_from
	piece.drawn_from = piece.state.position

	motor.tunables = _tunables_for(monster, tick_value) if monster != null else tunables
	motor.simulate(
		piece.state,
		command_for_piece(used, piece, pointer_of(monster, used)) if monster != null
			else used,
		delta,
		tick_value
	)
	motor.tunables = tunables
	block_piece(piece)


## Pushes one piece out of the level's geometry. Immediately after the motor, both ends.
func block_piece(piece: HungryPiece) -> bool:
	if piece == null or layout == null or layout.is_empty():
		return false

	# An administrator's noclip is the rocks not being there. Here, and not around the
	# call, because this is the function a client's replay runs: skipped on the server
	# only, every tick inside a rock is a correction back out of it.
	if Dot2DAdminModifiers.is_noclipped(piece.state):
		return false

	if not layout.resolve_circle(piece.state, piece.radius()):
		return false

	# Back inside the arena, because the push-out does not know the wall is there: a piece wider than the gap between a rock and a wall was pushed out through the wall.
	# The motor clamps before this call; the same arena invariant [method _grow] keeps is kept here. Pure, so a client's replay agrees.
	piece.state.position = arena.clamp_position(piece.state.position, piece.radius())
	return true


## Pushes one monster's own pieces apart. Client side, once per tick after predicting.
func separate_local(monster: HungryMonster, delta: float) -> void:
	if monster != null:
		_separate(monster, delta)


func _expire_effects() -> void:
	for monster in monsters():
		monster.expire_effects(_tick)


## Tunables with this monster's current speed multiplier folded in.
func _tunables_for(monster: HungryMonster, tick_value: int) -> Dot2DTunables:
	var multiplier := monster.speed_multiplier(tick_value)

	if is_equal_approx(multiplier, 1.0):
		return tunables

	_scaled.max_speed = tunables.max_speed * multiplier
	return _scaled


## Where the player is pointing, in world units.
static func pointer_of(monster: HungryMonster, command: Dot2DCommand) -> Vector2:
	if monster == null or command == null:
		return Vector2.ZERO

	return monster.centre() + command.aim * command.reach


## One piece's command: the monster's, re-aimed at the pointer from where this piece is.
func command_for_piece(
	command: Dot2DCommand,
	piece: HungryPiece,
	pointer: Vector2
) -> Dot2DCommand:
	_piece_command.move = command.move
	_piece_command.buttons = command.buttons

	var offset := pointer - piece.position()

	if offset.length_squared() <= 0.000001:
		_piece_command.aim = Vector2.ZERO
		_piece_command.reach = 0.0
	else:
		_piece_command.aim = offset.normalized()
		_piece_command.reach = minf(offset.length(), HungryNetCommand.MAX_REACH)

	return _piece_command


func _simulate_monsters(commands: Dictionary, delta: float) -> void:
	for id in player_ids():
		var monster: HungryMonster = _monsters[id]

		if not monster.alive:
			continue

		var command: Dot2DCommand = commands.get(id)

		if command == null:
			command = (
				monster.last_command if monster.last_command != null
				else Dot2DCommand.new()
			)
		else:
			# Everything in here came from a client. A move vector of length 40 is not a
			# crash, it is a player who moves forty times as fast as everyone else.
			command.sanitise(1200.0)

		# An administrator's freeze holds the whole monster, and a split, a throw or an
		# eject is movement by another route: a frozen player who could split would cross
		# the arena half a body at a time.
		if is_authority and not Dot2DAdminModifiers.bits_frozen(monster.admin):
			if command.just_pressed(Dot2DCommand.BUTTON_SPLIT, monster.last_command):
				_split(monster, command)

			if command.just_pressed(Dot2DCommand.BUTTON_ACTION, monster.last_command):
				_throw(monster, command)

			if command.just_pressed(Dot2DCommand.BUTTON_EJECT, monster.last_command):
				_eject(monster, command)

		monster.last_command = command.duplicate_command()

		motor.tunables = _tunables_for(monster, _tick)

		var pointer := pointer_of(monster, command)

		for piece in monster.pieces:
			# The monster's admin bits into every piece, every tick, on the authority only.
			if is_authority:
				Dot2DAdminModifiers.adopt(piece.state, monster.admin)

			# What a frame is drawn between, as [method simulate_piece] records it: offline
			# every monster is simulated here, the bots included.
			piece.drawn_two_back = piece.drawn_from
			piece.drawn_from = piece.state.position

			motor.simulate(
				piece.state, command_for_piece(command, piece, pointer), delta, _tick
			)
			block_piece(piece)

		_separate(monster, delta)

	motor.tunables = tunables
	_shed_outgrown()


## Keeps a monster's own pieces from sitting inside each other before they may merge.
func _separate(monster: HungryMonster, delta: float) -> void:
	if monster.pieces.size() < 2:
		return

	for a in range(monster.pieces.size()):
		for b in range(a + 1, monster.pieces.size()):
			var first := monster.pieces[a]
			var second := monster.pieces[b]

			if first.can_merge(_tick) and second.can_merge(_tick):
				continue

			var offset := second.position() - first.position()
			var distance := offset.length()
			var wanted := first.radius() + second.radius()

			if distance >= wanted:
				continue

			# A dead-centre overlap has no direction to push along, and normalising a
			# zero vector gives zero — which leaves two pieces fused for ever. The
			# fallback is arbitrary and deterministic, which is all it has to be.
			var away := (
				offset / distance if distance > 0.0001
				else Vector2.from_angle(float(first.id) * 0.7)
			)

			var push := (wanted - distance) * 0.5 * minf(1.0, delta * 12.0)
			first.state.position -= away * push
			second.state.position += away * push

			first.state.position = arena.clamp_position(
				first.state.position, first.radius()
			)
			second.state.position = arena.clamp_position(
				second.state.position, second.radius()
			)



## Food, fruit and item drops. One query per piece over one grid.
func _resolve_field() -> void:
	var rules := tunables.mass_rules
	var touched := false

	for piece_id in _sorted_piece_ids():
		var piece: HungryPiece = _pieces.get(piece_id)

		if piece == null:
			continue

		var monster := monster_for(piece.owner_id)

		if monster == null:
			continue

		# Centres, not circles: a crumb is eaten when the piece covers it, and a circle
		# test would let a monster eat everything its edge merely brushes.
		for grid_id in arena.grid.query_circle(
			piece.position(), piece.radius() * rules.eat_overlap, piece.id
		):
			if not HungryField.is_edible(grid_id):
				continue

			match HungryField.kind_of(grid_id):
				HungryField.Kind.FOOD, HungryField.Kind.PLANTED:
					if _eat_food(monster, piece, grid_id):
						touched = true

				HungryField.Kind.FRUIT:
					if _eat_fruit(monster, piece, grid_id):
						touched = true

				HungryField.Kind.ITEM:
					if _take_item(monster, grid_id):
						touched = true

	if touched:
		field_changed.emit()


func _eat_food(monster: HungryMonster, piece: HungryPiece, grid_id: int) -> bool:
	# The greedy trait is worth more food rather than more mass outright, so it compounds
	# with how much you are already eating instead of being a flat head start.
	var gained := field.mass_of(grid_id) * HungryContent.trait_food(monster.trait_id)

	# take() returning false is food another piece got first on this same tick. Normal,
	# and the reason it returns a bool at all.
	if not field.take(grid_id):
		return false

	arena.grid.remove(grid_id)
	_grow(piece, piece.mass() + gained)

	monster.food_eaten += 1
	monster.best_mass = maxf(monster.best_mass, monster.mass())

	food_eaten.emit(monster.id, grid_id, gained)
	return true


func _eat_fruit(monster: HungryMonster, piece: HungryPiece, grid_id: int) -> bool:
	var kind := field.fruit_kind_of(grid_id)

	if not field.take(grid_id):
		return false

	arena.grid.remove(grid_id)
	_grow(piece, piece.mass() + HungryContent.FRUIT_MASS)

	var until := _tick + int(HungryTuning.settings().fruit_effect_sec * float(tick_rate))

	match kind:
		HungryContent.Fruit.RUSH:
			monster.apply_effect(HungryContent.FLAG_RUSH, until)
		HungryContent.Fruit.MAW:
			monster.apply_effect(HungryContent.FLAG_MAW, until)
		HungryContent.Fruit.RIND:
			monster.apply_effect(HungryContent.FLAG_RIND, until)

	monster.fruit_eaten += 1
	monster.best_mass = maxf(monster.best_mass, monster.mass())

	fruit_eaten.emit(monster.id, grid_id, kind)
	return true


## Picks a throwable up. Refused, and left where it is, when the monster is full.
func _take_item(monster: HungryMonster, grid_id: int) -> bool:
	if monster.carried.size() >= HungryContent.MAX_CARRIED:
		return false

	var item := field.item_id_of(grid_id)

	# The catalogue is the authority on what an id means. An unknown one is a content
	# mismatch rather than a legal pickup, and swallowing it silently would hand the
	# player a charge of nothing.
	if items.find(item) == null:
		DotLog.warn(CHANNEL, "item drop names an id the catalogue does not have", {
			"item": String(item)
		})
		return false

	if not field.take(grid_id):
		return false

	arena.grid.remove(grid_id)
	monster.take_item(item)

	item_taken.emit(monster.id, grid_id, item)
	return true


## Monsters eating monsters.
func _resolve_pieces() -> void:
	var rules := tunables.mass_rules
	var eaten := {}

	# Sorted, so two machines resolve the same collisions in the same order (dictionary order is no guarantee).
	# The `eaten` set because one piece can be in range of two eaters on the same tick.
	for piece_id in _sorted_piece_ids():
		if eaten.has(piece_id):
			continue

		var piece: HungryPiece = _pieces.get(piece_id)

		if piece == null:
			continue

		var eater := monster_for(piece.owner_id)

		if eater == null or eater.has_effect(HungryContent.FLAG_PROTECTED, _tick):
			continue

		# The maw fruit lowers the ratio rather than raising the eater's mass: raising
		# the mass would also make them slower and wider, which is not what eating a
		# fruit called "maw" should do.
		var ratio := rules.eat_ratio * eater.eat_ratio_multiplier(_tick)

		for other_id in arena.grid.query_circle(
			piece.position(), piece.radius() * rules.eat_overlap, piece.id
		):
			if other_id >= HungryField.PIECE_ID_LIMIT or eaten.has(other_id):
				continue

			var victim: HungryPiece = _pieces.get(other_id)

			if victim == null or victim.owner_id == piece.owner_id:
				continue

			var prey := monster_for(victim.owner_id)

			if prey == null or prey.has_effect(HungryContent.FLAG_PROTECTED, _tick):
				continue

			if not can_be_harmed(prey.id):
				continue

			if piece.mass() < victim.mass() * ratio:
				continue

			if piece.position().distance_to(victim.position()) \
					> piece.radius() * rules.eat_overlap:
				continue

			eaten[other_id] = true
			_absorb(piece, victim, rules)


## Whether [param player_id] may be eaten, burst, hit or hunted now. False only while their
## client is behind its loading cover; a bot or a world with no [member loading_fn] is always
## harmable, so a suite that never connects a client is unchanged.
func can_be_harmed(player_id: int) -> bool:
	if not loading_fn.is_valid():
		return true
	return not bool(loading_fn.call(player_id))


func _absorb(eater: HungryPiece, victim: HungryPiece, rules: Dot2DMassRules) -> void:
	var gained := victim.mass()
	# Before the eater grows: how many times the victim's size it was is how hard it hit.
	var ratio := eater.mass() / maxf(gained, 0.001)
	var away := victim.position() - eater.position()

	_grow(eater, rules.absorb(eater.mass(), gained))

	var eater_monster := monster_for(eater.owner_id)
	var victim_monster := monster_for(victim.owner_id)

	if eater_monster != null:
		eater_monster.best_mass = maxf(eater_monster.best_mass, eater_monster.mass())

	piece_eaten.emit(eater.owner_id, victim.owner_id, gained)

	_destroy_piece(victim)

	if victim_monster != null and not victim_monster.alive:
		if eater_monster != null:
			eater_monster.players_eaten += 1

		# The victim's last piece. dot-match records the kill, the death and the respawn
		# timer; the world only says it happened.
		match_node.report_kill(
			str(eater.owner_id), str(victim.owner_id), &"devoured", _tick
		)
		victim_monster.death = decide_death(
			victim.owner_id, ratio >= SWALLOWED_WHOLE, power_of(ratio), gained, away
		)
		player_died.emit(victim.owner_id, eater.owner_id)



## Eaten by something at least this many times your mass: swallowed whole, which is this
## game's headshot (dot-player-char's `needs_headshot`: the headshot launch).
const SWALLOWED_WHOLE := 4.0

## The mass ratio a [code]death_power[/code] of 0 and of 1 stand for. A power launch needs 0.5,
## so it takes a monster ten times your size.
const POWER_FROM_RATIO := 2.0
const POWER_FULL_RATIO := 18.0


## How powerful an eat was, 0 to 1, from the eater's mass over the victim's.
static func power_of(ratio: float) -> float:
	return clampf((ratio - POWER_FROM_RATIO) / (POWER_FULL_RATIO - POWER_FROM_RATIO), 0.0, 1.0)


## The fall an eaten monster gets: dot-player-char's reaction rule over `sv_ragdoll_reactions`, seeded from the player and tick so every client draws the same one.
## [param mass] is the damage, [param away] the push on the plane. Authority only; a client draws the one that came on DIED.
func decide_death(player_id: int, swallowed: bool, power: float, mass: float, away: Vector2) -> DotPlayerDeath:
	return DotPlayerDeath.decide(
		ragdoll_rules.reactions() if ragdoll_rules != null else DotPlayerDeathReactions.stock(),
		swallowed, mass, Vector3(away.x, 0.0, away.y),
		DotPlayerDeath.seed_of(player_id, _tick), null, power
	)


## Removes a piece the authority says is gone. Client side.
func forget_piece(piece_id: int) -> void:
	var piece := piece_for(piece_id)

	if piece != null:
		_destroy_piece(piece)


func _sorted_piece_ids() -> Array[int]:
	var out: Array[int] = []

	for key in _pieces.keys():
		out.append(int(key))

	out.sort()
	return out



## Halves every eligible piece and throws one half along the aim.
func _split(monster: HungryMonster, command: Dot2DCommand) -> int:
	var rules := tunables.mass_rules

	if _tick < monster.split_ready_tick or command.aim == Vector2.ZERO:
		return 0

	var made := 0
	# A copy: the loop adds pieces, and iterating the live array would split the pieces
	# it has just created — which halves everything twice in one press.
	var existing: Array[HungryPiece] = monster.pieces.duplicate()

	for piece in existing:
		if monster.piece_count() >= rules.max_pieces:
			break

		if not rules.can_split(piece.mass(), monster.piece_count()):
			continue

		var half := piece.mass() * 0.5
		piece.set_mass(half, rules)

		var offset := command.aim.normalized() * (piece.radius() + 2.0)
		var child := attach_piece(
			monster,
			arena.clamp_position(piece.position() + offset, rules.radius_for(half)),
			half
		)

		motor.impulse(child.state, command.aim, rules.split_impulse)
		_delay_merge(piece, child)

		made += 1

	if made > 0:
		monster.split_ready_tick = _tick + HungryContent.SPLIT_COOLDOWN_TICKS

	return made


## Blows a monster apart. What a pepper does.
func burst(monster: HungryMonster, by_player: int, into: int = 0) -> int:
	if monster == null or not monster.alive:
		return 0

	# The rind fruit is spent stopping one burst rather than reducing it. A fruit that
	# made a burst smaller would be invisible; one that eats it outright is a thing a
	# player can feel they got value from.
	if monster.has_effect(HungryContent.FLAG_RIND, _tick):
		monster.clear_effect(HungryContent.FLAG_RIND)
		return 0

	var rules := tunables.mass_rules
	var made := 0
	var existing: Array[HungryPiece] = monster.pieces.duplicate()

	for piece in existing:
		if monster.piece_count() >= rules.max_pieces:
			break

		if piece.mass() < HungryContent.MIN_BURST_MASS:
			continue

		var room := rules.max_pieces - monster.piece_count() + 1
		# How many pieces; zero means "the usual". [HungryCombat] turns a resolved damage amount into it, so falloff stays dot-combat's.
		# Zero rather than a default so a caller with no opinion says so.
		var wanted := into if into >= 2 else HungryContent.PEPPER_PIECES
		var pieces := mini(wanted, room)

		if pieces < 2:
			continue

		var share := piece.mass() / float(pieces)
		var origin := piece.position()
		piece.set_mass(share, rules)

		for step in range(1, pieces):
			# Radial, and seeded from the piece id so two machines that replay this tick
			# scatter the pieces the same way.
			var angle := TAU * float(step) / float(pieces) + float(piece.id) * 0.37
			var direction := Vector2.from_angle(angle)
			var at := arena.clamp_position(
				origin + direction * (piece.radius() + 3.0), rules.radius_for(share)
			)

			var child := attach_piece(monster, at, share)
			child.state.set_flag(HungryContent.FLAG_BURST, true)

			motor.impulse(child.state, direction, rules.split_impulse * 0.85)
			_delay_merge(piece, child)

			made += 1

	if made > 0:
		monster.times_burst += 1
		monster_burst.emit(monster.id, by_player, made)

	return made


## Both halves get the merge delay, not just the new one.
func _delay_merge(parent: HungryPiece, child: HungryPiece) -> void:
	var delay := int(tunables.mass_rules.merge_delay_sec * float(tick_rate))
	parent.merge_tick = _tick + delay
	child.merge_tick = _tick + delay


## Merges a monster's own pieces back together once their delay has passed.
func _resolve_merges() -> void:
	for monster in monsters():
		if monster.piece_count() < 2:
			continue

		var merged := true

		# Repeated until nothing changes: three pieces in a pile merge two at a time, and
		# a single pass would leave the third for the next tick — which looks like a
		# merge that stutters.
		while merged:
			merged = false

			for a in range(monster.pieces.size()):
				for b in range(a + 1, monster.pieces.size()):
					var first := monster.pieces[a]
					var second := monster.pieces[b]

					if not first.can_merge(_tick) or not second.can_merge(_tick):
						continue

					var distance := first.position().distance_to(second.position())

					if distance > maxf(first.radius(), second.radius()):
						continue

					var keeper := first if first.mass() >= second.mass() else second
					var absorbed := second if keeper == first else first

					_grow(keeper, keeper.mass() + absorbed.mass())
					keeper.state.set_flag(HungryContent.FLAG_BURST, false)
					_destroy_piece(absorbed)

					merged = true
					break

				if merged:
					break



## Throws the oldest carried item along the aim.
func _throw(monster: HungryMonster, command: Dot2DCommand) -> HungryProjectile:
	if _tick < monster.throw_ready_tick or command.aim == Vector2.ZERO:
		return null

	if monster.carried.is_empty():
		return null

	var rider := monster.rider_piece()

	if rider == null:
		return null

	var item := monster.spend_item()
	monster.throw_ready_tick = _tick + HungryTuning.settings().throw_cooldown_ticks

	# Aimed from the rider at the pointer, not along the monster's own aim: the aim is
	# measured from the centroid, and after a burst the centroid is empty space several
	# hundred units from the piece the throw actually comes out of.
	var pointer := pointer_of(monster, command)
	var offset := pointer - rider.position()
	var direction := offset.normalized() if offset.length_squared() > 0.000001 \
		else command.aim.normalized()
	var origin := rider.position() + direction * (rider.radius() + HungryContent.THROW_RADIUS)

	var shot := HungryProjectile.make(
		_next_shot_id, monster.id, item, origin, direction, _tick
	)
	_next_shot_id += 1
	_shots[shot.id] = shot

	projectile_thrown.emit(shot)
	return shot


## Spits a blob of mass out along the aim.
func _eject(monster: HungryMonster, command: Dot2DCommand) -> int:
	if _tick < monster.eject_ready_tick or command.aim == Vector2.ZERO:
		return 0

	var rider := monster.rider_piece()

	if rider == null or rider.mass() < HungryContent.EJECT_MIN_MASS:
		return 0

	var pointer := pointer_of(monster, command)
	var offset := pointer - rider.position()
	var direction := offset.normalized() if offset.length_squared() > 0.000001 \
		else command.aim.normalized()

	if direction == Vector2.ZERO:
		return 0

	_grow(rider, rider.mass() - HungryContent.EJECT_MASS)
	monster.eject_ready_tick = _tick + HungryContent.EJECT_COOLDOWN_TICKS
	monster.ejected += 1

	var at := rider.position() + direction * (rider.radius() + HungryContent.EJECT_REACH)
	var placed := field.plant(
		arena.clamp_position(at, HungryContent.FOOD_TIER_RADIUS[HungryContent.EJECT_TIER]),
		1,
		HungryContent.EJECT_TIER,
		arena.bounds
	)

	for grid_id in placed:
		arena.grid.place(grid_id, field.position_of(grid_id), field.radius_of(grid_id))

	field_changed.emit()
	return placed.size()


## Mirrors a throw the authority has announced. Client side.
func adopt_projectile(shot: HungryProjectile) -> void:
	if shot == null or shot.id <= 0:
		return

	_shots[shot.id] = shot
	_next_shot_id = maxi(_next_shot_id, shot.id + 1)


## Removes a projectile the authority says has landed. Client side.
func drop_projectile(shot_id: int) -> void:
	_shots.erase(shot_id)


func _resolve_projectiles() -> void:
	for shot in projectiles():
		if shot.resolved:
			continue

		var at := shot.position_at(_tick, tick_rate)

		if not arena.bounds.has_point(at) or shot.expired(_tick, tick_rate):
			_land(shot, arena.clamp_position(at, HungryContent.THROW_RADIUS), 0)
			continue

		# A lure is not aimed at a person and passes through everybody. Resolving it on
		# contact would make it a worse pepper rather than a different item.
		if shot.item == HungryContent.ITEM_LURE:
			continue

		var hit := 0

		for grid_id in arena.grid.query_overlapping(at, HungryContent.THROW_RADIUS):
			if grid_id >= HungryField.PIECE_ID_LIMIT:
				continue

			var piece: HungryPiece = _pieces.get(grid_id)

			if piece == null or piece.owner_id == shot.thrower_id:
				continue

			var victim := monster_for(piece.owner_id)

			if victim == null or victim.has_effect(HungryContent.FLAG_PROTECTED, _tick):
				continue

			hit = piece.owner_id
			break

		if hit != 0:
			_land(shot, at, hit)


func _land(shot: HungryProjectile, at: Vector2, hit_player: int) -> void:
	shot.resolved = true
	_shots.erase(shot.id)

	# What a throwable does to a person, asked of whatever the host installed.
	var pieces := 0

	if hit_player != 0 and not can_be_harmed(hit_player):
		# Spent and announced like a refusal: the thrower sees it land and nothing happens.
		projectile_impact.emit(shot, at, 0)
		return

	if hit_player != 0 and damage_gate.is_valid():
		var verdict: Variant = damage_gate.call(
			shot.thrower_id, hit_player, shot.item, shot.origin.distance_to(at)
		)

		if verdict is Dictionary:
			if not bool((verdict as Dictionary).get("allowed", true)):
				# Refused: too far, or a rule said no. The projectile is still spent and
				# still announced, so a client draws the impact — a throw that vanished
				# would read as the item not working.
				projectile_impact.emit(shot, at, 0)
				return

			pieces = int((verdict as Dictionary).get("pieces", 0))

	match shot.item:
		HungryContent.ITEM_PEPPER:
			if hit_player != 0:
				burst(monster_for(hit_player), shot.thrower_id, pieces)

		HungryContent.ITEM_FROST:
			if hit_player != 0:
				var victim := monster_for(hit_player)
				if victim != null:
					victim.apply_effect(
						HungryContent.FLAG_FROSTED,
						_tick + int(HungryTuning.settings().frost_sec * float(tick_rate))
					)

		HungryContent.ITEM_LURE:
			for grid_id in field.plant(
				at,
				HungryTuning.settings().lure_food_count,
				HungryContent.LURE_FOOD_TIER,
				arena.bounds
			):
				arena.grid.place(
					grid_id, field.position_of(grid_id), field.radius_of(grid_id)
				)
			field_changed.emit()

	projectile_impact.emit(shot, at, hit_player)



## Takes back every slot that landed inside the level's own geometry.
func _cull_blocked(ids: Array[int]) -> Array[int]:
	if layout == null or layout.is_empty() or not is_authority:
		return ids

	var kept: Array[int] = []

	for grid_id in ids:
		if layout.blocked(field.position_of(grid_id), field.radius_of(grid_id)):
			field.take(grid_id)
		else:
			kept.append(grid_id)

	return kept


func _refill_field() -> void:
	var placed := _cull_blocked(field.refill())

	for grid_id in placed:
		arena.grid.place(grid_id, field.position_of(grid_id), field.radius_of(grid_id))

	if not placed.is_empty():
		field_changed.emit()


## Copies each monster's effect bits onto its pieces, and marks the rider.
func _sync_flags() -> void:
	for monster in monsters():
		monster.flags = monster.effect_flags(_tick)

		var rider := monster.rider_piece()

		for piece in monster.pieces:
			_apply_flags(monster, piece, rider)


func _apply_flags(
	monster: HungryMonster,
	piece: HungryPiece,
	rider: HungryPiece = null
) -> void:
	var carrier := rider if rider != null else monster.rider_piece()
	var bits := monster.flags

	if carrier != null and carrier.id == piece.id:
		bits |= HungryContent.FLAG_RIDER

	if piece.can_merge(_tick):
		bits |= HungryContent.FLAG_MERGE_READY

	if piece.state.has_flag(HungryContent.FLAG_BURST):
		bits |= HungryContent.FLAG_BURST

	piece.state.flags = bits


## Keeps the scoreboard's score in step with mass.
func _sync_scores() -> void:
	for monster in monsters():
		var record := match_node.scoreboard.find(str(monster.id))

		if record != null:
			record.score = int(monster.mass())


func _on_respawn_due(key: String, _spawn: DotSpawnPoint, _tick_value: int) -> void:
	spawn(int(key))



## Everything a player should be told about: pieces and food in their view.
func interest_for(player_id: int, limit: int = 420) -> Array[int]:
	var monster := monster_for(player_id)

	if monster == null or not monster.alive:
		return []

	var origin := monster.centre()
	var extent := arena.interest_extent * maxf(1.0, monster.spread_radius() / 95.0)

	var found := arena.grid.query_rect(Rect2(origin - extent, extent * 2.0))

	if found.size() <= limit:
		return found

	var near: Array[int] = []
	var far: Array[int] = []

	for grid_id in found:
		if grid_id < HungryField.PIECE_ID_LIMIT:
			near.append(grid_id)
		else:
			far.append(grid_id)

	if near.size() >= limit:
		return near.slice(0, limit)

	var out := near
	out.append_array(far.slice(0, limit - near.size()))
	return out


func leaderboard(count: int = 10) -> Array[HungryMonster]:
	var ranked := monsters()

	ranked.sort_custom(func(a: HungryMonster, b: HungryMonster) -> bool:
		if not is_equal_approx(a.mass(), b.mass()):
			return a.mass() > b.mass()
		# Ties on the id, so two machines produce the same order. A leaderboard whose
		# rows swap for no reason is the classic symptom of an unstable sort.
		return a.id < b.id
	)

	return ranked.slice(0, count)


func current_tick() -> int:
	return _tick


func set_tick(value: int) -> void:
	_tick = value


func describe() -> Dictionary:
	return {
		"tick": _tick,
		"authority": is_authority,
		"players": _monsters.size(),
		"pieces": _pieces.size(),
		"shots": _shots.size(),
		"field": field.describe() if field != null else {},
		"layout": layout.describe() if layout != null else {},
		"arena": arena.describe() if arena != null else {},
		"match": match_node.describe() if match_node != null else {},
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("hungry   tick %d, %d pieces, %d in flight" % [
		_tick, _pieces.size(), _shots.size()
	])

	if field != null:
		out.append("field    %d food (%d planted), %d fruit, %d drops" % [
			field.food_count(), field.planted_count(),
			field.fruit_count(), field.item_count(),
		])

	for monster in leaderboard(8):
		out.append("  %-16s %8.0f  %d pieces  %-14s%s" % [
			monster.display_name.substr(0, 16),
			monster.mass(),
			monster.piece_count(),
			"+".join(monster.carried_names()),
			"" if monster.alive else "  (dead)",
		])

	return out
