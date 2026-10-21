extends SceneTree
## T012 验收：导航可行性试验（分物种导航图 + 真实胶囊行走）
##
## 需求：`Docs/Tasks/T012.md`（总计划 §5「验证猫与鼠尺寸对应的导航/支持代理配置；NPC 可走其合法路线，猫不能进入鼠洞」）；
## 硬约束（`Docs/TechnicalDesign.md` §5、§6）：**导航面必须由两种实际胶囊验证**；
## **失败时禁止用瞬移伪装寻路成功**；`NavigationAgent3D` 用信号、失败不永久阻塞。
##
## 做法：① 两张落盘导航图的参数/结构断言；② **分层路径矩阵**（鼠层 layer 1 / 猫层 layer 2）；
##      ③ **真实 `AnimalBody` + `NavigationAgent3D` 沿路径走过去**（位置逐帧推进、0 重叠、不穿墙）。
## 注意：运行期改 navmesh 后同进程查询不可靠（T012 实测 600 帧仍空）→ 本测试用**落盘 .tres + 新进程**。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t012_navigation.gd' --quit-after 60000

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BODY := "res://scenes/characters/animal_body.tscn"
const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const NAV_MOUSE := "res://resources/nav/l_courtyard_mouse.tres"
const NAV_CAT := "res://resources/nav/l_courtyard_cat.tres"

const GROUP := "nav_source_courtyard"
const REGION_MOUSE := "NavRegion_Mouse"
const REGION_CAT := "NavRegion_Cat"
const LAYER_MOUSE := 1
const LAYER_CAT := 2

## 与生成器一致的烘焙参数（实测口径）
const CELL := 0.03
const REGION_MIN_SIZE := 0.02
const RADIUS_MARGIN := 0.01
const HEIGHT_MARGIN := 0.02

## 关卡几何（T011 已验收）
const HOLE_X := 26.5
const HOLE_HALF_W := 0.12
const BARRIER_Z_MIN := 18.5
const BARRIER_Z_MAX := 19.5
const BARRIER_TOP := 0.60
const BANK_X := -31.73
const BANK_GAP_HALF_W := 0.12
const BANK_Z_MIN := 6.0
const BANK_Z_MAX := 14.0

## 查询高度：取导航面之上（实测导航面 y = 地面 0.10 + 2×cell ≈ 0.14）
const QUERY_Y := 0.50
const NAV_READY_MAX_FRAMES := 400
const PROBE_FRAMES := 900
const ARRIVE_EPS := 0.70
const EPS := 0.02

var _checks := 0
var _fails := 0
var _world: Node3D = null
var _body: AnimalBody = null
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null
var _map: RID = RID()
var _nav_ready_frame := -1


func _initialize() -> void:
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig
	_assert("species_configs_loaded", "cat & mouse", str(_cat != null and _mouse != null),
		_cat != null and _mouse != null)

	var packed: PackedScene = load(LEVEL)
	_assert("level_loads", LEVEL, str(packed != null), packed != null)
	if packed == null:
		_finish()
		return
	_world = packed.instantiate() as Node3D
	_assert("level_root_is_node3d", "Node3D", str(_world != null), _world != null)
	if _world == null:
		_finish()
		return
	root.add_child(_world)
	await process_frame
	await process_frame

	_map = _world.get_world_3d().get_navigation_map()
	_assert("navigation_map_valid", "RID valid", str(_map), _map.is_valid())

	await _s1_resources()
	await _s2_mouse_layer()
	await _s3_cat_layer()
	await _s4_walk_probes()
	_finish()


# ---------------------------------------------------------------------------
# A 资源与配置
# ---------------------------------------------------------------------------

