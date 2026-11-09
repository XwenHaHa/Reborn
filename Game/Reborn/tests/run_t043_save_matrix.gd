extends SceneTree
## T043 存档测试矩阵 —— 只补 T037～T042 未覆盖的格子（对应 `Docs/Tasks/T043.md` §6）。
##
## A 资源/区域往返补齐；B 修订链单调；C 跨世连续性；D SETTLING/SELECTING 期保存。
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t043_save_matrix.gd' --quit-after 600000
## 结果口径：RESULT|pass=<n>|fail=<n>。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const TEST_DIR := "user://t043_tests"
const SAVE_PATH := "user://t043_tests/savegame_v1.json"
const EPS := 1e-6
const RESOURCE_ID := "t043_probe_resource"

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _entry: MainEntry = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await _advance_frames(1)
	_clean_dir()
	var sm := _sm()
	if sm != null:
		sm.set("allow_headless_writes", true)
		sm.call("set_save_path", SAVE_PATH)

	await _section_a_roundtrip()
	await _section_b_revision_chain()
	await _section_c_cross_life()
	await _section_d_phase_saves()

	_cleanup_scene()
	await _advance_frames(2)
	if paused:
		paused = false
	_clean_dir()
	_summary()
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------------------
# A 往返补齐：资源 next_refill_at/expire_at、区域 next_recover_at、世界时间
# ---------------------------------------------------------------------------

