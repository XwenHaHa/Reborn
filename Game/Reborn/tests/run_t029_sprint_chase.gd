extends SceneTree
## T029 猫 AI 追击冲刺（`Docs/Tasks/T029.md` §4）
##
## 验证 `CatAI` 只在 `CHASE` 且**水平距离 > chase_sprint_min_gap** 时置 `body.want_sprint = true`，
## 其余状态一律不冲刺；再实测"冲刺真的更快"与"体力不足自动降速且不崩"。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t029_sprint_chase.gd' --quit-after 300000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const CAT_AI := "res://scripts/ai/cat_ai.gd"

const EPS := 1e-3
const ARENA := 40.0
const CAT_Y := 0.25
const MOUSE_Y := 0.10
const SPAWN_FRAMES := 12
const ALERT_SEC := 0.45
const DEFAULT_MIN_GAP := 3.0      # T029：刹车余量（≥1.7）+ 给鼠 sprint 留反应带（2.0 m 时鼠会被打死）
const ATTACK_RANGE := 0.65
const RANGE_HYSTERESIS := 0.05

var _checks := 0
var _fails := 0
var _cat_cfg: SpeciesConfig = null
var _mouse_cfg: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null
var _region: NavigationRegion3D = null
var _npc: AnimalBody = null
var _ai: CatAI = null
var _prey: AnimalBody = null


func _initialize() -> void:
	print("TEST|run_t029_sprint_chase|engine=%s" % Engine.get_version_info().string)
	_cat_cfg = load(CAT) as SpeciesConfig
	_mouse_cfg = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")
	await _section_a_contract()
	await _section_b_state_gating()
	await _section_c_speed()
	await _section_d_stamina()
	_finish()


# ---------------------------------------------------------------------------
# A 接口与参数
# ---------------------------------------------------------------------------

func _section_a_contract() -> void:
	print("---- A 接口与参数 ----")
	var script := load(CAT_AI) as Script
	_assert("A1_cat_ai_script_exists", "非 null", str(script != null), script != null)
	if script == null:
		return
	var probe: Object = script.new()
	_assert("A2_is_cat_ai", "CatAI", str(probe is CatAI), probe is CatAI)
	if not (probe is CatAI):
		return
	var ai := probe as CatAI
	_assert("A3_chase_sprint_enabled_default_off", "false（平衡待定，默认关）", str(ai.chase_sprint_enabled),
		not ai.chase_sprint_enabled)
	_assert_near("A4_chase_sprint_min_gap_default", DEFAULT_MIN_GAP, ai.chase_sprint_min_gap, EPS)
	# 近身收步要做到：min_gap 必须**大于**攻击距离 + 迟滞，否则"贴脸还在冲刺"
	_assert("A5_min_gap_above_attack_reach", "> %.2f" % (ATTACK_RANGE + RANGE_HYSTERESIS),
		"%.2f" % ai.chase_sprint_min_gap,
		ai.chase_sprint_min_gap > ATTACK_RANGE + RANGE_HYSTERESIS)
	_assert("A6_attack_range_wired", "%.2f" % ATTACK_RANGE, "%.2f" % ai.attack_range,
		absf(ai.attack_range - ATTACK_RANGE) <= EPS)
	# 源码事实：冲刺意图只在 `_step_chase` 里被置真，且 `_step` 每帧先清
	var src := _read_source(CAT_AI)
	_assert("A7_source_sets_want_sprint", "1 次（集中在 `_sprint_gate`）", str(src.count("body.want_sprint = true")),
		src.count("body.want_sprint = true") == 1)
	_assert("A8_source_clears_want_sprint", "1 次", str(src.count("body.want_sprint = false")),
		src.count("body.want_sprint = false") == 1)
	var clear_at := src.find("body.want_sprint = false")
	var set_at := src.find("body.want_sprint = true")
	_assert("A9_clear_before_set", "清在置前", "%d < %d" % [clear_at, set_at],
		clear_at >= 0 and set_at > clear_at)
	# 物种确实"能跑得比走快"（否则冲刺没意义）
	_assert("A10_cat_sprint_faster_than_walk", "sprint > walk",
		"%.2f > %.2f" % [_cat_cfg.sprint_speed, _cat_cfg.walk_speed],
		_cat_cfg.sprint_speed > _cat_cfg.walk_speed)
	_assert("A11_cat_sprint_min_stamina", "> 0", "%.2f" % _cat_cfg.sprint_min_stamina,
		_cat_cfg.sprint_min_stamina > 0.0)
	probe.free()


