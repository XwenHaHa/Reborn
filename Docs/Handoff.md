# 开发交接：2026-10-27（T030 生命周期状态与事件记录落地 —— **P4 进行中，下一步 T031**）

## 真实状态

**引擎**：Godot 4.7.2 + GDScript（UE5 路线已废止）。

**T001 ～ T027 全部完成；T028（自测走查）与 T029（追击冲刺能力 + 默认关）均为 awaiting-review**（P0 = T001～T007；P1 = T008～T013；P2 = T014～T022；P3 = T023～T029）；台阶、导航、调试入口、生存时间入口、消耗/伤害、交互接口与食物/饮水、正式 HUD、鼠 NPC 状态机、**感知（视觉 / 听觉 / 逃跑躲藏）**、**猫扑击与捕获结算**、**猫循环回归与打包**、**猫 NPC 巡游与发现**、**猫的追击 / 搜索 / 放弃**、**NPC 攻击与玩家受伤**、**老鼠藏身与掩体规则**、**按玩家物种布置测试生态**、**第一轮概念试玩的自测走查**与**猫 AI 追击冲刺（默认关）**已落地；技术层文档为 Godot 版。

| 任务 | 状态 | 关键证据 |
|---|---|---|
| T001 | **done** | 环境/硬件采集、UE 定位全否定、Godot 无头闭环实测 |
| T002 | **done** | 无头断言 18/18 ×3；**视觉已补验通过**（修复了场景无光源缺陷） |
| T003 | **done** | LFS 生效；从零克隆的工程可被引擎实跑 18/18 |
| T004 | **done** | **资产路线已定：Blender 3.3.1 自带无头 CLI，不用 MCP** |
| T005 | **done（2026-10-13）** | 1 m 资产往返 = **1.0000 m**；断言 50/50 ×3 + 包内 50/50；运行中碰撞 1.0001 m；视觉已留证 |
| T006 | **done（2026-10-13）** | 骨骼往返 65/65 ×3 + 包内 65/65；长度 1.0 s、`LOOP_LINEAR`、首末闭合 0.000；无根运动/无根骨缩放；两帧视觉留证 |
| T007 | **done**（真实按键 awaiting-review） | 导出/运行/退出/重启/视觉均通过；包内断言 18/18 + 22/22 |
| T008 | **done（2026-10-13）** | 台阶组件化 + `SpeciesConfig`/`AnimalBody`；**配置驱动的物理台阶实测**；**114/114** ×2、包内 103/103 |
| T009 | **done（2026-10-13）** | 猫移动（走/跑/蹲/跳 + 第一人称相机）；斜坡・低顶・落地・相机穿墙全过；**81/81** ×3 + 包内 81/81；lab 玩家换成正式猫，T002/T005/T006/T007/T008 回归全绿；过程中修掉 `step_climb` 两处判据缺陷 |
| T010 | **done（2026-10-13）** | 鼠移动与通道尺度：**站立**过 24×30 cm 洞（胶囊 0.18 不变、0 空中帧）、**猫站立与蹲姿都过不去**、禁高跳、0.15 m 低顶下不扩碰撞；**95/95** ×3 + 包内 95/95；**gameplay 代码零改动**（差异全在 `mouse.tres`）→ 说明 T009 的抽象没漏东西 |
| T011 | **done（2026-10-13）** | 生态灰盒 `l_courtyard.tscn`：四区域**恰好铺满** 72×56 可玩矩形；策划 §8.2 五条结构全部落地并用**两种物种真实胶囊**验证（猫跳越 0.50 屏障、鼠穿 0.24×0.30 洞、猫在洞/溪缝前被挡、鼠穿溪缝）；四条出生点→补给走廊 0 阻挡；**210/210** ×3 + 包内 210/210；**gameplay 代码零改动**；视觉 7 帧 |
| T012 | **done（2026-10-13）** | 导航可行性：**分物种双导航图 + 分层**（鼠 layer1 r=0.07 / 猫 layer2 r=0.17、cell 0.03）；鼠层穿 0.24 洞 9.00 m、穿溪缝 12.00 m；猫层同一对端点 **35.44 m 且不穿洞**、**洞里没有猫的导航面**；真实胶囊行走（鼠进洞 236 帧 0 重叠；猫 900 帧 **0 帧进入洞口走廊**）；**79/79** ×3 + 包内 79/79；**视觉证据 NOT-RUN**（运行时导航调试绘制不可见）；**gameplay 代码零改动** |
| T013 | **done（2026-10-15）** | 调试入口 `scenes/debug/debug_entry.tscn` + `scripts/debug/debug_entry.gd`（切猫/鼠、碰撞线框、导航路径、调试 HUD、`PARAMS|`/`MOV|` 记录）；**修掉遗留项 ①**：台阶抬升只改 y，抬升帧水平位移 = 该帧正常位移（0.0300 = 0.0300；修复前 ≥0.2 m）；遗留项 ② 只记录 + 可视化（猫层 34.77 m 绕行不穿洞 / 鼠层 5.00 m 直穿洞口）；**159/159 + 73/73** ×3 + 包内同；全量回归（T002→T012 + 台阶探针）全绿；包 388,320 B；视觉 6 图（引擎碰撞开关实测**不可见** → 自绘线框兜底）；过程中记录了一次 `project.godot` 被外部覆盖的事故（`Docs/Evidence/T013.md` §9） |
| T014 | **done（2026-10-15）** | 生存状态与统一时间入口：`SurvivalState`（契约五字段）+ `SurvivalController`（**只吃世界时间、不累加 delta**）；饥渴按 `Parameters.md` 速率下降、体力 `RegenDelay` 后按速率恢复；**暂停（树暂停 / 显式门闩）实测不消耗**；**30/60/144 Hz 跑 60 s 消耗完全一致（spread = 0）**；**106/106 ×3 + 包内 106/106**；全量回归全绿；包 411,140 B |
| T015 | **done（2026-10-15）** | 消耗、警告与基础伤害：冲刺按 `SprintStaminaPerSecond` 扣体力（实测猫 15.01 / 鼠 35.02 per 1 s，行走 0.00）、**双门控**（≥5 才能开始 / 耗尽转行走且保留基础移动）、`RegenDelay` 后按速率恢复；`Hunger/Thirst ≤ 25` 预警（**不扣血**）、**归零各扣 1/s（两项 2/s）**、Health 不自动恢复；跌落 `≤7 m/s` 无伤、超过 `(v−7)×10`（3 m → 6.767）、上限 100；**93/93 ×3 + 包内 93/93**；全量回归全绿；包 433,020 B |
| T016 | **done（2026-10-15）** | 交互检测与动作接口：鸭子类型三方法（`has_method()`，**不用类型转换**；非 `Interactable` 子类也能参与）；`interactable` 层 `intersect_shape`（**不动身体 `collision_mask`**）；距离（猫 1.00 / 鼠 0.45，可被目标 `range_override` 覆盖）与遮挡（**只认 `world_static`**）；排序确定性（priority → 距离 → ID）且**只暴露一个目标**；`duration` 走世界时间（暂停冻结）；**同事务 ID 幂等**（第二次不再调目标）；**118/118 ×3 + 包内 118/118**；全量回归全绿；包 470,000 B |
| T017 | **done（2026-10-15）** | 食物、饮水与可取消交互：`ResourcePoint`（食物 1.5 s / Unit → Hunger 35；水 2 s → Thirst 40 且**无限**；容量 3、每 180 s 恢复 1 Unit）+ `scenes/world/resource_point.tscn`；**按物种判定食物类型**（猫肉 / 鼠种子，否则 `food_type`）；成功一次结算（扣 Unit + **夹紧**恢复）、取消与**受伤中断无收益**、耗尽 `empty`；**提交前复检**（禁用 / 超范围都拦且不扣不发）；**跨多周期一次结算**与 300 s 失效机制；**128/128 ×3 + 包内 128/128**；全量回归 15 套件全绿；包 499,624 B |
| T018 | **done（2026-10-15）** | 最小 HUD `scripts/ui/hud.gd` + `scenes/ui/hud.tscn`（`Control`，`mouse_filter = IGNORE`）：四项指标 `x / 上限`、低值警告（`饥饿` / `缺水` / `饥饿 + 缺水`，`≤25`）、交互提示（进食/饮水 + 目标 ID + 进度 %，无目标隐藏）；**信号驱动**（`_process` 唯一读取交互进度）、**只观察不改状态**、**正式界面不含调试数值（12 条禁词断言）**；**73/73 ×3 + 包内 73/73**；全量回归 16 套件全绿；包 523,148 B；**视觉 3 图判读通过**（`Art/Probes/t018_hud_*.png`：HUD 左下角可见、警告橙黄色、动作提示正确） |
| T019 | **done（2026-10-15）** | 鼠 NPC 觅食与警戒：`scripts/ai/animal_ai.gd` + `mouse_ai.gd`（`EXPLORE ↔ FORAGE ↔ ALERT ↔ WAIT`）；走去最近可用食物点（**5.22 m / 4.75 s**、到达 0.389 m ≤ 交互范围 0.45）→ 用**同一套** `InteractionDetector` 进食（units 3→2、Hunger +35）；警戒 **0.3 s** 上限（停手停脚、取消交互且**无收益**、可重复注入但不无限延长）；MoveTo 失败 **1 s / 最多 3 次重选 / 进 `WAIT` 后不永久阻塞**（实测 `path_failures=4`、`replans=3`、`no_progress`）；**状态与原因可查看**（`ai_report()` 16 字段 + HUD `ai:` + `MOV|ai_state=`）；配置用 `SpeciesConfig.ai_script`（**不写物种名判断**）且 `AnimalBody.ai_enabled` **默认关闭**；**72/72 ×3 + 包内 72/72**；全量回归 17 套件全绿；包 552,052 B |
| T020 | **done（2026-10-16）** | 鼠感知与逃跑：`scripts/systems/perception.gd`（**只观察**的组件，决定仍走 `alert_for()`）+ `mouse_ai.gd` 的 `ALERT → FLEE → HIDDEN → EXPLORE`；视锥 75°/6.5 m + `world_static` 遮挡 + 草丛 `visibility_factor` 0.4（重叠取最小）、**近距 0.80 m 内豁免草丛与遮挡但仍受视锥限制**；听觉 = `HearingRange × Loudness`（跑 10 / 走 5 / 蹲 2 m）**不吃墙不吃草丛**；**噪声只有发生位置**（声源走开 3.66 m 后快照仍不动）；脚步按速度反比 0.5/0.2/1.0 s **每事件一次**（121 帧 = 4 次）；180 cm 内立即逃、**可达鼠洞优先**（到达 0.267 ≤ 0.30）、洞不可达转草丛掩体、都没有则 `flee_timeout` **3 s 回退**（实测 2.90 s，**不位移、不假装躲藏**）、HIDDEN 撑满 4 s；**164/164 ×3 + 包内 164/164**；全量回归 **18 套件 1720 条全绿**；包 **605,740 B**；**视觉 3 图判读通过**（`-- t020`：警戒 / 逃跑途中 / 洞里躲藏）；**顺带修好 T019 遗留缺陷**（导航层反查读错 meta 键 → 猫曾误用鼠的导航面） |
| T021 | **done（2026-10-17）** | 猫扑击与捕获结算：新组件 `scripts/systems/capture.gd`（`CaptureSettlement`，挂在捕食者身上，**只观察 + 结算**）+ `animal_body.gd` 的 `enum ACT`（`IDLE/INTERACTING/POUNCING/RECOVERING/DEAD`）扑击状态机 + `mark_captured()`；140 cm / 0.25 s / 扣 25 / 恢复 0.6 s **全部从 `species_config` 读**（鼠 `can_pounce=false`，**不建捕获组件**）；扫掠用 `move_and_collide` 逐帧推进（单帧 0.0933 ≤ 0.0943，**不传送**；空地恰好 1.4000 m）；**障碍优先于障碍后的猎物**（墙距猫 50 cm → `blocked=world`、位移 0.340 m、猎物未结算、**体力不退还**）；命中后先查存活与账本 → 生成挂世界根的 `MEAT` 食物（容量 1、**300 s** 失效、命中点 0.000 m、鼠因食性被拒）、**不移除节点**（网格隐藏 / 层 0 / 出组 / 停物理，指标不回满）；**幂等**（二次结算 `invalid`；账本恒 1）；**4 只捕食者同帧只结算 1 次**、先到者得；启动门 8 种受阻原因、**被拒不扣体力不计数**；恢复期吞掉跳跃、再扑被拒（0.5862 s ∈ 0.6 ±0.08）；**279/279 ×3 + 包内 279/279**；全量回归 **19 套件 1999 条全绿**；包 **653,876 B**；**视觉 3 帧判读通过**（扑击中途 / 撞墙被挡 / 命中生成食物），并**修好取景工具的跨关卡污染**（`l_movement_lab` 自带 `Player` 被误读成第二个胶囊） |
| T022 | **done（2026-10-19）** | 猫循环回归与打包：真实关卡 `l_courtyard.tscn` 跑通 **探索 → 发现 → 扑击捕获 → 进食 → 饮水 → 再次探索**（位移 1.350 m、`captures=1`、捕获食物落点 0.072 m、Hunger Δ34.89、Thirst Δ39.88、再次扑击成功）；**连按与幂等**（10 帧只启动一次、扑击中 8 次全拒 `busy` 且不重复扣体力、交互连按 `consumed_count` 恒 1、重复上报 `invalid`）；**体力耗尽**（被拒不位移 0.00000 m、不进恢复态、冲刺回落 1.80 m/s、恢复后可再扑）；**寻路失败回退**（1.22 s 内记失败 → `wait`/`path_failed` 2.83 s → 重选 3 次后放弃不再查询 → 恢复后路径点数 2、账本不变）；**临时死亡重开**（`died` 只一次、死后交互/扑击全拒、计数 1→2→3、`world_time` 归零、旧实例释放、无残留、新一局可再捕获）；**168/168 ×3 + 包内 168/168**；全量回归 **19 套件 1999 条全绿**；包 **Reborn.pck 220,116 B / RebornSelfTest.pck 694,696 B**；**视觉 2 图判读通过**（死亡 HUD 的「按 F6 重开」确实画在屏幕上 / 重开后命中点出现捕获食物）；**修掉重开后 HUD 读已释放目标导致的 6 条脚本错误**（补 E13 回归断言，并把 A14 判据改成"套件内看汇总 + 外部日志扫描"） |
| T023 | **done（2026-10-20）** | 猫 NPC 巡游与发现：新 `scripts/ai/cat_ai.gd`（`CatAI extends AnimalAI`）= `EXPLORE` 巡游 → `ALERT` **0.4 s** → `APPROACH` 到 **0.65 m 停住**（**不扑击、不造成伤害**，攻击属 T025）；巡游点来自组 `patrol_points`（**按名字排序 = 确定性**）、无组时退化为环上可达点；到点 **2.43 s**/0.475 m、换点 2.00 s、不每帧请求路径（1 s 增量 1）；目标全不可达 → 2.74 s `WAIT`(`path_failed`) → 1.02 s 自恢复；视觉 **9 m / 60°** + `world_static` 遮挡 + 草丛 0.4 + 近距 0.8 豁免、听觉 **12 m × loudness**（**完全复用 T020 的 `Perception`，零新增算法**）；接近 **2.30 s 收敛 0.632 m**、失视后 `last_seen` 偏差 **0.0000 m**（不追实时坐标）、不可达记 `finished_without_progress`（不假装到位）；**177/177 ×3 + 包内 175/175**；全量回归 **20 套件 2167 条全绿**；包 **Reborn.pck 228,792 B / SelfTest.pck 741,544 B**；**视觉 2 帧判读通过**（HUD `ai:` 逐字含 `patrol=`、`state=approach reason=in_range`；两胶囊相距 < 0.5 身位）；**顺带修好基类两个真实缺陷**：① 导航代理挂在**身体中心** → 猫（0.24 m）原地抖零位移（改挂脚下 `NavOrigin`）；② "朝目标兜底"把**不可达**走成了可达（T019/T022 各挂 4/7 条，改成只在有路径时兜底） |
| T024 | **done（2026-10-21）** | 追击、搜索和放弃：`CatAI` 新增 **`CHASE`**（猎物跑开后的持续追击 / 搜索中重新发现）与 **`SEARCH`**（失视 → 警戒 0.4 s → 搜）；**搜索目标 = 失视时刻的快照，搜索/等待期间永不更新**（把猎物瞬移到视野外后快照偏差 **0.0000 m**、目的地距实时位置 > 0.5 m）；普通搜索 **5 s** 超时 → `EXPLORE(search_timeout)`、洞口场景**到达洞口起 6 s** → `hole_timeout`（另加 `search_overall_max` 12 s 兜底），**都记一次放弃、绝不无限走**；洞口判定用组 `hide_spots` + `metadata kind=mouse_hole`，**停在洞外 ≥ 半径 0.30 m**（不进洞、`move_intent=0`、1 s 位移 ≤ 0.15 m）；**逃脱账本**（`encounter_id` 唯一、一场只结算一次、**猎物存活才算逃脱**，信号 `chase_started`/`chase_ended`）；到 0.65 m 仍**只停住不攻击**；**134/134 ×3 + 包内 133/133**；全量回归 **22 套件 2478 条全绿**；包 **Reborn.pck 236,472 B / SelfTest.pck 781,180 B**；**视觉 2 帧判读通过**（HUD 逐字 `state=chase reason=chasing search=<none>` 与 `state=search reason=arrived search=(-4.00, 0.19, 19.60)/0.8s`，第二帧画面里猎物确实不在）；T023 的 2 条断言按规格升级为"失视 → `SEARCH`" |
| T025 | **done（2026-10-22）** | NPC 攻击与玩家受伤：新组件 `scripts/systems/attack.gd`（`AttackSettlement`，挂在攻击者身上，**只执行 + 结算**）= **预警 0.45 s → 伤害帧 35 → 恢复 1.2 s**（真源 `Parameters` 第 69 行）；伤害帧**四查一结算**：目标个体仍在 / 水平距离 ≤ 0.65 + 0.05 / 与**锁定方向**夹角 ≤ 60° / **无遮挡** —— 预警期间躲开（`out_of_range`）、绕墙（`occluded`）、目标已死或被捕获（`dead`）**都无伤**；**遮挡复核刻意自己打 `world_static` 射线，不走 `Perception` 的近距豁免**（0.65 m < 0.80 m，否则"绕墙"永远命中）；预警期不掉血、`move_intent=0`、1 s 位移 ≤ 0.15 m；恢复期内**绝不重复伤害**（同帧连按 10 次只启动 1 次）；伤害走既有 `survival.apply_damage(…, "attack")`，**受伤中断交互且无收益**、`died` 只发一次；鼠 `can_attack=false`（不建组件、AI 永不进 `attack`）；攻击不消耗体力、不扑击（T021 不受影响）；`ACT` 追加 `ATTACKING`（**只能追加**，T021 锁了前 5 个序号）；**175/175 ×3 + 包内 174/174**；全量回归 **23 套件 2655 条全绿**；包 **Reborn.pck 249,140 B / SelfTest.pck 825,204 B**；**视觉 2 帧已产出**（`t025_telegraph` 抓在预警窗口 `attack_state=telegraphing` / `prey_hp=100`；`t025_hit` 抓在伤害帧后 `hits=1` / `prey_hp=65`）**但判读因 vision 服务 503 记 NOT-VERIFIED**；T023/T024 夹具改为"关掉攻击"（各加声明断言） |
| T026 | **done（2026-10-23）** | 老鼠藏身与掩体规则（**验证型任务：生产代码零改动**）：① **草丛只降低可见性** —— `cover_volumes` 4 个全是 `visibility_factor=0.4` 的 `Area3D`（layer 0、**非实体**），4.5 m 草丛内**看不见** / 开阔看得见、3.0 m 可见 / 3.9 m 不可见（9.0×0.4=3.6 两侧），猫/鼠穿草丛 1 s 位移 **1.653 / 1.071 m**（不被顶住），`AttackSettlement.occluded()` **不把草丛当遮挡**（照样命中 35；真墙对照 `true`）；② **鼠洞阻止猫进入**（**按层**跨墙路由）—— 猫**绕墙 34.68 m**（最近洞口 2.000 m）而鼠**直穿 4.00 m**（最近 0.041 m），`reachable()` 猫 false / 鼠 true，物理推猫**停在 0.703 m**（走过 1.339 m）、鼠**钻到 0.089 m**；③ **躲藏不凭空恢复** —— `HIDDEN` 3.95 s 内 hunger/thirst 不上升不回满、health 不恢复、stamina 最大帧增 **0.00**、衰减 **0.1012 vs 探索 0.0990**（同量级）；**96/96 ×3 + 包内 96/96**；全量回归 **24 套件 2751 条全绿**；包 **Reborn.pck 249,140 B / SelfTest.pck 849,852 B**；**视觉 2 帧判读通过**（① 半透明草丛体量里的鼠 + HUD `seen=false`；② 洞口缝里半个鼠身 + 猫在墙外 `state=alert saw_prey`）；本轮修掉 **4 处夹具/断言缺陷**（层盲的 `map_get_closest_point`、与墙平行的 `_approach_dir`、已释放 AI 引用、鼠背对猫） |
| T027 | **done（2026-10-24）** | 按玩家物种布置测试生态：新组件 `scripts/world/ecology_spawner.gd`（`EcologySpawner`）+ 可玩入口 `scenes/debug/ecology_entry.tscn`（**唯一**把 `ecology_enabled` 打开的场景；`debug_entry.tscn` 保持关闭 → 12 个既有套件/7 个取景分支零影响）。**按玩家物种铺 NPC**：猫玩家→**2 只鼠 NPC**、鼠玩家→**1 只猫 NPC**，换物种**先 `clear()` 再重铺**（旧实例全释放、id 无残留）；**玩家不计入 NPC 数量**（只数本组件铺出的活跃 NPC，并与关卡 `animal_bodies` 存活数 − 1 交叉核对）；**出生周围无即时攻击** = 距离规则（非捕食者 **8.0 m**、捕食者 **14.0 m**，**都大于该物种视距** 6.5 / 9.0）+ 4 s 行为窗口（玩家零伤害、零攻击启动、最近 **3.63 m**）；落点用"现有出生标记 + 环上候选"，按**物种自己的导航层**吸附（层 1 最差 0.050 m / 层 2 最差 0.201 m）、**不改关卡几何**；集成：鼠 NPC 从 1.51 m 逃到 **8.50 m**、玩家猫 0.98 m 扑击**捕获**（生态计数 2→1）、猫 NPC 4.00 → **0.57 m** 接近、近距离**真的打到玩家**（100 → 65 一次 35 不秒杀）；**96/96 ×3 + 包内 96/96**；全量回归 **25 套 2846 条全绿**；包 **Reborn.pck 263,052 B / SelfTest.pck 889,120 B**；**视觉 2 帧判读通过**；顺带**修掉 1 个真实导出缺陷**（默认候选按 `.tres` 过滤 → 包里是 `.res`/`.remap` → 包内列表为空） |
| T028 | **awaiting-review（2026-10-25）** | 第一轮概念试玩（**自测半边完成、U01 真人半边 NOT-RUN**）：新增 `tests/tool_t028_walkthrough.gd`（`extends SceneTree` 走查工具：把玩家 `player_controlled=false`，每帧"朝下一个**按层**导航路点 `look_at` + `move_intent=(0,-1)`"驱动），在可玩入口 `scenes/debug/ecology_entry.tscn` 上跑两条真实路线。**猫线**：11.18 m 内 **0.90 s** 看见鼠（`sense: seen=true`）→ **1 次扑击 3.9 s 捕获**（`route_len 10.96 / straight 11.18 / ratio 0.98`、`prey_states=["explore","alert"]`、`prey_min_gap 1.10 m`、捕获后生态 2→1）。**鼠线**：0.43 s 被猫看见（探针复核 = `alert/saw_prey` @8.92 m ≈ 猫 `vision_range 9.0` 的**视觉**触发，**不是**初始化 alert）→ **14.1 s 进洞**（`hole_gap 0.24 m`；逃段 `21.39 m / straight 21.12 / ratio 1.01` = 几乎直线）、**猫最近只到洞心 6.99 m**、12 s 内回 `explore` 且 `giveups=1`；两线 `hp 100→100`。**W1~W4 4/4 ×3 次源码 + 包内 4/4**；全量回归 **25 套 2847 条全绿**；包 **Reborn.pck 263,052 B（与 T027 相同 → 生产代码零改动）/ SelfTest.pck 905,604 B**；视觉 2 帧（`t028_cat_chase` 210,342 B 判读通过；`t028_mouse_hole` 221,923 B **只部分确认**：墙+缺口+HUD `pos:(26.68,0.12,19.00)`=洞口坐标，角色辨识 vision 未确认 → 不编造）。**暴露 2 个体验问题候选交 T029**：A 鼠 `ALERT` 0.3 s 在猫 `sprint 4.5` 下形同虚设；B 猫 AI 追击**从不 `want_sprint`**（walk 1.8 < 鼠 sprint 3.0 → 追不上） |
| T030 | **done（2026-10-27）** | `Docs/Evidence/T030.md`、`Docs/Tasks/T030.md`、`autoload/game_state.gd`、`scripts/core/life_cycle.gd`、`scripts/core/main_entry.gd`、`scenes/core/main.tscn`（占位 → 真入口）、`tests/run_t030_lifecycle.gd`（111 条） | **生命周期状态与事件记录**：`LifeCycle` 四态（`ALIVE/SETTLING/SELECTING/SPAWNING`）+ 迁移表，非法迁移**不改状态/不写档案/不占 `LifeId`**；`GameState` 存档案（策划 §9.5 全字段）与事件（`seq` 单调、封顶 1024、跨世保留）、`LifeId L%04d` 单调；**死亡只结算一次**（连打 3 次 → 1 条档案 / 1 次信号）；结算期冻结世界时间与输入、**不留尸体**、NPC 数不变；`main.tscn` 改为真入口（关卡/HUD/状态栏运行期构建 → T013/T018/T026 旧断言继续全绿）；**111/111 ×3 + 包内 111/111，全量 27 套 2998 条全绿**；包 **289,832 / 968,900 B**；视觉 `t030_settled` 判读通过。**顺带修掉 2 个真实缺陷**：树外绝对路径取 autoload 报错、包内 `*.tres.remap` 导致 0 物种。遗留：`test_mode=true` 临时开发态（正式解锁属 T031）、真实按键选择 NOT-RUN |
| ART01 | **done（2026-10-21，系统时钟）** | `Docs/Evidence/ART01.md`、`Docs/Tasks/ART01.md`、`Tools/Blender/art01_bush_001.py`、`Game/Reborn/assets/environment/sm_bush_001.glb`、`tests/run_art01_bush.gd`、`tests/tool_capture_art01.gd` | **AI 建模工作流打通 + 首个静态资产接入**：草丛掩体 `ENV_BUSH_001`（2040 tris、2 材质、双面、**零碰撞**）替换半透明绿盒子，并补上**溪边掩体原本完全没有视觉**的缺陷；`tool_make_courtyard.gd` 生成器接入（**不手改 .tscn**）；**83/83 + 全量 29 套 3081 条全绿**；3 轮返工（泥土墩过高→躲进草丛相机在土里、草叶像"板条"、密度/取景缺陷）；**不是正式美术 approved**，也**没有**越过 P6 阶段门 |
| ART03-② | **done（2026-10-21，系统时钟；未 approved）** | `Docs/Tasks/ART03_BOULDER.md`、`Docs/Evidence/ART03_BOULDER.md`、`Tools/Blender/art05_boulder_001.py`、`Art/Exports/Environment/SM_Boulder_001.glb`、`Game/Reborn/assets/environment/sm_boulder_001.glb`、`tests/tool_capture_art05.gd` | **溪边巨石换成真实岩石**：Poly Haven `boulder_01`（CC0）实测 66,122 tris / **1.27 m 米制（推翻旧结论"12.7 m 需缩放"）** → 焊接后单轮减面 **7,500 tris** → `_mk_boulder()` 接入 `CreekBoulder`（视觉 .glb、碰撞 Godot 侧 `BoxShape3D` = 视觉 AABB）；生成器 7/7 + **全量 29 套 3,127 条全绿**；实机 4 机位自查通过（无浮空/陷地）；修掉两个真缺陷（glTF 接缝拆点致减面卡死、T012 溪缝断言依赖导航 tie-break） |

