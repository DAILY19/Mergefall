@tool
extends Control

const SAVE_PATH := "user://mergefall.save"
const BoardStateScript = preload("res://scripts/core/board_state.gd")
const PieceGeneratorScript = preload("res://scripts/core/piece_generator.gd")
const RunStatisticsScript = preload("res://scripts/core/run_statistics.gd")
const SaveDataScript = preload("res://scripts/core/save_data.gd")
const SaveDataStoreScript = preload("res://scripts/core/save_data_store.gd")
const GameplayAudioScript = preload("res://scripts/audio/gameplay_audio.gd")

@export var config: Resource

@onready var board_view: Control = %BoardView
@onready var hud: Control = %GameHUD

var board_state = BoardStateScript.new()
var piece_generator = PieceGeneratorScript.new()
var run_statistics = RunStatisticsScript.new()
var save_store = SaveDataStoreScript.new(SAVE_PATH)
var gameplay_audio
var current_piece: Resource
var next_pieces: Array[Resource] = []
var current_anchor := Vector2i.ZERO
var current_rotation := 0
var score := 0
var best_score := 0
var game_over := false
var completed_turns: int:
	get:
		return run_statistics.completed_turns
	set(value):
		run_statistics.completed_turns = value
var move_count: int:
	get:
		return completed_turns
	set(value):
		completed_turns = value

var previous_board
var previous_score := 0
var previous_run_statistics
var previous_piece: Resource
var previous_next_pieces: Array[Resource] = []
var previous_generator_state := 0
var previous_anchor := Vector2i.ZERO
var previous_rotation := 0
var can_undo := false
var blocked_feedback_until_msec := 0
var merge_feedback_steps: Array[Dictionary] = []
var merge_feedback_until_msec := 0
var spawn_feedback_until_msec := 0
var lock_feedback_cells: Array[Vector2i] = []
var lock_feedback_until_msec := 0
var was_blocked_feedback_active := false
var was_merge_feedback_active := false
var was_motion_feedback_active := false
var resolution_sequence_id := 0
var resolution_score_target := 0
var debug_metrics_enabled := false
var debug_process_frame_count := 0
var mobile_web_dpr_status := {"applied": false, "reason": "runtime_canvas_resize_disabled"}
var _transition_trace_enabled := false
var _transition_trace_id := 0


func _ready() -> void:
	if Engine.is_editor_hint():
		update_configuration_warnings()
		return
	hud.bind_actions(
		_on_move_left_pressed,
		_on_move_right_pressed,
		_on_drop_pressed,
		_on_undo_pressed,
		_on_restart_pressed
	)
	board_view.resolution_event_started.connect(_on_resolution_event_started)
	gameplay_audio = GameplayAudioScript.new()
	gameplay_audio.name = "GameplayAudio"
	add_child(gameplay_audio)
	resized.connect(_on_viewport_resized)
	set_process(false)
	_load_save_data()
	if config == null:
		push_error("Main scene requires a GameConfig resource.")
		hud.clear_preview()
		return
	var issues: PackedStringArray = config.validate()
	if not issues.is_empty():
		push_error("Invalid GameConfig: %s" % ", ".join(issues))
		hud.clear_preview()
		return
	board_view.config = config
	debug_metrics_enabled = bool(config.get("render_diagnostics_enabled")) if config != null else false
	board_view.set_diagnostics_enabled(debug_metrics_enabled)
	_transition_trace_enabled = debug_metrics_enabled
	start_new_game()


func start_new_game() -> void:
	if config == null:
		return
	if hud != null and hud.has_method("_reset_new_run_hold_visuals"):
		hud._reset_new_run_hold_visuals()
	resolution_sequence_id += 1
	board_view.cancel_resolution_feedback()
	board_state.setup(config.board_width, config.board_height)
	run_statistics.reset()
	score = 0
	resolution_score_target = 0
	game_over = false
	can_undo = false
	current_piece = null
	previous_board = null
	previous_run_statistics = null
	previous_piece = null
	previous_next_pieces.clear()
	merge_feedback_steps.clear()
	merge_feedback_until_msec = 0
	lock_feedback_cells.clear()
	lock_feedback_until_msec = 0
	next_pieces.clear()
	_fill_preview_queue(completed_turns)
	_draw_next_piece()
	_refresh_presentation()


