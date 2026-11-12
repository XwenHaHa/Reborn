class_name PlayerHud
extends Control

const GameClock := preload("res://scripts/core/game_clock.gd")


## 最小正式 HUD（T018）
##
## 真源：`轮生_Reborn_开发计划_v1.0.md` 第 134 行「状态、低值警告和交互提示可见；**调试数值不混入最终界面**」；
## `Docs/TechnicalDesign.md` §1 表格（`res://scenes/ui/hud.tscn` 是 `Control` 场景，**只观察状态、不直接修改资源账本**）
## 与第 77 行「用**信号（signal）**更新 UI，避免 UI 每帧写游戏状态」。
##
## 三条纪律：
##   1. **只读**：本文件不出现 `apply_damage()` / `restore_*()` / `commit_interaction()` / `spend_stamina()`；
##      它只读 `SurvivalState` 与 `InteractionDetector` 的查询结果。
##   2. **信号驱动**：状态 / 警告 / 目标切换都挂在信号上；`_process()` 里**唯一**读取的是交互进度（连续量）。
##   3. **不混调试**：文本里不出现 `PARAMS|` / `MOV|` / `nav_*` / `step_climb` / `probe` 等调试内容
##      （调试入口在 `scripts/debug/debug_entry.gd`，两者刻意分开）。

## 绑定成功时发出（含物种 ID；拿不到配置时为空）
signal bound(species_id: StringName)

## 动作 ID → 界面动作名（中文；未知动作原样显示）
const ACTION_NAMES := {
	&"eat": "进食",
	&"drink": "饮水",
}

## 四项指标条（ART04）：名字 → 颜色。顺序固定 = 界面顺序。
## 颜色对齐概念展板（生命 红 / 饥饿 橙 / 水分 蓝 / 体力 绿）。
const VITAL_ROWS := [
	{"key": &"health", "name": "生命", "color": Color(0.851, 0.325, 0.310)},
	{"key": &"hunger", "name": "饥饿", "color": Color(0.878, 0.651, 0.227)},
	{"key": &"thirst", "name": "水分", "color": Color(0.239, 0.608, 0.878)},
	{"key": &"stamina", "name": "体力", "color": Color(0.553, 0.761, 0.290)},
]
const BAR_WIDTH := 108.0
## 只在「未绑定」时才需要显示的占位值
const BAR_UNBOUND := -1.0

## ART09-D：展板把四条状态放在画面**右侧中部**（不是左下角）。
## 位置只用常量算，测试按锚点断言；`Margin/VBox/{VitalLabel,WarningLabel,InteractLabel}` 三条老路径保持不动。
const VITALS_WIDTH := 210.0
const VITALS_MARGIN := 24.0
const VITALS_CENTER_SHIFT := 46.0
const ICON_SIZE := 14.0

## 右下技能环：三个圆形**指示器**，只反映已有输入动作（`sprint`/`crouch`/`pounce`），不新增玩法。
## 物种没有该能力（例如鼠不能扑击）时按钮转禁用态 + `NOT-AVAILABLE` 提示。
const SKILL_ROWS := [
	{"key": &"sprint", "glyph": "冲", "hint": "Shift"},
	{"key": &"crouch", "glyph": "潜", "hint": "Ctrl"},
	{"key": &"pounce", "glyph": "扑", "hint": "左键"},
]
const SKILL_SIZE := 46.0
const SKILL_GAP := 10.0
const SKILL_MARGIN := 24.0

## 右上罗盘（朝向 = 玩家偏航；无玩家时指针朝上）
const COMPASS_SIZE := 84.0
const COMPASS_MARGIN := 20.0
const COMPASS_SCRIPT := "res://scripts/ui/compass_dial.gd"

## 可选：场景里直接指向一个身体（留空则用 `bind_player()`）
@export var player_path: NodePath = NodePath("")

