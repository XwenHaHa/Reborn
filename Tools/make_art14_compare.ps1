# ART14：相邻状态对比板（左=改前，右=改后），缩到 640x640 再拼，避免 vision 服务 8MB 上限。
#
# 用法：
#   powershell -File E:\Reborn\Tools\make_art14_compare.ps1 -Before <png> -After <png> -Out <png>
param(
    [Parameter(Mandatory = $true)][string]$Before,
    [Parameter(Mandatory = $true)][string]$After,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Gap = "16px",
    [int]$Cell = 640
)

Add-Type -AssemblyName System.Drawing

function Load-Cell([string]$path, [int]$cell) {
    $img = [System.Drawing.Image]::FromFile($path)
    $bmp = New-Object System.Drawing.Bitmap($cell, $cell)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($img, 0, 0, $cell, $cell)
    $g.Dispose()
    $img.Dispose()
    return $bmp
}

$left = Load-Cell $Before $Cell
$right = Load-Cell $After $Cell

$canvas = New-Object System.Drawing.Bitmap(($Cell * 2), $Cell)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.Clear([System.Drawing.Color]::FromArgb(24, 24, 26))
$g.DrawImage($left, 0, 0)
$g.DrawImage($right, $Cell, 0)
$g.Dispose()
$left.Dispose()
$right.Dispose()

$dir = [System.IO.Path]::GetDirectoryName($Out)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$canvas.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$canvas.Dispose()
Write-Output ("ART14_COMPARE|before={0}|after={1}|out={2}" -f $Before, $After, $Out)
