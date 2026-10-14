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
const OUT_USER_T005_ORTHO := "user://t005_lab_probe_ortho.png"
## 正交对照相机的固定参数（写在代码里，避免"凭记忆"复现）
## 取景要求：**同时**包含 1 m 标尺（x 0.7–1.7, y≈0.11）、探针立方体（x 1.9–2.9, y 0.1–1.1）
## 与顶部标记（y=2.6），否则"比长度/看标记"的视觉检查会缺一块（第一版 size=3.0 就把顶部标记切掉了）。
## 视野：竖直 4.0 m、水平 4.0×(1280/720)=7.11 m → x 覆盖 -1.16..5.96，y 覆盖 -0.6..3.4。
## 1 m 在画面上恒为 4.0/7.11*1280 = 180 px（正交、两物同深度 → 可直接比长度）。
const T005_CAM_POS := Vector3(2.4, 1.4, 3.0)
const T005_CAM_SIZE := 4.0
## T006：骨骼位姿两帧视图（同一相机、同一光照，只改动画时间）
## 位置放在 lab 地面左侧（x=-1.0），相机在其 +X 侧沿 -X 看 → 侧视能看到腿前后摆动。
## 刻意避开标尺（x 0.7–1.7）与 T005 探针（x 1.9–2.9）：相机放在两者之间靠左，标尺在相机背后。
const T006_ASSET := "res://assets/tests/sk_rig_probe.glb"
const T006_RIG_POS := Vector3(-1.0, 0.10, -2.5)
const T006_CAM_POS := Vector3(0.10, 0.45, -2.5)
const T006_CAM_TARGET := Vector3(-1.0, 0.22, -2.5)
const T006_TIMES := [0.0, 0.5]

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

	# T005：可选的正交对照视图。必须显式传 `-- t005`，默认行为完全不变。
	if OS.get_cmdline_user_args().has("t005"):
		await _capture_t005_ortho(lab)
	# T006：骨骼位姿两帧视图。同样只在显式传 `-- t006` 时执行。
	if OS.get_cmdline_user_args().has("t006"):
		await _capture_t006_frames(lab)
	# T009：猫移动三帧（坡道 / 低顶蹲姿 / 跳上 50 cm 高台）。只在显式传 `-- t009` 时执行。
	if OS.get_cmdline_user_args().has("t009"):
		await _capture_t009_frames(lab)
	# T010：鼠的两个尺度场景（洞里 / 15 cm 低顶下）。只在显式传 `-- t010` 时执行。
	if OS.get_cmdline_user_args().has("t010"):
		await _capture_t010_frames(lab)

	# T011：生态灰盒关卡的俯瞰与结构特写。只在显式传 `-- t011` 时执行。
	if OS.get_cmdline_user_args().has("t011"):
		await _capture_t011_frames(lab)

	# T012：导航面调试视图（按层分别只看一个 region）。只在显式传 `-- t012` 时执行。
	if OS.get_cmdline_user_args().has("t012"):
		await _capture_t012_frames(lab)

	print("CAP|done")
	quit(0)


## T005 正交对照捕获：正交投影下"1 m 就是同样宽"，用于真正比较探针立方体与 100 cm 标尺。
## 视角沿 -Z 平视；探针在标尺右端旁边，两者 z 相同（同一深度）→ 像素宽度可直接比较。
## 只在显式传 `-- t005` 时执行，不影响原有捕获行为。
func _capture_t005_ortho(lab: Node) -> void:
	print("CAP|t005_ortho|start")
	var cam := Camera3D.new()
	cam.name = "T005OrthoCamera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = T005_CAM_SIZE
	cam.near = 0.05
	cam.far = 100.0
	lab.add_child(cam)
	cam.global_position = T005_CAM_POS
	cam.rotation_degrees = Vector3.ZERO
	cam.current = true

	for i in SETTLE_FRAMES:
		await process_frame

	var vp := root.get_viewport()
	var active := vp.get_camera_3d()
	var active_name := "<none>"
	var proj := -1
	var csize := 0.0
	var cpos := Vector3.ZERO
	if active != null:
		active_name = active.name
		proj = active.projection
		csize = active.size
		cpos = active.global_position
	print("CAP|t005_ortho|active_camera=%s|projection=%d|size=%.2f|pos=%s" % [
		active_name, proj, csize, cpos
	])

	var tex := vp.get_texture()
	if tex == null:
		print("CAP|t005_ortho|ERROR|no viewport texture")
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|t005_ortho|ERROR|no image")
		return
	print("CAP|t005_ortho|image_size=%dx%d" % [img.get_width(), img.get_height()])
	_pixel_stats(img)
	var err := img.save_png(OUT_USER_T005_ORTHO)
	print("CAP|t005_ortho|save_png_result=%d (%s)" % [err, "OK" if err == OK else "FAIL"])
	print("CAP|t005_ortho|saved_to=%s" % ProjectSettings.globalize_path(OUT_USER_T005_ORTHO))


