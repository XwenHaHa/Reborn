extends SceneTree
## T022 猫循环回归与打包 断言
##
## 覆盖（`Docs/Tasks/T022.md` §4/§5；数值只读 `Docs/Parameters.md` 第 61/62/63/64/67/71/73/75/77 行）：
##   A 循环主干（真实 `l_courtyard.tscn`）：探索 → 发现 → 扑击捕获 → 进食 → 饮水 → 再次探索
##   B 连按与重复请求（扑击 / 跳跃 / 交互 / 重复上报同一猎物）
##   C 体力耗尽（拒绝扑击 / 不位移 / 不进恢复 / 不计次 / 冲刺降级 / 恢复后可再扑）
##   D 寻路失败回退（1 s 内回退 / 最多重选 3 次 / 进入 WAIT / 不永久阻塞 / 恢复可达）
##   E 死亡与临时重开（`died` 只发一次 → 死后全禁 → `DebugEntry.restart_round()` → 新一局完整循环）
##   F 入口与打包契约（`debug_restart` = F6 = 4194337 / HUD 死亡提示 / 无调试节点 / 重置幂等 / 打包可复验）
##
## 本任务**不引入任何新数值**：断言里的常量全部对应 `Docs/Parameters.md` 既有行。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t022_loop.gd' --quit-after 300000
## 包内复验（只能用编辑器二进制 + `--main-pack`）：
##   & '<godot_console.exe>' --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
##       --script 'res://tests/run_t022_loop.gd' --quit-after 300000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const RP := "res://scenes/world/resource_point.tscn"
const ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"

const EPS := 1e-4
const ARENA := 20.0
## 猫站立时胶囊中心高度（半高 0.24 + 1 cm，与 T021 夹具同口径）
const CAT_Y := 0.25
## 鼠站立时胶囊中心高度（半高 0.09 + 1 cm）
const MOUSE_Y := 0.10
## 猫/鼠胶囊中心高差（摆夹具时用来把鼠放到与猫同一块地面）
const CAPSULE_Y_GAP := CAT_Y - MOUSE_Y
## `Parameters.md` 第 67 行：最大水平距离 140 cm / 持续 0.25 s / 体力 25 / 恢复 0.6 s
const POUNCE_DIST := 1.40
const POUNCE_TIME := 0.25
const POUNCE_COST := 25.0
const POUNCE_RECOVERY := 0.6
## `Parameters.md` 第 77 行：捕获食物未进食 300 s 失效
const FOOD_EXPIRE := 300.0
## F6 = 4194337（`project.godot` 的 `debug_restart`）
const F6_KEYCODE := 4194337
## 寻路失败的 1 s 回退窗与最多 3 次重选（`Parameters.md` 第 71 行）
const RETRY_WINDOW := 1.0
const MAX_REPLANS := 3

var _checks := 0
var _fails := 0
var _cat_cfg: SpeciesConfig = null
var _mouse_cfg: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null
var _region: NavigationRegion3D = null
var _cat: AnimalBody = null
var _prey: AnimalBody = null
var _npc: AnimalBody = null
var _ai: MouseAI = null
var _entry: Node = null
var _capture_events := 0
var _food_events := 0
var _food_time := -1.0
var _died_count := 0
var _times: Array[float] = []


func _initialize() -> void:
	print("TEST|run_t022_loop|engine=%s" % Engine.get_version_info().string)
	_cat_cfg = load(CAT) as SpeciesConfig
	_mouse_cfg = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")
	if _wd != null and _wd.has_signal("capture_reported") \
			and not _wd.is_connected("capture_reported", _on_capture_reported):
		_wd.connect("capture_reported", _on_capture_reported)

	_assert("A0_world_director", "非 null", str(_wd != null), _wd != null)
	_assert("A0_cat_config", "SpeciesConfig", str(_cat_cfg != null), _cat_cfg != null)
	_assert("A0_mouse_config", "SpeciesConfig", str(_mouse_cfg != null), _mouse_cfg != null)
	if _wd == null or _cat_cfg == null or _mouse_cfg == null:
		_finish()
		return

	await _section_a_loop()
	await _section_b_repeat()
	await _section_c_stamina()
	await _section_d_nav_fallback()
	await _section_e_death_restart()
	await _section_f_entry_contract()

	_finish()


# ---------------------------------------------------------------------------
# A 循环主干（真实关卡）
# ---------------------------------------------------------------------------

