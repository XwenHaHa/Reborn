# ART01：AI 建模工作流打通 + 第一项试点资产（草丛掩体）

**状态**：done（2026-10-21，本机系统时钟）——但**不是**正式美术验收，见文末"边界"。
**触发**：负责人 `/modeling.md`（"现在建模实在太烂了"）——要求先做环境检查与资产审计，
再按 Blender→glTF→Godot 的链路做**一个非关键、易替换的静态模型**试点，含至少一轮实际返工。

**注意编号**：ART01 是**美术流水线任务**，不属于总计划的 T001～T063 玩法任务编号；
它不改变 P0～P5 的实施顺序，也**没有**越过 **P6（正式角色/骨骼资产）阶段门**。

## 1. 目标与验收

| 项 | 内容 |
|---|---|
| 目标 | 用可复现、可审计的命令行链路（Blender 3.3.1 无头 CLI）产出一个真实资产，接进现有 Godot 关卡，且**不改玩法** |
| 试点资产 | `ENV_BUSH_001`：草丛掩体的视觉（替换 `CoverBush*Mesh` / 补上溪边缺失的视觉） |
| 验收层 | A 资产层（尺寸/面数/材质/双面）· B 关卡层（接入位置/无碰撞/Area3D 不变）· C 运行层（猫胶囊落进掩体不被推开） |
| 视觉验收 | 多角度截图 + `vision.js` 判读；**返工前后**同一机位对比 |
| 回归 | 既有 28 套断言套件全绿 + 新增 ART01 套件 |

## 2. 路径与产物（全部为新增，不覆盖既有正式资产）

```
Tools/Blender/art01_bush_001.py                 建模脚本（确定性 seed，无外部贴图）
Art/Blender/Environment/ENV_BUSH_001_v001.blend 第 1 轮可编辑源（LFS）
Art/Blender/Environment/ENV_BUSH_001_v002.blend 第 2 轮（修泥土墩/密度）
Art/Blender/Environment/ENV_BUSH_001_v003.blend 第 3 轮（修叶形）＝交付版
Art/Exports/Environment/SM_Bush_001.glb         glTF 2.0 交付产物（LFS，可复现）
Game/Reborn/assets/environment/sm_bush_001.glb  Godot 侧资产（与上者逐字节相同）
Game/Reborn/assets/environment/sm_bush_001.glb.import
Game/Reborn/tests/run_art01_bush.gd             验收套件（83 条）
Game/Reborn/tests/tool_capture_art01.gd         视觉捕获工具（预览台 / 关卡两模式）
```

改动（**唯一两处**）：`Game/Reborn/tests/tool_make_courtyard.gd`（生成器加 `_mk_cover_bush`）
与其产物 `Game/Reborn/scenes/maps/l_courtyard.tscn`（重新生成）。
**gameplay 脚本零改动**（`git diff --stat` 只含上面两个文件）。

## 3. 步骤（可复现）

1. 环境与资产审计 → `Docs/Evidence/ART01.md` §1～§3。
2. 建分支 `art/modeling-pipeline`；新目录 `Art/Staging`、`Art/Blender/Environment`、`Art/Exports/Environment`、`Game/Reborn/assets/environment`。
3. Blender 建模 → 自检（包络/面数/材质槽/贴地/泥土垫高度）→ 保存 `.blend` → **重开该文件**复核 → 导出 `.glb`。
4. 复制 `.glb` 进工程 → `--headless --import` → 用 `tests/tool_dump_scene_tree.gd` 读回真实结构（**不猜导入结构**）。
5. 视觉捕获（`-- art01-preview` 7 机位 / `-- art01-level` 3 机位）→ `vision.js` 判读 → 记录缺陷。
6. 返工 → 重新导出/导入/捕获 → 再次判读（共 3 轮，见 Evidence §6）。
7. 接入关卡：改**生成器**（不是手改 `.tscn`）→ 运行生成器 → **重烤导航**（`tool_make_courtyard_nav.gd`）。
8. 断言 + 全量回归 + 关卡前后对比图。

## 4. 数据/接口契约（不要随手改）

| 契约 | 值 | 谁在依赖 |
|---|---|---|
| 资产原点 | 地面中心（`AABB.position.y = 0`） | 生成器把实例放在 `GROUND_TOP`（0.10） |
| 水平包络 | ≤ 1.45 m 半径（实际 2.872 × 2.870 m） | 掩体数据体量是 3×3×3 |
| 高度 | ≤ 0.90 m（实际 0.88 m） | 旧网格盒 0.9 m；必须高于猫 0.48 m |
| 泥土垫顶面 | ≤ 0.12 m（实际 0.09 m） | **玩家躲在草丛里时相机不能进土** |
| 材质槽 | 2（`MAT_Bush_Leaf` / `MAT_Bush_Soil`） | 预算"静态环境 ≤2 槽" |
| 双面 | `cull_mode = CULL_DISABLED` | 玩家站在草丛**里面**看草叶 |
| 三角形 | 2040（预算 ≤3000） | 场景预算 |
| 碰撞 | **没有**（视觉节点不带任何 CollisionShape3D/CollisionObject3D） | 掩护逻辑只认 `cover_volumes` 的 Area3D |
| 分组 | **不进** `nav_source_courtyard` | 否则会改导航面 |

## 5. 用例（自动）

`Game/Reborn/tests/run_art01_bush.gd`（83 条）：
- A 资产层 32 条：加载/根名/网格名/AABB 三轴/贴地/面数/预算/表面数/两套材质名 + sRGB 颜色 + 双面 + 粗糙度/无碰撞。
- B 关卡层 39 条：4 处 `cover_volumes`（含溪边）、`visibility_factor=0.4`、BoxShape 3×3×3、每处视觉是 glb 实例、贴地、坐标、无碰撞、不在导航组。
- C 运行层 12 条：猫胶囊（0.16/0.48）从 0.70 m 落到掩体中心，应停在 **0.3401 m**（期望 0.34±0.03）且水平位移 ≤0.05 m。

## 6. 失败恢复

| 症状 | 处置 |
|---|---|
| Blender 自检 `FAIL|...` | 退出码 1、`.glb` 未写；按 PROBE 行的具体判据改脚本（本次抓到过包络超限、泥土垫过高） |
| Godot 导入后结构不符 | 先跑 `tool_dump_scene_tree.gd -- res://assets/environment/sm_bush_001.glb`，按实测结构改断言 |
| 关卡重新生成后导航消失 | **必须**再跑 `tests/tool_make_courtyard_nav.gd`（本次踩到：`NavigationMesh` ext_resource 被覆盖掉） |
| 视觉判读说"看不见/黑" | 先查相机是否在几何体内部、光源是否在；用 `PIX|` 统计量做客观对照，不猜 |
| 需要回退 | 分支 `art/modeling-pipeline` 上 `git checkout -- Game/Reborn/scenes/maps/l_courtyard.tscn` 即回到旧盒子视觉 |

## 7. 边界（不算完成的事）

- 角色/骨骼资产（猫、鼠）仍属 **P6 阶段门**，本任务**没有**碰。
- 关卡仍是灰盒：地面/围栏/树根屏障/庇护棚/补给点标记都还是 BoxMesh。
- 这不是正式美术通过：`Docs/BlenderPipeline.md` 要求"模型轮廓与动画视觉未验证时可以登记 `generated-not-validated`，不得 approved"。当前状态 = **generated + 多角度视觉已判读 + 返工 3 轮**，仍等负责人决定它是否作为正式基线。
- 未推送、未发布。
