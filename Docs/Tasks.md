# 任务状态与执行入口

截至 **2026-10-13（引擎切换 Godot 4 后）**：

- **引擎已由 UE5 改为 Godot 4.7.2 + GDScript**（负责人决定）。技术层文档已重写为 Godot 版。
- **T001 = done（Godot 版）**：环境与引擎能力门通过。
- **T002 = done**（视觉部分 awaiting-review）：正式工程建立，无头断言 **18/18 通过**，10 次运行（5 冷启动 + 5 热运行）结果一致。
- **T003 = done**：LFS 生效；**从零克隆的工程可被引擎实际运行**（18/18 通过）。
- **T004 = 部分 done**：Godot 无头闭环实测通过；Blender 资产侧未开始。
- **T005 = done**（静态资产往返）、**T006 = done**（骨骼往返）、**T007 = done**（Windows 导出），均在 2026-10-13。
- T008～T063 全部 pending。**游戏测试除 E01 部分外全部 NOT-RUN，无 PASS 的游戏玩法用例。**

**能力门现状**：Godot 无头运行、`--check-only`、物理体创建与回读**已通过**；
**Windows 导出已解锁并通过**（T007 done）；**Blender 无头 CLI + glTF 资产往返已通过**（T005 done）；
视觉分析可用，已用于 T002/T005/T007 的视觉验收。

**P0 阶段门**：E01 部分通过；**打包通过**（T007）；**E02（静态资产往返）通过**（T005）；**E03（骨骼往返）通过**（T006）→
**P0 完成**（E01 的视觉部分已由 Visual-Verification 补验）。

## 状态规则

pending 未开始；in-progress 正在执行；blocked 有明确前置缺口；awaiting-review 产物已生成但必需验收未做；done 必需验收和证据全部通过。任一任务状态改变，在下表新增覆盖记录，**不删除原历史**。总计划是任务标题和依赖的基准；后续规格不能偷偷扩大产品范围。

## 当前覆盖记录

