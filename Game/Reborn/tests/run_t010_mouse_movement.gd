extends SceneTree
## T010 无头验收：老鼠移动与通道尺度
##
## 覆盖 `Docs/Tasks/T010.md` §6 的六组（M01 的"鼠半边" + M02 的鼠部分 + 通道尺度对照）：
##   1) 配置与几何：鼠起测值逐字段；洞 0.24×0.30、鼠低顶 0.15；**尺度判据用两个配置算**（鼠能过、猫过不去）
##   2) 鼠平地三档（短冲刺）+ 加减速 + 停住 + 贴地
##   3) 窄缝通过（M01 鼠半边）：鼠**站立**穿过 24×30 cm 洞；**猫（含蹲姿）过不去同一个洞**
##   4) 低顶（M02 鼠部分）：净空 0.15 下松蹲不扩大碰撞、走出去自动站起
##   5) 禁止高跳（M01 鼠半边）：按键不起跳；上不了 50 cm 高台；对照猫 `can_jump()==true`
##   6) 相机：鼠的小尺度下眼点仍在胶囊内、视线不插进几何体
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t010_mouse_movement.gd' --quit-after 40000
## 退出码：0 = 全部断言通过；1 = 有失败。

const FIXTURES := "res://scenes/maps/l_move_fixtures.tscn"
const BODY := "res://scenes/characters/animal_body.tscn"
const MOUSE := "res://resources/species/mouse.tres"
const CAT := "res://resources/species/cat.tres"

const GROUND_TOP := 0.10
## 设计意图常量（与 `tool_make_move_fixtures.gd` 一致；改了试验世界就必须改这里）
const TUNNEL_W := 0.24
const TUNNEL_H := 0.30
const MOUSE_LOW_CLEARANCE := 0.15
const PLATFORM_ABOVE_GROUND := 0.50

const EPS := 0.01
const FRAME := 1.0 / 60.0

## `Parameters.md` 鼠起测值（米/秒）——改这里前先改 `Parameters.md`
const WALK := 1.10
const SPRINT := 3.00
const CROUCH := 0.65
const ACCEL := 16.0

var _checks := 0
var _fails := 0
var _world: Node3D = null
var _body: AnimalBody = null
var _mouse: SpeciesConfig = null
var _cat: SpeciesConfig = null
var _geo: Dictionary = {}


func _initialize() -> void:
	print("TEST|run_t010_mouse_movement|engine=%s" % Engine.get_version_info().string)
	print("TEST|physics_ticks_per_second=%d" % Engine.physics_ticks_per_second)

	_mouse = load(MOUSE) as SpeciesConfig
	_cat = load(CAT) as SpeciesConfig
	# ART05：本套断言测第一人称的窄缝/低顶相机几何 → 钉住第一人称（正式配置已切成第三人称）
	_mouse.camera_mode = SpeciesConfig.CAMERA_FIRST_PERSON
	_cat.camera_mode = SpeciesConfig.CAMERA_FIRST_PERSON
	var packed: PackedScene = load(FIXTURES)
	if _mouse == null or _cat == null or packed == null:
		_assert("fixtures_and_configs_load", "all", "mouse=%s cat=%s fixtures=%s" % [
			_mouse != null, _cat != null, packed != null
		], false)
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

	await _s1_config_and_scale()
	await _s2_flat_speeds()
	await _s3_tunnel()
	await _s4_mouse_low_ceiling()
	await _s5_no_high_jump()

	_release_all()
	_finish()


# ---------------------------------------------------------------------------
# 0) 几何：从场景读
# ---------------------------------------------------------------------------

func _read_geometry() -> Dictionary:
	var out: Dictionary = {}
	for nm in [
		"Ground", "Platform50", "MouseTunnelLeft", "MouseTunnelRight", "MouseTunnelLintel", "MouseLowCeiling",
	]:
		var d := _box_info(nm)
		if d.is_empty():
			return {}
		out[nm] = d
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


## 洞的开口（宽 × 高，米）与车道中心 x
func _tunnel_opening() -> Dictionary:
	var l: Dictionary = _geo["MouseTunnelLeft"]
	var r: Dictionary = _geo["MouseTunnelRight"]
	var li: Dictionary = _geo["MouseTunnelLintel"]
	return {
		"w": float(r["min_x"]) - float(l["max_x"]),
		"h": float(li["bottom"]) - GROUND_TOP,
		"center_x": (float(l["max_x"]) + float(r["min_x"])) * 0.5,
		"near_z": float(l["max_z"]),   # 靠 +z 的那一面（来向）
		"far_z": float(l["min_z"]),    # 靠 −z 的那一面（去向）
	}


