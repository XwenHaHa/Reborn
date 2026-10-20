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

	# T013：调试入口三态（碰撞线框开/关、猫/鼠路径、HUD）。只在显式传 `-- t013` 时执行。
	if OS.get_cmdline_user_args().has("t013"):
		await _capture_t013_frames(lab)

	# T018：正式 HUD（状态 / 低值警告 / 交互提示）的屏幕可见性。只在显式传 `-- t018` 时执行。
	if OS.get_cmdline_user_args().has("t018"):
		await _capture_t018_frames(lab)
	# T020：鼠的感知与逃跑（警戒 / 逃跑 / 洞里躲藏）。只在显式传 `-- t020` 时执行。
	if OS.get_cmdline_user_args().has("t020"):
		await _capture_t020_frames(lab)

	# T021：猫扑击与捕获结算（扑击中途 / 撞墙被挡 / 命中并生成捕获食物）。只在显式传 `-- t021` 时执行。
	if OS.get_cmdline_user_args().has("t021"):
		await _capture_t021_frames(lab)
	# T022：猫循环回归（死亡 HUD 的 F6 重开提示 / 重开后再跑一次捕获）。只在显式传 `-- t022` 时执行。
	if OS.get_cmdline_user_args().has("t022"):
		await _capture_t022_frames(lab)
	# T023：猫 NPC 巡游与发现（巡游中 / 发现后接近猎物）。只在显式传 `-- t023` 时执行。
	if OS.get_cmdline_user_args().has("t023"):
		await _capture_t023_frames(lab)
	# T024：追击与搜索（追击中 / 失视后走向最后已知位置）。只在显式传 `-- t024` 时执行。
	if OS.get_cmdline_user_args().has("t024"):
		await _capture_t024_frames(lab)
	# T025：NPC 攻击与玩家受伤（预警中 / 命中后）。只在显式传 `-- t025` 时执行。
	if OS.get_cmdline_user_args().has("t025"):
		await _capture_t025_frames(lab)
	# T026：藏身与掩体（草丛里不可见 / 洞口外等待）。只在显式传 `-- t026` 时执行。
	if OS.get_cmdline_user_args().has("t026"):
		await _capture_t026_frames(lab)

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
func _capture_view(tag: String, cam: Camera3D, settle := SETTLE_FRAMES) -> void:
	var prefix: String = String(tag).split("_")[0]
	for i in settle:
		await process_frame
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


## T013：调试入口三态截图（碰撞 / 路径 / HUD）。只在显式传 `-- t013` 时执行。
##
## 为什么碰撞要拍**同机位开/关两张**：T013 实测引擎开关 `SceneTree.debug_collisions_hint`
## 打开后画面**逐字节不变**（画不出东西），所以"能看见碰撞"这件事必须用**自绘线框**的像素差来证明，
## 而不是只看开关的布尔值。引擎开关依旧会打开（编辑器调试运行下才有效果，本环境无法验证）。
const T013_ENTRY := "res://scenes/debug/debug_entry.tscn"
const T013_LANE_CAM := Vector3(26.5, 1.7, 26.5)
const T013_LANE_LOOK := Vector3(26.5, 0.3, 17.0)
const T013_HIGH_CAM := Vector3(26.5, 13.0, 31.0)
const T013_HIGH_LOOK := Vector3(26.5, 0.0, 18.0)
const T013_HUD_CAM := Vector3(-6.0, 4.0, 38.0)
const T013_HUD_LOOK := Vector3(-2.0, 0.4, 20.0)


func _capture_t013_frames(lab: Node) -> void:
	print("CAP|t013|start")
	# 先移走默认的试验世界：它和 80×80 的灰盒关卡在同一坐标会互相遮挡
	lab.queue_free()
	await process_frame
	await process_frame
	var packed: PackedScene = load(T013_ENTRY)
	if packed == null:
		print("CAP|t013|ERROR|debug entry load failed")
		return
	var entry: Node3D = packed.instantiate() as Node3D
	root.add_child(entry)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in SETTLE_FRAMES:
		await process_frame
	print("CAP|t013|entry|species=%s|hud=%s" % [
		str(entry.get("current_species")), str(entry.call("hud_enabled"))
	])

	var cam := Camera3D.new()
	cam.name = "T013Camera"
	cam.near = 0.05
	cam.far = 400.0
	entry.add_child(cam)

	# ① 碰撞线框：同机位开 / 关
	cam.fov = 70.0
	cam.global_position = T013_LANE_CAM
	cam.look_at(T013_LANE_LOOK, Vector3.UP)
	cam.current = true
	entry.call("toggle_hud")            # 关 HUD：文字会逐帧变，污染像素差
	entry.call("toggle_collision_debug")
	print("CAP|t013|collision_on|selfdraw_shapes=%d|engine_hint=%s" % [
		int(entry.call("drawn_collision_shapes")), str(entry.call("collision_debug_enabled"))
	])
	await _capture_view("t013_collision_on", cam)
	entry.call("toggle_collision_debug")
	print("CAP|t013|collision_off|selfdraw_shapes=%d|engine_hint=%s" % [
		int(entry.call("drawn_collision_shapes")), str(entry.call("collision_debug_enabled"))
	])
	await _capture_view("t013_collision_off", cam)

	# ①b 玩家胶囊线框近景：验证"上下两个圆 + 竖线"也真的画得出来（上两张只看得见长方体棱边）
	entry.call("toggle_collision_debug")
	cam.fov = 60.0
	cam.global_position = Vector3(-4.0, 1.2, 26.5)
	cam.look_at(Vector3(-4.0, 0.34, 24.0), Vector3.UP)
	cam.current = true
	print("CAP|t013|collision_player|selfdraw_shapes=%d" % int(entry.call("drawn_collision_shapes")))
	await _capture_view("t013_collision_player", cam)
	entry.call("toggle_collision_debug")

	# ② 导航路径：猫（绕行、不进洞）与鼠（直穿洞口）
	cam.fov = 50.0
	cam.global_position = T013_HIGH_CAM
	cam.look_at(T013_HIGH_LOOK, Vector3.UP)
	cam.current = true
	for species_path in ["res://resources/species/cat.tres", "res://resources/species/mouse.tres"]:
		var cfg: SpeciesConfig = load(species_path) as SpeciesConfig
		if cfg == null:
			print("CAP|t013|ERROR|config load failed: %s" % species_path)
			continue
		entry.call("switch_species", cfg.species_id)
		cam.current = true                  # 切物种会重建身体并把**玩家相机**设为 current，必须抢回来
		entry.call("toggle_path_display")
		for i in 60:
			await process_frame
		for i in 30:
			await physics_frame
		var pr: Dictionary = entry.call("probe_report", true)
		var ma: NavigationAgent3D = entry.get("main_agent")
		print("CAP|t013|path_agent|species=%s|agent_valid=%s|layer=%d|target=%s|raw_path=%d|reachable=%s|map_valid=%s" % [
			String(cfg.species_id), str(ma != null and is_instance_valid(ma)),
			ma.navigation_layers if ma != null else -1,
			str(ma.target_position) if ma != null else "<none>",
			ma.get_current_navigation_path().size() if ma != null else -1,
			str(ma.is_target_reachable()) if ma != null else "n/a",
			str(ma.get_navigation_map().is_valid()) if ma != null else "n/a"
		])
		print("CAP|t013|path|species=%s|points=%d|len=%.2f|probe_own_layer=%d|probe_own_len=%.2f|probe_own_crosses_hole=%s" % [
			String(cfg.species_id), int(entry.call("path_point_count")), float(entry.call("path_length")),
			int(pr.get("own_layer", 0)), float(pr.get("own_len", 0.0)), str(pr.get("own_crosses_hole"))
		])
		await _capture_view("t013_path_%s" % String(cfg.species_id).to_lower(), cam)
		entry.call("toggle_path_display")

	# ③ HUD（打开）
	cam.fov = 60.0
	cam.global_position = T013_HUD_CAM
	cam.look_at(T013_HUD_LOOK, Vector3.UP)
	cam.current = true
	var hud_on: bool = entry.call("toggle_hud")
	print("CAP|t013|hud|enabled=%s" % str(hud_on))
	await _capture_view("t013_debug_hud", cam)


