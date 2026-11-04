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
const CREEK_BED_SIZE := Vector3(15.6, 0.02, 4.2)

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

## ART09-E-2：Poly Haven CC0 贴图（1K，diffuse + nor_gl + arm），登记在 `Docs/THIRD_PARTY_ASSETS.md` §9
const TEX_DIR := "res://assets/environment/tex/"
const TEX_PEBBLES_DIFF := TEX_DIR + "dry_river_pebbles_diff_1k.jpg"
const TEX_PEBBLES_NOR := TEX_DIR + "dry_river_pebbles_nor_gl_1k.jpg"
const TEX_PEBBLES_ARM := TEX_DIR + "dry_river_pebbles_arm_1k.jpg"
const TEX_FLOOR_DIFF := TEX_DIR + "forest_floor_diff_1k.jpg"
const TEX_FLOOR_NOR := TEX_DIR + "forest_floor_nor_gl_1k.jpg"
const TEX_FLOOR_ARM := TEX_DIR + "forest_floor_arm_1k.jpg"
## B 阶段（2026-11-02）选型胜出：leafy_grass（Poly Haven CC0，登记 §9）。
## 9 宫格短名单 + 同机位 4 变体对比 + vision 判读：小尺度苔藓/泥土/碎叶混合，
## 平铺重复隐蔽好、与 3D 草丛融合最佳、自带湿润感；forest_leaves_02 因大叶片
## 重复感与干燥秋叶性格落选（详见 Docs/Evidence/ART11_GROUND_TEXTURE.md）。
const TEX_GROUND_DIFF := TEX_DIR + "leafy_grass_diff_1k.jpg"
const TEX_GROUND_NOR := TEX_DIR + "leafy_grass_nor_gl_1k.jpg"
const TEX_GROUND_ARM := TEX_DIR + "leafy_grass_arm_1k.jpg"
const TEX_STONE_DIFF := TEX_DIR + "stone_wall_02_diff_1k.jpg"
const TEX_STONE_NOR := TEX_DIR + "stone_wall_02_nor_gl_1k.jpg"
const TEX_STONE_ARM := TEX_DIR + "stone_wall_02_arm_1k.jpg"