# ---------------------------------------------------------------------------
# B 状态门控（真跑：EXPLORE / ALERT / APPROACH / CHASE 远 / CHASE 近 / SEARCH）
# ---------------------------------------------------------------------------

func _section_b_state_gating() -> void:
	print("---- B 状态门控 ----")
	await _fresh_world()
	if _npc == null or _ai == null:
		_assert("B0_cat_ai_ready", "有 CatAI", "null", false)
		return
	# B1 EXPLORE（猎物还没被看见）
	await _advance_frames(6)
	_assert("B1_state_explore", "explore", String(_ai.state_id()), String(_ai.state_id()) == "explore")
	var explore := await _sample_seconds(0.4)
	_assert("B2_explore_no_sprint", "全 false", "true 帧=%d" % int(explore["true_frames"]),
		int(explore["true_frames"]) == 0)
	# B3 ALERT（鼠放在正前方 6 m，进入视野）
	_place_prey(_front(6.0))
	await _advance_frames(2)
	var seen_alert := false
	var t0 := _now()
	while _now() - t0 < 1.2:
		await physics_frame
		if String(_ai.state_id()) == "alert":
			seen_alert = true
			break
	_assert("B3_state_alert_seen", "true", str(seen_alert), seen_alert)
	if seen_alert:
		var alert2 := await _sample_seconds(0.2)
		_assert("B4_alert_no_sprint", "全 false", "true 帧=%d" % int(alert2["true_frames"]),
			int(alert2["true_frames"]) == 0)
	else:
		_assert("B4_alert_no_sprint", "全 false", "未进入 alert（跳过）", false)
	# B5 进入 CHASE：先等到 APPROACH，再让猎物**跳变** > chase_trigger_move（0.5 m）
	var appr := await _run_until(StringName("approach"), 3.0)
	_assert("B4b_state_approach", "approach", "%s（%.2f s）" % [str(_ai.state_id()), appr],
		String(_ai.state_id()) == "approach")
	# T029 实测修正：`APPROACH` 在**远距离**同样冲刺（猫几乎不进 CHASE，只让 CHASE 冲刺等于没改）
	var approach := await _sample_seconds(0.3)
	_assert("B4c_approach_far_sprint_true", "true 帧 > 0", "true 帧=%d / gap=%.2f" % [
		int(approach["true_frames"]), float(approach["min_gap"])],
		int(approach["true_frames"]) > 0 and float(approach["min_gap"]) > DEFAULT_MIN_GAP)
	# 近距（1.0 m > 0.70 停步线，<= 1.2 门控）不冲刺
	_place_prey(_front(1.0))
	await _advance_frames(4)
	var approach_near := await _sample_seconds(0.25)
	_assert("B4d_near_no_sprint", "全 false", "true 帧=%d / gap=%.2f" % [
		int(approach_near["true_frames"]), float(approach_near["max_gap"])],
		int(approach_near["true_frames"]) == 0)
	_place_prey(_front(8.0))
	await _advance_frames(3)
	var gate := await _run_until(StringName("chase"), 4.0)
	_assert("B5_state_chase_reached", "chase", "%s（%.2f s）" % [str(_ai.state_id()), gate],
		String(_ai.state_id()) == "chase")
	if String(_ai.state_id()) != "chase":
		return
	# B6 CHASE 且远（> 1.2 m）→ 冲刺
	var far_pos := _front(8.0)
	_place_prey(far_pos)
	await _advance_frames(2)
	var far := await _sample_seconds(0.5)
	_assert("B6_chase_far_sprint_true", "true 帧 > 0", "true 帧=%d / %d" % [int(far["true_frames"]), int(far["frames"])],
		int(far["true_frames"]) > 0)
	_assert("B7_chase_far_gap", "> %.2f" % DEFAULT_MIN_GAP, "%.2f" % float(far["min_gap"]),
		float(far["min_gap"]) > DEFAULT_MIN_GAP)
	# B8 CHASE 且近（1.0 m：> 攻击距离 0.70 但 <= min_gap 1.2）→ 不冲刺
	_place_prey(_front(1.0))
	await _advance_frames(2)
	var near := await _sample_seconds(0.4)
	_assert("B8_chase_near_no_sprint", "全 false", "true 帧=%d" % int(near["true_frames"]),
		int(near["true_frames"]) == 0)
	_assert("B9_chase_near_gap", "<= %.2f" % DEFAULT_MIN_GAP, "%.2f" % float(near["max_gap"]),
		float(near["max_gap"]) <= DEFAULT_MIN_GAP + 0.05)
	# B10 开关关掉 → CHASE 里也不冲刺
	_ai.chase_sprint_enabled = false
	_place_prey(_front(8.0))
	await _advance_frames(2)
	var off := await _sample_seconds(0.5)
	_assert("B10_toggle_off_no_sprint", "全 false", "true 帧=%d" % int(off["true_frames"]),
		int(off["true_frames"]) == 0)
	_ai.chase_sprint_enabled = true
	# B11 SEARCH：把猎物藏到看不见的地方（猫身后 15 m 外 + 墙）
	await _enter_search()
	var search := await _sample_seconds(0.8)
	_assert("B11_state_search", "search", String(_ai.state_id()), String(_ai.state_id()) == "search")
	# T029 实测修正：搜索**赶路**阶段（离快照点还远）也冲刺 —— 否则猫还是追不上 sprint 3.0 的鼠
	_assert("B12_search_sprint_when_far", "true 帧 > 0 且 gap > 门控",
		"true 帧=%d / max_gap=%.2f" % [int(search["true_frames"]), float(search["max_gap"])],
		int(search["true_frames"]) > 0 and float(search["max_gap"]) > DEFAULT_MIN_GAP)


