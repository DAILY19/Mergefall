class_name BoardState
extends RefCounted

var width := 0
var height := 0
var cells: Array[Array] = []
var cell_sources: Array[Array] = []
var cell_fatigues: Array[Array] = []
var overflow_cells := {}
var overflow_sources := {}
var overflow_fatigues := {}

const COMPONENT_DIRECTIONS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]


func setup(board_width: int, board_height: int) -> void:
	width = board_width
	height = board_height
	cells.clear()
	cell_sources.clear()
	cell_fatigues.clear()
	overflow_cells.clear()
	overflow_sources.clear()
	overflow_fatigues.clear()
	for y in height:
		var row: Array[int] = []
		var source_row: Array[int] = []
		var fatigue_row: Array[bool] = []
		for _x in width:
			row.append(0)
			source_row.append(0)
			fatigue_row.append(false)
		cells.append(row)
		cell_sources.append(source_row)
		cell_fatigues.append(fatigue_row)


func duplicate_state() -> BoardState:
	var clone := BoardState.new()
	clone.width = width
	clone.height = height
	for row in cells:
		clone.cells.append(row.duplicate())
	for source_row in cell_sources:
		clone.cell_sources.append(source_row.duplicate())
	for fatigue_row in cell_fatigues:
		clone.cell_fatigues.append(fatigue_row.duplicate())
	clone.overflow_cells = overflow_cells.duplicate()
	clone.overflow_sources = overflow_sources.duplicate()
	clone.overflow_fatigues = overflow_fatigues.duplicate()
	return clone


