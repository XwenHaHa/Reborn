# THIRD_PARTY_ASSETS —— 第三方资产与署名义务登记

登记规则：任何进入仓库的第三方文件（含**仅作参考**的图片/模型）都必须在此登记来源与许可。
`references/**` 下的文件默认 **reference_only（只作参考，不进游戏）**。

版本 1.0（2026-10-21）

---

## 1. 已实际下载到仓库的文件（本轮，全部来自 Poly Haven，CC0）

来源站点：**Poly Haven** — https://polyhaven.com
许可：**CC0 1.0 Universal（公有领域献出，无需署名）** — 依据 <https://polyhaven.com/license>（实测抓取：
"CC0 1.0 Universal - public domain dedication, no attribution r…"；资源页 `polyhaven.com/a/boulder_01` 同样标注 CC0）

| 文件（仓库内） | 字节 | 说明 |
|---|---|---|
| `references/environment/boulder/candidates/boulder_01_polyhaven_gltf_1k/boulder_01.gltf` | 2,773 | Boulder 01 glTF 描述文件 |
| `references/environment/boulder/candidates/boulder_01_polyhaven_gltf_1k/boulder_01.bin` | 2,938,808 | 网格数据 |
| `…/textures/boulder_01_diff_1k.jpg` | 987,467 | 基础色 1K |
| `…/textures/boulder_01_nor_gl_1k.jpg` | 1,183,552 | 法线（gl）1K |
| `…/textures/boulder_01_arm_1k.jpg` | 659,386 | AO/Rough/Metal 1K |

- 作者：**Rico Cilliers**（Poly Haven 资产页署名）
- 下载方式：`https://api.polyhaven.com/files/boulder_01` 返回的匿名直链，逐个文件下载后**与 API 的 size 逐字节核对一致**
- 用途：`ENV_BOULDER_001` 参考/候选（隔离存放，**未进入 `Game/Reborn/`**）
- 署名义务：**无**（CC0）；仍在此登记以便追溯

## 2. 已下载的参考缩略图（仅作参考，不随游戏分发）

缩略图来自各资产页面 CDN，用于同角度对比与人工评估；**不进入游戏包**。

| 文件 | 来源页 | 作者 | 许可 | 署名义务 |
|---|---|---|---|---|
| `references/characters/cat/candidates/cat_fripouille_thumb.jpg` | https://sketchfab.com/models/0ab14bf98e754f8d90fe1bf1c84ca66c | guillaume.bolis | CC BY 4.0 | 署名（若最终采用） |
| `…/cat_bigcat_gbarzu_thumb.jpg` | https://sketchfab.com/models/e2fe596cf22c4bb9b78fb979a2697c7c | gbarzu | CC BY 4.0 | 署名 |
| `…/cat_scan_sleeping_thumb.jpg` | https://sketchfab.com/models/ae07a741be6944e8ba5e2657069d3aaf | albetan2012 | CC BY 4.0 | 署名 |
| `…/cat_toon_omabuarts_thumb.jpg` | https://sketchfab.com/models/b2bd1ee7858444bda366110a2d960386 | omabuarts | CC BY 4.0 | 署名 |
| `references/characters/mouse/candidates/mouse_charliecatling_thumb.jpg` | https://sketchfab.com/models/bf516bd5a93341b194976f6f391d1e30 | charliecatling | **Sketchfab Free Standard** | 依 Free Standard 条款（待人工核对） |
| `…/mouse_arribadaclub_thumb.jpg` | https://sketchfab.com/models/b05c5a51278645d99d40debb8d6ff6bd | arribadaclub | CC BY 4.0 | 署名 |
| `…/rat_rhcreations_thumb.jpg` | https://sketchfab.com/models/847629266c0f442da74fb132f46f3baf | rhcreations | CC BY 4.0 | 署名 |
| `…/mouse_studioochi_demo_thumb.jpg` | https://sketchfab.com/models/c301d0cd9b4941d6a0d61c576c66ef36 | studioochi | CC BY 4.0 | 署名 |
| `references/environment/root_hole/candidates/stump_callum_arb_thumb.jpg` | https://sketchfab.com/models/bb383af9741d4dd48dbccde3b7bf8b1e | callumARBInnovators | CC BY 4.0 | 署名 |
| `…/dead_tree_trunk_02_thumb.jpg` | https://polyhaven.com/a/dead_tree_trunk_02 | Jenelle van Heerden / Rico Cilliers | CC0 | 无 |
| `references/environment/boulder/candidates/boulder_01_thumb.jpg` | https://polyhaven.com/a/boulder_01 | Rico Cilliers | CC0 | 无 |
| `…/coast_rocks_01_thumb.jpg` | https://polyhaven.com/a/coast_rocks_01 | Rob Tuytel / Rico Cilliers | CC0 | 无 |
| `references/environment/fence/candidates/wall_stefan_wr_thumb.jpg` | https://sketchfab.com/models/0788f8b362a6463fa08ad75273c530ea | stefan_wr | CC BY 4.0 | 署名 |
| `…/fence_yadrogames_pack_thumb.jpg` | https://sketchfab.com/models/0cbf546419cf499cbabfee3af0916215 | yadrogames | CC BY 4.0 | 署名 |

> Sketchfab 许可文字取自其公开 API（`license.requirements`），CC BY 4.0 的原文是
> "Author must be credited. Commercial use is allowed."（即**允许商用，必须署名**）。

## 3. 若最终采用 CC BY 资产，必须完成的署名动作

1. 在游戏内"关于/致谢"页（或随包 `CREDITS.txt`）列出：**资产名 + 作者 + 来源 URL + 许可（CC BY 4.0 + 链接）**。
2. 保留 `references/` 中的来源页 URL 与许可快照（本文件 + `reference_manifest.json`）。
3. 修改/二次创作需注明"修改过"（CC BY 要求标注改动）。
4. **不得**把 CC BY 资产用于暗示作者为本项目背书。

## 4. 未下载、仅登记页面的来源

Sketchfab 模型**全部未下载**（需登录）；它们只在 `reference_manifest.json` 里登记为 `reference_pending`，
本轮**没有**任何 Sketchfab 文件进入仓库（除上表参考缩略图）。

## 5. 明确不采用的来源

| 来源 | 原因 |
|---|---|
| `blendkit.io` | 仅可达性探测（HTTP 200），未检索授权条款 → 本轮不作候选 |
| `poly.pizza` / `opengameart.org` | 可达但本轮未检索 → 后续补充来源 |
| `fab.com` | 仅出现在某候选描述的外链，未访问 |
| Sketchfab 上"Cat [Murdered: Soul Suspect]" | 作品名指向商业游戏角色，疑似提取物 → **不列入候选** |
