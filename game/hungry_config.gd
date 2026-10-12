@tool
extends DotConfig

## This game's own settings: the camera and what is drawn over the arena.
##
## [b]The declaration, not the store.[/b] [HungrySettings] reads these `@export`s with
## [method DotSettingsSchema.from_config] (the type, the range, the default) into the
## dot-settings document dot-menu's Escape menu is a view of, and the presentation layer
## writes each value back here as it changes, so the game reads plain properties and there
## is one list. The document is what is saved; this object is never written to disk. Until
## 2026-10-12 it was (`user://cfg/hungry.json`, dot-ui's settings screen), and
## [HungrySettings] migrates that file once.
##
## The volume is not here any more: it is dot-menu's stock audio page, which dot-audio's
## mixer applies, as in every game of the family.

@export_group("Camera")

## Seconds the camera takes to catch up with the monster. Zero snaps.
##
## Worth exposing rather than fixing: a player who finds the lag nauseating and a player
## who finds a snapped camera jarring are both right, and neither can be argued out of it.
@export_range(0.0, 0.5, 0.01) var follow_sec: float = 0.10

## Zoom out as the monster grows.
##
## Off is a legitimate preference and a legitimate advantage — a fixed zoom sees less and
## reacts faster — which is why it is a setting rather than a debug flag.
@export var zoom_with_size: bool = true

@export_group("Interface")

@export var show_minimap: bool = true

## Draw everybody's name above their monster.
##
## Off is quieter and, in a crowd, considerably more readable.
@export var show_names: bool = true

## Ring every monster by whether you could eat it, or it you.
##
## The one readability affordance this genre cannot do without: eating needs a *ratio*,
## not merely being bigger, and judging a quarter of a difference in area by eye is
## something nobody does reliably under pressure. Off for anybody who would rather learn
## to.
@export var show_threat: bool = true

## Lines the feed keeps on screen at once. Zero turns it off.
@export_range(0, 20, 1) var feed_lines: int = 8


func env_prefix() -> String:
	return "HUNGRY_"


func cli_prefix() -> String:
	return "--hungry-"


func validate() -> DotResult:
	if follow_sec < 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID, "A camera cannot catch up in negative time."
		)

	return DotResult.success(null)


func describe_summary() -> String:
	return "camera %.2fs%s" % [follow_sec, "" if zoom_with_size else ", fixed zoom"]
