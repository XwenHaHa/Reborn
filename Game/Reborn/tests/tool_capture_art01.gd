extends SceneTree
## ART01 视觉捕获：草丛掩体资产的多角度检查 + 关卡内实景。
##
## 为什么不复用 tests/tool_capture_render.gd：那是 2000+ 行、15 个 T 任务分支的大工具，
## 它默认加载 `l_movement_lab.tscn`（自带 Player）并把相机/光照写死给运动试验用。
## 本工具要的是"资产预览台"：**自己搭光、搭地、搭比例参照物**，不依赖任何关卡。
##
## 不能加 `--headless`（无头是 dummy 渲染器，没有画面）。
##
## 运行（两个模式，必须显式给参数，避免误跑）：
##   preview：三株草丛 + 1 m 立方体 + 猫/鼠比例参照胶囊 + 5 个机位
##     & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##         --script 'res://tests/tool_capture_art01.gd' --quit-after 2400 -- art01-preview
##   level：真实关卡里 4 处草丛掩体的实景（用来做"改造前 / 改造后"对比）
##     & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##         --script 'res://tests/tool_capture_art01.gd' --quit-after 2400 -- art01-level
##
## 每张图都打印客观像素统计（`PIX|`），便于返工前后做**数值**对比，
## 而不是只靠"看起来好点了"。

const BUSH := "res://assets/environment/sm_bush_001.glb"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const SETTLE := 45          # 0.75 s @60Hz：等阴影与天空环境光生效
const RES := Vector2i(1280, 720)

## 预览台布局（米）。相机从 +Z 朝 -Z 看（Godot 前方）。
## v002 修掉的**取景缺陷**：参照物原先放在 z=1.6（比草丛靠近相机 1.6 m），透视让 0.85 m 高的草
## "看起来"只有 1 m 立方体的 1/3 → 视觉判读的比例结论失真。现在草丛与参照物全在 z=0 同一深度。
const BUSH_XS := [-4.0, 0.0, 4.0]
const BUSH_YAWS := [0.0, 47.0, 133.0]
const RULER_POS := Vector3(-2.00, 0.50, 0.0)   # 1 m 立方体（地面顶面 y=0，半边长 0.5）
const CAT_POS := Vector3(2.00, 0.24, 0.0)      # 猫身体：半径 0.16 / 总高 0.48
const MOUSE_POS := Vector3(2.42, 0.09, 0.0)    # 鼠身体：半径 0.06 / 总高 0.18

## 预览机位：tag / 相机位置 / 注视点 / fov
const PREVIEW_VIEWS := [
	{"tag": "art01_preview_front", "pos": Vector3(0.0, 1.50, 11.0), "look": Vector3(0.0, 0.45, 0.0), "fov": 45.0},
	{"tag": "art01_preview_scale", "pos": Vector3(0.0, 1.10, 6.4), "look": Vector3(0.0, 0.45, 0.0), "fov": 45.0},
	{"tag": "art01_preview_corner45", "pos": Vector3(4.6, 1.60, 4.6), "look": Vector3(0.0, 0.40, 0.0), "fov": 45.0},
	{"tag": "art01_preview_side", "pos": Vector3(9.0, 0.90, 0.0), "look": Vector3(0.0, 0.40, 0.0), "fov": 40.0},
	# 叶形近景：单片草叶宽 1–3 cm，在 6~11 m 外只有 1–3 像素 → 远景点位**无法**判读"叶尖是否收尖、
	# 弧线是否自然"。这里把相机压到 1.6 m、fov 30，让一丛草占满画面。
	{"tag": "art01_preview_blade_close", "pos": Vector3(-0.9, 0.55, 1.55), "look": Vector3(0.0, 0.42, 0.0), "fov": 30.0},
	# 关键机位：**从草丛内部**往外看。草叶是单面时这里会看到"空"（单面剔除的直接证据）。
	{"tag": "art01_preview_inside", "pos": Vector3(0.0, 0.30, 0.0), "look": Vector3(0.0, 0.30, 2.0), "fov": 90.0},
	{"tag": "art01_preview_top", "pos": Vector3(0.0, 9.0, 0.02), "look": Vector3(0.0, 0.0, 0.0), "fov": 35.0},
]

