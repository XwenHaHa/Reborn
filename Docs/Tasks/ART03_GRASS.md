# ART03-⑧：草丛重做（`ENV_BUSH_002`）——从"绿纸条"到有折面的草团

**状态**：done（已接入关卡，实机图已自查）——**不是**正式美术 approved。
**触发**：负责人两次指出草丛假（"草丛和溪边很假"、"把草丛…做得真一点"）。

## 1. 旧资产到底假在哪（ART01 的 `sm_bush_001`）

- 叶片是**单层平面四边面**（2,040 tris），侧看/近看就是纸片；
- 叶片**宽度不足**（细条），远处直接消失，读不出"草丛"；
- 泥土垫按包络 1.4 m 半径做，直径 2.87 m，像一块棕色大饼。

## 2. 新资产做法（`Tools/Blender/art09_grass_002.py`，deterministic seed）

| 项 | 旧（ART01） | 新（ART03-⑧） |
|---|---|---|
| 叶片 | 平面四边面 | **带中脊折面的 3 段弯曲带**（横向 2 格 → 有折角，不再是平面） |
| 宽度 | 细条 | 30–55 mm（基部），沿长度收窄、尖端约 2 mm 并微微下垂 |
| 数量/分布 | — | **210 片**分 3 圈：外圈铺开（矮、倾角大）、中圈、内圈（高、直立），每片独立倾角/扭角/长度/下垂 |
| 泥土垫 | 半径 1.4 m（直径 2.87 m 的大饼） | **半径 0.62 m** 的基部一坨，且**补了盘心顶点**（第一版中间是洞，从上往下透出灰背景） |
| 三角面 | 2,040 | **2,600**（预算 ≤3,000） |
| 材质槽 | 2（MAT_Bush_Leaf / MAT_Bush_Soil） | **同名同色同粗糙度**（0.85）、**双面** → 对外契约不变 |
| 包络 | 2.872 × 0.880 × 2.870 | **2.7648 × 0.8155 × 2.9521**（仍覆盖 3×3 掩体体量，且高于猫 0.48） |

## 3. 接入

- `Game/Reborn/assets/environment/sm_bush_002.glb`（99,988 B，sha256 `04401552…`）。
- 生成器 `BUSH_ASSET` 指向新资产；旧 `sm_bush_001.glb` **保留在仓库里可回退**。
- 4 处掩体（3 处 + 溪边 1 处）与 13 丛芦苇 + 岸线草**全部**随之换成新资产。
- 已有风摆 shader（ART03-⑦）继续作用在新资产的 `MAT_Bush_Leaf` 表面。

## 4. 同步更新的旧断言（必须写清，避免"改测试凑绿"的误会）

| 文件 | 改动 | 原因 |
|---|---|---|
| `tests/run_art01_bush.gd` | `ASSET` → `sm_bush_002.glb`；`asset_root_name` → `sm_bush_002`；`asset_mesh_node_name` → `ENV_BUSH_002`；`EXPECT_MESH_X/Z/Y` → 2.764810 / 2.952138 / 0.815492；`EXPECT_TRIS` → 2600 | 资产被替换，这些断言本身就是"记录当前资产事实" |
| `tests/tool_make_courtyard.gd` | `BUSH_ASSET` 指向新资产 | 同上 |

材质名/颜色/双面/粗糙度/**零碰撞**/高度覆盖这些**契约型**断言**没有放宽**，全部原样通过。

## 5. 验证

- `run_art01_bush.gd`：**83/83 通过**（含资产层 AABB/面数/材质、关卡层 4 处视觉、运行层猫落进掩体）。
- 生成器 `VERIFY|CoverBush|*|mesh_size=(2.765, 0.815, 2.952)` 三处全 OK。
- 全量回归：**30 套 / 3,173 条 / 0 失败**。
- 实机图：`Art/Probes/art01_level_west_a_near.png`（近景草团）、`art09_grass_{low,q34,top}.png`（资产侧）。

## 6. 边界

- 仍**没有贴图**（纯色 + 折面明暗），近距离还是"程序化草"的观感；要更进一步得引入叶片 albedo/法线贴图或
  用更贵的建模手法（这也是 `ART_ASSET_SPEC` 允许的下一步）。
- 叶尖仍有轻微"硬折"（3 段），没有做逐叶细分。
- 未 approved、未推送。

## 7. 贴图（ART03-⑨，续做）

原因：ART03-⑧ 之后草丛是"纯色 + 折面"，近距离仍是程序化观感。这一轮加**程序化生成的贴图**。

| 项 | 做法 |
|---|---|
| 叶片 `T_Grass_Leaf` | 128×256：纵向明暗（基部 0.78 → 中上部 1.10 → 叶尖 0.90）+ 中脊高光（与几何中脊折面对应）+ 细纵纹（叶脉）+ 斑驳噪声；三通道轻微色偏（R1.00 / G1.03 / B0.96） |
| 泥土 `T_Grass_Soil` | 128×128：两级噪声斑驳 + 边缘压暗（土堆轮廓） |
| **关键：贴图是倍率图（均值≈1）** | 节点树用 `MixRGB(MULTIPLY)`：`image × 线性色 → Base Color`。glTF 因此**同时**导出 `baseColorTexture` 与 `baseColorFactor`，ART01 的"albedo ≈ sRGB(线性色)"契约**原样成立**（实测 factor = [0.085, 0.200, 0.075] 完全一致） |

