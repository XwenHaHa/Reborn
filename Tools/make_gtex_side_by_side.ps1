# 拼 2x2 并排对比：行=ground近景/scene整体，列=forest_leaves_02/leafy_grass
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$dir = "E:\Reborn\Art\Probes\ground_tex_compare"
$cells = @(
    @{x=0; y=0; file="gtex_ground_fl02.png"},
    @{x=1; y=0; file="gtex_ground_lgrass.png"},
    @{x=0; y=1; file="gtex_scene_fl02.png"},
    @{x=1; y=1; file="gtex_scene_lgrass.png"}
)
$w = 640; $h = 360; $label = 24
$sheet = New-Object System.Drawing.Bitmap ($w * 2), (($h + $label) * 2)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::Black)
$font = New-Object System.Drawing.Font "Arial", 16, ([System.Drawing.FontStyle]::Bold)
$brush = [System.Drawing.Brushes]::Yellow
foreach ($c in $cells) {
    $img = [System.Drawing.Image]::FromFile((Join-Path $dir $c.file))
    $px = $c.x * $w
    $py = $c.y * ($h + $label)
    $g.DrawImage($img, $px, ($py + $label), $w, $h)
    $g.DrawString($c.file, $font, $brush, ($px + 8), ($py + 4))
    $img.Dispose()
}
$g.Dispose()
$out = Join-Path $dir "gtex_side_by_side.png"
$sheet.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
Write-Output "SBS|saved=$out"
