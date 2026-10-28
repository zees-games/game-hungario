extends RefCounted

## What the arena's ambience is: the cvar defaults shared by the module (binds `hungry_ambient*`) and the client's director (plays them).

const PREFIX := "hungry"
## The cues are the game: the layer sits under them, with rare one-shots.
const LEVEL := 0.15
const RATE := 0.4
const DEFAULT_MOOD := &"outdoor_night"

## By preset id prefix (the map id the client reports is the preset id).
const PREFIX_MOODS := {
	"warrens": &"cave_tunnel", "gauntlet": &"industrial", "reef": &"swamp", "shallows": &"swamp",
}

## The bed's `{level, lively}` per preset id, the shape a map document's `ambient` has; the client's director reads it through `map_lookup`.
const LEVELS := {
	&"warrens": {"level": 0.8, "lively": false}, &"gauntlet": {"level": 1.2, "lively": true},
	&"reef": {"level": 1.0, "lively": true}, &"shallows": {"level": 0.9, "lively": true},
}


## The map-like record the director's lookup wants for a preset id, or null.
static func map_for(id: StringName) -> Variant:
	if LEVELS.has(id):
		return {"meta": {"ambient": LEVELS[id]}}
	return null


static func make_rules() -> DotAmbienceRules:
	var r := DotAmbienceRules.new()
	r.prefix = PREFIX
	r.volume = LEVEL
	r.frequency = RATE
	return r


## The cvars a workbench set offers: name -> profile type.
static func cvar_types() -> Dictionary:
	var rules := make_rules()
	var out := {}
	for key: String in DotAmbienceRules.VARS:
		var row: Array = DotAmbienceRules.VARS[key]
		out[rules.cvar_of(row)] = "string" if row[2] == null else "float"
	return out
