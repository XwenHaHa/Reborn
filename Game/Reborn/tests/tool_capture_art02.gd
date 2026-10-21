extends SceneTree
## ART02 视觉捕获：**同一机位、同一光照、同一玩家相机**下拍"胶囊占位(before) vs 真实模型(after)"。
##
## 为什么单独写一个工具：`tool_capture_render.gd` 与 `l_movement_lab` 绑得很紧（ART01 的教训），
## 这里的取证必须在**真实生态入口 + 真实玩家相机**里完成，而且要能在运行中把视觉退回胶囊占位。
##
## 用法（**不能加 --headless**，需要窗口出图）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_art02.gd' --quit-after 9000 -- art02
##
## 产物（user://，随后复制到 Art/Probes）：
##   art02_ingame_before.png / art02_ingame_after.png   —— 鼠玩家第一人称，猫在 1.6 m 正面
## 判据：结尾有 `CAP|art02|done`，且每张 `save_result=0 (OK)`。

const ENTRY := "res://scenes/debug/ecology_entry.tscn"
const CAT_ID := &"Cat"
const MOUSE_ID := &"Mouse"
const CAT_DISTANCE := 1.6
const SETTLE_FRAMES := 40


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("art02"):
		print("CAP|art02|skip|pass '-- art02' to run")
		quit(0)
		return
	await _run()


func _run() -> void:
	print("CAP|art02|start")
	var packed: PackedScene = load(ENTRY)
	if packed == null:
		print("CAP|art02|ERROR|entry load failed")
		quit(1)
		return
	var entry: Node3D = packed.instantiate() as Node3D
	root.add_child(entry)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in SETTLE_FRAMES:
		await process_frame

	var player: AnimalBody = entry.get("player") as AnimalBody
	if player == null:
		print("CAP|art02|ERROR|no player")
		quit(1)
		return
	# 玩家必须是鼠：这条线的观察距离/威胁感就是"被猫逼近"
	var mouse_cfg: SpeciesConfig = entry.get("mouse_config") as SpeciesConfig
	if player.species_config.species_id != MOUSE_ID and mouse_cfg != null:
		entry.call("switch_species", MOUSE_ID)
		for i in SETTLE_FRAMES:
			await process_frame
		player = entry.get("player") as AnimalBody

	var eco: EcologySpawner = entry.get("ecology") as EcologySpawner
	if eco == null:
		print("CAP|art02|ERROR|no ecology")
		quit(1)
		return
	var cat: AnimalBody = null
	for b in eco.npc_bodies():
		if b.species_config != null and b.species_config.species_id == CAT_ID:
			cat = b
			break
	if cat == null:
		print("CAP|art02|ERROR|no cat npc")
		quit(1)
		return

	# 固定观察条件：鼠玩家不动、猫不巡逻、猫站在玩家正前方 CAT_DISTANCE 处并面向玩家
	player.player_controlled = false
	player.move_intent = Vector2.ZERO
	if cat.ai != null and cat.ai is CatAI:
		(cat.ai as CatAI).patrol_enabled = false
	cat.player_controlled = false
	var cam: Camera3D = player.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		print("CAP|art02|ERROR|no player camera")
		quit(1)
		return
	_place_cat(player, cat, cam)
	for i in SETTLE_FRAMES:
		await physics_frame
		cat.move_intent = Vector2.ZERO
	_place_cat(player, cat, cam)
	for i in 4:
		await process_frame
	print("CAP|art02|place|cat_pos=%s|cat_yaw=%.1f|cam_pos=%s|cam_dist=%.2f|visual=%s" % [
		cat.global_position, cat.global_rotation_degrees.y, cam.global_position,
		cam.global_position.distance_to(cat.global_position),
		str(cat.visual_root != null)])

	# ---- before：把视觉退回胶囊占位（同一帧、同一机位）----
	var cat_cfg: SpeciesConfig = cat.species_config
	cat_cfg.visual_scene = null
	cat.call("_rebuild_visual")
	for i in 6:
		await process_frame
	await _save("art02_ingame_before")

	# ---- after：恢复真实模型 ----
	cat_cfg.visual_scene = load("res://assets/characters/cat/sm_cat_001.glb")
	cat.call("_rebuild_visual")
	for i in 6:
		await process_frame
	await _save("art02_ingame_after")

	print("CAP|art02|done")
	quit(0)


func _place_cat(player: AnimalBody, cat: AnimalBody, cam: Camera3D) -> void:
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var target: Vector3 = player.global_position + fwd * CAT_DISTANCE
	cat.global_position = Vector3(target.x, player.global_position.y, target.z)
	cat.velocity = Vector3.ZERO
	cat.look_at(Vector3(player.global_position.x, cat.global_position.y, player.global_position.z),
		Vector3.UP)


func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("CAP|art02|%s|ERROR|no image" % tag)
		return
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|art02|save_result=%d (%s)|path=%s|global=%s" % [
		err, "OK" if err == OK else "FAIL", path, ProjectSettings.globalize_path(path)])
