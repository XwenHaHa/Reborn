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
const RESOURCE_SCENE_PATH := "res://scenes/world/resource_point.tscn"
## T058：休息点（安全地点）。位置与交互时长见 `Docs/Parameters.md` §休息 实现默认值。
const REST_POINT_SCENE_PATH := "res://scenes/world/rest_point.tscn"
## 庭院庇护棚内（`SHELTER_X_MIN..MAX = -9.5..-6.5`、`SHELTER_Z_MIN..MAX = 25.6..29.0` 的中心偏南）
const REST_POINT_POSITION := Vector3(-8.0, 0.10, 27.3)
## T042：新脚本用 `preload` 显式依赖，避免依赖 `.godot` 全局类缓存的刷新时机。
const PAUSE_MENU_SCRIPT := preload("res://scripts/ui/pause_menu.gd")
const END_LIFE_CONFIRM_SCRIPT := preload("res://scripts/ui/end_life_confirm.gd")
const SPECIES_DIR := "res://resources/species"
const PlacementSafetyLib = preload("res://scripts/world/placement_safety.gd")

## 菜单展示区（ART04）：溪东岸的干燥地。相机与展示模型都**相对这个点**摆位，
## 关卡几何若变，只改这里并重新取景验证（`Docs/Evidence/ART04.md` §取景）。
const MENU_FOCUS := Vector3(-10.5, 0.10, 16.0)
## ART06：收益最高的改动是**机位更近**（0.86/0.42/0.80 → 0.66/0.42/0.61，相机到主体 1.26 → 0.992 m），
## 主体占屏高 0.363 → **0.467**（胶囊契约高度的脚点/头点投影，见 `Docs/Evidence/ART06.md` §3）。改这里要重跑取证。
const MENU_CAM_OFFSET := Vector3(0.66, 0.42, 0.61)
const MENU_CAM_LOOK := Vector3(0.0, 0.18, 0.0)
const MENU_CAM_FOV := 58.0
## ART06：机位右移量。0 = 主体在画面中线；负值把主体推右（给左侧标题/按钮让位）。
## 实测（脚点投影）：-0.16 → 猫的脚点 cx=746（右栏卡片从 828 开始，会压到卡片）；-0.05 → cx≈672。
const MENU_CAM_H_OFFSET := -0.05
## 小体型物种（鼠）按体型差往相机方向前移的总深度系数：不这么做，鼠选进主视觉时只有十几个像素高
const MENU_SHOWCASE_DEPTH_SCALE := 1.10

const ACTION_SELECT_1 := "life_select_1"
const ACTION_SELECT_2 := "life_select_2"
const SELECT_ACTIONS: Array[StringName] = [ACTION_SELECT_1, ACTION_SELECT_2]

## 开发测试模式（策划 §9.2）：允许直接选择两个物种；**正式体验与测试模式明确区分**
## （T030 遗留收口，T031 已接入正式解锁）：默认 false = 正式模式——
## 只有初始解锁物种（`SpeciesConfig.initially_unlocked`，当前数据下即猫）可选，
## 其余靠「发现指定地点」永久解锁（`SpeciesConfig.unlock_discovery` + `DiscoveryTracker`）。
@export var test_mode: bool = false
## 结算/选物种界面文字刷新间隔（帧）。
@export var status_refresh_frames: int = 10
## T040b：`last_reconcile.pending_excess > 0` 时的低频重试间隔（物理帧 ≈ 1 s @60 Hz）。
const RECONCILE_RETRY_FRAMES := 60
## 生态：每个物种的 NPC 数（按 `can_attack` 分派：捕食者少、猎物多）。
@export var prey_npc_count: int = 2
@export var predator_npc_count: int = 1

var level: Node3D = null
var hud: PlayerHud = null
var lifecycle: LifeCycle = null
var player: AnimalBody = null
## 地点发现（T031）：只观察组件；长期记录与解锁规则都在 `GameState`。
var discovery: DiscoveryTracker = null
var ecology: EcologySpawner = null
var status_label: Label = null

## 主菜单 / 物种选择界面（ART04）。**运行期建立**；`main.tscn` 仍是"只有根节点 + 本脚本"。
var menu: MainMenu = null
## 生命结算覆盖层（T032，策划 §9.3/§9.4）：**运行期建立**，加在 `menu` **之后** →
## 同 canvas 后加入者绘制在上，死亡后盖在选物种画面上方（`_enter_select` 时序不变，决策 D1/D5）。
var settle_panel: LifeSettlePanel = null
## T041 破坏性操作二次确认层：插在 `MainMenu` 之上、`LifeSettlePanel` 之下。
var confirm_dialog: NewGameConfirm = null
## T042 暂停层：插在 `Hud` 之上、`MainMenu` 之下（只在存活期可达）。
var pause_menu = null
## T042「结束本次生命」二次确认：暂停层之上。
var end_life_confirm = null
## T042 暂停状态（`SceneTree.paused` 由本入口统一开关）。
var _paused := false
## 选物种时的展示相机（挂在关卡里）；玩家出生后由玩家相机接管
var menu_camera: Camera3D = null
## 菜单补光（挂在菜单相机下、不投阴影）：展示动物的正脸常被主光甩进阴影，加一盏只用于菜单的补光
var menu_fill: DirectionalLight3D = null
## ART10 菜单轮廓光（同样只用于菜单）：从主体背后朝镜头打暖金边光，模仿展板的侧逆光毛边
var menu_rim: DirectionalLight3D = null
## 菜单里展示的物种模型（每个物种一个）：只在选物种/结算时存在，出生即释放
var _showcase: Array[Node3D] = []
## 设置项（ART04/ART05）：灵敏度倍数、视野覆盖。真源在 `user://settings.cfg`（见 `GameSettings`）
var sensitivity_scale := 1.0
## `0.0` = 不覆盖物种配置里的 `fov`；玩家动过滑块才写成具体值
var fov_override := 0.0
## 设置文件路径（测试可指向临时文件，不污染真实 `user://settings.cfg`）
@export var settings_path: String = GameSettings.DEFAULT_PATH
## 自动存档总开关（D9）。只有正式运行（`current_scene == self`）才真正启用；
## 测试/取证工具通过 `set_persistence_enabled()` 显式打开。
@export var persistence_enabled: bool = true
var _configs: Array[SpeciesConfig] = []
var _frame := 0
var _last_hunger := NAN
var _last_thirst := NAN
var _npcs_wired: Array[AnimalBody] = []
var _last_record: Dictionary = {}
var _wd_capture_hooked := false
var _wd_death_hooked := false
## T058：休息点与信号接线标记（`rest_point` 由 `_mount_rest_point()` 挂载）
var rest_point: Node = null
var _rest_wired := false
## 启动读档结果（T037）：快照在校验通过后暂存，等关卡/HUD 建好再按 D8 顺序应用。
var _loaded_snapshot: Dictionary = {}
var _load_status: String = "none"
var _load_message: String = ""
var _load_repairs: Array = []
## 读档结果提示：启动时 HUD 尚未显示（`_enter_select` 会隐藏它），所以同时写进菜单的
## 「上一世」文字位；消费一次即清空，不重复打扰。
var _load_notice := ""
var _persist_enabled := false
## T039 D3：双坏隔离后阻断本会话开新局（不静默进入新游戏、退出不写新档）。
var _load_blocked := false
## T041：开新局时丢弃当前一世（不弹结算、不落盘）。
var _discarding_new_game := false