func _s1_resources() -> void:
	var nm_mouse := load(NAV_MOUSE) as NavigationMesh
	var nm_cat := load(NAV_CAT) as NavigationMesh
	_assert("mouse_navmesh_loads", NAV_MOUSE, str(nm_mouse != null), nm_mouse != null)
	_assert("cat_navmesh_loads", NAV_CAT, str(nm_cat != null), nm_cat != null)
	if nm_mouse == null or nm_cat == null:
		return

	for pair in [["mouse", nm_mouse, _mouse], ["cat", nm_cat, _cat]]:
		var tag: String = pair[0]
		var m: NavigationMesh = pair[1]
		var cfg: SpeciesConfig = pair[2]
		_assert_near("%s_mesh_agent_radius" % tag, cfg.capsule_radius + RADIUS_MARGIN, m.agent_radius, 1e-6)
		_assert_near("%s_mesh_agent_height" % tag, cfg.capsule_height() + HEIGHT_MARGIN, m.agent_height, 1e-6)
		_assert_near("%s_mesh_max_climb" % tag, cfg.max_step_height, m.agent_max_climb, 1e-6)
		_assert_near("%s_mesh_cell_size" % tag, CELL, m.cell_size, 1e-6)
		_assert_near("%s_mesh_cell_height" % tag, CELL, m.cell_height, 1e-6)
		_assert_near("%s_mesh_region_min_size" % tag, REGION_MIN_SIZE, m.region_min_size, 1e-6)
		_assert("%s_mesh_parsed_static_colliders" % tag, "STATIC_COLLIDERS(%d)" % NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS,
			"%d" % m.geometry_parsed_geometry_type,
			m.geometry_parsed_geometry_type == NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS)
		_assert("%s_mesh_collision_mask_1" % tag, "1", "%d" % m.geometry_collision_mask, m.geometry_collision_mask == 1)
		_assert("%s_mesh_source_groups" % tag, "GROUPS_WITH_CHILDREN",
			"%d" % m.geometry_source_geometry_mode,
			m.geometry_source_geometry_mode == NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN)
		_assert("%s_mesh_source_group_name" % tag, GROUP, m.geometry_source_group_name,
			m.geometry_source_group_name == GROUP)
		_assert("%s_mesh_has_polygons" % tag, "> 0", "%d" % m.get_polygon_count(), m.get_polygon_count() > 0)
		_assert("%s_mesh_has_vertices" % tag, "> 0", "%d" % m.get_vertices().size(), m.get_vertices().size() > 0)
		var area := _mesh_area(m)
		_assert("%s_mesh_area_plausible" % tag, "[500, 7000] m²（整块地面 80×80 = 6400）", "%.1f m²" % area,
			area >= 500.0 and area <= 7000.0)
		print("MEASURE|navmesh_%s|polys=%d|verts=%d|area=%.1f|radius=%.3f|height=%.3f|climb=%.3f|cell=%.3f|rmin=%.3f" % [
			tag, m.get_polygon_count(), m.get_vertices().size(), area, m.agent_radius, m.agent_height,
			m.agent_max_climb, m.cell_size, m.region_min_size
		])

	# 场景里的两个 region
	var rn := _world.get_node_or_null(REGION_MOUSE) as NavigationRegion3D
	var rc := _world.get_node_or_null(REGION_CAT) as NavigationRegion3D
	_assert("mouse_region_exists", REGION_MOUSE, str(rn), rn != null)
	_assert("cat_region_exists", REGION_CAT, str(rc), rc != null)
	if rn != null:
		_assert("mouse_region_layer_1", "1", "%d" % rn.navigation_layers, rn.navigation_layers == LAYER_MOUSE)
		_assert("mouse_region_mesh_is_nav_mouse", NAV_MOUSE, str(rn.navigation_mesh),
			rn.navigation_mesh != null and rn.navigation_mesh.get_polygon_count() == nm_mouse.get_polygon_count())
	if rc != null:
		_assert("cat_region_layer_2", "2", "%d" % rc.navigation_layers, rc.navigation_layers == LAYER_CAT)
		_assert("cat_region_mesh_is_nav_cat", NAV_CAT, str(rc.navigation_mesh),
			rc.navigation_mesh != null and rc.navigation_mesh.get_polygon_count() == nm_cat.get_polygon_count())

	# 结构证据（与路径查询互相独立）：导航面是否**覆盖**洞口 / 缝隙的中心
	var hole_center := Vector3(HOLE_X, 0.14, (BARRIER_Z_MIN + BARRIER_Z_MAX) * 0.5)
	var bank_center := Vector3(BANK_X, 0.14, (BANK_Z_MIN + BANK_Z_MAX) * 0.5)
	var mouse_hole_cover := _mesh_covers_point(nm_mouse, hole_center)
	var cat_hole_cover := _mesh_covers_point(nm_cat, hole_center)
	var mouse_bank_cover := _mesh_covers_point(nm_mouse, bank_center)
	var cat_bank_cover := _mesh_covers_point(nm_cat, bank_center)
	_assert("mouse_mesh_covers_hole_center", "树根洞里**有**导航面", str(mouse_hole_cover), mouse_hole_cover)
	_assert("cat_mesh_does_not_cover_hole_center", "树根洞里**没有**导航面", str(cat_hole_cover), not cat_hole_cover)
	_assert("mouse_mesh_covers_creek_gap_center", "溪缝里有导航面", str(mouse_bank_cover), mouse_bank_cover)
	_assert("cat_mesh_does_not_cover_creek_gap_center", "溪缝里没有导航面", str(cat_bank_cover), not cat_bank_cover)
	print("MEASURE|mesh_coverage|hole_center_mouse=%s|hole_center_cat=%s|creek_gap_mouse=%s|creek_gap_cat=%s" % [
		str(mouse_hole_cover), str(cat_hole_cover), str(mouse_bank_cover), str(cat_bank_cover)
	])

	# 几何分组（烘焙源）仍在
	var grouped := 0
	for ch in _world.get_children():
		var sb := ch as StaticBody3D
		if sb != null and sb.is_in_group(GROUP):
			grouped += 1
	_assert("nav_source_group_present", "≥ 15 个静态体", "%d" % grouped, grouped >= 15)

	# 地图格与导航面一致（不一致会产生 rasterization 警告）
	_assert_near("map_cell_matches_navmesh", CELL, NavigationServer3D.map_get_cell_size(_map), 1e-6)

	# 就绪等待：直到"庭院内鼠层能取到路径"
	var a := Vector3(0.0, QUERY_Y, 24.0)
	var b := Vector3(0.0, QUERY_Y, 12.0)
	for i in NAV_READY_MAX_FRAMES:
		await physics_frame
		NavigationServer3D.map_force_update(_map)
		if NavigationServer3D.map_get_path(_map, a, b, true, LAYER_MOUSE).size() > 0:
			_nav_ready_frame = i
			break
	_assert("navigation_becomes_ready", "0 ≤ frames < %d" % NAV_READY_MAX_FRAMES, "%d" % _nav_ready_frame,
		_nav_ready_frame >= 0)
	print("MEASURE|nav_ready|first_path_frame=%d|map_cell=%.3f|regions=%d" % [
		_nav_ready_frame, NavigationServer3D.map_get_cell_size(_map),
		NavigationServer3D.map_get_regions(_map).size()
	])


