class_name DiscoveryTracker
extends Node
## 地点发现组件（T031，策划 v1.1 §9.2「作为猫首次发现指定鼠洞入口后，老鼠永久解锁」）。
##
## 职责（只观察，仿 `Perception` 的边界）：
## - 轮询 `player` 与 `discovery_points` 组内标记的**水平距离**；
## - 首次进入发现半径 → 调 `GameState.record_place_discovery()`（长期记录 + 解锁规则都在那边）；
## - 不改移动、不建/删节点、不写第二份档案、**不含**"发现者必须是猫"的特判——
##   正式模式初始只解锁猫（`SpeciesConfig.initially_unlocked`），解锁前鼠无法出生，
##   所以第一个能走到洞口的必然是猫（`Docs/Tasks/T031.md` 决策 D5）。
##
## 标记契约（由 `tool_make_courtyard.gd` 生成）：`Marker3D` ∈ `discovery_points` 组，
## `meta discovery_id`（稳定 ID，**进存档后不得改**，T036 契约）、可选 `meta radius`（米）。

## 首次发现一个地点（已通过 `GameState` 去重）时发出。
signal place_discovered(place_id: String)

## 扫描间隔（秒）。发现不需要亚秒级精度；0.25 s 远小于走路步长，省空转。
const DEFAULT_SCAN_INTERVAL := 0.25
## 发现半径兜底（米）：标记没写 `radius` meta 时用。真源在
## `Docs/Parameters.md`「地点发现与解锁」与关卡标记 meta。
const DEFAULT_RADIUS := 2.0

## 被跟踪的玩家（出生时由入口注入；结算时置空）。不绑死 `AnimalBody`，便于单测。
var player: Node3D = null
## 测试可调的扫描间隔。
var scan_interval: float = DEFAULT_SCAN_INTERVAL

var _elapsed: float = 0.0
var _pending: Array[Node3D] = []


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or _pending.is_empty():
		return
	_elapsed += delta
	if _elapsed < scan_interval:
		return
	_elapsed = 0.0
	_scan()


## 刷新待发现点：收 `discovery_points` 组里带非空 `discovery_id` 的 `Node3D`，
## 已在 `GameState` 长期层的跳过（跨世去重在记录端，这里只是省轮询）。
## 入口在出生后、发现点变动后调用。
func refresh_points() -> void:
	_pending = []
	# 入树完成前（SceneTree._initialize 期间的同步调用）拿不到组；等下一次刷新再收。
	if not is_inside_tree():
		return
	var gs := _game_state()
	var dict: Dictionary = {}
	if gs != null:
		dict = gs.get("discovered_places") as Dictionary
	for n in get_tree().get_nodes_in_group("discovery_points"):
		var point := n as Node3D
		if point == null:
			continue
		var pid := String(point.get_meta("discovery_id", ""))
		if pid == "" or dict.has(pid):
			continue
		_pending.append(point)


func pending_count() -> int:
	return _pending.size()


func _scan() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var pos := player.global_position
	var i := _pending.size() - 1
	while i >= 0:
		var point := _pending[i]
		if not is_instance_valid(point):
			_pending.remove_at(i)
			i -= 1
			continue
		var radius := DEFAULT_RADIUS
		if point.has_meta("radius"):
			radius = maxf(0.01, float(point.get_meta("radius", DEFAULT_RADIUS)))
		var flat := Vector2(pos.x - point.global_position.x, pos.z - point.global_position.z)
		if flat.length() <= radius:
			var pid := String(point.get_meta("discovery_id", ""))
			if bool(gs.call("record_place_discovery", StringName(pid))):
				place_discovered.emit(pid)
			_pending.remove_at(i)
		i -= 1


func _game_state() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("GameState")
	return null
