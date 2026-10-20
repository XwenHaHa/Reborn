extends SceneTree
## T030 生命周期状态与事件记录（`Docs/Tasks/T030.md` §6）
##
## 验证：状态机迁移表与非法迁移拒绝、物种门（解锁 / test_mode）、死亡**只结算一次**、
## 档案字段（含时长与结束原因）、事件 seq 与封顶、长期数据跨世保留、正式入口闭环。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t030_lifecycle.gd' --quit-after 300000

const LIFE_CYCLE := "res://scripts/core/life_cycle.gd"
const GAME_STATE := "res://autoload/game_state.gd"
const MAIN_ENTRY := "res://scripts/core/main_entry.gd"
const MAIN := "res://scenes/core/main.tscn"
const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"

const EPS := 1e-3
const MAX_EVENTS_EXPECTED := 1024
const STATUS_FORBIDDEN := ["Debug", "debug", "PARAMS|", "MOV|"]

var _checks := 0
var _fails := 0
var _gs: Node = null
var _wd: Node = null
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null
var _cats: StringName = &""
var _mice: StringName = &""


func _initialize() -> void:
	print("TEST|run_t030_lifecycle|engine=%s" % Engine.get_version_info().string)
	_gs = root.get_node_or_null("GameState")
	_wd = root.get_node_or_null("WorldDirector")
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig
	_cats = _cat.species_id if _cat != null else &"cat"
	_mice = _mouse.species_id if _mouse != null else &"mouse"
	await _section_a_contract()
	await _section_b_state_machine()
	await _section_c_species_gate()
	await _section_d_settle_once()
	await _section_e_record_fields()
	await _section_f_events()
	await _section_g_long_term()
	await _section_h_entry()
	_finish()


# ---------------------------------------------------------------------------
# A 契约
# ---------------------------------------------------------------------------

func _section_a_contract() -> void:
	print("---- A 契约 ----")
	var script := load(LIFE_CYCLE) as Script
	_assert("A1_life_cycle_script", "非 null", str(script != null), script != null)
	if script == null:
		return
	var probe: Object = script.new()
	_assert("A2_is_life_cycle", "LifeCycle", "LifeCycle" if probe is LifeCycle else probe.get_class(),
		probe is LifeCycle)
	_assert("A3_state_enum", "ALIVE=0,SETTLING=1,SELECTING=2,SPAWNING=3",
		"%d,%d,%d,%d" % [LifeCycle.State.ALIVE, LifeCycle.State.SETTLING,
			LifeCycle.State.SELECTING, LifeCycle.State.SPAWNING],
		LifeCycle.State.ALIVE == 0 and LifeCycle.State.SETTLING == 1
			and LifeCycle.State.SELECTING == 2 and LifeCycle.State.SPAWNING == 3)
	if probe is Node:
		(probe as Node).free()

	_assert("A4_game_state_autoload", "非 null", str(_gs != null), _gs != null)
	if _gs == null:
		return
	_assert("A5_max_events_is_const", str(MAX_EVENTS_EXPECTED), str(_const_of(GAME_STATE, "MAX_EVENTS")),
		_const_of(GAME_STATE, "MAX_EVENTS") == MAX_EVENTS_EXPECTED)
	_assert("A6_max_events_on_instance", str(MAX_EVENTS_EXPECTED), str(int(_gs.get("MAX_EVENTS"))),
		int(_gs.get("MAX_EVENTS")) == MAX_EVENTS_EXPECTED)
	_gs.call("reset_for_new_game")
	_assert("A7_life_id_format", "L0001", str(_gs.call("peek_life_id")),
		String(_gs.call("peek_life_id")) == "L0001")

	# 输入动作键码用引擎常量核对，不靠猜
	_assert("A8_action_select_1_exists", "true", str(InputMap.has_action("life_select_1")),
		InputMap.has_action("life_select_1"))
	_assert("A9_action_select_2_exists", "true", str(InputMap.has_action("life_select_2")),
		InputMap.has_action("life_select_2"))
	_assert("A10_select_1_is_key_1", str(KEY_1), str(_first_keycode("life_select_1")),
		_first_keycode("life_select_1") == int(KEY_1))
	_assert("A11_select_2_is_key_2", str(KEY_2), str(_first_keycode("life_select_2")),
		_first_keycode("life_select_2") == int(KEY_2))

	# 正式场景：单个 Node3D + 正式入口脚本，不含调试节点/CanvasLayer
	var packed := load(MAIN) as PackedScene
	_assert("A12_main_scene_loads", "非 null", str(packed != null), packed != null)
	if packed == null:
		return
	var main := packed.instantiate()
	_assert("A13_main_root_node3d", "Node3D", main.get_class(), main is Node3D)
	var script_path := ""
	if main.get_script() != null:
		script_path = String((main.get_script() as Script).resource_path)
	_assert("A14_main_uses_entry_script", MAIN_ENTRY, script_path, script_path == MAIN_ENTRY)
	_assert("A15_main_no_canvas_layer", "0", str(_count_class(main, "CanvasLayer")),
		_count_class(main, "CanvasLayer") == 0)
	_assert("A16_main_no_debug_script", "0", str(_count_debug(main)), _count_debug(main) == 0)
	main.free()


