extends SceneTree
## 关卡生成工具（T011）：生成生态灰盒 `res://scenes/maps/l_courtyard.tscn`
##
## 为什么用工具而不是手写 .tscn：与 `tool_add_probe_asset.gd` / `tool_make_move_fixtures.gd` 同规矩 ——
## **场景编辑绝不把场景加入场景树**（否则 pack() 会把运行时状态写进文件），子资源由引擎序列化更可靠。
##
## 布局（`Docs/Tasks/T011.md` §4；需求来自策划 §8.1/§8.2）：
##   地面 80×80 m（厚 0.2、顶面 y=0.10）；可玩矩形 x∈[−36,36]、z∈[−26,30]（72×56=4032 m²），四周围 3 m 栅栏。
##   四个区域**恰好铺满**可玩矩形（ID 用 TechnicalDesign §2 的固定串）：
##     * Courtyard x∈[−10,10] z∈[2,30]   560 m²  出生 + 基础补给（猫安全点、鼠边缘掩体与碎屑）
##     * Creek     x∈[−36,−10] z∈[2,30]  728 m²  浅溪饮水 + 路线选择（鼠的隐蔽入口）
##     * Roots     x∈[10,36]  z∈[2,30]   728 m²  树根屏障（猫 0.50 跳顶 / 鼠 0.24×0.30 洞）
##     * Grass     x∈[−36,36] z∈[−26,2] 2016 m²  开阔危险区 + 草丛掩体的安全绕行
##   分道原则（T009 教训）：结构不要压在出生点→补给点的走廊上；本文件的 §4.5 走廊在 `_verify()` 里会被复核。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_make_courtyard.gd'
## 幂等：每次按同一套常量重建覆盖，随后**重新加载**并核对几何（打印 VERIFY|）。

const OUT := "res://scenes/maps/l_courtyard.tscn"

# --- 4.1 地面与边界 ---------------------------------------------------------
const GROUND_SIZE := Vector3(80.0, 0.2, 80.0)
const GROUND_TOP := 0.10
const PLAY_MIN_X := -36.0

## 几何比较容差：坐标量级到 36 m，float32 的间隔约 4e-6，1e-6 会误杀（实测踩到）
const GEO_EPS := 1e-4
const PLAY_MAX_X := 36.0
const PLAY_MIN_Z := -26.0
const PLAY_MAX_Z := 30.0
const PLAY_AREA := 4032.0                     # 72 × 56
const FENCE_THICK := 0.2
const FENCE_HEIGHT := 3.0

# --- 4.2 四个区域（面积必须恰好铺满可玩矩形） --------------------------------
const REGIONS := [
	{"id": "Courtyard", "min_x": -10.0, "max_x": 10.0, "min_z": 2.0, "max_z": 30.0},
	{"id": "Creek", "min_x": -36.0, "max_x": -10.0, "min_z": 2.0, "max_z": 30.0},
	{"id": "Roots", "min_x": 10.0, "max_x": 36.0, "min_z": 2.0, "max_z": 30.0},
	{"id": "Grass", "min_x": -36.0, "max_x": 36.0, "min_z": -26.0, "max_z": 2.0},
]
const REGION_VOLUME_HEIGHT := 4.0             # 数据体量（layer=0，不参与物理）

# --- 4.3 出生点与补给 -------------------------------------------------------
const CAT_SPAWN := Vector3(-4.0, GROUND_TOP + 0.24, 24.0)
const MOUSE_SPAWN := Vector3(7.0, GROUND_TOP + 0.09, 26.0)
const SUPPLIES := [
	{"node": "FoodPoint_Courtyard_Cat", "pos": Vector3(-7.0, GROUND_TOP, 22.0), "type": "food", "species": "Cat", "region": "Courtyard"},
	{"node": "FoodPoint_Courtyard_Mouse", "pos": Vector3(8.0, GROUND_TOP, 25.0), "type": "food", "species": "Mouse", "region": "Courtyard"},
	{"node": "FoodPoint_Grass_Mouse", "pos": Vector3(2.0, GROUND_TOP, -20.0), "type": "food", "species": "Mouse", "region": "Grass"},
	{"node": "FoodPoint_Roots_Mouse", "pos": Vector3(20.0, GROUND_TOP, 24.0), "type": "food", "species": "Mouse", "region": "Roots"},
	{"node": "WaterPoint_Creek", "pos": Vector3(-24.0, GROUND_TOP, 16.0), "type": "water", "species": "Both", "region": "Creek"},
]

# --- 4.4 结构 ---------------------------------------------------------------
## 树根屏障（§8.2-1/2/5）：高 0.50 的横墙横贯 Roots；猫跳顶、鼠钻 0.24×0.30 洞。
const BARRIER_HEIGHT := 0.50
const BARRIER_Z_MIN := 18.5
const BARRIER_Z_MAX := 19.5
const BARRIER_MIN_X := 10.0
const BARRIER_MAX_X := 36.0
const HOLE_W := 0.24                          # 同 T010：鼠过、猫不过
const HOLE_H := 0.30
const HOLE_CENTER_X := 26.5                   # 洞中心（猫的跳顶车道在 x=30，互不干扰）
const CAT_JUMP_LANE_X := 30.0

## 溪边隐蔽入口（§8.2-2）：高 1.00 的两道岸墙夹出 0.24 的缝 —— 鼠过；猫既进不去也跳不过。
const BANK_WALL_HEIGHT := 1.00
const BANK_WALL_THICK := 0.30
const BANK_WALL_LEN := 8.0                    # z∈[6,14]
const BANK_Z_CENTER := 10.0
const BANK_GAP := 0.24
const BANK_WALL_A_CENTER_X := -32.0           # x∈[−32.15, −31.85]
const BANK_GAP_CENTER_X := -31.73             # 缝隙中心（鼠车道）

## 浅溪：仅网格、无碰撞（不做游泳系统）
const WATER_SIZE := Vector3(22.0, 0.03, 20.0)
const WATER_CENTER := Vector3(-23.0, GROUND_TOP + 0.015, 16.0)
const WATER_DEPTH := 0.03

## 庭院休息棚（§8.1 猫）、碎屑（鼠）
const SHELTER_X_MIN := -9.5
const SHELTER_X_MAX := -6.5
const SHELTER_Z_MIN := 25.6
const SHELTER_Z_MAX := 29.0
const SHELTER_WALL_H := 1.6

## 草地：开阔危险区 + 掩体（§8.2-3）
const DANGER_SIZE := Vector3(16.0, 4.0, 24.0)
const DANGER_CENTER := Vector3(2.0, 2.0, -10.0)
const COVER_SIZE := Vector3(3.0, 3.0, 3.0)
const COVER_FACTOR := 0.4                     # Parameters.md 草丛 VisibilityFactor
const COVERS := [
	{"node": "CoverBushWestA", "pos": Vector3(-16.0, 1.5, -6.0)},
	{"node": "CoverBushWestB", "pos": Vector3(-16.0, 1.5, -16.0)},
	{"node": "CoverBushNorthC", "pos": Vector3(-8.0, 1.5, -22.0)},
]
## ART01：草丛掩体的**视觉**改用 Blender 资产（glb 实例）。碰撞与可见性仍只由上面的 Area3D
## 数据体量负责 —— 换视觉**不改玩法**（T011 的几何断言、T026 的掩护断言都不受影响）。
## 资产缺失时自动退回原来的半透明绿盒子，生成器不会因此失败。
const BUSH_ASSET := "res://assets/environment/sm_bush_001.glb"
const BUSH_YAWS := [0.0, 63.0, 141.0]      # 三处朝向不同，避免"复制粘贴感"
const BUSH_SCALES := [1.00, 0.94, 1.06]

