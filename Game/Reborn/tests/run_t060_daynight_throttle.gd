extends SceneTree
## T060：**昼夜光照限频的性能修正**（`DayNightDirector.MIN_APPLY_INTERVAL`）的契约守卫。
##
## 为什么需要有这套断言：限频是为了性能，但很容易顺手改坏语义——
## 例如"小时间步永不更新"（画面卡在旧光照）、"读档跳变被吞掉"（回到错的时间）。
## 这里把四条硬契约钉住：
##   A. **显式 `apply_now()` 永远立即生效**（测试/读档/休息都靠它）；
##   B. **自动路径按 `MIN_APPLY_INTERVAL` 限频**：小于间隔不重推，达到间隔一定重推；
##   C. **时间跳变（读档/休息快进，正反两个方向）一定重推**，不会被限频吞掉；
##   D. 采样仍是 `world_time` 的**纯函数**（限频只改"多久写一次"，不改值）。

const LEVEL := "res://scenes/maps/l_courtyard.tscn"

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _dn: Node = null
var _wd: Node = null
var _sun: DirectionalLight3D = null


func _initialize() -> void:
	await process_frame
	_dn = root.get_node_or_null("/root/DayNightDirector")
	_wd = root.get_node_or_null("/root/WorldDirector")
	if not _assert("A0_autoloads", "DayNightDirector + WorldDirector",
			"%s/%s" % [_dn != null, _wd != null], _dn != null and _wd != null):
		_finish()
		return
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		_assert("A1_level", "关卡可加载", "null", false)
		_finish()
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	await process_frame
	_sun = level.get_node_or_null("SunLight") as DirectionalLight3D
	var bound: bool = bool(_dn.call("bind_level", level))
	_assert("A1_bind", "bind_level=true 且拿到 SunLight", "%s/%s" % [str(bound), str(_sun != null)],
		bound and _sun != null)
	if _sun == null:
		_finish()
		return
	await _check_contract()
	_finish()


func _check_contract() -> void:
	var interval := float(_dn.get("MIN_APPLY_INTERVAL"))
	_assert("B0_interval", "0 < 间隔 ≤ 1 s", "%.2f s" % interval, interval > 0.0 and interval <= 1.0)
	# 关掉时间推进：headless 下每帧真实 delta 不稳定（不受 vsync 限制），
	# 若让它继续走，"小步不重推"会被额外的帧时间补到间隔之上而假红。
	# 关掉后**只有** `set_world_time()` 能移动世界时间 → 变体间完全确定。
	_wd.set("time_advancing", false)

	# A：显式 apply_now 永远立即生效（连调两次都要 +1）
	_wd.call("set_world_time", 300.0)
	var c0 := int(_dn.get("apply_count"))
	_dn.call("apply_now")
	_dn.call("apply_now")
	var c1 := int(_dn.get("apply_count"))
	_assert("A2_explicit_always_applies", "显式调用两次都生效", "%d → %d" % [c0, c1], c1 == c0 + 2)
	_assert("A3_explicit_writes_sun", "正午仰角 70°", "%.2f°" % _sun.rotation_degrees.x,
		absf(_sun.rotation_degrees.x + 70.0) <= 0.01)

	# B：自动路径——小于间隔不重推
	await _auto_step(interval * 0.3)
	var c_small := int(_dn.get("apply_count"))
	_assert("B1_small_step_no_apply", "小于间隔不重推", "%d（基准 %d）" % [c_small, c1], c_small == c1)

	# B：达到间隔一定重推
	await _auto_step(interval * 1.5)
	var c_big := int(_dn.get("apply_count"))
	_assert("B2_interval_step_applies", "达到间隔就重推", "%d（预期 > %d）" % [c_big, c_small], c_big > c_small)

	# C：正向跳变（休息快进 60 s）一定重推，且写进去的就是**应用那一刻**的值。
	# 注意：`set_world_time` 之后引擎每帧仍按真实 delta 往前走，所以用 `last_sample.world_time`
	# 自洽核对（并另外确认它离跳变点 ≤ 1 s），不拿常量时间硬比。
	var t_before := float(_wd.get("world_time"))
	_wd.call("set_world_time", t_before + 60.0)
	await process_frame
	await process_frame
	var sample: Dictionary = _dn.get("last_sample")
	var applied_t := float(sample.get("world_time", -1.0))
	var expect := float(_dn.call("sample_at", applied_t).get("elevation_deg", 0.0))
	_assert("C1_forward_jump_applies", "正向跳变立即重推（离跳变点 ≤1 s）",
		"applied_t=%.3f 目标=%.3f" % [applied_t, t_before + 60.0],
		absf(applied_t - (t_before + 60.0)) <= 1.0
		and absf(float(sample.get("elevation_deg", 0.0)) - expect) <= 1e-9)

	# C：反向跳变（读档把时间调小）也一定重推
	_wd.call("set_world_time", 10.0)
	await process_frame
	await process_frame
	var back: Dictionary = _dn.get("last_sample")
	var back_t := float(back.get("world_time", -1.0))
	var expect_back := float(_dn.call("sample_at", back_t).get("elevation_deg", 0.0))
	_assert("C2_backward_jump_applies", "反向跳变立即重推（≤1 s 内跟上）",
		"applied_t=%.3f 目标=10.000" % back_t,
		absf(back_t - 10.0) <= 1.0
		and absf(float(back.get("elevation_deg", 0.0)) - expect_back) <= 1e-9)

	# D：采样仍是纯函数（同一个 t 两次采样逐位相同）
	var a := _dn.call("sample_at", 640.0) as Dictionary
	var b := _dn.call("sample_at", 640.0) as Dictionary
	_assert("D1_sample_pure", "同 t 两次采样逐位相同",
		"%.6f/%.6f" % [float(a["energy"]), float(b["energy"])],
		absf(float(a["energy"]) - float(b["energy"])) <= 0.0
		and absf(float(a["ambient"]) - float(b["ambient"])) <= 0.0)

	# E：关掉 director 后自动路径不再写（与探针的 `no_daynight` 变体同一条路径）
	_dn.set("enabled", false)
	var c_disabled := int(_dn.get("apply_count"))
	_wd.call("set_world_time", float(_wd.get("world_time")) + 120.0)
	await process_frame
	await process_frame
	_assert("E1_disabled_no_auto_apply", "enabled=false 时不自动写",
		"%d（基准 %d）" % [int(_dn.get("apply_count")), c_disabled],
		int(_dn.get("apply_count")) == c_disabled)
	_dn.set("enabled", true)
	_wd.set("time_advancing", true)


## 让世界时间前进 `step` 秒，再等两帧让 `_process` 有机会跑
func _auto_step(step: float) -> void:
	_wd.call("set_world_time", float(_wd.get("world_time")) + step)
	await process_frame
	await process_frame


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
