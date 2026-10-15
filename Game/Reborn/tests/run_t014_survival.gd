extends SceneTree
## T014 生存状态与统一时间入口 断言（可在打包产物内运行）
##
## 覆盖（`Docs/Tasks/T014.md` §6）：
##   A `SurvivalState` 数据契约（五字段 / 默认值 / 夹紧 / 比值 / 复制）
##   B 统一时间入口：`WorldDirector` 的世界时间是唯一时间源；显式门闩与树暂停都不推进
##   C 按时间消耗：饥/渴按 `Parameters.md` 速率下降；两个物种族速率不同
##   D **帧率无关**：30 / 60 / 144 Hz 三条步长推进同一段世界时间，结果近似一致
##   E 暂停不消耗（真实循环：跑 1 s → 树暂停 1 s → 恢复 1 s）
##   F 体力：消耗立即生效、`RegenDelay` 内不回复、之后按速率回复、封顶、不为负
##   G 生命：扣血 / 原因记录 / 夹紧 0 / `died` 恰好一次 / 死后不再发信号
##   H 极长帧（5 s 一次结算）与时间回退（读档）都不出错
##   I 集成：`AnimalBody` 真的按世界时间掉饥饿；调试入口 HUD 出现生存行；正式场景仍无调试节点
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t014_survival.gd' --quit-after 60000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"
const DEBUG_DIR := "res://scripts/debug/"

## 与 `SurvivalController.UPDATE_INTERVAL` 对齐的结算间隔（断言口径依赖它）
const UPDATE_INTERVAL := 0.2
const EPS := 1e-6

var _checks := 0
var _fails := 0
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null
var _wd: Node = null


func _initialize() -> void:
	print("TEST|run_t014_survival|engine=%s" % Engine.get_version_info().string)
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")
	print("MEASURE|world_director|node=%s|paused_ok=%s" % [str(_wd), str(paused == false)])

	_section_a_state_contract()
	await _section_b_world_time()
	await _section_c_consumption()
	_section_d_frame_rate_independence()
	await _section_e_pause_no_consumption()
	_section_f_stamina()
	_section_g_health()
	_section_h_long_frame_and_rewind()
	await _section_i_integration()

	_finish()


# ---------------------------------------------------------------------------
# A 数据契约
# ---------------------------------------------------------------------------

func _section_a_state_contract() -> void:
	print("---- A SurvivalState 契约 ----")
	_assert("A_configs_loaded", "2 个 SpeciesConfig", "%s / %s" % [_cat != null, _mouse != null],
		_cat != null and _mouse != null)
	var s := SurvivalState.new()
	_assert("A_is_resource", "Resource", s.get_class(), s is Resource)
	var names := []
	for p in s.get_property_list():
		names.append(String(p["name"]))
	for f in ["health", "hunger", "thirst", "stamina", "last_damage_reason"]:
		_assert("A_has_%s" % f, "契约字段存在", str(names.has(f)), names.has(f))
	_assert_near("A_default_health", 100.0, s.health, EPS)
	_assert_near("A_default_hunger", 100.0, s.hunger, EPS)
	_assert_near("A_default_thirst", 100.0, s.thirst, EPS)
	_assert_near("A_default_stamina", 100.0, s.stamina, EPS)
	_assert("A_default_damage_reason", "&\"\"", str(s.last_damage_reason), s.last_damage_reason == &"")

	# 夹紧：超上限夹到上限，负值夹到 0
	s.health = 150.0
	s.hunger = -5.0
	s.thirst = 0.0
	s.stamina = 300.0
	s.clamp_to_max(100.0, 100.0, 100.0, 100.0)
	_assert_near("A_clamp_health_high", 100.0, s.health, EPS)
	_assert_near("A_clamp_hunger_low", 0.0, s.hunger, EPS)
	_assert_near("A_clamp_thirst_zero", 0.0, s.thirst, EPS)
	_assert_near("A_clamp_stamina_high", 100.0, s.stamina, EPS)

	# 比值与复制
	s.hunger = 25.0
	_assert_near("A_ratio_hunger", 0.25, s.ratio(&"hunger", 100.0), EPS)
	_assert_near("A_ratio_unknown", 0.0, s.ratio(&"nope", 100.0), EPS)
	var copy := s.duplicate_state()
	_assert("A_duplicate_is_new_object", "不同实例", str(copy != s), copy != s)
	_assert_near("A_duplicate_value", 25.0, copy.hunger, EPS)
	copy.hunger = 1.0
	_assert_near("A_duplicate_is_deep_for_values", 25.0, s.hunger, EPS)


