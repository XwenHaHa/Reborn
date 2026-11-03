class_name MainMenu
extends Control
## 主菜单 + 物种选择（ART04，视觉与动画专项整改 V1 的阶段 3）
##
## 依据：`配套要求.md` §1「猫和鼠是首批可玩物种，禁止把猫鼠专属的 UI 硬编码」、
## §2「真实的 3D 生态场景作为背景；物种选择采用**数据驱动**的卡片列表；
##      新增物种应通过物种配置、模型、动画和能力数据接入」、§5「保留现有系统，先审计再改」。
##
## 三条纪律：
##   1. **数据驱动**：卡片、名字、定位语、数值全部来自 `SpeciesConfig`（`resources/species/*.tres`）。
##      本文件**不出现** `"Cat"` / `"Mouse"` 等物种名，也不写死物种数量。
##   2. **只做界面**：本文件不建玩家、不产生态、不写 `GameState`；选中后只发 `species_committed`，
##      真正的出生仍走 `MainEntry.select_species()` → `LifeCycle.begin_spawn()`。
##   3. **不是 CanvasLayer**：`main.tscn` 的断言要求正式场景里没有 `CanvasLayer`（T030 A15），
##      所以这里是普通 `Control`，由 `MainEntry` 在运行期建立。
##
## 卡片预览是每个物种一个 `SubViewport`（自有 `World3D`），直接实例化 `SpeciesConfig.visual_scene`：
## 模型换了、加了新物种，预览跟着变，UI 代码不用动。

## 玩家确认「进入世界」；`species_id` 来自卡片对应的 `SpeciesConfig`
signal species_committed(species_id: StringName)
## 玩家点了「退出」
signal quit_requested
## 设置项变化（`key` 只有 `sensitivity` / `fov`；是否持久化属后续任务，本轮只作用于本局）
signal setting_changed(key: StringName, value: float)
## 当前选中的物种变了（ART06：`MainEntry` 用它换菜单主视觉；只发选中，不触发出生）
signal selection_changed(species_id: StringName)

enum Page { MAIN, SPECIES }

## 未来开放物种：**尚未实现**，只在界面上占位（`配套要求.md` §2 允许「标记为未来开放」）。
## 真源不在这里 —— 这些物种一旦落地，就该有 `resources/species/*.tres` 并自动出现在可玩列表里。
const FUTURE_SPECIES := [
	{"name": "兔", "tagline": "草食性动物", "note": "以群体为单位活动"},
	{"name": "鸟", "tagline": "空中与地面双重生存", "note": "善于侦察与飞行"},
	{"name": "狐", "tagline": "机敏的猎手", "note": "擅长潜行与追踪"},
]

const PAGE_TITLE := "轮生"
const PAGE_SUBTITLE := "R E B O R N"
const TAGLINE := "不同的生命 · 同一个世界"
const TAGLINE_2 := "在轮回中相遇 · 在生存中延续"
const VERSION_TAG := "v0.1.0 · MVP Demo"

## 颜色：与 `BoardTokens` 同族；`run_art09_tokens.gd` 按 0.03 容差核对，防止两处各调一套
const COLOR_TEXT := Color(0.949, 0.929, 0.882)
const COLOR_DIM := Color(0.596, 0.639, 0.612)
const COLOR_FAINT := Color(0.396, 0.443, 0.427)
const COLOR_ACCENT := Color(0.851, 0.588, 0.227)
const COLOR_ACCENT_DIM := Color(0.431, 0.325, 0.157)
## ART10：面板底从"暗青灰"往"深灰蓝"偏（展板面板是偏蓝的深色磨砂玻璃；
## vision 判读旧值透出草绿后"浑浊发青"）。GOLD 强调色不动（令牌契约钉死）。
const COLOR_PANEL := Color(0.043, 0.055, 0.075, 0.900)
const COLOR_PANEL_SEL := Color(0.085, 0.105, 0.135, 0.965)

## 缩略图边长/超采样：真源在 `BoardTokens`，这里只做同值别名（断言守着，见 `run_art09_tokens.gd`）
const PREVIEW_PX := 64
const PREVIEW_SUPERSAMPLE := 2

var _configs: Array[SpeciesConfig] = []
var _selected: StringName = &""
var _page: int = Page.MAIN

var _scrim: ColorRect = null
var _rail_shade: Panel = null
var _left_column: Control = null
var _right_column: Control = null
var _main_buttons: VBoxContainer = null
var _species_buttons: VBoxContainer = null
var _record_label: Label = null
var _hint_label: Label = null
var _cards_box: VBoxContainer = null
var _mvp_note: Control = null
var _locked_box: VBoxContainer = null

## 物种选择页（ART09-C）：左侧大卡 + 底部缩略图行
var _species_card: Panel = null
var _card_portrait: TextureRect = null
var _card_name: Label = null
var _card_tagline: Label = null
var _card_note: Label = null
var _card_stats: Label = null
var _strip: HBoxContainer = null
## `species_id` → 卡内 ProgressBar / 数值 Label
var _card_bars: Dictionary = {}
## `species_id` → 缩略图槽
var _strip_slots: Dictionary = {}
## `species_id` → 缩略图槽里的 SubViewport（与右栏卡片分开登记：页面上两者不会同时可见）
var _strip_previews: Dictionary = {}
var _settings_panel: PanelContainer = null
var _center_showcase: Control = null

## `species_id` → {card, name_label, viewport, pivot, animation}
var _cards: Dictionary = {}
## 预览用的慢速自转速度（弧度/秒）：让卡片看起来是活的，但不足以分散注意力
var _spin_speed := 0.35
## 已存盘的设置（`GameSettings` 读出来的）；只用于回填滑块初值
var _initial_settings: Dictionary = {}
## 设置滑块的当前值（`settings_values()` 读它，证据/断言用）
var _sliders: Dictionary = {}
## T033 解锁集：`species_id` → true。真源在 `GameState.unlocked_species`，
## 由 `MainEntry` 通过 `build(..., unlocked_ids)` / `set_unlocked()` 推进来（本文件不读 `GameState`）
var _unlocked: Dictionary = {}
## 最近一次「点选/按键选择锁定物种」的反馈文字（断言/证据用）
var _lock_feedback := ""


## 灵敏度基准（= `AnimalBody.mouse_sensitivity` 的默认值）；设置里的滑块是**倍数**
const SENSITIVITY_BASE := 0.0025
const SETTINGS_SENSITIVITY := 1.0
## FOV 滑块的起点（真源仍是每个物种配置自己的 `fov`；不动滑块就不覆盖）
const SETTINGS_FOV := 90.0
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)


