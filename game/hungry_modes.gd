extends RefCounted

## The six modes' dials as configs: one [DotGameConfigBinder] per mode, kind `mode_<id>` (`cfg/game/game-hungario/mode_frenzy/frenzy.yml`), laid over [HungryPreset] by [method preset_for].
##
## A mode scene builds its preset before the module exists, so this is static and loads on first use.

const HungryPreset := preload("hungry_preset.gd")
const HungryModeConfig := preload("hungry_mode_config.gd")

const GAME_ID := "game-hungario"
const IDS: Array[StringName] = [&"classic", &"frenzy", &"gauntlet", &"warrens", &"reef", &"shallows"]

static var binders := {}
static var _result: DotResult = null


static func load_all() -> void:
	if _result != null:
		return
	_result = DotResult.success(null)
	for id in IDS:
		var raw := HungryPreset.for_id(id)
		var config := HungryModeConfig.new()
		config._mode_id = String(id)
		config.world_width = raw.world_size.x
		config.world_height = raw.world_size.y
		config.food_target = raw.food_target
		config.fruit_target = raw.fruit_target
		config.item_target = raw.item_target
		config.win_mass = raw.win_mass
		config.time_limit_sec = raw.time_limit_sec
		config.outgrown = raw.outgrown
		var binder := DotGameConfigBinder.create(config, GAME_ID, "hungry_mode_" + String(id))
		binder.profile_kind = "mode_" + String(id)
		binder.profile_id = String(id)
		binders[id] = binder
		var res := binder.load_layers()
		if not res.ok and _result.ok:
			_result = res


## The load outcome: a failure when strict and a layer was wrong.
static func result() -> DotResult:
	load_all()
	return _result


## The mode [param id] with its configured values: use this, not [method HungryPreset.for_id], wherever a game is built.
static func preset_for(id: StringName) -> HungryPreset:
	var preset := HungryPreset.for_id(id)
	load_all()
	var binder: DotGameConfigBinder = binders.get(preset.id)
	if binder == null:
		return preset
	var c: HungryModeConfig = binder.config
	preset.world_size = Vector2(c.world_width, c.world_height)
	preset.food_target = c.food_target
	preset.fruit_target = c.fruit_target
	preset.item_target = c.item_target
	preset.win_mass = c.win_mass
	preset.time_limit_sec = c.time_limit_sec
	preset.outgrown = c.outgrown
	return preset


## Forgets everything loaded (tests).
static func reset() -> void:
	binders = {}
	_result = null
