extends SceneTree
## ART05 取证工具：第三人称（猫 / 鼠）+ 设置读盘回填（**不是断言套件**）
##
## 用法（**不能加 `--headless`**，无头是 dummy 渲染器）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_tp.gd' --quit-after 6000 -- tp
##
## 产物：user://tp_*.png（拷到 Art/Probes/ 作为证据）

const RES := Vector2i(1280, 720)
const SETTLE := 20
const MAIN := "res://scenes/core/main.tscn"
const SETTINGS_TMP := "user://tp_capture_settings.cfg"


func _initialize() -> void:
	root.size = RES
	if OS.get_cmdline_user_args().has("tp"):
		await _run()
	else:
		print("CAP|tp|ERROR|need_arg|pass '-- tp'")
	print("CAP|tp|done")
	quit(0)


func _run() -> void:
	# 先写一份"已存盘"的设置，用来验证菜单回填（灵敏度 2.00× / FOV 100°）
	GameSettings.save_to({
		GameSettings.KEY_SENSITIVITY: 2.0,
		GameSettings.KEY_FOV: 100.0,
	}, SETTINGS_TMP)

	var main := (load(MAIN) as PackedScene).instantiate()
	(main as MainEntry).settings_path = SETTINGS_TMP
	root.add_child(main)
	for i in SETTLE:
		await process_frame

	var entry := main as MainEntry
	var configs := entry.species_configs()
	print("CAP|tp|settings_loaded|sensitivity=%.2f|fov=%.1f|menu=%s" % [
		entry.sensitivity_scale, entry.fov_override, str(entry.menu.settings_values())
	])
	entry.menu.open_settings(true)
	await _save("tp_settings_saved")
	entry.menu.open_settings(false)

	# 第三人称：猫
	for cfg in configs:
		var is_predator: bool = cfg.can_attack
		entry.select_species(cfg.species_id)
		for i in SETTLE + 10:
			await process_frame
		var player: AnimalBody = entry.player
		if player == null:
			print("CAP|tp|ERROR|player_missing|%s" % String(cfg.species_id))
			continue
		var cam := root.get_viewport().get_camera_3d()
		print("CAP|tp|spawn|%s|third_person=%s|arm=%.3f|dist=%.2f|cam_local=%s|fov=%.0f" % [
			String(cfg.species_id), str(player.is_third_person()), player.third_person_arm,
			cfg.third_person_distance, str(player.camera.position), player.camera.fov,
		])
		await _save("tp_%s" % ("cat" if is_predator else "mouse"))
		# 抬起视线看远一点（同一具相机的俯仰输入路径）
		player.apply_look(0.0, 0.18)
		for i in 6:
			await process_frame
		await _save("tp_%s_look_up" % ("cat" if is_predator else "mouse"))
		if cam != null:
			cam = null
		# 结束这一世，回到菜单（下一轮 species 用同一个入口）
		if player.survival != null:
			player.survival.apply_damage(9999.0, &"tp_capture")
		for i in SETTLE:
			await process_frame

	_remove(SETTINGS_TMP)


func _save(tag: String) -> void:
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		print("CAP|tp|%s|ERROR|no_texture" % tag)
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|tp|%s|ERROR|no_image" % tag)
		return
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|tp|%s|save_result=%d (%s)|%s" % [
		tag, err, "OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)
	])


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
