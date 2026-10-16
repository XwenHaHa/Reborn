class_name AnimalAI
extends Node
## 分物种有限状态机基类（T019）
##
## 真源：`轮生_Reborn_开发计划_v1.0.md` 第 135 行「有限状态机，觅食与警戒可切换；**状态和原因可查看**」；
## `Docs/Parameters.md` **第 71 行**「鼠 NPC：Alert 最长 0.3 s……**MoveTo 失败 1 s 内回退，重选最多 3 次后
## 进入短暂等待并记录诊断，不永久阻塞**」；`Docs/TechnicalDesign.md` §6（鼠 `EXPLORE/FORAGE → ALERT → …`、
## `NavigationAgent3D` 信号驱动、**不每帧请求路径**、失败最多重选 3 次后短暂等待）。
##
## 分工：
##   * **本类**：状态/原因/时间轴、导航层反查、目标设置与沿线推进、失败处理（1 s / 3 次 / `WAIT`）、诊断。
##   * **子类**（`MouseAI`）：具体行为——找什么、什么时候吃、被警戒后回哪。
##   * **身体**只执行意图（`move_intent` / `want_*`）；AI **不直接改位移、不直接改生存数值**。
##
## 时间：全部计时用**世界时间**（`AnimalBody.world_time_now()` 的差），**不累加 delta** → 暂停自然不推进。

## 与 `Docs/TechnicalDesign.md` §1 `AIState` **前 9 个值顺序一致**；`WAIT` 是本任务按 `Parameters.md`
## 第 71 行「短暂等待」追加的第 10 个值（不改变前 9 个的含义）。
enum State { EXPLORE, FORAGE, ALERT, FLEE, HIDDEN, APPROACH, CHASE, SEARCH, ATTACK, WAIT }

signal state_changed(from: StringName, to: StringName, reason: StringName)

const STATE_NAMES: Array[StringName] = [
	&"explore", &"forage", &"alert", &"flee", &"hidden",
	&"approach", &"chase", &"search", &"attack", &"wait",
]

## 躲藏点 / 安全点组（真实关卡里由鼠洞等处标记；布点扩充属 T031/T035）
const HIDE_GROUP := &"hide_spots"
## 草丛遮挡体量组（T011 关卡数据：Area3D + `metadata/visibility_factor`）
const COVER_GROUP := &"cover_volumes"

## 警戒最长时长（秒）——`Parameters.md` 第 71 行「Alert 最长 0.3 s」
@export var alert_max_time: float = 0.3
## 判定"没有推进"的时间窗（秒）——同上一行「MoveTo 失败 1 s 内回退」
@export var retry_window: float = 1.0
## 最多重选次数——同上「重选最多 3 次」
@export var max_replans: int = 3
## 重选耗尽后的短暂等待（秒）——"之后进入短暂等待"，取 1 s
@export var move_fail_wait: float = 1.0
## 一个时间窗内至少要走多远才算"在推进"（米）
@export var min_progress: float = 0.05
## 显式指定导航层（0 = 从地图 `NavigationRegion3D.metadata/species` 反查）
@export var nav_layer_override: int = 0

# --- 躲藏与逃跑（T020）---
## 判定"点在导航层上可达"的容差（米）——**T020 新增值**（见 `Docs/Tasks/T020.md` §9）
@export var reach_tolerance: float = 0.5
## 到达躲藏点的默认半径（米）；单个躲藏点可用 `metadata/radius` 覆盖
@export var hide_arrive_radius: float = 0.30

## 被驱动的身体（`setup()` 里赋值）
var body: AnimalBody = null
## 导航代理（挂在**身体**下；没有就由 `setup()` 建一个）
var agent: NavigationAgent3D = null

var _state: int = State.EXPLORE
var _reason: StringName = &"boot"
var _state_since: float = 0.0
var _world_now: float = 0.0
var _ticked := false

var _has_destination := false
var _destination := Vector3.ZERO
var _destination_sets := 0
var _path_failures := 0
var _replans := 0
var _consecutive_failures := 0
var _last_progress_pos := Vector3.ZERO
var _last_progress_time := 0.0
var _last_path_status := ""

