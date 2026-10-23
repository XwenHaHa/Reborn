extends SceneTree
## ART03-③：石墙/围栏（`FenceNorth/South/West/East` + 庇护棚三面墙）的**实机关卡**捕获工具。
##
## 运行（必须显式给模式参数；**不能用 --headless**，无头是 dummy 渲染器）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_art06.gd' --quit-after 2400 -- art06-level
##
## 每张图打印客观像素统计（`PIX|`），并打印墙段的节点事实（平铺块数/衬板/缩放）。

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const FENCE_ASSET := "res://assets/environment/sm_fence_module_001.glb"
const SETTLE := 45
const RES := Vector2i(1280, 720)

## 机位：站在可玩区内看边界墙；再拍一张庇护棚的内部感受
const VIEWS := [
	{"tag": "art06_fence_north_interior", "pos": Vector3(0.0, 1.65, 22.0), "look": Vector3(0.0, 1.20, 30.0), "fov": 60.0},
	{"tag": "art06_fence_corner", "pos": Vector3(24.0, 1.80, 20.0), "look": Vector3(35.0, 1.20, 29.0), "fov": 60.0},
	{"tag": "art06_fence_west_close", "pos": Vector3(-32.0, 1.30, 18.0), "look": Vector3(-36.0, 1.20, 22.0), "fov": 55.0},
	{"tag": "art06_shelter", "pos": Vector3(-11.6, 1.35, 27.3), "look": Vector3(-8.0, 0.90, 27.3), "fov": 60.0},
	{"tag": "art06_shelter_q34", "pos": Vector3(-12.4, 1.75, 22.6), "look": Vector3(-8.2, 0.85, 27.2), "fov": 55.0},
	{"tag": "art06_shelter_face", "pos": Vector3(-8.0, 1.00, 23.2), "look": Vector3(-8.0, 0.80, 25.7), "fov": 55.0},
	{"tag": "art06_shelter_corner_sw", "pos": Vector3(-11.1, 1.15, 24.3), "look": Vector3(-9.35, 0.80, 25.85), "fov": 55.0},
	{"tag": "art06_shelter_jamb", "pos": Vector3(-4.4, 1.15, 24.5), "look": Vector3(-6.6, 0.80, 25.85), "fov": 55.0},
	# NW 角：庇护棚北侧只剩 1 m 空隙（外面就是围栏），所以从棚内门口回望西北角
	{"tag": "art06_shelter_corner_nw", "pos": Vector3(-6.9, 1.30, 26.9), "look": Vector3(-9.30, 0.95, 28.80), "fov": 60.0},
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	print("CAP|art06|start|renderer=%s|args=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"), str(args)])
	root.size = RES
	if args.has("art06-level"):
		await _run_level()
	else:
		print("CAP|art06|ERROR|need_arg|pass '-- art06-level'")
	print("CAP|art06|done")
	quit(0)


func _run_level() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CAP|art06|ERROR|level_load_failed")
		return
	var level: Node3D = packed.instantiate() as Node3D
	root.add_child(level)
	print("CAP|art06|level=%s|loaded=true" % LEVEL)
	_report_walls(level)

	var cam := Camera3D.new()
	cam.name = "Art06Cam"
	cam.near = 0.05
	cam.far = 400.0
	level.add_child(cam)
	await process_frame
	for v in VIEWS:
		cam.fov = v["fov"]
		cam.look_at_from_position(v["pos"], v["look"], Vector3.UP)
		cam.current = true
		print("CAP|art06|view=%s|cam_pos=%s|look=%s|fov=%.1f" % [v["tag"], v["pos"], v["look"], v["fov"]])
		await _save(v["tag"])


func _report_walls(level: Node) -> void:
	var names := ["FenceNorth", "FenceSouth", "FenceWest", "FenceEast",
		"ShelterWallWest", "ShelterWallNorth", "ShelterWallSouth"]
	var total_tris := 0
	for nm in names:
		var body := level.get_node_or_null(nm) as StaticBody3D
		if body == null:
			print("CAP|art06|wall|%s|MISSING" % nm)
			continue
		var cs := body.get_node_or_null("Shape") as CollisionShape3D
		var box := cs.shape as BoxShape3D if cs != null else null
		var tiles := body.get_node_or_null("Tiles")
		var first := tiles.get_child(0) as Node3D if tiles != null and tiles.get_child_count() > 0 else null
		var backing := body.get_node_or_null("Backing") as MeshInstance3D
		var tris := 0
		if first != null:
			var mi := first.find_child("*", true, false) as MeshInstance3D
			if mi != null and mi.mesh != null:
				tris = mi.mesh.get_faces().size() / 3
		var cnt := tiles.get_child_count() if tiles != null else 0
		total_tris += tris * cnt
		print("CAP|art06|wall|%s|box=%s|tiles=%d|tile_scene=%s|tile_scale=%.3f|tris_per_tile=%d|backing=%s" % [
			nm, box.size if box != null else "<none>", cnt,
			first.scene_file_path if first != null else "<none>",
			first.scale.y if first != null else 0.0, tris,
			"yes" if backing != null else "no"])
	print("CAP|art06|tiles_total_tris=%d|asset=%s" % [total_tris, FENCE_ASSET])


func _save(tag: String) -> void:
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		print("CAP|art06|%s|ERROR|no_viewport_texture" % tag)
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|art06|%s|ERROR|no_image" % tag)
		return
	var active := vp.get_camera_3d()
	_pixel_stats(tag, img)
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|art06|%s|active_camera=%s|save_result=%d (%s)|global=%s" % [
		tag, active.name if active != null else "<none>", err,
		"OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)])


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