# ---------------------------------------------------------------------------
# B 鼠层（layer 1）
# ---------------------------------------------------------------------------

func _s2_mouse_layer() -> void:
	var flat := _query(Vector3(0.0, QUERY_Y, 24.0), Vector3(0.0, QUERY_Y, 12.0), LAYER_MOUSE)
	_assert("mouse_courtyard_path_exists", "> 0 点", "%d 点" % flat.size(), flat.size() > 0)
	_assert_near("mouse_courtyard_path_length", 12.0, _path_length(flat), 2.0)
	print("MEASURE|mouse_flat|points=%d|length=%.2f" % [flat.size(), _path_length(flat)])

	var hole := _query(Vector3(HOLE_X, QUERY_Y, BARRIER_Z_MAX + 4.0), Vector3(HOLE_X, QUERY_Y, BARRIER_Z_MIN - 4.0), LAYER_MOUSE)
	var hole_len := _path_length(hole)
	var crosses := _crosses_x_gap(hole, HOLE_X, HOLE_HALF_W + EPS, BARRIER_Z_MIN, BARRIER_Z_MAX)
	_assert("mouse_tree_hole_path_exists", "> 0 点", "%d 点" % hole.size(), hole.size() > 0)
	_assert("mouse_tree_hole_path_crosses_hole", "穿过洞口通道（|x−26.5| ≤ 0.14）", str(crosses), crosses)
	_assert("mouse_tree_hole_path_not_detour", "≤ 直距 9 m + 3 m", "%.2f m" % hole_len, hole_len <= 12.0)
	print("MEASURE|mouse_tree_hole|points=%d|length=%.2f|crosses_hole=%s" % [hole.size(), hole_len, str(crosses)])

	# ART05 实测：单段 A→B 查询在两条**近乎等长**的路线之间会随导航面重烤后的多边形顺序翻转
	# （穿缝 12.00 m vs 绕岸墙 B 东端 12.1x m）。接入巨石后真实翻到了绕行侧 —— 但缝本身仍可穿
	# （缝内航点 (−31.73, 10) 与南北两侧逐腿都连通）。能力断言不应依赖全局 tie-break，
	# 所以改成**经缝内航点逐腿查询**。
	var bank := _query_via(Vector3(BANK_X, QUERY_Y, BANK_Z_MAX + 2.0),
		Vector3(BANK_X, QUERY_Y, (BANK_Z_MIN + BANK_Z_MAX) * 0.5),
		Vector3(BANK_X, QUERY_Y, BANK_Z_MIN - 2.0), LAYER_MOUSE)
	var bank_len := _path_length(bank)
	var bank_crosses := _crosses_x_gap(bank, BANK_X, BANK_GAP_HALF_W + EPS, BANK_Z_MIN, BANK_Z_MAX)
	_assert("mouse_creek_gap_path_exists", "> 0 点", "%d 点" % bank.size(), bank.size() > 0)
	_assert("mouse_creek_gap_path_crosses_gap", "穿过缝隙（|x+31.73| ≤ 0.14）", str(bank_crosses), bank_crosses)
	_assert("mouse_creek_gap_path_not_detour", "≤ 直距 12 m + 3 m", "%.2f m" % bank_len, bank_len <= 15.0)
	print("MEASURE|mouse_creek_gap|points=%d|length=%.2f|crosses_gap=%s" % [bank.size(), bank_len, str(bank_crosses)])


