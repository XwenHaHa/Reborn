# 技术设计与数据契约 v0.2（Godot 4）

> **版本说明**：v0.1 为 UE5 蓝图版，已于 2026-10-13 废止。本版为 **Godot 4.7.2 + GDScript** 实现基线。
> 引擎切换依据与能力实测见 `Docs/Evidence/T004.md`。
>
> 本文件是首个原型的实现基线，不是已存在工程说明。**当前工程尚未创建**（T002 负责）。
> T002 必须实测"纯文本编写 → 无头运行 → 断言通过"闭环；未通过时按 Bootstrap 的阻塞规则执行。

## 0. 单位与坐标约定（**最容易出错，先读**）

| 项 | 约定 |
|---|---|
| **引擎内部单位** | Godot 一律使用**米（m）**。`Parameters.md` 全部数值是**厘米**，使用前 **÷100** |
| 距离显示 | 文档、参数表、UI 中仍用厘米，便于与策划案对照；**代码里只出现米** |
| 时间 | real seconds（现实秒）用于消耗与动作；sim seconds（世界秒）用于资源恢复与昼夜 |
| 坐标系 | Godot `+Y` 向上，`-Z` 为前向（与 glTF 一致） |
| Blender 坐标 | Blender `+Z` 向上、`-Y` 前向；导出 **glTF** 时自动转换，**不要手工旋转** |
| 角度 | 度（`deg_to_rad()` 转换后使用弧度 API） |

**换算基准表（`Parameters.md` → Godot 代码）**

| 参数 | 厘米 | 米（代码用） |
|---|---:|---:|
| Cat 胶囊半径 / 半高 | 16 / 24 | 0.16 / 0.24 |
| Mouse 胶囊半径 / 半高 | 6 / 9 | 0.06 / 0.09 |
| Cat Walk / Sprint / Crouch | 180 / 450 / 90 | 1.80 / 4.50 / 0.90 |
| Mouse Walk / Sprint / Crouch | 110 / 300 / 65 | 1.10 / 3.00 / 0.65 |
| Cat MaxStepHeight | 12 | 0.12 |
| Mouse MaxStepHeight | 3 | 0.03 |
| Cat JumpZVelocity | 320 | 3.20 |
| Cat 扑击最大水平距离 | 140 | 1.40 |
| InteractionRange Cat / Mouse | 100 / 45 | 1.00 / 0.45 |
| VisionRange Cat / Mouse | 900 / 650 | 9.00 / 6.50 |
| HearingRange Cat / Mouse | 1200 / 1000 | 12.00 / 10.00 |
| Cat NPC AttackRange | 65 | 0.65 |
| 灰盒地图 | 8000×8000 | 80×80 |
| 鼠通道内宽 / 高 | 24 / 30 | 0.24 / 0.30 |
| 高台高度 | 50 | 0.50 |
| 读档后 NPC 最小距离 | 300 | 3.00 |
| 近距视觉豁免 | 80 | 0.80 |
| 跌落无伤阈值 | 700 | 7.00 |

**`CapsuleShape3D` 陷阱**：Godot 的 `height` 是**含两端半球的总高**，不是 UE 的 HalfHeight。
- Cat：半高 24 cm → `height = 2 × 0.24 = 0.48`，`radius = 0.16`
- Mouse：半高 9 cm → `height = 2 × 0.09 = 0.18`，`radius = 0.06`

这个换算已在 T004 探针中**实测验证**（回读 16.0 cm / 48.0 cm）。

## 1. 路径与职责

预定工程：`Game/Reborn/project.godot`。资源根为 `res://`（磁盘 `Game/Reborn/`）。

