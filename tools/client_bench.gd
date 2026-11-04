extends DotGameClientBench

const HungryModule := preload("../game/hungry_module.gd")

## Client prediction bench (dot-game's DotGameClientBench): see that class for the flags.
## `--bots` adds that many of the module's own bots; `--play` supplies the pilot's movement.


func _configure() -> void:
	client_scene = "res://game/client/hungry_client.tscn"
	forward_action = &""
	strafe_actions = []
	jump_action = &""


func _boot_server(bots_wanted: int, data_dir: String) -> DotNetManager:
	var config := make_server_config(data_dir)
	config.max_players = 32
	var server := DotServer.new()
	server.name = "Server"
	server.config = config
	add_child(server)
	for _i in 60:
		await get_tree().process_frame
		if server.state == DotServer.State.RUNNING:
			break
	for descriptor in HungryModule.game_descriptors():
		server.games.add_game(descriptor)
	var changed: DotResult = await server.games.change_game(HungryModule.GAME_CLASSIC, "boot")
	if not changed.ok:
		printerr("client_bench server: ", changed.error)
		return null
	HungryModule.punishments_path = "%s/punishments.json" % data_dir
	var loaded: DotResult = await server.modules.load_module("res://game/hungry_module.gd")
	if not loaded.ok:
		printerr("client_bench server: ", loaded.error)
		return null
	var module: Object = server.modules.get_module("hungry")
	for i in bots_wanted:
		module.call("_add_bot", "Bot%d" % i)
	for n in server.modules.loaded_names():
		var m: Object = server.modules.get_module(n)
		if m != null and m.get("net") != null:
			return m.get("net")
	return null
