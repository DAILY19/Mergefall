class_name PieceGenerator
extends RefCounted

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func next_piece(definitions: Array[Resource]):
	var total_weight := 0
	for piece in definitions:
		if piece != null:
			total_weight += maxi(piece.spawn_weight, 0)
	if total_weight <= 0:
		return null
	var roll := rng.randi_range(1, total_weight)
	var running := 0
	for piece in definitions:
		if piece == null:
			continue
		running += maxi(piece.spawn_weight, 0)
		if roll <= running:
			return piece
	return definitions[0]
