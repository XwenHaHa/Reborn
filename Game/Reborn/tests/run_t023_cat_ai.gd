extends SceneTree
## T023 猫 NPC 巡游与发现 断言
##
## 覆盖（`Docs/Tasks/T023.md` §5；数值只读 `Docs/Parameters.md` 第 22/23/69/73 行）：
##   A 接口与配置（真源数值 / ai_script 接线 / 无物种名字面量）
##   B 巡游（patrol_points 组 / 无标记时的可达点 / 选点失败回退 WAIT / 不每帧请求路径 / 到点暂停）
##   C 发现：视觉（9 m / 60° / 遮挡 / 草丛 0.4 / 近距 0.8 豁免 / 死亡不算）
##   D 发现：听觉（12 m × loudness / 墙不挡 / 噪声只有发生位置 / 自己的噪声不触发自己）
##   E 警戒（0.4 s 上限 / 停手停脚 / 重复注入不无限延长）
##   F 接近（收敛到 0.65 m 停住 / 不扑击不伤害 / 失视不追实时坐标 / 不可达不永久卡）
##   G 与鼠对照（视野与听觉参数独立配置）
##   H 集成（真实关卡巡游 + HUD/MOV| 可查看 + 正式场景无调试节点）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t023_cat_ai.gd' --quit-after 300000
## 包内复验（只能用编辑器二进制 + --main-pack）：
##   & '<godot_console.exe>' --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
##       --script 'res://tests/run_t023_cat_ai.gd' --quit-after 300000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"
const CAT_AI := "res://scripts/ai/cat_ai.gd"
const PERCEPTION_SRC := "res://scripts/systems/perception.gd"

const EPS := 1e-3
const ARENA := 40.0
## 猫站立时胶囊中心高度（半高 0.24 + 1 cm）／鼠站立时（半高 0.09 + 1 cm）
const CAT_Y := 0.25
const MOUSE_Y := 0.10
## `Parameters.md` 第 69 行：猫 NPC 的 Alert 0.4 s / AttackRange 65 cm
const ALERT_TIME := 0.4
const ATTACK_RANGE := 0.65
## `Parameters.md` 第 22/23 行换算：猫 900 cm / 60° / 1200 cm；鼠 650 / 75° / 1000
const CAT_VISION := 9.0
const CAT_HALF_ANGLE := 60.0
const CAT_HEARING := 12.0
const MOUSE_VISION := 6.5
const MOUSE_HEARING := 10.0
const SPAWN_FRAMES := 12

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
var _mouse_ai: MouseAI = null
var _extras: Array[Node] = []
var _wall_seq := 0
## 状态跳变记录（E/F/H 段用"序列"断言，而不是"某一刻的状态"）
var _transitions: Array[Dictionary] = []


func _initialize() -> void:
	print("TEST|run_t023_cat_ai|engine=%s" % Engine.get_version_info().string)
	_cat_cfg = load(CAT) as SpeciesConfig
	_mouse_cfg = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")
	await _section_a_contract()
	await _section_b_patrol()
	await _section_c_vision()
	await _section_d_hearing()
	await _section_e_alert()
	await _section_f_approach()
	await _section_g_species_contrast()
	await _section_h_integration()
	_finish()


# ---------------------------------------------------------------------------
# A 接口与配置
# ---------------------------------------------------------------------------

func _section_a_contract() -> void:
	print("---- A 接口与配置 ----")
	var script := load(CAT_AI) as Script
	_assert("A_cat_ai_script_exists", "非 null", str(script != null), script != null)
	if script == null:
		return
	var probe: Object = script.new()
	_assert("A_cat_ai_is_animal_ai", "AnimalAI 子类", str(probe is AnimalAI), probe is AnimalAI)
	_assert("A_cat_ai_is_cat_ai", "CatAI", str(probe is CatAI), probe is CatAI)
	_assert("A_cat_tres_ai_script", CAT_AI,
		str(_cat_cfg.ai_script.resource_path) if _cat_cfg.ai_script != null else "<null>",
		_cat_cfg.ai_script != null and _cat_cfg.ai_script.resource_path == CAT_AI)
	_assert("A_mouse_tres_ai_script_unchanged", "mouse_ai.gd",
		str(_mouse_cfg.ai_script.resource_path) if _mouse_cfg.ai_script != null else "<null>",
		_mouse_cfg.ai_script != null and String(_mouse_cfg.ai_script.resource_path).ends_with("mouse_ai.gd"))

	# 猫的感知参数来自自己的配置（`Parameters.md` 第 22/23 行）
	_assert_near("A_cat_vision_range_9", CAT_VISION, _cat_cfg.vision_range, EPS)
	_assert_near("A_cat_half_angle_60", CAT_HALF_ANGLE, _cat_cfg.vision_half_angle_deg, EPS)
	_assert_near("A_cat_hearing_range_12", CAT_HEARING, _cat_cfg.hearing_range, EPS)
	_assert_near("A_mouse_vision_range_6_5", MOUSE_VISION, _mouse_cfg.vision_range, EPS)
	_assert_near("A_mouse_hearing_range_10", MOUSE_HEARING, _mouse_cfg.hearing_range, EPS)

	# 真源数值（第 69 行）
	if probe is CatAI:
		var ai := probe as CatAI
		_assert_near("A_npc_alert_time_0_4", ALERT_TIME, ai.npc_alert_time, EPS)
		_assert_near("A_attack_range_0_65", ATTACK_RANGE, ai.attack_range, EPS)
		_assert("A_patrol_radius_positive", "> 0", "%.2f" % ai.patrol_radius, ai.patrol_radius > 0.0)
		_assert("A_patrol_pause_positive", "> 0", "%.2f" % ai.patrol_pause, ai.patrol_pause > 0.0)
		_assert("A_patrol_min_move_positive", "> 0", "%.2f" % ai.patrol_min_move, ai.patrol_min_move > 0.0)
		_assert("A_patrol_retry_wait_positive", "> 0", "%.2f" % ai.patrol_retry_wait, ai.patrol_retry_wait > 0.0)
		_assert("A_approach_repath_positive", "> 0", "%.2f" % ai.approach_repath_interval,
			ai.approach_repath_interval > 0.0)
		_assert("A_patrol_enabled_default_true", "true", str(ai.patrol_enabled), ai.patrol_enabled)
	probe.free()

	# 静态检查：源码里不出现物种名字面量（包内 `.gd` 不可读 → 如实标 STATIC|NOT-APPLICABLE）
	_static_no_species_literal("A_static_no_species_literal_cat_ai", CAT_AI)
	_static_no_species_literal("A_static_no_species_literal_perception", PERCEPTION_SRC)

	# 起一局真实 fixture，读 setup 之后的 `alert_max_time` 与报告字段
	await _fresh_world({})
	if _ai == null:
		_assert("A_setup_builds_cat_ai", "非 null", "<null>", false)
		return
	_assert("A_setup_overrides_alert_max_time", "%.2f" % ALERT_TIME, "%.4f" % _ai.alert_max_time,
		absf(_ai.alert_max_time - ALERT_TIME) <= EPS)
	_assert("A_nav_layer_from_metadata", "2", "%d(%s)" % [_ai.nav_layer(), _ai.ai_report().get("nav_layer_source", "?")],
		_ai.nav_layer() == 2)
	var rep := _ai.ai_report()
	for key in ["patrol_index", "patrol_target", "patrol_reached", "detect_count", "approach_count",
			"lost_sight", "approach_distance", "patrol_enabled"]:
		_assert("A_report_has_%s" % key, "存在", str(rep.has(key)), rep.has(key))
	_assert("A_patrol_ids_empty_without_markers", "0", str(_ai.patrol_ids().size()), _ai.patrol_ids().is_empty())


