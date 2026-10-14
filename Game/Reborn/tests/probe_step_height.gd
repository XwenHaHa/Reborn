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
## 台阶抬升组件（同一算法只实现一次；见 scripts/characters/step_climb.gd）
var _climb: StepClimb = null


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
	_climb = null   # 每个试验用全新的组件实例（落脚面基准随实例复位）
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

	# 组件化后的台阶抬升：上限来自本用例的物种配置值（探针里是 CAPSULES 表）
	_climb = StepClimb.new(body, cfg.max_step, STEP_TOLERANCE, RADIUS_SAFE)

	await process_frame
	for i in SETTLE_STEPS:
		body.velocity = Vector3.ZERO
		await physics_frame

	# 站稳后确定"当前落脚面"基准
	_climb.update_base_y()
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
			_climb.step_or_slide(motion, dt)
		max_x = maxf(max_x, body.global_position.x)
		await physics_frame
		if mode == "stepup":
			_climb.update_base_y()

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


## 台阶抬升算法已**组件化**到 `res://scripts/characters/step_climb.gd`（`class_name StepClimb`），
## 本探针调用的是**同一实现**，不再保留本地副本 —— 因此下面的 6/6 判定同时也是该组件的回归证据。
## 实测根因、判据与标定记录见 `Docs/Evidence/T009-probe.md` 与组件文件头注释。

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
