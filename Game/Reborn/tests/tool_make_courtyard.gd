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
const WATER_SIZE := Vector3(22.0, 0.03, 9.0)   # ART03-⑥：20→9，从"池塘"收成"溪带"（仍覆盖 WaterPoint_Creek 的 z=16）
const WATER_CENTER := Vector3(-23.0, GROUND_TOP + 0.015, 16.0)
const WATER_DEPTH := 0.03
## ART03-⑥：溪水/溪边的视觉。水面用**程序化 shader**（流动+涟漪+岸边泡沫），
## 溪岸补湿泥带与芦苇丛，让"一整块纯蓝平面 + 一小丛草"不再那么假。
## 注意：这些全是 **MeshInstance3D**（零碰撞、不进导航组），玩法与 T011 断言零影响。
const WATER_SHADER := "res://shaders/creek_water.gdshader"
## ART03-⑦：草丛/芦苇的风摆动 shader（叶尖摆、根部不动；每丛相位不同）
const GRASS_WIND_SHADER := "res://shaders/grass_wind.gdshader"
## ART03-⑫：地面程序化材质（草地/土/干草斑块），只换材质不动几何
const GROUND_SHADER := "res://shaders/ground.gdshader"
## ART13：庭院地表贴图（复用 ART11 已入库 CC0 leafy_grass，见 Docs/THIRD_PARTY_ASSETS.md §9.1）
const GROUND_TEX_DIFF := "res://assets/environment/tex/leafy_grass_diff_1k.jpg"
const GROUND_TEX_NOR := "res://assets/environment/tex/leafy_grass_nor_gl_1k.jpg"
const GROUND_TEX_ARM := "res://assets/environment/tex/leafy_grass_arm_1k.jpg"
## ART03-⑬：土墩与棚顶的正式资产（极低面数，原点在脚印中心 + 底面 y=0）
const MOUND_ASSET := "res://assets/environment/sm_mound_001.glb"
const ROOF_ASSET := "res://assets/environment/sm_roof_001.glb"
## ART03-⑭：树根屏障本体的盘根模块（实测 2.461093 长 × 0.480000 高 × 0.295729 厚，640 tris）
const ROOT_BARRIER_ASSET := "res://assets/environment/sm_root_barrier_001.glb"
const ROOT_BARRIER_MOD_LEN := 2.461093
const ROOT_BARRIER_MOD_H := 0.480000
## ART03-⑮：矮墙专用模块（源件里本来就矮的那件，真实比例 1.6221 × 0.7738 × 0.1989，238 tris）
## 之前庇护棚 1.6 m 墙是把 3 m 模块压到 1.6 m（k=0.533）→ 石块被竖着压扁；现在改成**叠两层**
const WALL_LOW_ASSET := "res://assets/environment/sm_wall_low_001.glb"
const WALL_LOW_LEN := 2.436584
const WALL_LOW_H := 0.800000
const WALL_LOW_THICK := 0.302739
## 衬板在**敞开端**收进的量（转角端必须铺满，否则能看穿到棚内）
const BACKING_TRIM := 0.150000
## ART03-⑮-3：转角料石（quoin）—— 压住两片矮墙在转角处各自内缩的石排端，176 tris。
## 一件 = 4 皮**不同长宽高**的砌石（相邻层转 90°），总高 = 墙高 1.6，运行时每转角只摆一件。
const QUOIN_ASSET := "res://assets/environment/sm_quoin_001.glb"
const QUOIN_H := 1.600000        # 整件高度（= SHELTER_WALL_H）
const QUOIN_MIN_FOOT := 0.382    # 最小平面边长（要盖住墙厚 + 两侧石块外凸）
const QUOIN_MAX_FOOT := 0.422    # 最大平面边长（决定外凸量）
## ART03-⑮-2：门框立柱（收边 + 给棚顶东侧补支撑）—— 程序化木柱，28 tris
const SHELTER_POST_ASSET := "res://assets/environment/sm_shelter_post_001.glb"
const SHELTER_POST_W := 0.160000
const SHELTER_POST_D := 0.360000
const SHELTER_POST_H := 1.620000
## 立柱中心 x = SHELTER_X_MAX + PROUD − POST_W/2 → 东侧面向外凸出 PROUD，整片压住墙端
const SHELTER_POST_PROUD := 0.040000
## 芦苇丛位置（沿溪岸一圈，避开水面中心；尺度/朝向下面对应打散）
const REED_SPOTS := [
	{"x": -32.0, "z": 20.9, "yaw": 12.0, "s": 0.95},
	{"x": -27.5, "z": 21.1, "yaw": 78.0, "s": 1.05},
	{"x": -22.0, "z": 20.8, "yaw": 155.0, "s": 0.88},
	{"x": -16.5, "z": 21.0, "yaw": 210.0, "s": 1.00},
	{"x": -30.5, "z": 11.1, "yaw": 40.0, "s": 0.92},
	{"x": -25.0, "z": 11.0, "yaw": 130.0, "s": 1.02},
	{"x": -18.5, "z": 11.2, "yaw": 265.0, "s": 0.86},
	{"x": -14.0, "z": 11.3, "yaw": 300.0, "s": 0.94},
	{"x": -34.4, "z": 13.5, "yaw": 330.0, "s": 0.98},
	{"x": -34.2, "z": 18.5, "yaw": 25.0, "s": 1.06},
	{"x": -11.7, "z": 14.0, "yaw": 190.0, "s": 0.90},
	{"x": -11.9, "z": 19.0, "yaw": 300.0, "s": 1.04},
	{"x": -22.5, "z": 16.2, "yaw": 96.0, "s": 0.72},
]

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
## ART03-⑧：草丛换成重做的 `sm_bush_002`（带中脊折面的弯曲叶片 + 210 片/2,600 tris）。
## 旧 `sm_bush_001` 是单层平面叶片（2040 tris），近距离就是"绿纸条"，保留在仓库里可回退。
const BUSH_ASSET := "res://assets/environment/sm_bush_002.glb"
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


## ART09 天空球：CC0（Poly Haven `mossy_forest`，2k Radiance HDR）。
## 用途：菜单/实玩的背景天空；来源与许可见 `Docs/THIRD_PARTY_ASSETS.md`。
const SKY_HDRI_PATH := "res://assets/environment/hdri/mossy_forest_2k.hdr"
const ROUTE_SHORT_START := Vector3(2.0, GROUND_TOP, 2.0)
const ROUTE_SHORT_END := Vector3(2.0, GROUND_TOP, -22.0)

# --- ART07：构图 / 接触感 / 背光试作（全部为固定数组，确定性；一律**无碰撞**、**不进**导航组）-----
## 为什么需要：基线视觉判读（`Art/Probes/art07_before/t011_map_overview.png`）的结论是
## 「整场一层平」——80×80 地面 + 3 m 围墙 + 3 丛草，中远景没有任何分离手段，远景与近景
## 同一亮度与对比；草丛/石头贴地但缺接地阴影，远处读成"贴纸"。
## 下面这些节点只做**画面**：零碰撞、不进 `nav_source_courtyard`、不改变任何静态碰撞体，
## 所以 T011/T012/T026/T027 的几何与导航口径全部原样。
const GROUND_SHADOW_LIFT := 0.007            # 接地阴影离地 7 mm（地面顶 0.10 → 0.107）
const GROUND_SHADOW_COLOR := Color(0.055, 0.066, 0.050)
const GROUND_SHADOW_ALPHA_K := 3.2            # 接触阴影强度倍率（1.0 判"看不出"、1.7 判"底部没有压暗"；
                                              # 外扩 + 径向渐隐后中心峰值抬高，外露的一圈才有读数）
const GROUND_SHADOW_SPREAD := 1.75            # 阴影尺寸 = 脚印 × 1.75（**必须**明显大于冠层轮廓：
                                              # 收在脚印内的暗片会被草叶从上方盖住 → 判"没有 AO"）