## T006 骨骼两帧捕获
func _capture_t006_frames(lab: Node) -> void:
	print("CAP|t006|start")
	var packed: PackedScene = load(T006_ASSET)
	if packed == null:
		print("CAP|t006|ERROR|asset load failed")
		return
	var rig: Node3D = packed.instantiate() as Node3D
	lab.add_child(rig)
	rig.global_position = T006_RIG_POS

	var cam := Camera3D.new()
	cam.name = "T006Camera"
	cam.fov = 45.0
	cam.near = 0.02
	lab.add_child(cam)
	cam.global_position = T006_CAM_POS
	cam.look_at(T006_CAM_TARGET, Vector3.UP)
	cam.current = true

	var ap := _find_node(rig, "AnimationPlayer") as AnimationPlayer
	var sk := _find_node(rig, "Skeleton3D") as Skeleton3D
	if ap == null or sk == null:
		print("CAP|t006|ERROR|missing AnimationPlayer/Skeleton3D")
		return
	print("CAP|t006|rig_pos=%s|cam_pos=%s|fov=%.1f|animations=%s" % [
		rig.global_position, cam.global_position, cam.fov, str(ap.get_animation_list())
	])

	for i in SETTLE_FRAMES:
		await process_frame

	var idx := 0
	for t in T006_TIMES:
		ap.play("Loop")
		await process_frame
		# 关键（第一版踩到的真 bug）：play() 之后若一直等帧，播放器会把动画**推过头**
		# （实测等 90 帧后 t=0 那一张其实是 35° 摆动态）。必须先 pause 冻结，等场景稳定后再 seek。
		ap.pause()
		for i in SETTLE_FRAMES:
			await process_frame
		ap.seek(t, true)
		await process_frame
		await process_frame
		var vp := root.get_viewport()
		var tex := vp.get_texture()
		if tex == null:
			print("CAP|t006|ERROR|no viewport texture")
			return
		var img := tex.get_image()
		if img == null:
			print("CAP|t006|ERROR|no image")
			return
		print("CAP|t006|frame=%d|t=%.2f|leg_front_dir=%s|leg_back_dir=%s" % [
			idx, t, _bone_dir(sk, "leg_front"), _bone_dir(sk, "leg_back")
		])
		_pixel_stats(img)
		var path := "user://t006_rig_t%03d.png" % int(round(t * 100.0))
		var err := img.save_png(path)
		print("CAP|t006|save_result=%d (%s)|path=%s|global=%s" % [
			err, "OK" if err == OK else "FAIL", path, ProjectSettings.globalize_path(path)
		])
		idx += 1


## ---------------------------------------------------------------------------
## T009：猫移动三帧（坡道 / 低顶蹲姿 / 跳上 50 cm 高台）
##
## 为什么单独建一个世界：试验世界 `l_move_fixtures.tscn` 是 16×16 地面，与 lab 的 10×10
## 地面重叠同高，放在一起会互相遮挡/互相碰撞。所以这里先释放 lab，再装试验世界。
## 猫由工具自己实例化并**直接喂意图**（`player_controlled = false`），避免捕获时抢鼠标。
## ---------------------------------------------------------------------------

const T009_FIXTURES := "res://scenes/maps/l_move_fixtures.tscn"
const T009_BODY := "res://scenes/characters/animal_body.tscn"
const T009_CAT := "res://resources/species/cat.tres"
const T009_MOUSE := "res://resources/species/mouse.tres"

