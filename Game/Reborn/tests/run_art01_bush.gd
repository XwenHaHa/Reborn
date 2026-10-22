extends SceneTree
## ART01 验收：草丛掩体资产（ENV_BUSH_001）+ 关卡接入 + "掩体不是实体"的物理实测。
##
## 这不是"文件存在"检查。三层都要读回真实数据：
##   A) 资产层：导入网格的 AABB/面数/材质/双面剔除（玩家会站在草丛**里面**，单面会穿帮）
##   B) 关卡层：4 处掩体的视觉是 glb 实例、贴地、**没有碰撞**、Area3D 数据体量没变
##   C) 运行层：把猫胶囊扔进掩体中心，它应该落在地面上、水平不被推开（掩体不是实体）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_art01_bush.gd' --quit-after 20000
## 退出码：0 = 全部通过；1 = 有失败。

const ASSET := "res://assets/environment/sm_bush_002.glb"   # ART03-⑧ 重做版
const LEVEL := "res://scenes/maps/l_courtyard.tscn"

## Blender 侧几何契约（Tools/Blender/art01_bush_001.py）
const EXPECT_MESH_X := 2.800400
const EXPECT_MESH_Y := 0.815600
const EXPECT_MESH_Z := 2.929700
const EXPECT_TRIS := 4480
const EXPECT_SURFACES := 2

## Blender 侧材质（**线性** base color，Godot 存 sRGB 编码值）
const BLENDER_LINEAR := {
	"MAT_Bush_Leaf": Color(0.085, 0.200, 0.075),
	"MAT_Bush_Soil": Color(0.055, 0.038, 0.025),
}

## 关卡里 4 处草丛掩体（T011 的三处 + ART01 补上视觉的溪边一处）
const COVER_NODES := [
	{"area": "CoverBushWestA", "visual": "CoverBushWestAMesh", "sx": -16.0, "sz": -6.0},
	{"area": "CoverBushWestB", "visual": "CoverBushWestBMesh", "sx": -16.0, "sz": -16.0},
	{"area": "CoverBushNorthC", "visual": "CoverBushNorthCMesh", "sx": -8.0, "sz": -22.0},
	{"area": "CreekReedCover", "visual": "CreekReedCoverMesh", "sx": -28.0, "sz": 10.0},
]

const GEO_EPS := 0.01
const GROUND_TOP := 0.10          # 生态灰盒地面顶面
const CAT_RADIUS := 0.16
const CAT_HEIGHT := 0.48
const CAT_REST_Y := GROUND_TOP + CAT_HEIGHT * 0.5     # 0.34

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("TEST|run_art01_bush|engine=%s" % Engine.get_version_info().string)
	print("TEST|asset=%s" % ASSET)

	_check_asset_layer()
	await _check_level_layer()
	_finish()


# ---------------------------------------------------------------------------
# A) 资产层
# ---------------------------------------------------------------------------

func _check_asset_layer() -> void:
	var packed: PackedScene = load(ASSET)
	_assert("asset_loads", "PackedScene", str(packed != null), packed != null)
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	print("ASSET|root_class=%s|root_name=%s|children=%d" % [
		inst.get_class(), inst.name, inst.get_child_count()])
	_assert("asset_root_is_node3d", "Node3D", inst.get_class(), inst is Node3D)
	_assert("asset_root_name", "sm_bush_002", str(inst.name), String(inst.name) == "sm_bush_002")

	var mi := _find_mesh(inst)
	_assert("asset_has_mesh", "MeshInstance3D", str(mi != null), mi != null)
	if mi == null:
		inst.free()
		return
	_assert("asset_mesh_node_name", "ENV_BUSH_002", str(mi.name), String(mi.name) == "ENV_BUSH_002")

	var aabb: AABB = mi.mesh.get_aabb()
	print("ASSET|aabb_pos=%s|aabb_size=%s|verts=%d|tris=%d" % [
		aabb.position, aabb.size, _vertex_count(mi.mesh), _triangle_count(mi.mesh)])
	_assert_near("asset_width_x", EXPECT_MESH_X, aabb.size.x, 0.05)
	_assert_near("asset_height", EXPECT_MESH_Y, aabb.size.y, 0.02)
	_assert_near("asset_width_z", EXPECT_MESH_Z, aabb.size.z, 0.05)
	_assert_near("asset_grounded_y", 0.0, aabb.position.y, GEO_EPS)
	_assert("asset_tris", str(EXPECT_TRIS), str(_triangle_count(mi.mesh)),
		_triangle_count(mi.mesh) == EXPECT_TRIS)
	_assert("asset_tri_budget_6000", "<=6000", str(_triangle_count(mi.mesh)),
		_triangle_count(mi.mesh) <= 6000)
	_assert("asset_surfaces", str(EXPECT_SURFACES), str(mi.mesh.get_surface_count()),
		mi.mesh.get_surface_count() == EXPECT_SURFACES)

	# 材质：名字保留 + 颜色 = sRGB(线性) + **双面**（玩家在草丛里面看得到草叶）
	for i in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
		_assert("surface_%d_material" % i, "StandardMaterial3D", str(mat != null), mat != null)
		if mat == null:
			continue
		print("ASSET|surface=%d|name=%s|albedo=%s|cull_mode=%d|roughness=%.2f" % [
			i, mat.resource_name, mat.albedo_color, mat.cull_mode, mat.roughness])
		var linear: Color = BLENDER_LINEAR.get(String(mat.resource_name), Color.BLACK)
		_assert_near("surface_%d_albedo_r" % i, _srgb(linear.r), mat.albedo_color.r, 0.02)
		_assert_near("surface_%d_albedo_g" % i, _srgb(linear.g), mat.albedo_color.g, 0.02)
		_assert_near("surface_%d_albedo_b" % i, _srgb(linear.b), mat.albedo_color.b, 0.02)
		_assert("surface_%d_double_sided" % i,
			"CULL_DISABLED(2)", str(mat.cull_mode),
			mat.cull_mode == BaseMaterial3D.CULL_DISABLED)
		_assert_near("surface_%d_roughness" % i, 0.85, mat.roughness, 0.02)
	_assert("asset_has_no_collision", "0", str(_count_collision(inst)), _count_collision(inst) == 0)
	inst.free()


