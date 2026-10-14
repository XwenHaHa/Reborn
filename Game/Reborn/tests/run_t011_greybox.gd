extends SceneTree
## T011 验收：生态灰盒 `res://scenes/maps/l_courtyard.tscn`
##
## 需求：`Docs/Tasks/T011.md`（策划 §8.1 四区域、§8.2 五条必须结构）；尺寸口径 `Docs/TechnicalDesign.md` §0。
## 办法：**几何断言 + 两个物种的真实胶囊物理探针**（合成输入），不靠"看起来像"。
##
## 设计常量写死在断言里（谁改了关卡而没改设计，测试直接失败）；物种尺寸**从 `cat.tres`/`mouse.tres` 算**。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t011_greybox.gd' --quit-after 60000

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BODY := "res://scenes/characters/animal_body.tscn"
const CAT := "res://resources/species/cat.tres"
const MOUSE := "res://resources/species/mouse.tres"

const GROUND_TOP := 0.10
const GEO_EPS := 1e-4

# --- 关卡设计常量（Docs/Tasks/T011.md §4） ------------------------------------
const PLAY_MIN_X := -36.0
const PLAY_MAX_X := 36.0
const PLAY_MIN_Z := -26.0
const PLAY_MAX_Z := 30.0
const PLAY_AREA := 4032.0
const GROUND_SIZE_XZ := 80.0
const FENCE_HEIGHT := 3.0

const REGION_SPEC := {
	"Courtyard": Vector4(-10.0, 10.0, 2.0, 30.0),
	"Creek": Vector4(-36.0, -10.0, 2.0, 30.0),
	"Roots": Vector4(10.0, 36.0, 2.0, 30.0),
	"Grass": Vector4(-36.0, 36.0, -26.0, 2.0),
}
const REGION_AREAS := {"Courtyard": 560.0, "Creek": 728.0, "Roots": 728.0, "Grass": 2016.0}
const SPAWN_SPEC := {"CatSpawn": "Cat", "MouseSpawn": "Mouse"}
const SUPPLY_SPEC := {
	"FoodPoint_Courtyard_Cat": ["food", "Cat", "Courtyard"],
	"FoodPoint_Courtyard_Mouse": ["food", "Mouse", "Courtyard"],
	"FoodPoint_Grass_Mouse": ["food", "Mouse", "Grass"],
	"FoodPoint_Roots_Mouse": ["food", "Mouse", "Roots"],
	"WaterPoint_Creek": ["water", "Both", "Creek"],
}

const BARRIER_HEIGHT := 0.50
const HOLE_W := 0.24
const HOLE_H := 0.30
const HOLE_LANE_X := 26.5
const CAT_JUMP_LANE_X := 30.0
const BANK_GAP := 0.24
const BANK_WALL_HEIGHT := 1.00
const BANK_LANE_X := -31.73
const BANK_NORTH_FACE := 14.0            # 岸墙 z∈[6,14]
const BANK_SOUTH_FACE := 6.0
const COVER_FACTOR := 0.4
const COVER_NODES := ["CoverBushWestA", "CoverBushWestB", "CoverBushNorthC", "CreekReedCover"]
const DANGER_Z_EDGE := 2.0
const ROUTE_SHORT_LEN := 24.0
const ROUTE_SAFE_LEN := 60.0
const ROUTE_MARKERS := ["RouteShortStart", "RouteShortEnd", "RouteSafeWaypoint1", "RouteSafeWaypoint2", "RouteSafeEnd"]
const SHELTER_MIN_CLEARANCE := 0.60      # 棚内净空（猫站高 0.48 + 余量）

# 探针参数
const PROBE_Z_START := 24.0
const PROBE_FRAMES := 300
const PROBE_CROSS_Z := 18.4              # 屏障南侧 18.5 再留 0.1
const BANK_PROBE_FRAMES := 400
const BANK_CROSS_Z := 5.7

var _checks := 0
var _fails := 0
var _world: Node3D = null
var _body: AnimalBody = null
var _cat: SpeciesConfig = null
var _mouse: SpeciesConfig = null


func _initialize() -> void:
	_cat = load(CAT) as SpeciesConfig
	_mouse = load(MOUSE) as SpeciesConfig
	_assert("species_configs_loaded", "cat & mouse .tres", str(_cat != null and _mouse != null),
		_cat != null and _mouse != null)

	var packed: PackedScene = load(LEVEL)
	_assert("level_scene_loads", LEVEL, str(packed != null), packed != null)
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

	_s1_infrastructure()
	_s2_regions()
	_s3_spawns_supplies()
	_s4_structures()
	_s5_scale_rules()
	await _s6_probes()
	_finish()


# ---------------------------------------------------------------------------
# A 基础设施
# ---------------------------------------------------------------------------

func _s1_infrastructure() -> void:
	var g := _box("Ground")
	_assert_near("ground_top_is_0.10", GROUND_TOP, float(g.get("top", -1.0)), GEO_EPS)
	_assert_near("ground_is_80_wide", GROUND_SIZE_XZ,
		float(g.get("max_x", 0.0)) - float(g.get("min_x", 0.0)), GEO_EPS)
	_assert_near("ground_is_80_deep", GROUND_SIZE_XZ,
		float(g.get("max_z", 0.0)) - float(g.get("min_z", 0.0)), GEO_EPS)
	_assert("ground_covers_playable", "x∈[%.1f,%.1f] z∈[%.1f,%.1f]" % [PLAY_MIN_X, PLAY_MAX_X, PLAY_MIN_Z, PLAY_MAX_Z],
		"x∈[%.1f,%.1f] z∈[%.1f,%.1f]" % [g.get("min_x", 0.0), g.get("max_x", 0.0), g.get("min_z", 0.0), g.get("max_z", 0.0)],
		float(g.get("min_x", 0.0)) <= PLAY_MIN_X and float(g.get("max_x", 0.0)) >= PLAY_MAX_X
		and float(g.get("min_z", 0.0)) <= PLAY_MIN_Z and float(g.get("max_z", 0.0)) >= PLAY_MAX_Z)

	_assert("sun_light_exists", "DirectionalLight3D",
		str(_world.get_node_or_null("SunLight")), _world.get_node_or_null("SunLight") is DirectionalLight3D)
	var we := _world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_assert("world_environment_with_sky", "Environment + Sky",
		str(we != null and we.environment != null and we.environment.sky != null),
		we != null and we.environment != null and we.environment.sky != null)

	var n := _box("FenceNorth")
	var s := _box("FenceSouth")
	var w := _box("FenceWest")
	var e := _box("FenceEast")
	_assert_near("fence_north_inner_face", PLAY_MAX_Z, float(n.get("min_z", 0.0)), GEO_EPS)
	_assert_near("fence_south_inner_face", PLAY_MIN_Z, float(s.get("max_z", 0.0)), GEO_EPS)
	_assert_near("fence_west_inner_face", PLAY_MIN_X, float(w.get("max_x", 0.0)), GEO_EPS)
	_assert_near("fence_east_inner_face", PLAY_MAX_X, float(e.get("min_x", 0.0)), GEO_EPS)
	for pair in [["north", n], ["south", s], ["west", w], ["east", e]]:
		var d: Dictionary = pair[1]
		_assert_near("fence_%s_height_%.1f" % [pair[0], FENCE_HEIGHT],
			GROUND_TOP + FENCE_HEIGHT, float(d.get("top", 0.0)), GEO_EPS)
	print("MEASURE|level|ground_top=%.3f|play=[%.1f,%.1f]x[%.1f,%.1f]|area=%.0f|fence_h=%.2f" % [
		float(g.get("top", 0.0)), PLAY_MIN_X, PLAY_MAX_X, PLAY_MIN_Z, PLAY_MAX_Z, PLAY_AREA, FENCE_HEIGHT
	])
	_assert("no_player_node_yet", "T013 才放玩家",
		str(_world.get_node_or_null("Player")), _world.get_node_or_null("Player") == null)


