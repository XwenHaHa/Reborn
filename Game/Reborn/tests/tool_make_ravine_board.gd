extends SceneTree
## ART09-E：生成「展板切片」演示关 `res://scenes/maps/l_ravine_board.tscn`。
##
## 为什么要另建一张关：`l_courtyard` 是玩法/回归关（T011–T027 的几何、碰撞、导航都在上面），
## 它的宏观构图（3 m 围墙 + 直线水带）本身就不是展板里的森林溪谷，继续往庭院里加装饰属无效迭代
## （见 `Docs/Evidence/ART08_ENVIRONMENT_BOARD.md`）。所以展板展示放进独立关卡：
##   - 零碰撞：全部是 MeshInstance3D / Node3D 装饰，没有 StaticBody3D、没有导航区；
##   - 零玩法：不建玩家、不挂 AI、不写任何状态，只做画面；
##   - 固定数组：位置/朝向全是常量，不用随机数，重跑得到同一张关。
##
## 高度一律以 `GROUND_TOP` 为基准：`tool_probe_aabb.gd` 实测所有 glb 的原点都在**脚底**
## （min_y = 0.000），所以摆件只需 `pos + Vector3(0, GROUND_TOP, 0)`，不要再"猜中心偏移"。
##
## 用法：
##   `& $g --headless --path $proj --script 'res://tests/tool_make_ravine_board.gd' --quit-after 60000`

const OUT := "res://scenes/maps/l_ravine_board.tscn"

const GROUND_SIZE := Vector3(46.0, 0.2, 50.0)
const GROUND_TOP := 0.10

## 溪流：横穿中景的一条带（镜头朝 −Z 看，水面在 z≈−2.6；宽 16 m、进深 4.6 m）
const CREEK_CENTER := Vector3(2.4, 0.12, -2.6)
const CREEK_SIZE := Vector3(16.0, 0.03, 4.6)
const CREEK_BED_SIZE := Vector3(16.0, 0.02, 5.0)

## 岩石：前中后三档，前档做遮挡、中档做落点、后档做轮廓
const BOULDERS := [
	{"pos": Vector3(-3.4, 0.0, 1.2), "yaw": 24.0, "scale": 1.50},
	{"pos": Vector3(2.6, 0.0, -0.6), "yaw": -37.0, "scale": 1.15},
	{"pos": Vector3(6.4, 0.0, -3.2), "yaw": 118.0, "scale": 0.85},
	{"pos": Vector3(-7.2, 0.0, -4.0), "yaw": 63.0, "scale": 1.10},
	{"pos": Vector3(0.9, 0.0, -6.2), "yaw": -12.0, "scale": 0.95},
]

## 草丛/芦苇：近景沿溪 5 团（小），中远景背景 5 团（大，用来分层次）
const BUSHES := [
	{"pos": Vector3(-2.6, 0.0, 0.2), "yaw": 20.0, "scale": 0.55},
	{"pos": Vector3(5.2, 0.0, -0.4), "yaw": 200.0, "scale": 0.50},
	{"pos": Vector3(8.4, 0.0, -3.6), "yaw": 80.0, "scale": 0.45},
	{"pos": Vector3(-5.4, 0.0, -1.4), "yaw": 140.0, "scale": 0.52},
	{"pos": Vector3(1.6, 0.0, -5.0), "yaw": 300.0, "scale": 0.46},
	{"pos": Vector3(-9.0, 0.0, -8.4), "yaw": 40.0, "scale": 0.78},
	{"pos": Vector3(-4.2, 0.0, -9.6), "yaw": 150.0, "scale": 0.82},
	{"pos": Vector3(3.0, 0.0, -10.2), "yaw": 260.0, "scale": 0.80},
	{"pos": Vector3(7.6, 0.0, -8.6), "yaw": 15.0, "scale": 0.74},
	{"pos": Vector3(11.0, 0.0, -7.0), "yaw": 95.0, "scale": 0.68},
]

## 溪岸泥舌：贴在水陆交界，把直边水岸遮成弯岸线
const MUD_TONGUES := [
	{"pos": Vector3(-4.6, 0.0, -0.2), "size": Vector2(3.0, 1.0)},
	{"pos": Vector3(-0.6, 0.0, -0.4), "size": Vector2(2.6, 0.9)},
	{"pos": Vector3(4.0, 0.0, -4.8), "size": Vector2(2.8, 0.95)},
	{"pos": Vector3(7.6, 0.0, -4.6), "size": Vector2(2.4, 0.85)},
]

