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
# 墙钟守卫（T043a）：每套记录起止墙钟与输出静默上限；单套静默 >30 s，或整轮墙钟
# 与累计套件耗时偏离 >60 s → 该轮 INVALID（疑似系统待机/挂起，不算通过也不算失败），
# 退出码 2 要求重跑。可用 T040_GAP_SEC / T040_DRIFT_SEC 缩小阈值做验证。
param(
    [string[]]$Only = @(),
    [int]$Runs = 1,
    [string]$OutLog = 'E:\Reborn\Tools\Probes\t040_headless_batch.log',
    [int]$GapSec = 30,
    [int]$DriftSec = 60
)
$ErrorActionPreference = 'Stop'
# 便于经零窗口链（NoWindow.vbs 不能透传参数）用环境变量指定子集/重复次数。
if ($Only.Count -eq 0 -and $env:T040_ONLY) { $Only = $env:T040_ONLY -split ',' }
if ($Runs -le 1 -and $env:T040_RUNS) { $Runs = [int]$env:T040_RUNS }
if ($env:T040_OUTLOG) { $OutLog = $env:T040_OUTLOG }
if ($env:T040_GAP_SEC) { $GapSec = [int]$env:T040_GAP_SEC }
if ($env:T040_DRIFT_SEC) { $DriftSec = [int]$env:T040_DRIFT_SEC }
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
$anyInvalid = $false

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

# 进程执行器（C#）：Start-Process -PassThru 在 PS 5.1 上拿不到 ExitCode（只有 -Wait 才有），
# 这里用 .NET Process 自己等待并读退出码；同时按"输出文件是否有新增"监控墙钟空洞，
# 静默超过 gapSec 就 Kill 并回报 INVALID。输出行实时写入文件，供后续解析。
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

public static class BatchRunner {
    public static string Run(string exe, string args, string outFile, string errFile, int gapSec) {
        var psi = new ProcessStartInfo(exe, args);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        var outW = new StreamWriter(outFile, false) { AutoFlush = true };
        var errW = new StreamWriter(errFile, false) { AutoFlush = true };
        var last = DateTime.UtcNow;
        var maxSil = 0.0;
        double gap = -1.0;
        int code = -1;
        try {
            using (var p = new Process()) {
                p.StartInfo = psi;
                p.OutputDataReceived += (s, e) => { if (e.Data != null) { try { outW.WriteLine(e.Data); } catch {} last = DateTime.UtcNow; } };
                p.ErrorDataReceived += (s, e) => { if (e.Data != null) { try { errW.WriteLine(e.Data); } catch {} last = DateTime.UtcNow; } };
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                while (!p.HasExited) {
                    Thread.Sleep(500);
                    if (p.HasExited) break;
                    var sil = (DateTime.UtcNow - last).TotalSeconds;
                    if (sil > maxSil) maxSil = sil;
                    if (sil > gapSec) { gap = Math.Round(sil, 1); try { p.Kill(); } catch {} break; }
                }
                p.WaitForExit();
                try { code = p.ExitCode; } catch { code = -1; }
            }
        } catch {
            try { outW.WriteLine("RUNNER_ERROR|" + DateTime.UtcNow.ToString("o")); } catch {}
        } finally {
            try { outW.Flush(); errW.Flush(); outW.Dispose(); errW.Dispose(); } catch {}
        }
        return "exit=" + code + "|gap_s=" + gap.ToString("0.0") + "|max_sil=" + maxSil.ToString("0.0");
    }
}
'@

