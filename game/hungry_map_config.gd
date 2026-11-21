extends RefCounted

## Hungry's per-map settings: gs-game's [GSGameMapConfig] over the rule cvars a map may change.
##
## The map id is the mode's preset id (`frenzy`, `warrens`). Files: `cfg/game/game-hungario/gs_map/map/<name>.yml` (a glob covers a class of maps), overridable from `cfg/server/...`. Only [constant KEYS] are accepted; this game has no imported BSP maps, so no starter files ship. A value under a key's `min` is refused (key and value in the warning), never clamped; the only `max` is `hungry_hunters_on` 0/1, a switch.

const GAME_ID := "game-hungario"

## cvar -> its constraint. Rules only; nothing here runs a command.
const KEYS := {
	"hungry_hunters_on": {"type": "int", "min": 0, "max": 1},
	"hungry_hazards_count": {"type": "int", "min": 0},
	"hungry_outgrown": {"type": "string"},
	"hungry_warrens_corners": {"type": "string"},
	"hungry_fruit_effect_sec": {"type": "float", "min": 0.5},
	"hungry_frost_sec": {"type": "float", "min": 0.5},
	"hungry_pepper_damage": {"type": "float", "min": 1.0},
	"hungry_throw_cooldown_ticks": {"type": "int", "min": 0},
	"hungry_respawn_delay_sec": {"type": "float", "min": 0.0},
	"hungry_spawn_protection_sec": {"type": "float", "min": 0.0},
	"hungry_hunter_speed_scale": {"type": "float", "min": 0.1},
}


## The applier over [param console]'s cvars. Call `apply(map_id)` on every map load.
static func build(console: Object) -> GSGameMapConfig:
	return GSGameMapConfig.for_console(GAME_ID, console, KEYS)
