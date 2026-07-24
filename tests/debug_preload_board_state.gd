extends SceneTree


func _init() -> void:
	var board_state_script = load("res://scripts/core/board_state.gd")
	if board_state_script == null:
		push_error("Failed to load res://scripts/core/board_state.gd")
		quit(1)
		return

	print("Loaded board_state.gd successfully.")
	quit(0)
