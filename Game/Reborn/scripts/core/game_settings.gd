class_name GameSettings
extends RefCounted
## 菜单设置（鼠标灵敏度倍数 / 视野）的**读写真源**：`user://settings.cfg`（`ConfigFile`）。
##
## 纪律：
## - 只读写本作自己的两个键，**不碰引擎设置**（不写 `ProjectSettings`、不改全局配置）；
## - 文件缺省/损坏 → 回落默认值并返回默认（不崩、不弹错），由调用方决定是否重建；
## - 数值一律 `sanitize()` 夹紧，避免手改文件把视野调成负值。
##
## 为什么单独一个文件：`MainEntry` 在 `_ready` 读、菜单改动时写，双方都不需要知道路径细节；
## 测试可以传临时路径，不污染真实 `user://settings.cfg`。

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "player"
const KEY_SENSITIVITY := "sensitivity"
const KEY_FOV := "fov"

## 灵敏度是**倍数**（1.0 = `AnimalBody.mouse_sensitivity` 默认 0.0025）
const DEFAULT_SENSITIVITY := 1.0
const SENSITIVITY_MIN := 0.4
const SENSITIVITY_MAX := 3.0
## FOV = 0 表示"不覆盖物种配置里的 `fov`"
const DEFAULT_FOV := 0.0
const FOV_MIN := 60.0
const FOV_MAX := 110.0


## 读设置。文件不存在/读失败/键缺失 → 该项回落默认值。
static func load_from(path: String = DEFAULT_PATH) -> Dictionary:
	var values := {
		KEY_SENSITIVITY: DEFAULT_SENSITIVITY,
		KEY_FOV: DEFAULT_FOV,
	}
	if path.is_empty():
		return values
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		# `ERR_FILE_NOT_FOUND` 是**正常**情况（第一次运行），不告警
		if err != ERR_FILE_NOT_FOUND:
			push_warning("GameSettings: 读取 %s 失败（%d），使用默认值" % [path, err])
		return values
	if cfg.has_section_key(SECTION, KEY_SENSITIVITY):
		values[KEY_SENSITIVITY] = float(cfg.get_value(SECTION, KEY_SENSITIVITY))
	if cfg.has_section_key(SECTION, KEY_FOV):
		values[KEY_FOV] = float(cfg.get_value(SECTION, KEY_FOV))
	return sanitize(values)


## 写设置。返回是否成功（目录不可写时为 false，调用方不应把它当致命错误）。
static func save_to(values: Dictionary, path: String = DEFAULT_PATH) -> bool:
	if path.is_empty():
		return false
	var clean := sanitize(values)
	var cfg := ConfigFile.new()
	# 保留文件里**别人写的**其它节（本作目前没有，但别把将来的键擦掉）
	cfg.load(path)
	cfg.set_value(SECTION, KEY_SENSITIVITY, float(clean[KEY_SENSITIVITY]))
	cfg.set_value(SECTION, KEY_FOV, float(clean[KEY_FOV]))
	var err := cfg.save(path)
	if err != OK:
		push_warning("GameSettings: 写入 %s 失败（%d）" % [path, err])
		return false
	return true


## 夹紧 + 补默认键（幂等）。`fov = 0` 是合法值（= 不覆盖）。
static func sanitize(values: Dictionary) -> Dictionary:
	var out := {
		KEY_SENSITIVITY: DEFAULT_SENSITIVITY,
		KEY_FOV: DEFAULT_FOV,
	}
	if values.has(KEY_SENSITIVITY):
		var s := float(values[KEY_SENSITIVITY])
		if is_finite(s):
			out[KEY_SENSITIVITY] = clampf(s, SENSITIVITY_MIN, SENSITIVITY_MAX)
	if values.has(KEY_FOV):
		var f := float(values[KEY_FOV])
		if is_finite(f):
			out[KEY_FOV] = clampf(f, FOV_MIN, FOV_MAX) if f > 0.0 else DEFAULT_FOV
	return out
