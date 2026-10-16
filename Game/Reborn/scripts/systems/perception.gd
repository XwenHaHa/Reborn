class_name Perception
extends Node
## 感知组件（T020）：视觉 + 听觉。挂在身体下（与 T016 `InteractionDetector`、T019 `AnimalAI` 同一模式）。
##
## 真源：
##   * `Docs/Parameters.md` **第 73 行**「潜伏/行走/奔跑 Loudness = 0.2/0.5/1.0；当前 **HearingRange×Loudness** 为起测听觉距离。
##     每次脚步事件生成声与噪声，**非每帧生成**。草丛 **VisibilityFactor=0.4**，使视觉发现距离乘该值；
##     **近距 80 内仍按无遮挡检测**」
##   * `Docs/TechnicalDesign.md` §5「草丛用 `Area3D` 提供 `visibility_factor`；实体墙由 `ray_cast` 阻挡」
##   * 同文档 §6「视线有效时更新 `last_known_position`；**声音只创建 `NoiseLocation`（位置 + 时间）**」
##   * 策划案 v1.1 第 179 行「隔着不透明障碍不能直接视觉发现目标；**听见声音只得到声音位置，不获得目标持续的真实位置**」
##   * 同文档 §0 换算表「近距视觉豁免 80 cm」
##
## **本组件只观察、只记录知识**：不写 `move_intent`、不改状态机状态、不改生存数值。
## 决策（进 `alert_for()` 等）由 `AnimalAI` / `MouseAI` 做 —— 与 T016/T019 的分工一致。
##
## 三条语义要点（可断言，见 `tests/run_t020_perception.gd`）：
##   1. **遮挡有效**：`world_static` 挡视线；但近距 `near_detect_range` 内**按无遮挡处理**（草丛系数同样豁免），视野角始终生效。
##   2. **噪声只有发生位置**：`receive_noise()` 只记「发生位置 + 世界时间」，**不跟踪声源**；
##      `last_seen_*`（视觉知识）与 `last_noise_*`（噪声快照）分开放，调用方拿不到"声源真实位置"。
##   3. **听觉不看遮挡、不看草丛**（声音绕过实体），距离判据 = `hearing_range × loudness`。

## 听到一次噪声（位置 + 响度）。**不含声源实体**，避免调用方顺手跟踪真实位置。
signal noise_heard(position: Vector3, loudness: float)

## 身体所属组（T020 D2）：组里**物种 ID 不同**且存活的身体 = 潜在威胁（不写物种名判断）
const GROUP_ANIMAL_BODIES := &"animal_bodies"
## 草丛 / 遮挡体量组（T011 关卡数据：Area3D + `metadata/visibility_factor`）
const GROUP_COVER := &"cover_volumes"

## 近距视觉豁免（米）——`Docs/TechnicalDesign.md` §0「近距视觉豁免 80 cm」。
## 该距离内**跳过草丛系数与遮挡检查**（`Parameters.md` 第 73 行「近距 80 内仍按无遮挡检测」），视野角照旧。
@export var near_detect_range: float = 0.80
## 世界静态层（射线只认这一层；与 `AnimalBody.LAYER_WORLD_STATIC` 一致）
@export var world_static_layer: int = 1

## 被感知的身体（`setup()` 赋值）
var body: AnimalBody = null
## 物种配置（视觉/听觉范围从这里读）
var config: SpeciesConfig = null

var _now: float = 0.0
var _bus: Node = null
var _bus_checked := false

# --- 视觉知识 ---
var _visible := false
## 上一帧是否可见（用来把"发现次数"记成**跳变次数**，而不是每帧 +1）
var _was_visible := false
var _threat: AnimalBody = null
var _threat_position := Vector3.ZERO
var _last_seen_position := Vector3.ZERO
var _last_seen_time := 0.0
var _has_seen := false
var _sight_count := 0
var _visible_threats := 0

