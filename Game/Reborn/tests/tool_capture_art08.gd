extends SceneTree
## ART03-④（鼠换源）：在真实关卡里把**鼠**放到地面并出图，验证视觉替换在引擎里真的生效。
##
## 运行（**不能用 --headless**）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_art08.gd' --quit-after 2400 -- art08

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MOUSE_CFG := "res://resources/species/mouse.tres"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const SETTLE := 45
const RES := Vector2i(1280, 720)
## 放在庭院开阔处（远离猫出生点与围栏），y 取地面顶面
const SPAWN := Vector3(2.0, 0.10, 12.0)

var _world: Node3D = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("art08"):
		print("CAP|art08|ERROR|need_arg|pass '-- art08'")
		quit(1)
		return
	root.size = RES
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CAP|art08|ERROR|level_load_failed")
		quit(1)
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	await process_frame
	await process_frame

	var cfg: SpeciesConfig = load(MOUSE_CFG)
	var body: AnimalBody = (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.ai_enabled = false
	body.player_controlled = false
	_world.add_child(body)
	body.global_position = SPAWN
	for i in 6:
		await physics_frame
	_report(body)

	var cam := Camera3D.new()
	cam.name = "Art08Cam"
	cam.near = 0.01
	cam.far = 200.0
	_world.add_child(cam)
	await process_frame
	var views := [
		{"tag": "art08_mouse_side", "pos": SPAWN + Vector3(0.42, 0.13, 0.0), "look": SPAWN + Vector3(0.0, 0.05, 0.0), "fov": 45.0},
		{"tag": "art08_mouse_q34", "pos": SPAWN + Vector3(0.30, 0.22, -0.32), "look": SPAWN + Vector3(0.0, 0.04, 0.0), "fov": 45.0},
	]
	for v in views:
		cam.fov = v["fov"]
		cam.look_at_from_position(v["pos"], v["look"], Vector3.UP)
		cam.current = true
		print("CAP|art08|view=%s|cam_pos=%s|look=%s" % [v["tag"], v["pos"], v["look"]])
		await _save(v["tag"])
	print("CAP|art08|done")
	quit(0)


func _report(body: AnimalBody) -> void:
	var vis: Node3D = body.visual_root
	print("CAP|art08|body|pos=%s|visual=%s|visual_pos=%s|body_mesh_visible=%s" % [
		body.global_position,
		vis.scene_file_path if vis != null else "<none>",
		vis.position if vis != null else Vector3.ZERO,
		str(body.body_mesh != null and body.body_mesh.visible)])
	var skel := _find(vis, "Skeleton3D") as Skeleton3D
	var ap := _find(vis, "AnimationPlayer") as AnimationPlayer
	print("CAP|art08|visual|bones=%d|anims=%s" % [
		skel.get_bone_count() if skel != null else -1,
		str(ap.get_animation_list()) if ap != null else "<none>"])
	if ap != null:
		ap.play("Idle")
		print("CAP|art08|anim|playing=Idle")


func _find(node: Node, cls: String) -> Node:
	if node == null:
		return null
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _save(tag: String) -> void:
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		print("CAP|art08|%s|ERROR|no_viewport_texture" % tag)
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|art08|%s|ERROR|no_image" % tag)
		return
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|art08|%s|save_result=%d (%s)|global=%s" % [
		tag, err, "OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)])
