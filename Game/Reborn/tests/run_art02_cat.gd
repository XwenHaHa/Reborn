extends SceneTree
## ART02 验收：猫的真实模型（CAT_BODY_001 → `sm_cat_001.glb`）+ 配置驱动接入 + 不破坏原有胶囊契约。
##
## 三层：
##   A) 资产层：导入网格的 AABB / 面数 / 两个材质槽 / 贴图是否真的挂上 / 不带碰撞
##   B) 配置与接线层：`SpeciesConfig.visual_scene` 驱动实例化；胶囊网格退化为隐藏的尺寸代理；
##      脚底贴到胶囊底面；蹲姿压缩；捕获后隐藏 —— **胶囊尺寸与 T009/T013 的断言不变**
##   C) 运行层：把带真实模型的猫放进生态关卡，真实物理下落地 + 视觉跟着走
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_art02_cat.gd' --quit-after 30000
## 退出码：0 = 全部通过；1 = 有失败。

const ASSET := "res://assets/characters/cat/sm_cat_002.glb"
const CAT_CFG := "res://resources/species/cat.tres"
const MOUSE_CFG := "res://resources/species/mouse.tres"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"

## 资产契约（Tools/Blender/art04_cat_from_ref.py 的 PROBE + tests/tool_dump_scene_tree.gd 读回）
## 源：Sketchfab cat_fripouille（CC BY 4.0），已按项目契约归一化（体长 0.58 m / 面朝 +Y / 2 槽 / 33 骨）
const EXPECT_SIZE_X := 0.304614
const EXPECT_SIZE_Y := 0.310051
const EXPECT_SIZE_Z := 0.542281
const EXPECT_TRIS := 8376
const EXPECT_SURFACES := 2
const EXPECT_FUR_ROUGH := 0.72
const EXPECT_DETAIL_ROUGH := 0.28

const GEO_EPS := 0.02
const GROUND_TOP := 0.10

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("TEST|run_art02_cat|engine=%s" % Engine.get_version_info().string)
	print("TEST|asset=%s" % ASSET)
	_check_asset_layer()
	await _check_integration_layer()
	await _check_runtime_layer()
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
	_assert("asset_root_name", "sm_cat_002", str(inst.name), String(inst.name) == "sm_cat_002")

	var mi := _find_mesh(inst)
	_assert("asset_has_mesh", "MeshInstance3D", str(mi != null), mi != null)
	if mi == null:
		inst.free()
		return
	_assert("asset_mesh_node_name", "CAT_BODY_001", str(mi.name), String(mi.name) == "CAT_BODY_001")

	var aabb: AABB = mi.mesh.get_aabb()
	print("ASSET|aabb_pos=%s|aabb_size=%s|verts=%d|tris=%d" % [
		aabb.position, aabb.size, _vertex_count(mi.mesh), _triangle_count(mi.mesh)])
	_assert_near("asset_width_x", EXPECT_SIZE_X, aabb.size.x, GEO_EPS)
	_assert_near("asset_height_y", EXPECT_SIZE_Y, aabb.size.y, GEO_EPS)
	_assert_near("asset_length_z", EXPECT_SIZE_Z, aabb.size.z, GEO_EPS)
	# 原点 = 四脚着地的地面中心（Blender min_z ≈ 0 → Godot aabb.position.y ≈ 0）
	_assert_near("asset_grounded_y", 0.0, aabb.position.y, 0.01)
	# 朝向：鼻子在 -Z（Godot 前方）→ AABB 在 z 上更偏向负方向
	_assert("asset_faces_minus_z", "<0", "%.3f" % (aabb.position.z + aabb.size.z * 0.5),
		aabb.position.z + aabb.size.z * 0.5 < 0.0)
	_assert("asset_tris", str(EXPECT_TRIS), str(_triangle_count(mi.mesh)),
		_triangle_count(mi.mesh) == EXPECT_TRIS)
	_assert("asset_tri_budget_10000", "<=10000", str(_triangle_count(mi.mesh)),
		_triangle_count(mi.mesh) <= 10000)
	_assert("asset_surfaces", str(EXPECT_SURFACES), str(mi.mesh.get_surface_count()),
		mi.mesh.get_surface_count() == EXPECT_SURFACES)

	var tex_count := 0
	for i in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
		_assert("surface_%d_material" % i, "StandardMaterial3D", str(mat != null), mat != null)
		if mat == null:
			continue
		var has_tex := mat.albedo_texture != null
		if has_tex:
			tex_count += 1
		print("ASSET|surface=%d|name=%s|roughness=%.2f|albedo_tex=%s|cull=%d" % [
			i, mat.resource_name, mat.roughness,
			mat.albedo_texture.resource_path if has_tex else "none", mat.cull_mode])
		if i == 0:
			_assert("surface_0_is_fur", "MAT_Cat_Fur", String(mat.resource_name),
				String(mat.resource_name) == "MAT_Cat_Fur")
			_assert_near("surface_0_roughness", EXPECT_FUR_ROUGH, mat.roughness, 0.03)
			# 程序化花纹烤进贴图：没有贴图就退化成"纯色塑料"
			_assert("surface_0_has_albedo_texture", "texture", "none" if not has_tex else "yes", has_tex)
		else:
			_assert("surface_1_is_detail", "MAT_Cat_Detail", String(mat.resource_name),
				String(mat.resource_name) == "MAT_Cat_Detail")
			_assert_near("surface_1_roughness", EXPECT_DETAIL_ROUGH, mat.roughness, 0.03)
	_assert("asset_materials_textured", "2", str(tex_count), tex_count == EXPECT_SURFACES)
	_assert("asset_has_no_collision", "0", str(_count_collision(inst)), _count_collision(inst) == 0)
	inst.free()


