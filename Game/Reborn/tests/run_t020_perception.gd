extends SceneTree
## T020 老鼠视觉、听觉与逃跑 断言
##
## 覆盖（`Docs/Tasks/T020.md` §6；数值真源 `Docs/Parameters.md` 第 71 / 73 行）：
##   A 接口与默认值（`Perception` / 噪声配置 / 逃跑参数）
##   B 视觉：距离 × 草丛系数 → 视野角 → 遮挡；近距 0.80 m 豁免（`TechnicalDesign` §0）
##   C 听觉：`HearingRange × Loudness`；墙与草丛都不影响听觉；自己的噪声不触发自己
##   D **噪声只有发生位置**（TestCases **A02** 前半：墙后跑步 → 只警戒到原声音位置，不跟踪真实位置）
##   E 脚步事件（**非每帧**）+ 档位响度 0.2/0.5/1.0 + `WorldDirector` 噪声总线
##   F 逃跑与躲藏（可达鼠洞）：`ALERT` 0.3 s → `FLEE` → 钻洞 → `HIDDEN` → 无危险 4 s 后外出
##   G 无路径超时回退（TestCases **A03** 前半）：候选不可达 / 洞被堵住 → 都有回退且**不永久卡住**
##   H 集成（真实 `l_courtyard`：洞里的躲藏点、鼠层可达 / 猫层不可达、HUD 与 `MOV|` 可查看）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t020_perception.gd' --quit-after 240000

const MOUSE := "res://resources/species/mouse.tres"
const CAT := "res://resources/species/cat.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"

const EPS := 1e-4
const ARENA := 40.0
const NPC_Y := 0.10          # 鼠站立时胶囊中心高度（半高 0.09 + 1 cm）
const CAT_Y := 0.25          # 猫站立时胶囊中心高度（半高 0.24 + 1 cm）
const BARRIER_H := 0.50
const HOLE_W := 0.24
const HOLE_H := 0.30
const HOLE_POINT := Vector3(0.0, 0.05, 0.0)      # 夹具里的鼠洞躲藏点（洞中心）
const OUTSIDE_SPOT := Vector3(0.0, 0.05, 26.0)   # 没有导航面的孤立平台上的躲藏点

var _checks := 0
var _fails := 0
var _mouse: SpeciesConfig = null
var _cat: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null
var _region: NavigationRegion3D = null
var _npc: AnimalBody = null
var _ai: MouseAI = null
var _threat: AnimalBody = null
var _bus_events := 0
var _last_event := {}


func _initialize() -> void:
	print("TEST|run_t020_perception|engine=%s" % Engine.get_version_info().string)
	_mouse = load(MOUSE) as SpeciesConfig
	_cat = load(CAT) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")
	if _wd != null and _wd.has_signal("noise_emitted") and not _wd.is_connected("noise_emitted", _on_noise_event):
		_wd.connect("noise_emitted", _on_noise_event)

	_section_a_defaults()
	await _section_b_vision()
	await _section_c_hearing()
	await _section_d_noise_position_only()
	await _section_e_footsteps()
	await _section_f_flee_and_hide()
	await _section_g_blocked_fallback()
	await _section_h_integration()

	_finish()


# ---------------------------------------------------------------------------
# A 接口与默认值
# ---------------------------------------------------------------------------

func _section_a_defaults() -> void:
	print("---- A 接口与默认值 ----")
	var probe := Perception.new()
	_assert("A_perception_is_node", "Node", str(probe is Node), probe is Node)
	_assert("A_has_can_see_point", "有 can_see_point()", str(probe.has_method("can_see_point")),
		probe.has_method("can_see_point"))
	_assert("A_has_cover_factor_at", "有 cover_factor_at()", str(probe.has_method("cover_factor_at")),
		probe.has_method("cover_factor_at"))
	_assert("A_has_receive_noise", "有 receive_noise()", str(probe.has_method("receive_noise")),
		probe.has_method("receive_noise"))
	_assert("A_has_report", "有 report()", str(probe.has_method("report")), probe.has_method("report"))
	_assert_near("A_near_detect_range", 0.80, probe.near_detect_range, EPS)
	probe.free()

	var ai := MouseAI.new()
	_assert("A_mouse_ai_is_animal_ai", "MouseAI 继承 AnimalAI", str(ai is AnimalAI), ai is AnimalAI)
	_assert_near("A_hidden_hold_time", 4.0, ai.hidden_hold_time, EPS)
	_assert_near("A_immediate_flee_range", 1.80, ai.immediate_flee_range, EPS)
	_assert_near("A_flee_timeout", 3.0, ai.flee_timeout, EPS)
	_assert_near("A_alert_max_time", 0.3, ai.alert_max_time, EPS)
	_assert_near("A_hide_arrive_radius", 0.30, ai.hide_arrive_radius, EPS)
	_assert_near("A_reach_tolerance", 0.5, ai.reach_tolerance, EPS)
	_assert("A_has_reachable", "有 reachable()", str(ai.has_method("reachable")), ai.has_method("reachable"))
	_assert("A_has_find_hide_spot", "有 find_hide_spot()", str(ai.has_method("find_hide_spot")),
		ai.has_method("find_hide_spot"))
	_assert("A_has_find_cover_point", "有 find_cover_point()", str(ai.has_method("find_cover_point")),
		ai.has_method("find_cover_point"))
	_assert("A_state_flee", "3（契约顺序）", str(int(AnimalAI.State.FLEE)), int(AnimalAI.State.FLEE) == 3)
	_assert("A_state_hidden", "4（契约顺序）", str(int(AnimalAI.State.HIDDEN)), int(AnimalAI.State.HIDDEN) == 4)
	ai.free()

	_assert_near("A_mouse_loudness_crouch", 0.2, _mouse.noise_loudness_crouch, EPS)
	_assert_near("A_mouse_loudness_walk", 0.5, _mouse.noise_loudness_walk, EPS)
	_assert_near("A_mouse_loudness_sprint", 1.0, _mouse.noise_loudness_sprint, EPS)
	_assert_near("A_mouse_footstep_interval_base", 0.5, _mouse.footstep_interval_base, EPS)
	_assert_near("A_cat_loudness_sprint", 1.0, _cat.noise_loudness_sprint, EPS)
	_assert("A_mouse_config_valid", "无问题", str(_mouse.validate_config().size()), _mouse.validate_config().is_empty())
	_assert("A_cat_config_valid", "无问题", str(_cat.validate_config().size()), _cat.validate_config().is_empty())
	_assert("A_hearing_range_mouse_10", "10.0", "%.1f" % _mouse.hearing_range, absf(_mouse.hearing_range - 10.0) < EPS)


