extends SceneTree
## T040 加载顺序与位置安全 —— 先写可失败的断言（对应 `Docs/Tasks/T040.md` §6）。
##
## 覆盖：
##   A 基线 active<=total（区域账本权威；玩家鼠时猫每区 ≤ total=1）
##   B 按账本实例化（total=0 不生成、total=3 只到上限、未实例化不占位）
##   C 收敛（手工超额登记 → reconcile 退场、账本不动、幂等、visible_risk）
##   D 位置回退（合法原样保留；区外/水上/墙内/非有限 → 区内合法点）
##   E 捕获事务（total/active 同一次减、重复不扣、未登记不误扣、节点保留但出组）
##   F 兼容（T037 键/精确 transform、T038 队列观测、T039 口径、安全距离重建）
##
## 首跑策略：新 API 一律 `call()/get()/has_method()` 探测；未实现时该段只落红，不崩。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t040_load_order_safety.gd' --quit-after 300000
## 结果口径：RESULT|pass=<n>|fail=<n>。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CAT_ID := &"Cat"
const MOUSE_ID := &"Mouse"
const EPS := 0.001

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _entry: MainEntry = null
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await _advance_frames(1)
	# T043a：冻结世界时间——读档/账本断言不能被区域种群恢复（只吃 world_time）在夹具步骤间漂移
	var wd0 := root.get_node_or_null("WorldDirector")
	if wd0 != null:
		wd0.set("time_advancing", false)
	_cat = load("res://resources/species/cat.tres") as SpeciesConfig
	_mouse = load("res://resources/species/mouse.tres") as SpeciesConfig
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null or _cat == null or _mouse == null:
		_assert("A0_load", "场景与配置可加载", "null", false)
		_summary()
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	root.size = Vector2i(1280, 720)
	await _advance_frames(2)
	_entry = main as MainEntry
	if _entry == null:
		_assert("A0_entry", "MainEntry", "null", false)
		_summary()
		quit(1)
		return
	_gs().set("test_mode", true)
	_gs().call("unlock_species", MOUSE_ID)

	await _section_a_baseline()
	await _section_b_instantiate_by_ledger()
	await _section_c_reconcile()
	await _section_d_position_fallback()
	await _section_e_capture_transaction()
	await _section_f_compat_rebuild()

	_entry.queue_free()
	await _advance_frames(2)
	_summary()
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------------------
# A 基线 active<=total
# ---------------------------------------------------------------------------

func _section_a_baseline() -> void:
	print("---- A 基线 active<=total ----")
	_assert("A1_ledger_consistency_api", "true", str(_wd().has_method("ledger_consistency")),
		_wd().has_method("ledger_consistency"))
	# 夹具决定：把捕食者最小距缩到 8 m，让猫 NPC 在真实关卡的 Courtyard 有合法落点，
	# 这样“每区 total=1”才真正被压测到。默认值 24 由 A0b 单独守住。
	_assert("A0b_predator_default", "24",
		str(_entry.ecology.predator_min_distance if _entry.ecology != null else -1.0),
		_entry.ecology != null and is_equal_approx(_entry.ecology.predator_min_distance, 24.0))
	_entry.ecology.predator_min_distance = 8.0
	var accepted := _entry.select_species(CAT_ID)
	await _wait_ecology()
	_assert("A2_cat_spawn", "accepted/setup", "accepted=%s setup=%s" % [accepted,
		_entry.ecology.is_setup_done() if _entry.ecology != null else false],
		accepted and _entry.ecology != null and _entry.ecology.is_setup_done())
	_assert_consistency("A3_initial")
	var mouse_npc := _entry.ecology.npc_count_of(MOUSE_ID)
	_assert("A4_cat_player_mice", "2", str(mouse_npc), mouse_npc == 2)

	# 切到鼠（猫 NPC，猫 total=1/区、T027 想要 2 只）——旧实现会把 2 只塞进同区。
	await _kill_player()
	var ok_mouse := _entry.select_species(MOUSE_ID)
	await _wait_ecology()
	_assert("A5_mouse_spawn", "accepted", str(ok_mouse), ok_mouse)
	var cat_total := int(_wd().call("region_population_totals", CAT_ID))
	var cat_active := 0
	for rid in _region_ids():
		cat_active += int(_wd().call("region_active_count", rid, CAT_ID))
	_assert("A6_cat_total", "≤4", str(cat_total), cat_total <= 4)
	_assert("A7_cat_active_le_total", "≤%d" % cat_total, str(cat_active), cat_active <= cat_total)
	# 每区 total=1：压测“同区不得超实例化”这条硬约束（去掉上限后这里会是 2）。
	var cy_cat := int(_wd().call("region_active_count", &"Courtyard", CAT_ID))
	_assert("A7b_courtyard_cat_capped", "≤1", str(cy_cat), cy_cat <= 1)
	_assert("A7c_cat_npc_present", "≥1", str(_entry.ecology.npc_count_of(CAT_ID)),
		_entry.ecology.npc_count_of(CAT_ID) >= 1)
	_assert_consistency("A8_after_mouse")


