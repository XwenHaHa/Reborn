extends SceneTree
## T038 存档写入队列与关键事务 —— 先写可失败的断言（对应 `Docs/Tasks/T038.md` §6）。
##
## A 队列基础 / B 节流 / C 关键事务 / D 串行 / E 失败注入 / F 读档回退 / G T037 兼容。
## 首跑策略：新 API 一律 `has_method()/call()/get()` 探测；未实现时该段只落红，脚本不崩。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t038_save_queue.gd' --quit-after 600000
## 结果口径：RESULT|pass=<n>|fail=<n>。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const TEST_DIR := "user://t038_tests"
const SAVE_PATH := "user://t038_tests/savegame_v1.json"

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _entry: MainEntry = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await _advance_frames(1)
	_clean_test_dir()
	var sm := _sm()
	sm.set("allow_headless_writes", true)
	sm.call("set_save_path", SAVE_PATH)

	await _section_a_queue()
	await _section_b_throttle()
	await _section_c_critical()
	await _section_d_serial()
	await _section_e_failures()
	await _section_f_load_fallback()
	await _section_g_t037_compat()

	if _entry != null and is_instance_valid(_entry):
		_entry.queue_free()
		_entry = null
	await _advance_frames(2)
	var sm2 := _sm()
	sm2.set("fault_injection", "")
	_clean_test_dir()
	_summary()
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------------------
# A 队列基础
# ---------------------------------------------------------------------------

func _section_a_queue() -> void:
	var sm := _sm()
	_assert("A0_api_request_save", "有 request_save", "缺失",
		sm.has_method("request_save"))
	_assert("A0b_api_stats", "有 queue_stats", "缺失",
		sm.has_method("queue_stats"))
	var ts: Variant = sm.get("throttle_seconds")
	_assert("A1_default_throttle", "1.0", str(ts),
		ts != null and is_equal_approx(float(ts), 1.0))
	_assert("A2_stats_fields", "threaded/active", "缺失",
		not _stat(sm, "threaded", true) and int(_stat(sm, "active_writes", -1)) == 0)

	# 先落一份基线主档，revision=1。
	sm.set("throttle_seconds", 0.0)
	var base: Dictionary = sm.call("save_game", &"a_base")
	var rev0 := int(base.get("revision", 0))
	_assert("A3_baseline_saved", "ok", str(base.get("status", "")),
		String(base.get("status", "")) == "ok")

	# 同帧两次普通请求：队列只保留一个待写槽，实际只写一次。
	var r1 := _request(&"a_norm_1", false)
	var r2 := _request(&"a_norm_2", false)
	_assert("A4_same_frame_single_slot", "1", str(_queue_length(sm)), _queue_length(sm) == 1)
	_assert("A5_second_coalesced", "true", str(r2.get("coalesced", false)),
		bool(r2.get("coalesced", false)))
	_assert("A6_pending_reasons", "1", str(_pending_reasons(sm).size()),
		_pending_reasons(sm).size() == 1)
	await _advance_frames(3)
	var rev1 := _file_revision()
	_assert("A7_one_write_only", "%d" % (rev0 + 1), str(rev1), rev1 == rev0 + 1)
	_assert("A8_queue_drained", "0", str(_queue_length(sm)), _queue_length(sm) == 0)
	_assert("A9_queue_empty_active0", "0", str(int(_stat(sm, "active_writes", -1))),
		int(_stat(sm, "active_writes", -1)) == 0)
	_assert("A10_written_counted", ">=1", str(int(_stat(sm, "written", 0))),
		int(_stat(sm, "written", 0)) >= 1)
	_assert("A11_coalesced_counted", ">=1", str(int(_stat(sm, "coalesced", 0))),
		int(_stat(sm, "coalesced", 0)) >= 1)


# ---------------------------------------------------------------------------
# B 节流
# ---------------------------------------------------------------------------

