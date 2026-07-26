class_name BoardState
extends RefCounted

var width := 0
var height := 0
var cells: Array = []


func setup(board_width: int, board_height: int) -> void:
	width = board_width
	height = board_height
	cells.clear()
	for y in height:
		var row: Array[int] = []
		for _x in width:
			row.append(0)
		cells.append(row)


func duplicate_state():
	var clone = get_script().new()
	clone.width = width
	clone.height = height
	for row in cells:
		clone.cells.append(row.duplicate())
	return clone


func is_inside(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < width and position.y >= 0 and position.y < height


func get_value(position: Vector2i) -> int:
	if not is_inside(position):
		return -1
	return cells[position.y][position.x]


func set_value(position: Vector2i, value: int) -> void:
	if is_inside(position):
		cells[position.y][position.x] = value


func can_place(cells_to_place: Array) -> bool:
	for cell in cells_to_place:
		if not is_inside(cell):
			return false
		if get_value(cell) != 0:
			return false
	return true


## Staging permits cells above the visible board. Horizontal overflow, cells below
## the floor, and overlap with visible settled cells are still illegal.
func can_stage(cells_to_stage: Array) -> bool:
	for cell in cells_to_stage:
		if cell.x < 0 or cell.x >= width or cell.y >= height:
			return false
		if cell.y >= 0 and get_value(cell) != 0:
			return false
	return true


func can_settle(cells_to_drop: Array, values: Array = []) -> bool:
	if not can_stage(cells_to_drop):
		return false
	return bool(project_settlement(cells_to_drop, values).get("legal", false))


func place_cells(cells_to_place: Array, values: Array) -> void:
	for index in cells_to_place.size():
		set_value(cells_to_place[index], values[index])


func get_drop_distance(cells_to_drop: Array) -> int:
	var landing := get_landing_cells(cells_to_drop)
	if landing.size() != cells_to_drop.size() or landing.is_empty():
		return 0
	var distance: int = landing[0].y - cells_to_drop[0].y
	for index in landing.size():
		if landing[index].y - cells_to_drop[index].y != distance:
			return 0
	return distance


func get_rigid_landing_cells(cells_to_drop: Array) -> Array[Vector2i]:
	if cells_to_drop.is_empty() or not can_stage(cells_to_drop):
		return []
	if not _can_occupy_drop_offset(cells_to_drop, 0):
		return []
	var distance := 0
	while _can_occupy_drop_offset(cells_to_drop, distance + 1):
		distance += 1
	var landing: Array[Vector2i] = []
	for cell in cells_to_drop:
		var landed: Vector2i = cell + Vector2i(0, distance)
		if landed.y < 0 or not is_inside(landed):
			return []
		landing.append(landed)
	return landing


## Returns one landing position for every source cell, even if that tile is later
## consumed by horizontal resolution. This keeps the drop preview whole.
func get_landing_cells(cells_to_drop: Array, values: Array = []) -> Array[Vector2i]:
	var result := project_settlement(cells_to_drop, values)
	return result["landing_cells"]


## Runs the exact settlement rules used by settle_cells without mutating this board.
func project_settlement(cells_to_drop: Array, values: Array = []) -> Dictionary:
	var projection = duplicate_state()
	var result: Dictionary = projection.settle_cells(cells_to_drop, values, 0)
	var first_wave_merge_count := 0
	for event in result.get("events", []):
		if event.get("type", "") == "merge_wave":
			first_wave_merge_count = event.get("steps", []).size()
			break
	result["has_first_wave_merge"] = first_wave_merge_count > 0
	result["first_wave_merge_count"] = first_wave_merge_count
	return result


## Resolves one turn from a rigid active-piece landing into cell gravity and
## deterministic 2048-style orthogonal pair merge waves.
func settle_cells(cells_to_drop: Array, values: Array, score_per_rank: int) -> Dictionary:
	var result := {
		"legal": false,
		"score": 0,
		"merged": false,
		"steps": [],
		"events": [],
		"landing_cells": [],
		"settled_cells": []
	}
	if cells_to_drop.is_empty() or not can_stage(cells_to_drop):
		return result

	var original_cells := []
	for row in cells:
		original_cells.append(row.duplicate())

	var landing := get_rigid_landing_cells(cells_to_drop)
	if landing.size() != cells_to_drop.size():
		cells = original_cells
		return result

	for index in landing.size():
		var value := 1 if index >= values.size() else int(values[index])
		set_value(landing[index], value)
	result["legal"] = true
	result["landing_cells"] = landing
	result["settled_cells"] = landing.duplicate()
	result["events"].append({"type": "rigid_landing", "from": cells_to_drop.duplicate(), "to": landing.duplicate()})

	var pass_index := 0
	var wave_index := 1
	var gravity_phase_index := 1
	var iteration_limit := width * height * 4
	while true:
		if pass_index > iteration_limit:
			push_error("BoardState settlement exceeded defensive iteration limit.")
			break
		var gravity := _gravity_pass()
		if gravity["moved"]:
			result["events"].append({
				"type": "gravity_step",
				"moves": gravity["moves"],
				"moved_cells": gravity["moved_cells"],
				"gravity_phase": gravity_phase_index,
				"gravity_phase_index": gravity_phase_index,
				"wave": wave_index,
				"wave_index": wave_index
			})
			gravity_phase_index += 1
		var merge := _merge_wave(wave_index)
		_accumulate_resolution(result, merge)
		if merge["merged"]:
			result["events"].append({
				"type": "merge_wave",
				"wave": wave_index,
				"wave_index": wave_index,
				"multiplier": wave_index,
				"score": merge["score"],
				"steps": merge["steps"]
			})
			wave_index += 1
		if not gravity["moved"] and not merge["merged"]:
			break
		pass_index += 1
	result["events"].append({"type": "stable"})
	return result


## Deterministic pressure relief: remove the lowest row containing any tile, then
## let every unsupported cell fall. Returns metadata for presentation/tests.
func clear_lowest_occupied_row() -> Dictionary:
	var cleared_row := -1
	var cleared_cells: Array[Vector2i] = []
	for y in range(height - 1, -1, -1):
		for x in width:
			if get_value(Vector2i(x, y)) > 0:
				cleared_row = y
				break
		if cleared_row >= 0:
			break
	if cleared_row < 0:
		return {"cleared": false, "row": -1, "cells": [], "moved_cells": []}
	for x in width:
		var position := Vector2i(x, cleared_row)
		if get_value(position) > 0:
			cleared_cells.append(position)
		set_value(position, 0)
	var gravity := _gravity_pass()
	return {
		"cleared": true,
		"row": cleared_row,
		"cells": cleared_cells,
		"moved_cells": gravity["moved_cells"]
	}


func _can_occupy_drop_offset(cells_to_drop: Array, y_offset: int) -> bool:
	var occupied := {}
	for cell in cells_to_drop:
		occupied[cell + Vector2i(0, y_offset)] = true
	for cell in cells_to_drop:
		var position: Vector2i = cell + Vector2i(0, y_offset)
		if position.x < 0 or position.x >= width or position.y >= height:
			return false
		if position.y >= 0 and get_value(position) != 0:
			return false
	return true


func _gravity_pass() -> Dictionary:
	var moved_cells: Array[Vector2i] = []
	var moves: Array[Dictionary] = []
	for x in width:
		var write_y := height - 1
		for y in range(height - 1, -1, -1):
			var value := get_value(Vector2i(x, y))
			if value <= 0:
				continue
			if y != write_y:
				set_value(Vector2i(x, y), 0)
				set_value(Vector2i(x, write_y), value)
				var from := Vector2i(x, y)
				var to := Vector2i(x, write_y)
				moved_cells.append(to)
				moves.append({
					"from": from,
					"to": to,
					"value": value,
					"distance": write_y - y
				})
			write_y -= 1
	return {
		"moved": not moved_cells.is_empty(),
		"moved_cells": moved_cells,
		"moves": moves
	}


func _merge_wave(wave_index: int) -> Dictionary:
	var result := {"score": 0, "merged": false, "steps": []}
	var pairs := _find_merge_pairs()
	if pairs.is_empty():
		return result
	var snapshot := []
	for row in cells:
		snapshot.append(row.duplicate())
	var writes: Array[Dictionary] = []
	for pair in pairs:
		var first: Vector2i = pair[0]
		var second: Vector2i = pair[1]
		var value: int = snapshot[first.y][first.x]
		var target := _merge_result_position(first, second)
		var source := second if target == first else first
		writes.append({"source": source, "target": target, "value": value})
	for pair in pairs:
		set_value(pair[0], 0)
		set_value(pair[1], 0)
	for write in writes:
		var to_value: int = int(write["value"]) + 1
		set_value(write["target"], to_value)
		var score_awarded := int(pow(2.0, to_value)) * wave_index
		result["score"] += score_awarded
		result["steps"].append(_merge_step(write["source"], write["target"], int(write["value"]), "merge_wave", wave_index - 1, wave_index, score_awarded))
	result["merged"] = true
	return result


## Pairing is component-first to avoid dictionary-order behavior: equal orthogonal
## regions are ordered bottom-up, center-out, then left-to-right; each cell then
## claims its highest-priority available equal neighbor.
func _find_merge_pairs() -> Array:
	var visited := {}
	var pairs := []
	for y in height:
		for x in width:
			var start := Vector2i(x, y)
			if visited.has(start) or get_value(start) <= 0:
				continue
			var component := _equal_component(start, visited)
			if component.size() < 2:
				continue
			component.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				return _cell_priority_less(a, b)
			)
			var used := {}
			for cell in component:
				if used.has(cell):
					continue
				for neighbor in _ordered_equal_neighbors(cell, used):
					used[cell] = true
					used[neighbor] = true
					pairs.append([cell, neighbor])
					break
	return pairs


