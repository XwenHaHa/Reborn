extends SceneTree
## T016 交互检测与动作接口 断言
##
## 覆盖（`Docs/Tasks/T016.md` §6）：
##   A 参数与接口落地（三方法/鸭子类型/layer 3）
##   B 距离：配置范围（猫 1.00 / 鼠 0.45）+ `range_override` + 竖直差计入
##   C 遮挡：只认 `world_static`（interactable/safe_spot 层不挡）
##   D 优先级：priority 降序 → 距离升序 → ID 字典序
##   E 物种允许：`allowed_species` 过滤与 `deny_reason=species`
##   F 只显示一个：单一 `current_target` + `target_changed` 事件
##   G 只执行一个：进行中再请求被拒 `busy`，另一目标账本为 0
##   H 时长走**世界时间**：未到不提交、到点提交一次、暂停不前进、duration=0 立即
##   I 取消无收益：调 `cancel_interaction` 且不提交
##   J 事务幂等：同 `transaction_id` 第二次返回既有结果、**不再调用目标**
##   K 鸭子类型：非 `Interactable` 子类可参与；缺方法的节点被跳过
##   L 集成：真实 `animal_body.tscn` 走通 + 调试 HUD 只显示一个交互 + 正式场景无调试节点
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t016_interaction.gd' --quit-after 60000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"

const EPS := 1e-4
## 目标默认交互点（与眼睛同高，避免竖直差干扰距离断言）
const TARGET_RADIUS := 0.05

var _checks := 0
var _fails := 0
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null
var _body: AnimalBody = null


# ---------------------------------------------------------------------------
# 鸭子类型夹具（K 段）
# ---------------------------------------------------------------------------

## **不继承 `Interactable`** 的合法目标：只要实现三个方法就能参与
class DuckTarget extends Area3D:
	var t_id := "DuckTarget"
	var commit_calls := 0
	var commits := 0
	var cancels := 0
	var denials := 0

	func _init() -> void:
		collision_layer = 4
		collision_mask = 0

	func query_interaction(interactor: Node) -> Dictionary:
		return {"allowed": true, "action_id": &"duck", "duration": 0.0, "deny_reason": &""}

	func commit_interaction(interactor: Node, transaction_id: String) -> Dictionary:
		commit_calls += 1
		if commits > 0:
			denials += 1
			return {"success": false, "reason": &"already"}
		commits += 1
		return {"success": true, "reason": &"duck_ok"}

	func cancel_interaction(transaction_id: String) -> void:
		cancels += 1


## 只有 `query_interaction` 的节点：必须被**跳过**，不能让检测崩
class PartialTarget extends Area3D:
	func _init() -> void:
		collision_layer = 4
		collision_mask = 0

	func query_interaction(interactor: Node) -> Dictionary:
		return {"allowed": true, "action_id": &"partial", "duration": 0.0, "deny_reason": &""}


func _initialize() -> void:
	print("TEST|run_t016_interaction|engine=%s" % Engine.get_version_info().string)
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")

	_section_a_params()
	await _section_b_distance()
	await _section_c_occlusion()
	await _section_d_priority()
	await _section_e_species()
	await _section_f_single_display()
	await _section_g_single_action()
	await _section_h_duration()
	await _section_i_cancel()
	await _section_j_idempotent()
	await _section_k_duck_typing()
	await _section_l_integration()

	_finish()


# ---------------------------------------------------------------------------
# A 参数与接口落地
# ---------------------------------------------------------------------------

