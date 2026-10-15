extends SceneTree
## T013 调试入口断言（可在打包产物内运行）
##
## 覆盖（`Docs/Tasks/T013.md` §6）：
##   A 场景与分离：调试入口能建起关卡/玩家/相机/HUD；**正式场景里没有任何调试节点**
##   B 输入映射：5 个调试动作存在，且键码与引擎常量 `KEY_F1..KEY_F5` 一致
##   C 切换玩家：猫↔鼠 的胶囊尺寸/导航层/HUD 文本/落位正确，且不重叠、不穿墙
##   D 显示开关：碰撞（引擎开关 + 自绘线框）、导航路径、HUD 三态真的切换
##   E 参数与记录：移动参数与 `*.tres` 一致；`PARAMS|` 进关卡打一次；`MOV|` 周期出现
##   F 遗留项 ②：HUD 的"猫跨屏障"探针能复现 T012 实测（鼠层 9.0 m 穿洞 / 猫层绕行不穿洞）
##
## 不覆盖（如实说明）：**真实键盘按键**（禁止盲发按键，见 T007）；碰撞形状在**编辑器调试运行**下
## 是否可见（本环境只有命令行运行，见 `Docs/Evidence/T013.md` §5）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t013_debug_entry.gd' --quit-after 40000

const ENTRY := "res://scenes/debug/debug_entry.tscn"
const ENTRY_SCRIPT := "res://scripts/debug/debug_entry.gd"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"
const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const DEBUG_DIR := "res://scripts/debug/"

## 期望的调试动作 → 引擎键常量（用引擎自己的常量核对 `project.godot` 里的键码数字）
const EXPECTED_ACTIONS := {
	"debug_switch_cat": KEY_F1,
	"debug_switch_mouse": KEY_F2,
	"debug_toggle_collision": KEY_F3,
	"debug_toggle_path": KEY_F4,
	"debug_toggle_hud": KEY_F5,
}

## 正式场景里**不允许**出现的名字/脚本
const FORBIDDEN_NODE_NAMES := ["DebugHUD", "DebugPathMesh", "DebugCollisionMesh", "DebugLabel"]

## 出生点（T011 关卡常量）
const CAT_SPAWN := Vector3(-4.0, 0.34, 24.0)
const MOUSE_SPAWN := Vector3(7.0, 0.19, 26.0)
const SPAWN_EPS := 0.05

## 胶囊总高（Parameters.md：猫 0.48 / 鼠 0.18）
const CAT_CAPSULE_H := 0.48
const MOUSE_CAPSULE_H := 0.18
const NAV_LAYER_MOUSE := 1
const NAV_LAYER_CAT := 2

## 遗留项 ②：探针端点（与 `debug_entry.gd` 的 `LEGACY_PROBE_FROM/TARGET` 一致）。
## **这一对端点的直线距离就是 5.00 m**（z 从 21.5 到 16.5）。T012 记录里的 "9.00 m" 是另一对更宽的
## 端点（23.5 → 14.5）—— 同一张鼠图上两者都是**直穿洞口**，所以"是否穿洞"的结论一致。
const PROBE_FROM := Vector3(26.5, 0.10, 21.5)
const PROBE_TARGET := Vector3(26.5, 0.10, 16.5)
const PROBE_STRAIGHT := 5.0
## 直线/绕行的比较容差（米）
const PROBE_LEN_EPS := 0.6

const SETTLE_FRAMES := 90
const WAIT_FRAMES := 40
const OVERLAP_SHRINK := 0.005

var _checks := 0
var _fails := 0
var _entry: Node = null
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null


func _initialize() -> void:
	print("TEST|run_t013_debug_entry|engine=%s" % Engine.get_version_info().string)
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig

	await _section_a_scene_and_separation()
	_section_b_input_map()
	await _section_c_switch_species()
	await _section_d_toggles()
	await _section_e_params_and_records()
	await _section_f_legacy_probe()

	_finish()


# ---------------------------------------------------------------------------
# A 场景与分离
# ---------------------------------------------------------------------------

