class_name MouseAI
extends AnimalAI
## 鼠 NPC 行为（T019 觅食与警戒 + **T020 视觉、听觉与逃跑**）
##
## `Docs/TechnicalDesign.md` §6：鼠在 `EXPLORE/FORAGE → ALERT → FLEE → HIDDEN → EXPLORE` 之间切换。
## T020 把 T019 的「外部注入威胁」换成**真实感知**（`Perception`）：
##   * **看得见**威胁且距离 ≤ `immediate_flee_range` → **立即逃**（跳过警戒停留）——
##     `Docs/Parameters.md` 第 71 行「目标在 180 内立即逃」
##   * 看得见但还远 → 先 `ALERT`（最长 0.3 s，T019 语义）；警戒结束时**仍看得见**才 `FLEE`
##   * **只听见**噪声 → 警戒到**噪声发生位置**（`Perception` 不提供声源真实位置，D5）
##   * `FLEE` 选**可达**躲藏点（`hide_spots` 组；真实关卡里 = 鼠洞）→ 到达后 `HIDDEN`；
##     没有可达躲藏点就试附近**遮挡**（`cover_volumes`）；两者都没有或不达 → `flee_timeout` 超时回 `EXPLORE`
##   * `HIDDEN` 后**无危险持续 4 s**（`hidden_hold_time`，同第 71 行）→ 外出继续觅食
##
## 两条纪律（沿用 T019）：
##   * **不自己结算资源**：进食走 `InteractionDetector`，扣 Unit 与恢复 Hunger 由 `ResourcePoint`（T017）做
##   * **不瞬移**：只写 `move_intent`（身体自己 `move_and_slide`），位置推进靠导航路径

const FLEE_NONE := &"none"
const FLEE_HIDE := &"hide"
const FLEE_COVER := &"cover"

## 躲藏后"无危险持续"多久才外出（秒）——`Parameters.md` 第 71 行
@export var hidden_hold_time: float = 4.0
## 目标在这个距离内**立即逃**（米）——同上一行「目标在 180 内立即逃」
@export var immediate_flee_range: float = 1.80
## 找不到可达躲藏点 / 遮挡时的超时（秒）——**T020 新增值**（见 `Docs/Tasks/T020.md` §9）
@export var flee_timeout: float = 3.0

## 当前觅食目标
var _target: ResourcePoint = null
## 成功进食次数（诊断）
var _ate_count := 0
## 本次逃跑的落点类型（`hide` / `cover` / `none`）与落脚半径
var _flee_kind: StringName = FLEE_NONE
var _arrive_radius := 0.30
## 逃跑起点时间（用于"没有可达落点"的 `flee_timeout` 计时）
var _flee_started := 0.0
## 目的地的设置时刻（`is_navigation_finished()` 的失败判据要等满一个 `retry_window`）
var _flee_dest_set_at := 0.0
## 已经试过（失败或不可达）的躲藏点名字，避免逃跑时反复选同一个
var _tried_hide_ids: Array[String] = []
## 躲藏次数与进入时间（诊断）
var _hidden_count := 0
var _hidden_since := 0.0
## 最近一次已经反应过的噪声世界时间（同一声音不重复警戒）
var _last_reacted_noise := 0.0


func setup(p_body: AnimalBody) -> void:
	super(p_body)
	if p_body != null and p_body.interaction != null:
		if not p_body.interaction.interaction_committed.is_connected(_on_interaction_committed):
			p_body.interaction.interaction_committed.connect(_on_interaction_committed)
	change_state(State.EXPLORE, &"boot")


# ---------------------------------------------------------------------------
# 行为
# ---------------------------------------------------------------------------