## ART03-②：溪边巨石的正式视觉（Poly Haven boulder_01，CC0，减面到 7,500 tris）。
## 实测（tool_dump_scene_tree.gd）：AABB 1.268556 × 1.004233 × 1.829183，min_y = 0（资产原点在脚底）。
## 碰撞仍是 Godot 侧的 BoxShape3D（`Docs/ART_ASSET_SPEC.md` §3：.glb 只带视觉）。
const BOULDER_ASSET := "res://assets/environment/sm_boulder_001.glb"
const BOULDER_SIZE := Vector3(1.268556, 1.004233, 1.829183)

## ART03-③：石墙/围栏模块（Sketchfab `wall_stefan_wr`，CC-BY，取其最高的 `wall_stone` 件）。
## 实测（Godot 读回）：3.680367 × 3.000000 × 0.302739（长 × 高 × 厚），1,244 tris，
## 1 材质（roughness 0.85、metallic 0），原点在脚印中心 + 底面 y=0。
## 石块之间有真实通孔 → 生成器在墙体内侧再放一块深色衬板（`Backing`）遮缝，避免看穿边界。
const FENCE_ASSET := "res://assets/environment/sm_fence_module_001.glb"
const FENCE_MODULE_LEN := 3.680367
const FENCE_MODULE_H := 3.000000
const FENCE_MODULE_THICK := 0.302739

## ART03-④：鼠洞入口的树桩视觉（Sketchfab `stump_callum_arb`，CC-BY）。
## 实测（Godot 读回）：0.823243 × 0.850000 × 0.778105（宽 × 高 × 深），12,555 tris，1 材质，
## 原点 = 脚印中心 + 底面 y=0；**底部已被布尔破出 0.24 宽 × 0.30 高的贯通方孔**（与 `HOLE_W/HOLE_H` 一致）。
## 纯视觉：不带任何碰撞，也不进导航组（通行仍由 RootBarrier* 三个 BoxShape3D 决定）。
const ROOT_HOLE_ASSET := "res://assets/environment/sm_root_hole_001.glb"
const ROOT_HOLE_SIZE := Vector3(0.823243, 0.850000, 0.778105)

const ROUTE_SHORT_START := Vector3(2.0, GROUND_TOP, 2.0)
const ROUTE_SHORT_END := Vector3(2.0, GROUND_TOP, -22.0)

var _fails := 0