func _fill_preview_queue(first_effective_turn: int) -> void:
	while next_pieces.size() < config.preview_piece_count:
		var effective_turn := first_effective_turn + next_pieces.size()
		var piece = piece_generator.next_piece(
			config.piece_definitions,
			config.spawn_progression,
			effective_turn
		)
		if piece == null:
			break
		next_pieces.append(piece)


func _draw_next_piece() -> void:
	hud.reset_multiplier_bar()
	if next_pieces.is_empty():
		_fill_preview_queue(completed_turns)
	current_piece = next_pieces.pop_front() if not next_pieces.is_empty() else null
	_fill_preview_queue(completed_turns + 1)
	current_rotation = 0
	blocked_feedback_until_msec = 0
	if current_piece == null:
		_mark_game_over()
		return
	if not _find_legal_staging_position():
		_mark_game_over()
		return
	spawn_feedback_until_msec = Time.get_ticks_msec() + 240
	_update_process_activity()


func _on_restart_pressed() -> void:
	start_new_game()


func _on_move_left_pressed() -> void:
	_try_move_anchor(Vector2i.LEFT)


func _on_move_right_pressed() -> void:
	_try_move_anchor(Vector2i.RIGHT)


func _on_drop_pressed() -> void:
	_confirm_drop()


func _on_undo_pressed() -> void:
	if board_view.is_resolution_feedback_active():
		return
	if not can_undo or previous_board == null:
		_show_blocked_feedback()
		_refresh_presentation()
		return
	board_state = previous_board.duplicate_state()
	score = previous_score
	run_statistics = previous_run_statistics.duplicate_state()
	current_piece = previous_piece
	next_pieces = previous_next_pieces.duplicate()
	piece_generator.rng.state = previous_generator_state
	current_anchor = previous_anchor
	current_rotation = previous_rotation
	game_over = false
	can_undo = false
	merge_feedback_steps.clear()
	merge_feedback_until_msec = 0
	lock_feedback_cells.clear()
	lock_feedback_until_msec = 0
	hud.reset_multiplier_bar()
	_refresh_presentation()
	hud.show_toast("UNDO")


func _unhandled_input(event: InputEvent) -> void:
	if config == null or game_over:
		if event.is_action_pressed("ui_accept"):
			start_new_game()
		return

	if event.is_action_pressed("ui_left"):
		_try_move_anchor(Vector2i.LEFT)
	elif event.is_action_pressed("ui_right"):
		_try_move_anchor(Vector2i.RIGHT)
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_down"):
		_confirm_drop()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				start_new_game()


func _process(_delta: float) -> void:
	if debug_metrics_enabled:
		debug_process_frame_count += 1
		board_view.diagnostics.increment("process_callbacks")
		board_view.diagnostics.sample("active_tween_samples", board_view.is_resolution_feedback_active())
	var blocked_active := _is_blocked_feedback_active()
	var merge_active := _is_merge_feedback_active()
	var motion_feedback_active := (
		_spawn_feedback_ratio() > 0.0
		or _lock_feedback_ratio() > 0.0
	)
	if motion_feedback_active or motion_feedback_active != was_motion_feedback_active:
		_refresh_board_view()
	elif blocked_active or merge_active:
		_refresh_board_feedback_only()
	if blocked_active != was_blocked_feedback_active:
		_refresh_hud_only()
	if not merge_active and was_merge_feedback_active:
		merge_feedback_steps.clear()
		_refresh_board_feedback_only()
	was_blocked_feedback_active = blocked_active
	was_merge_feedback_active = merge_active
	was_motion_feedback_active = motion_feedback_active
	_update_process_activity()


