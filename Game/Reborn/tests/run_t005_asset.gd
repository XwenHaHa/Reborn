extends SceneTree
## T005 无头验收脚本：静态资产往返（Blender → glTF → Godot）
##
## 验收的不是"文件存在"，而是**引擎读回的真实数据**：
##   A) 资产层：导入网格的 AABB 尺寸 = 1.000 m；对象名保留；轴向映射与实测一致；材质随资产往返
##   B) 运行层：用**导入网格的 AABB** 造静态碰撞体，猫胶囊落到平地与落到 1 m 立方体顶，
##              两次落点高度差 = 1.00 m（≤2 cm）。这才是"碰撞在运行中正确"。
##   C) 场景层：资产已接入 l_movement_lab（对照 100 cm 标尺），且不挡出生点
##
## 为什么轴向断言写 (0,0,+2) 而不是 (0,0,-2)：
##   实测（2026-10-13，见 Docs/Evidence/T005.md）：Blender (x, y, z) → Godot (x, z, -y)。
##   即 Blender 的 **-Y（前）** 映射到 Godot 的 **+Z（身后）**。
##   Docs/BlenderPipeline.md 原表格把这两者写成"对应"，本次**用实测改正**了该文档。
##   断言写实测值，防止以后有人"顺手改回记忆中的样子"。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t005_asset.gd' --quit-after 20000
## 退出码：0 = 全部断言通过；1 = 有失败。

const ASSET := "res://assets/tests/sm_probe_cube.glb"
const LAB := "res://scenes/maps/l_movement_lab.tscn"

const EPS := 0.01          # 1 cm：E02 要求的尺寸/位置容差
const EPS_DROP := 0.02     # 落点高度差容差（物理接触有微穿透余量）
const HALF_HEIGHT := 0.24  # Cat 胶囊半高（Parameters.md 24 cm）
const RADIUS := 0.16       # Cat 胶囊半径（16 cm）
const GROUND_TOP := 0.10   # 试验世界地面顶面（与 lab 一致）

## Blender 侧建模用的反照率（**线性**空间，见 Tools/Blender/t005_static_probe.py）
const BLENDER_LINEAR := {
	"ProbeCube": Color(0.55, 0.58, 0.60),
	"Marker_Front": Color(0.85, 0.10, 0.10),
	"Marker_Top": Color(0.10, 0.20, 0.85),
	"Marker_Right": Color(0.90, 0.75, 0.10),
}

## Blender 里的对象位置（米）
const BLENDER_POS := {
	"ProbeCube": Vector3(0.0, 0.0, 0.0),
	"Marker_Front": Vector3(0.0, -2.0, 0.0),
	"Marker_Top": Vector3(0.0, 0.0, 2.0),
	"Marker_Right": Vector3(2.0, 0.0, 0.0),
}

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("TEST|run_t005_asset|engine=%s" % Engine.get_version_info().string)
	print("TEST|asset=%s" % ASSET)

	var packed: PackedScene = load(ASSET)
	if packed == null:
		_assert("asset_loads", "PackedScene", "null", false)
		_finish()
		return
	_assert("asset_loads", "PackedScene", "PackedScene", true)

	var inst: Node = packed.instantiate()
	print("ASSET|root_class=%s|root_name=%s|child_count=%d" % [
		inst.get_class(), inst.name, inst.get_child_count()
	])

	var probe_mesh := _check_asset_geometry(inst)
	if probe_mesh == null:
		_check_asset_names(inst)
		inst.free()
		_finish()
		return
	_check_asset_names(inst)
	_check_axis_mapping(inst)
	_check_asset_materials(inst)

	var aabb := probe_mesh.get_aabb()
	print("SIZE|probe_aabb_pos=%s|probe_aabb_size=%s" % [aabb.position, aabb.size])

	await _check_runtime_collision(aabb.size)
	await _check_lab_integration()

	inst.free()
	_finish()


# ---------------------------------------------------------------------------
# A) 资产层
# ---------------------------------------------------------------------------