# ---------------------------------------------------------------------------
# B 状态机
# ---------------------------------------------------------------------------

func _section_b_state_machine() -> void:
	print("---- B 状态机 ----")
	_gs.call("reset_for_new_game")
	_gs.set("test_mode", true)
	var lc := _new_cycle()
	_assert("B1_initial_settling", "settling", lc.current_state_name(),
		lc.state == LifeCycle.State.SETTLING)
	var selected := lc.request_select()
	_assert("B2_select_ok", "true", str(selected), selected and lc.state == LifeCycle.State.SELECTING)
	_assert("B3_time_frozen_while_selecting", "false", str(lc.time_is_advancing()),
		not lc.time_is_advancing())
	var spawned := lc.begin_spawn(_mice)
	_assert("B4_spawn_ok", "true", str(spawned), spawned and lc.state == LifeCycle.State.SPAWNING)
	_assert("B5_spawn_kept_time_frozen", "false", str(lc.time_is_advancing()),
		not lc.time_is_advancing())
	var life := lc.mark_spawned(null, Vector3.ZERO)
	_assert("B6_alive_after_spawn", "alive", lc.current_state_name(), lc.state == LifeCycle.State.ALIVE)
	_assert("B7_life_id_assigned", "L0001", life, life == "L0001")
	_assert("B8_time_resumed", "true", str(lc.time_is_advancing()), lc.time_is_advancing())

	# 非法迁移：状态不变 + 记录拒绝
	var before := lc.rejection_count()
	var rejected := lc.request_select()
	_assert("B9_double_select_rejected", "false", str(rejected), not rejected)
	_assert("B10_state_unchanged_after_reject", "alive", lc.current_state_name(),
		lc.state == LifeCycle.State.ALIVE)
	_assert("B11_reject_recorded", str(before + 1), str(lc.rejection_count()),
		lc.rejection_count() == before + 1)
	_assert("B12_reject_reason", "wrong_state", String(lc.last_rejection().get("reason", "")),
		String(lc.last_rejection().get("reason", "")) == "wrong_state")
	var respawn := lc.mark_spawned(null)
	_assert("B13_mark_spawned_in_alive_rejected", "", respawn, respawn == "")

	# 结算后：再次结算被拒（already_settled）
	var rec := lc.end_life(&"test_end")
	_assert("B14_settled_to_settling", "settling", lc.current_state_name(),
		lc.state == LifeCycle.State.SETTLING)
	_assert("B15_record_returned", "true", str(not rec.is_empty()), not rec.is_empty())
	_assert("B16_body_released", "true", str(lc.body == null), lc.body == null)
	var before2 := lc.rejection_count()
	var again := lc.end_life(&"test_end")
	_assert("B17_second_settle_rejected", "空字典", str(again.size()), again.is_empty())
	_assert("B18_second_settle_reason", "already_settled", String(lc.last_rejection().get("reason", "")),
		String(lc.last_rejection().get("reason", "")) == "already_settled")
	_assert("B19_second_settle_logged", str(before2 + 1), str(lc.rejection_count()),
		lc.rejection_count() == before2 + 1)
	_assert("B20_settle_count_is_one", "1", str(lc.settle_count), lc.settle_count == 1)
	lc.free()


# ---------------------------------------------------------------------------
# C 物种门
# ---------------------------------------------------------------------------

