extends RefCounted

const PieceGeneratorScript = preload("res://scripts/core/piece_generator.gd")
const Config = preload("res://resources/config/default_game_config.tres")

const BOUNDARIES := [
	[0, 0],
	[30, 0],
	[31, 1],
	[70, 1],
	[71, 2],
	[120, 2],
	[121, 3],
	[180, 3],
	[181, 4],
	[500, 4],
]
const EXPECTED_VALUES := [
	[2, 4],
	[2, 4, 8],
	[2, 4, 8],
	[4, 8, 16],
	[4, 8, 16],
]
const EXPECTED_WEIGHTS := [
	[70, 30],
	[55, 40, 5],
	[35, 50, 15],
	[55, 35, 10],
	[30, 50, 20],
]


static func run() -> PackedStringArray:
	var failures := PackedStringArray()
	_test_phase_boundaries(failures)
	_test_rank_mapping(failures)
	_test_generation_by_phase(failures)
	_test_seeded_determinism(failures)
	_test_weighted_first_draw(failures)
	return failures


static func _test_phase_boundaries(failures: PackedStringArray) -> void:
	_expect(Config.spawn_progression.validate().is_empty(), "Default spawn progression should validate.", failures)
	_expect(Config.spawn_progression.phases.size() == 5, "Default progression should contain five phases.", failures)
	for boundary in BOUNDARIES:
		var turn: int = boundary[0]
		var expected_index: int = boundary[1]
		var phase: Resource = Config.spawn_progression.phase_for_completed_turn(turn)
		_expect(phase == Config.spawn_progression.phases[expected_index], "Turn %d should use progression phase %d." % [turn, expected_index], failures)
	for index in Config.spawn_progression.phases.size():
		var phase: Resource = Config.spawn_progression.phases[index]
		_expect(phase.displayed_values == EXPECTED_VALUES[index], "Phase %d should expose the requested display values." % index, failures)
		_expect(phase.weights == EXPECTED_WEIGHTS[index], "Phase %d should expose the requested weights." % index, failures)


static func _test_rank_mapping(failures: PackedStringArray) -> void:
	for mapping in [[2, 1], [4, 2], [8, 3], [16, 4]]:
		var displayed_value: int = mapping[0]
		var rank: int = mapping[1]
		_expect(Config.spawn_progression.display_value_to_rank(displayed_value) == rank, "Display value %d should map to rank %d." % [displayed_value, rank], failures)
		_expect(Config.spawn_progression.rank_to_display_value(rank) == displayed_value, "Rank %d should map to display value %d." % [rank, displayed_value], failures)


static func _test_generation_by_phase(failures: PackedStringArray) -> void:
	for boundary in BOUNDARIES:
		var turn: int = boundary[0]
		var phase: Resource = Config.spawn_progression.phase_for_completed_turn(turn)
		var allowed_ranks: Array[int] = []
		for displayed_value in phase.displayed_values:
			allowed_ranks.append(Config.spawn_progression.display_value_to_rank(displayed_value))
		var generator = PieceGeneratorScript.new()
		generator.rng.seed = 8100 + turn
		for _sample in 128:
			var piece = generator.next_piece(Config.piece_definitions, Config.spawn_progression, turn)
			_expect(piece != null and piece.cells.size() == 4, "Turn %d generation should return a four-cell tetromino." % turn, failures)
			if piece == null:
				continue
			_expect(piece.generation_turn == turn, "Generated pieces should retain their effective activation turn.", failures)
			_expect(piece.selected_value_ranks.size() == 2 and piece.selected_value_ranks[0] != piece.selected_value_ranks[1], "Parity partitions must use two different ranks.", failures)
			for rank in piece.cell_values:
				_expect(allowed_ranks.has(rank), "Turn %d generated rank %d outside its active phase." % [turn, rank], failures)
			_expect(_has_no_adjacent_equal_values(piece), "Generated tetrominoes must not contain adjacent equal values.", failures)


static func _test_seeded_determinism(failures: PackedStringArray) -> void:
	var first = PieceGeneratorScript.new()
	var second = PieceGeneratorScript.new()
	first.rng.seed = 424242
	second.rng.seed = 424242
	var turns := [0, 1, 30, 31, 32, 70, 71, 120, 121, 180, 181, 250]
	var first_sequence := []
	var second_sequence := []
	for turn in turns:
		var first_piece = first.next_piece(Config.piece_definitions, Config.spawn_progression, turn)
		var second_piece = second.next_piece(Config.piece_definitions, Config.spawn_progression, turn)
		first_sequence.append(_signature(first_piece))
		second_sequence.append(_signature(second_piece))
	_expect(first_sequence == second_sequence, "Identical seeds and turn states should reproduce the full piece sequence.", failures)
	var different = PieceGeneratorScript.new()
	different.rng.seed = 424243
	var different_sequence := []
	for turn in turns:
		different_sequence.append(_signature(different.next_piece(Config.piece_definitions, Config.spawn_progression, turn)))
	_expect(first_sequence != different_sequence, "Different valid seeds should be able to produce different sequences.", failures)


static func _test_weighted_first_draw(failures: PackedStringArray) -> void:
	var generator = PieceGeneratorScript.new()
	generator.rng.seed = 998877
	var counts := {1: 0, 2: 0, 3: 0}
	var sample_count := 20000
	for _index in sample_count:
		var piece = generator.next_piece(Config.piece_definitions, Config.spawn_progression, 71)
		var first_rank: int = piece.selected_value_ranks[0]
		counts[first_rank] = int(counts.get(first_rank, 0)) + 1
	var expected := {1: 0.35, 2: 0.50, 3: 0.15}
	for rank in [1, 2, 3]:
		var observed := float(counts[rank]) / sample_count
		_expect(absf(observed - expected[rank]) < 0.025, "Turn 71 first weighted draw for rank %d should stay within tolerance (observed %.3f)." % [rank, observed], failures)


static func _has_no_adjacent_equal_values(piece: Resource) -> bool:
	for first_index in piece.cells.size():
		for second_index in range(first_index + 1, piece.cells.size()):
			var adjacent: bool = (piece.cells[first_index] - piece.cells[second_index]).length_squared() == 1
			if adjacent and piece.cell_values[first_index] == piece.cell_values[second_index]:
				return false
	return true


static func _signature(piece: Resource) -> String:
	return "%d:%s:%s:%s:%s" % [
		piece.generation_turn,
		piece.family,
		piece.orientation,
		piece.selected_value_ranks,
		piece.cell_values,
	]


static func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
