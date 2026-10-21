# ART_ASSET_AUDIT —— 资产审计（Reference Lock 第 1 轮）

日期：2026-10-21（本机系统时钟）｜执行：agent｜触发：`modeling4.md`
**本文件只记录实测事实**；未验证的内容一律标 `NOT-VERIFIED`。

## 1. 工程与工具（实测）

| 项 | 事实 |
|---|---|
| 引擎 | Godot **4.7.2.stable.official.ed1daf0bf**，`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` |
| 工程 | `Game/Reborn/`（`project.godot`） |
| Blender | `D:\SoftWare\Blender\blender.exe`，**3.3.1**，`--background --factory-startup --python` 可用 |
| Agent 文件能力 | 读写工程内任意文本/二进制资产；可跑 Blender 无头 CLI、Godot headless + 窗口渲染 |
| MCP | **没有**（`Docs/BlenderPipeline.md` §路线：CLI 取代 MCP；本机无 MCP 服务） |
| 联网 | **可用**：`api.polyhaven.com`、`api.sketchfab.com/v3`、`dl.polyhaven.org`、`kenney.nl`、`poly.pizza`、`opengameart.org` 均实测 HTTP 200（本机系统代理 `127.0.0.1:7897` 与直连均可） |
| 下载能力 | **实测可下载**：Poly Haven CC0 资源匿名直链下载成功并校验字节数；**Sketchfab 匿名 API 可查元数据，但下载需登录账号（本会话无凭据）** |
| 视觉判读 | `node E:\claude-vision-skill\vision.js <png> "<问题>"` 可用 |

## 2. Git 状态（修改前）

`git log -1` = `596522b feat(ART02-V009): 猫基础形体重建…正式资产保持 V008`
`git status --short` 仅 `?? modeling4.md`（本轮指令文件）。**本轮未修改任何正式资产。**

## 3. 现有资产清点（逐项实测）

### 3.1 真正建模并接入游戏的（**2 件**）

| 资产 ID | 源 | 导出 | 规格 | 引用处 |
|---|---|---|---|---|
| `CAT_BODY_001` (V008) | `Art/Blender/Cat/CAT_BODY_001_v001…v008.blend` | `Art/Exports/Cat/SM_Cat_001.glb` = `Game/Reborn/assets/characters/cat/sm_cat_001.glb`（1,744,408 B，sha256 `b5ae013b…`） | **9568 tris** / 2 材质槽 / 1×2048² albedo / 高 0.389 m / 长 0.601 m / **无骨骼·无动画·无碰撞** | `resources/species/cat.tres` → `visual_scene` → `AnimalBody._rebuild_visual()` |
| `ENV_BUSH_001` | `Art/Blender/Environment/ENV_BUSH_001_v001…v003.blend` | `Art/Exports/Environment/SM_Bush_001.glb` = `Game/Reborn/assets/environment/sm_bush_001.glb`（156,660 B） | **2040 tris** / 2 材质槽 / 无贴图 / 双面 / 零碰撞 / 高 0.88 m | `l_courtyard.tscn` 4 处掩体实例 |

**猫的未通过状态**：V008 = `generated + 5 轮返工 + 未 approved`；V009（骨架+Skin 重建）`not-accepted`，
在 `Art/Blender/Cat/CAT_BODY_001_v009{,r2,r3}.blend` + `Art/Staging/ART02_V009/`，**未接入 Godot**。

### 3.2 只做流水线验证的探针（**2 件**，非游戏内容）

| 资产 | 文件 | 面数 | 用途 |
|---|---|---|---|
| `SM_ProbeCube` | `assets/tests/sm_probe_cube.glb`（6,992 B） | 12 tris | T005 尺度/轴向往返 |
| `SK_RigProbe` | `assets/tests/sk_rig_probe.glb`（12,492 B） | 骨骼+1 段循环动画 | T006 骨骼往返 |

### 3.3 灰盒占位（**没有建模**，全部是引擎基元）

| 场景 | MeshInstance3D | BoxMesh 子资源 | 备注 |
|---|---|---|---|
| `scenes/maps/l_courtyard.tscn` | **22** | **22** | 地面/四周围栏/庇护棚(3 墙+顶)/碎片×6/土墩×2/树根屏障×3/溪岸墙×2/巨石/危险区薄片 |
| `scenes/maps/l_move_fixtures.tscn` | **18** | **18** | 斜坡/低顶/平台/台阶（玩法验证用，可长期保留） |
| `scenes/maps/l_movement_lab.tscn` | **3** | **3** | 另有 2 处探针立方体实例 |