var _player: AnimalBody = null
var _vital_label: Label = null
var _warning_label: Label = null
var _interact_label: Label = null
## `key` → {bar: ProgressBar, value: Label}（ART04 的条状显示）
var _bars: Dictionary = {}
## ART09-D：`key` → {panel: Panel, glyph: Label, hint: Label}（右下技能环指示器）
var _skills: Dictionary = {}
## ART09-D：右上罗盘（`compass_dial.gd`）
var _compass: Control = null


func _ready() -> void:
	_vital_label = get_node_or_null("Margin/VBox/VitalLabel") as Label
	_warning_label = get_node_or_null("Margin/VBox/WarningLabel") as Label
	_interact_label = get_node_or_null("Margin/VBox/InteractLabel") as Label
	_style_labels()
	_build_vitals_bars()
	_build_compass()
	_build_skill_ring()
	_build_toast()
	if not player_path.is_empty():
		var p := get_node_or_null(player_path)
		if p is AnimalBody:
			bind_player(p)
	refresh()


func _process(_delta: float) -> void:
	# **唯一**每帧读取的生存量：交互进度是连续量（其余全部信号驱动，见头注第 2 条）。
	# ART09-D 追加的两项同样只读玩家自身状态：罗盘朝向、技能指示器高亮。
	_refresh_interaction()
	_refresh_compass()
	_refresh_skills()
	# Toast 超时收口（T033）：真实毫秒对比，不跟帧率走
	if _toast_label != null and _toast_label.visible \
			and _toast_until_ms > 0 and GameClock.now_ms() > _toast_until_ms:
		_toast_label.visible = false


# ---------------------------------------------------------------------------
# 绑定
# ---------------------------------------------------------------------------

func bind_player(body: AnimalBody) -> void:
	unbind()
	_player = body
	if _player == null or not is_instance_valid(_player):
		refresh()
		return
	if _player.survival != null:
		if not _player.survival.changed.is_connected(_on_survival_changed):
			_player.survival.changed.connect(_on_survival_changed)
		if not _player.survival.warning_changed.is_connected(_on_warning_changed):
			_player.survival.warning_changed.connect(_on_warning_changed)
		if not _player.survival.died.is_connected(_on_survival_died):
			_player.survival.died.connect(_on_survival_died)
	if _player.interaction != null:
		var det := _player.interaction
		if not det.target_changed.is_connected(_on_target_changed):
			det.target_changed.connect(_on_target_changed)
		if not det.interaction_started.is_connected(_on_interaction_changed):
			det.interaction_started.connect(_on_interaction_changed)
		if not det.interaction_committed.is_connected(_on_interaction_changed):
			det.interaction_committed.connect(_on_interaction_changed)
		if not det.interaction_cancelled.is_connected(_on_interaction_changed):
			det.interaction_cancelled.connect(_on_interaction_changed)
	bound.emit(species_id())
	refresh()


func unbind() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = null
		return
	if _player.survival != null:
		var sc := _player.survival
		if sc.changed.is_connected(_on_survival_changed):
			sc.changed.disconnect(_on_survival_changed)
		if sc.warning_changed.is_connected(_on_warning_changed):
			sc.warning_changed.disconnect(_on_warning_changed)
		if sc.died.is_connected(_on_survival_died):
			sc.died.disconnect(_on_survival_died)
	if _player.interaction != null:
		var det := _player.interaction
		if det.target_changed.is_connected(_on_target_changed):
			det.target_changed.disconnect(_on_target_changed)
		if det.interaction_started.is_connected(_on_interaction_changed):
			det.interaction_started.disconnect(_on_interaction_changed)
		if det.interaction_committed.is_connected(_on_interaction_changed):
			det.interaction_committed.disconnect(_on_interaction_changed)
		if det.interaction_cancelled.is_connected(_on_interaction_changed):
			det.interaction_cancelled.disconnect(_on_interaction_changed)
	_player = null
	refresh()


