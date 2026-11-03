extends SceneTree
## T035 区域 NPC 数量账本 —— 先写可失败的断言（对应 `Docs/Tasks/T035.md` §6）。
##
## 覆盖：
##   A 初始化契约（4 区域 × 2 物种；鼠 2/4/240、猫 1/1/0；总计鼠 8 / 猫 4）
##   B 区域反查与活动登记（region_id_at 矩形包含；spawner 逐只登记；active ≤ total；玩家不计入）
##   C 捕获只扣一次（真实捕获扣账 / 幂等不重复扣 / 未登记个体不动区域账 / 下限 0）
##   D 恢复只吃世界时间（排期未来 / +1 / 多周期一次结算夹紧容量 / 门闩反证 / ALIVE 正对照 /
##     猫不自动增长 / 与捕猎·解锁零耦合）
##   E 快照与重建（形状 / round-trip / 未知区域·物种跳过 / 负数·超容量·非有限修复 / 恢复后继续运转）
##   F 重生不重置种群（死亡→重生 totals 保持、initialized 不翻）
##   H 既有契约复证（捕获发信==计数 / T033 UI 树序与解锁集 / T034 状态行与 hud_text）
##   G 新游戏重置（reset_for_new_game 清账 → 重新 init 回初始）
##
## 首跑策略：新 API 一律 `wd.call()/wd.get()` 探测——未实现时返回 null、
## 段首守卫断言红，脚本不崩（同 t033/t034 先红原则）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t035_region_population.gd' --quit-after 600000
## 结果口径：RESULT|pass=<n>|fail=<n> 全绿；失败时另打 RESULT|failed=<清单>。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const CAT_ID := &"Cat"
const MOUSE_ID := &"Mouse"

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _capture_events := 0   # capture_reported 发信计数（lambda 按值捕获，必须走成员）


func _on_capture_reported(_captor_id: String, _target_id: String, _pos: Vector3,
		_t: float) -> void:
	_capture_events += 1


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
	root.size = Vector2i(1280, 720)   # headless 根视口默认 64x64，add_child 后再设一次
	await _advance_frames(2)
	var entry := main as MainEntry
	if entry == null:
		print("RESULT|fail=1")
		print("RESULT|failed=A0_entry_class")
		quit(1)
		return
	_wd().connect("capture_reported", Callable(self, "_on_capture_reported"))

	await _section_a_init_contract()
	await _section_b_lookup_and_registry(entry)
	await _section_c_capture_deduct_once(entry)
	await _section_d_recovery_world_time(entry)
	await _section_e_snapshot_restore(entry)
	await _section_f_rebirth_keeps_ledger(entry)
	await _section_h_contract_recheck(entry)
	await _section_g_new_game_reset(entry)

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


func _advance_physics(n: int) -> void:
	for i in n:
		await physics_frame


## 真实毫秒等待（headless 帧推进不等价于真实时间；t033/t034 同法）
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


## 账本是否已初始化（段首守卫：未实现/未初始化时该段只出一条红，不连环崩）
func _ledger_ready() -> bool:
	return bool(_wd().get("region_population_initialized"))


## 区域 ID 列表（StringName→String 排序，便于整体对照）
func _region_ids_sorted() -> Array:
	var rids = _wd().call("region_ids")
	if not (rids is Array):
		return []
	var out: Array = []
	for r in rids:
		out.append(String(r))
	out.sort()
	return out


## 用公开 API（快照→改→重建，即读档路径）把某条记录改成受控状态。
## 数值必须合法（0 ≤ total ≤ 容量、next 有限），否则 restore 会修复掉。
func _set_record(region_id: StringName, species_id: StringName,
		total: int, next_at: float) -> bool:
	var snap = _wd().call("region_population_snapshot")
	if not (snap is Array):
		return false
	for rec in snap:
		if StringName(String(rec.get("region_id"))) == region_id \
				and StringName(String(rec.get("species_id"))) == species_id:
			rec["total_count"] = total
			rec["next_recover_at"] = next_at
	_wd().call("restore_region_population", snap)
	return int(_wd().call("region_total", region_id, species_id)) == total


