@tool
class_name SpawnProgression
extends Resource

const SpawnProgressionPhaseScript = preload("res://scripts/core/spawn_progression_phase.gd")

@export var phases: Array[Resource] = []

var _phase_cache_source: Array[Resource] = []
var _phase_cache_signature := ""
var _phase_thresholds: Array[int] = []
var _rank_by_display_value: Dictionary = {}


func phase_for_completed_turn(completed_turns: int) -> Resource:
	_rebuild_cache_if_needed()
	if phases.is_empty():
		return null
	var selected_index := 0
	for index in _phase_thresholds.size():
		if _phase_thresholds[index] > completed_turns:
			break
		selected_index = index
	return phases[selected_index]


func display_value_to_rank(displayed_value: int) -> int:
	_rebuild_cache_if_needed()
	if _rank_by_display_value.has(displayed_value):
		return int(_rank_by_display_value[displayed_value])
	return _calculate_rank(displayed_value)


func rank_to_display_value(rank: int) -> int:
	return 1 << maxi(0, rank)


func _rebuild_cache_if_needed() -> void:
	var signature := _cache_signature()
	if phases == _phase_cache_source and signature == _phase_cache_signature:
		return
	_phase_cache_source = phases.duplicate()
	_phase_cache_signature = signature
	_phase_thresholds.clear()
	_rank_by_display_value.clear()
	for phase in phases:
		if phase == null:
			continue
		_phase_thresholds.append(phase.min_completed_turns)
		for displayed_value in phase.displayed_values:
			if not _rank_by_display_value.has(displayed_value):
				_rank_by_display_value[displayed_value] = _calculate_rank(displayed_value)


func _cache_signature() -> String:
	var parts: PackedStringArray = []
	for phase in phases:
		if phase == null:
			parts.append("<null>")
		else:
			parts.append("%d:%s:%s" % [phase.min_completed_turns, phase.displayed_values, phase.weights])
	return "|".join(parts)


func _calculate_rank(displayed_value: int) -> int:
	if displayed_value < 2 or (displayed_value & (displayed_value - 1)) != 0:
		return 0
	var rank := 0
	var remaining := displayed_value
	while remaining > 1:
		remaining >>= 1
		rank += 1
	return rank


func validate() -> PackedStringArray:
	var issues := PackedStringArray()
	if phases.is_empty():
		issues.append("SpawnProgression requires at least one phase.")
		return issues
	var previous_start := -1
	for phase in phases:
		if phase == null:
			issues.append("SpawnProgression contains an empty phase.")
			continue
		if not phase is SpawnProgressionPhaseScript:
			issues.append("SpawnProgression entries must be SpawnProgressionPhase resources.")
			continue
		if phase.min_completed_turns <= previous_start:
			issues.append("SpawnProgression phases must use strictly increasing turn thresholds.")
		previous_start = phase.min_completed_turns
		for issue in phase.validate():
			issues.append("Turn %d phase: %s" % [phase.min_completed_turns, issue])
	if not phases.is_empty() and phases[0] != null and phases[0].min_completed_turns != 0:
		issues.append("SpawnProgression must begin at completed turn 0.")
	return issues
