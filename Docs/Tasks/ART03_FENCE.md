# ART03-③：围栏 + 庇护棚墙换成石墙模块（`wall_stefan_wr`）

**状态**：done（灰盒替换完成，视觉待负责人判读）——**不是**正式美术 approved。
**编号**：ART03 是美术流水线任务；**没有**越过 P6（正式角色/骨骼）阶段门。

## 1. 目标与验收

| 项 | 内容 |
|---|---|
| 目标 | 把 T011 灰盒里的 4 段边界围栏（`FenceNorth/South/West/East`）与庇护棚三面墙（`ShelterWall*`）换成真实石墙视觉，**玩法几何不变** |
| 源 | `references/_downloads/wall_stefan_wr/model.glb`（Sketchfab，CC-BY，作者 Stefan） |
| 验收层 | A 资产层（面数/材质槽/尺度/贴地）· B 关卡层（生成器接入、碰撞盒不变、平铺覆盖、衬板）· C 运行层（实机关卡 4 机位） |
| 回归 | 全量 29 套断言套件全绿 |

## 2. 源件实测（Blender 3.3.1 导入，源单位≈厘米）

| 模块 | tris | 归一后尺寸（÷100） | 用途 |
|---|---|---|---|
| `wall_stone` | **1,244** | 2.4607 × 0.3027 × 2.0058 | **取它**（唯一够高的） |
| `wall_stone_medium` | 324 | 1.6126 × 0.2728 × 0.9929 | 未用 |
| `wall_stone_low` | 238 | 1.6221 × 0.1989 × 0.7738 | 未用 |
| `wall_stone_triplet` | 106 | 0.7899 × 0.2246 × 0.5071 | 未用 |
| `wall_single_rock` / `_2` / `_2.001` | 32 / 28 / 28 | 单块石头 | 未用 |

7 个网格件共 2,000 tris、2 材质槽、4×1024² 贴图。

## 3. 交付与接入

```
Tools/Blender/art06_fence_from_ref.py                处理脚本（÷100 → 墙面内等比 → 原点 → 重建材质 → 导出）
Art/Exports/Environment/SM_Fence_Module_001.glb      1,823,464 B，sha256 c2f4f152…cf95
Game/Reborn/assets/environment/sm_fence_module_001.glb（+ 2 张贴图 .import）
Game/Reborn/tests/tool_capture_art06.gd              实机关卡捕获工具（4 机位 + 墙段事实）
Art/Probes/art06_fence_{q34,face,end}.png            Blender 侧
Art/Probes/art06_{fence_north_interior,fence_corner,fence_west_close,shelter}.png   实机
```

生成器改动（`Game/Reborn/tests/tool_make_courtyard.gd`）：
- 新增 `FENCE_ASSET / FENCE_MODULE_LEN / FENCE_MODULE_H / FENCE_MODULE_THICK` 与 `_mk_clad_wall()`。
- 7 处 `_mk_box` → `_mk_clad_wall`（4 段围栏 + 庇护棚三面墙），**碰撞盒尺寸/位置一字未改**。
- `_verify()` 新增 41 条断言（每段墙：平铺块非空/是资产/无碰撞/覆盖长度/贴地/衬板存在且够高；庇护棚另验等比缩放）。
- **新增一盏不投影的补光 `SkyFill`**（见 §6）。

## 4. 关键契约

| 契约 | 值 | 谁在依赖 |
|---|---|---|
| 模块尺寸 | 3.680367（长）× 3.000000（高）× 0.302739（厚）m | `FENCE_MODULE_*`；`_verify` 的覆盖面断言 |
| 原点 | 脚印中心 + 底面 `y = 0` | 实例下沉 `−size.y/2` |
| 缩放 | 按段高**等比**：围栏 3.0 m → 1.0×；庇护棚 1.6 m → 0.533× | 石块比例 |
| 平铺 | 间距 = 段长 / ceil(段长 / (模块长 × 0.80)) → **相邻模块重叠 ≥ 20%** | 填掉模块两端的不规则缺口 |
| 衬板 | `Backing` 厚 0.08、色 (0.22, 0.21, 0.20)、不投影 | 遮住石块间**真实通孔**，避免看穿边界 |
| 碰撞 | `.glb` 无碰撞；仍是 `BoxShape3D`（围栏 0.2 厚 × 3.0 高；庇护棚 0.2 × 1.6） | T011 的 `_box()` 断言 |

## 5. 面数代价（务必知道）

`tiles_total_tris = 120,668`（25+25+20+20 段围栏 + 3 段庇护棚）。这是目前单关卡最大的三角形开销，
比换之前（纯 BoxMesh 12 tris/面）高两个数量级。**没有做过实机帧率测试**，`Docs/ART_ASSET_SPEC.md` 也没有场景总预算；
若要降，优先把围栏换成 `wall_stone_medium`（324 tris/件）或减少重叠。

## 6. 实测踩到的四个真缺陷（全部已修）

