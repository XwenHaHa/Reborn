extends SceneTree
## T057：**简化昼夜光照**（开发计划 :249）。
##
## 验收词：「光照跟世界时间变化，**存档恢复正确**；**夜间可读**，必要感知差异可调」。
##
## 判据：
##  A. **纯函数曲线**：采样只由世界时间决定；日出/正午/日落/午夜四个点有明确数值；
##     昼→夜单调、周期性（t 与 t+1200 逐字段相同）；
##  B. **真的写进场景**：`SunLight` 的旋转/能量/颜色与 `WorldEnvironment` 的环境光跟着变；
##  C. **存档恢复正确**：光照是"按当前时间重算"的**无状态**量 —— 来回切时间后回到同一时刻，
##     逐字段完全一致（不需要额外的"快进到正确相位"代码）；
##  D. **夜间可读**：夜间环境光有硬下界（`NIGHT_AMBIENT_FLOOR`），月光是冷色（`b > r`）；
##  E. **必要感知差异可调**：`night_sight_multiplier` 旋钮存在且默认 1.0（默认不改玩法）；
##  F. 与 T034 昼夜口径一致：`WorldDirector.is_daytime()` 与采样 `is_day` 一致（互补于夜晚）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t057_day_night.gd' --quit-after 60000
## 结果口径：RESULT|pass=<n>|fail=<n>|failed=...

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const DAY_NIGHT := preload("res://scripts/systems/day_night.gd")

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _dn: Node = null
var _wd: Node = null
var _level: Node3D = null
var _sun: DirectionalLight3D = null
var _env: Environment = null


func _initialize() -> void:
	await process_frame
	_dn = root.get_node_or_null("/root/DayNightDirector")
	_wd = root.get_node_or_null("/root/WorldDirector")
	if not _assert("A0_autoloads", "DayNightDirector + WorldDirector",
			"%s/%s" % [_dn != null, _wd != null], _dn != null and _wd != null):
		_finish()
		return
	_check_curve()
	await _check_apply()
	_check_restore_is_stateless()
	_check_night_readable()
	_check_knob()
	_check_matches_world_clock()
	_finish()


# ---------------- A：纯函数曲线 ----------------

func _check_curve() -> void:
	var sunrise: Dictionary = DAY_NIGHT.sample(0.0, 1200.0)
	var noon: Dictionary = DAY_NIGHT.sample(300.0, 1200.0)
	var dusk: Dictionary = DAY_NIGHT.sample(600.0, 1200.0)
	var midnight: Dictionary = DAY_NIGHT.sample(900.0, 1200.0)

	_assert("A_sunrise_elevation", "0.0°", "%.2f°" % sunrise["elevation_deg"],
		absf(float(sunrise["elevation_deg"])) <= 0.01)
	_assert("A_noon_elevation", "70.0°", "%.2f°" % noon["elevation_deg"],
		absf(float(noon["elevation_deg"]) - 70.0) <= 0.01)
	_assert("A_dusk_is_night", "false", str(dusk["is_day"]), not bool(dusk["is_day"]))
	_assert("A_midnight_elevation", "-70.0°", "%.2f°" % midnight["elevation_deg"],
		absf(float(midnight["elevation_deg"]) + 70.0) <= 0.01)
	_assert("A_noon_brighter_than_night", "noon > night", "%.3f > %.3f" % [noon["energy"], midnight["energy"]],
		float(noon["energy"]) > float(midnight["energy"]))
	_assert("A_noon_energy", "1.30", "%.3f" % noon["energy"], absf(float(noon["energy"]) - 1.30) <= 1e-3)
	_assert("A_day_energy_above_night", "日出 > 午夜", "%.3f > %.3f" % [sunrise["energy"], midnight["energy"]],
		float(sunrise["energy"]) > float(midnight["energy"]))

	# 周期性：同相位必然同值（光照不该有"越玩越亮/越暗"的漂移）
	var same := true
	var detail: Array[String] = []
	for k in ["elevation_deg", "energy", "ambient", "phase"]:
		var a: float = float(noon[k])
		var b: float = float(DAY_NIGHT.sample(1500.0, 1200.0)[k])
		var c: float = float(DAY_NIGHT.sample(2700.0, 1200.0)[k])
		detail.append("%s=%.4f/%.4f/%.4f" % [k, a, b, c])
		if absf(a - b) > 1e-6 or absf(a - c) > 1e-6:
			same = false
	_assert("A_periodic_1200s", "t / t+1200 / t+2400 相同", " ".join(detail), same)