func _section_a_loop() -> void:
	print("---- A 循环主干（真实 l_courtyard）----")
	_free_world()
	await _advance_frames(2)
	var level := (load(LEVEL) as PackedScene).instantiate()
	_assert("A1_level_loads", "Node3D", "Node3D" if level is Node3D else str(level), level is Node3D)
	if not (level is Node3D):
		return
	_world = level as Node3D
	root.add_child(_world)
	await _advance_frames(10)
	_sample_time()
	var t_a_start := _time_now()

	var spawns := _spawn_points(_world)
	_assert("A2_spawn_has_cat", "含 Cat", str(spawns.keys()), spawns.has("Cat"))
	_assert("A2_spawn_has_mouse", "含 Mouse", str(spawns.keys()), spawns.has("Mouse"))
	var in_level := _markers_in(_world, "spawn_points")
	_assert("A2_spawn_markers_in_level", "2", str(in_level), in_level == 2)

	_cat = await _spawn_body(_cat_cfg, spawns.get("Cat", Vector3(-4.0, CAT_Y, 24.0)))
	_prey = await _spawn_body(_mouse_cfg, spawns.get("Mouse", Vector3(7.0, MOUSE_Y, 26.0)))
	_assert("A3_cat_on_floor", "true", str(_cat.is_on_floor()), _cat.is_on_floor())
	_assert("A3_mouse_on_floor", "true", str(_prey.is_on_floor()), _prey.is_on_floor())

	# A4 补给标记：猫食物 / 鼠食物 / 水源；按标记实例化资源点
	var supplies := _supply_points(_world)
	_assert("A4_cat_food_marker", "存在", str(supplies.has("food_Cat")), supplies.has("food_Cat"))
	_assert("A4_mouse_food_marker", "存在", str(supplies.has("food_Mouse")), supplies.has("food_Mouse"))
	_assert("A4_water_marker", "存在", str(supplies.has("water_Both")), supplies.has("water_Both"))
	var cat_food := await _resource_at(supplies.get("food_Cat", Vector3.ZERO), "t022_food_cat", _cat_cfg, false)
	var water := await _resource_at(supplies.get("water_Both", Vector3.ZERO), "t022_water", _cat_cfg, true)
	_assert("A4_water_infinite", "true", str(water.infinite), water.infinite)
	_assert("A5_food_in_level_group", "true（在关卡子树内且进 resource_points 组）",
		"in_group=%s" % str(_resource_in_world("t022_food_cat")), _resource_in_world("t022_food_cat"))
	_assert("A5_food_units_available", "> 0", str(cat_food.units), cat_food.units > 0)

	# A6 探索：朝鼠的出生点方向移动（位移只由物理推进），再把鼠摆到猫正前方验证"发现"
	var pos_before := _cat.global_position
	await _walk_towards(_cat, _prey.global_position, 0.5)
	var moved := _flat_distance(_cat.global_position, pos_before)
	_assert("A6_cat_moved", "> 0.05 m", "%.3f m" % moved, moved > 0.05)
	_prey.global_position = _front_of(_cat, 3.0, _cat.global_position.y - CAPSULE_Y_GAP)
	_prey.velocity = Vector3.ZERO
	await _advance_frames(6)
	_assert("A6_perception_present", "非 null", str(_cat.perception != null), _cat.perception != null)
	var seen := _cat.perception != null and _cat.perception.is_threat_visible()
	_assert("A6_prey_seen_at_3m", "true（9 m 视觉 / 3 m 且正前方）", str(seen), seen)
	_sample_time()

	# A7 扑击：鼠摆到 0.90 m 正前方（在 1.40 m 预算内）
	_prey.global_position = _front_of(_cat, 0.90, _cat.global_position.y - CAPSULE_Y_GAP)
	await _advance_frames(4)
	var cap0 := _capture_count()
	var food0 := _capture_food_count()
	var events0 := _capture_events
	if _cat.capture != null and not _cat.capture.food_spawned.is_connected(_on_food_spawned):
		_cat.capture.food_spawned.connect(_on_food_spawned)
	# 扑击前置（不引入新数值）：贴地 + 体力置为已知值 —— 差值断言只看"扣了一次 25"
	await _settle_on_floor(_cat)
	_cat.want_sprint = false
	_cat.survival.state.stamina = POUNCE_COST * 4.0
	var stamina_before := _cat.survival.state.stamina
	var started := _cat.request_pounce()
	_assert("A7_pounce_started", "true", str(started), started)
	_assert_near("A7_stamina_cost_25", stamina_before - POUNCE_COST, _cat.survival.state.stamina, 1e-3)
	await _run_out_pounce(_cat)
	_assert("A8_pounce_not_recovering_forever", "true", "state=%s" % _cat.action_state_name(),
		_cat.action_state_name() == "recovering" or _cat.action_state_name() == "idle")

	# A8 捕获结算
	_assert("A8_cat_captures_1", "1", str(_cat.captures), _cat.captures == 1)
	_assert("A8_prey_captured", "true", str(_prey.captured), _prey.captured)
	_assert("A8_prey_captured_by_cat", _cat.source_id(), _prey.captured_by, _prey.captured_by == _cat.source_id())
	_assert("A8_ledger_capture_plus_1", str(cap0 + 1), str(_capture_count()), _capture_count() == cap0 + 1)
	_assert("A8_ledger_food_plus_1", str(food0 + 1), str(_capture_food_count()), _capture_food_count() == food0 + 1)
	_assert("A8_capture_event_plus_1", str(events0 + 1), str(_capture_events), _capture_events == events0 + 1)

	# A9 捕获食物：生成在命中点、容量 1、300 s 失效
	var food: ResourcePoint = _cat.capture.last_spawned if _cat.capture != null else null
	_assert("A9_food_spawned", "非 null", str(food != null), food != null)
	if food == null:
		return
	_assert("A9_food_near_prey", "≤ 0.60 m", "%.3f m" % food.global_position.distance_to(_prey.global_position),
		food.global_position.distance_to(_prey.global_position) <= 0.60)
	_assert("A9_food_units_1", "1", str(food.units), food.units == 1)
	_assert_near("A9_food_expire_300", _food_time + FOOD_EXPIRE, food.expire_at, 1e-3)
	_assert("A9_food_in_group", "true", str(_resource_in_world(food.interaction_id)), _resource_in_world(food.interaction_id))

	# A10 进食捕获食物：Hunger 上升（差值）且 Unit 1 → 0
	# 先把 Hunger 压到中段：初始满值时 `restore_hunger()` 会被夹紧 → 差值看不见（T017 同口径）
	_set_hunger(_cat, 45.0)
	var hunger0 := _cat.survival.state.hunger
	var pressed := _cat.interaction.press_interact()
	_assert("A10_interact_started", "true",
		"pressed=%s target=%s" % [str(pressed), _cat.interaction.current_target_id()], pressed)
	var waited := await _run_seconds(2.5, func() -> bool: return _cat.survival.state.hunger > hunger0 + 0.5)
	_assert("A10_hunger_up", "> 0",
		"Δ=%.2f (%.2f s) deny=%s units=%d" % [_cat.survival.state.hunger - hunger0, waited,
			String(_cat.interaction.last_deny_reason()), food.units],
		_cat.survival.state.hunger > hunger0)
	_assert("A10_food_units_0", "0", str(food.units), food.units == 0)
	_sample_time()

	# A11 饮水：按标记实例化的无限水点（走去溪边；数值与身份都来自 WaterPoint_Creek 标记）
	var reached := await _walk_until(_cat, water.global_position, 16.0, 0.5)
	_assert("A11_reached_water", "≤ 0.5 m", "%.3f m" % _flat_distance(_cat.global_position, water.global_position), reached)
	# 诊断（一次性打印，写进 Evidence）：确认眼→交互点视线已无遮挡
	var eye := _cat.eye_position()
	var pt := water.interaction_point()
	var probe := PhysicsRayQueryParameters3D.create(eye, pt)
	probe.collision_mask = 1
	probe.collide_with_areas = false
	probe.exclude = [_cat.get_rid()]
	var blk := _cat.get_world_3d().direct_space_state.intersect_ray(probe)
	var blk_name := "<none>"
	if not blk.is_empty():
		var collider: Variant = blk.get("collider")
		blk_name = "%s@%s" % [collider.name, str(blk.get("position"))]
	print("DIAG|A11|free=%s|eye=%s|point=%s|blocker=%s|cat=%s|flat=%.3f" % [
		str(blk.is_empty()), str(eye), str(pt), blk_name, str(_cat.global_position),
		_flat_distance(_cat.global_position, water.global_position)])
	# 先把 Thirst 压到中段（同上：满值时 `restore_thirst()` 会被夹紧）
	_set_thirst(_cat, 45.0)
	var thirst0 := _cat.survival.state.thirst
	var drank_pressed := _cat.interaction.press_interact()
	_assert("A11_drink_started", "true",
		"pressed=%s deny=%s target=%s dist=%.2f" % [str(drank_pressed),
			String(_cat.interaction.last_deny_reason()), _cat.interaction.current_target_id(),
			_cat.eye_position().distance_to(water.interaction_point())],
		drank_pressed)
	var drank_wait := await _run_seconds(3.0, func() -> bool: return _cat.survival.state.thirst > thirst0 + 0.5)
	_assert("A11_thirst_up", "> 0",
		"Δ=%.2f (%.2f s) units=%d" % [_cat.survival.state.thirst - thirst0, drank_wait, water.units],
		_cat.survival.state.thirst > thirst0)
	_assert("A11_water_units_unchanged", "0（无限水不扣 Unit）", str(water.units), water.units == 0)

	# A12 再次探索：还能移动，还能扑击（循环闭合）
	var pos_again := _cat.global_position
	await _walk_towards(_cat, _front_of(_cat, 5.0, _cat.global_position.y), 0.4)
	var moved_again := _flat_distance(_cat.global_position, pos_again)
	_assert("A12_can_move_again", "> 0.05 m", "%.3f m" % moved_again, moved_again > 0.05)
	var prey2 := await _spawn_body(_mouse_cfg, _front_of(_cat, 0.90, _cat.global_position.y - CAPSULE_Y_GAP))
	await _advance_frames(4)
	_assert("A12_second_prey_on_floor", "true", str(prey2.is_on_floor()), prey2.is_on_floor())
	# 循环闭合的前置（不引入新数值）：贴地 + 体力 ≥ 代价。体力门本身已在 C 段断言
	await _settle_on_floor(_cat)
	_cat.want_sprint = false
	_cat.survival.state.stamina = maxf(_cat.survival.state.stamina, POUNCE_COST + 5.0)
	var started2 := _cat.request_pounce()
	_assert("A12_second_pounce_started", "true",
		"started=%s reason=%s stamina=%.1f on_floor=%s" % [str(started2), String(_cat.last_pounce_blocked_reason),
			_cat.survival.state.stamina, str(_cat.is_on_floor())], started2)
	await _run_out_pounce(_cat)

	# A13 世界时间单调不减且终点 > 起点
	_sample_time()
	_assert("A13_time_advances", "终点 > 起点", "%.2f → %.2f" % [t_a_start, _time_now()], _time_now() > t_a_start)
	var mono := true
	for i in range(1, _times.size()):
		if _times[i] < _times[i - 1] - 1e-6:
			mono = false
	_assert("A13_time_monotonic", "true", str(_times), mono)

	# A14 全程无脚本错误：按 T022 §5 的口径，由**断言汇总 + 退出码**判定
	_assert("A14_no_failed_assertion_so_far", "0", str(_fails), _fails == 0)
	print("NOTE|A14|'无脚本错误'分两段核对：套件内看 SUMMARY/RESULT + 退出码（本行报告此刻失败数=%d）；进程日志里的报错行由 Evidence 记录的 Select-String 扫描核对（套件读不到自身 stderr）" % _fails)


