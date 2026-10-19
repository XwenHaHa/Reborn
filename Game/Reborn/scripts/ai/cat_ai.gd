class_name CatAI
extends AnimalAI
## T023 猫 NPC：**巡游 → 发现 → 警戒 → 接近**
##
## 设计约束（`Docs/Tasks/T023.md`）：
## - **复用**既有机制：`Perception`（物种无关：威胁 = 异种且存活的身体）与 `AnimalAI`（状态/世界时间/导航/失败回退）。
##   本脚本**不实现感知算法、不写物种名分支、不直接改位移**（只写 `body.move_intent`）。
## - 只做"巡游 / 发现 / 警戒 / 接近"；**追击与搜索属 T024，攻击与伤害结算属 T025**（本任务到 0.65 m 就停住，不扑击）。
## - 参数真源：`Docs/Parameters.md` 第 22/23 行（视距 / 半角 / 听觉走**物种配置** `cat.tres`）、
##   第 69 行（猫 NPC：**Alert 0.4 s**、**AttackRange 65**）、第 73 行（Loudness、草丛、近距豁免）。
## - **失视后不得读取真实坐标导航**：只在看得见时更新目的地；失视即警戒 → 回 `EXPLORE`（T024 会把它改成 `SEARCH`）。

## 看见猎物（"发现"）：只报告，不改位移
signal prey_spotted(prey_id: String, position: Vector3)
## 失视（要么被遮挡、要么跑远）
signal prey_lost(prey_id: String)

const PATROL_GROUP := &"patrol_points"
## 组里没有巡逻点时的环形候选个数（确定顺序：`i × 45°`）
const RING_CANDIDATES := 8
## "停住"的迟滞：比 `attack_range` 近 5 cm 才算退出 `in_range`，避免在边界反复进出
const RANGE_HYSTERESIS := 0.05

## `Parameters.md` 第 69 行：猫 NPC Alert 0.4 s（基类默认 0.3 s 是鼠的，`setup()` 里覆盖）
@export var npc_alert_time: float = 0.4
## `Parameters.md` 第 69 行：AttackRange 65 cm。**T023 只用它决定"接近到哪里停"**，伤害结算属 T025
@export var attack_range: float = 0.65
## 关掉巡游 → 原地待命（**调试 / 夹具用**；真实关卡由生成的一方决定）
@export var patrol_enabled: bool = true
# 以下 5 个是 T023 新增的**实现默认值**（`Parameters.md` 无对应行 → 记入 Evidence 开放项，待负责人并入正式起测值）
@export var patrol_radius: float = 6.0
@export var patrol_pause: float = 1.0
@export var patrol_min_move: float = 0.5
@export var patrol_retry_wait: float = 1.0
@export var approach_repath_interval: float = 0.5

var _patrol_ids: Array[String] = []
var _patrol_index := 0
var _patrol_target_id := ""
var _patrol_pause_until := 0.0
var _patrol_retry_at := 0.0
var _patrol_reached := 0
var _detect_count := 0
var _approach_count := 0
var _lost_sight_count := 0
var _approach_dist := INF
## 当前这次警戒是不是因为"看见"起的（决定警戒结束后回 EXPLORE 时记不记一次失视）
var _alert_from_sight := false
var _last_reacted_noise := 0.0
var _last_repath_at := -1000.0
var _prey_id := ""


# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------

func setup(p_body: AnimalBody) -> void:
	super(p_body)
	if npc_alert_time > 0.0:
		alert_max_time = npc_alert_time
	change_state(State.EXPLORE, &"boot")


# ---------------------------------------------------------------------------
# 行为（子类覆盖点）
# ---------------------------------------------------------------------------