**未完成**：游戏玩法实现（T031 起：地点发现 / 档案页 / 重生 / 存档）、正式角色与骨骼资产（P6）、真实按键输入验证、**T028 的 U01 真人半边**、**T029 的冲刺平衡决策**。**T031～T063 全部 pending。**

**T030 的边界声明**：① 只做生命周期与记录，**没做**结算页美术/动效（P6/T032）、存档（T037）、正式解锁条件（T031）；② `MainEntry.test_mode = true` 是**临时开发态**，正式解锁接入后必须改 `false`；③ 真实按键（`1`/`2`）选择 **NOT-RUN**，只验证了键码=引擎常量与逻辑路径。
**P0 完成（T001～T007）、P1 完成（T008～T013）、P2 完成（T014～T022）、P3 完成（T023～T029；T028 真人半边 / T029 冲刺平衡挂 U01）、P4 进行中（T030 done）** → **下一步 T031 地点发现和老鼠解锁**。

> ## ⚠ 本次最重要的教训
>
> **数值断言全过 ≠ 画面正确。** T002 的 18 条断言长期全绿，但场景**没有光源、没有环境、
> 相机未激活**，导出程序窗口是深色空白。视觉工具一接入就发现了。
> 完整经过见 `Docs/Evidence/Visual-Verification.md`。今后"画面正确"必须有视觉证据。