## 溪道里的非碰撞石头（复用 `sm_boulder_001`）：打散"22×9 直带水面 + 几块泥舌"的矩形感。
## 位置全部落在水面矩形内（x∈[−34,−12]、z∈[11.5,20.5]），且离鼠车道（缝中心 x=−31.73、宽 0.24）足够远。
## **ART07 验收判读修正（视觉失败项）**：原 `CreekRock05` 在 (−33.2, 12.4) —— x 仅离缝轴 1.47 m、z 又落在岸墙跨度内，
## 在 `t011_creek_gap_lane` 机位（正对缝口、机位就在缝轴上）里正好压在**缝口左外侧的墙脚**，
## 判读为"石头+草丛把 0.24 m 鼠路线挤窄/视觉上封住"。现在把这条石头后移到溪心 (−24.5, 19.3)，
## 并把"缝轴两侧 ≥1.6 m（当 z 落在岸墙跨度内）"写成 `_verify` 的硬断言 `decor_clear_of_creek_gap_mouth`。
const CREEK_ROCKS := [
	{"x": -30.2, "z": 18.6, "yaw": 22.0, "s": 0.46},
	{"x": -26.4, "z": 12.9, "yaw": 133.0, "s": 0.52},
	{"x": -21.2, "z": 19.1, "yaw": 258.0, "s": 0.38},
	{"x": -16.2, "z": 13.1, "yaw": 302.0, "s": 0.60},
	{"x": -13.3, "z": 18.3, "yaw": 78.0, "s": 0.34},
	{"x": -24.5, "z": 19.3, "yaw": 196.0, "s": 0.40},
]
## 背景层草簇：贴围墙脚 / 场地边角，只提供中远景剪影。
## 约束：不进 `danger_zones`（开阔暴露区必须保持开阔）、离任何 `cover_volumes` 中心 ≥3 m，位置**未改**。
## **ART07 收尾轮 #2**：vision 判"背景草簇没有形成分层"。原因之一是从 45° 俯瞰时它们只有 1.6～1.9 m 宽，
## 在 40～90 m 的视距下就是几个像素的绿点。这里只把尺度统一抬到 0.70～0.86（仍明显小于 3×3 m 掩体的
## 1.00 尺度，避免读成"假掩体"），配合 `grass_wind.gdshader` 的根部压暗 + 逐实例明暗差，
## 让围墙脚形成一条**中景暗色草带**，而不是靠加雾/加贴片造纵深。位置、数量（10）、朝向全部保持原值。
const SCENERY_BUSHES := [
	{"x": -33.6, "z": 26.6, "yaw": 24.0, "s": 0.78},
	{"x": -27.8, "z": 28.5, "yaw": 78.0, "s": 0.70},
	{"x": -13.2, "z": 28.6, "yaw": 140.0, "s": 0.76},
	{"x": 13.4, "z": 28.5, "yaw": 205.0, "s": 0.74},
	{"x": 33.2, "z": 26.2, "yaw": 300.0, "s": 0.80},
	{"x": 34.0, "z": 3.0, "yaw": 45.0, "s": 0.84},
	{"x": -34.2, "z": 2.8, "yaw": 120.0, "s": 0.76},
	{"x": -33.6, "z": -24.0, "yaw": 200.0, "s": 0.86},
	{"x": 34.0, "z": -24.2, "yaw": 264.0, "s": 0.84},
	{"x": -12.6, "z": -24.6, "yaw": 330.0, "s": 0.72},
]
## ART07 收尾轮 #2（续）：vision 判围墙脚草簇"零星、点状、极其稀疏，没有连成带"。
## 因此沿同一条墙脚线**加密** 6 株（同资产、同规则：零碰撞、不进导航组、不进危险区、离掩体 ≥2 m），
## 让北墙/东西墙脚各读成一小段连续草带；尺度仍 ≤0.86（明显小于 1.00 的掩体草丛）。
## **ART12（C 阶段，2026-11-02）**：ART07 收口轮 vision 复判墙脚草带"仍点状散落"。
## 空档分析：北墙中部 x∈[-13.2, 13.4] 有 26 m 空档；西墙 z∈[-24.0, 2.8]、东墙 z∈[-24.2, 3.0]
## 各有两段 11～16 m 空档。再补 8 株（同规则，尺度压到 ≤0.74）把三段最大空档填上；
## 北墙中部株 z≈28 全部在 `danger_zones`（z∈[-22, 2]）之外，开阔暴露区保持开阔。
const SCENERY_BUSHES_FILL := [
	{"x": -21.0, "z": 28.4, "yaw": 55.0, "s": 0.74},
	{"x": -18.2, "z": 27.6, "yaw": 12.0, "s": 0.70},
	{"x": 20.4, "z": 28.2, "yaw": 168.0, "s": 0.76},
	{"x": 24.6, "z": 27.4, "yaw": 240.0, "s": 0.72},
	{"x": -34.2, "z": -8.4, "yaw": 310.0, "s": 0.70},
	{"x": 34.2, "z": -8.0, "yaw": 96.0, "s": 0.72},
	# ART12 新增（北墙中部 26 m 空档 ×4 + 东西墙各两段空档 ×4）
	{"x": -8.5, "z": 28.2, "yaw": 88.0, "s": 0.72},
	{"x": -3.0, "z": 27.8, "yaw": 152.0, "s": 0.70},
	{"x": 2.5, "z": 28.3, "yaw": 26.0, "s": 0.74},
	{"x": 8.0, "z": 27.9, "yaw": 214.0, "s": 0.71},
	{"x": -34.2, "z": -16.2, "yaw": 300.0, "s": 0.70},
	{"x": -34.1, "z": -3.2, "yaw": 68.0, "s": 0.72},
	{"x": 34.2, "z": -16.0, "yaw": 112.0, "s": 0.72},
	{"x": 34.1, "z": -2.8, "yaw": 246.0, "s": 0.70},
]
## 庭院内的前景小石（纯视觉）：给出生点附近一个近景参考物，不压出生→补给走廊。
const COURTYARD_ROCKS := [
	{"x": 1.2, "z": 21.4, "yaw": 34.0, "s": 0.26},
	{"x": -1.4, "z": 19.6, "yaw": 190.0, "s": 0.20},
	{"x": 4.6, "z": 22.2, "yaw": 96.0, "s": 0.30},
]
## 泥舌"半岛"：比现有锯齿更大的泥岸，探进水面，并在上面长草。
## 用途：让水边读成"不规则的岸"而不是"被一排小板子遮住的矩形"。
const MUD_PENINSULAS := [
	{"x": -19.5, "z": 19.4, "sx": 3.2, "sz": 2.2, "yaw": 6.0, "grass_s": 0.50},
	{"x": -23.6, "z": 12.6, "sx": 2.6, "sz": 1.8, "yaw": -8.0, "grass_s": 0.44},
	{"x": -12.9, "z": 16.9, "sx": 1.6, "sz": 2.8, "yaw": 3.0, "grass_s": 0.42},
	{"x": -28.6, "z": 19.2, "sx": 2.4, "sz": 1.7, "yaw": -5.0, "grass_s": 0.42},
	{"x": -27.2, "z": 12.3, "sx": 3.0, "sz": 1.9, "yaw": 4.0, "grass_s": 0.48},
]

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
	_add_composition_dressing(root_node)
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
	var ground := _mk_box(parent, "Ground", GROUND_SIZE, Vector3.ZERO, Vector3.ZERO,
		Color(0.32, 0.34, 0.36))
	_apply_material_override(ground, GROUND_SHADER, "ground")
	# ART13（2026-11-02）：庭院地表接 leafy_grass（复用 ART11 已入库 CC0 贴图，双尺度混合）。
	# 判读依据：vision 对 t011_grass_danger 的头号不满="地表贴图糊脏、与植被割裂"——
	# 程序化三色斑块在近景读成迷彩。贴图路径保留程序化低频斑块作明度调制（草/土区域感不丢）。
	# tint 偏冷绿（庭院是冷天光，展板关的 0.82/0.88/0.74 偏暖是 golden hour 用的）。
	var mi := ground.get_node_or_null("Mesh") as MeshInstance3D
	if mi != null and mi.material_override is ShaderMaterial:
		var smat := mi.material_override as ShaderMaterial
		var tex_d := load(GROUND_TEX_DIFF) as Texture2D
		var tex_n := load(GROUND_TEX_NOR) as Texture2D
		var tex_m := load(GROUND_TEX_ARM) as Texture2D
		if tex_d != null and tex_n != null and tex_m != null:
			smat.set_shader_parameter(&"tex_amount", 1.0)
			smat.set_shader_parameter(&"tex_albedo", tex_d)
			smat.set_shader_parameter(&"tex_normal", tex_n)
			smat.set_shader_parameter(&"tex_arm", tex_m)
			smat.set_shader_parameter(&"tex_tint", Color(0.85, 0.90, 0.78))
			smat.set_shader_parameter(&"tex_scale_a", Vector2(0.50, 0.50))
			smat.set_shader_parameter(&"tex_scale_b", Vector2(0.17, 0.17))
			print("TOOL|Ground|material=leafy_grass_2scale|tint=0.85,0.90,0.78|a=0.50|b=0.17")
		else:
			print("TOOL|Ground|material=procedural_fallback|tex_missing")
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
	# ART03-⑮：三面矮墙改用真比例矮墙模块**叠两层**（石块不再被压扁）
	_mk_low_wall(parent, "ShelterWallWest", Vector3(FENCE_THICK, SHELTER_WALL_H, len_z),
		Vector3(SHELTER_X_MIN + FENCE_THICK * 0.5, wall_y, cz), col)
	# 东端（门垛）敞开 → 衬板只在这一端收进 BACKING_TRIM；转角端铺满
	_mk_low_wall(parent, "ShelterWallNorth", Vector3(len_x, SHELTER_WALL_H, FENCE_THICK),
		Vector3(cx, wall_y, SHELTER_Z_MAX - FENCE_THICK * 0.5), col, 1)
	_mk_low_wall(parent, "ShelterWallSouth", Vector3(len_x, SHELTER_WALL_H, FENCE_THICK),
		Vector3(cx, wall_y, SHELTER_Z_MIN + FENCE_THICK * 0.5), col, 1)
	# ART03-⑮-2：门洞两侧的直立端用**门框立柱**收边（矮墙模块两端是开口壳体），
	# 同时补上棚顶东侧的支撑 —— 原先敞开的一侧没有任何柱子，棚顶像浮空。
	_mk_shelter_post(parent, "ShelterPostSouth",
		Vector3(SHELTER_X_MAX + SHELTER_POST_PROUD - SHELTER_POST_W * 0.5, GROUND_TOP,
			SHELTER_Z_MIN + FENCE_THICK * 0.5))
	_mk_shelter_post(parent, "ShelterPostNorth",
		Vector3(SHELTER_X_MAX + SHELTER_POST_PROUD - SHELTER_POST_W * 0.5, GROUND_TOP,
			SHELTER_Z_MAX - FENCE_THICK * 0.5))
	# ART03-⑮-3：两个外转角加料石（quoin），压住两片墙各自内缩的石排端与衬板竖带
	_mk_corner_quoin(parent, "ShelterQuoinSW",
		SHELTER_X_MIN + FENCE_THICK * 0.5, SHELTER_Z_MIN + FENCE_THICK * 0.5)
	_mk_corner_quoin(parent, "ShelterQuoinNW",
		SHELTER_X_MIN + FENCE_THICK * 0.5, SHELTER_Z_MAX - FENCE_THICK * 0.5)
	# ART03-⑬：棚顶换木板条资产（228 tris，含两根托梁）；碰撞盒（3.4 × 0.2 × 3.8）不变
	var roof := _mk_box(parent, "ShelterRoof", Vector3(len_x + 0.4, 0.2, len_z + 0.2),
		Vector3(cx, GROUND_TOP + SHELTER_WALL_H + 0.1, cz), Vector3.ZERO, col)
	_mk_prop_visual(roof, "ShelterRoofVisual", ROOF_ASSET,
		Vector3((len_x + 0.4) / 3.437582, 1.0, (len_z + 0.2) / 3.771297),
		Vector3(0.0, -0.1, 0.0), "")

	var debris_col := Color(0.62, 0.56, 0.46)
	var debris := [
		Vector3(9.0, GROUND_TOP + 0.15, 27.6),
		Vector3(8.4, GROUND_TOP + 0.15, 26.6),
		Vector3(9.4, GROUND_TOP + 0.15, 25.4),
	]
	for i in debris.size():
		_mk_rock_debris(parent, "CourtyardDebris%d" % (i + 1), Vector3(0.6, 0.3, 0.6),
			debris[i], debris_col, 0.40 + 0.06 * float(i))


# ---------------------------------------------------------------------------
# 草地（§8.2-3：近而危险 / 远而较安全）
# ---------------------------------------------------------------------------

func _add_grass_structures(parent: Node3D) -> void:
	# 开阔暴露区：只做数据体量 + 一块贴地的暗色标记（无碰撞，只给人看）
	_mk_data_area(parent, "DangerZone", DANGER_SIZE, DANGER_CENTER, "danger_zones",
		{"visibility_factor": 1.0, "role": "open_exposure"})
	# ART07：这块标记原来 alpha 0.35，俯视图里读成"铺了一块的浅红地毯"；压到 0.10 只留提示。
	_mk_surface_marker(parent, "DangerZoneMark", Vector3(DANGER_SIZE.x, 0.02, DANGER_SIZE.z),
		Vector3(DANGER_CENTER.x, GROUND_TOP + 0.01, DANGER_CENTER.z), Color(0.55, 0.35, 0.30, 0.10))

	for i in COVERS.size():
		var c: Dictionary = COVERS[i]
		_mk_data_area(parent, c["node"], COVER_SIZE, c["pos"], "cover_volumes",
			{"visibility_factor": COVER_FACTOR, "role": "cover"})
		# 视觉：贴地放在掩体中心（资产原点在草根处），只做视觉、不带碰撞
		_mk_cover_bush(parent, "%sMesh" % c["node"],
			Vector3(float(c["pos"].x), GROUND_TOP, float(c["pos"].z)),
			float(BUSH_YAWS[i]), float(BUSH_SCALES[i]))

	# 猫的观察点（0.50 高，鼠上不去）
	# ART03-⑬：土墩换低模圆丘（198 tris）+ 复用地面 shader 做草/土斑块；碰撞盒不变
	var mound_a := _mk_box(parent, "GrassMoundA", Vector3(2.0, 0.50, 2.0),
		Vector3(-20.0, GROUND_TOP + 0.25, -12.0), Vector3.ZERO, Color(0.30, 0.45, 0.28))
	_mk_prop_visual(mound_a, "GrassMoundAVisual", MOUND_ASSET, Vector3(1.0, 1.0, 1.0),
		Vector3(0.0, -0.25, 0.0), GROUND_SHADER)
	var mound_b := _mk_box(parent, "GrassMoundB", Vector3(2.0, 0.50, 2.0),
		Vector3(14.0, GROUND_TOP + 0.25, -8.0), Vector3.ZERO, Color(0.30, 0.45, 0.28))
	_mk_prop_visual(mound_b, "GrassMoundBVisual", MOUND_ASSET, Vector3(1.06, 1.0, 0.94),
		Vector3(0.0, -0.25, 0.0), GROUND_SHADER)


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

	# ART03-⑭：两段屏障换成盘根模块平铺（碰撞盒 / 洞口净空一字未改）
	var rw := _mk_box(parent, "RootBarrierWest", Vector3(hole_l - BARRIER_MIN_X, BARRIER_HEIGHT, depth),
		Vector3((BARRIER_MIN_X + hole_l) * 0.5, cy, cz), Vector3.ZERO, col)
	_mk_root_barrier_visual(rw, "RootBarrierWestRoots")
	var re := _mk_box(parent, "RootBarrierEast", Vector3(BARRIER_MAX_X - hole_r, BARRIER_HEIGHT, depth),
		Vector3((hole_r + BARRIER_MAX_X) * 0.5, cy, cz), Vector3.ZERO, col)
	_mk_root_barrier_visual(re, "RootBarrierEastRoots")
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