func _section_c_species_gate() -> void:
	print("---- C 物种门 ----")
	_gs.call("reset_for_new_game")
	_gs.set("test_mode", false)
	var lc := _new_cycle()
	lc.request_select()
	var locked := lc.begin_spawn(_cats)
	_assert("C1_locked_rejected", "false", str(locked), not locked)
	_assert("C2_locked_reason", "locked_species", String(lc.last_rejection().get("reason", "")),
		String(lc.last_rejection().get("reason", "")) == "locked_species")
	_assert("C3_state_still_selecting", "selecting", lc.current_state_name(),
		lc.state == LifeCycle.State.SELECTING)
	var unlocked := bool(_gs.call("unlock_species", _cats))
	_assert("C4_unlock_new", "true", str(unlocked), unlocked)
	var again := bool(_gs.call("unlock_species", _cats))
	_assert("C5_unlock_idempotent", "false", str(again), not again)
	var ok := lc.begin_spawn(_cats)
	_assert("C6_unlocked_spawn_ok", "true", str(ok), ok and lc.state == LifeCycle.State.SPAWNING)
	lc.mark_spawned(null)
	lc.end_life(&"c_done")

	# test_mode 放行未解锁物种
	_gs.call("reset_for_new_game")
	_gs.set("test_mode", true)
	var lc2 := _new_cycle()
	lc2.request_select()
	var ok2 := lc2.begin_spawn(_cats)
	_assert("C7_test_mode_allows_locked", "true", str(ok2), ok2 and lc2.state == LifeCycle.State.SPAWNING)
	lc2.mark_spawned(null)
	lc2.end_life(&"c_done2")
	# 未知物种：即使是测试模式也拒绝
	lc2.request_select()
	var unknown := lc2.begin_spawn(&"no_such_species")
	_assert("C8_unknown_species_rejected", "false", str(unknown), not unknown)
	_assert("C9_unknown_reason", "unknown_species", String(lc2.last_rejection().get("reason", "")),
		String(lc2.last_rejection().get("reason", "")) == "unknown_species")
	lc.free()
	lc2.free()


# ---------------------------------------------------------------------------
# D 死亡只结算一次
# ---------------------------------------------------------------------------

func _section_d_settle_once() -> void:
	print("---- D 死亡只结算一次 ----")
	_gs.call("reset_for_new_game")
	_gs.set("test_mode", true)
	var lc := _new_cycle()
	var ended := [0]
	lc.life_settled.connect(func(_r: Dictionary) -> void: ended[0] += 1)
	lc.request_select()
	lc.begin_spawn(_mice)
	var life := lc.mark_spawned(null)
	_assert("D1_life_started", "alive", lc.current_state_name(), lc.state == LifeCycle.State.ALIVE)
	lc.end_life(&"died", {"damage_reason": "attack"})
	lc.end_life(&"died", {"damage_reason": "attack"})
	lc.end_life(&"starved")
	var direct: Dictionary = _gs.call("end_life", &"died")
	_assert("D2_direct_second_end_empty", "空字典", str(direct.size()), direct.is_empty())
	_assert("D3_archive_single", "1", str(int(_gs.call("archive_count"))),
		int(_gs.call("archive_count")) == 1)
	_assert("D4_signal_single", "1", str(ended[0]), ended[0] == 1)
	_assert("D5_settle_count_single", "1", str(lc.settle_count), lc.settle_count == 1)
	var rec: Dictionary = _gs.call("last_record")
	_assert("D6_record_life_id", life, String(rec.get("life_id", "")),
		String(rec.get("life_id", "")) == life)
	_assert("D7_record_end_reason", "died", String(rec.get("end_reason", "")),
		String(rec.get("end_reason", "")) == "died")
	_assert("D8_record_damage_reason", "attack", String(rec.get("damage_reason", "")),
		String(rec.get("damage_reason", "")) == "attack")
	lc.free()


# ---------------------------------------------------------------------------
# E 档案字段
# ---------------------------------------------------------------------------

