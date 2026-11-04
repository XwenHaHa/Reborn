extends SceneTree
## T039 备份与失败回退试验 —— 先写可失败的断言（对应 `Docs/Tasks/T039.md` §6）。
##
## A `.tmp` 残留 / B 写入失败 / C 备份与双坏 / D 双坏阻断 / E 连续失败与退出 / F 兼容。
## 首跑策略：新 API 一律 `has_method()/call()/get()` 探测；未实现时该段只落红，脚本不崩。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t039_backup_fallback.gd' --quit-after 600000
## 结果口径：RESULT|pass=<n>|fail=<n>。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const TEST_DIR := "user://t039_tests"
const SAVE_PATH := "user://t039_tests/savegame_v1.json"
const MSG_CORRUPT := "存档损坏，已隔离；未载入"

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
	sm.set("throttle_seconds", 1.0)

	await _section_a_tmp()
	await _section_b_write_failures()
	await _section_c_backup()
	await _section_d_block()
	await _section_e_repeat_and_exit()
	_section_f_compat()

	_cleanup_scene()
	await _advance_frames(2)
	if _sm() != null:
		_sm().set("fault_injection", "")
		_sm().set("write_delay_phase", "")
		_sm().set("write_delay_ms", 0)
	_clean_test_dir()
	_summary()
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------------------
# A .tmp 残留不是读档来源
# ---------------------------------------------------------------------------

func _section_a_tmp() -> void:
	var sm := _sm()
	_section_reset()
	_write(SAVE_PATH, JSON.stringify(_valid(1, "main")))
	_write(SAVE_PATH + ".bak", JSON.stringify(_valid(1, "bak")))
	# A1 半截 tmp + 完好主档：主档内容不被污染，tmp 不参与读档。
	_write(SAVE_PATH + ".tmp", "{\"save_version\":1,\"resources\":[{")
	var main_before := _read(SAVE_PATH)
	var a1: Dictionary = sm.call("load_game")
	_assert("A1_half_tmp_load_ok", "ok", str(a1.get("status", "")),
		String(a1.get("status", "")) == "ok")
	_assert("A2_half_tmp_main_rev", "1", str(_snapshot_rev(a1)), _snapshot_rev(a1) == 1)
	_assert("A3_half_tmp_main_content", "10.0", str(_snapshot_world(a1)), is_equal_approx(_snapshot_world(a1), 10.0))
	_assert("A4_main_not_polluted", "相同", "变化", _read(SAVE_PATH) == main_before)
	_assert("A5_tmp_untouched_by_load", "存在", "删除", FileAccess.file_exists(SAVE_PATH + ".tmp"))

	# A6 tmp 完整且 revision 更“新”，仍不载入。
	_write(SAVE_PATH + ".tmp", JSON.stringify(_valid(99, "tmp99")))
	var a6: Dictionary = sm.call("load_game")
	_assert("A6_newer_tmp_ignored", "1", str(_snapshot_rev(a6)), _snapshot_rev(a6) == 1)
	_assert("A7_newer_tmp_world_ignored", "10.0", str(_snapshot_world(a6)), is_equal_approx(_snapshot_world(a6), 10.0))

	# A8 下次保存成功并清理陈旧 tmp。
	var a8: Dictionary = sm.call("save_game", &"a_save")
	_assert("A8_save_ok", "ok", str(a8.get("status", "")),
		String(a8.get("status", "")) == "ok")
	_assert("A9_save_rev2", "2", str(_file_revision()), _file_revision() == 2)
	_assert("A10_tmp_cleared", "无", "有", not FileAccess.file_exists(SAVE_PATH + ".tmp"))
	_assert("A11_bak_rotated", "1", str(_json_rev(SAVE_PATH + ".bak")), _json_rev(SAVE_PATH + ".bak") == 1)

	# A12 只有陈旧 tmp、没有主档/备份：读档 none，保存从新档开始并清掉 tmp。
	_section_reset()
	_write(SAVE_PATH + ".tmp", JSON.stringify(_valid(99, "orphan")))
	var a12: Dictionary = sm.call("load_game")
	_assert("A12_orphan_tmp_none", "none", str(a12.get("status", "")),
		String(a12.get("status", "")) == "none")
	var rev_before := int(sm.get("revision"))
	var a13: Dictionary = sm.call("save_game", &"a_orphan")
	_assert("A13_orphan_save_ok", "ok", str(a13.get("status", "")),
		String(a13.get("status", "")) == "ok")
	_assert("A14_orphan_new_rev", "%d" % (rev_before + 1), str(_file_revision()),
		_file_revision() == rev_before + 1)
	_assert("A15_orphan_tmp_cleared", "无", "有", not FileAccess.file_exists(SAVE_PATH + ".tmp"))
	_assert("A16_orphan_not_tmp_content", "非 99", str(_file_revision()), _file_revision() != 99)