func _static_no_species_literal(id: String, path: String) -> void:
	var src := _read_source(path)
	if src.is_empty():
		print("STATIC|NOT-APPLICABLE|%s（包内 .gd 不可读，T013 口径）" % path)
		return
	_assert(id, "不含 \"Cat\" 字面量", "含" if src.contains("\"Cat\"") else "不含", not src.contains("\"Cat\""))


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
# B 巡游
# ---------------------------------------------------------------------------

func _section_b_patrol() -> void:
	print("---- B 巡游 ----")
	var p0 := Vector3(0.0, 0.0, -5.0)
	var p1 := Vector3(5.0, 0.0, -5.0)
	await _fresh_world({"points": [p0, p1]})
	if _ai == null:
		_assert("B_patrol_has_ai", "非 null", "<null>", false)
		return
	var ids := _ai.patrol_ids()
	_assert("B_patrol_ids_from_group", "[\"Patrol00\", \"Patrol01\"]", str(ids),
		ids.size() == 2 and ids[0] == "Patrol00" and ids[1] == "Patrol01")
	_assert("B_patrol_ids_deterministic", str(ids), str(_ai.patrol_ids()), _ai.patrol_ids() == ids)

	var waited := await _run_seconds(1.0, func() -> bool: return _ai.has_destination())
	_assert("B_destination_within_1s", "true（%.2f s）" % waited, str(_ai.has_destination()), _ai.has_destination())
	_assert("B_first_target_id", "Patrol00", _ai.patrol_target_id(), _ai.patrol_target_id() == "Patrol00")
	_assert("B_destination_matches_marker", "≤ 0.40 m",
		"%.3f m" % _ai.destination().distance_to(p0), _ai.destination().distance_to(p0) <= 0.40)

	var arrived := await _run_seconds(14.0, func() -> bool: return _ai.patrol_reached_count() >= 1)
	_assert("B_reached_first_point", "1（%.2f s）" % arrived, str(_ai.patrol_reached_count()),
		_ai.patrol_reached_count() >= 1)
	_assert("B_arrive_distance", "≤ 0.50 m", "%.3f m" % _npc.global_position.distance_to(p0),
		_npc.global_position.distance_to(p0) <= 0.50)
	_assert("B_state_explore_after_arrival", "explore", str(_ai.state_id()), _ai.state_id() == &"explore")
	_assert("B_reason_patrol_reached", "patrol_reached", str(_ai.state_reason()),
		_ai.state_reason() == &"patrol_reached")

	# 到点后暂停：先等减速停下（1.8 m/s → 0，accel 10，约 0.16 m），再量 0.5 s 的静止
	await _run_seconds(0.35)
	var pause_start := _npc.global_position
	await _run_seconds(0.5)
	_assert("B_pause_holds", "≤ 0.05 m", "%.3f m" % pause_start.distance_to(_npc.global_position),
		pause_start.distance_to(_npc.global_position) <= 0.05)

	# 暂停结束后继续去第二个点
	var moved_on := await _run_seconds(6.0, func() -> bool: return _ai.patrol_index() == 1)
	_assert("B_switches_to_second", "index=1（%.2f s）" % moved_on, str(_ai.patrol_index()), _ai.patrol_index() == 1)
	var second_ok := await _run_seconds(4.0, func() -> bool: return _ai.patrol_target_id() == "Patrol01")
	_assert("B_second_target_id", "Patrol01（%.2f s）" % second_ok, _ai.patrol_target_id(),
		_ai.patrol_target_id() == "Patrol01")
	var sets_a := int(_ai.ai_report()["destination_sets"])
	var pos_a := _npc.global_position
	var sets_snapshot := sets_a
	await _run_seconds(1.0, func() -> bool: return _npc.global_position.distance_to(pos_a) > 1.0)
	var sets_b := int(_ai.ai_report()["destination_sets"])
	_assert("B_no_per_frame_repath", "增量 ≤ 2", "增量 %d" % (sets_b - sets_snapshot), sets_b - sets_snapshot <= 2)
	_assert("B_reason_patrol_moving", "patrol_moving", str(_ai.state_reason()), _ai.state_reason() == &"patrol_moving")
	var second_arrive := await _run_seconds(16.0, func() -> bool: return _ai.patrol_reached_count() >= 2)
	_assert("B_reached_second_point", "2（%.2f s）" % second_arrive, str(_ai.patrol_reached_count()),
		_ai.patrol_reached_count() >= 2)

	# 无标记 → 环上可达点（不能"站着不动"）
	await _fresh_world({})
	var ring_start := _npc.global_position
	var ring_moved := await _run_seconds(8.0, func() -> bool: return _npc.global_position.distance_to(ring_start) > 0.5)
	_assert("B_ring_patrol_moves", "> 0.5 m（%.2f s）" % ring_moved,
		"%.3f m" % ring_start.distance_to(_npc.global_position),
		ring_start.distance_to(_npc.global_position) > 0.5)
	_assert("B_ring_target_id_prefix", "ring_", _ai.patrol_target_id(), _ai.patrol_target_id().begins_with("ring_"))
	_assert("B_ring_target_reachable", "true", str(_ai.reachable(_ai.destination())), _ai.reachable(_ai.destination()))
	# 环上候选是**相对当前位置的方向索引**（`ring_0` 会重复出现），判据用"持续在巡游"而不是"换 id"
	var ring_pos := _npc.global_position
	var ring_again := await _run_seconds(6.0, func() -> bool: return _npc.global_position.distance_to(ring_pos) > 1.0)
	_assert("B_ring_keeps_patrolling", "再走 > 1 m（%.2f s）" % ring_again,
		"%.3f m" % ring_pos.distance_to(_npc.global_position),
		ring_pos.distance_to(_npc.global_position) > 1.0)

	# 标记都在没有导航面的地方 → 记录失败 + 进 WAIT + 自己恢复（不永久阻塞）
	await _fresh_world({"points": [Vector3(0.0, 0.0, -26.0), Vector3(3.0, 0.0, -26.0)]})
	var fail_seen := await _run_seconds(6.0, func() -> bool:
		return int(_ai.ai_report()["path_failures"]) >= 1 or _ai.state_id() == &"wait")
	_assert("B_unreachable_marks_failure", "≥ 1 次失败或进 wait（%.2f s）" % fail_seen,
		"failures=%d state=%s" % [int(_ai.ai_report()["path_failures"]), str(_ai.state_id())],
		int(_ai.ai_report()["path_failures"]) >= 1 or _ai.state_id() == &"wait")
	_assert("B_unreachable_no_fake_reach", "0", str(_ai.patrol_reached_count()), _ai.patrol_reached_count() == 0)
	var wait_seen := await _run_seconds(4.0, func() -> bool: return _ai.state_id() == &"wait")
	_assert("B_unreachable_enters_wait", "wait（%.2f s）" % wait_seen, str(_ai.state_id()), _ai.state_id() == &"wait")
	var recovered := await _run_seconds(4.0, func() -> bool: return _ai.state_id() == &"explore")
	_assert("B_unreachable_recovers", "回 explore（%.2f s）" % recovered, str(_ai.state_id()),
		_ai.state_id() == &"explore")
	_assert("B_world_time_advancing", "true", str(bool(_wd.get("time_advancing")) if _wd != null else "?"),
		_wd != null and bool(_wd.get("time_advancing")))

	# 关掉巡游：站住、无目的地、原因可查看
	await _fresh_world({"patrol": false})
	await _run_seconds(0.5)      # 等减速停下再量
	var off_pos := _npc.global_position
	await _run_seconds(1.0)
	_assert("B_patrol_off_no_destination", "false", str(_ai.has_destination()), not _ai.has_destination())
	_assert("B_patrol_off_reason", "patrol_off", str(_ai.state_reason()), _ai.state_reason() == &"patrol_off")
	_assert("B_patrol_off_move_intent_zero", "(0, 0)", str(_npc.move_intent), _npc.move_intent.length() < 0.01)
	_assert("B_patrol_off_no_move", "≤ 0.05 m", "%.4f m" % off_pos.distance_to(_npc.global_position),
		off_pos.distance_to(_npc.global_position) <= 0.05)


