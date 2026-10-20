extends SceneTree
## T027 按玩家物种布置测试生态 断言（`Docs/Tasks/T027.md` §4）
##
## 覆盖：
##   A 数据与接口（组件接口 / 入口开关默认值 / 关卡出生标记 / 数量与半径分派 / 静态"不写物种名"）
##   B 按玩家物种布置（猫玩家→鼠 NPC、鼠玩家→猫 NPC、属性与导航层、换物种重铺、间距）
##   C 玩家不计入 NPC 数量（身份 / 与 `animal_bodies` 组交叉核对 / 连续换物种不漂移）
##   D 出生周围无即时攻击（距离规则 > 视距 + 4 s 行为窗口零伤害零攻击 + 拒绝原因可解释）
##   E 集成（同一张地图：猫捕鼠 / 鼠避猫 / 捕食者接近并会真的打到玩家）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t027_ecology.gd' --quit-after 300000
## 包内复验（只能用编辑器二进制 + --main-pack）：
##   & '<godot_console.exe>' --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
##       --script 'res://tests/run_t027_ecology.gd' --quit-after 300000

const ENTRY := "res://scenes/debug/ecology_entry.tscn"
const PLAIN_ENTRY := "res://scenes/debug/debug_entry.tscn"
const LEVEL_PATH := "res://scenes/maps/l_courtyard.tscn"
const SPAWNER_SRC := "res://scripts/world/ecology_spawner.gd"
const SETTLE := 150               # 覆盖"导航就绪后重试"的几帧
const GROUP_ANIMALS := &"animal_bodies"
const EPS := 1e-3

var _checks := 0
var _fails := 0
var _entry: Node3D = null
var _eco: EcologySpawner = null
var _player: AnimalBody = null
var _cat_cfg: SpeciesConfig = null
var _mouse_cfg: SpeciesConfig = null
var _cat_id: StringName = &""
var _mouse_id: StringName = &""
var _wd: Node = null


func _initialize() -> void:
	print("TEST|run_t027_ecology|engine=%s" % Engine.get_version_info().string)
	_wd = root.get_node_or_null("WorldDirector")
	await _section_a_interface()
	await _section_b_by_player_species()
	await _section_c_player_not_counted()
	await _section_d_spawn_safety()
	await _section_e_integration()
	await _free_entry()
	_finish()


# ---------------------------------------------------------------------------
# A 数据与接口
# ---------------------------------------------------------------------------

