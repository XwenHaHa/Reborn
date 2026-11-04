extends SceneTree
## ART15：角色接地感取证机（**必须非 headless**，走 Tools/CaptureRun.ps1 隐藏桌面）。
##
## 目的：只改环境 SSAO / 接触阴影，判"角色是不是贴纸浮在地上"。四个固定机位 × 猫/鼠：
##   stand  开阔地站立（脚底与地面）
##   walk   行走姿态（鼠有 Walk clip；猫为静态网格，日志如实记录无 clip）
##   wall   贴庇护棚西墙（身体侧面与墙脚的接触缝）
##   rock   站在溪中巨石顶（CreekBoulder，碰撞盒顶面 y=1.104）
##
## 机位**完全固定**（距离按物种胶囊高 H 缩放、方向固定），改前/改后逐像素同机位；
## 不跟随相机、不用 alpha 闭环，避免把"变亮/变暗"混成"构图变了"。
##
## 同一进程内还会做一次 vsync 关闭的帧时间采样（120 帧平均），用于改前/改后性能对比。
##
## 用法：
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_art15_grounding.gd -UserArgs "art15_before"
##
## 产物：`user://art15_<pass>_<species>_<station>.png`（由脚本外侧拷到 Art/Probes/<pass>/）

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const SPECIES_PATHS := [
	"res://resources/species/cat.tres",
	"res://resources/species/mouse.tres",
]
const SIZE := Vector2i(1280, 720)
const GROUND_TOP := 0.10
## CreekBoulder：StaticBody3D 中心 y = 0.10 + 1.004233/2，盒顶 = 0.10 + 1.004233
const CREEK_ROCK_TOP := 1.104233
const SETTLE := 10
const CAM_FOV := 32.0
const PERF_FRAMES := 120

## 机位：pos = 角色身体原点（胶囊中心），dir = 相机相对目标的偏移方向，dist_h = 距离 = H * dist_h
const STATIONS := [
	{"name": "stand", "pos": Vector3(1.0, GROUND_TOP, 6.0),
		"dir": Vector3(0.55, 0.35, -1.0), "dist_h": 3.4, "clip": &"Idle"},
	# 行走机位与站立同视向（背景是开阔南侧），只换姿态，保证"接地"判读不受背景/遮挡变化干扰
	{"name": "walk", "pos": Vector3(1.0, GROUND_TOP, 6.0),
		"dir": Vector3(0.55, 0.35, -1.0), "dist_h": 3.4, "clip": &"Walk"},
	# 北侧围栏内侧面 z=30.0；角色原点按胶囊半径贴墙（猫 29.84 / 鼠 29.94，见 _station_pos）
	{"name": "wall", "pos": Vector3(0.0, GROUND_TOP, 29.84),
		"dir": Vector3(0.55, 0.45, -1.0), "dist_h": 3.2, "clip": &"Idle"},
	{"name": "rock", "pos": Vector3(-14.0, CREEK_ROCK_TOP, 8.0),
		"dir": Vector3(0.9, 0.35, -1.0), "dist_h": 3.0, "clip": &"Idle"},
]

var _pass := ""


func _initialize() -> void:
	var args := " ".join(OS.get_cmdline_user_args()).strip_edges().split(" ", false)
	if args.is_empty():
		print("ART15|ERROR|need_arg|pass '-- <pass>'")
		quit(1)
		return
	_pass = args[0]
	# vsync 关掉才能拿到"渲染一帧的真实耗时"；与游戏正常游玩无关，只在取证进程内生效
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = SIZE

	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for i in 4:
		await process_frame
	_report_environment(level)

	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	cam.near = 0.01
	cam.far = 400.0
	root.add_child(cam)
	cam.current = true

	var made := 0
	for sp in SPECIES_PATHS:
		var cfg := load(sp) as SpeciesConfig
		if cfg == null or cfg.visual_scene == null:
			print("ART15|ERROR|species_load|%s" % sp)
			continue
		for st in STATIONS:
			if await _render_station(level, cam, cfg, st):
				made += 1
	await _perf_sample()

	print("ART15|done|pass=%s|images=%d" % [_pass, made])
	quit(0 if made == 8 else 1)


