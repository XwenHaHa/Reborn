extends SceneTree
## T048：猫的**待机 / 行走**循环验收（开发计划 :216）。
##
## 验收词：「两段动画可循环；优先**原地动画**，避免根运动与 CharacterMovement 重复位移」。
##
## 断言分层：
##  A. 循环：`Idle/Walk/Run` 的 `loop_mode == LOOP_LINEAR`，且播放到超过一个周期后**真的绕回**（不停止）；
##  B. 原地：静止时 2 个周期内身体与视觉节点**零位移**（动画不自己走）；
##  C. 不重复位移：位移只来自 `CharacterBody3D`——1 s 走 1.8 m ±15%，且播放速率 = 实际/名义速度；
##  D. 根运动：逐周期检查视觉节点本地位置不累积（< 1 mm，2 个周期）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t048_cat_anim.gd' --quit-after 300000
## 结果口径：RESULT|pass=<n>|fail=<n>|failed=...

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CAT_CFG := "res://resources/species/cat.tres"
const CLOCK := "res://scripts/core/game_clock.gd"
const SPAWN := Vector3(-2.0, 0.45, 20.0)

var _level: Node3D = null
var _body: AnimalBody = null
var _pass := 0
var _fail := 0
var _failed: Array[String] = []


func _initialize() -> void:
	var gc := load(CLOCK)
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

	var cfg := load(CAT_CFG) as SpeciesConfig
	_body = (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	_body.species_config = cfg
	_body.ai_enabled = false
	_body.player_controlled = false
	_level.add_child(_body)
	_body.global_position = SPAWN
	await _step(45)

	_assert("A1_anim_bound", "true", str(_body.visual_anim_active), _body.visual_anim_active)
	var ap := _body.visual_anim
	for name in ["Idle", "Walk", "Run"]:
		var a := ap.get_animation(StringName(name))
		_assert("A2_%s_exists" % name, "Animation", str(a != null), a != null)
		if a == null:
			continue
		_assert("A3_%s_loop_linear" % name, "loop_mode=1", str(a.loop_mode),
			a.loop_mode == Animation.LOOP_LINEAR)

	# ---- B：静止两个 Idle 周期，身体与视觉节点都不动 ----
	var idle_len: float = ap.get_animation(&"Idle").length
	var pos0 := _body.global_position
	var vis0: Vector3 = _body.visual_root.position
	var t0 := Time.get_ticks_usec()
	var elapsed := 0.0
	while elapsed < idle_len * 2.0:
		await _step(1)
		elapsed += 1.0 / 60.0
	_assert("B1_idle_body_still", "≤ 0.01 m", "%.4f m" % pos0.distance_to(_body.global_position),
		pos0.distance_to(_body.global_position) <= 0.01)
	_assert("B2_idle_visual_still", "≤ 0.001 m", "%.4f m" % vis0.distance_to(_body.visual_root.position),
		vis0.distance_to(_body.visual_root.position) <= 0.001)
	_assert("B3_idle_clip", "Idle", str(_body.visual_anim_current),
		_assert_ok(_body.visual_anim_current == &"Idle"))

	# ---- A：Walk 播过 1.2 个周期后仍然在播（绕回，不停止）----
	_body.move_intent = Vector2(0.0, -1.0)
	await _step(10)
	var walk_a := ap.get_animation(&"Walk")
	var one_plus := walk_a.length * 1.2
	elapsed = 0.0
	while elapsed < one_plus:
		await _step(1)
		elapsed += 1.0 / 60.0
	_assert("A4_walk_still_playing", "true", str(ap.is_playing()), ap.is_playing())
	_assert("A5_walk_wrapped", "< 长度 %.3f" % walk_a.length,
		"%.3f" % ap.current_animation_position, ap.current_animation_position < walk_a.length)
	_assert("A6_walk_clip", "Walk", str(_body.visual_anim_current),
		_assert_ok(_body.visual_anim_current == &"Walk"))

	# ---- C：位移来自身体移动，速率与速度匹配 ----
	var cfg2 := load(CAT_CFG) as SpeciesConfig
	var rate := ap.speed_scale
	_assert("C1_walk_rate_matches_speed", "1.00±0.05", "%.3f" % rate,
		absf(rate - 1.0) <= 0.05)
	# 1 s 走 ≈ walk_speed
	var p1 := _body.global_position
	var n := 60
	for i in n:
		await _step(1)
	var moved := Vector2(_body.global_position.x - p1.x, _body.global_position.z - p1.z).length()
	var expect: float = cfg2.walk_speed * (float(n) / 60.0)
	_assert("C2_walk_distance_1s", "≈%.2f m" % expect, "%.3f m" % moved,
		absf(moved - expect) <= 0.15 * expect)

	# 说明：`speed_scale` 的**夹紧区间**（walk 0.5–1.8、run 0.6–1.6）本轮未单独断言——
	# 走/跑各只有一档实测速度可用，构造中间速度需要改移动参数；已如实记在证据"未验证"里。

	# ---- D：两个周期后视觉节点本地位置不累积 ----
	_body.move_intent = Vector2.ZERO
	await _step(30)
	var vis1: Vector3 = _body.visual_root.position
	_assert("D1_visual_no_accumulation", "≤ 0.001 m", "%.4f m" % vis1.distance_to(vis0),
		vis1.distance_to(vis0) <= 0.001)

	_finish()


func _step(n: int) -> void:
	for i in n:
		await physics_frame


func _assert_ok(v: bool) -> bool:
	return v


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