# --- 听觉知识（**只有发生位置 + 时间**）---
var _last_noise_position := Vector3.ZERO
var _last_noise_time := 0.0
var _last_noise_loudness := 0.0
var _last_noise_source := ""
var _has_noise := false
var _heard_count := 0

var _unsupported_shape_count := 0


func setup(p_body: AnimalBody, p_config: SpeciesConfig) -> void:
	body = p_body
	config = p_config
	_connect_bus()


func _ready() -> void:
	_connect_bus()


func _connect_bus() -> void:
	if _bus == null:
		if _bus_checked:
			return
		_bus = get_node_or_null("/root/WorldDirector")
		_bus_checked = true
	if _bus == null or not is_instance_valid(_bus):
		return
	if not _bus.has_signal("noise_emitted"):
		return
	if _bus.is_connected("noise_emitted", _on_noise_emitted):
		return
	_bus.connect("noise_emitted", _on_noise_emitted)


func _on_noise_emitted(source_id: String, position: Vector3, loudness: float, world_time: float) -> void:
	receive_noise(source_id, position, loudness, world_time)


# ---------------------------------------------------------------------------
# 每帧：刷新"是否看见威胁"
# ---------------------------------------------------------------------------

## 由身体**每物理帧**调用（喂世界时间；不累加 delta，暂停时世界时间不前进）
func tick(world_time: float) -> void:
	_now = world_time
	_visible = false
	_threat = null
	_visible_threats = 0
	if body == null or not is_instance_valid(body) or config == null:
		_was_visible = false
		return
	var best: AnimalBody = null
	var best_distance := INF
	for n in _threat_candidates():
		var other := n as AnimalBody
		if other == null or other == body:
			continue
		if not _can_see_body(other):
			continue
		_visible_threats += 1
		var d := horizontal_distance(body.global_position, other.global_position)
		if d < best_distance:
			best_distance = d
			best = other
	if best == null:
		_was_visible = false
		return
	if not _was_visible:
		# 只在"从看不见到看见"的跳变时计数（连续可见不会每帧 +1）
		_sight_count += 1
	_was_visible = true
	_visible = true
	_threat = best
	_threat_position = best.global_position
	_last_seen_position = best.global_position
	_last_seen_time = world_time
	_has_seen = true


## 潜在威胁：`animal_bodies` 组里**物种不同且存活**的身体（D2，不写物种名判断）
func _threat_candidates() -> Array[Node]:
	var out: Array[Node] = []
	if get_tree() == null:
		return out
	var mine := species_id()
	for n in get_tree().get_nodes_in_group(GROUP_ANIMAL_BODIES):
		var other := n as AnimalBody
		if other == null or other == body or other.species_config == null:
			continue
		if StringName(other.species_config.species_id) == mine:
			continue
		if _is_dead(other):
			continue
		out.append(other)
	return out


func _is_dead(other: AnimalBody) -> bool:
	if other.survival == null:
		return false
	return other.survival.state.health <= 0.0


func species_id() -> StringName:
	if body != null and is_instance_valid(body) and body.species_config != null:
		return StringName(body.species_config.species_id)
	return &""


func _can_see_body(other: AnimalBody) -> bool:
	return can_see_point(other.global_position, other.eye_position())


# ---------------------------------------------------------------------------
# 视觉：距离 × 草丛系数 → 视野角 → 遮挡（D3）
# ---------------------------------------------------------------------------

