class_name RunStatistics
extends RefCounted

var completed_turns := 0
var game_over_turn := -1
var highest_produced_tile := 0
var total_merges := 0
var total_merge_waves := 0
var longest_merge_chain := 0
var highest_multiplier := 1


func reset() -> void:
	completed_turns = 0
	game_over_turn = -1
	highest_produced_tile = 0
	total_merges = 0
	total_merge_waves = 0
	longest_merge_chain = 0
	highest_multiplier = 1


func record_completed_turn(settlement: Dictionary, board_state: RefCounted) -> void:
	var wave_count := 0
	for event in settlement.get("events", []):
		if event.get("type", "") != "merge_wave":
			continue
		wave_count += 1
		total_merge_waves += 1
		total_merges += event.get("steps", []).size()
		highest_multiplier = maxi(highest_multiplier, int(event.get("multiplier", 1)))
	longest_merge_chain = maxi(longest_merge_chain, wave_count)
	for row in board_state.cells:
		for rank in row:
			if int(rank) > 0:
				highest_produced_tile = maxi(highest_produced_tile, 1 << int(rank))
	completed_turns += 1


func mark_game_over() -> void:
	if game_over_turn < 0:
		game_over_turn = completed_turns


func duplicate_state():
	var copy = get_script().new()
	copy.completed_turns = completed_turns
	copy.game_over_turn = game_over_turn
	copy.highest_produced_tile = highest_produced_tile
	copy.total_merges = total_merges
	copy.total_merge_waves = total_merge_waves
	copy.longest_merge_chain = longest_merge_chain
	copy.highest_multiplier = highest_multiplier
	return copy


func to_dictionary() -> Dictionary:
	return {
		"completed_turns": completed_turns,
		"game_over_turn": game_over_turn,
		"highest_produced_tile": highest_produced_tile,
		"total_merges": total_merges,
		"total_merge_waves": total_merge_waves,
		"longest_merge_chain": longest_merge_chain,
		"highest_multiplier": highest_multiplier,
	}
