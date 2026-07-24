@tool
extends Control

const SAVE_PATH := "user://dumpster_delights_turn_based.save"
const BoardStateScript = preload("res://scripts/core/board_state.gd")
const PieceGeneratorScript = preload("res://scripts/core/piece_generator.gd")
const SaveDataScript = preload("res://scripts/core/save_data.gd")
const SaveDataStoreScript = preload("res://scripts/core/save_data_store.gd")

@export var config: Resource

@onready var board_view: Control = %BoardView
@onready var hud: Control = %GameHUD

var board_state = BoardStateScript.new()
var piece_generator = PieceGeneratorScript.new()
var save_store = SaveDataStoreScript.new(SAVE_PATH)
var current_piece: Resource
var next_pieces: Array[Resource] = []
var current_anchor := Vector2i.ZERO
var current_rotation := 0
var score := 0
var best_score := 0
var move_count := 0
var game_over := false

var previous_board
var previous_score := 0
var previous_move_count := 0
var previous_piece: Resource
var previous_anchor := Vector2i.ZERO
var previous_rotation := 0
var can_undo := false
var blocked_feedback_until_msec := 0
var merge_feedback_steps: Array[Dictionary] = []
var merge_feedback_until_msec := 0
var was_blocked_feedback_active := false
var was_merge_feedback_active := false


func _ready() -> void:
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	hud.bind_actions(
		_on_rotate_left_pressed,
		_try_place_piece,
		_on_rotate_right_pressed,
		_on_undo_pressed,
		_on_restart_pressed
	)
	board_view.anchor_targeted.connect(_on_board_anchor_targeted)
	resized.connect(_refresh_presentation)
	set_process(true)
	_load_save_data()
	if config == null:
		push_error("Main scene requires a GameConfig resource.")
		hud.update_status({"hint_text": "Missing GameConfig resource."})
		hud.clear_preview()
		return
	var issues: PackedStringArray = config.validate()
	if not issues.is_empty():
		push_error("Invalid GameConfig: %s" % ", ".join(issues))
		hud.update_status({"hint_text": issues[0]})
		hud.clear_preview()
		return
	board_view.config = config
	start_new_game()


func start_new_game() -> void:
	if config == null:
		return
	board_state.setup(config.board_width, config.board_height)
	score = 0
	move_count = 0
	game_over = false
	can_undo = false
	merge_feedback_steps.clear()
	merge_feedback_until_msec = 0
	next_pieces.clear()
	_fill_preview_queue()
	_draw_next_piece()
	_refresh_presentation()


func _fill_preview_queue() -> void:
	while next_pieces.size() < config.preview_piece_count:
		var piece = piece_generator.next_piece(config.piece_definitions)
		if piece == null:
			break
		next_pieces.append(piece)


func _draw_next_piece() -> void:
	if next_pieces.is_empty():
		_fill_preview_queue()
	current_piece = next_pieces.pop_front() if not next_pieces.is_empty() else null
	_fill_preview_queue()
	current_rotation = 0
	if current_piece == null:
		game_over = true
		return
	var bounds: Rect2i = _piece_bounds(current_piece.get_rotated_cells(current_rotation))
	current_anchor = Vector2i(
		maxi(0, int((config.board_width - bounds.size.x) / 2) - bounds.position.x),
		maxi(0, -bounds.position.y)
	)
	_clamp_current_anchor()
	if not board_state.can_place(_current_cells()):
		game_over = true


func _on_restart_pressed() -> void:
	start_new_game()


func _on_rotate_left_pressed() -> void:
	_try_rotate(-1)


func _on_rotate_right_pressed() -> void:
	_try_rotate(1)


func _on_undo_pressed() -> void:
	if not can_undo or previous_board == null:
		_show_blocked_feedback()
		_refresh_presentation()
		return
	board_state = previous_board.duplicate_state()
	score = previous_score
	move_count = previous_move_count
	current_piece = previous_piece
	current_anchor = previous_anchor
	current_rotation = previous_rotation
	game_over = false
	can_undo = false
	merge_feedback_steps.clear()
	merge_feedback_until_msec = 0
	_refresh_presentation()
	hud.show_toast("UNDO")