func _section_e_record_fields() -> void:
	print("---- E 档案字段 ----")
	_gs.call("reset_for_new_game")
	_gs.set("test_mode", true)
	_wd.set_world_time(10.0)
	var lc := _new_cycle()
	lc.request_select()
	lc.begin_spawn(_mice)
	var life := lc.mark_spawned(null, Vector3(1.0, 2.0, 3.0))
	_gs.call("add_to_life", "captures", 1)
	_gs.call("add_to_life", "escapes", 2)
	_gs.call("add_to_life", "food_gained", 3.5)
	_gs.call("add_to_life", "water_gained", 1.25)
	_gs.call("record_discovery", &"地点A")
	_wd.set_world_time(13.5)
	var rec := lc.end_life(&"starved", {"damage_reason": "hunger",
		"snapshot": {"health": 0.0, "hunger": 0.0, "thirst": 4.0, "stamina": 2.0}})
	_assert_near("E1_duration", 3.5, float(rec.get("duration", -1.0)), EPS)
	_assert_near("E2_start_world_time", 10.0, float(rec.get("start_world_time", -1.0)), EPS)
	_assert_near("E3_end_world_time", 13.5, float(rec.get("end_world_time", -1.0)), EPS)
	_assert("E4_species", String(_mice), String(rec.get("species_id", "")),
		String(rec.get("species_id", "")) == String(_mice))
	_assert("E5_captures", "1", str(int(rec.get("captures", 0))), int(rec.get("captures", 0)) == 1)
	_assert("E6_escapes", "2", str(int(rec.get("escapes", 0))), int(rec.get("escapes", 0)) == 2)
	_assert_near("E7_food_gained", 3.5, float(rec.get("food_gained", 0.0)), EPS)
	_assert_near("E8_water_gained", 1.25, float(rec.get("water_gained", 0.0)), EPS)
	var disc: Array = rec.get("discoveries", [])
	_assert("E9_discoveries", "1", str(disc.size()), disc.size() == 1 and String(disc[0]) == "地点A")
	var pos := rec.get("start_position", Vector3.ZERO) as Vector3
	_assert("E10_start_position", "(1, 2, 3)", str(pos),
		pos.is_equal_approx(Vector3(1.0, 2.0, 3.0)))
	var snap: Dictionary = rec.get("snapshot", {})
	_assert("E11_snapshot_keys", "health,hunger,thirst,stamina",
		str(snap.keys()), snap.size() == 4 and snap.has("health") and snap.has("hunger")
			and snap.has("thirst") and snap.has("stamina"))
	_assert("E12_archive_line_nonempty", "true", str(String(_gs.call("archive_line", rec)) != ""),
		String(_gs.call("archive_line", rec)) != "")
	_assert("E13_life_id_in_record", life, String(rec.get("life_id", "")),
		String(rec.get("life_id", "")) == life)
	lc.free()


# ---------------------------------------------------------------------------
# F 事件
# ---------------------------------------------------------------------------

func _section_f_events() -> void:
	print("---- F 事件 ----")
	_gs.call("reset_for_new_game")
	_gs.set("test_mode", true)
	var lc := _new_cycle()
	lc.request_select()
	lc.begin_spawn(_mice)
	var life1 := lc.mark_spawned(null)
	lc.notify_event(&"capture", {"target": "npc_1"})
	lc.end_life(&"died")
	var ev1: Array = _gs.call("events_for", life1)
	_assert("F1_events_for_life", "3", str(ev1.size()), ev1.size() == 3)
	if ev1.size() == 3:
		_assert("F2_life_start_first", "life_start", String((ev1[0] as Dictionary).get("kind", "")),
			String((ev1[0] as Dictionary).get("kind", "")) == "life_start")
		_assert("F3_life_end_last", "life_end",
			String((ev1[ev1.size() - 1] as Dictionary).get("kind", "")),
			String((ev1[ev1.size() - 1] as Dictionary).get("kind", "")) == "life_end")
	var all_events := _gs.get("events") as Array
	var mono := true
	for i in range(1, all_events.size()):
		var prev := int((all_events[i - 1] as Dictionary).get("seq", 0))
		var cur := int((all_events[i] as Dictionary).get("seq", 0))
		if cur <= prev:
			mono = false
	_assert("F4_seq_monotonic", "true", str(mono), mono)

	# 跨世：第二世不清理第一世事件
	lc.request_select()
	lc.begin_spawn(_mice)
	var life2 := lc.mark_spawned(null)
	lc.end_life(&"died")
	_assert("F5_life_ids_distinct", "不同", "%s vs %s" % [life1, life2], life1 != life2)
	var ev1_after: Array = _gs.call("events_for", life1)
	_assert("F6_first_life_events_kept", "3", str(ev1_after.size()), ev1_after.size() == 3)
	var ev2: Array = _gs.call("events_for", life2)
	_assert("F7_second_life_events", "2", str(ev2.size()), ev2.size() == 2)

	# 封顶
	_gs.call("reset_for_new_game")
	for i in MAX_EVENTS_EXPECTED + 20:
		_gs.call("record_event", "L9999", &"spam", {"i": i})
	var count := int(_gs.call("event_count"))
	_assert("F8_events_capped", str(MAX_EVENTS_EXPECTED), str(count), count == MAX_EVENTS_EXPECTED)
	var last_seq := int(_gs.call("last_event_seq"))
	_assert("F9_last_seq_keeps_growing", str(MAX_EVENTS_EXPECTED + 20), str(last_seq),
		last_seq == MAX_EVENTS_EXPECTED + 20)
	lc.free()


