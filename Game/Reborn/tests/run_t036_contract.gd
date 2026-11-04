extends SceneTree
## T036 数据契约与跨世回归 —— 先写可失败的断言（对应 `Docs/Tasks/T036.md` §6）。
##
## 覆盖：
##   A 契约形状（TD §3 的七个对象里「一致」的部分必须锁死：键集合 + 类型 + 单位）
##   B 稳定 ID（LifeId 格式/唯一、区域键、资源 interaction_id、地点发现去重）
##   C 存活期同步（CurrentLife 的 survival / transform 在活着时就可得）
##   D 捕获对照（本世计数 / 事件归属 / 区域扣账 / 幂等）
##   E 死亡对照（只结算一次 / 归档 / 快照 / 事件区间 / 档案隔离）
##   F 重生与多世（ID 递增 / 世界时间不回零 / 种群与发现保留 / 存活值回满 / 引用完整 / seq 单调）
##   G 新游戏重置（档案与解锁清空 / 计数器归零 / 区域重置 / 世界时间归零）
##
## 首跑策略：`sync_current_life` / `current_life.transform` 一律 `call()/get()` 探测 ——
## 未实现时该段只出一条红，脚本不崩（同 t034/t035 先红原则）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t036_contract.gd' --quit-after 300000
## 结果口径：RESULT|pass=<n>|fail=<n> 全绿；失败时另打 RESULT|failed=<清单>。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const CAT_ID := &"Cat"
const MOUSE_ID := &"Mouse"
const RESOURCE_GROUP := &"resource_points"
const ANIMAL_GROUP := &"animal_bodies"
const PROBE_PLACE := "t036_probe_place"

const RESOURCE_KEYS: Array[String] = ["id", "region_id", "kind", "food_type", "units",
	"capacity", "next_refill_at", "refill_interval", "transform", "expire_at"]
const REGION_KEYS: Array[String] = ["region_id", "species_id", "total_count",
	"capacity", "next_recover_at", "recover_interval"]
const EVENT_KEYS: Array[String] = ["seq", "life_id", "kind", "world_time", "data"]
const ARCHIVE_KEYS: Array[String] = ["life_id", "species_id", "start_world_time",
	"end_world_time", "duration", "end_reason", "damage_reason", "start_position",
	"captures", "escapes", "food_gained", "water_gained", "discoveries",
	"event_first", "event_last", "snapshot", "transform"]
## TD §3 `SpeciesConfig` 的契约字段（25 项；扩展组不算在内）
const SPECIES_KEYS: Array[String] = ["species_id", "capsule_radius", "capsule_half_height",
	"walk_speed", "sprint_speed", "crouch_speed", "crouch_half_height", "max_step_height",
	"jump_velocity", "max_acceleration", "camera_offset_z", "fov", "vision_range",
	"vision_half_angle_deg", "hearing_range", "hunger_loss_per_sec", "thirst_loss_per_sec",
	"sprint_stamina_per_sec", "stamina_regen_per_sec", "regen_delay", "interaction_range",
	"allowed_food_types", "can_jump", "can_pounce", "can_use_mouse_tunnel"]

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _first_life := ""
var _mouse_region := &""
var _mouse_total_after_capture := -1
## 资源点探针（关卡不烘焙资源点，运行时实例化；见 A3 段）
var _rp: Node3D = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("RESULT|fail=1")
		print("RESULT|failed=A0_scene_load")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	root.size = Vector2i(1280, 720)
	await _advance_frames(2)
	var entry := main as MainEntry
	if entry == null:
		print("RESULT|fail=1")
		print("RESULT|failed=A0_entry_class")
		quit(1)
		return

	await _section_a_shapes(entry)
	await _section_b_stable_ids(entry)
	await _section_c_live_sync(entry)
	await _section_d_capture(entry)
	await _section_e_death(entry)
	await _section_f_rebirth_multi_life(entry)
	await _section_g_new_game_reset(entry)

	if _rp != null and is_instance_valid(_rp):
		_rp.queue_free()
	main.queue_free()
	await _advance_frames(2)
	_summary()
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _wd() -> Node:
	return root.get_node_or_null("/root/WorldDirector")


func _gs() -> Node:
	return root.get_node_or_null("/root/GameState")


