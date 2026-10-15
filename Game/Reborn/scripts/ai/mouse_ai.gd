class_name MouseAI
extends AnimalAI
## 鼠 NPC 行为（T019）
##
## `Docs/TechnicalDesign.md` §6：鼠在 `EXPLORE/FORAGE → ALERT → …` 之间切换；本任务只做
## **觅食（EXPLORE ↔ FORAGE）** 与 **警戒（ALERT）**，以及路径失败时的 `WAIT` 回退。
## 逃跑（`FLEE`）、躲藏（`HIDDEN`）与真实视觉/听觉属 **T020**。
##
## 两条纪律：
##   * **不自己结算资源**：走到目标后调 `InteractionDetector.press_interact()`，扣 Unit 与恢复 Hunger
##     都由 `ResourcePoint`（T017）做；本文件不碰 `units`、不碰 `survival`。
##   * **不瞬移**：只写 `move_intent`（身体自己 `move_and_slide`），位置推进靠导航路径。

## 当前觅食目标
var _target: ResourcePoint = null
## 成功进食次数（诊断）
var _ate_count := 0


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
	if _state == State.WAIT:
		body.move_intent = Vector2.ZERO
		return
	if _has_alert:
		# 警戒期间：停住（逃跑属 T020）
		body.move_intent = Vector2.ZERO
		return

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
# 回调
# ---------------------------------------------------------------------------

## 重新选目标（基类在路径失败时调用）
func on_needs_new_target(_reason: StringName) -> void:
	_target = null
	_target_id = ""
	_clear_destination()


## 警戒结束：回探索（T020 会把这里换成"回安全点/躲藏"）
func _on_alert_ended(_world_time: float) -> void:
	_target = null
	_target_id = ""
	_clear_destination()
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
