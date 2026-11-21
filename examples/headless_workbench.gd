extends GSGameWorkbenchSuite

## game-hungario: the workbench over the config binder, one edit per profile set, the export and its cfg round trip.
## Run: godot --headless --path . res://examples/headless_workbench.tscn

const HungryServerConfig := preload("../game/hungry_server_config.gd")


func _make_config() -> GSConfig:
	return HungryServerConfig.new()


func _make_binder(config: GSConfig) -> GSGameConfigBinder:
	return HungryServerConfig.make_binder(config)
