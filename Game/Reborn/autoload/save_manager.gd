extends Node

const GameClock := preload("res://scripts/core/game_clock.gd")


## 存档持久化（T037 格式 + T038 写入队列）：快照组装、纯数据编码、校验修复、原子写与坏档恢复。
##
## 依据：`Docs/TechnicalDesign.md` §3（`WorldSnapshot` 契约与校验规则）、§8；
## `Docs/Tasks/T037.md`（D1～D10）、`Docs/Tasks/T038.md`（D1～D10）。
##
## 边界（D1）：
## - 本节点**只碰数据与文件**：不建角色、不碰关卡；读档后的场景重建在 `MainEntry.apply_saved_snapshot()`。
## - 存档落在 `user://`（单槽），不含个人目录、令牌或设备信息（D2）。
## - 根目录/测试可 `set_save_path()` 指向临时路径；真实档不会被测试触碰（D10）。
##
## 文件布局（D2/T038 D6）：
## - 主档 `user://savegame_v1.json`（JSON 文本）
## - 上一版 `user://savegame_v1.bak`（每次成功覆盖前复制；复制失败不阻断本次写）
## - 隔离坏档 `user://savegame_v1.corrupt-<unix>`（只改名，不删除）
## - 写入临时 `*.tmp` / 替换中间 `*.old` / 备份中间 `*.bak.tmp`（失败路径全部清理）

const SAVE_VERSION := 1
const DEFAULT_PATH := "user://savegame_v1.json"
## 契约键（TD §3，10 项）
const CONTRACT_KEYS: Array[String] = ["save_version", "revision", "world_time", "resources",
	"regions", "discovered_ids", "unlocked_species", "life_records", "current_life",
	"pending_settlement_life_id"]
## 实现扩展键（T037 D3；`saved_reason` 只写不读，属诊断）
const EXTENSION_KEYS: Array[String] = ["events", "life_counter", "event_seq", "saved_reason"]
## 集合类字段：缺失时补默认值并记修复（D7）
const COLLECTION_KEYS: Array[String] = ["resources", "regions", "discovered_ids",
	"unlocked_species", "life_records", "events"]

## 主档路径（测试可改）
var save_path: String = DEFAULT_PATH
## 已成功写入的版本号（读档后从快照续上）
var revision: int = 0
## "死亡已归档、结算页尚未展示"（T037 D4）。由 `MainEntry` 设置。
var pending_settlement_life_id: String = ""
## 无头测试/工具默认不允许自动写（防止污染真实 `user://`）
var allow_headless_writes: bool = false
## 总开关（工具可关）
var write_enabled: bool = true
var last_status: String = "none"
var last_message: String = ""
var last_repairs: Array = []
var last_reason: String = ""
## T039 D2/D9：本次读档实际隔离的文件（绝对/`user://` 原路径 → `.corrupt-*`）。
var last_quarantine: Array[String] = []

## T038 D4：普通保存节流窗口（秒）。关键事务/退出不受此限。
var throttle_seconds: float = 1.0
## T038 D7：仅测试设置；生产恒空。`tmp_open` / `disk_write` / `bak_copy` / `rename`。
var fault_injection: String = ""
## T039 D6：仅测试的可控延迟钩子（为真机强杀扩窗）；生产恒空/0。
## `before_tmp` / `tmp_mid` / `rename_gap` / `bak_rotate`。
var write_delay_phase: String = ""
var write_delay_ms: int = 0
## 最近一次备份失败（主档已写成功）的玩家文案；成功且无警告时清空。
var last_warning: String = ""
var last_failure_reason: String = ""
var last_failure_message: String = ""
var last_write_reason: String = ""

# T038 D2/D3：单写入队列（主线程帧驱动，无线程）。
var _pending_normal: bool = false
var _pending_reason: StringName = &""
var _critical_queue: Array[StringName] = []
var _writing: bool = false
var _active_writes: int = 0
var _max_active_writes: int = 0
var _last_normal_write_ms: int = -1000000
var _write_log: Array[String] = []
var _stats: Dictionary = {}


func _ready() -> void:
	set_process(false)


## 队列统计（T038 D9）；`threaded=false` 明示本实现为主线程串行。
func _reset_queue_state() -> void:
	_pending_normal = false
	_pending_reason = &""
	_critical_queue.clear()
	_writing = false
	_active_writes = 0
	_max_active_writes = 0
	_last_normal_write_ms = -1000000
	_write_log.clear()
	_stats = {"queued": 0, "coalesced": 0, "dropped_normal": 0, "written": 0,
		"failed": 0, "warnings": 0, "critical_written": 0}
	set_process(false)


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


## 是否允许本次写入/读取（D9/D10：无头默认关闭，测试显式打开）
func is_active() -> bool:
	return write_enabled and (not _headless() or allow_headless_writes)


func set_save_path(path: String) -> void:
	save_path = path
	revision = 0
	pending_settlement_life_id = ""
	last_status = "none"
	last_message = ""
	last_repairs = []
	last_warning = ""
	last_failure_reason = ""
	last_failure_message = ""
	last_write_reason = ""
	fault_injection = ""
	last_quarantine.clear()
	write_delay_phase = ""
	write_delay_ms = 0
	_reset_queue_state()


