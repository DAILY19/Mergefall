class_name PieceGenerator
extends RefCounted

const FAMILY_ORDER := ["I", "O", "T", "S", "Z", "J", "L"]
const DEFAULT_SEED := 0x4d4552474546414c
const ORTHOGONAL_DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var rng := RandomNumberGenerator.new()
var _catalog_source: Array[Resource] = []
var _catalog_cache: Dictionary = {}
var _available_families: Array[String] = []
var _settled_color_cache: Dictionary = {}


func _init() -> void:
	rng.seed = DEFAULT_SEED


func next_piece(definitions: Array[Resource], progression: Resource, completed_turns: int) -> PieceDefinition:
	var catalog: Dictionary = _build_catalog(definitions)
	if catalog.is_empty() or progression == null:
		return null
	if _available_families.is_empty():
		return null
	var family: String = _available_families[rng.randi_range(0, _available_families.size() - 1)]
	var orientations: Array[Resource] = catalog[family]
	var template: PieceDefinition = orientations[rng.randi_range(0, orientations.size() - 1)]
	var phase: Resource = progression.phase_for_completed_turn(completed_turns)
	if phase == null:
		return null
	var pair: Array[int] = _weighted_rank_pair(phase, progression)
	var values: Array[int] = _values_for_cells(template.cells, pair)
	var piece: PieceDefinition = template.duplicate_with_values(values)
	piece.generation_turn = completed_turns
	piece.selected_value_ranks = pair.duplicate()
	assert(_is_valid_piece_instance(piece, pair), "Generated malformed tetromino piece: %s" % piece.display_name)
	return piece


func get_catalog(definitions: Array[Resource]) -> Array[Resource]:
	var pieces: Array[Resource] = []
	var catalog: Dictionary = _build_catalog(definitions)
	for family in FAMILY_ORDER:
		for piece in catalog.get(family, []):
			pieces.append(piece)
	return pieces


func get_family_order() -> Array[String]:
	return FAMILY_ORDER.duplicate()


func _build_catalog(definitions: Array[Resource]) -> Dictionary:
	if definitions == _catalog_source:
		return _catalog_cache
	var catalog: Dictionary = {}
	for family in FAMILY_ORDER:
		catalog[family] = [] as Array[Resource]
	for piece in definitions:
		if piece == null:
			continue
		if not FAMILY_ORDER.has(piece.family):
			continue
		assert(_is_valid_catalog_piece(piece), "Malformed tetromino catalog entry: %s" % piece.display_name)
		catalog[piece.family].append(piece)
	for family in FAMILY_ORDER:
		if catalog[family].is_empty():
			catalog.erase(family)
	_catalog_source = definitions.duplicate()
	_catalog_cache = catalog
	_available_families.clear()
	for family in FAMILY_ORDER:
		if catalog.has(family):
			_available_families.append(family)
	return catalog


func _weighted_rank_pair(phase: Resource, progression: Resource) -> Array[int]:
	var first_index := _weighted_index(phase.weights)
	var second_index := _weighted_index(phase.weights, first_index)
	return [
		progression.display_value_to_rank(phase.displayed_values[first_index]),
		progression.display_value_to_rank(phase.displayed_values[second_index]),
	]


func _weighted_index(weights: Array[int], excluded_index: int = -1) -> int:
	var total := 0
	for index in weights.size():
		if index != excluded_index:
			total += weights[index]
	assert(total > 0, "Weighted selection requires at least one positive eligible weight.")
	var draw := rng.randi_range(1, total)
	var cumulative := 0
	for index in weights.size():
		if index == excluded_index:
			continue
		cumulative += weights[index]
		if draw <= cumulative:
			return index
	return weights.size() - 1


func _values_for_cells(cells: Array[Vector2i], pair: Array[int]) -> Array[int]:
	var flip_parity := rng.randi_range(0, 1) == 1
	var first_rank: int = pair[1] if flip_parity else pair[0]
	var second_rank: int = pair[0] if flip_parity else pair[1]
	var groups := _settled_color_groups(cells)
	var values: Array[int] = []
	for index in cells.size():
		values.append(first_rank if int(groups[index]) == 0 else second_rank)
	return values


