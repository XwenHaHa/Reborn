extends SceneTree
## T060：**真实场景性能探针**（非 headless；经 `Tools/CaptureRun.ps1` 隐藏桌面运行，零窗口）。
##
## 为什么要新工具：`tests/tool_perf_probe.gd`（ART03 遗留）测的是**空关卡**——没有玩家、没有 NPC、
## 没有 HUD、没有生态。开发计划 :257 明确「**不能以空地图 FPS 代表真实场景性能**」。
##
## 本工具测的是**正式入口 + 真实一局**（`main.tscn` + 出生 + 生态 NPC + HUD + 昼夜 + 环境音），
## 并在**同一机位**上逐变体关掉子系统，用差值做**负载归因**：
##   all / no_ai / no_vegetation / no_daynight
##
## 口径（沿用 `tool_perf_probe.gd`，可复现）：
##   关 vsync + `Engine.max_fps = 0`；预热 `WARMUP` 帧后采 `SAMPLE` 帧；
##   帧时间 = `frame_post_draw` 相邻墙钟差（含逻辑 + 渲染，就是玩家感知的整帧）；
##   同时读 `Performance.RENDER_TOTAL_*` 与 `MEMORY_STATIC`。
##
## 运行：
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 `
##       -Script tests/tool_t060_perf.gd -UserArgs t060 -QuitAfter 60000 -TimeoutSec 900

const MAIN_SCENE := "res://scenes/core/main.tscn"
const TMP_SETTINGS := "user://t060_perf_settings.cfg"
const WARMUP := 60
const SAMPLE := 240
## 固定机位（庭院出生点附近朝北看：把围栏/庇护棚/草丛/溪流都推进视野）
const CAM_POS := Vector3(2.0, 1.30, 23.0)
const CAM_LOOK := Vector3(-7.0, 0.9, 8.0)
const CAM_FOV := 72.0
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080)]

var _entry: Node = null
var _level: Node3D = null
var _cam: Camera3D = null
var _npcs: Array[Node] = []
var _vegs: Array[Node] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	print("PERF|t060|start|renderer=%s|args=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"), str(args)])
	if not args.has("t060"):
		print("PERF|t060|ERROR|need_arg|pass '-- t060'")
		print("PERF|t060|done")
		quit(1)
		return
	# 不锁帧、不等垂直同步：测的是"能跑多快"，不是"被限制在多少"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	await _boot()
	if _entry == null:
		print("PERF|t060|ERROR|boot_failed")
		print("PERF|t060|done")
		quit(1)
		return
	print(_machine_line())
	_collect_nodes()
	for res in RESOLUTIONS:
		await _measure_resolution(res)
	print("PERF|t060|done")
	quit(0)


# ---------------------------------------------------------------------------
# 启动：正式入口 + 出生（玩家 + 生态 NPC 都在跑）
# ---------------------------------------------------------------------------

func _boot() -> void:
	if FileAccess.file_exists(TMP_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("PERF|t060|ERROR|main_scene_missing")
		return
	_entry = packed.instantiate()
	_entry.set("settings_path", TMP_SETTINGS)
	_entry.set("test_mode", true)
	_entry.call("set_persistence_enabled", false)
	# 性能探针要测"满负载"：把新手提示关掉（它 10 s 后自己消失，会在采样窗口里造成跳变）
	_entry.set("hints_seen", true)
	root.add_child(_entry)
	for i in 10:
		await process_frame

	var configs: Array = _entry.call("species_configs")
	if configs.is_empty():
		print("PERF|t060|ERROR|no_species")
		return
	var species: StringName = (configs[0] as SpeciesConfig).species_id
	var ok: bool = bool(_entry.call("select_species", species))
	print("PERF|t060|spawn=%s|species=%s" % [str(ok), String(species)])
	for i in 20:
		await process_frame

	_level = _entry.get_node_or_null("Level") as Node3D
	if _level == null:
		print("PERF|t060|ERROR|no_level")
		return
	# 固定机位：自建相机并设为当前（玩家自己的相机会继续算位置，但不渲染）
	_cam = Camera3D.new()
	_cam.name = "T060Cam"
	_cam.near = 0.05
	_cam.far = 500.0
	_cam.fov = CAM_FOV
	_level.add_child(_cam)
	_cam.look_at_from_position(CAM_POS, CAM_LOOK, Vector3.UP)
	_cam.current = true
	for i in 6:
		await process_frame


func _machine_line() -> String:
	var info := OS.get_processor_name()
	return "PERF|t060|machine|cpu=%s|cores=%d|ram_mb=%d|os=%s|gpu=%s|driver=%s" % [
		info, OS.get_processor_count(), int(OS.get_memory_info().get("physical", 0)) / 1048576,
		OS.get_version(),
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(),
	]


## 收集变体要开/关的节点：NPC 身体 + 植被（草丛/背景草簇/芦苇；按节点名，不按 tag）
func _collect_nodes() -> void:
	_npcs.clear()
	_vegs.clear()
	var player: Node = _entry.get("player")
	for node in get_nodes_in_group(&"animal_bodies"):
		if node != player and is_instance_valid(node):
			_npcs.append(node)
	if _level == null:
		return
	for node in _level.find_children("*", "Node3D", true, false):
		var nm := String(node.name).to_lower()
		if nm.contains("bush") or nm.contains("grass") or nm.contains("reed") or nm.contains("tuft"):
			_vegs.append(node)
	print("PERF|t060|scene|level=l_courtyard|npcs=%d|vegetation_nodes=%d|hud=%s|daynight=%s|ambience=%s" % [
		_npcs.size(), _vegs.size(),
		str(_entry.get_node_or_null("Hud") != null),
		str(root.get_node_or_null("DayNightDirector") != null),
		str(root.get_node_or_null("AmbienceDirector") != null)])


# ---------------------------------------------------------------------------
# 测量
# ---------------------------------------------------------------------------

func _measure_resolution(res: Vector2i) -> void:
	root.size = res
	for i in 8:
		await process_frame
	for variant in ["all", "no_ai", "no_vegetation", "no_daynight", "all"]:
		await _set_variant(variant)
		var stats := await _sample()
		_report(res, variant, stats)
	await _set_variant("all")


func _set_variant(variant: String) -> void:
	# 先复位成"全开"
	for npc in _npcs:
		if not is_instance_valid(npc):
			continue
		npc.set("ai_enabled", true)
		(npc as Node).set_physics_process(true)
	for veg in _vegs:
		if is_instance_valid(veg) and veg is Node3D:
			(veg as Node3D).visible = true
	var dn := root.get_node_or_null("DayNightDirector")
	if dn != null:
		dn.set("enabled", true)

	match variant:
		"no_ai":
			for npc in _npcs:
				if not is_instance_valid(npc):
					continue
				npc.set("ai_enabled", false)
				(npc as Node).set_physics_process(false)
		"no_vegetation":
			for veg in _vegs:
				if is_instance_valid(veg) and veg is Node3D:
					(veg as Node3D).visible = false
		"no_daynight":
			if dn != null:
				dn.set("enabled", false)
	await process_frame


func _sample() -> Dictionary:
	for i in WARMUP:
		await process_frame

	var frames: Array[float] = []
	var prim_sum := 0
	var draw_sum := 0
	var obj_peak := 0
	var mem_static := 0
	var mem_max := 0
	var t_prev := Time.get_ticks_usec()
	for i in SAMPLE:
		await RenderingServer.frame_post_draw
		var t := Time.get_ticks_usec()
		frames.append(float(t - t_prev) / 1000000.0)
		t_prev = t
		prim_sum += int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		draw_sum += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		obj_peak = maxi(obj_peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		var st := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		mem_static = maxi(mem_static, st)
		mem_max = maxi(mem_max, int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)))

	frames.sort()
	var n := frames.size()
	var avg := 0.0
	for f in frames:
		avg += f
	avg /= float(maxi(1, n))
	return {
		"frames": n,
		"avg_ms": avg * 1000.0,
		"p50_ms": frames[int(float(n) * 0.5)] * 1000.0,
		"p95_ms": frames[mini(n - 1, int(float(n) * 0.95))] * 1000.0,
		"max_ms": frames[n - 1] * 1000.0,
		"fps": 1.0 / maxf(avg, 1e-6),
		"prim": prim_sum / maxi(1, n),
		"draw": draw_sum / maxi(1, n),
		"objects": obj_peak,
		"mem_static_mb": float(mem_static) / 1048576.0,
		"mem_static_max_mb": float(mem_max) / 1048576.0,
	}


func _report(res: Vector2i, variant: String, s: Dictionary) -> void:
	print("PERF|res=%dx%d|variant=%s|frame_ms|avg=%.3f|p50=%.3f|p95=%.3f|max=%.3f|fps=%.1f" % [
		res.x, res.y, variant, s["avg_ms"], s["p50_ms"], s["p95_ms"], s["max_ms"], s["fps"]])
	print("PERF|res=%dx%d|variant=%s|render|prims=%d|draw=%d|objects=%d" % [
		res.x, res.y, variant, s["prim"], s["draw"], s["objects"]])
	print("PERF|res=%dx%d|variant=%s|memory|static_mb=%.1f|static_max_mb=%.1f|os_static_mb=%.1f" % [
		res.x, res.y, variant, s["mem_static_mb"], s["mem_static_max_mb"],
		float(OS.get_static_memory_usage()) / 1048576.0])
