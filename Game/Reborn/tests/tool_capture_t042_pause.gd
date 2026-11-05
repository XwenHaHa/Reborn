extends SceneTree
## T042 视觉取证工具（**不是断言套件**）。走 `Tools/CaptureRun.ps1`（GUI exe + 隐藏桌面）。
##
## 用法：
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_t042_pause.gd -TimeoutSec 420
##
## 帧（`E:/Reborn/Art/Probes/`）：
##   t042_pause_menu.png         （存活期 Esc 暂停层：标题/两按钮/默认焦点「继续游戏」）
##   t042_end_life_confirm.png   （「结束本次生命」二次确认，默认焦点「取消」）
##   t042_player_quit_settle.png （确认后的结算页：「死亡（player_quit）」）
##
## 存档写到 `user://t042_capture/`，不碰真实 `user://savegame_v1.json`。

const RES := Vector2i(1280, 720)
const MAIN := "res://scenes/core/main.tscn"
const TMP_DIR := "user://t042_capture"
const SAVE_PATH := "user://t042_capture/savegame_v1.json"
const PNG_ROOT := "E:/Reborn/Art/Probes"


func _initialize() -> void:
	root.size = RES
	await _run()
	# 解除暂停，避免把全局暂停留给后续（异常路径同样执行）。
	print("CAP|t042|done")
	quit(0)


func _run() -> void:
	await process_frame
	var sm := root.get_node_or_null("/root/SaveManager")
	if sm == null:
		print("CAP|t042|ERROR|no_save_manager")
		return
	_clean()
	sm.set("allow_headless_writes", true)
	sm.call("set_save_path", SAVE_PATH)

	var packed := load(MAIN) as PackedScene
	change_scene_to_packed(packed)
	await _frames(14)
	var entry := current_scene as MainEntry
	if entry == null:
		print("CAP|t042|ERROR|main_root_not_entry")
		return

	# 存活期：选猫出生，等世界跑起来。
	var spawned: bool = entry.select_species(&"Cat")
	await _frames(30)
	print("CAP|t042|state|spawned=%s|life=%s|alive=%s" % [
		str(spawned), entry.current_life_id(), str(entry.lifecycle.is_alive())
	])
	if not entry.lifecycle.is_alive():
		print("CAP|t042|ERROR|player_not_alive")
		return

	# 帧 1：暂停层。
	var opened: bool = entry.open_pause()
	await _frames(6)
	await _focus_idle()
	print("CAP|t042|pause|open=%s|paused=%s|title=%s|resume=%s|end=%s|focus=%s" % [
		str(opened), str(entry.is_paused()), entry.pause_menu.title_text(),
		entry.pause_menu.resume_button_text(), entry.pause_menu.end_life_button_text(),
		entry.pause_menu.focused_button_text()
	])
	print("CAP|t042|frame|png=%s" % _shot("t042_pause_menu"))

	# 帧 2：结束确认（默认焦点「取消」）。
	var asked: bool = entry.request_end_life()
	await _frames(6)
	await _focus_idle()
	print("CAP|t042|confirm|open=%s|focus=%s|cancel=%s|confirm=%s" % [
		str(asked), entry.end_life_confirm.focused_button_text(),
		entry.end_life_confirm.cancel_text(), entry.end_life_confirm.confirm_text()
	])
	print("CAP|t042|frame|png=%s" % _shot("t042_end_life_confirm"))

	# 帧 3：确认后正常死亡 → 结算页。
	var done: bool = entry.confirm_end_life()
	await _frames(24)
	print("CAP|t042|settle|confirmed=%s|alive=%s|presenting=%s|text=%s|paused=%s" % [
		str(done), str(entry.lifecycle.is_alive()),
		str(entry.settle_panel.is_presenting()), entry.settle_panel.summary_text(),
		str(entry.is_paused())
	])
	print("CAP|t042|frame|png=%s" % _shot("t042_player_quit_settle"))


## 焦点在 deferred 调用里落定；等两帧让 focus 样式真正绘制出来。
func _focus_idle() -> void:
	await _frames(2)


func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var dir := DirAccess.open(TMP_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(TMP_DIR.path_join(String(f)))


func _shot(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(PNG_ROOT)
	var out := "%s/%s.png" % [PNG_ROOT, name]
	var img: Image = root.get_texture().get_image()
	var err := img.save_png(out)
	if err != 0:
		print("CAP|t042|ERROR|save_png|%s|err=%d" % [out, err])
		return "<err:%d>" % err
	return out


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
