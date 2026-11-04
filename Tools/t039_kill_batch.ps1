# T039 real-process kill injection batch.
# Runs four save-phase kill + restart-verify pairs through Tools/CaptureRun.ps1.
# Uses the hidden desktop and GUI exe; each kill run must report visible_hits=0 and killed=1.
# ASCII-only on purpose: PowerShell 5 parsing of this repo's Chinese-comment scripts was flaky.
#
# Usage: powershell -ExecutionPolicy Bypass -File E:\Reborn\Tools\t039_kill_batch.ps1

$ErrorActionPreference = "Stop"
$cap = "E:\Reborn\Tools\CaptureRun.ps1"
$phases = @("before_tmp", "tmp_mid", "rename_gap", "bak_rotate")
$log = "E:\Reborn\Tools\Probes\t039_kill_batch.log"
if (-not (Test-Path (Split-Path $log))) { New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null }
Set-Content -Path $log -Value "T039KILL|batch_start" -Encoding UTF8

foreach ($phase in $phases) {
    Write-Host "T039KILL|phase=$phase|kill_run"
    $kill = & $cap -Script "tests/tool_capture_t039_kill.gd" `
        -UserArgs @("kill", $phase, "4000") `
        -KillOnMarker ("T039|phase|{0}|begin" -f $phase) `
        -KillGraceMs 400 -KillExitCode 137 -TimeoutSec 120 2>&1
    $killExit = $LASTEXITCODE
    $kill | Add-Content -Path $log -Encoding UTF8
    $monFile = Get-ChildItem "E:\Reborn\Art\Probes\.capture_logs\tool_capture_t039_kill_*.log.winmon.log" |
        Sort-Object LastWriteTime | Select-Object -Last 1
    $monText = if ($monFile) { Get-Content $monFile.FullName -Raw } else { "" }
    $killed = if ($monText -match "killed=1") { "1" } else { "0" }
    $visible = if ($monText -match "visible_hits=0") { "0" } else { "miss" }
    Write-Host "T039KILL|phase=$phase|kill_exit=$killExit|killed=$killed|visible_hits=$visible"

    Write-Host "T039KILL|phase=$phase|verify_run"
    $verify = & $cap -Script "tests/tool_capture_t039_kill.gd" `
        -UserArgs @("verify", $phase) -TimeoutSec 120 2>&1
    $verifyExit = $LASTEXITCODE
    $verify | Add-Content -Path $log -Encoding UTF8
    $verifyText = ($verify | Out-String)
    $verifyLine = ($verify | Select-String -Pattern "CAP\|t039\|verify" | Select-Object -Last 1)
    $nextLine = ($verify | Select-String -Pattern "CAP\|t039\|next_save" | Select-Object -Last 1)
    Write-Host "T039KILL|phase=$phase|verify_exit=$verifyExit"
    Write-Host "T039KILL|phase=$phase|$verifyLine"
    Write-Host "T039KILL|phase=$phase|$nextLine"
    Add-Content -Path $log -Value ("T039KILL|phase={0}|kill_exit={1}|killed={2}|visible_hits={3}|verify_exit={4}" -f $phase, $killExit, $killed, $visible, $verifyExit) -Encoding UTF8
}

Write-Host "T039KILL|batch_done|log=$log"