# ---------------------------------------------------------------------------
# B 四区域：恰好铺满可玩矩形
# ---------------------------------------------------------------------------

func _s2_regions() -> void:
	var rects: Array = []
	var area_sum := 0.0
	for id in REGION_SPEC:
		var node := _world.get_node_or_null("Region_%s" % id) as Node3D
		var tag: String = String(id).to_lower()
		if not _assert("region_%s_exists" % tag, "Node3D", str(node), node != null):
			continue
		_assert("region_%s_meta_id" % tag, id, str(node.get_meta("region_id", "<none>")),
			String(node.get_meta("region_id", "")) == id)
		_assert("region_%s_in_group" % tag, "level_regions", str(node.get_groups()),
			node.is_in_group("level_regions"))
		var r: Vector4 = REGION_SPEC[id]
		var rect := _region_rect(node)
		_assert_near("region_%s_min_x" % tag, r.x, rect["min_x"], GEO_EPS)
		_assert_near("region_%s_max_x" % tag, r.y, rect["max_x"], GEO_EPS)
		_assert_near("region_%s_min_z" % tag, r.z, rect["min_z"], GEO_EPS)
		_assert_near("region_%s_max_z" % tag, r.w, rect["max_z"], GEO_EPS)
		var area: float = (rect["max_x"] - rect["min_x"]) * (rect["max_z"] - rect["min_z"])
		_assert_near("region_%s_area_%.0f" % [tag, REGION_AREAS[id]], REGION_AREAS[id], area, 1e-3)
		area_sum += area
		rects.append(rect)
	_assert_near("region_area_sum_is_playable", PLAY_AREA, area_sum, 1e-3)
	_assert("region_count_is_4", "4", "%d" % rects.size(), rects.size() == 4)
	_assert("regions_in_group_count_4", "4", "%d" % get_nodes_in_group("level_regions").size(),
		get_nodes_in_group("level_regions").size() == 4)

	var overlap := false
	var overlap_pair := ""
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Dictionary = rects[i]
			var b: Dictionary = rects[j]
			if a["min_x"] < b["max_x"] - GEO_EPS and b["min_x"] < a["max_x"] - GEO_EPS \
					and a["min_z"] < b["max_z"] - GEO_EPS and b["min_z"] < a["max_z"] - GEO_EPS:
				overlap = true
				overlap_pair = "%s×%s" % [a["id"], b["id"]]
	_assert("regions_do_not_overlap", "无重叠", overlap_pair if overlap else "no overlap", not overlap)

	var ux0 := INF
	var ux1 := -INF
	var uz0 := INF
	var uz1 := -INF
	for a in rects:
		ux0 = minf(ux0, a["min_x"])
		ux1 = maxf(ux1, a["max_x"])
		uz0 = minf(uz0, a["min_z"])
		uz1 = maxf(uz1, a["max_z"])
	_assert("region_union_equals_playable", "x∈[−36,36] z∈[−26,30]",
		"x∈[%.1f,%.1f] z∈[%.1f,%.1f]" % [ux0, ux1, uz0, uz1],
		absf(ux0 - PLAY_MIN_X) < GEO_EPS and absf(ux1 - PLAY_MAX_X) < GEO_EPS
		and absf(uz0 - PLAY_MIN_Z) < GEO_EPS and absf(uz1 - PLAY_MAX_Z) < GEO_EPS)
	print("MEASURE|regions|count=%d|area_sum=%.0f|union=[%.1f,%.1f]x[%.1f,%.1f]" % [
		rects.size(), area_sum, ux0, ux1, uz0, uz1
	])


# ---------------------------------------------------------------------------
# C 出生点 / 补给点 / 基础补给走廊
# ---------------------------------------------------------------------------

