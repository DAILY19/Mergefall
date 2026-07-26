@tool
class_name PiecePreviewStrip
extends Control

@export_range(1, 5, 1) var visible_card_count := 3:
	set(value):
		visible_card_count = maxi(1, value)
		queue_redraw()

@export_range(4, 24, 1) var card_spacing := 6:
	set(value):
		card_spacing = value
		queue_redraw()

@export_range(5, 24, 1) var card_padding := 6:
	set(value):
		card_padding = value
		queue_redraw()

@export var card_color := Color("f8eddc"):
	set(value):
		card_color = value
		queue_redraw()

@export var empty_card_color := Color("e9dcc8"):
	set(value):
		empty_card_color = value
		queue_redraw()

@export var outline_color := Color("8a6d4a"):
	set(value):
		outline_color = value
		queue_redraw()

@export var title_font: Font:
	set(value):
		title_font = value
		queue_redraw()

@export var label_font: Font:
	set(value):
		label_font = value
		queue_redraw()

@export_group("Art")
@export var visual_set: MergefallVisualSet:
	set(value):
		visual_set = value
		queue_redraw()

@export var title_text := "Next Up":
	set(value):
		title_text = value
		queue_redraw()

@export var show_piece_names := false:
	set(value):
		show_piece_names = value
		queue_redraw()

@export_range(8, 16, 1) var label_font_size := 11:
	set(value):
		label_font_size = value
		queue_redraw()

@export_range(8, 16, 1) var value_font_size := 12:
	set(value):
		value_font_size = value
		queue_redraw()

var _pieces: Array[Resource] = []
var _queue_handoff_ratio := 0.0
var _queue_tween: Tween


func set_pieces(pieces: Array[Resource]) -> void:
	var queue_changed := not _same_piece_queue(_pieces, pieces)
	_pieces = pieces.duplicate()
	if queue_changed and is_inside_tree() and not Engine.is_editor_hint():
		_queue_handoff_ratio = 1.0
		if _queue_tween != null and _queue_tween.is_valid():
			_queue_tween.kill()
		_queue_tween = create_tween()
		_queue_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_queue_tween.tween_method(_set_queue_handoff_ratio, 1.0, 0.0, 0.14)
	queue_redraw()


func clear_pieces() -> void:
	_pieces.clear()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	return Vector2(0, 58)


func _draw() -> void:
	var font := title_font if title_font != null else ThemeDB.fallback_font
	draw_string(font, Vector2(0, 12), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, outline_color)

	var cards_top := 15.0
	var cards_height := maxf(1.0, size.y - cards_top)
	var slot_width := (
		size.x - float(maxi(0, visible_card_count - 1)) * card_spacing
	) / float(visible_card_count)
	for index in visible_card_count:
		var card_rect := Rect2(
			Vector2(index * (slot_width + card_spacing), cards_top),
			Vector2(slot_width, cards_height)
		)
		var piece: Resource = _pieces[index] if index < _pieces.size() else null
		var handoff_offset := (8.0 + index * 2.0) * _queue_handoff_ratio
		draw_set_transform(Vector2(handoff_offset, 0.0))
		_draw_card(card_rect, piece)
		draw_set_transform(Vector2.ZERO)


