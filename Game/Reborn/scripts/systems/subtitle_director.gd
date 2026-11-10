extends Node
## T056：关键字幕 —— **只说玩家能感知到的事，且永远不给坐标**。
##
## 验收词（开发计划 :248）：「字幕**不显示不可感知敌人的真实位置**」。
## 做法不是"记得别打印坐标"，而是从结构上堵住：
##  1. 字幕**只**由玩家 `Perception.noise_heard` 信号产生 —— 该信号本身已经在
##     `Perception.receive_noise()` 里做过距离/响度/自身过滤，听不到就根本不会触发；
##  2. 文本只由**方位词**拼成（前方/右前/右侧/…），不含距离、坐标、数字；
##  3. 同一方位、不同位置的声源产生**完全相同**的文本 ⇒ 文本不携带位置信息。
##
## 可判定性：`subtitle_count` / `last_text` / `last_direction` 供测试直接读。

## 8 个方位桶（从正前方开始，顺时针 45° 一档）
const DIRECTIONS: Array[StringName] = [
	&"前方", &"右前", &"右侧", &"右后", &"后方", &"左后", &"左侧", &"左前",
]
const TTL_MS := 2200

var enabled := true
var hud: Node = null
var player: AnimalBody = null

var subtitle_count := 0
var last_text := ""
var last_kind: StringName = &""
var last_direction: StringName = &""
var visible_until_ms := 0


## HUD 只作为显示通道（复用既有 toast，避免再动 HUD 布局断言）
func bind_hud(h: Node) -> void:
	hud = h


## 绑定玩家身体；只订阅它的 `Perception.noise_heard`。
func bind_player(body: AnimalBody) -> void:
	if player != null and is_instance_valid(player) and player.perception != null \
			and player.perception.noise_heard.is_connected(_on_noise_heard):
		player.perception.noise_heard.disconnect(_on_noise_heard)
	player = body
	if body != null and body.perception != null \
			and not body.perception.noise_heard.is_connected(_on_noise_heard):
		body.perception.noise_heard.connect(_on_noise_heard)
	clear()


func unbind_player() -> void:
	bind_player(null)


func _on_noise_heard(position: Vector3, _loudness: float) -> void:
	if not enabled or player == null or not is_instance_valid(player):
		return
	push_noise(position)


## 由**已被告知**的噪声位置生成字幕（调用方保证"玩家确实听到了"）。
func push_noise(world_position: Vector3) -> String:
	var dir := direction_word(world_position)
	var text := "「%s传来动静」" % dir
	_push(text, &"noise", dir)
	return text


## 环境类字幕（溪水/风）：与敌人无关，允许直接推送。
func push_ambient(kind: StringName) -> String:
	var text := ""
	match kind:
		&"creek":
			text = "「溪水声」"
		&"wind":
			text = "「风声」"
		_:
			text = "「%s」" % kind
	_push(text, &"ambient", &"")
	return text


## 世界坐标 → 方位词（相对玩家朝向；**不含任何数值**）
func direction_word(world_position: Vector3) -> StringName:
	if player == null or not is_instance_valid(player):
		return &"附近"
	var local: Vector3 = player.global_transform.affine_inverse() * world_position
	var flat := Vector2(local.x, local.z)      # x = 右, z = 后（Godot 前方是 −Z）
	if flat.length() < 0.05:
		return &"附近"
	var angle := atan2(flat.x, -flat.y)        # 0 = 正前方，+90° = 右侧
	var index := int(round(angle / (PI / 4.0))) % 8
	if index < 0:
		index += 8
	return DIRECTIONS[index]


func _push(text: String, kind: StringName, direction: StringName) -> void:
	subtitle_count += 1
	last_text = text
	last_kind = kind
	last_direction = direction
	visible_until_ms = Time.get_ticks_msec() + TTL_MS
	if hud != null and is_instance_valid(hud) and hud.has_method("show_toast"):
		hud.call("show_toast", text, TTL_MS / 1000.0)


func current_text() -> String:
	return last_text


func is_visible() -> bool:
	return not last_text.is_empty() and Time.get_ticks_msec() <= visible_until_ms


func clear() -> void:
	last_text = ""
	last_kind = &""
	last_direction = &""
	visible_until_ms = 0
