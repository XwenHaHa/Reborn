extends SceneTree
## T009 无头验收：猫移动与第一人称相机
##
## 覆盖 `Docs/Tests/T009.md` §6 的六组用例（M01 的猫半边 + M02）：
##   1) 配置与几何（含"相机偏移是竖直偏移"这条决策断言）
##   2) 平地三档速度 / 加减速 / 停住 / 胶囊底贴地
##   3) 潜伏：胶囊变矮、视线变低、低顶下松开蹲姿**不扩大碰撞**、走出去自动站起
##   4) 斜坡：能上、不卡住、掉不出地面
##   5) 相机不穿墙：顶住墙角转 4 个朝向，相机始终在胶囊内且不进入几何体
##   6) 跳跃与落地：离地净空 = v²/2g、不穿透、不滑动、**实跳上 50 cm 高台**、不跳就上不去、走下台不滑
##
## 试验世界：`res://scenes/maps/l_move_fixtures.tscn`（由 `tests/tool_make_move_fixtures.gd` 生成）。
## 几何从场景节点读，但**设计意图常量**（50 cm 高台 / 42 cm 低顶净空 / 25° 坡）在断言里写死：
## 谁改了试验世界而没改设计，测试会直接失败。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t009_cat_movement.gd' --quit-after 20000
## 退出码：0 = 全部断言通过；1 = 有失败。

const FIXTURES := "res://scenes/maps/l_move_fixtures.tscn"
const BODY := "res://scenes/characters/animal_body.tscn"
const CAT := "res://resources/species/cat.tres"

## 与 `tool_make_move_fixtures.gd` 一致的地面口径
const GROUND_TOP := 0.10
## 设计意图常量（改了试验世界就必须改这里，反之亦然）
const PLATFORM_ABOVE_GROUND := 0.50
const LOW_CEILING_CLEARANCE := 0.42
const RAMP_DEG := 25.0

const EPS := 0.01
const FRAME := 1.0 / 60.0

## `Parameters.md` 起测值（米/秒）——改这里前先改 `Parameters.md`
const WALK := 1.80
const SPRINT := 4.50
const CROUCH := 0.90
const JUMP_V := 3.20
const ACCEL := 10.0

var _checks := 0
var _fails := 0
var _world: Node3D = null
var _body: AnimalBody = null
var _cat: SpeciesConfig = null
var _geo: Dictionary = {}


func _initialize() -> void:
	print("TEST|run_t009_cat_movement|engine=%s" % Engine.get_version_info().string)
	print("TEST|physics_ticks_per_second=%d" % Engine.physics_ticks_per_second)

	_cat = load(CAT) as SpeciesConfig
	# ART05：本套断言测的是**第一人称**相机契约（相机在胶囊内、眼高 = `camera_offset_z`）。
	# 正式配置已切成第三人称 → 这里显式钉住第一人称，断言口径不改。
	_cat.camera_mode = SpeciesConfig.CAMERA_FIRST_PERSON
	var packed: PackedScene = load(FIXTURES)
	if _cat == null or packed == null:
		_assert("fixtures_and_config_load", "both", "cat=%s fixtures=%s" % [_cat != null, packed != null], false)
		_finish()
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	await process_frame
	await process_frame
	_geo = _read_geometry()
	if _geo.is_empty():
		_assert("fixtures_geometry_readable", "non-empty", "empty", false)
		_finish()
		return

	await _s1_config_and_geometry()
	await _s2_flat_speeds()
	await _s3_crouch_low_ceiling()
	await _s4_ramp()
	await _s5_wall_camera()
	await _s6_jump_and_landing()

	_release_all()
	_finish()


# ---------------------------------------------------------------------------
# 0) 试验世界几何：从场景读，但设计意图必须与常量一致
# ---------------------------------------------------------------------------

