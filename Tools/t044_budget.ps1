# T044：资产预算实测（**非 headless**，必须真渲染才测得到 GPU 成本）。
# 窗口放到屏幕外（--position 2400,1200），不抢前台、不点鼠标。
# 产物：Tools/Probes/t044_budget.log（gitignore 的 *.log），每行 BUDGET|...
$ErrorActionPreference = 'Stop'
$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
$log = 'E:\Reborn\Tools\Probes\t044_budget.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null

& $godot --path $proj --position 2400,1200 `
    --script 'res://tests/tool_t044_budget_probe.gd' --quit-after 60000 -- budget *> $log
$code = $LASTEXITCODE
Get-Content $log -Encoding UTF8 | Select-String -Pattern '^BUDGET\|' | ForEach-Object { Write-Host $_.Line }
Write-Host "BUDGET|exit=$code|log=$log"
exit $code
