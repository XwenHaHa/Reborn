# 技术设计与数据契约 v0.1

本文件是首个原型的实现基线，不是已存在工程说明。保持 UE5 蓝图优先，不默认切换 C++；T001/T002 必须实测编辑器资产自动化能力，未通过时按 Bootstrap 的阻塞规则执行。

## 1. 路径与职责

预定工程：`Game/Reborn/Reborn.uproject`。UE 虚拟资产根：`/Game/Reborn`（磁盘 `Game/Reborn/Content/Reborn`）。已有工程时先复用，禁止强制新建覆盖。

| 类型/资产路径 | 基类与职责 | 创建任务 |
|---|---|---|
| Core/BP_RebornGameInstance | GameInstance，持有世界数据、长期记录、存档管理对象 | T030/T036 |
| Core/BP_RebornGameMode | GameModeBase，出生、身体替换、生命周期转换 | T002/T030 |
| Core/BP_RebornPlayerController | PlayerController，输入模式、HUD/菜单、玩家输入入口 | T009/T018 |
| Characters/BP_AnimalBase | Character，物种数据、身体、伤害/动作入口；玩家和 NPC 共用 | T008 |
| Characters/BP_Cat、BP_Mouse | AnimalBase 子类，配置引用与表现，不复制公共生存规则 | T008/T010 |
| Characters/BPC_Survival | ActorComponent，指标、消耗、警告、死亡通知 | T014 |
| Characters/BPC_Interaction | ActorComponent，目标查询、交互动作和取消 | T016 |
| AI/BP_AnimalAIController | AIController，分物种有限状态机、路径、最后已知位置 | T019/T023 |
| Data/PDA_Species | PrimaryDataAsset，物种参数，实例 DA_Cat/DA_Mouse | T008 |
| Core/BPI_Interactable | BlueprintInterface，交互查询/提交/取消 | T016 |
| World/BP_WorldDirector | Actor，统一世界时间入口、资源注册和 NPC 生成；世界数据不只存在 Actor 上 | T014/T034 |
| World/BP_ResourcePoint、BP_SafeSpot、BP_DiscoveryPoint | Actor，稳定 ID、表现与交互 | T017/T031 |
| Core/BP_SaveManager | GameInstance 持有的 UObject，串行保存、读档和错误；不能默认 UObject 接收 Actor Tick | T037 |
| Core/SG_Reborn | SaveGame，纯数据快照 | T037 |
| UI/WBP_HUD、WBP_MainMenu、WBP_LifeSummary | UserWidget，观察状态，不直接修改资源账本 | T018/T032/T041 |
| Maps/L_MovementLab、L_AIPlayground、L_SaveTest、L_Courtyard | 编辑器关卡资产，测试与主体验分别管理 | T002/T011/T043 |

P4 前无 GameInstance 世界账本时 WorldDirector 暂存最小数据；T036 迁移为 GameInstance 所有，禁止创建两份同时权威的数据。使用事件分发器更新 UI，避免 UI 每帧写游戏状态。

## 2. 单位与命名

距离 cm、现实经过时间 real seconds、世界时间 sim seconds，角度 degree、指标 0～100。WorldTime 从新游戏的 0 开始；禁止把墙钟系统时间当资源刷新计时。

SpeciesId：`Cat`、`Mouse`（Name）；区域：`Courtyard`、`Grass`、`Roots`、`Creek`。固定对象 Name ID 在地图中唯一；运行期捕获食物使用 GUID ID，加载后继续保留，不能每次重新生成。

枚举：E_LifeState={Alive,Settling,Selecting,Spawning}；E_ActionState={Idle,Interacting,Pouncing,Recovering,Dead}；E_FoodType={Meat,Seed}；E_AIState={Explore,Forage,Alert,Flee,Hidden,Approach,Chase,Search,Attack}。不合法转换拒绝并记录原因。

## 3. 数据结构