func _report_environment(level: Node) -> void:
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := level.get_node_or_null("SunLight") as DirectionalLight3D
	if we != null and we.environment != null:
		var e := we.environment
		print("ART15|env|ssao=%s|radius=%.3f|intensity=%.2f|power=%.2f|horizon=%.2f|sharpness=%.2f|detail=%.2f|light_affect=%.2f" % [
			str(e.ssao_enabled), e.ssao_radius, e.ssao_intensity, e.ssao_power,
			e.ssao_horizon, e.ssao_sharpness, e.ssao_detail, e.ssao_light_affect])
	if sun != null:
		print("ART15|sun|shadow=%s|bias=%.3f|normal_bias=%.3f|blur=%.2f|mode=%d|max_dist=%.1f|angular=%.1f" % [
			str(sun.shadow_enabled), sun.shadow_bias, sun.shadow_normal_bias, sun.shadow_blur,
			sun.directional_shadow_mode, sun.directional_shadow_max_distance, sun.light_angular_distance])


func _render_station(level: Node, cam: Camera3D, cfg: SpeciesConfig, st: Dictionary) -> bool:
	var body := (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	body.name = "ART15Subject"
	body.species_config = cfg
	body.player_controlled = false
	body.make_camera_current = false
	body.ai_enabled = false
	# STATIONS.pos 是**脚底所在地面高度**；胶囊以角色原点居中，所以原点要再抬 h/2，
	# 否则模型半截陷地（ART14 已踩过这个坑）。
	var feet: Vector3 = st["pos"] as Vector3
	if String(st["name"]) == "wall":
		feet.z = 30.0 - float(cfg.capsule_radius)
	var h := float(cfg.capsule_height())
	body.position = feet + Vector3(0.0, h * 0.5, 0.0)
	level.add_child(body)
	await process_frame
	body.set_physics_process(false)
	body.velocity = Vector3.ZERO
	_play_clip(body, st["clip"] as StringName, String(st["name"]))

	var aim: Vector3 = body.position + Vector3(0.0, h * 0.42, 0.0)
	var d: Vector3 = (st["dir"] as Vector3).normalized()
	cam.global_position = aim + d * (h * float(st["dist_h"]))
	cam.look_at(aim)

	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	var tex := root.get_texture()
	var img := tex.get_image() if tex != null else null
	if img == null:
		print("ART15|ERROR|no_image|%s|%s" % [String(cfg.species_id), String(st["name"])])
		body.queue_free()
		return false
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var sid := String(cfg.species_id).to_lower()
	var path := "user://art15_%s_%s_%s.png" % [_pass, sid, String(st["name"])]
	var err := img.save_png(path)
	print("ART15|shot|pass=%s|species=%s|station=%s|h=%.3f|dist=%.2f|cam=(%.2f,%.2f,%.2f)|save=%s|%s" % [
		_pass, String(cfg.species_id), String(st["name"]), h, h * float(st["dist_h"]),
		cam.global_position.x, cam.global_position.y, cam.global_position.z,
		"OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)])
	body.queue_free()
	for i in 2:
		await process_frame
	return err == OK


func _play_clip(body: AnimalBody, clip: StringName, station: String) -> void:
	var player := body.visual_anim
	if player == null:
		print("ART15|anim|%s|station=%s|no_animation_player" % [body.species_config.species_id, station])
		return
	if not player.has_animation(clip):
		print("ART15|anim|%s|station=%s|clip_missing=%s" % [body.species_config.species_id, station, clip])
		return
	var anim := player.get_animation(clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	player.play(clip)
	player.advance(0.28)
	# 定格：步行片段的姿态用于"脚在半步"的接地判读，不再随时间继续推进（避免不同帧之间姿势漂移）
	player.pause()
	print("ART15|anim|%s|station=%s|playing=%s|t=%.2f" % [
		body.species_config.species_id, station, clip, player.current_animation_position])



func _perf_sample() -> void:
	for i in 20:
		await process_frame
	var t0 := Time.get_ticks_usec()
	for i in PERF_FRAMES:
		await process_frame
	var t1 := Time.get_ticks_usec()
	var ms := float(t1 - t0) / 1000.0 / float(PERF_FRAMES)
	print("ART15|perf|pass=%s|frames=%d|avg_frame_ms=%.3f|fps=%.1f" % [
		_pass, PERF_FRAMES, ms, 1000.0 / ms if ms > 0.0 else 0.0])
