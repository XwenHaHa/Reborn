extends SceneTree
## T021 猫扑击与捕获结算 断言
##
## 覆盖（`Docs/Tasks/T021.md` §2/§3/§4；数值真源 `Docs/Parameters.md` 第 67 / 77 行）：
##   A 数值契约与接口（配置五值 / `ACT` 枚举 / 组件方法 / 诊断字段 D10）
##   B 启动门与体力代价（species / dead / airborne / busy / recovering / stamina + 成功立即扣 25）
##   C 扫掠与预算（逐帧 `move_and_collide`、位移 ≤ 1.40 m、时长 0.25 s、不传送）
##   D 障碍优先（撞墙停在墙前；**墙后的猎物不被结算** —— TechnicalDesign §4）
##   E 命中捕获与幂等（记账一次、猎物标记、活体表现移除、重复上报不再结算）
##   F 捕获食物（容量 1 / 不恢复 / 300 s 失效 / 字段与位置）
##   G 恢复期与再生（0.6 s 站位固定、禁扑禁跳、到点解除、可再次扑击）
##   H 集成（AI 目标、双捕食者不重复结算、`reset_for_new_game()`、`MOV|` 字段、真实场景加载）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t021_capture.gd' --quit-after 180000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"

const EPS := 1e-4
const ARENA := 40.0
const CAT_Y := 0.25          # 猫站立时胶囊中心高度（半高 0.24 + 1 cm）
const MOUSE_Y := 0.10        # 鼠站立时胶囊中心高度（半高 0.09 + 1 cm）
const POUNCE_DIST := 1.40    # Parameters.md 第 67 行：最大水平距离 140 cm
const POUNCE_TIME := 0.25    # 同上：持续 0.25 s
const POUNCE_COST := 25.0    # 同上：体力 25
const POUNCE_RECOVERY := 0.6 # 同上：恢复 0.6 s
const FOOD_EXPIRE := 300.0   # Parameters.md 第 77 行：未进食 300 s 失效
const CAT_SPEED := 5.6       # = 1.40 / 0.25（派生量）
const MAX_STEP := CAT_SPEED / 60.0 + 1e-3

var _checks := 0
var _fails := 0
var _cat_cfg: SpeciesConfig = null
var _mouse_cfg: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null
var _region: NavigationRegion3D = null
var _cat: AnimalBody = null
var _mouse: AnimalBody = null
var _capture_events := 0
var _capture_payload := {}
var _food_events := 0
var _food: ResourcePoint = null
var _food_time := -1.0


func _initialize() -> void:
	print("TEST|run_t021_capture|engine=%s" % Engine.get_version_info().string)
	_cat_cfg = load(CAT) as SpeciesConfig
	_mouse_cfg = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")
	if _wd != null and _wd.has_signal("capture_reported") \
			and not _wd.is_connected("capture_reported", _on_capture_reported):
		_wd.connect("capture_reported", _on_capture_reported)

	await _section_a_contract()
	await _section_b_gates()
	await _section_c_sweep()
	await _section_d_obstacle()
	await _section_efg_capture()
	await _section_h_integration()

	_finish()


# ---------------------------------------------------------------------------
# A 数值契约与接口
# ---------------------------------------------------------------------------

func _section_a_contract() -> void:
	print("---- A 数值契约与接口 ----")
	_assert("A_world_director_present", "非 null", str(_wd != null), _wd != null)
	_assert("A_cat_config_loaded", "SpeciesConfig", str(_cat_cfg != null), _cat_cfg != null)
	_assert("A_mouse_config_loaded", "SpeciesConfig", str(_mouse_cfg != null), _mouse_cfg != null)
	if _cat_cfg == null or _mouse_cfg == null:
		return

	# Parameters.md 第 67 行
	_assert_near("A_pounce_max_distance_1.40", POUNCE_DIST, _cat_cfg.pounce_max_distance, EPS)
	_assert_near("A_pounce_duration_0.25", POUNCE_TIME, _cat_cfg.pounce_duration, EPS)
	_assert_near("A_pounce_stamina_cost_25", POUNCE_COST, _cat_cfg.pounce_stamina_cost, EPS)
	_assert_near("A_pounce_recovery_0.6", POUNCE_RECOVERY, _cat_cfg.pounce_recovery, EPS)
	# Parameters.md 第 77 行
	_assert_near("A_capture_food_expire_300", FOOD_EXPIRE, _cat_cfg.capture_food_expire, EPS)
	_assert_near("A_pounce_speed_derived_5.6", CAT_SPEED, _cat_cfg.pounce_speed(), 1e-3)
	_assert("A_cat_can_pounce", "true", str(_cat_cfg.can_pounce), _cat_cfg.can_pounce)
	_assert("A_mouse_cannot_pounce", "false", str(_mouse_cfg.can_pounce), not _mouse_cfg.can_pounce)
	_assert("A_cat_config_valid", "无问题", str(_cat_cfg.validate_config().size()), _cat_cfg.validate_config().is_empty())
	_assert("A_mouse_config_valid", "无问题", str(_mouse_cfg.validate_config().size()), _mouse_cfg.validate_config().is_empty())

	# 动作状态枚举顺序（TechnicalDesign §1）
	_assert("A_act_idle_0", "0", str(int(AnimalBody.ACT.IDLE)), int(AnimalBody.ACT.IDLE) == 0)
	_assert("A_act_interacting_1", "1", str(int(AnimalBody.ACT.INTERACTING)), int(AnimalBody.ACT.INTERACTING) == 1)
	_assert("A_act_pouncing_2", "2", str(int(AnimalBody.ACT.POUNCING)), int(AnimalBody.ACT.POUNCING) == 2)
	_assert("A_act_recovering_3", "3", str(int(AnimalBody.ACT.RECOVERING)), int(AnimalBody.ACT.RECOVERING) == 3)
	_assert("A_act_dead_4", "4", str(int(AnimalBody.ACT.DEAD)), int(AnimalBody.ACT.DEAD) == 4)

	var comp := CaptureSettlement.new()
	_assert("A_capture_is_node3d", "Node3D", str(comp is Node3D), comp is Node3D)
	_assert("A_capture_has_setup", "有 setup()", str(comp.has_method("setup")), comp.has_method("setup"))
	_assert("A_capture_has_is_valid_prey", "有 is_valid_prey()", str(comp.has_method("is_valid_prey")), comp.has_method("is_valid_prey"))
	_assert("A_capture_has_try_capture", "有 try_capture()", str(comp.has_method("try_capture")), comp.has_method("try_capture"))
	_assert("A_capture_has_spawn_food", "有 spawn_captured_food()", str(comp.has_method("spawn_captured_food")), comp.has_method("spawn_captured_food"))
	_assert("A_capture_has_report", "有 report()", str(comp.has_method("report")), comp.has_method("report"))
	_assert("A_capture_has_world_time_now", "有 world_time_now()", str(comp.has_method("world_time_now")), comp.has_method("world_time_now"))
	comp.free()

	await _fresh_arena()
	_cat = await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0))
	_mouse = await _spawn_body(_mouse_cfg, Vector3(0.0, MOUSE_Y, -3.0))

	_assert("A_cat_has_capture_component", "非 null", str(_cat.capture != null), _cat.capture != null)
	_assert("A_mouse_has_no_capture_component", "null（鼠 can_pounce=false → 不建捕获组件）", str(_mouse.capture == null), _mouse.capture == null)
	_assert("A_body_has_start_pounce", "有 start_pounce()", str(_cat.has_method("start_pounce")), _cat.has_method("start_pounce"))
	_assert("A_body_has_request_pounce", "有 request_pounce()", str(_cat.has_method("request_pounce")), _cat.has_method("request_pounce"))
	_assert("A_body_has_is_pouncing", "有 is_pouncing()", str(_cat.has_method("is_pouncing")), _cat.has_method("is_pouncing"))
	_assert("A_body_has_is_recovering", "有 is_recovering()", str(_cat.has_method("is_recovering")), _cat.has_method("is_recovering"))
	_assert("A_body_has_action_state_name", "有 action_state_name()", str(_cat.has_method("action_state_name")), _cat.has_method("action_state_name"))
	_assert("A_body_has_mark_captured", "有 mark_captured()", str(_cat.has_method("mark_captured")), _cat.has_method("mark_captured"))
	_assert("A_body_has_can_pounce", "有 can_pounce()", str(_cat.has_method("can_pounce")), _cat.has_method("can_pounce"))

	# 诊断字段（T021 D10）：`MOV|` / 调试入口要能读到动作与捕获状态
	var st := _cat.debug_state()
	for key in ["action_state", "action_state_id", "pouncing", "recovering", "pounce_count",
			"pounce_travel", "pounce_blocked", "pounce_can", "captures", "captured",
			"captured_by", "interaction_blocked", "interaction_blocked_reason", "capture"]:
		_assert("A_debug_state_has_%s" % key, "存在", str(st.has(key)), st.has(key))
	_assert("A_debug_pounce_can_true", "true", str(st.get("pounce_can", null)), bool(st.get("pounce_can", false)))
	_assert("A_debug_action_state_idle", "idle", str(st.get("action_state", "")), String(st.get("action_state", "")) == "idle")
	_assert("A_debug_capture_report_dict", "Dictionary", str(st.get("capture", null) is Dictionary), st.get("capture", null) is Dictionary)