func is_bound() -> bool:
	return _player != null and is_instance_valid(_player)


func species_id() -> StringName:
	if not is_bound() or _player.species_config == null:
		return &""
	return _player.species_config.species_id


# ---------------------------------------------------------------------------
# 只读显示
# ---------------------------------------------------------------------------

func refresh() -> void:
	_refresh_vitals()
	_refresh_warning()
	_refresh_interaction()


## 四项指标（当前 / 上限）；未绑定时用占位符
func status_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if not is_bound() or _player.survival == null:
		for name in ["生命", "饥饿", "水分", "体力"]:
			out.append("%s  —  /  —" % name)
		return out
	var st: SurvivalState = _player.survival.state
	var cfg: SpeciesConfig = _player.survival.config
	out.append("生命  %.0f  /  %.0f" % [st.health, cfg.max_health])
	out.append("饥饿  %.0f  /  %.0f" % [st.hunger, cfg.max_hunger])
	out.append("水分  %.0f  /  %.0f" % [st.thirst, cfg.max_thirst])
	out.append("体力  %.0f  /  %.0f" % [st.stamina, cfg.max_stamina])
	return out


## 低值警告（`Hunger/Thirst ≤ low_stat_threshold`，T015 语义）；无警告时为空
func warning_text() -> String:
	if not is_bound() or _player.survival == null:
		return ""
	if _player.survival.is_dead():
		return "已死亡"
	var low_h := _player.survival.is_low_hunger()
	var low_t := _player.survival.is_low_thirst()
	if low_h and low_t:
		return "饥饿 + 缺水"
	if low_h:
		return "饥饿"
	if low_t:
		return "缺水"
	return ""


## 交互提示（进行中带百分比；无目标时为空）
func interaction_text() -> String:
	if _interact_label == null:
		return ""
	return _interact_label.text


func interaction_visible() -> bool:
	return _interact_label != null and _interact_label.visible



## T062：**包内探针/断言用** —— 四条指标条的 `ProgressBar` 列表（只读，不改显示状态）。
## 为什么加它：导出包里读不到 UI 层级、外部窗口截图对叠加层又不可靠，
## 需要一个"从引擎侧问 HUD 存在不存在"的稳定接口。
func vital_bars() -> Array:
	var out: Array = []
	for key in _bars:
		var entry: Dictionary = _bars[key]
		var bar := entry.get("bar") as ProgressBar
		if bar != null:
			out.append(bar)
	return out
## HUD 当前显示的全部文本（断言用）
func hud_text() -> String:
	var parts := PackedStringArray()
	parts.append_array(status_lines())
	var w := warning_text()
	if not w.is_empty():
		parts.append(w)
	var i := interaction_text()
	if not i.is_empty():
		parts.append(i)
	return "\n".join(parts)


# ---------------------------------------------------------------------------
# Toast（T033 发现/解锁反馈，`Docs/Tasks/T033.md` D5）
# ---------------------------------------------------------------------------

## 顶部居中的临时提示文字。最小可读版：无动画、无弹窗、超时隐藏；
## 不进 `hud_text()`（不碰 T018 的 HUD 文本契约）。
const TOAST_FONT := 16
const TOAST_DURATION := 4.0

var _toast_label: Label = null
var _toast_until_ms := 0

func show_toast(text: String, duration: float = TOAST_DURATION) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	# 空文本 = 立即隐藏；非零时长 = 按真实毫秒截止（`_process` 里统一收口）
	var show := not text.is_empty() and duration > 0.0
	_toast_label.visible = show
	_toast_until_ms = GameClock.now_ms() + int(duration * 1000.0) if show else 0


func toast_text() -> String:
	return _toast_label.text if _toast_label != null else ""


func toast_visible() -> bool:
	return _toast_label.visible if _toast_label != null else false


