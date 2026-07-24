@tool
class_name BoardView
extends Control

signal anchor_targeted(anchor: Vector2i)

const BoardStateScript = preload("res://scripts/core/board_state.gd")

@export var config: Resource:
	set(value):
		config = value
		queue_redraw()

@export_group("Layout")
@export_range(0, 320, 1) var top_padding := 16.0:
	set(value):
		top_padding = value
		queue_redraw()

@export_range(0, 320, 1) var bottom_padding := 16.0:
	set(value):
		bottom_padding = value
		queue_redraw()

@export_range(0, 200, 1) var board_corner_radius := 24:
	set(value):
		board_corner_radius = value
		queue_redraw()

@export_range(0, 120, 1) var cell_corner_radius := 16:
	set(value):
		cell_corner_radius = value
		queue_redraw()

@export_group("Textures")
@export var board_texture: Texture2D:
	set(value):
		board_texture = value
		queue_redraw()

@export var empty_cell_texture: Texture2D:
	set(value):
		empty_cell_texture = value
		queue_redraw()

@export var occupied_cell_texture: Texture2D:
	set(value):
		occupied_cell_texture = value
		queue_redraw()

@export_group("Typography")
@export var value_font: Font:
	set(value):
		value_font = value
		queue_redraw()

@export_range(8, 64, 1) var value_font_size := 22:
	set(value):
		value_font_size = value
		queue_redraw()

var _board_state: BoardState
var _current_piece: Resource
var _current_anchor := Vector2i.ZERO
var _current_rotation := 0
var _game_over := false
var _blocked_feedback_active := false
var _merge_feedback_steps: Array[Dictionary] = []
var _merge_feedback_ratio := 0.0


func set_board_state(board_state: BoardState) -> void:
	_board_state = board_state
	queue_redraw()


func set_active_piece(piece: Resource, anchor: Vector2i, rotation: int, game_over: bool) -> void:
	_current_piece = piece
	_current_anchor = anchor
	_current_rotation = rotation
	_game_over = game_over
	queue_redraw()