# ---------------------------------------------------------------------------
# C 速度对照（真跑位移速率）
# ---------------------------------------------------------------------------

func _section_c_speed() -> void:
	print("---- C 速度对照 ----")
	await _fresh_world()
	if _npc == null or _ai == null:
		_assert("C0_cat_ai_ready", "有 CatAI", "null", false)
		return
	var reached := await _drive_to_chase()
	_assert("C1_state_chase_reached", "chase", "%s" % str(_ai.state_id()), reached)
	if not reached:
		return
	# 把猎物放远，测 1 s 内的水平位移速率（冲刺开）
	# 7 m：**必须 < 猫视距 9.0**（12 m 会失视转 SEARCH，测到的就不是追击了）；1 s 冲刺 4.5 m 后仍 > 0.70 停步区
	_place_prey(_front(7.0))
	await _advance_frames(3)
	var rate_sprint := await _measure_rate(1.0)
	_assert("C2_sprint_rate_above_walk", "> %.2f" % _cat_cfg.walk_speed,
		"%.2f m/s" % rate_sprint, rate_sprint > _cat_cfg.walk_speed + 0.05)
	_assert("C3_sprint_rate_not_above_max", "<= %.2f" % _cat_cfg.sprint_speed,
		"%.2f m/s" % rate_sprint, rate_sprint <= _cat_cfg.sprint_speed + 0.05)
	# 同一场景关掉冲刺 → 速率回落到走速量级
	await _fresh_world()
	_ai.chase_sprint_enabled = false
	var reached_walk := await _drive_to_chase()
	_assert("C4b_walk_chase_reached", "chase", "%s" % str(_ai.state_id()), reached_walk)
	if not reached_walk:
		return
	_place_prey(_front(7.0))
	await _advance_frames(3)
	var rate_walk := await _measure_rate(1.0)
	_assert("C4_walk_rate_band", "%.2f ~ %.2f" % [_cat_cfg.walk_speed - 0.4, _cat_cfg.walk_speed + 0.4],
		"%.2f m/s" % rate_walk, absf(rate_walk - _cat_cfg.walk_speed) <= 0.4)
	_assert("C5_sprint_faster_than_walk_run", "> walk", "%.2f > %.2f" % [rate_sprint, rate_walk],
		rate_sprint > rate_walk + 0.3)
	_assert("C6_ratio_reasonable", ">= 1.5", "%.2f" % (rate_sprint / maxf(0.01, rate_walk)),
		rate_sprint / maxf(0.01, rate_walk) >= 1.5)


# ---------------------------------------------------------------------------
# D 体力门控（AI 只管"想不想"，能不能由 AnimalBody 决定）
# ---------------------------------------------------------------------------

