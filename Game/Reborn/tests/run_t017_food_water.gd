extends SceneTree
## T017 食物、饮水与可取消交互 断言
##
## 覆盖（`Docs/Tasks/T017.md` §6；数值全部来自 `Docs/Parameters.md` 第 75/77 行）：
##   A 参数与接口（食物 1.5 s / 35 / capacity 3 / refill 180；水 2.0 s / 40 / 无限）
##   B 区分物种食物（猫 MEAT / 鼠 SEED；不允许 → food_type）
##   C 成功一次发放收益（扣 1 Unit + 恢复指标一起做）
##   D 全值夹紧（不超上限）
##   E 耗尽不可继续领取（empty）
##   F 取消无收益（不扣不发）
##   G 时长走世界时间；暂停不提交
##   H 受伤中断（hurt）/ 死亡中断（died）
##   I 水点无限（连喝不扣）
##   J 按世界时间恢复：一次结算所有经过周期 + 夹紧 + 重新排期
##   K 失效（expire_at）
##   L 提交前复检（目标失效/移出范围 → 无收益）
##   M 集成（真实身体 + resource_point.tscn + HUD/MOV + 正式场景无调试节点）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t017_food_water.gd' --quit-after 90000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const RP_SCENE := "res://scenes/world/resource_point.tscn"
const ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"

const EPS := 1e-4
const TARGET_RADIUS := 0.05

var _checks := 0
var _fails := 0
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null
var _body: AnimalBody = null


func _initialize() -> void:
	print("TEST|run_t017_food_water|engine=%s" % Engine.get_version_info().string)
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")

	_section_a_params()
	await _section_b_species_filter()
	await _section_c_consume_once()
	await _section_d_clamp()
	await _section_e_empty()
	await _section_f_cancel()
	await _section_g_duration()
	await _section_h_interrupt()
	await _section_i_water_infinite()
	await _section_j_refill()
	await _section_k_expire()
	await _section_l_precommit_recheck()
	await _section_m_integration()

	_finish()


# ---------------------------------------------------------------------------
# A 参数与接口
# ---------------------------------------------------------------------------

func _section_a_params() -> void:
	print("---- A 参数与接口 ----")
	_assert("A_configs_loaded", "2 份配置", "%s / %s" % [_cat != null, _mouse != null],
		_cat != null and _mouse != null)
	var food := ResourcePoint.new()
	_assert("A_food_is_interactable", "是 Interactable 子类", str(food is Interactable), food is Interactable)
	_assert("A_food_layer", "4 (layer 3)", str(food.collision_layer), food.collision_layer == 4)
	_assert("A_food_kind", "food", str(food.kind), food.kind == &"food")
	_assert_near("A_food_duration", 1.5, food.interaction_duration, EPS)
	_assert_near("A_food_nutrition", 35.0, food.nutrition, EPS)
	_assert("A_food_capacity", "3", str(food.capacity), food.capacity == 3)
	_assert("A_food_units_full", "3（初始满量）", str(food.units), food.units == 3)
	_assert_near("A_food_refill_interval", 180.0, food.refill_interval, EPS)
	_assert("A_food_infinite", "false", str(food.infinite), not food.infinite)
	_assert("A_food_no_expire", "0", "%.1f" % food.expire_at, food.expire_at == 0.0)
	_assert("A_food_food_type_default", "0 (MEAT)", str(food.food_type), food.food_type == SpeciesConfig.FoodType.MEAT)
	food.free()

	var water := ResourcePoint.new()
	water.kind = &"water"
	_assert("A_water_kind", "water", str(water.kind), water.kind == &"water")
	_assert_near("A_water_duration", 2.0, water.interaction_duration, EPS)
	_assert_near("A_water_nutrition", 40.0, water.nutrition, EPS)
	_assert("A_water_infinite", "true", str(water.infinite), water.infinite)
	water.free()

	# ResourceRecord 形状（`TechnicalDesign.md` §3）
	var rp := ResourcePoint.new()
	rp.interaction_id = "food_seed_1"
	var rec := rp.to_record()
	for key in ["id", "region_id", "kind", "food_type", "units", "capacity",
			"next_refill_at", "refill_interval", "transform", "expire_at"]:
		_assert("A_record_has_%s" % key, "有字段", str(rec.has(key)), rec.has(key))
	_assert("A_record_id", "food_seed_1", str(rec.get("id", "")), String(rec.get("id", "")) == "food_seed_1")
	rp.free()

	# 场景存在（TechnicalDesign §1 指定 T017 建）
	_assert("A_rp_scene_exists", "存在", RP_SCENE, ResourceLoader.exists(RP_SCENE))


