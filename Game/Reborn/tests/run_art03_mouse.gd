extends SceneTree
## ART03-④（鼠换源）：CC-BY mehrus rat → `SM_Mouse_002.glb` 的验收套件。
##
## 覆盖三层：
##   A 资产层：能不能加载、根名、面数、材质槽、骨骼数、**4 段动画的名字与时长**、包围盒
##   B 配置层：`mouse.tres` 是否真的指向新资产，且**胶囊尺寸一字未改**（换视觉不改玩法）
##   C 运行层：`AnimalBody` 实例化后视觉是否被替换、胶囊网格是否隐藏、视觉贴地偏移是否正确
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_art03_mouse.gd' --quit-after 30000

const GLB := "res://assets/characters/mouse/sm_mouse_002.glb"
const MOUSE_CFG := "res://resources/species/mouse.tres"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"

const EXP_TRIS := 3602
const EXP_BONES := 23
const EXP_ANIMS := ["Eat", "Idle", "Run", "Walk"]
const EXP_LEN := {"Eat": 0.625, "Idle": 1.375, "Run": 0.416667, "Walk": 1.041667}
## 实测 AABB（Godot 读回）：0.055227 × 0.204321 × 0.084965（身体 0.135 m + 尾巴）
const EXP_SIZE := Vector3(0.055227, 0.204321, 0.084965)
const SIZE_EPS := 0.02

var _checks := 0
var _fails := 0
var _world: Node3D = null


func _initialize() -> void:
	_world = Node3D.new()
	_world.name = "Art03World"
	root.add_child(_world)
	_check_asset()
	_check_config()
	await _check_runtime()
	await _check_animation_switch()
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)


