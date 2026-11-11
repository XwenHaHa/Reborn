# 起测参数 v0.1

这是 agent 可直接采用的初值，不是平衡结果。修改集中在物种配置中并记入 Decisions，禁止各系统各写一份。距离 cm，时间 real seconds（世界默认 1:1），指标 0～100。

| 参数 | Cat | Mouse |
|---|---:|---:|
| CapsuleRadius / HalfHeight | 16 / 24 | 6 / 9 |
| CrouchHalfHeight **（T009 新增）** | **15** | **6** |
| CameraZ 相对胶囊中心（**T009 起实现为竖直偏移**，见 §相机轴说明） | 10 | 3 |
| Walk / Sprint / Crouch speed | 180 / 450 / 90 | 110 / 300 / 65 |
| MaxStepHeight | 12 | 3 |
| JumpZVelocity | 320 | 0（禁止跳跃） |
| MaxAcceleration | 1000 | 1600 |
| FOV | 90 | 90 |
| 初始 Health/Hunger/Thirst/Stamina | 100/100/100/100 | 100/100/100/100 |
| HungerLossPerSecond | 0.08 | 0.10 |
| ThirstLossPerSecond | 0.06 | 0.08 |
| SprintStaminaPerSecond | 15 | 35 |
| StaminaRegenPerSecond | 18 | 25 |
| RegenDelay | 1.0 | 0.7 |
| InteractionRange | 100 | 45 |
| VisionRange / HalfAngle | 900 / 60° | 650 / 75° |
| HearingRange（标准跑步声） | 1200 | 1000 |

## 单位与两条实现说明（T009 补记）

- 本表距离单位是**厘米**；Godot 工程里一律用**米**（÷100）。`CapsuleShape3D.height` 是含两端半球的总高。
- **相机轴说明**：`CameraZ 相对胶囊中心` 这一项源自 UE 参数表（UE 里 Z 是**上方向**），
  Godot 里按**本地 +Y（竖直）** 实现 —— 即"眼高 = 胶囊中心上方 10 cm（猫）/ 3 cm（鼠）"。
  字段名在契约里仍叫 `camera_offset_z`，轴向由断言 `camera_offset_axis == "y"` 锁死（见 `Docs/Evidence/T009.md` §4）。
- **`CrouchHalfHeight`（T009 新增，原表没有）**：蹲姿胶囊半高。猫 15（蹲高 30 cm）、鼠 6（蹲高 12 cm）；
  必须满足 `0 < CrouchHalfHeight < HalfHeight`（`validate_config()` 断言）。
  **这是 agent 在实现 M02"低顶下不扩大碰撞"时补的临时值，需要负责人确认后并入正式起测值。**

## 关卡尺度常量（T010 新增，属**试验世界设计**，不是物种参数）

- 鼠洞开口 **0.24 × 0.30 m**：M01 原文"内宽 24 / 高 30 cm"；鼠站立（0.12 × 0.18）能过，
  猫站立（0.32 × 0.48）与猫蹲姿（0.32 × 0.30 —— **宽度**就超了）都过不去。
- 鼠低顶净空 **0.15 m**：夹在鼠蹲高 0.12 与鼠站高 0.18 之间 —— 蹲着能过、松蹲站不起来。
- 两者只影响试验世界与断言：改 `tests/tool_make_move_fixtures.gd` 的常量时，
  `tests/run_t010_mouse_movement.gd` 的尺度断言会一起失败（互相守着，谁也别偷偷改）。
- **`0.15 m` 是 T010 新定值，需负责人确认是否作为关卡设计基线**；`0.24 × 0.30` 若关卡另有设计值同样在这里改。

### 生态灰盒关卡常量（T011 新增；`scenes/maps/l_courtyard.tscn`）

- 灰盒 **80 × 80 m**（厚 0.2、顶面 0.10）；**可玩矩形 72 × 56 m**（x∈[−36,36]、z∈[−26,30]），四周留 4 m 边距 + 3 m 栅栏。
- 四区域**恰好铺满**可玩矩形（ID 见 `TechnicalDesign.md` §2）：Courtyard 20×28、Creek 26×28、Roots 26×28、Grass 72×28。
- 同一道**树根屏障**（高 **0.50**、进深 1.0、横贯 Roots）：猫跳顶过去、鼠钻 **0.24 × 0.30** 洞过去。
- 溪边**隐蔽入口**：两道 **1.00** 高的岸墙夹出 **0.24** 缝（鼠进得去；猫宽度过不去、也跳不过）。
- 浅溪 **水深 0.03 m、无碰撞**（不做游泳系统）；草地危险区 16 × 24、掩体 4 处 `visibility_factor=0.4`。
- 这些是**关卡设计值**：真源在生成器 `tests/tool_make_courtyard.gd` 的常量，
  `tests/run_t011_greybox.gd` 会从场景几何 + 物种配置复核（改了不一致就红）。

### 导航数据常量（T012 新增；分物种导航图 + 分层）

- 两张**落盘导航图**：`resources/nav/l_courtyard_mouse.tres`（**layer 1**）、`l_courtyard_cat.tres`（**layer 2**），
  由 `tests/tool_make_courtyard_nav.gd` 烘焙；关卡里对应 `NavRegion_Mouse` / `NavRegion_Cat`。
- **代理参数从物种配置派生**：`agent_radius = 胶囊半径 + 0.01`（鼠 0.07 / 猫 0.17）、
  `agent_height = 胶囊总高 + 0.02`（0.20 / 0.50）、`agent_max_climb = max_step_height`（0.03 / 0.12）、`agent_max_slope = 45°`。
- **烘焙格**：`cell_size = cell_height = 0.03`、`region_min_size = 0.02`（实测口径：0.03 才留得住 0.24 的洞）。
  `project.godot` 的 `[navigation] 3d/default_cell_size/height = 0.03` 必须与之一致，否则刷格失配警告。
