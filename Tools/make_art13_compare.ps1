# ART13：把改前/改后帧水平拼成对比图（左=改前，右=改后），供 vision 判读。
# 改前基线：Art/Probes/art12_after/（HEAD 提交状态的原帧）。
# 规则：每块板的"改后"一律指向**该步的步骤快照**（art13_steps/sN），不指向 art13_after——
# art13_after 永远是最新状态，后续步骤会污染早先步骤的对比（S6 时实际踩过）。
Add-Type -AssemblyName System.Drawing
$pairs = @(
    @{ b = "E:\Reborn\Art\Probes\art12_after\ravine_tp.png"; a = "E:\Reborn\Art\Probes\art13_steps\s1\ravine_tp.png"; o = "cmp_s1_ravine_tp_exposure.png" },
    @{ b = "E:\Reborn\Art\Probes\art13_steps\s1\ravine_env_far.png"; a = "E:\Reborn\Art\Probes\art13_steps\s2\ravine_env_far.png"; o = "cmp_s2_ravine_far_tiling.png" },
    @{ b = "E:\Reborn\Art\Probes\art13_steps\s1\ravine_tp.png"; a = "E:\Reborn\Art\Probes\art13_steps\s2\ravine_tp.png"; o = "cmp_s2_ravine_tp_tiling.png" },
    @{ b = "E:\Reborn\Art\Probes\art12_after\t011_grass_danger.png"; a = "E:\Reborn\Art\Probes\art13_steps\s3\t011_grass_danger.png"; o = "cmp_s3_grass_danger_ground.png" },
    @{ b = "E:\Reborn\Art\Probes\art12_after\t011_courtyard.png"; a = "E:\Reborn\Art\Probes\art13_steps\s3\t011_courtyard.png"; o = "cmp_s3_courtyard_ground.png" },
    @{ b = "E:\Reborn\Art\Probes\art12_after\t011_map_overview.png"; a = "E:\Reborn\Art\Probes\art13_steps\s3\t011_map_overview.png"; o = "cmp_s3_map_overview_ground.png" },
    # S4（结构接地阴影）：基线 = S3 状态快照（贴图地面、无结构阴影），改后 = S4 快照（+9 阴影）
    @{ b = "E:\Reborn\Art\Probes\art13_steps\s3\t011_courtyard_shelter.png"; a = "E:\Reborn\Art\Probes\art13_steps\s4\t011_courtyard_shelter.png"; o = "cmp_s4_courtyard_shelter.png" },
    @{ b = "E:\Reborn\Art\Probes\art13_steps\s3\t011_roots_barrier_oblique.png"; a = "E:\Reborn\Art\Probes\art13_steps\s4\t011_roots_barrier_oblique.png"; o = "cmp_s4_roots_barrier.png" },
    @{ b = "E:\Reborn\Art\Probes\art13_steps\s3\t011_map_overview.png"; a = "E:\Reborn\Art\Probes\art13_steps\s4\t011_map_overview.png"; o = "cmp_s4_map_overview_fence.png" },
    # S5（湿泥带 + 溪中石/岸墙暗片）：creek 机位基线 = art12_after（ART12 提交态；S3 地表贴图差异已知通过，
    # vision 提问聚焦水线）；gap_lane 基线 = S4 快照（S5 才加岸墙基脚）
    @{ b = "E:\Reborn\Art\Probes\art12_after\creek_wide_a.png"; a = "E:\Reborn\Art\Probes\art13_steps\s5\creek_wide_a.png"; o = "cmp_s5_creek_wide_wetband.png" },
    @{ b = "E:\Reborn\Art\Probes\art12_after\creek_low_a.png"; a = "E:\Reborn\Art\Probes\art13_steps\s5\creek_low_a.png"; o = "cmp_s5_creek_low_wetband.png" },
    @{ b = "E:\Reborn\Art\Probes\art13_steps\s4\t011_creek_gap_lane.png"; a = "E:\Reborn\Art\Probes\art13_steps\s5\t011_creek_gap_lane.png"; o = "cmp_s5_creek_gap_bankwall.png" },
    # S6（远景深度雾 / A5 空气透视）：基线 = S5 快照（无雾），改后 = S6 快照（depth fog 80-170、energy 0.45）
    @{ b = "E:\Reborn\Art\Probes\art13_steps\s5\t011_map_overview.png"; a = "E:\Reborn\Art\Probes\art13_steps\s6\t011_map_overview.png"; o = "cmp_s6_overview_aerial.png" },
    @{ b = "E:\Reborn\Art\Probes\art13_steps\s5\t011_courtyard.png"; a = "E:\Reborn\Art\Probes\art13_steps\s6\t011_courtyard.png"; o = "cmp_s6_courtyard_grayveil.png" }
)
$outDir = "E:\Reborn\Art\Probes\art13_compare"
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