# ---------------------------------------------------------------------------
# B 按账本实例化
# ---------------------------------------------------------------------------

func _section_b_instantiate_by_ledger() -> void:
	print("---- B 按区域账本实例化 ----")
	# 玩家用 Cat（生态铺 Mouse，8 m 即可落点），把 Mouse 总量只放进 Roots：
	# 出生标记所在的 Courtyard total=0 必须挡住标记候选，Roots 再由区域候选实例化。
	var raw := _raw_snapshot()
	_set_mouse_totals(raw, 0, 0, 1, 0)
	_restore_as(raw, CAT_ID, _spawn_marker(CAT_ID))
	await _apply_raw(raw)
	var player_sid := "?"
	if _entry.player != null and _entry.player.species_config != null:
		player_sid = String(_entry.player.species_config.species_id)
	_assert("B0_apply", "alive(Cat)", "%s/%s" % [_entry.lifecycle_state_name(), player_sid],
		_entry.lifecycle_state_name() == "alive" and player_sid == String(CAT_ID))
	_assert("B1_courtyard_mouse_total", "0", str(_wd().call("region_total", &"Courtyard", MOUSE_ID)),
		int(_wd().call("region_total", &"Courtyard", MOUSE_ID)) == 0)
	_assert("B2_roots_mouse_total", "1", str(_wd().call("region_total", &"Roots", MOUSE_ID)),
		int(_wd().call("region_total", &"Roots", MOUSE_ID)) == 1)
	_assert("B3_grass_mouse_total", "0", str(_wd().call("region_total", &"Grass", MOUSE_ID)),
		int(_wd().call("region_total", &"Grass", MOUSE_ID)) == 0)
	var per := _active_by_region(MOUSE_ID)
	_assert("B4_zero_region_no_npc", "0", str(per.get("Courtyard", 0)),
		int(per.get("Courtyard", 0)) == 0)
	_assert("B5_roots_instantiated", "1", str(per.get("Roots", 0)),
		int(per.get("Roots", 0)) == 1)
	_assert("B6_grass_zero_no_npc", "0", str(per.get("Grass", 0)),
		int(per.get("Grass", 0)) == 0)
	_assert("B7_all_in_region", "全部区内", str(per), _all_in_region())
	_assert_consistency("B8_consistency")
	_assert_bodies_match_active("B9_registry_matches_bodies", MOUSE_ID)
	_assert("B10_visible_matches_ledger", "1", "%d" % _entry.ecology.npc_count_of(MOUSE_ID),
		_entry.ecology.npc_count_of(MOUSE_ID) == 1)

	# 未实例化的 total 不生成、不占位：Roots=3 但 T027 预算 2 → 只出现 2 只。
	var raw2 := _raw_snapshot()
	_set_mouse_totals(raw2, 0, 0, 3, 0)
	_restore_as(raw2, CAT_ID, _spawn_marker(CAT_ID))
	await _apply_raw(raw2)
	_assert("B11_root_total_3", "3", str(_wd().call("region_total", &"Roots", MOUSE_ID)),
		int(_wd().call("region_total", &"Roots", MOUSE_ID)) == 3)
	_assert("B12_unspawned_no_placeholder", "2", "%d" % _entry.ecology.npc_count_of(MOUSE_ID),
		_entry.ecology.npc_count_of(MOUSE_ID) == 2)
	_assert("B13_root_active_le_total", "≤3", str(_wd().call("region_active_count", &"Roots", MOUSE_ID)),
		int(_wd().call("region_active_count", &"Roots", MOUSE_ID)) <= 3)
	_assert_consistency("B14_consistency")
	_assert_bodies_match_active("B15_registry_matches_bodies", MOUSE_ID)


