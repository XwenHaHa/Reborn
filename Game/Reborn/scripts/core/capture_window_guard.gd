extends Node
## CaptureWindowGuard —— 取证运行的"窗口硬保证"（ART12 工具链，2026-11-02）。
##
## 背景：Godot 在 Windows 上创建主窗口时先落在项目默认位置（实测首见 rect 在可见区），
## 命令行 `--position` 要到稍后才生效——负责人多次看到窗口在左上角"闪一下"。
## 外层 `Tools/CaptureRun.ps1` 的 Win32 监视器只能把首见窗口尽快挪走（毫秒级兜底），
## 要**零可见帧**必须在引擎侧、首帧渲染前把窗口挪到屏幕外。
##
## 做法：本 autoload 在实例化时检查环境变量 `REBORN_CAPTURE_OFFSCREEN`（只有
## CaptureRun.ps1 会设它）。设了 = 本次是取证运行 → 立即 `window_set_position`
## 到 (-4000,-4000)（任何多显示器布局之外）；没设 = 正常游玩/编辑器运行，**零副作用**
## （不创建任何节点逻辑、不碰场景、不碰玩法）。
##
## 回退：从 project.godot 的 [autoload] 删掉这一行即可；脚本本身无状态。

func _ready() -> void:
	var flag := OS.get_environment("REBORN_CAPTURE_OFFSCREEN")
	if flag != "1":
		return
	if DisplayServer.get_name() == "headless":
		return
	# 首帧前硬挪屏幕外（不隐藏、不最小化——那会停止渲染拿到黑帧）。
	# t=引擎启动起的毫秒数：用来和 winmon 日志对表，量出"窗口 show → autoload 挪走"
	# 的真实可见时长（监视器侧同步 SetWindowPos 在启动期会被不泵消息的主线程阻塞，
	# 只能靠这里的进程内时间戳交叉验证）。
	var pos_before := DisplayServer.window_get_position()
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	print("WINDOW_GUARD|moved_offscreen|t=%dms|before=%s|after=%s"
		% [Time.get_ticks_msec(), pos_before, DisplayServer.window_get_position()])
