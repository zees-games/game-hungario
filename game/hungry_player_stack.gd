extends Node

const HungryContent := preload("hungry_content.gd")
const HungryField := preload("hungry_field.gd")
const HungryPiece := preload("hungry_piece.gd")
const HungryTuning := preload("hungry_tuning.gd")
const HungryWorld := preload("hungry_world.gd")

## The player-facing addons, stood up once and bound to the 2D arena.

const CHANNEL := "hungry.stack"

const SERVICE := &"hungry_player_stack"

@export var register_service: bool = true

@export var apply_physics: bool = true

var world: HungryWorld = null

var physics: DotPhysicsWorld = null
var roster: DotPlayerRoster = null
var teams: DotTeamRoster = null
var classes: DotPlayerClassManager = null
var characters: DotPlayerCharCatalogue = null
var spawns: DotSpawnDirector = null

var _registered: bool = false


func setup(p_world: HungryWorld) -> DotResult:
	if p_world == null:
		return DotResult.fail(DotError.CODE_INVALID, "No world to bind to.")

	if p_world.match_node == null:
		return DotResult.fail(
			DotError.CODE_STATE,
			"HungryWorld is not set up yet.",
			"Call setup() on it first; this reads its match and its field."
		)

	world = p_world

	var built := _build_physics()

	if not built.ok:
		return built

	_build_roster()
	_build_teams()
	_build_characters()
	_build_classes()
	_build_spawns()

	world.player_spawned.connect(_on_player_spawned)
	world.player_died.connect(_on_player_died)

	if register_service:
		DotRegistry.register(SERVICE, self)
		_registered = true

	DotLog.info(CHANNEL, "player stack up", {"tick_rate": world.tick_rate})
	return DotResult.success(null)


func _exit_tree() -> void:
	if _registered:
		DotRegistry.unregister_instance(SERVICE, self)



## Builds the physics node, and applies the engine half of it only where that is wanted.
func _build_physics() -> DotResult:
	physics = DotPhysicsWorld.new()
	physics.name = "Physics"

	# The project's own numbers with only the tick rate changed: this game does not use Godot's physics for anything that matters (dot-2d integrates over a spatial hash, the field is arithmetic).
	physics.profile = DotPhysicsProfile.from_project()
	physics.profile.tick_rate = world.tick_rate

	# The layout is the part worth having. It is inert until a body is classified, and
	# what it buys is that `pickup`, `hazard` and `projectile` stop being bit arithmetic
	# at the call site the day this game grows a `CollisionObject2D`.
	physics.layout = DotPhysicsLayout.top_down_2d()
	physics.register_service = false
	physics.write_layer_names = false
	add_child(physics)

	# The layout alone, so `classify` answers on a client too.
	var built := physics.layout.build()

	if not built.ok:
		return built.wrap("The collision layout")

	if not apply_physics:
		return DotResult.success(null)

	return physics.setup().wrap("hungario's physics profile")


func _build_roster() -> void:
	roster = DotPlayerRoster.new()
	roster.name = "Roster"
	roster.authoritative = world.is_authority
	roster.register_service = false

	var config := DotPlayerConfig.new()
	config.tick_rate = world.tick_rate
	config.max_players = HungryTuning.settings().max_players
	# A round is minutes and a dropped player's mass is the whole game. Holding the seat
	# for two of them is the difference between a reconnect and starting over as a dot.
	config.reconnect_window_sec = 120.0
	roster.config = config
	add_child(roster)


func _build_teams() -> void:
	teams = DotTeamRoster.new()
	teams.name = "Teams"
	teams.authoritative = world.is_authority
	teams.register_service = false
	# Free-for-all is ONE playing side, not none. Modelled as none, every consumer has
	# to branch on whether teams exist, and the branch nobody writes is the one that
	# matters — here it would be "can I eat this", which is the entire game.
	teams.teams = DotTeamSet.free_for_all()
	teams.policy = DotTeamPolicy.free_for_all()
	teams.policy.tick_rate = world.tick_rate
	teams.alive_fn = _alive_of_key
	add_child(teams)

	var res := teams.setup()

	if not res.ok:
		DotLog.error(CHANNEL, "team roster", {"why": res.error.message})


func _build_characters() -> void:
	# In pixels, not metres: dot-player-char's metrics are unit-agnostic, and a monster's "height" is a radius on a screen.
	characters = DotPlayerCharCatalogue.sprite_2d(HungryContent.CELL_SIZE)
	var res := characters.build()

	if not res.ok:
		DotLog.error(CHANNEL, "character catalogue", {"why": res.error.message})


