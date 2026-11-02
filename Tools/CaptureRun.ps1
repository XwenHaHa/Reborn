# CaptureRun.ps1 —— 统一的非 headless 实跑/取证启动包装（ART10 工具链约定）
#
# 解决三件事（都是 2026-11-02 实测踩过的坑，见 Docs/Evidence/ART10_BOARD_PARITY_PASS.md 与 ART07 证据 §9.4）：
#   1. **窗口不弹前台**：用 Godot 的 `--position X,Y` 把窗口直接创建在**屏幕外**——
#      窗口从头到尾不在任何显示器上出现，负责人不会再被晃到。
#      （不要用最小化：最小化窗口会停止渲染，截图会拿到黑帧。）
#   2. **print() 不再挂死**：Godot 的 print() 写入"读端已死"的管道会阻塞主线程
#      （前台命令超时转后台时管道就断了，症状=工具卡在某个 view 再也不存图）。
#      本包装用 Start-Process -RedirectStandardOutput 把输出写进日志文件，天然免疫。
#   3. **永远用 GUI 版 exe，不要用 console 版**：`Godot_v4.7.2-stable_win64_console.exe`
#      是控制台程序，哪怕加了 --headless / 参数全部正确，它本身也会在桌面上弹一个
#      黑色终端窗口（负责人 2026-11-02 二次反馈的晃眼来源）。日志一律由本包装的
#      Start-Process 重定向获得，与 exe 类型无关。
#
# 用法（所有捕获工具统一走这里，不要再直接 & godot）：
#   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_creek.gd -UserArgs creek
#   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_art09_board.gd -UserArgs ravine -TimeoutSec 600
#   headless（导入/生成器/回归，同样零窗口、日志落文件）：
#   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Headless -Script tests/run_art09_frame_contract.gd -TimeoutSec 300
#   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Headless -Script tests/tool_make_ravine_board.gd -TimeoutSec 300
#
# 参数：
#   -Script     相对 Game/Reborn 的脚本路径（tests/xxx.gd），或完整 res:// 路径
#   -UserArgs   传给脚本的用户参数（会被拼到 `--` 之后），数组或单词
#   -QuitAfter  --quit-after 帧数上限（默认 200000 ≈ 20-30 分钟，仅作保险）
#   -TimeoutSec 外层等待上限（默认 900 秒；超时杀进程并报 TIMEOUT，日志保留）
#   -LogDir     日志目录（默认 Art/Probes/.capture_logs）
#
# 返回：Godot 退出码（超时为 124）。日志路径会打印在输出第一行。

param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string[]]$UserArgs = @(),
    [int]$QuitAfter = 200000,
    [int]$TimeoutSec = 900,
    # -Headless：headless 导入/生成器/回归也走本包装。GUI exe + --headless + 输出重定向
    # = 全程零窗口；**不要**为了看输出改用 console 版 exe——它会额外弹一个黑色终端窗口
    # （负责人 2026-11-02 二次反馈的晃眼来源）。headless 模式下窗口无渲染，产物是日志/场景文件。
    [switch]$Headless,
    [string]$LogDir = "E:\Reborn\Art\Probes\.capture_logs",
    [string]$Godot = "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe",
    [string]$Project = "E:\Reborn\Game\Reborn"
)

$ErrorActionPreference = "Stop"

# --- 屏幕外坐标：从虚拟屏幕左上角再往左/上挪 2400 物理像素（多显示器也安全）---
Add-Type -AssemblyName System.Windows.Forms
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$offX = $vs.X - 2400
$offY = $vs.Y - 2400
$offPos = "{0},{1}" -f $offX, $offY

# --- 归一化脚本路径 ---
if ($Script -notlike "res://*") { $Script = "res://" + ($Script -replace '^[/\\]+', '') }

# --- 日志文件 ---
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$base = [System.IO.Path]::GetFileNameWithoutExtension(($Script -replace '^res://', ''))
$logPath = Join-Path $LogDir ("{0}_{1}.log" -f $base, $stamp)
$errPath = Join-Path $LogDir ("{0}_{1}.err.log" -f $base, $stamp)

# --- 组装参数 ---
$argList = @(
    "--path", $Project
)
if ($Headless) {
    $argList += "--headless"
} else {
    # 只有非 headless 才需要把渲染窗口挪到屏幕外
    $argList += "--position"
    $argList += $offPos
}
$argList += @(
    "--script", $Script,
    "--quit-after", "$QuitAfter"
)
if ($UserArgs.Count -gt 0) {
    $argList += "--"
    $argList += $UserArgs
}

Write-Host "CAPTURE_RUN|log=$logPath"
Write-Host "CAPTURE_RUN|script=$Script|user_args=[$($UserArgs -join ' ')]|window_offscreen=$offPos"

# 注意：**不要**用 -WindowStyle Hidden / 最小化 —— 隐藏窗口可能停止渲染拿到黑帧；
# 屏幕外定位（--position）已经保证窗口不可见，这里用默认窗口风格保持渲染循环活着。
$spArgs = @{
    FilePath               = $Godot
    ArgumentList           = $argList
    RedirectStandardOutput = $logPath
    RedirectStandardError  = $errPath
    PassThru               = $true
}
$proc = Start-Process @spArgs

$exited = $proc.WaitForExit($TimeoutSec * 1000)
if (-not $exited) {
    # 超时：先杀主进程（渲染窗口），日志保留供诊断
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    Write-Host "CAPTURE_RUN|TIMEOUT|${TimeoutSec}s|log=$logPath"
    Write-Host "CAPTURE_RUN|tail:"
    if (Test-Path $logPath) { Get-Content $logPath -Tail 12 }
    exit 124
}

$proc.Refresh()
$code = $proc.ExitCode
if ($null -eq $code) { $code = 0 }
Write-Host "CAPTURE_RUN|exit=$code|log=$logPath"
Write-Host "CAPTURE_RUN|tail:"
if (Test-Path $logPath) { Get-Content $logPath -Tail 12 }
exit $code
