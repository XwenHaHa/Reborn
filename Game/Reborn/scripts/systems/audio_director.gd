extends Node
## T055：行动音效的唯一出口（`AudioDirector`，autoload）。
##
## 为什么要有这一层：项目此前**没有任何音频设施**；如果让每个玩法脚本各自
## `AudioStreamPlayer.play()`，就会出现"声音和 AI 噪声各写一遍、条件不一致"的经典错位
## —— 玩家能听见、AI 听不见（或反过来）。这里把**音源选择、距离衰减、播放计数**
## 收到一处，玩法侧只表达"发生了什么事件"（`footstep_walk` / `attack` …）。
##
## 与 AI 的关系：`WorldDirector.emit_action()` 是同时喂**声音**和**噪声**的那个入口；
## 本类只管"出声"，不参与听觉判定（`Perception` 仍然只听 `noise_emitted`）。
##
## 可判定性：`play_log` / `play_count` 记录每次播放，测试用它们证明
## "一次事件 = 一次出声"，并用 `gain_at()` 证明距离衰减单调（不靠听）。

## 音源表：单位距离（`unit_size`）越大，同样距离下越响 —— 石块脚步声传得近、受伤声传得远。
const SOUNDS := {
	&"footstep_walk": {"path": "res://assets/audio/footstep_walk.wav", "unit": 1.6},
	&"footstep_run": {"path": "res://assets/audio/footstep_run.wav", "unit": 2.4},
	&"attack": {"path": "res://assets/audio/attack.wav", "unit": 2.2},
	&"hurt": {"path": "res://assets/audio/hurt.wav", "unit": 3.2},
}

const POOL_SIZE := 8
const MAX_DISTANCE := 40.0
const LOG_LIMIT := 32

## 关掉后只出噪声不出声（音频不得影响玩法，见 `tests/run_t055_audio_noise.gd` F 组）
var enabled := true

var play_count := 0
var last_kind: StringName = &""
var last_position := Vector3.ZERO
var last_loudness := 0.0
var play_log: Array[Dictionary] = []

var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _container: Node3D = null


func _ready() -> void:
	for kind in SOUNDS:
		var path: String = SOUNDS[kind]["path"]
		var stream := load(path)
		if stream != null:
			_streams[kind] = stream
	# 3D 播放器必须挂在 3D 世界里：autoload 本身是 `Node`，所以建一个 Node3D 容器
	_container = Node3D.new()
	_container.name = "AudioContainer"
	add_child(_container)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.name = "Voice%d" % i
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.max_distance = MAX_DISTANCE
		p.panning_strength = 0.6
		_container.add_child(p)
		_pool.append(p)


func has_kind(kind: StringName) -> bool:
	return _streams.has(kind)


func stream_of(kind: StringName) -> AudioStream:
	return _streams.get(kind, null)


## 播一次。返回 true = 真的分配到播放器并播放（资源缺失或 `enabled=false` 时 false）。
func play(kind: StringName, at: Vector3, loudness: float = 1.0) -> bool:
	if not enabled:
		return false
	var stream: AudioStream = _streams.get(kind, null)
	if stream == null:
		return false
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.unit_size = float(SOUNDS[kind]["unit"])
	p.volume_db = linear_to_db(clampf(loudness, 0.02, 1.0))
	p.global_position = at
	p.play()
	play_count += 1
	last_kind = kind
	last_position = at
	last_loudness = loudness
	play_log.append({
		"kind": kind,
		"position": at,
		"loudness": loudness,
		"volume_db": p.volume_db,
		"unit_size": p.unit_size,
	})
	if play_log.size() > LOG_LIMIT:
		play_log.pop_front()
	return true


## 距离衰减（0..1，与 `ATTENUATION_INVERSE_DISTANCE` 同口径）：
## `unit_size / max(distance, unit_size)`，距离 ≥ `max_distance` 时为 0。
func gain_at(kind: StringName, distance: float) -> float:
	if not SOUNDS.has(kind):
		return 0.0
	if distance >= MAX_DISTANCE:
		return 0.0
	var unit := float(SOUNDS[kind]["unit"])
	return clampf(unit / maxf(maxf(distance, 0.01), unit), 0.0, 1.0)


func gain_db_at(kind: StringName, distance: float) -> float:
	var g := gain_at(kind, distance)
	return linear_to_db(g) if g > 0.0 else -80.0


func reset_log() -> void:
	play_count = 0
	last_kind = &""
	last_position = Vector3.ZERO
	last_loudness = 0.0
	play_log.clear()