# ---------------------------------------------------------------------------
# B 视觉
# ---------------------------------------------------------------------------

func _section_b_vision() -> void:
	print("---- B 视觉（距离 / 视野 / 遮挡 / 草丛 / 近距豁免）----")
	await _fresh_world()
	var p := _npc.perception
	_assert_near("B_vision_range_6.5", 6.5, _mouse.vision_range, EPS)
	_assert_near("B_half_angle_75", 75.0, _mouse.vision_half_angle_deg, EPS)

	_assert_see("B_front_3m_seen", Vector3(0.0, CAT_Y, -3.0), true)
	_assert_see("B_front_6m_seen", Vector3(0.0, CAT_Y, -6.0), true)
	_assert_see("B_front_6.9m_not_seen", Vector3(0.0, CAT_Y, -6.9), false)
	_assert_see("B_fov_60deg_seen", Vector3(3.0 * sin(deg_to_rad(60.0)), CAT_Y, -3.0 * cos(deg_to_rad(60.0))), true)
	_assert_see("B_fov_74deg_seen", Vector3(3.0 * sin(deg_to_rad(74.0)), CAT_Y, -3.0 * cos(deg_to_rad(74.0))), true)
	_assert_see("B_fov_100deg_not_seen", Vector3(3.0 * sin(deg_to_rad(100.0)), CAT_Y, -3.0 * cos(deg_to_rad(100.0))), false)
	_assert_see("B_behind_not_seen", Vector3(0.0, CAT_Y, 3.0), false)

	# `tick()` 与点判定是同一条代码路径
	_place_cat(Vector3(0.0, CAT_Y, -3.0))
	await _advance_frames(3)
	_assert("B_tick_sees_threat", "true", str(p.is_threat_visible()), p.is_threat_visible())
	_assert("B_threat_id_recorded", "非空", p.threat_id(), not p.threat_id().is_empty())
	_assert("B_sight_count_once", "1（跳变计数，不是每帧 +1）", str(p.sight_count()), p.sight_count() == 1)

	# 遮挡：`world_static` 墙挡视线
	var wall := _add_box(_region, "VisionWall", Vector3(3.0, 2.0, 0.2), Vector3(0.0, 1.0, -1.5))
	await _advance_frames(2)
	_assert_see("B_occluded_by_wall", Vector3(0.0, CAT_Y, -3.0), false)
	await _advance_frames(2)
	_assert("B_occluded_tick", "false", str(p.is_threat_visible()), not p.is_threat_visible())
	wall.queue_free()
	await _advance_frames(3)
	_assert_see("B_seen_after_wall_removed", Vector3(0.0, CAT_Y, -3.0), true)

	# 近距豁免：0.80 m 内**按无遮挡检测**（隔墙 0.6 m 仍可见；1.2 m 就看不见）
	var near_wall := _add_box(_region, "NearWall", Vector3(3.0, 2.0, 0.2), Vector3(0.0, 1.0, -0.3))
	await _advance_frames(2)
	_assert_see("B_near_exempt_0.6m_seen", Vector3(0.0, CAT_Y, -0.6), true)
	_assert_see("B_beyond_near_1.2m_not_seen", Vector3(0.0, CAT_Y, -1.2), false)
	near_wall.queue_free()
	await _advance_frames(2)

	# 草丛系数：0.4 → 发现距离 6.5 × 0.4 = 2.6 m（`Parameters.md` 第 73 行）
	var cover := _add_cover(Vector3(0.0, 1.0, -3.0), Vector3(2.0, 2.0, 4.0), 0.4)
	await _advance_frames(3)
	_assert_near("B_cover_factor_in_cover", 0.4, p.cover_factor_at(Vector3(0.0, CAT_Y, -3.0)), EPS)
	_assert_near("B_cover_factor_outside", 1.0, p.cover_factor_at(Vector3(6.0, CAT_Y, 0.0)), EPS)
	_assert_see("B_in_cover_3m_not_seen", Vector3(0.0, CAT_Y, -3.0), false)
	_assert_see("B_in_cover_2m_seen", Vector3(0.0, CAT_Y, -2.0), true)
	cover.queue_free()
	await _advance_frames(3)
	_assert_see("B_outside_cover_3m_seen", Vector3(0.0, CAT_Y, -3.0), true)
	_assert("B_in_cover_flag_false", "false（草丛已移走）", str(p.report().get("in_cover", true)),
		not bool(p.report().get("in_cover", true)))
	_assert("B_unsupported_shapes", "0（Box 形状都被识别）", str(int(p.report().get("unsupported_shape_count", -1))),
		int(p.report().get("unsupported_shape_count", -1)) == 0)


