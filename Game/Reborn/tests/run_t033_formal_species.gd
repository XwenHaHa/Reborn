extends SceneTree

const GameClock := preload("res://scripts/core/game_clock.gd")
## T033 正式物种选择与重生（`Docs/Tasks/T033.md` §6）
##
## 验证：
## - A 契约：`MainMenu` 解锁集 API / `PlayerHud` Toast API；层序 menu < LifeStatus < settle（D1）；
##   MvpNote 与状态文字矩形不相交（ART09 遮挡遗留修复）；
## - B 正式锁定呈现：锁定卡可见、压暗、「尚未解锁」；点击/数字键只反馈不选中；入口门不放宽；
## - C 解锁链与刷新：真实发现路径（出生初始物种 → 洞口半径内）→ Toast + 菜单即时刷新；
## - D z 序与遮挡复检（一世轮回后）；
## - E Toast 契约（独立 HUD 实例）；
## - F 重生整备：两世后 Player 唯一、无 retired 残留（开发计划 T033 原文）+ T031 约束复证。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t033_formal_species.gd' --quit-after 300000

const MAIN := "res://scenes/core/main.tscn"
const MENU_SCRIPT := "res://scripts/ui/main_menu.gd"
const HUD_SCRIPT := "res://scripts/ui/hud.gd"
const HUD_SCENE := "res://scenes/ui/hud.tscn"
const ROOT_HOLE_ID := "root_hole_courtyard_01"
const PROBE_PLACE := "t033_probe_place"
## 洞南 1.5 m（与 run_t031_discovery E 段 / tool_capture_render t031 同点）
const HOLE_APPROACH := Vector3(26.5, 0.34, 17.5)

var _checks := 0
var _fails := 0
var _gs: Node = null
var _wd: Node = null


func _initialize() -> void:
	print("TEST|run_t033_formal_species|engine=%s" % Engine.get_version_info().string)
	_run()


func _run() -> void:
	_gs = root.get_node_or_null("GameState")
	_wd = root.get_node_or_null("WorldDirector")
	if _gs == null or _wd == null:
		print("ASSERT|A0_environment|FAIL|GameState/WorldDirector 缺失")
		print("SUMMARY|checks=1|failures=1")
		print("RESULT|FAIL")
		quit(1)
		return
	_gs.call("reset_for_new_game")
	_wd.set("world_time", 0.0)
	root.size = Vector2i(1280, 720)   # headless 根视口只有 64×64（与 art05/t032 同法）

	var packed := load(MAIN) as PackedScene
	if packed == null:
		print("ASSERT|A0_main_loads|FAIL|main.tscn 缺失")
		print("SUMMARY|checks=1|failures=1")
		print("RESULT|FAIL")
		quit(1)
		return
	var main := packed.instantiate()
	# 正式模式（默认 test_mode=false）：锁定门就是本套件的取证对象
	root.add_child(main)
	await _advance_frames(8)
	root.size = Vector2i(1280, 720)
	await _advance_frames(4)
	var entry := main as MainEntry
	if entry == null:
		_finish()
		return

	await _section_a_contract(entry)
	await _section_b_lock(entry)
	await _section_c_unlock_chain(entry)
	await _section_d_zorder_recheck(entry)
	await _section_e_toast(entry)
	await _section_f_rebirth(entry)

	main.queue_free()
	await _advance_frames(4)
	_finish()


# ---------------------------------------------------------------------------
# A 契约
# ---------------------------------------------------------------------------

