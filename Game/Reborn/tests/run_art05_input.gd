extends SceneTree
## ART05 输入链路验证（**引擎内注入**，不是 OS 级按键注入）
##
## 做法：把真实的 `InputEventKey` / `InputEventMouseButton` 送进**引擎自己的输入系统**
## - 键盘：`Input.parse_input_event()` → 真实 InputMap 映射 → Viewport 分发 → `_unhandled_input`
## - 鼠标：`root.push_input()` → 真实 GUI 命中测试 → `Control.gui_input`
## 不出进程、不碰宿主输入队列（项目规则禁止"盲发按键"到别的窗口）。
##
## **必须不加 `--headless`**：无头模式的根视口是 64×64 且没有鼠标进入事件，
## `BaseButton` 靠 `is_hovered()` 才发 `pressed` → 按钮点击一定失败（实测 headless 20 条里挂 2 条）。
## 有窗口时窗口尺寸 = 1280×720，hover/命中都走真实路径。
## 覆盖（ART04/ART05 的菜单链路）：
##   K1 启动进"选物种"、默认选中第一个物种
##   K2 数字键 2 → 选中第二个物种 + 切到物种页（不直接出生）
##   K3 回车 → 出生（物种正确、菜单隐藏、HUD 显示、相机交给玩家）
##   K4 死亡 → 回到菜单，且显示「上一世」
##   M1 鼠标点击卡片 → 选中该物种（真实 GUI 命中）
##   M2 鼠标点击「开始游戏」→ 进物种页（不直接出生）
##   K5 Esc → 回主菜单页（不出生）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_art05_input.gd' --quit-after 30000

const MAIN := "res://scenes/core/main.tscn"
const SETTINGS_TMP := "user://art05_input_settings.cfg"

var _checks := 0
var _fails := 0
var _entry: MainEntry = null


func _initialize() -> void:
	_run()


func _run() -> void:
	_remove(SETTINGS_TMP)
	var packed: PackedScene = load(MAIN)
	if packed == null:
		print("INPUT|ERROR|main.tscn load failed")
		quit(1)
		return
	var main := packed.instantiate()
	if main is MainEntry:
		(main as MainEntry).settings_path = SETTINGS_TMP
	root.add_child(main)
	root.size = Vector2i(1280, 720)
	for i in 8:
		await process_frame

	_entry = main as MainEntry
	if _entry == null or _entry.menu == null:
		print("INPUT|ERROR|main entry/menu missing")
		quit(1)
		return
	var configs := _entry.species_configs()
	if configs.size() < 2:
		print("INPUT|ERROR|need 2 species, got %d" % configs.size())
		quit(1)
		return
	var first := configs[0].species_id
	var second := configs[1].species_id

	# --- K1 ---
	_check("K1_menu_visible", "true", str(_entry.menu.visible), _entry.menu.visible)
	_check("K1_state_selecting", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")
	_check("K1_default_selected", String(first), String(_entry.menu.selected_species()),
		_entry.menu.selected_species() == first)

	# --- K2：数字键 2 只"选中"，不直接出生 ---
	await _tap_physical(KEY_2)
	_check("K2_key_selects_second", String(second), String(_entry.menu.selected_species()),
		_entry.menu.selected_species() == second)
	_check("K2_key_switches_page", "1 (species)", str(_entry.menu.current_page()),
		_entry.menu.current_page() == MainMenu.Page.SPECIES)
	_check("K2_no_spawn_on_select", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")

	# --- K3：回车出生 ---
	await _tap_physical(KEY_ENTER)
	for i in 10:
		await process_frame
	_check("K3_enter_spawns", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")
	_check("K3_spawned_species", String(second),
		String(_entry.player.species_config.species_id) if _entry.player != null else "<none>",
		_entry.player != null and _entry.player.species_config.species_id == second)
	_check("K3_menu_hidden", "false", str(_entry.menu.visible), not _entry.menu.visible)
	_check("K3_hud_visible", "true", str(_entry.hud.visible), _entry.hud.visible)
	var cam := root.get_viewport().get_camera_3d()
	_check("K3_player_camera", "Camera3D", cam.name if cam != null else "<none>",
		cam != null and _entry.player != null and cam == _entry.player.camera)

	# --- K4：死亡 → 回菜单（带「上一世」） ---
	if _entry.player != null and _entry.player.survival != null:
		_entry.player.survival.apply_damage(9999.0, &"art05_input")
	for i in 12:
		await process_frame
	_check("K4_back_to_select", "selecting", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "selecting")
	_check("K4_menu_visible_again", "true", str(_entry.menu.visible), _entry.menu.visible)
	_check("K4_record_text_present", "含 上一世", _entry.status_text(),
		_entry.status_text().contains("上一世"))

	# --- M1：鼠标点击第一个物种的卡片 ---
	var card := _find_node(_entry.menu, "Card_%s" % String(first)) as Control
	if card == null:
		_check("M1_card_found", "Card_%s" % String(first), "<null>", false)
	else:
		var center := card.get_global_rect().get_center()
		await _click(center)
		_check("M1_click_selects", String(first), String(_entry.menu.selected_species()),
			_entry.menu.selected_species() == first)
		_check("M1_click_species_page", "1 (species)", str(_entry.menu.current_page()),
			_entry.menu.current_page() == MainMenu.Page.SPECIES)

	# --- M2：Esc 回主菜单页，再点「开始游戏」只进物种页 ---
	await _tap_physical(KEY_ESCAPE)
	_check("K5_esc_back_to_main", "0 (main)", str(_entry.menu.current_page()),
		_entry.menu.current_page() == MainMenu.Page.MAIN)
	var start := _find_button(_entry.menu, "开始游戏")
	if start == null:
		_check("M2_start_button_found", "开始游戏", "<null>", false)
	else:
		await _click(start.get_global_rect().get_center())
		_check("M2_start_opens_species_page", "1 (species)", str(_entry.menu.current_page()),
			_entry.menu.current_page() == MainMenu.Page.SPECIES)
		_check("M2_start_no_spawn", "selecting", _entry.lifecycle_state_name(),
			_entry.lifecycle_state_name() == "selecting")

	# 收尾：回车真的出生（证明点击之后链路仍然可用）
	await _tap_physical(KEY_ENTER)
	for i in 10:
		await process_frame
	_check("M3_enter_after_click_spawns", "alive", _entry.lifecycle_state_name(),
		_entry.lifecycle_state_name() == "alive")

	_remove(SETTINGS_TMP)
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------------------
# 注入
# ---------------------------------------------------------------------------

## 敲一下物理键（按下 + 松开），走 `Input.parse_input_event` → InputMap → `_unhandled_input`。
## 同时给 `keycode` 与 `physical_keycode`：项目自定义动作按 physical 匹配（WASD / 1 / 2 / Space），
## 内置动作（`ui_accept` / `ui_cancel`）按 keycode 匹配 —— 两个通道都要能命中。
func _tap_physical(physical: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = physical
		ev.physical_keycode = physical
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
		await process_frame


## 点一下某个屏幕坐标（真实 GUI 命中测试）
func _click(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	root.push_input(motion)
	await process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev)
		await process_frame
	await process_frame


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _find_node(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_node(child, target_name)
		if found != null:
			return found
	return null


func _find_button(node: Node, text: String) -> Button:
	var b := node as Button
	if b != null and b.text == text:
		return b
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])