func _section_a_interface() -> void:
	print("---- A 数据与接口 ----")
	var probe := EcologySpawner.new()
	var wanted := ["setup", "clear", "npc_count", "npc_count_of", "npc_ids", "npc_bodies",
		"spawn_report", "min_distance_for", "desired_count", "spawn_origin",
		"player_species_id", "nav_ready", "is_setup_done"]
	var missing: Array[String] = []
	for m in wanted:
		if not probe.has_method(m):
			missing.append(m)
	_assert("A1_interface_complete", "0 缺失", str(missing), missing.is_empty())
	_assert("A1_defaults", "count=2 min=8.0 pred=14.0 max=3",
		"count=%d min=%.1f pred=%.1f max=%d" % [probe.count_per_species, probe.min_spawn_distance,
			probe.predator_min_distance, probe.max_npcs],
		probe.count_per_species == 2 and absf(probe.min_spawn_distance - 8.0) < EPS
			and absf(probe.predator_min_distance - 14.0) < EPS and probe.max_npcs == 3)
	var defs: Array = probe.call("default_candidates")
	_assert("A1_default_candidates_from_disk", "2（源码与**包内**都要成立）", str(defs.size()), defs.size() == 2)
	probe.free()

	# A2 入口默认值：`debug_entry.tscn` 关（既有夹具语义不变）、`ecology_entry.tscn` 开
	var plain: Node3D = (load(PLAIN_ENTRY) as PackedScene).instantiate() as Node3D
	root.add_child(plain)
	await _advance(40)
	_assert("A2_plain_entry_ecology_null", "null", str(plain.get("ecology")), plain.get("ecology") == null)
	var plain_line := String(plain.call("ecology_line"))
	_assert("A2_plain_entry_line_off", "以 eco: off 开头", plain_line.substr(0, 8), plain_line.begins_with("eco: off"))
	plain.queue_free()
	await _advance(4)

	await _fresh_eco_entry()
	if _eco == null or _player == null:
		_assert("A2_eco_entry_built", "非 null", "<null>", false)
		return
	_assert("A2_eco_entry_built", "非 null", str(_eco != null), _eco != null)
	_assert("A2_eco_setup_done", "true", str(_eco.is_setup_done()), _eco.is_setup_done())
	_assert("A2_eco_nav_ready", "true", str(_eco.nav_ready()), _eco.nav_ready())
	_assert("A2_two_species_ids_distinct", "两个不同的 species_id",
		"%s / %s" % [_cat_id, _mouse_id], _cat_id != &"" and _mouse_id != &"" and _cat_id != _mouse_id)

	# A3 关卡出生标记（真源：`spawn_points` 组 + `metadata/species`）
	var markers := _spawn_markers()
	_assert("A3_spawn_markers_nonempty", "≥ 2", str(markers.size()), markers.size() >= 2)
	var species_seen: Array[String] = []
	for m in markers:
		var s := String(m.get_meta("species", ""))
		if s != "" and not species_seen.has(s):
			species_seen.append(s)
	_assert("A3_markers_two_species", "%s 与 %s" % [_cat_id, _mouse_id], str(species_seen),
		species_seen.has(String(_cat_id)) and species_seen.has(String(_mouse_id)))

	# A4 数量与半径分派（数据驱动、按 can_attack 而不是物种名）
	var p2 := EcologySpawner.new()
	_assert_near("A4_default_count", 2.0, float(p2.desired_count(_cat_cfg)), EPS)
	p2.count_overrides = {_cat_id: 1}
	_assert_near("A4_override_speciesname_key", 1.0, float(p2.desired_count(_cat_cfg)), EPS)
	p2.count_overrides = {String(_mouse_id): 3}
	_assert_near("A4_override_string_key", 3.0, float(p2.desired_count(_mouse_cfg)), EPS)
	p2.count_overrides = {}
	p2.count_per_species = 5
	_assert_near("A4_per_species_applies", 5.0, float(p2.desired_count(_mouse_cfg)), EPS)
	_assert_near("A4_predator_radius_dispatch", p2.predator_min_distance, p2.min_distance_for(_cat_cfg), EPS)
	_assert_near("A4_prey_radius_dispatch", p2.min_spawn_distance, p2.min_distance_for(_mouse_cfg), EPS)
	_assert("A4_predator_radius_beats_vision", "> %.2f" % _cat_cfg.vision_range,
		"%.2f" % p2.min_distance_for(_cat_cfg), p2.min_distance_for(_cat_cfg) > _cat_cfg.vision_range)
	_assert("A4_prey_radius_beats_vision", "> %.2f" % _mouse_cfg.vision_range,
		"%.2f" % p2.min_distance_for(_mouse_cfg), p2.min_distance_for(_mouse_cfg) > _mouse_cfg.vision_range)
	_assert("A4_spawner_overrides_from_entry", "2 个物种",
		str(_eco.count_overrides), _eco.count_overrides.size() == 2)
	p2.free()

	# A5 静态检查：组件源码里不写物种名（差异必须在资源里）
	var src := FileAccess.get_file_as_string(SPAWNER_SRC)
	_assert("A5_source_loaded", "> 0", str(src.length()), src.length() > 0)
	_assert("A5_no_cat_name_literal", "不含 \"Cat\"", str(src.find("\"Cat\"")), src.find("\"Cat\"") < 0)
	_assert("A5_no_mouse_name_literal", "不含 \"Mouse\"", str(src.find("\"Mouse\"")), src.find("\"Mouse\"") < 0)

	# A6 计数口径的自我说明：报告里带上"玩家物种"与"安全半径"，便于日志核对
	var rep := _eco.spawn_report()
	_assert("A6_report_has_player_species", String(_player_species()), str(rep.get("player_species", "")),
		String(rep.get("player_species", "")) == String(_player_species()))
	_assert("A6_report_has_thresholds", "8.0/14.0",
		"%.1f/%.1f" % [float(rep.get("non_predator_min", -1.0)), float(rep.get("predator_min", -1.0))],
		absf(float(rep.get("non_predator_min", -1.0)) - 8.0) < EPS
			and absf(float(rep.get("predator_min", -1.0)) - 14.0) < EPS)