- **几何源**：分组 `nav_source_courtyard`（关卡所有 `StaticBody3D`）+ `PARSED_GEOMETRY_STATIC_COLLIDERS`。
- 判据（断言守着）：鼠层能穿 0.24 洞 / 溪缝；**猫层在洞与缝里没有导航面、路径不穿**。

共同：Hunger/Thirst≤25 发警告；任一归零后各扣 Health 1/s，两项均零则 2/s；Health 不自动恢复。Sprint 只有 Stamina≥5 可开始，耗尽转行走；运动消耗使用实际经过时间。起测跌落：落地前垂直速度绝对值≤700 无伤；超过按 (speed-700)*0.1 伤害，最大100，后续分别调试两物种。

猫扑击：最大水平距离 140，持续 0.25s，体力成本25，恢复0.6s，只在地面 Idle 时启动；期间锁定朝向，不允许其他扑击/跳跃/交互，连续扫掠停止于障碍。实际位移不能超预算，不用直接 SetActorLocation 穿过阻挡。

猫 NPC：Alert 0.4s；AttackRange 65；预警0.45s；伤害35；攻击恢复1.2s；搜索超时5s；鼠洞外等待最大6s；伤害帧以当前距离/遮挡检查。

鼠 NPC：Alert 最长0.3s；目标在180内立即逃；Hidden 后无危险持续4s再外出。MoveTo 失败1s内回退，重选最多3次后进入短暂等待并记录诊断，不永久阻塞。

声音：潜伏/行走/奔跑 Loudness = 0.2/0.5/1.0；当前 HearingRange*Loudness 为起测听觉距离。每次脚步事件生成声与噪声，非每帧生成。草丛 VisibilityFactor=0.4，使视觉发现距离乘该值；近距80内仍按无遮挡检测。

食物：一次交互1.5s，1 Unit 恢复 Hunger35；水2s恢复 Thirst40；提交前再检查距离、资源与受伤/死亡状态。受伤中断交互；被打断无收益，成功后全值夹紧。

固定食物容量3，每180s恢复1 Unit；捕获食物容量1，未进食在300s后失效。各区鼠容量4、初始2，每240s有空额恢复1；猫容量1、初始1，原型不自动增长。初始总计鼠8、猫4；目标玩家不计入。若负载不足以支持，记录调整而不是虚报性能。

灰盒80m×80m。通道内宽24、高30适合鼠不适合猫；鼠可行台阶≤3；猫高台约50需跳跃。必须现场验证，尺寸不是允许穿墙的豁免。

休息：推进60 sim seconds，Health恢复10；Hunger/Thirst照常扣，预计休息后任一≤0或正在警戒/追逐则拒绝。资源/种群结算所有经过的恢复周期并夹紧容量，NextRefillAt 更新到未来，不能只恢复一次造成时间错误。

**休息的实现默认值（T058，待负责人并入正式起测值）**：

- 危险判定半径 `RestDirector.DANGER_RADIUS = 8.0 m`（凡 NPC 的 AI 状态属于
  `alert/approach/chase/search/attack` 且距离 ≤ 8 m 就算"正在警戒/追逐"）；理由：猫 AI 的 `approach` 停在
  0.65 m、视距 9 m，8 m 覆盖"已进入接近/追击"的整段，又不把远处巡游算成危险。
- 休息交互时长 `RestPoint.REST_DURATION = 1.0 s`（食物 1.5 / 水 2.0 之间留档）。
- 休息点位置：庭院**庇护棚内** `(-8.0, 0.10, 27.3)`，运行时挂载（不改关卡几何）。
- 60 s / +10 两个数值**没有改**，仍是本行真源。

保存节流1s；死亡/退出绕过等待但仍串行。存活读档 NPC 距玩家至少300，玩家免伤2s。初始昼夜周期1200s，WorldTime=0 为白天起点；夜晚仍需看清基本路线。

更改物种尺度后必须同时重测胶囊、摄像机、台阶、鼠洞、导航和模型导出，不能只改速度或模型缩放。

## 生存与时间（T014 落地口径）

- **容量上限**：上表「初始 Health/Hunger/Thirst/Stamina = 100/100/100/100」在 T014 起由
  `SpeciesConfig.max_health / max_hunger / max_thirst / max_stamina` 承载（`SurvivalState` 的初值取同值）。
- **结算间隔**：`SurvivalController.UPDATE_INTERVAL = 0.2 s`（`TechnicalDesign.md` §5 允许的低频结算）；
  结算用的是**累计到的实际时间**，所以 30/60/144 Hz 结果一致（T014 实测 60 s 的消耗 spread = 0）。
- **时间源**：所有按时间的消耗取 `WorldDirector.world_time` 的差；暂停 / 结算 / 选择 / 加载时世界时间不推进 →
  数值不消耗（T014 实测：树暂停与显式门闩两条路径都成立）。

## 感知与逃跑（T020 落地口径）

- **阈值真源**：第 71 行（Alert 最长 0.3 s / 目标在 180 内立即逃 / Hidden 后无危险持续 4 s）与第 73 行
  （Loudness 0.2/0.5/1.0、**每次脚步事件**生成声与噪声、草丛 VisibilityFactor=0.4、近距 80 内仍按无遮挡检测）。
  落成字段后（**单位已换算为米**）：`alert_max_time = 0.3`、`immediate_flee_range = 1.80`（180 cm ÷100）、
  `hidden_hold_time = 4.0`、`near_detect_range = 0.80`（80 cm ÷100）。
- **听觉距离**：`HearingRange × Loudness`，**不另加系数**。鼠 = 10.0 m ×（跑 1.0 / 走 0.5 / 蹲 0.2）= **10 / 5 / 2 m**。
  墙与草丛**都不衰减声音**；自己发出的噪声按 `source_id` 忽略（不做自听）。
- **噪声只有发生位置**：`WorldDirector.noise_emitted(origin, loudness, source_id)` 每条只带**发生位置 + 时间戳**；
  感知侧存 `last_noise_position` / `last_noise_time` 快照，**不跟随声源移动**，也不为声源寻路。
