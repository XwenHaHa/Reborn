# Evidence：ART03-③ 围栏/庇护棚墙接入石墙模块（2026-10-21，本机系统时钟）

任务规格：`Docs/Tasks/ART03_FENCE.md`。环境：Blender 3.3.1、Godot 4.7.2-stable console。

## 1. 源件逐件实测（只读，未改动 `references/`）

```
PROBE|mesh|wall_stone_stone_wall_low_0|tris=1244|verts=775|slots=1|mat=stone_wall_low|dims=(246.067, 30.274, 200.578)
PROBE|mesh|wall_stone_medium_stone_wall_low_0|tris=324|dims=(161.262, 27.281, 99.286)
PROBE|mesh|wall_stone_low_stone_wall_low_0|tris=238|dims=(162.210, 19.893, 77.379)
PROBE|mesh|wall_stone_triplet_stone_wall_low_0|tris=106|dims=(78.993, 22.458, 50.713)
PROBE|mesh|wall_single_rock_stone_wall_low_0|tris=32|dims=(47.574, 32.077, 26.720)
PROBE|mesh|wall_single_rock_2_stone_wall_low_0|tris=28|dims=(35.945, 23.174, 27.641)
PROBE|mesh|wall_single_rock_2.001_stone_wall_low.001_0|tris=28|dims=(34.802, 29.772, 27.641)
PROBE|total_tris=2000
```

## 2. 处理脚本与产物

```
& 'D:\SoftWare\Blender\blender.exe' --background --factory-startup `
    --python 'E:\Reborn\Tools\Blender\art06_fence_from_ref.py' -- --stage all      # EXIT=0
```

```
PROBE|picked|wall_stone_stone_wall_low_0|tris=1244|verts=775|slots=1
PROBE|src|dims=(246.0665, 30.2739, 200.5777)|min=(-125.3459, -73.6051, -0.7892)
PROBE|scale|unit=0.0100|plane=1.49568|thickness_kept
PROBE|final|tris=1244|dims=(3.6804, 0.3027, 3.0000)|min=(-1.8402, -0.1514, 0.0000)|max=(1.8402, 0.1514, 3.0000)|slots=1
PROBE|rebuild_material|base=Image_0|normal=Image_2
PROBE|material|slots=1|name=MAT_Fence_Stone
PROBE|glb|path=E:/Reborn/Art/Exports/Environment/SM_Fence_Module_001.glb|bytes=1823464|sha256=c2f4f152c372655af98c8fdffa4315b8653e35698099631da8f8f855f728cf95
PROBE|done|tris=1244|failures=0
```

GLB 结构（自写 JSON chunk 解析器）：1 节点 / 1 网格 / 1 材质 `MAT_Fence_Stone`
（`baseColorTex=True`、`normalTex=True`、`roughness=0.85`、`metallic=0`）/ 2 张内嵌贴图 / 1,244 tris。

## 3. Godot 导入读回

```
DUMP|node|class=Node3D|name=sm_fence_module_001
  DUMP|node|class=MeshInstance3D|name=ENV_FENCE_MODULE_001
  DUMP|mesh|class=ArrayMesh|surface_count=1|aabb_pos=(-1.840184, 0.000000, -0.151370)|aabb_size=(3.680367, 3.000000, 0.302739)|verts=775|tris=1244
  DUMP|surface|index=0|material=res_name=MAT_Fence_Stone|roughness=0.850|metallic=0.000