# ---------------------------------------------------------------------------
# B 连按与重复请求
# ---------------------------------------------------------------------------

func _section_b_repeat() -> void:
	print("---- B 连按与重复请求 ----")
	await _fresh_arena_for_combat()
	_cat = await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0))
	_prey = await _spawn_body(_mouse_cfg, Vector3(0.0, MOUSE_Y, -0.90))

	# B1 连续 10 帧请求扑击：只启动一次
	var n0 := _cat.pounce_count
	var starts := 0
	for _i in 10:
		if _cat.request_pounce():
			starts += 1
	_assert("B1_single_start_in_10_frames", "1", str(starts), starts == 1)
	_assert("B1_pounce_count_plus_1", str(n0 + 1), str(_cat.pounce_count), _cat.pounce_count == n0 + 1)

	# B2 扑击中继续连按：被拒、不重复扣体力
	var immediate := _cat.request_pounce()
	_assert("B2_immediate_reject", "false", str(immediate), not immediate)
	_assert("B2_immediate_reason_busy", "busy", String(_cat.last_pounce_blocked_reason),
		_cat.last_pounce_blocked_reason == &"busy")
	var stamina_after_start := _cat.survival.state.stamina
	var reasons: Array[String] = []
	var frames := 0
	while _cat.is_pouncing() and frames < 120:
		if not _cat.request_pounce():
			reasons.append(String(_cat.last_pounce_blocked_reason))
		await physics_frame
		frames += 1
	_assert("B2_rejected_while_pouncing", "> 0", str(reasons.size()), reasons.size() > 0)
	_assert("B2_no_silent_pass", "无空原因（没有静默放行）", str(reasons), not reasons.has(""))
	_assert("B2_reason_set_busy_or_airborne", "全部 ∈ {busy, airborne}", str(_unique_strings(reasons)),
		reasons.all(func(r: String) -> bool: return r == "busy" or r == "airborne"))
	_assert_near("B2_no_extra_stamina_cost", stamina_after_start, _cat.survival.state.stamina, 1e-3)

	# B3 恢复期内连按：被拒 recovering，不再扣体力
	_assert("B3_in_recovery", "true", "state=%s" % _cat.action_state_name(), _cat.is_recovering())
	var s1 := _cat.survival.state.stamina
	var again := _cat.request_pounce()
	_assert("B3_rejected", "false", str(again), not again)
	_assert("B3_reason_recovering", "recovering", String(_cat.last_pounce_blocked_reason),
		_cat.last_pounce_blocked_reason == &"recovering")
	_assert_near("B3_no_extra_stamina_cost", s1, _cat.survival.state.stamina, 1e-3)

	# B4 连按跳跃：扑击期间禁跳（不产生额外纵向位移）
	await _fresh_arena_for_combat()
	_cat = await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0))
	_prey = await _spawn_body(_mouse_cfg, Vector3(0.0, MOUSE_Y, -0.90))
	_assert("B4_pounce_started", "true", str(_cat.request_pounce()), _cat.is_pouncing())
	var y0 := _cat.global_position.y
	var max_dy := 0.0
	frames = 0
	while _cat.is_pouncing() and frames < 120:
		_cat.want_jump = true
		await physics_frame
		max_dy = maxf(max_dy, absf(_cat.global_position.y - y0))
		frames += 1
	# 扑击结束后进入恢复期：这一段 `want_jump` 必须被吞掉（T021 D8：恢复期禁跳）
	for _i in 3:
		await physics_frame
		max_dy = maxf(max_dy, absf(_cat.global_position.y - y0))
	_assert("B4_jump_swallowed", "false", str(_cat.want_jump), not _cat.want_jump)
	_assert("B4_no_extra_vertical_motion", "≤ 0.02 m", "%.4f m" % max_dy, max_dy <= 0.02)
	await _run_out_pounce(_cat)

	# B5 交互连按：只结算一次
	await _fresh_arena_for_combat()
	_cat = await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0))
	var bite := _add_food_point("t022_bite", Vector3(0.0, 0.05, -0.50), _cat_cfg, 1, 0.0)
	_cat.interaction.detect()
	var first: Dictionary = _cat.interaction.try_interact()
	_assert("B5_first_commit", "true", str(first.get("success", null)), bool(first.get("success", false)))
	_assert("B5_units_1_to_0", "0", str(bite.units), bite.units == 0)
	_assert("B5_consumed_once", "1", str(bite.consumed_count), bite.consumed_count == 1)
	var repeats := 0
	for _i in 10:
		var r: Dictionary = _cat.interaction.try_interact()
		if not bool(r.get("success", false)):
			repeats += 1
	_assert("B5_repeat_rejected", "10", str(repeats), repeats == 10)
	_assert("B5_consumed_still_once", "1", str(bite.consumed_count), bite.consumed_count == 1)
	_assert("B5_repeat_reason_empty", "empty（没 Unit 了）", String(_cat.interaction.last_deny_reason()),
		_cat.interaction.last_deny_reason() == &"empty")

	# B6 重复上报同一猎物：第二次 false，账本不再增长
	await _fresh_arena_for_combat()
	_cat = await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0))
	_prey = await _spawn_body(_mouse_cfg, Vector3(0.0, MOUSE_Y, -0.50))
	var led0 := _capture_count()
	var fd0 := _capture_food_count()
	var ok1 := _cat.capture.try_capture(_prey, _prey.global_position)
	_assert("B6_first_report_true", "true", str(ok1), ok1)
	var ok2 := _cat.capture.try_capture(_prey, _prey.global_position)
	_assert("B6_second_report_false", "false", str(ok2), not ok2)
	_assert("B6_second_blocked_invalid", "invalid（猎物已标记捕获）", _cat.capture.blocked_by,
		_cat.capture.blocked_by == "invalid")
	_assert("B6_ledger_delta_1", str(led0 + 1), str(_capture_count()), _capture_count() == led0 + 1)
	_assert("B6_food_delta_1", str(fd0 + 1), str(_capture_food_count()), _capture_food_count() == fd0 + 1)
	_assert("B6_component_spawn_count_1", "1", str(_cat.capture.spawn_count), _cat.capture.spawn_count == 1)


