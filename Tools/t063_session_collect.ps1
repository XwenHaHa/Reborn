# T063：试玩会话回收（**只读**，不修改任何文件）——把"是不是技术问题"变成可核对的数字。
#
# 用法（在试玩者机器上执行）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\t063_session_collect.ps1 `
#       -Tester "P1" -Out "E:\Reborn\Tools\Probes\t063_P1.log"
#
# 输出（每行一条，便于汇总）：
#   SESSION|tester=..|save=..|lives=..|unlocked=..|world_time=..|revision=..|pending=..|quarantine=..|script_errors=..
#   SETTINGS|volume=..|shake=..|subtitles=..|hints_seen=..
#   PROBLEM|...      —— 发现的技术异常（会让"体验问题"和"技术缺陷"分开记账）
#   LOGTAIL|...      —— godot.log 末尾几行（便于看崩溃/报错上下文）
#
# 只读保证：本脚本只调用 Get-Content / Get-ChildItem / ConvertFrom-Json，**不写 user:// 目录**。
param(
    [string]$Tester = "P1",
    [string]$UserData = "$env:APPDATA\Godot\app_userdata\Reborn",
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"
$lines = New-Object System.Collections.Generic.List[string]
function Emit([string]$s) { $lines.Add($s); Write-Host $s }

Emit ("COLLECT|tester={0}|userdata={1}" -f $Tester, $UserData)
if (-not (Test-Path $UserData)) {
    Emit "PROBLEM|userdata_missing|试玩者没跑过游戏，或 APPDATA 路径不同"
    Emit "SESSION|tester=$Tester|save=false|lives=0|unlocked=|world_time=0|revision=0|pending=|quarantine=0|script_errors=0"
    if ($Out -ne "") { $lines | Set-Content -Path $Out -Encoding UTF8 }
    exit 0
}

# ---------- 1) 存档 ----------
$save = Join-Path $UserData "savegame_v1.json"
$saveOk = Test-Path $save
$lives = 0; $unlocked = ""; $worldTime = 0.0; $revision = 0; $pending = ""; $version = -1
if ($saveOk) {
    try {
        $j = Get-Content $save -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $j.life_records) { $lives = @($j.life_records).Count }
        if ($null -ne $j.unlocked_species) { $unlocked = (@($j.unlocked_species) -join ",") }
        if ($null -ne $j.world_time) { $worldTime = [double]$j.world_time }
        if ($null -ne $j.revision) { $revision = [int]$j.revision }
        if ($null -ne $j.pending_settlement_life_id) { $pending = [string]$j.pending_settlement_life_id }
        if ($null -ne $j.save_version) { $version = [int]$j.save_version }
        if ($version -ne 1) { Emit ("PROBLEM|save_version|期望 1，实际 {0}" -f $version) }
    } catch {
        Emit "PROBLEM|save_unparsable|存档 JSON 解析失败（可能是损坏档，应已被隔离）"
    }
} else {
    Emit "PROBLEM|save_missing|没有存档：要么没玩到存盘点，要么退出时没写盘"
}

# ---------- 2) 隔离文件（损坏档）----------
$quarantine = @(Get-ChildItem $UserData -Filter "*.corrupt-*" -ErrorAction SilentlyContinue)
if ($quarantine.Count -gt 0) {
    Emit ("PROBLEM|quarantine|隔离了 {0} 个损坏档：{1}" -f $quarantine.Count,
        (($quarantine | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ";"))
}

# ---------- 3) 设置 ----------
$settingsPath = Join-Path $UserData "settings.cfg"
$vol = "?"; $shake = "?"; $subs = "?"; $hints = "?"
if (Test-Path $settingsPath) {
    $cfg = Get-Content $settingsPath -Encoding UTF8
    foreach ($k in @("volume", "camera_shake", "subtitles", "hints_seen")) {
        $m = $cfg | Select-String -Pattern ("^{0}\s*=\s*(.+)$" -f $k) | Select-Object -First 1
        if ($m) {
            $val = $m.Matches[0].Groups[1].Value.Trim()
            switch ($k) {
                "volume" { $vol = $val }
                "camera_shake" { $shake = $val }
                "subtitles" { $subs = $val }
                "hints_seen" { $hints = $val }
            }
        }
    }
} else {
    Emit "PROBLEM|settings_missing|没有 settings.cfg（试玩者没改过设置 → 正常，但记为观察点）"
}
Emit ("SETTINGS|volume={0}|shake={1}|subtitles={2}|hints_seen={3}" -f $vol, $shake, $subs, $hints)

# ---------- 4) 日志 ----------
$logDir = Join-Path $UserData "logs"
$scriptErrors = 0
if (Test-Path $logDir) {
    foreach ($f in Get-ChildItem $logDir -Filter "*.log" -ErrorAction SilentlyContinue) {
        $hits = @(Select-String -Path $f.FullName -Pattern "SCRIPT ERROR" -ErrorAction SilentlyContinue)
        $scriptErrors += $hits.Count
        if ($hits.Count -gt 0) {
            Emit ("PROBLEM|script_error|{0} 里有 {1} 条 SCRIPT ERROR" -f $f.Name, $hits.Count)
        }
    }
    $latest = Get-ChildItem $logDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        $tail = Get-Content $latest.FullName -Encoding UTF8 -Tail 6
        foreach ($t in $tail) { Emit ("LOGTAIL|{0}" -f $t) }
    }
} else {
    Emit "PROBLEM|logs_missing|没有 logs 目录（可能是首次启动就异常退出）"
}

# ---------- 5) 汇总 ----------
Emit ("SESSION|tester={0}|save={1}|lives={2}|unlocked={3}|world_time={4:F1}|revision={5}|pending={6}|quarantine={7}|script_errors={8}" -f
    $Tester, $saveOk.ToString().ToLower(), $lives, $unlocked, $worldTime, $revision, $pending, $quarantine.Count, $scriptErrors)

if ($Out -ne "") {
    $dir = Split-Path $Out -Parent
    if ($dir -ne "" -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $lines | Set-Content -Path $Out -Encoding UTF8
    Write-Host ("COLLECT|written={0}" -f $Out)
}
exit 0