# ---------------------------------------------------------------------------
# C 听觉
# ---------------------------------------------------------------------------

func _section_c_hearing() -> void:
	print("---- C 听觉（HearingRange × Loudness）----")
	await _fresh_world()
	var p := _npc.perception
	var before := p.heard_count()

	var h1 := p.receive_noise("Cat#probe", Vector3(0.0, CAT_Y, -9.5), 1.0, _now())
	_assert("C_run_9.5m_heard", "true（9.5 ≤ 10.0）", str(h1), h1)
	var h2 := p.receive_noise("Cat#probe", Vector3(0.0, CAT_Y, -10.5), 1.0, _now())
	_assert("C_run_10.5m_not_heard", "false（10.5 > 10.0）", str(h2), not h2)
	var h3 := p.receive_noise("Cat#probe", Vector3(0.0, CAT_Y, -4.5), 0.5, _now())
	_assert("C_walk_4.5m_heard", "true（4.5 ≤ 5.0）", str(h3), h3)
	var h4 := p.receive_noise("Cat#probe", Vector3(0.0, CAT_Y, -5.5), 0.5, _now())
	_assert("C_walk_5.5m_not_heard", "false（5.5 > 5.0）", str(h4), not h4)
	var h5 := p.receive_noise("Cat#probe", Vector3(0.0, CAT_Y, -1.5), 0.2, _now())
	_assert("C_crouch_1.5m_heard", "true（1.5 ≤ 2.0）", str(h5), h5)
	var h6 := p.receive_noise("Cat#probe", Vector3(0.0, CAT_Y, -2.5), 0.2, _now())
	_assert("C_crouch_2.5m_not_heard", "false（2.5 > 2.0）", str(h6), not h6)
	_assert("C_count_only_valid", "%d（只有 3 次有效）" % (before + 3), str(p.heard_count()),
		p.heard_count() == before + 3)
	_assert("C_snapshot_has_position", "非零", str(p.last_noise_position()), p.last_noise_position().length() > 0.1)
	_assert_near("C_snapshot_loudness", 0.2, p.last_noise_loudness(), EPS)

	# 自己的噪声不触发自己（按 source_id 过滤）
	var h7 := p.receive_noise(_npc.source_id(), Vector3(0.0, NPC_Y, -1.0), 1.0, _now())
	_assert("C_own_noise_ignored", "false", str(h7), not h7)
	_assert("C_own_noise_not_counted", str(p.heard_count()), str(p.heard_count()), p.heard_count() == before + 3)

	# 墙**不**挡听觉（声音绕过实体）
	var wall := _add_box(_region, "HearingWall", Vector3(6.0, 2.0, 0.2), Vector3(0.0, 1.0, -1.5))
	await _advance_frames(2)
	var h8 := p.receive_noise("Cat#probe", Vector3(0.0, CAT_Y, -3.0), 1.0, _now())
	_assert("C_wall_does_not_block_hearing", "true", str(h8), h8)

	# 草丛也**不**减小听觉（听觉只看距离×响度）
	var cover := _add_cover(Vector3(0.0, 1.0, -3.5), Vector3(2.0, 2.0, 4.0), 0.4)
	await _advance_frames(2)
	var h9 := p.receive_noise("Cat#probe", Vector3(0.0, CAT_Y, -3.5), 0.5, _now())
	_assert("C_cover_does_not_reduce_hearing", "true（3.5 ≤ 5.0）", str(h9), h9)
	wall.queue_free()
	cover.queue_free()
	await _advance_frames(2)


# ---------------------------------------------------------------------------
# D 噪声只有发生位置（TestCases A02 前半）
# ---------------------------------------------------------------------------