var _has_alert := false
var _alert_position := Vector3.ZERO
var _alert_until := 0.0

var _wait_until := 0.0

var _nav_layer := 1
var _nav_layer_source := "fallback"
## 当前目标 ID（子类维护，供 HUD/诊断）
var _target_id := ""

# --- 逃跑与躲藏（T020）---
## 当前落点类型：躲避藏点 / 避遮挡 / 无（诊断）
var _hide_kind: StringName = &"none"
## 当前落点 ID（躲藏点名字；遮挡为 "cover"）
var _hide_id := ""
## 最近一次躲藏点搜索检查过的候选数
var _hide_candidates_tested := 0
## 累计"候选不可达"次数
var _hide_unreachable := 0
## 累计"超时退出逃跑"次数
var _flee_timeouts := 0


# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------

func setup(p_body: AnimalBody) -> void:
	body = p_body
	if body == null or not is_instance_valid(body):
		return
	agent = _find_or_make_agent()
	_nav_layer = _resolve_nav_layer()
	if agent != null:
		agent.navigation_layers = nav_layer()
		agent.path_desired_distance = 0.10
		agent.target_desired_distance = 0.10
	if _state_since <= 0.0:
		_state_since = current_world_time()
	_reason = &"boot"


## 由身体**每物理帧**调用（喂世界时间；不累加 delta）
func tick(world_time: float) -> void:
	_world_now = world_time
	_ticked = true
	if body == null or not is_instance_valid(body):
		return
	if _state_since <= 0.0:
		_state_since = world_time

	# 警戒到期 → 交给子类决定回哪个状态
	if _has_alert and world_time >= _alert_until:
		_has_alert = false
		_on_alert_ended(world_time)

	# 失败等待到期 → 回探索（**不永久阻塞**）
	if _state == State.WAIT and world_time >= _wait_until:
		_consecutive_failures = 0
		_last_progress_pos = Vector3.ZERO
		change_state(State.EXPLORE, &"wait_done")

	_step(world_time)


## 子类覆盖：具体行为（默认什么都不做）
func _step(_world_time: float) -> void:
	pass


# ---------------------------------------------------------------------------
# 状态与原因（"可查看"）
# ---------------------------------------------------------------------------

func current_world_time() -> float:
	if _ticked:
		return _world_now
	if body != null and is_instance_valid(body) and body.has_method("world_time_now"):
		return float(body.world_time_now())
	return 0.0


func state_id() -> StringName:
	if _state < 0 or _state >= STATE_NAMES.size():
		return &"unknown"
	return STATE_NAMES[_state]


func state_int() -> int:
	return _state


func state_reason() -> StringName:
	return _reason


func state_elapsed(world_time: float = NAN) -> float:
	var now := world_time if not is_nan(world_time) else current_world_time()
	return maxf(0.0, now - _state_since)


func target_id() -> String:
	return _target_id


func change_state(new_state: int, reason: StringName) -> void:
	_reason = reason
	if new_state == _state:
		return
	var from := state_id()
	_state = new_state
	_state_since = current_world_time()
	state_changed.emit(from, state_id(), reason)


## 记录原因但**不改状态**（用于"原因变了但状态没变"的情形）
func set_reason(reason: StringName) -> void:
	_reason = reason


# ---------------------------------------------------------------------------
# 警戒（威胁由外部注入；T020 接真实视觉/听觉）
# ---------------------------------------------------------------------------

func alert_for(position: Vector3, reason: StringName = &"threat") -> void:
	_has_alert = true
	_alert_position = position
	_alert_until = current_world_time() + alert_max_time
	_on_alert_started(reason)
	change_state(State.ALERT, reason)


func has_alert() -> bool:
	return _has_alert


func alert_position() -> Vector3:
	return _alert_position


func alert_until() -> float:
	return _alert_until


