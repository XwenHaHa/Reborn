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
const SETTLE := 6

## 第三人称：站在主体后上方，视线穿过主体落进溪谷（下俯 ~11°）
## 取景算过：FOV 45 + 斜距 ≈1.5 m 时，0.31 m 高的猫约占总高 0.25（展板约 1/4）
const TP_OFFSET := Vector3(0.42, 0.50, 1.45)
const TP_LOOK := Vector3(0.02, -0.10, -2.20)
const TP_FOV := 45.0
const TP_NEAR := 0.05
## 主体占屏高比的目标区间（`unproject_position` 实测，不是肉眼估）
const SUBJECT_RATIO_MIN := 0.20
const SUBJECT_RATIO_MAX := 0.30

var _failed := false

## 其余环境机位（同一场景、不同取景）
const SHOTS := [
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
	quit(1 if _failed else 0)


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
	# 主体占屏高比：用 unproject 实测（不再"看着差不多"）
	for i in 4:
		await process_frame
	var ratio := _subject_px_ratio(cam, body)
	print("SUBJECT|px_ratio=%.3f|target=%.2f..%.2f" % [
		ratio, SUBJECT_RATIO_MIN, SUBJECT_RATIO_MAX,
	])
	if ratio < SUBJECT_RATIO_MIN or ratio > SUBJECT_RATIO_MAX:
		print("CAP|ravine|FAIL|subject_ratio_out_of_range")
		_failed = true
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
			# ART10：远端景深加深（0.06→0.10、起焦 8 m），并**新增近端景深**
			# （0.7 m 内的前景草虚化）——展板前景是失焦的苔石/草叶，实机旧帧前景是"清晰的一马平川"。
			attrs.set("dof_blur_far_enabled", true)
			attrs.set("dof_blur_far_distance", 8.0)
			attrs.set("dof_blur_far_transition", 4.0)
			attrs.set("dof_blur_near_enabled", true)
			attrs.set("dof_blur_near_distance", 0.7)
			attrs.set("dof_blur_near_transition", 0.45)
			attrs.set("dof_blur_amount", 0.10)
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


## 主体占屏高比 = 头顶到脚底在屏幕上的像素跨度 / 视口高。
## 高度取"模型实际高 ≈ 胶囊高 × 0.65"（ART02/ART06 实测关系），不用胶囊总高虚报。
func _subject_px_ratio(cam: Camera3D, body: AnimalBody) -> float:
	if cam == null or body == null or not is_instance_valid(body):
		return 0.0
	var cfg: SpeciesConfig = body.species_config
	var h := (cfg.capsule_height() * 0.65) if cfg != null else 0.31
	var feet := body.global_position
	var head := feet + Vector3(0.0, h, 0.0)
	var a := cam.unproject_position(feet)
	var b := cam.unproject_position(head)
	return absf(b.y - a.y) / float(RES.y)
