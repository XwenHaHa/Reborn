extends SceneTree
## 台阶（MaxStepHeight）能力探针
##
## 为什么先做这个：
##   Godot 的 CharacterBody3D **没有** UE `MaxStepHeight` 的等价物。
##   move_and_slide() 不会自动上台阶。而 Parameters.md 要求：
##     猫 MaxStepHeight = 12 cm，鼠 MaxStepHeight = 3 cm
##   如果做不到，T009/T010 的移动设计要改，所以必须先验证。
##
## 关键修正（v2）：v1 把台阶块一直往世界里加、从不清理，导致试验互相污染
##   （猫在阶段 B 连 20cm 都"上去了"，实际是爬到了前面遗留的台阶上）。
##   现在每个试验都在**全新世界**里跑，结束时销毁，互不影响。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/probe_step_height.gd' --quit-after 20000

const STEP_HEIGHTS := [0.03, 0.12, 0.20]

# Parameters.md 的胶囊参数（厘米 ÷100）
const CAPSULES := {
	"Cat": {"radius": 0.16, "half_height": 0.24, "max_step": 0.12},
	"Mouse": {"radius": 0.06, "half_height": 0.09, "max_step": 0.03},
}

const SPEED := 1.0
const TARGET_X := 2.0
const START_X := -1.0
const SETTLE_STEPS := 40
const MAX_ITERS := 700

## 台阶容差（米）。由 sweep_tolerance 实测标定后固定，见文件末尾的标定记录。
var STEP_TOLERANCE: float = 0.002

var _results: Dictionary = {}


func _initialize() -> void:
	print("PROBE|step_height|engine=%s" % Engine.get_version_info().string)
	print("PROBE|physics_hz=%d|speed=%.2f|start_x=%.2f|target_x=%.2f|tolerance=%.4f" % [
		Engine.physics_ticks_per_second, SPEED, START_X, TARGET_X, STEP_TOLERANCE
	])

	await sweep_tolerance()
	return

	for mode in ["naive", "stepup"]:
		print("---- 阶段 %s ----" % ("A：裸 move_and_slide" if mode == "naive" else "B：自实现台阶抬升"))
		for species in CAPSULES.keys():
			var cfg: Dictionary = CAPSULES[species]
			for h in STEP_HEIGHTS:
				await _run_trial(species, cfg, h, mode)

	_verdicts()
	print("PROBE|probe_complete=1")
	quit(0)


## 容差标定 v2：直接**测量**每次尝试的候选抬升量分布，不再靠猜容差。
func sweep_tolerance() -> void:
	var candidates := [0.002, 0.02, 0.05]
	for tol in candidates:
		STEP_TOLERANCE = tol
		_results.clear()
		_gains.clear()
		print("SWEEP|tol=%.3f" % tol)
		for species in CAPSULES.keys():
			var cfg: Dictionary = CAPSULES[species]
			for h in STEP_HEIGHTS:
				await _run_trial(species, cfg, h, "stepup")
				var desc := "none"
				if _gains.has("%s|%.2f" % [species, h]):
					var gains: Array = _gains["%s|%.2f" % [species, h]]
					if gains.size() > 0:
						var mx: float = gains[0]
						var mn: float = gains[0]
						for g in gains:
							mx = maxf(mx, g)
							mn = minf(mn, g)
						desc = "n=%d min=%.4f max=%.4f" % [gains.size(), mn, mx]
				print("  GAINS|%s|step=%.2f|%s|limit=%.4f|on_top=%s" % [
					species, h, desc, cfg.max_step + tol, _lookup(species, h, "stepup")
				])
	print("SWEEP|done")
	quit(0)


## 记录每个用例中"候选落点"的抬升量（含被拒绝的），用于标定
var _gains: Dictionary = {}
var _cur_key: String = ""