# ---------------------------------------------------------------------------
# B 按玩家物种布置
# ---------------------------------------------------------------------------

func _section_b_by_player_species() -> void:
	print("---- B 按玩家物种布置 ----")
	await _fresh_eco_entry()
	if _eco == null:
		_assert("B_setup", "非 null", "<null>", false)
		return
	_assert("B1_player_is_cat", String(_cat_id), String(_player_species()), _player_species() == _cat_id)
	_assert("B1_count_all_mouse", "2", str(_eco.npc_count_of(_mouse_id)), _eco.npc_count_of(_mouse_id) == 2)
	_assert("B1_no_cat_npc", "0", str(_eco.npc_count_of(_cat_id)), _eco.npc_count_of(_cat_id) == 0)
	_assert("B1_npc_count_total", "2", str(_eco.npc_count()), _eco.npc_count() == 2)
	_b_body_checks("B1", _mouse_id)
	_b_separation_check("B1")

	# B2/B5 切到鼠：旧鼠 NPC 释放，换成猫 NPC
	var old_ids := _eco.npc_ids()
	var old_bodies := _eco.tracked_bodies()
	await _switch(_mouse_id)
	_assert("B2_player_is_mouse", String(_mouse_id), String(_player_species()), _player_species() == _mouse_id)
	_assert("B2_count_all_cat", "1", str(_eco.npc_count_of(_cat_id)), _eco.npc_count_of(_cat_id) == 1)
	_assert("B2_no_mouse_npc", "0", str(_eco.npc_count_of(_mouse_id)), _eco.npc_count_of(_mouse_id) == 0)
	_b_body_checks("B2", _cat_id)
	var still_tracked := 0
	for b in old_bodies:
		if is_instance_valid(b):
			still_tracked += 1
	await _advance(6)
	var still_valid := 0
	for b in old_bodies:
		if is_instance_valid(b):
			still_valid += 1
	_assert("B5_old_npcs_released", "0 存活", str(still_valid), still_valid == 0)
	var new_ids := _eco.npc_ids()
	var overlap := 0
	for i in new_ids:
		if old_ids.has(i):
			overlap += 1
	_assert("B5_no_id_carryover", "0", str(overlap), overlap == 0)
	print("MEASURE|b5|old_ids=%s|new_ids=%s|still_tracked=%d" % [str(old_ids), str(new_ids), still_tracked])

	# B5b 再切回猫 → 又只有鼠 NPC
	await _switch(_cat_id)
	_assert("B5_back_to_prey_only", "2", str(_eco.npc_count_of(_mouse_id)), _eco.npc_count_of(_mouse_id) == 2)
	_assert("B5_back_no_predator", "0", str(_eco.npc_count_of(_cat_id)), _eco.npc_count_of(_cat_id) == 0)


## 每只 NPC 的属性与"吸附在自己的导航层上"
func _b_body_checks(tag: String, expect_species: StringName) -> void:
	var wrong_species := 0
	var not_in_group := 0
	var dead := 0
	var ai_off := 0
	var not_under_level := 0
	var controlled := 0
	var snap_bad := 0
	var snap_worst := 0.0
	var layer := int(_entry.call("nav_layer_for", expect_species))
	var bodies := _eco.npc_bodies()
	for b in bodies:
		if b.species_config == null or b.species_config.species_id != expect_species:
			wrong_species += 1
		if not b.is_in_group(GROUP_ANIMALS):
			not_in_group += 1
		if b.survival != null and b.survival.is_dead():
			dead += 1
		if not b.ai_enabled:
			ai_off += 1
		if not _level().is_ancestor_of(b):
			not_under_level += 1
		if b.player_controlled:
			controlled += 1
		var snap_err := _snap_on_layer(b.global_position, layer).distance_to(b.global_position)
		snap_worst = maxf(snap_worst, snap_err)
		if snap_err > 0.60:
			snap_bad += 1
	_assert("%s_npc_species_all" % tag, "0 例外", str(wrong_species), wrong_species == 0)
	_assert("%s_npc_in_animal_group" % tag, "0 例外", str(not_in_group), not_in_group == 0)
	_assert("%s_npc_alive" % tag, "0 死亡", str(dead), dead == 0)
	_assert("%s_npc_ai_enabled" % tag, "0 关闭", str(ai_off), ai_off == 0)
	_assert("%s_npc_under_level" % tag, "0 例外", str(not_under_level), not_under_level == 0)
	_assert("%s_npc_not_player_controlled" % tag, "0 例外", str(controlled), controlled == 0)
	_assert("%s_npc_on_own_nav_layer" % tag, "≤ 0.60 m（layer %d）" % layer, "%.3f m" % snap_worst, snap_bad == 0)
	print("MEASURE|%s|npcs=%d|layer=%d|snap_worst=%.3f" % [tag, bodies.size(), layer, snap_worst])