## ART03-⑥：溪边"氛围"层 —— 芦苇丛沿两岸铺开 + 岸边湿泥带。
## 全部是 MeshInstance3D：**没有碰撞**、**不进** `nav_source_courtyard`，所以玩法与导航都不变。
## 为什么需要它：原来的溪边只有**一小丛**芦苇浮在整块纯色水面上，被负责人判为"假"。
func _add_creek_dressing(parent: Node3D) -> void:
	var ps: PackedScene = null
	if ResourceLoader.exists(BUSH_ASSET):
		ps = load(BUSH_ASSET) as PackedScene
	var placed := 0
	if ps != null:
		for i in REED_SPOTS.size():
			var spot: Dictionary = REED_SPOTS[i]
			var inst: Node3D = ps.instantiate() as Node3D
			inst.name = "CreekReed%02d" % i
			parent.add_child(inst)
			inst.owner = parent
			inst.position = Vector3(float(spot["x"]), GROUND_TOP, float(spot["z"]))
			inst.rotation_degrees = Vector3(0.0, float(spot["yaw"]), 0.0)
			inst.scale = Vector3.ONE * float(spot["s"])
			_apply_grass_wind(inst)
			placed += 1
	print("TOOL|CreekReeds|count=%d|asset=%s|via=_add_creek_dressing" % [placed, BUSH_ASSET])

	# 湿泥岸带：贴在水面边缘、略低于水面（0.105 < 水面顶 0.13），让"蓝面直接切到草地"变成
	# "草→湿泥→水"的过渡。四条窄带各 straddle 一条边。
	# ART03-⑦：岸线不再用 4 条笔直湿泥带（那样读起来还是矩形切口），
	# 改成"锯齿泥舌 + 泥舌上的草"让可见水边变弯，另加水下砾石层做深度。
	_add_creek_shore(parent)


## ART03-⑦：把"矩形水面"读成"有岸线的溪"。
##
## 原理：水面的顶面固定在 y=0.13（T011 断言 `creek_water_top_0.13`），而地面是 0.10，
## 所以**不可能**靠"把岸抬高到水面上"来做岸线——那需要改地面网格或改水位（都会碰玩法/断言）。
## 这里用两个纯视觉手段：
##   ① **锯齿泥舌**：沿水面四条边，各自以蜿蜒偏移铺 7 段低矮泥板（顶面 0.155，比水面高 2.5 cm），
##      有的探进水面、有的退回岸上 → 可见水边变成弯的，而且会遮住水面的直边。
##   ② **水下砾石层** `CreekBed`：水面 alpha 0.62 半透明，没有它就透出灰色地面；有了才有深浅层次。
## 两者都是 MeshInstance3D：零碰撞、不进导航组，玩法与 T011 断言完全不受影响。
func _add_creek_shore(parent: Node3D) -> void:
	var mud := Color(0.185, 0.170, 0.145)      # 湿泥：比地面暗一档，才不会读成棕色木板
	var gravel := Color(0.205, 0.198, 0.185)
	var half_x: float = WATER_SIZE.x * 0.5
	var half_z: float = WATER_SIZE.z * 0.5

	# ① 水下砾石层：顶面 0.106（比水面低 2.4 cm，靠水的透明度透出来）
	_mk_surface_marker(parent, "CreekBed", Vector3(WATER_SIZE.x - 0.2, 0.006, WATER_SIZE.z - 0.2),
		Vector3(WATER_CENTER.x, GROUND_TOP + 0.003, WATER_CENTER.z), gravel)

	# ② 锯齿泥舌：北/南两条长边各 7 段，东/西两端各 4 段
	var rim_top: float = 0.142      # 只比水面(0.13)高 1.2 cm
	var rim_h: float = rim_top - GROUND_TOP          # 0.055
	var rim_y: float = GROUND_TOP + rim_h * 0.5
	var seg := 0
	for side in [-1.0, 1.0]:
		var n := 7
		for i in n:
			var t: float = (float(i) + 0.5) / float(n)
			var x: float = WATER_CENTER.x - half_x + (half_x * 2.0) * t
			# 蜿蜒：奇数段探进水里（-0.45），偶数段退到岸上（+0.42）
			var inward: float = -0.45 if i % 2 == 0 else 0.42
			var z: float = WATER_CENTER.z + side * (half_z + inward)
			var nm := "CreekShore%s%02d" % ["S" if side < 0.0 else "N", i]
			# 尺寸/明暗按段号做确定性抖动：3.5×0.95 定死会读成"同规格木板"
			var w: float = 0.62 + 0.5 * absf(sin(float(i) * 2.3 + side))
			var l: float = 2.6 + 1.7 * absf(cos(float(i) * 1.7))
			var tone: float = 0.88 + 0.16 * absf(sin(float(i) * 1.1 + side * 0.7))
			var mi := _mk_surface_marker(parent, nm, Vector3(l, rim_h, w),
				Vector3(x, rim_y, z), Color(mud.r * tone, mud.g * tone, mud.b * tone))
			mi.rotation_degrees = Vector3(0.0, 11.0 * side * sin(float(i) * 1.3), 0.0)
			seg += 1
			# 泥舌上长草（隔一段一丛，避免整齐排队）
			if i % 2 == 0 and ResourceLoader.exists(BUSH_ASSET):
				var ps: PackedScene = load(BUSH_ASSET) as PackedScene
				if ps != null:
					var inst: Node3D = ps.instantiate() as Node3D
					inst.name = "%sGrass" % nm
					parent.add_child(inst)
					inst.owner = parent
					inst.position = Vector3(x + 1.1 * side, GROUND_TOP, z)
					inst.rotation_degrees = Vector3(0.0, 47.0 * float(i), 0.0)
					inst.scale = Vector3.ONE * (0.62 + 0.05 * float(i % 4))
					_apply_grass_wind(inst)
	for side in [-1.0, 1.0]:
		var n := 4
		for i in n:
			var t: float = (float(i) + 0.5) / float(n)
			var z: float = WATER_CENTER.z - half_z + (half_z * 2.0) * t
			var inward: float = -0.4 if i % 2 == 0 else 0.38
			var x: float = WATER_CENTER.x + side * (half_x + inward)
			var nm := "CreekShore%s%02d" % ["W" if side < 0.0 else "E", i]
			var w: float = 0.60 + 0.45 * absf(cos(float(i) * 2.1 + side))
			var l: float = 2.3 + 1.4 * absf(sin(float(i) * 1.9))
			var tone: float = 0.88 + 0.16 * absf(cos(float(i) * 1.2 + side * 0.5))
			var mi := _mk_surface_marker(parent, nm, Vector3(w, rim_h, l),
				Vector3(x, rim_y, z), Color(mud.r * tone, mud.g * tone, mud.b * tone))
			mi.rotation_degrees = Vector3(0.0, 11.0 * side * cos(float(i) * 1.5), 0.0)
			seg += 1

	# ③ ART13 S5：水线湿泥带（A7"水岸硬切"）——半透明暗棕贴地片，中线压在水线上：
	# 伸进水里的半幅沉在水面(0.13)之下、透过半透明水面读作湿泥；上岸的半幅渐隐读作水渍。
	# 北/南岸各 2 段，只铺缝口保护区（x∈[-33.3,-30.1]，缝轴两侧 1.6 m）以东。
	# 规格原文写"径向渐变"，实测长条用径向会中段成团（S4 围栏脚同结论），改用 S4 的线性带状渐变。
	for side in [-1.0, 1.0]:
		var shore_z: float = WATER_CENTER.z + side * half_z
		var side_tag := "S" if side < 0.0 else "N"
		for seg_i in 2:
			var seg_len: float = 9.5 if seg_i == 0 else 9.0
			var seg_min_x: float = -30.0 if seg_i == 0 else -20.5
			_mk_wet_band(parent, "CreekWetBand%s%d" % [side_tag, seg_i + 1],
				Vector3(seg_min_x + seg_len * 0.5, 0.0, shore_z + side * 0.15),
				Vector2(seg_len, 0.9), 0.30, 0.0)
	print("TOOL|CreekWetBand|segments=4|alpha=0.30|y=%.3f" % (GROUND_TOP + GROUND_SHADOW_LIFT))
	print("TOOL|CreekShore|segments=%d|rim_top=%.3f|bed_y=%.3f" % [
		seg, rim_top, GROUND_TOP + 0.003])


