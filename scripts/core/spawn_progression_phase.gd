@tool
class_name SpawnProgressionPhase
extends Resource

@export_range(0, 1000000, 1) var min_completed_turns := 0
@export var displayed_values: Array[int] = [2, 4]
@export var weights: Array[int] = [70, 30]


func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	if displayed_values.size() < 2:
		issues.append("A spawn progression phase requires at least two values.")
	if displayed_values.size() != weights.size():
		issues.append("Spawn progression values and weights must have matching sizes.")
	var seen := {}
	for index in displayed_values.size():
		var value: int = displayed_values[index]
		if value < 2 or (value & (value - 1)) != 0:
			issues.append("Spawn values must be powers of two starting at 2.")
		if seen.has(value):
			issues.append("Spawn progression values must be unique within a phase.")
		seen[value] = true
		if index >= weights.size() or weights[index] <= 0:
			issues.append("Every spawn progression value requires a positive weight.")
	return issues
