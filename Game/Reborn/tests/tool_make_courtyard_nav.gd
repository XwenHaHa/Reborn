extends SceneTree
## 导航数据工具（T012）：给生态灰盒 `res://scenes/maps/l_courtyard.tscn` 生成**分物种导航数据**。
##
## 三步（幂等；可反复整链重跑）：
##   ① **不入树**改场景：给所有 `StaticBody3D` 加持久分组 `nav_source_courtyard`，
##      并加两个 `NavigationRegion3D`：`NavRegion_Mouse`（layer 1）/ `NavRegion_Cat`（layer 2）。
##   ② **入树**烘焙（刻意破例：烘焙必须让几何在世界里可见）：两张 `NavigationMesh` 存
##      `res://resources/nav/l_courtyard_{mouse,cat}.tres`。**只读几何、只写 .tres，不保存场景。**
##   ③ **不入树**把两张 `.tres` 赋给对应 region 的 `navigation_mesh`，再保存场景。
##
## 为什么两张图 + 分层：`agent_radius` 是**烘焙参数**，一张图无法同时满足"0.12 宽的鼠过得去、
## 0.32 宽的猫过不去"的 0.24 洞。同图不同 layer 让两种物种各自只走自己的面（Godot 官方机制）。
##
## 烘焙参数由**实测**确定（`Docs/Evidence/T012.md` §4）：cell 0.03 / region_min_size 0.02 时
## 0.24 的洞能留在导航面上（鼠路径直穿、长度 = 直线距离）；cell ≥0.05 时洞被吃掉、路径改绕行。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_make_courtyard_nav.gd'

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const NAV_DIR := "res://resources/nav"
const OUT_MOUSE := "res://resources/nav/l_courtyard_mouse.tres"
const OUT_CAT := "res://resources/nav/l_courtyard_cat.tres"
const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"

const GROUP := "nav_source_courtyard"
const REGION_MOUSE := "NavRegion_Mouse"
const REGION_CAT := "NavRegion_Cat"
const LAYER_MOUSE := 1
const LAYER_CAT := 2

## 烘焙参数（实测口径，见文件头）
const CELL_SIZE := 0.03
const CELL_HEIGHT := 0.03
const REGION_MIN_SIZE := 0.02
const RADIUS_MARGIN := 0.01
const HEIGHT_MARGIN := 0.02
const MAX_SLOPE_DEG := 45.0

## 烘焙就绪等待上限（帧）。实测：新进程里第一张图要等若干帧才可查询（见 §4 实测）
const WARMUP_MAX_FRAMES := 600

var _fails := 0