# ---------------------------------------------------------------------------
# B 写入失败（四类注入 × 连续 2 次）
# ---------------------------------------------------------------------------

func _section_b_write_failures() -> void:
	var sm := _sm()
	_section_reset()
	sm.call("save_game", &"b_seed")
	sm.call("save_game", &"b_seed2")
	var main0 := _read(SAVE_PATH)
	var bak0 := _read(SAVE_PATH + ".bak")
	var failed0 := int(_stat(sm, "failed", 0))
	var warn0 := int(_stat(sm, "warnings", 0))

	for kind in ["tmp_open", "disk_write"]:
		sm.set("fault_injection", kind)
		for i in 2:
			var r: Dictionary = sm.call("save_game", StringName("b_%s_%d" % [kind, i]))
			_assert("B1_%s_%d_failed" % [kind, i], "write_failed", str(r.get("status", "")),
				String(r.get("status", "")) == "write_failed")
			_assert("B2_%s_%d_main_intact" % [kind, i], "相同", "变化", _read(SAVE_PATH) == main0)
			_assert("B3_%s_%d_bak_intact" % [kind, i], "相同", "变化", _read(SAVE_PATH + ".bak") == bak0)
			_assert("B4_%s_%d_no_tmp" % [kind, i], "无", "有", not FileAccess.file_exists(SAVE_PATH + ".tmp"))
			_assert("B5_%s_%d_no_old" % [kind, i], "无", "有", not FileAccess.file_exists(SAVE_PATH + ".old"))
		_assert("B6_%s_failed_count" % kind, ">=%d" % (failed0 + 2), str(int(_stat(sm, "failed", 0))),
			int(_stat(sm, "failed", 0)) >= failed0 + 2)
		sm.set("fault_injection", "")
		var okr: Dictionary = sm.call("save_game", StringName("b_%s_recover" % kind))
		_assert("B7_%s_recover" % kind, "ok", str(okr.get("status", "")),
			String(okr.get("status", "")) == "ok")
		main0 = _read(SAVE_PATH)
		bak0 = _read(SAVE_PATH + ".bak")

	# rename 失败：回滚，主档字节不变；连续两次也不双坏。
	sm.set("fault_injection", "rename")
	for i in 2:
		var r2: Dictionary = sm.call("save_game", StringName("b_rename_%d" % i))
		_assert("B8_rename_%d_failed" % i, "write_failed", str(r2.get("status", "")),
			String(r2.get("status", "")) == "write_failed")
		_assert("B9_rename_%d_main_bytes" % i, "相同", "变化", _read(SAVE_PATH) == main0)
		_assert("B10_rename_%d_no_tmp" % i, "无", "有", not FileAccess.file_exists(SAVE_PATH + ".tmp"))
		_assert("B11_rename_%d_no_old" % i, "无", "有", not FileAccess.file_exists(SAVE_PATH + ".old"))
	sm.set("fault_injection", "")

	# bak_copy：主档照常更新；旧 .bak 保留；warning 文案；不留中间文件。
	var bak_before_copy := _read(SAVE_PATH + ".bak")
	sm.set("fault_injection", "bak_copy")
	for i in 2:
		var r3: Dictionary = sm.call("save_game", StringName("b_bak_%d" % i))
		_assert("B12_bak_%d_ok_warn" % i, "ok", str(r3.get("status", "")),
			String(r3.get("status", "")) == "ok")
		_assert("B13_bak_%d_warning" % i, "含备份更新失败", str(r3.get("warning", "")),
			String(r3.get("warning", "")).contains("备份更新失败"))
		_assert("B14_bak_%d_old_bak_kept" % i, "相同", "变化", _read(SAVE_PATH + ".bak") == bak_before_copy)
		_assert("B15_bak_%d_no_btmp" % i, "无", "有", not FileAccess.file_exists(SAVE_PATH + ".bak.tmp"))
		_assert("B16_bak_%d_no_bprev" % i, "无", "有", not FileAccess.file_exists(SAVE_PATH + ".bak.prev"))
	sm.set("fault_injection", "")
	_assert("B17_bak_warning_count", ">=%d" % (warn0 + 2), str(int(_stat(sm, "warnings", 0))),
		int(_stat(sm, "warnings", 0)) >= warn0 + 2)

	# B18 所有失败类型之后：主档与 .bak 都仍可解析（不双坏）。
	_assert("B18_main_parses", "true", str(_parses(SAVE_PATH)), _parses(SAVE_PATH))
	_assert("B19_bak_parses", "true", str(_parses(SAVE_PATH + ".bak")), _parses(SAVE_PATH + ".bak"))
	_assert("B20_queue_reset", "0", str(_queue_len(sm)), _queue_len(sm) == 0)
	_assert("B21_active_zero", "0", str(int(_stat(sm, "active_writes", -1))),
		int(_stat(sm, "active_writes", -1)) == 0)


