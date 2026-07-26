extends RefCounted

const BoardStateScript = preload("res://scripts/core/board_state.gd")
const PieceGeneratorScript = preload("res://scripts/core/piece_generator.gd")
const SingleCrumbPiece = preload("res://resources/pieces/single_crumb.tres")
const DominoPiece = preload("res://resources/pieces/domino_bites.tres")
const CornerPiece = preload("res://resources/pieces/l_snack.tres")


static func run() -> PackedStringArray:
	var failures := PackedStringArray()
	_test_config_dimensions(failures)
	_test_basic_staging_and_rigid_landing(failures)
	_test_independent_gravity_and_split(failures)
	_test_gravity_event_payload(failures)
	_test_gravity_distances_and_sequence(failures)
	_test_orthogonal_merges_only(failures)
	_test_pairwise_component_merges(failures)
	_test_new_results_wait_until_later_wave(failures)
	_test_determinism(failures)
	_test_scoring_waves(failures)
	_test_same_piece_merges_are_allowed(failures)
	_test_piece_generation_values(failures)
	_test_game_over_uses_settlement(failures)
	_test_first_wave_projection(failures)
	_test_multiplier_bar_is_not_a_board_rule(failures)
	return failures


static func _test_config_dimensions(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	_expect(board.width == 6, "Prototype board width should be 6.", failures)
	_expect(board.height == 7, "Prototype board height should be 7.", failures)
	_expect(board.is_inside(Vector2i(5, 6)), "Row 6 should be playable.", failures)
	_expect(not board.is_inside(Vector2i(0, 7)), "Row 7 should be outside the board.", failures)


static func _test_basic_staging_and_rigid_landing(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	var staged: Array[Vector2i] = [Vector2i(2, -1), Vector2i(2, 0)]
	_expect(board.can_stage(staged), "Cells may stage partially above the board.", failures)
	var landing := board.get_rigid_landing_cells(staged)
	_expect(landing == [Vector2i(2, 5), Vector2i(2, 6)], "Rigid landing should preserve the fixed vertical shape.", failures)
	var projection := board.project_settlement(staged, [1, 2])
	_expect(projection["landing_cells"] == landing, "Projection should report the same rigid landing used by Drop.", failures)
	var committed := board.settle_cells(staged, [1, 2], 10)
	_expect(committed["legal"], "Partially above-board staging should settle when a path exists.", failures)
	_expect(committed["landing_cells"] == projection["landing_cells"], "Committed landing should match ghost projection.", failures)


static func _test_independent_gravity_and_split(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	board.set_value(Vector2i(0, 6), 4)
	var result := board.settle_cells([Vector2i(0, 0), Vector2i(1, 0)], [1, 2], 10)
	_expect(result["landing_cells"] == [Vector2i(0, 5), Vector2i(1, 5)], "Initial drop should land as a rigid shape.", failures)
	_expect(board.get_value(Vector2i(0, 5)) == 1, "Supported branch should remain above its blocker.", failures)
	_expect(board.get_value(Vector2i(1, 6)) == 2, "Unsupported branch should fall independently after landing.", failures)


static func _test_gravity_event_payload(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	board.set_value(Vector2i(0, 6), 4)
	var result := board.settle_cells([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], [1, 2, 3], 10)
	var gravity_events: Array = result.get("events", []).filter(func(event: Dictionary) -> bool:
		return event.get("type", "") == "gravity_step"
	)
	_expect(gravity_events.size() == 1, "Breakaway should produce one gravity event.", failures)
	if gravity_events.is_empty():
		return
	var moves: Array = gravity_events[0].get("moves", [])
	_expect(moves.size() == 2, "Multiple unsupported cells should share one gravity phase.", failures)
	_expect(gravity_events[0].get("gravity_phase_index", 0) == 1, "Gravity events should identify their authoritative phase.", failures)
	_expect(moves.has({"from": Vector2i(1, 5), "to": Vector2i(1, 6), "value": 2, "distance": 1}), "Gravity event should include exact one-row fall data.", failures)
	_expect(moves.has({"from": Vector2i(2, 5), "to": Vector2i(2, 6), "value": 3, "distance": 1}), "Gravity event should include exact simultaneous fall data.", failures)


static func _test_gravity_distances_and_sequence(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	board.place_cells([Vector2i(1, 2), Vector2i(2, 4)], [4, 5])
	var result := board.settle_cells([Vector2i(0, -1)], [9], 10)
	var gravity_events: Array = result.get("events", []).filter(func(event: Dictionary) -> bool:
		return event.get("type", "") == "gravity_step"
	)
	_expect(not gravity_events.is_empty(), "Unsupported cells should create a gravity event.", failures)
	if not gravity_events.is_empty():
		var moves: Array = gravity_events[0].get("moves", [])
		_expect(moves.has({"from": Vector2i(1, 2), "to": Vector2i(1, 6), "value": 4, "distance": 4}), "A long fall should retain its authoritative distance.", failures)
		_expect(moves.has({"from": Vector2i(2, 4), "to": Vector2i(2, 6), "value": 5, "distance": 2}), "Different fall distances should share one gravity event.", failures)


static func _test_orthogonal_merges_only(failures: PackedStringArray) -> void:
	var diagonal = BoardStateScript.new()
	diagonal.setup(6, 7)
	diagonal.place_cells([Vector2i(0, 5), Vector2i(1, 6)], [1, 1])
	var diagonal_result := diagonal.resolve_merges(2, 10)
	_expect(not diagonal_result["merged"], "Diagonal equality must not merge.", failures)
	var horizontal = BoardStateScript.new()
	horizontal.setup(6, 7)
	horizontal.place_cells([Vector2i(2, 6), Vector2i(3, 6)], [1, 1])
	var horizontal_result := horizontal.resolve_merges(2, 10)
	_expect(horizontal_result["merged"], "Horizontal equal neighbors should merge.", failures)
	_expect(horizontal.get_value(Vector2i(2, 6)) == 2, "Even-center horizontal pair should use the lower column tie-breaker.", failures)
	var vertical = BoardStateScript.new()
	vertical.setup(6, 7)
	vertical.place_cells([Vector2i(4, 5), Vector2i(4, 6)], [2, 2])
	var vertical_result := vertical.resolve_merges(2, 10)
	_expect(vertical_result["merged"], "Vertical equal neighbors should merge.", failures)
	_expect(vertical.get_value(Vector2i(4, 6)) == 3, "Vertical merge result should use the lower cell.", failures)
	var unequal = BoardStateScript.new()
	unequal.setup(6, 7)
	unequal.place_cells([Vector2i(0, 6), Vector2i(1, 6)], [1, 2])
	_expect(not unequal.resolve_merges(2, 10)["merged"], "Unequal adjacent cells must not merge.", failures)


static func _test_pairwise_component_merges(failures: PackedStringArray) -> void:
	var three = BoardStateScript.new()
	three.setup(6, 7)
	three.place_cells([Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6)], [1, 1, 1])
	var three_result := three.resolve_merges(2, 10)
	_expect(three_result["steps"].size() == 1, "Three equal cells should form one pair and leave one cell.", failures)
	_expect(_count_value(three, 1) == 1 and _count_value(three, 2) == 1, "Three-cell component should leave one original and one doubled tile.", failures)
	var four = BoardStateScript.new()
	four.setup(6, 7)
	four.place_cells([Vector2i(1, 5), Vector2i(2, 5), Vector2i(1, 6), Vector2i(2, 6)], [1, 1, 1, 1])
	var four_result := four.resolve_merges(2, 10)
	_expect(four_result["steps"].size() == 2, "Four equal connected cells should create two simultaneous pairs.", failures)
	_expect(_count_value(four, 2) == 2, "Four-cell component should produce two doubled cells.", failures)


static func _test_new_results_wait_until_later_wave(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	board.place_cells([Vector2i(2, 5), Vector2i(3, 5), Vector2i(2, 6), Vector2i(3, 6)], [1, 1, 1, 1])
	board.set_value(Vector2i(2, 4), 8)
	var result := board.settle_cells([Vector2i(5, -1)], [9], 10)
	var wave_count := _merge_wave_count(result)
	_expect(wave_count == 2, "Newly created results should merge only in a later wave when gravity makes them adjacent.", failures)
	_expect(board.get_value(Vector2i(2, 6)) == 3, "Later wave should be allowed to merge first-wave results.", failures)
	var event_types: Array = result.get("events", []).map(func(event: Dictionary) -> String:
		return event.get("type", "")
	)
	_expect(event_types.find("gravity_step", event_types.find("merge_wave") + 1) >= 0, "A merge that removes support should be followed by a later gravity event.", failures)


static func _test_determinism(failures: PackedStringArray) -> void:
	var seed = BoardStateScript.new()
	seed.setup(6, 7)
	seed.place_cells([Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(2, 5)], [1, 1, 1, 1])
	var first = seed.duplicate_state()
	var second = seed.duplicate_state()
	var first_result: Dictionary = first.settle_cells([Vector2i(5, -1)], [2], 10)
	var second_result: Dictionary = second.settle_cells([Vector2i(5, -1)], [2], 10)
	_expect(first_result == second_result, "Identical states should resolve to identical metadata.", failures)
	_expect(first.cells == second.cells, "Identical states should resolve to identical boards.", failures)
	var reordered = BoardStateScript.new()
	reordered.setup(6, 7)
	reordered.place_cells([Vector2i(2, 5), Vector2i(2, 6), Vector2i(1, 6), Vector2i(0, 6)], [1, 1, 1, 1])
	reordered.settle_cells([Vector2i(5, -1)], [2], 10)
	_expect(first.cells == reordered.cells, "Insertion order should not affect deterministic pairing.", failures)


static func _test_scoring_waves(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	board.place_cells([Vector2i(2, 5), Vector2i(3, 5), Vector2i(2, 6), Vector2i(3, 6)], [1, 1, 1, 1])
	var result := board.settle_cells([Vector2i(5, -1)], [9], 10)
	_expect(result["score"] == 24, "Score should use produced displayed values with increasing wave multipliers.", failures)
	_expect(result["steps"][0]["score"] == 4, "A 2+2->4 merge should award 4 in wave one.", failures)
	_expect(result["steps"][2]["score"] == 16, "A 4+4->8 merge should award 16 in wave two.", failures)
	var merge_events: Array = result.get("events", []).filter(func(event: Dictionary) -> bool:
		return event.get("type", "") == "merge_wave"
	)
	_expect(merge_events[0].get("multiplier", 0) == 1 and merge_events[1].get("multiplier", 0) == 2, "Merge events should carry authoritative wave multipliers.", failures)


static func _test_same_piece_merges_are_allowed(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	var result := board.settle_cells([Vector2i(2, -1), Vector2i(3, -1)], [1, 1], 10)
	_expect(result["merged"], "Same-piece cells should follow normal adjacency merge rules.", failures)
	_expect(_count_value(board, 2) == 1, "Same-piece pair should produce one doubled tile.", failures)


static func _test_piece_generation_values(failures: PackedStringArray) -> void:
	var generator = PieceGeneratorScript.new()
	var piece = generator.next_piece([DominoPiece, CornerPiece, SingleCrumbPiece])
	_expect(piece != null, "Generator should return a piece from valid definitions.", failures)
	for candidate in [DominoPiece, CornerPiece]:
		var cells: Array = candidate.get_rotated_cells(0)
		var values: Array = candidate.get_rotated_values(0)
		for first_index in cells.size():
			for second_index in range(first_index + 1, cells.size()):
				var adjacent: bool = (cells[first_index] - cells[second_index]).length_squared() == 1
				_expect(not adjacent or values[first_index] != values[second_index], "Prototype pieces should avoid adjacent equal internal values.", failures)


static func _test_game_over_uses_settlement(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(1, 2)
	_expect(board.has_any_moves([SingleCrumbPiece]), "An empty lane should have a legal settlement.", failures)
	board.set_value(Vector2i(0, 0), 1)
	board.set_value(Vector2i(0, 1), 2)
	_expect(not board.has_any_moves([SingleCrumbPiece]), "Game over should occur when no legal settlement path exists.", failures)


static func _test_first_wave_projection(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	board.set_value(Vector2i(2, 6), 1)
	var before: Array = board.cells.duplicate(true)
	var projection := board.project_settlement([Vector2i(2, -1)], [1])
	_expect(projection.get("legal", false), "First-wave projection should report legal settlement.", failures)
	_expect(projection.get("has_first_wave_merge", false), "Projection should detect a valid first merge wave.", failures)
	_expect(projection.get("first_wave_merge_count", 0) == 1, "Projection should report the first-wave pair count.", failures)
	_expect(board.cells == before, "Projection must not mutate the authoritative board.", failures)
	var actual := board.settle_cells([Vector2i(2, -1)], [1], 10)
	_expect(_merge_wave_count(actual) > 0, "Projected first-wave merge presence should agree with committed settlement.", failures)


static func _test_multiplier_bar_is_not_a_board_rule(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	board.place_cells([Vector2i(0, 6), Vector2i(1, 6)], [1, 1])
	var before = board.duplicate_state()
	var result := board.resolve_merges(2, 10)
	_expect(result["merged"], "Direct merge API should still mutate only through merge rules.", failures)
	_expect(before.get_value(Vector2i(0, 6)) == 1 and before.get_value(Vector2i(1, 6)) == 1, "Score feedback concepts should not mutate copied board state.", failures)


static func _count_value(board, value: int) -> int:
	var count := 0
	for y in board.height:
		for x in board.width:
			if board.get_value(Vector2i(x, y)) == value:
				count += 1
	return count


static func _merge_wave_count(result: Dictionary) -> int:
	var count := 0
	for event in result.get("events", []):
		if event.get("type", "") == "merge_wave":
			count += 1
	return count


static func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