func _section_d_stamina() -> void:
	print("---- D 体力门控 ----")
	await _fresh_world()
	if _npc == null or _ai == null:
		_assert("D0_cat_ai_ready", "有 CatAI", "null", false)
		return
	_place_prey(_front(6.0))
	await _advance_frames(2)
	var reached := await _drive_to_chase()
	_assert("D1_state_chase_reached", "chase", "%s" % str(_ai.state_id()), reached)
	if not reached:
		return
	# 体力压到门槛以下：AI 仍然"想冲"，但身体不该真的跑快
	_npc.survival.state.stamina = maxf(0.0, _cat_cfg.sprint_min_stamina - 1.0)
	_place_prey(_front(7.0))
	await _advance_frames(3)
	var low := await _sample_seconds(0.4)
	_assert("D2_ai_still_wants_sprint", "true 帧 > 0", "true 帧=%d" % int(low["true_frames"]),
		int(low["true_frames"]) > 0)
	var rate_low := await _measure_rate(1.0)
	_assert("D3_low_stamina_slow", "<= %.2f" % (_cat_cfg.walk_speed + 0.4),
		"%.2f m/s" % rate_low, rate_low <= _cat_cfg.walk_speed + 0.4)
	_assert("D4_body_alive_and_valid", "true", str(is_instance_valid(_npc) and not _npc.survival.is_dead()),
		is_instance_valid(_npc) and not _npc.survival.is_dead())
	_assert("D5_ai_state_stable", "非空", String(_ai.state_id()), String(_ai.state_id()) != "")
	# 体力回满 → 恢复冲刺速率
	_npc.survival.state.stamina = _cat_cfg.max_stamina if _cat_cfg.max_stamina > 0.0 else 100.0
	_place_prey(_front(7.0))
	await _advance_frames(3)
	var rate_ok := await _measure_rate(1.0)
	_assert("D6_stamina_back_sprint", "> %.2f" % (_cat_cfg.walk_speed + 0.05),
		"%.2f m/s" % rate_ok, rate_ok > _cat_cfg.walk_speed + 0.05)


# ---------------------------------------------------------------------------
# 夹具
# ---------------------------------------------------------------------------

func _fresh_world() -> void:
	_free_world()
	await _advance_frames(2)
	_world = Node3D.new()
	_world.name = "T029World"
	root.add_child(_world)
	await _advance_frames(2)
	_region = NavigationRegion3D.new()
	_region.name = "CatRegion"
	_region.navigation_mesh = _make_navmesh()
	_region.navigation_layers = 2
	_region.set_meta("species_id", "Cat")
	_world.add_child(_region)
	_add_box(_region, "ArenaGround", Vector3(ARENA, 1.0, ARENA), Vector3(0.0, -0.5, 0.0))
	await _advance_frames(2)
	_region.bake_navigation_mesh(false)
	await _advance_frames(8)

	_npc = (load(BODY) as PackedScene).instantiate() as AnimalBody
	_npc.species_config = _cat_cfg
	_npc.player_controlled = false
	_npc.position = Vector3(0.0, CAT_Y, 0.0)
	_world.add_child(_npc)
	_npc.ai_enabled = true
	_ai = _npc.ai as CatAI
	if _ai != null:
		_ai.patrol_enabled = false       # 只看追击，不需要巡游
	_ai.attack_enabled = false       # 近距离停住即可（攻击属 T025）
	# 默认是**关**（平衡待定，见 `Docs/Evidence/T029.md`）；本套件要验证能力本身，所以显式打开
	_ai.chase_sprint_enabled = true
	await _advance_frames(SPAWN_FRAMES)


func _free_world() -> void:
	if _prey != null and is_instance_valid(_prey):
		_prey.queue_free()
	_prey = null
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	_region = null
	_npc = null
	_ai = null


func _place_prey(point: Vector3) -> AnimalBody:
	var spot := Vector3(point.x, MOUSE_Y, point.z)
	if _prey == null or not is_instance_valid(_prey):
		_prey = (load(BODY) as PackedScene).instantiate() as AnimalBody
		_prey.species_config = _mouse_cfg
		_prey.player_controlled = false
		_prey.position = spot
		(_world if _world != null else root).add_child(_prey)
		return _prey
	_prey.global_position = spot
	_prey.velocity = Vector3.ZERO
	_prey.move_intent = Vector2.ZERO
	return _prey


