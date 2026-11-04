class_name PlacementSafety
## T040：位置合法性与回退（**纯静态工具**，不持有节点状态）。
##
## 合法定义（`Docs/Tasks/T040.md` D3）：
##   有限坐标 + 在某个 `level_regions` 区域内（账本已初始化时）+ 距该物种导航层最近点 ≤ 0.60 m
##   + 不在 `water_bodies` 的水平投影内 + 胶囊（玩家中心为原点）不与 `world_static`（层 1）重叠。
##
## 回退顺序：最近合法的环上点（1/2/4/8 m，同区域）→ 原区域中心 → 物种出生标记 → 原点上空。
## **合法输入原样返回**（不强行吸附 y，保住 T037 的精确 transform 语义）。

const SNAP_TOLERANCE := 0.60
const WORLD_STATIC_LAYER := 1
const PROBE_RING_RADII: Array[float] = [1.0, 2.0, 4.0, 8.0]
const PROBE_RING_STEPS := 8


## 按物种自己的导航层吸附（Godot 4.7.2 的 `map_get_closest_point()` 不带层 → 用 trivial 路径代替）。
static func nav_snap(context: Node3D, cfg: SpeciesConfig, point: Vector3) -> Vector3:
	if context == null or cfg == null:
		return point
	var world := context.get_world_3d()
	if world == null:
		return point
	var map := world.get_navigation_map()
	if not map.is_valid():
		return point
	var p: PackedVector3Array = NavigationServer3D.map_get_path(
		map, point, point + Vector3(0.05, 0.0, 0.0), true, maxi(1, nav_layer_for(context, cfg.species_id)))
	if p.size() >= 1:
		return p[0]
	return Vector3(INF, INF, INF)


## 物种导航层：从关卡里的 `NavigationRegion3D.metadata/species_id` 反查。
static func nav_layer_for(context: Node3D, species_id: StringName) -> int:
	if context == null:
		return 1
	var root: Node = context.get_tree().root if context.is_inside_tree() else context
	return _find_layer(root, species_id)


static func _find_layer(node: Node, species_id: StringName) -> int:
	if node is NavigationRegion3D:
		var reg := node as NavigationRegion3D
		if StringName(reg.get_meta("species_id", &"")) == species_id:
			return maxi(1, reg.navigation_layers)
	for child in node.get_children():
		var layer := _find_layer(child, species_id)
		if layer > 0:
			return layer
	return 1


## 完整合法性检查；`pos` 是身体原点（胶囊中心）。
static func is_legal(context: Node3D, cfg: SpeciesConfig, pos: Vector3) -> bool:
	if context == null or cfg == null or not _finite(pos):
		return false
	var wd := context.get_node_or_null("/root/WorldDirector")
	if wd != null and bool(wd.get("region_population_initialized")):
		if StringName(String(wd.call("region_id_at", pos))) == &"":
			return false
	if over_water(context, pos):
		return false
	if inside_static(context, cfg, pos):
		return false
	var snap := nav_snap(context, cfg, pos)
	if not _finite(snap):
		# `map_get_path()` 对任何查询都会返回**最近多边形点**，只有该层还没有已同步的
		# 导航区域时才返回空。因此“拿不到点”= 该物种导航层尚未就绪（启动首帧常见），
		# 不是“位置非法”。区域/水面/几何已通过 → 视为合法，避免把出生标记回退到原点。
		return true
	return snap.distance_to(pos) <= SNAP_TOLERANCE + 0.001


## 只查“水面/静态几何”，供已经吸附到导航面的 NPC 落点复用。
static func is_clear(context: Node3D, cfg: SpeciesConfig, pos: Vector3) -> bool:
	if context == null or cfg == null or not _finite(pos):
		return false
	return not over_water(context, pos) and not inside_static(context, cfg, pos)


