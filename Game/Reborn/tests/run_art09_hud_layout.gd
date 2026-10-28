extends SceneTree
## ART09 阶段 D 契约：HUD 四条状态（右侧中部 + 图标）、右下技能环、右上罗盘。
##
## 运行：`godot --headless --path <proj> --script 'res://tests/run_art09_hud_layout.gd' --quit-after 60000`
##
## 纪律：本套件只读 UI 节点与玩家状态，不改任何玩法数据；T018 的
## `Margin/VBox/{VitalLabel,WarningLabel,InteractLabel}` 三条老路径必须继续存在。

const HUD := "res://scenes/ui/hud.tscn"
const BODY := "res://scenes/characters/animal_body.tscn"
const MOUSE_CFG := "res://resources/species/mouse.tres"
const CAT_CFG := "res://resources/species/cat.tres"
const TOL := 2.0

var _checks := 0
var _fails := 0
var _hud: Control = null
var _world: Node3D = null
var _mouse: SpeciesConfig = null
var _cat: SpeciesConfig = null

func _initialize() -> void:
	_run()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_mouse = load(MOUSE_CFG) as SpeciesConfig
	_cat = load(CAT_CFG) as SpeciesConfig
	_check("configs_load", _mouse != null and _cat != null)

	_world = Node3D.new()
	root.add_child(_world)
	_hud = (load(HUD) as PackedScene).instantiate() as Control
	root.add_child(_hud)
	for i in 8:
		await process_frame
	# headless 根视口会在首帧被拉回 64×64：入树后再立一次，布局断言才有意义（ART09-B 实测）
	root.size = Vector2i(1280, 720)
	for i in 6:
		await process_frame

	_check_legacy_paths()
	await _check_vitals_panel()
	await _check_compass()
	await _check_skill_ring()

	_hud.queue_free()
	_world.queue_free()
	for i in 4:
		await process_frame
	_finish()


## T018 的三条路径 + 文字契约不变
func _check_legacy_paths() -> void:
	for name in ["VitalLabel", "WarningLabel", "InteractLabel"]:
		_check("legacy_%s_exists" % name,
			_hud.get_node_or_null("Margin/VBox/%s" % name) != null)
	var vital := _hud.get_node_or_null("Margin/VBox/VitalLabel") as Label
	_check("legacy_vital_label_hidden", vital != null and not vital.visible)
	var text := String(_hud.call("hud_text"))
	_check("hud_text_nonempty", text.length() > 0)
	_check("hud_text_has_vitals", text.contains("生命"))
	_check("hud_methods", _hud.has_method("status_lines") and _hud.has_method("interaction_visible"))


## 四条状态：右侧中部锚点 + 图标 + 名称 + 条 + 数值
func _check_vitals_panel() -> void:
	var box := _hud.get_node_or_null("VitalsBars") as Control
	_check("vitals_panel_exists", box != null)
	if box == null:
		return
	_check("vitals_anchor_right", is_equal_approx(box.anchor_left, 1.0)
		and is_equal_approx(box.anchor_right, 1.0))
	_check("vitals_anchor_vertical_center",
		is_equal_approx(box.anchor_top, 0.5) and is_equal_approx(box.anchor_bottom, 0.5))
	_check("vitals_margin",
		absf(box.offset_right - (-24.0)) <= TOL
		and absf(box.offset_left - (-(210.0 + 24.0))) <= TOL)
	print("LAYOUT|vitals=%.0f,%.0f %.0fx%.0f|viewport=%dx%d" % [
		box.global_position.x, box.global_position.y, box.size.x, box.size.y,
		root.size.x, root.size.y,
	])
	_check("vitals_on_right_half",
		box.global_position.x > float(root.size.x) * 0.5)
	for row in [
		{"key": "health", "name": "生命"},
		{"key": "hunger", "name": "饥饿"},
		{"key": "thirst", "name": "水分"},
		{"key": "stamina", "name": "体力"},
	]:
		var key := String(row["key"])
		var line := _find(box, "Row_%s" % key) as Control
		_check("row_%s_exists" % key, line != null)
		if line == null:
			continue
		var icon := _find(line, "Icon_%s" % key) as Control
		_check("row_%s_icon" % key, icon != null)
		if icon != null:
			_check("row_%s_icon_draws" % key,
				icon.get_signal_connection_list("draw").size() > 0)
		var label := _find(line, "Name_%s" % key) as Label
		_check("row_%s_name" % key,
			label != null and label.text == String(row["name"]))
		_check("row_%s_bar" % key, _find(line, "Bar_%s" % key) is ProgressBar)
		_check("row_%s_value" % key, _find(line, "Value_%s" % key) is Label)


