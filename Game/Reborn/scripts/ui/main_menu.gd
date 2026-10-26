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

const COLOR_TEXT := Color(0.949, 0.929, 0.882)
const COLOR_DIM := Color(0.596, 0.639, 0.612)
const COLOR_FAINT := Color(0.396, 0.443, 0.427)
const COLOR_ACCENT := Color(0.851, 0.588, 0.227)
const COLOR_ACCENT_DIM := Color(0.431, 0.325, 0.157)
const COLOR_PANEL := Color(0.043, 0.071, 0.078, 0.780)
const COLOR_PANEL_SEL := Color(0.086, 0.133, 0.145, 0.900)
const COLOR_CARD_LOCKED := Color(0.043, 0.059, 0.063, 0.560)

const PREVIEW_PX := 96
const PREVIEW_SUPERSAMPLE := 2

var _configs: Array[SpeciesConfig] = []
var _selected: StringName = &""
var _page: int = Page.MAIN

var _scrim: ColorRect = null
var _left_column: Control = null
var _right_column: Control = null
var _main_buttons: VBoxContainer = null
var _species_buttons: VBoxContainer = null
var _record_label: Label = null
var _hint_label: Label = null
var _cards_box: VBoxContainer = null
var _settings_panel: PanelContainer = null

## `species_id` → {card, name_label, viewport, pivot, animation}
var _cards: Dictionary = {}
## 预览用的慢速自转速度（弧度/秒）：让卡片看起来是活的，但不足以分散注意力
var _spin_speed := 0.35
## 已存盘的设置（`GameSettings` 读出来的）；只用于回填滑块初值
var _initial_settings: Dictionary = {}
## 设置滑块的当前值（`settings_values()` 读它，证据/断言用）
var _sliders: Dictionary = {}


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
func build(configs: Array[SpeciesConfig], initial_settings: Dictionary = {}) -> void:
	_configs = configs.duplicate()
	_initial_settings = initial_settings.duplicate()
	_clear()

	_build_scrim()
	_build_left_column()
	_build_right_column()
	_build_hint()
	_build_settings()
	if not _configs.is_empty():
		select_species(_configs[0].species_id)
	show_page(Page.MAIN)


## 打开主菜单（`previous_text` 非空时显示「上一世」摘要）
func open_menu(previous_text: String = "") -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_set_previews_running(true)
	_settings_panel.visible = false
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
	if _main_buttons != null:
		_main_buttons.visible = page == Page.MAIN
	if _species_buttons != null:
		_species_buttons.visible = page == Page.SPECIES
	if _cards_box != null:
		_cards_box.visible = true
	_refresh_cards()
	_refresh_hint()


func select_species(species_id: StringName) -> void:
	if _index_of(species_id) < 0:
		return
	_selected = species_id
	_refresh_cards()


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
	# 但这里只**选中**，进入世界还要再按回车 —— 避免误按直接出生）
	for i in _configs.size():
		var action := "life_select_%d" % (i + 1)
		if InputMap.has_action(action) and event.is_action_pressed(action):
			select_species(_configs[i].species_id)
			show_page(Page.SPECIES)
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
	# 压暗 3D 场景，保证文字可读；左重右轻，把注意力留在物种卡片这一侧
	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = Color(0.020, 0.035, 0.041, 0.470)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)

	var left_shade := ColorRect.new()
	left_shade.name = "LeftShade"
	left_shade.color = Color(0.016, 0.027, 0.031, 0.400)
	left_shade.anchor_bottom = 1.0
	left_shade.offset_right = 500.0
	left_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left_shade)


func _build_left_column() -> void:
	var margin := MarginContainer.new()
	margin.name = "LeftColumn"
	margin.anchor_bottom = 1.0
	margin.offset_right = 480.0
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 48)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_left_column = margin

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var title := _label(PAGE_TITLE, 84, COLOR_TEXT)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 3)
	column.add_child(title)

	column.add_child(_label(PAGE_SUBTITLE, 22, COLOR_ACCENT))
	column.add_child(_spacer(10))
	column.add_child(_label(TAGLINE, 19, Color(0.827, 0.804, 0.741)))
	column.add_child(_label(TAGLINE_2, 14, COLOR_DIM))
	column.add_child(_spacer(26))

	_main_buttons = _button_column()
	column.add_child(_main_buttons)
	var start := _button("开始游戏", true)
	start.pressed.connect(func() -> void: commit())
	_main_buttons.add_child(start)
	var pick := _button("物种选择", false)
	pick.pressed.connect(func() -> void: show_page(Page.SPECIES))
	_main_buttons.add_child(pick)
	var settings := _button("设置", false)
	settings.pressed.connect(_toggle_settings)
	_main_buttons.add_child(settings)
	var quit := _button("退出", false)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	_main_buttons.add_child(quit)

	_species_buttons = _button_column()
	_species_buttons.visible = false
	column.add_child(_species_buttons)
	var enter := _button("进入世界", true)
	enter.pressed.connect(func() -> void: commit())
	_species_buttons.add_child(enter)
	var back := _button("返回", false)
	back.pressed.connect(func() -> void: show_page(Page.MAIN))
	_species_buttons.add_child(back)

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


