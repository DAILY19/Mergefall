extends RefCounted

const BoardStateScript = preload("res://scripts/core/board_state.gd")
const SingleCrumbPiece = preload("res://resources/pieces/single_crumb.tres")


static func run() -> PackedStringArray:
	var failures := PackedStringArray()
	_test_basic_placement(failures)
	_test_merge_resolution(failures)
	_test_no_double_merge_loop(failures)
	_test_move_detection(failures)
	return failures


static func _test_basic_placement(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(4, 4)
	var cells: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1)]
	_expect(board.can_place(cells), "Expected empty cells to accept placement.", failures)
	board.place_cells(cells, [1, 2])
	_expect(not board.can_place(cells), "Expected occupied cells to reject placement.", failures)
	_expect(board.get_value(Vector2i(1, 1)) == 1, "Expected placed value 1 at (1,1).", failures)
	_expect(board.get_value(Vector2i(2, 1)) == 2, "Expected placed value 2 at (2,1).", failures)


static func _test_merge_resolution(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(4, 4)
	board.place_cells(
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		[1, 1, 1]
	)
	var result := board.resolve_merges(2, 10)
	_expect(result["merged"], "Expected three connected matching tiles to merge.", failures)
	_expect(board.get_value(Vector2i(0, 0)) == 2, "Expected merged anchor tile to upgrade to rank 2.", failures)
	_expect(board.get_value(Vector2i(1, 0)) == 0, "Expected merged neighbor to be cleared.", failures)
	_expect(board.get_value(Vector2i(2, 0)) == 0, "Expected merged neighbor to be cleared.", failures)
	_expect(result["score"] == 60, "Expected merge score of 60 for three rank-1 tiles at 10 points per rank.", failures)


static func _test_no_double_merge_loop(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(4, 4)
	board.place_cells(
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[1, 1, 1, 1]
	)
	var result := board.resolve_merges(2, 10)
	_expect(result["merged"], "Expected first merge step to occur.", failures)
	_expect(board.get_value(Vector2i(0, 0)) == 2, "Expected one upgraded tile after resolving a four-cell group.", failures)
	_expect(board.get_value(Vector2i(1, 0)) == 0, "Expected cleared merged cell at (1,0).", failures)
	_expect(board.get_value(Vector2i(0, 1)) == 0, "Expected cleared merged cell at (0,1).", failures)
	_expect(board.get_value(Vector2i(1, 1)) == 0, "Expected cleared merged cell at (1,1).", failures)


static func _test_move_detection(failures: PackedStringArray) -> void:
	var board = BoardStateScript.new()
	board.setup(2, 2)
	board.place_cells(
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
		[1, 1, 1]
	)
	_expect(board.has_any_moves([SingleCrumbPiece]), "Expected one remaining empty cell to count as a legal move.", failures)
	board.set_value(Vector2i(1, 1), 2)
	_expect(not board.has_any_moves([SingleCrumbPiece]), "Expected no legal placements on a full board.", failures)


static func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
