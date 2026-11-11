extends Node
## T057：简化昼夜光照 —— 把 `day_night.gd` 的纯函数结果**按当前世界时间重算**并写到场景里。
##
## 为什么"重算"而不是"累加"：存档恢复的正确性不靠额外代码，而靠**无状态**——
## 读档把 `WorldDirector.world_time` 设回存档值，下一帧光照自然就是那一刻的样子；
## 反过来，如果这里做 `+= delta` 的动画式推进，读档后就必须再补一次"快进到正确相位"，
## 那才是容易写错的地方。
##
## 只写这些字段：太阳旋转 / 能量 / 颜色、环境光（来源/颜色/能量）、天空材质倍率。
## 雾、色调映射、SSAO 等 ART 设置不动。
##
## 【T060 性能修正】原实现**每帧**都 `apply_now()`（世界时间每帧都在变），于是每帧都写
## `DirectionalLight3D` + `Environment` + `Sky` 材质 ≈ 8 个属性 → 触发渲染服务每帧重推环境资源。
## 实测（真实一局、同机位、720p）：关掉本 director 的 `_process` 后整帧 **5.249 → 4.415 ms（−0.79 ms，−15%）**，
## 比植被（−0.25 ms）与 AI（≈0）都大 ⇒ 限频到 `MIN_APPLY_INTERVAL`（默认 0.25 世界秒 ≈ 4 Hz）。
## 语义不变：采样仍是 `world_time` 的**纯函数**（无状态），只是"多久写一次"变了；
## 1200 s 一天的昼夜曲线在 4 Hz 下最多晚 0.25 s（整天的 1/4800），肉眼不可分。

const DAY_NIGHT := preload("res://scripts/systems/day_night.gd")

## 自动应用的最小间隔（世界秒）。显式 `apply_now()` 不受它限制。
const MIN_APPLY_INTERVAL := 0.25

var enabled := true

## 「必要感知差异可调」的预留旋钮：夜间视距/可见度倍率。
## 默认 1.0 = **不改玩法**；要调必须显式改这里并重跑感知相关套件（T020/T023/T024）。
var night_sight_multiplier := 1.0

var sun: DirectionalLight3D = null
var environment: Environment = null

var last_sample: Dictionary = {}
var apply_count := 0

var _last_time := -1.0
## 上一次真正写进场景时的世界时间（`apply_now()` 会更新它）
var _last_applied_world_time := -1.0


func _process(_delta: float) -> void:
	if not enabled or sun == null:
		return
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	var t: float = float(wd.get("world_time"))
	if is_equal_approx(t, _last_time):
		return
	# T060：限频（见文件头）。时间跳变（读档/休息快进）差值必然 ≥ 间隔，所以不会漏更新。
	if _last_applied_world_time >= 0.0 and absf(t - _last_applied_world_time) < MIN_APPLY_INTERVAL:
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
	_last_applied_world_time = -1.0
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
	_last_applied_world_time = t
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
	_last_applied_world_time = -1.0
