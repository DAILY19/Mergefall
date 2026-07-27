extends RefCounted

const RenderDiagnosticsScript = preload("res://scripts/core/render_diagnostics.gd")
const MobileWebDprScript = preload("res://scripts/core/mobile_web_dpr.gd")


static func run() -> PackedStringArray:
	var failures := PackedStringArray()
	_test_state_classifier(failures)
	_test_counters(failures)
	_test_mobile_web_dpr_logic(failures)
	return failures


static func _test_state_classifier(failures: PackedStringArray) -> void:
	_expect(RenderDiagnosticsScript.classify_visual_state({}) == RenderDiagnosticsScript.VisualState.STATIONARY, "Classifier should return STATIONARY for idle visuals.", failures)
	_expect(RenderDiagnosticsScript.classify_visual_state({"dropping": true}) == RenderDiagnosticsScript.VisualState.DROPPING, "Classifier should return DROPPING for rigid landing visuals.", failures)
	_expect(RenderDiagnosticsScript.classify_visual_state({"falling": true}) == RenderDiagnosticsScript.VisualState.FALLING, "Classifier should return FALLING for gravity visuals.", failures)
	_expect(RenderDiagnosticsScript.classify_visual_state({"merging": true}) == RenderDiagnosticsScript.VisualState.MERGING, "Classifier should return MERGING for merge visuals.", failures)
	_expect(RenderDiagnosticsScript.classify_visual_state({"dropping": true, "falling": true, "merging": true}) == RenderDiagnosticsScript.VisualState.MERGING, "Classifier priority should prefer MERGING over FALLING and DROPPING.", failures)
	_expect(RenderDiagnosticsScript.classify_visual_state({"dropping": true, "falling": true}) == RenderDiagnosticsScript.VisualState.FALLING, "Classifier priority should prefer FALLING over DROPPING.", failures)


static func _test_counters(failures: PackedStringArray) -> void:
	var diagnostics = RenderDiagnosticsScript.new()
	diagnostics.increment("draw_calls")
	_expect(diagnostics.report().get("draw_calls", 0) == 0, "Diagnostics should be disabled by default.", failures)
	diagnostics.begin()
	diagnostics.increment("draw_calls", 2)
	diagnostics.increment("redraw_requests")
	var report := diagnostics.report(RenderDiagnosticsScript.VisualState.DROPPING)
	_expect(report.get("state", "") == "DROPPING", "Diagnostics report should include deterministic state names.", failures)
	_expect(report.get("draw_calls", 0) == 2 and report.get("redraw_requests", 0) == 1, "Diagnostics should count enabled events.", failures)
	diagnostics.reset()
	_expect(diagnostics.report().get("draw_calls", 0) == 0, "Diagnostics reset should clear counters.", failures)


static func _test_mobile_web_dpr_logic(failures: PackedStringArray) -> void:
	var native := MobileWebDprScript.effective_dpr({
		"is_web": false,
		"touch_primary": true,
		"mobile_user_agent": true,
		"viewport": Vector2i(390, 844),
		"device_pixel_ratio": 3.0,
		"cap": 2.0
	})
	_expect(not native.get("applied", true), "Native platforms should never receive the mobile Web cap.", failures)
	var desktop_web := MobileWebDprScript.effective_dpr({
		"is_web": true,
		"touch_primary": false,
		"mobile_user_agent": false,
		"viewport": Vector2i(390, 844),
		"device_pixel_ratio": 3.0,
		"cap": 2.0
	})
	_expect(not desktop_web.get("applied", true), "Desktop Web should not be capped solely due to narrow viewport.", failures)
	var mobile := MobileWebDprScript.effective_dpr({
		"is_web": true,
		"touch_primary": true,
		"mobile_user_agent": true,
		"viewport": Vector2i(390, 844),
		"device_pixel_ratio": 3.0,
		"cap": 2.0
	})
	_expect(mobile.get("applied", false) and is_equal_approx(mobile.get("effective_dpr", 0.0), 2.0), "Mobile Web above the cap should be limited.", failures)
	var below := MobileWebDprScript.effective_dpr({
		"is_web": true,
		"touch_primary": true,
		"mobile_user_agent": true,
		"viewport": Vector2i(390, 844),
		"device_pixel_ratio": 1.5,
		"cap": 2.0
	})
	_expect(not below.get("applied", true) and is_equal_approx(below.get("effective_dpr", 0.0), 1.5), "Mobile Web below the cap should remain unchanged.", failures)
	var invalid := MobileWebDprScript.effective_dpr({
		"is_web": true,
		"touch_primary": true,
		"mobile_user_agent": true,
		"viewport": Vector2i(390, 844),
		"device_pixel_ratio": 3.0,
		"cap": 0.0
	})
	_expect(not invalid.get("applied", true) and invalid.get("reason", "") == "invalid_cap", "Invalid cap values should fall back safely without applying.", failures)
	var pixels := MobileWebDprScript.pixel_report(Vector2i(390, 844), 3.0, 2.0)
	_expect(pixels.get("effective_size", Vector2i.ZERO) == Vector2i(780, 1688), "DPR pixel report should calculate capped backing dimensions.", failures)
	_expect(absf(float(pixels.get("pixel_reduction", 0.0)) - 0.5555) < 0.01, "3.0 to 2.0 DPR should reduce pixel workload by about 55.6%.", failures)


static func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