func _section_a_params() -> void:
	print("---- A 参数与接口落地 ----")
	_assert("A_configs_loaded", "2 份配置", "%s / %s" % [_cat != null, _mouse != null],
		_cat != null and _mouse != null)
	if _cat == null or _mouse == null:
		return
	_assert_near("A_cat_interaction_range", 1.0, _cat.interaction_range, EPS)
	_assert_near("A_mouse_interaction_range", 0.45, _mouse.interaction_range, EPS)
	_assert("A_cat_range_gt_mouse", "猫 > 鼠", "%.2f / %.2f" % [_cat.interaction_range, _mouse.interaction_range],
		_cat.interaction_range > _mouse.interaction_range)

	# 基类三方法（鸭子类型的判定依据）
	var base := Interactable.new()
	_assert("A_interactable_query", "has_method=true", str(base.has_method("query_interaction")),
		base.has_method("query_interaction"))
	_assert("A_interactable_commit", "has_method=true", str(base.has_method("commit_interaction")),
		base.has_method("commit_interaction"))
	_assert("A_interactable_cancel", "has_method=true", str(base.has_method("cancel_interaction")),
		base.has_method("cancel_interaction"))
	_assert("A_interactable_is_area3d", "Area3D", base.get_class(), base is Area3D)
	# 层：必须在 interactable（layer 3 → bit 2 → 值 4）
	_assert("A_interactable_layer", "4 (layer 3)", str(base.collision_layer), base.collision_layer == 4)
	_assert("A_interactable_mask", "0（不主动撞任何东西）", str(base.collision_mask), base.collision_mask == 0)
	# 自检：借用的 not 触发不了；这里检查 detector 与目标层的常量一致
	_assert("A_detector_interactable_layer", "3", str(InteractionDetector.LAYER_INTERACTABLE),
		InteractionDetector.LAYER_INTERACTABLE == 3)
	_assert("A_detector_world_layer", "1", str(InteractionDetector.LAYER_WORLD_STATIC),
		InteractionDetector.LAYER_WORLD_STATIC == 1)
	base.free()


# ---------------------------------------------------------------------------
# B 距离
# ---------------------------------------------------------------------------

func _section_b_distance() -> void:
	print("---- B 距离（配置范围 + range_override + 竖直差）----")
	await _fresh(_cat)
	_assert("B_detector_built", "非 null", str(_body.interaction != null), _body.interaction != null)
	if _body.interaction == null:
		return
	_assert_near("B_cat_effective_range_no_target", 1.0, _body.interaction.effective_range(), EPS)
	_assert_near("B_probe_radius_has_margin", 1.5, _body.interaction.probe_radius(), EPS)

	await _add_target("near_cat", 0.98)
	_assert("B_cat_098_visible", "有目标", _id(), _body.interaction.detect() != null)
	_fresh_world_clear()

	await _add_target("far_cat", 1.02)
	_assert("B_cat_102_hidden", "无目标", "-", _body.interaction.detect() == null)
	_assert("B_cat_102_reason", "range", str(_body.interaction.last_deny_reason()),
		_body.interaction.last_deny_reason() == &"range")

	# 竖直差计入（D3）：水平 0.98 但高 0.5 → 距离 1.10 > 1.00
	await _add_target("high_cat", 0.98, {"dy": 0.5})
	_assert("B_cat_vertical_counts", "无目标（3D 距离 1.10）", "-", _body.interaction.detect() == null)

	# 鼠：0.45
	await _fresh(_mouse)
	await _add_target("near_mouse", 0.44)
	_assert("B_mouse_044_visible", "有目标", _id(), _body.interaction.detect() != null)
	_fresh_world_clear()
	await _add_target("far_mouse", 0.47)
	_assert("B_mouse_047_hidden", "无目标", "-", _body.interaction.detect() == null)

	# 同一距离下猫可用、鼠不可用（范围来自配置）
	await _fresh(_cat)
	await _add_target("same_dist", 0.80)
	_assert("B_cat_080_visible", "有目标", _id(), _body.interaction.detect() != null)
	await _fresh(_mouse)
	await _add_target("same_dist", 0.80)
	_assert("B_mouse_080_hidden", "无目标", "-", _body.interaction.detect() == null)

	# range_override 放大：鼠配置 0.45，目标给 0.90
	await _add_target("big_range", 0.80, {"range_override": 0.90})
	_assert("B_mouse_override_visible", "有目标（override 0.90）", _id(), _id() != "")
	_assert_near("B_override_effective_range", 0.90, _body.interaction.effective_range(), EPS)

	# range_override 缩小：猫配置 1.00，目标只给 0.50
	await _fresh(_cat)
	await _add_target("small_range", 0.80, {"range_override": 0.50})
	_assert("B_cat_override_hidden", "无目标（override 0.50）", "-", _body.interaction.detect() == null)


