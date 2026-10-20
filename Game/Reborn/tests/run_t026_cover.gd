extends SceneTree
## T026 老鼠藏身与掩体规则 断言
##
## 覆盖（`Docs/Tasks/T026.md` §4；数值只读 `Docs/Parameters.md` 第 71/73 行）：
##   A 数据与接口（草丛可见性系数 / 鼠洞标记 / `cover_factor_at` 取最小 / 鼠 AI 的躲藏参数 / "停在洞外"的数值前提）
##   B **草丛只降低可见性**（视觉对照 / 0.4 乘数边界 / **不改移动** / **不改攻击遮挡** / 非实体）
##   C **鼠洞阻止猫进入**（**按层**的跨墙路由 / `reachable()` / 猫的路径终点 / 物理推：猫撞不进去、鼠钻得进去）
##   D **躲藏不凭空恢复全部资源**（不上升 / 不跳变 / 速率同量级 / 出洞连续）
##   E 集成（真实关卡：猫全程在洞外 + 账本不变 + 无调试节点）
## 注：`NavigationServer3D.map_get_closest_point(map, p)` 在 4.7.2 **不带导航层**（已用 `--doctool` 核对
##     `NavigationServer3D.xml`）；猫与鼠共用同一张世界地图 RID → 判"能不能进洞"必须用带层的 `map_get_path()`。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t026_cover.gd' --quit-after 300000
## 包内复验（只能用编辑器二进制 + --main-pack）：
##   & '<godot_console.exe>' --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
##       --script 'res://tests/run_t026_cover.gd' --quit-after 300000

const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"
const BODY := "res://scenes/characters/animal_body.tscn"
const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const MAIN := "res://scenes/core/main.tscn"

const EPS := 1e-3
const ARENA := 40.0
const CAT_Y := 0.25
const MOUSE_Y := 0.10
const SPAWN_FRAMES := 12
const COVER_FACTOR := 0.4        # Parameters.md 第 73 行
const HOLE_RADIUS := 0.30        # 关卡 HideSpot_RootHole 的 metadata/radius
const HOLE_INNER_TOL := 0.10     # "洞里有导航面吗"的容差
const NAV_LAYER_MOUSE := 1
const NAV_LAYER_CAT := 2

var _checks := 0
var _fails := 0
var _cat_cfg: SpeciesConfig = null
var _mouse_cfg: SpeciesConfig = null
var _wd: Node = null
var _world: Node3D = null
var _cat: AnimalBody = null
var _cat_ai: CatAI = null
var _mouse: AnimalBody = null
var _mouse_ai: MouseAI = null
var _extras: Array[Node] = []
var _wall_normal_source := "fallback"


func _initialize() -> void:
	print("TEST|run_t026_cover|engine=%s" % Engine.get_version_info().string)
	_cat_cfg = load(CAT) as SpeciesConfig
	_mouse_cfg = load(MOUSE) as SpeciesConfig
	_wd = root.get_node_or_null("WorldDirector")
	await _section_a_data()
	await _section_b_cover_vision_only()
	await _section_c_hole_blocks_cat()
	await _section_d_hiding_resources()
	await _section_e_integration()
	_finish()


# ---------------------------------------------------------------------------
# A 数据与接口
# ---------------------------------------------------------------------------

