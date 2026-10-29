extends SceneTree
## ART09-F3：四态走态展示条（站立 / 起步 / 行走 / 奔跑），猫与鼠各一条，横向拼成一张图。
##
## 为什么不用游戏内截图：展板这一块是「同机位、同光照、纯侧视」的对照条，
## 必须帧与帧之间**只有姿势不同**，所以固定相机、固定灯、只改动画时间。
##
## 取景：闭环自校正一次（用 Idle 帧量填充率），**之后四个状态共用同一机位**，不重新取景。
##
## 用法（**必须非 headless**）：
##   `& $g --path $proj --script 'res://tests/tool_capture_art09_gait.gd' --quit-after 60000 -- gait`
##
## 产物：`user://gait_<species>_row.png`（1024×256，4 帧）

const SPECIES_DIR := "res://resources/species"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const SKY_HDRI := "res://assets/environment/hdri/mossy_forest_2k.hdr"
const CELL := 256
const CELLS := 4
const SETTLE := 6
const TARGET_FILL := 0.66
const FILL_TOL := 0.05
const MAX_ITER := 4
const CAM_FOV := 30.0
const DIST_GUESS := 2.0

## 四个状态：动画名 + 采样时间（秒）
const STATES := [
	{"label": "idle", "anim": "Idle", "t": 0.30},
	{"label": "walk_start", "anim": "Walk", "t": 0.02},
	{"label": "walk", "anim": "Walk", "t": 0.55},
	{"label": "run", "anim": "Run", "t": 0.30},
]


func _initialize() -> void:
	root.size = Vector2i(CELL, CELL)
	if not OS.get_cmdline_user_args().has("gait"):
		print("GAIT|ERROR|need_arg|pass '-- gait'")
		quit(1)
		return
	var made := 0
	for p in _species_paths():
		var cfg := load(p) as SpeciesConfig
		if cfg == null or cfg.visual_scene == null:
			continue
		if await _render_row(cfg):
			made += 1
	print("GAIT|done|rows=%d" % made)
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


func _render_row(cfg: SpeciesConfig) -> bool:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL, CELL)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := _make_environment()
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	_add_light(vp, Vector3(-34.0, 10.0, 0.0), Color(1.0, 0.93, 0.82), 1.4)
	_add_light(vp, Vector3(-14.0, 190.0, 0.0), Color(0.62, 0.72, 0.92), 0.40)

	var body := (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = false
	body.position = Vector3.ZERO
	vp.add_child(body)
	await process_frame
	body.set_physics_process(false)
	body.velocity = Vector3.ZERO
	body.position = Vector3.ZERO
	for mi in _meshes_of(body):
		mi.visible = String(mi.name) != "BodyMesh"

	var player := _find_animation_player(body)
	if player == null:
		print("GAIT|species=%s|SKIP|no_animation_player" % String(cfg.species_id))
		vp.queue_free()
		return false

	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	cam.near = 0.01
	cam.far = 200.0
	vp.add_child(cam)
	cam.current = true

	# 用 Idle 帧做一次闭环取景（之后不重算）
	_play_at(player, "Idle", 0.30)
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	# 单步反推距离（渲染投影对距离近似线性）：先量一次填充率，再按比例修一次即可，
	# 反复迭代会因为模型前后腿错位/近裁剪而震荡（实测 0.31→0.43→0.23）。
	var dist := DIST_GUESS
	var fill := 0.0
	var aim_y := 0.12
	_aim(cam, dist, aim_y)
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	var probe := vp.get_texture().get_image() if vp.get_texture() != null else null
	if probe != null:
		var used := probe.get_used_rect()
		if used.size.y > 0:
			fill = float(used.size.y) / float(CELL)
			# 侧视要**同时**照顾高与长：猫身长 0.54 m，只按高度定距离会把头尾切掉（实测踩到）
			var fill_x := float(used.size.x) / float(CELL)
			var k := maxf(fill / TARGET_FILL, fill_x / 0.86)
			dist = clampf(dist * k, 0.05, 200.0)
			# 垂直取中：模型原点不一定在脚底，实测会压低在画面底部 → 按像素偏差修视线高度
			var mpp := 2.0 * dist * tan(deg_to_rad(CAM_FOV * 0.5)) / float(CELL)
			var dy := float(used.position.y) + float(used.size.y) * 0.5 - float(CELL) * 0.5
			aim_y = maxf(0.01, aim_y - dy * mpp)
	print("GAIT|species=%s|probe_fill=%.2f|dist=%.3f|aim_y=%.3f" % [
		String(cfg.species_id), fill, dist, aim_y,
	])
	_aim(cam, dist, aim_y)
	env.background_mode = Environment.BG_SKY
	vp.transparent_bg = false

	var row := Image.create(CELL * CELLS, CELL, false, Image.FORMAT_RGBA8)
	for i in STATES.size():
		var st: Dictionary = STATES[i]
		_play_at(player, String(st["anim"]), float(st["t"]))
		for f in SETTLE:
			await process_frame
		await RenderingServer.frame_post_draw
		var tex := vp.get_texture()
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		# 视口纹理可能是 RGBAH/RGBE，`blit_rect` 要求同格式 → 先转 RGBA8
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		row.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(i * CELL, 0))
		print("GAIT|species=%s|cell=%d|state=%s|anim=%s|t=%.2f" % [
			String(cfg.species_id), i, String(st["label"]), String(st["anim"]), float(st["t"]),
		])
	var path := "user://gait_%s_row.png" % String(cfg.species_id).to_lower()
	var err := row.save_png(path)
	print("GAIT|species=%s|row=%dx%d|save_result=%d (%s)|%s" % [
		String(cfg.species_id), row.get_width(), row.get_height(), err,
		"OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path),
	])
	vp.queue_free()
	for i in 2:
		await process_frame
	return err == OK


func _play_at(player: AnimationPlayer, anim: String, t: float) -> void:
	if not player.has_animation(anim):
		return
	var a := player.get_animation(anim)
	if a != null:
		a.loop_mode = Animation.LOOP_NONE
	player.play(anim)
	player.seek(t, true)
	player.pause()


func _aim(cam: Camera3D, dist: float, aim_y: float = 0.10) -> void:
	# 纯侧视：相机在 +X 侧、与视线目标同高，视线沿 −X
	cam.global_position = Vector3(dist, aim_y + dist * 0.04, 0.0)
	cam.look_at(Vector3(0.0, aim_y, 0.0), Vector3.UP)


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
	env.ssao_intensity = 1.8
	return env


func _add_light(parent: Node, rot: Vector3, color: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = rot
	light.light_color = color
	light.light_energy = energy
	parent.add_child(light)


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
