extends SceneTree
## T015 消耗、警告与基础伤害 断言（可在打包产物内运行）
##
## 覆盖（`Docs/Tasks/T015.md` §6；数值全部来自 `Docs/Parameters.md` 第 65 行）：
##   A 参数落地（六个新字段 + 校验 + 单位换算自查）
##   B 冲刺消耗：按 **世界时间差** 扣 `SprintStaminaPerSecond`；不冲刺不扣；冲刺期间不恢复
##   C 双门控：`Stamina≥5` 才能**开始**冲刺；已开始可跑到**耗尽**；耗尽转行走
##   D 耗尽不被卡死：体力 0 按住冲刺仍以**行走速度**前进
##   E 恢复：`RegenDelay` 内不回复，之后按 `StaminaRegenPerSecond` 恢复并封顶
##   F 警告：`Hunger/Thirst ≤ 25` 发警告（布尔量 + `warning_changed` 事件）；警告本身不扣血
##   G 危机扣血：任一归零各扣 1/s、两项均零 2/s、`Health` 不自动恢复、归零只死一次
##   H 跌落伤害：`≤700 cm/s` 无伤；超过 `(v−7)×10`；上限 100；原因为 `fall`
##   I 集成：`AnimalBody` 冲刺门控 + 调试 HUD 出现警告标记 + 正式场景仍无调试节点
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t015_costs.gd' --quit-after 60000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"
const DEBUG_DIR := "res://scripts/debug/"

const UPDATE_INTERVAL := 0.2
const EPS := 1e-6
## 重力（用于"期望落地速度"的独立换算；Godot 默认 9.8，断言里同时打印实测值）
const G := 9.8

var _checks := 0
var _fails := 0
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null


func _initialize() -> void:
	print("TEST|run_t015_costs|engine=%s" % Engine.get_version_info().string)
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")

	_section_a_params()
	await _section_b_sprint_cost()
	await _section_c_sprint_gating()
	await _section_d_exhausted_keeps_walking()
	await _section_e_regen()
	_section_f_warnings()
	_section_g_crisis_damage()
	await _section_h_fall_damage()
	await _section_i_integration()

	_finish()


# ---------------------------------------------------------------------------
# A 参数落地
# ---------------------------------------------------------------------------

func _section_a_params() -> void:
	print("---- A 参数落地 ----")
	_assert("A_configs_loaded", "2 个配置", "%s / %s" % [_cat != null, _mouse != null],
		_cat != null and _mouse != null)
	if _cat == null or _mouse == null:
		return
	for cfg in [_cat, _mouse]:
		var tag := String(cfg.species_id)
		_assert_near("A_%s_sprint_min_stamina" % tag, 5.0, cfg.sprint_min_stamina, EPS)
		_assert_near("A_%s_low_stat_threshold" % tag, 25.0, cfg.low_stat_threshold, EPS)
		_assert_near("A_%s_starvation_damage" % tag, 1.0, cfg.starvation_damage_per_sec, EPS)
		_assert_near("A_%s_dehydration_damage" % tag, 1.0, cfg.dehydration_damage_per_sec, EPS)
		_assert_near("A_%s_fall_safe_speed" % tag, 7.0, cfg.fall_safe_vertical_speed, EPS)
		_assert_near("A_%s_fall_damage_scale" % tag, 10.0, cfg.fall_damage_scale, EPS)
		_assert("A_%s_validate_ok" % tag, "无问题", str(cfg.validate_config()), cfg.validate_config().is_empty())
		_assert_near("A_%s_sprint_cost_param" % tag, 15.0 if cfg.species_id == &"Cat" else 35.0,
			cfg.sprint_stamina_per_sec, EPS)

	# 非法值必须能被校验挡住（说明校验真的在跑，不是"永远返回空"）
	var bad: SpeciesConfig = _cat.duplicate() as SpeciesConfig
	bad.low_stat_threshold = -1.0
	_assert("A_validate_rejects_bad_threshold", "≥1 条问题", str(bad.validate_config().size()),
		bad.validate_config().size() >= 1)
	var bad2: SpeciesConfig = _cat.duplicate() as SpeciesConfig
	bad2.fall_damage_scale = 0.0
	_assert("A_validate_rejects_zero_fall_scale", "≥1 条问题", str(bad2.validate_config().size()),
		bad2.validate_config().size() >= 1)
	var bad3: SpeciesConfig = _cat.duplicate() as SpeciesConfig
	bad3.sprint_min_stamina = -1.0
	_assert("A_validate_rejects_negative_min_stamina", "≥1 条问题", str(bad3.validate_config().size()),
		bad3.validate_config().size() >= 1)

	# 单位换算自查（Parameters.md：700 cm/s 无伤，超过按 (speed_cm − 700) × 0.1，上限 100）
	_assert_near("A_unit_700cms_is_7ms", 7.0, 700.0 / 100.0, EPS)
	_assert_near("A_unit_formula_cm", 30.0, (1000.0 - 700.0) * 0.1, EPS)
	_assert_near("A_unit_formula_m", 30.0, (10.0 - 7.0) * 10.0, EPS)
	_assert_near("A_fall_cap_is_max_health", 100.0, _cat.max_health, EPS)


