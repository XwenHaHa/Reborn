extends Node
## 全局长期状态（T030）：解锁物种、生命档案、跨世事件记录的唯一权威。
##
## 依据：`Docs/TechnicalDesign.md` §1（`autoload/game_state.gd` = T030/T036 的长期数据）
## 与 §7（生命周期与事务）；策划 v1.1 §9.2–9.5（解锁、死亡只结算一次、档案字段、无玩家尸体）。
##
## 边界：
## - 本脚本**只做记录与查询**，不创建/销毁角色。角色出生由入口在 `LifeCycle.spawn_requested`
##   之后完成（决策 D1）。
## - 不写文件、不读文件：持久化属 T037。
## - 生命周期状态机在 `scripts/core/life_cycle.gd`；档案只存这里（决策 D2）。

signal life_started(record: Dictionary)
signal life_ended(record: Dictionary)
signal event_recorded(entry: Dictionary)
signal species_unlocked(species_id: StringName)

## 事件条数上限（内存保护）。超出时丢最旧的条目。
const MAX_EVENTS := 1024
const LIFE_ID_FORMAT := "L%04d"

const EVENT_LIFE_START := &"life_start"
const EVENT_LIFE_END := &"life_end"
const EVENT_CAPTURE := &"capture"
const EVENT_ESCAPE := &"escape"
const EVENT_FOOD := &"food"
const EVENT_WATER := &"water"
const EVENT_DISCOVERY := &"discovery"
const EVENT_UNLOCK := &"species_unlock"
const EVENT_REJECT := &"transition_reject"

## 开发测试模式（策划 §9.2）：允许选择未解锁物种。正式模式只允许已解锁物种。
var test_mode: bool = false
## 已解锁物种集合：键为 `StringName(species_id)`，值为 `true`。
var unlocked_species: Dictionary = {}
## 已完成的生命档案（按结束顺序追加，不清空）。
var life_records: Array = []
## 进行中的生命档案；空字典表示"当前没有活着的生命"。
var current_life: Dictionary = {}
## 跨世事件（长期记录）：`{seq, life_id, kind, world_time, data}`。
var events: Array = []

var _life_counter: int = 0
var _event_seq: int = 0


# ---------------------------------------------------------------------------
# 新游戏 / 解锁
# ---------------------------------------------------------------------------

## 显式开新游戏：清空长期数据、`LifeId` 归零、同步重置世界（捕获账本、时间）。
## **不是**轮回：轮回只结束一世，不清长期数据（决策 G）。
func reset_for_new_game() -> void:
	life_records = []
	current_life = {}
	events = []
	_life_counter = 0
	_event_seq = 0
	unlocked_species = {}
	test_mode = false
	var wd := _world_director()
	if wd != null and wd.has_method("reset_for_new_game"):
		wd.call("reset_for_new_game")


## 写入默认解锁集（覆盖式）。正式：只有鼠；测试：全解锁由调用方决定。
func set_default_unlock(species_ids: Array) -> void:
	unlocked_species = {}
	for id in species_ids:
		unlocked_species[StringName(id)] = true


## 解锁一个物种。返回是否**新**解锁（幂等：重复调用返回 false）。
func unlock_species(species_id: StringName) -> bool:
	var id := StringName(species_id)
	if String(id) == "" or unlocked_species.has(id):
		return false
	unlocked_species[id] = true
	species_unlocked.emit(id)
	if not current_life.is_empty():
		record_event(String(current_life.get("life_id", "")), EVENT_UNLOCK, {"species": String(id)})
	return true


func is_species_unlocked(species_id: StringName) -> bool:
	return unlocked_species.has(StringName(species_id))


func unlocked_list() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in unlocked_species.keys():
		out.append(StringName(k))
	out.sort()
	return out


# ---------------------------------------------------------------------------
# LifeId 与档案
# ---------------------------------------------------------------------------

## 下一个 `LifeId`（不占用计数器；真正占用发生在 `begin_life()`）。
func peek_life_id() -> String:
	return LIFE_ID_FORMAT % (_life_counter + 1)


## 开始一世：分配 `LifeId`、写入进行中档案。`world_time < 0` 时取 `WorldDirector.world_time`。
func begin_life(species_id: StringName, spawn_position: Vector3 = Vector3.ZERO,
		world_time: float = -1.0) -> Dictionary:
	_life_counter += 1
	var life_id := LIFE_ID_FORMAT % _life_counter
	var now := _now(world_time)
	current_life = {
		"life_id": life_id,
		"species_id": String(species_id),
		"start_world_time": now,
		"end_world_time": -1.0,
		"duration": -1.0,
		"end_reason": "",
		"damage_reason": "",
		"start_position": spawn_position,
		"captures": 0,
		"escapes": 0,
		"food_gained": 0.0,
		"water_gained": 0.0,
		"discoveries": [],
		"event_first": _event_seq + 1,
		"event_last": _event_seq,
		"snapshot": {},
	}
	record_event(life_id, EVENT_LIFE_START, {"species": String(species_id)}, now)
	var out: Dictionary = current_life.duplicate(true)
	life_started.emit(out)
	return out