## 出生间距（按**出生报告**的落点算 —— NPC 之后会自己走动，实时间距不能当判据）
func _b_separation_check(tag: String) -> void:
	var pts: Array[Vector3] = []
	for s in (_eco.spawn_report().get("spawned", []) as Array):
		pts.append((s as Dictionary).get("position", Vector3.ZERO))
	var min_sep: float = INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			min_sep = minf(min_sep, pts[i].distance_to(pts[j]))
	_assert("%s_npc_separation" % tag, "≥ %.1f m" % _eco.min_npc_separation, "%.2f m" % min_sep,
		pts.size() < 2 or min_sep >= _eco.min_npc_separation - EPS)


# ---------------------------------------------------------------------------
# C 玩家不计入 NPC 数量
# ---------------------------------------------------------------------------

func _section_c_player_not_counted() -> void:
	print("---- C 玩家不计入 NPC 数量 ----")
	await _fresh_eco_entry()
	if _eco == null or _player == null:
		_assert("C_setup", "非 null", "<null>", false)
		return
	var pid := int(_player.get_instance_id())
	_assert("C1_player_id_not_in_npc_ids", "不含玩家 id", str(_eco.npc_ids().has(pid)), not _eco.npc_ids().has(pid))
	_assert("C1_npc_count_is_2", "2", str(_eco.npc_count()), _eco.npc_count() == 2)
	_assert("C2_player_is_in_animal_group", "true", str(_player.is_in_group(GROUP_ANIMALS)), _player.is_in_group(GROUP_ANIMALS))
	var group_alive := _alive_group_count()
	_assert("C2_group_minus_player_equals_npc_count", "%d（= npc+1）" % (_eco.npc_count() + 1), str(group_alive),
		group_alive == _eco.npc_count() + 1)
	_assert("C3_no_npc_of_player_species", "0", str(_eco.npc_count_of(_cat_id)), _eco.npc_count_of(_cat_id) == 0)
	_assert("C3_player_species_recorded", String(_cat_id), String(_eco.player_species_id()),
		_eco.player_species_id() == _cat_id)

	# C4 连续换 3 次物种：计数精确、不累积、不漂移
	var seq: Array[StringName] = [_mouse_id, _cat_id, _mouse_id, _cat_id]
	var counts: Array[int] = []
	var id_sets: Array = []
	for id in seq:
		await _switch(id)
		counts.append(_eco.npc_count())
		id_sets.append(_eco.npc_ids())
	_assert("C4_counts_exact", "[1, 2, 1, 2]", str(counts), counts == [1, 2, 1, 2])
	var max_count := 0
	for c in counts:
		max_count = maxi(max_count, c)
	_assert("C4_never_exceeds_max_npcs", "≤ %d" % _eco.max_npcs, str(max_count), max_count <= _eco.max_npcs)
	var carry := 0
	for k in range(1, id_sets.size()):
		for i in (id_sets[k] as Array):
			if (id_sets[k - 1] as Array).has(i):
				carry += 1
	_assert("C4_no_id_carryover", "0", str(carry), carry == 0)
	print("MEASURE|c4|counts=%s" % str(counts))


# ---------------------------------------------------------------------------
# D 出生周围无即时攻击
# ---------------------------------------------------------------------------