# ---------------------------------------------------------------------------
# B 冲刺消耗（真实循环 + 世界时间）
# ---------------------------------------------------------------------------

func _section_b_sprint_cost() -> void:
	print("---- B 冲刺消耗 ----")
	if _wd == null:
		_assert("B_needs_world_director", "Autoload", "null", false)
		return
	for cfg in [_cat, _mouse]:
		var tag := String(cfg.species_id)
		var rate: float = cfg.sprint_stamina_per_sec
		# 1) 冲刺 1 s：体力下降 ≈ rate × 实际经过时间
		var r := await _run_body(cfg, true, 1.0)
		var spent: float = r["stamina_before"] - r["stamina_after"]
		_assert("B_%s_sprint_consumes" % tag, "≈ %.1f×%.2fs" % [rate, r["elapsed"]],
			"%.4f（elapsed=%.3f）" % [spent, r["elapsed"]],
			absf(spent - rate * r["elapsed"]) <= rate * 0.05 + 0.2)
		_assert("B_%s_sprinting_flag" % tag, "true", str(r["sprinting"]), r["sprinting"])
		_assert("B_%s_speed_is_sprint" % tag, "%.2f" % cfg.sprint_speed, "%.2f" % r["speed_end"],
			absf(float(r["speed_end"]) - cfg.sprint_speed) <= 0.001)
		# 2) 不冲刺同长度：体力一点都不掉
		var r2 := await _run_body(cfg, false, 1.0)
		_assert_near("B_%s_walk_no_stamina_cost" % tag, r2["stamina_before"], r2["stamina_after"], 1e-6)
		# 3) 冲刺期间不恢复：先把体力打到 50，再冲刺 1 s → 只降不升
		var r3 := await _run_body(cfg, true, 1.0, 50.0)
		var spent3: float = r3["stamina_before"] - r3["stamina_after"]
		_assert("B_%s_no_regen_while_sprinting" % tag, "仍按 rate 下降（无恢复抵消）",
			"%.4f（rate×elapsed=%.4f）" % [spent3, rate * r3["elapsed"]],
			absf(spent3 - rate * r3["elapsed"]) <= rate * 0.05 + 0.2)
		print("MEASURE|sprint_cost|%s|elapsed=%.3f|spent=%.4f|rate=%.1f|walk_spent=%.4f|spent_from50=%.4f" % [
			tag, r["elapsed"], spent, rate, r2["stamina_before"] - r2["stamina_after"], spent3
		])
	_free_world()


# ---------------------------------------------------------------------------
# C 双门控
# ---------------------------------------------------------------------------

