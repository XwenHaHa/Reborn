extends SceneTree
## ART03-③/④ 收尾：**客观性能探针** —— 墙类 120,668 tris 到底要多少代价。
##
## 为什么要有这个工具：`Docs/ART_ASSET_SPEC.md` 只给了"每件资产"的面数预算，没有场景总预算；
## 石墙平铺 90 件后墙体成了本关卡最大开销，但一直是"没实测"的状态。这里把 draw call、
## 三角形数、每帧耗时都测出来，避免用"感觉不卡"糊过去。
##
## 运行（**不能用 --headless**，无头是 dummy 渲染器）：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_perf_probe.gd' --quit-after 4000 -- perf
##
## 做法：关 vsync、不限帧；先空转 WARMUP 帧再采 SAMPLE 帧（每帧读 Performance 监视器）。

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
const RES := Vector2i(1280, 720)
const WARMUP := 60
const SAMPLE := 240

var _world: Node3D = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("perf"):
		print("PERF|ERROR|need_arg|pass '-- perf'")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = RES

	var packed: PackedScene = load(LEVEL)
	if packed == null:
		print("PERF|ERROR|level_load_failed")
		quit(1)
		return
	_world = packed.instantiate() as Node3D
	root.add_child(_world)

	var cam := Camera3D.new()
	cam.name = "PerfCam"
	cam.near = 0.05
	cam.far = 400.0
	_world.add_child(cam)
	await process_frame
	# 站在庭院中间朝北看：把四面围栏里的两面推进视野（最坏方向）
	cam.look_at_from_position(Vector3(0.0, 1.6, 6.0), Vector3(0.0, 1.2, 30.0), Vector3.UP)
	cam.current = true

	for i in WARMUP:
		await process_frame

	var frames: Array[float] = []
	var prim_peak := 0
	var draw_peak := 0
	var objects_peak := 0
	var prim_sum := 0
	var draw_sum := 0
	var t_start := Time.get_ticks_usec()
	for i in SAMPLE:
		await RenderingServer.frame_post_draw
		var t := Time.get_ticks_usec()
		frames.append(float(t - t_start) / 1000000.0)
		t_start = t
		var prim := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var draw := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		prim_sum += prim
		draw_sum += draw
		prim_peak = maxi(prim_peak, prim)
		draw_peak = maxi(draw_peak, draw)
		objects_peak = maxi(objects_peak, objs)

	frames.sort()
	var n := frames.size()
	var avg := 0.0
	for f in frames:
		avg += f
	avg /= float(maxi(1, n))
	var p50: float = frames[int(float(n) * 0.5)]
	var p95: float = frames[mini(n - 1, int(float(n) * 0.95))]
	print("PERF|res=%dx%d|warmup=%d|sample=%d" % [RES.x, RES.y, WARMUP, n])
	print("PERF|frame_ms|avg=%.3f|p50=%.3f|p95=%.3f|max=%.3f|avg_fps=%.1f" % [
		avg * 1000.0, p50 * 1000.0, p95 * 1000.0, frames[n - 1] * 1000.0, 1.0 / maxf(avg, 1e-6)])
	print("PERF|primitives|avg=%d|peak=%d" % [prim_sum / maxi(1, n), prim_peak])
	print("PERF|draw_calls|avg=%d|peak=%d" % [draw_sum / maxi(1, n), draw_peak])
	print("PERF|objects_in_frame|peak=%d" % objects_peak)
	print("PERF|done")
	quit(0)