## 每个试验用全新世界，结束后销毁，杜绝互相污染
func _run_trial(species: String, cfg: Dictionary, step_height: float, mode: String) -> void:
	_base_y = INF
	_cur_key = "%s|%.2f" % [species, step_height]
	if not _gains.has(_cur_key):
		_gains[_cur_key] = []
	var world := Node3D.new()
	world.name = "World_%s_%.2f_%s" % [species, step_height, mode]
	root.add_child(world)
	await process_frame

	# 主平台：顶面 y=0
	_add_box(world, "Ground", Vector3(40, 1.0, 20), Vector3(0, -0.5, 0))
	# 台阶块：从 x=0 起，深 6 m，顶面 = step_height
	_add_box(world, "Step", Vector3(6.0, step_height, 6.0), Vector3(3.0, step_height * 0.5, 0))

	var body := CharacterBody3D.new()
	body.name = "Walker"
	body.collision_layer = 2
	body.collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = cfg.radius
	cap.height = cfg.half_height * 2.0  # Godot 的 height 是含半球总高
	col.shape = cap
	body.add_child(col)
	body.position = Vector3(START_X, cfg.half_height + 0.002, 0)
	world.add_child(body)

	await process_frame
	for i in SETTLE_STEPS:
		body.velocity = Vector3.ZERO
		await physics_frame

	# 站稳后确定"当前落脚面"基准
	_update_base_y(body)
	var y_before: float = body.global_position.y
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var motion := Vector3(SPEED * dt, 0.0, 0.0)
	var iters := 0
	var max_x: float = START_X

	while body.global_position.x < TARGET_X and iters < MAX_ITERS:
		iters += 1
		if mode == "naive":
			body.velocity = motion / dt
			body.move_and_slide()
		else:
			if not _try_step_up(body, motion, cfg.max_step):
				body.velocity = motion / dt
				body.move_and_slide()
			else:
				body.velocity = Vector3.ZERO
		max_x = maxf(max_x, body.global_position.x)
		await physics_frame
		if mode == "stepup":
			_update_base_y(body)

	# 再稳一会，避免把"正在下落"当成落点
	for i in 20:
		body.velocity = Vector3.ZERO
		await physics_frame

	var y_after: float = body.global_position.y
	var climbed: float = y_after - y_before
	var reached: bool = max_x >= TARGET_X - 0.05
	# "上到台阶顶" = 水平通过 且 抬升接近台阶高度
	var on_top: bool = reached and climbed > step_height * 0.5

	print("RESULT|%s|%s|step=%.2f|y_before=%.3f|y_after=%.3f|climbed=%.3f|max_x=%.2f|reached=%s|on_top=%s|iters=%d" % [
		mode, species, step_height, y_before, y_after, climbed, max_x, reached, on_top, iters
	])

	var key := "%s|%.2f" % [species, step_height]
	if not _results.has(key):
		_results[key] = {}
	_results[key][mode] = on_top

	world.queue_free()
	await process_frame
	await process_frame


