class_name SpeciesConfig
extends Resource
## 物种配置 —— **两个物种的差异只写在这里**，代码里不做物种名判断
##
## 字段与含义按 `Docs/TechnicalDesign.md` §3 的数据契约；数值按 `Docs/Parameters.md`（厘米 → 米，÷100）。
## 谁要改数值：改 `Game/Reborn/resources/species/*.tres`，**不要**在系统代码里另写一份。
##
## 校验：`validate_config()` 用于加载后检查（T008 断言两个实例都返回空）。

## 食物类型（契约枚举，`Docs/TechnicalDesign.md` §2）
enum FoodType { MEAT, SEED }

## 稳定物种 ID：`&"Cat"` / `&"Mouse"`（**拼写固定**，不要用大小写变体）
@export var species_id: StringName = &""

@export_group("Movement")
## 胶囊半径（米）
@export var capsule_radius: float = 0.0
## 胶囊**半高**（米）。注意 Godot 的 `CapsuleShape3D.height` 是**含两端半球的总高** = 2×本值
@export var capsule_half_height: float = 0.0
## 潜伏（蹲姿）时的胶囊半高（米）。**比站姿小**，蹲下时胶囊变矮、视线变低（T009）
##
## 事实说明：`Docs/Parameters.md` **没有**蹲姿碰撞高度这一项（只有 `CrouchSpeed`）。
## 这是 T009 新增参数，取值见 `Docs/Tasks/T009.md` §4.2，**待负责人并入正式起测值**。
@export var crouch_half_height: float = 0.0
@export var walk_speed: float = 0.0
@export var sprint_speed: float = 0.0
@export var crouch_speed: float = 0.0
## 可上台阶高度（米）。由 `StepClimb` 组件消费
@export var max_step_height: float = 0.0
@export var jump_velocity: float = 0.0
@export var max_acceleration: float = 0.0
## 相机相对胶囊中心的**竖直（本地 +Y）**偏移（米），T009 实测确认。
##
## 为什么不是 +Z：`Parameters.md` 的参数表源自 UE 版（`CameraZ`/`JumpZVelocity`/`MaxStepHeight`），
## UE 里 Z 是上方向；按本地 +Z 实现会把第一人称相机放到身体**后面**而不是眼高。
## 字段名沿用契约（`TechnicalDesign.md` §3），只改轴向语义。见 `Docs/Tasks/T009.md` §4.1。
@export var camera_offset_z: float = 0.0
@export var fov: float = 90.0

@export_group("Perception")
## 视距（米）
@export var vision_range: float = 0.0
@export var vision_half_angle_deg: float = 0.0
## 听觉范围（米，对应"标准跑步声"Loudness=1.0）
@export var hearing_range: float = 0.0

@export_group("Noise")
## 脚步噪声响度（`Docs/Parameters.md` 第 73 行：潜伏 / 行走 / 奔跑 = 0.2 / 0.5 / 1.0）。
## 消费方：`AnimalBody.noise_loudness()`；听觉距离 = `hearing_range × loudness`。
@export var noise_loudness_crouch: float = 0.2
@export var noise_loudness_walk: float = 0.5
@export var noise_loudness_sprint: float = 1.0
## 标准行走时**每步**的间隔（秒）。`Parameters.md` 第 73 行只给了响度、没给节奏 →
## **T020 新增值**（见 `Docs/Tasks/T020.md` §9），其他档位按速度反比缩放。
@export var footstep_interval_base: float = 0.5

@export_group("Survival")
## 生存容量上限（T014）。来自 `Docs/Parameters.md` 第 15 行「初始 Health/Hunger/Thirst/Stamina = 100/100/100/100」；
## 食物/饮水"成功后全值夹紧"用的也是这四个上限。
@export var max_health: float = 100.0
@export var max_hunger: float = 100.0
@export var max_thirst: float = 100.0
@export var max_stamina: float = 100.0
@export_group("Costs & Damage")
## 能**开始**冲刺所需的最低体力（`Parameters.md` 第 65 行："Sprint 只有 Stamina≥5 可开始"）
@export var sprint_min_stamina: float = 5.0
## 饥渴**警告**阈值（`Parameters.md` 第 65 行：Hunger/Thirst ≤ 25 发警告）
@export var low_stat_threshold: float = 25.0
## 饥饿归零后的持续伤害（每秒）
@export var starvation_damage_per_sec: float = 1.0
## 水分归零后的持续伤害（每秒）。两项均归零时自然叠加为 2/s
@export var dehydration_damage_per_sec: float = 1.0
## 落地**无伤**的垂直速度上限（米/秒）。`Parameters.md`：「落地前垂直速度绝对值 ≤ 700」= 7 m/s
@export var fall_safe_vertical_speed: float = 7.0
## 超过安全速度后每 1 m/s 的伤害。`Parameters.md`：「(speed−700)×0.1」（cm/s 口径）→ 米制 ×10
@export var fall_damage_scale: float = 10.0
@export var hunger_loss_per_sec: float = 0.0
@export var thirst_loss_per_sec: float = 0.0
@export var sprint_stamina_per_sec: float = 0.0
@export var stamina_regen_per_sec: float = 0.0
@export var regen_delay: float = 0.0
## 交互距离（米）
@export var interaction_range: float = 0.0

@export_group("Abilities")
## 可食食物类型（`FoodType` 值）
@export var allowed_food_types: Array[int] = []
@export var can_jump: bool = false
@export var can_pounce: bool = false
## 能否使用鼠洞（猫为 false —— 鼠洞是猫的硬边界）
@export var can_use_mouse_tunnel: bool = false


