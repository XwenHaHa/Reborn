extends SceneTree
## T037 存档持久化与读档重建 —— 先写可失败的断言（对应 `Docs/Tasks/T037.md` §6）。
##
## A 格式 / B 写入 / C 校验与损坏恢复 / D 重建 / E 读档生命 / F 幂等 / G 自动存盘时机。
## 首跑策略：新 API 一律 `call()/get()` 探测；未实现时该段只落红，脚本不崩。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t037_save_load.gd' --quit-after 300000
## 结果口径：RESULT|pass=<n>|fail=<n>。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const RP_SCENE := "res://scenes/world/resource_point.tscn"
const TEST_DIR := "user://t037_tests"
const SAVE_PATH := "user://t037_tests/savegame_v1.json"
const PROBE_PLACE := "t037_probe_place"
const PROBE_PLACE_2 := "t037_probe_place_2"

const SNAPSHOT_KEYS: Array[String] = ["save_version", "revision", "world_time", "resources",
	"regions", "discovered_ids", "unlocked_species", "life_records", "current_life",
	"pending_settlement_life_id", "events", "life_counter", "event_seq", "saved_reason"]

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _rp: Node3D = null
var _entry: MainEntry = null
var _region_id := ""
var _loaded_revision := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await _advance_frames(1)
	_clean_test_dir()
	var sm := _sm()
	sm.set("allow_headless_writes", true)
	sm.call("set_save_path", SAVE_PATH)

	await _section_a_format()
	await _section_b_write()
	await _section_c_validate()

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_assert("A0_scene_load", "可加载", "null", false)
		_summary()
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	root.size = Vector2i(1280, 720)
	await _advance_frames(2)
	_entry = main as MainEntry
	if _entry == null:
		_assert("A0_entry_class", "MainEntry", "null", false)
		_summary()
		quit(1)
		return
	_region_id = _first_region_id()
	if _region_id == "":
		var rids: Array = _wd().call("region_ids")
		if rids.size() > 0:
			_region_id = String(rids[0])
	print("T037|region_id=%s|region_ids=%s" % [_region_id, str(_wd().call("region_ids"))])

	await _section_d_rebuild()
	await _section_e_life()
	await _section_f_idempotent()
	await _section_g_timing()

	if _rp != null and is_instance_valid(_rp):
		_rp.queue_free()
	if _entry != null and is_instance_valid(_entry):
		_entry.queue_free()
	await _advance_frames(2)
	_clean_test_dir()
	_summary()
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------------------
# A 格式
# ---------------------------------------------------------------------------

func _section_a_format() -> void:
	var wd := _wd()
	wd.set("time_advancing", false)
	wd.call("set_world_time", 42.5)
	_rp = _make_probe(Vector3(2.5, 0.1, -3.5))
	_rp.set("interaction_id", "t037_probe_food")
	await _advance_frames(2)

	var sm := _sm()
	var snap: Dictionary = sm.call("build_snapshot", &"a")
	_assert("A1_snapshot_keys", str(SNAPSHOT_KEYS.size()), str(snap.size()),
		snap.size() == SNAPSHOT_KEYS.size())
	var missing: Array[String] = []
	for key in SNAPSHOT_KEYS:
		if not snap.has(key):
			missing.append(key)
	_assert("A2_contract_keys", "无缺键", str(missing), missing.is_empty())
	_assert("A3_save_version", "1", str(snap.get("save_version")), int(snap.get("save_version", 0)) == 1)
	_assert("A4_world_time", "42.5", str(snap.get("world_time")),
		is_equal_approx(float(snap.get("world_time", -1.0)), 42.5))
	_assert("A5_pure_data", "纯数据", "含 Object", _is_pure_data(snap))

	var first: Dictionary = sm.call("save_game", &"a")
	var second: Dictionary = sm.call("save_game", &"a")
	_loaded_revision = int(second.get("revision", 0))
	_assert("A6_revision_monotonic", ">=2", str(_loaded_revision), _loaded_revision >= 2)

	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	_assert("A7_no_personal_path", "无个人路径", "命中",
		not _has_abs_path(text) and not text.contains("Documents") and not text.contains("AppData"))
	var res: Array = (on_disk as Dictionary).get("resources", [])
	var tf_ok := false
	for r in res:
		if String((r as Dictionary).get("id", "")) == "t037_probe_food":
			var t: Array = ((r as Dictionary).get("transform", {}) as Dictionary).get("$t", [])
			tf_ok = t.size() == 12 and is_equal_approx(float(t[9]), 2.5) \
				and is_equal_approx(float(t[11]), -3.5)
	_assert("A8_transform_roundtrip", "origin=(2.5,-3.5)", str(tf_ok), tf_ok)
	_assert("A9_first_save_ok", "ok", str(first.get("status", "")),
		String(first.get("status", "")) == "ok")