| 类型/资源路径 | 基类与职责 | 创建任务 |
|---|---|---|
| `res://autoload/world_director.gd` | **Autoload 单例**。统一世界时间、资源注册、区域种群账本、NPC 生成与区域账本 | T014/T034/T035 |
| `res://autoload/game_state.gd` | **Autoload 单例**。长期记录、解锁、生命档案、当前生命状态；替代 UE GameInstance | T030/T036 |
| `res://autoload/save_manager.gd` | **Autoload 单例**。串行保存、读档、错误处理 | T037 |
| `res://scenes/core/main.tscn` | 主入口场景。菜单/游戏切换、生命周期状态机 | T002/T030 |
| `res://scripts/core/life_cycle.gd` | 生命周期状态机（Alive/Settling/Selecting/Spawning） | T030 |
| `res://scenes/characters/animal_base.tscn` | `CharacterBody3D`。物种数据、身体、伤害/动作入口；**玩家与 NPC 共用** | T008 |
| `res://scenes/characters/cat.tscn`、`mouse.tscn` | 继承 animal_base，只做配置引用与表现 | T008/T010 |
| `res://scripts/characters/survival.gd` | Node 组件。指标、消耗、警告、死亡通知 | T014 |
| `res://scripts/characters/interaction.gd` | Node 组件。目标查询、交互动作与取消 | T016 |
| `res://scripts/ai/animal_ai.gd` | 分物种有限状态机、路径、最后已知位置 | T019/T023 |
| `res://data/species/species_config.gd` | `Resource` 子类。物种参数；实例 `cat.tres` / `mouse.tres` | T008 |
| `res://scripts/core/interactable.gd` | **基类 + duck typing**。交互查询/提交/取消（替代 UE BlueprintInterface） | T016 |
| `res://scenes/world/resource_point.tscn`、`safe_spot.tscn`、`discovery_point.tscn` | 稳定 ID、表现与交互 | T017/T031 |
| `res://scripts/core/save_data.gd` | `Resource` 子类。纯数据快照 | T037 |
| `res://scenes/ui/hud.tscn`、`main_menu.tscn`、`life_summary.tscn` | `Control` 场景。观察状态，**不直接修改资源账本** | T018/T032/T041 |
| `res://scenes/maps/l_movement_lab.tscn`、`l_ai_playground.tscn`、`l_save_test.tscn`、`l_courtyard.tscn` | 关卡场景 | T002/T011/T043 |

**关于"接口"**：GDScript 没有 BlueprintInterface 的等价物。改用**基类 + 鸭子类型**：
交互目标必须实现 `query_interaction()` / `commit_interaction()` / `cancel_interaction()` 三个方法。
用 `has_method()` 检查，**不要**用类型转换失败来判断。这是本次迁移中唯一一处范式变化。

P4 前无长期账本时 `world_director` 暂存最小数据；T036 迁移为 `game_state` 所有，**禁止两份同时权威的数据**。
用**信号（signal）**更新 UI，避免 UI 每帧写游戏状态。

## 2. 命名与 ID

- 场景/脚本文件：`snake_case.gd`、`snake_case.tscn`（Godot 惯例）
- 类名：`PascalCase`（`class_name SpeciesConfig`）
- 节点名：`PascalCase`（`PlayerBody`、`Camera3D`）
- SpeciesId：`"Cat"`、`"Mouse"`（`StringName`）
- 区域：`"Courtyard"`、`"Grass"`、`"Roots"`、`"Creek"`
- 固定对象 Name ID 在地图中唯一；运行期捕获食物用 GUID，加载后继续保留

**枚举**（GDScript `enum`）：

```gdscript
enum LifeState { ALIVE, SETTLING, SELECTING, SPAWNING }
enum ActionState { IDLE, INTERACTING, POUNCING, RECOVERING, DEAD }
enum FoodType { MEAT, SEED }
enum AIState { EXPLORE, FORAGE, ALERT, FLEE, HIDDEN, APPROACH, CHASE, SEARCH, ATTACK }
```

不合法转换拒绝并记录原因（`push_warning()` + 事件记录）。

## 3. 数据结构

全部为 `Resource` 子类或 `RefCounted` 结构；**没有 Node 引用的部分才可进存档**。

```gdscript
class_name SurvivalState extends Resource
var health: float
var hunger: float
var thirst: float
var stamina: float
var last_damage_reason: StringName
```

```gdscript
class_name SpeciesConfig extends Resource
@export var species_id: StringName
@export_group("Movement")
@export var capsule_radius: float        # m
@export var capsule_half_height: float   # m
@export var walk_speed: float
@export var sprint_speed: float
@export var crouch_speed: float
@export var crouch_half_height: float    # m，蹲姿胶囊半高（T009 新增，`Parameters.md` 原表没有）
@export var max_step_height: float
@export var jump_velocity: float
@export var max_acceleration: float
@export var camera_offset_z: float       # 相对胶囊中心的**竖直（本地 +Y）**偏移：UE 命名沿用，Godot 里是 Y
@export var fov: float
@export_group("Perception")
@export var vision_range: float
@export var vision_half_angle_deg: float
@export var hearing_range: float
@export_group("Survival")
@export var hunger_loss_per_sec: float
@export var thirst_loss_per_sec: float
@export var sprint_stamina_per_sec: float
@export var stamina_regen_per_sec: float
@export var regen_delay: float
@export var interaction_range: float
@export_group("Abilities")
@export var allowed_food_types: Array[int]
@export var can_jump: bool
@export var can_pounce: bool
@export var can_use_mouse_tunnel: bool
```

