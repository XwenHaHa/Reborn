extends SceneTree
## T025 NPC 攻击与玩家受伤 断言
##
## 覆盖（`Docs/Tasks/T025.md` §6；数值只读 `Docs/Parameters.md` 第 69 行）：
##   A 接口与参数（Attack 组 6 字段 / 自校验 / 组件与信号 / 鼠不建组件 / 无物种名字面量）
##   B 预警与命中（0.45 s 预警内不掉血 → 伤害帧 35 一次 → 恢复 1.2 s → 停住不乱跑）
##   C 躲开、绕墙与边界（A04 的另一半：移开/墙/死亡/捕获/背对/边界距离/换层）
##   D 恢复间隔与连按（恢复期不重复伤害、连按只启动一次、死亡后拒绝）
##   E 朝向与几何（半角边界、预警中途转身、竖直差不计入距离）
##   F 玩家受伤通道与不变量（apply_damage/"attack"、受伤中断交互无收益、账本不变、不扣体力）
##   G 鼠不攻击（species 拒绝、不建组件、AI 永不进 attack）
##   H 集成与可查看（真实关卡预警→命中 / 身后不掉血 / HUD 与 MOV| 字段 / 无调试节点）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t025_attack.gd' --quit-after 300000
## 包内复验（只能用编辑器二进制 + --main-pack）：
##   & '<godot_console.exe>' --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
##       --script 'res://tests/run_t025_attack.gd' --quit-after 300000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"
const RP_SCENE := "res://scenes/world/resource_point.tscn"
const ATTACK_GD := "res://scripts/systems/attack.gd"

const EPS := 1e-3
const ARENA := 40.0
const CAT_Y := 0.25
const MOUSE_Y := 0.10
const DAMAGE := 35.0            # Parameters.md 第 69 行
const TELEGRAPH := 0.45         # 第 69 行
const RECOVERY := 1.2           # 第 69 行
const RANGE := 0.65             # 第 69 行（AttackRange 65）
const HALF_ANGLE := 60.0        # 实现默认值
const HIT_TOL := 0.05           # 伤害帧迟滞（与 CatAI.RANGE_HYSTERESIS 同口径）
const SPAWN_FRAMES := 12

var _checks := 0
var _fails := 0
var _cat_cfg: SpeciesConfig = null
var _mouse_cfg: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null
var _cat: AnimalBody = null
var _cat_ai: CatAI = null
var _prey: AnimalBody = null
var _extras: Array[Node] = []
var _walls: Array[StaticBody3D] = []
var _wall_seq := 0
var _events: Array[Dictionary] = []
var _transitions: Array[Dictionary] = []
## `died` / `changed` 记账（**lambda 按值捕获**，局部计数器不会变 —— 必须往数组里 append）
var _died_events: Array = []
var _changed_events: Array = []


func _initialize() -> void:
	print("TEST|run_t025_attack|engine=%s" % Engine.get_version_info().string)
	_cat_cfg = load(CAT) as SpeciesConfig
	_mouse_cfg = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")
	await _section_a_contract()
	await _section_b_telegraph()
	await _section_c_dodge()
	await _section_d_recovery()
	await _section_e_facing()
	await _section_f_damage_channel()
	await _section_g_mouse_no_attack()
	await _section_h_integration()
	_finish()


# ---------------------------------------------------------------------------
# A 接口与参数
# ---------------------------------------------------------------------------