# ---------------------------------------------------------------------------
# G 长期数据跨世保留
# ---------------------------------------------------------------------------

func _section_g_long_term() -> void:
	print("---- G 长期数据跨世保留 ----")
	_gs.call("reset_for_new_game")
	_gs.set("test_mode", false)
	_gs.call("set_default_unlock", [_mice])
	_wd.set_world_time(5.0)
	var lc := _new_cycle()
	lc.request_select()
	lc.begin_spawn(_mice)
	var life1 := lc.mark_spawned(null)
	lc.end_life(&"died")
	_gs.call("unlock_species", _cats)
	_wd.set_world_time(20.0)
	lc.request_select()
	lc.begin_spawn(_cats)
	var life2 := lc.mark_spawned(null)
	_assert("G1_new_life_keeps_world_time", "20.0", "%.1f" % float(_wd.get("world_time")),
		absf(float(_wd.get("world_time")) - 20.0) <= EPS)
	_assert("G2_archive_kept", "1", str(int(_gs.call("archive_count"))),
		int(_gs.call("archive_count")) == 1)
	_assert("G3_unlock_kept", "true", str(bool(_gs.call("is_species_unlocked", _cats))),
		bool(_gs.call("is_species_unlocked", _cats)))
	_assert("G4_life_counter_monotonic", "L0002", life2, life2 == "L0002")
	var first_record: Dictionary = (_gs.get("life_records") as Array)[0]
	_assert("G5_life1_record_kept", life1, String(first_record.get("life_id", "")),
		String(first_record.get("life_id", "")) == life1)
	lc.end_life(&"g_end")
	lc.free()


# ---------------------------------------------------------------------------
# H 正式入口闭环
# ---------------------------------------------------------------------------

