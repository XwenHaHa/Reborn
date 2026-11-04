extends SceneTree
## T040b 挂账收口 —— 先写可失败断言（对应 `Docs/Tasks/T040b.md` §6）。
##
## 覆盖：
##   A 自然死亡扣账（幂等、下限 0、未登记不扣、玩家不扣、与捕获不重复）
##   B 恢复计时（死亡不改已有 next；满容量死亡后由 advance_to 起算）
##   C 读档/重生不复活（快照保留已扣值、重建不超 total）
##   D 12 m 内不退场（近处保留 + pending、走远后收敛、退场不扣账）
##   E 信号与重试（自然死亡触发收敛；玩家走远后低频重试）
##   F 兼容（14 键 / save_version=1 / T035 与 T040 API 不变）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t040b_ledger_closeout.gd' --quit-after 300000
## 结果口径：RESULT|pass=<n>|fail=<n>。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CAT_ID := &"Cat"
const MOUSE_ID := &"Mouse"
const REGION_IDS: Array[String] = ["Courtyard", "Creek", "Roots", "Grass"]

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _entry: MainEntry = null
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null
var _death_signal_count := 0
var _dead_region := ""
var _dead_total_before := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await _advance_frames(1)
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
	var accepted := _entry.select_species(CAT_ID)
	_assert("A0_spawn", "accepted/setup", "accepted=%s" % accepted,
		accepted and _entry.ecology != null)
	await _wait_ecology()
	# 冻结 NPC AI：避免猫 NPC 在测试等待期间攻击鼠，让 A 段的“谁死、扣多少”可控。
	for b in _entry.ecology.npc_bodies():
		b.ai_enabled = false
	if _wd().has_signal("region_natural_death"):
		_wd().connect("region_natural_death", _on_region_natural_death)

	await _section_a_natural_death()
	await _section_c_no_resurrection()
	await _section_b_recovery_timing()
	await _section_d_twelve_meter_retention()
	await _section_e_signal_and_retry()
	await _section_f_compat()

	_entry.queue_free()
	await _advance_frames(2)
	_summary()
	quit(0 if _fail == 0 else 1)


func _on_region_natural_death(_body_id: String, _region_id: String, _species_id: String,
		_reason: StringName, _world_time: float) -> void:
	_death_signal_count += 1


# ---------------------------------------------------------------------------
# A 自然死亡扣账
# ---------------------------------------------------------------------------

