class_name PlayerHud
extends Control
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
const BAR_WIDTH := 132.0
## 只在「未绑定」时才需要显示的占位值
const BAR_UNBOUND := -1.0

## 可选：场景里直接指向一个身体（留空则用 `bind_player()`）
@export var player_path: NodePath = NodePath("")

var _player: AnimalBody = null
var _vital_label: Label = null
var _warning_label: Label = null
var _interact_label: Label = null
## `key` → {bar: ProgressBar, value: Label}（ART04 的条状显示）
var _bars: Dictionary = {}


func _ready() -> void:
	_vital_label = get_node_or_null("Margin/VBox/VitalLabel") as Label
	_warning_label = get_node_or_null("Margin/VBox/WarningLabel") as Label
	_interact_label = get_node_or_null("Margin/VBox/InteractLabel") as Label
	_style_labels()
	_build_vitals_bars()
	if not player_path.is_empty():
		var p := get_node_or_null(player_path)
		if p is AnimalBody:
			bind_player(p)
	refresh()


func _process(_delta: float) -> void:
	# **唯一**每帧读取：交互进度是连续量（其余全部信号驱动，见头注第 2 条）
	_refresh_interaction()


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

## 在 `Margin/VBox` 里、四行文字**之前**插入一排指标条。
## 文字标签保留（`status_lines()` 与断言继续可用），但视觉上由条承担，避免同一信息重复两遍。
func _build_vitals_bars() -> void:
	if _vital_label == null:
		return
	var holder := _vital_label.get_parent()
	if holder == null:
		return
	var box := VBoxContainer.new()
	box.name = "VitalsBars"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	holder.add_child(box)
	holder.move_child(box, 0)

	for row in VITAL_ROWS:
		var key: StringName = row["key"]
		var line := HBoxContainer.new()
		line.name = "Row_%s" % String(key)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 6)
		box.add_child(line)

		var name_label := Label.new()
		name_label.text = String(row["name"])
		name_label.custom_minimum_size = Vector2(30.0, 0.0)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", Color(0.878, 0.898, 0.867))
		name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		name_label.add_theme_constant_override("outline_size", 3)
		line.add_child(name_label)

		var bar := ProgressBar.new()
		bar.name = "Bar_%s" % String(key)
		bar.custom_minimum_size = Vector2(BAR_WIDTH, 9.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", _bar_style(Color(0.0, 0.0, 0.0, 0.55)))
		bar.add_theme_stylebox_override("fill", _bar_style(row["color"]))
		line.add_child(bar)

		var value_label := Label.new()
		value_label.name = "Value_%s" % String(key)
		value_label.text = "—"
		value_label.custom_minimum_size = Vector2(46.0, 0.0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.add_theme_font_size_override("font_size", 12)
		value_label.add_theme_color_override("font_color", Color(0.906, 0.918, 0.882))
		value_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		value_label.add_theme_constant_override("outline_size", 3)
		line.add_child(value_label)

		_bars[key] = {"bar": bar, "value": value_label}

	# 原来的四行纯文字退到幕后（内容仍随 `status_lines()` 更新，断言与 `hud_text()` 不受影响）
	_vital_label.visible = false


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