## 全部区域的某物种总数之和
func _totals_of(species_id: StringName) -> int:
	var sum := 0
	for rid in _region_ids_sorted():
		sum += int(_wd().call("region_total", StringName(rid), species_id))
	return sum


## 快照的可比较转储（round-trip 断言用；顺序 = 账本插入序）
func _dump_snap(arr) -> Array:
	var out: Array = []
	if not (arr is Array):
		return out
	for r in arr:
		out.append("%s|%s|%d|%d|%.3f|%.3f" % [r.get("region_id"), r.get("species_id"),
			int(r.get("total_count", -1)), int(r.get("capacity", -1)),
			float(r.get("next_recover_at", -1.0)), float(r.get("recover_interval", -1.0))])
	return out


# ---------------------------------------------------------------------------
# A 初始化契约
# ---------------------------------------------------------------------------

func _section_a_init_contract() -> void:
	print("---- A 初始化契约 ----")
	var wd := _wd()
	_assert("A1_initialized", "true", str(wd.get("region_population_initialized")),
		_ledger_ready())
	if not _ledger_ready():
		return   # 守卫：账本未初始化（首跑红），后续段各自守卫
	var rids := _region_ids_sorted()
	_assert("A2_region_ids", "Courtyard,Creek,Grass,Roots", ",".join(rids),
		rids == ["Courtyard", "Creek", "Grass", "Roots"])
	var mouse_total_ok := true
	var mouse_cap_ok := true
	var mouse_int_ok := true
	var cat_ok := true
	for rid in rids:
		var rn := StringName(rid)
		mouse_total_ok = mouse_total_ok and int(wd.call("region_total", rn, MOUSE_ID)) == 2
		mouse_cap_ok = mouse_cap_ok and int(wd.call("region_capacity", rn, MOUSE_ID)) == 4
		mouse_int_ok = mouse_int_ok \
			and is_equal_approx(float(wd.get("region_records")[rn + String("|") + String(MOUSE_ID)]["recover_interval"]), 240.0)
		cat_ok = cat_ok and int(wd.call("region_total", rn, CAT_ID)) == 1 \
			and int(wd.call("region_capacity", rn, CAT_ID)) == 1 \
			and is_equal_approx(float(wd.get("region_records")[rn + String("|") + String(CAT_ID)]["recover_interval"]), 0.0)
	_assert("A3_mouse_total_per_region", "each=2", "ok=%s" % mouse_total_ok, mouse_total_ok)
	_assert("A4_mouse_capacity_per_region", "each=4", "ok=%s" % mouse_cap_ok, mouse_cap_ok)
	_assert("A5_mouse_recover_interval", "each=240", "ok=%s" % mouse_int_ok, mouse_int_ok)
	_assert("A6_cat_per_region", "each total=1/cap=1/interval=0", "ok=%s" % cat_ok, cat_ok)
	_assert("A7_mouse_totals", "8", str(_totals_of(MOUSE_ID)), _totals_of(MOUSE_ID) == 8)
	_assert("A8_cat_totals", "4", str(_totals_of(CAT_ID)), _totals_of(CAT_ID) == 4)
	# Population 组校验：两个 .tres 加载后 validate_config() 必须为空
	var cfg_cat := load("res://resources/species/cat.tres") as SpeciesConfig
	var cfg_mouse := load("res://resources/species/mouse.tres") as SpeciesConfig
	_assert("A9_validate_configs", "both empty",
		str(cfg_cat.validate_config()) + " / " + str(cfg_mouse.validate_config()),
		cfg_cat.validate_config().is_empty() and cfg_mouse.validate_config().is_empty())


# ---------------------------------------------------------------------------
# B 区域反查与活动登记
# ---------------------------------------------------------------------------