# ---------------------------------------------------------------------------
# C 发现：视觉
# ---------------------------------------------------------------------------

func _section_c_vision() -> void:
	print("---- C 发现：视觉（9 m / 60° / 遮挡 / 草丛 / 近距豁免）----")
	# **纯几何段：关掉 AI** —— 否则猫会先警戒再走向猎物，几何与被测位置都会漂；
	# 感知是**身体组件**（与 `ai_enabled` 无关），照常每物理帧 tick
	await _fresh_world({"patrol": false})
	if _ai == null:
		return
	_npc.ai_enabled = false
	await _advance_frames(3)
	var p := _npc.perception

	await _assert_see("C_front_3m_seen", 3.0, 0.0, true)
	await _assert_see("C_front_7m_seen", 7.0, 0.0, true)
	await _assert_see("C_front_8_9m_seen", 8.9, 0.0, true)
	await _assert_see("C_front_9_3m_not_seen", 9.3, 0.0, false)
	await _assert_see("C_angle_55_seen", 3.0, 55.0, true)
	await _assert_see("C_angle_61_not_seen", 3.0, 61.0, false)
	await _assert_see("C_angle_75_not_seen", 3.0, 75.0, false)
	await _assert_see("C_behind_not_seen", 3.0, 180.0, false)

	# `tick()` 与点判定同一条路径；跳变计数只在"看不见 → 看见"时 +1（**不需要 AI**）
	var sight_before := p.sight_count()
	_place_prey(_point_in_front(3.0))
	await _advance_frames(3)
	_assert("C_tick_sees_prey", "true", str(p.is_threat_visible()), p.is_threat_visible())
	_assert("C_threat_id_recorded", "非空", p.threat_id(), not p.threat_id().is_empty())
	_assert("C_sight_count_once", "%d（+1）" % (sight_before + 1), str(p.sight_count()),
		p.sight_count() == sight_before + 1)

	# 遮挡：`world_static` 墙
	var wall := _add_wall_at(1.5)
	await _advance_frames(3)
	await _assert_see("C_occluded_by_wall", 3.0, 0.0, false)
	wall.queue_free()
	await _advance_frames(3)
	await _assert_see("C_seen_after_wall_removed", 3.0, 0.0, true)


	# 近距豁免：≤ 0.80 m 忽略遮挡与草丛，但仍受视锥限制
	var near_wall := _add_wall_at(0.35)
	await _advance_frames(3)
	await _assert_see("C_near_exempt_0_7m_seen", 0.70, 0.0, true)
	await _assert_see("C_near_beyond_1_2m_not_seen", 1.20, 0.0, false)
	await _assert_see("C_near_exempt_still_fov_limited", 0.70, 90.0, false)
	near_wall.queue_free()
	await _advance_frames(3)

	# 草丛系数 0.4 → 发现距离 9 × 0.4 = 3.6 m（`Parameters.md` 第 73 行）
	var cover := _add_cover(_point_in_front(4.0), Vector3(2.0, 2.0, 6.0), 0.4)
	await _advance_frames(3)
	_assert_near("C_cover_factor_inside", 0.4, p.cover_factor_at(_point_in_front(4.0)), EPS)
	_assert_near("C_cover_factor_outside", 1.0, p.cover_factor_at(_point_in_front(4.0) + Vector3(8.0, 0.0, 0.0)), EPS)
	await _assert_see("C_cover_5m_not_seen", 5.0, 0.0, false)
	await _assert_see("C_cover_3m_seen", 3.0, 0.0, true)
	cover.queue_free()
	await _advance_frames(3)
	await _assert_see("C_outside_cover_5m_seen", 5.0, 0.0, true)

	# 死掉的猎物不再被"发现"（存活过滤在 `tick()` 的候选里，**不在点判定里**）
	_place_prey(_point_in_front(3.0))
	await _advance_frames(3)
	_assert("C_prey_seen_before_death", "true", str(p.is_threat_visible()), p.is_threat_visible())
	_prey.survival.apply_damage(9999.0, &"test")
	await _advance_frames(4)
	_assert("C_dead_prey_not_seen", "false", str(p.is_threat_visible()), not p.is_threat_visible())

	# AI 反应（**换一局、打开 AI**）：看见 → 进 `ALERT`（reason `saw_prey`）并记住水平距离
	await _fresh_world({"patrol": false})
	await _advance_frames(3)
	_place_prey(_point_in_front(3.0))
	await _advance_frames(3)
	_assert("C_state_alert_on_sight", "alert", str(_ai.state_id()), _ai.state_id() == &"alert")
	_assert("C_reason_saw_prey", "saw_prey", str(_ai.state_reason()), _ai.state_reason() == &"saw_prey")
	_assert("C_detect_count_1", "≥ 1", str(_ai.detect_count()), _ai.detect_count() >= 1)
	_assert("C_approach_distance_finite", "≈ 3.0 m（水平）", "%.3f m" % _ai.approach_distance(),
		absf(_ai.approach_distance() - 3.0) <= 0.5)

	# 远离视野外不会误警戒
	await _fresh_world({"patrol": false})
	await _advance_frames(3)
	_place_prey(_point_in_front(9.3))
	await _advance_frames(6)
	_assert("C_no_alert_when_out_of_range", "非 alert", str(_ai.state_id()), _ai.state_id() != &"alert")