func _section_a_natural_death() -> void:
	print("---- A 自然死亡扣账 ----")
	_assert("A1_api", "true", str(_wd().has_method("report_natural_death")),
		_wd().has_method("report_natural_death"))
	var npc := _first_alive_npc(MOUSE_ID)
	_assert("A2_target", "存在", str(npc), npc != null)
	if npc == null:
		return
	var rid := StringName(String(_wd().call("region_id_at", npc.global_position)))
	var sid: StringName = npc.species_config.species_id
	_dead_region = String(rid)
	_dead_total_before = int(_wd().call("region_total", rid, sid))
	var active_before := int(_wd().call("region_active_count", rid, sid))
	npc.survival.apply_damage(9999.0, &"t040b_natural")
	await _advance_frames(2)
	_assert("A3_total_minus_one", "%d" % (_dead_total_before - 1),
		str(_wd().call("region_total", rid, sid)),
		int(_wd().call("region_total", rid, sid)) == _dead_total_before - 1)
	_assert("A4_active_minus_one", "%d" % (active_before - 1),
		str(_wd().call("region_active_count", rid, sid)),
		int(_wd().call("region_active_count", rid, sid)) == active_before - 1)
	var death: Dictionary = _last_death()
	_assert("A5_death_report", "registered/total 同减",
		"reg=%s tb=%s ta=%s ab=%s aa=%s" % [death.get("registered", null),
			death.get("total_before", null), death.get("total_after", null),
			death.get("active_before", null), death.get("active_after", null)],
		bool(death.get("registered", false)) \
			and int(death.get("total_before", -1)) == _dead_total_before \
			and int(death.get("total_after", -2)) == _dead_total_before - 1 \
			and int(death.get("active_before", -1)) == active_before \
			and int(death.get("active_after", -2)) == active_before - 1)
	var again: Dictionary = _wd().call("report_natural_death", npc, &"t040b_again") \
		if _wd().has_method("report_natural_death") else {}
	_assert("A6_idempotent", "registered=false", str(again.get("registered", null)),
		not bool(again.get("registered", true)))
	_assert("A7_idempotent_total", "%d" % (_dead_total_before - 1),
		str(_wd().call("region_total", rid, sid)),
		int(_wd().call("region_total", rid, sid)) == _dead_total_before - 1)

	# 下限 0：账本已经是 0 时，死亡仍不产生负数。
	_set_total(&"Grass", MOUSE_ID, 0, 0.0)
	var floor_probe: AnimalBody = await _spawn_probe_body(_mouse, Vector3(0.0, 0.4, -6.0))
	var floor_sid := floor_probe.source_id()
	var floor_reg: bool = _wd().call("register_region_body", &"Grass", MOUSE_ID, floor_probe)
	_assert("A8_floor_registered", "true", str(floor_reg), floor_reg)
	floor_probe.survival.apply_damage(9999.0, &"t040b_floor")
	await _advance_frames(2)
	_assert("A9_floor_zero", "0", str(_wd().call("region_total", &"Grass", MOUSE_ID)),
		int(_wd().call("region_total", &"Grass", MOUSE_ID)) == 0)
	var floor_death: Dictionary = _last_death()
	_assert("A10_floor_report", "total_after=0", str(floor_death.get("total_after", null)),
		int(floor_death.get("total_after", -1)) == 0)

	# 未登记个体死亡：不扣。
	_set_total(&"Creek", MOUSE_ID, 2, 0.0)
	var stray: AnimalBody = await _spawn_probe_body(_mouse, Vector3(0.0, 0.4, -6.0))
	stray.survival.apply_damage(9999.0, &"t040b_stray")
	await _advance_frames(2)
	_assert("A11_unregistered_no_deduct", "2", str(_wd().call("region_total", &"Creek", MOUSE_ID)),
		int(_wd().call("region_total", &"Creek", MOUSE_ID)) == 2)
	_assert("A12_unregistered_report", "false", str(_last_death()),
		not bool(_last_death().get("registered", true)))

	# 玩家死亡不是区域个体死亡：账本不动。
	var totals_before := int(_wd().call("region_population_totals", MOUSE_ID))
	var player_rep: Dictionary = {}
	if _wd().has_method("report_natural_death"):
		var raw_rep = _wd().call("report_natural_death", _entry.player, &"player")
		player_rep = raw_rep if raw_rep is Dictionary else {}
	_assert("A13_player_no_deduct", str(totals_before),
		str(_wd().call("region_population_totals", MOUSE_ID)),
		int(_wd().call("region_population_totals", MOUSE_ID)) == totals_before \
			and not bool(player_rep.get("registered", true)))

	# 捕获后死亡：不重复扣。
	_set_total(&"Roots", MOUSE_ID, 2, 0.0)
	var captured: AnimalBody = await _spawn_probe_body(_mouse, Vector3(20.0, 0.4, 8.0))
	var cap_reg: bool = _wd().call("register_region_body", &"Roots", MOUSE_ID, captured)
	_assert("A14_capture_registered", "true", str(cap_reg), cap_reg)
	var cap_sid := captured.source_id()
	var cap_before := int(_wd().call("region_total", &"Roots", MOUSE_ID))
	var cap_ok: bool = _wd().call("report_capture", _entry.player.source_id(), cap_sid,
		captured.global_position, float(_wd().get("world_time")))
	captured.call("mark_captured", _entry.player.source_id())
	_assert("A15_capture_deduct", "%d" % (cap_before - 1), str(_wd().call("region_total", &"Roots", MOUSE_ID)),
		cap_ok and int(_wd().call("region_total", &"Roots", MOUSE_ID)) == cap_before - 1)
	var after_capture := int(_wd().call("region_total", &"Roots", MOUSE_ID))
	_wd().call("report_natural_death", captured, &"after_capture")
	_assert("A16_capture_then_death_noop", str(after_capture),
		str(_wd().call("region_total", &"Roots", MOUSE_ID)),
		int(_wd().call("region_total", &"Roots", MOUSE_ID)) == after_capture)

	# 先死亡再上报捕获：同样不重复扣。
	_set_total(&"Creek", MOUSE_ID, 2, 0.0)
	var dead_first: AnimalBody = await _spawn_probe_body(_mouse, Vector3(0.0, 0.4, -6.0))
	var dead_reg: bool = _wd().call("register_region_body", &"Creek", MOUSE_ID, dead_first)
	var dead_sid := dead_first.source_id()
	var before_death := int(_wd().call("region_total", &"Creek", MOUSE_ID))
	dead_first.survival.apply_damage(9999.0, &"t040b_dead_first")
	await _advance_frames(2)
	var after_death := int(_wd().call("region_total", &"Creek", MOUSE_ID))
	_assert("A17_death_first_deduct", "%d" % (before_death - 1), str(after_death),
		dead_reg and after_death == before_death - 1)
	var late_capture: bool = _wd().call("report_capture", _entry.player.source_id(), dead_sid,
		dead_first.global_position, float(_wd().get("world_time")))
	_assert("A18_death_then_capture_noop", str(after_death),
		str(_wd().call("region_total", &"Creek", MOUSE_ID)),
		late_capture and int(_wd().call("region_total", &"Creek", MOUSE_ID)) == after_death)
	_assert_consistency("A19_consistency")