# ---------------------------------------------------------------------------
# C 遮挡
# ---------------------------------------------------------------------------

func _section_c_occlusion() -> void:
	print("---- C 遮挡（只认 world_static）----")
	await _fresh(_cat)
	await _add_target("occl", 0.90)
	_assert("C_visible_before_wall", "有目标", _id(), _body.interaction.detect() != null)
	_fresh_world_clear()

	await _add_target("occl", 0.90)
	var wall := await _add_wall(1, 0.45)
	_assert("C_world_wall_blocks", "无目标", "-", _body.interaction.detect() == null)
	_assert("C_world_wall_reason", "occluded", str(_body.interaction.last_deny_reason()),
		_body.interaction.last_deny_reason() == &"occluded")
	wall.collision_layer = 4   # 改成 interactable 层
	await _advance_frames(2)
	_assert("C_interactable_layer_not_blocking", "有目标", _id(), _body.interaction.detect() != null)
	wall.collision_layer = 8   # safe_spot 层
	await _advance_frames(2)
	_assert("C_safe_spot_layer_not_blocking", "有目标", _id(), _body.interaction.detect() != null)
	wall.collision_layer = 1
	await _advance_frames(2)
	_assert("C_world_again_blocks", "无目标", "-", _body.interaction.detect() == null)
	wall.visible = false       # 视觉不可见 ≠ 物理不挡（不参与判定的证明）
	await _advance_frames(2)
	_assert("C_visibility_irrelevant", "无目标（仍挡）", "-", _body.interaction.detect() == null)
	_fresh_world_clear()

	# 墙移开 → 恢复
	await _add_target("occl2", 0.90)
	_assert("C_after_wall_removed", "有目标", _id(), _body.interaction.detect() != null)


# ---------------------------------------------------------------------------
# D 优先级
# ---------------------------------------------------------------------------

func _section_d_priority() -> void:
	print("---- D 优先级 ----")
	await _fresh(_cat)
	# 高 priority 更远也要赢
	await _add_target("low_near", 0.30, {"priority": 0})
	await _add_target("high_far", 0.90, {"priority": 5})
	var picked := _body.interaction.detect()
	_assert("D_priority_beats_distance", "high_far", _id(picked), _id(picked) == "high_far")
	_assert("D_candidates_two", "2", str(_body.interaction.candidates().size()),
		_body.interaction.candidates().size() == 2)

	# 同 priority → 近的赢
	_fresh_world_clear()
	await _add_target("p_near_a", 0.30, {"priority": 3})
	await _add_target("p_far_b", 0.90, {"priority": 3})
	_assert("D_same_priority_nearer", "p_near_a", _id(), _id() == "p_near_a")

	# 同 priority + 同距离 → ID 字典序（alpha < beta）
	_fresh_world_clear()
	await _add_target("beta", 0.50, {"priority": 1})
	await _add_target("alpha", 0.50, {"priority": 1})
	_assert("D_tie_break_by_id", "alpha", _id(), _id() == "alpha")

	# 排序与加入顺序无关（先加 alpha 再加 beta，结果仍 alpha）
	_fresh_world_clear()
	await _add_target("alpha", 0.50, {"priority": 1})
	await _add_target("beta", 0.50, {"priority": 1})
	_assert("D_order_independent", "alpha", _id(), _id() == "alpha")