func _section_a_contract(entry: MainEntry) -> void:
	print("---- A 契约 ----")
	# --- API 探针（不入树，只查方法面） ---
	var menu_probe: Object = (load(MENU_SCRIPT) as Script).new()
	var menu_api := ["set_unlocked", "is_locked", "locked_list", "last_lock_feedback"]
	var missing_menu: Array[String] = []
	for m in menu_api:
		if not menu_probe.has_method(m):
			missing_menu.append(m)
	_assert("A1_menu_api", "无缺失", str(missing_menu), missing_menu.is_empty())
	menu_probe.free()

	var hud_probe: Object = (load(HUD_SCRIPT) as Script).new()
	var hud_api := ["show_toast", "toast_text", "toast_visible"]
	var missing_hud: Array[String] = []
	for m in hud_api:
		if not hud_probe.has_method(m):
			missing_hud.append(m)
	_assert("A2_hud_api", "无缺失", str(missing_hud), missing_hud.is_empty())
	hud_probe.free()

	# --- build 默认语义（不传解锁集 = 全可玩；显式 set_unlocked 空数组 = 全锁） ---
	var configs := entry.species_configs()
	if configs.size() < 2:
		_assert("A0_need_two_species", ">=2", str(configs.size()), false)
		return
	var menu2 := MainMenu.new()
	menu2.name = "T033MenuProbe"
	root.add_child(menu2)
	await _advance_frames(2)
	menu2.build(configs, {})
	_assert("A3_build_default_all_unlocked", "0", str(menu2.locked_list().size()),
		menu2.locked_list().is_empty())
	menu2.set_unlocked([])
	var all_ids: Array[StringName] = []
	var first_id: StringName = configs[0].species_id
	var second_id: StringName = configs[1].species_id
	for cfg in configs:
		all_ids.append(cfg.species_id)
	_assert("A4_set_unlocked_empty_locks_all", str(all_ids), str(menu2.locked_list()),
		menu2.locked_list().size() == all_ids.size())
	menu2.set_unlocked([first_id])
	_assert("A5_set_unlocked_partial", str([second_id]), str(menu2.locked_list()),
		menu2.locked_list().size() == 1 and menu2.locked_list()[0] == second_id)
	menu2.queue_free()
	await _advance_frames(2)

	# --- 正式入口层序（D1）：menu < LifeStatus < settle ---
	_assert("A6_formal_test_mode_off", "false", str(entry.test_mode), not entry.test_mode)
	var status_layer := entry.get_node_or_null("LifeStatus")
	_assert("A7_status_layer_exists", "非 null", str(status_layer != null), status_layer != null)
	if status_layer != null and entry.menu != null and entry.settle_panel != null:
		var order := "%d<%d<%d" % [entry.menu.get_index(), status_layer.get_index(),
			entry.settle_panel.get_index()]
		var ok_order := entry.menu.get_index() < status_layer.get_index() \
			and status_layer.get_index() < entry.settle_panel.get_index()
		_assert("A8_layer_order_menu_status_settle", "menu<status<settle", order, ok_order)
	_assert("A9_no_canvas_layer", "0", str(_count_class(entry, "CanvasLayer")),
		_count_class(entry, "CanvasLayer") == 0)
	_assert("A10_status_select_text", "含选择物种", entry.status_text(),
		entry.status_text().contains("选择物种"))

	# --- ART09 遮挡遗留（D1/D2）：MvpNote 与状态文字矩形不相交 ---
	if not await _check_no_occlusion(entry, "A11"):
		pass


func _check_no_occlusion(entry: MainEntry, label: String) -> bool:
	if entry.menu == null or entry.status_label == null:
		_assert("%s_nodes" % label, "menu+status", "<缺失>", false)
		return false
	var mvp := _find(entry.menu, "MvpNote") as Control
	if mvp == null:
		_assert("%s_mvp_exists" % label, "非 null", "<null>", false)
		return false
	entry.status_label.visible = true   # 菜单打开时游戏隐藏状态文字；取证侧强制可见（同 t031 口径）
	await _advance_frames(2)
	var sr := entry.status_label.get_global_rect()
	var mr := mvp.get_global_rect()
	var inter := sr.intersects(mr)
	print("OCCL|status=%.0f,%.0f %.0fx%.0f|mvp=%.0f,%.0f %.0fx%.0f|intersects=%s" % [
		sr.position.x, sr.position.y, sr.size.x, sr.size.y,
		mr.position.x, mr.position.y, mr.size.x, mr.size.y, str(inter)])
	_assert("%s_no_intersect" % label, "false", str(inter), not inter)
	return not inter


# ---------------------------------------------------------------------------
# B 正式锁定呈现
# ---------------------------------------------------------------------------

