extends SceneTree
## T041 主菜单 / 继续 / 新游戏确认 —— 先写可失败的断言（对应 `Docs/Tasks/T041.md` §6）。
##
## A 有存档 / B 无存档 / C 双坏阻断 / D 备份恢复 / E 版本不兼容 / F 契约（树序、解锁集、默认焦点）。
## 首跑策略：新 API 一律 `has_method()/call()/get()` 探测；未实现时该段只落红，脚本不崩。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t041_main_menu_flow.gd' --quit-after 300000
## 结果口径：RESULT|pass=<n>|fail=<n>。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const TEST_DIR := "user://t041_tests"
const SAVE_PATH := "user://t041_tests/savegame_v1.json"
const MSG_CORRUPT := "存档损坏，已隔离；未载入"
const MSG_RECOVERED := "主存档损坏，已从备份恢复"
const MSG_VERSION := "存档版本不兼容"

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

	await _section_a_with_save()
	await _section_b_no_save()
	await _section_c_double_corrupt()
	await _section_d_backup_recovered()
	await _section_e_version_mismatch()
	await _section_f_contracts()

	_cleanup_scene()
	await _advance_frames(2)
	_clean_dir()
	_summary()
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------------------
# A 有存档（正常）：继续 + 新游戏；继续按 T037 顺序恢复；新游戏二次确认
# ---------------------------------------------------------------------------