- **草丛与遮挡**：草丛 `cover_volumes` 的 `visibility_factor`（0.4）乘到**视觉发现距离**上，多片草丛重叠取**最小**；
  视线遮挡只认 `world_static`。**近距 ≤ `near_detect_range`（0.80 m）豁免草丛分档与遮挡，但仍受视锥半角限制**
  （即「背后看不见」依然成立）。
- **视野**：鼠 `vision_range = 6.5 m`、`vision_half_angle_deg = 75`（第 22 行 650 / 75° 换算而来），**不做物种名分支**。
- **脚步**：走路时每 `footstep_interval_base` 出一个脚步事件；该间隔按**速度反比**缩放并夹在 0.1–1.5 s
  （实测间隔：跑 0.200 / 走 0.500 / 蹲 1.000 s；静止、离地、暂停都不出声）。
- **T020 新增 4 个实现默认值（`Parameters.md` 原文没有，需负责人并入正式起测值）**：

| 参数 | 值 | 含义与实测 |
|---|---:|---|
| `footstep_interval_base` | 0.5 s | 行走脚步间隔基准；按速度反比缩放（夹 0.1–1.5 s）。121 帧只出 4 次 → **每条事件一次，不是每帧** |
| `flee_timeout` | 3.0 s | `FLEE` 期间连掩体都没有时的上限，超时回 `EXPLORE`（实测 2.90 s 退出，**不位移、不假装躲藏**） |
| `reach_tolerance` | 0.5 m | 判「可达」的容差：`map_get_closest_point()` 与 `map_get_path()` 末端都要 ≤ 该值 |
| `hide_arrive_radius` | 0.30 m | 进洞判定半径；可被躲藏点自带的 `radius`（T011 鼠洞 0.24 × 0.30 m）覆盖 |

- **状态编号**：`AnimalAI.State.FLEE = 3`、`HIDDEN = 4`（沿用 T019 的枚举，不另起一套）。
- **逃跑优先级**：可达 `hide_spots` → 可达 `cover_volumes` → 都没有则不设目的点（交给 `flee_timeout`），
  **永不永久阻塞**；位置只由导航路径推进（**不瞬移**）。

## 扑击与捕获（T021 落地口径）

- **阈值真源**：第 67 行（猫扑击最大水平距离 140 cm、持续 0.25 s、体力 25、恢复 0.6 s、仅地面 Idle 启动、
  期间锁定朝向、禁止其他扑击/跳跃/交互、连续扫掠停止于障碍、实际位移不得超过预算、不得直接传送穿过阻挡）
  与第 77 行（捕获食物容量 1、未进食 300 s 失效）。落成字段后（**单位已换算为米**）：
  `pounce_max_distance = 1.40`（140 cm ÷100）、`pounce_duration = 0.25`、`pounce_stamina_cost = 25.0`、
  `pounce_recovery = 0.6`、`capture_food_expire = 300.0`。
- **只在 `can_pounce = true` 的物种上生效**：猫 `cat.tres` 赋上述值；鼠 `mouse.tres` 保持全 0，`can_pounce = false`。
  `SpeciesConfig` 自校验：可扑击物种五项必须 > 0；不可扑击物种五项必须为 0（**不写物种名分支**）。
- **代价一次付清、成功失败同价**：启动瞬间扣 25 点体力（体力 < 25 则**拒绝启动**，不扣不赔）；
  被障碍挡下、命中猎物、走满距离结束三种结局都不退还、也不额外扣减。
- **位移受预算约束、不传送**：用 `move_and_collide()` 逐物理帧推进（**不是** `move_and_slide()`，也不是直接写位置），
  水平速度 = `pounce_max_distance / pounce_duration` ≈ **5.6 m/s**，累计水平位移 **≤ 1.40 m**。
- **障碍优先于障碍后的猎物**：`move_and_collide()` 每帧只返回**第一个**碰撞 → 更近的墙先于墙后的猎物响应；
  碰撞体是 `world_static` → `blocked_by = "world"`；是动物但不满足猎物判据 → `"animal"`；两种都不结算捕获。
- **猎物判据**：不同 `species_id`、非自身、未 `captured`、存活（`survival == null` 视为未死，否则 `not survival.is_dead()`）
  ——纯状态/配置判定，**不写物种名分支**。`SurvivalState` **没有** `alive` 字段，一律用 `is_dead()`。
- **捕获结算幂等**：`WorldDirector.report_capture(captor_id, target_id, ...)` 按 `captured_target_ids` 去重，
  重复调用返回 `false` 且计数不变；目标侧 `mark_captured()` 亦幂等。结算**不走**伤害/死亡通道。
- **捕获食物（"可食对象"≠回满指标）**：命中点生成 1 个 `ResourcePoint`：`kind = food`、`food_type = MEAT`、
  `capacity = 1`、`units = 1`、`refill_interval = 0`（不随时间恢复）、`expire_at = 命中世界时间 + 300`；
  生成**不**直接改变捕食者任何生存值，进食仍须走 T017 的交互流程。
- **恢复 0.6 s**：扑击结束后 `RECOVERING`，按世界时间计时；期间不能再次扑击/跳跃/交互、站位固定，恢复结束回 `IDLE`。
- **T021 新增 1 个实现默认值（`Parameters.md` 原文没有，需负责人并入正式起测值）**：

| 参数 | 值 | 含义与实测 |
|---|---:|---|
| 捕获食物营养值 | 35.0 | 沿用 `ResourcePoint` 既有食物默认 `nutrition`；原文未为捕获食物单列营养值 |

- **动作状态枚举**：`ActionState { IDLE, INTERACTING, POUNCING, RECOVERING, DEAD }`（`TechnicalDesign` §1 已定义，
  由 `AnimalBody.action_state()` 只读汇总，优先级 `DEAD > POUNCING > RECOVERING > INTERACTING > IDLE`）。


## NPC 攻击（T025 落地口径）