## 近景散布（确定性网格 + 抖动，不用随机数）
## ART10：96 → 128 株、单株 0.10–0.22 → 0.16–0.36——旧密度/尺度被判读
## "草的比例和密度与猫完全不匹配"（猫肩高 ~0.31 m，草却只有火柴大小）。
const SCATTER_GRASS := 128
const SCATTER_PEBBLE := 34
const SCATTER_BAND_X := Vector2(-7.0, 9.0)
const SCATTER_BAND_Z := Vector2(0.4, 9.0)
## 岸边泥板（取代上一版那条 16×0.55 的直板）
const SHORE_PLATE_COUNT := 14

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
	# 地面：优先 Poly Haven CC0 森林地表贴图（albedo + normal + ARM），缺失时退回程序化 shader
	# B 阶段（2026-11-02）：forest_floor（秋叶+砾石）→ leafy_grass（苔藓/泥土/碎叶小尺度混合）。
	# vision 建议：贴图近景有粉/紫灰色偏 → tint 把色偏往暖棕-苔绿拉（R/B 略压、G 相对抬高）。
	# 第 1 轮修正（tp 判读"高反光/像水面 + 平铺重复"）：roughness 0.96→1.0、uv 15x17→24x26
	# （小尺度贴图支持更密平铺，单 tile ~1.9 m，重复图案更难读出）。
	# ART13（2026-11-02）：远景平铺感 → 换 `ground.gdshader` 的**世界坐标双尺度混合**材质
	# （tile 1.9 m 与 5.4 m 两尺度 + ~17 m 低频噪声互混，打破 UV 平铺周期；无接缝、
	# 顶/侧面连续）。tint 与原 StandardMaterial3D 轮一致（0.82/0.88/0.74）。
	var shader_ground := load(GROUND_SHADER) as Shader
	var tex_d := load(TEX_GROUND_DIFF) as Texture2D
	var tex_n := load(TEX_GROUND_NOR) as Texture2D
	var tex_m := load(TEX_GROUND_ARM) as Texture2D
	if shader_ground != null and tex_d != null and tex_n != null and tex_m != null:
		var smat := ShaderMaterial.new()
		smat.shader = shader_ground
		smat.set_shader_parameter(&"tex_amount", 1.0)
		smat.set_shader_parameter(&"tex_albedo", tex_d)
		smat.set_shader_parameter(&"tex_normal", tex_n)
		smat.set_shader_parameter(&"tex_arm", tex_m)
		smat.set_shader_parameter(&"tex_tint", Color(0.82, 0.88, 0.74))
		smat.set_shader_parameter(&"tex_scale_a", Vector2(24.0 / 46.0, 26.0 / 50.0))
		smat.set_shader_parameter(&"tex_scale_b", Vector2(0.185, 0.185))
		smat.set_shader_parameter(&"grain_strength", 0.12)
		mi.material_override = smat
		print("TOOL|Ground|material=leafy_grass_2scale|tint=0.82,0.88,0.74|a=0.522,0.52|b=0.185")
	elif _make_tex_material(TEX_GROUND_DIFF, TEX_GROUND_NOR, TEX_GROUND_ARM,
			Vector2(24.0, 26.0), 1.0) != null:
		var floor_mat := _make_tex_material(TEX_GROUND_DIFF, TEX_GROUND_NOR, TEX_GROUND_ARM,
			Vector2(24.0, 26.0), 1.0)
		floor_mat.albedo_color = Color(0.82, 0.88, 0.74)
		floor_mat.uv1_scale = Vector3(24.0, 26.0, 1.0)
		mi.material_override = floor_mat
		print("TOOL|Ground|material=leafy_grass|tint=0.82,0.88,0.74|uv=24x26|rough=1.0")
	else:
		if shader_ground != null:
			var smat2 := ShaderMaterial.new()
			smat2.shader = shader_ground
			smat2.set_shader_parameter(&"patch_scale", 0.34)
			smat2.set_shader_parameter(&"grain_strength", 0.18)
			smat2.set_shader_parameter(&"contrast", 0.62)
			mi.material_override = smat2
			print("TOOL|Ground|material=shader_fallback")
	parent.add_child(mi)
	mi.owner = parent

	var bed := MeshInstance3D.new()
	bed.name = "CreekBed"
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = CREEK_BED_SIZE
	bed.mesh = bed_mesh
	bed.position = Vector3(CREEK_CENTER.x, GROUND_TOP + 0.005, CREEK_CENTER.z)
	var bed_mat := _make_tex_material(TEX_PEBBLES_DIFF, TEX_PEBBLES_NOR, TEX_PEBBLES_ARM,
		Vector2(10.0, 3.4), 0.92)
	if bed_mat != null:
		bed.material_override = bed_mat
		print("TOOL|CreekBed|material=dry_river_pebbles")
	else:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.238, 0.220, 0.196)
		plain.roughness = 0.95
		bed.material_override = plain
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
		# ART10 二轮调水：①泡沫带 (foam_width 0.09) 在 16 m 水面上铺出 ~1.4 m 宽的白边，
		# 把矩形水岸整个描出来（被判读"泳池边"）→ 压到 0.03 且降强度；
		# ②涟漪更细更活 (13 / 0.26 / flow 0.30)；③再降 alpha 提镜面，逆光下出波光而不是塑料反光。
		smat.set_shader_parameter(&"shallow_color", Color(0.230, 0.330, 0.310))
		smat.set_shader_parameter(&"deep_color", Color(0.060, 0.110, 0.120))
		smat.set_shader_parameter(&"foam_color", Color(0.760, 0.800, 0.800))
		smat.set_shader_parameter(&"flow_dir", Vector2(-0.94, 0.34))
		smat.set_shader_parameter(&"flow_speed", 0.30)
		smat.set_shader_parameter(&"ripple_scale", 13.0)
		smat.set_shader_parameter(&"ripple_strength", 0.26)
		smat.set_shader_parameter(&"warp_amount", 1.2)
		smat.set_shader_parameter(&"foam_width", 0.03)
		smat.set_shader_parameter(&"foam_strength", 0.22)
		smat.set_shader_parameter(&"base_alpha", 0.26)
		smat.set_shader_parameter(&"roughness_base", 0.28)
		smat.set_shader_parameter(&"specular_amount", 0.34)
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
		bm.size = Vector3(size.x, 0.03, size.y)
		mi.mesh = bm
		mi.position = (spot["pos"] as Vector3) + Vector3(0.0, GROUND_TOP + 0.004, 0.0)
		# ART10：泥舌从"纯色土板"换成湿砾石贴图（压暗 tint + 低粗糙度的湿面），
		# 读作"水陆交界的湿石滩"而不是一块沥青板。贴图缺失时退回旧纯色。
		var mat := _make_tex_material(TEX_PEBBLES_DIFF, TEX_PEBBLES_NOR, TEX_PEBBLES_ARM,
			Vector2(1.6, 0.7), 0.50)
		if mat != null:
			mat.albedo_color = Color(0.40, 0.37, 0.31)
			mi.material_override = mat
		else:
			var plain := StandardMaterial3D.new()
			plain.albedo_color = Color(0.262, 0.236, 0.202)
			plain.roughness = 0.92
			mi.material_override = plain
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
		# ART10：草色往暖金压一档（golden hour 里草不该是"纯翠绿"，
		# vision 判读"受光面过于翠绿、没有和暖橙环境光融合"）。
		wm.set_shader_parameter(&"albedo_color", base_mat.albedo_color * Color(0.86, 0.78, 0.60))
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
			_apply_stone_to_instance(inst, Vector2(2.4, 1.2))
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
			_apply_stone_to_instance(inst, Vector2(3.0, 2.4))
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
	_add_shore_plates(parent)

	# 近景草：确定性散布 128 株（同一套 bush 资产缩到 0.16–0.36），带风摆
	var grass := 0
	if ResourceLoader.exists(BUSH_ASSET):
		var bush: PackedScene = load(BUSH_ASSET) as PackedScene
		for i in SCATTER_GRASS:
			var p := _scatter_point(i, 0.37)
			var inst: Node3D = bush.instantiate() as Node3D
			inst.name = "NearGrass%d" % (i + 1)
			inst.position = p + Vector3(0.0, GROUND_TOP, 0.0)
			inst.rotation_degrees = Vector3(0.0, float(i) * 37.0, 0.0)
			inst.scale = Vector3.ONE * (0.16 + 0.20 * _hash01(i, 5.7))
			parent.add_child(inst)
			inst.owner = parent
			_apply_grass_wind(inst)
			grass += 1

	# 近景碎石：34 颗（巨石缩到 0.05–0.12）
	var pebbles := 0
	if ResourceLoader.exists(BOULDER_ASSET):
		var boulder: PackedScene = load(BOULDER_ASSET) as PackedScene
		for i in SCATTER_PEBBLE:
			var p := _scatter_point(i, 0.71)
			var inst: Node3D = boulder.instantiate() as Node3D
			inst.name = "NearPebble%d" % (i + 1)
			inst.position = p + Vector3(0.0, GROUND_TOP, 0.0)
			inst.rotation_degrees = Vector3(0.0, float(i) * 53.0, 0.0)
			inst.scale = Vector3.ONE * (0.05 + 0.07 * _hash01(i, 2.3))
			parent.add_child(inst)
			inst.owner = parent
			pebbles += 1
	print("TOOL|NearClutter|grass=%d|pebbles=%d|shore_plates=%d" % [
		grass, pebbles, SHORE_PLATE_COUNT,
	])


