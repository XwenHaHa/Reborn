extends SceneTree
## ART03-④：鼠洞树桩（`RootHoleStump`）的**实机关卡**捕获工具。
##
## 运行（必须显式给模式参数；**不能用 --headless**）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_art07.gd' --quit-after 2400 -- art07-level

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const ROOT_HOLE_ASSET := "res://assets/environment/sm_root_hole_001.glb"
const SETTLE := 45
const RES := Vector2i(1280, 720)

## 洞口中心 (26.50, 0.10, 19.00)；机制孔 0.24 宽 × 0.30 高
const VIEWS := [
	{"tag": "art07_hole_approach", "pos": Vector3(26.50, 0.42, 17.15), "look": Vector3(26.50, 0.25, 19.00), "fov": 55.0},
	{"tag": "art07_hole_q34", "pos": Vector3(27.45, 0.62, 17.55), "look": Vector3(26.50, 0.25, 19.00), "fov": 50.0},
	{"tag": "art07_hole_north", "pos": Vector3(26.50, 0.45, 20.95), "look": Vector3(26.50, 0.25, 19.00), "fov": 55.0},
	{"tag": "art07_barrier_wide", "pos": Vector3(22.00, 1.60, 13.50), "look": Vector3(26.50, 0.30, 19.00), "fov": 55.0},
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	print("CAP|art07|start|renderer=%s|args=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"), str(args)])
	root.size = RES
	if args.has("art07-level"):
		await _run_level()
	else:
		print("CAP|art07|ERROR|need_arg|pass '-- art07-level'")
	print("CAP|art07|done")
	quit(0)


func _run_level() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CAP|art07|ERROR|level_load_failed")
		return
	var level: Node3D = packed.instantiate() as Node3D
	root.add_child(level)
	_report(level)

	var cam := Camera3D.new()
	cam.name = "Art07Cam"
	cam.near = 0.02
	cam.far = 400.0
	level.add_child(cam)
	await process_frame
	for v in VIEWS:
		cam.fov = v["fov"]
		cam.look_at_from_position(v["pos"], v["look"], Vector3.UP)
		cam.current = true
		print("CAP|art07|view=%s|cam_pos=%s|look=%s|fov=%.1f" % [v["tag"], v["pos"], v["look"], v["fov"]])
		await _save(v["tag"])


func _report(level: Node) -> void:
	for nm in ["RootHoleStumpS", "RootHoleStumpN"]:
		var stump := level.get_node_or_null(nm) as Node3D
		if stump == null:
			print("CAP|art07|stump|%s|MISSING" % nm)
			continue
		var mi := stump.find_child("*", true, false) as MeshInstance3D
		var aabb := AABB()
		if mi != null and mi.mesh != null:
			aabb = mi.mesh.get_aabb()
		print("CAP|art07|stump|%s|scene=%s|pos=%s|rot_deg=%s|scale=%s|aabb_size=%s|shapes=%d" % [
			nm, stump.scene_file_path, stump.position, stump.rotation_degrees, stump.scale,
			aabb.size, _count_shapes(stump)])
	for nm in ["RootBarrierWest", "RootBarrierEast", "RootBarrierLintel"]:
		var b := level.get_node_or_null(nm) as StaticBody3D
		if b == null:
			print("CAP|art07|barrier|%s|MISSING" % nm)
			continue
		var cs := b.get_node_or_null("Shape") as CollisionShape3D
		var box := cs.shape as BoxShape3D if cs != null else null
		print("CAP|art07|barrier|%s|box=%s|pos=%s" % [nm, box.size if box != null else Vector3.ZERO, b.position])


func _count_shapes(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is CollisionShape3D:
			c += 1
		c += _count_shapes(ch)
	return c


func _save(tag: String) -> void:
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		print("CAP|art07|%s|ERROR|no_viewport_texture" % tag)
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|art07|%s|ERROR|no_image" % tag)
		return
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|art07|%s|save_result=%d (%s)|global=%s" % [
		tag, err, "OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)])
