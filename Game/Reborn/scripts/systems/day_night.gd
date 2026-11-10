extends RefCounted
## T057：简化昼夜光照的**纯函数**部分（不持有节点、不读全局状态）。
##
## 为什么单独拆出来：光照必须能"只凭世界时间算出来"，存档恢复才可能正确 ——
## 只要采样是纯函数、且每帧都是"按当前 `world_time` 重算"而不是"累加"，恢复就天然正确。
##
## 时间口径沿用 T034（`Docs/Parameters.md` 第 83/255~258 行）：
## `day_length = 1200 s`，`WorldTime = 0` 是**白天起点**，昼夜对半（白天 [0,600)、夜晚 [600,1200)）。
##
## 光照形状（刻意简单，够读）：
##   白天 `p∈[0,0.5)`：仰角 `70·sin(π·d)`（d 是白天进度 0→1），能量 `0.35 + 0.95·sin`，色温随风化；
##   夜晚 `p∈[0.5,1)`：太阳在地平线下，改用**月光**（冷色、能量 0.12、环境光不低于 0.26）；
##   环境光下限 `NIGHT_AMBIENT_FLOOR = 0.26` —— 这是"夜间仍需看清基本路线"的可判定下界。

const DAY_LENGTH := 1200.0
const NIGHT_START_RATIO := 0.5

const NOON_ELEVATION := 70.0
const NIGHT_ELEVATION := -20.0
const NIGHT_ELEVATION_DEPTH := 50.0

const DAY_ENERGY_BASE := 0.35
const DAY_ENERGY_SWING := 0.95
const MOON_ENERGY := 0.12

const DAY_AMBIENT_BASE := 0.35
const DAY_AMBIENT_SWING := 0.50
const NIGHT_AMBIENT_FLOOR := 0.26

## 低角度暖光 → 正午白光
const COLOR_WARM := Color(1.0, 0.72, 0.45)
const COLOR_NOON := Color(1.0, 0.97, 0.92)
## 月光（冷色，`b > r` 是"夜"的可判定特征）
const COLOR_MOON := Color(0.55, 0.66, 0.95)


## 世界时间 → 光照参数（纯函数；同输入必同输出）
static func sample(world_time: float, day_length: float = DAY_LENGTH) -> Dictionary:
	var L: float = day_length if day_length > 0.0 else DAY_LENGTH
	var t: float = maxf(0.0, world_time)
	var p: float = fmod(t, L) / L
	var is_day: bool = p < NIGHT_START_RATIO
	var elevation := 0.0
	var energy := 0.0
	var ambient := 0.0
	var color := COLOR_NOON
	if is_day:
		var d: float = p / NIGHT_START_RATIO           # 0 = 日出，1 = 日落
		var arc: float = sin(PI * d)
		elevation = NOON_ELEVATION * arc
		energy = DAY_ENERGY_BASE + DAY_ENERGY_SWING * arc
		ambient = DAY_AMBIENT_BASE + DAY_AMBIENT_SWING * arc
		color = COLOR_WARM.lerp(COLOR_NOON, clampf(arc, 0.0, 1.0))
	else:
		var n: float = (p - NIGHT_START_RATIO) / NIGHT_START_RATIO   # 0 = 入夜，1 = 破晓
		elevation = NIGHT_ELEVATION - NIGHT_ELEVATION_DEPTH * sin(PI * n)
		energy = MOON_ENERGY
		ambient = NIGHT_AMBIENT_FLOOR
		color = COLOR_MOON
	return {
		"world_time": t,
		"phase": p,
		"is_day": is_day,
		"elevation_deg": elevation,
		"azimuth_deg": 90.0 + 180.0 * p,     # 一天转半圈多一点，够表现方向变化
		"energy": energy,
		"ambient": ambient,
		"color": color,
	}


## 把采样结果写到真实节点上（只碰旋转/能量/颜色/环境光，不改雾/色调映射等 ART 设置）
static func apply(sample_data: Dictionary, sun: DirectionalLight3D, env: Environment) -> void:
	if sun != null:
		sun.rotation_degrees = Vector3(-float(sample_data["elevation_deg"]), float(sample_data["azimuth_deg"]), 0.0)
		sun.light_energy = float(sample_data["energy"])
		sun.light_color = sample_data["color"]
	if env != null:
		env.ambient_light_energy = float(sample_data["ambient"])