func _read_geometry() -> Dictionary:
	var out: Dictionary = {}
	for nm in ["Ground", "Ramp", "LowCeiling", "Platform50", "WallCornerA", "WallCornerB"]:
		var d := _box_info(nm)
		if d.is_empty():
			return {}
		out[nm] = d

	_assert("fixture_ground_top", "%.3f" % GROUND_TOP, "%.4f" % float(out["Ground"]["top"]),
		absf(float(out["Ground"]["top"]) - GROUND_TOP) < 1e-6)
	_assert("fixture_platform_height_0.50", "%.3f" % PLATFORM_ABOVE_GROUND,
		"%.4f" % (float(out["Platform50"]["top"]) - GROUND_TOP),
		absf(float(out["Platform50"]["top"]) - GROUND_TOP - PLATFORM_ABOVE_GROUND) < 1e-6)
	_assert("fixture_low_ceiling_clearance_0.42", "%.3f" % LOW_CEILING_CLEARANCE,
		"%.4f" % (float(out["LowCeiling"]["bottom"]) - GROUND_TOP),
		absf(float(out["LowCeiling"]["bottom"]) - GROUND_TOP - LOW_CEILING_CLEARANCE) < 1e-6)
	# 低顶净空必须夹在"猫蹲得下"与"猫站不起"之间，否则 M02 用例没有意义
	_assert("fixture_clearance_between_crouch_and_stand",
		"(%.2f, %.2f)" % [_cat.crouch_height(), _cat.capsule_height()],
		"%.3f" % (float(out["LowCeiling"]["bottom"]) - GROUND_TOP),
		float(out["LowCeiling"]["bottom"]) - GROUND_TOP > _cat.crouch_height()
		and float(out["LowCeiling"]["bottom"]) - GROUND_TOP < _cat.capsule_height())
	var ramp_deg: float = rad_to_deg((out["Ramp"]["body"] as Node3D).transform.basis.get_euler().x)
	_assert("fixture_ramp_deg_25", "%.1f" % RAMP_DEG, "%.2f" % ramp_deg, absf(ramp_deg - RAMP_DEG) < 1e-3)
	print("GEO|ground_top=%.3f|platform_top=%.3f|platform_z=[%.2f,%.2f]|slab_bottom=%.3f|ramp_deg=%.2f|wall_inner_x=%.3f|wall_inner_z=%.3f" % [
		float(out["Ground"]["top"]), float(out["Platform50"]["top"]),
		float(out["Platform50"]["min_z"]), float(out["Platform50"]["max_z"]),
		float(out["LowCeiling"]["bottom"]), ramp_deg,
		float(out["WallCornerA"]["max_x"]), float(out["WallCornerB"]["max_z"]),
	])
	return out


func _box_info(nm: String) -> Dictionary:
	var sb := _world.get_node_or_null(nm) as StaticBody3D
	if sb == null:
		return {}
	var cs := sb.get_node_or_null("Shape") as CollisionShape3D
	var box := cs.shape as BoxShape3D if cs != null else null
	if box == null:
		return {}
	var c: Vector3 = sb.position
	var h := box.size * 0.5
	return {
		"body": sb, "size": box.size, "center": c,
		"top": c.y + h.y, "bottom": c.y - h.y,
		"min_x": c.x - h.x, "max_x": c.x + h.x,
		"min_z": c.z - h.z, "max_z": c.z + h.z,
	}


# ---------------------------------------------------------------------------
# 1) 配置与几何
# ---------------------------------------------------------------------------

func _s1_config_and_geometry() -> void:
	print("---- S1 配置与几何 ----")
	_assert("config_crouch_between_zero_and_stand", "0 < %.3f < %.3f" % [_cat.crouch_half_height, _cat.capsule_half_height],
		"%.3f" % _cat.crouch_half_height,
		_cat.crouch_half_height > 0.0 and _cat.crouch_half_height < _cat.capsule_half_height)
	_assert("config_validate_clean", "no problems", str(_cat.validate_config()), _cat.validate_config().is_empty())
	_assert_near("config_crouch_drop", 0.09, _cat.crouch_drop(), 1e-6)

	await _spawn_cat(Vector3(0.0, GROUND_TOP + _cat.capsule_half_height + 0.02, 6.0), 0.0)
	var st := _body.debug_state()
	_assert("camera_offset_axis_is_vertical", "y", str(st["camera_offset_axis"]), str(st["camera_offset_axis"]) == "y")
	var campos: Vector3 = _body.camera.position
	_assert_near("camera_offset_y", _cat.camera_offset_z, campos.y, 1e-6)
	_assert("camera_offset_no_horizontal", "x=z=0", "x=%.4f z=%.4f" % [campos.x, campos.z],
		absf(campos.x) < 1e-6 and absf(campos.z) < 1e-6)
	_assert("camera_inside_capsule_standing", "true", str(_camera_inside_capsule()), _camera_inside_capsule())
	# 视觉网格必须与碰撞胶囊同尺寸（灰盒网格是唯一能"看见"身体的东西，别各走一套数）
	_assert("mesh_matches_capsule_standing", "mesh=(%.3f, %.3f)" % [_cat.capsule_radius, _cat.capsule_height()],
		"mesh=(%.3f, %.3f)" % [float(st["mesh_radius"]), float(st["mesh_height"])],
		absf(float(st["mesh_radius"]) - _cat.capsule_radius) < 1e-4
		and absf(float(st["mesh_height"]) - _cat.capsule_height()) < 1e-4)
	_assert("climb_bound_to_config", "%.3f" % _cat.max_step_height,
		"%.3f" % _body.climb.max_step_height, absf(_body.climb.max_step_height - _cat.max_step_height) < 1e-9)


# ---------------------------------------------------------------------------
# 2) 平地三档速度 / 加减速 / 停住 / 贴地
# ---------------------------------------------------------------------------

