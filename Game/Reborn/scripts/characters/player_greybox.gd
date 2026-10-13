extends CharacterBody3D
## 临时灰盒玩家控制器（T002）
##
## 目的：仅用于验证"出生点有效、地面碰撞生效、能移动、能停止"。
## T009 会用正式猫的移动控制替换本脚本，届时本文件应删除或改名。
##
## 单位：米。Parameters.md 中 Cat 起测值（厘米 → 米）：
##   半径 16 / 半高 24 cm → 0.16 / 0.24
##   Walk 180 cm/s → 1.80 m/s ；Sprint 450 → 4.50 ；Crouch 90 → 0.90
##   JumpZVelocity 320 cm/s → 3.20 m/s ；MaxAcceleration 1000 cm/s² → 10.0 m/s²
##
## 注意：CapsuleShape3D.height 是含两端半球的总高 = 2 × 半高。

@export var walk_speed: float = 1.80
@export var sprint_speed: float = 4.50
@export var crouch_speed: float = 0.90
@export var jump_velocity: float = 3.20
@export var acceleration: float = 10.0
@export var friction: float = 12.0
@export var mouse_sensitivity: float = 0.0025

@onready var _camera: Camera3D = $Camera3D
@onready var _shape: CollisionShape3D = $CollisionShape3D

var _pitch: float = 0.0
var _was_on_floor: bool = false
## 供测试读取：本次运行中是否曾经落地。避免测试只能靠采样时机碰运气。
var has_touched_floor: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.4, 1.4)
		_camera.rotation.x = _pitch
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _physics_process(delta: float) -> void:
	# 重力
	if not is_on_floor():
		velocity += get_gravity() * delta

	if is_on_floor():
		has_touched_floor = true
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity

	# 水平输入（相对朝向）
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := walk_speed
	if Input.is_action_pressed("pause"):
		speed = crouch_speed
	elif Input.is_action_pressed("jump"):
		speed = sprint_speed

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if direction:
		horizontal = horizontal.move_toward(direction * speed, acceleration * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()


## 供测试与调试读取的只读信息。
func debug_state() -> Dictionary:
	return {
		"on_floor": is_on_floor(),
		"has_touched_floor": has_touched_floor,
		"position": global_position,
		"velocity": velocity,
	}
