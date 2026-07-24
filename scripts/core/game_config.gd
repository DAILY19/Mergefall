class_name GameConfig
extends Resource

const PieceDefinitionScript = preload("res://scripts/pieces/piece_definition.gd")

@export_group("Board")
@export_range(4, 10, 1) var board_width := 6
@export_range(6, 12, 1) var board_height := 8
@export_range(48, 120, 1) var cell_size := 64
@export_range(4, 24, 1) var cell_gap := 8
@export_range(12, 40, 1) var outer_padding := 20

@export_group("Rules")
@export_range(2, 6, 1) var min_merge_group := 2
@export_range(1, 10, 1) var score_per_rank := 10
@export var piece_definitions: Array[Resource] = []

@export_group("Visuals")
@export var background_color := Color("f4efe4")
@export var board_color := Color("d8c3a5")
@export var empty_cell_color := Color("efe0cc")
@export var tile_palette: Array[Color] = [
	Color("f7d27a"),
	Color("ffbf69"),
	Color("ff8c69"),
	Color("f25f5c"),
	Color("c06c84"),
	Color("6c5b7b"),
	Color("355c7d"),
	Color("2a9d8f"),
	Color("264653"),
	Color("111111"),
]
@export var tile_text_light := Color("fff8f0")
@export var tile_text_dark := Color("4a3414")


func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	if piece_definitions.is_empty():
		issues.append("GameConfig requires at least one PieceDefinition.")
	for piece in piece_definitions:
		if piece == null:
			issues.append("GameConfig contains an empty PieceDefinition entry.")
			continue
		if not piece is PieceDefinitionScript:
			issues.append("GameConfig contains a resource that is not a PieceDefinition.")
			continue
		if piece.cells.size() != piece.cell_values.size():
			issues.append("%s has mismatched cells and cell_values." % piece.display_name)
	return issues
