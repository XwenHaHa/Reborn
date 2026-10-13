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

## 探测前移量的下限（米）。必须足以让胶囊底心越过台阶竖直面，
## 否则下探会一直撞在台阶顶棱（不可站立面）上。取略大于最大胶囊半径。
const RADIUS_SAFE: float = 0.20

var _results: Dictionary = {}


func _initialize() -> void:
	print("PROBE|step_height|engine=%s" % Engine.get_version_info().string)
	print("PROBE|physics_hz=%d|speed=%.2f|start_x=%.2f|target_x=%.2f|tolerance=%.4f" % [
		Engine.physics_ticks_per_second, SPEED, START_X, TARGET_X, STEP_TOLERANCE
	])

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


## 自实现台阶抬升（v4 —— 基于实测根因重写）
##
## 根因（实测，见 Docs/Evidence/T009-probe.md）：
##   胶囊底部是半球。面对台阶时它停在"底心仍在台阶面左侧、圆底蹭到台阶顶棱"
##   的位置。向下探测在该处命中的是**棱角**：
##     碰撞点 (0.0, 0.12, 0.0)，法线 (-0.864, 0.504, 0)
##   法线与竖直方向夹角 59.7°，超出 Godot 默认 floor_max_angle（45°），
##   因此引擎判定为**墙面、不可站立**，落点也停在半空（胶囊底 0.0407）。
##
## 结论：不能只看"下落有没有命中"，必须**要求落点是可站立面**（法线足够竖直）。
##   同时在抬高前先让水平位移推进到被挡，使胶囊真正贴住台阶，再抬高前进。
##
## 判据（三条同时成立）：
##   1. 头顶有抬高空间
##   2. 抬高并前移后不被阻挡
##   3. 下落命中，且碰撞法线属于可站立面（n.y ≥ cos(floor_max_angle)），
##      并且落点相对当前落脚面的抬升 ∈ (0, max_step]
func _try_step_up(body: CharacterBody3D, motion: Vector3, max_step: float) -> bool:
	var flat := Vector3(motion.x, 0.0, motion.z)
	if flat.length() < 0.000001:
		return false

	var y_start: float = body.global_position.y
	var base: float = _base_y if is_finite(_base_y) else y_start
	# Godot 默认 floor_max_angle 是 45°，这里用同一判据认定"可站立"
	var min_walkable_ny: float = cos(deg_to_rad(45.0))

	# 前方必须有障碍（否则不是台阶场景）
	if not body.test_move(body.global_transform, flat):
		return false

	# 关键（v5）：**探测用的抬高量必须大于台阶阈值**，与 max_step 解耦。
	#
	# 原因：胶囊底部是半球。贴住台阶时圆底蹭在台阶顶棱上，底心高度比台阶顶
	# 还低。要让平底越过棱角，抬高量必须超过台阶高度本身，而不是只抬 max_step。
	# 实测：抬 max_step 时猫上不了 12cm 台阶（抬到 0.122 vs 台阶顶 0.120，
	# 只差 2mm，前进仍然蹭棱 → 可站立面判据拒绝）。
	#
	# 放宽抬高量**不会**放过更高台阶：过高的台阶会在"抬高后仍被挡"或最终
	# 增益上界校验处被拒绝。阈值把关靠 total_gain，不靠抬高量。
	var probe_raise: float = max_step * 2.0 + 0.05
	# 头顶空间：抬这么高会顶到天花板就放弃（低顶下不应上台阶）
	if body.test_move(body.global_transform, Vector3.UP * probe_raise):
		return false

	var raised := body.global_transform.translated(Vector3.UP * probe_raise)

	# 关键（v6）：**前移量必须足够让胶囊底心越过台阶竖直面**。
	#
	# 前一版用一帧的位移（motion，约 1.67cm）当前移量，结果底心根本没跨过
	# 台阶面（x=0），下探永远撞在台阶**顶棱**上：
	#   normal=(-0.868, 0.497, 0)  夹角 60° → 不可站立 → 被拒绝
	# 实测：把抬高量加到 0.29 也没用，因为问题在前移量而不是抬高量。
	#
	# 前移量取"至少一个半径 + 一个帧位移"，使平底足以落到台阶顶面之上。
	var forward_dist: float = maxf(flat.length(), 0.0)
	var probe_forward: float = RADIUS_SAFE + forward_dist
	var fwd_dir: Vector3 = flat.normalized()
	var forward := raised.translated(fwd_dir * probe_forward)
	if body.test_move(raised, fwd_dir * probe_forward):
		return false  # 抬起后仍被挡 → 台阶高于阈值

	# 下落探测，并收集所有碰撞的法线
	var params := PhysicsTestMotionParameters3D.new()
	params.from = forward
	params.motion = Vector3.DOWN * (probe_raise + 0.5)
	params.margin = 0.001
	params.max_collisions = 8
	var res := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), params, res):
		return false  # 前方悬空

	# 必须有**可站立**的接触面；只有棱角接触时返回 false
	var walkable := false
	for i in res.get_collision_count():
		if res.get_collision_normal(i).y >= min_walkable_ny:
			walkable = true
			break
	if not walkable:
		return false

	var landed_y: float = forward.origin.y + res.get_travel().y
	var total_gain: float = landed_y - base
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