# ---------------------------------------------------------------------------
# B) 配置与接线层
# ---------------------------------------------------------------------------

func _check_integration_layer() -> void:
	var cat := load(CAT_CFG) as SpeciesConfig
	var mouse := load(MOUSE_CFG) as SpeciesConfig
	_assert("cat_config_loads", "SpeciesConfig", str(cat != null), cat != null)
	if cat == null:
		return
	_assert("cat_visual_configured", ASSET, cat.visual_scene.resource_path if cat.visual_scene else "null",
		cat.visual_scene != null and cat.visual_scene.resource_path == ASSET)
	# 鼠仍是胶囊占位：本任务**只**换了猫（modeling2.md §三：试点通过前不批量替换）
	_assert("mouse_visual_still_placeholder", "null",
		mouse.visual_scene.resource_path if mouse != null and mouse.visual_scene != null else "null",
		mouse != null and mouse.visual_scene == null)

	var packed: PackedScene = load(BODY_SCENE)
	var body := packed.instantiate() as AnimalBody
	_assert("body_instance", "AnimalBody", str(body != null), body != null)
	if body == null:
		return
	# 先赋配置再入树：`_ready()` 会走一次完整 `apply_config()`
	body.species_config = cat
	root.add_child(body)
	body.apply_config()
	# 关掉输入驱动：否则 `_physics_process()` 每帧用 `Input.is_action_pressed("crouch")` 覆盖 want_crouch
	body.player_controlled = false
	await physics_frame
	await physics_frame

	# 胶囊契约不变（T009/T013 的断言依赖这两条）
	_assert_near("capsule_height_unchanged", cat.capsule_height(), body.body_mesh.mesh.height, 1e-4)
	_assert_near("capsule_radius_unchanged", cat.capsule_radius, body.body_mesh.mesh.radius, 1e-4)
	_assert("capsule_mesh_hidden", "false", str(body.body_mesh.visible), not body.body_mesh.visible)

	var visual := body.get_node_or_null("Visual") as Node3D
	_assert("visual_instantiated", "Node3D/Visual", str(visual != null), visual != null)
	if visual == null:
		body.queue_free()
		return
	_assert("visual_is_asset_scene", ASSET, visual.scene_file_path,
		visual.scene_file_path == ASSET)
	_assert("visual_has_mesh", "MeshInstance3D", str(_find_mesh(visual) != null),
		_find_mesh(visual) != null)
	print("INTEG|visual_pos=%s|scale=%s|capsule_h=%.3f" % [
		visual.position, visual.scale, cat.capsule_height()])
	# 脚底 = 胶囊底面：视觉原点下沉半个胶囊高
	_assert_near("visual_feet_at_capsule_bottom", -cat.capsule_height() * 0.5, visual.position.y, 1e-4)
	_assert_near("visual_stand_scale_y", 1.0, visual.scale.y, 1e-4)
	# 模型高 0.402 m 不得超出胶囊总高 0.48 m（否则视觉比碰撞大一圈）
	var vpos: float = visual.position.y + EXPECT_SIZE_Y * visual.scale.y
	_assert("visual_inside_capsule_top", "<=%.3f" % (cat.capsule_height() * 0.5), "%.3f" % vpos,
		vpos <= cat.capsule_height() * 0.5 + 1e-4)

	# 蹲姿：没有姿态动画（骨骼属 P6）→ 用竖向压缩把视觉留在蹲姿碰撞体内。
	# `want_crouch` 必须一起置位，否则下一个物理帧的 `_apply_stance()` 会立刻站回去。
	body.want_crouch = true
	body.call("_set_stance", true)
	await physics_frame
	await physics_frame
	var expect_squash: float = maxf(AnimalBody.VISUAL_MIN_SQUASH,
		cat.crouch_height() / cat.capsule_height())
	print("INTEG|crouch|is_crouching=%s|visual_pos=%s|scale=%s|expect_squash=%.4f" % [
		str(body.is_crouching), visual.position, visual.scale, expect_squash])
	_assert("crouch_applied", "true", str(body.is_crouching), body.is_crouching)
	_assert_near("visual_crouch_feet_at_bottom", -cat.crouch_height() * 0.5, visual.position.y, 1e-4)
	_assert_near("visual_crouch_scale_y", expect_squash, visual.scale.y, 1e-4)
	_assert("visual_crouch_inside_capsule", "<=%.3f" % (cat.crouch_height() * 0.5),
		"%.3f" % (visual.position.y + EXPECT_SIZE_Y * visual.scale.y),
		visual.position.y + EXPECT_SIZE_Y * visual.scale.y <= cat.crouch_height() * 0.5 + 1e-4)
	body.want_crouch = false
	body.call("_set_stance", false)
	await physics_frame
	await physics_frame
	_assert_near("visual_stand_restored", 1.0, visual.scale.y, 1e-4)

	# 捕获后隐藏视觉（与胶囊网格同口径）
	body.mark_captured("art02_test")
	_assert("visual_hidden_when_captured", "false", str(visual.visible), not visual.visible)
	body.queue_free()


