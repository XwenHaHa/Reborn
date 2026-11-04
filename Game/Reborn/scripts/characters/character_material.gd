extends RefCounted
## ART14：角色质感（不改模型、不改玩法，只改**材质呈现**）。
##
## 为什么需要这个模块：`sm_cat_004` / `sm_mouse_002` 的 glb 材质是"贴图 + 默认 PBR"，
## 皮毛面读起来像抛光树脂（粗糙度偏低、镜面默认 0.5、表面绝对光滑）。这里在**运行时**
## 给视觉网格挂表面覆盖材质，不写回资产、不改碰撞/动画/玩法，随时可整体摘掉。
##
## 分步原则（负责人要求）：一项一项改、每项单独同机位前后对比，不一次堆参数。
##   S1  PBR 校正：皮毛粗糙度 / 镜面强度（眼睛等光滑面保持原样）
##   S2  绒毛高频法线：程序化噪声扰动切线法线（`shaders/character_fur.gdshader`）
##
## 用 `preload` 而非 `class_name`：无头/未导入环境里全局类缓存可能不新鲜，
## preload 直接编译文件本身，保证取证与回归在任何启动路径下都能跑。

const FUR_SHADER := preload("res://shaders/character_fur.gdshader")

## S1：真实短毛是"宽而弱"的高光，不是抛光塑料。
## 但也不能一路哑光到底：0.94/0.16 在同机位判读里被判"过度矫正、像哑光橡皮泥/磨砂毡"（5.5/10），
## 故收到 0.84/0.26 —— 保留一点柔和的方向性光泽，不做镜面反射。
const A14_FUR_ROUGHNESS := 0.84
const A14_FUR_SPECULAR := 0.26
## 低于这个粗糙度的面视为"眼睛/爪/鼻头"等本来就该亮的部位，不参与皮毛改造。
const A14_GLOSSY_ROUGHNESS := 0.45

## S2：绒毛高频法线强度（实测 0.08 在现有 UV 上被判"砂纸/磨砂漆"，3/10 → 默认关闭）。
## 见 `Docs/Evidence/ART14_CHARACTER_MATERIAL.md`：现有模型没有毛发方向图，程序化各向同性噪声
## 只能做出"磨砂"而不是"绒"；天花板需要几何毛发/毛发卡片或授权的毛发 tiling 贴图。
const A14_FUR_NORMAL_STRENGTH := 0.08

## S2 的开关（默认 false）。取证工具只在"档位 2"这一次打开，用来保留那次判定样张。
static var fur_micro_normal := false
## S3：轮廓绒光强度。0.28 在全身机位被判"均匀光晕/柔光滤镜、边缘变糊"（5.5/10），
## 故压到 0.16（只做一点点边缘分离）；鼠没有法线/细节贴图，压到 0.12。
const A14_RIM_STRENGTH := 0.16
const A14_RIM_MOUSE_STRENGTH := 0.12

## S4：薄处透光（BACKLIGHT）颜色与强度。真 SSS 需要管线支持与厚度图，这里只做观感近似。
## 强度经过判读：0.35 在正面判 6/10（"方向对、偏保守但安全"）；0.60 在**逆光机位**被判
## "发光塑料、斑纹被洗淡"（3.5/10）→ 回退 0.35。这是本方案的取舍：正面"够用"，逆光"不过火"。
const A14_BACKLIGHT_CAT := Color(0.82, 0.44, 0.30)
const A14_BACKLIGHT_CAT_STRENGTH := 0.35
## 鼠在逆光机位 0.85 被判"红光过饱和、尾部像发光塑料、暗部死黑"（5.5/10）→ 降到 0.45、
## 并把颜色收回一点饱和度（不那么"荧光红"）。
const A14_BACKLIGHT_MOUSE := Color(0.88, 0.48, 0.44)
const A14_BACKLIGHT_MOUSE_STRENGTH := 0.45

## 档位（默认 4 = 全部生效）。取证工具用它逐档渲染同一机位，保证"每步只差一项"：
##   0 = 原始材质（不挂覆盖材质）
##   1 = S1 PBR 校正
##   2 = S1 + S2 绒毛微法线
##   3 = + S3 轮廓绒光
##   4 = + S4 薄处透光
static var step_level := 4


static func apply_to(root: Node, cfg: SpeciesConfig = null) -> void:
	# 0 档 = 原始 glb 材质，不加任何覆盖材质（取证用：改前样张）
	if step_level <= 0:
		return
	for mi in _meshes(root):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(s)
			if src is StandardMaterial3D:
				var std := src as StandardMaterial3D
				if std.roughness < A14_GLOSSY_ROUGHNESS:
					continue
				mi.set_surface_override_material(s, _fur_material(std, cfg))
			elif src is ShaderMaterial:
				# 已经是我们的 shader（重复调用时不要叠加）
				continue


static func _rim_strength_for(is_mouse: bool) -> float:
	return A14_RIM_MOUSE_STRENGTH if is_mouse else A14_RIM_STRENGTH


static func _fur_material(std: StandardMaterial3D, cfg: SpeciesConfig) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FUR_SHADER
	var albedo := std.albedo_texture
	mat.set_shader_parameter("has_albedo_tex", albedo != null)
	if albedo != null:
		mat.set_shader_parameter("albedo_tex", albedo)
	mat.set_shader_parameter("albedo_tint", std.albedo_color)
	var nrm := std.normal_texture
	mat.set_shader_parameter("has_normal_tex", nrm != null)
	if nrm != null:
		mat.set_shader_parameter("normal_tex", nrm)
	mat.set_shader_parameter("fur_roughness", A14_FUR_ROUGHNESS)
	mat.set_shader_parameter("fur_specular", A14_FUR_SPECULAR)
	# S2：绒毛法线（2 档起；判为"砂纸"故默认关闭，由 `fur_micro_normal` 显式打开）
	mat.set_shader_parameter(
		"fur_normal_strength",
		A14_FUR_NORMAL_STRENGTH if (step_level >= 2 and fur_micro_normal) else 0.0
	)
	# S3：轮廓绒光（3 档起）。鼠用更弱的档位：它没有法线贴图，强绒光会读成"毛绒玩具光晕"
	var is_mouse := cfg != null and String(cfg.species_id).to_lower() == "mouse"
	mat.set_shader_parameter("rim_strength", _rim_strength_for(is_mouse) if step_level >= 3 else 0.0)
	# S4：薄处透光按物种给色。猫耳/鼻偏暖，鼠耳更粉更透（薄皮肤）；4 档起生效
	var backlight_strength := A14_BACKLIGHT_MOUSE_STRENGTH if is_mouse else A14_BACKLIGHT_CAT_STRENGTH
	mat.set_shader_parameter("backlight_color", A14_BACKLIGHT_MOUSE if is_mouse else A14_BACKLIGHT_CAT)
	mat.set_shader_parameter("backlight_strength", backlight_strength if step_level >= 4 else 0.0)
	return mat


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for child in n.get_children():
		out.append_array(_meshes(child))
	return out
