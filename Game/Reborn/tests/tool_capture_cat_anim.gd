extends SceneTree
## ART02-ext 证据图：把带动画的猫放进庭院，拍"走一步的四分之一周期 + 跑 + 转身"。
##
## 用法：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_cat_anim.gd' --quit-after 60000 -- cat-anim
##
## 产物：user://catanim_*.png（拷到 Art/Probes/）

const RES := Vector2i(1280, 720)
const SETTLE := 8
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CAT_CFG := "res://resources/species/cat.tres"
const SPAWN := Vector3(-2.0, 0.45, 20.0)

var _level: Node3D = null
var _body: AnimalBody = null
var _cam: Camera3D = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	root.size = RES
	if args.has("cat-anim"):
		await _run()
	else:
		print("CAP|catanim|ERROR|need_arg|pass '-- cat-anim'")
	print("CAP|catanim|done")
	quit(0)


func _run() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CAP|catanim|ERROR|level_load_failed")
		return
	_level = packed.instantiate() as Node3D
	root.add_child(_level)
	print("CAP|catanim|level=%s" % LEVEL)

	_cam = Camera3D.new()
	_cam.name = "CatAnimCam"
	_cam.near = 0.05
	_cam.far = 200.0
	_cam.fov = 45.0
	_level.add_child(_cam)

	var cat := load(CAT_CFG) as SpeciesConfig
	_body = (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	_body.species_config = cat
	_body.ai_enabled = false
	_body.player_controlled = false
	_level.add_child(_body)
	_body.global_position = SPAWN
	for i in 30:
		await physics_frame
	print("CAP|catanim|body_pos=%s|anim_active=%s|clip=%s|anims=%s" % [
		_body.global_position, str(_body.visual_anim_active), str(_body.visual_anim_current),
		str(_body.visual_anim.get_animation_list() if _body.visual_anim != null else [])])

	# 走：一个 24 帧周期里取 4 个相位
	_body.move_intent = Vector2(0.0, -1.0)
	_body.want_sprint = false
	for i in 12:
		await physics_frame
	for phase in 4:
		for i in 6:
			await physics_frame
		await _shot("catanim_walk_%d" % phase, _body.visual_anim_current)

	# 跑
	_body.want_sprint = true
	for i in 14:
		await physics_frame
	for phase in 2:
		for i in 5:
			await physics_frame
		await _shot("catanim_run_%d" % phase, _body.visual_anim_current)

	# 转身：把意图翻 180°，逐帧记录朝向变化（证明是连续转，不是瞬切）
	_body.move_intent = Vector2(0.0, 1.0)
	var yaws := []
	for i in 8:
		await physics_frame
		yaws.append(snappedf(rad_to_deg(_body.rotation.y), 0.1))
	print("CAP|catanim|turn_yaw_deg=%s" % str(yaws))
	await _shot("catanim_turn", _body.visual_anim_current)


func _shot(tag: String, clip: StringName) -> void:
	var pos := _body.global_position + Vector3(1.9, 1.0, 1.9)
	var look := _body.global_position + Vector3(0.0, 0.13, 0.0)
	_cam.look_at_from_position(pos, look, Vector3.UP)
	_cam.current = true
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("CAP|catanim|%s|ERROR|no_image" % tag)
		return
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|catanim|%s|clip=%s|save_result=%d (%s)|global=%s" % [
		tag, str(clip), err, "OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)])
