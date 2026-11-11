extends SceneTree
## T058：**安全休息与快进**（开发计划 :250；真源 `Docs/Parameters.md:81`）
##
## 验收词：「追逐中拒绝，资源不足提前提示；时间、生存消耗、资源与种群恢复一致」。
##
## 判据：
##  A. 判定契约：`evaluate()` 纯观察、理由齐全（no_player/not_advancing/dead/busy/in_danger/
##     insufficient_resources）、常量与真源一致；
##  B. 正常休息：世界时间 **+60.000 s**、Health **+10**（夹紧）、Hunger/Thirst 按 `rate×60` 扣；
##  C. **一致性**：同一夹具下"自然推进 60 s"与"休息快进 60 s"的生存 / 资源 / 种群结果**逐项相同**
##     （证明快进没有走另一套账）；
##  D. **拒绝零副作用**：追逐/警戒、资源不足时，世界时间与全部账本**一字不变**；
##  E. 资源与种群**结算所有经过周期**并夹紧容量、`next_*` 前移到未来；
##  F. 交互接入：`RestPoint` 的 action/duration/幂等/拒绝理由与 `evaluate()` 同源；
##  G. 无状态昼夜：休息跨过昼夜边界后，采样就是新时间的纯函数值；
##  H. 暂停/门闩下拒绝。
##
## 运行：
##   & '<godot_gui.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t058_rest.gd' --quit-after 60000
## 结果口径：`RESULT|pass=<n>|fail=<n>|failed=...`

const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CAT_CFG := "res://resources/species/cat.tres"
const RESOURCE_SCENE := "res://scenes/world/resource_point.tscn"
const REST_POINT_SCENE := "res://scenes/world/rest_point.tscn"
const DAY_NIGHT := preload("res://scripts/systems/day_night.gd")

const T0 := 300.0

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _rd: Node = null
var _wd: Node = null
var _cfg: SpeciesConfig = null
var _bodies: Array[Node] = []
var _points: Array[Node] = []


func _initialize() -> void:
	await process_frame
	_rd = root.get_node_or_null("/root/RestDirector")
	_wd = root.get_node_or_null("/root/WorldDirector")
	_cfg = load(CAT_CFG) as SpeciesConfig
	if not _assert("A0_autoloads", "RestDirector + WorldDirector + 猫配置",
			"%s/%s/%s" % [_rd != null, _wd != null, _cfg != null],
			_rd != null and _wd != null and _cfg != null):
		_finish()
		return
	_check_constants()
	await _check_evaluate()
	await _check_rest_math()
	await _check_consistency()
	await _check_refusals()
	await _check_cycles()
	await _check_rest_point()
	_check_day_night_phase()
	_check_paused()
	await _check_main_entry_rest_point()
	_finish()


# ---------------- I：真实入口挂载（集成） ----------------

## 最后才跑：实例化 `main.tscn`，确认正式入口真的把休息点挂进关卡（不是只有场景文件）。
## 放在最后，避免它铺出来的生态影响上面的判定用例。
func _check_main_entry_rest_point() -> void:
	var packed := load("res://scenes/core/main.tscn") as PackedScene
	if not _assert("I_main_scene", "main.tscn 可加载", str(packed != null), packed != null):
		return
	var main := packed.instantiate()
	if main == null:
		_assert("I_main_scene", "可实例化", "null", false)
		return
	main.set("test_mode", true)
	root.add_child(main)
	for i in 8:
		await process_frame
	var level_node := main.get_node_or_null("Level")
	var point: Node = level_node.get_node_or_null("RestPoint") if level_node != null else null
	_assert("I_rest_point_mounted", "Level/RestPoint 存在", str(point != null), point != null)
	if point != null:
		var gpos: Vector3 = (point as Node3D).global_position
		_assert("I_rest_point_position", "(-8.000, 0.100, 27.300)",
			"(%.3f, %.3f, %.3f)" % [gpos.x, gpos.y, gpos.z],
			gpos.distance_to(Vector3(-8.0, 0.10, 27.3)) <= 0.001)
		_assert("I_rest_point_action", "rest", str(point.call("_action_id")),
			StringName(point.call("_action_id")) == &"rest")
	main.queue_free()
	await process_frame


# ---------------- A：常量与判定契约 ----------------