func _section_d_spawn_safety() -> void:
	print("---- D 出生周围无即时攻击 ----")
	# D1/D3 猫玩家 → 鼠 NPC（非捕食者半径 8 m > 鼠视距）
	await _fresh_eco_entry()
	if _eco == null:
		_assert("D_setup", "非 null", "<null>", false)
		return
	var spawned: Array = _eco.spawn_report().get("spawned", [])
	_assert("D1_spawned_two", "2", str(spawned.size()), spawned.size() == 2)
	var below_need := 0
	var min_prey: float = INF
	for s in spawned:
		var cfg := _cfg_for(StringName((s as Dictionary).get("species", "")))
		var need: float = _eco.min_distance_for(cfg)
		var d := float((s as Dictionary).get("distance", INF))
		min_prey = minf(min_prey, d)
		if d < need - EPS:
			below_need += 1
	_assert("D1_all_above_species_min", "0 违规", str(below_need), below_need == 0)
	_assert("D3_prey_min_distance_8", "≥ 8.00 m", "%.2f m" % min_prey, min_prey >= 8.0 - EPS)
	_assert("D3_prey_min_beats_vision", "> %.2f" % _mouse_cfg.vision_range, "%.2f m" % min_prey,
		min_prey > _mouse_cfg.vision_range)
	_assert("D3_prey_min_distance_equals_threshold", "与报告一致", "%.2f" % min_prey,
		absf(min_prey - _eco.min_spawn_distance_actual()) < EPS)
	print("MEASURE|d_prey|min=%.2f|need=%.2f|vision=%.2f" % [min_prey, _eco.min_spawn_distance, _mouse_cfg.vision_range])

	# D2 鼠玩家 → 猫 NPC（捕食者半径 14 m > 猫视距 9 m）
	await _switch(_mouse_id)
	var sp2: Array = _eco.spawn_report().get("spawned", [])
	_assert("D2_predator_spawned_one", "1", str(sp2.size()), sp2.size() == 1)
	var d_pred := -1.0
	var pred_can_attack := false
	if sp2.size() >= 1:
		d_pred = float((sp2[0] as Dictionary).get("distance", -1.0))
		pred_can_attack = bool((sp2[0] as Dictionary).get("can_attack", false))
	_assert("D2_predator_min_distance_14", "≥ 14.00 m", "%.2f m" % d_pred, d_pred >= 14.0 - EPS)
	_assert("D2_predator_min_beats_vision", "> %.2f" % _cat_cfg.vision_range, "%.2f m" % d_pred,
		d_pred > _cat_cfg.vision_range)
	_assert("D2_predator_flagged_can_attack", "true", str(pred_can_attack), pred_can_attack)
	print("MEASURE|d_pred|d=%.2f|need=%.2f|vision=%.2f" % [d_pred, _eco.predator_min_distance, _cat_cfg.vision_range])

	# D4/D5 行为窗口：刚铺好的 4 s 内 玩家零伤害、零攻击启动、最近距离 ≥ 3 m
	await _fresh_eco_entry()
	await _switch(_mouse_id)
	var hp0: float = _player.survival.state.health
	var reason0 := String(_player.survival.state.last_damage_reason)
	var min_live: float = INF
	var attacks := 0
	var t0 := _now()
	while _now() - t0 < 4.0:
		await physics_frame
		for b in _eco.npc_bodies():
			min_live = minf(min_live, b.global_position.distance_to(_player.global_position))
			if b.attack != null:
				attacks = maxi(attacks, b.attack.attack_count)
	_assert("D4_player_health_unchanged", "%.1f" % hp0, "%.1f" % _player.survival.state.health,
		absf(_player.survival.state.health - hp0) < EPS)
	_assert("D4_player_damage_reason_unchanged", reason0, String(_player.survival.state.last_damage_reason),
		String(_player.survival.state.last_damage_reason) == reason0)
	_assert("D4_no_npc_attack_started", "0", str(attacks), attacks == 0)
	_assert("D5_min_distance_in_window", "≥ 3.00 m", "%.2f m" % min_live, min_live >= 3.0)
	print("MEASURE|d_window|min_live=%.2f|hp=%.1f|attacks=%d" % [min_live, _player.survival.state.health, attacks])

	# D6 拒绝原因可解释（把最远距离压到 3 m → 全被拒，且理由可读）
	var sp := EcologySpawner.new()
	sp.max_spawn_distance = 3.0
	sp.candidates = [_cat_cfg, _mouse_cfg]      # 显式给候选：不依赖目录列举（包里资源会被转成 .res/.remap）
	_level().add_child(sp)
	var rep3 := sp.setup(_player, _player.global_position)
	_assert("D6_all_rejected", "0", str(sp.npc_count()), sp.npc_count() == 0)
	var reasons: Dictionary = rep3.get("skip_reasons", {})
	_assert("D6_reasons_present", "非空", str(reasons), not reasons.is_empty())
	_assert("D6_reason_is_distance_kind", "含 too_far/too_close", str(reasons.keys()),
		reasons.has("too_far") or reasons.has("too_close"))
	_assert("D6_skipped_entries_logged", "≥ 1", str((rep3.get("skipped", []) as Array).size()),
		(rep3.get("skipped", []) as Array).size() >= 1)
	sp.queue_free()
	await _advance(3)