func _s3_spawns_supplies() -> void:
	for name in SPAWN_SPEC:
		var tag: String = String(name).to_lower()
		var m := _world.get_node_or_null(name) as Marker3D
		if not _assert("spawn_%s_exists" % tag, "Marker3D", str(m), m != null):
			continue
		_assert("spawn_%s_in_group" % tag, "spawn_points", str(m.get_groups()), m.is_in_group("spawn_points"))
		_assert("spawn_%s_meta_region" % tag, "Courtyard", str(m.get_meta("region", "<none>")),
			String(m.get_meta("region", "")) == "Courtyard")
		_assert("spawn_%s_meta_species" % tag, SPAWN_SPEC[name], str(m.get_meta("species", "<none>")),
			String(m.get_meta("species", "")) == SPAWN_SPEC[name])
		_assert("spawn_%s_inside_courtyard" % tag, "在庭院区域内",
			_point_str(m.global_position), _inside_region(m.global_position, "Courtyard"))
		var cfg: SpeciesConfig = _cat if name == "CatSpawn" else _mouse
		var hits := _capsule_hits_at(cfg, m.global_position, 0.01)
		_assert("spawn_%s_capsule_clear" % tag, "0 overlap", "%d" % hits, hits == 0)

	for name in SUPPLY_SPEC:
		var spec: Array = SUPPLY_SPEC[name]
		var tag: String = String(name).to_lower()
		var m := _world.get_node_or_null(name) as Marker3D
		if not _assert("supply_%s_exists" % tag, "Marker3D", str(m), m != null):
			continue
		_assert("supply_%s_in_group" % tag, "supply_points", str(m.get_groups()), m.is_in_group("supply_points"))
		_assert("supply_%s_type_%s" % [tag, spec[0]], spec[0], str(m.get_meta("supply_type", "<none>")),
			String(m.get_meta("supply_type", "")) == spec[0])
		_assert("supply_%s_species_%s" % [tag, spec[1]], spec[1], str(m.get_meta("species", "<none>")),
			String(m.get_meta("species", "")) == spec[1])
		_assert("supply_%s_in_region_%s" % [tag, String(spec[2]).to_lower()], spec[2],
			str(m.get_meta("region", "<none>")), String(m.get_meta("region", "")) == spec[2])
		_assert("supply_%s_inside_%s" % [tag, String(spec[2]).to_lower()], "位置在声明的区域内",
			_point_str(m.global_position), _inside_region(m.global_position, spec[2]))

	# 基础补给走廊：每个出生点 → 本物种食物点 + → 饮水点
	var cat_spawn := (_world.get_node_or_null("CatSpawn") as Marker3D).global_position
	var mouse_spawn := (_world.get_node_or_null("MouseSpawn") as Marker3D).global_position
	var cat_food := (_world.get_node_or_null("FoodPoint_Courtyard_Cat") as Marker3D).global_position
	var mouse_food := (_world.get_node_or_null("FoodPoint_Courtyard_Mouse") as Marker3D).global_position
	var water := (_world.get_node_or_null("WaterPoint_Creek") as Marker3D).global_position
	var pairs := [
		["corridor_cat_food", cat_spawn, cat_food],
		["corridor_mouse_food", mouse_spawn, mouse_food],
		["corridor_cat_water", cat_spawn, water],
		["corridor_mouse_water", mouse_spawn, water],
	]
	for p in pairs:
		var from: Vector3 = p[1]
		var to: Vector3 = p[2]
		var blocked := _corridor_blocked(from, to, 0.20, 0.10)
		var dist: float = from.distance_to(to)
		_assert("%s_clear" % p[0], "0 命中（离地 0.20 m、半径 0.10 球）", "%d 命中" % blocked, blocked == 0)
		_assert("%s_length_plausible" % p[0], "[1, 60] m", "%.2f m" % dist, dist >= 1.0 and dist <= 60.0)
		print("MEASURE|%s|from=%s|to=%s|len=%.2f|blocked_samples=%d" % [
			p[0], _point_str(from), _point_str(to), dist, blocked
		])


# ---------------------------------------------------------------------------
# D 必需结构（策划 §8.2）
# ---------------------------------------------------------------------------