func _assert_see(id: String, dist: float, angle: float, expected: bool) -> void:
	var pt := _point_in_front(dist, angle)
	var ok := await _see_at(pt)
	_assert(id, str(expected), "%.2f m / %.1f° → %s" % [dist, angle, str(ok)], ok == expected)


func _see_at(point: Vector3) -> bool:
	_place_prey(point)
	await _advance_frames(1)
	if _npc == null or _prey == null or _npc.perception == null:
		return false
	return _npc.perception.can_see_point(_prey.global_position, _prey.eye_position())


# ---------------------------------------------------------------------------
# D 发现：听觉
# ---------------------------------------------------------------------------

func _section_d_hearing() -> void:
	print("---- D 发现：听觉（HearingRange × Loudness）----")
	await _fresh_world({})
	if _ai == null:
		return
	_ai.patrol_enabled = false
	await _advance_frames(3)
	var p := _npc.perception
	var before := p.heard_count()

	var h1 := p.receive_noise("Mouse#probe", _point_in_front(11.0), 1.0, _now())
	_assert("D_run_11m_heard", "true（11 ≤ 12）", str(h1), h1)
	var h2 := p.receive_noise("Mouse#probe", _point_in_front(12.5), 1.0, _now())
	_assert("D_run_12_5m_not_heard", "false（12.5 > 12）", str(h2), not h2)
	var h3 := p.receive_noise("Mouse#probe", _point_in_front(5.5), 0.5, _now())
	_assert("D_walk_5_5m_heard", "true（5.5 ≤ 6）", str(h3), h3)
	var h4 := p.receive_noise("Mouse#probe", _point_in_front(6.5), 0.5, _now())
	_assert("D_walk_6_5m_not_heard", "false（6.5 > 6）", str(h4), not h4)
	var h5 := p.receive_noise("Mouse#probe", _point_in_front(2.0), 0.2, _now())
	_assert("D_crouch_2m_heard", "true（2.0 ≤ 2.4）", str(h5), h5)
	var h6 := p.receive_noise("Mouse#probe", _point_in_front(3.0), 0.2, _now())
	_assert("D_crouch_3m_not_heard", "false（3.0 > 2.4）", str(h6), not h6)
	_assert("D_count_only_valid", "%d" % (before + 3), str(p.heard_count()), p.heard_count() == before + 3)
	_assert_near("D_snapshot_loudness", 0.2, p.last_noise_loudness(), EPS)

	# 自己的噪声不触发自己
	var h7 := p.receive_noise(_npc.source_id(), _point_in_front(1.0), 1.0, _now())
	_assert("D_own_noise_ignored", "false", str(h7), not h7)
	_assert("D_own_noise_not_counted", str(before + 3), str(p.heard_count()), p.heard_count() == before + 3)

	# 墙不挡听觉；草丛不减小听觉
	var wall := _add_wall_at(1.5)
	await _advance_frames(2)
	var h8 := p.receive_noise("Mouse#probe", _point_in_front(11.0), 1.0, _now())
	_assert("D_wall_does_not_block_hearing", "true", str(h8), h8)
	var cover := _add_cover(_point_in_front(5.5), Vector3(2.0, 2.0, 6.0), 0.4)
	await _advance_frames(2)
	var h9 := p.receive_noise("Mouse#probe", _point_in_front(5.5), 0.5, _now())
	_assert("D_cover_does_not_reduce_hearing", "true（5.5 ≤ 6）", str(h9), h9)
	wall.queue_free()
	cover.queue_free()
	await _advance_frames(3)

	# AI 层：噪声 → 警戒到**发生位置**
	await _fresh_world({})
	_ai.patrol_enabled = false
	await _advance_frames(3)
	var origin := _point_in_front(8.0)
	var heard := _npc.perception.receive_noise("Mouse#probe", origin, 1.0, _now())
	_assert("D_ai_saw_noise_event", "true", str(heard), heard)
	var alerted := await _run_seconds(0.5, func() -> bool: return _ai.state_id() == &"alert")
	_assert("D_ai_alerts_on_noise", "alert（%.2f s）" % alerted, str(_ai.state_id()), _ai.state_id() == &"alert")
	_assert("D_reason_heard_noise", "heard_noise", str(_ai.state_reason()), _ai.state_reason() == &"heard_noise")
	_assert("D_alert_position_is_noise_origin", "≤ 0.10 m",
		"%.3f m" % _ai.alert_position().distance_to(origin), _ai.alert_position().distance_to(origin) <= 0.10)
	_assert("D_snapshot_position_is_origin", "≤ 0.10 m",
		"%.3f m" % _npc.perception.last_noise_position().distance_to(origin),
		_npc.perception.last_noise_position().distance_to(origin) <= 0.10)

	# 只有发生位置：时间过去、位置不变（不跟踪声源）
	var alert_pos := _ai.alert_position()
	var noise_pos := _npc.perception.last_noise_position()
	await _run_seconds(0.7)
	_assert("D_noise_position_not_tracked", "不变（≤ 0.01 m）",
		"%.4f m" % noise_pos.distance_to(_npc.perception.last_noise_position()),
		noise_pos.distance_to(_npc.perception.last_noise_position()) <= 0.01)
	_assert("D_alert_position_unchanged", "≤ 0.01 m", "%.4f m" % alert_pos.distance_to(_ai.alert_position()),
		alert_pos.distance_to(_ai.alert_position()) <= 0.01)

	# 超出听觉范围 → 不警戒
	await _fresh_world({})
	_ai.patrol_enabled = false
	await _advance_frames(3)
	var far := _npc.perception.receive_noise("Mouse#probe", _point_in_front(15.0), 1.0, _now())
	_assert("D_far_noise_not_heard", "false", str(far), not far)
	await _run_seconds(0.4)
	_assert("D_no_alert_for_far_noise", "非 alert", str(_ai.state_id()), _ai.state_id() != &"alert")


