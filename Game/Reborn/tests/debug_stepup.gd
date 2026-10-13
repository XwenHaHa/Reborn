extends SceneTree
## 精确诊断：对 Cat/12cm 用例，逐个前置条件打印通过与否，
## 找出 _try_step_up 到底在哪一步拒绝。

const STEP := 0.12
const MAX_STEP := 0.12
const RADIUS := 0.16
const HALF_H := 0.24


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	await process_frame
	_add_box(world, "Ground", Vector3(40, 1.0, 20), Vector3(0, -0.5, 0))
	_add_box(world, "Step", Vector3(6.0, STEP, 6.0), Vector3(3.0, STEP * 0.5, 0))

	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HALF_H * 2.0
	col.shape = cap
	body.add_child(col)
	body.position = Vector3(-1.0, HALF_H + 0.002, 0)
	world.add_child(body)

	await process_frame
	for i in 40:
		body.velocity = Vector3.ZERO
		await physics_frame

	print("D|settled y=%.4f  on_floor=%s" % [body.global_position.y, body.is_on_floor()])
	print("D|台阶: x 从 0.0 起, 顶面 y=%.3f" % STEP)

	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var motion := Vector3(1.0 * dt, 0.0, 0.0)
	var traced := false

	for i in 400:
		var y0 := body.global_position.y
		var ok := _diagnose(body, motion, y0)
		if ok:
			body.global_position = body.global_position  # 位置已在里面设置
		else:
			body.velocity = motion / dt
			body.move_and_slide()
		# 接近台阶就诊断一次，然后停
		if not traced and body.global_position.x > -0.20:
			traced = true
			print("D|=== 诊断点 x=%.4f y=%.4f ===" % [body.global_position.x, body.global_position.y])
			_diagnose(body, motion, body.global_position.y)
		if body.global_position.x >= 1.0:
			print("D|END x=%.4f y=%.4f" % [body.global_position.x, body.global_position.y])
			break
		await physics_frame

	quit(0)


func _diagnose(body: CharacterBody3D, motion: Vector3, y_start: float) -> bool:
	var flat := Vector3(motion.x, 0.0, motion.z)
	var pos := body.global_position
	print("D|  x=%.4f y=%.4f | 胶囊底=%.4f 顶=%.4f | 前缘 x=%.4f" % [
		pos.x, pos.y, pos.y - HALF_H, pos.y + HALF_H, pos.x + RADIUS
	])

	# 条件 1：前方有障碍
	var has_obstacle := body.test_move(body.global_transform, flat)
	print("D|  1) test_move(flat) 有障碍 = %s" % has_obstacle)
	if not has_obstacle:
		print("D|  => 拒绝于【条件1：前方无障碍】")
		return false

	# 条件 2：障碍距离 ≤ max_step
	var probe := PhysicsTestMotionParameters3D.new()
	probe.from = body.global_transform
	probe.motion = flat
	probe.margin = 0.001
	var pr := PhysicsTestMotionResult3D.new()
	var hit := PhysicsServer3D.body_test_motion(body.get_rid(), probe, pr)
	var moved: float = pr.get_travel().length() if hit else flat.length()
	var gap: float = flat.length() - moved
	print("D|  2) 障碍距离 gap=%.4f (max_step=%.4f) hit=%s" % [gap, MAX_STEP, hit])
	if gap > MAX_STEP:
		print("D|  => 拒绝于【条件2：障碍距离 %.4f > %.4f】" % [gap, MAX_STEP])
		return false

	# 条件 3：头顶空间
	var up_blocked := body.test_move(body.global_transform, Vector3.UP * MAX_STEP)
	print("D|  3) test_move(up %.2f) 被挡 = %s" % [MAX_STEP, up_blocked])
	if up_blocked:
		print("D|  => 拒绝于【条件3：头顶空间不足】")
		return false

	# 条件 4：抬起后前进
	var raised := body.global_transform.translated(Vector3.UP * MAX_STEP)
	var fwd_blocked := body.test_move(raised, flat)
	print("D|  4) 抬起后 test_move(flat) 被挡 = %s" % fwd_blocked)
	if fwd_blocked:
		print("D|  => 拒绝于【条件4：抬起后仍被挡（台阶高于阈值）】")
		return false

	# 条件 5：下落找落点
	var forward := raised.translated(flat)
	var params := PhysicsTestMotionParameters3D.new()
	params.from = forward
	params.motion = Vector3.DOWN * (MAX_STEP + 0.01)
	params.margin = 0.001
	var res := PhysicsTestMotionResult3D.new()
	var hit_down := PhysicsServer3D.body_test_motion(body.get_rid(), params, res)
	print("D|  5) 下落命中 = %s" % hit_down)
	if not hit_down:
		print("D|  => 拒绝于【条件5：前方悬空无落点】")
		return false

	var landed_y: float = forward.origin.y + res.get_travel().y
	print("D|     落点 y=%.4f (胶囊底=%.4f, 台阶顶=%.3f) travel.y=%.4f" % [
		landed_y, landed_y - HALF_H, STEP, res.get_travel().y
	])
	return false  # 只诊断，不改变位置


func _add_box(parent: Node3D, nm: String, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	body.add_child(col)
	parent.add_child(body)