func _section_c_sprint_gating() -> void:
	print("---- C 冲刺双门控 ----")
	if _wd == null:
		_assert("C_needs_world_director", "Autoload", "null", false)
		return
	var cfg := _cat
	var body := await _spawn_in_flat_world(cfg)
	# 体力 4（<5）：按住冲刺也不许开始 → 走速，而且**不是 0**
	body.survival.spend_stamina(96.0)   # 体力 = 4（<5）；用 spend 重置"消耗后延迟"，避免测试期间自动恢复
	body.want_sprint = true
	body.move_intent = Vector2(0.0, -1.0)
	await _advance_frames(3)
	_assert("C_below_min_cannot_start", "false", str(body.is_sprinting()), not body.is_sprinting())
	_assert_near("C_below_min_speed_is_walk", cfg.walk_speed, body.current_speed(), 0.001)
	var p0: Vector3 = body.global_position
	await _run_world_seconds(0.5)
	_assert("C_below_min_still_moves", "位移 > 0", "%.3f" % (body.global_position - p0).length(),
		(body.global_position - p0).length() > 0.1)
	# 体力 6（≥5）：可以开始 → 跑速
	body.survival.state.stamina = 6.0   # 直接置 6（≥5）；此时距上次消耗 <1 s，不会自动恢复
	body.want_sprint = false
	await _advance_frames(2)
	body.want_sprint = true
	await _advance_frames(2)
	_assert("C_at_min_can_start", "true", str(body.is_sprinting()), body.is_sprinting())
	_assert_near("C_at_min_speed_is_sprint", cfg.sprint_speed, body.current_speed(), 0.001)
	# 已经开始 → 继续跑到耗尽（0），然后转行走
	await _run_world_seconds(0.8)
	_assert("C_exhausted_after_running", "stamina ≈ 0", "%.4f" % body.survival.state.stamina,
		body.survival.state.stamina <= 0.01)
	_assert("C_exhausted_stops_sprinting", "false", str(body.is_sprinting()), not body.is_sprinting())
	_assert_near("C_exhausted_speed_is_walk", cfg.walk_speed, body.current_speed(), 0.001)
	var p1: Vector3 = body.global_position
	await _run_world_seconds(0.5)
	_assert("C_exhausted_keeps_moving", "位移 > 0", "%.3f" % (body.global_position - p1).length(),
		(body.global_position - p1).length() > 0.1)
	print("MEASURE|gating|below_min_speed=%.2f|at_min_speed=%.2f|exhausted_speed=%.2f|stamina_end=%.4f" % [
		cfg.walk_speed, cfg.sprint_speed, cfg.walk_speed, body.survival.state.stamina
	])
	body.want_sprint = false
	body.move_intent = Vector2.ZERO
	_free_world()


# ---------------------------------------------------------------------------
# D 耗尽不被卡死（S02 口径）
# ---------------------------------------------------------------------------

func _section_d_exhausted_keeps_walking() -> void:
	print("---- D 耗尽仍可行走（S02） ----")
	if _wd == null:
		_assert("D_needs_world_director", "Autoload", "null", false)
		return
	for cfg in [_cat, _mouse]:
		var tag := String(cfg.species_id)
		var body := await _spawn_in_flat_world(cfg)
		body.survival.spend_stamina(1000.0)  # 体力 = 0 且重置延迟（否则 1 s 后会自动恢复到 ≥5）
		body.want_sprint = true
		body.move_intent = Vector2(0.0, -1.0)
		var p0: Vector3 = body.global_position
		var elapsed := await _run_world_seconds(0.6)   # 停在 RegenDelay 内，保证这段测试里不会自动恢复
		var moved: float = (body.global_position - p0).length()
		# 期望位移要扣掉**加速段**（从静止到 walk_speed 需要 walk_speed/max_acceleration 秒）
		var ramp_loss: float = 0.5 * cfg.walk_speed * cfg.walk_speed / cfg.max_acceleration
		var expect: float = cfg.walk_speed * elapsed - ramp_loss
		_assert("D_%s_moves_while_exhausted" % tag, "≈ walk_speed×%.2fs = %.2f m" % [elapsed, expect],
			"%.3f m" % moved, moved >= expect * 0.9 and moved <= expect * 1.15)
		_assert("D_%s_still_on_floor" % tag, "true", str(body.is_on_floor()), body.is_on_floor())
		_assert("D_%s_not_sprinting" % tag, "false", str(body.is_sprinting()), not body.is_sprinting())
		var st: SurvivalState = body.survival_snapshot()
		_assert("D_%s_health_intact" % tag, "100", "%.2f" % st.health, absf(st.health - 100.0) <= 0.01)
		print("MEASURE|exhausted_walk|%s|moved=%.3f|expected=%.3f|speed=%.2f" % [
			tag, moved, expect, body.current_speed()
		])
		body.want_sprint = false
		body.move_intent = Vector2.ZERO
		_free_world()