func set_feedback(blocked_active: bool, merge_steps: Array, merge_feedback_ratio: float) -> void:
	_blocked_feedback_active = blocked_active
	_merge_feedback_steps.clear()
	for step in merge_steps:
		_merge_feedback_steps.append(step.duplicate(true))
	_merge_feedback_ratio = clampf(merge_feedback_ratio, 0.0, 1.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if config == null or _board_state == null or _current_piece == null or _game_over:
		return
	if event is InputEventScreenTouch and event.pressed:
		_emit_anchor_for_pointer(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_emit_anchor_for_pointer(event.position)


func _draw() -> void:
	if config == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color("202020"), true)
		return

	draw_rect(Rect2(Vector2.ZERO, size), config.background_color, true)
	var board_rect := get_board_rect()
	_draw_board_backing(board_rect)

	if _board_state == null:
		return

	for y in config.board_height:
		for x in config.board_width:
			var position := Vector2i(x, y)
			var cell_rect := get_cell_rect(board_rect, position)
			_draw_cell(cell_rect, _board_state.get_value(position))

	if not _merge_feedback_steps.is_empty():
		for step in _merge_feedback_steps:
			for pos in step.get("positions", []):
				if _board_state.is_inside(pos):
					_draw_merge_flash(get_cell_rect(board_rect, pos), false)
			var anchor: Vector2i = step.get("anchor", Vector2i.ZERO)
			if _board_state.is_inside(anchor):
				_draw_merge_flash(get_cell_rect(board_rect, anchor), true)

	if _game_over or _current_piece == null:
		return

	var preview_cells := _current_cells()
	var can_place_preview: bool = _board_state.can_place(preview_cells)
	for index in preview_cells.size():
		var pos := preview_cells[index]
		if not _board_state.is_inside(pos):
			continue
		var preview_rect := get_cell_rect(board_rect, pos)
		_draw_preview_cell(preview_rect, _current_piece.cell_values[index], can_place_preview)


func get_board_rect() -> Rect2:
	if config == null:
		return Rect2()
	var board_pixel_width: int = config.board_width * config.cell_size + (config.board_width + 1) * config.cell_gap
	var board_pixel_height: int = config.board_height * config.cell_size + (config.board_height + 1) * config.cell_gap
	var max_width: float = size.x - config.outer_padding * 2.0
	var max_height := size.y - top_padding - bottom_padding
	var scale_factor := minf(max_width / board_pixel_width, max_height / board_pixel_height)
	scale_factor = minf(scale_factor, 1.0)
	var final_size := Vector2(board_pixel_width, board_pixel_height) * scale_factor
	return Rect2(
		Vector2((size.x - final_size.x) * 0.5, top_padding + (max_height - final_size.y) * 0.5),
		final_size
	)


func get_cell_rect(board_rect: Rect2, position: Vector2i) -> Rect2:
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


func _emit_anchor_for_pointer(pointer_position: Vector2) -> void:
	var board_rect := get_board_rect()
	if not board_rect.has_point(pointer_position):
		return
	anchor_targeted.emit(_anchor_from_pointer(pointer_position, board_rect))


func _anchor_from_pointer(pointer_position: Vector2, board_rect: Rect2) -> Vector2i:
	var cell_position := _cell_from_pointer(pointer_position, board_rect)
	var bounds := _piece_bounds(_current_piece.get_rotated_cells(_current_rotation))
	return cell_position - bounds.position


func _cell_from_pointer(pointer_position: Vector2, board_rect: Rect2) -> Vector2i:
	var unit := minf(
		(board_rect.size.x - config.cell_gap) / float(config.board_width * config.cell_size + config.board_width * config.cell_gap),
		(board_rect.size.y - config.cell_gap) / float(config.board_height * config.cell_size + config.board_height * config.cell_gap)
	)
	var scaled_cell: float = config.cell_size * unit
	var scaled_gap: float = config.cell_gap * unit
	var relative := pointer_position - board_rect.position - Vector2(scaled_gap, scaled_gap)
	var step := scaled_cell + scaled_gap
	var x := clampi(int(relative.x / step), 0, config.board_width - 1)
	var y := clampi(int(relative.y / step), 0, config.board_height - 1)
	return Vector2i(x, y)


func _draw_board_backing(board_rect: Rect2) -> void:
	if board_texture != null:
		draw_texture_rect(board_texture, board_rect, true)
		return
	var style := StyleBoxFlat.new()
	style.bg_color = config.board_color
	style.set_corner_radius_all(board_corner_radius)
	draw_style_box(style, board_rect)


func _draw_cell(cell_rect: Rect2, value: int) -> void:
	if value > 0 and occupied_cell_texture != null:
		draw_texture_rect(occupied_cell_texture, cell_rect, true)
	elif value <= 0 and empty_cell_texture != null:
		draw_texture_rect(empty_cell_texture, cell_rect, true)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = config.empty_cell_color
		style.set_corner_radius_all(cell_corner_radius)
		if value > 0:
			style.bg_color = config.tile_palette[(value - 1) % config.tile_palette.size()]
		draw_style_box(style, cell_rect)

	if value > 0:
		var text_color: Color = config.tile_text_dark if value <= 2 else config.tile_text_light
		_draw_cell_text(cell_rect, value, text_color)


func _draw_preview_cell(cell_rect: Rect2, value: int, is_valid: bool) -> void:
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = config.active_piece_valid_color if is_valid else config.active_piece_invalid_color
	preview_style.bg_color.a = config.active_piece_valid_alpha if is_valid else config.active_piece_invalid_alpha
	var blocked_border := 3 if _blocked_feedback_active and not is_valid else 2
	preview_style.border_width_left = blocked_border
	preview_style.border_width_top = blocked_border
	preview_style.border_width_right = blocked_border
	preview_style.border_width_bottom = blocked_border
	preview_style.border_color = config.active_piece_outline_color if is_valid else config.active_piece_blocked_outline_color
	preview_style.set_corner_radius_all(cell_corner_radius)
	draw_style_box(preview_style, cell_rect)
	var preview_text_color: Color = config.tile_text_dark if is_valid else config.tile_text_light
	_draw_cell_text(cell_rect, value, preview_text_color)


func _draw_merge_flash(cell_rect: Rect2, is_anchor: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = config.merge_flash_color
	style.bg_color.a = config.merge_flash_alpha * _merge_feedback_ratio * (1.0 if is_anchor else 0.65)
	style.border_color = config.active_piece_outline_color
	var border := 4 if is_anchor else 2
	style.border_width_left = border
	style.border_width_top = border
	style.border_width_right = border
	style.border_width_bottom = border
	style.set_corner_radius_all(cell_corner_radius)
	draw_style_box(style, cell_rect)


func _draw_cell_text(cell_rect: Rect2, value: int, text_color: Color) -> void:
	var font := value_font if value_font != null else ThemeDB.fallback_font
	var label := str(int(pow(2.0, value)))
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, value_font_size).x
	draw_string(
		font,
		Vector2(cell_rect.position.x + (cell_rect.size.x - width) * 0.5, cell_rect.position.y + cell_rect.size.y * 0.62),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		value_font_size,
		text_color
	)


func _current_cells() -> Array[Vector2i]:
	if _current_piece == null:
		return []
	var translated: Array[Vector2i] = []
	for cell in _current_piece.get_rotated_cells(_current_rotation):
		translated.append(cell + _current_anchor)
	return translated


func _piece_bounds(cells: Array[Vector2i]) -> Rect2i:
	var min_x := cells[0].x
	var min_y := cells[0].y
	var max_x := cells[0].x
	var max_y := cells[0].y
	for cell in cells:
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