## 现有产物

```
Game/Reborn/                       正式 Godot 工程（纯文本，agent 可直接编写）
├── project.godot                  InputMap 16 动作（10 操作 + **6 调试 F1~F6**）、4 碰撞层、forward_plus
├── export_presets.cfg             两个预设：Windows Desktop（发布）/ SelfTest（含测试）
├── autoload/world_director.gd     世界时间单例
├── scenes/core/main.tscn          主入口
├── scenes/maps/l_movement_lab.tscn  10×10m 地面、PlayerStart、**Player（= 猫 AnimalBody 实例，T009 换的）**、
│                                    100cm 标尺、**ProbeAsset（T005 资产：1 m 立方体 + BoxShape3D 碰撞）**
├── scenes/maps/l_move_fixtures.tscn  **移动试验世界（25° 坡道 / 猫低顶 42 cm / 墙角 / 50 cm 高台 / T010 加：鼠洞 24×30 cm、鼠低顶 15 cm）**
├── scenes/maps/l_courtyard.tscn       **生态灰盒关卡（T011：80×80 m、四区域、树根屏障 + 鼠洞、溪边缝隙、补给点）**
├── scripts/characters/step_climb.gd      **台阶抬升组件（自实现 MaxStepHeight；T009 修正两处判据）**
├── scripts/characters/animal_body.gd     **身体与移动控制器：成型/走跑蹲跳/相机（配置驱动，无物种名分支）**
├── scripts/data/species_config.gd        **物种配置类（字段按 TechnicalDesign §3）**
├── resources/species/cat.tres / mouse.tres  **物种数据真源（改数值只改这里）**
├── scenes/characters/animal_body.tscn    **身体场景（胶囊 + 灰盒 BodyMesh + 相机；不设 current，由 `make_camera_current` 决定）**
├── assets/tests/sm_probe_cube.glb / sk_rig_probe.glb + .import   资产与导入设置（.import 纯文本）
└── tests/
    ├── run_t002.gd                场景/出生/碰撞断言（18 条）
    ├── run_t005_asset.gd          静态资产往返断言（50 条）
    ├── run_t006_rig.gd            骨骼往返断言（65 条）
    ├── run_t008_species.gd        **物种配置/身体/台阶能力断言（114 条）**
    ├── run_t009_cat_movement.gd   **T009 猫移动与相机断言（81 条：速度/潜伏/斜坡/墙角/跳跃）**
    ├── run_t010_mouse_movement.gd  **T010 鼠移动与通道尺度断言（95 条：三档速度/窄缝/低顶/禁高跳）**
    ├── run_t011_greybox.gd        **T011 生态灰盒断言（210 条：四区域/补给走廊/§8.2 五条结构 + 6 组物理探针）**
    ├── run_t012_navigation.gd     **T012 导航可行性断言（79 条：双图参数/分层路径矩阵/结构判据 + 4 组真实胶囊行走）**
    ├── run_t007_input.gd          输入链路断言（22 条；现在跑在正式猫控制器上）
    ├── probe_step_height.gd       台阶能力探针（6 条判定；**现调用 StepClimb 组件**）
    ├── debug_stepup.gd            台阶逐条件诊断工具
    ├── tool_edit_lab_scene.gd     场景修补工具（不入树 + 无意外变更自检）
    ├── tool_add_probe_asset.gd    把探针资产接入 lab（幂等 + 自检）
    ├── tool_make_move_fixtures.gd **T009 生成移动试验世界（幂等 + 重载核对几何）**
    ├── tool_set_lab_player.gd     **T009 把 lab 的灰盒玩家换成正式猫（幂等 + 无意外变更自检）**
    ├── tool_make_courtyard.gd     **T011 生成生态灰盒关卡（幂等 + 重载核对几何 + 走廊自检）**
    ├── tool_dump_scene_tree.gd    dump 任意 PackedScene 真实结构（含骨骼/动画/蒙皮）
    ├── run_t023_cat_ai.gd        **T023 猫 NPC 巡游与发现断言（177 条：巡游/发现/警戒/接近/与鼠对照/集成）**
    ├── run_t024_chase_search.gd  **T024 追击 / 搜索 / 放弃断言（136 条：接口/追击/搜索/超时/洞口等待/不读实时坐标/逃脱账本/集成）**
    ├── run_t025_attack.gd        **T025 NPC 攻击与玩家受伤断言（175 条：接口/预警命中/躲开绕墙/恢复间隔/朝向/受伤通道/鼠不攻击/集成）**
    └── tool_capture_render.gd     引擎侧渲染捕获 + 像素统计（不能 headless；`-- t005` / `-- t006` / `-- t009` / `-- t010` / `-- t011` / `-- t012` / `-- t018` / `-- t020` / `-- t021` / `-- t022` / `-- t023` / `-- t024` / `-- t025`）

Art/Blender/Tests/StaticProbe_v001.blend   T005 可编辑源（LFS；**逐字节不可复现**）
Art/Exports/Tests/SM_ProbeCube.glb         T005 导出产物（LFS，sha256 629750364847…，**可复现**）
Art/Blender/Tests/RigProbe_v001.blend      T006 骨骼源（LFS，467,364 B）
Art/Exports/Tests/SK_RigProbe.glb          T006 导出产物（LFS，sha256 446bf3b67c90…）
Tools/Blender/t005_static_probe.py / t006_rig_probe.py   Blender 无头脚本（建模/重开校验/导出/GLB 自检）
Art/Probes/t005_lab_probe_render.png       正交对照帧（T005 视觉证据，LFS）
Art/Probes/t006_rig_t000.png / t050.png    骨骼两帧位姿（T006 视觉证据，LFS）

Builds/P0-Win64/                   导出产物（.gitignore 已排除；**T029 已两预设重导出并复验：Reborn.pck 263,436 B / RebornSelfTest.pck 921,704 B**）
├── Reborn.exe / Reborn.pck / Reborn.console.exe
└── RebornSelfTest.exe / .pck / .console.exe
```