1. **glTF 导入后网格数据是 Y-up**：`transform_apply` 只烘对象自身变换 → 顶点仍是 Y-up，
   于是把"厚度"当高度缩放（首次运行产出 24.38 × 0.02 × 3.00）。修法：先存 `matrix_world`、脱离父级后再烘。
2. **源材质是 Sketchfab 的 Diffuse+Glossy+Add Shader 旧式节点**，glTF 导出器无法映射 →
   导出 GLB `images=0`（33 KB、无贴图）。修法：脚本内显式重建 Principled BSDF（BaseColor+Normal+Roughness 0.85）。
3. **石块之间有真实通孔，能看穿边界墙**：先加大重叠，再补 `Backing` 衬板。
4. **北墙内表面朝 −Z，与主光同向 → 整面近乎全黑**（3 m 石墙读不出材质）：加一盏不投影的 `SkyFill` 补光
   （`Basis.looking_at((0, −0.55, 0.85))`、能量 0.45、不投影），只抬背光面，主光阴影方向不变。

## 7. 边界（不算完成的事）

- 未由负责人做视觉验收；**不写 approved**。石墙是"旧石墙"观感（顶边不规则、有台阶），不是砌筑整齐的新墙。
- 平铺的重复感：已用交替 180° 翻转减轻，但同一张 1024² 贴图会在 3.7 m 周期上重复。
- 衬板是"遮缝"手段，不是真实砌体厚度；从上方俯视能看到衬板与石块的层次。
- 未做帧率/预算实测（见 §5）。
- 未推送、未发布。

## 8. ART03-⑮ 更新：庇护棚矮墙改用专用模块（2026-10-22）

§4 表里"庇护棚 1.6 m → 0.533× 等比缩放""间距含 ≥20% 重叠"这两条**只对围栏/岸墙仍然成立**；
庇护棚三面墙已改走独立路径：

| 项 | 新约定 | 断言 |
|---|---|---|
| 资产 | `sm_wall_low_001.glb`（`ENV_WALL_LOW_001`）= 2.436584 × 0.800000 × 0.302739，663 tris | `*_tiles_is_low_asset` |
| 层数 | `courses = round(段高 / 0.800)` → 1.6 m = **2 皮** | `*_tiles_courses_cover_height` |
| 竖向 | `k_y = 层高 / 0.800` → **1.0（不压扁）**；厚度同比 | `*_tiles_course_height_ok` / `*_tiles_thickness_kept` |
| 横向 | `n = round(段长 / 2.436584)`，`k_x = 段长 / (n × 2.436584)` → **宽度精确等于间距**（不重叠不漏缝） | `*_tiles_width_matches_spacing` |
| 位置 | 每块**踩在这一皮的底面**（模块原点是脚底） | `*_tiles_cover_height_exactly` / `*_tiles_inside_run` |
| 衬板 | `Backing` 色 **(0.34, 0.33, 0.30)**、不投影 | `*_tiles_backing_exists` |

原因：3 m 模块压到 1.6 m 会让石块比例走样，且源件下半部是被地面遮挡的扫描区（石块大缺口）。
定位过程与四次弯路见 `Docs/Evidence/ART03_FENCE.md` §9。**碰撞盒未动**。

## 9. ART03-⑮-2 / ⑮-3 更新：门垛立柱 + 转角料石（2026-10-22）

§8 之后补的"收边"两件，**碰撞盒仍未动**：

| 项 | 约定 | 断言 |
|---|---|---|
| 门垛立柱 `ENV_SHELTER_POST_001` | 0.16 × 0.36 × 1.62 m / 28 tris / 1 槽；`SHELTER_POST_*`；底面 `GROUND_TOP`、顶 1.72（咬进棚顶 2 cm）；中心 x = `SHELTER_X_MAX + PROUD − W/2` | `shelterpost*_{exists,single_post,no_collision,not_nav_source,is_asset,at_jamb_x,reaches_roof,on_wall_axis,covers_stone_protrusion}` |
| 单元转角料石 `ENV_QUOIN_001` | 0.36 × 0.40 × 0.36 m / 44 tris / 1 槽；`QUOIN_W/D/H`；各转角 **4 皮**（每皮转 90°）到 1.70，皮数 = `round(SHELTER_WALL_H / QUOIN_H)` | `shelterquoin*_{exists,courses,no_collision,not_nav_source,is_asset,on_corner_x,on_corner_z,grounded,spans_wall_height,covers_wall_thickness,protrusion_within_5cm}` |
| 衬板修剪 | **只在敞开的门垛端**收进 `BACKING_TRIM = 0.15`，中心随之下移 0.075；转角端必须铺满 | `*_tiles_backing_{exists,inset,shift}` |

原因与弯路见 `Docs/Evidence/ART03_FENCE.md` §10：衬板两端都收会让转角**看穿**；
转角两片墙各自内缩 ±7 cm → 必须用**料石**压住，而不是继续挪衬板。
