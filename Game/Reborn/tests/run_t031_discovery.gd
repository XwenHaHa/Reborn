extends SceneTree
## T031 地点发现与老鼠解锁（`Docs/Tasks/T031.md` §6）
##
## 验证：稳定 ID 与关卡发现点契约、发现判定（半径/去重）、长期记录（跨世保留）、
## 发现→解锁规则（死亡不取消、捕猎不解锁）、正式入口集成（初始解锁门 + 解锁闭环）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t031_discovery.gd' --quit-after 300000

const GAME_STATE := "res://autoload/game_state.gd"
const MAIN_ENTRY := "res://scripts/core/main_entry.gd"
const MAIN := "res://scenes/core/main.tscn"
const COURTYARD := "res://scenes/maps/l_courtyard.tscn"
const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const TRACKER := "res://scripts/systems/discovery_tracker.gd"

## 与 `tool_make_courtyard.gd` 的稳定 ID 一致（**进存档后不得改**，T036 契约）
const ROOT_HOLE_ID := "root_hole_courtyard_01"
const HOLE_POS := Vector3(26.5, 0.10, 19.0)
const EPS := 1e-3

var _checks := 0
var _fails := 0
var _gs: Node = null
var _wd: Node = null
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null
var _cats: StringName = &""
var _mice: StringName = &""


func _initialize() -> void:
	print("TEST|run_t031_discovery|engine=%s" % Engine.get_version_info().string)
	_gs = root.get_node_or_null("GameState")
	_wd = root.get_node_or_null("WorldDirector")
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig
	_cats = _cat.species_id if _cat != null else &"Cat"
	_mice = _mouse.species_id if _mouse != null else &"Mouse"
	await _section_a_contract()
	await _section_b_tracker()
	await _section_c_long_term()
	await _section_d_unlock_rules()
	await _section_e_entry()
	_finish()


# ---------------------------------------------------------------------------
# A 契约
# ---------------------------------------------------------------------------

func _section_a_contract() -> void:
	print("---- A 契约 ----")
	_assert("A1_species_configs", "非 null", str(_cat != null and _mouse != null),
		_cat != null and _mouse != null)
	if _cat == null or _mouse == null:
		return
	# 初始解锁（策划 §9.2：猫默认可选）——数据驱动，不写物种名
	_assert("A2_cat_initially_unlocked", "true", str(_cat.get("initially_unlocked")),
		bool(_cat.get("initially_unlocked")))
	_assert("A3_mouse_not_initially_unlocked", "false", str(_mouse.get("initially_unlocked")),
		not bool(_mouse.get("initially_unlocked")))
	_assert("A4_mouse_unlock_discovery", ROOT_HOLE_ID, String(_mouse.get("unlock_discovery")),
		String(_mouse.get("unlock_discovery")) == ROOT_HOLE_ID)
	_assert("A5_cat_no_unlock_discovery", "", String(_cat.get("unlock_discovery")),
		StringName(_cat.get("unlock_discovery")) == &"")
	_assert("A6_cat_validates", "0 问题", str(_cat.validate_config().size()),
		_cat.validate_config().is_empty())
	_assert("A7_mouse_validates", "0 问题", str(_mouse.validate_config().size()),
		_mouse.validate_config().is_empty())

	# GameState 新 API
	_assert("A8_game_state", "非 null", str(_gs != null), _gs != null)
	if _gs == null:
		return
	_assert("A9_has_record_place_discovery", "true",
		str(_gs.has_method("record_place_discovery")), _gs.has_method("record_place_discovery"))
	_assert("A10_has_set_rules", "true", str(_gs.has_method("set_discovery_unlock_rules")),
		_gs.has_method("set_discovery_unlock_rules"))
	_assert("A11_has_discovered_places", "Dictionary",
		type_string(typeof(_gs.get("discovered_places"))),
		typeof(_gs.get("discovered_places")) == TYPE_DICTIONARY)

	# 入口默认正式模式（T030 遗留收口：正式解锁接入后 test_mode 必须 false）
	var packed := load(MAIN) as PackedScene
	_assert("A12_main_loads", "非 null", str(packed != null), packed != null)
	if packed != null:
		var main := packed.instantiate()
		var entry := main as MainEntry
		_assert("A13_entry_default_test_mode_false", "false",
			str(entry.test_mode if entry != null else "<null>"), entry != null and not entry.test_mode)
		main.free()

	# 关卡发现点：稳定 ID + 半径 + 位置 + 零碰撞
	var yard := load(COURTYARD) as PackedScene
	_assert("A14_courtyard_loads", "非 null", str(yard != null), yard != null)
	if yard == null:
		return
	var scene := yard.instantiate()
	var disc := scene.get_node_or_null("Discovery_RootHole") as Marker3D
	if _assert("A15_discovery_marker_exists", "非 null", str(disc != null), disc != null):
		_assert("A16_discovery_group", "true", str(disc.is_in_group("discovery_points")),
			disc.is_in_group("discovery_points"))
		_assert("A17_discovery_id", ROOT_HOLE_ID, String(disc.get_meta("discovery_id", "")),
			String(disc.get_meta("discovery_id", "")) == ROOT_HOLE_ID)
		_assert("A18_discovery_radius", "2.0", "%.2f" % float(disc.get_meta("radius", 0.0)),
			absf(float(disc.get_meta("radius", 0.0)) - 2.0) < EPS)
		_assert("A19_discovery_pos", str(HOLE_POS), str(disc.position),
			disc.position.distance_to(HOLE_POS) < EPS)
		_assert("A20_discovery_no_collision", "0", str(_count_collision_shapes(disc)),
			_count_collision_shapes(disc) == 0)
	scene.free()


