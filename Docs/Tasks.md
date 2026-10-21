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
| T022 | **done（2026-10-19）** | `Docs/Evidence/T022.md`；`Docs/Tasks/T022.md`；`tests/run_t022_loop.gd`；`scripts/debug/debug_entry.gd`（`restart_round()` + 死亡 HUD 提示 + 失效实例守卫）；`scripts/characters/interaction.gd`（`current_target()` 清失效目标）；`project.godot`（`debug_restart` = F6）；`tool_capture_render.gd -- t022`；`Art/Probes/t022_*.png` | 猫循环回归与打包：真实关卡 `l_courtyard.tscn` 上跑通 **探索 → 发现 → 扑击捕获 → 进食 → 饮水 → 再次探索**（位移 1.350 m、`captures=1`、捕获食物落点 0.072 m、Hunger Δ34.89、Thirst Δ39.88、再次扑击成功）；**连按与幂等**（10 帧只启动一次、扑击中 8 次全拒 `busy` 且不重复扣体力、交互连按 `consumed_count` 恒 1、重复上报 `invalid`）；**体力耗尽**（被拒不位移 0.00000 m、不进恢复态、冲刺回落 1.80 m/s、恢复后可再扑）；**寻路失败回退**（1.22 s 内记录失败 → `wait`/`path_failed` 2.83 s → 重选 3 次放弃且不再查询 → 恢复后路径点数 2、账本不变）；**临时死亡重开**（`died` 只一次、死后交互/扑击全拒、`restart_round()` 计数 1→2→3、`world_time` 归零、旧实例释放、无残留、新一局可再次捕获）；**168/168 ×3** + 包内 168/168；全量回归 **19 套件 1999 条全绿**；包 **Reborn.pck 220,116 B / RebornSelfTest.pck 694,696 B**；视觉 2 图已判读；**修掉重开后 HUD 读已释放目标导致的 6 条脚本错误**（补 E13 回归断言，并把 A14 判据改成"套件内看汇总 + 日志由外部扫描"） |
| T023 | **done（2026-10-20）** | `Docs/Evidence/T023.md`；`Docs/Tasks/T023.md`；`scripts/ai/cat_ai.gd`；`resources/species/cat.tres`（`ai_script`）；`scripts/ai/animal_ai.gd`（**脚下导航锚点** + 兜底收紧）；`debug_entry.gd`（`patrol=`）；`tests/run_t023_cat_ai.gd`；`tool_capture_render.gd -- t023`；`Art/Probes/t023_*.png` | 猫 NPC 巡游与发现：新 `CatAI`（`EXPLORE` 巡游 → `ALERT` **0.4 s** → `APPROACH` 到 **0.65 m 停住**，**不扑击、不造成伤害**）；巡游点来自组 `patrol_points`（**按名字排序 = 确定性**），无组时退化为环上可达点；到点 **2.43 s**/0.475 m、换点 2.00 s；不每帧请求路径（1 s 增量 1）；目标全不可达 → 2.74 s `WAIT`(`path_failed`) → 1.02 s 自恢复（**不永久阻塞、不假装到点**）；视觉 **9 m / 60°** + `world_static` 遮挡 + 草丛 0.4 + 近距 0.8 豁免、听觉 **12 m × loudness**（**完全复用 T020 感知，零新增算法**）；警戒 0.517 s 内结束且停手停脚、重复注入不无限延长；接近 **2.30 s 收敛到 0.632 m**，失视后 `last_seen` 偏差 **0.0000 m**（不追实时坐标）、不可达记 `finished_without_progress`；**177/177 ×3** + 包内 175/175（少 2 条为包内不可读的源码静态检查）；全量回归 **20 套件 2167 条全绿**；包 **Reborn.pck 228,792 B / SelfTest.pck 741,544 B**；视觉 2 帧（HUD `ai:` 逐字含 `patrol=`、`state=approach reason=in_range`；两胶囊相距 < 0.5 身位）；**顺带修好基类两个真实缺陷**（代理挂在身体中心 → 高个子物种零位移；兜底把"不可达"走成"可达"） |
| T024 | **done（2026-10-21）** | `Docs/Evidence/T024.md`；`Docs/Tasks/T024.md`；`scripts/ai/cat_ai.gd`（`CHASE`/`SEARCH`/洞口等待/逃脱账本）；`tests/run_t024_chase_search.gd`；`tests/run_t023_cat_ai.gd`（2 处断言升级）；`debug_entry.gd`（HUD `search=`；`MOV` 行 `search=`/`giveups=`/`chase=`）；`tool_capture_render.gd -- t024`；`Art/Probes/t024_*.png` | 追击、搜索和放弃：`CatAI` 新增 **`CHASE`**（猎物跑开后的持续追击 / 搜索中重新发现）与 **`SEARCH`**（失视 → 警戒 0.4 s → 搜）；**搜索目标 = 失视时刻的快照，搜索/等待期间永不更新**（瞬移猎物后快照偏差 **0.0000 m**、目的地距实时位置 > 0.5 m）；普通搜索 **5 s** 超时 → `EXPLORE(search_timeout)`、洞口场景**到达洞口起 6 s** → `hole_timeout`（另加 `search_overall_max` 12 s 兜底），**都记一次放弃、绝不无限走**；洞口判定用组 `hide_spots` + `metadata kind=mouse_hole`，**停在洞外 ≥ 半径**（不进洞、`move_intent=0`、1 s 位移 ≤ 0.15 m）；**逃脱账本**（`encounter_id` 唯一、一场只结算一次、**猎物存活才算逃脱**，信号 `chase_started`/`chase_ended`）；到 0.65 m 仍**只停住不攻击**（伤害属 T025）；**134/134 ×3** + 包内 133/133；全量回归 **22 套件 2478 条全绿**；包 **Reborn.pck 236,472 B / SelfTest.pck 781,180 B**；视觉 2 帧（HUD 逐字 `state=chase reason=chasing`、`state=search reason=arrived search=(-4.00, 0.19, 19.60)/0.8s`） |
| T025 | **done（2026-10-22）** | `Docs/Evidence/T025.md`；`Docs/Tasks/T025.md`；`scripts/systems/attack.gd`（新组件 `AttackSettlement`）；`scripts/data/species_config.gd`（`Attack` 组 + 自校验）；`resources/species/cat.tres`/`mouse.tres`；`scripts/characters/animal_body.gd`（`ACT.ATTACKING` + `attack` 组件）；`scripts/ai/cat_ai.gd`（`State.ATTACK` + `attack_enabled`）；`debug_entry.gd`（`attack=` / `atk*`）；`tests/run_t025_attack.gd`；`tool_capture_render.gd -- t025`；`Art/Probes/t025_*.png` | NPC 攻击与玩家受伤：`AttackSettlement` 走 **预警 0.45 s → 伤害帧 35 → 恢复 1.2 s**（真源 `Parameters` 第 69 行）；**伤害帧四查一结算**（目标个体仍在 / 水平距离 ≤ 0.65 + 0.05 / 与**锁定方向**夹角 ≤ 60° / **无遮挡**）——躲开、绕墙、目标已死或被捕获**都无伤**；**遮挡复核刻意不走 `Perception` 的近距豁免**（0.65 m < 0.80 m，否则"绕墙"永远命中）；预警期不掉血、不位移（1 s ≤ 0.15 m）；恢复期内**绝不重复伤害**（同帧连按 10 次只启动 1 次）；伤害走既有 `survival.apply_damage(…, "attack")`，**受伤中断交互且无收益**、`died` 只发一次；鼠 `can_attack=false`（不建组件、AI 永不进 `attack`）；攻击不消耗体力、不扑击（T021 不受影响）；**175/175 ×3** + 包内 174/174；全量回归 **23 套件 2655 条全绿**；包 **Reborn.pck 249,140 B / SelfTest.pck 825,204 B**；**视觉 2 帧已产出**（`t025_telegraph` 抓在预警窗口 `attack_state=telegraphing` / `prey_hp=100`；`t025_hit` 抓在伤害帧后 `hits=1` / `prey_hp=65`）**但判读因 vision 服务 503 记 NOT-VERIFIED** |
| T026 | **done（2026-10-23）** | `Docs/Evidence/T026.md`；`Docs/Tasks/T026.md`；`tests/run_t026_cover.gd`（96 条）；`tool_capture_render.gd -- t026`；`Art/Probes/t026_*.png` | 老鼠藏身与掩体规则：**三条规则实测全部为真 → 生产代码零改动**（验证型任务）。① **草丛只降低可见性**：`cover_volumes` 4 个全是 `visibility_factor=0.4` 的 `Area3D`（layer 0、**非实体**）；4.5 m 草丛内**看不见** / 开阔看得见，3.0 m 可见、3.9 m 不可见（9.0×0.4=3.6 两侧）；猫/鼠穿草丛 1 s 位移 1.653 / 1.071 m（**不被顶住**）；`AttackSettlement.occluded()` **不把草丛当遮挡**（照样命中 35，真墙对照 true）。② **鼠洞阻止猫进入**（**按层**跨墙路由）：猫**绕墙 34.68 m**（最近洞口 2.000 m）而鼠**直穿 4.00 m**（最近 0.041 m）；`reachable()` 猫 false / 鼠 true；物理推猫**停在 0.703 m**（走过 1.339 m）、鼠**钻到 0.089 m**。③ **躲藏不凭空恢复**：`HIDDEN` 3.95 s 内 hunger/thirst 不上升不回满、health 不恢复、stamina 最大帧增 0.00、衰减 0.1012 vs 探索 0.0990（同量级）。**96/96 ×3** + 包内 **96/96**；全量回归 **24 套 2751 条全绿**；包 **Reborn.pck 249,140 B / SelfTest.pck 849,852 B**；**视觉 2 帧 + vision 判读通过**（① 半透明草丛体量里的鼠 + HUD `seen=false`；② 洞口缝里半个鼠身 + 猫在墙外 `state=alert saw_prey`）。 |
| T027 | **done（2026-10-24）** | `Docs/Evidence/T027.md`；`Docs/Tasks/T027.md`；`scripts/world/ecology_spawner.gd`（新组件 `EcologySpawner`）；`scenes/debug/ecology_entry.tscn`（可玩入口）；`scripts/debug/debug_entry.gd`（`ecology_enabled` 默认 false + `eco:` HUD 行）；`tests/run_t027_ecology.gd`（96 条）；`tool_capture_render.gd -- t027`；`Art/Probes/t027_*.png` | 按玩家物种布置测试生态：**同一张 `l_courtyard.tscn`** 上按玩家物种铺 NPC —— 猫玩家→**2 只鼠 NPC**（可捕）、鼠玩家→**1 只猫 NPC**（要躲），换物种**先 `clear()` 再重铺**（旧实例全释放、id 无残留）；**玩家不计入 NPC 数量**（`npc_count()` 只数本组件铺出的活跃 NPC，并与关卡 `animal_bodies` 存活数 − 1 交叉核对）；**出生周围无即时攻击** = 距离规则（非捕食者 8.0 m、捕食者 14.0 m，**都大于该物种视距** 6.5 / 9.0）+ 4 s 行为窗口（玩家零伤害、零攻击启动、最近距离 **3.63 m**）；落点用"现有出生标记 + 环上候选"，按**物种自己的导航层**吸附（层 1 最差 0.050 m / 层 2 最差 0.201 m），**不改关卡几何**；集成：鼠 NPC 从 1.51 m 逃到 8.50 m、玩家猫 0.98 m 扑击**捕获**（生态计数 2→1、捕获食物 +1）、猫 NPC 4.00 → **0.57 m** 接近、近距离**真的打到玩家**（100 → 65，一次 35 不秒杀）；**96/96 ×3** + 包内 **96/96**；全量回归 **25 套 2846 条全绿**；包 **Reborn.pck 263,052 B / SelfTest.pck 889,120 B**；**视觉 2 帧 + vision 判读通过**；**顺带修掉 1 个真实导出缺陷**（默认候选按 `.tres` 扩展名过滤 → 包里资源是 `.res`/`.remap` → 包内列表为空） |
| T028 | **awaiting-review（2026-10-25）** | `Docs/Evidence/T028.md`；`Docs/Tasks/T028.md`；`tests/tool_t028_walkthrough.gd`（自测走查，4 条硬判据）；`tool_capture_render.gd -- t028`；`Art/Probes/t028_*.png` | 第一轮概念试玩 —— **自测半边完成、真人半边 NOT-RUN**（agent 自测不替代真人）。在可玩入口 `scenes/debug/ecology_entry.tscn` 上把两物种路线各真实走一遍（`player_controlled=false` + 沿**按层导航路径**驱动）：**猫线** 11.18 m 内 0.90 s 看见鼠、**1 次扑击 3.9 s 捕获**（`route_len 10.96 / ratio 0.98`、`prey_states=["explore","alert"]`、`prey_min_gap 1.10 m`、捕获后生态 2→1）；**鼠线** 0.43 s 被猫看见（探针确认是 `alert/saw_prey` 8.92 m **视觉**触发、非初始化 bug）→ **14.1 s 进洞**（`hole_gap 0.24 m`、逃段 `21.39 m / straight 21.12 / ratio 1.01`）、**猫最近只到洞心 6.99 m** 且 12 s 内回 `explore`（`giveups=1`）；两线 `hp 100→100`、存活。**W1~W4 4/4 通过 ×3 次源码 + 包内 4/4**；全量回归 **25 套 2847 条全绿**；包 **Reborn.pck 263,052 B（与 T027 相同 → 生产代码零改动）/ SelfTest.pck 905,604 B**；**视觉 2 帧**（`t028_cat_chase` 210,342 B 判读通过：2 角色 + HUD `eco: player=Cat npcs=2`、`sense: seen=true`；`t028_mouse_hole` 221,923 B 部分确认：墙+缺口+HUD `pos:(26.68,0.12,19.00)`=洞口坐标，**角色辨识 vision 未确认、不编造**）；**暴露 2 个体验问题候选交 T029**：A 鼠 `ALERT` 0.3 s 在猫 `sprint 4.5` 下形同虚设、B 猫 AI 追击**从不 `want_sprint`**（walk 1.8 < 鼠 sprint 3.0 → 追不上） |
| T029 | **awaiting-review（2026-10-26）** | `Docs/Evidence/T029.md`；`Docs/Tasks/T029.md`；`scripts/ai/cat_ai.gd`（`chase_sprint_enabled` 默认 **false**、`chase_sprint_min_gap` 3.0、`_sprint_gate()`）；`scripts/world/ecology_spawner.gd`（`predator_min_distance` 14.0→**24.0**）；`tests/run_t029_sprint_chase.gd`（39 条）；`tool_capture_render.gd -- t029`；`Art/Probes/t029_chase.png` | 调整路线与参数（选 T028 候选 **B**：猫 AI 追击从不 `want_sprint` → `CHASE` 数学上追不上）。**能力已实现并逐条验证**：移动阶段（`APPROACH`/`CHASE`/`SEARCH` 赶路）+ 距离门控才冲刺，`EXPLORE`/`ALERT`/`ATTACK`/`WAIT` 一律不冲；实测冲刺 **4.02 m/s** vs 关掉 **1.80 m/s**（比值 2.24）、低体力回落 **1.81 m/s** 不崩、回满 **4.29 m/s**；**39/39 ×3 源码 + 包内 39/39**；全量回归 **26 套 2887 条全绿**；包 **Reborn.pck 263,436 B / SelfTest.pck 921,704 B**。**关键实测**：只给 `CHASE` 加冲刺**等于没改**（猫几乎不进 `CHASE`，`cat_min_to_player` 6.76→6.75）→ 必须扩到 `APPROACH`/`SEARCH`；门控由**刹车距离**倒推（1.2 m 时滑 0.475 m、洞口挤 0.276 m）→ 取 **3.0 m**；`predator_min_distance` 按冲刺速度重算 **24.0 m**。**默认关**：打开后鼠被发现即被咬（3/3 `hp 100→0`），但根因是两条**既有缺陷**——①**鼠洞不是安全区**（洞里 0.24 m 处被洞外 0.79 m 的猫咬死，等于回答 T026 的"洞里能否被打中：能"）、②**冲刺会把 AI 冲出无护栏平台**（`split_platform` 实测 `y=-210 m`，该段已显式关冲刺）；② 与平衡归负责人 / U01。**视觉 1 帧**（191,964 B）**未抓到冲刺瞬间**（`want_sprint_frames=0/90`，如实记录），但 HUD 逐字确认 `safe_min=8.0/**24.0**`、`min_dist=26.00` = 出生半径改动的直接证据 |
| T030 | **done（2026-10-27）** | `Docs/Evidence/T030.md`；`Docs/Tasks/T030.md`；`autoload/game_state.gd`（新 `GameState`：解锁/档案/事件/`LifeId`）；`scripts/core/life_cycle.gd`（新 `LifeCycle` 状态机）；`scripts/core/main_entry.gd`（新正式入口）；`scenes/core/main.tscn`（**占位 → 真入口**）；`project.godot`（`GameState` autoload + `life_select_1/2`）；`tests/run_t030_lifecycle.gd`（111 条）；`tool_capture_render.gd -- t030`；`Art/Probes/t030_*.png` | 生命周期状态与事件记录：**存活 → 结算 → 选物种 → 出生**闭环（`State {ALIVE, SETTLING, SELECTING, SPAWNING}` + 迁移表；非法迁移**不改状态/不写档案/不占 `LifeId`**，原因 `wrong_state`/`locked_species`/`unknown_species`/`already_settled`）。**死亡只结算一次**：连打 3 次 `end_life` + 直接 `GameState.end_life` → 档案 1 条、`life_settled` 1 次、`settle_count` 1。**档案字段**（策划 §9.5 全覆盖）：`life_id/species_id/start,end_world_time/duration/end_reason/damage_reason/start_position/captures/escapes/food_gained/water_gained/discoveries/event_first,last/snapshot`（实测 `duration=3.5000` = 13.5−10.0）。**事件记录** `{seq, life_id, kind, world_time, data}`：`seq` 全局单调、封顶 `MAX_EVENTS=1024`（灌 1044 条 → 1024，`last_event_seq` 仍 1044）、跨世保留。**`LifeId`** `L%04d` 单调不复用。**结算期冻结**：`time_advancing=false` + `player_controlled=false` + 清空意向 + 取消交互；**不留尸体**（改名后 `queue_free()`，`Player*` 计数 0、`npc_count()` 不变）。**正式入口**：`main.tscn` 只剩 `Node3D+script`，关卡/HUD/状态栏运行期构建 → T013/T018/T026 断言继续成立；物种从 `resources/species/*.tres` 发现（**修掉包内 `*.tres.remap` 导致 0 物种的真实导出缺陷**）。**111/111 ×3 源码 + 包内 111/111**；全量回归 **27 套 2998 条全绿**；包 **Reborn.pck 289,832 B / SelfTest.pck 968,900 B**；视觉 3 帧，`t030_settled` 判读通过（结算+选物种文字在、无尸体、HUD `— / —`）。**遗留**：`test_mode=true` 为临时开发态（正式解锁条件属 T031）、真实按键选择 NOT-RUN、持久化属 T037 |
| ART01 | **done（2026-10-21，本机系统时钟）** | `Docs/Evidence/ART01.md`；`Docs/Tasks/ART01.md`；`Tools/Blender/art01_bush_001.py`；`Art/Exports/Environment/SM_Bush_001.glb`；`Game/Reborn/assets/environment/sm_bush_001.glb`；`Game/Reborn/tests/run_art01_bush.gd`（83 条）；`Game/Reborn/tests/tool_capture_art01.gd`；`Art/Probes/art01_*.png` | **建模流水线打通 + 首个静态资产接入**：草丛掩体由半透明绿盒子换成 2040 tris / 2 材质 / 双面 / **零碰撞** 的真实草叶，并补上**溪边掩体原本没有视觉**的缺陷；**83/83** + 全量 **29 套 3081 条全绿**；3 轮返工（泥土墩过高→相机在土里、草叶像板条、密度与取景缺陷）；**不是正式美术 approved**，也**没有**越过 P6 阶段门 |
| ART02 | **done（2026-10-21，本机系统时钟；**不是**正式美术 approved）** | `Docs/Tasks/ART02.md`；`Docs/Evidence/ART02.md`；`Tools/Blender/art02_cat_001.py`；`Art/Blender/Cat/CAT_BODY_001_v001…v008.blend`；`Art/Exports/Cat/SM_Cat_001.glb`（1,744,408 B，sha256 `b5ae013b…`）；`Game/Reborn/assets/characters/cat/sm_cat_001.glb`；`Game/Reborn/tests/run_art02_cat.gd`（46 条）；`Game/Reborn/tests/tool_capture_art02.gd`；`Art/Probes/art02_*.png` | **模型质量专项试点（只换猫）**：猫的视觉由**一个 `CapsuleMesh` 灰盒**换成 9568 tris / 2 材质槽 / 2048² 烘焙 albedo 的真实模型（骨架线→变截面放样→voxel remesh 焊接→抽面→噪声位移；眼/鼻/耳内为 remesh 之后贴的面部件）。接入方式：`SpeciesConfig.visual_scene` 配置驱动 → `AnimalBody._rebuild_visual()`，胶囊网格退化为隐藏的尺寸代理（**T009/T013 的 mesh==capsule 断言不变**），蹲姿用 0.625× 竖向压缩近似。**46/46** + 回归 9 套 **1122 条全绿**；游戏内同机位 before/after 判读从"完全看不出是猫"→"轮廓可辨认为猫"。**5 轮返工**；**仍未达专业动物水准**（耳比例/四肢/塑料感），下一步需专业基础模型（需授权），骨骼与动画仍属 **P6 阶段门** |
| ART02-V009 | **not-accepted（2026-10-21，本机系统时钟）** | `Docs/Tasks/ART02_V009.md`；`Docs/Evidence/ART02_V009.md`；`Tools/Blender/art02_cat_v009.py`；`Art/Blender/Cat/CAT_BODY_001_v009{,r2,r3}.blend`；`Art/Staging/ART02_V009/ART02_V008_vs_V009_{views,sheet}.png`；`Art/Probes/art02_v009_*.png` | **基础形体重建（换掉 voxel remesh 那套方法）但未过验收**：躯干+四肢+尾巴改为「一根骨架 → Skin 修改器 → 1 级细分 → 焊接 → bmesh 松弛 → 宽高斯解剖塑形」，头部为 12 截面放样 + 剖面调制，眼睛有上下眼睑环、耳朵是有厚度耳壳；产出 **99.3% 四边形 / 0 非流形 / 5296 tris / min_z=0**，**不使用 remesh / decimate / 噪声位移**（自检明文打印）。3 轮返工每轮按判读改（工具：`vision.js`）。**仍不达标**：横向环状台阶（成因是 Skin 逐关节半径起伏）、四肢关节不可辨、脚掌无趾部 → 按 `modeling3.md` §6 **停止迭代**。**正式资产仍是 V008**（`cat.tres`/导出/Godot 全部未改，`run_art02_cat.gd` 46/46 仍绿）。**待负责人决策**：授权获取专业短毛猫基础模型（首选）或安排美术雕刻 |
| T031～T063 | pending | 无 | 见 `轮生_Reborn_开发计划_v1.0.md` |

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
T001 / T002 / T003 / T005 / T006 / T007 / T008 ～ **T027 均已完成**，**T028 完成自测半边（awaiting-review）**；台阶、导航、调试入口、生存时间入口、交互接口、食物/饮水、正式 HUD、
**鼠 NPC 状态机**、**感知（视觉 / 听觉 / 逃跑躲藏）**、**猫扑击与捕获结算**、**猫循环回归与打包**、**猫 NPC 巡游与发现**、**猫的追击 / 搜索 / 放弃**、**NPC 攻击与玩家受伤**、**老鼠藏身与掩体规则**、**按玩家物种布置测试生态**、**第一轮概念试玩的自测走查（两物种各一条真实路线 + 两帧视觉）**已落地。
（口径变化：T011/T012 是"游戏代码零改动、差异全在配置/关卡/导航数据"；**T013 起开始真的改游戏代码** —— `step_climb` 抬升修复、调试入口、`SurvivalState`/`SurvivalController`、`AnimalBody` 接入、`Interactable`/`InteractionDetector`/`ResourcePoint` 与动作事务、`Perception`/`CaptureSettlement`、`AnimalBody.enum ACT` 扑击状态机、`DebugEntry.restart_round()`、`CatAI`（巡游 → 警戒 → 接近 → **追击 → 搜索 → 攻击**）、`AttackSettlement` 与**导航代理的脚下锚点**；**T026 是"验证型"任务：生产代码零改动**。）
**P0 阶段门完成**；**P1 完成**（T008～T013）；**P2 完成**（T014～T022）；**P3 完成**（T023～T029；T028 的真人半边与 T029 的冲刺平衡都挂在 U01 真人试玩上）；**P4 进行中**（**T030 已 done（2026-10-27）**）→ 下一步 **T031 地点发现和老鼠解锁**。

