class_name SaveData
extends RefCounted

var best_score := 0
var sound_muted := false


func to_dictionary() -> Dictionary:
	return {
		"best_score": best_score,
		"sound_muted": sound_muted,
	}


func load_from_dictionary(source: Dictionary) -> void:
	best_score = int(source.get("best_score", 0))
	sound_muted = bool(source.get("sound_muted", false))
