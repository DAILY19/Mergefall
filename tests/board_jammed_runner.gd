extends SceneTree

## Board-jammed integration tests (full scene, turn sequence).
##
## Rule under test ("any legal player move", Option 2):
##   - Every new piece spawns at the centered/default anchor.
##   - A run ends only when NO horizontal anchor allows a legal staged spawn
##     with an eventual non-overflow landing.
##   - No automatic relocation ever occurs; the player moves the piece.
##   - Visual staging offsets never modify gameplay coordinates.
##   - Game-over evaluation only happens after the placement+gravity+merge
##     sequence completes.
##
## Run: godot --headless -s res://tests/board_jammed_runner.gd

const OPiece = preload("res://resources/pieces/o.tres")
const IHorizontalPiece = preload("res://resources/pieces/i_horizontal.tres")
const IVerticalPiece = preload("res://resources/pieces/i_vertical.tres")

var failures: PackedStringArray = []
var _main


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(42)
	var scene := load("res://scenes/main.tscn") as PackedScene
	_main = scene.instantiate()
	root.add_child(_main)
	_main.start_new_game()
	for i in 60:
		await process_frame

	await _test_1_centered_blocked_side_legal()
	await _test_1b_reported_false_positive()
	await _test_2_no_legal_columns()
	await _test_3_visual_staging_independent()
	await _test_4_no_auto_relocation()
	await _test_5_resolution_ordering()

	if failures.is_empty():
		print("Board-jammed integration tests passed.")
		quit(0)
	else:
		print("FAILED:")
		for f in failures:
			print("  ", f)
		quit(1)


# --- scenario helpers ------------------------------------------------------

## Fresh run so tests never inherit game_over/board state from a previous test.
func _reset_run() -> void:
	_main.start_new_game()
	for i in 10:
		await process_frame


func _force_piece(piece: Resource) -> void:
	_main.next_pieces.push_front(piece)
	_main._draw_next_piece()
	await process_frame


## Force the exact next piece that will be drawn after the current turn resolves.
func _queue_next_piece(piece: Resource) -> void:
	_main.next_pieces.clear()
	_main.next_pieces.push_front(piece)


## Checkerboard of rank/rank+1: no equal orthogonal neighbors among the fill and
## no overlap with piece values, so overflow cells above the fill never merge and
## always count as stable overflow.
func _fill_columns(columns: Array, rank: int) -> void:
	var board = _main.board_state
	board.setup(int(_main.config.board_width), int(_main.config.board_height))
	for x in columns:
		for y in _main.config.board_height:
			board.set_value(Vector2i(x, y), rank + (x + y) % 2)


func _fill_all(rank: int) -> void:
	var board = _main.board_state
	board.setup(int(_main.config.board_width), int(_main.config.board_height))
	for x in _main.config.board_width:
		for y in _main.config.board_height:
			board.set_value(Vector2i(x, y), rank + (x + y) % 2)


func _fill_columns_pattern(columns: Array) -> void:
	var board = _main.board_state
	board.setup(int(_main.config.board_width), int(_main.config.board_height))
	for x in columns:
		for y in _main.config.board_height:
			board.set_value(Vector2i(x, y), 1 + (x + y) % 4)


func _await_resolution() -> void:
	for i in 400:
		await process_frame
		if not _main.board_view.is_resolution_feedback_active():
			break
	await process_frame


# --- tests -----------------------------------------------------------------

## Test 1 — centered spawn blocked (columns 3-4 full), side columns legal.
## The run continues, the piece stays centered, and the player can move to a
## legal column and drop without a game over.
func _test_1_centered_blocked_side_legal() -> void:
	await _reset_run()
	_fill_columns([3, 4], 20)
	await _force_piece(OPiece)
	_expect(not _main.game_over, "T1: centered blocked + side legal -> run continues.", failures)
	_expect(_main.current_anchor == Vector2i(3, -3), "T1: piece spawns centered (no auto-relocation).", failures)
	# Player moves left three times to the fully open columns 0-1.
	_main._try_move_anchor(Vector2i.LEFT)
	_main._try_move_anchor(Vector2i.LEFT)
	_main._try_move_anchor(Vector2i.LEFT)
	_expect(_main.current_anchor.x == 0, "T1: player movement reaches the legal column x=0.", failures)
	# Control the post-resolution piece so the final assertions are deterministic.
	_queue_next_piece(IVerticalPiece)
	_main._confirm_drop()
	await _await_resolution()
	_expect(not _main.game_over, "T1: dropping on the legal side column resolves without game over.", failures)
	_expect(_main.current_piece != null, "T1: next piece is drawn after a valid drop.", failures)