# ---------------------------------------------------------------------------
# B 写入
# ---------------------------------------------------------------------------

func _section_b_write() -> void:
	var sm := _sm()
	_assert("B1_no_tmp_residue", "无 .tmp", "有",
		not FileAccess.file_exists(SAVE_PATH + ".tmp"))
	_assert("B2_bak_exists", "有 .bak", "无", FileAccess.file_exists(SAVE_PATH + ".bak"))
	var bak_rev := -1
	var bak: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH + ".bak"))
	if bak is Dictionary:
		bak_rev = int((bak as Dictionary).get("revision", -1))
	_assert("B3_bak_is_previous", "<%d" % _loaded_revision, str(bak_rev), bak_rev >= 0 and bak_rev < _loaded_revision)
	_assert("B4_main_parses", "可解析", "空", bak is Dictionary)

	var before := FileAccess.get_file_as_string(SAVE_PATH)
	# 让父目录不可建：把父路径做成普通文件 → 打开临时文件失败。
	var blocker := TEST_DIR + "/blocked_parent"
	_write_text(blocker, "x")
	sm.call("set_save_path", TEST_DIR + "/blocked_parent/savegame_v1.json")
	var failed: Dictionary = sm.call("save_game", &"b_fail")
	_assert("B5_write_failed", "write_failed", str(failed.get("status", "")),
		String(failed.get("status", "")) == "write_failed")
	_assert("B6_old_file_intact", "内容不变", "changed",
		FileAccess.get_file_as_string(SAVE_PATH) == before)
	sm.call("set_save_path", SAVE_PATH)
	sm.set("revision", _loaded_revision)
	_assert("B7_no_tmp_after_fail", "无 .tmp", "有",
		not FileAccess.file_exists(TEST_DIR + "/blocked_parent/savegame_v1.json.tmp"))


# ---------------------------------------------------------------------------
# C 校验 / 损坏恢复
# ---------------------------------------------------------------------------