func _build_right_column() -> void:
	var margin := MarginContainer.new()
	margin.name = "RightColumn"
	margin.anchor_left = 1.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = -452.0
	margin.offset_right = -40.0
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 48)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_right_column = margin

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	column.add_child(_label("可玩物种", 15, COLOR_ACCENT))
	column.add_child(_label("MVP Demo：2 个物种，其余按数据接入", 12, COLOR_FAINT))
	column.add_child(_spacer(6))

	_cards_box = VBoxContainer.new()
	_cards_box.name = "SpeciesCards"
	_cards_box.add_theme_constant_override("separation", 8)
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_cards_box)

	for cfg in _configs:
		_cards_box.add_child(_make_species_card(cfg))

	_cards_box.add_child(_spacer(4))
	_cards_box.add_child(_label("未来开放", 13, COLOR_FAINT))
	for entry in FUTURE_SPECIES:
		_cards_box.add_child(_make_locked_card(entry))


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
	else:
		_hint_label.text = "Enter 开始 · 鼠标点击卡片选择物种 · Esc 返回"


# ---------------------------------------------------------------------------
# 构建：卡片
# ---------------------------------------------------------------------------

func _make_species_card(cfg: SpeciesConfig) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Card_%s" % String(cfg.species_id)
	card.custom_minimum_size = Vector2(0.0, 104.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _card_style(false))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var preview := _make_preview(cfg)
	row.add_child(preview)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)

	var name_label := _label(cfg.display_title(), 20, COLOR_TEXT)
	name_label.name = "Name"
	text.add_child(name_label)
	if not cfg.display_tagline.is_empty():
		text.add_child(_label(cfg.display_tagline, 13, Color(0.812, 0.769, 0.639)))
	if not cfg.display_note.is_empty():
		text.add_child(_label(cfg.display_note, 12, COLOR_DIM))
	text.add_child(_label(_stat_line(cfg), 11, COLOR_FAINT))

	var id := cfg.species_id
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (event as InputEventMouseButton).pressed:
			select_species(id)
			show_page(Page.SPECIES)
	)

	_cards[id] = {
		"card": card,
		"name": name_label,
		"viewport": preview.get_meta("sub_viewport", null),
		"pivot": preview.get_meta("pivot", null),
	}
	return card


func _make_locked_card(entry: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Locked_%s" % String(entry.get("name", "?"))
	card.custom_minimum_size = Vector2(0.0, 72.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _card_style(false)
	style.bg_color = COLOR_CARD_LOCKED
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var badge := Label.new()
	badge.text = String(entry.get("name", "?"))
	badge.custom_minimum_size = Vector2(PREVIEW_PX, 0.0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 26)
	badge.add_theme_color_override("font_color", COLOR_FAINT)
	row.add_child(badge)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	var tag := _label("%s · 未来开放" % String(entry.get("tagline", "")), 13, COLOR_FAINT)
	text.add_child(tag)
	text.add_child(_label(String(entry.get("note", "")), 11, COLOR_FAINT))
	return card


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


## 卡片里那行数值：全部由 `SpeciesConfig` 推出来（不同物种自动显示不同数字）
func _stat_line(cfg: SpeciesConfig) -> String:
	return "速度 %.1f/%.1f m/s · 视距 %.0f m · 体力 %.0f" % [
		cfg.walk_speed, cfg.sprint_speed, cfg.vision_range, cfg.max_stamina
	]


# ---------------------------------------------------------------------------
# 构建：卡片 3D 预览
# ---------------------------------------------------------------------------

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
	var target := Vector3(0.0, h * 0.46, 0.0)
	# 模型在 Godot 里**面朝 −Z**（见 `Docs/BlenderPipeline.md`）→ 相机放在 −Z 侧才能拍到正脸。
	# 这里手算朝向而不用 `look_at()`：此刻卡片还没挂到容器上、相机不在树里，
	# `look_at()` 会报 "Node not inside tree"（实测踩到）。
	var cam_pos := Vector3(0.0, h * 0.85, -h * 2.20)
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
	_left_column = null
	_right_column = null
	_main_buttons = null
	_species_buttons = null
	_record_label = null
	_hint_label = null
	_cards_box = null
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
	b.custom_minimum_size = Vector2(220.0, 46.0)
	b.add_theme_font_size_override("font_size", 19)
	var font_color := Color(0.980, 0.957, 0.898) if primary else Color(0.878, 0.898, 0.867)
	b.add_theme_color_override("font_color", font_color)
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))

	var normal := _panel_style()
	if primary:
		normal.bg_color = COLOR_ACCENT
		normal.border_color = COLOR_ACCENT.lightened(0.25)
	else:
		normal.bg_color = Color(0.086, 0.118, 0.129, 0.760)
		normal.border_color = Color(0.235, 0.286, 0.275, 0.800)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = COLOR_ACCENT.lightened(0.14) if primary else Color(0.145, 0.192, 0.204, 0.900)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


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