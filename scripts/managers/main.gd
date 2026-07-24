@tool
extends Control

const SAVE_PATH := "user://dumpster_delights_turn_based.save"
const BoardStateScript = preload("res://scripts/core/board_state.gd")
const PieceGeneratorScript = preload("res://scripts/core/piece_generator.gd")
const SaveDataScript = preload("res://scripts/core/save_data.gd")
const SaveDataStoreScript = preload("res://scripts/core/save_data_store.gd")

@export var config: Resource

@onready var title_label: Label = $Header/TitleLabel
@onready var subtitle_label: Label = $Header/SubtitleLabel
@onready var score_label: Label = $Header/StatsRow/ScoreLabel
@onready var best_label: Label = $Header/StatsRow/BestLabel
@onready var moves_label: Label = $Header/StatsRow/MovesLabel
@onready var target_label: Label = $Header/TargetLabel
@onready var toast_label: Label = $ToastLabel
@onready var hint_label: Label = $Footer/HintLabel
@onready var undo_button: Button = $Footer/ButtonsRow/UndoButton
@onready var restart_button: Button = $Footer/ButtonsRow/RestartButton

var board_state = BoardStateScript.new()
var piece_generator = PieceGeneratorScript.new()
var save_store = SaveDataStoreScript.new(SAVE_PATH)
var current_piece: Resource
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


func _ready() -> void:
	if Engine.is_editor_hint():
		update_configuration_warnings()
	undo_button.pressed.connect(_on_undo_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	resized.connect(queue_redraw)
	title_label.text = "Dumpster Delights"
	_load_save_data()
	if config == null:
		push_error("Main scene requires a GameConfig resource.")
		hint_label.text = "Missing GameConfig resource."
		return
	var issues: PackedStringArray = config.validate()
	if not issues.is_empty():
		push_error("Invalid GameConfig: %s" % ", ".join(issues))
		hint_label.text = issues[0]
		return
	start_new_game()


func start_new_game() -> void:
	if config == null:
		return
	board_state.setup(config.board_width, config.board_height)
	score = 0
	move_count = 0
	game_over = false
	can_undo = false
	_draw_next_piece()
	update_hud()
	queue_redraw()


func _draw_next_piece() -> void:
	current_piece = piece_generator.next_piece(config.piece_definitions)
	current_rotation = 0
	if current_piece == null:
		game_over = true
		hint_label.text = "No piece definitions are available."
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


func _on_undo_pressed() -> void:
	if not can_undo or previous_board == null:
		hint_label.text = "No rewind available yet."
		return
	board_state = previous_board.duplicate_state()
	score = previous_score
	move_count = previous_move_count
	current_piece = previous_piece
	current_anchor = previous_anchor
	current_rotation = previous_rotation
	game_over = false
	can_undo = false
	update_hud()
	queue_redraw()
	_show_toast("UNDO")


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


func _try_move_anchor(offset: Vector2i) -> void:
	var candidate := current_anchor + offset
	if _can_piece_fit(candidate, current_rotation):
		current_anchor = candidate
		queue_redraw()
		update_hud()


func _try_rotate(direction: int) -> void:
	if current_piece == null or not current_piece.allow_rotation:
		return
	var candidate_rotation: int = posmod(current_rotation + direction, 4)
	if _can_piece_fit(current_anchor, candidate_rotation):
		current_rotation = candidate_rotation
		_clamp_current_anchor()
		queue_redraw()
		update_hud()


func _try_place_piece() -> void:
	var placement_cells := _current_cells()
	if not board_state.can_place(placement_cells):
		hint_label.text = "That placement is blocked."
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
		_show_toast("MERGE!")
	_draw_next_piece()
	if game_over or not board_state.has_any_moves(config.piece_definitions):
		game_over = true
		_show_toast("BOARD JAMMED")
	update_hud()
	queue_redraw()


func update_hud() -> void:
	score_label.text = "Score: %d" % score
	best_label.text = "Best: %d" % best_score
	moves_label.text = "Turns: %d" % move_count
	target_label.text = "Place pieces, connect matching numbers, and merge groups."
	undo_button.disabled = not can_undo
	if game_over:
		subtitle_label.text = "No legal placements left. Start a fresh round."
		hint_label.text = "Press Place/Enter after moving a piece into position."
	elif current_piece != null:
		subtitle_label.text = "Current piece: %s." % current_piece.display_name
		hint_label.text = "Arrows move. Q/E rotate. Enter places the piece."


func _draw() -> void:
	if config == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color("202020"), true)
		return
	draw_rect(Rect2(Vector2.ZERO, size), config.background_color, true)

	var board_rect := _board_rect()
	var style := StyleBoxFlat.new()
	style.bg_color = config.board_color
	style.set_corner_radius_all(24)
	draw_style_box(style, board_rect)

	for y in config.board_height:
		for x in config.board_width:
			var cell_rect := _cell_rect(board_rect, Vector2i(x, y))
			_draw_cell(cell_rect, board_state.get_value(Vector2i(x, y)))

	if not game_over and current_piece != null:
		var preview_cells := _current_cells()
		var can_place_preview: bool = board_state.can_place(preview_cells)
		for index in preview_cells.size():
			var pos := preview_cells[index]
			if not board_state.is_inside(pos):
				continue
			var preview_rect := _cell_rect(board_rect, pos)
			var preview_style := StyleBoxFlat.new()
			preview_style.bg_color = current_piece.preview_color
			preview_style.bg_color.a = 0.6 if can_place_preview else 0.25
			preview_style.set_corner_radius_all(16)
			draw_style_box(preview_style, preview_rect)
			_draw_cell_text(preview_rect, current_piece.cell_values[index], Color("2f2419"))


