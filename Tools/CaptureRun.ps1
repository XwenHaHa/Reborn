# CaptureRun.ps1 —— 统一的实跑/取证启动包装（ART10/ART12 工具链约定）
#
# 解决四件事（都是 2026-11-02 实测踩过的坑，见 ART07 证据 §9.4 与 Tools/README.md）：
#   1. **窗口零可见（自建隐藏桌面）**：`--position X,Y` 是"软"参数——实测（2026-11-02，
#      winmon 证据）Godot 在 Windows 上主窗口显式建在 (0,0)（不用 CW_USEDEFAULT，
#      STARTF_USEPOSITION 无效），且启动期主线程 ~2 秒不泵消息：--position / project
#      设置 / autoload（t≈2442ms 才跑，引擎内部位置仍是 (0,0)）/ 外部 SetWindowPos 全部
#      要等引擎泵消息后才生效，窗口会先可见 ~1.8 秒。唯一不动引擎源码的根治法：非
#      headless 默认在自建隐藏桌面（winsta0\RebornCapture）上 CreateProcess——子进程的
#      所有窗口只能建在那个桌面，用户桌面按定义不可见。兜底/取证仍在：
#        a. 隐藏桌面（主防线）：visible_hits 应为 0；winmon 同时枚举两个桌面留证；
#        b. autoload `capture_window_guard.gd`（env 门控 REBORN_CAPTURE_OFFSCREEN=1）：
#           首帧前 window_set_position 屏幕外；正常游玩不设变量，零副作用；
#        c. `--position` + Win32 监视器（兜底 + 取证）：~3ms 轮询记录两个桌面的窗口
#           矩形/隐藏/重现/回弹；万一隐藏桌面不可用（-VisibleDesktop 诊断模式），监视器
#           当场异步挪走（SWP_ASYNCWINDOWPOS，绝不同步调用——会被不泵消息的目标线程
#           阻塞 ~1.4 秒）。
#      每次运行把首见矩形+时间戳写进 `<log>.winmon.log`（可证明验收，见 ART07 §9.4）。
#   2. **print() 不再挂死**：Godot 的 print() 写入"读端已死"的管道会阻塞主线程
#      （前台命令超时转后台时管道就断了，症状=工具卡在某个 view 再也不存图）。
#      本包装用 CreateProcessW 的 STARTF_USESTDHANDLES 把输出写进日志文件，天然免疫。
#   3. **永远用 GUI 版 exe，不要用 console 版**：`Godot_v4.7.2-stable_win64_console.exe`
#      是控制台程序，哪怕加了 --headless / 参数全部正确，它本身也会在桌面上弹一个
#      黑色终端窗口（负责人二次反馈的晃眼来源）。
#   4. **headless 统一入口**：导入/生成器/回归也走本包装的 -Headless（GUI exe + --headless，
#      零窗口），不要再直接 & console.exe --headless。
#
# 用法（所有捕获工具统一走这里，不要再直接 & godot）：
#   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_creek.gd -UserArgs creek
#   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_art09_board.gd -UserArgs ravine -TimeoutSec 600
#   headless（导入/生成器/回归，同样零窗口、日志落文件）：
#   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Headless -Script tests/run_art09_frame_contract.gd -TimeoutSec 300
#
# 参数：
#   -Script     相对 Game/Reborn 的脚本路径（tests/xxx.gd），或完整 res:// 路径
#   -UserArgs   传给脚本的用户参数（会被拼到 `--` 之后），数组或单词
#   -QuitAfter  --quit-after 帧数上限（默认 200000 ≈ 20-30 分钟，仅作保险）
#   -TimeoutSec 外层等待上限（默认 900 秒；超时杀进程并报 TIMEOUT，日志保留）
#   -LogDir     日志目录（默认 Art/Probes/.capture_logs）
#   -NoMonitor  跳过 Win32 监视器（一般不要用；仅诊断用）
#
# 返回：Godot 退出码（超时为 124）。日志路径会打印在输出第一行。
# 监视器统计行（WINMON|summary|...）会同时打进 stdout 与 <log>.winmon.log。

