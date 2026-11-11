class_name FirstRunHints
extends Control
## T059：**首次操作提示**（纯显示，不堵操作）。
##
## 真源：策划 v1.1 :65「首次体验提供简短操作提示；正式 HUD 不持续显示所有猎物与捕食者位置。」
##
## 「不堵操作」的硬约束（不是自觉遵守，而是可断言的）：
## - 本节点与所有子节点 `mouse_filter = IGNORE`、`focus_mode = NONE`：不抢鼠标、不抢焦点；
## - **不** `set_process_unhandled_input` / `_input`：不消费任何按键；
## - **不**暂停树、**不**改世界时间、**不**给玩家加任何门闩；
## - 只是屏幕下方的一块提示条，播完发 `finished` 自行隐藏。
##
## 文案必须与 `project.godot` 的 InputMap 一致（W/A/S/D、Space、Shift、Ctrl、E、鼠标左键、Esc）；
## 休息不是按键，而是"走到休息点按 E"，所以**不写"按 R 休息"**。

signal finished

const DEFAULT_LINE_SECONDS := 2.2
const FADE_SECONDS := 0.3
## 提示文案（逐条显示；改这里就改了玩家的第一条信息，别写不存在的按键）
const LINES: Array[String] = [
	"W/A/S/D 移动　空格 跳　Shift 冲刺　Ctrl 潜行",
	"E 交互：进食、饮水、走到休息点休息",
	"鼠标左键 扑击（猫才有）　Esc 暂停",
	"冲刺要体力：留力回程，别在开阔地跑到空",
]

## 每条停留时长（秒）。测试可调小，生产用默认值。
var line_seconds: float = DEFAULT_LINE_SECONDS

var _index := 0
var _elapsed := 0.0
var _done := false
var _panel: PanelContainer = null
var _label: Label = null


func _ready() -> void:
	name = "FirstRunHints"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	# 只做显示：不处理输入、不暂停、不改时间
	_build()
	_show_line(0)


func _build() -> void:
	var bottom := VBoxContainer.new()
	bottom.name = "Bottom"
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -96.0
	bottom.offset_bottom = -28.0
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bottom)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "HintPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.055, 0.075, 0.88)
	sb.border_color = Color(0.90, 0.72, 0.38, 0.45)
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 9.0
	sb.content_margin_bottom = 9.0
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	_label = Label.new()
	_label.name = "HintLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.980, 0.957, 0.898))
	_panel.add_child(_label)


# ---------------------------------------------------------------------------
# 播放
# ---------------------------------------------------------------------------

## 每渲染帧推进（`_process` 与测试共用同一条路径）
func _process(delta: float) -> void:
	advance(delta)


## 推进 dt 秒：淡入淡出 + 到点换条，最后一条走完即收尾。
## **测试直接调它**（注入固定 dt），不依赖真实帧率。
func advance(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	var in_alpha := clampf(_elapsed / FADE_SECONDS, 0.0, 1.0)
	var out_alpha := clampf((line_seconds - _elapsed) / FADE_SECONDS, 0.0, 1.0)
	if _panel != null:
		_panel.modulate.a = minf(in_alpha, out_alpha)
	if _elapsed >= line_seconds:
		if _index + 1 < LINES.size():
			_show_line(_index + 1)
		else:
			_finish()


func _show_line(index: int) -> void:
	_index = index
	_elapsed = 0.0
	if _label != null:
		_label.text = LINES[index]


## 立刻收尾：隐藏并**只发一次** `finished`
func _finish() -> void:
	if _done:
		return
	_done = true
	visible = false
	finished.emit()


## 跳过到结尾（测试用；与自然播完走同一个出口）
func finish_now() -> void:
	_finish()


# ---------------------------------------------------------------------------
# 诊断 / 断言
# ---------------------------------------------------------------------------

func line_index() -> int:
	return _index


func total_lines() -> int:
	return LINES.size()


func current_text() -> String:
	return _label.text if _label != null else ""


func is_finished() -> bool:
	return _done


## 是否真的"不堵操作"（断言用）：自身与所有子节点都不吃鼠标、不抢焦点
func blocks_input() -> bool:
	if mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return true
	if focus_mode != Control.FOCUS_NONE:
		return true
	for node in find_children("*", "Control", true, false):
		var c := node as Control
		if c == null:
			continue
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return true
		if c.focus_mode != Control.FOCUS_NONE:
			return true
	return false
