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

signal mute_toggled(muted: bool)

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
@onready var _board_stage: Control = %BoardStage
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
@onready var _mute_button: Button = %MuteButton
@onready var _restart_progress_bar: ProgressBar = %RestartProgressBar
@onready var _stats_row: HBoxContainer = %StatsRow
@onready var _board_slot: Control = %BoardSlot

var _multiplier_bar_state := "idle"
var _displayed_multiplier := 1
var _bar_tween: Tween
var _restart_action := Callable()
var _new_run_hold_active := false
var _new_run_hold_elapsed := 0.0
var _new_run_hold_completed := false
var _board_rect_global := Rect2()

const MERGE_PREVIEW_FILL := 18.0
const NEW_RUN_HOLD_DURATION := 1.0
const SIDE_BUTTON_SIZE := Vector2(48, 72)
const SIDE_BUTTON_GAP := 6.0
const SIDE_BUTTON_BOARD_Y_RATIO := 0.62


func _ready() -> void:
	_apply_theme()
	reset_multiplier_bar()
	_reset_new_run_hold_visuals()
	_setup_mute_button()
	visibility_changed.connect(_on_visibility_changed)


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
	_restart_action = restart_action
	if not _restart_button.button_down.is_connected(_begin_new_run_hold):
		_restart_button.button_down.connect(_begin_new_run_hold)
	if not _restart_button.button_up.is_connected(_cancel_new_run_hold):
		_restart_button.button_up.connect(_cancel_new_run_hold)
	if not _restart_button.mouse_exited.is_connected(_cancel_new_run_hold):
		_restart_button.mouse_exited.connect(_cancel_new_run_hold)


func update_status(data: Dictionary) -> void:
	_set_label_text(_score_label, str(data.get("score", 0)))
	_set_label_text(_best_label, str(data.get("best_score", 0)))
	_set_label_text(_moves_label, str(data.get("move_count", 0)))
	_set_label_text(_target_label, data.get("target_text", ""))
	_set_label_text(_subtitle_label, data.get("subtitle_text", ""))
	_set_label_text(_current_piece_label, data.get("current_piece_text", ""))
	_undo_button.disabled = not data.get("can_undo", false)
	var movement_disabled: bool = bool(data.get("movement_disabled", false))
	_left_button.disabled = movement_disabled
	_right_button.disabled = movement_disabled


func set_gameplay_rects(board_rect_global: Rect2, _drop_zone_rect_global: Rect2 = Rect2()) -> void:
	if _board_rect_global == board_rect_global:
		return
	_board_rect_global = board_rect_global
	_layout_side_controls()


func _set_label_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


func get_side_control_rects() -> Dictionary:
	if not is_node_ready():
		return {}
	return {
		"left": _left_button.get_global_rect(),
		"right": _right_button.get_global_rect(),
		"drop": _drop_button.get_global_rect()
	}


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


func get_new_run_hold_progress() -> float:
	return float(_restart_progress_bar.value) / float(_restart_progress_bar.max_value)


func is_new_run_hold_active() -> bool:
	return _new_run_hold_active


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
	_apply_side_button_style(_left_button)
	_apply_side_button_style(_right_button)
	_left_button.text = "<"
	_right_button.text = ">"
	_left_button.accessibility_name = "Move left"
	_right_button.accessibility_name = "Move right"
	_apply_mute_button_style()
	_rotate_button.visible = false
	_apply_button_style(_drop_button, true)
	_drop_button.add_theme_font_size_override("font_size", 15)
	_apply_button_style(_undo_button, false)
	_apply_button_style(_restart_button, false)
	_restart_button.add_theme_color_override("font_color", Color("2a1d10"))
	_restart_button.add_theme_color_override("font_hover_color", Color("2a1d10"))
	_restart_button.add_theme_color_override("font_pressed_color", Color("2a1d10"))
	_restart_button.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.44, 1.0))
	_apply_new_run_progress_style()
	_preview_strip.title_font = body_font
	_preview_strip.label_font = body_font
	_preview_strip.visual_set = visual_set
	_preview_strip.outline_color = text_color
	_preview_strip.card_color = Color(1.0, 0.98, 0.94, 0.72)
	_preview_strip.empty_card_color = Color(0.92, 0.86, 0.78, 0.34)
	_preview_strip.title_text = "Next up"
	_preview_strip.queue_redraw()
	_layout_side_controls()


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