# ---------------------------------------------------------------------------
# C 备份恢复与双坏
# ---------------------------------------------------------------------------

func _section_c_backup() -> void:
	var sm := _sm()
	# C1 主档坏 + .bak 好 → 隔离主档、载入备份。
	_section_reset()
	_write(SAVE_PATH, "{ broken")
	_write(SAVE_PATH + ".bak", JSON.stringify(_valid(1, "bak")))
	var c1: Dictionary = sm.call("load_game")
	_assert("C1_recovered", "recovered_backup", str(c1.get("status", "")),
		String(c1.get("status", "")) == "recovered_backup")
	_assert("C2_main_quarantined", "主档路径空", str(FileAccess.file_exists(SAVE_PATH)),
		not FileAccess.file_exists(SAVE_PATH))
	_assert("C3_main_corrupt_kept", "1", str(_corrupt_count("savegame_v1.json.corrupt-")),
		_corrupt_count("savegame_v1.json.corrupt-") == 1)
	_assert("C4_corrupt_content_kept", "{ broken", _read_corrupt("savegame_v1.json.corrupt-"),
		_read_corrupt("savegame_v1.json.corrupt-") == "{ broken")
	_assert("C5_bak_untouched", "true", str(_parses(SAVE_PATH + ".bak")), _parses(SAVE_PATH + ".bak"))
	_assert("C6_backup_rev", "1", str(_snapshot_rev(c1)), _snapshot_rev(c1) == 1)
	_assert("C7_quarantine_observable", "1", str(_quarantine_count(sm)), _quarantine_count(sm) == 1)

	# C8 主档坏 + 无备份 → corrupt + 隔离。
	_section_reset()
	_write(SAVE_PATH, "not json")
	var c8: Dictionary = sm.call("load_game")
	_assert("C8_corrupt", "corrupt", str(c8.get("status", "")),
		String(c8.get("status", "")) == "corrupt")
	_assert("C9_corrupt_message", MSG_CORRUPT, str(c8.get("message", "")),
		String(c8.get("message", "")) == MSG_CORRUPT)
	_assert("C10_main_moved", "无主档", str(FileAccess.file_exists(SAVE_PATH)),
		not FileAccess.file_exists(SAVE_PATH))
	_assert("C11_one_corrupt", "1", str(_corrupt_count("savegame_v1.json.corrupt-")),
		_corrupt_count("savegame_v1.json.corrupt-") == 1)

	# C12 主档缺失 + .bak 坏 → corrupt（不静默 none），坏 .bak 隔离。
	_section_reset()
	_write(SAVE_PATH + ".bak", "{ broken too")
	var c12: Dictionary = sm.call("load_game")
	_assert("C12_missing_main_bad_bak_corrupt", "corrupt", str(c12.get("status", "")),
		String(c12.get("status", "")) == "corrupt")
	_assert("C13_missing_main_bad_bak_message", MSG_CORRUPT, str(c12.get("message", "")),
		String(c12.get("message", "")) == MSG_CORRUPT)
	_assert("C14_bad_bak_moved", "无 .bak", str(FileAccess.file_exists(SAVE_PATH + ".bak")),
		not FileAccess.file_exists(SAVE_PATH + ".bak"))
	_assert("C15_bak_corrupt_kept", "1", str(_corrupt_count("savegame_v1.json.bak.corrupt-")),
		_corrupt_count("savegame_v1.json.bak.corrupt-") == 1)

	# C16 主档与 .bak 都坏 → 两份都隔离、精确文案、零写入。
	_section_reset()
	_write(SAVE_PATH, "{ broken main")
	_write(SAVE_PATH + ".bak", "{ broken bak")
	var written0 := int(_stat(sm, "written", 0))
	var c16: Dictionary = sm.call("load_game")
	_assert("C16_both_corrupt", "corrupt", str(c16.get("status", "")),
		String(c16.get("status", "")) == "corrupt")
	_assert("C17_both_message_exact", MSG_CORRUPT, str(c16.get("message", "")),
		String(c16.get("message", "")) == MSG_CORRUPT)
	_assert("C18_main_gone", "无主档", str(FileAccess.file_exists(SAVE_PATH)),
		not FileAccess.file_exists(SAVE_PATH))
	_assert("C19_bak_gone", "无 .bak", str(FileAccess.file_exists(SAVE_PATH + ".bak")),
		not FileAccess.file_exists(SAVE_PATH + ".bak"))
	_assert("C20_two_main_corrupt", "1", str(_corrupt_count("savegame_v1.json.corrupt-")),
		_corrupt_count("savegame_v1.json.corrupt-") == 1)
	_assert("C21_one_bak_corrupt", "1", str(_corrupt_count("savegame_v1.json.bak.corrupt-")),
		_corrupt_count("savegame_v1.json.bak.corrupt-") == 1)
	_assert("C22_main_content_kept", "{ broken main", _read_corrupt("savegame_v1.json.corrupt-"),
		_read_corrupt("savegame_v1.json.corrupt-") == "{ broken main")
	_assert("C23_bak_content_kept", "{ broken bak", _read_corrupt("savegame_v1.json.bak.corrupt-"),
		_read_corrupt("savegame_v1.json.bak.corrupt-") == "{ broken bak")
	_assert("C24_quarantine_two", "2", str(_quarantine_count(sm)), _quarantine_count(sm) == 2)
	_assert("C25_zero_write_on_load", "%d" % written0, str(int(_stat(sm, "written", 0))),
		int(_stat(sm, "written", 0)) == written0)
	_assert("C26_no_new_main", "无", "有", not FileAccess.file_exists(SAVE_PATH))
	var c27: Dictionary = sm.call("load_game")
	_assert("C27_after_quarantine_none", "none", str(c27.get("status", "")),
		String(c27.get("status", "")) == "none")
	_assert("C28_still_no_main", "无", "有", not FileAccess.file_exists(SAVE_PATH))