| 任务 | 状态 | 已有证据 | 下一步 |
|---|---|---|---|
| T001 | **done（Godot 版）** | `Docs/Evidence/T001.md`（环境/硬件/UE 定位）；`Docs/Evidence/T004.md`（Godot 能力） | 已完成 |
| T002 | **done** | `Docs/Evidence/T002.md`；`Visual-Verification.md` | 无头断言 18/18 ×3；**视觉已补验通过**（发现并修复场景无光源缺陷） |
| T003 | **done** | `Docs/Evidence/T003.md`；提交 `b7767ca`、`611a55b` | LFS 生效 + 从零克隆可运行工程（18/18 通过） |
| T004 | **done**（路线决策） | `Docs/Evidence/T004.md`、`BlenderPipeline.md` | **路线已定：用 Blender 自带无头 CLI，不用 MCP**；资产侧并入 T005 |
| 台阶探针 | **done**（T009/T010 前置） | `Docs/Evidence/T009-probe.md`；`tests/probe_step_height.gd` | 6/6 通过；算法已组件化（`scripts/characters/step_climb.gd`）；T009 期间修正两处判据，见 `Docs/Evidence/T009.md` §5 |
| T005 | **done** | `Docs/Evidence/T005.md`；`Docs/Tasks/T005.md`；`Game/Reborn/tests/run_t005_asset.gd`；`Art/Exports/Tests/SM_ProbeCube.glb` | 1 m 往返实测 1.0000 m（50/50 ×3、包内 50/50）；轴向由实测改正文档；运行中碰撞高度差 1.0001 m |
| T006 | **done** | `Docs/Evidence/T006.md`；`Docs/Tasks/T006.md`；`Game/Reborn/tests/run_t006_rig.gd`；`Art/Exports/Tests/SK_RigProbe.glb` | 骨骼往返 65/65 ×3 + 包内 65/65；长度 1.0 s、loop_mode=LOOP_LINEAR、首末闭合 0.000；无根运动/无根骨缩放 |
| T007 | **done**（真实按键 awaiting-review） | `Docs/Evidence/T007.md`；`Builds/P0-Win64/` | 导出/独立运行/干净退出/重启/视觉均通过 |
| T008 | **done** | `Docs/Evidence/T008.md`；`Docs/Tasks/T008.md`；`scripts/data/species_config.gd`；`resources/species/{cat,mouse}.tres`；`scripts/characters/animal_body.gd` + `scenes/characters/animal_body.tscn`；`tests/run_t008_species.gd` | 台阶组件化 + 配置逐字段对照 `Parameters.md`；**配置驱动的物理实测**：猫 12 cm 上/20 cm 挡、鼠 3 cm 上/12 cm 挡；**114/114** ×2、包内 103/103（T009 补了蹲姿/相机轴向断言） |
| T009 | **done（2026-10-13）** | `Docs/Evidence/T009.md`；`Docs/Tasks/T009.md`；`tests/run_t009_cat_movement.gd`；`scenes/maps/l_move_fixtures.tscn`（+`tests/tool_make_move_fixtures.gd`）；`Art/Probes/t009_*.png` | 猫移动：行走/奔跑/潜伏/跳跃 + 相机；斜坡/低顶/落地/相机穿墙全过；**81/81** ×3 + 包内 81/81；lab 玩家已换成正式猫（T002/T005/T006/T007/T008 回归全绿）；过程中修掉 `step_climb` 两处真实判据缺陷 |
| T010 | **done（2026-10-13）** | `Docs/Evidence/T010.md`；`Docs/Tasks/T010.md`；`tests/run_t010_mouse_movement.gd`；`scenes/maps/l_move_fixtures.tscn`（新增鼠洞 + 鼠低顶）；`Art/Probes/t010_*.png` | 鼠移动与通道尺度：**站立**过 24×30 cm 洞、猫（站/蹲）都过不去、禁高跳（`can_jump=false`）、0.15 m 低顶下不扩碰撞；**95/95** ×3 + 包内 95/95；**gameplay 代码零改动**（差异全在 `mouse.tres`） |
| T011 | **done（2026-10-13）** | `Docs/Evidence/T011.md`；`Docs/Tasks/T011.md`；`tests/tool_make_courtyard.gd` + `scenes/maps/l_courtyard.tscn`；`tests/run_t011_greybox.gd`；`Art/Probes/t011_*.png` | 生态灰盒：四区域铺满 72×56 可玩矩形、§8.2 五条结构全部落地；**210/210** ×3 + 包内 210/210；**gameplay 代码零改动**；猫跳越 0.50 屏障、鼠穿 0.24×0.30 洞、四条补给走廊 0 阻挡 |
| T012 | **done（2026-10-13）** | `Docs/Evidence/T012.md`；`Docs/Tasks/T012.md`；`tests/tool_make_courtyard_nav.gd` + `resources/nav/l_courtyard_{mouse,cat}.tres`；`tests/run_t012_navigation.gd` | 导航可行性：**分物种双图 + 分层**（鼠 layer1 r=0.07 / 猫 layer2 r=0.17，cell 0.03）；鼠层穿 0.24 洞 9.00 m、穿溪缝 12.00 m；猫层同一对端点 35.44 m 且**不穿洞**、洞里无导航面；真实胶囊行走（鼠进洞 236 帧 0 重叠、猫 900 帧 0 帧进入洞口走廊）；**79/79** ×3 + 包内 79/79；**视觉证据 NOT-RUN**（运行时导航调试不可见） |
| T013 | **done（2026-10-15）** | `Docs/Evidence/T013.md`；`Docs/Tasks/T013.md`；`scenes/debug/debug_entry.tscn` + `scripts/debug/debug_entry.gd`；`tests/run_t013_{debug_entry,movement_regression}.gd`；`tests/tool_capture_render.gd -- t013`；`Art/Probes/t013_*.png` | 调试入口（切猫/鼠 + 碰撞线框 + 导航路径 + 调试 HUD + `PARAMS|`/`MOV|` 记录）；**遗留项 ① 修好**：台阶抬升帧水平位移 = 该帧正常位移（0.0300 = 0.0300，修复前 ≥0.2 m）；遗留项 ② 只记录并可视化（猫层 34.77 m 绕行不穿洞 / 鼠层 5.00 m 直穿洞口）；**159/159 + 73/73** ×3 + 包内同；全量回归（T002→T012）全绿；包 388,320 B；视觉 6 图（引擎碰撞开关实测**不可见** → 自绘线框兜底） |
| T014 | **done（2026-10-15）** | `Docs/Evidence/T014.md`；`Docs/Tasks/T014.md`；`scripts/data/survival_state.gd` + `scripts/systems/survival_controller.gd`；`tests/run_t014_survival.gd` | 生存状态与统一时间入口：**只吃世界时间**（`tick_to()`，不累加 delta）；饥渴按参数速率、体力 `RegenDelay` 后恢复；**暂停两条路径实测不消耗**；**30/60/144 Hz 跑 60 s 消耗完全一致（spread = 0）**；**106/106** ×3 + 包内 106/106；全量回归全绿；包 411,140 B |
| T015 | **done（2026-10-15）** | `Docs/Evidence/T015.md`；`Docs/Tasks/T015.md`；`tests/run_t015_costs.gd`；`species_config.gd` 六个新参数 + `survival_controller.gd` 警告/危机 + `animal_body.gd` 双门控与跌落 | 消耗、警告与基础伤害：冲刺 15.01/35.02 per 1 s、**双门控**（≥5 开始 / 耗尽转行走）、`RegenDelay` 恢复；`≤25` 预警（不扣血）、归零各扣 1/s（两项 2/s）；跌落 ≤7 m/s 无伤、超过 (v−7)×10、上限 100；**93/93** ×3 + 包内 93/93；全量回归全绿；包 433,020 B |
| T016 | **done（2026-10-15）** | `Docs/Evidence/T016.md`；`Docs/Tasks/T016.md`；`scripts/core/interactable.gd` + `scripts/characters/interaction.gd`；`tests/run_t016_interaction.gd` | 交互检测与动作接口：鸭子类型三方法（`has_method()`，**不用类型转换**）、`interactable` 层 `intersect_shape`（**不动身体 mask**）、距离与遮挡（猫 1.00 / 鼠 0.45，可 `range_override`；遮挡只认 `world_static`）、排序确定性（priority → 距离 → ID）且**只暴露一个目标**、`duration` 走世界时间（暂停冻结）、**同事务 ID 幂等**；**118/118** ×3 + 包内 118/118；全量回归全绿；包 470,000 B |
| T017 | **done（2026-10-15）** | `Docs/Evidence/T017.md`；`Docs/Tasks/T017.md`；`scripts/world/resource_point.gd` + `scenes/world/resource_point.tscn`；`tests/run_t017_food_water.gd` | 食物、饮水与可取消交互：食物 1.5 s / Unit → Hunger 35、水 2 s → Thirst 40（**无限**）；**按物种判定食物类型**（猫肉 / 鼠种子，否则 `food_type`）；成功一次结算（扣 Unit + **夹紧**恢复）、取消与**受伤中断无收益**、耗尽 `empty`；**提交前复检**（禁用 / 超范围都拦且不扣不发）；固定食物容量 3、每 180 s 恢复 1 Unit（**跨多周期一次结算**）、300 s 失效机制；**128/128** ×3 + 包内 128/128；全量回归 15 套件全绿；包 499,624 B |
| T018 | **done（2026-10-15）** | `Docs/Evidence/T018.md`；`Docs/Tasks/T018.md`；`scripts/ui/hud.gd` + `scenes/ui/hud.tscn`；`tests/run_t018_hud.gd`；`tool_capture_render.gd -- t018`；`Art/Probes/t018_hud_*.png` | 最小 HUD：状态（四项指标 `x / 上限`）、低值警告（`饥饿` / `缺水` / `饥饿 + 缺水`，≤25 触发）、交互提示（**进食/饮水** + 目标 ID + 进度百分比，无目标隐藏）；**信号驱动**（`_process` 只读交互进度）；**只观察不改状态**（同帧快照一致、`commit_count()=0`）；**调试数值不混入**（12 条禁词逐条断言）；**73/73** ×3 + 包内 73/73；全量回归 16 套件全绿；包 523,148 B；**视觉 3 图已判读**（HUD 左下角可见、警告橙黄色、动作提示正确） |
| T019 | **done（2026-10-15）** | `Docs/Evidence/T019.md`；`Docs/Tasks/T019.md`；`scripts/ai/animal_ai.gd` + `scripts/ai/mouse_ai.gd`；`species_config.gd`（`ai_script`）+ `mouse.tres`；`animal_body.gd`（`ai_enabled` + `_sync_ai`）；`tests/run_t019_mouse_ai.gd` | 鼠 NPC 觅食与警戒：`EXPLORE ↔ FORAGE ↔ ALERT ↔ WAIT`；走去最近可用食物点（实测 **5.22 m / 4.75 s**、到达 0.389 m ≤ 0.45）→ 走**同一套**交互进食（units 3→2、Hunger +35）；警戒 **0.3 s** 上限（期间停手停脚、取消交互且**无收益**、可重复注入但不无限延长）；MoveTo 失败 **1 s / 最多 3 次 / 进 WAIT 后不永久阻塞**（实测 4 次失败、3 次重选、`no_progress`）；状态与原因可查看（`ai_report()` 16 字段 + HUD `ai:` + `MOV|ai_state=`）；**72/72** ×3 + 包内 72/72；全量回归 17 套件全绿；包 552,052 B |
| T020 | **done（2026-10-16）** | `Docs/Evidence/T020.md`；`Docs/Tasks/T020.md`；`scripts/systems/perception.gd`；`scripts/ai/animal_ai.gd` + `scripts/ai/mouse_ai.gd`；`scripts/characters/animal_body.gd`（感知组件 + 脚步噪声）；`species_config.gd`（`Noise` 组）+ `mouse.tres`/`cat.tres`；`world_director.gd`（`noise_emitted` 总线）；`scenes/maps/l_courtyard.tscn`（`HideSpot_RootHole`）；`debug_entry.gd`（`MOV|seen/heard/noise_age/steps/hide`）；`tests/run_t020_perception.gd`；`tool_capture_render.gd -- t020` | 老鼠视觉、听觉与逃跑：`Perception` 组件挂在 `AnimalBody`（**只观察**，做决定仍走既有 `alert_for()`）；视锥 75° / 6.5 m + `world_static` 遮挡 + 草丛 `visibility_factor` 0.4（重叠取最小），**近距 0.80 m 内豁免草丛与遮挡但仍受视锥限制**；听觉 = `HearingRange × Loudness`（跑 10 / 走 5 / 蹲 2 m），**不吃墙不吃草丛**；**噪声只有发生位置**（快照不跟随声源：声源走开 3.66 m 后快照仍不动）；脚步按速度反比 0.5/0.2/1.0 s、**每事件一次**（实测 121 帧 = 4 次）；`ALERT（0.3 s）→ FLEE → HIDDEN → EXPLORE`、180 cm 内立即逃、**可达鼠洞优先**（到达 0.267 m ≤ 0.30）、洞不可达转草丛掩体、都没有则 `flee_timeout` **3 s 回退**（实测 2.90 s，**不位移、不假装躲藏**）、HIDDEN 撑满 4 s 才外出；**164/164** ×3 + 包内 164/164；全量回归 **18 套件 1720 条全绿**；包 **605,740 B**；视觉 3 图已判读；**顺带修好 T019 遗留缺陷**（导航层反查读错 meta 键 → 猫曾误用鼠导航面） |
| T021 | **done（2026-10-17）** | `Docs/Evidence/T021.md`；`Docs/Tasks/T021.md`；`scripts/systems/capture.gd`（新组件 `CaptureSettlement`）；`scripts/characters/animal_body.gd`（`enum ACT` + 扑击状态机 + `mark_captured`）；`species_config.gd`（`Pounce` 组 + `FoodType` + `can_eat()`）+ `cat.tres`/`mouse.tres`；`world_director.gd`（捕获账本 + `capture_reported` + 真实 `world_time`）；`debug_entry.gd`（`MOV\|act/pounce/captures/blocked`）；`tests/run_t021_capture.gd`；`tool_capture_render.gd -- t021` | 猫扑击与捕获结算：140 cm / 0.25 s / 扣 25 / 恢复 0.6 s 全部从 `species_config` 读（鼠 `can_pounce=false`，**无捕获组件**）；启动门 8 种受阻原因（`species/airborne/dead/busy/stamina/recovering/pouncing`），**被拒不扣体力不计数**；扫掠用 `move_and_collide` 逐帧推进（单帧实测 0.0933 ≤ 0.0943，**不传送**），空地恰好走满 **1.4000 m**；**障碍优先于障碍后的猎物**（墙距猫 50 cm → `blocked=world`、位移 0.340 m = 0.50 − 0.16 胶囊半径、猎物未被结算、**体力不退还**）；命中后先查存活与账本，捕获一次即生成挂世界根的 `MEAT` 食物（容量 1、**300 s** 失效、命中点 0.000 m、鼠因食性被拒）且**不移除节点**（网格隐藏、层 0、出组、停物理，指标不回满）；**幂等**（二次结算 `invalid`、账本/食物账本恒 1）；4 只捕食者同帧**只结算 1 次**、先到者得、后到者全被拒；恢复期**吞掉跳跃**、再扑被拒（恢复窗口实测 0.5862 s ∈ 0.6 ±0.08），恢复后可再扑（二次扑击后体力 53.6，按「启动前体力 − 25」差值断言）；**279/279** ×3 + 包内 279/279；全量回归 **19 套件 1999 条全绿**；包 **653,876 B**；视觉 3 帧（扑击/撞墙/命中）已判读，并**修好取景工具的跨关卡污染**（lab 自带 `Player` 被误读为第二个胶囊） |
| T022～T063 | pending | 无 | 见 `轮生_Reborn_开发计划_v1.0.md` |

