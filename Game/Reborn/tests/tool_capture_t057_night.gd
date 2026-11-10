extends SceneTree
## T057：昼夜光照的**实拍**取证工具（正午 vs 夜间同机位）。
##
## 为什么必须实拍：`夜间可读`（"夜晚仍需看清基本路线"）是**视觉**判据，光验证
## `ambient_light_energy ≥ 0.26` 只能说明"参数有个下界"，说明不了画面是否看得清。
##
## 运行（**不能用 --headless**，headless 是 dummy 渲染器，出不了图）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_t057_night.gd' --quit-after 4000 -- t057
##
## 输出：`Art/Probes/t057_{noon,night}_{playerview,top}.png`，每张打印平均亮度（`PIX|`）。

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const OUT_DIR := "E:/Reborn/Art/Probes"
const RES := Vector2i(1280, 720)
const SETTLE := 12          # 等光照/阴影生效

## 时间点：300 s = 正午；900 s = 午夜（`day_length = 1200`，T034 口径）
const SHOTS := [
	{"tag": "noon_playerview", "time": 300.0, "pos": Vector3(2.0, 1.30, 23.0), "look": Vector3(-7.0, 0.9, 8.0), "fov": 72.0},
	{"tag": "night_playerview", "time": 900.0, "pos": Vector3(2.0, 1.30, 23.0), "look": Vector3(-7.0, 0.9, 8.0), "fov": 72.0},
	{"tag": "noon_top", "time": 300.0, "pos": Vector3(0.0, 62.0, 68.0), "look": Vector3(0.0, 0.0, 2.0), "fov": 60.0},
	{"tag": "night_top", "time": 900.0, "pos": Vector3(0.0, 62.0, 68.0), "look": Vector3(0.0, 0.0, 2.0), "fov": 60.0},
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	print("CAP|t057|start|renderer=%s|args=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"), str(args)])
	if not args.has("t057"):
		print("CAP|t057|ERROR|need_arg|pass '-- t057'")
		print("CAP|t057|done")
		quit(0)
		return
	await process_frame
	root.size = RES
	await _run()
	print("CAP|t057|done")
	quit(0)


func _run() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CAP|t057|ERROR|level_load_failed")
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	await process_frame

	var dn := root.get_node_or_null("/root/DayNightDirector")
	var wd := root.get_node_or_null("/root/WorldDirector")
	if dn == null or wd == null:
		print("CAP|t057|ERROR|director_missing")
		return
	var bound: bool = bool(dn.call("bind_level", level))
	print("CAP|t057|bound=%s" % bound)

	var cam := Camera3D.new()
	cam.name = "T057Cam"
	cam.near = 0.05
	cam.far = 500.0
	level.add_child(cam)
	await process_frame

	for shot in SHOTS:
		wd.call("set_world_time", float(shot["time"]))
		dn.call("apply_now")
		cam.fov = shot["fov"]
		cam.look_at_from_position(shot["pos"], shot["look"], Vector3.UP)
		cam.current = true
		for i in SETTLE:
			await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		if img == null:
			print("CAP|t057|ERROR|no_image|%s" % shot["tag"])
			continue
		var path := "%s/t057_%s.png" % [OUT_DIR, shot["tag"]]
		var err := img.save_png(path)
		print("CAP|t057|shot=%s|time=%.0f|path=%s|err=%d|%s" % [
			shot["tag"], float(shot["time"]), path, err, _stats(img)])
		_measure(dn, shot["tag"])


func _stats(img: Image) -> String:
	# 平均亮度（0..255）：夜景判读的客观陪衬，不是判据本身
	var w := img.get_width()
	var h := img.get_height()
	var total := 0.0
	var n := 0
	var step := maxi(1, w / 64)
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	var mean := (total / maxf(1.0, float(n))) * 255.0
	return "PIX|mean_luma=%.1f" % mean


func _measure(dn: Node, tag: String) -> void:
	var s: Dictionary = dn.get("last_sample")
	if s.is_empty():
		return
	print("LIGHT|%s|is_day=%s|elev=%.2f|energy=%.3f|ambient=%.3f|color=(%.2f,%.2f,%.2f)" % [
		tag, s["is_day"], float(s["elevation_deg"]), float(s["energy"]), float(s["ambient"]),
		(s["color"] as Color).r, (s["color"] as Color).g, (s["color"] as Color).b])
