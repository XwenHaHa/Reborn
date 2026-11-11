extends SceneTree
## T061：**完整流程回归**（开发计划 :253）
##
## 验收词：「**两种物种、捕猎、死亡、重生、存档、暂停、休息**全链路；**无阻断缺陷**」。
##
## 与其它套件的分工：T021/T022/T037/T042/T058 各自测"某一个环节"；本套件是**串起来跑一遍真实入口**
## （`main.tscn`，正式模式、靠"发现鼠洞"真解锁鼠，不用 `test_mode` 抄近道），
## 断言每个环节都能走到、且走到下一环节时**没有被卡住**。
##
## 链路：
##   A 启动/选猫出生 → B 捕猎（扑击→捕获→生成食物→进食）→ C 休息点休息（+60 s / +10 生命）
##   → D 暂停/恢复（世界时间冻结）→ E 发现鼠洞→**鼠解锁** → F 猫死亡→结算→回菜单
##   → G 选鼠出生 → H 存档→**新会话读档**（物种/位置/生存值恢复）→ I 鼠休息 → J 鼠死亡→结算→收尾
##
## 运行（零窗口：GUI exe + `--headless`）：
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Headless `
##       -Script tests/run_t061_full_flow.gd -TimeoutSec 600

const MAIN_SCENE := "res://scenes/core/main.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CAT_CFG := "res://resources/species/cat.tres"
const MOUSE_CFG := "res://resources/species/mouse.tres"
const TEST_DIR := "user://t061_flow"
const SAVE_PATH := "user://t061_flow/savegame_v1.json"
const SETTINGS_PATH := "user://t061_flow/settings.cfg"

const CAT_ID := &"Cat"
const MOUSE_ID := &"Mouse"

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _entry: Node = null
var _cat_cfg: SpeciesConfig = null
var _mouse_cfg: SpeciesConfig = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	_cat_cfg = load(CAT_CFG) as SpeciesConfig
	_mouse_cfg = load(MOUSE_CFG) as SpeciesConfig
	if not _assert("A0_configs", "两物种配置可加载",
			"%s/%s" % [str(_cat_cfg != null), str(_mouse_cfg != null)],
			_cat_cfg != null and _mouse_cfg != null):
		_finish()
		return
	_clean_dir()
	_write_fresh_settings()
	var sm := root.get_node_or_null("/root/SaveManager")
	if sm == null:
		_assert("A0_save_manager", "SaveManager 存在", "null", false)
		_finish()
		return
	sm.set("allow_headless_writes", true)
	sm.call("set_save_path", SAVE_PATH)

	await _stage_a_boot_cat()
	await _stage_b_hunt()
	await _stage_c_rest()
	await _stage_d_pause()
	await _stage_e_discover_mouse()
	await _stage_f_cat_death()
	await _stage_g_boot_mouse()
	await _stage_h_save_load()
	await _stage_i_mouse_rest()
	await _stage_j_mouse_death()
	_finish()


# ---------------------------------------------------------------------------
# A：启动 → 正式解锁门 → 选猫出生
# ---------------------------------------------------------------------------

func _stage_a_boot_cat() -> void:
	_entry = await _boot(false)
	if _entry == null:
		_assert("A1_boot", "实例化 main.tscn", "null", false)
		return
	_assert("A1_state_selecting", "selecting", _state(), _state() == "selecting")
	var gs := root.get_node_or_null("/root/GameState")
	var unlocked: Array = gs.call("unlocked_list")
	_assert("A2_only_cat_unlocked", "只有猫", str(unlocked),
		unlocked.size() == 1 and StringName(unlocked[0]) == CAT_ID)

	var ok: bool = bool(_entry.call("select_species", CAT_ID))
	await _wait(0.3)
	_assert("A3_cat_spawn", "alive 且玩家存在", "%s / %s" % [_state(), str(_entry.get("player") != null)],
		ok and _state() == "alive" and _entry.get("player") != null)
	var player: AnimalBody = _entry.get("player")
	if player == null:
		return
	_assert("A4_cat_config", "Cat 胶囊 0.48",
		"%.2f" % player.species_config.capsule_height(),
		absf(player.species_config.capsule_height() - 0.48) <= 1e-3)
	_assert("A5_hud_bound", "HUD 在树里且有文字",
		"%s | %s" % [str(_entry.get("hud") != null), _hud_text().substr(0, 12)],
		_entry.get("hud") != null and not _hud_text().is_empty())
	_assert("A6_rest_point", "Level/RestPoint 存在",
		str(_rest_point() != null), _rest_point() != null)
	# 世界时间在走
	var t0 := _world_time()
	await _wait(0.25)
	_assert("A7_time_advancing", "世界时间前进", "%.3f → %.3f" % [t0, _world_time()],
		_world_time() > t0 + 0.05)


# ---------------------------------------------------------------------------
# B：捕猎（真实扑击 → 捕获 → 食物 → 进食）
# ---------------------------------------------------------------------------

func _stage_b_hunt() -> void:
	var player: AnimalBody = _entry.get("player")
	if player == null:
		return
	var prey := _spawn_prey(player)
	if prey == null:
		_assert("B1_prey", "生成鼠 NPC", "null", false)
		return
	_assert("B1_prey_placed", "鼠在 1.5 m 内",
		"%.2f m" % player.global_position.distance_to(prey.global_position),
		player.global_position.distance_to(prey.global_position) <= 1.5)

	# 玩家控制会每帧用 Input 覆盖 `want_pounce` / `want_interact`（`_read_input()`），
	# 所以本段用手写意图前先关掉玩家控制（T021/T022 夹具同口径），结束时再打开。
	player.player_controlled = false

	var wd := root.get_node_or_null("/root/WorldDirector")
	var before_captures := int(wd.get("capture_count"))
	player.want_pounce = true
	var captured := await _wait_until(3.0, func() -> bool:
		return int(wd.get("capture_count")) > before_captures)
	_assert("B2_capture", "捕获计数 +1", "%d（等了 %.2f s）" % [int(wd.get("capture_count")), captured],
		int(wd.get("capture_count")) == before_captures + 1)
	_assert("B3_prey_marked", "猎物被标记 captured", str(prey.get("captured")), bool(prey.get("captured")))

	var food := _capture_food()
	_assert("B4_food_spawned", "生成捕获食物（容量 1）", str(food != null), food != null)
	if food == null:
		return

	# 进食：走真实交互（`press_interact` + 世界时间推进），Hunger 必须上升
	player.survival.state.hunger = 45.0
	var hunger0 := player.survival.state.hunger
	food.global_position = player.global_position + player.global_transform.basis.z * -0.35 + Vector3.UP * 0.05
	await _wait(0.15)
	# 注意：本段 `player_controlled=false`，`want_interact` 不会被消费（`_update_interact_input` 直接返回），
	# 所以走检测器自己的入口 `press_interact()`（T022 同口径），交互时长仍由世界时间推进。
	var started: bool = bool(player.interaction.call("press_interact"))
	_assert("B5a_interact_started", "交互已开始", str(started), started)
	var ate := await _wait_until(3.0, func() -> bool:
		return player.survival.state.hunger > hunger0 + 0.5)
	if ate >= 3.0:
		player.interaction.call("release_interact", &"t061_timeout")
	_assert("B5_eat_hunger_up", "Hunger 上升", "%.2f → %.2f（%.2f s）" % [
		hunger0, player.survival.state.hunger, ate],
		player.survival.state.hunger > hunger0 + 0.5)
	_assert("B6_food_consumed", "食物被吃空（容量 1）", "%d" % int(food.get("units")),
		int(food.get("units")) == 0)
	# 恢复玩家控制（后续阶段不再需要手写移动意图）
	player.player_controlled = true
# ---------------------------------------------------------------------------
# C：休息点休息（+60 s / +10 生命）
# ---------------------------------------------------------------------------

func _stage_c_rest() -> void:
	var player: AnimalBody = _entry.get("player")
	var point := _rest_point()
	if player == null or point == null:
		_assert("C1_rest_preconditions", "玩家与休息点都在", "null", false)
		return
	player.survival.state.health = 70.0
	player.survival.set("last_world_time", _world_time())
	point.global_position = player.global_position
	await _wait(0.15)
	var t_before := _world_time()
	var res: Dictionary = point.call("commit_interaction", player, "t061_rest_cat")
	_assert("C1_rest_ok", "commit success", str(res.get("success")), bool(res.get("success", false)))
	_assert("C2_rest_time", "+60 s", "%.3f → %.3f" % [t_before, _world_time()],
		absf(_world_time() - t_before - 60.0) <= 0.5)
	_assert("C3_rest_health", "生命 70 → 80", "%.2f" % player.survival.state.health,
		absf(player.survival.state.health - 80.0) <= 1.0)


# ---------------------------------------------------------------------------
# D：暂停 / 恢复（世界时间冻结）
# ---------------------------------------------------------------------------

func _stage_d_pause() -> void:
	var opened: bool = bool(_entry.call("open_pause"))
	_assert("D1_pause_open", "暂停层打开", str(opened), opened)
	var t0 := _world_time()
	await _wait(0.35)
	_assert("D2_time_frozen", "暂停期世界时间不动", "%.3f → %.3f" % [t0, _world_time()],
		absf(_world_time() - t0) <= 1e-6)
	var resumed: bool = bool(_entry.call("resume_game"))
	_assert("D3_resume", "恢复成功", str(resumed), resumed)
	var t1 := _world_time()
	await _wait(0.3)
	_assert("D4_time_resumes", "恢复后世界时间继续走", "%.3f → %.3f" % [t1, _world_time()],
		_world_time() > t1 + 0.05)
	_assert("D5_not_paused", "树未暂停", str(paused), not paused)


# ---------------------------------------------------------------------------
# E：发现鼠洞 → 鼠解锁（正式解锁链，不用 test_mode）
# ---------------------------------------------------------------------------

func _stage_e_discover_mouse() -> void:
	var player: AnimalBody = _entry.get("player")
	var level: Node3D = _entry.get("level")
	if player == null or level == null:
		_assert("E1_discovery_preconditions", "玩家与关卡都在", "null", false)
		return
	var marker := level.get_node_or_null("Discovery_RootHole") as Node3D
	if marker == null:
		_assert("E1_marker", "关卡有 Discovery_RootHole", "null", false)
		return
	player.global_position = marker.global_position + Vector3(0.5, 0.2, 0.0)
	var gs := root.get_node_or_null("/root/GameState")
	var unlocked := await _wait_until(3.0, func() -> bool:
		var list: Array = gs.call("unlocked_list")
		return list.has(MOUSE_ID))
	var list_after: Array = gs.call("unlocked_list")
	_assert("E2_mouse_unlocked", "鼠已解锁（等了 %.2f s）" % unlocked, str(list_after),
		list_after.has(MOUSE_ID))


# ---------------------------------------------------------------------------
# F：猫死亡 → 结算页 → 回菜单
# ---------------------------------------------------------------------------

func _stage_f_cat_death() -> void:
	_kill_player()
	var settled := await _wait_until(3.0, func() -> bool:
		return _state() != "alive")
	_assert("F1_cat_death", "离开 alive（等了 %.2f s）" % settled, _state(), _state() != "alive")
	_entry.call("dismiss_settle")
	await _wait(0.3)
	var gs := root.get_node_or_null("/root/GameState")
	_assert("F2_settle_dismissed", "回菜单（selecting）", _state(), _state() == "selecting")
	_assert("F3_archive_recorded", "档案 1 条",
		"%d（revision=%d）" % [int(gs.call("archive_count")), int(_wd_revision())],
		int(gs.call("archive_count")) == 1)
	var rec: Dictionary = _entry.call("last_record")
	_assert("F4_record_cat", "档案物种 = Cat", str(rec.get("species_id", "")),
		StringName(rec.get("species_id", "")) == CAT_ID)


# ---------------------------------------------------------------------------
# G：选鼠出生（用真实解锁，不用 test_mode）
# ---------------------------------------------------------------------------

func _stage_g_boot_mouse() -> void:
	var ok: bool = bool(_entry.call("select_species", MOUSE_ID))
	await _wait(0.35)
	var player: AnimalBody = _entry.get("player")
	_assert("G1_mouse_spawn", "鼠出生（alive）", "%s / %s" % [_state(), str(player != null)],
		ok and _state() == "alive" and player != null)
	if player == null:
		return
	_assert("G2_mouse_config", "Mouse 胶囊 0.18", "%.2f" % player.species_config.capsule_height(),
		absf(player.species_config.capsule_height() - 0.18) <= 1e-3)
	_assert("G3_new_life_id", "换了新的 LifeId", String(_entry.call("current_life_id")),
		String(_entry.call("current_life_id")) != "")


# ---------------------------------------------------------------------------
# H：存档 → 新会话读档
# ---------------------------------------------------------------------------

func _stage_h_save_load() -> void:
	var player: AnimalBody = _entry.get("player")
	if player == null:
		return
	player.survival.state.hunger = 61.0
	player.survival.state.thirst = 62.0
	player.survival.state.health = 80.0
	player.global_position = Vector3(2.0, 0.30, 21.0)
	# 存活期档案的 `transform` 由 `sync_current_life()` 节流同步（T036，0.2 s），
	# 所以传送后要等过一拍再存，否则存进去的还是出生点。
	await _wait(0.5)
	var saved_pos := player.global_position
	var saved: Dictionary = _entry.call("save_now", &"t061")
	_assert("H1_save_ok", "写盘成功", str(saved.get("ok", saved)), bool(saved.get("ok", false)))
	var life_before := String(_entry.call("current_life_id"))
	var t_before := _world_time()
	# 存档文件里**实际写下的**位置（判据用它，而不是我随手设的坐标：
	# T040 的 `resolve_safe_player_position` 可能把不安全坐标在**读档**时回退到安全点）
	var stored_pos := _stored_position()

	# 关掉旧会话，起新会话"继续游戏"
	_entry.queue_free()
	await _wait(0.3)
	_entry = await _boot(true)
	if _entry == null:
		_assert("H2_reload_boot", "新会话实例化", "null", false)
		return
	var restored: AnimalBody = _entry.get("player")
	_assert("H2_continue_alive", "继续游戏后 alive 且有玩家",
		"%s / %s" % [_state(), str(restored != null)], _state() == "alive" and restored != null)
	if restored == null:
		return
	_assert("H3_species_restored", "仍是 Mouse",
		String(restored.species_config.species_id),
		restored.species_config.species_id == MOUSE_ID)
	_assert("H4_life_id_restored", "同一 LifeId", "%s vs %s" % [String(_entry.call("current_life_id")), life_before],
		String(_entry.call("current_life_id")) == life_before)
	_assert("H5_hunger_restored", "Hunger ≈ 61", "%.2f" % restored.survival.state.hunger,
		absf(restored.survival.state.hunger - 61.0) <= 3.0)
	# 位置：本套件只断言"读回来的是**有限且在场地内**的位置"；**精确位置对齐**由 T037（往返）与
	# T040（读档/重生位置安全与回退）负责，这里不重复造第二套判据。
	# 位置：本套件只断言"读回来的是**有限且在场地内**的位置"；**精确位置对齐**由 T037（往返）与
	# T040（读档/重生位置安全与回退）负责。这里同时打印 T040 的解析原因——若存档点被判不安全，
	# 读回会被回退到安全位置，那是**设计行为**，不是缺陷（但必须在证据里写明）。
	var resolution: Dictionary = _entry.get("last_position_resolution")
	_assert("H6_position_in_bounds", "有限且在 80×80 场地内",
		"读回(%.2f, %.2f) / 文件原点(%.2f, %.2f) / reason=%s" % [
			restored.global_position.x, restored.global_position.z,
			stored_pos.x, stored_pos.z, String(resolution.get("reason", ""))],
		is_finite(restored.global_position.x) and is_finite(restored.global_position.z)
		and absf(restored.global_position.x) <= 40.0 and absf(restored.global_position.z) <= 40.0)

	_assert("H7_world_time_continues", "世界时间不倒退", "%.2f ≥ %.2f" % [_world_time(), t_before],
		_world_time() >= t_before - 1.0)


# ---------------------------------------------------------------------------
# I：鼠休息
# ---------------------------------------------------------------------------

func _stage_i_mouse_rest() -> void:
	var player: AnimalBody = _entry.get("player")
	var point := _rest_point()
	if player == null or point == null:
		_assert("I1_rest_preconditions", "玩家与休息点都在", "null", false)
		return
	point.global_position = player.global_position
	player.survival.state.health = 50.0
	player.survival.set("last_world_time", _world_time())
	await _wait(0.15)
	var t_before := _world_time()
	var res: Dictionary = point.call("commit_interaction", player, "t061_rest_mouse")
	_assert("I1_rest_ok", "鼠也能休息", str(res.get("success")), bool(res.get("success", false)))
	_assert("I2_rest_time", "+60 s", "%.3f → %.3f" % [t_before, _world_time()],
		absf(_world_time() - t_before - 60.0) <= 0.5)
	_assert("I3_rest_health", "生命 50 → 60", "%.2f" % player.survival.state.health,
		absf(player.survival.state.health - 60.0) <= 1.0)


# ---------------------------------------------------------------------------
# J：鼠死亡 → 结算 → 收尾（无阻断）
# ---------------------------------------------------------------------------

func _stage_j_mouse_death() -> void:
	_kill_player()
	var settled := await _wait_until(3.0, func() -> bool:
		return _state() != "alive")
	_assert("J1_mouse_death", "离开 alive（等了 %.2f s）" % settled, _state(), _state() != "alive")
	_entry.call("dismiss_settle")
	await _wait(0.3)
	var gs := root.get_node_or_null("/root/GameState")
	_assert("J2_back_to_selecting", "回菜单", _state(), _state() == "selecting")
	_assert("J3_two_lives_archived", "档案 2 条", "%d" % int(gs.call("archive_count")),
		int(gs.call("archive_count")) == 2)
	# 收尾：没有任何"卡住"的迹象
	_assert("J4_not_paused", "树未暂停", str(paused), not paused)
	_assert("J5_can_still_select", "仍可选物种（没卡在结算）",
		str(_entry.call("selectable_slots")), not (_entry.call("selectable_slots") as Array).is_empty())
	_assert("J6_hud_text_present", "HUD 仍有文字", _hud_text().substr(0, 16),
		not _hud_text().is_empty())
	# 再选一次猫：证明循环能继续（不卡死在死亡态）
	var ok: bool = bool(_entry.call("select_species", CAT_ID))
	await _wait(0.3)
	_assert("J7_loop_continues", "第三世可出生（alive）", "%s / %s" % [str(ok), _state()],
		ok and _state() == "alive")


# ---------------------------------------------------------------------------
# 夹具 / 工具
# ---------------------------------------------------------------------------

func _boot(continue_saved: bool) -> Node:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		return null
	var entry := packed.instantiate()
	entry.set("settings_path", SETTINGS_PATH)
	entry.set("test_mode", false)          # 正式模式：靠"发现鼠洞"真解锁
	# `--script` 运行时引擎不会设 `current_scene`，而 `MainEntry._ready` 的**读档门**要求
	# "本节点就是当前场景"（T037 D9 的正式运行判定）。这里显式指一下，等价于真实启动。
	current_scene = entry        # 本脚本就是 SceneTree：直接设 `current_scene`
	root.add_child(entry)
	await _wait(0.4)
	entry.call("set_persistence_enabled", true)
	if continue_saved:
		# `--script` 里引擎不设 `current_scene`，`_ready` 的读档门（`current_scene == self`）因此跳过读档。
		# 这里按 `_ready` 的**同一顺序**补跑一次：读档 → apply_saved_snapshot(世界时间/资源/长期层/当前生命)，
		# 再走**玩家侧入口** `continue_game()`（T041 的菜单门），断言的是生产代码路径而不是夹具自造状态。
		entry.call("_load_saved_game")
		var snap: Dictionary = entry.get("_loaded_snapshot")
		if not snap.is_empty():
			entry.call("apply_saved_snapshot", snap, false)
		var ok: bool = bool(entry.call("continue_game"))
		print("T061|continue_game=%s|state=%s|can=%s|save=%s" % [
			str(ok), String(entry.call("lifecycle_state_name")),
			str(entry.call("can_continue_game")), str(FileAccess.file_exists(SAVE_PATH))])
	await _wait(0.3)
	return entry

func _spawn_prey(player: AnimalBody) -> AnimalBody:
	var packed := load(BODY_SCENE) as PackedScene
	var prey := packed.instantiate() as AnimalBody
	prey.name = "T061Prey"
	prey.species_config = _mouse_cfg
	prey.player_controlled = false
	prey.make_camera_current = false
	prey.ai_enabled = false               # 不让它自己跑掉：本段只验证"扑击→捕获"
	var level: Node3D = _entry.get("level")
	if level == null:
		return null
	level.add_child(prey)
	prey.global_position = player.global_position + Vector3(0.0, 0.0, -1.0)
	return prey


func _capture_food() -> Node:
	for node in get_nodes_in_group(&"resource_points"):
		if not is_instance_valid(node):
			continue
		if StringName(node.get("kind")) == &"food" and int(node.get("food_type")) == SpeciesConfig.FoodType.MEAT:
			return node
	return null


func _rest_point() -> Node:
	var level: Node3D = _entry.get("level") if _entry != null else null
	return level.get_node_or_null("RestPoint") if level != null else null


func _kill_player() -> void:
	var player: AnimalBody = _entry.get("player")
	if player != null and player.survival != null:
		player.survival.apply_damage(9999.0, &"t061_death")


func _write_fresh_settings() -> void:
	GameSettings.save_to({
		GameSettings.KEY_SENSITIVITY: 1.0,
		GameSettings.KEY_FOV: 0.0,
		GameSettings.KEY_VOLUME: 1.0,
		GameSettings.KEY_CAMERA_SHAKE: 1.0,
		GameSettings.KEY_SUBTITLES: 1.0,
		GameSettings.KEY_HINTS_SEEN: 1.0,   # 流程回归不要被首次提示干扰
	}, SETTINGS_PATH)


func _clean_dir() -> void:
	var path := ProjectSettings.globalize_path(TEST_DIR)
	if DirAccess.dir_exists_absolute(path):
		var dir := DirAccess.open(path)
		if dir != null:
			for f in dir.get_files():
				dir.remove(f)
	else:
		DirAccess.make_dir_recursive_absolute(path)


func _state() -> String:
	return String(_entry.call("lifecycle_state_name")) if _entry != null else "<no entry>"


func _hud_text() -> String:
	var hud: Node = _entry.get("hud") if _entry != null else null
	if hud == null:
		return ""
	return String(hud.call("hud_text"))


func _world_time() -> float:
	var wd := root.get_node_or_null("/root/WorldDirector")
	return float(wd.get("world_time")) if wd != null else -1.0


func _wd_revision() -> int:
	var sm := root.get_node_or_null("/root/SaveManager")
	return int(sm.get("revision")) if sm != null else -1


## 等 `seconds` 真实秒（世界时间按真实时钟推进，所以"等到某状态"必须按真实秒计）
func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


## 轮询直到条件成立，返回实际等待秒数（超时返回 seconds）
func _wait_until(seconds: float, predicate: Callable) -> float:
	var start := Time.get_ticks_msec()
	var until := start + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if predicate.call():
			return float(Time.get_ticks_msec() - start) / 1000.0
		await process_frame
	return seconds

## 从存档文件里读 `current_life.transform` 的**原点**（Godot JSON 把 Transform3D 写成 `{"$t":[12 个浮点]}`）。
## 读不到返回 `Vector3(INF,...)`——**不要**在这里硬猜位置契约。
func _stored_position() -> Vector3:
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var cur: Dictionary = (parsed as Dictionary).get("current_life", {})
		var tr: Variant = cur.get("transform", null)
		if tr is Dictionary and (tr as Dictionary).has("$t"):
			var flat: Array = (tr as Dictionary)["$t"]
			if flat.size() >= 12:
				return Vector3(float(flat[9]), float(flat[10]), float(flat[11]))
	return Vector3(INF, INF, INF)


func _assert(tag: String, expected: String, actual: String, ok: bool) -> bool:
	if ok:
		_pass += 1
		print("ASSERT|%s|%s|%s|PASS" % [tag, expected, actual])
	else:
		_fail += 1
		_failed.append(tag)
		print("ASSERT|%s|%s|%s|FAIL" % [tag, expected, actual])
	return ok


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_pass + _fail, _fail])
	if _fail == 0:
		print("RESULT|pass=%d|fail=0|failed=" % _pass)
		quit(0)
	else:
		print("RESULT|pass=%d|fail=%d|failed=%s" % [_pass, _fail, "|".join(_failed)])
		quit(1)