# ---------------------------------------------------------------------------
# C 体力耗尽
# ---------------------------------------------------------------------------

func _section_c_stamina() -> void:
	print("---- C 体力耗尽 ----")
	await _fresh_arena_for_combat()
	_cat = await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0))

	_cat.survival.state.stamina = 0.0
	var pos0 := _cat.global_position
	var count0 := _cat.pounce_count
	var tried := _cat.request_pounce()
	_assert("C1_rejected", "false", str(tried), not tried)
	_assert("C1_reason_stamina", "stamina", String(_cat.last_pounce_blocked_reason),
		_cat.last_pounce_blocked_reason == &"stamina")
	await _advance_frames(2)
	_assert("C2_no_horizontal_motion", "< 0.001 m", "%.5f m" % _flat_distance(_cat.global_position, pos0),
		_flat_distance(_cat.global_position, pos0) < 0.001)
	_assert("C3_not_recovering", "false", str(_cat.is_recovering()), not _cat.is_recovering())
	_assert("C3_not_pouncing", "false", str(_cat.is_pouncing()), not _cat.is_pouncing())
	_assert("C4_pounce_count_unchanged", str(count0), str(_cat.pounce_count), _cat.pounce_count == count0)

	# C5 体力归零后冲刺不加速（≤ 步行上限）
	_cat.survival.state.stamina = 0.0
	_cat.want_sprint = true
	await _advance_frames(3)
	_assert("C5_sprint_denied", "false", str(_cat.is_sprinting()), not _cat.is_sprinting())
	_assert("C5_speed_at_walk", "≤ walk_speed=%.2f" % _cat_cfg.walk_speed,
		"%.3f m/s" % _cat.current_speed(), _cat.current_speed() <= _cat_cfg.walk_speed + EPS)
	_cat.want_sprint = false

	# C6 体力恢复到 ≥ 代价后可再次扑击
	_cat.survival.state.stamina = POUNCE_COST + 5.0
	var again := _cat.request_pounce()
	_assert("C6_allowed_after_regen", "true", str(again), again)
	_assert_near("C6_cost_applied", 5.0, _cat.survival.state.stamina, 1e-3)
	_assert("C6_count_plus_1", str(count0 + 1), str(_cat.pounce_count), _cat.pounce_count == count0 + 1)
	await _run_out_pounce(_cat)


# ---------------------------------------------------------------------------
# D 寻路失败回退（T019 口径：鼠层可达、猫层无交集 → 路径为空）
# ---------------------------------------------------------------------------

func _section_d_nav_fallback() -> void:
	print("---- D 寻路失败回退 ----")
	await _fresh_arena_for_combat()
	var food := _add_food_point("t022_nav_food", Vector3(-3.0, 0.05, 0.0), _mouse_cfg, 3)
	await _advance_frames(3)
	_npc = await _spawn_npc(_mouse_cfg, Vector3(0.0, MOUSE_Y, 0.0))
	_ai = _npc.ai as MouseAI
	_assert("D0_ai_built", "MouseAI", str(_ai != null), _ai != null)
	if _ai == null:
		return
	_assert("D0_has_food_target", "t022_nav_food", str(_ai.target_id()), _ai.target_id() == "t022_nav_food")
	var ledger0 := _capture_count()

	# 换到**与鼠层（位 1）没有交集**的层：路径为空 → 无法推进
	# 注意：`navigation_layers` 是**位掩码**，用 99 会包含位 1 反而仍可达（T019 实测踩过）
	_ai.nav_layer_override = 2
	_ai.force_replan()
	await _advance_frames(5)
	var failures_at_1s := 0
	var waited := await _run_seconds(RETRY_WINDOW + 0.2, func() -> bool: return false)
	failures_at_1s = int(_ai.ai_report().get("path_failures", 0))
	_assert("D2_failure_recorded_within_1s", "≥ 1", "%d（%.2f s）" % [failures_at_1s, waited], failures_at_1s >= 1)

	var to_wait := await _run_seconds(8.0, func() -> bool: return _ai.state_id() == &"wait")
	_assert("D1_not_stuck_in_planning", "wait", "%s（%.2f s）" % [_ai.state_id(), to_wait], _ai.state_id() == &"wait")
	_assert("D1_wait_reason", "path_failed", String(_ai.state_reason()), _ai.state_reason() == &"path_failed")
	var replans := int(_ai.ai_report().get("replans", 0))
	_assert("D3_replans_capped_max_3", "≤ %d" % MAX_REPLANS, str(replans), replans <= MAX_REPLANS)
	_assert("D3_replans_used", "≥ 1", str(replans), replans >= 1)
	_assert("D3_last_path_status_readable", "非空", String(_ai.ai_report().get("last_path_status", "")),
		String(_ai.ai_report().get("last_path_status", "")) != "")
	var sets_at_wait := int(_ai.ai_report().get("destination_sets", 0))
	await _run_seconds(0.7)
	_assert("D3_no_new_queries_after_giving_up", str(sets_at_wait), str(int(_ai.ai_report().get("destination_sets", 0))),
		int(_ai.ai_report().get("destination_sets", 0)) == sets_at_wait)
	_assert("D4_frames_advanced", "> 0 s", "%.2f s" % to_wait, to_wait > 0.0)
	_assert("D4_world_time_advancing", "true", str(_time_now() > 0.0), _time_now() > 0.0)

	# D5 恢复可达：回到鼠层 + 强制重规划 → 重新有路径
	_ai.nav_layer_override = 0
	_ai.force_replan()
	var path_ok := func() -> bool: return int(_ai.ai_report().get("path_points", 0)) > 0
	var got_path := await _run_seconds(3.0, path_ok)
	var pts := int(_ai.ai_report().get("path_points", 0))
	_assert("D5_path_points_after_restore", "> 0", "%d（%.2f s）" % [pts, got_path], pts > 0)
	_assert("D5_state_recovered", "explore/forage", str(_ai.state_id()),
		_ai.state_id() == &"explore" or _ai.state_id() == &"forage")
	_assert("D6_ledger_unchanged", str(ledger0), str(_capture_count()), _capture_count() == ledger0)
	_assert("D6_food_units_unchanged", "3", str(food.units), food.units == 3)

