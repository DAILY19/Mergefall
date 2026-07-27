extends RefCounted

const BoardStateScript = preload("res://scripts/core/board_state.gd")
const PieceGeneratorScript = preload("res://scripts/core/piece_generator.gd")
const Config = preload("res://resources/config/default_game_config.tres")
const IHorizontalPiece = preload("res://resources/pieces/i_horizontal.tres")
const IVerticalPiece = preload("res://resources/pieces/i_vertical.tres")
const OPiece = preload("res://resources/pieces/o.tres")


static func run() -> PackedStringArray:
	var failures := PackedStringArray()
	_test_config_dimensions(failures)
	_test_default_config_disables_merge_fatigue(failures)
	_test_basic_staging_and_rigid_landing(failures)
	_test_above_board_lock_validation(failures)
	_test_recoverable_overflow_resolution(failures)
	_test_unrecoverable_overflow_resolution(failures)
	_test_overflow_merge_interaction(failures)
	_test_overflow_projection_matches_commit(failures)
	_test_independent_gravity_and_split(failures)
	_test_gravity_event_payload(failures)
	_test_gravity_distances_and_sequence(failures)
	_test_merge_stability_event_order(failures)
	_test_orthogonal_merges_only(failures)
	_test_pairwise_component_merges(failures)
	_test_new_results_wait_until_later_wave(failures)
	_test_determinism(failures)
	_test_scoring_waves(failures)
	_test_same_turn_merge_ladder_without_fatigue(failures)
	_test_merge_fatigue_blocks_same_turn_remerge(failures)
	_test_merge_fatigue_allows_independent_branches(failures)
	_test_merge_fatigue_survives_gravity_and_expires(failures)
	_test_same_piece_merges_are_prevented_during_landing(failures)
	_test_piece_generation_values(failures)
	_test_orientation_self_merge_regressions(failures)
	_test_tetromino_catalog(failures)
	_test_large_sample_generation(failures)
	_test_game_over_uses_settlement(failures)
	_test_first_wave_projection(failures)
	_test_multiplier_bar_is_not_a_board_rule(failures)
	return failures


