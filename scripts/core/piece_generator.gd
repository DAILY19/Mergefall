class_name PieceGenerator
extends RefCounted

var rng := RandomNumberGenerator.new()
var recent_pieces: Array[Resource] = []


func _init() -> void:
	rng.randomize()


func next_piece(definitions: Array[Resource]):
	var candidates := definitions.filter(func(piece: Resource) -> bool:
		return piece != null and _has_valid_values(piece)
	)
	if candidates.is_empty():
		candidates = definitions.filter(func(piece: Resource) -> bool:
			return piece != null
		)
	if candidates.is_empty():
		return null
	var total_weight := 0
	for piece in candidates:
		if piece != null:
			var weight: int = maxi(piece.spawn_weight, 0)
			if recent_pieces.has(piece):
				weight = maxi(1, weight / 2)
			total_weight += weight
	if total_weight <= 0:
		return null
	var roll := rng.randi_range(1, total_weight)
	var running := 0
	for piece in candidates:
		if piece == null:
			continue
		var weight: int = maxi(piece.spawn_weight, 0)
		if recent_pieces.has(piece):
			weight = maxi(1, weight / 2)
		running += weight
		if roll <= running:
			_remember(piece)
			return piece
	_remember(candidates[0])
	return candidates[0]


func _remember(piece: Resource) -> void:
	recent_pieces.append(piece)
	while recent_pieces.size() > 2:
		recent_pieces.pop_front()


func _has_valid_values(piece: Resource) -> bool:
	var cells: Array = piece.get_rotated_cells(0)
	var values: Array = piece.get_rotated_values(0)
	for first_index in cells.size():
		for second_index in range(first_index + 1, cells.size()):
			if values[first_index] == values[second_index] and _is_orthogonal(cells[first_index], cells[second_index]):
				return false
	return true


func _is_orthogonal(first: Vector2i, second: Vector2i) -> bool:
	return absi(first.x - second.x) + absi(first.y - second.y) == 1