**验收命令**（改完脚本先 `--check-only`）：
```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'

# 工程内断言
& $g --headless --path $proj --script 'res://tests/run_t002.gd' --quit-after 1200
& $g --headless --path $proj --script 'res://tests/run_t005_asset.gd' --quit-after 20000
& $g --headless --path $proj --script 'res://tests/run_t006_rig.gd' --quit-after 20000
& $g --headless --path $proj --script 'res://tests/run_t008_species.gd' --quit-after 20000
& $g --headless --path $proj --script 'res://tests/run_t007_input.gd' --quit-after 20000
& $g --headless --path $proj --script 'res://tests/probe_step_height.gd' --quit-after 20000
& $g --headless --path $proj --script 'res://tests/run_t020_perception.gd' --quit-after 180000
& $g --headless --path $proj --script 'res://tests/run_t021_capture.gd' --quit-after 180000
& $g --headless --path $proj --script 'res://tests/run_t022_loop.gd' --quit-after 300000
& $g --headless --path $proj --script 'res://tests/run_t023_cat_ai.gd' --quit-after 300000
& $g --headless --path $proj --script 'res://tests/run_t024_chase_search.gd' --quit-after 300000
& $g --headless --path $proj --script 'res://tests/run_t025_attack.gd' --quit-after 300000
& $g --headless --path $proj --script 'res://tests/run_t026_cover.gd' --quit-after 300000
& $g --headless --path $proj --script 'res://tests/run_t027_ecology.gd' --quit-after 300000
& $g --headless --path $proj --script 'res://tests/run_t029_sprint_chase.gd' --quit-after 300000

# 走查工具（T028，切换玩家物种跑两条真实路线；不是断言套件）
& $g --headless --path $proj --script 'res://tests/tool_t028_walkthrough.gd' --quit-after 300000

# 包内断言（必须用编辑器二进制，导出产物拒绝 --script）
& $g --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
    --script 'res://tests/run_t008_species.gd' --quit-after 20000

# 看导入资产的真实结构（骨骼/动画/蒙皮也能 dump）
& $g --headless --path $proj --script 'res://tests/tool_dump_scene_tree.gd' --quit-after 600 `
    -- 'res://assets/tests/sk_rig_probe.glb'

# 视觉（**不能 headless**；`-- t005` 正交对照，`-- t006` 骨骼两帧，`-- t020` 感知三帧，`-- t021` 扑击/撞墙/命中三帧，`-- t022` 死亡 HUD / 重开后捕获两帧，`-- t023` 巡游 / 警戒后接近两帧，`-- t024` 追击 / 失视后搜索两帧，`-- t025` 预警 / 命中两帧，`-- t026` 草丛掩护 / 洞口外等待两帧，`-- t027` 猫玩家 / 鼠玩家两帧，`-- t028` 猫追鼠 / 鼠在洞口两帧，`-- t029` 追击冲刺一帧，`-- t030` 选物种 / 存活 / 结算三帧）
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 1200 -- t006
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 30000 -- t020
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 60000 -- t021
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 3000 -- t022
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 9000 -- t023
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 24000 -- t024
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 2000 -- t025
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 2000 -- t026
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 3000 -- t028
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 3000 -- t029
```
退出码 0 = 通过。**必须加 `--quit-after`**，否则脚本出错会挂死。

## 关键环境事实

- **Godot**：`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
  （**外层同名项是目录不是文件**）；版本 `4.7.2.stable.official.ed1daf0bf`。
- **单位**：Godot 用**米**，`Parameters.md` 是**厘米** → **÷100**。
  `CapsuleShape3D.height` 是**含两端半球的总高**（Cat：`radius=0.16, height=0.48`）。