# ---------------------------------------------------------------------------
# B 恢复计时
# ---------------------------------------------------------------------------

func _section_b_recovery_timing() -> void:
	print("---- B 恢复计时 ----")
	var wd := _wd()
	_set_total(&"Creek", MOUSE_ID, 3, 1000.0)
	var cap := _region_capacity(&"Creek", MOUSE_ID)
	var probe: AnimalBody = await _spawn_probe_body(_mouse, Vector3(0.0, 0.4, -6.0))
	var reg: bool = wd.call("register_region_body", &"Creek", MOUSE_ID, probe)
	probe.survival.apply_damage(9999.0, &"t040b_recover")
	await _advance_frames(2)
	_assert("B1_death_keeps_next", "1000", str(_region_rec(&"Creek", MOUSE_ID).get("next_recover_at", null)),
		reg and is_equal_approx(float(_region_rec(&"Creek", MOUSE_ID).get("next_recover_at", -1.0)), 1000.0))
	_assert("B2_death_total", "2", str(wd.call("region_total", &"Creek", MOUSE_ID)),
		int(wd.call("region_total", &"Creek", MOUSE_ID)) == 2)
	if wd.has_method("region_population_advance_to"):
		wd.call("region_population_advance_to", 1000.5)
	_assert("B3_recover_to_three", "3", str(wd.call("region_total", &"Creek", MOUSE_ID)),
		int(wd.call("region_total", &"Creek", MOUSE_ID)) == 3)
	_assert("B4_next_advanced", ">1000", str(_region_rec(&"Creek", MOUSE_ID).get("next_recover_at", null)),
		float(_region_rec(&"Creek", MOUSE_ID).get("next_recover_at", -1.0)) > 1000.0)

	# 满容量（next=0）死亡后：空额由既有 advance_to 起算。
	_set_total(&"Creek", MOUSE_ID, cap, 0.0)
	var full_probe: AnimalBody = await _spawn_probe_body(_mouse, Vector3(0.0, 0.4, -6.0))
	var full_reg: bool = wd.call("register_region_body", &"Creek", MOUSE_ID, full_probe)
	full_probe.survival.apply_damage(9999.0, &"t040b_full")
	await _advance_frames(2)
	_assert("B5_full_death_total", "%d" % (cap - 1), str(wd.call("region_total", &"Creek", MOUSE_ID)),
		full_reg and int(wd.call("region_total", &"Creek", MOUSE_ID)) == cap - 1)
	_assert("B6_full_death_next_zero", "0", str(_last_death().get("next_recover_at", null)),
		is_equal_approx(float(_last_death().get("next_recover_at", -1.0)), 0.0))
	var now := float(wd.get("world_time"))
	if wd.has_method("region_population_advance_to"):
		wd.call("region_population_advance_to", now + 0.5)
	_assert("B7_empty_slot_schedules", ">0", str(_region_rec(&"Creek", MOUSE_ID).get("next_recover_at", null)),
		float(_region_rec(&"Creek", MOUSE_ID).get("next_recover_at", -1.0)) > 0.0)
	_assert("B8_death_no_active_respawn", "0", str(wd.call("region_active_count", &"Creek", MOUSE_ID)),
		int(wd.call("region_active_count", &"Creek", MOUSE_ID)) == 0)


# ---------------------------------------------------------------------------
# C 读档/重生不复活
# ---------------------------------------------------------------------------

