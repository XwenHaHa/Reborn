# T052：鼠的待机 / 走 / 冲刺三种表现取证（**非 headless**，必须真渲染）。
$ErrorActionPreference = 'Stop'
$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
$log = 'E:\Reborn\Tools\Probes\t052_states.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null

& $godot --path $proj --position 2400,1200 `
    --script 'res://tests/tool_capture_t052_states.gd' --quit-after 20000 -- t052 *> $log
$code = $LASTEXITCODE
Get-Content $log -Encoding UTF8 | Select-String -Pattern '^CAP\|t052' | ForEach-Object { Write-Host $_.Line }
Write-Host "T052|exit=$code|log=$log"
exit $code