func _try_move_anchor(offset: Vector2i) -> void:
	if board_view.is_resolution_feedback_active():
		return
	var candidate := current_anchor + offset
	if _can_piece_fit(candidate, current_rotation):
		current_anchor = candidate
		board_view.play_move_feedback(offset)
		gameplay_audio.play_move(offset.x)
		_refresh_presentation()
	else:
		_show_blocked_feedback()
		_refresh_presentation()


func _confirm_drop() -> void:
	if current_piece == null or game_over or board_view.is_resolution_feedback_active():
		return
	_transition_trace_id += 1
	_capture_transition_checkpoint("before_piece_locks")
	var from_cells := _current_cells()
	var values: Array = current_piece.get_rotated_values(current_rotation)
	var projection: Dictionary = board_state.project_settlement(from_cells, values, config.merge_fatigue_enabled)
	if not projection.get("legal", false):
		_show_blocked_feedback()
		_refresh_presentation()
		return
	var landing_cells := _typed_vector2i_array(projection.get("landing_cells", []))
	var max_drop_distance := 0
	for index in mini(from_cells.size(), landing_cells.size()):
		max_drop_distance = maxi(max_drop_distance, landing_cells[index].y - from_cells[index].y)
	gameplay_audio.play_drop(max_drop_distance)
	_lock_current_piece(from_cells, values)


func _try_rotate(direction: int) -> void:
	@warning_ignore("unused_parameter")
	var _ignored_direction := direction
	_show_blocked_feedback()
	_refresh_presentation()


func _lock_current_piece(placement_cells: Array[Vector2i] = _current_cells(), placement_values: Array = []) -> void:
	if placement_values.is_empty() and current_piece != null:
		placement_values = current_piece.get_rotated_values(current_rotation)
	if not board_state.can_settle(placement_cells, placement_values, config.merge_fatigue_enabled):
		_show_blocked_feedback()
		_refresh_presentation()
		return

	previous_board = board_state.duplicate_state()
	previous_score = score
	previous_run_statistics = run_statistics.duplicate_state()
	previous_piece = current_piece
	previous_next_pieces = next_pieces.duplicate()
	previous_generator_state = piece_generator.rng.state
	previous_anchor = current_anchor
	previous_rotation = current_rotation
	can_undo = true

	var settlement: Dictionary = board_state.settle_cells(
		placement_cells,
		placement_values,
		config.score_per_rank,
		config.merge_fatigue_enabled
	)
	_capture_transition_checkpoint("after_active_piece_removed")
	_capture_resolution_events(settlement)
	var earned_score: int = int(settlement["score"])
	resolution_score_target = score + earned_score
	hud.begin_turn_resolution()
	resolution_sequence_id += 1
	var sequence_id := resolution_sequence_id
	board_view.play_resolution_feedback(previous_board, placement_cells, placement_values, settlement)
	_capture_transition_checkpoint("resolution_feedback_begins")
	_show_lock_feedback(settlement["landing_cells"])
	board_view.resolution_feedback_finished.connect(func() -> void:
		if sequence_id != resolution_sequence_id:
			return
		_capture_transition_checkpoint("resolution_feedback_ends")
		score = resolution_score_target
		best_score = maxi(best_score, score)
		_save_progress()
		hud.complete_turn_resolution()
		run_statistics.record_completed_turn(settlement, board_state)
		if board_state.has_stable_overflow():
			_mark_game_over()
		else:
			_draw_next_piece()
		if game_over:
			hud.show_toast("BOARD JAMMED")
		_capture_transition_checkpoint("before_returning_to_idle")
		_refresh_presentation()
		_capture_idle_frames()
	, CONNECT_ONE_SHOT)
	_refresh_presentation()


func _mark_game_over() -> void:
	game_over = true
	run_statistics.mark_game_over()
	if gameplay_audio != null:
		gameplay_audio.play_game_over()


