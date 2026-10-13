extends SceneTree
## 渲染捕获工具：让 **引擎自己**把渲染结果存成 PNG，并输出客观像素统计。
##
## 为什么不用屏幕截图：
##   屏幕截图依赖窗口可见、在前台、未被遮挡、DPI 缩放正确。实测中游戏窗口
##   会处于 (-25600,-25600) 且客户区 0x0（Windows 最小化位置），导致截到的是
##   桌面背景 → 视觉分析拿到无效输入、两次结论互相矛盾。
##   由引擎直接导出 viewport 纹理则完全绕开这些问题。
##
## 注意：**不能用 --headless**（无头是 dummy 渲染器，没有真实画面）。
##
## 运行：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/tool_capture_render.gd' --quit-after 400

const LAB := "res://scenes/maps/l_movement_lab.tscn"
const OUT_USER := "user://render_capture.png"
const SETTLE_FRAMES := 90   # 1.5s @60Hz，等场景稳定与光照生效


func _initialize() -> void:
	print("CAP|start|renderer=%s" % ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))

	var packed: PackedScene = load(LAB)
	if packed == null:
		print("CAP|ERROR|load failed")
		quit(1)
		return
	var lab: Node = packed.instantiate()
	root.add_child(lab)

	# 玩家脚本 _ready 会捕获鼠标；捕获工具不该劫持用户光标，立刻放开
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# 等场景稳定 + 完成渲染
	for i in SETTLE_FRAMES:
		await process_frame

	# 确认相机确实激活并有内容
	var vp := root.get_viewport()
	var cam := vp.get_camera_3d()
	print("CAP|viewport_size=%s" % vp.get_visible_rect().size)
	print("CAP|active_camera=%s" % (cam.name if cam else "<none>"))
	if cam:
		print("CAP|camera_global_pos=%s|global_rot_deg=%s|fov=%.1f" % [
			cam.global_position, cam.global_rotation_degrees, cam.fov
		])

	# 取渲染结果
	var tex := vp.get_texture()
	if tex == null:
		print("CAP|ERROR|no viewport texture")
		quit(1)
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|ERROR|no image")
		quit(1)
		return

	print("CAP|image_size=%dx%d|format=%d" % [img.get_width(), img.get_height(), img.get_format()])
	_pixel_stats(img)

	var err := img.save_png(OUT_USER)
	print("CAP|save_png_result=%d (%s)" % [err, "OK" if err == OK else "FAIL"])
	print("CAP|saved_to=%s" % ProjectSettings.globalize_path(OUT_USER))
	print("CAP|done")
	quit(0)


## 客观像素统计：用于判断"是否渲染出了有内容的三维画面"，
## 而不是依赖对图像的语义描述。
##   unique_colors 很少      → 基本是纯色/空白
##   luminance_range 很小    → 没有明暗结构
##   key_color_ratio 接近 1  → 几乎全是 Godot 的 default_clear_color（0.15,0.17,0.2）
##                             —— 即"什么都没画出来"的典型特征
func _pixel_stats(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	# 采样步长：大图不必逐像素，统计意义相同
	var step: int = maxi(1, int(minf(w, h) / 200.0))

	var colors := {}
	var lum_min := 1e9
	var lum_max := -1e9
	var lum_sum := 0.0
	var n := 0
	var clear_like := 0
	# Godot default_clear_color 默认 (0.15,0.17,0.2)
	var cc := Color(0.15, 0.17, 0.2)

	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			var key := "%02x%02x%02x" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]
			colors[key] = true
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			lum_min = minf(lum_min, lum)
			lum_max = maxf(lum_max, lum)
			lum_sum += lum
			# 与 clear color 的差是否极小
			if absf(c.r - cc.r) < 0.02 and absf(c.g - cc.g) < 0.02 and absf(c.b - cc.b) < 0.02:
				clear_like += 1
			n += 1

	print("CAP|stats|sampled=%d|unique_colors=%d" % [n, colors.size()])
	print("CAP|stats|lum_min=%.4f|lum_max=%.4f|lum_mean=%.4f|range=%.4f" % [
		lum_min, lum_max, lum_sum / float(n), lum_max - lum_min
	])
	print("CAP|stats|clear_color_like_ratio=%.4f" % (float(clear_like) / float(n)))
