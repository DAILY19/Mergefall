@tool
class_name BoardView
extends Control

signal resolution_feedback_finished
signal resolution_event_started(event: Dictionary)

const BoardStateScript = preload("res://scripts/core/board_state.gd")

@export var config: Resource:
	set(value):
		config = value
		_mark_layout_dirty()
		queue_redraw()

@export_group("Layout")
@export_range(0, 320, 1) var top_padding := 148.0:
	set(value):
		top_padding = value
		_mark_layout_dirty()
		queue_redraw()

@export_range(0, 320, 1) var bottom_padding := 16.0:
	set(value):
		bottom_padding = value
		_mark_layout_dirty()
		queue_redraw()

@export_range(0, 200, 1) var board_corner_radius := 24:
	set(value):
		board_corner_radius = value
		queue_redraw()

@export_range(0, 120, 1) var cell_corner_radius := 16:
	set(value):
		cell_corner_radius = value
		queue_redraw()

@export_range(3, 5, 1) var drop_zone_rows := 4:
	set(value):
		drop_zone_rows = value
		_mark_layout_dirty()
		queue_redraw()

@export_group("Art")
@export var visual_set: MergefallVisualSet:
	set(value):
		visual_set = value
		queue_redraw()

@export_group("Typography")
@export var value_font: Font:
	set(value):
		value_font = value
		queue_redraw()

@export_range(8, 64, 1) var value_font_size := 24:
	set(value):
		value_font_size = value
		queue_redraw()

@export_group("Frame")
@export var frame_fill_color := Color(0.86, 0.76, 0.64, 0.92):
	set(value):
		frame_fill_color = value
		queue_redraw()

@export var frame_border_color := Color(1.0, 0.97, 0.92, 0.7):
	set(value):
		frame_border_color = value
		queue_redraw()

@export var shadow_color := Color(0.19, 0.13, 0.09, 0.18):
	set(value):
		shadow_color = value
		queue_redraw()

@export var drop_zone_fill_color := Color(0.90, 0.83, 0.72, 0.70):
	set(value):
		drop_zone_fill_color = value
		queue_redraw()

@export var drop_zone_border_color := Color(0.57, 0.42, 0.27, 0.34):
	set(value):
		drop_zone_border_color = value
		queue_redraw()

var _board_state: BoardState
var _current_piece: Resource
var _current_anchor := Vector2i.ZERO
var _current_rotation := 0
var _game_over := false
var _spawn_feedback_ratio := 0.0
var _blocked_feedback_active := false
var _merge_feedback_steps: Array[Dictionary] = []
var _merge_feedback_ratio := 0.0
var _lock_feedback_cells: Array[Vector2i] = []
var _lock_feedback_ratio := 0.0
var _layout_rect_override := Rect2()
var _layout_dirty := true
var _layout_metrics := {}
var _active_motion_offset := Vector2.ZERO
var _rotation_snap_ratio := 0.0
var _drop_feedback_from: Array[Vector2i] = []
var _drop_feedback_to: Array[Vector2i] = []
var _drop_feedback_ratio := 0.0
var _motion_tween: Tween
var _drop_tween: Tween
var _resolution_board: BoardState
var _resolution_from: Array[Vector2i] = []
var _resolution_to: Array[Vector2i] = []
var _resolution_values: Array[int] = []
var _resolution_steps: Array[Dictionary] = []
var _resolution_events: Array[Dictionary] = []
var _resolution_event_segments: Array[Dictionary] = []
var _resolution_event_boards: Array = []
var _resolution_progress := 1.0
var _resolution_duration := 1.0
var _resolution_tween: Tween

const RESOLUTION_FALL_SEC := 0.28
const RESOLUTION_CONTACT_SEC := 0.14
const RESOLUTION_MERGE_SEC := 0.44
const RESOLUTION_GRAVITY_BASE_SEC := 0.08
const RESOLUTION_GRAVITY_ROW_SEC := 0.045
const RESOLUTION_GRAVITY_MAX_SEC := 0.32
const MIN_EDGE_MARGIN := 8.0
const MAX_EDGE_MARGIN := 18.0
const MIN_INTER_REGION_GAP := 16.0
const MAX_INTER_REGION_GAP := 48.0
const DROP_ZONE_TILE_ROWS := 5.0
const MIN_TILE_SIZE := 28.0
const GAP_TO_TILE_RATIO := 0.115
const MIN_CELL_GAP := 4.0
const MAX_CELL_GAP := 10.0


func set_board_state(board_state: BoardState) -> void:
	_board_state = board_state
	queue_redraw()


func set_active_piece(
	piece: Resource,
	anchor: Vector2i,
	rot: int,
	game_over: bool,
	spawn_ratio: float
) -> void:
	_current_piece = piece
	_current_anchor = anchor
	_current_rotation = rot
	_game_over = game_over
	_spawn_feedback_ratio = clampf(spawn_ratio, 0.0, 1.0)
	queue_redraw()


func play_move_feedback(offset: Vector2i) -> void:
	_active_motion_offset = Vector2(-offset)
	_rotation_snap_ratio = 0.0
	_restart_motion_tween(0.11, Tween.TRANS_QUAD, Tween.EASE_OUT)