# ---------------------------------------------------------------------------
# B 区分物种食物
# ---------------------------------------------------------------------------

func _section_b_species_filter() -> void:
	print("---- B 区分物种食物 ----")
	# 鼠吃种子
	await _fresh(_mouse)
	var seed_point := await _add_resource("seed", 0.30, {"kind": "food", "food_type": SpeciesConfig.FoodType.SEED})
	_assert("B_mouse_seed_allowed", "有目标", _id(), _id() == "seed")
	var q: Dictionary = _body.interaction.current_query()
	_assert("B_mouse_seed_query_allowed", "allowed=true", str(q.get("allowed", false)),
		bool(q.get("allowed", false)))
	seed_point.queue_free()

	# 鼠对肉被拒
	_fresh_world_clear()
	await _add_resource("meat", 0.30, {"kind": "food", "food_type": SpeciesConfig.FoodType.MEAT})
	_assert("B_mouse_meat_denied", "无目标", "-", _body.interaction.detect() == null)
	_assert("B_mouse_meat_reason", "food_type", str(_body.interaction.last_deny_reason()),
		_body.interaction.last_deny_reason() == &"food_type")

	# 猫吃肉；对种子被拒
	await _fresh(_cat)
	await _add_resource("meat", 0.80, {"kind": "food", "food_type": SpeciesConfig.FoodType.MEAT})
	_assert("B_cat_meat_allowed", "meat", _id(), _id() == "meat")
	_fresh_world_clear()
	await _add_resource("seed", 0.80, {"kind": "food", "food_type": SpeciesConfig.FoodType.SEED})
	_assert("B_cat_seed_denied", "无目标", "-", _body.interaction.detect() == null)
	_assert("B_cat_seed_reason", "food_type", str(_body.interaction.last_deny_reason()),
		_body.interaction.last_deny_reason() == &"food_type")

	# 水点不区分物种
	_fresh_world_clear()
	await _add_resource("water", 0.80, {"kind": "water"})
	_assert("B_cat_water_allowed", "water", _id(), _id() == "water")
	await _fresh(_mouse)
	await _add_resource("water", 0.30, {"kind": "water"})
	_assert("B_mouse_water_allowed", "water", _id(), _id() == "water")


# ---------------------------------------------------------------------------
# C 成功一次发放收益
# ---------------------------------------------------------------------------

func _section_c_consume_once() -> void:
	print("---- C 成功一次发放收益 ----")
	await _fresh(_mouse)
	var rp := await _add_resource("seed", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 0.0, "units": 3})
	_set_hunger(50.0)
	# GDScript 的 lambda **按值捕获**局部变量：计数必须放在数组里才改得动
	var consumed := [0]
	rp.consumed.connect(func(_tx: String, _who: Node, _left: int) -> void: consumed[0] += 1)

	var res := _body.interaction.try_interact()
	_assert("C_success", "true", str(res.get("success", false)), bool(res.get("success", false)))
	_assert_near("C_hunger_plus_35", 85.0, _body.survival.state.hunger, EPS)
	_assert("C_units_3_to_2", "2", str(rp.units), rp.units == 2)
	_assert("C_consumed_signal_once", "1", str(consumed[0]), consumed[0] == 1)
	_assert("C_commit_count", "1", str(rp.commit_count()), rp.commit_count() == 1)

	# 再来一次：再扣 1、再 +35（夹紧到 100 → 实测 100）
	var res2 := _body.interaction.try_interact()
	_assert("C_second_success", "true", str(res2.get("success", false)), bool(res2.get("success", false)))
	_assert("C_units_2_to_1", "1", str(rp.units), rp.units == 1)
	_assert("C_consumed_signal_twice", "2", str(consumed[0]), consumed[0] == 2)
	_assert_near("C_hunger_clamped_100", 100.0, _body.survival.state.hunger, EPS)


