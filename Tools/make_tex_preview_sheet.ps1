# 下载 6 个苔藓向候选的 diffuse 1k，拼带标签对比板（短名单筛选）
$ErrorActionPreference = "Stop"
$ids = @("forest_ground_04","forest_ground_05","forest_ground_06","leaves_forest_ground","leafy_grass","mud_forest")
$base = "E:\Reborn\references\_downloads"

foreach ($id in $ids) {
    $dir = Join-Path $base $id
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $api = Invoke-RestMethod -Uri "https://api.polyhaven.com/files/$id"
    $info = $api.Diffuse."1k".jpg
    $dest = Join-Path $dir (Split-Path $info.url -Leaf)
    if (-not (Test-Path $dest)) { Invoke-WebRequest -Uri $info.url -OutFile $dest }
    $bytes = (Get-Item $dest).Length
    $md5 = (Get-FileHash $dest -Algorithm MD5).Hash.ToLower()
    $sha256 = (Get-FileHash $dest -Algorithm SHA256).Hash
    $ok = ($bytes -eq $info.size) -and ($md5 -eq $info.md5)
    Write-Output ("TEXDL2|{0}|diffuse|bytes={1}|md5_ok={2}|sha256={3}" -f $id, $bytes, $ok, $sha256)
}

# --- 拼板（左 2 列 = 三个 forest_leaves 已判候选的 diff，右 2 列 = 6 个新候选）---
Add-Type -AssemblyName System.Drawing
$cell = 256
$sheetIds = @("forest_leaves_02","forest_leaves_03","forest_leaves_04","forest_ground_04","forest_ground_05","forest_ground_06","leaves_forest_ground","leafy_grass","mud_forest")
$cols = 3
$rows = [Math]::Ceiling($sheetIds.Count / $cols)
$sheet = New-Object System.Drawing.Bitmap ($cell * $cols), ($cell * $rows)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::Black)
$font = New-Object System.Drawing.Font "Arial", 11, ([System.Drawing.FontStyle]::Bold)
$brush = [System.Drawing.Brushes]::Yellow

$i = 0
foreach ($id in $sheetIds) {
    $file = Get-ChildItem (Join-Path $base $id) -Filter "*diff*1k.jpg" | Select-Object -First 1
    if (-not $file) { Write-Output "SHEET|$id|missing"; $i++; continue }
    $img = [System.Drawing.Image]::FromFile($file.FullName)
    $x = ($i % $cols) * $cell
    $y = [Math]::Floor($i / $cols) * $cell
    $side = [Math]::Min($img.Width, $img.Height)
    $sx = [Math]::Floor(($img.Width - $side) / 2)
    $sy = [Math]::Floor(($img.Height - $side) / 2)
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle ($x + 4), ($y + 4), ($cell - 8), ($cell - 28)),
        (New-Object System.Drawing.Rectangle $sx, $sy, $side, $side), [System.Drawing.GraphicsUnit]::Pixel)
    $g.DrawString($id, $font, $brush, ($x + 6), ($y + $cell - 24))
    $img.Dispose()
    $i++
}
$g.Dispose()
$outPath = "E:\Reborn\Art\Probes\ground_tex_compare\preview_sheet.png"
$sheet.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
Write-Output "SHEET|saved=$outPath"