# ---------------------------------------------------------------------------
# 对外
# ---------------------------------------------------------------------------

## 建立界面（必须在**入树之后**调用：卡片预览要用 `look_at` 与 `World3D`）。
## `initial_settings` 来自 `GameSettings`（已存盘的灵敏度/FOV），只用来回填滑块初值。
## `unlocked_ids`（T033）= 当前解锁的物种：**缺省空数组 = 全部可玩**（不传解锁信息的
## 回退兼容，取证工具/旧调用方不受影响）；正式路径由 `MainEntry` 显式传入
## `GameState.unlocked_species` 的内容。
func build(configs: Array[SpeciesConfig], initial_settings: Dictionary = {},
		unlocked_ids: Array = []) -> void:
	_configs = configs.duplicate()
	_initial_settings = initial_settings.duplicate()
	_unlocked.clear()
	if unlocked_ids.is_empty():
		for cfg in _configs:
			_unlocked[cfg.species_id] = true
	else:
		for id in unlocked_ids:
			_unlocked[id] = true
	_clear()

	_build_scrim()
	_build_left_column()
	_build_species_card()
	_build_right_column()
	_build_mvp_note()
	_build_hint()
	_build_settings()
	_apply_lock_states()
	# 默认选中第一个**已解锁**物种（正式模式下锁定物种不可被默认选中，数据驱动）
	var pick := _first_unlocked_id()
	if pick != &"":
		select_species(pick)
	show_page(Page.MAIN)


## 打开主菜单（`previous_text` 非空时显示「上一世」摘要）
func open_menu(previous_text: String = "") -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_set_previews_running(true)
	_settings_panel.visible = false
	_apply_lock_states()   # 解锁集可能在上次打开后变化；呈现层幂等刷新
	if _record_label != null:
		_record_label.text = previous_text
		_record_label.visible = not previous_text.is_empty()
	show_page(Page.MAIN)
	_refresh_cards()


func close_menu() -> void:
	visible = false
	set_process(false)
	_set_previews_running(false)


## 切换页面：`Page.MAIN` = 标题 + 开始/物种/设置/退出；`Page.SPECIES` = 进入世界/返回 + 卡片
func show_page(page: int) -> void:
	_page = page
	_settings_panel.visible = false
	var main := page == Page.MAIN
	if _main_buttons != null:
		_main_buttons.visible = main
	if _species_buttons != null:
		_species_buttons.visible = not main
	if _species_card != null:
		_species_card.visible = not main
	# 物种页用左侧大卡替代原来的「标题 + 四按钮」栏
	if _left_column != null:
		_left_column.visible = main
	# 展板的物种选择界面没有右栏和 MVP 说明：那两块版面留给大卡与主视觉
	if _right_column != null:
		_right_column.visible = main
	if _rail_shade != null:
		_rail_shade.visible = main
	if _mvp_note != null:
		_mvp_note.visible = main
	if _cards_box != null:
		_cards_box.visible = true
	_refresh_cards()
	_refresh_hint()


## 选中一个物种（T033）：锁定物种被拒（false）并给文字反馈，选中不变。
func select_species(species_id: StringName) -> bool:
	if _index_of(species_id) < 0:
		return false
	if is_locked(species_id):
		_notify_locked(species_id)
		return false
	var changed := _selected != species_id
	_selected = species_id
	_refresh_cards()
	if changed:
		selection_changed.emit(_selected)
	return true


# ---------------------------------------------------------------------------
# 解锁集（T033，`Docs/Tasks/T033.md` D2/D3）
# ---------------------------------------------------------------------------

## 锁定卡上的两句固定文案（不写物种名；物种名来自 `SpeciesConfig.display_title()`）
const LOCK_TAGLINE := "尚未解锁"
const LOCK_NOTE := "用已解锁的动物探索世界 · 发现线索后解锁"

## 是否锁定（供断言/调用方读取）。出生权威门在 `LifeCycle.begin_spawn`；
## 这里只把**选择呈现层**收紧到同一份解锁集。
func is_locked(species_id: StringName) -> bool:
	return _index_of(species_id) >= 0 and not bool(_unlocked.get(species_id, false))


## 当前锁定的物种（`species_id` 排序；断言/证据用）
func locked_list() -> Array[StringName]:
	var out: Array[StringName] = []
	for cfg in _configs:
		if is_locked(cfg.species_id):
			out.append(cfg.species_id)
	return out


## 显式覆盖解锁集（空数组 = 全部锁定）。由 `MainEntry` 在解锁状态变化时调用。
## 与 `build()` 的 `unlocked_ids` 缺省参数（空 = **全部可玩**）语义相反——
## 显式调用不做回退兼容，避免"忘传解锁集 = 全部放行"的坑。
func set_unlocked(ids: Array) -> void:
	_unlocked.clear()
	for id in ids:
		_unlocked[id] = true
	_apply_lock_states()
	# 防御：选中项因解锁集变化而锁定（正常流程不会发生）→ 回落到第一个已解锁物种
	if _selected != &"" and is_locked(_selected):
		_selected = &""
		var pick := _first_unlocked_id()
		if pick != &"":
			select_species(pick)
		_refresh_cards()


## 最近一次「点选/按键选择锁定物种」的反馈文字（断言/证据用；不做动画，只做可读）
func last_lock_feedback() -> String:
	return _lock_feedback


## 第一个已解锁物种（无则 `&""`）
func _first_unlocked_id() -> StringName:
	for cfg in _configs:
		if not is_locked(cfg.species_id):
			return cfg.species_id
	return &""


## 锁定反馈（D3）：明确告诉玩家"这个物种还没解锁"；选中不变、不出生、无动画
func _notify_locked(species_id: StringName) -> void:
	var i := _index_of(species_id)
	var title := _configs[i].display_title() if i >= 0 else String(species_id)
	_lock_feedback = "「%s」%s · %s" % [title, LOCK_TAGLINE, LOCK_NOTE]
	if _hint_label != null:
		_hint_label.text = _lock_feedback
	print("MENU|locked_feedback|%s" % String(species_id))


