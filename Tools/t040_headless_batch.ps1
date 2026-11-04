# T040 full headless regression batch (for Docs/Evidence/T040.md)
# Usage: powershell -File E:\Reborn\Tools\t040_headless_batch.ps1
# Log: E:\Reborn\Tools\Probes\t040_headless_batch.log
# Same ordering/accounting as t038: sequential, t031 counted via fails=.
$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
$log = 'E:\Reborn\Tools\Probes\t040_headless_batch.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Remove-Item $log -ErrorAction SilentlyContinue

$suites = Get-ChildItem "$proj\tests" -Filter 'run_*.gd' |
	Where-Object { $_.Name -ne 'run_art05_input.gd' } |
	Select-Object -ExpandProperty BaseName
$totalChecks = 0
$totalFails = 0
$bad = @()
foreach ($t in $suites) {
	$out = & $godot --headless --path $proj --script "res://tests/$t.gd" --quit-after 300000 2>&1
	$code = $LASTEXITCODE
	$line = ($out | Select-String -Pattern 'SUMMARY\|.*' | Select-Object -First 1).Line
	if (-not $line) {
		$line = ($out | Select-String -Pattern 'RESULT\|.*' | Select-Object -First 1).Line
	}
	$err = ($out | Select-String -Pattern 'SCRIPT ERROR' | Select-Object -First 1).Line
	Add-Content $log "$t => EXIT=$code $line $err"
	if ($code -ne 0 -or $err) { $bad += $t }
	if ($line -match 'checks=(\d+)\|(?:failures|fails)=(\d+)') {
		$totalChecks += [int]$Matches[1]
		$totalFails += [int]$Matches[2]
	} elseif ($line -match 'pass=(\d+)\|fail=(\d+)') {
		$totalChecks += [int]$Matches[1]
		$totalFails += [int]$Matches[2]
	}
}
Add-Content $log "TOTAL|suites=$($suites.Count)|checks=$totalChecks|failures=$totalFails"
if ($bad.Count -gt 0) { Add-Content $log "RED: $($bad -join ', ')" }
Write-Host "DONE suites=$($suites.Count) totalChecks=$totalChecks totalFails=$totalFails bad=$($bad.Count)"
