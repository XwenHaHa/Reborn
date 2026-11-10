extends SceneTree
## T055：**行动声音与 AI 噪声统一**（开发计划 :247）。
##
## 验收词：「步伐、奔跑、攻击和受伤音效；**同一事件驱动声音和 AI 噪声**，距离衰减可辨」。
##
## 判据：
##  A. 资产：4 个音源都在（`AudioDirector` autoload + 4 个 WAV），缺失即红灯；
##  B. 统一出口：**一次** `emit_action()` 同时（1）出声、（2）按白名单喂 AI 噪声；
##  C. 白名单外（攻击/受伤）**只出声、不动 AI** —— 加音效不得悄悄改玩法；
##  D. 距离衰减：`gain_at()` 随距离单调不增、1 m 与 8 m 差 ≥ 10 dB、超出 `max_distance` 归零；
##  E. 真实身体：一次脚步 = 1 声 + 1 个噪声事件；奔跑用 `footstep_run`；
##  F. 静音开关：`enabled=false` 时不出声，但**噪声照发**（音频不得影响玩法）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/run_t055_audio_noise.gd' --quit-after 60000
## 结果口径：RESULT|pass=<n>|fail=<n>|failed=...

const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const CAT_CFG := "res://resources/species/cat.tres"
const MOUSE_CFG := "res://resources/species/mouse.tres"

const KINDS := [&"footstep_walk", &"footstep_run", &"attack", &"hurt"]

var _pass := 0
var _fail := 0
var _failed: Array[String] = []
var _audio: Node = null
var _wd: Node = null


func _initialize() -> void:
	await process_frame   # SceneTree 的 root 还没进树时不能用绝对路径取 autoload（T043a 同口径）
	_audio = root.get_node_or_null("/root/AudioDirector")
	_wd = root.get_node_or_null("/root/WorldDirector")
	if not _assert("A0_audio_autoload", "AudioDirector", str(_audio != null), _audio != null):
		_finish()
		return
	if not _assert("A0_world_director", "WorldDirector", str(_wd != null), _wd != null):
		_finish()
		return
	_check_assets()
	_check_funnel()
	_check_gating()
	_check_attenuation()
	await _check_body_footsteps()
	_check_mute_switch()
	_finish()


# ---------------- A：资产 ----------------

func _check_assets() -> void:
	for kind in KINDS:
		var stream: AudioStream = _audio.call("stream_of", kind)
		_assert("A_stream_%s" % kind, "AudioStream", "null" if stream == null else stream.get_class(),
			stream != null)
		if stream != null:
			var secs: float = stream.get_length() if stream.has_method("get_length") else -1.0
			_assert("A_length_%s" % kind, "> 0.05 s", "%.3f s" % secs, secs > 0.05)


# ---------------- B：统一出口（一次调用 → 声音 + 噪声） ----------------

func _check_funnel() -> void:
	_audio.call("reset_log")
	var noise_before: int = int(_wd.get("noise_event_count"))
	var action_before: int = int(_wd.get("action_count"))
	var pos := Vector3(3.0, 0.2, -4.0)
	_wd.call("emit_action", &"footstep_walk", "probe#1", pos, 0.5)
	var plays: int = int(_audio.get("play_count"))
	var noise_after: int = int(_wd.get("noise_event_count"))
	var action_after: int = int(_wd.get("action_count"))
	_assert("B_one_play", "1", str(plays - 0), plays == 1)
	_assert("B_kind", "footstep_walk", str(_audio.get("last_kind")), _audio.get("last_kind") == &"footstep_walk")
	_assert("B_position", "(3.000,0.200,-4.000)", "%.3f,%.3f,%.3f" % [
		_audio.get("last_position").x, _audio.get("last_position").y, _audio.get("last_position").z],
		(_audio.get("last_position") as Vector3).distance_to(pos) < 1e-4)
	_assert("B_noise_plus_one", "+1", str(noise_after - noise_before), noise_after == noise_before + 1)
	_assert("B_action_count", "+1", str(action_after - action_before), action_after == action_before + 1)
	var last: Dictionary = _wd.get("last_action")
	_assert("B_last_action_to_ai", "true", str(last.get("to_ai", false)), bool(last.get("to_ai", false)))
	# 音量：0.5 线性 → -6.02 dB（容差 0.2）
	var logv: Array = _audio.get("play_log")
	var db: float = float(logv[-1].get("volume_db", 0.0)) if logv.size() > 0 else 0.0
	_assert("B_volume_db", "≈ -6.02 dB", "%.2f dB" % db, absf(db - (-6.0206)) <= 0.2)


# ---------------- C：白名单外只出声，不动 AI ----------------