func _s4_structures() -> void:
	# 庭院：休息棚 + 碎屑
	var sw := _box("ShelterWallWest")
	var sn := _box("ShelterWallNorth")
	var ss := _box("ShelterWallSouth")
	var roof := _box("ShelterRoof")
	_assert("shelter_三面墙存在", "West/North/South", "%s/%s/%s" % [not sw.is_empty(), not sn.is_empty(), not ss.is_empty()],
		not sw.is_empty() and not sn.is_empty() and not ss.is_empty())
	if not roof.is_empty() and not ss.is_empty():
		var clearance: float = float(roof["bottom"]) - GROUND_TOP
		_assert("shelter_ceiling_clearance", "≥ %.2f" % SHELTER_MIN_CLEARANCE, "%.3f" % clearance,
			clearance >= SHELTER_MIN_CLEARANCE)
		_assert("shelter_cat_fits_inside", "猫站高 %.2f ≤ 净空" % _cat.capsule_height(), "%.3f" % clearance,
			clearance >= _cat.capsule_height())
	for i in range(1, 4):
		_assert("courtyard_debris%d_exists" % i, "StaticBody3D", str(not _box("CourtyardDebris%d" % i).is_empty()),
			not _box("CourtyardDebris%d" % i).is_empty())

	# 草地：观察点（0.50）+ 危险区 + 掩体
	for nm in ["GrassMoundA", "GrassMoundB"]:
		var mb := _box(nm)
		if _assert("%s_exists" % nm.to_lower(), "StaticBody3D", str(not mb.is_empty()), not mb.is_empty()):
			_assert_near("%s_height_0.50" % nm.to_lower(), GROUND_TOP + 0.50, float(mb["top"]), GEO_EPS)
	var dz := _area("DangerZone")
	if _assert("danger_zone_exists", "Area3D", str(not dz.is_empty()), not dz.is_empty()):
		_assert_near("danger_zone_south_edge_at_region_border", DANGER_Z_EDGE, float(dz["max_z"]), GEO_EPS)
		_assert("danger_zone_size_16x24", "16 × 24", "%.1f × %.1f" % [dz["size_x"], dz["size_z"]],
			absf(dz["size_x"] - 16.0) < GEO_EPS and absf(dz["size_z"] - 24.0) < GEO_EPS)
		# "危险区提供退路/可观察的入口风险"：量**体量之间的空隙**，不是中心距（中心距会因体积大小而失义）
		var nearest_gap := INF
		for nm in COVER_NODES:
			var c := _area(nm)
			if not c.is_empty():
				nearest_gap = minf(nearest_gap, _area_gap(dz, c))
		_assert("danger_zone_has_retreat_within_5m", "危险区边界 ≤ 5 m 内有掩体",
			"%.2f m" % nearest_gap, nearest_gap <= 5.0)
	for nm in COVER_NODES:
		var c := _area(nm)
		if _assert("cover_%s_exists" % nm.to_lower(), "Area3D", str(not c.is_empty()), not c.is_empty()):
			var node := _world.get_node_or_null(nm) as Area3D
			_assert("cover_%s_group" % nm.to_lower(), "cover_volumes", str(node.get_groups()),
				node.is_in_group("cover_volumes"))
			_assert_near("cover_%s_visibility_factor_0.4" % nm.to_lower(), COVER_FACTOR,
				float(node.get_meta("visibility_factor", 0.0)), 1e-6)
			_assert("cover_%s_is_data_volume" % nm.to_lower(), "layer=0 & monitoring=false",
				"layer=%d monitoring=%s" % [node.collision_layer, str(node.monitoring)],
				node.collision_layer == 0 and not node.monitoring)

	# 树根屏障（§8.2-1/2/5）
	var lw := _box("RootBarrierWest")
	var le := _box("RootBarrierEast")
	var li := _box("RootBarrierLintel")
	if _assert("root_barrier_exists", "West/East/Lintel",
		"%s/%s/%s" % [not lw.is_empty(), not le.is_empty(), not li.is_empty()],
		not lw.is_empty() and not le.is_empty() and not li.is_empty()):
		_assert_near("root_barrier_top_above_ground", GROUND_TOP + BARRIER_HEIGHT, float(lw["top"]), GEO_EPS)
		_assert_near("root_barrier_bottom_at_ground", GROUND_TOP, float(lw["bottom"]), GEO_EPS)
		_assert_near("root_hole_width_0.24", HOLE_W, float(le["min_x"]) - float(lw["max_x"]), GEO_EPS)
		_assert_near("root_hole_height_0.30", HOLE_H, float(li["bottom"]) - GROUND_TOP, GEO_EPS)
		_assert_near("root_barrier_spans_roots_west", 10.0, float(lw["min_x"]), GEO_EPS)
		_assert_near("root_barrier_spans_roots_east", 36.0, float(le["max_x"]), GEO_EPS)
		var hole_center: float = (float(lw["max_x"]) + float(le["min_x"])) * 0.5
		_assert("root_hole_lane_is_clear_of_cat_jump_lane", "|x_cat − x_hole| ≥ 1.0",
			"%.2f" % absf(CAT_JUMP_LANE_X - hole_center), absf(CAT_JUMP_LANE_X - hole_center) >= 1.0)
		var barrier_depth: float = float(lw["max_z"]) - float(lw["min_z"])
		_assert_near("root_barrier_depth_1.0", 1.0, barrier_depth, GEO_EPS)
		print("MEASURE|root_barrier|top=%.3f|hole=%.2fx%.2f@x=%.2f|depth=%.2f|span=[%.1f,%.1f]" % [
			float(lw["top"]), float(le["min_x"]) - float(lw["max_x"]), float(li["bottom"]) - GROUND_TOP,
			hole_center, barrier_depth, float(lw["min_x"]), float(le["max_x"])
		])

	# 溪边隐蔽入口（§8.2-2）
	var wa := _box("CreekBankWallA")
	var wb := _box("CreekBankWallB")
	if _assert("creek_bank_walls_exist", "A/B", "%s/%s" % [not wa.is_empty(), not wb.is_empty()],
			not wa.is_empty() and not wb.is_empty()):
		_assert_near("creek_gap_width_0.24", BANK_GAP, float(wb["min_x"]) - float(wa["max_x"]), GEO_EPS)
		_assert_near("creek_wall_height_1.00", GROUND_TOP + BANK_WALL_HEIGHT, float(wa["top"]), GEO_EPS)
		_assert_near("creek_gap_center_x", BANK_LANE_X, (float(wb["min_x"]) + float(wa["max_x"])) * 0.5, GEO_EPS)
		_assert_near("creek_wall_north_face", BANK_NORTH_FACE, float(wa["max_z"]), GEO_EPS)
		_assert_near("creek_wall_south_face", BANK_SOUTH_FACE, float(wa["min_z"]), GEO_EPS)
	_assert("creek_boulder_exists", "StaticBody3D", str(not _box("CreekBoulder").is_empty()),
		not _box("CreekBoulder").is_empty())

	# 浅溪：只有网格、没有碰撞
	var water := _world.get_node_or_null("CreekWater") as MeshInstance3D
	if _assert("creek_water_exists", "MeshInstance3D", str(water), water != null):
		_assert("creek_water_has_no_collision", "0 个碰撞形状",
			"%d" % _count_collision_nodes(water), _count_collision_nodes(water) == 0)
		var bm := water.mesh as BoxMesh
		if _assert("creek_water_mesh_is_box", "BoxMesh", str(bm != null), bm != null):
			_assert_near("creek_water_top_0.13", 0.13, water.position.y + bm.size.y * 0.5, GEO_EPS)
			_assert_near("creek_water_depth_0.03", 0.03, bm.size.y, GEO_EPS)
		_assert("creek_water_depth_meta", "0.03", str(water.get_meta("water_depth", -1.0)),
			absf(float(water.get_meta("water_depth", 0.0)) - 0.03) < 1e-6)
	_assert("water_bodies_group_has_1", "1", "%d" % get_nodes_in_group("water_bodies").size(),
		get_nodes_in_group("water_bodies").size() == 1)

	# 路线标记与长度（§8.2-3）
	for nm in ROUTE_MARKERS:
		_assert("route_marker_%s_exists" % nm.to_lower(), "Marker3D",
			str(_world.get_node_or_null(nm)), _world.get_node_or_null(nm) != null)
	var short_len := (_marker_pos("RouteShortStart")).distance_to(_marker_pos("RouteShortEnd"))
	var safe_len := (_marker_pos("RouteSafeWaypoint1") - _marker_pos("RouteShortStart")).length() \
		+ (_marker_pos("RouteSafeWaypoint2") - _marker_pos("RouteSafeWaypoint1")).length() \
		+ (_marker_pos("RouteSafeEnd") - _marker_pos("RouteSafeWaypoint2")).length()
	_assert_near("route_short_length_24", ROUTE_SHORT_LEN, short_len, 0.05)
	_assert_near("route_safe_length_60", ROUTE_SAFE_LEN, safe_len, 0.05)
	_assert("route_safe_is_at_least_1.5x_short", "≥ 1.5 × 直穿",
		"%.2f ×" % (safe_len / maxf(0.01, short_len)), safe_len >= 1.5 * short_len)
	var short_in_danger := _sample_inside_area("RouteShortStart", "RouteShortEnd", "DangerZone", 0.1)
	var short_in_cover := _sample_inside_any_cover("RouteShortStart", "RouteShortEnd", 0.1)
	_assert("route_short_fully_exposed", "100% 在危险区", "%.1f%%" % (100.0 * short_in_danger), short_in_danger >= 0.999)
	_assert("route_short_has_no_cover", "0 个掩体命中", "%d" % short_in_cover, short_in_cover == 0)
	var safe_in_danger := _sample_polyline_inside_area(["RouteShortStart", "RouteSafeWaypoint1", "RouteSafeWaypoint2", "RouteSafeEnd"], "DangerZone", 0.1)
	var safe_cover := _sample_polyline_cover_hits(["RouteShortStart", "RouteSafeWaypoint1", "RouteSafeWaypoint2", "RouteSafeEnd"], 0.1)
	_assert("route_safe_exposure_below_50pct", "≤ 50%", "%.1f%%" % (100.0 * safe_in_danger), safe_in_danger <= 0.5)
	_assert("route_safe_passes_at_least_2_covers", "≥ 2", "%d" % safe_cover, safe_cover >= 2)
	print("MEASURE|routes|short=%.2f m (暴露 %.1f%%)|safe=%.2f m (暴露 %.1f%%, 掩体命中 %d)" % [
		short_len, 100.0 * short_in_danger, safe_len, 100.0 * safe_in_danger, safe_cover
	])