# ---------------------------------------------------------------------------
# E 集成：同一地图两条链
# ---------------------------------------------------------------------------

func _section_e_integration() -> void:
	print("---- E 集成（同一张地图：猫捕鼠 / 鼠避猫）----")
	await _fresh_eco_entry()
	if _eco == null or _player == null:
		_assert("E_setup", "非 null", "<null>", false)
		return
	_assert("E1_level_is_courtyard", LEVEL_PATH, String(_level().scene_file_path),
		String(_level().scene_file_path) == LEVEL_PATH)
	_assert("E1_spawn_markers_shared", "≥ 2", str(_spawn_markers().size()), _spawn_markers().size() >= 2)

	# E4 鼠避猫（猫玩家 → NPC 鼠 主动逃开）
	var prey: AnimalBody = null
	for b in _eco.npc_bodies():
		if b.species_config != null and b.species_config.species_id == _mouse_id:
			prey = b
			break
	_assert("E4_mouse_npc_found", "非 null", str(prey != null), prey != null)
	if prey != null:
		# 玩家放到"鼠自己朝向的前方"1.5 m，并把鼠也转向玩家（双保险）——鼠的视锥必须罩住玩家才会触发逃跑
		_place_player_in_front_of_facing(prey, 1.5)
		prey.look_at(Vector3(_player.global_position.x, prey.global_position.y, _player.global_position.z), Vector3.UP)
		await _advance(4)
		var d0 := prey.global_position.distance_to(_player.global_position)
		var states: Array[String] = []
		var max_d := d0
		var t4 := _now()
		while _now() - t4 < 8.0:
			await physics_frame
			var st := String(prey.ai.state_id()) if prey.ai != null else ""
			if st != "" and not states.has(st):
				states.append(st)
			max_d = maxf(max_d, prey.global_position.distance_to(_player.global_position))
		_assert("E4_npc_mouse_reacts", "含 alert/flee/hidden", str(states),
			states.has("alert") or states.has("flee") or states.has("hidden"))
		_assert("E4_npc_mouse_fled_away", "≥ %.2f m" % (d0 + 1.0), "%.2f m" % max_d, max_d >= d0 + 1.0 - EPS)
		print("MEASURE|e4|d0=%.2f|max_d=%.2f|states=%s" % [d0, max_d, str(states)])

	# E2 猫捕鼠（玩家猫 → 扑击捕获生态里的鼠 NPC）
	var hunted: AnimalBody = null
	for b in _eco.npc_bodies():
		if b.species_config != null and b.species_config.species_id == _mouse_id:
			hunted = b
			break
	_assert("E2_huntable_npc_present", "非 null", str(hunted != null), hunted != null)
	if hunted != null:
		hunted.ai_enabled = false          # 本段只验"生态里的 NPC 能被捕获"；鼠的逃跑链属 T020
		await _advance(3)
		var cap_before := _capture_count()
		var food_before := _food_count()
		var npc_before := _eco.npc_count()
		_place_player_in_front(hunted, 0.9)
		await _advance(4)
		var gap := hunted.global_position.distance_to(_player.global_position)
		_assert("E2_gap_within_pounce", "≤ 1.30 m", "%.2f m" % gap, gap <= 1.30)
		var started := _player.request_pounce()
		_assert("E2_pounce_started", "true", str(started), started)
		var t2 := _now()
		while _now() - t2 < 2.5 and _capture_count() == cap_before:
			await physics_frame
		_assert("E2_capture_ledger_plus_one", "%d" % (cap_before + 1), str(_capture_count()),
			_capture_count() == cap_before + 1)
		_assert("E2_prey_marked_captured", "true", str(hunted.captured), hunted.captured)
		_assert("E2_prey_left_animal_group", "false", str(hunted.is_in_group(GROUP_ANIMALS)),
			not hunted.is_in_group(GROUP_ANIMALS))
		_assert("E2_eco_count_drops_by_one", "%d" % (npc_before - 1), str(_eco.npc_count()),
			_eco.npc_count() == npc_before - 1)
		_assert("E2_capture_food_plus_one", "%d" % (food_before + 1), str(_food_count()),
			_food_count() == food_before + 1)
		print("MEASURE|e2|gap=%.2f|captures=%d|npcs=%d|food=%d" % [
			gap, _capture_count(), _eco.npc_count(), _food_count()])

	# E3 捕食者主动接近（鼠玩家 → NPC 猫），先关攻击只验"接近"
	await _switch(_mouse_id)
	var cat_npc: AnimalBody = null
	for b in _eco.npc_bodies():
		if b.species_config != null and b.species_config.species_id == _cat_id:
			cat_npc = b
			break
	_assert("E3_cat_npc_found", "非 null", str(cat_npc != null), cat_npc != null)
	if cat_npc != null:
		var cai := cat_npc.ai as CatAI
		if cai != null:
			cai.attack_enabled = false
			cai.patrol_enabled = false        # 关巡游：否则它会自己走开、朝向也不受控（实测连走 5.5 s 看不见玩家）
		var layer_cat := int(_entry.call("nav_layer_for", _cat_id))
		var place := _player.global_position + Vector3(0.0, 0.0, -4.0)
		cat_npc.global_position = _snap_on_layer(place, layer_cat)
		cat_npc.velocity = Vector3.ZERO
		await _advance(3)
		cat_npc.look_at(Vector3(_player.global_position.x, cat_npc.global_position.y, _player.global_position.z), Vector3.UP)
		await _advance(3)
		var d3_0 := cat_npc.global_position.distance_to(_player.global_position)
		var states3: Array[String] = []
		var d3_end := d3_0
		var d3_min := d3_0
		var t3 := _now()
		while _now() - t3 < 8.0:
			await physics_frame
			var st := String(cat_npc.ai.state_id()) if cat_npc.ai != null else ""
			if st != "" and not states3.has(st):
				states3.append(st)
			d3_end = cat_npc.global_position.distance_to(_player.global_position)
			d3_min = minf(d3_min, d3_end)
		_assert("E3_predator_reacts", "含 alert/approach/chase", str(states3),
			states3.has("alert") or states3.has("approach") or states3.has("chase"))
		# 判据看**窗口内最小距离**：T023 的 APPROACH 到 0.65 m 后会停住/回落，只看末帧会误判
		_assert("E3_predator_closed_in", "≤ %.2f m" % (d3_0 - 1.0), "%.2f m" % d3_min,
			d3_min <= d3_0 - 1.0 + EPS)
		print("MEASURE|e3|d0=%.2f|d_min=%.2f|d_end=%.2f|states=%s|hp=%.1f" % [
			d3_0, d3_min, d3_end, str(states3), _player.survival.state.health])

		# E3b 近距离会真的打到玩家（短窗：一只猫 NPC 不会秒杀）
		var hp1: float = _player.survival.state.health
		if cai != null:
			cai.attack_enabled = true
		_place_actor_in_front(cat_npc, _player, 0.55)
		var t3b := _now()
		while _now() - t3b < 1.8:
			await physics_frame
		var hp2: float = _player.survival.state.health
		_assert("E3b_player_took_damage", "< %.1f" % hp1, "%.1f" % hp2, hp2 < hp1 - EPS)
		_assert("E3b_player_survived_one_predator", "≥ 30.0（不秒杀）", "%.1f" % hp2, hp2 >= 30.0)
		print("MEASURE|e3b|hp_before=%.1f|hp_after=%.1f" % [hp1, hp2])

	# E1b 两个物种都在同一张地图上（切过物种后仍然是同一关卡路径）
	_assert("E1b_level_same_after_switch", LEVEL_PATH, String(_level().scene_file_path),
		String(_level().scene_file_path) == LEVEL_PATH)