# ---------------- B：真的写进场景 ----------------

func _check_apply() -> void:
	_level = (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(_level)
	await process_frame
	var bound: bool = bool(_dn.call("bind_level", _level))
	_sun = _level.get_node_or_null("SunLight") as DirectionalLight3D
	var we := _level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_env = we.environment if we != null else null
	_assert("B_bind_level", "true", str(bound), bound)
	_assert("B_sun_present", "DirectionalLight3D", str(_sun != null), _sun != null)
	_assert("B_environment_present", "Environment", str(_env != null), _env != null)
	if _sun == null or _env == null:
		return

	_wd.call("set_world_time", 300.0)
	var noon: Dictionary = _dn.call("apply_now")
	_assert("B_noon_energy_written", "%.3f" % noon["energy"], "%.3f" % _sun.light_energy,
		absf(_sun.light_energy - float(noon["energy"])) <= 1e-3)
	_assert("B_noon_rotation_written", "-70.0°", "%.2f°" % _sun.rotation_degrees.x,
		absf(_sun.rotation_degrees.x + 70.0) <= 0.01)
	_assert("B_noon_ambient_written", "%.3f" % noon["ambient"], "%.3f" % _env.ambient_light_energy,
		absf(_env.ambient_light_energy - float(noon["ambient"])) <= 1e-3)
	# 白天必须保持工程现场：SKY 源 + 天空倍率 1.0（T057 修正不得改白天一帧）
	_assert("B_noon_ambient_source_sky", "%d" % Environment.AMBIENT_SOURCE_SKY,
		"%d" % _env.ambient_light_source, _env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY)
	_assert("B_noon_sky_energy_untouched", "1.000", "%.3f" % _sky_energy(),
		absf(_sky_energy() - 1.0) <= 1e-3)
	print("MEASURE|noon|elev=%.2f|energy=%.3f|ambient=%.3f|color=(%.2f,%.2f,%.2f)" % [
		_sun.rotation_degrees.x, _sun.light_energy, _env.ambient_light_energy,
		_sun.light_color.r, _sun.light_color.g, _sun.light_color.b])

	_wd.call("set_world_time", 900.0)
	var night: Dictionary = _dn.call("apply_now")
	_assert("B_night_energy_written", "%.3f" % night["energy"], "%.3f" % _sun.light_energy,
		absf(_sun.light_energy - float(night["energy"])) <= 1e-3)
	_assert("B_night_color_is_cool", "b > r", "(%.2f,%.2f,%.2f)" % [
		_sun.light_color.r, _sun.light_color.g, _sun.light_color.b],
		_sun.light_color.b > _sun.light_color.r)
	print("MEASURE|night|elev=%.2f|energy=%.3f|ambient=%.3f|color=(%.2f,%.2f,%.2f)" % [
		_sun.rotation_degrees.x, _sun.light_energy, _env.ambient_light_energy,
		_sun.light_color.r, _sun.light_color.g, _sun.light_color.b])
	# 夜间：天空倍率压暗 + 环境光切 COLOR（否则 ambient 在下界也无效，画面会"像白天"）
	_assert("B_night_sky_energy_written", "%.3f" % night["sky_energy"], "%.3f" % _sky_energy(),
		absf(_sky_energy() - float(night["sky_energy"])) <= 1e-3)
	_assert("B_night_ambient_source_color", "%d" % Environment.AMBIENT_SOURCE_COLOR,
		"%d" % _env.ambient_light_source, _env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR)


# ---------------- C：存档恢复正确（无状态） ----------------

func _check_restore_is_stateless() -> void:
	if _sun == null or _env == null:
		_assert("C_restore", "需要先绑定成功", "skipped", false)
		return
	_wd.call("set_world_time", 412.5)
	_dn.call("apply_now")
	var first := _snapshot()
	# 中间去别的时间逛一圈，再"读档回来"
	_wd.call("set_world_time", 950.0)
	_dn.call("apply_now")
	_wd.call("set_world_time", 10.0)
	_dn.call("apply_now")
	_wd.call("set_world_time", 412.5)
	_dn.call("apply_now")
	var second := _snapshot()
	_assert("C_restore_identical", first, second, first == second)


func _sky_energy() -> float:
	if _env == null or _env.sky == null or _env.sky.sky_material == null:
		return -1.0
	return float(_env.sky.sky_material.get("energy_multiplier"))


func _snapshot() -> String:
	return "%.5f|%.5f|%.5f|%.5f|%.5f|%.5f|%.5f|%d|%.5f" % [
		_sun.rotation_degrees.x, _sun.rotation_degrees.y, _sun.light_energy,
		_sun.light_color.r, _sun.light_color.g, _sun.light_color.b,
		_sky_energy(), int(_env.ambient_light_source),
		float(_env.ambient_light_energy)]


# ---------------- D：夜间可读 ----------------

func _check_night_readable() -> void:
	var floor_ambient: float = float(DAY_NIGHT.NIGHT_AMBIENT_FLOOR)
	var worst := INF
	var detail: Array[String] = []
	var t := 600.0
	while t < 1200.0:
		var s: Dictionary = DAY_NIGHT.sample(t, 1200.0)
		var amp: float = float(s["ambient"])
		worst = minf(worst, amp)
		if absf(fmod(t, 120.0)) < 0.001:
			detail.append("%.0fs=%.2f" % [t, amp])
		t += 20.0
	_assert("D_night_ambient_floor", "≥ %.2f" % floor_ambient, "%.4f" % worst,
		worst >= floor_ambient - 1e-6)
	_assert("D_night_ambient_above_zero", "> 0.2（能看清路线）", "%.2f" % worst, worst > 0.2)
	_assert("D_day_ambient_brighter", "白天 > 夜间", "%.2f > %.2f" % [
		float(DAY_NIGHT.sample(300.0, 1200.0)["ambient"]), worst],
		float(DAY_NIGHT.sample(300.0, 1200.0)["ambient"]) > worst)


# ---------------- E：感知差异旋钮 ----------------

func _check_knob() -> void:
	var knob: Variant = _dn.get("night_sight_multiplier")
	_assert("E_knob_exists", "存在", str(knob), knob != null)
	_assert("E_knob_default_1", "1.0（默认不改玩法）", "%.2f" % float(knob), absf(float(knob) - 1.0) <= 1e-6)


# ---------------- F：与 T034 昼夜口径一致 ----------------

func _check_matches_world_clock() -> void:
	var mismatches: Array[String] = []
	for t in [0.0, 300.0, 599.0, 600.0, 900.0, 1199.0, 1200.0]:
		_wd.call("set_world_time", t)
		var day_by_director: bool = bool(_wd.call("is_daytime"))
		var day_by_sample: bool = bool(DAY_NIGHT.sample(t, float(_wd.get("day_length")))["is_day"])
		if day_by_director != day_by_sample:
			mismatches.append("%.0f:%s/%s" % [t, day_by_director, day_by_sample])
	_assert("F_matches_world_clock_is_daytime", "0 处不一致", "%s" % [mismatches], mismatches.is_empty())
	_wd.call("set_world_time", 0.0)


# ---------------- 工具 ----------------

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