# ---------------------------------------------------------------------------
# E 尺度判据（从两个物种配置算，不写死结论）
# ---------------------------------------------------------------------------

func _s5_scale_rules() -> void:
	var cat_w := _cat.capsule_radius * 2.0
	var cat_stand := _cat.capsule_height()
	var cat_crouch := _cat.crouch_height()
	var mouse_w := _mouse.capsule_radius * 2.0
	var mouse_stand := _mouse.capsule_height()
	var mouse_crouch := _mouse.crouch_height()
	print("SCALE|mouse_stand=%.3f x %.3f|mouse_crouch=%.3f x %.3f|cat_stand=%.3f x %.3f|cat_crouch=%.3f x %.3f|hole=%.3f x %.3f|barrier=%.2f|bank_gap=%.3f|bank_h=%.2f" % [
		mouse_w, mouse_stand, mouse_w, mouse_crouch, cat_w, cat_stand, cat_w, cat_crouch,
		HOLE_W, HOLE_H, BARRIER_HEIGHT, BANK_GAP, BANK_WALL_HEIGHT
	])

	# 树根洞：鼠过、猫不过在
	_assert("scale_mouse_stand_fits_root_hole", "%.2f ≤ %.2f 且 %.2f ≤ %.2f" % [mouse_w, HOLE_W, mouse_stand, HOLE_H],
		"w %.2f h %.2f" % [mouse_w, mouse_stand], mouse_w <= HOLE_W + GEO_EPS and mouse_stand <= HOLE_H + GEO_EPS)
	_assert("scale_mouse_crouch_fits_root_hole", "%.2f ≤ %.2f 且 %.2f ≤ %.2f" % [mouse_w, HOLE_W, mouse_crouch, HOLE_H],
		"w %.2f h %.2f" % [mouse_w, mouse_crouch], mouse_w <= HOLE_W + GEO_EPS and mouse_crouch <= HOLE_H + GEO_EPS)
	_assert("scale_cat_stand_blocked_by_root_hole", "猫站高 %.2f 或宽 %.2f 超过洞" % [cat_stand, cat_w],
		"w %.2f h %.2f" % [cat_w, cat_stand], cat_w > HOLE_W + GEO_EPS or cat_stand > HOLE_H + GEO_EPS)
	_assert("scale_cat_crouch_blocked_by_root_hole", "猫蹲宽 %.2f > 洞宽 %.2f（宽度是硬边界）" % [cat_w, HOLE_W],
		"w %.2f" % cat_w, cat_w > HOLE_W + GEO_EPS)

	# 屏障 0.50：猫跳得上去、鼠上不去
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var cat_clearance: float = _cat.jump_velocity * _cat.jump_velocity / (2.0 * gravity)
	_assert("scale_cat_jump_clears_barrier", "解析净空 %.4f > %.2f" % [cat_clearance, BARRIER_HEIGHT],
		"%.4f" % cat_clearance, cat_clearance > BARRIER_HEIGHT)
	_assert("scale_barrier_has_margin", "≥ 0.02 m", "%.4f m" % (cat_clearance - BARRIER_HEIGHT),
		cat_clearance - BARRIER_HEIGHT >= 0.02)
	_assert("scale_mouse_cannot_jump", "can_jump = false", str(_mouse.can_jump), not _mouse.can_jump)
	_assert("scale_mouse_step_below_barrier", "max_step %.3f < %.2f" % [_mouse.max_step_height, BARRIER_HEIGHT],
		"%.3f" % _mouse.max_step_height, _mouse.max_step_height < BARRIER_HEIGHT)
	_assert("scale_mouse_step_below_bank_wall", "max_step %.3f < %.2f" % [_mouse.max_step_height, BANK_WALL_HEIGHT],
		"%.3f" % _mouse.max_step_height, _mouse.max_step_height < BANK_WALL_HEIGHT)
	print("SCALE|cat_jump_clearance_analytic=%.4f|T009_measured=%.4f|barrier=%.2f|bank_wall=%.2f" % [
		cat_clearance, 0.5502, BARRIER_HEIGHT, BANK_WALL_HEIGHT
	])

	# 溪边缝隙：鼠过、猫进不去也跳不过
	_assert("scale_mouse_fits_bank_gap", "%.2f ≤ %.2f" % [mouse_w, BANK_GAP], "%.2f vs %.2f" % [mouse_w, BANK_GAP],
		mouse_w <= BANK_GAP + GEO_EPS)
	_assert("scale_cat_blocked_by_bank_gap_width", "%.2f > %.2f" % [cat_w, BANK_GAP], "%.2f vs %.2f" % [cat_w, BANK_GAP],
		cat_w > BANK_GAP + GEO_EPS)
	_assert("scale_cat_cannot_jump_bank_wall", "墙高 %.2f > 净空 %.4f × 1.2" % [BANK_WALL_HEIGHT, cat_clearance],
		"%.4f" % (BANK_WALL_HEIGHT / cat_clearance), BANK_WALL_HEIGHT > cat_clearance * 1.2)


# ---------------------------------------------------------------------------
# F 物理探针（真实 AnimalBody + 合成输入）
# ---------------------------------------------------------------------------

func _s6_probes() -> void:
	await _p1_mouse_roots_hole()
	await _p2_cat_blocked_at_roots_hole()
	await _p3_cat_crosses_barrier_by_jump()
	await _p4_mouse_cannot_cross_barrier()
	await _p5_mouse_through_creek_gap()
	await _p6_cat_blocked_at_creek_gap()