## 树根洞口（中景焦点）+ 后面那道盘根屏障
const ROOT_HOLE_POS := Vector3(-1.6, 0.0, -5.4)
const ROOT_BARRIER_POS := Vector3(-1.6, 0.0, -6.2)
const ROOT_BARRIER_TILES := 6
const ROOT_BARRIER_MOD_LEN := 2.461093

## 远景框景：低石墙（左）+ 围栏（右），做成"被林间小路夹住"的通道感
const WALL_SPOTS := [
	{"pos": Vector3(-9.6, 0.0, -8.2), "yaw": 8.0},
	{"pos": Vector3(-7.2, 0.0, -8.8), "yaw": 16.0},
	{"pos": Vector3(-4.8, 0.0, -9.2), "yaw": 4.0},
]
const FENCE_SPOTS := [
	{"pos": Vector3(4.6, 0.0, -9.4), "yaw": -6.0},
	{"pos": Vector3(8.2, 0.0, -8.8), "yaw": -14.0},
]

## 庇护棚（中景左）：4 根立柱 + 棚顶 + 土墩
const SHELTER_AT := Vector3(-10.6, 0.0, -7.2)
const SHELTER_POST_H := 1.620

## 近景补件：脚边小石头 / 贴地草丛（展板前景不是一片空地）
const NEAR_ROCKS := [
	{"pos": Vector3(-2.2, 0.0, 2.2), "yaw": 12.0, "scale": 0.34},
	{"pos": Vector3(1.4, 0.0, 1.8), "yaw": 77.0, "scale": 0.28},
	{"pos": Vector3(3.6, 0.0, 2.6), "yaw": 155.0, "scale": 0.32},
	{"pos": Vector3(-1.0, 0.0, 3.4), "yaw": 210.0, "scale": 0.22},
]
const NEAR_BUSHES := [
	{"pos": Vector3(-2.9, 0.0, 2.9), "yaw": 30.0, "scale": 0.30},
	{"pos": Vector3(2.2, 0.0, 3.3), "yaw": 250.0, "scale": 0.26},
	{"pos": Vector3(0.6, 0.0, 4.2), "yaw": 120.0, "scale": 0.24},
]

const GROUND_SHADER := "res://shaders/ground.gdshader"
const WATER_SHADER := "res://shaders/creek_water.gdshader"
const GRASS_WIND_SHADER := "res://shaders/grass_wind.gdshader"
const BOULDER_ASSET := "res://assets/environment/sm_boulder_001.glb"
const BUSH_ASSET := "res://assets/environment/sm_bush_002.glb"
const ROOT_HOLE_ASSET := "res://assets/environment/sm_root_hole_001.glb"
const ROOT_BARRIER_ASSET := "res://assets/environment/sm_root_barrier_001.glb"
const WALL_LOW_ASSET := "res://assets/environment/sm_wall_low_001.glb"
const FENCE_ASSET := "res://assets/environment/sm_fence_module_001.glb"
const SHELTER_POST_ASSET := "res://assets/environment/sm_shelter_post_001.glb"
const ROOF_ASSET := "res://assets/environment/sm_roof_001.glb"
const MOUND_ASSET := "res://assets/environment/sm_mound_001.glb"
const SKY_HDRI_PATH := "res://assets/environment/hdri/mossy_forest_2k.hdr"

## 第三人称机位的站位锚点（`tool_capture_art09_board.gd` 用它放主体）
const SUBJECT_ANCHOR := Vector3(0.0, 0.10, 2.4)


func _initialize() -> void:
	var node := Node3D.new()
	node.name = "RavineBoard"
	_add_ground(node)
	_add_creek(node)
	_add_shores(node)
	_add_rocks(node)
	_add_foliage(node)
	_add_root_hole(node)
	_add_far_frames(node)
	_add_near_clutter(node)
	_add_light_and_env(node)
	_add_subject_anchor(node)
	var out := PackedScene.new()
	if out.pack(node) != OK:
		print("TOOL|ERROR|pack_failed")
		node.free()
		quit(1)
		return
	var err := ResourceSaver.save(out, OUT)
	print("TOOL|save_result=%d (%s)|path=%s" % [err, "OK" if err == OK else "FAIL", OUT])
	node.free()
	quit(0 if err == OK else 1)