func _initialize() -> void:
	print("TOOL|courtyard_nav|start")
	var cat := load(CAT) as SpeciesConfig
	var mouse := load(MOUSE) as SpeciesConfig
	if cat == null or mouse == null:
		print("TOOL|ERROR|species configs missing")
		quit(1)
		return

	# --- ① 不入树：加分组 + 两个 region ---
	var scene: Node3D = (load(LEVEL) as PackedScene).instantiate() as Node3D
	if scene == null:
		print("TOOL|ERROR|level load failed")
		quit(1)
		return
	var grouped := 0
	for ch in scene.get_children():
		var sb := ch as StaticBody3D
		if sb == null:
			continue
		if not sb.is_in_group(GROUP):
			sb.add_to_group(GROUP, true)
		grouped += 1
	print("TOOL|grouped_static_bodies=%d|group=%s" % [grouped, GROUP])

	_ensure_region(scene, REGION_MOUSE, LAYER_MOUSE, mouse)
	_ensure_region(scene, REGION_CAT, LAYER_CAT, cat)
	var err := ResourceSaver.save(_pack(scene), LEVEL)
	print("TOOL|step1_save=%d (%s)" % [err, "OK" if err == OK else "FAIL"])
	scene.free()
	if err != OK:
		quit(1)
		return

	# --- ② 入树烘焙 ---
	await _bake_all(mouse, cat)

	# --- ③ 不入树：把 .tres 赋给 region ---
	var scene3: Node3D = (load(LEVEL) as PackedScene).instantiate() as Node3D
	var nm_mouse := load(OUT_MOUSE) as NavigationMesh
	var nm_cat := load(OUT_CAT) as NavigationMesh
	var ok3 := nm_mouse != null and nm_cat != null
	if ok3:
		(_get_region(scene3, REGION_MOUSE) as NavigationRegion3D).navigation_mesh = nm_mouse
		(_get_region(scene3, REGION_CAT) as NavigationRegion3D).navigation_mesh = nm_cat
		var err3 := ResourceSaver.save(_pack(scene3), LEVEL)
		print("TOOL|step3_save=%d (%s)" % [err3, "OK" if err3 == OK else "FAIL"])
		ok3 = err3 == OK
	scene3.free()

	# --- 自检 ---
	_verify(mouse, cat)
	print("TOOL|courtyard_nav|%s" % ("done" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)


func _pack(scene: Node3D) -> PackedScene:
	var ps := PackedScene.new()
	ps.pack(scene)
	return ps


func _ensure_region(scene: Node3D, nm: String, layer: int, cfg: SpeciesConfig) -> void:
	var existing := scene.get_node_or_null(nm) as NavigationRegion3D
	if existing != null:
		existing.navigation_layers = layer
		existing.navigation_mesh = null
		return
	var region := NavigationRegion3D.new()
	region.name = nm
	region.navigation_layers = layer
	region.navigation_mesh = null
	region.set_meta("agent_radius", cfg.capsule_radius + RADIUS_MARGIN)
	region.set_meta("agent_height", cfg.capsule_height() + HEIGHT_MARGIN)
	region.set_meta("agent_max_climb", cfg.max_step_height)
	region.set_meta("species_id", cfg.species_id)
	scene.add_child(region)
	region.owner = scene


func _get_region(scene: Node3D, nm: String) -> NavigationRegion3D:
	return scene.get_node_or_null(nm) as NavigationRegion3D


func _make_navmesh(cfg: SpeciesConfig) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.resource_name = "l_courtyard_%s" % String(cfg.species_id).to_lower()
	nm.cell_size = CELL_SIZE
	nm.cell_height = CELL_HEIGHT
	nm.agent_radius = cfg.capsule_radius + RADIUS_MARGIN
	nm.agent_height = cfg.capsule_height() + HEIGHT_MARGIN
	nm.agent_max_climb = cfg.max_step_height
	nm.agent_max_slope = MAX_SLOPE_DEG
	nm.region_min_size = REGION_MIN_SIZE
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = GROUP
	return nm


func _bake_all(mouse: SpeciesConfig, cat: SpeciesConfig) -> void:
	DirAccess.make_dir_recursive_absolute(NAV_DIR)
	var scene: Node3D = (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await process_frame
	await physics_frame

	var map := scene.get_world_3d().get_navigation_map()
	print("TOOL|map|valid=%s|cell_before=%.3f|project_setting=%s" % [
		str(map.is_valid()), NavigationServer3D.map_get_cell_size(map),
		str(ProjectSettings.get_setting("navigation/3d/default_cell_size", "<missing>"))
	])
	NavigationServer3D.map_set_cell_size(map, CELL_SIZE)
	NavigationServer3D.map_set_cell_height(map, CELL_HEIGHT)
	print("TOOL|map|cell_after=%.3f|height=%.3f" % [
		NavigationServer3D.map_get_cell_size(map), NavigationServer3D.map_get_cell_height(map)
	])

	var jobs := [
		{"region": REGION_MOUSE, "cfg": mouse, "out": OUT_MOUSE, "layer": LAYER_MOUSE},
		{"region": REGION_CAT, "cfg": cat, "out": OUT_CAT, "layer": LAYER_CAT},
	]
	var meshes := {}
	for job in jobs:
		var region := _get_region(scene, job["region"]) as NavigationRegion3D
		if region == null:
			print("TOOL|ERROR|region missing: %s" % job["region"])
			continue
		var nm := _make_navmesh(job["cfg"])
		region.navigation_mesh = nm
		region.navigation_layers = int(job["layer"])
		await process_frame
		region.bake_navigation_mesh(false)
		for i in 10:
			await physics_frame
		NavigationServer3D.map_force_update(map)
		var verts := nm.get_vertices()
		var sy := INF
		for v in verts:
			sy = minf(sy, v.y)
		print("TOOL|bake|region=%s|layer=%d|polys=%d|verts=%d|surface_y=%.3f|area=%.1f" % [
			job["region"], job["layer"], nm.get_polygon_count(), verts.size(),
			sy if verts.size() > 0 else -1.0, _mesh_area(nm)
		])
		var err := ResourceSaver.save(nm, job["out"])
		print("TOOL|save_navmesh|out=%s|result=%d (%s)" % [job["out"], err, "OK" if err == OK else "FAIL"])
		meshes[job["region"]] = nm

	# 注意（T012 实测）：**运行期**给 region 换 navmesh 后，同一进程内的地图查询不可靠
	# （实测等待 600 帧仍返回 0 个路径点）；烘焙产物**落盘**后在新进程里加载则一切正常。
	# 因此本工具只做"烘焙 + 落盘 + 赋回场景 + 结构自检"，
	# **路径与"猫能不能进洞"的断言放在独立进程**的 `run_t012_navigation.gd`（禁止假路径/瞬移掩饰）。
	var barrier := _barrier_geometry(scene)
	if not barrier.is_empty():
		print("TOOL|barrier|hole_x=%.3f|hole_w=%.3f|top=%.3f|z=[%.2f,%.2f]|lintel_bottom=%.3f" % [
			barrier["hole_x"], barrier["hole_w"], barrier["top"], barrier["z_min"], barrier["z_max"],
			barrier["lintel_bottom"]
		])
	scene.free()


## 树根屏障几何（洞中心 x、屏障顶 y、z 范围）
func _barrier_geometry(scene: Node3D) -> Dictionary:
	var lw := scene.get_node_or_null("RootBarrierWest") as StaticBody3D
	var le := scene.get_node_or_null("RootBarrierEast") as StaticBody3D
	var li := scene.get_node_or_null("RootBarrierLintel") as StaticBody3D
	if lw == null or le == null or li == null:
		return {}
	var lwc := lw.get_node_or_null("Shape") as CollisionShape3D
	var lec := le.get_node_or_null("Shape") as CollisionShape3D
	var lic := li.get_node_or_null("Shape") as CollisionShape3D
	var lb := lwc.shape as BoxShape3D
	var eb := lec.shape as BoxShape3D
	var ib := lic.shape as BoxShape3D
	return {
		"hole_x": (lw.position.x + lb.size.x * 0.5 + le.position.x - eb.size.x * 0.5) * 0.5,
		"top": lw.position.y + lb.size.y * 0.5,
		"z_min": lw.position.z - lb.size.z * 0.5,
		"z_max": lw.position.z + lb.size.z * 0.5,
		"hole_w": (le.position.x - eb.size.x * 0.5) - (lw.position.x + lb.size.x * 0.5),
		"lintel_bottom": li.position.y - ib.size.y * 0.5,
	}


func _crosses_hole(path: PackedVector3Array, b: Dictionary) -> bool:
	for i in range(1, path.size()):
		var p0: Vector3 = path[i - 1]
		var p1: Vector3 = path[i]
		if (p0.z > b["z_min"]) != (p1.z > b["z_min"]):
			if absf(p1.x - b["hole_x"]) <= b["hole_w"] * 0.5 + 0.02:
				return true
	return false


func _mesh_area(nm: NavigationMesh) -> float:
	var verts := nm.get_vertices()
	var area := 0.0
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		if poly.size() < 3:
			continue
		var a: Vector3 = verts[poly[0]]
		for j in range(1, poly.size() - 1):
			var b: Vector3 = verts[poly[j]]
			var c: Vector3 = verts[poly[j + 1]]
			area += ((b - a).cross(c - a)).length() * 0.5
	return area


func _verify(mouse: SpeciesConfig, cat: SpeciesConfig) -> void:
	var packed: PackedScene = load(LEVEL)
	_check("level_loads", packed != null)
	if packed == null:
		return
	var scene: Node3D = packed.instantiate() as Node3D
	_check("root_is_node3d", scene != null)
	if scene == null:
		return
	var grouped := 0
	for ch in scene.get_children():
		var sb := ch as StaticBody3D
		if sb != null and sb.is_in_group(GROUP):
			grouped += 1
	_check("nav_source_group_persisted", grouped >= 15)
	print("VERIFY|nav_source_group|count=%d" % grouped)

	var rn := _get_region(scene, REGION_MOUSE)
	var rc := _get_region(scene, REGION_CAT)
	_check("mouse_region_exists", rn != null)
	_check("cat_region_exists", rc != null)
	if rn == null or rc == null:
		scene.free()
		return
	_check("mouse_region_layer_1", rn.navigation_layers == LAYER_MOUSE)
	_check("cat_region_layer_2", rc.navigation_layers == LAYER_CAT)
	_check("mouse_region_has_mesh", rn.navigation_mesh != null)
	_check("cat_region_has_mesh", rc.navigation_mesh != null)
	if rn.navigation_mesh != null:
		_check("mouse_mesh_polygons>0", rn.navigation_mesh.get_polygon_count() > 0)
		_check("mouse_mesh_radius", absf(rn.navigation_mesh.agent_radius - (mouse.capsule_radius + RADIUS_MARGIN)) < 1e-6)
		_check("mouse_mesh_climb", absf(rn.navigation_mesh.agent_max_climb - mouse.max_step_height) < 1e-6)
		print("VERIFY|mouse_mesh|polys=%d|radius=%.3f|height=%.3f|climb=%.3f|cell=%.3f|rmin=%.3f" % [
			rn.navigation_mesh.get_polygon_count(), rn.navigation_mesh.agent_radius,
			rn.navigation_mesh.agent_height, rn.navigation_mesh.agent_max_climb,
			rn.navigation_mesh.cell_size, rn.navigation_mesh.region_min_size
		])
	if rc.navigation_mesh != null:
		_check("cat_mesh_polygons>0", rc.navigation_mesh.get_polygon_count() > 0)
		_check("cat_mesh_radius", absf(rc.navigation_mesh.agent_radius - (cat.capsule_radius + RADIUS_MARGIN)) < 1e-6)
		_check("cat_mesh_climb", absf(rc.navigation_mesh.agent_max_climb - cat.max_step_height) < 1e-6)
		print("VERIFY|cat_mesh|polys=%d|radius=%.3f|height=%.3f|climb=%.3f|cell=%.3f|rmin=%.3f" % [
			rc.navigation_mesh.get_polygon_count(), rc.navigation_mesh.agent_radius,
			rc.navigation_mesh.agent_height, rc.navigation_mesh.agent_max_climb,
			rc.navigation_mesh.cell_size, rc.navigation_mesh.region_min_size
		])
	scene.free()


func _check(id: String, ok: bool) -> bool:
	if not ok:
		_fails += 1
	print("VERIFY|%s|%s" % [id, "OK" if ok else "FAIL"])
	return ok