# ---------------------------------------------------------------------------
# E 死亡与临时重开（DebugEntry = 开发/验证入口，不是正式轮回）
# ---------------------------------------------------------------------------

func _section_e_death_restart() -> void:
	print("---- E 死亡与临时重开（DebugEntry / F6 入口）----")
	_free_world()
	await _advance_frames(2)
	_assert("E1_entry_scene_exists", "true", str(ResourceLoader.exists(ENTRY)), ResourceLoader.exists(ENTRY))
	if not ResourceLoader.exists(ENTRY):
		return
	var entry: Node = (load(ENTRY) as PackedScene).instantiate()
	root.add_child(entry)
	_entry = entry
	await _advance_frames(12)

	var p: AnimalBody = entry.get("player") as AnimalBody
	_assert("E1_player_built", "AnimalBody", str(p), p != null)
	if p == null:
		return
	var old_species := String(p.species_config.species_id)
	_assert("E1_player_species_is_cat_pool_first", _cat_cfg.species_id, old_species,
		old_species == String(_cat_cfg.species_id))
	_assert("E1_player_on_floor", "true", str(p.is_on_floor()), p.is_on_floor())

	# E1 致死后 died 只发一次
	_died_count = 0
	if not p.survival.died.is_connected(_on_died):
		p.survival.died.connect(_on_died)
	p.survival.apply_damage(9999.0, &"test")
	await _advance_frames(4)
	_assert("E1_died_once", "1", str(_died_count), _died_count == 1)
	p.survival.apply_damage(9999.0, &"test")
	await _advance_frames(3)
	_assert("E1_died_still_once", "1", str(_died_count), _died_count == 1)

	# E2 死亡态
	_assert("E2_is_dead", "true", str(p.survival.is_dead()), p.survival.is_dead())
	_assert("E2_action_state_dead", "dead", p.action_state_name(), p.action_state_name() == "dead")

	# E3 死后禁扑击
	var blocked := p.request_pounce()
	_assert("E3_pounce_rejected", "false", str(blocked), not blocked)
	_assert("E3_reason_dead", "dead", String(p.last_pounce_blocked_reason), p.last_pounce_blocked_reason == &"dead")
	_assert("E3_pounce_count_untouched", "0", str(p.pounce_count), p.pounce_count == 0)

	# E4 死后交互被拒（拒绝原因 dead），动作态仍是 dead
	var lvl := entry.get("level") as Node3D
	var dead_food := (load(RP) as PackedScene).instantiate() as ResourcePoint
	dead_food.kind = ResourcePoint.KIND_FOOD
	dead_food.food_type = SpeciesConfig.FoodType.MEAT
	dead_food.interaction_id = "t022_dead_food"
	dead_food.units = 1
	dead_food.capacity = 1
	dead_food.auto_advance = false
	dead_food.position = p.global_position
	lvl.add_child(dead_food)
	await _advance_frames(4)
	var res: Dictionary = p.interaction.try_interact()
	_assert("E4_interact_rejected", "false", str(res.get("success", null)), not bool(res.get("success", true)))
	_assert("E4_reason_dead", "dead", String(res.get("reason", "")),
		StringName(res.get("reason", &"")) == &"dead")
	_assert("E4_action_state_dead", "dead", p.action_state_name(), p.action_state_name() == "dead")

	# E5 restart_round() 返回递增计数
	var old_player := p
	var old_level: Node = lvl
	var count0 := int(entry.get("restart_count"))
	var rc := int(entry.call("restart_round", &"test"))
	_assert("E5_restart_count_plus_1", str(count0 + 1), str(rc), rc == count0 + 1)
	_assert("E5_restart_count_field_matches", str(rc), str(int(entry.get("restart_count"))),
		int(entry.get("restart_count")) == rc)
	await _advance_frames(5)

	# E6 / E7 世界时间与捕获账本归零
	_assert("E6_world_time_zeroed", "≤ 0.5", "%.3f" % _time_now(), _time_now() <= 0.5)
	_assert("E7_capture_count_0", "0", str(_capture_count()), _capture_count() == 0)
	_assert("E7_capture_food_count_0", "0", str(_capture_food_count()), _capture_food_count() == 0)
	_assert("E7_captured_ids_empty", "true", str((_wd.get("captured_target_ids") as Dictionary).is_empty()),
		(_wd.get("captured_target_ids") as Dictionary).is_empty())

	# E8 旧玩家 / 旧关卡实例已释放
	_assert("E8_old_player_freed", "false", "is_instance_valid=%s" % str(is_instance_valid(old_player)),
		not is_instance_valid(old_player))
	_assert("E8_old_level_freed", "false", "is_instance_valid=%s" % str(is_instance_valid(old_level)),
		not is_instance_valid(old_level))

	# E9 新一局玩家：存在、非死亡、落地、物种不变
	var p2: AnimalBody = entry.get("player") as AnimalBody
	_assert("E9_new_player_exists", "AnimalBody", str(p2), p2 != null)
	if p2 == null:
		return
	_assert("E9_new_player_alive", "false", str(p2.survival.is_dead()), not p2.survival.is_dead())
	_assert("E9_new_player_on_floor", "true", str(p2.is_on_floor()), p2.is_on_floor())
	_assert("E9_species_unchanged", old_species, String(p2.species_config.species_id),
		String(p2.species_config.species_id) == old_species)

	# E10 新一局可再次完整循环（再次捕猎成功）
	_world = entry.get("level") as Node3D
	var prey := await _spawn_body(_mouse_cfg, _front_of(p2, 0.90, p2.global_position.y - CAPSULE_Y_GAP))
	_assert("E10_new_prey_on_floor", "true", str(prey.is_on_floor()), prey.is_on_floor())
	var started := p2.request_pounce()
	_assert("E10_pounce_started", "true", str(started), started)
	await _run_out_pounce(p2)
	_assert("E10_captures_1", "1", str(p2.captures), p2.captures == 1)
	_assert("E10_prey_captured", "true", str(prey.captured), prey.captured)

	# E11 无残留：出生点不翻倍 / 只有一个 Player / 没有退场节点留在树上
	var lvl2 := entry.get("level") as Node
	_assert("E11_spawn_points_not_doubled", "2", str(_markers_in(lvl2, "spawn_points")),
		_markers_in(lvl2, "spawn_points") == 2)
	_assert("E11_single_player_node", "1", str(_count_named(lvl2, "Player")), _count_named(lvl2, "Player") == 1)
	_assert("E11_no_retired_level", "0", str(_count_named(root, "Level_retired")),
		_count_named(root, "Level_retired") == 0)
	_assert("E11_no_stale_animal_bodies", "1（只有当前玩家）", str(_animal_body_count()),
		_animal_body_count() == 1)

	# E12 重开可重复执行 ≥ 2 次且结果一致
	var c1 := int(entry.call("restart_round", &"repeat1"))
	await _advance_frames(5)
	_assert("E12_second_restart_count", str(rc + 1), str(c1), c1 == rc + 1)
	_assert("E12_second_time_zeroed", "≤ 0.5", "%.3f" % _time_now(), _time_now() <= 0.5)
	var c2 := int(entry.call("restart_round", &"repeat2"))
	await _advance_frames(5)
	_assert("E12_third_restart_count", str(c1 + 1), str(c2), c2 == c1 + 1)
	_assert("E12_third_time_zeroed", "≤ 0.5", "%.3f" % _time_now(), _time_now() <= 0.5)
	var p3: AnimalBody = entry.get("player") as AnimalBody
	_assert("E12_player_alive_after_repeats", "true",
		"player=%s dead=%s" % [str(p3 != null), str(p3.survival.is_dead()) if p3 != null else "<null>"],
		p3 != null and not p3.survival.is_dead())
	_assert("E12_consistent_species", old_species,
		String(p3.species_config.species_id) if p3 != null else "<null>",
		p3 != null and String(p3.species_config.species_id) == old_species)
	# E13 已释放目标不得泄漏到界面（重开后曾出现：HUD 读已释放资源点导致脚本报错）
	var t_after: Variant = p3.interaction.current_target() if p3 != null else null
	_assert("E13_target_not_freed_instance", "null 或有效实例",
		"null" if t_after == null else ("valid" if is_instance_valid(t_after) else "FREED"),
		t_after == null or is_instance_valid(t_after))
	var rline := String(entry.call("resource_line"))
	_assert("E13_resource_line_no_stale", "resource: <none>", rline, rline == "resource: <none>")
	var hud_res := String(entry.call("hud_text"))
	_assert("E13_hud_text_resource_none", "含 resource: <none>", str(hud_res.contains("resource: <none>")),
		hud_res.contains("resource: <none>"))
	_world = null