### T001 判定明细（Godot 版）

| 验收项 | 判定 |
|---|---|
| 读取路径与实际工具列表 | PASS |
| 只读检查版本、硬件与余量 | PASS |
| 定位引擎可执行文件与版本 | PASS（Godot 4.7.2；UE 未发现，已由负责人决策换引擎） |
| 最小场景操作 + 运行验证 | PASS（纯文本手写工程 → 无头运行 → 回读状态） |
| 建立工具能力表 | PASS |
| 不擅自更改技术路线 | PASS（换引擎是负责人决策，非 agent 擅自变更） |

### T002 / T003 判定明细

| 验收项 | 判定 | 证据 |
|---|---|---|
| T002 工程可被引擎加载运行 | PASS | `RESULT\|PASS`，退出码 0 |
| T002 无头断言 | PASS | 18/18，10 次运行（5 冷 + 5 热）一致 |
| T002 地面 1000×1000 cm | PASS | 读回 `BoxShape3D.size` = 10.0000 m |
| T002 出生点无碰撞重叠 | PASS | `intersect_shape` 实测 0 overlaps |
| T002 落地与停止 | PASS | `is_on_floor=true`，落点 y=0.3402（期望 0.34） |
| T002 视觉 | **awaiting-review** | vision 服务 403，未做画面判断 |
| T003 `.gitattributes` + LFS 生效 | PASS | 指针/实体/SHA256 三重验证 |
| T003 **恢复点** | PASS | 从零克隆后引擎实跑 18/18 通过 |

