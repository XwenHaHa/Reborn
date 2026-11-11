class_name RestPoint
extends Interactable
## T058：**休息点**（安全地点上的交互目标）
##
## 策划 v1.1 :129/:132 —— 休息与进食/饮水同属交互目标，冲突按"视线 + 距离"由
## `InteractionDetector`（T016）统一裁决；本类只负责**把休息的拒绝理由与结算接到交互契约上**。
##
## 为什么休息必须挂在交互点上：`Parameters.md:81` 的拒绝条件里有"正在警戒/追逐"，
## 策划 :297 还要求"受限于安全地点"。项目里的"安全点系统"（`last_safe_spot_id`）尚未立项
## （T042 挂账），所以本任务用**最小可判定口径**：**只有休息点存在的地方才能休息**——
## 交互体由 `MainEntry` 在关卡运行期挂载（与资源点同一做法，不改关卡几何）。

const ACTION_REST := &"rest"
## 交互时长（秒）。**实现默认值**：进食 1.5 / 饮水 2.0，休息取 1.0，
## 保证"一按即休息"又留一点操作节奏（策划 :132 要求不同动作可区分）。
const REST_DURATION := 1.0
## 交互点抬离地面（米）：`Interactable` 用交互点判距离与遮挡
const POINT_LIFT := 0.05


func _init() -> void:
	interaction_priority = 0
	interaction_duration = REST_DURATION
	interaction_point_offset = Vector3(0.0, POINT_LIFT, 0.0)


func _action_id() -> StringName:
	return ACTION_REST


## 拒绝理由**查询与提交共用**（基类契约）：把 `RestDirector.evaluate()` 的判定直接暴露给
## `InteractionDetector`，这样 HUD 在按下去之前就能显示"为什么不能休息"。
func deny_reason_for(interactor: Node) -> StringName:
	var base := super.deny_reason_for(interactor)
	if base != &"":
		return base
	var rd := get_node_or_null("/root/RestDirector")
	if rd == null:
		return &"no_director"
	var ev: Dictionary = rd.call("evaluate", interactor)
	if not bool(ev.get("ok", false)):
		return StringName(ev.get("reason", &"denied"))
	return &""


## 提交：**同一事务只结算一次**（沿用基类的 `_transactions` 幂等语义），
## 结算本体是 `RestDirector.rest()` 的原子事务。
func commit_interaction(interactor: Node, transaction_id: String) -> Dictionary:
	_commit_calls += 1
	var deny := deny_reason_for(interactor)
	if deny != &"":
		return {"success": false, "reason": deny}
	if _transactions.has(transaction_id):
		# 同一事务重复提交：返回既有结果，**不再结算**（不会白送第二次 60 s）
		return _transactions[transaction_id]

	var rd := get_node_or_null("/root/RestDirector")
	if rd == null:
		var missing := {"success": false, "reason": &"no_director"}
		_transactions[transaction_id] = missing
		return missing
	var res: Dictionary = rd.call("rest", interactor)
	if not bool(res.get("ok", false)):
		var refused := {"success": false, "reason": StringName(res.get("reason", &"denied"))}
		_transactions[transaction_id] = refused
		return refused
	var ok := {
		"success": true,
		"reason": &"ok",
		"world_time_after": float(res.get("world_time_after", 0.0)),
		"health_after": float(res.get("health_after", 0.0)),
	}
	_transactions[transaction_id] = ok
	_commit_count += 1
	committed.emit(transaction_id, interactor)
	return ok


## 最近一次休息结果（诊断/断言）
func rest_result() -> Dictionary:
	for key in _transactions.keys():
		var rec: Dictionary = _transactions[key]
		if bool(rec.get("success", false)):
			return rec
	return {}
