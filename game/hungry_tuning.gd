extends RefCounted

## The server's operator surface: [HungryServerConfig] through a [DotGameConfigBinder] (cfg/ yml tiers, env, argv, cvars, the workbench). The modes' are [HungryModes].
##
## Static, because the simulation reads it from places that have no owner to ask. Loaded on first use; [method result] holds a strict refusal until the module, which can quit, reads it.

const HungryServerConfig := preload("hungry_server_config.gd")

const GAME_ID := "game-hungario"

static var server: HungryServerConfig = null
static var binder: DotGameConfigBinder = null
static var _result: DotResult = null


## The server config, loaded on first use.
static func settings() -> HungryServerConfig:
	load_all()
	return server


static func load_all() -> void:
	if _result != null:
		return
	server = HungryServerConfig.new()
	binder = HungryServerConfig.make_binder(server)
	_result = binder.load_layers()


## The load outcome: a failure when strict and a layer was wrong.
static func result() -> DotResult:
	load_all()
	return _result


## Forgets everything loaded (tests).
static func reset() -> void:
	server = null
	binder = null
	_result = null
