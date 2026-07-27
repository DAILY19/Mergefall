extends SceneTree

const BoardStateTest = preload("res://tests/board_state_test.gd")
const ProgressionTest = preload("res://tests/progression_test.gd")
const InstrumentationDprTest = preload("res://tests/instrumentation_dpr_test.gd")


func _init() -> void:
	var failures := BoardStateTest.run()
	failures.append_array(ProgressionTest.run())
	failures.append_array(InstrumentationDprTest.run())
	if failures.is_empty():
		print("BoardState and progression tests passed.")
		quit(0)
		return

	push_error("Rules tests failed:")
	for failure in failures:
		push_error(" - %s" % failure)
	quit(1)
