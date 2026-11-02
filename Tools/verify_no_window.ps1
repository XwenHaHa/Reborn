# 验证"整条链路零可见窗口"（负责人 2026-11-02 二次反馈后）：
# 连续跑 2 次 CaptureRun（1 次 headless 回归 + 1 次非 headless 截图），
# 轮询记录所有 Godot 进程的 MainWindowHandle / MainWindowTitle 直到运行结束。
$ErrorActionPreference = "Stop"

function Poll-GodotWindows([System.Management.Automation.Job]$job, [string]$label) {
    $seenHandles = 0
    $titles = New-Object System.Collections.Generic.HashSet[string]
    $samples = 0
    while ($job.State -eq "Running") {
        $procs = Get-Process -Name "Godot*" -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            try { $p.Refresh() } catch { continue }
            $h = $p.MainWindowHandle
            if ($null -ne $h -and $h -ne 0) {
                $seenHandles += 1
                if ($p.MainWindowTitle) { $null = $titles.Add($p.MainWindowTitle) }
            }
        }
        $samples += 1
        Start-Sleep -Milliseconds 500
    }
    Write-Output ("WINPOLL|{0}|poll_samples={1}|window_handle_sightings={2}|titles=[{3}]" -f $label, $samples, $seenHandles, ($titles -join "; "))
}

# --- 第 1 次：headless 回归（GUI exe + --headless，应无任何窗口句柄）---
$job1 = Start-Job -ScriptBlock {
    powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\CaptureRun.ps1 -Headless -Script tests/run_art09_frame_contract.gd -TimeoutSec 240
    $LASTEXITCODE
}
Poll-GodotWindows $job1 "headless_run1"
$r1 = @(Receive-Job $job1)
Remove-Job $job1 -Force
Write-Output ("RUN1|exit={0}|summary={1}" -f ($r1 | Select-Object -Last 1), (($r1 | Select-String "SUMMARY|RESULT") -join " | "))

# --- 第 2 次：非 headless 截图（渲染窗口应在屏幕外）---
$job2 = Start-Job -ScriptBlock {
    powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_art09_board.gd -UserArgs ravine -TimeoutSec 240
    $LASTEXITCODE
}
Poll-GodotWindows $job2 "capture_run2"
$r2 = @(Receive-Job $job2)
Remove-Job $job2 -Force
Write-Output ("RUN2|exit={0}|saves_ok={1}" -f ($r2 | Select-Object -Last 1), (@($r2 | Select-String "save_result=0").Count))
Write-Output "VERIFY|done"