func _draw_cell(cell_rect: Rect2, value: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = config.empty_cell_color
	style.set_corner_radius_all(16)
	if value > 0:
		style.bg_color = config.tile_palette[(value - 1) % config.tile_palette.size()]
	draw_style_box(style, cell_rect)
	if value > 0:
		var text_color: Color = config.tile_text_dark if value <= 2 else config.tile_text_light
		_draw_cell_text(cell_rect, value, text_color)


func _draw_cell_text(cell_rect: Rect2, value: int, text_color: Color) -> void:
	var font := ThemeDB.fallback_font
	var label := str(int(pow(2.0, value)))
	var font_size := 22
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(
		font,
		Vector2(cell_rect.position.x + (cell_rect.size.x - width) * 0.5, cell_rect.position.y + cell_rect.size.y * 0.62),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		text_color
	)


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


func _board_rect() -> Rect2:
	var top := 164.0
	var bottom_margin := 196.0
	var board_pixel_width: int = config.board_width * config.cell_size + (config.board_width + 1) * config.cell_gap
	var board_pixel_height: int = config.board_height * config.cell_size + (config.board_height + 1) * config.cell_gap
	var max_width: float = size.x - config.outer_padding * 2.0
	var max_height := size.y - top - bottom_margin
	var scale_factor := minf(max_width / board_pixel_width, max_height / board_pixel_height)
	scale_factor = minf(scale_factor, 1.0)
	var final_size := Vector2(board_pixel_width, board_pixel_height) * scale_factor
	return Rect2(Vector2((size.x - final_size.x) * 0.5, top), final_size)


func _cell_rect(board_rect: Rect2, position: Vector2i) -> Rect2:
	var unit := minf(
		(board_rect.size.x - config.cell_gap) / float(config.board_width * config.cell_size + config.board_width * config.cell_gap),
		(board_rect.size.y - config.cell_gap) / float(config.board_height * config.cell_size + config.board_height * config.cell_gap)
	)
	var scaled_cell: float = config.cell_size * unit
	var scaled_gap: float = config.cell_gap * unit
	return Rect2(
		board_rect.position + Vector2(
			scaled_gap + position.x * (scaled_cell + scaled_gap),
			scaled_gap + position.y * (scaled_cell + scaled_gap)
		),
		Vector2.ONE * scaled_cell
	)


func _show_toast(message: String) -> void:
	if Engine.is_editor_hint():
		return
	toast_label.text = message
	toast_label.visible = true
	var tween := create_tween()
	toast_label.modulate = Color(1, 1, 1, 0)
	tween.tween_property(toast_label, "modulate", Color(1, 1, 1, 1), 0.15)
	tween.tween_interval(0.6)
	tween.tween_property(toast_label, "modulate", Color(1, 1, 1, 0), 0.25)
	tween.finished.connect(func() -> void:
		toast_label.visible = false
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
	return warnings
