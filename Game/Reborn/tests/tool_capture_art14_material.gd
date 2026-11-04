extends SceneTree
## ART14：角色材质判读机（**必须非 headless**，走 Tools/CaptureRun.ps1）。
##
## 为什么自己搭机位：角色质感要"同机位、同光照、只变材质"才能判读，
## 直接用游戏内截图会被跟随相机、太阳角度、地形遮挡干扰。
##
## 固定四灯（主光前左 / 冷补光 / 顶光 / 暖逆光）+ 三个固定机位：
##   front34  前 3/4（看皮肤/受光面与轮廓）
##   side     纯侧视（看形与边缘）
##   back     逆光（看有没有轮廓光/边缘发丝；没有逆光时主体会读成剪影）
##
## 取景用**几何 AABB**直接算距离（材料无关）：这样"改前/改后"两轮的机位**逐像素一致**，
## 不会因为材质变暗让取景漂移、把"变亮/变暗"和"构图变了"混在一起。
## （此前用透明底 alpha 闭环会在小鼠这种小主体上震荡到贴面，已弃用。）
##
## 用法：
##   `powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_art14_material.gd -UserArgs "material baseline"`
##   `... -UserArgs "material step2 2"`（第二参数 = 材质档位 0~4，见 `character_material.gd`）
##
## 产物：`user://art14_<pass>_<species>_<angle>.png`（由脚本外侧拷到 Art/Probes/art14_<pass>/）

const A14CharacterMaterial := preload("res://scripts/characters/character_material.gd")

const SPECIES_DIR := "res://resources/species"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const SIZE := 768
const SETTLE := 8
const TARGET_FILL := 0.64
const FILL_TOL := 0.04
const CENTER_TOL := 0.035
const MAX_ITER := 7
## 初始距离（米）：1.6 与 ART09 肖像工具相同，对两个物种都保证主体一开始就在画面内
const DIST_GUESS := 1.6
const CAM_FOV := 30.0

## 解析后的命令行参数（`OS.get_cmdline_user_args()` 经 CaptureRun 传入时是**一个整串**，必须先 split）
var _args: Array = []

## 机位：方向单位向量（相机相对主体的位置方向）
const ANGLES := [
	{"name": "front34", "dir": Vector3(-0.55, 0.18, -1.0)},
	{"name": "side", "dir": Vector3(1.0, 0.06, 0.0)},
	{"name": "back", "dir": Vector3(0.30, 0.16, 1.0)},
]


func _initialize() -> void:
	var args := " ".join(OS.get_cmdline_user_args()).strip_edges().split(" ", false)
	_args = args
	if args.size() < 2 or args[0] != "material":
		print("ART14|ERROR|need_arg|pass '-- material <pass> [step]'")
		quit(1)
		return
	var pass_name := args[1]
	if args.size() >= 3:
		var step := int(args[2])
		A14CharacterMaterial.step_level = step
		# 档位 2 = S2 绒毛微法线单独样张（该方案已被判"砂纸"，生产默认关闭，见 character_material.gd）
		A14CharacterMaterial.fur_micro_normal = step == 2
	print("ART14|step_level=%d|micro_normal=%s|pass=%s" % [
		A14CharacterMaterial.step_level, str(A14CharacterMaterial.fur_micro_normal), pass_name,
	])
	root.size = Vector2i(SIZE, SIZE)
	var made := 0
	for p in _species_paths():
		var cfg := load(p) as SpeciesConfig
		if cfg == null or cfg.visual_scene == null:
			continue
		if await _render_species(cfg, pass_name):
			made += 1
	print("ART14|done|pass=%s|species=%d" % [pass_name, made])
	quit(0 if made > 0 else 1)