func _setup_mute_button() -> void:
	_mute_button.toggled.connect(_on_mute_toggled)


func _on_mute_toggled(button_pressed: bool) -> void:
	mute_toggled.emit(button_pressed)
	_mute_button.tooltip_text = "Muted" if button_pressed else "Toggle sound on/off"


func set_mute_button_state(muted: bool) -> void:
	_mute_button.set_pressed_no_signal(muted)
	_mute_button.text = str("♪" if not muted else "♪̶")
	_mute_button.tooltip_text = "Muted" if muted else "Toggle sound on/off"


func _apply_mute_button_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.95, 0.88, 0.76)
	style.border_color = panel_border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(9)
	style.content_margin_left = 2
	style.content_margin_top = 2
	style.content_margin_right = 2
	style.content_margin_bottom = 2
	_mute_button.add_theme_stylebox_override("normal", style)
	_mute_button.add_theme_stylebox_override("hover", style)
	_mute_button.add_theme_stylebox_override("pressed", style)
	_mute_button.add_theme_stylebox_override("focus", style)
	_mute_button.add_theme_stylebox_override("disabled", style)
	_mute_button.add_theme_font_override("font", body_font if body_font != null else ThemeDB.fallback_font)
	_mute_button.add_theme_font_size_override("font_size", 16)
	_mute_button.add_theme_color_override("font_color", Color("2a1d10"))
	_mute_button.add_theme_color_override("font_hover_color", accent_color)
	_mute_button.add_theme_color_override("font_pressed_color", accent_color.darkened(0.2))
	_mute_button.toggle_mode = true


func _apply_stat_card(value_label: Label) -> void:
	var caption := value_label.get_parent().get_child(0) as Label
	var card := value_label.get_parent().get_parent() as PanelContainer
	_apply_panel_style(card, Color(1.0, 0.95, 0.88, 0.76), 9, 5, 2, 5, 2)
	_apply_label_style(caption, body_font, 10, Color("6d4f2e"))
	_apply_label_style(value_label, value_font if value_font != null else body_font, 16, Color("2a1d10"))


func _apply_board_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	_board_panel.add_theme_stylebox_override("panel", style)


func _apply_button_style(button: Button, emphasize: bool) -> void:
	var is_restart := button == _restart_button
	if is_restart:
		var cream_fill := Color(0.96, 0.92, 0.86, 1.0)
		var copper_border := Color("a96532")
		var pressed_fill := Color(0.88, 0.84, 0.78, 1.0)
		button.add_theme_font_override("font", body_font if body_font != null else ThemeDB.fallback_font)
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_stylebox_override("normal", _make_button_style(cream_fill, copper_border, 10))
		button.add_theme_stylebox_override("hover", _make_button_style(cream_fill.lightened(0.04), copper_border.lightened(0.12), 10))
		button.add_theme_stylebox_override("pressed", _make_button_style(pressed_fill, copper_border.darkened(0.15), 10))
		button.add_theme_stylebox_override("focus", _make_button_style(cream_fill, copper_border.lightened(0.08), 10))
		button.add_theme_stylebox_override("disabled", _make_button_style(Color(0.85, 0.82, 0.77, 0.92), Color(0.65, 0.55, 0.45, 0.6), 10))
		return
	var fill := accent_color if emphasize else Color(0.96, 0.92, 0.86, 1.0)
	var pressed := Color(fill.r * 0.9, fill.g * 0.9, fill.b * 0.9, fill.a)
	var font_color := Color("fffaf2") if emphasize else Color("2a1d10")
	button.add_theme_font_override("font", body_font if body_font != null else ThemeDB.fallback_font)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.44, 1.0))
	button.add_theme_stylebox_override("normal", _make_button_style(fill))
	button.add_theme_stylebox_override("hover", _make_button_style(fill.lightened(0.06)))
	button.add_theme_stylebox_override("pressed", _make_button_style(pressed))
	button.add_theme_stylebox_override("focus", _make_button_style(fill))
	button.add_theme_stylebox_override("disabled", _make_button_style(Color(0.85, 0.82, 0.77, 0.92)))