func _ready() -> void:
	_configs = _discover_configs()
	_load_settings()
	# T037 D9：只有正式运行（本节点就是当前场景）才启用自动存取；测试/工具默认关闭。
	_persist_enabled = persistence_enabled and get_tree() != null and get_tree().current_scene == self
	_load_saved_game()
	_load_blocked = _load_status == "corrupt"
	_setup_long_term()
	_build_level()
	_init_region_population()   # T035：建关卡后、铺生态前，把区域种群账本 init 一次（重生不再 init）
	# T037 D8：世界时间 → 区域账本 → 资源 → 长期层（此时关卡已建、账本已 init）。
	if not _loaded_snapshot.is_empty():
		apply_saved_snapshot(_loaded_snapshot, false)
	_build_ecology()
	_build_hud()
	# T042：暂停层贴 HUD 之上、菜单之下（存活期菜单/状态/确认/结算都隐藏）。
	_build_pause_layers()
	# T033（ART09 遮挡遗留）：`LifeStatus` 必须在 `MainMenu` **之后**加入——
	# 同 canvas 后加入者绘制在上，状态文字才不会被菜单（尤其右上 MvpNote）盖住；
	# `LifeSettlePanel` 仍最后加入、绘制在最上（T032 A9 契约）。
	_build_menu()
	_build_status()
	_build_confirm()
	_build_settle_panel()
	_build_lifecycle()
	_wire_gamestate_signals()
	_toast_load_status()
	_apply_menu_session_state()
	# T041 D1：有可恢复存档也停在菜单，由玩家点「继续」；无存档/无当前生命直接进选物种。
	_enter_select()
	print("ENTRY|ready|species=%d|test_mode=%s|unlocked=%s" % [
		_configs.size(), str(test_mode), str(_unlocked_ids())
	])


func _exit_tree() -> void:
	# T042：暂停是本节点的全局状态，离场前必须解除，避免把暂停留给后续场景/测试。
	if _paused:
		_paused = false
		if get_tree() != null:
			get_tree().paused = false
	# T037 D9：退出时存一次；T039 D3：双坏阻断期间禁止自动写新档。
	if not _load_blocked:
		save_now(&"exit")
	# 结算/选物种会冻结世界时间；本节点离场时恢复，避免影响其它场景与测试。
	var wd := _wd()
	if wd != null:
		wd.set("time_advancing", true)


func _unhandled_input(event: InputEvent) -> void:
	# T042：Esc 统一走优先级守卫（结算页 > 确认层 > 暂停）；未消费时继续走既有菜单路径。
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if handle_escape():
			get_viewport().set_input_as_handled()
		return
	if lifecycle == null or lifecycle.state != LifeCycle.State.SELECTING:
		return
	if confirm_dialog != null and confirm_dialog.is_open():
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
	# T040b：玩家走远后的低频收敛重试（只有存在 pending_excess 时才调用）。
	if _frame % RECONCILE_RETRY_FRAMES == 0:
		_retry_pending_reconcile()


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
## T039 D3：双坏隔离后拒绝开始新游戏（需重启；会话内确认入口属 T041）。
func select_species(species_id: StringName) -> bool:
	if _load_blocked:
		print("ENTRY|blocked|select_denied_corrupt|species=%s" % String(species_id))
		return false
	if lifecycle == null:
		return false
	return lifecycle.begin_spawn(species_id)


## T039 D9：双坏隔离后本会话是否被阻断。
func is_load_blocked() -> bool:
	return _load_blocked


# ---------------------------------------------------------------------------
# T041：继续 / 新游戏确认
# ---------------------------------------------------------------------------

## 「继续」是否可用：读档成功（含备份恢复）且快照里有当前生命或待结算。
func can_continue_game() -> bool:
	if _load_blocked:
		return false
	if _load_status != "ok" and _load_status != "recovered_backup":
		return false
	if _loaded_snapshot.is_empty():
		return false
	var current: Variant = _loaded_snapshot.get("current_life", {})
	if current is Dictionary and not (current as Dictionary).is_empty():
		return true
	return String(_loaded_snapshot.get("pending_settlement_life_id", "")) != ""


## 玩家点「继续」：按 T037 顺序恢复当前生命（世界层已在菜单建立前应用）。
func continue_game() -> bool:
	if not can_continue_game():
		print("ENTRY|continue|rejected|status=%s|blocked=%s" % [_load_status, str(_load_blocked)])
		return false
	var ok := _restore_life_from_snapshot(_loaded_snapshot)
	print("ENTRY|continue|ok=%s|state=%s|life=%s" % [
		str(ok), lifecycle_state_name(), current_life_id()
	])
	return ok


## 新游戏入口：有可覆盖旧档 → 打开确认层（默认焦点取消）；无旧档 → 直接开新局。
## 双坏阻断页的按钮标签本身即确认，直接清阻断并开新局。
## 返回 true = 新局已开始；false = 等待确认或被阻断。
func request_new_game() -> bool:
	if _load_blocked:
		return _start_new_game(true)
	var sm := _save_manager()
	if sm != null and sm.has_method("snapshot_exists") and bool(sm.call("snapshot_exists")):
		return _open_new_game_confirm()
	if not _loaded_snapshot.is_empty() or _load_status == "version_mismatch":
		return _open_new_game_confirm()
	if sm != null and FileAccess.file_exists(String(sm.call("backup_path"))):
		return _open_new_game_confirm()
	return _start_new_game(false)


func _open_new_game_confirm() -> bool:
	if confirm_dialog == null:
		return false
	var msg := "确定开始新游戏？当前存档将被清除，且无法恢复。"
	if _load_status == "version_mismatch":
		msg = "旧存档版本不兼容。确认后将清除旧档并开始新游戏。"
	confirm_dialog.open(msg)
	if menu != null:
		menu.set_input_locked(true)
	print("ENTRY|new_game_confirm|open|status=%s|focus=%s" % [
		_load_status, confirm_dialog.default_button_text()
	])
	return false