# ---------------------------------------------------------------------------
# D 夹紧
# ---------------------------------------------------------------------------

func _section_d_clamp() -> void:
	print("---- D 全值夹紧 ----")
	await _fresh(_mouse)
	var rp := await _add_resource("seed", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 0.0, "units": 3})
	_set_hunger(90.0)
	var res := _body.interaction.try_interact()
	_assert("D_success", "true", str(res.get("success", false)), bool(res.get("success", false)))
	_assert_near("D_hunger_exactly_100", 100.0, _body.survival.state.hunger, EPS)
	_assert("D_units_still_decremented", "2（资源照扣）", str(rp.units), rp.units == 2)


# ---------------------------------------------------------------------------
# E 耗尽不可继续领取
# ---------------------------------------------------------------------------

func _section_e_empty() -> void:
	print("---- E 耗尽不可继续领取 ----")
	await _fresh(_mouse)
	var rp := await _add_resource("seed", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 0.0, "units": 1})
	_set_hunger(30.0)
	var res := _body.interaction.try_interact()
	_assert("E_first_success", "true", str(res.get("success", false)), bool(res.get("success", false)))
	_assert("E_units_zero", "0", str(rp.units), rp.units == 0)
	_assert("E_is_empty", "true", str(rp.is_empty()), rp.is_empty())
	var h_after: float = _body.survival.state.hunger
	# 第二次：目标不在候选里
	_assert("E_no_target_when_empty", "无目标", "-", _body.interaction.detect() == null)
	_assert("E_empty_reason", "empty", str(_body.interaction.last_deny_reason()),
		_body.interaction.last_deny_reason() == &"empty")
	var res2 := _body.interaction.try_interact()
	_assert("E_second_fails", "success=false", str(res2.get("success", true)), not bool(res2.get("success", true)))
	_assert_near("E_hunger_unchanged", h_after, _body.survival.state.hunger, EPS)
	_assert("E_commit_count_still_one", "1", str(rp.commit_count()), rp.commit_count() == 1)


# ---------------------------------------------------------------------------
# F 取消无收益
# ---------------------------------------------------------------------------

func _section_f_cancel() -> void:
	print("---- F 取消无收益 ----")
	await _fresh(_mouse)
	var rp := await _add_resource("seed", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 1.5, "units": 3})
	_set_hunger(40.0)
	var det := _body.interaction
	det.detect()
	var ok := det.press_interact()
	_assert("F_started", "true", str(ok), ok)
	_assert("F_is_interacting", "true", str(det.is_interacting()), det.is_interacting())
	det.tick(det.interaction_start_time() + 0.5)
	_assert("F_half_progress", "0.33", "%.2f" % det.interaction_progress(),
		absf(det.interaction_progress() - (0.5 / 1.5)) < 0.02)
	var released := det.release_interact(&"released")
	_assert("F_release_reported", "true", str(released), released)
	_assert("F_cancel_called_once", "1", str(rp.cancel_call_count()), rp.cancel_call_count() == 1)
	_assert("F_no_units_lost", "3", str(rp.units), rp.units == 3)
	_assert_near("F_no_hunger_gain", 40.0, _body.survival.state.hunger, EPS)
	_assert("F_no_commit", "0", str(rp.commit_count()), rp.commit_count() == 0)
	_assert("F_not_interacting", "false", str(det.is_interacting()), not det.is_interacting())


# ---------------------------------------------------------------------------
# G 时长走世界时间
# ---------------------------------------------------------------------------

