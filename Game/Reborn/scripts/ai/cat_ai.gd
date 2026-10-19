class_name CatAI
extends AnimalAI
## 猫 NPC：**巡游 → 发现 → 警戒 → 接近（T023）** + **追击 → 搜索 → 放弃（T024）**
##
## 设计约束（`Docs/Tasks/T023.md`、`Docs/Tasks/T024.md`）：
## - **复用**既有机制：`Perception`（物种无关：威胁 = 异种且存活的身体）与 `AnimalAI`（状态/世界时间/导航/失败回退）。
##   本脚本**不实现感知算法、不写物种名分支、不直接改位移**（只写 `body.move_intent`）。
## - 状态链：`EXPLORE → ALERT → APPROACH → CHASE`；失去目标 `ALERT → SEARCH → EXPLORE`（T024 按
##   `Docs/TechnicalDesign.md` §6 第 226/230 行把 T023 的"失视 → EXPLORE"升级为"失视 → SEARCH"）。
## - **攻击与伤害结算属 T025**：本任务到 `attack_range` 只停住，不扑击、不扣血。
## - 参数真源：`Docs/Parameters.md` 第 22/23 行（视距 / 半角 / 听觉走**物种配置** `cat.tres`）、
##   第 69 行（猫 NPC：**Alert 0.4 s**、**AttackRange 65**、**搜索超时 5 s**、**鼠洞外等待最大 6 s**）、
##   第 73 行（Loudness、草丛、近距豁免）。
## - **隐藏后不得读取玩家真实坐标导航**（§6 第 226 行）：`SEARCH` 只用"失视时刻的快照"；
##   搜索 / 洞口等待期间**永不更新**目标点，猎物瞬移到别处也不跟（见 `Docs/Tasks/T024.md` §4 硬约束）。

## 看见猎物（"发现"）：只报告，不改位移
signal prey_spotted(prey_id: String, position: Vector3)
## 失视（要么被遮挡、要么跑远）
signal prey_lost(prey_id: String)
## 一场追击开始（`encounter_id` 形如 `enc-3`）
signal chase_started(encounter_id: String)
## 一场追击结束：`prey_alive` 为真才算一次"逃脱"（`Docs/TechnicalDesign.md` §6 末）
signal chase_ended(encounter_id: String, prey_alive: bool)

const PATROL_GROUP := &"patrol_points"
## 组里没有巡逻点时的环形候选个数（确定顺序：`i × 45°`）
const RING_CANDIDATES := 8
## "停住"的迟滞：比 `attack_range` 近 5 cm 才算退出 `in_range`，避免在边界反复进出
const RANGE_HYSTERESIS := 0.05
## 鼠洞标记的 `metadata/kind` 取值（T011/T020 约定）
const HOLE_KIND := "mouse_hole"

## `Parameters.md` 第 69 行：猫 NPC Alert 0.4 s（基类默认 0.3 s 是鼠的，`setup()` 里覆盖）
@export var npc_alert_time: float = 0.4
## `Parameters.md` 第 69 行：AttackRange 65 cm。**本任务只用它决定"追到哪里停"**，伤害结算属 T025
@export var attack_range: float = 0.65
## 关掉巡游 → 原地待命（**调试 / 夹具用**；真实关卡由生成的一方决定）
@export var patrol_enabled: bool = true
# 以下 5 个是 T023 新增的**实现默认值**（`Parameters.md` 无对应行 → 记入 Evidence 开放项，待负责人并入正式起测值）
@export var patrol_radius: float = 6.0
@export var patrol_pause: float = 1.0
@export var patrol_min_move: float = 0.5
@export var patrol_retry_wait: float = 1.0
@export var approach_repath_interval: float = 0.5
# --- T024 追击与搜索 ---
## `Parameters.md` 第 69 行：搜索超时 5 s（从**进入 `SEARCH`** 起算）
@export var search_timeout: float = 5.0
## `Parameters.md` 第 69 行：鼠洞外等待最大 6 s（从**到达洞口**起算）
@export var hole_wait_max: float = 6.0
# 以下 4 个是 T024 新增的**实现默认值**（`Parameters.md` 无对应行 → 记入 Evidence 开放项）
@export var chase_repath_interval: float = 0.25
@export var search_arrive_radius: float = 0.6
@export var hole_search_radius: float = 0.6
## 洞口场景的**总上限**（含赶路）：兜底"不无限走"（`search_timeout` 只管普通搜索）
@export var search_overall_max: float = 12.0
## 判定"猎物跳变（跑开 / 瞬移）"的距离阈值（米）→ `APPROACH → CHASE`
@export var chase_trigger_move: float = 0.5

