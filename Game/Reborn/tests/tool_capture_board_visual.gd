extends SceneTree
## ART08 展板视觉取证；必须使用非 headless Godot。

const RES := Vector2i(1280, 720)
const SETTLE := 20
const MAIN := "res://scenes/core/main.tscn"

func _initialize() -> void:
	root.size = RES
	if not OS.get_cmdline_user_args().has("board"):
		print("CAP|board|ERROR|need_arg|pass '-- board'")
		quit(1)
		return
	print("CAP|board|begin")
	await _run()
	print("CAP|board|done")
	quit(0)

func _run() -> void:
	var packed := load(MAIN) as PackedScene
	if packed == null:
		print("CAP|board|ERROR|main_load_failed")
		return
	var main := packed.instantiate()
	# T033：取证工具要选第二物种；正式模式下它呈锁定卡、会被选择门拒绝——
	# 开测试模式放行全部物种（菜单呈现层 + `LifeCycle.begin_spawn` 双层门都吃 test_mode）。
	(main as MainEntry).test_mode = true
	root.add_child(main)
	for i in SETTLE:
		await process_frame
	var entry := main as MainEntry
	if entry == null or entry.menu == null:
		print("CAP|board|ERROR|entry_or_menu_missing")
		return
	var cam := root.get_viewport().get_camera_3d()
	print("CAP|board|state=%s|selected=%s|camera=%s|viewport=%dx%d" % [
		entry.lifecycle_state_name(), String(entry.menu.selected_species()),
		cam.name if cam != null else "<none>", root.size.x, root.size.y,
	])
	await _save("board_menu")
	entry.menu.show_page(MainMenu.Page.SPECIES)
	await _save("board_species_cat")
	var configs := entry.species_configs()
	if configs.size() > 1:
		entry.menu.select_species(configs[1].species_id)
		await _save("board_species_mouse")
	entry.menu.open_settings(true)
	await _save("board_settings")
	entry.menu.open_settings(false)
	# ART09-C：960×540 下的物种选择页（大卡要收进视口，不能压出下边界）
	entry.menu.show_page(MainMenu.Page.SPECIES)
	root.size = Vector2i(960, 540)
	await _save("board_species_narrow")
	root.size = RES
	entry.menu.show_page(MainMenu.Page.MAIN)
	main.queue_free()
	for i in 4:
		await process_frame

func _save(tag: String) -> void:
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	var tex := root.get_viewport().get_texture()
	if tex == null:
		print("CAP|board|%s|ERROR|no_texture" % tag)
		return
	var image := tex.get_image()
	if image == null:
		print("CAP|board|%s|ERROR|no_image" % tag)
		return
	var path := "user://%s.png" % tag
	var err := image.save_png(path)
	print("CAP|board|%s|save_result=%d (%s)|%s" % [
		tag, err, "OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)
	])
