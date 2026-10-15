class_name ResourcePoint
extends Interactable
## 固定食物点 / 饮水点（T017）
##
## 真源：`Docs/Parameters.md` 第 75 行「食物：一次交互 1.5 s，1 Unit 恢复 Hunger 35；水 2 s 恢复 Thirst 40；
## 提交前再检查距离、资源与受伤/死亡状态。受伤中断交互；被打断无收益，成功后全值夹紧。」
## 第 77 行「固定食物容量 3，每 180 s 恢复 1 Unit；捕获食物容量 1，未进食在 300 s 后失效。」
##
## 分工：
##   * 检测与"提交前复检"（距离/视线/物种）在 `InteractionDetector` 里做；
##   * **本类只负责资源账本与收益**：`units` 扣减、恢复量、恢复周期、失效；
##   * 收益发放与扣资源在**同一个方法里**完成（`TechnicalDesign.md` §4 第 185 行）；
##   * 取消/被打断**不发收益**（`cancel_interaction()` 什么都不改）。
##
## 时间：恢复排期用**绝对世界时间** `next_refill_at`（`WorldDirector.world_time`），
## 暂停时世界时间不前进 → 自然不恢复；一次结算**所有**经过的周期（读档/重生不会"只补一次"）。

const KIND_FOOD := &"food"
const KIND_WATER := &"water"

## 被消耗一次（`units_left` 是扣完之后的余量）
signal consumed(transaction_id: String, interactor: Node, units_left: int)
## 恢复了一个或多个 Unit（`units` 是恢复后的余量）
signal refilled(units: int, world_time: float)
## 到期失效（只发一次）
signal expired(world_time: float)

## 类型：`food` / `water`。**改它会套用该类型的默认数值**（时长/恢复量/容量/间隔），之后再显式覆盖即可。
@export var kind: StringName = KIND_FOOD:
	set(value):
		if kind == value:
			return
		kind = value
		_apply_kind_defaults()
## 食物类型（`SpeciesConfig.FoodType`）；水点忽略
@export var food_type: int = SpeciesConfig.FoodType.MEAT
## 当前余量（水点不用）
@export var units: int = 0
## 容量上限
@export var capacity: int = 3
## 恢复间隔（秒）；0 = 不恢复
@export var refill_interval: float = 180.0
## 下一次恢复的**世界时间**；0 = 不排期（满容量/水点/不恢复）
@export var next_refill_at: float = 0.0
## 失效世界时间；0 = 不失效（捕获食物 300 s，属 T021）
@export var expire_at: float = 0.0
## 一次交互的恢复量（食物 → Hunger；水 → Thirst）
@export var nutrition: float = 35.0
## 无限资源（水点）：不扣 `units`、不受容量/恢复限制
@export var infinite: bool = false
## 所属区域（`ResourceRecord.region_id`；分区账本属 T031/T035）
@export var region_id: StringName = &"Courtyard"
## 是否每物理帧按世界时间自动推进恢复（测试用假时间时关掉它自行调用 `advance_to()`）
@export var auto_advance: bool = true
## 占位网格尺寸（正式美术属 P6）
@export var marker_size: Vector3 = Vector3(0.30, 0.12, 0.30)

## 本实例被消耗过几次（诊断）
var consumed_count := 0
## 累计恢复过几个 Unit（诊断）
var refill_count := 0

var _expired_signalled := false
var _last_world_time := 0.0
var _world_director: Node = null
var _world_director_checked := false


func _init() -> void:
	super()
	_apply_kind_defaults()


func _ready() -> void:
	super()
	# 持久分组（T012 实测坑：`add_to_group(g)` 默认不持久，第二个参数必须显式 true）
	add_to_group(&"resource_points", true)
	_sync_visual()
	if not infinite and units < capacity and next_refill_at <= 0.0:
		next_refill_at = _world_time() + refill_interval


func _physics_process(_delta: float) -> void:
	if not auto_advance:
		return
	# 时间只从 `WorldDirector` 取（**不累加 delta**）：暂停时世界时间不前进 → 不会恢复
	advance_to(_world_time())


# ---------------------------------------------------------------------------
# 账本
# ---------------------------------------------------------------------------

## 推进到世界时间 `world_time`：结算**所有**经过的恢复周期，并处理到期失效
func advance_to(world_time: float) -> void:
	_last_world_time = maxf(_last_world_time, world_time)

	if expire_at > 0.0 and world_time >= expire_at:
		if not _expired_signalled:
			_expired_signalled = true
			units = 0
			next_refill_at = 0.0
			expired.emit(world_time)
		return

	if infinite or capacity <= 0 or refill_interval <= 0.0:
		return
	if units >= capacity:
		next_refill_at = 0.0
		return
	if next_refill_at <= 0.0:
		next_refill_at = world_time + refill_interval

	var gained := 0
	var guard := 0
	while world_time >= next_refill_at and units < capacity and guard < 1000000:
		units += 1
		gained += 1
		next_refill_at += refill_interval
		guard += 1
	if units >= capacity:
		next_refill_at = 0.0
	if gained > 0:
		refill_count += gained
		refilled.emit(units, world_time)


