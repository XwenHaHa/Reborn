extends SceneTree
## T008 无头验收：最小物种配置与身体（Cat / Mouse）
##
## 验收的不是"文件存在"，而是：
##   A) 两个 `.tres` 是 `SpeciesConfig`，**逐字段**与 `Parameters.md`（cm→m）一致，`validate_config()` 无问题
##   B) `AnimalBody` 按配置成型：胶囊半径/总高、相机偏移/FOV、碰撞层，并且 `max_step_height` 真的接到 `StepClimb`
##   C) **物理实测**：猫能上 12 cm、上不了 20 cm；鼠能上 3 cm、上不了 12 cm（全部经配置驱动）
##   D) **不散落物种判断**：`animal_body.gd` / `step_climb.gd` 源码里没有物种名字面量与 `species_id ==` 分支
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t008_species.gd' --quit-after 20000
## 退出码：0 = 全部断言通过；1 = 有失败。

const BODY := "res://scenes/characters/animal_body.tscn"

## 起测参数（Docs/Parameters.md，cm → m）。**改这里之前先改 Parameters.md。**
const CAT := {
	"path": "res://resources/species/cat.tres",
	"id": "Cat",
	"floats": {
		"capsule_radius": 0.16,
		"capsule_half_height": 0.24,
		"walk_speed": 1.80,
		"crouch_half_height": 0.15,
		"sprint_speed": 4.50,
		"crouch_speed": 0.90,
		"max_step_height": 0.12,
		"jump_velocity": 3.20,
		"max_acceleration": 10.0,
		"camera_offset_z": 0.10,
		"fov": 90.0,
		"vision_range": 9.0,
		"vision_half_angle_deg": 60.0,
		"hearing_range": 12.0,
		"hunger_loss_per_sec": 0.08,
		"thirst_loss_per_sec": 0.06,
		"sprint_stamina_per_sec": 15.0,
		"stamina_regen_per_sec": 18.0,
		"regen_delay": 1.0,
		"interaction_range": 1.00,
	},
	"food": 0,
	"can_jump": true,
	"can_pounce": true,
	"can_tunnel": false,
	"too_high": 0.20,
}
const MOUSE := {
	"path": "res://resources/species/mouse.tres",
	"id": "Mouse",
	"floats": {
		"capsule_radius": 0.06,
		"capsule_half_height": 0.09,
		"walk_speed": 1.10,
		"sprint_speed": 3.00,
		"crouch_speed": 0.65,
		"max_step_height": 0.03,
		"jump_velocity": 0.0,
		"crouch_half_height": 0.06,
		"max_acceleration": 16.0,
		"camera_offset_z": 0.03,
		"fov": 90.0,
		"vision_range": 6.5,
		"vision_half_angle_deg": 75.0,
		"hearing_range": 10.0,
		"hunger_loss_per_sec": 0.10,
		"thirst_loss_per_sec": 0.08,
		"sprint_stamina_per_sec": 35.0,
		"stamina_regen_per_sec": 25.0,
		"regen_delay": 0.7,
		"interaction_range": 0.45,
	},
	"food": 1,
	"can_jump": false,
	"can_pounce": false,
	"can_tunnel": true,
	"too_high": 0.12,
}

## 台阶试验用的固定条件（与 tests/probe_step_height.gd 一致，便于对照）
const SPEED := 1.0
const START_X := -1.0
const TARGET_X := 2.0
const SETTLE_STEPS := 40
const MAX_ITERS := 700
const EPS := 0.000001

var _checks := 0
var _fails := 0


func _initialize() -> void:
	print("TEST|run_t008_species|engine=%s" % Engine.get_version_info().string)

	var cat := _check_config("cat", CAT)
	var mouse := _check_config("mouse", MOUSE)

	# 两个物种的稳定 ID 必须互不相同（防止"复制粘贴忘改 ID"）
	if cat != null and mouse != null:
		_assert("species_ids_distinct", "different", "%s / %s" % [cat.species_id, mouse.species_id],
			cat.species_id != mouse.species_id)

	if cat != null:
		await _check_body_applies("cat", cat)
	if mouse != null:
		await _check_body_applies("mouse", mouse)

	if cat != null:
		await _check_step_cases("cat", cat, CAT["too_high"])
	if mouse != null:
		await _check_step_cases("mouse", mouse, MOUSE["too_high"])

	_check_no_species_branching()
	_finish()


