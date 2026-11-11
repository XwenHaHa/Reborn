# T060：真实场景性能探针（**非 headless**，必须真渲染才测得到整帧成本）。
#
# 为什么不用 console exe / 直接 & godot：会让 Godot 窗口弹到负责人桌面上（Handoff 硬约束）。
# 统一经 `Tools/CaptureRun.ps1`：在自建隐藏桌面 `winsta0\RebornCapture` 上启动 GUI exe，
# 监视器应报 `windows_seen=0 / visible_hits=0`。
#
# 产物：`Tools/Probes/t060_perf.log`（gitignore 的 *.log），每行 `PERF|...`
$ErrorActionPreference = 'Stop'
$root = 'E:\Reborn'
$logDir = Join-Path $root 'Tools\Probes'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 't060_perf.log'

$out = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Tools\CaptureRun.ps1') `
    -Script tests/tool_t060_perf.gd -UserArgs t060 -QuitAfter 60000 -TimeoutSec 900 2>&1

$out | Set-Content -Path $log -Encoding UTF8
$out | Select-String -Pattern 'PERF\||WINMON\|summary|CAPTURE_RUN\|exit' | ForEach-Object { Write-Host $_.Line }

$code = 0
$exitLine = $out | Select-String -Pattern 'CAPTURE_RUN\|exit=(\d+)' | Select-Object -Last 1
if ($exitLine) { $code = [int]$exitLine.Matches[0].Groups[1].Value }
Write-Host "T060|exit=$code|log=$log"
exit $code