# ---------------------------------------------------------------------------
# T018：正式 HUD 的屏幕可见性（状态 / 低值警告 / 交互提示）
# ---------------------------------------------------------------------------

const T018_LEVEL := "res://scenes/maps/l_courtyard.tscn"
const T018_BODY := "res://scenes/characters/animal_body.tscn"
const T018_HUD := "res://scenes/ui/hud.tscn"
const T018_RP := "res://scenes/world/resource_point.tscn"
const T018_MOUSE := "res://resources/species/mouse.tres"
const T018_CAM_POS := Vector3(-4.0, 1.7, 25.6)
const T018_CAM_LOOK := Vector3(-4.0, 0.35, 23.8)


## 在**正式关卡**上摆玩家 + 一个食物点 + 一个水点，然后抓三张：
## ① 正常状态 ② 低值警告 ③ 交互提示。HUD 是屏幕空间控件，所以会直接出现在图里。
func _capture_t018_frames(lab: Node) -> void:
	print("CAP|t018|start")
	lab.queue_free()
	await process_frame
	await process_frame
	var level := (load(T018_LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for i in SETTLE_FRAMES:
		await process_frame
	var body := (load(T018_BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = load(T018_MOUSE) as SpeciesConfig
	body.player_controlled = false
	body.position = Vector3(-4.0, 0.35, 24.0)
	level.add_child(body)
	var hud := (load(T018_HUD) as PackedScene).instantiate() as PlayerHud
	level.add_child(hud)
	hud.bind_player(body)
	var food := (load(T018_RP) as PackedScene).instantiate() as ResourcePoint
	food.kind = &"food"
	food.food_type = SpeciesConfig.FoodType.SEED
	food.interaction_id = "t018_seed"
	food.position = Vector3(-4.0, 0.35, 23.6)
	level.add_child(food)
	var water := (load(T018_RP) as PackedScene).instantiate() as ResourcePoint
	water.kind = &"water"
	water.interaction_id = "t018_water"
	water.position = Vector3(-3.5, 0.35, 23.6)
	level.add_child(water)
	for i in SETTLE_FRAMES:
		await process_frame
	var cam := Camera3D.new()
	cam.name = "T018Camera"
	cam.near = 0.05
	cam.far = 400.0
	cam.fov = 60.0
	level.add_child(cam)
	cam.global_position = T018_CAM_POS
	cam.look_at(T018_CAM_LOOK, Vector3.UP)
	cam.current = true
	for i in 10:
		await process_frame
	print("CAP|t018|normal|hud_text=%s" % String(hud.hud_text()).replace("\n", " | "))
	await _capture_view("t018_hud_normal", cam)
	# 低值警告：直接改状态 + 发信号（与 `run_t018_hud.gd` 同一条路径；HUD 只观察）
	body.survival.state.hunger = 18.0
	body.survival.state.thirst = 12.0
	body.survival.changed.emit(body.survival.state)
	body.survival.warning_changed.emit(&"hunger", true)
	for i in 5:
		await process_frame
	print("CAP|t018|warning|warning_text=%s" % hud.warning_text())
	await _capture_view("t018_hud_warning", cam)
	# 交互提示：把玩家挪到食物点跟前，等检测器锁到目标
	body.global_position = Vector3(-4.0, 0.35, 23.95)
	for i in 30:
		await physics_frame
	for i in 5:
		await process_frame
	print("CAP|t018|interact|text=%s|visible=%s" % [hud.interaction_text(), str(hud.interaction_visible())])
	await _capture_view("t018_hud_interact", cam)
	print("CAP|t018|done")


# ---------------------------------------------------------------------------
# T020：鼠的感知与逃跑（警戒 → 逃跑 → 钻进鼠洞躲藏）
# ---------------------------------------------------------------------------

const T020_LEVEL := "res://scenes/maps/l_courtyard.tscn"
const T020_BODY := "res://scenes/characters/animal_body.tscn"
const T020_MOUSE := "res://resources/species/mouse.tres"
const T020_CAT := "res://resources/species/cat.tres"
## 取景（T010 教训：相机要**正对通道**，否则洞口侧壁会把主体完全遮住）
const T020_ALERT_CAM := Vector3(29.5, 1.5, 25.5)
const T020_ALERT_LOOK := Vector3(27.3, 0.30, 22.8)
const T020_LANE_CAM := Vector3(26.5, 0.85, 24.0)
const T020_LANE_LOOK := Vector3(26.5, 0.28, 19.0)
const T020_HOLE_CAM := Vector3(26.5, 0.62, 23.5)
const T020_HOLE_LOOK := Vector3(26.5, 0.32, 18.5)


## T020：真实关卡上的三帧（警戒 / 逃跑途中 / 洞里躲藏）。
##
## **不是只截图**：每帧同时打印 AI 状态、原因、躲藏点与感知数值，图像与状态文本在同一条日志里。
## 警戒只有 0.3 s（`Parameters.md` 第 71 行），所以这一帧靠**重复注入威胁**把 ALERT 保持住
## （日志里标 `held_by=repeat_alert`，**不假装是自然时序**）；逃跑与躲藏两帧是自然时序。
func _capture_t020_frames(lab: Node) -> void:
	print("CAP|t020|start")
	var packed: PackedScene = load(T020_LEVEL)
	if packed == null:
		print("CAP|t020|ERROR|level load failed")
		return
	var level: Node3D = packed.instantiate() as Node3D
	root.add_child(level)

	var mouse_cfg := load(T020_MOUSE) as SpeciesConfig
	var cat_cfg := load(T020_CAT) as SpeciesConfig
	var body_packed := load(T020_BODY) as PackedScene
	if mouse_cfg == null or cat_cfg == null or body_packed == null:
		print("CAP|t020|ERROR|config/body missing")
		return

	# 鼠 NPC：屏障北侧、朝洞里（前向 −Z）
	var mouse := body_packed.instantiate() as AnimalBody
	mouse.species_config = mouse_cfg
	mouse.player_controlled = false
	mouse.position = Vector3(26.5, 0.35, 24.5)
	level.add_child(mouse)
	mouse.ai_enabled = true
	await physics_frame

	# 威胁：猫在**正前偏右 2.9 m**（看得见，但不在"立即逃"的 1.8 m 内 → 先警戒 0.3 s）
	var cat := body_packed.instantiate() as AnimalBody
	cat.species_config = cat_cfg
	cat.player_controlled = false
	cat.position = Vector3(28.3, 0.35, 22.2)
	level.add_child(cat)
	await physics_frame

	var cam := Camera3D.new()
	cam.name = "T020Camera"
	cam.near = 0.05
	cam.far = 400.0
	cam.fov = 70.0
	level.add_child(cam)

	for i in 6:
		await physics_frame
	var spots := get_nodes_in_group("hide_spots")
	print("CAP|t020|fixture|hide_spots=%d|mouse=%s|cat=%s" % [spots.size(), mouse.global_position, cat.global_position])

	# 1) 警戒（保持住再拍：只等 4 帧；场景此前已渲染多帧，不需要 90 帧 settle）
	cam.global_position = T020_ALERT_CAM
	cam.look_at(T020_ALERT_LOOK, Vector3.UP)
	cam.current = true
	for i in 20:
		if mouse.ai != null:
			mouse.ai.alert_for(cat.global_position, &"saw_threat")
		await process_frame
	await _t020_print_state("alert|held_by=repeat_alert", mouse, cat)
	await _capture_view("t020_alert", cam, 4)

	# 2) 逃跑途中（自然时序：警戒到期 + 仍看得见 → FLEE）
	cam.global_position = T020_LANE_CAM
	cam.look_at(T020_LANE_LOOK, Vector3.UP)
	cam.current = true
	var waited := 0
	while waited < 180 and _t020_state(mouse) != &"flee":
		await physics_frame
		waited += 1
	# 刚进 FLEE 时鼠还在起点、正好在相机身后（拍了也看不到"逃"）→ 等它朝洞里真的走出一段再拍
	var flee_from_z := mouse.global_position.z
	var advanced := 0
	while advanced < 240 and _t020_state(mouse) == &"flee" and (flee_from_z - mouse.global_position.z) < 2.0:
		await physics_frame
		advanced += 1
	await _t020_print_state("flee", mouse, cat)
	await _capture_view("t020_flee", cam, 20)

	# 3) 钻进鼠洞躲藏（自然时序：等待 ≤ 15 s）
	cam.global_position = T020_HOLE_CAM
	cam.look_at(T020_HOLE_LOOK, Vector3.UP)
	cam.current = true
	var waited2 := 0
	while waited2 < 900 and _t020_state(mouse) != &"hidden":
		await physics_frame
		waited2 += 1
	await _t020_print_state("hidden", mouse, cat)
	await _capture_view("t020_hidden", cam)
	print("CAP|t020|done|flee_wait_frames=%d|flee_advance_frames=%d|hidden_wait_frames=%d" % [waited, advanced, waited2])


func _t020_state(body: AnimalBody) -> StringName:
	if body.ai == null:
		return &"<none>"
	return body.ai.state_id()


## 打印状态、原因与感知数值（与图像同时进日志；AI/感知缺失时如实打印 `<none>`）
func _t020_print_state(tag: String, mouse: AnimalBody, cat: AnimalBody) -> void:
	var ai := mouse.ai
	var rep: Dictionary = mouse.perception.report() if mouse.perception != null else {}
	print("CAP|t020|%s|ai_state=%s|ai_reason=%s|hide=%s|flee_kind=%s|mouse_pos=%s|cat_pos=%s|seen=%s|heard=%d|noise_age=%.1f" % [
		tag,
		str(ai.state_id()) if ai != null else "<none>",
		str(ai.state_reason()) if ai != null else "<none>",
		ai.hide_target_id() if ai != null else "-",
		str(ai.call("flee_kind")) if ai != null and ai.has_method("flee_kind") else "-",
		mouse.global_position, cat.global_position,
		str(rep.get("seen", false)), int(rep.get("heard_count", 0)), float(rep.get("last_noise_age", -1.0))
	])


# ---------------------------------------------------------------------------
# T021：猫扑击与捕获结算（扑击中途 / 撞墙被挡 / 命中并生成捕获食物）
# ---------------------------------------------------------------------------

const T021_BODY := "res://scenes/characters/animal_body.tscn"
const T021_CAT := "res://resources/species/cat.tres"
const T021_MOUSE := "res://resources/species/mouse.tres"
## 自建探针场：几何全部已知（不依赖关卡布局，避免 T010/T020 那种"主体被侧壁遮住"）
const T021_FLOOR_SIZE := Vector3(8.0, 0.20, 8.0)
const T021_WALL_SIZE := Vector3(2.4, 1.00, 0.20)
const T021_CAT_POS := Vector3(0.0, 0.35, 2.00)     # 猫在 z=2.0，**前向 −Z**
const T021_WALL_Z := 1.00                          # 墙距猫 1.00 m（扑击预算 1.40 m 之内）
const T021_MOUSE_NEAR_Z := 0.80                    # 猎物距猫 1.20 m
const T021_MOUSE_FAR_Z := -1.00                    # 猎物距猫 3.00 m（墙后）
const T021_CAM := Vector3(2.20, 1.20, 3.40)
const T021_LOOK := Vector3(0.0, 0.25, 1.10)


## 三帧：① 扑击中途（无墙无猎物，走满预算）② 撞墙被挡（墙 1.0 m、猎物 3.0 m 在墙后）
## ③ 命中并生成捕获食物。每帧同时打印动作状态与计数，图与状态在同一条日志里。
func _capture_t021_frames(lab: Node) -> void:
	print("CAP|t021|start")
	_t021_isolate_lab(lab)
	var body_packed := load(T021_BODY) as PackedScene
	var cat_cfg := load(T021_CAT) as SpeciesConfig
	var mouse_cfg := load(T021_MOUSE) as SpeciesConfig
	if body_packed == null or cat_cfg == null or mouse_cfg == null:
		print("CAP|t021|ERROR|config/body missing")
		return

	# 1) 扑击中途（0.25 s 的动作拍中间帧：settle 用小值，否则动作已结束）
	var a: Dictionary = _t021_arena(body_packed, cat_cfg, mouse_cfg, false, INF)
	await _t021_settle(a)
	var started: bool = (a["cat"] as AnimalBody).start_pounce()
	for i in 5:
		await physics_frame
	var mid_act := str((a["cat"] as AnimalBody).debug_state().get("action_state", "?"))
	var mid_travel: float = (a["cat"] as AnimalBody).last_pounce_travel
	print("CAP|t021|pounce|started=%s|act=%s|travel=%.2f" % [str(started), mid_act, mid_travel])
	await _capture_view("t021_pounce", a["cam"], 2)
	_t021_free(a)

	# 2) 撞墙被挡（障碍优先于墙后的猎物：位移停在墙前、猎物不被捕获）
	var b: Dictionary = _t021_arena(body_packed, cat_cfg, mouse_cfg, true, T021_MOUSE_FAR_Z)
	await _t021_settle(b)
	var cat_b: AnimalBody = b["cat"]
	var mouse_b: AnimalBody = b["mouse"]
	cat_b.start_pounce()
	var wait_b := 0
	while wait_b < 90 and cat_b.is_pouncing():
		await physics_frame
		wait_b += 1
	for i in 4:
		await physics_frame
	print("CAP|t021|blocked|frames=%d|act=%s|pounce=%d|captures=%d|blocked=%s|travel=%.2f|cat_z=%.2f|wall_z=%.2f|mouse_captured=%s|world_captures=%d" % [
		wait_b, str(cat_b.debug_state().get("action_state", "?")), cat_b.pounce_count, cat_b.captures,
		cat_b.last_pounce_blocked_reason, cat_b.last_pounce_travel,
		cat_b.global_position.z, T021_WALL_Z, str(mouse_b.captured), _t021_world_captures()])
	await _capture_view("t021_blocked", b["cam"], 3)
	_t021_free(b)

	# 3) 命中并生成捕获食物（猎物 1.20 m 在正前方、同一射线上）
	var c: Dictionary = _t021_arena(body_packed, cat_cfg, mouse_cfg, false, T021_MOUSE_NEAR_Z)
	await _t021_settle(c)
	var cat_c: AnimalBody = c["cat"]
	var mouse_c: AnimalBody = c["mouse"]
	cat_c.start_pounce()
	var wait_c := 0
	while wait_c < 90 and cat_c.captures == 0:
		await physics_frame
		wait_c += 1
	for i in 6:
		await physics_frame
	var food: Node = _t021_find_food(c["arena"])
	print("CAP|t021|capture|frames=%d|act=%s|pounce=%d|captures=%d|blocked=%s|travel=%.2f|mouse_captured=%s|mouse_by=%s|world_captures=%d|food_count=%d|food=%s|food_units=%d|food_expire_in=%.1f" % [
		wait_c, str(cat_c.debug_state().get("action_state", "?")), cat_c.pounce_count, cat_c.captures,
		cat_c.last_pounce_blocked_reason, cat_c.last_pounce_travel,
		str(mouse_c.captured), mouse_c.captured_by, _t021_world_captures(), _t021_world_food_count(),
		str(food.global_position) if food != null else "-",
		int(food.units) if food != null else -1,
		float(food.expire_at) - _t021_world_time() if food != null else -1.0])
	await _capture_view("t021_capture", c["cam"], 3)
	_t021_free(c)
	print("CAP|t021|done")


## 自建探针场（地板 + 可选墙 + 猫 + 可选猎物 + 环境光/平行光 + 相机）。返回 arena/cat/mouse/cam。
func _t021_arena(body_packed: PackedScene, cat_cfg: SpeciesConfig, mouse_cfg: SpeciesConfig,
		with_wall: bool, mouse_z: float) -> Dictionary:
	var arena := Node3D.new()
	arena.name = "T021Arena"
	root.add_child(arena)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.9
	env.environment = e
	arena.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	sun.light_energy = 1.1
	arena.add_child(sun)

	arena.add_child(_t021_static_box(Vector3(0.0, -0.10, 0.0), T021_FLOOR_SIZE, Color(0.42, 0.44, 0.40)))
	if with_wall:
		arena.add_child(_t021_static_box(Vector3(0.0, 0.50, T021_WALL_Z), T021_WALL_SIZE, Color(0.62, 0.55, 0.42)))

	var cat := body_packed.instantiate() as AnimalBody
	cat.species_config = cat_cfg
	cat.player_controlled = false
	cat.ai_enabled = false
	cat.position = T021_CAT_POS
	arena.add_child(cat)

	var mouse: AnimalBody = null
	if is_finite(mouse_z):
		mouse = body_packed.instantiate() as AnimalBody
		mouse.species_config = mouse_cfg
		mouse.player_controlled = false
		mouse.ai_enabled = false
		mouse.position = Vector3(0.0, 0.35, mouse_z)
		arena.add_child(mouse)

	var cam := Camera3D.new()
	cam.name = "T021Camera"
	cam.near = 0.05
	cam.far = 400.0
	cam.fov = 55.0
	arena.add_child(cam)
	cam.global_position = T021_CAM
	cam.look_at(T021_LOOK, Vector3.UP)
	cam.current = true
	return {"arena": arena, "cat": cat, "mouse": mouse, "cam": cam}


## 落地稳定（等重力把身体放到地板上；同时确认 `can_pounce()` 已随物种配置生效）
func _t021_settle(a: Dictionary) -> void:
	for i in 24:
		await physics_frame
	var cat: AnimalBody = a["cat"]
	print("CAP|t021|fixture|cat_can_pounce=%s|cat_on_floor=%s|cat_pos=%s|mouse=%s" % [
		str(cat.can_pounce()), str(cat.is_on_floor()), cat.global_position,
		str(a["mouse"].global_position) if a["mouse"] != null else "-"])


func _t021_free(a: Dictionary) -> void:
	var arena := a["arena"] as Node
	if arena != null and is_instance_valid(arena):
		arena.queue_free()


## 隔离：探针场之外**不要**出现在画面里。lab 自带 `Player`（一个 `animal_body.tscn` 的猫）站在
## 原点 1.5 m 高处，正好落在探针场里 → 会被误读成"第二个胶囊"；lab 的蓝/黄标尺同理污染取景。
## 这里隐藏 lab 的可视物并把它的 Player 移出碰撞/物理，保证帧里只有探针场几何。
func _t021_isolate_lab(lab: Node) -> void:
	if lab == null:
		return
	if lab is Node3D:
		(lab as Node3D).visible = false
	var player := lab.get_node_or_null("Player") as CollisionObject3D
	if player != null:
		player.collision_layer = 0
		player.collision_mask = 0
		player.set_physics_process(false)
	print("CAP|t021|isolate|lab=%s|lab_is_node3d=%s|lab_player=%s|player_layer=%d" % [
		lab.name, str(lab is Node3D), str(player != null),
		player.collision_layer if player != null else -1])


## 探针场里的静态盒（碰撞层 1 = world_static，与 AnimalBody 的 LAYER_WORLD_STATIC 一致）
func _t021_static_box(pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var cuboid := BoxShape3D.new()
	cuboid.size = size
	shape.shape = cuboid
	body.add_child(shape)
	return body


func _t021_world_captures() -> int:
	var wd := _t021_world_director()
	return int(wd.get("capture_count")) if wd != null else -1


func _t021_world_food_count() -> int:
	var wd := _t021_world_director()
	return int(wd.get("capture_food_count")) if wd != null else -1


## `WorldDirector` 单例（本工具 `extends SceneTree`，所以走 `root` 查节点，**不用** autoload 全局名）
func _t021_world_director() -> Node:
	return root.get_node_or_null("WorldDirector")


## 当前世界时间（秒）；拿不到单例时返回 -1
func _t021_world_time() -> float:
	var wd := _t021_world_director()
	return float(wd.get("world_time")) if wd != null else -1.0


## 捕获食物对象（在探针场里找 `ResourcePoint`，**不依赖组件节点名**；多个时取最后一个）
func _t021_find_food(arena: Node) -> Node:
	if arena == null:
		return null
	var found: Node = null
	for child in arena.get_children():
		if child is ResourcePoint:
			found = child
	return found


# ---------------------------------------------------------------------------
# T022：猫循环回归（死亡 HUD 的 F6 重开提示 / 重开后再跑一次捕获并生成捕获食物）
# ---------------------------------------------------------------------------

const T022_ENTRY := "res://scenes/debug/debug_entry.tscn"
const T022_BODY := "res://scenes/characters/animal_body.tscn"
const T022_MOUSE := "res://resources/species/mouse.tres"


## 两帧（都带屏幕空间的调试 HUD，所以"重开提示是否真的显示出来"可直接看图）：
##   ① 死亡态：`hud_text()` 应含"按 F6 重开"，用**玩家自己的相机**（真实玩家视角）；
##   ② 重开后：新一局活着 + 再捕一次成功 → 猎物表现消失、命中点出现捕获食物。
func _capture_t022_frames(lab: Node) -> void:
	print("CAP|t022|start")
	lab.queue_free()
	await process_frame
	await process_frame
	var packed: PackedScene = load(T022_ENTRY)
	if packed == null:
		print("CAP|t022|ERROR|debug entry load failed")
		return
	var entry: Node3D = packed.instantiate() as Node3D
	root.add_child(entry)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in SETTLE_FRAMES:
		await process_frame
	var player: AnimalBody = entry.get("player") as AnimalBody
	var level: Node3D = entry.get("level") as Node3D
	if player == null or level == null:
		print("CAP|t022|ERROR|player/level missing")
		return
	print("CAP|t022|boot|species=%s|player_pos=%s|hud=%s|start_species=%s" % [
		str(entry.get("current_species")), str(player.global_position),
		str(entry.call("hud_enabled")), str(entry.get("start_species"))])

	# ① 死亡态（玩家自己的相机 = 真实玩家视角）
	player.survival.apply_damage(9999.0, &"test")
	for i in 20:
		await process_frame
	var hud_dead := String(entry.call("hud_text"))
	var cam0 := root.get_viewport().get_camera_3d()
	print("CAP|t022|death|is_dead=%s|act=%s|hud_has_restart_hint=%s|cam=%s" % [
		str(player.survival.is_dead()), player.action_state_name(),
		str(hud_dead.contains("重开")), cam0.name if cam0 != null else "<none>"])
	print("CAP|t022|death_hud_text=%s" % hud_dead.replace("\n", " | "))
	if cam0 != null:
		await _capture_view("t022_death_hud", cam0)

	# ② 重开 → 再捕一次
	var rc: int = int(entry.call("restart_round", &"capture"))
	for i in 30:
		await physics_frame
	var cat: AnimalBody = entry.get("player") as AnimalBody
	var level2: Node3D = entry.get("level") as Node3D
	if cat == null or level2 == null:
		print("CAP|t022|ERROR|new round player/level missing")
		return
	print("CAP|t022|restart|count=%d|species=%s|player_pos=%s|world_time=%.2f|on_floor=%s|captures=%d" % [
		rc, str(cat.species_config.species_id), str(cat.global_position), _t021_world_time(),
		str(cat.is_on_floor()), cat.captures])

	var mouse_cfg := load(T022_MOUSE) as SpeciesConfig
	var body_packed := load(T022_BODY) as PackedScene
	if mouse_cfg == null or body_packed == null:
		print("CAP|t022|ERROR|mouse config/body missing")
		return
	var mouse := body_packed.instantiate() as AnimalBody
	mouse.species_config = mouse_cfg
	mouse.player_controlled = false
	mouse.ai_enabled = false
	var fwd := -cat.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
	mouse.position = cat.global_position + fwd * 0.90 - Vector3(0.0, 0.15, 0.0)
	level2.add_child(mouse)
	for i in 24:
		await physics_frame
	print("CAP|t022|prey|pos=%s|on_floor=%s|capsule_h=%.3f" % [
		str(mouse.global_position), str(mouse.is_on_floor()), mouse.species_config.capsule_height()])

	var started := cat.request_pounce()
	var waited := 0
	while waited < 90 and cat.captures == 0:
		await physics_frame
		waited += 1
	for i in 6:
		await physics_frame
	var food: Node = _t021_find_food(level2)
	var cam := Camera3D.new()
	cam.name = "T022Camera"
	cam.near = 0.05
	cam.far = 400.0
	cam.fov = 60.0
	level2.add_child(cam)
	# 机位：猎物/食物前方侧上（主体是"命中点上的捕获食物 + 它身后的猫"）
	cam.global_position = cat.global_position + fwd * 1.55 + Vector3(1.45, 1.10, 0.0)
	cam.look_at(cat.global_position + fwd * 0.35 + Vector3(0.0, 0.05, 0.0), Vector3.UP)
	cam.current = true
	var hud_alive := String(entry.call("hud_text"))
	print("CAP|t022|capture|started=%s|frames=%d|pounces=%d|captures=%d|prey_captured=%s|prey_by=%s|world_captures=%d|food_count=%d|food=%s|food_units=%d|food_expire_in=%.1f" % [
		str(started), waited, cat.pounce_count, cat.captures, str(mouse.captured), mouse.captured_by,
		_t021_world_captures(), _t021_world_food_count(),
		str(food.global_position) if food != null else "-",
		int(food.units) if food != null else -1,
		float(food.expire_at) - _t021_world_time() if food != null else -1.0])
	print("CAP|t022|alive_hud_has_restart_hint=%s|hud_text=%s" % [
		str(hud_alive.contains("重开")), hud_alive.replace("\n", " | ")])
	await _capture_view("t022_loop_capture", cam, 8)
	print("CAP|t022|done")


# ---------------------------------------------------------------------------
# T023：猫 NPC 巡游与发现（两帧）。只在显式传 `-- t023` 时执行。
# ---------------------------------------------------------------------------

const T023_ENTRY := "res://scenes/debug/debug_entry.tscn"
const T023_BODY := "res://scenes/characters/animal_body.tscn"
const T023_MOUSE := "res://resources/species/mouse.tres"


## 两帧：① 猫 NPC 在真实关卡里朝第一个巡逻点走（用**玩家自己的相机** = 第一人称）；
## ② 视野内放入猎物，走完 `ALERT → APPROACH` 后从侧后方看猫与鼠（探针相机）。
## 判据：结尾有 `CAP|t023|done` 且两张 `save_result=0 (OK)`。
func _capture_t023_frames(lab: Node) -> void:
	print("CAP|t023|start")
	lab.queue_free()
	await process_frame
	await process_frame
	var packed: PackedScene = load(T023_ENTRY)
	if packed == null:
		print("CAP|t023|ERROR|entry load failed")
		return
	var entry: Node3D = packed.instantiate() as Node3D
	root.add_child(entry)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in SETTLE_FRAMES:
		await process_frame
	var player: AnimalBody = entry.get("player") as AnimalBody
	var level: Node3D = entry.get("level") as Node3D
	if player == null or level == null:
		print("CAP|t023|ERROR|player/level missing")
		return
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
	var right := player.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 1e-8 else Vector3.RIGHT
	# 两个巡逻点在**运行时**放进关卡（正式点位属 T027）
	for i in 2:
		var marker := Marker3D.new()
		marker.name = &"PatrolA" if i == 0 else &"PatrolB"
		marker.position = player.global_position + fwd * 4.0 + right * (1.5 if i == 0 else -1.5)
		marker.add_to_group("patrol_points")
		level.add_child(marker)
	player.ai_enabled = true
	var ai := player.ai as CatAI
	if ai == null:
		print("CAP|t023|ERROR|CatAI missing（cat.tres 未接 ai_script？）")
		return
	print("CAP|t023|patrol|ids=%s|nav_layer=%d|state=%s|reason=%s" % [
		str(ai.patrol_ids()), ai.nav_layer(), str(ai.state_id()), str(ai.state_reason())])
	var start_pos := player.global_position
	var t0 := _t021_world_time()
	while _t021_world_time() - t0 < 3.0:
		await physics_frame
	print("CAP|t023|patrolling|state=%s|reason=%s|target=%s|moved=%.2f m|reached=%d" % [
		str(ai.state_id()), str(ai.state_reason()), ai.patrol_target_id(),
		start_pos.distance_to(player.global_position), ai.patrol_reached_count()])
	var cam0 := root.get_viewport().get_camera_3d()
	if cam0 != null:
		await _capture_view("t023_patrol", cam0, 8)
	else:
		print("CAP|t023|ERROR|no active camera for patrol frame")
	# 视野内放一只鼠 NPC（AI 关掉，站着不动）→ 应走 `ALERT → APPROACH`
	var mouse_cfg := load(T023_MOUSE) as SpeciesConfig
	var body_packed := load(T023_BODY) as PackedScene
	if mouse_cfg == null or body_packed == null:
		print("CAP|t023|ERROR|mouse config/body missing")
		return
	var mouse := body_packed.instantiate() as AnimalBody
	mouse.species_config = mouse_cfg
	mouse.player_controlled = false
	mouse.ai_enabled = false
	# 按猫**当前**朝向放猎物：猫在巡游中已经转过向，用开局朝向会放偏（实测 seen=false）
	var fwd_now := -player.global_transform.basis.z
	fwd_now.y = 0.0
	fwd_now = fwd_now.normalized() if fwd_now.length_squared() > 1e-8 else fwd
	var prey_spot := player.global_position + fwd_now * 5.0
	mouse.position = Vector3(prey_spot.x, 0.10, prey_spot.z)
	level.add_child(mouse)
	await physics_frame
	var t1 := _t021_world_time()
	var seen := false
	var alerted := false
	var approached := false
	while _t021_world_time() - t1 < 8.0:
		await physics_frame
		seen = seen or player.perception.is_threat_visible()
		alerted = alerted or ai.state_id() == &"alert"
		approached = approached or ai.state_id() == &"approach"
		if approached and ai.approach_distance() <= ai.attack_range + 0.05:
			break
	print("CAP|t023|detect|seen=%s|alert=%s|approach=%s|detect_count=%d|dist=%.2f|pounces=%d|prey_health=%.1f" % [
		str(seen), str(alerted), str(approached), ai.detect_count(), ai.approach_distance(),
		player.pounce_count, mouse.survival.state.health])
	var cam := Camera3D.new()
	cam.name = "T023Camera"
	root.add_child(cam)
	var focus := (player.global_position + mouse.global_position) * 0.5 + Vector3(0.0, 0.25, 0.0)
	cam.global_position = focus + right * 2.6 + fwd * -1.4 + Vector3(0.0, 1.5, 0.0)
	cam.look_at(focus)
	cam.make_current()
	await physics_frame
	await _capture_view("t023_approach", cam, 8)
	print("CAP|t023|done")


# ---------------------------------------------------------------------------
# T024：追击与搜索
# ---------------------------------------------------------------------------

const T024_ENTRY := "res://scenes/debug/debug_entry.tscn"
const T024_BODY := "res://scenes/characters/animal_body.tscn"
const T024_MOUSE := "res://resources/species/mouse.tres"


## 两帧（都用**玩家自己的相机** = 第一人称，HUD 里带 `ai:` 行）：
## ① `t024_chase`：视野内放鼠 → 猫接近，再把它"拔到 3 m 处跑开" → `CHASE`（追）；
## ② `t024_search`：把鼠搬到猫**身后 25 m**（视野与视距之外）→ `ALERT → SEARCH`，
##    猫走向**最后已知位置**（HUD `search=(x, y, z)/Ns`）。
## 判据：结尾 `CAP|t024|done` 且两张 `save_result=0 (OK)`。
func _capture_t024_frames(lab: Node) -> void:
	print("CAP|t024|start")
	lab.queue_free()
	await process_frame
	await process_frame
	var packed: PackedScene = load(T024_ENTRY)
	if packed == null:
		print("CAP|t024|ERROR|entry load failed")
		return
	var entry: Node3D = packed.instantiate() as Node3D
	root.add_child(entry)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in SETTLE_FRAMES:
		await process_frame
	var player: AnimalBody = entry.get("player") as AnimalBody
	var level: Node3D = entry.get("level") as Node3D
	if player == null or level == null:
		print("CAP|t024|ERROR|player/level missing")
		return
	player.ai_enabled = true
	var ai := player.ai as CatAI
	if ai == null:
		print("CAP|t024|ERROR|CatAI missing（cat.tres 未接 ai_script？）")
		return
	ai.patrol_enabled = false          # 本任务只看追击与搜索
	var mouse_cfg := load(T024_MOUSE) as SpeciesConfig
	var body_packed := load(T024_BODY) as PackedScene
	if mouse_cfg == null or body_packed == null:
		print("CAP|t024|ERROR|mouse config/body missing")
		return
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
	var mouse := body_packed.instantiate() as AnimalBody
	mouse.species_config = mouse_cfg
	mouse.player_controlled = false
	mouse.ai_enabled = false           # 站着不动的猎物，便于对照
	mouse.position = Vector3(player.global_position.x + fwd.x * 6.0, 0.10, player.global_position.z + fwd.z * 6.0)
	level.add_child(mouse)
	await physics_frame
	# ① 发现 → 警戒 0.4 s → 接近
	var t0 := _t021_world_time()
	var saw := false
	var alerted := false
	while _t021_world_time() - t0 < 8.0:
		await physics_frame
		saw = saw or player.perception.is_threat_visible()
		alerted = alerted or ai.state_id() == &"alert"
		if saw and alerted and ai.state_id() == &"approach":
			break
	print("CAP|t024|found|seen=%s|alert=%s|state=%s|reason=%s|dist=%.2f" % [
		str(saw), str(alerted), str(ai.state_id()), str(ai.state_reason()), ai.approach_distance()])
	# 猎物"跑开"：拔到 3 m 处（同方向、仍在视野内且超出攻击距离）→ 应转 CHASE
	var fwd_now := -player.global_transform.basis.z
	fwd_now.y = 0.0
	fwd_now = fwd_now.normalized() if fwd_now.length_squared() > 1e-8 else fwd
	mouse.global_position = Vector3(
		player.global_position.x + fwd_now.x * 3.0, 0.10, player.global_position.z + fwd_now.z * 3.0)
	var t1 := _t021_world_time()
	var chasing := false
	while _t021_world_time() - t1 < 8.0:
		await physics_frame
		chasing = chasing or ai.is_chasing()
		if chasing and ai.approach_distance() <= 2.4:
			break
	print("CAP|t024|chase|state=%s|reason=%s|chasing=%s|dist=%.2f|chase_count=%d|enc=%s|pounces=%d" % [
		str(ai.state_id()), str(ai.state_reason()), str(ai.is_chasing()), ai.approach_distance(),
		ai.chase_count(), ai.encounter_id(), player.pounce_count])
	var cam0 := root.get_viewport().get_camera_3d()
	if cam0 != null:
		await _capture_view("t024_chase", cam0, 8)
	else:
		print("CAP|t024|ERROR|no active camera for chase frame")
	# ② 猎物"藏起来"：搬到猫**身后 25 m**（视野与视距之外）→ ALERT → SEARCH 到最后已知位置
	mouse.global_position = Vector3(
		player.global_position.x - fwd_now.x * 25.0, 0.10, player.global_position.z - fwd_now.z * 25.0)
	var t2 := _t021_world_time()
	var searched := false
	while _t021_world_time() - t2 < 8.0:
		await physics_frame
		searched = searched or ai.is_searching()
		if searched and ai.state_reason() == &"moving_to_last_seen":
			break
	var t3 := _t021_world_time()
	while _t021_world_time() - t3 < 0.6:     # 走一小段，截图里能看到它在朝最后已知位置去
		await physics_frame
	var snap := ai.search_target()
	print("CAP|t024|search|state=%s|reason=%s|searching=%s|snapshot=(%.2f, %.2f, %.2f)|elapsed=%.2f|giveups=%d|escapes=%d" % [
		str(ai.state_id()), str(ai.state_reason()), str(ai.is_searching()), snap.x, snap.y, snap.z,
		ai.search_elapsed(), ai.give_up_count(), ai.escape_report_count()])
	var cam1 := root.get_viewport().get_camera_3d()
	if cam1 != null:
		await _capture_view("t024_search", cam1, 8)
	else:
		print("CAP|t024|ERROR|no active camera for search frame")
	print("CAP|t024|done")


# ---------------------------------------------------------------------------
# T025：NPC 攻击与玩家受伤
# ---------------------------------------------------------------------------

const T025_ENTRY := "res://scenes/debug/debug_entry.tscn"
const T025_BODY := "res://scenes/characters/animal_body.tscn"
const T025_MOUSE := "res://resources/species/mouse.tres"


## 两帧（都用**玩家自己的相机** = 第一人称，HUD 里带 `ai:` 行）：
## ① `t025_telegraph`：猎物在 0.6 m（攻击距离 0.65 内）→ 进 `ATTACK`、**预警中**（0.45 s 窗口内抓帧，HUD 应显示 `attack=telegraphing`）；
## ② `t025_hit`：伤害帧之后（HUD 应显示 `attack=recovering` 且命中计数 +1；CAP 行打印猎物生命 100 → 65）。
## 判据：结尾 `CAP|t025|done` 且两张 `save_result=0 (OK)`。
func _capture_t025_frames(lab: Node) -> void:
	print("CAP|t025|start")
	lab.queue_free()
	await process_frame
	await process_frame
	var packed: PackedScene = load(T025_ENTRY)
	if packed == null:
		print("CAP|t025|ERROR|entry load failed")
		return
	var entry: Node3D = packed.instantiate() as Node3D
	root.add_child(entry)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in SETTLE_FRAMES:
		await process_frame
	var player: AnimalBody = entry.get("player") as AnimalBody
	var level: Node3D = entry.get("level") as Node3D
	if player == null or level == null:
		print("CAP|t025|ERROR|player/level missing")
		return
	player.ai_enabled = true
	var ai := player.ai as CatAI
	if ai == null:
		print("CAP|t025|ERROR|CatAI missing")
		return
	ai.patrol_enabled = false
	ai.attack_enabled = true
	var mouse_cfg := load(T025_MOUSE) as SpeciesConfig
	var body_packed := load(T025_BODY) as PackedScene
	if mouse_cfg == null or body_packed == null:
		print("CAP|t025|ERROR|mouse config/body missing")
		return
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
	var mouse := body_packed.instantiate() as AnimalBody
	mouse.species_config = mouse_cfg
	mouse.player_controlled = false
	mouse.ai_enabled = false
	var spot := player.global_position + fwd * 0.6
	mouse.position = Vector3(spot.x, 0.10, spot.z)
	level.add_child(mouse)
	await physics_frame
	var hp0: float = mouse.survival.state.health
	print("CAP|t025|setup|prey_hp=%.1f|gap=%.2f|range=%.2f|telegraph=%.2f|damage=%.1f" % [
		hp0, player.global_position.distance_to(mouse.global_position),
		(player.attack.config.attack_range if player.attack != null else -1.0),
		(player.attack.config.attack_telegraph if player.attack != null else -1.0),
		(player.attack.config.attack_damage if player.attack != null else -1.0)])
	var t0 := _t021_world_time()
	var tele := false
	while _t021_world_time() - t0 < 8.0:
		await physics_frame
		if player.attack != null and player.attack.is_attacking():
			tele = true
			break
	print("CAP|t025|telegraph|state=%s|reason=%s|attack_state=%s|elapsed=%.3f|hits=%d|prey_hp=%.1f" % [
		str(ai.state_id()), str(ai.state_reason()),
		(player.attack.state_name() if player.attack != null else "none"),
		(player.attack.telegraph_elapsed() if player.attack != null else -1.0),
		(player.attack.hit_count if player.attack != null else -1), mouse.survival.state.health])
	var cam0 := root.get_viewport().get_camera_3d()
	if tele and cam0 != null:
		await _capture_view("t025_telegraph", cam0, 2)
	else:
		print("CAP|t025|ERROR|no telegraph window（tele=%s）" % str(tele))
	var t1 := _t021_world_time()
	var hit := false
	while _t021_world_time() - t1 < 4.0:
		await physics_frame
		if player.attack != null and player.attack.hit_count >= 1:
			hit = true
			break
	for i in 6:
		await physics_frame
	print("CAP|t025|hit|hits=%d|misses=%d|attack_state=%s|prey_hp=%.1f|damage=%.1f|reason=%s" % [
		(player.attack.hit_count if player.attack != null else -1),
		(player.attack.miss_count if player.attack != null else -1),
		(player.attack.state_name() if player.attack != null else "none"),
		mouse.survival.state.health,
		(player.attack.last_damage if player.attack != null else -1.0),
		str(mouse.survival.state.last_damage_reason)])
	var cam1 := root.get_viewport().get_camera_3d()
	if hit and cam1 != null:
		await _capture_view("t025_hit", cam1, 2)
	else:
		print("CAP|t025|ERROR|no hit（hit=%s）" % str(hit))
	print("CAP|t025|done")
# ---------------------------------------------------------------------------
# T026：老鼠藏身与掩体规则（草丛只降可见性 / 鼠洞阻止猫进入）

const T026_ENTRY := "res://scenes/debug/debug_entry.tscn"
const T026_BODY := "res://scenes/characters/animal_body.tscn"
const T026_MOUSE := "res://resources/species/mouse.tres"


## 两帧（都用**自带第三人称相机**；HUD 是 CanvasLayer，仍会出现在画面上）：
## ① `t026_cover`：鼠站在**草丛体量**里、猫在 4.5 m 外（> 9.0 × 0.4 = 3.6）→ CAP 行给 `cover_factor/visible` 客观值；
## ② `t026_hole`：鼠在洞腔里、猫贴在墙外 → CAP 行给两边到洞心的距离与状态。
## 判据：结尾 `CAP|t026|done` 且两张 `save_result=0 (OK)`。
func _capture_t026_frames(lab: Node) -> void:
	print("CAP|t026|start")
	lab.queue_free()
	await process_frame
	await process_frame
	var packed: PackedScene = load(T026_ENTRY)
	if packed == null:
		print("CAP|t026|ERROR|entry load failed")
		return
	var entry: Node3D = packed.instantiate() as Node3D
	root.add_child(entry)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in SETTLE_FRAMES:
		await process_frame
	var player: AnimalBody = entry.get("player") as AnimalBody
	var level: Node3D = entry.get("level") as Node3D
	if player == null or level == null:
		print("CAP|t026|ERROR|player/level missing")
		return
	var mouse_cfg := load(T026_MOUSE) as SpeciesConfig
	var body_packed := load(T026_BODY) as PackedScene
	if mouse_cfg == null or body_packed == null:
		print("CAP|t026|ERROR|mouse config/body missing")
		return
	player.ai_enabled = true
	var ai := player.ai as CatAI
	if ai == null:
		print("CAP|t026|ERROR|CatAI missing")
		return
	ai.patrol_enabled = false
	ai.attack_enabled = false
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
	var right := player.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 1e-8 else Vector3.RIGHT
	var mouse := body_packed.instantiate() as AnimalBody
	mouse.species_config = mouse_cfg
	mouse.player_controlled = false
	mouse.ai_enabled = false
	var grass_at := player.global_position + fwd * 4.5
	var cover := _t026_cover_volume(level, Vector3(grass_at.x, 0.75, grass_at.z), Vector3(2.4, 1.5, 2.4), 0.4)
	mouse.position = Vector3(grass_at.x, 0.10, grass_at.z)
	level.add_child(mouse)
	for i in 12:
		await physics_frame
	var cf := player.perception.cover_factor_at(mouse.global_position)
	var seen := player.perception.is_threat_visible()
	print("CAP|t026|cover|dist=%.2f|cover_factor=%.2f|vision_range=%.2f|eff_range=%.2f|visible=%s|cover_fixture=%s|cat_state=%s|cat_reason=%s" % [
		player.global_position.distance_to(mouse.global_position), cf, player.species_config.vision_range,
		player.species_config.vision_range * cf, str(seen), str(cover != null),
		str(ai.state_id()), str(ai.state_reason())])
	var cam0 := Camera3D.new()
	cam0.fov = 60.0
	root.add_child(cam0)
	cam0.global_position = player.global_position - fwd * 2.2 + right * 1.6 + Vector3(0.0, 1.5, 0.0)
	cam0.look_at(mouse.global_position + Vector3(0.0, 0.15, 0.0), Vector3.UP)
	cam0.current = true
	await _capture_view("t026_cover", cam0, 6)
	var hole := _t026_hole_marker()
	if hole == null:
		print("CAP|t026|ERROR|hole marker missing")
		return
	var hole_point: Vector3 = hole.global_position
	var normal := _t026_wall_normal(level)
	var mouse_in := hole_point + normal * 0.25
	mouse.ai_enabled = false
	mouse.global_position = Vector3(mouse_in.x, 0.10, mouse_in.z)
	var side := normal.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-8 else Vector3.RIGHT
	var cat_out := hole_point + normal * 0.95 - side * 0.30
	player.global_position = Vector3(cat_out.x, 0.25, cat_out.z)
	await physics_frame
	player.look_at(Vector3(hole_point.x, player.global_position.y, hole_point.z), Vector3.UP)
	await physics_frame
	mouse.look_at(Vector3(player.global_position.x, mouse.global_position.y, player.global_position.z), Vector3.UP)
	for i in 4:
		await physics_frame
	mouse.ai_enabled = true
	for i in 2:
		await physics_frame
	var m_ai := mouse.ai as MouseAI
	var hid := false
	var t0 := _t021_world_time()
	while _t021_world_time() - t0 < 4.0:
		await physics_frame
		if m_ai != null and m_ai.state_id() == &"hidden":
			hid = true
			break
	var cat_d := player.global_position.distance_to(hole_point)
	var mouse_d := mouse.global_position.distance_to(hole_point)
	print("CAP|t026|hole|cat_to_hole=%.3f|mouse_to_hole=%.3f|radius=%.2f|hid=%s|mouse_state=%s|hidden_n=%d|cat_state=%s|cat_reason=%s|gap=%.2f" % [
		cat_d, mouse_d, float(hole.get_meta("radius", -1.0)), str(hid),
		str(m_ai.state_id()) if m_ai != null else "<null>", m_ai.hidden_count() if m_ai != null else -1,
		str(ai.state_id()), str(ai.state_reason()), player.global_position.distance_to(mouse.global_position)])
	var cam1 := Camera3D.new()
	cam1.fov = 55.0
	root.add_child(cam1)
	# 低机位 + 离轴 0.70 m：从猫旁边看进洞口缝里的鼠（洞腔 0.24 宽 × 0.30 高 → 轴向约 ±13° 内可见）
	cam1.global_position = hole_point + normal * 2.4 + side * 0.70 + Vector3(0.0, 0.55, 0.0)
	cam1.look_at(hole_point + Vector3(0.0, 0.15, 0.0), Vector3.UP)
	cam1.current = true
	await _capture_view("t026_hole", cam1, 6)
	print("CAP|t026|done")


## 造一个"草丛体量"（与关卡 `cover_volumes` 同构：`Area3D` + layer 0 + `visibility_factor`，非实体）
func _t026_cover_volume(parent: Node, pos: Vector3, size: Vector3, factor: float) -> Area3D:
	var area := Area3D.new()
	area.name = "T026CoverFixture"
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.position = pos
	area.set_meta("visibility_factor", factor)
	area.set_meta("role", "cover")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	area.add_child(cs)
	var mesh := MeshInstance3D.new()
	mesh.name = "FixtureVisual"
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.80, 0.30, 0.30)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	area.add_child(mesh)
	area.add_to_group(&"cover_volumes")
	parent.add_child(area)
	return area


## 洞轴 = 墙法线：关卡 RootBarrier 墙（group `nav_source_courtyard`，名字含 `Lintel`）的本地 z 轴
func _t026_wall_normal(level: Node) -> Vector3:
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and n.is_in_group(&"nav_source_courtyard") and String(n.name).contains("Lintel"):
			var axis := (n as Node3D).global_transform.basis.z
			axis.y = 0.0
			if axis.length_squared() > 1e-8:
				return axis.normalized()
		for c in n.get_children():
			stack.append(c)
	return Vector3(0.0, 0.0, 1.0)


func _t026_hole_marker() -> Node3D:
	for n in get_nodes_in_group(&"hide_spots"):
		if n is Node3D and n.has_meta("kind") and String(n.get_meta("kind")) == "mouse_hole":
			return n as Node3D
	return null
