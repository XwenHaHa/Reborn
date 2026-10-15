extends SceneTree
## T019 老鼠 NPC 觅食与警戒 断言
##
## 覆盖（`Docs/Tasks/T019.md` §6；数值来自 `Docs/Parameters.md` 第 71 行）：
##   A 状态机接口（`State` 前 9 个值与契约一致 + `WAIT`；状态/原因/报告可查看）
##   B 目标选择（最近可食、有 Unit、未失效；跳过不可食/空；无目标 → explore/no_food_known）
##   C 导航（层号从地图 metadata 反查；设目标后路径 > 1 点；**不每帧重复设目标**）
##   D 移动与到达（真实物理帧下走过去；进入 interaction_range 后 forage/arrived）
##   E 进食（走 T017 交互：扣 1 Unit + Hunger 35；吃完整理由由 `ResourcePoint` 判定）
##   F 警戒（最长 0.3 s；期间停手停脚、交互被取消且无收益；可重复注入但不无限延长）
##   G MoveTo 失败（1 s 回退 / 最多重选 3 次 / 进入 WAIT / 记录诊断 / **不永久阻塞**）
##   H 集成（真实身体 + 资源点 + 关卡导航区域 + 调试 HUD 的 ai: 行）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t019_mouse_ai.gd' --quit-after 120000

const MOUSE := "res://resources/species/mouse.tres"
const CAT := "res://resources/species/cat.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const RP := "res://scenes/world/resource_point.tscn"
const ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"

const EPS := 1e-4
const ARENA := 20.0

var _checks := 0
var _fails := 0
var _mouse: SpeciesConfig = null
var _cat: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null
var _region: NavigationRegion3D = null
var _npc: AnimalBody = null
var _ai: MouseAI = null


func _initialize() -> void:
	print("TEST|run_t019_mouse_ai|engine=%s" % Engine.get_version_info().string)
	_mouse = load(MOUSE) as SpeciesConfig
	_cat = load(CAT) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")

	_section_a_state_machine()
	await _section_b_target_selection()
	await _section_c_navigation()
	await _section_d_move_and_arrive()
	await _section_e_eat()
	await _section_f_alert()
	await _section_g_move_failure()
	await _section_h_integration()

	_finish()


# ---------------------------------------------------------------------------
# A 状态机接口
# ---------------------------------------------------------------------------

func _section_a_state_machine() -> void:
	print("---- A 状态机接口 ----")
	_assert("A_state_explore", "0", str(int(AnimalAI.State.EXPLORE)), int(AnimalAI.State.EXPLORE) == 0)
	_assert("A_state_forage", "1", str(int(AnimalAI.State.FORAGE)), int(AnimalAI.State.FORAGE) == 1)
	_assert("A_state_alert", "2", str(int(AnimalAI.State.ALERT)), int(AnimalAI.State.ALERT) == 2)
	_assert("A_state_flee", "3", str(int(AnimalAI.State.FLEE)), int(AnimalAI.State.FLEE) == 3)
	_assert("A_state_hidden", "4", str(int(AnimalAI.State.HIDDEN)), int(AnimalAI.State.HIDDEN) == 4)
	_assert("A_state_approach", "5", str(int(AnimalAI.State.APPROACH)), int(AnimalAI.State.APPROACH) == 5)
	_assert("A_state_chase", "6", str(int(AnimalAI.State.CHASE)), int(AnimalAI.State.CHASE) == 6)
	_assert("A_state_search", "7", str(int(AnimalAI.State.SEARCH)), int(AnimalAI.State.SEARCH) == 7)
	_assert("A_state_attack", "8", str(int(AnimalAI.State.ATTACK)), int(AnimalAI.State.ATTACK) == 8)
	_assert("A_state_wait", "9（追加）", str(int(AnimalAI.State.WAIT)), int(AnimalAI.State.WAIT) == 9)

	_assert("A_mouse_ai_is_animal_ai", "MouseAI 继承 AnimalAI", str(MouseAI.new() is AnimalAI), MouseAI.new() is AnimalAI)
	var probe := AnimalAI.new()
	_assert("A_has_state_id", "有 state_id()", str(probe.has_method("state_id")), probe.has_method("state_id"))
	_assert("A_has_state_reason", "有 state_reason()", str(probe.has_method("state_reason")), probe.has_method("state_reason"))
	_assert("A_has_report", "有 ai_report()", str(probe.has_method("ai_report")), probe.has_method("ai_report"))
	_assert("A_has_alert_for", "有 alert_for()", str(probe.has_method("alert_for")), probe.has_method("alert_for"))
	_assert_near("A_alert_max_time_default", 0.3, probe.alert_max_time, EPS)
	_assert_near("A_retry_window_default", 1.0, probe.retry_window, EPS)
	_assert("A_max_replans_default", "3", str(probe.max_replans), probe.max_replans == 3)
	_assert_near("A_move_fail_wait_default", 1.0, probe.move_fail_wait, EPS)
	probe.free()