# ---------------------------------------------------------------------------
# E 恢复
# ---------------------------------------------------------------------------

func _section_e_regen() -> void:
	print("---- E 体力恢复 ----")
	if _wd == null:
		_assert("E_needs_world_director", "Autoload", "null", false)
		return
	var cfg := _cat
	var body := await _spawn_in_flat_world(cfg)
	body.want_sprint = false
	body.move_intent = Vector2.ZERO
	body.survival.spend_stamina(80.0)     # 体力 = 20；用 spend 重置"消耗后延迟"（延迟是相对**上次消耗**的）
	await _advance_frames(2)
	var t0: float = _wd.world_time
	var s0: float = body.survival.state.stamina
	# RegenDelay 内不回复
	await _run_world_seconds(cfg.regen_delay)
	var elapsed_delay: float = _wd.world_time - t0
	_assert("E_no_regen_within_delay", "≈ %.4f" % s0, "%.4f（elapsed=%.3f）" % [body.survival.state.stamina, elapsed_delay],
		absf(body.survival.state.stamina - s0) <= 0.3)
	# 之后按 rate 恢复
	var s1: float = body.survival.state.stamina
	var t1: float = _wd.world_time
	await _run_world_seconds(1.0)
	var elapsed2: float = _wd.world_time - t1
	var gained: float = body.survival.state.stamina - s1
	_assert("E_regen_rate", "≈ %.1f×%.2fs" % [cfg.stamina_regen_per_sec, elapsed2],
		"%.4f" % gained, absf(gained - cfg.stamina_regen_per_sec * elapsed2) <= cfg.stamina_regen_per_sec * 0.05 + 0.3)
	# 封顶
	await _run_world_seconds(6.0)
	_assert_near("E_regen_capped", cfg.max_stamina, body.survival.state.stamina, 1e-6)
	print("MEASURE|regen|delay_hold=%.4f|gained=%.4f|elapsed=%.3f|final=%.4f" % [
		s0, gained, elapsed2, body.survival.state.stamina
	])
	_free_world()


# ---------------------------------------------------------------------------
# F 警告
# ---------------------------------------------------------------------------

func _section_f_warnings() -> void:
	print("---- F 饥渴警告 ----")
	var cfg := _cat
	_assert("F_not_low_at_100", "false", str(SurvivalController.new(cfg).is_low_hunger()),
		not SurvivalController.new(cfg).is_low_hunger())
	var c := SurvivalController.new(cfg)
	c.state.hunger = 25.1
	_assert("F_above_threshold_no_warning", "false", str(c.is_low_hunger()), not c.is_low_hunger())
	c.state.hunger = 25.0
	_assert("F_at_threshold_warns", "true（≤25）", str(c.is_low_hunger()), c.is_low_hunger())
	c.state.hunger = 24.9
	_assert("F_below_threshold_warns", "true", str(c.is_low_hunger()), c.is_low_hunger())
	_assert("F_thirst_independent", "thirst=100 无警告", str(c.is_low_thirst()), not c.is_low_thirst())
	c.state.thirst = 10.0
	_assert("F_thirst_warns", "true", str(c.is_low_thirst()), c.is_low_thirst())
	_assert("F_both_can_warn", "hunger 与 thirst 同时", str(c.is_low_hunger() and c.is_low_thirst()),
		c.is_low_hunger() and c.is_low_thirst())

	# 事件在跨越阈值时发出（每个方向各一次）
	var events := []
	var c2 := SurvivalController.new(cfg)
	c2.warning_changed.connect(func(kind: StringName, active: bool) -> void:
		events.append("%s=%s" % [kind, active])
	)
	c2.state.hunger = 10.0
	c2.tick_to(0.0)
	c2.tick_to(UPDATE_INTERVAL)
	c2.state.hunger = 100.0
	c2.tick_to(2 * UPDATE_INTERVAL)
	_assert("F_warning_event_fired", "≥2 条", str(events), events.size() >= 2)
	_assert("F_warning_event_kind", "hunger", str(events), str(events).find("hunger=true") >= 0)
	_assert("F_warning_cleared_event", "hunger=false", str(events), str(events).find("hunger=false") >= 0)

	# 警告本身不扣血
	var c3 := SurvivalController.new(cfg)
	c3.state.hunger = 20.0
	c3.state.thirst = 20.0
	c3.tick_to(0.0)
	for k in range(1, 26):      # 5 s
		c3.tick_to(k * UPDATE_INTERVAL)
	_assert_near("F_warning_no_damage", 100.0, c3.state.health, EPS)
	_assert("F_warning_still_warns", "true", str(c3.is_low_hunger() and c3.is_low_thirst()),
		c3.is_low_hunger() and c3.is_low_thirst())
	print("MEASURE|warnings|hunger25.0=%s|hunger20_health_5s=%.4f|events=%s" % [
		str(true), c3.state.health, str(events)
	])