func _section_a_contract() -> void:
	print("---- A 接口与参数 ----")
	_assert("A_cat_cfg_loaded", "非 null", str(_cat_cfg != null), _cat_cfg != null)
	_assert("A_mouse_cfg_loaded", "非 null", str(_mouse_cfg != null), _mouse_cfg != null)
	if _cat_cfg == null or _mouse_cfg == null:
		return
	# 真源：Parameters.md 第 69 行
	_assert("A_cat_can_attack", "true", str(_cat_cfg.can_attack), _cat_cfg.can_attack)
	_assert_near("A_cat_damage_35", DAMAGE, _cat_cfg.attack_damage, EPS)
	_assert_near("A_cat_telegraph_0_45", TELEGRAPH, _cat_cfg.attack_telegraph, EPS)
	_assert_near("A_cat_recovery_1_2", RECOVERY, _cat_cfg.attack_recovery, EPS)
	_assert_near("A_cat_range_0_65", RANGE, _cat_cfg.attack_range, EPS)
	_assert_near("A_cat_half_angle_60", HALF_ANGLE, _cat_cfg.attack_facing_half_angle_deg, EPS)
	_assert("A_mouse_cannot_attack", "false", str(_mouse_cfg.can_attack), not _mouse_cfg.can_attack)
	_assert_near("A_mouse_damage_zero", 0.0, _mouse_cfg.attack_damage, EPS)
	_assert("A_cat_cfg_validates", "无问题", str(_cat_cfg.validate_config()), _cat_cfg.validate_config().is_empty())
	_assert("A_mouse_cfg_validates", "无问题", str(_mouse_cfg.validate_config()), _mouse_cfg.validate_config().is_empty())

	# 自校验：坏配置必须被挡
	var probe := load(CAT) as SpeciesConfig
	if probe != null:
		probe = probe.duplicate(true) as SpeciesConfig
		probe.attack_range = 0.0
		_assert("A_validate_rejects_zero_range", "≥ 1 条问题", str(probe.validate_config()),
			probe.validate_config().size() >= 1)
		var probe2 := load(MOUSE) as SpeciesConfig
		probe2 = probe2.duplicate(true) as SpeciesConfig
		probe2.can_attack = true
		_assert("A_validate_rejects_mouse_can_attack_no_damage", "≥ 1 条问题", str(probe2.validate_config()),
			probe2.validate_config().size() >= 1)

	# 组件类与查询
	var script := load(ATTACK_GD) as Script
	_assert("A_attack_script_exists", "非 null", str(script != null), script != null)
	if script == null:
		return
	var inst: Object = script.new()
	_assert("A_is_attack_settlement", "AttackSettlement", str(inst is AttackSettlement), inst is AttackSettlement)
	if inst is AttackSettlement:
		var atk := inst as AttackSettlement
		for m in ["setup", "start_attack", "is_attacking", "is_in_recovery", "state_name",
				"telegraph_elapsed", "recovery_elapsed", "target_id", "last_miss_reason", "report"]:
			_assert("A_attack_has_%s" % m, "有 %s()" % m, str(atk.has_method(m)), atk.has_method(m))
		for s in ["attack_started", "attack_landed", "attack_ended"]:
			_assert("A_attack_signal_%s" % s, "true", str(atk.has_signal(s)), atk.has_signal(s))
		_assert("A_attack_idle_at_start", "idle", atk.state_name(), atk.state_name() == "idle")
		for f in ["attack_count", "hit_count", "miss_count", "last_damage"]:
			_assert("A_attack_field_%s" % f, "存在", str(f in atk), f in atk)
	inst.free()

	# 枚举与动作状态
	_assert("A_has_attacking_action", "true", str("ATTACKING" in AnimalBody.ACT), "ATTACKING" in AnimalBody.ACT)
	_assert("A_ai_state_attack_index", "8", str(AnimalAI.State.ATTACK), AnimalAI.State.ATTACK == 8)

	# CatAI 新开关与查询
	await _fresh_world({"prey_at": _front(3.0), "cat_ai": true})
	if _cat_ai == null:
		_assert("A_builds_cat_ai", "非 null", "<null>", false)
		return
	_assert("A_ai_attack_enabled_default", "true", str(_cat_ai.attack_enabled), _cat_ai.attack_enabled)
	_assert("A_ai_retry_interval_positive", "> 0", "%.2f" % _cat_ai.attack_retry_interval,
		_cat_ai.attack_retry_interval > 0.0)
	_assert("A_ai_has_attack_count", "true", str(_cat_ai.has_method("attack_count")), _cat_ai.has_method("attack_count"))
	_assert("A_ai_range_matches_config", "%.4f" % _cat_cfg.attack_range,
		"%.4f" % _cat_ai.attack_range, absf(_cat_ai.attack_range - _cat_cfg.attack_range) <= EPS)
	var rep := _cat_ai.ai_report()
	for key in ["attack_enabled", "attack_count", "attack_hits", "attack_misses", "attack_state", "attack_target", "attack_miss_reason"]:
		_assert("A_report_has_%s" % key, "存在", str(rep.has(key)), rep.has(key))

	# 身体侧：猫有攻击组件，鼠没有
	_assert("A_cat_body_has_attack", "非 null", str(_cat.attack != null), _cat.attack != null)
	var mouse := (load(BODY) as PackedScene).instantiate() as AnimalBody
	mouse.species_config = _mouse_cfg
	mouse.player_controlled = false
	_world.add_child(mouse)
	await _advance_frames(4)
	_assert("A_mouse_body_has_no_attack", "<null>", str(mouse.attack), mouse.attack == null)
	var req_a := mouse.request_attack()
	_assert("A_mouse_request_attack_false", "false", str(req_a), not req_a)
	_assert("A_mouse_blocked_species", "species", str(mouse.last_attack_blocked_reason),
		mouse.last_attack_blocked_reason == &"species")
	mouse.queue_free()
	await _advance_frames(2)

	# 源码静态检查：不出现物种名字面量（包内 `.gd` 不可读 → 如实标 STATIC|NOT-APPLICABLE）
	var src := _read_source(ATTACK_GD)
	if src.is_empty():
		print("STATIC|NOT-APPLICABLE|attack.gd（包内 .gd 不可读，T013 口径）")
	else:
		_assert("A_static_no_species_literal", "不含 \"Cat\" 字面量", "含" if src.contains("\"Cat\"") else "不含",
			not src.contains("\"Cat\""))


func _read_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	return txt


# ---------------------------------------------------------------------------
# B 预警与命中
# ---------------------------------------------------------------------------