func _add_creek_structures(parent: Node3D) -> void:
	# 水面：只有网格，**没有碰撞**（可通行）
	var mi := MeshInstance3D.new()
	mi.name = "CreekWater"
	mi.position = WATER_CENTER
	var bm := BoxMesh.new()
	bm.size = WATER_SIZE
	mi.mesh = bm
	# 材质：优先程序化水面 shader（流动 + 涟漪 + 岸边泡沫）；shader 缺失则退回旧的纯色
	# 为什么：旧材质是**完全静态**的纯色平面，负责人直接指出"水都不带动的"。
	# 注意水面节点本身必须保持 BoxMesh（T011 的 creek_water_mesh_is_box / top_0.13 / depth_0.03），
	# 运动只做在片元里，不做顶点位移。
	var shader_res := load(WATER_SHADER) as Shader
	if shader_res != null:
		var smat := ShaderMaterial.new()
		smat.shader = shader_res
		smat.set_shader_parameter(&"shallow_color", Color(0.281, 0.514, 0.596))
		smat.set_shader_parameter(&"deep_color", Color(0.121, 0.286, 0.376))
		smat.set_shader_parameter(&"foam_color", Color(0.858, 0.898, 0.925))
		smat.set_shader_parameter(&"flow_dir", Vector2(-0.92, 0.39))
		smat.set_shader_parameter(&"flow_speed", 0.42)
		smat.set_shader_parameter(&"ripple_scale", 3.4)
		smat.set_shader_parameter(&"ripple_strength", 0.35)
		smat.set_shader_parameter(&"base_alpha", 0.62)
		mi.material_override = smat
		print("TOOL|CreekWater|material=shader|%s" % WATER_SHADER)
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.20, 0.45, 0.65, 0.60)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.15
		mi.material_override = mat
		print("TOOL|CreekWater|material=FALLBACK_STATIC|shader_missing=%s" % WATER_SHADER)
	mi.set_meta("water_depth", WATER_DEPTH)
	mi.add_to_group("water_bodies", true)
	parent.add_child(mi)
	mi.owner = parent

	# 溪边隐蔽入口：两道 1.00 高的岸墙夹出 0.24 的缝
	var cy: float = GROUND_TOP + BANK_WALL_HEIGHT * 0.5
	var bank_col := Color(0.42, 0.40, 0.38)
	# ART03-⑫：岸墙换成和围栏同一套石墙模块（碰撞盒尺寸/位置一字未改，仍是 0.30 × 1.00 × 8.00）
	_mk_clad_wall(parent, "CreekBankWallA", Vector3(BANK_WALL_THICK, BANK_WALL_HEIGHT, BANK_WALL_LEN),
		Vector3(BANK_WALL_A_CENTER_X, cy, BANK_Z_CENTER), bank_col)
	_mk_clad_wall(parent, "CreekBankWallB", Vector3(BANK_WALL_THICK, BANK_WALL_HEIGHT, BANK_WALL_LEN),
		Vector3(BANK_WALL_A_CENTER_X + BANK_WALL_THICK + BANK_GAP, cy, BANK_Z_CENTER), bank_col)
	# 朝向固定 0°：`_box()` 从 body 的 position/size 推世界 AABB，**不读旋转**，
	# 一旦给 body 加 yaw，测试读到的包围盒就会比真实碰撞小。要转就把 AABB 一起算。
	_mk_boulder(parent, "CreekBoulder", Vector3(-14.0, GROUND_TOP, 8.0), 0.0)
	_mk_data_area(parent, "CreekReedCover", COVER_SIZE, Vector3(-28.0, 1.5, 10.0), "cover_volumes",
		{"visibility_factor": COVER_FACTOR, "role": "cover"})
	# ART01 审计发现的真实缺陷：这处掩体**原来没有任何视觉**（实测 CreekReedCoverMesh = MISSING，
	# 玩家在溪边"被草丛掩护"却看不到草）。现在补上同一套资产。
	_mk_cover_bush(parent, "CreekReedCoverMesh", Vector3(-28.0, GROUND_TOP, 10.0), 212.0, 1.0)
	# ART03-⑥：补密芦苇 + 湿泥岸带（都是纯视觉 MeshInstance3D，零碰撞、不进导航组）
	_add_creek_dressing(parent)
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
	# ART07：0.45 → 0.62 —— 基线判读指出"背光面靠一盏灯兜底仍偏暗、明暗对比低"（根障斜视机位最明显）。
	# 只抬这盏**不投影**的补光，主光方向/能量/阴影方向一字未动（阴影结构不变，只把暗面抬起来）。
	fill.light_energy = 0.62
	fill.shadow_enabled = false
	parent.add_child(fill)
	fill.owner = parent


	# ART09：天空从纯程序化灰蓝换成 CC0 森林 HDRI（Poly Haven `mossy_forest` 2k HDR）。
	# 依据：展板背景是真实森林溪谷，程序化天空在画面上只剩一条灰带；HDRI 让背景读成
	# "树林 + 斑驳阳光"。仍然保持 `BG_SKY` + 非空 `Sky`（T011 的两条环境断言原样成立）。
	var sky := Sky.new()
	var hdri := load(SKY_HDRI_PATH)
	if hdri != null:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = hdri
		sky.sky_material = pano
		print("TOOL|Env|sky=panorama|%s" % SKY_HDRI_PATH)
	else:
		# 退路：没有 HDRI 就回到 ART07 的程序化天空（灰蓝地平线 + 0.75 能量），不静默变成黑屏。
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.70)
		sky_mat.ground_bottom_color = Color(0.52, 0.55, 0.58)
		sky_mat.energy_multiplier = 0.75
		sky.sky_material = sky_mat
		print("TOOL|Env|sky=procedural|hdri_missing")
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# 明暗结构：天光是这台机位"发灰、阴影不落"的主因——天空环境光（`AMBIENT_SOURCE_SKY`）
	# 把太阳阴影几乎洗平（vision 反复判"物体底部没有暗色接地压暗"）。
	# 实测：`env.ambient_light_energy` 对 SKY 源**无效**（0.72 与 1.0 渲染像素完全一致），
	# 正确的旋钮是天空材质的 `energy_multiplier`（它同时决定天光辐照与天空自身亮度）。
	# 0.75：太阳/天光比值拉开一档，天空整体略收暗，仍保持 BG_SKY 与灰蓝地平线。
	# 真实接触遮蔽：SSAO。vision 两轮判"草丛/石头底部没有 AO、像浮在贴纸上的插片"，
	# 贴地暗片只能补"轮廓外的一圈"，棚屋/墙角/石头与地面的**凹角**要靠屏幕空间 AO 才读得出。
	# 半径按"石头/草丛脚印 ~0.5 m"给（视距 20～50 m 仍能落在几个像素上），强度抬到 2.6。
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.6
	env.ssao_power = 2.0
	# 色调映射：Godot 默认 `TONE_MAPPER_LINEAR` 在这种"大面积中等亮度地面 + 一盏太阳"的场里
	# 会把明暗差压平（vision 反复判"发灰、平淡、低对比"）。ACES 保留高光、加深中暗部，
	# 前/中/背景靠**明暗**就能分层，不需要再加全屏 veil。曝光维持 1.0（不改整体亮度基准）。
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	print("TOOL|Env|ssao=%s|radius=%.2f|intensity=%.2f|tonemap=%d|exposure=%.2f" % [
		str(env.ssao_enabled), env.ssao_radius, env.ssao_intensity, env.tonemap_mode,
		env.tonemap_exposure])
	# **雾：最终状态 = 关闭**（指数雾被三轮实测否决；远景深度雾已实测可用但会带回"整屏偏灰"的判读，
	# 交负责人决定是否开启，见下）。
	# 单变量实测（overview 机位 pos(0,52,72)→look(0,0,2)，fov 45，1280×720；全图亮度 sd / 远带−近带均差）：
	#   指数 density 0.000 → sd 0.1319、far−near 0.1922
	#   指数 density 0.003 → sd 0.0893、far−near 0.1407（vision 判"整屏灰白雾幕"）
	#   指数 density 0.008 → sd 0.0513、far−near 0.0875
	# 结论：本机位到场地 40～90 m，**指数雾**在这里是全屏提亮式压对比，任何密度都只会抹平层次。
	# **远景深度雾（已实测的备选方案）**：`FOG_MODE_DEPTH` + begin=80 / end=170 / density=0.9 / sky_affect=0，
	# 近景（<80 m，含全部近景机位）零影响，只有远角起雾；vision 对它的判读是
	# "三层分明、远景明显更淡（空气透视 OK）、无漂浮"，但同时也答"整屏有灰白雾化感（偏灰）"。
	# 因为本轮验收明确要求"fog veil 必须消失"，**最终取关闭**；深度雾参数保留在下面几行，
	# 负责人若要 A5 的"远景更淡"一项，把 `env.fog_enabled` 改成 true 即可（其它设置不动）。
	# ART13 S6（2026-11-03，A5 空气透视）：按上述预留开启深度雾，并把雾光压暗——
	# 上轮判"整屏偏灰"的根因是雾光 energy 0.75 偏亮；0.45 + 更暗的冷灰色 (0.50,0.55,0.62)
	# 让远角只"退淡"不"提亮"。sky_affect=0 保持不变（只雾化远处几何，不洗天空/整屏）。
	# 若 vision 复判仍出现灰幕，回退 = 把 fog_enabled 改回 false（其余参数保留）。
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 80.0
	env.fog_depth_end = 170.0
	env.fog_depth_curve = 1.0
	env.fog_density = 0.9
	env.fog_light_color = Color(0.50, 0.55, 0.62)
	env.fog_light_energy = 0.45
	env.fog_sun_scatter = 0.0
	env.fog_aerial_perspective = 0.0
	# sky_affect = 0：**只雾化远处几何，不洗白天空/整屏**（0.25 时 vision 判"四周一圈淡化＝灰雾幕"）
	env.fog_sky_affect = 0.0
	print("TOOL|Env|fog=%s|mode=depth|begin=%.0f|end=%.0f|density=%.2f|sky_affect=%.2f|fill_energy=%.2f" % [
		"enabled" if env.fog_enabled else "disabled",
		env.fog_depth_begin, env.fog_depth_end, env.fog_density, env.fog_sky_affect,
		fill.light_energy])
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


## ART03-⑦：给草丛实例的**叶片**表面换成风动 shader。
## 只换名字里带 leaf 的表面：土墩面（MAT_Bush_Soil）保持原材质，否则整坨土也会跟着摆。
## 找不到 shader 就什么都不做（生成器仍能在缺文件时跑通）。
func _apply_grass_wind(inst: Node3D) -> void:
	var shader_res := load(GRASS_WIND_SHADER) as Shader
	if shader_res == null:
		return
	var mi := _find_first_mesh(inst)
	if mi == null or mi.mesh == null:
		return
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
	if applied == 0:
		print("TOOL|grass_wind|%s|NO_LEAF_SURFACE|surfaces=%d" % [
			inst.name, mi.mesh.get_surface_count()])


## ART03-⑫：给某个 StaticBody3D 的 `Mesh` 子节点换 shader 材质（找不到 shader 就保持原纯色）。
func _apply_material_override(body: StaticBody3D, shader_path: String, tag: String) -> void:
	var shader_res := load(shader_path) as Shader
	if shader_res == null:
		print("TOOL|material|%s|FALLBACK_PLAIN|shader_missing=%s" % [tag, shader_path])
		return
	var mi := body.get_node_or_null("Mesh") as MeshInstance3D
	if mi == null:
		return
	var smat := ShaderMaterial.new()
	smat.shader = shader_res
	mi.material_override = smat
	print("TOOL|material|%s|shader=%s" % [tag, shader_path])


## ART03-⑫：庭院碎屑 —— 碰撞仍是 0.6 × 0.3 × 0.6 的 BoxShape3D，视觉换成缩小的大石头。
## 复用已有的 `sm_boulder_001.glb`，不新增资产。
func _mk_rock_debris(parent: Node3D, nm: String, size: Vector3, pos: Vector3, color: Color,
		scale_mul: float) -> StaticBody3D:
	var sb := _mk_box(parent, nm, size, pos, Vector3.ZERO, color)
	var mi := sb.get_node_or_null("Mesh") as MeshInstance3D
	var ps: PackedScene = null
	if ResourceLoader.exists(BOULDER_ASSET):
		ps = load(BOULDER_ASSET) as PackedScene
	if ps == null:
		return sb
	if mi != null:
		mi.visible = false
	var rock: Node3D = ps.instantiate() as Node3D
	rock.name = "Rock"
	sb.add_child(rock)
	rock.owner = parent
	rock.scale = Vector3.ONE * scale_mul
	# 巨石原点在脚底；父节点在碰撞盒中心 → 下沉半个视觉高度
	rock.position = Vector3(0.0, -size.y * 0.5 + 0.01, 0.0)
	rock.rotation_degrees = Vector3(0.0, 37.0 + 61.0 * float(nm.length()), 0.0)
	print("TOOL|debris_rock|%s|asset=%s|scale=%.2f" % [nm, BOULDER_ASSET, scale_mul])
	return sb


## ART03-⑬：道具视觉替换 —— 保留 StaticBody3D 的碰撞与尺寸，只把 `Mesh` 换成 glb 实例。
## `shader_path` 非空时，会给实例里的网格挂上该 shader（土墩复用地面材质，草/土斑块自然衔接）。
func _mk_prop_visual(body: StaticBody3D, nm: String, glb: String, prop_scale: Vector3,
		pos: Vector3, shader_path: String) -> Node3D:
	var ps: PackedScene = null
	if ResourceLoader.exists(glb):
		ps = load(glb) as PackedScene
	if ps == null:
		print("TOOL|prop_visual|%s|FALLBACK_BOX|asset_missing=%s" % [nm, glb])
		return null
	var box_mesh := body.get_node_or_null("Mesh") as MeshInstance3D
	if box_mesh != null:
		box_mesh.visible = false
	var inst: Node3D = ps.instantiate() as Node3D
	inst.name = nm
	body.add_child(inst)
	inst.owner = body.owner
	inst.scale = prop_scale
	inst.position = pos
	if shader_path != "":
		var shader_res := load(shader_path) as Shader
		var mi := _find_first_mesh(inst)
		if shader_res != null and mi != null:
			var smat := ShaderMaterial.new()
			smat.shader = shader_res
			mi.material_override = smat
	print("TOOL|prop_visual|%s|asset=%s|scale=%s|pos=%s|shader=%s" % [
		nm, glb, prop_scale, pos, shader_path if shader_path != "" else "-"])
	return inst


## ART03-⑭：把一段树根屏障的视觉换成盘根模块平铺。
## 碰撞盒（0.50 高 × 1.00 深的 BoxShape3D）完全不动，所以"猫跳顶 / 鼠钻洞"的玩法契约不变。
func _mk_root_barrier_visual(body: StaticBody3D, nm: String) -> void:
	var ps: PackedScene = null
	if ResourceLoader.exists(ROOT_BARRIER_ASSET):
		ps = load(ROOT_BARRIER_ASSET) as PackedScene
	if ps == null:
		print("TOOL|root_barrier_visual|%s|FALLBACK_BOX|asset_missing=%s" % [nm, ROOT_BARRIER_ASSET])
		return
	var cs := body.get_node_or_null("Shape") as CollisionShape3D
	var box := cs.shape as BoxShape3D if cs != null else null
	var bsize: Vector3 = box.size if box != null else Vector3.ZERO
	var box_mesh := body.get_node_or_null("Mesh") as MeshInstance3D
	if box_mesh != null:
		box_mesh.visible = false
	# 高度等比缩放；沿长轴（X）平铺，间距 = 段长 / ceil(段长 / 模块长)
	var k: float = bsize.y / ROOT_BARRIER_MOD_H
	var mod_len: float = ROOT_BARRIER_MOD_LEN * k
	var n: int = maxi(1, int(ceil(bsize.x / maxf(0.01, mod_len * 0.92))))
	var spacing: float = bsize.x / float(n)
	var tiles := Node3D.new()
	tiles.name = "Roots"
	body.add_child(tiles)
	tiles.owner = body.owner
	for i in n:
		var inst: Node3D = ps.instantiate() as Node3D
		inst.name = "Root%d" % i
		tiles.add_child(inst)
		inst.owner = body.owner
		inst.scale = Vector3(k, k, k)
		inst.position = Vector3(-bsize.x * 0.5 + spacing * (float(i) + 0.5), -bsize.y * 0.5, 0.0)
		inst.rotation_degrees = Vector3(0.0, 180.0 if i % 2 == 1 else 0.0, 0.0)
	print("TOOL|root_barrier_visual|%s|asset=%s|size=(%.2f, %.2f, %.2f)|tiles=%d|spacing=%.3f|k=%.3f" % [
		nm, ROOT_BARRIER_ASSET, bsize.x, bsize.y, bsize.z, n, spacing, k])