## 树根洞（M01 鼠半边）：鼠**站立**穿过
func _p1_mouse_roots_hole() -> void:
	await _spawn(_mouse, Vector3(HOLE_LANE_X, GROUND_TOP + _mouse.capsule_half_height + 0.02, PROBE_Z_START), 0.0)
	var y0: float = _body.global_position.y
	var min_y := y0
	var max_y := y0
	var airborne := 0
	var crossed := -1
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in PROBE_FRAMES:
		await physics_frame
		min_y = minf(min_y, _body.global_position.y)
		max_y = maxf(max_y, _body.global_position.y)
		if not _body.is_on_floor():
			airborne += 1
		if _body.global_position.z <= PROBE_CROSS_Z:
			crossed = i
			break
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _wait(10)
	var p: Vector3 = _body.global_position
	var pen := _overlaps_world(0.005)
	var cap_h := _current_capsule_height()
	print("MEASURE|P1_mouse_roots_hole|start_z=%.3f|end=(%.3f, %.3f, %.3f)|frames_to_cross=%d|y=[%.4f, %.4f]|airborne=%d|overlaps=%d|capsule_h=%.3f" % [
		PROBE_Z_START, p.x, p.y, p.z, crossed, min_y, max_y, airborne, pen, cap_h
	])
	_assert("P1_mouse_crosses_root_hole", "z ≤ %.1f（穿过屏障）" % PROBE_CROSS_Z, "z=%.3f" % p.z, p.z <= PROBE_CROSS_Z)
	_assert("P1_mouse_crossed_within_budget", "0 ≤ frames < %d" % PROBE_FRAMES, "%d" % crossed,
		crossed >= 0 and crossed < PROBE_FRAMES)
	_assert("P1_mouse_stays_on_ground", "airborne = 0", "%d" % airborne, airborne == 0)
	_assert("P1_mouse_no_penetration", "overlaps = 0", "%d" % pen, pen == 0)
	_assert("P1_mouse_y_stable", "max − min ≤ 0.01", "%.4f" % (max_y - min_y), max_y - min_y <= 0.01)
	_assert("P1_mouse_standing_capsule", "0.180", "%.3f" % cap_h, absf(cap_h - 0.18) <= 0.01)


## 树根洞：猫在**同一车道**过不去
func _p2_cat_blocked_at_roots_hole() -> void:
	await _spawn(_cat, Vector3(HOLE_LANE_X, GROUND_TOP + _cat.capsule_half_height + 0.02, PROBE_Z_START), 0.0)
	# `last_probe` 在停下之后会被清空 → **在循环里持续记录**最后见到的判定原因
	var reason_seen := "<none>"
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in 240:
		await physics_frame
		if _body.climb != null and not _body.climb.last_probe.is_empty():
			reason_seen = str(_body.climb.last_probe.get("reason", "<none>"))
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _wait(10)
	var p: Vector3 = _body.global_position
	var pen := _overlaps_world(0.005)
	print("MEASURE|P2_cat_roots_hole|end=(%.3f, %.3f, %.3f)|face_north_z=%.2f|step_reason=%s|penetration=%d" % [
		p.x, p.y, p.z, 19.5, reason_seen, pen
	])
	_assert("P2_cat_moved_toward_barrier", "z ≤ 23.0", "z=%.3f" % p.z, p.z <= 23.0)
	_assert("P2_cat_blocked_by_root_hole", "z ≥ 19.5（屏障北面）", "z=%.3f" % p.z, p.z >= 19.5)
	_assert("P2_cat_step_reason", "blocked_after_raise", reason_seen, reason_seen == "blocked_after_raise")
	_assert("P2_cat_no_penetration", "overlaps = 0", "%d" % pen, pen == 0)


## 树根屏障（§8.2-1）：猫从 x=30 的车道**跳越**到南侧
func _p3_cat_crosses_barrier_by_jump() -> void:
	await _spawn(_cat, Vector3(CAT_JUMP_LANE_X, GROUND_TOP + _cat.capsule_half_height + 0.02, PROBE_Z_START), 0.0)
	var max_y: float = _body.global_position.y
	var max_feet: float = max_y - _cat.capsule_half_height
	var jump_frame := -1
	var crossed := -1
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in PROBE_FRAMES:
		await physics_frame
		max_y = maxf(max_y, _body.global_position.y)
		max_feet = maxf(max_feet, _body.global_position.y - _cat.capsule_half_height)
		if jump_frame < 0 and _body.global_position.z <= 20.25:
			jump_frame = i
			Input.action_press("jump")
		if jump_frame >= 0 and i >= jump_frame + 4:
			Input.action_release("jump")
		if _body.global_position.z <= PROBE_CROSS_Z and _body.is_on_floor():
			crossed = i
			break
	Input.action_release("jump")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _wait(20)
	var p: Vector3 = _body.global_position
	var pen := _overlaps_world(0.005)
	var feet_above_ground: float = max_feet - GROUND_TOP
	print("MEASURE|P3_cat_barrier_jump|lane_x=%.1f|jump_frame=%d|crossed_frame=%d|end=(%.3f, %.3f, %.3f)|max_center_y=%.4f|max_feet_above_ground=%.4f|on_floor=%s|overlaps=%d" % [
		CAT_JUMP_LANE_X, jump_frame, crossed, p.x, p.y, p.z, max_y, feet_above_ground, str(_body.is_on_floor()), pen
	])
	_assert("P3_cat_crosses_barrier_lane", "z ≤ %.1f（越过屏障）" % PROBE_CROSS_Z, "z=%.3f" % p.z,
		p.z <= PROBE_CROSS_Z)
	_assert("P3_cat_crossed_and_on_floor", "is_on_floor = true", str(_body.is_on_floor()), _body.is_on_floor())
	_assert("P3_cat_jumped_high_enough", "中心最高 ≥ %.2f（屏障顶 0.60 + 半球 0.24）" % (GROUND_TOP + BARRIER_HEIGHT + _cat.capsule_half_height - 0.04),
		"%.3f" % max_y, max_y >= GROUND_TOP + BARRIER_HEIGHT + _cat.capsule_half_height - 0.04)
	_assert("P3_cat_no_penetration", "overlaps = 0", "%d" % pen, pen == 0)
	_assert("P3_cat_not_stuck", "crossed_frame ≥ 0", "%d" % crossed, crossed >= 0 and crossed < PROBE_FRAMES)


