extends SceneTree
## T034 世界时钟与资源恢复 —— 先写可失败的断言（对应 `Docs/Tasks/T034.md` §6）。
##
## 覆盖：
##   A 昼夜时钟契约（day_length=1200 / 边界对半 / 纯函数 / 防呆）
##   B 门闩冻结与换算（结算/选物种期间 world_time 精确不变；ALIVE 下 1:1 推进）
##   C 重生不重置时间（第二世 start_world_time ≥ 死亡时刻、不跳数小时）
##   D 资源恢复 = 世界时间驱动（多周期一次结算 / 门闩真实等待不恢复 / ALIVE 正对照 /
##     捕获食物失效跟随世界时间）
##   E 存活读数（ALIVE 状态行「第 N 天·白天/夜晚」；快进翻相位/翻天）
##   F T033/T032 契约复证（树序 / 解锁集语义 / 时钟读数不进 hud_text）
##
## 首跑策略：对 WorldDirector 新增 API 一律经 `wd.call()/wd.get()` 调用——
## 未实现时返回 null、断言红，脚本不崩（同 t033 的先红原则）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t034_world_clock.gd' --quit-after 600000
## 结果口径：RESULT|pass=<n>|fail=<n> 全绿；失败时另打 RESULT|failed=<清单>。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const CAT_ID := &"Cat"
const RP_SCRIPT := "res://scripts/world/resource_point.gd"

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _refill_events := 0   # D 段信号计数（lambda 按值捕获局部变量，必须走成员）


func _on_refilled(_units: int, _world_time: float) -> void:
	_refill_events += 1


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("RESULT|fail=1")
		print("RESULT|failed=A0_scene_load")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	root.size = Vector2i(1280, 720)   # add_child 后再设一次（headless 根视口默认 64x64）
	await _advance_frames(2)
	var entry := main as MainEntry
	if entry == null:
		print("RESULT|fail=1")
		print("RESULT|failed=A0_entry_class")
		quit(1)
		return

	await _section_a_clock_contract()
	await _section_b_gate_and_scale(entry)
	await _section_c_rebirth_keeps_time(entry)
	await _section_d_resource_recovery(entry)
	await _section_e_alive_readout(entry)
	_section_f_contract_recheck(entry)

	main.queue_free()
	await _advance_frames(2)
	_summary()
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _wd() -> Node:
	return root.get_node_or_null("/root/WorldDirector")


func _gs() -> Node:
	return root.get_node_or_null("/root/GameState")


func _advance_frames(n: int) -> void:
	for i in n:
		await process_frame


## 等物理帧：`ResourcePoint.auto_advance` 走 `_physics_process`，
## `await process_frame` 不保证物理帧执行（实测会错位导致 flaky）——账本断言一律等物理帧。
func _advance_physics(n: int) -> void:
	for i in n:
		await physics_frame


