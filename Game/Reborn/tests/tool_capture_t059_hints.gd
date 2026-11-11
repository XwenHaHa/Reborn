extends SceneTree
## T059：**首次操作提示**的画面取证（非 headless；走 `Tools/CaptureRun.ps1`，隐藏桌面零窗口）。
##
## 为什么要有：`hints` 是新 UI。"不堵操作"是断言能证明的，**"画面上真的看得见、且不挡 HUD"
## 只能靠取景**。
##
## 运行：
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 `
##       -Script tests/tool_capture_t059_hints.gd -UserArgs t059 -QuitAfter 12000
## 输出：`Art/Probes/t059_hints_first_run.png`，并打印 `CAP|t059|...` 行（含 HUD 行数与提示文案）。

const MAIN_SCENE := "res://scenes/core/main.tscn"
const TMP_SETTINGS := "user://t059_capture_settings.cfg"
const OUT_PATH := "E:/Reborn/Art/Probes/t059_hints_first_run.png"
const RES := Vector2i(1280, 720)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	print("CAP|t059|start|renderer=%s|args=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"), str(args)])
	if not args.has("t059"):
		print("CAP|t059|ERROR|need_arg|pass '-- t059'")
		print("CAP|t059|done")
		quit(0)
		return
	await process_frame
	root.size = RES
	await _run()
	print("CAP|t059|done")
	quit(0)


func _run() -> void:
	# 干净的设置：保证这一次是"首次"
	if FileAccess.file_exists(TMP_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("CAP|t059|ERROR|main_scene_missing")
		return
	var entry := packed.instantiate()
	entry.set("settings_path", TMP_SETTINGS)
	entry.set("test_mode", true)
	entry.call("set_persistence_enabled", false)
	root.add_child(entry)
	for i in 8:
		await process_frame

	var configs: Array = entry.call("species_configs")
	if configs.is_empty():
		print("CAP|t059|ERROR|no_species")
		return
	var species: StringName = (configs[0] as SpeciesConfig).species_id
	var ok: bool = bool(entry.call("select_species", species))
	print("CAP|t059|spawn=%s|species=%s" % [str(ok), String(species)])
	for i in 10:
		await process_frame

	var hints: Node = entry.get("first_run_hints")
	print("CAP|t059|hints=%s" % ("null" if hints == null else str(hints.get_path())))
	if hints != null:
		print("CAP|t059|hint_text=%s" % String(hints.call("current_text")))
		print("CAP|t059|hint_blocks_input=%s" % str(hints.call("blocks_input")))
	# 让提示停在第 1 条的可读时机（默认 2.2 s 一条；这里只等几帧，仍是第 1 条）
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("CAP|t059|ERROR|no_image")
		return
	var err := img.save_png(OUT_PATH)
	print("CAP|t059|shot=%s|err=%d|size=%dx%d" % [OUT_PATH, err, img.get_width(), img.get_height()])