## 树根屏障：鼠在**同一车道**上不去（禁高跳）
func _p4_mouse_cannot_cross_barrier() -> void:
	await _spawn(_mouse, Vector3(CAT_JUMP_LANE_X, GROUND_TOP + _mouse.capsule_half_height + 0.02, PROBE_Z_START), 0.0)
	var y0: float = _body.global_position.y
	var max_up := 0.0
	var all_floor := true
	Input.action_press("move_forward")
	Input.action_press("jump")
	for i in 240:
		await physics_frame
		max_up = maxf(max_up, _body.global_position.y - y0)
		if not _body.is_on_floor():
			all_floor = false
	Input.action_release("jump")
	Input.action_release("move_forward")
	await _wait(10)
	var p: Vector3 = _body.global_position
	var pen := _overlaps_world(0.005)
	print("MEASURE|P4_mouse_barrier|lane_x=%.1f|max_up=%.4f|on_floor_all=%s|can_jump=%s|end_z=%.3f|overlaps=%d" % [
		CAT_JUMP_LANE_X, max_up, str(all_floor), str(_body.can_jump()), p.z, pen
	])
	_assert("P4_mouse_does_not_take_off", "max_up ≤ 0.01", "%.4f" % max_up, max_up <= 0.01)
	_assert("P4_mouse_can_jump_false", "false", str(_body.can_jump()), not _body.can_jump())
	_assert("P4_mouse_blocked_by_barrier", "z ≥ 19.5", "z=%.3f" % p.z, p.z >= 19.5)
	_assert("P4_mouse_no_penetration", "overlaps = 0", "%d" % pen, pen == 0)


## 溪边缝隙（§8.2-2）：鼠穿过 0.24 的缝
func _p5_mouse_through_creek_gap() -> void:
	await _spawn(_mouse, Vector3(BANK_LANE_X, GROUND_TOP + _mouse.capsule_half_height + 0.02, 17.0), 0.0)
	var y0: float = _body.global_position.y
	var min_y := y0
	var max_y := y0
	var airborne := 0
	var crossed := -1
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in BANK_PROBE_FRAMES:
		await physics_frame
		min_y = minf(min_y, _body.global_position.y)
		max_y = maxf(max_y, _body.global_position.y)
		if not _body.is_on_floor():
			airborne += 1
		if _body.global_position.z <= BANK_CROSS_Z:
			crossed = i
			break
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _wait(10)
	var p: Vector3 = _body.global_position
	var pen := _overlaps_world(0.005)
	print("MEASURE|P5_mouse_creek_gap|lane_x=%.3f|start_z=17.000|end=(%.3f, %.3f, %.3f)|frames_to_cross=%d|y=[%.4f, %.4f]|airborne=%d|overlaps=%d" % [
		BANK_LANE_X, p.x, p.y, p.z, crossed, min_y, max_y, airborne, pen
	])
	_assert("P5_mouse_crosses_creek_gap", "z ≤ %.1f（穿过缝隙南端 %.1f）" % [BANK_CROSS_Z, BANK_SOUTH_FACE],
		"z=%.3f" % p.z, p.z <= BANK_CROSS_Z)
	_assert("P5_mouse_crossed_within_budget", "0 ≤ frames < %d" % BANK_PROBE_FRAMES, "%d" % crossed,
		crossed >= 0 and crossed < BANK_PROBE_FRAMES)
	_assert("P5_mouse_stays_on_ground", "airborne = 0", "%d" % airborne, airborne == 0)
	_assert("P5_mouse_no_penetration", "overlaps = 0", "%d" % pen, pen == 0)
	_assert("P5_mouse_kept_lane", "|x − %.2f| ≤ 0.05" % BANK_LANE_X, "x=%.3f" % p.x, absf(p.x - BANK_LANE_X) <= 0.05)


## 溪边缝隙：猫同车道进不去
func _p6_cat_blocked_at_creek_gap() -> void:
	await _spawn(_cat, Vector3(BANK_LANE_X, GROUND_TOP + _cat.capsule_half_height + 0.02, 17.0), 0.0)
	var reason_seen := "<none>"
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in 240:
		await physics_frame
		if _body.climb != null and not _body.climb.last_probe.is_empty():
			reason_seen = str(_body.climb.last_probe.get("reason", "<none>"))
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _wait(10)
	var p: Vector3 = _body.global_position
	var pen := _overlaps_world(0.005)
	print("MEASURE|P6_cat_creek_gap|end=(%.3f, %.3f, %.3f)|wall_north_face=%.2f|step_reason=%s|penetration=%d" % [
		p.x, p.y, p.z, BANK_NORTH_FACE, reason_seen, pen
	])
	_assert("P6_cat_moved_toward_gap", "z ≤ 16.5", "z=%.3f" % p.z, p.z <= 16.5)
	_assert("P6_cat_blocked_by_gap_width", "z ≥ %.1f（墙北面）" % BANK_NORTH_FACE, "z=%.3f" % p.z,
		p.z >= BANK_NORTH_FACE)
	_assert("P6_cat_step_reason", "blocked_after_raise", reason_seen, reason_seen == "blocked_after_raise")
	_assert("P6_cat_no_penetration", "overlaps = 0", "%d" % pen, pen == 0)


# ---------------------------------------------------------------------------
# 几何读取工具
# ---------------------------------------------------------------------------

func _box(nm: String) -> Dictionary:
	var sb := _world.get_node_or_null(nm) as StaticBody3D
	if sb == null:
		return {}
	var cs := sb.get_node_or_null("Shape") as CollisionShape3D
	var box := cs.shape as BoxShape3D if cs != null else null
	if box == null:
		return {}
	var c: Vector3 = sb.position
	var h := box.size * 0.5
	return {
		"top": c.y + h.y, "bottom": c.y - h.y,
		"min_x": c.x - h.x, "max_x": c.x + h.x,
		"min_z": c.z - h.z, "max_z": c.z + h.z,
	}


## Area3D 数据体量：返回中心/尺寸（世界坐标，关卡根在原点）
func _area(nm: String) -> Dictionary:
	var a := _world.get_node_or_null(nm) as Area3D
	if a == null:
		return {}
	var cs := a.get_node_or_null("Shape") as CollisionShape3D
	var box := cs.shape as BoxShape3D if cs != null else null
	if box != null:
		return {
			"cx": a.position.x, "cz": a.position.z, "size_x": box.size.x, "size_z": box.size.z,
			"min_x": a.position.x - box.size.x * 0.5, "max_x": a.position.x + box.size.x * 0.5,
			"min_z": a.position.z - box.size.z * 0.5, "max_z": a.position.z + box.size.z * 0.5,
		}
	return {}


func _region_rect(node: Node3D) -> Dictionary:
	var cs := node.get_node_or_null("Volume/Shape") as CollisionShape3D
	var box := cs.shape as BoxShape3D if cs != null else null
	if box == null:
		return {"id": node.name, "min_x": 0.0, "max_x": 0.0, "min_z": 0.0, "max_z": 0.0}
	var c: Vector3 = node.position
	var h := box.size * 0.5
	return {
		"id": node.get_meta("region_id", "?"),
		"min_x": c.x - h.x, "max_x": c.x + h.x, "min_z": c.z - h.z, "max_z": c.z + h.z,
	}