func _section_b_lock(entry: MainEntry) -> void:
	print("---- B 正式锁定呈现 ----")
	var configs := entry.species_configs()
	var first_id: StringName = configs[0].species_id
	var second_id: StringName = configs[1].species_id
	var second_title := configs[1].display_title()
	# 数据推导：正式初始解锁 = initially_unlocked 的物种（不写物种名）
	var expected_locked: Array[StringName] = []
	for cfg in configs:
		if not cfg.initially_unlocked:
			expected_locked.append(cfg.species_id)
	expected_locked.sort()
	_assert("B1_locked_list_matches_configs", str(expected_locked),
		str(entry.menu.locked_list()), entry.menu.locked_list() == expected_locked)

	# 锁定卡同构：Card_<id> / Tagline=尚未解锁 / Note 非空 / 整卡压暗
	var locked_card := _find(entry.menu, "Card_%s" % String(second_id)) as Control
	_assert("B2_locked_card_exists", "非 null", str(locked_card != null), locked_card != null)
	if locked_card != null:
		var tagline := _find(locked_card, "Tagline") as Label
		_assert("B3_locked_tagline", "尚未解锁",
			tagline.text if tagline != null else "<null>",
			tagline != null and tagline.text == "尚未解锁")
		var note := _find(locked_card, "Note") as Label
		_assert("B4_locked_note_hint", "非空", note.text if note != null else "<null>",
			note != null and not note.text.is_empty())
		var open_card := _find(entry.menu, "Card_%s" % String(first_id)) as Control
		_assert("B5_locked_dimmed", "锁定卡暗于可玩卡",
			"%.2f vs %.2f" % [locked_card.modulate.r, open_card.modulate.r if open_card != null else -1.0],
			open_card != null and locked_card.modulate.r < open_card.modulate.r)

	# 默认选中 = 第一个已解锁物种（数据驱动）
	_assert("B6_default_selection_unlocked", str(first_id),
		str(entry.menu.selected_species()), entry.menu.selected_species() == first_id)

	# 菜单选择门：锁定 → false + 反馈，选中不变
	var ok_sel := entry.menu.select_species(second_id)
	_assert("B7_locked_select_refused", "false", str(ok_sel), not ok_sel)
	_assert("B8_selection_unchanged", str(first_id), str(entry.menu.selected_species()),
		entry.menu.selected_species() == first_id)
	var feedback := entry.menu.last_lock_feedback()
	_assert("B9_feedback_names_species_and_state", "含显示名+尚未解锁", feedback,
		feedback.contains(second_title) and feedback.contains("尚未解锁"))

	# 数字键 2（第二物种=锁定）：只反馈，不选中、不出生
	await _press_key(KEY_2)
	_assert("B10_number_key_locked_feedback", "含尚未解锁", entry.menu.last_lock_feedback(),
		entry.menu.last_lock_feedback().contains("尚未解锁"))
	_assert("B11_number_key_keeps_selection", str(first_id),
		str(entry.menu.selected_species()), entry.menu.selected_species() == first_id)
	_assert("B12_number_key_no_spawn", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")

	# 入口门不放宽：直接调 entry.select_species（锁定）仍被 lifecycle 拒绝
	var ok_entry := entry.select_species(second_id)
	await _advance_frames(2)
	_assert("B13_entry_locked_refused", "false", str(ok_entry), not ok_entry)
	_assert("B14_entry_reject_reason", "locked_species",
		String(entry.lifecycle.last_rejection().get("reason", "")),
		String(entry.lifecycle.last_rejection().get("reason", "")) == "locked_species")


# ---------------------------------------------------------------------------
# C 解锁链与刷新（真实发现路径）
# ---------------------------------------------------------------------------

func _section_c_unlock_chain(entry: MainEntry) -> void:
	print("---- C 解锁链与刷新 ----")
	var configs := entry.species_configs()
	var first_id: StringName = configs[0].species_id
	var second_id: StringName = configs[1].species_id
	var second_title := configs[1].display_title()

	var ok := entry.select_species(first_id)
	await _advance_frames(6)
	_assert("C1_first_life_alive", "alive", entry.lifecycle_state_name(),
		ok and entry.lifecycle_state_name() == "alive")
	if entry.player == null or not is_instance_valid(entry.player):
		_assert("C1_player_exists", "true", "false", false)
		return

	# 挪到鼠洞发现半径内 → 扫描触发（与 run_t031 E 段同一机制）
	entry.player.global_position = HOLE_APPROACH
	for i in 40:
		await physics_frame
		if bool(_gs.call("is_place_discovered", ROOT_HOLE_ID)):
			break
	_assert("C2_place_discovered", "true",
		str(bool(_gs.call("is_place_discovered", ROOT_HOLE_ID))),
		bool(_gs.call("is_place_discovered", ROOT_HOLE_ID)))

	# T031 约束复证：解锁发生时捕猎计数为 0（捕猎与解锁零耦合）
	var cur := _gs.get("current_life") as Dictionary
	_assert("C3_unlock_with_zero_captures", "0", str(int(cur.get("captures", -1))),
		int(cur.get("captures", -1)) == 0)

	# Toast：解锁发生时玩家可见（HUD 顶部）
	_assert("C4_unlock_toast_visible", "true", str(entry.hud.toast_visible()),
		entry.hud.toast_visible())
	_assert("C5_unlock_toast_text", "含 新物种已解锁+显示名", entry.hud.toast_text(),
		entry.hud.toast_text().contains("新物种已解锁")
		and entry.hud.toast_text().contains(second_title))

	# 菜单即时刷新：锁定清空、原锁定物种可选
	_assert("C6_menu_unlocked_after_discovery", "0", str(entry.menu.locked_list().size()),
		entry.menu.locked_list().is_empty())
	var ok_sel2 := entry.menu.select_species(second_id)
	_assert("C7_locked_now_selectable", "true", str(ok_sel2), ok_sel2)
	_assert("C8_selection_is_second", str(second_id), str(entry.menu.selected_species()),
		entry.menu.selected_species() == second_id)

	# 发现提示（无解锁规则的探针地点）：Toast 显示「发现新地点：<ID>」
	_gs.call("record_place_discovery", PROBE_PLACE)
	await _advance_frames(1)
	_assert("C9_discovery_toast", "含 发现新地点", entry.hud.toast_text(),
		entry.hud.toast_text().contains("发现新地点")
		and entry.hud.toast_text().contains(PROBE_PLACE))

	# 死亡：解锁保留（T031 约束复证）
	entry.player.survival.apply_damage(9999.0, &"t033_end")
	await _advance_frames(12)
	_assert("C10_back_to_selecting", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")
	_assert("C11_unlock_kept_after_death", "0", str(entry.menu.locked_list().size()),
		entry.menu.locked_list().is_empty())


# ---------------------------------------------------------------------------
# D z 序与遮挡复检（一世轮回后）
# ---------------------------------------------------------------------------

func _section_d_zorder_recheck(entry: MainEntry) -> void:
	print("---- D z 序与遮挡复检 ----")
	# 死亡后结算页盖在菜单上（T032 契约）——先确认结算页可见，再关掉复检底层
	_assert("D1_settle_presented_after_death", "true",
		str(entry.settle_panel.is_presenting()), entry.settle_panel.is_presenting())
	entry.dismiss_settle()
	await _advance_frames(2)
	_assert("D2_menu_visible_after_dismiss", "true", str(entry.menu.visible),
		entry.menu.visible)
	# 解锁后的数字键 2（菜单可见、SELECTING）：只选中第二物种，不出生（K2 契约在新门下复证）
	var configs := entry.species_configs()
	var second_id: StringName = configs[1].species_id
	await _press_key(KEY_2)
	_assert("D3_number_key_selects_after_unlock", str(second_id),
		str(entry.menu.selected_species()), entry.menu.selected_species() == second_id)
	_assert("D4_number_key_select_only", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")
	if not await _check_no_occlusion(entry, "D5"):
		pass
	if entry.menu != null and entry.settle_panel != null:
		var status_layer := entry.get_node_or_null("LifeStatus")
		_assert("D6_settle_still_topmost", "settle>status>menu",
			"%d" % entry.settle_panel.get_index(),
			status_layer != null and entry.settle_panel.get_index() > status_layer.get_index())


# ---------------------------------------------------------------------------
# E Toast 契约（独立 HUD 实例）
# ---------------------------------------------------------------------------

func _section_e_toast(_entry: MainEntry) -> void:
	print("---- E Toast 契约 ----")
	var packed := load(HUD_SCENE) as PackedScene
	if packed == null:
		_assert("E0_hud_loads", "非 null", "null", false)
		return
	var hud := packed.instantiate() as PlayerHud
	root.add_child(hud)
	await _advance_frames(2)
	const sample := "T033 Toast 逐字样本"
	hud.show_toast(sample)
	_assert("E1_toast_visible", "true", str(hud.toast_visible()), hud.toast_visible())
	_assert("E2_toast_text_exact", sample, hud.toast_text(), hud.toast_text() == sample)
	# 短时长自动隐藏（注入单调时钟，不真等毫秒）
	GameClock.use_fake()
	hud.show_toast(sample, 0.05)
	GameClock.advance_ms(400)
	await _advance_frames(2)
	_assert("E3_toast_expires", "false", str(hud.toast_visible()), not hud.toast_visible())
	GameClock.use_real()
	# 空文本直接隐藏
	hud.show_toast("")
	_assert("E4_toast_empty_hidden", "false", str(hud.toast_visible()), not hud.toast_visible())
	# T018 契约不破：Toast 不混入 hud_text()
	hud.show_toast(sample)
	_assert("E5_hud_text_excludes_toast", "不含样本", "有 Toast 字样",
		not hud.hud_text().contains(sample))
	hud.queue_free()
	await _advance_frames(2)


# ---------------------------------------------------------------------------
# F 重生整备（开发计划 T033 原文：无旧 Pawn 残留）+ 第二世出生
# ---------------------------------------------------------------------------

func _section_f_rebirth(entry: MainEntry) -> void:
	print("---- F 重生整备 ----")
	var configs := entry.species_configs()
	var second_id: StringName = configs[1].species_id
	var first_life := entry.current_life_id()

	var ok := entry.select_species(second_id)
	await _advance_frames(8)
	_assert("F1_second_species_alive", "alive", entry.lifecycle_state_name(),
		ok and entry.lifecycle_state_name() == "alive")
	_assert("F2_new_life_id", "不同于第一世", "%s→%s" % [first_life, entry.current_life_id()],
		entry.current_life_id() != "" and entry.current_life_id() != first_life)

	# Player 唯一 + 无 retired 残留（旧身体改名+queue_free 后应已释放）
	var player_count := 0
	for c in entry.level.get_children():
		if String(c.name) == "Player":
			player_count += 1
	_assert("F3_single_player_node", "1", str(player_count), player_count == 1)
	_assert("F4_no_retired_residue", "0", str(_count_retired(entry.level)),
		_count_retired(entry.level) == 0)
	_assert("F5_tracker_rebound", "true",
		str(entry.discovery.player == entry.player), entry.discovery.player == entry.player)
	_assert("F6_species_is_second", str(second_id), str(entry.lifecycle.species_id),
		entry.lifecycle.species_id == second_id)


# ---------------------------------------------------------------------------
# 夹具与工具
# ---------------------------------------------------------------------------

func _advance_frames(n: int) -> void:
	for i in n:
		await process_frame


func _press_key(code: int) -> void:
	# 与 run_art05_input / run_t032 同一模式：keycode + physical 双通道
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var rel := InputEventKey.new()
	rel.keycode = code
	rel.physical_keycode = code
	rel.pressed = false
	Input.parse_input_event(rel)
	await process_frame


func _find(node: Node, target: String) -> Node:
	if node == null:
		return null
	if String(node.name) == target:
		return node
	for child in node.get_children():
		var found := _find(child, target)
		if found != null:
			return found
	return null


func _count_class(node: Node, cls: String) -> int:
	var n := 0
	if node.get_class() == cls:
		n += 1
	for child in node.get_children():
		n += _count_class(child, cls)
	return n


func _count_retired(node: Node) -> int:
	# 旧身体的释放路径：改名 `<原名>_retired` 后 queue_free（LifeCycle._release_body）。
	# 释放完成后场景里不应再有带 retired 字样的节点。
	var n := 0
	if String(node.name).contains("retired"):
		n += 1
	for child in node.get_children():
		n += _count_retired(child)
	return n


func _assert(label: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [label, expected, actual, "PASS" if ok else "FAIL"])


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