func _section_g_duration() -> void:
	print("---- G 时长走世界时间 ----")
	await _fresh(_mouse)
	var rp := await _add_resource("seed", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 1.5, "units": 3})
	_set_hunger(40.0)
	var det := _body.interaction
	det.detect()
	var ok := det.press_interact()
	var t0 := det.interaction_start_time()
	_assert("G_started", "true", str(ok), ok)
	det.tick(t0 + 1.4)
	_assert("G_not_committed_at_1_4", "0", str(rp.commit_count()), rp.commit_count() == 0)
	_assert("G_still_interacting", "true", str(det.is_interacting()), det.is_interacting())
	det.tick(t0 + 1.6)
	_assert("G_committed_at_1_6", "1", str(rp.commit_count()), rp.commit_count() == 1)
	_assert("G_not_interacting_after", "false", str(det.is_interacting()), not det.is_interacting())
	_assert_near("G_hunger_after", 75.0, _body.survival.state.hunger, EPS)

	# 暂停：世界时间不前进 → 不提交
	_fresh_world_clear()
	var rp2 := await _add_resource("seed2", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 1.5, "units": 3})
	det.detect()
	det.press_interact()
	if _wd != null:
		_wd.time_advancing = false
	var moved := await _run_world_seconds(0.3, 200)
	if _wd != null:
		_wd.time_advancing = true
	_assert("G_paused_world_time_frozen", "0.0000", "%.4f" % moved, moved < EPS)
	_assert("G_paused_not_committed", "0", str(rp2.commit_count()), rp2.commit_count() == 0)
	det.release_interact(&"test_cleanup")


# ---------------------------------------------------------------------------
# H 受伤 / 死亡中断
# ---------------------------------------------------------------------------

func _section_h_interrupt() -> void:
	print("---- H 受伤与死亡中断 ----")
	await _fresh(_mouse)
	var rp := await _add_resource("seed", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 1.5, "units": 3})
	_set_hunger(40.0)
	var det := _body.interaction
	det.detect()
	det.press_interact()
	det.tick(det.interaction_start_time() + 0.5)
	_assert("H_interacting_before_hit", "true", str(det.is_interacting()), det.is_interacting())
	# 掉血 → 自动取消（Parameters.md 第 75 行：受伤中断交互）
	_body.survival.apply_damage(5.0, &"test_hit")
	_assert("H_interrupted_by_damage", "false", str(det.is_interacting()), not det.is_interacting())
	_assert("H_cancel_called", "1", str(rp.cancel_call_count()), rp.cancel_call_count() == 1)
	_assert("H_no_units_lost", "3", str(rp.units), rp.units == 3)
	_assert_near("H_no_hunger_gain", 40.0, _body.survival.state.hunger, EPS)
	_assert("H_no_commit", "0", str(rp.commit_count()), rp.commit_count() == 0)
	_assert_near("H_health_reduced", 95.0, _body.survival.state.health, EPS)


# ---------------------------------------------------------------------------
# I 水点无限
# ---------------------------------------------------------------------------

func _section_i_water_infinite() -> void:
	print("---- I 水点无限 ----")
	await _fresh(_mouse)
	var rp := await _add_resource("water", 0.30, {"kind": "water", "duration": 0.0})
	_assert("I_water_infinite", "true", str(rp.infinite), rp.infinite)
	_set_thirst(10.0)
	var res := _body.interaction.try_interact()
	_assert("I_first_drink", "true", str(res.get("success", false)), bool(res.get("success", false)))
	_assert_near("I_thirst_plus_40", 50.0, _body.survival.state.thirst, EPS)
	_assert("I_units_unused", "0", str(rp.units), rp.units == 0)
	_set_thirst(10.0)
	_body.interaction.try_interact()
	_assert_near("I_second_drink", 50.0, _body.survival.state.thirst, EPS)
	_set_thirst(90.0)
	_body.interaction.try_interact()
	_assert_near("I_clamped_100", 100.0, _body.survival.state.thirst, EPS)
	_assert("I_commit_three", "3", str(rp.commit_count()), rp.commit_count() == 3)
	_assert("I_still_available", "water", _id(), _id() == "water")
	_assert("I_health_unchanged", "100.0", "%.1f" % _body.survival.state.health,
		absf(_body.survival.state.health - 100.0) < EPS)
	_assert("I_not_empty", "false", str(rp.is_empty()), not rp.is_empty())


# ---------------------------------------------------------------------------
# J 按世界时间恢复
# ---------------------------------------------------------------------------