func _check_constants() -> void:
	_assert("A_rest_seconds", "60.0（Parameters:81）", "%.1f" % float(_rd.get("REST_SECONDS")),
		absf(float(_rd.get("REST_SECONDS")) - 60.0) <= 1e-9)
	_assert("A_rest_gain", "10.0（Parameters:81）", "%.1f" % float(_rd.get("REST_HEALTH_GAIN")),
		absf(float(_rd.get("REST_HEALTH_GAIN")) - 10.0) <= 1e-9)
	_assert("A_danger_radius", "> 0 且 ≤ 视距 9 m", "%.1f" % float(_rd.get("DANGER_RADIUS")),
		float(_rd.get("DANGER_RADIUS")) > 0.0 and float(_rd.get("DANGER_RADIUS")) <= 9.0)


func _check_evaluate() -> void:
	_wd.call("set_world_time", T0)
	var p := _make_body(true)
	await physics_frame
	var ev: Dictionary = _rd.call("evaluate", p)
	_assert("A_eval_ok", "ok=true / reason=ok", "%s / %s" % [ev["ok"], ev["reason"]],
		bool(ev["ok"]) and StringName(ev["reason"]) == &"ok")

	var none: Dictionary = _rd.call("evaluate", null)
	_assert("A_eval_no_player", "reason=no_player", str(none["reason"]),
		StringName(none["reason"]) == &"no_player")

	_wd.set("time_advancing", false)
	var gated: Dictionary = _rd.call("evaluate", p)
	_wd.set("time_advancing", true)
	_assert("A_eval_not_advancing", "reason=not_advancing", str(gated["reason"]),
		StringName(gated["reason"]) == &"not_advancing")

	var dead := _make_body(true)
	await physics_frame
	dead.survival.apply_damage(500.0, &"test")
	var dead_ev: Dictionary = _rd.call("evaluate", dead)
	_assert("A_eval_dead", "reason=dead", str(dead_ev["reason"]),
		StringName(dead_ev["reason"]) == &"dead")

	var busy := _make_body(true)
	await physics_frame
	# 「纯观察」的判定：从这一行起**不再 await**，所以世界时间与四项指标都不许变
	var snap := _eval_snapshot(p)
	busy.set("_pouncing", true)
	var busy_ev: Dictionary = _rd.call("evaluate", busy)
	busy.set("_pouncing", false)
	_rd.call("evaluate", p)
	_rd.call("evaluate", dead)
	_assert("A_eval_busy", "reason=busy（扑击期不许休息）", str(busy_ev["reason"]),
		StringName(busy_ev["reason"]) == &"busy")
	_assert("A_eval_no_side_effect", "零变化（时间 + 玩家四项）", "%s vs %s" % [snap, _eval_snapshot(p)],
		snap == _eval_snapshot(p))


# ---------------- B：正常休息的数学 ----------------

func _check_rest_math() -> void:
	_wd.call("set_world_time", T0)
	var p := _make_body(true)
	await physics_frame
	p.survival.state.hunger = 50.0
	p.survival.state.thirst = 50.0
	p.survival.state.health = 90.0
	# 世界时间在 `await physics_frame` 期间会按真实 delta 前进，所以一律用"调用前快照"做基准
	p.survival.set("last_world_time", float(_wd.get("world_time")))
	var t_before := float(_wd.get("world_time"))
	var before_count: int = int(_rd.get("rest_count"))
	var res: Dictionary = _rd.call("rest", p)
	_assert("B_ok", "ok=true", "%s / %s" % [res.get("ok"), res.get("reason")],
		bool(res.get("ok", false)))
	_assert("B_time_plus_60", "before + 60.0", "%.6f → %.6f" % [t_before, float(res.get("world_time_after"))],
		absf(float(res.get("world_time_after")) - t_before - 60.0) <= 1e-9)
	_assert("B_world_time_written", "世界时间 = world_time_after", "%.6f / %.6f" % [
		float(_wd.get("world_time")), float(res.get("world_time_after"))],
		absf(float(_wd.get("world_time")) - float(res.get("world_time_after"))) <= 1e-9)
	_assert("B_health_clamped", "100.0（90+10 夹紧）", "%.4f" % float(res.get("health_after")),
		absf(float(res.get("health_after")) - 100.0) <= 1e-6)
	var exp_hunger := 50.0 - _cfg.hunger_loss_per_sec * 60.0
	var exp_thirst := 50.0 - _cfg.thirst_loss_per_sec * 60.0
	_assert("B_hunger_rate", "%.4f（rate×60）" % exp_hunger, "%.4f" % float(res.get("hunger_after")),
		absf(float(res.get("hunger_after")) - exp_hunger) <= 1e-5)
	_assert("B_thirst_rate", "%.4f（rate×60）" % exp_thirst, "%.4f" % float(res.get("thirst_after")),
		absf(float(res.get("thirst_after")) - exp_thirst) <= 1e-5)
	_assert("B_count_incremented", "%d" % (before_count + 1), "%d" % int(_rd.get("rest_count")),
		int(_rd.get("rest_count")) == before_count + 1)
	_assert("B_no_double_settle_next_frame", "下一物理帧不再扣（tick_to 幂等）",
		"%.4f" % float(p.survival.state.hunger),
		await _no_double_settle(p, float(res.get("hunger_after"))))

	# 低血量也照实 +10（不夹在 100 之外的地方）
	_wd.call("set_world_time", T0)
	var low := _make_body(true)
	await physics_frame
	low.survival.state.health = 60.0
	low.survival.set("last_world_time", T0)
	var low_res: Dictionary = _rd.call("rest", low)
	_assert("B_health_plus_10_low", "70.0", "%.4f" % float(low_res.get("health_after")),
		absf(float(low_res.get("health_after")) - 70.0) <= 1e-6)