func _section_d_noise_position_only() -> void:
	print("---- D 噪声只有发生位置（A02 前半）----")
	await _fresh_world()
	var p := _npc.perception
	# 墙在 2.5 m 外（12 m 宽）；猫在墙后 5 m 处**沿墙平行跑** —— 看不见，只听得见
	_add_box(_region, "DWall", Vector3(12.0, 2.0, 0.2), Vector3(0.0, 1.0, -2.5))
	var cat := _place_cat(Vector3(0.0, CAT_Y, -5.0))
	await _advance_frames(8)
	_assert("D_not_seen_through_wall", "false", str(p.is_threat_visible()), not p.is_threat_visible())

	cat.move_intent = Vector2(1.0, 0.0)
	cat.want_sprint = true
	await _run_seconds(1.5, func() -> bool: return p.heard_count() >= 1)
	await _advance_frames(2)
	_assert("D_heard_footsteps", "≥ 1", str(p.heard_count()), p.heard_count() >= 1)
	_assert("D_no_visual_knowledge", "没有见过猫", str(p.has_seen()), not p.has_seen())
	_assert("D_alert_on_noise", "alert / heard_noise", "%s / %s" % [_ai.state_id(), _ai.state_reason()],
		_ai.state_id() == &"alert" and _ai.state_reason() == &"heard_noise")

	# 让它再跑一小会儿后停住（停止后不再产生脚步）
	await _run_seconds(0.4)
	cat.move_intent = Vector2.ZERO
	cat.want_sprint = false
	await _advance_frames(6)
	var noise_snapshot := p.last_noise_position()
	var alert_pos := _ai.alert_position()
	var heard_before := p.heard_count()
	_assert("D_noise_snapshot_behind_wall", "z < -2.5（声音来自墙后）", "%.2f" % noise_snapshot.z, noise_snapshot.z < -2.5)
	_assert("D_noise_snapshot_not_self", "> 4 m（不是老鼠自己）", "%.2f m" % noise_snapshot.distance_to(_npc.global_position),
		noise_snapshot.distance_to(_npc.global_position) > 4.0)
	_assert("D_alert_at_noise_position", "= 噪声发生位置", "%.4f" % alert_pos.distance_to(noise_snapshot),
		alert_pos.distance_to(noise_snapshot) < 0.6)

	# 声源**瞬移**到 8 m 外且不再发声
	cat.global_position = Vector3(0.0, CAT_Y, -8.0)
	cat.velocity = Vector3.ZERO
	await _advance_frames(45)
	_assert("D_moved_source_not_visible", "false", str(p.is_threat_visible()), not p.is_threat_visible())
	_assert("D_noise_snapshot_unchanged", "仍是原发生位置", "%.4f" % p.last_noise_position().distance_to(noise_snapshot),
		p.last_noise_position().distance_to(noise_snapshot) < EPS)
	_assert("D_no_new_noise", str(heard_before), str(p.heard_count()), p.heard_count() == heard_before)
	_assert("D_noise_age_grows", "> 0.5 s", "%.2f s" % p.noise_age(), p.noise_age() > 0.5)
	_assert("D_alert_position_unchanged", "仍是原发生位置", "%.4f" % _ai.alert_position().distance_to(alert_pos),
		_ai.alert_position().distance_to(alert_pos) < EPS)
	_assert("D_not_tracking_real_source", "> 3 m（没有跟着声源走）",
		"%.2f m" % _ai.alert_position().distance_to(cat.global_position),
		_ai.alert_position().distance_to(cat.global_position) > 3.0)
	_assert("D_no_navigation_to_source", "has_destination=false", str(_ai.ai_report().get("has_destination", true)),
		not bool(_ai.ai_report().get("has_destination", true)))
	_assert("D_alert_ended_after_0_3", "已回落（不无限延长）", str(_ai.has_alert()), not _ai.has_alert())


# ---------------------------------------------------------------------------
# E 脚步事件（非每帧 / 档位响度 / 总线）
# ---------------------------------------------------------------------------

func _section_e_footsteps() -> void:
	print("---- E 脚步事件（非每帧 / 响度 / 总线）----")
	await _fresh_world()
	var cat := _place_cat(Vector3(0.0, CAT_Y, -6.0))
	await _advance_frames(10)

	# 行走 2.0 s：0.5 s 一步 → 约 4 步
	var steps_before := cat.footstep_count
	var bus_before := _bus_events
	var frames_before := Engine.get_physics_frames()
	cat.move_intent = Vector2(0.0, -1.0)
	await _run_seconds(2.0)
	var frames := Engine.get_physics_frames() - frames_before
	var walked := cat.footstep_count - steps_before
	_assert("E_walk_steps_2s", "3~6 步", str(walked), walked >= 3 and walked <= 6)
	_assert("E_not_every_frame", "帧数 ≫ 步数", "frames=%d steps=%d" % [frames, walked], frames > walked * 10)
	_assert_near("E_walk_loudness_0.5", 0.5, cat.last_footstep_loudness, EPS)
	_assert("E_walk_interval_0.5", "≈ 0.5 s", "%.3f s" % cat.footstep_interval(), absf(cat.footstep_interval() - 0.5) < 0.06)
	_assert("E_bus_received_all_steps", "总线条数 = 脚步数", "bus=%d steps=%d" % [_bus_events - bus_before, walked],
		_bus_events - bus_before == walked)
	_assert_near("E_bus_loudness", 0.5, float(_last_event.get("loudness", 0.0)), EPS)
	_assert("E_bus_source_id", "= cat.source_id()", str(_last_event.get("source_id", "")),
		str(_last_event.get("source_id", "")) == cat.source_id())
	_assert("E_bus_position_is_origin", "≈ 猫的位置", "%.3f" % (Vector3(_last_event.get("position", Vector3.ZERO)).distance_to(cat.global_position)),
		Vector3(_last_event.get("position", Vector3.ZERO)).distance_to(cat.global_position) < 1.0)

	# 冲刺：响度 1.0、间隔 ≈ 0.2 s
	cat.want_sprint = true
	await _run_seconds(1.0)
	_assert_near("E_sprint_loudness_1.0", 1.0, cat.last_footstep_loudness, EPS)
	_assert("E_sprint_interval_0.2", "≈ 0.2 s", "%.3f s" % cat.footstep_interval(), absf(cat.footstep_interval() - 0.2) < 0.05)

	# 潜伏：响度 0.2、间隔 ≈ 1.0 s
	cat.want_sprint = false
	cat.move_intent = Vector2.ZERO
	cat.want_crouch = true
	await _advance_frames(6)
	_assert("E_crouching", "true", str(cat.is_crouching), cat.is_crouching)
	_assert_near("E_crouch_loudness_0.2", 0.2, cat.noise_loudness(), EPS)
	cat.move_intent = Vector2(0.0, -1.0)
	await _run_seconds(0.6)
	cat.move_intent = Vector2.ZERO
	_assert("E_crouch_interval_1.0", "≈ 1.0 s", "%.3f s" % cat.footstep_interval(),
		absf(cat.footstep_interval() - 1.0) < 0.2)

	# 停住 → 不再产生脚步
	await _advance_frames(4)
	var steps_still := cat.footstep_count
	await _run_seconds(0.7)
	_assert("E_no_steps_when_stopped", str(steps_still), str(cat.footstep_count), cat.footstep_count == steps_still)

	# 树暂停 → 世界时间不走 → 也不产生脚步
	cat.move_intent = Vector2(0.0, -1.0)
	await _advance_frames(2)
	var steps_paused := cat.footstep_count
	paused = true
	await _advance_frames(20)
	paused = false
	_assert("E_no_steps_while_paused", str(steps_paused), str(cat.footstep_count), cat.footstep_count == steps_paused)
	cat.move_intent = Vector2.ZERO