param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string[]]$UserArgs = @(),
    [int]$QuitAfter = 200000,
    [int]$TimeoutSec = 900,
    # -Headless：headless 导入/生成器/回归也走本包装。GUI exe + --headless + 输出重定向
    # = 全程零窗口；**不要**为了看输出改用 console 版 exe——它会额外弹一个黑色终端窗口。
    [switch]$Headless,
    [string]$LogDir = "E:\Reborn\Art\Probes\.capture_logs",
    [string]$Godot = "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe",
    [string]$Project = "E:\Reborn\Game\Reborn",
    [switch]$NoMonitor,
    # -VisibleDesktop：诊断用——不在隐藏桌面启动（退回"屏幕外+autoload+监视器"模式，
    # 该模式实测窗口会先可见 ~1.7 秒，见文件头说明）。平时不要用。
    [switch]$VisibleDesktop,
    # T039：真机强杀注入。`-KillOnMarker "T039|phase|tmp_mid|begin"` 时，监视器读到该字符串后
    # 等 -KillGraceMs 再 TerminateProcess（退出码 -KillExitCode）。默认关闭，零副作用。
    [string]$KillOnMarker = "",
    [int]$KillGraceMs = 300,
    [int]$KillExitCode = 137
)

$ErrorActionPreference = "Stop"

if ($Headless -and $KillOnMarker -ne "") {
    Write-Host "CAPTURE_RUN|ERROR|kill_on_marker_requires_gui_monitor"
    exit 2
}

# --- 屏幕外坐标：从虚拟屏幕左上角再往左/上挪 2400 物理像素（多显示器也安全）---
Add-Type -AssemblyName System.Windows.Forms
$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
$offX = $vs.X - 2400
$offY = $vs.Y - 2400
$offPos = "{0},{1}" -f $offX, $offY

# --- 归一化脚本路径 ---
if ($Script -notlike "res://*") { $Script = "res://" + ($Script -replace '^[/\\]+', '') }

# --- 日志文件 ---
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$base = [System.IO.Path]::GetFileNameWithoutExtension(($Script -replace '^res://', ''))
$logPath = Join-Path $LogDir ("{0}_{1}.log" -f $base, $stamp)
$errPath = Join-Path $LogDir ("{0}_{1}.err.log" -f $base, $stamp)
$monPath = "$logPath.winmon.log"