func play_rotation_feedback() -> void:
	_active_motion_offset = Vector2.ZERO
	_rotation_snap_ratio = 1.0
	_restart_motion_tween(0.13, Tween.TRANS_BACK, Tween.EASE_OUT)


func play_drop_feedback(from_cells: Array[Vector2i], to_cells: Array[Vector2i]) -> void:
	_drop_feedback_from = _typed_vector2i_array(from_cells)
	_drop_feedback_to = _typed_vector2i_array(to_cells)
	_drop_feedback_ratio = 1.0
	if _drop_tween != null and _drop_tween.is_valid():
		_drop_tween.kill()
	_drop_tween = create_tween()
	_drop_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_drop_tween.tween_method(_set_drop_feedback_ratio, 1.0, 0.0, 0.28)
	_drop_tween.finished.connect(func() -> void:
		_drop_feedback_from.clear()
		_drop_feedback_to.clear()
	)


func play_resolution_feedback(
	before_board: BoardState,
	from_cells: Array[Vector2i],
	values: Array,
	settlement: Dictionary
) -> void:
	_resolution_board = before_board.duplicate_state()
	_resolution_from = _typed_vector2i_array(from_cells)
	_resolution_to = _typed_vector2i_array(settlement.get("landing_cells", []))
	_resolution_values.clear()
	for value in values:
		_resolution_values.append(int(value))
	_resolution_steps.clear()
	for step in settlement.get("steps", []):
		_resolution_steps.append(step.duplicate(true))
	_resolution_events.clear()
	for event in settlement.get("events", []):
		_resolution_events.append(event.duplicate(true))
	_resolution_event_segments = _build_resolution_event_segments(_resolution_events)
	_resolution_event_boards = _build_resolution_event_boards(_resolution_board, _resolution_events)
	_resolution_progress = 0.0
	if _resolution_tween != null and _resolution_tween.is_valid():
		_resolution_tween.kill()
	_resolution_tween = create_tween()
	_resolution_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_resolution_duration = _timeline_duration(_resolution_event_segments)
	for segment in _resolution_event_segments:
		var start: float = float(segment.get("start", 0.0))
		var duration: float = float(segment.get("duration", 0.0))
		var event: Dictionary = segment.get("event", {})
		_resolution_tween.tween_callback(func() -> void:
			resolution_event_started.emit(event.duplicate(true))
		)
		_resolution_tween.tween_method(
			_set_resolution_progress,
			start / _resolution_duration,
			(start + duration) / _resolution_duration,
			duration
		)
	_resolution_tween.finished.connect(func() -> void:
		_resolution_board = null
		_resolution_from.clear()
		_resolution_to.clear()
		_resolution_values.clear()
		_resolution_steps.clear()
		_resolution_events.clear()
		_resolution_event_segments.clear()
		_resolution_event_boards.clear()
		_resolution_progress = 1.0
		queue_redraw()
		resolution_feedback_finished.emit()
	)


func is_resolution_feedback_active() -> bool:
	return _resolution_board != null


func cancel_resolution_feedback() -> void:
	if _resolution_tween != null and _resolution_tween.is_valid():
		_resolution_tween.kill()
	_resolution_board = null
	_resolution_from.clear()
	_resolution_to.clear()
	_resolution_values.clear()
	_resolution_steps.clear()
	_resolution_events.clear()
	_resolution_event_segments.clear()
	_resolution_event_boards.clear()
	_resolution_progress = 1.0
	queue_redraw()


func set_feedback(
	blocked_active: bool,
	merge_steps: Array,
	merge_feedback_ratio: float,
	lock_cells: Array,
	lock_feedback_ratio: float
) -> void:
	_blocked_feedback_active = blocked_active
	_merge_feedback_steps.clear()
	for step in merge_steps:
		_merge_feedback_steps.append(step.duplicate(true))
	_merge_feedback_ratio = clampf(merge_feedback_ratio, 0.0, 1.0)
	_lock_feedback_cells.clear()
	for cell in lock_cells:
		_lock_feedback_cells.append(cell)
	_lock_feedback_ratio = clampf(lock_feedback_ratio, 0.0, 1.0)
	queue_redraw()


func set_layout_rect(layout_rect: Rect2) -> void:
	if _layout_rect_override == layout_rect:
		return
	_layout_rect_override = layout_rect
	_mark_layout_dirty()
	queue_redraw()