- `LifeEvent`：`event_id`(String)、`life_id`(String)、`world_time`(float)、`type`(StringName)、`source_id`(String)、`reason`(StringName)、`amount`(float)
- `LifeRecord`：`life_id`、`species_id`、`duration`、`end_reason`、`food_count`/`capture_count`/`escape_count`、`discovered_ids: Array[StringName]`、`events: Array[LifeEvent]`
  - **原型每世最多 200 条事件**，超出保留统计与最近事件，避免无限增长
- `ResourceRecord`：`id`(String)、`region_id`、`kind`、`food_type`、`units`、`capacity`、`next_refill_at`、`refill_interval`、`transform`、`expire_at`（0 表示不失效）
  - 水点无限饮水、不储存可扣 `units`，仍有稳定 ID
- `RegionRecord`：`region_id`、`species_id`、`total_count`、`capacity`、`next_recover_at`、`recover_interval`
  - **`total_count` 包含已实例化与未实例化个体**；实例化/销毁表现不改变它
- `CurrentLife`：`life_id`、`species_id`、`life_state`、`transform`、`survival`、`spawn_world_time`、`last_safe_spot_id`、`current_events`、`current_discovered_ids`
- `WorldSnapshot`：`save_version`(=1)、`revision`(int)、`world_time`、`resources`、`regions`、`discovered_ids`、`unlocked_species`、`life_records`、`current_life`、`pending_settlement_life_id`
  - **T037 实现扩展**（只增不改，便于诊断/ID 单调）：`events`、`life_counter`、`event_seq`、`saved_reason`（只写不读）
  - `last_safe_spot_id` 仍在 `CurrentLife` 契约内，**T037 预留未建**（T042 落地；读档不读该键）

**读取校验**：拒绝未知版本、重复 ID、未知物种、负数/超容量、非有限数值（`is_finite()`）。
恢复可选指标前夹紧到 0～100 并**记录修复**。严重结构错误走坏档回退，**不静默开新游戏**。
设置数据另存，不混入死亡进度。

### 3.1 契约实现对照（T036 审计，2026-11-04）

逐字段差异清单与四类判定（一致 / 缺失 / 多出 / 语义偏移）见 `Docs/Evidence/T036.md` §3；
可执行锁测 `Game/Reborn/tests/run_t036_contract.gd`（72 条）。要点：

| 对象 | 状态 |
|---|---|
| `SurvivalState` / `RegionRecord` / `ResourceRecord` | **完全一致**（5 / 6 / 10 字段，A 段锁死） |
| `SpeciesConfig` | TD §3 的 **25 项全在场**；另有 41 项扩展组（来源任务见证据 §3.4），不违反契约 |
| `CurrentLife` | `transform` 已补齐（`GameState.sync_current_life()` 存活期同步）；`survival` 以既有 `snapshot` 键承载（不复制第二份）；`spawn_world_time→start_world_time`；`life_state` 真源 `LifeCycle.state`（不入档）；`last_safe_spot_id` **缺**（T042）；`current_events/current_discovered_ids` 有等价替代 |
| `LifeRecord` | 4 项一致；`food_count→food_gained`（累计增益，**不可逆**）、`capture_count→captures`、`escape_count→escapes`、`discovered_ids→discoveries`、`events→event_first/event_last` 为语义偏移 |
| `LifeEvent` | `life_id/world_time` 一致；`event_id→seq`、`type→kind`、`reason/amount→data.*` 为语义偏移；`source_id` 按 D5 **不补**（同一事实不存两份） |
| `WorldSnapshot` | **T037 已组装**（10 契约键 + 4 实现键）；`pending_settlement_life_id` = "死亡已发生、结算页尚未展示"，读档补弹后清空 |
| 信号 | `action_noise` 一致；其余 5 条为名称/参数/类型偏移（详见证据 §3.2），`captured` 无 `capture_id/region_id`、`died` 无 `life_id` |