# --- C# 助手（Win32 监视器 + CreateProcessW/STARTF_USEPOSITION 启动器）：必须在
#     启动子进程**之前**编译（Add-Type 要几百毫秒，放在启动后会留下"无监视空窗"，
#     那正是窗口闪现的漏洞）。headless 也走这个启动器（重定向 stdout/stderr），
#     只是不跑监视器。---
if (-not ("RebornWinMon" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class RebornWinMon {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after,
        int x, int y, int cx, int cy, uint flags);
    // Windows 默认定时器精度 ~15.6ms：不调 timeBeginPeriod(1) 的话 Thread.Sleep(2) 实际
    // 睡 ~15.6ms，轮询周期被撑到 ~20ms（2026-11-02 实测）。加上后 Sleep(2)≈2ms。
    [DllImport("winmm.dll")] public static extern uint timeBeginPeriod(uint ms);
    [DllImport("winmm.dll")] public static extern uint timeEndPeriod(uint ms);
    // --- CreateProcessW + STARTF_USEPOSITION：初始窗口位置写进启动块 ---
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcessW(IntPtr appName, IntPtr cmdLine, IntPtr procAttrs,
        IntPtr threadAttrs, bool inheritHandles, uint creationFlags, IntPtr env, string cwd,
        ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetHandleInformation(IntPtr h, uint mask, uint flags);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr sa,
        uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    // T039：读到测试脚本的 `T039|phase|...|begin` 标记后，从外部强制结束子进程（近似“进程被杀、
    // 句柄未 flush/fsync”这一层；**不能**复现真正掉电/OS 写缓存丢失/扇区损坏）。
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool TerminateProcess(IntPtr h, uint exitCode);
    // --- 隐藏桌面：让子进程的所有窗口建在我们自建的桌面上，用户桌面按定义不可见 ---
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateDesktopW(string desktop, string device, IntPtr devmode,
        uint flags, uint access, IntPtr sa);
    [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr hDesktop);
    public delegate bool DeskEnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumDesktopWindows(IntPtr hDesktop, DeskEnumProc cb, IntPtr lParam);
    // SWP_NOSIZE=0x0001 SWP_NOZORDER=0x0004 SWP_NOACTIVATE=0x0010 SWP_ASYNCWINDOWPOS=0x4000。
    // **必须带 SWP_ASYNCWINDOWPOS**：同步 SetWindowPos 要等目标窗口处理
    // WM_WINDOWPOSCHANGING/CHANGED——Godot 启动期主线程不泵消息，同步调用会阻塞
    // 监视器 1~2 秒（2026-11-02 实测：首见 648ms → 监视器卡到 2100ms 才返回，期间
    // "失明"）。异步版立即返回，挪动在目标泵消息时生效（进程内 autoload 挪得更早，
    // 这里只是兜底）。不改大小/层级/焦点。
    const uint SWP_FLAGS = 0x0001 | 0x0004 | 0x0010 | 0x4000;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int L, T, R, B; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public uint cb;
        public IntPtr lpReserved, lpDesktop, lpTitle;
        public uint dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public ushort wShowWindow, cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess, hThread;
        public uint dwProcessId, dwThreadId;
    }

    static IntPtr _hProc = IntPtr.Zero;
    static IntPtr _hDesk = IntPtr.Zero;

    // 启动子进程。desktopName 非空 = 在自建隐藏桌面（"winsta0\\<name>"）上启动，子进程
    // 的**所有**窗口只能建在那个桌面上——用户桌面按定义不可见，这是做不到 0 可见帧时
    // 的第二条路（STARTF_USEPOSITION 对 Godot 无效：它显式传坐标建窗，实测窗口仍在 (0,0)）。
    // 同时保留 STARTF_USEPOSITION（无害）与 STARTF_USESTDHANDLES（stdout/stderr 落文件）。
    public static uint StartOffscreen(string exe, string args, string outPath, string errPath,
        int x, int y, string desktopName) {
        IntPtr hOut = CreateFileW(outPath, 0x40000000u, 1u, IntPtr.Zero, 2u, 0x80u, IntPtr.Zero);
        IntPtr hErr = CreateFileW(errPath, 0x40000000u, 1u, IntPtr.Zero, 2u, 0x80u, IntPtr.Zero);
        IntPtr hIn  = CreateFileW("NUL", 0x80000000u, 3u, IntPtr.Zero, 3u, 0x80u, IntPtr.Zero);
        if (hOut == IntPtr.Zero || hErr == IntPtr.Zero || hIn == IntPtr.Zero)
            throw new Exception("CreateFileW for std handles failed: " + Marshal.GetLastWin32Error());
        SetHandleInformation(hOut, 1, 1);
        SetHandleInformation(hErr, 1, 1);
        SetHandleInformation(hIn, 1, 1);
        STARTUPINFO si = new STARTUPINFO();
        si.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFO));
        si.dwFlags = 0x00000004u /*STARTF_USEPOSITION*/ | 0x00000100u /*STARTF_USESTDHANDLES*/;
        si.dwX = unchecked((uint)x);
        si.dwY = unchecked((uint)y);
        si.hStdInput = hIn; si.hStdOutput = hOut; si.hStdError = hErr;
        IntPtr pDesk = IntPtr.Zero;
        if (!string.IsNullOrEmpty(desktopName)) {
            // GENERIC_ALL=0x10000000；创建者（本用户）拿到全部权限，子进程同用户可用
            _hDesk = CreateDesktopW(desktopName, null, IntPtr.Zero, 0, 0x10000000u, IntPtr.Zero);
            if (_hDesk == IntPtr.Zero)
                throw new Exception("CreateDesktopW failed: " + Marshal.GetLastWin32Error());
            pDesk = Marshal.StringToHGlobalUni("winsta0\\" + desktopName);
            si.lpDesktop = pDesk;
        }
        PROCESS_INFORMATION pi;
        IntPtr cmd = Marshal.StringToHGlobalUni("\"" + exe + "\" " + args);
        bool ok;
        try {
            ok = CreateProcessW(IntPtr.Zero, cmd, IntPtr.Zero, IntPtr.Zero, true, 0,
                IntPtr.Zero, null, ref si, out pi);
        } finally {
            Marshal.FreeHGlobal(cmd);
            if (pDesk != IntPtr.Zero) Marshal.FreeHGlobal(pDesk);
        }
        CloseHandle(hIn); CloseHandle(hOut); CloseHandle(hErr);
        if (!ok) throw new Exception("CreateProcessW failed: " + Marshal.GetLastWin32Error());
        CloseHandle(pi.hThread);
        _hProc = pi.hProcess;
        return pi.dwProcessId;
    }

    public static void DisposeProcHandle() {
        if (_hProc != IntPtr.Zero) { CloseHandle(_hProc); _hProc = IntPtr.Zero; }
        if (_hDesk != IntPtr.Zero) { CloseDesktop(_hDesk); _hDesk = IntPtr.Zero; }
    }

    // 等进程退出并取退出码（用启动时留下的句柄，避免 Get-Process 句柄竞态）。
    // 返回 0=已退出（exitCode 有效）；258=超时；-1=无句柄。
    public static int WaitForExitHandle(int timeoutMs, out uint exitCode) {
        exitCode = uint.MaxValue;
        if (_hProc == IntPtr.Zero) return -1;
        int r = (int)WaitForSingleObject(_hProc, (uint)timeoutMs);
        if (r == 0) GetExitCodeProcess(_hProc, out exitCode);
        return r;
    }

    static void LogLine(string logPath, string line) {
        try { File.AppendAllText(logPath, line + Environment.NewLine, Encoding.UTF8); } catch {}
    }

    // 子进程用 CreateFileW(..., share=FILE_SHARE_READ) 持有 stdout 日志；普通
    // File.ReadAllText 会以“拒绝写者”打开而失败。这里显式共享读写，只读打开。
    static string ReadShared(string path) {
        try {
            if (!File.Exists(path)) return null;
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete))
            using (var sr = new StreamReader(fs, Encoding.UTF8))
                return sr.ReadToEnd();
        } catch { return null; }
    }

    static bool Intersects(RECT r, int vsL, int vsT, int vsR, int vsB) {
        return (r.R > vsL && r.L < vsR && r.B > vsT && r.T < vsB);
    }

    // 监视 pid 的可见顶层窗口：首见即挪到 (offX, offY)，并跟踪三件事——
    //   1. 矩形变化（"引擎又把它挪回可见区"的防回弹）；
    //   2. **隐藏/重现事件**（证明"首见→挪走"之间窗口确实离屏/不可见，堵住
    //      "轮询间隙里其实还在可见区"的质疑——隐藏期窗口不在 IsWindowVisible 枚举里，
    //      若不记录会像 first_visible_to_offscreen_ms=1428 那样显得"可见了很久"）；
    //   3. visible_bound_ms：首见可见窗口的**可见时长上界** = 上一轮没见到它的时刻到
    //      本轮当场挪走，即 ≤ 一个轮询周期（≈ avg_poll_ms）。Godot 在 Windows 上窗口
    //      先以默认位置创建+show、任何定位参数都晚于它（引擎固有），无法做到 0 可见命中，
    //      只能把可见期压到轮询周期以内并如实记录毫秒数。
    // 枚举用全量 EnumWindows + pid 过滤（全系统顶层窗口 ~几百个，~1-2ms/轮）。
    // 轮询周期两个坑（2026-11-02 实测）：① Windows 默认定时器精度 ~15.6ms，
    // 不调 timeBeginPeriod(1) 时 Thread.Sleep(2) 实际睡 ~15.6ms（周期被撑到 ~20ms）；
    // ② 按线程 EnumThreadWindows 逐个调 Godot 几十个线程反而更慢。
    // visible_hits = 首见时矩形与虚拟屏幕相交的次数（如实计数，预期恒为 1，见上）。
    public static string Monitor(int pid, int offX, int offY,
        int vsL, int vsT, int vsR, int vsB, int timeoutMs, string logPath,
        string markerPath, string killMarker, int killGraceMs, uint killCode) {
        var seen = new HashSet<long>();
        var lastRect = new Dictionary<long, RECT>();
        var alive = new HashSet<long>(); // 上一轮枚举里还在的窗口
        var sw = Stopwatch.StartNew();
        Process p = null;
        try { p = Process.GetProcessById(pid); } catch (System.ArgumentException) { }
        int polls = 0, windows = 0, visibleHits = 0, moved = 0, rebounds = 0;
        int hiddenEv = 0, resights = 0, hiddenDeskWins = 0;
        long firstVisibleT = -1, offscreenConfirmT = -1, visibleBoundMs = -1;
        bool exited = (p == null);
        bool killed = false;
        long killAtMs = -1;
        long lastMarkerCheck = 0;
        long prevPollEnd = 0;
        timeBeginPeriod(1);
        while (!exited && sw.ElapsedMilliseconds < timeoutMs) {
            polls++;
            // T039：外部强杀窗口。测试脚本在保存阶段打印 begin 标记后阻塞；这里读到标记，
            // 等 grace 让日志落盘，再 TerminateProcess。仅在显式传 -KillOnMarker 时启用。
            if (!killed && killMarker != "" && sw.ElapsedMilliseconds - lastMarkerCheck >= 20) {
                lastMarkerCheck = sw.ElapsedMilliseconds;
                try {
                    string txt = ReadShared(markerPath);
                    if (txt != null && txt.Contains(killMarker)) {
                        killed = true;
                        killAtMs = sw.ElapsedMilliseconds;
                        LogLine(logPath, string.Format(
                            "WINMON|t={0}ms|kill_marker_seen|marker={1}", killAtMs, killMarker));
                        if (killGraceMs > 0) Thread.Sleep(killGraceMs);
                        TerminateProcess(_hProc, killCode);
                        LogLine(logPath, string.Format(
                            "WINMON|t={0}ms|terminated|code={1}", sw.ElapsedMilliseconds, killCode));
                    }
                } catch { }
            }
            IntPtr[] found = new IntPtr[64];
            int n = 0;
            EnumWindows(delegate(IntPtr h, IntPtr lp) {
                uint wpid;
                GetWindowThreadProcessId(h, out wpid);
                if (wpid == (uint)pid && IsWindowVisible(h) && n < 64) found[n++] = h;
                return true;
            }, IntPtr.Zero);
            // 隐藏桌面上的本进程窗口：只记录矩形（按定义用户不可见，不计 visible_hits、
            // 不挪动）。键加 0x100000000 偏移避免与用户桌面 hwnd 键冲突。
            if (_hDesk != IntPtr.Zero) {
                IntPtr[] hFound = new IntPtr[16];
                int hn = 0;
                EnumDesktopWindows(_hDesk, delegate(IntPtr h, IntPtr lp) {
                    uint wpid;
                    GetWindowThreadProcessId(h, out wpid);
                    if (wpid == (uint)pid && hn < 16) hFound[hn++] = h;
                    return true;
                }, IntPtr.Zero);
                for (int i = 0; i < hn; i++) {
                    long hkey = ((long)0x100000000) + hFound[i].ToInt64();
                    RECT hr;
                    if (!GetWindowRect(hFound[i], out hr)) continue;
                    if (!seen.Contains(hkey)) {
                        seen.Add(hkey);
                        hiddenDeskWins++;
                        LogLine(logPath, string.Format(
                            "WINMON|t={0}ms|hidden_desk_first_sight|hwnd=0x{1:X}|rect=({2},{3},{4},{5})",
                            sw.ElapsedMilliseconds, hFound[i].ToInt64(), hr.L, hr.T, hr.R, hr.B));
                        lastRect[hkey] = hr;
                    } else {
                        RECT hprev;
                        if (lastRect.TryGetValue(hkey, out hprev) &&
                            (hprev.L != hr.L || hprev.T != hr.T || hprev.R != hr.R || hprev.B != hr.B)) {
                            lastRect[hkey] = hr;
                            LogLine(logPath, string.Format(
                                "WINMON|t={0}ms|hidden_desk_rect|hwnd=0x{1:X}|rect=({2},{3},{4},{5})",
                                sw.ElapsedMilliseconds, hFound[i].ToInt64(), hr.L, hr.T, hr.R, hr.B));
                        }
                    }
                }
            }
            var nowFound = new HashSet<long>();
            var seenAtPollStart = new HashSet<long>(seen); // 本轮开始前已见过的（防首见轮误记 resight）
            for (int i = 0; i < n; i++) {
                IntPtr h = found[i];
                long key = h.ToInt64();
                nowFound.Add(key);
                RECT r;
                GetWindowRect(h, out r);
                if (!seen.Contains(key)) {
                    seen.Add(key);
                    windows++;
                    bool vis = Intersects(r, vsL, vsT, vsR, vsB);
                    if (vis) visibleHits++;
                    LogLine(logPath, string.Format(
                        "WINMON|t={0}ms|first_sight|hwnd=0x{1:X}|rect=({2},{3},{4},{5})|visible_hit={6}",
                        sw.ElapsedMilliseconds, key, r.L, r.T, r.R, r.B, vis ? "YES" : "no"));
                    if (vis) {
                        // 可见时长上界：上一轮（prevPollEnd 时）还没见到它 → 它是
                        // (prevPollEnd, now] 之间才出现的，本轮当场挪走。
                        if (visibleBoundMs < 0) visibleBoundMs = sw.ElapsedMilliseconds - prevPollEnd;
                        firstVisibleT = sw.ElapsedMilliseconds;
                        SetWindowPos(h, IntPtr.Zero, offX, offY, 0, 0, SWP_FLAGS);
                        moved++;
                    }
                    lastRect[key] = r;
                } else {
                    RECT prev;
                    bool had = lastRect.TryGetValue(key, out prev);
                    // 矩形变化才记（防刷屏）：重点是"仍/又在可见区"的防回弹
                    if (!had || prev.L != r.L || prev.T != r.T || prev.R != r.R || prev.B != r.B) {
                        lastRect[key] = r;
                        bool visNow = Intersects(r, vsL, vsT, vsR, vsB);
                        if (visNow) {
                            // 引擎（或别的什么）又把它挪回可见区 → 再挪出去
                            SetWindowPos(h, IntPtr.Zero, offX, offY, 0, 0, SWP_FLAGS);
                            moved++;
                            rebounds++;
                            LogLine(logPath, string.Format(
                                "WINMON|t={0}ms|rebound|hwnd=0x{1:X}|rect=({2},{3},{4},{5})|moved_offscreen_again",
                                sw.ElapsedMilliseconds, key, r.L, r.T, r.R, r.B));
                        } else if (had && Intersects(prev, vsL, vsT, vsR, vsB) && offscreenConfirmT < 0) {
                            offscreenConfirmT = sw.ElapsedMilliseconds;
                            LogLine(logPath, string.Format(
                                "WINMON|t={0}ms|confirmed_offscreen|hwnd=0x{1:X}|rect=({2},{3},{4},{5})",
                                sw.ElapsedMilliseconds, key, r.L, r.T, r.R, r.B));
                        }
                    }
                }
            }
            // 隐藏 / 重现（进程还活着但窗口不在可见枚举里 = 被引擎隐藏，不是销毁）
            foreach (long key in alive) {
                if (!nowFound.Contains(key)) {
                    hiddenEv++;
                    LogLine(logPath, string.Format(
                        "WINMON|t={0}ms|hidden|hwnd=0x{1:X}|note=left_visible_enum_while_proc_alive",
                        sw.ElapsedMilliseconds, key));
                }
            }
            foreach (long key in nowFound) {
                if (seenAtPollStart.Contains(key) && !alive.Contains(key)) {
                    resights++;
                    RECT r2;
                    IntPtr h2 = new IntPtr(key);
                    if (GetWindowRect(h2, out r2)) {
                        LogLine(logPath, string.Format(
                            "WINMON|t={0}ms|resighted|hwnd=0x{1:X}|rect=({2},{3},{4},{5})|visible_hit={6}",
                            sw.ElapsedMilliseconds, key, r2.L, r2.T, r2.R, r2.B,
                            Intersects(r2, vsL, vsT, vsR, vsB) ? "YES" : "no"));
                    }
                }
            }
            alive = nowFound;
            try { exited = p.HasExited; } catch { exited = true; }
            prevPollEnd = sw.ElapsedMilliseconds;
            if (!exited) Thread.Sleep(2);
        }
        timeEndPeriod(1);
        string dur = (firstVisibleT >= 0 && offscreenConfirmT >= 0)
            ? (offscreenConfirmT - firstVisibleT).ToString() : "-1";
        string sum = string.Format(
            "WINMON|summary|elapsed={0}ms|polls={1}|avg_poll_ms={2:F1}|windows_seen={3}|visible_hits={4}|moved_offscreen={5}|rebounds={6}|visible_bound_ms={7}|first_visible_to_offscreen_ms={8}|hidden_events={9}|resights={10}|hidden_desk_windows={11}|proc_exited={12}|killed={13}|kill_at_ms={14}",
            sw.ElapsedMilliseconds, polls, polls > 0 ? (double)sw.ElapsedMilliseconds / polls : 0,
            windows, visibleHits, moved, rebounds,
            visibleBoundMs.ToString(), dur, hiddenEv, resights, hiddenDeskWins, exited,
            killed ? 1 : 0, killAtMs);
        LogLine(logPath, sum);
        return sum;
    }
}
"@
}

