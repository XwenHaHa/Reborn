extends SceneTree
## 总览图工具：一次拍一组"看全局"的机位（俯瞰 + 各分区广角），用于进度全览。
##
## 用法：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_overview.gd' --quit-after 90000 -- overview
##
## 产物：user://overview_*.png（拷到 Art/Probes/ 作为证据）

const RES := Vector2i(1280, 720)
const SETTLE := 12
const LEVEL := "res://scenes/maps/l_courtyard.tscn"

## 机位：俯瞰全场 → 庇护棚区 → 溪流区 → 树根洞/屏障 → 玩家视角走廊
const VIEWS := [
	{"tag": "overview_top", "pos": Vector3(0.0, 62.0, 68.0), "look": Vector3(0.0, 0.0, 2.0), "fov": 60.0},
	{"tag": "overview_shelter_wide", "pos": Vector3(-17.0, 6.5, 16.5), "look": Vector3(-7.0, 0.8, 27.0), "fov": 55.0},
	{"tag": "overview_creek", "pos": Vector3(-10.0, 5.0, 5.0), "look": Vector3(-23.0, 0.2, 16.0), "fov": 60.0},
	{"tag": "overview_roothole", "pos": Vector3(16.0, 4.0, 8.0), "look": Vector3(26.5, 0.6, 19.0), "fov": 55.0},
	{"tag": "overview_playerview", "pos": Vector3(2.0, 1.30, 23.0), "look": Vector3(-7.0, 0.9, 8.0), "fov": 72.0},
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	root.size = RES
	if args.has("overview"):
		await _run()
	else:
		print("CAP|overview|ERROR|need_arg|pass '-- overview'")
	print("CAP|overview|done")
	quit(0)


func _run() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CAP|overview|ERROR|level_load_failed")
		return
	var level: Node3D = packed.instantiate() as Node3D
	root.add_child(level)
	print("CAP|overview|level=%s|loaded=true" % LEVEL)

	var cam := Camera3D.new()
	cam.name = "OverviewCam"
	cam.near = 0.05
	cam.far = 500.0
	level.add_child(cam)
	await process_frame
	for v in VIEWS:
		cam.fov = v["fov"]
		cam.look_at_from_position(v["pos"], v["look"], Vector3.UP)
		cam.current = true
		print("CAP|overview|view=%s|cam=%s|look=%s|fov=%.1f" % [
			v["tag"], v["pos"], v["look"], v["fov"]])
		await _save(v["tag"])


func _save(tag: String) -> void:
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		print("CAP|overview|%s|ERROR|no_texture" % tag)
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|overview|%s|ERROR|no_image" % tag)
		return
	_pixel_stats(tag, img)
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|overview|%s|save_result=%d (%s)|global=%s" % [
		tag, err, "OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)])


func _pixel_stats(tag: String, img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var total := 0.0
	var n := 0
	for y in range(0, h, 8):
		for x in range(0, w, 8):
			var c := img.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	print("PIX|%s|size=%dx%d|mean_lum=%.4f" % [tag, w, h, total / float(maxi(n, 1))])
