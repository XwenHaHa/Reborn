# T040/T043a full headless regression batch (Docs/Evidence/T040.md, T043a.md)
# Usage (must go through the zero-window chain):
#   wscript E:\Reborn\Tools\NoWindow.vbs <outer.log> "powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\ZeroWindowRun.ps1 -Name batch -Script E:\Reborn\Tools\t040_headless_batch.ps1 -TimeoutSec 2400"
#   (optionally) ... -Script "E:\Reborn\Tools\t040_headless_batch.ps1"  with -Only for subsets
#
# 自检守卫（T043a）：每套必须
#   1) EXIT=0
#   2) 有可解析的 SUMMARY/RESULT，且 checks > 0
#   3) failures = 0（兼容 t031 的 `fails=` 旧格式）
#   4) 没有 SCRIPT ERROR
#   5) RESULT|FAIL 与 failures=0 不得自相矛盾
# 任一不满足 → 该套 RED，日志写 GUARD|...|RED|原因，整体非零退出。
param(
    [string[]]$Only = @(),
    [int]$Runs = 1,
    [string]$OutLog = 'E:\Reborn\Tools\Probes\t040_headless_batch.log'
)
$ErrorActionPreference = 'Stop'
# 便于经零窗口链（NoWindow.vbs 不能透传参数）用环境变量指定子集/重复次数。
if ($Only.Count -eq 0 -and $env:T040_ONLY) { $Only = $env:T040_ONLY -split ',' }
if ($Runs -le 1 -and $env:T040_RUNS) { $Runs = [int]$env:T040_RUNS }
if ($env:T040_OUTLOG) { $OutLog = $env:T040_OUTLOG }
$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'
$proj = 'E:\Reborn\Game\Reborn'
$log = $OutLog
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Remove-Item $log -ErrorAction SilentlyContinue

$all = Get-ChildItem "$proj\tests" -Filter 'run_*.gd' |
	Where-Object { $_.Name -ne 'run_art05_input.gd' } |
	Sort-Object Name |
	Select-Object -ExpandProperty BaseName
$suites = if ($Only.Count -gt 0) { @($Only) } else { @($all) }
$tmpDir = 'E:\Reborn\Tools\Probes\t040_batch_tmp'
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$grandChecks = 0
$grandFails = 0
$bad = @()

function Get-Result($lines) {
	# 返回 @{ checks=<int>; fails=<int>; hasResult=<bool>; failFlag=<bool> } 或 $null。
	$checks = -1
	$fails = -1
	$hasResult = $false
	$failFlag = $false
	foreach ($ln in $lines) {
		if ($ln -match 'SUMMARY\|') { $hasResult = $true }
		if ($ln -match 'RESULT\|') { $hasResult = $true }
		if ($ln -match 'SUMMARY\|.*checks=(\d+)\|.*(?:failures|fails)=(\d+)') {
			$checks = [int]$Matches[1]; $fails = [int]$Matches[2]
		} elseif ($ln -match 'RESULT\|.*?checks=(\d+)\|fails=(\d+)') {
			$checks = [int]$Matches[1]; $fails = [int]$Matches[2]
		} elseif ($ln -match 'RESULT\|pass=(\d+)\|fail=(\d+)') {
			$checks = [int]$Matches[1]; $fails = [int]$Matches[2]
		}
		if ($ln -match 'RESULT\|FAIL\s*$') { $failFlag = $true }
	}
	if (-not $hasResult) { return $null }
	return @{ checks = $checks; fails = $fails; hasResult = $true; failFlag = $failFlag }
}

for ($r = 1; $r -le $Runs; $r++) {
	$grandChecks = 0
	$grandFails = 0
	$bad = @()
	Add-Content $log "RUN|$r|suites=$($suites.Count)"
	foreach ($t in $suites) {
		# 必须用 Start-Process -Wait + 重定向文件：Godot 是 GUI 子系统 exe，PowerShell 的
		# `&` 不会等待也不会捕获 stdout。GUI exe + --headless + 重定向 = 零窗口；
		# 不要改回 `_console.exe`（会弹终端）。
		$o = Join-Path $tmpDir ("{0}.r{1}.out.log" -f $t, $r)
		$e = Join-Path $tmpDir ("{0}.r{1}.err.log" -f $t, $r)
		$sw = [System.Diagnostics.Stopwatch]::StartNew()
		$p = Start-Process -FilePath $godot `
			-ArgumentList @('--headless', '--path', $proj, '--script', "res://tests/$t.gd", '--quit-after', '300000') `
			-RedirectStandardOutput $o -RedirectStandardError $e -Wait -PassThru
		$sw.Stop()
		$code = $p.ExitCode
		$ms = $sw.ElapsedMilliseconds
		$lines = @(Get-Content -LiteralPath $o -ErrorAction SilentlyContinue)
		$errLines = @(Get-Content -LiteralPath $e -ErrorAction SilentlyContinue)
		$err = (($lines + $errLines) | Select-String -Pattern 'SCRIPT ERROR' | Select-Object -First 1).Line
		$res = Get-Result $lines
		$resChecks = if ($null -ne $res -and $res.checks -ge 0) { [int]$res.checks } else { 0 }
		$resFails = if ($null -ne $res -and $res.fails -ge 0) { [int]$res.fails } else { 0 }
		# 并账必须覆盖**所有**套件（含 RED），否则 RED 套的 checks/fails 会被漏计
		$grandChecks += $resChecks
		$grandFails += $resFails
		$reason = ''
		if ($code -ne 0) { $reason = 'exit=' + $code }
		elseif ($null -eq $res) { $reason = 'unparseable' }
		elseif ($res.checks -le 0) { $reason = 'checks=0' }
		elseif ($res.fails -lt 0) { $reason = 'no_counts' }
		elseif ($res.fails -ne 0) { $reason = 'failures=' + $res.fails }
		elseif ($res.failFlag) { $reason = 'RESULT=FAIL' }
		elseif ($err) { $reason = 'SCRIPT ERROR' }
		if ($reason -ne '') {
			$bad += $t
			Add-Content $log "GUARD|$t|RED|cause=$reason|exit=$code|checks=$resChecks|fails=$resFails"
		} else {
			Add-Content $log "GUARD|$t|OK|exit=0|checks=$resChecks|fails=$resFails"
		}
		Add-Content $log "  => $t EXIT=$code $resChecks/$resFails ms=$ms $err"
	}
	Add-Content $log "RUN|$r|TOTAL|suites=$($suites.Count)|checks=$grandChecks|failures=$grandFails|bad=$($bad.Count)"
	if ($bad.Count -gt 0) {
		Add-Content $log "VERDICT|RED|bad=$($bad.Count)|list=$($bad -join ',')"
		Write-Host "VERDICT|RED|run=$r|bad=$($bad.Count)|$($bad -join ',')"
	} else {
		Add-Content $log "VERDICT|PASS|run=$r|checks=$grandChecks|failures=0"
		Write-Host "VERDICT|PASS|run=$r|suites=$($suites.Count)|checks=$grandChecks|failures=0"
	}
}
if ($bad.Count -gt 0) { exit 1 }
exit 0