func _initialize() -> void:
	print("TOOL|make_courtyard|start")

	var root_node := Node3D.new()
	root_node.name = "Courtyard"

	_add_ground(root_node)
	_add_fences(root_node)
	_add_regions(root_node)
	_add_spawns_and_supplies(root_node)
	_add_courtyard_structures(root_node)
	_add_grass_structures(root_node)
	_add_roots_structures(root_node)
	_add_creek_structures(root_node)
	_add_routes(root_node)
	_add_hide_spots(root_node)
	_add_light_and_env(root_node)

	var out := PackedScene.new()
	if out.pack(root_node) != OK:
		print("TOOL|ERROR|pack failed")
		quit(1)
		return
	var err := ResourceSaver.save(out, OUT)
	print("TOOL|save_result=%d (%s)|path=%s" % [err, "OK" if err == OK else "FAIL", OUT])
	root_node.free()
	if err != OK:
		quit(1)
		return

	_verify()
	print("TOOL|make_courtyard|%s" % ("done" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------------------
# 地面 / 边界
# ---------------------------------------------------------------------------

func _add_ground(parent: Node3D) -> void:
	_mk_box(parent, "Ground", GROUND_SIZE, Vector3.ZERO, Vector3.ZERO, Color(0.32, 0.34, 0.36))
	print("TOOL|Ground|size=%s|top=%.3f" % [GROUND_SIZE, GROUND_TOP])


func _add_fences(parent: Node3D) -> void:
	var mid_z: float = (PLAY_MIN_Z + PLAY_MAX_Z) * 0.5
	var len_x: float = PLAY_MAX_X - PLAY_MIN_X
	var len_z: float = PLAY_MAX_Z - PLAY_MIN_Z
	var y: float = GROUND_TOP + FENCE_HEIGHT * 0.5
	var col := Color(0.46, 0.41, 0.34)
	# 内侧面分别贴在可玩矩形的四条边上
	_mk_clad_wall(parent, "FenceNorth", Vector3(len_x + FENCE_THICK, FENCE_HEIGHT, FENCE_THICK),
		Vector3(0.0, y, PLAY_MAX_Z + FENCE_THICK * 0.5), col, 0.35)
	_mk_clad_wall(parent, "FenceSouth", Vector3(len_x + FENCE_THICK, FENCE_HEIGHT, FENCE_THICK),
		Vector3(0.0, y, PLAY_MIN_Z - FENCE_THICK * 0.5), col, 0.35)
	_mk_clad_wall(parent, "FenceWest", Vector3(FENCE_THICK, FENCE_HEIGHT, len_z + FENCE_THICK),
		Vector3(PLAY_MIN_X - FENCE_THICK * 0.5, y, mid_z), col, 0.35)
	_mk_clad_wall(parent, "FenceEast", Vector3(FENCE_THICK, FENCE_HEIGHT, len_z + FENCE_THICK),
		Vector3(PLAY_MAX_X + FENCE_THICK * 0.5, y, mid_z), col, 0.35)
	print("TOOL|Fences|play=%s|height=%.2f" % [
		[PLAY_MIN_X, PLAY_MAX_X, PLAY_MIN_Z, PLAY_MAX_Z], FENCE_HEIGHT
	])


# ---------------------------------------------------------------------------
# 区域数据体量（Area3D，layer=0 / monitoring=false，只给测试与后续系统读范围）
# ---------------------------------------------------------------------------

func _add_regions(parent: Node3D) -> void:
	for r in REGIONS:
		var cx: float = (float(r["min_x"]) + float(r["max_x"])) * 0.5
		var cz: float = (float(r["min_z"]) + float(r["max_z"])) * 0.5
		var w: float = float(r["max_x"]) - float(r["min_x"])
		var d: float = float(r["max_z"]) - float(r["min_z"])
		var rn := Node3D.new()
		rn.name = "Region_%s" % r["id"]
		rn.position = Vector3(cx, REGION_VOLUME_HEIGHT * 0.5, cz)
		rn.set_meta("region_id", r["id"])
		rn.add_to_group("level_regions", true)
		parent.add_child(rn)
		rn.owner = parent

		var area := Area3D.new()
		area.name = "Volume"
		area.collision_layer = 0
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		rn.add_child(area)
		area.owner = parent
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var box := BoxShape3D.new()
		box.size = Vector3(w, REGION_VOLUME_HEIGHT, d)
		cs.shape = box
		area.add_child(cs)
		cs.owner = parent
		print("TOOL|Region|id=%s|rect=[%.1f,%.1f]x[%.1f,%.1f]|area=%.0f" % [
			r["id"], r["min_x"], r["max_x"], r["min_z"], r["max_z"], w * d
		])


# ---------------------------------------------------------------------------
# 出生点与补给点
# ---------------------------------------------------------------------------

func _add_spawns_and_supplies(parent: Node3D) -> void:
	_mk_marker(parent, "CatSpawn", CAT_SPAWN, "spawn_points", {"region": "Courtyard", "species": "Cat"})
	_mk_marker(parent, "MouseSpawn", MOUSE_SPAWN, "spawn_points", {"region": "Courtyard", "species": "Mouse"})
	for s in SUPPLIES:
		_mk_marker(parent, s["node"], s["pos"], "supply_points", {
			"supply_type": s["type"], "species": s["species"], "region": s["region"]
		})


# ---------------------------------------------------------------------------
# 庭院（§8.1：猫探索/休息、鼠边缘掩体与碎屑）
# ---------------------------------------------------------------------------

func _add_courtyard_structures(parent: Node3D) -> void:
	var col := Color(0.55, 0.50, 0.42)
	var len_z: float = SHELTER_Z_MAX - SHELTER_Z_MIN
	var len_x: float = SHELTER_X_MAX - SHELTER_X_MIN
	var cx: float = (SHELTER_X_MIN + SHELTER_X_MAX) * 0.5
	var cz: float = (SHELTER_Z_MIN + SHELTER_Z_MAX) * 0.5
	var wall_y: float = GROUND_TOP + SHELTER_WALL_H * 0.5
	# 三面墙（东侧留门）+ 顶；内部净空 1.6 m
	_mk_clad_wall(parent, "ShelterWallWest", Vector3(FENCE_THICK, SHELTER_WALL_H, len_z),
		Vector3(SHELTER_X_MIN + FENCE_THICK * 0.5, wall_y, cz), col)
	_mk_clad_wall(parent, "ShelterWallNorth", Vector3(len_x, SHELTER_WALL_H, FENCE_THICK),
		Vector3(cx, wall_y, SHELTER_Z_MAX - FENCE_THICK * 0.5), col)
	_mk_clad_wall(parent, "ShelterWallSouth", Vector3(len_x, SHELTER_WALL_H, FENCE_THICK),
		Vector3(cx, wall_y, SHELTER_Z_MIN + FENCE_THICK * 0.5), col)
	_mk_box(parent, "ShelterRoof", Vector3(len_x + 0.4, 0.2, len_z + 0.2),
		Vector3(cx, GROUND_TOP + SHELTER_WALL_H + 0.1, cz), Vector3.ZERO, col)

	var debris_col := Color(0.62, 0.56, 0.46)
	var debris := [
		Vector3(9.0, GROUND_TOP + 0.15, 27.6),
		Vector3(8.4, GROUND_TOP + 0.15, 26.6),
		Vector3(9.4, GROUND_TOP + 0.15, 25.4),
	]
	for i in debris.size():
		_mk_box(parent, "CourtyardDebris%d" % (i + 1), Vector3(0.6, 0.3, 0.6), debris[i], Vector3.ZERO, debris_col)


# ---------------------------------------------------------------------------
# 草地（§8.2-3：近而危险 / 远而较安全）
# ---------------------------------------------------------------------------

func _add_grass_structures(parent: Node3D) -> void:
	# 开阔暴露区：只做数据体量 + 一块贴地的暗色标记（无碰撞，只给人看）
	_mk_data_area(parent, "DangerZone", DANGER_SIZE, DANGER_CENTER, "danger_zones",
		{"visibility_factor": 1.0, "role": "open_exposure"})
	_mk_surface_marker(parent, "DangerZoneMark", Vector3(DANGER_SIZE.x, 0.02, DANGER_SIZE.z),
		Vector3(DANGER_CENTER.x, GROUND_TOP + 0.01, DANGER_CENTER.z), Color(0.55, 0.35, 0.30, 0.35))

	for i in COVERS.size():
		var c: Dictionary = COVERS[i]
		_mk_data_area(parent, c["node"], COVER_SIZE, c["pos"], "cover_volumes",
			{"visibility_factor": COVER_FACTOR, "role": "cover"})
		# 视觉：贴地放在掩体中心（资产原点在草根处），只做视觉、不带碰撞
		_mk_cover_bush(parent, "%sMesh" % c["node"],
			Vector3(float(c["pos"].x), GROUND_TOP, float(c["pos"].z)),
			float(BUSH_YAWS[i]), float(BUSH_SCALES[i]))

	# 猫的观察点（0.50 高，鼠上不去）
	_mk_box(parent, "GrassMoundA", Vector3(2.0, 0.50, 2.0), Vector3(-20.0, GROUND_TOP + 0.25, -12.0),
		Vector3.ZERO, Color(0.30, 0.45, 0.28))
	_mk_box(parent, "GrassMoundB", Vector3(2.0, 0.50, 2.0), Vector3(14.0, GROUND_TOP + 0.25, -8.0),
		Vector3.ZERO, Color(0.30, 0.45, 0.28))


# ---------------------------------------------------------------------------
# 树根林地（§8.2-1/2/5：同一道屏障，猫跳顶 vs 鼠钻洞）
# ---------------------------------------------------------------------------

func _add_roots_structures(parent: Node3D) -> void:
	var col := Color(0.45, 0.32, 0.22)
	var depth: float = BARRIER_Z_MAX - BARRIER_Z_MIN
	var cz: float = (BARRIER_Z_MIN + BARRIER_Z_MAX) * 0.5
	var cy: float = GROUND_TOP + BARRIER_HEIGHT * 0.5
	var hole_l: float = HOLE_CENTER_X - HOLE_W * 0.5      # 26.38
	var hole_r: float = HOLE_CENTER_X + HOLE_W * 0.5      # 26.62

	_mk_box(parent, "RootBarrierWest", Vector3(hole_l - BARRIER_MIN_X, BARRIER_HEIGHT, depth),
		Vector3((BARRIER_MIN_X + hole_l) * 0.5, cy, cz), Vector3.ZERO, col)
	_mk_box(parent, "RootBarrierEast", Vector3(BARRIER_MAX_X - hole_r, BARRIER_HEIGHT, depth),
		Vector3((hole_r + BARRIER_MAX_X) * 0.5, cy, cz), Vector3.ZERO, col)
	# 洞的上沿：从 0.10+HOLE_H 到屏障顶 0.60
	var lintel_h: float = BARRIER_HEIGHT - HOLE_H        # 0.20
	_mk_box(parent, "RootBarrierLintel", Vector3(HOLE_W, lintel_h, depth),
		Vector3(HOLE_CENTER_X, GROUND_TOP + HOLE_H + lintel_h * 0.5, cz), Vector3.ZERO,
		Color(0.50, 0.36, 0.24))
	# ART03-④：洞口的树桩视觉。**必须贴在屏障外侧**——第一版把桩子放在 z=19（屏障正中，
	# 屏障深 1.0 m），结果整个桩子被灰盒吃掉、只露出顶部。这里让桩子的内端面正好贴住屏障面，
	# 资产里烘好的 0.24×0.30 贯通孔与玩法孔首尾相接，南北两侧各一桩（两侧都像"从树桩里钻出来"）。
	var half_depth: float = ROOT_HOLE_SIZE.z * 0.5
	_mk_root_hole_visual(parent, "RootHoleStumpS", Vector3(HOLE_CENTER_X, GROUND_TOP, BARRIER_Z_MIN - half_depth))
	_mk_root_hole_visual(parent, "RootHoleStumpN", Vector3(HOLE_CENTER_X, GROUND_TOP, BARRIER_Z_MAX + half_depth))
	print("TOOL|RootBarrier|top=%.3f|hole=%.2fx%.2f@x=%.2f|jump_lane_x=%.1f" % [
		GROUND_TOP + BARRIER_HEIGHT, HOLE_W, HOLE_H, HOLE_CENTER_X, CAT_JUMP_LANE_X
	])


# ---------------------------------------------------------------------------
# 浅溪（§8.1：饮水与路线选择；不做游泳系统）
# ---------------------------------------------------------------------------

func _add_creek_structures(parent: Node3D) -> void:
	# 水面：只有网格，**没有碰撞**（可通行）
	var mi := MeshInstance3D.new()
	mi.name = "CreekWater"
	mi.position = WATER_CENTER
	var bm := BoxMesh.new()
	bm.size = WATER_SIZE
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.45, 0.65, 0.60)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	mi.material_override = mat
	mi.set_meta("water_depth", WATER_DEPTH)
	mi.add_to_group("water_bodies", true)
	parent.add_child(mi)
	mi.owner = parent

	# 溪边隐蔽入口：两道 1.00 高的岸墙夹出 0.24 的缝
	var cy: float = GROUND_TOP + BANK_WALL_HEIGHT * 0.5
	var bank_col := Color(0.42, 0.40, 0.38)
	_mk_box(parent, "CreekBankWallA", Vector3(BANK_WALL_THICK, BANK_WALL_HEIGHT, BANK_WALL_LEN),
		Vector3(BANK_WALL_A_CENTER_X, cy, BANK_Z_CENTER), Vector3.ZERO, bank_col)
	_mk_box(parent, "CreekBankWallB", Vector3(BANK_WALL_THICK, BANK_WALL_HEIGHT, BANK_WALL_LEN),
		Vector3(BANK_WALL_A_CENTER_X + BANK_WALL_THICK + BANK_GAP, cy, BANK_Z_CENTER),
		Vector3.ZERO, bank_col)
	# 朝向固定 0°：`_box()` 从 body 的 position/size 推世界 AABB，**不读旋转**，
	# 一旦给 body 加 yaw，测试读到的包围盒就会比真实碰撞小。要转就把 AABB 一起算。
	_mk_boulder(parent, "CreekBoulder", Vector3(-14.0, GROUND_TOP, 8.0), 0.0)
	_mk_data_area(parent, "CreekReedCover", COVER_SIZE, Vector3(-28.0, 1.5, 10.0), "cover_volumes",
		{"visibility_factor": COVER_FACTOR, "role": "cover"})
	# ART01 审计发现的真实缺陷：这处掩体**原来没有任何视觉**（实测 CreekReedCoverMesh = MISSING，
	# 玩家在溪边"被草丛掩护"却看不到草）。现在补上同一套资产。
	_mk_cover_bush(parent, "CreekReedCoverMesh", Vector3(-28.0, GROUND_TOP, 10.0), 212.0, 1.0)
	print("TOOL|Creek|gap=%.3f@x=%.3f|wall_top=%.3f|water_top=%.3f|water_collision=none" % [
		BANK_GAP, BANK_GAP_CENTER_X, GROUND_TOP + BANK_WALL_HEIGHT,
		WATER_CENTER.y + WATER_SIZE.y * 0.5
	])


# ---------------------------------------------------------------------------
# 路线标记（§8.2-3）
# ---------------------------------------------------------------------------

func _add_routes(parent: Node3D) -> void:
	_mk_marker(parent, "RouteShortStart", ROUTE_SHORT_START, "route_markers", {"route": "short_dangerous"})
	_mk_marker(parent, "RouteShortEnd", ROUTE_SHORT_END, "route_markers", {"route": "short_dangerous"})
	_mk_marker(parent, "RouteSafeWaypoint1", Vector3(-16.0, GROUND_TOP, 2.0), "route_markers", {"route": "long_covered"})
	_mk_marker(parent, "RouteSafeWaypoint2", Vector3(-16.0, GROUND_TOP, -22.0), "route_markers", {"route": "long_covered"})
	_mk_marker(parent, "RouteSafeEnd", Vector3(2.0, GROUND_TOP, -22.0), "route_markers", {"route": "long_covered"})



## 躲藏点（T020）：把**真实鼠洞**标成鼠的躲藏点。
##
## 为什么放在洞里而不是洞口外：策划 v1.1 第 212 行「鼠洞是猫不可进入的空间安全边界」；
## T012 已实测**洞里只有鼠层的导航面** → 鼠钻得进去、猫的导航不可达。
## 每区域的安全点数量与布点扩充属 T031/T035（本任务只放这一个）。
func _add_hide_spots(parent: Node3D) -> void:
	var hide_z: float = (BARRIER_Z_MIN + BARRIER_Z_MAX) * 0.5
	var spot := _mk_marker(parent, "HideSpot_RootHole", Vector3(HOLE_CENTER_X, GROUND_TOP, hide_z),
		"hide_spots", {"species": "Mouse", "kind": "mouse_hole", "radius": 0.30})
	print("TOOL|HideSpots|count=1|id=%s|pos=(%.2f, %.2f, %.2f)" % [
		spot.name, spot.position.x, spot.position.y, spot.position.z
	])

func _add_light_and_env(parent: Node3D) -> void:
	var light := DirectionalLight3D.new()
	light.name = "SunLight"
	light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	parent.add_child(light)
	light.owner = parent
	# ART03-③ 实测缺陷：北墙内表面朝 −Z，与主光方向同向 → 整面**近乎全黑**，3 m 石墙读不出材质。
	# 补一盏**不投影**的填充光（朝下 + Z），只抬背光面，不改主光阴影方向。
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.basis = Basis.looking_at(Vector3(0.0, -0.55, 0.85))
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	parent.add_child(fill)
	fill.owner = parent


	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)
	we.owner = parent


