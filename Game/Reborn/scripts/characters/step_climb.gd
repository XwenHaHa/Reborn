class_name StepClimb
extends RefCounted
## 台阶抬升组件（Godot 4）
##
## 为什么需要它：Godot 的 `CharacterBody3D` **没有** UE `MaxStepHeight` 的等价物，
## `move_and_slide()` 不会自动上台阶。`Parameters.md` 要求猫能上 12 cm、鼠能上 3 cm，
## 所以必须自实现（P1 最高技术风险，已在 `tests/probe_step_height.gd` 实测 6/6 通过）。
##
## 本文件是**同一算法**的组件化版本，供 T009/T010 的移动控制器直接调用：
##   `var climb := StepClimb.new(self, config.max_step_height)`
##   `climb.update_base_y()` 每物理帧调一次；用 `climb.step_or_slide(motion, delta)` 代替 `move_and_slide()`。
##
## 实测根因（见 `Docs/Evidence/T009-probe.md`）：
##   胶囊底部是半球。面对台阶时它停在"底心仍在台阶面左侧、圆底蹭到台阶顶棱"的位置，
##   向下探测命中的是**棱角**（法线约 60° 偏离竖直），超出 Godot 默认 `floor_max_angle`(45°)，
##   引擎判定为墙面、不可站立。因此判据不能只看"下落有没有命中"。
##
## 判据（三条同时成立）：
##   1. 头顶有抬高空间
##   2. 抬高并前移后不被阻挡（否则台阶高于阈值）
##   3. 下落命中，且**存在可站立的接触面**（`n.y >= cos(floor_max_angle)`），
##      并且落点相对**当前落脚面**的抬升 ∈ (0, max_step + tolerance]
##
##   4. **落点高度必须来自接触面**（`_landing_y`），不能直接用运动测试的位移：
##      实测运动测试会在接触前停下，形状越小停得越早（鼠半径 0.06 高 2.655 mm、猫 0.16 高 0.249 mm），
##      直接用会把小物种的 3 cm 台阶算成 3.26 cm 而被上界拒绝。详见 `_landing_y` 注释。
## 两个实测校准过的量（不要凭直觉改小）：
##   * `probe_raise = max_step * 2 + 0.05`：抬高量必须**大于台阶高度本身**。
##     胶囊圆底蹭在台阶顶棱上时底心低于台阶顶，只抬 `max_step` 抬不过棱角。放宽抬高量**不会**放过更高台阶：
##     过高台阶会在"抬高后仍被挡"或最终 `total_gain` 上界被拒。
##   * `probe_forward = radius_safe + 本帧位移`：前移量必须让**胶囊底心越过台阶竖直面**，
##     否则下探永远撞在顶棱上。默认 `radius_safe = 0.20`，略大于目前最大胶囊半径（猫 0.16）。

## 被驱动的角色体（必须已在场景树内，才可做物理探针）
var body: CharacterBody3D
## 本物种可上台阶高度（米）—— 来自 `SpeciesConfig.max_step_height`
var max_step_height: float
## 落点抬升的容差（米）。由 `sweep_tolerance` 实测标定后固定，见探针文件末尾的标定记录
var tolerance: float = 0.002
## 探测前移量下限（米）
var radius_safe: float = 0.20
## 可站立面判据（度）。与 Godot 默认 `floor_max_angle` 一致
var floor_max_angle_deg: float = 45.0

## 当前所站的平面高度。只在真正站定时更新，避免被棘轮过程带偏
var _base_y: float = INF

## 上一次尝试的诊断信息（供调试与测试读取，不改行为）
var last_probe: Dictionary = {}


func _init(p_body: CharacterBody3D, p_max_step_height: float,
		p_tolerance: float = 0.002, p_radius_safe: float = 0.20) -> void:
	body = p_body
	max_step_height = p_max_step_height
	tolerance = p_tolerance
	radius_safe = p_radius_safe


## 复位落脚面基准（换试验世界/传送后调用）
func reset_base() -> void:
	_base_y = INF