# ---------------------------------------------------------------------------
# B 发现判定（tracker 单测：运行期造标记 + 桩玩家）
# ---------------------------------------------------------------------------

func _section_b_tracker() -> void:
	print("---- B 发现判定 ----")
	_assert("B0_tracker_script", "非 null", str(load(TRACKER) != null), load(TRACKER) != null)
	if _gs == null:
		return
	_gs.call("reset_for_new_game")

	# 桩世界：一个 Node3D 当"玩家"，两个发现点标记（一个有 ID、一个没有）。
	# 注意：入树前不能用 `global_position`（ setter 在树外不生效），用局部 `position`。
	var world := Node3D.new()
	world.name = "T031World"
	root.add_child(world)
	var player := Node3D.new()
	player.name = "T031Player"
	player.position = Vector3(0.0, 0.5, 0.0)
	world.add_child(player)
	var marker := Marker3D.new()
	marker.name = "T031Marker"
	marker.position = Vector3(10.0, 0.0, 0.0)
	marker.set_meta("discovery_id", ROOT_HOLE_ID)
	marker.set_meta("radius", 2.0)
	marker.add_to_group("discovery_points", true)
	world.add_child(marker)
	var bad := Marker3D.new()
	bad.name = "T031MarkerNoId"
	bad.position = Vector3(0.0, 0.0, 0.0)
	bad.add_to_group("discovery_points", true)
	world.add_child(bad)

	var tracker := DiscoveryTracker.new()
	tracker.name = "T031Tracker"
	tracker.player = player
	tracker.scan_interval = 0.05
	world.add_child(tracker)
	await _advance_frames(1)   # _initialize 期间入树通知要等一帧才完成
	tracker.refresh_points()
	_assert("B1_finds_one_pending", "1", str(tracker.pending_count()),
		tracker.pending_count() == 1)          # 无 ID 的标记被忽略

	# 半径外：不发现
	player.global_position = Vector3(10.0, 0.5, 2.5)   # 水平距 2.5 > 2.0
	await _advance_frames(8)
	_assert("B2_outside_radius_no_discovery", "false",
		str(_gs.call("is_place_discovered", ROOT_HOLE_ID)),
		not bool(_gs.call("is_place_discovered", ROOT_HOLE_ID)))

	# 进半径（边界 2.0 也算）：发现一次
	player.global_position = Vector3(10.0, 0.5, 2.0)   # 水平距恰 2.0
	await _advance_frames(8)
	_assert("B3_boundary_counts", "true",
		str(_gs.call("is_place_discovered", ROOT_HOLE_ID)),
		bool(_gs.call("is_place_discovered", ROOT_HOLE_ID)))
	_assert("B4_pending_cleared", "0", str(tracker.pending_count()), tracker.pending_count() == 0)

	# 出去再进来：长期层去重，不再记
	var events_before := int(_gs.call("event_count"))
	player.global_position = Vector3(10.0, 0.5, 0.5)
	await _advance_frames(8)
	player.global_position = Vector3(10.0, 0.5, 3.5)
	await _advance_frames(8)
	_assert("B5_no_duplicate_event", str(events_before), str(int(_gs.call("event_count"))),
		int(_gs.call("event_count")) == events_before)

	# 玩家置空（结算/选物种期间）：组件静默
	tracker.player = null
	player.global_position = Vector3(10.0, 0.5, 0.0)
	tracker.refresh_points()   # 已发现地点仍在长期层 → 不进 pending
	_assert("B6_discovered_not_pending", "0", str(tracker.pending_count()),
		tracker.pending_count() == 0)

	# 半径兜底：标记无 radius meta 时用组件默认值（探针用独立地点 ID，不清长期层——
	# 清了会把已发现的鼠洞标记也重新挂回 pending）
	var marker2 := Marker3D.new()
	marker2.name = "T031MarkerDefaultRadius"
	marker2.position = Vector3(0.0, 0.0, 0.0)
	marker2.set_meta("discovery_id", &"default_radius_probe")
	marker2.add_to_group("discovery_points", true)
	world.add_child(marker2)
	tracker.player = player
	tracker.refresh_points()
	_assert("B7_pending_has_probe", "1", str(tracker.pending_count()),
		tracker.pending_count() == 1)
	player.global_position = Vector3(1.9, 0.5, 0.0)
	await _advance_frames(8)
	_assert("B8_default_radius_2m", "true",
		str(_gs.call("is_place_discovered", &"default_radius_probe")),
		bool(_gs.call("is_place_discovered", &"default_radius_probe")))

	world.queue_free()
	await _advance_frames(2)


