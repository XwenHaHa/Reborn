# T043a CPU 负载复跑：启动 N 个**无窗口**忙进程（默认 8），跑批期间保持；结束后按 PID 收掉。
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\t043a_cpu_load.ps1 -Count 8 -DurationSec 3600
#   powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\t043a_cpu_load.ps1 -Stop
# 兼容 PowerShell 5.1。忙进程用 -WindowStyle Hidden 启动，理论上不产生可见窗口；
# 若产生可见窗口，ZeroWindowRun 的 visible_hits 会 >0，验收数字本身即可暴露。
param(
    [int]$Count = 8,
    [int]$DurationSec = 3600,
    [string]$PidFile = 'E:\Reborn\Tools\Probes\cpu_load_pids.txt',
    [switch]$Stop
)
$ErrorActionPreference = 'Stop'

function Get-KnownPids {
    if (-not (Test-Path -LiteralPath $PidFile)) { return @() }
    return @(Get-Content -LiteralPath $PidFile | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
}

if ($Stop) {
    $pids = Get-KnownPids
    $killed = 0
    foreach ($procId in $pids) {
        try {
            $p = Get-Process -Id $procId -ErrorAction Stop
            Stop-Process -Id $procId -Force
            $killed++
        } catch {}
    }
    Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
    Write-Host "LOAD|STOP|pids=$($pids.Count)|killed=$killed"
    exit 0
}

# 收掉上一轮残留（只杀本文件记录过的 PID）
$old = Get-KnownPids
foreach ($procId in $old) {
    try { Stop-Process -Id $procId -Force } catch {}
}
Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue

$body = '$end=(Get-Date).AddSeconds(' + $DurationSec + '); $n=0; while((Get-Date) -lt $end){ for($i=0;$i -lt 200000;$i++){ $n += $i } }'
$pids = New-Object System.Collections.Generic.List[int]
for ($i = 1; $i -le $Count; $i++) {
    $p = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $body) `
        -WindowStyle Hidden -PassThru
    $pids.Add($p.Id)
}
Set-Content -LiteralPath $PidFile -Value ($pids -join "`r`n") -Encoding ASCII

$logical = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
Start-Sleep -Seconds 3
$load = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
Write-Host ("LOAD|START|count={0}|logical_cpus={1}|load_pct={2}|duration_s={3}|pids={4}" -f $Count, $logical, $load, $DurationSec, ($pids -join ','))
exit 0
