extends SceneTree
## T054：**导入与替换回归** —— 动物与环境资产换新之后，动画接线、碰撞与数值契约仍成立。
##
## 开发计划 :222「两种动物及环境导入，动画蓝图/碰撞校验；P1/P2/P3 路线与战斗仍通过」。
## 引擎已定 Godot（UE5 路线废止），所以"动画蓝图"对应 `AnimalPlayer` 的片段表与
## `AnimalBody` 的切换口径，"碰撞校验"对应胶囊与 GLB 内建碰撞。
##
## 判据：
##  A. **片段表**：猫 4 段（`AttackCue` 一次性 + 3 段循环）、鼠 4 段（`Eat` 一次性 + 3 段循环），
##     片段非空、轨道数 > 0；缺一段或循环模式漂移即红灯。
##  B. **碰撞**：胶囊半径/高度 = `SpeciesConfig`（猫 0.16/0.48、鼠 0.06/0.18）；
##     视觉替换后**胶囊代理不变**（T009/T013 的 `mesh == capsule` 契约）；视觉节点内 0 碰撞。
##  C. **导入完整性**：`assets/characters` 下每个 `.glb` 都能加载且带 `.import`；
##     视觉场景里的材质/贴图都能解析（贴图缺失在替换回归里最容易漏）。
##  D. **数值契约**：换资产不得动玩法数值（猫 0.45/1.2/35/0.65、鼠 `can_attack=false` 且五项为 0）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t054_import_regression.gd' --quit-after 60000
## 结果口径：RESULT|pass=<n>|fail=<n>|failed=...

const CAT_CFG := "res://resources/species/cat.tres"
const MOUSE_CFG := "res://resources/species/mouse.tres"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CHAR_DIR := "res://assets/characters"

const CAT_CLIPS := ["AttackCue", "Idle", "Run", "Walk"]
const MOUSE_CLIPS := ["Eat", "Idle", "Run", "Walk"]
const ONESHOT := ["AttackCue", "Eat"]

var _pass := 0
var _fail := 0
var _failed: Array[String] = []


func _initialize() -> void:
	var cat := load(CAT_CFG) as SpeciesConfig
	var mouse := load(MOUSE_CFG) as SpeciesConfig
	if not _assert("A0_configs_load", "SpeciesConfig×2", "%s/%s" % [cat != null, mouse != null],
			cat != null and mouse != null):
		_finish()
		return

	await _check_clips("cat", cat, CAT_CLIPS)
	await _check_clips("mouse", mouse, MOUSE_CLIPS)
	await _check_body("cat", cat, 0.16, 0.48)
	await _check_body("mouse", mouse, 0.06, 0.18)
	_check_species_numbers(cat, mouse)
	_check_imports()
	_finish()


# ---------------- A：片段表 ----------------

func _check_clips(tag: String, cfg: SpeciesConfig, want: Array) -> void:
	var packed := cfg.visual_scene
	if not _assert("A_%s_visual_scene" % tag, "PackedScene", str(packed != null), packed != null):
		return
	var inst := packed.instantiate() as Node3D
	root.add_child(inst)
	await process_frame
	var ap := _find_animation_player(inst)
	if not _assert("A_%s_animation_player" % tag, "AnimationPlayer", str(ap != null), ap != null):
		inst.queue_free()
		return
	var names := ap.get_animation_list()
	var missing: Array[String] = []
	for clip in want:
		if not names.has(StringName(clip)):
			missing.append(String(clip))
	_assert("A_%s_clip_set" % tag, str(want), "%s" % [names], missing.is_empty())

	for clip in want:
		var anim := ap.get_animation(StringName(clip))
		if anim == null:
			continue
		# 资产层：glTF 导入一律 `LOOP_NONE`（循环由运行时决定）。第一版在这里断言 LOOP_LINEAR，
		# 6 条假红——循环模式是 `AnimalBody._bind_visual_animation()` 改的，不在资产里。
		_assert("A_%s_asset_loop_none_%s" % [tag, clip], "0 (LOOP_NONE)", str(anim.loop_mode),
			anim.loop_mode == Animation.LOOP_NONE)
		_assert("A_%s_tracks_%s" % [tag, clip], "≥ 1 轨", str(anim.get_track_count()),
			anim.get_track_count() >= 1)
	_assert("A_%s_materials_resolve" % tag, "0 个缺失材质", str(_missing_material_count(inst)),
		_missing_material_count(inst) == 0)
	inst.queue_free()
	await process_frame