func _check_gating() -> void:
	for kind in [&"attack", &"hurt"]:
		_audio.call("reset_log")
		var noise_before: int = int(_wd.get("noise_event_count"))
		_wd.call("emit_action", kind, "probe#2", Vector3.ZERO, 1.0)
		var plays: int = int(_audio.get("play_count"))
		var noise_after: int = int(_wd.get("noise_event_count"))
		_assert("C_%s_plays" % kind, "1", str(plays), plays == 1)
		_assert("C_%s_no_ai_noise" % kind, "0（白名单外）", str(noise_after - noise_before),
			noise_after == noise_before)
		var last: Dictionary = _wd.get("last_action")
		_assert("C_%s_to_ai_false" % kind, "false", str(last.get("to_ai", true)),
			not bool(last.get("to_ai", true)))


# ---------------- D：距离衰减 ----------------

func _check_attenuation() -> void:
	var dists := [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
	var prev := INF
	var mono := true
	var detail: Array[String] = []
	for d in dists:
		var g: float = _audio.call("gain_at", &"footstep_run", float(d))
		detail.append("%.1fm=%.4f" % [float(d), g])
		if g > prev + 1e-6:
			mono = false
		prev = g
	_assert("D_monotonic_decrease", "随距离不增", " ".join(detail), mono)
	var g1: float = _audio.call("gain_db_at", &"footstep_run", 1.0)
	var g8: float = _audio.call("gain_db_at", &"footstep_run", 8.0)
	_assert("D_db_spread_1m_vs_8m", "≥ 10 dB", "%.2f dB" % (g1 - g8), (g1 - g8) >= 10.0)
	var far: float = _audio.call("gain_at", &"footstep_run", 40.0)
	_assert("D_beyond_max_distance", "0", "%.4f" % far, far <= 0.0)
	# 响声更远的音源在同一距离上更响（受伤 > 脚步）
	var hurt_g: float = _audio.call("gain_at", &"hurt", 6.0)
	var walk_g: float = _audio.call("gain_at", &"footstep_walk", 6.0)
	_assert("D_unit_size_ordering", "hurt > footstep_walk", "%.4f > %.4f" % [hurt_g, walk_g],
		hurt_g > walk_g)


# ---------------- E：真实身体的一次脚步 ----------------

func _check_body_footsteps() -> void:
	var cat := (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	cat.species_config = load(CAT_CFG) as SpeciesConfig
	cat.ai_enabled = false
	cat.player_controlled = false
	root.add_child(cat)
	cat.global_position = Vector3(0.0, 0.5, 0.0)
	await _step(6)

	_audio.call("reset_log")
	var noise_before: int = int(_wd.get("noise_event_count"))
	cat.call("_emit_footstep")
	var plays: int = int(_audio.get("play_count"))
	var noise_after: int = int(_wd.get("noise_event_count"))
	_assert("E_walk_play", "1", str(plays), plays == 1)
	_assert("E_walk_kind", "footstep_walk", str(_audio.get("last_kind")),
		_audio.get("last_kind") == &"footstep_walk")
	_assert("E_walk_noise_one", "+1", str(noise_after - noise_before), noise_after == noise_before + 1)

	# 奔跑：`want_sprint` + 速度超阈值 → footstep_run
	cat.want_sprint = true
	cat.velocity = Vector3(0.0, 0.0, -4.5)
	_audio.call("reset_log")
	cat.call("_emit_footstep")
	_assert("E_run_kind", "footstep_run", str(_audio.get("last_kind")),
		_audio.get("last_kind") == &"footstep_run")
	cat.want_sprint = false
	cat.velocity = Vector3.ZERO

	# 受伤：掉血 → hurt 声；攻击声走同一出口（命中帧）
	_audio.call("reset_log")
	cat.survival.apply_damage(5.0, &"probe")
	_assert("E_hurt_kind", "hurt", str(_audio.get("last_kind")), _audio.get("last_kind") == &"hurt")
	_assert("E_hurt_plays", "1", str(int(_audio.get("play_count"))), int(_audio.get("play_count")) == 1)
	cat.queue_free()
	await _step(2)


# ---------------- F：静音开关不影响玩法 ----------------

func _check_mute_switch() -> void:
	# 计数从 0 起（否则会把上一节的播放算进来），并关掉音频
	_audio.set("enabled", false)
	_audio.call("reset_log")
	var noise_before: int = int(_wd.get("noise_event_count"))
	_wd.call("emit_action", &"footstep_walk", "probe#3", Vector3.ZERO, 0.5)
	var noise_after: int = int(_wd.get("noise_event_count"))
	var plays: int = int(_audio.get("play_count"))
	_audio.set("enabled", true)
	_assert("F_muted_no_play", "0", str(plays), plays == 0)
	_assert("F_muted_still_emits_noise", "+1（玩法不受音频影响）", str(noise_after - noise_before),
		noise_after == noise_before + 1)


# ---------------- 工具 ----------------

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
