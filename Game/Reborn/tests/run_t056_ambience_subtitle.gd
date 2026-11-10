extends SceneTree
## T056：**环境声音与关键字幕**（开发计划 :248）。
##
## 验收词：「溪流等基础环境音；字幕**不显示不可感知敌人的真实位置**」。
##
## 判据：
##  A. 环境音资产：溪流/风两条流都在、`LOOP_FORWARD`、长度 ≥ 2 s（否则循环会"播完就停"）；
##  B. 环境音布点：关卡里的每个 `water_bodies` 水体各挂一条 3D 循环，位置与水体一致、
##     `unit_size=6` / `max_distance=30`、确实在播；
##  C. **可感知的噪声** → 出字幕，文本用方位词（右侧/前方…）；
##  D. **不可感知的噪声**（超出 `hearing_range × loudness`）→ **完全不出字幕**；
##  E. 文本**不含位置信息**：同一方位、不同坐标 → 文本完全相同；且不含数字/坐标；
##  F. 环境字幕（溪水）与开关（`enabled=false` 后不再产生字幕）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t056_ambience_subtitle.gd' --quit-after 60000
## 结果口径：RESULT|pass=<n>|fail=<n>|failed=...

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CAT_CFG := "res://resources/species/cat.tres"

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _amb: Node = null
var _sub: Node = null
var _wd: Node = null
var _level: Node3D = null
var _cat: AnimalBody = null


func _initialize() -> void:
	await process_frame
	_amb = root.get_node_or_null("/root/AmbienceDirector")
	_sub = root.get_node_or_null("/root/SubtitleDirector")
	_wd = root.get_node_or_null("/root/WorldDirector")
	if not _assert("A0_autoloads", "AmbienceDirector + SubtitleDirector",
			"%s/%s" % [_amb != null, _sub != null], _amb != null and _sub != null):
		_finish()
		return
	_check_audio_assets()
	await _check_placement()
	await _check_subtitle_perceivable()
	_check_subtitle_unperceivable()
	_check_text_no_position()
	_check_ambient_and_switch()
	_finish()


# ---------------- A：环境音资产 ----------------

func _check_audio_assets() -> void:
	for pair in [["creek", "creek_stream"], ["wind", "wind_stream"]]:
		var s: AudioStream = _amb.call(pair[1])
		_assert("A_stream_%s" % pair[0], "AudioStreamWAV",
			"null" if s == null else s.get_class(), s != null and s is AudioStreamWAV)
		if s == null:
			continue
		var wav := s as AudioStreamWAV
		_assert("A_loop_%s" % pair[0], "LOOP_FORWARD", str(wav.loop_mode),
			wav.loop_mode == AudioStreamWAV.LOOP_FORWARD)
		var secs: float = wav.get_length()
		_assert("A_length_%s" % pair[0], "≥ 2.0 s", "%.2f s" % secs, secs >= 2.0)


# ---------------- B：布点 ----------------

