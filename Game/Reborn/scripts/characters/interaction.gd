class_name InteractionDetector
extends Node
## 交互检测与动作接口（T016）
##
## 职责（`Docs/Tasks/T016.md` §1）：
##   1) **检测**：只在 `interactable` 层（layer 3）找候选，按"优先级 → 距离 → ID"排出**唯一**目标
##   2) **判定**：距离用 `SpeciesConfig.interaction_range`（可被目标 `range_override` 覆盖）；
##      遮挡用一次 `ray_cast`（**只认 `world_static`**）；物种允许由目标自己在 `query_interaction` 里判
##   3) **动作接口**：调目标的 `query_/commit_/cancel_interaction`，**只执行一个**交互；
##      同一 `transaction_id` 重复提交返回既有结果（`TechnicalDesign.md` §4 第 186 行）
##   4) **时长**：`duration > 0` 时按**世界时间**推进（与 T014 同一时间入口，**不累加 delta**）
##
## 三条硬规矩：
##   * **不改身体的 `collision_mask`**：身体 mask 归移动（T009/T010 断言锁定只有 `world_static`）；
##     这里查询时**显式**给 `collision_mask`。
##   * **不用类型转换判断目标**：只 `has_method()`。任何实现三个方法的节点都能参与（鸭子类型）。
##   * **不瞬移、不替目标改状态**：本类只调用目标的方法，不直接改资源与表现。

## 目标切换时发出（无目标时 `interaction_id` 为 `""`）；**同一目标不重复发**
signal target_changed(interaction_id: String, allowed: bool)
signal interaction_started(transaction_id: String, interaction_id: String)
signal interaction_committed(transaction_id: String, interaction_id: String, success: bool, reason: StringName)
signal interaction_cancelled(transaction_id: String, interaction_id: String, reason: StringName)
signal interaction_rejected(interaction_id: String, reason: StringName)

## 与 `TechnicalDesign.md` §1 `ActionState` 对应的**本组件子集**（扑击/死亡属后续任务）
const ACTION_IDLE := &"idle"
const ACTION_INTERACTING := &"interacting"

const LAYER_WORLD_STATIC := 1
const LAYER_INTERACTABLE := 3

const METHOD_QUERY := &"query_interaction"
const METHOD_COMMIT := &"commit_interaction"
const METHOD_CANCEL := &"cancel_interaction"

## 探测球在"配置范围"之外的余量（米）：让 `range_override` 更大的目标也能被发现
@export var probe_extra_range: float = 0.5
## 单次形状查询最多取多少命中（够用即可，避免大范围时抖动）
@export var max_candidates: int = 32
## 幂等结果表上限（超出后丢弃最旧的键；只用于"重复事务"查表）
@export var max_remembered_transactions: int = 64

var _body: Node3D = null
var _config: SpeciesConfig = null

var _target: Node = null
var _target_allowed := false
var _candidates: Array[Node] = []

var _tx_seq := 0
var _last_tx := ""
var _active_tx := ""
var _active_target: Node = null
var _active_duration := 0.0
var _active_start := 0.0
## transaction_id → {success, reason, transaction_id, interaction_id}
var _transactions: Dictionary = {}

var _ticked := false
var _last_world_time := 0.0

var _commits := 0
var _cancels := 0
var _rejects := 0
var _skipped_non_interactable := 0
var _last_deny: StringName = &""


## 由身体在成型后调用（也会在热改配置时重复调用，**保留进行中的交互不成立**：配置换了就按新配置判）
func setup(body: Node3D, config: SpeciesConfig) -> void:
	_body = body
	_config = config


# ---------------------------------------------------------------------------
# 检测与选择
# ---------------------------------------------------------------------------

## 探测球半径（米）：配置范围 + 余量
func probe_radius() -> float:
	return _base_range() + maxf(0.0, probe_extra_range)


## 当前"有效范围"（米）：有目标时取目标的 `range_override`（若 > 0），否则取配置范围
func effective_range() -> float:
	if _target == null:
		return _base_range()
	return _range_for(_target)


## 只返回**一个**有效目标（无则 null）。交互进行中**锁定**当前目标（"只执行一个"）
func detect() -> Node:
	if is_interacting():
		return _active_target
	# 目标可能已被释放（例如资源点被消耗掉后销毁）：先清掉再重新找
	if _target != null and not is_instance_valid(_target):
		_set_target(null)
	_candidates = _collect_candidates()
	_set_target(_candidates[0] if not _candidates.is_empty() else null)
	return _target


