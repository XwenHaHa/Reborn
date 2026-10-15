class_name SurvivalController
extends RefCounted
## 生存推进（T014）：生命 / 饥饿 / 水分 / 体力随时间变化
##
## ## 统一时间入口（`Docs/Tasks/T014.md` 决策 D1）
##
## 本组件**不读任何 `delta`**，只接受**世界时间**（`WorldDirector.world_time`），用相邻两次
## `tick_to()` 的差推进。理由：一个渲染帧可能跑 0/1/2 次物理帧，直接累加 physics delta
## 既会与"世界时间"漂移，也会让"暂停不消耗"依赖两套开关。用世界时间做差以后：
##   * 树暂停（`get_tree().paused`）→ `WorldDirector._process` 不跑 → 世界时间不动 → 不消耗；
##   * 显式门闩（`WorldDirector.time_advancing = false`）→ 同上；
##   * 时钟回退（读档把世界时间调小）→ `dt <= 0` → 不消耗、也不回退数值。
##
## ## 低频结算但用真实经过时间（决策 D2）
##
## 累计到 `UPDATE_INTERVAL`（0.2 s）才结算一次，但**用累计到的实际时间**结算
## （`Docs/TechnicalDesign.md` §5：「低频消耗可 0.2 s 更新但必须使用实际 delta」）。
## 因此 30 / 60 / 144 Hz 的最终结果只在"不足一次结算间隔的残留"上有差别。

## 状态或数值发生变化时发出（HUD / 警告 / 存档可以据此刷新）
signal changed(state: SurvivalState)
## 生命归零时发出**恰好一次**（本世结束由上层处理：T030 结算流程）
signal died(reason: StringName)

## 结算间隔（秒）。低频更新的意义是省 CPU，不是省时间精度
const UPDATE_INTERVAL := 0.2

## 物种配置（速率与容量都从这里读，不在本文件里写死数值）
var config: SpeciesConfig
## 当前生存状态（外部可读；改数值请走本类的方法）
var state: SurvivalState
## 上一次推进到的世界时间（`NAN` = 还没对齐过，第一次 `tick_to()` 只对齐不消耗）
var last_world_time: float = NAN

var _accum := 0.0
## 距上次"消耗体力"过了多久（秒）。初始为 INF：没消耗过就不该有"消耗后延迟"
var _time_since_spend: float = INF
var _dead := false


func _init(p_config: SpeciesConfig, p_state: SurvivalState = null) -> void:
	config = p_config
	state = p_state if p_state != null else SurvivalState.new()
	if config != null:
		state.clamp_to_max(config.max_health, config.max_hunger, config.max_thirst, config.max_stamina)
	_dead = state.health <= 0.0


## 推进到世界时间 `world_time`。返回本次推进的世界时间差（≤0 表示时间没走，返回 0）。
##
## 调用方（`AnimalBody._physics_process`）每物理帧调用一次即可；重复调用同一时刻不会重复消耗。
func tick_to(world_time: float) -> float:
	if config == null or state == null:
		return 0.0
	if is_nan(last_world_time):
		last_world_time = world_time
		return 0.0
	var dt: float = world_time - last_world_time
	if dt <= 0.0:
		return 0.0
	last_world_time = world_time
	_accum += dt
	while _accum >= UPDATE_INTERVAL - 1e-9:
		_apply_interval(UPDATE_INTERVAL)
		_accum -= UPDATE_INTERVAL
	return dt


## 消耗体力（T015 会用它做奔跑/扑击代价）。小于等于 0 视为无操作
func spend_stamina(amount: float) -> void:
	if amount <= 0.0 or state == null:
		return
	state.stamina = maxf(0.0, state.stamina - amount)
	_time_since_spend = 0.0
	changed.emit(state)


## 扣血。写 `last_damage_reason`；归零时发 `died`（只发一次）；非正伤害无副作用
func apply_damage(amount: float, reason: StringName) -> void:
	if amount <= 0.0 or state == null:
		return
	var was_alive := not _dead
	state.health = maxf(0.0, state.health - amount)
	state.last_damage_reason = reason
	if was_alive and state.health <= 0.0:
		_dead = true
		died.emit(reason)
	changed.emit(state)


## 恢复生命（安全休息用；T017/T034 会调用）。夹紧在容量内
func restore_health(amount: float) -> void:
	if amount <= 0.0 or state == null:
		return
	state.health = minf(config.max_health, state.health + amount)
	changed.emit(state)


## 进食/饮水（T017 用；本任务只提供接口，保证夹紧与事件）
func restore_hunger(amount: float) -> void:
	if amount <= 0.0 or state == null:
		return
	state.hunger = minf(config.max_hunger, state.hunger + amount)
	changed.emit(state)


func restore_thirst(amount: float) -> void:
	if amount <= 0.0 or state == null:
		return
	state.thirst = minf(config.max_thirst, state.thirst + amount)
	changed.emit(state)


func is_dead() -> bool:
	return _dead


func health_ratio() -> float:
	return state.ratio(&"health", config.max_health) if config != null else 0.0


func hunger_ratio() -> float:
	return state.ratio(&"hunger", config.max_hunger) if config != null else 0.0


func thirst_ratio() -> float:
	return state.ratio(&"thirst", config.max_thirst) if config != null else 0.0


func stamina_ratio() -> float:
	return state.ratio(&"stamina", config.max_stamina) if config != null else 0.0


## 读档：换成另一份状态（会按当前配置夹紧，并重置推进入口）
func set_state(new_state: SurvivalState) -> void:
	state = new_state if new_state != null else SurvivalState.new()
	if config != null:
		state.clamp_to_max(config.max_health, config.max_hunger, config.max_thirst, config.max_stamina)
	_dead = state.health <= 0.0
	last_world_time = NAN
	_accum = 0.0
	_time_since_spend = INF
	changed.emit(state)


## 单元自检（断言与调试入口可用）：配置是否齐全
func validate_config() -> PackedStringArray:
	var problems := PackedStringArray()
	if config == null:
		problems.append("config 为空")
		return problems
	if config.max_health <= 0.0 or config.max_hunger <= 0.0 \
			or config.max_thirst <= 0.0 or config.max_stamina <= 0.0:
		problems.append("max_* 容量必须 > 0")
	if config.max_stamina < config.sprint_stamina_per_sec * 0.1:
		problems.append("max_stamina 相对 sprint_stamina_per_sec 过小")
	return problems


## 一次结算：消耗饥渴；体力按「距上次消耗 ≥ regen_delay」才回复
##
## 边界语义：**先判延迟、再累加本段**，所以"刚好到 regen_delay 的那一段"不算回复，
## 下一段才开始回复（与 `Parameters.md` 的「RegenDelay 后恢复」一致，且不依赖帧率）。
func _apply_interval(dt: float) -> void:
	state.hunger = maxf(0.0, state.hunger - config.hunger_loss_per_sec * dt)
	state.thirst = maxf(0.0, state.thirst - config.thirst_loss_per_sec * dt)
	if _time_since_spend >= config.regen_delay:
		state.stamina = minf(config.max_stamina, state.stamina + config.stamina_regen_per_sec * dt)
	_time_since_spend += dt
	changed.emit(state)