# ---------------------------------------------------------------------------
# 光照与后处理
# ---------------------------------------------------------------------------

func _add_light_and_env(parent: Node3D) -> void:
	# ART10：改**侧逆光**——主光从溪谷后方（画面深处）低角度射向镜头，
	# 主体（猫）背对光、镜头侧看到的是轮廓光 + 长阴影，这正是展板主视觉的布光。
	# 旧值 (-24, 32, 0) 是顺光，被判读"无方向光、无轮廓光、画面平"。
	var sun := DirectionalLight3D.new()
	sun.name = "BoardSun"
	sun.rotation_degrees = Vector3(-14.0, 196.0, 0.0)
	sun.light_color = Color(1.0, 0.83, 0.60)
	sun.light_energy = 1.60
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.03
	# ART16：默认 2.0 的法线偏移把阴影根部推开，0.31 m 的猫脚下出现"影子离脚"。
	# 0.6 让阴影终止线贴回接触处；方向/能量/色温/最大距离一字未动。
	sun.shadow_normal_bias = 0.6
	parent.add_child(sun)
	sun.owner = parent

	# 冷色天光补光：不投影，只把背光面抬起来
	var fill := DirectionalLight3D.new()
	fill.name = "BoardSkyFill"
	fill.basis = Basis.looking_at(Vector3(0.15, -0.55, -0.82))
	fill.light_color = Color(0.60, 0.70, 0.88)
	fill.light_energy = 0.55
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
	# ART16（2026-11-04）：展板关的猫体量约 0.31 m（屏幕占比 25%），1.35 m 的 AO 半径把脚底
	# 抹成一圈灰晕、影子与脚脱开。参考 ART15 庭院关结论（场景尺度相近、机位更近），取 0.75 m：
	# 半径只影响 AO 采样范围，强度/幂次/细节/light_affect 一字未动。
	env.ssao_radius = 0.75
	env.ssao_intensity = 2.8
	env.ssao_power = 2.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# ART13（2026-11-02）：tp 机位"中心强光过曝"第三轮——只动后处理层，光照方向/能量不动。
	# exposure 1.05→0.92（ACES 滚降区整体回压），辉光阈值 1.15→1.30（见下）。
	env.tonemap_exposure = 0.92
	env.tonemap_white = 1.0
	# 空气透视：近景 9 m 内零影响，远景（石墙/围栏）淡下去做层次
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.74, 0.71, 0.62)
	env.fog_light_energy = 0.75
	env.fog_density = 0.85
	env.fog_sky_affect = 0.15
	env.fog_depth_begin = 9.0
	env.fog_depth_end = 38.0
	env.fog_depth_curve = 1.0
	# ART10：体积雾——展板有"树冠间暖色光柱 + 溪面薄雾"，深度雾只推远景推不出光柱。
	# anisotropy 高值让逆光主光在雾里前向散射，形成穿林光带（T600 @1280x720 Forward+ 实测可开）。
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.016
	env.volumetric_fog_albedo = Color(0.82, 0.78, 0.70)
	env.volumetric_fog_anisotropy = 0.72
	env.volumetric_fog_length = 72.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.12
	env.volumetric_fog_sky_affect = 0.12
	env.volumetric_fog_temporal_reprojection_enabled = true
	# 展板的高光是"太阳边上发亮"，给一点点辉光就够，不做整屏泛白。
	# ART10 二轮：0.50/1.05 被判读"画面中心一片死白、吃掉水面细节"→ 收到 0.35/1.15。
	# ART13 三轮（tp 过曝收口）：辉光阈值 1.15→1.30——只有更强的高光才进辉光，
	# 中等亮度的草地/水面不再被泛白叠加（强度 0.35 维持）。
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.30
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


