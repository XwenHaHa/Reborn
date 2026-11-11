extends Node
## T058：**安全休息与快进**（autoload `RestDirector`）
##
## 真源 `Docs/Parameters.md:81`：
##   「休息：推进 60 sim seconds，Health 恢复 10；Hunger/Thirst 照常扣，
##     预计休息后任一 ≤0 或正在警戒/追逐则拒绝。资源/种群结算所有经过的恢复周期并夹紧容量，
##     NextRefillAt 更新到未来，不能只恢复一次造成时间错误。」
##
## 设计要点（`Docs/Tasks/T058.md` §2）：
## - **D1 原子事务**：60 sim seconds 是一次**权威时间跳变**（与读档 `set_world_time` 同一口径）。
##   资源与种群本来就按"多周期一次结算 + 夹紧容量 + next 前移"工作，因此不存在
##   "快进后只恢复一次"的时间错误。
## - **D2 预测不试算**：拒绝判定与提示都用 `rate × 60` 直接算，**不推进再回滚**
##   （回滚会污染 `SurvivalController.last_world_time` 与资源账本）。
## - **D3 危险判定复用 AI 状态**：只看 NPC 的 `ai.state_id()` 是否属于
##   `{alert, approach, chase, search, attack}` 且距离 ≤ `DANGER_RADIUS`。
## - **D6 顺序**：推进时间 → 生存结算（含危机伤害）→ `+10` 生命 → 资源点/种群结算到新时间。
##
## 本类**不自己存档、不自己弹 UI**：由 `MainEntry` 订阅信号后走 `save_now(&"rest")` 与 HUD Toast。

## 拒绝时发出（`reason` 见 `evaluate()`；`detail` 是完整判定结果，HUD 用它出提示文案）
signal rest_refused(reason: StringName, detail: Dictionary)
## 成功结算后发出（`result` 含前后数值，断言与存档日志都用它）
signal rest_completed(result: Dictionary)

## 一次休息推进的 sim seconds（`Parameters.md:81`）
const REST_SECONDS := 60.0
## 一次休息恢复的生命（`Parameters.md:81`）
const REST_HEALTH_GAIN := 10.0
## 危险判定半径（米）。**实现默认值**：猫 AI 的 `approach` 停在 0.65 m、
## 视距 9 m —— 8 m 覆盖"已经进入接近/追击"的整段，又不至于把远处巡游也算成危险。
const DANGER_RADIUS := 8.0
## 视作"警戒/追逐"的 AI 状态（`scripts/ai/animal_ai.gd` 的 `State` 名字）
const DANGER_STATES: Array[StringName] = [&"alert", &"approach", &"chase", &"search", &"attack"]

## 最近一次 `evaluate()` / `rest()` 的结果（诊断、HUD、断言）
var last_result: Dictionary = {}
## 成功休息的次数
var rest_count: int = 0


# ---------------------------------------------------------------------------
# 判定
# ---------------------------------------------------------------------------

## 能否休息。**纯观察**：不改世界时间、不改任何数值。
##
## 返回：`{ok, reason, seconds, gain, predicted:{hunger,thirst,health}, danger:{...}, world_time}`
## `reason` ∈ `no_player / no_survival / not_advancing / dead / busy / in_danger / insufficient_resources / ok`
func evaluate(player: Node) -> Dictionary:
	var out := {
		"ok": false,
		"reason": &"no_player",
		"seconds": REST_SECONDS,
		"gain": REST_HEALTH_GAIN,
		"predicted": {},
		"danger": {},
		"world_time": 0.0,
	}
	if player == null or not is_instance_valid(player):
		last_result = out
		return out
	var survival = player.get("survival")
	var cfg = player.get("species_config")
	if survival == null or cfg == null:
		out["reason"] = &"no_survival"
		last_result = out
		return out

	var wd := get_node_or_null("/root/WorldDirector")
	out["world_time"] = float(wd.get("world_time")) if wd != null else 0.0

	# 时间门闩（暂停 = `time_advancing=false` 或树暂停）下的"快进"没有意义：直接拒绝，
	# 而不是"跳过 60 s 却不扣消耗"——那会让玩家用暂停白嫖。
	if not _time_running(wd):
		out["reason"] = &"not_advancing"
		last_result = out
		return out

	out["predicted"] = predict(player)
	if bool(survival.call("is_dead")):
		out["reason"] = &"dead"
		last_result = out
		return out
	# 扑击 / 攻击 / 交互 / 恢复期都不许休息（`ACT.IDLE` 之外一律 busy）
	if player.has_method("action_state") and int(player.call("action_state")) != int(AnimalBody.ACT.IDLE):
		out["reason"] = &"busy"
		last_result = out
		return out

	var danger := _find_danger(player)
	out["danger"] = danger
	if bool(danger.get("found", false)):
		out["reason"] = &"in_danger"
		last_result = out
		return out

	# 资源不足提前提示：预计休息后饥/渴任一 ≤0 → 拒绝（不让玩家在不可操作的快进里无预警死亡）
	var pred: Dictionary = out["predicted"]
	if float(pred.get("hunger", 0.0)) <= 0.0 or float(pred.get("thirst", 0.0)) <= 0.0:
		out["reason"] = &"insufficient_resources"
		last_result = out
		return out

	out["ok"] = true
	out["reason"] = &"ok"
	last_result = out
	return out


