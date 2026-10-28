extends SceneTree
## ART09 阶段 C 契约：物种选择页按展板重排（左侧大卡 + 四条状态 + 底部缩略图行 + 金色开始按钮）。
##
## 运行：`godot --headless --path <proj> --script 'res://tests/run_art09_species_layout.gd' --quit-after 60000`

const MAIN := "res://scenes/core/main.tscn"
const TOL := 2.0

var _checks := 0
var _fails := 0

func _initialize() -> void:
	_run()


func _run() -> void:
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
	root.size = BoardTokens.DESIGN
	for i in 6:
		await process_frame
	var entry := main as MainEntry
	_check("entry_and_menu_ready", entry != null and entry.menu != null)
	if entry == null or entry.menu == null:
		_finish()
		return
	var menu := entry.menu

	menu.show_page(MainMenu.Page.SPECIES)
	for i in 6:
		await process_frame
	_check_card(menu, entry)
	_check_strip(menu, entry)
	await _check_selection_switch(menu, entry)
	_check_back_to_main(menu)
	await _check_narrow(menu)

	main.queue_free()
	for i in 4:
		await process_frame
	_finish()


func _check_card(menu: MainMenu, entry: MainEntry) -> void:
	var card := menu.get_node_or_null("SpeciesCard") as Panel
	_check("species_card_exists", card != null)
	_check("species_card_visible", card != null and card.visible)
	# 展板的物种选择界面没有右栏、没有 MVP 说明、没有主菜单标题栏
	var rail := menu.get_node_or_null("SpeciesRail") as Control
	var mvp := _find(menu, "MvpNote") as Control
	var left := menu.get_node_or_null("LeftPanel") as Control
	_check("rail_hidden_on_species", rail != null and not rail.visible)
	_check("mvp_note_hidden_on_species", mvp != null and not mvp.visible)
	_check("left_panel_hidden_on_species", left != null and not left.visible)
	var shade := menu.get_node_or_null("RightRailShade") as Control
	_check("rail_shade_hidden_on_species", shade != null and not shade.visible)
	if card == null:
		return
	_check("species_card_width", absf(card.size.x - BoardTokens.SPECIES_CARD_W) <= TOL)
	_check("species_card_height", absf(card.size.y - BoardTokens.SPECIES_CARD_H) <= TOL)
	_check("species_card_inside_viewport",
		card.global_position.x >= -TOL
		and card.global_position.x + card.size.x <= float(root.size.x) + TOL
		and card.global_position.y + card.size.y <= float(root.size.y) + TOL)
	print("LAYOUT|species_card=%.0f,%.0f %.0fx%.0f" % [
		card.global_position.x, card.global_position.y, card.size.x, card.size.y,
	])

	var cfg := menu.selected_config()
	_check("selected_config_present", cfg != null)
	if cfg == null:
		return
	var name_label := _find(card, "CardName") as Label
	_check("card_name_matches_config",
		name_label != null and name_label.text == cfg.display_title())
	var tagline := _find(card, "CardTagline") as Label
	_check("card_tagline_matches_config",
		tagline != null and tagline.text == cfg.display_tagline)
	var note := _find(card, "CardNote") as Label
	_check("card_note_matches_config",
		note != null and note.text == cfg.display_note)

	# 四条状态：进度条上限 = 该物种的生存上限，数值文本同源
	var maxima := {
		"health": cfg.max_health,
		"hunger": cfg.max_hunger,
		"thirst": cfg.max_thirst,
		"stamina": cfg.max_stamina,
	}
	for key in maxima.keys():
		var row := _find(card, "Vital_%s" % key) as Control
		_check("vital_%s_exists" % key, row != null)
		if row == null:
			continue
		var bar := _find(row, "Bar") as ProgressBar
		var value := _find(row, "Value") as Label
		var top := float(maxima[key])
		_check("vital_%s_max" % key, bar != null and is_equal_approx(bar.max_value, top))
		_check("vital_%s_full_at_start" % key, bar != null and is_equal_approx(bar.value, top))
		_check("vital_%s_value_text" % key,
			value != null and value.text == "%d / %d" % [int(top), int(top)])

	# 金色开始按钮在卡内（展板把开局按钮放在大卡底部）
	var enter := _find(card, "EnterButton") as Button
	_check("enter_button_in_card", enter != null)
	if enter != null:
		_check("enter_button_text", enter.text == "开始游戏")
		_check("enter_button_size",
			enter.custom_minimum_size.is_equal_approx(Vector2(BoardTokens.BUTTON_W, BoardTokens.BUTTON_H)))
		var style := enter.get_theme_stylebox("normal") as StyleBoxFlat
		_check("enter_button_is_gold",
			style != null and _color_close(style.bg_color, BoardTokens.GOLD, 0.05))
	_check("back_button_in_card", _find(card, "BackButton") != null)


