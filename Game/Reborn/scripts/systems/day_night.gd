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
##   夜晚 `p∈[0.5,1)`：太阳在地平线下，改用**月光**（冷色、能量 0.12）；**天空本身压暗**到
##   `NIGHT_SKY_ENERGY`，环境光切到 `AMBIENT_SOURCE_COLOR` 并给 `NIGHT_AMBIENT_FLOOR` 下界
##   —— 这是"夜间仍需看清基本路线"的可判定下界。
##
## 【2026-11-10 修正（T057 视觉判读）】原实现只写 `Environment.ambient_light_energy`，但本工程
## 的 `ambient_light_source = AMBIENT_SOURCE_SKY`、`ambient_light_sky_contribution = 1.0`，
## 而 ART07 已实测"**`ambient_light_energy` 对 SKY 源无效**（0.72 与 1.0 渲染像素完全一致）"。
## 结果：夜间只有太阳变暗，天空 HDRI 与天光仍是白天 ⇒ 实拍 `mean_luma` 115.6 vs 正午 142.5（81%），
## vision 把夜间帧判成"白天/像暗一点的白天"。
## 修正不改白天一帧：白天仍写 SKY 源（该值本就无效，画面零变化），只在夜间换成
## ① 天空材质 `energy_multiplier`（== 天光辐照 + 天空亮度，ART07 认定的正确旋钮）
## ② `AMBIENT_SOURCE_COLOR` + 冷色环境光（保证夜里地形与路线可读）。

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
## 夜间环境光下限。**第二次修正（2026-11-11）**：0.26 → **0.40** —— 实测 0.26 时画面是
## "树冠缝隙的高光 + 后方树林死黑剪影"，vision 仍判「白天」；夜间要的是**均匀的暗**，
## 所以抬环境光（diffuse 铺满全画面）而不是抬月光。
const NIGHT_AMBIENT_FLOOR := 0.40
## 天空自身亮度/天光辐照的倍率：白天维持 ART 现场（1.0），夜间压到 0.03。
## 第一次修正取 0.12 时树冠缝隙仍是"亮白色的日光斑"，视觉得到"阳光穿透树冠"的印象 → 再压一档。
const DAY_SKY_ENERGY := 1.0
const NIGHT_SKY_ENERGY := 0.03

## 低角度暖光 → 正午白光
const COLOR_WARM := Color(1.0, 0.72, 0.45)
const COLOR_NOON := Color(1.0, 0.97, 0.92)
## 月光（冷色，`b > r` 是"夜"的可判定特征）
const COLOR_MOON := Color(0.55, 0.66, 0.95)
## 夜间环境光（`AMBIENT_SOURCE_COLOR`）：偏蓝的冷色，用来把地形与路线**均匀**抬到看得清。
## 第二次修正把红色通道再压低（0.42→0.32），让夜里的地面偏冷而不是"灰亮"。
const COLOR_NIGHT_AMBIENT := Color(0.32, 0.40, 0.62)


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
	var sky_energy: float = DAY_SKY_ENERGY if is_day else NIGHT_SKY_ENERGY
	return {
		"world_time": t,
		"phase": p,
		"is_day": is_day,
		"elevation_deg": elevation,
		"azimuth_deg": 90.0 + 180.0 * p,     # 一天转半圈多一点，够表现方向变化
		"energy": energy,
		"ambient": ambient,
		"color": color,
		## 天空材质倍率：白天 1.0（ART 现场原值），夜间压暗
		"sky_energy": sky_energy,
		## 环境光来源：白天沿用工程现场（SKY），夜间切 COLOR 才能让 ambient 真的生效
		"ambient_source": "sky" if is_day else "color",
		"ambient_color": COLOR_NOON if is_day else COLOR_NIGHT_AMBIENT,
	}


## 把采样结果写到真实节点上。
##
## 写的东西：太阳旋转/能量/颜色；环境光的**来源/颜色/能量**；天空材质的 `energy_multiplier`。
## 不碰雾、色调映射、SSAO、曝光等 ART 设置（`run_art09_frame_contract` 锁着）。
static func apply(sample_data: Dictionary, sun: DirectionalLight3D, env: Environment) -> void:
	if sun != null:
		sun.rotation_degrees = Vector3(-float(sample_data["elevation_deg"]), float(sample_data["azimuth_deg"]), 0.0)
		sun.light_energy = float(sample_data["energy"])
		sun.light_color = sample_data["color"]
	if env == null:
		return
	env.ambient_light_energy = float(sample_data["ambient"])
	# 环境光来源：白天 SKY（工程现场、且该源的 energy 无效 → 画面与改前逐像素一致），
	# 夜间 COLOR（这是让 NIGHT_AMBIENT_FLOOR 真正生效的唯一途径）。
	var want_color := String(sample_data.get("ambient_source", "sky")) == "color"
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if want_color else Environment.AMBIENT_SOURCE_SKY
	if want_color:
		env.ambient_light_color = sample_data.get("ambient_color", COLOR_NIGHT_AMBIENT)
	# 天空材质倍率（Panorama/Procedural 都叫 `energy_multiplier`；没有就跳过，不报错）
	if env.sky != null and env.sky.sky_material != null:
		var mat: Object = env.sky.sky_material
		if "energy_multiplier" in mat:
			mat.set("energy_multiplier", float(sample_data.get("sky_energy", DAY_SKY_ENERGY)))