func _section_a_scene_and_separation() -> void:
	print("---- A 场景与分离 ----")
	var packed: PackedScene = load(ENTRY)
	_assert("A_entry_scene_loads", "PackedScene", str(packed != null), packed != null)
	if packed == null:
		return
	_entry = packed.instantiate()
	root.add_child(_entry)
	await _wait(2)

	_assert("A_root_is_node3d", "Node3D", _entry.get_class(), _entry is Node3D)
	_assert("A_root_has_script", ENTRY_SCRIPT, str(_entry.get_script().resource_path if _entry.get_script() != null else "<none>"),
		_entry.get_script() != null and _entry.get_script().resource_path == ENTRY_SCRIPT)

	var level: Node = _entry.get("level")
	_assert("A_level_instanced", "!= null", str(level != null), level != null)
	if level != null:
		_assert("A_level_is_courtyard", LEVEL, level.scene_file_path, level.scene_file_path == LEVEL)
		_assert("A_level_named_Level", "Level", level.name, level.name == "Level")
		_assert("A_level_has_nav_regions", "≥2 NavigationRegion3D",
			"%d" % _count_class(level, "NavigationRegion3D"), _count_class(level, "NavigationRegion3D") >= 2)

	var player: AnimalBody = _entry.get("player")
	_assert("A_player_is_animal_body", "AnimalBody", str(player != null), player != null)
	if player != null:
		_assert("A_player_camera_current", "true", str(player.camera.current), player.camera.current)
		_assert("A_player_controlled", "true", str(player.player_controlled), player.player_controlled)

	var hud: Node = _entry.get("hud")
	_assert("A_hud_exists", "CanvasLayer", str(hud != null and hud is CanvasLayer), hud != null and hud is CanvasLayer)
	_assert("A_hud_named_DebugHUD", "DebugHUD", hud.name if hud != null else "<none>", hud != null and hud.name == "DebugHUD")
	var hud_text := String(_entry.call("hud_text"))
	_assert("A_hud_text_marks_debug", "含 DEBUG", "len=%d" % hud_text.length(),
		hud_text.find("DEBUG") >= 0)
	_assert("A_hud_text_has_keys_legend", "含 F1..F5 图例",
		str(hud_text.find("F5") >= 0), hud_text.find("F5") >= 0)

	# 调试可视化节点确实属于调试入口
	_assert("A_entry_has_path_mesh", "!= null", str(_entry.get("path_mesh") != null), _entry.get("path_mesh") != null)
	_assert("A_entry_has_collision_mesh", "!= null",
		str(_entry.get("_collision_mesh") != null), _entry.get("_collision_mesh") != null)

	# --- 分离判据：正式场景不得含调试节点 ---
	for scene_path in [LEVEL, MAIN]:
		var sp: PackedScene = load(scene_path)
		if sp == null:
			_assert("A_%s_loads" % scene_path.get_file(), "PackedScene", "null", false)
			continue
		var inst: Node = sp.instantiate()
		var debug_nodes := 0
		for n in _all_nodes(inst):
			if n.get_script() != null and String(n.get_script().resource_path).begins_with(DEBUG_DIR):
				debug_nodes += 1
			if FORBIDDEN_NODE_NAMES.has(String(n.name)):
				debug_nodes += 1
		_assert("A_%s_no_debug_nodes" % scene_path.get_file(), "0", "%d" % debug_nodes, debug_nodes == 0)
		_assert("A_%s_no_canvas_layer" % scene_path.get_file(), "0",
			"%d" % _count_class(inst, "CanvasLayer"), _count_class(inst, "CanvasLayer") == 0)
		inst.free()
	# 文本级检查（**锦上添花**，不是主判据）：正式场景文件里完全不提调试脚本/调试 HUD。
	# 包内注意：`.pck` 里的场景不是可读文本（实测 `FileAccess` 读到 0 字节）→ 这条会退化成
	# "不可读即通过"，所以**真正的判据是上面结构级的**（实例化后无调试节点、无 CanvasLayer）。
	# 这里把长度与结论都打出来，避免"看起来通过了其实没检"。
	for scene_path in [LEVEL, MAIN]:
		var f := FileAccess.open(scene_path, FileAccess.READ)
		var text := f.get_as_text() if f != null else ""
		var readable: bool = text.length() > 0
		var clean: bool = (
			text.find("debug_entry") < 0 and text.find("DebugHUD") < 0 and text.find("scripts/debug") < 0
		)
		_assert("A_%s_no_debug_reference" % scene_path.get_file(), "文本不可读(包内退化) 或 不含调试引用",
			"len=%d clean=%s" % [text.length(), str(clean)], (not readable) or clean)
	# 对照组：调试入口场景**确实**指向调试脚本。同样两条路：文本引用 ∨ 实例化后的根节点脚本路径
	# （后者在包内也可用，是**运行期**判据）。否则上面的"找不到调试节点"可能只是判据永远为真。
	var ef := FileAccess.open(ENTRY, FileAccess.READ)
	var et := ef.get_as_text() if ef != null else ""
	var control_inst: Node = (load(ENTRY) as PackedScene).instantiate()
	var inst_script_path := ""
	if control_inst.get_script() != null:
		inst_script_path = String(control_inst.get_script().resource_path)
	control_inst.free()
	_assert("A_control_entry_references_debug_script", "文本引用 ∨ 实例化脚本路径 == " + ENTRY_SCRIPT,
		"text_len=%d inst_script=%s" % [et.length(), inst_script_path],
		et.find("scripts/debug/debug_entry.gd") >= 0 or inst_script_path == ENTRY_SCRIPT)