# ---------------------------------------------------------------------------
# 1) 配置与尺度
# ---------------------------------------------------------------------------

func _s1_config_and_scale() -> void:
	print("---- S1 配置与尺度 ----")
	var expected := {
		"capsule_radius": 0.06, "capsule_half_height": 0.09, "crouch_half_height": 0.06,
		"walk_speed": 1.10, "sprint_speed": 3.00, "crouch_speed": 0.65,
		"max_step_height": 0.03, "jump_velocity": 0.0, "max_acceleration": 16.0,
		"camera_offset_z": 0.03, "fov": 90.0, "vision_range": 6.5, "vision_half_angle_deg": 75.0,
		"hearing_range": 10.0, "hunger_loss_per_sec": 0.10, "thirst_loss_per_sec": 0.08,
		"sprint_stamina_per_sec": 35.0, "stamina_regen_per_sec": 25.0, "regen_delay": 0.7,
		"interaction_range": 0.45,
	}
	for field in expected:
		_assert_near("mouse_%s" % field, float(expected[field]), float(_mouse.get(field)), 1e-6)
	_assert("mouse_species_id", "Mouse", str(_mouse.species_id), str(_mouse.species_id) == "Mouse")
	_assert("mouse_validate_clean", "no problems", str(_mouse.validate_config()), _mouse.validate_config().is_empty())
	_assert("mouse_can_jump_false", "false", str(_mouse.can_jump), not _mouse.can_jump)
	_assert("mouse_can_use_mouse_tunnel_true", "true", str(_mouse.can_use_mouse_tunnel), _mouse.can_use_mouse_tunnel)
	_assert("cat_cannot_use_mouse_tunnel", "false", str(_cat.can_use_mouse_tunnel), not _cat.can_use_mouse_tunnel)

	# 洞与低顶：几何必须等于设计常量
	var op := _tunnel_opening()
	_assert_near("tunnel_opening_w", TUNNEL_W, float(op["w"]), 1e-3)
	_assert_near("tunnel_opening_h", TUNNEL_H, float(op["h"]), 1e-3)
	var cl: float = float(_geo["MouseLowCeiling"]["bottom"]) - GROUND_TOP
	_assert_near("mouse_low_clearance", MOUSE_LOW_CLEARANCE, cl, 1e-3)
	_assert_near("platform_above_ground", PLATFORM_ABOVE_GROUND,
		float(_geo["Platform50"]["top"]) - GROUND_TOP, 1e-6)

	# **尺度判据：全部从两个配置算，不写死结论**
	var mw: float = _mouse.capsule_radius * 2.0
	var mh: float = _mouse.capsule_height()
	var mcw: float = _mouse.capsule_radius * 2.0
	var mch: float = _mouse.crouch_height()
	var cw: float = _cat.capsule_radius * 2.0
	var ch: float = _cat.capsule_height()
	var cch: float = _cat.crouch_height()
	var w: float = float(op["w"])
	var h: float = float(op["h"])
	print("SCALE|mouse_stand=%.3f x %.3f|mouse_crouch=%.3f x %.3f|cat_stand=%.3f x %.3f|cat_crouch=%.3f x %.3f|tunnel=%.3f x %.3f" % [
		mw, mh, mcw, mch, cw, ch, cw, cch, w, h
	])
	_assert("scale_mouse_stand_fits", "%.3f<=%.3f and %.3f<=%.3f" % [mw, w, mh, h], "%.3f x %.3f" % [mw, mh],
		mw <= w and mh <= h)
	_assert("scale_mouse_crouch_fits", "fits", "%.3f x %.3f" % [mcw, mch], mcw <= w and mch <= h)
	_assert("scale_cat_stand_blocked", "blocked", "%.3f x %.3f" % [cw, ch], cw > w or ch > h)
	_assert("scale_cat_crouch_blocked", "blocked (width is the hard bound)", "%.3f x %.3f" % [cw, cch], cw > w)
	_assert("scale_mouse_low_ceiling_between_stances", "%.3f < %.3f < %.3f" % [mch, cl, mh], "ok",
		cl > mch and cl < mh)
	_assert("scale_cat_crouch_cannot_enter_mouse_low", "%.3f < %.3f" % [cl, cch], "ok", cl < cch)

	# 鼠站立成型：胶囊/相机/台阶
	await _spawn(_mouse, Vector3(-2.0, GROUND_TOP + _mouse.capsule_half_height + 0.02, 6.0), 0.0)
	var st := _body.debug_state()
	_assert_near("mouse_capsule_height_live", 0.18, float(st["capsule_height"]), 1e-4)
	_assert_near("mouse_mesh_matches_capsule", 0.18, float(st["mesh_height"]), 1e-4)
	_assert("mouse_camera_axis_vertical", "y", str(st["camera_offset_axis"]), str(st["camera_offset_axis"]) == "y")
	_assert("camera_inside_capsule_mouse_standing", "true", str(_camera_inside_capsule()), _camera_inside_capsule())
	_assert_near("mouse_climb_max_step", 0.03, _body.climb.max_step_height, 1e-9)