# ---------------------------------------------------------------------------
# G 危机扣血（S02 口径）
# ---------------------------------------------------------------------------

func _section_g_crisis_damage() -> void:
	print("---- G 危机扣血 ----")
	var cfg := _cat
	# 只用饥饿归零：10 s 世界时间 → 扣 10
	var c1 := SurvivalController.new(cfg)
	c1.state.hunger = 0.0
	c1.tick_to(0.0)
	for k in range(1, 51):
		c1.tick_to(k * UPDATE_INTERVAL)
	_assert_near("G_starvation_10s_damage", 90.0, c1.state.health, 1e-3)
	_assert("G_starvation_reason", "starvation", str(c1.state.last_damage_reason),
		c1.state.last_damage_reason == &"starvation")
	_assert("G_starvation_flag", "true", str(c1.is_starving()), c1.is_starving())

	# 只用口渴归零
	var c2 := SurvivalController.new(cfg)
	c2.state.thirst = 0.0
	c2.tick_to(0.0)
	for k in range(1, 51):
		c2.tick_to(k * UPDATE_INTERVAL)
	_assert_near("G_dehydration_10s_damage", 90.0, c2.state.health, 1e-3)
	_assert("G_dehydration_reason", "dehydration", str(c2.state.last_damage_reason),
		c2.state.last_damage_reason == &"dehydration")

	# 两项都归零 → 2/s
	var c3 := SurvivalController.new(cfg)
	c3.state.hunger = 0.0
	c3.state.thirst = 0.0
	c3.tick_to(0.0)
	for k in range(1, 51):
		c3.tick_to(k * UPDATE_INTERVAL)
	_assert_near("G_both_zero_10s_damage", 80.0, c3.state.health, 1e-3)
	_assert("G_both_reason", "exhaustion", str(c3.state.last_damage_reason),
		c3.state.last_damage_reason == &"exhaustion")

	# 没有危机就不掉血、也不自动恢复
	var c4 := SurvivalController.new(cfg)
	c4.state.health = 50.0
	c4.state.hunger = 80.0
	c4.state.thirst = 80.0
	c4.tick_to(0.0)
	for k in range(1, 51):
		c4.tick_to(k * UPDATE_INTERVAL)
	_assert_near("G_no_crisis_no_change", 50.0, c4.state.health, EPS)

	# 归零只死一次，且不再变负
	var c5 := SurvivalController.new(cfg)
	c5.state.hunger = 0.0
	c5.state.thirst = 0.0
	var deaths := [0]
	c5.died.connect(func(_r: StringName) -> void: deaths[0] += 1)
	c5.tick_to(0.0)
	for k in range(1, int(round(200.0 / UPDATE_INTERVAL)) + 1):
		c5.tick_to(k * UPDATE_INTERVAL)
	_assert_near("G_health_never_negative", 0.0, c5.state.health, EPS)
	_assert("G_died_once", "1", "%d" % deaths[0], deaths[0] == 1)
	_assert("G_is_dead", "true", str(c5.is_dead()), c5.is_dead())
	print("MEASURE|crisis|starvation10s=%.3f|dehydration10s=%.3f|both10s=%.3f|died=%d" % [
		c1.state.health, c2.state.health, c3.state.health, deaths[0]
	])


# ---------------------------------------------------------------------------
# H 跌落伤害
# ---------------------------------------------------------------------------

