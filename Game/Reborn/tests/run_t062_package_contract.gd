extends SceneTree
## T062：**候选版打包契约**（headless 可跑）—— 预设配置 / 运行期卫生 / 作弊入口可达性。
##
## 为什么要有：打包"成功"不等于"干净"。这三类问题只有断言能挡住：
##   ① 预设被改回（`exclude_filter` 丢了 debug 目录、控制台包装又开回来）；
##   ② 运行期脚本里混进**绝对盘符路径/个人目录**（换机器就炸，且会泄露本机路径）；
##   ③ 调试入口（F1~F6 切物种/碰撞线框/导航/调试 HUD/重开）被正式入口可达。
##
## 包内文件清单本身由 `Tools/t043_pck_audit.py`（`--deny scripts/debug/ …`）审计，本套件不重复解析 PCK。
##
## 运行：powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Headless -Script tests/run_t062_package_contract.gd

const PRESETS := "res://export_presets.cfg"
const MAIN_SCENE := "res://scenes/core/main.tscn"
const DEBUG_SCENE := "res://scenes/debug/debug_entry.tscn"
const SCAN_DIRS := ["res://scripts", "res://autoload"]

var _pass := 0
var _fail := 0
var _failed: Array[String] = []


func _initialize() -> void:
	await process_frame
	_check_presets()
	_check_hygiene()
	_check_no_absolute_paths()
	await _check_debug_not_reachable()
	_check_clean_defaults()
	_finish()


# ---------------------------------------------------------------------------
# A：导出预设契约
# ---------------------------------------------------------------------------

func _check_presets() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(PRESETS)
	if not _assert("A0_presets_load", "export_presets.cfg 可读", "%d" % err, err == OK):
		return
	_assert("A1_two_presets", "两个预设", "%s/%s" % [
		str(cfg.has_section("preset.0")), str(cfg.has_section("preset.1"))],
		cfg.has_section("preset.0") and cfg.has_section("preset.1"))

	var name0 := String(cfg.get_value("preset.0", "name", ""))
	var name1 := String(cfg.get_value("preset.1", "name", ""))
	_assert("A2_names", "Windows Desktop / SelfTest", "%s / %s" % [name0, name1],
		name0 == "Windows Desktop" and name1 == "Windows Desktop SelfTest")

	var exclude0 := String(cfg.get_value("preset.0", "exclude_filter", ""))
	var missing: Array[String] = []
	for pattern in ["tests/*", "scripts/debug/*", "scenes/debug/*"]:
		if not exclude0.contains(pattern):
			missing.append(pattern)
	_assert("A3_release_excludes_cheats", "排除 tests + scripts/debug + scenes/debug", exclude0,
		missing.is_empty())

	var exclude1 := String(cfg.get_value("preset.1", "exclude_filter", ""))
	_assert("A4_selftest_keeps_tests", "SelfTest 不排除（要跑包内断言）", "\"%s\"" % exclude1,
		exclude1.strip_edges().is_empty())

	var console0 := int(cfg.get_value("preset.0.options", "debug/export_console_wrapper", -1))
	var console1 := int(cfg.get_value("preset.1.options", "debug/export_console_wrapper", -1))
	_assert("A5_console_wrapper", "发布 0（不弹黑窗）/ SelfTest 2", "%d / %d" % [console0, console1],
		console0 == 0 and console1 == 2)

	var embed0 := bool(cfg.get_value("preset.0.options", "binary_format/embed_pck", true))
	var embed1 := bool(cfg.get_value("preset.1.options", "binary_format/embed_pck", true))
	_assert("A6_embed_pck_false", "两预设都不内嵌 pck（便于审计）", "%s / %s" % [str(embed0), str(embed1)],
		not embed0 and not embed1)

	var arch0 := String(cfg.get_value("preset.0.options", "binary_format/architecture", ""))
	var arch1 := String(cfg.get_value("preset.1.options", "binary_format/architecture", ""))
	_assert("A7_arch_x86_64", "x86_64", "%s / %s" % [arch0, arch1],
		arch0 == "x86_64" and arch1 == "x86_64")

	var mode0 := int(cfg.get_value("preset.0", "script_export_mode", -1))
	var mode1 := int(cfg.get_value("preset.1", "script_export_mode", -1))
	_assert("A8_script_export_mode", "2（编译后的字节码）", "%d / %d" % [mode0, mode1],
		mode0 == 2 and mode1 == 2)

	var prod0 := String(cfg.get_value("preset.0.options", "application/product_name", ""))
	var prod1 := String(cfg.get_value("preset.1.options", "application/product_name", ""))
	_assert("A9_product_names", "Reborn / RebornSelfTest", "%s / %s" % [prod0, prod1],
		prod0 == "Reborn" and prod1 == "RebornSelfTest")


# ---------------------------------------------------------------------------
# B：运行期卫生（作弊开关默认关）
# ---------------------------------------------------------------------------