全部为蓝图可用结构；没有 Actor/UObject 引用的部分可进存档。

- F_SurvivalState：Health/Hunger/Thirst/Stamina(float)，LastDamageReason(Name)。
- F_SpeciesConfig：SpeciesId(Name)、Movement/Perception/Survival 起测字段（见 Parameters）、AllowedFoodTypes(E_FoodType 数组)、bCanJump/bCanPounce/bCanUseMouseTunnel(bool)。
- F_LifeEvent：EventId(Guid)、LifeId(Guid)、WorldTime(double 或当前引擎支持的等价类型)、Type(Name)、SourceId(string)、Reason(Name)、Amount(float)。
- F_LifeRecord：LifeId、SpeciesId、Duration(float)、EndReason(Name)、FoodCount/CaptureCount/EscapeCount(int)、DiscoveredIds(Name 数组)、Events(F_LifeEvent 数组)。原型每世最多存 200 条事件，超出保留统计与最近事件，避免无限日志增长。
- F_ResourceRecord：Id(string)、RegionId(Name)、Kind={FixedFood,CaptureFood,Water}、FoodType、Units(int)、Capacity(int)、NextRefillAt(float)、RefillInterval(float)、Transform、ExpireAt(float，0 表示不失效)。水点无限饮水、不储存可扣 Units，仍有稳定 ID。
- F_RegionRecord：RegionId、SpeciesId、TotalCount(int)、Capacity(int)、NextRecoverAt(float)、RecoverInterval(float)。TotalCount 包括已实例化与未实例化个体；实例化/销毁表现不改变它。
- F_CurrentLife：LifeId、SpeciesId、LifeState、Transform、Survival、SpawnWorldTime、LastSafeSpotId(Name)、CurrentEvents、CurrentDiscoveredIds。
- F_WorldSnapshot：SaveVersion(int=1)、Revision(int64)、WorldTime、Resources 数组、Regions 数组、DiscoveredIds、UnlockedSpecies、LifeRecords、CurrentLife、PendingSettlementLifeId(Guid)。

读取校验：拒绝未知版本、重复 ID、未知物种、负数量/超过容量、非有限数值；恢复可选指标前夹紧到 0～100并记录修复。严重结构错误走坏档回退，不静默新游戏。设置数据另存，不混入死亡进度。

## 4. 输入与交互接口

Enhanced Input：IA_Move(Vector2D)、IA_Look(Vector2D)、IA_Sprint/IA_Crouch/IA_Jump/IA_Pounce/IA_Interact/IA_Pause/IA_Record(bool)，IMC_Animal 统一映射。物种能力决定动作能否触发，不通过删输入来复制控制器。

BPI_Interactable：

- QueryInteraction(Interactor Actor) → bAllowed(bool), ActionId(Name), Duration(float), DenyReason(Name)。
- CommitInteraction(Interactor Actor, TransactionId Guid) → bSuccess(bool), Reason(Name)。
- CancelInteraction(TransactionId Guid)；取消无收益。

距离、视线和允许物种在查询及提交时都检查；只选择一个有效目标。提交前把事务标为进行中，扣资源与加收益在同一主线程操作中完成，结束后才发 OnCommitted。重复 TransactionId 返回既有结果，不重复扣资源。

角色事件：OnSurvivalChanged(State)、OnDied(LifeId,Reason)、OnActionNoise(SourceId,Location,Loudness,WorldTime)、OnCaptured(CaptureId,VictimId,RegionId)、OnDiscovered(LocationId)、OnLifeEnded(Record)。CaptureId 和 LifeId 去重集合随权威状态维护。

## 5. 时间、动作和碰撞

WorldDirector 使用经过时间驱动 sim time，默认 1:1；暂停/结算/选择/加载不推进。低频消耗可 0.2s 更新但必须使用实际 delta；动作/移动依赖引擎帧更新，不能固定每帧扣值。