func _unhandled_input(event: InputEvent) -> void:
	if config == null or game_over:
		if event.is_action_pressed("ui_accept"):
			start_new_game()
		return

	if event.is_action_pressed("ui_left"):
		_try_move_anchor(Vector2i.LEFT)
	elif event.is_action_pressed("ui_right"):
		_try_move_anchor(Vector2i.RIGHT)
	elif event.is_action_pressed("ui_up"):
		_try_move_anchor(Vector2i.UP)
	elif event.is_action_pressed("ui_down"):
		_try_move_anchor(Vector2i.DOWN)
	elif event.is_action_pressed("ui_accept"):
		_try_place_piece()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q, KEY_Z:
				_try_rotate(-1)
			KEY_E, KEY_X:
				_try_rotate(1)
			KEY_R:
				start_new_game()


func _process(_delta: float) -> void:
	var blocked_active := _is_blocked_feedback_active()
	var merge_active := _is_merge_feedback_active()
	if blocked_active or merge_active:
		_refresh_board_feedback_only()
	if blocked_active != was_blocked_feedback_active:
		_refresh_hud_only()
	if not merge_active and was_merge_feedback_active:
		merge_feedback_steps.clear()
		_refresh_board_feedback_only()
	was_blocked_feedback_active = blocked_active
	was_merge_feedback_active = merge_active


func _try_move_anchor(offset: Vector2i) -> void:
	var candidate := current_anchor + offset
	if _can_piece_fit(candidate, current_rotation):
		current_anchor = candidate
		_refresh_presentation()
	else:
		_show_blocked_feedback()
		_refresh_presentation()


func _try_rotate(direction: int) -> void:
	if current_piece == null or not current_piece.allow_rotation:
		return
	var candidate_rotation: int = posmod(current_rotation + direction, 4)
	if _can_piece_fit(current_anchor, candidate_rotation):
		current_rotation = candidate_rotation
		_clamp_current_anchor()
		_refresh_presentation()
	else:
		_show_blocked_feedback()
		_refresh_presentation()


func _try_place_piece() -> void:
	var placement_cells := _current_cells()
	if not board_state.can_place(placement_cells):
		_show_blocked_feedback()
		_refresh_presentation()
		return

	previous_board = board_state.duplicate_state()
	previous_score = score
	previous_move_count = move_count
	previous_piece = current_piece
	previous_anchor = current_anchor
	previous_rotation = current_rotation
	can_undo = true

	board_state.place_cells(placement_cells, current_piece.get_rotated_values(current_rotation))
	var merge_result: Dictionary = board_state.resolve_merges(config.min_merge_group, config.score_per_rank)
	score += merge_result["score"]
	best_score = maxi(best_score, score)
	move_count += 1
	_save_progress()
	if merge_result["merged"]:
		_show_merge_feedback(merge_result.get("steps", []))
		hud.show_toast("MERGE!")
	_draw_next_piece()
	if game_over or not board_state.has_any_moves(config.piece_definitions):
		game_over = true
		hud.show_toast("BOARD JAMMED")
	_refresh_presentation()


func _on_board_anchor_targeted(target_anchor: Vector2i) -> void:
	if config == null or current_piece == null or game_over:
		return
	var resolved_anchor := _resolve_pointer_anchor(target_anchor)
	if _can_piece_fit(resolved_anchor, current_rotation):
		current_anchor = resolved_anchor
	else:
		_show_blocked_feedback()
	_refresh_presentation()


func _resolve_pointer_anchor(target_anchor: Vector2i) -> Vector2i:
	var rotated: Array[Vector2i] = current_piece.get_rotated_cells(current_rotation)
	var shifted_cells: Array[Vector2i] = []
	for cell in rotated:
		shifted_cells.append(cell + target_anchor)
	if board_state.can_place(shifted_cells):
		return target_anchor
	var bounds := _piece_bounds(rotated)
	var fallback := current_anchor
	fallback.x = clampi(target_anchor.x, -bounds.position.x, config.board_width - (bounds.position.x + bounds.size.x))
	fallback.y = clampi(target_anchor.y, -bounds.position.y, config.board_height - (bounds.position.y + bounds.size.y))
	return fallback


func _refresh_presentation() -> void:
	_refresh_board_view()
	_refresh_hud_only()


func _refresh_board_view() -> void:
	board_view.set_board_state(board_state)
	board_view.set_active_piece(current_piece, current_anchor, current_rotation, game_over)
	_refresh_board_feedback_only()