func _section_b_telegraph() -> void:
	print("---- B 预警与命中 ----")
	await _fresh_world({"prey_at": _front(0.5), "cat_ai": false})
	if _cat == null or _prey == null:
		return
	var atk := _cat.attack
	if atk == null:
		_assert("B_has_attack_component", "非 null", "<null>", false)
		return
	_hook_attack(atk)
	var hp0: float = _prey.survival.state.health
	_assert_near("B_health_starts_100", 100.0, hp0, 0.01)
	var started := _cat.request_attack()
	_assert("B_start_ok", "true", str(started), started)
	_assert("B_count_1", "1", str(atk.attack_count), atk.attack_count == 1)
	_assert("B_state_telegraphing", "telegraphing", atk.state_name(), atk.state_name() == "telegraphing")
	_assert("B_is_attacking", "true", str(atk.is_attacking()), atk.is_attacking())
	_assert("B_action_state_attacking", "attacking", _cat.action_state_name(), _cat.action_state_name() == "attacking")
	_assert("B_target_id_set", "非空", atk.target_id(), not atk.target_id().is_empty())

	# 预警期间：停住、不乱跑、目标**还没掉血**
	var hold := _cat.global_position
	var half := TELEGRAPH * 0.5
	await _run_seconds(half)
	var e0: float = atk.telegraph_elapsed()
	await _run_seconds(0.2)
	var e1: float = atk.telegraph_elapsed()
	var hp_before_hit: float = _prey.survival.state.health
	_assert("B_telegraph_elapsed_grows", "≥ 0.15 s", "%.3f s" % (e1 - e0), (e1 - e0) >= 0.15)
	_assert("B_no_damage_before_frame", "100.0", "%.1f" % hp_before_hit, absf(hp_before_hit - 100.0) <= 0.01)
	_assert("B_move_intent_zero", "(0, 0)", str(_cat.move_intent), _cat.move_intent.length() < 0.01)
	_assert("B_no_move_during_attack", "≤ 0.15 m", "%.4f m" % hold.distance_to(_cat.global_position),
		hold.distance_to(_cat.global_position) <= 0.15)

	# 伤害帧
	var hit_at := await _run_seconds(1.0, func() -> bool: return atk.hit_count >= 1)
	var hp1: float = _prey.survival.state.health
	_assert("B_hit_count_1", "1", str(atk.hit_count), atk.hit_count == 1)
	_assert_near("B_health_drops_35", hp0 - DAMAGE, hp1, 0.05)
	_assert("B_damage_recorded", "%.1f" % DAMAGE, "%.1f" % atk.last_damage, absf(atk.last_damage - DAMAGE) <= 0.05)
	_assert("B_hit_reason_attack", "attack", str(_prey.survival.state.last_damage_reason),
		_prey.survival.state.last_damage_reason == &"attack")
	_assert("B_signal_started_once", "1", str(_count_event("start")), _count_event("start") == 1)
	_assert("B_signal_landed_once", "1", str(_count_event("land")), _count_event("land") == 1)
	_assert("B_signal_ended_once", "1", str(_count_event("end")), _count_event("end") == 1)
	_assert("B_landed_applied_true", "true", str(_last_landed_applied()), _last_landed_applied())
	_assert("B_landed_damage_35", "%.1f" % DAMAGE, "%.1f" % _last_landed_damage(), absf(_last_landed_damage() - DAMAGE) <= 0.05)

	# 恢复期
	_assert("B_in_recovery", "true", str(atk.is_in_recovery()), atk.is_in_recovery())
	_assert("B_state_recovering", "recovering", atk.state_name(), atk.state_name() == "recovering")
	_assert("B_body_recovering", "true", str(_cat.is_recovering()), _cat.is_recovering())
	var rec := await _run_seconds(2.0, func() -> bool: return atk.state_name() == "idle")
	_assert("B_back_to_idle", "idle（%.2f s）" % rec, atk.state_name(), atk.state_name() == "idle")
	_assert("B_recovery_about_1_2", "1.2 ±0.2 s", "%.2f s" % (hit_at + rec), absf((hit_at + rec) - RECOVERY) <= 0.2)
	_assert("B_action_idle_after", "idle", _cat.action_state_name(), _cat.action_state_name() == "idle")


# ---------------------------------------------------------------------------
# C 躲开、绕墙与边界
# ---------------------------------------------------------------------------