func _section_b_lookup_and_registry(entry: MainEntry) -> void:
	print("---- B 区域反查与活动登记 ----")
	_assert("B0_ledger_ready", "true", str(_ledger_ready()), _ledger_ready())
	if not _ledger_ready():
		return
	var wd := _wd()
	# 出生（正式模式默认解锁 Cat）→ 生态布置器铺 NPC
	var accepted := entry.select_species(CAT_ID)
	await _advance_physics(4)
	var setup_ok := false
	for i in 300:   # 布置器最多 240 次尝试（MAX_SETUP_ATTEMPTS）
		if entry.ecology != null and entry.ecology.is_setup_done() \
				and entry.ecology.npc_count_of(MOUSE_ID) == 2:
			setup_ok = true
			break
		await _advance_physics(1)
	_assert("B1_ecology_spawned", "accepted+2 mice", "ok=%s" % setup_ok,
		accepted and setup_ok)
	# B2 区域反查自洽：每个 level_regions 标记的中心点都落回自己的 region_id
	var markers := get_nodes_in_group("level_regions")
	var self_ok := markers.size() == 4
	for m in markers:
		var rid = wd.call("region_id_at", (m as Node3D).global_position)
		self_ok = self_ok and String(rid) == String(m.get_meta("region_id"))
	_assert("B2_region_at_marker_center", "4/4 自洽", "ok=%s" % self_ok, self_ok)
	# B3 区外点反查为空
	var outside = wd.call("region_id_at", Vector3(0.0, 1.0, 999.0))
	_assert("B3_outside_empty", "", String(outside), String(outside) == "")
	# B4 spawner 铺的鼠逐只登记：登记区域 == 反查结果，且区内活动数与实际分布一致
	var bodies := entry.ecology.npc_bodies()
	var expect := {}   # region -> 只数
	var outside_bodies := 0
	for b in bodies:
		var rid = wd.call("region_id_at", b.global_position)
		if String(rid).is_empty():
			outside_bodies += 1
		else:
			expect[String(rid)] = int(expect.get(String(rid), 0)) + 1
	var dist_ok := outside_bodies == 0
	for key in expect:
		dist_ok = dist_ok and int(wd.call("region_active_count", StringName(key), MOUSE_ID)) \
			== int(expect[key])
	_assert("B4_registered_per_region", "active=分布", "ok=%s" % dist_ok, dist_ok)
	# B5 Σactive(Mouse) == 铺出数 == 2（全部落区内）
	var sum_active := 0
	for rid in _region_ids_sorted():
		sum_active += int(wd.call("region_active_count", StringName(rid), MOUSE_ID))
	_assert("B5_sum_active_mouse", "2", str(sum_active),
		sum_active == 2 and bodies.size() == 2)
	# B6 目标玩家不计入：全区猫的活动数为 0
	var sum_cat := 0
	for rid in _region_ids_sorted():
		sum_cat += int(wd.call("region_active_count", StringName(rid), CAT_ID))
	_assert("B6_player_not_counted", "0", str(sum_cat), sum_cat == 0)
	# B7 不变式：每区每物种 active ≤ total
	var inv_ok := true
	for rid in _region_ids_sorted():
		var rn := StringName(rid)
		for sid in [CAT_ID, MOUSE_ID]:
			inv_ok = inv_ok \
				and int(wd.call("region_active_count", rn, sid)) <= int(wd.call("region_total", rn, sid))
	_assert("B7_active_le_total", "all", "ok=%s" % inv_ok, inv_ok)


# ---------------------------------------------------------------------------
# C 捕获只扣一次
# ---------------------------------------------------------------------------

