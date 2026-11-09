# T050：鼠基础形体的正/侧/45° 低机位轮廓取证（**非 headless**，必须真渲染）。
# 窗口放屏幕外（--position 2400,1200），不抢前台。产物：user://t050_mouse_*.png → 拷到 Art/Probes/。
$ErrorActionPreference = 'Stop'
$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
$log = 'E:\Reborn\Tools\Probes\t050_silhouette.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null

& $godot --path $proj --position 2400,1200 `
    --script 'res://tests/tool_capture_t050_silhouette.gd' --quit-after 20000 -- t050 *> $log
$code = $LASTEXITCODE
Get-Content $log -Encoding UTF8 | Select-String -Pattern '^CAP\|t050' | ForEach-Object { Write-Host $_.Line }
Write-Host "T050|exit=$code|log=$log"
exit $code