func _section_j_refill() -> void:
	print("---- J 恢复周期 ----")
	await _fresh(_mouse)
	var rp := await _add_resource("seed", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 0.0, "units": 0})
	var t0 := 1000.0
	_assert("J_starts_empty", "0", str(rp.units), rp.units == 0)
	# 第一次推进：排期从"此刻"起算
	rp.advance_to(t0)
	_assert("J_schedules_after_first_advance", "> 0", "%.1f" % rp.next_refill_at, rp.next_refill_at > 0.0)
	_assert_near("J_next_refill_is_t0_plus_180", t0 + 180.0, rp.next_refill_at, 1.0)
	rp.advance_to(t0 + 179.0)
	_assert("J_not_yet_179", "0", str(rp.units), rp.units == 0)
	rp.advance_to(t0 + 181.0)
	_assert("J_refill_1_at_181", "1", str(rp.units), rp.units == 1)
	# 一次推进跨 3 个周期：必须**全部结算**（不能只恢复一次）
	rp.advance_to(t0 + 181.0 + 540.0)
	_assert("J_multi_period_all_settled", "3", str(rp.units), rp.units == 3)
	_assert("J_capacity_clamped", "3", str(rp.units), rp.units == rp.capacity)
	_assert("J_unscheduled_when_full", "0", "%.1f" % rp.next_refill_at, rp.next_refill_at == 0.0)
	# 消耗一个后重新排期
	_set_hunger(20.0)
	_body.interaction.try_interact()
	_assert("J_consumed_one", "2", str(rp.units), rp.units == 2)
	rp.advance_to(t0 + 1000.0)
	_assert("J_rescheduled_when_not_full", "> 0", "%.1f" % rp.next_refill_at, rp.next_refill_at > 0.0)
	rp.advance_to(t0 + 1000.0 + 181.0)
	_assert("J_refill_after_reschedule", "3", str(rp.units), rp.units == 3)
	# 暂停时世界时间不前 → 不恢复（用真实时间验证）
	if _wd != null:
		_wd.time_advancing = false
	var moved := await _run_world_seconds(0.3, 200)
	if _wd != null:
		_wd.time_advancing = true
	_assert("J_paused_no_refill", "0.0000", "%.4f" % moved, moved < EPS)
	_assert("J_units_unchanged_paused", "3", str(rp.units), rp.units == 3)


# ---------------------------------------------------------------------------
# K 失效
# ---------------------------------------------------------------------------

func _section_k_expire() -> void:
	print("---- K 失效 ----")
	await _fresh(_mouse)
	var rp := await _add_resource("carrion", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 0.0, "units": 1, "capacity": 1})
	rp.expire_at = 500.0
	# GDScript 的 lambda **按值捕获**局部变量：计数必须放在数组里才改得动
	var expired := [0]
	rp.expired.connect(func(_t: float) -> void: expired[0] += 1)
	rp.advance_to(499.0)
	_assert("K_alive_before_expiry", "1", str(rp.units), rp.units == 1)
	_assert("K_not_expired_before", "false", str(rp.is_expired(499.0)), not rp.is_expired(499.0))
	_assert("K_visible_before", "carrion", _id(), _id() == "carrion")
	rp.advance_to(501.0)
	_assert("K_units_zero_after_expiry", "0", str(rp.units), rp.units == 0)
	_assert("K_is_expired", "true", str(rp.is_expired(501.0)), rp.is_expired(501.0))
	_assert("K_expired_signal_once", "1", str(expired[0]), expired[0] == 1)
	rp.advance_to(600.0)
	_assert("K_expired_signal_not_repeated", "1", str(expired[0]), expired[0] == 1)
	_assert("K_no_target_when_expired", "无目标", "-", _body.interaction.detect() == null)


# ---------------------------------------------------------------------------
# L 提交前复检
# ---------------------------------------------------------------------------

