class_name AttackSettlement
extends Node3D
## NPC 攻击结算组件（T025）：**预警 → 伤害帧 → 恢复**，挂在**攻击者**身上。
##
## 真源：`Docs/Parameters.md` **第 69 行**「猫 NPC：Alert 0.4s；**AttackRange 65**；**预警0.45s**；**伤害35**；
## **攻击恢复1.2s**；…**伤害帧以当前距离/遮挡检查**」；
## `Docs/TechnicalDesign.md` §6 第 230/231 行「猫攻击链 `APPROACH → CHASE → ATTACK`；**攻击开始即保存方向与目标信息；
## 伤害帧重新检查距离/遮挡/目标存活**」。
##
## 分工（与 T021 `CaptureSettlement` 同结构）：
##   * **本组件**：计时、伤害帧的**四查一结算**、诊断与信号。**只执行 + 结算**，不改 AI 状态机、不写位移。
##   * **AI**（`CatAI`）：决定"什么时候打"（只调 `body.request_attack()`）。
##   * **身体**（`AnimalBody`）：动作互斥（`ACT.ATTACKING`）、锁朝向、禁扑击/跳跃/交互。
##
## 判定口径（`Docs/Tasks/T025.md` §4）：
##   ① 目标个体仍在（不是"重新找最近的"）② 水平距离 ≤ `attack_range` + 0.05（迟滞同 `RANGE_HYSTERESIS`）
##   ③ 朝向：与**攻击开始时锁定的方向**夹角 ≤ `attack_facing_half_angle_deg` ④ 无遮挡。
##   **④ 必须自己打射线，不能借 `Perception.can_see_point()`**：攻击距离 0.65 m 落在感知的
##   近距豁免（0.80 m）内，用感知判据会让"绕墙"永远命中（A04 的反面用例就守在这里）。

## 一次攻击开始（预警起）
signal attack_started(target_id: String)
## 伤害帧结算：`applied` 为真才真的掉了血
signal attack_landed(target_id: String, damage: float, applied: bool)
## 一次攻击结束（含预警与恢复）
signal attack_ended(target_id: String, hit: bool)

## 动物碰撞层（`2`）= 可被攻击的目标层（T011 约定）
const ANIMAL_LAYER := 2
## 静态世界层（`1`）= 遮挡射线的唯一来源（与 `Perception` 同口径）
const WORLD_STATIC_LAYER := 1
## 伤害帧的距离迟滞（米）：与 `CatAI.RANGE_HYSTERESIS` 同口径
const HIT_TOLERANCE := 0.05

## 被驱动的身体（`setup()` 里赋值）
var body: AnimalBody = null
## 物种配置（攻击参数真源）
var config: SpeciesConfig = null
## 发起次数（含未命中的）
var attack_count: int = 0
## 命中次数（真的掉了血）
var hit_count: int = 0
## 未命中次数
var miss_count: int = 0
## 最近一次命中施加的伤害
var last_damage: float = 0.0
## 最近一次命中的目标 ID
var last_hit_target_id: String = ""
## 最近一次启动被拒的原因（诊断）
var blocked_reason: StringName = &""

var _telegraphing := false
var _telegraph_started_at := 0.0
var _telegraph_end_at := 0.0
var _recovery_end_at := 0.0
var _target: AnimalBody = null
var _target_id := ""
var _locked_dir := Vector3.ZERO
var _miss_reason: StringName = &""


func setup(p_body: AnimalBody, p_config: SpeciesConfig) -> void:
	body = p_body
	config = p_config


func world_time_now() -> float:
	if body != null and is_instance_valid(body) and body.has_method("world_time_now"):
		return float(body.world_time_now())
	return 0.0


func _now() -> float:
	return world_time_now()


# ---------------------------------------------------------------------------
# 门控与启动
# ---------------------------------------------------------------------------

## 这个物种会攻击吗（`SpeciesConfig.can_attack`）
func can_attack() -> bool:
	return config != null and config.can_attack