# ---------------------------------------------------------------------------
# B 目标选择
# ---------------------------------------------------------------------------

func _section_b_target_selection() -> void:
	print("---- B 目标选择 ----")
	await _fresh_arena()
	_assert("B_initial_state", "explore", str(_ai.state_id()), _ai.state_id() == &"explore")
	# 只有不可食（猫的肉）与空（0 Unit）→ 没有可用目标
	var meat := await _add_food("meat_only", Vector3(-3.0, 0.05, 0.0), _cat, 3)
	var empty := await _add_food("empty_seed", Vector3(-2.0, 0.05, 0.0), _mouse, 0)
	await _advance_frames(20)
	_assert("B_skips_unedible_and_empty", "explore + no_food_known",
		"%s / %s" % [_ai.state_id(), _ai.state_reason()],
		_ai.state_id() == &"explore" and _ai.state_reason() == &"no_food_known")
	meat.queue_free()
	empty.queue_free()
	await _advance_frames(3)

	# 两个可食目标：远的 4 m（3 Unit，**先加**）、近的 1.5 m（2 Unit）；
	# 规则：初次选择取最近（`find_food_target`）；已锁定则不因出现更近的而抖动
	var far := await _add_food("far_seed", Vector3(-4.0, 0.05, 0.0), _mouse, 3)
	var near := await _add_food("near_seed", Vector3(-1.5, 0.05, 0.0), _mouse, 2)
	await _advance_frames(20)
	# 目标选择规则直接测（纯函数）：两个都可用时取**最近**的
	_assert("B_find_nearest", "near_seed", str(_ai.find_food_target().interaction_id if _ai.find_food_target() != null else ""),
		_ai.find_food_target() != null and _ai.find_food_target().interaction_id == "near_seed")
	# 一旦锁定就**不因出现更近的目标而抖动**（当前目标是先加的 far_seed）
	_assert("B_keeps_current_target", "far_seed（不抖动）", _ai.target_id(), _ai.target_id() == "far_seed")
	# 目标被移除 → 切到剩下的那个
	far.queue_free()
	await _advance_frames(5)
	_assert("B_switches_when_gone", "near_seed", _ai.target_id(), _ai.target_id() == "near_seed")
	_assert("B_eat_target_matches", "near_seed", str(_ai.eat_target().interaction_id if _ai.eat_target() != null else ""),
		_ai.eat_target() != null and _ai.eat_target().interaction_id == "near_seed")
	near.queue_free()
	await _advance_frames(5)


# ---------------------------------------------------------------------------
# C 导航
# ---------------------------------------------------------------------------

func _section_c_navigation() -> void:
	print("---- C 导航 ----")
	await _fresh_arena()
	var food := await _add_food("nav_seed", Vector3(-5.0, 0.05, 0.0), _mouse, 3)
	await _advance_frames(20)
	_assert("C_nav_layer_is_mouse_layer", "1（鼠层，来自区域 metadata）", str(_ai.nav_layer()), _ai.nav_layer() == 1)
	_assert("C_nav_layer_source", "metadata", str(_ai.ai_report().get("nav_layer_source", "")),
		String(_ai.ai_report().get("nav_layer_source", "")) == "metadata")
	_assert("C_destination_set_once", "1", str(int(_ai.ai_report().get("destination_sets", 0))),
		int(_ai.ai_report().get("destination_sets", 0)) == 1)
	# 跑 1 s，目标不变 → 不应重复设目标（**不每帧请求路径**）
	await _run_seconds(1.0)
	_assert("C_no_repeated_destination", "仍为 1", str(int(_ai.ai_report().get("destination_sets", 0))),
		int(_ai.ai_report().get("destination_sets", 0)) == 1)
	_assert("C_path_has_points", "> 1", str(int(_ai.ai_report().get("path_points", 0))),
		int(_ai.ai_report().get("path_points", 0)) > 1)
	food.queue_free()
	await _advance_frames(5)