# ---------------------------------------------------------------------------
# F 逃跑与躲藏（可达鼠洞）
# ---------------------------------------------------------------------------

func _section_f_flee_and_hide() -> void:
	print("---- F 逃跑与躲藏（可达鼠洞）----")
	await _fresh_world(true, true)
	var p := _npc.perception
	var spots := get_nodes_in_group("hide_spots")
	_assert("F_hide_spot_in_fixture", "1", str(spots.size()), spots.size() == 1)
	var spot := _ai.find_hide_spot()
	_assert("F_find_hide_spot", "HideSpot_Fixture", str(spot.name if spot != null else "<null>"),
		spot != null and spot.name == "HideSpot_Fixture")
	_assert("F_reachable_spot", "true（鼠层能进洞）", str(_ai.reachable(HOLE_POINT)), _ai.reachable(HOLE_POINT))
	_assert("F_candidates_tested", "≥ 1", str(_ai.hide_candidates_tested()), _ai.hide_candidates_tested() >= 1)
	_assert("F_no_unreachable", "0", str(_ai.hide_unreachable_count()), _ai.hide_unreachable_count() == 0)

	var start := _npc.global_position
	_place_cat(Vector3(2.5, CAT_Y, 3.0))          # 3.2 m、约 51° → 看得见，但不在"立即逃"距离内
	await _advance_frames(6)
	_assert("F_seen", "true", str(p.is_threat_visible()), p.is_threat_visible())
	_assert("F_alert_on_sight", "alert / saw_threat", "%s / %s" % [_ai.state_id(), _ai.state_reason()],
		_ai.state_id() == &"alert" and _ai.state_reason() == &"saw_threat")
	_assert("F_move_intent_zero_in_alert", "(0, 0)", str(_npc.move_intent), _npc.move_intent.length() < 0.01)
	await _run_seconds(0.2)
	_assert("F_still_alert_at_0.2", "alert", str(_ai.state_id()), _ai.state_id() == &"alert")
	await _run_seconds(0.25)
	_assert("F_flees_after_alert", "flee", str(_ai.state_id()), _ai.state_id() == &"flee")
	_assert("F_flee_reason", "alert_ended_threat", str(_ai.state_reason()), _ai.state_reason() == &"alert_ended_threat")
	_assert("F_flee_kind_hide", "hide", str(_ai.flee_kind()), _ai.flee_kind() == &"hide")
	_assert("F_hide_target_id", "HideSpot_Fixture", _ai.hide_target_id(), _ai.hide_target_id() == "HideSpot_Fixture")
	_assert("F_has_destination", "true", str(_ai.ai_report().get("has_destination", false)),
		bool(_ai.ai_report().get("has_destination", false)))
	_assert("F_path_has_points", "> 1", str(int(_ai.ai_report().get("path_points", 0))),
		int(_ai.ai_report().get("path_points", 0)) > 1)

	var travelled := await _run_seconds(15.0, func() -> bool: return _ai.state_id() == &"hidden")
	_assert("F_reached_hidden", "hidden", str(_ai.state_id()), _ai.state_id() == &"hidden")
	_assert("F_moved", "> 3 m", "%.2f m" % start.distance_to(_npc.global_position),
		start.distance_to(_npc.global_position) > 3.0)
	_assert("F_arrived_at_spot", "≤ 0.35 m", "%.3f m" % _npc.global_position.distance_to(Vector3(0.0, _npc.global_position.y, 0.0)),
		_npc.global_position.distance_to(Vector3(0.0, _npc.global_position.y, 0.0)) <= 0.35)
	_assert("F_inside_hole_lane", "|x| ≤ 0.2 且 z ≤ 0.5", "(%.2f, %.2f)" % [_npc.global_position.x, _npc.global_position.z],
		absf(_npc.global_position.x) <= 0.20 and _npc.global_position.z <= 0.5)
	_assert("F_hidden_count", "1", str(_ai.hidden_count()), _ai.hidden_count() == 1)
	_assert("F_move_intent_zero_hidden", "(0, 0)", str(_npc.move_intent), _npc.move_intent.length() < 0.01)
	_assert("F_reached_within_timeout", "≤ 15 s", "%.2f s" % travelled, travelled > 0.0)

	# 躲藏保持：**躲满 4 s 且这 4 s 内无危险**才外出（`Parameters.md` 第 71 行）
	var hidden_pos := _npc.global_position
	_assert("F_not_seen_in_hole", "false", str(p.is_threat_visible()), not p.is_threat_visible())
	await _run_seconds(3.0)
	_assert("F_still_hidden_at_3s", "hidden", str(_ai.state_id()), _ai.state_id() == &"hidden")
	_assert("F_no_move_while_hidden", "< 0.05 m（没有走动）", "%.4f m" % hidden_pos.distance_to(_npc.global_position),
		hidden_pos.distance_to(_npc.global_position) < 0.05)
	# 用 `until` 精确停在"刚外出"的那一帧，才读得到那一刻的原因
	var out_seconds := await _run_seconds(6.0, func() -> bool: return _ai.state_id() != &"hidden")
	_assert("F_out_after_4s", "explore", str(_ai.state_id()), _ai.state_id() == &"explore")
	_assert("F_out_reason", "hidden_done", str(_ai.state_reason()), _ai.state_reason() == &"hidden_done")
	# 允许 1 帧采样误差（AI 用自己那一帧的世界时间判定；测试侧采样时刻差 ≤ 1 物理帧）
	_assert("F_out_not_before_4s", "≥ 4 s − 1 帧", "%.3f s" % (3.0 + out_seconds), 3.0 + out_seconds >= 4.0 - 0.05)
	_assert("F_hidden_elapsed_ge_4", "≥ 4 s", "%.2f s" % float(_ai.ai_report().get("hidden_elapsed", 0.0)),
		float(_ai.ai_report().get("hidden_elapsed", 0.0)) >= 4.0)