func _draw() -> void:
	if config == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color("202020"), true)
		return

	draw_rect(Rect2(Vector2.ZERO, size), config.background_color, true)
	var board_rect := get_board_rect()
	if board_rect.size == Vector2.ZERO:
		return
	_draw_drop_zone_backing(get_drop_zone_rect(board_rect))
	_draw_board_backing(board_rect)

	if _board_state == null:
		return

	var displayed_board: BoardState = _board_state
	if _resolution_board != null:
		displayed_board = _resolution_display_board()
	for y in config.board_height:
		for x in config.board_width:
			var cell_pos := Vector2i(x, y)
			if _resolution_board != null and _resolution_hides_static_cell(cell_pos):
				continue
			var cell_rect := get_cell_rect(board_rect, cell_pos)
			_draw_cell(cell_rect, displayed_board.get_value(cell_pos))

	if _resolution_board != null:
		_draw_resolution_feedback(board_rect)
		return

	if _lock_feedback_ratio > 0.0:
		for pos in _lock_feedback_cells:
			if _board_state.is_inside(pos):
				_draw_lock_flash(get_cell_rect(board_rect, pos))

	if not _merge_feedback_steps.is_empty():
		for step in _merge_feedback_steps:
			for pos in step.get("positions", []):
				if _board_state.is_inside(pos):
					_draw_merge_flash(get_cell_rect(board_rect, pos), false)
					_redraw_cell_value(board_rect, pos)
			var anchor: Vector2i = step.get("anchor", Vector2i.ZERO)
			if _board_state.is_inside(anchor):
				_draw_merge_flash(get_cell_rect(board_rect, anchor), true)
				_redraw_cell_value(board_rect, anchor)

	if _drop_feedback_ratio > 0.0:
		_draw_drop_commitment(board_rect)

	if _game_over or _current_piece == null:
		return

	var preview_cells := _current_cells()
	var can_place_preview: bool = _board_state.can_stage(preview_cells)
	var landing_projection := _landing_projection()
	var landing_cells := _typed_vector2i_array(landing_projection.get("landing_cells", []))
	if landing_cells != preview_cells:
		var rotated_values: Array[int] = _current_piece.get_rotated_values(_current_rotation)
		for index in landing_cells.size():
			var pos: Vector2i = landing_cells[index]
			if _board_state.is_inside(pos):
				_draw_ghost_cell(
					get_cell_rect(board_rect, pos),
					rotated_values[index]
				)

	_draw_piece_connections(
		board_rect,
		preview_cells,
		_preview_fill_color(can_place_preview),
		4,
		true
	)
	for index in preview_cells.size():
		var pos := preview_cells[index]
		if not _is_drawable_staging_cell(pos):
			continue
		var preview_rect := _animated_active_rect(get_cell_rect(board_rect, pos), board_rect, preview_cells)
		_draw_preview_cell(preview_rect, _current_piece.cell_values[index], can_place_preview)


func get_board_rect() -> Rect2:
	return _calculate_gameplay_metrics().get("board_rect", Rect2())


func get_drop_zone_rect(board_rect: Rect2 = Rect2()) -> Rect2:
	var metrics := _calculate_gameplay_metrics()
	if board_rect.size != Vector2.ZERO and board_rect != metrics.get("board_rect", Rect2()):
		var grid := _grid_metrics(board_rect)
		var drop_height: float = DROP_ZONE_TILE_ROWS * grid["cell"] + floor(DROP_ZONE_TILE_ROWS) * grid["gap"]
		return Rect2(
			Vector2(board_rect.position.x, board_rect.position.y - metrics.get("structure_gap", grid["gap"]) - drop_height),
			Vector2(board_rect.size.x, drop_height)
		)
	return metrics.get("drop_zone_rect", Rect2())


func get_cell_rect(board_rect: Rect2, cell_pos: Vector2i) -> Rect2:
	var metrics := _grid_metrics(board_rect)
	var scaled_cell: float = metrics["cell"]
	var scaled_gap: float = metrics["gap"]
	return Rect2(
		board_rect.position + Vector2(
			scaled_gap + cell_pos.x * (scaled_cell + scaled_gap),
			scaled_gap + cell_pos.y * (scaled_cell + scaled_gap)
		),
		Vector2.ONE * scaled_cell
	)


func _grid_metrics(board_rect: Rect2) -> Dictionary:
	if config == null:
		return {"cell": 0.0, "gap": 0.0}
	var cached := _calculate_gameplay_metrics()
	if board_rect == cached.get("board_rect", Rect2()):
		return {"cell": cached.get("tile_size", 0.0), "gap": cached.get("cell_gap", 0.0)}
	var unit := board_rect.size.x / float(config.board_width * config.cell_size + (config.board_width + 1) * config.cell_gap)
	return {
		"cell": config.cell_size * unit,
		"gap": config.cell_gap * unit
	}