func _capture_t009_frames(lab: Node) -> void:
	print("CAP|t009|start")
	lab.queue_free()
	await process_frame
	await process_frame

	var packed: PackedScene = load(T009_FIXTURES)
	if packed == null:
		print("CAP|t009|ERROR|fixtures load failed")
		return
	var world: Node3D = packed.instantiate() as Node3D
	root.add_child(world)
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var cam := Camera3D.new()
	cam.name = "T009Camera"
	cam.fov = 45.0
	cam.near = 0.05
	world.add_child(cam)
	cam.current = true

	# 帧 1：走上 25° 坡道
	await _capture_case(world, cam, "t009_ramp", load(T009_CAT), Vector3(0.0, 0.36, 3.0),
		{"forward_frames": 150, "crouch": false}, Vector3(2.6, 1.5, 2.4))
	# 帧 2：蹲姿钻低顶（板底 0.52），并尝试站起来（被挡住）
	# 相机必须**低于板底**并贴近地面平视，否则俯视时板子会把蹲着的猫整个遮住（实测踩到过）
	await _capture_case(world, cam, "t009_low_ceiling", load(T009_CAT), Vector3(-6.0, 0.36, 3.0),
		{"forward_frames": 200, "crouch": true, "then_release_crouch": 60}, Vector3(0.0, 0.16, 1.7))
	# 帧 3：助跑跳上 50 cm 高台
	await _capture_case(world, cam, "t009_platform", load(T009_CAT), Vector3(6.5, 0.36, -1.5),
		{"jump_at_distance": 0.78, "forward_frames": 240}, Vector3(2.4, 1.3, 2.4))


## ---------------------------------------------------------------------------
## T010：鼠的两个尺度场景（24×30 cm 洞里 / 15 cm 低顶下）
##
## 取景要点（都踩过）：
##   * 洞里：相机在洞的 +z 侧、略高，视线穿过 24 cm 宽的开口看到鼠——正好也是"洞真的只有这么宽"的证据；
##   * 鼠低顶下：相机**必须低于板底（0.25）**并沿鼠的车道平视，否则板子把鼠整个遮住（与 T009 同一坑）。
## ---------------------------------------------------------------------------

func _capture_t010_frames(lab: Node) -> void:
	print("CAP|t010|start")
	lab.queue_free()
	await process_frame
	await process_frame

	var packed: PackedScene = load(T009_FIXTURES)
	if packed == null:
		print("CAP|t010|ERROR|fixtures load failed")
		return
	var world: Node3D = packed.instantiate() as Node3D
	root.add_child(world)
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var cam := Camera3D.new()
	cam.name = "T010Camera"
	cam.fov = 45.0
	cam.near = 0.02
	world.add_child(cam)
	cam.current = true

	var mouse: SpeciesConfig = load(T009_MOUSE) as SpeciesConfig
	# 帧 1：鼠**站立**停在 24×30 cm 洞里（洞中心 z=−2.0）
	# 相机必须**在鼠的车道上**（x 偏移 0）才不会让洞的侧壁挡住视线——第一版用了 x 偏移 1.6，
	# 视线在洞面处 x=2.78 落在洞口（2.38..2.62）之外，鼠被侧壁完全遮住（视觉判读两次都说"洞里是空的"）。
	await _capture_case(world, cam, "t010_tunnel", mouse, Vector3(2.5, 0.21, 2.1),
		{"forward_frames": 400, "crouch": false, "stop_z": -2.0}, Vector3(0.0, 0.20, 0.55))
	# 帧 2：鼠蹲在 0.15 m 净空低顶下（板底 0.25）
	await _capture_case(world, cam, "t010_mouse_low", mouse, Vector3(-3.5, 0.21, 4.0),
		{"forward_frames": 300, "crouch": true, "stop_z": 1.8}, Vector3(0.0, 0.06, 1.6))