func _marker_pos(nm: String) -> Vector3:
	var m := _world.get_node_or_null(nm) as Marker3D
	return m.global_position if m != null else Vector3.ZERO


func _inside_region(p: Vector3, region_id: String) -> bool:
	var node := _world.get_node_or_null("Region_%s" % region_id) as Node3D
	if node == null:
		return false
	var r := _region_rect(node)
	return p.x >= r["min_x"] - GEO_EPS and p.x <= r["max_x"] + GEO_EPS \
		and p.z >= r["min_z"] - GEO_EPS and p.z <= r["max_z"] + GEO_EPS


func _count_collision_nodes(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is CollisionShape3D or ch is CollisionObject3D:
			c += 1
		c += _count_collision_nodes(ch)
	return c


# ---------------------------------------------------------------------------
# 物理查询工具
# ---------------------------------------------------------------------------

## 胶囊（按物种配置）放在 pos 处与世界静态几何的重叠数
## 胶囊（按物种配置）放在 pos 处与世界静态几何的重叠数。
## `shrink`：收紧探测胶囊（出生点本来就"正好站在地面上"，不收紧会把地面接触算成 1 次重叠）
func _capsule_hits_at(cfg: SpeciesConfig, pos: Vector3, shrink: float = 0.0) -> int:
	var cap := CapsuleShape3D.new()
	cap.radius = maxf(0.001, cfg.capsule_radius - shrink)
	cap.height = maxf(0.002, cfg.capsule_height() - shrink * 2.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = cap
	params.transform = Transform3D(Basis(), pos)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return _world.get_world_3d().direct_space_state.intersect_shape(params, 4).size()


## 两个轴对齐数据体量（x/z 平面）之间的空隙距离；重叠时为 0
func _area_gap(a: Dictionary, b: Dictionary) -> float:
	var dx: float = maxf(0.0, maxf(a["min_x"] - b["max_x"], b["min_x"] - a["max_x"]))
	var dz: float = maxf(0.0, maxf(a["min_z"] - b["max_z"], b["min_z"] - a["max_z"]))
	return sqrt(dx * dx + dz * dz)


## 走廊被挡的采样点数：从 from 到 to，每 0.1 m 一点，点在离地 height 处用半径 radius 的球
func _corridor_blocked(from: Vector3, to: Vector3, height: float, radius: float) -> int:
	var space := _world.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var seg := to - from
	var steps := int(maxf(1.0, seg.length() / 0.1))
	var blocked := 0
	for i in range(steps + 1):
		var p: Vector3 = from + seg * (float(i) / float(steps))
		p.y = GROUND_TOP + height
		params.transform = Transform3D(Basis(), p)
		if not space.intersect_shape(params, 1).is_empty():
			blocked += 1
	return blocked


func _sample_inside_area(a: String, b: String, area: String, step: float) -> float:
	var sample := _sample_segment(_marker_pos(a), _marker_pos(b), step)
	if sample.is_empty():
		return 0.0
	var info := _area(area)
	var inside := 0
	for p in sample:
		if p.x >= info["min_x"] and p.x <= info["max_x"] and p.z >= info["min_z"] and p.z <= info["max_z"]:
			inside += 1
	return float(inside) / float(sample.size())


func _sample_inside_any_cover(a: String, b: String, step: float) -> int:
	var sample := _sample_segment(_marker_pos(a), _marker_pos(b), step)
	var hits := 0
	for p in sample:
		for nm in COVER_NODES:
			var info := _area(nm)
			if p.x >= info["min_x"] and p.x <= info["max_x"] and p.z >= info["min_z"] and p.z <= info["max_z"]:
				hits += 1
				break
	return hits


func _sample_polyline_inside_area(nodes: Array, area: String, step: float) -> float:
	var all: Array = []
	for i in range(nodes.size() - 1):
		all.append_array(_sample_segment(_marker_pos(nodes[i]), _marker_pos(nodes[i + 1]), step))
	if all.is_empty():
		return 0.0
	var info := _area(area)
	var inside := 0
	for p in all:
		if p.x >= info["min_x"] and p.x <= info["max_x"] and p.z >= info["min_z"] and p.z <= info["max_z"]:
			inside += 1
	return float(inside) / float(all.size())


func _sample_polyline_cover_hits(nodes: Array, step: float) -> int:
	var hits := 0
	for i in range(nodes.size() - 1):
		hits += _sample_inside_any_cover(nodes[i], nodes[i + 1], step)
	return hits


func _sample_segment(a: Vector3, b: Vector3, step: float) -> Array:
	var out: Array = []
	var seg := b - a
	var n := int(maxf(1.0, seg.length() / step))
	for i in range(n + 1):
		out.append(a + seg * (float(i) / float(n)))
	return out


# ---------------------------------------------------------------------------
# 身体驱动工具（与 T009/T010 同一套：合成输入 + 等物理帧）
# ---------------------------------------------------------------------------

func _spawn(cfg: SpeciesConfig, pos: Vector3, yaw: float) -> void:
	_release_all()
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
		await process_frame
	_body = (load(BODY) as PackedScene).instantiate() as AnimalBody
	_body.species_config = cfg
	_body.player_controlled = true
	_world.add_child(_body)
	_body.global_position = pos
	_body.rotation = Vector3(0.0, yaw, 0.0)
	_body.velocity = Vector3.ZERO
	_body.climb.reset_base()
	for i in 180:
		await physics_frame
		if _body.is_on_floor():
			break
	_body.climb.update_base_y()
	await _wait(5)


func _wait(frames: int) -> void:
	for i in frames:
		await physics_frame


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "jump", "interact", "pounce"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _current_capsule_height() -> float:
	var cap := _body.shape_node.shape as CapsuleShape3D
	return cap.height if cap != null else 0.0


## 当前胶囊底部的世界高度（用于算跳跃净空）
func GroundBodyBottom() -> float:
	var cap := _body.shape_node.shape as CapsuleShape3D
	return _body.global_position.y - (cap.height * 0.5 if cap != null else 0.0)


## 当前胶囊与世界静态几何的重叠数（收缩 shrink 避免自己贴地被算重叠）
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


func _point_str(p: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [p.x, p.y, p.z]


# ---------------------------------------------------------------------------
# 断言与收尾
# ---------------------------------------------------------------------------

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