# ---------------------------------------------------------------------------
# E 警戒
# ---------------------------------------------------------------------------

func _section_e_alert() -> void:
	print("---- E 警戒（0.4 s / 停手停脚 / 重复注入不无限延长）----")
	await _fresh_world({"patrol": false})
	if _ai == null:
		return
	await _advance_frames(3)
	await _run_seconds(0.5)      # 先等减速停下（否则警戒期间还会滑行 ~0.07 m）
	var t0 := _now()
	var pos0 := _npc.global_position
	_ai.alert_for(_point_in_front(5.0), &"threat")
	_assert("E_state_alert", "alert", str(_ai.state_id()), _ai.state_id() == &"alert")
	_assert("E_has_alert", "true", str(_ai.has_alert()), _ai.has_alert())
	await _run_seconds(0.2)
	_assert("E_still_alert_at_0_2", "0.4 窗口内仍是 alert（%.3f s）" % (_now() - t0), str(_ai.state_id()),
		_ai.state_id() == &"alert")
	_assert("E_move_intent_zero_during_alert", "(0, 0)", str(_npc.move_intent), _npc.move_intent.length() < 0.01)
	await _run_seconds(0.30)
	_assert("E_left_alert_by_0_45", "0.45 s 后已离开 alert（%.3f s）" % (_now() - t0), str(_ai.state_id()),
		_ai.state_id() != &"alert")
	_assert("E_no_displacement_during_alert", "≤ 0.05 m", "%.4f m" % pos0.distance_to(_npc.global_position),
		pos0.distance_to(_npc.global_position) <= 0.05)
	_assert("E_back_to_explore", "explore", str(_ai.state_id()), _ai.state_id() == &"explore")
	_assert("E_reason_alert_done_or_patrol", "alert_done / patrol_off", str(_ai.state_reason()),
		_ai.state_reason() == &"alert_done" or _ai.state_reason() == &"patrol_off" or _ai.state_reason() == &"lost_sight")

	# 重复注入：每次注入都会续期，但**有上限**（不是无限延长）
	var t1 := _now()
	_ai.alert_for(_point_in_front(5.0), &"threat")
	await _run_seconds(0.2)
	_ai.alert_for(_point_in_front(5.0), &"threat")
	await _run_seconds(0.15)
	_assert("E_repeat_still_alert_at_0_35", "true（%.3f s）" % (_now() - t1), str(_ai.state_id()),
		_ai.state_id() == &"alert")
	var left := await _run_seconds(0.5, func() -> bool: return _ai.state_id() != &"alert")
	_assert("E_repeat_left_by_0_65", "true（%.3f s）" % (_now() - t1), str(_ai.state_id()), _ai.state_id() != &"alert")
	_assert("E_repeat_bounded", "≤ 0.65 s", "%.3f s" % (_now() - t1), (_now() - t1) <= 0.75)

	# 看得见时警戒结束 → 接近
	await _fresh_world({})
	_ai.patrol_enabled = false
	await _advance_frames(3)
	_place_prey(_point_in_front(4.0))
	var approached := await _run_seconds(2.5, func() -> bool: return _ai.state_id() == &"approach")
	_assert("E_alert_to_approach_when_visible", "approach（%.2f s）" % approached, str(_ai.state_id()),
		_ai.state_id() == &"approach")
	var approach_transition := false
	for t in _transitions:
		if String(t["to"]) == "approach" and String(t["reason"]) == "alert_done":
			approach_transition = true
	_assert("E_reason_alert_done", "存在 alert→approach(alert_done)", str(_transitions), approach_transition)
	_assert("E_approach_count_1", "≥ 1", str(_ai.approach_count()), _ai.approach_count() >= 1)

	# 看不见时警戒结束 → 回探索，且记一次"失视"
	await _fresh_world({})
	_ai.patrol_enabled = false
	await _advance_frames(3)
	_place_prey(_point_in_front(4.0))
	await _run_seconds(0.4)
	var seen_once := _ai.detect_count() >= 1 or _npc.perception.has_seen()
	_assert("E_saw_prey_first", "true", str(seen_once), seen_once)
	_free_prey()
	await _run_seconds(0.6)
	_assert("E_lost_sight_returns_explore", "explore", str(_ai.state_id()), _ai.state_id() == &"explore")
	_assert("E_lost_sight_counted", "≥ 1", str(_ai.lost_sight_count()), _ai.lost_sight_count() >= 1)


# ---------------------------------------------------------------------------
# F 接近
# ---------------------------------------------------------------------------

