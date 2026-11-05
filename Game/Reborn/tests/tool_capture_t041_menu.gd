extends SceneTree
## T041 视觉取证工具（**不是断言套件**）。走 `Tools/CaptureRun.ps1`（GUI exe + 隐藏桌面）。
##
## 用法：
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_t041_menu.gd -UserArgs save -TimeoutSec 300
##   ... -UserArgs nosave / corrupt / confirm
##
## 帧（`E:/Reborn/Art/Probes/`）：
##   save    → t041_menu_save.png        （有存档：继续 + 新游戏）
##   nosave  → t041_menu_nosave.png      （无存档：只有新游戏）
##   corrupt → t041_menu_corrupt.png     （双坏阻断页 + 确认开始新游戏）
##   confirm → t041_confirm_new_game.png （新游戏确认层，默认焦点取消）
##
## 存档写到 `user://t041_capture/`，不碰真实 `user://savegame_v1.json`。

const RES := Vector2i(1280, 720)
const MAIN := "res://scenes/core/main.tscn"
const TMP_DIR := "user://t041_capture"
const SAVE_PATH := "user://t041_capture/savegame_v1.json"
const PNG_ROOT := "E:/Reborn/Art/Probes"


func _initialize() -> void:
	root.size = RES
	await _run()
	print("CAP|t041|done")
	quit(0)


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var mode := String(args[0]) if args.size() > 0 else "save"
	var sm := root.get_node_or_null("/root/SaveManager")
	if sm == null:
		print("CAP|t041|ERROR|no_save_manager")
		return
	_clean()
	sm.set("allow_headless_writes", true)
	sm.call("set_save_path", SAVE_PATH)
	match mode:
		"save", "confirm":
			_write(SAVE_PATH, _valid_json())
		"corrupt":
			_write(SAVE_PATH, "{ broken main")
			_write(SAVE_PATH + ".bak", "{ broken bak")
		"nosave":
			pass
		_:
			print("CAP|t041|ERROR|unknown_mode=%s" % mode)
			return

	var packed := load(MAIN) as PackedScene
	change_scene_to_packed(packed)
	await _frames(14)
	var entry := current_scene as MainEntry
	if entry == null:
		print("CAP|t041|ERROR|main_root_not_entry")
		return
	if mode == "confirm":
		entry.request_new_game()
		await _frames(4)
	var notice := ""
	if entry.menu != null:
		notice = entry.menu.session_notice_text()
	var dialog := entry.get("confirm_dialog") as Node
	print("CAP|t041|state|mode=%s|status=%s|blocked=%s|resume=%s|page=%d|notice=%s|dialog=%s" % [
		mode, String(entry.get("_load_status")), str(entry.is_load_blocked()),
		str(entry.can_continue_game()), entry.menu.current_page() if entry.menu != null else -1,
		notice, str(dialog != null and dialog.has_method("is_open") and dialog.call("is_open"))
	])
	await _frames(10)
	var png := _shot("t041_menu_%s" % ("confirm_new_game" if mode == "confirm" else mode))
	print("CAP|t041|frame|mode=%s|png=%s" % [mode, png])


func _valid_json() -> String:
	return JSON.stringify({
		"save_version": 1,
		"revision": 3,
		"world_time": 100.0,
		"resources": [],
		"regions": [],
		"discovered_ids": [],
		"unlocked_species": ["Cat"],
		"life_records": [],
		"current_life": {
			"life_id": "L0001",
			"species_id": "Cat",
			"start_world_time": 0.0,
			"end_world_time": -1.0,
			"duration": -1.0,
			"end_reason": "",
			"damage_reason": "",
			"snapshot": {"health": 80.0, "hunger": 70.0, "thirst": 65.0, "stamina": 90.0},
			"transform": {"$t": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0,
				-10.0, 0.6, 16.0]},
			"start_position": {"$v": [-10.0, 0.6, 16.0]},
			"captures": 0,
			"escapes": 0,
			"food_gained": 0.0,
			"water_gained": 0.0,
			"discoveries": [],
			"event_first": 1,
			"event_last": 1,
		},
		"pending_settlement_life_id": "",
		"events": [
			{"seq": 1, "life_id": "L0001", "kind": "life_start", "world_time": 0.0,
				"data": {"species": "Cat"}},
		],
		"life_counter": 1,
		"event_seq": 1,
		"saved_reason": "t041_capture",
	})


func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var dir := DirAccess.open(TMP_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(TMP_DIR.path_join(String(f)))


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _shot(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(PNG_ROOT)
	var out := "%s/%s.png" % [PNG_ROOT, name]
	var img: Image = root.get_texture().get_image()
	var err := img.save_png(out)
	if err != 0:
		print("CAP|t041|ERROR|save_png|%s|err=%d" % [out, err])
		return "<err:%d>" % err
	return out


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
