extends Node3D
class_name EcologySpawner
## T027 测试生态：**按玩家物种**布置 NPC（`Docs/Tasks/T027.md`）。
##
## 职责（只做这一件事）：给定玩家身体与其出生点，在**当前关卡**上铺出"另一种物种"的 NPC，
## 并保证**出生安全**（距离规则 + 可解释的报告）。NPC 的行为完全交给既有 AI（`species_config.ai_script`）：
##   鼠 NPC → T019/T020 觅食/警戒/逃跑/躲藏；猫 NPC → T023/T024/T025 巡游/追击/攻击。
##
## 铁律：
## - **不写物种名**：候选物种来自 `candidates`（`SpeciesConfig` 资源），数量来自 `count_overrides`，
##   捕食者半径由 `SpeciesConfig.can_attack` 分派 —— 差异全在资源与配置里。
## - **玩家不计入 NPC 数量**：`npc_count*()` 只数本组件铺出去的、仍活跃的 NPC。
## - **不改关卡几何**：落点只用现有出生标记 + 环上候选，并按**物种自己的导航层**吸附
##   （用带层的 `map_get_path()`；Godot 4.7.2 的 `map_get_closest_point()` **不带层**，不可用于判层）。
## - 安全点找不到就**跳过并记录**，绝不硬塞到玩家脸上。

## 生态铺好时发一次（报告结构见 `spawn_report()`）。
signal ecology_ready(report: Dictionary)

const BODY_SCENE := preload("res://scenes/characters/animal_body.tscn")
## 铺生态的**最大重试次数**（导航/关卡同步有延迟时逐帧重试，约 4 s）。
const MAX_SETUP_ATTEMPTS := 240

@export var body_scene: PackedScene = BODY_SCENE
## NPC 物种池（默认在 `_ready` 里按 `resources/species/*.tres` 的既有约定填）——**代码里不出现物种名**。
@export var candidates: Array[SpeciesConfig] = []
## 每个候选物种铺几只（`count_overrides` 可按 `species_id` 覆盖）。
@export var count_per_species: int = 2
## `species_id -> count` 覆盖表（键可以是 `String` 或 `StringName`）。
@export var count_overrides: Dictionary = {}
## 一次最多铺几只（含所有物种）。
@export var max_npcs: int = 3
## 非捕食者 NPC 距玩家出生点的最小距离（米）。
@export var min_spawn_distance: float = 8.0
## **捕食者**（`can_attack == true`）距玩家出生点的最小距离（米）。
## 取值按**最快速度 × 出生安全窗口**算：T029 之后捕食者追击会冲刺（`sprint_speed 4.5`），
## 4 s 窗口内能跑 18 m，所以旧值 14（按 walk 1.8 算的）不再够 —— 取 **24 m**（18 + 6 m 余量）。
## 仍受 `max_spawn_distance 45` 约束；相机能看见的"出生安静期"由此保证。
@export var predator_min_distance: float = 24.0
## 最远可接受距离（米）。
@export var max_spawn_distance: float = 45.0
## NPC 之间的最小间距（米）。
@export var min_npc_separation: float = 2.0
## 环上候选的半径（米）；每个标记周围按 12 个角度 × 2 圈取样。
@export var ring_radius: float = 4.0
## 优先使用的出生标记组（缺省回退到 `spawn_points`）。
@export var spawn_point_group: StringName = &"npc_spawn_points"
@export var fallback_spawn_group: StringName = &"spawn_points"
## 吸附到导航层的容差（米）：超过就认为这个点不可用。
@export var snap_tolerance: float = 0.60
## 铺出来的 NPC 是否立刻打开 AI（`false` 时它们站着不动，供静止夹具用）。
@export var setup_ai: bool = true

var _player: AnimalBody = null
var _origin := Vector3.ZERO
var _player_species: StringName = &""
var _npcs: Array[AnimalBody] = []
var _report: Dictionary = {}
var _setup_done := false
var _pending := false
var _attempts := 0


func _ready() -> void:
	if candidates.is_empty():
		candidates = default_candidates()