func _section_c_capture_deduct_once(entry: MainEntry) -> void:
	print("---- C 捕获只扣一次 ----")
	_assert("C0_ledger_ready", "true", str(_ledger_ready()), _ledger_ready())
	if not _ledger_ready() or entry.ecology == null:
		return
	var wd := _wd()
	var bodies := entry.ecology.npc_bodies()
	if bodies.is_empty():
		_assert("C0_live_mouse", ">=1", "0", false)
		return
	var m0: AnimalBody = bodies[0]
	var rid0: StringName = StringName(String(wd.call("region_id_at", m0.global_position)))
	var t0 := int(wd.call("region_total", rid0, MOUSE_ID))
	var a0 := int(wd.call("region_active_count", rid0, MOUSE_ID))
	# C1 真实捕获（走 CaptureSettlement → report_capture → 扣账）：
	var ok = entry.player.capture.try_capture(m0, m0.global_position)
	_assert("C1_capture_ok", "true", str(ok), bool(ok))
	_assert("C1_total_minus_one", str(t0 - 1), str(wd.call("region_total", rid0, MOUSE_ID)),
		int(wd.call("region_total", rid0, MOUSE_ID)) == t0 - 1)
	_assert("C1_active_minus_one", str(a0 - 1), str(wd.call("region_active_count", rid0, MOUSE_ID)),
		int(wd.call("region_active_count", rid0, MOUSE_ID)) == a0 - 1)
	# C2 同 target_id 重复上报 → false、账不再扣、计数不加
	var cc0 := int(wd.get("capture_count"))
	var dup = wd.call("report_capture", "t035_dup", m0.source_id(), m0.global_position)
	_assert("C2_dup_rejected", "false", str(dup),
		not bool(dup) and int(wd.get("capture_count")) == cc0 \
			and int(wd.call("region_total", rid0, MOUSE_ID)) == t0 - 1)
	# C3 未登记个体（合成 ID，不在活动登记）→ 全局计数 +1，区域账不动
	var sum_before := _totals_of(MOUSE_ID)
	var synth = wd.call("report_capture", "t035_synth", "Mouse#999999", Vector3.ZERO)
	_assert("C3_unregistered_no_region_change", "true/sum 同/cc+1",
		"synth=%s sum=%d cc=%d" % [str(synth), _totals_of(MOUSE_ID), int(wd.get("capture_count"))],
		bool(synth) and _totals_of(MOUSE_ID) == sum_before \
			and int(wd.get("capture_count")) == cc0 + 1)
	# C4 扣账下限 0：把 m1 所在区改成 total=0 再上报 → 0 而不是 -1
	var bodies1 := entry.ecology.npc_bodies()
	if bodies1.is_empty():
		_assert("C4_live_mouse2", ">=1", "0", false)
		return
	var m1: AnimalBody = bodies1[0]
	var rid1: StringName = StringName(String(wd.call("region_id_at", m1.global_position)))
	var cc1 := int(wd.get("capture_count"))
	_set_record(rid1, MOUSE_ID, 0, 0.0)
	var capped = wd.call("report_capture", "t035_cap", m1.source_id(), m1.global_position)
	_assert("C4_floor_zero", "true/total=0/active=0",
		"ok=%s total=%d active=%d" % [str(capped),
			int(wd.call("region_total", rid1, MOUSE_ID)),
			int(wd.call("region_active_count", rid1, MOUSE_ID))],
		bool(capped) and int(wd.call("region_total", rid1, MOUSE_ID)) == 0 \
			and int(wd.call("region_active_count", rid1, MOUSE_ID)) == 0 \
			and int(wd.get("capture_count")) == cc1 + 1)


# ---------------------------------------------------------------------------
# D 恢复只吃世界时间
# ---------------------------------------------------------------------------

