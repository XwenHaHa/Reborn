extends SceneTree
## T049：猫的**攻击提示动画**（`AttackCue`）与攻击事件时间对齐（开发计划 :217）。
##
## 验收词：「提供最小 NPC 动作反馈，**动画时间和攻击事件吻合**」。
##
## 断言：
##  A. 资产：`AttackCue` 片段存在、`loop_mode = LOOP_NONE`（只播一次）、长度 ≈ `attack_telegraph`（0.45 s）；
##  B. 事件对齐：`AttackSettlement.start_attack()` 后进入 `telegraphing`，**同一帧起** `visual_anim_current == "AttackCue"`，
##     且提示时长（`telegraph_elapsed`）不超过片段长度 + 容差；
##  C. 收尾：恢复期结束后回到 `Idle`/`Walk`（不卡在攻击姿态），且 `AttackCue` 期间不走路（`speed` 不变大）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t049_attack_cue.gd' --quit-after 300000
## 结果口径：RESULT|pass=<n>|fail=<n>|failed=...

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CAT_CFG := "res://resources/species/cat.tres"
const MOUSE_CFG := "res://resources/species/mouse.tres"
const CLOCK := "res://scripts/core/game_clock.gd"
const SPAWN := Vector3(-2.0, 0.45, 20.0)

const CLIP := "AttackCue"
const LEN_TOL := 0.02      # 片段长度与 telegraph 的容差（秒）
const TELEGRAPH_TOL := 0.05

var _level: Node3D = null
var _cat: AnimalBody = null
var _mouse: AnimalBody = null
var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _wd: Node = null