## 发起一次攻击。
##
## 成功：预警开始（**立即**记 `attack_count`、锁定朝向与目标）、返回 `true`。
## 失败：返回 `false` 并写 `blocked_reason`（`species`/`dead`/`captured`/`airborne`/`busy`/`target`）。
func start_attack() -> bool:
	blocked_reason = &""
	if not can_attack():
		blocked_reason = &"species"
		return false
	if body == null or not is_instance_valid(body):
		blocked_reason = &"dead"
		return false
	if body.captured:
		blocked_reason = &"captured"
		return false
	if body.survival != null and body.survival.is_dead():
		blocked_reason = &"dead"
		return false
	if body.is_on_floor() == false:
		blocked_reason = &"airborne"
		return false
	if is_attacking() or is_in_recovery():
		blocked_reason = &"busy"
		return false
	if body.interaction != null and body.interaction.is_interacting():
		blocked_reason = &"busy"
		return false
	var target := resolve_target()
	if target == null:
		blocked_reason = &"target"
		return false
	_telegraphing = true
	_telegraph_started_at = _now()
	_telegraph_end_at = _telegraph_started_at + maxf(0.01, config.attack_telegraph)
	_recovery_end_at = 0.0
	_target = target
	_target_id = _id_of(target)
	_locked_dir = _forward()
	_miss_reason = &""
	attack_count += 1
	body.on_attack_started()
	attack_started.emit(_target_id)
	return true


## 由身体**每物理帧**调用（喂世界时间；不累加 delta）
func step(world_time: float) -> void:
	if _telegraphing and world_time >= _telegraph_end_at:
		_telegraphing = false
		# **必须先结算再清锁定方向**：朝向复核用的就是 `_locked_dir`
		# （清零后 `_facing_direction()` 会走"无方向 = 放行"的兜底，朝向检查就失效了）
		var hit := _damage_frame(world_time)
		_locked_dir = Vector3.ZERO
		_recovery_end_at = world_time + maxf(0.01, config.attack_recovery)
		attack_ended.emit(_target_id, hit)
	if _recovery_end_at > 0.0:
		if world_time >= _recovery_end_at:
			_recovery_end_at = 0.0
			_target = null
			_target_id = ""
			body.on_attack_ended()


# ---------------------------------------------------------------------------
# 伤害帧：四查一结算
# ---------------------------------------------------------------------------

func _damage_frame(_world_time: float) -> bool:
	var reason := &""
	if _target == null or not is_instance_valid(_target):
		reason = &"target_lost"
	elif _target.survival == null:
		reason = &"target_lost"
	elif _target.captured or _target.survival.is_dead():
		reason = &"dead"
	elif horizontal_distance_to(_target) > config.attack_range + HIT_TOLERANCE:
		reason = &"out_of_range"
	elif not _facing_locked(_target):
		reason = &"facing"
	elif occluded(_target):
		reason = &"occluded"
	if reason != &"":
		miss_count += 1
		_miss_reason = reason
		attack_landed.emit(_target_id, config.attack_damage, false)
		return false
	_target.survival.apply_damage(config.attack_damage, &"attack")
	hit_count += 1
	last_damage = config.attack_damage
	last_hit_target_id = _target_id
	attack_landed.emit(_target_id, config.attack_damage, true)
	return true


# ---------------------------------------------------------------------------
# 目标解析与几何
# ---------------------------------------------------------------------------

## 在本体周围 `attack_range` 内找一个**可攻击**的目标（`animal` 层 + 异种 + 存活 + 未捕获 + 朝向 + 无遮挡）。
## 不写物种名分支：用 `species_id` 判"异种"。
func resolve_target() -> AnimalBody:
	if body == null or not is_instance_valid(body):
		return null
	var space := body.get_world_3d().direct_space_state
	if space == null:
		return null
	var shape := SphereShape3D.new()
	shape.radius = maxf(0.05, config.attack_range * 1.05)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), body.global_position)
	params.collision_mask = ANIMAL_LAYER
	params.collide_with_areas = false
	params.exclude = [body.get_rid()]
	var best: AnimalBody = null
	var best_distance := INF
	for hit in space.intersect_shape(params, 16):
		var other := hit.get("collider") as AnimalBody
		if other == null or other == body or not is_instance_valid(other):
			continue
		if not _is_valid_target(other):
			continue
		var d := horizontal_distance_to(other)
		if d > config.attack_range + HIT_TOLERANCE or d >= best_distance:
			continue
		if not _facing_direction(_forward(), other):
			continue
		if occluded(other):
			continue
		best = other
		best_distance = d
	return best


