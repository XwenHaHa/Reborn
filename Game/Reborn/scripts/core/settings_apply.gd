class_name SettingsApply
extends RefCounted
## T059：设置 → 运行时的**唯一应用点**（纯函数，不持有状态）。
##
## 为什么要单独一层：音量与字幕各自有出口（`AudioServer` / `SubtitleDirector`），
## 如果 `MainEntry` 在"启动时"和"菜单改动时"各写一遍，必然出现两条分支漂移
## （T055 已经踩过"声音与噪声各写一遍"的坑）。这里把三件事收到一处：
##   ① 主音量 → `AudioServer` 的 Master 总线（8 路 3D 行动音 + 环境音一起生效）
##   ② 字幕   → `SubtitleDirector.enabled`（T056 已有字段）
##   ③ 镜头晃动 → `AnimalBody.camera_shake_enabled`（T059 新增）
##
## 边界：**只动这三样**，不碰任何玩法数值、世界时间或存档。

## Master 总线索引（Godot 默认 `Master` 永远是 0 号）
const MASTER_BUS := 0
## 静音时的音量（`linear_to_db(0)` 是 `-inf`，必须走显式 mute 分支）
const SILENT_DB := -80.0


## 应用主音量（线性 0..1）。返回写进总线的 dB 值，便于断言。
static func apply_volume(volume: float, bus_index: int = MASTER_BUS) -> float:
	var v := clampf(volume, 0.0, 1.0)
	if v <= 0.0:
		AudioServer.set_bus_mute(bus_index, true)
		AudioServer.set_bus_volume_db(bus_index, SILENT_DB)
		return SILENT_DB
	AudioServer.set_bus_mute(bus_index, false)
	var db := linear_to_db(v)
	AudioServer.set_bus_volume_db(bus_index, db)
	return db


## 当前 Master 总线音量（dB）——断言与 HUD 用
static func master_volume_db(bus_index: int = MASTER_BUS) -> float:
	return AudioServer.get_bus_volume_db(bus_index)


static func master_is_muted(bus_index: int = MASTER_BUS) -> bool:
	return AudioServer.is_bus_mute(bus_index)


## 把整份设置应用到运行时。`body` 可空（菜单里没有玩家身体）。
## 返回实际生效的值（测试/日志用）。
static func apply_all(values: Dictionary, tree: SceneTree, body: AnimalBody = null) -> Dictionary:
	var volume := float(values.get(GameSettings.KEY_VOLUME, GameSettings.DEFAULT_VOLUME))
	var db := apply_volume(volume)

	var subs_on := GameSettings.as_bool(values, GameSettings.KEY_SUBTITLES)
	var subs: Node = null
	if tree != null and tree.root != null:
		subs = tree.root.get_node_or_null("SubtitleDirector")
	if subs != null:
		subs.set("enabled", subs_on)

	var shake_on := GameSettings.as_bool(values, GameSettings.KEY_CAMERA_SHAKE)
	if body != null and is_instance_valid(body):
		body.camera_shake_enabled = shake_on

	return {
		"volume": volume,
		"volume_db": db,
		"muted": master_is_muted(),
		"subtitles": subs_on,
		"subtitles_found": subs != null,
		"camera_shake": shake_on,
	}