## 4. 输入与交互接口

**InputMap**（定义在 `project.godot`，动作名固定）：

| 动作 | 类型 | 说明 |
|---|---|---|
| `move_forward` / `move_back` / `move_left` / `move_right` | 按键 | 组合为 Vector2 |
| `look_up` / `look_down` / `look_left` / `look_right` | 鼠标/按键 | |
| `sprint` / `crouch` / `jump` / `pounce` / `interact` / `pause` / `record` | 按键 | 布尔 |

物种能力决定动作**能否触发**，**不通过删输入**来复制控制器。

**交互接口（鸭子类型，三个方法）**：

```gdscript
func query_interaction(interactor: Node) -> Dictionary:
    # -> { allowed: bool, action_id: StringName, duration: float, deny_reason: StringName }

func commit_interaction(interactor: Node, transaction_id: String) -> Dictionary:
    # -> { success: bool, reason: StringName }

func cancel_interaction(transaction_id: String) -> void:
    # 取消无收益
```

距离、视线和允许物种在**查询及提交时都检查**；只选择一个有效目标。
提交前把事务标为进行中，**扣资源与加收益在同一主线程操作中完成**，结束后才发 `committed` 信号。
**重复 `transaction_id` 返回既有结果，不重复扣资源。**

**信号（替代 UE 事件分发器）**：

```gdscript
signal survival_changed(state: SurvivalState)
signal died(life_id: String, reason: StringName)
signal action_noise(source_id: String, position: Vector3, loudness: float, world_time: float)
signal captured(capture_id: String, victim_id: String, region_id: StringName)
signal discovered(location_id: StringName)
signal life_ended(record: LifeRecord)
```

`capture_id` 与 `life_id` 去重集合随权威状态维护。

## 5. 时间、动作和碰撞

`world_director` 用 `_process(delta)` 的经过时间驱动 sim time，默认 1:1；
**暂停 / 结算 / 选择 / 加载不推进**（用 `get_tree().paused` 或显式门闩）。
低频消耗可 0.2 s 更新但**必须使用实际 `delta`**；动作/移动依赖 `_physics_process`，**不能固定每帧扣值**。

**昼夜时钟（T034 契约）**：`world_director` 在 `world_time` 之上提供昼夜刻度——一天 `day_length = 1200 s`
（真源 `Parameters.md`「初始昼夜周期」），白天 `[0, 600)` / 夜晚 `[600, 1200)`（对半，新增实现默认值待并入起测值），
API `time_of_day() / day_index()（0 起）/ is_daytime() / phase_name()` **全部是 `world_time` 的纯函数**：
不存平行状态、门闩天然冻结昼夜读数；`set_world_time()` 是权威时间指令（读档/取证快进），门闩不阻止它。
正式死亡→重生**不重置世界时间**（`reset_for_new_game()` 只属"新游戏"）；昼夜光照属 T057，时钟类不做任何灯光变化。
资源恢复（`ResourcePoint` 每 180 s 恢复 1 Unit、捕获食物 300 s 失效）与失效判定**只吃世界时间**——
门闩期间不恢复不失效，多周期一次结算并夹紧容量（断言：`run_t034_world_clock.gd`）。

**区域种群账本（T035 契约）**：`world_director` 持有 §3 的 `RegionRecord` 账本（每 `level_regions` 区域 × 物种一条，
`total_count / capacity / next_recover_at / recover_interval`，纯数据可进 `WorldSnapshot.regions`）。
每区参数经 `SpeciesConfig.Population` 组从 `.tres` 读入（鼠 4/2/240、猫 1/1/0，真源 `Parameters.md`）。
`total_count` 是权威数量（含未实例化个体；实例化/销毁表现不改变它），活动登记只是表现层
（初始状态不变式 active ≤ total；按账本实例化身体属 T040）。**恢复只吃 `world_time`**：
`region_population_advance_to()` 镜像 `ResourcePoint.advance_to`（多周期一次结算、夹紧容量、满容量清零排期），
由 `_process` 在 `world_time += delta` 后驱动——门闩天然冻结；`set_world_time()` 快进后由下一次结算补齐经过的周期。
**捕获只扣一次**：`report_capture` 幂等门内扣受害者区域 `total_count − 1`（下限 0）并移出登记；未登记个体区域账不动。
快照/重建（`region_population_snapshot() / restore_region_population()`）：数量与恢复时刻从存档恢复，
容量与间隔是配置数据不从存档恢复；未知区域/物种跳过，负数/超容量/非有限按 §8 校验修复。
`reset_for_new_game()` 归零账本；`MainEntry._ready` 建关卡后 init 一次；**重生不重置种群**（与 T034 时间语义同构）。
断言：`run_t035_region_population.gd`。

