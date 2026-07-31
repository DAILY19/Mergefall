extends RefCounted

## Board-jammed rule tests (pure logic, no frames).
##
## Rule under test ("any legal player move", Option 2):
##   - Every new piece spawns at the centered/default anchor.
##   - The run ends ONLY when no horizontal anchor allows a legal staged spawn
##     with an eventual non-overflow landing.
##   - The legality scan must never write current_anchor (no auto-relocation).
##
## These tests call Main's private helpers directly on an un-treed instance
## (they touch no nodes). Scene-level end-to-end coverage lives in
## res://tests/board_jammed_runner.gd.

const MainScript = preload("res://scripts/managers/main.gd")
const Config = preload("res://resources/config/default_game_config.tres")
const OPiece = preload("res://resources/pieces/o.tres")
const IHorizontalPiece = preload("res://resources/pieces/i_horizontal.tres")


static func run() -> PackedStringArray:
	var failures := PackedStringArray()
	_test_1_centered_blocked_side_legal(failures)
	_test_1b_reported_false_positive(failures)
	_test_2_no_legal_columns(failures)
	_test_2b_horizontal_true_jam(failures)
	_test_3_scan_never_relocates(failures)
	_test_4_anchor_set_before_scan(failures)
	return failures


static func _fresh_main():
	var main = MainScript.new()
	main.config = Config
	main.board_state.setup(int(Config.board_width), int(Config.board_height))
	return main


## Fills every cell in the given columns with a checkerboard of rank/rank+1 so
## no two filled cells are equal orthogonal neighbors (they must never merge on
## their own). rank/rank+1 are far above any piece value, so a landed piece's
## overflow can never merge with the fill either — overflow is guaranteed stable.
static func _fill_columns(main, columns: Array, rank: int) -> void:
	for x in columns:
		for y in Config.board_height:
			main.board_state.set_value(Vector2i(x, y), rank + (x + y) % 2)


static func _fill_all(main, rank: int) -> void:
	for x in Config.board_width:
		for y in Config.board_height:
			main.board_state.set_value(Vector2i(x, y), rank + (x + y) % 2)


static func _fill_columns_pattern(main, columns: Array) -> void:
	for x in columns:
		for y in Config.board_height:
			main.board_state.set_value(Vector2i(x, y), 1 + (x + y) % 4)


static func _center_landing_legal(main, piece: Resource, anchor: Vector2i) -> bool:
	var staged: Array[Vector2i] = []
	for cell in piece.get_rotated_cells(0):
		staged.append(cell + anchor)
	var projection: Dictionary = main.board_state.project_settlement(staged, piece.get_rotated_values(0))
	return bool(projection.get("legal", false)) and not bool(projection.get("has_stable_overflow", false))


## Test 1 — centered spawn blocked, side columns legal:
## O piece, columns 3-4 full to the top (rank 20 never merges with 1/2).
## Center landing is invalid, but x=0 and x=5/6 land on empty columns.
static func _test_1_centered_blocked_side_legal(failures: PackedStringArray) -> void:
	var main = _fresh_main()
	_fill_columns(main, [3, 4], 20)
	main.current_piece = OPiece
	var ok := main._find_legal_staging_position()
	_expect(ok, "T1: centered column blocked but side columns legal -> run must continue.", failures)
	_expect(main.current_anchor == Vector2i(3, -3), "T1: piece must stay at the centered anchor, not auto-relocate.", failures)
	_expect(not _center_landing_legal(main, OPiece, Vector2i(3, -3)), "T1: scenario sanity — the centered landing must be invalid.", failures)
	_expect(not main.game_over, "T1: spawn scan must not mark game over by itself.", failures)
	var stage_y: int = main.current_anchor.y
	_expect(main._can_piece_fit(Vector2i(0, stage_y), 0), "T1: player can move left to the legal column x=0.", failures)
	_expect(main._can_piece_fit(Vector2i(5, stage_y), 0), "T1: player can move right to the legal column x=5.", failures)
	_expect(not main._can_piece_fit(Vector2i(7, stage_y), 0), "T1: out-of-bounds anchor stays invalid (sanity).", failures)
	main.free()


## Test 1b — the exact reported false positive:
## I Horizontal, centered footprint (columns 2-5) full to the top with the
## pattern 1+(x+y)%4. Center landing overflows, but the side anchor x=4 clears
## its overflow through a merge cascade. Previously this declared BOARD JAMMED.
static func _test_1b_reported_false_positive(failures: PackedStringArray) -> void:
	var main = _fresh_main()
	_fill_columns_pattern(main, [2, 3, 4, 5])
	main.current_piece = IHorizontalPiece
	var ok := main._find_legal_staging_position()
	_expect(ok, "T1b: reported false positive — a legal side column exists, so the run must continue.", failures)
	_expect(main.current_anchor == Vector2i(2, -2), "T1b: piece must remain at the centered anchor.", failures)
	_expect(not _center_landing_legal(main, IHorizontalPiece, Vector2i(2, -2)), "T1b: scenario sanity — the centered landing must be invalid.", failures)
	main.free()


## Test 2 — no legal columns anywhere: full board with non-merging values.
static func _test_2_no_legal_columns(failures: PackedStringArray) -> void:
	var main = _fresh_main()
	_fill_all(main, 20)
	main.current_piece = OPiece
	var ok := main._find_legal_staging_position()
	_expect(not ok, "T2: no horizontal anchor legal -> run over.", failures)
	_expect(main.current_anchor == Vector2i(3, -3), "T2: anchor is still deterministic (centered) even when jamming.", failures)
	main.free()


## Test 2b — the reported piece, non-merging full center: a true jam.
static func _test_2b_horizontal_true_jam(failures: PackedStringArray) -> void:
	var main = _fresh_main()
	_fill_columns(main, [2, 3, 4, 5], 20)
	main.current_piece = IHorizontalPiece
	var ok := main._find_legal_staging_position()
	_expect(not ok, "T2b: with non-merging full center footprint no side anchor is legal -> true jam.", failures)
	main.free()


## Test 3 — the legality scan must never write current_anchor.
static func _test_3_scan_never_relocates(failures: PackedStringArray) -> void:
	var main = _fresh_main()
	_fill_columns(main, [3, 4], 20)
	main.current_piece = OPiece
	var rotated: Array[Vector2i] = OPiece.get_rotated_cells(0)
	var bounds: Rect2i = main._piece_bounds(rotated)
	var stage_y: int = -bounds.position.y - bounds.size.y - 1
	main.current_anchor = Vector2i(99, 99)  # Sentinel: scan must leave it alone.
	var any_legal := main._any_anchor_has_legal_path(rotated, stage_y, 0, 6)
	_expect(any_legal, "T3: scan should find the legal side column.", failures)
	_expect(main.current_anchor == Vector2i(99, 99), "T3: scan must never write current_anchor (no horizontal rescue).", failures)
	main.free()


## Test 4 — the spawn helper sets the centered anchor before scanning; a jammed
## board still leaves the deterministic centered anchor.
static func _test_4_anchor_set_before_scan(failures: PackedStringArray) -> void:
	var main = _fresh_main()
	_fill_all(main, 20)
	main.current_piece = IHorizontalPiece
	var ok := main._find_legal_staging_position()
	_expect(not ok, "T4: full board is a true jam for the I piece.", failures)
	_expect(main.current_anchor == Vector2i(2, -2), "T4: jammed spawn still uses the centered anchor deterministically.", failures)
	main.free()


static func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