# ---------------------------------------------------------------------------
# E 物种允许
# ---------------------------------------------------------------------------

func _section_e_species() -> void:
	print("---- E 物种允许 ----")
	await _fresh(_mouse)
	await _add_target("mouse_only", 0.30, {"allowed_species": [&"Mouse"]})
	var q: Dictionary = _body.interaction.current_query()
	_assert("E_mouse_allowed_listed", "allowed=true", str(q.get("allowed", false)),
		bool(q.get("allowed", false)))
	_assert("E_mouse_picked", "mouse_only", _id(), _id() == "mouse_only")

	await _fresh(_cat)
	await _add_target("mouse_only", 0.90, {"allowed_species": [&"Mouse"]})
	_assert("E_cat_rejected_species", "无目标", "-", _body.interaction.detect() == null)
	_assert("E_cat_reason_species", "species", str(_body.interaction.last_deny_reason()),
		_body.interaction.last_deny_reason() == &"species")

	# 空列表 = 不限物种
	_fresh_world_clear()
	await _add_target("free_for_all", 0.90)
	_assert("E_empty_list_allows_cat", "free_for_all", _id(), _id() == "free_for_all")
	_fresh_world_clear()
	await _add_target("cat_only", 0.90, {"allowed_species": [&"Cat"]})
	_assert("E_cat_listed_ok", "cat_only", _id(), _id() == "cat_only")

	# 禁用的目标不出现在候选里
	_fresh_world_clear()
	await _add_target("disabled_one", 0.90, {"enabled": false})
	_assert("E_disabled_skipped", "无目标", "-", _body.interaction.detect() == null)
	_assert("E_disabled_reason", "disabled", str(_body.interaction.last_deny_reason()),
		_body.interaction.last_deny_reason() == &"disabled")


# ---------------------------------------------------------------------------
# F 只显示一个
# ---------------------------------------------------------------------------

func _section_f_single_display() -> void:
	print("---- F 只显示一个 ----")
	await _fresh(_cat)
	var events: Array[String] = []
	var det := _body.interaction
	det.target_changed.connect(func(id: String, allowed: bool) -> void:
		events.append("%s:%s" % [id, str(allowed)]))

	await _add_target("t1", 0.90, {"priority": 0})
	await _add_target("t2", 0.90, {"priority": 9})
	det.detect()
	_assert("F_single_target", "t2", _id(), _id() == "t2")
	# 身体每物理帧也会 `detect()`：这里只断言"最后事件 = 当前目标"与"同目标不重复发"
	_assert("F_last_event_is_target", "t2:true", str(events[-1]), events[-1] == "t2:true")
	_assert("F_events_no_dup_t2", "t2 恰好一次", str(events), events.count("t2:true") == 1)
	var before := events.size()
	det.detect()
	det.detect()
	det.detect()
	_assert("F_no_repeat_event", "不变", "%d → %d" % [before, events.size()], events.size() == before)
	# 高优先级目标被移走 → 换目标 + 一次新事件
	var t2 := _find_target("t2")
	t2.enabled = false
	await _advance_frames(2)
	det.detect()
	_assert("F_switch_after_disable", "t1", _id(), _id() == "t1")
	_assert("F_last_event_t1", "t1:true", str(events[-1]), events[-1] == "t1:true")
	var before2 := events.size()
	det.detect()
	det.detect()
	_assert("F_no_repeat_after_switch", "不变", "%d → %d" % [before2, events.size()], events.size() == before2)
	# 全部不可用 → 空目标事件（只发一次）
	_find_target("t1").enabled = false
	await _advance_frames(2)
	det.detect()
	_assert("F_target_id_empty", "", _id(), _id() == "")
	_assert("F_none_event", ":false", str(events[-1]), events[-1] == ":false")
	var before3 := events.size()
	det.detect()
	_assert("F_none_event_once", "不变", "%d → %d" % [before3, events.size()], events.size() == before3)


