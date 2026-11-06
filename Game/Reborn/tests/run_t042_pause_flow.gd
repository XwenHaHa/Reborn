extends SceneTree

const GameClock := preload("res://scripts/core/game_clock.gd")
## T042 暂停与主动结束确认 —— 先写可失败的断言（对应 `Docs/Tasks/T042.md` §6）。
##
## A 暂停入口 / B 冻结逐项 / C 恢复还原 / D Esc 优先级 / E 结束确认 / F 正常死亡路径 / G 契约。
## 首跑策略：新 API 一律 `has_method()/call()/get()` 探测；未实现时该段只落红，脚本不崩。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t042_pause_flow.gd' --quit-after 600000
## 结果口径：RESULT|pass=<n>|fail=<n>。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const TEST_DIR := "user://t042_tests"
const SAVE_PATH := "user://t042_tests/savegame_v1.json"
const EPS := 1e-9

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _entry: MainEntry = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	await _advance_frames(1)
	_clean_dir()
	GameClock.use_fake()
	var sm := _sm()
	if sm != null:
		sm.set("allow_headless_writes", true)
		sm.call("set_save_path", SAVE_PATH)

	await _section_a_pause_entry()
	await _section_b_freeze()
	await _section_c_resume()
	await _section_d_escape_priority()
	await _section_e_end_confirm()
	await _section_f_player_quit_path()
	await _section_g_contracts()

	_cleanup_scene()
	await _advance_frames(2)
	if paused:
		paused = false
	_clean_dir()
	_summary()
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------------------
# A 暂停入口：存活期可暂停；菜单文案与默认焦点；树暂停 + 时钟门闩
# ---------------------------------------------------------------------------