func _s2_flat_speeds() -> void:
	print("---- S2 平地三档速度 ----")
	var walk := await _measure_lane("walk", ["move_right"], 60)
	var sprint := await _measure_lane("sprint", ["move_right", "sprint"], 60)
	var crouch := await _measure_lane("crouch", ["move_right", "crouch"], 60)

	_assert_range("walk_distance_1s", 1.5, 1.9, walk["dist"])
	_assert_range("sprint_distance_1s", 3.0, 4.6, sprint["dist"])
	_assert_range("crouch_distance_1s", 0.6, 1.0, crouch["dist"])
	_assert("sprint_much_faster_than_walk", "sprint > walk*1.5", "%.3f vs %.3f" % [sprint["dist"], walk["dist"] * 1.5],
		sprint["dist"] > walk["dist"] * 1.5)
	_assert("crouch_much_slower_than_walk", "crouch < walk*0.6", "%.3f vs %.3f" % [crouch["dist"], walk["dist"] * 0.6],
		crouch["dist"] < walk["dist"] * 0.6)
	_assert_near("walk_terminal_speed", WALK, walk["terminal"], 0.10)
	_assert_near("sprint_terminal_speed", SPRINT, sprint["terminal"], 0.25)
	_assert_near("crouch_terminal_speed", CROUCH, crouch["terminal"], 0.06)
	_assert("walk_terminal_capsule_bottom_on_ground", "|bottom-0.10| < 0.01",
		"%.4f" % walk["min_bottom"], absf(walk["min_bottom"] - GROUND_TOP) < EPS)

	# 加速：从静止到 90% 目标速度的时间（max_acceleration = 10 m/s² → 理论 0.162 s）
	var accel_time := await _measure_accel_time()
	_assert("accel_time_within_0.35s", "<= 0.35 s", "%.3f s" % accel_time, accel_time <= 0.35)
	_assert("accel_time_matches_max_acceleration", ">= 0.10 s", "%.3f s" % accel_time, accel_time >= 0.10)

	# 松键后停下：无残余速度、无长距离滑行
	var stop := await _measure_stop()

	_assert("stop_velocity_near_zero", "< 0.05 m/s", "%.4f" % stop["speed"], stop["speed"] < 0.05)
	_assert("stop_extra_slide_short", "< 0.35 m", "%.3f" % stop["slide"], stop["slide"] < 0.35)


## 在固定车道（z=6，远离斜坡/低顶/高台/墙角）上按住若干动作跑 frames 帧
func _measure_lane(tag: String, actions: Array, frames: int) -> Dictionary:
	await _spawn_cat(Vector3(-2.0, GROUND_TOP + _cat.capsule_half_height + 0.02, 6.0), 0.0)
	var start: Vector3 = _body.global_position
	for a in actions:
		Input.action_press(a)
	var terminal := 0.0
	var min_bottom := 1e9
	for i in frames:
		await physics_frame
		terminal = maxf(terminal, Vector2(_body.velocity.x, _body.velocity.z).length())
		min_bottom = minf(min_bottom, _body.global_position.y - _current_half_height())
	for a in actions:
		Input.action_release(a)
	var delta: Vector3 = _body.global_position - start
	var dist: float = Vector2(delta.x, delta.z).length()
	print("MEASURE|%s|dist=%.3f|terminal=%.3f|dz=%.3f|min_bottom=%.4f|wish=%.3f" % [
		tag, dist, terminal, delta.z, min_bottom, _body.current_speed()
	])
	return {"dist": dist, "terminal": terminal, "delta": delta, "min_bottom": min_bottom}


## 从静止到 90% walk_speed 所需时间（秒）
func _measure_accel_time() -> float:
	await _spawn_cat(Vector3(-2.0, GROUND_TOP + _cat.capsule_half_height + 0.02, 6.0), 0.0)
	Input.action_press("move_right")
	var t := 0.0
	var reached := -1.0
	for i in 90:
		await physics_frame
		t += FRAME
		if reached < 0.0 and Vector2(_body.velocity.x, _body.velocity.z).length() >= WALK * 0.9:
			reached = t
			break
	Input.action_release("move_right")
	print("MEASURE|accel_to_90pct|t=%.4f|theory=%.4f" % [reached, WALK * 0.9 / ACCEL])
	return reached if reached >= 0.0 else 99.0


