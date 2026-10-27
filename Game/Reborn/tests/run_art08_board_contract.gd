extends SceneTree
## ART08 展板菜单契约。基线阶段预期报告当前布局缺少的目标节点。

const MAIN := "res://scenes/core/main.tscn"
var _checks := 0
var _fails := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	var packed := load(MAIN) as PackedScene
	_check("main_scene_loads", packed != null)
	if packed == null:
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	var entry := main as MainEntry
	_check("menu_exists", entry != null and entry.menu != null)
	if entry == null or entry.menu == null:
		_finish()
		return
	_check("main_page_exists", _find(entry.menu, "MainButtons") != null)
	_check("species_page_exists", _find(entry.menu, "SpeciesButtons") != null)
	_check("left_panel_exists", entry.menu.get_node_or_null("LeftPanel") != null)
	_check("species_rail_exists", entry.menu.get_node_or_null("SpeciesRail") != null)
	_check("menu_camera_exists", entry.menu_camera != null)
	_check("menu_fill_exists", entry.menu_fill != null)
	_check("default_cat", String(entry.menu.selected_species()) == "Cat")
	print("LAYOUT|viewport=%dx%d|left_panel=%s|species_rail=%s" % [
		root.size.x, root.size.y,
		str(entry.menu.get_node_or_null("LeftPanel") != null),
		str(entry.menu.get_node_or_null("SpeciesRail") != null),
	])
	main.queue_free()
	_finish()

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
