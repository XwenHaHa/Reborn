extends SceneTree
## T052 证据图：鼠的**待机 / 走 / 冲刺**三种表现的姿态差异（0.6 m 侧前方机位）。
##
## 只用于取证：直接写 `move_intent` / `want_sprint`，让 `AnimalBody` 自己切片段
## （`Idle` / `Walk` / `Run`），**不测速度**——速度与状态的一致性在 `run_t052_mouse_anim.gd` 里断言。
##
## 用法（**非 headless**）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_t052_states.gd' --quit-after 20000 -- t052
## 产物：`user://t052_mouse_{idle,walk,run}.png`

const RES := Vector2i(1280, 720)
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const MOUSE_CFG := "res://resources/species/mouse.tres"
const SPAWN := Vector3(-2.0, 0.45, 20.0)

var _level: Node3D = null
var _body: AnimalBody = null
var _cam: Camera3D = null
var _backdrop: MeshInstance3D = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	root.size = RES
	if args.has("t052"):
		await _run()
	else:
		print("CAP|t052|ERROR|need_arg|pass '-- t052'")
	print("CAP|t052|done")
	quit(0)


func _run() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("CAP|t052|ERROR|level_load_failed")
		return
	_level = packed.instantiate() as Node3D
	root.add_child(_level)
	_cam = Camera3D.new()
	_cam.name = "T052Cam"
	_cam.near = 0.01
	_cam.far = 200.0
	_cam.fov = 45.0
	_level.add_child(_cam)

	var cfg := load(MOUSE_CFG) as SpeciesConfig
	_body = (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	_body.species_config = cfg
	_body.ai_enabled = false
	_body.player_controlled = false
	_level.add_child(_body)
	_body.global_position = SPAWN
	for i in 30:
		await physics_frame

	_make_backdrop()

	# 待机
	_body.move_intent = Vector2.ZERO
	_body.want_sprint = false
	for i in 30:
		await physics_frame
	await _shot("idle")

	# 走（沿 -Z）
	_body.move_intent = Vector2(0.0, -1.0)
	for i in 30:
		await physics_frame
	await _shot("walk")

	# 冲刺
	_body.want_sprint = true
	for i in 30:
		await physics_frame
	await _shot("run")


func _make_backdrop() -> void:
	_backdrop = MeshInstance3D.new()
	_backdrop.name = "T052Backdrop"
	var quad := QuadMesh.new()
	quad.size = Vector2(40.0, 24.0)
	_backdrop.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.28, 0.30, 0.32)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_backdrop.material_override = mat
	_level.add_child(_backdrop)


func _shot(tag: String) -> void:
	# 侧前方 1.6 m、平视 0.10 m：冲刺 3.0 m/s 时取景那几帧还会前冲 ~0.2 m，
	# 机位太近会把主体跑出画面（0.6 m 实测踩到：run 帧只剩草地）。
	var focus := _body.global_position + Vector3(0.0, 0.05, 0.0)
	var cam_pos := focus + Vector3(1.13, 0.0, 1.13)
	cam_pos.y = _body.global_position.y + 0.10
	_cam.look_at_from_position(cam_pos, focus, Vector3.UP)
	_cam.current = true
	var away := (focus - cam_pos).normalized()
	_backdrop.global_position = focus + away * 3.0
	_backdrop.look_at(_backdrop.global_position - away, Vector3.UP)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("CAP|t052|%s|ERROR|no_image" % tag)
		return
	var path := "user://t052_mouse_%s.png" % tag
	var err := img.save_png(path)
	print("CAP|t052|%s|clip=%s|speed=%.3f|save=%d (%s)|%s" % [
		tag, str(_body.visual_anim_current),
		Vector2(_body.velocity.x, _body.velocity.z).length(), err,
		"OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)])