## 默认候选：从 `resources/species/` 列举并**逐个尝试 load**。
##
## **为什么不能按扩展名过滤**（T027 实测）：导出包里 `.tres` 会被转成 `.res` / `*.tres.remap`，
## 按 `ends_with(".tres")` 过滤会让默认列表在包里**变成空的**（源码内正常、包里静默失效）。
func default_candidates() -> Array[SpeciesConfig]:
	var out: Array[SpeciesConfig] = []
	var dir := DirAccess.open("res://resources/species")
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for n in names:
		var f := String(n)
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		var cfg := load("res://resources/species/%s" % f) as SpeciesConfig
		if cfg == null and f.ends_with(".remap"):
			cfg = load("res://resources/species/%s" % f.trim_suffix(".remap")) as SpeciesConfig
		if cfg != null:
			out.append(cfg)
	return out


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

## 按玩家物种铺生态。可重复调用（换物种/重开）——每次先 `clear()`。
## 返回 `spawn_report()` 同一份字典。
func setup(player: AnimalBody, origin: Vector3) -> Dictionary:
	clear()
	_attempts += 1
	_player = player
	_origin = origin
	_player_species = &""
	if player != null and player.species_config != null:
		_player_species = player.species_config.species_id
	_report = {
		"player_species": String(_player_species),
		"origin": origin,
		"spawned": [],
		"skipped": [],
		"skip_reasons": {},
		"min_distance": INF,
		"predator_min": predator_min_distance,
		"non_predator_min": min_spawn_distance,
	}
	if _player_species == &"":
		_report["note"] = "no_player_species"
		_setup_done = true
		ecology_ready.emit(_report)
		return _report
	if not _nav_ready():
		_pending = true
		_report["note"] = "nav_not_ready"
		ecology_ready.emit(_report)
		return _report
	_pending = false
	for cfg in candidates:
		if cfg == null or cfg.species_id == _player_species:
			continue                                  # 只铺"另一种物种"
		var want := desired_count(cfg)
		for _i in want:
			if _npcs.size() >= max_npcs:
				_note_skip(cfg.species_id, "max_npcs")
				break
			var pick := _pick_position(cfg)
			if not bool(pick.get("ok", false)):
				_note_skip(cfg.species_id, String(pick.get("reason", "unknown")))
				continue
			_spawn_one(cfg, pick["position"] as Vector3, String(pick.get("source", "")))
	_setup_done = true
	_report["attempt"] = _attempts
	# 一只都没铺出来 + 拒绝理由以导航类为主 + 还没超次数 → 导航/关卡还没同步完，下一物理帧再试
	if npc_count() == 0 and _attempts < MAX_SETUP_ATTEMPTS and _nav_rejections() > 0:
		_pending = true
		_report["note"] = "retry_pending"
	else:
		_pending = false
	ecology_ready.emit(_report)
	return _report


## 释放本组件铺出的所有 NPC（`queue_free` 到帧末才生效 → 先改名，避免同名节点被引擎自动改名）。
func clear() -> void:
	for b in _npcs:
		if b != null and is_instance_valid(b):
			b.name = "%s_retired" % b.name
			b.queue_free()
	_npcs.clear()
	_setup_done = false


# ---------------------------------------------------------------------------
# 查询（供断言/试玩观察）
# ---------------------------------------------------------------------------

func is_setup_done() -> bool:
	return _setup_done


func player_species_id() -> StringName:
	return _player_species


func spawn_origin() -> Vector3:
	return _origin


## **玩家不计入**：只数本组件铺出、且仍然活跃（存活、未被捕获、仍在 `animal` 组）的 NPC。
func npc_count() -> int:
	var n := 0
	for b in _npcs:
		if _is_active(b):
			n += 1
	return n


func npc_count_of(species_id: StringName) -> int:
	var n := 0
	for b in _npcs:
		if _is_active(b) and b.species_config != null and b.species_config.species_id == species_id:
			n += 1
	return n


func npc_ids() -> Array[int]:
	var out: Array[int] = []
	for b in _npcs:
		if _is_active(b):
			out.append(int(b.get_instance_id()))
	return out


func npc_bodies() -> Array[AnimalBody]:
	var out: Array[AnimalBody] = []
	for b in _npcs:
		if _is_active(b):
			out.append(b)
	return out