func _section_b_throttle() -> void:
	var sm := _sm()
	sm.set("throttle_seconds", 0.05)
	# 等过 A 段那次普通写留下的窗口，B 的前缘写才有意义。
	await create_timer(0.12).timeout
	var rev_before := _file_revision()
	# 前缘：第一个普通请求在下一次帧处理时立刻写。
	_request(&"b_lead", false)
	await _advance_frames(2)
	var rev_after_lead := _file_revision()
	_assert("B1_leading_edge_write", "%d" % (rev_before + 1), str(rev_after_lead),
		rev_after_lead == rev_before + 1)

	# 窗口内：两次请求不写，合并为一个待写槽。
	var c0 := int(_stat(sm, "coalesced", 0))
	_request(&"b_window_1", false)
	_request(&"b_window_2", false)
	await _advance_frames(1)
	_assert("B2_no_write_in_window", "%d" % rev_after_lead, str(_file_revision()),
		_file_revision() == rev_after_lead)
	_assert("B3_window_coalesced", ">=%d" % (c0 + 1), str(int(_stat(sm, "coalesced", 0))),
		int(_stat(sm, "coalesced", 0)) >= c0 + 1)
	await create_timer(0.12).timeout
	await _advance_frames(2)
	_assert("B4_one_write_after_window", "%d" % (rev_after_lead + 1), str(_file_revision()),
		_file_revision() == rev_after_lead + 1)

	# 绕过等待：节流窗口内关键请求立即写，revision 当场 +1。
	var rev_bypass := _file_revision()
	var bypass := _request(&"b_bypass_death", true, true)
	_assert("B5_bypass_immediate", "%d" % (rev_bypass + 1), str(_file_revision()),
		_file_revision() == rev_bypass + 1)
	_assert("B6_bypass_status_ok", "ok", str(bypass.get("status", "")),
		String(bypass.get("status", "")) == "ok")
	await _advance_frames(2)
	_assert("B7_bypass_still_serial", "<=1", str(int(_stat(sm, "max_active_writes", 9))),
		int(_stat(sm, "max_active_writes", 9)) <= 1)


# ---------------------------------------------------------------------------
# C 关键事务
# ---------------------------------------------------------------------------

func _section_c_critical() -> void:
	var sm := _sm()
	sm.set("throttle_seconds", 0.0)
	var rev0 := _file_revision()
	var dropped0 := int(_stat(sm, "dropped_normal", 0))
	# 普通 pending + 关键死亡：关键写吸收普通，只落一次盘。
	_request(&"c_normal", false)
	await _advance_frames(0)
	var crit := _request(&"c_death", true, true)
	_assert("C1_critical_written", "%d" % (rev0 + 1), str(_file_revision()),
		_file_revision() == rev0 + 1)
	_assert("C2_normal_dropped", ">=%d" % (dropped0 + 1), str(int(_stat(sm, "dropped_normal", 0))),
		int(_stat(sm, "dropped_normal", 0)) >= dropped0 + 1)
	_assert("C3_last_reason_death", "death", str(_last_write_reason(sm)),
		_last_write_reason(sm) == "c_death")
	_assert("C4_critical_status", "ok", str(crit.get("status", "")),
		String(crit.get("status", "")) == "ok")
	await _advance_frames(2)
	_assert("C5_dropped_normal_not_written_after", "%d" % (rev0 + 1), str(_file_revision()),
		_file_revision() == rev0 + 1)

	# 关键后再来普通：普通排在其后，两个独立写。
	_request(&"c_discovery", true, true)
	_request(&"c_after_normal", false)
	await _advance_frames(3)
	_assert("C6_order_after_critical", ">=%d" % (rev0 + 2), str(_file_revision()),
		_file_revision() >= rev0 + 2)
	var order_ok := _last_write_has_prefix(sm, &"c_after_normal")
	_assert("C7_normal_after_critical_order", "true", str(order_ok), order_ok)

	# 多条关键各自写，不合并不丢弃。
	var rev_multi := _file_revision()
	var crit_written0 := int(_stat(sm, "critical_written", 0))
	_request(&"c_settle", true, true)
	_request(&"c_unlock", true, true)
	_request(&"c_exit", true, true)
	_assert("C8_each_critical_writes", "%d" % (rev_multi + 3), str(_file_revision()),
		_file_revision() == rev_multi + 3)
	_assert("C9_critical_counter", ">=%d" % (crit_written0 + 3), str(int(_stat(sm, "critical_written", 0))),
		int(_stat(sm, "critical_written", 0)) >= crit_written0 + 3)