func _build_toast() -> void:
	_toast_label = Label.new()
	_toast_label.name = "ToastLabel"
	_toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast_label.offset_top = 56.0
	_toast_label.offset_bottom = 82.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.add_theme_font_size_override("font_size", TOAST_FONT)
	# 暖金 + 深色描边：压在 3D 画面上也读得清（与菜单 GOLD 同族色，无动画）
	_toast_label.add_theme_color_override("font_color", Color(0.980, 0.855, 0.530))
	_toast_label.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.06, 0.92))
	_toast_label.add_theme_constant_override("outline_size", 5)
	_toast_label.visible = false
	add_child(_toast_label)


# ---------------------------------------------------------------------------
# 信号处理
# ---------------------------------------------------------------------------

func _on_survival_changed(_state: SurvivalState) -> void:
	_refresh_vitals()
	_refresh_warning()


func _on_warning_changed(_kind: StringName, _active: bool) -> void:
	_refresh_warning()


func _on_survival_died(_reason: StringName) -> void:
	_refresh_vitals()
	_refresh_warning()


func _on_target_changed(_interaction_id: String, _allowed: bool) -> void:
	_refresh_interaction()


func _on_interaction_changed(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	# 三个交互信号参数各不相同，统一收在这里后只做一次刷新
	_refresh_interaction()


# ---------------------------------------------------------------------------
# 内部刷新
# ---------------------------------------------------------------------------

func _refresh_vitals() -> void:
	if _vital_label != null:
		_vital_label.text = "\n".join(status_lines())
	_refresh_bars()

func _refresh_warning() -> void:
	if _warning_label == null:
		return
	var w := warning_text()
	_warning_label.text = w
	_warning_label.visible = not w.is_empty()


func _refresh_interaction() -> void:
	if _interact_label == null:
		return
	if not is_bound() or _player.interaction == null:
		_set_interact("")
		return
	var det := _player.interaction
	var target_id := det.current_target_id()
	if target_id.is_empty():
		_set_interact("")
		return
	if det.is_interacting():
		var pct := int(round(clampf(det.interaction_progress(), 0.0, 1.0) * 100.0))
		_set_interact("[%s] %s  %d%%" % [_current_action_name(det), target_id, pct])
		return
	var q: Dictionary = det.current_query()
	if not q.is_empty() and bool(q.get("allowed", false)):
		_set_interact("[%s] %s" % [_action_name_of(q), target_id])
		return
	_set_interact("")


func _set_interact(text: String) -> void:
	_interact_label.text = text
	_interact_label.visible = not text.is_empty()


func _current_action_name(det: InteractionDetector) -> String:
	return _action_name_of(det.current_query())


func _action_name_of(q: Dictionary) -> String:
	var action = q.get("action_id", &"")
	var key := StringName(action)
	if ACTION_NAMES.has(key):
		return String(ACTION_NAMES[key])
	var s := String(action)
	return s if not s.is_empty() else "交互"


## 纯样式（不影响任何游戏状态；为了截图能看清）
func _style_labels() -> void:
	for label in [_vital_label, _warning_label, _interact_label]:
		if label == null:
			continue
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		label.add_theme_constant_override("outline_size", 4)
	if _vital_label != null:
		_vital_label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.92))
	if _warning_label != null:
		_warning_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.30))
	if _interact_label != null:
		_interact_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))


# ---------------------------------------------------------------------------
# 四项指标条（ART04）
# ---------------------------------------------------------------------------