func _section_c_no_resurrection() -> void:
	print("---- C 读档/重生不复活 ----")
	var wd := _wd()
	var rows: Array = wd.call("region_population_snapshot")
	var row: Dictionary = {}
	for raw in rows:
		var rec: Dictionary = raw
		if String(rec.get("region_id", "")) == _dead_region \
				and String(rec.get("species_id", "")) == "Mouse":
			row = rec
	_assert("C1_snapshot_has_dead_region", "true", str(row.size() > 0), row.size() > 0)
	_assert("C2_snapshot_reduced", "%d" % (_dead_total_before - 1),
		str(row.get("total_count", null)),
		int(row.get("total_count", -1)) == _dead_total_before - 1)
	var dead_rid := StringName(_dead_region)
	var restored: Dictionary = wd.call("restore_region_population", rows) \
		if wd.has_method("restore_region_population") else {}
	_assert("C3_restore_keeps_reduced", "%d" % (_dead_total_before - 1),
		str(wd.call("region_total", dead_rid, MOUSE_ID)),
		int(wd.call("region_total", dead_rid, MOUSE_ID)) == _dead_total_before - 1)
	_assert("C4_restore_report", "restored≥1", str(restored.get("restored", null)),
		int(restored.get("restored", 0)) >= 1)

	# 清场 + 按账本重建：只生成 total 允许的数量，死亡个体不回来。
	_set_total(dead_rid, MOUSE_ID, _dead_total_before - 1, 0.0)
	for rid in REGION_IDS:
		if rid != _dead_region:
			_set_total(StringName(rid), MOUSE_ID, 0, 0.0)
	_entry.ecology.clear()
	await _advance_frames(2)
	if _entry.ecology.has_method("setup"):
		_entry.ecology.setup(_entry.player, _entry.player.global_position)
		await _wait_ecology()
	var expected_total := _dead_total_before - 1
	_assert("C5_rebuild_total", "%d" % expected_total,
		str(wd.call("region_population_totals", MOUSE_ID)),
		int(wd.call("region_population_totals", MOUSE_ID)) == expected_total)
	_assert("C6_rebuild_no_extra", "≤%d" % expected_total,
		str(_entry.ecology.npc_count_of(MOUSE_ID)),
		_entry.ecology.npc_count_of(MOUSE_ID) <= expected_total)
	_assert_consistency("C7_consistency")


# ---------------------------------------------------------------------------
# D 12 m 内不退场
# ---------------------------------------------------------------------------

func _section_d_twelve_meter_retention() -> void:
	print("---- D 12 m 内不退场 ----")
	var wd := _wd()
	_entry.ecology.clear()
	await _advance_frames(2)
	for rid in REGION_IDS:
		_set_total(StringName(rid), MOUSE_ID, 0, 0.0)
	var near: AnimalBody = await _spawn_probe_body(_mouse, _entry.player.global_position \
		+ Vector3(2.0, 0.0, 0.0))
	var reg: bool = wd.call("register_region_body", &"Courtyard", MOUSE_ID, near)
	var rep: Dictionary = wd.call("reconcile_region_population", _entry.player.global_position)
	_assert("D1_near_retained", "removed=0,pending≥1",
		"removed=%s pending=%s" % [rep.get("removed", -1), rep.get("pending_excess", -1)],
		reg and int(rep.get("removed", -1)) == 0 and int(rep.get("pending_excess", -1)) >= 1)
	_assert("D2_near_body_valid", "true", str(is_instance_valid(near)), is_instance_valid(near))
	_assert("D3_near_active_one", "1", str(wd.call("region_active_count", &"Courtyard", MOUSE_ID)),
		int(wd.call("region_active_count", &"Courtyard", MOUSE_ID)) == 1)
	var pending: Array = rep.get("pending_entries", []) as Array
	_assert("D4_pending_reason", "within_visible_distance",
		str(pending[0].get("reason", "")) if pending.size() > 0 else "<empty>",
		pending.size() > 0 and String(pending[0].get("reason", "")) == "within_visible_distance")
	_assert("D5_pending_count", "1", str(pending[0].get("count", -1)) if pending.size() > 0 else "<empty>",
		pending.size() > 0 and int(pending[0].get("count", -1)) == 1)
	print("VIS|t040b|near_retained|pos=%s|distance=%.2f|pending=%d" % [
		near.global_position, near.global_position.distance_to(_entry.player.global_position),
		int(rep.get("pending_excess", 0))])

	# 玩家原地等 70 帧（触发一次低频重试）：近处个体不得消失。
	await _advance_physics(70)
	_assert("D6_still_valid_after_retry", "true", str(is_instance_valid(near)), is_instance_valid(near))
	_assert("D7_pending_kept", "≥1",
		str((wd.get("last_reconcile") as Dictionary).get("pending_excess", -1)),
		int((wd.get("last_reconcile") as Dictionary).get("pending_excess", -1)) >= 1)

	# 玩家走远：低频重试应把它收敛掉（个体没动，是玩家走远）。
	var old_player_pos := _entry.player.global_position
	_entry.player.global_position = Vector3(20.0, old_player_pos.y, 16.0)
	await _advance_physics(70)
	_assert("D8_far_removed", "invalid", str(is_instance_valid(near)), not is_instance_valid(near))
	_assert("D9_active_zero", "0", str(wd.call("region_active_count", &"Courtyard", MOUSE_ID)),
		int(wd.call("region_active_count", &"Courtyard", MOUSE_ID)) == 0)
	_assert("D10_total_unchanged", "0", str(wd.call("region_total", &"Courtyard", MOUSE_ID)),
		int(wd.call("region_total", &"Courtyard", MOUSE_ID)) == 0)
	_assert("D11_pending_zero", "0", str((wd.get("last_reconcile") as Dictionary).get("pending_excess", -1)),
		int((wd.get("last_reconcile") as Dictionary).get("pending_excess", -1)) == 0)
	_assert("D12_no_visible_removal", "0",
		str(((wd.get("last_reconcile") as Dictionary).get("visible_risk", []) as Array).size()),
		((wd.get("last_reconcile") as Dictionary).get("visible_risk", []) as Array).size() == 0)
	print("VIS|t040b|far_converged|body_valid=%s|pending=%d|player=%s" % [
		str(is_instance_valid(near)),
		int((wd.get("last_reconcile") as Dictionary).get("pending_excess", -1)),
		_entry.player.global_position])