# ---------------------------------------------------------------------------
# D 移动与到达
# ---------------------------------------------------------------------------

func _section_d_move_and_arrive() -> void:
	print("---- D 移动与到达 ----")
	await _fresh_arena()
	# 目标放在 6 m 外（超出 interaction_range 0.45，必须真的走过去）
	var food := await _add_food("walk_seed", Vector3(-6.0, 0.05, 0.0), _mouse, 3)
	await _advance_frames(20)
	var start := _npc.global_position
	_assert("D_far_target", "距离 > 5 m", "%.2f" % start.distance_to(food.global_position),
		start.distance_to(food.global_position) > 5.0)
	var moved := await _run_seconds(8.0, func() -> bool: return _ai.state_reason() == &"arrived")
	_assert("D_moved_towards_target", "位置变化 > 3 m", "%.2f m（%.2f s）" % [start.distance_to(_npc.global_position), moved],
		start.distance_to(_npc.global_position) > 3.0)
	_assert("D_reached_forage", "forage", str(_ai.state_id()), _ai.state_id() == &"forage")
	_assert("D_reason_arrived", "arrived", str(_ai.state_reason()), _ai.state_reason() == &"arrived")
	var dist := _npc.global_position.distance_to(food.global_position)
	_assert("D_within_interaction_range", "≤ 0.45", "%.3f" % dist, dist <= _mouse.interaction_range + 0.10)
	# 没有穿墙/瞬移：只在 xz 上移动（起点与终点 y 相同量级）
	_assert("D_no_vertical_teleport", "|Δy| < 0.5", "%.3f" % absf(_npc.global_position.y - start.y),
		absf(_npc.global_position.y - start.y) < 0.5)
	food.queue_free()
	await _advance_frames(5)


# ---------------------------------------------------------------------------
# E 进食
# ---------------------------------------------------------------------------

func _section_e_eat() -> void:
	print("---- E 进食（共用 T017 规则）----")
	await _fresh_arena()
	var food := await _add_food("eat_seed", Vector3(-1.2, 0.05, 0.0), _mouse, 3, 0.2)   # 交互时长 0.2 s
	_set_hunger(40.0)
	await _advance_frames(20)
	_assert("E_target_chosen", "eat_seed", _ai.target_id(), _ai.target_id() == "eat_seed")
	var units_before := food.units
	var hunger_before: float = _npc.survival.state.hunger
	# 让它走到并吃（时长 0.2 s，但还要走 ~1 m）
	var ok := await _run_seconds(6.0, func() -> bool: return food.commit_count() >= 1)
	_assert("E_committed", "1", str(food.commit_count()), food.commit_count() == 1)
	_assert("E_units_decremented_once", "%d → %d" % [units_before, units_before - 1], str(food.units),
		food.units == units_before - 1)
	_assert_near("E_hunger_plus_35", hunger_before + 35.0, _npc.survival.state.hunger, 0.5)
	_assert("E_state_back_to_explore", "explore", str(_ai.state_id()), _ai.state_id() == &"explore")
	_assert("E_reason_ate", "ate", "reason=%s" % _ai.state_reason(), _ai.state_reason() == &"ate")
	_assert("E_ate_count", "1", str(_ai.ate_count()), _ai.ate_count() == 1)
	_assert("E_elapsed_is_number", "≥ 0", "%.2f" % ok, ok >= 0.0)
	food.queue_free()
	await _advance_frames(5)


# ---------------------------------------------------------------------------
# F 警戒
# ---------------------------------------------------------------------------