- **键码**：手写 `project.godot` 要写裸数字，**必须实测核对**（Esc=4194305、Shift=4194325、Ctrl=4194326）。
- **Git 推送**必须走代理 `127.0.0.1:7897`（直连 github.com 超时），**未写入全局配置**；
  2026-10-27 已在**仓库本地**配好 `http.proxy` / `https.proxy` = `http://127.0.0.1:7897`，
  并设 `lfs.https://github.com/XwenHaHa/Reborn.git/info/lfs.locksverify=false`
  —— **不设这一条 `git push` 会先卡在 LFS 锁校验超时**（远端 LFS locking API 经本机代理不可达，本仓库也没用锁）。
- **视觉工具可用**：`E:\claude-vision-skill\vision.js`（先用已知答案图 `Art/Probes/vision_probe_red_blue.png` 自检）：
  `node E:\claude-vision-skill\vision.js <图片> "<中文问题>"`。
  T025 期间曾返回 **API 503 `auth_unavailable`**（当时记 NOT-VERIFIED）；**T026 期间已恢复**（两帧判读通过）。
  **遇到工具侧报错要如实记录并重试，不得编造画面判断**；它逐字读 HUD 很准，可当"画面里到底写了什么"的独立核对。
- **导出产物拒绝 `--script` 与位置参数**（官方模板编译时带 `disable_path_overrides=yes`，是 Godot 有意设计）。
  想在包内跑断言只能用 `--main-pack` + 编辑器二进制。
- **`debug/export_console_wrapper` 是枚举**：`No=0 / Debug Only=1 / Debug and Release=2`；写 `1` 时 release 不出 `.console.exe`。
- 硬件：i7-11800H / 31.75 GB / T600 Laptop 4GB / Win10 19045；C: 仅剩 13.7 GB。
- **Play 不能靠返回值判断**：Godot 4.7 的 `AnimationPlayer.play()` 返回 **void**（不是 `Error`）→ 查 `is_playing()` / `current_animation`。
- **动画轨道插值 API**：`Animation.rotation_track_interpolate(track, t)`（**没有**通用的 `track_interpolate`）；
  同族还有 `position_/scale_/blend_shape_/value_/bezier_track_interpolate`。
- **骨骼姿态含静止位姿**：`Skeleton3D.get_bone_pose_rotation()` 返回**含 rest 的**父骨相对旋转
  （实测 t=0 时腿骨就是 −90° = rest），"作者转了多少度"要**从动画轨道数据**算，别直接读姿态角。
- **导入会重采样动画**：按 `animation/fps`（默认 30）重采样并**丢掉部分键**（实测 t=0.5 不是键）→ 源里的极值被削约 1–2%。
- **`.blend` 不可逐字节复现**（Blender 写时间/会话元数据）；**`.glb` 可复现**（两次 SHA256 相同）→ 验收以 `.glb` 为准。
- **新增/修改 `class_name` 脚本后必须先 `--import`**：全局类名缓存在 `.godot/global_script_class_cache.cfg`，
  否则引用方报 `Parse Error: Identifier "Xxx" not declared in the current scope`（2026-10-13 实测踩到）。
- **`AnimalBody` / `SpeciesConfig` / `StepClimb` 已就位（T008/T009）**：物种差异**只在** `resources/species/*.tres`；
  系统代码里不写物种名分支（有静态断言守着）。
- **相机偏移语义（T009 决策 D1）**：`camera_offset_z` 按 **本地 +Y（竖直）** 实现 —— 依据是 `Parameters.md`
  源自 UE 参数表（UE 里 Z 是上方向），第一人称眼高必须竖直；字段名沿契约不变，断言锁死轴向。
- **新增参数（T009 决策 D2）**：`crouch_half_height`（猫 0.15 / 鼠 0.06）—— `Parameters.md` 原本没有蹲姿尺寸，
  **待负责人并入正式起测值**。
- **`StepClimb` 两处判据在 T009 被实测推翻并修正**（详见 `Docs/Evidence/T009.md` §5）：
  ① 落点高度必须来自**接触面**（用 `get_travel()` 会因"形状越小停得越早"把鼠的 3 cm 台阶算成 3.26 cm 而拒绝）；
  ② **斜坡不算台阶**（只按"真正阻挡本次运动的接触面是否可站立"判；`n·dir<0` 这一条不能省，否则连正常台阶都上不去）。
- **包内跑不了源码级静态检查**：`.pck` 里只有编译产物，读不到 `.gd` → 相关检查在包内如实标
  `STATIC|NOT-APPLICABLE`（不假装通过、也不误判为失败）。
- **实例子节点的属性覆盖不会被 `PackedScene.pack()` 序列化**（T009 实测）：改子节点 `Camera3D.current`
  存盘文件里**没有这行**，重载回来相机不 current（视觉捕获会黑屏）；要在场景里表达，就用**节点自己的导出属性**。
- **新关卡尺度常量（T010）**：鼠洞 **0.24 × 0.30 m**、鼠低顶净空 **0.15 m**（属**试验世界设计**，不是物种参数；
  记在 `Docs/Parameters.md`）。改 `tool_make_move_fixtures.gd` 的常量时 T010 的尺度断言会一起失败。
  **`0.15 m` 待负责人确认为关卡设计基线。**
- **视觉判读的取景前提（T010 实测）**：相机要**正对**主体所在通道，否则洞口侧壁会把主体完全遮住、
  模型只会答"洞里是空的"（详见 `Docs/Commands.md` §8 与 `Docs/Evidence/T010.md` §5.1）。
- **感知已落地（T020）**：`Perception`（`scripts/systems/perception.gd`）挂在 `AnimalBody` 下、**只观察**；
  做决定走既有 `alert_for(position, reason)`，NPC **不直接写** `move_intent` 或生存值。
  噪声总线是 `WorldDirector.noise_emitted(origin, loudness, source_id)`，**每条只带发生位置 + 时间**、不跟随声源。
- **脚步噪声是"事件"不是"每帧"**：`AnimalBody._update_footsteps()` 用世界时间差 + 实际速度算间隔
  （`footstep_interval_base` 0.5 s 按速度反比缩放、夹在 0.1–1.5 s），**暂停不出声**；实测 121 帧只出 4 次。
- **导航区域读的 meta 键是 `species_id`**（`tool_make_courtyard_nav.gd` 写的），**不是 `species`**；
  Godot 里 `get_meta(name, null)` 的 null 默认值**等同报错**（不是"返回 null"）——读 meta 一律先 `has_meta()`。
  T020 修掉过这个坑：猫因此退回层 1、**误用鼠的导航面**。重生成关卡后**必须重烤导航**（`tool_make_courtyard.gd` → `tool_make_courtyard_nav.gd`）。
- **T020 新增 4 个实现默认值**（`Parameters.md` 原本没有）：`footstep_interval_base` 0.5 s、`flee_timeout` 3.0 s、
  `reach_tolerance` 0.5 m、`hide_arrive_radius` 0.30 m —— **待负责人并入正式起测值**。
- **T021 捕获已落地**：捕食者身上挂 `CaptureSettlement`（`scripts/systems/capture.gd`），**只观察 + 结算**；
  `AnimalBody` 用 `enum ACT`（`IDLE/INTERACTING/POUNCING/RECOVERING/DEAD`）走扑击状态机，
  `mark_captured()` **幂等**且**不销毁节点**（网格隐藏 / 层 0 / 出组 / 停物理）。
  捕获食物挂**世界根**、`kind=food` + `food_type=MEAT`、容量 1、300 s 失效；是否可食由 `SpeciesConfig.allowed_food_types` 决定（**不写物种名分支**）。
- **取景工具会跨关卡污染**（T021 实测）：`tool_capture_render.gd` 的 `-- t021` 加载 `l_movement_lab.tscn`，
  该场景自带 `Player`（= 猫 `AnimalBody` 实例，原点附近，`collision_layer=2`）会落进取景场并被读成「第二个胶囊」。
  已加 `_t021_isolate_lab()` 隐藏 lab 可视物 + 把 `Player` 移出碰撞层并停物理；**后续任何「在 lab 里搭探针场」的取景都要先隔离**。
- **重开后不能留失效引用**（T022 实测缺陷）：`InteractionDetector.current_target()` 对**已释放目标**先清空再返回 `null`；调试 HUD 的 `_resource_for_display()` / `_resource_units()` 用 `is_instance_valid()` 跳过失效实例 —— 否则重开后每次刷新 HUD 都会打脚本错误。
- **"SUMMARY 全绿"不等于"日志干净"**：套件读不到自己的 stderr —— 每次验收都要另跑 `Select-String -Pattern 'SCRIPT ERROR' <日志>` 并记录条数（T022 就是这样抓到 6 条/次的真实脚本错误的）。
- **重开入口（T022）**：`DebugEntry.restart_round(reason)` + 输入动作 `debug_restart`（**F6 = 4194337**）；顺序固定为 释放旧玩家 → 释放旧关卡 → `WorldDirector.reset_for_new_game()` → 重建关卡 → 重新 `switch_species()`；**只有死亡态** HUD 才显示提示。
- **导航代理要挂在"脚下"**（T023 实测缺陷）：`NavigationAgent3D` 继承 `Node`（**没有自己的变换**），位置取自**父节点**。挂在胶囊中心时，与导航面的垂直差会超过 `path_desired_distance`(0.10)，`get_next_path_position()` **永远**返回"脚下的投影起点"（水平差 ≈ 0）→ **高个子物种原地抖、零位移**（猫 0.24 m 中招、鼠 0.09 m 侥幸没事）。现在统一挂到 `AnimalBody/NavOrigin`（`Marker3D`，本地 y = −`capsule_half_height`）。
- **"有目的地"≠"会动"，"到不了"≠"走了直线"**：`_advance_along_path()` 的"下一点在脚下 → 朝目标走"兜底**只在 `get_current_navigation_path()` 非空时**生效；否则"不可达目标"会被走成"可达"（T019/T022 各挂 4/7 条断言就是踩在这里）。

