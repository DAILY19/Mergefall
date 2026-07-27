@tool
class_name MergefallVisualSet
extends Resource

## Swappable art references shared by the board and piece queue.
##
## Textures are optional. Board cell textures are drawn over the procedural
## fallback, so transparent detail art can be replaced without losing color or
## readability. Placement and merge textures are overlays by design.

@export_group("Board")
@export var board_overlay: Texture2D
@export var empty_cell_overlay: Texture2D
@export var occupied_cell_overlay: Texture2D
@export var sword_rank_set: MergefallSwordRankSet

@export_group("Active Piece")
@export var active_piece_cell_overlay: Texture2D
@export var valid_placement_overlay: Texture2D
@export var invalid_placement_overlay: Texture2D

@export_group("Feedback")
@export var merge_highlight_overlay: Texture2D

@export_group("Piece Preview")
@export var preview_card_texture: Texture2D
@export var preview_piece_cell_overlay: Texture2D


func get_sword_for_rank(rank: int) -> Texture2D:
	if sword_rank_set == null:
		return null
	return sword_rank_set.get_sword_for_rank(rank)


func get_sword_tint_for_rank(rank: int) -> Color:
	if sword_rank_set == null:
		return Color.WHITE
	return sword_rank_set.get_tint_for_rank(rank)