## 返回 ProbeCube 的 MeshInstance3D（尺寸断言的对象）
func _check_asset_geometry(inst: Node) -> MeshInstance3D:
	var probe := _find(inst, "ProbeCube") as MeshInstance3D
	if probe == null:
		_assert("probe_mesh_exists", "MeshInstance3D", "null", false)
		return null
	_assert("probe_mesh_exists", "MeshInstance3D", "MeshInstance3D", true)

	var mesh: Mesh = probe.mesh
	if mesh == null:
		_assert("probe_mesh_has_mesh", "Mesh", "null", false)
		return null
	_assert("probe_mesh_has_mesh", "Mesh", mesh.get_class(), true)

	var aabb: AABB = mesh.get_aabb()
	# E02：源 1 m 物体在 Godot 必须是 1.0 m（不是 0.01，也不是 100）
	_assert_near("probe_size_x_m", 1.0, aabb.size.x, EPS)
	_assert_near("probe_size_y_m", 1.0, aabb.size.y, EPS)
	_assert_near("probe_size_z_m", 1.0, aabb.size.z, EPS)
	# 网格原点居中：AABB 角应为 -0.5（证明导出没有把 pivot 挪走）
	_assert_near("probe_aabb_corner_x_m", -0.5, aabb.position.x, EPS)
	_assert_near("probe_aabb_corner_y_m", -0.5, aabb.position.y, EPS)
	_assert_near("probe_aabb_corner_z_m", -0.5, aabb.position.z, EPS)

	var tris := _triangle_count(mesh)
	print("SIZE|surface_count=%d|verts=%d|tris=%d|class=%s" % [
		mesh.get_surface_count(), _vertex_count(mesh), tris, mesh.get_class()
	])
	# BlenderPipeline：静态环境模块 ≤3000 triangles
	_assert("probe_tris_within_budget", "<= 3000", str(tris), tris > 0 and tris <= 3000)
	# 标记物尺寸（同时验证小尺寸物体的缩放也没被改）
	var marker := _find(inst, "Marker_Front") as MeshInstance3D
	if marker != null and marker.mesh != null:
		var ma: AABB = marker.mesh.get_aabb()
		_assert_near("marker_front_size_x_m", 0.1, ma.size.x, EPS)
	return probe


func _check_asset_names(inst: Node) -> void:
	var want := BLENDER_POS.keys()
	want.sort()
	var got: Array = []
	for nm in BLENDER_POS:
		if _find(inst, nm) != null:
			got.append(nm)
	got.sort()
	_assert("all_blender_object_names_preserved", str(want), str(got), got == want)
	# 不允许出现 Cube.001 式自动改名/重复
	var dup := 0
	for nm in BLENDER_POS:
		dup += _count_named(inst, nm)
	_assert("no_duplicate_objects", "4 total", str(dup), dup == want.size())


func _check_axis_mapping(inst: Node) -> void:
	# 实测映射：Godot = (x_b, z_b, -y_b)；这里逐个对象核对，并打印推导过程
	for nm in BLENDER_POS:
		var n := _find(inst, nm) as Node3D
		if n == null:
			_assert("axis_%s_exists" % nm, "Node3D", "null", false)
			continue
		var b: Vector3 = BLENDER_POS[nm]
		var expect := Vector3(b.x, b.z, -b.y)
		var pos: Vector3 = n.position
		print("MAPPING|%s|blender=%s|expected_godot=%s|actual_godot=%s" % [
			nm, b, expect, pos
		])
		_assert(
			"axis_%s" % nm,
			str(expect),
			str(pos),
			(pos - expect).length() <= EPS,
		)
	# 明确断言"+Y 向上"：Blender 的 +Z 标记必须落在 Godot 的 +Y 轴
	var top := _find(inst, "Marker_Top") as Node3D
	if top != null:
		_assert("up_axis_is_godot_plus_y", "y > 0 (Blender +Z)", "y = %.3f" % top.position.y, top.position.y > 0.0)
	# 明确断言"Blender 前方 -Y 落到 Godot +Z"（与本文件顶部注释一致）
	var front := _find(inst, "Marker_Front") as Node3D
	if front != null:
		_assert("blender_minus_y_maps_to_godot_plus_z", "z > 0", "z = %.3f" % front.position.z, front.position.z > 0.0)


func _check_asset_materials(inst: Node) -> void:
	var seen: Array = []
	for nm in BLENDER_LINEAR:
		var mi := _find(inst, nm) as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
			_assert("material_%s_present" % nm, "surface material", "missing", false)
			continue
		var mat := mi.mesh.surface_get_material(0)
		if mat == null or not (mat is BaseMaterial3D):
			_assert("material_%s_present" % nm, "BaseMaterial3D", str(mat), false)
			continue
		var b := mat as BaseMaterial3D
		var lin: Color = BLENDER_LINEAR[nm]
		# glTF 的 baseColorFactor 是**线性**的；Godot 的 albedo_color 是 **sRGB** 编码值。
		# 实测（0.55 线性 → 0.7674 sRGB），因此按 sRGB 编码后比较。
		var expect := Color(_srgb(lin.r), _srgb(lin.g), _srgb(lin.b))
		print("MATERIAL|%s|res_name=%s|linear=%s|expected_srgb=%s|got=%s|emission=%s|roughness=%.3f" % [
			nm, b.resource_name, lin, expect, b.albedo_color, b.emission_enabled, b.roughness
		])
		var maxdiff := maxf(maxf(absf(b.albedo_color.r - expect.r), absf(b.albedo_color.g - expect.g)),
			absf(b.albedo_color.b - expect.b))
		_assert_near("material_%s_albedo_srgb" % nm, expect.r, b.albedo_color.r, EPS)
		_assert_near("material_%s_albedo_diff_max" % nm, 0.0, maxdiff, EPS)
		# 自发光必须为 0：自发光会冲掉方向光造成的明暗差（Visual-Verification §3.2）
		_assert("material_%s_no_emission" % nm, "false", str(b.emission_enabled), not b.emission_enabled)
		seen.append(b.albedo_color)

	var distinct := {}
	for c in seen:
		distinct["%.3f_%.3f_%.3f" % [c.r, c.g, c.b]] = true
	_assert("four_distinct_materials", "4", str(distinct.size()), distinct.size() == 4)