# ---------------------------------------------------------------------------
# B 启动门与体力代价
# ---------------------------------------------------------------------------

func _section_b_gates() -> void:
	print("---- B 启动门与体力代价（D2 / D8）----")
	await _fresh_arena()
	_cat = await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0))

	_assert("B_cat_on_floor", "true", str(_cat.is_on_floor()), _cat.is_on_floor())
	_assert("B_idle_before", "idle", _cat.action_state_name(), _cat.action_state_name() == "idle")
	_assert("B_not_pouncing_before", "false", str(_cat.is_pouncing()), not _cat.is_pouncing())
	_assert("B_not_recovering_before", "false", str(_cat.is_recovering()), not _cat.is_recovering())
	_assert("B_can_pounce", "true", str(_cat.can_pounce()), _cat.can_pounce())
	_assert("B_mask_idle_world_only", "1", str(_cat.collision_mask), _cat.collision_mask == AnimalBody.LAYER_WORLD_STATIC)

	var stamina_before := _stamina(_cat)
	var started := _cat.request_pounce()
	var stamina_after := _stamina(_cat)
	_assert("B_pounce_started_ok", "true", str(started), started)
	_assert_near("B_stamina_cost_exactly_25", POUNCE_COST, stamina_before - stamina_after, 1e-3)
	_assert("B_pounce_count_1", "1", str(_cat.pounce_count), _cat.pounce_count == 1)
	_assert("B_pouncing_true", "true", str(_cat.is_pouncing()), _cat.is_pouncing())
	_assert("B_action_state_pouncing", "pouncing", _cat.action_state_name(), _cat.action_state_name() == "pouncing")
	_assert("B_action_state_id_2", "2", str(int(_cat.action_state())), int(_cat.action_state()) == 2)
	_assert("B_mask_pouncing_adds_animal", "3", str(_cat.collision_mask),
		_cat.collision_mask == (AnimalBody.LAYER_WORLD_STATIC | AnimalBody.LAYER_ANIMAL))
	_assert("B_interaction_blocked_pouncing", "pouncing", String(_cat.interaction_blocked_reason),
		_cat.interaction_blocked_reason == &"pouncing")

	# 扑击期间再按 → busy（不叠加、不重复扣体力）
	_cat.start_pounce()
	_assert("B_busy_blocked", "busy", String(_cat.last_pounce_blocked_reason), _cat.last_pounce_blocked_reason == &"busy")
	_assert("B_busy_keeps_count", "1", str(_cat.pounce_count), _cat.pounce_count == 1)
	_assert_near("B_busy_keeps_stamina", stamina_after, _stamina(_cat), 0.05)

	var frames := await _run_out_pounce()
	_assert("B_pounce_finished", "false", str(_cat.is_pouncing()), not _cat.is_pouncing())
	_assert("B_pounce_frames_in_range", "10..25", str(frames), frames >= 10 and frames <= 25)
	_assert("B_mask_restored", "1", str(_cat.collision_mask), _cat.collision_mask == AnimalBody.LAYER_WORLD_STATIC)
	_assert("B_recovering_after", "true", str(_cat.is_recovering()), _cat.is_recovering())
	_assert("B_action_state_recovering", "recovering", _cat.action_state_name(), _cat.action_state_name() == "recovering")
	_assert("B_interaction_blocked_recovering", "recovering", String(_cat.interaction_blocked_reason),
		_cat.interaction_blocked_reason == &"recovering")
	_cat.start_pounce()
	_assert("B_recovering_blocked", "recovering", String(_cat.last_pounce_blocked_reason),
		_cat.last_pounce_blocked_reason == &"recovering")

	# 腾空门：新身体（还没落地）
	await _fresh_arena()
	var air := await _spawn_body(_cat_cfg, Vector3(6.0, 3.0, 0.0), false, 3)
	_assert("B_air_body_not_on_floor", "false", str(air.is_on_floor()), not air.is_on_floor())
	air.start_pounce()
	_assert("B_airborne_blocked", "airborne", String(air.last_pounce_blocked_reason), air.last_pounce_blocked_reason == &"airborne")
	_assert("B_airborne_keeps_count", "0", str(air.pounce_count), air.pounce_count == 0)

	# 物种门：鼠不能扑击（can_pounce = false）
	_mouse = await _spawn_body(_mouse_cfg, Vector3(6.0, MOUSE_Y, -3.0))
	_assert("B_mouse_on_floor", "true", str(_mouse.is_on_floor()), _mouse.is_on_floor())
	_mouse.start_pounce()
	_assert("B_species_blocked", "species", String(_mouse.last_pounce_blocked_reason), _mouse.last_pounce_blocked_reason == &"species")

	# 死亡门：死猫不能扑击
	var dead_cat := await _spawn_body(_cat_cfg, Vector3(12.0, CAT_Y, 0.0))
	dead_cat.survival.apply_damage(9999.0, &"test")
	_assert("B_dead_cat_is_dead", "true", str(dead_cat.survival.is_dead()), dead_cat.survival.is_dead())
	_assert("B_dead_state_name", "dead", dead_cat.action_state_name(), dead_cat.action_state_name() == "dead")
	dead_cat.start_pounce()
	_assert("B_dead_blocked", "dead", String(dead_cat.last_pounce_blocked_reason), dead_cat.last_pounce_blocked_reason == &"dead")
	_assert("B_dead_keeps_count", "0", str(dead_cat.pounce_count), dead_cat.pounce_count == 0)

	# 体力门：不足时拒绝启动，**不扣不赔**
	var tired := await _spawn_body(_cat_cfg, Vector3(-12.0, CAT_Y, 0.0))
	tired.survival.state.stamina = 10.0
	tired.start_pounce()
	_assert("B_stamina_blocked", "stamina", String(tired.last_pounce_blocked_reason), tired.last_pounce_blocked_reason == &"stamina")
	_assert_near("B_stamina_not_spent", 10.0, _stamina(tired), 1e-3)
	_assert("B_stamina_keeps_count", "0", str(tired.pounce_count), tired.pounce_count == 0)

	# 输入路径：外部写 `want_pounce`（AI / 测试）与玩家按键走**同一条**消费路径（`_physics_process()`）
	await _fresh_arena()
	_cat = await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0))
	_cat.want_pounce = true
	await _advance_frames(1)
	_assert("B_input_path_pouncing", "true", str(_cat.is_pouncing()), _cat.is_pouncing())
	_assert("B_input_path_consumed", "false", str(_cat.want_pounce), not _cat.want_pounce)
	_assert("B_input_path_count_1", "1", str(_cat.pounce_count), _cat.pounce_count == 1)
	await _run_out_pounce()

	# 玩家按键路径：`project.godot` 必须注册 `pounce` 动作（`_read_input()` 唯一的接线点）
	_assert("B_input_action_registered", "有 pounce 动作", str(InputMap.has_action("pounce")),
		InputMap.has_action("pounce"))
	await _fresh_arena()
	var keyed := await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0), true)
	var keyed_ok := false
	for _attempt in 4:
		Input.action_press("pounce")
		# `physics_frame` 在节点 `_physics_process()` **之前**发射：等**两**帧，
		# 让节点先读到 `just_pressed` 再释放；在节点处理之前释放会把 `just_pressed` 抹掉。
		await physics_frame
		await physics_frame
		Input.action_release("pounce")
		if keyed.is_pouncing():
			keyed_ok = true
			break
		await physics_frame
	Input.action_release("pounce")
	_assert("B_keyboard_path_starts_pounce", "true",
		"pouncing=%s count=%d" % [str(keyed.is_pouncing()), keyed.pounce_count], keyed_ok)
	_assert("B_keyboard_path_count_1", "1", str(keyed.pounce_count), keyed.pounce_count == 1)
	await _run_out_pounce(keyed)