# ---------------------------------------------------------------------------
# B) 关卡层 + C) 运行层
# ---------------------------------------------------------------------------

func _check_level_layer() -> void:
	var packed: PackedScene = load(LEVEL)
	_assert("level_loads", "PackedScene", str(packed != null), packed != null)
	if packed == null:
		return
	var level: Node3D = packed.instantiate() as Node3D
	root.add_child(level)
	await physics_frame
	await physics_frame

	var cover_areas := get_nodes_in_group("cover_volumes")
	print("LEVEL|cover_volumes=%d" % cover_areas.size())
	_assert("cover_volume_count", "4", str(cover_areas.size()), cover_areas.size() == 4)

	for c in COVER_NODES:
		var area := level.get_node_or_null(c["area"]) as Area3D
		if not _assert("%s_area_exists" % c["area"], "Area3D", str(area != null), area != null):
			continue
		_assert("%s_area_is_cover" % c["area"], "true", str(area.is_in_group("cover_volumes")),
			area.is_in_group("cover_volumes"))
		_assert_near("%s_factor" % c["area"], 0.4, float(area.get_meta("visibility_factor", 0.0)), 1e-6)
		var cs := area.get_node_or_null("Shape") as CollisionShape3D
		var box := cs.shape as BoxShape3D if cs != null else null
		_assert("%s_area_shape" % c["area"], "BoxShape3D 3x3x3", str(box.size) if box != null else "none",
			box != null and box.size.is_equal_approx(Vector3(3.0, 3.0, 3.0)))

		var vis := level.get_node_or_null(c["visual"]) as Node3D
		if not _assert("%s_visual_exists" % c["area"], "Node3D", str(vis != null), vis != null):
			continue
		print("LEVEL|visual=%s|scene_file_path=%s|pos=%s|yaw=%.1f|scale=%s" % [
			c["visual"], vis.scene_file_path, vis.position, vis.rotation_degrees.y, vis.scale])
		_assert("%s_visual_is_asset" % c["area"], ASSET, vis.scene_file_path,
			vis.scene_file_path == ASSET)
		_assert_near("%s_visual_ground_y" % c["area"], GROUND_TOP, vis.position.y, GEO_EPS)
		_assert_near("%s_visual_x" % c["area"], float(c["sx"]), vis.position.x, GEO_EPS)
		_assert_near("%s_visual_z" % c["area"], float(c["sz"]), vis.position.z, GEO_EPS)
		_assert("%s_visual_no_collision" % c["area"], "0", str(_count_collision(vis)),
			_count_collision(vis) == 0)
		_assert("%s_visual_not_nav_source" % c["area"], "false",
			str(vis.is_in_group("nav_source_courtyard")), not vis.is_in_group("nav_source_courtyard"))

	# C) 运行层：真的把猫胶囊扔到掩体中心，看它是不是"穿过草丛站在地上"
	for c in COVER_NODES:
		var body := CharacterBody3D.new()
		body.name = "Art01Probe"
		body.collision_layer = 2
		body.collision_mask = 1                     # 只与 world_static 交互
		var shape_node := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = CAT_RADIUS
		cap.height = CAT_HEIGHT
		shape_node.shape = cap
		body.add_child(shape_node)
		level.add_child(body)
		var start := Vector3(float(c["sx"]), GROUND_TOP + 0.60, float(c["sz"]))
		body.position = start
		# CharacterBody3D **不会自己下落**（它是运动学体，不是刚体）—— 必须逐帧喂速度再 move_and_slide()。
		# 第一版直接等 120 帧，结果 landed == start（0.7000），4 条断言全挂在这里。
		var vel_y := 0.0
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		for i in 240:
			await physics_frame
			if body.is_on_floor():
				break
			vel_y -= 9.8 * dt
			body.velocity = Vector3(0.0, vel_y, 0.0)
			body.move_and_slide()
		var landed := body.position
		print("PHYS|%s|start=%s|landed=%s" % [c["area"], start, landed])
		_assert_near("%s_probe_rests_on_ground" % c["area"], CAT_REST_Y, landed.y, 0.03)
		_assert_near("%s_probe_not_pushed_x" % c["area"], start.x, landed.x, 0.05)
		_assert_near("%s_probe_not_pushed_z" % c["area"], start.z, landed.z, 0.05)
		body.queue_free()

	level.queue_free()


# ---------------------------------------------------------------------------
# 小工具
# ---------------------------------------------------------------------------

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for c in node.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


func _count_collision(node: Node) -> int:
	var n := 1 if (node is CollisionShape3D or node is CollisionObject3D) else 0
	for c in node.get_children():
		n += _count_collision(c)
	return n


## sRGB 编码（线性 → 显示）：Godot 的 albedo_color 存的是 glTF baseColorFactor 的 sRGB 编码值
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


func _assert(id: String, expected: String, actual: String, ok: bool) -> bool:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])
	return ok


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	var ok: bool = absf(expected - actual) <= eps
	_assert(id, "%.4f (±%.3f)" % [expected, eps], "%.4f" % actual, ok)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