## 所有铺出过的身体（含已被捕获的）——清理与诊断用。
func tracked_bodies() -> Array[AnimalBody]:
	var out: Array[AnimalBody] = []
	for b in _npcs:
		if b != null and is_instance_valid(b):
			out.append(b)
	return out


func spawn_report() -> Dictionary:
	return _report.duplicate(true)


## 实测的"最近一只 NPC 距玩家出生点"（没有 NPC 时为 INF）。
func min_spawn_distance_actual() -> float:
	var best: float = INF
	for s in (_report.get("spawned", []) as Array):
		best = minf(best, float((s as Dictionary).get("distance", INF)))
	return best


func desired_count(cfg: SpeciesConfig) -> int:
	if cfg == null:
		return 0
	var key := cfg.species_id
	if count_overrides.has(key):
		return maxi(0, int(count_overrides[key]))
	if count_overrides.has(String(key)):
		return maxi(0, int(count_overrides[String(key)]))
	return maxi(0, count_per_species)


## 该物种距玩家出生点的最小距离：**捕食者用更大的半径**（按 `can_attack` 分派，不看物种名）。
func min_distance_for(cfg: SpeciesConfig) -> float:
	if cfg == null:
		return min_spawn_distance
	return predator_min_distance if cfg.can_attack else min_spawn_distance


# ---------------------------------------------------------------------------
# 落点
# ---------------------------------------------------------------------------

func _pick_position(cfg: SpeciesConfig) -> Dictionary:
	var need := min_distance_for(cfg)
	var rejected: Dictionary = {}
	for cand in _candidate_points(cfg):
		var pt: Vector3 = cand["point"]
		var source: String = cand["source"]
		var snap := _snap_on_layer(pt, _nav_layer_for(cfg))
		if snap.distance_to(pt) > snap_tolerance:
			_bump(rejected, "not_on_layer")
			continue
		var d := snap.distance_to(_origin)
		if d < need:
			_bump(rejected, "too_close")
			continue
		if d > max_spawn_distance:
			_bump(rejected, "too_far")
			continue
		var nearest := INF
		for b in npc_bodies():
			nearest = minf(nearest, snap.distance_to(b.global_position))
		if nearest < min_npc_separation:
			_bump(rejected, "too_near_other")
			continue
		var place := snap
		place.y = snap.y + cfg.capsule_half_height + 0.05    # 站在导航面**之上**，不要半沉进地面
		return {"ok": true, "position": place, "source": source, "distance": d}
	return {"ok": false, "reason": _dominant_reason(rejected)}


## 候选点顺序：标记点 → 绕标记的环 → 绕玩家出生点的环（保证"至少离玩家多远"有解）。
func _candidate_points(cfg: SpeciesConfig) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for marker in _spawn_markers(cfg):
		out.append({"point": marker, "source": "marker"})
		for r in [ring_radius, ring_radius * 1.6]:
			for p in _ring(marker, float(r)):
				out.append({"point": p, "source": "marker_ring"})
	var need := min_distance_for(cfg)
	for r in [need + 2.0, need + 6.0]:
		for p in _ring(_origin, float(r)):
			out.append({"point": p, "source": "origin_ring"})
	return out


func _spawn_markers(cfg: SpeciesConfig) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for grp in [spawn_point_group, fallback_spawn_group]:
		for n in get_tree().get_nodes_in_group(grp):
			var m := n as Node3D
			if m == null:
				continue
			var s := StringName(m.get_meta("species", &""))
			if s != &"" and s != cfg.species_id:
				continue                              # 有物种标注就必须匹配
			out.append(m.global_position)
		if not out.is_empty():
			break                                 # 优先组里有就够用
	return out