func _no_double_settle(body: AnimalBody, expected_hunger: float) -> bool:
	await physics_frame
	await physics_frame
	return absf(body.survival.state.hunger - expected_hunger) <= 1e-5


# ---------------- C：一致性（自然推进 vs 快进） ----------------

func _check_consistency() -> void:
	# 生存
	_wd.call("set_world_time", T0)
	var natural := _make_body(true)
	var rested := _make_body(true)
	await physics_frame
	for b in [natural, rested]:
		b.survival.state.hunger = 70.0
		b.survival.state.thirst = 70.0
		b.survival.state.health = 70.0
		b.survival.set("last_world_time", T0)
	natural.survival.tick_to(T0 + 60.0)          # "自然推进 60 s"（与休息同一条 tick_to 路径）
	natural.survival.restore_health(10.0)        # 与 D6 顺序一致：先扣后加
	var rest_res: Dictionary = _rd.call("rest", rested)
	var same := absf(natural.survival.state.hunger - float(rest_res["hunger_after"])) <= 1e-6 \
		and absf(natural.survival.state.thirst - float(rest_res["thirst_after"])) <= 1e-6 \
		and absf(natural.survival.state.health - float(rest_res["health_after"])) <= 1e-6
	_assert("C_survival_equal", "自然=快进（hunger/thirst/health）",
		"natural=(%.4f,%.4f,%.4f) rest=(%.4f,%.4f,%.4f)" % [
			natural.survival.state.hunger, natural.survival.state.thirst, natural.survival.state.health,
			float(rest_res["hunger_after"]), float(rest_res["thirst_after"]),
			float(rest_res["health_after"])], same)

	# 资源点
	_wd.call("set_world_time", T0)
	var rp_nat := _make_resource_point(T0, 0, 3, 20.0)
	var rp_rest := _make_resource_point(T0, 0, 3, 20.0)
	await physics_frame
	rp_nat.advance_to(T0 + 60.0)
	_rd.call("rest", rested)
	var rp_same := rp_nat.units == rp_rest.units \
		and absf(rp_nat.next_refill_at - rp_rest.next_refill_at) <= 1e-6
	_assert("C_resource_equal", "自然=快进（units / next_refill_at）",
		"natural=(%d,%.2f) rest=(%d,%.2f)" % [rp_nat.units, rp_nat.next_refill_at,
			rp_rest.units, rp_rest.next_refill_at], rp_same)

	# 种群
	_wd.call("set_world_time", T0)
	var key := "T058Region|Mouse"
	var make_rec := func(total: int) -> Dictionary:
		return {"region_id": &"T058Region", "species_id": &"Mouse", "total_count": total,
			"capacity": 4, "recover_interval": 30.0, "next_recover_at": T0 + 30.0}
	_wd.set("region_records", {key: make_rec.call(1)})
	_wd.call("region_population_advance_to", T0 + 60.0)      # 自然推进
	var nat_total := int((_wd.get("region_records") as Dictionary)[key]["total_count"])
	var nat_next := float((_wd.get("region_records") as Dictionary)[key]["next_recover_at"])
	_wd.set("region_records", {key: make_rec.call(1)})
	_rd.call("rest", rested)                                  # 快进
	var rest_total := int((_wd.get("region_records") as Dictionary)[key]["total_count"])
	var rest_next := float((_wd.get("region_records") as Dictionary)[key]["next_recover_at"])
	_assert("C_population_equal", "自然=快进（total / next_recover_at）",
		"natural=(%d,%.2f) rest=(%d,%.2f)" % [nat_total, nat_next, rest_total, rest_next],
		nat_total == rest_total and absf(nat_next - rest_next) <= 1e-6)
	_wd.set("region_records", {})


