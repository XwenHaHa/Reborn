class_name LifeCycle
extends Node
## 生命周期状态机（T030）：存活 → 结算 → 选物种 → 出生 → 存活。
##
## 依据：`Docs/TechnicalDesign.md` §7；策划 v1.1 §9.3（死亡只结算一次）、§9.5（无玩家尸体）、
## §10（结算/选物种期间模拟与时间停止）；决策见 `Docs/Tasks/T030.md` §3。
##
## 边界（决策 D1/D2）：
## - 本节点**不创建角色**：入口收到 `spawn_requested` 后自己实例化身体，再回呼 `mark_spawned()`。
## - 档案与事件只存 `GameState`（唯一权威），本节点只编排调用。
## - 非法迁移一律拒绝：不改状态、不写档案、不留 `LifeId`；记 `push_warning()` + `transition_rejected` + 事件。

signal state_changed(previous: int, current: int)
signal life_started(life_id: String, species_id: StringName)
signal life_settled(record: Dictionary)
signal spawn_requested(species_id: StringName)
signal transition_rejected(from_state: int, to_state: int, reason: StringName)

enum State { ALIVE = 0, SETTLING = 1, SELECTING = 2, SPAWNING = 3 }

const REJECT_WRONG_STATE := &"wrong_state"
const REJECT_UNKNOWN_SPECIES := &"unknown_species"
const REJECT_LOCKED_SPECIES := &"locked_species"
const REJECT_ALREADY_SETTLED := &"already_settled"
const REJECT_NO_GAME_STATE := &"no_game_state"

## 当前状态。初值 `SETTLING`：开局先"结算"一个尚不存在的生命（空操作）。
var state: State = State.SETTLING
## 当前玩家身体（`SETTLING`/`SELECTING` 期间为 null）。
var body: AnimalBody = null
## 当前这一世的 `LifeId`；未出生时为空串。
var life_id: String = ""
## 当前这一世的物种；未出生时为空 `StringName`。
var species_id: StringName = &""
## 最近一次的结束原因。
var end_reason: StringName = &""
## 入口可告知"引擎里到底存在哪些物种配置"；为空时不校验物种存在性。
var known_species: Array[StringName] = []
## 被拒绝的迁移记录：`{from, to, reason, world_time}`。
var rejections: Array = []
var settle_count: int = 0
var spawn_count: int = 0


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func current_state_name() -> String:
	match state:
		State.ALIVE:
			return "alive"
		State.SETTLING:
			return "settling"
		State.SELECTING:
			return "selecting"
		State.SPAWNING:
			return "spawning"
	return "unknown"


func is_alive() -> bool:
	return state == State.ALIVE


func state_name_of(s: int) -> String:
	match s:
		State.ALIVE:
			return "alive"
		State.SETTLING:
			return "settling"
		State.SELECTING:
			return "selecting"
		State.SPAWNING:
			return "spawning"
	return "unknown"


func last_rejection() -> Dictionary:
	if rejections.is_empty():
		return {}
	return (rejections[rejections.size() - 1] as Dictionary).duplicate(true)


func rejection_count() -> int:
	return rejections.size()


# ---------------------------------------------------------------------------
# 迁移
# ---------------------------------------------------------------------------

## `SETTLING → SELECTING`。结算/选物种期间时间冻结（决策 D7）。
func request_select() -> bool:
	if state != State.SETTLING:
		return _reject(state, State.SELECTING, REJECT_WRONG_STATE)
	_freeze_time()
	_set_state(State.SELECTING)
	return true


## `SELECTING → SPAWNING`。校验物种存在性与解锁状态（决策 D4），再请求入口出生。
func begin_spawn(target_species: StringName) -> bool:
	if state != State.SELECTING:
		return _reject(state, State.SPAWNING, REJECT_WRONG_STATE)
	if not _species_known(target_species):
		return _reject(state, State.SPAWNING, REJECT_UNKNOWN_SPECIES)
	if not _species_allowed(target_species):
		return _reject(state, State.SPAWNING, REJECT_LOCKED_SPECIES)
	var gs := _game_state()
	if gs == null:
		return _reject(state, State.SPAWNING, REJECT_NO_GAME_STATE)
	species_id = target_species
	_set_state(State.SPAWNING)
	spawn_requested.emit(species_id)
	return true


## `SPAWNING → ALIVE`。入口创建好身体后回呼；`LifeId` 在这里才被占用。
func mark_spawned(new_body: AnimalBody, spawn_position: Vector3 = Vector3.ZERO) -> String:
	if state != State.SPAWNING:
		_reject(state, State.ALIVE, REJECT_WRONG_STATE)
		return ""
	var gs := _game_state()
	if gs == null:
		_reject(state, State.ALIVE, REJECT_NO_GAME_STATE)
		return ""
	bind_body(new_body)
	gs.call("begin_life", species_id, spawn_position)
	life_id = String(gs.call("current_life_id"))
	end_reason = &""
	spawn_count += 1
	_restore_time()
	_set_state(State.ALIVE)
	life_started.emit(life_id, species_id)
	return life_id


