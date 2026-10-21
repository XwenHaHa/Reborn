# ART02：模型质量专项——猫 CAT_BODY_001 深度重做（试点）

**状态**：done（2026-10-21，本机系统时钟）——**不是正式美术 approved**，见 §7「边界」。
**触发**：负责人 `/modeling2.md`（"第一阶段的建模效果仍然不理想，暂停批量建模，先解决质量问题"）。
**与总计划的关系**：ART02 是美术流水线任务，不占 T001～T063 编号，不改玩法顺序。
**只换一个模型**：`modeling2.md` §三 明确"只能选择一个代表性模型作为试点"，
试点通过验收前**不替换其他模型**（鼠仍是胶囊占位）。

## 1. 诊断（为什么选猫，详见 `Docs/Evidence/ART02.md` §1）

| 事实 | 证据 |
|---|---|
| 全项目**没有**动物模型：猫/鼠的"模型"只是 `AnimalBody/BodyMesh` 上的一个 `CapsuleMesh`（`radius=0.16 / height=0.48`，单一 albedo，无耳/四肢/尾/脸） | `scenes/characters/animal_body.tscn`；`tests/run_t009_cat_movement.gd:158` 断言"网格高度 = 胶囊高度" |
| 游戏内同一机位判读（鼠玩家的第一人称，猫在 1.58 m）：「像一个光滑的胶囊/蛋」「完全看不出是猫」「逻辑与视觉完全脱节」 | `Art/Probes/art02_ingame_before.png` + `vision.js` |
| 唯一已建模资产是草丛（ART01），缺陷是"面片感/塑料感/形态重复"，但**画面不影响"这是什么生物"的识别** | `Art/Probes/art01_preview_corner45_v4.png` 判读 |
| 猫是鼠线的追捕者、也是猫线的玩家本体 → 出现频率与画面占比最高 | `Docs/Evidence/T027.md`、`T028.md` |

**结论**：最影响观感的是"动物根本没有模型"。选 **猫** 做唯一试点。

## 2. 建模方案与理由（不是"加面数/加细节"）

| 旧方案（v0 = 胶囊） | 新方案（CAT_BODY_001） | 为什么 |
|---|---|---|
| 一个 `CapsuleMesh` 基元 | **骨架线 → 变截面放样**：躯干/颈/头/四肢/尾都是沿解剖轴线的连续截面（胸腔深 0.080、腰细 0.042、髋 0.062；前肢 4 段、后肢 5 段关节角） | 轮廓由**结构**决定，不是由基元拼接决定 |
| 无过渡 | **Voxel Remesh 焊接**（0.0042 m）→ Smooth ×8 → 抽面到 8200 → 轻修 ×2 → 噪声位移 | 接缝是网格级连续过渡 + 毛发起伏，不是"两个圆柱插在一起" |
| 单色 albedo（塑料感） | **程序化配色烘焙成 2048² albedo**：背部深褐/体侧黄褐/腹部米白/虎斑暗纹/吻部浅色/耳尖渐变 | 塑料感的根因是"没有颜色变化与图案" |
| 没有五官 | **remesh 之后再贴面部件**：眼球（琥珀虹膜 + 近黑瞳孔，用"距眼心距离"在材质里画）、鼻头粉、耳内深色 | 五官在 remesh+平滑里会被吃掉，必须后贴 |
| 眼睛是独立球体 | 眼窝垫 + 眉弓 + 上眼睑棱（毛发槽，进 remesh） | 让眼睛"嵌在脸里"而不是"贴在表面" |

**为什么不用外部专业模型**：`modeling2.md` §二 允许"主动提出"，但下载/付费/第三方资产需要负责人授权
（`AGENTS.md`「需要确认」），本轮**未**下载任何外部资产；这是 §7 的首条建议。

## 3. 资产契约（**不要随手改**）

| 契约 | 值 | 谁在依赖 |
|---|---|---|
| 原点 | 四脚着地的地面中心（`min_z ≈ 0`，Godot `aabb.position.y = 0.0004`） | `AnimalBody._sync_visual()` 把视觉放到 `y = -capsule_half_height` |
| 朝向 | Blender 面朝 `+Y` → Godot 面朝 `-Z` | `animal_body.gd` 的 `move_forward` 走 -Z |
| 尺寸 | 0.1849 × 0.3894 × 0.6011 m（宽×高×长） | 高度必须 ≤ 胶囊总高 0.48（断言 `visual_inside_capsule_top`） |
| 三角形 | 9568（预算 ≤10000） | 场景预算 |
| 材质槽 | 2（`MAT_Cat_Fur` 贴图 + roughness 0.78 / `MAT_Cat_Detail` roughness 0.32） | 预算"动物 ≤2 槽" |
| 贴图 | 1 张 2048² albedo（烘焙；Godot 导入时抽成 `sm_cat_001_CAT_BODY_001_BaseColor.png`） | 预算"贴图 ≤2048" |
| 碰撞 | **没有**（`.glb` 只带视觉） | 碰撞永远是 `CollisionShape3D` 的胶囊 |
| 命名 | `CAT_BODY_001` / `SM_Cat_001.glb`（静态网格；**骨骼版仍按 `SK_Cat.glb`，属 P6**） | `Docs/BlenderPipeline.md` 命名约定（此处有意偏离 `SK_` 前缀，因本资产无骨骼） |