- **阈值真源**：第 69 行（`AttackRange 65` → 0.65 m；预警 0.45 s；伤害 35；攻击恢复 1.2 s；**伤害帧以当前距离/遮挡检查**）。
  落成字段（`SpeciesConfig` 的 `Attack` 组，**只有 `can_attack` 的物种才建 `AttackSettlement`**）：
  `attack_damage = 35.0`、`attack_telegraph = 0.45`、`attack_recovery = 1.2`、`attack_range = 0.65`；猫 `can_attack = true`，鼠 `can_attack = false`（五项必须为 0，自校验守着）。
- **伤害帧四查一结算**：目标个体仍在 → 水平距离 ≤ `attack_range` + 0.05 → 与**攻击开始时锁定的方向**夹角 ≤ 半角 → 无遮挡；
  全过才 `survival.apply_damage(35, "attack")`，否则记 `out_of_range` / `facing` / `occluded` / `dead` / `target_lost` 且**不掉血**。
- **遮挡复核单独打 `world_static` 射线**（**不借感知的近距豁免**）：攻击距离 0.65 m 落在近距豁免 0.80 m 内，
  用感知判据会让"绕墙"永远命中（A04 的反面用例）。
- **T025 新增 3 个实现默认值（原文没有，需负责人并入正式起测值）**：

| 参数 | 值 | 含义与实测 |
|---|---:|---|
| `attack_facing_half_angle_deg` | 60 | 伤害帧的朝向半角（与猫的视锥半角同量级）；目标偏 90° 时 `facing` 不命中 |
| `attack_retry_interval` | 0.25 | 在攻击距离内但被拒（朝向/遮挡/目标层）时的重试间隔（实测：连续被拒 8 次后回 `CHASE` 重新走位，**不永久卡**） |
| `attack_fail_max` | 8 | 连续被拒多少次就回 `CHASE`（实现默认值） |

- **明确不做的**：攻击**不消耗体力**（第 69 行没给成本）；伤害值不按物种分列；被攻击后的逃跑/仇恨属 T026 与 P4；攻击音效属 T055。


## 藏身与掩体（T026 落地口径）

- **阈值真源**：第 73 行（草丛 `VisibilityFactor = 0.4`；**近距 80 cm 内仍按无遮挡检测**）、第 71 行（鼠 `Hidden` 后无危险持续 4 s，**不永久阻塞**）、
  第 69 行（洞口外等待最大 6 s，属 T024）。
- **草丛不是实体**：`cover_volumes` 里的体量是 `Area3D` + `collision_layer == 0`（**不参与物理查询**）+ `metadata/visibility_factor`
  （关卡实测 **4 个，全是 0.4**）；`Perception.cover_factor_at()` **重叠取最小**、草丛外默认 **1.0**。
  "开阔 = 1.0" 在关卡里由 `danger_zones` 的 `role = "open_exposure"` **声明**，**不进** `cover_volumes`。
- **只降可见性、不改别的**（T026 实测锁住）：发现距离乘 0.4（猫 9.0 → 3.6 m）；**不改移动**（猫/鼠穿草丛 1 s 位移 1.653 / 1.071 m，不被顶住）；
  **不改攻击遮挡**（`AttackSettlement.occluded()` 只认 `world_static` → 隔草丛照样命中 35）。
- **鼠洞（关卡几何，不是物种参数）**：`HideSpot_RootHole`（组 `hide_spots`，`kind = mouse_hole`、`radius = 0.30`、`species = Mouse`）——
  洞口是**墙上的缺口**（`RootBarrier*`，0.24 宽 × 0.30 高）：**猫的导航层没有洞内面**、猫也挤不进去（物理极限 ≈ 0.70 m，实测停在 0.703 m）；
  **鼠的导航层直达洞口**（实测钻到 0.089 m）；按层跨墙路由：猫绕墙 34.68 m / 鼠直穿 4.00 m。
- **躲藏不凭空恢复**（实测锁住）：`HIDDEN` 期间 hunger/thirst 不上升不回满、health 不恢复、stamina 不跳变（最大帧增 0.00）、
  衰减速率与 `EXPLORE` 同量级（**0.1012 vs 0.0990**）。
- **T026 新增实现默认值：无**（三条规则全部走既有真源；本轮**不改** `Parameters.md` 的正式起测值，也**不改生产代码**）。
- **待负责人定（T026 新发现）**：① **洞里"看得见但够不到"** —— 0.24×0.30 缺口在同轴方向**通视**，
  猫在墙外仍能把洞里的鼠判为 `seen`（实测离洞心 0.806～1.025 m）；洞里**能否被打中未测**（攻击距离 0.65 m < 猫物理极限 ≈ 0.70 m → 预期打不到）→ 交 T027 生态布置。
  ② 草丛是否改成**物理体积**（T020 §8 遗留项，本轮按数据钉住"非实体"）。


## 按玩家物种布置测试生态（T027 落地口径）

- **按玩家物种**：只铺"与玩家**不同种**"的 NPC；候选来自 `resources/species/*.tres` 的 `SpeciesConfig`（**代码不写物种名**），
  数量用 `count_per_species` + `count_overrides`（`species_id → int`）。
- **出生安全（"出生周围无即时攻击"的可验口径）**：每只 NPC 距玩家出生点 ≥ `min_distance_for(cfg)`，且该值**必须大于该物种的 `vision_range`**
  （出生瞬间连看都看不见玩家）：非捕食者 `min_spawn_distance = 8.0 m`（> 鼠 6.5 m）、
  **捕食者 `predator_min_distance = 24.0 m`**——**按 `can_attack` 分派，不看物种名**。（T029 起捕食者会冲刺，4 s 窗口能跑 18 m，故由 14.0 上调到 24.0，见下方 T029 段。）
  另有 NPC 相互最小间距 `min_npc_separation = 2.0 m`、最远可接受 `max_spawn_distance = 45.0 m`、层吸附容差 `snap_tolerance = 0.60 m`、
  环上候选 `ring_radius = 4.0 m`（每个出生标记 12 个角度 × 2 圈）。