func _calculate_gameplay_metrics() -> Dictionary:
	if not _layout_dirty:
		return _layout_metrics
	_layout_dirty = false
	_layout_metrics = _empty_layout_metrics()
	if config == null:
		return _layout_metrics
	var layout_rect := _resolved_layout_rect()
	if layout_rect.size.x <= 0.0 or layout_rect.size.y <= 0.0:
		return _layout_metrics

	var edge_margin := clampf(layout_rect.size.x * 0.025, MIN_EDGE_MARGIN, MAX_EDGE_MARGIN)
	var usable_width := maxf(1.0, layout_rect.size.x - edge_margin * 2.0)
	var preferred_gap := clampf(config.cell_gap, MIN_CELL_GAP, MAX_CELL_GAP)
	var width_tile := (usable_width - float(config.board_width + 1) * preferred_gap) / float(config.board_width)
	var vertical_gap := clampf(width_tile * GAP_TO_TILE_RATIO, MIN_CELL_GAP, MAX_CELL_GAP)
	var width_limited_tile := (usable_width - float(config.board_width + 1) * vertical_gap) / float(config.board_width)
	var structure_gap := clampf(layout_rect.size.y * 0.028, MIN_INTER_REGION_GAP, MAX_INTER_REGION_GAP)
	var drop_height_units := DROP_ZONE_TILE_ROWS
	var vertical_units := float(config.board_height) + drop_height_units
	var vertical_gaps: float = float(config.board_height + 1) + floor(drop_height_units) + 1.0
	var height_limited_tile: float = (
		layout_rect.size.y - structure_gap - vertical_gaps * vertical_gap
	) / vertical_units
	var tile_size := maxf(MIN_TILE_SIZE, floor(minf(width_limited_tile, height_limited_tile)))
	var cell_gap := clampf(tile_size * GAP_TO_TILE_RATIO, MIN_CELL_GAP, MAX_CELL_GAP)
	var board_width := float(config.board_width) * tile_size + float(config.board_width + 1) * cell_gap
	var board_height := float(config.board_height) * tile_size + float(config.board_height + 1) * cell_gap
	var drop_height: float = DROP_ZONE_TILE_ROWS * tile_size + floor(DROP_ZONE_TILE_ROWS) * cell_gap
	var structure_height: float = drop_height + structure_gap + board_height
	var structure_x := layout_rect.position.x + (layout_rect.size.x - board_width) * 0.5
	var structure_y := layout_rect.position.y + maxf(0.0, (layout_rect.size.y - structure_height) * 0.5)
	var drop_rect := Rect2(Vector2(structure_x, structure_y), Vector2(board_width, drop_height))
	var board_rect := Rect2(
		Vector2(structure_x, drop_rect.end.y + structure_gap),
		Vector2(board_width, board_height)
	)
	_layout_metrics = {
		"tile_size": tile_size,
		"cell_gap": cell_gap,
		"gameplay_width": board_width,
		"available_rect": layout_rect,
		"drop_zone_rect": drop_rect,
		"board_rect": board_rect,
		"active_piece_origin": drop_rect.position + Vector2(cell_gap, cell_gap),
		"structure_gap": structure_gap,
		"structure_height": structure_height
	}
	return _layout_metrics


func _empty_layout_metrics() -> Dictionary:
	return {
		"tile_size": 0.0,
		"cell_gap": 0.0,
		"gameplay_width": 0.0,
		"available_rect": Rect2(),
		"drop_zone_rect": Rect2(),
		"board_rect": Rect2(),
		"active_piece_origin": Vector2.ZERO,
		"structure_gap": 0.0,
		"structure_height": 0.0
	}


func _mark_layout_dirty() -> void:
	_layout_dirty = true


func _draw_drop_zone_backing(drop_rect: Rect2) -> void:
	if drop_rect.size == Vector2.ZERO:
		return
	draw_style_box(_make_fill_style(drop_zone_fill_color, drop_zone_border_color, 2, mini(board_corner_radius, 14)), drop_rect)


func _draw_board_backing(board_rect: Rect2) -> void:
	draw_style_box(_make_fill_style(config.board_color, Color.TRANSPARENT, 0, board_corner_radius), board_rect)
	_draw_art_overlay(visual_set.board_overlay if visual_set != null else null, board_rect)


func _draw_cell(cell_rect: Rect2, value: int) -> void:
	draw_style_box(_make_cell_style(value), cell_rect)
	var overlay: Texture2D = null
	if visual_set != null:
		overlay = visual_set.occupied_cell_overlay if value > 0 else visual_set.empty_cell_overlay
	_draw_art_overlay(overlay, cell_rect)

	if value > 0:
		_draw_occupied_cell_highlight(cell_rect)
		var text_color := _tile_text_color(value)
		_draw_cell_text(cell_rect, value, text_color)


func _draw_preview_cell(cell_rect: Rect2, value: int, is_valid: bool) -> void:
	draw_style_box(_make_preview_style(is_valid), cell_rect)
	if visual_set != null:
		_draw_art_overlay(visual_set.active_piece_cell_overlay, cell_rect)
	var preview_text_color: Color = config.tile_text_dark if is_valid else config.tile_text_light
	_draw_cell_text(cell_rect, value, preview_text_color)


func _draw_lock_flash(cell_rect: Rect2) -> void:
	var settle := sin((1.0 - _lock_feedback_ratio) * PI)
	var color := Color(1.0, 0.97, 0.82, (0.38 + settle * 0.24) * _lock_feedback_ratio)
	var inset := 2.0 + settle * 2.0
	var style := _make_fill_style(Color.TRANSPARENT, color, 3, cell_corner_radius)
	draw_style_box(style, cell_rect.grow(-inset))