# ---------------------------------------------------------------------------
# B 统一时间入口
# ---------------------------------------------------------------------------

func _section_b_world_time() -> void:
	print("---- B 世界时间入口 ----")
	_assert("B_world_director_available", "Autoload 存在", str(_wd), _wd != null)
	if _wd == null:
		return
	var t0: float = _wd.world_time
	await _advance_frames(12)
	var t1: float = _wd.world_time
	_assert("B_world_time_advances", "t1 > t0", "%.4f -> %.4f" % [t0, t1], t1 > t0)
	_assert_near("B_get_world_time_matches_field", t1, _wd.get_world_time(), EPS)

	# 显式门闩
	_wd.time_advancing = false
	var t2: float = _wd.world_time
	await _advance_frames(12)
	_assert("B_gate_freezes_time", "world_time 不变", "%.6f -> %.6f" % [t2, _wd.world_time],
		absf(_wd.world_time - t2) <= EPS)
	_assert_near("B_gate_zero_sim_delta", 0.0, _wd.sim_delta, EPS)
	_assert("B_is_time_advancing_false", "false", str(_wd.is_time_advancing()), not _wd.is_time_advancing())
	_wd.time_advancing = true
	await _advance_frames(12)
	_assert("B_gate_resumes_time", "world_time 继续前进", "%.4f -> %.4f" % [t2, _wd.world_time],
		_wd.world_time > t2 + EPS)

	# 树暂停（第二条路径）
	var t3: float = _wd.world_time
	paused = true
	await _advance_frames(12)
	var frozen: bool = absf(_wd.world_time - t3) <= EPS
	paused = false
	_assert("B_tree_pause_freezes_time", "world_time 不变", "%.6f -> %.6f" % [t3, _wd.world_time], frozen)
	await _advance_frames(6)
	_assert("B_tree_unpause_resumes", "> 暂停时", "%.4f -> %.4f" % [t3, _wd.world_time], _wd.world_time > t3 + EPS)

	# 新游戏重置
	_wd.reset_for_new_game()
	_assert_near("B_reset_world_time", 0.0, _wd.world_time, EPS)
	_assert("B_reset_time_advancing", "true", str(_wd.is_time_advancing()), _wd.is_time_advancing())


# ---------------------------------------------------------------------------
# C 按时间消耗（用 0.2 的整数倍推进 → 无残留，可精确断言）
# ---------------------------------------------------------------------------