# ---------------------------------------------------------------------------
# 基础构造件
# ---------------------------------------------------------------------------

## 静态盒子：StaticBody3D（layer=1 world_static, mask=0）+ Mesh + CollisionShape
func _mk_box(parent: Node3D, nm: String, size: Vector3, pos: Vector3, rot_deg: Vector3, color: Color) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = nm
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation_degrees = rot_deg
	parent.add_child(sb)
	sb.owner = parent

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mi.material_override = mat
	sb.add_child(mi)
	mi.owner = parent

	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	cs.owner = parent
	return sb


## 数据体量：Area3D（layer=0、mask=0、monitoring=false）+ BoxShape3D 形状（给测试/后续系统读范围）
func _mk_data_area(parent: Node3D, nm: String, size: Vector3, pos: Vector3, group: String, meta: Dictionary) -> Area3D:
	var area := Area3D.new()
	area.name = nm
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.position = pos
	for k in meta:
		area.set_meta(k, meta[k])
	area.add_to_group(group, true)
	parent.add_child(area)
	area.owner = parent

	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	area.add_child(cs)
	cs.owner = parent
	return area


## 贴地/装饰网格：只有 MeshInstance3D，**没有碰撞**（不参与物理）
func _mk_surface_marker(parent: Node3D, nm: String, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.position = pos
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.9
	mi.material_override = mat
	parent.add_child(mi)
	mi.owner = parent
	return mi


## ART01：草丛掩体的**视觉**节点（glb 实例，不带任何碰撞/Area3D）。
## 缺资产时退回原来的 3x0.9x3 半透明绿盒子 —— 生成器要保持能在没有资产的机器上跑通。
func _mk_cover_bush(parent: Node3D, nm: String, ground_pos: Vector3, yaw_deg: float,
		scale_mul: float) -> void:
	var ps: PackedScene = null
	if ResourceLoader.exists(BUSH_ASSET):
		ps = load(BUSH_ASSET) as PackedScene
	if ps == null:
		_mk_surface_marker(parent, nm, Vector3(3.0, 0.9, 3.0),
			ground_pos + Vector3(0.0, 0.45, 0.0), Color(0.24, 0.42, 0.26, 0.9))
		print("TOOL|cover_visual|%s|FALLBACK_BOX|asset_missing=%s" % [nm, BUSH_ASSET])
		return
	var inst: Node3D = ps.instantiate() as Node3D
	inst.name = nm
	parent.add_child(inst)
	inst.owner = parent          # 不设 owner → pack() 会丢掉这个节点
	inst.position = ground_pos
	inst.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	inst.scale = Vector3.ONE * scale_mul
	print("TOOL|cover_visual|%s|asset=%s|pos=(%.2f, %.2f, %.2f)|yaw=%.1f|scale=%.2f" % [
		nm, BUSH_ASSET, ground_pos.x, ground_pos.y, ground_pos.z, yaw_deg, scale_mul])

## ART03-②：溪边巨石 —— StaticBody3D + 子节点 `Shape`（BoxShape3D 匹配视觉外包盒）+ glb 实例作视觉。
## glb 原点在脚底，所以实例下沉半个高度，视觉与碰撞盒同心；资产缺失时退回灰色盒子。
func _mk_boulder(parent: Node3D, nm: String, ground_pos: Vector3, yaw_deg: float) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = nm
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = ground_pos + Vector3(0.0, BOULDER_SIZE.y * 0.5, 0.0)
	sb.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(sb)
	sb.owner = parent

	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = BOULDER_SIZE
	cs.shape = box
	sb.add_child(cs)
	cs.owner = parent

	var ps: PackedScene = null
	if ResourceLoader.exists(BOULDER_ASSET):
		ps = load(BOULDER_ASSET) as PackedScene
	if ps == null:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var mesh := BoxMesh.new()
		mesh.size = BOULDER_SIZE
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.40, 0.42, 0.44)
		mat.roughness = 0.9
		mi.material_override = mat
		sb.add_child(mi)
		mi.owner = parent
		print("TOOL|creek_boulder|%s|FALLBACK_BOX|asset_missing=%s" % [nm, BOULDER_ASSET])
		return sb

	var vis: Node3D = ps.instantiate() as Node3D
	vis.name = "Mesh"
	vis.position = Vector3(0.0, -BOULDER_SIZE.y * 0.5, 0.0)
	sb.add_child(vis)
	vis.owner = parent          # 不设 owner → pack() 会丢掉这个节点
	print("TOOL|creek_boulder|%s|asset=%s|size=(%.3f, %.3f, %.3f)|pos=(%.2f, %.2f, %.2f)|yaw=%.1f" % [
		nm, BOULDER_ASSET, BOULDER_SIZE.x, BOULDER_SIZE.y, BOULDER_SIZE.z,
		ground_pos.x, ground_pos.y, ground_pos.z, yaw_deg])
	return sb