# ---------------------------------------------------------------------------
# C 长期记录
# ---------------------------------------------------------------------------

func _section_c_long_term() -> void:
	print("---- C 长期记录 ----")
	if _gs == null:
		return
	_gs.call("reset_for_new_game")
	_gs.set("test_mode", true)
	_wd.set("world_time", 12.0)

	var lc := _new_cycle()
	lc.request_select()
	lc.begin_spawn(_mice)
	var life1 := lc.mark_spawned(null)

	var first: bool = _gs.call("record_place_discovery", ROOT_HOLE_ID)
	_assert("C1_first_returns_true", "true", str(first), bool(first))
	var list: Array = _gs.call("discovered_place_list")
	_assert("C2_long_term_listed", "1", str(list.size()),
		list.size() == 1 and String(list[0]) == ROOT_HOLE_ID)
	var ev: Array = _gs.call("events_of_kind", &"discovery")
	_assert("C3_discovery_event", "1", str(ev.size()), ev.size() == 1)
	if ev.size() == 1:
		var e := ev[0] as Dictionary
		_assert("C4_event_fields", "%s|%s|12" % [life1, ROOT_HOLE_ID],
			"%s|%s|%.1f" % [String(e.get("life_id", "")),
				String((e.get("data", {}) as Dictionary).get("label", "")),
				float(e.get("world_time", -1.0))],
			String(e.get("life_id", "")) == life1
				and String((e.get("data", {}) as Dictionary).get("label", "")) == ROOT_HOLE_ID
				and absf(float(e.get("world_time", -1.0)) - 12.0) < EPS)
	var cur := _gs.get("current_life") as Dictionary
	_assert("C5_in_life_discoveries", "1",
		str((cur.get("discoveries", []) as Array).size()),
		(cur.get("discoveries", []) as Array).size() == 1)

	# 同一世重复：不再记
	var again: bool = _gs.call("record_place_discovery", ROOT_HOLE_ID)
	_assert("C6_repeat_false", "false", str(again), not bool(again))
	_assert("C7_event_still_one", "1", str((_gs.call("events_of_kind", &"discovery") as Array).size()),
		(_gs.call("events_of_kind", &"discovery") as Array).size() == 1)

	# 死亡 → 新一世：长期发现保留（跨世地点记录，策划 §9）
	lc.end_life(&"c_done")
	_assert("C8_kept_after_life_end", "true",
		str(_gs.call("is_place_discovered", ROOT_HOLE_ID)),
		bool(_gs.call("is_place_discovered", ROOT_HOLE_ID)))
	lc.request_select()
	lc.begin_spawn(_cats)
	lc.mark_spawned(null)
	var third: bool = _gs.call("record_place_discovery", ROOT_HOLE_ID)
	_assert("C9_new_life_still_false", "false", str(third), not bool(third))

	# 新一世档案的 discoveries 不被旧地点污染（本世还没发现任何地点）
	var cur2 := _gs.get("current_life") as Dictionary
	_assert("C10_new_life_discoveries_empty", "0",
		str((cur2.get("discoveries", []) as Array).size()),
		(cur2.get("discoveries", []) as Array).size() == 0)

	# 没有进行中的生命也能记长期层（life_id 空串），不崩不丢
	lc.end_life(&"c_done2")
	var outside: bool = _gs.call("record_place_discovery", &"lonely_place")
	_assert("C11_record_without_life", "true", str(outside), bool(outside))
	var ev2: Array = _gs.call("events_of_kind", &"discovery")
	if _assert("C12_two_discovery_events", "2", str(ev2.size()), ev2.size() == 2):
		var last := ev2[ev2.size() - 1] as Dictionary
		_assert("C13_no_life_event_id", "", String(last.get("life_id", "")),
			String(last.get("life_id", "")) == "")

	# reset_for_new_game 清长期进度
	_gs.call("reset_for_new_game")
	_assert("C14_reset_clears", "false", str(_gs.call("is_place_discovered", ROOT_HOLE_ID)),
		not bool(_gs.call("is_place_discovered", ROOT_HOLE_ID)))
	lc.free()