func _section_c_consumption() -> void:
	print("---- C 按时间消耗 ----")
	for cfg in [_cat, _mouse]:
		if cfg == null:
			continue
		var tag := String(cfg.species_id)
		var ctrl := SurvivalController.new(cfg)
		ctrl.tick_to(0.0)              # 先对齐世界时间（第一次 tick 只对齐、不消耗）
		_assert("%s_controller_state_ready" % tag, "非空", str(ctrl.state != null), ctrl.state != null)
		var seconds := 4.0
		var steps := int(round(seconds / UPDATE_INTERVAL))
		for k in range(1, steps + 1):
			ctrl.tick_to(k * UPDATE_INTERVAL)
		var elapsed := steps * UPDATE_INTERVAL
		_assert_near("%s_hunger_rate" % tag, cfg.hunger_loss_per_sec * elapsed, 100.0 - ctrl.state.hunger, 1e-4)
		_assert_near("%s_thirst_rate" % tag, cfg.thirst_loss_per_sec * elapsed, 100.0 - ctrl.state.thirst, 1e-4)
		_assert_near("%s_health_untouched" % tag, 100.0, ctrl.state.health, EPS)
		_assert_near("%s_stamina_untouched" % tag, 100.0, ctrl.state.stamina, EPS)
		print("MEASURE|consumption|%s|elapsed=%.2f|hunger=%.4f|thirst=%.4f|stamina=%.4f" % [
			tag, elapsed, ctrl.state.hunger, ctrl.state.thirst, ctrl.state.stamina
		])
	# 两个物种速率必须不同（配置真源在 *.tres）
	_assert("C_species_rates_differ_hunger", "猫 < 鼠",
		"%.3f < %.3f" % [_cat.hunger_loss_per_sec, _mouse.hunger_loss_per_sec],
		_cat.hunger_loss_per_sec < _mouse.hunger_loss_per_sec)
	_assert("C_species_rates_differ_thirst", "猫 < 鼠",
		"%.3f < %.3f" % [_cat.thirst_loss_per_sec, _mouse.thirst_loss_per_sec],
		_cat.thirst_loss_per_sec < _mouse.thirst_loss_per_sec)
	_assert_near("C_cat_hunger_param", 0.08, _cat.hunger_loss_per_sec, 1e-6)
	_assert_near("C_mouse_hunger_param", 0.10, _mouse.hunger_loss_per_sec, 1e-6)
	_assert_near("C_cat_thirst_param", 0.06, _cat.thirst_loss_per_sec, 1e-6)
	_assert_near("C_mouse_thirst_param", 0.08, _mouse.thirst_loss_per_sec, 1e-6)
	_assert_near("C_max_hunger_param", 100.0, _cat.max_hunger, EPS)

	# 归零后不会变负
	var ctrl2 := SurvivalController.new(_mouse)
	for k in range(1, int(round(3000.0 / UPDATE_INTERVAL)) + 1):
		ctrl2.tick_to(k * UPDATE_INTERVAL)
	_assert_near("C_hunger_never_negative", 0.0, ctrl2.state.hunger, EPS)
	_assert_near("C_thirst_never_negative", 0.0, ctrl2.state.thirst, EPS)


# ---------------------------------------------------------------------------
# D 帧率无关（核心判据）
# ---------------------------------------------------------------------------

func _section_d_frame_rate_independence() -> void:
	print("---- D 帧率无关（30 / 60 / 144 Hz） ----")
	var seconds := 60.0
	var steps: Array[float] = [1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0]
	var results: Array[float] = []
	for cfg in [_cat, _mouse]:
		if cfg == null:
			continue
		var tag := String(cfg.species_id)
		results.clear()
		var rate: float = cfg.hunger_loss_per_sec
		for step in steps:
			var ctrl := SurvivalController.new(cfg)
			ctrl.tick_to(0.0)          # 先对齐世界时间（第一次 tick 只对齐、不消耗）
			var n := int(round(seconds / step))
			for k in range(1, n + 1):
				ctrl.tick_to(k * step)
			results.append(100.0 - ctrl.state.hunger)
		var lo: float = rate * (seconds - UPDATE_INTERVAL)
		var hi: float = rate * seconds
		var spread: float = results.max() - results.min()
		for i in results.size():
			_assert("D_%s_step%d_in_band" % [tag, i], "[%.4f, %.4f]" % [lo, hi],
				"%.4f" % results[i], results[i] >= lo - 1e-4 and results[i] <= hi + 1e-4)
		_assert("D_%s_spread_within_one_interval" % tag, " ≤ %.4f" % (rate * UPDATE_INTERVAL + 1e-4),
			"%.6f（30/60/144Hz 实测：%.4f / %.4f / %.4f）" % [spread, results[0], results[1], results[2]],
			spread <= rate * UPDATE_INTERVAL + 1e-4)
		print("MEASURE|frame_rate|%s|60s|30Hz=%.4f|60Hz=%.4f|144Hz=%.4f|spread=%.6f" % [
			tag, results[0], results[1], results[2], spread
		])


# ---------------------------------------------------------------------------
# E 暂停不消耗（真实循环）
# ---------------------------------------------------------------------------

