extends SceneTree
## T038 取证工具（**不是断言套件**）：写入失败 / 备份失败时玩家可见的 Toast，以及队列失败后主档仍在。
##
## 用法（走 `Tools/CaptureRun.ps1`，隐藏桌面、GUI exe，禁止 headless）：
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_t038_failure.gd -UserArgs fail
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_t038_failure.gd -UserArgs warn
##
## 产物：`E:\Reborn\Art\Probes\t038_queue_fail.png` / `t038_queue_warn.png`

const RES := Vector2i(1280, 720)
const SETTLE := 45
const MAIN := "res://scenes/core/main.tscn"
const DIR := "user://t038_visual"
const SAVE := "user://t038_visual/savegame_v1.json"
const OUT_FAIL := "E:/Reborn/Art/Probes/t038_queue_fail.png"
const OUT_WARN := "E:/Reborn/Art/Probes/t038_queue_warn.png"


func _initialize() -> void:
	root.size = RES
	var mode := "fail"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = String(args[0])
	await _run(mode)
	print("CAP|t038|done")
	quit(0)


func _run(mode: String) -> void:
	await process_frame
	_clean()
	var sm := root.get_node_or_null("/root/SaveManager")
	if sm == null:
		print("CAP|t038|ERROR|no_save_manager")
		return
	sm.set("allow_headless_writes", true)
	sm.call("set_save_path", SAVE)

	var packed := load(MAIN) as PackedScene
	if packed == null:
		print("CAP|t038|ERROR|main_load_failed")
		return
	var main := packed.instantiate()
	root.add_child(main)
	current_scene = main
	for i in SETTLE:
		await process_frame
	var entry := main as MainEntry
	if entry == null:
		print("CAP|t038|ERROR|main_root_not_entry")
		return
	entry.call("set_persistence_enabled", true)
	entry.select_species(&"Cat")
	for i in 40:
		await process_frame
	entry.call("save_now", &"capture_seed")
	for i in 6:
		await process_frame

	if mode == "warn":
		sm.set("fault_injection", "bak_copy")
		entry.call("save_now", &"capture_warn")
	else:
		sm.set("fault_injection", "disk_write")
		entry.call("save_now", &"capture_fail")
	for i in 5:
		await process_frame

	var stats: Dictionary = sm.call("queue_stats")
	var out := OUT_WARN if mode == "warn" else OUT_FAIL
	var img: Image = root.get_texture().get_image()
	var err := img.save_png(out)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	print("CAP|t038|mode=%s|status=%s|warning=%s|rev=%s|failed=%d|queue=%d|png=%s|err=%d" % [
		mode, String(sm.get("last_status")), String(sm.get("last_warning")),
		str((parsed as Dictionary).get("revision", -1) if parsed is Dictionary else -1),
		int(stats.get("failed", 0)), int(sm.call("queue_length")), out, err
	])
	sm.set("fault_injection", "")
	_clean()


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(DIR)
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(DIR.path_join(String(f)))