func _advance_frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_real_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _assert(key: String, expected: String, actual: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("PASS|%s" % key)
	else:
		_fail += 1
		_failed.append(key)
		print("FAIL|%s|expected=%s|actual=%s" % [key, expected, actual])


func _summary() -> void:
	print("RESULT|pass=%d|fail=%d" % [_pass, _fail])
	if _fail > 0:
		print("RESULT|failed=%s" % ",".join(_failed))


func _keys_sorted(d: Dictionary) -> Array:
	var out: Array = []
	for k in d.keys():
		out.append(String(k))
	out.sort()
	return out


## 递归判断纯数据：存档快照里**不允许**出现 Node/Object（TD §3「没有 Node 引用的部分才可进存档」）
func _is_pure_data(v: Variant) -> bool:
	if v == null:
		return true
	if v is Object:
		return false
	if v is Dictionary:
		for k in (v as Dictionary).keys():
			if not _is_pure_data((v as Dictionary)[k]):
				return false
		return true
	if v is Array:
		for item in (v as Array):
			if not _is_pure_data(item):
				return false
		return true
	return true


## 契约里的四个数值字段类型必须是 float（int 会破坏存档的浮点精度）
func _all_floats(d: Dictionary, keys: Array) -> bool:
	for k in keys:
		if typeof(d.get(k)) != TYPE_FLOAT:
			return false
	return true


func _has_sync_api() -> bool:
	var gs := _gs()
	return gs != null and gs.has_method("sync_current_life")


func _current_transform_ok() -> bool:
	var cur := _gs().get("current_life") as Dictionary
	return cur.has("transform") and typeof(cur.get("transform")) == TYPE_TRANSFORM3D


func _wait_setup(entry: MainEntry) -> bool:
	for i in 240:
		if entry.ecology != null and bool(entry.ecology.call("is_setup_done")):
			return true
		await process_frame
	return false


func _mouse_bodies() -> Array:
	var out: Array = []
	for b in get_nodes_in_group(ANIMAL_GROUP):
		if b == null or not is_instance_valid(b):
			continue
		var cfg = b.get("species_config")
		if cfg == null or String(cfg.get("species_id")) != "Mouse":
			continue
		if bool(b.get("captured")):
			continue
		out.append(b)
	return out


func _kill(entry: MainEntry) -> void:
	if entry.player == null or not is_instance_valid(entry.player):
		return
	entry.player.survival.apply_damage(9999.0, &"t036_test")
	await _advance_frames(14)


func _respawn(entry: MainEntry) -> bool:
	entry.dismiss_settle()
	await _advance_frames(2)
	var ok := entry.select_species(CAT_ID)
	await _advance_frames(6)
	return ok


# ---------------------------------------------------------------------------
# A 契约形状
# ---------------------------------------------------------------------------

func _section_a_shapes(entry: MainEntry) -> void:
	print("---- A 契约形状 ----")

	# A1 SurvivalState：契约 5 字段，四个数值必须是 float
	var sd := SurvivalState.new().to_dictionary()
	var sd_keys := _keys_sorted(sd)
	_assert("A1_survival_state_keys", "5 键", ",".join(sd_keys),
		sd_keys == ["health", "hunger", "last_damage_reason", "stamina", "thirst"])
	_assert("A1b_survival_values_float", "health/hunger/thirst/stamina = float", "",
		_all_floats(sd, ["health", "hunger", "thirst", "stamina"]))
	_assert("A1c_survival_nametype", "last_damage_reason StringName",
		str(typeof(sd.get("last_damage_reason"))),
		typeof(sd.get("last_damage_reason")) == TYPE_STRING_NAME)

	# A2 RegionRecord：六字段（String/String/int/int/float/float）
	var wd := _wd()
	var regions = wd.call("region_population_snapshot")
	_assert("A2a_region_snapshot_exists", "Array 且非空", str(typeof(regions)),
		regions is Array and (regions as Array).size() > 0)
	if regions is Array and (regions as Array).size() > 0:
		var r0: Dictionary = (regions as Array)[0]
		_assert("A2b_region_keys", ",".join(REGION_KEYS), ",".join(_keys_sorted(r0)),
			_keys_sorted(r0) == ["capacity", "next_recover_at", "recover_interval",
				"region_id", "species_id", "total_count"])
		_assert("A2c_region_types", "str/str/int/int/float/float",
			"%d/%d/%d/%d/%d/%d" % [typeof(r0["region_id"]), typeof(r0["species_id"]),
				typeof(r0["total_count"]), typeof(r0["capacity"]),
				typeof(r0["next_recover_at"]), typeof(r0["recover_interval"])],
			typeof(r0["region_id"]) == TYPE_STRING
			and typeof(r0["species_id"]) == TYPE_STRING
			and typeof(r0["total_count"]) == TYPE_INT
			and typeof(r0["capacity"]) == TYPE_INT
			and typeof(r0["next_recover_at"]) == TYPE_FLOAT
			and typeof(r0["recover_interval"]) == TYPE_FLOAT)
		_assert("A2d_region_pure_data", "无 Object 引用", "", _is_pure_data(regions))

	# A3 ResourceRecord：十字段，含 Transform3D
	# 关卡本身不烘焙资源点（T012 口径：运行时布置），这里实例化一个探针点（同 t034 A 段做法）。
	var packed_rp := load("res://scenes/world/resource_point.tscn") as PackedScene
	if packed_rp != null:
		_rp = packed_rp.instantiate() as Node3D
	_assert("A3a_resource_point_scene", "可实例化", "null", _rp != null)
	if _rp != null:
		_rp.set("interaction_id", "T036_RP_PROBE")
		_rp.position = Vector3(0.0, 0.2, 0.0)
		root.add_child(_rp)
		await process_frame
		var rr: Dictionary = _rp.call("to_record")
		_assert("A3b_resource_keys", ",".join(RESOURCE_KEYS), ",".join(_keys_sorted(rr)),
			_keys_sorted(rr) == ["capacity", "expire_at", "food_type", "id",
				"kind", "next_refill_at", "refill_interval", "region_id", "transform", "units"])
		_assert("A3c_resource_transform_type", "Transform3D", str(typeof(rr.get("transform"))),
			typeof(rr.get("transform")) == TYPE_TRANSFORM3D)
		_assert("A3d_resource_pure_data", "无 Object 引用", "", _is_pure_data(rr))

	# A4 LifeEvent：5 键
	_gs().call("record_event", "", &"t036_probe", {"probe": true})
	var ev: Dictionary = (_gs().get("events") as Array).back()
	_assert("A4a_event_keys", ",".join(EVENT_KEYS), ",".join(_keys_sorted(ev)),
		_keys_sorted(ev) == ["data", "kind", "life_id", "seq", "world_time"])
	_assert("A4b_event_seq_int", "int", str(typeof(ev.get("seq"))),
		typeof(ev.get("seq")) == TYPE_INT)
	_assert("A4c_event_kind_string", "String（不是 StringName）", str(typeof(ev.get("kind"))),
		typeof(ev.get("kind")) == TYPE_STRING)

	# A5 SpeciesConfig：TD §3 的 25 项契约字段（扩展组另计）
	var missing_cat: Array = []
	var missing_mouse: Array = []
	for cfg in entry.species_configs():
		var miss: Array = []
		for f in SPECIES_KEYS:
			if cfg.get(f) == null:
				miss.append(f)
		if String(cfg.get("species_id")) == "Cat":
			missing_cat = miss
		elif String(cfg.get("species_id")) == "Mouse":
			missing_mouse = miss
	_assert("A5a_species_contract_fields_cat", "25/25", "缺 %s" % str(missing_cat),
		missing_cat.is_empty())
	_assert("A5b_species_contract_fields_mouse", "25/25", "缺 %s" % str(missing_mouse),
		missing_mouse.is_empty())

	# A6/A7 档案形状（出生后才有，见 C 段）


# ---------------------------------------------------------------------------
# B 稳定 ID
# ---------------------------------------------------------------------------

func _section_b_stable_ids(entry: MainEntry) -> void:
	print("---- B 稳定 ID ----")
	var gs := _gs()
	_assert("B1_life_id_format", "L0001", String(gs.call("peek_life_id")),
		String(gs.call("peek_life_id")) == "L0001")

	# 区域键集合（region|species）——跨重生必须一字不变
	var keys_a: Array = []
	for r in (_wd().call("region_population_snapshot") as Array):
		keys_a.append("%s|%s" % [r.get("region_id"), r.get("species_id")])
	keys_a.sort()
	_assert("B3a_region_keys_count", "8 条", str(keys_a.size()), keys_a.size() == 8)
	_assert("B3b_region_keys_stable", "4 区 × 2 物种",
		",".join(keys_a),
		keys_a == ["Courtyard|Cat", "Courtyard|Mouse", "Creek|Cat", "Creek|Mouse",
			"Grass|Cat", "Grass|Mouse", "Roots|Cat", "Roots|Mouse"])

	# 资源稳定 ID：非空且全局唯一（T017 契约）。用 A 段探针点 + 关卡里的运行时资源点。
	var ids: Array = []
	var dup := ""
	for rp in get_nodes_in_group(RESOURCE_GROUP):
		var id := String(rp.get("interaction_id"))
		if id == "":
			dup = "空 ID"
			break
		if ids.has(id):
			dup = "重复：%s" % id
			break
		ids.append(id)
	_assert("B4_resource_ids_unique", "非空且唯一", "n=%d %s" % [ids.size(), dup],
		dup == "" and ids.size() > 0)

	# 地点发现 ID：去重、列表稳定
	var gs_first := bool(gs.call("record_place_discovery", PROBE_PLACE))
	var gs_again := bool(gs.call("record_place_discovery", PROBE_PLACE))
	var list1: Array = gs.call("discovered_place_list")
	var list2: Array = gs.call("discovered_place_list")
	_assert("B5a_discovery_dedup", "首次 true / 再次 false",
		"%s/%s" % [gs_first, gs_again], gs_first and not gs_again)
	_assert("B5b_discovery_list_stable", "含探针且排序稳定", ",".join(list1),
		list1.has(PROBE_PLACE) and list1 == list2
			and list1.duplicate() == list1)

	# 契约缺失项必须在场：WorldSnapshot 整容器（记录于证据，断言只锁「不存在」不锁值）
	_assert("B6_world_snapshot_absent_by_design", "T037 负责",
		"gs.has_method=%s" % str(gs.has_method("world_snapshot")),
		not gs.has_method("world_snapshot"))


# ---------------------------------------------------------------------------
# C 存活期同步
# ---------------------------------------------------------------------------

func _section_c_live_sync(entry: MainEntry) -> void:
	print("---- C 存活期同步 ----")
	var gs := _gs()

	# C5 无生命时同步必须被拒（不产生档案写）
	if not _has_sync_api():
		_assert("C0_sync_api_exists", "GameState.sync_current_life",
			"未实现（首跑红）", false)
		return
	var empty_sync := bool(gs.call("sync_current_life", {"health": 1.0}, Transform3D()))
	_assert("C5_sync_rejected_without_life", "false 且 current_life 仍空",
		"ret=%s empty=%s" % [empty_sync, str(gs.get("current_life").is_empty())],
		not empty_sync and (gs.get("current_life") as Dictionary).is_empty())

	var spawned := entry.select_species(CAT_ID)
	await _advance_frames(6)
	_assert("C1a_spawned", "alive", entry.lifecycle_state_name(),
		spawned and entry.lifecycle_state_name() == "alive")
	if not spawned:
		return
	var cur := gs.get("current_life") as Dictionary
	_first_life = String(cur.get("life_id", ""))
	_assert("C1b_life_id_assigned", "L0001", _first_life, _first_life == "L0001")
	_assert("C1c_species_recorded", "Cat", String(cur.get("species_id", "")),
		String(cur.get("species_id", "")) == "Cat")

	# 契约字段在场（archive 17 键；CurrentLife 的关键八项在其子集内）
	var miss: Array = []
	for k in ARCHIVE_KEYS:
		if not cur.has(k):
			miss.append(k)
	_assert("A6_archive_keys", "17 键齐", "缺 %s" % str(miss), miss.is_empty())
	_assert("A7a_current_life_contract_fields", "life_id/species_id/snapshot/transform",
		"%s/%s/%s/%s" % [cur.has("life_id"), cur.has("species_id"),
			cur.has("snapshot"), cur.has("transform")],
		cur.has("life_id") and cur.has("species_id")
			and cur.has("snapshot") and cur.has("transform"))
	_assert("A7b_archive_pure_data", "无 Object 引用", "", _is_pure_data(cur))

	# C2/C3 存活期同步：等一次 0.2 s 的 survival 回调
	await _wait_real_ms(700)
	cur = gs.get("current_life") as Dictionary
	var snap: Dictionary = cur.get("snapshot", {})
	var live := entry.player.survival.state
	_assert("C2a_live_survival_keys", "5 键", ",".join(_keys_sorted(snap)),
		_keys_sorted(snap) == ["health", "hunger", "last_damage_reason", "stamina", "thirst"])
	_assert("C2b_live_survival_value", "与 survival.state 同值（±0.5）",
		"snap=%.2f live=%.2f" % [float(snap.get("health", -1)), live.health],
		abs(float(snap.get("health", -1)) - live.health) <= 0.5)
	_assert("C3a_live_transform_type", "Transform3D", str(typeof(cur.get("transform"))),
		_current_transform_ok())
	var tpos: Transform3D = cur.get("transform", Transform3D())
	_assert("C3b_live_transform_position", "≈ 玩家位置（≤0.15 m）",
		"%.3f m" % tpos.origin.distance_to(entry.player.global_position),
		tpos.origin.distance_to(entry.player.global_position) <= 0.15)

	# C4 位移后再同步
	var moved := entry.player.global_position + Vector3(0.5, 0.0, 0.0)
	entry.player.global_position = moved
	await _advance_frames(2)
	await _wait_real_ms(700)
	cur = gs.get("current_life") as Dictionary
	tpos = cur.get("transform", Transform3D())
	_assert("C4_transform_follows_move", "≈ 新位置（≤0.15 m）",
		"%.3f m" % tpos.origin.distance_to(moved),
		tpos.origin.distance_to(moved) <= 0.15)


# ---------------------------------------------------------------------------
# D 捕获对照
# ---------------------------------------------------------------------------

func _section_d_capture(entry: MainEntry) -> void:
	print("---- D 捕获对照 ----")
	var gs := _gs()
	var wd := _wd()
	if not await _wait_setup(entry):
		_assert("D0_ecology_ready", "is_setup_done", "未就绪", false)
		return
	var mice := _mouse_bodies()
	_assert("D0b_mouse_npc_exists", "≥ 1", str(mice.size()), mice.size() > 0)
	if mice.is_empty():
		return
	var m0 = mice[0]
	_mouse_region = wd.call("region_id_at", m0.global_position)
	var before: int = int(wd.call("region_total", _mouse_region, MOUSE_ID))

	var ok := bool(entry.player.capture.try_capture(m0, m0.global_position))
	await _advance_frames(4)
	var cur := gs.get("current_life") as Dictionary
	_assert("D1_capture_recorded_in_life", "captures=1", str(int(cur.get("captures", -1))),
		ok and int(cur.get("captures", -1)) == 1)

	var cap_events: Array = gs.call("events_of_kind", &"capture")
	var last_cap: Dictionary = cap_events.back() if cap_events.size() > 0 else {}
	_assert("D2_capture_event_belongs_to_life", "life_id=%s" % _first_life,
		String(last_cap.get("life_id", "")),
		String(last_cap.get("life_id", "")) == _first_life)

	_mouse_total_after_capture = int(wd.call("region_total", _mouse_region, MOUSE_ID))
	_assert("D3_region_deduct_once", "%d（原 %d）" % [before - 1, before],
		str(_mouse_total_after_capture), _mouse_total_after_capture == before - 1)

	var dup := bool(wd.call("report_capture", "t036_dup", m0.source_id(),
		m0.global_position, -1.0))
	_assert("D4_capture_idempotent", "重复上报 false 且不改账",
		"%s total=%d" % [dup, int(wd.call("region_total", _mouse_region, MOUSE_ID))],
		not dup and int(wd.call("region_total", _mouse_region, MOUSE_ID)) == _mouse_total_after_capture)


# ---------------------------------------------------------------------------
# E 死亡对照
# ---------------------------------------------------------------------------

func _section_e_death(entry: MainEntry) -> void:
	print("---- E 死亡对照 ----")
	var gs := _gs()
	await _kill(entry)
	# 死亡 → 自动进入选物种（T032 口径：结算页盖在选物种画面上），状态**不是** settling
	_assert("E1a_death_enters_select", "selecting 且结算页可见",
		"state=%s panel=%s" % [entry.lifecycle_state_name(),
			str(entry.settle_panel != null and entry.settle_panel.visible)],
		entry.lifecycle_state_name() == "selecting"
			and entry.settle_panel != null and entry.settle_panel.visible)
	_assert("E1b_lifecycle_double_end_rejected", "空字典",
		str(entry.lifecycle.end_life(&"second").size()),
		(entry.lifecycle.end_life(&"second") as Dictionary).is_empty())
	_assert("E1c_gamestate_double_end_rejected", "二次 end_life 返回空",
		str((gs.call("end_life", &"second", {}) as Dictionary).size()),
		(gs.call("end_life", &"second", {}) as Dictionary).is_empty())

	var n: int = int(gs.call("archive_count"))
	_assert("E2_archive_grew", "1", str(n), n == 1)
	var rec: Dictionary = gs.call("last_record")
	var start := float(rec.get("start_world_time", -2.0))
	var end := float(rec.get("end_world_time", -2.0))
	_assert("E3_duration_matches_timestamps", "end−start（±0.001）",
		"%.3f / %.3f" % [float(rec.get("duration", -1.0)), end - start],
		abs(float(rec.get("duration", -1.0)) - maxf(0.0, end - start)) <= 0.001)
	_assert("E4_end_reasons", "died / t036_test",
		"%s / %s" % [rec.get("end_reason"), rec.get("damage_reason")],
		String(rec.get("end_reason", "")) == "died"
			and String(rec.get("damage_reason", "")) == "t036_test")
	var snap: Dictionary = rec.get("snapshot", {})
	_assert("E5a_death_snapshot_keys", "5 键", ",".join(_keys_sorted(snap)),
		_keys_sorted(snap) == ["health", "hunger", "last_damage_reason", "stamina", "thirst"])
	_assert("E5b_death_snapshot_health_zero", "≤0", "%.3f" % float(snap.get("health", 1.0)),
		float(snap.get("health", 1.0)) <= 0.001)
	_assert("E6_current_life_cleared", "空", str((gs.get("current_life") as Dictionary).size()),
		(gs.get("current_life") as Dictionary).is_empty())

	var evs: Array = gs.call("events_for", _first_life)
	_assert("E7a_event_range_nonempty", "≥3 条", str(evs.size()), evs.size() >= 3)
	_assert("E7b_event_range_first_start", "life_start",
		String(evs[0].get("kind", "")) if evs.size() > 0 else "",
		evs.size() > 0 and String(evs[0].get("kind", "")) == "life_start")
	_assert("E7c_event_range_last_end", "life_end",
		String(evs.back().get("kind", "")) if evs.size() > 0 else "",
		evs.size() > 0 and String(evs.back().get("kind", "")) == "life_end")
	_assert("E7d_event_range_matches_archive", "event_first/last 覆盖",
		"%d..%d" % [int(rec.get("event_first", -1)), int(rec.get("event_last", -1))],
		int(evs[0].get("seq", -1)) == int(rec.get("event_first", -2))
			and int(evs.back().get("seq", -1)) == int(rec.get("event_last", -2)))

	# E8 档案隔离：外部改副本不得影响已归档记录
	var view: Dictionary = gs.call("last_record")
	view["captures"] = 999
	var archived: Dictionary = (gs.get("life_records") as Array)[0]
	_assert("E8_archive_copy_isolated", "captures 仍为 1", str(int(archived.get("captures", -1))),
		int(archived.get("captures", -1)) == 1)


# ---------------------------------------------------------------------------
# F 重生与多世
# ---------------------------------------------------------------------------

func _section_f_rebirth_multi_life(entry: MainEntry) -> void:
	print("---- F 重生与多世 ----")
	var gs := _gs()
	var wd := _wd()
	var wt_before := float(wd.get("world_time"))
	var ok2 := await _respawn(entry)
	_assert("F1a_respawn_alive", "alive", entry.lifecycle_state_name(),
		ok2 and entry.lifecycle_state_name() == "alive")
	var lid2 := entry.current_life_id()
	_assert("F1b_second_life_id", "L0002", lid2, lid2 == "L0002" and lid2 != _first_life)
	_assert("F2_world_time_not_reset", "不回零且 ≥ 前一世",
		"%.2f → %.2f" % [wt_before, float(wd.get("world_time"))],
		float(wd.get("world_time")) >= wt_before and float(wd.get("world_time")) > 0.0)
	_assert("F3_region_totals_persist", "鼠 %d" % _mouse_total_after_capture,
		str(int(wd.call("region_total", _mouse_region, MOUSE_ID))),
		int(wd.call("region_total", _mouse_region, MOUSE_ID)) == _mouse_total_after_capture)
	_assert("F4_discovery_persists", "true",
		str(bool(gs.call("is_place_discovered", PROBE_PLACE))),
		bool(gs.call("is_place_discovered", PROBE_PLACE)))
	var unlocked: Array = gs.call("unlocked_list")
	_assert("F4b_unlock_persists", "含 Cat", str(unlocked),
		unlocked.has(CAT_ID))

	await _wait_real_ms(700)
	var cur := gs.get("current_life") as Dictionary
	var snap: Dictionary = cur.get("snapshot", {})
	_assert("F5_fresh_survival", "health≈100",
		"health=%.1f" % float(snap.get("health", -1.0)),
		float(snap.get("health", -1.0)) >= 99.0 and _keys_sorted(snap).size() == 5)

	# 第三世（第二次死亡 → 重生）
	await _kill(entry)
	await _advance_frames(4)
	var ok3 := await _respawn(entry)
	var lid3 := entry.current_life_id()
	_assert("F6a_third_life_id", "L0003", lid3, ok3 and lid3 == "L0003" and lid3 != lid2)
	_assert("F6b_archive_two", "2", str(int(gs.call("archive_count"))),
		int(gs.call("archive_count")) == 2)

	# 事件引用完整性 + seq 单调
	var ids := {_first_life: true, lid2: true, lid3: true, "": true}
	var orphans: Array = []
	for e in (gs.get("events") as Array):
		var eid := String(e.get("life_id", ""))
		if not ids.has(eid):
			orphans.append(eid)
	_assert("F7_event_referential_integrity", "无孤儿 life_id", str(orphans.size()),
		orphans.is_empty())
	var seq_ok := true
	var prev := -1
	for e in (gs.get("events") as Array):
		var s := int(e.get("seq", -1))
		if s <= prev:
			seq_ok = false
			break
		prev = s
	_assert("F8_event_seq_monotonic", "严格递增", "last=%d" % prev, seq_ok and prev > 0)


# ---------------------------------------------------------------------------
# G 新游戏重置（破坏性，放最后）
# ---------------------------------------------------------------------------

func _section_g_new_game_reset(entry: MainEntry) -> void:
	print("---- G 新游戏重置 ----")
	var gs := _gs()
	var wd := _wd()
	gs.call("reset_for_new_game")
	await _advance_frames(2)
	_assert("G1a_archive_cleared", "0 / 0 / 0",
		"%d / %d / %d" % [int(gs.call("archive_count")), int(gs.call("event_count")),
			(gs.call("discovered_place_list") as Array).size()],
		int(gs.call("archive_count")) == 0 and int(gs.call("event_count")) == 0
			and (gs.call("discovered_place_list") as Array).is_empty())
	_assert("G1b_unlock_cleared", "0", str((gs.get("unlocked_species") as Dictionary).size()),
		(gs.get("unlocked_species") as Dictionary).is_empty())
	_assert("G1c_current_life_cleared", "空", str((gs.get("current_life") as Dictionary).size()),
		(gs.get("current_life") as Dictionary).is_empty())
	_assert("G2_life_counter_reset", "L0001", String(gs.call("peek_life_id")),
		String(gs.call("peek_life_id")) == "L0001")
	_assert("G3a_region_cleared", "records=0/initialized=false",
		"snap=%d init=%s" % [(wd.call("region_population_snapshot") as Array).size(),
			str(wd.get("region_population_initialized"))],
		(wd.call("region_population_snapshot") as Array).is_empty()
			and not bool(wd.get("region_population_initialized")))
	wd.call("init_region_population", entry.get("_configs"))
	var m := 0
	var c := 0
	for r in (wd.call("region_population_snapshot") as Array):
		if String(r.get("species_id")) == "Mouse":
			m += int(r.get("total_count", 0))
		elif String(r.get("species_id")) == "Cat":
			c += int(r.get("total_count", 0))
	_assert("G3b_region_reinit", "鼠8 / 猫4", "鼠%d / 猫%d" % [m, c], m == 8 and c == 4)
	_assert("G4_world_time_reset", "≈0", "%.3f" % float(wd.get("world_time")),
		float(wd.get("world_time")) <= 0.2)