func _draw_card(card_rect: Rect2, piece: Resource) -> void:
	draw_style_box(_make_card_style(piece != null), card_rect.grow(-1.0))

	if piece == null:
		return

	var display_rotation := _best_display_rotation(piece, card_rect)
	var piece_cells: Array[Vector2i] = piece.get_rotated_cells(display_rotation)
	var bounds := _piece_bounds(piece_cells)
	var grid_size := Vector2(bounds.size.x, bounds.size.y)
	var label_space := 18.0 if show_piece_names else 0.0
	var available := Vector2(
		maxf(1.0, card_rect.size.x - card_padding * 2.0),
		maxf(1.0, card_rect.size.y - label_space - card_padding * 2.0)
	)
	var cell_extent := minf(available.x / maxf(1.0, grid_size.x), available.y / maxf(1.0, grid_size.y))
	var grid_pixels := grid_size * cell_extent
	var shape_area := Rect2(
		card_rect.position + Vector2.ONE * card_padding,
		card_rect.size - Vector2(card_padding * 2.0, card_padding * 2.0 + label_space)
	)
	var grid_origin := shape_area.position + (shape_area.size - grid_pixels) * 0.5
	if show_piece_names:
		var font := label_font if label_font != null else ThemeDB.fallback_font
		var text: String = piece.display_name
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, card_rect.size.x - 12.0, label_font_size)
		draw_string(
			font,
			Vector2(card_rect.position.x + (card_rect.size.x - text_size.x) * 0.5, card_rect.end.y - 7.0),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			card_rect.size.x - 12.0,
			label_font_size,
			outline_color
		)

	var cell_gap := clampf(cell_extent * 0.045, 0.75, 1.5)
	var shape_cell_size := maxf(1.0, cell_extent - cell_gap)
	_draw_piece_connections(piece_cells, bounds, grid_origin, cell_extent, shape_cell_size, piece.preview_color)
	var rotated_values: Array[int] = piece.get_rotated_values(display_rotation)
	for cell_index in piece_cells.size():
		var cell := piece_cells[cell_index]
		var local := Vector2(cell.x - bounds.position.x, cell.y - bounds.position.y)
		var rect := Rect2(
			grid_origin + local * cell_extent + Vector2.ONE * cell_gap * 0.5,
			Vector2.ONE * shape_cell_size
		)
		draw_style_box(_make_piece_cell_style(piece.preview_color), rect)
		if visual_set != null and visual_set.preview_piece_cell_overlay != null:
			draw_texture_rect(visual_set.preview_piece_cell_overlay, rect, false)
		_draw_value(rect, rotated_values[cell_index])


func _draw_piece_connections(
	piece_cells: Array[Vector2i],
	bounds: Rect2i,
	grid_origin: Vector2,
	cell_extent: float,
	cell_size: float,
	fill_color: Color
) -> void:
	var occupied := {}
	for cell in piece_cells:
		occupied[cell] = true
	for cell in piece_cells:
		var local := Vector2(cell.x - bounds.position.x, cell.y - bounds.position.y)
		var center := grid_origin + local * cell_extent + Vector2.ONE * cell_extent * 0.5
		if occupied.has(cell + Vector2i.RIGHT):
			draw_rect(
				Rect2(center - Vector2(0.0, cell_size * 0.34), Vector2(cell_extent, cell_size * 0.68)),
				fill_color,
				true
			)
		if occupied.has(cell + Vector2i.DOWN):
			draw_rect(
				Rect2(center - Vector2(cell_size * 0.34, 0.0), Vector2(cell_size * 0.68, cell_extent)),
				fill_color,
				true
			)


func _draw_value(cell_rect: Rect2, value: int) -> void:
	var font := label_font if label_font != null else ThemeDB.fallback_font
	var label := str(int(pow(2.0, value)))
	var fitted_size := mini(value_font_size, maxi(9, int(cell_rect.size.x * 0.48)))
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted_size).x
	draw_string(
		font,
		Vector2(cell_rect.position.x + (cell_rect.size.x - width) * 0.5, cell_rect.position.y + cell_rect.size.y * 0.62),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fitted_size,
		Color("2f2419")
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


func _best_display_rotation(piece: Resource, card_rect: Rect2) -> int:
	var best_rotation := 0
	var best_extent := 0.0
	var rotation_count := 1
	for rotation_index in rotation_count:
		var bounds := _piece_bounds(piece.get_rotated_cells(rotation_index))
		var available := card_rect.size - Vector2(card_padding * 2.0, card_padding * 2.0)
		var extent := minf(
			available.x / maxf(1.0, bounds.size.x),
			available.y / maxf(1.0, bounds.size.y)
		)
		if extent > best_extent:
			best_extent = extent
			best_rotation = rotation_index
	return best_rotation


func _make_card_style(has_piece: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = card_color if has_piece else empty_card_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = outline_color
	style.set_corner_radius_all(8)
	return style


func _make_piece_cell_style(fill_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = Color(1.0, 0.97, 0.92, 0.4)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(3)
	return style


func _same_piece_queue(left: Array[Resource], right: Array[Resource]) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if left[index] != right[index]:
			return false
	return true


func _set_queue_handoff_ratio(ratio: float) -> void:
	_queue_handoff_ratio = ratio
	queue_redraw()