# ---------------------------------------------------------------------------
# G 只执行一个
# ---------------------------------------------------------------------------

func _section_g_single_action() -> void:
	print("---- G 只执行一个 ----")
	await _fresh(_cat)
	var slow := await _add_target("slow", 0.50, {"duration": 0.30, "priority": 1})
	var fast := await _add_target("fast", 0.50, {"duration": 0.0, "priority": 9})
	var det := _body.interaction
	_assert("G_fast_picked", "fast", _id(), _id() == "fast")

	# 先手动切到 slow（用 press 参数指定目标不方便，直接压低 fast 的优先级）
	fast.enabled = false
	await _advance_frames(2)
	det.detect()
	_assert("G_slow_picked", "slow", _id(), _id() == "slow")
	var started := det.press_interact()
	_assert("G_press_started", "true", str(started), started)
	_assert("G_is_interacting", "true", str(det.is_interacting()), det.is_interacting())
	_assert("G_locked_target", "slow", _id(), _id() == "slow")
	# 进行中再请求 → busy，且第二个目标账本仍 0
	var second := det.try_interact()
	_assert("G_second_rejected", "success=false", str(second.get("success", true)),
		not bool(second.get("success", true)))
	_assert("G_second_reason_busy", "busy", str(second.get("reason", &"")),
		String(second.get("reason", &"")) == "busy")
	_assert("G_slow_not_committed_yet", "0", str(slow.commit_count()), slow.commit_count() == 0)
	_assert("G_fast_not_committed", "0", str(fast.commit_count()), fast.commit_count() == 0)
	_assert("G_rejects_counted", "1", str(det.stats()["rejects"]), int(det.stats()["rejects"]) == 1)
	det.release_interact(&"test_cleanup")


# ---------------------------------------------------------------------------
# H 时长走世界时间
# ---------------------------------------------------------------------------

func _section_h_duration() -> void:
	print("---- H 时长（世界时间；暂停不前进）----")
	await _fresh(_cat)
	var slow := await _add_target("timed", 0.50, {"duration": 0.5})
	var det := _body.interaction
	det.detect()
	var ok := det.press_interact()
	var t0 := det.interaction_start_time()
	_assert("H_started", "true", str(ok), ok)
	# 合成时间推进（tick 是纯函数式的：只看传入的世界时间）
	det.tick(t0 + 0.4)
	_assert("H_progress_04", "0.80", "%.2f" % det.interaction_progress(), absf(det.interaction_progress() - 0.8) < 0.02)
	_assert("H_not_committed_at_04", "0", str(slow.commit_count()), slow.commit_count() == 0)
	_assert("H_still_interacting", "true", str(det.is_interacting()), det.is_interacting())
	det.tick(t0 + 0.6)
	_assert("H_committed_after_duration", "1", str(slow.commit_count()), slow.commit_count() == 1)
	_assert("H_not_interacting_after", "false", str(det.is_interacting()), not det.is_interacting())
	_assert("H_progress_reset", "0.00", "%.2f" % det.interaction_progress(), det.interaction_progress() == 0.0)

	# 暂停：真实世界时间不前进 → 进度不前进
	_fresh_world_clear()
	var timed2 := await _add_target("timed2", 0.50, {"duration": 5.0})
	det.detect()
	det.press_interact()
	# 用**真实**世界时间推进 0.2 s（不合成 tick，避免与真实帧混用）
	var live := await _run_world_seconds(0.2)
	var p_before := det.interaction_progress()
	_assert("H_live_progress_advanced", "> 0", "%.4f" % p_before, p_before > 0.0)
	_assert("H_live_elapsed_reported", ">= 0.2", "%.4f" % live, live >= 0.2 - EPS)
	if _wd != null:
		_wd.time_advancing = false
	var moved := await _run_world_seconds(0.3, 200)
	if _wd != null:
		_wd.time_advancing = true
	_assert("H_paused_world_time_frozen", "0.0000", "%.4f" % moved, moved < EPS)
	_assert("H_paused_progress_frozen", "%.4f" % p_before, "%.4f" % det.interaction_progress(),
		absf(det.interaction_progress() - p_before) < EPS)
	_assert("H_paused_not_committed", "0", str(timed2.commit_count()), timed2.commit_count() == 0)
	det.release_interact(&"test_cleanup")

	# duration == 0：按下即提交
	_fresh_world_clear()
	var instant := await _add_target("instant", 0.50, {"duration": 0.0})
	det.detect()
	var res := det.try_interact()
	_assert("H_instant_success", "true", str(res.get("success", false)), bool(res.get("success", false)))
	_assert("H_instant_committed", "1", str(instant.commit_count()), instant.commit_count() == 1)
	_assert("H_instant_not_interacting", "false", str(det.is_interacting()), not det.is_interacting())