# ---------------------------------------------------------------------------
# 地面 / 溪流 / 岸线
# ---------------------------------------------------------------------------

func _add_ground(parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	var bm := BoxMesh.new()
	bm.size = GROUND_SIZE
	mi.mesh = bm
	mi.position = Vector3(0.0, GROUND_TOP - GROUND_SIZE.y * 0.5, 0.0)
	var shader_res := load(GROUND_SHADER) as Shader
	if shader_res != null:
		var smat := ShaderMaterial.new()
		smat.shader = shader_res
		# 近景机位要看到"草/土/枯草"的斑块：庭院那套低频斑块（0.09）在这里会糊成一整片绿
		smat.set_shader_parameter(&"patch_scale", 0.34)
		smat.set_shader_parameter(&"grain_strength", 0.18)
		smat.set_shader_parameter(&"contrast", 0.62)
		smat.set_shader_parameter(&"color_grass", Color(0.196, 0.235, 0.168))
		smat.set_shader_parameter(&"color_dirt", Color(0.247, 0.216, 0.176))
		smat.set_shader_parameter(&"color_dry", Color(0.298, 0.286, 0.204))
		mi.material_override = smat
	parent.add_child(mi)
	mi.owner = parent

	var bed := MeshInstance3D.new()
	bed.name = "CreekBed"
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = CREEK_BED_SIZE
	bed.mesh = bed_mesh
	bed.position = Vector3(CREEK_CENTER.x, GROUND_TOP + 0.005, CREEK_CENTER.z)
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = Color(0.238, 0.220, 0.196)
	bed_mat.roughness = 0.95
	bed.material_override = bed_mat
	parent.add_child(bed)
	bed.owner = parent
	print("TOOL|Ground|size=%s|top=%.3f" % [GROUND_SIZE, GROUND_TOP])


func _add_creek(parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "CreekWater"
	# 展示关用 **PlaneMesh**（薄片）：BoxMesh 的侧壁在近景会被看穿成"水池挡板"（实测截图）
	var pm := PlaneMesh.new()
	pm.size = Vector2(CREEK_SIZE.x, CREEK_SIZE.z)
	mi.mesh = pm
	mi.position = CREEK_CENTER
	var shader_res := load(WATER_SHADER) as Shader
	if shader_res != null:
		var smat := ShaderMaterial.new()
		smat.shader = shader_res
		smat.set_shader_parameter(&"shallow_color", Color(0.216, 0.412, 0.451))
		smat.set_shader_parameter(&"deep_color", Color(0.075, 0.176, 0.208))
		smat.set_shader_parameter(&"foam_color", Color(0.800, 0.850, 0.860))
		smat.set_shader_parameter(&"flow_dir", Vector2(-0.94, 0.34))
		smat.set_shader_parameter(&"flow_speed", 0.38)
		smat.set_shader_parameter(&"ripple_scale", 3.0)
		smat.set_shader_parameter(&"ripple_strength", 0.30)
		smat.set_shader_parameter(&"base_alpha", 0.55)
		mi.material_override = smat
		print("TOOL|Creek|water=shader|%s" % WATER_SHADER)
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.20, 0.45, 0.65, 0.60)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.15
		mi.material_override = mat
		print("TOOL|Creek|water=FALLBACK_STATIC")
	mi.set_meta("water_depth", CREEK_SIZE.y)
	mi.add_to_group("water_bodies", true)
	parent.add_child(mi)
	mi.owner = parent


func _add_shores(parent: Node3D) -> void:
	var i := 0
	for spot in MUD_TONGUES:
		i += 1
		var size: Vector2 = spot["size"]
		var mi := MeshInstance3D.new()
		mi.name = "MudTongue%d" % i
		var bm := BoxMesh.new()
		bm.size = Vector3(size.x, 0.05, size.y)
		mi.mesh = bm
		mi.position = (spot["pos"] as Vector3) + Vector3(0.0, GROUND_TOP + 0.004, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.196, 0.180, 0.157)
		mat.roughness = 0.92
		mi.material_override = mat
		parent.add_child(mi)
		mi.owner = parent
	print("TOOL|Shore|mud_tongues=%d" % i)


# ---------------------------------------------------------------------------
# 岩石 / 植被
# ---------------------------------------------------------------------------

func _add_rocks(parent: Node3D) -> void:
	if not ResourceLoader.exists(BOULDER_ASSET):
		print("TOOL|ERROR|boulder_missing|%s" % BOULDER_ASSET)
		return
	var boulder: PackedScene = load(BOULDER_ASSET) as PackedScene
	var i := 0
	for spot in BOULDERS:
		i += 1
		var inst: Node3D = boulder.instantiate() as Node3D
		inst.name = "BoardBoulder%d" % i
		inst.position = (spot["pos"] as Vector3) + Vector3(0.0, GROUND_TOP, 0.0)
		inst.rotation_degrees = Vector3(0.0, float(spot["yaw"]), 0.0)
		inst.scale = Vector3.ONE * float(spot["scale"])
		parent.add_child(inst)
		inst.owner = parent
	print("TOOL|Rocks|boulders=%d" % i)


func _add_foliage(parent: Node3D) -> void:
	if not ResourceLoader.exists(BUSH_ASSET):
		print("TOOL|ERROR|bush_missing|%s" % BUSH_ASSET)
		return
	var bush: PackedScene = load(BUSH_ASSET) as PackedScene
	var i := 0
	var wind := 0
	for spot in BUSHES:
		i += 1
		var inst: Node3D = bush.instantiate() as Node3D
		inst.name = "BoardBush%d" % i
		inst.position = (spot["pos"] as Vector3) + Vector3(0.0, GROUND_TOP, 0.0)
		inst.rotation_degrees = Vector3(0.0, float(spot["yaw"]), 0.0)
		inst.scale = Vector3.ONE * float(spot["scale"])
		parent.add_child(inst)
		inst.owner = parent
		if _apply_grass_wind(inst):
			wind += 1
	print("TOOL|Foliage|bushes=%d|grass_wind=%d" % [i, wind])


## 给草丛的叶片表面换风摆 shader（与庭院同一套做法：只替换名字含 leaf 的材质槽）
func _apply_grass_wind(inst: Node3D) -> bool:
	var shader_res := load(GRASS_WIND_SHADER) as Shader
	if shader_res == null:
		return false
	var mi := _find_first_mesh(inst)
	if mi == null or mi.mesh == null:
		return false
	var applied := 0
	for i in mi.mesh.get_surface_count():
		var base_mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
		if base_mat == null:
			continue
		if not "leaf" in String(base_mat.resource_name).to_lower():
			continue
		var wm := ShaderMaterial.new()
		wm.shader = shader_res
		wm.set_shader_parameter(&"albedo_color", base_mat.albedo_color)
		wm.set_shader_parameter(&"roughness_value", base_mat.roughness)
		mi.set_surface_override_material(i, wm)
		applied += 1
	return applied > 0


func _find_first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for child in n.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# 树根洞口 / 远景框景 / 近景补件
# ---------------------------------------------------------------------------

func _add_root_hole(parent: Node3D) -> void:
	if ResourceLoader.exists(ROOT_HOLE_ASSET):
		var hole: PackedScene = load(ROOT_HOLE_ASSET) as PackedScene
		var inst: Node3D = hole.instantiate() as Node3D
		inst.name = "BoardRootHole"
		inst.position = ROOT_HOLE_POS + Vector3(0.0, GROUND_TOP, 0.0)
		inst.rotation_degrees = Vector3(0.0, 12.0, 0.0)
		parent.add_child(inst)
		inst.owner = parent
		print("TOOL|RootHole|pos=%s" % ROOT_HOLE_POS)
	else:
		print("TOOL|ERROR|root_hole_missing|%s" % ROOT_HOLE_ASSET)

	if not ResourceLoader.exists(ROOT_BARRIER_ASSET):
		print("TOOL|ERROR|root_barrier_missing|%s" % ROOT_BARRIER_ASSET)
		return
	var barrier: PackedScene = load(ROOT_BARRIER_ASSET) as PackedScene
	var span := ROOT_BARRIER_MOD_LEN * float(ROOT_BARRIER_TILES)
	var start_x := ROOT_BARRIER_POS.x - span * 0.5
	for i in ROOT_BARRIER_TILES:
		var inst: Node3D = barrier.instantiate() as Node3D
		inst.name = "BoardRootBarrier%d" % (i + 1)
		inst.position = Vector3(start_x + ROOT_BARRIER_MOD_LEN * (float(i) + 0.5),
			ROOT_BARRIER_POS.y + GROUND_TOP, ROOT_BARRIER_POS.z)
		inst.rotation_degrees = Vector3(0.0, 180.0 if i % 2 == 1 else 0.0, 0.0)
		parent.add_child(inst)
		inst.owner = parent
	print("TOOL|RootBarrier|tiles=%d|span=%.2f" % [ROOT_BARRIER_TILES, span])


func _add_far_frames(parent: Node3D) -> void:
	var walls := 0
	if ResourceLoader.exists(WALL_LOW_ASSET):
		var ps: PackedScene = load(WALL_LOW_ASSET) as PackedScene
		for spot in WALL_SPOTS:
			walls += 1
			var inst: Node3D = ps.instantiate() as Node3D
			inst.name = "BoardWall%d" % walls
			inst.position = (spot["pos"] as Vector3) + Vector3(0.0, GROUND_TOP, 0.0)
			inst.rotation_degrees = Vector3(0.0, float(spot["yaw"]), 0.0)
			parent.add_child(inst)
			inst.owner = parent
	var fences := 0
	if ResourceLoader.exists(FENCE_ASSET):
		var ps: PackedScene = load(FENCE_ASSET) as PackedScene
		for spot in FENCE_SPOTS:
			fences += 1
			var inst: Node3D = ps.instantiate() as Node3D
			inst.name = "BoardFence%d" % fences
			inst.position = (spot["pos"] as Vector3) + Vector3(0.0, GROUND_TOP, 0.0)
			inst.rotation_degrees = Vector3(0.0, float(spot["yaw"]), 0.0)
			parent.add_child(inst)
			inst.owner = parent
	_add_shelter(parent)
	print("TOOL|FarFrames|walls=%d|fences=%d" % [walls, fences])


func _add_shelter(parent: Node3D) -> void:
	var posts := 0
	if ResourceLoader.exists(SHELTER_POST_ASSET):
		var ps: PackedScene = load(SHELTER_POST_ASSET) as PackedScene
		for offset in [Vector3(-1.55, 0.0, -1.65), Vector3(1.55, 0.0, -1.65),
				Vector3(-1.55, 0.0, 1.65), Vector3(1.55, 0.0, 1.65)]:
			posts += 1
			var inst: Node3D = ps.instantiate() as Node3D
			inst.name = "BoardShelterPost%d" % posts
			inst.position = SHELTER_AT + offset + Vector3(0.0, GROUND_TOP, 0.0)
			parent.add_child(inst)
			inst.owner = parent
	if ResourceLoader.exists(ROOF_ASSET):
		var roof_ps: PackedScene = load(ROOF_ASSET) as PackedScene
		var roof: Node3D = roof_ps.instantiate() as Node3D
		roof.name = "BoardShelterRoof"
		# 棚顶原点在板底：坐在立柱顶面（1.62 m）上
		roof.position = SHELTER_AT + Vector3(0.0, GROUND_TOP + SHELTER_POST_H, 0.0)
		parent.add_child(roof)
		roof.owner = parent
	if ResourceLoader.exists(MOUND_ASSET):
		var mound_ps: PackedScene = load(MOUND_ASSET) as PackedScene
		var mound: Node3D = mound_ps.instantiate() as Node3D
		mound.name = "BoardShelterMound"
		mound.position = SHELTER_AT + Vector3(0.0, GROUND_TOP, 0.6)
		parent.add_child(mound)
		mound.owner = parent
	print("TOOL|Shelter|posts=%d|at=%s" % [posts, SHELTER_AT])


func _add_near_clutter(parent: Node3D) -> void:
	var shore := MeshInstance3D.new()
	shore.name = "WetShore"
	var sm := BoxMesh.new()
	sm.size = Vector3(CREEK_SIZE.x, 0.03, 0.55)
	shore.mesh = sm
	shore.position = Vector3(CREEK_CENTER.x, GROUND_TOP + 0.006,
		CREEK_CENTER.z + CREEK_SIZE.z * 0.5 + 0.20)
	var shore_mat := StandardMaterial3D.new()
	shore_mat.albedo_color = Color(0.145, 0.133, 0.114)
	shore_mat.roughness = 0.72
	shore.material_override = shore_mat
	parent.add_child(shore)
	shore.owner = parent

	var rocks := 0
	if ResourceLoader.exists(BOULDER_ASSET):
		var ps: PackedScene = load(BOULDER_ASSET) as PackedScene
		for spot in NEAR_ROCKS:
			rocks += 1
			var inst: Node3D = ps.instantiate() as Node3D
			inst.name = "NearRock%d" % rocks
			inst.position = (spot["pos"] as Vector3) + Vector3(0.0, GROUND_TOP, 0.0)
			inst.rotation_degrees = Vector3(0.0, float(spot["yaw"]), 0.0)
			inst.scale = Vector3.ONE * float(spot["scale"])
			parent.add_child(inst)
			inst.owner = parent
	var bushes := 0
	if ResourceLoader.exists(BUSH_ASSET):
		var ps: PackedScene = load(BUSH_ASSET) as PackedScene
		for spot in NEAR_BUSHES:
			bushes += 1
			var inst: Node3D = ps.instantiate() as Node3D
			inst.name = "NearBush%d" % bushes
			inst.position = (spot["pos"] as Vector3) + Vector3(0.0, GROUND_TOP, 0.0)
			inst.rotation_degrees = Vector3(0.0, float(spot["yaw"]), 0.0)
			inst.scale = Vector3.ONE * float(spot["scale"])
			parent.add_child(inst)
			inst.owner = parent
			_apply_grass_wind(inst)
	print("TOOL|NearClutter|rocks=%d|bushes=%d" % [rocks, bushes])


# ---------------------------------------------------------------------------
# 光照与后处理
# ---------------------------------------------------------------------------

func _add_light_and_env(parent: Node3D) -> void:
	# 暖色低角度主光：展板的侧逆光来自画面右上，阴影拉长在前景
	var sun := DirectionalLight3D.new()
	sun.name = "BoardSun"
	sun.rotation_degrees = Vector3(-24.0, 32.0, 0.0)
	sun.light_color = Color(1.0, 0.90, 0.72)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.03
	parent.add_child(sun)
	sun.owner = parent

	# 冷色天光补光：不投影，只把背光面抬起来
	var fill := DirectionalLight3D.new()
	fill.name = "BoardSkyFill"
	fill.basis = Basis.looking_at(Vector3(0.15, -0.55, -0.82))
	fill.light_color = Color(0.62, 0.72, 0.88)
	fill.light_energy = 0.38
	fill.shadow_enabled = false
	parent.add_child(fill)
	fill.owner = parent

	var env := Environment.new()
	var sky := Sky.new()
	var hdri := load(SKY_HDRI_PATH) as Texture2D
	if hdri != null:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = hdri
		sky.sky_material = pano
		print("TOOL|Env|sky=panorama|%s" % SKY_HDRI_PATH)
	else:
		var pm := ProceduralSkyMaterial.new()
		pm.ground_horizon_color = Color(0.62, 0.66, 0.70)
		pm.ground_bottom_color = Color(0.52, 0.55, 0.58)
		sky.sky_material = pm
		print("TOOL|Env|sky=procedural|hdri_missing")
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 2.4
	env.ssao_power = 2.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 1.0
	# 空气透视：近景 9 m 内零影响，远景（石墙/围栏）淡下去做层次
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.68, 0.74, 0.78)
	env.fog_light_energy = 0.85
	env.fog_density = 0.85
	env.fog_sky_affect = 0.10
	env.fog_depth_begin = 9.0
	env.fog_depth_end = 46.0
	env.fog_depth_curve = 1.0
	# 展板的高光是"太阳边上发亮"，给一点点辉光就够，不做整屏泛白
	env.glow_enabled = true
	env.glow_intensity = 0.30
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.10
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)
	we.owner = parent
	print("TOOL|Env|ssao=%s|fog=%.0f..%.0f|tonemap=%d|exposure=%.2f|glow=%s" % [
		str(env.ssao_enabled), env.fog_depth_begin, env.fog_depth_end,
		env.tonemap_mode, env.tonemap_exposure, str(env.glow_enabled),
	])


## 主体站位锚点：第三人称取证时把猫放在这里（面向 −Z / 溪谷）
func _add_subject_anchor(parent: Node3D) -> void:
	var marker := Marker3D.new()
	marker.name = "BoardSubjectAnchor"
	marker.position = SUBJECT_ANCHOR
	parent.add_child(marker)
	marker.owner = parent
	print("TOOL|Anchor|subject=%s" % SUBJECT_ANCHOR)