关联用例：**E01 部分 PASS**（工程可加载、脚本保留、无 `SCRIPT ERROR`、`--check-only` 退出码 0）；
E01 的视觉部分**已补验通过**；**E02 本次通过**（`Docs/Evidence/T005.md`）；**E03 已通过**（T006 骨骼往返 65/65）。

## 选择顺序
T001 / T002 / T003 / T005 / T006 / T007 / T008 / T009 / T010 / T011 / T012 / T013 / T014 / T015 / T016 / T017 / T018 / T019 / **T020 均已完成**；台阶、导航、调试入口、生存时间入口、交互接口、食物/饮水、正式 HUD、**鼠 NPC 状态机**与**感知（视觉 / 听觉 / 逃跑躲藏）**已落地。
（口径变化：T011/T012 是"游戏代码零改动、差异全在配置/关卡/导航数据"；**T013 起开始真的改游戏代码** —— `step_climb` 抬升修复、调试入口、`SurvivalState`/`SurvivalController`、`AnimalBody` 接入、`Interactable`/`InteractionDetector`/`ResourcePoint` 与动作事务。）
**P0 阶段门完成**；**P1 进行中**（T008～T020 连续完成 → 下一步 **T021 猫扑击与捕获结算**）。

下一步可执行（按建议优先级）：
1. **T021（猫扑击与捕获结算）**（4～8h，前置 T015、T020）：扫掠阻止穿墙，成功/失败均有体力代价；捕获一次生成可食对象。
   顺带带上待定：**猫跨 0.50 屏障是否加 `NavigationLink3D`**（T013 §9）、**跳跃是否消耗体力**（T015 §9）、
   **交互是否要朝向/视锥限制**（T016/T017 §9）、**食物/水恢复值是否按物种分列**（T017 §9）、**"调参页"是否要做成可交互面板**（T018 §8）。
   **交互用"按住开始/松开取消"是否最终设计、距离是否要含竖直差**（T016 §7）。
   T020 §8 新待定：**感知新增 4 个实现默认值**（`footstep_interval_base` 0.5 s、`flee_timeout` 3.0 s、`reach_tolerance` 0.5 m、`hide_arrive_radius` 0.30 m）、**近距豁免是否受视锥限制**、**威胁判据是否加“正在扑击 / 已发现我”**、**草丛是否要改成物理体积**、**关卡鼠洞是否只留 1 个**。
