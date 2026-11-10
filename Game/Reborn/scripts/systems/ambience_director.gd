extends Node
## T056：环境音（溪流 + 风）—— 自有合成、可无缝循环。
##
## 为什么单独一层：环境音不是"某个事件的声音"，而是**空间性的持续声场**：
## 溪流随位置远近变化（3D 衰减），风是铺满全场的底噪（非定位）。
## 与行动音效（T055 的 `AudioDirector`）分开，避免"事件音"和"环境床"互相抢播放器。
##
## 可判定性：`active_loops()` / `creek_positions()` / 每个播放器的 `playing`、`unit_size`、
## `max_distance`、`loop_mode` 都能被测试直接读，不依赖"听"。

const CREEK_PATH := "res://assets/audio/creek_loop.wav"
const WIND_PATH := "res://assets/audio/wind_loop.wav"

## 溪流：`unit_size` 决定"多近才算贴着水边"，`max_distance` 决定能听多远
const CREEK_UNIT := 6.0
const CREEK_MAX_DISTANCE := 30.0
const CREEK_DB := -4.0
const WIND_DB := -20.0
const WATER_GROUP := &"water_bodies"

var enabled := true

var _creek_stream: AudioStreamWAV = null
var _wind_stream: AudioStreamWAV = null
var _container: Node3D = null
var _creek_players: Array[AudioStreamPlayer3D] = []
var _wind_player: AudioStreamPlayer = null


func _ready() -> void:
	_creek_stream = _prepare_loop(CREEK_PATH)
	_wind_stream = _prepare_loop(WIND_PATH)
	_container = Node3D.new()
	_container.name = "AmbienceContainer"
	add_child(_container)
	_wind_player = AudioStreamPlayer.new()
	_wind_player.name = "WindBed"
	_wind_player.stream = _wind_stream
	_wind_player.volume_db = WIND_DB
	add_child(_wind_player)
	if enabled and _wind_player.stream != null:
		_wind_player.play()


## 载入并把循环点设成整段（导入器默认 `LOOP_DISABLED`，不设就会"播完就停"）。
func _prepare_loop(path: String) -> AudioStreamWAV:
	var s := load(path) as AudioStreamWAV
	if s == null:
		return null
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	var channels: int = 2 if s.stereo else 1
	s.loop_end = int(s.data.size() / (2 * channels))
	return s


## 给关卡里的每个水体挂一条 3D 溪流循环。返回挂上的条数。
func bind_level(level: Node) -> int:
	clear()
	if level == null or not is_inside_tree():
		return 0
	var water := get_tree().get_nodes_in_group(WATER_GROUP)
	for w in water:
		var node := w as Node3D
		if node == null or not level.is_ancestor_of(node):
			continue
		var p := AudioStreamPlayer3D.new()
		p.name = "CreekLoop_%s" % node.name
		p.stream = _creek_stream
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = CREEK_UNIT
		p.max_distance = CREEK_MAX_DISTANCE
		p.volume_db = CREEK_DB
		p.panning_strength = 0.8
		_container.add_child(p)
		p.global_position = node.global_position
		if enabled and p.stream != null:
			p.play()
		_creek_players.append(p)
	return _creek_players.size()


## 只读副本（测试按位置/衰减参数断言）
func players() -> Array[AudioStreamPlayer3D]:
	var out: Array[AudioStreamPlayer3D] = []
	for p in _creek_players:
		if is_instance_valid(p):
			out.append(p)
	return out


func clear() -> void:
	for p in _creek_players:
		if is_instance_valid(p):
			p.stop()
			p.queue_free()
	_creek_players.clear()


func active_loops() -> int:
	return _creek_players.size()


func playing_loops() -> int:
	var n := 0
	for p in _creek_players:
		if is_instance_valid(p) and p.playing:
			n += 1
	return n


func creek_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in _creek_players:
		if is_instance_valid(p):
			out.append(p.global_position)
	return out


func creek_stream() -> AudioStream:
	return _creek_stream


func wind_stream() -> AudioStream:
	return _wind_stream


func wind_playing() -> bool:
	return _wind_player != null and _wind_player.playing


func set_enabled(value: bool) -> void:
	enabled = value
	if _wind_player != null:
		if value and _wind_player.stream != null:
			_wind_player.play()
		else:
			_wind_player.stop()
	for p in _creek_players:
		if not is_instance_valid(p):
			continue
		if value and p.stream != null:
			p.play()
		else:
			p.stop()