## 预测休息后的数值（**不推进时间、不改状态**）
func predict(player: Node) -> Dictionary:
	var out := {"hunger": 0.0, "thirst": 0.0, "health": 0.0}
	if player == null or not is_instance_valid(player):
		return out
	var survival = player.get("survival")
	var cfg = player.get("species_config")
	if survival == null or cfg == null:
		return out
	var st = survival.get("state")
	if st == null:
		return out
	out["hunger"] = maxf(0.0, float(st.get("hunger")) - float(cfg.get("hunger_loss_per_sec")) * REST_SECONDS)
	out["thirst"] = maxf(0.0, float(st.get("thirst")) - float(cfg.get("thirst_loss_per_sec")) * REST_SECONDS)
	out["health"] = minf(float(cfg.get("max_health")), float(st.get("health")) + REST_HEALTH_GAIN)
	return out


## 找最近的、处于警戒/追逐状态的 NPC（玩家自己不算）
func _find_danger(player: Node) -> Dictionary:
	var out := {"found": false, "state": &"", "id": "", "distance": -1.0}
	var tree := get_tree()
	if tree == null:
		return out
	var best := INF
	for node in tree.get_nodes_in_group(&"animal_bodies"):
		if node == player or not is_instance_valid(node):
			continue
		var ai = node.get("ai")
		if ai == null or not ai.has_method("state_id"):
			continue
		var st: StringName = ai.call("state_id")
		if not DANGER_STATES.has(st):
			continue
		var body := node as Node3D
		if body == null:
			continue
		var d: float = body.global_position.distance_to((player as Node3D).global_position)
		if d > DANGER_RADIUS:
			continue
		if d < best:
			best = d
			out["found"] = true
			out["state"] = st
			out["id"] = String(body.name)
			out["distance"] = d
	return out


## 时间是否真的在走：树暂停 or 显式门闩任一成立都算"没在走"
func _time_running(wd: Node) -> bool:
	var tree := get_tree()
	if tree != null and tree.paused:
		return false
	if wd != null and wd.has_method("is_time_advancing") and not bool(wd.call("is_time_advancing")):
		return false
	return true


# ---------------------------------------------------------------------------
# 结算
# ---------------------------------------------------------------------------

## 执行一次休息（**原子**）。拒绝时返回 `evaluate()` 的结果且**零副作用**。
func rest(player: Node) -> Dictionary:
	var ev := evaluate(player)
	if not bool(ev.get("ok", false)):
		rest_refused.emit(ev.get("reason", &"denied"), ev)
		last_result = ev
		return ev

	var survival = player.get("survival")
	var cfg = player.get("species_config")
	var st = survival.get("state")
	var wd := get_node_or_null("/root/WorldDirector")

	var before := {
		"world_time": float(wd.get("world_time")) if wd != null else 0.0,
		"hunger": float(st.get("hunger")),
		"thirst": float(st.get("thirst")),
		"health": float(st.get("health")),
	}
	var t1: float = float(before["world_time"]) + REST_SECONDS

	# ① 权威时间跳变（与读档同一口径：只写世界时间，不额外补"快进"代码）
	if wd != null:
		wd.call("set_world_time", t1)
	# ② 生存按时间结算（含危机伤害；`tick_to` 内部按 0.2 s 分块，和正常游玩完全同一条路径）
	survival.call("tick_to", t1)
	# ③ 再回血：先扣后加，`+10` 不会被自伤吃掉，也不会在饥渴归零时掩盖饥饿
	survival.call("restore_health", REST_HEALTH_GAIN)
	# ④ 资源点与种群结算所有经过的周期（各自内部夹紧容量、next 前移，重复调用是 no-op）
	var points_settled := 0
	var tree := get_tree()
	if tree != null:
		for node in tree.get_nodes_in_group(&"resource_points"):
			if is_instance_valid(node) and node.has_method("advance_to"):
				node.call("advance_to", t1)
				points_settled += 1
	if wd != null and wd.has_method("region_population_advance_to"):
		wd.call("region_population_advance_to", t1)

	var result := {
		"ok": true,
		"reason": &"ok",
		"seconds": REST_SECONDS,
		"gain": REST_HEALTH_GAIN,
		"world_time_before": before["world_time"],
		"world_time_after": t1,
		"hunger_before": before["hunger"],
		"hunger_after": float(st.get("hunger")),
		"thirst_before": before["thirst"],
		"thirst_after": float(st.get("thirst")),
		"health_before": before["health"],
		"health_after": float(st.get("health")),
		"resource_points_settled": points_settled,
		"died_during_rest": bool(survival.call("is_dead")),
		"max_health": float(cfg.get("max_health")),
	}
	rest_count += 1
	last_result = result
	rest_completed.emit(result)
	return result