## 把当前解锁集套到已建好的卡片/缩略图槽上（锁定只是**呈现层**差异：
## 结构不变，压暗 + 换两句文案 + 悬停提示；解锁时复原）
func _apply_lock_states() -> void:
	for cfg in _configs:
		var id := cfg.species_id
		var locked := is_locked(id)
		var entry: Dictionary = _cards.get(id, {})
		var card := entry.get("card") as Control
		if card != null:
			card.modulate = Color(0.45, 0.45, 0.45, 1.0) if locked else Color(1.0, 1.0, 1.0, 1.0)
			card.tooltip_text = "%s %s" % [LOCK_TAGLINE, LOCK_NOTE] if locked else ""
			var tag := card.get_node_or_null("Row/Text/Tagline") as Label
			if tag != null:
				tag.text = LOCK_TAGLINE if locked else cfg.display_tagline
			var note := card.get_node_or_null("Row/Text/Note") as Label
			if note != null:
				note.text = LOCK_NOTE if locked else cfg.display_note
		var slot := _strip_slots.get(id) as Control
		if slot != null:
			slot.modulate = Color(0.55, 0.55, 0.55, 1.0) if locked else Color(1.0, 1.0, 1.0, 1.0)
			slot.tooltip_text = "%s %s" % [LOCK_TAGLINE, LOCK_NOTE] if locked else ""

func selected_species() -> StringName:
	return _selected


## 当前选中物种的配置（无则 null）
func selected_config() -> SpeciesConfig:
	var i := _index_of(_selected)
	return _configs[i] if i >= 0 else null


## 当前页（供证据/断言读取）
func current_page() -> int:
	return _page


## 玩家确认进入世界（按钮 / 回车都走这里）
func commit() -> void:
	if _selected == &"":
		return
	if _page != Page.SPECIES:
		show_page(Page.SPECIES)
		return
	species_committed.emit(_selected)


## 卡片文本（证据/断言用）：`<标题>|<定位语>|<备注>`
func card_text(species_id: StringName) -> String:
	var i := _index_of(species_id)
	if i < 0:
		return ""
	var cfg := _configs[i]
	return "%s|%s|%s" % [cfg.display_title(), cfg.display_tagline, cfg.display_note]


## 卡片顺序（= 由 `resources/species/*.tres` 发现的顺序，证据/断言用）
func species_order() -> Array[StringName]:
	var out: Array[StringName] = []
	for cfg in _configs:
		out.append(cfg.species_id)
	return out


func set_previous_record(text: String) -> void:
	if _record_label != null:
		_record_label.text = text
		_record_label.visible = not text.is_empty()



## 打开/关闭设置面板（对外：证据工具与后续 UI 复用）
func open_settings(on: bool) -> void:
	if _settings_panel == null:
		return
	_settings_panel.visible = on and visible


## 设置滑块的当前值（键与 `GameSettings` 一致；证据/断言用）
func settings_values() -> Dictionary:
	var out := {}
	for key in _sliders.keys():
		out[key] = float((_sliders[key] as HSlider).value)
	return out


## 程序化改设置（设置面板/测试共用一条路径：改滑块 → 发 `setting_changed`）
func set_setting(key: StringName, value: float) -> void:
	if not _sliders.has(key):
		return
	var slider := _sliders[key] as HSlider
	if slider != null:
		slider.value = value

# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _settings_panel.visible:
			_settings_panel.visible = false
		elif _page == Page.SPECIES:
			show_page(Page.MAIN)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		commit()
		get_viewport().set_input_as_handled()
		return
	# 数字键 1..N：直接选中第 N 个物种（与 `life_select_1/2` 的设置标签一致，
	# 但这里只**选中**，进入世界还要再按回车 —— 避免误按直接出生）。
	# T033：锁定物种不选中，只给反馈（选中不变、不出生、无动画）
	for i in _configs.size():
		var action := "life_select_%d" % (i + 1)
		if InputMap.has_action(action) and event.is_action_pressed(action):
			var id := _configs[i].species_id
			if not is_locked(id):
				select_species(id)
				show_page(Page.SPECIES)
			else:
				_notify_locked(id)
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	for id in _cards.keys():
		var card: Dictionary = _cards[id]
		var pivot := card.get("pivot") as Node3D
		if pivot != null and is_instance_valid(pivot):
			pivot.rotate_y(_spin_speed * delta)


# ---------------------------------------------------------------------------
# 构建：底图与两列
# ---------------------------------------------------------------------------

func _build_scrim() -> void:
	# 展板：背景是实拍级森林溪谷，文字直接压在照片上。这里背景是真实 3D 关卡
	# + CC0 森林天空球（`BoardTokens.ASSET_SKY_HDRI`）；等阶段 E 的 `l_ravine_board`
	# 出来以后，这块换成那台机位渲染的关键图（见 `Docs/BoardArtPipeline.md`）。
	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = BoardTokens.SCRIM
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)

	# 左栏：横向渐变压暗（展板是照片自然变暗，不是一块矩形面板）
	var left_shade := TextureRect.new()
	left_shade.name = "LeftPanelShade"
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.008, 0.016, 0.016, 0.94))
	ramp.set_color(1, Color(0.008, 0.016, 0.016, 0.0))
	var ramp_tex := GradientTexture2D.new()
	ramp_tex.gradient = ramp
	ramp_tex.width = 256
	ramp_tex.height = 8
	ramp_tex.fill_from = Vector2(0.0, 0.0)
	ramp_tex.fill_to = Vector2(1.0, 0.0)
	left_shade.texture = ramp_tex
	left_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left_shade.stretch_mode = TextureRect.STRETCH_SCALE
	left_shade.anchor_bottom = 1.0
	left_shade.offset_right = BoardTokens.LEFT_WIDTH + 210.0
	left_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left_shade)

	# 右栏：深色玻璃卡片列（展板右栏是明显的一块深色底板）
	var right_panel := Panel.new()
	right_panel.name = "RightRailShade"
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -BoardTokens.RAIL_WIDTH
	right_panel.offset_right = 0.0
	right_panel.add_theme_stylebox_override("panel", _rail_style())
	right_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right_panel)
	_rail_shade = right_panel

