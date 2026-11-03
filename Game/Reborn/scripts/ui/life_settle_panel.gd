class_name LifeSettlePanel
extends Control
## 生命结算覆盖层（T032，策划 v1.1 §9.3/§9.4、§327「死亡结算」必需页面）。
##
## 三条纪律（沿用 `MainMenu`）：
##   1. **只做界面**：只把 `MainEntry` 传入的结算档案与 context **照实**格式化；
##      不读 `GameState`、不建玩家、不写任何状态（数据唯一权威在 `GameState`，决策 D2）。
##   2. **不是 CanvasLayer**：普通 `Control`（T030 H8 契约），由入口加在 `MainMenu`
##      **之后** → 同 canvas 后加入者绘制在上，天然盖住菜单（含 MVP 块，决策 D5；
##      ART09 菜单 z 序遗留属 T033，本面板不参与修复）。
##   3. **只呈现一次**：`LifeCycle.end_life()` 保证只结算一次（T030）；
##      本面板随之只 `present` 一次（`present_count()` 供断言，决策 D4）。
##
## 内容口径（策划 §9.4）：物种、存活时长、发现地点、食物/水获取、捕猎/逃脱、
## 重要事件计数、结束原因与死亡时生存状态——**只给系统确实记录的事实**，不编造（决策 D3）。
##
## 输入（决策 D7）：可见时消费**全部**按键，防止穿到背后的菜单；
## `ui_accept` / `ui_cancel` / 点击任意处 / 「继续」按钮 → dismiss；出生由入口自动隐藏。

signal dismissed

## 面板尺寸（设计分辨率 1280×720 下的中央卡）
const PANEL_HALF_W := 300.0
const PANEL_HALF_H := 220.0

var _record: Dictionary = {}
var _context: Dictionary = {}
var _present_count := 0
var _lines: Array[String] = []

var _scrim: ColorRect = null
var _card: PanelContainer = null
var _title: Label = null
var _line_box: VBoxContainer = null
var _hint: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	gui_input.connect(_on_click_anywhere)
	_build()


# ---------------------------------------------------------------------------
# 对外（入口 / 断言）
# ---------------------------------------------------------------------------

## 呈现一页结算。`record` = `life_settled` 的档案；`context` = 入口组装的
## `{species_titles: {species_id: 显示名}, event_kinds: {事件 kind: 条数}}`。
func present(record: Dictionary, context: Dictionary = {}) -> void:
	if record.is_empty():
		return
	_record = record.duplicate(true)
	_context = context.duplicate(true)
	_present_count += 1
	_rebuild()
	visible = true


func dismiss() -> void:
	if not visible:
		return
	visible = false
	dismissed.emit()


func is_presenting() -> bool:
	return visible


func present_count() -> int:
	return _present_count


## 面板呈现的档案（断言用；与 `GameState.last_record()` 应完全一致，无平行副本漂移）。
func record() -> Dictionary:
	return _record.duplicate(true)


func event_kinds() -> Dictionary:
	return (_context.get("event_kinds", {}) as Dictionary).duplicate(true)


## 面板正文一行拼接（断言 / 取证日志共用）。
func summary_text() -> String:
	return "\n".join(_lines)


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

## 可见时消费全部按键（保护背后的菜单）；Enter/Esc 同时消隐。
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.is_action_pressed("ui_accept") or key.is_action_pressed("ui_cancel"):
		dismiss()
	# 面板可见期间所有按键都不许穿到菜单（决策 D7）
	get_viewport().set_input_as_handled()