## 把玩家放到目标正前方 `dist` 米并面朝它（同高）
func _place_player_in_front(target: Node3D, dist: float) -> void:
	_place_actor_in_front(_player, target, dist)


## 把玩家放到"目标自己朝向的正前方"`dist` 米（目标的视锥要罩住玩家，感知才会触发）
func _place_player_in_front_of_facing(target: Node3D, dist: float) -> void:
	var fwd := -target.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var pos := target.global_position + fwd * dist
	_player.global_position = Vector3(pos.x, target.global_position.y, pos.z)
	_player.velocity = Vector3.ZERO
	_player.look_at(Vector3(target.global_position.x, _player.global_position.y, target.global_position.z), Vector3.UP)


func _place_actor_in_front(actor: AnimalBody, target: Node3D, dist: float) -> void:
	var to := actor.global_position - target.global_position
	to.y = 0.0
	to = to.normalized() if to.length_squared() > 1e-6 else Vector3.FORWARD
	var pos := target.global_position + to * dist
	actor.global_position = Vector3(pos.x, target.global_position.y, pos.z)
	actor.velocity = Vector3.ZERO
	actor.look_at(Vector3(target.global_position.x, actor.global_position.y, target.global_position.z), Vector3.UP)


# ---------------------------------------------------------------------------
# fixture / 辅助
# ---------------------------------------------------------------------------

