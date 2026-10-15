class_name AnimalBody
extends CharacterBody3D
## 由 `SpeciesConfig` 驱动的动物身体（T008 成型 + T009 移动）
##
## 本文件**不出现物种名判断**：所有差异（尺寸、速度、跳跃、台阶、蹲姿、相机）都从配置读。
##
## 职责：
##   1) 成型：胶囊尺寸、相机偏移/FOV、碰撞层
##   2) 台阶：`StepClimb.new(self, config.max_step_height)`，移动时用 `step_or_slide()`
##   3) 移动（T009）：行走/奔跑/潜伏三档水平速度 + 跳跃，全部来自 `max_acceleration` / `jump_velocity`
##   4) 潜伏（T009）：蹲姿把胶囊变矮、视线降低；**只在头顶空间允许时**才恢复站姿
##      （`Docs/TechnicalDesign.md` 的硬要求：不能靠改 `scale` 蒙过去，要真的查空间）
##   5) 第一人称相机：眼高 = 配置的竖直偏移，鼠标查表 → `apply_look()`（测试可直接调它）
##
## 相机偏移的轴向（T009 决策 D1）：`camera_offset_z` 按 **本地 +Y（竖直）** 实现。
## 依据：`Docs/Parameters.md` 的表源自 UE 版（`CameraZ`/`JumpZVelocity`），UE 里 Z 是上方向；
## 第一人称的"眼高"必须是竖直偏移。字段名沿用契约，见 `Docs/Tasks/T009.md` §4.1。
##
## 碰撞层固定用 `project.godot` 已定义的层（不新增未验证层）：
##   layer 1 = world_static，layer 2 = animal，layer 3 = interactable，layer 4 = safe_spot
##
## 输入：默认读 `Input`（玩家）。`player_controlled = false` 时不读输入，改由外部每帧写
## `move_intent` / `want_sprint` / `want_crouch` / `want_jump`（为测试与将来的 NPC 留口）。

signal configured(species_id: StringName)
## 蹲/站状态真的改变时发出（被头顶挡住时不发）
signal stance_changed(crouching: bool)

const LAYER_WORLD_STATIC := 1
const LAYER_ANIMAL := 2

## 头顶空间探测：形状收窄量（米）。避免"贴着墙/地面"被当成头顶受阻。
## 依据：探测胶囊与墙相切、与地面相切都会产生接触；收窄 5 mm 后：
##   站姿半径 0.160 → 探测 0.155；探测底面比站立底面高 1 cm。见 `Docs/Tasks/T009.md` §8。
const HEADROOM_SHRINK := 0.005
## 头顶空间探测：整体上移量（米）。宁可**保守**（挡住）也不要"站起来卡进天花板"。
## 结果：探测顶面 = 站立顶面 + 5 mm，探测底面 = 站立底面 + 1 cm。
const HEADROOM_MARGIN := 0.005
## 俯仰上限（弧度）
const MAX_PITCH := 1.4

## 物种配置（由生成者赋值；T009/T010 用它区分两种玩家）
@export var species_config: SpeciesConfig:
	set(value):
		species_config = value
		if is_node_ready():
			apply_config()

## 是否读 `Input`（玩家为 true；测试/将来 NPC 设 false 后直接写意图）
@export var player_controlled: bool = true
## 入树时是否把相机的 `current` 置为 true。
## 为什么要有这个开关：`animal_body.tscn` 里的相机刻意不设 current（谁生成谁决定）；
## 但场景**实例**的子节点属性覆盖不会被 `PackedScene.pack()` 序列化（实测：改子节点 current 后
## 存盘文件里没有这行，重载回来相机不是 current → 视觉捕获采到黑屏）。所以走"节点自己的导出属性"。
@export var make_camera_current: bool = false
@export var mouse_sensitivity: float = 0.0025

# --- 运动意图（每物理帧由 Input 或外部写入）---
## x = 右(+1)/左(-1)，y = 后(+1)/前(-1)（与 `Input.get_vector` 一致）
var move_intent: Vector2 = Vector2.ZERO
var want_sprint: bool = false
var want_crouch: bool = false
var want_jump: bool = false

## 是否处于蹲姿
var is_crouching: bool = false
## 本次运行中是否曾经落地（测试用，避免只能靠采样时机碰运气）
var has_touched_floor: bool = false
## 上一次"想站起来但头顶不够"（诊断用）
var stance_blocked_by_headroom: bool = false
## 台阶抬升组件（上限来自配置）
var climb: StepClimb = null