func _ring(center: Vector3, radius: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in 12:
		var a := TAU * float(k) / 12.0
		out.append(center + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	return out


## 按**物种自己的导航层**吸附（Godot 4.7.2 的 `map_get_closest_point()` 不带层 → 用 trivial 路径代替）。
func _snap_on_layer(point: Vector3, layer: int) -> Vector3:
	var map := _nav_map()
	if not map.is_valid():
		return point
	var p: PackedVector3Array = NavigationServer3D.map_get_path(
		map, point, point + Vector3(0.05, 0.0, 0.0), true, maxi(1, layer))
	if p.size() >= 1:
		return p[0]
	return Vector3(INF, INF, INF)


func _nav_map() -> RID:
	var w := get_world_3d()
	if w == null:
		return RID()
	return w.get_navigation_map()


## 导航层从**关卡区域 metadata** 反查（与 `AnimalAI._resolve_nav_layer()` 同口径）。
func _nav_layer_for(cfg: SpeciesConfig) -> int:
	var chain: Array[Node] = []
	var n: Node = self
	while n != null:
		chain.append(n)
		n = n.get_parent()
	for top in chain:
		for x in _all_nodes(top):
			if x is NavigationRegion3D:
				var reg := x as NavigationRegion3D
				var sid := StringName(reg.get_meta("species_id", &""))
				if sid == cfg.species_id:
					return maxi(1, reg.navigation_layers)
	return 1


func _all_nodes(node: Node) -> Array[Node]:
	if node == null:
		return []
	var out: Array[Node] = [node]
	for c in node.get_children():
		out.append_array(_all_nodes(c))
	return out


# ---------------------------------------------------------------------------
# 生成与记账
# ---------------------------------------------------------------------------

func _spawn_one(cfg: SpeciesConfig, pos: Vector3, source: String) -> void:
	if body_scene == null:
		_note_skip(cfg.species_id, "no_body_scene")
		return
	var body := body_scene.instantiate() as AnimalBody
	if body == null:
		_note_skip(cfg.species_id, "body_not_animal")
		return
	body.name = "NPC_%s_%d" % [String(cfg.species_id), _npcs.size()]
	body.species_config = cfg          # 入树前赋值：`_ready` 会 apply_config()
	body.player_controlled = false
	body.ai_enabled = setup_ai
	add_child(body)
	body.global_position = pos
	body.velocity = Vector3.ZERO
	if body.climb != null:
		body.climb.reset_base()
	_npcs.append(body)
	(_report["spawned"] as Array).append({
		"species": String(cfg.species_id),
		"position": pos,
		"distance": pos.distance_to(_origin),
		"source": source,
		"can_attack": cfg.can_attack,
		"id": int(body.get_instance_id()),
	})
	_report["min_distance"] = minf(float(_report.get("min_distance", INF)), pos.distance_to(_origin))


func _is_active(b: AnimalBody) -> bool:
	if b == null or not is_instance_valid(b) or not b.is_inside_tree():
		return false
	if b.survival != null and b.survival.is_dead():
		return false
	if b.is_in_group(&"animal_bodies"):
		return true
	return false                                     # 被捕获后出组 → 不再计入


func _note_skip(species_id: StringName, reason: String) -> void:
	(_report["skipped"] as Array).append({"species": String(species_id), "reason": reason})
	_bump(_report["skip_reasons"] as Dictionary, reason)


func _bump(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1


func _dominant_reason(rejected: Dictionary) -> String:
	var best := "no_candidate"
	var best_n := 0
	for k in rejected.keys():
		if int(rejected[k]) > best_n:
			best = String(k)
			best_n = int(rejected[k])
	return best
# ---------------------------------------------------------------------------
# 导航就绪与重试
# ---------------------------------------------------------------------------
# 真实关卡在 `_ready` 阶段导航图还没有 iteration → 这时硬铺会把所有候选点判成"不在层上"。
# 记 `_pending`，由 `_physics_process` 在导航就绪后重试一次（HUD 下一拍显示真实计数）。

func _physics_process(_delta: float) -> void:
	if _pending and _nav_ready():
		_pending = false
		setup(_player, _origin)


## 供断言/诊断：导航图是否已同步（`map_get_iteration_id() > 0`）。
func nav_ready() -> bool:
	return _nav_ready()


func _nav_ready() -> bool:
	var map := _nav_map()
	if not map.is_valid():
		return false
	return NavigationServer3D.map_get_iteration_id(map) > 0


## 报告里"导航类"拒绝的条数（导航/关卡还没同步好的强信号，用于决定是否重试）。
func _nav_rejections() -> int:
	var r: Dictionary = _report.get("skip_reasons", {})
	return int(r.get("not_on_layer", 0)) + int(r.get("no_candidate", 0))