- **数量**：`max_npcs = 3`；本入口的覆盖是 **猫 NPC 1 / 鼠 NPC 2**（`predator_npc_count` / `npc_count_per_species`）。
- **T027 新增实现默认值（原文没有，需负责人并入正式起测值）**：`min_spawn_distance 8.0` / `predator_min_distance 24.0`（T029 上调，原 14.0） /
  `min_npc_separation 2.0` / `max_spawn_distance 45.0` / `snap_tolerance 0.60` / `ring_radius 4.0` / `count_per_species 2` / `max_npcs 3`。
- **明确不做的**：区域 NPC 数量账本与容量（T035）；正式出生链（T030）；按区域布置正式出生点（本轮只用"现有出生标记 + 环上候选"，
  **未改关卡几何**；代码已支持 `npc_spawn_points` 组）。

## 猫 AI 追击冲刺（T029 落地口径）

- **能力**：`CatAI` 在**移动阶段**（`APPROACH` / `CHASE` / `SEARCH` 赶路）且**离当前目标 > `chase_sprint_min_gap`** 时置
  `body.want_sprint = true`；`EXPLORE`（巡游）/ `ALERT` / `ATTACK` / `WAIT` **一律不冲刺**（巡逻要可预期、可观察）。
  实现在 `_sprint_gate()`；`_step()` 每帧先把 `want_sprint` 清成 `false` 再按状态重算（无残留）。
- **能不能真跑**由 `AnimalBody` 的既有双门控决定（`sprint_min_stamina`、体力消耗）——AI 只管"想不想"。
- **实测（`tests/run_t029_sprint_chase.gd`，39 条 ×3 + 包内 39/39）**：`CHASE` 远距冲刺 **4.02 m/s**、关掉后 **1.79~1.80 m/s**（= `walk_speed`）；
  体力压到 `sprint_min_stamina` 以下 → 回落 **1.81 m/s** 且不崩；回满 → 恢复 **4.29 m/s**。`APPROACH` 在 6 m 时也冲刺（19/19 帧）。
- **`chase_sprint_enabled` 默认 `false`**（能力已实现、已实测；是否默认开是**产品平衡**问题，见 `Docs/Evidence/T029.md` §6）。
- **`chase_sprint_min_gap = 3.0 m`**（实现默认值）：
  ① 刹车距离倒推 —— 4.5 m/s 在 `max_acceleration 10` 下需 4.5²/(2×10) ≈ **1.01 m** 才停，加攻击停步线 0.65 + 迟滞 0.05 →
  门控 **≥ 1.7 m**，否则"进 `in_range` 后还滑 0.475 m、洞口挤到 0.276 m"（实测）；
  ② 再给"鼠 `sprint 3.0` 拉开距离"留反应带 —— 2.0 m 时实测鼠玩家在远离洞口处会被追上打死。
- **连带调整**：`EcologySpawner.predator_min_distance` **14.0 → 24.0 m**。原值按 `walk 1.8` 的 4 s 窗口（7.2 m）留余量，
  冲刺后 4 s 能跑 **18 m**，14 m 不再够（实测 T027 的"出生 4 s 零伤害"判据转红）→ 按**最快速度 × 窗口 + 6 m 余量**重算。
  仍受 `max_spawn_distance 45.0` 约束。
- **不做**：不改任何 `walk_speed` / `sprint_speed`（速度差是设计）；不改 `AnimalBody` 的冲刺门控；不动鼠的 `ALERT` 停留（T028 候选 A 留给 U01）。
- **已知未解**：**鼠洞当前不是安全区** —— 鼠进洞（距洞心 0.24 m）后，猫在洞外 0.79 m 处仍在攻击距离（0.65+0.05）内，
  实测把鼠咬死（`hp 100 → 0`）。这回答了 T026 的"洞里能否被打中=未测"，且**与冲刺无关**（关掉冲刺同样发生）→ 需设计决策。

## 地点发现与解锁（T031 落地口径）

- **稳定 ID（进存档后不得改，T036 契约）**：`root_hole_courtyard_01` = 庭院树根屏障的唯一鼠洞（`HOLE_CENTER_X 26.5`，z∈[18.5, 19.5]）。
  真源在关卡发现点标记 `Discovery_RootHole` 的 `discovery_id` meta（`tool_make_courtyard.gd` 生成）；
  消费方（`mouse.tres` 的 `unlock_discovery`、`GameState.discovered_places`、事件 `discovery` 的 `label`）都读这同一个字符串。
- **T031 新增实现默认值（原文没有，需负责人并入正式起测值）**：
  - 发现半径 `200 cm = 2.0 m`（**水平距离**，玩家到发现点标记；写在标记 `radius` meta，`DiscoveryTracker.DEFAULT_RADIUS` 兜底同值）。
    依据：策划 §9.2 只说"发现入口"，未定义看见/听见；原型确定性优先选半径判定。两侧入口距洞心 ≤ 1.0 m，半径 2.0 m 时洞前 1.0 m 空地即触发。
  - 扫描间隔 `0.25 s`（`DiscoveryTracker.DEFAULT_SCAN_INTERVAL`）：发现不需要亚秒级精度，远小于走路步长。
- **正式初始解锁（策划 §9.2「猫默认可选」）**：`SpeciesConfig.initially_unlocked`——猫 `true` / 鼠 `false`（数据驱动，代码不写物种名）。
- **解锁条件（策划 §9.2「作为猫首次发现指定鼠洞入口后，老鼠永久解锁；不要求捕食数量」）**：
  `SpeciesConfig.unlock_discovery`——鼠 = `root_hole_courtyard_01`；首次发现 → `unlock_species()`（跨世保留，死亡不取消）。
  捕获计数与解锁**无任何连接**（断言固化：`run_t031_discovery.gd` D2）。
- **`MainEntry.test_mode` 默认 `false`（T030 遗留收口）**：正式模式只放行已解锁物种；测试模式（显式 `true`）放行全部物种
  （策划 §9.2「开发测试模式允许直接选择两种物种，但正式体验与测试模式需明确区分」）。
