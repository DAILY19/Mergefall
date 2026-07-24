@tool
class_name GameHUD
extends Control

@export_group("Theme")
@export var title_font: Font:
	set(value):
		title_font = value
		_apply_theme()

@export var body_font: Font:
	set(value):
		body_font = value
		_apply_theme()

@export var header_panel_texture: Texture2D:
	set(value):
		header_panel_texture = value
		_apply_theme()

@export var footer_panel_texture: Texture2D:
	set(value):
		footer_panel_texture = value
		_apply_theme()

@export var stat_chip_texture: Texture2D:
	set(value):
		stat_chip_texture = value
		_apply_theme()

@export_range(0, 64, 1) var header_separation := 8:
	set(value):
		header_separation = value
		_apply_theme()

@export_range(0, 64, 1) var footer_separation := 10:
	set(value):
		footer_separation = value
		_apply_theme()

@export_range(0, 64, 1) var stats_separation := 12:
	set(value):
		stats_separation = value
		_apply_theme()

@export var panel_tint := Color(1, 1, 1, 0.96):
	set(value):
		panel_tint = value
		_apply_theme()

@export var text_color := Color("2f2419"):
	set(value):
		text_color = value
		_apply_theme()

@export var title_text := "Dumpster Delights":
	set(value):
		title_text = value
		if is_node_ready():
			%TitleLabel.text = title_text

@onready var _header_panel: PanelContainer = %HeaderPanel
@onready var _footer_panel: PanelContainer = %FooterPanel
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _best_label: Label = %BestLabel
@onready var _moves_label: Label = %MovesLabel
@onready var _target_label: Label = %TargetLabel
@onready var _preview_strip: PiecePreviewStrip = %PreviewStrip
@onready var _toast_label: Label = %ToastLabel
@onready var _hint_label: Label = %HintLabel
@onready var _rotate_left_button: Button = %RotateLeftButton
@onready var _place_button: Button = %PlaceButton
@onready var _rotate_right_button: Button = %RotateRightButton
@onready var _undo_button: Button = %UndoButton
@onready var _restart_button: Button = %RestartButton
@onready var _header_box: VBoxContainer = %HeaderBox
@onready var _footer_box: VBoxContainer = %FooterBox
@onready var _stats_row: HBoxContainer = %StatsRow


func _ready() -> void:
	_apply_theme()


func bind_actions(
	rotate_left_action: Callable,
	place_action: Callable,
	rotate_right_action: Callable,
	undo_action: Callable,
	restart_action: Callable
) -> void:
	_rotate_left_button.pressed.connect(rotate_left_action)
	_place_button.pressed.connect(place_action)
	_rotate_right_button.pressed.connect(rotate_right_action)
	_undo_button.pressed.connect(undo_action)
	_restart_button.pressed.connect(restart_action)


func update_status(data: Dictionary) -> void:
	_score_label.text = "Score: %d" % data.get("score", 0)
	_best_label.text = "Best: %d" % data.get("best_score", 0)
	_moves_label.text = "Turns: %d" % data.get("move_count", 0)
	_target_label.text = data.get("target_text", "")
	_subtitle_label.text = data.get("subtitle_text", "")
	_hint_label.text = data.get("hint_text", "")
	_undo_button.disabled = not data.get("can_undo", false)


func set_preview_pieces(pieces: Array[Resource], visible_count: int) -> void:
	_preview_strip.visible_card_count = visible_count
	_preview_strip.set_pieces(pieces)


func clear_preview() -> void:
	_preview_strip.clear_pieces()


func show_toast(message: String) -> void:
	if Engine.is_editor_hint():
		return
	_toast_label.text = message
	_toast_label.visible = true
	var tween := create_tween()
	_toast_label.modulate = Color(1, 1, 1, 0)
	tween.tween_property(_toast_label, "modulate", Color(1, 1, 1, 1), 0.15)
	tween.tween_interval(0.6)
	tween.tween_property(_toast_label, "modulate", Color(1, 1, 1, 0), 0.25)
	tween.finished.connect(func() -> void:
		_toast_label.visible = false
	)


func get_preview_strip() -> PiecePreviewStrip:
	return _preview_strip


func _apply_theme() -> void:
	if not is_node_ready():
		return

	_title_label.text = title_text
	_header_box.add_theme_constant_override("separation", header_separation)
	_footer_box.add_theme_constant_override("separation", footer_separation)
	_stats_row.add_theme_constant_override("separation", stats_separation)
	_apply_panel_style(_header_panel, header_panel_texture)
	_apply_panel_style(_footer_panel, footer_panel_texture)
	_apply_chip_style(_score_label)
	_apply_chip_style(_best_label)
	_apply_chip_style(_moves_label)
	_apply_label_style(_title_label, title_font, 30)
	_apply_label_style(_subtitle_label, body_font, 16)
	_apply_label_style(_target_label, body_font, 15)
	_apply_label_style(_hint_label, body_font, 16)
	_apply_label_style(_toast_label, title_font if title_font != null else body_font, 26)
	_preview_strip.title_font = body_font
	_preview_strip.label_font = body_font
	_preview_strip.outline_color = text_color
	_preview_strip.card_texture = stat_chip_texture
	_preview_strip.title_text = "Next Bites"


func _apply_label_style(label: Label, font: Font, font_size: int) -> void:
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", text_color)


func _apply_panel_style(panel: PanelContainer, texture: Texture2D) -> void:
	if texture == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = panel_tint
		flat.border_color = text_color
		flat.set_corner_radius_all(18)
		flat.content_margin_left = 16
		flat.content_margin_top = 16
		flat.content_margin_right = 16
		flat.content_margin_bottom = 16
		panel.add_theme_stylebox_override("panel", flat)
		return
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = panel_tint
	style.texture_margin_left = 6
	style.texture_margin_top = 6
	style.texture_margin_right = 6
	style.texture_margin_bottom = 6
	style.content_margin_left = 16
	style.content_margin_top = 16
	style.content_margin_right = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)


func _apply_chip_style(label: Label) -> void:
	_apply_label_style(label, body_font, 18)