## 跟踪"当前所站的平面高度"。每物理帧调用一次。
## 注意：不能要求 `velocity < 0.05`——抬升分支里清零速度后 `move_and_slide()`
## 会重新写入速度，条件不稳定，曾导致 `_base_y` 一直是 INF（已实测踩到）。
func update_base_y() -> void:
	if body.is_on_floor():
		_base_y = body.global_position.y


## 尝试上一级台阶：成功则**已把 body 放到台阶顶面**并返回 true；失败返回 false（调用方照常水平推进）。
func try_step_up(motion: Vector3) -> bool:
	last_probe = {}
	var flat := Vector3(motion.x, 0.0, motion.z)
	if flat.length() < 0.000001:
		return false

	var y_start: float = body.global_position.y
	var base: float = _base_y if is_finite(_base_y) else y_start

	# 前方必须有障碍（否则不是台阶场景）
	var flat_res := _test_motion(flat)
	if flat_res == null:
		return false
	# 障碍是"可站立面"（斜坡、台阶顶面）时**不做台阶判断**，交给 move_and_slide 顺着坡走。
	# 依据（T009 实测）：25° 坡若按台阶处理，每帧都会瞬移 `radius_safe` 米（0.2 m/帧），
	#   猫沿坡"飞"上去再摔下来（实测 2.66 m/s、坡顶越界、坡上不落地）。
	if _blocked_by_walkable_surface(flat_res, flat):
		last_probe = {"reason": "walkable_surface"}
		return false

	# 抬高量必须大于台阶本身（见文件头说明）
	var probe_raise: float = max_step_height * 2.0 + 0.05
	# 头顶空间：抬这么高会顶到天花板就放弃（低顶下不应上台阶）
	if body.test_move(body.global_transform, Vector3.UP * probe_raise):
		last_probe = {"reason": "no_headroom"}
		return false

	var raised := body.global_transform.translated(Vector3.UP * probe_raise)

	# 前移量必须让胶囊底心越过台阶竖直面（见文件头说明）
	var forward_dist: float = flat.length()
	var probe_forward: float = radius_safe + forward_dist
	var fwd_dir: Vector3 = flat.normalized()
	var forward := raised.translated(fwd_dir * probe_forward)
	if body.test_move(raised, fwd_dir * probe_forward):
		last_probe = {"reason": "blocked_after_raise"}
		return false  # 抬起后仍被挡 → 台阶高于阈值

	# 下落探测：落点用"真实接触面高度"算（不要用 get_travel()，理由见 _landing_y）
	var params := PhysicsTestMotionParameters3D.new()
	params.from = forward
	params.motion = Vector3.DOWN * (probe_raise + 0.5)
	params.margin = 0.001
	params.max_collisions = 8
	var res := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), params, res):
		last_probe = {"reason": "no_ground"}
		return false  # 前方悬空

	var landed_y: float = _landing_y(res, forward)
	if not is_finite(landed_y):
		last_probe = {"reason": "no_walkable_face"}
		return false

	var total_gain: float = landed_y - base
	last_probe = {"gain": total_gain, "landed_y": landed_y, "base": base}
	if total_gain <= 0.0 or total_gain > max_step_height + tolerance:
		return false

	# **只抬 y**：水平位置不在这一帧改动，交给本帧的 `move_and_slide()` 推进（T013 修，见 step_or_slide 说明）
	body.global_position = Vector3(body.global_position.x, landed_y, body.global_position.z)
	return true


## 便利封装：能上台阶就**只抬 y**，本帧的水平推进**照常交给 `move_and_slide()`**；不能上就按原速度滑。
## 返回是否发生了抬升。`delta` 为物理帧长（用于把位移换算成速度，保持原有速度语义）。
##
## 为什么抬升后仍要 `move_and_slide()`（T013 修，遗留项 ①）：
##   旧实现抬升成功后**把身体瞬移到 `radius_safe + 本帧位移` 处并把速度清零**，
##   实测表现为"上台阶时水平前移 0.2 m"（`Docs/Evidence/T009.md` §5.3）。
##   改成"只抬 y + 正常前推"后，抬升帧的水平位移 = 该帧正常位移（量化判据见 `Docs/Evidence/T013.md`）。
func step_or_slide(motion: Vector3, delta: float) -> bool:
	var stepped := try_step_up(motion)
	if delta > 0.0:
		body.velocity = Vector3(motion.x / delta, body.velocity.y, motion.z / delta)
	body.move_and_slide()
	return stepped