func _section_e_pause_no_consumption() -> void:
	print("---- E 暂停不消耗（真实循环） ----")
	if _wd == null:
		_assert("E_needs_world_director", "Autoload", "null", false)
		return
	var ctrl := SurvivalController.new(_cat)
	var last_t: float = _wd.world_time
	var spend := func() -> void:
		if _wd.world_time > last_t:
			ctrl.tick_to(_wd.world_time)
			last_t = _wd.world_time
	# 1) 跑 1 s
	await _run_world_seconds(1.0, spend)
	var after_run: float = ctrl.state.hunger
	_assert("E_consumes_while_running", "hunger < 100", "%.4f" % after_run, after_run < 100.0 - EPS)
	# 2) 暂停树：**世界时间根本不走**（实测暂停期间增量为 0）→ 按下限帧数等一小会儿，
	#    期间照旧调用 tick_to（时间没走 → 不消耗）
	paused = true
	var frozen_t0: float = _wd.world_time
	var h_before_pause: float = ctrl.state.hunger
	await _advance_frames(60)
	ctrl.tick_to(_wd.world_time)
	var frozen_dt: float = _wd.world_time - frozen_t0
	var after_pause: float = ctrl.state.hunger
	paused = false
	_assert_near("E_world_time_frozen_while_paused", 0.0, frozen_dt, 1e-9)
	_assert_near("E_no_consumption_while_paused", h_before_pause, after_pause, 1e-9)
	# 3) 恢复再跑 1 s
	await _run_world_seconds(1.0, spend)
	var after_resume: float = ctrl.state.hunger
	_assert("E_consumes_after_resume", "hunger < 暂停后", "%.4f -> %.4f" % [after_pause, after_resume],
		after_resume < after_pause - EPS)
	print("MEASURE|pause|run=%.4f|paused=%.4f|resumed=%.4f" % [after_run, after_pause, after_resume])


# ---------------------------------------------------------------------------
# F 体力
# ---------------------------------------------------------------------------

func _section_f_stamina() -> void:
	print("---- F 体力 ----")
	var cfg := _cat
	var ctrl := SurvivalController.new(cfg)
	ctrl.tick_to(0.0)
	var delay: float = cfg.regen_delay
	var regen: float = cfg.stamina_regen_per_sec
	var maxs: float = cfg.max_stamina
	_assert_near("F_starts_full", maxs, ctrl.state.stamina, EPS)

	ctrl.spend_stamina(30.0)
	_assert_near("F_spend_is_immediate", 70.0, ctrl.state.stamina, EPS)
	ctrl.spend_stamina(0.0)
	_assert_near("F_spend_zero_noop", 70.0, ctrl.state.stamina, EPS)
	ctrl.spend_stamina(999.0)
	_assert_near("F_spend_clamped_at_zero", 0.0, ctrl.state.stamina, EPS)

	# 从头来一遍，测回复曲线（步长 0.2 → 与延迟对齐，可精确断言）
	var c2 := SurvivalController.new(cfg)
	c2.tick_to(0.0)
	c2.spend_stamina(30.0)          # 70
	var steps_delay := int(round(delay / UPDATE_INTERVAL))
	for k in range(1, steps_delay + 1):
		c2.tick_to(k * UPDATE_INTERVAL)
	_assert_near("F_no_regen_within_delay", 70.0, c2.state.stamina, 1e-4)
	c2.tick_to((steps_delay + 1) * UPDATE_INTERVAL)
	_assert_near("F_regen_starts_after_delay", 70.0 + regen * UPDATE_INTERVAL, c2.state.stamina, 1e-4)
	# 一直跑到满，必须封顶且不越界
	for k in range(0, 40):
		c2.tick_to((steps_delay + 1) * UPDATE_INTERVAL + k * UPDATE_INTERVAL)
	_assert_near("F_regen_capped_at_max", maxs, c2.state.stamina, EPS)
	_assert("F_stamina_not_over_max", "≤ max", "%.4f" % c2.state.stamina, c2.state.stamina <= maxs + EPS)
	print("MEASURE|stamina|delay=%.2f|regen=%.1f|after_spend=70|after_delay+0.2=%.2f|max=%.1f" % [
		delay, regen, 70.0 + regen * UPDATE_INTERVAL, maxs
	])


# ---------------------------------------------------------------------------
# G 生命
# ---------------------------------------------------------------------------

