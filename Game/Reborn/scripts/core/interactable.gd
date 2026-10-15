class_name Interactable
extends Area3D
## 交互目标基类（T016）
##
## `Docs/TechnicalDesign.md` §4：交互目标必须实现三个方法（**鸭子类型**，替代 UE BlueprintInterface）：
##   `query_interaction(interactor) -> {allowed, action_id, duration, deny_reason}`
##   `commit_interaction(interactor, transaction_id) -> {success, reason}`
##   `cancel_interaction(transaction_id) -> void`
##
## 本类**只是默认实现**：任何自己实现这三个方法的节点都能被 `InteractionDetector` 选中
## （检测侧只用 `has_method()` 判断，**不做类型转换**，见 `Docs/Tasks/T016.md` D8）。
##
## 碰撞：固定在 `interactable` 层（layer 3）；`collision_mask = 0`（目标不主动撞任何东西）。
## 不打开 `monitoring`：查询由交互者主动发起（`intersect_shape`），目标不需要自己监听进入/离开。
##
## 本类**不发收益**：账本只记"提交了几次"，实际扣资源/加收益属 T017 的子类职责。

## 提交成功时发出（`transaction_id` 同一事务只会成功一次）
signal committed(transaction_id: String, interactor: Node)
## 取消时发出（取消**无收益**）
signal cancelled(transaction_id: String)

const LAYER_INTERACTABLE := 3
## 默认动作 ID；子类可覆盖 `_action_id()`（例如将来的 `eat` / `drink` / `hide`）
const DEFAULT_ACTION_ID := &"interact"

## 稳定 ID（地图内唯一）。留空则在入树时用节点名兜底；存档与日志用它，不用节点路径。
@export var interaction_id: String = ""
## 优先级：越大越优先（检测排序第一关键字）。
## 名字带前缀：`Area3D` 自带 native `priority`（float，用于重叠排序），**不复用**它以免语义混淆。
@export var interaction_priority: int = 0
## 允许的物种；**空数组 = 不限**（`SpeciesId` 为 `"Cat"` / `"Mouse"`）
@export var allowed_species: Array[StringName] = []
## 交互时长（秒）。0 = 按下即完成；> 0 由 `InteractionDetector` 按**世界时间**推进
@export var interaction_duration: float = 0.0
## 交互范围覆盖（米）。0 = 用交互者物种配置的 `interaction_range`
@export var range_override: float = 0.0
## 交互点相对本节点原点的偏移（米）；交互点用于距离与视线判定
@export var interaction_point_offset: Vector3 = Vector3.ZERO
## 关掉后目标立即不可用（也不进候选）
@export var enabled: bool = true

## 目标真的被调用 `commit_interaction()` 的次数（含重复事务；诊断用）
var _commit_calls := 0
## 成功结算次数（同一事务 ID 不重复计；诊断与断言用）
var _commit_count := 0
## 被调用 `cancel_interaction()` 的次数
var _cancel_calls := 0
## 事务 ID → 既有结果（重复事务返回它，不重复结算）
var _transactions: Dictionary = {}


func _init() -> void:
	# 固定层与掩码：**不随场景覆盖**（层是"物理契约"，见 TechnicalDesign §5）
	collision_layer = 1 << (LAYER_INTERACTABLE - 1)
	collision_mask = 0
	monitoring = false


func _ready() -> void:
	if interaction_id.is_empty():
		interaction_id = String(name)


# ---------------------------------------------------------------------------
# 查询 / 提交 / 取消（三个方法就是"接口"）
# ---------------------------------------------------------------------------

## 交互点（全局坐标）
func interaction_point() -> Vector3:
	return to_global(interaction_point_offset)


## 当前物种是否允许（`allowed_species` 为空 = 不限）
func is_allowed_for(species_id: StringName) -> bool:
	if allowed_species.is_empty():
		return true
	return allowed_species.has(species_id)


## 拒绝理由（**查询与提交都走它**，保证两处判定一致）
func deny_reason_for(interactor: Node) -> StringName:
	if not enabled:
		return &"disabled"
	if not is_allowed_for(species_of(interactor)):
		return &"species"
	return &""


func query_interaction(interactor: Node) -> Dictionary:
	var deny := deny_reason_for(interactor)
	return {
		"allowed": deny == &"",
		"action_id": _action_id(),
		"duration": interaction_duration,
		"deny_reason": deny,
	}


func commit_interaction(interactor: Node, transaction_id: String) -> Dictionary:
	_commit_calls += 1
	var deny := deny_reason_for(interactor)
	if deny != &"":
		return {"success": false, "reason": deny}
	if _transactions.has(transaction_id):
		# 同一事务重复提交：返回既有结果，**不再结算**
		return _transactions[transaction_id]
	var res := {"success": true, "reason": &"ok"}
	_transactions[transaction_id] = res
	_commit_count += 1
	committed.emit(transaction_id, interactor)
	return res


func cancel_interaction(transaction_id: String) -> void:
	_cancel_calls += 1
	cancelled.emit(transaction_id)


# ---------------------------------------------------------------------------
# 诊断（HUD / 断言）
# ---------------------------------------------------------------------------

func commit_call_count() -> int:
	return _commit_calls


func commit_count() -> int:
	return _commit_count


func cancel_call_count() -> int:
	return _cancel_calls


func successful_transactions() -> PackedStringArray:
	var out := PackedStringArray()
	for key in _transactions.keys():
		out.append(String(key))
	return out


## 交互者的物种 ID（从 `species_config.species_id` 读，**不硬编码物种名**）
func species_of(interactor: Node) -> StringName:
	if interactor == null:
		return &""
	var cfg = interactor.get("species_config") if "species_config" in interactor else null
	if cfg is SpeciesConfig:
		return (cfg as SpeciesConfig).species_id
	return &""


## 子类覆盖：默认动作 ID
func _action_id() -> StringName:
	return DEFAULT_ACTION_ID