# ---------------------------------------------------------------------------
# D 解锁规则
# ---------------------------------------------------------------------------

func _section_d_unlock_rules() -> void:
	print("---- D 解锁规则 ----")
	if _gs == null:
		return
	_gs.call("reset_for_new_game")
	_gs.set("test_mode", false)
	_gs.call("set_default_unlock", [_cats])          # 正式初始解锁：只有猫
	_gs.call("set_discovery_unlock_rules", {ROOT_HOLE_ID: _mice})

	_assert("D1_mouse_locked_initially", "false",
		str(_gs.call("is_species_unlocked", _mice)),
		not bool(_gs.call("is_species_unlocked", _mice)))

	# 捕猎不解锁（策划 §9.2：不要求必须捕食一定数量老鼠）
	_gs.call("begin_life", _cats, Vector3.ZERO)
	_gs.call("add_to_life", "captures", 5)
	_gs.call("add_to_life", "escapes", 3)
	_assert("D2_hunting_does_not_unlock", "false",
		str(_gs.call("is_species_unlocked", _mice)),
		not bool(_gs.call("is_species_unlocked", _mice)))
	_assert("D3_no_unlock_event_yet", "0",
		str((_gs.call("events_of_kind", &"species_unlock") as Array).size()),
		(_gs.call("events_of_kind", &"species_unlock") as Array).size() == 0)

	# 首次发现 → 解锁 + 事件
	var first: bool = _gs.call("record_place_discovery", ROOT_HOLE_ID)
	_assert("D4_discovery_returns_true", "true", str(first), bool(first))
	_assert("D5_mouse_unlocked", "true", str(_gs.call("is_species_unlocked", _mice)),
		bool(_gs.call("is_species_unlocked", _mice)))
	var uev: Array = _gs.call("events_of_kind", &"species_unlock")
	if _assert("D6_unlock_event", "1", str(uev.size()), uev.size() == 1):
		var e := uev[0] as Dictionary
		_assert("D7_unlock_event_species", String(_mice),
			String((e.get("data", {}) as Dictionary).get("species", "")),
			String((e.get("data", {}) as Dictionary).get("species", "")) == String(_mice))

	# 死亡不取消（策划 §9.2）
	_gs.call("end_life", &"died")
	_assert("D8_unlock_survives_death", "true",
		str(_gs.call("is_species_unlocked", _mice)),
		bool(_gs.call("is_species_unlocked", _mice)))

	# 重复发现不再触发（unlock_species 幂等）：先出生（life_start 事件本身也算一条），
	# 再对比前后的总事件数——重复发现不得新增任何事件。
	_gs.call("begin_life", _cats, Vector3.ZERO)
	var events_before := int(_gs.call("event_count"))
	_gs.call("record_place_discovery", ROOT_HOLE_ID)
	_assert("D9_repeat_no_new_events", str(events_before), str(int(_gs.call("event_count"))),
		int(_gs.call("event_count")) == events_before)
	_gs.call("end_life", &"d_done")

	# 无规则的地点：只记录、不解锁
	_gs.call("reset_for_new_game")
	_gs.set("test_mode", false)
	_gs.call("set_default_unlock", [_cats])
	_gs.call("set_discovery_unlock_rules", {ROOT_HOLE_ID: _mice})
	_gs.call("begin_life", _cats, Vector3.ZERO)
	_gs.call("record_place_discovery", &"unknown_place")
	_assert("D10_no_rule_no_unlock", "false",
		str(_gs.call("is_species_unlocked", _mice)),
		not bool(_gs.call("is_species_unlocked", _mice)))
	_gs.call("end_life", &"d_done2")

	# 规则是接线数据：reset 保留、set 覆盖式重写
	_assert("D11_rules_kept_over_reset", "true",
		str((_gs.get("discovery_unlock_rules") as Dictionary).has(ROOT_HOLE_ID)),
		(_gs.get("discovery_unlock_rules") as Dictionary).has(ROOT_HOLE_ID))
	_gs.call("set_discovery_unlock_rules", {})
	_assert("D12_rules_overwritten", "0",
		str((_gs.get("discovery_unlock_rules") as Dictionary).size()),
		(_gs.get("discovery_unlock_rules") as Dictionary).is_empty())


