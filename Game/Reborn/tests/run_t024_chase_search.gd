extends SceneTree
## T024 追击、搜索和放弃 断言
##
## 覆盖（`Docs/Tasks/T024.md` §6；数值只读 `Docs/Parameters.md` 第 69 行）：
##   A 接口与参数（搜索超时 5 s / 洞口等待 6 s / 新查询与信号 / 无物种名字面量）
##   B 追击（猎物跑开 → CHASE → 再次收敛；节流；不扑击不伤害）
##   C 失视 → 搜索（SEARCH + 快照目的地；到了就停；重新发现 → CHASE）
##   D 搜索超时放弃（5 s 上限、有界、可重复、不动世界账本）
##   E 洞口等待（洞口目标、洞外停住、6 s 上限、重新出现则不候）
##   F **不读隐藏玩家实时坐标**（瞬移猎物后目的地与快照都不动）
##   G 一场 CHASE 只结算一次（encounter_id 去重；猎物活着才算逃脱）
##   H 集成（真实关卡追击 / 洞口 / HUD 与 MOV| / 无调试节点）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t024_chase_search.gd' --quit-after 300000
## 包内复验（只能用编辑器二进制 + --main-pack）：
##   & '<godot_console.exe>' --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
##       --script 'res://tests/run_t024_chase_search.gd' --quit-after 300000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"
const CAT_AI := "res://scripts/ai/cat_ai.gd"

const EPS := 1e-3
const ARENA := 40.0
const CAT_Y := 0.25
const MOUSE_Y := 0.10
const ATTACK_RANGE := 0.65      # Parameters.md 第 69 行（AttackRange 65）
const SEARCH_TIMEOUT := 5.0     # 第 69 行（搜索超时 5 s）
const HOLE_WAIT_MAX := 6.0      # 第 69 行（鼠洞外等待最大 6 s）
const SPAWN_FRAMES := 12
const HOLE_RADIUS := 0.30

var _checks := 0
var _fails := 0
var _cat_cfg: SpeciesConfig = null
var _mouse_cfg: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null
var _region: NavigationRegion3D = null
var _npc: AnimalBody = null
var _ai: CatAI = null
var _prey: AnimalBody = null
var _mouse_npc: AnimalBody = null
var _extras: Array[Node] = []
var _walls: Array[StaticBody3D] = []
var _wall_seq := 0
var _transitions: Array[Dictionary] = []
var _chase_events: Array[Dictionary] = []


func _initialize() -> void:
	print("TEST|run_t024_chase_search|engine=%s" % Engine.get_version_info().string)
	_cat_cfg = load(CAT) as SpeciesConfig
	_mouse_cfg = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")
	await _section_a_contract()
	await _section_b_chase()
	await _section_c_search()
	await _section_d_timeout()
	await _section_e_hole_wait()
	await _section_f_no_live_tracking()
	await _section_g_encounter()
	await _section_h_integration()
	_finish()


# ---------------------------------------------------------------------------
# A 接口与参数
# ---------------------------------------------------------------------------

func _section_a_contract() -> void:
	print("---- A 接口与参数 ----")
	var script := load(CAT_AI) as Script
	_assert("A_cat_ai_script_exists", "非 null", str(script != null), script != null)
	if script == null:
		return
	var probe: Object = script.new()
	_assert("A_is_cat_ai", "CatAI", str(probe is CatAI), probe is CatAI)
	if probe is CatAI:
		var ai := probe as CatAI
		_assert_near("A_search_timeout_5", SEARCH_TIMEOUT, ai.search_timeout, EPS)
		_assert_near("A_hole_wait_max_6", HOLE_WAIT_MAX, ai.hole_wait_max, EPS)
		_assert("A_chase_repath_positive", "> 0", "%.2f" % ai.chase_repath_interval, ai.chase_repath_interval > 0.0)
		_assert("A_search_arrive_radius_positive", "> 0", "%.2f" % ai.search_arrive_radius, ai.search_arrive_radius > 0.0)
		_assert("A_hole_search_radius_positive", "> 0", "%.2f" % ai.hole_search_radius, ai.hole_search_radius > 0.0)
		_assert("A_search_overall_max_ge_11", "≥ 11", "%.2f" % ai.search_overall_max, ai.search_overall_max >= 11.0)
		for m in ["is_chasing", "is_searching", "search_elapsed", "search_target", "search_count",
				"give_up_count", "hole_wait_elapsed", "hole_target_id", "chase_count",
				"escape_report_count", "encounter_id"]:
			_assert("A_has_%s" % m, "有 %s()" % m, str(ai.has_method(m)), ai.has_method(m))
		_assert("A_has_signal_chase_started", "true", str(ai.has_signal("chase_started")), ai.has_signal("chase_started"))
		_assert("A_has_signal_chase_ended", "true", str(ai.has_signal("chase_ended")), ai.has_signal("chase_ended"))
	probe.free()

	# 枚举顺序（T019 契约）：CHASE = 6、SEARCH = 7
	_assert("A_state_chase_index", "6", str(AnimalAI.State.CHASE), AnimalAI.State.CHASE == 6)
	_assert("A_state_search_index", "7", str(AnimalAI.State.SEARCH), AnimalAI.State.SEARCH == 7)

	# 源码静态检查：不出现物种名字面量（包内 `.gd` 不可读 → 如实标 STATIC|NOT-APPLICABLE）
	var src := _read_source(CAT_AI)
	if src.is_empty():
		print("STATIC|NOT-APPLICABLE|cat_ai.gd（包内 .gd 不可读，T013 口径）")
	else:
		_assert("A_static_no_species_literal", "不含 \"Cat\" 字面量", "含" if src.contains("\"Cat\"") else "不含",
			not src.contains("\"Cat\""))

	# 起一局读 `ai_report()` 新字段
	await _fresh_world({"prey_at": _front(3.0)})
	if _ai == null:
		_assert("A_builds_cat_ai", "非 null", "<null>", false)
		return
	var rep := _ai.ai_report()
	for key in ["search_elapsed", "search_target", "search_count", "give_up_count", "hole_wait_elapsed",
			"hole_target", "chase_count", "escape_reports", "encounter_id", "chasing", "searching"]:
		_assert("A_report_has_%s" % key, "存在", str(rep.has(key)), rep.has(key))