- **待定（需负责人定）**：
  - 发现是否要求"看见"（视锥/遮挡）——当前只按距离；
  - ~~发现时的 HUD/菜单提示（当前只有日志 + 信号 `place_discovered`，UI 接入属后续任务）~~ **已由 T033 收口**（发现/解锁走 HUD Toast，见 T033 证据 §7）；
  - ~~菜单内"锁定物种"的视觉/提示（点「开始游戏」被拒后无可见反馈，属 T033 正式物种选择）~~ **已由 T033 收口**（锁定卡呈现 + 点选反馈落 hint 行）。

## 世界时钟与资源恢复（T034 落地口径）

- **一天长度**：`day_length = 1200 s`（世界秒）。真源就是第 83 行「初始昼夜周期 1200s」；本任务把它从策划句固化为 `WorldDirector.day_length` 代码常值并被断言锁死（`run_t034_world_clock.gd` A1）。
- **刻度与换算**：连续世界秒（无 tick/整点跳变）；`1 sim s = 1 real s`（TD §5 既有契约）；暂停/结算/选物种/加载不推进（T014/T030 既有门闩，T034 只复证：`world_time` 精确不变，断言 B6）。
- **T034 新增实现默认值（策划只给了周期与白天起点、未定义昼夜边界；需负责人并入正式起测值）**：
  - 昼夜边界**对半**：白天 `[0, 600) s`、夜晚 `[600, 1200) s`（`WorldDirector.NIGHT_START_RATIO = 0.5`，`WorldTime=0` 为白天起点，第 83 行原文）。
  - 天数从 0 起计（`WorldDirector.day_index()`）；**呈现层 +1** 得「第 N 天」（人话从 1 数起）。
  - 存活状态行读数「第 N 天·白天/夜晚」（呈现层最小可读版；存活期状态行默认隐藏是既有呈现，取证侧强制可见——T034 证据 §5）。
- **资源恢复（T017 既有账本，T034 断言固化口径）**：固定食物每 `180 s` 恢复 1 Unit（容量 3）、捕获食物 `300 s` 失效——**全部吃世界时间**，门闩期间不恢复不失效（正/反对照断言 D7/D8/D9 vs D11）；多周期一次结算并夹紧容量（D2/D3）。区域 NPC 数量恢复属 T035，本任务不涉及。
- **重生不重置时间（策划 §10.1 + 验收 :371）**：正式死亡→重生路径不调用 `reset_for_new_game()`，第二世 `start_world_time ≥` 第一世死亡时刻且间隔数秒内（不跳数小时、不重置白天；断言 C2/C3）。

## 区域种群账本（T035 落地口径）

- **真源**：第 77 行「各区鼠容量4、初始2，每240s有空额恢复1；猫容量1、初始1，原型不自动增长。初始总计鼠8、猫4；
  目标玩家不计入。若负载不足以支持，记录调整而不是虚报性能。」——**按初值执行，本轮零调参**（无 old→new）。
- **数据面**：`SpeciesConfig` 新增 `Population` 组三字段（**差异只写 `.tres`**，代码不写物种名分支）：
  `region_capacity`（每区容量上限）、`region_initial`（每区初始数量）、`region_recover_interval`
  （有空额时每补 1 只的间隔，**世界秒**；`0 = 不自动恢复`）。鼠 `mouse.tres` = 4 / 2 / 240；猫 `cat.tres` = 1 / 1 / 0。
  `SpeciesConfig.validate_config()` 校验：capacity ≥ 0、initial ∈ [0, capacity]、interval ≥ 0 且有限。
- **账本位置与形状**：`WorldDirector`（TD §1 排定；TD §8 禁止两份权威）。每区 × 每物种一条 TD §3 `RegionRecord`
  （`total_count / capacity / next_recover_at / recover_interval`），纯数据、无 Node 引用，可整体进存档。
  区域清单来自关卡 `level_regions` 组——**初始总计以关卡 4 区域为前提**（4×2=8 鼠、4×1=4 猫），区域数变化则总量跟随，不是硬编码。
- **恢复规则（T035 D4）**：只吃 `world_time`（复用 T034 时钟契约：单一时间源、门闩冻结、`set_world_time` 权威快进后由下一次
  advance 结算经过的周期——休息任务 T058 复用同一口径）。镜像 `ResourcePoint.advance_to` 语义：**多周期一次结算**、
  **夹紧容量**、**满容量清零 `next_recover_at`**、捕获造出空额时排期 `t + 240`。恢复与捕猎计数、解锁集、UI **零耦合**
  （断言 D8）。猫 `interval=0` → **原型不自动增长**（快进任意时长不恢复，断言 D7）。
- **捕获扣账（T035 D5）**：`report_capture` 幂等门内（首次真实结算）把受害者所属区域的 `total_count −1`（下限 0）并移出
  活动登记；重复上报不重复扣。**未登记个体**（测试夹具/临时身体）只走全局捕获账本，区域账不动——既有套件的夹具捕获零影响。
- **自然死亡扣账（T040b，改 T035 D6；负责人 2026-11-04 口头定）**：
  **旧口径** = "自然死亡不扣账，只有捕获扣"（TD §3 原意 + T035 D6 + 本文旧版明文；后果是自然死亡个体在下次读档/重生时复活）。
  **新口径** = 非捕获的真实个体死亡（AI/伤害致死、超时清退、系统回收为死亡）按 `source_id` **幂等**扣所属区域
  `total_count −1`（下限 0），并与捕获扣账互斥、不重复计数；**表现退场**（`reconcile_region_population` 的超额退场、
  `EcologySpawner.clear()` 的读档清场、重生重建）**不扣**。死亡**不改变已有 `next_recover_at`**；记录原本满容量
  （`next_recover_at=0`）时，死亡造成的空额由既有 `region_population_advance_to()` 按 `recover_interval` 起算。
  读档/重生只按新 `total_count` 重建，不再复活自然死亡个体（`Docs/Evidence/T040b.md`）。