func is_inside(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < width and position.y >= 0 and position.y < height


func is_within_horizontal_bounds(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < width


func is_visible_board_cell(position: Vector2i) -> bool:
	return is_inside(position)


func is_valid_logical_cell(position: Vector2i) -> bool:
	return is_within_horizontal_bounds(position) and position.y < height


func has_stable_overflow() -> bool:
	return not overflow_cells.is_empty()


func get_overflow_positions() -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for position: Vector2i in overflow_cells.keys():
		positions.append(position)
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return positions


func get_value(position: Vector2i) -> int:
	if position.y < 0 and overflow_cells.has(position):
		return int(overflow_cells[position])
	if not is_inside(position):
		return -1
	return cells[position.y][position.x]


func set_value(position: Vector2i, value: int) -> void:
	if position.y < 0 and is_within_horizontal_bounds(position):
		if value > 0:
			overflow_cells[position] = value
		else:
			overflow_cells.erase(position)
			overflow_sources.erase(position)
			overflow_fatigues.erase(position)
	elif is_inside(position):
		cells[position.y][position.x] = value
		if cell_sources.size() == height:
			cell_sources[position.y][position.x] = 0
		if cell_fatigues.size() == height:
			cell_fatigues[position.y][position.x] = false


func get_source(position: Vector2i) -> int:
	if position.y < 0:
		return int(overflow_sources.get(position, 0))
	if not is_inside(position) or cell_sources.size() != height:
		return 0
	return cell_sources[position.y][position.x]


func set_source(position: Vector2i, source: int) -> void:
	if position.y < 0 and overflow_cells.has(position):
		if source > 0:
			overflow_sources[position] = source
		else:
			overflow_sources.erase(position)
	elif is_inside(position) and cell_sources.size() == height:
		cell_sources[position.y][position.x] = source


func is_fatigued(position: Vector2i) -> bool:
	if position.y < 0:
		return bool(overflow_fatigues.get(position, false))
	if not is_inside(position) or cell_fatigues.size() != height:
		return false
	return bool(cell_fatigues[position.y][position.x])


func set_fatigued(position: Vector2i, fatigued: bool) -> void:
	if position.y < 0 and overflow_cells.has(position):
		if fatigued:
			overflow_fatigues[position] = true
		else:
			overflow_fatigues.erase(position)
	elif is_inside(position) and cell_fatigues.size() == height:
		cell_fatigues[position.y][position.x] = fatigued


func can_place(cells_to_place: Array) -> bool:
	for cell: Vector2i in cells_to_place:
		if not is_inside(cell):
			return false
		if get_value(cell) != 0:
			return false
	return true


## Staging permits cells above the visible board. Horizontal overflow, cells below
## the floor, and overlap with visible settled cells are still illegal.
func can_stage(cells_to_stage: Array) -> bool:
	var seen := {}
	for cell: Vector2i in cells_to_stage:
		if not is_valid_logical_cell(cell):
			return false
		if seen.has(cell):
			return false
		seen[cell] = true
		if get_value(cell) > 0:
			return false
	return true


func can_settle(cells_to_drop: Array, values: Array = [], merge_fatigue_enabled: bool = false) -> bool:
	if not can_stage(cells_to_drop):
		return false
	return bool(project_settlement(cells_to_drop, values, merge_fatigue_enabled).get("legal", false))


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
		if not is_valid_logical_cell(landed):
			return []
		landing.append(landed)
	return landing


## Returns one landing position for every source cell, even if that tile is later
## consumed by horizontal resolution. This keeps the drop preview whole.
func get_landing_cells(cells_to_drop: Array, values: Array = []) -> Array[Vector2i]:
	var result := project_settlement(cells_to_drop, values)
	return result["landing_cells"]


## Runs the exact settlement rules used by settle_cells without mutating this board.
func project_settlement(cells_to_drop: Array, values: Array = [], merge_fatigue_enabled: bool = false) -> Dictionary:
	var projection := duplicate_state()
	var result: Dictionary = projection.settle_cells(cells_to_drop, values, 0, merge_fatigue_enabled)
	var first_wave_merge_count := 0
	for event in result.get("events", []):
		if event.get("type", "") == "merge_wave":
			first_wave_merge_count = event.get("steps", []).size()
			break
	result["has_first_wave_merge"] = first_wave_merge_count > 0
	result["first_wave_merge_count"] = first_wave_merge_count
	return result


## Resolves one turn from a rigid active-piece landing into a deterministic
## stability pipeline: complete gravity pass, then one merge wave, repeated until
## no tile moved and no eligible pair merged. Merges never run mid-gravity.
func settle_cells(cells_to_drop: Array, values: Array, score_per_rank: int, merge_fatigue_enabled: bool = false) -> Dictionary:
	var result := {
		"legal": false,
		"score": 0,
		"merged": false,
		"steps": [],
		"events": [],
		"landing_cells": [],
		"settled_cells": [],
		"has_stable_overflow": false
	}
	if cells_to_drop.is_empty() or not can_stage(cells_to_drop):
		return result

	var original_cells: Array[Array] = []
	for row in cells:
		original_cells.append(row.duplicate())
	var original_sources: Array[Array] = []
	for source_row in cell_sources:
		original_sources.append(source_row.duplicate())
	var original_fatigues: Array[Array] = []
	for fatigue_row in cell_fatigues:
		original_fatigues.append(fatigue_row.duplicate())
	var original_overflow_cells := overflow_cells.duplicate()
	var original_overflow_sources := overflow_sources.duplicate()
	var original_overflow_fatigues := overflow_fatigues.duplicate()
	_clear_fatigues()

	var landing := get_rigid_landing_cells(cells_to_drop)
	if landing.size() != cells_to_drop.size():
		cells = original_cells
		cell_sources = original_sources
		cell_fatigues = original_fatigues
		overflow_cells = original_overflow_cells
		overflow_sources = original_overflow_sources
		overflow_fatigues = original_overflow_fatigues
		return result

	for index in landing.size():
		var value := 1 if index >= values.size() else int(values[index])
		set_value(landing[index], value)
		set_source(landing[index], 1)
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
		var merge := _merge_wave(wave_index, merge_fatigue_enabled)
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
	_clear_sources()
	_clear_fatigues()
	result["events"].append({"type": "stable"})
	result["has_stable_overflow"] = has_stable_overflow()
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
	for cell: Vector2i in cells_to_drop:
		var position: Vector2i = cell + Vector2i(0, y_offset)
		if not is_valid_logical_cell(position):
			return false
		if get_value(position) > 0:
			return false
	return true


func _gravity_pass() -> Dictionary:
	var moved_cells: Array[Vector2i] = []
	var moves: Array[Dictionary] = []
	for x in width:
		var write_y := height - 1
		for y in range(height - 1, _min_occupied_y_for_column(x) - 1, -1):
			var value := get_value(Vector2i(x, y))
			if value <= 0:
				continue
			if y != write_y:
				var source := get_source(Vector2i(x, y))
				var fatigued := is_fatigued(Vector2i(x, y))
				set_value(Vector2i(x, y), 0)
				set_value(Vector2i(x, write_y), value)
				set_source(Vector2i(x, write_y), source)
				set_fatigued(Vector2i(x, write_y), fatigued)
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


func _merge_wave(wave_index: int, merge_fatigue_enabled: bool = false) -> Dictionary:
	var result := {"score": 0, "merged": false, "steps": []}
	var pairs: Array[Array] = _find_merge_pairs()
	if pairs.is_empty():
		return result
	var writes: Array[Dictionary] = []
	for pair in pairs:
		var first: Vector2i = pair[0]
		var second: Vector2i = pair[1]
		var value: int = get_value(first)
		var target := _merge_result_position(first, second)
		var source := second if target == first else first
		writes.append({"source": source, "target": target, "value": value})
	for pair in pairs:
		set_value(pair[0], 0)
		set_value(pair[1], 0)
	for write in writes:
		var to_value: int = int(write["value"]) + 1
		set_value(write["target"], to_value)
		set_source(write["target"], 0)
		set_fatigued(write["target"], merge_fatigue_enabled)
		var score_awarded := int(pow(2.0, to_value)) * wave_index
		result["score"] += score_awarded
		result["steps"].append(_merge_step(write["source"], write["target"], int(write["value"]), "merge_wave", wave_index - 1, wave_index, score_awarded))
	result["merged"] = true
	return result


## Pairing is component-first to avoid dictionary-order behavior: equal orthogonal
## regions are ordered bottom-up, center-out, then left-to-right; each cell then
## claims its highest-priority available equal neighbor.
func _find_merge_pairs() -> Array[Array]:
	var visited := {}
	var pairs: Array[Array] = []
	for start: Vector2i in _occupied_positions_top_down():
		if visited.has(start) or get_value(start) <= 0:
			continue
		var component := _equal_component(start, visited)
		if component.size() < 2:
			continue
		component.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _cell_priority_less(a, b)
		)
		var used := {}
		for cell: Vector2i in component:
			if used.has(cell):
				continue
			for neighbor: Vector2i in _ordered_equal_neighbors(cell, used):
				if not _can_merge_pair(cell, neighbor):
					continue
				used[cell] = true
				used[neighbor] = true
				pairs.append([cell, neighbor])
				break
	return pairs


func _can_merge_pair(first: Vector2i, second: Vector2i) -> bool:
	if _is_protected_same_spawn_pair(first, second):
		return false
	if is_fatigued(first) or is_fatigued(second):
		return false
	return true


func _is_protected_same_spawn_pair(first: Vector2i, second: Vector2i) -> bool:
	var first_source := get_source(first)
	return first_source > 0 and first_source == get_source(second)


func _clear_sources() -> void:
	for y in cell_sources.size():
		for x in cell_sources[y].size():
			cell_sources[y][x] = 0
	overflow_sources.clear()


func _clear_fatigues() -> void:
	for y in cell_fatigues.size():
		for x in cell_fatigues[y].size():
			cell_fatigues[y][x] = false
	overflow_fatigues.clear()


func _equal_component(start: Vector2i, visited: Dictionary) -> Array[Vector2i]:
	var value := get_value(start)
	var component: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]
	var queue_index := 0
	visited[start] = true
	while queue_index < queue.size():
		var cell: Vector2i = queue[queue_index]
		queue_index += 1
		component.append(cell)
		for direction in COMPONENT_DIRECTIONS:
			var neighbor: Vector2i = cell + direction
			if not is_valid_logical_cell(neighbor) or visited.has(neighbor) or get_value(neighbor) != value:
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
		if is_valid_logical_cell(neighbor) and not used.has(neighbor) and get_value(neighbor) == get_value(cell):
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
		var rotated: Array[Vector2i] = piece.get_rotated_cells(0)
		var values: Array[int] = piece.get_rotated_values(0)
		var bounds: Rect2i = _bounds(rotated)
		var stage_y: int = -bounds.position.y - bounds.size.y - 1
		var min_anchor_x: int = -bounds.position.x
		var max_anchor_x: int = width - bounds.position.x - bounds.size.x
		for x in range(min_anchor_x, max_anchor_x + 1):
			var anchor := Vector2i(x, stage_y)
			var projection := project_settlement(_translated(rotated, anchor), values)
			if projection.get("legal", false) and not projection.get("has_stable_overflow", false):
				return true
	return false


func resolve_merges(_min_group_size: int, _score_per_rank: int) -> Dictionary:
	return _merge_wave(1)


func _min_occupied_y_for_column(x: int) -> int:
	var min_y := 0
	for position: Vector2i in overflow_cells.keys():
		if position.x == x:
			min_y = mini(min_y, position.y)
	return min_y


func _occupied_positions_top_down() -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for position: Vector2i in overflow_cells.keys():
		if get_value(position) > 0:
			positions.append(position)
	for y in height:
		for x in width:
			var position := Vector2i(x, y)
			if get_value(position) > 0:
				positions.append(position)
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return positions


func _translated(source: Array[Vector2i], anchor: Vector2i) -> Array[Vector2i]:
	var translated: Array[Vector2i] = []
	for cell in source:
		translated.append(cell + anchor)
	return translated


func _bounds(source: Array[Vector2i]) -> Rect2i:
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