# ---------------- D：拒绝零副作用 ----------------

func _check_refusals() -> void:
	var refused_reasons: Array[String] = []
	_rd.connect("rest_refused", func(reason: StringName, _d: Dictionary) -> void:
		refused_reasons.append(String(reason)))

	# 资源不足：hunger 只剩 2 → 预测 ≤0
	_wd.call("set_world_time", T0)
	var p := _make_body(true)
	await physics_frame
	p.survival.state.hunger = 2.0
	p.survival.state.thirst = 80.0
	p.survival.state.health = 80.0
	p.survival.set("last_world_time", T0)
	var rp := _make_resource_point(T0, 1, 3, 30.0)
	await physics_frame
	var snap_before := _snapshot(p, rp)
	var ev: Dictionary = _rd.call("evaluate", p)
	_assert("D_insufficient_reason", "reason=insufficient_resources", str(ev["reason"]),
		StringName(ev["reason"]) == &"insufficient_resources")
	var pred: Dictionary = ev.get("predicted", {})
	_assert("D_insufficient_predicted", "predicted.hunger ≤ 0", "%.3f" % float(pred.get("hunger", 9.0)),
		float(pred.get("hunger", 9.0)) <= 0.0)
	var res: Dictionary = _rd.call("rest", p)
	_assert("D_insufficient_refused", "ok=false", str(res.get("ok")), not bool(res.get("ok", true)))
	_assert("D_insufficient_no_side_effect", "零变化", "%s vs %s" % [snap_before, _snapshot(p, rp)],
		snap_before == _snapshot(p, rp))

	# 警戒/追逐：放一只 2 m 内的猫 NPC 并把它推进 ALERT
	_wd.call("set_world_time", T0)
	var prey := _make_body(true)
	await physics_frame
	prey.global_position = Vector3(0.0, 0.5, 0.0)
	prey.survival.state.hunger = 90.0
	prey.survival.state.thirst = 90.0
	prey.survival.state.health = 90.0
	prey.survival.set("last_world_time", T0)
	var npc := _make_body(false, true)
	await physics_frame
	npc.global_position = Vector3(2.0, 0.5, 0.0)
	npc.ai.call("alert_for", prey.global_position, &"t058_test")
	var snap_prey := _snapshot(prey, null)
	var danger_ev: Dictionary = _rd.call("evaluate", prey)
	_assert("D_in_danger_reason", "reason=in_danger（2 m / alert）", "%s / %s" % [
		danger_ev["reason"], danger_ev.get("danger", {})],
		StringName(danger_ev["reason"]) == &"in_danger")
	_assert("D_in_danger_distance", "danger.distance ≈ 2.0",
		"%.3f" % float((danger_ev.get("danger", {}) as Dictionary).get("distance", -1.0)),
		absf(float((danger_ev.get("danger", {}) as Dictionary).get("distance", -1.0)) - 2.0) <= 0.05)
	var danger_res: Dictionary = _rd.call("rest", prey)
	_assert("D_in_danger_refused", "ok=false", str(danger_res.get("ok")),
		not bool(danger_res.get("ok", true)))
	_assert("D_in_danger_no_side_effect", "零变化", "%s vs %s" % [snap_prey, _snapshot(prey, null)],
		snap_prey == _snapshot(prey, null))

	# 同一状态但 NPC 在危险半径外（20 m）→ 允许
	npc.global_position = Vector3(20.0, 0.5, 0.0)
	npc.ai.call("alert_for", prey.global_position, &"t058_test")
	var far_ev: Dictionary = _rd.call("evaluate", prey)
	_assert("D_far_npc_ok", "ok=true（20 m > 危险半径）", "%s / danger=%s" % [
		far_ev["ok"], far_ev.get("danger", {})], bool(far_ev["ok"]))

	_assert("D_refused_signal", "rest_refused 至少 2 次", str(refused_reasons),
		refused_reasons.size() >= 2 and refused_reasons.has("insufficient_resources")
		and refused_reasons.has("in_danger"))