# ---------------------------------------------------------------------------
# C 收敛
# ---------------------------------------------------------------------------

func _section_c_reconcile() -> void:
	print("---- C active>total 收敛（T040b：12 m 内不退场） ----")
	var wd := _wd()
	var probe: AnimalBody = await _spawn_probe_body(_mouse, _entry.player.global_position \
		+ Vector3(2.0, 0.0, 0.0))
	var registered: bool = wd.call("register_region_body", &"Courtyard", MOUSE_ID, probe)
	var active_before := int(wd.call("region_active_count", &"Courtyard", MOUSE_ID))
	var total_before := int(wd.call("region_total", &"Courtyard", MOUSE_ID))
	_assert("C1_forced_excess", "active=1>total=0", "active=%d total=%d" % [active_before, total_before],
		registered and active_before > total_before)
	_assert("C2_reconcile_api", "true", str(wd.has_method("reconcile_region_population")),
		wd.has_method("reconcile_region_population"))
	var rep: Dictionary = wd.call("reconcile_region_population", _entry.player.global_position) \
		if wd.has_method("reconcile_region_population") else {}
	_assert("C3_near_retained", "removed=0,pending≥1",
		"removed=%s pending=%s" % [rep.get("removed", -1), rep.get("pending_excess", -1)],
		int(rep.get("removed", -1)) == 0 and int(rep.get("pending_excess", -1)) >= 1)
	_assert("C4_near_body_valid", "true", str(is_instance_valid(probe)), is_instance_valid(probe))
	_assert("C5_near_active_one", "1", str(wd.call("region_active_count", &"Courtyard", MOUSE_ID)),
		int(wd.call("region_active_count", &"Courtyard", MOUSE_ID)) == 1)
	var pending: Array = rep.get("pending_entries", []) as Array
	_assert("C6_pending_reason", "within_visible_distance",
		str(pending[0].get("reason", "")) if pending.size() > 0 else "<empty>",
		pending.size() > 0 and String(pending[0].get("reason", "")) == "within_visible_distance")
	var rep2: Dictionary = wd.call("reconcile_region_population", _entry.player.global_position) \
		if wd.has_method("reconcile_region_population") else {}
	_assert("C7_near_idempotent", "removed=0,pending≥1",
		"removed=%s pending=%s" % [rep2.get("removed", -1), rep2.get("pending_excess", -1)],
		int(rep2.get("removed", -1)) == 0 and int(rep2.get("pending_excess", -1)) >= 1)
	# 就地收敛：不夹 `await`，避免主循环的低频 pending 重试抢在断言前把探针退场（T043a）
	probe.global_position = _entry.player.global_position + Vector3(0.0, 0.0, 13.0)
	var rep_far: Dictionary = wd.call("reconcile_region_population",
		_entry.player.global_position) if wd.has_method("reconcile_region_population") else {}
	_assert("C8_far_removed", "≥1", str(rep_far.get("removed", 0)),
		int(rep_far.get("removed", 0)) >= 1)
	_assert("C9_total_unchanged", "0", str(wd.call("region_total", &"Courtyard", MOUSE_ID)),
		int(wd.call("region_total", &"Courtyard", MOUSE_ID)) == 0)
	_assert("C10_active_zero", "0", str(wd.call("region_active_count", &"Courtyard", MOUSE_ID)),
		int(wd.call("region_active_count", &"Courtyard", MOUSE_ID)) == 0)
	_assert("C11_no_visible_removal", "visible_risk=0,pending=0",
		"visible_risk=%s pending=%s" % [rep_far.get("visible_risk", []), rep_far.get("pending_excess", -1)],
		(rep_far.get("visible_risk", []) as Array).size() == 0 \
			and int(rep_far.get("pending_excess", -1)) == 0)
	await _advance_frames(2)
	_assert("C12_body_retired", "invalid", str(is_instance_valid(probe)), not is_instance_valid(probe))
	_assert_consistency("C13_consistency")


# ---------------------------------------------------------------------------
# D 位置回退
# ---------------------------------------------------------------------------

