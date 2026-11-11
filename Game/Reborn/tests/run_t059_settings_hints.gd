extends SceneTree
## T059：**设置与新手提示**（开发计划 :251；策划 v1.1 :136/:329/:65）
##
## 验收词：「灵敏度、FOV、音量、晃动开关；首次提示不堵操作；设置重启保留」。
##
## 判据：
##  A. 设置真源：六个键可读写、**缺键回默认**、坏值夹紧、布尔口径统一；
##  B. 音量真的落到 Master 总线（0 = 静音，不走 `-inf`）；
##  C. 关键声音字幕开关真的改 `SubtitleDirector.enabled`；
##  D. 镜头晃动：**受伤才晃**、可关（关掉后偏移**恒为零**）、约 1 s 内衰减到 0；
##  E. 首次提示：可见、**不堵操作**（不吃鼠标/不抢焦点/不暂停/世界时间照走）、播完落盘、
##     第二次出生与**重启后**都不再显示；
##  F. 菜单侧三个新控件可读可改。
##
## 运行（**零窗口**：GUI exe + `--headless`）：
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Headless `
##       -Script tests/run_t059_settings_hints.gd -TimeoutSec 300

const MAIN_SCENE := "res://scenes/core/main.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CAT_CFG := "res://resources/species/cat.tres"
const TMP_SETTINGS := "user://t059_settings_test.cfg"

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _cfg: SpeciesConfig = null


func _initialize() -> void:
	await process_frame
	_cfg = load(CAT_CFG) as SpeciesConfig
	if not _assert("A0_config", "猫配置可加载", str(_cfg != null), _cfg != null):
		_finish()
		return
	_remove_tmp()
	_check_settings_contract()
	_check_volume()
	await _check_subtitles()
	await _check_camera_shake()
	await _check_hints_standalone()
	await _check_hints_main_entry()
	await _check_menu_settings()
	_remove_tmp()
	_finish()


# ---------------- A：设置真源 ----------------

func _check_settings_contract() -> void:
	var defaults := GameSettings.load_from(TMP_SETTINGS)
	_assert("A1_defaults", "volume=1.0 / shake=1 / subs=1 / hints_seen=0",
		"%.2f/%.0f/%.0f/%.0f" % [
			float(defaults[GameSettings.KEY_VOLUME]), float(defaults[GameSettings.KEY_CAMERA_SHAKE]),
			float(defaults[GameSettings.KEY_SUBTITLES]), float(defaults[GameSettings.KEY_HINTS_SEEN])],
		absf(float(defaults[GameSettings.KEY_VOLUME]) - 1.0) <= 1e-9
		and GameSettings.as_bool(defaults, GameSettings.KEY_CAMERA_SHAKE)
		and GameSettings.as_bool(defaults, GameSettings.KEY_SUBTITLES)
		and not GameSettings.as_bool(defaults, GameSettings.KEY_HINTS_SEEN))

	var written := {
		GameSettings.KEY_SENSITIVITY: 1.75,
		GameSettings.KEY_FOV: 100.0,
		GameSettings.KEY_VOLUME: 0.35,
		GameSettings.KEY_CAMERA_SHAKE: 0.0,
		GameSettings.KEY_SUBTITLES: 0.0,
		GameSettings.KEY_HINTS_SEEN: 1.0,
	}
	var ok := GameSettings.save_to(written, TMP_SETTINGS)
	var back := GameSettings.load_from(TMP_SETTINGS)
	var same := absf(float(back[GameSettings.KEY_SENSITIVITY]) - 1.75) <= 1e-6 \
		and absf(float(back[GameSettings.KEY_FOV]) - 100.0) <= 1e-6 \
		and absf(float(back[GameSettings.KEY_VOLUME]) - 0.35) <= 1e-6 \
		and not GameSettings.as_bool(back, GameSettings.KEY_CAMERA_SHAKE) \
		and not GameSettings.as_bool(back, GameSettings.KEY_SUBTITLES) \
		and GameSettings.as_bool(back, GameSettings.KEY_HINTS_SEEN)
	_assert("A2_roundtrip_persists", "逐键相同（重启即读回）", "saved=%s back=%s" % [str(ok), str(back)], ok and same)

	# 坏值：音量 1.7 → 1.0；-1 → 0；晃动 0.4 → 0；hints 0.7 → 1
	var clamped := GameSettings.sanitize({
		GameSettings.KEY_VOLUME: 1.7,
		GameSettings.KEY_CAMERA_SHAKE: 0.4,
		GameSettings.KEY_SUBTITLES: 0.6,
		GameSettings.KEY_HINTS_SEEN: 0.7,
	})
	_assert("A3_clamp_volume_high", "1.0", "%.3f" % float(clamped[GameSettings.KEY_VOLUME]),
		absf(float(clamped[GameSettings.KEY_VOLUME]) - 1.0) <= 1e-9)
	_assert("A4_bool_floor", "shake=0（0.4 < 0.5）", "%.1f" % float(clamped[GameSettings.KEY_CAMERA_SHAKE]),
		float(clamped[GameSettings.KEY_CAMERA_SHAKE]) == 0.0)
	_assert("A5_bool_ceil", "subs=1 / hints=1（≥0.5）", "%.1f/%.1f" % [
		float(clamped[GameSettings.KEY_SUBTITLES]), float(clamped[GameSettings.KEY_HINTS_SEEN])],
		float(clamped[GameSettings.KEY_SUBTITLES]) == 1.0 and float(clamped[GameSettings.KEY_HINTS_SEEN]) == 1.0)
	_assert("A6_clamp_volume_low", "0.0", "%.3f" % float(GameSettings.sanitize(
		{GameSettings.KEY_VOLUME: -1.0})[GameSettings.KEY_VOLUME]),
		float(GameSettings.sanitize({GameSettings.KEY_VOLUME: -1.0})[GameSettings.KEY_VOLUME]) == 0.0)
	# 老档（只有灵敏度/FOV）必须仍能读，新键回默认
	var legacy := {GameSettings.KEY_SENSITIVITY: 2.0, GameSettings.KEY_FOV: 80.0}
	var legacy_clean := GameSettings.sanitize(legacy)
	_assert("A7_legacy_file_ok", "灵敏度保留 + 新键回默认",
		"%.2f/%.2f" % [float(legacy_clean[GameSettings.KEY_SENSITIVITY]),
			float(legacy_clean[GameSettings.KEY_VOLUME])],
		absf(float(legacy_clean[GameSettings.KEY_SENSITIVITY]) - 2.0) <= 1e-9
		and absf(float(legacy_clean[GameSettings.KEY_VOLUME]) - 1.0) <= 1e-9)
	_assert("A8_as_bool_missing_default", "缺键按默认（字幕=开）",
		str(GameSettings.as_bool({}, GameSettings.KEY_SUBTITLES)),
		GameSettings.as_bool({}, GameSettings.KEY_SUBTITLES))


# ---------------- B：音量 ----------------

func _check_volume() -> void:
	var db_half := SettingsApply.apply_volume(0.5)
	_assert("B1_half_linear_to_db", "%.2f dB" % linear_to_db(0.5), "%.2f dB" % db_half,
		absf(db_half - linear_to_db(0.5)) <= 1e-4)
	_assert("B2_bus_matches", "总线 = 写入值", "%.2f dB" % SettingsApply.master_volume_db(),
		absf(SettingsApply.master_volume_db() - db_half) <= 1e-4)
	_assert("B3_not_muted_at_half", "未静音", str(SettingsApply.master_is_muted()),
		not SettingsApply.master_is_muted())

	var db_zero := SettingsApply.apply_volume(0.0)
	_assert("B4_zero_is_silent", "%.1f dB（不是 -inf）" % SettingsApply.SILENT_DB, "%.1f dB" % db_zero,
		absf(db_zero - SettingsApply.SILENT_DB) <= 1e-6)
	_assert("B5_zero_muted", "mute=true", str(SettingsApply.master_is_muted()),
		SettingsApply.master_is_muted())

	SettingsApply.apply_volume(1.0)
	_assert("B6_full_unmute", "0 dB 且未静音", "%.2f / %s" % [SettingsApply.master_volume_db(),
		str(SettingsApply.master_is_muted())],
		absf(SettingsApply.master_volume_db()) <= 1e-4 and not SettingsApply.master_is_muted())


# ---------------- C：字幕 ----------------

func _check_subtitles() -> void:
	var subs := root.get_node_or_null("/root/SubtitleDirector")
	_assert("C0_subtitle_director", "SubtitleDirector 存在", str(subs != null), subs != null)
	if subs == null:
		return
	var off := SettingsApply.apply_all({
		GameSettings.KEY_VOLUME: 1.0,
		GameSettings.KEY_SUBTITLES: 0.0,
		GameSettings.KEY_CAMERA_SHAKE: 1.0,
	}, self, null)
	_assert("C1_subtitles_off", "enabled=false", "%s（found=%s）" % [
		str(subs.get("enabled")), str(off.get("subtitles_found"))],
		not bool(subs.get("enabled")) and bool(off.get("subtitles_found")))
	var on := SettingsApply.apply_all({
		GameSettings.KEY_VOLUME: 1.0,
		GameSettings.KEY_SUBTITLES: 1.0,
		GameSettings.KEY_CAMERA_SHAKE: 1.0,
	}, self, null)
	_assert("C2_subtitles_on", "enabled=true", "%s / subs=%s" % [str(subs.get("enabled")), str(on.get("subtitles"))],
		bool(subs.get("enabled")) and bool(on.get("subtitles")))
	await process_frame


# ---------------- D：镜头晃动 ----------------

func _check_camera_shake() -> void:
	var body := _make_body()
	await physics_frame
	await physics_frame
	_assert("D0_shake_default_on", "默认开", str(body.camera_shake_enabled), body.camera_shake_enabled)

	body.survival.apply_damage(10.0, &"test")
	_assert("D1_damage_triggers_shake", "振幅 > 0（真实受伤触发，不是手动调）",
		"%.3f" % body.camera_shake_amplitude, body.camera_shake_amplitude > 0.0)
	var off_now := body.camera_shake_offset()
	_assert("D2_offset_nonzero", "偏移 ≠ 0", "%.4f m" % off_now.length(), off_now.length() > 0.0)
	_assert("D3_offset_within_limit", "≤ SHAKE_MAX_OFFSET", "%.4f ≤ %.3f" % [
		off_now.length(), AnimalBody.SHAKE_MAX_OFFSET],
		off_now.length() <= AnimalBody.SHAKE_MAX_OFFSET + 1e-6)

	# 用注入 dt 推进 1 s：必须衰减到 0 且偏移归零
	body.set_process(false)
	var t := 0.0
	while t < 1.0:
		body.advance_camera_shake(0.05)
		t += 0.05
	_assert("D4_decays_to_zero", "1 s 后振幅 = 0", "%.6f" % body.camera_shake_amplitude,
		body.camera_shake_amplitude == 0.0)
	_assert("D5_offset_back_to_zero", "偏移 = (0,0,0)（相机归位）",
		str(body.camera_shake_offset()), body.camera_shake_offset() == Vector3.ZERO)

	# 关掉之后：受伤也不晃、偏移恒零
	body.camera_shake_enabled = false
	body.survival.apply_damage(10.0, &"test")
	_assert("D6_disabled_no_amplitude", "振幅仍 0", "%.6f" % body.camera_shake_amplitude,
		body.camera_shake_amplitude == 0.0)
	body.shake_camera(1.0)
	_assert("D7_disabled_offset_zero", "手动请求也不动", str(body.camera_shake_offset()),
		body.camera_shake_offset() == Vector3.ZERO)

	# 设置层：camera_shake=0 真的写进身体
	var applied := SettingsApply.apply_all({
		GameSettings.KEY_VOLUME: 1.0,
		GameSettings.KEY_SUBTITLES: 1.0,
		GameSettings.KEY_CAMERA_SHAKE: 0.0,
	}, self, body)
	_assert("D8_settings_disable_body", "身体开关被设置关掉", "%s / %s" % [
		str(body.camera_shake_enabled), str(applied.get("camera_shake"))],
		not body.camera_shake_enabled and not bool(applied.get("camera_shake")))
	body.queue_free()
	await process_frame


# ---------------- E1：提示本体（不堵操作） ----------------

func _check_hints_standalone() -> void:
	var hints := FirstRunHints.new()
	hints.line_seconds = 0.5
	hints.set_process(false)          # 测试注入 dt，不吃真实帧率
	root.add_child(hints)
	await process_frame

	_assert("E1_hints_visible", "首帧可见", str(hints.visible), hints.visible)
	_assert("E2_hints_first_line", "第一条是移动键", hints.current_text(),
		hints.current_text().contains("W/A/S/D"))
	_assert("E3_hints_no_extra_lines", "4 条（简短）", "%d" % hints.total_lines(),
		hints.total_lines() == 4)
	_assert("E4_hints_blocks_input", "不抢鼠标/焦点", str(hints.blocks_input()), not hints.blocks_input())
	_assert("E5_hints_no_input_processing", "不处理 unhandled input",
		str(hints.is_processing_unhandled_input()), not hints.is_processing_unhandled_input())
	_assert("E6_hints_tree_not_paused", "不暂停树", str(paused), not paused)

	var finished := [0]
	hints.finished.connect(func() -> void: finished[0] += 1)
	hints.advance(0.5)
	_assert("E7_hints_advances", "第 2 条", "%d / %s" % [hints.line_index(), hints.current_text()],
		hints.line_index() == 1 and hints.current_text().contains("E 交互"))
	# 再推 3 次：最后一条播完即收尾
	hints.advance(0.5)
	hints.advance(0.5)
	_assert("E8_last_line", "第 4 条", "%d" % hints.line_index(), hints.line_index() == 3)
	hints.advance(0.5)
	_assert("E9_finished_once", "finished 恰好 1 次", "%d" % finished[0], finished[0] == 1)
	_assert("E10_hidden_after", "播完隐藏", str(hints.visible), not hints.visible)
	hints.advance(0.5)
	_assert("E11_finished_idempotent", "再推也不重复发", "%d" % finished[0], finished[0] == 1)
	hints.queue_free()
	await process_frame


# ---------------- E2：真实入口里首次显示 + 落盘 + 重启不再显示 ----------------

func _check_hints_main_entry() -> void:
	# 清掉 A 组留下的 `hints_seen=1`：本组要的"首次"必须自己造（不然测的是"已看过"路径）
	_remove_tmp()
	var first := await _spawn_entry()
	if first == null:
		_assert("E12_entry_spawn", "首次实例化并出生", "null", false)
		return
	var hints: Node = first.get("first_run_hints")
	_assert("E12_entry_hints_shown", "首次出生显示提示", str(hints != null), hints != null)
	if hints != null:
		_assert("E13_entry_hints_non_blocking", "提示不堵操作（真实入口）",
			"%s / paused=%s" % [str(hints.call("blocks_input")), str(paused)],
			not bool(hints.call("blocks_input")) and not paused)
		_assert("E14_world_time_advancing", "世界时间照走（提示不冻结时间）",
			"%.3f" % float(_wd_time()), float(_wd_time()) > 0.0)
		hints.call("finish_now")
		await process_frame
		var after := GameSettings.load_from(TMP_SETTINGS)
		_assert("E15_hints_seen_persisted", "hints_seen=1 已落盘",
			"%.0f" % float(after[GameSettings.KEY_HINTS_SEEN]),
			GameSettings.as_bool(after, GameSettings.KEY_HINTS_SEEN))
		_assert("E16_entry_flag", "MainEntry.hints_seen=true", str(first.get("hints_seen")),
			bool(first.get("hints_seen")))
		# 造一个"非默认但已持久化"的音量，用来验证重启后设置被读回（E19）
		var persisted := GameSettings.load_from(TMP_SETTINGS)
		persisted[GameSettings.KEY_VOLUME] = 0.35
		GameSettings.save_to(persisted, TMP_SETTINGS)
	_assert("E17_no_leftover_node", "提示节点已释放", str(first.get("first_run_hints") == null),
		first.get("first_run_hints") == null)

	first.queue_free()
	await process_frame
	await process_frame

	# "重启"：同一份 settings 文件下重新实例化 → 不再显示
	var second := await _spawn_entry()
	if second == null:
		_assert("E18_restart_spawn", "再次实例化并出生", "null", false)
		return
	_assert("E18_restart_no_hints", "重启后不再显示提示", str(second.get("first_run_hints")),
		second.get("first_run_hints") == null)
	_assert("E19_restart_settings_kept", "设置也读回来了（volume 仍为写入值）",
		"%.2f" % float(second.get("volume_level")),
		absf(float(second.get("volume_level")) - 0.35) <= 1e-6)
	second.queue_free()
	await process_frame


## 用临时设置文件实例化 `main.tscn` 并出生第一个物种（test_mode，不写存档）
func _spawn_entry() -> Node:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		return null
	var entry := packed.instantiate()
	entry.set("settings_path", TMP_SETTINGS)
	entry.set("test_mode", true)
	entry.call("set_persistence_enabled", false)
	root.add_child(entry)
	for i in 6:
		await process_frame
	var configs: Array = entry.call("species_configs")
	if configs.is_empty():
		return null
	var id: StringName = (configs[0] as SpeciesConfig).species_id
	entry.call("select_species", id)
	for i in 6:
		await process_frame
	return entry


func _wd_time() -> float:
	var wd := root.get_node_or_null("/root/WorldDirector")
	return float(wd.get("world_time")) if wd != null else -1.0


# ---------------- F：菜单侧三个新控件 ----------------

func _check_menu_settings() -> void:
	var menu := MainMenu.new()
	root.add_child(menu)
	await process_frame
	menu.build([_cfg], {
		GameSettings.KEY_SENSITIVITY: 1.0,
		GameSettings.KEY_FOV: 0.0,
		GameSettings.KEY_VOLUME: 0.35,
		GameSettings.KEY_CAMERA_SHAKE: 0.0,
		GameSettings.KEY_SUBTITLES: 1.0,
	}, [&"Cat"])
	await process_frame
	var values := menu.settings_values()
	var keys := [GameSettings.KEY_VOLUME, GameSettings.KEY_CAMERA_SHAKE, GameSettings.KEY_SUBTITLES]
	var missing: Array[String] = []
	for k in keys:
		if not values.has(k):
			missing.append(String(k))
	_assert("F1_menu_has_new_controls", "volume/camera_shake/subtitles", str(values.keys()), missing.is_empty())
	_assert("F2_menu_backfills_saved", "volume 从 0.35 回填、晃动 0（关）",
		"%.2f / %.1f" % [float(values.get(GameSettings.KEY_VOLUME, -1.0)),
			float(values.get(GameSettings.KEY_CAMERA_SHAKE, -1.0))],
		absf(float(values.get(GameSettings.KEY_VOLUME, -1.0)) - 0.35) <= 1e-6
		and float(values.get(GameSettings.KEY_CAMERA_SHAKE, -1.0)) == 0.0)

	var emitted := []
	menu.setting_changed.connect(func(key: StringName, value: float) -> void:
		emitted.append("%s=%.2f" % [String(key), value]))
	menu.set_setting(GameSettings.KEY_VOLUME, 0.8)
	menu.set_setting(GameSettings.KEY_CAMERA_SHAKE, 1.0)
	_assert("F3_menu_emits_changes", "两次 setting_changed", str(emitted), emitted.size() == 2)
	_assert("F4_menu_values_updated", "滑块值同步", "%.2f / %.1f" % [
		float((menu.settings_values())[GameSettings.KEY_VOLUME]),
		float((menu.settings_values())[GameSettings.KEY_CAMERA_SHAKE])],
		absf(float((menu.settings_values())[GameSettings.KEY_VOLUME]) - 0.8) <= 1e-6
		and float((menu.settings_values())[GameSettings.KEY_CAMERA_SHAKE]) == 1.0)
	menu.queue_free()
	await process_frame


# ---------------- 夹具 / 工具 ----------------

func _make_body() -> AnimalBody:
	var packed := load(BODY_SCENE) as PackedScene
	var body := packed.instantiate() as AnimalBody
	body.name = "T059Body"
	body.species_config = _cfg
	body.player_controlled = false
	body.make_camera_current = false
	root.add_child(body)
	return body


func _remove_tmp() -> void:
	var abs_path := ProjectSettings.globalize_path(TMP_SETTINGS)
	if FileAccess.file_exists(TMP_SETTINGS):
		DirAccess.remove_absolute(abs_path)


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