func _draw_ghost_cell(cell_rect: Rect2, value: int) -> void:
	var ghost_rect := cell_rect.grow(-2.0)
	var ghost_fill: Color = config.active_piece_valid_color
	ghost_fill.a = 0.07
	var ghost_outline: Color = config.active_piece_valid_color.darkened(0.18)
	ghost_outline.a = 0.58
	var ghost_style := _make_fill_style(
		ghost_fill,
		ghost_outline,
		2,
		_connected_corner_radius(cell_rect)
	)
	draw_style_box(ghost_style, ghost_rect)
	var text_color: Color = config.tile_text_dark
	text_color.a = 0.62
	_draw_cell_text(ghost_rect, value, text_color)


func _draw_piece_connections(
	board_rect: Rect2,
	piece_cells: Array[Vector2i],
	fill_color: Color,
	inset: int,
	animate_active: bool = false
) -> void:
	var occupied := {}
	for cell in piece_cells:
		occupied[cell] = true
	for cell in piece_cells:
		if not _is_drawable_staging_cell(cell):
			continue
		var rect := get_cell_rect(board_rect, cell)
		if animate_active:
			rect = _animated_active_rect(rect, board_rect, piece_cells)
		rect = rect.grow(-float(inset))
		if occupied.has(cell + Vector2i.RIGHT):
			var right_rect := get_cell_rect(board_rect, cell + Vector2i.RIGHT)
			if animate_active:
				right_rect = _animated_active_rect(right_rect, board_rect, piece_cells)
			right_rect = right_rect.grow(-float(inset))
			draw_rect(
				Rect2(
					Vector2(rect.get_center().x, rect.position.y),
					Vector2(right_rect.get_center().x - rect.get_center().x, rect.size.y)
				),
				fill_color,
				true
			)
		if occupied.has(cell + Vector2i.DOWN):
			var down_rect := get_cell_rect(board_rect, cell + Vector2i.DOWN)
			if animate_active:
				down_rect = _animated_active_rect(down_rect, board_rect, piece_cells)
			down_rect = down_rect.grow(-float(inset))
			draw_rect(
				Rect2(
					Vector2(rect.position.x, rect.get_center().y),
					Vector2(rect.size.x, down_rect.get_center().y - rect.get_center().y)
				),
				fill_color,
				true
			)


func _draw_merge_flash(cell_rect: Rect2, is_anchor: bool) -> void:
	var intensity := 1.0 if is_anchor else 0.65
	var pop := sin((1.0 - _merge_feedback_ratio) * PI)
	var pulse_rect := cell_rect.grow(pop * (2.5 if is_anchor else 1.5))
	var merge_color: Color = config.merge_flash_color
	merge_color.a = config.merge_flash_alpha * _merge_feedback_ratio * intensity
	draw_style_box(_make_merge_style(is_anchor), pulse_rect)
	if visual_set != null:
		_draw_art_overlay(
			visual_set.merge_highlight_overlay,
			pulse_rect,
			Color(1, 1, 1, merge_color.a)
		)


func _draw_drop_commitment(board_rect: Rect2) -> void:
	var count := mini(_drop_feedback_from.size(), _drop_feedback_to.size())
	for index in count:
		var from_center := get_cell_rect(board_rect, _drop_feedback_from[index]).get_center()
		var to_center := get_cell_rect(board_rect, _drop_feedback_to[index]).get_center()
		var trail_color: Color = config.active_piece_valid_color
		trail_color.a = 0.18 * _drop_feedback_ratio
		draw_line(from_center, to_center, trail_color, 3.0, true)
		var landing_rect := get_cell_rect(board_rect, _drop_feedback_to[index]).grow(-3.0)
		var landing_color: Color = config.active_piece_outline_color
		landing_color.a = 0.34 * _drop_feedback_ratio
		draw_arc(
			landing_rect.get_center(),
			landing_rect.size.x * (0.42 + 0.08 * (1.0 - _drop_feedback_ratio)),
			0.0,
			TAU,
			20,
			landing_color,
			2.0,
			true
		)


func _draw_resolution_feedback(board_rect: Rect2) -> void:
	var elapsed := _resolution_elapsed()
	var segment := _resolution_segment_at(elapsed)
	if segment.is_empty():
		return
	var event: Dictionary = segment.get("event", {})
	var local_ratio := clampf(
		(elapsed - float(segment.get("start", 0.0))) / maxf(0.001, float(segment.get("duration", 0.001))),
		0.0,
		1.0
	)
	match event.get("type", ""):
		"rigid_landing":
			_draw_rigid_landing_event(board_rect, local_ratio)
		"gravity_step":
			_draw_gravity_event(board_rect, event, local_ratio)
		"merge_wave":
			_draw_merge_group(board_rect, event, local_ratio)


func _draw_rigid_landing_event(board_rect: Rect2, ratio: float) -> void:
	var max_distance := 1
	for index in mini(_resolution_from.size(), _resolution_to.size()):
		max_distance = maxi(max_distance, _resolution_to[index].y - _resolution_from[index].y)
	var resolved_steps := ease(ratio, 1.35) * float(max_distance)
	for index in mini(_resolution_from.size(), _resolution_to.size()):
		var from := _resolution_from[index]
		var distance := maxi(0, _resolution_to[index].y - from.y)
		var shown_steps := minf(float(distance), resolved_steps)
		var cell_rect := get_cell_rect(board_rect, from)
		var row_step := get_cell_rect(board_rect, Vector2i(0, 1)).position.y - get_cell_rect(board_rect, Vector2i.ZERO).position.y
		cell_rect.position.y += shown_steps * row_step
		_draw_resolution_cell(cell_rect, _resolution_values[index], false, 1.0)