func _fresh_eco_entry() -> void:
	await _free_entry()
	_entry = (load(ENTRY) as PackedScene).instantiate() as Node3D
	root.add_child(_entry)
	await _advance(SETTLE)
	_eco = _entry.get("ecology") as EcologySpawner
	_player = _entry.get("player") as AnimalBody
	_cat_cfg = _entry.get("cat_config") as SpeciesConfig
	_mouse_cfg = _entry.get("mouse_config") as SpeciesConfig
	if _cat_cfg != null:
		_cat_id = _cat_cfg.species_id
	if _mouse_cfg != null:
		_mouse_id = _mouse_cfg.species_id


func _free_entry() -> void:
	if _entry != null and is_instance_valid(_entry):
		_entry.queue_free()
	_entry = null
	_eco = null
	_player = null
	await _advance(4)


func _switch(id: StringName) -> void:
	if _entry == null:
		return
	_entry.call("switch_species", id)
	await _advance(SETTLE)
	_player = _entry.get("player") as AnimalBody


func _level() -> Node3D:
	return _entry.get("level") as Node3D if _entry != null else null


func _player_species() -> StringName:
	return _player.species_config.species_id if _player != null and _player.species_config != null else &""


func _cfg_for(id: StringName) -> SpeciesConfig:
	if id == _cat_id:
		return _cat_cfg
	if id == _mouse_id:
		return _mouse_cfg
	return null


func _spawn_markers() -> Array[Node]:
	var out: Array[Node] = []
	for n in get_nodes_in_group(&"spawn_points"):
		out.append(n)
	return out


func _alive_group_count() -> int:
	var n := 0
	for b in get_nodes_in_group(GROUP_ANIMALS):
		var body := b as AnimalBody
		if body != null and is_instance_valid(body) and body.survival != null and not body.survival.is_dead():
			n += 1
	return n


func _capture_count() -> int:
	return int(_wd.get("capture_count")) if _wd != null else -1


func _food_count() -> int:
	return int(_wd.get("capture_food_count")) if _wd != null else -1


func _now() -> float:
	return float(_wd.get("world_time")) if _wd != null else 0.0


func _nav_map() -> RID:
	var lv := _level()
	if lv == null or lv.get_world_3d() == null:
		return RID()
	return lv.get_world_3d().get_navigation_map()


## 按**层**把点吸附到导航面（Godot 4.7.2 的 `map_get_closest_point()` 不带层 → 用 trivial 路径）
func _snap_on_layer(point: Vector3, layer: int) -> Vector3:
	var map := _nav_map()
	if not map.is_valid():
		return point
	var p: PackedVector3Array = NavigationServer3D.map_get_path(
		map, point, point + Vector3(0.05, 0.0, 0.0), true, maxi(1, layer))
	if p.size() >= 1:
		return p[0]
	return Vector3(INF, INF, INF)


func _advance(n: int) -> void:
	for i in n:
		await physics_frame


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	_assert(id, "%.4f ±%.4f" % [expected, eps], "%.4f" % actual, absf(actual - expected) <= eps)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