## ART03-③：石墙视觉 —— StaticBody3D + `Shape`（BoxShape3D 尺寸 = 原来 `_mk_box` 的尺寸，玩法不变）
## + `Backing` 深色衬板（遮住石块间真实通孔）+ `Tiles` 下按模块长平铺的 glb 实例。
## 模块按段高**等比**缩放（围栏 3.0 m → 1.0×；庇护棚 1.6 m → 0.533×），保持石块比例不变。
func _mk_clad_wall(parent: Node3D, nm: String, size: Vector3, pos: Vector3, color: Color,
		bleed: float = 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = nm
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	parent.add_child(sb)
	sb.owner = parent

	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	cs.owner = parent

	var ps: PackedScene = null
	if ResourceLoader.exists(FENCE_ASSET):
		ps = load(FENCE_ASSET) as PackedScene
	if ps == null:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var mesh := BoxMesh.new()
		mesh.size = size
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		mi.material_override = mat
		sb.add_child(mi)
		mi.owner = parent
		print("TOOL|wall_visual|%s|FALLBACK_BOX|asset_missing=%s" % [nm, FENCE_ASSET])
		return sb

	# 衬板：厚度 0.08，贴在墙体中心；石块包在它两侧，缝隙里看到的是深色内壁而不是"看穿"
	var backing := MeshInstance3D.new()
	backing.name = "Backing"
	var bm := BoxMesh.new()
	var along_x := size.x >= size.z
	bm.size = Vector3(size.x * 0.995, size.y * 0.995, 0.08) if along_x \
		else Vector3(0.08, size.y * 0.995, size.z * 0.995)
	backing.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.22, 0.21, 0.20)
	bmat.roughness = 0.95
	backing.material_override = bmat
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sb.add_child(backing)
	backing.owner = parent

	# 平铺：段高决定等比缩放。**相邻模块必须重叠约 20%** —— 实测按模块长 1:1 排布时，
	# 模块两端的不规则缺口会露出大片衬板（第一版实机图里是明显的黑色板面）。
	var k: float = size.y / FENCE_MODULE_H
	var mod_len: float = FENCE_MODULE_LEN * k
	var long_len: float = (size.x if along_x else size.z) + bleed
	var n: int = maxi(1, int(ceil(long_len / (mod_len * 0.80))))
	var spacing: float = long_len / float(n)
	var tiles := Node3D.new()
	tiles.name = "Tiles"
	sb.add_child(tiles)
	tiles.owner = parent
	for i in n:
		var inst: Node3D = ps.instantiate() as Node3D
		inst.name = "Tile%d" % i
		inst.scale = Vector3(k, k, k)
		# 模块原点在脚印中心 + 底面；父节点在墙体中心 → 下沉半个格高
		var off: float = -long_len * 0.5 + spacing * (float(i) + 0.5)
		if along_x:
			inst.position = Vector3(off, -size.y * 0.5, 0.0)
			inst.rotation_degrees = Vector3(0.0, 180.0 if i % 2 == 1 else 0.0, 0.0)
		else:
			inst.position = Vector3(0.0, -size.y * 0.5, off)
			inst.rotation_degrees = Vector3(0.0, 90.0 + (180.0 if i % 2 == 1 else 0.0), 0.0)
		tiles.add_child(inst)
		inst.owner = parent
	print("TOOL|wall_visual|%s|asset=%s|size=(%.3f, %.3f, %.3f)|tiles=%d|spacing=%.3f|k=%.3f" % [
		nm, FENCE_ASSET, size.x, size.y, size.z, n, spacing, k])
	return sb


## ART03-④：鼠洞入口的树桩视觉（glb 实例，**不带碰撞**、不进导航组，通行仍由 RootBarrier* 决定）。
func _mk_root_hole_visual(parent: Node3D, nm: String, ground_pos: Vector3) -> void:
	var ps: PackedScene = null
	if ResourceLoader.exists(ROOT_HOLE_ASSET):
		ps = load(ROOT_HOLE_ASSET) as PackedScene
	if ps == null:
		print("TOOL|root_hole_visual|%s|ASSET_MISSING|%s" % [nm, ROOT_HOLE_ASSET])
		return
	var inst: Node3D = ps.instantiate() as Node3D
	inst.name = nm
	parent.add_child(inst)
	inst.owner = parent          # 不设 owner → pack() 会丢掉这个节点
	inst.position = ground_pos
	inst.rotation_degrees = Vector3.ZERO      # 资产里的孔沿 −Z 贯通，必须与玩法孔同轴
	inst.scale = Vector3.ONE                  # 缩放会改孔径 → 禁止
	print("TOOL|root_hole_visual|%s|asset=%s|pos=(%.2f, %.2f, %.2f)|size=(%.3f, %.3f, %.3f)" % [
		nm, ROOT_HOLE_ASSET, ground_pos.x, ground_pos.y, ground_pos.z,
		ROOT_HOLE_SIZE.x, ROOT_HOLE_SIZE.y, ROOT_HOLE_SIZE.z])


func _mk_marker(parent: Node3D, nm: String, pos: Vector3, group: String, meta: Dictionary) -> Marker3D:
	var m := Marker3D.new()
	m.name = nm
	m.position = pos
	for k in meta:
		m.set_meta(k, meta[k])
	m.add_to_group(group, true)
	parent.add_child(m)
	m.owner = parent
	return m