## 美术流水线（ART01 已打通，2026-10-21）

- **Blender 侧**：`Tools/Blender/art01_bush_001.py`（确定性 seed、程序化建模、无外部贴图）→
  `Art/Blender/Environment/ENV_BUSH_001_v00{1,2,3}.blend`（**每轮返工存新版本**）→
  `Art/Exports/Environment/SM_Bush_001.glb` → `Game/Reborn/assets/environment/sm_bush_001.glb`。
- **资产硬契约**：原点在地面中心（`AABB.position.y=0`）、包络 ≤1.45 m 半径、高 ≤0.90 m、
  泥土垫顶面 **≤0.12 m**（否则玩家躲进草丛时相机在土里，v001 就是这么错的）、2 材质槽、
  **双面 `CULL_DISABLED`**、**零碰撞**、不进 `nav_source_courtyard`、三角形 ≤3000。
- **视觉捕获**：`tests/tool_capture_art01.gd`（自己搭光/地面/1 m 立方体/猫鼠比例胶囊），
  `--quit-after 8000 -- art01-preview`（7 机位）或 `-- art01-level`（关卡 3 机位）。
  **`--quit-after 2400` 会在第 3 个机位前被掐断**（实测）。
- **叶形必须在近景判读**：单片草叶 1–3 cm，720p 远景下只有 1–3 px，远景点位判"直板条"是**分辨率限制**，不是模型结论。
- **`CharacterBody3D` 不会自己下落**（运动学体），下落探针必须逐帧喂速度 + `move_and_slide()`；
  否则会得到 `landed == start` 的假"通过/失败"。
- **重跑 `tool_make_courtyard.gd` 会清掉 `NavigationRegion3D`**（`NavigationMesh` ext_resource 消失）→
  必须紧接着跑 `tool_make_courtyard_nav.gd`；重烤后 nav `.tres` 若 `git status` 无改动，说明几何确实没变。

## 美术：模型质量专项（ART02，2026-10-21）

- **猫的视觉已从胶囊换成真实模型**：`Tools/Blender/art02_cat_001.py` →
  `Art/Blender/Cat/CAT_BODY_001_v00{1..8}.blend` → `Art/Exports/Cat/SM_Cat_001.glb`
  → `Game/Reborn/assets/characters/cat/sm_cat_001.glb`（9568 tris / 2 材质槽 / 2048² 烘焙 albedo）。
- **接入方式（配置驱动，无物种名分支）**：`SpeciesConfig.visual_scene` → `AnimalBody._rebuild_visual()`。
  胶囊网格 `BodyMesh` **保留但 `visible=false`**（它是尺寸代理），所以 T009/T013 的
  "网格尺寸 == 胶囊尺寸"断言继续成立；蹲姿用 `scale.y = crouch_height/capsule_height`（0.625）近似，
  脚底永远贴胶囊底面。**改 `cat.tres` 删掉 `visual_scene` 一行即可回退到胶囊**。
- **资产契约**：原点在四脚着地的地面中心（`aabb.position.y≈0.0004`）、面朝 `-Z`、
  0.1849×0.3894×0.6011 m、高 ≤0.48（胶囊总高）、**零碰撞**、三角形 ≤10000。
- **烘焙三坑**（详见 `Docs/BlenderPipeline.md` §ART02）：`ShaderNodeTexImage` 的输入只有 `Vector`；
  烘焙目标节点**必须先不连** Base Color；眼/鼻/耳内必须在 **remesh 之后**才贴（否则被平滑吃掉）。
- **游戏内取证工具**：`tests/tool_capture_art02.gd`（真实生态入口 + 鼠玩家第一人称 + 猫固定 1.58 m，
  同一帧先退回胶囊拍 before 再装回模型拍 after）→ `Art/Probes/art02_ingame_{before,after}.png`。
- **回归**：`run_art02_cat.gd` 46/46 + t008/t009/t010/t013×2/t021/t026/t027/art01 全绿 = **1122 条**。
  **未跑**：全量 27 套的其余套件（t002/t005/t006/t007/t011/t012/t014～t020/t022～t025/t029/t030，以及 `tool_t028_walkthrough`）与打包/导出复验。
- **仍未达专业水准**：四轮视觉判读持续指出"耳比例像兔耳、四肢像棍、颈胸过渡生硬、表面像哑光塑料"。
  继续调参只会逼近程序化放样的上限 → 下一步建议见 `Docs/Evidence/ART02.md` §7
  （**首选**：引入有版权的专业猫基础模型或请美术雕刻基底；**需负责人授权**）。
- **鼠仍是胶囊**：按 `modeling2.md` §五，试点未正式验收前不批量替换。

### V009 基础形体重建（2026-10-21，**not-accepted**）

- **换方法重做**：`Tools/Blender/art02_cat_v009.py`——躯干+四肢+尾巴用「一根骨架 → `SKIN` 修改器 →
  1 级细分 → 焊接 → bmesh 松弛 → 宽高斯解剖塑形」，头部 12 截面放样 + 剖面调制，
  眼睛有上下眼睑环，耳朵是有厚度耳壳；**完全不用 voxel remesh / decimate / 噪声位移**
  （自检行：`pipeline=skin+subsurf+loft|remesh=False|decimate=False|noise_displace=False`）。
- **量化结果**：5296 tris / **99.3% 四边形** / **0 非流形** / 4 个毛发壳（躯干+头+2 耳）/
  `min_z=0.000000` / 高 0.4056 m；产物在 `Art/Blender/Cat/CAT_BODY_001_v009{,r2,r3}.blend`
  与 `Art/Staging/ART02_V009/`。
- **仍不达标（3 轮返工后）**：横向环状台阶（成因是 Skin 逐关节半径起伏，松弛加强 3 倍仍在）、
  四肢关节不可辨、脚掌无趾部。判读原话："躯干像一节一节横向拼接的热狗""玩具/香肠模型"。
- `modeling3.md` §6 的**停止条件已触发** → 不再调参。
- **正式资产仍是 V008**：`cat.tres` / 导出 / Godot 资产**全部未改**，`run_art02_cat.gd` 46/46 仍绿。
- **待负责人决策**（最小请求）：① 授权获取/采购可商用短毛猫基础模型（首选，接入链路已就绪）；
  ② 或安排美术在 Blender 雕刻/重拓扑。**不要**再让 agent 在这套脚本上调参。
- 同角度对比：`Art/Staging/ART02_V009/ART02_V008_vs_V009_{views,sheet}.png`（两套渲染用同一套机位/灯光/采样）。

### ART03 Reference Lock：参考库 + 基础模型选型（2026-10-21，**awaiting-review**）

- **强制流程已落地**：`reference_pending → reference_confirmed → modeling → review → approved`
  （`Docs/ART_ASSET_SPEC.md` §5）。**参考未确认前不得开展正式建模**；`approved` 只能负责人置位。
- **新文件**：`references/ART_STYLE_GUIDE.md`（风格基线=写实偏风格化，待确认）、
  `references/reference_manifest.json`（5 类资产 / 16 个候选，带 URL/作者/许可/面数/是否已下载）、
  `Docs/ART_ASSET_SPEC.md`（逐资产规格 + 预算 + 评分 ≥85）、`Docs/ART_ASSET_AUDIT.md`（现状审计）、
  `Docs/THIRD_PARTY_ASSETS.md`（第三方登记 + 署名义务）、`Docs/ART_ASSET_CHANGELOG.md`。
- **能力实测（更新）**：联网可用；Poly Haven 匿名直链可下载（`boulder_01` CC0 glTF 1K 已下载，字节数与 API 一致）；
  **Sketchfab 可用"已登录浏览器会话 + API token"取签名直链下载**（会话 cookie 不能直接调 API，401）。
  本轮实际下载并校验 4 个候选：`cat_fripouille`(FBX+4 贴图)、`mouse_arribadaclub`(glb)、`stump_callum_arb`(glb)、
  `wall_stefan_wr`(glb)，全部落在 `references/_downloads/`（已 gitignore）。**令牌未落盘、未入日志、未提交**。
- **真实网格实测**（`references/reference_measurements.json`，Blender 3.3.1 导入读回）：
  猫 **8,376 tris / 33 骨 / 0 动作 / 3 材质槽 / 尺度非米（15.86 单位，需 ≈0.0315 缩放）/ 最长轴 X 需转向**；
  鼠 **10,000 tris / 1 槽 / 3×1024² / 无骨骼 / 真实尺度 0.068×0.138×0.061 m**；
  树桩 **39,122 tris（超预算 2.6×）/ 腔体净空 ≈0.238×0.173 m（未达 0.24×0.30）**；
  石墙 **2,000 tris / 2 槽 / 7 个独立模块 / 尺度像 cm**。四个文件的 faces 与 API 完全一致。
- **未取得**：`mouse_charliecatling`（403/400，唯一带 3 段动画的鼠）、`cat_bigcat_gbarzu`（唯一带 2 段动画的猫，未下）。
- **选型建议（未确认）**：猫→`cat_fripouille`（8.4k 写实无骨骼）或 `cat_bigcat_gbarzu`（58.6k 带 2 段动画）；
  鼠→`mouse_charliecatling`（6.2k 带 3 段动画，**许可为 Free Standard 需核对**）否则 `mouse_arribadaclub`（CC-BY 10k）；
  洞口→`stump_callum_arb`（39k 带洞，需减面+量净空）；巨石→`boulder_01`（CC0，需减面 + 12.7 m→1.2 m 缩放）；
  围栏→`wall_stefan_wr`（2k，作者自述模块化石墙）。
- **未改动任何正式游戏资产**：`git status` 对 `Game/` 为空；Godot 侧 46/46 仍绿。
- **待负责人确认 5 项**：① Sketchfab 下载授权（或你手动放 `references/_downloads/`）；
  ② 是否接受 CC-BY 署名；③ 风格基线（写实偏风格化 vs 卡通）；④ `boulder_01` 缩放 0.09× 是否可接受；
  ⑤ 猫走"自带骨骼候选"还是"无骨骼 + 重新绑骨（P6 T047）"。