func _section_d_position_fallback() -> void:
	print("---- D 位置回退 ----")
	_assert("D1_resolve_api", "true", str(_entry.has_method("resolve_safe_player_position")),
		_entry.has_method("resolve_safe_player_position"))
	var marker := _spawn_marker(MOUSE_ID)
	var good: Dictionary = _entry.call("resolve_safe_player_position", _mouse, marker) \
		if _entry.has_method("resolve_safe_player_position") else {}
	_assert("D2_valid_preserved", "valid/exact", "reason=%s pos=%s" % [good.get("reason", ""),
		good.get("position", null)], String(good.get("reason", "")) == "valid" \
		and (good.get("position") as Vector3).is_equal_approx(marker))

	var outside := Vector3(200.0, 5.0, 200.0)
	var res_out: Dictionary = _entry.call("resolve_safe_player_position", _mouse, outside) \
		if _entry.has_method("resolve_safe_player_position") else {}
	_assert("D3_outside_fallback", "非 valid/区内", "reason=%s region=%s" % [res_out.get("reason", ""),
		res_out.get("region_id", "")], String(res_out.get("reason", "")) != "valid" \
		and String(res_out.get("region_id", "")) != "" and _is_legal(_mouse, res_out.get("position", Vector3.ZERO)))

	var water := Vector3(-23.0, 0.6, 16.0)
	var res_water: Dictionary = _entry.call("resolve_safe_player_position", _mouse, water) \
		if _entry.has_method("resolve_safe_player_position") else {}
	_assert("D4_water_fallback", "不在水面/区内", "reason=%s region=%s" % [res_water.get("reason", ""),
		res_water.get("region_id", "")], String(res_water.get("reason", "")) != "valid" \
		and not _over_water(res_water.get("position", Vector3.ZERO)) \
		and String(res_water.get("region_id", "")) != "")

	var wall := Vector3(-32.0, 0.6, 10.0)
	var res_wall: Dictionary = _entry.call("resolve_safe_player_position", _cat, wall) \
		if _entry.has_method("resolve_safe_player_position") else {}
	_assert("D5_wall_fallback", "不在墙内/区内", "reason=%s pos=%s" % [res_wall.get("reason", ""),
		res_wall.get("position", null)], String(res_wall.get("reason", "")) != "valid" \
		and String(res_wall.get("region_id", "")) != "" \
		and _is_legal(_cat, res_wall.get("position", Vector3.ZERO)))

	var nan_pos := Vector3(NAN, 0.0, 0.0)
	var res_nan: Dictionary = _entry.call("resolve_safe_player_position", _mouse, nan_pos) \
		if _entry.has_method("resolve_safe_player_position") else {}
	_assert("D6_nonfinite_fallback", "有限/区内", "reason=%s pos=%s" % [res_nan.get("reason", ""),
		res_nan.get("position", null)], String(res_nan.get("reason", "")) != "valid" \
		and _finite(res_nan.get("position", Vector3.ZERO)) and _is_legal(_mouse, res_nan.get("position", Vector3.ZERO)))

	# 实际读档：水面位置必须被回退，玩家可见落点就是回退点。
	var raw := _raw_snapshot()
	raw["current_life"]["transform"] = Transform3D(Basis(), water)
	raw["current_life"]["start_position"] = water
	raw["pending_settlement_life_id"] = ""
	await _apply_raw(raw)
	var resolved: Dictionary = _entry.get("last_position_resolution") \
		if (_entry.get("last_position_resolution") is Dictionary) else {}
	_assert("D7_loaded_player_not_water", "不在水面", str(_entry.player.global_position if _entry.player else null),
		_entry.player != null and not _over_water(_entry.player.global_position))
	_assert("D8_resolution_reason", "非 valid", str(resolved.get("reason", "")),
		String(resolved.get("reason", "")) != "" and String(resolved.get("reason", "")) != "valid")
	_assert("D9_resolution_matches_player", "同一点",
		"res=%s player=%s" % [str(resolved.get("position", null)), str(_applied_player_pos)],
		_applied_player_present and (resolved.get("position", Vector3.ZERO) as Vector3) \
			.distance_to(_applied_player_pos) <= 0.05)

	# 合法存档位置必须原样保留（T037 D12 的精确 transform 语义）。
	var raw2 := _raw_snapshot()
	var exact := Vector3(3.5, 0.6, -2.25)
	raw2["current_life"]["transform"] = Transform3D(Basis(), exact)
	raw2["current_life"]["start_position"] = exact
	raw2["pending_settlement_life_id"] = ""
	await _apply_raw(raw2)
	# 与 D9 同口径：断言"读档应用后的落点"（`_applied_player_pos`），而不是物理沉降后的实时坐标
	_assert("D10_valid_exact_transform", str(exact), str(_applied_player_pos if _applied_player_present else null),
		_applied_player_present and _applied_player_pos.distance_to(exact) <= 0.05)