func _build_left_column() -> void:
	var margin := MarginContainer.new()
	margin.name = "LeftPanel"
	margin.anchor_bottom = 1.0
	margin.offset_right = BoardTokens.LEFT_WIDTH
	margin.add_theme_constant_override("margin_left", int(BoardTokens.CONTENT_MARGIN_LEFT))
	margin.add_theme_constant_override("margin_top", int(BoardTokens.CONTENT_MARGIN_TOP))
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 42)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_left_column = margin

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# 书法主标题：用系统行楷（`BoardTokens.title_font()`）。字体文件不进仓库——
	# 华文行楷不可再分发，运行时取系统字体，换机器没有就自动退回默认字重。
	var title := _label(PAGE_TITLE, BoardTokens.FONT_TITLE, COLOR_TEXT)
	title.name = "TitleCalligraphy"
	title.add_theme_font_override("font", BoardTokens.title_font())
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	column.add_child(title)

	# 英文标题：展板是金色 + 大字距（Label 没有 tracking，`PAGE_SUBTITLE` 里用空格代替）
	var latin := _label(PAGE_SUBTITLE, BoardTokens.FONT_TITLE_LATIN, COLOR_ACCENT)
	latin.name = "TitleLatin"
	latin.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	latin.add_theme_constant_override("outline_size", 4)
	column.add_child(latin)

	# 细金线：展板英文标题下的分隔线
	var rule := ColorRect.new()
	rule.name = "TitleRule"
	rule.color = Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.45)
	rule.custom_minimum_size = Vector2(BoardTokens.TITLE_RULE_W, 1.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	column.add_child(_spacer(20))
	column.add_child(_label(TAGLINE, BoardTokens.FONT_TAGLINE, Color(0.930, 0.875, 0.730)))
	column.add_child(_label(TAGLINE_2, BoardTokens.FONT_TAGLINE_SMALL, COLOR_DIM))
	column.add_child(_spacer(30))

	_main_buttons = _button_column()
	_main_buttons.name = "MainButtons"
	column.add_child(_main_buttons)

	var start := _button("开始游戏", true)
	start.name = "StartButton"
	start.pressed.connect(func() -> void: commit())
	_main_buttons.add_child(start)
	var pick := _button("物种选择", false)
	pick.name = "SpeciesButton"
	pick.pressed.connect(func() -> void: show_page(Page.SPECIES))
	_main_buttons.add_child(pick)
	var settings := _button("设置", false)
	settings.name = "SettingsButton"
	settings.pressed.connect(_toggle_settings)
	_main_buttons.add_child(settings)
	var quit := _button("退出", false)
	quit.name = "QuitButton"
	quit.pressed.connect(func() -> void: quit_requested.emit())
	_main_buttons.add_child(quit)

	# ART09-C：物种页的按钮已搬进左侧大卡（`_build_species_card()`），
	# 左栏只保留主菜单的四按钮，避免两套按钮组同时占位。

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(filler)

	_record_label = _label("", 13, Color(0.796, 0.749, 0.612))
	_record_label.name = "PreviousRecord"
	_record_label.visible = false
	_record_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_record_label)
	column.add_child(_label(VERSION_TAG, 12, COLOR_FAINT))


# ---------------------------------------------------------------------------
# 构建：物种选择大卡（ART09-C，展板「物种选择界面」）
# ---------------------------------------------------------------------------

## 展板第二块：左侧一张大卡（名字 / 定位 / 一句描述 / 四条状态）+ 底部缩略图行 + 金色开始按钮。
## 与展板的**已知偏差**：展板把动物大图放在卡内右侧；这里那张大图由 `MainEntry` 的中央 3D 主视觉承担，
## 因为菜单相机是世界空间节点、`MenuCamera` / `MenuFill` 是 ART08 契约，不能塞进 `Control`。
func _build_species_card() -> void:
	var panel := Panel.new()
	panel.name = "SpeciesCard"
	panel.offset_left = BoardTokens.SPECIES_CARD_X
	panel.offset_top = BoardTokens.SPECIES_CARD_Y
	panel.offset_right = BoardTokens.SPECIES_CARD_X + BoardTokens.SPECIES_CARD_W
	panel.offset_bottom = BoardTokens.SPECIES_CARD_Y + BoardTokens.SPECIES_CARD_H
	panel.add_theme_stylebox_override("panel", _species_card_style())
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	_species_card = panel

	# 大卡背景：展板的卡内是动物大图。这里用该物种的**肖像图**铺底（无肖像时保持纯色面板）
	var card_portrait := TextureRect.new()
	card_portrait.name = "CardPortrait"
	card_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_portrait.modulate = Color(1.0, 1.0, 1.0, 0.28)
	card_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_portrait.visible = false
	panel.add_child(card_portrait)
	_card_portrait = card_portrait
	# 窗口变窄/变矮时把大卡收回视口内（960×540 实测会压出下边界）
	if not get_viewport().size_changed.is_connected(_layout_species_card):
		get_viewport().size_changed.connect(_layout_species_card)

	var margin := MarginContainer.new()
	margin.name = "CardBody"
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	_card_name = _label("", 38, BoardTokens.TEXT)
	_card_name.name = "CardName"
	_card_name.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_card_name.add_theme_constant_override("shadow_offset_x", 2)
	_card_name.add_theme_constant_override("shadow_offset_y", 2)
	column.add_child(_card_name)

	_card_tagline = _label("", 15, BoardTokens.GOLD)
	_card_tagline.name = "CardTagline"
	column.add_child(_card_tagline)

	_card_note = _label("", 13, BoardTokens.TEXT_DIM)
	_card_note.name = "CardNote"
	_card_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_card_note)

	column.add_child(_spacer(12))
	for row in BoardTokens.VITAL_ROWS:
		column.add_child(_vital_row(row))

	column.add_child(_spacer(8))
	_card_stats = _label("", 12, BoardTokens.TEXT_FAINT)
	_card_stats.name = "CardStats"
	_card_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_card_stats)

	var filler := Control.new()
	filler.name = "Filler"
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(filler)

	# 底部缩略图行（展板：5 个方图；可玩的可点，未来的加「?」且不可点）
	_strip = HBoxContainer.new()
	_strip.name = "SpeciesStrip"
	_strip.add_theme_constant_override("separation", 8)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_strip)
	for cfg in _configs:
		_strip.add_child(_make_strip_slot(cfg))
	for entry in FUTURE_SPECIES:
		_strip.add_child(_make_locked_slot(entry))

	column.add_child(_spacer(8))
	_species_buttons = _button_column()
	_species_buttons.name = "SpeciesButtons"
	_species_buttons.visible = false
	column.add_child(_species_buttons)
	var enter := _button("开始游戏", true)
	enter.name = "EnterButton"
	enter.pressed.connect(func() -> void: commit())
	_species_buttons.add_child(enter)
	var back := _button("返回", false)
	back.name = "BackButton"
	back.pressed.connect(func() -> void: show_page(Page.MAIN))
	_species_buttons.add_child(back)
	_layout_species_card()