- **2026-10-21 负责人决策**：猫用 `cat_fripouille`；其余也从已下载候选取
  （鼠 `mouse_arribadaclub`、洞口 `stump_callum_arb`、围栏 `wall_stefan_wr`、巨石 `boulder_01`）→
  manifest 里 5 类资产全部 `reference_confirmed`，猫进 `modeling`。
- **猫的第一个合规产物**：`Tools/Blender/art04_cat_from_ref.py` → `Art/Exports/Cat/SM_Cat_002.glb`
  （8,376 tris / **2 槽** / **33 骨** / 体长 0.596 m / 高 0.307 m / 贴地 / 面朝 +Y / 法线 G 已翻转）。
  **已接入**：`cat.tres` → `sm_cat_002.glb`，`run_art02_cat.gd` **46/46 PASS**；
  游戏内实拍 `Art/Probes/art02_ingame_after_v2.png`（正面朝向、四脚落地）。
  **看图方式已变**：`Read` 直接读 PNG（多模态可用），不再依赖 `vision.js`。
  仍缺：Idle/Walk/Run/AttackCue 动画（P6 T048/T049）；鼠/洞口/围栏/巨石尚未产出资产。

## 下一步（按建议优先级）

1. **T031（地点发现和老鼠解锁）**（2～4h，前置 T030 **已满足**）：给鼠洞指定**稳定 ID**；发现事件写进 `GameState` 长期记录，**不按"刷捕猎"解锁**；同时把 `MainEntry.test_mode` 从临时 `true` 接到正式解锁链上。
   T032（生命档案与结算页）/ T033（正式物种选择与重生）**已有底座**：`GameState.life_records`/`events_for()` 与 `LifeCycle` 四态可直接用。
   必须带上 T029 的两条**待决策**（`Docs/Evidence/T029.md` §6）：**① 鼠洞不是安全区**（洞里能被打中）/ **② 冲刺会把 AI 冲出无护栏平台**（`split_platform` 实测 `y=-210 m`）。
   **U01 真人半边仍 NOT-RUN**：2～3 位外部试玩者的最小请求在 `Docs/Tasks/T028.md` §7 与 `Docs/Evidence/T028.md` §10，等负责人安排。
2. 带上 T027 的 3 条待定（`Docs/Evidence/T027.md` §7）：**正式启动链已落地（T030）**、**区域 NPC 账本属 T035**、
   **NPC 出生点正式布置**（本轮未改关卡几何；代码已支持 `npc_spawn_points` 组）、**猫 : 鼠 NPC 配比 1 : 2** 是否最终（T029 按试玩调）。
3. 带上 T026 的两条新发现（`Docs/Evidence/T026.md` §7）：**洞里"看得见但够不到"** —— **T029 已实测"洞里能被咬"**（`Docs/Evidence/T029.md` §6 ①，
   洞外 0.79 m 的猫咬死洞里 0.24 m 的鼠）→ 已升级为待决策项；**`AnimalAI.reachable()` 判据① 层盲**（判据② 带层故结论不变，但① 只会造成假否 → **会影响 T019/T023/T024 共享代码**）。
4. 带上遗留项：**猫跨 0.50 m 屏障是否加 `NavigationLink3D`**（`Docs/Evidence/T013.md` §9）；
   **T020 的 4 个感知默认值**与**近距豁免是否受视锥限制**（`Docs/Evidence/T020.md` §8）；
   **T021 捕获食物营养 35.0** 与**恢复期是否锁姿态**（`Docs/Evidence/T021.md` §8）；
   **T022 的「重开」是否升级为正式 UI / F6 冲突 / 发布节奏**（`Docs/Evidence/T022.md` §9）；
   **T023 的 5 个新实现默认值**与**巡逻点位布置（T027）**（`Docs/Evidence/T023.md` §7）；
   **T024 的 5 个新实现默认值**与**多洞口优先级（T027）**（`Docs/Evidence/T024.md` §7）；
   **T025 的 3 个攻击默认值**与**攻击是否消耗体力**（`Docs/Evidence/T025.md` §7）。
4. **美术（ART01 已落地第一轮，待负责人定夺）**：草丛掩体已由半透明盒子换成真实草叶资产，
   详见 `Docs/Evidence/ART01.md`。待定：① 是否作为**正式基线**（未 approved）；② 下一批建议
   **补给点标记 → 树根屏障/鼠洞 → 庇护棚**；③ **猫/鼠角色与骨骼资产仍属 P6 阶段门，不得提前**。
5. **T025 的两帧视觉判读可补**：vision 服务已在 T026 期间恢复，`Art/Probes/t025_*.png` 随时可重新判读。

## 待负责人处理

| 事项 | 说明 |
|---|---|
| **Git 提交** | 已获授权并执行：**每完成一个任务提交一次**（T010 → `8140d6f`，T011 → `1f71f46`，T012 → `2968909`，T013 → `89ac039`，T014 → `b6351d9`，T015 → `79f2bbd`，T016 → `692fe9a`，T017 → `ab6225e`，T018 → `a2070bc`，T019 → `5bfb1c7`，T020 → `38be427`，T021 → `c36fff2`，T022 → `5b922be`，T023 → `899444c`，T024 → `cd66a9f`，T025 → `80b7eba`，T026 → `2769811`，T027 → `3ae16b9`，T028 → `d8374b3`，**T029 → `36d5944`**）；当前 `main` 比 `origin/main` **ahead 以 `git rev-list --count origin/main..main` 为准（当时累计 50 个提交未推送，含 T029 / T030）；**已于 2026-10-27 推送成功：`origin/main` = `8da9eeb`，ahead=0 / behind=0，LFS 54/54 对象（10 MB）已上传** |
| **Git 推送 / 发布** | **推送于 2026-10-27 已打通并执行**（`origin/main` = `8da9eeb`）。原因与修法：① 直连 github.com 超时 → 需代理 `127.0.0.1:7897`；② 远端 LFS locking API 经该代理不可达 → 必须关掉锁校验。两项都已写在**仓库本地配置**（不动全局），见"关键环境事实"。**对外发布（新构建给别人）仍需负责人确认** |
| 是否发布新构建 | `Builds/P0-Win64/` 已按 T029 改动**重新导出两个预设并再复验**：发布包 `Reborn.pck` **263,436 B**（+384 = 两个生产脚本改动）、自检包 `RebornSelfTest.pck` **921,704 B**（包内 T002 18/18、T019 72/72、T020 164/164、T023 178/178、T024 136/136、T025 174/174、T026 96/96、T027 96/96、T028 走查 4/4、**T029 39/39**）；**发布动作本身仍需负责人确认**（发布节奏未定） |
| 真实按键输入验证方式 | 需受审查的输入自动化工具（**需授权**），或真人操作录像。**不要盲发按键** |
| 相机轴语义 D1 / 蹲姿高度 D2 | 见上方"关键事实"：D1 已按竖直偏移实现并断言锁定；D2 需并入 `Parameters.md` 正式起测值 |
| **T020 感知新增的 4 个默认值** | `footstep_interval_base` 0.5 s、`flee_timeout` 3.0 s、`reach_tolerance` 0.5 m、`hide_arrive_radius` 0.30 m —— `Parameters.md` 原本没有，需负责人并入正式起测值（`Docs/Evidence/T020.md` §8） |
| **T021 捕获食物默认值** | 捕获食物 `nutrition` 现取物种营养表默认 **35.0**（`Parameters.md` 未给捕获食物专门值）；另「恢复期 0.6 s 是否锁俯仰/姿态」待确认（`Docs/Evidence/T021.md` §8） |
| **T023 新增的 5 个巡游/接近默认值** | `patrol_radius` 6.0 / `patrol_pause` 1.0 / `patrol_min_move` 0.5 / `patrol_retry_wait` 1.0 / `approach_repath_interval` 0.5 —— `Parameters.md` 无对应行，需负责人并入正式起测值；**猫的巡逻点位布置属 T027**（`Docs/Evidence/T023.md` §7） |
| **T024 新增的 5 个追击/搜索默认值** | `chase_repath_interval` 0.25 / `search_arrive_radius` 0.6 / `hole_search_radius` 0.6 / `search_overall_max` 12.0 / `chase_trigger_move` 0.5 —— `Parameters.md` 无对应行，需负责人并入正式起测值；**多洞口优先级属 T026/T027**（`Docs/Evidence/T024.md` §7） |
| **T025 新增的 3 个攻击默认值** | `attack_facing_half_angle_deg` 60 / `attack_retry_interval` 0.25 / `attack_fail_max` 8 —— `Parameters.md` 无对应行，需负责人并入正式起测值；另：**伤害帧的遮挡复核刻意不走感知的近距豁免**（0.65 m < 0.80 m）、**攻击是否消耗体力未定**（`Docs/Evidence/T025.md` §7） |
| **T026 的两条新发现** | ① **洞里"看得见但够不到"**：0.24×0.30 缺口同轴通视 → 猫在墙外仍能把洞里的鼠判为 `seen=true`（实测离洞心 0.806～1.025 m）；**洞里能否被打中未测**（攻击距离 0.65 m < 猫物理极限 ≈ 0.70 m → 预期打不到）→ 交 T027 生态布置定夺。② **`AnimalAI.reachable()` 判据① 层盲**：`map_get_closest_point()` 不带导航层（Godot 4.7.2 实测），对猫可能取到鼠标层的点（0.040 m）；判据② 带层故结论不变，但① 只会造成**假否** → 理想解是去掉①或改成按层，**会影响 T019/T023/T024 共享代码**（`Docs/Evidence/T026.md` §7） |
| **T027 的 4 条待定** | ① **正式启动链**：`main.tscn` 仍是"挂试验世界"的占位，正式出生/选物种属 T030；T027 只给可玩入口 `scenes/debug/ecology_entry.tscn`。② **区域 NPC 数量账本**（含捕获扣减、恢复周期、读档重建）属 T035。③ **NPC 出生点正式布置**（各区域数量/巢穴）：本轮只用现有标记 + 环上候选，**未改关卡几何**；代码已支持 `npc_spawn_points` 组。④ **猫 : 鼠 NPC 配比 1 : 2** 是否最终设计（T029 按试玩结果调，`Docs/Evidence/T027.md` §7） |
| 50 cm 高台的跳跃余量 | 净空 0.5502 m vs 台高 0.50 m（端到端实跳已通过，窗口窄）；是否提高 `JumpZVelocity` 由负责人定 |
| 确认脚本语言 | 默认 GDScript（无需额外工具链）。改 C# 需追加 .NET 配置 |
| Godot 渲染器 | **Forward+ 已确认可渲染**（T009 捕获工具实测 `renderer=forward_plus`、1280×720 出图正常）；**帧率未测** |