func _section_l_precommit_recheck() -> void:
	print("---- L 提交前复检 ----")
	# 1) 交互中目标被禁用
	await _fresh(_mouse)
	var rp := await _add_resource("seed", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 0.3, "units": 3})
	_set_hunger(40.0)
	var det := _body.interaction
	det.detect()
	det.press_interact()
	det.tick(det.interaction_start_time() + 0.4)
	_assert("L_committed_when_valid", "1", str(rp.commit_count()), rp.commit_count() == 1)

	# 2) 交互中目标被禁用 → 提交失败、无收益
	_fresh_world_clear()
	var rp2 := await _add_resource("seed2", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 0.3, "units": 3})
	_set_hunger(40.0)
	det.detect()
	det.press_interact()
	rp2.enabled = false
	await _advance_frames(2)
	det.tick(det.interaction_start_time() + 0.4)
	_assert("L_disabled_not_committed", "0", str(rp2.commit_count()), rp2.commit_count() == 0)
	_assert("L_no_hunger_gain_when_disabled", "40.0", "%.1f" % _body.survival.state.hunger,
		absf(_body.survival.state.hunger - 40.0) < EPS)
	_assert("L_units_kept_when_disabled", "3", str(rp2.units), rp2.units == 3)
	rp2.enabled = true

	# 3) 交互中目标被移出范围 → 提交失败、无收益
	_fresh_world_clear()
	var rp3 := await _add_resource("seed3", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 0.3, "units": 3})
	_set_hunger(40.0)
	det.detect()
	det.press_interact()
	rp3.position = Vector3(0.0, rp3.position.y, rp3.position.z - 3.0)   # 移到 3 m 外
	await _advance_frames(3)
	det.tick(det.interaction_start_time() + 0.4)
	_assert("L_out_of_range_not_committed", "0", str(rp3.commit_count()), rp3.commit_count() == 0)
	_assert("L_no_hunger_gain_out_of_range", "40.0", "%.1f" % _body.survival.state.hunger,
		absf(_body.survival.state.hunger - 40.0) < EPS)
	_assert("L_units_kept_out_of_range", "3", str(rp3.units), rp3.units == 3)


# ---------------------------------------------------------------------------
# M 集成
# ---------------------------------------------------------------------------

func _section_m_integration() -> void:
	print("---- M 集成 ----")
	await _fresh(_mouse)
	var rp := await _add_resource_from_scene("scene_seed", 0.30,
		{"kind": "food", "food_type": SpeciesConfig.FoodType.SEED, "duration": 0.0, "units": 3})
	_assert("M_scene_instance_loaded", "非 null", str(rp != null), rp != null)
	if rp == null:
		return
	_set_hunger(40.0)
	var res := _body.interaction.try_interact()
	_assert("M_scene_consume_success", "true", str(res.get("success", false)), bool(res.get("success", false)))
	_assert_near("M_hunger_after_scene_food", 75.0, _body.survival.state.hunger, EPS)
	_assert("M_in_group", "在 resource_points 组", str(rp.is_in_group(&"resource_points")),
		rp.is_in_group(&"resource_points"))

	if ResourceLoader.exists(ENTRY):
		var entry: Node = (load(ENTRY) as PackedScene).instantiate()
		root.add_child(entry)
		await _advance_frames(6)
		if entry.has_method("switch_species"):
			entry.call("switch_species", &"Mouse")
			await _advance_frames(6)
		var hud := String(entry.call("hud_text")) if entry.has_method("hud_text") else ""
		var mov := String(entry.call("mov_line")) if entry.has_method("mov_line") else ""
		_assert("M_hud_has_resource_line", "含 'resource:'", _clip(hud), hud.contains("resource:"))
		_assert("M_mov_has_food_field", "含 'food='", _clip(mov), mov.contains("food="))
		_assert("M_mov_has_water_field", "含 'water='", _clip(mov), mov.contains("water="))
		entry.queue_free()
		await _advance_frames(2)
	else:
		_assert("M_entry_exists", "存在", "缺失", false)

	for path in [MAIN, LEVEL]:
		var scene := (load(path) as PackedScene).instantiate()
		root.add_child(scene)
		await _advance_frames(4)
		var debug_nodes := 0
		for n in _all_nodes(scene):
			if n.get_script() != null:
				var sp := String((n.get_script() as Script).resource_path)
				if sp.contains("/debug/"):
					debug_nodes += 1
		_assert("M_no_debug_node_%s" % path.get_file(), "0", str(debug_nodes), debug_nodes == 0)
		scene.queue_free()
		await _advance_frames(2)


# ---------------------------------------------------------------------------
# 夹具与辅助
# ---------------------------------------------------------------------------