## 真实毫秒等待（headless 帧推进不等价于真实时间，t033 E 段同法）。
func _wait_real_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _assert(key: String, expected: String, actual: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("PASS|%s" % key)
	else:
		_fail += 1
		_failed.append(key)
		print("FAIL|%s|expected=%s|actual=%s" % [key, expected, actual])


func _summary() -> void:
	print("RESULT|pass=%d|fail=%d" % [_pass, _fail])
	if _fail > 0:
		print("RESULT|failed=%s" % ",".join(_failed))


# ---------------------------------------------------------------------------
# A 昼夜时钟契约
# ---------------------------------------------------------------------------

func _section_a_clock_contract() -> void:
	print("---- A 昼夜时钟契约 ----")
	var wd := _wd()
	_assert("A1_day_length_initial", "1200.0", str(wd.get("day_length")),
		str(wd.get("day_length")) == "1200.0")
	# wt=0：白天起点（真源 Parameters:83）
	wd.call("set_world_time", 0.0)
	_assert("A2_day_index_zero", "0", str(wd.call("day_index")),
		int(wd.call("day_index")) == 0)
	_assert("A3_time_of_day_zero", "0.0", str(wd.call("time_of_day")),
		is_equal_approx(float(wd.call("time_of_day")), 0.0))
	_assert("A4_is_daytime_at_zero", "true", str(wd.call("is_daytime")),
		bool(wd.call("is_daytime")))
	_assert("A5_phase_day", "day", str(wd.call("phase_name")),
		String(wd.call("phase_name")) == "day")
	# 昼夜对半边界（T034 决策：白天 [0,600) / 夜晚 [600,1200)）
	wd.call("set_world_time", 599.99)
	_assert("A6_daytime_before_600", "true", str(wd.call("is_daytime")),
		bool(wd.call("is_daytime")))
	wd.call("set_world_time", 600.0)
	_assert("A7_night_at_600", "false", str(wd.call("is_daytime")),
		not bool(wd.call("is_daytime")))
	_assert("A8_phase_night", "night", str(wd.call("phase_name")),
		String(wd.call("phase_name")) == "night")
	wd.call("set_world_time", 1199.99)
	_assert("A9_night_until_day_end", "night day 0",
		"%s %d" % [wd.call("phase_name"), int(wd.call("day_index"))],
		String(wd.call("phase_name")) == "night" and int(wd.call("day_index")) == 0)
	wd.call("set_world_time", 1200.0)
	_assert("A10_new_day_at_1200", "day day 1",
		"%s %d" % [wd.call("phase_name"), int(wd.call("day_index"))],
		String(wd.call("phase_name")) == "day" and int(wd.call("day_index")) == 1)
	wd.call("set_world_time", 1800.0)
	_assert("A11_night_day_1", "night day 1",
		"%s %d" % [wd.call("phase_name"), int(wd.call("day_index"))],
		String(wd.call("phase_name")) == "night" and int(wd.call("day_index")) == 1)
	# 纯函数：同输入两次结果一致且取值正确（不存平行状态）
	wd.call("set_world_time", 650.0)
	var tod_a := float(wd.call("time_of_day"))
	var tod_b := float(wd.call("time_of_day"))
	_assert("A12_pure_function", "650=650 night day 0",
		"%.2f=%.2f %s %d" % [tod_a, tod_b, wd.call("phase_name"), int(wd.call("day_index"))],
		is_equal_approx(tod_a, 650.0) and is_equal_approx(tod_a, tod_b)
			and String(wd.call("phase_name")) == "night" and int(wd.call("day_index")) == 0)
	# 防呆：负 world_time（直接写，绕过 set_world_time 的钳制）按 0 处理
	wd.set("world_time", -5.0)
	_assert("A13_negative_guard", "0 0.0 day",
		"%d %.2f %s" % [int(wd.call("day_index")), float(wd.call("time_of_day")), wd.call("phase_name")],
		int(wd.call("day_index")) == 0 and is_equal_approx(float(wd.call("time_of_day")), 0.0)
			and String(wd.call("phase_name")) == "day")
	# 防呆：day_length<=0 视为恒白天（恢复默认值，不污染后续段）
	var backup := float(wd.get("day_length"))
	wd.set("day_length", 0.0)
	_assert("A14_bad_day_length_guard", "0 0.0 day true",
		"%d %.2f %s %s" % [int(wd.call("day_index")), float(wd.call("time_of_day")),
			wd.call("phase_name"), wd.call("is_daytime")],
		int(wd.call("day_index")) == 0 and is_equal_approx(float(wd.call("time_of_day")), 0.0)
			and String(wd.call("phase_name")) == "day" and bool(wd.call("is_daytime")))
	wd.set("day_length", backup)
	wd.call("set_world_time", 0.0)


# ---------------------------------------------------------------------------
# B 门闩冻结与换算
# ---------------------------------------------------------------------------

func _section_b_gate_and_scale(entry: MainEntry) -> void:
	print("---- B 门闩冻结与换算 ----")
	var wd := _wd()
	# 出生（正式模式默认解锁 Cat）
	var accepted := entry.select_species(CAT_ID)
	await _advance_frames(4)
	_assert("B1_spawn_alive", "alive", entry.lifecycle_state_name(),
		accepted and entry.lifecycle_state_name() == "alive")
	_assert("B2_time_advancing", "true", str(entry.lifecycle.time_is_advancing()),
		entry.lifecycle.time_is_advancing())
	# ALIVE：真实等待 → world_time 递增（1:1 sim/real 由 T014 证过，这里证出生后时钟在走）
	var wt0 := float(wd.get("world_time"))
	await _wait_real_ms(300)
	var wt1 := float(wd.get("world_time"))
	_assert("B3_time_grows_alive", ">0", str(wt1 - wt0), wt1 > wt0)
	# 死亡 → SETTLING：门闩立即生效，world_time 冻结在死亡时刻
	entry.player.survival.apply_damage(9999.0, &"t034_gate")
	await _advance_frames(2)
	var t_death := float(wd.get("world_time"))
	_assert("B4_death_time_positive", ">0", str(t_death), t_death > 0.0)
	_assert("B5_time_frozen_after_death", "false", str(entry.lifecycle.time_is_advancing()),
		not entry.lifecycle.time_is_advancing())
	# 真实毫秒等待（对照：若门闩失效，300 ms 足够 world_time 漂移）
	await _wait_real_ms(600)
	_assert("B6_time_exactly_frozen", str(t_death), str(wd.get("world_time")),
		is_equal_approx(float(wd.get("world_time")), t_death))
	# 时钟读数在门闩期间不翻转；选物种状态行不含天读数
	_assert("B7_phase_not_flipped", "day", str(wd.call("phase_name")),
		String(wd.call("phase_name")) == "day")
	await _advance_frames(12)   # 让 _on_life_settled → _enter_select 完成
	_assert("B8_selecting_state", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")
	_assert("B9_no_day_readout_in_select", "不含「第」", entry.status_text(),
		not entry.status_text().contains("第"))


# ---------------------------------------------------------------------------
# C 重生不重置时间
# ---------------------------------------------------------------------------

func _section_c_rebirth_keeps_time(entry: MainEntry) -> void:
	print("---- C 重生不重置时间 ----")
	var wd := _wd()
	var t_death := float(wd.get("world_time"))
	entry.dismiss_settle()
	await _advance_frames(2)
	var accepted := entry.select_species(CAT_ID)
	await _advance_frames(4)
	_assert("C1_respawn_alive", "alive", entry.lifecycle_state_name(),
		accepted and entry.lifecycle_state_name() == "alive")
	var cur := _gs().get("current_life") as Dictionary
	var start2 := float(cur.get("start_world_time", -1.0))
	_assert("C2_start_after_death", ">=%s" % str(t_death), str(start2),
		start2 >= t_death)
	# 策划 §10.1「重生不额外跳过数小时或重置白天」：间隔在数秒内
	_assert("C3_no_hours_skipped", "<10", str(start2 - t_death),
		start2 - t_death < 10.0)
	_assert("C4_world_time_continues", ">=%s" % str(t_death), str(wd.get("world_time")),
		float(wd.get("world_time")) >= t_death)
	var wt0 := float(wd.get("world_time"))
	await _wait_real_ms(200)
	_assert("C5_time_grows_after_respawn", ">0", str(float(wd.get("world_time")) - wt0),
		float(wd.get("world_time")) - wt0 > 0.0)


# ---------------------------------------------------------------------------
# D 资源恢复 = 世界时间驱动
# ---------------------------------------------------------------------------

func _section_d_resource_recovery(entry: MainEntry) -> void:
	print("---- D 资源恢复（世界时间驱动） ----")
	var wd := _wd()
	# 关卡内没有预置资源点（正式点位布置属后续任务）——用真实
	# `resource_point.tscn` 实例挂进正式关卡（同 t031/t033 的运行时布置口径）。
	var packed_rp := load("res://scenes/world/resource_point.tscn") as PackedScene
	var rp: Node = null
	if packed_rp != null and entry.level != null:
		rp = packed_rp.instantiate()
		entry.level.add_child(rp)
		await _advance_physics(3)
	_assert("D0_food_point_found", "非 null", str(rp), rp != null)
	if rp == null:
		return
	var capacity := int(rp.get("capacity"))
	# 只改实例（不入库）：恢复周期 1.0 s，方便一次结算观察
	rp.set("refill_interval", 1.0)
	rp.set("next_refill_at", 0.0)
	rp.set("units", capacity)
	_refill_events = 0
	rp.connect("refilled", Callable(self, "_on_refilled"))
	await _advance_physics(3)

	# ① 多周期一次结算：权威快进 +2.5 s → 两次恢复一次到账并夹紧容量
	rp.set("units", 1)
	await _advance_physics(3)   # auto_advance 先排期（next_refill_at = wt + 1.0）
	var scheduled := float(rp.get("next_refill_at"))
	_assert("D1_refill_scheduled", ">wt", str(scheduled),
		scheduled > float(wd.get("world_time")))
	wd.call("set_world_time", scheduled + 2.5)
	await _advance_physics(3)
	_assert("D2_multi_period_settled_once", str(capacity), str(rp.get("units")),
		int(rp.get("units")) == capacity)
	# T017 语义：多周期在一次 advance_to 里**合并成一次事件**（refill_count 记到账数）
	_assert("D3_refill_once_with_count_2", "event=1,count=2",
		"event=%d,count=%d" % [_refill_events, int(rp.get("refill_count"))],
		_refill_events == 1 and int(rp.get("refill_count")) == 2)
	# T017 语义：满容量清零 next_refill_at，下次消耗时重新排期（不是排到未来）
	_assert("D4_next_refill_cleared_when_full", "0.0", str(rp.get("next_refill_at")),
		is_equal_approx(float(rp.get("next_refill_at")), 0.0))

	# ② 捕获食物失效跟随世界时间：ALIVE 下权威快进过期
	var cap_food: Node = load(RP_SCRIPT).new()
	cap_food.set("kind", &"food")
	cap_food.set("units", 1)
	cap_food.set("capacity", 1)
	entry.level.add_child(cap_food)
	await _advance_physics(3)
	cap_food.set("expire_at", float(wd.get("world_time")) + 300.0)
	wd.call("set_world_time", float(wd.get("world_time")) + 301.0)
	await _advance_physics(3)
	_assert("D5_capture_expires_with_world_time", "0", str(cap_food.get("units")),
		int(cap_food.get("units")) == 0)

	# ③ 门闩反证：同样夹具在 SELECTING（时间冻结）下真实等待 600 ms 不恢复
	entry.player.survival.apply_damage(9999.0, &"t034_gate2")
	await _advance_frames(12)
	_assert("D6_back_to_selecting", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")
	var wt_frozen := float(wd.get("world_time"))
	rp.set("units", 1)
	rp.set("next_refill_at", wt_frozen + 0.01)
	await _wait_real_ms(600)
	_assert("D7_no_refill_while_frozen", "1", str(rp.get("units")),
		int(rp.get("units")) == 1)
	_assert("D8_next_refill_untouched", str(wt_frozen + 0.01), str(rp.get("next_refill_at")),
		is_equal_approx(float(rp.get("next_refill_at")), wt_frozen + 0.01))

	# ④ 门闩下捕获食物不过期（对照 ②）
	var cap_food2: Node = load(RP_SCRIPT).new()
	cap_food2.set("kind", &"food")
	cap_food2.set("units", 1)
	cap_food2.set("capacity", 1)
	entry.level.add_child(cap_food2)
	await _advance_physics(3)
	cap_food2.set("expire_at", float(wd.get("world_time")) + 300.0)
	await _wait_real_ms(400)
	_assert("D9_no_expire_while_frozen", "1", str(cap_food2.get("units")),
		int(cap_food2.get("units")) == 1)
	cap_food2.queue_free()
	cap_food.queue_free()

	# ⑤ ALIVE 正对照：同夹具真实等待 300 ms 即恢复（与 ③ 互为反证）
	entry.dismiss_settle()
	await _advance_frames(2)
	var accepted := entry.select_species(CAT_ID)
	await _advance_frames(4)
	_assert("D10_third_life_alive", "alive", entry.lifecycle_state_name(),
		accepted and entry.lifecycle_state_name() == "alive")
	rp.set("units", 1)
	rp.set("next_refill_at", float(wd.get("world_time")) + 0.01)
	await _wait_real_ms(300)
	_assert("D11_refills_when_time_advances", "2", str(rp.get("units")),
		int(rp.get("units")) == 2)


# ---------------------------------------------------------------------------
# E 存活读数
# ---------------------------------------------------------------------------

func _section_e_alive_readout(entry: MainEntry) -> void:
	print("---- E 存活读数 ----")
	var wd := _wd()
	await _advance_frames(12)   # 状态行 10 帧一刷
	var txt := entry.status_text()
	_assert("E1_alive_has_day_and_daytime", "第 1 天·白天", txt,
		txt.contains("第 1 天") and txt.contains("白天"))
	# 权威快进到 650 s → 第 1 天·夜晚（边界对半的呈现侧复证）
	wd.call("set_world_time", 650.0)
	await _advance_frames(12)
	txt = entry.status_text()
	_assert("E2_night_readout", "第 1 天·夜晚", txt,
		txt.contains("第 1 天") and txt.contains("夜晚"))
	# 快进到 1200 s → 第 2 天·白天
	wd.call("set_world_time", 1200.0)
	await _advance_frames(12)
	txt = entry.status_text()
	_assert("E3_next_day_readout", "第 2 天·白天", txt,
		txt.contains("第 2 天") and txt.contains("白天"))


# ---------------------------------------------------------------------------
# F T033/T032 契约复证（零改动）
# ---------------------------------------------------------------------------

func _section_f_contract_recheck(entry: MainEntry) -> void:
	print("---- F 契约复证 ----")
	# 层序：hud → MainMenu → LifeStatus → LifeSettlePanel（T033 D1）
	var menu := entry.get_node_or_null("MainMenu")
	var status := entry.get_node_or_null("LifeStatus")
	var settle := entry.get_node_or_null("LifeSettlePanel")
	_assert("F1_layer_order_intact", "menu<status<settle",
		"%d/%d/%d" % [menu.get_index() if menu else -1,
			status.get_index() if status else -1,
			settle.get_index() if settle else -1],
		menu != null and status != null and settle != null
			and menu.get_index() < status.get_index()
			and status.get_index() < settle.get_index())
	# 解锁集语义：正式模式未解锁的 Mouse 仍是唯一锁定项（T033 复证）
	var locked: Array = entry.menu.call("locked_list")
	_assert("F2_locked_semantics_intact", "1(Mouse)", "%d:%s" % [locked.size(), str(locked)],
		locked.size() == 1 and String(locked[0]) == "Mouse")
	# 时钟读数只进状态行，不进 hud_text（T034 D5：不加时钟 UI）
	var hud_txt := entry.hud.call("hud_text") as String
	_assert("F3_clock_not_in_hud_text", "不含「第 1 天」", "<hud_text>",
		not hud_txt.contains("第 1 天") and not hud_txt.contains("第 2 天"))