# ---------------------------------------------------------------------------
# G 无路径超时回退（TestCases A03 前半）
# ---------------------------------------------------------------------------

func _section_g_blocked_fallback() -> void:
	print("---- G 无路径超时回退（A03 前半）----")

	# G1：躲藏点在**没有导航面**的孤立平台上 → 候选不可达 → 超时回退（不设目的地、不卡死）
	await _fresh_world(false, true, true)
	_assert("G1_spot_exists", "1", str(get_nodes_in_group("hide_spots").size()), get_nodes_in_group("hide_spots").size() == 1)
	var spot := _ai.find_hide_spot()
	_assert("G1_no_reachable_hide_spot", "<null>", str(spot), spot == null)
	_assert("G1_candidates_tested", "≥ 1", str(_ai.hide_candidates_tested()), _ai.hide_candidates_tested() >= 1)
	_assert("G1_unreachable_recorded", "≥ 1", str(_ai.hide_unreachable_count()), _ai.hide_unreachable_count() >= 1)
	_assert("G1_reachable_false", "false", str(_ai.reachable(OUTSIDE_SPOT)), not _ai.reachable(OUTSIDE_SPOT))
	_assert("G1_no_cover_fallback", "NAN（没有草丛）", str(_ai.find_cover_point()), is_nan(_ai.find_cover_point().x))

	_place_cat(Vector3(0.8, CAT_Y, -1.0))         # 1.28 m、在**正前**（鼠朝 −Z）→ **立即逃**（不等警戒 0.3 s）
	await _advance_frames(6)
	_assert("G1_immediate_flee", "flee / threat_close", "%s / %s" % [_ai.state_id(), _ai.state_reason()],
		_ai.state_id() == &"flee" and _ai.state_reason() == &"threat_close")
	_assert("G1_flee_kind_none", "none", str(_ai.flee_kind()), _ai.flee_kind() == &"none")
	_assert("G1_no_destination", "false", str(_ai.ai_report().get("has_destination", true)),
		not bool(_ai.ai_report().get("has_destination", true)))
	var stuck_pos := _npc.global_position
	_free_threat()
	await _advance_frames(3)
	var back := await _run_seconds(8.0, func() -> bool: return _ai.state_id() == &"explore")
	_assert("G1_timeout_returns_explore", "explore", str(_ai.state_id()), _ai.state_id() == &"explore")
	_assert("G1_timeout_reason", "flee_timeout", str(_ai.state_reason()), _ai.state_reason() == &"flee_timeout")
	_assert("G1_timeout_recorded", "≥ 1", str(_ai.flee_timeouts()), _ai.flee_timeouts() >= 1)
	_assert("G1_timeout_within_bounds", "≤ 8 s", "%.2f s" % back, back > 0.0 and back <= 8.0)
	_assert("G1_no_move_without_target", "< 0.05 m", "%.4f m" % stuck_pos.distance_to(_npc.global_position),
		stuck_pos.distance_to(_npc.global_position) < 0.05)
	_assert("G1_never_hid", "hidden_count=0", str(_ai.hidden_count()), _ai.hidden_count() == 0)

	# G2：洞被**烘焙之后**堵住（导航图仍以为可达）→ 实走失败 → 记诊断、退出 FLEE、**不假躲藏**
	await _fresh_world(true, true, false, true)
	_assert("G2_nav_precheck_ok", "true（导航图是堵洞前烘焙的）", str(_ai.find_hide_spot() != null),
		_ai.find_hide_spot() != null)
	_place_cat(Vector3(0.8, CAT_Y, 4.0))
	await _advance_frames(6)
	_assert("G2_flee_started", "flee", str(_ai.state_id()), _ai.state_id() == &"flee")
	_free_threat()
	await _advance_frames(3)
	var left := await _run_seconds(20.0,
		func() -> bool: return _ai.state_id() != &"flee" and _ai.state_id() != &"alert")
	_assert("G2_left_flee", "非 flee / alert", str(_ai.state_id()),
		_ai.state_id() != &"flee" and _ai.state_id() != &"alert")
	_assert("G2_failures_recorded", "≥ 1", str(int(_ai.ai_report().get("path_failures", 0))),
		int(_ai.ai_report().get("path_failures", 0)) >= 1)
	_assert("G2_diagnostic_readable", "非空", str(_ai.ai_report().get("last_path_status", "")),
		not String(_ai.ai_report().get("last_path_status", "")).is_empty())
	_assert("G2_no_fake_hiding", "没有进 HIDDEN", "hidden_count=%d" % _ai.hidden_count(), _ai.hidden_count() == 0)
	_assert("G2_exited_within_bounds", "≤ 20 s", "%.2f s" % left, left > 0.0)
	_assert("G2_blocked_before_hole", "z > 0（没穿到屏障另一侧）", "%.2f" % _npc.global_position.z, _npc.global_position.z > 0.0)