## 一条状态：色块 + 名称 + 进度条 + 数值。**只展示物种的初始上限**（出生即满），
## 不读 `SurvivalState`，也不参与任何生存计算。
func _vital_row(row: Dictionary) -> Control:
	var key := StringName(row["key"])
	var box := HBoxContainer.new()
	box.name = "Vital_%s" % String(key)
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var chip := ColorRect.new()
	chip.name = "Chip"
	chip.color = row["color"] as Color
	chip.custom_minimum_size = Vector2(10.0, 10.0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(chip)

	var name_label := _label(String(row["name"]), 12, BoardTokens.TEXT_DIM)
	name_label.name = "Name"
	name_label.custom_minimum_size = Vector2(32.0, 0.0)
	box.add_child(name_label)

	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(140.0, 8.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.add_theme_stylebox_override("background", _bar_bg_style())
	bar.add_theme_stylebox_override("fill", _bar_fill_style(row["color"] as Color))
	box.add_child(bar)

	var value := _label("100 / 100", 11, BoardTokens.TEXT_DIM)
	value.name = "Value"
	value.custom_minimum_size = Vector2(56.0, 0.0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value)

	_card_bars[key] = {"bar": bar, "value": value}
	return box


## 可玩物种的缩略图槽：点击只**选中**（留在本页），真正开局仍走金色「开始游戏」
func _make_strip_slot(cfg: SpeciesConfig) -> Control:
	var id := cfg.species_id
	var preview: Control = _make_preview(cfg) if cfg.display_portrait == null else null
	var content: Control = preview if preview != null else _make_portrait(cfg)
	var frame := _thumb_frame(content, "Strip_%s" % String(id), BoardTokens.STRIP_SLOT)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (event as InputEventMouseButton).pressed:
			select_species(id)
	)
	_strip_slots[id] = frame
	var vp: SubViewport = null
	if preview != null and preview.has_meta("sub_viewport"):
		vp = preview.get_meta("sub_viewport") as SubViewport
	if vp != null:
		_strip_previews[id] = vp
	return frame


## 未来物种的缩略图槽：同样大小、内容为「?」，**不可点**
func _make_locked_slot(entry: Dictionary) -> Control:
	var name := String(entry.get("name", "?"))
	var mark := _label("?", 22, BoardTokens.TEXT_FAINT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var frame := _thumb_frame(mark, "StripLocked_%s" % name, BoardTokens.STRIP_SLOT)
	frame.tooltip_text = "未来开放：%s" % String(entry.get("note", ""))
	return frame


## 选中态：名字变金 + 缩略图槽换金边
func _refresh_species_card() -> void:
	var cfg := selected_config()
	if cfg == null or _species_card == null:
		return
	if _card_name != null:
		_card_name.text = cfg.display_title()
	if _card_portrait != null:
		_card_portrait.texture = cfg.display_portrait
		_card_portrait.visible = cfg.display_portrait != null
	if _card_tagline != null:
		_card_tagline.text = cfg.display_tagline
	if _card_note != null:
		_card_note.text = cfg.display_note
	if _card_stats != null:
		_card_stats.text = _stat_line(cfg)
	var maxima := {
		&"health": cfg.max_health,
		&"hunger": cfg.max_hunger,
		&"thirst": cfg.max_thirst,
		&"stamina": cfg.max_stamina,
	}
	for key in _card_bars.keys():
		var entry: Dictionary = _card_bars[key]
		var bar := entry.get("bar") as ProgressBar
		var value := entry.get("value") as Label
		var top := maxf(1.0, float(maxima.get(key, 100.0)))
		if bar != null:
			bar.max_value = top
			bar.value = top
		if value != null:
			value.text = "%d / %d" % [int(top), int(top)]
	for id in _strip_slots.keys():
		var frame := _strip_slots[id] as Control
		if frame != null:
			frame.add_theme_stylebox_override(
				"panel", _thumb_style(StringName(id) == _selected)
			)


## 把大卡收进当前视口：1280×720 用令牌常量，窄/矮窗口按可用空间收缩（不越界、不压右栏）
func _layout_species_card() -> void:
	if _species_card == null:
		return
	var vp := get_viewport_rect().size
	var w := clampf(vp.x - BoardTokens.SPECIES_CARD_X - 16.0,
		BoardTokens.SPECIES_CARD_W * 0.72, BoardTokens.SPECIES_CARD_W)
	var h := clampf(vp.y - BoardTokens.SPECIES_CARD_Y - 16.0,
		BoardTokens.SPECIES_CARD_H * 0.72, BoardTokens.SPECIES_CARD_H)
	_species_card.offset_right = BoardTokens.SPECIES_CARD_X + w
	_species_card.offset_bottom = BoardTokens.SPECIES_CARD_Y + h


func _species_card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BoardTokens.PANEL
	sb.border_color = BoardTokens.RAIL_BORDER
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	return sb


func _bar_bg_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb


func _bar_fill_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb


func _build_right_column() -> void:
	# 展板右栏：一块深色玻璃底板，里面是同款「照片卡」——可玩物种在上，
	# 未来物种在下（压暗、不可点），底部一行「更多物种·敬请期待」。
	var margin := MarginContainer.new()
	margin.name = "SpeciesRail"
	margin.anchor_left = 1.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = -BoardTokens.RAIL_WIDTH
	margin.offset_right = 0.0
	margin.add_theme_constant_override("margin_left", int(BoardTokens.RAIL_INNER_PAD))
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", int(BoardTokens.RAIL_INNER_PAD))
	margin.add_theme_constant_override("margin_bottom", 22)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_right_column = margin

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var heading := _label("生命档案", BoardTokens.FONT_RAIL_HEAD, COLOR_ACCENT)
	heading.name = "RailHeading"
	heading.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.70))
	heading.add_theme_constant_override("outline_size", 3)
	column.add_child(heading)
	column.add_child(_label("选择你的生存方式", 12, Color(0.760, 0.780, 0.730)))
	column.add_child(_spacer(4))

	_cards_box = VBoxContainer.new()
	_cards_box.name = "SpeciesCards"
	_cards_box.add_theme_constant_override("separation", int(BoardTokens.CARD_GAP))
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_cards_box)

	for cfg in _configs:
		_cards_box.add_child(_make_species_card(cfg))

	_cards_box.add_child(_spacer(6))
	var future_head := _label("未来将拓展更多动物", 12, COLOR_DIM)
	future_head.name = "FutureHeading"
	_cards_box.add_child(future_head)

	_locked_box = VBoxContainer.new()
	_locked_box.name = "FutureSpecies"
	_locked_box.add_theme_constant_override("separation", 8)
	_locked_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_box.add_child(_locked_box)
	for entry in FUTURE_SPECIES:
		_locked_box.add_child(_make_locked_card(entry))

	var footer := _label("更多物种 · 敬请期待", BoardTokens.FONT_FOOTNOTE, COLOR_FAINT)
	footer.name = "RailFooter"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cards_box.add_child(footer)