## 松键后：速度与水滑距离
func _measure_stop() -> Dictionary:
	await _spawn_cat(Vector3(-2.0, GROUND_TOP + _cat.capsule_half_height + 0.02, 6.0), 0.0)
	Input.action_press("move_right")
	for i in 60:
		await physics_frame
	Input.action_release("move_right")
	var at_release: Vector3 = _body.global_position
	var v0: float = Vector2(_body.velocity.x, _body.velocity.z).length()
	for i in 60:
		await physics_frame
	var slide: float = Vector2(_body.global_position.x - at_release.x, _body.global_position.z - at_release.z).length()
	var speed: float = Vector2(_body.velocity.x, _body.velocity.z).length()
	print("MEASURE|stop|v_at_release=%.3f|slide=%.3f|v_after_1s=%.4f|theory_slide=%.3f" % [
		v0, slide, speed, v0 * v0 / (2.0 * ACCEL)
	])
	return {"slide": slide, "speed": speed}


# ---------------------------------------------------------------------------
# 3) 潜伏：胶囊变矮、视线变低、低顶下不扩大碰撞、走出去站起来
# ---------------------------------------------------------------------------

func _s3_crouch_low_ceiling() -> void:
	print("---- S3 潜伏与低顶（M02）----")
	# (a) 开阔地蹲下
	var lc: Dictionary = _geo["LowCeiling"]
	var lc_x: float = (lc["center"] as Vector3).x
	var lane_z: float = float(lc["max_z"]) + 1.7
	await _spawn_cat(Vector3(lc_x, GROUND_TOP + _cat.capsule_half_height + 0.02, lane_z), 0.0)
	var eye_stand: float = _body.camera.global_position.y
	var y_stand: float = _body.global_position.y
	Input.action_press("crouch")
	await _wait(6)
	var st := _body.debug_state()
	_assert("crouch_state_on", "true", str(st["is_crouching"]), st["is_crouching"])
	_assert_near("crouch_capsule_height", 2.0 * _cat.crouch_half_height, float(st["capsule_height"]), 1e-4)
	_assert("mesh_matches_capsule_crouched", "mesh_h=%.3f" % _cat.crouch_height(), "mesh_h=%.3f" % float(st["mesh_height"]),
		absf(float(st["mesh_height"]) - _cat.crouch_height()) < 1e-4)
	_assert_near("crouch_body_y_drops_by_drop", y_stand - _cat.crouch_drop(), _body.global_position.y, EPS)
	var bottom: float = _body.global_position.y - _cat.crouch_half_height
	_assert_near("crouch_capsule_bottom_still_on_ground", GROUND_TOP, bottom, EPS)
	var eye_crouch: float = _body.camera.global_position.y
	_assert_near("crouch_camera_local_y_lowered", _cat.camera_offset_z - _cat.crouch_drop(),
		_body.camera.position.y, 1e-6)
	_assert_near("crouch_eye_drops_by_2x_drop", 2.0 * _cat.crouch_drop(), eye_stand - eye_crouch, 0.005)
	# 视线相对"当前胶囊顶面"的偏移应与站立时一致（蹲下是整体变矮，不是相机乱跑）
	_assert_near("eye_below_capsule_top_invariant", 0.14,
		(_body.global_position.y + _cat.crouch_half_height) - eye_crouch, 0.005)
	_assert("camera_inside_capsule_crouched", "true", str(_camera_inside_capsule()), _camera_inside_capsule())
	print("MEASURE|crouch_open|y_stand=%.3f|y_crouch=%.3f|eye_stand=%.3f|eye_crouch=%.3f" % [
		y_stand, _body.global_position.y, eye_stand, eye_crouch
	])

	# (b) 蹲着钻进低顶（板底 0.52），然后松开蹲姿 1.0 s
	Input.action_press("move_forward")
	await _wait(200)
	Input.action_release("move_forward")
	var under: Vector3 = _body.global_position
	var slab_bottom: float = float(_geo["LowCeiling"]["bottom"])
	_assert("entered_under_low_ceiling", "z < %.3f" % (float(lc["max_z"]) - 0.4), "z=%.3f" % under.z,
		under.z < float(lc["max_z"]) - 0.4)
	_assert("still_under_slab", "capsule top < slab bottom",
		"top=%.3f < %.3f" % [under.y + _cat.crouch_half_height, slab_bottom],
		under.y + _cat.crouch_half_height < slab_bottom + 1e-6)

	Input.action_release("crouch")
	await _wait(60)
	var st2 := _body.debug_state()
	_assert("low_ceiling_keeps_crouch", "still crouching", "crouching=%s" % st2["is_crouching"],
		bool(st2["is_crouching"]))
	_assert("low_ceiling_blocks_standup_flag", "true", str(st2["stance_blocked_by_headroom"]),
		bool(st2["stance_blocked_by_headroom"]))
	_assert_near("low_ceiling_capsule_still_crouch_height", 2.0 * _cat.crouch_half_height,
		float(st2["capsule_height"]), 1e-4)
	_assert("low_ceiling_headroom_free_false", "false", str(st2["headroom_free"]), not bool(st2["headroom_free"]))
	var overlaps: int = _overlaps_world(0.01)
	_assert("no_penetration_under_low_ceiling", "0 overlaps", "%d overlaps" % overlaps, overlaps == 0)
	_assert("camera_clear_under_low_ceiling", "0 hits", "%d hits" % _camera_hits(), _camera_hits() == 0)
	print("MEASURE|low_ceiling|z=%.3f|y=%.3f|capsule_h=%.3f|slab_bottom=%.3f" % [
		under.z, _body.global_position.y, float(st2["capsule_height"]), slab_bottom
	])

	# (c) 从原路走出低顶 → 自动站起（往回走：前方 z<−1.3 之后是墙角那条墙，别撞上）
	Input.action_press("move_back")
	await _wait(150)
	Input.action_release("move_back")
	await _wait(30)
	var st3 := _body.debug_state()
	_assert("left_low_ceiling_footprint", "z > %.3f" % float(lc["max_z"]), "z=%.3f" % _body.global_position.z,
		_body.global_position.z > float(lc["max_z"]))
	_assert("stands_up_after_leaving_low_ceiling", "not crouching", "crouching=%s" % st3["is_crouching"],
		not bool(st3["is_crouching"]))
	_assert_near("capsule_back_to_stand_height", _cat.capsule_height(), float(st3["capsule_height"]), 1e-4)
	_assert_near("standing_body_y_on_ground", GROUND_TOP + _cat.capsule_half_height, _body.global_position.y, EPS)
	_assert("headroom_free_outside", "true", str(st3["headroom_free"]), bool(st3["headroom_free"]))
	print("MEASURE|after_low_ceiling|z=%.3f|y=%.3f|capsule_h=%.3f" % [
		_body.global_position.z, _body.global_position.y, float(st3["capsule_height"])
	])


