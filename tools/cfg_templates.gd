extends SceneTree

## Rewrites cfg/game/game-hungario/config_*/game.yml from HungryServerConfig's fields: godot --headless --path . --script tools/cfg_templates.gd

const HungryServerConfig := preload("../game/hungry_server_config.gd")


func _init() -> void:
	var binder := HungryServerConfig.make_binder(HungryServerConfig.new())
	var files := binder.template_files()
	for path: String in files:
		var res := DotPaths.write_text("res://" + path, files[path])
		print("%s %s" % ["wrote" if res.ok else "FAILED", path])
	quit()