static func _test_config_dimensions(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(Config.board_width, Config.board_height)
	_expect(board.width == 8, "Mergefall board width should be 8.", failures)
	_expect(board.height == 10, "Mergefall board height should be 10.", failures)
	var stored_cells := 0
	for row in board.cells:
		stored_cells += row.size()
	_expect(stored_cells == 80, "Board storage should contain 80 cells.", failures)
	_expect(board.is_inside(Vector2i(7, 9)), "Column 7 and row 9 should be playable.", failures)
	_expect(not board.is_inside(Vector2i(8, 0)), "Column 8 should be outside the board.", failures)
	_expect(not board.is_inside(Vector2i(0, 10)), "Row 10 should be outside the board.", failures)


static func _test_default_config_disables_merge_fatigue(failures: PackedStringArray) -> void:
	_expect(not Config.merge_fatigue_enabled, "Default gameplay config should disable Merge Fatigue.", failures)


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


static func _test_above_board_lock_validation(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(4, 3)
	for x in board.width:
		board.set_value(Vector2i(x, 0), 7 + x)
		board.set_value(Vector2i(x, 1), 11 + x)
		board.set_value(Vector2i(x, 2), 15 + x)
	board.set_value(Vector2i(1, 0), 0)
	_expect(board.can_stage([Vector2i(1, -1)]), "A piece with one cell above row 0 may stage and lock.", failures)
	_expect(board.can_settle([Vector2i(1, -1)], [1]), "A one-cell overflow lock should be allowed for resolution.", failures)
	_expect(board.can_settle([Vector2i(1, -2), Vector2i(1, -1)], [1, 2]), "Multiple above-board cells may lock.", failures)
	_expect(not board.can_settle([Vector2i(-1, -1)], [1]), "Horizontal left overflow remains illegal.", failures)
	_expect(not board.can_settle([Vector2i(4, -1)], [1]), "Horizontal right overflow remains illegal.", failures)
	_expect(not board.can_settle([Vector2i(1, 3)], [1]), "Bottom overflow remains illegal.", failures)
	_expect(not board.can_settle([Vector2i(1, -1), Vector2i(1, -1)], [1, 2]), "Duplicate overflow coordinates are rejected.", failures)


static func _test_recoverable_overflow_resolution(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(2, 2)
	board.set_value(Vector2i(0, 0), 4)
	board.set_value(Vector2i(0, 1), 8)
	board.set_value(Vector2i(1, 1), 9)
	var result := board.settle_cells([Vector2i(1, -1)], [3], 10)
	_expect(result.get("legal", false), "Recoverable overflow should be a legal settlement.", failures)
	_expect(not result.get("has_stable_overflow", true), "Recovered overflow should finish with no stable negative-row cells.", failures)
	_expect(board.get_value(Vector2i(1, 0)) == 3, "An overflow cell should fall into row 0 when space is available.", failures)
	_expect(not board.has_stable_overflow(), "The board should clear temporary overflow after recovery.", failures)


static func _test_unrecoverable_overflow_resolution(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(2, 2)
	board.place_cells([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], [1, 2, 3, 4])
	var result := board.settle_cells([Vector2i(0, -1), Vector2i(1, -1)], [5, 6], 10)
	_expect(result.get("legal", false), "Unrecoverable overflow should still be allowed to lock.", failures)
	_expect(result.get("has_stable_overflow", false), "Stable negative-row cells should be reported for game over after resolution.", failures)
	_expect(board.get_value(Vector2i(0, -1)) == 5 and board.get_value(Vector2i(1, -1)) == 6, "The final jammed overflow state should remain intact.", failures)
	_expect(_event_types(result).back() == "stable", "Overflow loss should be evaluated after stability.", failures)


static func _test_overflow_merge_interaction(failures: PackedStringArray) -> void:
	var horizontal = BoardStateScript.new()
	horizontal.setup(3, 2)
	horizontal.place_cells([Vector2i(0, -1), Vector2i(1, -1)], [1, 1])
	var result := horizontal.resolve_merges(2, 10)
	_expect(result.get("merged", false), "Equal overflow neighbors should merge during resolution.", failures)
	_expect(horizontal.get_value(Vector2i(1, -1)) == 2 or horizontal.get_value(Vector2i(0, -1)) == 2, "Overflow merge result should remain at a logical overflow coordinate when still jammed.", failures)

	var vertical = BoardStateScript.new()
	vertical.setup(2, 2)
	vertical.place_cells([Vector2i(0, -1), Vector2i(0, 0)], [4, 4])
	var row_zero_result := vertical.resolve_merges(2, 10)
	_expect(row_zero_result.get("merged", false), "Row -1 and row 0 adjacency should merge when values match.", failures)
	_expect(vertical.get_value(Vector2i(0, 0)) == 5, "A row -1/row 0 vertical merge should anchor on row 0.", failures)


static func _test_overflow_projection_matches_commit(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(2, 2)
	board.place_cells([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], [1, 2, 3, 4])
	var projection := board.project_settlement([Vector2i(0, -1)], [5])
	_expect(projection.get("legal", false), "Projection should not block a losing overflow placement.", failures)
	_expect(projection.get("has_stable_overflow", false), "Projection should identify stable overflow loss.", failures)
	var actual := board.settle_cells([Vector2i(0, -1)], [5], 10)
	_expect(actual.get("has_stable_overflow", false) == projection.get("has_stable_overflow", false), "Projected overflow loss should match actual resolution.", failures)
	_expect(actual.get("landing_cells", []) == projection.get("landing_cells", []), "Projected overflow landing should match actual landing.", failures)


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


static func _test_merge_stability_event_order(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	board.place_cells([Vector2i(1, 2), Vector2i(2, 2), Vector2i(1, 6), Vector2i(2, 6)], [1, 1, 1, 1])
	var result := board.settle_cells([Vector2i(5, -1)], [9], 10)
	var events: Array = result.get("events", [])
	for index in events.size():
		if events[index].get("type", "") != "gravity_step":
			continue
		var next_merge_index := -1
		for next_index in range(index + 1, events.size()):
			if events[next_index].get("type", "") == "merge_wave":
				next_merge_index = next_index
				break
		_expect(next_merge_index != index, "Merges should be recorded only after a complete gravity event.", failures)
	_expect(_event_types(result).find("gravity_step") < _event_types(result).find("merge_wave"), "Gravity must settle before the first merge wave.", failures)


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
	var result := board.settle_cells([Vector2i(5, -1)], [9], 10, false)
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
	var result := board.settle_cells([Vector2i(5, -1)], [9], 10, false)
	_expect(result["score"] == 24, "Score should use produced displayed values with increasing wave multipliers.", failures)
	_expect(result["steps"][0]["score"] == 4, "A 2+2->4 merge should award 4 in wave one.", failures)
	_expect(result["steps"][2]["score"] == 16, "A 4+4->8 merge should award 16 in wave two.", failures)
	var merge_events: Array = result.get("events", []).filter(func(event: Dictionary) -> bool:
		return event.get("type", "") == "merge_wave"
	)
	_expect(merge_events[0].get("multiplier", 0) == 1 and merge_events[1].get("multiplier", 0) == 2, "Merge events should carry authoritative wave multipliers.", failures)


static func _test_same_turn_merge_ladder_without_fatigue(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(4, 6)
	board.place_cells([Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5)], [1, 1, 1, 1])
	var result := board.settle_cells([Vector2i(3, -1)], [9], 10, false)
	_expect(_merge_wave_count(result) == 2, "Without fatigue, newly created merge tiles may merge again in the same resolution cycle.", failures)
	_expect(_count_value(board, 3) == 1, "Immediate same-turn 4+4 into 8 merge should be restored when fatigue is disabled.", failures)
	var merge_events: Array = result.get("events", []).filter(func(event: Dictionary) -> bool:
		return event.get("type", "") == "merge_wave"
	)
	_expect(merge_events.size() == 2 and merge_events[1].get("multiplier", 0) == 2, "Restored same-turn ladder should retain wave multipliers.", failures)


static func _test_merge_fatigue_blocks_same_turn_remerge(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(4, 6)
	board.place_cells([Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5)], [1, 1, 1, 1])
	var result := board.settle_cells([Vector2i(3, -1)], [9], 10, true)
	_expect(_merge_wave_count(result) == 1, "Fatigue should prevent newly created tiles from merging again in the same turn.", failures)
	_expect(_count_value(board, 2) == 2, "Two fatigued merge results should remain as separate tiles.", failures)
	_expect(_count_value(board, 3) == 0, "Fatigue should stop the immediate 4+4 into 8 cascade.", failures)


static func _test_merge_fatigue_allows_independent_branches(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 6)
	board.place_cells([Vector2i(0, 5), Vector2i(1, 5), Vector2i(4, 5), Vector2i(5, 5)], [1, 1, 3, 3])
	var result := board.settle_cells([Vector2i(2, -1)], [9], 10, true)
	_expect(result.get("merged", false), "Existing independent branches should still merge during the same wave.", failures)
	_expect(result.get("steps", []).size() == 2, "Two unrelated merge branches should resolve simultaneously.", failures)
	_expect(_count_value(board, 2) == 1 and _count_value(board, 4) == 1, "Independent merge results should both be produced.", failures)


static func _test_merge_fatigue_survives_gravity_and_expires(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(5, 7)
	board.place_cells([Vector2i(1, 5), Vector2i(2, 5), Vector2i(1, 6), Vector2i(2, 6), Vector2i(1, 4)], [1, 1, 1, 1, 6])
	var result := board.settle_cells([Vector2i(4, -1)], [9], 10, true)
	_expect(_merge_wave_count(result) == 1, "Fatigue should persist across gravity after merge support is removed.", failures)
	_expect(_count_value(board, 2) == 2, "Fatigued results should fall normally without immediately merging.", failures)
	var later := board.resolve_merges(2, 10)
	_expect(later.get("merged", false), "Fatigue should expire before later merge resolution.", failures)
	_expect(_count_value(board, 3) == 1, "Expired fatigue should allow the later 4+4 into 8 merge.", failures)


static func _test_same_piece_merges_are_prevented_during_landing(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(6, 7)
	var result := board.settle_cells([Vector2i(2, -1), Vector2i(3, -1)], [1, 1], 10)
	_expect(not result["merged"], "Same-spawn cells should not merge during their landing-resolution cycle.", failures)
	_expect(_count_value(board, 1) == 2, "Protected same-spawn cells should both remain on the board.", failures)
	var later := board.resolve_merges(2, 10)
	_expect(later["merged"], "Same cells should merge normally after landing protection expires.", failures)
	_expect(_count_value(board, 2) == 1, "Expired protection should allow the later doubled tile.", failures)


static func _test_piece_generation_values(failures: PackedStringArray) -> void:
	var generator = PieceGeneratorScript.new()
	generator.rng.seed = 12345
	var piece = generator.next_piece(Config.piece_definitions, Config.spawn_progression, 0)
	_expect(piece != null, "Generator should return a piece from valid definitions.", failures)
	_expect(piece.cells.size() == 4, "Generated tetromino should contain exactly four cells.", failures)
	var seen_patterns := {}
	for _index in 256:
		var candidate = generator.next_piece(Config.piece_definitions, Config.spawn_progression, 0)
		var cells: Array = candidate.get_rotated_cells(0)
		var values: Array = candidate.get_rotated_values(0)
		var displayed_values: Array = values.map(func(value: int) -> int:
			return int(pow(2.0, value))
		)
		_expect(displayed_values.all(func(value: int) -> bool:
			return value == 2 or value == 4
		), "Turn-zero generated pieces should only use display values 2 or 4.", failures)
		for first_index in cells.size():
			for second_index in range(first_index + 1, cells.size()):
				var adjacent: bool = (cells[first_index] - cells[second_index]).length_squared() == 1
				_expect(not adjacent or values[first_index] != values[second_index], "Tetromino pieces should avoid adjacent equal internal values.", failures)
		seen_patterns["%s:%s:%s" % [candidate.family, candidate.orientation, values]] = true
	_expect(seen_patterns.size() > 19, "Generated tetrominoes should include both parity value patterns.", failures)


static func _test_tetromino_catalog(failures: PackedStringArray) -> void:
	var generator = PieceGeneratorScript.new()
	var catalog := generator.get_catalog(Config.piece_definitions)
	var counts := {}
	var shapes := {}
	for piece in catalog:
		counts[piece.family] = int(counts.get(piece.family, 0)) + 1
		_expect(piece.cells.size() == 4, "%s should contain exactly four cells." % piece.display_name, failures)
		_expect(_is_normalized(piece.cells), "%s should use normalized coordinates." % piece.display_name, failures)
		_expect(_has_unique_cells(piece.cells), "%s should not duplicate coordinates." % piece.display_name, failures)
		_expect(_is_connected(piece.cells), "%s should be orthogonally connected." % piece.display_name, failures)
		var key := _shape_key(piece.cells)
		_expect(not shapes.has(key), "%s should not duplicate another normalized orientation." % piece.display_name, failures)
		shapes[key] = true
	_expect(counts.keys().size() == 7, "Tetromino catalog should contain exactly seven families.", failures)
	_expect(catalog.size() == 19, "Tetromino catalog should contain exactly 19 orientations.", failures)
	_expect(counts == {"I": 2, "O": 1, "T": 4, "S": 2, "Z": 2, "J": 4, "L": 4}, "Tetromino family counts should match the standard orientation catalog.", failures)


static func _test_orientation_self_merge_regressions(failures: PackedStringArray) -> void:
	var generator = PieceGeneratorScript.new()
	var catalog := generator.get_catalog(Config.piece_definitions)
	for piece in catalog:
		var cells: Array[Vector2i] = piece.get_rotated_cells(0)
		var values := generator._values_for_cells(cells, [1, 2])
		_expect(_unique_values(values).size() == 2, "%s should use exactly two generated ranks." % piece.display_name, failures)
		for support in ["empty", "flat", "uneven"]:
			var board = BoardStateScript.new()
			board.setup(Config.board_width, Config.board_height)
			if support == "flat":
				for x in Config.board_width:
					board.set_value(Vector2i(x, Config.board_height - 1), 9 + posmod(x, 2))
			elif support == "uneven":
				for x in Config.board_width:
					for y in range(Config.board_height - 1, Config.board_height - 1 - posmod(x, 3), -1):
						board.set_value(Vector2i(x, y), 8 + posmod(x + y, 3))
			var staged := _center_staged_cells(cells, Config.board_width)
			var result: Dictionary = board.settle_cells(staged, values, 10)
			_expect(result.get("legal", false), "%s should settle on %s support." % [piece.display_name, support], failures)
			_expect(not result.get("merged", false), "%s should not self-merge on %s support." % [piece.display_name, support], failures)


static func _test_large_sample_generation(failures: PackedStringArray) -> void:
	var first = PieceGeneratorScript.new()
	var second = PieceGeneratorScript.new()
	first.rng.seed = 777
	second.rng.seed = 777
	var families := {}
	var orientations := {}
	var first_signature := []
	var second_signature := []
	for index in 10000:
		var piece = first.next_piece(Config.piece_definitions, Config.spawn_progression, 0)
		var matching_piece = second.next_piece(Config.piece_definitions, Config.spawn_progression, 0)
		var signature := "%s:%s:%s" % [piece.family, piece.orientation, piece.cell_values]
		if index < 64:
			first_signature.append(signature)
			second_signature.append("%s:%s:%s" % [matching_piece.family, matching_piece.orientation, matching_piece.cell_values])
		families[piece.family] = int(families.get(piece.family, 0)) + 1
		var orientation_key := "%s:%s" % [piece.family, piece.orientation]
		orientations[orientation_key] = int(orientations.get(orientation_key, 0)) + 1
		_expect(piece.cells.size() == 4, "Generated sample should not exceed four cells.", failures)
		_expect(_has_unique_cells(piece.cells), "Generated sample should not contain duplicate cells.", failures)
		_expect(_is_normalized(piece.cells), "Generated sample should remain normalized.", failures)
		var bounds := _piece_bounds(piece.cells)
		_expect(bounds.size.x <= Config.board_width and bounds.size.y <= Config.board_height, "Generated sample should fit within board dimensions.", failures)
		_expect(piece.cell_values.all(func(value: int) -> bool:
			return value == 1 or value == 2
		), "Turn-zero generated samples should only use ranks for display values 2 and 4.", failures)
		_expect(_has_valid_values(piece), "Generated sample should not contain adjacent equal values.", failures)
	_expect(first_signature == second_signature, "Identical generator seeds should produce identical queues.", failures)
	_expect(families.keys().size() == 7, "Large sample should include all seven families.", failures)
	_expect(orientations.keys().size() == 19, "Large sample should include all 19 orientations.", failures)
	for family in PieceGeneratorScript.FAMILY_ORDER:
		var family_ratio := float(families.get(family, 0)) / 10000.0
		_expect(absf(family_ratio - (1.0 / 7.0)) < 0.025, "Family %s should retain uniform family-first selection." % family, failures)
	var orientations_per_family := {"I": 2, "O": 1, "T": 4, "S": 2, "Z": 2, "J": 4, "L": 4}
	for orientation_key in orientations:
		var family: String = orientation_key.split(":")[0]
		var conditional_ratio := float(orientations[orientation_key]) / float(families[family])
		var expected_ratio := 1.0 / float(orientations_per_family[family])
		_expect(absf(conditional_ratio - expected_ratio) < 0.05, "Orientation %s should remain uniform within family %s." % [orientation_key, family], failures)
	var different = PieceGeneratorScript.new()
	different.rng.seed = 778
	var different_piece = different.next_piece(Config.piece_definitions, Config.spawn_progression, 0)
	_expect(first_signature[0] != "%s:%s:%s" % [different_piece.family, different_piece.orientation, different_piece.cell_values], "Different seeds should be able to produce different output.", failures)


static func _test_game_over_uses_settlement(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(4, 4)
	_expect(board.has_any_moves([IHorizontalPiece, IVerticalPiece, OPiece]), "An empty tetromino lane should have a legal settlement.", failures)
	for y in board.height:
		for x in board.width:
			board.set_value(Vector2i(x, y), 10 + y * board.width + x)
	_expect(not board.has_any_moves([IHorizontalPiece, IVerticalPiece, OPiece]), "Game over should occur when no tetromino has a legal settlement path.", failures)


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


static func _unique_values(values: Array) -> Dictionary:
	var unique := {}
	for value in values:
		unique[int(value)] = true
	return unique


static func _center_staged_cells(cells: Array[Vector2i], board_width: int) -> Array[Vector2i]:
	var bounds := _piece_bounds(cells)
	var anchor := Vector2i(
		int((board_width - bounds.size.x) / 2) - bounds.position.x,
		-bounds.position.y - bounds.size.y - 1
	)
	var staged: Array[Vector2i] = []
	for cell in cells:
		staged.append(cell + anchor)
	return staged


static func _merge_wave_count(result: Dictionary) -> int:
	var count := 0
	for event in result.get("events", []):
		if event.get("type", "") == "merge_wave":
			count += 1
	return count


static func _event_types(result: Dictionary) -> Array[String]:
	var types: Array[String] = []
	for event in result.get("events", []):
		types.append(event.get("type", ""))
	return types


static func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


static func _has_valid_values(piece: Resource) -> bool:
	for first_index in piece.cells.size():
		for second_index in range(first_index + 1, piece.cells.size()):
			if piece.cell_values[first_index] == piece.cell_values[second_index]:
				if (piece.cells[first_index] - piece.cells[second_index]).length_squared() == 1:
					return false
	return true


static func _is_normalized(cells: Array[Vector2i]) -> bool:
	var bounds := _piece_bounds(cells)
	return bounds.position == Vector2i.ZERO


static func _has_unique_cells(cells: Array[Vector2i]) -> bool:
	var seen := {}
	for cell in cells:
		if seen.has(cell):
			return false
		seen[cell] = true
	return true


static func _is_connected(cells: Array[Vector2i]) -> bool:
	var remaining := {}
	for cell in cells:
		remaining[cell] = true
	var frontier: Array[Vector2i] = [cells[0]]
	remaining.erase(cells[0])
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if remaining.has(next):
				remaining.erase(next)
				frontier.append(next)
	return remaining.is_empty()


static func _piece_bounds(cells: Array[Vector2i]) -> Rect2i:
	var first_cell: Vector2i = cells[0]
	var min_x: int = first_cell.x
	var min_y: int = first_cell.y
	var max_x: int = first_cell.x
	var max_y: int = first_cell.y
	for cell in cells:
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


static func _shape_key(cells: Array[Vector2i]) -> String:
	var sorted := cells.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return str(sorted)