```

## 4. 关卡接入

```
--check-only tool_make_courtyard.gd                       EXIT=0
tool_make_courtyard.gd                                    EXIT=0
tool_make_courtyard_nav.gd（**必跑**）                     EXIT=0
```

```
TOOL|wall_visual|FenceNorth|asset=…sm_fence_module_001.glb|size=(72.200, 3.000, 0.200)|tiles=25|spacing=2.902|k=1.000
TOOL|wall_visual|FenceSouth|…|tiles=25|spacing=2.902|k=1.000
TOOL|wall_visual|FenceWest|size=(0.200, 3.000, 56.200)|tiles=20|spacing=2.828|k=1.000
TOOL|wall_visual|FenceEast|…|tiles=20|spacing=2.828|k=1.000
TOOL|wall_visual|ShelterWallWest|size=(0.200, 1.600, 3.400)|tiles=3|spacing=1.133|k=0.533
TOOL|wall_visual|ShelterWallNorth|size=(3.000, 1.600, 0.200)|tiles=2|spacing=1.500|k=0.533
TOOL|wall_visual|ShelterWallSouth|…|tiles=2|spacing=1.500|k=0.533
```

`_verify()` 新增 41 条断言全部 OK（节选）：

```
VERIFY|fencenorth_wall_tiles_exist|OK
VERIFY|fencenorth_wall_tiles_is_asset|OK
VERIFY|fencenorth_wall_tiles_no_collision|OK
VERIFY|fencenorth_wall_tiles_cover_run|OK
VERIFY|fencenorth_wall_tiles_sunk|OK
VERIFY|fencenorth_wall_backing_is_slab|OK
…
VERIFY|shelterwallwest_tiles_scaled_to_wall|OK
```

## 5. 实机捕获

```
& '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
    --script 'res://tests/tool_capture_art06.gd' --quit-after 2400 -- art06-level
