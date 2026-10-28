extends SceneTree
## ART09 阶段 E 契约：展板切片关 `l_ravine_board.tscn` 的结构与后处理。
##
## 检查三件事：
##   1. 它是**纯展示关**：零碰撞、零导航区、不挂 AI —— 不会污染玩法；
##   2. 后处理与光照**真的在场景里**（HDRI 天空球 + SSAO + ACES + 深度雾 + 暖主光）；
##   3. 装饰件数量达标（巨石/草丛/泥舌/远景框景/近景补件），不是空场景。
##
## 运行：`godot --headless --path <proj> --script 'res://tests/run_art09_frame_contract.gd' --quit-after 60000`

const LEVEL := "res://scenes/maps/l_ravine_board.tscn"
const MAIN := "res://scenes/core/main.tscn"

var _checks := 0
var _fails := 0

func _initialize() -> void:
	_run()


func _run() -> void:
	var packed := load(LEVEL) as PackedScene
	_check("level_loads", packed != null)
	if packed == null:
		_finish()
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	for i in 4:
		await process_frame
	_check("root_named_ravine_board", level.name == "RavineBoard")

	# --- 纯展示：没有碰撞体、没有导航区 ---
	_check("no_static_body", _count_type(level, "StaticBody3D") == 0)
	_check("no_collision_shape", _count_type(level, "CollisionShape3D") == 0)
	_check("no_navigation_region", _count_type(level, "NavigationRegion3D") == 0)
	_check("no_resources_playable", _count_type(level, "ResourcePoint") == 0)

	# --- 后处理 ---
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_check("world_environment_exists", we != null and we.environment != null)
	if we != null and we.environment != null:
		var env := we.environment
		_check("env_background_sky", env.background_mode == Environment.BG_SKY)
		_check("env_sky_present", env.sky != null)
		_check("env_tonemap_aces", env.tonemap_mode == Environment.TONE_MAPPER_ACES)
		_check("env_ssao_on", env.ssao_enabled)
		_check("env_fog_depth", env.fog_enabled and env.fog_mode == Environment.FOG_MODE_DEPTH)
		_check("env_fog_starts_near", env.fog_depth_begin >= 6.0 and env.fog_depth_begin <= 14.0)
		_check("env_exposure_in_range", env.tonemap_exposure >= 0.95 and env.tonemap_exposure <= 1.2)
		var sky_mat := env.sky.sky_material
		_check("env_sky_is_panorama", sky_mat is PanoramaSkyMaterial)
		print("FRAME_CONTRACT|env|tonemap=%d|ssao=%s|fog=%.0f..%.0f|exposure=%.2f|sky=%s" % [
			env.tonemap_mode, str(env.ssao_enabled), env.fog_depth_begin,
			env.fog_depth_end, env.tonemap_exposure,
			"panorama" if sky_mat is PanoramaSkyMaterial else "procedural",
		])

	# --- 光照 ---
	var sun := level.get_node_or_null("BoardSun") as DirectionalLight3D
	_check("warm_sun_exists", sun != null)
	if sun != null:
		_check("sun_shadows_on", sun.shadow_enabled)
		_check("sun_is_warm", sun.light_color.r > sun.light_color.b + 0.15)
		_check("sun_energy_reasonable", sun.light_energy >= 1.0 and sun.light_energy <= 2.0)
		print("FRAME_CONTRACT|sun|energy=%.2f|color=%s|rot=%s" % [
			sun.light_energy, sun.light_color, sun.rotation_degrees,
		])
	_check("sky_fill_exists", level.get_node_or_null("BoardSkyFill") != null)

	# --- 水 ---
	var water := level.get_node_or_null("CreekWater") as MeshInstance3D
	_check("creek_water_exists", water != null)
	if water != null:
		_check("creek_water_is_plane", water.mesh is PlaneMesh)
		_check("creek_water_group", water.is_in_group("water_bodies"))
		_check("creek_water_no_collision", _count_type(water, "CollisionShape3D") == 0)
		_check("creek_water_shader", water.material_override is ShaderMaterial)

	# --- 装饰件数量 ---
	var counts := {
		"boulders": _count_prefix(level, "BoardBoulder"),
		"bushes": _count_prefix(level, "BoardBush"),
		"mud_tongues": _count_prefix(level, "MudTongue"),
		"root_barrier": _count_prefix(level, "BoardRootBarrier"),
		"walls": _count_prefix(level, "BoardWall"),
		"fences": _count_prefix(level, "BoardFence"),
		"shelter_posts": _count_prefix(level, "BoardShelterPost"),
		"near_rocks": _count_prefix(level, "NearRock"),
		"near_bushes": _count_prefix(level, "NearBush"),
	}
	print("FRAME_CONTRACT|counts|%s" % str(counts))
	_check("boulders_at_least_5", int(counts["boulders"]) >= 5)
	_check("bushes_at_least_10", int(counts["bushes"]) >= 10)
	_check("mud_tongues_at_least_4", int(counts["mud_tongues"]) >= 4)
	_check("root_barrier_tiled", int(counts["root_barrier"]) >= 4)
	_check("far_frames_present", int(counts["walls"]) >= 2 and int(counts["fences"]) >= 1)
	_check("shelter_posts_4", int(counts["shelter_posts"]) == 4)
	_check("near_clutter_present",
		int(counts["near_rocks"]) >= 3 and int(counts["near_bushes"]) >= 2)
	_check("root_hole_visible", level.get_node_or_null("BoardRootHole") != null)
	_check("ground_exists", level.get_node_or_null("Ground") != null)
	_check("creek_bed_exists", level.get_node_or_null("CreekBed") != null)
	_check("wet_shore_exists", level.get_node_or_null("WetShore") != null)
	var mesh_total := _count_type(level, "MeshInstance3D")
	print("FRAME_CONTRACT|meshes=%d" % mesh_total)
	_check("mesh_density", mesh_total >= 40)

	# --- 主体锚点（第三人称取证用）---
	var anchor := level.get_node_or_null("BoardSubjectAnchor") as Marker3D
	_check("subject_anchor_exists", anchor != null)
	if anchor != null:
		_check("subject_anchor_position",
			absf(anchor.position.x) <= 0.5 and absf(anchor.position.z - 2.4) <= 0.5)

	# --- 正式流程没被改：main.tscn 不引用这张关 ---
	var f := FileAccess.open(MAIN, FileAccess.READ)
	var main_text := f.get_as_text() if f != null else ""
	if f != null:
		f.close()
	_check("main_scene_untouched", main_text.length() > 0 and not main_text.contains("ravine"))

	level.queue_free()
	for i in 2:
		await process_frame
	_finish()


func _count_type(n: Node, type_name: String) -> int:
	var total := 1 if _is_type(n, type_name) else 0
	for child in n.get_children():
		total += _count_type(child, type_name)
	return total


func _is_type(n: Node, type_name: String) -> bool:
	match type_name:
		"StaticBody3D":
			return n is StaticBody3D
		"CollisionShape3D":
			return n is CollisionShape3D
		"NavigationRegion3D":
			return n is NavigationRegion3D
		"MeshInstance3D":
			return n is MeshInstance3D
		"ResourcePoint":
			return n is Area3D and String(n.name).begins_with("ResourcePoint")
		_:
			return false


func _count_prefix(n: Node, prefix: String) -> int:
	var total := 1 if String(n.name).begins_with(prefix) else 0
	for child in n.get_children():
		total += _count_prefix(child, prefix)
	return total


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s" % [label, "PASS" if ok else "FAIL"])


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