**物理与碰撞**：
- 用 Godot 内置 `CharacterBody3D` + `move_and_slide()` 作为两种地面动物原型。**不要一开始就自定义 `PhysicsBody`。**
- 起测碰撞层集中定义在 `project.godot`：`1 = world_static`、`2 = animal`、`3 = interactable`、`4 = safe_spot`；**不新增未经验证的层**。
- 扑击用 `move_and_collide()` 或 `PhysicsDirectSpaceState3D.intersect_shape()` 做扫掠；**障碍优先于障碍后的猎物**；命中 animal 后再检查物种和存活。
- 交互视线用 `ray_cast`；目标碰撞体响应要实测。
- **台阶（高风险）**：Godot `CharacterBody3D` **没有 UE `MaxStepHeight` 的直接等价物**。
  需用 `move_and_slide` 配合自实现的台阶探测（`test_move()` 探针）或加小斜坡碰撞。
  **T009 必须先验证这一项**，因为它直接决定鼠标能否上 3 cm 台阶、猫能否上 12 cm 台阶。

**草叶视觉遮挡与 AI 可见性不是同一回事**：
草丛用 `Area3D` 提供 `visibility_factor`；实体墙由 `ray_cast` 阻挡。
鼠洞真实通道尺寸限制猫；**安全点标记不应让猫传送穿过墙**。

**可蹲姿**只有碰撞空间允许才改变/恢复胶囊尺寸（用 `ShapeCast3D` 检测头顶空间，**不是**单纯改 `scale`）。
导航 `NavigationMesh` 要由两种实际胶囊验证；**失败时禁止用瞬移伪装寻路成功**。

## 6. 感知与 AI 转换

视线有效时更新 `last_known_position`；声音**只创建** `NoiseLocation`（位置 + 时间）。
失去视线后 `CHASE → SEARCH`，`SEARCH` 到最后已知位置后超时放弃。**隐藏后不得读取玩家真实坐标导航。**

- **鼠**：`EXPLORE/FORAGE → ALERT → FLEE → HIDDEN → EXPLORE`。
  `ALERT` 期间可提前逃跑；安全点不可达则找遮挡；连续失败按超时退出路径请求并重新选择，**不每帧请求路径**。
- **猫**：`EXPLORE → ALERT → APPROACH → CHASE → ATTACK`；失去目标 `→ SEARCH → EXPLORE`。
  攻击开始即保存方向与目标信息；伤害帧重新检查距离/遮挡/目标存活；**预警后不中必然命中**。

`escape_count` 只在一场有效 `CHASE` 结束**且玩家存活**时增加一次，以 `encounter_id` 去重。
**隐藏瞬间不立即刷逃脱记录。**

`NavigationAgent3D` 用 `target_reached` / `navigation_finished` 信号；
路径请求失败**最多重选 3 次**后进入短暂等待并记录诊断，**不永久阻塞**（`Parameters.md` 要求）。

### 6.1 感知模块落地（T020 实现口径）

- **`Perception`（`scripts/systems/perception.gd`）是挂在 `AnimalBody` 下的组件，只观察**：
  输入是「自己的身体 + 世界」与 `WorldDirector.noise_emitted(origin, loudness, source_id)`；
  输出是 `can_see_point()` / `cover_factor_at()` / `danger_time()` / `report()` 等只读查询。
  **它不写 `move_intent`、不写生存数值**；NPC 的决定仍由 `AnimalAI.alert_for(position, reason)` 注入。
- **噪声是快照而不是实体**：只保存 `last_noise_position` + `last_noise_time`；
  **不跟随声源移动、不暴露声源的真实持续坐标**（与上面「隐藏后不得读取真实坐标」是同一条纪律）。
- **威胁 = 异物种的存活身体**（比较 `species_id`），**不写物种名分支**。
- **可达性判据**（`AnimalAI.reachable()`）：`map_get_closest_point()` ≤ `reach_tolerance`
  **且** `map_get_path()` 非空、末端 ≤ 容差；导航图尚未同步时按可达处理。
