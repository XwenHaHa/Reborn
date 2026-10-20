extends SceneTree
## T028 第一轮概念试玩 —— **自测走查**（`Docs/Tasks/T028.md` §4）
##
## 目的：在**可玩的生态入口**上把两条物种路线各真实走一遍，输出**客观记录**（路线长度/耗时/被发现/受伤/进洞）
## 与 4 条硬判据（W1 猫能捕获 / W2 鼠能进洞 / W3 猫不穿洞 / W4 玩家存活）。
## **本工具不产出"好玩/不好玩"的结论**：真人体验属 U01，记 NOT-RUN。
##
## 驱动方式（D2）：把玩家 `player_controlled = false`（否则 `_read_input()` 每帧把 `move_intent` 覆盖成 Input，
## headless 下就是 0），然后"朝下一个导航路点 `look_at` + `move_intent = (0,-1)`"（D3：走导航路径，不直撞墙）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_t028_walkthrough.gd' --quit-after 300000

const ENTRY := "res://scenes/debug/ecology_entry.tscn"
const CAT_SPECIES := &"Cat"
const MOUSE_SPECIES := &"Mouse"
const SETTLE := 150
const EPS := 1e-3
const POUNCE_RANGE := 1.2          # 进入这个距离就停住再扑（T021：只在地面 Idle 启动）
const MAX_APPROACH_SEC := 45.0
const MAX_SPOT_SEC := 30.0
const MAX_HOLE_SEC := 25.0
const OBSERVE_SEC := 12.0
const HOLE_RADIUS := 0.30          # 关卡 `HideSpot_RootHole` 的 metadata/radius
const PATH_REPLAN_SEC := 0.2

var _checks := 0
var _fails := 0
var _wd: Node = null
var _entry: Node3D = null
var _level: Node3D = null
var _player: AnimalBody = null
var _eco: EcologySpawner = null
var _cat_id: StringName = &""
var _mouse_id: StringName = &""
var _path: PackedVector3Array = PackedVector3Array()
var _path_at := -1.0
var _path_target := Vector3(INF, INF, INF)


func _initialize() -> void:
	print("TEST|tool_t028_walkthrough|engine=%s" % Engine.get_version_info().string)
	_wd = root.get_node_or_null("WorldDirector")
	var cat := await _run_cat_session()
	await _teardown()
	var mouse := await _run_mouse_session()
	await _teardown()
	_assert("W1_cat_captured", "capture_count +1", str(bool(cat.get("caught", false))), bool(cat.get("caught", false)))
	var hole_gap := float(mouse.get("hole_gap", 99.0))
	_assert("W2_mouse_entered_hole", "≤ %.2f m" % HOLE_RADIUS, "%.2f m" % hole_gap, hole_gap <= HOLE_RADIUS + EPS)
	var cat_min := float(mouse.get("cat_min_to_hole", -1.0))
	_assert("W3_cat_never_in_hole", "≥ %.2f m" % HOLE_RADIUS, "%.2f m" % cat_min, cat_min >= 0.0 and cat_min >= HOLE_RADIUS - EPS)
	var alive := bool(cat.get("alive", false)) and bool(mouse.get("alive", false))
	_assert("W4_players_survived", "true", str(alive), alive)
	_finish()


# ---------------------------------------------------------------------------
# 猫 session：发现 → 接近 → 扑击 → 捕获
# ---------------------------------------------------------------------------