func _section_c_validate() -> void:
	var sm := _sm()

	# C1 版本不匹配：不隔离、不覆盖、不改文件。
	var before := FileAccess.get_file_as_string(SAVE_PATH)
	_write_text(SAVE_PATH, JSON.stringify({"save_version": 2, "revision": 9}))
	var vm: Dictionary = sm.call("load_game")
	_assert("C1_version_mismatch", "version_mismatch", str(vm.get("status", "")),
		String(vm.get("status", "")) == "version_mismatch")
	_assert("C1b_file_untouched", "未改动", "被改",
		FileAccess.get_file_as_string(SAVE_PATH).contains("\"save_version\":2"))
	_write_text(SAVE_PATH, before)
	sm.set("revision", _loaded_revision)

	# C2 缺集合 → 补默认 + repairs
	var miss: Dictionary = sm.call("validate", {"save_version": 1})
	var mr: Array = miss.get("repairs", [])
	var has_missing := false
	for r in mr:
		if String(r).begins_with("missing:"):
			has_missing = true
	_assert("C2_missing_collections", "有 missing 修复", str(mr), has_missing)
	var ms: Dictionary = miss.get("snapshot", {})
	_assert("C2b_defaults", "空数组", str(ms.get("resources", null)),
		ms.get("resources", null) is Array and (ms.get("resources", []) as Array).is_empty())

	# C3/C4 负值 / 超容量 → 夹紧
	var clamp_raw := {"save_version": 1, "resources": [{"id": "r1", "kind": "food",
		"units": -3, "capacity": 3}], "regions": [{"region_id": "R", "species_id": "S",
		"total_count": 9, "capacity": 4}]}
	var clamped: Dictionary = sm.call("validate", clamp_raw)
	var cs: Dictionary = clamped.get("snapshot", {})
	_assert("C3_negative_units", "0", str((cs.get("resources", []) as Array)[0].get("units")),
		int(((cs.get("resources", []) as Array)[0] as Dictionary).get("units", -1)) == 0)
	_assert("C4_over_capacity", "4", str((cs.get("regions", []) as Array)[0].get("total_count")),
		int(((cs.get("regions", []) as Array)[0] as Dictionary).get("total_count", -1)) == 4)

	# C5 非有限 → 记修复并回默认
	var nan_raw := {"save_version": 1, "resources": [{"id": "r2", "kind": "food",
		"units": 0, "capacity": NAN}]}
	var nan_res: Dictionary = sm.call("validate", nan_raw)
	_assert("C5_non_finite_repair", "有 non_finite", str(nan_res.get("repairs", [])),
		_find_prefix(nan_res.get("repairs", []), "resources.capacity:non_finite"))

	# C6 截断 → corrupt + 隔离（先移除 .bak 保证无可恢复备份）
	_remove_file(SAVE_PATH + ".bak")
	_write_text(SAVE_PATH, "{\"save_version\":1,\"resources\":[")
	var corrupt: Dictionary = sm.call("load_game")
	_assert("C6_truncated_corrupt", "corrupt", str(corrupt.get("status", "")),
		String(corrupt.get("status", "")) == "corrupt")
	var leftover := before
	var q_count := 0
	var dir := DirAccess.open(TEST_DIR)
	if dir != null:
		for f in dir.get_files():
			if String(f).begins_with("savegame_v1.json.corrupt-"):
				q_count += 1
	_assert("C6b_quarantined", ">=1", str(q_count), q_count >= 1)
	_assert("C6c_corrupt_message", "非空", str(corrupt.get("message", "")),
		String(corrupt.get("message", "")) != "")

	# C7 主档坏 + 备份好 → recovered_backup
	_write_text(SAVE_PATH + ".bak", JSON.stringify({"save_version": 1, "revision": 3,
		"world_time": 7.0, "resources": [], "regions": [], "discovered_ids": [],
		"unlocked_species": [], "life_records": [], "current_life": {},
		"pending_settlement_life_id": "", "events": [], "life_counter": 0, "event_seq": 0}))
	_write_text(SAVE_PATH, "not json at all")
	var rec: Dictionary = sm.call("load_game")
	_assert("C7_recovered_backup", "recovered_backup", str(rec.get("status", "")),
		String(rec.get("status", "")) == "recovered_backup")
	_assert("C7b_backup_message", "含备份", str(rec.get("message", "")),
		String(rec.get("message", "")) != "")
	# 复原一份有效主档供后续 D/F 使用
	_write_text(SAVE_PATH, JSON.stringify(rec.get("snapshot", {})))
	_remove_file(SAVE_PATH + ".bak")


# ---------------------------------------------------------------------------
# D 重建
# ---------------------------------------------------------------------------

