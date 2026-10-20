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
  **捕食者 `predator_min_distance = 14.0 m`（> 猫 9.0 m）**——**按 `can_attack` 分派，不看物种名**。
  另有 NPC 相互最小间距 `min_npc_separation = 2.0 m`、最远可接受 `max_spawn_distance = 45.0 m`、层吸附容差 `snap_tolerance = 0.60 m`、
  环上候选 `ring_radius = 4.0 m`（每个出生标记 12 个角度 × 2 圈）。
- **数量**：`max_npcs = 3`；本入口的覆盖是 **猫 NPC 1 / 鼠 NPC 2**（`predator_npc_count` / `npc_count_per_species`）。
- **T027 新增实现默认值（原文没有，需负责人并入正式起测值）**：`min_spawn_distance 8.0` / `predator_min_distance 14.0` /
  `min_npc_separation 2.0` / `max_spawn_distance 45.0` / `snap_tolerance 0.60` / `ring_radius 4.0` / `count_per_species 2` / `max_npcs 3`。
- **明确不做的**：区域 NPC 数量账本与容量（T035）；正式出生链（T030）；按区域布置正式出生点（本轮只用"现有出生标记 + 环上候选"，
  **未改关卡几何**；代码已支持 `npc_spawn_points` 组）。
