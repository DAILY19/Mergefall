class_name SaveData
extends RefCounted

var best_score := 0


func to_dictionary() -> Dictionary:
	return {
		"best_score": best_score,
	}


func load_from_dictionary(source: Dictionary) -> void:
	best_score = int(source.get("best_score", 0))
