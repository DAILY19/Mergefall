@tool
class_name SpawnProgression
extends Resource

const SpawnProgressionPhaseScript = preload("res://scripts/core/spawn_progression_phase.gd")

@export var phases: Array[Resource] = []


func phase_for_completed_turn(completed_turns: int) -> Resource:
	if phases.is_empty():
		return null
	var selected: Resource = phases[0]
	for phase in phases:
		if phase == null or phase.min_completed_turns > completed_turns:
			break
		selected = phase
	return selected


func display_value_to_rank(displayed_value: int) -> int:
	if displayed_value < 2 or (displayed_value & (displayed_value - 1)) != 0:
		return 0
	var rank := 0
	var remaining := displayed_value
	while remaining > 1:
		remaining >>= 1
		rank += 1
	return rank


func rank_to_display_value(rank: int) -> int:
	return 1 << maxi(0, rank)


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