@onready var shape_node: CollisionShape3D = $CollisionShape3D
## 灰盒占位网格：与碰撞胶囊同尺寸（正式模型属 P6 资产任务）
@onready var body_mesh: MeshInstance3D = get_node_or_null("BodyMesh") as MeshInstance3D
@onready var camera: Camera3D = $Camera3D

var _pitch: float = 0.0
## 生存状态推进器（T014）。由 `apply_config()` 建立
var survival: SurvivalController = null
## 冲刺档实际是否生效（受"开始/继续"双门控；T015）
var _sprint_active := false
## 最近一次落地前的**最大下落速度**（米/秒，正数）。落地后保留，供诊断与断言（T015）
var last_fall_speed := 0.0
var _fall_speed := 0.0
var _was_on_floor := true
## 无 Autoload 环境下的兜底时钟（**有 `WorldDirector` 时完全不用它**，两套时间源不会混用）
var _fallback_world_time := 0.0
var _world_director: Node = null
var _world_director_checked := false


func _ready() -> void:
	if player_controlled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if species_config != null:
		apply_config()
	else:
		push_warning("AnimalBody 未赋 species_config：身体保持场景默认值")
	if make_camera_current and camera != null:
		camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		apply_look(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


## 偏航/俯仰（弧度）。鼠标事件经 `_unhandled_input` 调它；测试可直接调它，走同一段代码。
func apply_look(yaw_delta: float, pitch_delta: float) -> void:
	rotate_y(yaw_delta)
	_pitch = clampf(_pitch + pitch_delta, -MAX_PITCH, MAX_PITCH)
	if camera != null:
		camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if species_config == null:
		return
	_read_input()
	_apply_stance()

	var direction := Vector3.ZERO
	if move_intent != Vector2.ZERO:
		direction = (transform.basis * Vector3(move_intent.x, 0.0, move_intent.y)).normalized()

	# 重力与跳跃：`is_on_floor()` 由上一次 `move_and_slide()` 决定（与 T002 灰盒一致）
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		has_touched_floor = true
		if want_jump and can_jump():
			velocity.y = species_config.jump_velocity
			want_jump = false

	# 水平速度：三档速度来自配置，加减速用 max_acceleration
	var target := direction * current_speed()
	var accel: float = species_config.max_acceleration
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# 生存状态按**世界时间**推进（统一时间入口；见 scripts/systems/survival_controller.gd 头注）
	if survival != null:
		var dt_sim: float = survival.tick_to(world_time_now())
		# 冲刺代价（T015）：用**世界时间差**扣（`Parameters.md`「运动消耗使用实际经过时间」）
		if dt_sim > 0.0 and is_sprinting():
			survival.spend_stamina(species_config.sprint_stamina_per_sec * dt_sim)
		# 跌落结算（T015）：每物理帧跟踪腾空速度，落地那帧扣血
		_track_fall()

	# 位移交给台阶组件（能上台阶就抬上去，否则普通 move_and_slide）
	var motion := Vector3(velocity.x * delta, 0.0, velocity.z * delta)
	if climb != null:
		climb.update_base_y()
		climb.step_or_slide(motion, delta)
	else:
		move_and_slide()


## 当前档位速度（米/秒）。蹲姿优先于奔跑（与 T002 灰盒的选择顺序一致）
func current_speed() -> float:
	if species_config == null:
		return 0.0
	if is_crouching:
		return species_config.crouch_speed
	# 冲刺档要过**双门控**（T015）：这里顺手刷新一次，保证"直接读档位"（HUD/测试）也拿到正确结果
	_update_sprint_latch()
	if _sprint_active:
		return species_config.sprint_speed
	return species_config.walk_speed


func _read_input() -> void:
	if not player_controlled:
		return
	move_intent = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	want_sprint = Input.is_action_pressed("sprint")
	want_crouch = Input.is_action_pressed("crouch")
	# 与灰盒一致：不做跳跃缓冲（空中按键落地不自动跳）
	want_jump = Input.is_action_just_pressed("jump")


## 蹲/站切换：只有"想蹲"或"想站且头顶够"才真的切换
func _apply_stance() -> void:
	if want_crouch == is_crouching:
		if not want_crouch:
			stance_blocked_by_headroom = false
		return
	if want_crouch:
		_set_stance(true)
		return
	if has_headroom():
		_set_stance(false)
	else:
		stance_blocked_by_headroom = true


## 真正改变姿态：胶囊尺寸 + 视线高度 + 脚底高度一起改，保证胶囊底**始终贴在同一地面**
func _set_stance(crouching: bool) -> void:
	var drop: float = species_config.crouch_drop()
	is_crouching = crouching
	# 脚底不动：蹲下时身体下沉 drop，站起时上升 drop（只在贴地时做，避免空中传送）
	if is_on_floor():
		global_position.y += -drop if crouching else drop
	_rebuild_capsule()
	_update_camera()
	if climb != null:
		climb.reset_base()
	stance_blocked_by_headroom = false
	stance_changed.emit(is_crouching)


func _rebuild_capsule() -> void:
	if shape_node == null:
		return
	var cap := CapsuleShape3D.new()
	cap.radius = species_config.capsule_radius
	cap.height = species_config.crouch_height() if is_crouching else species_config.capsule_height()
	shape_node.shape = cap
	shape_node.position = Vector3.ZERO
	_sync_body_mesh(cap)


## 让灰盒网格与碰撞胶囊**同尺寸**（蹲下时一起变矮）。
## 不变量由 `tests/run_t009_cat_movement.gd` 断言：视觉与碰撞不允许各走一套数。
func _sync_body_mesh(cap: CapsuleShape3D) -> void:
	if body_mesh == null:
		return
	var mesh := body_mesh.mesh as CapsuleMesh
	if mesh == null or not mesh.resource_local_to_scene:
		# 每只身体各自一份网格资源，避免共享 sub_resource 被互相改尺寸
		mesh = CapsuleMesh.new()
		mesh.resource_local_to_scene = true
		body_mesh.mesh = mesh
	mesh.radius = cap.radius
	mesh.height = cap.height
	body_mesh.position = Vector3.ZERO


## 相机：竖直偏移 = 配置值；蹲下时按 crouch_drop() 降低视线（视线跟着身体变低）
func _update_camera() -> void:
	if camera == null:
		return
	var drop: float = species_config.crouch_drop() if is_crouching else 0.0
	camera.position = Vector3(0.0, species_config.camera_offset_z - drop, 0.0)
	camera.fov = species_config.fov


## 头顶是否有站起来的空间（真实物理查询，不是改 scale）。
## 探测体积 = 站姿胶囊（收窄 5 mm、上移 5 mm）放在"站起来之后身体中心会在的位置"。
func has_headroom() -> bool:
	if species_config == null or not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var probe := CapsuleShape3D.new()
	probe.radius = maxf(0.001, species_config.capsule_radius - HEADROOM_SHRINK)
	probe.height = maxf(0.002, species_config.capsule_height() - HEADROOM_SHRINK * 2.0)

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = Transform3D(
		Basis(),
		global_position + Vector3.UP * (species_config.crouch_drop() + HEADROOM_MARGIN),
	)
	params.collision_mask = LAYER_WORLD_STATIC
	params.collide_with_bodies = true
	params.exclude = [get_rid()]
	return space.intersect_shape(params, 1).is_empty()


## 按配置成型。重复调用安全（可热改配置，便于调试与测试）。
func apply_config() -> void:
	if species_config == null:
		push_warning("apply_config 调用时 species_config 仍是 null")
		return
	if not is_node_ready():
		push_warning("apply_config 需在入树后调用（@onready 节点尚未就绪）")
		return

	is_crouching = false
	_rebuild_capsule()
	_update_camera()

	collision_layer = LAYER_ANIMAL
	collision_mask = LAYER_WORLD_STATIC

	climb = StepClimb.new(self, species_config.max_step_height)
	configured.emit(species_config.species_id)
	# 生存推进器（T014）。重复调用 `apply_config()` 时**保留当前数值**（热改配置不清血）；
	# 时间一律来自 `WorldDirector` 的世界时间，本文件不累加 delta
	survival = SurvivalController.new(
		species_config, survival.state if survival != null else null
	)


## 能力查询：全部读配置，调用方不需要知道是哪个物种
func can_jump() -> bool:
	return species_config != null and species_config.can_jump


func can_pounce() -> bool:
	return species_config != null and species_config.can_pounce


func can_use_mouse_tunnel() -> bool:
	return species_config != null and species_config.can_use_mouse_tunnel


## 当前灰盒网格（与碰撞胶囊同尺寸），没有则 null
func _capsule_mesh() -> CapsuleMesh:
	if body_mesh == null:
		return null
	return body_mesh.mesh as CapsuleMesh


## 供测试/调试读取的只读状态快照
func debug_state() -> Dictionary:
	var shape := shape_node.shape as CapsuleShape3D if shape_node != null else null
	return {
		"species_id": species_config.species_id if species_config != null else &"<none>",
		"capsule_radius": shape.radius if shape != null else -1.0,
		"capsule_height": shape.height if shape != null else -1.0,
		"mesh_radius": (body_mesh.mesh as CapsuleMesh).radius if _capsule_mesh() != null else -1.0,
		"mesh_height": (body_mesh.mesh as CapsuleMesh).height if _capsule_mesh() != null else -1.0,
		"camera_offset_z": camera.position.y if camera != null else 0.0,
		"camera_offset_axis": "y",
		"camera_local_position": camera.position if camera != null else Vector3.ZERO,
		"fov": camera.fov if camera != null else 0.0,
		"collision_layer": collision_layer,
		"collision_mask": collision_mask,
		"max_step_height": climb.max_step_height if climb != null else -1.0,
		"is_crouching": is_crouching,
		"headroom_free": has_headroom(),
		"stance_blocked_by_headroom": stance_blocked_by_headroom,
		"on_floor": is_on_floor(),
		"has_touched_floor": has_touched_floor,
		"position": global_position,
		"velocity": velocity,
		"wish_speed": current_speed(),
		"survival": survival.state.to_dictionary() if survival != null else {},
		"health": survival.state.health if survival != null else -1.0,
		"hunger": survival.state.hunger if survival != null else -1.0,
		"thirst": survival.state.thirst if survival != null else -1.0,
		"stamina": survival.state.stamina if survival != null else -1.0,
		"sprinting": _sprint_active,
		"last_fall_speed": last_fall_speed,
		"low_hunger": survival.is_low_hunger() if survival != null else false,
		"low_thirst": survival.is_low_thirst() if survival != null else false,
		"starving": survival.is_starving() if survival != null else false,
		"dehydrated": survival.is_dehydrated() if survival != null else false,
		"player_controlled": player_controlled,
	}


## 当前世界时间（秒）——**统一时间入口**。
##
## 正常运行时取 Autoload `WorldDirector` 的世界时间；只有在没有该单例的环境里
## （例如某些裸 `SceneTree` 测试）才退回"本节点按物理帧累计"的兜底时钟。
## **两套时间源不会同时使用**：只要能拿到单例就只用单例。
func world_time_now() -> float:
	if not _world_director_checked:
		_world_director = get_node_or_null("/root/WorldDirector")
		_world_director_checked = true
	if _world_director != null and is_instance_valid(_world_director):
		return float(_world_director.get("world_time"))
	_fallback_world_time += 1.0 / float(Engine.physics_ticks_per_second)
	return _fallback_world_time


## 生存状态的一份**独立副本**（HUD/存档/断言用；改副本不影响身体）
func survival_snapshot() -> SurvivalState:
	if survival == null:
		return SurvivalState.new()
	return survival.state.duplicate_state()


# ---------------------------------------------------------------------------
# 消耗与伤害（T015）
# ---------------------------------------------------------------------------

## 冲刺档是否**真的**生效（双门控，`Docs/Parameters.md` 第 65 行）：
##   * 开始：`Stamina ≥ SpeciesConfig.sprint_min_stamina`（5）
##   * 继续：`Stamina > 0` —— 耗尽后**自动转行走**，不会停下、不会掉出移动能力
func is_sprinting() -> bool:
	_update_sprint_latch()
	return _sprint_active


func _update_sprint_latch() -> void:
	if not want_sprint or is_crouching or survival == null or species_config == null:
		_sprint_active = false
		return
	if _sprint_active:
		_sprint_active = survival.has_any_stamina()
	else:
		_sprint_active = survival.has_min_stamina()


## 跌落结算（T015）：腾空期间记录**最大下落速度**，落地那一帧结算一次。
## 判据只看**垂直速度**（`Parameters.md`「落地前垂直速度绝对值」），水平速度不参与。
func _track_fall() -> void:
	var on_floor_now := is_on_floor()
	if not on_floor_now:
		_fall_speed = maxf(_fall_speed, absf(velocity.y))
	elif not _was_on_floor:
		_apply_fall_damage()
	_was_on_floor = on_floor_now


func _apply_fall_damage() -> void:
	last_fall_speed = _fall_speed
	_fall_speed = 0.0
	if survival == null or species_config == null:
		return
	var safe: float = species_config.fall_safe_vertical_speed
	if last_fall_speed <= safe:
		return
	var damage: float = minf(
		species_config.max_health,
		(last_fall_speed - safe) * species_config.fall_damage_scale
	)
	if damage > 0.0:
		survival.apply_damage(damage, &"fall")
