extends Node
## 世界统一入口（Autoload 单例）
##
## 职责（T002 阶段只实现时间；T014/T034 扩充资源注册与区域账本）：
##   - 维护 sim time（世界时间），驱动资源恢复与昼夜
##   - 暂停 / 结算 / 选择 / 加载时不推进
##
## 单位约定：世界时间用秒（float）。距离一律用米。
## 依据 Docs/TechnicalDesign.md §5。

## 世界时间（sim seconds），新游戏从 0 开始。禁止用墙钟系统时间。
var world_time: float = 0.0

## 单独的时间推进开关。get_tree().paused 之外再给一个显式门闩，
## 用于"结算/选物种/加载"这类必须停表但不一定暂停整棵树的状态。
var time_advancing: bool = true

## 本帧的 sim delta，供各系统读取，避免每处自己算。
var sim_delta: float = 0.0

## 行动噪声总线（T020；`Docs/TechnicalDesign.md` §4 信号表 `action_noise`）：
## 每次**脚步事件**发一次（**不是每帧**），带来源 ID、发生位置、响度与世界时间。
## 感知方（`scripts/systems/perception.gd`）只从这里取"声音**发生**位置 + 时间"，
## **不建立对声源的持续跟踪**（§6：听见声音只得到声音位置）。
signal noise_emitted(source_id: String, position: Vector3, loudness: float, world_time: float)

## 本次运行广播过的噪声事件数（诊断/断言用）
var noise_event_count: int = 0


func _process(delta: float) -> void:
	if not time_advancing:
		sim_delta = 0.0
		return
	sim_delta = delta
	world_time += delta
	region_population_advance_to(world_time)   # T035 种群恢复只吃世界时间


## 供存档/读档设置世界时间，不触发恢复结算。
func set_world_time(t: float) -> void:
	world_time = maxf(0.0, t)


## 供新游戏重置。只有明确的新游戏确认才可调用（TechnicalDesign §7）。
func reset_for_new_game() -> void:
	world_time = 0.0
	time_advancing = true
	# 捕获账本（T021）也必须随新游戏清零，否则新一局会把旧的猎物判成"已记账"
	capture_count = 0
	capture_food_count = 0
	captured_target_ids = {}
	# 区域种群账本（T035）随新游戏彻底归零；下一次 MainEntry 建关卡时重新 init
	region_records = {}
	region_active_bodies = {}
	_region_rects = {}
	_region_initials = {}
	region_population_initialized = false


## 当前世界时间（秒）——**统一时间入口**。
## 所有按时间的系统（生存消耗、资源恢复、昼夜……）都从这里取差推进，**不要各自累加 `delta`**：
## 一个渲染帧可能跑 0/1/2 次物理帧，各自累加会与世界时间漂移。
func get_world_time() -> float:
	return world_time


## 显式门闩的当前状态。注意：**树暂停时 `_process` 不跑，本函数仍可能返回 true** ——
## 要判断"时间是不是真的在走"，看 `world_time` 有没有变（见 `Docs/Tasks/T014.md` 决策 D1）。
func is_time_advancing() -> bool:
	return time_advancing


## 广播一次行动噪声（T020）。`loudness ≤ 0` 直接丢弃；计数只统计真正广播出去的事件。
## 调用方：`AnimalBody._emit_footstep()`（每次脚步事件一次，**不是每帧**）。
func emit_noise(source_id: String, position: Vector3, loudness: float) -> void:
	if loudness <= 0.0:
		return
	noise_event_count += 1
	noise_emitted.emit(source_id, position, loudness, world_time)


## 成功捕获广播（T021；`Docs/TechnicalDesign.md` §7 捕获流程）。每次**真实结算**只发一次。
signal capture_reported(captor_id: String, target_id: String, position: Vector3, world_time: float)

## 本次运行成功结算的捕获次数（诊断/断言用；被拒绝的重复上报不计入）
var capture_count: int = 0

## 本次运行生成的捕获食物对象数（诊断/断言用）
var capture_food_count: int = 0

## 已结算捕获的猎物 ID 账本（`String -> true`），用于幂等去重
var captured_target_ids: Dictionary = {}


## 上报一次捕获（T021）。**幂等**：同一个 `target_id` 只结算一次。
## 返回 true = 本次真的结算了（记账 + 计数 + 发信号）；
## 返回 false = 早就结算过（或 target_id 为空），**不改任何计数、不发信号**（TechnicalDesign §7"检查未记账"）。
func report_capture(captor_id: String, target_id: String, position: Vector3,
		world_time: float = -1.0) -> bool:
	if target_id.is_empty() or captured_target_ids.has(target_id):
		return false
	var t: float = world_time if world_time >= 0.0 else get_world_time()
	captured_target_ids[target_id] = true
	capture_count += 1
	_deduct_region_for_capture(target_id)   # T035：区域账扣一次（幂等门内，重复上报不会再扣）
	capture_reported.emit(captor_id, target_id, position, t)
	return true