func current_target() -> Node:
	return _target


## 目标在界面/日志里显示用的稳定 ID（无目标为 `""`）
func current_target_id() -> String:
	return _target_id_of(_target)


## 任意节点的交互 ID（诊断与断言用）
func target_id_of(node: Variant) -> String:
	return _target_id_of(node)


## 当前目标的 `query_interaction()` 结果（无目标为 `{}`）
func current_query() -> Dictionary:
	if _target == null:
		detect()
	if _target == null:
		return {}
	return _query(_target)


## 排序后的**全部**有效候选（仅供诊断；对外只暴露一个目标）
func candidates() -> Array[Node]:
	return _candidates.duplicate()


## 上一次"没有目标"的拒绝理由（`range` / `occluded` / `species` / `disabled` / `busy` / `no_target`）
func last_deny_reason() -> StringName:
	return _last_deny


func stats() -> Dictionary:
	return {
		"state": ACTION_INTERACTING if is_interacting() else ACTION_IDLE,
		"target_id": _target_id_of(_target),
		"allowed": _target_allowed,
		"progress": interaction_progress(),
		"commits": _commits,
		"cancels": _cancels,
		"rejects": _rejects,
		"skipped": _skipped_non_interactable,
		"transactions": _transactions.size(),
		"deny_reason": _last_deny,
		"active_transaction_id": _active_tx,
	}


# ---------------------------------------------------------------------------
# 动作接口
# ---------------------------------------------------------------------------

func is_interacting() -> bool:
	# 目标可能已被释放（资源点被销毁）：那种情况不算"进行中"
	return _active_target != null and is_instance_valid(_active_target)


func active_transaction_id() -> String:
	return _active_tx


## 本次交互的世界时间起点（`interaction_progress()` 的基准）
func interaction_start_time() -> float:
	return _active_start


func interaction_progress() -> float:
	if not is_interacting():
		return 0.0
	if _active_duration <= 0.0:
		return 1.0
	return clampf((_last_world_time - _active_start) / _active_duration, 0.0, 1.0)


## 按下交互（`duration == 0` 的目标会在这里直接完成）。返回是否真的**开始/完成**了
func press_interact(transaction_id: String = "") -> bool:
	if is_interacting():
		_reject(&"busy")
		return false
	if _target == null:
		detect()
	if _target == null:
		_reject(_last_deny if _last_deny != &"" else &"no_target")
		return false
	var q: Dictionary = _query(_target)
	if not bool(q.get("allowed", false)):
		_reject(_reason_of(q))
		return false

	_last_tx = transaction_id if not transaction_id.is_empty() else _next_transaction_id()
	_active_tx = _last_tx
	_active_target = _target
	_active_duration = maxf(0.0, float(q.get("duration", 0.0)))
	_active_start = current_world_time()
	interaction_started.emit(_active_tx, _target_id_of(_active_target))
	if _active_duration <= 0.0:
		var t := _active_target
		var tx := _active_tx
		_clear_active()
		commit_transaction(tx, t)
	return true


## 松开交互：进行中则**取消**（无收益）
func release_interact(reason: StringName = &"released") -> bool:
	if not is_interacting():
		return false
	var t := _active_target
	var tx := _active_tx
	_clear_active()
	if t != null and is_instance_valid(t) and t.has_method(METHOD_CANCEL):
		t.call(METHOD_CANCEL, tx)
	_cancels += 1
	interaction_cancelled.emit(tx, _target_id_of(t), reason)
	return true


## 一步式入口（断言与调试用）：按下 + 取结果。`duration > 0` 的目标只"开始"，结果在 `tick()` 里产生
func try_interact(transaction_id: String = "") -> Dictionary:
	if not press_interact(transaction_id):
		return {"success": false, "reason": _last_deny, "transaction_id": "", "started": false}
	var tx := _last_tx
	if _transactions.has(tx):
		var res: Dictionary = (_transactions[tx] as Dictionary).duplicate()
		res["started"] = true
		return res
	return {"success": true, "reason": &"started", "transaction_id": tx,
		"interaction_id": _target_id_of(_active_target), "started": true}


