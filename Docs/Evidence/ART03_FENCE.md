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