func _section_h_entry() -> void:
	print("---- H 正式入口 ----")
	_gs.call("reset_for_new_game")
	_wd.set_world_time(0.0)
	var main := (load(MAIN) as PackedScene).instantiate() as Node3D
	root.add_child(main)
	await _advance_frames(4)
	if not (main is MainEntry):
		_assert("H1_entry_class", "MainEntry", main.get_class(), false)
		main.queue_free()
		await _advance_frames(2)
		return
	var entry := main as MainEntry
	_assert("H1_entry_class", "MainEntry", "MainEntry", true)
	_assert("H2_initial_selecting", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")
	_assert("H3_no_life_yet", "", entry.current_life_id(), entry.current_life_id() == "")
	_assert("H4_time_frozen_in_select", "false", str(entry.lifecycle.time_is_advancing()),
		not entry.lifecycle.time_is_advancing())
	var slots := entry.selectable_slots()
	_assert("H5_slots_has_species", ">=2", str(slots.size()), slots.size() >= 2)
	_assert("H6_status_has_slot_keys", "含 1=", entry.status_text(),
		entry.status_text().contains("1="))
	var forbidden := false
	for w in STATUS_FORBIDDEN:
		if entry.status_text().contains(String(w)):
			forbidden = true
	_assert("H7_status_no_debug_words", "false", entry.status_text(), not forbidden)
	_assert("H8_no_canvas_layer_runtime", "0", str(_count_class(main, "CanvasLayer")),
		_count_class(main, "CanvasLayer") == 0)
	_assert("H9_no_debug_script_runtime", "0", str(_count_debug(main)), _count_debug(main) == 0)

	# 出生 → 存活
	var accepted := entry.select_species(_mice)
	await _advance_frames(4)
	var life1 := entry.current_life_id()
	_assert("H10_spawn_alive", "alive", entry.lifecycle_state_name(),
		accepted and entry.lifecycle_state_name() == "alive")
	_assert("H11_life_id", "L0001", life1, life1 == "L0001")
	_assert("H12_player_exists", "true", str(entry.player != null and is_instance_valid(entry.player)),
		entry.player != null and is_instance_valid(entry.player))
	_assert("H13_time_resumed", "true", str(entry.lifecycle.time_is_advancing()),
		entry.lifecycle.time_is_advancing())
	var npc_before := entry.npc_count()
	if not (entry.player != null and is_instance_valid(entry.player)):
		main.queue_free()
		await _advance_frames(2)
		return
	var body := entry.player
	_assert("H14_player_controlled", "true", str(body.player_controlled), body.player_controlled)
	_assert("H15_hud_bound", "true", str(entry.hud != null and entry.hud.is_bound()),
		entry.hud != null and entry.hud.is_bound())

	# 用显式世界时间推进（headless 帧间隔极小，不能靠帧数攒出可测时长）
	var start_time := float((_gs.get("current_life") as Dictionary).get("start_world_time", 0.0))
	_wd.set_world_time(start_time + 2.0)
	# 死亡：连打三次也只结算一次
	body.survival.apply_damage(9999.0, &"test_kill")
	body.survival.apply_damage(9999.0, &"test_kill")
	body.survival.apply_damage(9999.0, &"test_kill")
	await _advance_frames(6)
	_assert("H16_archive_after_death", "1", str(entry.archive_count()), entry.archive_count() == 1)
	var rec := entry.last_record()
	_assert("H17_end_reason", "died", String(rec.get("end_reason", "")),
		String(rec.get("end_reason", "")) == "died")
	_assert("H18_damage_reason", "test_kill", String(rec.get("damage_reason", "")),
		String(rec.get("damage_reason", "")) == "test_kill")
	_assert("H19_back_to_selecting", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")
	_assert("H20_player_released", "true", str(entry.player == null), entry.player == null)
	_assert("H21_time_frozen_after_death", "false", str(entry.lifecycle.time_is_advancing()),
		not entry.lifecycle.time_is_advancing())
	_assert("H22_npc_count_unchanged", str(npc_before), str(entry.npc_count()),
		entry.npc_count() == npc_before)
	_assert("H23_no_player_node", "0", str(_count_named(main, "Player")),
		_count_named(main, "Player") == 0)
	_assert("H24_status_shows_archive", "含 上一世", entry.status_text(),
		entry.status_text().contains("上一世"))
	_assert_near("H25_duration_matches_world_time", 2.0, float(rec.get("duration", -1.0)), 1e-3)

	# 选第二个物种：新 LifeId、世界时间不归零、档案保留
	var world_before := entry.world_time_now()
	var accepted2 := entry.select_species(_cats)
	await _advance_frames(4)
	var life2 := entry.current_life_id()
	_assert("H26_respawn_alive", "alive", entry.lifecycle_state_name(),
		accepted2 and entry.lifecycle_state_name() == "alive")
	_assert("H27_new_life_id", "L0002", life2, life2 == "L0002")
	_assert("H28_life_ids_distinct", "不同", "%s vs %s" % [life1, life2], life1 != life2)
	_assert("H29_world_time_kept", ">= %.3f" % world_before, "%.3f" % entry.world_time_now(),
		entry.world_time_now() + EPS >= world_before)
	_assert("H30_archive_kept", "1", str(entry.archive_count()), entry.archive_count() == 1)

	main.queue_free()
	await _advance_frames(4)
	_assert("H31_time_restored_on_exit", "true", str(bool(_wd.get("time_advancing"))),
		bool(_wd.get("time_advancing")))


# ---------------------------------------------------------------------------
# 夹具与工具
# ---------------------------------------------------------------------------

func _new_cycle() -> LifeCycle:
	var lc := LifeCycle.new()
	lc.name = "T030LifeCycle"
	lc.known_species = [_cats, _mice]
	root.add_child(lc)
	return lc


func _first_keycode(action: String) -> int:
	for e in InputMap.action_get_events(action):
		var k := e as InputEventKey
		if k != null:
			return int(k.physical_keycode)
	return -1


func _const_of(path: String, name: String) -> int:
	var s := load(path) as Script
	if s == null:
		return -2
	var map := s.get_script_constant_map()
	if not map.has(name):
		return -3
	return int(map[name])


func _all_nodes(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all_nodes(c))
	return out


func _count_class(node: Node, cls: String) -> int:
	var n := 0
	for x in _all_nodes(node):
		if x.get_class() == cls:
			n += 1
	return n


func _count_debug(node: Node) -> int:
	var n := 0
	for x in _all_nodes(node):
		if x.get_script() != null:
			var sp := String((x.get_script() as Script).resource_path)
			if sp.contains("/debug/"):
				n += 1
	return n


func _count_named(node: Node, prefix: String) -> int:
	var n := 0
	for x in _all_nodes(node):
		if String(x.name).begins_with(prefix):
			n += 1
	return n


func _advance_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	_assert(id, "%.4f±%.4f" % [expected, eps], "%.4f" % actual, absf(expected - actual) <= eps)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