- **12 m 内不退场（T040b，改 T040 D1；负责人 2026-11-04 口头定）**：
  `reconcile_region_population()` 只移除距玩家 **>12 m** 的超额个体；≤12 m 的个体一律保留，仍 `active > total` 时
  在 `last_reconcile` 记 `pending_excess / pending_entries`（`reason="within_visible_distance"`），不硬收。
  重试时机：捕获、自然死亡、读档/重生后立即调用；玩家走远后由 `MainEntry` 每 60 物理帧检查 pending 重试。
  **old = 无**（T040 旧规则按“距玩家最远”移除，允许移除 2 m 内个体）→ **new = 12 m**。
- **活动登记 = 表现层**：`region_active_count` = 登记且实例有效且未死未捕获；正式初始状态不变式 **active ≤ total**
  （断言 B7）。布置器（T027）落点按 `level_regions` 矩形反查区域后登记；**布置计数仍按 T027 契约**（猫玩家 2 鼠 / 鼠玩家 1 猫），
  按账本实例化身体属 T040——捕获/重生后的过渡态可能出现 active>total，T040b 按 12 m 保留口径收口。
- **快照与重建（T035 D7）**：`region_population_snapshot()`（TD §3 `WorldSnapshot.regions` 元素形状）+
  `restore_region_population()`：数量/下次恢复时刻从快照恢复，**容量与恢复间隔是配置数据、不从快照恢复**；未知区域/物种跳过、
  负数钳 0、超容量钳容量、非有限整条回初始（TD §8 读档校验口径）。真实读档属 T037+。
- **新游戏/重生（T035 D8）**：`reset_for_new_game()` 把账本彻底归零（只有明确新游戏确认才可调）；`MainEntry._ready`
  建关卡后 init 一次；正式死亡→重生**不重置种群**（与 T034 时间语义同构，断言 F2）。

### 存档（T037 格式 + T038 写入队列 + T039 损坏/强杀边界落地口径）

- **路径**：主档 `user://savegame_v1.json`，上一版快照 `user://savegame_v1.json.bak`，坏档隔离
  `user://savegame_v1.json.corrupt-<unix秒>`（`.bak` 对应 `.bak.corrupt-<unix秒>`）；写临时 `*.tmp`、
  替换中间 `*.old`、备份中间 `*.bak.tmp/.prev`。
  只写 `user://`，**不含个人绝对路径/用户名/令牌**（T037 断言 A7）。
  测试专用路径 `user://t037_tests/`、`user://t038_tests/`、`user://t039_tests/`、`user://t039_kill/`（套件/取证结束清理）。
- **格式**：UTF-8 JSON 纯数据。`save_version=1`、`revision` 单调递增、`world_time` 秒。
  契约 10 键（`resources/regions/discovered_ids/unlocked_species/life_records/current_life/pending_settlement_life_id` 等）
  + 实现扩展 `events/life_counter/event_seq` + 诊断 `saved_reason`（只写不读）。
  `Transform3D→{"$t":[12 floats]}`、`Vector3→{"$v":[3 floats]}`；`last_safe_spot_id` **预留未建**（T042）。
- **写入队列（T038）**：所有生产保存经 `SaveManager.request_save()` 单队列、主线程帧驱动、无线程；
  同一时刻只允许一次写（`active_writes ≤ 1`）。普通请求可合并/丢弃；关键事务（死亡、`pending` 清空、发现、
  解锁、退出）**逐条写、不合并、不丢弃、不被后续普通请求插队**。`MainEntry.save_now()` 立即排空，保持 T037 时序。
- **节流**：普通保存窗口 `throttle_seconds=1.0`（首次前缘立即写，窗口内请求合并为一次，`revision` 只 +1）；
  关键事务与退出绕过等待，但仍逐条串行。
- **原子写**：`*.tmp` 写完 flush/关闭 → 复制主档到 `.bak.tmp` 后轮换 `.bak`（复制失败不阻断本次写，旧 `.bak`
  原样保留，warning「存档已保存（备份更新失败）」）→ 主档改名为 `.old` → `.tmp` 换入主档 → 删除 `.old`。
  最终换名失败**回滚 `.old` 为主档**并清理 tmp，返回 `write_failed`；任何失败路径主档不被截断/删除。
  重复保存幂等（除 `revision/saved_reason`）。
- **失败注入（仅测试）**：`fault_injection ∈ {tmp_open, disk_write, bak_copy, rename}`；生产恒空。
  写失败 Toast「存档写入失败」，备份失败 warning Toast「存档已保存（备份更新失败）」，队列失败后不复位锁、后续请求继续。
- **版本与恢复**：`save_version` 缺失/非整数 → `corrupt`；≠1 → `version_mismatch`（不隔离不覆盖）。
  解析失败或结构非法 → 隔离主档后尝试 `.bak`：可用 `recovered_backup`，否则 `corrupt`。
  **主档缺失但 `.bak` 有效** → `recovered_backup`，文案「主存档缺失，已从备份恢复」（T038 改名窗口兜底）。
  **T039 双坏**：主档与 `.bak` 都不可用 → 两份都隔离（不删除）、消息精确「存档损坏，已隔离；未载入」、
  读档零写入；`MainEntry` 阻断本会话开新局（`is_load_blocked()`、选物种被拒、退出不保存），重启后才按 `none` 开新局。
  **主档缺失 + `.bak` 损坏** → 隔离 `.bak` 并返回 `corrupt`（不再静默 `none`）。
  `.tmp/.old/.bak.tmp` **永不作为读档来源**；只有陈旧 `.tmp` 时返回 `none`，下次写入清理。
  缺失集合补默认+`repairs`；负数/超容量夹紧；非有限回默认；坏条目跳过；`current_life`+`pending` 互斥（清 `pending`）。