# ---------------------------------------------------------------------------
# C 扫掠与位移预算（D3 / D9）
# ---------------------------------------------------------------------------

func _section_c_sweep() -> void:
	print("---- C 扫掠与位移预算（D3 / D9）----")
	await _fresh_arena()
	_cat = await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0))

	var start := _cat.global_position
	_assert("C_start_on_floor", "true", str(_cat.is_on_floor()), _cat.is_on_floor())
	_assert_near("C_start_x0", 0.0, start.x, 1e-3)
	_assert_near("C_start_z0", 0.0, start.z, 1e-3)
	# 朝向 -Z：`basis.z` 指向 +Z，所以 `-basis.z.z == -1`
	_assert_near("C_facing_minus_z", -1.0, -_cat.transform.basis.z.z, 1e-3)

	_assert("C_pounce_started", "true", str(_cat.request_pounce()), _cat.is_pouncing())

	var frames := 0
	var prev := _cat.global_position
	var max_step := 0.0
	var max_y_gap := 0.0
	while _cat.is_pouncing() and frames < 120:
		await physics_frame
		frames += 1
		var now := _cat.global_position
		max_step = maxf(max_step, Vector2(now.x - prev.x, now.z - prev.z).length())
		max_y_gap = maxf(max_y_gap, absf(now.y - start.y))
		prev = now

	_assert("C_ended", "false", str(_cat.is_pouncing()), not _cat.is_pouncing())
	_assert("C_frames_in_range", "10..25", str(frames), frames >= 10 and frames <= 25)
	_assert("C_blocked_reason_empty", "", String(_cat.last_pounce_blocked_reason),
		_cat.last_pounce_blocked_reason == &"")
	_assert_near("C_travel_full_budget", POUNCE_DIST, _cat.last_pounce_travel, 0.02)
	_assert("C_travel_not_over_budget", "<= %.3f" % POUNCE_DIST, "%.4f" % _cat.last_pounce_travel,
		_cat.last_pounce_travel <= POUNCE_DIST + 1e-3)

	var finish := _cat.global_position
	_assert_near("C_end_z_at_budget", -POUNCE_DIST, finish.z, 0.03)
	_assert_near("C_end_x_stays_0", 0.0, finish.x, 5e-3)
	_assert_near("C_horizontal_disp", POUNCE_DIST, Vector2(finish.x - start.x, finish.z - start.z).length(), 0.03)
	_assert("C_kept_height", "|Δy| <= 0.02", "%.4f" % max_y_gap, max_y_gap <= 0.02)
	# "不传送"：**每一帧**的真实位移都不超过一帧的物理预算（`speed * 1/60 + ε`）
	_assert("C_no_teleport_any_frame", "<= %.4f" % MAX_STEP, "%.4f" % max_step, max_step <= MAX_STEP)
	_assert("C_pounce_count_1", "1", str(_cat.pounce_count), _cat.pounce_count == 1)
	_assert("C_stamina_spent_once", "75.0", "%.2f" % _stamina(_cat), absf(_stamina(_cat) - 75.0) < 0.5)


# ---------------------------------------------------------------------------
# D 障碍优先（D3 / D4）：撞墙就停，墙后的猎物**不**被结算
# ---------------------------------------------------------------------------

