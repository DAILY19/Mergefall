class_name PieceDefinition
extends Resource

@export_group("Identity")
@export var display_name := "Piece"

@export_group("Shape")
@export var cells: Array[Vector2i] = [Vector2i.ZERO]
@export var cell_values: Array[int] = [1]
@export var allow_rotation := true

@export_group("Spawn Rules")
@export_range(1, 100, 1) var spawn_weight := 1

@export_group("Preview")
@export var preview_color := Color("ffbf69")


func get_rotated_cells(rotation_steps: int) -> Array[Vector2i]:
	var rotated: Array[Vector2i] = []
	var normalized_steps := posmod(rotation_steps, 4)
	for cell in cells:
		var current := cell
		for _index in normalized_steps:
			current = Vector2i(-current.y, current.x)
		rotated.append(current)
	return rotated


func get_rotated_values(_rotation_steps: int) -> Array[int]:
	return cell_values.duplicate()