## 结束当前一世并把档案归档。**只结算一次**：没有进行中的生命时返回空字典、不写任何东西。
## `detail` 可带：`world_time`、`damage_reason`、`snapshot`。
func end_life(reason: StringName, detail: Dictionary = {}) -> Dictionary:
	if current_life.is_empty():
		return {}
	var life_id := String(current_life.get("life_id", ""))
	var now := _now(float(detail.get("world_time", -1.0)))
	var start := float(current_life.get("start_world_time", now))
	var rec := current_life
	rec["end_world_time"] = now
	rec["duration"] = maxf(0.0, now - start)
	rec["end_reason"] = String(reason)
	rec["damage_reason"] = String(detail.get("damage_reason", ""))
	rec["snapshot"] = (detail.get("snapshot", {}) as Dictionary).duplicate(true)
	current_life = {}
	record_event(life_id, EVENT_LIFE_END, {"reason": String(reason)}, now)
	rec["event_last"] = _event_seq
	life_records.append(rec)
	var out: Dictionary = rec.duplicate(true)
	life_ended.emit(out.duplicate(true))
	return out


## 累加进行中档案的计数字段（捕猎/逃脱/食物/水）。没有进行中的生命时忽略。
func add_to_life(field: String, amount: float) -> bool:
	if current_life.is_empty():
		return false
	if not current_life.has(field):
		return false
	var cur: Variant = current_life[field]
	if cur is int:
		current_life[field] = int(cur) + int(round(amount))
	else:
		current_life[field] = float(cur) + amount
	return true


## 记录一次发现（地点/重要事件的去重名）。返回是否新记录。
func record_discovery(label: StringName) -> bool:
	if current_life.is_empty() or String(label) == "":
		return false
	var list := current_life.get("discoveries", []) as Array
	if list.has(String(label)):
		return false
	list.append(String(label))
	current_life["discoveries"] = list
	record_event(String(current_life.get("life_id", "")), EVENT_DISCOVERY, {"label": String(label)})
	return true


func archive_count() -> int:
	return life_records.size()


func last_record() -> Dictionary:
	if life_records.is_empty():
		return {}
	return (life_records[life_records.size() - 1] as Dictionary).duplicate(true)


func has_life() -> bool:
	return not current_life.is_empty()


func current_life_id() -> String:
	return String(current_life.get("life_id", ""))


# ---------------------------------------------------------------------------
# 事件
# ---------------------------------------------------------------------------

## 追加一条事件。`seq` 全局单调递增；超过 `MAX_EVENTS` 丢最旧的。
func record_event(life_id: String, kind: StringName, data: Dictionary = {},
		world_time: float = -1.0) -> Dictionary:
	_event_seq += 1
	var entry := {
		"seq": _event_seq,
		"life_id": life_id,
		"kind": String(kind),
		"world_time": _now(world_time),
		"data": data.duplicate(true),
	}
	events.append(entry)
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)
	event_recorded.emit(entry.duplicate(true))
	return entry


func event_count() -> int:
	return events.size()


func last_event_seq() -> int:
	return _event_seq


func events_for(life_id: String) -> Array:
	var out: Array = []
	for e in events:
		if String((e as Dictionary).get("life_id", "")) == life_id:
			out.append((e as Dictionary).duplicate(true))
	return out


func events_of_kind(kind: StringName) -> Array:
	var out: Array = []
	for e in events:
		if String((e as Dictionary).get("kind", "")) == String(kind):
			out.append((e as Dictionary).duplicate(true))
	return out


## 人可读的一行档案摘要（HUD / 日志 / 结算提示共用）。
func archive_line(rec: Dictionary) -> String:
	if rec.is_empty():
		return ""
	return "%s %s 存活 %.1f s｜捕猎 %d｜逃脱 %d｜食物 %.1f｜水 %.1f｜结束：%s" % [
		String(rec.get("life_id", "?")), String(rec.get("species_id", "?")),
		float(rec.get("duration", -1.0)), int(rec.get("captures", 0)),
		int(rec.get("escapes", 0)), float(rec.get("food_gained", 0.0)),
		float(rec.get("water_gained", 0.0)), String(rec.get("end_reason", "")),
	]


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _now(world_time: float) -> float:
	if world_time >= 0.0:
		return world_time
	var wd := _world_director()
	if wd == null:
		return 0.0
	return float(wd.get("world_time"))


func _world_director() -> Node:
	var r := _tree_root()
	return r.get_node_or_null("WorldDirector") if r != null else null
func _tree_root() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root if ml is SceneTree else null