func _on_resolution_event_started(event: Dictionary) -> void:
	match event.get("type", ""):
		"rigid_landing":
			gameplay_audio.play_land()
		"merge_wave":
			var event_score: int = int(event.get("score", 0))
			score = mini(resolution_score_target, score + event_score)
			best_score = maxi(best_score, score)
			var multiplier: int = int(event.get("multiplier", event.get("wave", 1)))
			hud.show_merge_wave(multiplier, minf(float(multiplier) / 4.0, 1.0))
			gameplay_audio.play_merge(event.get("steps", []).size())
			_refresh_hud_only()


func _refresh_presentation() -> void:
	_refresh_hud_only()
	_refresh_board_view()


func _on_viewport_resized() -> void:
	_refresh_presentation()


func _refresh_board_view() -> void:
	board_view.set_layout_rect(hud.get_board_layout_rect())
	if hud.has_method("set_gameplay_rects"):
		var board_rect: Rect2 = board_view.get_board_rect()
		hud.set_gameplay_rects(board_rect, board_view.get_drop_zone_rect(board_rect))
	board_view.set_board_state(board_state)
	board_view.set_active_piece(
		current_piece,
		current_anchor,
		current_rotation,
		game_over,
		_spawn_feedback_ratio()
	)
	_refresh_board_feedback_only()


func _refresh_board_feedback_only() -> void:
	board_view.set_feedback(
		_is_blocked_feedback_active(),
		merge_feedback_steps,
		_merge_feedback_ratio(),
		lock_feedback_cells,
		_lock_feedback_ratio()
	)


func _refresh_hud_only() -> void:
	hud.set_preview_pieces(next_pieces, config.preview_piece_count)
	hud.update_status({
		"score": score,
		"best_score": best_score,
		"move_count": move_count,
		"target_text": "Drop fixed pieces. Equal neighbors merge in deterministic waves.",
		"subtitle_text": _subtitle_text(),
		"current_piece_text": _current_piece_text(),
		"can_undo": can_undo,
		"movement_disabled": current_piece == null or game_over or board_view.is_resolution_feedback_active()
	})
	_refresh_merge_preview()


func _capture_resolution_events(settlement: Dictionary) -> void:
	if not _transition_trace_enabled:
		return
	var gravity_index := 0
	var merge_index := 0
	for event in settlement.get("events", []):
		match event.get("type", ""):
			"gravity_step":
				gravity_index += 1
				_capture_transition_checkpoint("after_gravity_pass_%d" % gravity_index)
			"merge_wave":
				merge_index += 1
				_capture_transition_checkpoint("after_merge_pass_%d" % merge_index)


func _capture_idle_frames() -> void:
	if not _transition_trace_enabled:
		return
	await get_tree().process_frame
	_capture_transition_checkpoint("one_frame_after_idle")
	await get_tree().process_frame
	_capture_transition_checkpoint("two_frames_after_idle")


func _capture_transition_checkpoint(label: String) -> void:
	if not _transition_trace_enabled:
		return
	var board_rect := board_view.get_board_rect()
	var drop_rect := board_view.get_drop_zone_rect(board_rect)
	var viewport_rect := get_viewport().get_visible_rect()
	var snapshot := {
		"trace": _transition_trace_id,
		"checkpoint": label,
		"root_global_position": global_position,
		"root_size": size,
		"board_global_position": board_rect.position,
		"board_size": board_rect.size,
		"board_scale": board_view.scale,
		"drop_zone_global_position": drop_rect.position,
		"drop_zone_size": drop_rect.size,
		"viewport_visible_rect": viewport_rect,
		"canvas": _browser_canvas_report(),
		"active_piece_exists": current_piece != null,
		"active_piece_position": current_anchor,
		"preview_piece_exists": not next_pieces.is_empty(),
		"preview_piece_position": Vector2.ZERO,
		"gameplay_state": _gameplay_state_name(),
		"process_enabled": is_processing(),
		"active_tween_count": _active_tween_count(),
		"redraw_count": board_view.diagnostics_report().get("redraw_requests", 0)
	}
	print("[MergefallTransition] ", JSON.stringify(snapshot))


