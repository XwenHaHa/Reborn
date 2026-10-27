extends SceneTree
## ART08 角色接入契约：验证现有猫/鼠资产不破坏玩法胶囊，并记录新增资产授权阻塞。

const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const SPECIES := ["res://resources/species/cat.tres", "res://resources/species/mouse.tres"]
var _checks := 0
var _fails := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	var body_scene := load(BODY_SCENE) as PackedScene
	_check("body_scene_loads", body_scene != null)
	for path in SPECIES:
		var cfg := load(path) as SpeciesConfig
		_check("config_loads_%s" % path.get_file(), cfg != null)
		if cfg == null:
			continue
		_check("visual_scene_set_%s" % String(cfg.species_id), cfg.visual_scene != null)
		_check("config_valid_%s" % String(cfg.species_id), cfg.validate_config().is_empty())
		if cfg.visual_scene != null:
			var inst := cfg.visual_scene.instantiate()
			_check("visual_instantiates_%s" % String(cfg.species_id), inst != null)
			_check("visual_is_node3d_%s" % String(cfg.species_id), inst is Node3D)
			if inst != null:
				var mesh := _find_mesh(inst)
				_check("visual_mesh_exists_%s" % String(cfg.species_id), mesh != null)
				_check("visual_has_no_collision_%s" % String(cfg.species_id), _find_collision(inst) == null)
				inst.free()
		print("ASSET|species=%s|visual=%s|animations=%s|status=existing_fallback" % [
			String(cfg.species_id), cfg.visual_scene.resource_path,
			str(_animation_names(cfg.visual_scene))])
	print("ASSET|rabbit=blocked|fox=blocked|bird=blocked|reason=authorization_required")
	_finish()

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null

func _find_collision(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node as CollisionShape3D
	for child in node.get_children():
		var found := _find_collision(child)
		if found != null:
			return found
	return null

func _animation_names(scene: PackedScene) -> Array[String]:
	var root_node := scene.instantiate()
	var out: Array[String] = []
	var player := _find_animation_player(root_node)
	if player != null:
		for name in player.get_animation_list():
			out.append(String(name))
	root_node.free()
	return out

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s" % [label, "PASS" if ok else "FAIL"])

func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