# ---------------------------------------------------------------------------
# D 双坏阻断：不静默进入新游戏、不自动写新档
# ---------------------------------------------------------------------------

func _section_d_block() -> void:
	_section_reset()
	_write(SAVE_PATH, "{ broken main")
	_write(SAVE_PATH + ".bak", "{ broken bak")
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_assert("D0_scene_load", "可加载", "null", false)
		return
	# 正式运行路径：current_scene 在本节点，持久化自动启用。
	change_scene_to_packed(packed)
	await _advance_frames(4)
	_entry = current_scene as MainEntry
	if _entry == null:
		_assert("D0b_entry", "MainEntry", "null", false)
		return
	_assert("D1_blocked_api", "true", str(_entry.has_method("is_load_blocked")),
		_entry.has_method("is_load_blocked"))
	var blocked_now: bool = _entry.has_method("is_load_blocked") and bool(_entry.call("is_load_blocked"))
	_assert("D2_blocked", "true", str(blocked_now), blocked_now)
	_assert("D3_load_status_corrupt", "corrupt", _load_status(),
		_load_status() == "corrupt")
	_assert("D4_snapshot_empty", "空", "非空", _loaded_snapshot_empty())
	_assert("D5_select_denied", "false", str(_entry.select_species(&"Cat")),
		not _entry.select_species(&"Cat"))
	_assert("D6_still_selecting", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")
	_assert("D7_no_player", "null", str(_entry.player), _entry.player == null)
	_assert("D8_no_new_main", "无", "有", not FileAccess.file_exists(SAVE_PATH))
	var save_res: Dictionary = _entry.call("save_now", &"d_blocked")
	_assert("D9_save_now_blocked", "blocked", str(save_res.get("status", "")),
		String(save_res.get("status", "")) == "blocked")
	_assert("D10_still_no_main", "无", "有", not FileAccess.file_exists(SAVE_PATH))

	# 第一次退出：阻断时不得写新档。
	change_scene_to_packed(packed)
	await _advance_frames(4)
	_entry = current_scene as MainEntry
	_assert("D11_reload_after_exit_none", "none", _load_status(), _load_status() == "none")
	var blocked2: bool = _entry.has_method("is_load_blocked") and bool(_entry.call("is_load_blocked"))
	_assert("D12_not_blocked_after_quarantine", "false", str(blocked2), not blocked2)
	_assert("D13_exit_did_not_write", "无", "有", not FileAccess.file_exists(SAVE_PATH))
	# 新一局必须由玩家显式选择物种才会开始（T041 再做确认入口）。
	var d14 := _entry.select_species(&"Cat")
	_assert("D14_explicit_select_ok", "true", str(d14), d14)
	await _advance_frames(4)
	_assert("D15_alive_after_select", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	# 退出保存此时才允许产生新档（显式开局之后）。
	_cleanup_scene()
	await _advance_frames(3)
	_assert("D16_new_main_after_explicit_game", "true", str(_parses(SAVE_PATH)), _parses(SAVE_PATH))


# ---------------------------------------------------------------------------
# E 连续失败与失败后退出
# ---------------------------------------------------------------------------

func _section_e_repeat_and_exit() -> void:
	var sm := _sm()
	_section_reset()
	sm.call("save_game", &"e_seed")
	sm.call("save_game", &"e_seed2")
	var rev0 := _file_revision()
	var main0 := _read(SAVE_PATH)
	var bak0 := _read(SAVE_PATH + ".bak")
	var failed0 := int(_stat(sm, "failed", 0))
	sm.set("fault_injection", "disk_write")
	for i in 3:
		var r: Dictionary = sm.call("save_game", StringName("e_%d" % i))
		_assert("E1_%d_failed" % i, "write_failed", str(r.get("status", "")),
			String(r.get("status", "")) == "write_failed")
		_assert("E2_%d_rev_unchanged" % i, "%d" % rev0, str(_file_revision()),
			_file_revision() == rev0)
		_assert("E3_%d_main_intact" % i, "相同", "变化", _read(SAVE_PATH) == main0)
		_assert("E4_%d_bak_intact" % i, "相同", "变化", _read(SAVE_PATH + ".bak") == bak0)
	_assert("E5_failed_three", ">=%d" % (failed0 + 3), str(int(_stat(sm, "failed", 0))),
		int(_stat(sm, "failed", 0)) >= failed0 + 3)
	_assert("E6_no_tmp", "无", "有", not FileAccess.file_exists(SAVE_PATH + ".tmp"))
	_assert("E7_no_old", "无", "有", not FileAccess.file_exists(SAVE_PATH + ".old"))

	# 失败后退出：入口的退出保存也失败，旧档仍可解析、队列不锁死。
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_assert("E8_scene_load", "可加载", "null", false)
		return
	change_scene_to_packed(packed)
	await _advance_frames(4)
	_entry = current_scene as MainEntry
	var fail_exit: Dictionary = _entry.call("save_now", &"e_before_exit")
	_assert("E9_save_now_failed", "write_failed", str(fail_exit.get("status", "")),
		String(fail_exit.get("status", "")) == "write_failed")
	var failed_before_exit := int(_stat(sm, "failed", 0))
	_cleanup_scene()
	await _advance_frames(3)
	_assert("E10_exit_save_attempted", ">=%d" % (failed_before_exit + 1), str(int(_stat(sm, "failed", 0))),
		int(_stat(sm, "failed", 0)) >= failed_before_exit + 1)
	_assert("E11_main_still_parses", "true", str(_parses(SAVE_PATH)), _parses(SAVE_PATH))
	_assert("E12_bak_still_parses", "true", str(_parses(SAVE_PATH + ".bak")), _parses(SAVE_PATH + ".bak"))
	_assert("E13_rev_still", "%d" % rev0, str(_file_revision()), _file_revision() == rev0)
	_assert("E14_no_tmp_after_exit", "无", "有", not FileAccess.file_exists(SAVE_PATH + ".tmp"))
	_assert("E15_no_old_after_exit", "无", "有", not FileAccess.file_exists(SAVE_PATH + ".old"))
	_assert("E16_queue_empty", "0", str(_queue_len(sm)), _queue_len(sm) == 0)
	_assert("E17_active_zero", "0", str(int(_stat(sm, "active_writes", -1))),
		int(_stat(sm, "active_writes", -1)) == 0)
	sm.set("fault_injection", "")
	var recover: Dictionary = sm.call("save_game", &"e_recover")
	_assert("E18_recover_after_exit_failure", "ok", str(recover.get("status", "")),
		String(recover.get("status", "")) == "ok")
	_assert("E19_rev_advances", "%d" % (rev0 + 1), str(_file_revision()),
		_file_revision() == rev0 + 1)


# ---------------------------------------------------------------------------
# F 兼容
# ---------------------------------------------------------------------------

func _section_f_compat() -> void:
	var sm := _sm()
	var ts: Variant = sm.get("throttle_seconds")
	_assert("F1_throttle_default", "1.0", str(ts),
		ts != null and is_equal_approx(float(ts), 1.0))
	_assert("F2_not_threaded", "false", str(_stat(sm, "threaded", true)),
		not bool(_stat(sm, "threaded", true)))
	_assert("F3_queue_api", "true", str(sm.has_method("queue_length")),
		sm.has_method("queue_length"))
	_assert("F4_request_api", "true", str(sm.has_method("request_save")),
		sm.has_method("request_save"))
	var snap: Dictionary = sm.call("build_snapshot", &"f_compat")
	var cur: Dictionary = snap.get("current_life", {})
	_assert("F5_no_last_safe_spot", "无预留键", "出现",
		not cur.has("last_safe_spot_id"))
	_assert("F6_save_version", "1", str(snap.get("save_version", -1)),
		int(snap.get("save_version", -1)) == 1)
	_assert("F7_zero_queue", "0", str(_queue_len(sm)), _queue_len(sm) == 0)


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

## 输出一个完整可校验的最小快照；`marker` 只写进 `saved_reason` 便于辨源。
func _valid(rev: int, marker: String) -> Dictionary:
	return {
		"save_version": 1,
		"revision": rev,
		"world_time": float(rev) * 10.0,
		"resources": [],
		"regions": [],
		"discovered_ids": [],
		"unlocked_species": [],
		"life_records": [],
		"current_life": {},
		"pending_settlement_life_id": "",
		"events": [],
		"life_counter": 0,
		"event_seq": 0,
		"saved_reason": marker,
	}


func _sm() -> Node:
	return root.get_node_or_null("/root/SaveManager")


func _section_reset() -> void:
	_clean_test_dir()
	var sm := _sm()
	if sm != null:
		sm.call("set_save_path", SAVE_PATH)
		sm.set("fault_injection", "")


func _load_status() -> String:
	var v: Variant = _entry.get("_load_status")
	return "" if v == null else String(v)


func _loaded_snapshot_empty() -> bool:
	var v: Variant = _entry.get("_loaded_snapshot")
	return not (v is Dictionary) or (v as Dictionary).is_empty()


func _snapshot_rev(res: Dictionary) -> int:
	var snap: Dictionary = res.get("snapshot", {})
	return int(snap.get("revision", -1))


func _snapshot_world(res: Dictionary) -> float:
	var snap: Dictionary = res.get("snapshot", {})
	return float(snap.get("world_time", -1.0))


func _quarantine_count(sm: Node) -> int:
	var v: Variant = sm.get("last_quarantine")
	if v is Array:
		return (v as Array).size()
	return -1


func _corrupt_count(prefix: String) -> int:
	return _corrupt_names(prefix).size()


func _corrupt_names(prefix: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var s := String(f)
		if s.begins_with(prefix):
			out.append(s)
	return out


func _read_corrupt(prefix: String) -> String:
	var names := _corrupt_names(prefix)
	if names.is_empty():
		return ""
	return _read(TEST_DIR.path_join(String(names[0])))


func _queue_len(sm: Node) -> int:
	if sm == null or not sm.has_method("queue_length"):
		return -1
	return int(sm.call("queue_length"))


func _stat(sm: Node, key: String, fallback: Variant) -> Variant:
	if sm == null or not sm.has_method("queue_stats"):
		return fallback
	var st: Dictionary = sm.call("queue_stats")
	return st.get(key, fallback)


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


func _cleanup_scene() -> void:
	if current_scene != null:
		current_scene = null
	if _entry != null and is_instance_valid(_entry):
		_entry.queue_free()
	_entry = null


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


func _parses(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return JSON.parse_string(FileAccess.get_file_as_string(path)) is Dictionary


func _file_revision() -> int:
	return _json_rev(SAVE_PATH)


func _json_rev(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return int((parsed as Dictionary).get("revision", -1))
	return -1