```

```
CAP|art06|wall|FenceNorth|box=(72.2, 3.0, 0.2)|tiles=25|tile_scene=…sm_fence_module_001.glb|tile_scale=1.000|tris_per_tile=1244|backing=yes
CAP|art06|wall|ShelterWallWest|box=(0.2, 1.6, 3.4)|tiles=3|tile_scale=0.533|tris_per_tile=1244|backing=yes
CAP|art06|tiles_total_tris=120668
四张图 save_result=0 (OK)
```

**视觉自查**（直接 Read PNG；本机 `vision.js` 不可用，不声称用过）：
- 第 1 版：`art06_fence_north_interior.png` 里模块间露出**大片黑色板面**（衬板裸露），整面墙几乎全黑。
- 修法后：石块连成连续砌体、缝里是深色灰缝（衬板作为"灰浆"读得通）、北墙背光面可辨材质。
- 仍未解决：模块顶边有台阶（旧石墙观感）、贴图 3.7 m 周期重复。

## 6. 回归

| 套件 | 结果 |
|---|---|
| T011 灰盒 | 210 / 0 失败（围栏内表面几何断言全部照旧 → 碰撞未变） |
| T012 导航 | 79 / 0 失败 |
| T026 掩护 / ART01 / ART02 | 96 / 83 / 46，全 0 失败 |
| **全量 29 套** | **3,127 条断言 / 0 失败 / 每套 EXIT=0 / `SCRIPT ERROR` 0** |

## 7. 四个真缺陷（本次发现并修掉）

1. **Y-up 陷阱**：glTF 导入后**网格数据是 Y-up**（Sketchfab 根节点带 −90°X 旋转），
   对子对象 `transform_apply` 只烘自身局部变换 → 顶点仍 Y-up。首跑把厚度当高度，产出
   `dims=(24.3840, 0.0201, 3.0000)` 并触发 `module_len|24.384` 断言失败。
   **修法**：删父级前先 `mw = src.matrix_world.copy()`，`src.parent = None` 后 `src.matrix_world = mw`，再 apply。
2. **材质不可导出**：源材质是 `Diffuse BSDF + Glossy BSDF + Add Shader`（Sketchfab 旧式），
   导出器无法映射 → 首版 GLB 33,376 B、`images=0`、`baseColorTex=False`。
   **修法**：脚本内按链接关系找出 diffuse/normal 贴图，重建 Principled BSDF（Roughness 0.85 常量，
   第三张 glossy 贴图属 specular 工作流，不硬塞进 Metallic-Roughness）。修后 1,823,464 B、`images=2`。
3. **通孔/裸露衬板**：石块之间是真通孔（能看穿边界墙）；且模块两端轮廓不规则，按 1:1 平铺时露出大片衬板。
   **修法**：① 加 `Backing` 衬板（0.08 厚、不投影）遮缝；② 平铺间距改为 `ceil(段长/(模块长×0.80))` → 重叠 ≥20%；
   ③ 衬板色从 0.13 调到 0.22（不再读成黑洞）；④（另加）交替 180° 翻转减轻重复感。
4. **背光面全黑**：北墙内表面朝 −Z，与主光（rot −50°/−30°，朝 +X 下 −Z）同向 → 整面几乎无光。
   **修法**：新增不投影的 `SkyFill`（`Basis.looking_at((0,−0.55,0.85))`、能量 0.45）。
   主光阴影方向与既有画面不受影响（其余截图平均亮度未见异常跳变，回归全绿）。

## 8. 未验证 / 未做

- 未做帧率/场景总面数实测（当前墙类共 120,668 tris）。
- 未由负责人视觉验收；**不写 approved**。
- 未推送、未发布。

---

## 9. ART03-⑮ 后续：庇护棚矮墙换专用模块（2026-10-22）

### 问题
§6 记录的已知瑕疵：庇护棚三面墙（`0.20 × 1.60 × 3.40/3.00`）此前把 **3 m 高的围栏模块整体缩到 1.6 m**
（`k = 0.533`），近看"石块悬空 + 大片深色衬板"。

### 定位（三次证伪，避免再走回头路）
1. **不是缩放压扁**：把源件各候选模块单独摆进 Blender/Godot 空场景正投影看，问题依旧。
2. `wall_stone_low`（1.622 × 0.774）**不是墙**，是 **7 块零星石头垒的锥形残堆**（顶端 1 块）。
3. `wall_stone_medium`（1.613 × 0.993）是 **4 排梯形石堆**；`wall_stone_triplet` 只有 3 块石头。
   → 源件 `wall_stefan_wr` 里**只有 `wall_stone`（围栏那件）是真墙面**。
4. 用"顶点压平"把 2.006 m 削到 0.800 m → 被压的三角面挤成一条、法线翻转被剔除，
   实机出现**大片塌陷空洞**（`holes_fill` 对这种"分离壳体"补不出面，实测 `faces=0`）。
5. 只留**下面** 0.8 m 也空 → 源件**下半部是被地面遮挡的扫描区**，石块本来就有大缺口。

### 做法
`Tools/Blender/art12_short_wall.py` → `SM_Wall_Low_001.glb`：取 `wall_stone` **最上面 0.800 m**
（上边界不动、下边界切在 2.006 − 0.800），切口用一块**藏在砌体内部**的石板封住
（`inset_x 0.90 / inset_y 0.42`、顶面下沉 6 mm —— 第一版几乎与石块同宽同厚，层缝处
露出一条偏亮的"找平线"，收进去之后侧视被石块包住，仍保持 **1 材质槽**）。
产出 **2.436584 × 0.800000 × 0.302739 m / 663 tris / 1 材质槽 / 1,810,332 B**，
sha256 `af7c6d52c7d5fee6d6f4764734948e06ee9fe5d593d78ae04af5b8c7ad53e168`
（初版 `6bee417f…` 是石帽未收进去的那一版）。

生成器 `_mk_low_wall()`：`courses = round(1.6 / 0.800) = 2`、`k_y = 1.0`（**无竖向压扁**）、
`n = round(段长 / 2.436584)`（3.0 m → 1 块、3.4 m → 1 块）、`k_x = 段长 / 2.436584`（1.231 / 1.395），
每块**踩在这一皮的底面**（模块原点是脚底，写成中心会上下各错半皮 —— 本轮真踩过这个坑，
已补 `*_tiles_cover_height_exactly` 断言）。衬板色从 0.20 提到 0.34（石缝读成砂浆而非黑洞）。

### 新增断言（9 条 × 3 面 = 27 条，全 OK）
`tiles_exist` / `tiles_is_low_asset`（`scene_file_path == WALL_LOW_ASSET`）/ `tiles_no_collision` /
`tiles_courses_cover_height` / `tiles_course_height_ok` / `tiles_thickness_kept` /
`tiles_width_matches_spacing` / `tiles_inside_run`（不探出段端）/ `tiles_cover_height_exactly` / `tiles_backing_exists`。

### 实机
```
& '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
    --script 'res://tests/tool_capture_art06.gd' --quit-after 40000 -- art06-level
