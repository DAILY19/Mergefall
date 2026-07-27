class_name RenderDiagnostics
extends RefCounted

enum VisualState { STATIONARY, DROPPING, FALLING, MERGING }

const STATE_NAMES := {
	VisualState.STATIONARY: "STATIONARY",
	VisualState.DROPPING: "DROPPING",
	VisualState.FALLING: "FALLING",
	VisualState.MERGING: "MERGING"
}

var enabled := false
var started_msec := 0
var last_second_msec := 0
var current_second_draws := 0
var peak_draws_per_second := 0
var counters := {}


static func classify_visual_state(flags: Dictionary) -> int:
	if bool(flags.get("merging", false)):
		return VisualState.MERGING
	if bool(flags.get("falling", false)):
		return VisualState.FALLING
	if bool(flags.get("dropping", false)):
		return VisualState.DROPPING
	return VisualState.STATIONARY


static func state_name(state: int) -> String:
	return STATE_NAMES.get(state, "STATIONARY")


func begin() -> void:
	reset()
	enabled = true


func stop() -> Dictionary:
	var report := report()
	enabled = false
	return report


func reset() -> void:
	started_msec = Time.get_ticks_msec()
	last_second_msec = started_msec
	current_second_draws = 0
	peak_draws_per_second = 0
	counters = {
		"process_callbacks": 0,
		"physics_process_callbacks": 0,
		"redraw_requests": 0,
		"draw_calls": 0,
		"board_draws": 0,
		"drop_zone_draws": 0,
		"active_piece_draws": 0,
		"ghost_draws": 0,
		"falling_cell_draws": 0,
		"merge_feedback_draws": 0,
		"active_tween_samples": 0,
		"active_timer_samples": 0,
		"layout_recalculations": 0,
		"cells_drawn": 0,
		"text_metric_cache_hits": 0,
		"text_metric_cache_misses": 0,
		"projection_calls": 0
	}


func increment(name: String, amount: int = 1) -> void:
	if not enabled:
		return
	counters[name] = int(counters.get(name, 0)) + amount
	if name == "draw_calls":
		_record_draw_second(amount)


func sample(name: String, active: bool) -> void:
	if active:
		increment(name)


func report(state: int = VisualState.STATIONARY) -> Dictionary:
	var elapsed_sec := maxf(0.001, float(Time.get_ticks_msec() - started_msec) / 1000.0)
	var snapshot := counters.duplicate()
	snapshot["state"] = state_name(state)
	snapshot["duration"] = elapsed_sec
	snapshot["average_draws_per_second"] = float(snapshot.get("draw_calls", 0)) / elapsed_sec
	snapshot["peak_draws_per_second"] = peak_draws_per_second
	return snapshot


func _record_draw_second(amount: int) -> void:
	var now := Time.get_ticks_msec()
	if now - last_second_msec >= 1000:
		peak_draws_per_second = maxi(peak_draws_per_second, current_second_draws)
		current_second_draws = 0
		last_second_msec = now
	current_second_draws += amount
	peak_draws_per_second = maxi(peak_draws_per_second, current_second_draws)