func _equal_component(start: Vector2i, visited: Dictionary) -> Array[Vector2i]:
	var value := get_value(start)
	var component: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		component.append(cell)
		for direction in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var neighbor: Vector2i = cell + direction
			if not is_inside(neighbor) or visited.has(neighbor) or get_value(neighbor) != value:
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return component


func _cell_priority_less(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y > b.y
	var center_twice := width - 1
	var a_distance := absi(a.x * 2 - center_twice)
	var b_distance := absi(b.x * 2 - center_twice)
	if a_distance != b_distance:
		return a_distance < b_distance
	return a.x < b.x


func _ordered_equal_neighbors(cell: Vector2i, used: Dictionary) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var center_left := float(width - 1) / 2.0
	var toward := Vector2i.RIGHT if float(cell.x) < center_left else Vector2i.LEFT
	var away := -toward
	for direction in [Vector2i.DOWN, toward, away, Vector2i.UP]:
		var neighbor: Vector2i = cell + direction
		if is_inside(neighbor) and not used.has(neighbor) and get_value(neighbor) == get_value(cell):
			candidates.append(neighbor)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ap := _neighbor_priority(cell, a, toward)
		var bp := _neighbor_priority(cell, b, toward)
		if ap != bp:
			return ap < bp
		return a.x < b.x
	)
	return candidates