# ---------------------------------------------------------------------------
# D 串行
# ---------------------------------------------------------------------------

func _section_d_serial() -> void:
	var sm := _sm()
	_assert("D1_max_active_one", "<=1", str(int(_stat(sm, "max_active_writes", 9))),
		int(_stat(sm, "max_active_writes", 9)) <= 1)
	_assert("D2_no_active_after", "0", str(int(_stat(sm, "active_writes", -1))),
		int(_stat(sm, "active_writes", -1)) == 0)
	_assert("D3_not_threaded", "false", str(_stat(sm, "threaded", true)),
		not bool(_stat(sm, "threaded", true)))
	_assert("D4_write_log_alternates", "start→end", str(_log_alternates(sm)), _log_alternates(sm))


# ---------------------------------------------------------------------------
# E 失败注入
# ---------------------------------------------------------------------------

func _section_e_failures() -> void:
	var sm := _sm()
	sm.set("throttle_seconds", 0.0)

	# E1 磁盘写失败：主档 / .bak 原样，无 tmp / .old，状态 write_failed。
	var main_before := _read(SAVE_PATH)
	var bak_before := _read(SAVE_PATH + ".bak")
	var failed0 := int(_stat(sm, "failed", 0))
	sm.set("fault_injection", "disk_write")
	var e1: Dictionary = sm.call("save_game", &"e1_disk")
	_assert("E1_status_write_failed", "write_failed", str(e1.get("status", "")),
		String(e1.get("status", "")) == "write_failed")
	_assert("E2_main_intact", "相同", "变化", _read(SAVE_PATH) == main_before)
	_assert("E3_bak_intact", "相同", "变化", _read(SAVE_PATH + ".bak") == bak_before)
	_assert("E4_no_tmp", "无", "有", not FileAccess.file_exists(SAVE_PATH + ".tmp"))
	_assert("E5_no_old", "无", "有", not FileAccess.file_exists(SAVE_PATH + ".old"))
	_assert("E6_failure_counted", ">=%d" % (failed0 + 1), str(int(_stat(sm, "failed", 0))),
		int(_stat(sm, "failed", 0)) >= failed0 + 1)
	_assert("E7_failure_reason_visible", "非空", "空", not _last_failure_reason(sm).is_empty())
	_assert("E8_message_player", "含存档写入失败", str(e1.get("message", "")),
		String(e1.get("message", "")).contains("存档写入失败"))

	# 清除故障后队列继续：下一次写成功，revision +1。
	sm.set("fault_injection", "")
	var rev_after_fail := _file_revision()
	var e1b: Dictionary = sm.call("save_game", &"e1_recover")
	_assert("E9_continue_after_failure", "ok", str(e1b.get("status", "")),
		String(e1b.get("status", "")) == "ok")
	_assert("E10_revision_advances", "%d" % (rev_after_fail + 1), str(_file_revision()),
		_file_revision() == rev_after_fail + 1)

	# E11 rename 失败：回滚主档，主档仍可解析且内容不变。
	var main_before_rename := _read(SAVE_PATH)
	var rev_before_rename := _file_revision()
	sm.set("fault_injection", "rename")
	var e2: Dictionary = sm.call("save_game", &"e2_rename")
	_assert("E11_rename_failed", "write_failed", str(e2.get("status", "")),
		String(e2.get("status", "")) == "write_failed")
	_assert("E12_main_rollback", "相同", "变化", _read(SAVE_PATH) == main_before_rename)
	_assert("E13_rev_unchanged", "%d" % rev_before_rename, str(_file_revision()),
		_file_revision() == rev_before_rename)
	_assert("E14_no_old_after_rollback", "无", "有", not FileAccess.file_exists(SAVE_PATH + ".old"))
	_assert("E15_no_tmp_after_rename_fail", "无", "有", not FileAccess.file_exists(SAVE_PATH + ".tmp"))

	# E16 .bak 复制失败：主档照常更新，旧 .bak 原样保留，状态 ok + warning。
	var bak_before_copy := _read(SAVE_PATH + ".bak")
	var rev_before_copy := _file_revision()
	sm.set("fault_injection", "bak_copy")
	var e3: Dictionary = sm.call("save_game", &"e3_bak")
	_assert("E16_bak_failure_nonfatal", "ok", str(e3.get("status", "")),
		String(e3.get("status", "")) == "ok")
	_assert("E17_main_updated", "%d" % (rev_before_copy + 1), str(_file_revision()),
		_file_revision() == rev_before_copy + 1)
	_assert("E18_old_bak_preserved", "相同", "变化", _read(SAVE_PATH + ".bak") == bak_before_copy)
	_assert("E19_warning_message", "含备份更新失败", str(e3.get("warning", "")),
		String(e3.get("warning", "")).contains("备份更新失败"))

	# E20 队列内失败后仍能继续（不是只在 save_game 直调时可用）。
	sm.set("fault_injection", "disk_write")
	_request(&"e4_queue_fail", false)
	await _advance_frames(2)
	_assert("E20_queue_failure_resets", "0", str(_queue_length(sm)), _queue_length(sm) == 0)
	_assert("E21_active_zero", "0", str(int(_stat(sm, "active_writes", -1))),
		int(_stat(sm, "active_writes", -1)) == 0)
	sm.set("fault_injection", "")
	var rev_queue_fail := _file_revision()
	_request(&"e4_queue_ok", false)
	await _advance_frames(3)
	_assert("E22_queue_continues", "%d" % (rev_queue_fail + 1), str(_file_revision()),
		_file_revision() == rev_queue_fail + 1)

	# E23 任一失败后至少一份可解析存档。
	_assert("E23_at_least_one_valid", "main 或 bak 可解析", "双坏",
		_parses(SAVE_PATH) or _parses(SAVE_PATH + ".bak"))
	sm.set("fault_injection", "")