func _section_d_rebuild() -> void:
	var sm := _sm()
	var gs := _gs()
	var wd := _wd()
	gs.call("reset_for_new_game")
	# 真实新游戏序列：清长期层后，入口重新建关卡并 init 区域账本（reset 会清空账本）。
	wd.call("init_region_population", _entry.species_configs())
	_assert("D0b_region_initialized", "true", str(wd.get("region_population_initialized")),
		bool(wd.get("region_population_initialized")))
	# 清掉 A 段探针的消耗状态，确保"应用既有资源点"可被观察到。
	_rp.set("units", 0)
	_rp.set("capacity", 3)

	var raw := {
		"save_version": 1,
		"revision": 5,
		"world_time": 321.5,
		"resources": [
			{"id": "t037_probe_food", "region_id": _region_id, "kind": "food", "food_type": 0,
				"units": 2, "capacity": 3, "next_refill_at": 400.0, "refill_interval": 180.0,
				"transform": Transform3D(Basis(), Vector3(5.0, 0.1, 5.0)), "expire_at": 0.0},
			{"id": "t037_saved_water", "region_id": _region_id, "kind": "water", "food_type": 0,
				"units": 0, "capacity": 0, "next_refill_at": 0.0, "refill_interval": 0.0,
				"transform": Transform3D(Basis(), Vector3(6.0, 0.1, 6.0)), "expire_at": 0.0},
		],
		"regions": [{"region_id": _region_id, "species_id": "Mouse", "total_count": 3,
			"capacity": 4, "next_recover_at": 0.0, "recover_interval": 240.0}],
		"discovered_ids": [PROBE_PLACE],
		"unlocked_species": ["Cat", "Mouse"],
		"life_records": [{"life_id": "L0001", "species_id": "Cat", "start_world_time": 10.0,
			"end_world_time": 100.0, "duration": 90.0, "end_reason": "died",
			"damage_reason": "starvation", "start_position": Vector3(1, 0, 1),
			"captures": 1, "escapes": 1, "food_gained": 35.0, "water_gained": 40.0,
			"discoveries": [], "event_first": 1, "event_last": 2,
			"snapshot": {"health": 0.0, "hunger": 0.0, "thirst": 0.0, "stamina": 0.0},
			"transform": Transform3D(Basis(), Vector3(1, 0, 1))}],
		"current_life": {"life_id": "L0002", "species_id": "Cat",
			"start_world_time": 150.0, "end_world_time": -1.0, "duration": -1.0,
			"end_reason": "", "damage_reason": "", "start_position": Vector3(3, 0, 3),
			"captures": 0, "escapes": 0, "food_gained": 0.0, "water_gained": 0.0,
			"discoveries": [], "event_first": 3, "event_last": 2,
			"snapshot": {"health": 82.0, "hunger": 61.0, "thirst": 54.0, "stamina": 77.0,
				"last_damage_reason": ""},
			"transform": Transform3D(Basis(), Vector3(3.5, 0.6, -2.25))},
		"events": [{"seq": 1, "life_id": "L0001", "kind": "life_start", "world_time": 10.0, "data": {}},
			{"seq": 2, "life_id": "L0001", "kind": "life_end", "world_time": 100.0,
				"data": {"reason": "died"}}],
		"life_counter": 2,
		"event_seq": 2,
		"pending_settlement_life_id": "",
		"saved_reason": "probe",
	}
	var checked: Dictionary = sm.call("validate", raw)
	_assert("D0_validate_ok", "ok", str(checked.get("status", "")),
		String(checked.get("status", "")) == "ok")
	var snap: Dictionary = checked.get("snapshot", {})
	wd.set("time_advancing", false)
	var applied: bool = _entry.call("apply_saved_snapshot", snap)
	# 恢复是同步的：下面几项在下一物理帧前断言，避免位移/时间自然演化干扰。
	_assert("D1_applied", "true", str(applied), applied)
	_assert("D2_world_time", "321.5", str(wd.get("world_time")),
		is_equal_approx(float(wd.get("world_time")), 321.5))
	_assert("D12_transform", "(3.5,0.6,-2.25)", str(_entry.player.global_position if _entry.player else null),
		_entry.player != null and _entry.player.global_position.is_equal_approx(Vector3(3.5, 0.6, -2.25)))
	var st0: SurvivalState = _entry.player.survival.state if _entry.player != null else null
	_assert("D13_survival", "82/61/54/77", str(st0.to_dictionary() if st0 else null),
		st0 != null and is_equal_approx(st0.health, 82.0) and is_equal_approx(st0.hunger, 61.0)
		and is_equal_approx(st0.thirst, 54.0) and is_equal_approx(st0.stamina, 77.0))
	_assert("D14_hud_bound", "true", str(_entry.hud.is_bound() if _entry.hud else null),
		_entry.hud != null and _entry.hud.is_bound())
	await _advance_frames(3)

	var recs: Array = wd.call("region_population_snapshot")
	var total := -1
	for r in recs:
		if String((r as Dictionary).get("region_id", "")) == _region_id \
				and String((r as Dictionary).get("species_id", "")) == "Mouse":
			total = int((r as Dictionary).get("total_count", -1))
	_assert("D3_region_total", "3", str(total), total == 3)

	var probe := _find_resource("t037_probe_food")
	_assert("D4_resource_applied", "units=2", str(probe.get("units") if probe else null),
		probe != null and int(probe.get("units")) == 2)
	_assert("D4b_resource_transform", "x=5", str(probe.get("global_position") if probe else null),
		probe != null and is_equal_approx((probe as Node3D).global_position.x, 5.0))
	var spawned := _find_resource("t037_saved_water")
	_assert("D5_resource_created", "存在", "缺失", spawned != null)

	_assert("D6_discovery", "含探针", str(gs.call("discovered_place_list")),
		(gs.call("discovered_place_list") as Array).has(PROBE_PLACE))
	_assert("D7_unlocked", "含 Cat+Mouse", str(gs.call("unlocked_list")),
		(gs.call("unlocked_list") as Array).has(&"Cat") and (gs.call("unlocked_list") as Array).has(&"Mouse"))
	_assert("D8_archive_count", "1", str(_entry.archive_count()), _entry.archive_count() == 1)
	_assert("D9_event_seq", "2", str(gs.call("last_event_seq")), int(gs.call("last_event_seq")) == 2)
	_assert("D10_life_id", "L0002", _entry.current_life_id(), _entry.current_life_id() == "L0002")
	_assert("D11_alive", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")


# ---------------------------------------------------------------------------
# E 读档生命
# ---------------------------------------------------------------------------

func _section_e_life() -> void:
	var gs := _gs()
	var wd := _wd()
	var life_before := _entry.current_life_id()
	gs.call("record_event", "L0002", &"t037_probe", {})
	_assert("E1_event_seq_continues", "3", str(gs.call("last_event_seq")),
		int(gs.call("last_event_seq")) == 3)
	_assert("E2_time_advancing", "true", str(wd.get("time_advancing")),
		bool(wd.get("time_advancing")))
	_assert("E3_life_id_preserved", life_before, _entry.current_life_id(),
		_entry.current_life_id() == life_before)

	# 死亡：只结算一次；无自动存档（测试未启用）也不许崩。
	_entry.player.survival.apply_damage(999.0, &"t037_test")
	await _advance_frames(3)
	_assert("E4_dead_selecting", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")
	_assert("E5_archive_after_death", "2", str(_entry.archive_count()), _entry.archive_count() == 2)
	_assert("E6_pending_cleared", "空", _entry.pending_settlement_life_id(),
		_entry.pending_settlement_life_id() == "")

	# 读档：current_life 空 + pending 空 → 停留在选物种，归档不变。
	var sm := _sm()
	var packed: Dictionary = sm.call("build_snapshot", &"e_dead")
	packed["pending_settlement_life_id"] = ""
	var dead_checked: Dictionary = sm.call("validate", packed)
	_entry.call("apply_saved_snapshot", dead_checked.get("snapshot", {}))
	await _advance_frames(2)
	_assert("E7_reload_dead_selecting", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")
	_assert("E8_reload_archive_kept", "2", str(_entry.archive_count()), _entry.archive_count() == 2)

	# 待结算：pending 非空 → 补弹结算页，展示后清空。
	packed["pending_settlement_life_id"] = "L0002"
	var pend_checked: Dictionary = sm.call("validate", packed)
	_entry.call("apply_saved_snapshot", pend_checked.get("snapshot", {}))
	await _advance_frames(2)
	_assert("E9_pending_presented", "true", str(_entry.settle_panel.is_presenting()),
		_entry.settle_panel != null and _entry.settle_panel.is_presenting())
	_assert("E10_pending_cleared", "空", _entry.pending_settlement_life_id(),
		_entry.pending_settlement_life_id() == "")


# ---------------------------------------------------------------------------
# F 幂等
# ---------------------------------------------------------------------------

func _section_f_idempotent() -> void:
	var sm := _sm()
	_entry.dismiss_settle()
	_entry.call("save_now", &"f1")   # 未启用 → 不应写；下面直接走 SaveManager
	var a: Dictionary = sm.call("save_game", &"f1")
	var a_text := FileAccess.get_file_as_string(SAVE_PATH)
	var b: Dictionary = sm.call("save_game", &"f2")
	var b_text := FileAccess.get_file_as_string(SAVE_PATH)
	_assert("F1_repeat_save_stable", "规范化相同", "不同",
		_normalized(a_text) == _normalized(b_text))
	_assert("F2_revision_advances", ">=%d" % int(a.get("revision", 0)),
		str(b.get("revision", -1)), int(b.get("revision", -1)) > int(a.get("revision", 0)))
	var loaded: Dictionary = sm.call("load_game")
	_assert("F3_load_after_save", "ok", str(loaded.get("status", "")),
		String(loaded.get("status", "")) == "ok")
	sm.call("save_game", &"f3")
	var c_text := FileAccess.get_file_as_string(SAVE_PATH)
	_assert("F4_load_then_save_same", "规范化相同", "不同",
		_normalized(b_text) == _normalized(c_text))
	var saved: Variant = JSON.parse_string(b_text)
	_assert("F5_life_counter_saved", "2", str((saved as Dictionary).get("life_counter", -1)),
		int((saved as Dictionary).get("life_counter", -1)) == 2)


# ---------------------------------------------------------------------------
# G 自动存盘时机
# ---------------------------------------------------------------------------

func _section_g_timing() -> void:
	var sm := _sm()
	var gs := _gs()
	# 非正式运行：save_now 必须不写。
	var disabled: Dictionary = _entry.call("save_now", &"g_off")
	_assert("G1_disabled_when_not_formal", "disabled", str(disabled.get("status", "")),
		String(disabled.get("status", "")) == "disabled")

	_entry.call("set_persistence_enabled", true)
	var rev0 := _file_revision()
	# 需要一个存活玩家：走既有选物种出生（Cat 已解锁）。
	_entry.select_species(&"Cat")
	await _advance_frames(4)
	_assert("G2_spawned", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	# 读档恢复 life_counter 后，新一世必须继续 L0003（不能与档案重号）。
	_assert("G2b_life_counter", "L0003", _entry.current_life_id(),
		_entry.current_life_id() == "L0003")

	# 死亡：两次写（pending 有 → 无），最终文件 pending 为空。
	_entry.player.survival.apply_damage(999.0, &"t037_g")
	await _advance_frames(3)
	var rev_death := _file_revision()
	_assert("G3_death_two_writes", ">=2", str(rev_death - rev0), rev_death - rev0 >= 2)
	var after_death: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	_assert("G4_pending_cleared_in_file", "空", str((after_death as Dictionary).get("pending_settlement_life_id", "?")),
		String((after_death as Dictionary).get("pending_settlement_life_id", "x")) == "")
	_assert("G5_settle_presented", "true", str(_entry.settle_panel.is_presenting()),
		_entry.settle_panel != null and _entry.settle_panel.is_presenting())

	# 发现 / 解锁各自落盘。
	gs.call("record_place_discovery", StringName(PROBE_PLACE_2))
	await _advance_frames(1)
	var after_disc: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	_assert("G6_discovery_saved", "含探针", str((after_disc as Dictionary).get("discovered_ids", [])),
		((after_disc as Dictionary).get("discovered_ids", []) as Array).has(PROBE_PLACE_2))
	gs.call("unlock_species", &"T037ProbeSpecies")
	await _advance_frames(1)
	var after_unlock: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	_assert("G7_unlock_saved", "含探针物种", str((after_unlock as Dictionary).get("unlocked_species", [])),
		((after_unlock as Dictionary).get("unlocked_species", []) as Array).has("T037ProbeSpecies"))

	# 退出：`_exit_tree` 再写一次。
	var rev_before_exit := _file_revision()
	_entry.queue_free()
	_entry = null
	await _advance_frames(3)
	_assert("G8_exit_saved", ">=%d" % (rev_before_exit + 1), str(_file_revision()),
		_file_revision() >= rev_before_exit + 1)


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _sm() -> Node:
	return root.get_node_or_null("/root/SaveManager")


func _gs() -> Node:
	return root.get_node_or_null("/root/GameState")


func _wd() -> Node:
	return root.get_node_or_null("/root/WorldDirector")


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


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _make_probe(pos: Vector3) -> Node3D:
	var packed := load(RP_SCENE) as PackedScene
	if packed == null:
		return null
	var rp := packed.instantiate() as Node3D
	rp.name = "T037Probe"
	rp.set("auto_advance", false)
	root.add_child(rp)
	rp.global_position = pos
	return rp


func _find_resource(id: String) -> Node:
	for n in get_nodes_in_group(&"resource_points"):
		if String(n.get("interaction_id")) == id:
			return n
	return null


func _first_region_id() -> String:
	for n in get_nodes_in_group(&"level_regions"):
		return String(n.get_meta("region_id", ""))
	return ""


func _is_pure_data(v: Variant) -> bool:
	if v == null or v is bool or v is int or v is float or v is String or v is StringName:
		return true
	if v is Array:
		for item in (v as Array):
			if not _is_pure_data(item):
				return false
		return true
	if v is Dictionary:
		for k in (v as Dictionary).keys():
			if not _is_pure_data((v as Dictionary)[k]):
				return false
		return true
	return false


func _has_abs_path(text: String) -> bool:
	var lower := text.to_lower()
	return lower.contains("c:\\\\") or lower.contains("c:/users") or lower.contains("e:/reborn") \
		or lower.contains("e:\\\\reborn")


func _find_prefix(list: Array, prefix: String) -> bool:
	for item in list:
		if String(item).begins_with(prefix):
			return true
	return false


func _normalized(text: String) -> String:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return text
	var d: Dictionary = (parsed as Dictionary).duplicate(true)
	d.erase("revision")
	d.erase("saved_reason")
	return JSON.stringify(d)


func _file_revision() -> int:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		return int((parsed as Dictionary).get("revision", -1))
	return -1