## 湿泥岸：14 段**不规则**泥板（长 0.9–2.5、宽 0.28–0.62、yaw ±13°、明度抖动）。
## 取代上一版那条 16×0.55 直板——直板在截图里读成"一条沥青带"（ART09-E 证据 §3）。
func _add_shore_plates(parent: Node3D) -> void:
	var half := CREEK_SIZE.z * 0.5
	for i in SHORE_PLATE_COUNT:
		var near_edge := i % 2 == 0
		var edge_z := CREEK_CENTER.z + half if near_edge else CREEK_CENTER.z - half
		var t := (_hash01(i, 1.7) - 0.5) * CREEK_SIZE.x * 0.92
		var w := 0.9 + 1.6 * _hash01(i, 2.9)
		var d := 0.28 + 0.34 * _hash01(i, 4.1)
		var offset_z := (0.12 + 0.16 * _hash01(i, 6.3)) * (1.0 if near_edge else -1.0)
		var mi := MeshInstance3D.new()
		mi.name = "ShorePlate%d" % (i + 1)
		var bm := BoxMesh.new()
		bm.size = Vector3(w, 0.02, d)
		mi.mesh = bm
		mi.position = Vector3(CREEK_CENTER.x + t, GROUND_TOP + 0.004, edge_z + offset_z)
		mi.rotation_degrees = Vector3(0.0, (_hash01(i, 8.1) - 0.5) * 26.0, 0.0)
		# ART10：岸板是"灰色悬空板/马路牙子"判读的头号来源——纯色深灰必须换掉。
		# 换成湿砾石贴图（uv 随板长走、tint 按原抖动压暗、低粗糙度做湿面高光）。
		var shade := 0.150 + 0.075 * _hash01(i, 9.7)
		var mat := _make_tex_material(TEX_PEBBLES_DIFF, TEX_PEBBLES_NOR, TEX_PEBBLES_ARM,
			Vector2(1.4, 0.6), 0.42)
		if mat != null:
			mat.albedo_color = Color(shade * 2.9, shade * 2.75, shade * 2.5)
			mi.material_override = mat
		else:
			var plain := StandardMaterial3D.new()
			plain.albedo_color = Color(shade, shade * 0.93, shade * 0.84)
			plain.roughness = 0.86
			mi.material_override = plain
		parent.add_child(mi)
		mi.owner = parent


