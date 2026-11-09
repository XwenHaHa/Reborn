extends SceneTree
## T044 资产预算实测探针：把"每类资产能花多少三角面"从**本机实测**推出来，不套固定面数。
##
## 背景：`Docs/ART_ASSET_SPEC.md` §2 的面数预算源自 `modeling4.md`，标注"未经实机性能测试验证"。
## 本探针在真实关卡 `l_courtyard.tscn` 上按固定机位，向场景里叠加 N 个**真实资产实例**
## （已接入的猫/鼠骨骼网格、巨石/草丛静态网格），测每帧耗时与 primitive/draw call，得到
## "每万三角形 / 每 draw call 的边际成本"，再据此反推各类资产的面数上限。
##
## 运行（**不能用 --headless**，无头是 dummy 渲染器，测不出 GPU 成本）：
##   & 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_t044_budget_probe.gd' --quit-after 60000 -- budget
##
## 口径：
## - 关 vsync、`Engine.max_fps = 0`、1280×720（项目基线）与 1920×1080（余量）各测一遍。
## - 每档 30 帧预热 + 90 帧采样，取 avg / p50 / p95。
## - 只测**渲染**：不跑 AI/物理结算，所以结果是"资产渲染成本"；实际游戏还要叠加逻辑/物理
##   预算，预算表按 30% 预留。
## - 同一档位的实例位置固定（前排 8 个 + 后排堆叠），跨档位可比。

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const CAT_VISUAL := "res://assets/characters/cat/sm_cat_002.glb"
const MOUSE_VISUAL := "res://assets/characters/mouse/sm_mouse_002.glb"
const BOULDER_VISUAL := "res://assets/environment/sm_boulder_001.glb"
const BUSH_VISUAL := "res://assets/environment/sm_bush_002.glb"
const WARMUP := 30
const SAMPLE := 90

var _world: Node3D = null
var _cam: Camera3D = null
var _payload: Node3D = null
var _res := Vector2i(1280, 720)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("budget"):
		print("BUDGET|ERROR|need_arg|pass '-- budget'")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = _res

	print("BUDGET|machine|cpu=%s|gpu=%s|renderer=%s|fps_max=%d|sample=%d" % [
		OS.get_processor_name(), RenderingServer.get_video_adapter_name(),
		String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")),
		Engine.max_fps, SAMPLE])

	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("BUDGET|ERROR|level_load_failed")
		quit(1)
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)
	_cam = Camera3D.new()
	_cam.name = "BudgetCam"
	_cam.near = 0.05
	_cam.far = 400.0
	_world.add_child(_cam)
	await process_frame
	# 与 `tool_perf_probe.gd` 同一机位：站在庭院中间朝北看（围栏最坏方向）。
	_cam.look_at_from_position(Vector3(0.0, 1.6, 6.0), Vector3(0.0, 1.2, 30.0), Vector3.UP)
	_cam.current = true
	_payload = Node3D.new()
	_payload.name = "BudgetPayload"
	_world.add_child(_payload)

	# 1280×720：项目基线
	await _set_resolution(Vector2i(1280, 720))
	await _measure("baseline", 0)
	await _sweep("cat_skinned", CAT_VISUAL, [1, 2, 4, 8, 16, 24, 32])
	await _sweep("mouse_skinned", MOUSE_VISUAL, [4, 8, 16, 32, 64])
	await _sweep("boulder_static", BOULDER_VISUAL, [8, 16, 32, 64])
	await _sweep("bush_static", BUSH_VISUAL, [8, 16, 32])

	# 1920×1080：分辨率余量（纯像素填充成本）
	await _clear_payload()
	await _set_resolution(Vector2i(1920, 1080))
	await _measure("baseline_1080p", 0)
	await _sweep("cat_skinned_1080p", CAT_VISUAL, [8, 16, 32])

	print("BUDGET|done")
	quit(0)


func _set_resolution(size: Vector2i) -> void:
	_res = size
	root.size = size
	await process_frame


func _sweep(tag: String, visual_path: String, counts: Array) -> void:
	for n in counts:
		await _measure(tag, int(n), visual_path)


func _clear_payload() -> void:
	if _payload == null:
		return
	for child in _payload.get_children():
		_payload.remove_child(child)
		child.queue_free()
	await process_frame


func _measure(tag: String, count: int, visual_path: String = "") -> void:
	await _clear_payload()
	if count > 0 and visual_path != "":
		var packed: PackedScene = load(visual_path)
		if packed == null:
			print("BUDGET|ERROR|visual_load_failed|path=%s" % visual_path)
			return
		for i in count:
			var node: Node3D = packed.instantiate() as Node3D
			if node == null:
				print("BUDGET|ERROR|not_node3d|path=%s" % visual_path)
				return
			# 前排 8 个 + 后排堆叠；间距 0.9 m，全部落在机位视野内。
			var col := i % 8
			var row := int(i / 8)
			node.position = Vector3((float(col) - 3.5) * 0.9, 0.25, 8.0 + float(row) * 1.2)
			_payload.add_child(node)
	await process_frame
	for i in WARMUP:
		await process_frame

	var frames: Array[float] = []
	var prim_peak := 0
	var draw_peak := 0
	var t_start := Time.get_ticks_usec()
	for i in SAMPLE:
		await RenderingServer.frame_post_draw
		var t := Time.get_ticks_usec()
		frames.append(float(t - t_start) / 1000000.0)
		t_start = t
		prim_peak = maxi(prim_peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		draw_peak = maxi(draw_peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

	frames.sort()
	var n := frames.size()
	var avg := 0.0
	for f in frames:
		avg += f
	avg /= float(maxi(1, n))
	var p50: float = frames[int(float(n) * 0.5)]
	var p95: float = frames[mini(n - 1, int(float(n) * 0.95))]
	print("BUDGET|case=%s|res=%dx%d|count=%d|ms_avg=%.3f|ms_p50=%.3f|ms_p95=%.3f|fps=%.1f|prim_peak=%d|draw_peak=%d" % [
		tag, _res.x, _res.y, count, avg * 1000.0, p50 * 1000.0, p95 * 1000.0,
		1.0 / maxf(avg, 1e-6), prim_peak, draw_peak])
