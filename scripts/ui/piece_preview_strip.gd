@tool
class_name PiecePreviewStrip
extends Control

@export_range(1, 5, 1) var visible_card_count := 3:
	set(value):
		visible_card_count = maxi(1, value)
		queue_redraw()

@export_range(48, 120, 1) var card_width := 72:
	set(value):
		card_width = value
		queue_redraw()

@export_range(56, 160, 1) var card_height := 92:
	set(value):
		card_height = value
		queue_redraw()

@export_range(6, 24, 1) var card_spacing := 10:
	set(value):
		card_spacing = value
		queue_redraw()

@export_range(8, 24, 1) var card_padding := 12:
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

@export var card_texture: Texture2D:
	set(value):
		card_texture = value
		queue_redraw()

@export var title_text := "Next Up":
	set(value):
		title_text = value
		queue_redraw()

var _pieces: Array[Resource] = []


func set_pieces(pieces: Array[Resource]) -> void:
	_pieces = pieces.duplicate()
	queue_redraw()


func clear_pieces() -> void:
	_pieces.clear()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var cards_width := visible_card_count * card_width + maxi(0, visible_card_count - 1) * card_spacing
	return Vector2(cards_width, card_height + 34)


func _draw() -> void:
	var font := title_font if title_font != null else ThemeDB.fallback_font
	draw_string(font, Vector2(0, 20), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, outline_color)

	for index in visible_card_count:
		var card_rect := Rect2(
			Vector2(index * (card_width + card_spacing), 30),
			Vector2(card_width, card_height)
		)
		var piece: Resource = _pieces[index] if index < _pieces.size() else null
		_draw_card(card_rect, piece)


func _draw_card(card_rect: Rect2, piece: Resource) -> void:
	if card_texture != null:
		draw_texture_rect(card_texture, card_rect, true, Color.WHITE if piece != null else Color(1, 1, 1, 0.72))
	else:
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = card_color if piece != null else empty_card_color
		card_style.border_width_left = 2
		card_style.border_width_top = 2
		card_style.border_width_right = 2
		card_style.border_width_bottom = 2
		card_style.border_color = outline_color
		card_style.set_corner_radius_all(18)
		draw_style_box(card_style, card_rect)

	if piece == null:
		return

	var piece_cells: Array[Vector2i] = piece.get_rotated_cells(0)
	var bounds := _piece_bounds(piece_cells)
	var grid_size := Vector2(bounds.size.x, bounds.size.y)
	var available := Vector2(card_rect.size.x - card_padding * 2.0, card_rect.size.y - 34.0 - card_padding * 2.0)
	var cell_extent := minf(available.x / maxf(1.0, grid_size.x), available.y / maxf(1.0, grid_size.y))
	var grid_pixels := grid_size * cell_extent
	var grid_origin := Vector2(
		card_rect.position.x + (card_rect.size.x - grid_pixels.x) * 0.5,
		card_rect.position.y + 14.0
	)
	var font := label_font if label_font != null else ThemeDB.fallback_font
	var text: String = piece.display_name
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, card_rect.size.x - 12.0, 13)
	draw_string(
		font,
		Vector2(card_rect.position.x + (card_rect.size.x - text_size.x) * 0.5, card_rect.end.y - 10.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		card_rect.size.x - 12.0,
		13,
		outline_color
	)

	for cell_index in piece_cells.size():
		var cell := piece_cells[cell_index]
		var local := Vector2(cell.x - bounds.position.x, cell.y - bounds.position.y)
		var rect := Rect2(
			grid_origin + local * cell_extent,
			Vector2.ONE * maxf(8.0, cell_extent - 4.0)
		)
		var tile_style := StyleBoxFlat.new()
		tile_style.bg_color = piece.preview_color
		tile_style.set_corner_radius_all(10)
		draw_style_box(tile_style, rect)
		_draw_value(rect, piece.cell_values[cell_index])


func _draw_value(cell_rect: Rect2, value: int) -> void:
	var font := label_font if label_font != null else ThemeDB.fallback_font
	var label := str(int(pow(2.0, value)))
	var font_size := 14
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(
		font,
		Vector2(cell_rect.position.x + (cell_rect.size.x - width) * 0.5, cell_rect.position.y + cell_rect.size.y * 0.62),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
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