## ART03-⑮：矮石墙 —— 用真比例矮墙模块**叠层**（而不是把 3 m 模块压扁）。
## 层数 = round(段高 / 模块高)（1.6 / 0.774 → 2 层），每层按 `层高/模块高` 等比缩放，
## 相邻层错开半个间距形成"通缝错开"，视觉上才像砌体。
## 碰撞盒仍是原来的 BoxShape3D（尺寸/位置一字未改）。
## `trim_along_end`：衬板在哪一端收进 `BACKING_TRIM`（0 = 两端都不收；+1/−1 = 收 +along/−along 端）。
## 转角处两端墙互相咬合，衬板必须**铺到端头**（否则转角能看穿到棚内）；只有敞开的门垛端才收进。
func _mk_low_wall(parent: Node3D, nm: String, size: Vector3, pos: Vector3, color: Color,
		trim_along_end: int = 0) -> StaticBody3D:
	var sb := _mk_box(parent, nm, size, pos, Vector3.ZERO, color)
	var ps: PackedScene = null
	if ResourceLoader.exists(WALL_LOW_ASSET):
		ps = load(WALL_LOW_ASSET) as PackedScene
	if ps == null:
		print("TOOL|low_wall|%s|FALLBACK_BOX|asset_missing=%s" % [nm, WALL_LOW_ASSET])
		return sb
	var box_mesh := sb.get_node_or_null("Mesh") as MeshInstance3D
	if box_mesh != null:
		box_mesh.visible = false
	var along_x: bool = size.x >= size.z
	var long_len: float = size.x if along_x else size.z
	var courses: int = maxi(1, int(round(size.y / WALL_LOW_H)))
	var course_h: float = size.y / float(courses)
	# 竖向：每皮按 层高/模块高 缩放（0.8 / 0.8 → 1.0，石块**不被压扁**）
	var k_y: float = course_h / WALL_LOW_H
	# 横向：先按真实长度决定块数，再用 k_x = 间距/模块长 精确贴合 → 不重叠、不漏缝
	var n: int = maxi(1, int(round(long_len / maxf(0.05, WALL_LOW_LEN * k_y))))
	var spacing: float = long_len / float(n)
	var k_x: float = spacing / WALL_LOW_LEN
	var tiles := Node3D.new()
	tiles.name = "Tiles"
	sb.add_child(tiles)
	tiles.owner = parent
	var total := 0
	for c in courses:
		# 模块原点是**脚底**（契约：原点=脚底），所以每皮的 y 取这一皮的底面，不能取中心
		var y: float = -size.y * 0.5 + course_h * float(c)
		for i in n:
			var inst: Node3D = ps.instantiate() as Node3D
			inst.name = "C%d_%d" % [c, i]
			tiles.add_child(inst)
			inst.owner = parent
			inst.scale = Vector3(k_x, k_y, k_y)
			var off: float = -long_len * 0.5 + spacing * (float(i) + 0.5)
			if along_x:
				inst.position = Vector3(off, y, 0.0)
			else:
				inst.position = Vector3(0.0, y, off)
				inst.rotation_degrees = Vector3(0.0, 90.0, 0.0)
			total += 1
	var backing := MeshInstance3D.new()
	backing.name = "Backing"
	var bm := BoxMesh.new()
	var trim_len: float = 0.0 if trim_along_end == 0 else BACKING_TRIM
	var run_len: float = maxf(0.30, long_len - trim_len)
	# 只在被收进的那一端让位：衬板中心随之下移 trim_len/2
	var run_off: float = -float(trim_along_end) * trim_len * 0.5
	bm.size = Vector3(run_len, size.y * 0.99, 0.06) if along_x \
		else Vector3(0.06, size.y * 0.99, run_len)
	backing.mesh = bm
	backing.position = Vector3(run_off, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, run_off)
	var bmat := StandardMaterial3D.new()
	# 衬板是"灰缝"的底色，不能太黑 —— 石块接缝处透出来的应该是砂浆色而不是黑洞
	bmat.albedo_color = Color(0.34, 0.33, 0.30)
	bmat.roughness = 0.95
	backing.material_override = bmat
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sb.add_child(backing)
	backing.owner = parent
	print("TOOL|low_wall|%s|asset=%s|size=(%.2f, %.2f, %.2f)|courses=%d|course_h=%.3f|n=%d|k=(%.3f, %.3f)|tiles=%d|backing_len=%.3f|backing_off=%.3f|trim=%d" % [
		nm, WALL_LOW_ASSET, size.x, size.y, size.z, courses, course_h, n, k_x, k_y, total,
		run_len, run_off, trim_along_end])
	return sb