for ($r = 1; $r -le $Runs; $r++) {
	$grandChecks = 0
	$grandFails = 0
	$bad = @()
	$invalid = @()
	$sumMs = 0
	$runStart = Get-Date
	Add-Content $log "RUN|$r|suites=$($suites.Count)"
	foreach ($t in $suites) {
		# Godot 是 GUI 子系统 exe，必须重定向 stdout/stderr；GUI exe + --headless + 重定向 =
		# 零窗口，不要改回 `_console.exe`（会弹终端）。
		$o = Join-Path $tmpDir ("{0}.r{1}.out.log" -f $t, $r)
		$e = Join-Path $tmpDir ("{0}.r{1}.err.log" -f $t, $r)
		Remove-Item -LiteralPath $o, $e -ErrorAction SilentlyContinue
		$sw = [System.Diagnostics.Stopwatch]::StartNew()
		$startWall = Get-Date
		$argStr = '--headless --path "' + $proj + '" --script "res://tests/' + $t + '.gd" --quit-after 300000'
		$rc = [BatchRunner]::Run($godot, $argStr, $o, $e, $GapSec)
		$sw.Stop()
		$endWall = Get-Date
		$ms = $sw.ElapsedMilliseconds
		$sumMs += $ms
		$kv = @{}
		foreach ($kvp in $rc.Split('|')) {
			$pair = $kvp.Split('=', 2)
			if ($pair.Count -eq 2) { $kv[$pair[0]] = $pair[1] }
		}
		$code = [int]$kv['exit']
		$gapS = [double]$kv['gap_s']
		$maxSilence = [double]$kv['max_sil']
		$gapDetected = ($gapS -ge 0)
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
		if ($gapDetected) {
			$invalid += $t
			Add-Content $log "GUARD|$t|INVALID|cause=silence_gap|gap_s=$gapS|max_silence_s=$([math]::Round($maxSilence, 1))|exit=$code|checks=$resChecks|fails=$resFails"
		} elseif ($reason -ne '') {
			$bad += $t
			Add-Content $log "GUARD|$t|RED|cause=$reason|exit=$code|checks=$resChecks|fails=$resFails"
		} else {
			Add-Content $log "GUARD|$t|OK|exit=0|checks=$resChecks|fails=$resFails"
		}
		Add-Content $log ("WALL|{0}|start={1}|end={2}|wall_ms={3}|max_silence_s={4}" -f $t, $startWall.ToString('HH:mm:ss.fff'), $endWall.ToString('HH:mm:ss.fff'), $ms, [math]::Round($maxSilence, 1))
		Add-Content $log "  => $t EXIT=$code $resChecks/$resFails ms=$ms $err"
	}
	$runEnd = Get-Date
	$runWallMs = [int]($runEnd - $runStart).TotalMilliseconds
	$driftMs = $runWallMs - $sumMs
	Add-Content $log ("RUN|$r|WALL|start={0}|end={1}|wall_ms={2}|sum_ms={3}|delta_ms={4}" -f $runStart.ToString('HH:mm:ss.fff'), $runEnd.ToString('HH:mm:ss.fff'), $runWallMs, $sumMs, $driftMs)
	if ($driftMs -gt ($DriftSec * 1000)) { $invalid += 'run_drift' }
	Add-Content $log "RUN|$r|TOTAL|suites=$($suites.Count)|checks=$grandChecks|failures=$grandFails|bad=$($bad.Count)|invalid=$($invalid.Count)"
	if ($invalid.Count -gt 0) {
		$anyInvalid = $true
		Add-Content $log "VERDICT|INVALID|run=$r|list=$($invalid -join ',')|drift_ms=$driftMs"
		Write-Host "VERDICT|INVALID|run=$r|$($invalid -join ',')"
	} elseif ($bad.Count -gt 0) {
		Add-Content $log "VERDICT|RED|bad=$($bad.Count)|list=$($bad -join ',')"
		Write-Host "VERDICT|RED|run=$r|bad=$($bad.Count)|$($bad -join ',')"
	} else {
		Add-Content $log "VERDICT|PASS|run=$r|checks=$grandChecks|failures=0"
		Write-Host "VERDICT|PASS|run=$r|suites=$($suites.Count)|checks=$grandChecks|failures=0"
	}
}
if ($anyInvalid) { exit 2 }
if ($bad.Count -gt 0) { exit 1 }
exit 0