# ---------------------------------------------------------------------------
# B) 运行层：碰撞真的能用
# ---------------------------------------------------------------------------

func _check_runtime_collision(imported_size: Vector3) -> void:
	var world := Node3D.new()
	world.name = "T005World"
	root.add_child(world)

	# 地面：顶面 y = 0（与 probe_step_height 的试验世界一致，便于对照）
	_add_static_box(world, "Ground", Vector3(40, 1.0, 20), Vector3(0, -0.5, 0))

	var body := CharacterBody3D.new()
	body.name = "Walker"
	body.collision_layer = 2
	body.collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HALF_HEIGHT * 2.0  # Godot 的 height 是含半球总高
	col.shape = cap
	body.add_child(col)
	body.position = Vector3(0.0, HALF_HEIGHT + 0.05, 0.0)
	world.add_child(body)
	await process_frame

	# 基线：落到平地
	var y_ground := await _fall_until_rest(body, Vector3(0.0, HALF_HEIGHT + 0.05, 0.0), 300)
	_assert("baseline_landed_on_ground", "true", str(body.is_on_floor()), body.is_on_floor())
	_assert_near("baseline_y_m", HALF_HEIGHT, y_ground, EPS_DROP)

	# 1 m 立方体：碰撞盒尺寸**取自导入网格的 AABB**，底面坐在地面上 → 顶面 y = 1.0
	var half := imported_size * 0.5
	_add_static_box(world, "ProbeCollider", imported_size, Vector3(2.5, half.y, 0.0))

	var y_top := await _fall_until_rest(body, Vector3(2.5, 3.0, 0.0), 400)
	_assert("landed_on_probe_top", "true", str(body.is_on_floor()), body.is_on_floor())

	var delta := y_top - y_ground
	print("COLLISION|y_ground=%.4f|y_top=%.4f|delta=%.4f|imported_size=%s" % [
		y_ground, y_top, delta, imported_size
	])
	_assert_near("step_up_height_m", 1.0, delta, EPS_DROP)
	# 没有穿透：胶囊底不得低于立方体顶面
	var bottom := y_top - HALF_HEIGHT
	_assert("no_penetration_through_probe", ">= 1.0 - 0.02", "%.4f" % bottom, bottom >= 1.0 - EPS_DROP)
	# 没有从顶面滑落
	_assert_near("no_horizontal_slide_on_top_m", 2.5, body.global_position.x, EPS)

	world.queue_free()
	await process_frame
	await process_frame


## 把 body 放到 from、等它落到静止；返回最终 y。
func _fall_until_rest(body: CharacterBody3D, from: Vector3, max_steps: int) -> float:
	body.global_position = from
	body.velocity = Vector3.ZERO
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	# 先推进一帧再判 is_on_floor：瞬移之后该标志仍是**上一帧**的状态，
	# 否则从空中瞬移过来会被误判为"已经落地"（已实测踩到：y_top 停在 3.0000）。
	body.velocity.y -= 9.8 * dt
	body.move_and_slide()
	await physics_frame
	for i in max_steps:
		if body.is_on_floor():
			break
		body.velocity.y -= 9.8 * dt
		body.move_and_slide()
		await physics_frame
	# 再稳 20 帧，避免把"正在下落"当成落点
	for i in 20:
		body.velocity = Vector3.ZERO
		body.move_and_slide()
		await physics_frame
	return body.global_position.y