func _section_d_obstacle() -> void:
	print("---- D 障碍优先（D3 / D4）----")
	await _fresh_arena(true)
	# 墙在 z=-0.60（厚 0.20 → 近侧墙面 z=-0.50）；鼠在墙后 z=-1.20
	_cat = await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0))
	_mouse = await _spawn_body(_mouse_cfg, Vector3(0.0, MOUSE_Y, -1.20))
	_mouse.ai_enabled = false

	var wall := _world.get_node_or_null("PounceWall") as Node3D
	_assert("D_wall_present", "非 null", str(wall != null), wall != null)
	_assert("D_prey_behind_wall", "鼠 z < -0.70", "z=%.3f" % _mouse.global_position.z,
		_mouse.global_position.z < -0.70)
	var ledger_before := _capture_count()
	var food_before := _capture_food_count()
	var events_before := _capture_events
	var stamina_before := _stamina(_cat)

	var start := _cat.global_position
	_assert("D_pounce_started", "true", str(_cat.request_pounce()), _cat.is_pouncing())
	var frames := await _run_out_pounce()
	var stop := _cat.global_position

	_assert("D_blocked_by_world", "world", String(_cat.last_pounce_blocked_reason),
		_cat.last_pounce_blocked_reason == &"world")
	_assert("D_stopped_before_wall", "z ∈ [-0.50, -0.20]", "z=%.3f" % stop.z, stop.z >= -0.50 and stop.z <= -0.20)
	_assert("D_travel_partial", "0.20 < travel < 0.70", "%.3f" % _cat.last_pounce_travel,
		_cat.last_pounce_travel > 0.20 and _cat.last_pounce_travel < 0.70)
	_assert("D_moved_less_than_budget", "travel < 1.40", "%.3f" % _cat.last_pounce_travel,
		_cat.last_pounce_travel < POUNCE_DIST)
	_assert("D_frames_few", "< 15", str(frames), frames > 0 and frames < 15)
	_assert_near("D_stamina_not_refunded", stamina_before - POUNCE_COST, _stamina(_cat), 0.05)
	_assert_near("D_x_unchanged", start.x, stop.x, 5e-3)

	# 关键断言：**墙后**的猎物一根汗毛都没动，账本没涨，也没多出食物
	_assert("D_prey_not_captured", "false", str(_mouse.captured), not _mouse.captured)
	_assert("D_prey_captured_by_empty", "", _mouse.captured_by, _mouse.captured_by.is_empty())
	_assert("D_prey_not_dead", "false", str(_mouse.survival.is_dead()), not _mouse.survival.is_dead())
	_assert("D_cat_captures_0", "0", str(_cat.captures), _cat.captures == 0)
	_assert("D_capture_component_spawn_0", "0", str(_cat.capture.spawn_count), _cat.capture.spawn_count == 0)
	_assert("D_ledger_unchanged", str(ledger_before), str(_capture_count()), _capture_count() == ledger_before)
	_assert("D_food_ledger_unchanged", str(food_before), str(_capture_food_count()),
		_capture_food_count() == food_before)
	_assert("D_no_capture_event", str(events_before), str(_capture_events), _capture_events == events_before)
	_assert("D_prey_in_group", "true", str(_mouse.is_in_group(AnimalBody.GROUP_ANIMAL_BODIES)),
		_mouse.is_in_group(AnimalBody.GROUP_ANIMAL_BODIES))
	_assert("D_prey_still_processing", "true", str(_mouse.is_physics_processing()), _mouse.is_physics_processing())
	# ART03-④：鼠换成 glb 视觉后 `body_mesh` 恒隐藏（胶囊退化为尺寸代理），
	# 所以"猎物还看得见"要改看 `visual_root`；没有 visual_root 的物种仍看 `body_mesh`。
	var prey_visual_visible: bool = (_mouse.visual_root != null and _mouse.visual_root.visible) \
		or (_mouse.body_mesh != null and _mouse.body_mesh.visible)
	_assert("D_prey_mesh_visible", "true（visual_root 或 body_mesh）", str(prey_visual_visible),
		prey_visual_visible)
	_assert("D_prey_layer_intact", "2", str(_mouse.collision_layer), _mouse.collision_layer == AnimalBody.LAYER_ANIMAL)

	# 收尾口径：掩码回到静止态；恢复期内禁扑（不复位预算、不补体力）
	_assert("D_mask_restored", "1", str(_cat.collision_mask), _cat.collision_mask == AnimalBody.LAYER_WORLD_STATIC)
	var again := _cat.request_pounce()
	_assert("D_recovering_blocks_second", "false", str(again), not again)
	_assert("D_recovering_reason", "recovering", String(_cat.last_pounce_blocked_reason),
		_cat.last_pounce_blocked_reason == &"recovering")
	_assert("D_pounce_count_1", "1", str(_cat.pounce_count), _cat.pounce_count == 1)


# ---------------------------------------------------------------------------
# E / F / G 捕获结算、捕获食物、恢复期
# ---------------------------------------------------------------------------

func _section_efg_capture() -> void:
	await _section_e_capture_hit()
	await _section_f_capture_food()
	await _section_g_recovery()