func _neighbor_priority(cell: Vector2i, neighbor: Vector2i, toward: Vector2i) -> int:
	var delta := neighbor - cell
	if delta == Vector2i.DOWN:
		return 0
	if delta == toward:
		return 1
	if delta == -toward:
		return 2
	if delta == Vector2i.UP:
		return 3
	return 4


func _merge_result_position(first: Vector2i, second: Vector2i) -> Vector2i:
	if first.y != second.y:
		return first if first.y > second.y else second
	var center_twice := width - 1
	var first_distance := absi(first.x * 2 - center_twice)
	var second_distance := absi(second.x * 2 - center_twice)
	if first_distance != second_distance:
		return first if first_distance < second_distance else second
	return first if first.x < second.x else second


func _merge_step(
	source: Vector2i,
	target: Vector2i,
	from_value: int,
	stage: String,
	pass_index: int,
	wave_index: int = 1,
	score_awarded: int = 0
) -> Dictionary:
	return {
		"source": source,
		"positions": [source, target],
		"anchor": target,
		"from_value": from_value,
		"to_value": from_value + 1,
		"direction": target - source,
		"stage": stage,
		"pass": pass_index,
		"wave": wave_index,
		"score": score_awarded
	}


func _accumulate_resolution(total: Dictionary, stage_result: Dictionary) -> void:
	total["score"] += int(stage_result["score"])
	total["merged"] = total["merged"] or bool(stage_result["merged"])
	total["steps"].append_array(stage_result["steps"])


func has_any_moves(piece_definitions: Array) -> bool:
	for piece in piece_definitions:
		if piece == null:
			continue
		var rotated = piece.get_rotated_cells(0)
		var values = piece.get_rotated_values(0)
		var bounds = _bounds(rotated)
		var stage_y: int = -bounds.position.y - bounds.size.y - 1
		var min_anchor_x: int = -bounds.position.x
		var max_anchor_x: int = width - bounds.position.x - bounds.size.x
		for x in range(min_anchor_x, max_anchor_x + 1):
			var anchor = Vector2i(x, stage_y)
			if can_settle(_translated(rotated, anchor), values):
				return true
	return false


func resolve_merges(_min_group_size: int, _score_per_rank: int) -> Dictionary:
	return _merge_wave(1)


func _translated(source: Array, anchor: Vector2i) -> Array:
	var translated: Array = []
	for cell in source:
		translated.append(cell + anchor)
	return translated


func _bounds(source: Array) -> Rect2i:
	var min_x: int = source[0].x
	var min_y: int = source[0].y
	var max_x: int = source[0].x
	var max_y: int = source[0].y
	for cell in source:
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