func _section_d_recovery_world_time(entry: MainEntry) -> void:
	print("---- D 恢复只吃世界时间 ----")
	_assert("D0_ledger_ready", "true", str(_ledger_ready()), _ledger_ready())
	if not _ledger_ready():
		return
	var wd := _wd()
	var rids := _region_ids_sorted()
	var rid0: StringName = StringName(rids[0])   # Courtyard（排序第一）
	# D1 排期到未来：next=0 → advance 到 t 只排期不立刻补
	_set_record(rid0, MOUSE_ID, 2, 0.0)
	var wt := float(wd.get("world_time"))
	wd.call("region_population_advance_to", wt)
	var next1 = float(wd.get("region_records")[rid0 + String("|") + String(MOUSE_ID)]["next_recover_at"])
	_assert("D1_schedules_future", "total=2/next>w t", "total=%d next=%.2f" % [
		int(wd.call("region_total", rid0, MOUSE_ID)), next1],
		int(wd.call("region_total", rid0, MOUSE_ID)) == 2 and next1 > wt)
	# D2 到点 +1 且再排未来
	wd.call("region_population_advance_to", next1 + 0.5)
	var next2 = float(wd.get("region_records")[rid0 + String("|") + String(MOUSE_ID)]["next_recover_at"])
	_assert("D2_recovers_one", "total=3/next>t", "total=%d next=%.2f" % [
		int(wd.call("region_total", rid0, MOUSE_ID)), next2],
		int(wd.call("region_total", rid0, MOUSE_ID)) == 3 and next2 > next1 + 0.5)
	# D3 多周期一次结算 + 夹紧容量：一次 advance 快进 10000 s → 只补到 4，满容量清零 next
	var t3 := float(wd.get("world_time"))
	wd.call("region_population_advance_to", t3 + 10000.0)
	_assert("D3_multi_period_clamp", "total=4/next=0", "total=%d next=%.2f" % [
		int(wd.call("region_total", rid0, MOUSE_ID)),
		float(wd.get("region_records")[rid0 + String("|") + String(MOUSE_ID)]["next_recover_at"])],
		int(wd.call("region_total", rid0, MOUSE_ID)) == 4 \
			and is_equal_approx(float(wd.get("region_records")[rid0 + String("|") + String(MOUSE_ID)]["next_recover_at"]), 0.0))
	# D4 满容量后不再长
	wd.call("region_population_advance_to", float(wd.get("world_time")) + 20000.0)
	_assert("D4_never_over_capacity", "4", str(wd.call("region_total", rid0, MOUSE_ID)),
		int(wd.call("region_total", rid0, MOUSE_ID)) == 4)
	# D5 门闩反证：死亡 → SELECTING，next=冻结时刻+0.01，真实等 600 ms 不恢复
	entry.player.survival.apply_damage(9999.0, &"t035_gate")
	await _advance_frames(2)
	var frozen := float(wd.get("world_time"))
	_set_record(rid0, MOUSE_ID, 1, frozen + 0.01)
	await _wait_real_ms(600)
	_assert("D5_frozen_no_recovery", "1", str(wd.call("region_total", rid0, MOUSE_ID)),
		int(wd.call("region_total", rid0, MOUSE_ID)) == 1 \
			and is_equal_approx(float(wd.get("world_time")), frozen))
	# D6 ALIVE 正对照：重生后真实等 300 ms → +1（时间重新走）。
	# 重生会重铺生态（setup→clear→再铺 2 只新鼠），先等布置完成再做后续断言。
	entry.dismiss_settle()
	await _advance_frames(2)
	var accepted := entry.select_species(CAT_ID)
	await _advance_frames(4)
	for i in 300:   # 等重铺完成（导航未就绪时布置器会跨帧重试）
		if entry.ecology != null and entry.ecology.is_setup_done() \
				and entry.ecology.npc_count_of(MOUSE_ID) == 2:
			break
		await _advance_physics(1)
	_assert("D6_alive_recovers", "alive/total=2", "%s total=%d" % [entry.lifecycle_state_name(),
		int(wd.call("region_total", rid0, MOUSE_ID))],
		accepted and entry.lifecycle_state_name() == "alive" \
			and int(wd.call("region_total", rid0, MOUSE_ID)) == 2)
	# D7 猫不自动增长（interval=0）：total=0 快进 20000 s 仍为 0
	_set_record(rid0, CAT_ID, 0, 0.0)
	wd.call("region_population_advance_to", float(wd.get("world_time")) + 20000.0)
	_assert("D7_cat_no_auto_growth", "0", str(wd.call("region_total", rid0, CAT_ID)),
		int(wd.call("region_total", rid0, CAT_ID)) == 0)
	# D8 零耦合：恢复不碰捕获账本、不铺/销毁表现、不动解锁集。
	# 注意重生后生态已重铺 2 只新鼠（D6 等待过），恢复结算本身不改变这个数。
	var locked: Array = entry.menu.call("locked_list")
	_assert("D8_zero_coupling", "cc=3/npc 不变/解锁不变",
		"cc=%d npc=%d locked=%s" % [int(wd.get("capture_count")),
			entry.ecology.npc_count_of(MOUSE_ID), str(locked)],
		int(wd.get("capture_count")) == 3 \
			and entry.ecology.npc_count_of(MOUSE_ID) == 2 \
			and locked.size() == 1 and String(locked[0]) == "Mouse")