## 该目标是否已被结算过捕获（T021）
func is_captured(target_id: String) -> bool:
	return captured_target_ids.has(target_id)


# ---------------------------------------------------------------------------
# 昼夜时钟（T034）
# ---------------------------------------------------------------------------

## 一天多长（世界秒）。真源：`Docs/Parameters.md` 第 83 行「初始昼夜周期 1200s」。
## 昼夜边界对半（白天 600 s + 夜晚 600 s，`NIGHT_START_RATIO`）是 T034 决策——
## 策划只给了周期与「WorldTime=0 为白天起点」，未定义边界；待负责人并入正式起测值。
## 昼夜**光照**属 T057：本类只提供时钟读数，不做任何渲染/灯光变化。
var day_length: float = 1200.0
const NIGHT_START_RATIO := 0.5


## 当天内的世界秒（`fmod` 取余）。负 `world_time` 或非法 `day_length` 一律按 0 处理。
func time_of_day() -> float:
	if day_length <= 0.0 or world_time < 0.0:
		return 0.0
	return fmod(world_time, day_length)


## 第几天，0 起（呈现层 +1 得「第 N 天」）。
func day_index() -> int:
	if day_length <= 0.0 or world_time < 0.0:
		return 0
	return int(floor(world_time / day_length))


## 是否白天：`[0, day_length/2)`。昼夜 API 全部是 `world_time` 的**纯函数**——
## 不存平行状态、不推进时间；门闩（`time_advancing=false`）天然冻结昼夜读数。
func is_daytime() -> bool:
	if day_length <= 0.0:
		return true   # 防呆：非法周期视为恒白天
	return time_of_day() < day_length * NIGHT_START_RATIO


func phase_name() -> StringName:
	return &"day" if is_daytime() else &"night"


# ===========================================================================
# 区域种群账本（T035）。真源 `Docs/Parameters.md` 第 77 行（鼠 4/2/240、猫 1/1/0，
# 数值经 `SpeciesConfig.Population` 组从 `.tres` 读入，代码不写物种名分支）。
# TD §3 `RegionRecord` 契约：`total_count` 是**权威数量**（含未实例化个体）；
# 实例化/销毁表现不改变它。活动登记只是表现层，服务于两件事：
#   ① 不变式「每区每物种 active ≤ total」（正式初始状态）；
#   ② 捕获扣账时反查受害者区域。
# 恢复只吃 `world_time`（T034 D1/D2 时钟契约：单一时间源、门闩冻结、`set_world_time`
# 权威快进后由下一次 advance 结算）。账本为纯数据（无 Node 引用），可整体进存档。
# ===========================================================================

## 账本记录。键 = `"region_id|species_id"`，值 = TD §3 RegionRecord 形状的 Dictionary
var region_records: Dictionary = {}
## 活动个体登记（表现层）。同键 → `Array[Dictionary{instance_id:int, source_id:String}]`
var region_active_bodies: Dictionary = {}
## 区域矩形缓存（`region_id` → `{min_x, max_x, min_z, max_z}`，从关卡标记只读推导）
var _region_rects: Dictionary = {}
## 初始数量缓存（`restore` 的非有限修复回初始用；键同账本）
var _region_initials: Dictionary = {}
## 账本是否已按当前关卡区域初始化（`MainEntry._ready` 建关卡后 init 一次；重生不重置）
var region_population_initialized: bool = false


func _region_key(region_id: StringName, species_id: StringName) -> String:
	return "%s|%s" % [String(region_id), String(species_id)]


## 初始化区域种群账本：**只在明确的新游戏/新一局调用**（正式死亡→重生绝不调，
# T034 D3 时间语义同构）。区域清单来自当前关卡 `level_regions` 组；无该组的夹具关卡
# 账本保持空（`region_population_initialized=false`），全部种群 API 为安全 no-op。
func init_region_population(configs: Array) -> void:
	region_records = {}
	region_active_bodies = {}
	_region_rects = {}
	_region_initials = {}
	region_population_initialized = false
	var regions := get_tree().get_nodes_in_group("level_regions")
	for node in regions:
		var rid := StringName(String(node.get_meta("region_id")))
		if String(rid).is_empty():
			continue
		_region_rects[rid] = _region_rect_of(node)
	for cfg in configs:
		if cfg == null:
			continue
		var sid: StringName = cfg.species_id
		for rid in _region_rects:
			var key := _region_key(rid, sid)
			region_records[key] = {
				"region_id": String(rid),
				"species_id": String(sid),
				"total_count": int(cfg.region_initial),
				"capacity": int(cfg.region_capacity),
				"next_recover_at": 0.0,
				"recover_interval": float(cfg.region_recover_interval),
			}
			region_active_bodies[key] = []
			_region_initials[key] = int(cfg.region_initial)
	region_population_initialized = not _region_rects.is_empty()