func _step(world_time: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	# 1) 失败等待：停住（基类到点会回 EXPLORE，**不永久阻塞**）
	if _state == State.WAIT:
		body.move_intent = Vector2.ZERO
		return
	# 2) 警戒：停手停脚（基类 `_on_alert_started()` 已清意图并取消交互）
	if _state == State.ALERT:
		body.move_intent = Vector2.ZERO
		return
	# 3) 感知 → 警戒 / 失视
	_react_to_senses(world_time)
	if _state == State.ALERT or _has_alert:
		body.move_intent = Vector2.ZERO
		return
	# 4) 接近
	if _state == State.APPROACH:
		_step_approach(world_time)
		return
	# 5) 巡游
	_step_patrol(world_time)


## 把"看见 / 听见"翻译成状态变化。**本函数不改位移**，只调 `alert_for()`。
func _react_to_senses(world_time: float) -> void:
	var p := _perception()
	if p == null:
		return
	if p.is_threat_visible():
		if _state == State.APPROACH:
			return          # 接近中且看得见 → 交给 `_step_approach`
		if not _has_alert:
			_alert_from_sight = true
			_detect_count += 1
			_prey_id = p.threat_id()
			_approach_dist = horizontal_distance_to(p.threat_position())
			prey_spotted.emit(_prey_id, p.threat_position())
			alert_for(p.threat_position(), &"saw_prey")
		return
	# 看不见了
	if _state == State.APPROACH:
		_alert_from_sight = true
		alert_for(p.last_seen_position(), &"lost_sight")
		return
	# 只听见声音：警戒到**发生位置**（不跟踪声源真实位置，`TechnicalDesign` §6）
	var noise_time := p.last_noise_time()
	if noise_time > _last_reacted_noise:
		_last_reacted_noise = noise_time
		_alert_from_sight = false
		alert_for(p.last_noise_position(), &"heard_noise")


## 警戒结束：看得见就接近；看不见就回探索（**T024 会把它改成 SEARCH**）
func _on_alert_ended(world_time: float) -> void:
	var p := _perception()
	if p != null and p.is_threat_visible():
		_enter_approach(world_time, &"alert_done")
		return
	_clear_destination()
	if body != null and is_instance_valid(body):
		body.move_intent = Vector2.ZERO
	if _alert_from_sight:
		_alert_from_sight = false
		_lost_sight_count += 1
		if not _prey_id.is_empty():
			prey_lost.emit(_prey_id)
		change_state(State.EXPLORE, &"lost_sight")
		return
	change_state(State.EXPLORE, &"alert_done")


## 进入接近：清掉巡游目的地，节流计时归零
func _enter_approach(world_time: float, reason: StringName) -> void:
	_clear_destination()
	_last_repath_at = -1000.0
	_approach_count += 1
	change_state(State.APPROACH, reason)


## 接近：只在**看得见**时更新目的地（不追实时坐标）；到 `attack_range` 停住，**不扑击**
func _step_approach(world_time: float) -> void:
	var p := _perception()
	if p == null or not p.is_threat_visible():
		return
	var prey_pos := p.threat_position()
	_approach_dist = horizontal_distance_to(prey_pos)
	if _approach_dist <= attack_range + RANGE_HYSTERESIS:
		body.move_intent = Vector2.ZERO
		_clear_destination()
		set_reason(&"in_range")
		return
	if not _has_destination or world_time - _last_repath_at >= approach_repath_interval:
		_last_repath_at = world_time
		if not _set_destination(prey_pos):
			_register_path_failure(world_time)
			return
		set_reason(&"closing")
	_advance_along_path()
	_track_progress(world_time)


# ---------------------------------------------------------------------------
# 巡游
# ---------------------------------------------------------------------------

func _step_patrol(world_time: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not patrol_enabled:
		body.move_intent = Vector2.ZERO
		_clear_destination()
		if _state != State.EXPLORE:
			change_state(State.EXPLORE, &"patrol_off")
		else:
			set_reason(&"patrol_off")
		return
	if world_time < _patrol_pause_until:
		body.move_intent = Vector2.ZERO
		set_reason(&"patrol_pause")
		return
	if not _has_destination:
		_pick_patrol_target(world_time)
		if not _has_destination:
			body.move_intent = Vector2.ZERO
			return
	if body.global_position.distance_to(_destination) <= patrol_arrive_radius():
		_patrol_reached += 1
		_patrol_pause_until = world_time + patrol_pause
		_patrol_index += 1
		_patrol_target_id = ""      # 到点后**不再声称**还在去这个点（"可查看"要诚实）
		_clear_destination()
		body.move_intent = Vector2.ZERO
		change_state(State.EXPLORE, &"patrol_reached")
		return
	if _state != State.EXPLORE:
		change_state(State.EXPLORE, &"patrol_moving")
	else:
		set_reason(&"patrol_moving")
	_advance_along_path()
	_track_progress(world_time)


## 到达判定（比基类 `reach_tolerance` 略保守）
func patrol_arrive_radius() -> float:
	return maxf(0.15, reach_tolerance)


## 选下一个巡游点：① 组 `patrol_points`（按名字排序、循环）② 组为空 → 环上第一个**可达**点
## 都不可达 → 走基类失败口径（记录 + 可能进 `WAIT`），**不永久阻塞、不每帧重选**
func _pick_patrol_target(world_time: float) -> void:
	if world_time < _patrol_retry_at:
		return
	_refresh_patrol_ids()
	if not _patrol_ids.is_empty():
		var count := _patrol_ids.size()
		for i in count:
			var idx := (_patrol_index + i) % count
			var node := _patrol_node(_patrol_ids[idx])
			if node == null:
				continue
			var point := _patrol_point(node)
			if not reachable(point):
				continue
			_patrol_index = idx
			_patrol_target_id = _patrol_ids[idx]
			if _set_destination(point):
				return
		_register_path_failure(world_time)
		_patrol_retry_at = world_time + patrol_retry_wait
		return
	for i in RING_CANDIDATES:
		var angle := TAU * float(i) / float(RING_CANDIDATES)
		var point := body.global_position + Vector3(cos(angle), 0.0, sin(angle)) * patrol_radius
		point = _ground_point_under(point)
		if point.distance_to(body.global_position) <= patrol_min_move:
			continue
		if not reachable(point):
			continue
		_patrol_target_id = "ring_%d" % i
		if _set_destination(point):
			return
	_register_path_failure(world_time)
	_patrol_retry_at = world_time + patrol_retry_wait


func _refresh_patrol_ids() -> void:
	_patrol_ids.clear()
	if get_tree() == null:
		return
	var ids: Array[String] = []
	for n in get_tree().get_nodes_in_group(PATROL_GROUP):
		if n == null or not is_instance_valid(n):
			continue
		ids.append(_patrol_id_of(n))
	ids.sort()      # 确定性：不依赖场景树顺序
	_patrol_ids = ids


func _patrol_id_of(node: Node) -> String:
	if node.has_meta("patrol_id"):
		return str(node.get_meta("patrol_id"))
	return String(node.name)


func _patrol_node(id: String) -> Node3D:
	if get_tree() == null:
		return null
	for n in get_tree().get_nodes_in_group(PATROL_GROUP):
		if n == null or not is_instance_valid(n):
			continue
		if _patrol_id_of(n) == id:
			return n as Node3D
	return null


func _patrol_point(node: Node3D) -> Vector3:
	return _ground_point_under(node.global_position)


# ---------------------------------------------------------------------------
# 查询（"状态和原因可查看"）
# ---------------------------------------------------------------------------

func _perception() -> Perception:
	if body == null or not is_instance_valid(body):
		return null
	return body.perception


func horizontal_distance_to(point: Vector3) -> float:
	if body == null or not is_instance_valid(body):
		return INF
	var d := point - body.global_position
	d.y = 0.0
	return d.length()


func patrol_ids() -> Array[String]:
	_refresh_patrol_ids()
	return _patrol_ids.duplicate()


func patrol_index() -> int:
	return _patrol_index


func patrol_target_id() -> String:
	return _patrol_target_id


func patrol_reached_count() -> int:
	return _patrol_reached


func detect_count() -> int:
	return _detect_count


func approach_count() -> int:
	return _approach_count


func lost_sight_count() -> int:
	return _lost_sight_count


## 当前与猎物的**水平**距离（没有视觉目标时 = `INF`）
func approach_distance() -> float:
	return _approach_dist


## 当前导航目的地（无目的地时返回 `Vector3.ZERO`）——诊断用
func destination() -> Vector3:
	return _destination if _has_destination else Vector3.ZERO


func ai_report() -> Dictionary:
	var d := super()
	d["ai_kind"] = "cat"
	d["patrol_enabled"] = patrol_enabled
	d["patrol_index"] = _patrol_index
	d["patrol_target"] = _patrol_target_id
	d["patrol_reached"] = _patrol_reached
	d["detect_count"] = _detect_count
	d["approach_count"] = _approach_count
	d["lost_sight"] = _lost_sight_count
	d["approach_distance"] = _approach_dist
	d["attack_range"] = attack_range
	d["npc_alert_time"] = alert_max_time
	return d
