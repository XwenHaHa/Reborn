extends SceneTree
## ART03-⑥：溪水/溪边的**运动取证**工具。
##
## 为什么需要：负责人指出"水都不带动的"。这类判断不能靠"我改了 shader 所以它应该动"——
## 这里在**同一机位**采两帧（相隔若干帧），直接算像素差：
##   水面区域平均亮度差 > 0 且不接近 0 ⇒ 画面确实在变（shader 的 TIME 生效）。
## 同时打印水体材质类型与芦苇丛数量，确认生成器真的接上了。
##
## 运行（**不能用 --headless**）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_creek.gd' --quit-after 3000 -- creek

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const SETTLE := 40
const GAP_FRAMES := 45          # 两帧间隔：0.75 s @60Hz（水面图案应已明显移动）
const RES := Vector2i(1280, 720)

## 水在画面下半部：取 y∈[55%, 95%]、x∈[10%, 90%] 作为"水面区域"
const WATER_REGION := Rect2(0.10, 0.55, 0.80, 0.40)

const VIEWS := [
	{"tag": "creek_wide", "pos": Vector3(-20.0, 1.8, 16.0), "look": Vector3(-28.0, 0.5, 10.0), "fov": 55.0},
	{"tag": "creek_low", "pos": Vector3(-19.0, 0.55, 20.0), "look": Vector3(-26.0, 0.15, 12.0), "fov": 60.0},
]

var _world: Node3D = null
var _cam: Camera3D = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("creek"):
		print("CREEK|ERROR|need_arg|pass '-- creek'")
		quit(1)
		return
	root.size = RES
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CREEK|ERROR|level_load_failed")
		quit(1)
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	await process_frame
	_report_nodes()

	_cam = Camera3D.new()
	_cam.name = "CreekCam"
	_cam.near = 0.05
	_cam.far = 400.0
	_world.add_child(_cam)
	await process_frame

	for v in VIEWS:
		_cam.fov = v["fov"]
		_cam.look_at_from_position(v["pos"], v["look"], Vector3.UP)
		_cam.current = true
		for i in SETTLE:
			await process_frame
		var a := await _grab()
		if a == null:
			continue
		for i in GAP_FRAMES:
			await process_frame
		var b := await _grab()
		if b == null:
			continue
		_diff_and_save(v["tag"], a, b)
	print("CREEK|done")
	quit(0)


func _report_nodes() -> void:
	var water := _world.get_node_or_null("CreekWater") as MeshInstance3D
	if water == null:
		print("CREEK|water|MISSING")
	else:
		var mat := water.material_override
		var mat_kind := "none"
		if mat is ShaderMaterial:
			mat_kind = "ShaderMaterial(shader=%s)" % (mat as ShaderMaterial).shader.resource_path
		elif mat is StandardMaterial3D:
			mat_kind = "StandardMaterial3D(STATIC)"
		print("CREEK|water|node=%s|mesh=%s|material=%s|group_water_bodies=%s" % [
			water.name, water.mesh.get_class(), mat_kind,
			str(water.is_in_group("water_bodies"))])
	var reeds := 0
	for c in _world.get_children():
		if String(c.name).begins_with("CreekReed"):
			reeds += 1
	print("CREEK|reeds|count=%d" % reeds)
	for nm in ["CreekWetBankSouth", "CreekWetBankNorth", "CreekWetBankWest", "CreekWetBankEast"]:
		print("CREEK|wetband|%s=%s" % [nm, str(_world.get_node_or_null(nm) != null)])


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		return null
	return tex.get_image()


func _mean_lum(img: Image, rect: Rect2) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int(rect.position.x * w)
	var y0 := int(rect.position.y * h)
	var x1 := int((rect.position.x + rect.size.x) * w)
	var y1 := int((rect.position.y + rect.size.y) * h)
	var step := 4
	var total := 0.0
	var n := 0
	for y in range(y0, y1, step):
		for x in range(x0, x1, step):
			var c := img.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return total / float(maxi(1, n))


func _diff_and_save(tag: String, a: Image, b: Image) -> void:
	var changed := 0
	var sum_abs := 0.0
	var n := 0
	var w := a.get_width()
	var h := a.get_height()
	var step := 2
	for y in range(0, h, step):
		for x in range(0, w, step):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var la := 0.2126 * ca.r + 0.7152 * ca.g + 0.0722 * ca.b
			var lb := 0.2126 * cb.r + 0.7152 * cb.g + 0.0722 * cb.b
			var d: float = absf(la - lb)
			sum_abs += d
			if d > 0.01:
				changed += 1
			n += 1
	print("CREEK|motion|%s|frames_apart=%d|mean_abs_diff=%.5f|changed_px_ratio=%.4f|water_region_lum_a=%.4f|water_region_lum_b=%.4f" % [
		tag, GAP_FRAMES, sum_abs / float(maxi(1, n)), float(changed) / float(maxi(1, n)),
		_mean_lum(a, WATER_REGION), _mean_lum(b, WATER_REGION)])
	var path_a := "user://%s_a.png" % tag
	var path_b := "user://%s_b.png" % tag
	a.save_png(path_a)
	b.save_png(path_b)
	print("CREEK|saved|%s|%s|%s" % [
		tag, ProjectSettings.globalize_path(path_a), ProjectSettings.globalize_path(path_b)])
