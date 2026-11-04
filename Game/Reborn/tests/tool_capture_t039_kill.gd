extends SceneTree
## T039 真机强杀取证工具（**不是断言套件**）。
##
## 用法（必须走 `Tools/CaptureRun.ps1`，隐藏桌面 + GUI exe；不要 headless）：
##   强杀：-Script tests/tool_capture_t039_kill.gd -UserArgs kill <phase> 4000 `
##         -KillOnMarker "T039|phase|<phase>|begin" -KillGraceMs 400 -KillExitCode 137
##   重启验证：-Script tests/tool_capture_t039_kill.gd -UserArgs verify <phase>
##
## phase ∈ before_tmp / tmp_mid / rename_gap / bak_rotate。
## 存档都在 `user://t039_kill/<phase>/`，不碰真实 `user://savegame_v1.json`。
## 产物：`Art/Probes/t039_kill_<phase>.png`（验证模式）。

const RES := Vector2i(1280, 720)
const MAIN := "res://scenes/core/main.tscn"
const DIR_ROOT := "user://t039_kill"
const PNG_ROOT := "E:/Reborn/Art/Probes"


func _initialize() -> void:
	root.size = RES
	var args := OS.get_cmdline_user_args()
	var mode := "verify"
	var phase := "before_tmp"
	var hold_ms := 4000
	if args.size() > 0:
		mode = String(args[0])
	if args.size() > 1:
		phase = String(args[1])
	if args.size() > 2:
		hold_ms = int(args[2])
	await _run(mode, phase, hold_ms)
	print("CAP|t039|done|mode=%s|phase=%s" % [mode, phase])
	quit(0)


func _run(mode: String, phase: String, hold_ms: int) -> void:
	await process_frame
	var sm := root.get_node_or_null("/root/SaveManager")
	if sm == null:
		print("CAP|t039|ERROR|no_save_manager")
		return
	sm.set("allow_headless_writes", true)
	sm.call("set_save_path", _save_path(phase))

	if mode == "kill":
		_seed(phase)
	else:
		# 验证模式：**不**清理、**不**重造档；只读取强杀后的残留。
		pass

	var packed := load(MAIN) as PackedScene
	if packed == null:
		print("CAP|t039|ERROR|main_load_failed")
		return
	# 用 change_scene 让 `current_scene == self`，正式持久化在 `_ready` 自动启用并读档。
	change_scene_to_packed(packed)
	for i in 45:
		await process_frame
	var entry := current_scene as MainEntry
	if entry == null:
		print("CAP|t039|ERROR|main_root_not_entry")
		return

	if mode == "kill":
		var picked := entry.select_species(&"Cat")
		for i in 20:
			await process_frame
		print("CAP|t039|kill_ready|phase=%s|picked=%s|hold_ms=%d" % [phase, str(picked), hold_ms])
		sm.set("write_delay_phase", phase)
		sm.set("write_delay_ms", hold_ms)
		# 标记在 SaveManager 内部打印；外部监视器读到后 TerminateProcess。
		var res: Dictionary = entry.call("save_now", &"kill_probe")
		print("CAP|t039|NOT_KILLED|phase=%s|status=%s" % [phase, str(res.get("status", ""))])
		return

	await _verify(entry, sm, phase)


func _verify(entry: MainEntry, sm: Node, phase: String) -> void:
	for i in 8:
		await process_frame
	var notice := String(entry.get("_load_notice"))
	var status := String(entry.get("_load_status"))
	var blocked := bool(entry.call("is_load_blocked"))
	var snap: Variant = entry.get("_loaded_snapshot")
	var snap_rev := -1
	if snap is Dictionary:
		snap_rev = int((snap as Dictionary).get("revision", -1))
	var p := _save_path(phase)

	var out := "%s/t039_kill_%s.png" % [PNG_ROOT, phase]
	DirAccess.make_dir_recursive_absolute(PNG_ROOT)
	var img: Image = root.get_texture().get_image()
	var err := img.save_png(out)

	print("CAP|t039|verify|phase=%s|load=%s|blocked=%s|rev=%s|main=%s|bak=%s|tmp=%s|old=%s|btmp=%s|msg=%s|notice=%s|png=%s|err=%d" % [
		phase, status, str(blocked), str(snap_rev),
		_file_state(p), _file_state(p + ".bak"), _file_state(p + ".tmp"),
		_file_state(p + ".old"), _file_state(p + ".bak.tmp"),
		String(sm.get("last_message")), notice, out, err
	])

	# 下次保存仍能成功，并清理残留中间态。
	var res: Dictionary = entry.call("save_now", &"verify_next")
	for i in 4:
		await process_frame
	var after: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	var next_rev := int((after as Dictionary).get("revision", -1)) if after is Dictionary else -1
	print("CAP|t039|next_save|phase=%s|status=%s|ok=%s|after_rev=%d|tmp=%s|old=%s|btmp=%s|main_parses=%s|bak_parses=%s" % [
		phase, String(res.get("status", "")), str(res.get("ok", false)), next_rev,
		_file_state(p + ".tmp"), _file_state(p + ".old"), _file_state(p + ".bak.tmp"),
		str(_parses(p)), str(_parses(p + ".bak"))
	])


func _save_path(phase: String) -> String:
	return "%s/%s/savegame_v1.json" % [DIR_ROOT, phase]


func _seed(phase: String) -> void:
	var dir := "%s/%s" % [DIR_ROOT, phase]
	DirAccess.make_dir_recursive_absolute(dir)
	var p := _save_path(phase)
	# 清掉上一轮强杀留下的 tmp/old/corrupt，保证本轮从已知状态开始。
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(dir.path_join(String(f)))
	var body := JSON.stringify(_valid())
	_write(p, body)
	_write(p + ".bak", body)


func _valid() -> Dictionary:
	return {
		"save_version": 1,
		"revision": 1,
		"world_time": 10.0,
		"resources": [],
		"regions": [],
		"discovered_ids": [],
		"unlocked_species": ["Cat"],
		"life_records": [],
		"current_life": {},
		"pending_settlement_life_id": "",
		"events": [],
		"life_counter": 0,
		"event_seq": 0,
		"saved_reason": "t039_seed",
	}


func _file_state(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "missing"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return "rev:%d" % int((parsed as Dictionary).get("revision", -1))
	return "bad"


func _json_rev(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return int((parsed as Dictionary).get("revision", -1))
	return -1


func _parses(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return JSON.parse_string(FileAccess.get_file_as_string(path)) is Dictionary


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