func _section_e_capture_hit() -> void:
	print("---- E 命中捕获与幂等（D4 / D5 / D6）----")
	await _fresh_arena()
	_cat = await _spawn_body(_cat_cfg, Vector3(0.0, CAT_Y, 0.0))
	_mouse = await _spawn_body(_mouse_cfg, Vector3(0.0, MOUSE_Y, -1.20))
	_mouse.ai_enabled = false
	var cap := _cat.capture
	_assert("E_capture_wired", "非 null", str(cap != null), cap != null)
	if cap == null:
		return
	if not cap.food_spawned.is_connected(_on_food_spawned):
		cap.food_spawned.connect(_on_food_spawned)

	# 猎物判据（D4）：全部来自状态/配置判定
	_assert("E_valid_prey_mouse", "true", str(cap.is_valid_prey(_mouse)), cap.is_valid_prey(_mouse))
	_assert("E_invalid_self", "false", str(cap.is_valid_prey(_cat)), not cap.is_valid_prey(_cat))
	_assert("E_invalid_null", "false", str(cap.is_valid_prey(null)), not cap.is_valid_prey(null))
	_assert("E_invalid_non_animal", "false", str(cap.is_valid_prey(_world)), not cap.is_valid_prey(_world))
	var same_species := await _spawn_body(_cat_cfg, Vector3(3.0, CAT_Y, 0.0))
	_assert("E_invalid_same_species", "false", str(cap.is_valid_prey(same_species)),
		not cap.is_valid_prey(same_species))
	var dead_prey := await _spawn_body(_mouse_cfg, Vector3(6.0, MOUSE_Y, 0.0))
	dead_prey.ai_enabled = false
	dead_prey.survival.apply_damage(9999.0, &"test")
	_assert("E_dead_prey_is_dead", "true", str(dead_prey.survival.is_dead()), dead_prey.survival.is_dead())
	_assert("E_invalid_dead_prey", "false", str(cap.is_valid_prey(dead_prey)),
		not cap.is_valid_prey(dead_prey))

	var ledger_before := _capture_count()
	var food_ledger_before := _capture_food_count()
	var events_before := _capture_events
	var prey_health_before := _mouse.survival.state.health
	var prey_hunger_before := _mouse.survival.state.hunger
	_assert("E_ledger_before_0", "0", str(ledger_before), ledger_before == 0)
	_assert("E_food_ledger_before_0", "0", str(food_ledger_before), food_ledger_before == 0)

	# 扑击命中：猫中心到鼠中心 1.20 m，两个胶囊半径和 0.16+0.06 → 行进约 0.98 m 就接触
	_assert("E_pounce_started", "true", str(_cat.request_pounce()), _cat.is_pouncing())
	_assert("E_mask_during_pounce", "3", str(_cat.collision_mask),
		_cat.collision_mask == (AnimalBody.LAYER_WORLD_STATIC | AnimalBody.LAYER_ANIMAL))
	var frames := await _run_out_pounce()
	_assert("E_pounce_ended", "false", str(_cat.is_pouncing()), not _cat.is_pouncing())
	_assert("E_frames_positive", "> 0", str(frames), frames > 0)
	_assert("E_capture_reason_empty", "", String(_cat.last_pounce_blocked_reason),
		_cat.last_pounce_blocked_reason == &"")
	_assert("E_captures_1", "1", str(_cat.captures), _cat.captures == 1)
	_assert("E_travel_reached_prey", "0.80 < travel < 1.10", "%.3f" % _cat.last_pounce_travel,
		_cat.last_pounce_travel > 0.80 and _cat.last_pounce_travel < 1.10)
	_assert("E_stopped_before_budget_end", "travel < 1.35", "%.3f" % _cat.last_pounce_travel,
		_cat.last_pounce_travel < 1.35)
	_assert("E_component_spawn_1", "1", str(cap.spawn_count), cap.spawn_count == 1)
	_assert("E_component_blocked_by_empty", "", cap.blocked_by, cap.blocked_by.is_empty())

	# 猎物侧：标记 + 账本 + 事件
	_assert("E_prey_captured", "true", str(_mouse.captured), _mouse.captured)
	_assert("E_prey_captured_by_cat", _cat.source_id(), _mouse.captured_by,
		_mouse.captured_by == _cat.source_id())
	_assert("E_ledger_is_captured", "true", str(bool(_wd.call("is_captured", _mouse.source_id()))),
		bool(_wd.call("is_captured", _mouse.source_id())))
	_assert("E_ledger_count_1", "1", str(_capture_count()), _capture_count() == 1)
	_assert("E_food_ledger_1", "1", str(_capture_food_count()), _capture_food_count() == 1)
	_assert("E_capture_events_delta_1", str(events_before + 1), str(_capture_events),
		_capture_events == events_before + 1)
	_assert("E_event_captor", _cat.source_id(), String(_capture_payload.get("captor_id", "")),
		String(_capture_payload.get("captor_id", "")) == _cat.source_id())
	_assert("E_event_target", _mouse.source_id(), String(_capture_payload.get("target_id", "")),
		String(_capture_payload.get("target_id", "")) == _mouse.source_id())
	var hit: Vector3 = _capture_payload.get("position", Vector3.ZERO)
	_assert("E_event_position_near_prey", "<= 0.50 m", "%.3f" % hit.distance_to(_mouse.global_position),
		hit.distance_to(_mouse.global_position) <= 0.50)

	# 活体表现移除（TechnicalDesign §7 第 4 步）：节点还在，但不再是"活体"
	_assert("E_prey_action_state_dead", "dead", _mouse.action_state_name(), _mouse.action_state_name() == "dead")
	_assert("E_prey_out_of_group", "false", str(_mouse.is_in_group(AnimalBody.GROUP_ANIMAL_BODIES)),
		not _mouse.is_in_group(AnimalBody.GROUP_ANIMAL_BODIES))
	_assert("E_prey_survival_processing_off", "false", str(_mouse.is_physics_processing()),
		not _mouse.is_physics_processing())
	_assert("E_prey_layer_zero", "0", str(_mouse.collision_layer), _mouse.collision_layer == 0)
	_assert("E_prey_mask_zero", "0", str(_mouse.collision_mask), _mouse.collision_mask == 0)
	_assert("E_prey_mesh_hidden", "false", str(_mouse.body_mesh.visible), not _mouse.body_mesh.visible)
	_assert("E_prey_node_kept", "true", str(is_instance_valid(_mouse)), is_instance_valid(_mouse))
	_assert("E_prey_still_in_tree", "true", str(_mouse.is_inside_tree()), _mouse.is_inside_tree())

	# 捕获**不**走伤害/死亡通道、**不**回满指标（Parameters.md 第 77 行）
	_assert("E_prey_health_not_zero", "false", str(_mouse.survival.is_dead()), not _mouse.survival.is_dead())
	_assert_near("E_prey_health_unchanged", prey_health_before, _mouse.survival.state.health, 1e-3)
	_assert("E_prey_hunger_not_restored", "<= before", "%.3f" % _mouse.survival.state.hunger,
		_mouse.survival.state.hunger <= prey_hunger_before + 1e-3)
	_assert("E_cat_stamina_only_pounce_cost", "75.0", "%.2f" % _stamina(_cat), absf(_stamina(_cat) - 75.0) < 0.05)

	# 幂等（D6）：重复上报不重复生成食物、不重复计数
	var repeat_try := cap.try_capture(_mouse, _mouse.global_position)
	_assert("E_repeat_try_false", "false", str(repeat_try), not repeat_try)
	_assert("E_repeat_blocked_by_invalid", "invalid", cap.blocked_by, cap.blocked_by == "invalid")
	var repeat_mark := _mouse.mark_captured("another_cat")
	_assert("E_repeat_mark_false", "false", str(repeat_mark), not repeat_mark)
	_assert("E_prey_captured_by_unchanged", _cat.source_id(), _mouse.captured_by,
		_mouse.captured_by == _cat.source_id())
	var repeat_report := bool(_wd.call("report_capture", "x", _mouse.source_id(), Vector3.ZERO, 0.0))
	_assert("E_repeat_report_false", "false", str(repeat_report), not repeat_report)
	_assert("E_ledger_still_1", "1", str(_capture_count()), _capture_count() == 1)
	_assert("E_food_ledger_still_1", "1", str(_capture_food_count()), _capture_food_count() == 1)
	_assert("E_component_spawn_still_1", "1", str(cap.spawn_count), cap.spawn_count == 1)