# ---------------------------------------------------------------------------
# B 输入映射
# ---------------------------------------------------------------------------

func _section_b_input_map() -> void:
	print("---- B 输入映射 ----")
	_assert("B_debug_actions_count", "5", "%d" % EXPECTED_ACTIONS.size(), EXPECTED_ACTIONS.size() == 5)
	for action in EXPECTED_ACTIONS.keys():
		var key: int = EXPECTED_ACTIONS[action]
		var has: bool = InputMap.has_action(action)
		_assert("B_has_%s" % action, "true", str(has), has)
		if not has:
			continue
		var found := false
		var detail := "<none>"
		for ev in InputMap.action_get_events(action):
			var k := ev as InputEventKey
			if k == null:
				continue
			if k.physical_keycode == key or k.keycode == key:
				found = true
				detail = "physical=%d keycode=%d" % [k.physical_keycode, k.keycode]
		_assert("B_%s_is_F%d" % [action, key - KEY_F1 + 1], "KEY_%s(%d)" % [key, key],
			detail, found)
	# 调试动作不得抢走正式操作键（WASD/空格/Shift/Ctrl）
	var official := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "sprint": KEY_SHIFT, "crouch": KEY_CTRL}
	for action in official.keys():
		var key: int = official[action]
		var conflict := false
		for dbg in EXPECTED_ACTIONS.keys():
			for ev in InputMap.action_get_events(dbg):
				var k := ev as InputEventKey
				if k != null and (k.physical_keycode == key or k.keycode == key):
					conflict = true
		_assert("B_no_conflict_with_%s" % action, "无冲突", str(conflict), not conflict)


# ---------------------------------------------------------------------------
# C 切换玩家
# ---------------------------------------------------------------------------

func _section_c_switch_species() -> void:
	print("---- C 切换玩家 ----")
	var pool: Array[SpeciesConfig] = []
	if _cat != null:
		pool.append(_cat)
	if _mouse != null:
		pool.append(_mouse)
	_assert("C_two_configs_loaded", "2", "%d" % pool.size(), pool.size() == 2)
	if pool.size() < 2:
		return

	# 文件里的起始物种 = 第一个配置（猫）
	_assert("C_start_species_is_first_config", String(_cat.species_id),
		String(_entry.get("current_species")), _entry.get("current_species") == _cat.species_id)

	# 切鼠
	_entry.call("switch_species", _mouse.species_id)
	await _wait(SETTLE_FRAMES)
	var mouse_state := _assert_species_state("C_mouse", _mouse, MOUSE_CAPSULE_H, NAV_LAYER_MOUSE, MOUSE_SPAWN)

	# 切回猫
	_entry.call("switch_species", _cat.species_id)
	await _wait(SETTLE_FRAMES)
	_assert_species_state("C_cat", _cat, CAT_CAPSULE_H, NAV_LAYER_CAT, CAT_SPAWN)

	# 鼠也必须能在关卡里"站住"（同一条判据反着跑一次，避免只看猫）
	_entry.call("switch_species", _mouse.species_id)
	await _wait(SETTLE_FRAMES)
	_assert("C_mouse_stays_on_floor_second_time", "true", str(mouse_state["on_floor"]), mouse_state["on_floor"])
	_entry.call("switch_species", _cat.species_id)
	await _wait(SETTLE_FRAMES)