func _on_menu_resume() -> void:
	continue_game()


func _on_menu_new_game() -> void:
	request_new_game()


func _on_new_game_confirmed() -> void:
	_start_new_game(false)


func _on_new_game_cancelled() -> void:
	if menu != null:
		menu.set_input_locked(false)


## 清档 + 重置长期数据 + 重建区域账本，进入物种选择。
func _start_new_game(blocked_origin: bool) -> bool:
	var gs := _game_state()
	var sm := _save_manager()
	if gs == null or not gs.has_method("reset_for_new_game"):
		push_error("MainEntry: 缺少 GameState.reset_for_new_game")
		return false
	if sm == null or not sm.has_method("clear_slot"):
		push_error("MainEntry: 缺少 SaveManager.clear_slot")
		return false
	var was_blocked := _load_blocked
	_load_blocked = false
	# 玩家可能正在存活期点「新游戏」：先丢弃这一世（不归档、不弹结算、不落盘）。
	_discarding_new_game = true
	if lifecycle != null and lifecycle.state == LifeCycle.State.ALIVE:
		lifecycle.end_life(&"new_game")
	_discarding_new_game = false
	sm.call("clear_slot")
	gs.call("reset_for_new_game")
	_loaded_snapshot = {}
	_load_status = "none"
	_load_message = ""
	_load_repairs = []
	_load_notice = ""
	_last_record = {}
	_last_hunger = NAN
	_last_thirst = NAN
	_npcs_wired.clear()
	if ecology != null and is_instance_valid(ecology) and ecology.has_method("clear"):
		ecology.call("clear")
	_init_region_population()
	_setup_long_term()
	if confirm_dialog != null:
		confirm_dialog.close()
	dismiss_settle()
	# 存活期被丢弃后状态机停在 SETTLING，必须回到 SELECTING 才能选物种。
	if lifecycle != null and lifecycle.state == LifeCycle.State.SETTLING:
		_enter_select()
	if menu != null:
		menu.set_input_locked(false)
		menu.set_unlocked(_unlocked_ids())
		menu.set_session_state(false, false, "")
		menu.show_page(MainMenu.Page.SPECIES)
	_refresh_status()
	print("ENTRY|new_game|blocked_origin=%s|was_blocked=%s|state=%s" % [
		str(blocked_origin), str(was_blocked), lifecycle_state_name()
	])
	return true


func _apply_menu_session_state() -> void:
	if menu == null:
		return
	var notice := ""
	if _load_blocked:
		notice = _load_message if _load_message != "" else "存档损坏，已隔离；未载入"
	else:
		notice = _load_notice
	menu.set_session_state(can_continue_game(), _load_blocked, notice)


## T040：最近一次玩家落点解析结果（`{ok, position, reason, fallback, region_id, desired}`）。
var last_position_resolution: Dictionary = {}


## T040：读档/重生落点解析（合法原样返回；非法按最近导航点 → 区域中心 → 出生标记 → 原点回退）。
func resolve_safe_player_position(cfg: SpeciesConfig, desired: Vector3) -> Dictionary:
	if cfg == null:
		return {"ok": false, "position": desired, "reason": "no_config", "fallback": false}
	var resolved := PlacementSafetyLib.resolve_player_position(self, cfg, desired) as Dictionary
	last_position_resolution = resolved
	if not bool(resolved.get("fallback", false)):
		return resolved
	print("ENTRY|position_fallback|species=%s|from=%s|to=%s|reason=%s|region=%s" % [
		String(cfg.species_id), str(desired), str(resolved.get("position", desired)),
		String(resolved.get("reason", "")), String(resolved.get("region_id", "")),
	])
	return resolved


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


## 菜单展示模型（ART06 取证用：**只读**；不改变任何展示状态）
func showcase_nodes() -> Array[Node3D]:
	return _showcase


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
	# 发现 → 解锁规则（T031）：从物种配置 `unlock_discovery` 汇总（接线数据，覆盖式重写）
	var rules := {}
	for cfg in _configs:
		if cfg.unlock_discovery != &"":
			rules[String(cfg.unlock_discovery)] = cfg.species_id
	gs.call("set_discovery_unlock_rules", rules)
	# 读档成功时，解锁/发现由快照恢复；不能在这里补默认集（否则会覆盖存档进度）。
	if _loaded_snapshot.is_empty() and (gs.get("unlocked_species") as Dictionary).is_empty():
		if test_mode:
			gs.call("set_default_unlock", _all_ids())
		else:
			# 正式模式（T031，策划 §9.2「猫默认可选」）：初始解锁 = 配置里
			# `initially_unlocked` 的物种；不写物种名（数据在 `resources/species/*.tres`）。
			var initial: Array[StringName] = []
			for cfg in _configs:
				if cfg.initially_unlocked:
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
	_mount_rest_point()


## 区域种群账本初始化（T035）：建关卡后、铺生态前，按当前关卡 `level_regions`
## × 物种配置各建一条记录（差异只在 `*.tres` 的 Population 组，真源 Parameters:77）。
## **只在 `_ready` 调一次**：正式死亡→重生**不重置也不再 init**（与 T034 D3
## 时间语义同构）；`reset_for_new_game()` 后由下一次 MainEntry 构建重新 init。
func _init_region_population() -> void:
	if level == null:
		return
	var w := _wd()
	if w != null:
		w.call("init_region_population", _configs)



# ---------------------------------------------------------------------------
# 安全休息（T058）
# ---------------------------------------------------------------------------