func _draw_gravity_event(board_rect: Rect2, event: Dictionary, ratio: float) -> void:
	var event_duration := _event_duration(event)
	for move in event.get("moves", []):
		var from: Vector2i = move.get("from", Vector2i.ZERO)
		var to: Vector2i = move.get("to", Vector2i.ZERO)
		var value: int = int(move.get("value", 1))
		var move_duration := _gravity_move_duration(int(move.get("distance", to.y - from.y)))
		var move_ratio := clampf(ratio * event_duration / move_duration, 0.0, 1.0)
		var eased := ease(move_ratio, 1.45)
		var from_rect := get_cell_rect(board_rect, from)
		var to_rect := get_cell_rect(board_rect, to)
		var moving_rect := from_rect
		moving_rect.position = from_rect.position.lerp(to_rect.position, eased)
		_draw_resolution_cell(moving_rect, value, false, 1.0)

func _draw_merge_group(board_rect: Rect2, group: Dictionary, ratio: float) -> void:
	for step in group.get("steps", []):
		_draw_merge_step(board_rect, step, ratio)


func _draw_merge_step(board_rect: Rect2, step: Dictionary, ratio: float) -> void:
	var source: Vector2i = step.get("source", Vector2i.ZERO)
	var anchor: Vector2i = step.get("anchor", Vector2i.ZERO)
	if not _board_state.is_inside(source) or not _board_state.is_inside(anchor):
		return
	var source_rect := get_cell_rect(board_rect, source)
	var anchor_rect := get_cell_rect(board_rect, anchor)
	var travel_ratio := ease(clampf(ratio / 0.68, 0.0, 1.0), 1.6)
	var moving_rect := source_rect
	moving_rect.position = source_rect.position.lerp(anchor_rect.position, travel_ratio)
	var focus_color: Color = config.merge_flash_color
	focus_color.a = 0.94
	draw_line(source_rect.get_center(), anchor_rect.get_center(), Color(focus_color, 0.54), 4.0, true)
	_draw_resolution_cell(anchor_rect, int(step.get("from_value", 1)), true, 1.0)
	_draw_resolution_cell(moving_rect, int(step.get("from_value", 1)), true, 1.0)
	if ratio >= 0.62:
		var result_ratio := clampf((ratio - 0.62) / 0.38, 0.0, 1.0)
		var result_rect := anchor_rect.grow(sin(result_ratio * PI) * 5.0)
		_draw_resolution_cell(result_rect, int(step.get("to_value", 2)), true, 1.0)
		var ring := _make_fill_style(Color.TRANSPARENT, Color(focus_color, 1.0 - result_ratio * 0.25), 4, cell_corner_radius)
		draw_style_box(ring, result_rect.grow(3.0))


func _resolution_elapsed() -> float:
	return clampf(_resolution_progress, 0.0, 1.0) * _resolution_duration


func _resolution_display_board():
	var segment := _resolution_segment_at(_resolution_elapsed())
	if segment.is_empty():
		return _resolution_board
	var index: int = int(segment.get("index", 0))
	if index >= 0 and index < _resolution_event_boards.size():
		return _resolution_event_boards[index]
	return _resolution_board


func _resolution_hides_static_cell(cell_pos: Vector2i) -> bool:
	var segment := _resolution_segment_at(_resolution_elapsed())
	if segment.is_empty():
		return false
	var event: Dictionary = segment.get("event", {})
	match event.get("type", ""):
		"gravity_step":
			for move in event.get("moves", []):
				if move.get("from", Vector2i.ZERO) == cell_pos:
					return true
		"merge_wave":
			for step in event.get("steps", []):
				for pos in step.get("positions", []):
					if pos == cell_pos:
						return true
	return false


func _draw_resolution_cell(cell_rect: Rect2, value: int, is_merge: bool, emphasis: float) -> void:
	var fill: Color = config.merge_flash_color if is_merge else config.active_piece_valid_color
	fill.a = (0.88 if is_merge else 0.76) * emphasis
	var outline: Color = config.merge_flash_color.darkened(0.24) if is_merge else config.active_piece_outline_color
	outline.a = 0.96
	draw_style_box(
		_make_fill_style(fill, outline, 4 if is_merge else 3, mini(cell_corner_radius, 8)),
		cell_rect.grow(-2.0)
	)
	_draw_cell_text(cell_rect.grow(-2.0), value, config.tile_text_dark)


func _build_resolution_event_segments(events: Array[Dictionary]) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var start := 0.0
	for index in events.size():
		var event := events[index]
		var duration := _event_duration(event)
		if duration <= 0.0:
			continue
		segments.append({
			"index": index,
			"event": event,
			"start": start,
			"duration": duration
		})
		start += duration
	return segments