## 行为（T019）：指向驱动这个物种的 AI 脚本（`AnimalAI` 子类）。
## 用**脚本引用**而不是"物种名判断"来选择状态机 —— 差异全在 `resources/species/*.tres` 里。
## 留空表示"暂时没有 AI"（猫的状态机属 T023）。
@export_group("Behavior")
@export var ai_script: Script = null


## Godot 的 `CapsuleShape3D.height` 是含两端半球的总高
func capsule_height() -> float:
	return capsule_half_height * 2.0


## 潜伏（蹲姿）时的胶囊总高（米），口径与 `CapsuleShape3D.height` 一致
func crouch_height() -> float:
	return crouch_half_height * 2.0


## 蹲下时胶囊顶面相对站姿顶面的下降量（米）= 相机应下降的量
func crouch_drop() -> float:
	return maxf(0.0, capsule_half_height - crouch_half_height)


## 胶囊长度与半径的比值（调试用：鼠比猫更"长条"）
func capsule_aspect() -> float:
	return capsule_height() / capsule_radius if capsule_radius > 0.0 else INF


func can_eat(food_type: int) -> bool:
	return allowed_food_types.has(food_type)


## 加载后校验。返回问题列表（空 = 通过）。
## 只检查"必须成立"的量，不做平衡判断。
func validate_config() -> PackedStringArray:
	var problems := PackedStringArray()
	if species_id == &"":
		problems.append("species_id 为空")
	if capsule_radius <= 0.0 or not is_finite(capsule_radius):
		problems.append("capsule_radius 必须 > 0")
	if capsule_half_height <= 0.0 or not is_finite(capsule_half_height):
		problems.append("capsule_half_height 必须 > 0")
	# 蹲姿必须真的更矮（否则"潜伏"没有意义，低顶通行也无从谈起）
	if crouch_half_height <= 0.0 or not is_finite(crouch_half_height):
		problems.append("crouch_half_height 必须 > 0")
	elif crouch_half_height >= capsule_half_height:
		problems.append("crouch_half_height 必须小于 capsule_half_height（蹲姿要更矮）")
	if max_step_height < 0.0 or not is_finite(max_step_height):
		problems.append("max_step_height 不能为负")
	if not is_finite(camera_offset_z):
		problems.append("camera_offset_z 必须是有限值")
	if fov <= 0.0 or fov >= 180.0:
		problems.append("fov 必须在 (0,180)")
	if walk_speed <= 0.0 or crouch_speed <= 0.0:
		problems.append("walk_speed/crouch_speed 必须 > 0")
	if sprint_speed < walk_speed:
		problems.append("sprint_speed 不应低于 walk_speed")
	if allowed_food_types.is_empty():
		problems.append("allowed_food_types 不能为空")
	if can_jump and jump_velocity <= 0.0:
		problems.append("can_jump 为 true 时 jump_velocity 必须 > 0")
	if not can_jump and jump_velocity > 0.0:
		problems.append("can_jump 为 false 时 jump_velocity 应为 0")
	# 台阶不能超过胶囊总高的一半（否则"上台阶"退化成"爬墙"）
	if max_step_height > capsule_height() * 0.5:
		problems.append("max_step_height 不应超过胶囊总高的一半")
	# 生存容量（T014）：容量必须为正，否则"夹紧"会把所有数值压到 0
	for pair in [["max_health", max_health], ["max_hunger", max_hunger],
			["max_thirst", max_thirst], ["max_stamina", max_stamina]]:
		if float(pair[1]) <= 0.0 or not is_finite(float(pair[1])):
			problems.append("%s 必须 > 0（生存容量）" % pair[0])
	# 消耗与伤害（T015）：数值来自 `Parameters.md` 第 65 行（标"共同"，两物种同值）
	var t015_non_negative := [
		["sprint_min_stamina", sprint_min_stamina], ["low_stat_threshold", low_stat_threshold],
		["starvation_damage_per_sec", starvation_damage_per_sec],
		["dehydration_damage_per_sec", dehydration_damage_per_sec],
		["fall_safe_vertical_speed", fall_safe_vertical_speed],
		["fall_damage_scale", fall_damage_scale],
	]
	for pair in t015_non_negative:
		if float(pair[1]) < 0.0 or not is_finite(float(pair[1])):
			problems.append("%s 不能为负（T015 消耗/伤害）" % pair[0])
	if fall_damage_scale <= 0.0:
		problems.append("fall_damage_scale 必须 > 0（否则跌落永远不造成伤害）")
	if low_stat_threshold > max_hunger or low_stat_threshold > max_thirst:
		problems.append("low_stat_threshold 不应高于饥渴容量（否则一出生就报警）")
	# 噪声（T020）：响度必须在 (0,1]，且"越快越响"（潜伏 ≤ 行走 ≤ 奔跑，Parameters.md 第 73 行）
	for pair in [["noise_loudness_crouch", noise_loudness_crouch],
			["noise_loudness_walk", noise_loudness_walk],
			["noise_loudness_sprint", noise_loudness_sprint]]:
		if float(pair[1]) <= 0.0 or float(pair[1]) > 1.0 or not is_finite(float(pair[1])):
			problems.append("%s 必须在 (0,1]（脚步噪声响度）" % pair[0])
	if noise_loudness_walk < noise_loudness_crouch or noise_loudness_sprint < noise_loudness_walk:
		problems.append("噪声响度应满足 潜伏 ≤ 行走 ≤ 奔跑（越快的档位越响）")
	if footstep_interval_base <= 0.0 or not is_finite(footstep_interval_base):
		problems.append("footstep_interval_base 必须 > 0（否则脚步事件无处产生）")
	return problems