func _section_f_capture_food() -> void:
	print("---- F 捕获食物（D6；Parameters.md 第 77 行）----")
	var cap := _cat.capture
	_assert("F_food_spawned", "非 null", str(_food != null), _food != null)
	if _food == null:
		return
	_assert("F_food_events_1", "1", str(_food_events), _food_events == 1)
	_assert("F_food_time_recorded", "> 0", "%.3f" % _food_time, _food_time > 0.0)
	_assert("F_kind_food", "food", String(_food.kind), _food.kind == ResourcePoint.KIND_FOOD)
	_assert("F_food_type_meat", "0", str(_food.food_type), _food.food_type == SpeciesConfig.FoodType.MEAT)
	_assert("F_units_1", "1", str(_food.units), _food.units == 1)
	_assert("F_capacity_1", "1", str(_food.capacity), _food.capacity == 1)
	_assert("F_not_infinite", "false", str(_food.infinite), not _food.infinite)
	_assert("F_no_refill", "0.00", "%.4f" % _food.refill_interval, absf(_food.refill_interval) < 1e-6)
	_assert("F_auto_advance", "true", str(_food.auto_advance), _food.auto_advance)
	_assert("F_region_courtyard", "Courtyard", String(_food.region_id), _food.region_id == &"Courtyard")
	_assert_near("F_nutrition_35", 35.0, _food.nutrition, 1e-3)
	_assert_near("F_expire_at_hit_plus_300", _food_time + FOOD_EXPIRE, _food.expire_at, 0.05)

	# 失效窗口（300 s 未进食）
	_assert("F_not_expired_at_hit", "false", str(_food.is_expired(_food_time)), not _food.is_expired(_food_time))
	_assert("F_not_expired_299", "false", str(_food.is_expired(_food_time + 299.0)),
		not _food.is_expired(_food_time + 299.0))
	_assert("F_expired_301", "true", str(_food.is_expired(_food_time + 301.0)),
		_food.is_expired(_food_time + 301.0))

	# 交互口径：谁吃得上由**配置**决定（猫能、鼠不能），代码里没有物种名分支
	_assert("F_deny_cat_allowed", "", String(_food.deny_reason_for(_cat)), _food.deny_reason_for(_cat) == &"")
	_assert("F_deny_mouse_food_type", "food_type", String(_food.deny_reason_for(_mouse)),
		_food.deny_reason_for(_mouse) == &"food_type")

	# 位置与父节点：挂在**关卡根**，不挂在猎物（会被隐藏）或捕食者（会跟着走）身上
	var hit: Vector3 = _capture_payload.get("position", Vector3.ZERO)
	_assert("F_food_near_hit", "<= 0.50 m", "%.3f" % _food.global_position.distance_to(hit),
		_food.global_position.distance_to(hit) <= 0.50)
	_assert("F_parent_not_prey", "true", str(_food.get_parent() != _mouse), _food.get_parent() != _mouse)
	_assert("F_parent_not_predator", "true", str(_food.get_parent() != _cat), _food.get_parent() != _cat)
	_assert("F_parent_is_world", "true", str(_food.get_parent() == _world), _food.get_parent() == _world)
	_assert("F_in_tree", "true", str(_food.is_inside_tree()), _food.is_inside_tree())

	# 账本与记录形状（T031/T035 要用的存档字段）
	_assert("F_component_spawn_count_1", "1", str(cap.spawn_count), cap.spawn_count == 1)
	_assert("F_component_last_spawned", "true", str(cap.last_spawned == _food), cap.last_spawned == _food)
	var record := _food.to_record()
	for key in ["id", "region_id", "kind", "food_type", "units", "capacity", "next_refill_at",
			"refill_interval", "transform", "expire_at"]:
		_assert("F_record_has_%s" % key, "存在", str(record.has(key)), record.has(key))
	_assert("F_record_units_1", "1", str(record.get("units", -1)), int(record.get("units", -1)) == 1)


func _section_g_recovery() -> void:
	print("---- G 恢复期与再生（D7 / D8）----")
	_assert("G_recovering", "true", str(_cat.is_recovering()), _cat.is_recovering())
	_assert("G_action_state_recovering", "recovering", _cat.action_state_name(),
		_cat.action_state_name() == "recovering")
	_assert("G_interaction_blocked", "recovering", String(_cat.interaction_blocked_reason),
		_cat.interaction_blocked_reason == &"recovering")
	_assert_near("G_recover_window_0.6", POUNCE_RECOVERY, _cat._recover_until - _time_now(), 0.08)

	# 恢复期站位固定：跳被吞、扑被拒、不产生位移
	var pos_before := _cat.global_position
	_cat.want_jump = true
	await _advance_frames(10)
	_assert("G_jump_swallowed", "false", str(_cat.want_jump), not _cat.want_jump)
	_assert("G_kept_height", "|Δy| <= 0.02", "%.4f" % absf(_cat.global_position.y - pos_before.y),
		absf(_cat.global_position.y - pos_before.y) <= 0.02)
	_assert("G_still_on_floor", "true", str(_cat.is_on_floor()), _cat.is_on_floor())
	var blocked := _cat.request_pounce()
	_assert("G_blocked_during_recovery", "false", str(blocked), not blocked)
	_assert("G_blocked_reason_recovering", "recovering", String(_cat.last_pounce_blocked_reason),
		_cat.last_pounce_blocked_reason == &"recovering")
	_assert("G_pounce_count_still_1", "1", str(_cat.pounce_count), _cat.pounce_count == 1)

	# 到点解除：按**世界时间**解除，不靠帧数
	await _run_seconds(POUNCE_RECOVERY + 0.1)
	_assert("G_recovery_ended", "false", str(_cat.is_recovering()), not _cat.is_recovering())
	_assert("G_action_state_idle", "idle", _cat.action_state_name(), _cat.action_state_name() == "idle")
	_assert("G_interaction_unblocked", "", String(_cat.interaction_blocked_reason),
		_cat.interaction_blocked_reason == &"")

	# 恢复后可再扑：一次扑击**恰**扣一次代价（差值断言，规避 `regen_delay` 之后的体力再生）
	var stamina_before := _stamina(_cat)
	var second := _cat.request_pounce()
	_assert("G_second_pounce_allowed", "true", str(second), second)
	_assert("G_pounce_count_2", "2", str(_cat.pounce_count), _cat.pounce_count == 2)
	_assert_near("G_stamina_second_cost", stamina_before - POUNCE_COST, _stamina(_cat), 0.05)
	var frames := await _run_out_pounce()
	_assert("G_second_pounce_ended", "false", str(_cat.is_pouncing()), not _cat.is_pouncing())
	_assert("G_second_frames_ok", "> 0", str(frames), frames > 0)


