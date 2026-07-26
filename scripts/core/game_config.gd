@tool
class_name GameConfig
extends Resource

const PieceDefinitionScript = preload("res://scripts/pieces/piece_definition.gd")
const BOARD_WIDTH := 7
const BOARD_HEIGHT := 9

@export_group("Board")
@export_range(4, 10, 1) var board_width := BOARD_WIDTH
@export_range(6, 12, 1) var board_height := BOARD_HEIGHT
@export_range(48, 120, 1) var cell_size := 64
@export_range(4, 24, 1) var cell_gap := 8
@export_range(12, 40, 1) var outer_padding := 20

@export_group("Rules")
@export_range(2, 6, 1) var min_merge_group := 2
@export_range(1, 10, 1) var score_per_rank := 10
@export_range(2, 20, 1) var merge_charge_threshold := 8
@export var piece_definitions: Array[Resource] = []
@export_range(1, 5, 1) var preview_piece_count := 3
@export var spawn_progression: Resource

@export_group("Visuals")
@export var background_color := Color("f4efe4")
@export var board_color := Color("d8c3a5")
@export var empty_cell_color := Color("efe0cc")
@export var active_piece_valid_color := Color("ffbf69")
@export var active_piece_invalid_color := Color("f25f5c")
@export_range(0.1, 1.0, 0.05) var active_piece_valid_alpha := 0.65
@export_range(0.1, 1.0, 0.05) var active_piece_invalid_alpha := 0.32
@export var active_piece_outline_color := Color("fff8f0")
@export var active_piece_blocked_outline_color := Color("7a1f2b")
@export var merge_flash_color := Color("fff2a8")
@export_range(0.1, 1.0, 0.05) var merge_flash_alpha := 0.75
@export_range(0.1, 1.5, 0.05) var merge_flash_duration_sec := 0.55
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
	if active_piece_valid_alpha <= 0.0 or active_piece_invalid_alpha <= 0.0:
		issues.append("Active piece preview alpha values must be greater than 0.")
	if merge_flash_alpha <= 0.0:
		issues.append("Merge flash alpha must be greater than 0.")
	if merge_flash_duration_sec <= 0.0:
		issues.append("Merge flash duration must be greater than 0.")
	if merge_charge_threshold < 2:
		issues.append("Merge charge threshold must be at least 2.")
	if spawn_progression == null:
		issues.append("GameConfig requires a SpawnProgression resource.")
	elif not spawn_progression.has_method("phase_for_completed_turn") or not spawn_progression.has_method("validate"):
		issues.append("GameConfig.spawn_progression must be a SpawnProgression resource.")
	else:
		for issue in spawn_progression.validate():
			issues.append(issue)
	return issues