func _section_a_data() -> void:
	print("---- A 数据与接口 ----")
	_assert("A_cat_cfg", "非 null", str(_cat_cfg != null), _cat_cfg != null)
	_assert("A_mouse_cfg", "非 null", str(_mouse_cfg != null), _mouse_cfg != null)
	if _cat_cfg == null or _mouse_cfg == null:
		return
	# 真实关卡的数据（T011 口径）
	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	_assert("A_level_loads", "Node3D", str(level != null), level != null)
	if level == null:
		return
	root.add_child(level)
	await _advance_frames(6)

	var covers: Array[Node] = []
	for n in get_nodes_in_group(&"cover_volumes"):
		covers.append(n)
	var cover_nodes := 0
	var other_nodes := 0
	var all_areas := true
	for n in covers:
		if not (n is Area3D):
			all_areas = false
		var f := float(n.get_meta("visibility_factor", -1.0))
		if absf(f - COVER_FACTOR) < 1e-6:
			cover_nodes += 1
		else:
			other_nodes += 1
	_assert("A1_cover_group_nonempty", "≥ 1", str(covers.size()), covers.size() >= 1)
	_assert("A1_cover_factor_nodes", "≥ 1", str(cover_nodes), cover_nodes >= 1)
	# 草丛体量**只**声明 0.4：`cover_volumes` 里不该混进"开阔 1.0"（开阔是默认值，见下一条）
	_assert("A1_cover_only_lower_visibility", "0", str(other_nodes), other_nodes == 0)
	_assert("A1_all_areas", "全是 Area3D", str(all_areas), all_areas)
	print("MEASURE|a1|cover_volumes=%d|factor_0_4=%d|other=%d" % [covers.size(), cover_nodes, other_nodes])
	# "开阔 = 1.0" 在关卡里由 `danger_zones`（role=open_exposure）声明；`Perception.cover_factor_at()`
	# 只读 `cover_volumes`，草丛外即默认 1.0 → 两者语义一致（T026 D2）
	var exposures := 0
	for n in get_nodes_in_group(&"danger_zones"):
		if String(n.get_meta("role", "")) == "open_exposure" \
				and absf(float(n.get_meta("visibility_factor", -1.0)) - 1.0) < 1e-6:
			exposures += 1
	_assert("A1_exposure_zone_declared", "≥ 1", str(exposures), exposures >= 1)
	if covers.size() > 0:
		_assert("A1_cover_layer_zero", "0（不参与物理查询）", str((covers[0] as CollisionObject3D).collision_layer),
			(covers[0] as CollisionObject3D).collision_layer == 0)
		_assert("A1_cover_has_shape", "true", str(_has_cover_shape(covers[0])), _has_cover_shape(covers[0]))

	var hole: Node3D = null
	for n in get_nodes_in_group(&"hide_spots"):
		if n is Node3D and n.has_meta("kind") and String(n.get_meta("kind")) == "mouse_hole":
			hole = n as Node3D
			break
	_assert("A2_hole_found", "非 null", str(hole != null), hole != null)
	if hole != null:
		_assert("A2_hole_radius", "%.2f" % HOLE_RADIUS, "%.2f" % float(hole.get_meta("radius", -1.0)),
			absf(float(hole.get_meta("radius", -1.0)) - HOLE_RADIUS) < EPS)
		_assert("A2_hole_species", "Mouse", String(hole.get_meta("species", "")),
			String(hole.get_meta("species", "")) == "Mouse")
	level.queue_free()
	await _advance_frames(3)

	# `cover_factor_at`：草丛内 0.4 / 草丛外 1.0 / 重叠取最小
	await _fresh_arena({"with_cat": true})
	if _cat == null or _cat.perception == null:
		return
	_add_cover(_cat.global_position + Vector3(0.0, 0.0, -2.0), Vector3(1.0, 1.0, 1.0), 0.6)
	_add_cover(_cat.global_position + Vector3(0.0, 0.0, -2.0), Vector3(1.0, 1.0, 1.0), COVER_FACTOR)
	await _advance_frames(4)
	var inside := _cat.perception.cover_factor_at(_cat.global_position + Vector3(0.0, 0.0, -2.0))
	var outside := _cat.perception.cover_factor_at(_cat.global_position + Vector3(0.0, 0.0, -6.0))
	_assert("A3_inside_overlap_min", "%.2f（取最小）" % COVER_FACTOR, "%.2f" % inside, absf(inside - COVER_FACTOR) < EPS)
	_assert("A3_outside_one", "1.00", "%.2f" % outside, absf(outside - 1.0) < EPS)
	await _fresh_arena({"with_cat": true})
	_add_cover(_cat.global_position + Vector3(0.0, 0.0, -2.0), Vector3(1.0, 1.0, 1.0), COVER_FACTOR)
	await _advance_frames(4)
	_assert("A3_single_cover", "%.2f" % COVER_FACTOR,
		"%.2f" % _cat.perception.cover_factor_at(_cat.global_position + Vector3(0.0, 0.0, -2.0)),
		absf(_cat.perception.cover_factor_at(_cat.global_position + Vector3(0.0, 0.0, -2.0)) - COVER_FACTOR) < EPS)

	# 鼠 AI 的躲藏参数（第 71 行）+ 猫的"停在洞外"数值前提
	await _fresh_arena({"with_mouse": true, "mouse_ai": true})
	if _mouse_ai == null:
		_assert("A4_mouse_ai_built", "非 null", "<null>", false)
		return
	_assert("A4_hidden_hold_4", "4.0", "%.2f" % _mouse_ai.hidden_hold_time, absf(_mouse_ai.hidden_hold_time - 4.0) < EPS)
	_assert("A4_immediate_flee_1_8", "1.80", "%.2f" % _mouse_ai.immediate_flee_range,
		absf(_mouse_ai.immediate_flee_range - 1.80) < EPS)
	_assert("A4_flee_timeout_3", "3.0", "%.2f" % _mouse_ai.flee_timeout, absf(_mouse_ai.flee_timeout - 3.0) < EPS)
	_assert("A4_hidden_count_query", "true", str(_mouse_ai.has_method("hidden_count")), _mouse_ai.has_method("hidden_count"))
	_assert("A4_flee_kind_query", "true", str(_mouse_ai.has_method("flee_kind")), _mouse_ai.has_method("flee_kind"))
	await _fresh_arena({"with_cat": true, "cat_ai": true})
	if _cat_ai == null:
		_assert("A5_cat_ai_built", "非 null", "<null>", false)
		return
	_assert("A5_hole_search_radius_outside", "≥ %.2f" % HOLE_RADIUS, "%.2f" % _cat_ai.hole_search_radius,
		_cat_ai.hole_search_radius >= HOLE_RADIUS - EPS)
	_assert("A5_search_arrive_radius_outside", "≥ %.2f" % HOLE_RADIUS, "%.2f" % _cat_ai.search_arrive_radius,
		_cat_ai.search_arrive_radius >= HOLE_RADIUS - EPS)


func _has_cover_shape(node: Node) -> bool:
	for c in node.get_children():
		var cs := c as CollisionShape3D
		if cs != null and cs.shape != null and (cs.shape is BoxShape3D or cs.shape is SphereShape3D):
			return true
	return false


# ---------------------------------------------------------------------------
# B 草丛只降低可见性
# ---------------------------------------------------------------------------

