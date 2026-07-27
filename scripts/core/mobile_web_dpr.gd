class_name MobileWebDpr
extends RefCounted

const DEFAULT_CAP := 2.0
const MIN_SAFE_CAP := 1.0


static func effective_dpr(context: Dictionary) -> Dictionary:
	var platform := str(context.get("platform", ""))
	var is_web := bool(context.get("is_web", platform == "Web"))
	var touch_primary := bool(context.get("touch_primary", false))
	var mobile_user_agent := bool(context.get("mobile_user_agent", false))
	var viewport := Vector2i(context.get("viewport", Vector2i.ZERO))
	var physical_dpr := maxf(1.0, float(context.get("device_pixel_ratio", 1.0)))
	var cap := float(context.get("cap", DEFAULT_CAP))
	var enabled := bool(context.get("enabled", true))
	var valid_cap := cap >= MIN_SAFE_CAP
	var mobile_viewport := viewport.x > 0 and viewport.y > 0 and mini(viewport.x, viewport.y) <= 520 and maxi(viewport.x, viewport.y) <= 960
	var mobile_web := is_web and touch_primary and mobile_viewport and mobile_user_agent
	var should_cap := enabled and valid_cap and mobile_web and physical_dpr > cap
	var effective := cap if should_cap else physical_dpr
	return {
		"applied": should_cap,
		"effective_dpr": effective,
		"physical_dpr": physical_dpr,
		"cap": cap if valid_cap else DEFAULT_CAP,
		"mobile_web": mobile_web,
		"reason": _reason(enabled, valid_cap, is_web, touch_primary, mobile_viewport, mobile_user_agent, physical_dpr, cap)
	}


static func pixel_report(css_size: Vector2i, physical_dpr: float, effective_dpr_value: float) -> Dictionary:
	var uncapped := Vector2i(roundi(float(css_size.x) * physical_dpr), roundi(float(css_size.y) * physical_dpr))
	var capped := Vector2i(roundi(float(css_size.x) * effective_dpr_value), roundi(float(css_size.y) * effective_dpr_value))
	var uncapped_pixels := uncapped.x * uncapped.y
	var capped_pixels := capped.x * capped.y
	var ratio := 1.0 if uncapped_pixels <= 0 else float(capped_pixels) / float(uncapped_pixels)
	return {
		"uncapped_size": uncapped,
		"effective_size": capped,
		"uncapped_pixels": uncapped_pixels,
		"effective_pixels": capped_pixels,
		"pixel_workload_ratio": ratio,
		"pixel_reduction": 1.0 - ratio
	}


static func _reason(
	enabled: bool,
	valid_cap: bool,
	is_web: bool,
	touch_primary: bool,
	mobile_viewport: bool,
	mobile_user_agent: bool,
	physical_dpr: float,
	cap: float
) -> String:
	if not enabled:
		return "disabled"
	if not valid_cap:
		return "invalid_cap"
	if not is_web:
		return "not_web"
	if not touch_primary:
		return "not_touch_primary"
	if not mobile_user_agent:
		return "not_mobile_user_agent"
	if not mobile_viewport:
		return "not_mobile_viewport"
	if physical_dpr <= cap:
		return "below_cap"
	return "capped"