func _add_static_box(parent: Node3D, nm: String, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.name = nm
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	sb.add_child(cs)
	parent.add_child(sb)


# ---------------------------------------------------------------------------
# C) 场景层：接入 l_movement_lab + 对照 100 cm 标尺
# ---------------------------------------------------------------------------

func _check_lab_integration() -> void:
	var packed: PackedScene = load(LAB)
	if packed == null:
		_assert("lab_loads", "PackedScene", "null", false)
		return
	var lab: Node = packed.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame

	var probe := lab.get_node_or_null("ProbeAsset") as StaticBody3D
	_assert("lab_has_probe_asset", "StaticBody3D", str(probe), probe != null)
	if probe == null:
		lab.queue_free()
		return

	# 资产在场景里仍然读到 1 m
	var mi := _find_mesh(probe)
	if mi == null or mi.mesh == null:
		_assert("lab_probe_mesh_present", "MeshInstance3D", "null", false)
		lab.queue_free()
		return
	var aabb: AABB = mi.mesh.get_aabb()
	_assert_near("lab_probe_size_x_m", 1.0, aabb.size.x, EPS)
	_assert_near("lab_probe_size_y_m", 1.0, aabb.size.y, EPS)
	_assert_near("lab_probe_size_z_m", 1.0, aabb.size.z, EPS)

	# 碰撞形状必须与导入网格的 AABB 一致（防止"看着对、碰撞不对"）
	var shape_node := probe.get_node_or_null("ProbeShape") as CollisionShape3D
	var box := shape_node.shape as BoxShape3D if shape_node != null else null
	if box == null:
		_assert("lab_probe_shape_is_box", "BoxShape3D", "null", false)
	else:
		_assert("lab_probe_shape_is_box", "BoxShape3D", "BoxShape3D", true)
		_assert_near("lab_probe_shape_size_x_m", aabb.size.x, box.size.x, EPS)
		_assert_near("lab_probe_shape_size_y_m", aabb.size.y, box.size.y, EPS)
		_assert_near("lab_probe_shape_size_z_m", aabb.size.z, box.size.z, EPS)

	# 资产坐在地面上（底面对齐地面顶面），否则视觉与碰撞都不可信
	var bottom := probe.global_position.y - aabb.size.y * 0.5
	_assert_near("lab_probe_sits_on_ground_m", GROUND_TOP, bottom, EPS)

	# 对照 100 cm 标尺：标尺自身确为 1 m，且与立方体同宽（±1 cm）——数值化"比长度"
	var ruler := lab.get_node_or_null("Ruler100cm") as MeshInstance3D
	if ruler == null or not (ruler.mesh is BoxMesh):
		_assert("ruler_present", "BoxMesh", "null", false)
	else:
		var rm := ruler.mesh as BoxMesh
		_assert_near("ruler_length_m", 1.0, rm.size.x, EPS)
		print("RULER|ruler_len=%.4f|probe_width=%.4f|probe_pos=%s|ruler_pos=%s" % [
			rm.size.x, aabb.size.x, probe.global_position, ruler.global_position
		])
		_assert_near("probe_width_equals_ruler_length", rm.size.x, aabb.size.x, EPS)

	# 资产不得压住出生点（否则 T002 的出生无重叠断言会被破坏）
	var start := lab.get_node_or_null("PlayerStart") as Marker3D
	if start != null and probe.is_inside_tree():
		var space := probe.get_world_3d().direct_space_state
		var params := PhysicsShapeQueryParameters3D.new()
		var qcap := CapsuleShape3D.new()
		qcap.radius = RADIUS
		qcap.height = HALF_HEIGHT * 2.0
		params.shape = qcap
		params.transform = Transform3D(Basis(), start.global_position)
		params.collision_mask = 1
		params.collide_with_bodies = true
		var res: Array[Dictionary] = space.intersect_shape(params, 4)
		_assert("spawn_not_blocked_by_probe", "0 overlaps", "%d overlaps" % res.size(), res.is_empty())

	lab.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _find(root_node: Node, nm: String) -> Node:
	if root_node.name == nm:
		return root_node
	for c in root_node.get_children():
		var r := _find(c, nm)
		if r:
			return r
	return null


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for c in node.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null


func _count_named(node: Node, nm: String) -> int:
	var n := 1 if node.name == nm else 0
	for c in node.get_children():
		n += _count_named(c, nm)
	return n


## sRGB 编码（线性 → 显示）：Godot 的 albedo_color 用这个空间存储 glTF 的线性 baseColorFactor
func _srgb(c: float) -> float:
	if c <= 0.0031308:
		return c * 12.92
	return 1.055 * pow(c, 1.0 / 2.4) - 0.055


func _vertex_count(mesh: Mesh) -> int:
	var total := 0
	for i in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total


func _triangle_count(mesh: Mesh) -> int:
	var total := 0
	for i in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
			total += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	var ok: bool = absf(expected - actual) <= eps
	_assert(id, "%.4f (±%.3f)" % [expected, eps], "%.4f" % actual, ok)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