func backup_path() -> String:
	return save_path + ".bak"


func tmp_path() -> String:
	return save_path + ".tmp"


func snapshot_exists() -> bool:
	return FileAccess.file_exists(save_path)


## T041：清空当前槽（主档 / 备份 / 写入中间文件）。`.corrupt-*` 隔离档**保留**，
## 供证据与人工恢复；不碰任何真实用户目录之外的内容。
func clear_slot() -> void:
	for p in [save_path, backup_path(), tmp_path(), save_path + ".old", backup_path() + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	revision = 0
	pending_settlement_life_id = ""
	last_status = "none"
	last_message = ""
	last_repairs = []
	last_warning = ""
	last_failure_reason = ""
	last_failure_message = ""
	last_write_reason = ""
	last_quarantine.clear()


# ---------------------------------------------------------------------------
# 快照组装（只读 autoload 与场景资源点，不写任何东西）
# ---------------------------------------------------------------------------

## 组装下一版快照（**已编码为 JSON 纯数据**：Transform3D/Vector3/StringName 都转成可逆标记）。
func build_snapshot(reason: StringName = &"manual") -> Dictionary:
	var gs := get_node_or_null("/root/GameState")
	var wd := get_node_or_null("/root/WorldDirector")
	var long_term: Dictionary = {}
	if gs != null and gs.has_method("snapshot_long_term"):
		long_term = gs.call("snapshot_long_term")
	var regions: Array = []
	if wd != null and wd.has_method("region_population_snapshot"):
		regions = wd.call("region_population_snapshot")
	var snap := {
		"save_version": SAVE_VERSION,
		"revision": revision + 1,
		"world_time": float(wd.get("world_time")) if wd != null else 0.0,
		"resources": _collect_resources(),
		"regions": regions,
		"discovered_ids": long_term.get("discovered_ids", []),
		"unlocked_species": long_term.get("unlocked_species", []),
		"life_records": long_term.get("life_records", []),
		"current_life": long_term.get("current_life", {}),
		"pending_settlement_life_id": pending_settlement_life_id,
		"events": long_term.get("events", []),
		"life_counter": int(long_term.get("life_counter", 0)),
		"event_seq": int(long_term.get("event_seq", 0)),
		"saved_reason": String(reason),
	}
	return _pack(snap)


## 场景里所有资源点的记录（按稳定 ID 排序，保证重复保存可比）。
func _collect_resources() -> Array:
	var out: Array = []
	var tree := get_tree()
	if tree == null:
		return out
	for node in tree.get_nodes_in_group(&"resource_points"):
		if node is ResourcePoint and node.has_method("to_record"):
			out.append((node as ResourcePoint).call("to_record"))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", "")))
	return _pack(out)


# ---------------------------------------------------------------------------
# 写队列（T038 D2～D5）与原子写（T038 D6）
# ---------------------------------------------------------------------------

## 立即存档（底层同步 API，测试/工具用）。仍走单写守卫，返回 `{ok, status, ...}`。
func save_game(reason: StringName = &"manual") -> Dictionary:
	return _perform_write(reason, true)


## 入队。`critical=true`：死亡/结算清空/发现/解锁/退出 —— 立即同步排空、不合并不丢弃；
## 普通请求：帧驱动、节流窗口内合并。返回 `{queued, coalesced, status, revision, ...}`。
func request_save(reason: StringName = &"manual", critical: bool = false,
		bypass_throttle: bool = true) -> Dictionary:
	if not is_active():
		last_status = "disabled"
		last_message = "存档写入已禁用（无头或工具环境）"
		return {"ok": false, "queued": false, "status": "disabled", "revision": revision,
			"message": last_message}
	if critical:
		# 关键事务吸收尚未落盘的普通请求（普通请求可丢弃，关键不可）。
		if _pending_normal:
			_pending_normal = false
			_stats["dropped_normal"] = int(_stats.get("dropped_normal", 0)) + 1
		_stats["queued"] = int(_stats.get("queued", 0)) + 1
		if _writing:
			_critical_queue.append(reason)
			return {"ok": false, "queued": true, "status": "queued", "revision": revision}
		_critical_queue.append(reason)
		return _drain_critical()
	var coalesced := _pending_normal
	if coalesced:
		_stats["coalesced"] = int(_stats.get("coalesced", 0)) + 1
	else:
		_stats["queued"] = int(_stats.get("queued", 0)) + 1
	_pending_normal = true
	_pending_reason = reason
	set_process(true)
	if bypass_throttle:
		return flush_queue_now()
	return {"ok": false, "queued": true, "coalesced": coalesced,
		"status": last_status, "revision": revision}


## 立即排空队列（退出用）：先写 pending 普通，再按 FIFO 写关键；仍逐条串行。
func flush_queue_now() -> Dictionary:
	if not is_active():
		return {"ok": false, "status": "disabled", "revision": revision}
	var last: Dictionary = {"ok": false, "status": "none", "revision": revision}
	if _pending_normal and not _writing:
		var pending_reason := _pending_reason
		_pending_normal = false
		last = _perform_write(pending_reason, false)
	if not _writing and not _critical_queue.is_empty():
		last = _drain_critical()
	return last


func _drain_critical() -> Dictionary:
	var last: Dictionary = {"ok": false, "status": "none", "revision": revision}
	while not _critical_queue.is_empty():
		if _writing:
			break
		var reason: StringName = _critical_queue.pop_front()
		last = _perform_write(reason, true)
	return last


## 帧驱动：只在有普通请求且节流窗口到期时写一次（T038 D4/D5）。
func _process(_delta: float) -> void:
	if not _pending_normal:
		set_process(false)
		return
	if _writing:
		return
	var now := GameClock.now_ms()
	if now - _last_normal_write_ms < int(throttle_seconds * 1000.0):
		return
	var pending_reason := _pending_reason
	_pending_normal = false
	_perform_write(pending_reason, false)
	if not _pending_normal:
		set_process(false)


## 单写守卫包装：任何路径都复位 `_writing/active_writes`，失败不锁死队列（D5/D9）。
func _perform_write(reason: StringName, critical: bool) -> Dictionary:
	if _writing:
		if critical:
			_critical_queue.push_front(reason)
		else:
			_pending_normal = true
			_pending_reason = reason
		return {"ok": false, "status": "busy", "queued": true, "revision": revision}
	_writing = true
	_active_writes += 1
	_max_active_writes = maxi(_max_active_writes, _active_writes)
	_write_log.append("start|%s" % String(reason))
	var result := _write_snapshot(reason)
	_active_writes -= 1
	_writing = false
	_write_log.append("end|%s|%s" % [String(reason), String(result.get("status", ""))])
	last_reason = String(reason)
	last_write_reason = String(reason)
	if bool(result.get("ok", false)):
		_stats["written"] = int(_stats.get("written", 0)) + 1
		if critical:
			_stats["critical_written"] = int(_stats.get("critical_written", 0)) + 1
		last_status = "ok"
		var warn := String(result.get("warning", ""))
		last_warning = warn
		last_message = warn
		if warn != "":
			_stats["warnings"] = int(_stats.get("warnings", 0)) + 1
	else:
		_stats["failed"] = int(_stats.get("failed", 0)) + 1
		last_status = String(result.get("status", "write_failed"))
		last_message = String(result.get("message", ""))
		last_failure_reason = String(reason)
		last_failure_message = last_message
	if not critical:
		_last_normal_write_ms = GameClock.now_ms()
	return result


## 真正的磁盘写入：tmp → 刷新 .bak → 主档换名（失败回滚）→ 成功才 `revision+1`。
func _write_snapshot(reason: StringName) -> Dictionary:
	_test_pause("before_tmp")
	last_repairs = []
	var snap := build_snapshot(reason)
	var text := JSON.stringify(snap)
	var dir_path := save_path.get_base_dir()
	if dir_path != "" and not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var tmp := tmp_path()
	if fault_injection == "tmp_open":
		return _write_fail("存档写入失败：无法创建临时文件（注入）")
	_remove_if_exists(tmp)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _write_fail("存档写入失败：无法创建临时文件（%s）" % FileAccess.get_open_error())
	f.store_string(text)
	f.flush()
	_test_pause("tmp_mid")
	f.close()
	if fault_injection == "disk_write":
		_remove_if_exists(tmp)
		return _write_fail("存档写入失败：磁盘写入失败（注入）")

	var warning := ""
	if FileAccess.file_exists(save_path):
		warning = _refresh_backup()

	# 主档替换：先改名到 .old，成功换入 tmp 后才删除；失败回滚（T038 D6）。
	var old_path := save_path + ".old"
	_remove_if_exists(old_path)
	var had_main := FileAccess.file_exists(save_path)
	if had_main:
		var move_err := DirAccess.rename_absolute(save_path, old_path)
		if move_err != OK:
			_remove_if_exists(tmp)
			return _write_fail("存档写入失败：无法替换主档（%d）" % move_err)
		_test_pause("rename_gap")
	var rename_err := ERR_FILE_CANT_WRITE
	if fault_injection != "rename":
		rename_err = DirAccess.rename_absolute(tmp, save_path)
	if rename_err != OK:
		if had_main:
			DirAccess.rename_absolute(old_path, save_path)
		_remove_if_exists(tmp)
		return _write_fail("存档写入失败：无法替换主档（%d）" % rename_err)
	if had_main:
		_remove_if_exists(old_path)
	revision += 1
	return {"ok": true, "status": "ok", "path": save_path, "revision": revision,
		"reason": String(reason), "warning": warning, "repairs": [], "message": warning}


## 刷新 `.bak`：复制主档到 `.bak.tmp`，再轮换旧 `.bak`。失败不阻断本次写（D6/D8）。
func _refresh_backup() -> String:
	var bak := backup_path()
	var btmp := bak + ".tmp"
	var bprev := bak + ".prev"
	_remove_if_exists(btmp)
	var copy_err := DirAccess.copy_absolute(save_path, btmp)
	if fault_injection == "bak_copy":
		copy_err = ERR_FILE_CANT_WRITE
	if copy_err != OK:
		_remove_if_exists(btmp)
		last_repairs.append("backup_failed:%d" % copy_err)
		return "存档已保存（备份更新失败）"
	_test_pause("bak_rotate")
	var moved_prev := false
	if FileAccess.file_exists(bak):
		if DirAccess.rename_absolute(bak, bprev) != OK:
			_remove_if_exists(btmp)
			return "存档已保存（备份更新失败）"
		moved_prev = true
	if DirAccess.rename_absolute(btmp, bak) != OK:
		if moved_prev:
			DirAccess.rename_absolute(bprev, bak)
		_remove_if_exists(btmp)
		return "存档已保存（备份更新失败）"
	if moved_prev:
		_remove_if_exists(bprev)
	return ""


func _write_fail(message: String) -> Dictionary:
	return {"ok": false, "status": "write_failed", "path": save_path,
		"revision": revision, "repairs": [], "message": message}


## T039 D6：仅测试用的可控延迟（生产 `write_delay_phase` 为空、`write_delay_ms=0`）。
## 打印标记供 `Tools/CaptureRun.ps1` 的外部监视器在指定阶段强杀进程。
func _test_pause(phase: String) -> void:
	if write_delay_phase != phase or write_delay_ms <= 0:
		return
	print("T039|phase|%s|begin" % phase)
	OS.delay_msec(write_delay_ms)
	print("T039|phase|%s|end" % phase)


## 队列可观测（T038 D9）；`threaded=false` 明示主线程串行实现。
func queue_length() -> int:
	return (1 if _pending_normal else 0) + _critical_queue.size()


func pending_reasons() -> Array:
	var out: Array = []
	if _pending_normal:
		out.append(String(_pending_reason))
	for reason in _critical_queue:
		out.append(String(reason))
	return out


func queue_stats() -> Dictionary:
	var st: Dictionary = _stats.duplicate(true)
	st["active_writes"] = _active_writes
	st["max_active_writes"] = _max_active_writes
	st["last_failure_reason"] = last_failure_reason
	st["last_write_reason"] = last_write_reason
	st["last_warning"] = last_warning
	st["threaded"] = false
	st["write_log"] = _write_log.duplicate()
	return st


# ---------------------------------------------------------------------------
# 读 + 校验 + 损坏恢复（D5/D7）
# ---------------------------------------------------------------------------

## 读档并校验。返回 `{status, snapshot, repairs, message}`。
## status：`ok` / `none` / `corrupt` / `version_mismatch` / `recovered_backup` / `disabled`。
func load_game() -> Dictionary:
	last_repairs = []
	last_message = ""
	last_quarantine.clear()
	if not is_active():
		last_status = "disabled"
		return {"status": "disabled", "snapshot": {}, "repairs": [],
			"message": "存档读取已禁用（无头或工具环境）"}
	if not FileAccess.file_exists(save_path):
		# T038 D6 / T039 D4：主档缺失（替换窗口崩溃/被外部删除）时按 `.bak` 判定。
		return _recover_missing_main()
	var parsed: Variant = _read_json(save_path)
	if parsed == null:
		# D7：解析失败（截断/非 JSON）同样先隔离，再从 `.bak` 尝试恢复。
		_quarantine_main()
		return _recover_from_backup("主存档无法解析（损坏或截断）")
	var checked := validate(parsed)
	if checked.get("status") == "ok":
		var snap: Dictionary = checked.get("snapshot", {})
		revision = int(snap.get("revision", revision))
		last_status = "ok"
		last_repairs = checked.get("repairs", [])
		last_message = _repairs_message(last_repairs)
		return checked
	if checked.get("status") == "version_mismatch":
		# 版本不兼容：不隔离、不覆盖、不回退（D5）。
		last_status = "version_mismatch"
		last_message = checked.get("message", "存档版本不兼容，未载入")
		return {"status": "version_mismatch", "snapshot": {}, "repairs": [],
			"message": last_message}
	# corrupt
	_quarantine_main()
	return _recover_from_backup("主存档结构损坏")


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	return JSON.parse_string(text)


## 主档缺失但 `.bak` 存在：完整则回退；损坏则隔离并报 corrupt（T039 D4，不再静默 none）。
func _recover_missing_main() -> Dictionary:
	var bak := backup_path()
	if not FileAccess.file_exists(bak):
		last_status = "none"
		last_message = ""
		return {"status": "none", "snapshot": {}, "repairs": [], "message": ""}
	var parsed: Variant = _read_json(bak)
	if parsed == null:
		_quarantine_file(bak)
		return _corrupt_result()
	var checked := validate(parsed)
	if checked.get("status") != "ok":
		if checked.get("status") == "corrupt":
			_quarantine_file(bak)
			return _corrupt_result()
		# version_mismatch：不隔离、不载入（T037 D5 口径保持）。
		last_status = "none"
		last_message = ""
		return {"status": "none", "snapshot": {}, "repairs": [], "message": ""}
	var snap: Dictionary = checked.get("snapshot", {})
	revision = int(snap.get("revision", revision))
	last_status = "recovered_backup"
	last_repairs = checked.get("repairs", [])
	last_message = "主存档缺失，已从备份恢复"
	if not last_repairs.is_empty():
		last_message += "（并修复 %d 处）" % last_repairs.size()
	return {"status": "recovered_backup", "snapshot": snap,
		"repairs": last_repairs, "message": last_message}


## 主档坏：改名隔离（不删除），尝试从 `.bak` 恢复；`.bak` 也坏则一并隔离（T039 D2/D3）。
func _recover_from_backup(reason: String) -> Dictionary:
	var repairs := [reason]
	var parsed: Variant = _read_json(backup_path())
	if parsed != null:
		var checked := validate(parsed)
		if checked.get("status") == "ok":
			var snap: Dictionary = checked.get("snapshot", {})
			revision = int(snap.get("revision", revision))
			var all_repairs := repairs.duplicate()
			all_repairs.append_array(checked.get("repairs", []))
			last_status = "recovered_backup"
			last_repairs = all_repairs
			last_message = "主存档损坏，已从备份恢复"
			if all_repairs.size() > 1:
				last_message += "（并修复 %d 处）" % (all_repairs.size() - 1)
			return {"status": "recovered_backup", "snapshot": snap,
				"repairs": all_repairs, "message": last_message}
		if checked.get("status") == "corrupt":
			_quarantine_file(backup_path())
	elif FileAccess.file_exists(backup_path()):
		_quarantine_file(backup_path())
	last_repairs = repairs
	return _corrupt_result()


## 双坏 / 无备份可用的统一结果（T039 D3）。
func _corrupt_result() -> Dictionary:
	last_status = "corrupt"
	last_message = "存档损坏，已隔离；未载入"
	return {"status": "corrupt", "snapshot": {}, "repairs": last_repairs.duplicate(),
		"message": last_message}


func _quarantine_main() -> void:
	_quarantine_file(save_path)


## 把损坏源改名到 `<原路径>.corrupt-<unix>`（同名追加 `-1/-2…`）；失败保留原文件、不删除。
## 返回隔离目标路径；未隔离返回空串。
func _quarantine_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var stamp := int(Time.get_unix_time_from_system())
	var target := "%s.corrupt-%d" % [path, stamp]
	var n := 1
	while FileAccess.file_exists(target):
		target = "%s.corrupt-%d-%d" % [path, stamp, n]
		n += 1
	var err := DirAccess.rename_absolute(path, target)
	if err != OK:
		# 改名失败（只读等）时保留原文件——不做删除（D7）。
		last_repairs.append("quarantine_failed:%d" % err)
		return ""
	last_repairs.append("quarantined:%s" % target.get_file())
	last_quarantine.append(target)
	return target


# ---------------------------------------------------------------------------
# 校验（D7：结构/版本/缺失/非法值四类）
# ---------------------------------------------------------------------------

## 校验已解析的 JSON（packed 或 native 均可）。返回 `{status, snapshot, repairs, message}`。
## `snapshot` 是**逆向解码后的原生字典**（Transform3D/Vector3 已还原）。
func validate(raw: Variant) -> Dictionary:
	var parsed: Variant = _unpack(raw)
	if not (parsed is Dictionary):
		return {"status": "corrupt", "snapshot": {}, "repairs": ["not_dictionary"],
			"message": "存档结构损坏（根节点不是字典）"}
	var src: Dictionary = parsed
	if not src.has("save_version"):
		return {"status": "corrupt", "snapshot": {}, "repairs": ["missing_save_version"],
			"message": "存档缺少版本号"}
	var version: Variant = src.get("save_version")
	if not (version is int or version is float):
		return {"status": "corrupt", "snapshot": {}, "repairs": ["bad_save_version"],
			"message": "存档版本号非法"}
	if version is float and (not is_finite(version) or float(version) != floor(float(version))):
		return {"status": "corrupt", "snapshot": {}, "repairs": ["bad_save_version"],
			"message": "存档版本号非法"}
	if int(version) != SAVE_VERSION:
		return {"status": "version_mismatch", "snapshot": {}, "repairs": [],
			"message": "存档版本不兼容（v%d），未载入" % int(version)}

	var repairs: Array[String] = []
	# D7：集合类字段缺失 → 补默认值并记修复。
	for key in COLLECTION_KEYS:
		if not src.has(key):
			repairs.append("missing:%s" % key)
	var world_time := _finite(src.get("world_time", 0.0), "world_time", 0.0, repairs)
	var rev := maxi(0, int(_finite(src.get("revision", 0.0), "revision", 0.0, repairs)))
	var resources := _validate_resources(src.get("resources", []), repairs)
	var regions := _validate_regions(src.get("regions", []), repairs)
	var discovered := _string_list(src.get("discovered_ids", []), "discovered_ids", repairs)
	var unlocked := _string_list(src.get("unlocked_species", []), "unlocked_species", repairs)
	discovered.sort()
	unlocked.sort()
	var records := _validate_records(src.get("life_records", []), repairs)
	var events := _validate_events(src.get("events", []), repairs)
	var counters := _validate_counters(src, records, events, repairs)
	var current := _validate_current_life(src.get("current_life", {}), repairs)
	var pending := String(src.get("pending_settlement_life_id", ""))
	if pending != "" and not _has_record(records, pending):
		repairs.append("pending_without_record:%s" % pending)
		pending = ""
	if pending != "" and not current.is_empty():
		# 契约互斥：进行中生命与"死亡待展示结算页"不能同时成立。
		repairs.append("pending_with_current_life")
		pending = ""
	var saved_reason := String(src.get("saved_reason", ""))

	var snap := {
		"save_version": SAVE_VERSION,
		"revision": rev,
		"world_time": world_time,
		"resources": resources,
		"regions": regions,
		"discovered_ids": discovered,
		"unlocked_species": unlocked,
		"life_records": records,
		"current_life": current,
		"pending_settlement_life_id": pending,
		"events": events,
		"life_counter": counters.get("life_counter", 0),
		"event_seq": counters.get("event_seq", 0),
		"saved_reason": saved_reason,
	}
	return {"status": "ok", "snapshot": snap, "repairs": repairs,
		"message": _repairs_message(repairs)}


func _validate_resources(value: Variant, repairs: Array[String]) -> Array:
	var out: Array = []
	if not (value is Array):
		repairs.append("resources:not_array")
		return out
	for item in (value as Array):
		if not (item is Dictionary):
			repairs.append("resources:skip_non_dict")
			continue
		var d: Dictionary = item
		var id := String(d.get("id", ""))
		if id == "":
			repairs.append("resources:skip_no_id")
			continue
		var cap := maxi(0, int(_finite(d.get("capacity", 0.0), "resources.capacity", 0.0, repairs)))
		var units := maxi(0, int(_finite(d.get("units", 0.0), "resources.units", 0.0, repairs)))
		if units > cap:
			units = cap
			repairs.append("resources:clamp_units:%s" % id)
		var kind := String(d.get("kind", "food"))
		if kind != "food" and kind != "water":
			repairs.append("resources:bad_kind:%s" % id)
			kind = "food"
		var xform: Variant = _as_transform(d.get("transform", null))
		if xform == null:
			repairs.append("resources:bad_transform:%s" % id)
			xform = Transform3D()
		out.append({
			"id": id,
			"region_id": String(d.get("region_id", "")),
			"kind": kind,
			"food_type": int(d.get("food_type", 0)),
			"units": units,
			"capacity": cap,
			"next_refill_at": _finite(d.get("next_refill_at", 0.0), "resources.next_refill_at", 0.0, repairs),
			"refill_interval": maxf(0.0, _finite(d.get("refill_interval", 0.0), "resources.refill_interval", 0.0, repairs)),
			"transform": xform,
			"expire_at": maxf(0.0, _finite(d.get("expire_at", 0.0), "resources.expire_at", 0.0, repairs)),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", "")))
	if out.size() != (value as Array).size():
		repairs.append("resources:dropped=%d" % [(value as Array).size() - out.size()])
	return out


func _validate_regions(value: Variant, repairs: Array[String]) -> Array:
	var out: Array = []
	if not (value is Array):
		repairs.append("regions:not_array")
		return out
	for item in (value as Array):
		if not (item is Dictionary):
			repairs.append("regions:skip_non_dict")
			continue
		var d: Dictionary = item
		var rid := String(d.get("region_id", ""))
		var sid := String(d.get("species_id", ""))
		if rid == "" or sid == "":
			repairs.append("regions:skip_no_id")
			continue
		var cap := maxi(0, int(_finite(d.get("capacity", 0.0), "regions.capacity", 0.0, repairs)))
		var total := maxi(0, int(_finite(d.get("total_count", 0.0), "regions.total_count", 0.0, repairs)))
		if total > cap:
			total = cap
			repairs.append("regions:clamp_total:%s/%s" % [rid, sid])
		out.append({
			"region_id": rid,
			"species_id": sid,
			"total_count": total,
			"capacity": cap,
			"next_recover_at": _finite(d.get("next_recover_at", 0.0), "regions.next_recover_at", 0.0, repairs),
			"recover_interval": maxf(0.0, _finite(d.get("recover_interval", 0.0), "regions.recover_interval", 0.0, repairs)),
		})
	return out


func _validate_records(value: Variant, repairs: Array[String]) -> Array:
	var out: Array = []
	if not (value is Array):
		repairs.append("life_records:not_array")
		return out
	var seen := {}
	for item in (value as Array):
		if not (item is Dictionary):
			repairs.append("life_records:skip_non_dict")
			continue
		var d: Dictionary = item
		var lid := String(d.get("life_id", ""))
		if lid == "" or seen.has(lid):
			repairs.append("life_records:skip_bad_id")
			continue
		seen[lid] = true
		var rec := d.duplicate(true)
		rec["life_id"] = lid
		rec["species_id"] = String(d.get("species_id", ""))
		rec["duration"] = maxf(0.0, _finite(d.get("duration", 0.0), "life_records.duration", 0.0, repairs))
		rec["start_world_time"] = _finite(d.get("start_world_time", 0.0), "life_records.start_world_time", 0.0, repairs)
		rec["end_world_time"] = _finite(d.get("end_world_time", 0.0), "life_records.end_world_time", 0.0, repairs)
		rec["captures"] = maxi(0, int(_finite(d.get("captures", 0.0), "life_records.captures", 0.0, repairs)))
		rec["escapes"] = maxi(0, int(_finite(d.get("escapes", 0.0), "life_records.escapes", 0.0, repairs)))
		rec["food_gained"] = maxf(0.0, _finite(d.get("food_gained", 0.0), "life_records.food_gained", 0.0, repairs))
		rec["water_gained"] = maxf(0.0, _finite(d.get("water_gained", 0.0), "life_records.water_gained", 0.0, repairs))
		rec["end_reason"] = String(d.get("end_reason", ""))
		rec["damage_reason"] = String(d.get("damage_reason", ""))
		rec["discoveries"] = _string_list(d.get("discoveries", []), "life_records.discoveries", repairs)
		rec["snapshot"] = _validate_survival(d.get("snapshot", {}), repairs)
		rec["start_position"] = _as_vector3(d.get("start_position", null))
		rec["transform"] = _as_transform(d.get("transform", null))
		out.append(rec)
	return out


func _validate_events(value: Variant, repairs: Array[String]) -> Array:
	var out: Array = []
	if not (value is Array):
		repairs.append("events:not_array")
		return out
	for item in (value as Array):
		if not (item is Dictionary):
			repairs.append("events:skip_non_dict")
			continue
		var d: Dictionary = item
		var seq := int(_finite(d.get("seq", -1.0), "events.seq", -1.0, repairs))
		var kind := String(d.get("kind", ""))
		if seq <= 0 or kind == "":
			repairs.append("events:skip_bad_entry")
			continue
		var data: Variant = d.get("data", {})
		if not (data is Dictionary):
			repairs.append("events:data_not_dict:%d" % seq)
			data = {}
		out.append({
			"seq": seq,
			"life_id": String(d.get("life_id", "")),
			"kind": kind,
			"world_time": _finite(d.get("world_time", 0.0), "events.world_time", 0.0, repairs),
			"data": (data as Dictionary).duplicate(true),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("seq", 0)) < int(b.get("seq", 0)))
	return out


func _validate_counters(src: Dictionary, records: Array, events: Array,
		repairs: Array[String]) -> Dictionary:
	var life_counter := maxi(0, int(_finite(src.get("life_counter", 0.0), "life_counter", 0.0, repairs)))
	var event_seq := maxi(0, int(_finite(src.get("event_seq", 0.0), "event_seq", 0.0, repairs)))
	# 反推下界：档案里出现的最大 L 编号 / 事件最大 seq（防止读档后重号）。
	var max_life := 0
	for rec in records:
		var lid := String((rec as Dictionary).get("life_id", ""))
		if lid.begins_with("L"):
			max_life = maxi(max_life, lid.substr(1).to_int())
	var max_seq := 0
	for e in events:
		max_seq = maxi(max_seq, int((e as Dictionary).get("seq", 0)))
	if life_counter < max_life:
		life_counter = max_life
		repairs.append("life_counter:raised_to_max")
	if event_seq < max_seq:
		event_seq = max_seq
		repairs.append("event_seq:raised_to_max")
	return {"life_counter": life_counter, "event_seq": event_seq}


func _validate_current_life(value: Variant, repairs: Array[String]) -> Dictionary:
	if not (value is Dictionary):
		if value != null and value != {}:
			repairs.append("current_life:not_dict")
		return {}
	var d: Dictionary = value
	if d.is_empty():
		return {}
	var lid := String(d.get("life_id", ""))
	var sid := String(d.get("species_id", ""))
	if lid == "" or sid == "":
		repairs.append("current_life:invalid_ids")
		return {}
	var life := d.duplicate(true)
	life["life_id"] = lid
	life["species_id"] = sid
	life["start_world_time"] = _finite(d.get("start_world_time", 0.0), "current_life.start_world_time", 0.0, repairs)
	life["snapshot"] = _validate_survival(d.get("snapshot", {}), repairs)
	var health := float(life["snapshot"].get("health", 100.0)) if life["snapshot"] is Dictionary else 100.0
	if health <= 0.0:
		repairs.append("current_life:dead_state_dropped")
		return {}
	var xform: Variant = _as_transform(d.get("transform", null))
	if xform == null:
		var pos: Variant = _as_vector3(d.get("start_position", null))
		xform = Transform3D(Basis(), pos if pos != null else Vector3.ZERO)
		repairs.append("current_life:transform_defaulted")
	life["transform"] = xform
	life["start_position"] = _as_vector3(d.get("start_position", null))
	life["captures"] = maxi(0, int(_finite(d.get("captures", 0.0), "current_life.captures", 0.0, repairs)))
	life["escapes"] = maxi(0, int(_finite(d.get("escapes", 0.0), "current_life.escapes", 0.0, repairs)))
	life["food_gained"] = maxf(0.0, _finite(d.get("food_gained", 0.0), "current_life.food_gained", 0.0, repairs))
	life["water_gained"] = maxf(0.0, _finite(d.get("water_gained", 0.0), "current_life.water_gained", 0.0, repairs))
	life["discoveries"] = _string_list(d.get("discoveries", []), "current_life.discoveries", repairs)
	life["event_first"] = maxi(0, int(_finite(d.get("event_first", 0.0), "current_life.event_first", 0.0, repairs)))
	life["event_last"] = maxi(0, int(_finite(d.get("event_last", 0.0), "current_life.event_last", 0.0, repairs)))
	# `last_safe_spot_id` 属 T042：v1 预留，读到也不会写入（D7/规格 §9）。
	return life


func _validate_survival(value: Variant, repairs: Array[String]) -> Dictionary:
	if not (value is Dictionary):
		if value != null and value != {}:
			repairs.append("snapshot:not_dict")
		return {}
	var d: Dictionary = value
	var out := {}
	for key in ["health", "hunger", "thirst", "stamina"]:
		var v := _finite(d.get(key, 100.0), "snapshot.%s" % key, 100.0, repairs)
		var clamped := clampf(v, 0.0, 100.0)
		if clamped != v:
			repairs.append("snapshot:clamp_%s" % key)
		out[key] = clamped
	out["last_damage_reason"] = StringName(String(d.get("last_damage_reason", "")))
	return out


func _has_record(records: Array, life_id: String) -> bool:
	for rec in records:
		if String((rec as Dictionary).get("life_id", "")) == life_id:
			return true
	return false


func _string_list(value: Variant, tag: String, repairs: Array[String]) -> Array:
	var out: Array = []
	if not (value is Array):
		repairs.append("%s:not_array" % tag)
		return out
	var seen := {}
	for item in (value as Array):
		if not (item is String or item is StringName):
			repairs.append("%s:skip_non_string" % tag)
			continue
		var s := String(item)
		if s == "" or seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	return out


func _finite(value: Variant, tag: String, fallback: float, repairs: Array[String]) -> float:
	if value is int:
		return float(value)
	if value is float and is_finite(value):
		return float(value)
	repairs.append("%s:non_finite" % tag)
	return fallback


func _repairs_message(repairs: Array[String]) -> String:
	if repairs.is_empty():
		return ""
	return "存档已修复 %d 处后载入" % repairs.size()


# ---------------------------------------------------------------------------
# 纯数据编码（D3）：JSON 只认基础类型，Transform3D/Vector3/StringName 用标记对象
# ---------------------------------------------------------------------------

func _pack(value: Variant) -> Variant:
	if value == null or value is bool or value is int or value is String:
		return value
	if value is float:
		return float(value) if is_finite(value) else 0.0
	if value is StringName:
		return String(value)
	if value is Vector3:
		return {"$v": [value.x, value.y, value.z]}
	if value is Transform3D:
		return {"$t": [
			value.basis.x.x, value.basis.x.y, value.basis.x.z,
			value.basis.y.x, value.basis.y.y, value.basis.y.z,
			value.basis.z.x, value.basis.z.y, value.basis.z.z,
			value.origin.x, value.origin.y, value.origin.z,
		]}
	if value is Array:
		var arr: Array = []
		for item in (value as Array):
			arr.append(_pack(item))
		return arr
	if value is Dictionary:
		var out := {}
		for key in (value as Dictionary).keys():
			out[String(key)] = _pack((value as Dictionary)[key])
		return out
	return null


func _unpack(value: Variant) -> Variant:
	if value is Array:
		var arr: Array = []
		for item in (value as Array):
			arr.append(_unpack(item))
		return arr
	if value is Dictionary:
		var d: Dictionary = value
		if d.has("$v") and d["$v"] is Array and (d["$v"] as Array).size() == 3:
			var v: Array = d["$v"]
			return Vector3(float(v[0]), float(v[1]), float(v[2]))
		if d.has("$t") and d["$t"] is Array and (d["$t"] as Array).size() == 12:
			var t: Array = d["$t"]
			var basis := Basis(
				Vector3(float(t[0]), float(t[1]), float(t[2])),
				Vector3(float(t[3]), float(t[4]), float(t[5])),
				Vector3(float(t[6]), float(t[7]), float(t[8])))
			return Transform3D(basis, Vector3(float(t[9]), float(t[10]), float(t[11])))
		var out := {}
		for key in d.keys():
			out[key] = _unpack(d[key])
		return out
	return value


func _as_transform(value: Variant) -> Variant:
	var v: Variant = _unpack(value)
	if v is Transform3D:
		var t: Transform3D = v
		if _transform_finite(t):
			return t
		return null
	return null


func _as_vector3(value: Variant) -> Variant:
	var v: Variant = _unpack(value)
	if v is Vector3:
		var p: Vector3 = v
		if is_finite(p.x) and is_finite(p.y) and is_finite(p.z):
			return p
		return null
	return null


func _transform_finite(t: Transform3D) -> bool:
	for col in [t.basis.x, t.basis.y, t.basis.z]:
		if not (is_finite(col.x) and is_finite(col.y) and is_finite(col.z)):
			return false
	return is_finite(t.origin.x) and is_finite(t.origin.y) and is_finite(t.origin.z)


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