func _section_a_pause_entry() -> void:
	await _reset()
	await _load_main()
	if _entry == null:
		_assert("A0_entry", "MainEntry", "null", false)
		return
	var picked := _entry.select_species(&"Cat")
	await _advance_frames(8)
	_assert("A1_select_cat", "true", str(picked), picked)
	_assert("A2_alive_before_pause", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_assert("A3_player_before_pause", "非 null", str(_entry.player),
		_entry.player != null and is_instance_valid(_entry.player))

	# 先落一次盘（暂停前已有主档），用于“暂停不写盘”对照
	var pre_save: Dictionary = _entry.call("save_now", &"pre_pause")
	await _advance_frames(1)
	_assert("A4_pre_pause_save", "true", str(pre_save.get("ok", false)),
		bool(pre_save.get("ok", false)))
	_assert("A5_save_exists_before_pause", "true", str(FileAccess.file_exists(SAVE_PATH)),
		FileAccess.file_exists(SAVE_PATH))

	var revision_before_open := int(_sm_get("revision"))
	var save_before_open := _save_text()
	var opened: Variant = _entry_call("open_pause", false)
	await _advance_frames(3)
	_assert("A6_open_pause_accepted", "true", str(opened), bool(opened))
	_assert("A7_is_paused", "true", str(_entry_call("is_paused", false)),
		bool(_entry_call("is_paused", false)))
	_assert("A8_tree_paused", "true", str(paused), paused)
	_assert("A9_pause_menu_visible", "true", str(_node_call(_pause_node(), "is_open", false)),
		bool(_node_call(_pause_node(), "is_open", false)))
	_assert("A10_title", "游戏已暂停", str(_node_call(_pause_node(), "title_text", "")),
		String(_node_call(_pause_node(), "title_text", "")) == "游戏已暂停")
	_assert("A11_resume_text", "继续游戏", str(_node_call(_pause_node(), "resume_button_text", "")),
		String(_node_call(_pause_node(), "resume_button_text", "")) == "继续游戏")
	_assert("A12_end_text", "结束本次生命", str(_node_call(_pause_node(), "end_life_button_text", "")),
		String(_node_call(_pause_node(), "end_life_button_text", "")) == "结束本次生命")
	_assert("A13_hint", "Esc 继续游戏", str(_node_call(_pause_node(), "hint_text", "")),
		String(_node_call(_pause_node(), "hint_text", "")) == "Esc 继续游戏")
	_assert("A14_focus_resume", "继续游戏", str(_node_call(_pause_node(), "focused_button_text", "")),
		String(_node_call(_pause_node(), "focused_button_text", "")) == "继续游戏")
	_assert("A15_time_gate_off", "false", str(_wd_get("time_advancing")),
		not bool(_wd_get("time_advancing")))
	# 非存活状态拒绝暂停（稍后 G 段在 selecting 时再钉一次）
	_assert("A16_pause_needs_alive", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_assert("A17_open_pause_no_save", str(revision_before_open), str(int(_sm_get("revision"))),
		int(_sm_get("revision")) == revision_before_open)
	_assert("A18_open_pause_save_bytes_same", "same", _save_text(), _save_text() == save_before_open)


# ---------------------------------------------------------------------------
# B 冻结逐项：暂停 5 s 后世界时间/资源/区域/NPC/玩家/四指标/脚步/存档一字不变
# ---------------------------------------------------------------------------

func _section_b_freeze() -> void:
	if not bool(_entry_call("is_paused", false)):
		_assert("B0_paused_precondition", "true", str(_entry_call("is_paused", false)), false)
		return
	var t0 := _entry.world_time_now()
	var player: AnimalBody = _entry.player
	# 资源点：无存档时关卡里没有资源点，补建一个；设成“再晚 0.1 s 就该恢复”。
	var rp := _ensure_test_resource()
	if rp != null:
		rp.units = 0
		rp.capacity = maxi(2, rp.capacity)
		rp.refill_interval = 1.0
		rp.next_refill_at = t0 + 0.1
		rp.infinite = false
		rp.expire_at = 0.0
		rp.auto_advance = true
	# 区域账本：设成“再晚 0.1 s 就该恢复”
	var region := _prepare_region_recovery(t0)
	var region_key := String(region.get("key", ""))

	var sim_delta_before := float(_wd_get("sim_delta"))
	var res_units_before := int(rp.units) if rp != null else -1
	var res_next_before := float(rp.next_refill_at) if rp != null else -1.0
	var region_total_before := int(region.get("total_before", -1))
	var region_next_before := float(region.get("next_before", -1.0))
	var npc_xforms_before := _npc_transforms()
	var player_xform_before := str(player.global_transform)
	var player_vel_before := str(player.velocity)
	var survival_before := _survival(player)
	var steps_before := player.footstep_count
	var save_text_before := _save_text()
	var revision_before := int(_sm_get("revision"))

	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	# 暂停中跨过 5 s：用注入的单调时钟，不真等墙钟。
	GameClock.advance_ms(5000)
	await _advance_frames(2)
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")

	_assert("B1_clock_advance_5s", ">=5000ms", str(GameClock.now_ms()),
		GameClock.now_ms() >= 5000)
	_assert("B2_world_time_frozen", "%.6f" % t0, "%.6f" % _entry.world_time_now(),
		absf(_entry.world_time_now() - t0) <= EPS)
	_assert("B3_sim_delta_unchanged", "%.9f" % sim_delta_before, "%.9f" % float(_wd_get("sim_delta")),
		absf(float(_wd_get("sim_delta")) - sim_delta_before) <= EPS)
	_assert("B4_time_gate_still_off", "false", str(_wd_get("time_advancing")),
		not bool(_wd_get("time_advancing")))
	if rp != null:
		_assert("B5_resource_units_frozen", str(res_units_before), str(rp.units),
			rp.units == res_units_before)
		_assert("B6_resource_next_refill_frozen", "%.6f" % res_next_before,
			"%.6f" % rp.next_refill_at, absf(rp.next_refill_at - res_next_before) <= EPS)
	else:
		_assert("B5_resource_present", "非 null", "null", false)
	if region_key != "":
		var rec_after: Dictionary = _region_records().get(region_key, {})
		_assert("B7_region_total_frozen", str(region_total_before),
			str(int(rec_after.get("total_count", -1))),
			int(rec_after.get("total_count", -1)) == region_total_before)
		_assert("B8_region_next_recover_frozen", "%.6f" % region_next_before,
			"%.6f" % float(rec_after.get("next_recover_at", -1.0)),
			absf(float(rec_after.get("next_recover_at", -1.0)) - region_next_before) <= EPS)
	else:
		_assert("B7_region_present", "非空账本", "空", false)
	_assert("B9_npc_frozen", "same", _join(npc_xforms_before), npc_xforms_before == _npc_transforms())
	_assert("B10_player_transform_frozen", "same", player_xform_before,
		str(player.global_transform) == player_xform_before)
	_assert("B11_player_velocity_frozen", "same", player_vel_before,
		str(player.velocity) == player_vel_before)
	_assert("B12_survival_frozen", "same", str(survival_before), _survival(player) == survival_before)
	_assert("B13_footsteps_frozen", str(steps_before), str(player.footstep_count),
		player.footstep_count == steps_before)
	_assert("B14_no_save_during_pause", "same", _save_text(), _save_text() == save_text_before)
	_assert("B15_revision_unchanged", str(revision_before), str(int(_sm_get("revision"))),
		int(_sm_get("revision")) == revision_before)
	_assert("B16_input_no_effect", "0.0", str(player.velocity.length()),
		player.velocity.length() <= 0.001)


# ---------------------------------------------------------------------------
# C 恢复：逐字段还原；世界时间继续走、资源/区域继续恢复、消耗与移动恢复
# ---------------------------------------------------------------------------

func _section_c_resume() -> void:
	if not bool(_entry_call("is_paused", false)):
		_assert("C0_paused_precondition", "true", str(_entry_call("is_paused", false)), false)
		return
	var player: AnimalBody = _entry.player
	var t_at_resume := _entry.world_time_now()
	var hunger_at_resume := float(_survival(player).get("hunger", -1.0))
	var rp := _first_refillable_resource()
	var units_at_resume := int(rp.units) if rp != null else -1
	var region := _prepare_region_recovery(t_at_resume)
	var region_key := String(region.get("key", ""))
	var region_total_at_resume := int(region.get("total_before", -1))
	var pos_at_resume: Vector3 = player.global_position

	var resumed: Variant = _entry_call("resume_game", false)
	await _advance_frames(2)
	_assert("C1_resume_accepted", "true", str(resumed), bool(resumed))
	_assert("C2_not_paused", "false", str(_entry_call("is_paused", false)),
		not bool(_entry_call("is_paused", false)))
	_assert("C3_tree_running", "false", str(paused), not paused)
	_assert("C4_pause_menu_hidden", "false", str(_node_call(_pause_node(), "is_open", false)),
		not bool(_node_call(_pause_node(), "is_open", false)))
	_assert("C5_time_gate_on", "true", str(_wd_get("time_advancing")),
		bool(_wd_get("time_advancing")))
	# 恢复瞬间基线不跳变（"逐字段还原"）
	_assert("C6_world_time_continues_from_same", "%.6f" % t_at_resume,
		"%.6f" % _entry.world_time_now(),
		absf(_entry.world_time_now() - t_at_resume) <= 1.0)
	_assert("C7_survival_same_at_resume", "%.4f" % hunger_at_resume,
		"%.4f" % float(_survival(player).get("hunger", -2.0)),
		absf(float(_survival(player).get("hunger", -2.0)) - hunger_at_resume) <= 1.0)
	_assert("C8_position_same_at_resume", str(pos_at_resume), str(player.global_position),
		player.global_position.distance_to(pos_at_resume) <= 0.2)

	await _advance_world_seconds(0.7)
	_assert("C9_world_time_advances_after_resume", ">%.4f" % t_at_resume,
		"%.4f" % _entry.world_time_now(), _entry.world_time_now() > t_at_resume + 0.05)
	if rp != null:
		_assert("C10_resource_refills_after_resume", str(units_at_resume), str(rp.units),
			rp.units > units_at_resume)
	if region_key != "":
		var rec_after: Dictionary = _region_records().get(region_key, {})
		_assert("C11_region_recovers_after_resume", str(region_total_at_resume),
			str(int(rec_after.get("total_count", -1))),
			int(rec_after.get("total_count", -1)) > region_total_at_resume)
	_assert("C12_hunger_drops_after_resume", "<%.4f" % hunger_at_resume,
		"%.4f" % float(_survival(player).get("hunger", 999.0)),
		float(_survival(player).get("hunger", 999.0)) < hunger_at_resume)
	# 输入恢复：按住前进，位置应当变化（不是“暂停后输入失灵”）
	Input.action_press(&"move_forward")
	for i in 20:
		await physics_frame
	var moved := player.global_position.distance_to(pos_at_resume)
	Input.action_release(&"move_forward")
	_assert("C13_player_input_restored", ">0.01", "%.4f" % moved, moved > 0.01)
	_assert("C14_still_alive", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_assert("C15_player_controlled", "true", str(player.player_controlled), player.player_controlled)


# ---------------------------------------------------------------------------
# D Esc 优先级：结算页 > 确认层 > 暂停
# ---------------------------------------------------------------------------

func _section_d_escape_priority() -> void:
	if _entry == null or _entry.lifecycle_state_name() != "alive":
		_assert("D0_alive_precondition", "alive", _entry.lifecycle_state_name() if _entry != null else "null", false)
		return
	# 暂停中 Esc → 恢复
	var esc_resume: Variant = _entry_call("handle_escape", false)
	_assert("D1_esc_opens_pause", "true", str(esc_resume), bool(esc_resume))
	await _advance_frames(2)
	_assert("D2_paused_after_esc", "true", str(_entry_call("is_paused", false)),
		bool(_entry_call("is_paused", false)))
	var esc_again: Variant = _entry_call("handle_escape", false)
	_assert("D3_esc_resumes", "true", str(esc_again), bool(esc_again))
	await _advance_frames(2)
	_assert("D4_resumed_after_esc", "false", str(_entry_call("is_paused", false)),
		not bool(_entry_call("is_paused", false)))

	# 真实 Esc 键在树暂停时由 PauseMenu（PROCESS_MODE_ALWAYS）接管
	_entry_call("open_pause", false)
	await _advance_frames(2)
	var esc_key := InputEventKey.new()
	esc_key.keycode = KEY_ESCAPE
	esc_key.physical_keycode = KEY_ESCAPE
	esc_key.pressed = true
	Input.parse_input_event(esc_key)
	await _advance_frames(3)
	_assert("D4b_real_esc_resumes_while_paused", "false", str(_entry_call("is_paused", false)),
		not bool(_entry_call("is_paused", false)))

	# 入口接线：真实 InputEventAction("pause") 走 _unhandled_input
	var ev := InputEventAction.new()
	ev.action = &"pause"
	ev.pressed = true
	_entry.call("_unhandled_input", ev)
	await _advance_frames(2)
	_assert("D5_input_event_opens_pause", "true", str(_entry_call("is_paused", false)),
		bool(_entry_call("is_paused", false)))
	# 先恢复，回到“确认层可在非暂停时打开”的真实语境
	_entry_call("resume_game", false)
	await _advance_frames(2)

	# 确认层打开：Esc 不得开暂停（优先级高于暂停）
	var dialog := _entry.get("confirm_dialog") as Node
	if dialog != null and dialog.has_method("open"):
		dialog.call("open", "优先级测试")
		await _advance_frames(2)
		var escaped: Variant = _entry_call("handle_escape", true)
		_assert("D6_confirm_blocks_pause", "false", str(escaped), not bool(escaped))
		_assert("D7_still_not_paused", "false", str(_entry_call("is_paused", false)),
			not bool(_entry_call("is_paused", false)))
		_assert("D8_confirm_stays_open", "true", str(dialog.call("is_open")), bool(dialog.call("is_open")))
		dialog.call("cancel")
		await _advance_frames(2)
	else:
		_assert("D6_confirm_present", "非 null", "null", false)

	# 结束确认层打开：Esc 只取消确认、保持暂停（不得恢复游戏）
	if not bool(_entry_call("is_paused", false)):
		var o: Variant = _entry_call("open_pause", false)
		_assert("D9_reopen_pause", "true", str(o), bool(o))
		await _advance_frames(2)
	var req: Variant = _entry_call("request_end_life", false)
	await _advance_frames(2)
	_assert("D10_end_confirm_open", "true", str(_end_confirm_open()), _end_confirm_open())
	var confirm_esc: Variant = _entry_call("handle_escape", false)
	_assert("D11_esc_cancels_confirm", "true", str(confirm_esc), bool(confirm_esc))
	await _advance_frames(2)
	_assert("D12_confirm_closed", "false", str(_end_confirm_open()), not _end_confirm_open())
	_assert("D13_still_paused", "true", str(_entry_call("is_paused", false)),
		bool(_entry_call("is_paused", false)))
	_assert("D14_still_alive_after_cancel", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	# 真实 Esc：确认层优先，只取消确认、保持暂停（不触发 PauseMenu 的恢复）
	var req2: Variant = _entry_call("request_end_life", false)
	await _advance_frames(2)
	_assert("D15_confirm_reopen", "true", str(_end_confirm_open()), _end_confirm_open())
	Input.parse_input_event(esc_key.duplicate())
	await _advance_frames(3)
	_assert("D16_real_esc_cancels_confirm_only", "false", str(_end_confirm_open()),
		not _end_confirm_open())
	_assert("D17_still_paused_after_real_esc", "true", str(_entry_call("is_paused", false)),
		bool(_entry_call("is_paused", false)))
	_assert("D18_still_alive_after_real_esc", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")


# ---------------------------------------------------------------------------
# E 结束确认：默认焦点取消；取消后仍暂停/仍存活；暂停不写盘
# ---------------------------------------------------------------------------

func _section_e_end_confirm() -> void:
	if not bool(_entry_call("is_paused", false)):
		_assert("E0_paused_precondition", "true", str(_entry_call("is_paused", false)), false)
		return
	var req: Variant = _entry_call("request_end_life", false)
	await _advance_frames(3)
	_assert("E1_request_accepted", "true", str(req), bool(req))
	_assert("E2_confirm_open", "true", str(_end_confirm_open()), _end_confirm_open())
	_assert("E3_title", "结束本次生命？", str(_node_call(_end_confirm_node(), "title_text", "")),
		String(_node_call(_end_confirm_node(), "title_text", "")) == "结束本次生命？")
	_assert("E4_default_cancel", "取消", str(_node_call(_end_confirm_node(), "default_button_text", "")),
		String(_node_call(_end_confirm_node(), "default_button_text", "")) == "取消")
	_assert("E5_focus_cancel", "取消", str(_node_call(_end_confirm_node(), "focused_button_text", "")),
		String(_node_call(_end_confirm_node(), "focused_button_text", "")) == "取消")
	_assert("E6_pause_menu_below", "true", str(_node_call(_pause_node(), "is_open", false)),
		bool(_node_call(_pause_node(), "is_open", false)))
	var archive_before := _archive_count()
	var revision_before := int(_sm_get("revision"))
	var save_before := _save_text()
	GameClock.advance_ms(1000)
	await _advance_frames(2)
	_assert("E7_no_save_while_confirm", "same", _save_text(), _save_text() == save_before)
	_assert("E8_revision_unchanged", str(revision_before), str(int(_sm_get("revision"))),
		int(_sm_get("revision")) == revision_before)
	var cancelled: Variant = _entry_call("cancel_end_life", false)
	await _advance_frames(2)
	_assert("E9_cancel_accepted", "true", str(cancelled), bool(cancelled))
	_assert("E10_confirm_closed_after_cancel", "false", str(_end_confirm_open()), not _end_confirm_open())
	_assert("E11_still_paused_after_cancel", "true", str(_entry_call("is_paused", false)),
		bool(_entry_call("is_paused", false)))
	_assert("E12_still_alive_after_cancel", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_assert("E13_archive_unchanged", str(archive_before), str(_archive_count()),
		_archive_count() == archive_before)


# ---------------------------------------------------------------------------
# F 确认后：走正常死亡路径（归档 + player_quit + pending 存盘 + 结算页；不重生/不清档）
# ---------------------------------------------------------------------------

func _section_f_player_quit_path() -> void:
	if not bool(_entry_call("is_paused", false)):
		_assert("F0_paused_precondition", "true", str(_entry_call("is_paused", false)), false)
		return
	var life_before := _entry.current_life_id()
	var spawn_before := int(_entry.lifecycle.spawn_count)
	var settle_before := int(_entry.lifecycle.settle_count)
	var revision_before := int(_sm_get("revision"))
	var req: Variant = _entry_call("request_end_life", false)
	await _advance_frames(2)
	_assert("F1_request_accepted", "true", str(req), bool(req))
	var confirmed: Variant = _entry_call("confirm_end_life", false)
	await _advance_frames(4)
	_assert("F2_confirm_accepted", "true", str(confirmed), bool(confirmed))
	_assert("F3_not_paused_after_quit", "false", str(_entry_call("is_paused", false)),
		not bool(_entry_call("is_paused", false)))
	_assert("F4_tree_running_after_quit", "false", str(paused), not paused)
	_assert("F5_selecting_not_respawned", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")
	_assert("F6_no_player_after_quit", "null", str(_entry.player),
		_entry.player == null or not is_instance_valid(_entry.player))
	_assert("F7_no_direct_respawn", str(spawn_before), str(int(_entry.lifecycle.spawn_count)),
		int(_entry.lifecycle.spawn_count) == spawn_before)
	_assert("F8_settle_once", str(settle_before + 1), str(int(_entry.lifecycle.settle_count)),
		int(_entry.lifecycle.settle_count) == settle_before + 1)
	_assert("F9_archive_count_plus_one", "1", str(_archive_count()), _archive_count() == 1)
	_assert("F10_not_cleared", "true", str(FileAccess.file_exists(SAVE_PATH)),
		FileAccess.file_exists(SAVE_PATH))
	_assert("F11_not_blocked", "false", str(_entry.is_load_blocked()), not _entry.is_load_blocked())

	var rec := _entry.last_record()
	_assert("F12_record_life_id", life_before, str(rec.get("life_id", "")),
		String(rec.get("life_id", "")) == life_before)
	_assert("F13_end_reason_died", "died", str(rec.get("end_reason", "")),
		String(rec.get("end_reason", "")) == "died")
	_assert("F14_damage_reason_player_quit", "player_quit", str(rec.get("damage_reason", "")),
		String(rec.get("damage_reason", "")) == "player_quit")

	var events: Array = _gs().call("events_for", life_before)
	_assert("F15_event_sequence", "1", str(events.size()), events.size() >= 1)
	var last_kind := String((events[events.size() - 1] as Dictionary).get("kind", "")) if not events.is_empty() else ""
	_assert("F16_last_event_life_end", "life_end", last_kind, last_kind == "life_end")

	_assert("F17_settle_visible", "true", str(_settle_presenting()), _settle_presenting())
	_assert("F18_settle_text_player_quit", "死亡（player_quit）", _settle_text(),
		_settle_text().contains("死亡（player_quit）"))
	_assert("F19_settle_present_once", "1", str(int(_entry.settle_panel.call("present_count"))),
		int(_entry.settle_panel.call("present_count")) == 1)
	_assert("F20_pending_cleared", "", _entry.pending_settlement_life_id(),
		_entry.pending_settlement_life_id() == "")
	_assert("F21_two_critical_saves", ">= %d" % (revision_before + 2),
		str(int(_sm_get("revision"))), int(_sm_get("revision")) >= revision_before + 2)
	var saved := _saved_json()
	# 与 `_on_player_died` 完全同序：pending → end_life（内部 settle_shown 写）→ death 写，最终 reason=death。
	_assert("F22_saved_reason_death", "death", String(saved.get("saved_reason", "")),
		String(saved.get("saved_reason", "")) == "death")
	_assert("F23_saved_pending_empty", "", String(saved.get("pending_settlement_life_id", "?")),
		String(saved.get("pending_settlement_life_id", "?")) == "")
	_assert("F24_saved_no_current_life", "0", str((saved.get("current_life", {}) as Dictionary).size()),
		(saved.get("current_life", {}) as Dictionary).is_empty())
	var saved_records: Array = saved.get("life_records", [])
	var saved_rec := {}
	for r in saved_records:
		if String((r as Dictionary).get("life_id", "")) == life_before:
			saved_rec = r
	_assert("F25_saved_record_player_quit", "player_quit", String(saved_rec.get("damage_reason", "")),
		String(saved_rec.get("damage_reason", "")) == "player_quit")

	# 结算页最上：Esc 优先级最高，不得因 Esc 触发暂停
	var settle_esc: Variant = _entry_call("handle_escape", true)
	_assert("F26_settle_blocks_pause", "false", str(settle_esc), not bool(settle_esc))
	_assert("F27_not_paused_with_settle", "false", str(_entry_call("is_paused", false)),
		not bool(_entry_call("is_paused", false)))
	_assert("F28_settle_still_visible", "true", str(_settle_presenting()), _settle_presenting())

	# 菜单可见时状态行隐藏（T033 口径不改）
	_assert("F29_menu_visible", "true", str(_entry.menu.visible), _entry.menu.visible)
	_assert("F30_status_hidden_with_menu", "false", str(_entry.status_label.visible),
		not _entry.status_label.visible)
	# 选物种态不得暂停
	var paused_in_select: Variant = _entry_call("open_pause", false)
	_assert("F31_pause_rejected_in_selecting", "false", str(paused_in_select),
		not bool(paused_in_select))

	# 重生仍由玩家在结算后触发
	_entry.dismiss_settle()
	await _advance_frames(2)
	var respawned := _entry.select_species(&"Cat")
	await _advance_frames(6)
	_assert("F32_player_respawn_after_settle", "true", str(respawned), respawned)
	_assert("F33_alive_after_respawn", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_assert("F34_new_life_not_old", life_before, _entry.current_life_id(),
		_entry.current_life_id() != life_before)


# ---------------------------------------------------------------------------
# G 契约：树序、解锁集语义、状态行隐藏
# ---------------------------------------------------------------------------

func _section_g_contracts() -> void:
	if _entry == null:
		_assert("G0_entry", "MainEntry", "null", false)
		return
	var hud_i := -1
	var pause_i := -1
	var end_i := -1
	var menu_i := -1
	var status_i := -1
	var confirm_i := -1
	var settle_i := -1
	var kids := _entry.get_children()
	for i in kids.size():
		var k := kids[i]
		if k is PlayerHud:
			hud_i = i
		elif k.name == "PauseMenu":
			pause_i = i
		elif k.name == "EndLifeConfirm":
			end_i = i
		elif k.name == "MainMenu":
			menu_i = i
		elif k.name == "LifeStatus":
			status_i = i
		elif k.name == "NewGameConfirm":
			confirm_i = i
		elif k.name == "LifeSettlePanel":
			settle_i = i
	_assert("G1_tree_nodes", "全部存在",
		"hud=%d|pause=%d|end=%d|menu=%d|status=%d|confirm=%d|settle=%d" % [
			hud_i, pause_i, end_i, menu_i, status_i, confirm_i, settle_i],
		hud_i >= 0 and pause_i >= 0 and end_i >= 0 and menu_i >= 0 \
			and status_i >= 0 and confirm_i >= 0 and settle_i >= 0)
	_assert("G2_hud_pause_end", "hud<pause<end",
		"%d<%d<%d" % [hud_i, pause_i, end_i], hud_i < pause_i and pause_i < end_i)
	_assert("G3_pause_below_menu", "end<menu",
		"%d<%d" % [end_i, menu_i], end_i < menu_i)
	_assert("G4_legacy_menu_status_confirm_settle", "menu<status<confirm<settle",
		"%d<%d<%d<%d" % [menu_i, status_i, confirm_i, settle_i],
		menu_i < status_i and status_i < confirm_i and confirm_i < settle_i)

	# 解锁集语义：build([]) = 全部可玩；set_unlocked([]) = 全锁
	var probe := MainMenu.new()
	root.add_child(probe)
	await _advance_frames(1)
	probe.build(_entry.species_configs(), {}, [])
	_assert("G5_build_empty_all_playable", "0", str(probe.locked_list().size()),
		probe.locked_list().is_empty())
	probe.set_unlocked([])
	_assert("G6_set_unlocked_empty_locks_all", str(_entry.species_configs().size()),
		str(probe.locked_list().size()),
		probe.locked_list().size() == _entry.species_configs().size())
	probe.queue_free()

	# 清理：确保测试结束不把全局暂停留给后续套件
	if bool(_entry_call("is_paused", false)):
		_entry_call("resume_game", false)
	if paused:
		paused = false
	await _advance_frames(1)


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
		if bool(_entry_call("is_paused", false)):
			_entry_call("resume_game", false)
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


func _cleanup_scene() -> void:
	# 测试离场不触发既有 exit 存档（否则会把已拆树的玩家 transform 读爆）。
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


func _sm() -> Node:
	return root.get_node_or_null("/root/SaveManager")


func _gs() -> Node:
	return root.get_node_or_null("/root/GameState")


func _wd() -> Node:
	return root.get_node_or_null("/root/WorldDirector")


func _wd_get(field: String) -> Variant:
	var wd := _wd()
	return wd.get(field) if wd != null else null


func _sm_get(field: String) -> Variant:
	var sm := _sm()
	if sm == null:
		return null
	if field == "revision":
		return int(sm.get("revision"))
	return sm.get(field)


func _pause_node() -> Node:
	return _entry.get("pause_menu") as Node if _entry != null else null


func _end_confirm_node() -> Node:
	return _entry.get("end_life_confirm") as Node if _entry != null else null


func _end_confirm_open() -> bool:
	var n := _end_confirm_node()
	return bool(_node_call(n, "is_open", false))


func _settle_presenting() -> bool:
	return _entry != null and _entry.settle_panel != null and bool(_entry.settle_panel.call("is_presenting"))


func _settle_text() -> String:
	if _entry == null or _entry.settle_panel == null:
		return ""
	return String(_entry.settle_panel.call("summary_text"))


func _archive_count() -> int:
	var gs := _gs()
	return int(gs.call("archive_count")) if gs != null else -1


func _survival(player: AnimalBody) -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {}
	if player.survival == null or player.survival.state == null:
		return {}
	return (player.survival.state as SurvivalState).to_dictionary()


func _npc_transforms() -> Array[String]:
	var out: Array[String] = []
	if _entry == null or _entry.ecology == null:
		return out
	for b in _entry.ecology.npc_bodies():
		if b != null and is_instance_valid(b):
			out.append(str(b.global_transform))
	return out


## 无存档时关卡不生成资源点；补建一个只用于冻结/恢复断言的资源点。
func _ensure_test_resource() -> ResourcePoint:
	var existing := _first_refillable_resource()
	if existing != null:
		return existing
	if _entry == null or _entry.level == null:
		return null
	var packed := load("res://scenes/world/resource_point.tscn") as PackedScene
	if packed == null:
		return null
	var rp := packed.instantiate() as ResourcePoint
	if rp == null:
		return null
	rp.name = "T042TestResource"
	_entry.level.add_child(rp)
	return rp


func _first_refillable_resource() -> ResourcePoint:
	for n in get_nodes_in_group("resource_points"):
		var rp := n as ResourcePoint
		if rp != null and not rp.infinite and rp.capacity > 0:
			return rp
	return null


func _region_records() -> Dictionary:
	var wd := _wd()
	var raw = wd.get("region_records") if wd != null else null
	return raw as Dictionary if raw is Dictionary else {}


## 把一条区域记录设成“0.1 s 后就该恢复”，返回 {key,total_before,next_before}。
func _prepare_region_recovery(t0: float) -> Dictionary:
	var records := _region_records()
	if records.is_empty():
		return {}
	var key := ""
	for k in records.keys():
		var rec: Dictionary = records[k]
		if int(rec.get("capacity", 0)) > 0:
			key = String(k)
			break
	if key == "":
		return {}
	var rec2: Dictionary = records[key]
	rec2["total_count"] = maxi(0, mini(int(rec2.get("total_count", 0)), int(rec2.get("capacity", 1)) - 1))
	rec2["recover_interval"] = 1.0
	rec2["next_recover_at"] = t0 + 0.1
	return {"key": key, "total_before": int(rec2["total_count"]), "next_before": float(rec2["next_recover_at"])}


func _save_text() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return ""
	return FileAccess.get_file_as_string(SAVE_PATH)


func _saved_json() -> Dictionary:
	var parsed = JSON.parse_string(_save_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _join(lines: Array[String]) -> String:
	return "|".join(lines)


func _entry_call(method: String, fallback: Variant = null) -> Variant:
	if _entry != null and _entry.has_method(method):
		return _entry.call(method)
	return fallback


func _node_call(node: Node, method: String, fallback: Variant = null) -> Variant:
	if node != null and node.has_method(method):
		return node.call(method)
	return fallback


## 权威世界时间快进（不睡眠）：推进 world_time 后跑两帧让各系统按新时间结算。
func _advance_world_seconds(seconds: float) -> void:
	var wd := _wd()
	if wd != null:
		wd.call("set_world_time", float(wd.get("world_time")) + seconds)
	await _advance_frames(2)


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
