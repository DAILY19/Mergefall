extends SceneTree

const SinglePiece = preload("res://resources/pieces/single_crumb.tres")
const CornerPiece = preload("res://resources/pieces/l_snack.tres")
const SpirePiece = preload("res://resources/pieces/tray_tower.tres")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var failures := PackedStringArray()

	_expect(main.config.board_width == 6 and main.config.board_height == 7, "The scene should use the authoritative 6x7 configuration.", failures)
	var buttons_row: Node = main.hud.get_node("%LeftButton").get_parent()
	var visible_buttons: Array[String] = []
	for child in buttons_row.get_children():
		if child is Button and child.visible:
			visible_buttons.append(child.text.to_upper())
	_expect(visible_buttons == ["LEFT", "DROP", "RIGHT"], "Bottom controls should be ordered LEFT, DROP, RIGHT.", failures)
	_expect(not main.hud.get_node("%RotateButton").visible, "Rotation control should be hidden.", failures)
	_expect(not main.board_view.clip_contents, "The active-piece view should not clip above-board cells.", failures)
	var initial_board_rect: Rect2 = main.board_view.get_board_rect()
	var initial_drop_zone_rect: Rect2 = main.board_view.get_drop_zone_rect(initial_board_rect)
	var initial_metrics: Dictionary = main.board_view._calculate_gameplay_metrics()
	_expect(initial_drop_zone_rect.size.y > 0.0, "A separate drop-zone presentation region should exist above the board.", failures)
	_expect(is_equal_approx(initial_drop_zone_rect.position.x, initial_board_rect.position.x), "The drop zone should share the board's left edge.", failures)
	_expect(is_equal_approx(initial_drop_zone_rect.size.x, initial_board_rect.size.x), "The drop zone width should match the game board width.", failures)
	_expect(initial_drop_zone_rect.end.y <= initial_board_rect.position.y, "The drop zone should sit above the actual board.", failures)
	_expect(
		initial_metrics.get("tile_size", 0.0) > 0.0
		and is_equal_approx(initial_metrics.get("tile_size", 0.0), main.board_view._grid_metrics(initial_board_rect).get("cell", 0.0)),
		"Board, drop zone, ghost, active piece, and settled cells should share one cached tile size.",
		failures
	)
	_expect(
		is_equal_approx(initial_board_rect.get_center().x, main.hud.get_board_layout_rect().get_center().x),
		"The combined gameplay structure should be horizontally centered in the board slot.",
		failures
	)
	var resized_slot: Rect2 = main.hud.get_board_layout_rect()
	resized_slot.size.x = maxf(160.0, resized_slot.size.x - 48.0)
	main.board_view.set_layout_rect(resized_slot)
	var resized_board_rect: Rect2 = main.board_view.get_board_rect()
	_expect(
		resized_board_rect.size.x < initial_board_rect.size.x,
		"Board metrics should update when the layout rect changes.",
		failures
	)
	main.board_view.set_layout_rect(main.hud.get_board_layout_rect())
	_expect(main.board_view.drop_zone_fill_color != main.config.board_color, "The drop-zone background should differ from the board background.", failures)
	_expect(main.board_view.drop_zone_fill_color != main.config.background_color, "The drop-zone background should differ from the screen background.", failures)
	var mixed_gravity_event := {
		"type": "gravity_step",
		"moves": [
			{"from": Vector2i(0, 2), "to": Vector2i(0, 6), "value": 1, "distance": 4},
			{"from": Vector2i(1, 5), "to": Vector2i(1, 6), "value": 2, "distance": 1}
		]
	}
	var gravity_duration: float = main.board_view._event_duration(mixed_gravity_event)
	_expect(gravity_duration == main.board_view._gravity_move_duration(4), "A gravity event should wait for its longest simultaneous fall.", failures)
	_expect(main.board_view._gravity_move_duration(1) < gravity_duration, "Short and long falls should use distinct distance-based durations.", failures)
	var ordered_events: Array[Dictionary] = [
		mixed_gravity_event,
		{"type": "merge_wave", "wave": 1, "multiplier": 1, "steps": []}
	]
	var ordered_segments: Array[Dictionary] = main.board_view._build_resolution_event_segments(ordered_events)
	_expect(
		float(ordered_segments[1].get("start", 0.0)) >= gravity_duration,
		"A later merge event should not begin before all gravity moves finish.",
		failures
	)

	main.start_new_game()
	main.current_piece = SpirePiece
	_expect(main._find_legal_staging_position(), "A vertical three-cell piece should have a legal staged spawn.", failures)
	main._refresh_board_view()
	var staged_cells: Array[Vector2i] = main._current_cells()
	_expect(staged_cells == [Vector2i(2, -4), Vector2i(2, -3), Vector2i(2, -2)], "Spawn positioning should keep the Spire higher while aligned with the board entrance.", failures)
	var board_rect: Rect2 = main.board_view.get_board_rect()
	var drop_zone_rect: Rect2 = main.board_view.get_drop_zone_rect(board_rect)
	var top_staged_rect: Rect2 = main.board_view.get_cell_rect(board_rect, staged_cells[0])
	var bottom_staged_rect: Rect2 = main.board_view.get_cell_rect(board_rect, staged_cells[-1])
	_expect(
		top_staged_rect.position.y >= drop_zone_rect.position.y and bottom_staged_rect.end.y <= drop_zone_rect.end.y,
		"The complete vertical piece should fit in the visible drop zone (%s to %s within %s)." % [top_staged_rect, bottom_staged_rect, drop_zone_rect],
		failures
	)
	_expect(
		bottom_staged_rect.end.y < board_rect.position.y - (bottom_staged_rect.size.y * 0.5),
		"The staged piece should leave visible space before the board entrance.",
		failures
	)

	main.start_new_game()
	main.current_piece = CornerPiece
	main.current_anchor = Vector2i(0, 0)
	main.current_rotation = 0
	main._try_rotate(1)
	_expect(main.current_rotation == 0, "Rotation input should not alter the active fixed-orientation piece.", failures)

	main.start_new_game()
	main.current_piece = SinglePiece
	main.current_anchor = Vector2i(2, -2)
	main.current_rotation = 0
	main._process(10.0)
	_expect(main.current_anchor == Vector2i(2, -2), "Pieces should never descend on a timer.", failures)
	_expect(main.board_state.get_value(Vector2i(2, main.config.board_height - 1)) == 0, "Waiting should not place a piece.", failures)
	main._confirm_drop()
	_expect(main.board_state.get_value(Vector2i(2, main.config.board_height - 1)) == 1, "Drop confirmation should settle at the floor.", failures)
	_expect(main.board_view.is_resolution_feedback_active(), "Drop should begin a sequenced resolution presentation.", failures)
	_expect(main.board_view._resolution_from == [Vector2i(2, -2)], "Rigid-drop animation should start from the displayed drop-zone position.", failures)
	var hidden_piece_anchor: Vector2i = main.current_anchor
	var piece_before_resolution: Resource = main.current_piece
	main._try_move_anchor(Vector2i.LEFT)
	_expect(main.current_anchor == hidden_piece_anchor, "The hidden next piece must not accept input during resolution feedback.", failures)
	_expect(main.current_piece == piece_before_resolution, "The next piece should not activate before resolution feedback finishes.", failures)
	await create_timer(1.6).timeout
	_expect(not main.board_view.is_resolution_feedback_active(), "Resolution presentation should finish before the next turn accepts input.", failures)
	_expect(main.current_piece != null, "A next piece should be active after resolution feedback finishes.", failures)
	_expect(main.hud.get_multiplier_bar_state() != "resolving", "The multiplier bar should leave resolving state only after the turn finishes.", failures)

	main.start_new_game()
	main.current_piece = SinglePiece
	main.current_anchor = Vector2i(2, 0)
	main.current_rotation = 0
	main._try_move_anchor(Vector2i.LEFT)
	_expect(main.current_anchor == Vector2i(1, 0), "Left input should remain available.", failures)
	main._try_move_anchor(Vector2i.RIGHT)
	_expect(main.current_anchor == Vector2i(2, 0), "Right input should remain available.", failures)
	main.current_anchor = Vector2i(0, 0)
	main._try_move_anchor(Vector2i.LEFT)
	_expect(
		main.gameplay_audio.input_player.stream.resource_path.ends_with("UI_Button_Disable.wav"),
		"Blocked movement should use the disabled-input cue.",
		failures
	)

	main.start_new_game()
	main.current_piece = SinglePiece
	main.current_anchor = Vector2i(2, 0)
	main.current_rotation = 0
	main.board_state.set_value(Vector2i(2, main.config.board_height - 1), 1)
	main._refresh_presentation()
	await create_timer(0.2).timeout
	_expect(main.hud.get_multiplier_bar_state() == "preview", "A projected first-wave merge should highlight the multiplier bar.", failures)
	_expect(main.hud.get_displayed_multiplier() == 1, "Preview feedback must retain the base multiplier.", failures)
	_expect(main.hud.get_multiplier_bar_value() > 0.0, "Preview feedback should use a small fixed bar fill.", failures)
	main._try_move_anchor(Vector2i.LEFT)
	main._try_move_anchor(Vector2i.LEFT)
	await create_timer(0.2).timeout
	_expect(main.hud.get_multiplier_bar_state() == "idle", "Moving away from a projected merge should refresh the bar to idle.", failures)
	main._try_move_anchor(Vector2i.RIGHT)
	main._try_move_anchor(Vector2i.RIGHT)
	await create_timer(0.2).timeout
	_expect(main.hud.get_multiplier_bar_state() == "preview", "Moving back to a merge lane should restore staged preview.", failures)
	var resolution_events: Array[String] = []
	var shown_multipliers: Array[int] = []
	main.board_view.resolution_event_started.connect(func(event: Dictionary) -> void:
		resolution_events.append(event.get("type", ""))
		if event.get("type", "") == "merge_wave":
			shown_multipliers.append(int(event.get("multiplier", 0)))
	)
	main._confirm_drop()
	_expect(main.hud.get_multiplier_bar_state() == "resolving", "Drop should clear staged preview and begin resolution feedback.", failures)
	_expect(main.board_state.get_value(Vector2i(2, main.config.board_height - 1)) == 2, "A falling tile should merge with equal orthogonal support.", failures)
	await create_timer(1.4).timeout
	_expect(resolution_events.find("rigid_landing") < resolution_events.find("merge_wave"), "Rigid landing should animate before the merge wave.", failures)
	_expect(shown_multipliers == [1], "The first merge event should display authoritative multiplier x1.", failures)
	_expect(main.score == 4, "Score presentation should advance from the authoritative merge-wave score.", failures)

	main.hud.reset_multiplier_bar()
	_expect(main.hud.get_multiplier_bar_state() == "idle" and main.hud.get_multiplier_bar_value() == 0.0, "The multiplier bar should have a neutral idle state.", failures)
	main.hud.set_merge_preview(true)
	_expect(main.hud.get_displayed_multiplier() == 1, "Preview state should not alter the actual multiplier.", failures)
	main.hud.begin_turn_resolution()
	main.hud.show_merge_wave(1, 0.25)
	_expect(main.hud.get_displayed_multiplier() == 1, "First resolved wave should display x1.", failures)
	main.hud.show_merge_wave(2, 0.5)
	_expect(main.hud.get_displayed_multiplier() == 2, "Second resolved wave should display x2.", failures)
	main.hud.show_merge_wave(4, 1.0)
	_expect(main.hud.get_displayed_multiplier() == 4, "Later resolved waves should use the passed authoritative multiplier.", failures)
	main.hud.reset_multiplier_bar()
	_expect(main.hud.get_displayed_multiplier() == 1, "Reset should restore the base multiplier between turns.", failures)
	_expect(not main.hud.get_node("%ToastLabel").visible, "No staged-merge popup should be displayed.", failures)

	main.start_new_game()
	main.current_piece = SinglePiece
	main.current_anchor = Vector2i(2, 0)
	main.current_rotation = 0
	main.board_state.set_value(Vector2i(2, 5), 3)
	main._refresh_board_view()
	var landing_cells: Array[Vector2i] = main.board_view._landing_cells()
	_expect(landing_cells == [Vector2i(2, 4)], "Ghost should stop at the authoritative rigid landing cell.", failures)
	_expect(landing_cells[0].y >= 0 and landing_cells[0].y < main.config.board_height, "Ghost cells should remain inside the actual board.", failures)

	for failure in failures:
		push_error(failure)
	root.remove_child(main)
	main.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