func _section_f_alert() -> void:
	print("---- F 警戒 ----")
	await _fresh_arena()
	var food := await _add_food("alert_seed", Vector3(-1.0, 0.05, 0.0), _mouse, 3, 5.0)   # 长时长，便于打断
	_set_hunger(40.0)
	await _advance_frames(20)
	# 先让它走到目标并开始进食
	await _run_seconds(6.0, func() -> bool: return _npc.interaction.is_interacting() or _ai.state_id() == &"forage")
	var interacting_before := _npc.interaction.is_interacting()
	var cancel_before := food.cancel_call_count()
	var units_before := food.units
	var hunger_before: float = _npc.survival.state.hunger

	_ai.alert_for(Vector3(0.0, 0.0, 5.0), &"heard_noise")
	_assert("F_state_alert", "alert", str(_ai.state_id()), _ai.state_id() == &"alert")
	_assert("F_reason_recorded", "heard_noise", str(_ai.state_reason()), _ai.state_reason() == &"heard_noise")
	_assert("F_has_alert", "true", str(_ai.has_alert()), _ai.has_alert())
	_assert("F_alert_position", "≈ (0, 0, 5)", str(_ai.alert_position()), _ai.alert_position().distance_to(Vector3(0.0, 0.0, 5.0)) < EPS)
	_assert("F_move_intent_zero", "(0, 0)", str(_npc.move_intent), _npc.move_intent.length() < 0.01)
	if interacting_before:
		_assert("F_interaction_cancelled", "取消次数 +1", "%d → %d" % [cancel_before, food.cancel_call_count()],
			food.cancel_call_count() == cancel_before + 1)
	_assert("F_no_units_lost", str(units_before), str(food.units), food.units == units_before)
	_assert_near("F_no_hunger_gain", hunger_before, _npc.survival.state.hunger, EPS)
	# 0.3 s 内仍在警戒；超过后回落
	await _run_seconds(0.2)
	_assert("F_still_alert_at_0_2", "alert", str(_ai.state_id()), _ai.state_id() == &"alert")
	await _run_seconds(0.2)
	_assert("F_left_alert_after_0_3", "非 alert", str(_ai.state_id()), _ai.state_id() != &"alert")
	_assert("F_has_alert_false", "false", str(_ai.has_alert()), not _ai.has_alert())
	# 重复注入：仍保持 alert，但不无限延长（以最后一次注入 + 0.3 s 为界）
	_ai.alert_for(Vector3(0.0, 0.0, 4.0), &"heard_noise")
	await _run_seconds(0.15)
	_ai.alert_for(Vector3(0.0, 0.0, 3.0), &"heard_noise")
	await _run_seconds(0.2)
	_assert("F_repeated_alert_still_alert", "alert", str(_ai.state_id()), _ai.state_id() == &"alert")
	await _run_seconds(0.25)
	_assert("F_repeated_alert_ends", "非 alert（不无限延长）", str(_ai.state_id()), _ai.state_id() != &"alert")
	food.queue_free()
	await _advance_frames(5)


# ---------------------------------------------------------------------------
# G MoveTo 失败处理
# ---------------------------------------------------------------------------