# ---------------------------------------------------------------------------
# H 集成（真实关卡 / 双捕食者 / `MOV|` / 新游戏重置）
# ---------------------------------------------------------------------------

func _section_h_integration() -> void:
	print("---- H 集成（真实关卡 / 双捕食者 / MOV| / 重置）----")
	_free_world()
	await _advance_frames(2)
	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	_assert("H_level_loaded", "非 null", str(level != null), level != null)
	if level == null:
		return
	root.add_child(level)
	await _advance_frames(10)
	_world = level

	# H1 调试入口的 `MOV|` 新字段（act / pounce / captures / blocked）
	if ResourceLoader.exists(ENTRY):
		var entry: Node = (load(ENTRY) as PackedScene).instantiate()
		root.add_child(entry)
		await _advance_frames(6)
		if entry.has_method("switch_species"):
			entry.call("switch_species", _cat_cfg.species_id)
			await _advance_frames(6)
		var mov := String(entry.call("mov_line")) if entry.has_method("mov_line") else ""
		_assert("H_mov_has_act", "含 act=", _clip(mov), mov.contains("act="))
		_assert("H_mov_has_pounce", "含 pounce=", _clip(mov), mov.contains("pounce="))
		_assert("H_mov_has_captures", "含 captures=", _clip(mov), mov.contains("captures="))
		_assert("H_mov_has_blocked", "含 blocked=", _clip(mov), mov.contains("blocked="))
		entry.queue_free()
		await _advance_frames(2)

	# H2 真实关卡里的扑击捕获：`l_courtyard.tscn` 只提供几何 + `spawn_points`
	# （关卡自身不含 AnimalBody，身体由测试按标记生成——与 T020 的 H 段同模型）
	var spawns := _spawn_points(level)
	_assert("H_level_spawn_points", ">= 2", str(spawns.size()), spawns.size() >= 2)
	_assert("H_level_has_cat_spawn", "true", str(spawns.has("Cat")), spawns.has("Cat"))
	_assert("H_level_has_mouse_spawn", "true", str(spawns.has("Mouse")), spawns.has("Mouse"))
	if not (spawns.has("Cat") and spawns.has("Mouse")):
		level.queue_free()
		_world = null
		return
	var cat_spawn: Vector3 = spawns["Cat"]
	var mouse_spawn: Vector3 = spawns["Mouse"]
	var cat_body := await _spawn_body(_cat_cfg, cat_spawn)
	var mouse_body := await _spawn_body(_mouse_cfg, mouse_spawn)
	cat_body.ai_enabled = false
	mouse_body.ai_enabled = false
	_assert("H_level_cat_parented_to_level", "true", str(cat_body.get_parent() == level),
		cat_body.get_parent() == level)
	_assert("H_level_mouse_parented_to_level", "true", str(mouse_body.get_parent() == level),
		mouse_body.get_parent() == level)
	_assert("H_level_cat_on_floor_at_spawn", "true", str(cat_body.is_on_floor()), cat_body.is_on_floor())
	_assert("H_level_mouse_on_floor_at_spawn", "true", str(mouse_body.is_on_floor()),
		mouse_body.is_on_floor())

	# 把猎物放到猫出生点正前方 1.20 m（出生点由关卡保证是空地），猫沿 -Z 扑
	var home := cat_body.global_position
	var prey_spot := Vector3(home.x, mouse_body.global_position.y, home.z - 1.20)
	mouse_body.global_position = prey_spot
	mouse_body.velocity = Vector3.ZERO
	cat_body.velocity = Vector3.ZERO
	cat_body.move_intent = Vector2.ZERO
	cat_body.look_at(prey_spot, Vector3.UP)
	await _advance_frames(12)
	_assert("H_cat_on_floor_in_level", "true", str(cat_body.is_on_floor()), cat_body.is_on_floor())
	_assert("H_mouse_on_floor_in_level", "true", str(mouse_body.is_on_floor()), mouse_body.is_on_floor())
	_assert_near("H_prey_distance_1.20", 1.20,
		Vector2(home.x - mouse_body.global_position.x, home.z - mouse_body.global_position.z).length(), 0.05)

	var cap := cat_body.capture
	_assert("H_level_capture_wired", "非 null", str(cap != null), cap != null)
	if cap == null:
		level.queue_free()
		_world = null
		return
	if not cap.food_spawned.is_connected(_on_food_spawned):
		cap.food_spawned.connect(_on_food_spawned)
	_food = null
	_food_time = -1.0
	_food_events = 0
	var ledger_before := _capture_count()
	var food_before := _capture_food_count()
	var started := cat_body.request_pounce()
	_assert("H_pounce_started_in_level", "true", str(started), started)
	await _run_out_pounce(cat_body)
	_assert("H_level_captures_1", "1", str(cat_body.captures), cat_body.captures == 1)
	_assert("H_level_prey_captured", "true", str(mouse_body.captured), mouse_body.captured)
	_assert("H_level_reason_empty", "", String(cat_body.last_pounce_blocked_reason),
		cat_body.last_pounce_blocked_reason == &"")
	_assert("H_ledger_delta_1", str(ledger_before + 1), str(_capture_count()),
		_capture_count() == ledger_before + 1)
	_assert("H_food_ledger_delta_1", str(food_before + 1), str(_capture_food_count()),
		_capture_food_count() == food_before + 1)
	_assert("H_level_food_spawned", "非 null", str(_food != null), _food != null)
	if _food != null:
		_assert("H_level_food_parented_to_level", "true", str(_food.get_parent() == level),
			_food.get_parent() == level)
		_assert("H_level_food_near_prey", "<= 0.60 m",
			"%.3f" % _food.global_position.distance_to(mouse_body.global_position),
			_food.global_position.distance_to(mouse_body.global_position) <= 0.60)
	level.queue_free()
	await _advance_frames(2)
	_world = null

	# H3 双捕食者抢同一只猎物：**恰好一次**结算
	await _fresh_arena()
	var prey := await _spawn_body(_mouse_cfg, Vector3(0.0, MOUSE_Y, 0.0))
	var cats: Array[AnimalBody] = []
	for i in 4:
		cats.append(await _spawn_body(_cat_cfg, Vector3(1.5 + 0.5 * float(i), CAT_Y, 0.0)))
	var ledger0 := _capture_count()
	var food0 := _capture_food_count()
	var events0 := _capture_events
	var settled := 0
	var captor := -1
	for i in cats.size():
		if cats[i].capture.try_capture(prey, prey.global_position):
			settled += 1
			captor = i
	_assert("H4_single_settlement", "1", str(settled), settled == 1)
	# 直接调 `try_capture()` 走的是**组件入口**（不经过扑击），所以"谁结算了"要看组件的
	# `spawn_count` / `blocked_by`；`AnimalBody.captures` 只在扑击命中时累加（见 H2）。
	_assert("H4_captor_is_first_in_order", "0", str(captor), captor == 0)
	var captors := 0
	var spawned_total := 0
	var blocked_reasons: Array[String] = []
	for i in cats.size():
		spawned_total += cats[i].capture.spawn_count
		if cats[i].capture.spawn_count == 1:
			captors += 1
		if i != captor:
			blocked_reasons.append(cats[i].capture.blocked_by)
	_assert("H4_exactly_one_captor", "1", str(captors), captors == 1)
	_assert("H4_total_spawn_1", "1", str(spawned_total), spawned_total == 1)
	# 落败者**全部**被挡下（D5 双重去重：猎物已被 `mark_captured()` 标记，或账本已记），
	# 且没有被静默放行（`blocked_by == ""` 仍是"成功"）
	_assert("H4_losers_all_blocked", "非空原因 ×%d" % (cats.size() - 1), str(blocked_reasons),
		not blocked_reasons.has(""))
	_assert("H4_ledger_delta_1", str(ledger0 + 1), str(_capture_count()), _capture_count() == ledger0 + 1)
	_assert("H4_food_delta_1", str(food0 + 1), str(_capture_food_count()), _capture_food_count() == food0 + 1)
	_assert("H4_events_delta_1", str(events0 + 1), str(_capture_events), _capture_events == events0 + 1)
	_assert("H4_event_captor_is_first", cats[0].source_id(), String(_capture_payload.get("captor_id", "")),
		String(_capture_payload.get("captor_id", "")) == cats[0].source_id())

	# H5 新游戏重置：账本清空、时间归零（T030/T031 的入口）
	_assert("H5_board_not_empty", "true", str(not (_wd.get("captured_target_ids") as Dictionary).is_empty()),
		not (_wd.get("captured_target_ids") as Dictionary).is_empty())
	_wd.call("reset_for_new_game")
	_assert("H5_reset_count_0", "0", str(_capture_count()), _capture_count() == 0)
	_assert("H5_reset_food_0", "0", str(_capture_food_count()), _capture_food_count() == 0)
	_assert("H5_reset_board_empty", "true", str((_wd.get("captured_target_ids") as Dictionary).is_empty()),
		(_wd.get("captured_target_ids") as Dictionary).is_empty())
	_assert("H5_reset_time_zeroed", "<= 0.5", "%.3f" % _time_now(), _time_now() <= 0.5)
	_assert("H5_prey_no_longer_recorded", "false", str(bool(_wd.call("is_captured", prey.source_id()))),
		not bool(_wd.call("is_captured", prey.source_id())))