## 4. 路径与产物

```
Tools/Blender/art02_cat_001.py                    建模+UV+烘焙+渲染+导出（--version / --stage mesh|shot|all）
Art/Blender/Cat/CAT_BODY_001_v001…v008.blend      每轮返工存新版本（LFS）
Art/Exports/Cat/SM_Cat_001.glb                    交付产物（LFS，1,744,408 B，sha256 b5ae013b…）
Art/Exports/Cat/CAT_BODY_001_BaseColor.png        烘焙出的 albedo 源图（LFS）
Game/Reborn/assets/characters/cat/sm_cat_001.glb  Godot 侧资产（与导出逐字节相同）+ .import
Game/Reborn/resources/species/cat.tres            + visual_scene = ExtResource("3_vis")
Game/Reborn/scripts/data/species_config.gd        + @export visual_scene: PackedScene
Game/Reborn/scripts/characters/animal_body.gd     + _rebuild_visual() / _sync_visual() / VISUAL_MIN_SQUASH
Game/Reborn/tests/run_art02_cat.gd                验收套件（46 条）
Game/Reborn/tests/tool_capture_art02.gd           游戏内 before/after 捕获工具
Art/Probes/art02_v00*.png                         多角度渲染 + 线框 + 四向合影（每轮）
Art/Probes/art02_ingame_{before,after}.png        同机位游戏内对比（1.58 m，鼠玩家第一人称）
```

## 5. 用例（自动）

`Game/Reborn/tests/run_art02_cat.gd`（46 条）：
- A 资产层 23 条：加载/根名/网格名/AABB 三轴/贴地/朝向 `-Z`/面数/预算/表面数/两个材质名与 roughness/**两个槽都真的挂了贴图**/无碰撞。
- B 配置与接线层 19 条：`cat.tres` 指向资产、**鼠仍为 null**、胶囊网格与胶囊尺寸不变、胶囊网格隐藏、
  `Visual` 实例化自资产、脚底贴胶囊底面、站立/蹲姿/恢复的缩放与位置、捕获后隐藏。
- C 运行层 4 条：真实关卡 + 真实物理落地（0.3403 m）、视觉脚底贴地（0.100 m）、缩放不拉伸。

## 6. 失败恢复

| 症状 | 处置 |
|---|---|
| Blender 自检 `FAIL|...` | 退出码 1 且不写 `.glb`；按 PROBE 行改 `SPINE_RADII` / `HEAD_STATIONS` / 半径表 |
| 烘焙出全黑贴图 | 烘焙目标 `Image Texture` 节点**不能**连到 Base Color（会读到空贴图）；见脚本 `build_materials()` 注释 |
| `AttributeError: bpy_prop_collection['Color']` | `ShaderNodeTexImage` 的**输入**只有 `Vector`，颜色是**输出** `Color` |
| Godot 里眼睛/花纹丢失 | 贴图被导成外部文件，需 `--import` 后再断言 `albedo_texture`（`run_art02_cat.gd` A 层） |
| 蹲下后视觉穿出胶囊 | `_sync_visual()` 用 `crouch_height()/capsule_height()` 压缩，`VISUAL_MIN_SQUASH=0.55` 兜底 |
| 需要回退到胶囊 | `resources/species/cat.tres` 删掉 `visual_scene` 一行即可（`_rebuild_visual()` 会把胶囊网格显示回来） |

## 7. 边界（不算完成的事）

- **不是正式美术 approved**：按 `Docs/BlenderPipeline.md`，本资产登记为 `generated + 多角度视觉已判读 + 5 轮返工`。
- **没有骨骼/动画**：猫仍无 Idle/Walk/Run 姿态，蹲姿用**竖向压缩**近似；骨骼资产属 **P6 阶段门**，本任务没有越过。
- **鼠没换**：仍是胶囊（`modeling2.md` §五：试点通过验收前不批量替换）。
- **形体仍不专业**：视觉判读（4 轮）持续指出"耳朵仍偏长、四肢像棍、颈胸过渡生硬、表面像哑光塑料"。
  继续堆参数只会逼近程序化放样的上限 → 建议见 `Docs/Evidence/ART02.md` §7。
- **胶囊与四足形状不匹配**（0.32 直径的竖直胶囊 vs 0.60 m 长的四足）：视觉在鼻/尾两端**超出碰撞体**，
  属已知偏差，改胶囊会影响导航烘焙与玩法，需负责人决定。
- 未推送、未发布。