func _run_cat_session() -> Dictionary:
	var out := {"session": "cat", "caught": false, "alive": false}
	await _boot(CAT_SPECIES)
	if _player == null or _eco == null or _player.species_config == null:
		print("WALK|cat|ERROR|boot_failed")
		return out
	if _player.species_config.species_id != CAT_SPECIES:
		print("WALK|cat|ERROR|wrong_species=%s" % _player.species_config.species_id)
		return out
	_player.player_controlled = false          # D2
	var start := _player.global_position
	var hp0: float = _player.survival.state.health
	var cap0 := _capture_count()
	var prey: AnimalBody = null
	var gap: float = INF
	for b in _eco.npc_bodies():
		var d := b.global_position.distance_to(_player.global_position)
		if d < gap:
			gap = d
			prey = b
	out["npc_count"] = _eco.npc_count()
	out["spawn_gap"] = gap
	if prey == null:
		print("WALK|cat|ERROR|no_prey")
		return out
	var route := 0.0
	var last := _player.global_position
	var t0 := _now()
	var detect_s := -1.0
	var pounces := 0
	var caught := false
	var prey_states: Array[String] = []
	var prey_min: float = INF
	var pose_frames := 0
	while _now() - t0 < MAX_APPROACH_SEC:
		await physics_frame
		route += _traveled(last, _player.global_position)
		last = _player.global_position
		if detect_s < 0.0 and _player.perception != null and _player.perception.is_threat_visible():
			detect_s = _now() - t0
		if _capture_count() > cap0:
			caught = true
			break
		var d := _player.global_position.distance_to(prey.global_position)
		prey_min = minf(prey_min, d)
		var pst := String(prey.ai.state_id()) if prey.ai != null else ""
		if pst != "" and not prey_states.has(pst):
			prey_states.append(pst)
		if d <= POUNCE_RANGE:
			_player.move_intent = Vector2.ZERO
			_player.want_sprint = false
			pose_frames += 1
			if pose_frames >= 3:                     # 先站定（IDLE）再扑
				_player.look_at(_flat(prey.global_position, _player.global_position.y), Vector3.UP)
				if _player.request_pounce():
					pounces += 1
				await _advance(22)
				pose_frames = 0
		else:
			pose_frames = 0
			_drive_towards(_player, prey.global_position, true)
	if _capture_count() > cap0:
		caught = true
	var straight := start.distance_to(prey.global_position) if prey != null else 0.0
	out["detect_s"] = detect_s
	out["pounces"] = pounces
	out["catch_s"] = (_now() - t0) if caught else -1.0
	out["route_len"] = route
	out["straight_gap"] = straight
	out["ratio"] = route / maxf(0.01, straight)
	out["health_before"] = hp0
	out["health_after"] = _player.survival.state.health
	out["npc_after"] = _eco.npc_count()
	out["alive"] = not _player.survival.is_dead()
	out["caught"] = caught
	out["prey_states"] = prey_states
	out["prey_min_gap"] = prey_min
	print("WALK|cat|npc=%d|spawn_gap=%.2f|detect_s=%.2f|pounces=%d|catch_s=%.2f|route_len=%.2f|straight=%.2f|ratio=%.2f|prey_states=%s|prey_min_gap=%.2f|hp=%.1f->%.1f|npcs_after=%d|caught=%s|alive=%s" % [
		int(out["npc_count"]), gap, detect_s, pounces, float(out["catch_s"]), route, straight,
		float(out["ratio"]), str(prey_states), prey_min, hp0, float(out["health_after"]),
		int(out["npc_after"]), str(caught), str(out["alive"])])
	return out


# ---------------------------------------------------------------------------
# 鼠 session：在场地里走动 → 被猫发现 → 逃向洞口 → 观察猫
# ---------------------------------------------------------------------------