# ---------------------------------------------------------------------------
# 夹具
# ---------------------------------------------------------------------------

## 一块 40 × 40 的平地（顶面 y = 0，与 T020 夹具同口径）。
##
## `with_wall`：在 z = -0.60 放一堵 0.20 m 厚、0.60 m 高的墙（**近侧面 z = -0.50**），
## 用来验证"障碍优先于障碍后的猎物"（TechnicalDesign §4 / T021 D3）。
## 本夹具**不**烘导航：T021 的用例全部显式关掉 AI，位移只由扑击/重力产生。
func _fresh_arena(with_wall := false) -> void:
	_free_world()
	await _advance_frames(2)
	_world = Node3D.new()
	_world.name = "T021World"
	root.add_child(_world)
	await _advance_frames(2)
	_add_box(_world, "ArenaGround", Vector3(ARENA, 1.0, ARENA), Vector3(0.0, -0.5, 0.0))
	if with_wall:
		_add_box(_world, "PounceWall", Vector3(6.0, 0.60, 0.20), Vector3(0.0, 0.30, -0.60))
	await _advance_frames(2)


func _free_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	_region = null
	_cat = null
	_mouse = null
	_food = null
	_food_time = -1.0
	_food_events = 0


## 生成一只身体：`player_controlled` 默认 false（用例自己写 `want_*`），
## `ai_enabled` 保持默认 false（T019 起默认关闭）——AI 会抢 `move_intent`，夹具不能用它。
func _spawn_body(cfg: SpeciesConfig, pos: Vector3, player_controlled := false, frames := 12) -> AnimalBody:
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = player_controlled
	body.position = pos
	body.velocity = Vector3.ZERO
	_world.add_child(body)
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


## 关卡 `spawn_points` 分组的出生标记：`metadata/species` → 全局坐标（T019 的出生契约）。
## 只收本关卡子树里的标记，避免把别的场景（调试入口、测试夹具）的标记算进来。
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


# ---------------------------------------------------------------------------
# 信号回调（账本与捕获食物的**唯一**观测口）
# ---------------------------------------------------------------------------

func _on_capture_reported(captor_id: String, target_id: String, position: Vector3, world_time: float) -> void:
	_capture_events += 1
	_capture_payload = {
		"captor_id": captor_id,
		"target_id": target_id,
		"position": position,
		"world_time": world_time,
	}


func _on_food_spawned(point: ResourcePoint, world_time: float) -> void:
	_food_events += 1
	_food = point
	_food_time = world_time


# ---------------------------------------------------------------------------
# 观察与推进
# ---------------------------------------------------------------------------

## 推进物理帧直到扑击结束（或超时）；返回推进的帧数。默认看 `_cat`。
func _run_out_pounce(body: AnimalBody = null) -> int:
	var target := body if body != null else _cat
	if target == null:
		return 0
	var frames := 0
	while target.is_pouncing() and frames < 240:
		await physics_frame
		frames += 1
	return frames


func _stamina(body: AnimalBody) -> float:
	if body == null or body.survival == null:
		return -1.0
	return body.survival.state.stamina


func _capture_count() -> int:
	return int(_wd.get("capture_count")) if _wd != null else -1


func _capture_food_count() -> int:
	return int(_wd.get("capture_food_count")) if _wd != null else -1


## 世界时间（`WorldDirector.world_time`；暂停时不前进）
func _time_now() -> float:
	return float(_wd.get("world_time")) if _wd != null else 0.0


## 推进**真实世界时间**直到经过 `seconds`（或超出真实时间预算）；返回实际经过秒数。
##
## 物理帧长度固定为 1/60 s，但世界时间来自 `WorldDirector._process()` 的**真实 delta**，
## 所以这里按真实时钟兜底，避免在极快的无头环境里被"帧数上限"提前掐断（T020 的 240 帧上限会）。
func _run_seconds(seconds: float) -> float:
	if _wd == null:
		return 0.0
	var t0 := _time_now()
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0 * 4.0) + 2000
	while _time_now() - t0 < seconds and Time.get_ticks_msec() < deadline:
		await physics_frame
	return _time_now() - t0


func _advance_frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _clip(s: String) -> String:
	return s.replace("\n", " | ").substr(0, 90)


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
