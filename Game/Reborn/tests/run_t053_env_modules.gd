extends SceneTree
## T053：环境模块生产 —— **模块口径 + 洞口通行**断言套件。
##
## 开发计划 :221「环境模块生产：先做石块、树根/洞口、矮墙等 3～5 个模块；不把碰撞堵住鼠路」。
##
## 覆盖三类判据：
##  A. 每个模块自身的口径（`Docs/ART_ASSET_SPEC.md` §4.3～§4.5d）：
##     面数预算、材质槽数、尺寸、原点落地（`min_y≈0`）、**GLB 内不带碰撞**（碰撞由关卡显式建）；
##  B. 关卡里的**碰撞与视觉一致**：`CreekBoulder` 的 `BoxShape3D.size` 必须等于实例网格的
##     世界 AABB（±1 mm）——之前没有任何断言，视觉比碰撞大 0 或小 0 都看不出来；
##  C. **不把碰撞堵住鼠路**：洞口净空 ≥ 0.24×0.30 m，且用真实胶囊做物理查询：
##     鼠（r 0.06 / 高 0.18）在洞口中心**不碰到任何静态体**，猫（r 0.16 / 高 0.48）**必须被挡**。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t053_env_modules.gd' --quit-after 60000
## 结果口径：RESULT|pass=<n>|fail=<n>|failed=...

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const ENV := "res://assets/environment/"

const SIZE_EPS := 0.012      # 尺寸容差（m）：放样/导入的量化误差
const GROUND_EPS := 0.002    # 原点落地容差（m）
const HOLE_W_MIN := 0.24     # 鼠洞净宽下限（`HOLE_W`，tool_make_courtyard.gd）
const HOLE_H_MIN := 0.30     # 鼠洞净高下限（`HOLE_H`）

## 模块表：tris_max 取 spec 预算上界；size 取**本次实测**（作为回归基线，漂移即红灯）
const MODULES := [
	{"file": "sm_boulder_001", "tris_min": 1000, "tris_max": 8000, "mats": 1,
		"size": Vector3(1.269, 1.004, 1.829)},
	{"file": "sm_root_hole_001", "tris_min": 3000, "tris_max": 15000, "mats": 1,
		"size": Vector3(0.823, 0.850, 0.778)},
	{"file": "sm_root_barrier_001", "tris_min": 100, "tris_max": 4000, "mats": 1,
		"size": Vector3(2.461, 0.480, 0.296)},
	{"file": "sm_wall_low_001", "tris_min": 500, "tris_max": 4000, "mats": 1,
		"size": Vector3(2.437, 0.800, 0.303)},
	{"file": "sm_fence_module_001", "tris_min": 500, "tris_max": 4000, "mats": 1,
		"size": Vector3(3.680, 3.000, 0.303)},
	{"file": "sm_quoin_001", "tris_min": 100, "tris_max": 1000, "mats": 1,
		"size": Vector3(0.382, 1.600, 0.422)},
	{"file": "sm_shelter_post_001", "tris_min": 12, "tris_max": 200, "mats": 1,
		"size": Vector3(0.160, 1.620, 0.360)},
	{"file": "sm_bush_002", "tris_min": 1000, "tris_max": 6000, "mats": 2,
		"size": Vector3(2.800, 0.816, 2.930)},
]

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _level: Node3D = null


