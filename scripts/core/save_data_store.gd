class_name SaveDataStore
extends RefCounted

const SaveDataScript = preload("res://scripts/core/save_data.gd")

var save_path := ""


func _init(path: String) -> void:
	save_path = path


func load_data():
	var data = SaveDataScript.new()
	if not FileAccess.file_exists(save_path):
		return data
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return data
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		data.load_from_dictionary(parsed)
	return data


func save_data(data) -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data.to_dictionary()))