# ---------------------------------------------------------------------------
# E 信号与重试
# ---------------------------------------------------------------------------

func _section_e_signal_and_retry() -> void:
	print("---- E 信号与重试 ----")
	var wd := _wd()
	_set_total(&"Creek", MOUSE_ID, 2, 0.0)
	var probe: AnimalBody = await _spawn_probe_body(_mouse, Vector3(0.0, 0.4, -6.0))
	var reg: bool = wd.call("register_region_body", &"Creek", MOUSE_ID, probe)
	_death_signal_count = 0
	probe.survival.apply_damage(9999.0, &"t040b_signal")
	await _advance_frames(2)
	_assert("E1_death_signal_once", "1", str(_death_signal_count), reg and _death_signal_count == 1)
	_assert("E2_reconcile_after_death", "true", str(wd.get("last_reconcile") is Dictionary),
		wd.get("last_reconcile") is Dictionary)
	_assert("E3_total_after_death", "1", str(wd.call("region_total", &"Creek", MOUSE_ID)),
		int(wd.call("region_total", &"Creek", MOUSE_ID)) == 1)
	_assert_consistency("E4_consistency")


# ---------------------------------------------------------------------------
# F 兼容
# ---------------------------------------------------------------------------

func _section_f_compat() -> void:
	print("---- F 兼容 ----")
	var snap: Dictionary = _sm().call("build_snapshot", &"t040b_f")
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
	_assert("F3_t035_totals_api", "true", str(_wd().has_method("region_population_totals")),
		_wd().has_method("region_population_totals"))
	_assert("F4_t040_resolver_api", "true", str(_entry.has_method("resolve_safe_player_position")),
		_entry.has_method("resolve_safe_player_position"))
	_assert("F5_pending_empty", "",
		str(snap.get("pending_settlement_life_id")),
		String(snap.get("pending_settlement_life_id", "x")) == "")
	_assert_consistency("F6_consistency")


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


func _wait_ecology() -> void:
	for _i in 240:
		if _entry.ecology != null and _entry.ecology.is_setup_done():
			var note := String((_entry.ecology.spawn_report() as Dictionary).get("note", ""))
			if note != "nav_not_ready" and note != "retry_pending":
				return
		await _advance_physics(1)


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
		if b.species_config == null or b.species_config.species_id != species_id:
			continue
		if bool(b.get("captured")):
			continue
		if b.survival != null and b.survival.is_dead():
			continue
		return b
	return null


func _last_death() -> Dictionary:
	var raw = _wd().get("last_natural_death")
	return raw if raw is Dictionary else {}


func _region_rec(region_id: StringName, species_id: StringName) -> Dictionary:
	var recs: Dictionary = _wd().get("region_records") if _wd().get("region_records") is Dictionary else {}
	return recs.get("%s|%s" % [String(region_id), String(species_id)], {})


func _set_total(region_id: StringName, species_id: StringName, total: int, next: float) -> void:
	var recs: Dictionary = _wd().get("region_records") if _wd().get("region_records") is Dictionary else {}
	var key := "%s|%s" % [String(region_id), String(species_id)]
	var rec: Dictionary = recs.get(key, {})
	if rec.is_empty():
		return
	rec["total_count"] = total
	rec["next_recover_at"] = next
	recs[key] = rec


func _region_capacity(region_id: StringName, species_id: StringName) -> int:
	return int(_region_rec(region_id, species_id).get("capacity", 4))


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
