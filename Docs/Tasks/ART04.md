# ART04 主菜单 / 物种选择 / HUD 条 / 动画过渡（视觉与动画专项整改 V1 的阶段 1 + 3）

> 依据：`配套要求.md`（§1 可扩展定位、§2 主菜单与物种选择、§3 动画、§5 先审计再改 + 保留现有系统）、
> `《轮生 Reborn》视觉与动画专项整改任务 V1.md`（§二 保护现有项目、§三 动画、§四 任务 B 开场、§五 任务 C 界面规范、§六 分阶段交付）。
> 状态与证据：`Docs/Evidence/ART04.md`。

## 1. 目标（只说本任务要做的）

1. **开场不再是"纯色背景 + 一行文字"**：选物种时必须看到真实运行的 3D 生态场景 + 猫鼠模型 + 正式排版。
2. **物种选择是数据驱动的卡片列表**：新增物种只改 `resources/species/*.tres`，**不重写 UI**。
3. **HUD 从纯文字升级为四项指标条**（生命 / 饥饿 / 水分 / 体力），保留原有文本通道（断言与 `hud_text()` 不变）。
4. **Idle↔Walk↔Run 交叉淡入**，消除状态硬切造成的"动作生硬"。
5. **不动玩法**：生存系统、移动控制、物种切换、重生与生命周期状态机全部保留，行为断言必须继续全绿。

## 2. 目标路径

| 角色 | 路径 |
|---|---|
| 新界面（菜单/物种选择/设置） | `Game/Reborn/scripts/ui/main_menu.gd`（`class_name MainMenu`，运行期构建，**不是** `CanvasLayer`） |
| 装配与菜单相机/展示模型 | `Game/Reborn/scripts/core/main_entry.gd` |
| HUD 指标条 | `Game/Reborn/scripts/ui/hud.gd`（`Margin/VBox` 内新增 `VitalsBars`，原三个 `Label` 保留） |
| 动画交叉淡入 | `Game/Reborn/scripts/characters/animal_body.gd` |
| 物种显示文案字段 | `Game/Reborn/scripts/data/species_config.gd`（`Display` 组）+ `resources/species/{cat,mouse}.tres` |
| 取证工具 | `Game/Reborn/tests/tool_capture_art04.gd`（`-- art04`，非 headless） |

## 3. 数据与事件

- **只读数据**：物种卡片的名字/定位语/备注/数值全部来自 `SpeciesConfig`（新增 `display_name` / `display_tagline` / `display_note` + `display_title()`；
  数值行由 `walk_speed` / `sprint_speed` / `vision_range` / `max_stamina` 推导）。代码里**不写物种名**、不写死物种数量。
- **新增信号（菜单 → 入口，单向）**：`MainMenu.species_committed(species_id)`、`setting_changed(key, value)`、`quit_requested`。
- **不改的状态机**：选物种仍走 `MainEntry.select_species()` → `LifeCycle.begin_spawn()`；菜单只负责"选谁"和"确认"。
- **设置项**：`sensitivity`（灵敏度倍数）/ `fov`（视野）；出生时由 `MainEntry._apply_settings_to()` 落到玩家身体上。
  **只作用于本次运行**，持久化属后续存档任务。

## 4. 步骤

1. 审计（阶段 1）：真实取景看现状，列文件/根因/资源缺口 → `Docs/Evidence/ART04.md` §2。
2. `SpeciesConfig` 加显示字段 + 两个 `.tres` 补文案（可回退：字段留空即回退到 `species_id`）。
3. 新增 `MainMenu`（两页 + 卡片 + 每物种一个 `SubViewport` 预览 + 设置面板）。
4. `MainEntry`：运行期建菜单与菜单相机（含只用于菜单的补光）、展示模型；选物种时显示、出生时隐藏并释放。
5. `hud.gd`：`VitalsBars`（4 行：名字 + 条 + 数值），原 `VitalLabel` 隐藏但继续更新文本。
6. `animal_body.gd`：`play(want, blend)` 交叉淡入（0.18 s；走↔跑 0.10 s）。
7. 取证：`tool_capture_art04.gd -- art04` → 6 张 + 2 张改前对照 → `Art/Probes/art04_*.png`。
8. 回归：见 §5，逐套件记录 `SUMMARY` 与 `SCRIPT ERROR` 条数。

## 5. 用例（验收）

| 用例 | 判据 |
|---|---|
| U1 选物种画面 | 有 3D 场景 + 猫鼠模型 + 标题/按钮/卡片；无调试文字、无 `— / —` 占位 |
| U2 数据驱动 | 卡片文案与数值来自 `.tres`；改 `display_name` 后画面跟着变（不碰 UI 代码） |
| U3 选中态 | 点卡片 / 按 `1`、`2` 都切换选中；选中的卡片有琥珀色左边框与高亮名字 |
| U4 进入世界 | `开始游戏`/`进入世界`/`Enter` 都出生；出生后菜单隐藏、HUD 出现、相机交给玩家 |
| U5 HUD | 四条按数值着色；`饥饿 18 / 水分 12` 时条形明显短 + 「饥饿 + 缺水」警告 |
| U6 生命周期不回退 | 死亡 → 结算 → 回菜单（显示「上一世：…」）→ 再选物种可出生 |
| U7 动画 | Idle↔Walk↔Run 交叉淡入；速度仍驱动 `speed_scale`（不因淡入改变位移） |
| U8 回归 | T002/T005/T006/T007/T008/T009/T010/T011/T012/T013×2/T014…T030 与 ART01/02/03 套件全绿 |

**失败恢复**：`cat.tres` / `mouse.tres` 删掉 `display_*` 行即回到英文 ID；`MainEntry` 不建菜单就会退回 T030 的"状态文字"界面（`MainMenu` 全是新增文件，不删生产逻辑）。

## 6. 明确不做（本轮边界）

- 不做第三人称（第一人称相机与 `camera_offset_z` 竖直语义属 T009 决策 D1，改动需单独评审）。
- 不做主菜单专用新场景/新关卡：菜单**复用** `l_courtyard.tscn` 的真实几何与光照（`配套要求.md` §2 最后一条）。
- 不做设置持久化、不做正式解锁链（T031）、不做结算页美术（T032）。