func _section_b_cover_vision_only() -> void:
	print("---- B 草丛只降低可见性 ----")
	# B1/B2 视觉对照：同一距离 4.5 m（> 9.0 × 0.4 = 3.6）→ 草丛内看不见、草丛外看得见
	await _fresh_arena({"with_cat": true})
	if _cat == null or _cat.perception == null:
		return
	var grass_at := _front(4.5)
	_add_cover(grass_at, Vector3(2.0, 1.0, 2.0), COVER_FACTOR)
	_place_mouse(Vector3(grass_at.x, MOUSE_Y, grass_at.z))
	await _advance_frames(6)
	_assert("B1_in_grass_cover_factor", "%.2f" % COVER_FACTOR,
		"%.2f" % _cat.perception.cover_factor_at(_mouse.global_position),
		absf(_cat.perception.cover_factor_at(_mouse.global_position) - COVER_FACTOR) < EPS)
	_assert("B1_in_grass_invisible_at_4_5", "false（4.5 > 3.6）", str(_cat.perception.is_threat_visible()),
		not _cat.perception.is_threat_visible())
	await _fresh_arena({"with_cat": true})
	_place_mouse(_front(4.5))
	await _advance_frames(6)
	_assert("B1_open_visible_at_4_5", "true", str(_cat.perception.is_threat_visible()),
		_cat.perception.is_threat_visible())

	# B2 0.4 乘数边界：草丛内 3.0 m 可见（< 3.6）、草丛内 3.9 m 不可见（> 3.6）
	await _fresh_arena({"with_cat": true})
	var g3 := _front(3.0)
	_add_cover(g3, Vector3(1.6, 1.0, 1.6), COVER_FACTOR)
	_place_mouse(Vector3(g3.x, MOUSE_Y, g3.z))
	await _advance_frames(6)
	_assert("B2_in_grass_visible_at_3_0", "true（3.0 < 3.6）", str(_cat.perception.is_threat_visible()),
		_cat.perception.is_threat_visible())
	await _fresh_arena({"with_cat": true})
	var g4 := _front(3.9)
	_add_cover(g4, Vector3(1.6, 1.0, 1.6), COVER_FACTOR)
	_place_mouse(Vector3(g4.x, MOUSE_Y, g4.z))
	await _advance_frames(6)
	_assert("B2_in_grass_invisible_at_3_9", "false（3.9 > 3.6）", str(_cat.perception.is_threat_visible()),
		not _cat.perception.is_threat_visible())

	# B3 不改移动：鼠/猫在草丛体量里直走 1 s
	await _fresh_arena({"with_cat": true})
	_add_cover(_cat.global_position + Vector3(0.0, 0.0, -3.0), Vector3(4.0, 1.0, 8.0), COVER_FACTOR)
	await _advance_frames(4)
	var cat_from := _cat.global_position
	_cat.move_intent = Vector2(0.0, -1.0)
	await _run_seconds(1.0)
	_cat.move_intent = Vector2.ZERO
	var cat_moved := Vector2(_cat.global_position.x - cat_from.x, _cat.global_position.z - cat_from.z).length()
	_assert("B3_cat_moves_through_grass", "≥ 0.6 m", "%.3f m" % cat_moved, cat_moved >= 0.6)
	_assert("B3_cat_inside_grass", "%.2f" % COVER_FACTOR,
		"%.2f" % _cat.perception.cover_factor_at(_cat.global_position),
		absf(_cat.perception.cover_factor_at(_cat.global_position) - COVER_FACTOR) < EPS)

	await _fresh_arena({"with_mouse": true})
	_add_cover(_mouse.global_position + Vector3(0.0, 0.0, -2.0), Vector3(4.0, 1.0, 6.0), COVER_FACTOR)
	await _advance_frames(4)
	var mouse_from := _mouse.global_position
	_mouse.move_intent = Vector2(0.0, -1.0)
	await _run_seconds(1.0)
	_mouse.move_intent = Vector2.ZERO
	var mouse_moved := Vector2(_mouse.global_position.x - mouse_from.x, _mouse.global_position.z - mouse_from.z).length()
	_assert("B3_mouse_moves_through_grass", "≥ 0.6 m", "%.3f m" % mouse_moved, mouse_moved >= 0.6)

	# B4 不改攻击遮挡：草丛在猫与鼠之间 → 不算遮挡，攻击照样命中
	await _fresh_arena({"with_cat": true})
	_place_mouse(_front(0.5))
	_add_cover(_cat.global_position + Vector3(0.0, 0.0, -0.25), Vector3(1.4, 1.0, 0.2), COVER_FACTOR)
	await _advance_frames(6)
	if _cat.attack == null:
		_assert("B4_attack_component", "非 null", "<null>", false)
		return
	_assert("B4_grass_between_has_factor", "%.2f" % COVER_FACTOR,
		"%.2f" % _cat.perception.cover_factor_at(_cat.global_position + Vector3(0.0, 0.0, -0.25)),
		absf(_cat.perception.cover_factor_at(_cat.global_position + Vector3(0.0, 0.0, -0.25)) - COVER_FACTOR) < EPS)
	_assert("B4_grass_not_occluding", "false（草丛不算遮挡）", str(_cat.attack.occluded(_mouse)),
		not _cat.attack.occluded(_mouse))
	var hp_before: float = _mouse.survival.state.health
	var started := _cat.request_attack()
	_assert("B4_start_ok", "true", str(started), started)
	await _run_seconds(1.2, func() -> bool: return _cat.attack.hit_count >= 1)
	_assert("B4_hit_through_grass", "1", str(_cat.attack.hit_count), _cat.attack.hit_count == 1)
	_assert("B4_hp_65", "%.1f" % (hp_before - 35.0), "%.1f" % _mouse.survival.state.health,
		absf(_mouse.survival.state.health - (hp_before - 35.0)) <= 0.05)
	# 对照：真墙在同一位置会挡住
	var wall := _add_box(_world, "WallB4", Vector3(1.4, 1.0, 0.2), _cat.global_position + Vector3(0.0, 0.5, -0.25))
	await _advance_frames(4)
	_assert("B4_wall_occludes", "true（真墙算遮挡）", str(_cat.attack.occluded(_mouse)), _cat.attack.occluded(_mouse))
	wall.queue_free()
	await _advance_frames(2)

	# B5 草丛非实体
	for n in get_nodes_in_group(&"cover_volumes"):
		var co := n as CollisionObject3D
		if co != null:
			_assert("B5_cover_layer_zero_%s" % String(n.name), "0", str(co.collision_layer), co.collision_layer == 0)
	_assert("B5_mouse_collision_layer_is_animal", "2", str(_mouse.collision_layer), _mouse.collision_layer == 2)


# ---------------------------------------------------------------------------
# C 鼠洞阻止猫进入
# ---------------------------------------------------------------------------