func _run_mouse_session() -> Dictionary:
	var out := {"session": "mouse", "alive": false, "hole_gap": 99.0, "cat_min_to_hole": -1.0}
	await _boot(MOUSE_SPECIES)
	if _player == null or _eco == null or _player.species_config == null:
		print("WALK|mouse|ERROR|boot_failed")
		return out
	if _player.species_config.species_id != MOUSE_SPECIES:
		print("WALK|mouse|ERROR|wrong_species=%s" % _player.species_config.species_id)
		return out
	_player.player_controlled = false          # D2
	var hole := _hole_marker()
	if hole == null:
		print("WALK|mouse|ERROR|no_hole_marker")
		return out
	var hole_point: Vector3 = hole.global_position
	var predator: AnimalBody = null
	for b in _eco.npc_bodies():
		if b.species_config != null and b.species_config.can_attack:
			predator = b
			break
	if predator == null:
		print("WALK|mouse|ERROR|no_predator")
		return out
	var start := _player.global_position
	var hp0: float = _player.survival.state.health
	var route := 0.0
	var route_probe := 0.0
	var last := _player.global_position
	var states: Array[String] = []
	var spotted_s := -1.0
	var spot_point := _player.global_position
	# ① 模拟"在场地上走动"：朝捕食者走，直到被它发现（或已进入 6 m）
	var t0 := _now()
	while _now() - t0 < MAX_SPOT_SEC:
		await physics_frame
		var step := _traveled(last, _player.global_position)
		route += step
		route_probe += step
		last = _player.global_position
		var st := String(predator.ai.state_id()) if predator.ai != null else ""
		if st != "" and not states.has(st):
			states.append(st)
		if spotted_s < 0.0 and (st == "alert" or st == "approach" or st == "chase"):
			spotted_s = _now() - t0
			spot_point = _player.global_position
			break
		if _player.global_position.distance_to(predator.global_position) <= 6.0:
			spot_point = _player.global_position
			break
		_drive_towards(_player, predator.global_position, false)
	# ② 逃向洞口
	var t1 := _now()
	var enter_s := -1.0
	var route_escape := 0.0
	var cat_min := -1.0
	var cat_min_player := -1.0
	while _now() - t1 < MAX_HOLE_SEC:
		await physics_frame
		var esc := _traveled(last, _player.global_position)
		route += esc
		route_escape += esc
		last = _player.global_position
		var ch := predator.global_position.distance_to(hole_point)
		cat_min = ch if cat_min < 0.0 else minf(cat_min, ch)
		var cp := predator.global_position.distance_to(_player.global_position)
		cat_min_player = cp if cat_min_player < 0.0 else minf(cat_min_player, cp)
		if _player.global_position.distance_to(hole_point) <= HOLE_RADIUS:
			enter_s = _now() - t1
			break
		_drive_towards(_player, hole_point, true)
	# ③ 观察猫在洞外
	var t2 := _now()
	var cat_states: Array[String] = []
	var giveups := 0
	while _now() - t2 < OBSERVE_SEC:
		await physics_frame
		_player.move_intent = Vector2.ZERO
		_player.want_sprint = false
		var to_hole := predator.global_position.distance_to(hole_point)
		cat_min = to_hole if cat_min < 0.0 else minf(cat_min, to_hole)
		var to_player := predator.global_position.distance_to(_player.global_position)
		cat_min_player = to_player if cat_min_player < 0.0 else minf(cat_min_player, to_player)
		var st2 := String(predator.ai.state_id()) if predator.ai != null else ""
		if st2 != "" and not cat_states.has(st2):
			cat_states.append(st2)
		if predator.ai != null and predator.ai.has_method("give_up_count"):
			giveups = maxi(giveups, int(predator.ai.call("give_up_count")))
	var hole_gap := _player.global_position.distance_to(hole_point)
	var straight := Vector2(hole_point.x - spot_point.x, hole_point.z - spot_point.z).length()
	out["spotted_s"] = spotted_s
	out["enter_hole_s"] = enter_s
	out["hole_gap"] = hole_gap
	out["route_len"] = route
	out["route_probe"] = route_probe
	out["route_escape"] = route_escape
	out["straight_escape"] = straight
	out["ratio_escape"] = route_escape / maxf(0.01, straight)
	out["cat_min_to_hole"] = cat_min
	out["cat_min_to_player"] = cat_min_player
	out["cat_states"] = cat_states
	out["states_before"] = states
	out["giveups"] = giveups
	out["health_before"] = hp0
	out["health_after"] = _player.survival.state.health
	out["alive"] = not _player.survival.is_dead()
	print("WALK|mouse|spotted_s=%.2f|enter_hole_s=%.2f|hole_gap=%.2f|route=%.2f(probe=%.2f+escape=%.2f)|straight_escape=%.2f|ratio_escape=%.2f|cat_min_to_hole=%.2f|cat_min_to_player=%.2f|cat_states=%s|states_before=%s|giveups=%d|hp=%.1f->%.1f|alive=%s" % [
		spotted_s, enter_s, hole_gap, route, route_probe, route_escape, straight,
		float(out["ratio_escape"]), cat_min, cat_min_player, str(cat_states), str(states),
		giveups, hp0, float(out["health_after"]), str(out["alive"])])
	return out