## Test 1b — the reported false positive (I horizontal, columns 2-5 full with
## merging pattern): side anchor x=4 is legal, so the run must continue and the
## piece must stay centered.
func _test_1b_reported_false_positive() -> void:
	await _reset_run()
	_fill_columns_pattern([2, 3, 4, 5])
	await _force_piece(IHorizontalPiece)
	_expect(not _main.game_over, "T1b: reported screenshot scenario — side column legal, run continues.", failures)
	_expect(_main.current_anchor == Vector2i(2, -2), "T1b: piece remains centered.", failures)


## Test 2 — no legal columns anywhere: full board with non-merging values.
func _test_2_no_legal_columns() -> void:
	await _reset_run()
	_fill_all(20)
	await _force_piece(IHorizontalPiece)
	_expect(_main.game_over, "T2: no horizontal anchor legal -> true game over.", failures)


## Test 3 — visual staging/overflow offsets never modify gameplay coordinates.
func _test_3_visual_staging_independent() -> void:
	await _reset_run()
	_fill_columns([3, 4], 20)
	await _force_piece(OPiece)
	_main._refresh_presentation()
	var anchor_before: Vector2i = _main.current_anchor
	var cells_before: Array[Vector2i] = _main._current_cells()
	var board_rect: Rect2 = _main.board_view.get_board_rect()
	var offset: Vector2 = _main.board_view._staging_visual_offset(board_rect, cells_before)
	_expect(offset.x == 0.0, "T3: visual staging offset is vertical-only.", failures)
	_expect(_main.current_anchor == anchor_before, "T3: visual offset must not modify current_anchor.", failures)
	_expect(_main._current_cells() == cells_before, "T3: visual offset must not modify placement coordinates.", failures)
	_expect(_main.board_view._current_anchor == _main.current_anchor, "T3: view anchor mirrors the gameplay anchor.", failures)


## Test 4 — drawing the next piece never relocates it horizontally.
func _test_4_no_auto_relocation() -> void:
	await _reset_run()
	_fill_columns([3, 4], 20)
	await _force_piece(OPiece)
	_expect(_main.current_anchor == Vector2i(3, -3), "T4: first draw keeps the centered anchor.", failures)
	_main.next_pieces.push_front(OPiece)
	_main._draw_next_piece()
	await process_frame
	_expect(_main.current_anchor == Vector2i(3, -3), "T4: redrawing the piece still keeps the centered anchor.", failures)


## Test 5 — game-over evaluation happens only after the placement/gravity/merge
## sequence completes; the active piece is not replaced mid-resolution and
## movement is disabled while resolving.
func _test_5_resolution_ordering() -> void:
	await _reset_run()
	var board = _main.board_state
	board.setup(int(_main.config.board_width), int(_main.config.board_height))
	await _force_piece(IVerticalPiece)
	var piece_before: Resource = _main.current_piece
	_main._confirm_drop()
	_expect(_main.board_view.is_resolution_feedback_active(), "T5: resolution feedback is active after the drop.", failures)
	_expect(_main.current_piece == piece_before, "T5: active piece is not replaced mid-resolution.", failures)
	_expect(not _main.game_over, "T5: no game-over evaluation mid-resolution.", failures)
	var anchor_before: Vector2i = _main.current_anchor
	_main._try_move_anchor(Vector2i.LEFT)
	_expect(_main.current_anchor == anchor_before, "T5: movement is disabled during resolution.", failures)
	await _await_resolution()
	_expect(_main.current_piece != null, "T5: next piece is drawn after resolution completes.", failures)
	_expect(not _main.game_over, "T5: empty-board drop resolves without game over.", failures)


func _expect(condition: bool, message: String, out: PackedStringArray) -> void:
	if not condition:
		out.append(message)