# ---------------------------------------------------------------------------
# F 读档回退
# ---------------------------------------------------------------------------

func _section_f_load_fallback() -> void:
	var sm := _sm()
	var good := _read(SAVE_PATH)
	_write(SAVE_PATH + ".bak", good)
	_remove_file(SAVE_PATH)
	var res: Dictionary = sm.call("load_game")
	_assert("F1_status_recovered", "recovered_backup", str(res.get("status", "")),
		String(res.get("status", "")) == "recovered_backup")
	_assert("F2_message_missing_main", "含主存档缺失", str(res.get("message", "")),
		String(res.get("message", "")).contains("主存档缺失"))
	_assert("F3_snapshot_loaded", "非空", "空", not (res.get("snapshot", {}) as Dictionary).is_empty())

	# 主档与 .bak 同时坏：corrupt，不静默新游戏。
	_write(SAVE_PATH, "{ broken")
	_write(SAVE_PATH + ".bak", "{ broken too")
	var bad: Dictionary = sm.call("load_game")
	_assert("F4_both_corrupt", "corrupt", str(bad.get("status", "")),
		String(bad.get("status", "")) == "corrupt")
	_assert("F5_corrupt_message", "含存档损坏", str(bad.get("message", "")),
		String(bad.get("message", "")).contains("存档损坏"))
	_clean_test_dir()
	sm.call("set_save_path", SAVE_PATH)


# ---------------------------------------------------------------------------
# G T037 兼容（关键事务仍即时落盘）
# ---------------------------------------------------------------------------

