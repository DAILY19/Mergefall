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

@export var value_font: Font:
	set(value):
		value_font = value
		_apply_theme()

@export_group("Presentation")
@export var visual_set: MergefallVisualSet:
	set(value):
		visual_set = value
		if is_node_ready():
			_preview_strip.visual_set = visual_set

@export_range(0, 64, 1) var stack_separation := 8:
	set(value):
		stack_separation = value
		_apply_theme()

@export_range(0, 64, 1) var section_separation := 6:
	set(value):
		section_separation = value
		_apply_theme()

@export_range(0, 64, 1) var stats_separation := 8:
	set(value):
		stats_separation = value
		_apply_theme()

@export var background_tint := Color(0.99, 0.96, 0.92, 0.96):
	set(value):
		background_tint = value
		_apply_theme()

@export var panel_tint := Color(1.0, 0.99, 0.96, 0.98):
	set(value):
		panel_tint = value
		_apply_theme()

@export var panel_border := Color("b28d65"):
	set(value):
		panel_border = value
		_apply_theme()

@export var accent_color := Color("e78a52"):
	set(value):
		accent_color = value
		_apply_theme()

@export var text_color := Color("2f2419"):
	set(value):
		text_color = value
		_apply_theme()

@export var muted_text_color := Color("7a6751"):
	set(value):
		muted_text_color = value
		_apply_theme()

@export var title_text := "Mergefall":
	set(value):
		title_text = value
		if is_node_ready():
			%TitleLabel.text = title_text

@onready var _app_stack: VBoxContainer = %AppStack
@onready var _top_panel: PanelContainer = %TopPanel
@onready var _board_panel: PanelContainer = %BoardPanel
@onready var _bottom_panel: PanelContainer = %BottomPanel
@onready var _top_stack: VBoxContainer = %TopStack
@onready var _bottom_stack: VBoxContainer = %BottomStack
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _best_label: Label = %BestLabel
@onready var _moves_label: Label = %MovesLabel
@onready var _target_label: Label = %TargetLabel
@onready var _current_piece_label: Label = %CurrentPieceLabel
@onready var _charge_label: Label = %ChargeLabel
@onready var _charge_value_label: Label = %ChargeValueLabel
@onready var _charge_bar: ProgressBar = %ChargeBar
@onready var _preview_strip: PiecePreviewStrip = %PreviewStrip
@onready var _preview_panel: PanelContainer = %PreviewPanel
@onready var _toast_label: Label = %ToastLabel
@onready var _left_button: Button = %LeftButton
@onready var _rotate_button: Button = %RotateButton
@onready var _right_button: Button = %RightButton
@onready var _drop_button: Button = %DropButton
@onready var _undo_button: Button = %UndoButton
@onready var _restart_button: Button = %RestartButton
@onready var _stats_row: HBoxContainer = %StatsRow
@onready var _board_slot: Control = %BoardSlot

var _multiplier_bar_state := "idle"
var _displayed_multiplier := 1
var _bar_tween: Tween

const MERGE_PREVIEW_FILL := 18.0


func _ready() -> void:
	_apply_theme()
	reset_multiplier_bar()


func bind_actions(
	move_left_action: Callable,
	move_right_action: Callable,
	drop_action: Callable,
	undo_action: Callable,
	restart_action: Callable
) -> void:
	_left_button.pressed.connect(move_left_action)
	_right_button.pressed.connect(move_right_action)
	_drop_button.pressed.connect(drop_action)
	_undo_button.pressed.connect(undo_action)
	_restart_button.pressed.connect(restart_action)


func update_status(data: Dictionary) -> void:
	_score_label.text = str(data.get("score", 0))
	_best_label.text = str(data.get("best_score", 0))
	_moves_label.text = str(data.get("move_count", 0))
	_target_label.text = data.get("target_text", "")
	_subtitle_label.text = data.get("subtitle_text", "")
	_current_piece_label.text = data.get("current_piece_text", "")
	_undo_button.disabled = not data.get("can_undo", false)
	_left_button.text = "LEFT"
	_drop_button.text = "DROP"
	_right_button.text = "RIGHT"


func set_merge_preview(active: bool) -> void:
	if _multiplier_bar_state == "resolving" or _multiplier_bar_state == "complete":
		return
	var next_state := "preview" if active else "idle"
	if next_state == _multiplier_bar_state:
		return
	_multiplier_bar_state = next_state
	_displayed_multiplier = 1
	_update_multiplier_text()
	_apply_charge_bar_style()
	_animate_bar_to(MERGE_PREVIEW_FILL if active else 0.0, false)


func begin_turn_resolution() -> void:
	_multiplier_bar_state = "resolving"
	_displayed_multiplier = 1
	_update_multiplier_text()
	_apply_charge_bar_style()
	_animate_bar_to(0.0, false)


func show_merge_wave(multiplier: int, progress: float) -> void:
	_multiplier_bar_state = "resolving"
	_displayed_multiplier = maxi(1, multiplier)
	_update_multiplier_text()
	_apply_charge_bar_style()
	_animate_bar_to(clampf(progress, 0.0, 1.0) * 100.0, true)


func complete_turn_resolution() -> void:
	_multiplier_bar_state = "complete"
	_apply_charge_bar_style()


func reset_multiplier_bar() -> void:
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
	_multiplier_bar_state = "idle"
	_displayed_multiplier = 1
	_charge_bar.max_value = 100.0
	_charge_bar.value = 0.0
	_charge_bar.scale = Vector2.ONE
	_charge_bar.modulate = Color.WHITE
	_update_multiplier_text()
	_apply_charge_bar_style()


func get_multiplier_bar_state() -> String:
	return _multiplier_bar_state


func get_displayed_multiplier() -> int:
	return _displayed_multiplier