# ---------------------------------------------------------------------------
# C 猫层（layer 2）：常规地面可行，洞/缝不穿
# ---------------------------------------------------------------------------

func _s3_cat_layer() -> void:
	var flat := _query(Vector3(-4.0, QUERY_Y, 24.0), Vector3(-7.0, QUERY_Y, 22.0), LAYER_CAT)
	_assert("cat_courtyard_path_exists", "> 0 点", "%d 点" % flat.size(), flat.size() > 0)
	_assert_near("cat_courtyard_path_length", 3.61, _path_length(flat), 1.5)
	print("MEASURE|cat_flat|points=%d|length=%.2f" % [flat.size(), _path_length(flat)])

	var hole := _query(Vector3(HOLE_X, QUERY_Y, BARRIER_Z_MAX + 4.0), Vector3(HOLE_X, QUERY_Y, BARRIER_Z_MIN - 4.0), LAYER_CAT)
	var hole_len := _path_length(hole)
	var crosses := _crosses_x_gap(hole, HOLE_X, HOLE_HALF_W + EPS, BARRIER_Z_MIN, BARRIER_Z_MAX)
	_assert("cat_never_paths_through_mouse_hole", "不穿过洞口通道", str(crosses), not crosses)
	if hole.size() > 0:
		_assert("cat_hole_path_is_long_detour", "≥ 直距 9 m + 8 m", "%.2f m" % hole_len, hole_len >= 17.0)
	else:
		_assert("cat_hole_path_absent_or_detour", "无路径 或 长绕行", "无路径（0 点）", true)
	print("MEASURE|cat_tree_hole|points=%d|length=%.2f|crosses_hole=%s|direct=9.00" % [hole.size(), hole_len, str(crosses)])

	var bank := _query(Vector3(BANK_X, QUERY_Y, BANK_Z_MAX + 2.0), Vector3(BANK_X, QUERY_Y, BANK_Z_MIN - 2.0), LAYER_CAT)
	var bank_len := _path_length(bank)
	var bank_crosses := _crosses_x_gap(bank, BANK_X, BANK_GAP_HALF_W + EPS, BANK_Z_MIN, BANK_Z_MAX)
	_assert("cat_never_paths_through_creek_gap", "不穿过缝隙", str(bank_crosses), not bank_crosses)
	if bank.size() > 0:
		# 岸墙只夹出一个 0.24 的"槽"，**槽两侧的地面是通的** → 猫会贴着墙外侧绕过去
		# （实测 12.17 m ≈ 直距 12 m）。所以这里**不写"必须长绕行"**，只要求它**不穿过槽**
		# （上一条已断言），并如实记录长度。
		_assert("cat_creek_gap_path_not_a_chokepoint", "直距 12 m ± 2 m（可绕墙外侧）", "%.2f m" % bank_len,
			absf(bank_len - 12.0) <= 2.0)
	else:
		_assert("cat_creek_gap_path_absent", "无路径也可接受", "无路径（0 点）", true)
	print("MEASURE|cat_creek_gap|points=%d|length=%.2f|crosses_gap=%s|direct=12.00" % [bank.size(), bank_len, str(bank_crosses)])

	# 屏障顶（0.60）在猫图上不应与地面"贴在一起"（无跳跃边）
	var top := _query(Vector3(30.0, QUERY_Y, 24.0), Vector3(30.0, BARRIER_TOP + 0.1, 19.0), LAYER_CAT)
	var top_crosses := _crosses_x_gap(top, 30.0, 0.15, BARRIER_Z_MIN, BARRIER_Z_MAX)
	_assert("cat_barrier_top_is_not_adjacent", "不落到屏障顶上（无跳跃边）", str(top_crosses), not top_crosses)
	print("MEASURE|cat_barrier_top|points=%d|length=%.2f|crosses_barrier_lane=%s" % [
		top.size(), _path_length(top), str(top_crosses)
	])