func _section_g_health() -> void:
	print("---- G 生命 ----")
	var ctrl := SurvivalController.new(_cat)
	var deaths := [0]
	var reasons := []
	ctrl.died.connect(func(r: StringName) -> void:
		deaths[0] += 1
		reasons.append(r)
	)
	_assert("G_not_dead_initially", "false", str(ctrl.is_dead()), not ctrl.is_dead())
	ctrl.apply_damage(30.0, &"fall")
	_assert_near("G_damage_applied", 70.0, ctrl.state.health, EPS)
	_assert("G_reason_recorded", "fall", str(ctrl.state.last_damage_reason), ctrl.state.last_damage_reason == &"fall")
	_assert("G_died_count_0", "0", "%d" % deaths[0], deaths[0] == 0)
	ctrl.apply_damage(1000.0, &"maul")
	_assert_near("G_health_clamped_zero", 0.0, ctrl.state.health, EPS)
	_assert("G_died_once", "1", "%d" % deaths[0], deaths[0] == 1)
	_assert("G_died_reason", "maul", str(reasons[0]), reasons[0] == &"maul")
	_assert("G_is_dead_true", "true", str(ctrl.is_dead()), ctrl.is_dead())
	ctrl.apply_damage(10.0, &"again")
	_assert("G_no_second_died_signal", "1", "%d" % deaths[0], deaths[0] == 1)
	# 非正伤害不产生副作用
	var c2 := SurvivalController.new(_cat)
	c2.apply_damage(0.0, &"zero")
	_assert_near("G_zero_damage_noop", 100.0, c2.state.health, EPS)
	_assert("G_zero_damage_no_reason", "&\"\"", str(c2.state.last_damage_reason), c2.state.last_damage_reason == &"")
	c2.apply_damage(-5.0, &"negative")
	_assert_near("G_negative_damage_noop", 100.0, c2.state.health, EPS)
	_assert("G_negative_damage_no_reason", "&\"\"", str(c2.state.last_damage_reason), c2.state.last_damage_reason == &"")


# ---------------------------------------------------------------------------
# H 极长帧 / 时间回退
# ---------------------------------------------------------------------------

func _section_h_long_frame_and_rewind() -> void:
	print("---- H 极长帧与时间回退 ----")
	var cfg := _cat
	var ctrl := SurvivalController.new(cfg)
	ctrl.tick_to(0.0)
	var advanced := ctrl.tick_to(5.0)
	_assert_near("H_long_frame_dt", 5.0, advanced, EPS)
	_assert_near("H_long_frame_hunger", 100.0 - cfg.hunger_loss_per_sec * 5.0, ctrl.state.hunger, 1e-4)
	_assert_near("H_long_frame_thirst", 100.0 - cfg.thirst_loss_per_sec * 5.0, ctrl.state.thirst, 1e-4)
	_assert("H_long_frame_values_sane", "都在 (0, 100]",
		"h=%.4f t=%.4f" % [ctrl.state.hunger, ctrl.state.thirst],
		ctrl.state.hunger > 0.0 and ctrl.state.thirst > 0.0)
	var before: float = ctrl.state.hunger
	var rewound := ctrl.tick_to(3.0)
	_assert_near("H_rewind_returns_zero", 0.0, rewound, EPS)
	_assert_near("H_rewind_no_negative_consumption", before, ctrl.state.hunger, 1e-9)
	# 极短帧（1/1000 s）也不出错、几乎不动
	var c2 := SurvivalController.new(cfg)
	c2.tick_to(0.0)
	for k in range(1, 1001):
		c2.tick_to(k * 0.001)
	_assert_near("H_tiny_frames_hunger_after_1s", 100.0 - cfg.hunger_loss_per_sec * 1.0, c2.state.hunger, 1e-4)
	print("MEASURE|long_frame|dt5s_hunger=%.4f|rewind=%.6f|tiny_1s_hunger=%.4f" % [
		ctrl.state.hunger, rewound, c2.state.hunger
	])


# ---------------------------------------------------------------------------
# I 集成
# ---------------------------------------------------------------------------