# ---------------------------------------------------------------------------
# E 快照与重建
# ---------------------------------------------------------------------------

func _section_e_snapshot_restore(entry: MainEntry) -> void:
	print("---- E 快照与重建 ----")
	_assert("E0_ledger_ready", "true", str(_ledger_ready()), _ledger_ready())
	if not _ledger_ready():
		return
	var wd := _wd()
	var rids := _region_ids_sorted()
	var rid0: StringName = StringName(rids[0])
	# E1 形状与数值：8 条记录、逐字段与账本一致
	var snap = wd.call("region_population_snapshot")
	var shape_ok: bool = snap is Array and snap.size() == 8
	if shape_ok:
		for rec in snap:
			shape_ok = shape_ok and rec.has("region_id") and rec.has("species_id") \
				and rec.has("total_count") and rec.has("capacity") \
				and rec.has("next_recover_at") and rec.has("recover_interval") \
				and int(wd.call("region_total", StringName(String(rec["region_id"])),
					StringName(String(rec["species_id"])))) == int(rec["total_count"]) \
				and int(wd.call("region_capacity", StringName(String(rec["region_id"])),
					StringName(String(rec["species_id"])))) == int(rec["capacity"])
	_assert("E1_snapshot_shape", "8 条全字段", "ok=%s" % shape_ok, shape_ok)
	# E2 round-trip：快照 → 变账 → 用旧快照重建 → 账回快照值
	var s1 = wd.call("region_population_snapshot")
	_set_record(rid0, MOUSE_ID, 0, 0.0)
	wd.call("region_population_advance_to", float(wd.get("world_time")) + 100.0)   # <240 s 不补
	var rep_rt: Dictionary = wd.call("restore_region_population", s1)
	var s2 = wd.call("region_population_snapshot")
	_assert("E2_round_trip", "same dump", "rep=%s" % str(rep_rt.get("restored")),
		_dump_snap(s1) == _dump_snap(s2))
	# E3 未知区域 → 跳过
	var s_bad = wd.call("region_population_snapshot")
	s_bad.append({"region_id": "Atlantis", "species_id": "Mouse", "total_count": 1,
		"capacity": 4, "next_recover_at": 0.0, "recover_interval": 240.0})
	var rep3: Dictionary = wd.call("restore_region_population", s_bad)
	_assert("E3_unknown_region_skipped", "skipped 含 Atlantis|Mouse", str(rep3.get("skipped")),
		str(rep3.get("skipped")).contains("Atlantis|Mouse") \
			and (wd.call("region_population_snapshot") as Array).size() == 8)
	# E4 未知物种 → 跳过
	var s_bad2 = wd.call("region_population_snapshot")
	s_bad2.append({"region_id": "Courtyard", "species_id": "Dragon", "total_count": 1,
		"capacity": 4, "next_recover_at": 0.0, "recover_interval": 240.0})
	var rep4: Dictionary = wd.call("restore_region_population", s_bad2)
	_assert("E4_unknown_species_skipped", "skipped 含 Courtyard|Dragon", str(rep4.get("skipped")),
		str(rep4.get("skipped")).contains("Courtyard|Dragon") \
			and (wd.call("region_population_snapshot") as Array).size() == 8)
	# E5 负数 → 钳 0 + 修复记录
	var s_neg = wd.call("region_population_snapshot")
	for rec in s_neg:
		if String(rec["region_id"]) == String(rid0) and String(rec["species_id"]) == String(MOUSE_ID):
			rec["total_count"] = -5
	var rep5: Dictionary = wd.call("restore_region_population", s_neg)
	_assert("E5_negative_clamped", "total=0/repaired", "total=%d rep=%s" % [
		int(wd.call("region_total", rid0, MOUSE_ID)), str(rep5.get("repaired"))],
		int(wd.call("region_total", rid0, MOUSE_ID)) == 0 \
			and str(rep5.get("repaired")).contains("Courtyard|Mouse"))
	# E6 超容量 → 钳容量
	var s_over = wd.call("region_population_snapshot")
	for rec in s_over:
		if String(rec["region_id"]) == String(rid0) and String(rec["species_id"]) == String(MOUSE_ID):
			rec["total_count"] = 99
	var rep6: Dictionary = wd.call("restore_region_population", s_over)
	_assert("E6_over_capacity_clamped", "total=4", "total=%d rep=%s" % [
		int(wd.call("region_total", rid0, MOUSE_ID)), str(rep6.get("repaired"))],
		int(wd.call("region_total", rid0, MOUSE_ID)) == 4)
	# E7 非有限 → 整条回初始
	var s_nan = wd.call("region_population_snapshot")
	for rec in s_nan:
		if String(rec["region_id"]) == String(rid0) and String(rec["species_id"]) == String(MOUSE_ID):
			rec["next_recover_at"] = NAN
	var rep7: Dictionary = wd.call("restore_region_population", s_nan)
	_assert("E7_nonfinite_reset_initial", "total=2/next=0/repaired", "total=%d next=%.2f rep=%s" % [
		int(wd.call("region_total", rid0, MOUSE_ID)),
		float(wd.get("region_records")[rid0 + String("|") + String(MOUSE_ID)]["next_recover_at"]),
		str(rep7.get("repaired"))],
		int(wd.call("region_total", rid0, MOUSE_ID)) == 2 \
			and is_equal_approx(float(wd.get("region_records")[rid0 + String("|") + String(MOUSE_ID)]["next_recover_at"]), 0.0) \
			and str(rep7.get("repaired")).contains("Courtyard|Mouse"))
	# E8 restore 后继续运转：能重新排期
	_set_record(rid0, MOUSE_ID, 2, 0.0)
	wd.call("region_population_advance_to", float(wd.get("world_time")))
	var next_e = float(wd.get("region_records")[rid0 + String("|") + String(MOUSE_ID)]["next_recover_at"])
	_assert("E8_resumes_after_restore", "next>0", "%.2f" % next_e, next_e > 0.0)
	# 收尾：把 rid0 鼠恢复到 2/0，避免影响后续段
	_set_record(rid0, MOUSE_ID, 2, 0.0)