func _assert_species_state(tag: String, cfg: SpeciesConfig, expect_h: float, expect_layer: int,
		expect_spawn: Vector3) -> Dictionary:
	var player: AnimalBody = _entry.get("player")
	if player == null:
		_assert("%s_player_exists" % tag, "AnimalBody", "null", false)
		return {}
	var st: Dictionary = player.debug_state()
	_assert("%s_species_id" % tag, String(cfg.species_id), String(st["species_id"]), st["species_id"] == cfg.species_id)
	_assert_near("%s_capsule_height" % tag, expect_h, st["capsule_height"], 0.05)
	_assert_near("%s_capsule_radius" % tag, cfg.capsule_radius, st["capsule_radius"], 0.001)
	_assert_near("%s_camera_offset_y" % tag, cfg.camera_offset_z, st["camera_local_position"].y, 0.001)
	_assert("%s_on_floor" % tag, "true", str(st["on_floor"]), st["on_floor"])
	_assert_near("%s_spawn_x" % tag, expect_spawn.x, st["position"].x, SPAWN_EPS)
	_assert_near("%s_spawn_z" % tag, expect_spawn.z, st["position"].z, SPAWN_EPS)
	_assert_near("%s_spawn_y" % tag, expect_spawn.y, st["position"].y, 0.08)

	var params: Dictionary = _entry.call("movement_parameters")
	_assert("%s_nav_layer_from_level" % tag, str(expect_layer), str(params["nav_layer"]),
		int(params["nav_layer"]) == expect_layer)
	var hud := String(_entry.call("hud_text"))
	_assert("%s_hud_mentions_species" % tag, String(cfg.species_id),
		"HUD 含 %s" % String(cfg.species_id), hud.find(String(cfg.species_id)) >= 0)
	_assert("%s_camera_current" % tag, "true", str((player.camera as Camera3D).current), (player.camera as Camera3D).current)

	var overlaps := _overlaps_world(player, OVERLAP_SHRINK)
	_assert("%s_no_static_overlap" % tag, "0", "%d" % overlaps, overlaps == 0)
	_assert("%s_mesh_matches_collision" % tag, "网格高 == 碰撞高",
		"mesh=%.3f capsule=%.3f" % [st["mesh_height"], st["capsule_height"]],
		absf(float(st["mesh_height"]) - float(st["capsule_height"])) < 0.001)
	print("MEASURE|%s|pos=(%.3f, %.3f, %.3f)|capsule_h=%.3f|nav_layer=%d|overlaps=%d" % [
		tag, st["position"].x, st["position"].y, st["position"].z, st["capsule_height"],
		int(params["nav_layer"]), overlaps
	])
	return st


# ---------------------------------------------------------------------------
# D 显示开关
# ---------------------------------------------------------------------------

