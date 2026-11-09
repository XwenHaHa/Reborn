# T043 包内断言：用 GUI 版 Godot 编辑器二进制 + --headless --main-pack 读取导出的
# SelfTest pck（历史约定见 Docs/Evidence/T007.md：导出 exe 会忽略 --script，必须走
# 编辑器二进制 + --main-pack）。全过程经 Tools\NoWindow.vbs / ZeroWindowRun.ps1 启动，
# 输出重定向到文件，不产生控制台或游戏窗口。
# 产物：Builds/P0-Win64/_assert_*.log（构建目录，不入 git）。
$ErrorActionPreference = 'Stop'

$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'
$pck = 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck'
$out = 'E:\Reborn\Builds\P0-Win64'
if (-not (Test-Path $pck)) { Write-Host 'ASSERT|FAIL|missing_pck'; exit 1 }

function Invoke-PckScript([string]$script, [string]$tag) {
    $o = Join-Path $out ("_assert_{0}.out.log" -f $tag)
    $e = Join-Path $out ("_assert_{0}.err.log" -f $tag)
    $p = Start-Process -FilePath $godot `
        -ArgumentList @('--headless', '--main-pack', $pck, '--script', $script, '--quit-after', '300000') `
        -RedirectStandardOutput $o -RedirectStandardError $e -Wait -PassThru
    return @{
        Code = $p.ExitCode
        Out = @(Get-Content -LiteralPath $o -ErrorAction SilentlyContinue)
        Err = @(Get-Content -LiteralPath $e -ErrorAction SilentlyContinue)
    }
}

# 1) 探针：证明包能被载入，并打印脱敏的 user:// 路径形态
$probe = Invoke-PckScript 'res://tests/tool_t043_package_probe.gd' 'probe'
$probeLines = @($probe.Out | Where-Object { $_ -match 'PROBE\|' })
$probeLines | ForEach-Object { Write-Host $_ }
$probe.Err | Where-Object { $_ -ne '' } | ForEach-Object { Write-Host "ASSERT|STDERR|$_" }
$probeOk = ($probe.Code -eq 0 -and $probeLines.Count -ge 2)

# 2) 包内跑 T043 存档矩阵：证明包内运行时依赖完整
$suite = Invoke-PckScript 'res://tests/run_t043_save_matrix.gd' 'suite'
$suiteLine = ($suite.Out | Select-String -Pattern 'RESULT\|.*' | Select-Object -First 1).Line
$suite.Err | Where-Object { $_ -ne '' } | ForEach-Object { Write-Host "ASSERT|STDERR|$_" }
Write-Host "ASSERT|suite|exit=$($suite.Code)|$suiteLine"
$suiteOk = ($suite.Code -eq 0 -and $suiteLine -match 'pass=60\|fail=0')

# 3) 发行 exe 自启动（headless，无窗口）：确认包能跑主循环，并刷新 user:// 的 logs 目录
# 导出模板会忽略 --script（见 Docs/Evidence/T007.md），发行 exe 只做启动冒烟：
$release = Join-Path $out 'Reborn.exe'
$relLog = Join-Path $out '_assert_release.out.log'
$relErr = Join-Path $out '_assert_release.err.log'
$relProc = Start-Process -FilePath $release `
    -ArgumentList @('--headless', '--verbose', '--quit-after', '200') `
    -RedirectStandardOutput $relLog -RedirectStandardError $relErr -Wait -PassThru
$relLines = @(Get-Content -LiteralPath $relLog -ErrorAction SilentlyContinue)
$relErrLines = @(Get-Content -LiteralPath $relErr -ErrorAction SilentlyContinue)
$relErrLines | Where-Object { $_ -ne '' } | ForEach-Object { Write-Host "ASSERT|STDERR|$_" }
$relOk = ($relProc.ExitCode -eq 0 -and ($relLines | Select-String -Pattern 'ENTRY\|settings_loaded' | Measure-Object).Count -ge 1)
Write-Host ("ASSERT|release|exit={0}|entries={1}" -f $relProc.ExitCode, $relLines.Count)

Write-Host ("ASSERT|probe={0}|suite={1}|release={2}" -f $probeOk, $suiteOk, $relOk)
if (-not ($probeOk -and $suiteOk -and $relOk)) { exit 1 }
exit 0