## 一个捕获场景：放一个身体（cfg）、按 script 驱动、再拍第三人称 + 第一人称两张。
## script 支持：`crouch` / `forward_frames` / `jump_at_distance` / `then_release_crouch` /
## `stop_z`（向 −z 走到该 z 就停下，用于"停在洞/低顶里"这种取景）。
func _capture_case(world: Node3D, cam: Camera3D, tag: String, cfg: SpeciesConfig, spawn: Vector3,
		script: Dictionary, cam_off: Vector3) -> void:
	var body: AnimalBody = (load(T009_BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = false
	world.add_child(body)
	body.global_position = spawn
	body.velocity = Vector3.ZERO
	for i in 180:
		await physics_frame
		if body.is_on_floor():
			break

	var intent := Vector2(0.0, -1.0)
	body.move_intent = intent
	body.want_crouch = bool(script.get("crouch", false))
	var jump_dist: float = float(script.get("jump_at_distance", -1.0))
	var frames: int = int(script.get("forward_frames", 150))
	var stop_z: float = float(script.get("stop_z", -1e9))   # 默认不停（走满 frames）
	var jumped := false
	for i in frames:
		if jump_dist >= 0.0 and not jumped and body.is_on_floor():
			var pf := world.get_node_or_null("Platform50") as Node3D
			if pf != null and absf(body.global_position.z - (pf.position.z + 1.0)) <= jump_dist:
				jumped = true
				body.want_jump = true
		# 上到台顶就停下，别再往前走（否则会从台子另一侧走下去、掉出地面——实测踩到过）
		if jumped and body.is_on_floor() and body.global_position.y > spawn.y + 0.3:
			body.move_intent = Vector2.ZERO
			break
		# 走到指定 z 就停下（取景"停在洞里/低顶下"用）
		if body.global_position.z <= stop_z:
			body.move_intent = Vector2.ZERO
			break
		await physics_frame
	if script.has("then_release_crouch"):
		body.move_intent = Vector2.ZERO
		body.want_crouch = false
		for i in int(script["then_release_crouch"]):
			await physics_frame
	body.move_intent = Vector2.ZERO
	for i in 30:
		await physics_frame

	# 第三人称（看得到身体与姿态）
	cam.global_position = body.global_position + cam_off
	cam.look_at(body.global_position + Vector3(0.0, 0.05, 0.0), Vector3.UP)
	cam.current = true
	await _capture_shot("%s_tp" % tag, body, cam)
	# 第一人称（玩家真正的视角：眼高与视野是否正常）
	cam.current = false
	body.camera.current = true
	body.camera.rotation = Vector3.ZERO
	await _capture_shot("%s_fp" % tag, body, body.camera)
	body.camera.current = false

	body.queue_free()
	await process_frame

## T011：生态灰盒关卡 `l_courtyard.tscn` 的俯瞰与三个结构特写。只在显式传 `-- t011` 时执行。
## 取景前提（T010 教训）：相机要**正对结构所在的通道**，否则墙体/顶板会把主体遮住。
const T011_LEVEL := "res://scenes/maps/l_courtyard.tscn"
const T011_VIEWS := [
	{"tag": "t011_map_overview", "pos": Vector3(0.0, 52.0, 72.0), "look": Vector3(0.0, 0.0, 2.0), "fov": 45.0},
	{"tag": "t011_courtyard", "pos": Vector3(0.0, 20.0, 44.0), "look": Vector3(0.0, 0.0, 16.0), "fov": 55.0},
	{"tag": "t011_courtyard_shelter", "pos": Vector3(-3.0, 1.15, 27.3), "look": Vector3(-8.5, 0.8, 27.3), "fov": 70.0},
	{"tag": "t011_grass_danger", "pos": Vector3(2.0, 24.0, 16.0), "look": Vector3(2.0, 0.0, -12.0), "fov": 55.0},
	{"tag": "t011_roots_hole_lane", "pos": Vector3(26.5, 0.62, 23.5), "look": Vector3(26.5, 0.32, 18.5), "fov": 70.0},
	{"tag": "t011_roots_barrier_oblique", "pos": Vector3(30.0, 3.0, 25.0), "look": Vector3(30.0, 0.3, 19.0), "fov": 60.0},
	{"tag": "t011_creek_gap_lane", "pos": Vector3(-31.73, 0.62, 16.5), "look": Vector3(-31.73, 0.32, 9.0), "fov": 70.0},
]


func _capture_t011_frames(lab: Node) -> void:
	print("CAP|t011|start")
	var packed: PackedScene = load(T011_LEVEL)
	if packed == null:
		print("CAP|t011|ERROR|level load failed")
		return
	var world: Node3D = packed.instantiate() as Node3D
	if world == null:
		print("CAP|t011|ERROR|level root is not Node3D")
		return
	root.add_child(world)

	var cam := Camera3D.new()
	cam.name = "T011Camera"
	cam.near = 0.05
	cam.far = 400.0
	world.add_child(cam)

	for v in T011_VIEWS:
		cam.fov = float(v["fov"])
		cam.global_position = v["pos"]
		cam.look_at(v["look"], Vector3.UP)
		cam.current = true
		print("CAP|t011|view=%s|cam_pos=%s|look=%s|fov=%.1f" % [v["tag"], v["pos"], v["look"], cam.fov])
		await _capture_view(v["tag"], cam)


## 只拍一张（没有身体主体）：T011 关卡视角用
func _capture_view(tag: String, cam: Camera3D) -> void:
	var prefix: String = String(tag).split("_")[0]
	for i in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		print("CAP|%s|ERROR|no viewport texture" % prefix)
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|%s|ERROR|no image" % prefix)
		return
	var active := vp.get_camera_3d()
	print("CAP|%s|%s|cam_pos=%s|active=%s" % [prefix, tag, cam.global_position,
		active.name if active != null else "<none>"])
	_pixel_stats(img)
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|%s|save_result=%d (%s)|path=%s|global=%s" % [
		prefix, err, "OK" if err == OK else "FAIL", path, ProjectSettings.globalize_path(path)
	])