# ---------------------------------------------------------------------------
# E 捕获事务
# ---------------------------------------------------------------------------

func _section_e_capture_transaction() -> void:
	print("---- E 捕获事务 ----")
	var wd := _wd()
	# B 之后玩家是 Cat → 生态铺的是 Mouse；捕获一只已登记的鼠（账本同一次事务减一）。
	var target := _first_alive_npc(MOUSE_ID)
	_assert("E0_target", "存在", str(target), target != null)
	if target == null:
		return
	var sid := target.source_id()
	var rid := StringName(String(wd.call("region_id_at", target.global_position)))
	var target_sid: StringName = target.species_config.species_id
	var total_before := int(wd.call("region_total", rid, target_sid))
	var active_before := int(wd.call("region_active_count", rid, target_sid))
	var ok: bool = wd.call("report_capture", _entry.player.source_id(), sid,
		target.global_position, float(wd.get("world_time")))
	_assert("E1_capture_ok", "true", str(ok), ok)
	target.call("mark_captured", _entry.player.source_id())
	_assert("E2_total_minus_one", "%d" % (total_before - 1), str(wd.call("region_total", rid, target_sid)),
		int(wd.call("region_total", rid, target_sid)) == total_before - 1)
	_assert("E3_active_minus_one", "%d" % (active_before - 1),
		str(wd.call("region_active_count", rid, target_sid)),
		int(wd.call("region_active_count", rid, target_sid)) == active_before - 1)
	var ledger: Dictionary = wd.get("last_capture_ledger") if wd.get("last_capture_ledger") is Dictionary else {}
	_assert("E4_capture_ledger", "registered/total 同减",
		"reg=%s tb=%s ta=%s ab=%s aa=%s" % [ledger.get("registered", null), ledger.get("total_before", null),
			ledger.get("total_after", null), ledger.get("active_before", null), ledger.get("active_after", null)],
		bool(ledger.get("registered", false)) \
			and int(ledger.get("total_before", -1)) == total_before \
			and int(ledger.get("total_after", -2)) == total_before - 1 \
			and int(ledger.get("active_before", -1)) == active_before \
			and int(ledger.get("active_after", -2)) == active_before - 1)
	_assert_consistency("E5_consistency")
	# CaptureSettlement 顺序：report_capture 后立刻 mark_captured（同调用栈）。
	_assert("E6_mark_captured", "captured", str(target.captured), target.captured)
	await _advance_frames(2)
	_assert("E7_node_kept", "valid", str(is_instance_valid(target)), is_instance_valid(target))
	_assert("E8_out_of_group", "false", str(target.is_in_group(&"animal_bodies")),
		not target.is_in_group(&"animal_bodies"))
	# 重复上报：零扣减。
	var dup: bool = wd.call("report_capture", _entry.player.source_id(), sid, target.global_position,
		float(wd.get("world_time")))
	_assert("E9_duplicate_noop", "false", str(dup), not dup)
	_assert("E10_duplicate_total", "%d" % (total_before - 1), str(wd.call("region_total", rid, target_sid)),
		int(wd.call("region_total", rid, target_sid)) == total_before - 1)
	# 未登记目标：不误扣。
	var stray: AnimalBody = await _spawn_probe_body(_mouse, Vector3(0.0, 0.6, 8.0))
	var stray_sid := stray.source_id()
	var total_all_before := int(wd.call("region_population_totals", MOUSE_ID))
	var stray_ok: bool = wd.call("report_capture", _entry.player.source_id(), stray_sid,
		stray.global_position, float(wd.get("world_time")))
	_assert("E11_unregistered_capture", "true", str(stray_ok), stray_ok)
	_assert("E12_unregistered_no_deduct", str(total_all_before),
		str(wd.call("region_population_totals", MOUSE_ID)),
		int(wd.call("region_population_totals", MOUSE_ID)) == total_all_before)
	_assert_consistency("E13_consistency")