## 进入警戒：停手停脚；进行中的交互**取消且无收益**（`Docs/Parameters.md` 第 75 行）
func _on_alert_started(_reason: StringName) -> void:
	if body == null or not is_instance_valid(body):
		return
	body.move_intent = Vector2.ZERO
	if body.interaction != null and body.interaction.is_interacting():
		body.interaction.release_interact(&"alert")


## 警戒结束：默认回探索；子类可覆盖
func _on_alert_ended(_world_time: float) -> void:
	_clear_destination()
	change_state(State.EXPLORE, &"alert_ended")


# ---------------------------------------------------------------------------
# 导航
# ---------------------------------------------------------------------------

func nav_layer() -> int:
	if nav_layer_override > 0:
		return nav_layer_override
	return _nav_layer


## 读取节点的物种标记：优先 `species_id`（导航区域用的键），兼容 `species`（出生点 / 补给点 / 躲藏点用的键）。
## **不能写成 `get_meta(name, null)`**：Godot 在默认值为 null 时会直接报错（T020 捕获时实测，见 `Docs/Evidence/T020.md`）。
func node_species_id(node: Object) -> StringName:
	if node == null:
		return &""
	if node.has_meta("species_id"):
		return StringName(node.get_meta("species_id"))
	if node.has_meta("species"):
		return StringName(node.get_meta("species"))
	return &""


## 从地图里 `NavigationRegion3D.metadata/species_id`（旧键 `species`）反查层号（**不硬编码物种名**）
func _resolve_nav_layer() -> int:
	var want := StringName("")
	if body != null and is_instance_valid(body) and body.species_config != null:
		want = body.species_config.species_id
	for region in _navigation_regions():
		var species := node_species_id(region)
		if species != &"" and species == want:
			_nav_layer_source = "metadata"
			return maxi(1, region.navigation_layers)
	_nav_layer_source = "fallback"
	return 1


func _navigation_regions() -> Array[NavigationRegion3D]:
	var out: Array[NavigationRegion3D] = []
	_collect_regions(get_tree().root if get_tree() != null else null, out)
	return out


func _collect_regions(node: Node, out: Array[NavigationRegion3D]) -> void:
	if node == null:
		return
	if node is NavigationRegion3D:
		out.append(node as NavigationRegion3D)
	for c in node.get_children():
		_collect_regions(c, out)


## 设置寻路目标。**同一目标不重复设**（"不每帧请求路径"）
func _set_destination(point: Vector3) -> bool:
	if agent == null or body == null:
		return false
	if _has_destination and _destination.distance_to(point) < 0.05:
		return true
	_destination = point
	_has_destination = true
	_destination_sets += 1
	agent.target_position = point
	_reset_progress_window()
	return true


## 强制下一次重新规划（换层 / 外部诊断用）
func force_replan() -> void:
	_clear_destination()
	_consecutive_failures = 0
	_last_progress_pos = Vector3.ZERO
	if agent != null:
		agent.navigation_layers = nav_layer()
	on_needs_new_target(&"force_replan")


## 子类覆盖：需要重新选目标（换目标 / 强制重规划）
func on_needs_new_target(_reason: StringName) -> void:
	pass


func _clear_destination() -> void:
	_has_destination = false
	_destination = Vector3.ZERO


func has_destination() -> bool:
	return _has_destination


## 沿导航路径推进：读 `get_next_path_position()` → 转向 + 向前（**不瞬移**）
## 无路径 / 已到终点时**必须清空意图**，否则会残留上一帧的方向继续走（实测会让"不可达"看起来像走通了）
func _advance_along_path() -> void:
	if agent == null or body == null or not _has_destination:
		return
	if agent.is_navigation_finished():
		body.move_intent = Vector2.ZERO
		return
	var next := agent.get_next_path_position()
	var to_next := next - body.global_position
	to_next.y = 0.0
	if to_next.length() < 0.01:
		body.move_intent = Vector2.ZERO
		return
	body.look_at(body.global_position + to_next.normalized(), Vector3.UP)
	body.move_intent = Vector2(0.0, -1.0)