# --- T025 攻击 ---
## 允许转入 `ATTACK`（默认开；**测试夹具可关掉**以单独验证追击 / 搜索，见 T024 §7 D7）
@export var attack_enabled: bool = true
## 攻击被拒后的重试间隔（秒）——**实现默认值**（`Parameters.md` 无对应行）
@export var attack_retry_interval: float = 0.25
## 连续被拒多少次就回 `CHASE` 重新走位（**不永久卡**）——实现默认值
@export var attack_fail_max: int = 8

var _patrol_ids: Array[String] = []
var _patrol_index := 0
var _patrol_target_id := ""
var _patrol_pause_until := 0.0
var _patrol_retry_at := 0.0
var _patrol_reached := 0
var _detect_count := 0
var _approach_count := 0
var _lost_sight_count := 0
var _approach_dist := INF
## 当前这次警戒是不是因为"看见"起的（决定警戒结束后回 `SEARCH` 还是 `EXPLORE`）
var _alert_from_sight := false
var _last_reacted_noise := 0.0
var _last_repath_at := -1000.0
var _prey_id := ""

# --- T024：追击与搜索 ---
var _search_started_at := 0.0
var _search_target := Vector3.ZERO
var _search_count := 0
var _give_up_count := 0
var _last_search_repath_at := -1000.0
var _hole_id := ""
var _hole_point := Vector3.ZERO
var _hole_radius := 0.0
## 洞口等待开始时刻（`<= 0` = 还没到洞口、不在等待）
var _hole_wait_started_at := -1.0
var _chase_repath_at := -1000.0
var _chase_count := 0
var _escape_reports := 0
var _encounter_id := ""
var _encounter_seq := 0
var _encounter_settled := false
## 上一帧看见猎物时的位置（判"跳变"用；只在看得见时更新）
var _prey_seen_pos := Vector3.ZERO
var _has_prey_seen_pos := false
## 攻击（T025）：被拒后多久再试一次（秒）——**实现默认值**
var _attack_retry_at := -1000.0
## 连续被拒次数（达到 `attack_fail_max` 就回 `CHASE` 重新走位，**不永久卡**）
var _attack_fail_streak := 0


# ---------------------------------------------------------------------------
# 生命周期
# ---------------------------------------------------------------------------

func setup(p_body: AnimalBody) -> void:
	super(p_body)
	if npc_alert_time > 0.0:
		alert_max_time = npc_alert_time
	# T025：攻击距离以**物种配置**为真源（`Parameters.md` 第 69 行 AttackRange 65 cm）；
	# `@export` 的默认值只在配置缺失时兜底，避免同一数值出现两个真源。
	if body != null and is_instance_valid(body) and body.species_config != null \
			and body.species_config.attack_range > 0.0:
		attack_range = body.species_config.attack_range
	change_state(State.EXPLORE, &"boot")


# ---------------------------------------------------------------------------
# 行为（子类覆盖点）
# ---------------------------------------------------------------------------

