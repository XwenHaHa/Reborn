extends SceneTree
## ART03-②：溪边巨石 `CreekBoulder` 的**实机关卡**捕获工具。
##
## 为什么单独写：ART01/ART02 的捕获工具各自只覆盖自己的资产；巨石要同时拍"岩石本体"
## 与"它与溪岸墙/水面的相对位置"，所以机位必须落在真实 `l_courtyard.tscn` 里。
##
## 运行（必须显式给模式参数，避免误跑；**不能用 --headless**，无头是 dummy 渲染器）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_art05.gd' --quit-after 2400 -- art05-level
##
## 每张图打印客观像素统计（`PIX|`），换资产前后可用**数值**对比，而不只靠"看着像"。

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BOULDER := "res://assets/environment/sm_boulder_001.glb"
const SETTLE := 45          # 0.75 s @60Hz：等阴影与天空环境光生效
const RES := Vector2i(1280, 720)

## 巨石实测中心：机身 (-14.0, 0.10..1.10, 8.0)，包围盒 1.269 × 1.004 × 1.829
const TARGET := Vector3(-14.0, 0.55, 8.0)

const VIEWS := [
	{"tag": "art05_level_boulder_wide", "pos": Vector3(-22.0, 2.60, 15.5), "look": TARGET, "fov": 50.0},
	{"tag": "art05_level_boulder_front", "pos": Vector3(-14.0, 1.30, 12.6), "look": TARGET, "fov": 45.0},
	{"tag": "art05_level_boulder_corner", "pos": Vector3(-10.8, 1.55, 12.0), "look": TARGET, "fov": 45.0},
	{"tag": "art05_level_boulder_close", "pos": Vector3(-12.4, 0.75, 10.6), "look": Vector3(-14.0, 0.45, 8.0), "fov": 50.0},
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	print("CAP|art05|start|renderer=%s|args=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"), str(args)])
	root.size = RES
	if args.has("art05-level"):
		await _run_level()
	else:
		print("CAP|art05|ERROR|need_arg|pass '-- art05-level'")
	print("CAP|art05|done")
	quit(0)


func _run_level() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CAP|art05|ERROR|level_load_failed")
		return
	var level: Node3D = packed.instantiate() as Node3D
	root.add_child(level)
	print("CAP|art05|level=%s|loaded=true" % LEVEL)
	_report_boulder(level)

	var cam := Camera3D.new()
	cam.name = "Art05Cam"
	cam.near = 0.05
	cam.far = 400.0
	level.add_child(cam)
	# 实测踩到过：add_child 后立刻 look_at 会报 "Node not inside tree"，机位静默保留默认朝向。
	await process_frame
	for v in VIEWS:
		cam.fov = v["fov"]
		cam.look_at_from_position(v["pos"], v["look"], Vector3.UP)
		cam.current = true
		print("CAP|art05|view=%s|cam_pos=%s|look=%s|fov=%.1f" % [v["tag"], v["pos"], v["look"], v["fov"]])
		await _save(v["tag"])


## 客观证据：巨石的节点结构（视觉是不是 glb 实例、碰撞盒尺寸、视觉是否贴合地面）。
func _report_boulder(level: Node) -> void:
	var body := level.get_node_or_null("CreekBoulder") as StaticBody3D
	if body == null:
		print("CAP|art05|boulder|MISSING")
		return
	var vis := body.get_node_or_null("Mesh") as Node3D
	if vis != null:
		print("CAP|art05|boulder|body=%s|class=%s|pos=%s|rot_deg=%s|visual_scene=%s|visual_pos=%s" % [
			body.name, body.get_class(), body.position, body.rotation_degrees,
			vis.scene_file_path, vis.position])
		var mesh_inst := vis.find_child("*", true, false) as MeshInstance3D
		if mesh_inst == null:
			mesh_inst = vis as MeshInstance3D
		if mesh_inst != null and mesh_inst.mesh != null:
			print("CAP|art05|boulder_visual|mesh=%s|aabb_size=%s|surfaces=%d" % [
				mesh_inst.mesh.get_class(), mesh_inst.mesh.get_aabb().size, mesh_inst.mesh.get_surface_count()])
	else:
		print("CAP|art05|boulder|body=%s|visual_scene=MISSING" % body.name)
	var cs := body.get_node_or_null("Shape") as CollisionShape3D
	var box := cs.shape as BoxShape3D if cs != null else null
	if box != null:
		print("CAP|art05|boulder_collision|BoxShape3D|size=%s|shape_count=%d" % [
			box.size, _count_shapes(body)])


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
		print("CAP|art05|%s|ERROR|no_viewport_texture" % tag)
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|art05|%s|ERROR|no_image" % tag)
		return
	var active := vp.get_camera_3d()
	_pixel_stats(tag, img)
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|art05|%s|active_camera=%s|save_result=%d (%s)|path=%s|global=%s" % [
		tag, active.name if active != null else "<none>", err, "OK" if err == OK else "FAIL",
		path, ProjectSettings.globalize_path(path)])


func _pixel_stats(tag: String, img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var total := 0.0
	var mn := 1.0
	var mx := 0.0
	var step := 4
	var n := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			total += lum
			mn = minf(mn, lum)
			mx = maxf(mx, lum)
			n += 1
	print("PIX|%s|size=%dx%d|sampled=%d|mean_lum=%.4f|min_lum=%.4f|max_lum=%.4f" % [
		tag, w, h, n, total / float(maxi(n, 1)), mn, mx])