func _initialize() -> void:
	var gc := load(CLOCK)
	if gc != null and gc.has_method("use_fake"):
		gc.call("use_fake", 0)
	await process_frame
	_wd = root.get_node_or_null("/root/WorldDirector")
	var packed: PackedScene = load(LEVEL)
	if not _assert("A0_level_loads", "PackedScene", str(packed != null), packed != null):
		_finish()
	_level = packed.instantiate() as Node3D
	root.add_child(_level)
	await process_frame

	var cat_cfg := load(CAT_CFG) as SpeciesConfig
	_cat = (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	_cat.species_config = cat_cfg
	_cat.ai_enabled = false
	_cat.player_controlled = false
	_level.add_child(_cat)
	_cat.global_position = SPAWN
	await _step(30)

	# ---- A：片段本身 ----
	var ap := _cat.visual_anim
	var clip := ap.get_animation(StringName(CLIP))
	if not _assert("A1_clip_exists", CLIP, str(clip != null), clip != null):
		_finish()
		return
	var telegraph := float(cat_cfg.attack_telegraph)
	_assert("A2_clip_length_matches_telegraph", "≈%.3f s" % telegraph,
		"%.3f s" % clip.length, absf(clip.length - telegraph) <= LEN_TOL)
	_assert("A3_clip_loop_none", "loop_mode=0", str(clip.loop_mode),
		clip.loop_mode == Animation.LOOP_NONE)
	_assert("A4_clip_has_tracks", "≥ 12 条轨", str(clip.get_track_count()),
		clip.get_track_count() >= 12)

	# ---- B：事件对齐 ----
	var mouse_cfg := load(MOUSE_CFG) as SpeciesConfig
	_mouse = (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	_mouse.species_config = mouse_cfg
	_mouse.ai_enabled = false
	_mouse.player_controlled = false
	_level.add_child(_mouse)
	# 猫朝 -Z，把猎物放在前方 0.40 m（进入 0.65 m 攻击范围 + 60° 扇区）
	_mouse.global_position = SPAWN + Vector3(0.0, 0.0, -0.40)
	await _step(20)

	var atk: AttackSettlement = _cat.attack
	if not _assert("B0_attack_settlement", "AttackSettlement", str(atk != null), atk != null):
		_finish()
		return
	var ok := atk.start_attack()
	_assert("B1_start_attack", "true", str(ok), ok)
	_assert("B2_state_telegraphing", "telegraphing", atk.state_name(),
		atk.state_name() == "telegraphing")
	# 同一帧起就该播提示（`_update_visual_animation` 每物理帧都会跑到）
	await _step(1)
	_assert("B3_clip_switched", CLIP, str(_cat.visual_anim_current),
		_cat.visual_anim_current == StringName(CLIP))

	# 提示期：片段在播、位置单调推进、不走路
	var pos0 := _cat.global_position
	var prev_pos := ap.current_animation_position
	var advanced := true
	var moved_telegraph := 0.0
	var frames := 0
	while atk.is_attacking() and frames < 120:
		await _step(1)
		frames += 1
		if ap.current_animation_position + 1e-6 < prev_pos and atk.is_attacking():
			advanced = advanced and false
		prev_pos = ap.current_animation_position
		moved_telegraph = maxf(moved_telegraph, pos0.distance_to(_cat.global_position))
	_assert("B4_clip_advances", "true", str(advanced), advanced)
	_assert("B5_telegraph_duration", "≈%.2f s" % telegraph, "%.3f s" % (float(frames) / 60.0),
		absf(float(frames) / 60.0 - telegraph) <= TELEGRAPH_TOL)
	_assert("B6_no_locomotion_while_telegraphing", "≤ 0.05 m", "%.4f m" % moved_telegraph,
		moved_telegraph <= 0.05)

	# ---- C：收尾回到常规片段 ----
	await _step(120)  # 覆盖 recovery（1.2 s）
	_assert("C1_back_to_locomotion", "Idle/Walk", str(_cat.visual_anim_current),
		_cat.visual_anim_current in [&"Idle", &"Walk"])
	_assert("C2_attack_ended", "false", str(atk.is_attacking()), not atk.is_attacking())

	# ---- D：奔跑（任务名的另一半"猫奔跑"：冲刺必须真的切到 Run）----
	# `want_sprint` / `move_intent` 平时由 AI 或玩家输入逐帧写入，这里无人接管，自己喂。
	var sprint_speed := 0.0
	for i in 30:
		_cat.move_intent = Vector2(0.0, -1.0)
		_cat.want_sprint = true
		await _step(1)
		sprint_speed = maxf(sprint_speed, Vector2(_cat.velocity.x, _cat.velocity.z).length())
	_assert("D1_sprint_reaches_config", "≈%.2f m/s" % cat_cfg.sprint_speed,
		"%.3f m/s" % sprint_speed, absf(sprint_speed - float(cat_cfg.sprint_speed)) <= 0.5)
	_assert("D2_run_clip_while_sprinting", "Run", str(_cat.visual_anim_current),
		_cat.visual_anim_current == &"Run")
	# `speed_scale` 是**归一化**速率：Run 分支 = speed / sprint_speed（满速恰好 1.0）。
	# 第一版按 ">1.0" 断言是我判据写错（现在改成对照归一比值），不是生产缺陷。
	var live_speed := Vector2(_cat.velocity.x, _cat.velocity.z).length()
	var want_rate := clampf(live_speed / maxf(0.05, float(cat_cfg.sprint_speed)), 0.6, 1.6)
	_assert("D3_run_rate_tracks_speed", "≈%.3f" % want_rate, "%.3f" % ap.speed_scale,
		absf(ap.speed_scale - want_rate) <= 0.01)
	_cat.move_intent = Vector2.ZERO
	_cat.want_sprint = false
	await _step(40)
	_assert("D4_stop_back_to_idle", "Idle", str(_cat.visual_anim_current),
		_cat.visual_anim_current == &"Idle")

	_finish()


func _step(n: int) -> void:
	# T043a 的注入口径：假时钟下世界时间不会自己走，必须逐物理帧注入，
	# 否则 `AttackSettlement` 的前摇/恢复永远不会到期（第一版实测卡在 telegraphing 2 s 不动）。
	for i in n:
		if _wd != null:
			_wd.call("set_world_time", float(_wd.get("world_time")) + 1.0 / 60.0)
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