## 由下落探测结果算出"身体会被放在的高度"（米）。找不到可站立面返回 -INF。
##
## 为什么不用 `res.get_travel()`（这里踩过一次真坑，别改回去）：
##   实测运动测试会在**接触前**停下，而且**形状越小停得越早**：同一个 3 cm 台阶，
##   鼠（半径 0.06）停下的高度比真实面高 **2.655 mm**，猫（半径 0.16）只高 0.249 mm
##   （`Docs/Evidence/T009.md` 诊断表）。若直接拿"停下高度"当落点，鼠的 3 cm 台阶会被
##   算成 3.26 cm，超过上界 `max_step + tolerance` 而被拒绝 —— 鼠永远上不了自己的台阶。
##   接触点 + 法线给出的是**真实平面高度**，与形状大小无关，所以改成这条路径。
func _landing_y(res: PhysicsTestMotionResult3D, forward: Transform3D) -> float:
	var min_walkable_ny: float = cos(deg_to_rad(floor_max_angle_deg))
	var cap := _body_capsule()
	var walkable := false
	var best := -INF
	for i in res.get_collision_count():
		var n: Vector3 = res.get_collision_normal(i)
		if n.y < min_walkable_ny:
			continue
		walkable = true
		var p: Vector3 = res.get_collision_point(i)
		# 平面方程 n·(x−p)=0 → 解出该接触面在**胶囊轴线 (x,z)** 处的高度
		var plane_y: float = p.y
		if n.y > 0.000001:
			plane_y = p.y - (n.x * (forward.origin.x - p.x) + n.z * (forward.origin.z - p.z)) / n.y
		if cap == null:
			best = maxf(best, plane_y)
			continue
		# 球底贴在斜面上时，球心沿法线再抬高 r/n.y：
		# 身体中心 = 平面高度 + 半高 + r(1/n.y − 1)。平面时 r(1/n.y−1)=0 → 就是"面高 + 半高"。
		var rest_y: float = plane_y + cap.height * 0.5 + cap.radius * (1.0 / n.y - 1.0)
		best = maxf(best, rest_y)
	if not walkable:
		return -INF
	# 退化路径：身体不是胶囊（没有半高概念）时，退回旧的"位移法"，保持原行为
	if cap == null:
		return forward.origin.y + res.get_travel().y
	return best


## 取身体当前的胶囊形状（蹲下时高度会变，所以每次都重新取，不能缓存）。
## 找不到（非胶囊形体）时返回 null。
func _body_capsule() -> CapsuleShape3D:
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs != null and cs.shape is CapsuleShape3D:
			return cs.shape as CapsuleShape3D
	return null


## 跑一次运动测试：未被挡住（可以走完 motion）返回 null，否则返回结果（含碰撞法线）
func _test_motion(motion: Vector3) -> PhysicsTestMotionResult3D:
	var params := PhysicsTestMotionParameters3D.new()
	params.from = body.global_transform
	params.motion = motion
	params.margin = 0.001
	params.max_collisions = 8
	var res := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), params, res):
		return null
	return res


## 本次水平运动是否被**可站立面**挡住（= 前方是斜坡/地面，应交给 move_and_slide 顺着坡走，
## 不该按台阶处理）。
##
## 关键细节（踩过一次，别简化）：**必须只看"真正阻挡本次运动"的接触**（`n·dir < 0`），
## 否则脚下地面的接触（法线竖直、点积 0）也会被判成"可站立面"，于是猫再也上不了任何台阶
## （T008 的 12 cm/3 cm 用例会直接失败）。
func _blocked_by_walkable_surface(res: PhysicsTestMotionResult3D, dir: Vector3) -> bool:
	var min_ny: float = cos(deg_to_rad(floor_max_angle_deg))
	var d: Vector3 = dir.normalized()
	for i in res.get_collision_count():
		var n: Vector3 = res.get_collision_normal(i)
		if n.dot(d) > -0.05:
			continue
		if n.y >= min_ny:
			return true
	return false