## 玩家落点解析。`desired` 合法 → 原样返回；否则按 D3 顺序回退。
static func resolve_player_position(context: Node3D, cfg: SpeciesConfig,
		desired: Vector3) -> Dictionary:
	if context == null or cfg == null:
		return {"ok": false, "position": Vector3.ZERO, "reason": "no_context", "fallback": false}
	if _finite(desired) and is_legal(context, cfg, desired):
		var rid := _region_at(context, desired)
		return {"ok": true, "position": desired, "reason": "valid", "fallback": false,
			"region_id": rid, "desired": desired}
	var origin := _region_at(context, desired)
	var nearest := _nearest_ring_candidate(context, cfg, desired, origin)
	if not nearest.is_empty():
		nearest["fallback"] = true
		nearest["desired"] = desired
		return nearest
	if String(origin) != "":
		var center := _region_center(context, origin)
		var place := _snapped_center(context, cfg, center)
		if is_legal(context, cfg, place):
			return {"ok": true, "position": place, "reason": "region_center", "fallback": true,
				"region_id": String(origin), "desired": desired}
	var marker := spawn_marker(context, cfg)
	if _finite(marker) and is_legal(context, cfg, marker):
		return {"ok": true, "position": marker, "reason": "spawn_marker", "fallback": true,
			"region_id": _region_at(context, marker), "desired": desired}
	var origin_pos := Vector3(0.0, cfg.capsule_half_height + 0.10, 0.0)
	return {"ok": true, "position": origin_pos, "reason": "origin", "fallback": true,
		"region_id": _region_at(context, origin_pos), "desired": desired}


static func _nearest_ring_candidate(context: Node3D, cfg: SpeciesConfig, desired: Vector3,
		origin_region: StringName) -> Dictionary:
	var best := {}
	var best_d := INF
	for radius in PROBE_RING_RADII:
		for k in PROBE_RING_STEPS:
			var a := TAU * float(k) / float(PROBE_RING_STEPS)
			var raw := desired + Vector3(cos(a) * radius, 0.0, sin(a) * radius)
			var snap := nav_snap(context, cfg, raw)
			if not _finite(snap):
				continue
			var place := snap
			place.y = snap.y + cfg.capsule_half_height + 0.05
			if not is_legal(context, cfg, place):
				continue
			if String(origin_region) != "" and _region_at(context, place) != origin_region:
				continue
			var d := place.distance_to(desired)
			if d < best_d:
				best_d = d
				best = {"ok": true, "position": place, "reason": "nearest_nav",
					"region_id": String(_region_at(context, place))}
	if best.is_empty():
		return {}
	return best


static func _snapped_center(context: Node3D, cfg: SpeciesConfig, center: Vector3) -> Vector3:
	var snap := nav_snap(context, cfg, center)
	if not _finite(snap):
		return center
	var place := snap
	place.y = snap.y + cfg.capsule_half_height + 0.05
	return place


static func _region_at(context: Node3D, pos: Vector3) -> StringName:
	var wd := context.get_node_or_null("/root/WorldDirector")
	if wd == null or not bool(wd.get("region_population_initialized")):
		return &""
	return StringName(String(wd.call("region_id_at", pos)))


static func _region_center(context: Node3D, region_id: StringName) -> Vector3:
	var wd := context.get_node_or_null("/root/WorldDirector")
	if wd == null or not wd.has_method("region_center"):
		return Vector3.ZERO
	return wd.call("region_center", region_id)


static func spawn_marker(context: Node3D, cfg: SpeciesConfig) -> Vector3:
	for n in context.get_tree().get_nodes_in_group("spawn_points"):
		var m := n as Node3D
		if m == null:
			continue
		var s := StringName(m.get_meta("species", &""))
		if s == &"" or s == cfg.species_id:
			return m.global_position
	return Vector3(INF, INF, INF)


static func over_water(context: Node3D, pos: Vector3) -> bool:
	if context == null or not _finite(pos):
		return false
	for n in context.get_tree().get_nodes_in_group("water_bodies"):
		var m := n as MeshInstance3D
		if m == null:
			continue
		var aabb := m.get_aabb()
		var center := m.global_transform * aabb.get_center()
		var half := aabb.size * m.global_transform.basis.get_scale() * 0.5
		if absf(pos.x - center.x) <= half.x and absf(pos.z - center.z) <= half.z:
			return true
	return false


## 胶囊中心与 `world_static`（层 1）的查询；收缩 3/6 cm 避免把贴地误差判成重叠。
static func inside_static(context: Node3D, cfg: SpeciesConfig, pos: Vector3) -> bool:
	if context == null or cfg == null or not _finite(pos):
		return false
	var world := context.get_world_3d()
	if world == null:
		return false
	var space := world.direct_space_state
	if space == null:
		return false
	var probe := SphereShape3D.new()
	# 取上半身而不是整根胶囊：出生点允许胶囊底轻微压进地面（引擎会解算），
	# 但**墙体/树干**必须在躯干高度被挡住。
	probe.radius = maxf(0.02, mini(cfg.capsule_radius - 0.02, 0.18))
	var center := pos + Vector3(0.0, cfg.capsule_half_height * 0.6, 0.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = WORLD_STATIC_LAYER
	params.collide_with_bodies = true
	return not space.intersect_shape(params, 1).is_empty()


static func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