func _section_a_with_save() -> void:
	await _reset()
	_write(SAVE_PATH, _valid_json(1, true))
	await _load_main()
	if _entry == null:
		_assert("A0_entry", "MainEntry", "null", false)
		return
	_assert("A1_status_ok", "ok", _status(), _status() == "ok")
	_assert("A2_menu_visible", "true", str(_menu_visible()), _menu_visible())
	_assert("A3_resume_visible", "true", str(_menu_call("resume_button_visible", false)),
		bool(_menu_call("resume_button_visible", false)))
	_assert("A4_resume_text", "继续", str(_menu_call("resume_button_text", "")),
		String(_menu_call("resume_button_text", "")) == "继续")
	_assert("A5_newgame_text", "新游戏", str(_menu_call("new_game_button_text", "")),
		String(_menu_call("new_game_button_text", "")) == "新游戏")
	_assert("A6_confirm_closed_at_start", "false", str(_dialog_open()), not _dialog_open())
	_assert("A7_status_hidden_with_menu", "false", str(_status_visible()), not _status_visible())
	_assert("A8_selecting_not_auto_spawn", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")
	_assert("A9_no_player_before_continue", "null", str(_entry.player), _entry.player == null)

	# 继续：按 T037 恢复当前生命（不分配新 LifeId）
	var resumed: Variant = _entry_call("continue_game", false)
	await _advance_frames(3)
	_assert("A10_continue_accepted", "true", str(resumed), bool(resumed))
	_assert("A11_alive_after_continue", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_assert("A12_player_after_continue", "非 null", str(_entry.player),
		_entry.player != null and is_instance_valid(_entry.player))
	_assert("A13_life_id_preserved", "L0001", _entry.current_life_id(),
		_entry.current_life_id() == "L0001")
	_assert("A14_world_time_restored", "≈100.0", str(_entry.world_time_now()),
		absf(_entry.world_time_now() - 100.0) < 1.0)
	_assert("A15_menu_hidden_after_continue", "false", str(_menu_visible()), not _menu_visible())

	# 新游戏 → 确认层；默认焦点取消；取消不动旧档
	var req: Variant = _entry_call("request_new_game", false)
	await _advance_frames(2)
	_assert("A16_confirm_open_on_new_game", "true", str(_dialog_open()), _dialog_open())
	_assert("A17_confirm_default_cancel", "取消", str(_dialog_call("default_button_text", "")),
		String(_dialog_call("default_button_text", "")) == "取消")
	_assert("A18_save_still_there_before_confirm", "true",
		str(FileAccess.file_exists(SAVE_PATH)), FileAccess.file_exists(SAVE_PATH))
	_dialog_call("cancel", null)
	await _advance_frames(2)
	_assert("A19_cancel_keeps_alive", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_assert("A20_cancel_keeps_save", "true", str(FileAccess.file_exists(SAVE_PATH)),
		FileAccess.file_exists(SAVE_PATH))
	_assert("A21_cancel_closes_dialog", "false", str(_dialog_open()), not _dialog_open())

	# 再次确认 → 清档并进入物种选择
	var req2: Variant = _entry_call("request_new_game", false)
	await _advance_frames(2)
	_dialog_call("confirm", null)
	await _advance_frames(3)
	_assert("A22_selecting_after_new_game", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")
	_assert("A23_save_cleared", "false", str(FileAccess.file_exists(SAVE_PATH)),
		not FileAccess.file_exists(SAVE_PATH))
	_assert("A24_archive_reset", "0", str(_archive_count()), _archive_count() == 0)
	_assert("A25_resume_hidden_after_new_game", "false",
		str(_menu_call("resume_button_visible", false)),
		not bool(_menu_call("resume_button_visible", false)))
	_assert("A26_not_blocked_after_new_game", "false", str(_blocked()), not _blocked())
	_assert("A27_species_page_after_new_game", "1", str(_menu_page()),
		_menu_page() == 1)
	_assert("A28_default_cat_playable", "true", str(_has_slot(&"Cat")), _has_slot(&"Cat"))
	var old_req: Variant = req2
	_assert("A29_new_game_waited_for_confirm", "false", str(bool(old_req)), not bool(old_req))


# ---------------------------------------------------------------------------
# B 无存档：不显示继续，不落进空载入；新游戏无需确认
# ---------------------------------------------------------------------------

func _section_b_no_save() -> void:
	await _reset()
	await _load_main()
	if _entry == null:
		_assert("B0_entry", "MainEntry", "null", false)
		return
	_assert("B1_status_none", "none", _status(), _status() == "none")
	_assert("B2_resume_hidden", "false", str(_menu_call("resume_button_visible", false)),
		not bool(_menu_call("resume_button_visible", false)))
	_assert("B3_continue_rejected", "false", str(_entry_call("continue_game", true)),
		not bool(_entry_call("continue_game", true)))
	_assert("B4_no_player", "null", str(_entry.player), _entry.player == null)
	_assert("B5_selecting", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")
	var req: Variant = _entry_call("request_new_game", false)
	await _advance_frames(3)
	_assert("B6_no_confirm_without_save", "false", str(_dialog_open()), not _dialog_open())
	_assert("B7_species_page", "1", str(_menu_page()), _menu_page() == 1)
	_assert("B8_still_no_save", "false", str(FileAccess.file_exists(SAVE_PATH)),
		not FileAccess.file_exists(SAVE_PATH))
	_assert("B9_new_game_accepted", "true", str(req), bool(req))


# ---------------------------------------------------------------------------
# C 双坏阻断：唯一出路「确认开始新游戏」；确认前不保存、不静默开新档
# ---------------------------------------------------------------------------

func _section_c_double_corrupt() -> void:
	await _reset()
	_write(SAVE_PATH, "{ broken main")
	_write(SAVE_PATH + ".bak", "{ broken bak")
	await _load_main()
	if _entry == null:
		_assert("C0_entry", "MainEntry", "null", false)
		return
	_assert("C1_status_corrupt", "corrupt", _status(), _status() == "corrupt")
	_assert("C2_blocked", "true", str(_blocked()), _blocked())
	_assert("C3_blocked_view", "true", str(_menu_call("is_blocked_view", false)),
		bool(_menu_call("is_blocked_view", false)))
	_assert("C4_blocked_message", MSG_CORRUPT, str(_menu_call("blocked_message", "")),
		String(_menu_call("blocked_message", "")) == MSG_CORRUPT)
	_assert("C5_resume_hidden", "false", str(_menu_call("resume_button_visible", false)),
		not bool(_menu_call("resume_button_visible", false)))
	_assert("C6_blocked_button_text", "确认开始新游戏",
		str(_menu_call("blocked_button_text", "")),
		String(_menu_call("blocked_button_text", "")) == "确认开始新游戏")
	_assert("C7_confirm_closed", "false", str(_dialog_open()), not _dialog_open())
	_assert("C8_continue_rejected", "false", str(_entry_call("continue_game", true)),
		not bool(_entry_call("continue_game", true)))
	_assert("C9_select_denied", "false", str(_entry.select_species(&"Cat")),
		not _entry.select_species(&"Cat"))
	var save_res: Dictionary = _entry.call("save_now", &"c_blocked")
	_assert("C10_save_blocked", "blocked", String(save_res.get("status", "")),
		String(save_res.get("status", "")) == "blocked")
	_assert("C11_no_main_before_confirm", "false", str(FileAccess.file_exists(SAVE_PATH)),
		not FileAccess.file_exists(SAVE_PATH))
	_assert("C12_still_selecting", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")

	# 阻断页唯一按钮：标签本身就是确认
	var req: Variant = _entry_call("request_new_game", false)
	await _advance_frames(3)
	_assert("C13_unblocked_after_confirm", "false", str(_blocked()), not _blocked())
	_assert("C14_blocked_view_off", "false", str(_menu_call("is_blocked_view", false)),
		not bool(_menu_call("is_blocked_view", false)))
	_assert("C15_species_page", "1", str(_menu_page()), _menu_page() == 1)
	var picked := _entry.select_species(&"Cat")
	_assert("C16_select_allowed", "true", str(picked), picked)
	await _advance_frames(4)
	_assert("C17_alive_after_confirm", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_assert("C18_no_main_until_save", "false", str(FileAccess.file_exists(SAVE_PATH)),
		not FileAccess.file_exists(SAVE_PATH))
	var after: Dictionary = _entry.call("save_now", &"c_after")
	_assert("C19_save_allowed_after_confirm", "blocked", String(after.get("status", "")),
		String(after.get("status", "")) != "blocked")


# ---------------------------------------------------------------------------
# D 主档损坏、已从备份恢复：提示后正常继续；不弹新游戏确认
# ---------------------------------------------------------------------------

func _section_d_backup_recovered() -> void:
	await _reset()
	_write(SAVE_PATH + ".bak", _valid_json(1, true))
	_write(SAVE_PATH, "{ broken main")
	await _load_main()
	if _entry == null:
		_assert("D0_entry", "MainEntry", "null", false)
		return
	_assert("D1_status_recovered", "recovered_backup", _status(),
		_status() == "recovered_backup")
	_assert("D2_notice", MSG_RECOVERED, str(_menu_call("session_notice_text", "")),
		String(_menu_call("session_notice_text", "")).contains(MSG_RECOVERED))
	_assert("D3_resume_visible", "true", str(_menu_call("resume_button_visible", false)),
		bool(_menu_call("resume_button_visible", false)))
	_assert("D4_no_confirm_popup", "false", str(_dialog_open()), not _dialog_open())
	_assert("D5_not_blocked", "false", str(_blocked()), not _blocked())
	_assert("D6_blocked_view_off", "false", str(_menu_call("is_blocked_view", false)),
		not bool(_menu_call("is_blocked_view", false)))
	var resumed: Variant = _entry_call("continue_game", false)
	await _advance_frames(3)
	_assert("D7_continue_ok", "true", str(resumed), bool(resumed))
	_assert("D8_alive", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_assert("D9_player", "非 null", str(_entry.player),
		_entry.player != null and is_instance_valid(_entry.player))


# ---------------------------------------------------------------------------
# E 版本不兼容：提示 vN；旧档仍在、不隔离、不阻断；确认后才清
# ---------------------------------------------------------------------------

func _section_e_version_mismatch() -> void:
	await _reset()
	_write(SAVE_PATH, _valid_json(7, true))
	await _load_main()
	if _entry == null:
		_assert("E0_entry", "MainEntry", "null", false)
		return
	_assert("E1_status_version", "version_mismatch", _status(),
		_status() == "version_mismatch")
	_assert("E2_message_has_v7", "（v7）", str(_entry.get("_load_message")),
		String(_entry.get("_load_message")).contains("（v7）"))
	_assert("E3_message_text", MSG_VERSION, str(_entry.get("_load_message")),
		String(_entry.get("_load_message")).contains(MSG_VERSION))
	_assert("E4_old_save_kept", "true", str(FileAccess.file_exists(SAVE_PATH)),
		FileAccess.file_exists(SAVE_PATH))
	_assert("E5_not_blocked", "false", str(_blocked()), not _blocked())
	_assert("E6_blocked_view_off", "false", str(_menu_call("is_blocked_view", false)),
		not bool(_menu_call("is_blocked_view", false)))
	_assert("E7_resume_hidden", "false", str(_menu_call("resume_button_visible", false)),
		not bool(_menu_call("resume_button_visible", false)))
	_assert("E8_notice", MSG_VERSION, str(_menu_call("session_notice_text", "")),
		String(_menu_call("session_notice_text", "")).contains(MSG_VERSION))
	_assert("E9_no_quarantine", "0", str(_corrupt_count()), _corrupt_count() == 0)
	_assert("E10_continue_rejected", "false", str(_entry_call("continue_game", true)),
		not bool(_entry_call("continue_game", true)))

	var req: Variant = _entry_call("request_new_game", false)
	await _advance_frames(2)
	_assert("E11_confirm_on_new_game", "true", str(_dialog_open()), _dialog_open())
	_assert("E12_default_cancel", "取消", str(_dialog_call("default_button_text", "")),
		String(_dialog_call("default_button_text", "")) == "取消")
	_dialog_call("cancel", null)
	await _advance_frames(2)
	_assert("E13_cancel_keeps_old_save", "true", str(FileAccess.file_exists(SAVE_PATH)),
		FileAccess.file_exists(SAVE_PATH))
	var req2: Variant = _entry_call("request_new_game", false)
	await _advance_frames(2)
	_dialog_call("confirm", null)
	await _advance_frames(3)
	_assert("E14_confirm_clears_old_save", "false", str(FileAccess.file_exists(SAVE_PATH)),
		not FileAccess.file_exists(SAVE_PATH))
	_assert("E15_selecting_after_new_game", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")


# ---------------------------------------------------------------------------
# F 契约：UI 树序、解锁集语义、状态行隐藏、默认焦点
# ---------------------------------------------------------------------------

func _section_f_contracts() -> void:
	if _entry == null:
		_assert("F0_entry", "MainEntry", "null", false)
		return
	var hud_i := -1
	var menu_i := -1
	var status_i := -1
	var confirm_i := -1
	var settle_i := -1
	var kids := _entry.get_children()
	for i in kids.size():
		var k := kids[i]
		if k is PlayerHud:
			hud_i = i
		elif k.name == "MainMenu":
			menu_i = i
		elif k.name == "LifeStatus":
			status_i = i
		elif k.name == "NewGameConfirm":
			confirm_i = i
		elif k.name == "LifeSettlePanel":
			settle_i = i
	_assert("F1_tree_nodes", "全部存在",
		"hud=%d|menu=%d|status=%d|confirm=%d|settle=%d" % [hud_i, menu_i, status_i, confirm_i, settle_i],
		hud_i >= 0 and menu_i >= 0 and status_i >= 0 and confirm_i >= 0 and settle_i >= 0)
	_assert("F2_order_hud_menu_status", "hud<menu<status",
		"%d<%d<%d" % [hud_i, menu_i, status_i], hud_i < menu_i and menu_i < status_i)
	_assert("F3_confirm_above_menu", "menu<confirm",
		"%d<%d" % [menu_i, confirm_i], menu_i < confirm_i)
	_assert("F4_confirm_below_settle", "confirm<settle",
		"%d<%d" % [confirm_i, settle_i], confirm_i < settle_i)
	_assert("F5_legacy_order_menu_status_settle", "menu<status<settle",
		"%d<%d<%d" % [menu_i, status_i, settle_i], menu_i < status_i and status_i < settle_i)
	_assert("F6_status_hidden_while_menu", "false", str(_status_visible()), not _status_visible())
	_assert("F7_menu_visible", "true", str(_menu_visible()), _menu_visible())
	_assert("F8_not_blocked_final", "false", str(_blocked()), not _blocked())

	# 解锁集语义：build([]) = 全部可玩；set_unlocked([]) = 全锁
	var probe := MainMenu.new()
	root.add_child(probe)
	await _advance_frames(1)
	probe.build(_entry.species_configs(), {}, [])
	_assert("F9_build_empty_all_playable", "0", str(probe.locked_list().size()),
		probe.locked_list().is_empty())
	probe.set_unlocked([])
	_assert("F10_set_unlocked_empty_locks_all", str(_entry.species_configs().size()),
		str(probe.locked_list().size()),
		probe.locked_list().size() == _entry.species_configs().size())
	probe.queue_free()

	# 默认焦点：直接打开确认层，焦点必须是取消（不走 request_new_game，
	# 因为此前的开新局已把槽清空，此时没有可覆盖旧档）。
	var d := _dialog()
	if d != null and d.has_method("open"):
		d.call("open", "焦点校验")
	await _advance_frames(2)
	_assert("F11_confirm_reopen", "true", str(_dialog_open()), _dialog_open())
	_assert("F12_focus_is_cancel", "取消", str(_dialog_call("focused_button_text", "")),
		String(_dialog_call("focused_button_text", "")) == "取消")
	_dialog_call("cancel", null)
	await _advance_frames(2)


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


func _load_main() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_assert("LOAD|scene", "可加载", "null", false)
		return
	change_scene_to_packed(packed)
	await _advance_frames(8)
	_entry = current_scene as MainEntry


func _cleanup_scene() -> void:
	if current_scene != null:
		current_scene = null
	if _entry != null and is_instance_valid(_entry):
		_entry.queue_free()
	_entry = null


func _clean_dir() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(TEST_DIR)
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(TEST_DIR.path_join(String(f)))


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _sm() -> Node:
	return root.get_node_or_null("/root/SaveManager")


func _gs() -> Node:
	return root.get_node_or_null("/root/GameState")


func _status() -> String:
	if _entry == null:
		return ""
	return String(_entry.get("_load_status"))


func _blocked() -> bool:
	if _entry == null:
		return false
	return bool(_entry.get("_load_blocked"))


func _menu_visible() -> bool:
	return _entry != null and _entry.menu != null and _entry.menu.visible


func _menu_page() -> int:
	if _entry == null or _entry.menu == null:
		return -1
	return _entry.menu.current_page()


func _status_visible() -> bool:
	return _entry != null and _entry.status_label != null and _entry.status_label.visible


func _archive_count() -> int:
	var gs := _gs()
	return int(gs.call("archive_count")) if gs != null else -1


func _has_slot(id: StringName) -> bool:
	if _entry == null:
		return false
	return _entry.selectable_slots().has(id)


func _entry_call(method: String, fallback: Variant = null) -> Variant:
	if _entry != null and _entry.has_method(method):
		return _entry.call(method)
	return fallback


func _menu_call(method: String, fallback: Variant = null) -> Variant:
	if _entry == null or _entry.menu == null:
		return fallback
	if _entry.menu.has_method(method):
		return _entry.menu.call(method)
	return fallback


func _dialog() -> Node:
	if _entry == null:
		return null
	return _entry.get("confirm_dialog") as Node


func _dialog_open() -> bool:
	var d := _dialog()
	if d != null and d.has_method("is_open"):
		return bool(d.call("is_open"))
	return false


func _dialog_call(method: String, fallback: Variant = null) -> Variant:
	var d := _dialog()
	if d != null and d.has_method(method):
		return d.call(method)
	return fallback


func _corrupt_count() -> int:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return 0
	var n := 0
	for f in dir.get_files():
		if String(f).contains(".corrupt-"):
			n += 1
	return n


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


## 一份通过 T037 校验的 v1 存档；`with_current=true` 时带存活当前生命（「继续」可用）
func _valid_json(version: int, with_current: bool) -> String:
	var current := {}
	if with_current:
		current = {
			"life_id": "L0001",
			"species_id": "Cat",
			"start_world_time": 0.0,
			"end_world_time": -1.0,
			"duration": -1.0,
			"end_reason": "",
			"damage_reason": "",
			"snapshot": {"health": 80.0, "hunger": 70.0, "thirst": 65.0, "stamina": 90.0},
			"transform": {"$t": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0,
				-10.0, 0.6, 16.0]},
			"start_position": {"$v": [-10.0, 0.6, 16.0]},
			"captures": 0,
			"escapes": 0,
			"food_gained": 0.0,
			"water_gained": 0.0,
			"discoveries": [],
			"event_first": 1,
			"event_last": 1,
		}
	return JSON.stringify({
		"save_version": version,
		"revision": 3,
		"world_time": 100.0,
		"resources": [],
		"regions": [],
		"discovered_ids": [],
		"unlocked_species": ["Cat"],
		"life_records": [],
		"current_life": current,
		"pending_settlement_life_id": "",
		"events": [
			{"seq": 1, "life_id": "L0001", "kind": "life_start", "world_time": 0.0,
				"data": {"species": "Cat"}},
		],
		"life_counter": 1,
		"event_seq": 1,
		"saved_reason": "t041",
	})
