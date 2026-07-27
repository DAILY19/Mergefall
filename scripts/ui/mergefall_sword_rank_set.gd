@tool
class_name MergefallSwordRankSet
extends Resource

@export var rank_icons: Array[Texture2D] = []
@export var fallback_icon: Texture2D
@export var rank_names: Array[String] = []
@export var rank_tints: Array[Color] = []


func get_sword_for_rank(rank: int) -> Texture2D:
	var index := _rank_index(rank)
	if index >= 0 and index < rank_icons.size() and rank_icons[index] != null:
		return rank_icons[index]
	return fallback_icon


func get_name_for_rank(rank: int) -> String:
	var index := _rank_index(rank)
	if index >= 0 and index < rank_names.size():
		return rank_names[index]
	return "Relic Sword"


func get_tint_for_rank(rank: int) -> Color:
	var index := _rank_index(rank)
	if index >= 0 and index < rank_tints.size():
		return rank_tints[index]
	return Color.WHITE


func _rank_index(rank: int) -> int:
	if rank <= 0:
		return -1
	if rank_icons.is_empty():
		return -1
	return mini(rank - 1, rank_icons.size() - 1)
