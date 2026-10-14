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
