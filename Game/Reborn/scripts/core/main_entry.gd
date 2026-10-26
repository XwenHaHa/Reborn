class_name MainEntry
extends Node3D
## 正式入口（T030）：把关卡、生态、HUD 与 `LifeCycle` 组装成"存活 → 结算 → 选物种 → 出生"的闭环。
##
## 依据：`Docs/TechnicalDesign.md` §7；策划 v1.1 §9.2–9.5、§10；决策见 `Docs/Tasks/T030.md` §3。
##
## 关键约束：
## - 场景 `scenes/core/main.tscn` 只有根节点 + 本脚本；关卡/HUD/状态栏全部运行期构建，
##   保证既有断言"无调试节点、无 CanvasLayer、无调试字样"继续成立（决策 D8）。
## - 物种一律从 `resources/species/*.tres` 发现，不写物种名与数量。
## - 档案与事件只写 `GameState`；本节点只做聚合与装配。

const LEVEL_SCENE_PATH := "res://scenes/maps/l_courtyard.tscn"
const BODY_SCENE_PATH := "res://scenes/characters/animal_body.tscn"
const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"
const SPECIES_DIR := "res://resources/species"

## 菜单展示区（ART04）：溪东岸的干燥地。相机与展示模型都**相对这个点**摆位，
## 关卡几何若变，只改这里并重新取景验证（`Docs/Evidence/ART04.md` §取景）。
const MENU_FOCUS := Vector3(-10.5, 0.10, 16.0)
const MENU_CAM_OFFSET := Vector3(0.86, 0.42, 0.80)
const MENU_CAM_LOOK := Vector3(0.0, 0.15, 0.0)
const MENU_CAM_FOV := 58.0
## 把展示主体推到画面右侧，左侧留给标题与按钮（负值 = 视线右移）
const MENU_CAM_H_OFFSET := -0.05
## 两个物种展示模型的横向间隔（米，沿相机右方向排开）
const MENU_SHOWCASE_SPREAD := 0.36

const ACTION_SELECT_1 := "life_select_1"
const ACTION_SELECT_2 := "life_select_2"
const SELECT_ACTIONS: Array[StringName] = [ACTION_SELECT_1, ACTION_SELECT_2]

## 开发测试模式（策划 §9.2）：解锁条件尚未接入（后续任务），默认放行全部物种。
## 接入正式解锁后改 false，届时正式模式只允许已解锁物种 + 初始物种（非捕食者）。
@export var test_mode: bool = true
## 结算/选物种界面文字刷新间隔（帧）。
@export var status_refresh_frames: int = 10
## 生态：每个物种的 NPC 数（按 `can_attack` 分派：捕食者少、猎物多）。
@export var prey_npc_count: int = 2
@export var predator_npc_count: int = 1

var level: Node3D = null
var hud: PlayerHud = null
var lifecycle: LifeCycle = null
var player: AnimalBody = null
var ecology: EcologySpawner = null
var status_label: Label = null

## 主菜单 / 物种选择界面（ART04）。**运行期建立**；`main.tscn` 仍是"只有根节点 + 本脚本"。
var menu: MainMenu = null
## 选物种时的展示相机（挂在关卡里）；玩家出生后由玩家相机接管
var menu_camera: Camera3D = null
## 菜单补光（挂在菜单相机下、不投阴影）：展示动物的正脸常被主光甩进阴影，加一盏只用于菜单的补光
var menu_fill: DirectionalLight3D = null
## 菜单里展示的物种模型（每个物种一个）：只在选物种/结算时存在，出生即释放
var _showcase: Array[Node3D] = []
## 设置项（ART04/ART05）：灵敏度倍数、视野覆盖。真源在 `user://settings.cfg`（见 `GameSettings`）
var sensitivity_scale := 1.0
## `0.0` = 不覆盖物种配置里的 `fov`；玩家动过滑块才写成具体值
var fov_override := 0.0
## 设置文件路径（测试可指向临时文件，不污染真实 `user://settings.cfg`）
@export var settings_path: String = GameSettings.DEFAULT_PATH
var _configs: Array[SpeciesConfig] = []
var _frame := 0
var _last_hunger := NAN
var _last_thirst := NAN
var _npcs_wired: Array[AnimalBody] = []
var _last_record: Dictionary = {}
var _wd_capture_hooked := false