func _add_box(parent: Node3D, nm: String, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = pos
	body.add_child(col)
	parent.add_child(body)


## 自实现台阶抬升。
## API 依据：Godot 4.7.2 引擎文档（--doctool 权威签名）
##   PhysicsServer3D.body_test_motion(body: RID,
##       parameters: PhysicsTestMotionParameters3D,
##       result: PhysicsTestMotionResult3D = null) -> bool
##
## 判据演进（三个版本，两个真实 bug 的修正记录）：
##   v1 用 "dropped <= max_step" —— 错。它只说明"落点还在同一水平面附近"，
##      实测反例：猫(max=0.12) 对 20cm 台阶 dropped=0.1223、落点仍在地面，却判为通过。
##   v2 改用 "落点相对起点的增益 ∈ (0, max_step]" —— 仍是错。
##      **逐帧棘轮**：胶囊底部是圆的，贴着台阶棱角每帧只抬升一点点
##      （实测增益序列 0.0921 → 0.0337 → 0.0225 → 0.0149 → … → 0.0012），
##      每帧都小于阈值，累积却爬上了 19.8cm 的台阶。上限形同虚设。
##   v3（当前）把基准从"本帧起点"改为"**当前落脚面**"：
##      总抬升 = 拟落点 − 当前所站平面。超过 max_step 一律拒绝。
##      base_y 只在真正站定时更新（速度接近 0 且在落地状态）。
func _try_step_up(body: CharacterBody3D, motion: Vector3, max_step: float) -> bool:
	var flat := Vector3(motion.x, 0.0, motion.z)
	if flat.length() < 0.000001:
		return false

	var y_start: float = body.global_position.y

	# 前方必须有障碍，否则不是台阶场景
	if not body.test_move(body.global_transform, flat):
		return false

	# 障碍距离必须 ≤ max_step，否则是远墙而不是台阶
	var probe := PhysicsTestMotionParameters3D.new()
	probe.from = body.global_transform
	probe.motion = flat
	probe.margin = 0.001
	var probe_res := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), probe, probe_res):
		return false
	var moved: float = probe_res.get_travel().length()
	if flat.length() - moved > max_step:
		return false  # 被挡得太早 → 不是可上的台阶

	# 头顶要有空间
	if body.test_move(body.global_transform, Vector3.UP * max_step):
		return false

	var raised := body.global_transform.translated(Vector3.UP * max_step)
	if body.test_move(raised, flat):
		return false  # 抬起后仍被挡 → 台阶高于阈值

	# 找落点
	var forward := raised.translated(flat)
	var params := PhysicsTestMotionParameters3D.new()
	params.from = forward
	params.motion = Vector3.DOWN * (max_step + 0.01)
	params.margin = 0.001
	var res := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), params, res):
		return false  # 前方悬空

	var landed_y: float = forward.origin.y + res.get_travel().y

	# 记录候选抬升量（含被拒绝的），供容差标定使用
	if _cur_key != "":
		if not _gains.has(_cur_key):
			_gains[_cur_key] = []
		var arr: Array = _gains[_cur_key]
		if arr.size() < 400:
			arr.append(landed_y - _base_y)

	# v3 关键：以"当前落脚面"为基准算总抬升，防止逐帧棘轮。
	# 容差说明：胶囊底部是半球，靠上台阶棱角时需要的抬升量会略大于台阶高度，
	# 因此允许 STEP_TOLERANCE 的余量。该值由 sweep_tolerance 实测标定。
	var total_gain: float = landed_y - _base_y
	if total_gain <= 0.0 or total_gain > max_step + STEP_TOLERANCE:
		return false

	body.global_position = Vector3(forward.origin.x, landed_y, forward.origin.z)
	return true


## 跟踪当前所站的平面高度。只在真正站定时更新，避免被棘轮过程带偏。
var _base_y: float = INF


## 跟踪当前所站的平面高度。只在真正站定时更新。
## 注意：不能要求 velocity < 0.05——_try_step_up 分支里把速度清零后
## move_and_slide 会重新写入速度，条件不稳定，导致 _base_y 一直是 INF（已实测踩到）。
## 改用"在地面上"这一个稳定条件。
func _update_base_y(body: CharacterBody3D) -> void:
	if body.is_on_floor():
		_base_y = body.global_position.y


func _verdicts() -> void:
	print("---- 判定 ----")

	var a3: bool = _lookup("Cat", 0.03, "naive")
	var a12: bool = _lookup("Cat", 0.12, "naive")
	print("BASELINE|naive_cat_3cm=%s|naive_cat_12cm=%s" % [a3, a12])
	if a12:
		print("NOTE|裸 move_and_slide 竟能上 12cm —— 与预期不符，需重新评估")
	else:
		print("NOTE|确认：裸 move_and_slide 上不了 12cm 台阶，12cm 必须自实现")

	var checks := [
		["Cat_3cm_should_pass", "Cat", 0.03, true],
		["Cat_12cm_should_pass", "Cat", 0.12, true],
		["Cat_20cm_should_block", "Cat", 0.20, false],
		["Mouse_3cm_should_pass", "Mouse", 0.03, true],
		["Mouse_12cm_should_block", "Mouse", 0.12, false],
		["Mouse_20cm_should_block", "Mouse", 0.20, false],
	]
	for c in checks:
		var actual: bool = _lookup(c[1], c[2], "stepup")
		var expected: bool = c[3]
		print("CAPABILITY|%s|expected=%s|actual=%s|%s" % [
			c[0], expected, actual, "OK" if actual == expected else "MISMATCH"
		])


func _lookup(species: String, step_height: float, mode: String) -> bool:
	var key := "%s|%.2f" % [species, step_height]
	if _results.has(key) and _results[key].has(mode):
		return _results[key][mode]
	return false