func _build_classes() -> void:
	classes = DotPlayerClassManager.new()
	classes.name = "Classes"
	classes.authoritative = world.is_authority
	classes.register_service = false
	classes.catalogue = _trait_catalogue()
	# Traits are picked before a round and change what a monster is; changing one mid-life would change its mass rules, which `apply_on_respawn` exists for. A life ends when you are eaten, so the next spawn is the boundary.
	classes.rules = DotPlayerClassRules.standard()
	classes.team_fn = func(key: String) -> StringName: return teams.team_of(key)
	classes.alive_fn = _alive_of_key
	add_child(classes)

	var res := classes.setup()

	if not res.ok:
		DotLog.error(CHANNEL, "class manager", {"why": res.error.message})


## Hungario's traits, as a class catalogue a server can check.
func _trait_catalogue() -> DotPlayerClassCatalogue:
	var cat := DotPlayerClassCatalogue.new()
	cat.id = &"hungry_traits"

	# Read off HungryContent.TRAIT_IDS rather than listed here. A trait added to the
	# game and forgotten in this file would be a trait a player can hold and the class
	# manager refuses, which presents as "my perk does nothing" on one server only.
	for trait_id in HungryContent.TRAIT_IDS:
		var def := DotPlayerClassDef.make(
			trait_id, 100.0, HungryContent.trait_speed(trait_id)
		)
		def.description = "A hungario trait."
		# The mass ratio the trait actually carries, so the document is the whole trait
		# rather than the half of it that happened to fit `make`.
		def.mass = HungryContent.trait_mass(trait_id) * 100.0
		def.attributes = {"food_scale": HungryContent.trait_food(trait_id)}
		cat.classes.append(def)

	cat.default_class = HungryContent.TRAIT_NIMBLE

	var res := cat.build()

	if not res.ok:
		# Falls back rather than leaving the manager with nothing: a catalogue that
		# fails to build is a content mistake, and a session where nobody can be any
		# class at all is a worse answer than one class for everybody.
		DotLog.error(CHANNEL, "trait catalogue", {"why": res.error.message})
		return DotPlayerClassCatalogue.single(100.0)

	return cat


func _build_spawns() -> void:
	spawns = DotSpawnDirector.new()
	spawns.name = "Spawns"
	spawns.tick_rate = world.tick_rate
	spawns.register_service = false
	spawns.rules = DotSpawnRules.deathmatch()
	spawns.rules.seed_value = 0x4E55
	# [b]Distance from EVERY other monster, because in hungario everybody is dangerous
	# to somebody.[/b] There are no sides, so the enemy list is the whole field — which
	# is the honest answer here and is why the selector is asked for distance at all.
	spawns.enemies_fn = _other_positions
	# The rule `_safe_spawn` applied by hand: what kills a new monster is somebody near and bigger, a mass ratio the scoring cannot express,
	# so it is a veto rather than a penalty, as dot-spawn's docs say a distance that is death should be.
	var safety := SiteIsNotDeadly.new()
	safety.danger_fn = _bigger_monster_near
	spawns.conditions = [safety]
	spawns.rules.protection_sec = 0.0
	add_child(spawns)

	refresh_spawn_rules()
	refresh_spawns()


## Lays a grid of sites over the field.
func refresh_spawns() -> void:
	if spawns == null or world == null:
		return

	spawns.clear_sites()

	var half := world.world_size * 0.5
	var steps := 5

	for x in range(steps):
		for y in range(steps):
			# Inset by half a cell so no site sits exactly on the boundary, where a
			# monster with any size at all would be spawned half outside the arena.
			var at := Vector2(
				lerpf(-half.x, half.x, (float(x) + 0.5) / float(steps)),
				lerpf(-half.y, half.y, (float(y) + 0.5) / float(steps))
			)
			var site := DotSpawnSite.point(
				StringName("cell_%d_%d" % [x, y]), Vector3(at.x, at.y, 0.0)
			)
			site.is_2d = true
			spawns.add_site(site)

	DotLog.debug(CHANNEL, "spawn sites", {"count": spawns.sites().size()})



## Adds somebody to every record. Call from `HungryWorld.add_player`.
func add_player(id: int, display_name: String) -> void:
	if not roster.authoritative:
		return

	var key := str(id)
	var res := roster.join(key, display_name, id, world.current_tick())

	if not res.ok:
		DotLog.warn(CHANNEL, "player not added to the roster", {
			"key": key, "why": res.error.message
		})
		return

	var _team := teams.add(key, world.current_tick())
	var _class := classes.add(key)
	var _char := roster.set_char(key, &"sprite")


## Drops somebody. Call from `HungryWorld.remove_player`.
func drop_player(id: int) -> void:
	if not roster.authoritative:
		return

	var key := str(id)
	spawns.cancel_respawn(key)
	classes.remove(key)
	var _left := teams.remove(key)
	var _held := roster.note_disconnected(key, world.current_tick())


func _on_player_spawned(id: int) -> void:
	if not roster.authoritative:
		return

	var key := str(id)
	# Before the alive flag, so anything reading the class in an `alive_changed`
	# handler reads the one this life is being started with.
	var _landed := classes.apply_pending(key)
	var _alive := roster.set_alive(key, true)


