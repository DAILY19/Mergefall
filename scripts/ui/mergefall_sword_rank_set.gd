@tool
class_name MergefallSwordRankSet
extends Resource

@export var rank_icons: Array[Texture2D] = []
@export var fallback_icon: Texture2D
@export var rank_names: Array[String] = []
@export var rank_tints: Array[Color] = []

## Display name shown in UI for this weapon class (e.g. "Swords", "Axes").
@export var display_name: String = ""

## Multiplier applied to the computed icon draw size.
## Use < 1.0 for smaller native icons (spears/staffs at 16x16)
## to keep their apparent size similar to 32x32 swords/axes.
@export var icon_scale_multiplier: float = 1.0

## Vertical offset in pixels added on top of the default centering offset.
## Positive moves the icon down, negative moves it up.
## Use for 16x16 icons that need less upward clearance from the value badge.
@export var icon_vertical_offset: float = 0.0


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