# ---------------------------------------------------------------------------
# 2) 平地三档
# ---------------------------------------------------------------------------

func _s2_flat_speeds() -> void:
	print("---- S2 鼠平地三档 ----")
	var walk := await _measure_lane("walk", ["move_right"], 60)
	var sprint := await _measure_lane("sprint", ["move_right", "sprint"], 60)
	var crouch := await _measure_lane("crouch", ["move_right", "crouch"], 60)

	_assert_range("walk_distance_1s", 0.95, 1.15, walk["dist"])
	_assert_range("sprint_distance_1s", 2.40, 3.00, sprint["dist"])
	_assert_range("crouch_distance_1s", 0.50, 0.75, crouch["dist"])
	_assert("sprint_much_faster_than_walk", "sprint > walk*2", "%.3f vs %.3f" % [sprint["dist"], walk["dist"] * 2.0],
		sprint["dist"] > walk["dist"] * 2.0)
	_assert("crouch_much_slower_than_walk", "crouch < walk*0.75", "%.3f vs %.3f" % [crouch["dist"], walk["dist"] * 0.75],
		crouch["dist"] < walk["dist"] * 0.75)
	_assert_near("walk_terminal_speed", WALK, walk["terminal"], 0.06)
	_assert_near("sprint_terminal_speed", SPRINT, sprint["terminal"], 0.20)
	_assert_near("crouch_terminal_speed", CROUCH, crouch["terminal"], 0.05)
	_assert("walk_capsule_bottom_on_ground", "|bottom-0.10| < 0.01", "%.4f" % walk["min_bottom"],
		absf(walk["min_bottom"] - GROUND_TOP) < EPS)

	var accel_time := await _measure_accel_time()
	_assert("accel_time_within_0.20s", "<= 0.20 s", "%.3f s" % accel_time, accel_time <= 0.20)
	_assert("accel_time_positive", ">= 0.02 s", "%.3f s" % accel_time, accel_time >= 0.02)

	var stop := await _measure_stop()
	_assert("stop_velocity_near_zero", "< 0.05 m/s", "%.4f" % stop["speed"], stop["speed"] < 0.05)
	_assert("stop_extra_slide_short", "< 0.10 m", "%.3f" % stop["slide"], stop["slide"] < 0.10)


func _measure_lane(tag: String, actions: Array, frames: int) -> Dictionary:
	await _spawn(_mouse, Vector3(-2.0, GROUND_TOP + _mouse.capsule_half_height + 0.02, 6.0), 0.0)
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
	print("MEASURE|mouse_%s|dist=%.3f|terminal=%.3f|min_bottom=%.4f" % [tag, dist, terminal, min_bottom])
	return {"dist": dist, "terminal": terminal, "min_bottom": min_bottom}


func _measure_accel_time() -> float:
	await _spawn(_mouse, Vector3(-2.0, GROUND_TOP + _mouse.capsule_half_height + 0.02, 6.0), 0.0)
	Input.action_press("move_right")
	var t := 0.0
	var reached := -1.0
	for i in 60:
		await physics_frame
		t += FRAME
		if reached < 0.0 and Vector2(_body.velocity.x, _body.velocity.z).length() >= WALK * 0.9:
			reached = t
			break
	Input.action_release("move_right")
	print("MEASURE|mouse_accel_to_90pct|t=%.4f|theory=%.4f" % [reached, WALK * 0.9 / ACCEL])
	return reached if reached >= 0.0 else 99.0