- **强杀取证（仅测试）**：`write_delay_phase ∈ {before_tmp, tmp_mid, rename_gap, bak_rotate}` +
  `write_delay_ms` 仅在工具里设置，生产恒空/0；`CaptureRun.ps1` 的 `-KillOnMarker` 默认关闭。
  这是为扩窗加的可控延迟，**不是生产参数**；只覆盖“进程被杀、未 flush/fsync”，不覆盖掉电/缓存/扇区损坏。
- **存盘时机**：死亡结算（写 `pending`）→ 结算页展示（清 `pending`）；新发现；新解锁；退出。
  仅在正式运行（`current_scene == self`）启用；读档补弹结算页也属"展示完毕即清空"。
- **读档重建顺序**：世界时间 → 区域种群 → 资源点（稳定 ID 匹配/补建）→ 档案/事件/发现/解锁/计数器 → 当前生命
  （存活恢复身体；`pending` 非空补弹结算页，展示后清空）。`LifeCycle` 只接受 `SETTLING/SELECTING → ALIVE`，
  不经 `mark_spawned`、不新分配 `LifeId`、不发 `life_started`。

## 角色接地感（ART15 落地口径）

只动**庭院关**的 SSAO 半径与太阳光阴影法线偏移；主光方向/能量/色温、体积雾、DOF、色调映射均未改。
参数真源：`Game/Reborn/scenes/maps/l_courtyard.tscn`（生成器 `tests/tool_make_courtyard.gd` 同步同值）。

| 参数 | 旧值 | 新值 | 作用（角色尺度 0.18～0.48 m） | 回退位置 |
|---|---:|---:|---|---|
| `Environment.ssao_radius` | 1.2 m | **0.75 m** | 1.2 m 的 AO 半径把脚底抹成灰圈；0.45 m 虽最贴脚，但远景墙脚/围栏底部的宽 AO 被削窄（反向校验 §7），折中 **0.75 m**：角色接地仍 PASS、大结构遮蔽更接近 ART13 基线 | tscn 第 1277 行；生成器第 823 行 |
| `DirectionalLight3D.shadow_normal_bias`（SunLight） | 2.0（默认） | **0.8** | 降低法线偏移，阴影根部贴住几何接触处，减少"影脚分离/悬浮"；0.8 未出现阴影痤疮 | tscn 第 2871 行（删该行即回默认）；生成器 `light.shadow_normal_bias` |

`ssao_intensity/power/horizon/sharpness/detail`、`shadow_bias`、`shadow_blur`、阴影分档与最大距离均保持原值。
实测帧时间：改前 ≈6.28 ms、改后 ≈6.20 ms（1280×720、vsync off、120 帧均值），差异在 ±3% 噪声内；
半径 0.45/0.75 的采样成本相同，二者帧时间一致（6.19 / 6.200 ms）。
**全局影响**：`ssao_radius` 作用于整个环境。反向校验（总览 + 远景两机位对 `Art/Probes/art13_after/`）
显示 0.45 下大结构墙脚 AO 局部收窄（vision 4/10、客观像素差 >8/255 占 3.3%），故取 0.75；
判读细节与像素统计见 `Docs/Evidence/ART15_CHARACTER_GROUNDING.md` §7。
**不得整体重新生成 `l_courtyard.tscn`**：生成器不写导航资源引用，重生成会丢 `l_courtyard_{mouse,cat}.tres` 并刷新全部 `unique_id`。

## 菜单展板接地（ART16 落地口径）

只动**展板切片关**的 SSAO 半径与 `BoardSun` 阴影法线偏移；主光方向/能量/色温、天光补光、
雾、曝光、辉光、DOF、几何/碰撞/导航均未改。真源：`Game/Reborn/scenes/maps/l_ravine_board.tscn`
（生成器 `tests/tool_make_ravine_board.gd` 同步同值），**不整体重生成场景**。

| 参数 | 旧值 | 新值 | 作用（展板猫占屏 25.5%、脚下 0.31 m） | 回退位置 |
|---|---:|---:|---|---|
| `Environment.ssao_radius` | 1.35 m | **0.75 m** | 1.35 m 在特写下把脚底糊成灰圈；0.75 m 与庭院关同值（场景/结构同尺度，机位更近），vision 三问 5/4/5 → 8/8/8，远景 9.5/10、根障 9/10 | tscn 第 509 行；生成器第 572 行 |
| `DirectionalLight3D.shadow_normal_bias`（BoardSun） | 2.0（默认） | **0.7** | 阴影根部贴回脚掌，消除"影子离脚"；取证抬升纠偏后逐档实测，0.7 三问 9.5/10/10（重拍确认 8.5/7.5/9），全面优于 0.8 与 0.6；0.6 无痤疮但无补偿收益，不采纳 | tscn 第 1251 行（删该行即回默认）；生成器第 540 行 |

`ssao_intensity 2.8`、`ssao_power 2.0`、`ssao_detail 0.5`、`shadow_bias 0.03`、
`directional_shadow_max_distance 45` 均保持原值；`tonemap_exposure 0.92`、`glow_hdr_threshold 1.30` 未动。
实测帧时间（120 帧均值）：改前 **5.782 ms（173 fps）** → S1 5.616 → S2 5.673 → 纠偏后最终 **5.616 ms（178 fps）**，
差在 ±2% 运行噪声内，60 fps 预算占用约 34%，无可感知代价。
**portrait 图不受影响**：`tool_render_board_portraits.gd` 自建环境（`ssao_radius = 0.3`、独立 HDRI 与灯光），
不读展板关的 `WorldEnvironment`。
**取证抬升纠偏（2026-11-04）**：旧取证工具把猫脚底摆在 0.12 m（真实地面 0.10 m）之上 2 cm，
已改为精确接触（`GROUNDING|gap_mm=0.0`）。该偏移**只存在于取证工具**，未进本表；
登记与回退位置见 `Docs/Evidence/ART16_MENU_BOARD_GROUNDING.md` §10 与 `tests/tool_capture_art09_board.gd` 第 111–116 / 124 行注释。
判读机位、像素统计与其他未解决项见 `Docs/Evidence/ART16_MENU_BOARD_GROUNDING.md`。
