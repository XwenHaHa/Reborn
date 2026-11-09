extends SceneTree
## T050 证据图：鼠基础形体的**正/侧/45° 低机位轮廓**（0.45 m 观察距离，纯色背板）。
##
## 验收词（开发计划 :218）：小尺度仍可辨、贴图和轮廓清楚；不直接缩放猫作为鼠。
## 现役视觉 `sm_mouse_002.glb`（CC-BY 大鼠，来源 `mouse_arribadaclub`）。
##
## 用法（**不能用 --headless**，要真渲染）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_t050_silhouette.gd' --quit-after 20000 -- t050
##
## 产物：`user://t050_mouse_{front,side,three_quarter}.png`（拷到 `Art/Probes/`）

const RES := Vector2i(1280, 720)
const SETTLE := 8
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const MOUSE_CFG := "res://resources/species/mouse.tres"
const SPAWN := Vector3(-2.0, 0.45, 20.0)
const VIEW_DISTANCE := 0.45
const VIEW_HEIGHT := 0.10

var _level: Node3D = null
var _body: AnimalBody = null
var _cam: Camera3D = null
var _backdrop: MeshInstance3D = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	root.size = RES
	if args.has("t050"):
		await _run()
	else:
		print("CAP|t050|ERROR|need_arg|pass '-- t050'")
	print("CAP|t050|done")
	quit(0)


func _run() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CAP|t050|ERROR|level_load_failed")
		return
	_level = packed.instantiate() as Node3D
	root.add_child(_level)

	_cam = Camera3D.new()
	_cam.name = "T050Cam"
	_cam.near = 0.01
	_cam.far = 200.0
	_cam.fov = 45.0
	_level.add_child(_cam)

	var cfg := load(MOUSE_CFG) as SpeciesConfig
	_body = (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	_body.species_config = cfg
	_body.ai_enabled = false
	_body.player_controlled = false
	_level.add_child(_body)
	_body.global_position = SPAWN
	for i in 30:
		await physics_frame

	_report_asset()
	_make_backdrop()

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
	var cfg := load(MOUSE_CFG) as SpeciesConfig
	print("CAP|t050|contract|cap_h=%.3f|asset=%s" % [
		cfg.capsule_height(), cfg.visual_scene.resource_path if cfg.visual_scene else "null"])
	if mi == null:
		print("CAP|t050|ERROR|mesh_not_found")
		return
	var aabb := mi.get_aabb()
	var mat_names: Array[String] = []
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		mat_names.append(String(m.resource_name) if m != null else "<null>")
	print("CAP|t050|aabb|size=(%.4f,%.4f,%.4f)|pos=(%.4f,%.4f,%.4f)|surfaces=%d|mats=%s" % [
		aabb.size.x, aabb.size.y, aabb.size.z,
		aabb.position.x, aabb.position.y, aabb.position.z,
		mi.mesh.get_surface_count(), str(mat_names)])
	print("CAP|t050|tris=%d" % _triangle_count(mi.mesh))
	if sk != null:
		print("CAP|t050|bones=%d" % sk.get_bone_count())
	var anims: Array[String] = []
	if visual != null:
		for child in visual.get_children():
			if child is AnimationPlayer:
				for name in (child as AnimationPlayer).get_animation_list():
					anims.append(String(name))
	print("CAP|t050|animations=%s" % str(anims))


func _make_backdrop() -> void:
	_backdrop = MeshInstance3D.new()
	_backdrop.name = "T050Backdrop"
	var quad := QuadMesh.new()
	# 必须铺满视野：5×3 m @2.5 m 在这个机位会露出地平线，被判读成"渲染缺陷"（T045 踩过）
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
	var away := (focus - cam_pos).normalized()
	_backdrop.global_position = focus + away * 3.0
	_backdrop.look_at(_backdrop.global_position - away, Vector3.UP)
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("CAP|t050|%s|ERROR|no_image" % tag)
		return
	var path := "user://t050_mouse_%s.png" % tag
	var err := img.save_png(path)
	print("CAP|t050|%s|cam=(%.3f,%.3f,%.3f)|save=%d (%s)|%s" % [
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
		total += (idx.size() / 3) if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX].size() / 3)
	return total
