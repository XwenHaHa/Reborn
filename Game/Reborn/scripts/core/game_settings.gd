class_name GameSettings
extends RefCounted
## 菜单设置的**读写真源**：`user://settings.cfg`（`ConfigFile`）。
##
## 键（全部在 `[player]` 节）：
##   `sensitivity`  鼠标灵敏度**倍数**（1.0 = `AnimalBody.mouse_sensitivity` 默认 0.0025）
##   `fov`          视野覆盖（0 = 不覆盖物种配置）
##   `volume`       主音量线性 0..1（T059）
##   `camera_shake` 镜头晃动开关 0/1（T059）
##   `subtitles`    关键声音字幕开关 0/1（T059）
##   `hints_seen`   首次操作提示是否已播过 0/1（T059）
##
## 纪律：
## - 只读写本作自己的键，**不碰引擎设置**（不写 `ProjectSettings`、不改全局配置）；
## - 文件缺省/损坏 → 回落默认值并返回默认（不崩、不弹错），由调用方决定是否重建；
## - **缺键回默认**（老档没有 T059 的键也必须能读），数值一律 `sanitize()` 夹紧，
##   避免手改文件把音量调成 7 或把开关写成 0.37；
## - 布尔项统一用 `as_bool()` 读（`>= 0.5` 为真），不在别处各自解释浮点。
##
## 为什么单独一个文件：`MainEntry` 在 `_ready` 读、菜单改动时写，双方都不需要知道路径细节；
## 测试可以传临时路径，不污染真实 `user://settings.cfg`。

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "player"

const KEY_SENSITIVITY := "sensitivity"
const KEY_FOV := "fov"
const KEY_VOLUME := "volume"
const KEY_CAMERA_SHAKE := "camera_shake"
const KEY_SUBTITLES := "subtitles"
const KEY_HINTS_SEEN := "hints_seen"

## 灵敏度是**倍数**（1.0 = `AnimalBody.mouse_sensitivity` 默认 0.0025）
const DEFAULT_SENSITIVITY := 1.0
const SENSITIVITY_MIN := 0.4
const SENSITIVITY_MAX := 3.0
## FOV = 0 表示"不覆盖物种配置里的 `fov`"
const DEFAULT_FOV := 0.0
const FOV_MIN := 60.0
const FOV_MAX := 110.0

## 主音量（线性）。0 = 静音（`AudioServer` 走显式 mute 分支）
const DEFAULT_VOLUME := 1.0
const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0

## 镜头晃动 / 关键声音字幕：默认**开**（策划 :136 要求可关，不是默认关）
const DEFAULT_CAMERA_SHAKE := 1.0
const DEFAULT_SUBTITLES := 1.0
## 首次操作提示默认**没看过**
const DEFAULT_HINTS_SEEN := 0.0


## 读设置。文件不存在/读失败/键缺失 → 该项回落默认值。
static func load_from(path: String = DEFAULT_PATH) -> Dictionary:
	var values := _defaults()
	if path.is_empty():
		return values
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		# `ERR_FILE_NOT_FOUND` 是**正常**情况（第一次运行），不告警
		if err != ERR_FILE_NOT_FOUND:
			push_warning("GameSettings: 读取 %s 失败（%d），使用默认值" % [path, err])
		return values
	for key in values.keys():
		if cfg.has_section_key(SECTION, key):
			values[key] = float(cfg.get_value(SECTION, key))
	return sanitize(values)


## 写设置。返回是否成功（目录不可写时为 false，调用方不应把它当致命错误）。
static func save_to(values: Dictionary, path: String = DEFAULT_PATH) -> bool:
	if path.is_empty():
		return false
	var clean := sanitize(values)
	var cfg := ConfigFile.new()
	# 保留文件里**别人写的**其它节（本作目前没有，但别把将来的键擦掉）
	cfg.load(path)
	for key in clean.keys():
		cfg.set_value(SECTION, key, float(clean[key]))
	var err := cfg.save(path)
	if err != OK:
		push_warning("GameSettings: 写入 %s 失败（%d）" % [path, err])
		return false
	return true


## 全量默认值（新增键只加在这里，`load_from` 的"缺键回默认"自动生效）
static func _defaults() -> Dictionary:
	return {
		KEY_SENSITIVITY: DEFAULT_SENSITIVITY,
		KEY_FOV: DEFAULT_FOV,
		KEY_VOLUME: DEFAULT_VOLUME,
		KEY_CAMERA_SHAKE: DEFAULT_CAMERA_SHAKE,
		KEY_SUBTITLES: DEFAULT_SUBTITLES,
		KEY_HINTS_SEEN: DEFAULT_HINTS_SEEN,
	}


## 夹紧 + 补默认键（幂等）。`fov = 0` 是合法值（= 不覆盖）。
static func sanitize(values: Dictionary) -> Dictionary:
	var out := _defaults()
	if values.has(KEY_SENSITIVITY):
		var s := float(values[KEY_SENSITIVITY])
		if is_finite(s):
			out[KEY_SENSITIVITY] = clampf(s, SENSITIVITY_MIN, SENSITIVITY_MAX)
	if values.has(KEY_FOV):
		var f := float(values[KEY_FOV])
		if is_finite(f):
			out[KEY_FOV] = clampf(f, FOV_MIN, FOV_MAX) if f > 0.0 else DEFAULT_FOV
	if values.has(KEY_VOLUME):
		var v := float(values[KEY_VOLUME])
		if is_finite(v):
			out[KEY_VOLUME] = clampf(v, VOLUME_MIN, VOLUME_MAX)
	for key in [KEY_CAMERA_SHAKE, KEY_SUBTITLES, KEY_HINTS_SEEN]:
		if values.has(key):
			var b := float(values[key])
			if is_finite(b):
				out[key] = 1.0 if b >= 0.5 else 0.0
	return out


## 布尔项的唯一解释口径（`>= 0.5` 为真）。缺键时用该键的默认值。
static func as_bool(values: Dictionary, key: StringName) -> bool:
	var defaults := _defaults()
	var fallback := float(defaults.get(key, 0.0))
	var raw := float(values.get(key, fallback))
	return raw >= 0.5