# ---------------------------------------------------------------------------
# D 真实胶囊沿路径行走（**禁止瞬移**）
# ---------------------------------------------------------------------------

func _s4_walk_probes() -> void:
	# P1 鼠：从屏障北侧走进洞、到南侧
	var r1 := await _walk("P1_mouse_nav_through_hole", _mouse, LAYER_MOUSE,
		Vector3(HOLE_X, 0.0, 21.5), Vector3(HOLE_X, 0.0, 16.5), PROBE_FRAMES)
	_assert("P1_mouse_reaches_target", "距离 ≤ %.2f" % ARRIVE_EPS, "%.3f m" % r1["end_dist"], r1["end_dist"] <= ARRIVE_EPS)
	_assert("P1_mouse_crossed_hole", "终点 z ≤ %.1f" % BARRIER_Z_MIN, "z=%.3f" % r1["end"].z, r1["end"].z <= BARRIER_Z_MIN)
	_assert("P1_mouse_never_collided", "0 重叠", "%d" % r1["overlaps"], r1["overlaps"] == 0)
	_assert("P1_mouse_stays_on_floor", "0 空中帧", "%d" % r1["airborne"], r1["airborne"] == 0)
	_assert("P1_mouse_y_stable", "max−min ≤ 0.02", "%.4f" % r1["y_span"], r1["y_span"] <= 0.02)
	_assert("P1_target_reachable_signal", "is_target_reachable = true", str(r1["reachable"]), r1["reachable"])
	_assert("P1_navigation_finished_signal", "navigation_finished（信号或 API）",
		"%s / %s" % [str(r1["finished"]), str(r1["nav_finished_api"])],
		r1["finished"] or r1["nav_finished_api"])

	# P2 猫：同一对端点 —— **不得从洞里钻过去**
	var r2 := await _walk("P2_cat_nav_to_hole", _cat, LAYER_CAT,
		Vector3(HOLE_X, 0.0, 21.5), Vector3(HOLE_X, 0.0, 16.5), PROBE_FRAMES)
	_assert("P2_cat_never_enters_hole_corridor", "全程 |x−26.5| ≤ 0.25 且 z∈[18.5,19.5] 的帧数 = 0",
		"%d 帧" % r2["frames_in_hole"], r2["frames_in_hole"] == 0)
	_assert("P2_cat_never_collided", "0 重叠", "%d" % r2["overlaps"], r2["overlaps"] == 0)
	_assert("P2_cat_stays_on_floor", "0 空中帧", "%d" % r2["airborne"], r2["airborne"] == 0)
	_assert("P2_cat_still_progressing_or_arrived", "移动距离 > 1 m（不卡死）", "%.2f m" % r2["moved"],
		r2["moved"] > 1.0)
	print("MEASURE|P2_cat|end=(%.3f, %.3f, %.3f)|end_dist=%.3f|moved=%.2f|path_len=%.2f|frames_in_hole=%d|reachable=%s" % [
		r2["end"].x, r2["end"].y, r2["end"].z, r2["end_dist"], r2["moved"], r2["nav_path_len"],
		r2["frames_in_hole"], str(r2["reachable"])
	])

	# P3 猫：庭院内正常寻路走到目标（证明猫图可用、代理能走）
	var r3 := await _walk("P3_cat_nav_courtyard", _cat, LAYER_CAT,
		Vector3(-4.0, 0.0, 24.0), Vector3(-7.0, 0.0, 22.0), 400)
	_assert("P3_cat_reaches_target", "距离 ≤ %.2f" % ARRIVE_EPS, "%.3f m" % r3["end_dist"], r3["end_dist"] <= ARRIVE_EPS)
	_assert("P3_cat_never_collided", "0 重叠", "%d" % r3["overlaps"], r3["overlaps"] == 0)
	_assert("P3_cat_finished_signal", "navigation_finished（信号或 API）",
		"%s / %s" % [str(r3["finished"]), str(r3["nav_finished_api"])],
		r3["finished"] or r3["nav_finished_api"])

	# P4 鼠：穿过溪边 0.24 缝
	var r4 := await _walk("P4_mouse_nav_through_creek_gap", _mouse, LAYER_MOUSE,
		Vector3(BANK_X, 0.0, 15.5), Vector3(BANK_X, 0.0, 4.5), PROBE_FRAMES)
	_assert("P4_mouse_reaches_target", "距离 ≤ %.2f" % ARRIVE_EPS, "%.3f m" % r4["end_dist"], r4["end_dist"] <= ARRIVE_EPS)
	_assert("P4_mouse_crossed_creek_gap", "终点 z ≤ %.1f" % BANK_Z_MIN, "z=%.3f" % r4["end"].z, r4["end"].z <= BANK_Z_MIN)
	_assert("P4_mouse_never_collided", "0 重叠", "%d" % r4["overlaps"], r4["overlaps"] == 0)
	_assert("P4_mouse_stays_on_floor", "0 空中帧", "%d" % r4["airborne"], r4["airborne"] == 0)
	_assert("P4_mouse_y_stable", "max−min ≤ 0.02", "%.4f" % r4["y_span"], r4["y_span"] <= 0.02)