func _section_g_t037_compat() -> void:
	var sm := _sm()
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_assert("G0_scene_load", "可加载", "null", false)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _advance_frames(3)
	_entry = main as MainEntry
	if _entry == null:
		_assert("G0_entry_class", "MainEntry", "null", false)
		return
	var disabled: Dictionary = _entry.call("save_now", &"g_off")
	_assert("G1_disabled", "disabled", str(disabled.get("status", "")),
		String(disabled.get("status", "")) == "disabled")

	_entry.call("set_persistence_enabled", true)
	var rev0 := _file_revision()
	_entry.select_species(&"Cat")
	await _advance_frames(4)
	_assert("G2_alive", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")

	_entry.player.survival.apply_damage(999.0, &"t038_g")
	await _advance_frames(3)
	var rev_death := _file_revision()
	_assert("G3_death_two_writes", ">=2", str(rev_death - rev0), rev_death - rev0 >= 2)
	var after_death: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	_assert("G4_pending_cleared", "空", str((after_death as Dictionary).get("pending_settlement_life_id", "?")),
		String((after_death as Dictionary).get("pending_settlement_life_id", "x")) == "")

	var gs := _gs()
	gs.call("record_place_discovery", &"t038_probe_place")
	await _advance_frames(1)
	var after_disc: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	_assert("G5_discovery_saved", "含探针", str((after_disc as Dictionary).get("discovered_ids", [])),
		((after_disc as Dictionary).get("discovered_ids", []) as Array).has("t038_probe_place"))
	gs.call("unlock_species", &"T038ProbeSpecies")
	await _advance_frames(1)
	var after_unlock: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	_assert("G6_unlock_saved", "含探针物种", str((after_unlock as Dictionary).get("unlocked_species", [])),
		((after_unlock as Dictionary).get("unlocked_species", []) as Array).has("T038ProbeSpecies"))

	var rev_before_exit := _file_revision()
	_entry.queue_free()
	_entry = null
	await _advance_frames(3)
	_assert("G7_exit_saved", ">=%d" % (rev_before_exit + 1), str(_file_revision()),
		_file_revision() >= rev_before_exit + 1)


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _sm() -> Node:
	return root.get_node_or_null("/root/SaveManager")


func _gs() -> Node:
	return root.get_node_or_null("/root/GameState")


func _request(reason: StringName, critical: bool = false, bypass: bool = false) -> Dictionary:
	var sm := _sm()
	if sm == null or not sm.has_method("request_save"):
		return {}
	return sm.call("request_save", reason, critical, bypass)


func _queue_length(sm: Node) -> int:
	if sm == null or not sm.has_method("queue_length"):
		return -1
	return int(sm.call("queue_length"))


func _pending_reasons(sm: Node) -> Array:
	if sm == null or not sm.has_method("pending_reasons"):
		return []
	return sm.call("pending_reasons")


func _stat(sm: Node, key: String, fallback: Variant) -> Variant:
	if sm == null or not sm.has_method("queue_stats"):
		return fallback
	var st: Dictionary = sm.call("queue_stats")
	return st.get(key, fallback)


func _last_write_reason(sm: Node) -> String:
	if sm == null or not sm.has_method("queue_stats"):
		return ""
	var st: Dictionary = sm.call("queue_stats")
	return String(st.get("last_write_reason", ""))


func _last_write_has_prefix(sm: Node, reason: StringName) -> bool:
	var want := String(reason)
	if sm == null or not sm.has_method("queue_stats"):
		return false
	var st: Dictionary = sm.call("queue_stats")
	return String(st.get("last_write_reason", "")) == want


func _last_failure_reason(sm: Node) -> String:
	if sm == null:
		return ""
	var v: Variant = sm.get("last_failure_reason")
	return "" if v == null else String(v)


func _log_alternates(sm: Node) -> bool:
	if sm == null or not sm.has_method("queue_stats"):
		return false
	var st: Dictionary = sm.call("queue_stats")
	var log: Array = st.get("write_log", [])
	if log.is_empty():
		return false
	var expect_start := true
	for raw in log:
		var s := String(raw)
		if expect_start and not s.begins_with("start|"):
			return false
		if not expect_start and not s.begins_with("end|"):
			return false
		expect_start = not expect_start
	return true


func _advance_frames(n: int) -> void:
	for i in n:
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


func _clean_test_dir() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(TEST_DIR)
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(TEST_DIR.path_join(String(f)))


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _parses(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return JSON.parse_string(FileAccess.get_file_as_string(path)) is Dictionary


func _file_revision() -> int:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		return int((parsed as Dictionary).get("revision", -1))
	return -1