- **`AnimalBody` 新增**：`action_noise` 信号（脚步）、`footstep_count`、`footstep_interval()`、
  `noise_loudness()`、`source_id()`、`world_time_now()`；脚步**只在落地且速度 > 0.05 m/s** 时按世界时间差计数。
- **`WorldDirector` 新增**：`signal noise_emitted(origin, loudness, source_id)`、`noise_event_count`、`emit_noise()`。
- **状态枚举**：`AnimalAI.State.FLEE = 3`、`HIDDEN = 4`（沿用 T019 的 `AnimalAI.State`，不另起一套）。
- 数值与阈值见 `Docs/Parameters.md`「感知与逃跑（T020 落地口径）」；命令、实测值与视觉留证见 `Docs/Evidence/T020.md`。

## 7. 生命周期与事务

`ALIVE → SETTLING`：先设状态与 `DEAD` 动作，取消交互/扑击，解绑旧输入；**创建档案一次**，提交世界变化，排队保存。
`SETTLING → SELECTING` 只在结算记录已形成后发生。
`SELECTING → SPAWNING → ALIVE`：合法物种、有效出生点、**新 LifeId、新身体**；**长期数据和时间不清空**。

保存失败显示"结算已发生但未落盘"，可重试；**禁止自动复活旧身体**。
下一次磁盘加载仍可能回退最近成功快照，**这一限制如实提示**。

**捕获**：检查目标存活/未记账 → 标记 Captured → **扣区域数量一次** → 建立捕获食物记录 → 移除活体表现 → 发信号 → 保存。
捕获食物余量和位置**必须持久化**，否则读档会丢收益或复制资源。

**初始化普通新游戏**：世界时间 0、猫解锁、资源满量、各区域初始数量；**只有明确新游戏确认才执行**。

### 7.1 地点发现与解锁门（T031 实现口径）

- **`GameState` 是唯一权威**（§1 既定分工）：长期发现 `discovered_places`（键 = 稳定地点 ID，跨世保留、
  按 ID 去重，`reset_for_new_game()` 才清）、发现→解锁规则 `discovery_unlock_rules`（**接线数据**：
  入口从 `SpeciesConfig.unlock_discovery` 汇总写入，reset 不清）、`record_place_discovery()`
  （首次记录 → 本世档案 + 事件 `discovery` + 按规则 `unlock_species()`）。
- **`DiscoveryTracker`（`scripts/systems/discovery_tracker.gd`）只观察**（仿 `Perception` 边界）：
  轮询玩家与 `discovery_points` 组标记的**水平距离**，进半径 → 调 `GameState.record_place_discovery()`；
  不改移动、不建节点、不含"发现者必须是猫"特判——正式门（初始只解锁猫）结构性保证第一个发现者必是猫。
- **解锁只挂在发现上**：捕获计数与解锁无任何连接（策划 §9.2「不要求捕食数量」）；
  解锁跨世保留、死亡不取消。
- **差异全部数据驱动**：`SpeciesConfig` 新增 `initially_unlocked`（猫 true / 鼠 false）与
  `unlock_discovery`（鼠 = `root_hole_courtyard_01`，稳定 ID 真源在关卡标记 meta，进存档后不得改）。
  `MainEntry` 与 `GameState` 不出现物种名。
- **`MainEntry.test_mode` 默认 `false`**（正式解锁接入后从 T030 的临时 true 收口）：
  正式模式只放行已解锁物种；测试模式显式打开后放行全部（策划 §9.2 的"明确区分"）。
- 参数与待定项（发现半径 2.0 m、扫描间隔 0.25 s、是否要求"看见"）见 `Docs/Parameters.md`
  「地点发现与解锁（T031 落地口径）」；命令与实测见 `Docs/Evidence/T031.md`。

### 7.2 生命结算页（T032 实现口径）

- **呈现层，不改状态机**：`LifeSettlePanel`（`scripts/ui/life_settle_panel.gd`，纯 `Control`）
  在 `life_settled` 之后盖在选物种画面**上方**；`_enter_select()` 时序不变
  （`SETTLING → SELECTING` 仍在结算记录形成后立即发生，本节 §7 契约不动）。
- **零平行数据**：面板只格式化入口传入的结算档案 + `events_for(life_id)` 按 kind 计数
  + `SpeciesConfig.display_title()`；不读 `GameState`、不新增字段/事件/存档数据。