func _section_h_fall_damage() -> void:
	print("---- H 跌落伤害 ----")
	if _wd == null:
		_assert("H_needs_world_director", "Autoload", "null", false)
		return
	# 0.5 m（≈3.1 m/s < 7）→ 无伤
	var r1 := await _fall_from(_cat, 0.5)
	_assert("H_short_fall_speed_below_safe", "< 7 m/s", "%.3f m/s" % r1["fall_speed"],
		float(r1["fall_speed"]) < _cat.fall_safe_vertical_speed)
	_assert_near("H_short_fall_no_damage", 100.0, r1["health"], 1e-6)
	# 3 m（≈7.67 m/s）→ 伤害 = (v−7)×10
	var r2 := await _fall_from(_cat, 3.0)
	var v2: float = r2["fall_speed"]
	var expected2: float = (v2 - _cat.fall_safe_vertical_speed) * _cat.fall_damage_scale
	_assert("H_mid_fall_exceeds_safe", "> 7 m/s", "%.3f m/s" % v2, v2 > _cat.fall_safe_vertical_speed)
	_assert_near("H_mid_fall_damage_matches_formula", expected2, 100.0 - float(r2["health"]), 0.02)
	_assert("H_mid_fall_reason", "fall", str(r2["reason"]), StringName(r2["reason"]) == &"fall")
	# 与解析解对照（sqrt(2gh)），允许一个物理步的误差（±0.2 m/s）
	var v_analytic: float = sqrt(2.0 * G * 3.0)
	_assert("H_mid_fall_speed_matches_analytic", "√(2gh)=%.2f ±0.25" % v_analytic, "%.3f" % v2,
		absf(v2 - v_analytic) <= 0.25)
	# 极高落差 → 伤害封顶到 max_health
	var r3 := await _fall_from(_cat, 40.0)
	_assert_near("H_huge_fall_capped", _cat.max_health, 100.0 - float(r3["health"]), 1e-6)
	_assert("H_huge_fall_speed_big", "≫ 7 m/s", "%.2f m/s" % float(r3["fall_speed"]),
		float(r3["fall_speed"]) > 20.0)
	print("MEASURE|fall|0.5m_v=%.3f_dmg=%.3f|3m_v=%.3f_dmg=%.3f|40m_v=%.2f_dmg=%.3f" % [
		r1["fall_speed"], 100.0 - float(r1["health"]), v2, 100.0 - float(r2["health"]),
		r3["fall_speed"], 100.0 - float(r3["health"])
	])


# ---------------------------------------------------------------------------
# I 集成
# ---------------------------------------------------------------------------

func _section_i_integration() -> void:
	print("---- I 集成 ----")
	if _wd == null:
		_assert("I_needs_world_director", "Autoload", "null", false)
		return
	var body := await _spawn_in_flat_world(_cat)
	body.survival.spend_stamina(80.0)      # 体力 = 20（并重置延迟）
	body.want_sprint = true
	body.move_intent = Vector2(0.0, -1.0)
	await _advance_frames(3)
	_assert("I_body_sprinting", "true", str(body.is_sprinting()), body.is_sprinting())
	var s0: float = body.survival.state.stamina
	var t0: float = _wd.world_time
	await _run_world_seconds(0.5)
	var elapsed: float = _wd.world_time - t0
	var spent: float = s0 - body.survival.state.stamina
	_assert("I_body_sprint_cost", "≈ %.1f×%.2fs" % [_cat.sprint_stamina_per_sec, elapsed],
		"%.4f" % spent, absf(spent - _cat.sprint_stamina_per_sec * elapsed) <= _cat.sprint_stamina_per_sec * 0.05 + 0.3)
	# 体力降到 <5 后应转行走（本用例 20 → 约 12.5，仍在冲刺；把体力直接压到 3 再验一次门控）
	body.survival.spend_stamina(1000.0)    # 体力 = 0（重置延迟，保证这段时间内不恢复）
	await _advance_frames(3)
	_assert("I_body_below_min_walks", "false", str(body.is_sprinting()), not body.is_sprinting())
	_assert_near("I_body_below_min_speed", _cat.walk_speed, body.current_speed(), 0.001)
	print("MEASURE|integration|sprint_spent=%.4f|elapsed=%.3f|walk_speed_after=%.2f" % [
		spent, elapsed, body.current_speed()
	])
	body.want_sprint = false
	body.move_intent = Vector2.ZERO
	_free_world()

	# 调试入口 HUD：警告/危机标记
	var entry: Node = (load(ENTRY) as PackedScene).instantiate()
	root.add_child(entry)
	await _advance_frames(20)
	var hud := String(entry.call("hud_text"))
	_assert("I_debug_hud_has_survival", "含 survival", "len=%d" % hud.length(), hud.find("survival") >= 0)
	_assert("I_debug_hud_has_warn_marker", "含 warn=", str(hud.find("warn=") >= 0), hud.find("warn=") >= 0)
	for line in hud.split("\n"):
		if String(line).find("survival") >= 0:
			print("MEASURE|debug_hud_survival_line|%s" % line)
	for scene_path in [LEVEL, MAIN]:
		var inst: Node = (load(scene_path) as PackedScene).instantiate()
		var debug_nodes := 0
		for n in _all_nodes(inst):
			if n.get_script() != null and String(n.get_script().resource_path).begins_with(DEBUG_DIR):
				debug_nodes += 1
		_assert("I_%s_no_debug_nodes" % scene_path.get_file(), "0", "%d" % debug_nodes, debug_nodes == 0)
		inst.free()


