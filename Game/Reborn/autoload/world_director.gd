extends Node
## 世界统一入口（Autoload 单例）
##
## 职责（T002 阶段只实现时间；T014/T034 扩充资源注册与区域账本）：
##   - 维护 sim time（世界时间），驱动资源恢复与昼夜
##   - 暂停 / 结算 / 选择 / 加载时不推进
##
## 单位约定：世界时间用秒（float）。距离一律用米。
## 依据 Docs/TechnicalDesign.md §5。

## 世界时间（sim seconds），新游戏从 0 开始。禁止用墙钟系统时间。
var world_time: float = 0.0

## 单独的时间推进开关。get_tree().paused 之外再给一个显式门闩，
## 用于"结算/选物种/加载"这类必须停表但不一定暂停整棵树的状态。
var time_advancing: bool = true

## 本帧的 sim delta，供各系统读取，避免每处自己算。
var sim_delta: float = 0.0

## 行动噪声总线（T020；`Docs/TechnicalDesign.md` §4 信号表 `action_noise`）：
## 每次**脚步事件**发一次（**不是每帧**），带来源 ID、发生位置、响度与世界时间。
## 感知方（`scripts/systems/perception.gd`）只从这里取"声音**发生**位置 + 时间"，
## **不建立对声源的持续跟踪**（§6：听见声音只得到声音位置）。
signal noise_emitted(source_id: String, position: Vector3, loudness: float, world_time: float)

## 本次运行广播过的噪声事件数（诊断/断言用）
var noise_event_count: int = 0


func _process(delta: float) -> void:
	if not time_advancing:
		sim_delta = 0.0
		return
	sim_delta = delta
	world_time += delta


## 供存档/读档设置世界时间，不触发恢复结算。
func set_world_time(t: float) -> void:
	world_time = maxf(0.0, t)


## 供新游戏重置。只有明确的新游戏确认才可调用（TechnicalDesign §7）。
func reset_for_new_game() -> void:
	world_time = 0.0
	time_advancing = true
	# 捕获账本（T021）也必须随新游戏清零，否则新一局会把旧的猎物判成"已记账"
	capture_count = 0
	capture_food_count = 0
	captured_target_ids = {}


## 当前世界时间（秒）——**统一时间入口**。
## 所有按时间的系统（生存消耗、资源恢复、昼夜……）都从这里取差推进，**不要各自累加 `delta`**：
## 一个渲染帧可能跑 0/1/2 次物理帧，各自累加会与世界时间漂移。
func get_world_time() -> float:
	return world_time


## 显式门闩的当前状态。注意：**树暂停时 `_process` 不跑，本函数仍可能返回 true** ——
## 要判断"时间是不是真的在走"，看 `world_time` 有没有变（见 `Docs/Tasks/T014.md` 决策 D1）。
func is_time_advancing() -> bool:
	return time_advancing


## 广播一次行动噪声（T020）。`loudness ≤ 0` 直接丢弃；计数只统计真正广播出去的事件。
## 调用方：`AnimalBody._emit_footstep()`（每次脚步事件一次，**不是每帧**）。
func emit_noise(source_id: String, position: Vector3, loudness: float) -> void:
	if loudness <= 0.0:
		return
	noise_event_count += 1
	noise_emitted.emit(source_id, position, loudness, world_time)


## 成功捕获广播（T021；`Docs/TechnicalDesign.md` §7 捕获流程）。每次**真实结算**只发一次。
signal capture_reported(captor_id: String, target_id: String, position: Vector3, world_time: float)

## 本次运行成功结算的捕获次数（诊断/断言用；被拒绝的重复上报不计入）
var capture_count: int = 0

## 本次运行生成的捕获食物对象数（诊断/断言用）
var capture_food_count: int = 0

## 已结算捕获的猎物 ID 账本（`String -> true`），用于幂等去重
var captured_target_ids: Dictionary = {}


## 上报一次捕获（T021）。**幂等**：同一个 `target_id` 只结算一次。
## 返回 true = 本次真的结算了（记账 + 计数 + 发信号）；
## 返回 false = 早就结算过（或 target_id 为空），**不改任何计数、不发信号**（TechnicalDesign §7"检查未记账"）。
func report_capture(captor_id: String, target_id: String, position: Vector3,
		world_time: float = -1.0) -> bool:
	if target_id.is_empty() or captured_target_ids.has(target_id):
		return false
	var t: float = world_time if world_time >= 0.0 else get_world_time()
	captured_target_ids[target_id] = true
	capture_count += 1
	capture_reported.emit(captor_id, target_id, position, t)
	return true


## 该目标是否已被结算过捕获（T021）
func is_captured(target_id: String) -> bool:
	return captured_target_ids.has(target_id)
