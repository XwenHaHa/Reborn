extends SceneTree
## ART09 阶段 B 契约：菜单是否真的按展板栅格排（左栏 / 中央主视觉 / 右栏），
## 以及展板元素是否齐全（书法标题、金色主按钮 + chevron、照片式物种卡、MVP 说明、更多物种）。
##
## 运行：`godot --headless --path <proj> --script 'res://tests/run_art09_menu_contract.gd' --quit-after 60000`

const MAIN := "res://scenes/core/main.tscn"
const TOL := 2.0

var _checks := 0
var _fails := 0

func _initialize() -> void:
	_run()


func _run() -> void:
	# headless 的根视口默认是 64×64，必须先按设计分辨率立起来再量布局
	root.size = BoardTokens.DESIGN
	var packed := load(MAIN) as PackedScene
	_check("main_scene_loads", packed != null)
	if packed == null:
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	for i in 12:
		await process_frame
	# 入树后再立一次：headless 的根视口会在首帧被拉回 64×64，早设无效（实测）
	root.size = BoardTokens.DESIGN
	for i in 6:
		await process_frame
	var entry := main as MainEntry
	_check("entry_and_menu_ready", entry != null and entry.menu != null)
	if entry == null or entry.menu == null:
		_finish()
		return
	var menu := entry.menu
	await _check_layout(menu, entry)
	await _check_responsive(menu)
	main.queue_free()
	for i in 4:
		await process_frame
	_finish()


func _check_layout(menu: MainMenu, entry: MainEntry) -> void:
	# --- 三段栅格 ---
	var left := menu.get_node_or_null("LeftPanel") as Control
	var rail := menu.get_node_or_null("SpeciesRail") as Control
	_check("left_panel_exists", left != null)
	_check("species_rail_exists", rail != null)
	if left == null or rail == null:
		return
	var rail_left := BoardTokens.rail_left(float(root.size.x))
	_check("left_panel_width", absf(left.size.x - BoardTokens.LEFT_WIDTH) <= TOL)
	_check("rail_left_edge", absf(rail.global_position.x - rail_left) <= TOL)
	_check("rail_width", absf(rail.size.x - BoardTokens.RAIL_WIDTH) <= TOL)
	print("LAYOUT|viewport=%dx%d|left=%.0f..%.0f|center=%.0f..%.0f|rail=%.0f..%.0f" % [
		root.size.x, root.size.y,
		left.global_position.x, left.global_position.x + left.size.x,
		BoardTokens.LEFT_WIDTH, rail_left,
		rail.global_position.x, rail.global_position.x + rail.size.x,
	])
	_check("left_before_rail",
		left.global_position.x + left.size.x <= rail.global_position.x)
	_check("menu_camera_kept", entry.menu_camera != null)
	_check("menu_fill_kept", entry.menu_fill != null)

	# --- 展板标题块 ---
	var title := _find(menu, "TitleCalligraphy") as Label
	_check("title_calligraphy_exists", title != null)
	if title != null:
		var font := title.get_theme_font("font")
		_check("title_uses_system_font", font is SystemFont)
		_check("title_font_size", title.get_theme_font_size("font_size") == BoardTokens.FONT_TITLE)
	_check("title_latin_exists", _find(menu, "TitleLatin") != null)
	_check("title_rule_exists", _find(menu, "TitleRule") != null)
	_check("mvp_note_exists", _find(menu, "MvpNote") != null)

	# --- 左栏按钮：金色主按钮 + chevron，尺寸取自令牌 ---
	var start := _find(menu, "StartButton") as Button
	_check("start_button_exists", start != null)
	if start != null:
		_check("start_button_size",
			start.custom_minimum_size.is_equal_approx(Vector2(BoardTokens.BUTTON_W, BoardTokens.BUTTON_H)))
		_check("start_button_chevron", start.get_node_or_null("Chevron") != null)
	_check("species_button_exists", _find(menu, "SpeciesButton") != null)
	_check("settings_button_exists", _find(menu, "SettingsButton") != null)
	_check("quit_button_exists", _find(menu, "QuitButton") != null)

	# --- 右栏：可玩卡（照片式版式）+ 未来卡 + 底部一行 ---
	var configs := entry.species_configs()
	var cards_box := _find(menu, "SpeciesCards") as Control
	_check("cards_box_exists", cards_box != null)
	for cfg in configs:
		var card := _find(menu, "Card_%s" % String(cfg.species_id)) as Control
		_check("card_%s_exists" % String(cfg.species_id), card != null)
		if card == null:
			continue
		_check("card_%s_height" % String(cfg.species_id),
			absf(card.custom_minimum_size.y - BoardTokens.CARD_H) <= TOL)
		var thumb := _find(card, "Thumb_%s" % String(cfg.species_id)) as Control
		_check("card_%s_thumb" % String(cfg.species_id),
			thumb != null and absf(thumb.custom_minimum_size.x - BoardTokens.THUMB) <= TOL)
		_check("card_%s_has_tagline_note" % String(cfg.species_id),
			_find(card, "Tagline") != null and _find(card, "Note") != null)
	var locked := 0
	for name in ["兔", "鸟", "狐"]:
		var node := _find(menu, "Locked_%s" % name) as Control
		_check("locked_%s_exists" % name, node != null)
		if node != null:
			locked += 1
			_check("locked_%s_not_clickable" % name,
				node.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("locked_cards_count", locked == 3)
	_check("rail_footer_exists", _find(menu, "RailFooter") != null)

	# --- 数据驱动没被破坏 ---
	_check("default_species_cat", String(menu.selected_species()) == "Cat")
	menu.show_page(MainMenu.Page.SPECIES)
	await process_frame
	_check("species_page_switchable", menu.current_page() == MainMenu.Page.SPECIES)
	menu.show_page(MainMenu.Page.MAIN)
	await process_frame


## 960×540：窄视口下左栏与右栏不许重叠（展板版式要么收缩要么换行，不许互相压）
func _check_responsive(menu: MainMenu) -> void:
	root.size = Vector2i(960, 540)
	for i in 6:
		await process_frame
	var left := menu.get_node_or_null("LeftPanel") as Control
	var rail := menu.get_node_or_null("SpeciesRail") as Control
	if left == null or rail == null:
		_check("responsive_nodes", false)
		return
	print("LAYOUT|narrow=%dx%d|left_right=%.0f|rail_left=%.0f" % [
		root.size.x, root.size.y,
		left.global_position.x + left.size.x, rail.global_position.x,
	])
	_check("narrow_no_overlap",
		left.global_position.x + left.size.x <= rail.global_position.x + TOL)
	root.size = Vector2i(1280, 720)
	for i in 4:
		await process_frame


func _find(node: Node, target: String) -> Node:
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