# ---------------------------------------------------------------------------
# 自检：重新加载刚保存的文件，核对几何与设计意图（不是"文件存在"就算过）
# ---------------------------------------------------------------------------

func _verify() -> void:
	var packed: PackedScene = load(OUT)
	_check("scene_loads", packed != null)
	if packed == null:
		return
	var scene: Node3D = packed.instantiate() as Node3D
	_check("root_is_node3d", scene != null)
	if scene == null:
		return

	# A 基础设施
	_check("ground_top_is_0.10", absf(float(_box(scene, "Ground").get("top", -1.0)) - GROUND_TOP) < GEO_EPS)
	_check("has_light", scene.get_node_or_null("SunLight") != null)
	_check("has_environment", scene.get_node_or_null("WorldEnvironment") != null)
	_check("fence_north_inner_face", absf(float(_box(scene, "FenceNorth").get("min_z", 0.0)) - PLAY_MAX_Z) < GEO_EPS)
	_check("fence_south_inner_face", absf(float(_box(scene, "FenceSouth").get("max_z", 0.0)) - PLAY_MIN_Z) < GEO_EPS)
	_check("fence_west_inner_face", absf(float(_box(scene, "FenceWest").get("max_x", 0.0)) - PLAY_MIN_X) < GEO_EPS)
	_check("fence_east_inner_face", absf(float(_box(scene, "FenceEast").get("min_x", 0.0)) - PLAY_MAX_X) < GEO_EPS)
	for f in ["FenceNorth", "FenceSouth", "FenceWest", "FenceEast"]:
		_check("%s_tall_enough" % f.to_lower(), float(_box(scene, f).get("top", 0.0)) - GROUND_TOP >= 1.0)

	# ART03-③：围栏/庇护棚墙的视觉换成石墙模块（碰撞盒尺寸不变 → 上面的几何断言全部照旧）
	for f in ["FenceNorth", "FenceSouth", "FenceWest", "FenceEast"]:
		var fid: String = str(f).to_lower()
		var tiles_root := scene.get_node_or_null("%s/Tiles" % f) as Node3D
		if not _check("%s_wall_tiles_exist" % fid, tiles_root != null):
			continue
		_check("%s_wall_tiles_not_empty" % fid, tiles_root.get_child_count() > 0)
		var first := tiles_root.get_child(0) as Node3D
		_check("%s_wall_tiles_is_asset" % fid, first != null and first.scene_file_path == FENCE_ASSET)
		_check("%s_wall_tiles_no_collision" % fid, _count_collision_shapes(tiles_root) == 0)
		var bx := _box(scene, f)
		var bsize: Vector3 = bx.get("size", Vector3.ZERO)
		var long_len: float = maxf(bsize.x, bsize.z)
		var n: int = tiles_root.get_child_count()
		var spacing: float = long_len / float(n)
		_check("%s_wall_tiles_cover_run" % fid,
			spacing > 0.0 and spacing <= FENCE_MODULE_LEN + 1e-4)
		# 每块模块底边必须落在这一段墙的底面上（下沉 −size.y/2）
		_check("%s_wall_tiles_sunk" % fid,
			absf(first.position.y + bsize.y * 0.5) < 1e-4)
		var backing := scene.get_node_or_null("%s/Backing" % f) as MeshInstance3D
		_check("%s_wall_backing_exists" % fid, backing != null)
		if backing != null:
			var bmesh := backing.mesh as BoxMesh
			_check("%s_wall_backing_is_slab" % fid, bmesh != null and bmesh.size.y >= bsize.y * 0.99)
	for s in ["ShelterWallWest", "ShelterWallNorth", "ShelterWallSouth"]:
		var sid: String = str(s).to_lower()
		var st := scene.get_node_or_null("%s/Tiles" % s) as Node3D
		if _check("%s_tiles_exist" % sid, st != null):
			_check("%s_tiles_is_asset" % sid,
				(st.get_child(0) as Node3D).scene_file_path == FENCE_ASSET)
			# 庇护棚墙 1.6 m 高 → 模块等比缩放到 0.533×，不能超过护栏那种 1.0×
			var sc: float = (st.get_child(0) as Node3D).scale.y
			_check("%s_tiles_scaled_to_wall" % sid, absf(sc - SHELTER_WALL_H / FENCE_MODULE_H) < 1e-4)

	# B 四区域：恰好铺满可玩矩形
	var area_sum := 0.0
	var rects: Array = []
	for r in REGIONS:
		var rn := scene.get_node_or_null("Region_%s" % r["id"]) as Node3D
		if not _check("region_%s_exists" % r["id"].to_lower(), rn != null):
			continue
		_check("region_%s_id" % r["id"].to_lower(), String(rn.get_meta("region_id", "")) == r["id"])
		var cs := rn.get_node_or_null("Volume/Shape") as CollisionShape3D
		var box := cs.shape as BoxShape3D if cs != null else null
		if not _check("region_%s_volume" % r["id"].to_lower(), box != null):
			continue
		var w: float = box.size.x
		var d: float = box.size.z
		area_sum += w * d
		rects.append({
			"min_x": rn.position.x - w * 0.5, "max_x": rn.position.x + w * 0.5,
			"min_z": rn.position.z - d * 0.5, "max_z": rn.position.z + d * 0.5,
		})
	_check("region_area_sum_4032", absf(area_sum - PLAY_AREA) < 1e-3)
	var overlap := false
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Dictionary = rects[i]
			var b: Dictionary = rects[j]
			if a["min_x"] < b["max_x"] - GEO_EPS and b["min_x"] < a["max_x"] - GEO_EPS \
					and a["min_z"] < b["max_z"] - GEO_EPS and b["min_z"] < a["max_z"] - GEO_EPS:
				overlap = true
	_check("regions_do_not_overlap", not overlap)
	var ux0 := INF
	var ux1 := -INF
	var uz0 := INF
	var uz1 := -INF
	for a in rects:
		ux0 = minf(ux0, a["min_x"])
		ux1 = maxf(ux1, a["max_x"])
		uz0 = minf(uz0, a["min_z"])
		uz1 = maxf(uz1, a["max_z"])
	_check("region_union_is_playable", absf(ux0 - PLAY_MIN_X) < GEO_EPS and absf(ux1 - PLAY_MAX_X) < GEO_EPS
		and absf(uz0 - PLAY_MIN_Z) < GEO_EPS and absf(uz1 - PLAY_MAX_Z) < GEO_EPS)
	print("VERIFY|Regions|area_sum=%.0f|count=%d" % [area_sum, rects.size()])

	# C 出生点与补给点落在声明的区域内
	_check("cat_spawn_region", _inside_rect(scene, CAT_SPAWN, "Courtyard"))
	_check("mouse_spawn_region", _inside_rect(scene, MOUSE_SPAWN, "Courtyard"))
	for s in SUPPLIES:
		var m := scene.get_node_or_null(s["node"])
		if not _check("supply_%s_exists" % String(s["node"]).to_lower(), m != null):
			continue
		_check("supply_%s_type" % String(s["node"]).to_lower(), String(m.get_meta("supply_type", "")) == s["type"])
		_check("supply_%s_species" % String(s["node"]).to_lower(), String(m.get_meta("species", "")) == s["species"])
		_check("supply_%s_in_region" % String(s["node"]).to_lower(), _inside_rect(scene, s["pos"], s["region"]))

	# D 结构
	var lw := _box(scene, "RootBarrierWest")
	var le := _box(scene, "RootBarrierEast")
	var li := _box(scene, "RootBarrierLintel")
	if _check("root_barrier_exists", not lw.is_empty() and not le.is_empty() and not li.is_empty()):
		var w: float = float(le["min_x"]) - float(lw["max_x"])
		var h: float = float(li["bottom"]) - GROUND_TOP
		_check("root_hole_w_0.24", absf(w - HOLE_W) < GEO_EPS)
		_check("root_hole_h_0.30", absf(h - HOLE_H) < GEO_EPS)
		_check("root_barrier_top_+0.50", absf(float(lw["top"]) - GROUND_TOP - BARRIER_HEIGHT) < GEO_EPS
			and absf(float(le["top"]) - float(lw["top"])) < GEO_EPS)
		_check("root_barrier_bottom_at_ground", absf(float(lw["bottom"]) - GROUND_TOP) < GEO_EPS)
		# 屏障横贯 Roots（西端 = 区域边界 x=10，东端 = 36）
		_check("root_barrier_spans_roots", absf(float(lw["min_x"]) - 10.0) < GEO_EPS
			and absf(float(le["max_x"]) - 36.0) < GEO_EPS)
		# 尺度判据（从配置口径算：鼠站立 0.12×0.18、猫站立 0.32×0.48、猫蹲 0.32×0.30）
		_check("mouse_stand_fits_root_hole", 0.12 <= w and 0.18 <= h)
		_check("cat_stand_blocked_by_root_hole", 0.32 > w or 0.48 > h)

		_check("cat_crouch_blocked_by_root_hole", 0.32 > w)
		print("VERIFY|RootHole|w=%.3f|h=%.3f|barrier_top=%.3f|span=[%.2f,%.2f]" % [
			w, h, float(lw["top"]), float(lw["min_x"]), float(le["max_x"])
		])

	# ART03-④：树桩视觉必须与玩法孔**同轴同尺寸**（错位就等于"洞画在树桩旁边"）。
	# 南北各一桩：内端面分别贴 z=BARRIER_Z_MIN / BARRIER_Z_MAX，孔与玩法孔首尾相接。
	var stump_hd: float = ROOT_HOLE_SIZE.z * 0.5
	for pair in [["RootHoleStumpS", BARRIER_Z_MIN - stump_hd, "s"],
			["RootHoleStumpN", BARRIER_Z_MAX + stump_hd, "n"]]:
		var nm: String = pair[0]
		var want_z: float = pair[1]
		var tag: String = pair[2]
		var stump := scene.get_node_or_null(nm) as Node3D
		if not _check("root_hole_stump_%s_exists" % tag, stump != null):
			continue
		_check("root_hole_stump_%s_is_asset" % tag, stump.scene_file_path == ROOT_HOLE_ASSET)
		_check("root_hole_stump_%s_no_collision" % tag, _count_collision_shapes(stump) == 0)
		_check("root_hole_stump_%s_not_in_nav_group" % tag,
			not stump.is_in_group("nav_source_courtyard"))
		_check("root_hole_stump_%s_on_ground" % tag, absf(stump.position.y - GROUND_TOP) < 1e-4)
		_check("root_hole_stump_%s_axis_x" % tag, absf(stump.position.x - HOLE_CENTER_X) < 1e-4)
		_check("root_hole_stump_%s_abuts_barrier" % tag, absf(stump.position.z - want_z) < 1e-4)
		# 一旦有人给实例加旋转/缩放，资产里烘好的 0.24×0.30 孔就与玩法孔不再一致
		_check("root_hole_stump_%s_unrotated" % tag,
			stump.rotation_degrees.length() < 1e-4 and stump.scale.is_equal_approx(Vector3.ONE))

	var wa := _box(scene, "CreekBankWallA")
	var wb := _box(scene, "CreekBankWallB")
	if _check("creek_bank_walls_exist", not wa.is_empty() and not wb.is_empty()):
		var gap: float = float(wb["min_x"]) - float(wa["max_x"])
		var wall_h: float = float(wa["top"]) - GROUND_TOP
		_check("creek_gap_w_0.24", absf(gap - BANK_GAP) < GEO_EPS)
		_check("creek_wall_h_1.00", absf(wall_h - BANK_WALL_HEIGHT) < GEO_EPS)
		_check("creek_gap_center_x", absf((float(wb["min_x"]) + float(wa["max_x"])) * 0.5 - BANK_GAP_CENTER_X) < GEO_EPS)
		_check("mouse_fits_creek_gap", 0.12 <= gap)
		_check("cat_blocked_by_creek_gap_width", 0.32 > gap)
		_check("cat_cannot_jump_creek_wall", wall_h > 0.55)     # 猫跳净空实测 0.5502
		print("VERIFY|CreekGap|gap=%.3f|wall_h=%.3f|center_x=%.3f" % [gap, wall_h, (float(wb["min_x"]) + float(wa["max_x"])) * 0.5])

	var water := scene.get_node_or_null("CreekWater") as MeshInstance3D
	if _check("creek_water_exists", water != null):
		_check("creek_water_has_no_collision", _count_collision_shapes(water) == 0)
		_check("creek_water_is_mesh_only", water is MeshInstance3D and water.get_node_or_null("Shape") == null)
		var bm := water.mesh as BoxMesh
		_check("creek_water_top_0.13", bm != null and absf(water.position.y + bm.size.y * 0.5 - 0.13) < GEO_EPS)

	# ART01：溪边掩体补上的视觉（原来 MISSING）
	var creek_vis := scene.get_node_or_null("CreekReedCoverMesh") as Node3D
	if _check("creek_cover_visual_exists", creek_vis != null):
		_check("creek_cover_visual_is_asset", creek_vis.scene_file_path == BUSH_ASSET)
		_check("creek_cover_visual_no_collision", _count_collision_shapes(creek_vis) == 0)

	# ART03-②：溪边巨石换正式资产 —— 视觉来自 .glb，碰撞仍是 Godot 侧 BoxShape3D
	var boulder := _box(scene, "CreekBoulder")
	if _check("creek_boulder_box_ok", not boulder.is_empty()):
		var b_size: Vector3 = boulder["size"]
		_check("creek_boulder_collision_matches_asset",
			absf(b_size.x - BOULDER_SIZE.x) < 1e-4 and absf(b_size.y - BOULDER_SIZE.y) < 1e-4
			and absf(b_size.z - BOULDER_SIZE.z) < 1e-4)
		_check("creek_boulder_rests_on_ground", absf(float(boulder["bottom"]) - GROUND_TOP) < 1e-4)
		var b_vis := scene.get_node_or_null("CreekBoulder/Mesh") as Node3D
		if _check("creek_boulder_visual_exists", b_vis != null):
			_check("creek_boulder_visual_is_asset", b_vis.scene_file_path == BOULDER_ASSET)
			# glb 原点在脚底 → 实例必须下沉半个包围盒高，否则视觉会整块浮在碰撞盒上方
			_check("creek_boulder_visual_sunk", absf(b_vis.position.y + BOULDER_SIZE.y * 0.5) < 1e-4)
			_check("creek_boulder_visual_no_collision", _count_collision_shapes(b_vis) == 0)

	for c in COVERS:
		var area := scene.get_node_or_null(c["node"]) as Area3D
		if not _check("cover_%s_exists" % String(c["node"]).to_lower(), area != null):
			continue
		_check("cover_%s_factor_0.4" % String(c["node"]).to_lower(),
			absf(float(area.get_meta("visibility_factor", 0.0)) - COVER_FACTOR) < 1e-9)
		# ART01：视觉必须是 glb 实例，且**不带碰撞**（掩体不是实体，逻辑只认上面的 Area3D）
		var vis := scene.get_node_or_null("%sMesh" % c["node"]) as Node3D
		if _check("cover_%s_visual_exists" % String(c["node"]).to_lower(), vis != null):
			_check("cover_%s_visual_is_asset" % String(c["node"]).to_lower(),
				vis.scene_file_path == BUSH_ASSET)
			_check("cover_%s_visual_no_collision" % String(c["node"]).to_lower(),
				_count_collision_shapes(vis) == 0)
			var bush_mi := _find_first_mesh(vis)
			if _check("cover_%s_visual_mesh" % String(c["node"]).to_lower(),
					bush_mi != null and bush_mi.mesh != null):
				var bsz: Vector3 = bush_mi.mesh.get_aabb().size
				_check("cover_%s_visual_size" % String(c["node"]).to_lower(),
					bsz.x >= 2.5 and bsz.x <= 3.1 and bsz.z >= 2.5 and bsz.z <= 3.1
					and bsz.y >= 0.80 and bsz.y <= 1.00)
				print("VERIFY|CoverBush|%s|mesh_size=(%.3f, %.3f, %.3f)" % [
					c["node"], bsz.x, bsz.y, bsz.z])
	var dz := scene.get_node_or_null("DangerZone") as Area3D
	if _check("danger_zone_exists", dz != null):
		var cs := dz.get_node_or_null("Shape") as CollisionShape3D
		var box := cs.shape as BoxShape3D
		_check("danger_zone_borders_courtyard", absf(dz.position.z + box.size.z * 0.5 - 2.0) < GEO_EPS)
	# 出生点→补给点走廊（与测试同一算法，工具先兜一遍）
	_check("corridor_spawn_cat_food", _segment_clear(scene, CAT_SPAWN, SUPPLIES[0]["pos"]))
	_check("corridor_spawn_mouse_food", _segment_clear(scene, MOUSE_SPAWN, SUPPLIES[1]["pos"]))
	_check("corridor_spawn_cat_water", _segment_clear(scene, CAT_SPAWN, SUPPLIES[4]["pos"]))
	_check("corridor_spawn_mouse_water", _segment_clear(scene, MOUSE_SPAWN, SUPPLIES[4]["pos"]))

	# 躲藏点（T020）：树根洞里恰好 1 个**鼠**躲藏点（猫层在洞里没有导航面，见 T012）
	var hole_spot := scene.get_node_or_null("HideSpot_RootHole") as Marker3D
	if _check("hide_spot_root_hole_exists", hole_spot != null):
		_check("hide_spot_root_hole_group", hole_spot.is_in_group("hide_spots"))
		_check("hide_spot_root_hole_species", StringName(hole_spot.get_meta("species", &"")) == &"Mouse")
		var hide_z: float = (BARRIER_Z_MIN + BARRIER_Z_MAX) * 0.5
		_check("hide_spot_root_hole_pos",
			hole_spot.position.distance_to(Vector3(HOLE_CENTER_X, GROUND_TOP, hide_z)) < GEO_EPS)
		_check("hide_spot_root_hole_in_hole_span", absf(hole_spot.position.x - HOLE_CENTER_X) <= HOLE_W * 0.5)
		_check("hide_spot_root_hole_radius_0.30", absf(float(hole_spot.get_meta("radius", 0.0)) - 0.30) < GEO_EPS)
		print("VERIFY|HideSpot|id=%s|pos=(%.2f, %.2f, %.2f)|radius=%.2f" % [
			hole_spot.name, hole_spot.position.x, hole_spot.position.y, hole_spot.position.z,
			float(hole_spot.get_meta("radius", 0.0))
		])
	scene.free()