其它：
- **鼠**的视觉 = `scenes/characters/animal_body.tscn` 的 `CapsuleMesh`（r 0.06 / h 0.18），**没有任何模型**。
- 猫的**碰撞** = 同一 `AnimalBody/CollisionShape3D` 胶囊（0.16 / 0.48）；`BodyMesh` 的胶囊网格保留但 `visible=false`（尺寸代理）。
- `scenes/world/resource_point.tscn` 的食物/水源 = `BoxMesh` + 纯色材质（`scripts/world/resource_point.gd:279`）。
- HUD / 调试线框 = 2D UI + `ImmediateMesh`（**不算 3D 建模**）。
- **贴图**：只有猫有 1 张烘焙 albedo；其余全部纯色 `StandardMaterial3D`。

### 3.4 依赖关系（改动风险）

| 资产 | 依赖方 | 契约 |
|---|---|---|
| 猫视觉 | `cat.tres`、`AnimalBody`、`tests/run_art02_cat.gd`（46 条）、`tests/tool_capture_art02.gd` | 原点=脚底地面中心、面朝 `-Z`、高 ≤0.48、无碰撞、≤2 材质槽；`run_t009/t013` 的 `mesh==capsule` 断言 |
| 草丛 | `tool_make_courtyard.gd`、`tests/run_art01_bush.gd`（83 条） | 包络 ≤1.45 m、高 ≤0.90、泥土垫顶 ≤0.12、双面、零碰撞、不进 `nav_source_courtyard` |
| 关卡几何 | `tool_make_courtyard.gd` → `l_courtyard.tscn` → **必须**再跑 `tool_make_courtyard_nav.gd` 重烤导航 | 改几何会清掉 `NavigationRegion3D`（ART01 实测） |

## 4. 本轮实测的「需要建模」清单与状态

（口径：`开发计划` P6 T044～T054 + 游戏内需要被看见的对象）

| # | 对象 | 计划任务 | 状态 |
|---|---|---|---|
| 1 | 猫形体 `CAT_BODY_001` | T045/T046 | 🟡 **已建模未 approved**（V008 在用；V009 未通过） |
| 2 | 猫骨骼+权重 | T047 | ⬜ 未开始 |
| 3 | 猫 Idle/Walk | T048 | ⬜ 未开始 |
| 4 | 猫 Run/AttackCue | T049 | ⬜ 未开始 |
| 5 | 鼠形体 `MOUSE_BODY_001` + UV/材质 | T050 | ✅ **已建模并接入**（3,602 tris / 23 骨 / 4 段动画；未 approved） |
| 6 | 鼠骨骼+权重 | T051 | ⬜ 未开始 |
| 7 | 鼠 Idle/Move/Flee | T052 | ⬜ 未开始 |
| 8 | 草丛掩体 `ENV_BUSH_001` | T053 | ✅ **已建模**（未 approved） |
| 9 | 树根屏障 + 鼠洞（含通行净空） `ENV_ROOT_HOLE_001` | T053 | 🟡 **洞口的树桩入口已做并接入**；整道屏障仍是 BoxMesh |
| 10 | 溪边巨石 `ENV_BOULDER_001` | T053 | ✅ **已建模并接入**（7,500 tris / 1 槽；未 approved） |
| 11 | 矮墙/围栏 `ENV_FENCE_MODULE_001` | T053 | ✅ **已建模并接入**（1,244 tris/模块 ×90 平铺；未 approved） |
| 12 | 庇护棚 / 地面 / 土墩 / 碎片 / 溪岸 | T053 延伸 | ⬜ BoxMesh |
| 13 | 食物（肉/种子）、水源交互物 | 玩法需要 | ⬜ `BoxMesh` + 纯色 |
| 14 | 环境材质与贴图（石/土/木/草） | T053/T060 | ⬜ 纯色，无贴图 |

**结论**：需要建模的对象里 **只有 3 件已完成建模**（猫、草丛、巨石），其余 11 类仍是灰盒或不存在。
其中 **猫/鼠/洞口/巨石/围栏** 这 5 类是本轮 Reference Lock 要选型的对象。

## 5. 本轮能力限制（不得假装已做）

- **Sketchfab 下载需要账号**：匿名 API 只返回元数据（`isDownloadable=true`，但 `archives` 为空）→
  候选模型**没有下载**，状态为 `reference_pending`，已在 manifest 里写明人工下载步骤。