# ---------------------------------------------------------------------------
# F 入口与打包契约
# ---------------------------------------------------------------------------

func _section_f_entry_contract() -> void:
	print("---- F 入口与打包契约 ----")
	var entry := _entry
	_assert("F1_entry_present", "非 null", str(entry != null), entry != null)
	if entry == null:
		return
	var gs := entry.get_script() as GDScript
	var consts: Dictionary = gs.get_script_constant_map() if gs != null else {}
	_assert("F1_has_restart_round", "有 restart_round()", str(entry.has_method("restart_round")),
		entry.has_method("restart_round"))
	_assert("F1_action_restart_name", "debug_restart", str(consts.get("ACTION_RESTART", "<无>")),
		String(consts.get("ACTION_RESTART", "")) == "debug_restart")
	_assert("F1_has_round_restarted_signal", "true", str(entry.has_signal("round_restarted")),
		entry.has_signal("round_restarted"))
	_assert("F1_restart_count_field", "≥ 3（E 段已重开 3 次）", str(entry.get("restart_count")),
		int(entry.get("restart_count")) >= 3)

	# F2 project.godot 的 debug_restart：存在且键码 = F6 = 4194337
	_assert("F2_action_registered", "true", str(InputMap.has_action("debug_restart")),
		InputMap.has_action("debug_restart"))
	var keycodes: Array[int] = []
	if InputMap.has_action("debug_restart"):
		for ev in InputMap.action_get_events("debug_restart"):
			if ev is InputEventKey:
				keycodes.append(int((ev as InputEventKey).physical_keycode))
	_assert("F2_keycode_f6", str(F6_KEYCODE), str(keycodes), keycodes.has(F6_KEYCODE))

	# F3 不与既有调试动作重名
	var actions: Array = consts.get("DEBUG_ACTIONS", [])
	_assert("F3_debug_actions_unique", "无重复（共 %d）" % actions.size(),
		"%d 唯一 / %d 总数" % [_unique_count(actions), actions.size()],
		_unique_count(actions) == actions.size())
	_assert("F3_restart_in_debug_actions", "true", str(actions),
		actions.has(&"debug_restart") or actions.has("debug_restart"))
	var existing := ["debug_switch_cat", "debug_switch_mouse", "debug_toggle_collision",
		"debug_toggle_path", "debug_toggle_hud"]
	var restart_name := String(consts.get("ACTION_RESTART", ""))
	_assert("F3_not_shadowing_existing", "不在既有 5 键中", restart_name, not existing.has(restart_name))

	# F4 非死亡态也能调用 restart_round()，且不破坏状态（调试工具语义）
	var pa: AnimalBody = entry.get("player") as AnimalBody
	var alive_before := pa != null and not pa.survival.is_dead()
	_assert("F4_alive_before_restart", "true", str(alive_before), alive_before)
	var c0 := int(entry.get("restart_count"))
	var rc := int(entry.call("restart_round", &"alive"))
	await _advance_frames(6)
	var pb: AnimalBody = entry.get("player") as AnimalBody
	_assert("F4_count_incremented", str(c0 + 1), str(rc), rc == c0 + 1)
	_assert("F4_player_valid_after", "AnimalBody", str(pb), pb != null)
	_assert("F4_player_not_dead", "false", str(pb.survival.is_dead()) if pb != null else "<null>",
		pb != null and not pb.survival.is_dead())
	_assert("F4_player_on_floor", "true", str(pb.is_on_floor()) if pb != null else "<null>",
		pb != null and pb.is_on_floor())

	# F5 正式场景内无 /debug/ 脚本节点（T013 口径）
	for scene_path in [MAIN, LEVEL]:
		var sc := (load(scene_path) as PackedScene).instantiate()
		root.add_child(sc)
		await _advance_frames(4)
		var dbg := _debug_nodes(sc)
		_assert("F5_no_debug_node_in_%s" % String(scene_path).get_file().get_basename(), "0", str(dbg), dbg == 0)
		sc.queue_free()
		await _advance_frames(2)

	# F6 reset_for_new_game() 幂等（连续两次无副作用）
	_wd.call("reset_for_new_game")
	_wd.call("reset_for_new_game")
	_assert("F6_idempotent_time", "≤ 0.5", "%.3f" % _time_now(), _time_now() <= 0.5)
	_assert("F6_idempotent_counts", "0/0", "%d/%d" % [_capture_count(), _capture_food_count()],
		_capture_count() == 0 and _capture_food_count() == 0)
	_assert("F6_idempotent_board", "true", str((_wd.get("captured_target_ids") as Dictionary).is_empty()),
		(_wd.get("captured_target_ids") as Dictionary).is_empty())
	_assert("F6_time_advancing_restored", "true", str(bool(_wd.get("time_advancing"))),
		bool(_wd.get("time_advancing")))

	# F7 HUD：死亡态含重开提示；非死亡态不含
	var hud_alive := String(entry.call("hud_text"))
	_assert("F7_hud_alive_no_restart_hint", "不含 重开", _clip(hud_alive), not hud_alive.contains("重开"))
	var pl: AnimalBody = entry.get("player") as AnimalBody
	if pl != null:
		pl.survival.apply_damage(9999.0, &"test")
	await _advance_frames(3)
	var hud_dead := String(entry.call("hud_text"))
	_assert("F7_hud_dead_has_restart_hint", "含 重开", _clip(hud_dead), hud_dead.contains("重开"))
	_assert("F7_hud_dead_has_death_line", "含 death:", _clip(hud_dead), hud_dead.contains("death:"))
	entry.call("restart_round", &"cleanup")
	await _advance_frames(4)

	# F8 打包契约：可复验资源在编辑器与 SelfTest 包里都能解析
	_assert("F8_entry_scene_loadable", "true", str(ResourceLoader.exists(ENTRY)), ResourceLoader.exists(ENTRY))
	_assert("F8_level_scene_loadable", "true", str(ResourceLoader.exists(LEVEL)), ResourceLoader.exists(LEVEL))
	var self_script := load("res://tests/run_t022_loop.gd")
	_assert("F8_self_script_loadable", "true", str(self_script != null), self_script != null)
	# 打包契约（Evidence 读这行区分"编辑器 / 包内"）：`export_presets.cfg` 不是资源、不入包，
	# 所以编辑器里 `presets_file=true`、`--main-pack` 运行里 `false`；`main_pack_arg` 因引擎吞掉自身参数
	# 在包内也可能是 false，仅作参考。
	print("PACK|editor=%s|template=%s|presets_file=%s|main_pack_arg=%s|engine=%s" % [
		str(OS.has_feature("editor")),
		str(OS.has_feature("template")),
		str(FileAccess.file_exists("res://export_presets.cfg")),
		str("--main-pack" in OS.get_cmdline_args()),
		Engine.get_version_info().string
	])
	entry.queue_free()
	await _advance_frames(2)
	_entry = null


