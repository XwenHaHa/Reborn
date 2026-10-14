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
| `res://autoload/world_director.gd` | **Autoload 单例**。统一世界时间、资源注册、NPC 生成与区域账本 | T014/T034 |
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

**读取校验**：拒绝未知版本、重复 ID、未知物种、负数/超容量、非有限数值（`is_finite()`）。
恢复可选指标前夹紧到 0～100 并**记录修复**。严重结构错误走坏档回退，**不静默开新游戏**。
设置数据另存，不混入死亡进度。

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

## 7. 生命周期与事务

`ALIVE → SETTLING`：先设状态与 `DEAD` 动作，取消交互/扑击，解绑旧输入；**创建档案一次**，提交世界变化，排队保存。
`SETTLING → SELECTING` 只在结算记录已形成后发生。
`SELECTING → SPAWNING → ALIVE`：合法物种、有效出生点、**新 LifeId、新身体**；**长期数据和时间不清空**。

保存失败显示"结算已发生但未落盘"，可重试；**禁止自动复活旧身体**。
下一次磁盘加载仍可能回退最近成功快照，**这一限制如实提示**。

**捕获**：检查目标存活/未记账 → 标记 Captured → **扣区域数量一次** → 建立捕获食物记录 → 移除活体表现 → 发信号 → 保存。
捕获食物余量和位置**必须持久化**，否则读档会丢收益或复制资源。

**初始化普通新游戏**：世界时间 0、猫解锁、资源满量、各区域初始数量；**只有明确新游戏确认才执行**。

## 8. 保存与恢复策略

一个逻辑进度槽，物理上用 `Reborn_A` / `Reborn_B` 双槽（`user://`）。
**Revision 单调增加，每次写非当前槽**；写成功后重新读取并做结构校验，才视为最新完成快照；**保留另一槽，不删除旧槽**。
加载检查两个槽，选 Revision 最大的**有效**快照，**不依赖未验证的原子替换**。

格式用 `ResourceSaver` + `save_data.gd`（Godot 原生，类型安全），或 JSON 便于人工排查。
**T037 实测后固定，不预先假定可靠性。**

一次仅一个异步写入。新变化保留最新待写 Revision，当前写完再生成最新权威快照；
**关键事务不可在序列化中途修改该快照**。节流 1 s（见 `Parameters.md`），死亡/退出绕过等待但仍串行。
正常退出等结果，失败提供重试或明确"退出将丢最近进度"的确认。

双槽是**需要故障注入验证**的回退方案，**不宣称任何断电场景零丢失**。
无有效槽时显示恢复失败与明确新游戏选项，**不静默覆盖**。

**加载顺序**：校验数据 → 暂停模拟 → 恢复世界数据 → 重建固定与捕获资源 →
根据区域总数实例化 NPC → 选择结算或恢复身体 → 验证落点与安全距离 → 绑定 UI/输入 → 解除暂停。
短暂保护期间禁止敌人伤害，不能无限重复领资源。

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