func _section_f_approach() -> void:
	print("---- F 接近（收敛到 0.65 m / 不扑击 / 失视不追实时坐标 / 不可达不永久卡）----")
	await _fresh_world({})
	if _ai == null:
		return
	_ai.patrol_enabled = false
	await _advance_frames(3)
	_place_prey(_point_in_front(4.0))
	await _advance_frames(3)

	var closes := await _run_seconds(15.0, func() -> bool: return _ai.approach_distance() <= ATTACK_RANGE)
	_assert("F_entered_approach", "≥ 1 次", str(_ai.approach_count()), _ai.approach_count() >= 1)
	_assert("F_closed_to_attack_range", "≤ %.2f m（%.2f s）" % [ATTACK_RANGE, closes],
		"%.3f m" % _ai.approach_distance(), _ai.approach_distance() <= ATTACK_RANGE)
	_assert("F_state_approach", "approach", str(_ai.state_id()), _ai.state_id() == &"approach")
	_assert("F_reason_in_range", "in_range", str(_ai.state_reason()), _ai.state_reason() == &"in_range")
	_assert("F_path_points_positive", "> 0 或已到终点", str(int(_ai.ai_report()["path_points"])),
		int(_ai.ai_report()["path_points"]) >= 0)

	var hold_pos := _npc.global_position
	var sets_hold := int(_ai.ai_report()["destination_sets"])
	await _run_seconds(1.0)
	_assert("F_stops_after_in_range", "≤ 0.15 m", "%.4f m" % hold_pos.distance_to(_npc.global_position),
		hold_pos.distance_to(_npc.global_position) <= 0.15)
	_assert("F_repath_throttled", "增量 ≤ 2", "增量 %d" % (int(_ai.ai_report()["destination_sets"]) - sets_hold),
		int(_ai.ai_report()["destination_sets"]) - sets_hold <= 2)

	# 不扑击、不攻击、不扣血、不捕获
	_assert("F_no_pounce", "0", str(_npc.pounce_count), _npc.pounce_count == 0)
	_assert("F_not_pouncing", "非 pouncing", _npc.action_state_name(), _npc.action_state_name() != "pouncing")
	_assert("F_no_captures", "0", str(_npc.captures), _npc.captures == 0)
	_assert("F_prey_health_unchanged", "100.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 100.0) <= 0.01)
	_assert("F_prey_not_captured", "false", str(_prey.captured), not _prey.captured)
	_assert("F_no_world_capture", "0", str(int(_wd.get("capture_count")) if _wd != null else -1),
		_wd != null and int(_wd.get("capture_count")) == 0)

	# 猎物在视野内换位置 → 重新接近
	var moved_point := _point_in_front(2.0, 0.0) + Vector3(2.5, 0.0, 0.0)
	_place_prey(Vector3(moved_point.x, MOUSE_Y, moved_point.z))
	await _advance_frames(3)
	var reclosed := await _run_seconds(14.0, func() -> bool: return _ai.approach_distance() <= ATTACK_RANGE)
	_assert("F_recloses_after_prey_moves", "≤ %.2f m（%.2f s）" % [ATTACK_RANGE, reclosed],
		"%.3f m" % _ai.approach_distance(), _ai.approach_distance() <= ATTACK_RANGE)

	# 中途遮挡 → 失视警戒 → 回探索；**不朝实时坐标导航**
	# 注意：≤ 0.80 m 时近距豁免会忽略遮挡，所以先把猎物放回 3.5 m、墙放在 1.5 m 处（> 0.8 m）
	# 先把猎物放到 4 m 外、等猫接近到 ≤ 2.8 m，再在**猫与猎物连线的 40% 处**放 8 m 宽的墙
	# （0.4 × 2.8 = 1.12 m > 近距豁免 0.8 m；8 m 宽避免猫沿墙边滑出去绕开）
	_place_prey(_point_in_front(4.0))
	var occlusion_setup := await _run_seconds(6.0, func() -> bool: return _ai.approach_distance() <= 2.8)
	_assert("F_occlusion_setup", "≤ 2.8 m（%.2f s）" % occlusion_setup, "%.3f m" % _ai.approach_distance(),
		_ai.approach_distance() <= 2.8)
	var occluder := _add_wall_between(_npc.global_position, _prey.global_position, 0.4, 8.0)
	await _advance_frames(4)
	var lost := await _run_seconds(1.0, func() -> bool: return _ai.state_reason() == &"lost_sight")
	_assert("F_lost_sight_alerts", "lost_sight（%.2f s）" % lost, str(_ai.state_reason()),
		_ai.state_reason() == &"lost_sight")
	_assert("F_lost_sight_state_alert_or_explore", "alert / explore", str(_ai.state_id()),
		_ai.state_id() == &"alert" or _ai.state_id() == &"explore")
	# 失视**之后**再取快照：接着把猎物搬走 3 m，看目的地与 `last_seen` 会不会跟着实时坐标走
	var last_seen_at_loss := _npc.perception.last_seen_position()
	_prey.global_position = _prey.global_position + Vector3(0.0, 0.0, -3.0)
	await _advance_frames(6)
	var live_after := _prey.global_position
	var no_live_tracking := (not _ai.has_destination()) or _ai.destination().distance_to(live_after) > 0.5
	_assert("F_no_live_tracking", "无目的地或不指向猎物实时位置",
		"dest=%s live=%s has=%s" % [str(_ai.destination()), str(live_after), str(_ai.has_destination())],
		no_live_tracking)
	_assert("F_last_seen_unchanged", "≤ 0.01 m（不跟随）",
		"%.4f m" % last_seen_at_loss.distance_to(_npc.perception.last_seen_position()),
		last_seen_at_loss.distance_to(_npc.perception.last_seen_position()) <= 0.01)
	var back := await _run_seconds(1.5, func() -> bool: return _ai.state_id() == &"explore")
	_assert("F_back_to_explore_after_loss", "explore（%.2f s）" % back, str(_ai.state_id()),
		_ai.state_id() == &"explore")
	_assert("F_lost_sight_counted", "≥ 1", str(_ai.lost_sight_count()), _ai.lost_sight_count() >= 1)
	occluder.queue_free()
	await _advance_frames(3)

	# 可见但不可达（两块平台中间有沟）→ 记录失败 / 不永久卡
	await _fresh_world({"split_platform": true, "patrol": false})
	_ai.patrol_enabled = false
	await _advance_frames(3)
	_place_prey(Vector3(0.0, MOUSE_Y, -6.5))
	await _advance_frames(6)
	_assert("F_unreachable_prey_visible", "true", str(_npc.perception.is_threat_visible()),
		_npc.perception.is_threat_visible())
	var stuck := await _run_seconds(8.0, func() -> bool:
		return int(_ai.ai_report()["path_failures"]) >= 1 or _ai.state_id() == &"wait")
	_assert("F_unreachable_no_permanent_block", "≥ 1 失败或进 wait（%.2f s）" % stuck,
		"failures=%d state=%s" % [int(_ai.ai_report()["path_failures"]), str(_ai.state_id())],
		int(_ai.ai_report()["path_failures"]) >= 1 or _ai.state_id() == &"wait")
	_assert("F_unreachable_no_fake_in_range", "reason != in_range", str(_ai.state_reason()),
		_ai.state_reason() != &"in_range")
	# 有界 + 可诊断：失败原因记在 `last_path_status` 里（且上面已断言不假装到位）
	_assert("F_unreachable_reason_recorded", "非空（可诊断）", str(_ai.ai_report()["last_path_status"]),
		not str(_ai.ai_report()["last_path_status"]).is_empty())


# ---------------------------------------------------------------------------
# G 与鼠对照（参数独立配置）
# ---------------------------------------------------------------------------

func _section_g_species_contrast() -> void:
	print("---- G 与鼠对照（视野 / 听觉各自配置）----")
	await _fresh_world({"with_mouse": true, "mouse_at": Vector3(0.0, MOUSE_Y, -7.0), "patrol": false})
	if _ai == null or _mouse_npc == null:
		_assert("G_both_npcs_built", "猫与鼠都有", "cat=%s mouse=%s" % [str(_ai != null), str(_mouse_npc != null)], false)
		return
	if _mouse_ai != null:
		_mouse_ai.set("nav_layer_override", 2)
	await _advance_frames(6)

	var cat_sees := _npc.perception.is_threat_visible()
	var live_ai := _npc.ai as CatAI
	_assert("G_cat_sees_mouse_at_7m", "true（7 ≤ 9）",
		"same_ai=%s body_patrol=%s target=%s dest=%s seen=%s count=%d state=%s reason=%s intent=%s vel=%s cat=%s mouse=%s" % [
		str(live_ai == _ai), str(live_ai.patrol_enabled), live_ai.patrol_target_id(), str(live_ai.destination()),
		str(cat_sees), _npc.perception.visible_threat_count(), str(live_ai.state_id()), str(live_ai.state_reason()),
		str(_npc.move_intent), str(_npc.velocity), str(_npc.global_position), str(_mouse_npc.global_position)], cat_sees)
	var mouse_sees := _mouse_npc.perception.is_threat_visible()
	_assert("G_mouse_not_see_cat_at_7m", "false（7 > 6.5）", str(mouse_sees), not mouse_sees)

	var noise_point := _npc.global_position + Vector3(0.0, 0.0, -11.0)
	var cat_hears := _npc.perception.receive_noise("Mouse#probe", noise_point, 1.0, _now())
	var mouse_hears := _mouse_npc.perception.receive_noise("Cat#probe", _mouse_npc.global_position + Vector3(0.0, 0.0, -11.0),
		1.0, _now())
	_assert("G_cat_hears_11m", "true（11 ≤ 12）", str(cat_hears), cat_hears)
	_assert("G_mouse_not_hear_11m", "false（11 > 10）", str(mouse_hears), not mouse_hears)

	await _advance_frames(6)
	_assert("G_cat_reacts", "alert / approach", str(_ai.state_id()),
		_ai.state_id() == &"alert" or _ai.state_id() == &"approach")
	_assert("G_mouse_not_alert_or_flee", "非 alert / flee",
		str(_mouse_npc.ai.state_id()) if _mouse_npc.ai != null else "<no ai>",
		_mouse_npc.ai == null or (_mouse_npc.ai.state_id() != &"alert" and _mouse_npc.ai.state_id() != &"flee"))
	_assert("G_cat_perception_config_is_cat", "%.1f m" % CAT_VISION, "%.1f m" % _npc.species_config.vision_range,
		absf(_npc.species_config.vision_range - CAT_VISION) <= EPS)
	_assert("G_mouse_perception_config_is_mouse", "%.1f m" % MOUSE_VISION,
		"%.1f m" % _mouse_npc.species_config.vision_range,
		absf(_mouse_npc.species_config.vision_range - MOUSE_VISION) <= EPS)
	_assert("G_reports_independent", "各自独立", "cat=%s mouse=%s" % [str(_ai.state_id()),
		str(_mouse_npc.ai.state_id()) if _mouse_npc.ai != null else "-"], true)


# ---------------------------------------------------------------------------
# H 集成与可查看
# ---------------------------------------------------------------------------

func _section_h_integration() -> void:
	print("---- H 集成（真实关卡 / HUD 与 MOV| 可查看 / 无调试节点）----")
	_free_world()
	await _advance_frames(3)

	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	_assert("H_level_loads", "Node3D", str(level != null), level != null)
	if level == null:
		return
	root.add_child(level)
	await _advance_frames(6)

	var cat_spawn := Vector3.ZERO
	var found_spawn := false
	for n in _all_nodes(level):
		if n.is_in_group("spawn_points") and n.has_meta("species") and String(n.get_meta("species")) == "Cat":
			cat_spawn = (n as Node3D).global_position
			found_spawn = true
	_assert("H_cat_spawn_marker", "true", str(found_spawn), found_spawn)

	var cat := (load(BODY) as PackedScene).instantiate() as AnimalBody
	cat.species_config = _cat_cfg
	cat.player_controlled = false
	cat.position = cat_spawn
	level.add_child(cat)
	cat.ai_enabled = true
	await _advance_frames(SPAWN_FRAMES)
	_assert("H_cat_on_floor", "true", str(cat.is_on_floor()), cat.is_on_floor())
	_assert("H_cat_has_cat_ai", "CatAI", str(cat.ai), cat.ai is CatAI)
	_assert("H_cat_nav_layer_2", "2", str(int(cat.ai.ai_report()["nav_layer"])), int(cat.ai.ai_report()["nav_layer"]) == 2)
	_assert("H_cat_nav_layer_source_metadata", "metadata", str(cat.ai.ai_report()["nav_layer_source"]),
		str(cat.ai.ai_report()["nav_layer_source"]) == "metadata")

	# 运行时把两个巡逻点放进关卡（T027 才布置正式点位）
	var m1 := Marker3D.new()
	m1.name = "PatrolH1"
	m1.position = cat.global_position + Vector3(4.0, 0.0, 0.0)
	m1.add_to_group("patrol_points")
	level.add_child(m1)
	var m2 := Marker3D.new()
	m2.name = "PatrolH2"
	m2.position = cat.global_position + Vector3(0.0, 0.0, -4.0)
	m2.add_to_group("patrol_points")
	level.add_child(m2)
	await _advance_frames(4)
	var cat_ai := cat.ai as CatAI
	_assert("H_patrol_ids_in_level", "2", str(cat_ai.patrol_ids().size()), cat_ai.patrol_ids().size() == 2)

	var start := cat.global_position
	var t0 := _now()
	var moved := await _run_seconds(16.0, func() -> bool:
		return cat_ai.patrol_reached_count() >= 1 or cat.global_position.distance_to(start) > 1.0)
	_assert("H_cat_patrols_in_level", "位移 > 1 m 或到点（%.2f s）" % moved,
		"%.2f m / reached=%d" % [start.distance_to(cat.global_position), cat_ai.patrol_reached_count()],
		start.distance_to(cat.global_position) > 1.0 or cat_ai.patrol_reached_count() >= 1)
	var t1 := _now()
	await _run_seconds(1.0)
	_assert("H_world_time_advances", "≥ 0.9 s", "%.2f s" % (_now() - t1), (_now() - t1) >= 0.9)

	var level_debug := _count_debug_nodes(level)
	_assert("H_no_debug_node_in_level", "0", str(level_debug), level_debug == 0)
	level.queue_free()
	cat = null
	await _advance_frames(3)

	# 调试入口：默认玩家的猫**没有** AI（正式场景不自动跑 NPC 逻辑）；打开后 HUD/MOV| 能看到 cat 的巡游字段
	var entry := (load(ENTRY) as PackedScene).instantiate() as Node3D
	root.add_child(entry)
	await _advance_frames(10)
	var player := entry.get("player") as AnimalBody
	_assert("H_debug_entry_player_exists", "非 null", str(player != null), player != null)
	if player != null:
		_assert("H_player_cat_has_no_ai_by_default", "null", str(player.ai), player.ai == null)
		player.ai_enabled = true
		await _advance_frames(12)
		_assert("H_player_cat_ai_when_enabled", "CatAI", str(player.ai), player.ai is CatAI)
		var hud := String(entry.call("hud_text"))
		var mov := String(entry.call("mov_line"))
		_assert("H_hud_has_ai_line", "含 'ai:'", _clip(hud), hud.contains("ai:"))
		_assert("H_hud_has_patrol_field", "含 'patrol='", _clip(hud), hud.contains("patrol="))
		_assert("H_mov_has_patrol_field", "含 'patrol='", _clip(mov), mov.contains("patrol="))
		_assert("H_mov_has_ai_state", "含 'ai_state='", _clip(mov), mov.contains("ai_state="))
	entry.queue_free()
	await _advance_frames(3)

	var main: Node = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _advance_frames(4)
	var main_debug := _count_debug_nodes(main)
	_assert("H_no_debug_node_in_main", "0", str(main_debug), main_debug == 0)
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

## 建一局：地面 + 猫层导航区域 + 可选巡逻标记 / 猎物 / 沟（`split_platform`）
func _fresh_world(opts: Dictionary = {}) -> void:
	_free_world()
	await _advance_frames(2)
	_world = Node3D.new()
	_world.name = "T023World"
	root.add_child(_world)
	await _advance_frames(2)

	var split := bool(opts.get("split_platform", false))
	_region = NavigationRegion3D.new()
	_region.name = "CatRegion"
	_region.navigation_mesh = _make_navmesh()
	_region.navigation_layers = 2
	_region.set_meta("species_id", "Cat")
	_world.add_child(_region)
	if split:
		# 猫这侧只到 z = -4；另一侧 z = -6..-14 不在导航面上（中间 2 m 沟）
		_add_box(_region, "CatSide", Vector3(16.0, 1.0, 8.0), Vector3(0.0, -0.5, 0.0))
	else:
		_add_box(_region, "ArenaGround", Vector3(ARENA, 1.0, ARENA), Vector3(0.0, -0.5, 0.0))
	await _advance_frames(2)
	if split:
		# 另一块平台**不挂在导航区域下** → 那里没有导航面
		_add_box(_world, "FarSide", Vector3(16.0, 1.0, 8.0), Vector3(0.0, -0.5, -10.0))

	var points: Array = opts.get("points", [])
	for i in points.size():
		_add_marker(points[i], "Patrol%02d" % i, "patrol_points")
	await _advance_frames(2)
	_region.bake_navigation_mesh(false)
	await _advance_frames(8)

	var cat_at: Vector3 = opts.get("cat_at", Vector3(0.0, CAT_Y, 0.0))
	_npc = (load(BODY) as PackedScene).instantiate() as AnimalBody
	_npc.species_config = _cat_cfg
	_npc.player_controlled = false
	_npc.position = cat_at
	_world.add_child(_npc)
	_npc.ai_enabled = true
	_ai = _npc.ai as CatAI
	if _ai != null and not _ai.state_changed.is_connected(_on_state_changed):
		_ai.state_changed.connect(_on_state_changed)
	if _ai != null and opts.has("patrol") and not bool(opts["patrol"]):
		_ai.patrol_enabled = false      # 夹具级关闭：**在第一次 tick 之前**生效（避免"先巡游再停"）
	if _ai == null:
		push_warning("猫 NPC 没有 CatAI（cat.tres 未接 ai_script 或实现缺失）")
	await _advance_frames(SPAWN_FRAMES)

	if bool(opts.get("with_mouse", false)):
		_mouse_npc = (load(BODY) as PackedScene).instantiate() as AnimalBody
		_mouse_npc.species_config = _mouse_cfg
		_mouse_npc.player_controlled = false
		_mouse_npc.position = opts.get("mouse_at", Vector3(0.0, MOUSE_Y, -5.0))
		_world.add_child(_mouse_npc)
		_mouse_npc.ai_enabled = true
		_mouse_ai = _mouse_npc.ai as MouseAI
		await _advance_frames(SPAWN_FRAMES)


func _free_world() -> void:
	_free_prey()
	_free_extras()
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	_region = null
	_npc = null
	_ai = null
	_mouse_npc = null
	_mouse_ai = null
	_transitions.clear()


func _free_prey() -> void:
	if _prey != null and is_instance_valid(_prey):
		_prey.queue_free()
	_prey = null


func _free_extras() -> void:
	for n in _extras:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_extras.clear()


## 放/移动猎物（鼠，**AI 关闭**，原地站着）
func _place_prey(point: Vector3) -> AnimalBody:
	if _prey == null or not is_instance_valid(_prey):
		_prey = (load(BODY) as PackedScene).instantiate() as AnimalBody
		_prey.species_config = _mouse_cfg
		_prey.player_controlled = false
		var parent: Node = _world if _world != null else root
		_prey.position = Vector3(point.x, MOUSE_Y, point.z)
		parent.add_child(_prey)
		return _prey
	_prey.global_position = Vector3(point.x, MOUSE_Y, point.z)
	_prey.velocity = Vector3.ZERO
	_prey.move_intent = Vector2.ZERO
	return _prey


## 猫的**正前方**偏 `angle_deg`、水平距离 `dist` 的世界坐标（正前方 = 本地 -Z）
func _point_in_front(dist: float, angle_deg := 0.0) -> Vector3:
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


func _add_marker(pos: Vector3, id: String, group: StringName) -> Marker3D:
	var m := Marker3D.new()
	m.name = id
	m.position = pos
	m.add_to_group(group)
	_world.add_child(m)
	return m


## 在猫正前方 `dist` 处横向放一道 `width` × 2 × 0.2 的实心墙（只挡视线，不一定挡路）
func _add_wall_at(dist: float, angle_deg := 0.0, width := 3.0) -> StaticBody3D:
	_wall_seq += 1
	var pt := _point_in_front(dist, angle_deg)
	var wall := _add_box(_world, "VisionWall_%d" % _wall_seq, Vector3(width, 2.0, 0.2), Vector3(pt.x, 1.0, pt.z))
	_extras.append(wall)
	return wall


## 在某两点之间放墙：`t` 是沿连线的比例（0.5 = 中点），墙沿两点连线的**法线**方向铺开、宽 `width`
func _add_wall_between(a: Vector3, b: Vector3, t := 0.5, width := 3.0) -> StaticBody3D:
	_wall_seq += 1
	var mid := a.lerp(b, t)
	var dir := b - a
	dir.y = 0.0
	var size := Vector3(width, 2.0, 0.2)
	if absf(dir.normalized().x) > absf(dir.normalized().z):
		size = Vector3(0.2, 2.0, width)
	var wall := _add_box(_world, "MidWall_%d" % _wall_seq, size, Vector3(mid.x, 1.0, mid.z))
	_extras.append(wall)
	return wall


func _add_cover(pos: Vector3, size: Vector3, factor: float) -> Area3D:
	var area := Area3D.new()
	area.name = "CoverFixture_%d" % (_wall_seq + 1)
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.position = pos
	area.set_meta("visibility_factor", factor)
	area.add_to_group("cover_volumes")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	area.add_child(cs)
	_world.add_child(area)
	_extras.append(area)
	return area


## 猫层导航参数与 T012/T019 实测口径一致
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

## 记录状态跳变（`from → to`(reason)）：E/F 段用"序列"断言，不受帧率与轮询时机影响
func _on_state_changed(from: StringName, to: StringName, reason: StringName) -> void:
	_transitions.append({"from": String(from), "to": String(to), "reason": String(reason)})
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