func _section_a_roundtrip() -> void:
	await _reset()
	await _load_main()
	if _entry == null:
		_assert("A0_entry", "MainEntry", "null", false)
		return
	var picked := _entry.select_species(&"Cat")
	await _advance_frames(8)
	_assert("A1_select_cat", "true", str(picked), picked)
	if not picked:
		return

	# 世界时间 + 长期层探针
	var wd := _wd()
	if wd != null and wd.has_method("set_world_time"):
		wd.call("set_world_time", 250.0)
	var gs := _gs()
	var disc_first: bool = bool(gs.call("record_place_discovery", &"Creek", 250.0))
	var unlock_first: bool = bool(gs.call("unlock_species", &"Mouse"))
	_assert("A2_discovery_recorded", "true", str(disc_first), disc_first)
	_assert("A3_unlock_recorded", "true", str(unlock_first), unlock_first)

	var rp := _ensure_test_resource()
	if rp == null:
		_assert("A4_resource_fixture", "非 null", "null", false)
		return
	rp.interaction_id = RESOURCE_ID
	rp.units = 2
	rp.capacity = 5
	rp.refill_interval = 4.0
	rp.next_refill_at = 1000.25
	rp.expire_at = 999.5
	rp.food_type = 2
	rp.infinite = false
	rp.auto_advance = false
	_assert("A5_resource_fixture", RESOURCE_ID, String(rp.interaction_id),
		String(rp.interaction_id) == RESOURCE_ID)

	var region := _first_region_with_capacity()
	if region.is_empty():
		_assert("A6_region_fixture", "存在", "空", false)
		return
	region["total_count"] = maxi(0, int(region.get("capacity", 1)) - 1)
	region["recover_interval"] = 3.0
	region["next_recover_at"] = 777.5

	var save1: Dictionary = _entry.call("save_now", &"matrix_base")
	await _advance_frames(1)
	_assert("A7_save_ok", "true", str(save1.get("ok", false)), bool(save1.get("ok", false)))
	var saved := _saved_json()
	_assert("A8_world_time_saved", "250.0", str(saved.get("world_time", null)),
		absf(float(saved.get("world_time", -1.0)) - 250.0) <= EPS)
	var saved_res := _record_by_id(saved.get("resources", []), RESOURCE_ID)
	_assert("A9_res_units", "2", str(saved_res.get("units", null)), int(saved_res.get("units", -1)) == 2)
	_assert("A10_res_next_refill", "1000.25", str(saved_res.get("next_refill_at", null)),
		absf(float(saved_res.get("next_refill_at", -1.0)) - 1000.25) <= EPS)
	_assert("A11_res_expire_at", "999.5", str(saved_res.get("expire_at", null)),
		absf(float(saved_res.get("expire_at", -1.0)) - 999.5) <= EPS)
	_assert("A12_res_capacity", "5", str(saved_res.get("capacity", null)),
		int(saved_res.get("capacity", -1)) == 5)
	var saved_region := _region_by_key(saved.get("regions", []), String(region.get("key", "")))
	_assert("A13_region_next_recover", "777.5", str(saved_region.get("next_recover_at", null)),
		absf(float(saved_region.get("next_recover_at", -1.0)) - 777.5) <= EPS)
	_assert("A14_region_interval", "3.0", str(saved_region.get("recover_interval", null)),
		absf(float(saved_region.get("recover_interval", -1.0)) - 3.0) <= EPS)
	_assert("A15_discovered_saved", "Creek", str(saved.get("discovered_ids", [])),
		(saved.get("discovered_ids", []) as Array).has("Creek"))
	_assert("A16_unlocked_saved", "Mouse", str(saved.get("unlocked_species", [])),
		(saved.get("unlocked_species", []) as Array).has("Mouse"))
	_assert("A17_contract_keys", "14", str(saved.size()), saved.size() == 14)

	# 真重载：走 MainEntry 的读档装配，而不是只看 JSON
	await _reload_main()
	if _entry == null:
		_assert("A18_reload_entry", "MainEntry", "null", false)
		return
	_assert("A19_world_time_restored", "≈250.0", str(_entry.world_time_now()),
		absf(_entry.world_time_now() - 250.0) <= 0.05)
	var rp2 := _resource_node_by_id(RESOURCE_ID)
	_assert("A20_res_node_rebuilt", "非 null", "null", rp2 != null)
	if rp2 != null:
		_assert("A21_res_units_roundtrip", "2", str(rp2.units), rp2.units == 2)
		_assert("A22_res_next_refill_roundtrip", "1000.25", str(rp2.next_refill_at),
			absf(rp2.next_refill_at - 1000.25) <= EPS)
		_assert("A23_res_expire_roundtrip", "999.5", str(rp2.expire_at),
			absf(rp2.expire_at - 999.5) <= EPS)
	var rec2 := _region_by_key(_wd().call("region_population_snapshot"), String(region.get("key", "")))
	_assert("A24_region_next_roundtrip", "777.5", str(rec2.get("next_recover_at", null)),
		absf(float(rec2.get("next_recover_at", -1.0)) - 777.5) <= EPS)
	# 契约（T035 D7）：`capacity/recover_interval` 是配置/关卡数据，不从快照恢复；只证它仍非负。
	_assert("A25_region_interval_config_owned", ">=0", str(rec2.get("recover_interval", null)),
		float(rec2.get("recover_interval", -1.0)) >= 0.0)
	_assert("A26_discovered_restored", "true", str(_gs().call("is_place_discovered", &"Creek")),
		bool(_gs().call("is_place_discovered", &"Creek")))
	_assert("A27_unlocked_restored", "true", str(_gs().call("is_species_unlocked", &"Mouse")),
		bool(_gs().call("is_species_unlocked", &"Mouse")))


# ---------------------------------------------------------------------------
# B 修订链：每次成功保存 revision 恰好 +1，读档不回退
# ---------------------------------------------------------------------------

func _section_b_revision_chain() -> void:
	if _entry == null:
		_assert("B0_entry", "MainEntry", "null", false)
		return
	await _advance_frames(2)
	_assert("B1_loaded_revision", ">0", str(int(_sm_get("revision"))), int(_sm_get("revision")) > 0)
	var reasons: Array[StringName] = [&"manual", &"death", &"discovery", &"unlock", &"exit"]
	var expected := int(_sm_get("revision"))
	for reason in reasons:
		var res: Dictionary = _entry.call("save_now", reason)
		expected += 1
		var file_rev := _file_revision()
		_assert("B2_%s_ok" % String(reason), "true", str(res.get("ok", false)),
			bool(res.get("ok", false)))
		_assert("B3_%s_exact_plus_one" % String(reason), str(expected), str(file_rev),
			file_rev == expected)
		_assert("B4_%s_reason" % String(reason), String(reason),
			String(_saved_json().get("saved_reason", "")),
			String(_saved_json().get("saved_reason", "")) == String(reason))
	_assert("B5_revision_monotonic", "≥%d" % expected, str(int(_sm_get("revision"))),
		int(_sm_get("revision")) >= expected)