# ---------------------------------------------------------------------------
# fixture：启动 / 拆除 / 导航驱动
# ---------------------------------------------------------------------------

func _boot(species_id: StringName) -> void:
	_entry = (load(ENTRY) as PackedScene).instantiate() as Node3D
	root.add_child(_entry)
	await _advance(SETTLE)
	_cat_id = (_entry.get("cat_config") as SpeciesConfig).species_id
	_mouse_id = (_entry.get("mouse_config") as SpeciesConfig).species_id
	if species_id != &"":
		_entry.call("switch_species", species_id)
		await _advance(SETTLE)
	_level = _entry.get("level") as Node3D
	_player = _entry.get("player") as AnimalBody
	_eco = _entry.get("ecology") as EcologySpawner
	if _player != null and _player.species_config != null:
		print("WALK|boot|requested=%s|player=%s|npcs=%d|eco_ready=%s" % [
			str(species_id), str(_player.species_config.species_id),
			_eco.npc_count() if _eco != null else -1,
			str(_eco.is_setup_done()) if _eco != null else "n/a"])
	_path = PackedVector3Array()
	_path_at = -1.0
	_path_target = Vector3(INF, INF, INF)


func _teardown() -> void:
	if _entry != null and is_instance_valid(_entry):
		_entry.queue_free()
	_entry = null
	_level = null
	_player = null
	_eco = null
	await _advance(4)


## 朝目标驱动：沿**按物种导航层**算出的路径走（D3），可开 sprint。
func _drive_towards(actor: AnimalBody, target: Vector3, sprint: bool) -> void:
	var next := _next_waypoint(actor, target)
	var to := next - actor.global_position
	to.y = 0.0
	if to.length() < 0.05:
		actor.move_intent = Vector2.ZERO
		return
	actor.look_at(actor.global_position + to.normalized(), Vector3.UP)
	actor.move_intent = Vector2(0.0, -1.0)
	actor.want_sprint = sprint


func _next_waypoint(actor: AnimalBody, target: Vector3) -> Vector3:
	var t := _now()
	var need := _path.is_empty() or _path_target.distance_to(target) > 0.5 or t - _path_at > PATH_REPLAN_SEC
	if need:
		_path = _layer_path(actor, target)
		_path_at = t
		_path_target = target
	for p in _path:
		var flat := Vector2(p.x - actor.global_position.x, p.z - actor.global_position.z).length()
		if flat > 0.30:
			return p
	return target


func _layer_path(actor: AnimalBody, target: Vector3) -> PackedVector3Array:
	var map := _nav_map()
	if not map.is_valid() or _entry == null or actor.species_config == null:
		return PackedVector3Array()
	var layer := int(_entry.call("nav_layer_for", actor.species_config.species_id))
	return NavigationServer3D.map_get_path(map, actor.global_position, target, true, maxi(1, layer))


func _nav_map() -> RID:
	if _level == null or _level.get_world_3d() == null:
		return RID()
	return _level.get_world_3d().get_navigation_map()


func _hole_marker() -> Node3D:
	for n in get_nodes_in_group(&"hide_spots"):
		if n is Node3D and n.has_meta("kind") and String(n.get_meta("kind")) == "mouse_hole":
			return n as Node3D
	return null


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _flat(p: Vector3, y: float) -> Vector3:
	return Vector3(p.x, y, p.z)


func _traveled(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


func _capture_count() -> int:
	return int(_wd.get("capture_count")) if _wd != null else -1


func _now() -> float:
	return float(_wd.get("world_time")) if _wd != null else 0.0


func _advance(n: int) -> void:
	for i in n:
		await physics_frame


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