## 能不能看见某个**点**（对"身体"调用时射线打到目标的眼高）。
##
## 判定顺序（D3）：① 水平距离 ≤ `vision_range × 草丛系数`（近距豁免时系数按 1.0）
## → ② 水平视野角 ≤ `vision_half_angle_deg`（**始终检查**）→ ③ `world_static` 射线无阻挡（近距豁免时跳过）。
func can_see_point(point: Vector3, target_eye: Vector3 = Vector3(NAN, NAN, NAN)) -> bool:
	if body == null or not is_instance_valid(body) or config == null:
		return false
	var eye := body.eye_position()
	var to_point := point if is_nan(target_eye.x) else target_eye
	var flat := Vector3(to_point.x - eye.x, 0.0, to_point.z - eye.z)
	var distance := flat.length()
	if distance <= 0.001:
		return true
	var near := distance <= near_detect_range
	var factor := 1.0 if near else cover_factor_at(point)
	if distance > config.vision_range * factor:
		return false
	# 视野角：用身体的**前向**（Godot 前向 = −Z），只看水平角
	if not _inside_fov(flat):
		return false
	if near:
		return true
	return not _occluded(eye, to_point)


func _inside_fov(flat_from_eye: Vector3) -> bool:
	if config == null:
		return false
	var fwd := -body.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return true
	var dir := flat_from_eye.normalized()
	var cos_angle := clampf(fwd.normalized().dot(dir), -1.0, 1.0)
	return rad_to_deg(acos(cos_angle)) <= config.vision_half_angle_deg


## 实体墙挡视线吗（只认 `world_static`；草丛**不**走射线，见 `cover_factor_at()`）
func _occluded(from: Vector3, to: Vector3) -> bool:
	if get_tree() == null:
		return false
	var space := body.get_world_3d().direct_space_state
	if space == null:
		return false
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = world_static_layer
	params.collide_with_areas = false
	params.exclude = [body.get_rid()]
	return not space.intersect_ray(params).is_empty()


## 点位置在**草丛**里的系数：取所有覆盖该点的草丛体量的最小值；不在草丛 = 1.0。
##
## 为什么用几何判定：T011 的 `cover_volumes` 是 **`layer=0` 的纯数据 Area3D**（不参与物理查询），
## 物理 `intersect_point` 打不到它（见 `Docs/Evidence/T011.md`）。支持 Box / Sphere；
## 其它形状计数到 `unsupported_shape_count`，**不静默当成"没有遮挡"**（T020 §8）。
func cover_factor_at(point: Vector3) -> float:
	var factor := 1.0
	if get_tree() == null:
		return factor
	for n in get_tree().get_nodes_in_group(GROUP_COVER):
		var area := n as Node3D
		if area == null:
			continue
		if not _area_contains(area, point):
			continue
		var f := float(area.get_meta("visibility_factor", 1.0))
		if f < factor:
			factor = f
	return factor


func _area_contains(area: Node3D, point: Vector3) -> bool:
	var local := area.global_transform.affine_inverse() * point
	for c in area.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var offset: Vector3 = cs.position
		var d := local - offset
		var s := cs.shape
		if s is BoxShape3D:
			var half := (s as BoxShape3D).size * 0.5
			if absf(d.x) <= half.x and absf(d.y) <= half.y and absf(d.z) <= half.z:
				return true
		elif s is SphereShape3D:
			if d.length() <= (s as SphereShape3D).radius:
				return true
		else:
			_unsupported_shape_count += 1
	return false


## 水平距离（米）：视觉范围与听觉范围都用水平口径（竖直差忽略，见 `Docs/Tasks/T020.md` §4 D3）
func horizontal_distance(a: Vector3, b: Vector3) -> float:
	var d := Vector3(a.x - b.x, 0.0, a.z - b.z)
	return d.length()


# ---------------------------------------------------------------------------
# 听觉：噪声事件 → **只有发生位置 + 时间**（D4/D5）
# ---------------------------------------------------------------------------

