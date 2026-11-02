extends SceneTree
## B 阶段：地表贴图选型的**同机位对比**捕获。**必须非 headless**（走 Tools/CaptureRun.ps1）。
##
## 用法：
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_ground_compare.gd -UserArgs gtex
##
## 做什么：加载展板关 `l_ravine_board.tscn`，在**两个固定机位**下分别渲染 4 个地面变体：
##   - baseline   = 关卡现状（forest_floor + 冷绿 tint，ART10 后的样子），不动它的材质；
##   - fl02/fl03/fl04 = forest_leaves_02/03/04 候选（diffuse+nor_gl+arm，**不加 tint**——
##     tint 是接入时的调节旋钮，选型阶段先看贴图本色，避免把"贴图差异"和"调色差异"混在一起）。
## 候选贴图从 `res://assets/environment/tex_candidates/` 加载（临时目录，仅比对用，选型后删除；
## 源文件在 references/_downloads，不入库不进包）。
##
## 帧输出：`user://gtex_<view>_<variant>.png`，逐帧打印 GTEX|save_result。

const LEVEL := "res://scenes/maps/l_ravine_board.tscn"
const RES := Vector2i(1280, 720)
const SETTLE_FIRST := 40   # 首帧等体积雾/环境稳定
const SETTLE := 12

const TEX_CAND_DIR := "res://assets/environment/tex_candidates/"

## 与现有 tex/ 命名对齐（Poly Haven 原名是 *_diffuse_*，仓库惯例是 *_diff_*）
const CANDIDATES := [
	{"tag": "fl02", "diff": "forest_leaves_02_diff_1k.jpg",
		"nor": "forest_leaves_02_nor_gl_1k.jpg", "arm": "forest_leaves_02_arm_1k.jpg"},
	{"tag": "fl03", "diff": "forest_leaves_03_diff_1k.jpg",
		"nor": "forest_leaves_03_nor_gl_1k.jpg", "arm": "forest_leaves_03_arm_1k.jpg"},
	{"tag": "fl04", "diff": "forest_leaves_04_diff_1k.jpg",
		"nor": "forest_leaves_04_nor_gl_1k.jpg", "arm": "forest_leaves_04_arm_1k.jpg"},
	## 追加候选（第一轮 9 宫格短名单里与 fl02 并列最高分，苔藓密覆向）
	{"tag": "lgrass", "diff": "leafy_grass_diff_1k.jpg",
		"nor": "leafy_grass_nor_gl_1k.jpg", "arm": "leafy_grass_arm_1k.jpg"},
]

## 两个固定机位（所有变体完全相同）：
##   ground = 低斜视近景，主体是地面纹理本身（看平铺感/叶片尺度/苔感）；
##   scene  = 与 tool_capture_art09_board.gd 的 ravine_env_creek 完全相同的机位（看与溪/岸/草的整体融合）。
const VIEWS := [
	{"tag": "ground", "pos": Vector3(3.50, 0.50, 3.20),
		"look": Vector3(6.00, 0.08, -0.80), "fov": 40.0},
	{"tag": "scene", "pos": Vector3(0.60, 0.40, 0.20),
		"look": Vector3(4.00, 0.14, -3.20), "fov": 42.0},
]

## 候选材质参数与 tool_make_ravine_board.gd 的地面一致（uv 15x17 / roughness 0.96 / metallic 0），
## 仅 albedo 不压 tint。
const UV_SCALE := Vector2(15.0, 17.0)
const ROUGH := 0.96

var _failed := false


func _initialize() -> void:
	root.size = RES
	if not OS.get_cmdline_user_args().has("gtex"):
		print("GTEX|ERROR|need_arg|pass '-- gtex'")
		quit(1)
		return
	await _run()
	print("GTEX|done")
	quit(1 if _failed else 0)


func _run() -> void:
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		print("GTEX|ERROR|level_load_failed")
		_failed = true
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	for i in SETTLE_FIRST:
		await process_frame

	var ground := level.get_node_or_null("Ground") as MeshInstance3D
	if ground == null:
		print("GTEX|ERROR|ground_node_missing")
		_failed = true
		return
	var baseline_mat := ground.material_override

	# 相机：两个机位都建好，逐帧切换 current
	var cams := {}
	for v in VIEWS:
		var cam := Camera3D.new()
		cam.name = "Cam_gtex_%s" % String(v["tag"])
		cam.fov = float(v["fov"])
		cam.near = 0.05
		cam.far = 220.0
		level.add_child(cam)
		cam.global_position = v["pos"] as Vector3
		cam.look_at(v["look"] as Vector3, Vector3.UP)
		cams[String(v["tag"])] = cam

	# 变体表：baseline 用场景自带材质；候选按需构建，缺文件即 FAIL（不静默降级）
	var variants: Array = [{"tag": "baseline", "mat": baseline_mat}]
	for c in CANDIDATES:
		var mat := _make_candidate_material(c)
		if mat == null:
			print("GTEX|ERROR|candidate_textures_missing|%s" % String(c["tag"]))
			_failed = true
			continue
		variants.push_back({"tag": String(c["tag"]), "mat": mat})

	for varr in variants:
		var tag := String(varr["tag"])
		ground.material_override = varr["mat"]
		await process_frame
		for v in VIEWS:
			var vt := String(v["tag"])
			for key in cams:
				(cams[key] as Camera3D).current = (key == vt)
			for i in SETTLE:
				await process_frame
			await _save("gtex_%s_%s" % [vt, tag])
		print("GTEX|variant_done|%s" % tag)

	ground.material_override = baseline_mat
	level.queue_free()
	for i in 4:
		await process_frame


func _make_candidate_material(c: Dictionary) -> StandardMaterial3D:
	var diff_path := TEX_CAND_DIR + String(c["diff"])
	var nor_path := TEX_CAND_DIR + String(c["nor"])
	var arm_path := TEX_CAND_DIR + String(c["arm"])
	if not (ResourceLoader.exists(diff_path) and ResourceLoader.exists(nor_path)
			and ResourceLoader.exists(arm_path)):
		return null
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(diff_path) as Texture2D
	mat.normal_enabled = true
	mat.normal_texture = load(nor_path) as Texture2D
	var arm_tex := load(arm_path) as Texture2D
	if arm_tex != null:
		mat.ao_enabled = true
		mat.ao_texture = arm_tex
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.roughness_texture = arm_tex
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.uv1_scale = Vector3(UV_SCALE.x, UV_SCALE.y, 1.0)
	mat.roughness = ROUGH
	mat.metallic = 0.0
	return mat


func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var tex := root.get_viewport().get_texture()
	if tex == null:
		print("GTEX|%s|ERROR|no_texture" % tag)
		_failed = true
		return
	var image := tex.get_image()
	if image == null:
		print("GTEX|%s|ERROR|no_image" % tag)
		_failed = true
		return
	var path := "user://%s.png" % tag
	var err := image.save_png(path)
	print("GTEX|save_result=%d (%s)|%s|%s" % [
		err, "OK" if err == OK else "FAIL", tag, ProjectSettings.globalize_path(path)])
	if err != OK:
		_failed = true
