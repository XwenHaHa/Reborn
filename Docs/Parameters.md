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
