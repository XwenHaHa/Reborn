extends SceneTree
## T018 最小 HUD 与调参页 断言
##
## 覆盖（`Docs/Tasks/T018.md` §6）：
##   A 场景与接口（`Control`、不吃输入、三个 Label）
##   B 状态显示：四项指标 + 上限；**信号驱动**更新（掉血/恢复后不手动刷新）
##   C 低值警告：`Hunger/Thirst ≤ 25` 出现、恢复后消失
##   D 交互提示：当前唯一目标（进食 / 饮水）+ 目标 ID；离开范围后隐藏
##   E 交互进度百分比随世界时间变化；提交后回到无目标态
##   F **调试数值不混入最终界面**（12 条禁词）
##   G 只观察不改状态（绑定前后快照一致）
##   H 集成（正式关卡 + 真实身体 + 0 调试节点）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t018_hud.gd' --quit-after 90000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const HUD := "res://scenes/ui/hud.tscn"
const RP := "res://scenes/world/resource_point.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"

const EPS := 1e-4
const TARGET_RADIUS := 0.05

## 正式界面里**不许**出现的调试字样（`Docs/Tasks/T018.md` §6 F）
const DEBUG_FORBIDDEN := [
	"PARAMS|", "MOV|", "nav_points", "nav_layer", "step_climb",
	"probe", "headroom", "wish=", "frame=", "collision_debug", "F1=", "Debug",
]

var _checks := 0
var _fails := 0
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null
var _body: AnimalBody = null
var _hud: PlayerHud = null


func _initialize() -> void:
	print("TEST|run_t018_hud|engine=%s" % Engine.get_version_info().string)
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")

	_section_a_scene()
	await _section_b_status()
	await _section_c_warning()
	await _section_d_interaction_hint()
	await _section_e_progress()
	await _section_f_no_debug_text()
	await _section_g_read_only()
	await _section_h_integration()

	_finish()


# ---------------------------------------------------------------------------
# A 场景与接口
# ---------------------------------------------------------------------------