func _build_hint() -> void:
	_hint_label = _label("", 13, COLOR_DIM)
	_hint_label.name = "Hint"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_right = 1.0
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_top = -44.0
	_hint_label.offset_bottom = -18.0
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_label)
	_refresh_hint()


func _refresh_hint() -> void:
	if _hint_label == null:
		return
	if _page == Page.SPECIES:
		_hint_label.text = "1 / 2 选择物种 · Enter 进入世界 · Esc 返回"
		# 物种页左半屏是大卡：提示文字只占右侧剩余空间，避免压在「返回」按钮上
		_hint_label.offset_left = BoardTokens.SPECIES_CARD_X + BoardTokens.SPECIES_CARD_W + 16.0
	else:
		_hint_label.text = "Enter 开始 · 鼠标点击卡片选择物种 · Esc 返回"
		_hint_label.offset_left = 0.0


## 展板右上角那块「初期版本（MVP Demo）」说明：告诉玩家当前只有 1～2 个可玩物种。
func _build_mvp_note() -> void:
	var box := VBoxContainer.new()
	box.name = "MvpNote"
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -BoardTokens.RAIL_WIDTH - 300.0
	box.offset_right = -BoardTokens.RAIL_WIDTH - 18.0
	# T033（ART09 遗留）：顶部状态文字两行占 y≈12–64（`LifeStatus` 顶部居中偏右），
	# 原先 offset_top=34 会把第二行「选择物种：…」整个压住。下移到 84 避开，
	# 两块文字互不覆盖（`run_t033_formal_species` 的 OCCL 断言盯住这里）。
	box.offset_top = 84.0
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(box)
	_mvp_note = box

	var head := _label("初期版本（MVP Demo）", 13, Color(0.949, 0.929, 0.882))
	head.name = "MvpHeading"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	head.add_theme_constant_override("shadow_offset_x", 1)
	head.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(head)

	for line in [
		"目前仅开放 %d 种动物（猫 / 鼠）作为示例。" % maxi(1, _configs.size()),
		"后续将陆续加入更多动物，",
		"体现不同的生存方式与生态关系。",
	]:
		var body := _label(String(line), 11, Color(0.780, 0.800, 0.760))
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.80))
		body.add_theme_constant_override("shadow_offset_x", 1)
		body.add_theme_constant_override("shadow_offset_y", 1)
		box.add_child(body)

func _make_species_card(cfg: SpeciesConfig) -> PanelContainer:
	# 展板右栏卡：左侧方图缩略图 + 右侧「名字 / 定位 / 一句描述」三层文字。
	var card := PanelContainer.new()
	card.name = "Card_%s" % String(cfg.species_id)
	card.custom_minimum_size = Vector2(0.0, BoardTokens.CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _card_style(false))

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	# ART09-F1：配置里有肖像图就用它（引擎渲染，展板观感），否则回退实时 3D 预览
	var preview: Control = _make_preview(cfg) if cfg.display_portrait == null else null
	var thumb: Control = preview if preview != null else _make_portrait(cfg)
	row.add_child(_thumb_frame(thumb, "Thumb_%s" % String(cfg.species_id)))

	var text := VBoxContainer.new()
	text.name = "Text"
	text.add_theme_constant_override("separation", 1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)

	var name_label := _label(cfg.display_title(), BoardTokens.FONT_CARD_NAME, COLOR_TEXT)
	name_label.name = "Name"
	text.add_child(name_label)
	# T033：Tagline/Note **无条件创建**——锁定态要往里写「尚未解锁/解锁提示」
	# （art09 卡契约要求这两个子节点存在；可玩态文本为空时也无碍）
	var tag := _label(cfg.display_tagline, BoardTokens.FONT_CARD_TAG, Color(0.812, 0.769, 0.639))
	tag.name = "Tagline"
	text.add_child(tag)
	var note := _label(cfg.display_note, BoardTokens.FONT_CARD_NOTE, COLOR_DIM)
	note.name = "Note"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(note)

	var id := cfg.species_id
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (event as InputEventMouseButton).pressed:
			# T033：锁定物种点击 → `select_species` 返回 false（已给反馈），不进物种页
			if select_species(id):
				show_page(Page.SPECIES)
	)

	_cards[id] = {
		"card": card,
		"name": name_label,
		"viewport": preview.get_meta("sub_viewport") if preview != null and preview.has_meta("sub_viewport") else null,
		"pivot": preview.get_meta("pivot") if preview != null and preview.has_meta("pivot") else null,
	}
	return card


## 未来物种卡：版式与可玩卡同族，但**整体压暗、不可点**。
## 仍然只是占位：真源是 `resources/species/*.tres`，落地后自动出现在上面的可玩列表里。
func _make_locked_card(entry: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Locked_%s" % String(entry.get("name", "?"))
	card.custom_minimum_size = Vector2(0.0, 60.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.tooltip_text = "未来开放：%s" % String(entry.get("note", ""))
	card.add_theme_stylebox_override("panel", _locked_style())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var mark := _label("?", 20, COLOR_FAINT)
	mark.custom_minimum_size = Vector2(44.0, 44.0)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_thumb_frame(mark, "Thumb_%s" % String(entry.get("name", "?")), 44.0))

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	text.add_child(_label(String(entry.get("name", "?")), 14, COLOR_DIM))
	text.add_child(_label(String(entry.get("tagline", "")), 11, COLOR_FAINT))
	return card


## 缩略图外框：展板是圆角方形照片框，这里给同尺寸深色玻璃框（3D 预览贴在里面）。
func _thumb_frame(content: Control, node_name: String, side: float = -1.0) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = node_name
	var s := side if side > 0.0 else BoardTokens.THUMB
	frame.custom_minimum_size = Vector2(s, s)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _thumb_style())
	frame.add_child(content)
	return frame