# ---------------------------------------------------------------------------
# F 重生不重置种群
# ---------------------------------------------------------------------------

func _section_f_rebirth_keeps_ledger(entry: MainEntry) -> void:
	print("---- F 重生不重置种群 ----")
	_assert("F0_ledger_ready", "true", str(_ledger_ready()), _ledger_ready())
	if not _ledger_ready():
		return
	var wd := _wd()
	var rids := _region_ids_sorted()
	var rid_x: StringName = StringName(rids[2])   # Grass（刻意挑一个未在 D 段操作的区）
	# 受控状态：total=3（≠初始 2、≠容量 4）、next 排远
	_set_record(rid_x, MOUSE_ID, 3, 1000000000.0)
	entry.player.survival.apply_damage(9999.0, &"t035_gate2")
	await _advance_frames(14)
	entry.dismiss_settle()
	await _advance_frames(2)
	var accepted := entry.select_species(CAT_ID)
	await _advance_frames(4)
	_assert("F1_rebirth_alive", "alive", entry.lifecycle_state_name(),
		accepted and entry.lifecycle_state_name() == "alive")
	_assert("F2_totals_kept_through_rebirth", "total=3/next=1e9/initialized",
		"total=%d next=%.1f init=%s" % [int(wd.call("region_total", rid_x, MOUSE_ID)),
			float(wd.get("region_records")[rid_x + String("|") + String(MOUSE_ID)]["next_recover_at"]),
			str(wd.get("region_population_initialized"))],
		int(wd.call("region_total", rid_x, MOUSE_ID)) == 3 \
			and is_equal_approx(float(wd.get("region_records")[rid_x + String("|") + String(MOUSE_ID)]["next_recover_at"]), 1000000000.0) \
			and bool(wd.get("region_population_initialized")))
	_assert("F3_not_initial_totals", "鼠总 ≠ 8", str(_totals_of(MOUSE_ID)),
		_totals_of(MOUSE_ID) != 8)