# ---------------------------------------------------------------------------
# 自检用的小工具（**用纯几何**：场景未入树，不能做物理查询）
# ---------------------------------------------------------------------------

func _box(scene: Node3D, nm: String) -> Dictionary:
	var sb := scene.get_node_or_null(nm) as StaticBody3D
	if sb == null:
		return {}
	var cs := sb.get_node_or_null("Shape") as CollisionShape3D
	var box := cs.shape as BoxShape3D if cs != null else null
	if box == null:
		return {}
	var center: Vector3 = sb.position
	var half := box.size * 0.5
	return {
		"body": sb, "size": box.size, "center": center,
		"top": center.y + half.y, "bottom": center.y - half.y,
		"min_x": center.x - half.x, "max_x": center.x + half.x,
		"min_z": center.z - half.z, "max_z": center.z + half.z,
	}


## 点是否在指定区域的数据体量内（x/z 用区域矩形，y 用体量高度）
func _inside_rect(scene: Node3D, p: Vector3, region_id: String) -> bool:
	var rn := scene.get_node_or_null("Region_%s" % region_id) as Node3D
	if rn == null:
		return false
	var cs := rn.get_node_or_null("Volume/Shape") as CollisionShape3D
	var box := cs.shape as BoxShape3D if cs != null else null
	if box == null:
		return false
	var half := box.size * 0.5
	return absf(p.x - rn.position.x) <= half.x + GEO_EPS \
		and absf(p.z - rn.position.z) <= half.z + GEO_EPS \
		and absf(p.y - rn.position.y) <= half.y + GEO_EPS


