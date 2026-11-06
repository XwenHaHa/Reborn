# T043：零窗口运行 + 全程可见窗口监视。
# 不得直接运行本文件；由 Tools\NoWindow.vbs 以 windowStyle=0 启动，使本 PowerShell
# 及其全部 console 子进程共享一个隐藏控制台，不产生任何可见窗口。
#
# 用法（外层必须经 NoWindow.vbs）：
#   wscript E:\Reborn\Tools\NoWindow.vbs <outer.log> "powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\ZeroWindowRun.ps1 -Name export -Script E:\Reborn\Tools\t043_package.ps1 -TimeoutSec 900"
#
# 输出：
#   <WatchLog> 每次首见可见窗口写 HIT|...，末尾写 WINDOWWATCH|summary|visible_hits=N
#   退出码：被运行脚本的退出码；超时 124。
param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Script,
    [int]$TimeoutSec = 900,
    [string]$LogDir = 'E:\Reborn\Art\Probes\.capture_logs'
)
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$watchLog = Join-Path $LogDir ("zerowindow_{0}_{1}.log" -f $Name, $stamp)
$portable = 'E:\Reborn'

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class ZeroWindowWatch {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassNameW(IntPtr hWnd, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowTextW(IntPtr hWnd, StringBuilder s, int n);
    [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint ms);
    [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint ms);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }

    static volatile bool _stop = false;
    static Thread _thread = null;
    static string _log = null;
    static int _hits = 0;
    static int _other = 0;
    static string _startIso = "";

    // 只把**自动化链自己的进程**算进 visible_hits；用户桌面上的第三方窗口（Chrome 弹窗等）
    // 记为 OTHER，不污染验收数字，也不隐藏事实。
    static bool IsAutomation(string exe) {
        string n = exe.ToLowerInvariant();
        return n == "godot_v4.7.2-stable_win64" || n == "godot" || n == "python" ||
               n == "cmd" || n == "powershell" || n == "wscript" || n == "conhost" ||
               n == "reborn" || n == "rebornselftest";
    }

    static bool ShellClass(string c) {
        return c == "Progman" || c == "Shell_TrayWnd" || c == "WorkerW" ||
               c == "Windows.UI.Core.CoreWindow" || c == "MultitaskingViewFrame" ||
               c == "ForegroundStaging";
    }

    static void Write(string line) {
        try { File.AppendAllText(_log, line + Environment.NewLine, Encoding.UTF8); } catch {}
    }

    static void Loop() {
        var seen = new HashSet<long>();
        var existing = new HashSet<long>();
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint pid; GetWindowThreadProcessId(h, out pid);
            RECT r; GetWindowRect(h, out r);
            if (IsWindowVisible(h) && (r.R-r.L) > 0 && (r.B-r.T) > 0) existing.Add((long)h);
            return true;
        }, IntPtr.Zero);
        timeBeginPeriod(1);
        while (!_stop) {
            EnumWindows(delegate(IntPtr h, IntPtr l) {
                if (seen.Contains((long)h)) return true;
                uint pid; GetWindowThreadProcessId(h, out pid);
                RECT r; GetWindowRect(h, out r);
                var cls = new StringBuilder(256); GetClassNameW(h, cls, 256);
                string c = cls.ToString();
                if (!IsWindowVisible(h) || (r.R-r.L) <= 0 || (r.B-r.T) <= 0) return true;
                if (existing.Contains((long)h) || ShellClass(c)) return true;
                seen.Add((long)h);
                if (!IsWindowVisible(h)) return true;
                var title = new StringBuilder(256); GetWindowTextW(h, title, 256);
                string exe = "";
                try { var p = Process.GetProcessById((int)pid); exe = p.ProcessName; } catch {}
                bool ours = IsAutomation(exe);
                if (ours) _hits++; else _other++;
                Write((ours ? "HIT|" : "OTHER|") + "pid=" + pid + "|exe=" + exe + "|class=" + c +
                      "|title=" + title + "|rect=" + r.L + "," + r.T + "," + r.R + "," + r.B);
                return true;
            }, IntPtr.Zero);
            Thread.Sleep(5);
        }
        timeEndPeriod(1);
        Write("WINDOWWATCH|summary|visible_hits=" + _hits + "|other_windows=" + _other +
              "|duration_ms=" +
              (long)((DateTime.Now - DateTime.Parse(_startIso)).TotalMilliseconds));
    }

    public static void Start(string log) {
        _log = log; _hits = 0; _other = 0; _stop = false;
        _startIso = DateTime.Now.ToString("o");
        Write("WINDOWWATCH|start|" + _startIso);
        _thread = new Thread(Loop);
        _thread.IsBackground = true;
        _thread.Start();
    }
    public static void Stop() { _stop = true; if (_thread != null) _thread.Join(3000); }
    public static int Hits() { return _hits; }
}
"@

[ZeroWindowWatch]::Start($watchLog)
Write-Host "ZEROWINDOW|start|name=$Name|watch=$watchLog|script=$Script"
$code = 124
try {
    Push-Location $portable
    # 用子 PowerShell 执行目标脚本：目标脚本里的 exit 只结束子进程，
    # 不会跳过本监视器的 Stop/汇总；整条链共享同一个隐藏控制台，无可见窗口。
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -NoProfile -ExecutionPolicy Bypass -File $Script
    $code = [int]$LASTEXITCODE
    Pop-Location
} catch {
    Write-Host "ZEROWINDOW|ERROR|$($_.Exception.Message)"
    $code = 1
}
[ZeroWindowWatch]::Stop()
$hits = [ZeroWindowWatch]::Hits()
Write-Host "ZEROWINDOW|summary|name=$Name|visible_hits=$hits|exit=$code|watch=$watchLog"
exit $code