func _reset_progress_window() -> void:
	if body != null and is_instance_valid(body):
		_last_progress_pos = body.global_position
	_last_progress_time = current_world_time()


## 失败判据（`Parameters.md` 第 71 行）：一个 `retry_window` 内推进 < `min_progress` 且没到终点 → 记一次失败
func _track_progress(world_time: float) -> void:
	if not _has_destination or agent == null or body == null:
		return
	if _last_progress_pos == Vector3.ZERO:
		_reset_progress_window()
		return
	if world_time - _last_progress_time < retry_window:
		return
	var progressed := body.global_position.distance_to(_last_progress_pos) >= min_progress
	_last_progress_pos = body.global_position
	_last_progress_time = world_time
	if progressed:
		return
	_register_path_failure(world_time)


func _register_path_failure(world_time: float) -> void:
	_path_failures += 1
	if agent != null and agent.is_navigation_finished():
		_last_path_status = "finished_without_progress"
	else:
		_last_path_status = "no_progress"
	if _consecutive_failures < max_replans:
		_consecutive_failures += 1
		_replans += 1
		_clear_destination()
		on_needs_new_target(&"replan")
		set_reason(&"replan")
		return
	# 重选已经用满 → 短暂等待（**不永久阻塞**）
	_consecutive_failures = 0
	_clear_destination()
	_wait_until = world_time + move_fail_wait
	change_state(State.WAIT, &"path_failed")


# ---------------------------------------------------------------------------
# 诊断（"状态和原因可查看"）
# ---------------------------------------------------------------------------

func ai_report() -> Dictionary:
	return {
		"state": state_id(),
		"state_int": _state,
		"reason": _reason,
		"elapsed": state_elapsed(),
		"target": _target_id,
		"path_failures": _path_failures,
		"replans": _replans,
		"destination_sets": _destination_sets,
		"path_points": agent.get_current_navigation_path().size() if agent != null else 0,
		"last_path_status": _last_path_status,
		"nav_layer": nav_layer(),
		"nav_layer_source": "override" if nav_layer_override > 0 else _nav_layer_source,
		"position": body.global_position if body != null and is_instance_valid(body) else Vector3.ZERO,
		"alerting": _has_alert,
		"alert_position": _alert_position,
		"has_destination": _has_destination,
		"perception": (body.perception.report() if body != null and body.perception != null else {}),
		"seen": (body.perception.is_threat_visible() if body != null and body.perception != null else false),
		"heard": (body.perception.heard_count() if body != null and body.perception != null else 0),
		"noise_age": (body.perception.noise_age() if body != null and body.perception != null else -1.0),
		"hide_target": _hide_id,
		"hide_candidates_tested": _hide_candidates_tested,
		"hide_unreachable": _hide_unreachable,
		"flee_timeouts": _flee_timeouts,
	}


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _find_or_make_agent() -> NavigationAgent3D:
	if body == null:
		return null
	var existing := body.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if existing != null:
		return existing
	var a := NavigationAgent3D.new()
	a.name = "NavigationAgent3D"
	body.add_child(a)
	return a


# ---------------------------------------------------------------------------
# 可达性 / 躲藏点 / 遮挡（T020：逃跑目标选择）
# ---------------------------------------------------------------------------

## 这个点在**本物种的导航层**上可达吗（D8）？
##
## 判据：① `map_get_closest_point()` 落在目标附近（≤ `reach_tolerance`）；
## ② `map_get_path()` 非空且终点也在 `reach_tolerance` 内。
##
## 取不到有效导航地图、或地图还没同步（`map_get_iteration_id() == 0`）时**不判定为不可达** ——
## 把"地图未就绪"误判成"封路"会让 NPC 平白放弃（见 `Docs/Tasks/T020.md` §4 D8）。
func reachable(point: Vector3) -> bool:
	if agent == null or body == null:
		return false
	var map := agent.get_navigation_map()
	if not map.is_valid():
		return true
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return true
	var closest := NavigationServer3D.map_get_closest_point(map, point)
	if closest.distance_to(point) > reach_tolerance:
		return false
	var path := NavigationServer3D.map_get_path(map, body.global_position, point, true, nav_layer())
	if path.is_empty():
		return false
	return path[path.size() - 1].distance_to(point) <= reach_tolerance