# ---------------------------------------------------------------------------
# I 取消无收益
# ---------------------------------------------------------------------------

func _section_i_cancel() -> void:
	print("---- I 取消无收益 ----")
	await _fresh(_cat)
	var slow := await _add_target("cancellable", 0.50, {"duration": 1.0})
	var det := _body.interaction
	det.detect()
	det.press_interact()
	det.tick(_body.world_time_now() + 0.2)
	_assert("I_in_progress", "true", str(det.is_interacting()), det.is_interacting())
	var released := det.release_interact(&"released")
	_assert("I_release_reported", "true", str(released), released)
	_assert("I_cancel_called", "1", str(slow.cancel_call_count()), slow.cancel_call_count() == 1)
	_assert("I_no_commit", "0", str(slow.commit_count()), slow.commit_count() == 0)
	_assert("I_state_idle", "false", str(det.is_interacting()), not det.is_interacting())
	_assert("I_cancels_counted", "1", str(det.stats()["cancels"]), int(det.stats()["cancels"]) == 1)
	# 取消后可以重新开始（新事务 ID，不再重复取消）
	det.press_interact()
	_assert("I_restart_ok", "true", str(det.is_interacting()), det.is_interacting())
	_assert("I_restart_new_tx", "不同 ID", "%s / %s" % [det.active_transaction_id(), ""],
		det.active_transaction_id() != "")
	det.release_interact(&"test_cleanup")
	_assert("I_cancel_called_twice", "2", str(slow.cancel_call_count()), slow.cancel_call_count() == 2)
	# 取消不能改变既有成功账本
	_assert("I_commit_still_zero", "0", str(slow.commit_count()), slow.commit_count() == 0)


# ---------------------------------------------------------------------------
# J 事务幂等
# ---------------------------------------------------------------------------

func _section_j_idempotent() -> void:
	print("---- J 事务幂等 ----")
	await _fresh(_cat)
	var t := await _add_target("tx_target", 0.50, {"duration": 0.0})
	var det := _body.interaction
	det.detect()
	var first := det.try_interact("tx_fixed")
	_assert("J_first_success", "true", str(first.get("success", false)), bool(first.get("success", false)))
	var second := det.try_interact("tx_fixed")
	_assert("J_second_success_same", "true", str(second.get("success", false)), bool(second.get("success", false)))
	_assert("J_commit_count_once", "1", str(t.commit_count()), t.commit_count() == 1)
	_assert("J_target_called_once", "1", str(t.commit_call_count()), t.commit_call_count() == 1)
	_assert("J_same_transaction_id", "tx_fixed", str(second.get("transaction_id", "")),
		String(second.get("transaction_id", "")) == "tx_fixed")
	# 直接重复提交同一事务 ID 也不重复调用
	var again := det.commit_transaction("tx_fixed")
	_assert("J_direct_repeat_ok", "true", str(again.get("success", false)), bool(again.get("success", false)))
	_assert("J_target_still_once", "1", str(t.commit_call_count()), t.commit_call_count() == 1)
	# 不同事务 ID → 一个新的成功（目标自己决定是否允许）
	var three := det.try_interact("tx_other")
	_assert("J_new_tx_success", "true", str(three.get("success", false)), bool(three.get("success", false)))
	_assert("J_commit_count_two", "2", str(t.commit_count()), t.commit_count() == 2)