## T012：导航面调试视图（按层分别只开一个 region，便于对比"鼠图有洞、猫图没洞"）。
## 只在显式传 `-- t012` 时执行。注意：**导航调试是否真的画出来必须靠客观像素对比确认**。
const T012_LEVEL := "res://scenes/maps/l_courtyard.tscn"
const T012_AREAS := [
	{"tag": "t012_tree_hole", "pos": Vector3(26.5, 11.0, 31.0), "look": Vector3(26.5, 0.0, 19.0), "fov": 50.0},
	{"tag": "t012_creek_gap", "pos": Vector3(-31.73, 13.0, 23.0), "look": Vector3(-31.73, 0.0, 10.0), "fov": 50.0},
]


func _capture_t012_frames(lab: Node) -> void:
	print("CAP|t012|start")
	var packed: PackedScene = load(T012_LEVEL)
	if packed == null:
		print("CAP|t012|ERROR|level load failed")
		return
	var world: Node3D = packed.instantiate() as Node3D
	root.add_child(world)
	var rn := world.get_node_or_null("NavRegion_Mouse") as NavigationRegion3D
	var rc := world.get_node_or_null("NavRegion_Cat") as NavigationRegion3D
	print("CAP|t012|regions|mouse=%s|cat=%s" % [str(rn != null), str(rc != null)])
	NavigationServer3D.set_debug_enabled(true)
	print("CAP|t012|nav_debug_enabled=%s" % str(NavigationServer3D.get_debug_enabled()))
	var cam := Camera3D.new()
	cam.name = "T012Camera"
	cam.near = 0.05
	cam.far = 400.0
	world.add_child(cam)
	for area in T012_AREAS:
		for which in ["mouse", "cat"]:
			if rn != null:
				rn.enabled = which == "mouse"
			if rc != null:
				rc.enabled = which == "cat"
			for i in 3:
				await physics_frame
			cam.fov = float(area["fov"])
			cam.global_position = area["pos"]
			cam.look_at(area["look"], Vector3.UP)
			cam.current = true
			print("CAP|t012|view=%s_%s|enabled_region=%s" % [area["tag"], which, which])
			await _capture_view("%s_%s" % [area["tag"], which], cam)

## 拍一张并存 PNG + 打印客观像素统计（T009/T010 共用：只看 tag 与相机，与物种无关）
## 输出前缀从 tag 推导（`t009_*` → `CAP|t009|`，`t010_*` → `CAP|t010|`），保证 T009 的日志格式不变。
func _capture_shot(tag: String, body: AnimalBody, cam: Camera3D) -> void:
	var prefix: String = String(tag).split("_")[0]
	for i in SETTLE_FRAMES:
		await process_frame
	# 必须等"真正画完一帧"再读：只 await process_frame 时，读到的是**上一帧**（换机位后会拿到上一机位的画面，
	# 实测：tp/fp 两张图会字节完全相同）。`RenderingServer.frame_post_draw` 才是"这一帧已绘制完"的信号。
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		print("CAP|%s|ERROR|no viewport texture" % prefix)
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|%s|ERROR|no image" % prefix)
		return
	print("CAP|%s|%s|body_pos=%s|crouch=%s|capsule_h=%.3f|cam_pos=%s|active=%s" % [
		prefix, tag, body.global_position, str(body.is_crouching),
		(body.shape_node.shape as CapsuleShape3D).height, cam.global_position,
		vp.get_camera_3d().name if vp.get_camera_3d() != null else "<none>"
	])
	_pixel_stats(img)
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|%s|save_result=%d (%s)|path=%s|global=%s" % [
		prefix, err, "OK" if err == OK else "FAIL", path, ProjectSettings.globalize_path(path)
	])


func _find_node(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r := _find_node(c, cls)
		if r:
			return r
	return null


func _bone_dir(sk: Skeleton3D, bone: String) -> String:
	var i := sk.find_bone(bone)
	if i < 0:
		return "<missing>"
	return str(sk.get_bone_global_pose(i).basis.y.normalized())


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
