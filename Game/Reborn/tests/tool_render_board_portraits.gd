extends SceneTree
## ART09-F1：把每个物种渲染成 512×512 **肖像图**（引擎内渲染 = 关键图管线 A 类来源）。
##
## 取景用**闭环自校正**，不猜任何几何：
##   渲染（透明底）→ 用 alpha 的 `get_used_rect()` 量主体填充率与画面中心偏差
##   → 按比例修距离、按偏差修视线 → 重复，最多 `MAX_ITER` 轮，达标后带天空背景渲正式图。
## 这样对骨骼模型（`get_aabb()` 实测只有 0.02 m，不可用）、对任何缩放/原点约定都成立。
##
## 用法（**必须非 headless**）：
##   `& $g --path $proj --script 'res://tests/tool_render_board_portraits.gd' --quit-after 60000 -- portraits`
##
## 产物：`res://assets/ui/portraits/portrait_<species_id>.png` → 写进 `SpeciesConfig.display_portrait`

const SPECIES_DIR := "res://resources/species"
const OUT_DIR := "res://assets/ui/portraits"
const SKY_HDRI := "res://assets/environment/hdri/mossy_forest_2k.hdr"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const SIZE := 512
const SETTLE := 6
## 目标：主体占画面高度比例 / 允许的中心偏差（归一化）
const TARGET_FILL := 0.62
const FILL_TOL := 0.05
const CENTER_TOL := 0.04
const MAX_ITER := 5
## 3/4 视角：相机在左前方、略高
const CAM_SIDE := -0.55
const CAM_FOV := 32.0
const DIST_GUESS := 1.6


func _initialize() -> void:
	root.size = Vector2i(SIZE, SIZE)
	if not OS.get_cmdline_user_args().has("portraits"):
		print("PORTRAIT|ERROR|need_arg|pass '-- portraits'")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var paths := _species_paths()
	if paths.is_empty():
		print("PORTRAIT|ERROR|no_species_tres")
		quit(1)
		return
	var made := 0
	for p in paths:
		var cfg := load(p) as SpeciesConfig
		if cfg == null:
			continue
		if await _render(cfg):
			made += 1
	print("PORTRAIT|done|made=%d|dir=%s" % [made, OUT_DIR])
	quit(0 if made > 0 else 1)


func _species_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(SPECIES_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and (entry.ends_with(".tres") or entry.ends_with(".res")):
			out.append(SPECIES_DIR + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _render(cfg: SpeciesConfig) -> bool:
	if cfg.visual_scene == null:
		print("PORTRAIT|species=%s|SKIP|no_visual_scene" % String(cfg.species_id))
		return false

	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var env := _make_environment()
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	_add_light(vp, Vector3(-38.0, 42.0, 0.0), Color(1.0, 0.92, 0.78), 1.5)
	_add_light(vp, Vector3(-12.0, -120.0, 0.0), Color(0.62, 0.72, 0.92), 0.45)
	_add_light(vp, Vector3(-24.0, 168.0, 0.0), Color(1.0, 0.95, 0.85), 0.9)

	# 用 `AnimalBody` 承载：它负责视觉网格的实例化与 Idle 播放（直接实例化 glb 不会隐藏胶囊占位）
	var body := (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	body.name = "PortraitSubject"
	body.species_config = cfg
	body.player_controlled = false
	body.make_camera_current = false
	body.position = Vector3.ZERO
	vp.add_child(body)
	await process_frame
	body.set_physics_process(false)
	body.velocity = Vector3.ZERO
	body.position = Vector3.ZERO
	_play_idle(body)
	var mesh_count := 0
	for mi in _meshes_of(body):
		if String(mi.name) == "BodyMesh":
			mi.visible = false   # 胶囊占位：游戏里也隐藏，肖像里必须继续隐藏
			continue
		mi.visible = true
		mesh_count += 1

	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	cam.near = 0.01
	cam.far = 300.0
	vp.add_child(cam)
	cam.current = true

	# 闭环：距离 + 视线高度一起收敛（**先切成透明底**，否则 `get_used_rect()` 量到的是整张天空）
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	var dist := DIST_GUESS
	var target_y := 0.12
	var fill := 0.0
	var center_err := 0.0
	for iteration in MAX_ITER:
		_aim(cam, dist, target_y)
		for i in SETTLE:
			await process_frame
		await RenderingServer.frame_post_draw
		var probe := vp.get_texture().get_image() if vp.get_texture() != null else null
		if probe == null:
			print("PORTRAIT|species=%s|ERROR|no_probe_image" % String(cfg.species_id))
			vp.queue_free()
			return false
		var used := probe.get_used_rect()
		if used.size.y <= 0:
			dist *= 0.5
			continue
		fill = float(used.size.y) / float(SIZE)
		var dx := float(used.position.x) + float(used.size.x) * 0.5 - float(SIZE) * 0.5
		var dy := float(used.position.y) + float(used.size.y) * 0.5 - float(SIZE) * 0.5
		center_err = dy / float(SIZE)
		print("PORTRAIT|species=%s|iter=%d|dist=%.3f|fill=%.2f|dx=%.0f|dy=%.0f" % [
			String(cfg.species_id), iteration + 1, dist, fill, dx, dy,
		])
		if absf(fill - TARGET_FILL) <= FILL_TOL and absf(dx) <= float(SIZE) * CENTER_TOL \
				and absf(dy) <= float(SIZE) * CENTER_TOL:
			break
		# 填充率偏低 → 拉近；主体偏心 → **平移相机**（比转视线稳，不会因为视线落到地下而卡住）
		var mpp := 2.0 * dist * tan(deg_to_rad(CAM_FOV * 0.5)) / float(SIZE)
		cam.global_position += cam.global_basis.x * (dx * mpp) - cam.global_basis.y * (dy * mpp)
		target_y = cam.global_position.y - dist * 0.18
		dist = clampf(dist * (fill / TARGET_FILL), 0.02, 200.0)

	# 正式图：带森林天空
	env.background_mode = Environment.BG_SKY
	vp.transparent_bg = false
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	var tex := vp.get_texture()
	if tex == null:
		print("PORTRAIT|species=%s|ERROR|no_texture" % String(cfg.species_id))
		vp.queue_free()
		return false
	var image := tex.get_image()
	if image == null:
		print("PORTRAIT|species=%s|ERROR|no_image" % String(cfg.species_id))
		vp.queue_free()
		return false
	var path := "%s/portrait_%s.png" % [OUT_DIR, String(cfg.species_id).to_lower()]
	var err := image.save_png(path)
	print("PORTRAIT|species=%s|meshes=%d|fill=%.2f|dist=%.3f|save_result=%d (%s)|%s" % [
		String(cfg.species_id), mesh_count, fill, dist, err,
		"OK" if err == OK else "FAIL", path,
	])
	vp.queue_free()
	for i in 2:
		await process_frame
	return err == OK


func _aim(cam: Camera3D, dist: float, target_y: float) -> void:
	cam.global_position = Vector3(CAM_SIDE * dist, target_y + dist * 0.18, -dist)
	cam.look_at(Vector3(0.0, target_y, 0.0), Vector3.UP)


func _make_environment() -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	var hdri := load(SKY_HDRI) as Texture2D
	if hdri != null:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = hdri
		sky.sky_material = pano
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.02
	env.ssao_enabled = true
	env.ssao_radius = 0.3
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_hdr_threshold = 1.1
	return env


func _add_light(parent: Node, rot: Vector3, color: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = rot
	light.light_color = color
	light.light_energy = energy
	parent.add_child(light)


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