- **只记录事实**（策划 §9.4）：`end_reason` / `damage_reason` / snapshot 四项数值照实呈现，不编造。
- **不是 CanvasLayer**（T030 H8 契约）：入口把面板加在 `MainMenu` **之后**（同 canvas 后加入者
  绘制在上）；可见时消费全部按键，`ui_accept`/`ui_cancel`/点击/「继续」消隐，出生自动隐藏。
- 重复伤害只结算一次（`LifeCycle.end_life`）→ 面板只呈现一次（`present_count()` 断言）。
- 捕猎/逃脱计数**只作展示**，与解锁零连接（§7.1 固化）。

### 7.3 正式选择呈现与解锁反馈（T033 实现口径）

- **UI 树序**：`MainEntry._ready` 构建 `hud → MainMenu → LifeStatus（状态文字）→ LifeSettlePanel`。
  状态文字绘制在菜单**之上**（修 ART09 遮挡遗留：同 canvas 后加入者绘制在上）；结算页仍最后加入=最上
  （§7.2 不动）；`MvpNote` 下移到 y=84 避开状态文字两行——两层文字同帧可读（`intersects=false` 断言）。
- **锁定呈现（数据驱动）**：`MainMenu.build(configs, settings, unlocked_ids)`——空数组=**全部可玩**
  （不传解锁信息的回退兼容，取证/旧调用方语义不变）；正式路径由入口传入 `GameState.unlocked_list()`。
  锁定卡与可玩卡**同构**（`Card_<id>`/`Thumb_<id>`/`Tagline`/`Note`，art09 契约不破），差异只是
  整卡压暗 + `Tagline=尚未解锁` + 解锁提示 Note + tooltip；真实显示名保留（不保密，与 MVP 说明一致）。
- **选择门只收在呈现层**：`MainMenu.select_species(锁定) → false` + 底部 hint 反馈文字
  （`last_lock_feedback()` 供断言），数字键对锁定物种同样只反馈；**出生权威门仍在 `LifeCycle.begin_spawn`**
  （§7.1 语义一字不动，入口 `selectable_slots` 未改）。
- **解锁即时刷新**：入口消费 `GameState.species_unlocked → menu.set_unlocked()`（显式调用，空=全锁，
  与 `build` 缺省语义相反——显式调用不回退，防"忘传=全放行"）。
- **Toast（最小可读版）**：`PlayerHud.show_toast(text, duration:=4.0)`——顶部居中金色 Label+深描边、
  无动画、真实毫秒截止隐藏；**不进 `hud_text()`**（T018 契约不动）。解锁文案=「新物种已解锁：
  `<SpeciesConfig.display_title()>`」；发现文案=「发现新地点：`<稳定 ID>`」（地点无配置显示名前照实显示 ID）。
- **重生整备**：旧身体由 `LifeCycle._release_body()` 改名+释放（T022/T030 已有）；断言固化
  两世后关卡 `Player` 恰好 1 个、无 `*_retired` 残留、`DiscoveryTracker.player` 重绑新身体。

## 8. 保存与恢复策略

**T037 落地口径（已实测；取代下文旧双槽设想）**：一个逻辑槽，物理上
`user://savegame_v1.json`（主档）+ `user://savegame_v1.json.bak`（上一版有效快照）。JSON 纯数据便于排查；
`Transform3D/Vector3` 以 `{"$t":[...]}` / `{"$v":[...]}` 标记编码，其余只用 String/int/float/bool/Array/Dictionary。

**T038 写入队列（已实测；补充 T037 的同步写语义）**：
- 所有生产保存经 `SaveManager.request_save()` 进单队列；主线程 `_process` 帧驱动，**不使用线程**
  （快照 < 数百 KB，全部真源在主线程，线程只会带来深拷贝与锁的成本）。
- 普通请求：`throttle_seconds=1.0`，窗口内多次请求合并为一次（`revision` 只 +1）；可被关键事务吸收丢弃。
- 关键事务（死亡、`pending` 清空、发现、解锁、退出）：逐条同步写，不合并、不丢弃、不被后续普通请求插队；
  退出 `_exit_tree` 通过 `flush_queue_now()` 绕过节流但仍串行。`MainEntry.save_now()` 保持立即语义。
- 串行守卫：`_writing/active_writes`，任何失败路径均复位；`queue_stats()` 暴露长度、计数、`last_failure_reason`、
  `last_warning`、写日志，`threaded=false`。