func _species_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(SPECIES_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tres"):
			out.append(SPECIES_DIR + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _render_species(cfg: SpeciesConfig, pass_name: String) -> bool:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var env := _make_environment()
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	# 接触项（S5）：`contact` 参数把 SSAO 调到"角色尺度"（现模型腿径约 3~6 cm，默认 0.3 m 半径几乎压不到脚底）
	if _args.has("contact"):
		env.ssao_radius = 0.06
		env.ssao_intensity = 3.0
		env.ssao_power = 2.0
		print("ART14|ssao|contact=on|radius=%.3f|intensity=%.1f" % [env.ssao_radius, env.ssao_intensity])
	# 判读"接地是否自然"必须有地面：中性灰地板 + 真实投影，否则任何角色都会被判"悬空"
	var ground := _make_ground()
	vp.add_child(ground)
	# 固定四灯：主光 / 冷补 / 顶光 / 暖逆光（逆光是判"轮廓有没有光"的唯一手段）
	_add_light(vp, Vector3(-38.0, 42.0, 0.0), Color(1.0, 0.92, 0.78), 1.5, true)
	_add_light(vp, Vector3(-12.0, -120.0, 0.0), Color(0.62, 0.72, 0.92), 0.45, false)
	_add_light(vp, Vector3(-24.0, 168.0, 0.0), Color(1.0, 0.95, 0.85), 0.9, false)
	_add_light(vp, Vector3(-30.0, 175.0, 0.0), Color(1.0, 0.80, 0.62), 1.1, false)

	var body := (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	body.name = "ART14Subject"
	body.species_config = cfg
	body.player_controlled = false
	body.make_camera_current = false
	# 与游戏生成一致：胶囊**居中**于身体原点，脚底在原点下方 cap_h/2。
	# 因此身体原点必须抬到地面之上 cap_h/2，否则模型会陷进地面（实测：只剩头露出来，
	# 接触处是一条硬直线、也没有接触阴影 —— 那是机位 bug，不是贴图/材质问题）。
	var stand_h := float(cfg.capsule_height())
	body.position = Vector3(0.0, stand_h * 0.5, 0.0)
	vp.add_child(body)
	await process_frame
	body.set_physics_process(false)
	body.velocity = Vector3.ZERO
	_play_idle(body)
	var meshes := _meshes_of(body)
	for mi in meshes:
		mi.visible = String(mi.name) != "BodyMesh"
	# 诊断：确认实际参与渲染的网格与它们的材质类（证明覆盖材质真的落到画面上）
	for mi in meshes:
		print("ART14|dbg|species=%s|mesh=%s|visible=%s|surfaces=%d|mat0=%s|aabb=%s" % [
			String(cfg.species_id), String(mi.name), str(mi.visible),
			mi.mesh.get_surface_count() if mi.mesh != null else -1,
			mi.get_active_material(0).get_class() if mi.mesh != null and mi.mesh.get_surface_count() > 0 and mi.get_active_material(0) != null else "null",
			str(mi.global_transform * mi.get_aabb()),
		])

	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	cam.near = 0.005
	cam.far = 300.0
	vp.add_child(cam)
	cam.current = true

	var sid := String(cfg.species_id).to_lower()
	# 取景只用**几何**（透明底 alpha），与材质无关；且机位由迭代收敛到固定目标填充率，
	# 因此"改前/改后"两轮、每个档位的机位逐像素一致 —— 不会把"变亮/变暗"混成"构图变了"。
	# 为什么不用网格 AABB：glTF 蒙皮网格的 `get_aabb()` 是绑定姿态（猫 2 cm、鼠 1 mm），
	# 直接用会算出贴面机位（实测：鼠被取景到画面外，5 个档位截图字节完全相同）。
	var subject_h := float(cfg.capsule_height())
	var half_tan := tan(deg_to_rad(CAM_FOV * 0.5))
	var base_aim := Vector3(0.0, subject_h * 0.5, 0.0)
	ground.visible = false
	vp.transparent_bg = true
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	for spec in ANGLES:
		var angle_name := String(spec["name"])
		var d: Vector3 = (spec["dir"] as Vector3).normalized()
		var cam_aim := base_aim
		var dist := DIST_GUESS
		var fill := 0.0
		var iters := 0
		for it in MAX_ITER:
			iters = it + 1
			cam.global_position = cam_aim + d * dist
			cam.look_at(cam_aim)
			for i in SETTLE:
				await process_frame
			await RenderingServer.frame_post_draw
			var probe_tex := vp.get_texture()
			var probe := probe_tex.get_image() if probe_tex != null else null
			if probe == null:
				break
			if probe.get_format() != Image.FORMAT_RGBA8:
				probe.convert(Image.FORMAT_RGBA8)
			var used := probe.get_used_rect()
			if used.size.y <= 2:
				# 主体不在画面：**退后**扩大视野（不能拉近，越拉近越可能已经在主体背后）
				dist = clampf(dist * 1.6, 0.02, 30.0)
				continue
			fill = float(used.size.y) / float(SIZE)
			var dx := float(used.position.x) + float(used.size.x) * 0.5 - float(SIZE) * 0.5
			var dy := float(used.position.y) + float(used.size.y) * 0.5 - float(SIZE) * 0.5
			var mpp := 2.0 * dist * half_tan / float(SIZE)
			# 平移视线目标（不转相机朝向）：沿相机的右/上轴移动，主体回到画面中心
			cam_aim += cam.global_basis.x * (dx * mpp) - cam.global_basis.y * (dy * mpp)
			dist = clampf(dist * (fill / TARGET_FILL), 0.02, 30.0)
			if absf(fill - TARGET_FILL) <= FILL_TOL and absf(dx) <= float(SIZE) * CENTER_TOL \
					and absf(dy) <= float(SIZE) * CENTER_TOL:
				break
		# 正式图：恢复地面与暗底（判"接地"必须看到投影/接触阴影）
		ground.visible = true
		vp.transparent_bg = false
		env.background_mode = Environment.BG_COLOR
		for i in SETTLE:
			await process_frame
		await RenderingServer.frame_post_draw
		var tex := vp.get_texture()
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		var path := "user://art14_%s_%s_%s.png" % [pass_name, sid, angle_name]
		var err := img.save_png(path)
		print("ART14|species=%s|angle=%s|pass=%s|dist=%.3f|fill=%.2f|iters=%d|save=%s|%s" % [
			String(cfg.species_id), angle_name, pass_name, dist, fill, iters,
			"OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path),
		])
		# 复位：下一个机位继续用透明底做纯几何取景
		ground.visible = false
		vp.transparent_bg = true
		env.background_mode = Environment.BG_CLEAR_COLOR
		if err != OK:
			vp.queue_free()
			return false
	vp.queue_free()
	for i in 2:
		await process_frame
	return true


func _make_environment() -> Environment:
	var env := Environment.new()
	# 中性暗底 + 固定环境光：判读要的是"材质本身"，不是森林天空把主体染绿/过曝
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.37, 0.44)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.02
	env.ssao_enabled = true
	env.ssao_radius = 0.3
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_hdr_threshold = 1.1
	return env


func _add_light(parent: Node, rot: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = rot
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	if shadows:
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		light.directional_shadow_max_distance = 8.0
		light.shadow_blur = 1.0
		light.light_angular_distance = 2.0
		light.shadow_bias = 0.02
	parent.add_child(light)


func _make_ground() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.49, 0.46)
	mat.roughness = 0.92
	mat.metallic = 0.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _play_idle(node: Node) -> void:
	var player := _find_animation_player(node)
	if player == null:
		return
	for candidate in [&"Idle", &"idle", &"Walk", &"walk"]:
		if player.has_animation(candidate):
			var anim := player.get_animation(candidate)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR
			player.play(candidate)
			player.advance(0.35)
			return


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _meshes_of(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for child in n.get_children():
		out.append_array(_meshes_of(child))
	return out