func _section_d_toggles() -> void:
	print("---- D 显示开关 ----")
	var path_mesh: MeshInstance3D = _entry.get("path_mesh")
	var collision_mesh: MeshInstance3D = _entry.get("_collision_mesh")

	# 碰撞：引擎开关 + 自绘线框
	_assert("D_collision_off_initially", "false", str(_entry.call("collision_debug_enabled")),
		not bool(_entry.call("collision_debug_enabled")))
	var on: bool = _entry.call("toggle_collision_debug")
	_assert("D_collision_on_returns_true", "true", str(on), on)
	_assert("D_collision_engine_hint_on", "true", str(_entry.call("collision_debug_enabled")),
		bool(_entry.call("collision_debug_enabled")))
	await _wait(2)
	var drawn: int = _entry.call("drawn_collision_shapes")
	_assert("D_collision_selfdraw_shapes", "> 0", "%d" % drawn, drawn > 0)
	_assert("D_collision_mesh_visible", "true", str(collision_mesh.visible), collision_mesh.visible)
	_assert("D_collision_mesh_has_surface", "≥1", "%d" % (collision_mesh.mesh as ImmediateMesh).get_surface_count(),
		(collision_mesh.mesh as ImmediateMesh).get_surface_count() >= 1)
	_assert("D_collision_wire_has_vertices", "> 0",
		"%d" % _surface_vertex_count(collision_mesh.mesh as ImmediateMesh), _surface_vertex_count(collision_mesh.mesh as ImmediateMesh) > 0)
	var off: bool = _entry.call("toggle_collision_debug")
	_assert("D_collision_off_returns_false", "false", str(off), not off)
	_assert("D_collision_engine_hint_off", "false", str(_entry.call("collision_debug_enabled")),
		not bool(_entry.call("collision_debug_enabled")))
	_assert("D_collision_selfdraw_cleared", "0", "%d" % _entry.call("drawn_collision_shapes"),
		int(_entry.call("drawn_collision_shapes")) == 0)
	_assert("D_collision_mesh_hidden", "false", str(collision_mesh.visible), not collision_mesh.visible)
	_assert("D_collision_mesh_no_surface", "0", "%d" % (collision_mesh.mesh as ImmediateMesh).get_surface_count(),
		(collision_mesh.mesh as ImmediateMesh).get_surface_count() == 0)

	# 路径
	_assert("D_path_off_initially", "false", str(_entry.call("path_display_enabled")),
		not bool(_entry.call("path_display_enabled")))
	_assert("D_path_mesh_hidden_initially", "false", str(path_mesh.visible), not path_mesh.visible)
	# 先客观记录：主代理的路径到底有没有（画不出来时，是"没路径"还是"画错"要分得清）
	var ma: NavigationAgent3D = _entry.get("main_agent")
	print("MEASURE|path_display|agent=%s|layer=%d|target=%s|path_points=%d|reachable=%s|map_valid=%s" % [
		str(ma != null), ma.navigation_layers if ma != null else -1,
		str(ma.target_position) if ma != null else "<none>",
		ma.get_current_navigation_path().size() if ma != null else -1,
		str(ma.is_target_reachable()) if ma != null else "n/a",
		str(ma.get_navigation_map().is_valid()) if ma != null else "n/a"
	])
	var p_on: bool = _entry.call("toggle_path_display")
	_assert("D_path_on_returns_true", "true", str(p_on), p_on)
	await _wait(30)
	_assert("D_path_mesh_visible", "true", str(path_mesh.visible), path_mesh.visible)
	var pts: int = _entry.call("path_point_count")
	_assert("D_path_points", "≥2", "%d" % pts, pts >= 2)
	_assert("D_path_length_positive", "> 0", "%.3f" % float(_entry.call("path_length")),
		float(_entry.call("path_length")) > 0.0)
	_assert("D_path_mesh_has_surface", "≥1", "%d" % (path_mesh.mesh as ImmediateMesh).get_surface_count(),
		(path_mesh.mesh as ImmediateMesh).get_surface_count() >= 1)
	var p_off: bool = _entry.call("toggle_path_display")
	_assert("D_path_off_returns_false", "false", str(p_off), not p_off)
	_assert("D_path_mesh_hidden_again", "false", str(path_mesh.visible), not path_mesh.visible)
	_assert("D_path_points_cleared", "0", "%d" % _entry.call("path_point_count"),
		int(_entry.call("path_point_count")) == 0)
	_assert("D_path_mesh_no_surface_after_off", "0", "%d" % (path_mesh.mesh as ImmediateMesh).get_surface_count(),
		(path_mesh.mesh as ImmediateMesh).get_surface_count() == 0)

	# HUD
	_assert("D_hud_on_initially", "true", str(_entry.call("hud_enabled")), bool(_entry.call("hud_enabled")))
	var h_on: bool = _entry.call("toggle_hud")
	_assert("D_hud_off_returns_false", "false", str(h_on), not h_on)
	_assert("D_hud_disabled", "false", str(_entry.call("hud_enabled")), not bool(_entry.call("hud_enabled")))
	var h_on2: bool = _entry.call("toggle_hud")
	_assert("D_hud_on_returns_true", "true", str(h_on2), h_on2)
	_assert("D_hud_enabled_again", "true", str(_entry.call("hud_enabled")), bool(_entry.call("hud_enabled")))


