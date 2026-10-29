extends SceneTree
## ART09-F1 契约：物种**肖像图**（引擎渲染）是否真的进了配置，并被菜单/物种页用上。
##
## 运行：`godot --headless --path <proj> --script 'res://tests/run_art09_portrait_contract.gd' --quit-after 60000`

const MAIN := "res://scenes/core/main.tscn"
const PORTRAIT_DIR := "res://assets/ui/portraits"

var _checks := 0
var _fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load(MAIN) as PackedScene
	_check("main_scene_loads", packed != null)
	if packed == null:
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	root.size = Vector2i(1280, 720)
	for i in 4:
		await process_frame
	var entry := main as MainEntry
	_check("entry_ready", entry != null and entry.menu != null)
	if entry == null or entry.menu == null:
		_finish()
		return
	var menu := entry.menu
	var configs := entry.species_configs()
	_check("species_present", configs.size() >= 2)

	# 配置层：有肖像就必须是方形大图；没有则允许回退 3D 预览
	for cfg in configs:
		var tag := String(cfg.species_id)
		if cfg.display_portrait != null:
			var size := cfg.display_portrait.get_size()
			_check("portrait_%s_square" % tag, absf(size.x - size.y) <= 1.0)
			_check("portrait_%s_big_enough" % tag, size.x >= 256)
			print("PORTRAIT_CONTRACT|%s|%dx%d" % [tag, size.x, size.y])
		else:
			_check("portrait_%s_or_fallback" % tag, _find(menu, "Thumb_%s" % tag) != null)

	# 右栏卡片：有肖像时，缩略图槽里应是 `Portrait_*` TextureRect，且贴图就是配置里的那张
	for cfg in configs:
		var tag := String(cfg.species_id)
		var thumb := _find(menu, "Thumb_%s" % tag) as Control
		_check("card_thumb_%s" % tag, thumb != null)
		if thumb == null:
			continue
		var tex := _find(thumb, "Portrait_%s" % tag) as TextureRect
		if cfg.display_portrait != null:
			_check("card_uses_portrait_%s" % tag, tex != null)
			if tex != null:
				_check("card_portrait_texture_%s" % tag, tex.texture == cfg.display_portrait)
		else:
			_check("card_fallback_preview_%s" % tag,
				_find(thumb, "Preview_%s" % tag) != null)

	# 物种页：缩略图行 + 大卡背景
	menu.show_page(MainMenu.Page.SPECIES)
	for i in 4:
		await process_frame
	var cfg0 := menu.selected_config()
	for cfg in configs:
		var tag := String(cfg.species_id)
		var slot := _find(menu, "Strip_%s" % tag) as Control
		_check("strip_%s" % tag, slot != null)
		if slot == null:
			continue
		var portrait := _find(slot, "Portrait_%s" % tag) as TextureRect
		if cfg.display_portrait != null:
			_check("strip_uses_portrait_%s" % tag, portrait != null)
	var card := menu.get_node_or_null("SpeciesCard") as Panel
	_check("species_card_exists", card != null)
	if card != null:
		var bg := _find(card, "CardPortrait") as TextureRect
		_check("card_portrait_bg_exists", bg != null)
		if bg != null and cfg0 != null:
			_check("card_portrait_bg_texture", bg.texture == cfg0.display_portrait)
			_check("card_portrait_bg_visible", bg.visible == (cfg0.display_portrait != null))
			# 背景必须压暗，否则会盖住卡内文字
			_check("card_portrait_bg_dimmed", bg.modulate.a <= 0.4)
	menu.show_page(MainMenu.Page.MAIN)
	for i in 2:
		await process_frame

	# 产物目录必须有文件（防止"配置指向不存在的图"）
	var dir := DirAccess.open(PORTRAIT_DIR)
	_check("portrait_dir_exists", dir != null)
	if dir != null:
		var count := 0
		dir.list_dir_begin()
		var entry_name := dir.get_next()
		while entry_name != "":
			if entry_name.ends_with(".png"):
				count += 1
			entry_name = dir.get_next()
		dir.list_dir_end()
		print("PORTRAIT_CONTRACT|files=%d" % count)
		_check("portrait_files_present", count >= 2)

	main.queue_free()
	for i in 3:
		await process_frame
	_finish()


func _find(node: Node, target: String) -> Node:
	if node == null:
		return null
	if node.name == target:
		return node
	for child in node.get_children():
		var found := _find(child, target)
		if found != null:
			return found
	return null


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s" % [label, "PASS" if ok else "FAIL"])


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
