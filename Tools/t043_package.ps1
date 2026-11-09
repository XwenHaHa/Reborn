# T043 打包与发行包审计（可重复运行）
# 用法：powershell -ExecutionPolicy Bypass -File E:\Reborn\Tools\t043_package.ps1
# 产物：Builds/P0-Win64/{Reborn.exe,Reborn.pck,RebornSelfTest.exe,RebornSelfTest.pck,THIRD_PARTY_NOTICES.md}
# 注意：二进制不入 git；本脚本只读工程，写构建目录。
$ErrorActionPreference = "Stop"

$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'
$proj = 'E:\Reborn\Game\Reborn'
$out = 'E:\Reborn\Builds\P0-Win64'
$notice = Join-Path $out 'THIRD_PARTY_NOTICES.md'

if (-not (Test-Path $out)) { New-Item -ItemType Directory -Force -Path $out | Out-Null }

# 1) 清理旧的发行控制台包装，确保“发行版只有 GUI exe”是本次导出的真实结果
$staleConsole = Join-Path $out 'Reborn.console.exe'
if (Test-Path $staleConsole) { Remove-Item $staleConsole -Force }

# 2) 两预设导出
& $godot --headless --path $proj --export-release 'Windows Desktop' (Join-Path $out 'Reborn.exe') 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "PACK|FAIL|release_export=$LASTEXITCODE"; exit 1 }
& $godot --headless --path $proj --export-debug 'Windows Desktop SelfTest' (Join-Path $out 'RebornSelfTest.exe') 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "PACK|FAIL|selftest_export=$LASTEXITCODE"; exit 1 }

# 3) 发行包不得带控制台包装
if (Test-Path $staleConsole) { Write-Host "PACK|FAIL|release_console_wrapper_present"; exit 1 }

# 4) 文件大小与 SHA256
$files = @('Reborn.exe', 'Reborn.pck', 'RebornSelfTest.exe', 'RebornSelfTest.pck')
foreach ($f in $files) {
    $p = Join-Path $out $f
    if (-not (Test-Path $p)) { Write-Host "PACK|FAIL|missing=$f"; exit 1 }
    $item = Get-Item $p
    $hash = (Get-FileHash -Algorithm SHA256 $p).Hash.ToLower()
    Write-Host ("PACK|file={0}|bytes={1}|sha256={2}" -f $f, $item.Length, $hash)
}

# 5) PCK 泄露审计（发行包）
$audit = @(
    'E:\Reborn\Tools\t043_pck_audit.py',
    (Join-Path $out 'Reborn.pck'),
    '--deny', 'tests/', '--deny', 'references/', '--deny', 'Docs/', '--deny', '.uid',
    '--deny', 'tool_capture_', '--deny', 'tool_make_', '--deny', 'run_t0'
)
python @audit
if ($LASTEXITCODE -ne 0) { Write-Host "PACK|FAIL|pck_leak"; exit 1 }

# 6) 随包许可清单：只列已入库、会进入包内的第三方资产
$rows = @(
    @{ path='assets/characters/mouse/sm_mouse_002.glb'; name='SM_Mouse_002'; author='Mehrus'; license='CC-BY 4.0'; url='https://sketchfab.com/3d-models/none-978e06562faa4c95b842d451ed23338c' },
    @{ path='assets/environment/sm_fence_module_001.glb'; name='SM_Fence_Module_001'; author='Stefan (stefan_wr)'; license='CC-BY 4.0'; url='https://sketchfab.com/models/0788f8b362a6463fa08ad75273c530ea' },
    @{ path='assets/environment/sm_root_hole_001.glb'; name='SM_RootHole_001'; author='Callum (callum_arb)'; license='CC-BY 4.0'; url='https://sketchfab.com/models/bb383af9741d4dd48dbccde3b7bf8b1e' },
    @{ path='assets/environment/sm_boulder_001.glb'; name='SM_Boulder_001'; author='Poly Haven (Rico Cilliers)'; license='CC0 1.0'; url='https://polyhaven.com/a/boulder_01' },
    @{ path='assets/environment/hdri/mossy_forest_2k.hdr'; name='mossy_forest_2k.hdr'; author='Greg Zaal / Poly Haven'; license='CC0 1.0'; url='https://polyhaven.com/a/mossy_forest' }
)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# THIRD_PARTY NOTICES — 轮生 Reborn')
$lines.Add('')
$lines.Add('本清单随 Windows 发行包分发，覆盖所有进入包内的第三方资产。')
$lines.Add('`references/`、`Docs/`、`tests/` 与内部取证脚本不在发行包内。')
$lines.Add('')
$lines.Add('## 已入库游戏资产')
$lines.Add('')
$lines.Add('| 资产 | 作者 | 许可 | 来源 | SHA256 |')
$lines.Add('|---|---|---|---|---|')
foreach ($r in $rows) {
    $p = Join-Path $proj $r.path
    if (Test-Path $p) {
        $hash = (Get-FileHash -Algorithm SHA256 $p).Hash.ToLower()
        $lines.Add(('| {0} | {1} | {2} | {3} | `{4}` |' -f $r.name, $r.author, $r.license, $r.url, $hash))
    } else {
        $lines.Add(('| {0} | {1} | {2} | {3} | `MISSING` |' -f $r.name, $r.author, $r.license, $r.url))
    }
}
$lines.Add('')
$lines.Add('## Poly Haven 1K 贴图（CC0 1.0）')
$lines.Add('')
$lines.Add('| 文件 | SHA256 |')
$lines.Add('|---|---|')
Get-ChildItem (Join-Path $proj 'assets/environment/tex') -Filter '*.jpg' | Sort-Object Name | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower()
    $lines.Add(('| {0} | `{1}` |' -f $_.Name, $hash))
}
$lines.Add('')
$lines.Add('CC-BY 资产分发时必须保留作者与来源；CC0 资产无强制署名义务，此处自愿登记。')
$lines.Add('完整登记与选型过程见仓库 `Docs/THIRD_PARTY_ASSETS.md`（不随包）。')
Set-Content -Path $notice -Value ($lines -join "`r`n") -Encoding UTF8
Write-Host "PACK|notice=$notice"

Write-Host "PACK|OK|release=Reborn.exe|selftest=RebornSelfTest.exe"