func _section_c_hole_blocks_cat() -> void:
	print("---- C 鼠洞阻止猫进入 ----")
	await _fresh_level()
	if _mouse == null or _mouse_ai == null or _cat_ai == null:
		return
	var hole := _hole_marker()
	if hole == null:
		_assert("C_hole_found", "非 null", "<null>", false)
		return
	var hole_point: Vector3 = _cat_ai.hide_spot_point(hole)
	var hole_radius: float = _cat_ai.hide_spot_radius(hole)
	_assert("C_hole_radius", "%.2f" % HOLE_RADIUS, "%.2f" % hole_radius, absf(hole_radius - HOLE_RADIUS) < EPS)

	var cat_map := _cat_ai.agent.get_navigation_map()
	var mouse_map := _mouse_ai.agent.get_navigation_map()
	_assert("C_cat_map_valid", "true", str(cat_map.is_valid()), cat_map.is_valid())
	_assert("C_mouse_map_valid", "true", str(mouse_map.is_valid()), mouse_map.is_valid())
	if not cat_map.is_valid() or not mouse_map.is_valid():
		return
	var iter_cat: int = NavigationServer3D.map_get_iteration_id(cat_map)
	var iter_mouse: int = NavigationServer3D.map_get_iteration_id(mouse_map)
	_assert("C_cat_map_synced", "> 0", str(iter_cat), iter_cat > 0)
	_assert("C_mouse_map_synced", "> 0", str(iter_mouse), iter_mouse > 0)

	# --- 导航层证据 ---
	# `map_get_closest_point(map, p)` **不带导航层**（见文件头注），对猫会把"鼠标层洞面"上的点当最近点
	# （实测 0.04 m）→ 不能用它判"猫能不能进洞"。判据改用**按层的** `map_get_path()`：
	# 从墙一侧 2 m 走到另一侧 2 m，看路由是否穿过洞口。
	_assert("C_map_shared_one_world", "同一张世界地图（层区分物种）", str(cat_map == mouse_map), cat_map == mouse_map)
	var wall_normal := _wall_normal(hole_point)
	_assert("C_wall_normal_source", "lintel（关卡 RootBarrier 墙）", _wall_normal_source, _wall_normal_source == "lintel")
	_assert("C_wall_normal_horizontal", "|y| < 0.01", "%.4f" % wall_normal.y, absf(wall_normal.y) < 0.01)
	var closest_cat: Vector3 = NavigationServer3D.map_get_closest_point(cat_map, hole_point)
	var closest_mouse: Vector3 = NavigationServer3D.map_get_closest_point(mouse_map, hole_point)
	print("MEASURE|c_nav|layerblind_cat=%.3f|layerblind_mouse=%.3f|hole=%s|normal=%s" % [
		closest_cat.distance_to(hole_point), closest_mouse.distance_to(hole_point), str(hole_point), str(wall_normal)])
	# 前提：两个端点必须**真的铺在猫的层上**，否则下面"猫绕远/无路"就是假结论
	var side_out := hole_point + wall_normal * 2.0
	var side_far := hole_point - wall_normal * 2.0
	var snap_out := _snap_on_layer(cat_map, side_out, NAV_LAYER_CAT)
	var snap_far := _snap_on_layer(cat_map, side_far, NAV_LAYER_CAT)
	_assert("C1d_cat_layer_covers_out", "≤ 0.60 m", "%.3f m" % snap_out.distance_to(side_out),
		snap_out.distance_to(side_out) <= 0.60)
	_assert("C1e_cat_layer_covers_far", "≤ 0.60 m", "%.3f m" % snap_far.distance_to(side_far),
		snap_far.distance_to(side_far) <= 0.60)
	# C1/C2 跨墙路由：猫不穿洞、鼠穿洞
	var path_cat: PackedVector3Array = NavigationServer3D.map_get_path(cat_map, snap_out, snap_far, true, NAV_LAYER_CAT)
	var path_mouse: PackedVector3Array = NavigationServer3D.map_get_path(cat_map, snap_out, snap_far, true, NAV_LAYER_MOUSE)
	var cat_min := _path_min_dist(path_cat, hole_point)
	var mouse_min := _path_min_dist(path_mouse, hole_point)
	var cat_len := _path_length(path_cat)
	var mouse_len := _path_length(path_mouse)
	var straight := snap_out.distance_to(snap_far)
	print("MEASURE|c1_route|straight=%.2f|cat_pts=%d|cat_len=%.2f|cat_min_to_hole=%.3f|mouse_pts=%d|mouse_len=%.2f|mouse_min_to_hole=%.3f" % [
		straight, path_cat.size(), cat_len, cat_min, path_mouse.size(), mouse_len, mouse_min])
	_assert("C1_cat_route_avoids_hole", "≥ %.2f m" % hole_radius, "%.3f m" % cat_min, cat_min >= hole_radius - EPS)
	_assert("C2_mouse_route_through_hole", "< %.2f m" % hole_radius, "%.3f m" % mouse_min, mouse_min < hole_radius)
	_assert("C1b_cat_route_detours_or_none", "0 点 或 > %.1f m" % (straight * 1.5),
		"%d 点 / %.2f m" % [path_cat.size(), cat_len], path_cat.size() <= 1 or cat_len > straight * 1.5)
	_assert("C2b_mouse_route_nearly_straight", "≤ %.1f m" % (straight * 1.4), "%.2f m" % mouse_len,
		mouse_len <= straight * 1.4)

	# C3 AI 侧可达性
	var cat_reach: bool = _cat_ai.reachable(hole_point)
	var mouse_reach: bool = _mouse_ai.reachable(hole_point)
	_assert("C3_cat_cannot_reach_hole", "false", str(cat_reach), not cat_reach)
	_assert("C3_mouse_can_reach_hole", "true", str(mouse_reach), mouse_reach)

	# C4 猫的路径终点不在洞里
	var from: Vector3 = _cat.global_position
	var path: PackedVector3Array = NavigationServer3D.map_get_path(cat_map, from, hole_point, true, NAV_LAYER_CAT)
	_assert("C4_cat_path_nonempty", "≥ 1", str(path.size()), path.size() >= 1)
	if path.size() >= 1:
		var end_d := path[path.size() - 1].distance_to(hole_point)
		print("MEASURE|c4|path_points=%d|end_to_hole=%.3f" % [path.size(), end_d])
		_assert("C4_cat_path_ends_outside", "> %.2f m" % HOLE_INNER_TOL, "%.3f m" % end_d, end_d > HOLE_INNER_TOL)

	# C7 数值前提（运行时）
	_assert("C7_hole_search_radius_outside", "≥ %.2f" % hole_radius, "%.2f" % _cat_ai.hole_search_radius,
		_cat_ai.hole_search_radius >= hole_radius - EPS)
	_assert("C7_search_arrive_radius_outside", "≥ %.2f" % hole_radius, "%.2f" % _cat_ai.search_arrive_radius,
		_cat_ai.search_arrive_radius >= hole_radius - EPS)

	# C5 物理推：猫沿洞轴朝洞口撞 1.5 s，全程停在洞外
	# （夹具纪律：沿**墙法线**摆位；`_approach_dir` 那条"朝猫出生点"的轴与墙平行，会把身体插进墙里 → 假通过）
	_cat.ai_enabled = false
	_cat.global_position = _push_start(side_out, CAT_Y)
	await _advance_frames(SPAWN_FRAMES)
	var cat_from := _cat.global_position
	var min_cat := INF
	var t0 := _now()
	while _now() - t0 < 1.5:
		_push_towards(_cat, hole_point)
		await physics_frame
		min_cat = minf(min_cat, _cat.global_position.distance_to(hole_point))
	_cat.move_intent = Vector2.ZERO
	await _advance_frames(4)
	var final_cat := _cat.global_position.distance_to(hole_point)
	var cat_travel := Vector2(_cat.global_position.x - cat_from.x, _cat.global_position.z - cat_from.z).length()
	print("MEASURE|c5|min_cat=%.3f|final_cat=%.3f|travel=%.3f|radius=%.2f" % [min_cat, final_cat, cat_travel, hole_radius])
	# 夹具守卫：**确实朝洞口走了**，否则"没进洞"只是空话
	_assert("C5_setup_cat_travels", "≥ 0.50 m", "%.3f m" % cat_travel, cat_travel >= 0.50)
	_assert("C5_cat_never_inside", "≥ %.2f m" % hole_radius, "%.3f m" % min_cat, min_cat >= hole_radius - EPS)
	_assert("C5_cat_stops_outside", "≥ %.2f m" % hole_radius, "%.3f m" % final_cat, final_cat >= hole_radius - EPS)
	# C6 物理推：同一动作，鼠要能钻进去
	_mouse.ai_enabled = false
	_mouse.global_position = _push_start(side_out, MOUSE_Y)
	await _advance_frames(SPAWN_FRAMES)
	var mouse_from := _mouse.global_position
	var min_mouse := INF
	var t1 := _now()
	while _now() - t1 < 2.5:
		_push_towards(_mouse, hole_point)
		await physics_frame
		min_mouse = minf(min_mouse, _mouse.global_position.distance_to(hole_point))
	_mouse.move_intent = Vector2.ZERO
	await _advance_frames(4)
	var mouse_travel := Vector2(_mouse.global_position.x - mouse_from.x, _mouse.global_position.z - mouse_from.z).length()
	print("MEASURE|c6|min_mouse=%.3f|travel=%.3f|radius=%.2f" % [min_mouse, mouse_travel, hole_radius])
	_assert("C6_setup_mouse_travels", "≥ 0.50 m", "%.3f m" % mouse_travel, mouse_travel >= 0.50)
	_assert("C6_mouse_can_enter", "< %.2f m" % hole_radius, "%.3f m" % min_mouse, min_mouse < hole_radius)