## 提交事务（幂等）：**同一 `transaction_id` 第二次直接返回既有结果，不再调用目标**
func commit_transaction(transaction_id: String, target: Node = null) -> Dictionary:
	if _transactions.has(transaction_id):
		return _transactions[transaction_id]
	var t := target if target != null else _target
	if t == null:
		return {"success": false, "reason": &"no_target"}
	# **提交前复检**（`TechnicalDesign.md` §4 第 184 行：距离、视线和允许物种在查询**及提交时**都检查）。
	# 目标被禁用 / 资源耗尽 / 食物类型不允许 / 移出范围 / 被挡住 → 失败且**不调用目标**（因此不扣资源、不发收益）
	var recheck := _recheck_target(t)
	if recheck != &"":
		var failed := {
			"success": false,
			"reason": recheck,
			"transaction_id": transaction_id,
			"interaction_id": _target_id_of(t),
		}
		_transactions[transaction_id] = failed
		interaction_committed.emit(transaction_id, failed["interaction_id"], false, recheck)
		return failed
	var raw: Dictionary = t.call(METHOD_COMMIT, _body, transaction_id)
	var res := {
		"success": bool(raw.get("success", false)),
		"reason": _reason_of(raw),
		"transaction_id": transaction_id,
		"interaction_id": _target_id_of(t),
	}
	_transactions[transaction_id] = res
	_trim_transactions()
	if res["success"]:
		_commits += 1
	interaction_committed.emit(transaction_id, res["interaction_id"], res["success"], res["reason"])
	return res


## 由身体**每物理帧**喂世界时间（统一时间入口；暂停时喂进来的值不前进 → 进度自然冻结）
func tick(world_time: float) -> void:
	_last_world_time = world_time
	_ticked = true
	if not is_interacting() or _active_duration <= 0.0:
		return
	if world_time - _active_start < _active_duration:
		return
	var t := _active_target
	var tx := _active_tx
	_clear_active()
	commit_transaction(tx, t)


## 当前世界时间（秒）：优先用最近一次 `tick()` 的值，其次问身体
func current_world_time() -> float:
	if _ticked:
		return _last_world_time
	if _body != null and _body.has_method("world_time_now"):
		return float(_body.call("world_time_now"))
	return 0.0


# ---------------------------------------------------------------------------
# 内部：查询与排序
# ---------------------------------------------------------------------------

func _collect_candidates() -> Array[Node]:
	var out: Array[Node] = []
	_last_deny = &""
	if _body == null or _config == null or not (_body is CollisionObject3D):
		return out
	var space := _body.get_world_3d().direct_space_state
	if space == null:
		return out

	var shape := SphereShape3D.new()
	shape.radius = probe_radius()
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), _eye_position())
	params.collision_mask = 1 << (LAYER_INTERACTABLE - 1)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.exclude = [(_body as CollisionObject3D).get_rid()]

	var hits := space.intersect_shape(params, maxi(1, max_candidates))
	var entries: Array[Dictionary] = []
	var eye := _eye_position()
	for hit in hits:
		var node: Node = (hit as Dictionary).get("collider")
		if node == null or node == _body:
			continue
		if not _implements_protocol(node):
			_skipped_non_interactable += 1
			continue
		if not _is_enabled(node):
			_last_deny = &"disabled"
			continue
		var q: Dictionary = node.call(METHOD_QUERY, _body)
		if not bool(q.get("allowed", false)):
			_last_deny = _reason_of(q)
			continue
		var point := _point_of(node)
		var distance := eye.distance_to(point)
		if distance > _range_for(node):
			_last_deny = &"range"
			continue
		if not _has_line_of_sight(eye, point):
			_last_deny = &"occluded"
			continue
		entries.append({
			"node": node,
			"priority": _priority_of(node),
			"distance": distance,
			"id": _target_id_of(node),
		})
	entries.sort_custom(_sort_entries)
	for e in entries:
		out.append(e["node"])
	return out


## 排序：priority 降序 → 距离升序 → ID 字典序（**确定性**，不依赖加入顺序）
func _sort_entries(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a["priority"])
	var pb := int(b["priority"])
	if pa != pb:
		return pa > pb
	var da := float(a["distance"])
	var db := float(b["distance"])
	if absf(da - db) > 1e-6:
		return da < db
	return String(a["id"]) < String(b["id"])


func _set_target(node: Node) -> void:
	if node == _target:
		return
	_target = node
	if node == null:
		_target_allowed = false
		target_changed.emit("", false)
		return
	var q := _query(node)
	_target_allowed = bool(q.get("allowed", false))
	target_changed.emit(_target_id_of(node), _target_allowed)


func _query(node: Variant) -> Dictionary:
	if node == null or not is_instance_valid(node) or not node.has_method(METHOD_QUERY):
		return {"allowed": false, "action_id": &"", "duration": 0.0, "deny_reason": &"not_interactable"}
	return node.call(METHOD_QUERY, _body)