## 未来/锁定卡片的底色：比可玩卡更暗、边框更淡，读起来就是「还没开放」
func _locked_style() -> StyleBoxFlat:
	var sb := _panel_style()
	sb.bg_color = Color(0.032, 0.043, 0.060, 0.760)
	sb.border_color = Color(0.180, 0.220, 0.212, 0.480)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


## 缩略图框：未选中 1 px 暗金边，选中 2 px 亮金边（展板里选中槽是描金框）
func _thumb_style(is_selected: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.024, 0.034, 0.048, 0.900)
	sb.border_color = BoardTokens.GOLD if is_selected else Color(0.560, 0.470, 0.290, 0.700)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	var w := 2 if is_selected else 1
	sb.border_width_left = w
	sb.border_width_top = w
	sb.border_width_right = w
	sb.border_width_bottom = w
	return sb


func _refresh_cards() -> void:
	for id in _cards.keys():
		var entry: Dictionary = _cards[id]
		var card := entry.get("card") as Control
		if card == null:
			continue
		var is_selected := StringName(id) == _selected
		card.add_theme_stylebox_override("panel", _card_style(is_selected))
		var name_label := entry.get("name") as Label
		if name_label != null:
			name_label.add_theme_color_override(
				"font_color", COLOR_ACCENT if is_selected else COLOR_TEXT
			)
	# 物种页大卡与右栏卡片共用同一次刷新（选中变化 → 两处一起更新）
	_refresh_species_card()


## 卡片里那行数值：全部由 `SpeciesConfig` 推出来（不同物种自动显示不同数字）
func _stat_line(cfg: SpeciesConfig) -> String:
	return "速度 %.1f/%.1f m/s · 视距 %.0f m · 体力 %.0f" % [
		cfg.walk_speed, cfg.sprint_speed, cfg.vision_range, cfg.max_stamina
	]


# ---------------------------------------------------------------------------
# 构建：卡片 3D 预览
# ---------------------------------------------------------------------------

## ART09-F1：肖像图控件（配置里有 `display_portrait` 时用它，缺省回退 `_make_preview()`）
func _make_portrait(cfg: SpeciesConfig) -> Control:
	var tr := TextureRect.new()
	tr.name = "Portrait_%s" % String(cfg.species_id)
	tr.texture = cfg.display_portrait
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(BoardTokens.THUMB, BoardTokens.THUMB)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 返回一个 `SubViewportContainer`，并在它的 meta 里挂上 `sub_viewport` / `pivot`
func _make_preview(cfg: SpeciesConfig) -> Control:
	if cfg.visual_scene == null:
		# 没有模型的物种：给一个占位方块，**不假装**有素材
		var fallback := Label.new()
		fallback.text = "?"
		fallback.custom_minimum_size = Vector2(PREVIEW_PX, PREVIEW_PX)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_font_size_override("font_size", 30)
		fallback.add_theme_color_override("font_color", COLOR_FAINT)
		return fallback

	var holder := SubViewportContainer.new()
	holder.name = "Preview_%s" % String(cfg.species_id)
	holder.custom_minimum_size = Vector2(PREVIEW_PX, PREVIEW_PX)
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var size := PREVIEW_PX * PREVIEW_SUPERSAMPLE
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.68)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 34.0, 0.0)
	key.light_energy = 1.45
	key.light_color = Color(1.0, 0.96, 0.88)
	key.shadow_enabled = false
	vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, -140.0, 0.0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.72, 0.83, 0.95)
	fill.shadow_enabled = false
	vp.add_child(fill)

	var pivot := Node3D.new()
	pivot.name = "Pivot"
	vp.add_child(pivot)

	var inst := cfg.visual_scene.instantiate() as Node3D
	if inst == null:
		return holder
	pivot.add_child(inst)
	_play_preview_idle(inst)

	# 取景按**物种自己的胶囊尺寸**算，不用模型 AABB：胶囊高度是配置里的尺寸契约
	# （猫 0.48 m / 鼠 0.18 m），这样两个卡片里动物看起来一样大，也不受 glb 内部缩放影响。
	var h := maxf(0.05, cfg.capsule_height())
	# 取景按「模型实际高 ≈ 胶囊高 × 0.65」留余量：展板缩略图是紧凑肖像，
	# 早先 中心 h*0.46 / 距离 h*2.20 会让动物只占方框一半，读起来像迷你模型。
	var target := Vector3(0.0, h * 0.34, 0.0)
	# 模型在 Godot 里**面朝 −Z**（见 `Docs/BlenderPipeline.md`）→ 相机放在 −Z 侧才能拍到正脸。
	# 这里手算朝向而不用 `look_at()`：此刻卡片还没挂到容器上、相机不在树里，
	# `look_at()` 会报 "Node not inside tree"（实测踩到）。
	var cam_pos := Vector3(0.0, h * 0.42, -h * 1.50)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.01
	cam.transform = _look_transform(cam_pos, target)
	vp.add_child(cam)
	cam.current = true

	holder.set_meta("sub_viewport", vp)
	holder.set_meta("pivot", pivot)
	return holder


## 预览里播 Idle（有 `AnimationPlayer` 才播；没有动画的模型完全不受影响）
func _play_preview_idle(root: Node) -> void:
	var player := _find_animation_player(root)
	if player == null:
		return
	for candidate in [&"Idle", &"idle", &"Walk", &"walk"]:
		if player.has_animation(candidate):
			var anim := player.get_animation(candidate)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR
			player.play(candidate)
			return


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null




## 由「看向」构造变换（不依赖入树；`Camera3D` 的视线是本地 −Z）
func _look_transform(from: Vector3, to: Vector3) -> Transform3D:
	var forward := (to - from).normalized()
	if forward.length() <= 0.0:
		forward = Vector3.FORWARD
	var up_ref := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var right := forward.cross(up_ref).normalized()
	var up := right.cross(forward).normalized()
	return Transform3D(Basis(right, up, -forward), from)
func _set_previews_running(running: bool) -> void:
	var mode := SubViewport.UPDATE_ALWAYS if running else SubViewport.UPDATE_DISABLED
	for id in _cards.keys():
		var vp := (_cards[id] as Dictionary).get("viewport") as SubViewport
		if vp != null and is_instance_valid(vp):
			vp.render_target_update_mode = mode
	# 物种页缩略图行是另一批 SubViewport（同一物种两个预览，页面上只有一组可见）
	for id in _strip_previews.keys():
		var vp := _strip_previews[id] as SubViewport
		if vp != null and is_instance_valid(vp):
			vp.render_target_update_mode = mode