# ---------------------------------------------------------------------------
# 4) 斜坡
# ---------------------------------------------------------------------------

func _s4_ramp() -> void:
	print("---- S4 斜坡（25°）----")
	var start_z := 3.0
	await _spawn_cat(Vector3(0.0, GROUND_TOP + _cat.capsule_half_height + 0.02, start_z), 0.0)
	var y0: float = _body.global_position.y
	Input.action_press("move_forward")
	var min_y := 1e9
	var all_on_floor := true
	var airborne := 0
	var stuck_run := 0
	var worst_stuck := 0
	var prev: Vector3 = _body.global_position
	for i in 150:
		await physics_frame
		var p: Vector3 = _body.global_position
		min_y = minf(min_y, p.y)
		if not _body.is_on_floor():
			all_on_floor = false
			airborne += 1
		if Vector2(p.x - prev.x, p.z - prev.z).length() < 0.0005:
			stuck_run += 1
			worst_stuck = maxi(worst_stuck, stuck_run)
		else:
			stuck_run = 0
		prev = p
	Input.action_release("move_forward")
	var y1: float = _body.global_position.y
	var gain: float = y1 - y0
	var fwd: float = start_z - _body.global_position.z
	print("MEASURE|ramp|y0=%.3f|y1=%.3f|gain=%.3f|forward=%.3f|min_y=%.3f|on_floor_all=%s|airborne_frames=%d|worst_stuck_frames=%d" % [
		y0, y1, gain, fwd, min_y, all_on_floor, airborne, worst_stuck
	])
	_assert("ramp_height_gain_ge_0.45", ">= 0.45 m", "%.3f m" % gain, gain >= 0.45)
	_assert("ramp_forward_progress_ge_1.0", ">= 1.0 m", "%.3f m" % fwd, fwd >= 1.0)
	_assert("ramp_never_leaves_floor", "true", str(all_on_floor), all_on_floor)
	_assert("ramp_does_not_fall_through", "y >= ground top (0.10)", "%.3f" % min_y, min_y >= GROUND_TOP - 0.001)
	_assert("ramp_not_stuck", "< 30 stuck frames", "%d" % worst_stuck, worst_stuck < 30)
	_assert("camera_inside_capsule_on_ramp", "true", str(_camera_inside_capsule()), _camera_inside_capsule())


# ---------------------------------------------------------------------------
# 5) 相机不穿墙（M02）
# ---------------------------------------------------------------------------