2. ~~T008 / T009 / T010 / T011 / T012~~ **已完成**；正式角色/骨骼资产仍属 **P6** 阶段门，不得提前。

**做角色资产时必须遵守 T005/T006 实测的两条约定**：
① 在 Blender 里**面朝 `+Y`**（导入 Godot 后才朝 `-Z` 前方）；
② 骨骼动画**原地、无根运动**；导入会让极值削减约 1–2%（见 T006 证据 §3.2）。

**T006 已解除，不再阻塞**：骨骼链往返已被实测证明，正式骨骼资产可以开始（但仍属 P6，需按阶段门排期）。
T028 若只有自测，则 awaiting-review，不冒充真实玩家验证。

P4 前先阅读 TechnicalDesign 数据契约，T036 是契约实现检查与持久化准备，不是首次想数据结构。

## 当前阻塞与最小解除条件

| 阻塞 | 影响 | 最小解除条件 |
|---|---|---|
| ~~Godot 导出模板未安装~~ | ~~T007~~ | **已解除** |
| ~~技术层文档仍是 UE5 版~~ | ~~T002 起~~ | **已解除** |
| ~~台阶 MaxStepHeight 能力未达成~~ | ~~T009/T010~~ | **已解除**（6/6 通过） |
| ~~vision 服务 403~~ | ~~全部视觉验收~~ | **已解除**（换用负责人提供的网关并验证；T002/T007 视觉已补验通过） |
| ~~Blender 资产路线未定~~ | ~~T005/T006~~ | **已解除**（负责人决定：用 Blender 3.3.1 自带无头 CLI） |
| 真实按键输入无安全自动化手段 | T007 的"输入"项、P7 试玩 | 受审查的输入自动化工具（**需授权**），或真人操作录像。**禁止盲发按键**；合成输入已覆盖 |
| C: 仅剩 13.7 GB | 产物落盘 | 确认工程与产物落 D:/E: |
| Godot 渲染器（T600 4GB 能否跑 Forward+） | P1 起的画质与性能 | 渲染器**已确认可用**（T009 捕获工具实测 `renderer=forward_plus`、1280×720 正常出图）；**帧率仍未测**，不宣称性能基线 |
| 相机轴语义 D1 / 蹲姿高度 D2 待确认 | T010 起沿用同一套实现 | 负责人确认即可（改回只需改一行实现 + 1 条断言，见 `Docs/Evidence/T009.md` §4/§9） |
| 台阶抬升会前移 0.2 m（单级"跳一下"的手感） | 关卡手感与窄台阶（T011/T013） | 改成"只抬起 y、由 `move_and_slide()` 推进"，并重跑 T008/T009 断言 |