## 让一个真实身体沿导航路径走到目标；逐帧记录位置/重叠/是否进洞通道
func _walk(tag: String, cfg: SpeciesConfig, layer: int, from_xz: Vector3, target_xz: Vector3, frames: int) -> Dictionary:
	_release_all()
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
		await process_frame
	_body = (load(BODY) as PackedScene).instantiate() as AnimalBody
	_body.species_config = cfg
	_body.player_controlled = true
	_world.add_child(_body)
	var spawn := Vector3(from_xz.x, 0.10 + cfg.capsule_half_height + 0.02, from_xz.z)
	_body.global_position = spawn
	_body.velocity = Vector3.ZERO
	_body.climb.reset_base()
	for i in 180:
		await physics_frame
		if _body.is_on_floor():
			break
	_body.climb.update_base_y()
	await _wait(5)

	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	agent.navigation_layers = layer
	agent.radius = cfg.capsule_radius
	agent.height = cfg.capsule_height()
	agent.path_desired_distance = 0.25
	agent.target_desired_distance = 0.25
	_body.add_child(agent)
	agent.set_navigation_map(_map)
	agent.target_position = Vector3(target_xz.x, 0.10 + cfg.capsule_half_height, target_xz.z)

	var finished := false
	agent.navigation_finished.connect(func() -> void: finished = true)

	var start: Vector3 = _body.global_position
	var ymin: float = start.y
	var ymax: float = start.y
	var airborne := 0
	var worst_overlap := 0
	var frames_in_hole := 0
	var reached_frame := -1
	var moved_total := 0.0
	var prev: Vector3 = start
	Input.action_press("move_forward")
	for i in frames:
		await physics_frame
		var p: Vector3 = _body.global_position
		moved_total += p.distance_to(prev)
		prev = p
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
		if not _body.is_on_floor():
			airborne += 1
		worst_overlap = maxi(worst_overlap, _overlaps_world(0.005))
		if absf(p.x - HOLE_X) <= 0.25 and p.z >= BARRIER_Z_MIN - 0.2 and p.z <= BARRIER_Z_MAX + 0.2:
			frames_in_hole += 1
		if p.distance_to(agent.target_position) <= ARRIVE_EPS and reached_frame < 0:
			reached_frame = i
		# 转向下一个路径点后前进
		var next := agent.get_next_path_position()
		var d := Vector3(next.x - p.x, 0.0, next.z - p.z)
		if d.length() > 0.01:
			_body.rotation.y = atan2(-d.x, -d.z)
		if agent.is_navigation_finished():
			break
		# 已到达后再走 60 帧，给 agent 机会发出 navigation_finished（信号/API 二选一断言）
		if reached_frame >= 0 and i >= reached_frame + 60:
			break
	Input.action_release("move_forward")
	await _wait(25)

	var end: Vector3 = _body.global_position
	var res := {
		"end": end,
		"end_dist": Vector2(end.x - target_xz.x, end.z - target_xz.z).length(),
		"moved": moved_total,
		"y_span": ymax - ymin,
		"airborne": airborne,
		"overlaps": worst_overlap,
		"frames_in_hole": frames_in_hole,
		"reachable": agent.is_target_reachable(),
		"finished": finished,
		"nav_finished_api": agent.is_navigation_finished(),
		"reach_frame": reached_frame,
		"nav_path_len": _path_length(agent.get_current_navigation_path()),
	}
	print("MEASURE|%s|from=(%.2f, %.2f)|target=(%.2f, %.2f)|end=(%.3f, %.3f, %.3f)|end_dist=%.3f|moved=%.2f|reach_frame=%d|y_span=%.4f|airborne=%d|overlaps=%d|nav_path_len=%.2f|finished=%s|reachable=%s" % [
		tag, from_xz.x, from_xz.z, target_xz.x, target_xz.z, end.x, end.y, end.z, res["end_dist"],
		moved_total, reached_frame, res["y_span"], airborne, worst_overlap, res["nav_path_len"],
		str(finished), str(agent.is_target_reachable())
	])
	agent.queue_free()
	return res


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _query(a: Vector3, b: Vector3, layer: int) -> PackedVector3Array:
	NavigationServer3D.map_force_update(_map)
	return NavigationServer3D.map_get_path(_map, a, b, true, layer)


