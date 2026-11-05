class_name EndLifeConfirm
extends Control
## T042：暂停层里的「结束本次生命」二次确认。
##
## 契约：
## - 默认焦点「取消」；Esc 只取消确认、回到暂停菜单（用 `_input` 先于 `PauseMenu`
##   的 `_unhandled_input` 消费，保证「确认层 > 暂停」）。
## - `PROCESS_MODE_ALWAYS`：暂停中仍可点击/按键。
## - 只发信号，不直接改生命周期/存档；正常死亡路径由 `MainEntry` 执行。

signal confirmed
signal cancelled

const TITLE := "结束本次生命？"
const MESSAGE := "本次生命将正常结算并写入档案，无法撤销；重生需在结算页之后重新选择物种。"
const HINT := "「取消」为默认选项 · Esc 返回"
const CANCEL_TEXT := "取消"
const CONFIRM_TEXT := "确认结束本次生命"

var _cancel: Button = null
var _confirm: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(0.0, 0.0, 0.0, 0.66)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

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

	var message := _label(MESSAGE, 14, BoardTokens.TEXT)
	message.name = "Message"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(500.0, 0.0)
	column.add_child(message)

	var hint := _label(HINT, 12, BoardTokens.TEXT_FAINT)
	hint.name = "Hint"
	column.add_child(hint)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)

	_cancel = _button(CANCEL_TEXT, true)
	_cancel.name = "CancelButton"
	_cancel.focus_mode = Control.FOCUS_ALL
	_cancel.pressed.connect(cancel)
	buttons.add_child(_cancel)

	_confirm = _button(CONFIRM_TEXT, false)
	_confirm.name = "ConfirmButton"
	_confirm.focus_mode = Control.FOCUS_ALL
	_confirm.pressed.connect(confirm)
	buttons.add_child(_confirm)


# ---------------------------------------------------------------------------
# 对外
# ---------------------------------------------------------------------------

func open() -> void:
	if _cancel == null:
		_build()
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


func title_text() -> String:
	return TITLE


func message_text() -> String:
	return MESSAGE


func hint_text() -> String:
	return HINT


func default_button_text() -> String:
	return _cancel.text if _cancel != null else ""


func cancel_text() -> String:
	return default_button_text()


func confirm_text() -> String:
	return _confirm.text if _confirm != null else ""


## 当前焦点按钮的文字（断言/证据用）；无焦点时回落到默认「取消」。
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


## `_input` 早于 `PauseMenu._unhandled_input`：确认层打开时 Esc 只取消确认。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()


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
