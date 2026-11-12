extends SceneTree
## T062：**包内探针** —— 在导出产物里验证"资源与 HUD 真的可用"（headless，可在 `--main-pack` 下跑）。
##
## 为什么需要它：T043 的发行包取证是**外部窗口截图**（PrintWindow/BitBlt），对 Vulkan 叠加层不可靠，
## 留下 `HUD-NOT-CONFIRMED`（"读不到右下指标条"）。本探针在**包内**直接问引擎：
## HUD 节点在不在、四条指标条 visible/有值、休息点/昼夜/音频/存档 autoload 在不在。
## 它证明的是"**包里的代码与场景资源可用**"；"画到屏幕上"仍以外部截图为辅证。
##
## 运行（编辑器二进制 + 包；**必须用编辑器二进制**，导出产物拒绝 `--script`）：
##   & '<godot_console/gui exe>' --headless `
##       --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
##       --script 'res://tests/tool_t062_packaged_probe.gd' --quit-after 30000

const MAIN_SCENE := "res://scenes/core/main.tscn"

var _pass := 0
var _fail := 0
var _failed: Array[String] = []


func _initialize() -> void:
	await process_frame
	print("PROBE|t062|packed=%s|engine=%s" % [
		str(OS.has_feature("editor") == false), Engine.get_version_info()["string"]])

	var packed := load(MAIN_SCENE) as PackedScene
	if not _check("A1_main_scene_in_pack", "main.tscn 可加载", str(packed != null), packed != null):
		_finish()
		return
	var entry := packed.instantiate()
	entry.set("test_mode", false)
	root.add_child(entry)
	for i in 6:
		await process_frame

	var configs: Array = entry.call("species_configs")
	_check("A2_species_configs_in_pack", "两物种配置可读", "%d 个" % configs.size(), configs.size() == 2)
	var first: StringName = (configs[0] as SpeciesConfig).species_id if not configs.is_empty() else &""
	# 正式模式：只用初始解锁的第一个物种（鼠要靠发现解锁，包里也一样）
	var ok: bool = bool(entry.call("select_species", first))
	for i in 12:
		await process_frame
	_check("A3_spawn_in_pack", "出生成功", "%s / %s" % [str(ok), String(entry.call("lifecycle_state_name"))],
		ok and String(entry.call("lifecycle_state_name")) == "alive")

	# HUD：节点在、可见、四条指标条都在且有值
	var hud: Node = entry.get("hud")
	_check("B1_hud_present", "HUD 节点存在", str(hud != null), hud != null)
	if hud != null:
		_check("B2_hud_visible", "HUD visible", str((hud as CanvasItem).visible), (hud as CanvasItem).visible)
		var bars: Array = hud.call("vital_bars") if hud.has_method("vital_bars") else []
		_check("B3_vital_bars", "四条指标条", "%d 条" % bars.size(), bars.size() == 4)
		var all_visible := true
		var values: Array[String] = []
		for b in bars:
			var bar := b as Range
			if bar == null or not (bar as CanvasItem).visible:
				all_visible = false
				continue
			values.append("%.1f" % bar.value)
		_check("B4_bars_visible_with_values", "每条都可见且有值", str(values), all_visible and not values.is_empty())
		var text := String(hud.call("hud_text")) if hud.has_method("hud_text") else ""
		_check("B5_hud_text_present", "HUD 文本非空", text.substr(0, 24), not text.is_empty())

	# 其它 autoload / 运行期资源
	for name in ["WorldDirector", "SaveManager", "GameState", "AudioDirector", "AmbienceDirector",
			"SubtitleDirector", "DayNightDirector", "RestDirector"]:
		var node := root.get_node_or_null("/root/" + name)
		_check("C1_autoload_" + name, "在包里存在", str(node != null), node != null)

	var level: Node = entry.get("level")
	_check("C2_level_in_pack", "关卡已实例化", str(level != null), level != null)
	if level != null:
		_check("C3_rest_point_in_pack", "休息点挂上（T058）",
			str(level.get_node_or_null("RestPoint") != null), level.get_node_or_null("RestPoint") != null)
		var sun := level.get_node_or_null("SunLight")
		_check("C4_sunlight_in_pack", "太阳节点在（T057）", str(sun != null), sun != null)

	# 音频资源：T055 的 4 个音源必须在包里能 load
	var audio_ok := true
	var audio_detail: Array[String] = []
	for path in ["res://assets/audio/footstep_walk.wav", "res://assets/audio/footstep_run.wav",
			"res://assets/audio/attack.wav", "res://assets/audio/hurt.wav",
			"res://assets/audio/creek_loop.wav", "res://assets/audio/wind_loop.wav"]:
		var s := load(path)
		audio_detail.append("%s=%s" % [path.get_file(), str(s != null)])
		if s == null:
			audio_ok = false
	_check("D1_audio_assets_in_pack", "6 个音源可 load", str(audio_detail), audio_ok)

	_finish()


func _check(tag: String, expected: String, actual: String, ok: bool) -> bool:
	if ok:
		_pass += 1
		print("ASSERT|%s|%s|%s|PASS" % [tag, expected, actual])
	else:
		_fail += 1
		_failed.append(tag)
		print("ASSERT|%s|%s|%s|FAIL" % [tag, expected, actual])
	return ok


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_pass + _fail, _fail])
	if _fail == 0:
		print("RESULT|pass=%d|fail=0|failed=" % _pass)
		quit(0)
	else:
		print("RESULT|pass=%d|fail=%d|failed=%s" % [_pass, _fail, "|".join(_failed)])
		quit(1)