# ---------------------------------------------------------------------------
# 夹具
# ---------------------------------------------------------------------------

## 平地 + 已烘焙的鼠层导航（T019 口径）+ 只有地板、可随时生成身体。
## 说明（T012 实测坑）：**烘焙几何源只认区域子节点**，地面必须挂在 `NavigationRegion3D` 下。
func _fresh_arena_for_combat() -> void:
	_free_world()
	await _advance_frames(2)
	_world = Node3D.new()
	_world.name = "T022World"
	root.add_child(_world)
	await _advance_frames(2)

	_region = NavigationRegion3D.new()
	_region.name = "MouseRegion"
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.07
	nm.agent_height = 0.09
	nm.cell_size = 0.03
	nm.cell_height = 0.03
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	_region.navigation_mesh = nm
	_region.navigation_layers = 1
	_region.set_meta("species", "Mouse")
	_world.add_child(_region)
	_add_box(_region, "ArenaGround", Vector3(ARENA, 1.0, ARENA), Vector3(0.0, -0.5, 0.0))
	await _advance_frames(2)
	_region.bake_navigation_mesh(false)
	await _advance_frames(6)


func _free_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	_region = null
	_cat = null
	_prey = null
	_npc = null
	_ai = null


## 生成一只身体：`player_controlled` 默认 false（用例自己写 `move_intent` / `want_*`），
## `ai_enabled` 保持默认 false —— AI 会抢 `move_intent`，夹具不能用它。
func _spawn_body(cfg: SpeciesConfig, pos: Vector3, player_controlled := false, frames := 12) -> AnimalBody:
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = player_controlled
	body.position = pos
	body.velocity = Vector3.ZERO
	_world.add_child(body)
	await _advance_frames(frames)
	return body


## 生成一只 NPC 身体（显式打开 AI；T019 起默认关闭）
func _spawn_npc(cfg: SpeciesConfig, pos: Vector3, frames := 12) -> AnimalBody:
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = false
	body.position = pos
	body.velocity = Vector3.ZERO
	_world.add_child(body)
	body.ai_enabled = true
	await _advance_frames(frames)
	return body


