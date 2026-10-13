extends SceneTree
## T007 输入链路验证（可在打包产物内运行）
##
## 验证范围 —— 说清楚边界：
##   覆盖：InputMap 动作 → 玩家控制器 → **实际位移**。这是可自动判定的部分。
##   不覆盖：操作系统键盘 → 引擎 这一段。那需要真实按键注入，而"盲发按键"
##          可能打进用户当前焦点窗口，风险不可接受，因此不做。
##          所以 T007 的"真实按键输入"仍记 awaiting-review，本测试提供的是
##          **合成输入**证据。
##
## 本测试的存在理由（真实 bug）：
##   玩家控制器曾经把 crouch 写成 pause、sprint 写成 jump，后果是蹲下键无效、
##   按跳跃键同时触发跳跃与冲刺。这个测试覆盖此类"动作名写错"的问题。
##
## 运行（项目内）：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t007_input.gd' --quit-after 20000
## 运行（打包产物内）：
##   & '<godot_console.exe>' --headless --main-pack 'Builds\...\RebornSelfTest.pck' \
##       --script 'res://tests/run_t007_input.gd' --quit-after 20000

const LAB := "res://scenes/maps/l_movement_lab.tscn"
const WALK := 1.80        # Parameters.md: Cat Walk 180 cm/s -> 1.80 m/s
const SPRINT := 4.50      # 450 cm/s -> 4.50 m/s
const CROUCH := 0.90      # 90 cm/s -> 0.90 m/s
const SAMPLE_FRAMES := 60 # 1.0 s @ 60 Hz

var _checks := 0
var _fails := 0
var _lab: Node
var _player: CharacterBody3D


func _initialize() -> void:
	print("TEST|run_t007_input|engine=%s" % Engine.get_version_info().string)

	var packed: PackedScene = load(LAB)
	if packed == null:
		_assert("lab_loads", "PackedScene", "null", false)
		_finish()
		return
	_lab = packed.instantiate()
	root.add_child(_lab)
	await process_frame
	await process_frame

	_player = _lab.get_node_or_null("Player") as CharacterBody3D
	if _player == null:
		_assert("player_found", "CharacterBody3D", "null", false)
		_finish()
		return
	_assert("player_found", "CharacterBody3D", "CharacterBody3D", true)

	# 确认所有动作都已在 InputMap 中定义（防止动作名拼错）
	for a in ["move_forward", "move_back", "move_left", "move_right",
			"jump", "sprint", "crouch", "interact", "pounce", "pause"]:
		_assert("inputmap_has_%s" % a, "true", str(InputMap.has_action(a)), InputMap.has_action(a))

	# --- 方向测试 ---
	var fwd := await _measure("move_forward")
	_assert("forward_dz_negative", "< 0", "%.3f" % fwd.z, fwd.z < -0.5)
	_assert("forward_dx_small", "|dx| < 0.1", "%.3f" % fwd.x, absf(fwd.x) < 0.1)
	_assert_range("forward_distance_m", 1.2, 1.9, fwd.length())

	var back := await _measure("move_back")
	_assert("back_dz_positive", "> 0", "%.3f" % back.z, back.z > 0.5)

	var right := await _measure("move_right")
	_assert("right_dx_positive", "> 0", "%.3f" % right.x, right.x > 0.5)

	var left := await _measure("move_left")
	_assert("left_dx_negative", "< 0", "%.3f" % left.x, left.x < -0.5)

	# --- 速度档位测试（这是发现动作名写错的关键用例）---
	var walk_d := fwd.length()
	var sprint_d := (await _measure("move_forward", ["sprint"])).length()
	var crouch_d := (await _measure("move_forward", ["crouch"])).length()

	print("SPEED|walk=%.3f m/s 实测位移=%.3f m" % [WALK, walk_d])
	print("SPEED|sprint=%.3f m/s 实测位移=%.3f m" % [SPRINT, sprint_d])
	print("SPEED|crouch=%.3f m/s 实测位移=%.3f m" % [CROUCH, crouch_d])

	_assert("sprint_faster_than_walk", "sprint_d > walk_d * 1.5",
		"%.3f vs %.3f" % [sprint_d, walk_d * 1.5], sprint_d > walk_d * 1.5)
	_assert("crouch_slower_than_walk", "crouch_d < walk_d * 0.7",
		"%.3f vs %.3f" % [crouch_d, walk_d * 0.7], crouch_d < walk_d * 0.7)

	# 冲刺位移应接近理论值（4.50 m/s 跑 1s，扣除加速段）
	_assert_range("sprint_distance_m", 3.0, 4.6, sprint_d)
	_assert_range("crouch_distance_m", 0.5, 1.0, crouch_d)

	# --- 跳跃 ---
	await _reset_player()
	var y_before := _player.global_position.y
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	var peak := y_before
	for i in 40:
		await physics_frame
		peak = maxf(peak, _player.global_position.y)
	_assert("jump_leaves_ground", "peak > y_before + 0.15",
		"%.3f -> %.3f" % [y_before, peak], peak > y_before + 0.15)

	# --- 小鼠不应能跳（Parameters.md: Mouse JumpZVelocity = 0）---
	# 这里只验证猫能跳；鼠的"禁止跳跃"属 T010，需要鼠的控制器，当前尚未实现。

	_finish()


## 重置玩家到出生点并站稳，返回时保证在地面上、速度接近 0。
func _reset_player() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right",
			"jump", "sprint", "crouch"]:
		Input.action_release(a)
	_player.global_position = Vector3(0, 0.5, 0)
	_player.velocity = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	for i in 120:
		await physics_frame
		if _player.is_on_floor():
			break
	for i in 20:
		await physics_frame


## 按住 action（+额外动作）SAMPLE_FRAMES 帧，返回位移向量。
func _measure(action: String, extra: Array = []) -> Vector3:
	await _reset_player()
	var start: Vector3 = _player.global_position
	Input.action_press(action)
	for e in extra:
		Input.action_press(e)
	for i in SAMPLE_FRAMES:
		await physics_frame
	Input.action_release(action)
	for e in extra:
		Input.action_release(e)
	return _player.global_position - start


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_range(id: String, lo: float, hi: float, actual: float) -> void:
	var ok: bool = actual >= lo and actual <= hi
	_assert(id, "[%.2f, %.2f]" % [lo, hi], "%.3f" % actual, ok)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