func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total

## 分段查询：A→M→B 两腿拼接（去掉重复的接点）。用于"必须经过某处"的**能力**断言。
func _query_via(a: Vector3, m: Vector3, b: Vector3, layer: int) -> PackedVector3Array:
	var p1 := _query(a, m, layer)
	var p2 := _query(m, b, layer)
	if p1.is_empty() or p2.is_empty():
		return PackedVector3Array()
	var out := p1.duplicate()
	for i in range(1, p2.size()):
		out.append(p2[i])
	return out

## 路径是否在 (x_center ± half_w, z∈[z0,z1]) 这段"通道"里穿过
func _crosses_x_gap(path: PackedVector3Array, x_center: float, half_w: float, z0: float, z1: float) -> bool:
	for i in range(1, path.size()):
		var p0: Vector3 = path[i - 1]
		var p1: Vector3 = path[i]
		if (p0.z > z0) != (p1.z > z0) or (p0.z > z1) != (p1.z > z1):
			if absf(p1.x - x_center) <= half_w and p1.z >= z0 - 0.3 and p1.z <= z1 + 0.3:
				return true
	return false


func _mesh_area(m: NavigationMesh) -> float:
	var verts := m.get_vertices()
	var area := 0.0
	for i in m.get_polygon_count():
		var poly := m.get_polygon(i)
		if poly.size() < 3:
			continue
		var a: Vector3 = verts[poly[0]]
		for j in range(1, poly.size() - 1):
			var b: Vector3 = verts[poly[j]]
			var c: Vector3 = verts[poly[j + 1]]
			area += ((b - a).cross(c - a)).length() * 0.5
	return area