func _event_duration(event: Dictionary) -> float:
	match event.get("type", ""):
		"rigid_landing":
			return RESOLUTION_FALL_SEC + RESOLUTION_CONTACT_SEC
		"gravity_step":
			var max_distance := 1
			for move in event.get("moves", []):
				max_distance = maxi(max_distance, int(move.get("distance", 1)))
			return _gravity_move_duration(max_distance)
		"merge_wave":
			return RESOLUTION_MERGE_SEC
	return 0.0


func _gravity_move_duration(distance: int) -> float:
	return minf(
		RESOLUTION_GRAVITY_MAX_SEC,
		RESOLUTION_GRAVITY_BASE_SEC + float(maxi(1, distance)) * RESOLUTION_GRAVITY_ROW_SEC
	)


func _timeline_duration(segments: Array[Dictionary]) -> float:
	var duration := 0.0
	for segment in segments:
		duration = maxf(duration, float(segment.get("start", 0.0)) + float(segment.get("duration", 0.0)))
	return maxf(duration, 0.001)


func _resolution_segment_at(elapsed: float) -> Dictionary:
	for segment in _resolution_event_segments:
		var start := float(segment.get("start", 0.0))
		var duration := float(segment.get("duration", 0.0))
		if elapsed >= start and elapsed <= start + duration:
			return segment
	return {}


func _build_resolution_event_boards(before_board: BoardState, events: Array[Dictionary]) -> Array:
	var boards := []
	var board = before_board.duplicate_state()
	for event in events:
		boards.append(board.duplicate_state())
		_apply_resolution_event_to_board(board, event)
	return boards


func _apply_resolution_event_to_board(board: BoardState, event: Dictionary) -> void:
	match event.get("type", ""):
		"rigid_landing":
			var to_cells: Array = event.get("to", [])
			for index in mini(to_cells.size(), _resolution_values.size()):
				board.set_value(to_cells[index], _resolution_values[index])
		"gravity_step":
			for move in event.get("moves", []):
				board.set_value(move.get("from", Vector2i.ZERO), 0)
			for move in event.get("moves", []):
				board.set_value(move.get("to", Vector2i.ZERO), int(move.get("value", 1)))
		"merge_wave":
			for step in event.get("steps", []):
				for pos in step.get("positions", []):
					board.set_value(pos, 0)
			for step in event.get("steps", []):
				board.set_value(step.get("anchor", Vector2i.ZERO), int(step.get("to_value", 1)))


func _animated_active_rect(
	cell_rect: Rect2,
	board_rect: Rect2,
	piece_cells: Array[Vector2i]
) -> Rect2:
	var step := Vector2(
		get_cell_rect(board_rect, Vector2i(1, 0)).position.x - get_cell_rect(board_rect, Vector2i.ZERO).position.x,
		get_cell_rect(board_rect, Vector2i(0, 1)).position.y - get_cell_rect(board_rect, Vector2i.ZERO).position.y
	)
	var rect := cell_rect
	rect.position += _active_motion_offset * step
	if _rotation_snap_ratio <= 0.0 or piece_cells.is_empty():
		return rect
	var bounds := _piece_bounds(piece_cells)
	var first := get_cell_rect(board_rect, bounds.position)
	var last := get_cell_rect(board_rect, bounds.end - Vector2i.ONE)
	var pivot := Rect2(first.position, last.end - first.position).get_center()
	var scale_factor := 1.0 - 0.08 * _rotation_snap_ratio
	var center := pivot + (rect.get_center() - pivot) * scale_factor
	return Rect2(center - rect.size * scale_factor * 0.5, rect.size * scale_factor)


func _is_drawable_staging_cell(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < config.board_width and pos.y >= -drop_zone_rows and pos.y < config.board_height


func _restart_motion_tween(
	duration: float,
	transition: Tween.TransitionType,
	easing: Tween.EaseType
) -> void:
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = create_tween()
	_motion_tween.set_trans(transition).set_ease(easing)
	_motion_tween.set_parallel(true)
	_motion_tween.tween_method(_set_active_motion_ratio, 1.0, 0.0, duration)
	_motion_tween.tween_method(_set_rotation_snap_ratio, _rotation_snap_ratio, 0.0, duration)


func _set_active_motion_ratio(ratio: float) -> void:
	if _active_motion_offset != Vector2.ZERO:
		_active_motion_offset = _active_motion_offset.normalized() * ratio
	queue_redraw()


func _set_rotation_snap_ratio(ratio: float) -> void:
	_rotation_snap_ratio = ratio
	queue_redraw()


func _set_drop_feedback_ratio(ratio: float) -> void:
	_drop_feedback_ratio = ratio
	queue_redraw()


func _set_resolution_progress(progress: float) -> void:
	_resolution_progress = progress
	queue_redraw()


func _draw_cell_text(cell_rect: Rect2, value: int, text_color: Color) -> void:
	var font := value_font if value_font != null else ThemeDB.fallback_font
	var label := str(int(pow(2.0, value)))
	var dynamic_font_size := _fitted_value_font_size(font, label, cell_rect)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, dynamic_font_size).x
	var text_position := Vector2(
		cell_rect.position.x + (cell_rect.size.x - width) * 0.5,
		cell_rect.position.y + cell_rect.size.y * 0.64
	)
	var outline_color := Color(1, 1, 1, 0.82) if text_color.get_luminance() < 0.5 else Color(0.08, 0.06, 0.04, 0.72)
	draw_string_outline(
		font,
		text_position,
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		dynamic_font_size,
		2 if dynamic_font_size >= 16 else 1,
		outline_color
	)
	draw_string(
		font,
		text_position,
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		dynamic_font_size,
		text_color
	)