## 展板把四条状态放在**画面右侧中部**：这里是独立锚点容器，不再塞进左下的 `Margin/VBox`。
## 四行纯文字标签仍在 `Margin/VBox`（`status_lines()` / `hud_text()` 与 T018 断言继续可用），
## 只是 `visible = false`，避免同一信息在屏幕上出现两遍。
func _build_vitals_bars() -> void:
	var box := VBoxContainer.new()
	box.name = "VitalsBars"
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -(VITALS_WIDTH + VITALS_MARGIN)
	box.offset_right = -VITALS_MARGIN
	box.offset_top = VITALS_CENTER_SHIFT - 44.0
	box.offset_bottom = VITALS_CENTER_SHIFT + 44.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	for row in VITAL_ROWS:
		var key: StringName = row["key"]
		var color: Color = row["color"]
		var line := HBoxContainer.new()
		line.name = "Row_%s" % String(key)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 6)
		box.add_child(line)

		line.add_child(_make_vital_icon(key, color))

		var name_label := Label.new()
		name_label.name = "Name_%s" % String(key)
		name_label.text = String(row["name"])
		name_label.custom_minimum_size = Vector2(30.0, 0.0)
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", Color(0.878, 0.898, 0.867))
		name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		name_label.add_theme_constant_override("outline_size", 3)
		line.add_child(name_label)

		var bar := ProgressBar.new()
		bar.name = "Bar_%s" % String(key)
		bar.custom_minimum_size = Vector2(BAR_WIDTH, 8.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", _bar_style(Color(0.0, 0.0, 0.0, 0.55)))
		bar.add_theme_stylebox_override("fill", _bar_style(color))
		line.add_child(bar)

		var value_label := Label.new()
		value_label.name = "Value_%s" % String(key)
		value_label.text = "—"
		value_label.custom_minimum_size = Vector2(40.0, 0.0)
		value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.add_theme_font_size_override("font_size", 11)
		value_label.add_theme_color_override("font_color", Color(0.906, 0.918, 0.882))
		value_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		value_label.add_theme_constant_override("outline_size", 3)
		line.add_child(value_label)

		_bars[key] = {"bar": bar, "value": value_label}

	# 原来的四行纯文字退到幕后（内容仍随 `status_lines()` 更新，断言与 `hud_text()` 不受影响）
	if _vital_label != null:
		_vital_label.visible = false


# ---------------------------------------------------------------------------
# ART09-D：状态图标（程序化绘制，不引入图标资源）
# ---------------------------------------------------------------------------

## 14×14 的矢量图标：心 / 肉块 / 水滴 / 闪电。**程序化绘制**，不是图标素材，
## 所以不受第三方许可限制；形状与展板一致（红心、橙肉、蓝水滴、绿闪电）。
func _make_vital_icon(key: StringName, color: Color) -> Control:
	var icon := Control.new()
	icon.name = "Icon_%s" % String(key)
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func() -> void: _draw_vital_icon(icon, key, color))
	return icon


func _draw_vital_icon(canvas: Control, key: StringName, color: Color) -> void:
	var s := canvas.size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var m := minf(s.x, s.y)
	match key:
		&"health":
			# 心形：两个圆 + 下方三角
			var r := m * 0.26
			var cy := s.y * 0.38
			canvas.draw_circle(Vector2(s.x * 0.34, cy), r, color)
			canvas.draw_circle(Vector2(s.x * 0.66, cy), r, color)
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(s.x * 0.09, cy + r * 0.30),
				Vector2(s.x * 0.91, cy + r * 0.30),
				Vector2(s.x * 0.50, s.y * 0.95),
			]), color)
		&"hunger":
			# 肉块：圆形块 + 外伸的骨柄
			canvas.draw_circle(Vector2(s.x * 0.42, s.y * 0.56), m * 0.30, color)
			canvas.draw_line(Vector2(s.x * 0.60, s.y * 0.50),
				Vector2(s.x * 0.90, s.y * 0.22), color, 2.0, true)
		&"thirst":
			# 水滴：上方尖 + 下方圆
			canvas.draw_circle(Vector2(s.x * 0.50, s.y * 0.64), m * 0.26, color)
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(s.x * 0.50, s.y * 0.04),
				Vector2(s.x * 0.26, s.y * 0.64),
				Vector2(s.x * 0.74, s.y * 0.64),
			]), color)
		&"stamina":
			# 闪电：六点多边形
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(s.x * 0.60, s.y * 0.02),
				Vector2(s.x * 0.24, s.y * 0.58),
				Vector2(s.x * 0.46, s.y * 0.58),
				Vector2(s.x * 0.38, s.y * 0.98),
				Vector2(s.x * 0.78, s.y * 0.42),
				Vector2(s.x * 0.54, s.y * 0.42),
			]), color)
		_:
			canvas.draw_circle(s * 0.5, m * 0.3, color)