# ---------------------------------------------------------------------------
# D 躲藏不凭空恢复全部资源
# ---------------------------------------------------------------------------

func _section_d_hiding_resources() -> void:
	print("---- D 躲藏不凭空恢复全部资源 ----")
	await _fresh_level()
	if _mouse == null or _mouse_ai == null:
		return
	var hole := _hole_marker()
	if hole == null:
		return
	var hole_point: Vector3 = _mouse_ai.hide_spot_point(hole)
	# 鼠放在洞口**外** 2.5 m（沿洞轴/墙法线摆位，别插进墙里），猫身体放在鼠身后 1.2 m
	var dir := _wall_normal(hole_point)
	_cat.ai_enabled = false
	_mouse.ai_enabled = false
	_mouse.global_position = _push_start(hole_point + dir * 2.5, MOUSE_Y)
	await _advance_frames(SPAWN_FRAMES)
	_cat.global_position = _push_start(_mouse.global_position + dir * 1.2, CAT_Y)
	await _advance_frames(6)
	# 让鼠**面朝**猫：威胁在背后时鼠的感知看不见 → 永远不会 FLEE（会让本段退化成空断言）
	_mouse.look_at(_cat.global_position, Vector3.UP)
	await _advance_frames(2)
	_assert("D_setup_threat_visible", "true（鼠看得见猫）", str(_mouse.perception.is_threat_visible()),
		_mouse.perception.is_threat_visible())
	# 先记一段 EXPLORE 期间的资源速率（基线）
	var base := _mouse.survival.state.duplicate_state()
	var base_t := _now()
	await _run_seconds(2.0)
	var base_dt := _now() - base_t
	var explore_rate := (base.hunger - _mouse.survival.state.hunger) / maxf(0.01, base_dt)
	print("MEASURE|d_base|explore_hunger_rate=%.4f|dt=%.2f" % [explore_rate, base_dt])
	_assert("D_baseline_rate_positive", "> 0", "%.4f" % explore_rate, explore_rate > 0.0)

	# 让鼠真的逃进洞（猫 AI 关着避免追打；感知挂在**身体**上，不依赖 AI → 看见威胁 → FLEE → HIDDEN）
	_mouse.ai_enabled = true
	await _advance_frames(4)
	_mouse_ai = _mouse.ai as MouseAI
	if _mouse_ai == null:
		_assert("D_mouse_ai_rebuilt", "非 null", "<null>", false)
		return
	var mai: MouseAI = _mouse_ai
	var hid := await _run_seconds(12.0, func() -> bool: return is_instance_valid(mai) and mai.state_id() == &"hidden")
	await _advance_frames(4)
	_assert("D_reached_hidden", "hidden（%.2f s）" % hid, str(mai.state_id()) if is_instance_valid(mai) else "<freed>",
		is_instance_valid(mai) and mai.state_id() == &"hidden")
	_assert("D_hidden_count_1", "≥ 1", str(mai.hidden_count()) if is_instance_valid(mai) else "<freed>",
		is_instance_valid(mai) and mai.hidden_count() >= 1)
	_assert("D_hidden_at_hole", "< %.2f m" % HOLE_RADIUS, "%.3f m" % _mouse.global_position.distance_to(hole_point),
		_mouse.global_position.distance_to(hole_point) < HOLE_RADIUS)
	_assert("D_flee_kind_set", "hide", str(mai.flee_kind()) if is_instance_valid(mai) else "<freed>",
		is_instance_valid(mai) and mai.flee_kind() == &"hide")

	# D1/D2/D5 躲藏期间采样 2.5 s
	var h0: float = _mouse.survival.state.hunger
	var t0: float = _mouse.survival.state.thirst
	var hp0: float = _mouse.survival.state.health
	var max_stamina := 0.0
	var max_stamina_step := 0.0
	var prev_stamina: float = _mouse.survival.state.stamina
	var pos0 := _mouse.global_position
	var dt_sum := 0.0
	var frames := 0
	var last_world := _now()
	var max_hunger := h0
	var max_thirst := t0
	var max_health := hp0
	while _now() - t0 < 2.5 and is_instance_valid(mai) and mai.state_id() == &"hidden":
		await physics_frame
		var now := _now()
		var dt := now - last_world
		last_world = now
		dt_sum += dt
		frames += 1
		var st: float = _mouse.survival.state.stamina
		max_stamina_step = maxf(max_stamina_step, st - prev_stamina)
		prev_stamina = st
		max_stamina = maxf(max_stamina, st)
		max_hunger = maxf(max_hunger, _mouse.survival.state.hunger)
		max_thirst = maxf(max_thirst, _mouse.survival.state.thirst)
		max_health = maxf(max_health, _mouse.survival.state.health)
	var hidden_rate := (h0 - _mouse.survival.state.hunger) / maxf(0.01, dt_sum)
	print("MEASURE|d_hidden|frames=%d|dt=%.2f|hunger_rate=%.4f|max_step=%.2f" % [frames, dt_sum, hidden_rate, max_stamina_step])
	_assert("D1_sampled_enough", "≥ 60 帧", str(frames), frames >= 60)
	_assert("D1_hunger_not_rising", "Δ ≤ +0.05", "%.4f" % (max_hunger - h0), max_hunger - h0 <= 0.05)
	_assert("D1_thirst_not_rising", "Δ ≤ +0.05", "%.4f" % (max_thirst - t0), max_thirst - t0 <= 0.05)
	_assert("D1_hunger_not_full", "< 上限 100", "%.1f" % max_hunger, max_hunger < 100.0)
	_assert("D1_thirst_not_full", "< 上限 100", "%.1f" % max_thirst, max_thirst < 100.0)
	_assert("D1_health_not_restored", "Δ ≤ 0", "%.4f" % (max_health - hp0), max_health - hp0 <= 0.001)
	_assert("D2_stamina_within_max", "≤ 100", "%.1f" % max_stamina, max_stamina <= 100.0 + EPS)
	var stamina_step_limit: float = _mouse_cfg.stamina_regen_per_sec * (1.0 / 60.0) * 2.0
	_assert("D2_stamina_no_jump", "帧增量 ≤ %.3f" % stamina_step_limit, "%.4f" % max_stamina_step,
		max_stamina_step <= stamina_step_limit)
	_assert("D3_hidden_rate_same_order", "±30%% of %.4f" % explore_rate, "%.4f" % hidden_rate,
		absf(hidden_rate - explore_rate) <= 0.3 * explore_rate)
	_assert("D5_no_move_while_hidden", "≤ 0.05 m", "%.4f m" % pos0.distance_to(_mouse.global_position),
		pos0.distance_to(_mouse.global_position) <= 0.05)

	# D4/D6 出洞：数值连续、状态回 explore
	var h_at_leave: float = _mouse.survival.state.hunger
	var t_at_leave: float = _mouse.survival.state.thirst
	var left := await _run_seconds(8.0, func() -> bool: return not is_instance_valid(mai) or mai.state_id() != &"hidden")
	_assert("D6_left_hiding", "非 hidden（%.2f s）" % left, str(mai.state_id()) if is_instance_valid(mai) else "<freed>",
		not is_instance_valid(mai) or mai.state_id() != &"hidden")
	_assert("D6_back_to_explore", "explore", str(mai.state_id()) if is_instance_valid(mai) else "<freed>",
		is_instance_valid(mai) and mai.state_id() == &"explore")
	_assert("D4_hunger_not_higher", "≤ 离开时", "%.2f -> %.2f" % [h_at_leave, _mouse.survival.state.hunger],
		_mouse.survival.state.hunger <= h_at_leave + 0.05)
	_assert("D4_thirst_not_higher", "≤ 离开时", "%.2f -> %.2f" % [t_at_leave, _mouse.survival.state.thirst],
		_mouse.survival.state.thirst <= t_at_leave + 0.05)
	_assert("D4_no_instant_refill", "< 100", "%.1f" % _mouse.survival.state.hunger, _mouse.survival.state.hunger < 100.0)


