extends DotGamePerfBench

## Solo-client benchmark (dot-game's DotGamePerfBench: see it for the flags and the report). Runs the offline client with `--bots N` stand-ins on the game's own default map; windowed on a GPU box through tools/perf_bench.sh, not headless.


func _configure() -> void:
	client_scene = "res://game/client/hungry_client.tscn"
	bots = 6


func _setup_client(c: Node) -> void:
	c.set("force_offline", true)
	c.set("offline_bots", bots)