func _snapshot(body: AnimalBody, rp: Node) -> String:
	var st = body.survival.state
	return "t=%.6f|h=%.6f|th=%.6f|hp=%.6f|rp=%d|n=%.3f" % [
		float(_wd.get("world_time")), st.hunger, st.thirst, st.health,
		int(rp.units) if rp != null else -1,
		float(rp.next_refill_at) if rp != null else -1.0]


## 「纯观察」快照：世界时间 + 玩家四项（`evaluate()` 前后必须逐字相同）
func _eval_snapshot(body: AnimalBody) -> String:
	var st = body.survival.state
	return "t=%.6f|h=%.6f|th=%.6f|hp=%.6f|sp=%.6f|act=%d" % [
		float(_wd.get("world_time")), st.hunger, st.thirst, st.health, st.stamina,
		int(body.action_state())]


# ---------------- E：资源与种群的周期结算 ----------------

func _check_cycles() -> void:
	_wd.call("set_world_time", T0)
	var p := _make_body(true)
	await physics_frame
	p.survival.state.hunger = 90.0
	p.survival.state.thirst = 90.0
	p.survival.set("last_world_time", T0)
	# 30 s 一个周期、60 s 内 2 次、容量 3 → 2
	var rp := _make_resource_point(T0, 0, 3, 30.0)
	await physics_frame
	var r1: Dictionary = _rd.call("rest", p)
	_assert("E_multi_cycle", "units=2（60 s / 30 s）", "%d" % rp.units, rp.units == 2)
	_assert("E_next_in_future", "next_refill_at > world_time",
		"next=%.2f t=%.2f" % [rp.next_refill_at, float(r1["world_time_after"])],
		rp.next_refill_at > float(r1["world_time_after"]))
	_assert("E_points_settled_reported", "resource_points_settled ≥ 1",
		"%d" % int(r1.get("resource_points_settled", 0)),
		int(r1.get("resource_points_settled", 0)) >= 1)

	# 容量夹紧：2/3 起、10 s 周期 → 60 s 内到 3 就停，next 清零
	var rp2 := _make_resource_point(T0, 2, 3, 10.0)
	await physics_frame
	_rd.call("rest", p)
	_assert("E_capacity_clamp", "units=3 且 next=0", "%d / %.2f" % [rp2.units, rp2.next_refill_at],
		rp2.units == 3 and absf(rp2.next_refill_at) <= 1e-9)


# ---------------- F：休息点交互接入 ----------------

