extends SceneTree
## ART09-E 取证：展板切片关 `l_ravine_board.tscn` 的第三人称/环境帧。**必须非 headless**。
##
## 用法：`& $g --path $proj --script 'res://tests/tool_capture_art09_board.gd' --quit-after 60000 -- ravine`
##
## 机位是**固定常量**（展板构图基准）：第三人称 = 相机高 0.62 m、下俯 ~10°、FOV 58、远景景深；
## 全部帧输出 `CAP|ravine|<tag>|save_result=...`，结束时 `CAP|ravine|done`。

const LEVEL := "res://scenes/maps/l_ravine_board.tscn"
const BODY := "res://scenes/characters/animal_body.tscn"
const CAT_CFG := "res://resources/species/cat.tres"

const RES := Vector2i(1280, 720)
const SETTLE := 10

## 第三人称：站在主体后上方，视线穿过主体落进溪谷（下俯 ~12°）
const TP_OFFSET := Vector3(0.45, 0.58, 1.35)
const TP_LOOK := Vector3(0.02, 0.14, -2.60)
const TP_FOV := 58.0
const TP_NEAR := 0.05

## 其余环境机位（同一场景、不同取景）
const SHOTS := [
	{"tag": "ravine_tp_wide", "pos": Vector3(1.15, 0.70, 2.20),
		"look": Vector3(-0.20, 0.22, -3.20), "fov": 50.0},
	{"tag": "ravine_env_creek", "pos": Vector3(0.60, 0.40, 0.20),
		"look": Vector3(4.00, 0.14, -3.20), "fov": 42.0},
	{"tag": "ravine_env_roots", "pos": Vector3(-0.20, 0.50, -3.00),
		"look": Vector3(-1.60, 0.38, -5.40), "fov": 40.0},
	{"tag": "ravine_env_far", "pos": Vector3(0.00, 1.35, 3.00),
		"look": Vector3(-4.00, 0.50, -9.00), "fov": 46.0},
]

func _initialize() -> void:
	root.size = RES
	if not OS.get_cmdline_user_args().has("ravine"):
		print("CAP|ravine|ERROR|need_arg|pass '-- ravine'")
		quit(1)
		return
	print("CAP|ravine|begin")
	await _run()
	print("CAP|ravine|done")
	quit(0)


func _run() -> void:
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		print("CAP|ravine|ERROR|level_load_failed")
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	for i in SETTLE:
		await process_frame

	var anchor := level.get_node_or_null("BoardSubjectAnchor") as Marker3D
	var subject_at := anchor.global_position if anchor != null else Vector3(0.0, 0.10, 2.4)
	var body := await _spawn_cat(level, subject_at)

	# 第三人称主帧：相机挂在主体后上方，视线穿过主体落进溪谷
	var cam := _make_camera(level, "TPCamera", subject_at + TP_OFFSET,
		subject_at + TP_LOOK, TP_FOV, true)
	cam.current = true
	await _save("ravine_tp")

	for shot in SHOTS:
		cam.current = false
		var c := _make_camera(level, "Cam_%s" % String(shot["tag"]),
			shot["pos"] as Vector3, shot["look"] as Vector3, float(shot["fov"]), false)
		c.current = true
		await _save(String(shot["tag"]))

	if body != null:
		body.queue_free()
	level.queue_free()
	for i in 4:
		await process_frame


func _spawn_cat(parent: Node3D, at: Vector3) -> AnimalBody:
	var cfg := load(CAT_CFG) as SpeciesConfig
	if cfg == null:
		print("CAP|ravine|ERROR|cat_config_missing")
		return null
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.name = "BoardSubjectCat"
	body.species_config = cfg
	body.player_controlled = false
	body.make_camera_current = false
	body.position = at + Vector3(0.0, cfg.capsule_half_height + 0.02, 0.0)
	# 面朝 −Z（Godot 前方）：动物模型本身面朝 −Z，rotation 0 就是朝溪谷
	body.rotation_degrees = Vector3.ZERO
	parent.add_child(body)
	# 展示关是**零碰撞**的：不冻结物理，CharacterBody3D 会直接掉出画面（首轮实测 y=−0.27）
	await process_frame
	body.set_physics_process(false)
	body.velocity = Vector3.ZERO
	body.position = at + Vector3(0.0, cfg.capsule_half_height + 0.02, 0.0)
	for i in SETTLE:
		await process_frame
	print("CAP|ravine|subject=%s|pos=%s" % [String(cfg.species_id), body.global_position])
	return body


func _make_camera(parent: Node3D, nm: String, from: Vector3, to: Vector3,
		fov: float, with_dof: bool) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = nm
	cam.fov = fov
	cam.near = TP_NEAR
	cam.far = 220.0
	parent.add_child(cam)
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	var pitch := -rad_to_deg(cam.global_rotation.x)
	var dof := "off"
	if with_dof:
		var attrs := CameraAttributesPractical.new()
		var supported := false
		for p in attrs.get_property_list():
			if String(p["name"]) == "dof_blur_far_enabled":
				supported = true
				break
		if supported:
			attrs.set("dof_blur_far_enabled", true)
			attrs.set("dof_blur_far_distance", 7.0)
			attrs.set("dof_blur_far_transition", 5.0)
			attrs.set("dof_blur_amount", 0.06)
			cam.attributes = attrs
			dof = "on"
	print("FRAME|%s|pos=(%.2f, %.2f, %.2f)|pitch=%.1f|fov=%.0f|dof=%s" % [
		nm, from.x, from.y, from.z, pitch, fov, dof,
	])
	return cam


func _save(tag: String) -> void:
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	var tex := root.get_viewport().get_texture()
	if tex == null:
		print("CAP|ravine|%s|ERROR|no_texture" % tag)
		return
	var image := tex.get_image()
	if image == null:
		print("CAP|ravine|%s|ERROR|no_image" % tag)
		return
	var path := "user://%s.png" % tag
	var err := image.save_png(path)
	print("CAP|ravine|%s|save_result=%d (%s)|%s" % [
		tag, err, "OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path),
	])