func _refresh_board_feedback_only() -> void:
	board_view.set_feedback(
		_is_blocked_feedback_active(),
		merge_feedback_steps,
		_merge_feedback_ratio()
	)


func _refresh_hud_only() -> void:
	hud.set_preview_pieces(next_pieces, config.preview_piece_count)
	hud.update_status({
		"score": score,
		"best_score": best_score,
		"move_count": move_count,
		"target_text": "Place pieces, connect matching numbers, and merge groups.",
		"subtitle_text": _subtitle_text(),
		"hint_text": _hint_text(),
		"can_undo": can_undo
	})


func _subtitle_text() -> String:
	if game_over:
		return "No legal placements left. Start a fresh round."
	if current_piece != null:
		return "Current piece: %s." % current_piece.display_name
	return ""


func _hint_text() -> String:
	if _is_blocked_feedback_active():
		return "That spot is jammed. Slide the snack somewhere roomier."
	if game_over:
		return "Press Place/Enter after moving a piece into position."
	return "Tap the board or use arrows to move. Rotate, then Place the snack."


func _current_cells() -> Array[Vector2i]:
	if current_piece == null:
		return []
	var translated: Array[Vector2i] = []
	for cell in current_piece.get_rotated_cells(current_rotation):
		translated.append(cell + current_anchor)
	return translated


func _can_piece_fit(anchor: Vector2i, rotation: int) -> bool:
	if current_piece == null:
		return false
	var translated: Array[Vector2i] = []
	for cell in current_piece.get_rotated_cells(rotation):
		translated.append(cell + anchor)
	return board_state.can_place(translated)


func _clamp_current_anchor() -> void:
	if current_piece == null:
		return
	var rotated: Array[Vector2i] = current_piece.get_rotated_cells(current_rotation)
	var bounds := _piece_bounds(rotated)
	var max_anchor_x: int = config.board_width - (bounds.position.x + bounds.size.x)
	var max_anchor_y: int = config.board_height - (bounds.position.y + bounds.size.y)
	current_anchor.x = clampi(current_anchor.x, -bounds.position.x, max_anchor_x)
	current_anchor.y = clampi(current_anchor.y, -bounds.position.y, max_anchor_y)


func _piece_bounds(cells: Array) -> Rect2i:
	var min_x: int = cells[0].x
	var min_y: int = cells[0].y
	var max_x: int = cells[0].x
	var max_y: int = cells[0].y
	for cell in cells:
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _show_blocked_feedback() -> void:
	blocked_feedback_until_msec = Time.get_ticks_msec() + 700


func _is_blocked_feedback_active() -> bool:
	return Time.get_ticks_msec() < blocked_feedback_until_msec


func _show_merge_feedback(steps: Array) -> void:
	merge_feedback_steps.clear()
	for step in steps:
		merge_feedback_steps.append(step.duplicate(true))
	merge_feedback_until_msec = Time.get_ticks_msec() + int(config.merge_flash_duration_sec * 1000.0)


func _is_merge_feedback_active() -> bool:
	return Time.get_ticks_msec() < merge_feedback_until_msec and not merge_feedback_steps.is_empty()


func _merge_feedback_ratio() -> float:
	if not _is_merge_feedback_active():
		return 0.0
	return clampf(
		float(merge_feedback_until_msec - Time.get_ticks_msec()) / maxf(1.0, config.merge_flash_duration_sec * 1000.0),
		0.0,
		1.0
	)


func _save_progress() -> void:
	var data = SaveDataScript.new()
	data.best_score = best_score
	save_store.save_data(data)


func _load_save_data() -> void:
	var data = save_store.load_data()
	best_score = data.best_score


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if config == null:
		warnings.append("Assign a GameConfig resource to Main.config.")
		return warnings
	if not config.has_method("validate"):
		warnings.append("Main.config must be a GameConfig resource.")
		return warnings
	for issue in config.validate():
		warnings.append(issue)
	if config.board_width <= 0 or config.board_height <= 0:
		warnings.append("Board dimensions must be positive.")
	if config.tile_palette.is_empty():
		warnings.append("GameConfig.tile_palette should contain at least one color.")
	if config.preview_piece_count <= 0:
		warnings.append("GameConfig.preview_piece_count must be at least 1.")
	return warnings