# ---------------------------------------------------------------------------
# ART09-D：右上罗盘
# ---------------------------------------------------------------------------

func _build_compass() -> void:
	var script := load(COMPASS_SCRIPT) as Script
	if script == null:
		return
	var dial := script.new() as Control
	if dial == null:
		return
	dial.name = "Compass"
	dial.anchor_left = 1.0
	dial.anchor_right = 1.0
	dial.offset_left = -(COMPASS_SIZE + COMPASS_MARGIN)
	dial.offset_right = -COMPASS_MARGIN
	dial.offset_top = COMPASS_MARGIN
	dial.offset_bottom = COMPASS_MARGIN + COMPASS_SIZE
	dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dial)
	_compass = dial


## 罗盘朝向 = 玩家偏航（只读）。没有玩家时指针朝上（北）。
func _refresh_compass() -> void:
	if _compass == null:
		return
	var yaw := 0.0
	if _player != null and is_instance_valid(_player):
		yaw = _player.global_rotation.y
	if _compass.has_method("set_heading"):
		_compass.call("set_heading", -yaw)


# ---------------------------------------------------------------------------
# ART09-D：右下技能环（指示器，不是新玩法）
# ---------------------------------------------------------------------------

func _build_skill_ring() -> void:
	var ring := HBoxContainer.new()
	ring.name = "SkillRing"
	ring.anchor_left = 1.0
	ring.anchor_right = 1.0
	ring.anchor_top = 1.0
	ring.anchor_bottom = 1.0
	ring.offset_left = -(SKILL_SIZE * SKILL_ROWS.size() + SKILL_GAP * (SKILL_ROWS.size() - 1) + SKILL_MARGIN)
	ring.offset_right = -SKILL_MARGIN
	ring.offset_top = -(SKILL_SIZE + SKILL_MARGIN)
	ring.offset_bottom = -SKILL_MARGIN
	ring.add_theme_constant_override("separation", int(SKILL_GAP))
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring)

	for row in SKILL_ROWS:
		var key: StringName = row["key"]
		var panel := Panel.new()
		panel.name = "Skill_%s" % String(key)
		panel.custom_minimum_size = Vector2(SKILL_SIZE, SKILL_SIZE)
		# 纯指示器：不吃鼠标（左键要留给真实的扑击动作）
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _skill_style(false, true))
		ring.add_child(panel)

		var column := VBoxContainer.new()
		column.anchor_right = 1.0
		column.anchor_bottom = 1.0
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", -2)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(column)

		var glyph := Label.new()
		glyph.name = "Glyph"
		glyph.text = String(row["glyph"])
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.add_theme_font_size_override("font_size", 16)
		glyph.add_theme_color_override("font_color", Color(0.949, 0.929, 0.882))
		glyph.add_theme_constant_override("outline_size", 3)
		glyph.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		column.add_child(glyph)

		var hint := Label.new()
		hint.name = "Hint"
		hint.text = String(row["hint"])
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.add_theme_font_size_override("font_size", 9)
		hint.add_theme_color_override("font_color", Color(0.72, 0.76, 0.72))
		column.add_child(hint)

		_skills[key] = {"panel": panel, "glyph": glyph, "hint": hint,
			"hint_text": String(row["hint"]), "active": false, "available": true}