## 本次边界声明（T029）

- **未安装/卸载任何软件**；未连接 MCP；未改 git 全局配置；**未删除任何源资产**；**未推送、未发布**。
- **改了两处生产代码**（T029 是调参任务）：`cat_ai.gd`（冲刺能力 + 默认**关**）、`ecology_spawner.gd`（`predator_min_distance` 14.0→24.0）；
  测试侧：新增 `tests/run_t029_sprint_chase.gd`、改 `run_t023_cat_ai.gd`（`split_platform` 段关冲刺）/ `run_t027_ecology.gd`（三处阈值）/ `tool_capture_render.gd`（`-- t029`）。
- **默认关**是刻意的：打开后"鼠被发现即被咬死"，而根因是**既有缺陷**（洞里能被打中），不是冲刺 → 平衡归负责人 / U01。
- ❌ **一次严重操作失误（已恢复）**：曾用 `Get-Content | -replace | Set-Content` 改 `tool_capture_render.gd`，
  把整文件编码/行尾改坏（`228 insertions / 297 deletions`）→ 立刻 `git checkout --` 恢复并改用 Edit 重做（最终 diff 只有 62 行新增）。
- **已按任务提交 Git**（T005~T009 → `562fba4` / `0a7442b` / `bcc65be` / `44eb062`；提交策略 `965120a`；T010 → `8140d6f`；T011 → `1f71f46`；T012 → `2968909`；T013 → `89ac039`；T014 → `b6351d9`；T015 → `79f2bbd`；T016 → `692fe9a`；T017 → `ab6225e`；T018 → `a2070bc`；T019 → `5bfb1c7`；T020 → `38be427`；T021 → `c36fff2`；T022 → `5b922be`；T023 → `899444c`；T024 → `cd66a9f`；T025 → `80b7eba`；T026 → `2769811`；T027 → `3ae16b9`；T028 → `d8374b3`）；
  **已推送**（2026-10-27：`origin/main` = `8da9eeb`，含此前累计的 50 个提交 + 本文件修补；LFS 54/54 对象已上传）。
- 运行过的受限程序：Godot **非 headless** 渲染捕获（创建窗口并短暂捕获鼠标，工具立即放开）。
- 只读查询过 `E:\claude-vision-skill\vision.js`（读图判读）；用 `--doctool` 把官方类文档 dump 到 `$env:PI_SCRATCH_DIR`（**不改工程**）核对 API 签名。
- **未做真实按键注入**（禁止盲发按键）；输入验证仍是合成输入。
- 临时诊断脚本 / 日志全部写在 `$env:PI_SCRATCH_DIR`，**没有落入工程**（T027 的 `tests/tmp_t027_probe.gd` 已删除，`git status` 可核）。
- 新增的 `.tres` / `.tscn` / `.gd` 都不走 LFS（保持纯文本可 diff）；视觉 PNG 走 LFS。

## 可直接发给下一个 agent

> 请在 E:/Reborn 工作。先读 AGENTS.md、Docs/Handoff.md、Docs/Environment.md、Docs/Evidence/T011.md、Docs/Evidence/T010.md、Docs/Evidence/T009.md、Docs/Evidence/T008.md、Docs/Tasks.md、Docs/BlenderPipeline.md。
> **引擎是 Godot 4.7.2 / GDScript**，不是 UE5（UE5 路线已废止）。工程在 `Game/Reborn/`，纯文本可直接编辑。
> 工具：`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（**外层同名项是目录不是文件**）；
> Blender：`D:\SoftWare\Blender\blender.exe`（3.3.1，`--background --factory-startup --python <脚本>`）。
> 改完脚本**先跑 `--check-only`**，再跑 `--headless ... --quit-after N`（**不加 `--quit-after` 会挂死**）；
> **新增/修改 `class_name` 脚本后先跑一次 `--import`**（否则引用方报 "Identifier not declared"）。
> Godot 用**米**，Parameters.md 是**厘米**，需 ÷100。`CapsuleShape3D.height` 是含半球的总高。
> **验收脚本模板**：`run_t002.gd`(18)、`run_t005_asset.gd`(50)、`run_t006_rig.gd`(65)、`run_t008_species.gd`(114)、`run_t009_cat_movement.gd`(81)、`run_t010_mouse_movement.gd`(95)、`run_t011_greybox.gd`(210)、`run_t012_navigation.gd`(79)、`run_t007_input.gd`(22)、`probe_step_height.gd`(6)、`run_t013_debug_entry.gd`(159)、`run_t013_movement_regression.gd`(73)、`run_t014_survival.gd`(106)、`run_t015_costs.gd`(93)、`run_t016_interaction.gd`(118)、`run_t017_food_water.gd`(128)、`run_t018_hud.gd`(73)、`run_t019_mouse_ai.gd`(72)、`run_t020_perception.gd`(164)、`run_t021_capture.gd`(279)、`run_t022_loop.gd`(168)、`run_t023_cat_ai.gd`(177)、`run_t024_chase_search.gd`(136)、`run_t025_attack.gd`(175)、`run_t026_cover.gd`(96)、`run_t027_ecology.gd`(96)。
> **走查工具（不是断言套件）**：`tool_t028_walkthrough.gd` —— 用 `player_controlled=false` + 按层导航路径驱动玩家，跑"猫追鼠"与"鼠逃洞"两条真实路线，输出 `WALK|` 客观量 + 4 条硬判据（W1 猫能捕获 / W2 鼠能进洞 / W3 猫不穿洞 / W4 玩家存活）。
> **资产链已打通**：Blender → `.glb` → Godot（T005 静态 / T006 骨骼）；脚本在 `Tools/Blender/`；
> 结构 dump 用 `tests/tool_dump_scene_tree.gd`（支持骨骼/动画/蒙皮）。
> **资产约定（全部实测）**：轴向 `(x,y,z)_Blender → (x,z,−y)_Godot`——**角色在 Blender 里要面朝 `+Y`**；
> glb 只带视觉、碰撞在 Godot 侧用简单形状建；材质 albedo 是 sRGB；骨骼动画**原地无根运动**；导入削极值 1–2%。
> **数据结构已落地（T008）**：`SpeciesConfig`（`scripts/data/species_config.gd`）+ `resources/species/{cat,mouse}.tres`
> 是**唯一数据真源**；身体 `AnimalBody`（`scenes/characters/animal_body.tscn`）按配置成型；
> **移动已落地（T009）**：同一个 `AnimalBody` 就是控制器（走/跑/蹲/跳/相机），
> 台阶用 `scripts/characters/step_climb.gd`（每帧 `climb.update_base_y()`，移动时 `climb.step_or_slide(motion, dt)`）。
> **关卡**：试验世界 `scenes/maps/l_move_fixtures.tscn`（生成器 `tests/tool_make_move_fixtures.gd`）；
> **生态灰盒 `scenes/maps/l_courtyard.tscn`（T011：80×80 m、四区域 + 树根屏障/鼠洞/溪边缝隙；生成器 `tests/tool_make_courtyard.gd`）**；
> **导航数据（T012）**：`resources/nav/l_courtyard_{mouse,cat}.tres`（**鼠 layer1 / 猫 layer2**，生成器 `tests/tool_make_courtyard_nav.gd`）；
> **测试生态入口（T027）**：`scenes/debug/ecology_entry.tscn`（= `debug_entry.gd` + `ecology_enabled = true`）——
> 玩家是猫 → 场上 **2 只鼠 NPC**（可捕）；玩家是鼠 → 场上 **1 只猫 NPC**（要躲）；F1/F2 换物种会**先清再重铺**；
> `debug_entry.tscn` 本身保持生态关闭（**既有 24 套夹具语义不变**）。
> **视觉捕获**：`tests/tool_capture_render.gd -- t009` / `-- t010` / `-- t011` / `-- t012` / `-- t018` / `-- t020` / `-- t021` / `-- t022` / `-- t023` / `-- t024` / `-- t025` / `-- t026` / `-- t027` / `-- t028` / `-- t029`（**不能加 `--headless`**，`--quit-after` 给到 30000+；
> **必须检查 `CAP|done` 与每张 `save_result=OK`** —— T011 实测遇到过一次"中途静默退出、退出码却仍是 0"）。
> **不要写物种名分支**：能力差异走配置字段（`can_jump` / `can_pounce` / `can_use_mouse_tunnel`），有静态断言守着。
> 打包：`export_presets.cfg` 两个预设；**导出产物拒绝 `--script`**，包内断言用 `--main-pack` + 编辑器二进制。
> **P0 / P1 / P2 已完成（T001～T022 done）；P3 进行中（T023～T027 done；T028 / T029 awaiting-review）**。下一个动作：**T030 生命周期状态与事件记录**
> （先读 `Docs/Evidence/T029.md` §6 的两条待决策：**鼠洞不是安全区**、**冲刺会把 AI 冲出平台**；冲刺开关默认关，等 U01 真人试玩定）。
> 已知阻塞：真实按键输入无安全自动化手段（**禁止盲发按键**）。
> 不要在没有实测证据时把任何游戏任务标为 done；不要因无头断言通过就宣称画面正确。

