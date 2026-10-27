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
	print("CAP|art04|showcase_begin")
	_report_layout(entry)
	_report_showcase(entry, "menu")
	print("CAP|art04|showcase_end")
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
		_report_showcase(entry, "species_second")
		await _save("art04_species_second")
		# 朝向核对：绕到主视觉的**另一侧**再拍一张。两张对比就能判断模型正面朝哪边
		# （`look_at` 让模型本地面朝相机的前提是"模型面朝 −Z"，这条前提不该只靠注释相信）。
		await _save_mirrored(entry, "art04_species_second_mirror")

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


# ---------------------------------------------------------------------------
# 客观取景量（ART06）：把展示模型的世界 AABB 投到屏幕，报出包围盒/占比/是否压住 UI。
# 这一段**只测量**，不生成任何结论；画面判断仍以截图 + vision 判读为准。
# ---------------------------------------------------------------------------

## 报左栏、右栏卡片的屏幕边界（从真实控件矩形读，不写死像素）
func _report_layout(entry: MainEntry) -> void:
	if entry.menu == null:
		print("CAP|art04|layout|ERROR|no_menu")
		return
	var left := _find_node(entry.menu, "LeftColumn") as Control
	var right := _find_node(entry.menu, "SpeciesCards") as Control
	var lr := left.get_global_rect() if left != null else Rect2()
	var rr := right.get_global_rect() if right != null else Rect2()
	print("CAP|art04|layout|viewport=%dx%d|left_end=%.0f|right_start=%.0f|gap=%.0f..%.0f" % [
		root.size.x, root.size.y, lr.end.x, rr.position.x, lr.end.x, rr.position.x,
	])


## 展示模型取景量：**脚点/头点投影**（高度取 `SpeciesConfig.capsule_height()`，是配置契约，
## 不是从模型量出来的）。刻意不用网格 AABB：glTF 蒙皮网格的节点 AABB 带骨骼缩放，
## 实测猫 0.31 m 的局部盒投出来只有 0.011 m（`CAP|art04|mesh|` 行），会得出错误结论。
func _report_showcase(entry: MainEntry, tag: String) -> void:
	var cam := entry.menu_camera
	if cam == null:
		print("CAP|art04|%s|showcase|ERROR|no_menu_camera" % tag)
		return
	var nodes := entry.showcase_nodes()
	print("CAP|art04|%s|showcase|count=%d|cam=%s|pos=%s|fov=%.1f|selected=%s" % [
		tag, nodes.size(), cam.name, str(cam.global_position.round()), cam.fov,
		String(entry.menu.selected_species()) if entry.menu != null else "<none>",
	])
	var left_end := 480.0
	var right_start := 828.0
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		var cfg := _config_for_showcase(entry, node)
		var h := cfg.capsule_height() if cfg != null else 0.2
		var feet := node.global_position
		var head := feet + Vector3.UP * h
		var feet_px := cam.unproject_position(feet)
		var head_px := cam.unproject_position(head)
		var px_h := absf(feet_px.y - head_px.y)
		print(("CAP|art04|%s|showcase|%s|id=%s|pos=%s|dist=%.3f"
			+ "|feet=(%.0f,%.0f)|head=(%.0f,%.0f)|px_h=%.0f|h_frac=%.3f|cx=%.0f"
			+ "|in_gap=%s") % [
			tag, node.name, String(cfg.species_id) if cfg != null else "?",
			str(feet.round()), cam.global_position.distance_to(feet),
			feet_px.x, feet_px.y, head_px.x, head_px.y, px_h, px_h / float(root.size.y),
			feet_px.x, str(feet_px.x >= left_end and feet_px.x <= right_start),
		])


## `Showcase_<species_id>` → 对应配置（找不到返回 null，不猜）
func _config_for_showcase(entry: MainEntry, node: Node3D) -> SpeciesConfig:
	var n := String(node.name)
	if not n.begins_with("Showcase_"):
		return null
	var id := n.trim_prefix("Showcase_")
	for cfg in entry.species_configs():
		if String(cfg.species_id) == id:
			return cfg
	return null


func _find_node(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_node(child, target_name)
		if found != null:
			return found
	return null


## 把菜单相机镜像到主视觉的另一侧拍一张，然后**原样还原**（不改生产逻辑，只换取证机位）
func _save_mirrored(entry: MainEntry, tag: String) -> void:
	var cam := entry.menu_camera
	var nodes := entry.showcase_nodes()
	if cam == null or nodes.is_empty():
		print("CAP|art04|%s|ERROR|no_camera_or_showcase" % tag)
		return
	var focus := nodes[0].global_position
	var keep := cam.global_transform
	var delta := cam.global_position - focus
	var up_keep := delta.y
	delta.y = 0.0     # 只镜像水平方位；连高度一起镜像会把相机送进地面以下（实测拍出的是全黑地面）
	cam.global_position = focus - delta + Vector3.UP * up_keep
	cam.look_at(focus + Vector3.UP * 0.18, Vector3.UP)
	await _save(tag)
	cam.global_transform = keep
