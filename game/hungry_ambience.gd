extends RefCounted

## What the arena's ambience is: the cvar defaults shared by the module (binds `hungry_ambient*`) and the client's director (plays them).

const PREFIX := "hungry"
## The cues are the game: the layer sits under them, with rare one-shots.
const LEVEL := 0.3
const RATE := 0.5
const DEFAULT_MOOD := &"outdoor_night"

## By preset id prefix (the map id the client reports is the preset id).
const PREFIX_MOODS := {
	"warrens": &"cave_tunnel", "gauntlet": &"industrial", "reef": &"swamp", "shallows": &"swamp",
}


static func make_rules() -> DotAmbienceRules:
	var r := DotAmbienceRules.new()
	r.prefix = PREFIX
	r.volume = LEVEL
	r.frequency = RATE
	return r
