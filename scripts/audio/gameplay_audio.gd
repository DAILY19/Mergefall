class_name MergefallGameplayAudio
extends Node

# A deliberately small palette from the local Universal Sound Effects packs.
# Movement shares one sound with a slight directional pitch shift so repeated
# play stays cohesive instead of becoming a wall of unrelated cues.
const MOVE_STREAM_PATH := "res://assets/audio/sfx/User Interface Pack 1 - Universal Sound Effects/WAV/Button Clicks/UI_Button_Click_6.wav"
const ROTATE_STREAM_PATH := "res://assets/audio/sfx/User Interface Pack 1 - Universal Sound Effects/WAV/Button Clicks/UI_Button_Click_8.wav"
const DROP_STREAM_PATH := "res://assets/audio/sfx/User Interface Pack 1 - Universal Sound Effects/WAV/Menus/UI_Swish_2.wav"
const LAND_STREAM_PATH := "res://assets/audio/sfx/Game Sound Effects 2 - Universal Sound Effects/WAV/GS2_Land.wav"
const BLOCKED_STREAM_PATH := "res://assets/audio/sfx/User Interface Pack 1 - Universal Sound Effects/WAV/Button Clicks/UI_Button_Disable.wav"
const MERGE_STREAM_PATH := "res://assets/audio/sfx/User Interface Pack 1 - Universal Sound Effects/WAV/Puzzle Game/UI_Puzzle_Game_6.wav"
const GAME_OVER_STREAM_PATH := "res://assets/audio/sfx/User Interface Pack 2 - Universal Sound Effects/WAV/UI2_Decline_2.wav"

const BLOCKED_COOLDOWN_MSEC := 140

var input_player := AudioStreamPlayer.new()
var motion_player := AudioStreamPlayer.new()
var impact_player := AudioStreamPlayer.new()
var result_player := AudioStreamPlayer.new()
var last_blocked_msec := -BLOCKED_COOLDOWN_MSEC
var play_versions := {}
var stream_cache: Dictionary = {}
var active_tweens: Array[Tween] = []


func _ready() -> void:
	input_player.name = "InputSFX"
	motion_player.name = "MotionSFX"
	impact_player.name = "ImpactSFX"
	result_player.name = "ResultSFX"
	add_child(input_player)
	add_child(motion_player)
	add_child(impact_player)
	add_child(result_player)


func _exit_tree() -> void:
	for tween in active_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	active_tweens.clear()
	for player in [input_player, motion_player, impact_player, result_player]:
		player.stop()
		player.stream = null
	play_versions.clear()
	stream_cache.clear()


func play_move(direction: int) -> void:
	_play(input_player, _stream(MOVE_STREAM_PATH), -18.0, 0.96 if direction < 0 else 1.04)


func play_rotate() -> void:
	_play(input_player, _stream(ROTATE_STREAM_PATH), -16.5, 1.0)


func play_drop(distance: int) -> void:
	# A tiny pitch range keeps long drops legible without turning them dramatic.
	var pitch := remap(clampf(float(distance), 0.0, 10.0), 0.0, 10.0, 1.08, 0.94)
	_play(motion_player, _stream(DROP_STREAM_PATH), -18.0, pitch)


func play_land() -> void:
	# The source has a long tail; a soft cap keeps repeated turns tactile.
	_play(impact_player, _stream(LAND_STREAM_PATH), -14.5, 1.08, 0.24, 0.08)


func play_blocked() -> void:
	var now := Time.get_ticks_msec()
	if now - last_blocked_msec < BLOCKED_COOLDOWN_MSEC:
		return
	last_blocked_msec = now
	_play(input_player, _stream(BLOCKED_STREAM_PATH), -20.0, 0.92, 0.18, 0.06)


func play_merge(chain_length: int) -> void:
	var pitch := 1.0 + minf(float(maxi(chain_length - 1, 0)) * 0.035, 0.14)
	_play(result_player, _stream(MERGE_STREAM_PATH), -12.5, pitch, 0.38, 0.10)


func play_game_over() -> void:
	_play(result_player, _stream(GAME_OVER_STREAM_PATH), -16.0, 0.94)


func _stream(path: String) -> AudioStream:
	if not stream_cache.has(path):
		stream_cache[path] = load(path) as AudioStream
	return stream_cache[path]


func _play(
	player: AudioStreamPlayer,
	stream: AudioStream,
	volume_db: float,
	pitch_scale: float,
	hold_sec: float = 0.0,
	fade_sec: float = 0.0
) -> void:
	if stream == null:
		return
	var player_id := player.get_instance_id()
	var version: int = int(play_versions.get(player_id, 0)) + 1
	play_versions[player_id] = version
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	if hold_sec <= 0.0:
		return
	var hold_tween := create_tween()
	active_tweens.append(hold_tween)
	hold_tween.tween_interval(hold_sec)
	hold_tween.tween_callback(func() -> void:
		if int(play_versions.get(player_id, 0)) != version:
			return
		var fade_tween := create_tween()
		active_tweens.append(fade_tween)
		fade_tween.tween_property(player, "volume_db", -60.0, fade_sec)
		fade_tween.tween_callback(func() -> void:
			if int(play_versions.get(player_id, 0)) == version:
				player.stop()
		)
		fade_tween.finished.connect(func() -> void:
			active_tweens.erase(fade_tween)
		)
	)
	hold_tween.finished.connect(func() -> void:
		active_tweens.erase(hold_tween)
	)