# ---------------------------------------------------------------------------
# A) 配置逐字段核对
# ---------------------------------------------------------------------------

func _check_config(key: String, spec: Dictionary) -> SpeciesConfig:
	var cfg: SpeciesConfig = load(spec["path"])
	var loaded: bool = cfg != null
	_assert("config_%s_loads" % key, "SpeciesConfig", "null" if not loaded else str(cfg.get_class()), loaded)
	if not loaded:
		return null

	var id_ok: bool = str(cfg.species_id) == str(spec["id"])
	_assert("config_%s_species_id" % key, str(spec["id"]), str(cfg.species_id), id_ok)

	var floats: Dictionary = spec["floats"]
	for field in floats:
		_assert_near("config_%s_%s" % [key, field], float(floats[field]), float(cfg.get(field)), EPS)

	var expect_food := "[%d]" % int(spec["food"])
	_assert("config_%s_allowed_food_types" % key, expect_food, str(cfg.allowed_food_types),
		str(cfg.allowed_food_types) == expect_food)

	_assert("config_%s_can_jump" % key, str(spec["can_jump"]), str(cfg.can_jump), cfg.can_jump == spec["can_jump"])
	_assert("config_%s_can_pounce" % key, str(spec["can_pounce"]), str(cfg.can_pounce), cfg.can_pounce == spec["can_pounce"])
	_assert("config_%s_can_use_mouse_tunnel" % key, str(spec["can_tunnel"]), str(cfg.can_use_mouse_tunnel),
		cfg.can_use_mouse_tunnel == spec["can_tunnel"])

	# Godot 的 CapsuleShape3D.height 是含半球总高
	_assert_near("config_%s_capsule_height_is_2x_half" % key, cfg.capsule_half_height * 2.0, cfg.capsule_height(), EPS)

	# 蹲姿（T009 新增参数）：比站姿矮，才能"蹲着过 42 cm 低顶"
	_assert_near("config_%s_crouch_height_is_2x_half" % key, cfg.crouch_half_height * 2.0, cfg.crouch_height(), EPS)
	_assert("config_%s_crouch_lower_than_stand" % key, "crouch < stand",
		"%.3f < %.3f" % [cfg.crouch_height(), cfg.capsule_height()], cfg.crouch_height() < cfg.capsule_height())
	_assert_near("config_%s_crouch_drop" % key, cfg.capsule_half_height - cfg.crouch_half_height, cfg.crouch_drop(), EPS)


	# 食物能力查询（调用方不需要知道物种）
	_assert("config_%s_can_eat_own_food" % key, "true", str(cfg.can_eat(int(spec["food"]))),
		cfg.can_eat(int(spec["food"])))
	var other_food: int = 1 - int(spec["food"])
	_assert("config_%s_cannot_eat_other_food" % key, "false", str(cfg.can_eat(other_food)),
		not cfg.can_eat(other_food))

	var problems := cfg.validate_config()
	_assert("config_%s_validate_config" % key, "no problems", str(problems), problems.is_empty())

	print("CONFIG|%s|radius=%.3f|half_height=%.3f|total_height=%.3f|max_step=%.3f|jump=%.2f" % [
		cfg.species_id, cfg.capsule_radius, cfg.capsule_half_height, cfg.capsule_height(),
		cfg.max_step_height, cfg.jump_velocity
	])
	return cfg


# ---------------------------------------------------------------------------
# B) 身体按配置成型
# ---------------------------------------------------------------------------

