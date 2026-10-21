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
| 5 | 鼠形体 `MOUSE_BODY_001` + UV/材质 | T050 | ⬜ 仍是胶囊 |
| 6 | 鼠骨骼+权重 | T051 | ⬜ 未开始 |
| 7 | 鼠 Idle/Move/Flee | T052 | ⬜ 未开始 |
| 8 | 草丛掩体 `ENV_BUSH_001` | T053 | ✅ **已建模**（未 approved） |
| 9 | 树根屏障 + 鼠洞（含通行净空） `ENV_ROOT_HOLE_001` | T053 | ⬜ BoxMesh 拼的，洞口无几何 |
| 10 | 溪边巨石 `ENV_BOULDER_001` | T053 | ⬜ 1.2³ BoxMesh |
| 11 | 矮墙/围栏 `ENV_FENCE_MODULE_001` | T053 | ⬜ BoxMesh |
| 12 | 庇护棚 / 地面 / 土墩 / 碎片 / 溪岸 | T053 延伸 | ⬜ BoxMesh |
| 13 | 食物（肉/种子）、水源交互物 | 玩法需要 | ⬜ `BoxMesh` + 纯色 |
| 14 | 环境材质与贴图（石/土/木/草） | T053/T060 | ⬜ 纯色，无贴图 |

**结论**：需要建模的对象里 **只有 2 件已完成建模**（猫、草丛），其余 12 类仍是灰盒或不存在。
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

补充：巨石 `boulder_01`（Poly Haven CC0）已下载 glTF 1K；其 123,976 面与 ~12.7 m 尺寸来自 API 的 `polycount`/`dimensions`，
**尚未做减面与缩放验证**（下一步）。

## 7. 本轮结论（供负责人 5 分钟内决策）

1. **猫**：`cat_fripouille` **够格当基础模型**（带 33 骨、面数 8.4k、有 PBR 贴图），主要工作量在"归一化 + 转向 + 2 槽合并 + 自建动画"。
2. **鼠**：`mouse_arribadaclub` 尺寸/材质完美但**没骨骼**；若你要求"带动画起步"，需要补下 `mouse_charliecatling`（本轮下载失败）。
3. **洞口**：`stump_callum_arb` 的腔体偏窄，**要么放大改形，要么只借它的树皮质感自建洞口**。
4. **围栏**：`wall_stefan_wr` 直接可用（模块化 + 2000 面）。
5. **巨石**：CC0 但要减面 + 缩到 1.2 m（12.7 m → 0.09×）。