func _browser_canvas_report() -> Dictionary:
	if OS.get_name() != "Web" or not Engine.has_singleton("JavaScriptBridge"):
		return {
			"width": 0,
			"height": 0,
			"effective_dpr": mobile_web_dpr_status.get("effective_dpr", 1.0),
			"inner_width": 0,
			"inner_height": 0
		}
	var bridge = Engine.get_singleton("JavaScriptBridge")
	var response = bridge.eval("""
	(function() {
		const canvas = document.querySelector('canvas');
		return JSON.stringify({
			width: canvas ? canvas.width : 0,
			height: canvas ? canvas.height : 0,
			effective_dpr: window.__mergefallDprCap ? window.__mergefallDprCap.cap : (window.devicePixelRatio || 1),
			inner_width: window.innerWidth || 0,
			inner_height: window.innerHeight || 0
		});
	})();
	""", true)
	var parsed = JSON.parse_string(str(response))
	return parsed if parsed is Dictionary else {}


func _gameplay_state_name() -> String:
	if game_over:
		return "game_over"
	if board_view.is_resolution_feedback_active():
		return "resolving"
	if current_piece == null:
		return "no_active_piece"
	if _spawn_feedback_ratio() > 0.0:
		return "spawning"
	if _lock_feedback_ratio() > 0.0:
		return "lock_feedback"
	if _is_merge_feedback_active():
		return "merge_feedback"
	if _is_blocked_feedback_active():
		return "blocked_feedback"
	return "idle"


func _active_tween_count() -> int:
	var count := 0
	if board_view.get("_motion_tween") != null and board_view.get("_motion_tween").is_valid():
		count += 1
	if board_view.get("_resolution_tween") != null and board_view.get("_resolution_tween").is_valid():
		count += 1
	if hud.get("_bar_tween") != null and hud.get("_bar_tween").is_valid():
		count += 1
	var preview = hud.get_preview_strip()
	if preview != null and preview.get("_queue_tween") != null and preview.get("_queue_tween").is_valid():
		count += 1
	return count


func _subtitle_text() -> String:
	if game_over:
		return "No legal drop remains. Start a fresh run."
	if current_piece != null:
		return "Position %s, then drop it into place." % current_piece.display_name
	return ""


func _current_piece_text() -> String:
	if current_piece == null:
		return "Current Form: --"
	return "Current Form: %s" % current_piece.display_name


func _refresh_merge_preview() -> void:
	if current_piece == null or game_over or board_view.is_resolution_feedback_active():
		return
	var projection: Dictionary = board_state.project_settlement(
		_current_cells(),
		current_piece.get_rotated_values(current_rotation),
		config.merge_fatigue_enabled
	)
	hud.set_merge_preview(
		projection.get("legal", false)
		and projection.get("has_first_wave_merge", false)
	)


func _current_cells() -> Array[Vector2i]:
	if current_piece == null:
		return []
	var translated: Array[Vector2i] = []
	for cell in current_piece.get_rotated_cells(current_rotation):
		translated.append(cell + current_anchor)
	return translated


func _can_piece_fit(anchor: Vector2i, rot: int) -> bool:
	if current_piece == null:
		return false
	var translated: Array[Vector2i] = []
	for cell in current_piece.get_rotated_cells(rot):
		translated.append(cell + anchor)
	return board_state.can_stage(translated)