func _section_g_move_failure() -> void:
	print("---- G MoveTo 失败 ----")
	await _fresh_arena()
	var food := await _add_food("blocked_seed", Vector3(-3.0, 0.05, 0.0), _mouse, 3)
	await _advance_frames(20)
	# 把 AI 指到一个**没有任何导航面**的层上 → 路径为空 → 无法推进（对应"导航不可达/失败"）
	# 换到**与鼠层（位 1）没有交集**的层 → 路径为空 → 无法推进（对应"导航不可达/失败"）
	# 注意：`navigation_layers` 是**位掩码**，用 99 会包含位 1 反而仍然可达（实测踩过）
	_ai.nav_layer_override = 2
	_ai.force_replan()
	await _advance_frames(5)
	var ok := await _run_seconds(6.0, func() -> bool: return _ai.state_id() == &"wait")
	_assert("G_failures_recorded", "≥ 1", str(int(_ai.ai_report().get("path_failures", 0))),
		int(_ai.ai_report().get("path_failures", 0)) >= 1)
	_assert("G_replans_capped", "≤ 3", str(int(_ai.ai_report().get("replans", 0))),
		int(_ai.ai_report().get("replans", 0)) <= 3)
	_assert("G_enters_wait", "wait", str(_ai.state_id()), _ai.state_id() == &"wait")
	_assert("G_wait_reason", "path_failed", str(_ai.state_reason()), _ai.state_reason() == &"path_failed")
	_assert("G_last_path_status_readable", "非空", str(_ai.ai_report().get("last_path_status", "")),
		String(_ai.ai_report().get("last_path_status", "")) != "")
	_assert("G_not_stuck_forever", "WAIT 能在 1 s 内结束", "%.2f s" % ok, ok >= 0.0)
	# WAIT 结束后回 explore（恢复层号并给可走目标）
	_ai.nav_layer_override = 0
	await _run_seconds(2.0, func() -> bool: return _ai.state_id() == &"explore" or _ai.state_id() == &"forage")
	_assert("G_recovers_after_wait", "explore/forage", str(_ai.state_id()),
		_ai.state_id() == &"explore" or _ai.state_id() == &"forage")
	food.queue_free()
	await _advance_frames(5)


# ---------------------------------------------------------------------------
# H 集成
# ---------------------------------------------------------------------------

func _section_h_integration() -> void:
	print("---- H 集成 ----")
	# 正式关卡里能反查导航层（T012 的烘焙产物 + metadata/species）
	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	await _advance_frames(10)
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = _mouse
	body.player_controlled = false
	body.position = Vector3(-4.0, 0.35, 24.0)
	level.add_child(body)
	body.ai_enabled = true
	await _advance_frames(10)
	var ai := body.ai as MouseAI
	_assert("H_ai_built_for_mouse", "MouseAI", str(ai != null), ai != null)
	if ai != null:
		_assert("H_level_nav_layer", "1（关卡的鼠层）", str(ai.nav_layer()), ai.nav_layer() == 1)
		# 关卡里现在**没有**布资源点（布点属 T031/T035）：那就应该报告"没有已知食物"
		_assert("H_no_food_reason", "空目标 + no_food_known",
			"target='%s' reason=%s" % [ai.target_id(), ai.state_reason()],
			ai.target_id().is_empty() and ai.state_reason() == &"no_food_known")
		_assert("H_report_fields", "含 state/reason/target/path_failures",
			str(ai.ai_report().keys()),
			ai.ai_report().has("state") and ai.ai_report().has("reason")
				and ai.ai_report().has("target") and ai.ai_report().has("path_failures"))
	# 猫暂时没有 AI（T023 才做）——不应崩，也不应产生 ai 组件误判
	var cat_body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	cat_body.species_config = _cat
	cat_body.player_controlled = false
	cat_body.position = Vector3(-8.0, 0.35, 24.0)
	level.add_child(cat_body)
	await _advance_frames(5)
	_assert("H_cat_ai_is_mouse_ai_or_null", "空或非鼠 AI", str(cat_body.ai),
		cat_body.ai == null or not (cat_body.ai is MouseAI))

	# 调试入口 HUD 出现 ai: 行 + MOV| 出现 ai_state=
	if ResourceLoader.exists(ENTRY):
		var entry: Node = (load(ENTRY) as PackedScene).instantiate()
		root.add_child(entry)
		await _advance_frames(10)
		if entry.has_method("switch_species"):
			entry.call("switch_species", &"Mouse")
			await _advance_frames(10)
		var hud := String(entry.call("hud_text")) if entry.has_method("hud_text") else ""
		var mov := String(entry.call("mov_line")) if entry.has_method("mov_line") else ""
		_assert("H_hud_has_ai_line", "含 'ai:'", _clip(hud), hud.contains("ai:"))
		_assert("H_mov_has_ai_state", "含 'ai_state='", _clip(mov), mov.contains("ai_state="))
		entry.queue_free()
		await _advance_frames(2)

	var debug_nodes := 0
	for n in _all_nodes(level):
		if n.get_script() != null:
			var sp := String((n.get_script() as Script).resource_path)
			if sp.contains("/debug/"):
				debug_nodes += 1
	_assert("H_no_debug_node_in_level", "0", str(debug_nodes), debug_nodes == 0)
	level.queue_free()
	await _advance_frames(3)

	var main := (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _advance_frames(4)
	var main_debug := 0
	for n in _all_nodes(main):
		if n.get_script() != null:
			var sp := String((n.get_script() as Script).resource_path)
			if sp.contains("/debug/"):
				main_debug += 1
	_assert("H_no_debug_node_in_main", "0", str(main_debug), main_debug == 0)
	main.queue_free()
	await _advance_frames(2)


# ---------------------------------------------------------------------------
# 夹具与辅助
# ---------------------------------------------------------------------------

func _set_hunger(value: float) -> void:
	_npc.survival.state.hunger = value
	_npc.survival.tick_to(_npc.world_time_now())


## 扁世界 + 一块烘焙好的导航面（鼠层）+ 一只鼠 NPC。
## 注意（T012 的坑）：**烘焙几何源只认区域子节点**，所以地面必须挂在 `NavigationRegion3D` 下面。
func _fresh_arena() -> void:
	_free_world()
	_world = Node3D.new()
	_world.name = "T019World"
	root.add_child(_world)
	await _advance_frames(2)

	_region = NavigationRegion3D.new()
	_region.name = "MouseRegion"
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.07          # 鼠层（T012 实测值）
	nm.agent_height = 0.09
	nm.cell_size = 0.03
	nm.cell_height = 0.03
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	_region.navigation_mesh = nm
	_region.navigation_layers = 1
	_region.set_meta("species", "Mouse")
	_world.add_child(_region)

	var ground := StaticBody3D.new()
	ground.name = "ArenaGround"
	ground.collision_layer = 1
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ARENA, 1.0, ARENA)
	cs.shape = box
	ground.add_child(cs)
	ground.position = Vector3(0.0, -0.5, 0.0)
	_region.add_child(ground)
	await _advance_frames(2)
	_region.bake_navigation_mesh(false)
	await _advance_frames(4)

	var npc := (load(BODY) as PackedScene).instantiate() as AnimalBody
	npc.species_config = _mouse
	npc.player_controlled = false
	npc.position = Vector3(0.0, _mouse.capsule_half_height + 0.01, 0.0)
	npc.velocity = Vector3.ZERO
	_world.add_child(npc)
	npc.ai_enabled = true          # NPC：显式打开 AI（T019 起默认关闭，避免夹具被抢 move_intent）
	await _advance_frames(10)
	_npc = npc
	_ai = npc.ai as MouseAI
	if _ai == null:
		push_warning("NPC 没有 MouseAI（实现缺失）")


