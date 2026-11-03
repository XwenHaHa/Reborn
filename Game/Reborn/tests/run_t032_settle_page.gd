extends SceneTree
## T032 生命档案与结算页（`Docs/Tasks/T032.md` §6）
##
## 验证：结算覆盖层契约（纯 Control、加在菜单之后、无 CanvasLayer）、
## 呈现内容 = `GameState` 结算档案照实（策划 §9.4 字段，无平行数据）、
## 确认消隐（Esc / Enter / 点击）、重复伤害只呈现一次（§9.3）、
## 出生自动隐藏 + 面板可见时消费按键（保护背后菜单）。
##
## 输入注入与 `run_art05_input.gd` 同一模式（引擎内注入，不出进程）：
## - 键盘：`Input.parse_input_event()`（keycode + physical 双通道，内置动作用 keycode）
## - 鼠标：`root.push_input()`（真实 GUI 命中）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t032_settle_page.gd' --quit-after 300000

const PANEL := "res://scripts/ui/life_settle_panel.gd"
const MAIN_ENTRY := "res://scripts/core/main_entry.gd"
const MAIN := "res://scenes/core/main.tscn"
const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"

const EPS := 1e-3

var _checks := 0
var _fails := 0
var _gs: Node = null
var _wd: Node = null
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null


func _initialize() -> void:
	print("TEST|run_t032_settle_page|engine=%s" % Engine.get_version_info().string)
	_gs = root.get_node_or_null("GameState")
	_wd = root.get_node_or_null("WorldDirector")
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig
	await _section_a_contract()
	await _section_b_settle_page()
	_finish()


# ---------------------------------------------------------------------------
# A 契约
# ---------------------------------------------------------------------------

func _section_a_contract() -> void:
	print("---- A 契约 ----")
	var script := load(PANEL) as Script
	_assert("A1_panel_script_loads", "非 null", str(script != null), script != null)
	if script == null:
		return
	var probe: Object = script.new()
	_assert("A2_panel_is_control", "Control",
		"Control" if probe is Control else probe.get_class(), probe is Control)
	var api := ["present", "dismiss", "present_count", "is_presenting",
		"summary_text", "record", "event_kinds"]
	var missing: Array[String] = []
	for m in api:
		if not probe.has_method(m):
			missing.append(m)
	_assert("A3_panel_api", "无缺失", str(missing), missing.is_empty())
	var entry_probe := load(MAIN_ENTRY).new() as Object
	_assert("A4_entry_has_dismiss_settle", "true",
		str(entry_probe.has_method("dismiss_settle")), entry_probe.has_method("dismiss_settle"))
	probe.free()
	entry_probe.free()

	var packed := load(MAIN) as PackedScene
	_assert("A5_main_loads", "非 null", str(packed != null), packed != null)
	if packed == null:
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _advance_frames(6)
	var entry := main as MainEntry
	if _assert("A6_entry_class", "MainEntry", main.get_class(), entry != null):
		_assert("A7_settle_panel_built", "非 null",
			str(entry.settle_panel != null), entry.settle_panel != null)
		_assert("A8_panel_is_control", "Control",
			entry.settle_panel.get_class() if entry.settle_panel != null else "<null>",
			entry.settle_panel is Control)
		_assert("A9_panel_after_menu", "index > menu",
			"%d vs %d" % [entry.settle_panel.get_index() if entry.settle_panel != null else -1,
				entry.menu.get_index() if entry.menu != null else -1],
			entry.settle_panel != null and entry.menu != null
				and entry.settle_panel.get_index() > entry.menu.get_index())
		_assert("A10_panel_hidden_at_boot", "false",
			str(entry.settle_panel.visible if entry.settle_panel != null else "null"),
			entry.settle_panel != null and not entry.settle_panel.visible)
	_assert("A11_no_canvas_layer", "0", str(_count_class(main, "CanvasLayer")),
		_count_class(main, "CanvasLayer") == 0)
	main.queue_free()
	await _advance_frames(4)


# ---------------------------------------------------------------------------
# B–E 结算页行为（一个 MainEntry 实例上走完一世→死亡→消隐→再世）
# ---------------------------------------------------------------------------