- **未验证项**：候选模型的真实网格（拓扑密度分布、UV 质量、骨骼/权重、朝向、真实尺寸）**无法在无下载的情况下确认**，
  因此**不给**面数之外的技术结论，也不给 `approved`。
- **未访问**：Blendkit 站点只做了可达性探测（HTTP 200），**未检索其授权条款**；本轮不把它作为候选来源。

## 6. 本轮真实网格检查（4 个候选，Blender 3.3.1 导入读回）

> 不是复述页面标注：以下数字是 `bpy.ops.import_scene.*` 导入后从 `mesh.loop_triangles` / `armature.bones` /
> `action` / 世界包围盒读出来的。原始记录：`references/reference_measurements.json`。

| 候选 | 文件 | tris | 材质槽 | 贴图 | 骨骼/动作 | 真实尺寸（m） | 与 API 一致 | 结论 |
|---|---|---|---|---|---|---|---|---|
| 猫 `cat_fripouille` | `frip_F_export.fbx` | **8,376** | 3（SHD_frip / SHD_eye / whiskers） | 4 张（BaseColor 2.85 MB、Normal DX、AO、eye）**未随 FBX 自动挂上** | **33 骨** / **0 动作** | 15.86 × 10.17 × 8.41（**非米**） | ✅ | **可作猫基础模型**；需归一化缩放 ≈0.0315、转向（最长轴 X）、材质并到 2 槽、自建 4 段动画 |
| 鼠 `mouse_arribadaclub` | `model.glb` | **10,000** | 1 | 3×1024² | 无骨骼 / 无动作 | **0.068 × 0.138 × 0.061**（真实家鼠尺度） | ✅ | **可作鼠基础模型**；需完整绑定 + Idle/Move/Flee |
| 洞口 `stump_callum_arb` | `model.glb` | **39,122** | 1 | 2×1024² | 无 | 2.13 × 2.67 × 1.21 | ✅ | 有真空腔但净空 ≈0.238 × 0.173 m **未达 0.24 × 0.30**；需减面到 ≤15k + 局部改形 |
| 围栏 `wall_stefan_wr` | `model.glb` | **2,000** | 2 | 4×1024² | 无 | 4.08 × 1.59 × 2.01（像 cm） | ✅ | **7 个独立模块**，面数与槽位都合格；需归一化 + 清层级 |

四个文件的 `faces` 与 Sketchfab API 返回的 `faceCount` **逐一相同** → 该来源的元数据可信，可用于选型判断。

补充：巨石 `boulder_01`（Poly Haven CC0）**已下载、已实测、已处理并接入关卡**（见 §9）：
源 66,122 面 / **1.2721 × 1.8303 × 1.0038 m（米制，无需缩放）**，减面到 7,500 后替换 `CreekBoulder` 的 1.2³ BoxMesh。

## 7. 本轮结论（供负责人 5 分钟内决策）

1. **猫**：`cat_fripouille` **够格当基础模型**（带 33 骨、面数 8.4k、有 PBR 贴图），主要工作量在"归一化 + 转向 + 2 槽合并 + 自建动画"。
2. **鼠**：`mouse_arribadaclub` 尺寸/材质完美但**没骨骼**；若你要求"带动画起步"，需要补下 `mouse_charliecatling`（本轮下载失败）。
3. **洞口**：`stump_callum_arb` 的腔体偏窄，**要么放大改形，要么只借它的树皮质感自建洞口**。
4. **围栏**：`wall_stefan_wr` 的 `wall_stone` 模块已处理并接入（见 §10），1,244 tris/件、平铺 90 件、共 120,668 tris。
5. **巨石**：CC0，**实测 1.27 m 米制（不是 12.7 m）**，只需减面 66,122 → 7,500；已完成并接入（见 §9）。

## 8. 负责人决策后的第一件产物：猫（cat_fripouille → 合规资产）

负责人 2026-10-21 决策：**猫用 `cat_fripouille`，其余也从已下载候选里取**。
据此新增 `Tools/Blender/art04_cat_from_ref.py`，产出 `Art/Exports/Cat/SM_Cat_002.glb`：

```
fit|scale=0.03657|dims=(0.3720, 0.5800, 0.3074)|min=(-0.1860, -0.2900, 0.0000)
check|tris=8376|verts=4264|slots=2|bones=33|dims=(0.3576, 0.5961, 0.3074)|min_z=-0.0000
glb|path=Art/Exports/Cat/SM_Cat_002.glb|bytes=7,075,276|sha256=bb01371788c837d6…
```