- **写入**：先写 `savegame_v1.json.tmp`（`flush` 后关闭）→ 复制主档到 `.bak.tmp` 并轮换 `.bak`
  （复制失败不阻断本次写，旧 `.bak` 保留并 warning）→ 主档改名 `.old` → `.tmp` 换入主档 → 删除 `.old`。
  最终换名失败回滚 `.old` 为主档并清理 tmp，返回 `write_failed`（主档不被截断）。写完 `revision += 1`。
  重复保存幂等：除 `revision/saved_reason` 外内容一致（断言 F1/F4）。
- **失败注入（仅测试）**：`fault_injection ∈ {tmp_open, disk_write, bak_copy, rename}`；写失败 Toast「存档写入失败」，
  备份失败 warning「存档已保存（备份更新失败）」，失败后队列复位、后续请求继续。
- **版本**：`save_version=1`；缺失/非整数/非有限 → `corrupt`；等值不匹配 → `version_mismatch`（**不隔离、不覆盖**）。
- **损坏恢复**：解析失败或结构非法 → 主档改名 `.corrupt-<unix时间戳>`（不删除）→ 用 `.bak` 再校验；
  可用则 `recovered_backup`，否则 `corrupt`（不静默开新游戏）。字段缺失补默认并记 `repairs`；
  负数/超容量夹紧、非有限值回默认、坏条目跳过；`current_life` 与 `pending` 同时非空 → 清 `pending`。
  **主档缺失但 `.bak` 有效** → `recovered_backup`（「主存档缺失，已从备份恢复」），兜底换名窗口崩溃。
- **玩家可见**：修复载入 Toast「存档已修复 N 处后载入」；备份恢复「主存档损坏，已从备份恢复」；
  损坏无备份「存档损坏，已隔离；未载入」；版本不兼容「存档版本不兼容（vN），未载入」。
- **自动存盘时机**：死亡结算（`pending` 写入，第 1 次）→ 结算页展示后清 `pending`（第 2 次）；
  新发现/新解锁各自落盘；退出时 `_exit_tree` 存一次。只有正式运行（`current_scene == self`）启用；
  测试/工具显式 `set_persistence_enabled(true)`。
- **加载顺序**：`SaveManager.validate` → 建关卡/区域账本 → 世界时间 → 区域种群 → 资源点（按稳定 ID 匹配/补建）
  → 长期层（档案/事件/发现/解锁/计数器）→ 当前生命（存活恢复身体；`pending` 非空补弹结算页）→ 绑定 HUD/输入。
- **安全项**：存档只落在 `user://`，不写个人绝对路径与令牌（断言 A7）；设置仍另存 `user://settings.cfg`，不混入死亡进度。

## 9. 与 UE5 方案的差异清单（迁移对照）

| UE5 (v0.1) | Godot 4 (v0.2) | 影响 |
|---|---|---|
| Blueprint 连线图 | GDScript 文本 | **agent 可直接编写与 diff** |
| `UCLASS`/`Actor`/`Character` | `Node3D`/`CharacterBody3D` | |
| ActorComponent | 组合子 Node | |
| PrimaryDataAsset | `Resource` + `.tres` | 纯文本，可 diff |
| BlueprintInterface | 基类 + `has_method()` 鸭子类型 | **范式变化** |
| UMG UserWidget | `Control` 节点场景 | |
| Enhanced Input | InputMap + `Input` 单例 | |
| `GameInstance` | Autoload 单例 | |
| `SaveGame` | `Resource`/JSON + `FileAccess` | |
| Distance cm | **Distance m（÷100）** | **全参数换算** |
| `MaxStepHeight` | **无直接等价物** | **P1 高风险，需自实现** |
| `Sweep`/`LineTrace` | `move_and_collide`/`ray_cast` | |
| Navigation Mesh | `NavigationRegion3D`/`NavigationAgent3D` | |
| 事件分发器 | `signal` | |
| `RunUAT` | `--export-release` | |
| `.uasset`/`.umap` | `.tscn`/`.tres` | 均为纯文本 |

## 10. 扩展边界

本设计不要求一开始创建表中全部资产。**对应任务才创建对应资产和测试。**
新自定义导航、GDExtension、插件或技术路线变更在 `Decisions` 记录并按 AGENTS 的确认边界处理。