## 最近的**可达**躲藏点（`hide_spots` 组；真实关卡里 = 鼠洞）。没有可达的返回 null。
## `exclude` 用来跳过"上次已经失败过"的点（逃跑途中重选时用）。
func find_hide_spot(exclude: Array = []) -> Node3D:
	_hide_candidates_tested = 0
	if body == null or not is_instance_valid(body) or get_tree() == null:
		return null
	var best: Node3D = null
	var best_distance := INF
	for n in get_tree().get_nodes_in_group(HIDE_GROUP):
		var spot := n as Node3D
		if spot == null:
			continue
		if exclude.has(String(spot.name)):
			continue
		var species := node_species_id(spot)
		if species != &"" and species != _species_id():
			continue
		_hide_candidates_tested += 1
		var point := hide_spot_point(spot)
		var d := body.global_position.distance_to(point)
		if d >= best_distance:
			continue
		if not reachable(point):
			_hide_unreachable += 1
			continue
		best = spot
		best_distance = d
	return best


## 躲藏点的落脚点（默认取节点全局位置；`metadata/point_offset` 可微调）
func hide_spot_point(spot: Node3D) -> Vector3:
	var offset: Vector3 = spot.get_meta("point_offset", Vector3.ZERO)
	return spot.global_position + offset


## 躲藏点的到达半径（米）：`metadata/radius` 可覆盖默认值
func hide_spot_radius(spot: Node3D) -> float:
	return maxf(0.05, float(spot.get_meta("radius", hide_arrive_radius)))


## 最近的**可达**遮挡落点（`cover_volumes` 中心投到地面）。没有则返回 NAN 向量（用 `is_nan(v.x)` 判断）。
##
## 策划 v1.1 第 198 行：没有可达鼠洞时"尝试附近遮挡和替代路径"。
func find_cover_point() -> Vector3:
	if body == null or not is_instance_valid(body) or get_tree() == null:
		return Vector3(NAN, NAN, NAN)
	var best := Vector3(NAN, NAN, NAN)
	var best_distance := INF
	for n in get_tree().get_nodes_in_group(COVER_GROUP):
		var area := n as Node3D
		if area == null:
			continue
		var point := _ground_point_under(area.global_position)
		if not point.is_finite():
			continue
		var d := body.global_position.distance_to(point)
		if d >= best_distance:
			continue
		if not reachable(point):
			continue
		best = point
		best_distance = d
	return best


## 从某点向下打到 `world_static` 的地面点（草丛体量中心在半空，要落到地面才是可走位置）
func _ground_point_under(point: Vector3) -> Vector3:
	if body == null or not is_instance_valid(body):
		return Vector3(NAN, NAN, NAN)
	var space := body.get_world_3d().direct_space_state
	if space == null:
		return Vector3(NAN, NAN, NAN)
	var params := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 10.0, point - Vector3.UP * 10.0
	)
	params.collision_mask = 1
	params.collide_with_areas = false
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return Vector3(NAN, NAN, NAN)
	return hit["position"]


## 最近一次躲藏点搜索里**检查过**的候选数（诊断；封路时应 ≥ 1）
func hide_candidates_tested() -> int:
	return _hide_candidates_tested


## 累计"候选点不可达"次数（诊断）
func hide_unreachable_count() -> int:
	return _hide_unreachable


## 累计"没有可达落点、超时退出逃跑"次数（诊断；**不永久阻塞**的证据）
func flee_timeouts() -> int:
	return _flee_timeouts


## 当前躲藏点 ID（诊断；没有就是空串）
func hide_target_id() -> String:
	return _hide_id


func _species_id() -> StringName:
	if body != null and is_instance_valid(body) and body.species_config != null:
		return StringName(body.species_config.species_id)
	return &""