## 从区域标记只读推导水平矩形（标记中心 ± 子 `Volume/Shape` BoxShape3D 半尺寸）。
## 生产代码不依赖生成器脚本；换关卡只看 `level_regions` 组的内容。
func _region_rect_of(marker: Node) -> Dictionary:
	var rect := {"min_x": 0.0, "max_x": 0.0, "min_z": 0.0, "max_z": 0.0}
	var m3 := marker as Node3D
	if m3 == null:
		return rect
	var center := m3.global_position
	for child in marker.get_children():
		var area := child as Area3D
		if area == null:
			continue
		for shape_node in area.get_children():
			var cs := shape_node as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				continue
			var box := cs.shape as BoxShape3D
			rect["min_x"] = center.x - box.size.x * 0.5
			rect["max_x"] = center.x + box.size.x * 0.5
			rect["min_z"] = center.z - box.size.z * 0.5
			rect["max_z"] = center.z + box.size.z * 0.5
			return rect
	return rect


## 当前账本里的全部区域 ID（排序输出，便于整体对照）
func region_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for rid in _region_rects:
		out.append(rid)
	out.sort()
	return out


func region_total(region_id: StringName, species_id: StringName) -> int:
	var rec: Dictionary = region_records.get(_region_key(region_id, species_id), {})
	return int(rec.get("total_count", 0))


func region_capacity(region_id: StringName, species_id: StringName) -> int:
	var rec: Dictionary = region_records.get(_region_key(region_id, species_id), {})
	return int(rec.get("capacity", 0))


## 某物种的全区域总数之和（W01「区域总数」口径）
func region_population_totals(species_id: StringName) -> int:
	var sum := 0
	for key in region_records:
		var rec: Dictionary = region_records[key]
		if StringName(String(rec["species_id"])) == species_id:
			sum += int(rec["total_count"])
	return sum


## 活动数 = 登记且实例有效且未死且未被捕获（表现层计数；不改总数）
func region_active_count(region_id: StringName, species_id: StringName) -> int:
	var arr: Array = region_active_bodies.get(_region_key(region_id, species_id), [])
	var n := 0
	for e in arr:
		var b := instance_from_id(int(e["instance_id"]))
		if b == null:
			continue
		var ab := b as AnimalBody
		if ab == null:
			continue
		if bool(ab.get("captured")):
			continue
		if ab.survival != null and ab.survival.is_dead():
			continue
		n += 1
	return n


## 水平 XZ 矩形包含判定（含边界）。账本未初始化或点在区域外 → `&""`。
func region_id_at(position: Vector3) -> StringName:
	if not region_population_initialized:
		return &""
	for rid in _region_rects:
		var rect: Dictionary = _region_rects[rid]
		if position.x >= float(rect["min_x"]) and position.x <= float(rect["max_x"]) \
				and position.z >= float(rect["min_z"]) and position.z <= float(rect["max_z"]):
			return rid
	return &""


## 登记活动个体（表现层；`total_count` 才是权威）。账本未初始化 / 未知区域-物种 /
## 同 source_id 重复登记 → 返回 false，调用方安静跳过。
func register_region_body(region_id: StringName, species_id: StringName, body: Node) -> bool:
	if not region_population_initialized or body == null or not is_instance_valid(body):
		return false
	var key := _region_key(region_id, species_id)
	if not region_records.has(key):
		return false
	if not body.has_method("source_id"):
		return false
	var sid := String(body.call("source_id"))
	if sid.is_empty():
		return false
	for k in region_active_bodies:
		for e in region_active_bodies[k]:
			if String(e["source_id"]) == sid:
				return false   # 已登记过（不重复计）
	(region_active_bodies[key] as Array).append({
		"instance_id": int(body.get_instance_id()),
		"source_id": sid,
	})
	return true