func _initialize() -> void:
	await _check_modules()
	_level = (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(_level)
	await physics_frame
	await physics_frame
	_check_boulder_collision()
	_check_root_hole_passage()
	_finish()


# ---------------- A：模块口径 ----------------

func _check_modules() -> void:
	for cfg in MODULES:
		var path := ENV + String(cfg["file"]) + ".glb"
		var packed := load(path) as PackedScene
		if not _assert("A_load_%s" % cfg["file"], "PackedScene", str(packed != null), packed != null):
			continue
		var inst := packed.instantiate() as Node3D
		root.add_child(inst)
		await process_frame

		var meshes := _meshes(inst)
		var tris := 0
		var mats := {}
		for m in meshes:
			var mesh := (m as MeshInstance3D).mesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				tris += (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)
				var mat := mesh.surface_get_material(s)
				mats["%s" % (mat.get_instance_id() if mat != null else 0)] = true

		var aabb := _world_aabb(meshes)
		var tag := String(cfg["file"])
		_assert("A_tris_%s" % tag, "%d..%d" % [cfg["tris_min"], cfg["tris_max"]], str(tris),
			tris >= int(cfg["tris_min"]) and tris <= int(cfg["tris_max"]))
		_assert("A_mats_%s" % tag, "≤ %d 槽" % cfg["mats"], str(mats.size()),
			mats.size() <= int(cfg["mats"]))
		var want: Vector3 = cfg["size"]
		_assert("A_size_%s" % tag, "(%.3f,%.3f,%.3f)" % [want.x, want.y, want.z],
			"(%.3f,%.3f,%.3f)" % [aabb.size.x, aabb.size.y, aabb.size.z],
			absf(aabb.size.x - want.x) <= SIZE_EPS and absf(aabb.size.y - want.y) <= SIZE_EPS
				and absf(aabb.size.z - want.z) <= SIZE_EPS)
		_assert("A_grounded_%s" % tag, "min_y ≈ 0", "%.4f" % aabb.position.y,
			absf(aabb.position.y) <= GROUND_EPS)
		# 碰撞必须在关卡侧显式建（spec §4.3/§4.4「碰撞：无」），GLB 自带碰撞会重复且难改
		var cols := _collision_count(inst)
		_assert("A_no_collision_%s" % tag, "0", str(cols), cols == 0)
		print("MEASURE|%s|tris=%d|mats=%d|size=(%.3f,%.3f,%.3f)|min_y=%.4f|collision=%d" % [
			tag, tris, mats.size(), aabb.size.x, aabb.size.y, aabb.size.z, aabb.position.y, cols])

		inst.queue_free()
		await process_frame


# ---------------- B：碰撞与视觉一致 ----------------

func _check_boulder_collision() -> void:
	var body := _level.get_node_or_null("CreekBoulder") as StaticBody3D
	if not _assert("B_boulder_exists", "StaticBody3D", str(body != null), body != null):
		return
	var shape := body.get_node_or_null("Shape") as CollisionShape3D
	var box := shape.shape as BoxShape3D if shape != null else null
	if not _assert("B_boulder_box_shape", "BoxShape3D", str(box != null), box != null):
		return
	var holder := body.get_node_or_null("Mesh") as Node3D
	var meshes := _meshes(holder) if holder != null else ([] as Array[Node])
	var aabb := _world_aabb(meshes)
	var shape_size := box.size
	_assert("B_boulder_collider_matches_visual", "(%.3f,%.3f,%.3f)" % [aabb.size.x, aabb.size.y, aabb.size.z],
		"(%.3f,%.3f,%.3f)" % [shape_size.x, shape_size.y, shape_size.z],
		absf(shape_size.x - aabb.size.x) <= 0.002 and absf(shape_size.y - aabb.size.y) <= 0.002
			and absf(shape_size.z - aabb.size.z) <= 0.002)
	print("MEASURE|boulder|visual=(%.3f,%.3f,%.3f)|collider=(%.3f,%.3f,%.3f)" % [
		aabb.size.x, aabb.size.y, aabb.size.z, shape_size.x, shape_size.y, shape_size.z])


# ---------------- C：洞口净空 + 鼠能进 / 猫不能 ----------------

func _check_root_hole_passage() -> void:
	var west := _level.get_node_or_null("RootBarrierWest") as StaticBody3D
	var east := _level.get_node_or_null("RootBarrierEast") as StaticBody3D
	var lintel := _level.get_node_or_null("RootBarrierLintel") as StaticBody3D
	if not _assert("C_barriers_exist", "West/East/Lintel",
			"%s/%s/%s" % [west != null, east != null, lintel != null],
			west != null and east != null and lintel != null):
		return
	var wb := _shape_aabb(west)
	var eb := _shape_aabb(east)
	var lb := _shape_aabb(lintel)
	var gap_w := eb.position.x - (wb.position.x + wb.size.x)
	var gap_top := lb.position.y
	# 净空基准是屏障的**底面**（地面），不是顶面：屏障 y∈[0.10,0.60]、门楣底面 0.40 ⇒ 净高 0.30。
	# 第一版写成 `position.y + size.y`（顶面 0.60），算出 −0.20 的负净高（夹具错，不是几何错）。
	var ground := wb.position.y
	var gap_h := gap_top - ground
	_assert("C_hole_width_ge_0.24", "≥ %.2f m" % HOLE_W_MIN, "%.4f m" % gap_w, gap_w >= HOLE_W_MIN - 1e-4)
	_assert("C_hole_height_ge_0.30", "≥ %.2f m" % HOLE_H_MIN, "%.4f m" % gap_h, gap_h >= HOLE_H_MIN - 1e-4)

	var center := Vector3(
		(wb.position.x + wb.size.x + eb.position.x) * 0.5,
		ground + gap_h * 0.5,
		(wb.position.z + wb.size.z * 0.5))
	var space := (_level.get_world_3d() as World3D).direct_space_state if _level != null else null
	if not _assert("C_space_state", "PhysicsDirectSpaceState3D", str(space != null), space != null):
		return

	var mouse_hits := _capsule_hits(space, center, 0.06, 0.18)
	var cat_hits := _capsule_hits(space, center, 0.16, 0.48)
	_assert("C_mouse_capsule_passes_hole", "0 个静态体", str(mouse_hits), mouse_hits == 0)
	_assert("C_cat_capsule_blocked_by_hole", "≥ 1 个静态体", str(cat_hits), cat_hits >= 1)
	print("MEASURE|root_hole|west=(%.3f,%.3f,%.3f)s=(%.3f,%.3f,%.3f)|east=(%.3f,%.3f,%.3f)s=(%.3f,%.3f,%.3f)|lintel=(%.3f,%.3f,%.3f)s=(%.3f,%.3f,%.3f)|ground=%.3f|gap=(%.4f x %.4f)|center=(%.3f,%.3f,%.3f)|mouse_hits=%d|cat_hits=%d" % [
		wb.position.x, wb.position.y, wb.position.z, wb.size.x, wb.size.y, wb.size.z,
		eb.position.x, eb.position.y, eb.position.z, eb.size.x, eb.size.y, eb.size.z,
		lb.position.x, lb.position.y, lb.position.z, lb.size.x, lb.size.y, lb.size.z,
		ground, gap_w, gap_h, center.x, center.y, center.z, mouse_hits, cat_hits])


func _capsule_hits(space: PhysicsDirectSpaceState3D, at: Vector3, radius: float, height: float) -> int:
	var params := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = height
	params.shape = cap
	params.transform = Transform3D(Basis(), at)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return space.intersect_shape(params, 32).size()


# ---------------- 工具 ----------------

func _shape_aabb(body: StaticBody3D) -> AABB:
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var box := cs.shape as BoxShape3D
		if box == null:
			continue
		var center := cs.global_position
		return AABB(center - box.size * 0.5, box.size)
	return AABB()


func _meshes(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _world_aabb(meshes: Array[Node]) -> AABB:
	var out := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _collision_count(n: Node) -> int:
	var count := 1 if (n is CollisionShape3D or n is CollisionPolygon3D) else 0
	for c in n.get_children():
		count += _collision_count(c)
	return count


func _assert(tag: String, expected: String, actual: String, ok: bool) -> bool:
	if ok:
		_pass += 1
		print("ASSERT|%s|%s|%s|PASS" % [tag, expected, actual])
	else:
		_fail += 1
		_failed.append(tag)
		print("ASSERT|%s|%s|%s|FAIL" % [tag, expected, actual])
	return ok


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_pass + _fail, _fail])
	if _fail == 0:
		print("RESULT|pass=%d|fail=0|failed=" % _pass)
		quit(0)
	else:
		print("RESULT|pass=%d|fail=%d|failed=%s" % [_pass, _fail, "|".join(_failed)])
		quit(1)