# ---------------- B：碰撞 ----------------

func _check_body(tag: String, cfg: SpeciesConfig, want_r: float, want_h: float) -> void:
	var body := (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.ai_enabled = false
	body.player_controlled = false
	root.add_child(body)
	await physics_frame
	await physics_frame
	var st := body.debug_state()
	_assert("B_%s_capsule_radius" % tag, "%.2f" % want_r, "%.3f" % float(st["capsule_radius"]),
		absf(float(st["capsule_radius"]) - want_r) <= 1e-3)
	_assert("B_%s_capsule_height" % tag, "%.2f" % want_h, "%.3f" % float(st["capsule_height"]),
		absf(float(st["capsule_height"]) - want_h) <= 1e-3)
	# T009/T013 契约：视觉换真人模型后，隐藏的胶囊代理尺寸不变
	_assert("B_%s_proxy_mesh_matches" % tag, "mesh r=%.2f h=%.2f" % [want_r, want_h],
		"r=%.3f h=%.3f" % [float(st["mesh_radius"]), float(st["mesh_height"])],
		absf(float(st["mesh_radius"]) - want_r) <= 1e-3 and absf(float(st["mesh_height"]) - want_h) <= 1e-3)
	_assert("B_%s_visual_binds_anim" % tag, "true", str(body.visual_anim_active), body.visual_anim_active)
	# 运行时绑定：三段循环片段被改成 LOOP_LINEAR，一次性片段保持 LOOP_NONE
	for clip in ["Idle", "Walk", "Run"]:
		var ca := body.visual_anim.get_animation(StringName(clip)) if body.visual_anim != null else null
		_assert("B_%s_runtime_loop_%s" % [tag, clip], "1 (LOOP_LINEAR)",
			str(ca.loop_mode) if ca != null else "<missing>",
			ca != null and ca.loop_mode == Animation.LOOP_LINEAR)
	var oneshot := "AttackCue" if tag == "cat" else "Eat"
	var oa := body.visual_anim.get_animation(StringName(oneshot)) if body.visual_anim != null else null
	_assert("B_%s_runtime_oneshot_%s" % [tag, oneshot], "0 (LOOP_NONE)",
		str(oa.loop_mode) if oa != null else "<missing>",
		oa != null and oa.loop_mode == Animation.LOOP_NONE)
	var visual_cols := _collision_count(body.visual_root) if body.visual_root != null else 0
	_assert("B_%s_visual_has_no_collision" % tag, "0", str(visual_cols), visual_cols == 0)
	body.queue_free()
	await physics_frame


# ---------------- C：导入完整性 ----------------

func _check_imports() -> void:
	var dir := DirAccess.open(CHAR_DIR)
	if not _assert("C_char_dir", "可打开", CHAR_DIR, dir != null):
		return
	var total := 0
	var broken: Array[String] = []
	for sub in _subdirs(dir):
		var d := DirAccess.open(CHAR_DIR.path_join(sub))
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".glb"):
				continue
			total += 1
			var full := CHAR_DIR.path_join(sub).path_join(f)
			if load(full) == null:
				broken.append(f)
			elif not FileAccess.file_exists(full + ".import"):
				broken.append(f + "(无.import)")
	# 2026-11-10 清理：Game 内只保留**在役**视觉资产（猫 `sm_cat_006`、鼠 `sm_mouse_002`），
	# 退役的 sm_cat_001/002/004/005 已删（仍可在 Art/Exports 与 git 历史里查到）。
	# 阈值因此从 6 收到 2——断言的本意是"每个物种的视觉资产都在册且可加载"，不是"文件越多越好"。
	_assert("C_glb_count", "≥ 2（在役资产）", str(total), total >= 2)
	_assert("C_glb_all_loadable", "0 个损坏", "%s" % [broken], broken.is_empty())

	# 被物种引用的视觉场景必须能实例化（外部贴图缺失会在这里炸）
	for pair in [["cat", CAT_CFG], ["mouse", MOUSE_CFG]]:
		var cfg := load(pair[1]) as SpeciesConfig
		var inst := cfg.visual_scene.instantiate()
		root.add_child(inst)
		await process_frame
		_assert("C_visual_instantiates_%s" % pair[0], "节点数 ≥ 2", str(inst.get_child_count()),
			inst.get_child_count() >= 2)
		inst.queue_free()
		await process_frame