func _s5_wall_camera() -> void:
	print("---- S5 墙角与相机 ----")
	var inner_x: float = float(_geo["WallCornerA"]["max_x"])
	var inner_z: float = float(_geo["WallCornerB"]["max_z"])
	var radius: float = _cat.capsule_radius
	# 面朝墙角（−x,−z）方向：yaw 45° 时 move_forward 指向 (−x,−z)
	await _spawn_cat(Vector3(-3.5, GROUND_TOP + _cat.capsule_half_height + 0.02, -3.5), deg_to_rad(45.0))
	Input.action_press("move_forward")
	var inside_ok := true
	var clear_ok := true
	var view_ok := true
	for i in 130:
		await physics_frame
		if not _camera_inside_capsule():
			inside_ok = false
		if _camera_hits() != 0:
			clear_ok = false
		# 顶住墙时的视线检查：相机朝前/朝上/朝下，近平面不得插进几何体
		if not await _camera_view_clear(0.0):
			view_ok = false
	Input.action_release("move_forward")
	await _wait(10)
	var p: Vector3 = _body.global_position
	var penetration: int = _overlaps_world(0.01)
	print("MEASURE|wall_corner|pos=(%.3f, %.3f, %.3f)|inner_x=%.3f|inner_z=%.3f|cam_in_capsule=%s|cam_hits=%d|penetration=%d" % [
		p.x, p.y, p.z, inner_x, inner_z, inside_ok, _camera_hits(), penetration
	])
	_assert("wall_no_pass_through_x", "x >= %.3f" % (inner_x + radius - EPS), "%.3f" % p.x, p.x >= inner_x + radius - EPS)
	_assert("wall_no_pass_through_z", "z >= %.3f" % (inner_z + radius - EPS), "%.3f" % p.z, p.z >= inner_z + radius - EPS)
	_assert("wall_reached_the_corner", "dx,dz <= 0.25 m", "dx=%.3f dz=%.3f" % [
		p.x - (inner_x + radius), p.z - (inner_z + radius)
	], (p.x - (inner_x + radius)) <= 0.25 and (p.z - (inner_z + radius)) <= 0.25)
	_assert_near("wall_body_still_on_ground", GROUND_TOP + _cat.capsule_half_height, p.y, 0.02)
	_assert("camera_never_leaves_capsule_in_corner", "true", str(inside_ok), inside_ok)
	_assert("camera_never_inside_geometry_in_corner", "0 hits", str(clear_ok), clear_ok)
	_assert("camera_near_plane_never_inside_wall", "0 hits along view", str(view_ok), view_ok)
	_assert("no_penetration_in_corner", "0 overlaps", "%d overlaps" % penetration, penetration == 0)

	# 顶在墙角时转视角（4 个朝向 × 上/平/下）：相机位置与近平面都必须始终干净
	var rot_base: float = _body.rotation.y
	var all_yaws_ok := true
	for k in 4:
		_body.rotation.y = rot_base + deg_to_rad(90.0 * float(k))
		await _wait(3)
		if not _camera_inside_capsule() or _camera_hits() != 0:
			all_yaws_ok = false
		for pitch in [0.0, 1.0, -1.0]:
			if not await _camera_view_clear(pitch):
				all_yaws_ok = false
	_body.rotation.y = rot_base
	print("MEASURE|corner_look_around|4_yaws_x_3_pitches|ok=%s|pos=(%.3f, %.3f, %.3f)" % [
		all_yaws_ok, _body.global_position.x, _body.global_position.y, _body.global_position.z
	])
	_assert("corner_look_around_camera_clean", "true", str(all_yaws_ok), all_yaws_ok)


# ---------------------------------------------------------------------------
# 6) 跳跃与落地（M01 的猫半边）
# ---------------------------------------------------------------------------

