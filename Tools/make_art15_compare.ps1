param(
    [Parameter(Mandatory=$true)][string]$Before,
    [Parameter(Mandatory=$true)][string]$After,
    [Parameter(Mandatory=$true)][string]$Out,
    [string]$Gap = "12px",
    [int]$CellW = 800,
    [int]$CellH = 450
)
Add-Type -AssemblyName System.Drawing
$gap = [int]($Gap -replace 'px','')
$b = [System.Drawing.Image]::FromFile((Resolve-Path $Before))
$a = [System.Drawing.Image]::FromFile((Resolve-Path $After))
$w = $CellW * 2 + $gap
$canvas = New-Object System.Drawing.Bitmap($w, $CellH)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.Clear([System.Drawing.Color]::FromArgb(24, 24, 24))
$g.DrawImage($b, 0, 0, $CellW, $CellH)
$g.DrawImage($a, ($CellW + $gap), 0, $CellW, $CellH)
$dir = Split-Path -Parent $Out
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$canvas.Save((Join-Path (Resolve-Path $dir) (Split-Path -Leaf $Out)), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $canvas.Dispose(); $b.Dispose(); $a.Dispose()
Write-Output "COMPARE|out=$Out|cell=${CellW}x${CellH}"
