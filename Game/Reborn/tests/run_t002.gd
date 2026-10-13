extends SceneTree
## T002 无头验收脚本
##
## 为什么用 SceneTree 而不是一个 Node 场景：
##   用 `--script` 直接驱动，不依赖主场景的 _ready 时序，退出码可控，
##   可在 CI/agent 环境中完全无人值守运行。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t002.gd'
##
## 退出码：0 = 全部断言通过；1 = 有失败。stdout 每条一行 ASSERT|。
##
## 断言覆盖 Bootstrap T002 的验收点：
##   - 地面是 10 m x 10 m（1000 cm x 1000 cm）
##   - PlayerStart 在地面上方且无碰撞重叠
##   - PIE 等价：物理步进后玩家落到地面、不穿透
##   - 地面碰撞生效（is_on_floor）
##   - 停止后无残留速度
## 单位：米。

const LAB := "res://scenes/maps/l_movement_lab.tscn"
const EPS := 0.01  # 1 cm

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	print("TEST|run_t002|engine=%s" % Engine.get_version_info().string)
	print("TEST|physics_ticks_per_second=%d" % Engine.physics_ticks_per_second)

	var packed: PackedScene = load(LAB)
	if packed == null:
		_assert("lab_scene_loads", "PackedScene", "null", false)
		_finish()
		return
	_assert("lab_scene_loads", "PackedScene", "PackedScene", true)

	var lab: Node = packed.instantiate()
	root.add_child(lab)

	# 必须等节点真正进入场景树：add_child 之后同一帧内 get_global_transform()
	# 仍会失败（!is_inside_tree），读到的是零变换。
	# 这里用条件轮询而不是固定帧数——固定帧数在首次运行（需生成 .godot 缓存）
	# 时会不够，曾实测出一次间歇性失败。轮询把时序依赖彻底去掉。
	var entered: bool = await _await_condition(
		func() -> bool: return (lab.get_node_or_null("Player") as Node3D).is_inside_tree(),
		600,
	)
	_assert("player_entered_tree", "true", str(entered), entered)

	_check_ground_scale(lab)
	_check_spawn_clearance(lab)

	# 模拟 PIE 运行：轮询等玩家真正落地，而不是赌固定帧数够用。
	# 1.5 m 自由落体约 0.49 s；给 600 physics 帧（10 s）的宽裕上限。
	var landed: bool = await _await_condition(
		func() -> bool: return (lab.get_node_or_null("Player") as CharacterBody3D).is_on_floor(),
		600,
	)
	_assert("player_landed_within_timeout", "true", str(landed), landed)
	_check_landed(lab)

	# 停止后检查残余速度
	await _run_physics_steps(20)
	_check_rest(lab)

	lab.queue_free()
	_finish()


## 轮询等待条件成立，最多 max_steps 个 physics 帧。返回条件是否在期限内成立。
func _await_condition(predicate: Callable, max_steps: int) -> bool:
	for i in max_steps:
		if predicate.call():
			return true
		await physics_frame
	return predicate.call()


func _check_ground_scale(lab: Node) -> void:
	var shape_node := lab.get_node_or_null("Ground/GroundShape") as CollisionShape3D
	if shape_node == null:
		_assert("ground_shape_exists", "CollisionShape3D", "null", false)
		return
	var box := shape_node.shape as BoxShape3D
	if box == null:
		_assert("ground_shape_is_box", "BoxShape3D", "other", false)
		return
	_assert("ground_shape_is_box", "BoxShape3D", "BoxShape3D", true)
	# 1000 cm x 1000 cm -> 10 m x 10 m
	_assert_near("ground_size_x_m", 10.0, box.size.x, EPS)
	_assert_near("ground_size_z_m", 10.0, box.size.z, EPS)

	var mesh_node := lab.get_node_or_null("Ground/GroundMesh") as MeshInstance3D
	if mesh_node != null and mesh_node.mesh is BoxMesh:
		var bm := mesh_node.mesh as BoxMesh
		_assert_near("ground_mesh_size_x_m", 10.0, bm.size.x, EPS)
		_assert_near("ground_mesh_size_z_m", 10.0, bm.size.z, EPS)


## PlayerStart 必须在地面上方且与地面无碰撞重叠。
## 用真实物理查询（不是拿坐标自己算），才是有效证据。
func _check_spawn_clearance(lab: Node) -> void:
	var start := lab.get_node_or_null("PlayerStart") as Marker3D
	if start == null:
		_assert("player_start_exists", "Marker3D", "null", false)
		return
	_assert("player_start_exists", "Marker3D", "Marker3D", true)

	var player := lab.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		_assert("player_exists", "CharacterBody3D", "null", false)
		return
	_assert("player_exists", "CharacterBody3D", "CharacterBody3D", true)

	# 玩家实际位置必须与 PlayerStart 一致（不是写了没用上）
	var d: float = player.global_position.distance_to(start.global_position)
	_assert_near("player_at_start_m", 0.0, d, EPS)

	# 高于地面：地面顶面在 y=0.1（厚 0.2 居中于 0），胶囊半高 0.24
	_assert(
		"spawn_above_ground",
		"> 0.34 (ground top 0.10 + half height 0.24)",
		"%.3f" % player.global_position.y,
		player.global_position.y > 0.34,
	)

	# 真实重叠检测：胶囊与 world_static 层不应有交叠
	var space := player.get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var col := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	params.shape = col.shape
	params.transform = Transform3D(Basis(), player.global_position)
	params.collision_mask = 1  # world_static
	params.collide_with_bodies = true
	var res: Array[Dictionary] = space.intersect_shape(params, 4)
	_assert(
		"spawn_no_overlap_with_world_static",
		"0 overlaps",
		"%d overlaps" % res.size(),
		res.is_empty(),
	)


func _check_landed(lab: Node) -> void:
	var player := lab.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		return
	var on_floor: bool = player.is_on_floor()
	_assert("player_on_floor_after_steps", "true", str(on_floor), on_floor)

	# 落地后 y 应接近 地面顶 0.10 + 半高 0.24 = 0.34
	var y: float = player.global_position.y
	_assert_near("player_landed_y_m", 0.34, y, 0.02)

	# 未穿透地面：y 不得低于地面顶面
	_assert("player_not_through_ground", "y >= 0.10", "%.3f" % y, y >= 0.10)

	# 水平方向不应漂移
	var drift: float = Vector2(player.global_position.x, player.global_position.z).length()
	_assert("player_no_horizontal_drift", "< 0.01 m", "%.4f" % drift, drift < 0.01)


func _check_rest(lab: Node) -> void:
	var player := lab.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		return
	var v: Vector3 = player.velocity
	_assert(
		"player_at_rest",
		"|velocity| < 0.05 m/s",
		"%.4f" % v.length(),
		v.length() < 0.05,
	)


func _run_physics_steps(count: int) -> void:
	for i in count:
		await physics_frame


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	var ok: bool = absf(expected - actual) <= eps
	_assert(
		id,
		"%.4f (±%.3f)" % [expected, eps],
		"%.4f" % actual,
		ok,
	)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _failures])
	print("RESULT|%s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)