func _section_a_scene() -> void:
	print("---- A 场景与接口 ----")
	_assert("A_hud_scene_exists", "存在", HUD, ResourceLoader.exists(HUD))
	if not ResourceLoader.exists(HUD):
		return
	var hud := (load(HUD) as PackedScene).instantiate()
	_assert("A_is_control", "Control", hud.get_class(), hud is Control)
	_assert("A_is_player_hud", "PlayerHud", str(hud is PlayerHud), hud is PlayerHud)
	_assert("A_mouse_filter_ignore", "2 (IGNORE)", str((hud as Control).mouse_filter),
		(hud as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_assert("A_visible_by_default", "true", str((hud as Control).visible), (hud as Control).visible)
	for name in ["VitalLabel", "WarningLabel", "InteractLabel"]:
		_assert("A_has_%s" % name, "存在", str(hud.get_node_or_null("Margin/VBox/%s" % name) != null),
			hud.get_node_or_null("Margin/VBox/%s" % name) != null)
	_assert("A_hud_methods", "有 hud_text/status_lines/warning_text/interaction_text",
		"%s/%s/%s/%s" % [hud.has_method("hud_text"), hud.has_method("status_lines"),
			hud.has_method("warning_text"), hud.has_method("interaction_text")],
		hud.has_method("hud_text") and hud.has_method("status_lines")
			and hud.has_method("warning_text") and hud.has_method("interaction_text"))
	_assert("A_unbound_text", "未绑定时非空且不含指标", hud.call("hud_text"), String(hud.call("hud_text")).length() > 0)
	_assert("A_unbound_interaction_hidden", "false", str(hud.call("interaction_visible")),
		not bool(hud.call("interaction_visible")))
	hud.free()


# ---------------------------------------------------------------------------
# B 状态显示（信号驱动）
# ---------------------------------------------------------------------------

func _section_b_status() -> void:
	print("---- B 状态显示 ----")
	await _fresh(_mouse)
	_build_hud()
	var text := _hud.hud_text()
	_assert("B_has_health", "含 100 与 '/'（当前 / 上限）", _clip(text), text.contains("100") and text.contains("/"))
	_assert("B_has_labels", "含生命/饥饿/水分/体力", _clip(text),
		text.contains("生命") and text.contains("饥饿") and text.contains("水分") and text.contains("体力"))
	_assert("B_status_lines_count", "4", str(_hud.status_lines().size()), _hud.status_lines().size() == 4)

	# 掉血走真实路径：`apply_damage` → `survival.changed` → HUD 自己更新（**不手动 refresh**）
	_body.survival.apply_damage(30.0, &"test_damage")
	var t2 := _hud.hud_text()
	_assert("B_health_updated_by_signal", "含 70", _clip(t2), t2.contains("70"))
	_assert("B_health_exact", "70.0", "%.1f" % float(_body.survival.state.health),
		absf(_body.survival.state.health - 70.0) < EPS)
	# 恢复同样走信号
	_body.survival.restore_health(10.0)
	_assert("B_restore_updated", "含 80", _clip(_hud.hud_text()), _hud.hud_text().contains("80"))
	# 饥饿变化（直接改状态 + 发信号，验证 UI 对信号的反应）
	_set_hunger(60.0)
	_assert("B_hunger_updated", "含 60", _clip(_hud.hud_text()), _hud.hud_text().contains("60"))


# ---------------------------------------------------------------------------
# C 低值警告
# ---------------------------------------------------------------------------

func _section_c_warning() -> void:
	print("---- C 低值警告 ----")
	_assert("C_no_warning_initially", "空", "'%s'" % _hud.warning_text(), _hud.warning_text().is_empty())
	_set_hunger(20.0)
	_assert("C_hunger_warning", "含 '饥饿'", "'%s'" % _hud.warning_text(), _hud.warning_text().contains("饥饿"))
	_set_hunger(80.0)
	_assert("C_hunger_warning_cleared", "空", "'%s'" % _hud.warning_text(), _hud.warning_text().is_empty())
	_set_thirst(20.0)
	_assert("C_thirst_warning", "含 '缺水'", "'%s'" % _hud.warning_text(), _hud.warning_text().contains("缺水"))
	_set_hunger(15.0)
	_assert("C_both_warning", "含 '饥饿 + 缺水'", "'%s'" % _hud.warning_text(),
		_hud.warning_text().contains("饥饿") and _hud.warning_text().contains("缺水"))
	_set_hunger(90.0)
	_set_thirst(90.0)
	_assert("C_all_cleared", "空", "'%s'" % _hud.warning_text(), _hud.warning_text().is_empty())
	# 临界值 25 的语义（T015：≤25 触发）
	_set_hunger(25.0)
	_assert("C_at_threshold_warns", "含 '饥饿'（≤25 触发）", "'%s'" % _hud.warning_text(),
		_hud.warning_text().contains("饥饿"))
	_set_hunger(100.0)


# ---------------------------------------------------------------------------
# D 交互提示
# ---------------------------------------------------------------------------

func _section_d_interaction_hint() -> void:
	print("---- D 交互提示 ----")
	_assert("D_hidden_without_target", "false", str(_hud.interaction_visible()), not _hud.interaction_visible())
	var seed_point := await _add_resource("seed_food_1", 0.30, {"food_type": SpeciesConfig.FoodType.SEED})
	var text := _hud.interaction_text()
	_assert("D_visible_with_target", "true", str(_hud.interaction_visible()), _hud.interaction_visible())
	_assert("D_contains_action", "含 '进食'", "'%s'" % text, text.contains("进食"))
	_assert("D_contains_id", "含目标 ID", "'%s'" % text, text.contains("seed_food_1"))
	seed_point.queue_free()
	await _advance_frames(3)
	_assert("D_hidden_after_removal", "false", str(_hud.interaction_visible()), not _hud.interaction_visible())

	# 水点 → 饮水
	var water := await _add_resource("water_1", 0.30, {"kind": "water"})
	var wtext := _hud.interaction_text()
	_assert("D_water_action", "含 '饮水'", "'%s'" % wtext, wtext.contains("饮水"))
	_assert("D_water_id", "含 water_1", "'%s'" % wtext, wtext.contains("water_1"))
	water.queue_free()
	await _advance_frames(3)


# ---------------------------------------------------------------------------
# E 交互进度
# ---------------------------------------------------------------------------

func _section_e_progress() -> void:
	print("---- E 交互进度 ----")
	var food := await _add_resource("timed_food", 0.30,
		{"food_type": SpeciesConfig.FoodType.SEED, "duration": 0.4})
	var det := _body.interaction
	det.detect()
	var started := det.press_interact()
	_assert("E_started", "true", str(started), started)
	# 交互进度必须用**真实世界时间**推进：合成 `tick()` 会被身体的每物理帧 `tick()` 拉回（T016 §5 坑 4）
	var moved := await _run_world_seconds(0.15)
	await _process_frame
	var text := _hud.interaction_text()
	var pct := det.interaction_progress()
	_assert("E_shows_progress_format", "含 '%'", "'%s'" % text, text.contains("%"))
	_assert("E_progress_advanced", "0.2 ~ 0.7", "%.3f（真实推进 %.3f s）" % [pct, moved],
		pct > 0.2 and pct < 0.7)
	# 继续推进到完成（目标时长 0.4 s）
	await _run_world_seconds(0.5)
	await _process_frame
	# 提交后回到"可用提示"态（目标仍在范围内、还剩 Unit）：显示目标 ID 但**不带百分比**
	var back := _hud.interaction_text()
	_assert("E_hint_back_to_available", "含 ID 且不含 %", "'%s'" % back,
		back.contains("timed_food") and not back.contains("%"))
	_assert("E_committed_once", "1", str(food.commit_count()), food.commit_count() == 1)


# ---------------------------------------------------------------------------
# F 调试数值不混入
# ---------------------------------------------------------------------------

func _section_f_no_debug_text() -> void:
	print("---- F 调试数值不混入 ----")
	# 造一个"什么都有"的状态：低值 + 有交互目标
	_set_hunger(20.0)
	_set_thirst(18.0)
	var rp := await _add_resource("dbg_food", 0.30, {"food_type": SpeciesConfig.FoodType.SEED})
	var hud_text := _hud.hud_text()
	for word in DEBUG_FORBIDDEN:
		_assert("F_no_%s" % word.replace("|", "_").replace("=", ""), "不含", _clip(hud_text),
			not hud_text.contains(word))
	_assert("F_text_nonempty", "非空", "%d 字符" % hud_text.length(), hud_text.length() > 0)
	rp.queue_free()
	await _advance_frames(3)
	_set_hunger(100.0)
	_set_thirst(100.0)


# ---------------------------------------------------------------------------
# G 只观察不改状态
# ---------------------------------------------------------------------------

func _section_g_read_only() -> void:
	print("---- G 只观察不改状态 ----")
	var rp := await _add_resource("observe_food", 0.30, {"food_type": SpeciesConfig.FoodType.SEED})
	var state_before: Dictionary = _body.survival.state.to_dictionary()
	var record_before: Dictionary = rp.to_record()
	var units_before := rp.units
	# 绑定/刷新/触发信号全跑一遍
	_hud.unbind()
	_hud.bind_player(_body)
	_hud.refresh()
	_body.survival.changed.emit(_body.survival.state)
	_body.interaction.target_changed.emit(_hud.interaction_text() , true)
	var state_after: Dictionary = _body.survival.state.to_dictionary()
	var record_after: Dictionary = rp.to_record()
	_assert("G_state_unchanged", "字典相等", "%s vs %s" % [str(state_before == state_after), str(state_after)],
		state_before == state_after)
	_assert("G_units_unchanged", str(units_before), str(rp.units), rp.units == units_before)
	_assert("G_record_units_unchanged", "同 before", "%s vs %s" % [record_before.get("units"), record_after.get("units")],
		int(record_before.get("units")) == int(record_after.get("units")))
	_assert("G_no_commit", "0", str(rp.commit_count()), rp.commit_count() == 0)
	_assert("G_still_bound", "true", str(_hud.is_bound()), _hud.is_bound())
	rp.queue_free()
	await _advance_frames(3)


# ---------------------------------------------------------------------------
# H 集成
# ---------------------------------------------------------------------------

func _section_h_integration() -> void:
	print("---- H 集成 ----")
	# 在**正式关卡**上放玩家 + HUD（不改关卡文件，实例化后挂上去）
	var scene := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(scene)
	await _advance_frames(4)
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = _mouse
	body.player_controlled = false
	body.position = Vector3(0.0, _mouse.capsule_half_height + 0.01, 0.0)
	scene.add_child(body)
	await _advance_frames(8)
	var hud := (load(HUD) as PackedScene).instantiate() as PlayerHud
	scene.add_child(hud)
	await _advance_frames(2)
	hud.bind_player(body)
	await _advance_frames(2)
	_assert("H_hud_visible_in_level", "true", str(hud.visible), hud.visible)
	_assert("H_hud_in_tree", "true", str(hud.is_inside_tree()), hud.is_inside_tree())
	_assert("H_hud_text_has_stats", "含 '生命'", _clip(hud.hud_text()), hud.hud_text().contains("生命"))
	_assert("H_bound", "true", str(hud.is_bound()), hud.is_bound())
	var debug_nodes := 0
	for n in _all_nodes(scene):
		if n.get_script() != null:
			var sp := String((n.get_script() as Script).resource_path)
			if sp.contains("/debug/"):
				debug_nodes += 1
	_assert("H_no_debug_node_in_level", "0", str(debug_nodes), debug_nodes == 0)
	for word in DEBUG_FORBIDDEN:
		_assert("H_no_%s" % word.replace("|", "_").replace("=", ""), "不含", _clip(hud.hud_text()),
			not hud.hud_text().contains(word))
	hud.queue_free()
	scene.queue_free()
	await _advance_frames(3)

	# `main.tscn` 也不含调试节点（T013 规则继续成立）
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

## 直接写状态并**手动发一次信号**（`SurvivalController` 没有 setter；这里验证的是"UI 对信号的反应"）
func _set_hunger(value: float) -> void:
	_body.survival.state.hunger = value
	_body.survival.tick_to(_body.world_time_now())
	_body.survival.changed.emit(_body.survival.state)


func _set_thirst(value: float) -> void:
	_body.survival.state.thirst = value
	_body.survival.tick_to(_body.world_time_now())
	_body.survival.changed.emit(_body.survival.state)


func _build_hud() -> void:
	_hud = (load(HUD) as PackedScene).instantiate() as PlayerHud
	_world.add_child(_hud)
	_hud.bind_player(_body)


func _new_flat_world() -> void:
	_free_world()
	_world = Node3D.new()
	_world.name = "T018World"
	root.add_child(_world)
	await _advance_frames(2)
	var sb := StaticBody3D.new()
	sb.name = "T018Ground"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	cs.shape = box
	sb.add_child(cs)
	sb.position = Vector3(0.0, -0.5, 0.0)
	_world.add_child(sb)
	await _advance_frames(2)


func _fresh(cfg: SpeciesConfig) -> AnimalBody:
	await _new_flat_world()
	var body := (load(BODY) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = false
	body.position = Vector3(0.0, cfg.capsule_half_height + 0.01, 0.0)
	body.velocity = Vector3.ZERO
	_world.add_child(body)
	await _advance_frames(8)
	_body = body
	return body


func _free_world() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		_world = null
	_body = null
	_hud = null


func _add_resource(id: String, dist: float, opts: Dictionary = {}) -> ResourcePoint:
	var rp := (load(RP) as PackedScene).instantiate() as ResourcePoint
	if opts.has("kind"):
		rp.kind = StringName(opts["kind"])
	rp.interaction_id = id
	if opts.has("food_type"):
		rp.food_type = int(opts["food_type"])
	if opts.has("duration"):
		rp.interaction_duration = float(opts["duration"])
	rp.auto_advance = false
	rp.next_refill_at = 0.0
	var eye := _eye()
	rp.position = Vector3(0.0, eye.y, eye.z - dist)
	_world.add_child(rp)
	await _advance_frames(3)
	return rp


func _eye() -> Vector3:
	if _body == null:
		return Vector3.ZERO
	var cam = _body.get("camera")
	if cam != null and cam is Camera3D:
		return (cam as Camera3D).global_position
	return _body.global_position


## 推进真实世界时间 `seconds` 秒（暂停时不死等；T014 §6 的坑）
func _run_world_seconds(seconds: float, max_frames := 20000) -> float:
	if _wd == null:
		return 0.0
	var t0: float = _wd.world_time
	var frames := 0
	while _wd.world_time - t0 < seconds and frames < max_frames and not paused:
		await process_frame
		frames += 1
	return _wd.world_time - t0


func _process_frame() -> void:
	await process_frame
	await process_frame


func _clip(s: String) -> String:
	return s.replace("\n", " | ").substr(0, 90)


func _advance_frames(n: int) -> void:
	for i in n:
		await physics_frame


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


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
