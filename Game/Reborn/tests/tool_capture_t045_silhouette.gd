extends SceneTree
## T045 证据图：猫基础形体的**正/侧/45° 低机位轮廓**（1.2 m 观察距离，纯色背板去干扰）。
##
## 为什么单独做：T045 的验收是"正侧面与低镜头距离轮廓可辨、模型符合已验证身体尺寸"。
## 现有正式视觉是 `sm_cat_006.glb`（来源 `cat_fripouille`，2026-10-21 负责人授权；2026-11-09 T046-A 重展开+重烘焙；2026-11-10 T049 追加 `AttackCue`），
## 本工具只**取证 + 量尺寸**，不改网格、不改配置。
##
## 用法（**不能用 --headless**，要真渲染）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_t045_silhouette.gd' --quit-after 20000 -- t045
##
## 产物：`user://t045_cat_{front,side,three_quarter}.png`（拷到 `Art/Probes/`）

const RES := Vector2i(1280, 720)
const SETTLE := 8
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CAT_CFG := "res://resources/species/cat.tres"
const SPAWN := Vector3(-2.0, 0.45, 20.0)
const VIEW_DISTANCE := 1.2
const VIEW_HEIGHT := 0.30

var _level: Node3D = null
var _body: AnimalBody = null
var _cam: Camera3D = null
var _backdrop: MeshInstance3D = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	root.size = RES
	if args.has("t045"):
		await _run()
	else:
		print("CAP|t045|ERROR|need_arg|pass '-- t045'")
	print("CAP|t045|done")
	quit(0)


func _run() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CAP|t045|ERROR|level_load_failed")
		return
	_level = packed.instantiate() as Node3D
	root.add_child(_level)

	_cam = Camera3D.new()
	_cam.name = "T045Cam"
	_cam.near = 0.02
	_cam.far = 200.0
	_cam.fov = 45.0
	_level.add_child(_cam)

	var cat := load(CAT_CFG) as SpeciesConfig
	_body = (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	_body.species_config = cat
	_body.ai_enabled = false
	_body.player_controlled = false
	_level.add_child(_body)
	_body.global_position = SPAWN
	for i in 30:
		await physics_frame

	_report_asset()
	_make_backdrop()

	# 猫在 Godot 里朝 -Z：front = 从 -Z 侧看它的脸；side = 从 +X 看右侧面。
	await _shot("front", Vector3(0.0, 0.0, -1.0))
	await _shot("side", Vector3(1.0, 0.0, 0.0))
	await _shot("three_quarter", Vector3(0.7071, 0.0, -0.7071))


func _report_asset() -> void:
	var visual: Node = _body.visual_root
	var mi: MeshInstance3D = null
	var sk: Skeleton3D = null
	if visual != null:
		mi = _find_mesh(visual)
		sk = _find_skeleton(visual)
	var cat := load(CAT_CFG) as SpeciesConfig
	print("CAP|t045|contract|cap_h=%.3f|cap_len_contract=0.620|asset=%s" % [
		cat.capsule_height(), cat.visual_scene.resource_path if cat.visual_scene else "null"])
	if mi == null:
		print("CAP|t045|ERROR|mesh_not_found")
		return
	var aabb := mi.get_aabb()
	var mat_names: Array[String] = []
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		mat_names.append(String(m.resource_name) if m != null else "<null>")
	print("CAP|t045|aabb|size=(%.3f,%.3f,%.3f)|pos=(%.3f,%.3f,%.3f)|surfaces=%d|mats=%s" % [
		aabb.size.x, aabb.size.y, aabb.size.z,
		aabb.position.x, aabb.position.y, aabb.position.z,
		mi.mesh.get_surface_count(), str(mat_names)])
	print("CAP|t045|verts_approx|tris=%d" % _triangle_count(mi.mesh))
	if sk != null:
		print("CAP|t045|skeleton|bones=%d" % sk.get_bone_count())
	var anims: Array[String] = []
	if visual != null:
		for child in visual.get_children():
			if child is AnimationPlayer:
				for name in (child as AnimationPlayer).get_animation_list():
					anims.append(String(name))
	print("CAP|t045|animations=%s" % str(anims))


func _make_backdrop() -> void:
	_backdrop = MeshInstance3D.new()
	_backdrop.name = "T045Backdrop"
	var quad := QuadMesh.new()
	# 背板必须"铺满整个视野"（40×24 m @6 m）：否则视锥边缘会出现地平线/色块边界，
	# 视觉判读会把它当成"渲染缺陷"（2026-11-09 实测踩到两次，换尺寸后才稳定）。
	quad.size = Vector2(40.0, 24.0)
	_backdrop.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.28, 0.30, 0.32)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_backdrop.material_override = mat
	_level.add_child(_backdrop)


func _shot(tag: String, dir: Vector3) -> void:
	var focus := _body.global_position + Vector3(0.0, VIEW_HEIGHT * 0.5, 0.0)
	var cam_pos := focus + dir.normalized() * VIEW_DISTANCE
	cam_pos.y = _body.global_position.y + VIEW_HEIGHT
	_cam.look_at_from_position(cam_pos, focus, Vector3.UP)
	_cam.current = true
	# 背板放到主体另一侧、正对相机，避免庭院背景干扰轮廓判读。
	var away := (focus - cam_pos).normalized()
	# 背板放到主体**远处**（6 m）并且很大（12×8 m）：读作"一面墙"，不会像浮在猫身后的面板。
	_backdrop.global_position = focus + away * 6.0
	_backdrop.look_at(_backdrop.global_position - away, Vector3.UP)
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("CAP|t045|%s|ERROR|no_image" % tag)
		return
	var path := "user://t045_cat_%s.png" % tag
	var err := img.save_png(path)
	print("CAP|t045|%s|cam=(%.2f,%.2f,%.2f)|save=%d (%s)|%s" % [
		tag, cam_pos.x, cam_pos.y, cam_pos.z, err, "OK" if err == OK else "FAIL",
		ProjectSettings.globalize_path(path)])


func _find_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _triangle_count(mesh: Mesh) -> int:
	var total := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.size() > 0:
			total += idx.size() / 3
		else:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += verts.size() / 3
	return total