func _resolved_layout_rect() -> Rect2:
	if _layout_rect_override.size.x > 0.0 and _layout_rect_override.size.y > 0.0:
		return _layout_rect_override
	return Rect2(Vector2.ZERO, size)


func _current_cells() -> Array[Vector2i]:
	if _current_piece == null:
		return []
	var translated: Array[Vector2i] = []
	for cell in _current_piece.get_rotated_cells(_current_rotation):
		translated.append(cell + _current_anchor)
	return translated


func _landing_cells() -> Array[Vector2i]:
	return _typed_vector2i_array(_landing_projection().get("landing_cells", []))


func _landing_projection() -> Dictionary:
	var cells := _current_cells()
	if cells.is_empty():
		return {"landing_cells": cells, "steps": []}
	return _board_state.project_settlement(
		cells,
		_current_piece.get_rotated_values(_current_rotation)
	)


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


func _draw_art_overlay(texture: Texture2D, rect: Rect2, draw_modulate: Color = Color.WHITE) -> void:
	if texture != null:
		draw_texture_rect(texture, rect, true, draw_modulate)


func _typed_vector2i_array(source: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for value in source:
		typed.append(value as Vector2i)
	return typed


func _draw_occupied_cell_highlight(cell_rect: Rect2) -> void:
	var inset := maxf(3.0, cell_rect.size.x * 0.08)
	var top_start := cell_rect.position + Vector2(inset, inset)
	var top_end := Vector2(cell_rect.end.x - inset, cell_rect.position.y + inset)
	draw_line(top_start, top_end, Color(1, 1, 1, 0.42), 2.0, true)


func _fitted_value_font_size(font: Font, label: String, cell_rect: Rect2) -> int:
	var font_size := clampi(int(cell_rect.size.x * 0.46), 15, value_font_size)
	var max_width := cell_rect.size.x * 0.82
	while font_size > 13 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		font_size -= 1
	return font_size


func _redraw_cell_value(board_rect: Rect2, cell_pos: Vector2i) -> void:
	var value := _board_state.get_value(cell_pos)
	if value > 0:
		_draw_cell_text(get_cell_rect(board_rect, cell_pos), value, _tile_text_color(value))


func _make_cell_style(value: int) -> StyleBoxFlat:
	var is_filled := value > 0
	var fill_color: Color = _tile_fill_color(value) if is_filled else config.empty_cell_color
	return _make_fill_style(
		fill_color,
		fill_color.darkened(0.28) if is_filled else Color(0.42, 0.32, 0.22, 0.34),
		2,
		mini(cell_corner_radius, 8) if is_filled else cell_corner_radius
	)


func _make_preview_style(is_valid: bool) -> StyleBoxFlat:
	var border_width := 4
	if _spawn_feedback_ratio > 0.0:
		border_width = 5
	if _blocked_feedback_active and not is_valid:
		border_width = 5
	var outline_color: Color = config.active_piece_outline_color
	if _spawn_feedback_ratio > 0.0:
		outline_color = outline_color.lerp(config.merge_flash_color, _spawn_feedback_ratio * 0.65)
	return _make_fill_style(
		_preview_fill_color(is_valid),
		outline_color if is_valid else config.active_piece_blocked_outline_color,
		border_width,
		mini(cell_corner_radius, 8)
	)


func _connected_corner_radius(cell_rect: Rect2) -> int:
	return mini(cell_corner_radius, maxi(4, int(cell_rect.size.x * 0.13)))


func _make_merge_style(is_anchor: bool) -> StyleBoxFlat:
	var intensity := 1.0 if is_anchor else 0.65
	var fill_color: Color = config.merge_flash_color
	fill_color.a = minf(0.2, config.merge_flash_alpha * _merge_feedback_ratio * 0.22) * intensity
	var border_color: Color = config.merge_flash_color
	border_color.a = maxf(0.55, _merge_feedback_ratio) * intensity
	return _make_fill_style(fill_color, border_color, 5 if is_anchor else 3, cell_corner_radius)


func _make_fill_style(fill_color: Color, border_color: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.set_corner_radius_all(radius)
	return style


func _tile_fill_color(value: int) -> Color:
	if value <= 0 or config.tile_palette.is_empty():
		return config.empty_cell_color
	return config.tile_palette[(value - 1) % config.tile_palette.size()]


func _tile_text_color(value: int) -> Color:
	return config.tile_text_dark if value <= 2 else config.tile_text_light


func _preview_fill_color(is_valid: bool) -> Color:
	var fill_color: Color = config.active_piece_valid_color if is_valid else config.active_piece_invalid_color
	fill_color.a = config.active_piece_valid_alpha if is_valid else config.active_piece_invalid_alpha
	return fill_color