# ---------------- D：数值契约 ----------------

func _check_species_numbers(cat: SpeciesConfig, mouse: SpeciesConfig) -> void:
	_assert("D_cat_telegraph", "0.45", "%.3f" % cat.attack_telegraph, absf(cat.attack_telegraph - 0.45) <= 1e-3)
	_assert("D_cat_recovery", "1.20", "%.3f" % cat.attack_recovery, absf(cat.attack_recovery - 1.2) <= 1e-3)
	_assert("D_cat_damage", "35", "%.1f" % cat.attack_damage, absf(cat.attack_damage - 35.0) <= 1e-3)
	_assert("D_cat_range", "0.65", "%.3f" % cat.attack_range, absf(cat.attack_range - 0.65) <= 1e-3)
	_assert("D_cat_speeds", "1.8 / 4.5", "%.2f / %.2f" % [cat.walk_speed, cat.sprint_speed],
		absf(cat.walk_speed - 1.8) <= 1e-3 and absf(cat.sprint_speed - 4.5) <= 1e-3)
	_assert("D_mouse_no_attack", "false 且五项为 0", "can_attack=%s" % mouse.can_attack,
		not mouse.can_attack and absf(mouse.attack_damage) <= 1e-6 and absf(mouse.attack_telegraph) <= 1e-6
			and absf(mouse.attack_recovery) <= 1e-6 and absf(mouse.attack_range) <= 1e-6
			and absf(mouse.attack_facing_half_angle_deg) <= 1e-6)
	_assert("D_mouse_speeds", "1.1 / 3.0", "%.2f / %.2f" % [mouse.walk_speed, mouse.sprint_speed],
		absf(mouse.walk_speed - 1.1) <= 1e-3 and absf(mouse.sprint_speed - 3.0) <= 1e-3)


# ---------------- 工具 ----------------

func _subdirs(dir: DirAccess) -> Array[String]:
	var out: Array[String] = []
	for d in dir.get_directories():
		out.append(String(d))
	return out


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_animation_player(c)
		if r != null:
			return r
	return null


func _missing_material_count(n: Node) -> int:
	var count := 0
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				if mat == null:
					count += 1
				elif mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					if bm.albedo_texture == null and bm.albedo_color == Color.BLACK:
						count += 1
	for c in n.get_children():
		count += _missing_material_count(c)
	return count


func _collision_count(n: Node) -> int:
	var count := 1 if (n is CollisionShape3D or n is CollisionPolygon3D) else 0
	for c in n.get_children():
		count += _collision_count(c)
	return count


func _assert(tag: String, expected: String, actual: String, ok: bool) -> bool:
	if ok:
		_pass += 1
		print("ASSERT|%s|%s|%s|PASS" % [tag, expected, actual])
	else:
		_fail += 1
		_failed.append(tag)
		print("ASSERT|%s|%s|%s|FAIL" % [tag, expected, actual])
	return ok


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_pass + _fail, _fail])
	if _fail == 0:
		print("RESULT|pass=%d|fail=0|failed=" % _pass)
		quit(0)
	else:
		print("RESULT|pass=%d|fail=%d|failed=%s" % [_pass, _fail, "|".join(_failed)])
		quit(1)