# ---------------------------------------------------------------------------
# E 集成
# ---------------------------------------------------------------------------

func _section_e_integration() -> void:
	print("---- E 集成（真实关卡：猫追 → 鼠钻洞 → 猫搜洞放弃，全程在洞外）----")
	await _fresh_level()
	if _mouse == null or _cat == null or _cat_ai == null:
		return
	var hole := _hole_marker()
	if hole == null:
		return
	var hole_point: Vector3 = _cat_ai.hide_spot_point(hole)
	var cap_before := int(_wd.get("capture_count")) if _wd != null else -1
	var food_before := int(_wd.get("capture_food_count")) if _wd != null else -1
	# 摆位：鼠在洞口外 2.5 m、猫再外 5.0 m，两边**互看** → 猫追、鼠逃进洞
	# （非空前提写在 E1_setup_*：猫真的追过 ≥ 1 m、鼠真的钻进去过）
	var dir := _wall_normal(hole_point)
	_mouse.ai_enabled = false
	_mouse.global_position = _push_start(hole_point + dir * 2.5, MOUSE_Y)
	await _advance_frames(SPAWN_FRAMES)
	_cat.ai_enabled = false
	_cat.global_position = _push_start(hole_point + dir * 5.0, CAT_Y)
	await _advance_frames(6)
	_mouse.look_at(_cat.global_position, Vector3.UP)
	_cat.look_at(_mouse.global_position, Vector3.UP)
	await _advance_frames(2)
	_mouse.ai_enabled = true
	await _advance_frames(2)
	_mouse_ai = _mouse.ai as MouseAI
	if _mouse_ai == null:
		_assert("E1_mouse_ai_rebuilt", "非 null", "<null>", false)
		return
	var mai: MouseAI = _mouse_ai
	_cat.ai_enabled = true
	await _advance_frames(2)
	_cat_ai = _cat.ai as CatAI
	if _cat_ai == null:
		_assert("E1_cat_ai_rebuilt", "非 null", "<null>", false)
		return
	_cat_ai.patrol_enabled = false
	# 攻击关掉：本段只验"洞"，攻击链见 B4（草丛不挡）与 T025
	_cat_ai.attack_enabled = false
	var cat_from := _cat.global_position
	var min_cat := INF
	var t0 := _now()
	while _now() - t0 < 14.0:
		await physics_frame
		min_cat = minf(min_cat, _cat.global_position.distance_to(hole_point))
	var cat_travel := Vector2(_cat.global_position.x - cat_from.x, _cat.global_position.z - cat_from.z).length()
	# 先读状态再关 AI（关掉会释放 AI 实例）
	var e_state := str(_cat_ai.state_id())
	var e_reason := str(_cat_ai.state_reason())
	var e_giveups := int(_cat_ai.give_up_count())
	var e_hidden := int(mai.hidden_count())
	var e_mouse_state := str(mai.state_id())
	_cat.ai_enabled = false
	print("MEASURE|e1|min_cat_to_hole=%.3f|cat_travel=%.3f|state=%s|reason=%s|giveups=%d|mouse_state=%s|hidden=%d|hp=%.1f" % [
		min_cat, cat_travel, e_state, e_reason, e_giveups, e_mouse_state, e_hidden, _mouse.survival.state.health])
	_assert("E1_setup_cat_travels", "≥ 1.00 m", "%.3f m" % cat_travel, cat_travel >= 1.00)
	_assert("E1_setup_mouse_hid", "≥ 1", str(e_hidden), e_hidden >= 1)
	_assert("E1_cat_stays_outside", "≥ %.2f m" % HOLE_RADIUS, "%.3f m" % min_cat, min_cat >= HOLE_RADIUS - EPS)
	_assert("E1_cat_searching_or_exploring", "search/explore/alert/approach/chase/attack", e_state,
		e_state in ["search", "explore", "alert", "approach", "chase", "attack"])
	_assert("E2_capture_ledger_same", "%d" % cap_before, str(int(_wd.get("capture_count"))),
		int(_wd.get("capture_count")) == cap_before)
	_assert("E2_food_ledger_same", "%d" % food_before, str(int(_wd.get("capture_food_count"))),
		int(_wd.get("capture_food_count")) == food_before)
	_assert("E2_mouse_alive", "true", str(not _mouse.survival.is_dead()), not _mouse.survival.is_dead())

	await _free_world()
	var main: Node = (load(MAIN) as PackedScene).instantiate()
	root.add_child(main)
	await _advance_frames(4)
	_assert("E3_no_debug_node_in_main", "0", str(_count_debug_nodes(main)), _count_debug_nodes(main) == 0)
	main.queue_free()
	await _advance_frames(2)