## 注销活动个体（按 source_id 全表找一次；找不到返回 false）
func unregister_region_body(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not body.has_method("source_id"):
		return false
	var sid := String(body.call("source_id"))
	for k in region_active_bodies:
		var arr: Array = region_active_bodies[k]
		for i in range(arr.size()):
			if String(arr[i]["source_id"]) == sid:
				arr.remove_at(i)
				return true
	return false


## 恢复结算（T035 D4）：只吃世界时间，镜像 `ResourcePoint.advance_to` 语义——
## 多周期**一次结算**、**夹紧容量**、满容量**清零 `next_recover_at`**、有空额时排期
## `t + interval`。驱动：`_process`（时间门闩时本函数不会被叫到 → 天然冻结）；
## 测试与读档可直调（`set_world_time` 权威快进后由下一次调用结算经过的周期）。
## `interval <= 0`（猫：原型不自动增长）与满容量记录直接跳过。
func region_population_advance_to(world_time: float) -> void:
	for key in region_records:
		var rec: Dictionary = region_records[key]
		var interval := float(rec["recover_interval"])
		if interval <= 0.0:
			continue
		var total := int(rec["total_count"])
		var capacity := int(rec["capacity"])
		var next := float(rec["next_recover_at"])
		if total >= capacity:
			rec["next_recover_at"] = 0.0
			continue
		if next <= 0.0:
			rec["next_recover_at"] = world_time + interval   # 有空额才起表
			continue
		if next > world_time:
			continue
		var periods := int(floor((world_time - next) / interval)) + 1
		var gained := mini(periods, capacity - total)
		rec["total_count"] = total + gained
		if int(rec["total_count"]) >= capacity:
			rec["next_recover_at"] = 0.0
		else:
			rec["next_recover_at"] = next + interval * float(gained)


## 捕获扣账（T035 D5）：**只在 `report_capture` 幂等门内调用**（首次真实结算才扣；
## 重复上报不会重复扣）。只对活动登记中的个体扣其所属区域；未登记个体
##（测试夹具/临时身体）区域账不动。`total_count` 下限 0。
func _deduct_region_for_capture(target_id: String) -> void:
	for key in region_active_bodies:
		var arr: Array = region_active_bodies[key]
		for i in range(arr.size()):
			if String(arr[i]["source_id"]) == target_id:
				var rec: Dictionary = region_records.get(key)
				if not rec.is_empty():
					rec["total_count"] = maxi(0, int(rec["total_count"]) - 1)
				arr.remove_at(i)
				return


## 快照（进 TD §3 `WorldSnapshot.regions`）。纯数据、无 Node 引用。
func region_population_snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in region_records:
		var rec: Dictionary = region_records[key]
		out.append({
			"region_id": String(rec["region_id"]),
			"species_id": String(rec["species_id"]),
			"total_count": int(rec["total_count"]),
			"capacity": int(rec["capacity"]),
			"next_recover_at": float(rec["next_recover_at"]),
			"recover_interval": float(rec["recover_interval"]),
		})
	return out


## 依据快照重建账本（T035 D7：**读档可据数量重建**——数量是存档状态；
## `capacity/recover_interval` 是配置/关卡数据，**不从快照恢复**，只按当前账本为准）。
## 校验（TD §8 读档校验口径）：未知区域/物种 → 跳过并记入 `skipped`；
## 负数 → 钳 0、超容量 → 钳容量（记入 `repaired`）；非有限数值 → 整条回初始。
## 返回修复报告 `{restored:int, skipped:Array, repaired:Array}`。
func restore_region_population(snapshot: Array) -> Dictionary:
	var report := {"restored": 0, "skipped": [], "repaired": []}
	if not region_population_initialized:
		(report["skipped"] as Array).append("population_not_initialized")
		return report
	for raw in snapshot:
		if not (raw is Dictionary):
			(report["skipped"] as Array).append("entry_not_dictionary")
			continue
		var rid := StringName(String(raw.get("region_id", "")))
		var sid := StringName(String(raw.get("species_id", "")))
		var key := _region_key(rid, sid)
		if not region_records.has(key):
			(report["skipped"] as Array).append("%s|%s" % [String(rid), String(sid)])
			continue
		var rec: Dictionary = region_records[key]
		var capacity := int(rec["capacity"])
		var total_v = raw.get("total_count", rec["total_count"])
		var next_v = raw.get("next_recover_at", rec["next_recover_at"])
		var total := int(_region_initials.get(key, 0))
		var next := 0.0
		var repaired := false
		if ((total_v is int) or (total_v is float)) and ((next_v is int) or (next_v is float)) \
				and is_finite(float(total_v)) and is_finite(float(next_v)):
			total = int(total_v)
			next = maxf(0.0, float(next_v))
		else:
			repaired = true   # 非有限 → 整条回初始（total 已取 initial，next 归 0）
		if total < 0:
			total = 0
			repaired = true
		if total > capacity:
			total = capacity
			repaired = true
		rec["total_count"] = total
		rec["next_recover_at"] = next
		report["restored"] = int(report["restored"]) + 1
		if repaired:
			(report["repaired"] as Array).append("%s|%s" % [String(rid), String(sid)])
	return report