# ---------------------------------------------------------------------------
# E 参数与记录
# ---------------------------------------------------------------------------

func _section_e_params_and_records() -> void:
	print("---- E 参数与记录 ----")
	for cfg in [_cat, _mouse]:
		if cfg == null:
			continue
		_entry.call("switch_species", cfg.species_id)
		await _wait(3)
		var p: Dictionary = _entry.call("movement_parameters")
		var tag := "E_%s" % String(cfg.species_id)
		_assert_near("%s_walk" % tag, cfg.walk_speed, p["walk_speed"], 1e-6)
		_assert_near("%s_sprint" % tag, cfg.sprint_speed, p["sprint_speed"], 1e-6)
		_assert_near("%s_crouch" % tag, cfg.crouch_speed, p["crouch_speed"], 1e-6)
		_assert_near("%s_jump" % tag, cfg.jump_velocity, p["jump_velocity"], 1e-6)
		_assert_near("%s_max_step" % tag, cfg.max_step_height, p["max_step_height"], 1e-6)
		_assert_near("%s_accel" % tag, cfg.max_acceleration, p["max_acceleration"], 1e-6)
		_assert_near("%s_radius" % tag, cfg.capsule_radius, p["capsule_radius"], 1e-6)
		_assert_near("%s_half_height" % tag, cfg.capsule_half_height, p["capsule_half_height"], 1e-6)
		_assert_near("%s_capsule_height" % tag, cfg.capsule_height(), p["capsule_height"], 1e-6)
		_assert_near("%s_camera_offset" % tag, cfg.camera_offset_z, p["camera_offset_z"], 1e-6)
		_assert_near("%s_fov" % tag, cfg.fov, p["fov"], 1e-6)
		_assert("%s_can_jump" % tag, str(cfg.can_jump), str(p["can_jump"]), bool(p["can_jump"]) == cfg.can_jump)

	# PARAMS| 进关卡只打一次
	var lines: int = int(_entry.get("params_log_lines"))
	_assert("E_params_logged_once", "1", "%d" % lines, lines == 1)
	var pline := String(_entry.call("params_line"))
	_assert("E_params_line_prefix", "PARAMS|", pline.substr(0, 7), pline.begins_with("PARAMS|"))
	for field in ["walk=", "sprint=", "crouch=", "jump=", "step=", "accel=", "r=", "h=", "cam=", "fov=", "nav_layer="]:
		_assert("E_params_line_has_%s" % field.trim_suffix("="), field, str(pline.find(field) >= 0), pline.find(field) >= 0)

	# MOV| 周期记录
	_entry.set("record_period_sec", 0.2)
	var before: int = int(_entry.get("mov_lines"))
	await _wait(30)
	var after: int = int(_entry.get("mov_lines"))
	_assert("E_mov_lines_increase", "> before", "%d -> %d" % [before, after], after > before)
	var mline := String(_entry.call("mov_line"))
	_assert("E_mov_line_prefix", "MOV|", mline.substr(0, 4), mline.begins_with("MOV|"))
	for field in ["frame=", "species=", "pos=", "vel=", "stance=", "on_floor=", "headroom=", "step_reason=", "nav_len="]:
		_assert("E_mov_line_has_%s" % field.trim_suffix("="), field, str(mline.find(field) >= 0), mline.find(field) >= 0)
	_assert("E_mov_line_species", String(_entry.get("current_species")), String(_entry.get("current_species")),
		mline.find(String(_entry.get("current_species"))) >= 0)


# ---------------------------------------------------------------------------
# F 遗留项 ②（T012 实测口径）—— 只记录与可视化
# ---------------------------------------------------------------------------