# ---------------------------------------------------------------------------
# F 兼容与安全距离
# ---------------------------------------------------------------------------

func _section_f_compat_rebuild() -> void:
	print("---- F 兼容与安全距离 ----")
	var sm := _sm()
	var snap: Dictionary = sm.call("build_snapshot", &"t040_f")
	var keys := ["save_version", "revision", "world_time", "resources", "regions", "discovered_ids",
		"unlocked_species", "life_records", "current_life", "pending_settlement_life_id", "events",
		"life_counter", "event_seq", "saved_reason"]
	var missing: Array[String] = []
	for k in keys:
		if not snap.has(k):
			missing.append(k)
	_assert("F1_format_keys", "14", str(snap.size()), snap.size() == keys.size() and missing.is_empty())
	_assert("F2_save_version", "1", str(snap.get("save_version")),
		int(snap.get("save_version", 0)) == 1)

	# 读档 + 安全距离：玩家放 Roots，猫 total 给 1，猫出生标记 25m 外。
	var raw := _raw_snapshot()
	for r in (raw["regions"] as Array):
		var rec: Dictionary = r
		if String(rec.get("region_id", "")) == "Roots" and String(rec.get("species_id", "")) == "Cat":
			rec["total_count"] = 1
		if String(rec.get("region_id", "")) == "Courtyard" and String(rec.get("species_id", "")) == "Mouse":
			rec["capacity"] = 99
			rec["recover_interval"] = 1.0
			rec["next_recover_at"] = 0.0
	raw["current_life"]["transform"] = Transform3D(Basis(), Vector3(20.0, 0.6, 16.0))
	raw["current_life"]["start_position"] = Vector3(20.0, 0.6, 16.0)
	raw["pending_settlement_life_id"] = ""
	await _apply_raw(raw)
	_assert("F3_reload_alive", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_assert("F4_capacity_not_restored", "4/240",
		"%d/%.0f" % [int(_wd().call("region_capacity", &"Courtyard", MOUSE_ID)),
			float(_ledger_rec("Courtyard", "Mouse").get("recover_interval", -1.0))],
		int(_wd().call("region_capacity", &"Courtyard", MOUSE_ID)) == 4 \
			and is_equal_approx(float(_ledger_rec("Courtyard", "Mouse").get("recover_interval", -1.0)), 240.0))
	_assert("F5_pending_unchanged", "空", str(_sm().get("pending_settlement_life_id")),
		String(_sm().get("pending_settlement_life_id")) == "" and bool(_wd().get("region_population_initialized")))
	var safe := _safe_distances_ok()
	_assert("F6_safe_distance", "全部 ≥ min", safe.get("detail", ""), bool(safe.get("ok", false)))
	_assert("F7_no_overlap", "无胶囊重叠", safe.get("overlap", ""), int(safe.get("overlaps", -1)) == 0)
	var rep: Dictionary = _entry.ecology.spawn_report() if _entry.ecology != null else {}
	_assert("F8_report_safe_flag", "true", str(rep.get("safe_distance_ok", null)),
		rep.has("safe_distance_ok") and bool(rep.get("safe_distance_ok")))
	_assert_consistency("F9_consistency")
	_assert("F10_t027_defaults", "2/3", "%d/%d" % [_entry.ecology.count_per_species,
		_entry.ecology.max_npcs], _entry.ecology.count_per_species == 2 and _entry.ecology.max_npcs == 3)

	# T039 口径：双坏阻断 API 仍在，且真实存档路径未被本任务改写。
	_assert("F11_t039_blocked_api", "true", str(_entry.has_method("is_load_blocked")),
		_entry.has_method("is_load_blocked"))


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _wd() -> Node:
	return root.get_node_or_null("/root/WorldDirector")


func _gs() -> Node:
	return root.get_node_or_null("/root/GameState")


func _sm() -> Node:
	return root.get_node_or_null("/root/SaveManager")


func _advance_frames(n: int) -> void:
	for _i in n:
		await process_frame


func _advance_physics(n: int) -> void:
	for _i in n:
		await physics_frame


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


func _region_ids() -> Array[StringName]:
	return _wd().call("region_ids") as Array[StringName]


func _active_by_region(species_id: StringName) -> Dictionary:
	var out := {}
	for rid in _region_ids():
		out[String(rid)] = int(_wd().call("region_active_count", rid, species_id))
	return out


func _assert_consistency(key: String) -> void:
	var wd := _wd()
	if not wd.has_method("ledger_consistency"):
		_assert(key, "true", "API 缺失", false)
		return
	var rows: Array = wd.call("ledger_consistency")
	var bad: Array[String] = []
	for raw in rows:
		var r: Dictionary = raw
		if not bool(r.get("ok", false)):
			bad.append("%s|%s a=%s t=%s" % [r.get("region_id", ""), r.get("species_id", ""),
				r.get("active", -1), r.get("total", -1)])
	_assert(key, "全部 active<=total", str(bad), bad.is_empty())


func _all_in_region() -> bool:
	for b in _entry.ecology.tracked_bodies():
		if String(_wd().call("region_id_at", b.global_position)) == "":
			return false
	return true


func _assert_bodies_match_active(key: String, species_id: StringName) -> void:
	var per := _active_by_region(species_id)
	var actual := {}
	for b in _entry.ecology.npc_bodies():
		if b.species_config != null and b.species_config.species_id == species_id:
			var rid := String(_wd().call("region_id_at", b.global_position))
			actual[rid] = int(actual.get(rid, 0)) + 1
	var same := true
	for rid in per.keys():
		if int(per.get(rid, 0)) != int(actual.get(rid, 0)):
			same = false
	_assert(key, str(per), str(actual), same)


func _kill_player() -> void:
	if _entry.player == null or not is_instance_valid(_entry.player):
		return
	_entry.player.survival.apply_damage(999.0, &"t040_test")
	await _advance_frames(4)


## 等一次**真正完成**的布置（`is_setup_done()` 在导航未就绪时就为 true，但 `note` 仍是
## `nav_not_ready`/`retry_pending`，由 `_physics_process` 稍后重试）——只等 done 会读到 0 只。
func _wait_ecology() -> void:
	for _i in 240:
		if _entry.ecology != null and _entry.ecology.is_setup_done():
			var note := String((_entry.ecology.spawn_report() as Dictionary).get("note", ""))
			if note != "nav_not_ready" and note != "retry_pending":
				return
		await _advance_physics(1)


## 把 Mouse 总量按区域改写（Courtyard/Creek/Roots/Grass），只动 `total_count`。
func _set_mouse_totals(raw: Dictionary, courtyard: int, creek: int, roots: int, grass: int) -> void:
	for r in (raw.get("regions", []) as Array):
		var rec: Dictionary = r
		if String(rec.get("species_id", "")) != "Mouse":
			continue
		var n := 0
		match String(rec.get("region_id", "")):
			"Courtyard": n = courtyard
			"Creek": n = creek
			"Roots": n = roots
			"Grass": n = grass
		if String(rec.get("region_id", "")) in ["Courtyard", "Creek", "Roots", "Grass"]:
			rec["total_count"] = n


## 让读档后的玩家换成指定物种并落在指定位置（其余快照键保持不变）。
func _restore_as(raw: Dictionary, species_id: StringName, pos: Vector3) -> void:
	var life: Dictionary = raw["current_life"]
	life["species_id"] = String(species_id)
	life["transform"] = Transform3D(Basis(), pos)
	life["start_position"] = pos
	raw["pending_settlement_life_id"] = ""


func _spawn_marker(species_id: StringName) -> Vector3:
	for n in get_nodes_in_group("spawn_points"):
		var m := n as Node3D
		if m != null and StringName(m.get_meta("species", &"")) == species_id:
			return m.global_position
	return Vector3(0.0, 1.0, 0.0)


func _raw_snapshot() -> Dictionary:
	var raw: Dictionary = _sm().call("build_snapshot", &"t040_probe")
	raw["pending_settlement_life_id"] = ""
	return raw


func _load_status() -> String:
	return String(_sm().get("last_status"))


## 读档后**立即**记录的玩家落点（用于与 resolve 结果比对；之后物理帧可能让身体微沉）。
var _applied_player_pos := Vector3.ZERO
var _applied_player_present := false


func _apply_raw(raw: Dictionary) -> void:
	await _kill_player()
	var checked: Dictionary = _sm().call("validate", raw)
	if String(checked.get("status", "")) != "ok":
		print("T040|apply|validate=%s" % String(checked.get("status", "")))
		return
	_entry.call("apply_saved_snapshot", checked.get("snapshot", {}), true)
	_applied_player_present = _entry.player != null
	_applied_player_pos = _entry.player.global_position if _applied_player_present else Vector3.ZERO
	await _advance_frames(4)
	await _wait_ecology()


func _spawn_probe_body(cfg: SpeciesConfig, pos: Vector3) -> AnimalBody:
	var packed := load(BODY_SCENE) as PackedScene
	var body := packed.instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = false
	body.ai_enabled = false
	_entry.level.add_child(body)
	body.global_position = pos
	body.velocity = Vector3.ZERO
	await _advance_frames(1)
	return body


func _first_alive_npc(species_id: StringName) -> AnimalBody:
	for b in _entry.ecology.npc_bodies():
		if b.species_config != null and b.species_config.species_id == species_id:
			return b
	return null


func _ledger_rec(region_id: String, species_id: String) -> Dictionary:
	for raw in (_wd().call("region_population_snapshot") as Array):
		var r: Dictionary = raw
		if String(r.get("region_id", "")) == region_id and String(r.get("species_id", "")) == species_id:
			return r
	return {}


func _is_legal(cfg: SpeciesConfig, pos: Vector3) -> bool:
	if not _finite(pos) or cfg == null:
		return false
	if String(_wd().call("region_id_at", pos)) == "" or _over_water(pos):
		return false
	if _inside_static(cfg, pos):
		return false
	var map := _entry.get_world_3d().get_navigation_map()
	var layer := _nav_layer(cfg.species_id)
	var p: PackedVector3Array = NavigationServer3D.map_get_path(map, pos,
		pos + Vector3(0.05, 0.0, 0.0), true, maxi(1, layer))
	if p.size() < 1:
		return false
	return p[0].distance_to(pos) <= 0.61


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _over_water(pos: Vector3) -> bool:
	for n in get_nodes_in_group("water_bodies"):
		var m := n as MeshInstance3D
		if m == null:
			continue
		var aabb := m.get_aabb()
		var c := m.global_transform * aabb.get_center()
		var half := aabb.size * m.global_transform.basis.get_scale() * 0.5
		if absf(pos.x - c.x) <= half.x and absf(pos.z - c.z) <= half.z:
			return true
	return false


func _inside_static(cfg: SpeciesConfig, pos: Vector3) -> bool:
	var space := _entry.get_world_3d().direct_space_state
	if space == null:
		return false
	var probe := SphereShape3D.new()
	probe.radius = maxf(0.02, mini(cfg.capsule_radius - 0.02, 0.18))
	var center := pos + Vector3(0.0, cfg.capsule_half_height * 0.6, 0.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = 1
	params.collide_with_bodies = true
	return not space.intersect_shape(params, 1).is_empty()


func _nav_layer(species_id: StringName) -> int:
	if _entry != null and _entry.level != null:
		var layer := _find_layer(_entry.level, species_id)
		if layer > 0:
			return layer
	return 1


func _find_layer(node: Node, species_id: StringName) -> int:
	if node is NavigationRegion3D:
		var reg := node as NavigationRegion3D
		if StringName(reg.get_meta("species_id", &"")) == species_id:
			return maxi(1, reg.navigation_layers)
	for child in node.get_children():
		var layer := _find_layer(child, species_id)
		if layer > 0:
			return layer
	return 0


func _safe_distances_ok() -> Dictionary:
	var worst := INF
	var overlaps := 0
	var detail := ""
	var player: AnimalBody = _entry.player
	if player == null or not is_instance_valid(player):
		return {"ok": false, "overlaps": overlaps, "detail": "no_player"}
	for b in _entry.ecology.npc_bodies():
		var need := _entry.ecology.min_distance_for(b.species_config)
		var d := b.global_position.distance_to(player.global_position)
		if d < worst:
			worst = d
			detail = "%s d=%.2f need=%.2f" % [String(b.species_config.species_id), d, need]
		if d < need - 0.01:
			return {"ok": false, "overlaps": overlaps, "detail": detail, "min": d, "need": need}
		if d < b.species_config.capsule_radius + player.species_config.capsule_radius + 0.02:
			overlaps += 1
	return {"ok": true, "overlaps": overlaps, "detail": "min=%s" % detail}