## ART03-⑮-2：门框立柱 —— 把矮墙模块**开口的直立端**收边，同时给棚顶东侧补支撑。
## 纯视觉：无碰撞、不进 `nav_source_courtyard` 组（顶到棚顶下沿，略咬进 2 cm）。
func _mk_shelter_post(parent: Node3D, nm: String, base: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = nm
	parent.add_child(holder)
	holder.owner = parent
	holder.position = base
	var ps: PackedScene = null
	if ResourceLoader.exists(SHELTER_POST_ASSET):
		ps = load(SHELTER_POST_ASSET) as PackedScene
	if ps == null:
		print("TOOL|shelter_post|%s|FALLBACK_EMPTY|asset_missing=%s" % [nm, SHELTER_POST_ASSET])
		return holder
	var inst: Node3D = ps.instantiate() as Node3D
	inst.name = "Post"
	holder.add_child(inst)
	inst.owner = parent
	inst.scale = Vector3.ONE
	inst.position = Vector3.ZERO
	print("TOOL|shelter_post|%s|asset=%s|size=(%.2f, %.2f, %.2f)|base=%s|top=%.3f" % [
		nm, SHELTER_POST_ASSET, SHELTER_POST_W, SHELTER_POST_D, SHELTER_POST_H, base,
		base.y + SHELTER_POST_H])
	return holder


## ART03-⑮-3：转角料石 —— 两片矮墙在转角处各自的石排都会内缩，接缝会露出衬板竖带；
## 用一件**整高料石**（内含 4 皮不同长宽高的砌石，相邻层转 90°）把转角整段压住。
## **纯视觉**：无碰撞、不进导航组。
func _mk_corner_quoin(parent: Node3D, nm: String, cx: float, cz: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = nm
	parent.add_child(holder)
	holder.owner = parent
	holder.position = Vector3(cx, GROUND_TOP, cz)
	var ps: PackedScene = null
	if ResourceLoader.exists(QUOIN_ASSET):
		ps = load(QUOIN_ASSET) as PackedScene
	if ps == null:
		print("TOOL|quoin|%s|FALLBACK_EMPTY|asset_missing=%s" % [nm, QUOIN_ASSET])
		return holder
	var inst: Node3D = ps.instantiate() as Node3D
	inst.name = "Quoin"
	holder.add_child(inst)
	inst.owner = parent
	inst.position = Vector3.ZERO
	inst.rotation_degrees = Vector3.ZERO
	print("TOOL|quoin|%s|asset=%s|h=%.3f|foot=%.3f..%.3f|base=%s|top=%.3f" % [
		nm, QUOIN_ASSET, QUOIN_H, QUOIN_MIN_FOOT, QUOIN_MAX_FOOT,
		str(holder.position), GROUND_TOP + QUOIN_H])
	return holder


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
	_apply_grass_wind(inst)
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
# ART07：构图装饰（接地阴影 / 背景草簇 / 溪中石 / 庭院小石 / 泥舌"半岛"）
# 全部**零碰撞**、**不进** `nav_source_courtyard`、数据全是固定数组 → 玩法与导航零影响。
# ---------------------------------------------------------------------------

func _add_composition_dressing(parent: Node3D) -> void:
	# ① 接地阴影：给**已有**贴地物件补一圈暗色压边，让它们"坐"在地面上而不是浮在贴图上。
	for i in COVERS.size():
		var c: Dictionary = COVERS[i]
		_mk_ground_shadow(parent, "GroundShadowCover%d" % (i + 1),
			Vector3(float(c["pos"].x), 0.0, float(c["pos"].z)), Vector2(2.3, 2.4), 0.20, float(BUSH_YAWS[i]))
	_mk_ground_shadow(parent, "GroundShadowCreekCover", Vector3(-28.0, 0.0, 10.0),
		Vector2(2.3, 2.4), 0.20, 212.0)
	_mk_ground_shadow(parent, "GroundShadowBoulder", Vector3(-14.0, 0.0, 8.0),
		Vector2(1.6, 2.1), 0.26, 0.0)
	var stump_hd: float = ROOT_HOLE_SIZE.z * 0.5
	_mk_ground_shadow(parent, "GroundShadowStumpS",
		Vector3(HOLE_CENTER_X, 0.0, BARRIER_Z_MIN - stump_hd), Vector2(1.0, 0.95), 0.30, 0.0)
	_mk_ground_shadow(parent, "GroundShadowStumpN",
		Vector3(HOLE_CENTER_X, 0.0, BARRIER_Z_MAX + stump_hd), Vector2(1.0, 0.95), 0.30, 0.0)
	var debris_at := [Vector3(9.0, 0.0, 27.6), Vector3(8.4, 0.0, 26.6), Vector3(9.4, 0.0, 25.4)]
	for i in debris_at.size():
		_mk_ground_shadow(parent, "GroundShadowDebris%d" % (i + 1), debris_at[i],
			Vector2(0.5, 0.5), 0.24, 0.0)
	_mk_ground_shadow(parent, "GroundShadowMoundA", Vector3(-20.0, 0.0, -12.0), Vector2(2.3, 2.3), 0.18, 0.0)
	_mk_ground_shadow(parent, "GroundShadowMoundB", Vector3(14.0, 0.0, -8.0), Vector2(2.3, 2.3), 0.18, 0.0)

	# ART13 S4（A7 结构接地）：棚柱 / 棚内地坪 / 根障基座 / 围栏基脚 +9 块 → 阴影总数 39→48。
	# vision 对 courtyard_shelter 判"棚柱底下没有压暗、像插在贴图上"，对 roots_barrier_oblique 判
	# "根障与地面接触处生硬"，对 map_overview 判"围栏脚是悬空直线"。全部零碰撞、不进导航组，
	# 与既有接地暗片同一机制（unshaded 贴地薄片），只是长条结构改用线性渐变（见 `_mk_ground_band`）。
	# 棚柱×2：东侧两根立柱（x = SHELTER_X_MAX + PROUD − POST_W/2 = −6.54，z 贴南北短墙内侧）。
	# 脚印 0.16×0.36，传 (0.28, 0.50) 经 ×1.75 外扩 → 最终 0.49×0.88，读作柱脚一圈压暗。
	var post_x: float = SHELTER_X_MAX + SHELTER_POST_PROUD - SHELTER_POST_W * 0.5
	_mk_ground_shadow(parent, "GroundShadowShelterPostS",
		Vector3(post_x, 0.0, SHELTER_Z_MIN + FENCE_THICK * 0.5), Vector2(0.28, 0.50), 0.28, 0.0)
	_mk_ground_shadow(parent, "GroundShadowShelterPostN",
		Vector3(post_x, 0.0, SHELTER_Z_MAX - FENCE_THICK * 0.5), Vector2(0.28, 0.50), 0.28, 0.0)
	# 棚内地坪×1：棚内（三面矮墙 + 顶）环境光被遮，地面整片应比外面暗一档。
	# 室内 x∈[−9.4,−6.5] z∈[25.7,28.9]，中心 (−7.95, 27.3)，传 footprint/1.75 → 最终 2.9×3.2。
	_mk_ground_shadow(parent, "GroundShadowShelterFloor",
		Vector3(-7.95, 0.0, 27.3), Vector2(2.9 / 1.75, 3.2 / 1.75), 0.08, 0.0)
	# 根障基座×2：RootBarrierWest x∈[10, 26.38]、East x∈[26.62, 36]（中间是鼠洞缝，留空不压暗），
	# z∈[18.5, 19.5]。长条 → `_mk_ground_band`，尺寸即最终尺寸，宽 1.4（脚印 1.0 + 两侧渐隐）。
	_mk_ground_band(parent, "GroundShadowBarrierW",
		Vector3(18.19, 0.0, 19.0), Vector2(16.38, 1.4), 0.10, 0.0)
	_mk_ground_band(parent, "GroundShadowBarrierE",
		Vector3(31.31, 0.0, 19.0), Vector2(9.38, 1.4), 0.10, 0.0)
	# 围栏基脚×4：北/南沿 x 长 72.2，东/西沿 z 长 56.2，条宽 0.9 居中压在可玩边界线上。
	# alpha 故意压很低（0.08 → 最终 0.256）：只要"墙脚有一道暗线"，不能把 72 m 边界读成黑框。
	_mk_ground_band(parent, "GroundShadowFenceN",
		Vector3(0.0, 0.0, PLAY_MAX_Z), Vector2(72.2, 0.9), 0.08, 0.0)
	_mk_ground_band(parent, "GroundShadowFenceS",
		Vector3(0.0, 0.0, PLAY_MIN_Z), Vector2(72.2, 0.9), 0.08, 0.0)
	var mid_z: float = (PLAY_MIN_Z + PLAY_MAX_Z) * 0.5
	_mk_ground_band(parent, "GroundShadowFenceW",
		Vector3(PLAY_MIN_X, 0.0, mid_z), Vector2(56.2, 0.9), 0.08, 90.0)
	_mk_ground_band(parent, "GroundShadowFenceE",
		Vector3(PLAY_MAX_X, 0.0, mid_z), Vector2(56.2, 0.9), 0.08, 90.0)
	# ART13 S5：缝口两道岸墙的基脚压暗×2（长条 → `_mk_ground_band`）。岸墙高 1.0 m、
	# 立在溪区，是"水岸硬切"读感的来源之一；Shadow 名按缝口净空断言的设计豁免（压暗是
	# 贴地贴花，不会像石头/草丛那样在视觉上挤窄 0.24 m 鼠车道）。
	_mk_ground_band(parent, "GroundShadowBankWallA",
		Vector3(BANK_WALL_A_CENTER_X, 0.0, BANK_Z_CENTER), Vector2(0.9, 8.6), 0.12, 0.0)
	_mk_ground_band(parent, "GroundShadowBankWallB",
		Vector3(BANK_WALL_A_CENTER_X + BANK_WALL_THICK + BANK_GAP, 0.0, BANK_Z_CENTER),
		Vector2(0.9, 8.6), 0.12, 0.0)

	# ② 背景层草簇：贴围墙脚 / 场地边角，只做中远景剪影
	#    主列表 10 株（`SceneryBush00..09`）+ 加密列表 14 株（`SceneryBushFill0..13`，ART12 增 8），同资产同规则。
	for i in SCENERY_BUSHES.size():
		var b: Dictionary = SCENERY_BUSHES[i]
		var nm := "SceneryBush%02d" % i
		var at := Vector3(float(b["x"]), GROUND_TOP, float(b["z"]))
		_mk_decor_bush(parent, nm, at, float(b["yaw"]), float(b["s"]))
		_mk_ground_shadow(parent, "%sShadow" % nm, at,
			Vector2(2.4, 2.5) * float(b["s"]), 0.16, float(b["yaw"]))
	for i in SCENERY_BUSHES_FILL.size():
		var bf: Dictionary = SCENERY_BUSHES_FILL[i]
		var fnm := "SceneryBushFill%d" % i
		var fat := Vector3(float(bf["x"]), GROUND_TOP, float(bf["z"]))
		_mk_decor_bush(parent, fnm, fat, float(bf["yaw"]), float(bf["s"]))
		_mk_ground_shadow(parent, "%sShadow" % fnm, fat,
			Vector2(2.4, 2.5) * float(bf["s"]), 0.16, float(bf["yaw"]))

	# ③ 溪中石：打散"22×9 直带水面"的矩形感（复用 CC0 巨石资产，纯视觉）
	#    ART13 S5：每块补脚下暗片（贴地 0.107 沉在水面之下，读作"泡在水里"），与庭院石同规格。
	for i in CREEK_ROCKS.size():
		var r: Dictionary = CREEK_ROCKS[i]
		var rnm := "CreekRock%02d" % i
		var rat := Vector3(float(r["x"]), GROUND_TOP, float(r["z"]))
		_mk_rock_decor(parent, rnm, rat, float(r["yaw"]), float(r["s"]))
		_mk_ground_shadow(parent, "%sShadow" % rnm, rat,
			Vector2(1.5, 2.1) * float(r["s"]) * 0.9, 0.22, float(r["yaw"]))

	# ④ 庭院前景小石（给出生点附近一个近景参考物）
	for i in COURTYARD_ROCKS.size():
		var q: Dictionary = COURTYARD_ROCKS[i]
		var qnm := "CourtyardRock%02d" % i
		var qat := Vector3(float(q["x"]), GROUND_TOP, float(q["z"]))
		_mk_rock_decor(parent, qnm, qat, float(q["yaw"]), float(q["s"]))
		_mk_ground_shadow(parent, "%sShadow" % qnm, qat,
			Vector2(1.5, 2.1) * float(q["s"]) * 0.9, 0.22, float(q["yaw"]))

	# ⑤ 泥舌"半岛"：探进水面的大块泥岸，上面长草 → 水边不再是直线
	# **ART07 收尾轮 #2**：0.152 → **0.1405**。vision 对 `creek_wide` 判"泥板像悬在水上的方块、
	# 边缘直上直下"——原高度让泥板侧面露出 2.2 cm，斜视时读成漂浮的厚板。压到水面(0.13)之上 1.05 cm：
	# 仍保证泥板高于水面不被水盖住（`_verify` 的 0.13 < top < 0.155 断言照旧），但侧面薄到读作"岸"。
	var rim_top: float = 0.1405
	var rim_h: float = rim_top - GROUND_TOP
	for i in MUD_PENINSULAS.size():
		var p: Dictionary = MUD_PENINSULAS[i]
		var pnm := "CreekPeninsula%02d" % i
		var mi := _mk_opaque_plate(parent, pnm,
			Vector3(float(p["sx"]), rim_h, float(p["sz"])),
			Vector3(float(p["x"]), GROUND_TOP + rim_h * 0.5, float(p["z"])),
			Color(0.170, 0.156, 0.132))
		mi.rotation_degrees = Vector3(0.0, float(p["yaw"]), 0.0)
		_mk_decor_bush(parent, "%sGrass" % pnm,
			Vector3(float(p["x"]), rim_top - 0.004, float(p["z"])),
			float(p["yaw"]) * 7.0 + 33.0, float(p["grass_s"]))

	# 计数从**实际节点**数出来（不靠手写的累加，避免"加了一处忘了记"）
	var shadow_nodes := 0
	for ch in parent.get_children():
		if String(ch.name).find("Shadow") >= 0:      # GroundShadow* / SceneryBush*Shadow / CourtyardRock*Shadow
			shadow_nodes += 1
	print("TOOL|Composition|shadows=%d|scenery_bushes=%d|creek_rocks=%d|courtyard_rocks=%d|peninsulas=%d|shadow_lift=%.3f" % [
		shadow_nodes, SCENERY_BUSHES.size(), CREEK_ROCKS.size(), COURTYARD_ROCKS.size(),
		MUD_PENINSULAS.size(), GROUND_SHADOW_LIFT])


## 不透明贴地泥板。**为什么不用 `_mk_surface_marker`**：那家伙给所有贴地色块都开
## `TRANSPARENCY_ALPHA`，透明物按深度排序绘制 → 水面（alpha 0.62）在斜视/俯视时可能被排到
## 泥板前面，把"不规则岸线"整个盖掉。半岛必须不透明：不透明先写深度，水面只能在它**后面**混合。
func _mk_opaque_plate(parent: Node3D, nm: String, size: Vector3, pos: Vector3,
		color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.position = pos
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mi.material_override = mat
	parent.add_child(mi)
	mi.owner = parent
	return mi


## 接地阴影：贴地薄片（`PlaneMesh` 水平面）+ 无光照半透明暗色 → 只压暗地面一圈，不投影、不碰撞。
## 为什么不用真阴影：草丛/石头已经在投真实阴影，但环境光下的接触区仍读不出"压住地面"，
## 而且远景（>20 m）阴影贴图分辨率不够；贴地压暗是分辨率无关的。
## **ART07 收尾轮 #2 实测修正**：vision 两轮判"草丛/石头像浮在地面上的贴纸、底部没有 AO"。
## 原因不是 alpha 太小，而是 `GROUND_SHADOW_SHRINK=0.85` 把暗片收在**脚印之内**——
## 从俯瞰/中高角机位看，草叶冠层把脚下一整块暗片盖住了，露出来的不到几十厘米边。
## 现在改成：尺寸 = 脚印 × `GROUND_SHADOW_SPREAD`（**外扩**到冠层轮廓之外一圈），
## 并用**径向渐变 alpha**（中心实、边缘渐隐）代替硬边方片 → 读成"接地压暗"，不是"画上去的圆片"。
func _mk_ground_shadow(parent: Node3D, nm: String, at: Vector3, size: Vector2, alpha: float,
		yaw_deg: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var pm := PlaneMesh.new()
	pm.size = size * GROUND_SHADOW_SPREAD
	# 分段给它几格，避免超大暗片在极斜视角下的顶点插值和地面不够贴合（不动几何，只使命中率更稳）
	pm.subdivide_width = 2
	pm.subdivide_depth = 2
	mi.mesh = pm
	mi.position = Vector3(at.x, GROUND_TOP + GROUND_SHADOW_LIFT, at.z)
	mi.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _shadow_alpha_texture()
	mat.albedo_color = Color(GROUND_SHADOW_COLOR.r, GROUND_SHADOW_COLOR.g, GROUND_SHADOW_COLOR.b,
		minf(0.85, alpha * GROUND_SHADOW_ALPHA_K))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.owner = parent
	return mi


## 径向渐变 alpha 贴图（**程序化生成**，不是新资产文件：64×64、确定性、随场景序列化）。
## 中心不透明 → 边缘全透明，让每块暗片都像"被物体压住的地面"，而不是一块牌子。
## 缓存成成员变量：25 块暗片共用同一张纹理，避免 .tscn 里塞 25 份一样的子资源。
var _shadow_tex: GradientTexture2D = null


func _shadow_alpha_texture() -> GradientTexture2D:
	if _shadow_tex != null:
		return _shadow_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.62),      # 中段保持实一些：外扩后仍要压得住
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.0)
	_shadow_tex = tex
	return _shadow_tex


## ART13 S4：长条结构的接地压暗纹理——沿短轴的**对称线性渐变**（横向白、中线实）。
## 为什么不共用径向贴图：72 m 长的围栏脚用径向渐变会"中段一坨实、两端全虚"，
## 读成墙中间的黑斑；线性渐变沿长度均匀、只在横向渐隐，才是"墙脚接触 AO"。
var _shadow_band_tex: GradientTexture2D = null


func _shadow_band_texture() -> GradientTexture2D:
	if _shadow_band_tex != null:
		return _shadow_band_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 0.62),      # 中线（压在结构脚下）最实，往两侧渐隐
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 16
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	_shadow_band_tex = tex
	return _shadow_band_tex


## ART13 S4：长条接地压暗（围栏脚 / 根障基座）。与 `_mk_ground_shadow` 同机制
## （unshaded 贴地薄片、无碰撞、不投影、名字带 "Shadow" 进计数断言），差别两处：
##   1. 纹理用线性渐变（见 `_shadow_band_texture`）——沿长度均匀，不是径向团块；
##   2. **size 即最终尺寸**，不做 ×1.75 外扩——外扩是为"冠层盖住脚印"的草丛设计的，
##      72 m 围栏再外扩会戳出场地角落。
func _mk_ground_band(parent: Node3D, nm: String, at: Vector3, size: Vector2, alpha: float,
		yaw_deg: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 8
	pm.subdivide_depth = 2
	mi.mesh = pm
	mi.position = Vector3(at.x, GROUND_TOP + GROUND_SHADOW_LIFT, at.z)
	mi.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _shadow_band_texture()
	mat.albedo_color = Color(GROUND_SHADOW_COLOR.r, GROUND_SHADOW_COLOR.g, GROUND_SHADOW_COLOR.b,
		minf(0.85, alpha * GROUND_SHADOW_ALPHA_K))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.owner = parent
	return mi


## ART13 S5：水线湿泥带。与 `_mk_ground_band` 同机制（线性渐变、unshaded、半透明、
## 零碰撞、不投影），差别三处：
##   1. 颜色是湿泥暗棕，不是阴影色——它表达"材质变湿"，不是"被遮挡"；
##   2. alpha 即最终值（不乘 `GROUND_SHADOW_ALPHA_K` 倍率）；
##   3. 名字不含 "Shadow" → 不进阴影计数，进 T011 want_decor 点名。
## 贴地 y = GROUND_TOP + GROUND_SHADOW_LIFT = 0.107：高于地面、低于水面(0.13)——
## 伸进水里的半幅透过水面读作湿泥，上岸的半幅是水渍。
func _mk_wet_band(parent: Node3D, nm: String, at: Vector3, size: Vector2, alpha: float,
		yaw_deg: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 8
	pm.subdivide_depth = 2
	mi.mesh = pm
	mi.position = Vector3(at.x, GROUND_TOP + GROUND_SHADOW_LIFT, at.z)
	mi.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _shadow_band_texture()
	mat.albedo_color = Color(0.155, 0.128, 0.098, alpha)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.owner = parent
	return mi


## 装饰草丛（背景层 / 泥舌上的草）：与掩体草丛同一资产，但**不是掩体**（无 Area3D、无碰撞）。
func _mk_decor_bush(parent: Node3D, nm: String, ground_pos: Vector3, yaw_deg: float,
		scale_mul: float) -> Node3D:
	var ps: PackedScene = null
	if ResourceLoader.exists(BUSH_ASSET):
		ps = load(BUSH_ASSET) as PackedScene
	if ps == null:
		print("TOOL|decor_bush|%s|ASSET_MISSING|%s" % [nm, BUSH_ASSET])
		return null
	var inst: Node3D = ps.instantiate() as Node3D
	inst.name = nm
	parent.add_child(inst)
	inst.owner = parent          # 不设 owner → pack() 会丢掉这个节点
	inst.position = ground_pos
	inst.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	inst.scale = Vector3.ONE * scale_mul
	_apply_grass_wind(inst)
	print("TOOL|decor_bush|%s|asset=%s|pos=(%.2f, %.2f, %.2f)|yaw=%.1f|scale=%.2f" % [
		nm, BUSH_ASSET, ground_pos.x, ground_pos.y, ground_pos.z, yaw_deg, scale_mul])
	return inst


## 装饰石头（溪中 / 庭院前景）：复用 `sm_boulder_001`，节点只有视觉，**没有碰撞体**。
func _mk_rock_decor(parent: Node3D, nm: String, ground_pos: Vector3, yaw_deg: float,
		scale_mul: float) -> Node3D:
	var ps: PackedScene = null
	if ResourceLoader.exists(BOULDER_ASSET):
		ps = load(BOULDER_ASSET) as PackedScene
	if ps == null:
		print("TOOL|rock_decor|%s|ASSET_MISSING|%s" % [nm, BOULDER_ASSET])
		return null
	var inst: Node3D = ps.instantiate() as Node3D
	inst.name = nm
	parent.add_child(inst)
	inst.owner = parent          # 不设 owner → pack() 会丢掉这个节点
	inst.position = ground_pos
	inst.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	inst.scale = Vector3.ONE * scale_mul
	print("TOOL|rock_decor|%s|asset=%s|pos=(%.2f, %.2f, %.2f)|yaw=%.1f|scale=%.2f|h=%.3f" % [
		nm, BOULDER_ASSET, ground_pos.x, ground_pos.y, ground_pos.z, yaw_deg, scale_mul,
		BOULDER_SIZE.y * scale_mul])
	return inst


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
		if not _check("%s_tiles_exist" % sid, st != null):
			continue
		var first_low := st.get_child(0) as Node3D
		_check("%s_tiles_is_low_asset" % sid,
			first_low != null and first_low.scene_file_path == WALL_LOW_ASSET)
		_check("%s_tiles_no_collision" % sid, _count_collision_shapes(st) == 0)
		# 矮墙用真比例模块叠层（而不是把 3 m 模块压扁）：层数 = round(段高/模块高)
		var courses_seen := {}
		for ch in st.get_children():
			courses_seen[str((ch as Node).name).split("_")[0]] = true
		var courses: int = courses_seen.size()
		_check("%s_tiles_courses_cover_height" % sid,
			courses == maxi(1, int(round(SHELTER_WALL_H / WALL_LOW_H))))
		# 竖向：每皮缩放到 层高/模块高（1.6 m / 2 皮 → 0.8 / 0.8 = 1.0，石块不被压扁）
		var k_y_expected: float = (SHELTER_WALL_H / float(maxi(1, courses))) / WALL_LOW_H
		_check("%s_tiles_course_height_ok" % sid,
			first_low != null and absf(first_low.scale.y - k_y_expected) < 1e-4)
		# 厚度跟着竖向同比例（石块不会变成薄片/厚块）
		_check("%s_tiles_thickness_kept" % sid,
			first_low != null and absf(first_low.scale.z - k_y_expected) < 1e-4)
		# 横向：k_x 必须让模块宽度精确等于间距 → 既不重叠也不漏缝
		var per_course := 0
		for ch in st.get_children():
			if str((ch as Node).name).begins_with("C0_"):
				per_course += 1
		var wall_box: Vector3 = _box(scene, s).get("size", Vector3.ZERO)
		var long_len_low: float = maxf(wall_box.x, wall_box.z)
		var spacing_low: float = long_len_low / float(maxi(1, per_course))
		_check("%s_tiles_width_matches_spacing" % sid,
			first_low != null and absf(first_low.scale.x * WALL_LOW_LEN - spacing_low) < 1e-4)
		# 任何一块都不能探出这段墙的两端（v1 的"悬空石头"就是这么来的）
		var protrude := 0.0
		var half_mod: float = first_low.scale.x * WALL_LOW_LEN * 0.5 if first_low != null else 0.0
		for ch in st.get_children():
			var cn := ch as Node3D
			var along: float = cn.position.x if wall_box.x >= wall_box.z else cn.position.z
			protrude = maxf(protrude, absf(along) + half_mod - long_len_low * 0.5)
		_check("%s_tiles_inside_run" % sid, protrude <= 1e-4)
		# 竖向：最下一块踩地、最上一块顶到墙顶（模块原点是脚底，写成"中心"就会上下各错半皮）
		var ymin_low := INF
		var ymax_low := -INF
		for ch in st.get_children():
			var cy := ch as Node3D
			ymin_low = minf(ymin_low, cy.position.y)
			ymax_low = maxf(ymax_low, cy.position.y + cy.scale.y * WALL_LOW_H)
		_check("%s_tiles_cover_height_exactly" % sid,
			absf(ymin_low + wall_box.y * 0.5) < 1e-4 and absf(ymax_low - wall_box.y * 0.5) < 1e-4)
		var low_backing := scene.get_node_or_null("%s/Backing" % s) as MeshInstance3D
		_check("%s_tiles_backing_exists" % sid, low_backing != null)
		# 衬板只在**门垛端**收进 BACKING_TRIM，转角端必须铺满（否则转角能看穿到棚内）
		var bk_mesh := low_backing.mesh as BoxMesh if low_backing != null else null
		var bk_run: float = maxf(bk_mesh.size.x, bk_mesh.size.z) if bk_mesh != null else 0.0
		var bk_off: float = (absf(low_backing.position.x) + absf(low_backing.position.z)) \
			if low_backing != null else 0.0
		var trimmed: bool = sid == "shelterwallnorth" or sid == "shelterwallsouth"
		var want_run: float = long_len_low - (BACKING_TRIM if trimmed else 0.0)
		var want_off: float = (BACKING_TRIM * 0.5) if trimmed else 0.0
		_check("%s_tiles_backing_inset" % sid,
			bk_mesh != null and absf(bk_run - want_run) < 1e-3)
		_check("%s_tiles_backing_shift" % sid, absf(bk_off - want_off) < 1e-3)

	# ART03-⑮-2：门洞两侧的门框立柱（收边 + 棚顶支撑）
	for p in ["ShelterPostSouth", "ShelterPostNorth"]:
		var pid: String = str(p).to_lower()
		var pn := scene.get_node_or_null(p) as Node3D
		if not _check("%s_exists" % pid, pn != null):
			continue
		_check("%s_single_post" % pid, pn.get_child_count() == 1)
		_check("%s_no_collision" % pid, _count_collision_shapes(pn) == 0)
		_check("%s_not_nav_source" % pid, not pn.is_in_group("nav_source_courtyard"))
		var p0 := pn.get_child(0) as Node3D
		_check("%s_is_asset" % pid,
			p0 != null and p0.scene_file_path == SHELTER_POST_ASSET)
		# 踩在地面、贴着门垛外沿（沿 +X 不越过 0.1 m，避免挡门洞）
		_check("%s_at_jamb_x" % pid,
			absf(pn.position.x - (SHELTER_X_MAX + SHELTER_POST_PROUD - SHELTER_POST_W * 0.5)) < 1e-3)
		# 柱顶要顶到棚顶下沿（1.70）并且不穿出棚顶（≤ 1.72）
		var p_top: float = pn.position.y + SHELTER_POST_H
		_check("%s_reaches_roof" % pid, p_top >= 1.70 - 1e-3 and p_top <= 1.72 + 1e-3)
		# 立柱面宽要盖住"墙厚 + 两侧石块外凸"（0.20 + 2×(0.30−0.20)/2 = 0.30）
		_check("%s_covers_stone_protrusion" % pid,
			SHELTER_POST_D >= FENCE_THICK + WALL_LOW_THICK - FENCE_THICK + 1e-3)
		var p_zin: float = minf(absf(pn.position.z - (SHELTER_Z_MIN + FENCE_THICK * 0.5)),
			absf(pn.position.z - (SHELTER_Z_MAX - FENCE_THICK * 0.5)))
		_check("%s_on_wall_axis" % pid, p_zin < 1e-3)

	# ART03-⑮-3：两个外转角的料石（quoin）
	for q in [{"n": "ShelterQuoinSW", "z": SHELTER_Z_MIN + FENCE_THICK * 0.5},
			{"n": "ShelterQuoinNW", "z": SHELTER_Z_MAX - FENCE_THICK * 0.5}]:
		var qid: String = str(q["n"]).to_lower()
		var qn := scene.get_node_or_null(q["n"]) as Node3D
		if not _check("%s_exists" % qid, qn != null):
			continue
		# 一件 = 4 皮（不同长宽高、相邻层转 90°），总高 = 墙高
		_check("%s_single_piece" % qid, qn.get_child_count() == 1)
		_check("%s_no_collision" % qid, _count_collision_shapes(qn) == 0)
		_check("%s_not_nav_source" % qid, not qn.is_in_group("nav_source_courtyard"))
		var q0 := qn.get_child(0) as Node3D
		_check("%s_is_asset" % qid, q0 != null and q0.scene_file_path == QUOIN_ASSET)
		_check("%s_on_corner_x" % qid,
			absf(qn.position.x - (SHELTER_X_MIN + FENCE_THICK * 0.5)) < 1e-3)
		_check("%s_on_corner_z" % qid, absf(qn.position.z - float(q["z"])) < 1e-3)
		_check("%s_grounded" % qid, absf(qn.position.y - GROUND_TOP) < 1e-3)
		_check("%s_spans_wall_height" % qid, absf(QUOIN_H - SHELTER_WALL_H) < 1e-3)
		var q_top: float = qn.position.y + QUOIN_H
		_check("%s_top_at_wall_top" % qid,
			absf(q_top - (GROUND_TOP + SHELTER_WALL_H)) < 1e-3)
		# 料石要盖住整片墙厚（含两侧石块外凸），但不许变成一根粗柱子
		# 外凸相对石块外凸面（WALL_LOW_THICK/2）不超过 6 cm，否则就像柱子了
		_check("%s_protrusion_within_6cm" % qid,
			QUOIN_MAX_FOOT * 0.5 - WALL_LOW_THICK * 0.5 <= 0.06)

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
					and bsz.y >= 0.78 and bsz.y <= 1.00)   # ART03-⑩：叶片改 5 段后高 0.797（仍远高于猫 0.48）
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
	# ART07：构图装饰（接地阴影 / 背景草簇 / 溪中石 / 庭院小石 / 泥舌半岛）。
	# 这些节点的唯一契约是"只看得见、碰不到"：零碰撞、不进导航组、不改任何静态碰撞体。
	var expected_bodies := [
		"Ground", "FenceNorth", "FenceSouth", "FenceWest", "FenceEast",
		"ShelterWallWest", "ShelterWallNorth", "ShelterWallSouth", "ShelterRoof",
		"CourtyardDebris1", "CourtyardDebris2", "CourtyardDebris3",
		"GrassMoundA", "GrassMoundB",
		"RootBarrierWest", "RootBarrierEast", "RootBarrierLintel",
		"CreekBankWallA", "CreekBankWallB", "CreekBoulder",
	]
	var bodies_seen: Array = []
	for ch in scene.get_children():
		if ch is StaticBody3D:
			bodies_seen.append(String(ch.name))
	bodies_seen.sort()
	var want_bodies: Array = expected_bodies.duplicate()
	want_bodies.sort()
	_check("static_body_set_unchanged", bodies_seen == want_bodies)
	print("VERIFY|StaticBodies|count=%d|names=%s" % [bodies_seen.size(), str(bodies_seen)])
	# 场景尚未入树 → `get_tree().get_nodes_in_group()` 拿不到，按节点自己的组标记判定
	var nav_ok := true
	for ch in scene.get_children():
		if ch.is_in_group("nav_source_courtyard") and not (ch is StaticBody3D):
			nav_ok = false
			print("VERIFY|nav_source_unexpected|%s" % ch.name)
	_check("nav_source_only_static_bodies", nav_ok)

	var decor_shadows := 0
	for ch in scene.get_children():
		var cn := String(ch.name)
		if cn.find("Shadow") < 0:
			continue
		decor_shadows += 1
		_check("shadow_%d_no_collision" % decor_shadows, _count_collision_shapes(ch) == 0)
		_check("shadow_%d_not_nav_source" % decor_shadows, not ch.is_in_group("nav_source_courtyard"))
		var cy: float = (ch as Node3D).position.y
		_check("shadow_%d_hugging_ground" % decor_shadows,
			cy >= GROUND_TOP and cy <= GROUND_TOP + 0.02)
	# 25 → 31（ART07 #2：加密 6 株背景草簇各带一块接地暗片）→ 39（ART12：再加密 8 株）
	# → 48（ART13 S4：棚柱×2 + 棚内地坪×1 + 根障基座×2 + 围栏基脚×4）
	# → 56（ART13 S5：缝口岸墙基脚×2 + 溪中石脚下暗片×6）。
	# 12（掩体/溪岸草/巨石/两树桩/三碎屑/两土墩）+ 24 株草 + 3 庭院石 + 9 结构件 + 8 溪区件
	_check("shadow_count_is_56", decor_shadows == 56)
	print("VERIFY|GroundShadows|count=%d|lift=%.3f" % [decor_shadows, GROUND_SHADOW_LIFT])

	var scenery := 0
	var scenery_specs: Array = []
	for i in SCENERY_BUSHES.size():
		scenery_specs.append({"nm": "SceneryBush%02d" % i, "spec": SCENERY_BUSHES[i]})
	for i in SCENERY_BUSHES_FILL.size():
		scenery_specs.append({"nm": "SceneryBushFill%d" % i, "spec": SCENERY_BUSHES_FILL[i]})
	for item in scenery_specs:
		var nm2: String = item["nm"]
		var n := scene.get_node_or_null(nm2) as Node3D
		if not _check("scenery_bush_%s_exists" % nm2, n != null):
			continue
		scenery += 1
		_check("scenery_bush_%s_is_asset" % nm2, n.scene_file_path == BUSH_ASSET)
		_check("scenery_bush_%s_no_collision" % nm2, _count_collision_shapes(n) == 0)
		_check("scenery_bush_%s_not_nav_source" % nm2, not n.is_in_group("nav_source_courtyard"))
		_check("scenery_bush_%s_on_ground" % nm2, absf(n.position.y - GROUND_TOP) < 1e-4)
		_check("scenery_bush_%s_clear_of_covers" % nm2, _decor_clear_of_covers(n.position, 2.0))
		_check("scenery_bush_%s_outside_danger" % nm2, not _inside_danger(n.position))
	_check("scenery_bush_count_total",
		scenery == SCENERY_BUSHES.size() + SCENERY_BUSHES_FILL.size())

	var rocks := 0
	for i in CREEK_ROCKS.size():
		var nm := "CreekRock%02d" % i
		var n := scene.get_node_or_null(nm) as Node3D
		if not _check("creek_rock_%s_exists" % nm, n != null):
			continue
		rocks += 1
		_check("creek_rock_%s_is_asset" % nm, n.scene_file_path == BOULDER_ASSET)
		_check("creek_rock_%s_no_collision" % nm, _count_collision_shapes(n) == 0)
		_check("creek_rock_%s_not_nav_source" % nm, not n.is_in_group("nav_source_courtyard"))
		# 必须在**水面矩形内**（否则就变成"岸上的石头"，构图意义消失）
		_check("creek_rock_%s_inside_water" % nm, absf(n.position.x - WATER_CENTER.x) <= WATER_SIZE.x * 0.5
			and absf(n.position.z - WATER_CENTER.z) <= WATER_SIZE.z * 0.5)
		# 不得挡住鼠的溪缝车道（缝中心 x=−31.73，车道宽 0.24）
		_check("creek_rock_%s_clear_of_gap_lane" % nm, absf(n.position.x - BANK_GAP_CENTER_X) >= 1.2)
	for i in COURTYARD_ROCKS.size():
		var nm := "CourtyardRock%02d" % i
		var n := scene.get_node_or_null(nm) as Node3D
		if not _check("courtyard_rock_%s_exists" % nm, n != null):
			continue
		rocks += 1
		_check("courtyard_rock_%s_is_asset" % nm, n.scene_file_path == BOULDER_ASSET)
		_check("courtyard_rock_%s_no_collision" % nm, _count_collision_shapes(n) == 0)
		_check("courtyard_rock_%s_not_nav_source" % nm, not n.is_in_group("nav_source_courtyard"))
		_check("courtyard_rock_%s_on_ground" % nm, absf(n.position.y - GROUND_TOP) < 1e-4)
	_check("decor_rock_count", rocks == CREEK_ROCKS.size() + COURTYARD_ROCKS.size())

	# ART07 视觉失败项锁定：**所有**新增装饰都不得落进溪缝车道轴附近（缝轴 x = BANK_GAP_CENTER_X，车道宽 0.24）。
	# 判据读**实际节点位置**而不是数组常量，所以"改了数组没重看机位"也能拦住。
	# 阈值：z 落在岸墙跨度内（±(BANK_WALL_LEN/2 + 2.0)）时，x 必须离缝轴 ≥ 1.6 m
	# （岸墙外表面离缝轴只有 0.42 m，1.6 m 才留出"缝口两侧是空地"的读图空间）。
	var lane_bad: Array = []
	for ch in scene.get_children():
		var cn := String(ch.name)
		if cn.find("Shadow") >= 0 or not (ch is Node3D):
			continue
		var is_decor: bool = (cn.begins_with("CreekRock") or cn.begins_with("SceneryBush")
			or cn.begins_with("CourtyardRock") or cn.begins_with("CreekPeninsula")
			or cn.begins_with("CreekWetBand"))
		if not is_decor:
			continue
		var p: Vector3 = (ch as Node3D).position
		if absf(p.z - BANK_Z_CENTER) <= BANK_WALL_LEN * 0.5 + 2.0 \
				and absf(p.x - BANK_GAP_CENTER_X) < 1.6:
			lane_bad.append("%s@(%.2f, %.2f)" % [cn, p.x, p.z])
	_check("decor_clear_of_creek_gap_mouth", lane_bad.is_empty())
	if not lane_bad.is_empty():
		print("VERIFY|decor_in_creek_gap_mouth|%s" % str(lane_bad))
	print("VERIFY|DecorRocks|count=%d|creek=%d|courtyard=%d" % [
		rocks, CREEK_ROCKS.size(), COURTYARD_ROCKS.size()])

	var peninsulas := 0
	for i in MUD_PENINSULAS.size():
		var nm := "CreekPeninsula%02d" % i
		var n := scene.get_node_or_null(nm) as MeshInstance3D
		if not _check("peninsula_%s_exists" % nm, n != null):
			continue
		peninsulas += 1
		var bm := n.mesh as BoxMesh
		_check("peninsula_%s_is_mesh_only" % nm, bm != null and n.get_node_or_null("Shape") == null)
		_check("peninsula_%s_no_collision" % nm, _count_collision_shapes(n) == 0)
		var top: float = n.position.y + (bm.size.y * 0.5 if bm != null else 0.0)
		# 泥舌顶面必须**略高于水面**（0.13）但低于锯齿泥舌的上限（0.155）
		_check("peninsula_%s_top_above_water" % nm, top > 0.13 and top < 0.155)
		_check("peninsula_%s_inside_water_span" % nm,
			absf(n.position.x - WATER_CENTER.x) <= WATER_SIZE.x * 0.5 + 1.0
			and absf(n.position.z - WATER_CENTER.z) <= WATER_SIZE.z * 0.5 + 1.0)
		var g := scene.get_node_or_null("%sGrass" % nm) as Node3D
		if _check("peninsula_%s_grass_exists" % nm, g != null):
			_check("peninsula_%s_grass_no_collision" % nm, _count_collision_shapes(g) == 0)
			_check("peninsula_%s_grass_sits_on_plinth" % nm, absf(g.position.y - top) < 0.01)
	_check("peninsula_count", peninsulas == MUD_PENINSULAS.size())
	print("VERIFY|Peninsulas|count=%d" % peninsulas)

	# ART13 S5：水线湿泥带契约——4 段全在、零碰撞、不进导航组、贴地 0.107、都在缝口保护区以东
	var wet_bands := ["CreekWetBandN1", "CreekWetBandN2", "CreekWetBandS1", "CreekWetBandS2"]
	for wnm in wet_bands:
		var wn := scene.get_node_or_null(wnm) as MeshInstance3D
		if _check("wet_band_%s_exists" % wnm, wn != null):
			_check("wet_band_%s_no_collision" % wnm, _count_collision_shapes(wn) == 0)
			_check("wet_band_%s_not_nav_source" % wnm, not wn.is_in_group("nav_source_courtyard"))
			_check("wet_band_%s_hugging_ground" % wnm,
				absf(wn.position.y - (GROUND_TOP + GROUND_SHADOW_LIFT)) < 1e-4)
			_check("wet_band_%s_east_of_gap" % wnm,
				wn.position.x - BANK_GAP_CENTER_X > 1.6 and wn.position.x > WATER_CENTER.x - WATER_SIZE.x * 0.5)
	print("VERIFY|CreekWetBands|count=%d" % wet_bands.size())

	# 水面契约原样（四区域 / 洞 / 缝 / 掩体的断言都在上面，这里只补 group 与环境两条）
	var water_nodes := 0
	for ch in scene.get_children():
		if ch.is_in_group("water_bodies"):
			water_nodes += 1
	_check("water_bodies_group_count_1", water_nodes == 1)
	var we2 := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _check("environment_exists", we2 != null and we2.environment != null):
		# 雾的防回归锁：**必须是远景深度雾**（begin ≥ 60 m），不许回到"近距离就开始吃对比"的指数雾
		_check("environment_fog_is_far_depth",
			(not we2.environment.fog_enabled)
			or (we2.environment.fog_mode == Environment.FOG_MODE_DEPTH
				and we2.environment.fog_depth_begin >= 60.0))
		# 关雾后仍然必须有天空（BG_SKY + ProceduralSkyMaterial），否则地平线会露出默认深褐空洞
		_check("environment_sky_kept", we2.environment.background_mode == Environment.BG_SKY
			and we2.environment.sky != null)
		# 接地感/对比的机制断言：SSAO 与 ACES 色调映射必须真的落进环境资源
		_check("environment_ssao_enabled", we2.environment.ssao_enabled)
		_check("environment_tonemap_aces", we2.environment.tonemap_mode == Environment.TONE_MAPPER_ACES)
		# 接地暗片必须**外扩**到冠层轮廓之外（收在脚印内会被草叶盖住 → 判"没有 AO"）
		var sh0 := scene.get_node_or_null("GroundShadowCover1") as MeshInstance3D
		if _check("ground_shadow_cover_exists", sh0 != null and sh0.mesh is PlaneMesh):
			var pm0 := sh0.mesh as PlaneMesh
			_check("ground_shadow_spread_outside_footprint", pm0.size.x > 2.3 and pm0.size.y > 2.4)
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


## ART07：装饰是否离所有掩体中心足够远（避免"看着像掩体、其实不是"的假线索）。
func _decor_clear_of_covers(p: Vector3, min_gap: float) -> bool:
	var centers := []
	for c in COVERS:
		centers.append(Vector2(float(c["pos"].x), float(c["pos"].z)))
	centers.append(Vector2(-28.0, 10.0))          # CreekReedCover
	for c in centers:
		if Vector2(p.x, p.z).distance_to(c) < min_gap:
			return false
	return true


## ART07：开阔暴露区（`DangerZone`）必须保持开阔 —— 装饰不得放进去。
func _inside_danger(p: Vector3) -> bool:
	var half := DANGER_SIZE * 0.5
	return absf(p.x - DANGER_CENTER.x) <= half.x and absf(p.z - DANGER_CENTER.z) <= half.z


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