func _on_player_died(id: int, _killer: int) -> void:
	if not roster.authoritative:
		return

	var _dead := roster.set_alive(str(id), false)


## One tick of what this node runs on its own.
func tick(current_tick: int) -> void:
	if not roster.authoritative:
		return

	var _dropped := roster.advance(current_tick)

	if spawns.protection != null:
		spawns.protection.advance(current_tick)



## Opens the protection window to the match's own number.
func refresh_spawn_rules() -> void:
	if spawns == null or world == null or world.match_node == null:
		return

	spawns.rules.protection_sec = world.match_node.rules.spawn_protection_sec
	# Off for game-arena's reason: only one of the two records can be revoked, and a
	# protection that ended for one gate and not the other is worse than either answer.
	spawns.rules.protection_breaks_on_attack = false


## Whether spawn protection should stop [param attacker] eating [param victim].
func blocks_damage(
	attacker_key: String, victim_key: String, tick: int, world_damage: bool = false
) -> bool:
	if spawns == null or spawns.protection == null:
		return false

	return spawns.protection.blocks(attacker_key, victim_key, tick, world_damage)


## Where a monster should appear, scored by how far it is from everybody else.
func choose_spawn(id: int) -> DotResult:
	var key := str(id)
	return spawns.choose(
		DotSpawnRequest.make(
			key, teams.team_of(key), classes.class_of(key), world.current_tick()
		)
	)


## The body metrics for a monster, in pixels.
func character() -> DotPlayerCharDef:
	return characters.fallback_for() if characters != null else null



## The dot-spectate team number for [param key], derived from the side they are on.
func team_index_of(key: String) -> int:
	if teams == null:
		return 0

	var side := teams.team_of(key)

	if side == &"" or not teams.teams.is_playing(side):
		return 0

	return teams.teams.playing_ids().find(side) + 1



## Puts [param node] on the layout's [param layer_id] layer, with that layer's mask.
func classify(node: Node, layer_id: StringName) -> DotResult:
	if physics == null or physics.layout == null:
		return DotResult.fail(DotError.CODE_STATE, "No collision layout.")

	return physics.classify(node, layer_id)


## Puts every collision object under [param root] on [param layer_id]. Returns how many.
func classify_tree(root: Node, layer_id: StringName) -> int:
	if root == null or physics == null or physics.layout == null:
		return 0

	var done := 0

	if root is CollisionObject3D or root is CollisionObject2D:
		if classify(root, layer_id).ok:
			done += 1

	for child in root.get_children():
		done += classify_tree(child, layer_id)

	return done


## The mask a player's movement sweeps against, out of the layout.
func player_collision_mask() -> int:
	if physics == null or physics.layout == null:
		return 1

	return physics.layout.collision_mask(&"player")


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("--- player stack")

	if physics != null:
		out.append_array(physics.describe_lines())

	out.append_array(roster.describe_lines())
	out.append_array(teams.describe_lines())
	out.append_array(classes.describe_lines())
	out.append_array(spawns.describe_lines())
	return out


func describe() -> Dictionary:
	return {
		"players": roster.count(),
		"alive": roster.alive_count(),
		"spawn_sites": spawns.sites().size(),
		"traits": classes.catalogue.ids().size(),
	}



func _alive_of_key(key: String) -> bool:
	var monster := world.monster_for(int(key))
	return monster != null and not monster.pieces.is_empty()


## Whether anything big enough to eat a fresh monster is standing near [param at].
func _bigger_monster_near(at: Vector2) -> bool:
	if world == null or world.arena == null:
		return false

	var start_radius := world.tunables.mass_rules.radius_for(HungryContent.START_MASS)

	for other_id in world.arena.overlapping(at, start_radius * 7.0):
		if other_id >= HungryField.PIECE_ID_LIMIT:
			continue

		var piece: HungryPiece = world.piece_for(other_id)

		if piece != null and piece.mass() > HungryContent.START_MASS:
			return true

	return false


## Refuses a site with something big enough to eat you standing on it.
class SiteIsNotDeadly extends DotSpawnCondition:
	## `func(at: Vector2) -> bool`. Left unset, nothing is deadly and every site passes.
	var danger_fn: Callable = Callable()

	func _init() -> void:
		id = &"site_is_not_deadly"

	func allows(site: DotSpawnSite, _context: Dictionary) -> bool:
		if not danger_fn.is_valid():
			return true

		return not bool(danger_fn.call(site.position_2d()))

	func reason() -> String:
		return "something big enough to eat you is standing on it"


func _other_positions(_team: StringName) -> Array:
	var out: Array = []

	for monster in world.monsters():
		if monster.pieces.is_empty():
			continue

		var at := monster.centre()
		out.append(Vector3(at.x, at.y, 0.0))

	return out