## 在关卡里挂休息点（**运行期挂载**，不改关卡几何 —— 与资源点同一做法）。
## 幂等：同一个关卡里已经挂过就直接用现有的。
func _mount_rest_point() -> void:
	if level == null:
		return
	if rest_point != null and is_instance_valid(rest_point):
		return
	var packed := load(REST_POINT_SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("MainEntry: 休息点场景缺失 %s" % REST_POINT_SCENE_PATH)
		return
	var point := packed.instantiate()
	if point == null:
		return
	point.name = "RestPoint"
	level.add_child(point)
	if point is Node3D:
		(point as Node3D).global_position = REST_POINT_POSITION
	rest_point = point


## 休息信号 → Toast + 关键事务存档。`RestDirector` 只发信号（不碰 UI、不碰存档）。
## 用**节点查找**而不是 autoload 单例名：`--script` 下直接写单例名会编译期报错（T056 教训）。
func _wire_rest_director() -> void:
	if _rest_wired:
		return
	var rd := get_node_or_null("/root/RestDirector")
	if rd == null:
		return
	if rd.has_signal("rest_completed"):
		rd.connect("rest_completed", _on_rest_completed)
	if rd.has_signal("rest_refused"):
		rd.connect("rest_refused", _on_rest_refused)
	_rest_wired = true


## 休息成功：**完成即存档**（策划 v1.1 :305 的自动存档节点之一）。
func _on_rest_completed(result: Dictionary) -> void:
	if hud != null:
		hud.show_toast("休息完成：时间 +%.0f 秒，生命 +%.0f" % [
			float(result.get("seconds", 0.0)), float(result.get("gain", 0.0))])
	save_now(&"rest")


## 休息被拒：把 `RestDirector` 的理由翻成**玩家能看懂的原因**（不出现数字/内部枚举名）。
func _on_rest_refused(reason: StringName, _detail: Dictionary) -> void:
	if hud == null:
		return
	var msg := ""
	match reason:
		&"in_danger":
			msg = "正在被追猎，无法休息"
		&"insufficient_resources":
			msg = "食物或水分不足，撑不到休息结束"
		&"busy":
			msg = "正在行动中，无法休息"
		&"not_advancing":
			msg = "现在不能休息"
		&"dead":
			msg = ""
		_:
			msg = "无法休息"
	if msg != "":
		hud.show_toast(msg)

# ---------------------------------------------------------------------------
# 存档与读档（T037）
# ---------------------------------------------------------------------------

## 测试/取证工具显式打开自动存档（正式运行由 `_ready` 自行判定）。
func set_persistence_enabled(value: bool) -> void:
	_persist_enabled = value


func pending_settlement_life_id() -> String:
	var sm := _save_manager()
	return String(sm.get("pending_settlement_life_id")) if sm != null else ""


## 立即存一次（D9 的四个时机都走这里）。未启用时返回 `disabled`，不做任何写入。
func save_now(reason: StringName = &"manual") -> Dictionary:
	if not _persist_enabled:
		return {"ok": false, "status": "disabled", "message": "自动存档未启用"}
	if _load_blocked:
		return {"ok": false, "status": "blocked", "message": "存档损坏已隔离，未载入；本会话不写新档"}
	var sm := _save_manager()
	if sm == null:
		return {"ok": false, "status": "disabled", "message": "缺少 SaveManager"}
	# 存活期把最新四指标与位置同步进进行中档案（死亡后不再写，避免污染已归档记录）。
	if lifecycle != null and lifecycle.is_alive() and player != null and is_instance_valid(player) \
			and player.survival != null and player.survival.state != null:
		var gs := _game_state()
		if gs != null:
			gs.call("sync_current_life", player.survival.state.to_dictionary(),
				player.global_transform)
	var res: Dictionary = sm.call("request_save", reason, true, true)
	if String(res.get("status", "")) == "queued":
		res = sm.call("flush_queue_now")
	print("ENTRY|save|%s|ok=%s|revision=%d|status=%s" % [
		String(reason), str(res.get("ok", false)), int(res.get("revision", 0)),
		String(res.get("status", ""))
	])
	if not bool(res.get("ok", false)) and hud != null:
		hud.show_toast("存档写入失败")
	elif not String(res.get("warning", "")).is_empty() and hud != null:
		hud.show_toast(String(res.get("warning", "")))
	return res


## 启动读档（D9：只在正式运行/显式启用时执行）。校验通过的快照暂存，稍后按 D8 应用。
func _load_saved_game() -> void:
	if not _persist_enabled:
		return
	var sm := _save_manager()
	if sm == null:
		return
	var res: Dictionary = sm.call("load_game")
	_load_status = String(res.get("status", "none"))
	_load_message = String(res.get("message", ""))
	_load_repairs = res.get("repairs", [])
	if _load_status == "ok" or _load_status == "recovered_backup":
		_loaded_snapshot = res.get("snapshot", {})
	print("ENTRY|load|status=%s|repairs=%d|message=%s" % [
		_load_status, _load_repairs.size(), _load_message
	])


## 读档结果对玩家的可见反馈（复用 HUD Toast，不新建 UI）。
func _toast_load_status() -> void:
	var msg := ""
	if _load_status == "corrupt":
		msg = _load_message if _load_message != "" else "存档损坏，已隔离；未载入"
	elif _load_status == "version_mismatch":
		msg = _load_message if _load_message != "" else "存档版本不兼容，未载入"
	elif _load_status == "recovered_backup":
		msg = _load_message if _load_message != "" else "主存档损坏，已从备份恢复"
	elif _load_status == "ok" and _load_repairs.size() > 0:
		msg = _load_message
	if msg == "":
		return
	_load_notice = msg
	if hud != null and hud.visible:
		hud.show_toast(msg)
	print("ENTRY|load_notice|%s" % msg)


## 按 D8 顺序应用快照：世界时间 → 区域账本 → 资源点 → 长期层 → 当前生命。
## `restore_life=false` 时只恢复世界数据（`_ready` 早期调用，此时 HUD/状态机尚未建好）。
func apply_saved_snapshot(snapshot: Dictionary, restore_life: bool = true) -> bool:
	if snapshot.is_empty():
		return false
	var wd := _wd()
	if wd != null and snapshot.has("world_time"):
		wd.call("set_world_time", float(snapshot.get("world_time", 0.0)))
	if wd != null and snapshot.has("regions"):
		var report: Dictionary = wd.call("restore_region_population", snapshot.get("regions", []))
		print("ENTRY|load|regions|restored=%d|skipped=%s|repaired=%s" % [
			int(report.get("restored", 0)), str(report.get("skipped", [])),
			str(report.get("repaired", []))
		])
		# T040：账本恢复后立刻收敛旧会话遗留的 `active > total`（读档后重建生态前也要成立）。
		if wd.has_method("reconcile_region_population"):
			var anchor := Vector3.ZERO
			if player != null and is_instance_valid(player):
				anchor = player.global_position
			wd.call("reconcile_region_population", anchor)
	_apply_resources(snapshot.get("resources", []))
	var gs := _game_state()
	if gs != null:
		gs.call("restore_long_term", snapshot)
	if restore_life:
		_restore_life_from_snapshot(snapshot)
	return true


## 资源点：按稳定 `interaction_id` 匹配既有节点，缺失的**补建**；数值/位置用 `apply_record()`。
func _apply_resources(records: Variant) -> void:
	if level == null or not (records is Array):
		return
	var by_id := {}
	for node in get_tree().get_nodes_in_group(&"resource_points"):
		if node is ResourcePoint:
			by_id[String(node.get("interaction_id"))] = node
	var packed: PackedScene = null
	for raw in (records as Array):
		if not (raw is Dictionary):
			continue
		var rec: Dictionary = raw
		var id := String(rec.get("id", ""))
		if id == "":
			continue
		var point := by_id.get(id) as ResourcePoint
		if point == null:
			if packed == null:
				packed = load(RESOURCE_SCENE_PATH) as PackedScene
			if packed == null:
				continue
			point = packed.instantiate() as ResourcePoint
			if point == null:
				continue
			point.name = "Saved_%s" % id
			level.add_child(point)
		point.apply_record(rec)
		by_id[id] = point


## D8 最后一步：存活 → 直接恢复身体；待结算 → 补弹结算页；两者都没有 → false（进选物种）。
func _restore_life_from_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		return false
	var current: Dictionary = snapshot.get("current_life", {})
	if not current.is_empty():
		var cfg := _config_for(StringName(String(current.get("species_id", ""))))
		if cfg == null:
			if hud != null:
				hud.show_toast("存档中的物种配置缺失，未恢复当前生命")
			return false
		_spawn_restored_player(cfg, current)
		return true
	var pending := String(snapshot.get("pending_settlement_life_id", ""))
	if pending != "":
		var rec := _record_by_id(pending)
		if rec.is_empty():
			return false
		_last_record = rec
		_enter_select()
		_present_settle(rec)
		# D4：结算页已展示 → 清空 pending 并落盘（语义"死亡已发生、结算页尚未展示"）。
		_clear_pending_settlement()
		save_now(&"settle_shown")
		return true
	return false


## 读档恢复存活玩家：复用既有身体装配，但**不经** `mark_spawned`（不分配新 LifeId）。
func _spawn_restored_player(cfg: SpeciesConfig, life: Dictionary) -> void:
	dismiss_settle()
	var packed := load(BODY_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("MainEntry: 身体场景缺失 %s" % BODY_SCENE_PATH)
		return
	var body := packed.instantiate() as AnimalBody
	if body == null:
		push_error("MainEntry: 身体根节点不是 AnimalBody")
		return
	body.name = "Player"
	body.species_config = cfg
	body.player_controlled = true
	body.make_camera_current = true
	_dismiss_menu()
	level.add_child(body)
	var xform: Variant = life.get("transform")
	if xform is Transform3D:
		var xf: Transform3D = xform
		var resolved := resolve_safe_player_position(cfg, xf.origin)
		var xf_pos: Vector3 = resolved.get("position", xf.origin)
		xf.origin = xf_pos
		body.global_transform = xf
	else:
		var pos: Variant = life.get("start_position")
		var desired: Vector3 = pos if pos is Vector3 else _spawn_position(cfg)
		var resolved2 := resolve_safe_player_position(cfg, desired)
		var desired_pos: Vector3 = resolved2.get("position", desired)
		body.global_position = desired_pos
	_apply_settings_to(body)
	body.velocity = Vector3.ZERO
	if body.climb != null:
		body.climb.reset_base()
	# 四指标恢复（夹紧由 `set_state()` 按当前物种配置做）。
	var survival_data: Variant = life.get("snapshot")
	if body.survival != null and survival_data is Dictionary and not (survival_data as Dictionary).is_empty():
		body.survival.set_state(SurvivalState.from_dictionary(survival_data))
	player = body
	var subs_restore := get_node_or_null("/root/SubtitleDirector")
	if subs_restore != null and subs_restore.has_method("bind_player"):
		subs_restore.call("bind_player", body)
	if not lifecycle.restore_alive(body, String(life.get("life_id", "")),
			StringName(String(life.get("species_id", "")))):
		push_error("MainEntry: 读档恢复存活失败")
		return
	if discovery != null:
		discovery.player = body
		discovery.refresh_points()
	if hud != null:
		hud.bind_player(body)
	# 从当前数值起算增量，避免"读档后第一帧"把差值误记成进食/饮水收益。
	if body.survival != null and body.survival.state != null:
		_last_hunger = body.survival.state.hunger
		_last_thirst = body.survival.state.thirst
		body.survival.died.connect(_on_player_died)
		body.survival.changed.connect(_on_survival_changed)
	if ecology != null and is_instance_valid(ecology):
		ecology.candidates = _configs
		ecology.setup(body, body.global_position)
		_wire_npc_events()
		var wd := _wd()
		if wd != null and wd.has_method("reconcile_region_population"):
			wd.call("reconcile_region_population", body.global_position)
	_refresh_status()
	print("ENTRY|restored|%s|life=%s|pos=%s" % [
		String(cfg.species_id), String(life.get("life_id", "")), str(body.global_position)
	])


func _record_by_id(life_id: String) -> Dictionary:
	var gs := _game_state()
	if gs == null or life_id == "":
		return {}
	for rec in (gs.get("life_records") as Array):
		if String((rec as Dictionary).get("life_id", "")) == life_id:
			return (rec as Dictionary).duplicate(true)
	return {}


func _clear_pending_settlement() -> void:
	var sm := _save_manager()
	if sm != null:
		sm.set("pending_settlement_life_id", "")


func _save_manager() -> Node:
	var r := _tree_root()
	return r.get_node_or_null("SaveManager") if r != null else null


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
	# T056：字幕挂显示通道；环境音按关卡里的水体布点
	# T056：字幕挂显示通道、环境音按水体布点。用**节点查找**而不是 autoload 单例名 ——
	# `--script` 运行方式下直接写单例名会在编译期报 `Identifier not found`（实测全量批 3 套红）。
	var subs := get_node_or_null("/root/SubtitleDirector")
	if subs != null and subs.has_method("bind_hud"):
		subs.call("bind_hud", hud)
	var amb := get_node_or_null("/root/AmbienceDirector")
	if amb != null and amb.has_method("bind_level"):
		amb.call("bind_level", level)
	# T057：昼夜光照按世界时间重算（无状态，读档后自然正确）
	var dn := get_node_or_null("/root/DayNightDirector")
	if dn != null and dn.has_method("bind_level"):
		dn.call("bind_level", level)
	# T058：休息的提示与完成存档（`RestDirector` 只发信号，不碰 UI / 存档）
	_wire_rest_director()


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
	_build_discovery_tracker()


## 地点发现（T031）：只观察组件。出生时注入玩家，结算时置空；记录与解锁都在 `GameState`。
func _build_discovery_tracker() -> void:
	discovery = DiscoveryTracker.new()
	discovery.name = "DiscoveryTracker"
	add_child(discovery)
	discovery.place_discovered.connect(_on_place_discovered)


func _on_place_discovered(place_id: String) -> void:
	# 发现 + 解锁都已在 `GameState` 落档（事件 discovery / species_unlock）；
	# 这里只留一行可检索的运行证据（世界时间见事件本体）。
	print("ENTRY|discovery|%s|life=%s|unlocked=%s" % [
		place_id, lifecycle.life_id if lifecycle != null else "",
		str(_unlocked_ids())
	])


# ---------------------------------------------------------------------------
# 发现/解锁的玩家可见反馈（T033，`Docs/Tasks/T033.md` D4/D5）
# ---------------------------------------------------------------------------

## 接线 `GameState` 的长期层信号：菜单/入口都**只观察**，不写回 GameState。
func _wire_gamestate_signals() -> void:
	var gs := _game_state()
	if gs == null:
		return
	if not gs.is_connected("species_unlocked", _on_species_unlocked):
		gs.connect("species_unlocked", _on_species_unlocked)
	# 走 GameState 信号而不是 DiscoveryTracker 的：测试/取证直接调
	# `record_place_discovery()` 的路径同样有提示（解锁链两步走同一条接线）。
	if not gs.is_connected("place_discovered", _on_place_discovered_toast):
		gs.connect("place_discovered", _on_place_discovered_toast)


## 解锁发生（发现→解锁链、或未来其它解锁途径）：菜单即时刷新 + HUD Toast。
## 显示名来自 `SpeciesConfig.display_title()`——入口不写物种名（配套要求 §1）。
func _on_species_unlocked(species_id: StringName) -> void:
	if menu != null:
		menu.set_unlocked(_unlocked_ids())
	var cfg := _config_for(species_id)
	if hud != null and cfg != null:
		hud.show_toast("新物种已解锁：%s" % cfg.display_title())
	_refresh_status()
	print("ENTRY|unlock|%s|unlocked=%s" % [String(species_id), str(_unlocked_ids())])
	# T037 D9：解锁发生即落盘（跨世进度不能只留在内存）。
	save_now(&"unlock")


## 发现新地点：Toast 只报稳定 ID（地点没有配置化显示名，不编名字）。
func _on_place_discovered_toast(place_id: String) -> void:
	if hud != null:
		hud.show_toast("发现新地点：%s" % place_id)
	# T037 D9：新发现即落盘（`discovered_ids` 是跨世保留项）。
	save_now(&"discovery")


# ---------------------------------------------------------------------------
# 生命结算覆盖层（T032）
# ---------------------------------------------------------------------------

## 结算页与菜单同层、**后加入**（同 canvas 后加入者绘制在上；不是 CanvasLayer——T030 H8 契约）。
## T041：确认层先于结算页加入 → `MainMenu < LifeStatus < NewGameConfirm < LifeSettlePanel`。
func _build_confirm() -> void:
	confirm_dialog = NewGameConfirm.new()
	confirm_dialog.name = "NewGameConfirm"
	add_child(confirm_dialog)
	confirm_dialog.confirmed.connect(_on_new_game_confirmed)
	confirm_dialog.cancelled.connect(_on_new_game_cancelled)


## T042：暂停层 + 结束确认。调用点在 `_build_hud()` 之后、`_build_menu()` 之前 →
## `Hud < PauseMenu < EndLifeConfirm < MainMenu < LifeStatus < NewGameConfirm < LifeSettlePanel`。
func _build_pause_layers() -> void:
	pause_menu = PAUSE_MENU_SCRIPT.new() as Control
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.resume_requested.connect(_on_pause_resume_requested)
	pause_menu.end_life_requested.connect(_on_pause_end_life_requested)
	end_life_confirm = END_LIFE_CONFIRM_SCRIPT.new() as Control
	end_life_confirm.name = "EndLifeConfirm"
	add_child(end_life_confirm)
	end_life_confirm.confirmed.connect(_on_end_life_confirmed)
	end_life_confirm.cancelled.connect(_on_end_life_cancelled)


func _build_settle_panel() -> void:
	settle_panel = LifeSettlePanel.new()
	settle_panel.name = "LifeSettlePanel"
	add_child(settle_panel)


## `life_settled` 之后呈现结算页（决策 D1：`_enter_select()` 时序不变，面板只是盖在上面的呈现层）。
## 数据全部来自刚归档的结算记录 + `GameState.events_for()`（决策 D2：零平行数据结构）。
func _present_settle(record: Dictionary) -> void:
	if record.is_empty() or settle_panel == null:
		return
	var titles := {}
	for cfg in _configs:
		titles[String(cfg.species_id)] = cfg.display_title()
	var kinds := {}
	var gs := _game_state()
	if gs != null:
		var evs: Array = gs.call("events_for", String(record.get("life_id", "")))
		for e in evs:
			var k := String((e as Dictionary).get("kind", ""))
			kinds[k] = int(kinds.get(k, 0)) + 1
	settle_panel.present(record, {"species_titles": titles, "event_kinds": kinds})
	print("ENTRY|settle|life=%s|duration=%.1f|end=%s|damage=%s" % [
		String(record.get("life_id", "?")), float(record.get("duration", -1.0)),
		String(record.get("end_reason", "")), String(record.get("damage_reason", "")),
	])


## 关闭结算页（测试 / 取证工具用；面板自己的确认路径见 `LifeSettlePanel`）。
func dismiss_settle() -> void:
	if settle_panel != null:
		settle_panel.dismiss()


# ---------------------------------------------------------------------------
# 暂停与主动结束（T042）
# ---------------------------------------------------------------------------

func is_paused() -> bool:
	return _paused


## 存活期打开暂停：树暂停 + 世界时钟门闩双保险；结算页/确认层存在时拒绝。
func open_pause() -> bool:
	if _paused:
		return true
	if lifecycle == null or not lifecycle.is_alive():
		return false
	if settle_panel != null and settle_panel.is_presenting():
		return false
	if confirm_dialog != null and confirm_dialog.is_open():
		return false
	if end_life_confirm != null and end_life_confirm.is_open():
		return false
	if pause_menu == null:
		return false
	_paused = true
	_apply_time_gate(false)
	if get_tree() != null:
		get_tree().paused = true
	pause_menu.open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("ENTRY|pause|open|world_time=%.4f|advancing=false" % world_time_now())
	return true


## 恢复：逐字段还原（暂停期没有任何节点跑 `_process/_physics_process`）。
func resume_game() -> bool:
	if not _paused:
		return false
	if end_life_confirm != null:
		end_life_confirm.close()
	if pause_menu != null:
		pause_menu.close()
	_paused = false
	if get_tree() != null:
		get_tree().paused = false
	if lifecycle != null and lifecycle.is_alive():
		_apply_time_gate(true)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("ENTRY|pause|resume|world_time=%.4f|advancing=%s" % [
		world_time_now(), str(lifecycle != null and lifecycle.is_alive())
	])
	return true


## Esc 优先级唯一入口：结算页 > 确认层 > 暂停。返回是否消费。
func handle_escape() -> bool:
	if settle_panel != null and settle_panel.is_presenting():
		return false
	if confirm_dialog != null and confirm_dialog.is_open():
		return false
	if end_life_confirm != null and end_life_confirm.is_open():
		cancel_end_life()
		return true
	if _paused:
		resume_game()
		return true
	if lifecycle != null and lifecycle.is_alive():
		return open_pause()
	return false


## 暂停菜单里的「结束本次生命」→ 打开二次确认（默认「取消」）。
func request_end_life() -> bool:
	if not _paused:
		return false
	if lifecycle == null or not lifecycle.is_alive():
		return false
	if end_life_confirm == null:
		return false
	end_life_confirm.open()
	print("ENTRY|end_life_confirm|open|focus=%s" % end_life_confirm.default_button_text())
	return true


func cancel_end_life() -> bool:
	if end_life_confirm == null or not end_life_confirm.is_open():
		return false
	end_life_confirm.cancel()
	return true


func confirm_end_life() -> bool:
	if end_life_confirm == null or not end_life_confirm.is_open():
		return false
	end_life_confirm.confirm()
	return true


## 确认后走 `_on_player_died` 同一条正常死亡路径：归档 → pending → death/settle 两次写 → 结算页。
## 禁止直接重生/清档/跳结算；重生仍由玩家在结算后选物种。
func _on_end_life_confirmed() -> void:
	if not _paused:
		return
	if end_life_confirm != null:
		end_life_confirm.close()
	if pause_menu != null:
		pause_menu.close()
	_paused = false
	if get_tree() != null:
		get_tree().paused = false
	if lifecycle == null or not lifecycle.is_alive():
		_apply_time_gate(false)
		return
	var life := lifecycle.life_id
	var sm := _save_manager()
	if sm != null:
		sm.set("pending_settlement_life_id", life)
	lifecycle.end_life(&"died", {"damage_reason": "player_quit"})
	print("ENTRY|end_life|player_quit|life=%s|archive=%d|settle=%d" % [
		life, archive_count(), lifecycle.settle_count
	])
	save_now(&"death")


func _on_pause_resume_requested() -> void:
	resume_game()


func _on_pause_end_life_requested() -> void:
	request_end_life()


func _on_end_life_cancelled() -> void:
	pass


func _apply_time_gate(value: bool) -> void:
	var wd := _wd()
	if wd != null:
		wd.set("time_advancing", value)


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
		_apply_menu_session_state()
		# 读档提示借用菜单的「上一世」文字位（HUD 在此被隐藏），消费一次即清空。
		var previous := _previous_record_text()
		if _load_notice != "" and not _load_blocked:
			previous = _load_notice if previous == "" else "%s\n%s" % [_load_notice, previous]
			_load_notice = ""
		menu.open_menu(previous)
		if confirm_dialog != null and confirm_dialog.is_open():
			menu.set_input_locked(true)
	if hud != null:
		hud.visible = false
	if status_label != null:
		status_label.visible = false
	_build_showcase()
	if menu_camera != null:
		menu_camera.current = true
	if menu_fill != null:
		menu_fill.visible = true
	if menu_rim != null:
		menu_rim.visible = true
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
	if menu_rim != null:
		menu_rim.visible = false


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
	if _discarding_new_game:
		# 新游戏主动丢弃的一世：不展示结算、不写盘（清档后立刻写新档会违背“确认后才清”）。
		_last_record = {}
		if hud != null:
			hud.unbind()
		player = null
		if discovery != null:
			discovery.player = null
		return
	_last_record = record
	if hud != null:
		hud.unbind()
	player = null
	if discovery != null:
		discovery.player = null
	_enter_select()
	_present_settle(record)
	# T037 D4/D9：结算页已展示 → 清空 pending 并落盘（第二次写，与死亡时的第一次成对）。
	_clear_pending_settlement()
	save_now(&"settle_shown")


## 创建玩家身体并回呼 `mark_spawned()`（决策 D1：状态机不建节点）。
func _spawn_player(species_id: StringName) -> void:
	# 出生即离开结算页（决策 D7：`select_species()` 直接出生时也要收起）
	dismiss_settle()
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
	var resolved := resolve_safe_player_position(cfg, spawn)
	var resolved_pos: Vector3 = resolved.get("position", spawn)
	spawn = resolved_pos
	body.global_position = spawn
	_apply_settings_to(body)
	body.velocity = Vector3.ZERO
	if body.climb != null:
		body.climb.reset_base()

	player = body
	var subs_spawn := get_node_or_null("/root/SubtitleDirector")
	if subs_spawn != null and subs_spawn.has_method("bind_player"):
		subs_spawn.call("bind_player", body)
	lifecycle.mark_spawned(body, spawn)
	if discovery != null:
		discovery.player = body
		discovery.refresh_points()

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
	if not _wd_death_hooked:
		var wdd := _wd()
		if wdd != null and wdd.has_signal("region_natural_death"):
			wdd.connect("region_natural_death", _on_region_natural_death)
			_wd_death_hooked = true

	if ecology != null and is_instance_valid(ecology):
		ecology.candidates = _configs
		ecology.setup(body, spawn)
		_wire_npc_events()
		var wd := _wd()
		if wd != null and wd.has_method("reconcile_region_population"):
			wd.call("reconcile_region_population", spawn)
	_refresh_status()
	print("ENTRY|spawn|%s|life=%s|pos=%s|npc=%d" % [
		String(species_id), lifecycle.life_id, str(spawn), npc_count()
	])


func _on_player_died(reason: StringName) -> void:
	if lifecycle == null or not lifecycle.is_alive():
		return
	# T037 D4：先标记"死亡已发生、结算页尚未展示"，再归档 → 结算页呈现后清空。
	var sm := _save_manager()
	if sm != null:
		sm.set("pending_settlement_life_id", lifecycle.life_id)
	lifecycle.end_life(&"died", {"damage_reason": String(reason)})
	print("ENTRY|died|life=%s|reason=%s|archive=%d" % [
		lifecycle.life_id, String(reason), archive_count()
	])
	# T037 D9：死亡结算时写第一次（pending 非空）。
	save_now(&"death")


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
	# T036：把存活状态与当前位置同步进进行中档案（存档读回的「当前生命状态与位置」）。
	# 复用本回调的既有 0.2 s 节流，不新增每帧写入。
	if player != null and is_instance_valid(player):
		gs.call("sync_current_life", state.to_dictionary(), player.global_transform)


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
	# T040：捕获扣账已在 `report_capture` 同一次调用内完成；这里再收敛一次，
	# 保证其他历史超额（如读档前遗留）也不会让 `active > total` 跨帧存在。
	var wd := _wd()
	if wd != null and wd.has_method("reconcile_region_population"):
		wd.call("reconcile_region_population", player.global_position)


## T040b：自然死亡扣账后立即尝试收敛（若之前有近处保留的超额，这里可能仍保留）。
func _on_region_natural_death(_body_id: String, _region_id: String, _species_id: String,
		_reason: StringName, _world_time: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var wd := _wd()
	if wd != null and wd.has_method("reconcile_region_population"):
		wd.call("reconcile_region_population", player.global_position)


## T040b：玩家走远后由低频重试收敛；没有 pending 时完全不碰账本。
func _retry_pending_reconcile() -> void:
	if player == null or not is_instance_valid(player):
		return
	var wd := _wd()
	if wd == null or not wd.has_method("reconcile_region_population"):
		return
	var raw = wd.get("last_reconcile")
	if not (raw is Dictionary):
		return
	var last: Dictionary = raw
	if int(last.get("pending_excess", 0)) <= 0:
		return
	var rep_raw = wd.call("reconcile_region_population", player.global_position)
	var rep: Dictionary = rep_raw if rep_raw is Dictionary else {}
	if int(rep.get("removed", 0)) > 0:
		print("ENTRY|reconcile_retry|removed=%d|pending=%d|player=%s" % [
			int(rep.get("removed", 0)), int(rep.get("pending_excess", 0)),
			player.global_position])


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
			# T034 D5：存活读数带昼夜时钟（数据来自 WorldDirector 纯函数，入口不存平行时钟）
			var day := 1
			var phase := "白天"
			var wd := _wd()
			if wd != null:
				day = int(wd.call("day_index")) + 1
				phase = "白天" if bool(wd.call("is_daytime")) else "夜晚"
			status_label.text = "%s %s｜第 %d 天·%s｜存活 %.1f s" % [
				lifecycle.life_id, String(lifecycle.species_id), day, phase, _life_elapsed()
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
	# 选中项变化 → 主视觉换人（ART06：主视觉跟着选中的物种走）
	menu.selection_changed.connect(_on_menu_selection_changed)
	# 入树之后再 build：卡片预览要用 `World3D` 与 `look_at`。
	# T033：显式传入当前解锁集（正式模式只有初始解锁物种可玩；test_mode 全解锁）——
	# 菜单据此呈现锁定卡（数据来自 `GameState.unlocked_species`，入口不写物种名）
	menu.build(_configs, current_settings(), _unlocked_ids())
	menu.species_committed.connect(_on_menu_species_committed)
	menu.setting_changed.connect(_on_menu_setting_changed)
	menu.quit_requested.connect(_on_menu_quit)
	menu.resume_requested.connect(_on_menu_resume)
	menu.new_game_requested.connect(_on_menu_new_game)
	_apply_menu_session_state()
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
	# ART10：菜单轮廓光——展板主视觉是侧逆光，动物毛边有一圈暖金亮边；实机旧帧
	# 展示模型被判读"光照平、无立体感"。灯挂在 MenuCamera 下、朝镜头方向打（绕 Y 转 180°），
	# 只照亮主体的背光边缘；与 MenuFill 同开同关，出生即隐藏，不进玩法。
	menu_rim = DirectionalLight3D.new()
	menu_rim.name = "MenuRim"
	menu_rim.light_energy = 0.85
	menu_rim.light_color = Color(1.0, 0.82, 0.60)
	menu_rim.shadow_enabled = false
	menu_rim.rotation_degrees = Vector3(-6.0, 180.0, 0.0)
	menu_rim.visible = false
	menu_camera.add_child(menu_rim)


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


## 主视觉展示（ART06）：菜单里**只展示当前选中的物种**，把它放在画面中央当主视觉；
## 其余物种不再挤在同一个机位里（ART04 是两只并排，鼠只占屏高约 2%，实际读不出体态），
## 由右侧卡片各自的实时 3D 预览承担（`MainMenu._make_preview()`），鼠仍是可选卡片。
##
## 选中项来自 `MainMenu.selected_species()`（数据驱动）：本文件不出现物种名，也不写死数量。
## 默认选中 = 物种配置排序后的第一个（当前数据下就是猫），所以默认主视觉是猫。
func _build_showcase() -> void:
	_clear_showcase()
	if level == null or menu_camera == null or _configs.is_empty():
		return
	var hero := _hero_config()
	if hero == null:
		return
	var focus := _menu_focus_ground()
	var camera_pos := menu_camera.global_position
	var inst := hero.visual_scene.instantiate() as Node3D
	if inst == null:
		return
	inst.name = "Showcase_%s" % String(hero.species_id)
	level.add_child(inst)
	# 体型差补偿（沿用 ART04 的做法）：小体型物种沿"朝向相机"方向前移，否则鼠选进来只有十几个像素高。
	var to_camera := camera_pos - focus
	to_camera.y = 0.0
	to_camera = to_camera.normalized()
	var depth := (_max_capsule_height() - hero.capsule_height()) * MENU_SHOWCASE_DEPTH_SCALE
	var pos := focus + to_camera * depth
	pos.y = focus.y
	inst.global_position = pos
	# 模型本地面朝 −Z：`look_at` 让 −Z 指向相机 → 正好朝观众
	inst.look_at(Vector3(camera_pos.x, pos.y, camera_pos.z), Vector3.UP)
	_showcase_idle(inst)
	_showcase.append(inst)


## 主视觉物种：优先当前选中项；没有选中或它没有视觉资产时退回"第一个有视觉资产的物种"。
func _hero_config() -> SpeciesConfig:
	var selected: StringName = menu.selected_species() if menu != null else &""
	var picked := _config_for(selected)
	if picked != null and picked.visual_scene != null:
		return picked
	for cfg in _configs:
		if cfg.visual_scene != null:
			return cfg
	return null


## 配置里最大的胶囊高度（体型差补偿的基准；没有物种时给 0）
func _max_capsule_height() -> float:
	var h := 0.0
	for cfg in _configs:
		h = maxf(h, cfg.capsule_height())
	return h


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


## 菜单选中项变了 → 换主视觉（ART06）。只在菜单可见时重建：出生后再改选中状态不动场景。
func _on_menu_selection_changed(_species_id: StringName) -> void:
	if menu == null or not menu.visible:
		return
	_build_showcase()