func _section_c_dodge() -> void:
	print("---- C 躲开、绕墙与边界 ----")
	# C1 预警期间移开 → 无伤
	await _fresh_world({"prey_at": _front(0.5), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	var atk := _cat.attack
	_hook_attack(atk)
	var req_c1 := _cat.request_attack()
	_assert("C1_start_ok", "true", str(req_c1), req_c1)
	await _run_seconds(TELEGRAPH * 0.5)
	_place_prey(_front(1.5))
	await _run_seconds(1.2)
	_assert("C1_miss_out_of_range", "out_of_range", str(atk.last_miss_reason()),
		atk.last_miss_reason() == &"out_of_range")
	_assert("C1_miss_count_1", "1", str(atk.miss_count), atk.miss_count == 1)
	_assert("C1_hit_count_0", "0", str(atk.hit_count), atk.hit_count == 0)
	_assert("C1_health_unchanged", "100.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 100.0) <= 0.01)

	# C2 预警期间加墙 → 无伤（近距豁免不得放行）
	await _fresh_world({"prey_at": _front(0.5), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	var req_c2 := _cat.request_attack()
	_assert("C2_start_ok", "true", str(req_c2), req_c2)
	await _run_seconds(TELEGRAPH * 0.5)
	_add_wall_between(_cat.global_position, _prey.global_position, 0.5, 1.0)
	await _advance_frames(4)
	await _run_seconds(1.2)
	_assert("C2_miss_occluded", "occluded", str(atk.last_miss_reason()), atk.last_miss_reason() == &"occluded")
	_assert("C2_health_unchanged", "100.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 100.0) <= 0.01)

	# C3 预警期间目标死亡 → 无伤
	await _fresh_world({"prey_at": _front(0.5), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	var req_c3 := _cat.request_attack()
	_assert("C3_start_ok", "true", str(req_c3), req_c3)
	await _run_seconds(TELEGRAPH * 0.5)
	_prey.survival.apply_damage(9999.0, &"test")
	await _advance_frames(4)
	var hp_before: float = _prey.survival.state.health
	await _run_seconds(1.2)
	_assert("C3_prey_dead", "true", str(_prey.survival.is_dead()), _prey.survival.is_dead())
	_assert("C3_miss_dead", "dead", str(atk.last_miss_reason()), atk.last_miss_reason() == &"dead")
	_assert("C3_no_extra_damage", "%.1f" % hp_before, "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - hp_before) <= 0.01)
	_assert("C3_hit_count_0", "0", str(atk.hit_count), atk.hit_count == 0)

	# C4 预警期间目标被捕获 → 无伤
	await _fresh_world({"prey_at": _front(0.5), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	var req_c4 := _cat.request_attack()
	_assert("C4_start_ok", "true", str(req_c4), req_c4)
	await _run_seconds(TELEGRAPH * 0.5)
	var marked_c4 := _prey.mark_captured("test_cat")
	_assert("C4_marked", "true", str(marked_c4), marked_c4)
	await _run_seconds(1.2)
	_assert("C4_miss_dead", "dead", str(atk.last_miss_reason()), atk.last_miss_reason() == &"dead")
	_assert("C4_health_unchanged", "100.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 100.0) <= 0.01)

	# C5 目标在身后（背对）→ 打不中
	await _fresh_world({"prey_at": _front(0.3), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	_place_prey(_front(0.3, 180.0))     # 同距离但转到正后方
	await _advance_frames(4)
	var started_back := _cat.request_attack()
	_assert("C5_back_start_rejected", "拒绝或搭不上", str(_cat.last_attack_blocked_reason),
		not started_back or _cat.last_attack_blocked_reason == &"target")
	await _run_seconds(1.2)
	_assert("C5_back_no_damage", "100.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 100.0) <= 0.01)

	# C6 距离边界：0.65 命中 / 0.70 不命中
	await _fresh_world({"prey_at": _front(RANGE - 0.02), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	var req_c6 := _cat.request_attack()
	_assert("C6_start_in_range", "true", str(req_c6), req_c6)
	await _run_seconds(1.4)
	_assert("C6_border_hit", "1", str(atk.hit_count), atk.hit_count == 1)
	var hp_at_border: float = _prey.survival.state.health

	await _fresh_world({"prey_at": _front(RANGE + 0.05 + 0.02), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	var started_far := _cat.request_attack()
	_assert("C6_far_start_rejected", "false", "%s(%s)" % [str(started_far), str(_cat.last_attack_blocked_reason)],
		not started_far)
	await _run_seconds(1.0)
	_assert("C6_far_no_damage", "100.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 100.0) <= 0.01)
	_assert("C6_border_hp_65", "65.0", "%.1f" % hp_at_border, absf(hp_at_border - (100.0 - DAMAGE)) <= 0.05)

	# C7 目标换到别的碰撞层 → 不误伤
	await _fresh_world({"prey_at": _front(0.5), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	_prey.collision_layer = 4           # 不再是 animal 层（2）
	await _advance_frames(4)
	var started_layer := _cat.request_attack()
	_assert("C7_layer_start_rejected", "false", "%s(%s)" % [str(started_layer), str(_cat.last_attack_blocked_reason)],
		not started_layer)
	await _run_seconds(1.0)
	_assert("C7_layer_no_damage", "100.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 100.0) <= 0.01)


# ---------------------------------------------------------------------------
# D 恢复间隔与连按
# ---------------------------------------------------------------------------

func _section_d_recovery() -> void:
	print("---- D 恢复间隔与连按 ----")
	await _fresh_world({"prey_at": _front(0.5), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	var atk := _cat.attack
	_hook_attack(atk)
	var req_d1 := _cat.request_attack()
	_assert("D_first_start", "true", str(req_d1), req_d1)
	# 同一帧连按 10 次 → 只启动一次
	for i in 10:
		_cat.request_attack()
	_assert("D_burst_count_1", "1", str(atk.attack_count), atk.attack_count == 1)
	await _run_seconds(1.0, func() -> bool: return atk.hit_count >= 1)
	_assert("D_hit_1", "1", str(atk.hit_count), atk.hit_count == 1)
	var hp_hit: float = _prey.survival.state.health
	_assert_near("D_hp_65", 65.0, hp_hit, 0.05)
	# 恢复期内请求被拒
	var during := _cat.request_attack()
	_assert("D_rejected_during_recovery", "false", "%s(%s)" % [str(during), str(_cat.last_attack_blocked_reason)],
		not during)
	_assert("D_blocked_busy", "busy 或 recovering", str(_cat.last_attack_blocked_reason),
		_cat.last_attack_blocked_reason == &"busy" or _cat.last_attack_blocked_reason == &"recovering")
	_assert("D_count_still_1", "1", str(atk.attack_count), atk.attack_count == 1)
	# 恢复期内不再掉血
	var samples := 0
	var min_hp := 100.0
	var t0 := _now()
	while _now() - t0 < 1.0:
		await physics_frame
		min_hp = minf(min_hp, _prey.survival.state.health)
		samples += 1
	_assert("D_samples", "≥ 30 帧", str(samples), samples >= 30)
	_assert("D_no_repeat_damage", "65.0", "%.1f" % min_hp, absf(min_hp - 65.0) <= 0.05)
	# 恢复结束后可再打
	var idle := await _run_seconds(1.5, func() -> bool: return atk.state_name() == "idle")
	_assert("D_idle_again", "idle（%.2f s）" % idle, atk.state_name(), atk.state_name() == "idle")
	var second := _cat.request_attack()
	_assert("D_second_start", "true", str(second), second)
	await _run_seconds(1.2, func() -> bool: return atk.hit_count >= 2)
	_assert("D_hit_2", "2", str(atk.hit_count), atk.hit_count == 2)
	_assert_near("D_hp_30", 30.0, _prey.survival.state.health, 0.05)
	# 第三次 → 0 血，died 只发一次
	_prey.survival.died.connect(func(r: StringName) -> void: _died_events.append(r))
	var idled2 := await _run_seconds(2.0, func() -> bool: return atk.state_name() == "idle")
	_assert("D_idle_before_third", "idle", atk.state_name(), atk.state_name() == "idle")
	_cat.request_attack()
	await _run_seconds(1.2, func() -> bool: return atk.hit_count >= 3)
	_assert("D_hit_3", "3", str(atk.hit_count), atk.hit_count == 3)
	_assert_near("D_hp_zero", 0.0, _prey.survival.state.health, 0.05)
	_assert("D_prey_dead", "true", str(_prey.survival.is_dead()), _prey.survival.is_dead())
	_assert("D_died_once", "1", str(_died_events.size()), _died_events.size() == 1)
	await _run_seconds(0.6)
	_assert("D_died_still_once", "1", str(_died_events.size()), _died_events.size() == 1)
	var after_dead := _cat.request_attack()
	_assert("D_after_dead_rejected", "false", "%s(%s)" % [str(after_dead), str(_cat.last_attack_blocked_reason)],
		not after_dead)


# ---------------------------------------------------------------------------
# E 朝向与几何
# ---------------------------------------------------------------------------

func _section_e_facing() -> void:
	print("---- E 朝向与几何 ----")
	# 正前方命中
	await _fresh_world({"prey_at": _front(0.3), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	var atk := _cat.attack
	_hook_attack(atk)
	var req_e1 := _cat.request_attack()
	_assert("E_front_start", "true", str(req_e1), req_e1)
	await _run_seconds(1.2)
	_assert("E_front_hit", "1", str(atk.hit_count), atk.hit_count == 1)

	# 侧方 30°（半角 60° 内）→ 命中
	await _fresh_world({"prey_at": _front(0.4, 30.0), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	var req_e2 := _cat.request_attack()
	_assert("E_30deg_start", "true", str(req_e2), req_e2)
	await _run_seconds(1.2)
	_assert("E_30deg_hit", "1", str(atk.hit_count), atk.hit_count == 1)
	_assert("E_30deg_hp_65", "65.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 65.0) <= 0.05)

	# 侧方 90°（半角外）→ 打不中
	await _fresh_world({"prey_at": _front(0.4, 90.0), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	var started_90 := _cat.request_attack()
	_assert("E_90deg_rejected", "false", "%s(%s)" % [str(started_90), str(_cat.last_attack_blocked_reason)],
		not started_90)
	await _run_seconds(1.0)
	_assert("E_90deg_no_damage", "100.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 100.0) <= 0.01)

	# E3a 攻击**锁定方向**（§6 第 231 行）：预警中途**猫自己转身**，目标仍在锁定锥内 → 照样命中
	await _fresh_world({"prey_at": _front(0.5), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	var req_e3 := _cat.request_attack()
	_assert("E3_start", "true", str(req_e3), req_e3)
	await _run_seconds(TELEGRAPH * 0.5)
	_cat.look_at(_cat.global_position - Vector3(0.0, 0.0, 1.0), Vector3.UP)   # 自己转身 180°
	await _advance_frames(2)
	await _run_seconds(1.2)
	_assert("E3_lock_still_hits", "1", str(atk.hit_count), atk.hit_count == 1)
	_assert("E3_lock_damage_65", "65.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 65.0) <= 0.05)

	# E3b **目标**跑出锁定锥（同距离 0.4 m、偏 90°，半角 60° 之外）→ 伤害帧 `facing`、不掉血
	await _fresh_world({"prey_at": _front(0.5), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	var req_e3b := _cat.request_attack()
	_assert("E3b_start", "true", str(req_e3b), req_e3b)
	await _run_seconds(TELEGRAPH * 0.5)
	_place_prey(_front(0.4, 90.0))
	await _advance_frames(2)
	await _run_seconds(1.2)
	_assert("E3b_miss_facing", "facing", str(atk.last_miss_reason()), atk.last_miss_reason() == &"facing")
	_assert("E3b_no_damage", "100.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 100.0) <= 0.01)

	# E4 竖直差不算距离：抬高 0.5 m，水平仍 0.5 m → 命中
	await _fresh_world({"prey_at": _front(0.5), "cat_ai": false})
	if _cat == null or _cat.attack == null:
		return
	atk = _cat.attack
	_hook_attack(atk)
	var spot := _front(0.5)
	_prey.global_position = Vector3(spot.x, MOUSE_Y + 0.5, spot.z)
	await _advance_frames(4)
	var req_e4 := _cat.request_attack()
	_assert("E4_elevated_start", "true", str(req_e4), req_e4)
	await _run_seconds(1.2)
	_assert("E4_elevated_hit", "1", str(atk.hit_count), atk.hit_count == 1)
	_assert("E4_elevated_hp_65", "65.0", "%.1f" % _prey.survival.state.health,
		absf(_prey.survival.state.health - 65.0) <= 0.05)


# ---------------------------------------------------------------------------
# F 玩家受伤通道与不变量
# ---------------------------------------------------------------------------

func _section_f_damage_channel() -> void:
	print("---- F 玩家受伤通道与不变量 ----")
	await _fresh_world({"prey_at": _front(0.5), "cat_ai": false, "with_food": true})
	if _cat == null or _cat.attack == null or _prey == null:
		return
	var atk := _cat.attack
	_hook_attack(atk)
	_prey.survival.changed.connect(func(s: SurvivalState) -> void: _changed_events.append(s))
	var cap_before := int(_wd.get("capture_count")) if _wd != null else -1
	var food_before := int(_wd.get("capture_food_count")) if _wd != null else -1
	var stamina_before: float = _cat.survival.state.stamina
	var pounce_before: int = _cat.pounce_count
	_cat.request_attack()
	await _run_seconds(1.2, func() -> bool: return atk.hit_count >= 1)
	_assert("F1_changed_signal", "≥ 1", str(_changed_events.size()), _changed_events.size() >= 1)
	_assert("F1_reason_attack", "attack", str(_prey.survival.state.last_damage_reason),
		_prey.survival.state.last_damage_reason == &"attack")
	_assert("F1_hp_65", "65.0", "%.1f" % _prey.survival.state.health, absf(_prey.survival.state.health - 65.0) <= 0.05)
	_assert("F3_capture_ledger_same", "%d" % cap_before, str(int(_wd.get("capture_count"))),
		int(_wd.get("capture_count")) == cap_before)
	_assert("F3_food_ledger_same", "%d" % food_before, str(int(_wd.get("capture_food_count"))),
		int(_wd.get("capture_food_count")) == food_before)
	_assert("F4_prey_not_captured", "false", str(_prey.captured), not _prey.captured)
	_assert("F4_attacker_no_captures", "0", str(_cat.captures), _cat.captures == 0)
	_assert("F5_no_pounce_used", "%d" % pounce_before, str(_cat.pounce_count), _cat.pounce_count == pounce_before)
	_assert("F5_stamina_kept", "≥ 起始 − 0.5", "%.2f -> %.2f" % [stamina_before, _cat.survival.state.stamina],
		_cat.survival.state.stamina >= stamina_before - 0.5)

	# F2 受伤中断交互且无收益（T017 交界）
	var rp := _find_food_point()
	if rp == null or rp.units <= 0:
		print("MEASURE|f2|skipped|no resource point in fixture")
		return
	_place_prey(_front(0.5))
	await _advance_frames(4)
	_prey.global_position = rp.global_position + Vector3(0.2, 0.0, 0.0)
	await _advance_frames(6)
	var units_before: int = rp.units
	_prey.interaction.try_interact()
	await _run_seconds(0.3)
	var interacting: bool = _prey.interaction.is_interacting()
	_prey.survival.apply_damage(DAMAGE, &"attack")
	await _advance_frames(4)
	_assert("F2_was_interacting", "true", str(interacting), interacting)
	_assert("F2_interaction_stopped", "false", str(_prey.interaction.is_interacting()), not _prey.interaction.is_interacting())
	_assert("F2_no_units_gain", "%d" % units_before, str(rp.units), rp.units == units_before)


# ---------------------------------------------------------------------------
# G 鼠不攻击
# ---------------------------------------------------------------------------

func _section_g_mouse_no_attack() -> void:
	print("---- G 鼠不攻击 ----")
	await _fresh_world({"cat_ai": false})
	if _mouse_cfg == null:
		return
	_assert("G1_mouse_can_attack_false", "false", str(_mouse_cfg.can_attack), not _mouse_cfg.can_attack)
	_assert_near("G1_mouse_damage_0", 0.0, _mouse_cfg.attack_damage, EPS)
	var mouse := (load(BODY) as PackedScene).instantiate() as AnimalBody
	mouse.species_config = _mouse_cfg
	mouse.player_controlled = false
	mouse.position = Vector3(1.0, MOUSE_Y, 0.0)
	_world.add_child(mouse)
	await _advance_frames(SPAWN_FRAMES)
	_assert("G2_no_component", "<null>", str(mouse.attack), mouse.attack == null)
	var req_g2 := mouse.request_attack()
	_assert("G2_request_false", "false", str(req_g2), not req_g2)
	_assert("G2_blocked_species", "species", str(mouse.last_attack_blocked_reason),
		mouse.last_attack_blocked_reason == &"species")
	# 跑一圈鼠 AI：状态名里绝不出现 attack
	mouse.ai_enabled = true
	var mouse_ai := mouse.ai as MouseAI
	_assert("G3_mouse_ai_built", "MouseAI", str(mouse_ai), mouse_ai is MouseAI)
	var saw_attack := false
	var t0 := _now()
	while _now() - t0 < 3.0:
		await physics_frame
		if mouse_ai != null and mouse_ai.state_id() == &"attack":
			saw_attack = true
			break
	_assert("G3_mouse_never_attacks", "false", str(saw_attack), not saw_attack)
	_assert("G3_mouse_state_is_normal", "非空且非 attack", str(mouse_ai.state_id()),
		not str(mouse_ai.state_id()).is_empty() and mouse_ai.state_id() != &"attack")
	mouse.queue_free()
	await _advance_frames(2)


# ---------------------------------------------------------------------------
# H 集成
# ---------------------------------------------------------------------------

func _section_h_integration() -> void:
	print("---- H 集成（真实关卡 / HUD 与 MOV| / 无调试节点）----")
	_free_world()
	await _advance_frames(3)
	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	_assert("H_level_loads", "Node3D", str(level != null), level != null)
	if level == null:
		return
	root.add_child(level)
	await _advance_frames(6)
	var cat_spawn := Vector3.ZERO
	for n in _all_nodes(level):
		if n.is_in_group("spawn_points") and n.has_meta("species") and String(n.get_meta("species")) == "Cat":
			cat_spawn = (n as Node3D).global_position
	_assert("H_cat_spawn_found", "非零", str(cat_spawn), cat_spawn != Vector3.ZERO)

	var cat := (load(BODY) as PackedScene).instantiate() as AnimalBody
	cat.species_config = _cat_cfg
	cat.player_controlled = false
	cat.position = cat_spawn
	level.add_child(cat)
	cat.ai_enabled = true
	await _advance_frames(SPAWN_FRAMES)
	var cat_ai := cat.ai as CatAI
	_assert("H_cat_ai", "CatAI", str(cat_ai), cat_ai is CatAI)
	if cat_ai == null:
		level.queue_free()
		return
	cat_ai.patrol_enabled = false
	cat_ai.attack_enabled = true
	var fwd := -cat.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
	var mouse := (load(BODY) as PackedScene).instantiate() as AnimalBody
	mouse.species_config = _mouse_cfg
	mouse.player_controlled = false
	mouse.ai_enabled = false
	var spot := cat.global_position + fwd * 2.0
	mouse.position = Vector3(spot.x, 0.10, spot.z)
	level.add_child(mouse)
	await _advance_frames(6)

	var hp0: float = mouse.survival.state.health
	var attacked := await _run_seconds(14.0, func() -> bool:
		return cat.attack != null and cat.attack.hit_count >= 1)
	_assert("H1_ai_attacked", "hit_count ≥ 1（%.2f s）" % attacked,
		"%s" % str(cat.attack.hit_count if cat.attack != null else -1),
		cat.attack != null and cat.attack.hit_count >= 1)
	_assert("H1_damage_35", "%.1f" % (hp0 - DAMAGE), "%.1f" % mouse.survival.state.health,
		absf(mouse.survival.state.health - (hp0 - DAMAGE)) <= 0.1)
	_assert("H1_hp_65", "65.0", "%.1f" % mouse.survival.state.health,
		absf(mouse.survival.state.health - 65.0) <= 0.1)

	# H2 把鼠搬到猫身后 1.5 m → 不会隔空打
	var hp_after_h1: float = mouse.survival.state.health
	mouse.global_position = cat.global_position - fwd * 1.5
	mouse.global_position = Vector3(mouse.global_position.x, 0.10, mouse.global_position.z)
	await _advance_frames(4)
	var hits_before: int = cat.attack.hit_count
	await _run_seconds(2.0)
	_assert("H2_no_backstab", "%.1f" % hp_after_h1, "%.1f" % mouse.survival.state.health,
		absf(mouse.survival.state.health - hp_after_h1) <= 0.01)
	_assert("H2_no_extra_hits", "%d" % hits_before, str(cat.attack.hit_count), cat.attack.hit_count == hits_before)

	var level_debug := _count_debug_nodes(level)
	_assert("H4_no_debug_node_in_level", "0", str(level_debug), level_debug == 0)
	level.queue_free()
	await _advance_frames(3)

	# 调试入口：HUD `ai:` 与 `MOV|` 能看到 attack / atk 字段
	var entry := (load(ENTRY) as PackedScene).instantiate() as Node3D
	root.add_child(entry)
	await _advance_frames(10)
	var player := entry.get("player") as AnimalBody
	if player != null:
		player.ai_enabled = true
		await _advance_frames(12)
		var hud := String(entry.call("hud_text"))
		var mov := String(entry.call("mov_line"))
		_assert("H3_hud_has_attack_field", "含 'attack='", _clip(hud), hud.contains("attack="))
		_assert("H3_mov_has_atk_field", "含 'atk='", _clip(mov), mov.contains("atk="))
		_assert("H3_mov_has_atk_hits", "含 'atk_hits='", _clip(mov), mov.contains("atk_hits="))
		_assert("H3_mov_has_atk_miss", "含 'atk_miss='", _clip(mov), mov.contains("atk_miss="))
		_assert("H3_mov_has_atk_state", "含 'atk_state='", _clip(mov), mov.contains("atk_state="))
	entry.queue_free()
	await _advance_frames(3)

	var main: Node = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _advance_frames(4)
	_assert("H4_no_debug_node_in_main", "0", str(_count_debug_nodes(main)), _count_debug_nodes(main) == 0)
	main.queue_free()
	await _advance_frames(2)


func _count_debug_nodes(node: Node) -> int:
	var n := 0
	for x in _all_nodes(node):
		if x.get_script() != null:
			var sp := String((x.get_script() as Script).resource_path)
			if sp.contains("/debug/"):
				n += 1
	return n


# ---------------------------------------------------------------------------
# fixture
# ---------------------------------------------------------------------------

## 建一局：地面 + 猫（AI 默认关）+ 可选猎物。**攻击面用纯几何**（T023/T024 同口径）
func _fresh_world(opts: Dictionary = {}) -> void:
	_free_world()
	await _advance_frames(2)
	_world = Node3D.new()
	_world.name = "T025World"
	root.add_child(_world)
	await _advance_frames(2)
	_add_box(_world, "Ground", Vector3(ARENA, 1.0, ARENA), Vector3(0.0, -0.5, 0.0))
	# 需要"受伤中断交互"的段（F2）自带一个食物点：**SEED(=1)** 才在鼠的 `allowed_food_types` 里。
	# 必须用**场景**实例（`ResourcePoint.new()` 没有碰撞体 → 交互检测找不到它）
	if bool(opts.get("with_food", false)):
		var rp_scene := load(RP_SCENE) as PackedScene
		if rp_scene == null:
			print("MEASURE|f2|skipped|resource_point.tscn missing")
		else:
			var fp := rp_scene.instantiate() as ResourcePoint
			fp.name = "FoodProbe"
			fp.kind = &"food"
			fp.food_type = 1
			fp.interaction_id = "t025_food"
			fp.position = Vector3(2.0, 0.10, 0.0)
			_world.add_child(fp)
			await _advance_frames(2)
	await _advance_frames(2)
	_cat = (load(BODY) as PackedScene).instantiate() as AnimalBody
	_cat.species_config = _cat_cfg
	_cat.player_controlled = false
	_cat.position = Vector3(0.0, CAT_Y, 0.0)
	_world.add_child(_cat)
	_cat.ai_enabled = bool(opts.get("cat_ai", false))
	_cat_ai = _cat.ai as CatAI
	if _cat_ai != null:
		_cat_ai.patrol_enabled = false
		_cat_ai.patrol_radius = 1.0
		if not _cat_ai.state_changed.is_connected(_on_state_changed):
			_cat_ai.state_changed.connect(_on_state_changed)
	await _advance_frames(SPAWN_FRAMES)
	if opts.has("prey_at"):
		_place_prey(opts["prey_at"])
		await _advance_frames(4)


func _free_world() -> void:
	if _prey != null and is_instance_valid(_prey):
		_prey.queue_free()
	_prey = null
	for n in _extras:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	_walls.clear()
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	_cat = null
	_cat_ai = null
	_events.clear()
	_transitions.clear()
	_died_events.clear()
	_changed_events.clear()


## 放/移动猎物（鼠，**AI 关闭**，站着不动）
func _place_prey(point: Vector3) -> AnimalBody:
	var spot := Vector3(point.x, MOUSE_Y, point.z)
	if _prey == null or not is_instance_valid(_prey):
		_prey = (load(BODY) as PackedScene).instantiate() as AnimalBody
		_prey.species_config = _mouse_cfg
		_prey.player_controlled = false
		_prey.ai_enabled = false
		var parent: Node = _world if _world != null else root
		_prey.position = spot
		parent.add_child(_prey)
		return _prey
	_prey.global_position = spot
	_prey.velocity = Vector3.ZERO
	_prey.move_intent = Vector2.ZERO
	return _prey


## 猫的**正前方**偏 `angle_deg`、水平距离 `dist`
func _front(dist: float, angle_deg := 0.0) -> Vector3:
	var basis := _cat.global_transform.basis if _cat != null and is_instance_valid(_cat) else Basis.IDENTITY
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
	var right := basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 1e-8 else Vector3.RIGHT
	var a := deg_to_rad(angle_deg)
	var dir := (fwd * cos(a) + right * sin(a)).normalized()
	var base := _cat.global_position if _cat != null and is_instance_valid(_cat) else Vector3.ZERO
	return base + dir * dist


func _add_box(parent: Node, id: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = id
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


## 在两点之间 `t` 比例处插一片 0.1 m 厚、`width` 宽的墙（用来制造遮挡）
func _add_wall_between(from: Vector3, to: Vector3, t := 0.5, width := 1.0) -> StaticBody3D:
	_wall_seq += 1
	var mid := from.lerp(to, t)
	var wall := _add_box(_world, "Wall_%d" % _wall_seq, Vector3(width, 1.0, 0.1),
		Vector3(mid.x, 0.5, mid.z))
	_extras.append(wall)
	_walls.append(wall)
	return wall


## 夹具里有食物点就用它测"受伤中断交互"（没有则跳过 F2）
func _find_food_point() -> ResourcePoint:
	for n in get_nodes_in_group(&"resource_points"):
		if is_instance_valid(n) and n is ResourcePoint and (n as ResourcePoint).kind == &"food":
			return n as ResourcePoint
	return null


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _hook_attack(atk: AttackSettlement) -> void:
	if not atk.attack_started.is_connected(_on_attack_started):
		atk.attack_started.connect(_on_attack_started)
	if not atk.attack_landed.is_connected(_on_attack_landed):
		atk.attack_landed.connect(_on_attack_landed)
	if not atk.attack_ended.is_connected(_on_attack_ended):
		atk.attack_ended.connect(_on_attack_ended)


func _on_attack_started(target_id: String) -> void:
	_events.append({"kind": "start", "id": target_id})


func _on_attack_landed(target_id: String, damage: float, applied: bool) -> void:
	_events.append({"kind": "land", "id": target_id, "damage": damage, "applied": applied})


func _on_attack_ended(target_id: String, hit: bool) -> void:
	_events.append({"kind": "end", "id": target_id, "hit": hit})


func _on_state_changed(from: StringName, to: StringName, reason: StringName) -> void:
	_transitions.append({"from": String(from), "to": String(to), "reason": String(reason)})


func _count_event(kind: String) -> int:
	var n := 0
	for e in _events:
		if String(e["kind"]) == kind:
			n += 1
	return n


func _last_landed_applied() -> bool:
	for i in range(_events.size() - 1, -1, -1):
		if String(_events[i]["kind"]) == "land":
			return bool(_events[i]["applied"])
	return false


func _last_landed_damage() -> float:
	for i in range(_events.size() - 1, -1, -1):
		if String(_events[i]["kind"]) == "land":
			return float(_events[i]["damage"])
	return -1.0


func _has_transition(to: String, reason: String) -> bool:
	for t in _transitions:
		if String(t["to"]) == to and String(t["reason"]) == reason:
			return true
	return false


func _now() -> float:
	return float(_wd.get("world_time")) if _wd != null else 0.0


func _run_seconds(seconds: float, until: Callable = Callable()) -> float:
	if _wd == null:
		return 0.0
	var t0: float = _now()
	var frames := 0
	var max_frames := int(maxf(240.0, seconds * 240.0))
	while _now() - t0 < seconds and frames < max_frames and not paused:
		if until.is_valid() and bool(until.call()):
			break
		await physics_frame
		frames += 1
	return _now() - t0


func _advance_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _clip(s: String) -> String:
	return s.replace("\n", " | ").substr(0, 90)


func _all_nodes(node: Node) -> Array[Node]:
	if node == null:
		return []
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