func _section_i_integration() -> void:
	print("---- I 集成（AnimalBody + 调试入口） ----")
	if _wd == null:
		_assert("I_needs_world_director", "Autoload", "null", false)
		return
	var world := Node3D.new()
	world.name = "T014World"
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	cs.shape = box
	ground.add_child(cs)
	world.add_child(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)
	await _advance_frames(2)

	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = _cat
	body.player_controlled = false
	world.add_child(body)
	body.global_position = Vector3(0.0, _cat.capsule_half_height + 0.01, 0.0)
	body.velocity = Vector3.ZERO
	await _advance_frames(10)
	_assert("I_body_has_survival", "SurvivalController", str(body.survival != null), body.survival != null)
	var st: SurvivalState = body.survival_snapshot()
	_assert("I_snapshot_is_state", "SurvivalState", str(st != null), st != null)
	var debug: Dictionary = body.debug_state()
	for f in ["health", "hunger", "thirst", "stamina"]:
		_assert("I_debug_state_has_%s" % f, "字段存在", str(debug.has(f)), debug.has(f))

	var t0: float = _wd.world_time
	var h0: float = body.survival_snapshot().hunger
	await _run_world_seconds(2.0)
	var elapsed: float = _wd.world_time - t0
	var consumed: float = h0 - body.survival_snapshot().hunger
	var rate: float = _cat.hunger_loss_per_sec
	_assert("I_body_hunger_decreases", "> 0", "%.4f" % consumed, consumed > EPS)
	_assert("I_body_consumption_matches_clock", "[%.4f, %.4f]" % [(elapsed - UPDATE_INTERVAL) * rate, elapsed * rate],
		"%.4f（elapsed=%.3f, rate=%.2f）" % [consumed, elapsed, rate],
		consumed >= (elapsed - UPDATE_INTERVAL) * rate - 1e-4 and consumed <= elapsed * rate + 1e-4)
	print("MEASURE|integration|body|elapsed=%.3f|consumed=%.4f|expected_max=%.4f" % [elapsed, consumed, elapsed * rate])

	# 暂停不消耗（在真实身体上再验一次）：暂停期间**世界时间不走** → 身体也不消耗
	paused = true
	var h1: float = body.survival_snapshot().hunger
	var t_frozen0: float = _wd.world_time
	await _advance_frames(60)
	var t_frozen_dt: float = _wd.world_time - t_frozen0
	var h2: float = body.survival_snapshot().hunger
	paused = false
	_assert_near("I_world_time_frozen_while_paused", 0.0, t_frozen_dt, 1e-9)
	_assert_near("I_body_no_consumption_while_paused", h1, h2, 1e-9)
	world.queue_free()
	await _advance_frames(2)

	# 调试入口 HUD 出现生存行（只在调试入口；正式场景仍干净）
	var wd_node := _wd
	var entry: Node = (load(ENTRY) as PackedScene).instantiate()
	root.add_child(entry)
	await _advance_frames(20)
	var hud := String(entry.call("hud_text"))
	_assert("I_debug_hud_has_survival_line", "含 survival",
		"len=%d" % hud.length(), hud.find("survival") >= 0)
	_assert("I_debug_hud_has_hunger_value", "含 hunger=", str(hud.find("hunger=") >= 0), hud.find("hunger=") >= 0)
	for scene_path in [LEVEL, MAIN]:
		var inst: Node = (load(scene_path) as PackedScene).instantiate()
		var debug_nodes := 0
		for n in _all_nodes(inst):
			if n.get_script() != null and String(n.get_script().resource_path).begins_with(DEBUG_DIR):
				debug_nodes += 1
		_assert("I_%s_no_debug_nodes" % scene_path.get_file(), "0", "%d" % debug_nodes, debug_nodes == 0)
		inst.free()
	_assert("I_world_director_alive", "同一实例", str(wd_node == _wd), wd_node == _wd)
	print("MEASURE|debug_hud_survival_line|%s" % hud.split("\n")[0])
	for line in hud.split("\n"):
		if String(line).find("survival") >= 0:
			print("MEASURE|debug_hud_survival_line|%s" % line)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _advance_frames(n: int) -> void:
	for i in n:
		await process_frame


## 推进真实世界时间 `seconds` 秒；每帧调用 `probe`（若给了）以让被测对象读到世界时间
func _run_world_seconds(seconds: float, probe: Callable = Callable(), max_frames := 20000) -> float:
	if _wd == null:
		return 0.0
	var t0: float = _wd.world_time
	var frames := 0
	# `not paused` 是**安全阀**：树暂停时世界时间根本不走，在这里等会死循环（T014 实测踩到过）
	while _wd.world_time - t0 < seconds and frames < max_frames and not paused:
		await process_frame
		frames += 1
		if probe.is_valid():
			probe.call()
	return _wd.world_time - t0


func _all_nodes(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all_nodes(c))
	return out


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