func is_empty() -> bool:
	return not infinite and units <= 0


func is_expired(world_time: float) -> bool:
	return expire_at > 0.0 and world_time >= expire_at


## 调试/初始化：填满容量
func fill() -> void:
	if infinite:
		return
	units = capacity
	next_refill_at = 0.0


## `ResourceRecord` 形状（`Docs/TechnicalDesign.md` §3），供 T037 存档
func to_record() -> Dictionary:
	return {
		"id": interaction_id,
		"region_id": String(region_id),
		"kind": String(kind),
		"food_type": food_type,
		"units": units,
		"capacity": capacity,
		"next_refill_at": next_refill_at,
		"refill_interval": refill_interval,
		"transform": global_transform if is_inside_tree() else Transform3D(),
		"expire_at": expire_at,
	}


# ---------------------------------------------------------------------------
# 交互（覆盖基类）
# ---------------------------------------------------------------------------

## 判定顺序：基类（enabled / allowed_species）→ 失效 → 食物类型 → 余量 → 死亡
func deny_reason_for(interactor: Node) -> StringName:
	var base := super(interactor)
	if base != &"":
		return base
	if is_expired(_world_time()):
		return &"expired"
	if kind == KIND_FOOD and not _can_eat(interactor):
		return &"food_type"
	if is_empty():
		return &"empty"
	var sc := _survival_of(interactor)
	if sc != null and sc.is_dead():
		return &"dead"
	return &""


func query_interaction(interactor: Node) -> Dictionary:
	var deny := deny_reason_for(interactor)
	return {
		"allowed": deny == &"",
		"action_id": &"eat" if kind == KIND_FOOD else &"drink",
		"duration": interaction_duration,
		"deny_reason": deny,
	}


## 扣 1 Unit + 发放收益在**同一个方法里**完成；失败时不扣不发（`TechnicalDesign.md` §4）
func commit_interaction(interactor: Node, transaction_id: String) -> Dictionary:
	_commit_calls += 1
	var deny := deny_reason_for(interactor)
	if deny != &"":
		return {"success": false, "reason": deny}
	if _transactions.has(transaction_id):
		# 同一个事务只结算一次（重复提交返回既有结果）
		return _transactions[transaction_id]
	var sc := _survival_of(interactor)
	if sc == null:
		return {"success": false, "reason": &"no_survival"}

	if not infinite:
		units -= 1
	if kind == KIND_WATER:
		sc.restore_thirst(nutrition)
	else:
		sc.restore_hunger(nutrition)
	# 消耗后**不在这里排期**：下一次 `advance_to()` 看到"未满且未排期"会自动排期，
	# 这样排期只用**一个时间源**（`advance_to` 传入的世界时间），不会和测试的假时间混用

	var res := {
		"success": true,
		"reason": &"ok",
		"action_id": &"eat" if kind == KIND_FOOD else &"drink",
		"nutrition": nutrition,
		"units_left": units,
	}
	_transactions[transaction_id] = res
	_commit_count += 1
	consumed_count += 1
	committed.emit(transaction_id, interactor)
	consumed.emit(transaction_id, interactor, units)
	return res


## 取消**不发收益**（`Parameters.md` 第 75 行：被打断无收益）
func cancel_interaction(transaction_id: String) -> void:
	super(transaction_id)


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _apply_kind_defaults() -> void:
	if kind == KIND_WATER:
		interaction_duration = 2.0
		nutrition = 40.0
		infinite = true
		capacity = 0
		units = 0
		refill_interval = 0.0
		next_refill_at = 0.0
		marker_size = Vector3(0.60, 0.05, 0.60)
	else:
		interaction_duration = 1.5
		nutrition = 35.0
		infinite = false
		capacity = 3
		units = 3
		refill_interval = 180.0
		next_refill_at = 0.0
		marker_size = Vector3(0.30, 0.12, 0.30)
	_sync_visual()


func _can_eat(interactor: Node) -> bool:
	var cfg = interactor.get("species_config") if "species_config" in interactor else null
	if cfg is SpeciesConfig:
		return (cfg as SpeciesConfig).can_eat(food_type)
	return false


func _survival_of(interactor: Node) -> SurvivalController:
	if interactor == null or not ("survival" in interactor):
		return null
	return interactor.get("survival") as SurvivalController


## 占位网格：按 `kind` 上色（正式美术属 P6；只为"能看出这里有东西"）
func _sync_visual() -> void:
	if not is_inside_tree():
		return
	var mi := get_node_or_null("Mesh") as MeshInstance3D
	if mi == null:
		return
	var box := BoxMesh.new()
	box.size = marker_size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.55, 0.30) if kind == KIND_FOOD else Color(0.25, 0.45, 0.75)
	mi.material_override = mat


## 当前世界时间（秒）：拿不到 `WorldDirector` 时返回最近一次推进值（不自己累加）
func _world_time() -> float:
	if not _world_director_checked:
		_world_director = get_node_or_null("/root/WorldDirector")
		_world_director_checked = true
	if _world_director != null and is_instance_valid(_world_director):
		return float(_world_director.get("world_time"))
	return _last_world_time