## 用 Poly Haven 的 diff / nor_gl / arm 三张 1K 贴图拼一个 `StandardMaterial3D`
## （arm 打包：R = AO、G = Roughness、B = Metallic）。贴图缺失时返回 null，调用方退回纯色。
func _make_tex_material(diff: String, nor: String, arm: String, uv_scale: Vector2,
		rough_override: float = -1.0) -> StandardMaterial3D:
	if not (ResourceLoader.exists(diff) and ResourceLoader.exists(nor) and ResourceLoader.exists(arm)):
		return null
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(diff) as Texture2D
	mat.normal_enabled = true
	mat.normal_texture = load(nor) as Texture2D
	var arm_tex := load(arm) as Texture2D
	if arm_tex != null:
		mat.ao_enabled = true
		mat.ao_texture = arm_tex
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.roughness_texture = arm_tex
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	if rough_override >= 0.0:
		mat.roughness = rough_override
	mat.metallic = 0.0
	return mat


## 把石墙贴图套到某个 glb 实例的所有表面上（只换材质，几何与碰撞不动）。
## 必须在**入树之后**调用：入树前套的 override 在 `PackedScene.pack()` 里会丢（实测）。
func _apply_stone_to_instance(inst: Node3D, uv_scale: Vector2) -> int:
	var mat := _make_tex_material(TEX_STONE_DIFF, TEX_STONE_NOR, TEX_STONE_ARM, uv_scale, 0.92)
	if mat == null:
		return 0
	var applied := 0
	for mi in _meshes_of(inst):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, mat)
			applied += 1
	# glb 的子网格 owner 是实例根，`pack()` 只存 owner 指向场景根的节点 → override 会丢。
	# 所以把整棵子树认领给场景根（展示关里可以摊平；玩法关不这么做）。
	if inst.owner != null:
		_own_recursive(inst, inst.owner)
	return applied


func _own_recursive(n: Node, owner_node: Node) -> void:
	for child in n.get_children():
		child.owner = owner_node
		_own_recursive(child, owner_node)


func _meshes_of(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for child in n.get_children():
		out.append_array(_meshes_of(child))
	return out


## 确定性 0..1 伪随机（不用 RandomNumberGenerator，重跑结果一致）
func _hash01(i: int, salt: float) -> float:
	var s := sin(float(i) * 12.9898 + salt * 78.233) * 43758.5453
	return s - floorf(s)


func _scatter_point(i: int, salt: float) -> Vector3:
	var u := _hash01(i * 2 + 1, salt)
	var v := _hash01(i * 2 + 2, salt + 3.1)
	return Vector3(
		lerpf(SCATTER_BAND_X.x, SCATTER_BAND_X.y, u), 0.0,
		lerpf(SCATTER_BAND_Z.x, SCATTER_BAND_Z.y, v)
	)