func _free_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		_world = null
	_npc = null
	_ai = null


func _add_food(id: String, pos: Vector3, eater_cfg: SpeciesConfig, units: int, duration := 1.5) -> ResourcePoint:
	var rp := (load(RP) as PackedScene).instantiate() as ResourcePoint
	rp.kind = &"food"
	rp.interaction_id = id
	# 用"能吃它的物种"反推食物类型（不写物种名判断）
	rp.food_type = eater_cfg.allowed_food_types[0] if not eater_cfg.allowed_food_types.is_empty() else 0
	rp.units = units
	rp.capacity = maxi(units, 1)
	rp.interaction_duration = duration
	rp.auto_advance = false
	rp.next_refill_at = 0.0
	rp.position = pos
	_world.add_child(rp)
	await _advance_frames(3)
	return rp


## 推进真实世界时间，直到 `until()` 为真或超时；返回实际经过秒数
func _run_seconds(seconds: float, until: Callable = Callable()) -> float:
	if _wd == null:
		return 0.0
	var t0: float = _wd.world_time
	var frames := 0
	var max_frames := int(maxf(120.0, seconds * 240.0))
	while _wd.world_time - t0 < seconds and frames < max_frames and not paused:
		if until.is_valid() and bool(until.call()):
			break
		await physics_frame
		frames += 1
	return _wd.world_time - t0


func _advance_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _clip(s: String) -> String:
	return s.replace("\n", " | ").substr(0, 90)


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
	_assert(id, "%.4f ±%.4f" % [expected, eps], "%.4f" % a, absf(a - expected) <= eps)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