| 项 | 结果 |
|---|---|
| 面数 / 材质槽 | **8,376 tris / 2 槽**（原 3 槽已并：`SHD_eye` + `whiskers` → `MAT_Cat_Detail`） |
| 骨骼 | **33 骨保留**（`export_skins=True`），无动画（源无 action） |
| 贴图 | BaseColor + 法线（DirectX → **G 通道已翻转**）+ 眼球贴图；随 GLB 内嵌 |
| 尺度 | 按体长 **0.596 m** 归一（高 0.307 m、宽 0.358 m），`min_z = 0`（贴地） |
| 朝向 | 用"眼睛质心"判定头侧 → 绕 Z 旋转 **-90°**，面朝 **+Y**（Godot 内即 -Z） |
| 渲染 | `Art/Probes/art04_cat_ref_{front,side,back,corner45,top,face}.png` + `_sheet.png` |
| Godot 接入 | **尚未接入**（`cat.tres` 仍指向 V008）。等视觉确认后再切 |

**视觉判读状态**：`vision.js` 两次调用均失败（502 上游错误 → 503 `auth_unavailable`），
按项目规则**记录为 NOT-VERIFIED**，不编造判读结论；图已生成，可由负责人直接查看。


## 9. 巨石 `boulder_01` → 合规资产（**已接入关卡**）

`Tools/Blender/art05_boulder_001.py` → `Art/Exports/Environment/SM_Boulder_001.glb`（3,048,844 B，
sha256 `dc9a00e4…288c`）→ `Game/Reborn/assets/environment/sm_boulder_001.glb`，
由 `tool_make_courtyard.gd` 的 `_mk_boulder()` 替换 `CreekBoulder` 的 1.2³ BoxMesh。
详见 `Docs/Tasks/ART03_BOULDER.md` / `Docs/Evidence/ART03_BOULDER.md`。

| 项 | 源件实测 | 交付 |
|---|---|---|
| 三角形 | 66,122 | **7,500**（预算 1k–8k） |
| 尺度 | **1.2721 × 1.8303 × 1.0038 m** | 1.2686 × 1.8292 × 1.0042（**未缩放**） |
| 材质槽 | 1 | 1（metallic 0） |
| 贴图 | 3 × 1K | 3 × 1K 内嵌 |
| 原点 | — | 脚底中心（Godot `aabb_pos.y = 0`，实例下沉 −0.502117） |
| 碰撞 | — | `.glb` 无碰撞；Godot 侧 `BoxShape3D` = 视觉 AABB（1 个 shape） |

**⚠ 更正**：§5 补充段与 §7 第 5 条曾写"123,976 面 / ~12.7 m，要缩到 1.2 m（0.09×）"，
那是 Sketchfab API 元数据（本资产其实来自 Poly Haven）。**Blender 实测 66,122 面、1.27 m，米制**，
**不需要缩放**，只需减面。已按实测处理。

**视觉状态**：`generated + 4 机位实机图`（`Art/Probes/art05_level_boulder_*.png`），**等负责人判读**，
不写 approved。`vision.js` 本机不可用（502/503），视觉自查用直接读 PNG。

## 10. 围栏/庇护棚墙 `wall_stefan_wr` → 合规资产（**已接入关卡**）

`Tools/Blender/art06_fence_from_ref.py` → `Art/Exports/Environment/SM_Fence_Module_001.glb`
（1,823,464 B，sha256 `c2f4f152…cf95`）→ `Game/Reborn/assets/environment/sm_fence_module_001.glb`，
由 `tool_make_courtyard.gd` 的 `_mk_clad_wall()` 平铺到 4 段边界围栏 + 庇护棚三面墙。
详见 `Docs/Tasks/ART03_FENCE.md` / `Docs/Evidence/ART03_FENCE.md`。

| 项 | 源件实测（取 `wall_stone` 件） | 交付 |
|---|---|---|
| 三角形 | 1,244（7 件合计 2,000） | 1,244 / 件 |
| 尺度 | 246.0665 × 30.2739 × 200.5777（源单位≈厘米） | **3.680367 长 × 3.000000 高 × 0.302739 厚**（÷100 后墙面内等比到 3.0 m 高，厚度保持天然） |
| 材质 | 2 槽（`stone_wall_low` / `.001`） | **1 槽** `MAT_Fence_Stone`（BaseColor + Normal + Roughness 0.85） |
| 贴图 | 4 × 1024² | 2 × 1024² 内嵌 |
| 碰撞 | — | `.glb` 无碰撞；Godot 侧仍是 `BoxShape3D`（围栏 0.2 厚 × 3.0 高、庇护棚 0.2 × 1.6），**尺寸一字未改** |
| 平铺 | — | 间距 = 段长 / ceil(段长/(模块长×0.80))（重叠 ≥20%）+ 交替 180° 翻转；`Backing` 衬板遮住石块通孔 |

