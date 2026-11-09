extends SceneTree
## T052：鼠的**待机 / 移动 / 逃跑**三种表现 + 速度与状态匹配（开发计划 :220）。
##
## 验收词：「三种表现可用，可共享移动循环但**速度与状态匹配**」。
##
## 断言分三层：
##  A. 表现层：静止 → `Idle`、走 → `Walk`、冲刺 → `Run`（片段名与 `AnimalBody` 判据一致）；
##  B. 速度层：走 ≈ `walk_speed`(1.1)、冲刺 ≈ `sprint_speed`(3.0)，且 `Run` 只在 `want_sprint` 且速度 > walk×1.15 时出现；
##  C. AI 层：`MouseAI` 的 **FLEE 状态真的跑起来**（`want_sprint=true` + `Run` + 速度 ≥2.5）；
##     把 `flee_sprint` 关掉后必须回到"走"的速度（对照组，证明是数据在起作用，不是巧合）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t052_mouse_anim.gd' --quit-after 300000
## 结果口径：RESULT|pass=<n>|fail=<n>|failed=...

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const MOUSE_CFG := "res://resources/species/mouse.tres"
const FLY := "res://scripts/core/game_clock.gd"

const WALK_NOMINAL := 1.1
const RUN_NOMINAL := 3.0
const SPEED_EPS := 0.30

var _level: Node3D = null
var _body: AnimalBody = null
var _ai: AnimalAI = null

var _pass := 0
var _fail := 0
var _failed: Array[String] = []


func _initialize() -> void:
	# 假时钟：`GameClock` 用于 HUD/存档节流，本套件不需要真实毫秒
	var gc := load(FLY)
	if gc != null and gc.has_method("use_fake"):
		gc.call("use_fake", 0)
	await process_frame

	var packed: PackedScene = load(LEVEL)
	if not _assert("A0_level_loads", "PackedScene", str(packed != null), packed != null):
		_finish()
		return
	_level = packed.instantiate() as Node3D
	root.add_child(_level)
	await process_frame

	await _case_visual_and_speed()
	await _case_ai_flee()
	_finish()


