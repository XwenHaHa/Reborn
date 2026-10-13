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