func _count_debug_nodes(node: Node) -> int:
	var n := 0
	for x in _all_nodes(node):
		if x.get_script() != null:
			var sp := String((x.get_script() as Script).resource_path)
			if sp.contains("/debug/"):
				n += 1
	return n


# ---------------------------------------------------------------------------
# fixture
# ---------------------------------------------------------------------------

## 合成竞技场（草丛/攻击/移动的受控几何）
func _fresh_arena(opts: Dictionary = {}) -> void:
	await _free_world()
	_world = Node3D.new()
	_world.name = "T026Arena"
	root.add_child(_world)
	await _advance_frames(2)
	_add_box(_world, "Ground", Vector3(ARENA, 1.0, ARENA), Vector3(0.0, -0.5, 0.0))
	await _advance_frames(2)
	if bool(opts.get("with_cat", false)):
		_cat = (load(BODY) as PackedScene).instantiate() as AnimalBody
		_cat.species_config = _cat_cfg
		_cat.player_controlled = false
		_cat.position = Vector3(0.0, CAT_Y, 0.0)
		_world.add_child(_cat)
		if bool(opts.get("cat_ai", false)):
			_cat.ai_enabled = true
			_cat_ai = _cat.ai as CatAI
			if _cat_ai != null:
				_cat_ai.patrol_enabled = false
				_cat_ai.attack_enabled = false
		await _advance_frames(SPAWN_FRAMES)
	if bool(opts.get("with_mouse", false)):
		_place_mouse(Vector3(0.0, MOUSE_Y, -2.0))
		await _advance_frames(4)
		if bool(opts.get("mouse_ai", false)):
			_mouse.ai_enabled = true
			_mouse_ai = _mouse.ai as MouseAI
			await _advance_frames(2)


## 真实关卡（草丛/鼠洞/导航/AI）
func _fresh_level() -> void:
	await _free_world()
	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	_assert("L_level_instantiated", "Node3D", str(level != null), level != null)
	if level == null:
		return
	_world = level
	root.add_child(level)
	await _advance_frames(8)
	var cat_spawn := Vector3.ZERO
	var mouse_spawn := Vector3.ZERO
	for n in _all_nodes(level):
		if n.is_in_group("spawn_points") and n.has_meta("species"):
			var s := String(n.get_meta("species"))
			if s == "Cat":
				cat_spawn = (n as Node3D).global_position
			elif s == "Mouse":
				mouse_spawn = (n as Node3D).global_position
	_cat = (load(BODY) as PackedScene).instantiate() as AnimalBody
	_cat.species_config = _cat_cfg
	_cat.player_controlled = false
	_cat.position = cat_spawn if cat_spawn != Vector3.ZERO else Vector3(0.0, CAT_Y, 0.0)
	level.add_child(_cat)
	_cat.ai_enabled = true
	await _advance_frames(SPAWN_FRAMES)
	_cat_ai = _cat.ai as CatAI
	if _cat_ai != null:
		_cat_ai.patrol_enabled = false
		_cat_ai.attack_enabled = false
	_place_mouse(mouse_spawn if mouse_spawn != Vector3.ZERO else Vector3(2.0, MOUSE_Y, 0.0))
	await _advance_frames(4)
	_mouse.ai_enabled = true
	await _advance_frames(4)
	_mouse_ai = _mouse.ai as MouseAI
	# 立刻把 AI 停住（本任务的夹具只需要它们的导航代理与查询；位置由测试显式摆放）
	if _mouse_ai != null:
		_mouse.ai_enabled = false
		await _advance_frames(2)
		_mouse.ai_enabled = true
		_mouse_ai = _mouse.ai as MouseAI
	await _advance_frames(4)