# ---------------------------------------------------------------------------
# H 集成（真实 l_courtyard）
# ---------------------------------------------------------------------------

func _section_h_integration() -> void:
	print("---- H 集成（真实 l_courtyard）----")
	_free_world()
	await _advance_frames(2)
	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await _advance_frames(10)
	_world = level

	var spots := get_nodes_in_group("hide_spots")
	_assert("H_level_hide_spot_count", "1", str(spots.size()), spots.size() == 1)
	var hole_point := Vector3(26.5, 0.15, 19.0)
	if spots.size() == 1:
		var spot := spots[0] as Node3D
		_assert("H_level_hide_spot_id", "HideSpot_RootHole", str(spot.name), spot.name == "HideSpot_RootHole")
		_assert("H_level_hide_spot_species", "Mouse", str(spot.get_meta("species", "")),
			StringName(spot.get_meta("species", &"")) == &"Mouse")
		_assert("H_level_hide_spot_in_hole", "x=26.50 / z=19.00", "(%.2f, %.2f)" % [spot.position.x, spot.position.z],
			absf(spot.position.x - 26.50) < 0.01 and absf(spot.position.z - 19.00) < 0.05)

	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = _mouse
	body.player_controlled = false
	body.position = Vector3(24.0, 0.35, 24.0)     # Roots 区（屏障北侧）
	level.add_child(body)
	body.ai_enabled = true
	await _advance_frames(12)
	var ai := body.ai as MouseAI
	_assert("H_ai_built", "MouseAI", str(ai != null), ai != null)
	if ai == null:
		level.queue_free()
		_world = null
		return

	_assert("H_nav_layer_mouse", "1（关卡的鼠层）", str(ai.nav_layer()), ai.nav_layer() == 1)
	var found := ai.find_hide_spot()
	_assert("H_find_hide_spot", "HideSpot_RootHole", str(found.name if found != null else "<null>"),
		found != null and found.name == "HideSpot_RootHole")
	_assert("H_spot_reachable", "true", str(ai.reachable(hole_point)), ai.reachable(hole_point))
	_assert("H_perception_wired", "有感知组件", str(body.perception != null), body.perception != null)

	# 鼠层能到洞里、**猫层到不了**（T012 口径）
	var map := ai.agent.get_navigation_map()
	var mouse_path := NavigationServer3D.map_get_path(map, body.global_position, hole_point, true, 1)
	var mouse_end := mouse_path[mouse_path.size() - 1] if mouse_path.size() > 0 else Vector3(INF, INF, INF)
	_assert("H_mouse_path_has_points", "> 1", str(mouse_path.size()), mouse_path.size() > 1)
	_assert("H_mouse_path_reaches_hole", "≤ 0.5 m", "%.3f m" % mouse_end.distance_to(hole_point),
		mouse_end.distance_to(hole_point) <= 0.5)
	var cat_path := NavigationServer3D.map_get_path(map, Vector3(30.0, 0.35, 24.0), hole_point, true, 2)
	var cat_end := cat_path[cat_path.size() - 1] if cat_path.size() > 0 else Vector3(INF, INF, INF)
	_assert("H_cat_layer_cannot_reach_hole", "猫层终点离洞 > 0.5 m", "%.3f m" % cat_end.distance_to(hole_point),
		cat_end.distance_to(hole_point) > 0.5)

	var rep := ai.ai_report()
	_assert("H_report_has_perception_fields", "含 seen/heard/noise_age/hide_target/flee_timeouts",
		str(rep.keys()).substr(0, 0) + "keys=%d" % rep.keys().size(),
		rep.has("seen") and rep.has("heard") and rep.has("noise_age") and rep.has("hide_target")
			and rep.has("flee_timeouts"))

	# 调试入口 HUD：`sense:` 行 + `MOV|` 字段（"状态和原因可查看"）
	if ResourceLoader.exists(ENTRY):
		var entry: Node = (load(ENTRY) as PackedScene).instantiate()
		root.add_child(entry)
		await _advance_frames(10)
		if entry.has_method("switch_species"):
			entry.call("switch_species", &"Mouse")
			await _advance_frames(10)
		var hud := String(entry.call("hud_text")) if entry.has_method("hud_text") else ""
		var mov := String(entry.call("mov_line")) if entry.has_method("mov_line") else ""
		_assert("H_hud_has_sense_line", "含 'sense:'", _clip(hud), hud.contains("sense:"))
		_assert("H_mov_has_heard", "含 'heard='", _clip(mov), mov.contains("heard="))
		_assert("H_mov_has_noise_age", "含 'noise_age='", _clip(mov), mov.contains("noise_age="))
		_assert("H_mov_has_steps", "含 'steps='", _clip(mov), mov.contains("steps="))
		entry.queue_free()
		await _advance_frames(2)

	var debug_nodes := 0
	for n in _all_nodes(level):
		if n.get_script() != null:
			var sp := String((n.get_script() as Script).resource_path)
			if sp.contains("/debug/"):
				debug_nodes += 1
	_assert("H_no_debug_node_in_level", "0", str(debug_nodes), debug_nodes == 0)

	var main := (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _advance_frames(4)
	_assert("H_main_loads", "true", str(main != null), main != null)
	main.queue_free()
	await _advance_frames(2)
	level.queue_free()
	await _advance_frames(2)
	_world = null


# ---------------------------------------------------------------------------
# 夹具
# ---------------------------------------------------------------------------

## 平地 + 已烘焙的鼠层导航 + 一只鼠 NPC（威胁由 `_place_cat()` 放置）
##
## `with_barrier`：树根屏障 + 0.24×0.30 洞（与 T011 关卡同口径，洞中心 x=0 / z=0）
## `with_hide_spot`：放一个 `hide_spots` 标记（`spot_outside` 时放在**没有导航面**的孤立平台上）
## `block_hole`：**烘焙之后**再堵洞（导航图仍以为可达 → 测"实际走不通"的回退）
func _fresh_world(with_barrier := false, with_hide_spot := false, spot_outside := false, block_hole := false) -> void:
	_free_world()
	await _advance_frames(2)
	_world = Node3D.new()
	_world.name = "T020World"
	root.add_child(_world)
	await _advance_frames(2)

	_region = NavigationRegion3D.new()
	_region.name = "MouseRegion"
	_region.navigation_mesh = _make_navmesh()
	_region.navigation_layers = 1
	_region.set_meta("species", "Mouse")
	_world.add_child(_region)

	_add_box(_region, "ArenaGround", Vector3(ARENA, 1.0, ARENA), Vector3(0.0, -0.5, 0.0))
	if with_barrier:
		_add_barrier()
	if with_hide_spot:
		if spot_outside:
			# 孤立平台：**不挂在导航区域下** → 这个点没有导航面（"候选不可达"）
			_add_box(_world, "OutPlatform", Vector3(4.0, 1.0, 4.0), Vector3(0.0, -0.5, 26.0))
			_add_hide_spot(OUTSIDE_SPOT, "HideSpot_Fixture")
		else:
			_add_hide_spot(HOLE_POINT, "HideSpot_Fixture")
	await _advance_frames(2)
	_region.bake_navigation_mesh(false)
	await _advance_frames(6)
	if block_hole:
		_add_box(_region, "HolePlug", Vector3(HOLE_W, HOLE_H, 0.6), Vector3(0.0, HOLE_H * 0.5, 0.0))
		await _advance_frames(2)

	var npc := (load(BODY) as PackedScene).instantiate() as AnimalBody
	npc.species_config = _mouse
	npc.player_controlled = false
	npc.position = Vector3(0.0, NPC_Y, 5.0) if with_barrier else Vector3(0.0, NPC_Y, 0.0)
	npc.velocity = Vector3.ZERO
	_world.add_child(npc)
	npc.ai_enabled = true
	await _advance_frames(12)
	_npc = npc
	_ai = npc.ai as MouseAI
	if _ai == null:
		push_warning("NPC 没有 MouseAI（实现缺失）")


func _free_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	_region = null
	_npc = null
	_ai = null
	_threat = null


func _free_threat() -> void:
	if _threat != null and is_instance_valid(_threat):
		_threat.queue_free()
	_threat = null


## 树根屏障 + 0.24 × 0.30 洞（baking 前调用，洞会留在导航面上）
func _add_barrier() -> void:
	var span := 10.0
	var half_gap := HOLE_W * 0.5
	var west_w := span - half_gap
	_add_box(_region, "BarrierWest", Vector3(west_w, BARRIER_H, 1.0), Vector3(-(half_gap + west_w * 0.5), BARRIER_H * 0.5, 0.0))
	_add_box(_region, "BarrierEast", Vector3(west_w, BARRIER_H, 1.0), Vector3(half_gap + west_w * 0.5, BARRIER_H * 0.5, 0.0))
	var lintel_h := BARRIER_H - HOLE_H
	_add_box(_region, "BarrierLintel", Vector3(HOLE_W, lintel_h, 1.0), Vector3(0.0, HOLE_H + lintel_h * 0.5, 0.0))


## 鼠层导航参数与 T012/T019 实测口径一致（0.03 格才留得住 0.24 的洞）
func _make_navmesh() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.07
	nm.agent_height = 0.20
	nm.agent_max_climb = 0.03
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.03
	nm.cell_height = 0.03
	nm.region_min_size = 0.02
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	return nm


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


func _add_hide_spot(pos: Vector3, id: String, species := "Mouse", radius := 0.30) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = id
	marker.position = pos
	marker.set_meta("species", species)
	marker.set_meta("radius", radius)
	marker.set_meta("kind", "mouse_hole")
	marker.add_to_group("hide_spots")
	_world.add_child(marker)
	return marker


func _add_cover(pos: Vector3, size: Vector3, factor: float) -> Area3D:
	var area := Area3D.new()
	area.name = "CoverFixture"
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
	return area


func _place_cat(pos: Vector3) -> AnimalBody:
	if _threat == null or not is_instance_valid(_threat):
		_threat = (load(BODY) as PackedScene).instantiate() as AnimalBody
		_threat.species_config = _cat
		_threat.player_controlled = false
		_threat.position = pos
		_world.add_child(_threat)
	else:
		_threat.global_position = pos
		_threat.velocity = Vector3.ZERO
	_threat.move_intent = Vector2.ZERO
	_threat.want_sprint = false
	_threat.want_crouch = false
	return _threat


func _assert_see(id: String, pos: Vector3, expected: bool) -> void:
	var cat := _place_cat(pos)
	var seen: bool = _npc.perception.can_see_point(cat.global_position, cat.eye_position())
	_assert(id, str(expected), str(seen), seen == expected)


func _on_noise_event(source_id: String, position: Vector3, loudness: float, world_time: float) -> void:
	_bus_events += 1
	_last_event = {"source_id": source_id, "position": position, "loudness": loudness, "world_time": world_time}


func _now() -> float:
	return float(_wd.get("world_time")) if _wd != null else 0.0


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

## 推进真实世界时间直到 `until()` 为真或超时；返回实际经过秒数
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
