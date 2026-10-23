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
}


## The applier over [param console]'s cvars. Call `apply(map_id)` on every map load.
static func build(console: Object) -> DotGameMapConfig:
	return DotGameMapConfig.for_console(GAME_ID, console, KEYS)
