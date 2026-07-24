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


func place_cells(cells_to_place: Array, values: Array) -> void:
	for index in cells_to_place.size():
		set_value(cells_to_place[index], values[index])


func has_any_moves(piece_definitions: Array) -> bool:
	for piece in piece_definitions:
		if piece == null:
			continue
		for rotation in range(4 if piece.allow_rotation else 1):
			var rotated = piece.get_rotated_cells(rotation)
			var bounds = _bounds(rotated)
			for y in height:
				for x in width:
					var anchor = Vector2i(x, y) - bounds.position
					if can_place(_translated(rotated, anchor)):
						return true
	return false


func resolve_merges(min_group_size: int, score_per_rank: int) -> Dictionary:
	var total_score := 0
	var merged_any := false
	while true:
		var groups := _find_merge_groups(min_group_size)
		if groups.is_empty():
			break
		merged_any = true
		for group in groups:
			var positions = group["positions"]
			var value = group["value"]
			positions.sort_custom(func(a, b) -> bool:
				return a.y < b.y or (a.y == b.y and a.x < b.x)
			)
			var anchor = positions[0]
			for pos in positions:
				set_value(pos, 0)
			var upgraded: int = value + 1
			set_value(anchor, upgraded)
			total_score += upgraded * score_per_rank * positions.size()
	return {
		"score": total_score,
		"merged": merged_any
	}


func _find_merge_groups(min_group_size: int) -> Array:
	var groups: Array = []
	var visited := {}
	for y in height:
		for x in width:
			var start := Vector2i(x, y)
			if visited.has(start):
				continue
			var value := get_value(start)
			if value <= 0:
				continue
			var group = _flood_fill(start, value, visited)
			if group.size() >= min_group_size:
				groups.append({"value": value, "positions": group})
	return groups


func _flood_fill(start: Vector2i, target_value: int, visited: Dictionary) -> Array:
	var found: Array = []
	var stack: Array = [start]
	visited[start] = true
	while not stack.is_empty():
		var current: Vector2i = stack.pop_back()
		found.append(current)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next = current + offset
			if not is_inside(next):
				continue
			if visited.has(next):
				continue
			if get_value(next) != target_value:
				continue
			visited[next] = true
			stack.append(next)
	return found


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