func _check_strip(menu: MainMenu, entry: MainEntry) -> void:
	var strip := _find(menu, "SpeciesStrip") as Control
	_check("strip_exists", strip != null)
	if strip == null:
		return
	var configs := entry.species_configs()
	for cfg in configs:
		var slot := _find(strip, "Strip_%s" % String(cfg.species_id)) as Control
		_check("strip_%s_exists" % String(cfg.species_id), slot != null)
		if slot != null:
			_check("strip_%s_size" % String(cfg.species_id),
				absf(slot.custom_minimum_size.x - BoardTokens.STRIP_SLOT) <= TOL)
			_check("strip_%s_clickable" % String(cfg.species_id),
				slot.mouse_filter == Control.MOUSE_FILTER_STOP)
	var locked := 0
	for name in ["兔", "鸟", "狐"]:
		var slot := _find(strip, "StripLocked_%s" % name) as Control
		_check("strip_locked_%s_exists" % name, slot != null)
		if slot != null:
			locked += 1
			_check("strip_locked_%s_not_clickable" % name,
				slot.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("strip_locked_count", locked == 3)
	_check("strip_total_slots", strip.get_child_count() == configs.size() + 3)
	print("LAYOUT|strip_slots=%d|configs=%d|locked=%d" % [
		strip.get_child_count(), configs.size(), locked,
	])


## 换选中物种：卡内文字、四条状态、缩略图高亮都要跟着变，且停在物种页（不触发出生）
func _check_selection_switch(menu: MainMenu, entry: MainEntry) -> void:
	var configs := entry.species_configs()
	if configs.size() < 2:
		_check("two_species_available", false)
		return
	var other := configs[1]
	menu.select_species(other.species_id)
	for i in 4:
		await process_frame
	var card := menu.get_node_or_null("SpeciesCard") as Panel
	var name_label := _find(card, "CardName") as Label
	_check("switch_updates_card_name",
		name_label != null and name_label.text == other.display_title())
	_check("switch_stays_on_species_page", menu.current_page() == MainMenu.Page.SPECIES)
	var bar_row := _find(card, "Vital_health") as Control
	var bar := _find(bar_row, "Bar") as ProgressBar
	_check("switch_updates_health_max",
		bar != null and is_equal_approx(bar.max_value, other.max_health))
	var strip := _find(menu, "SpeciesStrip") as Control
	var slot := _find(strip, "Strip_%s" % String(other.species_id)) as Control
	var style: StyleBoxFlat = null
	if slot != null:
		style = slot.get_theme_stylebox("panel") as StyleBoxFlat
	_check("switch_highlights_strip_slot", style != null and style.border_width_left == 2)


func _check_back_to_main(menu: MainMenu) -> void:
	menu.show_page(MainMenu.Page.MAIN)
	var card := menu.get_node_or_null("SpeciesCard") as Control
	var rail := menu.get_node_or_null("SpeciesRail") as Control
	var left := menu.get_node_or_null("LeftPanel") as Control
	_check("card_hidden_on_main", card != null and not card.visible)
	_check("rail_visible_on_main", rail != null and rail.visible)
	_check("left_panel_visible_on_main", left != null and left.visible)


## 960×540：大卡要落在视口内，且不与右栏重叠（右栏在物种页本就隐藏）
func _check_narrow(menu: MainMenu) -> void:
	menu.show_page(MainMenu.Page.SPECIES)
	root.size = Vector2i(960, 540)
	for i in 8:
		await process_frame
	var card := menu.get_node_or_null("SpeciesCard") as Control
	if card == null:
		_check("narrow_card_exists", false)
		return
	print("LAYOUT|narrow=%dx%d|card=%.0f,%.0f %.0fx%.0f" % [
		root.size.x, root.size.y,
		card.global_position.x, card.global_position.y, card.size.x, card.size.y,
	])
	_check("narrow_card_inside_viewport",
		card.global_position.x + card.size.x <= float(root.size.x) + TOL
		and card.global_position.y + card.size.y <= float(root.size.y) + TOL)
	root.size = BoardTokens.DESIGN
	for i in 4:
		await process_frame


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


func _color_close(a: Color, b: Color, tol: float) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol \
		and absf(a.b - b.b) <= tol and absf(a.a - b.a) <= tol


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s" % [label, "PASS" if ok else "FAIL"])


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