func _check_body_applies(key: String, cfg: SpeciesConfig) -> void:
	var packed: PackedScene = load(BODY)
	if packed == null:
		_assert("body_%s_scene_loads" % key, "PackedScene", "null", false)
		return
	_assert("body_%s_scene_loads" % key, "PackedScene", "PackedScene", true)

	var world := Node3D.new()
	world.name = "T008BodyWorld"
	root.add_child(world)
	var body: AnimalBody = packed.instantiate() as AnimalBody
	body.species_config = cfg
	world.add_child(body)
	await process_frame

	var state := body.debug_state()
	print("BODY|%s|%s" % [key, str(state)])

	_assert("body_%s_is_character_body" % key, "CharacterBody3D", body.get_class(), body is CharacterBody3D)
	_assert_near("body_%s_capsule_radius" % key, cfg.capsule_radius, float(state["capsule_radius"]), EPS)
	_assert_near("body_%s_capsule_height" % key, cfg.capsule_height(), float(state["capsule_height"]), EPS)
	_assert_near("body_%s_camera_offset_z" % key, cfg.camera_offset_z, float(state["camera_offset_z"]), EPS)
	# 相机偏移的轴向（T009 决策 D1）：必须是**竖直**偏移，不是 +Z；且没有水平分量
	_assert("body_%s_camera_offset_axis" % key, "y (vertical)", str(state["camera_offset_axis"]),
		str(state["camera_offset_axis"]) == "y")
	var cam_local: Vector3 = state["camera_local_position"]
	_assert("body_%s_camera_no_horizontal_offset" % key, "|x|,|z| < 0.001",
		"x=%.4f z=%.4f" % [cam_local.x, cam_local.z], absf(cam_local.x) < 0.001 and absf(cam_local.z) < 0.001)
	_assert_near("body_%s_fov" % key, cfg.fov, float(state["fov"]), EPS)

	# 碰撞层：animal(2) 检测 world_static(1)（不新增未验证层）
	_assert("body_%s_collision_layer" % key, "2 (animal)", str(body.collision_layer), body.collision_layer == AnimalBody.LAYER_ANIMAL)
	_assert("body_%s_collision_mask" % key, "1 (world_static)", str(body.collision_mask), body.collision_mask == AnimalBody.LAYER_WORLD_STATIC)

	# 台阶上限来自配置
	var has_climb: bool = body.climb != null
	_assert("body_%s_has_step_climb" % key, "StepClimb", "null" if not has_climb else "StepClimb", has_climb)
	if has_climb:
		_assert_near("body_%s_climb_max_step" % key, cfg.max_step_height, body.climb.max_step_height, EPS)

	# 能力查询走配置
	_assert("body_%s_can_jump" % key, str(cfg.can_jump), str(body.can_jump()), body.can_jump() == cfg.can_jump)
	_assert("body_%s_can_pounce" % key, str(cfg.can_pounce), str(body.can_pounce()), body.can_pounce() == cfg.can_pounce)
	_assert("body_%s_can_use_mouse_tunnel" % key, str(cfg.can_use_mouse_tunnel), str(body.can_use_mouse_tunnel()),
		body.can_use_mouse_tunnel() == cfg.can_use_mouse_tunnel)

	world.queue_free()
	await process_frame


# ---------------------------------------------------------------------------
# C) 配置驱动的台阶能力（物理实测）
# ---------------------------------------------------------------------------

func _check_step_cases(key: String, cfg: SpeciesConfig, too_high: float) -> void:
	var ok := await _run_step_case(cfg, cfg.max_step_height)
	print("STEP|%s|capsule_radius=%.3f|capsule_height=%.3f|step=%.3f|climbed=%.4f|max_x=%.3f|reached=%s" % [
		cfg.species_id, cfg.capsule_radius, cfg.capsule_height(), cfg.max_step_height,
		ok["climbed"], ok["max_x"], ok["reached"]
	])
	_assert("step_%s_on_max_step_reached" % key, "true", str(ok["reached"]), ok["reached"])
	_assert("step_%s_on_max_step_climbed" % key, "> %.3f" % (cfg.max_step_height * 0.5),
		"%.4f" % ok["climbed"], ok["climbed"] > cfg.max_step_height * 0.5)

	var high := await _run_step_case(cfg, too_high)
	print("STEP|%s|step=%.3f（高于上限）|climbed=%.4f|max_x=%.3f|reached=%s" % [
		cfg.species_id, too_high, high["climbed"], high["max_x"], high["reached"]
	])
	var blocked: bool = not (high["reached"] and high["climbed"] > too_high * 0.5)
	_assert("step_%s_on_too_high_blocked" % key, "blocked", "reached=%s climbed=%.4f" % [high["reached"], high["climbed"]], blocked)