## 提交前复检：返回拒绝理由（`&""` = 仍然有效）。
## 和检测阶段用同一套判定（距离 / 视线 / enabled / 目标自己的 `query_interaction`），
## 差别是**不排序、只看这一个目标**——用于"查询及提交时都检查"。
func _recheck_target(t: Variant) -> StringName:
	if t == null or not is_instance_valid(t) or not t.is_inside_tree():
		return &"gone"
	if not _implements_protocol(t):
		return &"not_interactable"
	if not _is_enabled(t):
		return &"disabled"
	var q: Dictionary = t.call(METHOD_QUERY, _body)
	if not bool(q.get("allowed", false)):
		return _reason_of(q)
	var eye := _eye_position()
	var point := _point_of(t)
	if eye.distance_to(point) > _range_for(t):
		return &"range"
	if not _has_line_of_sight(eye, point):
		return &"occluded"
	return &""


## 视线：从眼睛到交互点的一次 `ray_cast`，**只认 `world_static`**（草叶视觉遮挡不算物理遮挡）
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if from.distance_to(to) <= 1e-4:
		return true
	if _body == null or not (_body is CollisionObject3D):
		return true
	var space := _body.get_world_3d().direct_space_state
	if space == null:
		return true
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 1 << (LAYER_WORLD_STATIC - 1)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.exclude = [(_body as CollisionObject3D).get_rid()]
	return space.intersect_ray(params).is_empty()


## 眼睛（交互判定原点）：优先身体相机；没有相机时用"胶囊中心 + 半高"
func _eye_position() -> Vector3:
	if _body == null:
		return Vector3.ZERO
	if _body.has_method("eye_position"):
		return _body.call("eye_position")
	var cam = _body.get("camera") if "camera" in _body else null
	if cam is Camera3D:
		return (cam as Camera3D).global_position
	if _body is Node3D:
		return (_body as Node3D).global_position + Vector3(0.0, _half_height(), 0.0)
	return Vector3.ZERO


func _half_height() -> float:
	if _config != null:
		return _config.capsule_half_height
	return 0.0


func _base_range() -> float:
	if _config != null:
		return _config.interaction_range
	return 0.0


func _range_for(node: Variant) -> float:
	var base := _base_range()
	if node != null and "range_override" in node:
		var v := float(node.get("range_override"))
		if v > 0.0:
			return v
	return base


func _priority_of(node: Variant) -> int:
	if node == null:
		return 0
	# 优先读专用字段（`Interactable`）；鸭子类型节点可以用 `priority`
	if "interaction_priority" in node:
		return int(node.get("interaction_priority"))
	if "priority" in node:
		return int(node.get("priority"))
	return 0


func _is_enabled(node: Variant) -> bool:
	if node != null and "enabled" in node:
		return bool(node.get("enabled"))
	return true


func _point_of(node: Variant) -> Vector3:
	if node == null:
		return Vector3.ZERO
	if node.has_method("interaction_point"):
		return node.call("interaction_point")
	if node is Node3D:
		return (node as Node3D).global_position
	return Vector3.ZERO


func _target_id_of(node: Variant) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	if "interaction_id" in node:
		var v := String(node.get("interaction_id"))
		if not v.is_empty():
			return v
	return String(node.name)


## 鸭子类型判定：只认方法，**不做类型转换**
## 鸭子类型判定：只认方法，**不做类型转换**。参数不带类型：目标可能已被 `queue_free()`（带类型会报错）
func _implements_protocol(node: Variant) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return node.has_method(METHOD_QUERY) and node.has_method(METHOD_COMMIT) and node.has_method(METHOD_CANCEL)


func _reason_of(d: Dictionary) -> StringName:
	var v = d.get("deny_reason", d.get("reason", &""))
	if v == null:
		return &""
	return StringName(v)


func _clear_active() -> void:
	_active_tx = ""
	_active_target = null
	_active_duration = 0.0
	_active_start = 0.0


func _next_transaction_id() -> String:
	_tx_seq += 1
	return "tx_%d_%s" % [_tx_seq, _target_id_of(_target)]


func _reject(reason: StringName) -> void:
	_last_deny = reason
	_rejects += 1
	interaction_rejected.emit(_target_id_of(_target), reason)


func _trim_transactions() -> void:
	var limit := maxi(1, max_remembered_transactions)
	while _transactions.size() > limit:
		var keys := _transactions.keys()
		_transactions.erase(keys[0])