func _skill_style(active: bool, available: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = int(SKILL_SIZE * 0.5)
	sb.corner_radius_top_right = int(SKILL_SIZE * 0.5)
	sb.corner_radius_bottom_left = int(SKILL_SIZE * 0.5)
	sb.corner_radius_bottom_right = int(SKILL_SIZE * 0.5)
	if not available:
		sb.bg_color = Color(0.020, 0.028, 0.028, 0.720)
		sb.border_color = Color(0.320, 0.340, 0.320, 0.480)
	elif active:
		sb.bg_color = Color(0.851, 0.588, 0.227, 0.920)
		sb.border_color = Color(1.0, 0.86, 0.56, 0.950)
	else:
		sb.bg_color = Color(0.055, 0.070, 0.070, 0.780)
		sb.border_color = Color(0.560, 0.470, 0.290, 0.700)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	return sb


## 只读玩家状态：高亮 = 该动作正在生效；不可用 = 该物种没有这个能力（鼠无扑击）。
func _refresh_skills() -> void:
	if _skills.is_empty():
		return
	var live := _player != null and is_instance_valid(_player)
	var cfg: SpeciesConfig = _player.species_config if live else null
	var sprint_on := live and _player.want_sprint
	var crouch_on := live and _player.is_crouching
	var pouncing := live and _player.action_state() == AnimalBody.ACT.POUNCING
	var can_pounce := cfg == null or cfg.can_pounce
	_apply_skill(&"sprint", sprint_on, true)
	_apply_skill(&"crouch", crouch_on, true)
	_apply_skill(&"pounce", pouncing, can_pounce)


func _apply_skill(key: StringName, active: bool, available: bool) -> void:
	var entry: Dictionary = _skills.get(key, {})
	if entry.is_empty():
		return
	if bool(entry["active"]) == active and bool(entry["available"]) == available:
		return
	entry["active"] = active
	entry["available"] = available
	_skills[key] = entry
	var panel := entry.get("panel") as Panel
	if panel != null:
		panel.add_theme_stylebox_override("panel", _skill_style(active, available))
		panel.tooltip_text = "" if available else "NOT-AVAILABLE：该物种不能扑击"
	var glyph := entry.get("glyph") as Label
	if glyph != null:
		glyph.add_theme_color_override("font_color",
			Color(0.949, 0.929, 0.882) if available else Color(0.42, 0.45, 0.42))
	var hint := entry.get("hint") as Label
	if hint != null:
		# 恢复可用时把按键提示放回去（换物种会走“不可用 → 可用”的来回）
		hint.text = String(entry.get("hint_text", hint.text)) if available else "不可用"


func _bar_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	sb.content_margin_left = 0.0
	sb.content_margin_right = 0.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	return sb


## 四条指标的当前值/上限（`BAR_UNBOUND` = 未绑定，显示占位符）
func _vital_pairs() -> Dictionary:
	var out := {}
	if not is_bound() or _player.survival == null:
		return out
	var st: SurvivalState = _player.survival.state
	var cfg: SpeciesConfig = _player.survival.config
	out[&"health"] = [st.health, cfg.max_health]
	out[&"hunger"] = [st.hunger, cfg.max_hunger]
	out[&"thirst"] = [st.thirst, cfg.max_thirst]
	out[&"stamina"] = [st.stamina, cfg.max_stamina]
	return out


func _refresh_bars() -> void:
	if _bars.is_empty():
		return
	var pairs := _vital_pairs()
	for row in VITAL_ROWS:
		var key: StringName = row["key"]
		var entry: Dictionary = _bars.get(key, {})
		var bar := entry.get("bar") as ProgressBar
		var value_label := entry.get("value") as Label
		if bar == null or value_label == null:
			continue
		if not pairs.has(key):
			bar.value = 0.0
			value_label.text = "—"
			continue
		var pair: Array = pairs[key]
		var cur := float(pair[0])
		var max_v := maxf(0.0001, float(pair[1]))
		bar.max_value = max_v
		bar.value = clampf(cur, 0.0, max_v)
		value_label.text = "%.0f" % cur
