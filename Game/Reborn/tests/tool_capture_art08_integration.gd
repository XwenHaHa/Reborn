extends SceneTree
## ART08 最终整合取证：真实入口菜单、物种选择和两种出生画面。

const MAIN := "res://scenes/core/main.tscn"
const RES := Vector2i(1280, 720)
const SETTLE := 20

func _initialize() -> void:
	root.size = RES
	if not OS.get_cmdline_user_args().has("integration"):
		print("CAP|integration|ERROR|need_arg|pass '-- integration'")
		quit(1)
		return
	await _run()
	print("CAP|integration|done")
	quit(0)

func _run() -> void:
	var packed := load(MAIN) as PackedScene
	if packed == null:
		print("CAP|integration|ERROR|main_load_failed")
		return
	var main := packed.instantiate() as MainEntry
	# T033：取证工具要选/出生第二物种；正式模式下它呈锁定卡、会被选择门拒绝
	# （菜单呈现层 + `LifeCycle.begin_spawn` 双层门）——开测试模式放行全部物种。
	if main != null:
		main.test_mode = true
	root.add_child(main)
	for i in SETTLE:
		await process_frame
	if main == null or main.menu == null:
		print("CAP|integration|ERROR|entry_or_menu_missing")
		return
	await _save("integration_menu_cat")
	main.menu.show_page(MainMenu.Page.SPECIES)
	await _save("integration_species_cat")
	var configs := main.species_configs()
	if configs.size() < 2:
		print("CAP|integration|ERROR|need_two_species")
		return
	main.menu.select_species(configs[1].species_id)
	await _save("integration_species_mouse")
	main.menu.commit()
	for i in SETTLE:
		await process_frame
	await _save("integration_alive_mouse")
	if main.player != null and main.player.survival != null:
		main.player.survival.apply_damage(9999.0, &"art08_capture")
	for i in SETTLE:
		await process_frame
	main.menu.select_species(configs[0].species_id)
	main.menu.show_page(MainMenu.Page.SPECIES)
	main.menu.commit()
	for i in SETTLE:
		await process_frame
	await _save("integration_alive_cat")
	main.queue_free()

func _save(tag: String) -> void:
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	var tex := root.get_viewport().get_texture()
	if tex == null:
		print("CAP|integration|%s|ERROR|no_texture" % tag)
		return
	var image := tex.get_image()
	if image == null:
		print("CAP|integration|%s|ERROR|no_image" % tag)
		return
	var path := "user://%s.png" % tag
	var err := image.save_png(path)
	print("CAP|integration|%s|save_result=%d (%s)|%s" % [
		tag, err, "OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)])