## 导航面是否覆盖某个点：XZ 在多边形内 **且** 多边形高度贴近该点高度
## （必须带高度：猫图会把 0.60 高的屏障顶面也烘出来，它在 XZ 上盖住了洞口 → 只查 XZ 会误判）
func _mesh_covers_point(m: NavigationMesh, p: Vector3) -> bool:
	var verts := m.get_vertices()
	for i in m.get_polygon_count():
		var poly := m.get_polygon(i)
		if poly.size() < 3:
			continue
		if not _point_in_poly_xz(verts, poly, p):
			continue
		var ysum := 0.0
		for k in poly.size():
			ysum += verts[poly[k]].y
		if absf(ysum / float(poly.size()) - p.y) <= 0.15:
			return true
	return false


func _point_in_poly_xz(verts: PackedVector3Array, poly: PackedInt32Array, p: Vector3) -> bool:
	var inside := false
	var n := poly.size()
	for i in n:
		var a: Vector3 = verts[poly[i]]
		var b: Vector3 = verts[poly[(i + 1) % n]]
		if (a.z > p.z) != (b.z > p.z) \
				and p.x < (b.x - a.x) * (p.z - a.z) / (b.z - a.z) + a.x:
			inside = not inside
	return inside


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "jump", "interact", "pounce"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _overlaps_world(shrink: float) -> int:
	var cap := _body.shape_node.shape as CapsuleShape3D
	var probe := CapsuleShape3D.new()
	probe.radius = maxf(0.001, cap.radius - shrink)
	probe.height = maxf(0.002, cap.height - shrink * 2.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = Transform3D(Basis(), _body.global_position)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.exclude = [_body.get_rid()]
	return _body.get_world_3d().direct_space_state.intersect_shape(params, 4).size()


func _assert(id: String, expected: String, actual: String, ok: bool) -> bool:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])
	return ok


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	_assert(id, "%.4f (±%.4f)" % [expected, eps], "%.4f" % actual, absf(expected - actual) <= eps)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
