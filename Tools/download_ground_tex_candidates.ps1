# 补充下载短名单候选 leafy_grass（1K 三件套）到 references/_downloads
$ErrorActionPreference = "Stop"
$c = "leafy_grass"
$dir = "E:\Reborn\references\_downloads\$c"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$api = Invoke-RestMethod -Uri "https://api.polyhaven.com/files/$c"
foreach ($m in @("diffuse", "nor_gl", "arm")) {
    $info = $api.$m."1k".jpg
    $dest = Join-Path $dir (Split-Path $info.url -Leaf)
    if (-not (Test-Path $dest)) { Invoke-WebRequest -Uri $info.url -OutFile $dest }
    $bytes = (Get-Item $dest).Length
    $md5 = (Get-FileHash $dest -Algorithm MD5).Hash.ToLower()
    $sha256 = (Get-FileHash $dest -Algorithm SHA256).Hash
    $ok = ($bytes -eq $info.size) -and ($md5 -eq $info.md5)
    Write-Output ("TEXDL3|{0}|{1}|bytes={2}|md5_ok={3}|sha256={4}" -f $c, $m, $bytes, $ok, $sha256)
}
# 拷进项目临时比对目录（统一 _diff_ 命名）
$dst = "E:\Reborn\Game\Reborn\assets\environment\tex_candidates"
Copy-Item (Get-ChildItem "$dir\*diff*1k.jpg").FullName "$dst\${c}_diff_1k.jpg"
Copy-Item "$dir\${c}_nor_gl_1k.jpg" $dst
Copy-Item "$dir\${c}_arm_1k.jpg" $dst
Write-Output "TEXDL3|copied_to=$dst"