func _measure_stop() -> Dictionary:
	await _spawn(_mouse, Vector3(-2.0, GROUND_TOP + _mouse.capsule_half_height + 0.02, 6.0), 0.0)
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
	print("MEASURE|mouse_stop|v_at_release=%.3f|slide=%.3f|v_after_1s=%.4f|theory=%.3f" % [
		v0, slide, speed, v0 * v0 / (2.0 * ACCEL)
	])
	return {"slide": slide, "speed": speed}


# ---------------------------------------------------------------------------
# 3) 窄缝通过（M01 鼠半边 + 通道尺度）
# ---------------------------------------------------------------------------

func _s3_tunnel() -> void:
	print("---- S3 窄缝 24x30 cm（M01 鼠半边）----")
	var op := _tunnel_opening()
	var cx: float = float(op["center_x"])
	var near_z: float = float(op["near_z"])
	var far_z: float = float(op["far_z"])

	# (a) 鼠：站立穿过
	await _spawn(_mouse, Vector3(cx, GROUND_TOP + _mouse.capsule_half_height + 0.02, near_z + 4.0), 0.0)
	var start_z: float = _body.global_position.z
	var all_on_floor := true
	var min_y := 1e9
	var max_y := -1e9
	var airborne := 0
	var overlaps := 0
	var cam_ok_in_tunnel := true
	var cam_samples_in_tunnel := 0
	Input.action_press("move_forward")
	var frames_to_pass := -1
	for i in 380:
		await physics_frame
		var p: Vector3 = _body.global_position
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
		if not _body.is_on_floor():
			all_on_floor = false
			airborne += 1
		# 走到洞里（z 在洞厚范围内）时抽查相机：眼点必须在胶囊内、且不插进几何体
		if absf(p.z - (near_z + far_z) * 0.5) <= 0.10:
			cam_samples_in_tunnel += 1
			if not _camera_inside_capsule() or _camera_hits() != 0 or not await _camera_view_clear(0.0):
				cam_ok_in_tunnel = false
		if frames_to_pass < 0 and p.z < far_z - 0.30:
			frames_to_pass = i
			break
	Input.action_release("move_forward")
	await _wait(10)
	var end: Vector3 = _body.global_position
	overlaps = _overlaps_world(0.01)
	var expected_y: float = GROUND_TOP + _mouse.capsule_half_height
	print("MEASURE|mouse_tunnel|start_z=%.3f|end=(%.3f, %.3f, %.3f)|frames_to_pass=%d|y=[%.4f, %.4f]|airborne=%d|overlaps=%d|capsule_h=%.3f" % [
		start_z, end.x, end.y, end.z, frames_to_pass, min_y, max_y, airborne, overlaps,
		(_body.shape_node.shape as CapsuleShape3D).height
	])
	_assert("tunnel_mouse_passed", "z < %.3f" % (far_z - 0.30), "z=%.3f" % end.z, end.z < far_z - 0.30)
	_assert("tunnel_mouse_stayed_on_floor", "true", str(all_on_floor), all_on_floor)
	_assert("tunnel_mouse_never_raised", "|y-%.3f| < 0.01" % expected_y, "y_max=%.4f" % max_y,
		absf(max_y - expected_y) < EPS and absf(min_y - expected_y) < EPS)
	_assert("tunnel_mouse_no_penetration", "0 overlaps", "%d overlaps" % overlaps, overlaps == 0)
	_assert_near("tunnel_mouse_walked_standing", 2.0 * _mouse.capsule_half_height,
		(_body.shape_node.shape as CapsuleShape3D).height, 1e-4)
	_assert("tunnel_camera_sampled_inside", "> 3 samples", "%d samples" % cam_samples_in_tunnel,
		cam_samples_in_tunnel > 3)
	_assert("tunnel_mouse_camera_clean_inside", "true", str(cam_ok_in_tunnel), cam_ok_in_tunnel)

	# (b) 猫：同一车道、同一个洞，站着过不去
	await _spawn(_cat, Vector3(cx, GROUND_TOP + _cat.capsule_half_height + 0.02, near_z + 4.0), 0.0)
	var step_reason := "<none>"
	Input.action_press("move_forward")
	for i in 150:
		await physics_frame
		var pr: Dictionary = _body.climb.last_probe
		if pr.has("reason"):
			step_reason = str(pr["reason"])
	Input.action_release("move_forward")
	await _wait(10)
	var cat_end: Vector3 = _body.global_position
	var cat_pen := _overlaps_world(0.01)
	print("MEASURE|cat_tunnel_standing|end=(%.3f, %.3f, %.3f)|near_z=%.3f|step_reason=%s|penetration=%d" % [
		cat_end.x, cat_end.y, cat_end.z, near_z, step_reason, cat_pen
	])
	_assert("tunnel_cat_stand_blocked", "z >= %.3f" % (near_z + _cat.capsule_radius - EPS), "z=%.3f" % cat_end.z,
		cat_end.z >= near_z + _cat.capsule_radius - EPS)
	_assert("tunnel_cat_stand_did_not_pass", "z > %.3f" % far_z, "z=%.3f" % cat_end.z, cat_end.z > far_z)
	_assert("tunnel_cat_stand_stayed_on_ground", "y=%.3f" % (GROUND_TOP + _cat.capsule_half_height),
		"y=%.3f" % cat_end.y, absf(cat_end.y - (GROUND_TOP + _cat.capsule_half_height)) < 0.02)
	_assert("tunnel_cat_stand_no_penetration", "0 overlaps", "%d overlaps" % cat_pen, cat_pen == 0)
	# 非真空：猫必须真的**走到洞面并被挡住**（150 帧 @1.8 m/s 刚好够 4.0 m；实测停在洞面）
	_assert("tunnel_cat_stand_reached_the_face", "|z - %.3f| <= 0.10" % (near_z + _cat.capsule_radius),
		"z=%.3f" % cat_end.z, absf(cat_end.z - (near_z + _cat.capsule_radius)) <= 0.10)

	# (c) 猫蹲着也过不去（宽度 0.32 > 0.24 是硬边界）
	# 帧数必须够它**走到**洞前：蹲姿 0.9 m/s，起步在洞前 4.0 m → 需要约 4.5 s（270 帧），给 400 帧余量。
	# （第一版只给 150 帧，猫根本没走到洞前，两条断言都成了"真空通过"——已修。）
	await _spawn(_cat, Vector3(cx, GROUND_TOP + _cat.capsule_half_height + 0.02, near_z + 4.0), 0.0)
	Input.action_press("crouch")
	await _wait(10)
	Input.action_press("move_forward")
	await _wait(400)
	Input.action_release("move_forward")
	Input.action_release("crouch")
	await _wait(10)
	var cat_c: Vector3 = _body.global_position
	var face_limit: float = near_z + _cat.capsule_radius
	print("MEASURE|cat_tunnel_crouched|end=(%.3f, %.3f, %.3f)|capsule_h=%.3f|face_limit=%.3f" % [
		cat_c.x, cat_c.y, cat_c.z, (_body.shape_node.shape as CapsuleShape3D).height, face_limit
	])
	_assert("tunnel_cat_crouch_did_not_pass", "z > %.3f" % far_z, "z=%.3f" % cat_c.z, cat_c.z > far_z)
	# 非真空：它必须真的**走到洞面并被挡住**（不能停在半路就宣称"过不去"）
	_assert("tunnel_cat_crouch_reached_the_face", "|z - %.3f| <= 0.10" % face_limit, "z=%.3f" % cat_c.z,
		absf(cat_c.z - face_limit) <= 0.10)


# ---------------------------------------------------------------------------
# 4) 鼠低顶（M02 鼠部分）
# ---------------------------------------------------------------------------

func _s4_mouse_low_ceiling() -> void:
	print("---- S4 鼠低顶（净空 0.15 m）----")
	var lc: Dictionary = _geo["MouseLowCeiling"]
	var lc_x: float = (lc["center"] as Vector3).x
	var lc_max_z: float = float(lc["max_z"])
	var lane_z: float = lc_max_z + 1.0   # 从低顶外侧 1 m 处起步

	await _spawn(_mouse, Vector3(lc_x, GROUND_TOP + _mouse.capsule_half_height + 0.02, lane_z), 0.0)
	var y_stand: float = _body.global_position.y
	var eye_stand: float = _body.camera.global_position.y

	# (a) 开阔地蹲下：胶囊 0.12、视线下降 drop、胶囊底仍贴地
	Input.action_press("crouch")
	await _wait(6)
	var st := _body.debug_state()
	var eye_crouch: float = _body.camera.global_position.y
	print("MEASURE|mouse_crouch_open|y_stand=%.3f|y_crouch=%.3f|eye_stand=%.3f|eye_crouch=%.3f|capsule_h=%.3f" % [
		y_stand, _body.global_position.y, eye_stand, eye_crouch, float(st["capsule_height"])
	])
	_assert("crouch_state_on", "true", str(st["is_crouching"]), bool(st["is_crouching"]))
	_assert_near("crouch_capsule_height", _mouse.crouch_height(), float(st["capsule_height"]), 1e-4)
	_assert_near("crouch_body_y_drops", y_stand - _mouse.crouch_drop(), _body.global_position.y, EPS)
	_assert_near("crouch_capsule_bottom_on_ground", GROUND_TOP,
		_body.global_position.y - _mouse.crouch_half_height, EPS)
	_assert_near("crouch_camera_local_y_lowered", _mouse.camera_offset_z - _mouse.crouch_drop(),
		_body.camera.position.y, 1e-6)
	# 视线下降 = 2 × crouch_drop：身体下沉 1 份 + 相机本地再降 1 份（与 T009 猫一致）
	_assert_near("crouch_eye_drops_by_2x_drop", 2.0 * _mouse.crouch_drop(), eye_stand - eye_crouch, 0.005)
	_assert("camera_inside_capsule_mouse_crouched", "true", str(_camera_inside_capsule()), _camera_inside_capsule())

	# (b) 蹲着钻进低顶（板底 0.25），再松开蹲姿 1.0 s
	Input.action_press("move_forward")
	await _wait(220)
	Input.action_release("move_forward")
	var under: Vector3 = _body.global_position
	_assert("entered_under_mouse_low", "z < %.3f" % (lc_max_z - 0.4), "z=%.3f" % under.z, under.z < lc_max_z - 0.4)
	_assert("still_under_slab", "capsule top < slab bottom",
		"top=%.3f < %.3f" % [under.y + _mouse.crouch_half_height, float(lc["bottom"])],
		under.y + _mouse.crouch_half_height < float(lc["bottom"]) + 1e-6)

	Input.action_release("crouch")
	await _wait(60)
	var st2 := _body.debug_state()
	print("MEASURE|mouse_low_ceiling|z=%.3f|y=%.3f|capsule_h=%.3f|slab_bottom=%.3f|headroom=%s" % [
		_body.global_position.z, _body.global_position.y, float(st2["capsule_height"]),
		float(lc["bottom"]), str(st2["headroom_free"])
	])
	_assert("low_ceiling_keeps_crouch", "still crouching", "crouching=%s" % st2["is_crouching"],
		bool(st2["is_crouching"]))
	_assert("low_ceiling_blocks_standup_flag", "true", str(st2["stance_blocked_by_headroom"]),
		bool(st2["stance_blocked_by_headroom"]))
	_assert_near("low_ceiling_capsule_still_crouch", _mouse.crouch_height(), float(st2["capsule_height"]), 1e-4)
	_assert("low_ceiling_headroom_free_false", "false", str(st2["headroom_free"]), not bool(st2["headroom_free"]))
	var ov: int = _overlaps_world(0.01)
	_assert("no_penetration_under_mouse_low", "0 overlaps", "%d overlaps" % ov, ov == 0)
	_assert("camera_clear_under_mouse_low", "0 hits", "%d hits" % _camera_hits(), _camera_hits() == 0)
	_assert("camera_view_clear_under_mouse_low", "true", str(await _camera_view_clear(0.0)),
		await _camera_view_clear(0.0))

	# (c) 走出低顶 → 自动站起
	Input.action_press("move_back")
	await _wait(220)
	Input.action_release("move_back")
	await _wait(30)
	var st3 := _body.debug_state()
	var out: Vector3 = _body.global_position
	_assert("left_mouse_low_footprint", "z > %.3f" % lc_max_z, "z=%.3f" % out.z, out.z > lc_max_z)
	_assert("stands_up_after_leaving_mouse_low", "not crouching", "crouching=%s" % st3["is_crouching"],
		not bool(st3["is_crouching"]))
	_assert_near("capsule_back_to_stand", _mouse.capsule_height(), float(st3["capsule_height"]), 1e-4)
	_assert_near("standing_body_y_on_ground", GROUND_TOP + _mouse.capsule_half_height, out.y, EPS)
	print("MEASURE|mouse_low_exit|z=%.3f|y=%.3f|capsule_h=%.3f" % [
		out.z, out.y, float(st3["capsule_height"])
	])


# ---------------------------------------------------------------------------
# 5) 禁止高跳（M01 鼠半边）
# ---------------------------------------------------------------------------

func _s5_no_high_jump() -> void:
	print("---- S5 禁止高跳 ----")
	# (a) 平地按跳跃：不得起跳
	await _spawn(_mouse, Vector3(-2.0, GROUND_TOP + _mouse.capsule_half_height + 0.02, 6.0), 0.0)
	var y0: float = _body.global_position.y
	var max_up := 0.0
	var all_floor := true
	Input.action_press("jump")
	for i in 40:
		await physics_frame
		max_up = maxf(max_up, _body.global_position.y - y0)
		if not _body.is_on_floor():
			all_floor = false
	Input.action_release("jump")
	print("MEASURE|mouse_jump_flat|max_up=%.4f|on_floor_all=%s|can_jump=%s|jump_v=%.2f" % [
		max_up, all_floor, str(_body.can_jump()), _mouse.jump_velocity
	])
	_assert("mouse_can_jump_false_live", "false", str(_body.can_jump()), not _body.can_jump())
	_assert("mouse_jump_does_not_take_off", "max_up <= 0.01", "%.4f" % max_up, max_up <= 0.01)
	_assert("mouse_jump_stays_on_floor", "true", str(all_floor), all_floor)

	# (b) 直冲 50 cm 高台：上不去，且原因是被台阶逻辑挡住
	var pf: Dictionary = _geo["Platform50"]
	var face_z: float = float(pf["max_z"])
	var cx: float = (pf["center"] as Vector3).x
	await _spawn(_mouse, Vector3(cx, GROUND_TOP + _mouse.capsule_half_height + 0.02, face_z + 2.0), 0.0)
	var step_reason := "<none>"
	Input.action_press("move_forward")
	for i in 150:
		await physics_frame
		var pr: Dictionary = _body.climb.last_probe
		if pr.has("reason"):
			step_reason = str(pr["reason"])
	Input.action_release("move_forward")
	await _wait(10)
	var p: Vector3 = _body.global_position
	var pen := _overlaps_world(0.01)
	print("MEASURE|mouse_platform_blocked|y=%.3f|z=%.3f|face_z=%.3f|step_reason=%s|penetration=%d" % [
		p.y, p.z, face_z, step_reason, pen
	])
	_assert_near("mouse_stays_on_ground_at_platform", GROUND_TOP + _mouse.capsule_half_height, p.y, 0.02)
	_assert("mouse_never_on_platform", "z >= %.3f" % (face_z + _mouse.capsule_radius - EPS), "z=%.3f" % p.z,
		p.z >= face_z + _mouse.capsule_radius - EPS)
	_assert("mouse_blocked_by_step_logic", "blocked_after_raise", step_reason, step_reason == "blocked_after_raise")
	_assert("mouse_no_penetration_at_platform", "0 overlaps", "%d overlaps" % pen, pen == 0)

	# (c) 对照：同一位置用猫配置 → can_jump 为 true（能力差异只在配置）
	await _spawn(_cat, Vector3(cx, GROUND_TOP + _cat.capsule_half_height + 0.02, face_z + 2.0), 0.0)
	_assert("cat_can_jump_true_live", "true", str(_body.can_jump()), _body.can_jump())


# ---------------------------------------------------------------------------
# 通用工具
# ---------------------------------------------------------------------------

func _spawn(cfg: SpeciesConfig, pos: Vector3, yaw: float) -> void:
	_release_all()
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
		await process_frame
	_body = (load(BODY) as PackedScene).instantiate() as AnimalBody
	_body.species_config = cfg
	_world.add_child(_body)
	_body.global_position = pos
	_body.rotation = Vector3(0.0, yaw, 0.0)
	_body.velocity = Vector3.ZERO
	_body.climb.reset_base()
	for i in 180:
		await physics_frame
		if _body.is_on_floor():
			break
	_body.climb.update_base_y()
	await _wait(5)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "jump", "interact", "pounce"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


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


## 相机位置处半径 2 cm 的球是否命中世界静态几何
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


## 相机视线是否干净：从眼点沿朝向射线 `camera.near + 5 mm`，不得命中世界静态几何
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


## 把当前胶囊收缩 shrink 米后与世界静态几何的重叠数
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


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
