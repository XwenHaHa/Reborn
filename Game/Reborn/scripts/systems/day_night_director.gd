extends Node
## T057：简化昼夜光照 —— 把 `day_night.gd` 的纯函数结果**每帧按当前世界时间重算**并写到场景里。
##
## 为什么"重算"而不是"累加"：存档恢复的正确性不靠额外代码，而靠**无状态**——
## 读档把 `WorldDirector.world_time` 设回存档值，下一帧光照自然就是那一刻的样子；
## 反过来，如果这里做 `+= delta` 的动画式推进，读档后就必须再补一次"快进到正确相位"，
## 那才是容易写错的地方。
##
## 只写四个字段：太阳旋转 / 能量 / 颜色、环境光能量。雾、色调映射、SSAO 等 ART 设置不动。

const DAY_NIGHT := preload("res://scripts/systems/day_night.gd")

var enabled := true

## 「必要感知差异可调」的预留旋钮：夜间视距/可见度倍率。
## 默认 1.0 = **不改玩法**；要调必须显式改这里并重跑感知相关套件（T020/T023/T024）。
var night_sight_multiplier := 1.0

var sun: DirectionalLight3D = null
var environment: Environment = null

var last_sample: Dictionary = {}
var apply_count := 0

var _last_time := -1.0


func _process(_delta: float) -> void:
	if not enabled or sun == null:
		return
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	var t: float = float(wd.get("world_time"))
	if is_equal_approx(t, _last_time):
		return
	apply_now()


## 绑定关卡里的太阳与环境（找不到就返回 false，不报错）
func bind_level(level: Node) -> bool:
	if level == null:
		return false
	sun = level.get_node_or_null("SunLight") as DirectionalLight3D
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	environment = we.environment if we != null else null
	_last_time = -1.0
	apply_now()
	return sun != null


## 按**当前**世界时间重算并应用；返回本次采样（测试直接读）
func apply_now() -> Dictionary:
	var wd := get_node_or_null("/root/WorldDirector")
	var t: float = float(wd.get("world_time")) if wd != null else 0.0
	var sample := sample_at(t)
	DAY_NIGHT.apply(sample, sun, environment)
	last_sample = sample
	_last_time = t
	apply_count += 1
	return sample


func sample_at(world_time: float) -> Dictionary:
	var day_length := 1200.0
	var wd := get_node_or_null("/root/WorldDirector")
	if wd != null:
		day_length = float(wd.get("day_length"))
	return DAY_NIGHT.sample(world_time, day_length)


func unbind() -> void:
	sun = null
	environment = null
	last_sample = {}
	_last_time = -1.0