func _is_valid_target(other: AnimalBody) -> bool:
	if other.species_config == null or other.survival == null:
		return false
	if StringName(other.species_config.species_id) == _my_species_id():
		return false
	if other.captured or other.survival.is_dead():
		return false
	return true


## 目标到本体的**水平**距离（`Parameters` 第 69 行的 AttackRange 是水平距离；竖直差不算，见 T025 E4）
func horizontal_distance_to(other: AnimalBody) -> float:
	var d := other.global_position - body.global_position
	d.y = 0.0
	return d.length()


func _forward() -> Vector3:
	var f := -body.global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 1e-8:
		return Vector3.FORWARD
	return f.normalized()


func _facing_locked(other: AnimalBody) -> bool:
	return _facing_direction(_locked_dir, other)


func _facing_direction(dir: Vector3, other: AnimalBody) -> bool:
	if dir.length_squared() < 1e-8:
		return true
	var to := other.global_position - body.global_position
	to.y = 0.0
	if to.length_squared() < 1e-8:
		return true
	var cos_angle := clampf(dir.normalized().dot(to.normalized()), -1.0, 1.0)
	return rad_to_deg(acos(cos_angle)) <= config.attack_facing_half_angle_deg + 1e-6


## 视线被 `world_static` 挡住吗。**不走 `Perception` 的近距豁免**（T025 D4）。
func occluded(other: AnimalBody) -> bool:
	if body == null or not is_instance_valid(body):
		return true
	var space := body.get_world_3d().direct_space_state
	if space == null:
		return false
	var from := body.eye_position()
	var to := other.eye_position()
	if from.distance_to(to) <= 1e-4:
		return false
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = WORLD_STATIC_LAYER
	params.collide_with_areas = false
	params.exclude = [body.get_rid(), other.get_rid()]
	return not space.intersect_ray(params).is_empty()


func _id_of(other: AnimalBody) -> String:
	return String(other.name)


func _my_species_id() -> StringName:
	if body != null and is_instance_valid(body) and body.species_config != null:
		return StringName(body.species_config.species_id)
	return &""


# ---------------------------------------------------------------------------
# 查询（"状态和原因可查看"）
# ---------------------------------------------------------------------------

## 预警中
func is_attacking() -> bool:
	return _telegraphing


## 恢复期（1.2 s）内；到点自动结束
func is_in_recovery() -> bool:
	if _recovery_end_at <= 0.0:
		return false
	if _now() < _recovery_end_at:
		return true
	_recovery_end_at = 0.0
	_target = null
	_target_id = ""
	return false


func state_name() -> String:
	if _telegraphing:
		return "telegraphing"
	if is_in_recovery():
		return "recovering"
	return "idle"


func telegraph_elapsed(world_time: float = NAN) -> float:
	if not _telegraphing:
		return 0.0
	var now := world_time if not is_nan(world_time) else _now()
	return maxf(0.0, now - _telegraph_started_at)


func recovery_elapsed(world_time: float = NAN) -> float:
	if _recovery_end_at <= 0.0:
		return 0.0
	var now := world_time if not is_nan(world_time) else _now()
	var total := maxf(0.01, config.attack_recovery)
	return clampf(total - maxf(0.0, _recovery_end_at - now), 0.0, total)


func target_id() -> String:
	return _target_id


func last_miss_reason() -> StringName:
	return _miss_reason


func report() -> Dictionary:
	return {
		"can_attack": can_attack(),
		"state": state_name(),
		"attack_count": attack_count,
		"hit_count": hit_count,
		"miss_count": miss_count,
		"last_damage": last_damage,
		"last_hit_target": last_hit_target_id,
		"target": _target_id,
		"miss_reason": _miss_reason,
		"blocked": blocked_reason,
		"telegraph": (config.attack_telegraph if config != null else 0.0),
		"recovery": (config.attack_recovery if config != null else 0.0),
		"damage": (config.attack_damage if config != null else 0.0),
		"range": (config.attack_range if config != null else 0.0),
	}