func _check_asset() -> void:
	var packed: PackedScene = load(GLB)
	if not _check("glb_loads", packed != null):
		return
	_check("glb_root_name", packed.resource_path == GLB)
	var inst: Node = packed.instantiate()
	if not _check("glb_instantiates", inst != null):
		return
	_world.add_child(inst)

	var skel := _find_first(inst, "Skeleton3D") as Skeleton3D
	if _check("skeleton_exists", skel != null):
		_check("skeleton_bone_count_23", skel.get_bone_count() == EXP_BONES)

	var mi := _find_first_mesh(inst)
	if _check("mesh_exists", mi != null and mi.mesh != null):
		var mesh: Mesh = mi.mesh
		_check("mesh_surface_count_1", mesh.get_surface_count() == 1)
		var tri := 0
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tri += idx.size() / 3
		_check("mesh_tris_3602", tri == EXP_TRIS)
		var size: Vector3 = mesh.get_aabb().size
		_check("mesh_aabb_scale_ok",
			absf(size.x - EXP_SIZE.x) < SIZE_EPS and absf(size.y - EXP_SIZE.y) < SIZE_EPS
			and absf(size.z - EXP_SIZE.z) < SIZE_EPS)
		var mat := mesh.surface_get_material(0) as StandardMaterial3D
		if _check("material_is_standard", mat != null):
			_check("material_roughness_0.8", absf(mat.roughness - 0.8) < 1e-4)
			_check("material_metallic_0", mat.metallic < 1e-4)
			_check("material_not_unlit", not mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
			_check("material_has_albedo_texture", mat.albedo_texture != null)
		print("MEASURE|mesh|tris=%d|aabb_size=%s|surfaces=%d" % [tri, size, mesh.get_surface_count()])

	var ap := _find_first(inst, "AnimationPlayer") as AnimationPlayer
	if _check("animation_player_exists", ap != null):
		var names: Array = []
		for n in ap.get_animation_list():
			names.append(String(n))
		_check("anim_count_4", names.size() == 4)
		for want in EXP_ANIMS:
			_check("anim_%s_present" % String(want).to_lower(), names.has(want))
			var a := ap.get_animation(want)
			if a != null:
				var want_len: float = float(EXP_LEN[want])
				_check("anim_%s_length_%.3f" % [String(want).to_lower(), want_len],
					absf(a.length - want_len) < 0.01)
		print("MEASURE|anims|names=%s" % str(names))
	inst.queue_free()


func _check_config() -> void:
	var cfg: SpeciesConfig = load(MOUSE_CFG)
	if not _check("mouse_config_loads", cfg != null):
		return
	_check("mouse_species_id", cfg.species_id == &"Mouse")
	if _check("mouse_visual_scene_set", cfg.visual_scene != null):
		_check("mouse_visual_scene_is_new_asset", cfg.visual_scene.resource_path == GLB)
	# 换视觉不能改玩法：胶囊尺寸必须与 T010/T011 的既有数值一致
	_check("capsule_radius_unchanged_0.06", absf(cfg.capsule_radius - 0.06) < 1e-6)
	_check("capsule_half_height_unchanged_0.09", absf(cfg.capsule_half_height - 0.09) < 1e-6)
	_check("can_use_mouse_tunnel_still_true", cfg.can_use_mouse_tunnel)
	_check("can_jump_still_false", not cfg.can_jump)


func _check_runtime() -> void:
	var cfg: SpeciesConfig = load(MOUSE_CFG)
	var packed: PackedScene = load(BODY_SCENE)
	if not _check("body_scene_loads", packed != null and cfg != null):
		return
	var body: AnimalBody = packed.instantiate() as AnimalBody
	body.species_config = cfg
	body.ai_enabled = false
	_world.add_child(body)
	for i in 8:
		await physics_frame
	var vis: Node3D = body.visual_root
	if not _check("runtime_visual_root_exists", vis != null):
		return
	_check("runtime_visual_is_glb", vis.scene_file_path == GLB)
	_check("runtime_body_mesh_hidden", body.body_mesh != null and not body.body_mesh.visible)
	var cap_h: float = cfg.capsule_height()
	_check("runtime_visual_sunk_by_half_capsule", absf(vis.position.y + cap_h * 0.5) < 1e-4)
	_check("runtime_visual_has_no_collision", _count_shapes(vis) == 0)
	# 骨骼真的跟着视觉实例进来了（不是只挂了空壳）
	var skel := _find_first(vis, "Skeleton3D") as Skeleton3D
	_check("runtime_has_skeleton", skel != null and skel.get_bone_count() == EXP_BONES)
	print("MEASURE|runtime|visual=%s|pos=%s|cap_h=%.4f|skeleton_bones=%d" % [
		vis.scene_file_path, vis.position, cap_h,
		skel.get_bone_count() if skel != null else -1])


## 动画接线：静止→Idle、走动→Walk、冲刺→Run、停下→Idle。
## 这段验证的是 `animal_body.gd` 里 ART03-④ 的视觉动画逻辑（只读速度与冲刺意图，不写玩法状态）。
func _check_animation_switch() -> void:
	# 加一块地板，否则鼠会一直自由落体（水平位移仍算，但落地判定更真实）
	var floor_body := StaticBody3D.new()
	floor_body.name = "AnimTestFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0.0, -0.05, 0.0)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.1, 20.0)
	cs.shape = box
	floor_body.add_child(cs)
	_world.add_child(floor_body)

	var cfg: SpeciesConfig = load(MOUSE_CFG)
	var body: AnimalBody = (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.ai_enabled = false
	body.player_controlled = false
	_world.add_child(body)
	body.global_position = Vector3(0.0, 0.2, 0.0)
	for i in 20:
		await physics_frame
	if not _check("anim_bound", body.visual_anim_active):
		return
	_check("anim_idle_when_still", body.visual_anim_current == &"Idle")

	body.move_intent = Vector2(0.0, -1.0)
	body.want_sprint = false
	for i in 30:
		await physics_frame
	_check("anim_walk_when_moving", body.visual_anim_current == &"Walk")
	var walk_speed := body.horizontal_speed()

	body.want_sprint = true
	for i in 40:
		await physics_frame
	_check("anim_run_when_sprinting", body.visual_anim_current == &"Run")
	var run_speed := body.horizontal_speed()
	_check("anim_run_faster_than_walk", run_speed > walk_speed)

	body.move_intent = Vector2.ZERO
	body.want_sprint = false
	for i in 40:
		await physics_frame
	_check("anim_idle_after_stop", body.visual_anim_current == &"Idle")
	print("MEASURE|anim_switch|walk_speed=%.3f|run_speed=%.3f|final_clip=%s" % [
		walk_speed, run_speed, body.visual_anim_current])


func _find_first(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r := _find_first(c, cls)
		if r != null:
			return r
	return null


func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for c in node.get_children():
		var r := _find_first_mesh(c)
		if r != null:
			return r
	return null


func _count_shapes(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is CollisionShape3D:
			c += 1
		c += _count_shapes(ch)
	return c


func _check(id: String, ok: bool) -> bool:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s" % [id, "PASS" if ok else "FAIL"])
	return ok