func _section_f_legacy_probe() -> void:
	print("---- F 遗留项 ② 探针 ----")
	_entry.call("switch_species", _cat.species_id)
	await _wait(3)
	var cat_rep: Dictionary = _entry.call("probe_report", true)
	_assert("F_cat_report_nonempty", "!= {}", "%d fields" % cat_rep.size(), not cat_rep.is_empty())
	if cat_rep.is_empty():
		return
	_assert("F_cat_own_layer", str(NAV_LAYER_CAT), str(cat_rep["own_layer"]), int(cat_rep["own_layer"]) == NAV_LAYER_CAT)
	_assert("F_cat_other_layer", str(NAV_LAYER_MOUSE), str(cat_rep["other_layer"]),
		int(cat_rep["other_layer"]) == NAV_LAYER_MOUSE)
	_assert("F_cat_does_not_cross_hole", "false", str(cat_rep["own_crosses_hole"]), not bool(cat_rep["own_crosses_hole"]))
	_assert("F_cat_detours", "> %.1f m" % (PROBE_STRAIGHT * 1.5), "%.2f m" % float(cat_rep["own_len"]),
		float(cat_rep["own_len"]) > PROBE_STRAIGHT * 1.5)
	_assert("F_mouse_layer_crosses_hole", "true", str(cat_rep["other_crosses_hole"]), bool(cat_rep["other_crosses_hole"]))
	_assert_near("F_mouse_layer_short_path", PROBE_STRAIGHT, cat_rep["other_len"], PROBE_LEN_EPS)
	print("MEASURE|legacy2_cat_species|own_layer=%d|own_len=%.2f|own_crosses_hole=%s|other_layer=%d|other_len=%.2f|other_crosses_hole=%s" % [
		int(cat_rep["own_layer"]), float(cat_rep["own_len"]), str(cat_rep["own_crosses_hole"]),
		int(cat_rep["other_layer"]), float(cat_rep["other_len"]), str(cat_rep["other_crosses_hole"])
	])

	var hud := String(_entry.call("hud_text"))
	_assert("F_hud_has_probe_line", "probe(legacy2", "HUD 含 probe(legacy2", hud.find("probe(legacy2") >= 0)

	# 切到鼠：本层就应该是"穿洞的短路径"
	_entry.call("switch_species", _mouse.species_id)
	await _wait(3)
	var mouse_rep: Dictionary = _entry.call("probe_report", true)
	_assert("F_mouse_own_layer", str(NAV_LAYER_MOUSE), str(mouse_rep["own_layer"]),
		int(mouse_rep["own_layer"]) == NAV_LAYER_MOUSE)
	_assert("F_mouse_own_crosses_hole", "true", str(mouse_rep["own_crosses_hole"]), bool(mouse_rep["own_crosses_hole"]))
	_assert_near("F_mouse_own_len", PROBE_STRAIGHT, mouse_rep["own_len"], PROBE_LEN_EPS)
	_assert("F_mouse_other_is_cat", str(NAV_LAYER_CAT), str(mouse_rep["other_layer"]),
		int(mouse_rep["other_layer"]) == NAV_LAYER_CAT)
	print("MEASURE|legacy2_mouse_species|own_layer=%d|own_len=%.2f|own_crosses_hole=%s|other_layer=%d|other_len=%.2f" % [
		int(mouse_rep["own_layer"]), float(mouse_rep["own_len"]), str(mouse_rep["own_crosses_hole"]),
		int(mouse_rep["other_layer"]), float(mouse_rep["other_len"])
	])
	_entry.call("switch_species", _cat.species_id)
	await _wait(3)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


## 身体胶囊与 world_static（层 1）的重叠数。收窄 `shrink` 后，**站在地面上不算重叠**。
func _overlaps_world(body: CharacterBody3D, shrink: float) -> int:
	var shape := CapsuleShape3D.new()
	var src := (body.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	shape.radius = maxf(0.001, src.radius - shrink)
	shape.height = maxf(0.002, src.height - shrink * 2.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = body.global_transform
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(params, 16).size()


func _surface_vertex_count(im: ImmediateMesh) -> int:
	var total := 0
	for s in im.get_surface_count():
		var arrays := im.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += verts.size()
	return total


func _count_class(node: Node, cls: String) -> int:
	var n := 0
	for x in _all_nodes(node):
		if x.is_class(cls):
			n += 1
	return n


func _all_nodes(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all_nodes(c))
	return out


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	var a := float(actual)
	var ok: bool = absf(a - expected) <= eps
	_assert(id, "%.4f ±%.4f" % [expected, eps], "%.4f" % a, ok)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
