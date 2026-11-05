class_name PauseMenu
extends Control
## T042：存活期暂停层（普通 `Control`，由 `MainEntry` 运行期建立）。
##
## 契约：
## - 树序插在 `Hud` 之上、`MainMenu` 之下（`Hud < PauseMenu < EndLifeConfirm < MainMenu ...`）。
## - `PROCESS_MODE_ALWAYS`：`SceneTree.paused=true` 时仍能收键与点击。
## - 默认焦点「继续游戏」；Esc 与「继续游戏」同一出口，只发信号，不自己改状态。

signal resume_requested
signal end_life_requested

const TITLE := "游戏已暂停"
const RESUME_TEXT := "继续游戏"
const END_LIFE_TEXT := "结束本次生命"
const HINT := "Esc 继续游戏"

var _resume: Button = null
var _end_life: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(0.0, 0.0, 0.0, 0.58)
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
	panel.custom_minimum_size = Vector2(420.0, 0.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := _label(TITLE, 26, BoardTokens.GOLD)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var hint := _label(HINT, 12, BoardTokens.TEXT_FAINT)
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

	_resume = _button(RESUME_TEXT, true)
	_resume.name = "ResumeButton"
	_resume.focus_mode = Control.FOCUS_ALL
	_resume.pressed.connect(_on_resume_pressed)
	column.add_child(_resume)

	_end_life = _button(END_LIFE_TEXT, false)
	_end_life.name = "EndLifeButton"
	_end_life.focus_mode = Control.FOCUS_ALL
	_end_life.pressed.connect(_on_end_life_pressed)
	column.add_child(_end_life)


# ---------------------------------------------------------------------------
# 对外
# ---------------------------------------------------------------------------

func open() -> void:
	if _resume == null:
		_build()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(true)
	call_deferred("_focus_default")


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_unhandled_input(false)
	if _resume != null:
		_resume.release_focus()


func is_open() -> bool:
	return visible


func title_text() -> String:
	return TITLE


func resume_button_text() -> String:
	return _resume.text if _resume != null else ""


func end_life_button_text() -> String:
	return _end_life.text if _end_life != null else ""


func hint_text() -> String:
	return HINT


func default_button_text() -> String:
	return resume_button_text()


## 当前焦点按钮的文字（断言/证据用）；无焦点时回落到默认「继续游戏」。
func focused_button_text() -> String:
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner is Button:
		return (owner as Button).text
	return default_button_text()


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _focus_default() -> void:
	if visible and _resume != null and _resume.is_inside_tree():
		_resume.grab_focus()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_end_life_pressed() -> void:
	end_life_requested.emit()


## 暂停中 Esc = 继续游戏。用 `_unhandled_input`（`EndLifeConfirm` 用 `_input` 先消费，
## 保证「确认层 > 暂停」的优先级不靠节点顺序碰运气）。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


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
	b.custom_minimum_size = Vector2(150.0, 46.0)
	b.add_theme_font_size_override("font_size", 17)
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