func _step(world_time: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	# 1) 躲藏中：停住；无危险持续 hidden_hold_time → 外出
	if _state == State.HIDDEN:
		body.move_intent = Vector2.ZERO
		if _can_leave_hiding(world_time):
			_leave_hiding(world_time)
		return
	# 2) 失败等待（T019）：短暂停住，结束后基类会回 EXPLORE（**不永久阻塞**）
	if _state == State.WAIT:
		body.move_intent = Vector2.ZERO
		return
	# 3) 感知 → 警戒 / 立即逃（**逃跑与躲藏中不重复警戒**，见 `_react_to_senses`）
	_react_to_senses(world_time)
	if _has_alert:
		body.move_intent = Vector2.ZERO
		return
	# 4) 逃跑中：跑到可达落点 → 躲藏；没有落点 → 超时回探索
	if _state == State.FLEE:
		_step_flee(world_time)
		return
	# 5) 觅食（T019 原逻辑）
	_refresh_target()
	if _target == null:
		body.move_intent = Vector2.ZERO
		if _state != State.EXPLORE:
			change_state(State.EXPLORE, &"no_food_known")
		else:
			set_reason(&"no_food_known")
		return

	var dist := body.global_position.distance_to(_target.interaction_point())
	if dist <= arrive_range():
		_on_arrived()
		return

	if not _has_destination:
		_set_destination(_target.global_position)
		change_state(State.FORAGE, &"moving")
	_advance_along_path()
	_track_progress(world_time)


## 到达判定：略小于物种的交互范围（保证 `press_interact()` 时目标在范围内）
func arrive_range() -> float:
	var r := 0.35
	if body != null and body.species_config != null:
		r = maxf(0.20, body.species_config.interaction_range * 0.9)
	return r


func _on_arrived() -> void:
	_clear_destination()
	body.move_intent = Vector2.ZERO
	if _state != State.FORAGE or _reason != &"arrived":
		change_state(State.FORAGE, &"arrived")
	if body.interaction != null and not body.interaction.is_interacting():
		# 走**和玩家一样**的交互接口；成功与否由 `ResourcePoint.deny_reason_for()` 决定
		body.interaction.press_interact()


## 目标失效（被吃空 / 失效 / 不再可食）就换一个
func _refresh_target() -> void:
	if _target != null and is_instance_valid(_target) and _target.deny_reason_for(body) == &"":
		_target_id = _target.interaction_id
		return
	var next := find_food_target()
	if next != _target:
		_clear_destination()
	_target = next
	_target_id = next.interaction_id if next != null else ""


## 最近的可用食物点：`kind=food` 且 `ResourcePoint.deny_reason_for()` 为空
## （等于"可食 + 有 Unit + 未失效"，复用 T017 的判定，**不重复实现规则**）
func find_food_target() -> ResourcePoint:
	var best: ResourcePoint = null
	var best_distance := INF
	for n in get_tree().get_nodes_in_group(&"resource_points"):
		if not (n is ResourcePoint):
			continue
		var rp := n as ResourcePoint
		if rp.kind != ResourcePoint.KIND_FOOD:
			continue
		if rp.deny_reason_for(body) != &"":
			continue
		var d := body.global_position.distance_to(rp.interaction_point())
		if d < best_distance:
			best_distance = d
			best = rp
	return best


func eat_target() -> ResourcePoint:
	return _target


func ate_count() -> int:
	return _ate_count


# ---------------------------------------------------------------------------
# 感知 → 警戒 / 逃跑（T020）
# ---------------------------------------------------------------------------

func _perception() -> Perception:
	if body == null or not is_instance_valid(body):
		return null
	return body.perception


## 把"看见 / 听见"翻译成状态变化。**本函数不改位移**，只调 `alert_for()` / `start_flee()`。
func _react_to_senses(world_time: float) -> void:
	var p := _perception()
	if p == null:
		return
	# 逃跑中或躲藏中不再重新警戒（否则会在"警戒停住"与"逃跑"之间来回抖）
	if _state == State.FLEE or _state == State.HIDDEN:
		return
	if p.is_threat_visible():
		var threat_pos := p.threat_position()
		if body.global_position.distance_to(threat_pos) <= immediate_flee_range:
			start_flee(world_time, &"threat_close")
			return
		if not _has_alert:
			alert_for(threat_pos, &"saw_threat")
		return
	# 只听见声音：警戒到**发生位置**（不跟踪声源真实位置，`TechnicalDesign` §6）
	var noise_time := p.last_noise_time()
	if noise_time > _last_reacted_noise:
		_last_reacted_noise = noise_time
		alert_for(p.last_noise_position(), &"heard_noise")


## 进入逃跑：清掉觅食目标与已试过的点，选一个可达落点（没有就交给 `flee_timeout`）
func start_flee(world_time: float, reason: StringName) -> void:
	_release_food_target()
	_tried_hide_ids.clear()
	_flee_started = world_time
	_pick_flee_target(world_time)
	change_state(State.FLEE, reason)


## 选逃跑落点（D7）：① 可达躲藏点 → ② 可达遮挡 → ③ 都没有（不设目的地，靠超时回退）
func _pick_flee_target(world_time: float) -> void:
	_clear_destination()
	_flee_kind = FLEE_NONE
	_hide_id = ""
	_arrive_radius = hide_arrive_radius
	var spot := find_hide_spot(_tried_hide_ids)
	if spot != null:
		_flee_kind = FLEE_HIDE
		_hide_id = String(spot.name)
		_tried_hide_ids.append(_hide_id)
		_arrive_radius = hide_spot_radius(spot)
		_set_destination(hide_spot_point(spot))
		_flee_dest_set_at = world_time
		return
	var cover := find_cover_point()
	if not is_nan(cover.x):
		_flee_kind = FLEE_COVER
		_hide_id = "cover"
		_arrive_radius = hide_arrive_radius
		_set_destination(cover)
		_flee_dest_set_at = world_time
		return
	# 没有可达落点：从现在起算 flee_timeout（**不永久卡在 FLEE**）
	_flee_started = world_time
	set_reason(&"no_hide_spot")


## 逃跑推进：到达 → HIDDEN；导航说"走完了"但人没到位 → 记失败；没有目的地且超时 → 回 EXPLORE
##
## 到达判据**只看真实距离**（`_arrive_radius`）—— 不能用 `is_navigation_finished()` 当到达：
## 被墙挡住时"路径走完"也可能成立，那会变成**假躲藏**（T020 实测口径，见 `Docs/Tasks/T020.md` §8）。
func _step_flee(world_time: float) -> void:
	if not _has_destination:
		body.move_intent = Vector2.ZERO
		if world_time - _flee_started >= flee_timeout:
			_flee_timeouts += 1
			change_state(State.EXPLORE, &"flee_timeout")
		return
	if body.global_position.distance_to(_destination) <= _arrive_radius:
		_enter_hidden(world_time)
		return
	if agent.is_navigation_finished():
		body.move_intent = Vector2.ZERO
		if world_time - _flee_dest_set_at >= retry_window:
			_register_path_failure(world_time)
		return
	_advance_along_path()
	_track_progress(world_time)


func _enter_hidden(world_time: float) -> void:
	_clear_destination()
	body.move_intent = Vector2.ZERO
	_hidden_count += 1
	_hidden_since = world_time
	change_state(State.HIDDEN, &"hidden")


## 可以外出了吗：**无危险持续** `hidden_hold_time`（危险 = 看见威胁或听到噪声）
func _can_leave_hiding(world_time: float) -> bool:
	var p := _perception()
	if p == null:
		return world_time - _hidden_since >= hidden_hold_time
	if p.is_threat_visible():
		return false
	# 「Hidden 后无危险持续 4 s 再外出」：**躲满 4 s** 且这 4 s 内没有危险（看见/听见都会把计时推后）
	return world_time - maxf(_hidden_since, p.danger_time()) >= hidden_hold_time


func _leave_hiding(_world_time: float) -> void:
	_release_food_target()
	_flee_kind = FLEE_NONE
	_hide_id = ""
	_tried_hide_ids.clear()
	change_state(State.EXPLORE, &"hidden_done")


func _release_food_target() -> void:
	_target = null
	_target_id = ""
	_clear_destination()


# ---------------------------------------------------------------------------
# 诊断
# ---------------------------------------------------------------------------

func hide_target_id() -> String:
	return _hide_id


func hidden_count() -> int:
	return _hidden_count


## 本次逃跑的落点类型（`hide` / `cover` / `none`）
func flee_kind() -> StringName:
	return _flee_kind


func hidden_elapsed(world_time: float) -> float:
	return maxf(0.0, world_time - _hidden_since)


func ai_report() -> Dictionary:
	var r := super.ai_report()
	r["flee_kind"] = _flee_kind
	r["hidden_count"] = _hidden_count
	r["hidden_elapsed"] = hidden_elapsed(current_world_time())
	r["ate_count"] = _ate_count
	r["tried_hide_spots"] = _tried_hide_ids.size()
	return r


# ---------------------------------------------------------------------------
# 回调
# ---------------------------------------------------------------------------

## 重新选目标（基类在路径失败时调用）
func on_needs_new_target(_reason: StringName) -> void:
	if _state == State.FLEE:
		# 逃跑途中的重选：换下一个可达点（试过的点不再选）；没有就交给 flee_timeout
		_pick_flee_target(current_world_time())
		return
	_release_food_target()


## 警戒结束（T019 语义：0.3 s 上限）：**仍看得见**威胁就开逃，否则回探索
func _on_alert_ended(world_time: float) -> void:
	var p := _perception()
	if p != null and p.is_threat_visible():
		start_flee(world_time, &"alert_ended_threat")
		return
	_release_food_target()
	change_state(State.EXPLORE, &"alert_ended")


func _on_interaction_committed(_transaction_id: String, interaction_id: String, success: bool, _reason: StringName) -> void:
	if not success:
		return
	if interaction_id.is_empty() or interaction_id != (_target.interaction_id if _target != null else ""):
		return
	_ate_count += 1
	_target = null
	_target_id = ""
	_clear_destination()
	change_state(State.EXPLORE, &"ate")
