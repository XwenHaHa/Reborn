extends SceneTree
## ART05 设置持久化断言（`GameSettings` + `MainEntry` + 菜单滑块的闭环）
##
## 覆盖：
##   S1 文件不存在 → 默认值（1.00× / 不覆盖 FOV），不崩、不写垃圾
##   S2 写→读往返：{2.00×, 80°} 原样回来
##   S3 越界夹紧：{99×, 5°} → {3.00×, 60°}
##   S4 文件损坏 → 回落默认值
##   S5 正式入口：开机读盘 → 菜单滑块回填 → 改设置立刻落盘
##   S6 出生后设置**真的生效**：玩家相机 fov = 存盘 FOV、鼠标灵敏度 = 基准 × 倍数
##   S7 "重启"（第二个 MainEntry 实例）读到的是上次存的值
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_art05_settings.gd' --quit-after 30000

const MAIN := "res://scenes/core/main.tscn"
const TMP := "user://art05_settings_test.cfg"
const EPS := 1e-4

var _checks := 0
var _fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_remove(TMP)

	# --- S1 缺文件 → 默认 ---
	var defaults := GameSettings.load_from(TMP)
	_check("S1_missing_file_sensitivity", "1.00", "%.2f" % float(defaults[GameSettings.KEY_SENSITIVITY]),
		absf(float(defaults[GameSettings.KEY_SENSITIVITY]) - GameSettings.DEFAULT_SENSITIVITY) < EPS)
	_check("S1_missing_file_fov", "0（不覆盖）", "%.1f" % float(defaults[GameSettings.KEY_FOV]),
		absf(float(defaults[GameSettings.KEY_FOV]) - GameSettings.DEFAULT_FOV) < EPS)
	_check("S1_no_file_created", "false", str(FileAccess.file_exists(TMP)),
		not FileAccess.file_exists(TMP))

	# --- S2 往返 ---
	var saved := GameSettings.save_to({
		GameSettings.KEY_SENSITIVITY: 2.0,
		GameSettings.KEY_FOV: 80.0,
	}, TMP)
	_check("S2_save_ok", "true", str(saved), saved)
	_check("S2_file_created", "true", str(FileAccess.file_exists(TMP)),
		FileAccess.file_exists(TMP))
	var loaded := GameSettings.load_from(TMP)
	_check("S2_roundtrip_sensitivity", "2.00", "%.2f" % float(loaded[GameSettings.KEY_SENSITIVITY]),
		absf(float(loaded[GameSettings.KEY_SENSITIVITY]) - 2.0) < EPS)
	_check("S2_roundtrip_fov", "80.0", "%.1f" % float(loaded[GameSettings.KEY_FOV]),
		absf(float(loaded[GameSettings.KEY_FOV]) - 80.0) < EPS)

	# --- S3 夹紧 ---
	GameSettings.save_to({GameSettings.KEY_SENSITIVITY: 99.0, GameSettings.KEY_FOV: 5.0}, TMP)
	var clamped := GameSettings.load_from(TMP)
	_check("S3_sensitivity_clamped", "3.00", "%.2f" % float(clamped[GameSettings.KEY_SENSITIVITY]),
		absf(float(clamped[GameSettings.KEY_SENSITIVITY]) - GameSettings.SENSITIVITY_MAX) < EPS)
	_check("S3_fov_clamped", "60.0", "%.1f" % float(clamped[GameSettings.KEY_FOV]),
		absf(float(clamped[GameSettings.KEY_FOV]) - GameSettings.FOV_MIN) < EPS)

	# --- S4 损坏文件 → 默认 ---
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	if f != null:
		f.store_string("这不是配置文件\n[乱七八糟\n===\n")
		f.close()
	var broken := GameSettings.load_from(TMP)
	_check("S4_corrupt_defaults", "1.00/0.0", "%.2f/%.1f" % [
		float(broken[GameSettings.KEY_SENSITIVITY]), float(broken[GameSettings.KEY_FOV])],
		absf(float(broken[GameSettings.KEY_SENSITIVITY]) - GameSettings.DEFAULT_SENSITIVITY) < EPS
			and absf(float(broken[GameSettings.KEY_FOV]) - GameSettings.DEFAULT_FOV) < EPS)

	# --- S5/S6：正式入口读盘 → 回填 → 改设置 → 落盘 → 出生后生效 ---
	GameSettings.save_to({GameSettings.KEY_SENSITIVITY: 2.0, GameSettings.KEY_FOV: 80.0}, TMP)
	var entry := await _new_entry()
	if entry == null:
		_finish()
		return
	_check("S5_entry_reads_sensitivity", "2.00", "%.2f" % entry.sensitivity_scale,
		absf(entry.sensitivity_scale - 2.0) < EPS)
	_check("S5_entry_reads_fov", "80.0", "%.1f" % entry.fov_override,
		absf(entry.fov_override - 80.0) < EPS)
	var shown := entry.menu.settings_values()
	_check("S5_menu_slider_sensitivity", "2.00",
		"%.2f" % float(shown.get(GameSettings.KEY_SENSITIVITY, -1.0)),
		absf(float(shown.get(GameSettings.KEY_SENSITIVITY, -1.0)) - 2.0) < EPS)
	_check("S5_menu_slider_fov", "80", "%.0f" % float(shown.get(GameSettings.KEY_FOV, -1.0)),
		absf(float(shown.get(GameSettings.KEY_FOV, -1.0)) - 80.0) < EPS)

	# 改设置（走菜单滑块 → 信号 → 落盘）
	entry.menu.set_setting(GameSettings.KEY_SENSITIVITY, 1.5)
	entry.menu.set_setting(GameSettings.KEY_FOV, 100.0)
	await process_frame
	await process_frame
	var after := GameSettings.load_from(TMP)
	_check("S5_change_persisted_sensitivity", "1.50",
		"%.2f" % float(after[GameSettings.KEY_SENSITIVITY]),
		absf(float(after[GameSettings.KEY_SENSITIVITY]) - 1.5) < EPS)
	_check("S5_change_persisted_fov", "100.0", "%.1f" % float(after[GameSettings.KEY_FOV]),
		absf(float(after[GameSettings.KEY_FOV]) - 100.0) < EPS)

	# 出生 → 设置真的落到玩家身上
	var configs := entry.species_configs()
	entry.select_species(configs[0].species_id)
	for i in 10:
		await process_frame
	_check("S6_player_spawned", "alive", entry.lifecycle_state_name(),
		entry.lifecycle_state_name() == "alive")
	if entry.player != null and entry.player.camera != null:
		_check("S6_player_fov_applied", "100.0", "%.1f" % entry.player.camera.fov,
			absf(entry.player.camera.fov - 100.0) < EPS)
		var want := MainMenu.SENSITIVITY_BASE * 1.5
		_check("S6_player_sensitivity_applied", "%.5f" % want,
			"%.5f" % entry.player.mouse_sensitivity,
			absf(entry.player.mouse_sensitivity - want) < 1e-6)
	else:
		_check("S6_player_exists", "非 null", "<null>", false)

	# --- S7 "重启"：第二个实例读到上次的值 ---
	entry.queue_free()
	for i in 6:
		await process_frame
	var entry2 := await _new_entry()
	if entry2 != null:
		_check("S7_restart_reads_saved", "1.50", "%.2f" % entry2.sensitivity_scale,
			absf(entry2.sensitivity_scale - 1.5) < EPS)
		entry2.queue_free()
		for i in 4:
			await process_frame

	_remove(TMP)
	_finish()


func _new_entry() -> MainEntry:
	var packed: PackedScene = load(MAIN)
	if packed == null:
		_check("entry_main_loads", "PackedScene", "<null>", false)
		return null
	var main := packed.instantiate()
	if not (main is MainEntry):
		_check("entry_is_main_entry", "MainEntry", main.get_class(), false)
		main.queue_free()
		return null
	(main as MainEntry).settings_path = TMP
	root.add_child(main)
	for i in 10:
		await process_frame
	return main as MainEntry


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])