## `ALIVE → SETTLING`。**只结算一次**：其余状态下重复调用一律被拒（策划 §9.3）。
## `detail` 可带：`damage_reason`、`snapshot`、`world_time`。
func end_life(reason: StringName, detail: Dictionary = {}) -> Dictionary:
	if state != State.ALIVE:
		var why: StringName = REJECT_ALREADY_SETTLED if state == State.SETTLING else REJECT_WRONG_STATE
		_reject(state, State.SETTLING, why)
		return {}
	var gs := _game_state()
	var payload := detail.duplicate(true)
	if not payload.has("snapshot"):
		payload["snapshot"] = survival_snapshot()
	# 先冻结再结算：死亡当帧之后不再接受输入，也不推进时间。
	_freeze_body()
	_freeze_time()
	var rec: Dictionary = {}
	if gs != null:
		rec = gs.call("end_life", reason, payload)
	end_reason = reason
	settle_count += 1
	_set_state(State.SETTLING)
	_release_body()
	life_settled.emit(rec)
	return rec


## 迟到绑定（入口在 `mark_spawned` 之外建立身体时使用）。
func bind_body(new_body: AnimalBody) -> void:
	body = new_body


## 把玩法层事件转写进 `GameState` 事件记录（无进行中的一世时忽略）。
func notify_event(kind: StringName, data: Dictionary = {}) -> bool:
	var gs := _game_state()
	if gs == null or life_id == "":
		return false
	gs.call("record_event", life_id, kind, data)
	return true


func current_survival() -> Dictionary:
	return survival_snapshot()


## 存活快照（策划 §9.5 档案字段）。身体缺失时返回空字典。
func survival_snapshot() -> Dictionary:
	if body == null or not is_instance_valid(body):
		return {}
	if body.survival == null or body.survival.state == null:
		return {}
	var st: SurvivalState = body.survival.state
	return st.to_dictionary()


func world_time() -> float:
	var wd := _world_director()
	if wd == null:
		return 0.0
	return float(wd.get("world_time"))


func time_is_advancing() -> bool:
	var wd := _world_director()
	if wd == null:
		return true
	return bool(wd.get("time_advancing"))


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _set_state(next: State) -> void:
	var prev := state
	if prev == next:
		return
	state = next
	state_changed.emit(int(prev), int(next))


func _reject(from_state: int, to_state: int, reason: StringName) -> bool:
	var entry := {
		"from": from_state,
		"to": to_state,
		"reason": String(reason),
		"world_time": world_time(),
	}
	rejections.append(entry)
	var gs := _game_state()
	if gs != null:
		gs.call("record_event", life_id, &"transition_reject", {
			"from": state_name_of(from_state),
			"to": state_name_of(to_state),
			"reason": String(reason),
		})
	push_warning("LifeCycle: 拒绝迁移 %s → %s（%s）" % [
		state_name_of(from_state), state_name_of(to_state), String(reason)
	])
	transition_rejected.emit(from_state, to_state, reason)
	return false


func _species_known(id: StringName) -> bool:
	if known_species.is_empty():
		return String(id) != ""
	return known_species.has(StringName(id))


## 正式模式只允许已解锁物种；`test_mode` 放行（策划 §9.2，决策 D4）。
func _species_allowed(id: StringName) -> bool:
	var gs := _game_state()
	if gs == null:
		return false
	if bool(gs.get("test_mode")):
		return true
	return bool(gs.call("is_species_unlocked", id))


## 冻结玩家输入（决策 D5）：置非玩家控制、清空所有意向、取消进行中的交互。
func _freeze_body() -> void:
	var b := body
	if b == null or not is_instance_valid(b):
		return
	b.player_controlled = false
	b.move_intent = Vector2.ZERO
	b.want_sprint = false
	b.want_crouch = false
	b.want_jump = false
	b.want_interact = false
	b.want_pounce = false
	if b.interaction != null and is_instance_valid(b.interaction):
		if b.interaction.is_interacting():
			b.interaction.release_interact(&"life_ended")


## 不留下玩家尸体（策划 §9.5）：先改名再排队释放，避免同帧同名节点被引擎改名（T022 踩坑）。
func _release_body() -> void:
	var b := body
	body = null
	if b == null or not is_instance_valid(b):
		return
	b.player_controlled = false
	b.name = "%s_retired" % String(b.name)
	b.queue_free()


func _freeze_time() -> void:
	var wd := _world_director()
	if wd != null:
		wd.set("time_advancing", false)


func _restore_time() -> void:
	var wd := _world_director()
	if wd != null:
		wd.set("time_advancing", true)


func _game_state() -> Node:
	var r := _tree_root()
	return r.get_node_or_null("GameState") if r != null else null


func _world_director() -> Node:
	var r := _tree_root()
	return r.get_node_or_null("WorldDirector") if r != null else null


## 从 `SceneTree.root` 相对查找（树外调用绝对路径会报错）。
func _tree_root() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root if ml is SceneTree else null