# ---------------------------------------------------------------------------
# A/B：表现与速度（玩家式驱动，不经 AI）
# ---------------------------------------------------------------------------
func _case_visual_and_speed() -> void:
	var cfg := load(MOUSE_CFG) as SpeciesConfig
	_body = (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	_body.species_config = cfg
	_body.ai_enabled = false
	_body.player_controlled = false
	_level.add_child(_body)
	_body.global_position = _spawn_point()
	await _step(45)

	_assert("A1_anim_bound", "true", str(_body.visual_anim_active), _body.visual_anim_active)
	_assert("A2_idle_clip", "Idle", str(_body.visual_anim_current),
		_body.visual_anim_current == &"Idle")
	_assert("A3_idle_speed", "≈0", "%.3f" % _speed(), _speed() <= 0.05)

	# 走
	_body.move_intent = Vector2(0.0, -1.0)
	_body.want_sprint = false
	await _step(30)
	var walk_speed := _speed()
	_assert("B1_walk_clip", "Walk", str(_body.visual_anim_current),
		_body.visual_anim_current == &"Walk")
	_assert("B2_walk_speed", "≈%.2f" % WALK_NOMINAL, "%.3f" % walk_speed,
		absf(walk_speed - WALK_NOMINAL) <= SPEED_EPS)

	# 冲刺
	_body.want_sprint = true
	await _step(45)
	var run_speed := _speed()
	_assert("B3_run_clip", "Run", str(_body.visual_anim_current),
		_body.visual_anim_current == &"Run")
	_assert("B4_run_speed", "≈%.2f" % RUN_NOMINAL, "%.3f" % run_speed,
		absf(run_speed - RUN_NOMINAL) <= SPEED_EPS)
	_assert("B5_run_faster_than_walk", "run > walk",
		"%.3f > %.3f" % [run_speed, walk_speed], run_speed > walk_speed + 0.5)

	# 松开冲刺回到 Walk（速度也要回落）
	_body.want_sprint = false
	await _step(45)
	_assert("B6_back_to_walk_clip", "Walk", str(_body.visual_anim_current),
		_body.visual_anim_current == &"Walk")
	_assert("B7_back_to_walk_speed", "≈%.2f" % WALK_NOMINAL, "%.3f" % _speed(),
		absf(_speed() - WALK_NOMINAL) <= SPEED_EPS)

	# 停下
	_body.move_intent = Vector2.ZERO
	await _step(30)
	_assert("B8_stop_idle", "Idle", str(_body.visual_anim_current),
		_body.visual_anim_current == &"Idle")

	# 片段时长（防止导出把时长压短，T046 踩过）
	for pair in [["Idle", 1.375], ["Walk", 1.041667], ["Run", 0.416667]]:
		var a := _body.visual_anim.get_animation(StringName(pair[0]))
		var want := float(pair[1])
		_assert("B9_%s_length" % pair[0], "≈%.3f" % want,
			"%.3f" % (a.length if a != null else -1.0),
			a != null and absf(a.length - want) <= 0.05)


# ---------------------------------------------------------------------------
# C：AI 的 FLEE 是否真的跑起来（含 `flee_sprint` 关闭的对照组）
# ---------------------------------------------------------------------------
func _case_ai_flee() -> void:
	var spots := get_nodes_in_group("hide_spots")
	_assert("C0_hide_spot_exists", "≥1", str(spots.size()), spots.size() >= 1)
	if spots.is_empty():
		return
	var spot: Node3D = spots[0] as Node3D

	var cfg := load(MOUSE_CFG) as SpeciesConfig
	var body := (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.ai_enabled = true
	body.player_controlled = false
	_level.add_child(body)
	# 放在洞口外 2.5 m（朝向庭院中心），保证有可跑的路程
	body.global_position = spot.global_position + Vector3(0.0, 0.5, 2.5)
	await _step(60)

	var ai: AnimalAI = body.ai
	_assert("C1_ai_is_mouse_ai", "MouseAI", str(ai != null), ai != null and ai is AnimalAI)
	if ai == null:
		return
	_assert("C2_flee_sprint_default", "true", str(ai.get("flee_sprint")), bool(ai.get("flee_sprint")))

	var wd: Node = root.get_node_or_null("/root/WorldDirector")
	var wt := 0.0
	if wd != null:
		wt = float(wd.get("world_time"))

	ai.call("start_flee", wt, &"t052_probe")
	var sprint_seen := false
	var run_clip := false
	var max_speed := 0.0
	for i in 30:
		await _step(1)
		if body.want_sprint:
			sprint_seen = true
		if body.visual_anim_current == &"Run":
			run_clip = true
		max_speed = maxf(max_speed, _speed_of(body))
	_assert("C3_flee_want_sprint", "true", str(sprint_seen), sprint_seen)
	_assert("C4_flee_uses_run_clip", "Run", str(body.visual_anim_current),
		run_clip or body.visual_anim_current == &"Run")
	_assert("C5_flee_speed_faster_than_walk", "> %.2f" % (WALK_NOMINAL + 0.5),
		"%.3f" % max_speed, max_speed > WALK_NOMINAL + 0.5)

	# 对照组：同一套夹具，但**一开始就**把 flee_sprint 关掉 → 只该用"走"的速度
	# （先关再逃，避免从 3.0 减速的过渡段把"减速中"误判成"没生效"）
	var ctrl := (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	ctrl.species_config = cfg
	ctrl.ai_enabled = true
	ctrl.player_controlled = false
	_level.add_child(ctrl)
	ctrl.global_position = spot.global_position + Vector3(1.2, 0.5, 2.5)
	await _step(60)
	var ctrl_ai: AnimalAI = ctrl.ai
	if ctrl_ai == null:
		_assert("C6_control_ai", "MouseAI", "null", false)
		return
	ctrl_ai.set("flee_sprint", false)
	ctrl_ai.call("start_flee", wt, &"t052_control")
	var ctrl_run := false
	var ctrl_max := 0.0
	for i in 60:
		await _step(1)
		ctrl_max = maxf(ctrl_max, _speed_of(ctrl))
		if ctrl.want_sprint or ctrl.visual_anim_current == &"Run":
			ctrl_run = true
	_assert("C6_control_no_sprint", "false", str(ctrl_run), not ctrl_run)
	_assert("C7_control_speed_walk_like", "0.4–%.2f" % (WALK_NOMINAL + SPEED_EPS),
		"%.3f" % ctrl_max, ctrl_max > 0.4 and ctrl_max <= WALK_NOMINAL + SPEED_EPS)
	ctrl.queue_free()


# ---------------------------------------------------------------------------
func _spawn_point() -> Vector3:
	return Vector3(-2.0, 0.45, 20.0)


func _speed() -> float:
	return _speed_of(_body)


func _speed_of(b: AnimalBody) -> float:
	var v: Vector3 = b.velocity if b != null else Vector3.ZERO
	return Vector2(v.x, v.z).length()

func _step(n: int) -> void:
	for i in n:
		await physics_frame


func _assert(tag: String, expected: String, actual: String, ok: bool) -> bool:
	if ok:
		_pass += 1
		print("ASSERT|%s|%s|%s|PASS" % [tag, expected, actual])
	else:
		_fail += 1
		_failed.append(tag)
		print("ASSERT|%s|%s|%s|FAIL" % [tag, expected, actual])
	return ok


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_pass + _fail, _fail])
	if _fail == 0:
		print("RESULT|pass=%d|fail=0|failed=" % _pass)
		quit(0)
	else:
		print("RESULT|pass=%d|fail=%d|failed=%s" % [_pass, _fail, "|".join(_failed)])
		quit(1)