func _s6_jump_and_landing() -> void:
	print("---- S6 跳跃与落地 ----")
	# (a) 平地起跳：净空 = v²/(2g)
	await _spawn_cat(Vector3(-2.0, GROUND_TOP + _cat.capsule_half_height + 0.02, 6.0), 0.0)
	var y0: float = _body.global_position.y
	await _press_once("jump")
	var apex: float = y0
	var min_y: float = y0
	for i in 70:
		await physics_frame
		apex = maxf(apex, _body.global_position.y)
		min_y = minf(min_y, _body.global_position.y)
	var clear := apex - y0
	var theory: float = JUMP_V * JUMP_V / (2.0 * 9.8)
	print("MEASURE|jump_flat|clearance=%.4f|theory_v2_2g=%.4f|min_y=%.4f|y_now=%.4f|on_floor=%s" % [
		clear, theory, min_y, _body.global_position.y, _body.is_on_floor()
	])
	_assert_near("jump_clearance_matches_formula", theory, clear, 0.06)
	_assert("jump_clearance_ge_0.50", ">= 0.50 m", "%.4f m" % clear, clear >= 0.50)
	_assert("jump_never_penetrates_ground", "y >= 0.33", "%.4f" % min_y, min_y >= GROUND_TOP + _cat.capsule_half_height - EPS)
	_assert("jump_lands_on_floor", "true", str(_body.is_on_floor()), _body.is_on_floor())
	_assert_near("jump_land_y", GROUND_TOP + _cat.capsule_half_height, _body.global_position.y, 0.02)
	await _wait(30)
	var v: float = Vector2(_body.velocity.x, _body.velocity.z).length()
	_assert("jump_no_residual_slide", "< 0.05 m/s", "%.4f" % v, v < 0.05)

	# (b) 不跳就上不去 50 cm 高台（也不许被台阶算法"蹭上去"）
	var pf: Dictionary = _geo["Platform50"]
	var face_z: float = float(pf["max_z"])
	var spin_x: float = (pf["center"] as Vector3).x
	await _spawn_cat(Vector3(spin_x, GROUND_TOP + _cat.capsule_half_height + 0.02, face_z + 2.0), 0.0)
	Input.action_press("move_forward")
	# 注意：贴住台面后水平速度会被 move_and_slide 清零，届时 try_step_up 因"无位移"直接返回，
	# last_probe 会变成空字典。所以要在**接近过程中**采样台阶判定的原因（这里取最后一次非空）。
	var step_reason := "<none>"
	for i in 120:
		await physics_frame
		var pr: Dictionary = _body.climb.last_probe
		if pr.has("reason"):
			step_reason = str(pr["reason"])
	Input.action_release("move_forward")
	await _wait(20)
	var p_no_jump: Vector3 = _body.global_position
	print("MEASURE|platform_no_jump|y=%.3f|z=%.3f|face_z=%.3f|step_reason=%s" % [
		p_no_jump.y, p_no_jump.z, face_z, step_reason
	])
	_assert_near("no_jump_stays_on_ground", GROUND_TOP + _cat.capsule_half_height, p_no_jump.y, 0.02)
	_assert("no_jump_not_inside_platform", "z >= %.3f" % (face_z + _cat.capsule_radius - EPS), "z=%.3f" % p_no_jump.z,
		p_no_jump.z >= face_z + _cat.capsule_radius - EPS)
	_assert("no_jump_blocked_by_step_logic", "blocked_after_raise", step_reason,
		step_reason == "blocked_after_raise")

	# (c) 走上并实跳上 50 cm 高台
	await _spawn_cat(Vector3(spin_x, GROUND_TOP + _cat.capsule_half_height + 0.02, face_z + 2.5), 0.0)
	Input.action_press("move_forward")
	var jumped := false
	var d_at_jump := -1.0
	var apex2 := 0.0
	var frames := 0
	for i in 240:
		frames = i
		var d: float = _body.global_position.z - face_z
		if not jumped and d <= 0.78 and _body.is_on_floor():
			jumped = true
			d_at_jump = d
			Input.action_press("jump")
			await physics_frame
			Input.action_release("jump")
		await physics_frame
		apex2 = maxf(apex2, _body.global_position.y)
		if jumped and _body.global_position.y >= GROUND_TOP + PLATFORM_ABOVE_GROUND + _cat.capsule_half_height - 0.02 \
				and _body.is_on_floor():
			break
	Input.action_release("move_forward")
	await _wait(30)
	var landed: Vector3 = _body.global_position
	var on_top: bool = landed.y >= GROUND_TOP + PLATFORM_ABOVE_GROUND + _cat.capsule_half_height - 0.02
	var pen_pf: int = _overlaps_world(0.01)
	print("MEASURE|platform_jump|jumped=%s|d_at_jump=%.3f|apex=%.3f|final=(%.3f,%.3f,%.3f)|frames=%d|on_top=%s|penetration=%d" % [
		jumped, d_at_jump, apex2, landed.x, landed.y, landed.z, frames, on_top, pen_pf
	])
	_assert("platform_jump_triggered", "true", str(jumped), jumped)
	_assert("platform_jump_lands_on_top", "y >= %.3f" % (GROUND_TOP + PLATFORM_ABOVE_GROUND + _cat.capsule_half_height - 0.02),
		"y=%.3f" % landed.y, on_top)
	_assert("platform_jump_on_floor", "true", str(_body.is_on_floor()), _body.is_on_floor())
	_assert("platform_jump_no_penetration", "0 overlaps", "%d overlaps" % pen_pf, pen_pf == 0)

	# (d) 从高台走下来：落地、不穿透、不滑
	if on_top:
		Input.action_press("move_back")
		var min_y2 := 1e9
		var was_airborne := false
		for i in 120:
			await physics_frame
			min_y2 = minf(min_y2, _body.global_position.y)
			if not _body.is_on_floor():
				was_airborne = true
			if was_airborne and _body.is_on_floor() and _body.global_position.y < GROUND_TOP + _cat.capsule_half_height + 0.02:
				break
		Input.action_release("move_back")
		await _wait(30)
		var p2: Vector3 = _body.global_position
		var v2: float = Vector2(_body.velocity.x, _body.velocity.z).length()
		print("MEASURE|walk_off_platform|y=%.3f|min_y=%.3f|landed_on_floor=%s|v=%.4f|airborne_seen=%s" % [
			p2.y, min_y2, _body.is_on_floor(), v2, was_airborne
		])
		_assert("walk_off_platform_landed", "y=0.34", "%.3f" % p2.y, absf(p2.y - (GROUND_TOP + _cat.capsule_half_height)) < 0.02)
		_assert("walk_off_platform_on_floor", "true", str(_body.is_on_floor()), _body.is_on_floor())
		_assert("walk_off_platform_no_penetration", "y >= 0.33", "%.4f" % min_y2, min_y2 >= GROUND_TOP + _cat.capsule_half_height - EPS)
		_assert("walk_off_platform_no_residual_slide", "< 0.05 m/s", "%.4f" % v2, v2 < 0.05)
	else:
		_cancelled("walk_off_platform", "上不了高台，走下台用例不适用（已在 platform_jump_lands_on_top 记录失败）")