func _read_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	return txt


# ---------------------------------------------------------------------------
# B 追击
# ---------------------------------------------------------------------------

func _section_b_chase() -> void:
	print("---- B 追击（CHASE）----")
	await _fresh_world({"prey_at": _front(8.0)})
	if _ai == null:
		return
	var saw := await _run_seconds(2.0, func() -> bool: return _ai.state_id() == &"alert")
	_assert("B1_sight_alerts", "alert（%.2f s）" % saw, str(_ai.state_id()), _ai.state_id() == &"alert")
	_assert("B1_reason_saw_prey", "saw_prey", str(_ai.state_reason()), _ai.state_reason() == &"saw_prey")
	var appr := await _run_seconds(3.0, func() -> bool: return _ai.state_id() == &"approach")
	_assert("B1_then_approach", "approach（%.2f s）" % appr, str(_ai.state_id()), _ai.state_id() == &"approach")

	# 猎物跑开（仍可见、超出攻击距离）→ CHASE
	_place_prey(_front(3.0))
	var chased := await _run_seconds(2.5, func() -> bool: return _ai.state_id() == &"chase")
	_assert("B2_enters_chase", "chase（%.2f s）" % chased, str(_ai.state_id()), _ai.state_id() == &"chase")
	_assert("B2_reason_chasing", "chasing", str(_ai.state_reason()), _ai.state_reason() == &"chasing")
	_assert("B5_path_points_positive", "≥ 1", str(int(_ai.ai_report()["path_points"])),
		int(_ai.ai_report()["path_points"]) >= 1)

	var sets0 := int(_ai.ai_report()["destination_sets"])
	await _run_seconds(1.0, func() -> bool: return _ai.approach_distance() <= ATTACK_RANGE)
	var sets1 := int(_ai.ai_report()["destination_sets"])
	_assert("B4_repath_throttled", "增量 ≤ 6", "增量 %d" % (sets1 - sets0), sets1 - sets0 <= 6)

	var closed := await _run_seconds(12.0, func() -> bool: return _ai.approach_distance() <= ATTACK_RANGE)
	_assert("B3_closes_again", "≤ %.2f m（%.2f s）" % [ATTACK_RANGE, closed], "%.3f m" % _ai.approach_distance(),
		_ai.approach_distance() <= ATTACK_RANGE)
	_assert("B7_reason_in_range", "in_range", str(_ai.state_reason()), _ai.state_reason() == &"in_range")
	var hold := _npc.global_position
	await _run_seconds(1.0)
	_assert("B7_stops_after_in_range", "≤ 0.15 m", "%.4f m" % hold.distance_to(_npc.global_position),
		hold.distance_to(_npc.global_position) <= 0.15)

	# 连续换位 3 次 → 每次都能再收敛（追击不是一次性）
	for i in 3:
		# ±30° 保持在视锥内（半角 60°）：120° 会被判"看不见"，那就成了搜索而不是追击
		_place_prey(_front(2.0, (float(i) - 1.0) * 30.0))
		await _advance_frames(3)
		var again := await _run_seconds(12.0, func() -> bool: return _ai.approach_distance() <= ATTACK_RANGE)
		_assert("B6_reclose_%d" % (i + 1), "≤ %.2f m（%.2f s）" % [ATTACK_RANGE, again],
			"%.3f m" % _ai.approach_distance(), _ai.approach_distance() <= ATTACK_RANGE)

	_assert("B8_no_pounce", "0", str(_npc.pounce_count), _npc.pounce_count == 0)
	_assert("B8_no_captures", "0", str(_npc.captures), _npc.captures == 0)
	_assert("B8_prey_health_unchanged", "100.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 100.0) <= 0.01)


# ---------------------------------------------------------------------------
# C 失视 → 搜索
# ---------------------------------------------------------------------------

func _section_c_search() -> void:
	print("---- C 失视 → 搜索（SEARCH）----")
	await _fresh_world({"prey_at": _front(3.0)})
	if _ai == null:
		return
	await _run_seconds(6.0, func() -> bool: return _ai.approach_distance() <= ATTACK_RANGE)
	_place_prey(_front(3.0))
	await _advance_frames(3)
	_add_wall_at(1.5, 0.0, 8.0)
	# `lost_sight` 只活到"警戒结束后的同一帧"（紧接着 `_step_search` 会写 `moving_to_last_seen`），
	# 所以触发原因用**转移账**判定，而不是抓瞬时 `state_reason()`
	var lost := await _run_seconds(1.5, func() -> bool:
		return _ai.state_reason() == &"lost_sight" or _has_transition("search", "lost_sight"))
	_assert("C1_alert_on_loss", "alert(lost_sight) → search（%.2f s）" % lost,
		"%s/%s" % [str(_ai.state_id()), str(_ai.state_reason())],
		_ai.state_id() == &"alert" or _ai.state_reason() == &"lost_sight" or _has_transition("search", "lost_sight"))
	_assert("C1_transition_lost_sight", "存在 alert→search(lost_sight)", _transition_reasons(),
		_has_transition("search", "lost_sight"))
	var in_search := await _run_seconds(1.5, func() -> bool: return _ai.is_searching())
	_assert("C1_enters_search", "search（%.2f s）" % in_search, str(_ai.state_id()), _ai.is_searching())
	_assert("C2_reason_moving", "moving_to_last_seen", str(_ai.state_reason()),
		_ai.state_reason() == &"moving_to_last_seen")
	_assert("E7_no_hole_target", "空", _ai.hole_target_id(), _ai.hole_target_id().is_empty())

	var snapshot: Vector3 = _ai.search_target()
	var seen_now := _npc.perception.last_seen_position()
	_assert("C3_snapshot_matches_last_seen", "≤ 0.01 m", "%.4f m" % snapshot.distance_to(seen_now),
		snapshot.distance_to(seen_now) <= 0.01)
	_assert("C2_destination_is_snapshot", "≤ 0.15 m", "%.4f m" % _ai.destination().distance_to(snapshot),
		_ai.destination().distance_to(snapshot) <= 0.15)

	# 搜索计时与状态可查看
	var e0: float = _ai.search_elapsed()
	await _run_seconds(0.4)
	_assert("C6_search_elapsed_grows", "≥ 0.35 s", "%.3f s" % (_ai.search_elapsed() - e0),
		_ai.search_elapsed() - e0 >= 0.35)
	# C4：把猎物搬到视野外（仍不可见）→ 快照与目的地都不动，**不指实时位置**
	_hide_prey()
	await _advance_frames(4)
	_assert("C4_prey_not_visible", "false", str(_npc.perception.is_threat_visible()),
		not _npc.perception.is_threat_visible())
	_assert("C4_snapshot_unchanged", "≤ 0.01 m", "%.4f m" % snapshot.distance_to(_ai.search_target()),
		snapshot.distance_to(_ai.search_target()) <= 0.01)
	_assert("C4_destination_not_live", "> 0.5 m", "%.3f m" % _ai.destination().distance_to(_prey.global_position),
		_ai.destination().distance_to(_prey.global_position) > 0.5)
	# 撤掉遮挡：猫要能真的走到快照点（墙挡着会被顶住 → 失败链先于 arrived）
	_free_walls()
	await _advance_frames(4)
	var arrived := await _run_seconds(8.0, func() -> bool: return _ai.state_reason() == &"arrived")
	_assert("C5_reaches_snapshot", "arrived（%.2f s）" % arrived, str(_ai.state_reason()),
		_ai.state_reason() == &"arrived")
	var stop_pos := _npc.global_position
	await _run_seconds(1.0)
	_assert("C5_stops_when_arrived", "≤ 0.15 m", "%.4f m" % stop_pos.distance_to(_npc.global_position),
		stop_pos.distance_to(_npc.global_position) <= 0.15)

	# 搜索中重新发现 → CHASE（reacquired）
	await _fresh_world({"prey_at": _front(3.0)})
	await _run_seconds(6.0, func() -> bool: return _ai.approach_distance() <= ATTACK_RANGE)
	_place_prey(_front(3.0))
	await _advance_frames(3)
	var wall := _add_wall_at(1.5, 0.0, 8.0)
	await _run_seconds(2.0, func() -> bool: return _ai.is_searching())
	_assert("C7_search_before_reacquire", "true", str(_ai.is_searching()), _ai.is_searching())
	wall.queue_free()
	await _advance_frames(3)
	# `reacquired` 同样会被同一帧的 `_step_chase` 覆盖成 `chasing` → 触发原因用转移账判定
	var reacq := await _run_seconds(2.5, func() -> bool:
		return _ai.state_id() == &"chase" and _has_transition("chase", "reacquired"))
	_assert("C7_reacquire_to_chase", "chase（%.2f s）" % reacq, str(_ai.state_id()), _ai.state_id() == &"chase")
	_assert("C7_reason_reacquired", "存在 search→chase(reacquired)", str(_ai.state_reason()),
		_has_transition("chase", "reacquired"))


# ---------------------------------------------------------------------------
# D 搜索超时放弃
# ---------------------------------------------------------------------------

func _section_d_timeout() -> void:
	print("---- D 搜索超时放弃（5 s 上限）----")
	await _fresh_world({"prey_at": _front(3.0)})
	if _ai == null:
		return
	await _run_seconds(6.0, func() -> bool: return _ai.approach_distance() <= ATTACK_RANGE)
	_place_prey(_front(3.0))
	await _advance_frames(3)
	_add_wall_at(1.5, 0.0, 8.0)
	await _run_seconds(2.0, func() -> bool: return _ai.is_searching())
	_assert("D_setup_searching", "true", str(_ai.is_searching()), _ai.is_searching())
	# 让 5 s 上限能真的走完：猎物搬到视野外（保持"看不见"），并撤掉挡住路的墙
	_hide_prey()
	_free_walls()
	await _advance_frames(4)
	var t0 := _now()
	var gave_up := await _run_seconds(8.0, func() -> bool: return _ai.state_reason() == &"search_timeout")
	var spent := _now() - t0
	_assert("D1_timeout_to_explore", "explore/search_timeout（%.2f s）" % spent,
		"%s/%s" % [str(_ai.state_id()), str(_ai.state_reason())], _ai.state_reason() == &"search_timeout")
	_assert("D1_timeout_about_5s", "5.0 ±1.0 s", "%.2f s" % spent, absf(spent - SEARCH_TIMEOUT) <= 1.0)
	_assert("D2_give_up_count_1", "1", str(_ai.give_up_count()), _ai.give_up_count() == 1)
	_assert("D2_not_searching", "false", str(_ai.is_searching()), not _ai.is_searching())
	# 放弃后计时字段要**诚实归零**（不在搜索 / 不在等待 = 0）
	_assert("D7_search_elapsed_reset", "0.00 s", "%.2f s" % _ai.search_elapsed(), _ai.search_elapsed() <= 0.01)
	_assert("D7_hole_wait_reset", "0.00 s", "%.2f s" % _ai.hole_wait_elapsed(), _ai.hole_wait_elapsed() <= 0.01)
	_assert("D3_world_time_advanced", "> 4.0 s", "%.2f s" % spent, spent > 4.0)
	_assert("D5_no_immediate_research", "非 search", str(_ai.state_id()), _ai.state_id() != &"search")
	_assert("D6_no_capture_change", "0/0", "%d/%d" % [int(_wd.get("capture_count")), int(_wd.get("capture_food_count"))],
		int(_wd.get("capture_count")) == 0 and int(_wd.get("capture_food_count")) == 0)

	# 第二次：重新看见 → 再失视 → 重新搜索并重新计时
	var walls := _extras.duplicate()
	for n in walls:
		if n != null and is_instance_valid(n):
			n.queue_free()
	await _advance_frames(3)
	await _run_seconds(4.0, func() -> bool: return _ai.state_id() == &"chase" or _ai.state_id() == &"approach")
	_place_prey(_front(3.0))
	await _advance_frames(3)
	_add_wall_at(1.5, 0.0, 8.0)
	await _run_seconds(2.0, func() -> bool: return _ai.is_searching())
	_assert("D4_second_search_count_2", "≥ 2", str(_ai.search_count()), _ai.search_count() >= 2)
	# 同上：保持"看不见"但把路让开，让 5 s 上限能真的走到
	_hide_prey()
	_free_walls()
	await _advance_frames(4)
	var t1 := _now()
	var gave_up2 := await _run_seconds(8.0, func() -> bool: return _ai.give_up_count() >= 2)
	_assert("D4_second_give_up", "≥ 2（%.2f s）" % (_now() - t1), str(_ai.give_up_count()), _ai.give_up_count() >= 2)
	_assert("D4_second_also_about_5s", "≈ 5 s", "%.2f s" % (_now() - t1), absf((_now() - t1) - SEARCH_TIMEOUT) <= 1.2)


# ---------------------------------------------------------------------------
# E 洞口等待
# ---------------------------------------------------------------------------

func _section_e_hole_wait() -> void:
	print("---- E 洞口等待（6 s 上限）----")
	var hole := Vector3(0.0, 0.05, -3.5)
	await _fresh_world({"prey_at": hole, "hole_at": hole, "hole_id": "HideSpot_Hole"})
	if _ai == null:
		return
	await _run_seconds(3.0, func() -> bool: return _npc.perception.is_threat_visible())
	_assert("E_setup_prey_visible", "true", str(_npc.perception.is_threat_visible()),
		_npc.perception.is_threat_visible())
	# 让猎物"进洞"：瞬移到视野外（最后已知位置 = 洞口附近）
	_place_prey(Vector3(0.0, MOUSE_Y, -25.0))
	var in_hole := await _run_seconds(2.5, func() -> bool: return not _ai.hole_target_id().is_empty())
	_assert("E1_hole_target_chosen", "HideSpot_Hole（%.2f s）" % in_hole, _ai.hole_target_id(),
		_ai.hole_target_id() == "HideSpot_Hole")
	_assert("E1_destination_is_hole", "≤ 0.20 m", "%.4f m" % _ai.destination().distance_to(hole),
		_ai.destination().distance_to(hole) <= 0.20)
	var waiting := await _run_seconds(6.0, func() -> bool: return _ai.hole_wait_elapsed() > 0.0)
	_assert("E2_hole_wait_started", "> 0（%.2f s）" % waiting, "%.2f" % _ai.hole_wait_elapsed(),
		_ai.hole_wait_elapsed() > 0.0)
	_assert("E2_reason_hole_wait", "hole_wait", str(_ai.state_reason()), _ai.state_reason() == &"hole_wait")
	var wait_pos := _npc.global_position
	var wait_mark: float = _ai.hole_wait_elapsed()
	await _run_seconds(1.0)
	_assert("E3_still_during_wait", "≤ 1.05 s", "%.3f s" % _ai.hole_wait_elapsed(),
		_ai.hole_wait_elapsed() <= 1.05 and _ai.hole_wait_elapsed() >= wait_mark)
	_assert("E3_move_intent_zero", "(0, 0)", str(_npc.move_intent), _npc.move_intent.length() < 0.01)
	_assert("E3_no_move_while_waiting", "≤ 0.15 m", "%.4f m" % wait_pos.distance_to(_npc.global_position),
		wait_pos.distance_to(_npc.global_position) <= 0.15)
	_assert("E4_not_inside_hole", "≥ 0.30 m", "%.3f m" % _npc.global_position.distance_to(hole),
		_npc.global_position.distance_to(hole) >= HOLE_RADIUS)

	var hole_out := await _run_seconds(8.0, func() -> bool: return _ai.state_reason() == &"hole_timeout")
	_assert("E5_hole_timeout", "hole_timeout（%.2f s）" % hole_out, str(_ai.state_reason()),
		_ai.state_reason() == &"hole_timeout")
	_assert("E5_give_up_counted", "≥ 1", str(_ai.give_up_count()), _ai.give_up_count() >= 1)
	_assert("E5_back_to_explore", "explore", str(_ai.state_id()), _ai.state_id() == &"explore")

	# 等待期间猎物重新出现 → 立刻转追击（不等满 6 s）
	await _fresh_world({"prey_at": hole, "hole_at": hole, "hole_id": "HideSpot_Hole"})
	await _run_seconds(3.0, func() -> bool: return _npc.perception.is_threat_visible())
	_place_prey(Vector3(0.0, MOUSE_Y, -25.0))
	await _run_seconds(6.0, func() -> bool: return _ai.hole_wait_elapsed() > 0.0)
	_assert("E6_setup_waiting", "> 0", "%.2f" % _ai.hole_wait_elapsed(), _ai.hole_wait_elapsed() > 0.0)
	_place_prey(_front(3.0))
	var to_chase := await _run_seconds(2.5, func() -> bool: return _ai.state_id() == &"chase")
	_assert("E6_reappear_to_chase", "chase（%.2f s）" % to_chase, str(_ai.state_id()), _ai.state_id() == &"chase")
	_assert("E6_wait_cleared", "0", "%.2f" % _ai.hole_wait_elapsed(), _ai.hole_wait_elapsed() <= 0.01)


# ---------------------------------------------------------------------------
# F 不读隐藏玩家实时坐标
# ---------------------------------------------------------------------------

func _section_f_no_live_tracking() -> void:
	print("---- F 不读隐藏玩家实时坐标 ----")
	var hole := Vector3(0.0, 0.05, -3.5)
	await _fresh_world({"prey_at": hole, "hole_at": hole, "hole_id": "HideSpot_Hole"})
	if _ai == null:
		return
	await _run_seconds(3.0, func() -> bool: return _npc.perception.is_threat_visible())
	_place_prey(Vector3(0.0, MOUSE_Y, -25.0))
	await _run_seconds(2.0, func() -> bool: return not _ai.hole_target_id().is_empty())
	var snapshot: Vector3 = _ai.search_target()
	var dest := _ai.destination()
	# 把隐藏的猎物搬到**看得见之外**的两处（远 / 较近，都在视距与视锥之外）：快照与目的地都不得动
	_hide_prey()
	await _advance_frames(6)
	_assert("F1_prey_out_of_sight", "false", str(_npc.perception.is_threat_visible()),
		not _npc.perception.is_threat_visible())
	_assert("F1_snapshot_unchanged_far", "≤ 0.01 m", "%.4f m" % snapshot.distance_to(_ai.search_target()),
		snapshot.distance_to(_ai.search_target()) <= 0.01)
	_assert("F1_destination_unchanged_far", "≤ 0.01 m", "%.4f m" % dest.distance_to(_ai.destination()),
		dest.distance_to(_ai.destination()) <= 0.01)
	_assert("F3_destination_far_from_live_1", "> 0.5 m", "%.3f m" % _ai.destination().distance_to(_prey.global_position),
		_ai.destination().distance_to(_prey.global_position) > 0.5)
	_hide_prey(Vector3(0.0, MOUSE_Y, 14.0))
	await _advance_frames(6)
	_assert("F2_prey_out_of_sight", "false", str(_npc.perception.is_threat_visible()),
		not _npc.perception.is_threat_visible())
	_assert("F2_snapshot_unchanged_nearer", "≤ 0.01 m", "%.4f m" % snapshot.distance_to(_ai.search_target()),
		snapshot.distance_to(_ai.search_target()) <= 0.01)
	_assert("F2_destination_unchanged_nearer", "≤ 0.01 m", "%.4f m" % dest.distance_to(_ai.destination()),
		dest.distance_to(_ai.destination()) <= 0.01)
	_assert("F3_destination_far_from_live_2", "> 0.5 m", "%.3f m" % _ai.destination().distance_to(_prey.global_position),
		_ai.destination().distance_to(_prey.global_position) > 0.5)

	# 普通搜索里"朝快照走"：位移方向朝向快照（夹角 < 60°）
	await _fresh_world({"prey_at": _front(6.0)})
	await _run_seconds(2.0, func() -> bool: return _npc.perception.is_threat_visible())
	_add_wall_at(2.5, 0.0, 8.0)
	await _run_seconds(2.0, func() -> bool: return _ai.is_searching())
	var target: Vector3 = _ai.search_target()
	var p0 := _npc.global_position
	await _run_seconds(0.8)
	var moved := _npc.global_position - p0
	var to_target: Vector3 = target - p0
	moved.y = 0.0
	to_target.y = 0.0
	var dot := 1.0
	if moved.length() > 0.05 and to_target.length() > 0.05:
		dot = moved.normalized().dot(to_target.normalized())
	_assert("F4_moves_towards_snapshot", "夹角 < 60°（dot > 0.5）", "dot=%.3f moved=%.3f m" % [dot, moved.length()],
		dot > 0.5)


# ---------------------------------------------------------------------------
# G 一场 CHASE 只结算一次
# ---------------------------------------------------------------------------

func _section_g_encounter() -> void:
	print("---- G 一场 CHASE 只结算一次 ----")
	await _fresh_world({"prey_at": _front(3.0)})
	if _ai == null:
		return
	await _run_seconds(6.0, func() -> bool: return _ai.approach_distance() <= ATTACK_RANGE)
	_place_prey(_front(3.0))
	var chase := await _run_seconds(3.0, func() -> bool: return _ai.is_chasing())
	_assert("G1_enters_chase", "true（%.2f s）" % chase, str(_ai.is_chasing()), _ai.is_chasing())
	var first_id: String = _ai.encounter_id()
	_assert("G1_encounter_id_nonempty", "非空", first_id, not first_id.is_empty())
	_assert("G1_chase_count_1", "1", str(_ai.chase_count()), _ai.chase_count() == 1)
	_assert("G1_started_signal_once", "1", str(_chase_starts()), _chase_starts() == 1)

	# 猎物存活下失视 → 结束一场追逐 → 记一次逃脱
	_add_wall_at(1.5, 0.0, 8.0)
	var searched := await _run_seconds(3.0, func() -> bool: return _ai.is_searching())
	_assert("G2_search_after_loss", "true（%.2f s）" % searched, str(_ai.is_searching()), _ai.is_searching())
	_assert("G2_escape_reported", "1", str(_ai.escape_report_count()), _ai.escape_report_count() == 1)
	_assert("G2_ended_prey_alive", "true", str(_chase_last_alive()), _chase_last_alive())
	_assert("G2_encounter_cleared", "空", _ai.encounter_id(), _ai.encounter_id().is_empty())
	_assert("G3_ended_signal_once", "1", str(_chase_ends()), _chase_ends() == 1)
	await _run_seconds(1.0)
	_assert("G3_no_double_settle", "1", str(_ai.escape_report_count()), _ai.escape_report_count() == 1)

	# 重新看见 → 新一场 CHASE → 新 encounter_id
	var walls := _extras.duplicate()
	for n in walls:
		if n != null and is_instance_valid(n):
			n.queue_free()
	await _advance_frames(3)
	_place_prey(_front(3.0))
	var second := await _run_seconds(3.0, func() -> bool: return _ai.is_chasing())
	_assert("G5_second_chase", "true（%.2f s）" % second, str(_ai.is_chasing()), _ai.is_chasing())
	_assert("G5_new_encounter_id", "≠ 上一场", "%s vs %s" % [_ai.encounter_id(), first_id],
		not _ai.encounter_id().is_empty() and _ai.encounter_id() != first_id)
	_assert("G5_chase_count_2", "2", str(_ai.chase_count()), _ai.chase_count() == 2)

	# 猎物已死 → 结束时不记逃脱
	await _fresh_world({"prey_at": _front(3.0)})
	await _run_seconds(6.0, func() -> bool: return _ai.approach_distance() <= ATTACK_RANGE)
	_place_prey(_front(3.0))
	await _run_seconds(3.0, func() -> bool: return _ai.is_chasing())
	_prey.survival.apply_damage(9999.0, &"test")
	await _advance_frames(4)
	await _run_seconds(3.0, func() -> bool: return _ai.is_searching())
	_assert("G4_ended_prey_dead", "false", str(_chase_last_alive()), not _chase_last_alive())
	_assert("G4_no_escape_for_dead_prey", "0", str(_ai.escape_report_count()), _ai.escape_report_count() == 0)


func _chase_starts() -> int:
	var n := 0
	for e in _chase_events:
		if String(e["kind"]) == "start":
			n += 1
	return n


func _chase_ends() -> int:
	var n := 0
	for e in _chase_events:
		if String(e["kind"]) == "end":
			n += 1
	return n


func _chase_last_alive() -> bool:
	for i in range(_chase_events.size() - 1, -1, -1):
		if String(_chase_events[i]["kind"]) == "end":
			return bool(_chase_events[i]["alive"])
	return false


# ---------------------------------------------------------------------------
# H 集成
# ---------------------------------------------------------------------------

func _section_h_integration() -> void:
	print("---- H 集成（真实关卡 / HUD 与 MOV| / 无调试节点）----")
	_free_world()
	await _advance_frames(3)
	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	_assert("H_level_loads", "Node3D", str(level != null), level != null)
	if level == null:
		return
	root.add_child(level)
	await _advance_frames(6)

	var cat_spawn := Vector3.ZERO
	var hole_pos := Vector3.ZERO
	var hole_name := ""
	for n in _all_nodes(level):
		if n.is_in_group("spawn_points") and n.has_meta("species") and String(n.get_meta("species")) == "Cat":
			cat_spawn = (n as Node3D).global_position
		if n.is_in_group("hide_spots") and n is Node3D:
			var kind := ""
			if n.has_meta("kind"):
				kind = String(n.get_meta("kind"))
			if kind == "mouse_hole":
				hole_pos = (n as Node3D).global_position
				hole_name = String(n.name)
	_assert("H_cat_spawn_found", "非零", str(cat_spawn), cat_spawn != Vector3.ZERO)
	_assert("H_hole_marker_found", "非空", hole_name, not hole_name.is_empty())

	# 猫 NPC 在关卡里发现 → 追击（水平位移 > 1.5 m）
	var cat := (load(BODY) as PackedScene).instantiate() as AnimalBody
	cat.species_config = _cat_cfg
	cat.player_controlled = false
	cat.position = cat_spawn
	level.add_child(cat)
	cat.ai_enabled = true
	await _advance_frames(SPAWN_FRAMES)
	var cat_ai := cat.ai as CatAI
	_assert("H_cat_ai", "CatAI", str(cat_ai), cat_ai is CatAI)
	var fwd := -cat.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
	var mouse := (load(BODY) as PackedScene).instantiate() as AnimalBody
	mouse.species_config = _mouse_cfg
	mouse.player_controlled = false
	mouse.ai_enabled = false
	var spot := cat.global_position + fwd * 5.0
	mouse.position = Vector3(spot.x, 0.10, spot.z)
	level.add_child(mouse)
	await _advance_frames(6)
	var start := cat.global_position
	var spaced := await _run_seconds(10.0, func() -> bool:
		return Vector2(cat.global_position.x - start.x, cat.global_position.z - start.z).length() > 1.5)
	var moved_dist := Vector2(cat.global_position.x - start.x, cat.global_position.z - start.z).length()
	_assert("H1_cat_chases_in_level", "> 1.5 m（%.2f s）" % spaced, "%.2f m" % moved_dist, moved_dist > 1.5)

	# 鼠"进洞" → 猫搜索 → 洞口等待 → 有界放弃
	if not hole_name.is_empty():
		# **不去动 `ai_enabled`**：`AnimalBody._sync_ai()` 在关闭时会释放 AI、再打开时重建**新实例** →
		# 旧引用失效且计数清零（实测会 `Nil` + 崩溃）。改用"记不住状态就重建一对新猫/鼠"：H1 的猫鼠释放，
		# 新猫巡游关掉（不进巡游就不会自己转身/走开），摆好位后显式 `look_at` 朝向鼠。
		# 近距豁免（≤ 0.80 m）只跳过遮挡、**仍查视野角**，所以朝向必须对。
		cat.queue_free()
		mouse.queue_free()
		await _advance_frames(3)
		# 洞口可能贴着树根/屏障 → 鼠放在"洞口朝出生点一侧" 0.40 m（仍在 `hole_search_radius` 0.6 m 内），猫再往前 0.50 m
		var away := cat_spawn - hole_pos
		away.y = 0.0
		if away.length() < 0.5:
			away = Vector3(0.0, 0.0, 1.0)
		away = away.normalized()
		var mouse_at := Vector3(hole_pos.x + away.x * 0.4, 0.10, hole_pos.z + away.z * 0.4)
		mouse = (load(BODY) as PackedScene).instantiate() as AnimalBody
		mouse.species_config = _mouse_cfg
		mouse.player_controlled = false
		mouse.position = mouse_at
		level.add_child(mouse)
		cat = (load(BODY) as PackedScene).instantiate() as AnimalBody
		cat.species_config = _cat_cfg
		cat.player_controlled = false
		cat.position = Vector3(hole_pos.x + away.x * 0.9, 0.25, hole_pos.z + away.z * 0.9)
		level.add_child(cat)
		cat.ai_enabled = true
		cat_ai = cat.ai as CatAI
		cat_ai.patrol_enabled = false
		await _advance_frames(SPAWN_FRAMES)
		cat.look_at(Vector3(mouse_at.x, cat.global_position.y, mouse_at.z), Vector3.UP)
		await _advance_frames(2)
		print("MEASURE|h2|cat=%s mouse=%s hole=%s gap=%.3f" % [
			cat.global_position, mouse.global_position, hole_pos, cat.global_position.distance_to(mouse.global_position)])
		var seen_hole := await _run_seconds(2.0, func() -> bool: return cat.perception.is_threat_visible())
		_assert("H2_sees_at_hole", "true（%.2f s）" % seen_hole, str(cat.perception.is_threat_visible()),
			cat.perception.is_threat_visible())
		_assert("H2_snapshot_near_hole", "≤ 0.6 m", "%.3f m" % cat.perception.last_seen_position().distance_to(hole_pos),
			cat.perception.last_seen_position().distance_to(hole_pos) <= 0.6)
		mouse.global_position = Vector3(hole_pos.x, 0.10, hole_pos.z - 25.0)
		var hole_chosen := await _run_seconds(4.0, func() -> bool: return not cat_ai.hole_target_id().is_empty())
		_assert("H2_hole_target_is_level_hole", hole_name, cat_ai.hole_target_id(),
			cat_ai.hole_target_id() == hole_name or not cat_ai.hole_target_id().is_empty())
		var bounded := await _run_seconds(16.0, func() -> bool: return cat_ai.give_up_count() >= 1)
		_assert("H2_gives_up_bounded", "≥ 1（%.2f s）" % bounded, str(cat_ai.give_up_count()),
			cat_ai.give_up_count() >= 1)

	var level_debug := _count_debug_nodes(level)
	_assert("H4_no_debug_node_in_level", "0", str(level_debug), level_debug == 0)
	level.queue_free()
	await _advance_frames(3)

	# 调试入口：HUD `ai:` 与 `MOV|` 能看到 search / giveups / chase
	var entry := (load(ENTRY) as PackedScene).instantiate() as Node3D
	root.add_child(entry)
	await _advance_frames(10)
	var player := entry.get("player") as AnimalBody
	if player != null:
		player.ai_enabled = true
		await _advance_frames(12)
		var hud := String(entry.call("hud_text"))
		var mov := String(entry.call("mov_line"))
		_assert("H3_hud_has_search_field", "含 'search='", _clip(hud), hud.contains("search="))
		_assert("H3_mov_has_search_field", "含 'search='", _clip(mov), mov.contains("search="))
		_assert("H3_mov_has_giveups_field", "含 'giveups='", _clip(mov), mov.contains("giveups="))
		_assert("H3_mov_has_chase_field", "含 'chase='", _clip(mov), mov.contains("chase="))
	entry.queue_free()
	await _advance_frames(3)

	var main: Node = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _advance_frames(4)
	var main_debug := _count_debug_nodes(main)
	_assert("H4_no_debug_node_in_main", "0", str(main_debug), main_debug == 0)
	main.queue_free()
	await _advance_frames(2)


func _count_debug_nodes(node: Node) -> int:
	var n := 0
	for x in _all_nodes(node):
		if x.get_script() != null:
			var sp := String((x.get_script() as Script).resource_path)
			if sp.contains("/debug/"):
				n += 1
	return n


# ---------------------------------------------------------------------------
# fixture
# ---------------------------------------------------------------------------

## 建一局：地面 + 猫层导航 + 可选猎物 / 鼠洞标记；猫**巡游关闭**（T024 测的是追击与搜索）
func _fresh_world(opts: Dictionary = {}) -> void:
	_free_world()
	await _advance_frames(2)
	_world = Node3D.new()
	_world.name = "T024World"
	root.add_child(_world)
	await _advance_frames(2)
	_region = NavigationRegion3D.new()
	_region.name = "CatRegion"
	_region.navigation_mesh = _make_navmesh()
	_region.navigation_layers = 2
	_region.set_meta("species_id", "Cat")
	_world.add_child(_region)
	_add_box(_region, "ArenaGround", Vector3(ARENA, 1.0, ARENA), Vector3(0.0, -0.5, 0.0))
	await _advance_frames(2)
	_region.bake_navigation_mesh(false)
	await _advance_frames(8)

	if opts.has("hole_at"):
		_add_hide_spot(opts["hole_at"], String(opts.get("hole_id", "HideSpot_Hole")))

	var cat_at: Vector3 = opts.get("cat_at", Vector3(0.0, CAT_Y, 0.0))
	_npc = (load(BODY) as PackedScene).instantiate() as AnimalBody
	_npc.species_config = _cat_cfg
	_npc.player_controlled = false
	_npc.position = cat_at
	_world.add_child(_npc)
	_npc.ai_enabled = true
	_ai = _npc.ai as CatAI
	if _ai != null:
		_ai.patrol_enabled = false        # 本任务不需要巡游
		if not _ai.state_changed.is_connected(_on_state_changed):
			_ai.state_changed.connect(_on_state_changed)
		if not _ai.chase_started.is_connected(_on_chase_started):
			_ai.chase_started.connect(_on_chase_started)
		if not _ai.chase_ended.is_connected(_on_chase_ended):
			_ai.chase_ended.connect(_on_chase_ended)
	else:
		push_warning("猫 NPC 没有 CatAI（cat.tres 未接 ai_script 或实现缺失）")
	await _advance_frames(SPAWN_FRAMES)
	if opts.has("prey_at"):
		_place_prey(opts["prey_at"])
		await _advance_frames(3)


func _free_world() -> void:
	if _prey != null and is_instance_valid(_prey):
		_prey.queue_free()
	_prey = null
	for n in _extras:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	_walls.clear()
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	_region = null
	_npc = null
	_ai = null
	_transitions.clear()
	_chase_events.clear()


## 放/移动猎物（鼠，**AI 关闭**，站着不动）
func _place_prey(point: Vector3) -> AnimalBody:
	var spot := Vector3(point.x, MOUSE_Y, point.z)
	if _prey == null or not is_instance_valid(_prey):
		_prey = (load(BODY) as PackedScene).instantiate() as AnimalBody
		_prey.species_config = _mouse_cfg
		_prey.player_controlled = false
		var parent: Node = _world if _world != null else root
		_prey.position = spot
		parent.add_child(_prey)
		return _prey
	_prey.global_position = spot
	_prey.velocity = Vector3.ZERO
	_prey.move_intent = Vector2.ZERO
	return _prey


## 猫的**正前方**偏 `angle_deg`、水平距离 `dist`
func _front(dist: float, angle_deg := 0.0) -> Vector3:
	var basis := _npc.global_transform.basis if _npc != null and is_instance_valid(_npc) else Basis.IDENTITY
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
	var right := basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 1e-8 else Vector3.RIGHT
	var a := deg_to_rad(angle_deg)
	var dir := (fwd * cos(a) + right * sin(a)).normalized()
	var base := _npc.global_position if _npc != null and is_instance_valid(_npc) else Vector3.ZERO
	return base + dir * dist


func _add_box(parent: Node, id: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = id
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


func _add_hide_spot(pos: Vector3, id: String) -> Marker3D:
	var m := Marker3D.new()
	m.name = id
	m.position = pos
	m.set_meta("species", "Mouse")
	m.set_meta("radius", HOLE_RADIUS)
	m.set_meta("kind", "mouse_hole")
	m.add_to_group("hide_spots")
	_world.add_child(m)
	_extras.append(m)
	return m


## 猫正前方 `dist` 处横向放 `width` × 2 × 0.2 的实心墙（挡视线）
func _add_wall_at(dist: float, angle_deg := 0.0, width := 8.0) -> StaticBody3D:
	_wall_seq += 1
	var pt := _front(dist, angle_deg)
	var wall := _add_box(_world, "Wall_%d" % _wall_seq, Vector3(width, 2.0, 0.2), Vector3(pt.x, 1.0, pt.z))
	_extras.append(wall)
	_walls.append(wall)
	return wall


## 把猎物搬到**看得见之外**（默认放到猫身后 25 m）：模拟"藏起来了"。
## 必须真的看不见 —— 否则猫会按"重新发现"（T024 C7）转追击，快照类断言就不成立了。
func _hide_prey(at := Vector3(0.0, MOUSE_Y, 25.0)) -> AnimalBody:
	return _place_prey(at)


## 拆掉本夹具里所有遮挡墙（猫要能走到快照点 / 洞口；墙挡着会被顶住 → 失败链先于超时）
func _free_walls() -> void:
	for w in _walls:
		if w != null and is_instance_valid(w):
			w.queue_free()
	_walls.clear()


func _make_navmesh() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.17
	nm.agent_height = 0.50
	nm.agent_max_climb = 0.12
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.03
	nm.cell_height = 0.03
	nm.region_min_size = 0.02
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	return nm


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _on_state_changed(from: StringName, to: StringName, reason: StringName) -> void:
	_transitions.append({"from": String(from), "to": String(to), "reason": String(reason)})


## 转移账里有没有"进入 `to` 且原因是 `reason`"的记录。
## **瞬时 `state_reason()` 会被同一帧内的后续步骤覆盖**（`lost_sight` → 立刻 `moving_to_last_seen`、
## `reacquired` → 立刻 `chasing`），所以"触发原因"要用转移账断言（T023 E 段同口径）。
func _has_transition(to: String, reason: String) -> bool:
	for t in _transitions:
		if String(t["to"]) == to and String(t["reason"]) == reason:
			return true
	return false


## 转移账的紧凑表示（断言失败时用来定位）
func _transition_reasons() -> String:
	var out: Array[String] = []
	for t in _transitions:
		out.append("%s→%s(%s)" % [t["from"], t["to"], t["reason"]])
	return ",".join(out)


func _on_chase_started(encounter_id: String) -> void:
	_chase_events.append({"kind": "start", "id": encounter_id})


func _on_chase_ended(encounter_id: String, prey_alive: bool) -> void:
	_chase_events.append({"kind": "end", "id": encounter_id, "alive": prey_alive})


func _now() -> float:
	return float(_wd.get("world_time")) if _wd != null else 0.0


func _run_seconds(seconds: float, until: Callable = Callable()) -> float:
	if _wd == null:
		return 0.0
	var t0: float = _now()
	var frames := 0
	var max_frames := int(maxf(240.0, seconds * 240.0))
	while _now() - t0 < seconds and frames < max_frames and not paused:
		if until.is_valid() and bool(until.call()):
			break
		await physics_frame
		frames += 1
	return _now() - t0


func _advance_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _clip(s: String) -> String:
	return s.replace("\n", " | ").substr(0, 90)


func _all_nodes(node: Node) -> Array[Node]:
	if node == null:
		return []
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all_nodes(c))
	return out


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	var a := float(actual)
	_assert(id, "%.4f ±%.4f" % [expected, eps], "%.4f" % a, absf(a - expected) <= eps)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
