extends "res://examples/headless_net_game.gd"

const CHECKS := 186

func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()

func _run() -> void:
	print("game-hungario: netcode")
	print("")

	_test_command_wire()
	_test_event_wire()
	_test_field_wire()

	if _build():
		_test_handshake()
		_test_replication()
		_test_prediction()
		_test_admin_is_predicted()
		_test_field_replication()
		_test_splitting_replicates()
		_test_throw_replicates()
		_test_death_carries_its_fall()
		_test_interest()
		_test_blind_and_beacon()
		_test_avatar()
		_test_interpolation()
		_test_loadout()
		_test_direction_enforced()
		_test_drawn_through_a_slip()
		_test_vote_wire()
		_test_loss()
		_test_game_change()
		_test_warrens_rock_converges()

	_test_the_remote_workbench()
	_teardown()

	print("")
	_check(
		_completed == _entered,
		"every section ran to its last line (%d of %d)" % [_completed, _entered],
		"a section that aborted stops adding checks and the total cannot show it"
	)

	_report(CHECKS)