> ## ⚠ 一条重要教训（2026-10-13）
>
> **数值断言全过 ≠ 画面正确。** T002 的 18 条断言长期全绿，但场景**完全没有光源、
> 没有环境、相机未激活**，导出程序窗口是一片深色空白。视觉检查一接入就发现了。
> 今后任何"画面正确"的结论都必须有视觉证据，见 `Docs/Evidence/Visual-Verification.md`。

## 后续单任务规格格式

路径 `Docs/Tasks/Txxx.md`。包含：任务目标、必须通过的前置及证据、创建/修改的真实路径、现有对象检查、所用参数版本、接口/状态转换、逐步实现、对应 TestCases 步骤及预期、失败回退、所需确认事项。

每个开始任务最多细化一个可验证增量。未知工具签名先查真实工具，**不写伪 API**。资源或场景新建后**保存重开验证**。任何产物不存在就写"待创建"，不得引用成现有文件。

## 证据格式

`Docs/Evidence/Txxx.md`：实际日期/工具版本、操作或命令、**退出码**、资产路径、用例预期与实际、PASS/FAIL/NOT-RUN、图像/录像/日志路径、已知限制、恢复位置。**不包含密钥与完整个人配置。**

只有日志中的成功信息不能代替交互、视觉或存档实际验证。完成后同步 Handoff，列出最早可执行任务与阻塞。

**Godot 特有要求**：无头运行的证据必须包含实际 stdout（`ASSERT|` 行）与退出码，不能只写"运行成功"。视觉未验证的部分标 `awaiting-review`，**不得因无头断言通过就宣称画面正确**。