func _ready() -> void:
	_configs = _discover_configs()
	_load_settings()
	_setup_long_term()
	_build_level()
	_build_ecology()
	_build_hud()
	_build_status()
	_build_menu()
	_build_lifecycle()
	_enter_select()
	print("ENTRY|ready|species=%d|test_mode=%s|unlocked=%s" % [
		_configs.size(), str(test_mode), str(_unlocked_ids())
	])


func _exit_tree() -> void:
	# 结算/选物种会冻结世界时间；本节点离场时恢复，避免影响其它场景与测试。
	var wd := _wd()
	if wd != null:
		wd.set("time_advancing", true)


func _unhandled_input(event: InputEvent) -> void:
	if lifecycle == null or lifecycle.state != LifeCycle.State.SELECTING:
		return
	var slots := selectable_slots()
	for i in SELECT_ACTIONS.size():
		if event.is_action_pressed(SELECT_ACTIONS[i]) and i < slots.size():
			select_species(slots[i])
			return


func _physics_process(_delta: float) -> void:
	_frame += 1
	if lifecycle == null:
		return
	if status_refresh_frames > 0 and _frame % status_refresh_frames == 0:
		_refresh_status()


# ---------------------------------------------------------------------------
# 对外（测试 / HUD / 结算）
# ---------------------------------------------------------------------------

## 可选物种（按 `species_id` 排序）：正式模式只含已解锁物种。
func selectable_slots() -> Array[StringName]:
	var out: Array[StringName] = []
	var gs := _game_state()
	for cfg in _configs:
		if gs == null or bool(gs.get("test_mode")) or bool(gs.call("is_species_unlocked", cfg.species_id)):
			out.append(cfg.species_id)
	return out


## 选择一个物种出生。返回是否被接受（被拒时 `lifecycle.rejections` 有记录）。
func select_species(species_id: StringName) -> bool:
	if lifecycle == null:
		return false
	return lifecycle.begin_spawn(species_id)


func lifecycle_state_name() -> String:
	return lifecycle.current_state_name() if lifecycle != null else "none"


func current_life_id() -> String:
	return lifecycle.life_id if lifecycle != null else ""


func archive_count() -> int:
	var gs := _game_state()
	return int(gs.call("archive_count")) if gs != null else 0


func last_record() -> Dictionary:
	var gs := _game_state()
	return gs.call("last_record") if gs != null else {}


func npc_count() -> int:
	if ecology == null or not is_instance_valid(ecology):
		return 0
	return ecology.npc_count()


func status_text() -> String:
	return status_label.text if status_label != null else ""


func species_configs() -> Array[SpeciesConfig]:
	return _configs


func world_time_now() -> float:
	var wd := _wd()
	return float(wd.get("world_time")) if wd != null else 0.0


# ---------------------------------------------------------------------------
# 构建
# ---------------------------------------------------------------------------

## 从 `resources/species/*.tres` 发现物种配置，按 `species_id` 排序（槽位顺序稳定）。
func _discover_configs() -> Array[SpeciesConfig]:
	var out: Array[SpeciesConfig] = []
	var dir := DirAccess.open(SPECIES_DIR)
	if dir == null:
		push_error("MainEntry: 打不开物种目录 %s" % SPECIES_DIR)
		return out
	var files: Array[String] = []
	# 导出包里文本资源会被转成 `*.tres.remap`（`Docs/Evidence/T030.md` §6 踩坑），
	# 所以先剥掉 `.remap` 再按真实扩展名收集，并对同名去重。
	for raw in dir.get_files():
		var f := String(raw)
		if f.ends_with(".remap"):
			f = f.trim_suffix(".remap")
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		if not files.has(f):
			files.append(f)
	files.sort()
	for f in files:
		var cfg := load("%s/%s" % [SPECIES_DIR, f]) as SpeciesConfig
		if cfg == null:
			continue
		if _config_index_of(out, cfg.species_id) >= 0:
			continue
		out.append(cfg)
	out.sort_custom(func(a: SpeciesConfig, b: SpeciesConfig) -> bool:
		return String(a.species_id) < String(b.species_id))
	return out


func _config_index_of(list: Array[SpeciesConfig], id: StringName) -> int:
	for i in list.size():
		if list[i].species_id == id:
			return i
	return -1


func _config_for(id: StringName) -> SpeciesConfig:
	var i := _config_index_of(_configs, id)
	return _configs[i] if i >= 0 else null