func _settled_color_groups(cells: Array[Vector2i]) -> Array[int]:
	var cache_key := _shape_key(cells)
	if _settled_color_cache.has(cache_key):
		return _settled_color_cache[cache_key].duplicate()
	var settled := _flat_settled_cells(cells)
	var adjacency := {}
	for index in settled.size():
		adjacency[index] = []
	for first_index in settled.size():
		for second_index in range(first_index + 1, settled.size()):
			if _is_orthogonal(cells[first_index], cells[second_index]):
				adjacency[first_index].append(second_index)
				adjacency[second_index].append(first_index)
	var groups: Array[int] = []
	for _index in cells.size():
		groups.append(-1)
	var order := range(cells.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var first: Vector2i = settled[a]
		var second: Vector2i = settled[b]
		return first.y < second.y or (first.y == second.y and first.x < second.x)
	)
	for start_index in order:
		if groups[start_index] >= 0:
			continue
		groups[start_index] = 0
		var queue: Array[int] = [start_index]
		var queue_index := 0
		while queue_index < queue.size():
			var current: int = queue[queue_index]
			queue_index += 1
			var neighbors: Array = adjacency[current]
			neighbors.sort_custom(func(a: int, b: int) -> bool:
				var first: Vector2i = settled[a]
				var second: Vector2i = settled[b]
				return first.y < second.y or (first.y == second.y and first.x < second.x)
			)
			for neighbor in neighbors:
				if groups[neighbor] < 0:
					groups[neighbor] = 1 - groups[current]
					queue.append(neighbor)
	var typed: Array[int] = []
	for group in groups:
		typed.append(int(group))
	_settled_color_cache[cache_key] = typed.duplicate()
	return typed


func _flat_settled_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var columns := {}
	for index in cells.size():
		var cell := cells[index]
		if not columns.has(cell.x):
			columns[cell.x] = []
		columns[cell.x].append({"index": index, "cell": cell})
	var settled: Array[Vector2i] = []
	settled.resize(cells.size())
	for x in columns.keys():
		var column: Array = columns[x]
		column.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var first: Vector2i = a["cell"]
			var second: Vector2i = b["cell"]
			return first.y > second.y or (first.y == second.y and first.x < second.x)
		)
		for stack_index in column.size():
			settled[int(column[stack_index]["index"])] = Vector2i(int(x), -stack_index)
	var min_x := settled[0].x
	var min_y := settled[0].y
	for cell in settled:
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
	for index in settled.size():
		settled[index] -= Vector2i(min_x, min_y)
	return settled


func _shape_key(cells: Array[Vector2i]) -> String:
	var sorted := cells.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return str(sorted)


func _has_valid_values(piece: Resource) -> bool:
	var cells: Array[Vector2i] = piece.get_rotated_cells(0)
	var values: Array[int] = piece.get_rotated_values(0)
	for first_index in cells.size():
		for second_index in range(first_index + 1, cells.size()):
			if values[first_index] == values[second_index] and _is_orthogonal(cells[first_index], cells[second_index]):
				return false
	return true


func _is_orthogonal(first: Vector2i, second: Vector2i) -> bool:
	return absi(first.x - second.x) + absi(first.y - second.y) == 1


func _is_valid_catalog_piece(piece: Resource) -> bool:
	return (
		FAMILY_ORDER.has(piece.family)
		and piece.orientation != ""
		and _has_four_unique_normalized_cells(piece)
		and _is_connected(piece.cells)
	)


func _is_valid_piece_instance(piece: Resource, allowed_ranks: Array[int]) -> bool:
	if piece.cell_values.size() != piece.cells.size():
		return false
	for value in piece.cell_values:
		if not allowed_ranks.has(value):
			return false
	return allowed_ranks.size() == 2 and allowed_ranks[0] != allowed_ranks[1] and _has_valid_values(piece)


func _has_four_unique_normalized_cells(piece: Resource) -> bool:
	if piece.cells.size() != 4:
		return false
	var seen := {}
	var first_cell: Vector2i = piece.cells[0]
	var min_x: int = first_cell.x
	var min_y: int = first_cell.y
	for cell in piece.cells:
		if seen.has(cell):
			return false
		seen[cell] = true
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
	return min_x == 0 and min_y == 0


func _is_connected(cells: Array[Vector2i]) -> bool:
	var remaining := {}
	for cell in cells:
		remaining[cell] = true
	var frontier: Array[Vector2i] = [cells[0]]
	remaining.erase(cells[0])
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for neighbor in ORTHOGONAL_DIRECTIONS:
			var next: Vector2i = cell + neighbor
			if remaining.has(next):
				remaining.erase(next)
				frontier.append(next)
	return remaining.is_empty()