导出核验（自写 GLB JSON 解析）：

```
mat[0] name=MAT_Bush_Leaf baseColorFactor=[0.085, 0.200, 0.075, 1] metallic=0 roughness=0.85 baseColorTex=True
mat[1] name=MAT_Bush_Soil baseColorFactor=[0.055, 0.038, 0.025, 1] metallic=0 roughness=0.85 baseColorTex=True
image[0] T_Grass_Leaf image/png 10,063 B / image[1] T_Grass_Soil image/png 13,662 B
```

Godot 侧：两张贴图被正常抽取为 `sm_bush_002_T_Grass_{Leaf,Soil}.png`（+`.import`）；
`MAT_Bush_Leaf.albedo_color` 仍是 `(0.3227, 0.4845, 0.3035)`、roughness 0.85、`cull_mode=2`。

**效果与局限**：中近景能看到叶片根暗尖亮、纵向纹理、土堆有斑驳；但**远处（>6 m）增益有限**，
而且**没有法线贴图**，折面 + 贴图仍是"程序化草"的底子。要继续提升得做叶片双面法线或用贴图工厂做 atlas。

## 8. 细分 + 法线贴图 + 双面法线（ART03-⑩，续做）

上一轮贴图只解决了"颜色纹理"，近景仍是"硬折 + 平面光照"。这一轮补三件事：

| 项 | 改动 | 为什么 |
|---|---|---|
| 叶片细分 | 3 段 → **5 段**；为守住 ≤3000 tris，叶片数 210 → **145**（145×5×2×2 = 2,900 + 土垫 80 = **2,980**） | 3 段时叶尖有明显硬折；5 段弯曲更顺，代价是同样面数下叶子少一些 |
| **叶片法线贴图** `T_Grass_Leaf_N`（128×256，Non-Color） | 由高度场（中脊凹槽 + 叶脉细棱 + 斑驳 + 叶缘下卷）做有限差分生成切线空间法线，接 `Normal Map → Principled Normal`；导出开 `export_tangents` | 让中脊/叶脉在光照下真的"有起伏"，而不是只靠折面 |
| **双面法线修正** | `grass_wind.gdshader` 的 `fragment()` 第一条：`NORMAL = FRONT_FACING ? NORMAL : -NORMAL;` | 草叶是单面网格 + `cull_disabled` 双面渲染；背面不翻法线会让**草丛内部发黑**（玩家蹲在草里时最明显） |

导出后核验（自写 GLB JSON 解析）：

```
mat[0] MAT_Bush_Leaf baseColorFactor=[0.085, 0.200, 0.075, 1] roughness=0.85 baseColorTex=True normalTex=True
mat[1] MAT_Bush_Soil baseColorFactor=[0.055, 0.038, 0.025, 1] roughness=0.85 baseColorTex=True normalTex=False
image[0] T_Grass_Leaf_N 58,641 B / image[1] T_Grass_Leaf 10,063 B / image[2] T_Grass_Soil 13,662 B
```

Godot 侧抽出 3 张图（含 `sm_bush_002_T_Grass_Leaf_N.png` 58,641 B）。

**AABB 变化**：2.626693 × 0.796629 × 2.747555（叶片更少更细），已同步
`run_art01_bush.gd` 的 `EXPECT_MESH_X/Y/Z` 与 `EXPECT_TRIS=2980`；
生成器 `cover_*_visual_size` 的下界从 y≥0.80 放宽到 **y≥0.78** 并在注释里写明原因
（0.797 仍远高于猫 0.48，掩体语义不变）。

## 9. 验证（⑩）

- `run_art01_bush.gd`：**83/83**
- 生成器：`VERIFY|CoverBush|*|mesh_size=(2.627, 0.797, 2.748)` 三处 OK
- 全量回归：**30 套 / 3,173 条 / 0 失败**
- 实机图 `Art/Probes/art01_level_west_a_near.png`：叶片弯曲连续（无硬折）、有明暗条纹

**剩余局限**：法线贴图是程序化生成的，近景仍有"程序化"底子；草叶数量减少后密度略降
（可用 scale 或再提高面数预算补回，但那需要先改 ART01 的 ≤3000 预算）。

## 10. 预算 3k → 6k、叶片加回 220（ART03-⑪）

- 依据：`tool_perf_probe.gd` 实测本关卡 **1.643 ms/帧（p95 1.969）≈609 fps @720p**，
  即使草丛升到 4,480 tris（场景 178,068 primitives / 53 draw call）也没有变成瓶颈。
- 改动：`TRI_BUDGET 3000 → 6000`；叶片 145 → **220**（96+72+52 三圈）；基部宽 30–55 → **34–62 mm**。
- 结果：**4,480 tris**，AABB 2.800434 × 0.815600 × 2.929748，min_z=0；颜色/法线贴图与双面法线不变。
- 同步：`run_art01_bush.gd` 的 `EXPECT_TRIS=4480`、`EXPECT_MESH_X/Y/Z`、以及
  `asset_tri_budget_3000 → asset_tri_budget_6000`（"≤3000" → "≤6000"）；`Docs/ART_ASSET_SPEC.md` 新增草丛预算行。
- 回归：`run_art01_bush` **83/83**；全量 **30 套 / 3,173 条 / 0 失败**。