func _free_world() -> void:
	if _cat != null and is_instance_valid(_cat):
		_cat.queue_free()
	if _mouse != null and is_instance_valid(_mouse):
		_mouse.queue_free()
	_cat = null
	_mouse = null
	_cat_ai = null
	_mouse_ai = null
	for n in _extras:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_extras.clear()
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	await _advance_frames(3)


func _place_mouse(point: Vector3) -> AnimalBody:
	var spot := Vector3(point.x, MOUSE_Y, point.z)
	if _mouse == null or not is_instance_valid(_mouse):
		_mouse = (load(BODY) as PackedScene).instantiate() as AnimalBody
		_mouse.species_config = _mouse_cfg
		_mouse.player_controlled = false
		_mouse.ai_enabled = false
		var parent: Node = _world if _world != null else root
		_mouse.position = spot
		parent.add_child(_mouse)
		return _mouse
	_mouse.global_position = spot
	_mouse.velocity = Vector3.ZERO
	_mouse.move_intent = Vector2.ZERO
	return _mouse


## 草丛体量（纯数据 `Area3D`，layer 0 + Box 形状 + `visibility_factor`）—— 与 T011 关卡同构
func _add_cover(pos: Vector3, size: Vector3, factor: float) -> Area3D:
	var area := Area3D.new()
	area.name = "Cover_%d" % _extras.size()
	area.collision_layer = 0
	area.collision_mask = 0
	area.position = pos
	area.set_meta("visibility_factor", factor)
	area.set_meta("role", "cover")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	area.add_child(cs)
	area.add_to_group("cover_volumes")
	var parent: Node = _world if _world != null else root
	parent.add_child(area)
	_extras.append(area)
	return area


func _add_box(parent: Node, id: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = id
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


func _hole_marker() -> Node3D:
	for n in get_nodes_in_group(&"hide_spots"):
		if n is Node3D and n.has_meta("kind") and String(n.get_meta("kind")) == "mouse_hole":
			return n as Node3D
	return null


## 洞轴 = 墙法线：取关卡 RootBarrier 墙（group `nav_source_courtyard`，名字含 `Lintel`）的本地 z 轴。
## **不要**拿"猫出生点 → 洞口"当来向：那条轴与墙**平行**，会把身体摆进墙里（本轮夹具教训）。
func _wall_normal(_hole_point: Vector3) -> Vector3:
	_wall_normal_source = "fallback"
	for n in _all_nodes(_world):
		if n is Node3D and n.is_in_group(&"nav_source_courtyard") and String(n.name).contains("Lintel"):
			var axis := (n as Node3D).global_transform.basis.z
			axis.y = 0.0
			if axis.length_squared() > 1e-8:
				_wall_normal_source = "lintel"
				return axis.normalized()
	return Vector3(0.0, 0.0, 1.0)


## 把"沿洞轴 N 米"的点摆到站立高度（只改 y），避免把身体插进地面
func _push_start(point: Vector3, stand_y: float) -> Vector3:
	return Vector3(point.x, stand_y, point.z)


## 按层把点吸附到导航面：`map_get_closest_point()` **不带层**（见文件头注）→ 用一次 trivial 路径代替
func _snap_on_layer(map: RID, point: Vector3, layer: int) -> Vector3:
	var p: PackedVector3Array = NavigationServer3D.map_get_path(map, point, point + Vector3(0.05, 0.0, 0.0), true, layer)
	if p.size() >= 1:
		return p[0]
	return Vector3(INF, INF, INF)


func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	return total


func _path_min_dist(path: PackedVector3Array, point: Vector3) -> float:
	var best := INF
	for p in path:
		best = minf(best, p.distance_to(point))
	return best


func _push_towards(body: AnimalBody, target: Vector3) -> void:
	var to := target - body.global_position
	to.y = 0.0
	if to.length() < 0.001:
		body.move_intent = Vector2.ZERO
		return
	body.look_at(body.global_position + to.normalized(), Vector3.UP)
	body.move_intent = Vector2(0.0, -1.0)


## 猫的正前方偏 `angle_deg`、水平距离 `dist`
func _front(dist: float, angle_deg := 0.0) -> Vector3:
	var base := Vector3.ZERO
	var basis := Basis.IDENTITY
	if _cat != null and is_instance_valid(_cat):
		base = _cat.global_position
		basis = _cat.global_transform.basis
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.FORWARD
	var right := basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 1e-8 else Vector3.RIGHT
	var a := deg_to_rad(angle_deg)
	var dir := (fwd * cos(a) + right * sin(a)).normalized()
	return base + dir * dist


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _now() -> float:
	return float(_wd.get("world_time")) if _wd != null else 0.0


func _run_seconds(seconds: float, until: Callable = Callable()) -> float:
	if _wd == null:
		return 0.0
	var t0: float = _now()
	var frames := 0
	var max_frames := int(maxf(240.0, seconds * 240.0))
	while _now() - t0 < seconds and frames < max_frames and not paused:
		if until.is_valid() and bool(until.call()):
			break
		await physics_frame
		frames += 1
	return _now() - t0


func _advance_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _clip(s: String) -> String:
	return s.replace("\n", " | ").substr(0, 90)


func _all_nodes(node: Node) -> Array[Node]:
	if node == null:
		return []
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all_nodes(c))
	return out


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	var a := float(actual)
	_assert(id, "%.4f ±%.4f" % [expected, eps], "%.4f" % a, absf(a - expected) <= eps)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
