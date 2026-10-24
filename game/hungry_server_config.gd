@tool
extends DotConfig

## The server's tunables, which only the server decides: reachable as `hungry_<field>` cvars, `cfg/game/game-hungario/config/game.yml`, and the workbench (see [HungryTuning]).
##
## Not here, on purpose: anything a client predicts with (the rush and frost speed multipliers, split and eject cooldowns, a mode's top speed and merge delay). A client builds those from its own code, so a server that changed them would rubber-band every player.

@export_group("Hand-bound cvars")

## Release NPC hunters into the arena. Off: a mode about eating and a mode about being hunted are different games.
@export var hunters_on: bool = false

## Rocks scattered into the arena at load.
@export_range(0, 64, 1) var hazards_count: int = 0

## A monster wedged in a refuge it outgrew: accept, cap (food stops counting) or eject (sheds the excess). Empty: the mode's.
@export var outgrown: String = ""

## The warrens' corner rocks: open, or quartered (shut into a quarter past about 903 mass). Empty: the mode's. From the next mode change.
@export var warrens_corners: String = ""

## Manifest URL for this server's rider content. Empty: whatever the client shipped with.
@export var avatar_pack: String = ""

## Path of the file holding this server's site integration token (never the token itself).
@export var backbone_config: String = "user://cfg/auth.json"

@export_group("Fruit and throwables")

## Seconds a fruit's effect lasts.
@export_range(0.5, 120.0, 0.5) var fruit_effect_sec: float = 8.0

## Seconds a frosted monster is slowed.
@export_range(0.5, 60.0, 0.5) var frost_sec: float = 5.0

## Pepper damage at point blank, in dot-combat's units; the falloff and the minimum scale from it.
@export_range(1.0, 1000.0, 1.0) var pepper_damage: float = 100.0

## Crumbs a lure plants where it lands.
@export_range(1, 200, 1) var lure_food_count: int = 26

## Ticks between two throws.
@export_range(0, 600, 1) var throw_cooldown_ticks: int = 24

@export_group("Round")

## Seconds a dead player waits before respawning.
@export_range(0.0, 60.0, 0.5) var respawn_delay_sec: float = 3.0

## Seconds of protection after a spawn.
@export_range(0.0, 60.0, 0.5) var spawn_protection_sec: float = 3.0

## Whether a thrown pepper hurts everybody (true), or nobody on the thrower's team (false, once teams exist).
@export var friendly_fire: bool = true

## Seconds the scoreboard shows between rounds.
@export_range(0.0, 120.0, 1.0) var intermission_sec: float = 8.0

## Seconds a finished match lasts before the next.
@export_range(0.0, 120.0, 1.0) var match_end_sec: float = 12.0

@export_group("Hunters")

## Multiplier on every hunter's speed.
@export_range(0.1, 5.0, 0.05) var hunter_speed_scale: float = 1.0

@export_group("Server")

## Player slots. Read when the roster is built, so a change takes a restart.
@export_range(1, 128, 1) var max_players: int = 32

## The default for `bot_quota` (bots kept in fill mode). Read once at load.
@export_range(0, 64, 1) var bot_fill: int = 6


func env_prefix() -> String:
	return "HUNGRY_SERVER_"


func cli_prefix() -> String:
	return "--hungry-server-"


func validate() -> DotResult:
	if not ["", "accept", "cap", "eject"].has(outgrown.strip_edges().to_lower()):
		return DotResult.fail(DotError.CODE_INVALID, "outgrown must be accept, cap, eject or empty")
	if not ["", "open", "quartered"].has(warrens_corners.strip_edges().to_lower()):
		return DotResult.fail(DotError.CODE_INVALID, "warrens_corners must be open, quartered or empty")
	return DotResult.success(null)