## 点击面板任意空白处消隐（按钮/文本的命中最终都会冒泡回这里或走各自处理器）
func _on_click_anywhere(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		dismiss()


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

func _build() -> void:
	_scrim = ColorRect.new()
	_scrim.name = "SettleScrim"
	_scrim.color = Color(0.010, 0.016, 0.020, 0.820)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_click_anywhere)
	add_child(_scrim)

	_card = PanelContainer.new()
	_card.name = "SettleCard"
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card.offset_left = -PANEL_HALF_W
	_card.offset_right = PANEL_HALF_W
	_card.offset_top = -PANEL_HALF_H
	_card.offset_bottom = PANEL_HALF_H
	_card.add_theme_stylebox_override("panel", _card_style())
	add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 18)
	_card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_title = _label("生命结算", 24, BoardTokens.GOLD)
	_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_title.add_theme_constant_override("shadow_offset_x", 2)
	_title.add_theme_constant_override("shadow_offset_y", 2)
	column.add_child(_title)

	_line_box = VBoxContainer.new()
	_line_box.name = "SettleLines"
	_line_box.add_theme_constant_override("separation", 6)
	column.add_child(_line_box)

	column.add_child(_spacer(10))
	var cont := _continue_button()
	column.add_child(cont)

	_hint = _label("Enter / Esc / 点击任意处 继续", 12, BoardTokens.TEXT_FAINT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)


func _rebuild() -> void:
	_lines = _build_lines()
	for child in _line_box.get_children():
		_line_box.remove_child(child)
		child.queue_free()
	for i in _lines.size():
		# 首行是「档案号 · 物种」：字号与暖白让它读作副标题，其余是正文
		var font := 17 if i == 0 else 14
		var color := BoardTokens.TEXT_WARM if i == 0 else BoardTokens.TEXT_DIM
		_line_box.add_child(_label(_lines[i], font, color))


## 策划 §9.4 字段 → 文案（只格式化档案里确实有的数据，决策 D3）
func _build_lines() -> Array[String]:
	var out: Array[String] = []
	var titles := _context.get("species_titles", {}) as Dictionary
	var species_id := String(_record.get("species_id", "?"))
	var title := String(titles.get(species_id, species_id))
	out.append("%s · %s" % [String(_record.get("life_id", "?")), title])
	out.append("存活 %.1f s" % float(_record.get("duration", 0.0)))
	var reason := _reason_text(String(_record.get("end_reason", "")))
	var damage := String(_record.get("damage_reason", ""))
	if not damage.is_empty():
		reason = "%s（%s）" % [reason, damage]
	out.append("结束原因：%s" % reason)
	var snap := _record.get("snapshot", {}) as Dictionary
	out.append("死亡时状态：%s" % _vitals_text(snap))
	out.append("捕猎 %d · 逃脱 %d" % [
		int(_record.get("captures", 0)), int(_record.get("escapes", 0))])
	out.append("食物 +%.2f · 水 +%.2f" % [
		float(_record.get("food_gained", 0.0)), float(_record.get("water_gained", 0.0))])
	var places := (_record.get("discoveries", []) as Array).map(func(p): return String(p))
	out.append("发现地点：%s" % ("，".join(places) if not places.is_empty() else "（无）"))
	out.append("重要事件：%s" % _kinds_text())
	return out


func _reason_text(reason: String) -> String:
	match reason:
		"died":
			return "死亡"
		"":
			return "（未记录）"
		_:
			return reason


func _vitals_text(snap: Dictionary) -> String:
	if snap.is_empty():
		return "（未记录）"
	return "生命 %.0f · 饥饿 %.0f · 水分 %.0f · 体力 %.0f" % [
		float(snap.get("health", 0.0)), float(snap.get("hunger", 0.0)),
		float(snap.get("thirst", 0.0)), float(snap.get("stamina", 0.0)),
	]


func _kinds_text() -> String:
	var kinds := _context.get("event_kinds", {}) as Dictionary
	if kinds.is_empty():
		return "（无）"
	var keys := kinds.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s×%d" % [String(k), int(kinds[k])])
	return "，".join(parts)


# ---------------------------------------------------------------------------
# 小部件与样式
# ---------------------------------------------------------------------------

func _continue_button() -> Button:
	var b := Button.new()
	b.name = "ContinueButton"
	b.text = "继续"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(180.0, 40.0)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color(0.980, 0.957, 0.898))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = BoardTokens.GOLD
	sb.border_color = BoardTokens.GOLD_BRIGHT
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = BoardTokens.GOLD.lightened(0.10)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(dismiss)
	return b


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BoardTokens.PANEL
	sb.border_color = Color(BoardTokens.GOLD.r, BoardTokens.GOLD.g, BoardTokens.GOLD.b, 0.55)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	return sb


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