func _check_rest_point() -> void:
	var packed := load(REST_POINT_SCENE) as PackedScene
	if not _assert("F_point_scene", "rest_point.tscn 可加载", str(packed != null), packed != null):
		return
	var point := packed.instantiate() as RestPoint
	root.add_child(point)
	_points.append(point)
	await process_frame
	_assert("F_point_action", "rest", String(point.call("_action_id")),
		StringName(point.call("_action_id")) == &"rest")
	_assert("F_point_duration", "%.1f" % float(point.get("interaction_duration")),
		"%.1f（1.0）" % float(point.get("interaction_duration")),
		absf(float(point.get("interaction_duration")) - 1.0) <= 1e-9)
	_assert("F_point_id", "稳定 ID", point.interaction_id,
		point.interaction_id == "rest_shelter_courtyard_01")

	# 幂等：同一事务第二次提交不再结算（世界时间只 +60 一次）
	_wd.call("set_world_time", T0)
	var p := _make_body(true)
	await physics_frame
	p.survival.state.hunger = 90.0
	p.survival.state.thirst = 90.0
	p.survival.set("last_world_time", float(_wd.get("world_time")))
	# 口径：世界时间在 `await physics_frame` 期间会按真实 delta 前进（`WorldDirector._process`），
	# 所以幂等与拒绝都要**和调用前的快照比**，不能跟常量 `T0` 比。
	var t_before := float(_wd.get("world_time"))
	var first: Dictionary = point.commit_interaction(p, "t058_tx_1")
	var after_first := float(_wd.get("world_time"))
	var second: Dictionary = point.commit_interaction(p, "t058_tx_1")
	var after_second := float(_wd.get("world_time"))
	_assert("F_point_commit_ok", "success=true", str(first.get("success")), bool(first.get("success", false)))
	_assert("F_point_idempotent", "第一次 +60、第二次不再 +60（同一 %.1f）" % after_first,
		"before=%.6f first=%.6f second=%.6f" % [t_before, after_first, after_second],
		absf(after_first - t_before - 60.0) <= 1e-6 and absf(after_second - after_first) <= 1e-9)
	_assert("F_point_commit_count", "commit_count=1", "%d" % point.commit_count(),
		point.commit_count() == 1)
	_assert("F_point_tx_idempotent_result", "第二次返回缓存成功", str(second.get("success")),
		bool(second.get("success", false)))

	# 拒绝理由与 evaluate() 同源
	_wd.call("set_world_time", T0)
	var low := _make_body(true)
	await physics_frame
	low.survival.state.hunger = 1.0
	low.survival.set("last_world_time", float(_wd.get("world_time")))
	var deny := StringName(point.deny_reason_for(low))
	_assert("F_point_deny_mirrors_evaluate", "insufficient_resources", str(deny),
		deny == &"insufficient_resources")
	var t_before_refuse := float(_wd.get("world_time"))
	var refused: Dictionary = point.commit_interaction(low, "t058_tx_2")
	var t_after_refuse := float(_wd.get("world_time"))
	_assert("F_point_refuse_no_settle", "success=false 且世界时间不变",
		"%s / %.6f -> %.6f" % [refused.get("success"), t_before_refuse, t_after_refuse],
		not bool(refused.get("success", true)) and absf(t_after_refuse - t_before_refuse) <= 1e-9)


# ---------------- G：跨越昼夜边界后的采样 ----------------

func _check_day_night_phase() -> void:
	var dn := root.get_node_or_null("/root/DayNightDirector")
	if not _assert("G_daynight_present", "DayNightDirector", str(dn != null), dn != null):
		return
	_wd.call("set_world_time", 580.0)
	var before: Dictionary = DAY_NIGHT.sample(580.0, 1200.0)
	var after_time := 580.0 + 60.0
	var expect: Dictionary = DAY_NIGHT.sample(after_time, 1200.0)
	var actual: Dictionary = dn.call("sample_at", after_time)
	var keys := ["elevation_deg", "energy", "ambient", "phase"]
	var same := true
	for k in keys:
		if absf(float(expect[k]) - float(actual[k])) > 1e-9:
			same = false
	_assert("G_phase_after_rest", "采样 = 新时间的纯函数值（跨昼夜边界）",
		"before.is_day=%s after.is_day=%s" % [before["is_day"], expect["is_day"]],
		same and bool(before["is_day"]) and not bool(expect["is_day"]))


# ---------------- H：暂停 / 门闩 ----------------

func _check_paused() -> void:
	var p := _make_body(true)
	await process_frame
	paused = true
	var ev: Dictionary = _rd.call("evaluate", p)
	paused = false
	_assert("H_paused_refused", "reason=not_advancing（树暂停）", str(ev["reason"]),
		StringName(ev["reason"]) == &"not_advancing")


# ---------------- 夹具 ----------------

func _make_body(as_player: bool, with_ai: bool = false) -> AnimalBody:
	var packed := load(BODY_SCENE) as PackedScene
	var body := packed.instantiate() as AnimalBody
	body.name = ("T058P%d" % _bodies.size()) if as_player else ("T058N%d" % _bodies.size())
	body.species_config = _cfg
	body.player_controlled = false
	body.make_camera_current = false
	body.ai_enabled = with_ai
	root.add_child(body)
	_bodies.append(body)
	if with_ai and body.ai == null:
		push_warning("T058: NPC 未拿到 AI（species_config.ai_script）")
	return body


func _make_resource_point(at_time: float, units: int, capacity: int, interval: float) -> ResourcePoint:
	var packed := load(RESOURCE_SCENE) as PackedScene
	var rp := packed.instantiate() as ResourcePoint
	rp.name = "T058RP%d" % _points.size()
	rp.auto_advance = false
	rp.capacity = capacity
	rp.units = units
	rp.refill_interval = interval
	rp.next_refill_at = at_time + interval if units < capacity else 0.0
	root.add_child(rp)
	_points.append(rp)
	return rp


# ---------------- 工具 ----------------

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
