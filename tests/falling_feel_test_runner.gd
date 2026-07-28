extends SceneTree

const IHorizontalPiece = preload("res://resources/pieces/i_horizontal.tres")
const IVerticalPiece = preload("res://resources/pieces/i_vertical.tres")
const OPiece = preload("res://resources/pieces/o.tres")
const TUpPiece = preload("res://resources/pieces/t_up.tres")
const MobileWebDprScript = preload("res://scripts/core/mobile_web_dpr.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._refresh_presentation()
	await process_frame
	main.set_process(false)
	var failures := PackedStringArray()

	_expect(main.config.board_width == 8 and main.config.board_height == 10, "The scene should use the authoritative 8x10 configuration.", failures)
	_expect(main.config.piece_definitions.size() == 19, "The scene should use the 19-orientation tetromino catalog.", failures)
	_expect(main.completed_turns == 0 and main.current_piece.generation_turn == 0, "A new run should activate a turn-zero piece.", failures)
	_expect(
		main.next_pieces.map(func(piece: Resource) -> int: return piece.generation_turn) == [1, 2, 3],
		"Initial queue previews should be generated for their future activation turns.",
		failures
	)
	var control_rects: Dictionary = main.hud.get_side_control_rects()
	var left_rect: Rect2 = control_rects.get("left", Rect2())
	var right_rect: Rect2 = control_rects.get("right", Rect2())
	var drop_rect: Rect2 = control_rects.get("drop", Rect2())
	var first_board_rect: Rect2 = main.board_view.get_board_rect()
	var hud_rect: Rect2 = main.hud.get_global_rect()
	_expect(main.hud.get_node("%LeftButton").text == "<", "Left control should use an arrow treatment.", failures)
	_expect(main.hud.get_node("%RightButton").text == ">", "Right control should use an arrow treatment.", failures)
	_expect(left_rect.end.x <= first_board_rect.position.x + 0.5, "Left control should sit entirely left of the playable board.", failures)
	_expect(right_rect.position.x >= first_board_rect.end.x - 0.5, "Right control should sit entirely right of the playable board.", failures)
	_expect(left_rect.position.x >= hud_rect.position.x and right_rect.end.x <= hud_rect.end.x + 0.5, "Side controls should remain within the viewport.", failures)
	_expect(absf(drop_rect.get_center().x - first_board_rect.get_center().x) <= 8.0, "Drop control should remain centered beneath the board.", failures)
	_expect(drop_rect.position.y > first_board_rect.end.y, "Drop control should remain beneath the board.", failures)
	_expect(not main.hud.get_node("%RotateButton").visible, "Rotation control should be hidden.", failures)
	_expect(main.hud.get_node("%RestartButton").text == "NEW RUN", "Restart control should use the idle NEW RUN label.", failures)
	_expect(main.hud.get_new_run_hold_progress() == 0.0, "New Run hold progress should begin at zero.", failures)
	_expect(not main.board_view.clip_contents, "The active-piece view should not clip above-board cells.", failures)
	_expect(not main.board_view.diagnostics.enabled, "Render diagnostics should be disabled by default.", failures)
	main.board_view.set_diagnostics_enabled(true)
	main.board_view.reset_diagnostics()
	main.board_view._request_redraw()
	var diagnostics_report: Dictionary = main.board_view.diagnostics_report()
	_expect(diagnostics_report.get("redraw_requests", 0) == 1, "Diagnostics should count redraw requests when explicitly enabled.", failures)
	_expect(diagnostics_report.get("state", "") == "STATIONARY", "Idle main scene should classify as STATIONARY.", failures)
	main.board_view.set_diagnostics_enabled(false)
	_expect(not main.board_view.diagnostics.enabled, "Diagnostics should be disable-able after measurement.", failures)
	var mobile_context := {
		"is_web": true,
		"touch_primary": true,
		"mobile_user_agent": true,
		"viewport": Vector2i(390, 844),
		"device_pixel_ratio": 3.0,
		"enabled": true,
		"cap": 2.0
	}
	var mobile_dpr := MobileWebDprScript.effective_dpr(mobile_context)
	_expect(mobile_dpr.get("applied", false), "Mobile viewport Web context should apply the DPR cap in the shared DPR helper.", failures)
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
		absf(initial_board_rect.get_center().x - main.hud.get_board_layout_rect().get_center().x) <= 1.0,
		"The combined gameplay structure should be horizontally centered in the board slot (center x=%.1f, slot x=%.1f)." % [initial_board_rect.get_center().x, main.hud.get_board_layout_rect().get_center().x],
		failures
	)
	var resized_slot: Rect2 = main.hud.get_board_layout_rect()
	resized_slot.size.x = maxf(160.0, resized_slot.size.x - 180.0)
	main.board_view.set_layout_rect(resized_slot)
	var resized_board_rect: Rect2 = main.board_view.get_board_rect()
	_expect(
		main.board_view._calculate_gameplay_metrics().get("available_rect", Rect2()) == resized_slot
		and resized_board_rect.position != initial_board_rect.position,
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
	main.current_piece = IVerticalPiece
	_expect(main._find_legal_staging_position(), "A vertical I piece should have a legal staged spawn.", failures)
	main._refresh_board_view()
	var staged_cells: Array[Vector2i] = main._current_cells()
	_expect(staged_cells.size() == 4, "The vertical I piece should expose all four drawable cells.", failures)
	var board_rect: Rect2 = main.board_view.get_board_rect()
	var drop_zone_rect: Rect2 = main.board_view.get_drop_zone_rect(board_rect)
	var staged_rects: Array[Rect2] = []
	for cell in staged_cells:
		staged_rects.append(main.board_view.get_staged_cell_rect(board_rect, cell, staged_cells))
	_expect(
		staged_rects.size() == 4,
		"The vertical I should produce four staged cell rects.",
		failures
	)
	var first_column_x: float = staged_rects[0].position.x
	_expect(
		staged_rects.all(func(rect: Rect2) -> bool: return is_equal_approx(rect.position.x, first_column_x)),
		"The vertical I should preserve exact horizontal board-column alignment.",
		failures
	)
	var top_staged_rect: Rect2 = staged_rects[0]
	var bottom_staged_rect: Rect2 = staged_rects[-1]
	var overflow_top := drop_zone_rect.position.y - top_staged_rect.position.y
	var overflow_bottom := bottom_staged_rect.end.y - drop_zone_rect.end.y
	_expect(
		absf(overflow_top - overflow_bottom) <= 1.5,
		"The vertical I should have balanced overflow within a small rounding tolerance (top=%.1f bottom=%.1f)." % [overflow_top, overflow_bottom],
		failures
	)
	var preview_panel_y: float = main.hud.get_node("%PreviewPanel").position.y
	main.current_piece = OPiece
	main.current_anchor = Vector2i(2, 0)
	main.current_rotation = 0
	main._refresh_board_view()
	var short_piece_rects: Array[Rect2] = []
	for cell in main._current_cells():
		short_piece_rects.append(main.board_view.get_staged_cell_rect(board_rect, cell, main._current_cells()))
	_expect(
		short_piece_rects.all(func(rect: Rect2) -> bool: return rect.end.y <= drop_zone_rect.end.y + 0.5),
		"Short pieces should stay fully contained in the compact staging zone.",
		failures
	)
	_expect(
		is_equal_approx(preview_panel_y, main.hud.get_node("%PreviewPanel").position.y),
		"The staging panel should remain fixed while the piece is staged.",
		failures
	)
	main.current_piece = IVerticalPiece
	main.current_anchor = Vector2i(3, 0)
	main.current_rotation = 0
	main._refresh_board_view()
	var initial_vertical_position: float = main.board_view.get_staged_cell_rect(board_rect, main._current_cells()[0], main._current_cells()).position.y
	main._try_move_anchor(Vector2i.LEFT)
	var after_left_position: float = main.board_view.get_staged_cell_rect(board_rect, main._current_cells()[0], main._current_cells()).position.y
	main._try_move_anchor(Vector2i.RIGHT)
	var after_right_position: float = main.board_view.get_staged_cell_rect(board_rect, main._current_cells()[0], main._current_cells()).position.y
	_expect(
		is_equal_approx(initial_vertical_position, after_left_position) and is_equal_approx(initial_vertical_position, after_right_position),
		"Horizontal movement should not alter the staged vertical position.",
		failures
	)
	_verify_drop_zone_geometry_for_all_orientations(main, failures)

	main.start_new_game()
	main.current_piece = TUpPiece
	main.current_anchor = Vector2i(0, 0)
	main.current_rotation = 0
	main._try_rotate(1)
	_expect(main.current_rotation == 0, "Rotation input should not alter the active fixed-orientation piece.", failures)

	main.start_new_game()
	main.current_piece = IHorizontalPiece
	main.current_anchor = Vector2i(1, -2)
	main.current_rotation = 0
	main._process(10.0)
	_expect(main.current_anchor == Vector2i(1, -2), "Pieces should never descend on a timer.", failures)
	_expect(main.board_state.get_value(Vector2i(1, main.config.board_height - 1)) == 0, "Waiting should not place a piece.", failures)
	var queue_before_drop: Array[Resource] = main.next_pieces.duplicate()
	var generator_state_before_drop: int = main.piece_generator.rng.state
	main._confirm_drop()
	_expect(main.completed_turns == 0, "A turn should not complete while resolution feedback is still active.", failures)
	_expect(main.board_state.get_value(Vector2i(1, main.config.board_height - 1)) == 1, "Drop confirmation should settle at the floor.", failures)
	_expect(main.board_view.is_resolution_feedback_active(), "Drop should begin a sequenced resolution presentation.", failures)
	_expect(main.board_view._resolution_from == [Vector2i(1, -2), Vector2i(2, -2), Vector2i(3, -2), Vector2i(4, -2)], "Rigid-drop animation should start from the displayed drop-zone position.", failures)
	var hidden_piece_anchor: Vector2i = main.current_anchor
	var piece_before_resolution: Resource = main.current_piece
	main._try_move_anchor(Vector2i.LEFT)
	_expect(main.current_anchor == hidden_piece_anchor, "The hidden next piece must not accept input during resolution feedback.", failures)
	_expect(main.current_piece == piece_before_resolution, "The next piece should not activate before resolution feedback finishes.", failures)
	await create_timer(1.6).timeout
	_expect(not main.board_view.is_resolution_feedback_active(), "Resolution presentation should finish before the next turn accepts input.", failures)
	_expect(main.current_piece != null, "A next piece should be active after resolution feedback finishes.", failures)
	_expect(main.hud.get_multiplier_bar_state() != "resolving", "The multiplier bar should leave resolving state only after the turn finishes.", failures)
	_expect(main.completed_turns == 1, "A fully resolved placed piece should advance completed turns exactly once.", failures)
	_expect(main.run_statistics.highest_produced_tile >= 4, "Run statistics should record the highest stable tile.", failures)
	main._on_undo_pressed()
	_expect(main.completed_turns == 0, "Undo should restore the completed-turn snapshot.", failures)
	_expect(main.next_pieces == queue_before_drop, "Undo should restore the exact preview queue.", failures)
	_expect(main.piece_generator.rng.state == generator_state_before_drop, "Undo should restore generator RNG state.", failures)

	main.start_new_game()
	main.completed_turns = 15
	main.current_piece = null
	main.next_pieces.clear()
	main._fill_preview_queue(15)
	main._draw_next_piece()
	var boundary_preview: Resource = main.next_pieces[0]
	_expect(main.current_piece.generation_turn == 15, "Turn 15 should activate a first-phase piece.", failures)
	_expect(boundary_preview.generation_turn == 16, "The first preview at turn 15 should already use turn 16 progression.", failures)
	main.completed_turns = 16
	main._draw_next_piece()
	_expect(main.current_piece == boundary_preview, "The phase-boundary preview must be the exact piece that becomes active.", failures)
	_expect(
		main.current_piece.cell_values.all(func(rank: int) -> bool: return [1, 2, 3].has(rank)),
		"Turn 16 queue handoff should use only second-phase ranks.",
		failures
	)

	main.start_new_game()
	main.current_piece = IHorizontalPiece
	main.current_anchor = Vector2i(1, 0)
	main.current_rotation = 0
	var restart_button: Button = main.hud.get_node("%RestartButton")
	var starting_piece: Resource = main.current_piece
	var starting_anchor: Vector2i = main.current_anchor
	var starting_move_count: int = main.move_count
	restart_button.pressed.emit()
	_expect(main.current_piece == starting_piece and main.current_anchor == starting_anchor and main.move_count == starting_move_count, "A normal New Run click should not restart the active run.", failures)
	main.hud._begin_new_run_hold()
	main.hud._update_new_run_hold(0.25)
	_expect(main.hud.is_new_run_hold_active(), "Short New Run hold should remain cancellable.", failures)
	_expect(main.hud.get_new_run_hold_progress() > 0.0, "New Run hold progress should increase while held.", failures)
	main.hud._cancel_new_run_hold()
	_expect(main.current_piece == starting_piece and main.current_anchor == starting_anchor and main.move_count == starting_move_count, "Releasing New Run early should keep the current run unchanged.", failures)
	_expect(main.hud.get_new_run_hold_progress() == 0.0, "New Run hold progress should reset after cancellation.", failures)
	for _click_index in 5:
		main.hud._begin_new_run_hold()
		main.hud._update_new_run_hold(0.05)
		main.hud._cancel_new_run_hold()
	_expect(main.current_piece == starting_piece and main.current_anchor == starting_anchor and main.move_count == starting_move_count, "Rapid short New Run presses should not restart.", failures)
	main.hud._begin_new_run_hold()
	main.hud._update_new_run_hold(0.2)
	restart_button.mouse_exited.emit()
	_expect(not main.hud.is_new_run_hold_active() and main.hud.get_new_run_hold_progress() == 0.0, "Leaving the New Run button should cancel an active hold safely.", failures)
	main.hud._begin_new_run_hold()
	main.start_new_game()
	_expect(not main.hud.is_new_run_hold_active() and main.hud.get_new_run_hold_progress() == 0.0, "Starting a new game should clear any active New Run hold.", failures)
	main.current_piece = IHorizontalPiece
	main.current_anchor = Vector2i(1, 0)
	main.current_rotation = 0
	main._confirm_drop()
	_expect(main.board_state.get_value(Vector2i(1, main.config.board_height - 1)) == 1, "Drop input should remain available after restart protection changes.", failures)

	main.start_new_game()
	main.current_piece = IHorizontalPiece
	main.current_anchor = Vector2i(1, 0)
	main.current_rotation = 0
	main._try_move_anchor(Vector2i.LEFT)
	_expect(main.current_anchor == Vector2i(0, 0), "Left input should remain available.", failures)
	main._try_move_anchor(Vector2i.RIGHT)
	_expect(main.current_anchor == Vector2i(1, 0), "Right input should remain available.", failures)
	main.current_anchor = Vector2i(-1, 0)
	main._refresh_merge_preview()
	main._confirm_drop()
	_expect(main.completed_turns == 0, "Preview work and a failed drop should not advance completed turns.", failures)
	main.current_anchor = Vector2i(0, 0)
	main._try_move_anchor(Vector2i.LEFT)
	_expect(
		main.gameplay_audio.input_player.stream.resource_path.ends_with("UI_Button_Disable.wav"),
		"Blocked movement should use the disabled-input cue.",
		failures
	)

	main.start_new_game()
	main.current_piece = IHorizontalPiece
	main.current_anchor = Vector2i(1, 0)
	main.current_rotation = 0
	main._try_move_anchor(Vector2i.LEFT)
	var pre_restart_anchor: Vector2i = main.current_anchor
	main.run_statistics.completed_turns = 12
	main.run_statistics.total_merges = 7
	main.run_statistics.total_merge_waves = 4
	main.run_statistics.longest_merge_chain = 3
	main.run_statistics.highest_multiplier = 3
	main.hud._begin_new_run_hold()
	main.hud._update_new_run_hold(1.0)
	var post_restart_anchor: Vector2i = main.current_anchor
	_expect(pre_restart_anchor != post_restart_anchor or main.move_count == 0, "Completed New Run hold should run the existing reset behavior.", failures)
	_expect(main.hud.get_new_run_hold_progress() == 0.0, "New Run hold progress should reset after successful restart.", failures)
	_expect(main.completed_turns == 0 and main.current_piece.generation_turn == 0, "Completed New Run hold should reset progression to turn zero.", failures)
	_expect(
		main.run_statistics.total_merges == 0
		and main.run_statistics.total_merge_waves == 0
		and main.run_statistics.longest_merge_chain == 0
		and main.run_statistics.highest_multiplier == 1,
		"Starting a new run should reset lightweight run statistics.",
		failures
	)
	main.current_anchor = Vector2i(3, 0)
	main.hud._update_new_run_hold(2.0)
	_expect(main.current_anchor == Vector2i(3, 0), "Continuing to hold after completion should not trigger additional restarts.", failures)

	main.start_new_game()
	main.current_piece = IHorizontalPiece
	main.current_anchor = Vector2i(2, 0)
	main.current_rotation = 0
	main.board_state.set_value(Vector2i(4, main.config.board_height - 1), 1)
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
	_expect(main.completed_turns == 0, "A resolving turn should remain incomplete until all resolution feedback finishes.", failures)
	_expect(main.hud.get_multiplier_bar_state() == "resolving", "Drop should clear staged preview and begin resolution feedback.", failures)
	_expect(main.board_state.get_value(Vector2i(3, main.config.board_height - 1)) == 3, "A falling tetromino cell should be able to remerge in the same resolution cycle when fatigue is disabled.", failures)
	await create_timer(2.8).timeout
	_expect(resolution_events.find("rigid_landing") < resolution_events.find("merge_wave"), "Rigid landing should animate before the merge wave.", failures)
	_expect(not shown_multipliers.is_empty() and shown_multipliers[0] == 1, "The first merge event should display authoritative multiplier x1.", failures)
	_expect(main.score > 0, "Score presentation should advance from the authoritative merge-wave score.", failures)
	_expect(main.completed_turns == 1, "A restored same-turn merge sequence should still count as exactly one completed turn.", failures)
	_expect(
		main.run_statistics.total_merges >= 1
		and main.run_statistics.total_merge_waves >= 1
		and main.run_statistics.longest_merge_chain >= 1
		and main.run_statistics.highest_multiplier >= 1,
		"Run statistics should summarize restored merge counts, waves, chains, and multipliers.",
		failures
	)

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
	main.current_piece = OPiece
	main.current_anchor = Vector2i(2, 0)
	main.current_rotation = 0
	main.board_state.set_value(Vector2i(2, main.config.board_height - 2), 3)
	main._refresh_board_view()
	var landing_cells: Array[Vector2i] = main.board_view._landing_cells()
	_expect(landing_cells == [Vector2i(2, main.config.board_height - 4), Vector2i(3, main.config.board_height - 4), Vector2i(2, main.config.board_height - 3), Vector2i(3, main.config.board_height - 3)], "Ghost should stop at the authoritative rigid landing cells.", failures)
	_expect(landing_cells[0].y >= 0 and landing_cells[0].y < main.config.board_height, "Ghost cells should remain inside the actual board.", failures)

	main.start_new_game()
	main.completed_turns = 181
	for y in main.config.board_height:
		for x in main.config.board_width:
			main.board_state.set_value(Vector2i(x, y), 10 + y * main.config.board_width + x)
	main.current_piece = null
	main.next_pieces.clear()
	main._fill_preview_queue(181)
	main._draw_next_piece()
	_expect(main.game_over, "A blocked entrance should preserve existing game-over behavior.", failures)
	_expect(main.completed_turns == 181 and main.run_statistics.game_over_turn == 181, "Game over should record but not advance the completed turn.", failures)
	main._confirm_drop()
	_expect(main.completed_turns == 181 and main.run_statistics.game_over_turn == 181, "Game-over drop attempts should not advance progression.", failures)

	for failure in failures:
		push_error(failure)
	main.set_process(false)
	main.hud.set_process(false)
	main.board_view.cancel_resolution_feedback()
	main.current_piece = null
	main.next_pieces.clear()
	main.previous_piece = null
	main.previous_next_pieces.clear()
	main.config = null
	root.remove_child(main)
	main.queue_free()
	main = null
	scene = null
	for _frame in 6:
		await process_frame
	if failures.is_empty():
		print("Gameplay integration tests passed.")
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _verify_drop_zone_geometry_for_all_orientations(main, failures: PackedStringArray) -> void:
	var original_slot: Rect2 = main.hud.get_board_layout_rect()
	var viewport_slots: Array[Vector2] = [
		Vector2(360, 560),
		Vector2(375, 570),
		Vector2(390, 590),
		Vector2(412, 620),
		Vector2(430, 640),
		Vector2(720, 760)
	]
	for slot_size in viewport_slots:
		main.board_view.set_layout_rect(Rect2(Vector2.ZERO, slot_size))
		for piece in main.config.piece_definitions:
			main.start_new_game()
			main.current_piece = piece
			_expect(main._find_legal_staging_position(), "%s should find a legal staged spawn." % piece.display_name, failures)
			main._refresh_board_view()
			var board_rect: Rect2 = main.board_view.get_board_rect()
			var drop_zone_rect: Rect2 = main.board_view.get_drop_zone_rect(board_rect)
			var staged_cells: Array[Vector2i] = main._current_cells()
			var visual_bounds := _staged_visual_bounds(main, board_rect, staged_cells)
			var top_margin := visual_bounds.position.y - drop_zone_rect.position.y
			var bottom_margin := drop_zone_rect.end.y - visual_bounds.end.y
			_expect(drop_zone_rect.size.x == board_rect.size.x, "Drop zone should match board width at %s." % slot_size, failures)
			_expect(_rect_is_integer(board_rect), "Board rect should be pixel-aligned at %s." % slot_size, failures)
			_expect(_rect_is_integer(drop_zone_rect), "Drop zone rect should be pixel-aligned at %s." % slot_size, failures)
			# Tall pieces (I-vertical, 4 cells) may overflow a 3-row drop zone.
			# When they overflow, overflow must be balanced top and bottom.
			var fits_vertically := visual_bounds.position.y >= drop_zone_rect.position.y - 0.5 and visual_bounds.end.y <= drop_zone_rect.end.y + 0.5
			if fits_vertically:
				pass
			else:
				_expect(
					absf(top_margin - bottom_margin) <= 1.5,
					"%s should have balanced overflow at %s (top=%.1f bottom=%.1f)." % [piece.display_name, slot_size, top_margin, bottom_margin],
					failures
				)
			_expect(
				absf(top_margin - bottom_margin) <= 1.5,
				"%s should be vertically centered by occupied bounds at %s." % [piece.display_name, slot_size],
				failures
			)
	main.board_view.set_layout_rect(original_slot)


func _staged_visual_bounds(main, board_rect: Rect2, staged_cells: Array[Vector2i]) -> Rect2:
	var first_rect: Rect2 = main.board_view.get_staged_cell_rect(board_rect, staged_cells[0], staged_cells)
	var min_x := first_rect.position.x
	var min_y := first_rect.position.y
	var max_x := first_rect.end.x
	var max_y := first_rect.end.y
	for cell in staged_cells:
		var rect: Rect2 = main.board_view.get_staged_cell_rect(board_rect, cell, staged_cells)
		min_x = minf(min_x, rect.position.x)
		min_y = minf(min_y, rect.position.y)
		max_x = maxf(max_x, rect.end.x)
		max_y = maxf(max_y, rect.end.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


func _rect_is_integer(rect: Rect2) -> bool:
	return (
		is_equal_approx(rect.position.x, roundf(rect.position.x))
		and is_equal_approx(rect.position.y, roundf(rect.position.y))
		and is_equal_approx(rect.size.x, roundf(rect.size.x))
		and is_equal_approx(rect.size.y, roundf(rect.size.y))
	)