# --- 组装参数 ---
$argList = @(
    "--path", $Project
)
if ($Headless) {
    $argList += "--headless"
} else {
    # 只有非 headless 才需要把渲染窗口挪到屏幕外（软参数 + autoload 硬保证 + 监视器兜底）
    $argList += "--position"
    $argList += $offPos
}
$argList += @(
    "--script", $Script,
    "--quit-after", "$QuitAfter"
)
if ($UserArgs.Count -gt 0) {
    $argList += "--"
    $argList += $UserArgs
}

Write-Host "CAPTURE_RUN|log=$logPath"
Write-Host "CAPTURE_RUN|script=$Script|user_args=[$($UserArgs -join ' ')]|window_offscreen=$offPos|kill_on_marker=$KillOnMarker"

# --- 引擎侧硬保证的开关：autoload capture_window_guard.gd 只在这个环境变量为 1 时
#     才把窗口挪屏幕外（正常游玩不设这个变量，零副作用）---
if (-not $Headless) {
    $env:REBORN_CAPTURE_OFFSCREEN = "1"
}

# 注意：**不要**用 -WindowStyle Hidden / 最小化 —— 隐藏窗口可能停止渲染拿到黑帧。
# 启动方式：CreateProcessW，非 headless 默认在**自建隐藏桌面**（winsta0\RebornCapture）上
# 启动——子进程的所有窗口只能建在那个桌面上，用户桌面按定义不可见（0 可见帧）。
# 为什么必须这样做：实测 Godot 在 Windows 上主窗口显式建在 (0,0)（不用 CW_USEDEFAULT，
# STARTF_USEPOSITION 无效），且启动期主线程 ~2 秒不泵消息——--position / project 设置 /
# autoload / 外部 SetWindowPos 全部要等引擎泵消息后才生效，窗口会先可见 ~1.8 秒
# （winmon 证据见 <log>.winmon.log 与 ART07 证据 §9.4）。
# stdout/stderr 由 STARTF_USESTDHANDLES 重定向进文件，等价于原 Start-Process 的重定向。
$desktopName = $null
if (-not $Headless -and -not $VisibleDesktop) { $desktopName = "RebornCapture" }
$argStr = ($argList | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
$childPid = [int][RebornWinMon]::StartOffscreen($Godot, $argStr, $logPath, $errPath, $offX, $offY, $desktopName)
Write-Host "CAPTURE_RUN|child_pid=$childPid|startup_position=$offPos|desktop=$desktopName"

# --- 命令行取证：异步查 Win32_Process（Get-CimInstance 要几十毫秒，不能挡在监视器前面）---
$cmdRun = [System.Management.Automation.PowerShell]::Create()
$null = $cmdRun.AddScript("Get-CimInstance Win32_Process -Filter 'ProcessId=$childPid' | Select-Object -ExpandProperty CommandLine")
$cmdAsync = $cmdRun.BeginInvoke()

# --- Win32 监视器（首见即挪屏外，全程记录；STARTF_USEPOSITION 生效时应为 visible_hits=0）---
$monitorSummary = "WINMON|skipped|headless_or_disabled"
if (-not $Headless -and -not $NoMonitor) {
    $monitorSummary = [RebornWinMon]::Monitor($childPid, $offX, $offY,
        $vs.X, $vs.Y, ($vs.X + $vs.Width), ($vs.Y + $vs.Height), ($TimeoutSec * 1000), $monPath,
        $logPath, $KillOnMarker, $KillGraceMs, [uint32]$KillExitCode)
} else {
    Write-Host "CAPTURE_RUN|$monitorSummary"
}

# --- 收命令行结果（验证 --position / 环境开关确实到达进程）---
try {
    $cmdLine = $cmdRun.EndInvoke($cmdAsync)
    if ($cmdLine) {
        Write-Host "CAPTURE_RUN|pid=$childPid|cmdline=$cmdLine"
        Add-Content -Path $monPath -Value "CAPTURE_RUN|pid=$childPid|cmdline=$cmdLine" -Encoding UTF8
    }
} catch {
    Write-Host "CAPTURE_RUN|pid=$childPid|cmdline_query_failed=$($_.Exception.Message)"
}

if (-not $Headless) {
    Write-Host "CAPTURE_RUN|$monitorSummary"
    Write-Host "CAPTURE_RUN|winmon_log=$monPath"
    Remove-Item Env:\REBORN_CAPTURE_OFFSCREEN -ErrorAction SilentlyContinue
}

# --- 等待退出并取退出码（用启动时留下的进程句柄；监视器正常情况下已等到退出）---
$exitCode = [uint32]0
$waitR = [RebornWinMon]::WaitForExitHandle(5000, [ref]$exitCode)
if ($waitR -eq 258) {
    # 监视器超时/被跳过时进程可能还活着：再给满超时，仍不死才杀
    $waitR = [RebornWinMon]::WaitForExitHandle($TimeoutSec * 1000, [ref]$exitCode)
}
if ($waitR -ne 0) {
    [RebornWinMon]::DisposeProcHandle()
    try { Stop-Process -Id $childPid -Force -ErrorAction SilentlyContinue } catch {}
    Write-Host "CAPTURE_RUN|TIMEOUT|${TimeoutSec}s|log=$logPath"
    Write-Host "CAPTURE_RUN|tail:"
    if (Test-Path $logPath) { Get-Content $logPath -Tail 12 }
    exit 124
}
[RebornWinMon]::DisposeProcHandle()

$code = [int]$exitCode
if ($null -eq $code) { $code = 0 }
Write-Host "CAPTURE_RUN|exit=$code|log=$logPath"
Write-Host "CAPTURE_RUN|tail:"
if (Test-Path $logPath) { Get-Content $logPath -Tail 12 }
exit $code