# ---------------------------------------------------------------------------
# C 跨世连续性：世界时间不重置、发现去重、解锁永久、life_counter 递增
# ---------------------------------------------------------------------------

func _section_c_cross_life() -> void:
	if _entry == null or not _entry.lifecycle.is_alive():
		# 重载后停在主菜单：先点「继续」恢复上一世
		if _entry != null:
			var resumed: Variant = _entry.call("continue_game")
			await _advance_frames(6)
			_assert("C0_resume", "true", str(resumed), bool(resumed))
	if _entry == null or not _entry.lifecycle.is_alive():
		_assert("C1_alive_precondition", "alive", _entry.lifecycle_state_name() if _entry != null else "null", false)
		return
	var world_before := _entry.world_time_now()
	var life_counter_before := int(_gs().get("_life_counter"))
	var disc_before := (_gs().call("discovered_place_list") as Array).size()
	var old_life := _entry.current_life_id()
	_entry.lifecycle.end_life(&"died", {"damage_reason": "matrix_cross_life"})
	await _advance_frames(4)
	_assert("C2_died", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")
	_entry.dismiss_settle()
	await _advance_frames(2)
	var respawned := _entry.select_species(&"Cat")
	await _advance_frames(6)
	_assert("C3_respawn", "true", str(respawned), respawned)
	_assert("C4_alive", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_assert("C5_life_changed", old_life, _entry.current_life_id(),
		_entry.current_life_id() != old_life)
	_assert("C6_life_counter_plus_one", str(life_counter_before + 1),
		str(int(_gs().get("_life_counter"))), int(_gs().get("_life_counter")) == life_counter_before + 1)
	_assert("C7_world_time_not_reset", "≥%.2f" % world_before, str(_entry.world_time_now()),
		_entry.world_time_now() >= world_before - EPS)
	var discovered := _gs().call("discovered_place_list") as Array
	_assert("C8_discovery_dedup", str(disc_before), str(discovered.size()), discovered.size() == disc_before)
	_assert("C9_unlock_permanent", "true", str(_gs().call("is_species_unlocked", &"Mouse")),
		bool(_gs().call("is_species_unlocked", &"Mouse")))


# ---------------------------------------------------------------------------
# D 阶段期保存：SETTLING / SELECTING 期间请求保存不产生脏 current_life
# ---------------------------------------------------------------------------

func _section_d_phase_saves() -> void:
	if _entry == null or not _entry.lifecycle.is_alive():
		_assert("D0_alive_precondition", "alive", _entry.lifecycle_state_name() if _entry != null else "null", false)
		return
	var rev0 := int(_sm_get("revision"))
	var archive_before := _archive_count()
	_entry.lifecycle.end_life(&"died", {"damage_reason": "matrix_phase"})
	await _advance_frames(3)
	_assert("D1_settling", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")
	_assert("D2_settle_presenting", "true", str(_settle_presenting()), _settle_presenting())
	var settle_save: Dictionary = _entry.call("save_now", &"settle_phase_probe")
	await _advance_frames(1)
	_assert("D3_settle_save_ok", "true", str(settle_save.get("ok", false)), bool(settle_save.get("ok", false)))
	_assert("D4_settle_revision_plus", str(rev0 + 1), str(int(_sm_get("revision"))),
		int(_sm_get("revision")) >= rev0 + 1)
	_assert("D5_settle_no_current_life", "0",
		str((_saved_json().get("current_life", {}) as Dictionary).size()),
		(_saved_json().get("current_life", {}) as Dictionary).is_empty())

	_entry.dismiss_settle()
	await _advance_frames(2)
	var select_rev := int(_sm_get("revision"))
	var select_save: Dictionary = _entry.call("save_now", &"selecting_probe")
	await _advance_frames(1)
	_assert("D6_selecting_save_ok", "true", str(select_save.get("ok", false)),
		bool(select_save.get("ok", false)))
	_assert("D7_selecting_revision_plus", str(select_rev + 1), str(int(_sm_get("revision"))),
		int(_sm_get("revision")) >= select_rev + 1)
	_assert("D8_selecting_no_current_life", "0",
		str((_saved_json().get("current_life", {}) as Dictionary).size()),
		(_saved_json().get("current_life", {}) as Dictionary).is_empty())
	_assert("D9_saved_pending_empty", "", String(_saved_json().get("pending_settlement_life_id", "?")),
		String(_saved_json().get("pending_settlement_life_id", "?")) == "")
	_assert("D10_archive_has_record", str(archive_before + 1), str(_archive_count()),
		_archive_count() == archive_before + 1)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _reset() -> void:
	_cleanup_scene()
	await _advance_frames(3)
	_clean_dir()
	var sm := _sm()
	if sm != null:
		sm.call("set_save_path", SAVE_PATH)
	if paused:
		paused = false


func _load_main() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_assert("LOAD|scene", "可加载", "null", false)
		return
	change_scene_to_packed(packed)
	await _advance_frames(8)
	_entry = current_scene as MainEntry
	if _entry != null:
		_entry.set_persistence_enabled(true)


func _reload_main() -> void:
	_cleanup_scene()
	await _advance_frames(3)
	await _load_main()


func _cleanup_scene() -> void:
	if _entry != null and is_instance_valid(_entry):
		_entry.set_persistence_enabled(false)
		_entry.queue_free()
	if current_scene != null:
		current_scene = null
	_entry = null


func _clean_dir() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(TEST_DIR)
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(TEST_DIR.path_join(String(f)))
	DirAccess.remove_absolute(SAVE_PATH)
	DirAccess.remove_absolute(SAVE_PATH + ".bak")


func _sm() -> Node:
	return root.get_node_or_null("/root/SaveManager")


func _gs() -> Node:
	return root.get_node_or_null("/root/GameState")


func _wd() -> Node:
	return root.get_node_or_null("/root/WorldDirector")


func _sm_get(field: String) -> Variant:
	var sm := _sm()
	return sm.get(field) if sm != null else null


func _ensure_test_resource() -> ResourcePoint:
	for n in get_nodes_in_group("resource_points"):
		var rp := n as ResourcePoint
		if rp != null and not rp.infinite:
			return rp
	if _entry == null or _entry.level == null:
		return null
	var packed := load("res://scenes/world/resource_point.tscn") as PackedScene
	if packed == null:
		return null
	var rp2 := packed.instantiate() as ResourcePoint
	if rp2 == null:
		return null
	rp2.name = "T043TestResource"
	_entry.level.add_child(rp2)
	return rp2


func _first_region_with_capacity() -> Dictionary:
	var raw = _wd().get("region_records") if _wd() != null else null
	if raw is Dictionary:
		for k in (raw as Dictionary).keys():
			var rec: Dictionary = (raw as Dictionary)[k]
			if int(rec.get("capacity", 0)) > 0:
				rec["key"] = String(k)
				return rec
	return {}


func _resource_node_by_id(id: String) -> ResourcePoint:
	for n in get_nodes_in_group("resource_points"):
		var rp := n as ResourcePoint
		if rp != null and String(rp.interaction_id) == id:
			return rp
	return null


func _record_by_id(records: Variant, id: String) -> Dictionary:
	if records is Array:
		for raw in (records as Array):
			if raw is Dictionary and String((raw as Dictionary).get("id", "")) == id:
				return raw
	return {}


func _region_by_key(records: Variant, key: String) -> Dictionary:
	var region_id := ""
	var species_id := ""
	var sep := key.find("|")
	if sep >= 0:
		region_id = key.substr(0, sep)
		species_id = key.substr(sep + 1)
	if records is Array:
		for raw in (records as Array):
			if not (raw is Dictionary):
				continue
			var rec: Dictionary = raw
			if String(rec.get("region_id", "")) == region_id and String(rec.get("species_id", "")) == species_id:
				return rec
	return {}


func _settle_presenting() -> bool:
	return _entry != null and _entry.settle_panel != null and bool(_entry.settle_panel.call("is_presenting"))


func _archive_count() -> int:
	return int(_gs().call("archive_count")) if _gs() != null else -1


func _save_text() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return ""
	return FileAccess.get_file_as_string(SAVE_PATH)


func _saved_json() -> Dictionary:
	var parsed = JSON.parse_string(_save_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _file_revision() -> int:
	return int(_saved_json().get("revision", -1))


func _advance_frames(n: int) -> void:
	for _i in n:
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
	print("RESULT|pass=%d|fail=%d|failed=%s" % [_pass, _fail, "|".join(_failed)])