func _step(world_time: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	# 0) 逃脱账本：**只要不再处于 CHASE**（警戒 / 搜索 / 等待 / 探索）就把这场追逐结算掉。
	#    放在这里而不是分散在各转移里，保证"一场只结算一次"且覆盖所有出口（T024 §4）。
	if not _encounter_id.is_empty() and _state != State.CHASE:
		_settle_encounter()
	# 1) 失败等待：停住（基类到点会回 EXPLORE，**不永久阻塞**）
	if _state == State.WAIT:
		body.move_intent = Vector2.ZERO
		return
	# 2) 警戒：停手停脚（基类 `_on_alert_started()` 已清意图并取消交互）
	if _state == State.ALERT:
		body.move_intent = Vector2.ZERO
		return
	# 3) 感知 → 警戒 / 失视 / 重新发现
	_react_to_senses(world_time)
	if _state == State.ALERT or _has_alert:
		body.move_intent = Vector2.ZERO
		return
	# 4) 状态分派
	if _state == State.APPROACH:
		_step_approach(world_time)
		return
	if _state == State.CHASE:
		_step_chase(world_time)
		return
	if _state == State.ATTACK:
		_step_attack(world_time)
		return
	if _state == State.SEARCH:
		_step_search(world_time)
		return
	# 5) 巡游（EXPLORE）
	_step_patrol(world_time)


## 把"看见 / 听见"翻译成状态变化。**本函数不改位移**，只调 `alert_for()` / 切状态。
func _react_to_senses(world_time: float) -> void:
	var p := _perception()
	if p == null:
		return
	var visible := p.is_threat_visible()
	# 搜索期间：只认"重新看见"（→ CHASE），**不被声音带离快照**（T024：搜索是承诺，不是重新警戒）
	if _state == State.SEARCH:
		if visible:
			_enter_chase(world_time, &"reacquired")
		return
	if visible:
		if _state == State.APPROACH or _state == State.CHASE or _state == State.ATTACK:
			return          # 已经在接近 / 追击 / 攻击 → 交给各自的 `_step_*`
		if not _has_alert:
			_alert_from_sight = true
			_detect_count += 1
			_prey_id = p.threat_id()
			_approach_dist = horizontal_distance_to(p.threat_position())
			prey_spotted.emit(_prey_id, p.threat_position())
			alert_for(p.threat_position(), &"saw_prey")
		return
	# 看不见了：接近 / 追击中 → 警戒（0.4 s）后再决定搜索还是重新接近
	if _state == State.APPROACH or _state == State.CHASE or _state == State.ATTACK:
		_alert_from_sight = true
		alert_for(p.last_seen_position(), &"lost_sight")
		return
	# 只听见声音：警戒到**发生位置**（不跟踪声源真实位置，`TechnicalDesign` §6）
	var noise_time := p.last_noise_time()
	if noise_time > _last_reacted_noise:
		_last_reacted_noise = noise_time
		_alert_from_sight = false
		alert_for(p.last_noise_position(), &"heard_noise")


## 警戒结束：看得见就接近；看不见（且之前看得见）就去**搜索最后已知位置**
func _on_alert_ended(world_time: float) -> void:
	var p := _perception()
	if p != null and p.is_threat_visible():
		_enter_approach(world_time, &"alert_done")
		return
	_clear_destination()
	if body != null and is_instance_valid(body):
		body.move_intent = Vector2.ZERO
	if _alert_from_sight:
		_alert_from_sight = false
		_lost_sight_count += 1
		if not _prey_id.is_empty():
			prey_lost.emit(_prey_id)
		# T025 试过"猎物已经死了就跳过搜索"的捷径 → **撤回**：那要靠 `_prey_alive()` 全图查询，
		# 等于让猫读到上帝视角信息（它并没有看见猎物死）；一律走既有"失视 → SEARCH → 超时 → EXPLORE"。
		_enter_search(world_time, &"lost_sight")
		return
	change_state(State.EXPLORE, &"alert_done")


## 进入接近：清掉巡游目的地，节流计时归零
func _enter_approach(world_time: float, reason: StringName) -> void:
	_clear_destination()
	_last_repath_at = -1000.0
	_approach_count += 1
	_seed_prey_seen_pos()
	change_state(State.APPROACH, reason)


## 接近（**警戒后的首次接近**）：只在看得见时更新目的地；到 `attack_range` 停住，**不扑击**。
## 猎物在视野里**跳变**（跑开 / 瞬移）且仍在攻击距离外 → 转入持续追击（T024 D1）。
func _step_approach(world_time: float) -> void:
	var p := _perception()
	if p == null or not p.is_threat_visible():
		return
	var prey_pos := p.threat_position()
	_approach_dist = horizontal_distance_to(prey_pos)
	var jump := _prey_seen_pos.distance_to(prey_pos) if _has_prey_seen_pos else 0.0
	_prey_seen_pos = prey_pos
	_has_prey_seen_pos = true
	if jump > chase_trigger_move and _approach_dist > attack_range + RANGE_HYSTERESIS:
		_enter_chase(world_time, &"chasing")
		return
	if _approach_dist <= attack_range + RANGE_HYSTERESIS:
		if _should_attack():
			_enter_attack(world_time, &"in_range")
			return
		body.move_intent = Vector2.ZERO
		_clear_destination()
		set_reason(&"in_range")
		return
	if not _has_destination or world_time - _last_repath_at >= approach_repath_interval:
		_last_repath_at = world_time
		if not _set_destination(prey_pos):
			_register_path_failure(world_time)
			return
		set_reason(&"closing")
	_advance_along_path()
	_track_progress(world_time)


# ---------------------------------------------------------------------------
# 追击（T024）
# ---------------------------------------------------------------------------

## 进入追击：新开一场 `encounter`（逃脱账本按场结算）、清掉搜索与洞口账
func _enter_chase(world_time: float, reason: StringName) -> void:
	if _state == State.CHASE:
		set_reason(reason)
		return
	_clear_destination()
	_last_repath_at = -1000.0
	_chase_repath_at = -1000.0
	_clear_search_state()
	_seed_prey_seen_pos()
	_begin_encounter()
	change_state(State.CHASE, reason)


## 追到攻击距离就停（**不扑击、不伤害**，攻击属 T025）；否则按 `chase_repath_interval` 节流重设目的地
func _step_chase(world_time: float) -> void:
	var p := _perception()
	if p == null or not p.is_threat_visible():
		return
	var prey_pos := p.threat_position()
	_approach_dist = horizontal_distance_to(prey_pos)
	_prey_seen_pos = prey_pos
	_has_prey_seen_pos = true
	if _approach_dist <= attack_range + RANGE_HYSTERESIS:
		if _should_attack():
			_enter_attack(world_time, &"in_range")
			return
		body.move_intent = Vector2.ZERO
		_clear_destination()
		set_reason(&"in_range")
		return
	if not _has_destination or world_time - _chase_repath_at >= chase_repath_interval:
		_chase_repath_at = world_time
		if not _set_destination(prey_pos):
			_register_path_failure(world_time)
			return
		set_reason(&"chasing")
	_advance_along_path()
	_track_progress(world_time)



# ---------------------------------------------------------------------------
# 攻击（T025）
# ---------------------------------------------------------------------------

## 现在该不该转入攻击：开关打开 + 物种会攻击 + 组件在
func _should_attack() -> bool:
	if not attack_enabled:
		return false
	if body == null or not is_instance_valid(body):
		return false
	if not body.can_attack():
		return false
	return _attack_comp() != null


## 进入攻击：停住 + 锁朝向由 `AttackSettlement` 在启动时负责
func _enter_attack(world_time: float, reason: StringName) -> void:
	_clear_destination()
	if body != null and is_instance_valid(body):
		body.move_intent = Vector2.ZERO
	_last_repath_at = -1000.0
	_attack_retry_at = -1000.0
	_attack_fail_streak = 0
	_seed_prey_seen_pos()
	change_state(State.ATTACK, reason)


## 攻击：停住 → 请求攻击（预警 0.45 s → 伤害帧 35 → 恢复 1.2 s）→ 恢复完再打。
## **本状态不写位移、不扑击**（`Parameters.md` 第 69 行；伤害在 `AttackSettlement` 里结算）。
## 猎物跑出攻击距离 → 回 `CHASE` 重新走位；连续被拒几次也回 `CHASE`（**不永久卡**）。
func _step_attack(world_time: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	body.move_intent = Vector2.ZERO
	var comp := _attack_comp()
	if comp == null:
		_enter_chase(world_time, &"chasing")
		return
	var p := _perception()
	if p != null and p.is_threat_visible():
		_approach_dist = horizontal_distance_to(p.threat_position())
		if _approach_dist > attack_range + RANGE_HYSTERESIS:
			_enter_chase(world_time, &"chasing")
			return
	if comp.is_attacking():
		set_reason(&"attacking")
		return
	if comp.is_in_recovery():
		set_reason(&"recovering")
		return
	if world_time < _attack_retry_at:
		return
	_attack_retry_at = world_time + attack_retry_interval
	if body.request_attack():
		_attack_fail_streak = 0
		set_reason(&"attacking")
		return
	# 被拒（多半是 `target`：朝向 / 遮挡 / 目标层）→ 记几次后回 CHASE 重新走位
	_attack_fail_streak += 1
	if _attack_fail_streak >= attack_fail_max:
		_attack_fail_streak = 0
		_enter_chase(world_time, &"chasing")

# ---------------------------------------------------------------------------
# 搜索（T024）
# ---------------------------------------------------------------------------

## 进入搜索：把"最后已知位置"**快照**下来（此后不再更新），并判定是否落在鼠洞外
func _enter_search(world_time: float, reason: StringName) -> void:
	_clear_destination()
	if body != null and is_instance_valid(body):
		body.move_intent = Vector2.ZERO
	var p := _perception()
	var target := _search_target
	if p != null and p.has_seen():
		target = p.last_seen_position()
	elif body != null and is_instance_valid(body):
		target = body.global_position
	_search_target = target          # **快照**：搜索 / 等待期间永不更新
	_search_started_at = world_time
	_search_count += 1
	_last_search_repath_at = -1000.0
	_clear_search_state()
	var hole := _find_hole_near(_search_target)
	if hole != null:
		_hole_id = String(hole.name)
		_hole_point = hide_spot_point(hole)
		_hole_radius = hide_spot_radius(hole)
	_set_destination(_search_goal())
	change_state(State.SEARCH, reason)


## 搜索：走去快照点（或洞口）→ 到了就停着找；两个上限（5 s / 6 s）+ 总上限兜底，**绝不无限走**
func _step_search(world_time: float) -> void:
	var p := _perception()
	if p != null and p.is_threat_visible():
		_enter_chase(world_time, &"reacquired")
		return
	var overall := maxf(0.0, world_time - _search_started_at)
	var in_hole_wait := _hole_wait_started_at > 0.0
	# ① 洞口等待：从**到达洞口**起 `hole_wait_max`（6 s）
	if in_hole_wait and world_time - _hole_wait_started_at >= hole_wait_max:
		_give_up(&"hole_timeout")
		return
	# ② 普通搜索：从**进入 SEARCH** 起 `search_timeout`（5 s）
	if not in_hole_wait and overall >= search_timeout:
		_give_up(&"search_timeout")
		return
	# ③ 总上限（含赶路）：兜底"不无限走"
	if overall >= search_overall_max:
		_give_up(&"search_timeout")
		return
	var goal := _search_goal()
	var arrive := search_arrive_radius
	if not _hole_id.is_empty():
		# 洞口：停在**洞外**（至少 `radius + 0.10`），不贴进洞里
		arrive = maxf(search_arrive_radius, _hole_radius + 0.10)
	if horizontal_distance_to(goal) <= arrive:
		body.move_intent = Vector2.ZERO
		_clear_destination()
		if not _hole_id.is_empty():
			if _hole_wait_started_at <= 0.0:
				_hole_wait_started_at = world_time
			set_reason(&"hole_wait")
			return
		set_reason(&"arrived")
		return
	if not _has_destination or world_time - _last_search_repath_at >= approach_repath_interval:
		_last_search_repath_at = world_time
		if not _set_destination(goal):
			_register_path_failure(world_time)
			return
	if _reason != &"moving_to_last_seen":
		set_reason(&"moving_to_last_seen")
	_advance_along_path()
	_track_progress(world_time)


## 放弃搜索：回探索 + 记一次放弃（"不永久卡"的证据）
func _give_up(reason: StringName) -> void:
	_give_up_count += 1
	_clear_search_state()
	_clear_destination()
	if body != null and is_instance_valid(body):
		body.move_intent = Vector2.ZERO
	change_state(State.EXPLORE, reason)


## 搜索目的地：有洞口就去洞口，否则去快照点
func _search_goal() -> Vector3:
	return _hole_point if not _hole_id.is_empty() else _search_target


## 清掉搜索的洞口账（进入追击 / 放弃时调）
func _clear_search_state() -> void:
	_hole_id = ""
	_hole_point = Vector3.ZERO
	_hole_radius = 0.0
	_hole_wait_started_at = -1.0


## 快照点 `hole_search_radius` 内的鼠洞标记（`hide_spots` + `metadata/kind == mouse_hole`）。
## 没标记就返回 null → 退回普通搜索（T024 E7）。
func _find_hole_near(point: Vector3) -> Node3D:
	if get_tree() == null:
		return null
	var best: Node3D = null
	var best_distance := INF
	for n in get_tree().get_nodes_in_group(HIDE_GROUP):
		var spot := n as Node3D
		if spot == null or not is_instance_valid(spot):
			continue
		if not spot.has_meta("kind") or String(spot.get_meta("kind")) != HOLE_KIND:
			continue
		var d := point.distance_to(hide_spot_point(spot))
		if d > hole_search_radius or d >= best_distance:
			continue
		best = spot
		best_distance = d
	return best


# ---------------------------------------------------------------------------
# 逃脱账本（一场 CHASE 只结算一次；只有猎物存活才算逃脱）
# ---------------------------------------------------------------------------

func _begin_encounter() -> void:
	_encounter_settled = false
	_encounter_seq += 1
	_encounter_id = "enc-%d" % _encounter_seq
	_chase_count += 1
	chase_started.emit(_encounter_id)


## 幂等：同一场追逐重复调用不会重复计数（`encounter_id` 结算后即清空）
func _settle_encounter() -> void:
	if _encounter_id.is_empty() or _encounter_settled:
		return
	_encounter_settled = true
	var alive := _prey_alive()
	if alive:
		_escape_reports += 1
	var id := _encounter_id
	_encounter_id = ""
	chase_ended.emit(id, alive)


## 猎物还活着吗（= 世界里还有**异种且存活**的身体）。与 `Perception` 的威胁口径一致，不写物种名。
func _prey_alive() -> bool:
	if get_tree() == null:
		return false
	var mine := _species_id()
	for n in get_tree().get_nodes_in_group(Perception.GROUP_ANIMAL_BODIES):
		var other := n as AnimalBody
		if other == null or not is_instance_valid(other) or other.species_config == null:
			continue
		if StringName(other.species_config.species_id) == mine:
			continue
		if other.survival == null or other.survival.state.health > 0.0:
			return true
	return false


# ---------------------------------------------------------------------------
# 巡游
# ---------------------------------------------------------------------------

func _step_patrol(world_time: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not patrol_enabled:
		body.move_intent = Vector2.ZERO
		_clear_destination()
		if _state != State.EXPLORE:
			change_state(State.EXPLORE, &"patrol_off")
		else:
			set_reason(&"patrol_off")
		return
	if world_time < _patrol_pause_until:
		body.move_intent = Vector2.ZERO
		set_reason(&"patrol_pause")
		return
	if not _has_destination:
		_pick_patrol_target(world_time)
		if not _has_destination:
			body.move_intent = Vector2.ZERO
			return
	if body.global_position.distance_to(_destination) <= patrol_arrive_radius():
		_patrol_reached += 1
		_patrol_pause_until = world_time + patrol_pause
		_patrol_index += 1
		_patrol_target_id = ""      # 到点后**不再声称**还在去这个点（"可查看"要诚实）
		_clear_destination()
		body.move_intent = Vector2.ZERO
		change_state(State.EXPLORE, &"patrol_reached")
		return
	if _state != State.EXPLORE:
		change_state(State.EXPLORE, &"patrol_moving")
	else:
		set_reason(&"patrol_moving")
	_advance_along_path()
	_track_progress(world_time)


## 到达判定（比基类 `reach_tolerance` 略保守）
func patrol_arrive_radius() -> float:
	return maxf(0.15, reach_tolerance)


## 选下一个巡游点：① 组 `patrol_points`（按名字排序、循环）② 组为空 → 环上第一个**可达**点
## 都不可达 → 走基类失败口径（记录 + 可能进 `WAIT`），**不永久阻塞、不每帧重选**
func _pick_patrol_target(world_time: float) -> void:
	if world_time < _patrol_retry_at:
		return
	_refresh_patrol_ids()
	if not _patrol_ids.is_empty():
		var count := _patrol_ids.size()
		for i in count:
			var idx := (_patrol_index + i) % count
			var node := _patrol_node(_patrol_ids[idx])
			if node == null:
				continue
			var point := _patrol_point(node)
			if not reachable(point):
				continue
			_patrol_index = idx
			_patrol_target_id = _patrol_ids[idx]
			if _set_destination(point):
				return
		_register_path_failure(world_time)
		_patrol_retry_at = world_time + patrol_retry_wait
		return
	for i in RING_CANDIDATES:
		var angle := TAU * float(i) / float(RING_CANDIDATES)
		var point := body.global_position + Vector3(cos(angle), 0.0, sin(angle)) * patrol_radius
		point = _ground_point_under(point)
		if point.distance_to(body.global_position) <= patrol_min_move:
			continue
		if not reachable(point):
			continue
		_patrol_target_id = "ring_%d" % i
		if _set_destination(point):
			return
	_register_path_failure(world_time)
	_patrol_retry_at = world_time + patrol_retry_wait


func _refresh_patrol_ids() -> void:
	_patrol_ids.clear()
	if get_tree() == null:
		return
	var ids: Array[String] = []
	for n in get_tree().get_nodes_in_group(PATROL_GROUP):
		if n == null or not is_instance_valid(n):
			continue
		ids.append(_patrol_id_of(n))
	ids.sort()      # 确定性：不依赖场景树顺序
	_patrol_ids = ids


func _patrol_id_of(node: Node) -> String:
	if node.has_meta("patrol_id"):
		return str(node.get_meta("patrol_id"))
	return String(node.name)


func _patrol_node(id: String) -> Node3D:
	if get_tree() == null:
		return null
	for n in get_tree().get_nodes_in_group(PATROL_GROUP):
		if n == null or not is_instance_valid(n):
			continue
		if _patrol_id_of(n) == id:
			return n as Node3D
	return null


func _patrol_point(node: Node3D) -> Vector3:
	return _ground_point_under(node.global_position)


# ---------------------------------------------------------------------------
# 查询（"状态和原因可查看"）
# ---------------------------------------------------------------------------

func _perception() -> Perception:
	if body == null or not is_instance_valid(body):
		return null
	return body.perception


## 记下"现在看见猎物在哪"（判跳变的基准；只在看得见时更新）
func _seed_prey_seen_pos() -> void:
	var p := _perception()
	if p == null or not p.is_threat_visible():
		return
	_prey_seen_pos = p.threat_position()
	_has_prey_seen_pos = true


func horizontal_distance_to(point: Vector3) -> float:
	if body == null or not is_instance_valid(body):
		return INF
	var d := point - body.global_position
	d.y = 0.0
	return d.length()


func patrol_ids() -> Array[String]:
	_refresh_patrol_ids()
	return _patrol_ids.duplicate()


func patrol_index() -> int:
	return _patrol_index


func patrol_target_id() -> String:
	return _patrol_target_id


func patrol_reached_count() -> int:
	return _patrol_reached


func detect_count() -> int:
	return _detect_count


func approach_count() -> int:
	return _approach_count


func lost_sight_count() -> int:
	return _lost_sight_count


## 当前与猎物的**水平**距离（没有视觉目标时 = `INF`）
func approach_distance() -> float:
	return _approach_dist


## 当前导航目的地（无目的地时返回 `Vector3.ZERO`）——诊断用
func destination() -> Vector3:
	return _destination if _has_destination else Vector3.ZERO


func is_chasing() -> bool:
	return _state == State.CHASE


func is_searching() -> bool:
	return _state == State.SEARCH


## 本次搜索已用时（不在搜索 = 0）
func search_elapsed(world_time: float = NAN) -> float:
	if not is_searching():
		return 0.0
	var now := world_time if not is_nan(world_time) else current_world_time()
	return maxf(0.0, now - _search_started_at)


## 搜索目标 = **失视时刻的快照**（不随后续实时位置变化）
func search_target() -> Vector3:
	return _search_target


func search_count() -> int:
	return _search_count


## 超时 / 洞口超时放弃的次数（"不永久卡"的证据）
func give_up_count() -> int:
	return _give_up_count


## 洞口等待已用时（不在等待 = 0）
func hole_wait_elapsed(world_time: float = NAN) -> float:
	if not is_searching() or _hole_wait_started_at <= 0.0:
		return 0.0
	var now := world_time if not is_nan(world_time) else current_world_time()
	return maxf(0.0, now - _hole_wait_started_at)


## 正在等的洞口标记 id（没有 = 空串）
func hole_target_id() -> String:
	return _hole_id


func chase_count() -> int:
	return _chase_count


## 结算过的"逃脱"次数（**只算猎物存活**）
func escape_report_count() -> int:
	return _escape_reports


## 当前这场追击的 id（没有进行中的追击 = 空串）
func encounter_id() -> String:
	return _encounter_id



## 发起过的攻击次数（没有攻击组件 = 0）
func attack_count() -> int:
	var comp := _attack_comp()
	return comp.attack_count if comp != null else 0


## 攻击组件的状态名（`idle` / `telegraphing` / `recovering`；没有组件 = `none`）
func attack_state() -> String:
	var comp := _attack_comp()
	return comp.state_name() if comp != null else "none"


## 身体上的攻击组件（没有 = null；鼠不会走到这里）
func _attack_comp() -> AttackSettlement:
	if body == null or not is_instance_valid(body):
		return null
	return body.attack

func ai_report() -> Dictionary:
	var d := super()
	var comp := _attack_comp()
	d["ai_kind"] = "cat"
	d["patrol_enabled"] = patrol_enabled
	d["patrol_index"] = _patrol_index
	d["patrol_target"] = _patrol_target_id
	d["patrol_reached"] = _patrol_reached
	d["detect_count"] = _detect_count
	d["approach_count"] = _approach_count
	d["lost_sight"] = _lost_sight_count
	d["approach_distance"] = _approach_dist
	d["attack_range"] = attack_range
	d["npc_alert_time"] = alert_max_time
	# --- T024 ---
	d["chasing"] = is_chasing()
	d["searching"] = is_searching()
	d["search_elapsed"] = search_elapsed()
	d["search_target"] = _search_target
	d["search_count"] = _search_count
	d["give_up_count"] = _give_up_count
	d["hole_wait_elapsed"] = hole_wait_elapsed()
	d["hole_target"] = _hole_id
	d["chase_count"] = _chase_count
	d["escape_reports"] = _escape_reports
	d["encounter_id"] = _encounter_id
	# --- T025 攻击 ---
	d["attack_enabled"] = attack_enabled
	d["attack_count"] = attack_count()
	d["attack_hits"] = (comp.hit_count if comp != null else 0)
	d["attack_misses"] = (comp.miss_count if comp != null else 0)
	d["attack_state"] = attack_state()
	d["attack_target"] = (comp.target_id() if comp != null else "")
	d["attack_miss_reason"] = (comp.last_miss_reason() if comp != null else &"")
	d["attack_blocked"] = (String(body.last_attack_blocked_reason) if body != null and is_instance_valid(body) else "")
	d["attack_fail_streak"] = _attack_fail_streak
	d["search_timeout"] = search_timeout
	d["hole_wait_max"] = hole_wait_max
	return d
