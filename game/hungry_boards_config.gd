@tool
class_name HungryBoardsConfig
extends DotConfig

## Where this server's leaderboards live. Layered like every [DotConfig]: defaults, JSON
## file, environment (`HUNGRY_BOARDS_BACKEND`), command line (`--hungry-boards-backend`).

## "memory" keeps boards in this process; "backbone" keeps them on the site (needs a registered backbone client).
@export_enum("memory", "backbone") var backend: String = "memory"


func env_prefix() -> String:
	return "HUNGRY_BOARDS_"


func cli_prefix() -> String:
	return "--hungry-boards-"


func validate() -> DotResult:
	if backend != "memory" and backend != "backbone":
		return DotResult.fail(DotError.CODE_INVALID, "backend must be memory or backbone")
	return DotResult.success(null)
