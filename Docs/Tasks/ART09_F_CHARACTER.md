# ART09-F 任务规格：角色肖像与四态展示

状态：**F1 done / F2、F3 pending**（2026-10-29）
上位计划：`Docs/Tasks/ART09_BOARD_PARITY.md` §3 阶段 F

## 目标

把「展板里动物是照片级肖像 + 四态走态条」这件事拆成三块，能做的先做掉，需要授权的留在门口：

| 子项 | 内容 | 依赖 | 状态 |
|---|---|---|---|
| **F1** | 物种**肖像图**（引擎渲染）+ 接进菜单卡/物种页/大卡背景 | 无（零授权） | **done** |
| **F2** | 评估 `sm_cat_004.glb`（ART-V3.2-3 步态候选）是否替换 `sm_cat_002` | 无 | pending |
| **F3** | 四态展示条（站立/起步/行走/奔跑，猫+鼠，同机位同侧视角拼条） | 无 | pending |
| 授权门 | 猫扑击 / 鼠逃跑动作；兔/狐/鸟模型 | 需负责人授权 | blocked |

## F1 实现（本次落地）

- 新增 `Game/Reborn/tests/tool_render_board_portraits.gd`（**非 headless**）：
  每个 `resources/species/*.tres` 渲一张 512×512 肖像 → `res://assets/ui/portraits/portrait_<id>.png`。
  - 用 `AnimalBody` 承载（它负责视觉网格与 Idle 播放，并隐藏胶囊占位 `BodyMesh`）；
  - 背景用同一张 CC0 森林 HDRI 天空球；三点光（暖主光 / 冷补光 / 轮廓光）；
  - **取景闭环自校正**：透明底渲一遍 → 用 alpha `get_used_rect()` 量「填充率 + 偏心」→ 修距离/平移相机 → 最多 5 轮，
    收敛到填充率 0.62±0.05、偏心 ≤4%。不依赖胶囊尺寸、也不猜骨骼网格 AABB。
- `SpeciesConfig` 新增 `@export var display_portrait: Texture2D`；`cat.tres` / `mouse.tres` 各自指向自己的肖像。
- 菜单：右栏卡片与物种页缩略图槽**有肖像就用 `TextureRect`（`Portrait_<id>`）**，没有则回退实时 3D 预览（旧配置不坏）。
- 物种页大卡新增 `CardPortrait` 背景层（`modulate.a = 0.28`，压暗当纹理，不抢文字）。
- 新增契约 `Game/Reborn/tests/run_art09_portrait_contract.gd`（24 条）。

## 验收（F1）

- `run_art09_portrait_contract.gd` 24/24；`run_art09_menu_contract` 42/42、`run_art09_species_layout` 59/59、
  `run_art08_board_contract` 9/9、`run_art09_tokens` 15/15 全不变。
- 非 headless `tool_capture_board_visual.gd -- board` 四图 `save_result=OK`（含肖像的菜单与物种页）。
- 视觉：肖像里的动物必须完整入画（不切头切脚）、填充率约 0.62、背景是森林而不是纯色。

## 后续（F2 / F3）

- F2：先把 `cat.tres` 的 `visual_scene` 临时改到 `sm_cat_004.glb`，跑 `run_art02_cat`（72 条）+ `tool_cat_gait_eval`，
  与 002 同机位截图对比步态；通过才正式切换，否则保留 002 并记录 `NOT-ACCEPTED`。
- F3：新增 `tool_capture_art09_gait.gd`：固定相机（侧视、`fov` 固定），每个物种渲 4 个状态帧
  （Idle / Walk 起始 / Walk / Run），横向拼成 `cat_row.png`、`mouse_row.png`。
- 两者都不需要新授权；兔/狐/鸟仍只能用 `?` 占位（无模型 = 不伪造）。

## 回退

删除 `assets/ui/portraits/`、`tool_render_board_portraits.gd`、`run_art09_portrait_contract.gd`，
把 `cat.tres`/`mouse.tres` 的 `display_portrait` 行去掉、`load_steps` 改回 4，并把 `main_menu.gd` 的
`_make_portrait()` 与 `CardPortrait` 段回退即可 —— 菜单会自动回到实时 3D 缩略图。