func _section_b_settle_page() -> void:
	print("---- B 呈现内容 ----")
	if _gs == null or _wd == null:
		_assert("B0_environment", "GameState/WorldDirector", "<缺失>", false)
		return
	_gs.call("reset_for_new_game")
	_wd.set("world_time", 0.0)
	var packed := load(MAIN) as PackedScene
	if packed == null:
		_assert("B0_main_loads", "非 null", "null", false)
		return
	var main := packed.instantiate()
	var entry := main as MainEntry
	if entry == null:
		_assert("B0_entry_class", "MainEntry", "<null>", false)
		return
	# 本套件不测解锁门（T031 固化），测结算页 → 显式开测试模式（与 t030 H / art05 同口径）
	entry.test_mode = true
	root.size = Vector2i(1280, 720)   # 与 art05 同法：headless 根视口只有 64×64
	root.add_child(main)
	await _advance_frames(8)
	_assert("B1_panel_hidden_before_death", "false", str(entry.settle_panel.visible),
		not entry.settle_panel.visible)

	var configs := entry.species_configs()
	if configs.size() < 2:
		_assert("B0_need_two_species", ">=2", str(configs.size()), false)
		main.queue_free()
		await _advance_frames(4)
		return
	var first: StringName = configs[0].species_id
	var second: StringName = configs[1].species_id
	var first_title := configs[0].display_title()

	# ---- 第一世：富化档案（捕猎/逃脱/食物/水/发现），推进世界时间后连打三次致死 ----
	var ok1 := entry.select_species(first)
	await _advance_frames(6)
	_assert("B2_first_life_alive", "alive", entry.lifecycle_state_name(),
		ok1 and entry.lifecycle_state_name() == "alive")
	if entry.player == null or not is_instance_valid(entry.player):
		_assert("B0_player_exists", "true", "false", false)
		main.queue_free()
		await _advance_frames(4)
		return
	_gs.call("add_to_life", "captures", 1)
	_gs.call("add_to_life", "escapes", 1)
	_gs.call("add_to_life", "food_gained", 0.5)
	_gs.call("add_to_life", "water_gained", 0.25)
	_gs.call("record_discovery", &"t032_test_place")
	var cur := _gs.get("current_life") as Dictionary
	var start_time := float(cur.get("start_world_time", 0.0))
	_wd.call("set_world_time", start_time + 2.0)
	var body := entry.player
	body.survival.apply_damage(9999.0, &"t032_kill")
	body.survival.apply_damage(9999.0, &"t032_kill")
	body.survival.apply_damage(9999.0, &"t032_kill")
	await _advance_frames(8)

	var panel := entry.settle_panel
	var rec := entry.last_record()
	var life1 := String(rec.get("life_id", ""))
	var summary := panel.summary_text()

	_assert("B3_panel_presented", "true", str(panel.visible), panel.visible)
	_assert("B4_present_count_once", "1", str(panel.present_count()),
		panel.present_count() == 1)                                     # D4 重复伤害只一次
	_assert("B5_archive_once", "1", str(entry.archive_count()),
		entry.archive_count() == 1)                                     # §9.3 只一份档案
	_assert("B6_summary_has_life_id", life1, summary, summary.contains(life1))
	_assert("B7_summary_has_species", first_title, summary, summary.contains(first_title))
	_assert("B8_summary_has_duration", "2.0", summary,
		summary.contains("2.0") and absf(float(rec.get("duration", -1.0)) - 2.0) < EPS)
	_assert("B9_summary_has_end_reason", "死亡", summary, summary.contains("死亡"))
	_assert("B10_summary_has_damage_reason", "t032_kill", summary, summary.contains("t032_kill"))
	_assert("B11_summary_has_captures", "捕猎 1", summary, summary.contains("捕猎 1"))
	_assert("B12_summary_has_escapes", "逃脱 1", summary, summary.contains("逃脱 1"))
	_assert("B13_summary_has_food_water", "+0.50 / +0.25", summary,
		summary.contains("+0.50") and summary.contains("+0.25"))
	_assert("B14_summary_has_discovery", "t032_test_place", summary,
		summary.contains("t032_test_place"))
	_assert("B15_summary_has_vitals", "生命/饥饿/水分/体力", summary,
		summary.contains("生命") and summary.contains("饥饿")
			and summary.contains("水分") and summary.contains("体力"))
	_assert("B16_panel_record_matches_archive", "== last_record",
		str(panel.record() == rec), panel.record() == rec)             # D2 无平行副本
	var expected_kinds := _kinds_of(_gs.call("events_for", life1))
	_assert("B17_event_kinds_match_events", str(expected_kinds), str(panel.event_kinds()),
		panel.event_kinds() == expected_kinds)                          # D2 context 照实
	_assert("B18_state_selecting", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")                   # D1 时序不变
	_assert("B19_menu_visible_behind", "true", str(entry.menu.visible), entry.menu.visible)
	_assert("B20_time_frozen", "false", str(entry.lifecycle.time_is_advancing()),
		not entry.lifecycle.time_is_advancing())

	# ---- C 确认消隐：Esc 关闭 → 菜单露出；第二世死亡换内容；Enter 也可关闭 ----
	print("---- C 确认消隐 ----")
	await _tap_key(KEY_ESCAPE)
	await _advance_frames(4)
	_assert("C1_esc_dismissed", "false", str(panel.visible), not panel.visible)
	_assert("C2_menu_visible_after_dismiss", "true", str(entry.menu.visible), entry.menu.visible)
	_assert("C3_state_still_selecting", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")
	_assert("C4_time_still_frozen", "false", str(entry.lifecycle.time_is_advancing()),
		not entry.lifecycle.time_is_advancing())

	var ok2 := entry.select_species(second)
	await _advance_frames(6)
	_assert("C5_second_life_alive", "alive", entry.lifecycle_state_name(),
		ok2 and entry.lifecycle_state_name() == "alive")
	_assert("C6_panel_hidden_on_spawn", "false", str(panel.visible), not panel.visible)  # D7 出生自动隐藏
	if entry.player != null and is_instance_valid(entry.player):
		entry.player.survival.apply_damage(9999.0, &"t032_kill_2")
	await _advance_frames(8)
	var rec2 := entry.last_record()
	var life2 := String(rec2.get("life_id", ""))
	_assert("C7_panel_presented_again", "true", str(panel.visible), panel.visible)
	_assert("C8_present_count_two", "2", str(panel.present_count()), panel.present_count() == 2)
	_assert("C9_summary_switches_life", life2, panel.summary_text(),
		panel.summary_text().contains(life2))
	# 点击消隐在 headless 测不了（无头根视口没有鼠标进入事件，GUI 命中不触发——
	# 与 `run_art05_input.gd` 同一能力门）：由 art05（非 headless）用真实点击覆盖，
	# 本套件只走键盘路径（Esc / Enter）与 API 路径。
	_assert("C10_state_selecting_before_third_life", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")

	# 第三世：用 Enter 验证 ui_accept 消隐路径（若穿到菜单会直接出生 → 状态变 alive）
	var ok3 := entry.select_species(first)
	await _advance_frames(6)
	_assert("C12_third_life_alive", "alive", entry.lifecycle_state_name(),
		ok3 and entry.lifecycle_state_name() == "alive")
	if entry.player != null and is_instance_valid(entry.player):
		entry.player.survival.apply_damage(9999.0, &"t032_kill_3")
	await _advance_frames(8)
	_assert("C13_panel_presented_third", "true", str(panel.visible), panel.visible)
	await _tap_key(KEY_ENTER)
	await _advance_frames(4)
	_assert("C14_enter_dismissed", "false", str(panel.visible), not panel.visible)
	_assert("C15_enter_not_leaked_to_menu", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")

	# ---- E 输入保护：面板可见时数字键不穿到菜单/入口 ----
	print("---- E 输入保护 ----")
	var ok4 := entry.select_species(first)
	await _advance_frames(6)
	_assert("E0_fourth_life_alive", "alive", entry.lifecycle_state_name(),
		ok4 and entry.lifecycle_state_name() == "alive")
	if entry.player != null and is_instance_valid(entry.player):
		entry.player.survival.apply_damage(9999.0, &"t032_kill_4")
	await _advance_frames(8)
	_assert("E1_panel_presented", "true", str(panel.visible), panel.visible)
	await _tap_key(KEY_1)
	await _advance_frames(6)
	_assert("E2_key_consumed_still_presenting", "true", str(panel.visible), panel.visible)
	_assert("E3_key_consumed_no_spawn", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")
	await _tap_key(KEY_ESCAPE)
	await _advance_frames(4)
	_assert("E4_esc_dismissed", "false", str(panel.visible), not panel.visible)
	# 现有菜单契约（art05 K2 固化）：数字键只**选中**物种，不直接出生——
	# 键盘穿到菜单的证明 = 选中项变化；出生走 Enter（菜单 commit 路径）
	await _tap_key(KEY_1)
	await _advance_frames(4)
	_assert("E5_key_reaches_menu", String(first), String(entry.menu.selected_species()),
		entry.menu.selected_species() == first)
	await _tap_key(KEY_ENTER)
	await _advance_frames(6)
	_assert("E6_enter_spawns_after_dismiss", "alive", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "alive")
	_assert("E7_panel_hidden_after_spawn", "false", str(panel.visible), not panel.visible)

	main.queue_free()
	await _advance_frames(4)
	_assert("E8_time_restored_on_exit", "true", str(bool(_wd.get("time_advancing"))),
		bool(_wd.get("time_advancing")))


# ---------------------------------------------------------------------------
# 注入与工具
# ---------------------------------------------------------------------------

## 敲一下键（按下 + 松开），走 `Input.parse_input_event` → InputMap → `_unhandled_key_input`。
## keycode 与 physical_keycode 双通道（与 `run_art05_input.gd` 同模式）。
func _tap_key(keycode: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
		await process_frame


func _kinds_of(events: Variant) -> Dictionary:
	var out := {}
	for e in events:
		var k := String((e as Dictionary).get("kind", ""))
		out[k] = int(out.get(k, 0)) + 1
	return out


func _advance_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _count_class(node: Node, cls: String) -> int:
	var n := 0
	for x in _all_nodes(node):
		if x.get_class() == cls:
			n += 1
	return n


func _all_nodes(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all_nodes(c))
	return out


func _assert(id: String, expected: String, actual: String, ok: bool) -> bool:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])
	return ok


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