# ---------------------------------------------------------------------------
# 构建：设置
# ---------------------------------------------------------------------------

## 设置面板：只放**真的会生效**的两项（出生时由 `MainEntry` 应用到玩家身体）。
## 持久化（写入存档）属后续任务，本轮明确只在本次运行内生效。
func _build_settings() -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.name = "Settings"
	_settings_panel.visible = false
	_settings_panel.anchor_left = 0.5
	_settings_panel.anchor_right = 0.5
	_settings_panel.anchor_top = 0.5
	_settings_panel.anchor_bottom = 0.5
	_settings_panel.offset_left = -220.0
	_settings_panel.offset_right = 220.0
	_settings_panel.offset_top = -120.0
	_settings_panel.offset_bottom = 120.0
	_settings_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_settings_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_settings_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	column.add_child(_label("设置", 20, COLOR_ACCENT))
	# 初值来自 `GameSettings`（存盘值）；FOV 存的是 0 = 不覆盖 → 滑块从物种默认 90 起步
	var sens := float(_initial_settings.get(
		GameSettings.KEY_SENSITIVITY, SETTINGS_SENSITIVITY))
	var fov := float(_initial_settings.get(GameSettings.KEY_FOV, 0.0))
	if fov <= 0.0:
		fov = SETTINGS_FOV
	column.add_child(_slider_row("鼠标灵敏度", &"sensitivity", 0.4, 3.0, sens))
	column.add_child(_slider_row("视野 (FOV)", &"fov", 60.0, 110.0, fov))

	var close := _button("关闭", false)
	close.pressed.connect(func() -> void: _settings_panel.visible = false)
	column.add_child(close)


func _toggle_settings() -> void:
	_settings_panel.visible = not _settings_panel.visible


func _slider_row(label_text: String, key: StringName, min_v: float, max_v: float,
		default_v: float) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(head)
	var name_label := _label(label_text, 13, COLOR_DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value_label := _label(_format_setting(key, default_v), 13, COLOR_TEXT)
	head.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.05 if key == &"sensitivity" else 1.0
	slider.value = default_v
	slider.custom_minimum_size = Vector2(0.0, 18.0)
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = _format_setting(key, v)
		setting_changed.emit(key, v)
	)
	_sliders[key] = slider
	row.add_child(slider)
	return row


func _format_setting(key: StringName, value: float) -> String:
	if key == &"fov":
		return "%.0f°" % value
	return "%.2f×" % value


# ---------------------------------------------------------------------------
# 小部件与样式
# ---------------------------------------------------------------------------

func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cards.clear()
	_scrim = null
	_rail_shade = null
	_left_column = null
	_right_column = null
	_main_buttons = null
	_species_buttons = null
	_record_label = null
	_hint_label = null
	_cards_box = null
	_mvp_note = null
	_locked_box = null
	_species_card = null
	_card_portrait = null
	_card_name = null
	_card_tagline = null
	_card_note = null
	_card_stats = null
	_strip = null
	_card_bars.clear()
	_strip_slots.clear()
	_strip_previews.clear()
	_settings_panel = null


func _index_of(species_id: StringName) -> int:
	for i in _configs.size():
		if _configs[i].species_id == species_id:
			return i
	return -1


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


func _button_column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(BoardTokens.BUTTON_W, BoardTokens.BUTTON_H)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", BoardTokens.FONT_BUTTON)
	b.add_theme_color_override("font_color", Color(0.980, 0.957, 0.898))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	var normal := _button_style(primary, false)
	var hover := _button_style(primary, true)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if primary:
		# 展板金色主按钮右侧有 chevron：用一个忽略鼠标的 Label 画，不引入图标资源
		var chevron := _label("›", 24, Color(1.0, 0.96, 0.86, 0.95))
		chevron.name = "Chevron"
		chevron.anchor_left = 1.0
		chevron.anchor_right = 1.0
		chevron.anchor_top = 0.5
		chevron.anchor_bottom = 0.5
		chevron.offset_left = -42.0
		chevron.offset_right = -16.0
		chevron.offset_top = -16.0
		chevron.offset_bottom = 16.0
		chevron.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(chevron)
	return b


func _button_style(primary: bool, hovered: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if primary:
		# 展板主按钮：金底 + 亮金边 + 轻微投影（撑起"可点"的层次）
		sb.bg_color = BoardTokens.GOLD.lightened(0.10) if hovered else BoardTokens.GOLD
		sb.border_color = BoardTokens.GOLD_BRIGHT
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(0.0, 2.0)
		sb.corner_radius_top_left = 3
		sb.corner_radius_top_right = 3
		sb.corner_radius_bottom_left = 3
		sb.corner_radius_bottom_right = 3
	else:
		# 次级按钮：深色玻璃 + 1 px 暗边，hover 只提亮一档，不抢主按钮（ART10：同面板一起偏蓝灰）
		sb.bg_color = Color(0.086, 0.112, 0.150, 0.92) if hovered else Color(0.055, 0.068, 0.090, 0.88)
		sb.border_color = Color(0.60, 0.62, 0.52, 0.70) if hovered else Color(0.48, 0.51, 0.44, 0.55)
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_left = 2
		sb.corner_radius_bottom_right = 2
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 24.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 13.0
	sb.content_margin_bottom = 13.0
	return sb


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.200, 0.250, 0.239, 0.550)
	return sb


func _card_style(is_selected: bool) -> StyleBoxFlat:
	var sb := _panel_style()
	sb.bg_color = COLOR_PANEL_SEL if is_selected else COLOR_PANEL
	sb.border_width_left = 3 if is_selected else 1
	sb.border_color = COLOR_ACCENT if is_selected else Color(0.200, 0.250, 0.239, 0.550)
	return sb
func _menu_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.012, 0.024, 0.024, 0.86)
	sb.border_width_right = 1
	sb.border_color = Color(0.76, 0.58, 0.28, 0.32)
	return sb


func _rail_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BoardTokens.RAIL_BG
	sb.border_width_left = 1
	sb.border_color = Color(0.90, 0.72, 0.38, 0.42)
	sb.corner_radius_top_left = 2
	sb.corner_radius_bottom_left = 2
	return sb