func _front(dist: float) -> Vector3:
	var basis := _npc.global_transform.basis if _npc != null and is_instance_valid(_npc) else Basis.IDENTITY
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
	var base := _npc.global_position if _npc != null and is_instance_valid(_npc) else Vector3.ZERO
	return base + fwd * dist


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


func _make_navmesh() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.17
	nm.agent_height = 0.50
	nm.agent_max_climb = 0.12
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.03
	nm.cell_height = 0.03
	nm.region_min_size = 0.02
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	return nm


## 把猫带到 `CHASE`：先放正前方 6 m（进视野 → alert → approach），再**瞬移** > 0.5 m 触发"猎物跳变"。
## （T024：`CHASE` 只在猎物跳变或搜索中重新发现时进入，光靠"看见"只会停在 `APPROACH`）
func _drive_to_chase() -> bool:
	_place_prey(_front(6.0))
	await _advance_frames(3)
	var t0 := _now()
	while _now() - t0 < 4.0:
		await physics_frame
		if _ai == null or not is_instance_valid(_ai):
			return false
		var st := String(_ai.state_id())
		if st == "approach" or st == "chase":
			break
	if String(_ai.state_id()) == "chase":
		return true
	_place_prey(_front(8.0))
	await _advance_frames(3)
	t0 = _now()
	while _now() - t0 < 4.0:
		await physics_frame
		if _ai == null or not is_instance_valid(_ai):
			return false
		if String(_ai.state_id()) == "chase":
			return true
	return false
## 把猎物挪到猫视线外，逼出 `SEARCH`（跳变 + 遮挡都避免，靠"看不见"）
func _enter_search() -> void:
	var behind := _npc.global_position - _front_dir() * 15.0
	_place_prey(behind)
	await _advance_frames(2)
	var t0 := _now()
	while _now() - t0 < 3.0:
		await physics_frame
		var st := String(_ai.state_id())
		if st == "search":
			return


func _front_dir() -> Vector3:
	var fwd := -_npc.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD


# ---------------------------------------------------------------------------
# 采样与辅助
# ---------------------------------------------------------------------------

## 在 `seconds` 内每物理帧采样 `want_sprint` 与水平距离
func _sample_seconds(seconds: float) -> Dictionary:
	var frames := 0
	var true_frames := 0
	var min_gap := INF
	var max_gap := 0.0
	var t0 := _now()
	while _now() - t0 < seconds:
		await physics_frame
		frames += 1
		if _npc == null or not is_instance_valid(_npc):
			break
		if _npc.want_sprint:
			true_frames += 1
		if _prey != null and is_instance_valid(_prey):
			var g := Vector2(_npc.global_position.x - _prey.global_position.x,
				_npc.global_position.z - _prey.global_position.z).length()
			min_gap = minf(min_gap, g)
			max_gap = maxf(max_gap, g)
	return {"frames": frames, "true_frames": true_frames,
		"min_gap": min_gap if min_gap < INF else -1.0, "max_gap": max_gap}


## 测 `seconds` 内的**水平**位移速率（m/s）
func _measure_rate(seconds: float) -> float:
	if _npc == null or not is_instance_valid(_npc):
		return -1.0
	var start := _npc.global_position
	var t0 := _now()
	var frames := 0
	while _now() - t0 < seconds:
		await physics_frame
		frames += 1
	var moved := Vector2(_npc.global_position.x - start.x, _npc.global_position.z - start.z).length()
	var dt := _now() - t0
	if dt <= 0.0001:
		return -1.0
	return moved / dt


## 跑到指定状态（或超时），返回耗时
func _run_until(state: StringName, timeout: float) -> float:
	var t0 := _now()
	while _now() - t0 < timeout:
		await physics_frame
		if _ai == null or not is_instance_valid(_ai):
			return -1.0
		if _ai.state_id() == state:
			return _now() - t0
	return _now() - t0


func _read_source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _now() -> float:
	return float(_wd.get("world_time")) if _wd != null else 0.0


func _advance_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	_assert(id, "%.4f±%.4f" % [expected, eps], "%.4f" % actual, absf(expected - actual) <= eps)


func _finish() -> void:
	_free_world()
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