func _add_box(parent: Node, id: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = id
	sb.collision_layer = AnimalBody.LAYER_WORLD_STATIC
	sb.collision_mask = 0
	sb.position = pos
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


## 按标记实例化一个补给点（食物 / 水）。**先设位置再入树**（T016 实测坑：
## 入树后再设 `global_position` 会让物理体在原点存在一帧）。
func _resource_at(pos: Vector3, id: String, cfg: SpeciesConfig, water: bool) -> ResourcePoint:
	var rp := (load(RP) as PackedScene).instantiate() as ResourcePoint
	rp.kind = ResourcePoint.KIND_WATER if water else ResourcePoint.KIND_FOOD
	rp.interaction_id = id
	if not water:
		rp.food_type = cfg.allowed_food_types[0] if not cfg.allowed_food_types.is_empty() else 0
	# 交互点抬离地面：`supply_points` 标记贴在关卡地面上（顶面 y=0.10），
	# 眼→点射线会在**端点掠射**到 Ground 被判 `occluded`（本轮实测：blocker=Ground@(-24.0,0.1,16.0)）；
	# 用 T016 既有的 `interaction_point_offset` 把交互点抬到表面之上（不改任何数值断言）。
	rp.interaction_point_offset = Vector3(0.0, 0.05, 0.0)
	rp.position = pos
	_world.add_child(rp)
	await _advance_frames(3)
	return rp


## 运行期建食物点（不走场景）：`duration == 0` = 按下即完成
func _add_food_point(id: String, pos: Vector3, eater: SpeciesConfig, units: int, duration := 1.5) -> ResourcePoint:
	var rp := (load(RP) as PackedScene).instantiate() as ResourcePoint
	rp.kind = ResourcePoint.KIND_FOOD
	rp.interaction_id = id
	rp.food_type = eater.allowed_food_types[0] if not eater.allowed_food_types.is_empty() else 0
	rp.units = units
	rp.capacity = maxi(units, 1)
	rp.interaction_duration = duration
	# 恢复排期交给测试显式控制，避免真实世界时间插进来
	rp.auto_advance = false
	rp.next_refill_at = 0.0
	rp.position = pos
	_world.add_child(rp)
	return rp


## 身体正前方 `dist` 米处的点（局地水平朝向；`y` 不给就沿用身体高度）
func _front_of(body: AnimalBody, dist: float, y: float = NAN) -> Vector3:
	var fwd := -body.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-8:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var p := body.global_position + fwd * dist
	p.y = body.global_position.y if is_nan(y) else y
	return p


# ---------------------------------------------------------------------------
# 关卡标记读取
# ---------------------------------------------------------------------------

## `spawn_points` 分组标记：`metadata/species` → 全局坐标（只收本关卡子树里的）
func _spawn_points(level: Node) -> Dictionary:
	var out := {}
	if level == null:
		return out
	for n in get_nodes_in_group("spawn_points"):
		var marker := n as Node3D
		if marker == null or not level.is_ancestor_of(marker):
			continue
		var sid := String(marker.get_meta("species", ""))
		if sid.is_empty():
			continue
		out[sid] = marker.global_position
	return out


## `supply_points` 分组标记：`<supply_type>_<species>` → 全局坐标（`Both` 视为两物种通用）
func _supply_points(level: Node) -> Dictionary:
	var out := {}
	if level == null:
		return out
	for n in get_nodes_in_group("supply_points"):
		var marker := n as Node3D
		if marker == null or not level.is_ancestor_of(marker):
			continue
		var kind := String(marker.get_meta("supply_type", ""))
		var species := String(marker.get_meta("species", "Both"))
		if kind.is_empty():
			continue
		out["%s_%s" % [kind, species]] = marker.global_position
	return out


func _markers_in(level: Node, group: StringName) -> int:
	var count := 0
	if level == null:
		return count
	for n in get_nodes_in_group(group):
		if level.is_ancestor_of(n):
			count += 1
	return count


func _resource_in_world(id: String) -> bool:
	if id.is_empty() or _world == null:
		return false
	for n in get_nodes_in_group("resource_points"):
		if n is ResourcePoint and _world.is_ancestor_of(n) and (n as ResourcePoint).interaction_id == id:
			return true
	return false


# ---------------------------------------------------------------------------
# 观察与推进
# ---------------------------------------------------------------------------

func _set_hunger(body: AnimalBody, value: float) -> void:
	# `restore_hunger()` 只加不设，所以直接改状态；**同时对齐 tick**，避免期间按时间掉值干扰断言
	body.survival.state.hunger = value
	body.survival.tick_to(body.world_time_now())


func _set_thirst(body: AnimalBody, value: float) -> void:
	body.survival.state.thirst = value
	body.survival.tick_to(body.world_time_now())


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## 定长走向目标（`look_at` 转向 + `move_intent` 前进，与 AI 的推进方式一致；不瞬移）
func _walk_towards(body: AnimalBody, target: Vector3, seconds: float) -> void:
	if body == null:
		return
	var t0 := _time_now()
	while _time_now() - t0 < seconds:
		_steer_towards(body, target)
		await physics_frame
	body.move_intent = Vector2.ZERO
	body.want_sprint = false


## 等身体落地（扑击要求贴地；最多等 `max_frames` 帧）
func _settle_on_floor(body: AnimalBody, max_frames := 60) -> void:
	if body == null:
		return
	for _i in max_frames:
		if body.is_on_floor():
			return
		await physics_frame


## 走目标，直到水平距离 ≤ `arrive_radius`（或超时）；返回是否到达
func _walk_until(body: AnimalBody, target: Vector3, max_seconds: float, arrive_radius: float) -> bool:
	if body == null:
		return false
	var t0 := _time_now()
	while _time_now() - t0 < max_seconds:
		if _flat_distance(body.global_position, target) <= arrive_radius:
			body.move_intent = Vector2.ZERO
			body.want_sprint = false
			return true
		_steer_towards(body, target)
		await physics_frame
	body.move_intent = Vector2.ZERO
	body.want_sprint = false
	return false


func _steer_towards(body: AnimalBody, target: Vector3) -> void:
	var flat := Vector3(target.x - body.global_position.x, 0.0, target.z - body.global_position.z)
	if flat.length() > 0.01:
		body.look_at(body.global_position + flat.normalized(), Vector3.UP)
	body.want_sprint = true
	body.move_intent = Vector2(0.0, -1.0)


## 推进物理帧直到扑击结束（或超时）；返回推进的帧数
func _run_out_pounce(body: AnimalBody) -> int:
	if body == null:
		return 0
	var frames := 0
	while body.is_pouncing() and frames < 240:
		await physics_frame
		frames += 1
	return frames


## 推进**真实世界时间**直到经过 `seconds`（或 `until()` 为真 / 超出真实时间预算）；返回实际经过秒数。
## 物理帧长度固定为 1/60 s，但世界时间来自 `WorldDirector._process()` 的**真实 delta**，
## 所以按真实时钟兜底，避免在极快的无头环境里被"帧数上限"提前掐断。
func _run_seconds(seconds: float, until := Callable()) -> float:
	if _wd == null:
		return 0.0
	var t0 := _time_now()
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0 * 3.0) + 2000
	while _time_now() - t0 < seconds and Time.get_ticks_msec() < deadline:
		if until.is_valid() and bool(until.call()):
			break
		await physics_frame
	return _time_now() - t0


func _advance_frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _time_now() -> float:
	return float(_wd.get("world_time")) if _wd != null else 0.0


func _sample_time() -> void:
	_times.append(_time_now())


func _capture_count() -> int:
	return int(_wd.get("capture_count")) if _wd != null else -1


func _capture_food_count() -> int:
	return int(_wd.get("capture_food_count")) if _wd != null else -1


func _animal_body_count() -> int:
	return get_nodes_in_group(&"animal_bodies").size()


func _count_named(tree: Node, name: String) -> int:
	var count := 0
	if tree == null:
		return count
	for n in _all_nodes(tree):
		if String(n.name) == name:
			count += 1
	return count


func _debug_nodes(tree: Node) -> int:
	var count := 0
	if tree == null:
		return count
	for n in _all_nodes(tree):
		var sc: Variant = n.get_script()
		if sc is Script and String((sc as Script).resource_path).contains("/debug/"):
			count += 1
	return count


func _all_nodes(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all_nodes(c))
	return out


func _unique_strings(arr: Array) -> Array[String]:
	var seen := {}
	var out: Array[String] = []
	for v in arr:
		var s := String(v)
		if seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	return out


func _unique_count(arr: Array) -> int:
	return _unique_strings(arr).size()


func _clip(s: String) -> String:
	return s.replace("\n", " | ").substr(0, 90)


# ---------------------------------------------------------------------------
# 信号回调（账本与捕获食物的观测口）
# ---------------------------------------------------------------------------

func _on_capture_reported(captor_id: String, target_id: String, position: Vector3, world_time: float) -> void:
	_capture_events += 1


func _on_food_spawned(point: ResourcePoint, world_time: float) -> void:
	_food_events += 1
	_food_time = world_time


func _on_died(_reason: StringName) -> void:
	_died_count += 1


# ---------------------------------------------------------------------------
# 断言
# ---------------------------------------------------------------------------

func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	var a := float(actual)
	_assert(id, "%.4f ±%.4f" % [expected, eps], "%.4f" % a, absf(a - expected) <= eps)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