# ---------------------------------------------------------------------------
# K 鸭子类型
# ---------------------------------------------------------------------------

func _section_k_duck_typing() -> void:
	print("---- K 鸭子类型 ----")
	await _fresh(_cat)
	var duck := DuckTarget.new()
	duck.name = "DuckTarget"
	var dcs := CollisionShape3D.new()
	var dsphere := SphereShape3D.new()
	dsphere.radius = 0.05
	dcs.shape = dsphere
	duck.add_child(dcs)
	duck.position = Vector3(0.0, _eye().y, _eye().z - 0.5)
	_world.add_child(duck)
	await _advance_frames(2)
	var det := _body.interaction
	var any_duck: Variant = duck
	_assert("K_duck_not_interactable", "不是 Interactable 子类", str(any_duck is Interactable),
		not (any_duck is Interactable))
	_assert("K_duck_picked", "DuckTarget", _id(), _id() == "DuckTarget")
	var res := det.try_interact("tx_duck")
	_assert("K_duck_committed", "true", str(res.get("success", false)), bool(res.get("success", false)))
	_assert("K_duck_commit_calls", "1", str(duck.commit_calls), duck.commit_calls == 1)
	_assert("K_duck_commit_once", "1", str(duck.commits), duck.commits == 1)

	# 缺方法的节点被跳过，且计入诊断（不崩、不选中）
	var partial := PartialTarget.new()
	partial.name = "PartialTarget"
	var pcs := CollisionShape3D.new()
	var psphere := SphereShape3D.new()
	psphere.radius = 0.05
	pcs.shape = psphere
	partial.add_child(pcs)
	partial.position = Vector3(0.0, _eye().y, _eye().z - 0.2)
	_world.add_child(partial)
	await _advance_frames(2)
	_assert("K_partial_skipped", "DuckTarget", "被选中的是 %s" % _id(), _id() == "DuckTarget")
	_assert("K_skipped_counted", "≥1", str(det.stats()["skipped"]), int(det.stats()["skipped"]) >= 1)
	# 非交互的静态墙（layer 3）也不能被选中
	var body_wall := await _add_wall(4, 0.30)
	_assert("K_plain_static_not_picked", "DuckTarget", "被选中的是 %s" % _id(), _id() == "DuckTarget")
	body_wall.queue_free()


# ---------------------------------------------------------------------------
# L 集成
# ---------------------------------------------------------------------------

func _section_l_integration() -> void:
	print("---- L 集成（真实身体 + 调试入口）----")
	await _fresh(_cat)
	var target := await _add_target("real_target", 0.80, {"duration": 0.0})
	var det := _body.interaction
	det.detect()
	_assert("L_body_has_interaction", "非 null", str(det != null), det != null)
	var st: Dictionary = _body.debug_state()
	_assert("L_debug_state_interaction", "有 interaction 键", str(st.has("interaction")), st.has("interaction"))
	_assert("L_debug_state_target_id", "real_target", str(st.get("interaction_target_id", "")),
		String(st.get("interaction_target_id", "")) == "real_target")
	# 用按键路径（press/release 与 _read_input 同一条代码）
	var pressed := det.press_interact()
	_assert("L_press_key_path", "true", str(pressed), pressed)
	_assert("L_key_commit", "1", str(target.commit_count()), target.commit_count() == 1)

	# 调试入口：HUD 与 MOV 行都出现交互字段（只显示一个）
	if ResourceLoader.exists(ENTRY):
		var entry: Node = (load(ENTRY) as PackedScene).instantiate()
		root.add_child(entry)
		await _advance_frames(6)
		if entry.has_method("switch_species"):
			entry.call("switch_species", &"Cat")
			await _advance_frames(6)
		var hud := String(entry.call("hud_text")) if entry.has_method("hud_text") else ""
		var mov := String(entry.call("mov_line")) if entry.has_method("mov_line") else ""
		_assert("L_hud_has_interact_line", "含 'interact:'", _clip(hud), hud.contains("interact:"))
		_assert("L_mov_has_iact", "含 'iact='", _clip(mov), mov.contains("iact="))
		entry.queue_free()
		await _advance_frames(2)
	else:
		_assert("L_entry_exists", "存在", "缺失", false)

	# 正式场景不含调试节点（沿用 T013 的规则）
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
		_assert("L_no_debug_node_%s" % path.get_file(), "0", str(debug_nodes), debug_nodes == 0)
		scene.queue_free()
		await _advance_frames(2)