## 关卡机位：覆盖 4 处草丛掩体（改造前 = 半透明绿盒子；改造后 = 草丛资产）
const LEVEL_VIEWS := [
	{"tag": "art01_level_west_a", "pos": Vector3(-8.0, 1.90, 2.0), "look": Vector3(-16.0, 0.50, -6.0), "fov": 55.0},
	{"tag": "art01_level_west_a_near", "pos": Vector3(-12.6, 0.75, -3.0), "look": Vector3(-16.0, 0.45, -6.0), "fov": 60.0},
	{"tag": "art01_level_creek", "pos": Vector3(-20.0, 1.80, 16.0), "look": Vector3(-28.0, 0.50, 10.0), "fov": 55.0},
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	print("CAP|art01|start|renderer=%s|args=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"), str(args)])
	root.size = RES
	if args.has("art01-preview"):
		await _run_preview()
	elif args.has("art01-level"):
		await _run_level()
	else:
		print("CAP|art01|ERROR|need_arg|pass '-- art01-preview' or '-- art01-level'")
		print("CAP|art01|done")
		quit(2)
		return
	print("CAP|art01|done")
	quit(0)


# ---------------------------------------------------------------------------
# 预览台
# ---------------------------------------------------------------------------

func _run_preview() -> void:
	var world := Node3D.new()
	world.name = "Art01Preview"
	root.add_child(world)

	_add_lighting(world)
	_mk_box(world, "Ground", Vector3(16.0, 0.2, 16.0), Vector3(0.0, -0.1, 0.0),
		Color(0.29, 0.29, 0.28), false)

	var ps: PackedScene = load(BUSH)
	if ps == null:
		print("CAP|art01|ERROR|bush_asset_load_failed|%s" % BUSH)
		return
	print("CAP|art01|bush_asset=%s|loaded=true" % BUSH)
	for i in BUSH_XS.size():
		var inst: Node3D = ps.instantiate() as Node3D
		inst.name = "Bush%d" % i
		world.add_child(inst)
		inst.position = Vector3(BUSH_XS[i], 0.0, 0.0)
		inst.rotation_degrees = Vector3(0.0, BUSH_YAWS[i], 0.0)
		print("CAP|art01|placed|name=%s|pos=%s|yaw=%.1f" % [inst.name, inst.position, BUSH_YAWS[i]])

	# 比例参照：1 m 立方体 + 猫/鼠真实胶囊尺寸（判断"草能不能藏住这个物种"）
	_mk_box(world, "Ruler1m", Vector3(1.0, 1.0, 1.0), RULER_POS, Color(0.82, 0.82, 0.80), false)
	_mk_capsule(world, "CatProxy", 0.16, 0.48, CAT_POS, Color(0.62, 0.50, 0.36))
	_mk_capsule(world, "MouseProxy", 0.06, 0.18, MOUSE_POS, Color(0.55, 0.52, 0.50))
	print("CAP|art01|reference|ruler=1.0m_cube|cat=0.16x0.48|mouse=0.06x0.18")

	var cam := Camera3D.new()
	cam.name = "Art01Cam"
	cam.near = 0.05
	cam.far = 400.0
	world.add_child(cam)
	# 必须先让相机真正进入场景树才能摆朝向（**实测踩到**：_initialize 里 add_child 后立刻
	# look_at 会报 "Node not inside tree"，第一个机位静默保留默认朝向 → 图与设计不符）。
	await process_frame
	for v in PREVIEW_VIEWS:
		cam.fov = v["fov"]
		cam.look_at_from_position(v["pos"], v["look"], Vector3.UP)
		cam.current = true
		print("CAP|art01|view=%s|cam_pos=%s|look=%s|fov=%.1f" % [v["tag"], v["pos"], v["look"], v["fov"]])
		await _save(v["tag"])


# ---------------------------------------------------------------------------
# 真实关卡
# ---------------------------------------------------------------------------

