# ART12：把改前/改后帧水平拼成对比图（左=改前，右=改后），供 vision 判读。
# 改前基线：Art/Probes/art07_after/（庭院，15:17）与 art11_ground_after/（展板关，16:08），
# 均为 HEAD 提交状态的原帧。输出 Art/Probes/art12_compare/。
Add-Type -AssemblyName System.Drawing
$pairs = @(
    @{ b = "E:\Reborn\Art\Probes\art07_after\t011_map_overview.png";       a = "E:\Reborn\Art\Probes\art12_after\t011_map_overview.png";  o = "cmp_t011_map_overview.png" },
    @{ b = "E:\Reborn\Art\Probes\art07_after\t011_courtyard.png";         a = "E:\Reborn\Art\Probes\art12_after\t011_courtyard.png";    o = "cmp_t011_courtyard.png" },
    @{ b = "E:\Reborn\Art\Probes\art07_after\t011_grass_danger.png";      a = "E:\Reborn\Art\Probes\art12_after\t011_grass_danger.png"; o = "cmp_t011_grass_danger.png" },
    @{ b = "E:\Reborn\Art\Probes\art07_after\creek_wide_a.png";           a = "E:\Reborn\Art\Probes\art12_after\creek_wide_a.png";      o = "cmp_creek_wide.png" },
    @{ b = "E:\Reborn\Art\Probes\art11_ground_after\ravine_tp.png";       a = "E:\Reborn\Art\Probes\art12_after\ravine_tp.png";         o = "cmp_ravine_tp.png" },
    @{ b = "E:\Reborn\Art\Probes\art11_ground_after\ravine_env_creek.png"; a = "E:\Reborn\Art\Probes\art12_after\ravine_env_creek.png";  o = "cmp_ravine_env_creek.png" }
)
$outDir = "E:\Reborn\Art\Probes\art12_compare"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
foreach ($p in $pairs) {
    $ib = [System.Drawing.Image]::FromFile($p.b)
    $ia = [System.Drawing.Image]::FromFile($p.a)
    # 缩到一半宽再拼，防超 vision 的 8MB 上限：640x360 x2 = 1280x360
    $w = 640; $h = 360
    $bmp = New-Object System.Drawing.Bitmap ($w * 2), $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.DrawImage($ib, 0, 0, $w, $h)
    $g.DrawImage($ia, $w, 0, $w, $h)
    $g.Dispose()
    $bmp.Save("$outDir\$($p.o)", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose(); $ib.Dispose(); $ia.Dispose()
    Write-Output ("CMP|{0}|bytes={1}" -f $p.o, (Get-Item "$outDir\$($p.o)").Length)
}
