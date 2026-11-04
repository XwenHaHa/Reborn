extends SceneTree
## T037 取证工具（**不是断言套件**）：读档补弹结算页 / 备份恢复 Toast 的可见面。
##
## 用法（走 `Tools/CaptureRun.ps1`，隐藏桌面、GUI exe）：
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_t037_load.gd -UserArgs settle
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_t037_load.gd -UserArgs recovered
##
## 产物：`E:\Reborn\Art\Probes\t037_load_settle.png` / `t037_load_recovered.png`
## 注意：不能 `--headless`（dummy 渲染器没有画面）。

const RES := Vector2i(1280, 720)
const SETTLE := 40
const MAIN := "res://scenes/core/main.tscn"
const DIR := "user://t037_visual"
const SAVE := "user://t037_visual/savegame_v1.json"
const OUT_SETTLE := "E:/Reborn/Art/Probes/t037_load_settle.png"
const OUT_RECOVERED := "E:/Reborn/Art/Probes/t037_load_recovered.png"


func _initialize() -> void:
	root.size = RES
	var mode := "settle"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = String(args[0])
	await _run(mode)
	print("CAP|t037|done")
	quit(0)


func _run(mode: String) -> void:
	await process_frame
	_clean()
	var sm := root.get_node_or_null("/root/SaveManager")
	if sm == null:
		print("CAP|t037|ERROR|no_save_manager")
		return
	sm.set("allow_headless_writes", true)
	sm.call("set_save_path", SAVE)
	if mode == "recovered":
		_write(SAVE + ".bak", _snapshot_json(""))
		_write(SAVE, "{ broken")
	else:
		_write(SAVE, _snapshot_json("L0001"))

	var packed := load(MAIN) as PackedScene
	if packed == null:
		print("CAP|t037|ERROR|main_load_failed")
		return
	var main := packed.instantiate()
	root.add_child(main)
	current_scene = main
	for i in SETTLE:
		await process_frame
	var entry := main as MainEntry
	if entry == null:
		print("CAP|t037|ERROR|main_root_not_entry")
		return
	entry.call("set_persistence_enabled", true)
	entry.call("_load_saved_game")
	entry.call("_toast_load_status")
	entry.call("apply_saved_snapshot", entry.get("_loaded_snapshot"))
	entry.call("_present_menu")   # 工具已过 `_ready` 的首次 `_enter_select`，再刷一次菜单提示
	for i in SETTLE:
		await process_frame

	var out := OUT_SETTLE if mode == "settle" else OUT_RECOVERED
	var img: Image = root.get_texture().get_image()
	var err := img.save_png(out)
	print("CAP|t037|mode=%s|status=%s|state=%s|pending=%s|settle=%s|png=%s|err=%d" % [
		mode, String(entry.get("_load_status")), entry.lifecycle_state_name(),
		entry.pending_settlement_life_id(),
		str(entry.settle_panel != null and entry.settle_panel.is_presenting()), out, err
	])
	_clean()


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(DIR)
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(DIR.path_join(String(f)))


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _snapshot_json(pending: String) -> String:
	var record := {
		"life_id": "L0001", "species_id": "Cat", "start_world_time": 0.0,
		"end_world_time": 90.0, "duration": 90.0, "end_reason": "died",
		"damage_reason": "starvation", "start_position": {"$v": [0.0, 0.0, 0.0]},
		"captures": 1, "escapes": 2, "food_gained": 35.0, "water_gained": 40.0,
		"discoveries": [], "event_first": 1, "event_last": 2,
		"snapshot": {"health": 0.0, "hunger": 0.0, "thirst": 0.0, "stamina": 0.0},
		"transform": {"$t": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]},
	}
	return JSON.stringify({
		"save_version": 1, "revision": 3, "world_time": 100.0,
		"resources": [], "regions": [], "discovered_ids": ["creek_east_bank"],
		"unlocked_species": ["Cat"], "life_records": [record], "current_life": {},
		"pending_settlement_life_id": pending,
		"events": [
			{"seq": 1, "life_id": "L0001", "kind": "life_start", "world_time": 0.0, "data": {}},
			{"seq": 2, "life_id": "L0001", "kind": "life_end", "world_time": 90.0,
				"data": {"reason": "died"}},
		],
		"life_counter": 1, "event_seq": 2, "saved_reason": "visual",
	})