func _count_collision_shapes(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is CollisionShape3D or ch is CollisionObject3D:
			c += 1
		c += _count_collision_shapes(ch)
	return c


## glb 实例的层级是 Node3D → MeshInstance3D，网格不一定在第一层 → 递归找第一个
func _find_first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for ch in n.get_children():
		var r := _find_first_mesh(ch)
		if r != null:
			return r
	return null


## 走廊是否通畅（纯几何）：沿线段每 0.1 m 取一点，`height` = 离地高度、`radius` = 球半径，
## 判据 = 该点不在任何 world_static 盒子的"膨胀 AABB"内（本关卡的静态盒子都是轴对齐的）。
## **必须用离地高度**：贴着地面的采样点会被地面自己判成阻挡（地面顶 y=0.10）。
## 取 0.20 m：两种物种实测台阶能力 ≤0.12 m，能被"跨过去"的低矮物不算阻挡；高于 0.20 m 的会被抓到。
func _segment_clear(scene: Node3D, a: Vector3, b: Vector3) -> bool:
	return _segment_clear_at(scene, a, b, 0.20, 0.10)


func _segment_clear_at(scene: Node3D, a: Vector3, b: Vector3, height: float, radius: float) -> bool:
	var boxes := _all_static_boxes(scene)
	var seg := b - a
	var steps := int(maxf(1.0, seg.length() / 0.1))
	for i in range(steps + 1):
		var p: Vector3 = a + seg * (float(i) / float(steps))
		p.y = GROUND_TOP + height
		for bx in boxes:
			if _point_near_box(p, bx, radius):
				print("VERIFY|corridor_blocked|at=%s|by=%s" % [p, bx["name"]])
				return false
	return true


func _all_static_boxes(scene: Node3D) -> Array:
	var out: Array = []
	for ch in scene.get_children():
		var sb := ch as StaticBody3D
		if sb == null:
			continue
		var cs := sb.get_node_or_null("Shape") as CollisionShape3D
		var box := cs.shape as BoxShape3D if cs != null else null
		if box == null:
			continue
		var half := box.size * 0.5
		out.append({
			"name": sb.name, "min": sb.position - half, "max": sb.position + half,
		})
	return out


func _point_near_box(p: Vector3, bx: Dictionary, r: float) -> bool:
	var lo: Vector3 = bx["min"] - Vector3(r, r, r)
	var hi: Vector3 = bx["max"] + Vector3(r, r, r)
	return p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y and p.z >= lo.z and p.z <= hi.z


func _check(id: String, ok: bool) -> bool:
	if not ok:
		_fails += 1
	print("VERIFY|%s|%s" % [id, "OK" if ok else "FAIL"])
	return ok