起测碰撞使用引擎 Pawn、WorldStatic/WorldDynamic、Visibility；先不新增未经验证的自定义通道。扑击用 Sweep，障碍优先于障碍后的猎物；命中 AnimalBase 后再检查物种和 Alive。交互视线用 Visibility，目标组件响应要实测。

草叶视觉遮挡与 AI 可见性不是同一回事：草丛 Volume 提供 VisibilityFactor，实体墙由视线 Trace 阻挡。鼠洞真实通道尺寸限制猫，安全点标记不应让猫传送穿过墙。

可蹲姿只有碰撞空间允许才改变/恢复胶囊尺寸。导航 Supported Agents 由两种实际胶囊验证；失败时禁止用瞬移伪装寻路成功。

## 6. 感知与 AI 转换

视线有效时更新 LastKnownPosition；声音只创建 NoiseLocation/Time。失去视线后 Chase 转 Search，Search 到最后已知位置后超时放弃。隐藏后不得读取玩家真实坐标导航。

鼠：Explore/Forage → Alert → Flee → Hidden → Explore。Alert 期间可提前逃跑；安全点不可达则找遮挡，连续失败按超时退出路径请求并重新选择，不每帧请求路径。

猫：Explore → Alert → Approach → Chase → Attack；失去目标 → Search → Explore。攻击开始即保存方向与目标信息，伤害帧重新检查距离/遮挡/目标存活；预警后不中必然命中。

EscapeCount 只在一场有效 Chase 结束且玩家存活时增加一次，以 EncounterId 去重。隐藏瞬间不立即刷逃脱记录。

## 7. 生命周期与事务

Alive→Settling：先设置状态和 Dead 动作，取消交互/扑击，解绑旧输入；创建档案一次，提交世界变化，排队保存。Settling→Selecting 只在结算记录已形成后发生。Selecting→Spawning→Alive：合法物种、有效出生点、新 LifeId、新身体；长期数据和时间不清空。

保存失败显示结算已发生但未落盘，可重试；禁止自动复活旧身体。下一次磁盘加载仍可能回退最近成功快照，这一限制如实提示。

捕获：检查目标 Alive/未记账 → 标记 Captured → 扣区域数量一次 → 建立捕获食物记录 → 移除活体表现 → 发布事件 → 保存。捕获食物余量和位置必须持久化，否则读档会丢收益或复制资源。

初始化普通新游戏：世界时间 0、猫解锁、资源满量、各区域初始数量；只有明确新游戏确认才执行。

## 8. 保存与恢复策略

一个逻辑进度槽，物理上可使用 `Reborn_A`、`Reborn_B` 双槽。Revision 单调增加，每次写非当前槽；写成功后重新读取并做结构校验，才将其视为最新完成快照；保留另一槽，不删除旧槽。加载检查两个槽，选 Revision 最大的有效快照，不依赖未验证的原子替换。

一次仅一个异步写入。新变化保留最新待写 Revision，当前写完再生成最新权威数据快照；关键事务不可在序列化中途修改该快照。节流间隔见 Parameters，死亡/退出请求立即进入队列；正常退出等结果，失败提供重试或明确“退出将丢最近进度”的确认。

双槽是需要故障注入验证的回退方案，不宣称任何断电场景零丢失。无有效槽时显示恢复失败与明确新游戏选项，不能静默覆盖。

加载顺序：校验数据→暂停模拟→恢复世界数据→重建固定与捕获资源→根据区域总数实例化 NPC→选择结算或恢复身体→验证落点与安全距离→绑定 UI/输入→解除暂停。短暂保护期间禁止敌人伤害，不能无限重复领资源。

## 9. 扩展边界

本设计不要求一开始创建表中全部资产。对应任务才创建对应资产和测试。新自定义导航、C++、插件或技术路线变更在 Decisions 记录并按 AGENTS 的确认边界处理。