下一步可执行（按建议优先级）：
1. **T031（地点发现和老鼠解锁）**（2～4h，前置 T030 **已满足**）：指定鼠洞**稳定 ID**；发现事件更新长期记录，**不按"刷捕猎"解锁**。
   紧随其后的 **T032（生命档案与结算页）**、**T033（正式物种选择与重生）**：`scenes/core/main.tscn` **已经是真入口**，
   T030 已提供 `GameState` 档案/事件与 `LifeCycle` 状态机，T032/T033 在其上补"结算页"与"重生清理"。
   会上必须带上 T029 的两条**待决策**（`Docs/Evidence/T029.md` §6）：**① 鼠洞不是安全区**（洞里能被打中 → 鼠的"进洞"不是脱战），
   **② 冲刺会把 AI 冲出无护栏平台且掉落后无处理**（`split_platform` 实测 `y=-210 m`）——加地形高差前必须定"掉落后怎么办"。
   T029 的冲刺能力已实现但**默认关**：是否默认开、开多狠，等 **U01 真人试玩**（2～3 位外部试玩者的最小请求在 `Docs/Tasks/T028.md` §7 与 `Docs/Evidence/T028.md` §10）。
   T027 §7 待定：**正式启动链已落地**（T030：`main.tscn` = 真入口，出生/选物种在 `MainEntry` + `LifeCycle`；`test_mode` 待 T031 接正式解锁）、**区域 NPC 数量账本属 T035**、
   **NPC 出生点正式布置**（本轮只用现有标记 + 环上候选，**未改关卡几何**）、**猫 : 鼠 NPC 数量配比 1 : 2** 是否最终设计（T029 按试玩结果调）。
   顺带带上待定：**猫跨 0.50 屏障是否加 `NavigationLink3D`**（T013 §9）、**跳跃是否消耗体力**（T015 §9）、
   **交互是否要朝向/视锥限制**（T016/T017 §9）、**食物/水恢复值是否按物种分列**（T017 §9）、
   **"调参页"是否要做成可交互面板**（T018 §8）、**交互用"按住开始/松开取消"是否最终设计、距离是否要含竖直差**（T016 §7）。
   T020 §8 待定：**感知新增 4 个实现默认值**（`footstep_interval_base` 0.5 s、`flee_timeout` 3.0 s、`reach_tolerance` 0.5 m、`hide_arrive_radius` 0.30 m）、
   **近距豁免是否受视锥限制**、**威胁判据是否加"正在扑击 / 已发现我"**、**草丛是否要改成物理体积**、**关卡鼠洞是否只留 1 个**。
   T021 §8 待定：**捕获食物营养 35.0**、**恢复期是否锁姿态**。　T022 §9 待定：**"重开"是否升级为正式 UI**（P4）、**F6 是否与正式快捷键冲突**、**发布节奏**。
   T023 §9 待定：**5 个新实现默认值**（`patrol_radius` 6.0 / `patrol_pause` 1.0 / `patrol_min_move` 0.5 / `patrol_retry_wait` 1.0 / `approach_repath_interval` 0.5）、**巡逻点位布置属 T027**、**环上巡游的目标 ID 会重复**（无稳定点位）。
   T024 §9 待定：**5 个新实现默认值**（`chase_repath_interval` 0.25 / `search_arrive_radius` 0.6 / `hole_search_radius` 0.6 / `search_overall_max` 12.0 / `chase_trigger_move` 0.5）、**多洞口优先级属 T027**。
   T025 §9 待定：**3 个新实现默认值**（`attack_facing_half_angle_deg` 60 / `attack_retry_interval` 0.25 / `attack_fail_max` 8）、
   **伤害帧遮挡复核刻意不走感知的近距豁免**（0.65 m < 0.80 m；若将来统一改掉可合并）、**攻击是否消耗体力**（第 69 行没给）、
   **被攻击后的逃跑 / 仇恨属 P4**、**攻击音效属 T055**。
   **`APPROACH → CHASE` 的判据是"猎物跳变 > 0.5 m"**（连续低速奔跑不切 `CHASE`，只是状态名不同、行为等价）、**逃脱账本落 `LifeRecord` 与 `encounter_id` 持久化属 P4**。
2. ~~T008 / T009 / T010 / T011 / T012~~ **已完成**；正式角色/骨骼资产仍属 **P6** 阶段门，不得提前。

**做角色资产时必须遵守 T005/T006 实测的两条约定**：
① 在 Blender 里**面朝 `+Y`**（导入 Godot 后才朝 `-Z` 前方）；
② 骨骼动画**原地、无根运动**；导入会让极值削减约 1–2%（见 T006 证据 §3.2）。

**T006 已解除，不再阻塞**：骨骼链往返已被实测证明，正式骨骼资产可以开始（但仍属 P6，需按阶段门排期）。
T028 已按此执行：**awaiting-review**（自测 4/4 通过、U01 真人半边 NOT-RUN），**不冒充真实玩家验证**；后续任何"体验通过"都必须来自真人试玩。

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
