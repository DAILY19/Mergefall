extends SceneTree

const BoardStateTest = preload("res://tests/board_state_test.gd")


func _init() -> void:
	var failures := BoardStateTest.run()
	if failures.is_empty():
		print("BoardState tests passed.")
		quit(0)
		return

	push_error("BoardState tests failed:")
	for failure in failures:
		push_error(" - %s" % failure)
	quit(1)