func _check_hygiene() -> void:
	var main_src := _read("res://scripts/core/main_entry.gd")
	_assert("B1_test_mode_default_false", "@export var test_mode: bool = false",
		"含该声明" if main_src.contains("@export var test_mode: bool = false") else "缺失",
		main_src.contains("@export var test_mode: bool = false"))


	_assert("B2_settings_default_user_path", "user://settings.cfg", GameSettings.DEFAULT_PATH,
		GameSettings.DEFAULT_PATH.begins_with("user://"))

	var sm := root.get_node_or_null("/root/SaveManager")
	var sm_path := String(sm.get("save_path")) if sm != null else "<none>"
	_assert("B3_save_default_user_path", "user://…", sm_path, sm_path.begins_with("user://"))

	# 正式入口不得有任何"作弊/调试"开关被打开
	_assert("B4_no_debug_ecology_in_main", "main_entry 不打开 ecology_enabled",
		"ok" if not main_src.contains("ecology_enabled = true") else "含开启语句",
		not main_src.contains("ecology_enabled = true"))


# ---------------------------------------------------------------------------
# C：运行期脚本里不得有绝对盘符路径（个人配置）
# ---------------------------------------------------------------------------

func _check_no_absolute_paths() -> void:
	var offenders: Array[String] = []
	var scanned := 0
	for dir in SCAN_DIRS:
		scanned += _scan_dir(String(dir), offenders)
	_assert("C1_no_absolute_paths", "scripts/** 与 autoload/** 无 E:\\ / C:\\ / /home/",
		"扫描 %d 个文件，命中 %d" % [scanned, offenders.size()],
		scanned > 0 and offenders.is_empty())
	if not offenders.is_empty():
		print("T062|absolute_path_offenders=%s" % str(offenders.slice(0, 8)))


func _scan_dir(path: String, offenders: Array[String]) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	var count := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		count += 1
		var src := _read(path + "/" + f)
		if src.contains("E:\\") or src.contains("E:/") or src.contains("C:\\") \
				or src.contains("/home/") or src.contains("\\\\Users\\\\"):
			offenders.append(path + "/" + f)
	for sub in dir.get_directories():
		count += _scan_dir(path + "/" + sub, offenders)
	return count


# ---------------------------------------------------------------------------
# D：调试入口不可从正式入口到达
# ---------------------------------------------------------------------------

func _check_debug_not_reachable() -> void:
	_assert("D0_debug_scene_exists_in_source", "开发用调试场景仍在工程里（只是不进发行包）",
		str(FileAccess.file_exists(DEBUG_SCENE)), FileAccess.file_exists(DEBUG_SCENE))

	var packed := load(MAIN_SCENE) as PackedScene
	if not _assert("D1_main_loads", "main.tscn 可加载", str(packed != null), packed != null):
		return
	var entry := packed.instantiate()
	root.add_child(entry)
	for i in 3:
		await process_frame
	var hits: Array[String] = []
	_collect_debug_hits(entry, hits)
	_assert("D2_no_debug_node_in_main", "正式入口树内无 DebugEntry/调试脚本",
		"命中 %d" % hits.size(), hits.is_empty())
	if not hits.is_empty():
		print("T062|debug_hits=%s" % str(hits.slice(0, 8)))
	entry.queue_free()
	await process_frame


func _collect_debug_hits(node: Node, hits: Array[String]) -> void:
	var nm := String(node.name).to_lower()
	if nm.contains("debugentry") or nm.contains("debug_entry"):
		hits.append(String(node.name))
	var script: Variant = node.get_script()
	if script != null:
		var sp := String((script as Script).resource_path)
		if sp.contains("scripts/debug/"):
			hits.append(sp)
	for child in node.get_children():
		_collect_debug_hits(child, hits)


# ---------------------------------------------------------------------------
# E：干净档（缺文件 → 默认值 / 状态 none，不写盘）
# ---------------------------------------------------------------------------

func _check_clean_defaults() -> void:
	var missing := "user://__t062_never_written__.cfg"
	var defaults := GameSettings.load_from(missing)
	_assert("E1_missing_settings_defaults", "volume=1 / hints_seen=0 / 文件未被创建",
		"%.1f / %s / exists=%s" % [float(defaults[GameSettings.KEY_VOLUME]),
			str(GameSettings.as_bool(defaults, GameSettings.KEY_HINTS_SEEN)),
			str(FileAccess.file_exists(missing))],
		absf(float(defaults[GameSettings.KEY_VOLUME]) - 1.0) <= 1e-9
		and not GameSettings.as_bool(defaults, GameSettings.KEY_HINTS_SEEN)
		and not FileAccess.file_exists(missing))

	var sm := root.get_node_or_null("/root/SaveManager")
	if sm == null:
		_assert("E2_save_manager", "SaveManager 存在", "null", false)
		return
	var prev := String(sm.get("save_path"))
	var prev_writes := bool(sm.get("allow_headless_writes"))
	# headless 下 SaveManager 默认拒写（也会把读档判成 `disabled`）；这里显式放开只为读，
	# 判据仍是"缺档 → status=none 且不造档"（结束后不写任何文件）。
	sm.set("allow_headless_writes", true)
	sm.call("set_save_path", "user://__t062_never_saved__/savegame_v1.json")
	var res: Dictionary = sm.call("load_game")
	var created := FileAccess.file_exists("user://__t062_never_saved__/savegame_v1.json")
	sm.call("set_save_path", prev)
	sm.set("allow_headless_writes", prev_writes)
	_assert("E2_missing_save_status_none", "status=none（不崩、不造档）",
		"%s / created=%s" % [String(res.get("status", "")), str(created)],
		String(res.get("status", "")) == "none" and not created)

# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


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