# ---------------------------------------------------------------------------
# E 正式入口集成
# ---------------------------------------------------------------------------

func _section_e_entry() -> void:
	print("---- E 正式入口集成 ----")
	if _gs == null:
		return
	_gs.call("reset_for_new_game")
	_wd.set("world_time", 0.0)
	var packed := load(MAIN) as PackedScene
	if packed == null:
		_assert("E0_main_loads", "非 null", "null", false)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _advance_frames(6)
	var entry := main as MainEntry
	if entry == null:
		_assert("E0_entry_class", "MainEntry", "<null>", false)
		main.queue_free()
		await _advance_frames(2)
		return
	_assert("E0_entry_class", "MainEntry", "MainEntry", true)

	# 正式模式（默认 test_mode=false）：初始只可选猫
	_assert("E1_formal_test_mode_off", "false", str(bool(_gs.get("test_mode"))),
		not bool(_gs.get("test_mode")))
	var slots := entry.selectable_slots()
	_assert("E2_only_initially_unlocked", str([String(_cats)]), str(slots),
		slots.size() == 1 and slots[0] == _cats)

	# 选未解锁的鼠：被拒（locked_species）——"作为猫"的门控不变量
	var accepted_mouse := entry.select_species(_mice)
	await _advance_frames(2)
	_assert("E3_locked_rejected", "false", str(accepted_mouse), not accepted_mouse)
	_assert("E4_reject_reason", "locked_species",
		String(entry.lifecycle.last_rejection().get("reason", "")),
		String(entry.lifecycle.last_rejection().get("reason", "")) == "locked_species")
	_assert("E5_still_selecting", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")

	# 出生猫 → 走到洞口发现半径内 → 鼠解锁
	var accepted := entry.select_species(_cats)
	await _advance_frames(6)
	_assert("E6_cat_alive", "alive", entry.lifecycle_state_name(),
		accepted and entry.lifecycle_state_name() == "alive")
	if entry.player == null or not is_instance_valid(entry.player):
		_assert("E7_player_exists", "true", "false", false)
		main.queue_free()
		await _advance_frames(2)
		return
	_assert("E7_player_exists", "true", "true", true)
	_assert("E8_tracker_wired", "true", str(entry.discovery.player == entry.player),
		entry.discovery.player == entry.player)

	entry.player.global_position = Vector3(26.5, 0.10 + 0.24, 17.5)   # 洞南 1.5 m
	for i in 30:
		await physics_frame
		if bool(_gs.call("is_place_discovered", ROOT_HOLE_ID)):
			break
	_assert("E9_place_discovered", "true",
		str(_gs.call("is_place_discovered", ROOT_HOLE_ID)),
		bool(_gs.call("is_place_discovered", ROOT_HOLE_ID)))
	_assert("E10_mouse_unlocked_after_walk", "true",
		str(_gs.call("is_species_unlocked", _mice)),
		bool(_gs.call("is_species_unlocked", _mice)))
	var slots_after := entry.selectable_slots()
	_assert("E11_both_slots_after_discovery", "2", str(slots_after.size()),
		slots_after.size() == 2 and slots_after.has(_cats) and slots_after.has(_mice))

	# 结束本世：解锁保留、下一世鼠可出生
	if entry.player.survival != null:
		entry.player.survival.apply_damage(9999.0, &"t031_end")
	for i in 12:
		await physics_frame
	_assert("E12_back_to_selecting", "selecting", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "selecting")
	_assert("E13_unlock_kept_after_death", "true",
		str(_gs.call("is_species_unlocked", _mice)),
		bool(_gs.call("is_species_unlocked", _mice)))
	var accepted2 := entry.select_species(_mice)
	await _advance_frames(6)
	_assert("E14_mouse_can_spawn", "alive", entry.lifecycle_state_name(),
		accepted2 and entry.lifecycle_state_name() == "alive")

	# 测试模式明确区分：翻开后两个物种都可选（不需要发现）
	entry.test_mode = true
	var main2 := packed.instantiate()
	(main2 as MainEntry).test_mode = true
	root.add_child(main2)
	await _advance_frames(6)
	var entry2 := main2 as MainEntry
	_assert("E15_test_mode_both_slots", "2",
		str(entry2.selectable_slots().size()),
		entry2.selectable_slots().size() == 2)
	main2.queue_free()
	await _advance_frames(4)

	main.queue_free()
	await _advance_frames(4)
	_assert("E16_time_restored_on_exit", "true", str(bool(_wd.get("time_advancing"))),
		bool(_wd.get("time_advancing")))


# ---------------------------------------------------------------------------
# 夹具与工具
# ---------------------------------------------------------------------------

func _new_cycle() -> LifeCycle:
	var lc := LifeCycle.new()
	lc.name = "T031LifeCycle"
	lc.known_species = [_cats, _mice]
	root.add_child(lc)
	return lc


func _count_collision_shapes(node: Node) -> int:
	var n := 0
	if node is CollisionShape3D or node is CollisionObject3D:
		n += 1
	for c in node.get_children():
		n += _count_collision_shapes(c)
	return n


func _advance_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _assert(id: String, expected: String, actual: String, ok: bool) -> bool:
	_checks += 1
	if not ok:
		_fails += 1
		print("CHECK|%s|FAIL|want=%s|got=%s" % [id, expected, actual])
	else:
		print("CHECK|%s|OK" % id)
	return ok


func _finish() -> void:
	print("RESULT|run_t031_discovery|checks=%d|fails=%d" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
