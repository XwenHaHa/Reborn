class_name CaptureSettlement
extends Node3D
## 捕获结算组件（T021）
##
## 真源：
##   * `Docs/Parameters.md` 第 67 行（猫扑击：最大水平距离 140 cm、持续 0.25 s、体力 25、恢复 0.6 s）
##   * `Docs/Parameters.md` 第 77 行（捕获食物容量 1、未进食 300 s 失效；捕获**不**直接回满指标）
##   * `Docs/TechnicalDesign.md` §7（捕获流程：检查存活/未记账 → 标记 Captured → 建立捕获食物 → 移除活体表现 → 发信号）
##
## 与 `Perception` 同一模式：**捕食者自带的组件**，由 `AnimalBody.apply_config()` 在 `can_pounce()`
## 为真时创建并 `add_child`。本组件只负责三件事：
##   1) 判定猎物是否**有效**（纯存活/配置判定，**不写物种名分支**）；
##   2) 把捕获结果上报给 `WorldDirector`（账本在那里，幂等去重）；
##   3) 在命中点生成一个"可食对象"（`ResourcePoint`）。
##
## 它**不**造成伤害、**不**走走伤害/死亡通道、**不**直接回满任何指标 ——
## 捕获只是"把猎物变成一份食物"，进食仍须由既有 T017 交互流程消费该对象。

const FOOD_SCENE := "res://scenes/world/resource_point.tscn"

## 生成一个捕获食物对象时发出（测试与证据读取用）
signal food_spawned(point: ResourcePoint, world_time: float)

## 所属身体（捕食者）
var body: AnimalBody = null
## 物种配置（与身体共用同一份资源，本组件不另存数值）
var config: SpeciesConfig = null
## 本次运行生成过的捕获食物数（与 `WorldDirector.capture_food_count` 同增）
var spawn_count: int = 0
## 最近一次生成的食物对象
var last_spawned: ResourcePoint = null
## 最近一次 `try_capture()` 被挡下的原因：`""`（成功）/ `"invalid"` / `"recorded"` / `"no_director"`
var blocked_by: String = ""
## 生成食物所属区域（`ResourceRecord.region_id`；分区账本属 T031/T035）
@export var region_id: StringName = &"Courtyard"


func setup(p_body: AnimalBody, p_config: SpeciesConfig) -> void:
	body = p_body
	config = p_config


# ---------------------------------------------------------------------------
# 判定 / 结算
# ---------------------------------------------------------------------------

## 有效猎物（D4）：是动物身体、不是自己、**不同物种**、未被捕获、还活着。
## 全部是状态/配置判定 —— 因此猫能吃鼠、鼠不能吃猫，而代码里没有一处写物种名。
func is_valid_prey(target: Node) -> bool:
	if body == null or config == null or target == null:
		return false
	if not (target is AnimalBody):
		return false
	var prey := target as AnimalBody
	if prey == body:
		return false
	if prey.species_config == null:
		return false
	if prey.species_config.species_id == config.species_id:
		return false
	if prey.captured:
		return false
	if prey.survival != null and prey.survival.is_dead():
		return false
	return true


## 尝试结算一次捕获（D5/D6）。**幂等**：`WorldDirector.captured_target_ids` 与
## 猎物的 `mark_captured()` 双重去重，重复上报不会重复生成食物。
func try_capture(target: Node, hit_position: Vector3) -> bool:
	if not is_valid_prey(target):
		blocked_by = "invalid"
		return false
	var prey := target as AnimalBody
	var wd := _world_director()
	if wd == null:
		# 没有世界入口就没法保证"只结算一次"（TechnicalDesign §7 的"检查未记账"）
		blocked_by = "no_director"
		return false
	var now := world_time_now()
	if not bool(wd.call("report_capture", body.source_id(), prey.source_id(), hit_position, now)):
		blocked_by = "recorded"
		return false
	# 记账成功 → 标记猎物（幂等）+ 生成捕获食物。顺序按 TechnicalDesign §7。
	prey.mark_captured(body.source_id())
	spawn_captured_food(hit_position, now)
	blocked_by = ""
	return true


## 在命中点生成一个捕获食物对象（D6：容量 1、不恢复、`capture_food_expire` 秒后失效）。
## 返回生成的 `ResourcePoint`（场景资源缺失时返回 null）。
func spawn_captured_food(position: Vector3, world_time: float) -> ResourcePoint:
	var scene := load(FOOD_SCENE) as PackedScene
	if scene == null:
		push_warning("CaptureSettlement 找不到捕获食物场景：%s" % FOOD_SCENE)
		return null
	var point := scene.instantiate() as ResourcePoint
	if point == null:
		push_warning("CaptureSettlement 实例化出的节点不是 ResourcePoint：%s" % FOOD_SCENE)
		return null

	spawn_count += 1
	point.name = "CaptureFood_%d" % spawn_count
	point.interaction_id = "capture_food_%s_%d" % [
		body.source_id() if body != null else "unknown", spawn_count
	]
	# 数值契约（先设 kind 再设覆盖项：`kind` 的 setter 会重套该类型默认值）
	point.kind = ResourcePoint.KIND_FOOD
	point.food_type = SpeciesConfig.FoodType.MEAT
	point.units = 1
	point.capacity = 1
	point.refill_interval = 0.0
	point.next_refill_at = 0.0
	point.infinite = false
	point.auto_advance = true
	point.region_id = region_id
	point.expire_at = world_time + _expire_seconds()

	var parent := _spawn_parent()
	parent.add_child(point)
	point.global_position = position
	# 生成点的 `_ready()` 先把"入树时刻"当成基准；这里显式对齐到命中的世界时间，
	# 保证 `expire_at == 命中时间 + capture_food_expire`，且不会凭空多排一次恢复周期。
	point.advance_to(world_time)

	last_spawned = point
	var wd := _world_director()
	if wd != null:
		wd.set("capture_food_count", int(wd.get("capture_food_count")) + 1)
	food_spawned.emit(point, world_time)
	return point


# ---------------------------------------------------------------------------
# 诊断
# ---------------------------------------------------------------------------

## 只读快照（`AnimalBody.debug_state()` / 断言用）
func report() -> Dictionary:
	return {
		"spawn_count": spawn_count,
		"blocked_by": blocked_by,
		"last_spawned_id": last_spawned.interaction_id if last_spawned != null else "",
	}


## 统一时间入口：优先用身体的时间（`AnimalBody.world_time_now()`），没有身体时退回 `WorldDirector`
func world_time_now() -> float:
	if body != null and is_instance_valid(body):
		return body.world_time_now()
	var wd := _world_director()
	if wd != null:
		return float(wd.get("world_time"))
	return 0.0


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

## 失效时长（秒）来自物种配置；未配置（0）时**不失效**
func _expire_seconds() -> float:
	return config.capture_food_expire if config != null else 0.0


## 捕获食物挂在**关卡根**下，而不是挂在已被捕获的猎物或捕食者身上：
## 挂在猎物身上会随猎物一起被隐藏/停用，挂在捕食者身上会跟着它一起移动。
func _spawn_parent() -> Node:
	if body != null and is_instance_valid(body) and body.is_inside_tree():
		var tree := body.get_tree()
		if tree.current_scene != null:
			return tree.current_scene
		if body.get_parent() != null:
			return body.get_parent()
	return self


func _world_director() -> Node:
	return get_node_or_null("/root/WorldDirector")
