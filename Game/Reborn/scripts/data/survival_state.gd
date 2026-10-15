class_name SurvivalState
extends Resource
## 生存状态数据（`Docs/TechnicalDesign.md` §3 契约）
##
## 只放**数据**：它将来要进存档，所以**不允许**持有 Node 引用（契约明文）。
## 推进/伤害/恢复的逻辑在 `SurvivalController`（`RefCounted`，无 Node 依赖，便于无头断言）。
##
## 数值口径：`Docs/Parameters.md` 第 15 行「初始 Health/Hunger/Thirst/Stamina = 100/100/100/100」；
## 容量上限由 `SpeciesConfig.max_*` 给出（两者都取 100）。

## 生命值。归零结束本世（`SurvivalController.died`）
@export var health: float = 100.0
## 饥饿。随模拟时间下降，由有效食物恢复（T017）
@export var hunger: float = 100.0
## 水分。随模拟时间下降，由饮水恢复（T017）
@export var thirst: float = 100.0
## 体力。奔跑/冲刺/跳跃/扑击消耗（T015），停止高强度行动后恢复
@export var stamina: float = 100.0
## 最近一次受伤原因（诊断与生命档案用）
@export var last_damage_reason: StringName = &""

## 契约里的四个数值字段名（工具函数按名字取值时用，避免到处写字符串）
const VALUE_NAMES: Array[StringName] = [&"health", &"hunger", &"thirst", &"stamina"]


## 夹紧到 [0, max]，避免任何来源写出越界值
func clamp_to_max(max_health: float, max_hunger: float, max_thirst: float, max_stamina: float) -> void:
	health = clampf(health, 0.0, maxf(0.0, max_health))
	hunger = clampf(hunger, 0.0, maxf(0.0, max_hunger))
	thirst = clampf(thirst, 0.0, maxf(0.0, max_thirst))
	stamina = clampf(stamina, 0.0, maxf(0.0, max_stamina))


## 按名字取数值。未知名字返回 0（调用方不需要知道有哪些字段）
func value_of(value_name: StringName) -> float:
	match value_name:
		&"health":
			return health
		&"hunger":
			return hunger
		&"thirst":
			return thirst
		&"stamina":
			return stamina
		_:
			return 0.0


## 是否有该数值字段
func has_value(value_name: StringName) -> bool:
	return VALUE_NAMES.has(value_name)


## 比值（0..1），供 HUD 与警告阈值使用。`max_value <= 0` 或未知名字返回 0
func ratio(value_name: StringName, max_value: float) -> float:
	if max_value <= 0.0 or not has_value(value_name):
		return 0.0
	return clampf(value_of(value_name) / max_value, 0.0, 1.0)


## 一份**独立**的副本（存档与断言用；改副本不会影响原状态）
func duplicate_state() -> SurvivalState:
	var copy := SurvivalState.new()
	copy.health = health
	copy.hunger = hunger
	copy.thirst = thirst
	copy.stamina = stamina
	copy.last_damage_reason = last_damage_reason
	return copy


func to_dictionary() -> Dictionary:
	return {
		"health": health,
		"hunger": hunger,
		"thirst": thirst,
		"stamina": stamina,
		"last_damage_reason": last_damage_reason,
	}
