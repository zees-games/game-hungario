extends RefCounted

## Hungry's per-map settings: dot-game's [DotGameMapConfig] over the rule cvars a map may change.
##
## The map id is the mode's preset id (`frenzy`, `warrens`). Files: `cfg/game/game-hungario/dot_map/map/<name>.yml` (a glob covers a class of maps), overridable from `cfg/server/...`. Only [constant KEYS] are accepted; this game has no imported BSP maps, so no starter files ship.

const GAME_ID := "game-hungario"

## cvar -> its constraint. Rules only; nothing here runs a command.
const KEYS := {
	"hungry_hunters_on": {"type": "int", "min": 0, "max": 1},
	"hungry_hazards_count": {"type": "int", "min": 0, "max": 64},
	"hungry_outgrown": {"type": "string"},
	"hungry_warrens_corners": {"type": "string"},
	"hungry_fruit_effect_sec": {"type": "float", "min": 0.5, "max": 120.0},
	"hungry_frost_sec": {"type": "float", "min": 0.5, "max": 60.0},
	"hungry_pepper_damage": {"type": "float", "min": 1.0, "max": 1000.0},
	"hungry_throw_cooldown_ticks": {"type": "int", "min": 0, "max": 600},
	"hungry_respawn_delay_sec": {"type": "float", "min": 0.0, "max": 60.0},
	"hungry_spawn_protection_sec": {"type": "float", "min": 0.0, "max": 60.0},
	"hungry_hunter_speed_scale": {"type": "float", "min": 0.1, "max": 5.0},
}


## The applier over [param console]'s cvars. Call `apply(map_id)` on every map load.
static func build(console: Object) -> DotGameMapConfig:
	return DotGameMapConfig.for_console(GAME_ID, console, KEYS)