## 长期数据：只在新游戏（无档案、无进行中的一世）时写默认解锁集，绝不重置世界。
func _setup_long_term() -> void:
	var gs := _game_state()
	if gs == null:
		push_error("MainEntry: 缺少 GameState autoload")
		return
	gs.set("test_mode", test_mode)
	if (gs.get("unlocked_species") as Dictionary).is_empty():
		if test_mode:
			gs.call("set_default_unlock", _all_ids())
		else:
			# 正式模式：初始只解锁非捕食者（策划 §9.2 起手为鼠；不写物种名）。
			var initial: Array[StringName] = []
			for cfg in _configs:
				if not cfg.can_attack:
					initial.append(cfg.species_id)
			gs.call("set_default_unlock", initial)


func _all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for cfg in _configs:
		out.append(cfg.species_id)
	return out


func _unlocked_ids() -> Array[StringName]:
	var gs := _game_state()
	if gs == null:
		return []
	return gs.call("unlocked_list")


func _build_level() -> void:
	var packed := load(LEVEL_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("MainEntry: 关卡场景缺失 %s" % LEVEL_SCENE_PATH)
		return
	level = packed.instantiate() as Node3D
	if level == null:
		push_error("MainEntry: 关卡根节点不是 Node3D")
		return
	level.name = "Level"
	add_child(level)


func _build_ecology() -> void:
	if level == null:
		return
	var e := EcologySpawner.new()
	e.name = "Ecology"
	e.candidates = _configs
	var overrides := {}
	for cfg in _configs:
		overrides[cfg.species_id] = predator_npc_count if cfg.can_attack else prey_npc_count
	e.count_overrides = overrides
	level.add_child(e)
	ecology = e


func _build_hud() -> void:
	var packed := load(HUD_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("MainEntry: HUD 场景缺失 %s" % HUD_SCENE_PATH)
		return
	hud = packed.instantiate() as PlayerHud
	if hud == null:
		push_error("MainEntry: HUD 根节点不是 PlayerHud")
		return
	hud.name = "Hud"
	add_child(hud)


## 结算/选物种状态栏（普通 `Control`，不是 `CanvasLayer`：正式场景不许 CanvasLayer）。
func _build_status() -> void:
	var layer := Control.new()
	layer.name = "LifeStatus"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	status_label = Label.new()
	status_label.name = "LifeStatusLabel"
	status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status_label.position = Vector2(0.0, 12.0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
	status_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	status_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(status_label)


func _build_lifecycle() -> void:
	lifecycle = LifeCycle.new()
	lifecycle.name = "LifeCycle"
	lifecycle.known_species = _all_ids()
	add_child(lifecycle)
	lifecycle.spawn_requested.connect(_on_spawn_requested)
	lifecycle.life_settled.connect(_on_life_settled)
	lifecycle.state_changed.connect(_on_state_changed)


func _enter_select() -> void:
	if lifecycle == null:
		return
	if lifecycle.state != LifeCycle.State.SETTLING:
		return
	lifecycle.request_select()
	_refresh_status()
	_present_menu()


## 进入"选物种"画面（ART04）：显示菜单 + 展示模型 + 菜单相机，隐藏 HUD 与状态文字。
## 只改**呈现**，不改 `LifeCycle` 的任何状态（状态迁移仍由 `request_select()` 负责）。
func _present_menu() -> void:
	if menu != null:
		menu.open_menu(_previous_record_text())
	if hud != null:
		hud.visible = false
	if status_label != null:
		status_label.visible = false
	_build_showcase()
	if menu_camera != null:
		menu_camera.current = true
	if menu_fill != null:
		menu_fill.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## 离开菜单（出生那一刻）：释放展示模型、交还相机、恢复 HUD
func _dismiss_menu() -> void:
	if menu != null:
		menu.close_menu()
	if hud != null:
		hud.visible = true
	_clear_showcase()
	if menu_fill != null:
		menu_fill.visible = false


func _previous_record_text() -> String:
	var gs := _game_state()
	if gs == null or _last_record.is_empty():
		return ""
	var line := String(gs.call("archive_line", _last_record))
	return "上一世：%s" % line


# ---------------------------------------------------------------------------
# 生命周期回调
# ---------------------------------------------------------------------------

func _on_state_changed(_previous: int, _current: int) -> void:
	_refresh_status()


func _on_spawn_requested(species_id: StringName) -> void:
	_spawn_player(species_id)


func _on_life_settled(record: Dictionary) -> void:
	_last_record = record
	if hud != null:
		hud.unbind()
	player = null
	_enter_select()


## 创建玩家身体并回呼 `mark_spawned()`（决策 D1：状态机不建节点）。
func _spawn_player(species_id: StringName) -> void:
	var cfg := _config_for(species_id)
	if cfg == null or level == null:
		push_error("MainEntry: 无法出生 %s" % species_id)
		return
	var packed := load(BODY_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("MainEntry: 身体场景缺失 %s" % BODY_SCENE_PATH)
		return
	var body := packed.instantiate() as AnimalBody
	if body == null:
		push_error("MainEntry: 身体根节点不是 AnimalBody")
		return
	body.name = "Player"
	body.species_config = cfg       # 入树前赋值：`_ready` 里会 apply_config()
	body.player_controlled = true
	body.make_camera_current = true
	# ART04：出生即离开菜单（释放展示模型、恢复 HUD）。相机由 `make_camera_current` 接管。
	_dismiss_menu()
	level.add_child(body)
	var spawn := _spawn_position(cfg)
	body.global_position = spawn
	_apply_settings_to(body)
	body.velocity = Vector3.ZERO
	if body.climb != null:
		body.climb.reset_base()

	player = body
	lifecycle.mark_spawned(body, spawn)

	if hud != null:
		hud.bind_player(body)
	_last_hunger = NAN
	_last_thirst = NAN
	if body.survival != null:
		body.survival.died.connect(_on_player_died)
		body.survival.changed.connect(_on_survival_changed)
	if not _wd_capture_hooked:
		var wd := _wd()
		if wd != null and wd.has_signal("capture_reported"):
			wd.connect("capture_reported", _on_capture_reported)
			_wd_capture_hooked = true

	if ecology != null and is_instance_valid(ecology):
		ecology.candidates = _configs
		ecology.setup(body, spawn)
		_wire_npc_events()
	_refresh_status()
	print("ENTRY|spawn|%s|life=%s|pos=%s|npc=%d" % [
		String(species_id), lifecycle.life_id, str(spawn), npc_count()
	])


func _on_player_died(reason: StringName) -> void:
	if lifecycle == null or not lifecycle.is_alive():
		return
	lifecycle.end_life(&"died", {"damage_reason": String(reason)})
	print("ENTRY|died|life=%s|reason=%s|archive=%d" % [
		lifecycle.life_id, String(reason), archive_count()
	])


func _on_survival_changed(state: SurvivalState) -> void:
	if state == null or lifecycle == null or not lifecycle.is_alive():
		return
	var gs := _game_state()
	if gs == null:
		return
	var hunger := state.hunger
	var thirst := state.thirst
	if not is_nan(_last_hunger):
		var df := hunger - _last_hunger
		if df > 1e-4:
			gs.call("add_to_life", "food_gained", df)
			lifecycle.notify_event(&"food", {"amount": df})
	if not is_nan(_last_thirst):
		var dw := thirst - _last_thirst
		if dw > 1e-4:
			gs.call("add_to_life", "water_gained", dw)
			lifecycle.notify_event(&"water", {"amount": dw})
	_last_hunger = hunger
	_last_thirst = thirst


func _on_capture_reported(captor_id: String, target_id: String, position: Vector3,
		world_time: float) -> void:
	if player == null or not is_instance_valid(player) or lifecycle == null:
		return
	if not lifecycle.is_alive() or captor_id != player.source_id():
		return
	var gs := _game_state()
	if gs != null:
		gs.call("add_to_life", "captures", 1)
	lifecycle.notify_event(&"capture", {
		"target": target_id, "position": position, "world_time": world_time,
	})


## NPC 追击结束：猎物还活着且就是玩家 → 记一次逃脱（策划 §9.5 的"逃脱"）。
func _on_npc_prey_lost(prey_id: String) -> void:
	if player == null or not is_instance_valid(player) or lifecycle == null:
		return
	if not lifecycle.is_alive() or prey_id != player.source_id():
		return
	var gs := _game_state()
	if gs != null:
		gs.call("add_to_life", "escapes", 1)
	lifecycle.notify_event(&"escape", {})


func _wire_npc_events() -> void:
	if ecology == null or not is_instance_valid(ecology):
		return
	for body in ecology.npc_bodies():
		if body == null or not is_instance_valid(body) or _npcs_wired.has(body):
			continue
		_npcs_wired.append(body)
		var ai := body.ai
		if ai != null and is_instance_valid(ai) and ai.has_signal("prey_lost"):
			if not ai.is_connected("prey_lost", _on_npc_prey_lost):
				ai.connect("prey_lost", _on_npc_prey_lost)


# （捕获账本挂钩状态用 `_wd_capture_hooked` 布尔位，见 `_spawn_player()`）


# ---------------------------------------------------------------------------
# 状态栏
# ---------------------------------------------------------------------------

func _refresh_status() -> void:
	if status_label == null or lifecycle == null:
		return
	match lifecycle.state:
		LifeCycle.State.SELECTING:
			var slots := selectable_slots()
			var names: Array[String] = []
			for i in slots.size():
				if i >= SELECT_ACTIONS.size():
					break
				names.append("%d=%s" % [i + 1, String(slots[i])])
			var prev := ""
			if not _last_record.is_empty():
				var gs := _game_state()
				prev = "上一世：%s\n" % String(gs.call("archive_line", _last_record)) if gs != null else ""
			status_label.text = "%s选择物种：%s" % [prev, "  ".join(names)]
		LifeCycle.State.SETTLING:
			status_label.text = "结算中…"
		LifeCycle.State.SPAWNING:
			status_label.text = "出生中…"
		LifeCycle.State.ALIVE:
			status_label.text = "%s %s｜存活 %.1f s" % [
				lifecycle.life_id, String(lifecycle.species_id), _life_elapsed()
			]


func _life_elapsed() -> float:
	var gs := _game_state()
	if gs == null:
		return 0.0
	var cur := gs.get("current_life") as Dictionary
	if cur == null or cur.is_empty():
		return 0.0
	return maxf(0.0, world_time_now() - float(cur.get("start_world_time", 0.0)))


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

## 出生点：优先用关卡里组 `spawn_points` 且 `species` 元数据匹配的标记；否则原点上方兜底。
func _spawn_position(cfg: SpeciesConfig) -> Vector3:
	for n in get_tree().get_nodes_in_group("spawn_points"):
		var m := n as Node3D
		if m != null and StringName(m.get_meta("species", &"")) == cfg.species_id:
			return m.global_position
	return Vector3(0.0, cfg.capsule_half_height + 0.02, 0.0)


func _game_state() -> Node:
	var r := _tree_root()
	return r.get_node_or_null("GameState") if r != null else null


func _wd() -> Node:
	var r := _tree_root()
	return r.get_node_or_null("WorldDirector") if r != null else null


## 从 `SceneTree.root` 相对查找（树外调用绝对路径会报错）。
func _tree_root() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root if ml is SceneTree else null


# ---------------------------------------------------------------------------
# 主菜单 / 物种选择（ART04）
# ---------------------------------------------------------------------------

## 建立菜单与"选物种"用的展示相机。两者都在**运行期**建立：
## `main.tscn` 保持"只有根节点 + 本脚本"（T030 A15/A16 的断言不变）。
func _build_menu() -> void:
	menu = MainMenu.new()
	menu.name = "MainMenu"
	add_child(menu)
	# 入树之后再 build：卡片预览要用 `World3D` 与 `look_at`
	menu.build(_configs, current_settings())
	menu.species_committed.connect(_on_menu_species_committed)
	menu.setting_changed.connect(_on_menu_setting_changed)
	menu.quit_requested.connect(_on_menu_quit)
	_build_menu_camera()


func _build_menu_camera() -> void:
	if level == null or _configs.is_empty():
		return
	var focus := _menu_focus_ground()
	menu_camera = Camera3D.new()
	menu_camera.name = "MenuCamera"
	menu_camera.fov = MENU_CAM_FOV
	menu_camera.near = 0.05
	level.add_child(menu_camera)
	menu_camera.global_position = focus + MENU_CAM_OFFSET
	menu_camera.look_at(focus + MENU_CAM_LOOK, Vector3.UP)
	menu_camera.h_offset = MENU_CAM_H_OFFSET
	menu_camera.current = false
	# 菜单补光：只在选物种/结算时点亮，出生后立刻关掉，**不改动关卡原有光照**
	menu_fill = DirectionalLight3D.new()
	menu_fill.name = "MenuFill"
	menu_fill.light_energy = 0.55
	menu_fill.light_color = Color(1.0, 0.97, 0.90)
	menu_fill.shadow_enabled = false
	menu_fill.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
	menu_fill.visible = false
	menu_camera.add_child(menu_fill)


## 展示点吸附到地面：向下打一条射线；打不到就用常数高度（关卡变化时的兜底）
func _menu_focus_ground() -> Vector3:
	var from := MENU_FOCUS + Vector3.UP * 2.0
	var to := MENU_FOCUS - Vector3.UP * 4.0
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1        # world_static
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return hit.get("position", MENU_FOCUS)
	return MENU_FOCUS


## 展示模型：每个有 `visual_scene` 的物种一个，沿相机右方向并排，面朝相机。
## 全部来自 `SpeciesConfig` —— 新增物种自动出现在展示里，本函数不用改。
func _build_showcase() -> void:
	_clear_showcase()
	if level == null or menu_camera == null or _configs.is_empty():
		return
	var focus := _menu_focus_ground()
	var right := menu_camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length() > 0.001 else Vector3.RIGHT
	var shown: Array[SpeciesConfig] = []
	for cfg in _configs:
		if cfg.visual_scene != null:
			shown.append(cfg)
	if shown.is_empty():
		return
	var camera_pos := menu_camera.global_position
	# 小物种往相机方向挪一点（按体型差）：真按同一深度摆，鼠在菜单里只有十几个像素高
	var h_max := 0.0
	for cfg in shown:
		h_max = maxf(h_max, cfg.capsule_height())
	var to_camera := camera_pos - focus
	to_camera.y = 0.0
	to_camera = to_camera.normalized()
	for i in shown.size():
		var inst := shown[i].visual_scene.instantiate() as Node3D
		if inst == null:
			continue
		inst.name = "Showcase_%s" % String(shown[i].species_id)
		level.add_child(inst)
		var t := float(i) - (float(shown.size()) - 1.0) * 0.5
		var depth := (h_max - shown[i].capsule_height()) * 1.10
		var pos := focus + right * (t * MENU_SHOWCASE_SPREAD) + to_camera * depth
		pos.y = focus.y
		inst.global_position = pos
		# 模型本地面朝 −Z：`look_at` 让 −Z 指向相机 → 正好朝观众
		inst.look_at(Vector3(camera_pos.x, pos.y, camera_pos.z), Vector3.UP)
		_showcase_idle(inst)
		_showcase.append(inst)


func _clear_showcase() -> void:
	for node in _showcase:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_showcase.clear()


## 展示模型播 Idle（有动画才播；模型没有动画时完全不受影响）
func _showcase_idle(root: Node) -> void:
	var player := _find_anim_player(root)
	if player == null:
		return
	for candidate in [&"Idle", &"idle", &"Walk", &"walk"]:
		if player.has_animation(candidate):
			var anim := player.get_animation(candidate)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR
			player.play(candidate)
			return


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found != null:
			return found
	return null


## 设置项落到玩家身体上（灵敏度按倍数、FOV 直接覆盖物种默认值）
func _apply_settings_to(body: AnimalBody) -> void:
	if body == null or not is_instance_valid(body):
		return
	body.mouse_sensitivity = MainMenu.SENSITIVITY_BASE * sensitivity_scale
	if fov_override > 0.0 and body.camera != null:
		body.camera.fov = fov_override


func _on_menu_species_committed(species_id: StringName) -> void:
	select_species(species_id)


## 菜单设置改动：立刻落到本局 + 立刻写 `user://settings.cfg`（真源见 `GameSettings`）
func _on_menu_setting_changed(key: StringName, value: float) -> void:
	if key == &"sensitivity":
		sensitivity_scale = value
	elif key == &"fov":
		fov_override = value
	else:
		return
	var ok := GameSettings.save_to(current_settings(), settings_path)
	print("ENTRY|settings|%s=%.3f|saved=%s|path=%s" % [
		String(key), value, str(ok), settings_path
	])


## 当前生效的设置（菜单回填与写盘都用这一份）
func current_settings() -> Dictionary:
	return {
		GameSettings.KEY_SENSITIVITY: sensitivity_scale,
		GameSettings.KEY_FOV: fov_override,
	}


## 从 `settings_path` 读设置；缺失/损坏时回落默认值（不崩）
func _load_settings() -> void:
	var s := GameSettings.load_from(settings_path)
	sensitivity_scale = float(s[GameSettings.KEY_SENSITIVITY])
	fov_override = float(s[GameSettings.KEY_FOV])
	print("ENTRY|settings_loaded|sensitivity=%.2f|fov=%.1f|path=%s" % [
		sensitivity_scale, fov_override, settings_path
	])


func _on_menu_quit() -> void:
	if lifecycle != null and not lifecycle.is_alive():
		print("ENTRY|quit|requested")
		get_tree().quit()