```
```
CAP|art06|wall|ShelterWallWest|box=(0.2, 1.6, 3.4)|tiles=2|tile_scene=res://assets/environment/sm_wall_low_001.glb|tile_scale=1.000|tris_per_tile=663|backing=yes
CAP|art06|wall|ShelterWallNorth|box=(3.0, 1.6, 0.2)|tiles=2|tile_scene=res://assets/environment/sm_wall_low_001.glb|tile_scale=1.000|tris_per_tile=663|backing=yes
CAP|art06|wall|ShelterWallSouth|box=(3.0, 1.6, 0.2)|tiles=2|tile_scene=res://assets/environment/sm_wall_low_001.glb|tile_scale=1.000|tris_per_tile=663|backing=yes
```
新增机位 `art06_shelter_q34`（3/4 全景）与 `art06_shelter_face`（正对南墙）。
**视觉自查**（直接 Read PNG）：两面矮墙现在是**致密砌石**，石块比例与围栏一致、不再悬空；
原来层缝处那条浅色"找平线"已随石帽收进砌体消失，只在个别石排缺口处露出小亮块；
角落仍能看到一小段衬板/石排台阶。诊断用探针 `tests/tool_capture_low_wall.gd`
（空场景单块正/背投影，产物 `Art/Probes/lowwall_front/back.png`）。

### 回归
**全量 30 套 / 3,173 条断言 / 0 失败 / 每套 EXIT=0 / `SCRIPT ERROR` 0**
（`run_t013_movement_regression` 73、`run_t024_chase_search` 136、`run_t027_ecology` 96 需 `--quit-after 40000`，
默认 6000 会被截断成 NO_SUMMARY）。

### 两条本轮踩到的操作坑（务必记住）
1. **`tool_capture_art06.gd` 机位多，必须给足帧预算**：6 机位用 6000 会在第 1 机位后被引擎截断、
   PNG 不更新 → 读到的是**上一轮的旧图**（本轮据此误判过"墙面变成一块空板"）。现为 7 机位，
   用 **`--quit-after 60000`**。判据：日志必须有 `CAP|art06|done` 与每条 `save_result=0`。
2. **重跑 `tool_make_courtyard.gd` 后必须重跑 `tool_make_courtyard_nav.gd`**。生成器会重建整份
   `l_courtyard.tscn`，`NavRegion_Mouse/Cat` 与 `nav_source_courtyard` 组随之消失 → 全量回归里
   t012(18) / t013(15) / t020(4) / t023(3) / t024(1) / t025(3) / t026(16) / t027(16) 连锁失败（**76 条**），
   重烘焙后立刻恢复 3,173 条全绿。

### 仍未做
- 两端台阶（源件自带 ±7 cm）与横向 1.23–1.40 拉伸未处理。
- 未由负责人视觉验收；**不写 approved**；未推送、未发布。

---

## 10. ART03-⑮-2 / ⑮-3：门框立柱 + 转角料石（2026-10-22）

### 背景：谁做的
⑮-2（门框立柱）**接手时已在工作区未提交**（`Tools/Blender/art13_shelter_post.py`、
`SM_Shelter_Post_001.glb`、生成器 `_mk_shelter_post()` 与相关断言），非本次所写；
本轮复核、跑通、并修掉它的两处问题；⑮-3（转角料石）为本次新增。

### ⑮-2 门框立柱（`ENV_SHELTER_POST_001`）
门洞东侧两个直立端原先没有收边、棚顶东侧也没有支撑。木立柱 **0.16 × 0.36 × 1.62 m / 28 tris**
（程序化、1 材质槽、无碰撞、不进导航组），底面立在 `GROUND_TOP`、柱顶 1.72 略咬进棚顶下沿 1.70。

复核修掉的两点：
1. **材质过亮**：第一版 `baseColorFactor` 是 (0.200, 0.125, 0.072)，是棚顶木料
   `MAT_Roof_Plank` (0.048, 0.030, 0.017) 的 4 倍亮 → 实机像塑料立柱；
   改为 **(0.062, 0.040, 0.023)**（≈1.3 倍），同一套木料观感。
2. **重复断言 id**：`*_covers_wall_ends` 写了两遍且判据等价，改为
   `*_covers_stone_protrusion`（判据 `POST_D ≥ 0.30 + 1e-3`，即盖住两侧石块外凸）。
3. 顺带把衬板从"两端各收进 0.15"改成**只在门垛端收进**（新增 `trim_along_end` 参数），
   因为两端都收会让转角看穿（见下）。

### ⑮-3 转角料石（`ENV_QUOIN_001`）
**问题**：衬板改成只在门垛端收进后，转角靠两片墙互相咬合；但矮墙模块是平板扫描件，
石排在模块两端有 ±7 cm 内缩 → 转角处两边石头都往回收，露出 **6–10 cm 衬板竖带 + 壳体薄边**
（3× 放大图确认）。只把衬板铺到端头，只是把"看穿"变成"看到一块灰板"。

**做法（v2）**：`Tools/Blender/art14_quoin.py` → 一件整高料石 **0.382 × 0.422 × 1.600 m / 176 tris / 1 槽**，
内部是 **4 皮不同长宽高**的砌石：`(0.38,0.38,0.34) / (0.42,0.38,0.42) / (0.38,0.42,0.44) / (0.40,0.38,0.403)`，
相邻层转 90°、错缝摆放、皮间留 1 mm 缝；四边 12 mm 倒角 + 顶面 3% 收分；
材质 = **矮墙同一张贴图 × 倍率色 (0.70, 0.78, 0.70)**（导出 `baseColorTexture` + `baseColorFactor`，
守住倍率贴图约定）+ 法线贴图（强度 **0.35**，1.0 时料石上会出现明显 V 形阴影），roughness 0.85；
原点脚底居中。生成器 `_mk_corner_quoin()` 在 `ShelterQuoinSW`（−9.4, 25.7）与
`ShelterQuoinNW`（−9.4, 28.9）**各摆一件**（不运行时叠放/旋转）到 1.70，**零碰撞、不进导航组**。

**UV 弯路**：第一版按米数取窗口（密度 1/2.4366）→ 跨过贴图上的砖缝，料石印出**菱形花格**。
改为在贴图里**自动挑又平整、色调又接近墙石**的 64×64 方块做投影窗口
（`find_patches`：`方差 + 0.6×(均值−0.20)²` 打分，每皮各取一块互不重叠的），并把倍率色压到墙石亮度。
**第二版**再把"4 块同尺寸方块"换成"4 块不同长宽高的砌石"，最小边长提到 0.38（半宽 0.19，
比墙石外凸面 0.151 再多凸 3.9–5.9 cm）：外面看是错落的转角柱，棚内看也是一根清楚的柱子。

### 新增断言
- 立柱：存在/单实例/无碰撞/非导航源/是资产/贴门垛 x/顶到棚顶/面宽盖住石块外凸/在墙轴上。
- 料石：存在/单件/无碰撞/非导航源/是资产/在转角 x/z/落地/总高=墙高/顶到墙顶/盖住墙厚/外凸 ≤6 cm。
- 衬板：存在/长度符合"只在门垛端收进"/偏移符合。

### 实机
```
& '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
    --script 'res://tests/tool_capture_art06.gd' --quit-after 60000 -- art06-level
```
7 机位全部 `save_result=0`；新增 `art06_shelter_corner_sw` / `art06_shelter_jamb` /
`art06_shelter_corner_nw`（NW 角外侧只剩 1 m 空隙，改为从棚内门口回望）。
**视觉自查**（直接 Read PNG）：转角被整根料石压住、接缝不再露衬板；四皮高矮不同、错缝；门垛木柱与棚顶同色系。

### 第三条操作坑
**删掉 `.godot/imported/sm_xxx*` 之后要连跑两次 `--import`**：第一次只重建贴图（`.ctex`），
`.scn` 仍缺 → 生成器读到空场景、`*_is_asset` 全挂。判据：
`Get-ChildItem .godot\imported -Filter 'sm_xxx*.scn'` 能看到文件再继续。

### 回归
**全量 30 套 / 3,173 条断言 / 0 失败 / 每套 EXIT=0 / `SCRIPT ERROR` 0**。

### 仍未做
- 料石比乱石墙更"规整、略浅"，属修琢料石与毛石的质感差；若要更溶入可再做 2–3 块不同长宽的料石。
- 未由负责人视觉验收；**不写 approved**；未推送、未发布。