func _set_hunger(value: float) -> void:
	# `restore_hunger` 只加不设，所以直接改状态；**同时对齐 tick**，避免期间按时间掉值干扰断言
	_body.survival.state.hunger = value
	_body.survival.tick_to(_body.world_time_now())


func _set_thirst(value: float) -> void:
	_body.survival.state.thirst = value
	_body.survival.tick_to(_body.world_time_now())


func _new_flat_world() -> void:
	_free_world()
	_world = Node3D.new()
	_world.name = "T017World"
	root.add_child(_world)
	await _advance_frames(2)
	var sb := StaticBody3D.new()
	sb.name = "T017Ground"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	cs.shape = box
	sb.add_child(cs)
	sb.position = Vector3(0.0, -0.5, 0.0)
	_world.add_child(sb)
	await _advance_frames(2)


func _fresh(cfg: SpeciesConfig) -> AnimalBody:
	await _new_flat_world()
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = false
	body.position = Vector3(0.0, cfg.capsule_half_height + 0.01, 0.0)
	body.velocity = Vector3.ZERO
	_world.add_child(body)
	await _advance_frames(8)
	_body = body
	return body


func _fresh_world_clear() -> void:
	if _world == null:
		return
	for c in _world.get_children():
		if c == _body or c is AnimalBody or c is Camera3D:
			continue
		if c is Area3D or c is StaticBody3D and String(c.name).begins_with("T017Wall"):
			c.queue_free()
	await _advance_frames(3)


func _free_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		_world = null
	_body = null


func _eye() -> Vector3:
	if _body == null:
		return Vector3.ZERO
	var cam = _body.get("camera")
	if cam != null and cam is Camera3D:
		return (cam as Camera3D).global_position
	return _body.global_position


## 运行期建资源点：**先设位置再入树**（T016 实测坑：入树后再设 global_position 会让物理体在原点存在一帧）
func _add_resource(id: String, dist: float, opts: Dictionary = {}) -> ResourcePoint:
	var rp := ResourcePoint.new()
	_configure_resource(rp, id, dist, opts)
	_world.add_child(rp)
	# 恢复排期改由测试用**假时间**显式驱动：`_ready` 会用真实世界时间排期，会干扰假时间断言
	rp.auto_advance = false
	rp.next_refill_at = 0.0
	await _advance_frames(3)
	return rp


func _add_resource_from_scene(id: String, dist: float, opts: Dictionary = {}) -> ResourcePoint:
	var rp := (load(RP_SCENE) as PackedScene).instantiate() as ResourcePoint
	if rp == null:
		return null
	_configure_resource(rp, id, dist, opts)
	_world.add_child(rp)
	rp.auto_advance = false
	rp.next_refill_at = 0.0
	await _advance_frames(3)
	return rp


func _configure_resource(rp: ResourcePoint, id: String, dist: float, opts: Dictionary) -> void:
	# 顺序：先 kind（会套用该类型默认值），再显式覆盖测试要改的字段
	if opts.has("kind"):
		rp.kind = StringName(opts["kind"])
	rp.interaction_id = id
	if opts.has("food_type"):
		rp.food_type = int(opts["food_type"])
	if opts.has("units"):
		rp.units = int(opts["units"])
	if opts.has("capacity"):
		rp.capacity = int(opts["capacity"])
	if opts.has("duration"):
		rp.interaction_duration = float(opts["duration"])
	if not opts.has("duration") and rp.kind == &"food":
		rp.interaction_duration = 1.5
	if not rp.has_node("CollisionShape3D"):
		var cs := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = TARGET_RADIUS
		cs.shape = sphere
		rp.add_child(cs)
	var eye := _eye()
	rp.position = Vector3(0.0, eye.y, eye.z - dist)


func _id() -> String:
	if _body == null or _body.interaction == null:
		return ""
	var n := _body.interaction.detect()
	if n == null:
		return ""
	return _body.interaction.target_id_of(n)


func _clip(s: String) -> String:
	return s.replace("\n", " | ").substr(0, 90)


func _advance_frames(n: int) -> void:
	for i in n:
		await physics_frame


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