func _apply_side_button_style(button: Button) -> void:
	button.custom_minimum_size = SIDE_BUTTON_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_override("font", body_font if body_font != null else ThemeDB.fallback_font)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", Color("fffaf2"))
	button.add_theme_color_override("font_disabled_color", Color(0.62, 0.56, 0.49, 1.0))
	button.add_theme_stylebox_override("normal", _make_button_style(accent_color, 9))
	button.add_theme_stylebox_override("hover", _make_button_style(accent_color.lightened(0.06), 9))
	button.add_theme_stylebox_override("pressed", _make_button_style(accent_color.darkened(0.12), 9))
	button.add_theme_stylebox_override("focus", _make_button_style(accent_color.lightened(0.08), 9))
	button.add_theme_stylebox_override("disabled", _make_button_style(Color(0.82, 0.78, 0.72, 0.9), 9))


func _apply_new_run_progress_style() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color.TRANSPARENT
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent_color.lightened(0.1)
	fill.set_corner_radius_all(2)
	_restart_progress_bar.add_theme_stylebox_override("background", background)
	_restart_progress_bar.add_theme_stylebox_override("fill", fill)


func _make_button_style(fill_color: Color, border_color: Color = Color(0, 0, 0, 0), radius: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = panel_border if border_color == Color() else border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	return style


func _layout_side_controls() -> void:
	if not is_node_ready() or _board_rect_global.size == Vector2.ZERO:
		return
	var stage_rect := _board_stage.get_global_rect()
	var board_in_stage := Rect2(_board_rect_global.position - stage_rect.position, _board_rect_global.size)
	var button_size := SIDE_BUTTON_SIZE
	var usable_left := maxf(0.0, board_in_stage.position.x)
	var usable_right := maxf(0.0, stage_rect.size.x - board_in_stage.end.x)
	button_size.x = minf(button_size.x, maxf(36.0, minf(usable_left, usable_right) - SIDE_BUTTON_GAP))
	button_size.y = minf(button_size.y, maxf(52.0, board_in_stage.size.y * 0.2))
	_left_button.size = button_size
	_right_button.size = button_size
	var y := clampf(
		board_in_stage.position.y + board_in_stage.size.y * SIDE_BUTTON_BOARD_Y_RATIO - button_size.y * 0.5,
		0.0,
		maxf(0.0, stage_rect.size.y - button_size.y)
	)
	_left_button.position = Vector2(maxf(0.0, board_in_stage.position.x - SIDE_BUTTON_GAP - button_size.x), y)
	_right_button.position = Vector2(minf(stage_rect.size.x - button_size.x, board_in_stage.end.x + SIDE_BUTTON_GAP), y)


func _process(delta: float) -> void:
	_update_new_run_hold(delta)


func _begin_new_run_hold() -> void:
	if _new_run_hold_active or _new_run_hold_completed or _restart_button.disabled:
		return
	_new_run_hold_active = true
	_new_run_hold_elapsed = 0.0
	_new_run_hold_completed = false
	_restart_progress_bar.value = 0.0
	set_process(true)


func _update_new_run_hold(delta: float) -> void:
	if not _new_run_hold_active or _new_run_hold_completed:
		return
	_new_run_hold_elapsed = minf(_new_run_hold_elapsed + maxf(delta, 0.0), NEW_RUN_HOLD_DURATION)
	_restart_progress_bar.value = (_new_run_hold_elapsed / NEW_RUN_HOLD_DURATION) * _restart_progress_bar.max_value
	if _new_run_hold_elapsed >= NEW_RUN_HOLD_DURATION:
		_complete_new_run_hold()


func _cancel_new_run_hold() -> void:
	if not _new_run_hold_active and _new_run_hold_elapsed <= 0.0:
		return
	if _new_run_hold_completed:
		_reset_new_run_hold_visuals()
		return
	_new_run_hold_active = false
	_new_run_hold_elapsed = 0.0
	_reset_new_run_hold_visuals()


func _complete_new_run_hold() -> void:
	if _new_run_hold_completed:
		return
	_new_run_hold_completed = true
	_new_run_hold_active = false
	if _restart_action.is_valid():
		_restart_action.call()
	_reset_new_run_hold_visuals()


func _reset_new_run_hold_visuals() -> void:
	_new_run_hold_active = false
	_new_run_hold_elapsed = 0.0
	_new_run_hold_completed = false
	_restart_progress_bar.value = 0.0
	set_process(false)


func _on_visibility_changed() -> void:
	if not visible:
		_cancel_new_run_hold()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_cancel_new_run_hold()