**代价（务必知道）**：墙类合计 **120,668 tris**，是本关卡目前最大开销；**未做帧率实测**，规格里也没有场景总预算。
**视觉状态**：`generated + 4 机位实机图`，**等负责人判读**，不写 approved。

## 11. 鼠洞入口 `stump_callum_arb` → 合规资产（**已接入关卡**）

`Tools/Blender/art07_root_hole_from_ref.py` → `Art/Exports/Environment/SM_RootHole_001.glb`
（3,102,320 B，sha256 `d983a1e1…2be5`）→ `Game/Reborn/assets/environment/sm_root_hole_001.glb`，
由 `tool_make_courtyard.gd` 的 `_mk_root_hole_visual()` 放在洞口南北两侧（`RootHoleStumpS/N`）。
详见 `Docs/Tasks/ART03_ROOTHOLE.md` / `Docs/Evidence/ART03_ROOTHOLE.md`。

| 项 | 源件实测 | 交付 |
|---|---|---|
| 三角形 | 39,122（超预算 2.6 倍） | **12,555**（预算 3k–15k） |
| 尺度 | 2.128 × 2.666 × 1.205（**含扫描自带方形地面**） | 0.823243 × 0.850000 × 0.778105（归一高 0.85 m） |
| 材质/贴图 | 1 槽 | 1 槽（BaseColor + Normal） |
| 真实形态 | 空心中空树干，**腔体是"碗"、没有贯穿洞** | 布尔破出 **0.24 × 0.30 贯通方孔**，射线 9/9 全通 |
| 连通块 | **528 个**（树干 + 扫描碎石） | 只留主体（裁半径 0.55 m 外 + 删小壳） |
| 碰撞 | — | **零碰撞**、**不进** `nav_source_courtyard`（通行仍由 `RootBarrier*` 的 BoxShape3D 决定） |

**⚠ 更正**：§6 表里"洞口腔体净空 ≈0.238×0.173 m（未达 0.24×0.30）"是**按包围盒猜的**，
实测没有贯穿洞 → 已改为"自己破孔"方案。

**视觉状态**：`generated + 4 机位实机图`，**等负责人判读**，不写 approved。

## 12. 鼠 `mouse_cc_mehrus_rat` → 合规资产（**已接入关卡**）

`Tools/Blender/art08_mouse_from_ref.py` → `Art/Exports/Mouse/SM_Mouse_002.glb`
（501,512 B，sha256 `d27a5534…`）→ `Game/Reborn/assets/characters/mouse/sm_mouse_002.glb`，
经 `resources/species/mouse.tres` 的 `visual_scene` 由 `AnimalBody._rebuild_visual()` 实例化。
详见 `Docs/Tasks/ART03_MOUSE.md` / `Docs/Evidence/ART03_MOUSE.md`。

| 项 | 源件实测 | 交付 |
|---|---|---|
| 三角形 | 3,602 | 3,602（预算 5k–20k，低于下限但结构完整） |
| 骨骼/动画 | **23 骨**、**4 段**（Iddle/Walk/Run/Eat） | 23 骨、4 段（`Idle/Walk/Run/Eat`，各 69 通道） |
| 材质/贴图 | 1 槽、1×1024²；**unlit**（Emission+Transparent+Mix） | 1 槽 Principled（Roughness 0.8 / Metallic 0） |
| 尺度 | 身体（去尾）2.4015 单位 | 身体 **0.135 m**，含尾 0.2245 m，身高 0.0706 m |
| 朝向 | 头朝 −Y | 绕 Z 180° → 头朝 **+Y**（Godot −Z） |
| 碰撞 | — | **无**（胶囊 r=0.06 / half_height=0.09 未改） |
| 已知落差 | — | **大鼠体态**，不是家鼠；**动画播放逻辑未接** |

**弃用记录**：`mouse_arribadaclub`（展平标本扫描件，不能当活体角色）、
`mouse_charliecatling`（Free Standard 限制再分发 + NoAI 标记，与入库/AI 流程冲突）。