# ---------------------------------------------------------------------------
# H 既有契约复证（T021/T033/T034）
# ---------------------------------------------------------------------------

func _section_h_contract_recheck(entry: MainEntry) -> void:
	print("---- H 契约复证 ----")
	var wd := _wd()
	# H1 每次真实结算只发一次信号；扣账没有偷加发信
	_assert("H1_capture_events_equal_count", "events=count=3",
		"events=%d count=%d" % [_capture_events, int(wd.get("capture_count"))],
		_capture_events == int(wd.get("capture_count")) and _capture_events == 3)
	# H2 层序：hud → MainMenu → LifeStatus → LifeSettlePanel（T033 D1）
	var menu := entry.get_node_or_null("MainMenu")
	var status := entry.get_node_or_null("LifeStatus")
	var settle := entry.get_node_or_null("LifeSettlePanel")
	_assert("H2_layer_order_intact", "menu<status<settle",
		"%d/%d/%d" % [menu.get_index() if menu else -1,
			status.get_index() if status else -1,
			settle.get_index() if settle else -1],
		menu != null and status != null and settle != null
			and menu.get_index() < status.get_index()
			and status.get_index() < settle.get_index())
	# H3 解锁集语义：正式模式未解锁的 Mouse 仍是唯一锁定项（T033 复证）
	var locked: Array = entry.menu.call("locked_list")
	_assert("H3_locked_semantics_intact", "1(Mouse)", "%d:%s" % [locked.size(), str(locked)],
		locked.size() == 1 and String(locked[0]) == "Mouse")
	# H4 时钟读数只进状态行、不进 hud_text（T034 D5）
	await _advance_frames(12)   # 状态行 10 帧一刷
	var txt := entry.status_text()
	var hud_txt := entry.hud.call("hud_text") as String
	_assert("H4_day_readout_intact", "状态行含「第…天」/hud 不含", txt,
		txt.contains("第") and txt.contains("白天") and not hud_txt.contains("第"))


# ---------------------------------------------------------------------------
# G 新游戏重置（破坏性，放最后）
# ---------------------------------------------------------------------------

func _section_g_new_game_reset(entry: MainEntry) -> void:
	print("---- G 新游戏重置 ----")
	var wd := _wd()
	wd.call("reset_for_new_game")
	_assert("G1_ledger_cleared", "records=0/initialized=false",
		"snap=%d init=%s" % [(wd.call("region_population_snapshot") as Array).size(),
			str(wd.get("region_population_initialized"))],
		(wd.call("region_population_snapshot") as Array).is_empty() \
			and not bool(wd.get("region_population_initialized")))
	_assert("G2_rects_cleared", "", str(wd.call("region_id_at", Vector3(0.0, 1.0, 16.0))),
		String(wd.call("region_id_at", Vector3(0.0, 1.0, 16.0))) == "")
	_assert("G3_active_cleared", "0", str(wd.call("region_active_count", &"Courtyard", MOUSE_ID)),
		int(wd.call("region_active_count", &"Courtyard", MOUSE_ID)) == 0)
	_assert("G4_capture_ledger_cleared", "cc=0", str(int(wd.get("capture_count"))),
		int(wd.get("capture_count")) == 0 and (wd.get("captured_target_ids") as Dictionary).is_empty())
	# 重新 init → 回初始（鼠 8 / 猫 4）
	wd.call("init_region_population", entry.get("_configs"))
	_assert("G5_reinit_initial_totals", "鼠8/猫4/initialized",
		"m=%d c=%d init=%s" % [_totals_of(MOUSE_ID), _totals_of(CAT_ID),
			str(wd.get("region_population_initialized"))],
		_totals_of(MOUSE_ID) == 8 and _totals_of(CAT_ID) == 4 \
			and bool(wd.get("region_population_initialized")))