func _check_placement() -> void:
	_level = (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(_level)
	await process_frame
	var water := _level.find_child("CreekWater", true, false) as Node3D
	if not _assert("B_water_node", "CreekWater", str(water != null), water != null):
		return
	var count: int = int(_amb.call("bind_level", _level))
	_assert("B_bind_loops", "≥ 1", str(count), count >= 1)
	_assert("B_playing_all", "全部在播", "%d/%d" % [int(_amb.call("playing_loops")), count],
		int(_amb.call("playing_loops")) == count)
	var players: Array = _amb.call("players")
	var max_delta := 0.0
	var unit_ok := true
	var far_ok := true
	for p in players:
		max_delta = maxf(max_delta, (p as AudioStreamPlayer3D).global_position.distance_to(water.global_position))
		if absf((p as AudioStreamPlayer3D).unit_size - 6.0) > 1e-3:
			unit_ok = false
		if absf((p as AudioStreamPlayer3D).max_distance - 30.0) > 1e-3:
			far_ok = false
	_assert("B_position_matches_water", "≤ 0.5 m", "%.3f m" % max_delta, max_delta <= 0.5)
	_assert("B_unit_size_6", "6.0", "ok" if unit_ok else "mismatch", unit_ok)
	_assert("B_max_distance_30", "30.0", "ok" if far_ok else "mismatch", far_ok)
	_assert("B_wind_bed", "true", str(_amb.call("wind_playing")), bool(_amb.call("wind_playing")))


# ---------------- C：可感知噪声 → 字幕 ----------------

func _check_subtitle_perceivable() -> void:
	_cat = (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	_cat.species_config = load(CAT_CFG) as SpeciesConfig
	_cat.ai_enabled = false
	_cat.player_controlled = true
	_level.add_child(_cat)
	_cat.global_position = Vector3(0.0, 0.5, 0.0)
	_cat.rotation = Vector3.ZERO
	await _step(4)
	_sub.call("bind_player", _cat)
	var before: int = int(_sub.get("subtitle_count"))
	# 玩家朝 −Z；声源放在右前方 1.4 m（猫 hearing_range 12 × 0.5 = 6 m 内，必然可闻）
	_wd.call("emit_action", &"footstep_walk", "npc#t056", Vector3(1.0, 0.2, -1.0), 0.5)
	await _step(3)
	var after: int = int(_sub.get("subtitle_count"))
	var text: String = String(_sub.call("current_text"))
	_assert("C_perceivable_makes_subtitle", "+1", str(after - before), after == before + 1)
	_assert("C_text_has_direction", "含方向词", text,
		text.contains("右侧") or text.contains("右前") or text.contains("前方"))
	_assert("C_text_no_digits", "无 0-9", text, not _has_digits(text))
	print("MEASURE|subtitle|text=%s|direction=%s" % [text, _sub.get("last_direction")])


# ---------------- D：不可感知噪声 → 无字幕 ----------------

func _check_subtitle_unperceivable() -> void:
	var before: int = int(_sub.get("subtitle_count"))
	# 50 m 外：远超 12 × 1.0 的听觉距离
	_wd.call("emit_action", &"footstep_run", "npc#far", Vector3(50.0, 0.2, -50.0), 1.0)
	_assert("D_unperceivable_no_subtitle", "+0", "0",
		int(_sub.get("subtitle_count")) == before)


# ---------------- E：文本不含位置信息 ----------------

func _check_text_no_position() -> void:
	var a: String = String(_sub.call("push_noise", Vector3(1.0, 0.2, -3.0)))
	var b: String = String(_sub.call("push_noise", Vector3(0.5, 0.2, -3.0)))
	_assert("E_same_direction_same_text", a, b, a == b)
	_assert("E_text_no_digits_again", "无 0-9", a, not _has_digits(a))
	var no_coords: bool = not (a.contains("(") or a.contains(",") or a.contains("米") or a.contains(" m"))
	_assert("E_text_no_coordinates", "不含 ( , 米 m", a, no_coords)
	# 反例守卫：真实位置不得出现在文本里
	_assert("E_text_differs_from_coords", "≠ 坐标串", a,
		not a.contains("1.0") and not a.contains("-3") and not a.contains("3.0"))


# ---------------- F：环境字幕 + 开关 ----------------

func _check_ambient_and_switch() -> void:
	var creek_text: String = String(_sub.call("push_ambient", &"creek"))
	_assert("F_ambient_creek_text", "「溪水声」", creek_text, creek_text == "「溪水声」")
	_assert("F_ambient_no_digits", "无 0-9", creek_text, not _has_digits(creek_text))

	_sub.set("enabled", false)
	var before: int = int(_sub.get("subtitle_count"))
	_wd.call("emit_action", &"footstep_walk", "npc#t056b", Vector3(1.0, 0.2, -1.0), 0.5)
	_assert("F_switch_off_no_subtitle", "+0", "0", int(_sub.get("subtitle_count")) == before)
	_sub.set("enabled", true)


# ---------------- 工具 ----------------

func _has_digits(s: String) -> bool:
	var digits := "0123456789"
	for ch in s:
		if digits.contains(ch):
			return true
	return false


func _step(n: int) -> void:
	for i in n:
		await physics_frame


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
