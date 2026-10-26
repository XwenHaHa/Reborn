extends SceneTree
## ART04 取证工具：主菜单 / 物种选择 / 设置 / 出生后的 HUD（**不是断言套件**）
##
## 用法：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_art04.gd' --quit-after 6000 -- art04
##
## 产物：user://art04_*.png（拷到 Art/Probes/ 作为证据）
## 注意：**不能加 `--headless`**（无头是 dummy 渲染器，没有画面）。

const RES := Vector2i(1280, 720)
const SETTLE := 20
const MAIN := "res://scenes/core/main.tscn"


func _initialize() -> void:
	root.size = RES
	if OS.get_cmdline_user_args().has("art04"):
		await _run()
	else:
		print("CAP|art04|ERROR|need_arg|pass '-- art04'")
	print("CAP|art04|done")
	quit(0)


func _run() -> void:
	var packed: PackedScene = load(MAIN)
	if packed == null:
		print("CAP|art04|ERROR|main_load_failed")
		return
	var main := packed.instantiate()
	root.add_child(main)
	for i in SETTLE:
		await process_frame

	var entry := main as MainEntry
	if entry == null:
		print("CAP|art04|ERROR|main_root_not_entry")
		return
	print("CAP|art04|state=%s|menu=%s|species=%s|status=%s" % [
		entry.lifecycle_state_name(),
		str(entry.menu != null),
		str(entry.menu.species_order()) if entry.menu != null else "<none>",
		entry.status_text(),
	])
	var cam := root.get_viewport().get_camera_3d()
	print("CAP|art04|active_camera=%s|pos=%s|fov=%.1f" % [
		cam.name if cam != null else "<none>",
		str(cam.global_position) if cam != null else "-",
		cam.fov if cam != null else -1.0,
	])
	await _save("art04_menu")

	# 物种选择页
	entry.menu.show_page(MainMenu.Page.SPECIES)
	print("CAP|art04|page=species|selected=%s" % str(entry.menu.selected_species()))
	await _save("art04_species")

	# 设置页
	entry.menu.open_settings(true)
	await _save("art04_settings")
	entry.menu.open_settings(false)

	# 切到第二个物种，确认卡片选中态跟着变
	var configs := entry.species_configs()
	if configs.size() > 1:
		entry.menu.select_species(configs[1].species_id)
		print("CAP|art04|selected=%s|card=%s" % [
			str(entry.menu.selected_species()),
			entry.menu.card_text(entry.menu.selected_species()),
		])
		await _save("art04_species_second")

	# 进入世界 → HUD
	entry.menu.commit()
	for i in SETTLE:
		await process_frame
	print("CAP|art04|after_commit|state=%s|life=%s|player=%s|menu_visible=%s|hud_visible=%s" % [
		entry.lifecycle_state_name(), entry.current_life_id(),
		str(entry.player != null), str(entry.menu.visible), str(entry.hud.visible),
	])
	var player_cam := root.get_viewport().get_camera_3d()
	if player_cam != null:
		print("CAP|art04|player_camera=%s|fov=%.1f" % [player_cam.name, player_cam.fov])
		await _save("art04_alive")
	else:
		print("CAP|art04|ERROR|player_camera_missing")

	# 把鼠的饥饿/水分压低，验证条形与低值警告确实在画面上
	if entry.player != null and entry.player.survival != null:
		entry.player.survival.state.hunger = 18.0
		entry.player.survival.state.thirst = 12.0
		entry.player.survival.state.stamina = 40.0
		entry.player.survival.changed.emit(entry.player.survival.state)
		for i in 6:
			await process_frame
		print("CAP|art04|hud_text=%s" % entry.hud.hud_text().replace("\n", " / "))
		await _save("art04_hud_low")

	main.queue_free()
	for i in 4:
		await process_frame


func _save(tag: String) -> void:
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		print("CAP|art04|%s|ERROR|no_texture" % tag)
		return
	var img := tex.get_image()
	if img == null:
		print("CAP|art04|%s|ERROR|no_image" % tag)
		return
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|art04|%s|save_result=%d (%s)|%s" % [
		tag, err, "OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)
	])