## 收到一次噪声。可闻条件 = `距离 ≤ hearing_range × loudness`（`Parameters.md` 第 73 行）。
##
## 返回是否听见。**自己的噪声不触发自己**（按 `source_id` 过滤，脚步事件里带发送者的 `source_id()`）；
## 墙**不挡**听觉，也不乘草丛系数（声音绕过实体）；听见后**只记录发生位置与时间**，不建立跟踪。
func receive_noise(source_id: String, position: Vector3, loudness: float, world_time: float = NAN) -> bool:
	if body == null or not is_instance_valid(body) or config == null:
		return false
	if loudness <= 0.0 or not is_finite(loudness):
		return false
	if not source_id.is_empty() and source_id == body.source_id():
		return false
	var distance := horizontal_distance(body.global_position, position)
	if distance > config.hearing_range * loudness:
		return false
	var now := world_time if not is_nan(world_time) else _now
	_last_noise_position = position
	_last_noise_time = now
	_last_noise_loudness = loudness
	_last_noise_source = source_id
	_has_noise = true
	_heard_count += 1
	if now > _now:
		_now = now
	noise_heard.emit(position, loudness)
	return true


# ---------------------------------------------------------------------------
# 知识查询（"状态和原因可查看"）
# ---------------------------------------------------------------------------

func is_threat_visible() -> bool:
	return _visible


func threat_position() -> Vector3:
	return _threat_position if _visible else Vector3.ZERO


func threat_id() -> String:
	if _threat == null or not is_instance_valid(_threat):
		return ""
	return _threat.source_id()


func visible_threat_count() -> int:
	return _visible_threats


## 视觉知识：最后一次**看见**威胁的位置（**不包含**噪声位置）
func last_seen_position() -> Vector3:
	return _last_seen_position


func last_seen_time() -> float:
	return _last_seen_time


func has_seen() -> bool:
	return _has_seen


func sight_count() -> int:
	return _sight_count


## 噪声快照：声音**发生**位置（不是声源当前位置）
func last_noise_position() -> Vector3:
	return _last_noise_position


func last_noise_time() -> float:
	return _last_noise_time


func last_noise_loudness() -> float:
	return _last_noise_loudness


func last_noise_source() -> String:
	return _last_noise_source


func has_heard() -> bool:
	return _has_noise


func heard_count() -> int:
	return _heard_count


func noise_age(world_time: float = NAN) -> float:
	if not _has_noise:
		return INF
	var now := world_time if not is_nan(world_time) else _now
	return maxf(0.0, now - _last_noise_time)


## "危险"时间戳 = max(最后看见, 最后听见)。躲藏外出计时（`Parameters.md` 第 71 行「无危险持续 4 s」）用它。
func danger_time() -> float:
	if not _has_seen:
		return _last_noise_time if _has_noise else 0.0
	if not _has_noise:
		return _last_seen_time
	return maxf(_last_seen_time, _last_noise_time)


func danger_age(world_time: float = NAN) -> float:
	var now := world_time if not is_nan(world_time) else _now
	return maxf(0.0, now - danger_time())


func world_time_now() -> float:
	if body != null and is_instance_valid(body):
		return body.world_time_now()
	return _now


## 感知状态快照（HUD / `MOV|` / 断言）
func report() -> Dictionary:
	var now := world_time_now()
	var point := body.global_position if body != null and is_instance_valid(body) else Vector3.ZERO
	var factor := cover_factor_at(point)
	return {
		"seen": _visible,
		"threat_id": threat_id(),
		"threat_position": _threat_position,
		"threats": _visible_threats,
		"sight_count": _sight_count,
		"heard_count": _heard_count,
		"has_seen": _has_seen,
		"has_heard": _has_noise,
		"last_seen_position": _last_seen_position,
		"last_seen_age": (maxf(0.0, now - _last_seen_time) if _has_seen else -1.0),
		"last_noise_position": _last_noise_position,
		"last_noise_age": (maxf(0.0, now - _last_noise_time) if _has_noise else -1.0),
		"last_noise_loudness": _last_noise_loudness,
		"last_noise_source": _last_noise_source,
		"danger_age": danger_age(now),
		"cover_factor_here": factor,
		"in_cover": factor < 1.0,
		"near_detect_range": near_detect_range,
		"vision_range": config.vision_range if config != null else 0.0,
		"hearing_range": config.hearing_range if config != null else 0.0,
		"unsupported_shape_count": _unsupported_shape_count,
	}
