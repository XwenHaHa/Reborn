extends SceneTree
## v5 逻辑逐步诊断：在真实被挡位置打印每一步条件与落点法线。

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

	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var motion := Vector3(1.0 * dt, 0.0, 0.0)
	var base: float = body.global_position.y
	print("V|base=%.4f 台阶顶=%.3f max_step=%.3f" % [base, STEP, MAX_STEP])

	var blocked := 0
	var prev_x := body.global_position.x
	var printed := 0
	for i in 600:
		body.velocity = motion / dt
		body.move_and_slide()
		await physics_frame
		var dx: float = body.global_position.x - prev_x
		prev_x = body.global_position.x
		if dx < motion.x * 0.1:
			blocked += 1
		else:
			blocked = 0
		if blocked >= 3 and printed < 3:
			printed += 1
			_diag(body, motion, base)
		if blocked >= 5:
			break

	print("V|END x=%.4f y=%.4f" % [body.global_position.x, body.global_position.y])
	quit(0)


func _diag(body: CharacterBody3D, motion: Vector3, base: float) -> void:
	var flat := Vector3(motion.x, 0.0, motion.z)
	var p := body.global_position
	print("V|--- 诊断 @ x=%.4f y=%.4f 前缘=%.4f ---" % [p.x, p.y, p.x + RADIUS])

	var c1 := body.test_move(body.global_transform, flat)
	print("V| 1) 前方有障碍 = %s" % c1)
	if not c1:
		return

	var probe_raise: float = MAX_STEP * 2.0 + 0.05
	var c2 := body.test_move(body.global_transform, Vector3.UP * probe_raise)
	print("V| 2) 头顶抬 %.3f 被挡 = %s" % [probe_raise, c2])

	var raised := body.global_transform.translated(Vector3.UP * probe_raise)
	var c3 := body.test_move(raised, flat)
	print("V| 3) 抬起后前进被挡 = %s" % c3)

	var forward := raised.translated(flat)
	var params := PhysicsTestMotionParameters3D.new()
	params.from = forward
	params.motion = Vector3.DOWN * (probe_raise + 0.5)
	params.margin = 0.001
	params.max_collisions = 8
	var res := PhysicsTestMotionResult3D.new()
	var hit := PhysicsServer3D.body_test_motion(body.get_rid(), params, res)
	print("V| 4) 下落命中 = %s  碰撞数=%d" % [hit, res.get_collision_count()])
	var landed_y: float = forward.origin.y + res.get_travel().y
	for i in res.get_collision_count():
		var n: Vector3 = res.get_collision_normal(i)
		var pt: Vector3 = res.get_collision_point(i)
		print("V|     #%d normal=(%.3f, %.3f, %.3f) n.y=%.3f 可站立=%s point=(%.4f, %.4f, %.4f)" % [
			i, n.x, n.y, n.z, n.y, n.y >= cos(deg_to_rad(45.0)), pt.x, pt.y, pt.z
		])
	print("V| 5) 落点 y=%.4f 总增益=%.4f (上界 %.4f)" % [
		landed_y, landed_y - base, MAX_STEP + 0.002
	])


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