# ---------------------------------------------------------------------------
# 夹具与辅助
# ---------------------------------------------------------------------------

func _new_flat_world() -> void:
	_free_world()
	_world = Node3D.new()
	_world.name = "T016World"
	root.add_child(_world)
	await _advance_frames(2)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	cs.shape = box
	sb.add_child(cs)
	sb.name = "T016Ground"
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


## 只清目标/墙，保留身体与地面（同一个检测器实例上做多轮）
func _fresh_world_clear() -> void:
	if _world == null:
		return
	for c in _world.get_children():
		if c == _body or c is AnimalBody or c is Camera3D:
			continue
		if c is Interactable or c is Area3D or String(c.name).begins_with("T016Wall"):
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


func _add_target(id: String, dist: float, opts: Dictionary = {}) -> Interactable:
	var t := Interactable.new()
	t.interaction_id = id
	t.interaction_priority = int(opts.get("priority", 0))
	if opts.has("allowed_species"):
		t.allowed_species.assign(opts["allowed_species"])
	t.interaction_duration = float(opts.get("duration", 0.0))
	t.range_override = float(opts.get("range_override", 0.0))
	t.enabled = bool(opts.get("enabled", true))
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TARGET_RADIUS
	cs.shape = sphere
	t.add_child(cs)
	# **先设位置再加树**：add_child 之后再设 `global_position` 会让物理体在原点存在一帧，
	# 与地面/身体重叠时会被 depenetration 推开（实测把身体推离 0.1877 m，见 Docs/Evidence/T016.md）
	var eye := _eye()
	t.position = Vector3(
		float(opts.get("x", 0.0)), eye.y + float(opts.get("dy", 0.0)), eye.z - dist
	)
	_world.add_child(t)
	await _advance_frames(3)
	return t


func _add_wall(layer: int, dist: float) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.8, 0.06)
	cs.shape = box
	sb.add_child(cs)
	# 同 `_add_target`：位置必须在 add_child **之前**设好
	var eye := _eye()
	sb.name = "T016Wall"
	sb.position = Vector3(0.0, eye.y, eye.z - dist)
	_world.add_child(sb)
	await _advance_frames(3)
	return sb


func _find_target(id: String) -> Interactable:
	for n in _world.get_children():
		if n is Interactable and (n as Interactable).interaction_id == id:
			return n as Interactable
	return null


func _id(node: Node = null) -> String:
	if _body == null or _body.interaction == null:
		return ""
	var det := _body.interaction
	var n := node
	if n == null:
		n = det.detect()
	if n == null:
		return ""
	return det.target_id_of(n)


func _clip(s: String) -> String:
	var one := s.replace("\n", " | ")
	return one.substr(0, 90)


func _advance_frames(n: int) -> void:
	for i in n:
		await physics_frame


## 推进真实世界时间 `seconds` 秒（暂停时不死等）
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