# ---------------------------------------------------------------------------
# 通用工具
# ---------------------------------------------------------------------------

func _spawn_cat(pos: Vector3, yaw: float) -> void:
	_release_all()
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
		await process_frame
	_body = (load(BODY) as PackedScene).instantiate() as AnimalBody
	_body.species_config = _cat
	_world.add_child(_body)
	_body.global_position = pos
	_body.rotation = Vector3(0.0, yaw, 0.0)
	_body.velocity = Vector3.ZERO
	_body.climb.reset_base()
	# 等落地站稳
	for i in 180:
		await physics_frame
		if _body.is_on_floor():
			break
	_body.climb.update_base_y()
	await _wait(5)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


## 单帧按一次（跳跃这类 just_pressed 用）
func _press_once(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "jump", "interact", "pounce"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


## 当前姿态下的胶囊半高（蹲下时会变，读数才诚实）
func _current_half_height() -> float:
	var cap := _body.shape_node.shape as CapsuleShape3D
	return cap.height * 0.5 if cap != null else 0.0


## 相机是否在胶囊内部（按当前胶囊几何算允许半径）
func _camera_inside_capsule() -> bool:
	if _body == null or _body.shape_node.shape == null:
		return false
	var cap := _body.shape_node.shape as CapsuleShape3D
	var half := cap.height * 0.5
	var local: Vector3 = _body.camera.position
	if absf(local.y) > half - 0.01:
		return false
	var allowed: float = cap.radius
	var cyl := half - cap.radius
	if absf(local.y) > cyl:
		var dy: float = absf(local.y) - cyl
		allowed = sqrt(maxf(0.0, cap.radius * cap.radius - dy * dy))
	return Vector2(local.x, local.z).length() <= allowed - 0.01


## 相机位置处半径 2 cm 的球是否命中世界静态几何（>0 = 相机钻进了几何体）
func _camera_hits() -> int:
	var space := _body.get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.02
	params.shape = s
	params.transform = Transform3D(Basis(), _body.camera.global_position)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.exclude = [_body.get_rid()]
	return space.intersect_shape(params, 4).size()


## 把当前胶囊收缩 shrink 米后与世界静态几何的重叠数（>0 = 真的嵌进几何体）
func _overlaps_world(shrink: float) -> int:
	var cap := _body.shape_node.shape as CapsuleShape3D
	var probe := CapsuleShape3D.new()
	probe.radius = maxf(0.001, cap.radius - shrink)
	probe.height = maxf(0.002, cap.height - shrink * 2.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = Transform3D(Basis(), _body.global_position)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.exclude = [_body.get_rid()]
	return _body.get_world_3d().direct_space_state.intersect_shape(params, 4).size()
func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	_assert(id, "%.4f (±%.4f)" % [expected, eps], "%.4f" % actual, absf(expected - actual) <= eps)


func _assert_range(id: String, lo: float, hi: float, actual: float) -> void:
	_assert(id, "[%.2f, %.2f]" % [lo, hi], "%.3f" % actual, actual >= lo and actual <= hi)



## 相机视线是否干净：从眼点沿当前朝向射线 `camera.near + 5 mm`，不得命中世界静态几何。
## 这是"相机不穿墙 / 不钻地 / 不插天花板"的真正判据：近平面插进几何体时画面会破洞。
## 眼点始终在胶囊内部（`_camera_inside_capsule`），所以这个断言的意义是**验证那条不变量真的成立**。
func _camera_view_clear(pitch: float) -> bool:
	_body.camera.rotation.x = clampf(pitch, -1.4, 1.4)
	await physics_frame
	var eye: Vector3 = _body.camera.global_position
	var dir: Vector3 = -_body.camera.global_transform.basis.z
	var space := _body.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(eye, eye + dir * (_body.camera.near + 0.005))
	params.collision_mask = 1
	params.exclude = [_body.get_rid()]
	return space.intersect_ray(params).is_empty()

func _cancelled(id: String, why: String) -> void:
	print("CANCELLED|%s|%s" % [id, why])


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