# ---------------------------------------------------------------------------
# C) 运行层：真实物理 + 真实关卡
# ---------------------------------------------------------------------------

func _check_runtime_layer() -> void:
	var level_packed: PackedScene = load(LEVEL)
	if not _assert("level_loads", "PackedScene", str(level_packed != null), level_packed != null):
		return
	var level: Node3D = level_packed.instantiate() as Node3D
	root.add_child(level)
	await physics_frame
	await physics_frame

	var cat := load(CAT_CFG) as SpeciesConfig
	var body := (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	# 先赋配置再入树：`_ready()` 会走完整 `apply_config()`（入树后立刻读 @onready 节点）
	body.species_config = cat
	level.add_child(body)
	body.player_controlled = false
	var start := Vector3(-8.0, GROUND_TOP + 0.60, 0.0)
	body.global_position = start
	await physics_frame
	await physics_frame
	var visual := body.get_node_or_null("Visual") as Node3D
	_assert("runtime_visual_present", "true", str(visual != null), visual != null)

	# CharacterBody3D 不会自己下落：逐帧喂速度 + move_and_slide（ART01 踩过这个坑）
	var vel_y := 0.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for i in 240:
		await physics_frame
		if body.is_on_floor():
			break
		vel_y -= 9.8 * dt
		body.velocity = Vector3(0.0, vel_y, 0.0)
		body.move_and_slide()
	var landed := body.global_position
	print("RUNTIME|start=%s|landed=%s|visual_global=%s|on_floor=%s" % [
		start, landed, visual.global_position if visual != null else Vector3.ZERO,
		str(body.is_on_floor())])
	var expect_y := GROUND_TOP + cat.capsule_height() * 0.5
	_assert_near("runtime_lands_on_ground", expect_y, landed.y, 0.03)
	_assert("runtime_visual_feet_on_ground", "≈%.3f" % GROUND_TOP,
		"%.3f" % (visual.global_position.y if visual != null else -1.0),
		visual != null and absf(visual.global_position.y - GROUND_TOP) <= 0.03)
	_assert("runtime_visual_not_stretched", "scale.y=1",
		"%.3f" % (visual.scale.y if visual != null else -1.0),
		visual != null and absf(visual.scale.y - 1.0) <= 1e-4)
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
	_assert(id, "%.4f (±%.4f)" % [expected, eps], "%.4f" % actual, ok)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
