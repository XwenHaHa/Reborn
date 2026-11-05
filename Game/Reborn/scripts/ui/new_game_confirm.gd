class_name NewGameConfirm
extends Control
## T041：破坏性操作二次确认层（普通 `Control`，不引入 `CanvasLayer`；由 `MainEntry` 运行期建立）。
##
## 契约：
## - 插在 `MainMenu` 之上、`LifeSettlePanel` 之下（同 canvas 后加入者绘制在上）。
## - 全屏遮罩拦截鼠标，防止误点背后的「新游戏」。
## - **默认焦点在「取消」**：打开即 `grab_focus()`；按 Esc / Enter 都先落到取消。

signal confirmed
signal cancelled

const TITLE := "开始新游戏？"
const DEFAULT_MESSAGE := "确定开始新游戏？当前存档将被清除，且无法恢复。"
const HINT := "「取消」为默认选项 · Esc 返回"

var _scrim: ColorRect = null
var _message: Label = null
var _cancel: Button = null
var _confirm: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = Color(0.0, 0.0, 0.0, 0.62)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(560.0, 0.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := _label(TITLE, 22, BoardTokens.GOLD)
	title.name = "Title"
	column.add_child(title)

	_message = _label(DEFAULT_MESSAGE, 14, BoardTokens.TEXT)
	_message.name = "Message"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(500.0, 0.0)
	column.add_child(_message)

	var hint := _label(HINT, 12, BoardTokens.TEXT_FAINT)
	hint.name = "Hint"
	column.add_child(hint)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)

	_cancel = _button("取消", true)
	_cancel.name = "CancelButton"
	_cancel.focus_mode = Control.FOCUS_ALL
	_cancel.pressed.connect(cancel)
	buttons.add_child(_cancel)

	_confirm = _button("确认开始新游戏", false)
	_confirm.name = "ConfirmButton"
	_confirm.focus_mode = Control.FOCUS_ALL
	_confirm.pressed.connect(confirm)
	buttons.add_child(_confirm)


# ---------------------------------------------------------------------------
# 对外
# ---------------------------------------------------------------------------

func open(message: String = "") -> void:
	if _cancel == null:
		_build()
	_message.text = message if message != "" else DEFAULT_MESSAGE
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(true)
	call_deferred("_focus_default")


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_unhandled_input(false)
	if _cancel != null:
		_cancel.release_focus()


func is_open() -> bool:
	return visible


func cancel() -> void:
	if not visible:
		return
	close()
	cancelled.emit()


func confirm() -> void:
	if not visible:
		return
	close()
	confirmed.emit()


func message_text() -> String:
	return _message.text if _message != null else ""


func default_button_text() -> String:
	return _cancel.text if _cancel != null else ""


func cancel_text() -> String:
	return default_button_text()


func confirm_text() -> String:
	return _confirm.text if _confirm != null else ""


## 当前焦点按钮的文字（断言/证据用）；无焦点时回落到默认取消
func focused_button_text() -> String:
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner is Button:
		return (owner as Button).text
	return default_button_text()


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _focus_default() -> void:
	if visible and _cancel != null and _cancel.is_inside_tree():
		_cancel.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150.0, 44.0)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.980, 0.957, 0.898))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_stylebox_override("normal", _button_style(primary, false))
	b.add_theme_stylebox_override("hover", _button_style(primary, true))
	b.add_theme_stylebox_override("pressed", _button_style(primary, true))
	b.add_theme_stylebox_override("focus", _focus_style())
	return b


func _button_style(primary: bool, hovered: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if primary:
		sb.bg_color = BoardTokens.GOLD.lightened(0.10) if hovered else BoardTokens.GOLD
		sb.border_color = BoardTokens.GOLD_BRIGHT
	else:
		sb.bg_color = Color(0.086, 0.112, 0.150, 0.92) if hovered else Color(0.055, 0.068, 0.090, 0.88)
		sb.border_color = Color(0.60, 0.62, 0.52, 0.70) if hovered else Color(0.48, 0.51, 0.44, 0.55)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb


func _focus_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	sb.border_color = BoardTokens.GOLD_BRIGHT
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	return sb


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.055, 0.075, 0.965)
	sb.border_color = Color(0.90, 0.72, 0.38, 0.55)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb
