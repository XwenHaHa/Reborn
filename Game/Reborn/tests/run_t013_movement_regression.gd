extends SceneTree
## T013 移动回归套件（可在打包产物内运行）
##
## 目的：把散在 T009/T010/T011 里的**移动判据**集中复现一次，并加上 T013 新判据：
##   **单级台阶抬升那一帧的水平位移 ≤ 该帧正常位移 + 0.05 m**
##   —— 修复前实测抬升帧会**水平瞬移 `radius_safe`（0.2 m）**（`Docs/Evidence/T009.md` §5.3），
##      所以这条判据能真的分辨"修好了"和"没修"。
##
## 数值口径全部沿用已验收的阈值（`Docs/Parameters.md` + T009/T010/T011 证据），**不放宽**：
##   平地三档速度、台阶 12/3 cm 能上而 20/12 cm 不能、猫跳净空 ≥0.50、鼠不能跳、
##   24×30 鼠洞能过而猫不能、25° 坡能上且 0 空中帧、相机眼高与蹲姿下降。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t013_movement_regression.gd' --quit-after 40000

const BODY := "res://scenes/characters/animal_body.tscn"
const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const COURTYARD := "res://scenes/maps/l_courtyard.tscn"

const GROUND_TOP := 0.10
const DT := 1.0 / 60.0

## 台阶（自建几何，口径与 `tests/probe_step_height.gd` 一致：地面顶面 y=0，台阶从 x=0 起）
const STEP_START_X := -1.5
const STEP_TARGET_X := 2.0
## 抬升那一帧允许比"正常位移"多出的水平量（米）—— 修复前实测多出 0.2 m
const TELEPORT_TOLERANCE := 0.05
## 判据：某一帧的水平位移超过"正常位移 × 1.5 + 0.05"就算异常跳变
const JUMP_FACTOR := 1.5

## 25° 坡（自建，几何与 `tests/tool_make_move_fixtures.gd` 的 Ramp 一致）
const RAMP_DEG := 25.0
const RAMP_SIZE := Vector3(2.0, 0.2, 6.0)
const RAMP_SURFACE_AT_Z := 1.5
const RAMP_START_Z := 4.0
## 鼠"不许离地"的容差（米）
const MOUSE_JUMP_EPS := 0.01
## 鼠洞/树根屏障车道（T011/T012 关卡常量）
const HOLE_X := 26.5
const BARRIER_Z_MIN := 18.5
const BARRIER_Z_MAX := 19.5
const LANE_START_Z := 21.5

## 平地三档的位移区间（60 帧 = 1 s，口径与 T007 一致：留加速段）
const GEARS := {
	"Cat": {"walk": [1.2, 1.9], "sprint": [3.0, 4.6], "crouch": [0.5, 1.0]},
	"Mouse": {"walk": [0.7, 1.15], "sprint": [1.9, 3.1], "crouch": [0.35, 0.72]},
}

const FLAT_FRAMES := 60
const SETTLE_FRAMES := 60
## 判定"站稳"所需的**连续**稳定帧数（见 `_settle` 说明）
const STABLE_FRAMES := 10
const CAT_JUMP_CLEARANCE := 0.50
const OVERLAP_SHRINK := 0.005

var _checks := 0
var _fails := 0
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null
var _world: Node3D = null


func _initialize() -> void:
	print("TEST|run_t013_movement_regression|engine=%s|physics_hz=%d" % [
		Engine.get_version_info().string, Engine.physics_ticks_per_second
	])
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig
	# ART05：本套断言比较 `camera.position.y == camera_offset_z`（第一人称口径）→ 钉住第一人称
	_cat.camera_mode = SpeciesConfig.CAMERA_FIRST_PERSON
	_mouse.camera_mode = SpeciesConfig.CAMERA_FIRST_PERSON

	await _phase_flat_gears()
	await _phase_steps()
	await _phase_jump()
	await _phase_ramp()
	await _phase_camera_stance()
	await _phase_mouse_tunnel_lane()

	_finish()


# ---------------------------------------------------------------------------
# 1) 平地三档
# ---------------------------------------------------------------------------

func _phase_flat_gears() -> void:
	print("---- 1 平地三档（60 帧位移） ----")
	for cfg in [_cat, _mouse]:
		var ranges: Dictionary = GEARS[String(cfg.species_id)]
		for gear in ["walk", "sprint", "crouch"]:
			var d := await _measure_gear(cfg, gear)
			var r: Array = ranges[gear]
			var tag := "%s_%s" % [String(cfg.species_id), gear]
			_assert_range("flat_%s_distance" % tag, float(r[0]), float(r[1]), d["moved"])
			_assert("flat_%s_no_frame_jump" % tag, "每帧 ≤ 速×dt×%.1f+%.2f" % [JUMP_FACTOR, TELEPORT_TOLERANCE],
				"max=%.4f" % d["max_frame"], d["max_frame"] <= d["wish_speed"] * DT * JUMP_FACTOR + TELEPORT_TOLERANCE)
			_assert("flat_%s_stays_on_floor" % tag, "true", str(d["on_floor"]), d["on_floor"])
			print("MEASURE|flat|%s|moved=%.3f|wish=%.2f|max_frame=%.4f" % [tag, d["moved"], d["wish_speed"], d["max_frame"]])
	# 档位顺序：蹲 < 走 < 跑（两条都查）
	for cfg in [_cat, _mouse]:
		var w := await _measure_gear(cfg, "walk")
		var s := await _measure_gear(cfg, "sprint")
		var c := await _measure_gear(cfg, "crouch")
		var tag := String(cfg.species_id)
		_assert("gear_order_%s" % tag, "crouch < walk < sprint",
			"%.2f < %.2f < %.2f" % [c["moved"], w["moved"], s["moved"]],
			c["moved"] < w["moved"] and w["moved"] < s["moved"])


func _measure_gear(cfg: SpeciesConfig, gear: String) -> Dictionary:
	await _new_flat_world()
	var body := _spawn_body(_world, cfg, Vector3(0.0, cfg.capsule_half_height + 0.01, 6.0))
	await _settle(body)
	body.move_intent = Vector2(0.0, -1.0)      # 朝 −Z
	body.want_sprint = gear == "sprint"
	body.want_crouch = gear == "crouch"
	if gear == "crouch":
		await _wait(10)                        # 蹲下要一帧才生效（headroom 检查）
	var res := await _drive(body, FLAT_FRAMES)
	res["wish_speed"] = body.current_speed()
	res["crouching"] = body.is_crouching
	body.move_intent = Vector2.ZERO
	body.want_sprint = false
	body.want_crouch = false
	return res


# ---------------------------------------------------------------------------
# 2) 台阶（含 T013 新判据：抬升帧不得水平瞬移）
# ---------------------------------------------------------------------------

func _phase_steps() -> void:
	print("---- 2 台阶（12/3 cm 能上；20/12 cm 被挡；抬升不瞬移） ----")
	for cfg in [_cat, _mouse]:
		var ok_h: float = cfg.max_step_height
		var blocked_h: float = 0.20 if cfg.species_id == &"Cat" else 0.12
		var tag := String(cfg.species_id)

		var ok := await _measure_step(cfg, ok_h)
		_assert("step_%s_%.0fcm_climbs" % [tag, ok_h * 100.0], "y 增益 ≈ %.3f" % ok_h,
			"%.4f" % ok["climbed"], absf(ok["climbed"] - ok_h) <= 0.01)
		_assert("step_%s_%.0fcm_on_top" % [tag, ok_h * 100.0], "> %.1f" % STEP_TARGET_X,
			"max_x=%.3f" % ok["max_x"], ok["max_x"] > STEP_TARGET_X)
		_assert("step_%s_%.0fcm_no_teleport" % [tag, ok_h * 100.0],
			"抬升帧 dxz ≤ 正常(%.4f) + %.2f" % [ok["normal_frame"], TELEPORT_TOLERANCE],
			"lift_dxz=%.4f (lift_frame=%d)" % [ok["lift_dxz"], ok["lift_frame"]],
			ok["lift_dxz"] <= ok["normal_frame"] + TELEPORT_TOLERANCE)
		_assert("step_%s_%.0fcm_lands_on_step" % [tag, ok_h * 100.0], "落点高度 ≈ 台阶顶 + 半高",
			"y=%.4f expected=%.4f" % [ok["y_after"], ok_h + cfg.capsule_half_height],
			absf(ok["y_after"] - (ok_h + cfg.capsule_half_height)) <= 0.01)
		_assert("step_%s_%.0fcm_on_floor" % [tag, ok_h * 100.0], "true", str(ok["on_floor"]), ok["on_floor"])
		print("MEASURE|step|%s|step=%.2f|lift_frame=%d|lift_dxz=%.4f|normal_frame=%.4f|climbed=%.4f|max_x=%.3f" % [
			tag, ok_h, ok["lift_frame"], ok["lift_dxz"], ok["normal_frame"], ok["climbed"], ok["max_x"]
		])

		var bad := await _measure_step(cfg, blocked_h)
		_assert("step_%s_%.0fcm_blocked_y" % [tag, blocked_h * 100.0], "climbed ≈ 0",
			"%.4f" % bad["climbed"], absf(bad["climbed"]) <= 0.01)
		_assert("step_%s_%.0fcm_blocked_x" % [tag, blocked_h * 100.0], "< 0.2",
			"max_x=%.3f" % bad["max_x"], bad["max_x"] < 0.2)
		print("MEASURE|step_blocked|%s|step=%.2f|climbed=%.4f|max_x=%.3f" % [tag, blocked_h, bad["climbed"], bad["max_x"]])
	_free_world()


func _measure_step(cfg: SpeciesConfig, step_h: float) -> Dictionary:
	await _new_world("T013Step_%s_%.2f" % [String(cfg.species_id), step_h])
	_add_box(_world, "Ground", Vector3(40.0, 1.0, 20.0), Vector3(0.0, -0.5, 0.0))
	_add_box(_world, "Step", Vector3(6.0, step_h, 6.0), Vector3(3.0, step_h * 0.5, 0.0))
	var body := _spawn_body(_world, cfg, Vector3(STEP_START_X, cfg.capsule_half_height + 0.002, 0.0))
	await _settle(body)
	if body.climb != null:
		body.climb.update_base_y()
	var y_before: float = body.global_position.y
	var normal_frame: float = cfg.walk_speed * DT
	body.move_intent = Vector2(1.0, 0.0)      # 朝 +X

	var prev: Vector3 = body.global_position
	var lift_frame := -1
	var lift_dxz := 0.0
	var max_x: float = prev.x
	var airborne := 0
	var ymin := prev.y
	var ymax := prev.y
	var ylog: Array[float] = []
	for i in 600:
		await physics_frame
		var p: Vector3 = body.global_position
		var dxz: float = Vector2(p.x - prev.x, p.z - prev.z).length()
		max_x = maxf(max_x, p.x)
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
		if not body.is_on_floor():
			airborne += 1
		if lift_frame < 0 and p.y - prev.y > 0.002:
			lift_frame = i
			lift_dxz = dxz
		if ylog.size() >= 12:
			ylog.remove_at(0)
		ylog.append(p.y)
		prev = p
		if p.x > STEP_TARGET_X and body.is_on_floor():
			break
	body.move_intent = Vector2.ZERO
	var y_after: float = body.global_position.y
	print("MEASURE|step_trace|%s|step=%.2f|y_before=%.4f|y_after=%.4f|x_end=%.3f|z_end=%.3f|ymin=%.4f|ymax=%.4f|floor=%s|floor_normal=%s|ylog=%s" % [
		String(cfg.species_id), step_h, y_before, y_after, body.global_position.x,
		body.global_position.z, ymin, ymax, "1" if body.is_on_floor() else "0",
		str(body.get_floor_normal()), str(ylog)
	])
	return {
		"climbed": y_after - y_before,
		"y_after": y_after,
		"max_x": max_x,
		"lift_frame": lift_frame,
		"lift_dxz": lift_dxz,
		"normal_frame": normal_frame,
		"on_floor": body.is_on_floor(),
		"airborne": airborne,
		"ymin": ymin,
		"ymax": ymax,
	}


# ---------------------------------------------------------------------------
# 3) 跳跃
# ---------------------------------------------------------------------------

func _phase_jump() -> void:
	print("---- 3 跳跃 ----")
	# 猫：净空 ≥ 0.50（T009 口径）
	await _new_flat_world()
	var cat := _spawn_body(_world, _cat, Vector3(0.0, _cat.capsule_half_height + 0.01, 6.0))
	await _settle(cat)
	var y0: float = cat.global_position.y
	cat.want_jump = true
	var peak := y0
	var jtrace := PackedStringArray()
	for i in 90:
		await physics_frame
		peak = maxf(peak, cat.global_position.y)
		if i < 20:
			jtrace.append("%d:y=%.3f,vy=%.2f,f=%s" % [
				i, cat.global_position.y, cat.velocity.y, "1" if cat.is_on_floor() else "0"
			])
	print("MEASURE|jump_trace|gravity=%s|jump_velocity=%.2f|y0=%.3f|peak=%.3f|%s" % [
		str(cat.get_gravity()), _cat.jump_velocity, y0, peak, " | ".join(jtrace)
	])
	_assert("jump_cat_clearance", "≥ %.2f" % CAT_JUMP_CLEARANCE, "%.4f" % (peak - y0),
		peak - y0 >= CAT_JUMP_CLEARANCE)
	_assert("jump_cat_back_on_floor", "true", str(cat.is_on_floor()), cat.is_on_floor())

	# 鼠：can_jump = false，按住跳跃也不许离地
	var mouse := _spawn_body(_world, _mouse, Vector3(2.0, _mouse.capsule_half_height + 0.01, 6.0))
	await _settle(mouse)
	var m0: float = mouse.global_position.y
	mouse.want_jump = true
	var mpeak := m0
	for i in 90:
		await physics_frame
		mouse.want_jump = true
		mpeak = maxf(mpeak, mouse.global_position.y)
	_assert("jump_mouse_cannot_jump", "低于 %.2f" % MOUSE_JUMP_EPS, "%.4f" % (mpeak - m0),
		mpeak - m0 < MOUSE_JUMP_EPS)
	_assert("jump_mouse_touched_floor", "true", str(mouse.has_touched_floor), mouse.has_touched_floor)
	print("MEASURE|jump|Mouse|max_up=%.4f|can_jump=%s" % [mpeak - m0, str(mouse.can_jump())])
	_free_world()





# ---------------------------------------------------------------------------
# 4) 25° 坡
# ---------------------------------------------------------------------------

func _phase_ramp() -> void:
	print("---- 4 25° 坡（能上、0 空中帧、不瞬移） ----")
	await _new_flat_world()
	var deg := deg_to_rad(RAMP_DEG)
	var normal := Vector3(0.0, cos(deg), sin(deg))
	var center := Vector3(0.0, GROUND_TOP, RAMP_SURFACE_AT_Z) - normal * (RAMP_SIZE.y * 0.5)
	_add_box(_world, "Ramp", RAMP_SIZE, center, Vector3(RAMP_DEG, 0.0, 0.0))
	var body := _spawn_body(_world, _cat, Vector3(0.0, GROUND_TOP + _cat.capsule_half_height + 0.02, RAMP_START_Z))
	await _settle(body)
	var y0: float = body.global_position.y
	body.move_intent = Vector2(0.0, -1.0)     # 朝 −Z 上坡
	var res := await _drive(body, 150)
	body.move_intent = Vector2.ZERO
	_assert("ramp_climbs", "y 增益 > 0.4", "%.4f" % (body.global_position.y - y0), body.global_position.y - y0 > 0.4)
	_assert("ramp_no_airborne", "0 空中帧", "%d" % res["airborne"], int(res["airborne"]) == 0)
	_assert("ramp_progresses", "> 1.5 m", "%.2f m" % res["moved"], res["moved"] > 1.5)
	_assert("ramp_no_frame_jump", "每帧 ≤ 速×dt×%.1f+%.2f" % [JUMP_FACTOR, TELEPORT_TOLERANCE],
		"max=%.4f" % res["max_frame"],
		res["max_frame"] <= _cat.walk_speed * DT * JUMP_FACTOR + TELEPORT_TOLERANCE)
	_assert("ramp_on_floor_at_end", "true", str(body.is_on_floor()), body.is_on_floor())
	print("MEASURE|ramp|y_gain=%.4f|moved=%.2f|airborne=%d|max_frame=%.4f" % [
		body.global_position.y - y0, res["moved"], res["airborne"], res["max_frame"]
	])
	_free_world()


# ---------------------------------------------------------------------------
# 5) 相机与蹲姿
# ---------------------------------------------------------------------------

func _phase_camera_stance() -> void:
	print("---- 5 相机眼高与蹲姿 ----")
	for cfg in [_cat, _mouse]:
		await _new_flat_world()
		var body := _spawn_body(_world, cfg, Vector3(0.0, cfg.capsule_half_height + 0.01, 6.0))
		await _settle(body)
		var tag := String(cfg.species_id)
		var cam := body.camera as Camera3D
		_assert_near("camera_%s_offset_y" % tag, cfg.camera_offset_z, cam.position.y, 0.001)
		_assert_near("camera_%s_offset_x" % tag, 0.0, cam.position.x, 0.001)
		_assert_near("camera_%s_offset_z_axis" % tag, 0.0, cam.position.z, 0.001)
		_assert_near("camera_%s_fov" % tag, cfg.fov, cam.fov, 0.001)
		var stand_h := (body.shape_node.shape as CapsuleShape3D).height
		# 蹲下
		body.want_crouch = true
		await _wait(10)
		_assert("stance_%s_crouches" % tag, "true", str(body.is_crouching), body.is_crouching)
		var crouch_h := (body.shape_node.shape as CapsuleShape3D).height
		_assert_near("stance_%s_capsule_crouch_h" % tag, cfg.crouch_height(), crouch_h, 0.001)
		_assert_near("stance_%s_capsule_drop" % tag, 2.0 * cfg.crouch_drop(), stand_h - crouch_h, 0.001)
		_assert_near("stance_%s_camera_drop" % tag, cfg.crouch_drop(),
			cfg.camera_offset_z - cam.position.y, 0.001)
		_assert_near("stance_%s_mesh_matches_capsule" % tag, crouch_h, (body.body_mesh.mesh as CapsuleMesh).height, 0.001)
		# 站起来（平地头顶够）
		body.want_crouch = false
		await _wait(10)
		_assert("stance_%s_stands_again" % tag, "true", str(not body.is_crouching), not body.is_crouching)
		_assert_near("stance_%s_capsule_stand_h" % tag, cfg.capsule_height(),
			(body.shape_node.shape as CapsuleShape3D).height, 0.001)
		print("MEASURE|stance|%s|stand_h=%.3f|crouch_h=%.3f|camera_drop=%.3f" % [
			tag, stand_h, cfg.crouch_height(), cfg.crouch_drop()
		])
	_free_world()


# ---------------------------------------------------------------------------
# 6) 鼠洞通道（生态灰盒关卡：鼠能过、猫被挡）
# ---------------------------------------------------------------------------

func _phase_mouse_tunnel_lane() -> void:
	print("---- 6 鼠洞车道（l_courtyard：鼠穿 0.24 洞 / 猫被挡） ----")
	_free_world()
	var packed: PackedScene = load(COURTYARD)
	if packed == null:
		_assert("courtyard_loads", "PackedScene", "null", false)
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	await _wait(5)

	# 鼠：从北侧穿洞到南侧
	var mouse := _spawn_body(_world, _mouse, Vector3(HOLE_X, GROUND_TOP + _mouse.capsule_half_height + 0.02, LANE_START_Z))
	await _settle(mouse)
	mouse.move_intent = Vector2(0.0, -1.0)
	var mres := await _drive(mouse, 300)
	mouse.move_intent = Vector2.ZERO
	_assert("tunnel_mouse_crosses", "终点 z ≤ %.1f" % BARRIER_Z_MIN, "z=%.3f" % mouse.global_position.z,
		mouse.global_position.z <= BARRIER_Z_MIN)
	_assert("tunnel_mouse_y_stable", "y 波动 ≤ 0.02", "%.4f" % mres["y_span"], mres["y_span"] <= 0.02)
	_assert("tunnel_mouse_no_airborne", "0 空中帧", "%d" % mres["airborne"], int(mres["airborne"]) == 0)
	_assert("tunnel_mouse_no_overlap", "0 重叠", "%d" % _overlaps_world(mouse), _overlaps_world(mouse) == 0)
	print("MEASURE|tunnel|Mouse|end_z=%.3f|moved=%.2f|y_span=%.4f|airborne=%d" % [
		mouse.global_position.z, mres["moved"], mres["y_span"], mres["airborne"]
	])

	# 猫：同一车道被挡（不得进洞）
	var cat := _spawn_body(_world, _cat, Vector3(HOLE_X, GROUND_TOP + _cat.capsule_half_height + 0.02, LANE_START_Z))
	await _settle(cat)
	cat.move_intent = Vector2(0.0, -1.0)
	var cres := await _drive(cat, 300)
	cat.move_intent = Vector2.ZERO
	var end_z: float = cat.global_position.z
	_assert("tunnel_cat_blocked", "终点 z ≥ %.1f" % (BARRIER_Z_MAX - 0.1), "z=%.3f" % end_z,
		end_z >= BARRIER_Z_MAX - 0.1)
	_assert("tunnel_cat_never_in_hole", "0 帧在洞里", "%d" % cres["frames_in_hole"], int(cres["frames_in_hole"]) == 0)
	_assert("tunnel_cat_no_overlap", "0 重叠", "%d" % _overlaps_world(cat), _overlaps_world(cat) == 0)
	_assert("tunnel_cat_no_airborne", "0 空中帧", "%d" % cres["airborne"], int(cres["airborne"]) == 0)
	print("MEASURE|tunnel|Cat|end_z=%.3f|moved=%.2f|frames_in_hole=%d|airborne=%d" % [
		end_z, cres["moved"], cres["frames_in_hole"], cres["airborne"]
	])
	_free_world()


# ---------------------------------------------------------------------------
# 驱动与采样
# ---------------------------------------------------------------------------

## 逐帧采样驱动：位置/水平位移/空中帧/进洞帧，返回统计
func _drive(body: AnimalBody, frames: int) -> Dictionary:
	var prev: Vector3 = body.global_position
	var start := prev
	var ymin := prev.y
	var ymax := prev.y
	var max_frame := 0.0
	var moved := 0.0
	var airborne := 0
	var frames_in_hole := 0
	var worst_overlap := 0
	for i in frames:
		await physics_frame
		var p: Vector3 = body.global_position
		var dxz: float = Vector2(p.x - prev.x, p.z - prev.z).length()
		max_frame = maxf(max_frame, dxz)
		moved += p.distance_to(prev)
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
		if not body.is_on_floor():
			airborne += 1
		if absf(p.x - HOLE_X) <= 0.25 and p.z >= BARRIER_Z_MIN and p.z <= BARRIER_Z_MAX:
			frames_in_hole += 1
		worst_overlap = maxi(worst_overlap, _overlaps_world(body))
		prev = p
	return {
		"start": start,
		"end": prev,
		"moved": moved,
		"max_frame": max_frame,
		"y_span": ymax - ymin,
		"airborne": airborne,
		"frames_in_hole": frames_in_hole,
		"overlaps": worst_overlap,
		"on_floor": body.is_on_floor(),
	}


## 等到**真的**站稳：连续 `STABLE_FRAMES` 帧在地面上且速度接近 0。
##
## 为什么必须"连续"（本任务实测踩到）：只判一帧会被"出生瞬间刚好落地、下一帧又被顶起来"骗过去，
## 于是 `y_before` 取到半空中的高度，台阶/跳跃的增益全被算错（曾出现"上了台阶 y 反而下降"的假数据）。
## 连续站不稳时**明确报错并打印轨迹**，不允许静默继续。
func _settle(body: AnimalBody) -> void:
	body.move_intent = Vector2.ZERO
	var stable := 0
	var trace := PackedStringArray()
	for i in 300:
		await physics_frame
		var v: Vector3 = body.velocity
		var still: bool = body.is_on_floor() and absf(v.y) < 0.05 and Vector2(v.x, v.z).length() < 0.05
		if i < 30:
			trace.append("%d:y=%.3f,vy=%.2f,f=%s" % [
				i, body.global_position.y, v.y, "1" if body.is_on_floor() else "0"
			])
		if still:
			stable += 1
			if stable >= STABLE_FRAMES:
				return
		else:
			stable = 0
	print("MEASURE|settle_failed|y=%.4f|vy=%.3f|floor=%s|trace=%s" % [
		body.global_position.y, body.velocity.y, "1" if body.is_on_floor() else "0", " | ".join(trace)
	])


# ---------------------------------------------------------------------------
# 场景/身体搭建
# ---------------------------------------------------------------------------
func _new_flat_world() -> void:
	await _new_world("T013Flat")
	_add_box(_world, "Ground", Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0))


func _new_world(tag: String) -> void:
	_free_world()
	_world = Node3D.new()
	_world.name = tag
	root.add_child(_world)
	await _wait(2)


## 释放当前临时世界（下一个用例用全新世界，杜绝用例互相污染）
func _free_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		_world = null


func _add_box(parent: Node3D, name: String, size: Vector3, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = name
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	parent.add_child(sb)
	sb.global_position = pos
	sb.rotation_degrees = rot_deg
	return sb


func _spawn_body(world: Node3D, cfg: SpeciesConfig, pos: Vector3) -> AnimalBody:
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = false          # 由本测试直接写意图（不读真实输入）
	world.add_child(body)
	body.global_position = pos
	body.velocity = Vector3.ZERO
	if body.climb != null:
		body.climb.reset_base()
	return body


func _overlaps_world(body: CharacterBody3D) -> int:
	var cs := body.get_node("CollisionShape3D") as CollisionShape3D
	var src := cs.shape as CapsuleShape3D
	var shape := CapsuleShape3D.new()
	shape.radius = maxf(0.001, src.radius - OVERLAP_SHRINK)
	shape.height = maxf(0.002, src.height - OVERLAP_SHRINK * 2.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = body.global_transform
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(params, 16).size()


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	var a := float(actual)
	_assert(id, "%.4f ±%.4f" % [expected, eps], "%.4f" % a, absf(a - expected) <= eps)


func _assert_range(id: String, lo: float, hi: float, actual: float) -> void:
	_assert(id, "[%.2f, %.2f]" % [lo, hi], "%.3f" % actual, actual >= lo and actual <= hi)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