## 一个台阶用例：全新世界（避免互相污染），角色体由配置驱动
func _run_step_case(cfg: SpeciesConfig, step_height: float) -> Dictionary:
	var world := Node3D.new()
	world.name = "T008Step_%s_%.2f" % [cfg.species_id, step_height]
	root.add_child(world)
	_add_box(world, "Ground", Vector3(40, 1.0, 20), Vector3(0, -0.5, 0))
	_add_box(world, "Step", Vector3(6.0, step_height, 6.0), Vector3(3.0, step_height * 0.5, 0))

	var packed: PackedScene = load(BODY)
	var body: AnimalBody = packed.instantiate() as AnimalBody
	body.species_config = cfg
	world.add_child(body)
	body.global_position = Vector3(START_X, cfg.capsule_half_height + 0.002, 0.0)
	await process_frame

	for i in SETTLE_STEPS:
		body.velocity = Vector3.ZERO
		await physics_frame

	body.climb.update_base_y()
	var y_before: float = body.global_position.y
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var motion := Vector3(SPEED * dt, 0.0, 0.0)
	var iters := 0
	var max_x: float = START_X
	while body.global_position.x < TARGET_X and iters < MAX_ITERS:
		iters += 1
		body.climb.step_or_slide(motion, dt)
		max_x = maxf(max_x, body.global_position.x)
		await physics_frame
		body.climb.update_base_y()

	for i in 20:
		body.velocity = Vector3.ZERO
		await physics_frame

	var y_after: float = body.global_position.y
	world.queue_free()
	await process_frame
	await process_frame
	return {
		"climbed": y_after - y_before,
		"max_x": max_x,
		"reached": max_x >= TARGET_X - 0.05,
	}


# ---------------------------------------------------------------------------
# D) 静态检查：代码里不散落物种名判断
# ---------------------------------------------------------------------------

func _check_no_species_branching() -> void:
	var paths := [
		"res://scripts/characters/animal_body.gd",
		"res://scripts/characters/step_climb.gd",
	]
	var needles := ["\"Cat\"", "\"Mouse\"", "&\"Cat\"", "&\"Mouse\"", "species_id =="]
	var checked := 0
	var missing := PackedStringArray()
	for path in paths:
		if not FileAccess.file_exists(path):
			missing.append(path)
			continue
		checked += 1
		var f := FileAccess.open(path, FileAccess.READ)
		var src := f.get_as_text()
		for needle in needles:
			var found: bool = src.contains(needle)
			_assert("no_species_branch_%s_%s" % [path.get_file().get_basename(), needle.replace("\"", "Q")],
				"absent", "present" if found else "absent", not found)

	if checked == 0:
		# 打包产物里只有编译后的资源，源码读不到 → 本检查**不适用**（如实标 N/A，
		# 既不假装通过、也不算失败）。在工程内运行时，下面的断言会执行。
		print("STATIC|NOT-APPLICABLE|readable=%d/%d|missing=%s" % [
			checked, paths.size(), ",".join(missing)
		])
		return
	_assert("static_check_covered_all_sources", str(paths.size()), "%d files" % checked, checked == paths.size())


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _add_box(parent: Node3D, nm: String, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.name = nm
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	sb.add_child(cs)
	parent.add_child(sb)


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	var ok: bool = absf(expected - actual) <= eps
	_assert(id, "%.6f (±%.6f)" % [expected, eps], "%.6f" % actual, ok)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