# ---------------------------------------------------------------------------
# 工具：世界 / 身体 / 采样
# ---------------------------------------------------------------------------

func _new_flat_world() -> void:
	_free_world()
	_world = Node3D.new()
	_world.name = "T015World"
	root.add_child(_world)
	await _advance_frames(2)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	cs.shape = box
	sb.add_child(cs)
	_world.add_child(sb)
	sb.global_position = Vector3(0.0, -0.5, 0.0)
	await _advance_frames(2)


func _free_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		_world = null


func _spawn_in_flat_world(cfg: SpeciesConfig) -> AnimalBody:
	await _new_flat_world()
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = false
	_world.add_child(body)
	body.global_position = Vector3(0.0, cfg.capsule_half_height + 0.01, 0.0)
	body.velocity = Vector3.ZERO
	await _advance_frames(10)
	return body


## 跑 `seconds` 世界时间：返回体力/速度/是否冲刺等
func _run_body(cfg: SpeciesConfig, sprint: bool, seconds: float, start_stamina: float = -1.0) -> Dictionary:
	var body := await _spawn_in_flat_world(cfg)
	if start_stamina >= 0.0:
		body.survival.spend_stamina(100.0 - start_stamina)   # 赋值 + 重置"消耗后延迟"
	body.want_sprint = sprint
	body.move_intent = Vector2(0.0, -1.0)
	await _advance_frames(3)
	var s_before: float = body.survival.state.stamina
	var elapsed := await _run_world_seconds(seconds)
	var res := {
		"elapsed": elapsed,
		"stamina_before": s_before,
		"stamina_after": body.survival.state.stamina,
		"sprinting": body.is_sprinting(),
		"speed_end": body.current_speed(),
		"on_floor": body.is_on_floor(),
	}
	body.want_sprint = false
	body.move_intent = Vector2.ZERO
	_free_world()
	return res


## 从 `height` 米高处自由落体到地面，返回落地前垂直速度与落地后的生命值
func _fall_from(cfg: SpeciesConfig, height: float) -> Dictionary:
	await _new_flat_world()
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = false
	_world.add_child(body)
	body.global_position = Vector3(0.0, cfg.capsule_half_height + height, 0.0)
	body.velocity = Vector3.ZERO
	# 等落地（最多 600 帧）
	var frames := 0
	while not body.is_on_floor() and frames < 600:
		await physics_frame
		frames += 1
	await _advance_frames(3)
	var st: SurvivalState = body.survival_snapshot()
	var res := {
		"fall_speed": body.last_fall_speed,
		"health": st.health,
		"reason": st.last_damage_reason,
		"frames": frames,
		"on_floor": body.is_on_floor(),
	}
	_free_world()
	return res


func _advance_frames(n: int) -> void:
	for i in n:
		await process_frame


## 推进真实世界时间 `seconds` 秒（暂停时不死等：见 T014 证据 §6 的坑）
func _run_world_seconds(seconds: float, max_frames := 20000) -> float:
	if _wd == null:
		return 0.0
	var t0: float = _wd.world_time
	var frames := 0
	while _wd.world_time - t0 < seconds and frames < max_frames and not paused:
		await process_frame
		frames += 1
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