func _run_level() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CAP|art01|ERROR|level_load_failed")
		return
	var level: Node3D = packed.instantiate() as Node3D
	root.add_child(level)
	print("CAP|art01|level=%s|loaded=true" % LEVEL)
	_report_cover_visuals(level)

	var cam := Camera3D.new()
	cam.name = "Art01LevelCam"
	cam.near = 0.05
	cam.far = 400.0
	level.add_child(cam)
	await process_frame
	for v in LEVEL_VIEWS:
		cam.fov = v["fov"]
		cam.look_at_from_position(v["pos"], v["look"], Vector3.UP)
		cam.current = true
		print("CAP|art01|view=%s|cam_pos=%s|look=%s|fov=%.1f" % [v["tag"], v["pos"], v["look"], v["fov"]])
		await _save(v["tag"])


## 打印关卡里 4 处草丛掩体的**视觉节点真实类型**（改造前是 MeshInstance3D 盒子，
## 改造后是 glb 实例）—— 这是"改造到底生效没有"的客观证据，不靠看图猜。
func _report_cover_visuals(level: Node) -> void:
	var names := ["CoverBushWestAMesh", "CoverBushWestBMesh", "CoverBushNorthCMesh", "CreekReedCoverMesh"]
	for nm in names:
		var n := level.get_node_or_null(nm)
		if n == null:
			print("CAP|art01|cover_visual|%s|MISSING" % nm)
			continue
		var cls := n.get_class()
		var sfp: String = n.scene_file_path
		# 用 position 而不是 global_position：这几处视觉节点都是关卡根的直接子节点，
		# 而且此时场景刚 add_child、还没被 SceneTree 标记为 inside_tree（global_position 会报错返 0）。
		var pos: Vector3 = (n as Node3D).position if n is Node3D else Vector3.ZERO
		print("CAP|art01|cover_visual|%s|class=%s|scene_file_path=%s|pos=%s" % [nm, cls, sfp, pos])


# ---------------------------------------------------------------------------
# 场景搭建 / 捕获
# ---------------------------------------------------------------------------

func _add_lighting(world: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Art01Sun"
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	world.add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.52, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.84)
	sky_mat.ground_bottom_color = Color(0.18, 0.20, 0.18)
	sky_mat.ground_horizon_color = Color(0.52, 0.54, 0.48)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "Art01Env"
	we.environment = env
	world.add_child(we)


func _mk_box(world: Node3D, nm: String, size: Vector3, pos: Vector3, color: Color,
		transparent: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color, transparent)
	mi.position = pos
	world.add_child(mi)
	return mi


func _mk_capsule(world: Node3D, nm: String, radius: float, height: float, pos: Vector3,
		color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = _mat(color, false)
	mi.position = pos
	world.add_child(mi)
	return mi


func _mat(color: Color, transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _save(tag: String) -> void:
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		print("CAP|art01|%s|ERROR|no_viewport_texture" % tag)
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|art01|%s|ERROR|no_image" % tag)
		return
	var active := vp.get_camera_3d()
	_pixel_stats(tag, img)
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|art01|%s|active_camera=%s|save_result=%d (%s)|path=%s|global=%s" % [
		tag, active.name if active != null else "<none>", err, "OK" if err == OK else "FAIL",
		path, ProjectSettings.globalize_path(path)])


## 客观像素统计：改造前后用同一机位同一光照对比，避免"看着感觉好点"。
func _pixel_stats(tag: String, img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var total := 0.0
	var mn := 1.0
	var mx := 0.0
	var green := 0
	var step := 4
	var n := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			total += lum
			mn = minf(mn, lum)
			mx = maxf(mx, lum)
			# "草绿"判据：绿色显著高于红与蓝
			if c.g > 0.10 and c.g > c.r * 1.25 and c.g > c.b * 1.25:
				green += 1
			n += 1
	print("PIX|%s|size=%dx%d|sampled=%d|mean_lum=%.4f|min_lum=%.4f|max_lum=%.4f|green_px=%d|green_ratio=%.4f" % [
		tag, w, h, n, total / float(maxi(n, 1)), mn, mx, green, float(green) / float(maxi(n, 1))])