func _find_legal_staging_position() -> bool:
	if current_piece == null:
		return false
	var rotation_count: int = 1
	for rotation_index in rotation_count:
		var rotated: Array[Vector2i] = current_piece.get_rotated_cells(rotation_index)
		var bounds: Rect2i = _piece_bounds(rotated)
		# Stage forms above the board entrance while preserving the same landing columns.
		var stage_y: int = -bounds.position.y - bounds.size.y - 1
		var min_anchor_x: int = -bounds.position.x
		var max_anchor_x: int = int(config.board_width) - bounds.position.x - bounds.size.x
		var centered_x: int = clampi(
			int((config.board_width - bounds.size.x) / 2) - bounds.position.x,
			min_anchor_x,
			max_anchor_x
		)
		var candidates: Array[int] = [centered_x]
		for distance in config.board_width:
			for direction in [-1, 1]:
				var candidate_x: int = centered_x + distance * direction
				if candidate_x >= min_anchor_x and candidate_x <= max_anchor_x and not candidates.has(candidate_x):
					candidates.append(candidate_x)
		for candidate_x in candidates:
			var anchor := Vector2i(candidate_x, stage_y)
			var staged_cells: Array[Vector2i] = []
			for cell in rotated:
				staged_cells.append(cell + anchor)
			var values: Array = current_piece.get_rotated_values(rotation_index)
			var projection: Dictionary = board_state.project_settlement(staged_cells, values)
			if projection.get("legal", false) and not projection.get("has_stable_overflow", false):
				current_rotation = rotation_index
				current_anchor = anchor
				return true
	return false


func _piece_bounds(cells: Array) -> Rect2i:
	var min_x: int = cells[0].x
	var min_y: int = cells[0].y
	var max_x: int = cells[0].x
	var max_y: int = cells[0].y
	for cell in cells:
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _show_blocked_feedback() -> void:
	blocked_feedback_until_msec = Time.get_ticks_msec() + 700
	if gameplay_audio != null:
		gameplay_audio.play_blocked()
	_update_process_activity()


func _is_blocked_feedback_active() -> bool:
	return Time.get_ticks_msec() < blocked_feedback_until_msec


func _is_merge_feedback_active() -> bool:
	return Time.get_ticks_msec() < merge_feedback_until_msec and not merge_feedback_steps.is_empty()


func _merge_feedback_ratio() -> float:
	if not _is_merge_feedback_active():
		return 0.0
	return clampf(
		float(merge_feedback_until_msec - Time.get_ticks_msec()) / maxf(1.0, config.merge_flash_duration_sec * 1000.0),
		0.0,
		1.0
	)


func _spawn_feedback_ratio() -> float:
	return clampf(
		float(spawn_feedback_until_msec - Time.get_ticks_msec()) / 240.0,
		0.0,
		1.0
	)


func _show_lock_feedback(cells: Array[Vector2i]) -> void:
	lock_feedback_cells = _typed_vector2i_array(cells)
	lock_feedback_until_msec = Time.get_ticks_msec() + 220
	_update_process_activity()


func _lock_feedback_ratio() -> float:
	var ratio := clampf(
		float(lock_feedback_until_msec - Time.get_ticks_msec()) / 220.0,
		0.0,
		1.0
	)
	if ratio <= 0.0 and not lock_feedback_cells.is_empty():
		lock_feedback_cells.clear()
	return ratio


func _update_process_activity() -> void:
	set_process(
		_is_blocked_feedback_active()
		or _is_merge_feedback_active()
		or _spawn_feedback_ratio() > 0.0
		or _lock_feedback_ratio() > 0.0
	)


func _save_progress() -> void:
	var data = SaveDataScript.new()
	data.best_score = best_score
	save_store.save_data(data)


func _load_save_data() -> void:
	var data = save_store.load_data()
	best_score = data.best_score


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if config == null:
		warnings.append("Assign a GameConfig resource to Main.config.")
		return warnings
	if not config.has_method("validate"):
		warnings.append("Main.config must be a GameConfig resource.")
		return warnings
	for issue in config.validate():
		warnings.append(issue)
	if config.board_width <= 0 or config.board_height <= 0:
		warnings.append("Board dimensions must be positive.")
	if config.tile_palette.is_empty():
		warnings.append("GameConfig.tile_palette should contain at least one color.")
	if config.preview_piece_count <= 0:
		warnings.append("GameConfig.preview_piece_count must be at least 1.")
	return warnings


func _typed_vector2i_array(source: Array) -> Array[Vector2i]:
	var typed: Array[Vector2i] = []
	for value in source:
		typed.append(value as Vector2i)
	return typed