func _check_compass() -> void:
	var compass := _hud.get_node_or_null("Compass") as Control
	_check("compass_exists", compass != null)
	if compass == null:
		return
	_check("compass_top_right",
		is_equal_approx(compass.anchor_left, 1.0)
		and is_equal_approx(compass.anchor_top, 0.0)
		and absf(compass.offset_top - 20.0) <= TOL)
	_check("compass_has_heading_api", compass.has_method("set_heading"))
	_check("compass_does_not_eat_mouse",
		compass.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	# 朝向跟着玩家偏航走：转 90° 后 heading 应等于 −π/2
	var body := await _spawn_body(_cat)
	_hud.call("bind_player", body)
	for i in 4:
		await process_frame
	body.rotation.y = PI * 0.5
	for i in 6:
		await process_frame
	var heading := float(compass.get("heading_rad"))
	print("LAYOUT|compass_heading=%.3f|expected=%.3f" % [heading, -PI * 0.5])
	_check("compass_follows_yaw", absf(wrapf(heading - (-PI * 0.5), -PI, PI)) <= 0.05)
	body.queue_free()
	for i in 2:
		await process_frame


func _check_skill_ring() -> void:
	var ring := _hud.get_node_or_null("SkillRing") as Control
	_check("skill_ring_exists", ring != null)
	if ring == null:
		return
	_check("skill_ring_bottom_right",
		is_equal_approx(ring.anchor_left, 1.0)
		and is_equal_approx(ring.anchor_bottom, 1.0)
		and absf(ring.offset_right - (-24.0)) <= TOL)
	for key in ["sprint", "crouch", "pounce"]:
		var panel := _find(ring, "Skill_%s" % key) as Panel
		_check("skill_%s_exists" % key, panel != null)
		if panel == null:
			continue
		_check("skill_%s_does_not_eat_mouse" % key,
			panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)
		_check("skill_%s_has_glyph" % key, _find(panel, "Glyph") is Label)
		_check("skill_%s_has_hint" % key, _find(panel, "Hint") is Label)

	# 鼠不能扑击 → 扑击按钮转禁用态并标 NOT-AVAILABLE
	var mouse := await _spawn_body(_mouse)
	_hud.call("bind_player", mouse)
	for i in 4:
		await process_frame
	var pounce := _find(ring, "Skill_pounce") as Panel
	var hint := _find(pounce, "Hint") as Label
	print("SKILL|mouse|pounce_hint=%s|tooltip=%s" % [
		hint.text if hint != null else "<null>", pounce.tooltip_text,
	])
	_check("skill_pounce_unavailable_for_mouse",
		hint != null and hint.text == "不可用")
	_check("skill_pounce_marks_not_available",
		pounce.tooltip_text.contains("NOT-AVAILABLE"))
	var sprint_chip := _find(ring, "Skill_sprint") as Panel
	var sprint_hint := _find(sprint_chip, "Hint") as Label
	_check("skill_sprint_hint_kept", sprint_hint != null and sprint_hint.text == "Shift")
	mouse.queue_free()
	for i in 2:
		await process_frame

	# 猫能扑击 → 恢复可用；冲刺按下时高亮成金色
	var cat := await _spawn_body(_cat)
	_hud.call("bind_player", cat)
	for i in 4:
		await process_frame
	var pounce2 := _find(ring, "Skill_pounce") as Panel
	var hint2 := _find(pounce2, "Hint") as Label
	_check("skill_pounce_available_for_cat", hint2 != null and hint2.text == "左键")
	var idle_style := _find(ring, "Skill_sprint").get_theme_stylebox("panel") as StyleBoxFlat
	_check("skill_sprint_idle_not_gold",
		idle_style != null and not _color_close(idle_style.bg_color, Color(0.851, 0.588, 0.227), 0.08))
	cat.want_sprint = true
	for i in 6:
		await process_frame
	var active_style := _find(ring, "Skill_sprint").get_theme_stylebox("panel") as StyleBoxFlat
	print("SKILL|cat|sprint_bg=%s" % str(active_style.bg_color if active_style != null else Color.BLACK))
	_check("skill_sprint_highlights",
		active_style != null and _color_close(active_style.bg_color, Color(0.851, 0.588, 0.227), 0.08))
	_check("skill_no_gameplay_written", not cat.want_crouch and cat.want_pounce == false)
	cat.queue_free()
	for i in 2:
		await process_frame


func _spawn_body(cfg: SpeciesConfig) -> AnimalBody:
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = false
	body.position = Vector3(0.0, cfg.capsule_half_height + 0.05, 0.0)
	_world.add_child(body)
	for i in 4:
		await process_frame
	return body


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
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s" % [label, "PASS" if ok else "FAIL"])


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