func get_multiplier_bar_value() -> float:
	return float(_charge_bar.value)


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


func get_board_layout_rect() -> Rect2:
	if not is_node_ready():
		return Rect2()
	return _board_slot.get_global_rect()


func _apply_theme() -> void:
	if not is_node_ready():
		return

	_title_label.text = title_text
	_app_stack.add_theme_constant_override("separation", stack_separation)
	_top_stack.add_theme_constant_override("separation", section_separation)
	_bottom_stack.add_theme_constant_override("separation", section_separation)
	_stats_row.add_theme_constant_override("separation", stats_separation)
	_apply_panel_style(_top_panel, panel_tint, 12, 6, 3, 6, 3)
	_apply_panel_style(_preview_panel, Color(1, 1, 1, 0.12), 8, 3, 1, 3, 1)
	_apply_board_panel_style()
	_apply_panel_style(_bottom_panel, panel_tint, 12, 6, 3, 6, 3)
	_apply_label_style(_title_label, title_font, 16, text_color)
	_apply_label_style(_subtitle_label, body_font, 11, muted_text_color)
	_apply_label_style(_target_label, body_font, 13, text_color)
	_apply_label_style(_current_piece_label, body_font, 12, text_color)
	_apply_label_style(_charge_label, body_font, 11, text_color)
	_apply_label_style(_charge_value_label, value_font if value_font != null else body_font, 11, text_color)
	_apply_charge_bar_style()
	_apply_label_style(_toast_label, title_font if title_font != null else body_font, 24, text_color)
	_apply_stat_card(_score_label)
	_apply_stat_card(_best_label)
	_apply_stat_card(_moves_label)
	_apply_button_style(_left_button, false)
	_apply_button_style(_right_button, false)
	_rotate_button.visible = false
	_apply_button_style(_drop_button, true)
	_apply_button_style(_undo_button, false)
	_apply_button_style(_restart_button, false)
	_preview_strip.title_font = body_font
	_preview_strip.label_font = body_font
	_preview_strip.visual_set = visual_set
	_preview_strip.outline_color = text_color
	_preview_strip.card_color = Color(1.0, 0.98, 0.94, 0.72)
	_preview_strip.empty_card_color = Color(0.92, 0.86, 0.78, 0.34)
	_preview_strip.title_text = "Next up"
	_preview_strip.queue_redraw()


func _apply_charge_bar_style() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.82, 0.76, 0.68, 0.65)
	background.border_color = accent_color.lightened(0.22) if _multiplier_bar_state == "preview" else panel_border
	background.set_border_width_all(2 if _multiplier_bar_state == "preview" else 1)
	background.set_corner_radius_all(7)
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent_color.lightened(0.12) if _multiplier_bar_state == "preview" else accent_color
	fill.set_corner_radius_all(7)
	_charge_bar.add_theme_stylebox_override("background", background)
	_charge_bar.add_theme_stylebox_override("fill", fill)


func _update_multiplier_text() -> void:
	if not is_node_ready():
		return
	_charge_label.text = "MULTIPLIER"
	_charge_value_label.text = "x%d" % _displayed_multiplier


func _animate_bar_to(value: float, emphasize: bool) -> void:
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.set_parallel(true)
	_bar_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bar_tween.tween_property(_charge_bar, "value", value, 0.16)
	if emphasize:
		_charge_bar.pivot_offset = _charge_bar.size * 0.5
		_bar_tween.tween_property(_charge_bar, "scale", Vector2(1.0, 1.12), 0.08)
		_bar_tween.chain().tween_property(_charge_bar, "scale", Vector2.ONE, 0.11)


func _apply_label_style(label: Label, font: Font, font_size: int, color: Color) -> void:
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)


func _apply_panel_style(
	panel: PanelContainer,
	fill_color: Color,
	radius: int,
	margin_left: int,
	margin_top: int,
	margin_right: int,
	margin_bottom: int
) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = panel_border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.shadow_color = Color(0.16, 0.11, 0.07, 0.12)
	style.shadow_size = 4
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin_left
	style.content_margin_top = margin_top
	style.content_margin_right = margin_right
	style.content_margin_bottom = margin_bottom
	panel.add_theme_stylebox_override("panel", style)


func _apply_stat_card(value_label: Label) -> void:
	var caption := value_label.get_parent().get_child(0) as Label
	var card := value_label.get_parent().get_parent() as PanelContainer
	_apply_panel_style(card, Color(1.0, 0.95, 0.88, 0.76), 9, 5, 2, 5, 2)
	_apply_label_style(caption, body_font, 9, muted_text_color)
	_apply_label_style(value_label, value_font if value_font != null else body_font, 15, text_color)


func _apply_board_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	_board_panel.add_theme_stylebox_override("panel", style)


func _apply_button_style(button: Button, emphasize: bool) -> void:
	var fill := accent_color if emphasize else Color(0.96, 0.92, 0.86, 1.0)
	var pressed := Color(fill.r * 0.9, fill.g * 0.9, fill.b * 0.9, fill.a)
	var font_color := Color("fffaf2") if emphasize else text_color
	button.add_theme_font_override("font", body_font if body_font != null else ThemeDB.fallback_font)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.44, 1.0))
	button.add_theme_stylebox_override("normal", _make_button_style(fill))
	button.add_theme_stylebox_override("hover", _make_button_style(fill.lightened(0.06)))
	button.add_theme_stylebox_override("pressed", _make_button_style(pressed))
	button.add_theme_stylebox_override("focus", _make_button_style(fill))
	button.add_theme_stylebox_override("disabled", _make_button_style(Color(0.85, 0.82, 0.77, 0.92)))


func _make_button_style(fill_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = panel_border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(14)
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	return style
