# ART09-E 证据：展板切片关（溪谷）与第三人称构图

状态：done / 环境材质 **FAIL（未达展板级，按路径 C 预期）**
日期：2026-10-29
分支：`art/modeling-pipeline`

## 1. 命令与结果

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
& $g --headless --path $proj --script 'res://tests/tool_probe_aabb.gd' --quit-after 60000
& $g --headless --path $proj --script 'res://tests/tool_make_ravine_board.gd' --quit-after 60000
& $g --headless --path $proj --script 'res://tests/run_art09_frame_contract.gd' --quit-after 60000
& $g --path $proj --script 'res://tests/tool_capture_art09_board.gd' --quit-after 60000 -- ravine
```

| 套件 | 结果 |
|---|---|
| `tool_probe_aabb.gd`（新增） | 9 件资产 AABB 全部 `min_y = 0.000`（**原点在脚底**） |
| `tool_make_ravine_board.gd`（新增） | `save_result=0 (OK)`；巨石 5 / 草丛 10 / 泥舌 4 / 盘根 6 / 矮墙 3 / 围栏 2 / 立柱 4 / 脚边石 4 / 脚边草 3 |
| `run_art09_frame_contract.gd`（新增） | **40/40，0 failures，exit 0** |
| `run_t011_greybox.gd` | 229/229，exit 0（庭院geometry/导航未受影响） |
| `run_art09_tokens / menu / species / hud` | 15/15、42/42、59/59、63/63 全绿 |
| `tool_capture_art09_board.gd -- ravine`（**非 headless**） | 5 帧全部 `save_result=0 (OK)`，`CAP|ravine|done`，exit 0 |

关键读数：

```text
FRAME_CONTRACT|env|tonemap=3|ssao=true|fog=9..46|exposure=1.05|sky=panorama
FRAME_CONTRACT|sun|energy=1.45|color=(1.0, 0.9, 0.72, 1.0)|rot=(-24.0, 32.0, 0.0)
FRAME_CONTRACT|counts|{ "boulders": 5, "bushes": 10, "mud_tongues": 4, "root_barrier": 6,
  "walls": 3, "fences": 2, "shelter_posts": 4, "near_rocks": 4, "near_bushes": 3 }
FRAME_CONTRACT|meshes=48
FRAME|TPCamera|pos=(0.45, 0.68, 3.75)|pitch=6.3|fov=58|dof=on
SUMMARY|checks=40|failures=0
```

## 2. 截图

`Art/Probes/art09_board_after/`

- `ravine_tp.png`：第三人称主帧（猫在左下、面向溪谷、远景景深开）
- `ravine_tp_wide.png`：宽景
- `ravine_env_creek.png`：溪流特写
- `ravine_env_roots.png`：树根洞口
- `ravine_env_far.png`：远景框景（矮墙/围栏/庇护棚）

## 3. 逐项视觉判读（对比展板第三人称实玩区）

| 展板要素 | 现状 | 判定 |
|---|---|---|
| 动物在下三分之一、背对镜头、视线进景 | 猫站在 (0, 0.36, 2.4) 面朝 −Z，占屏高约 1/6，位于左下 | **PASS**（位置）；**FAIL**（占比偏小，展板约 1/4） |
| 画面纵深：前景地面 → 溪流 → 中景石/洞 → 远景林 | 四层齐备，深度雾 9→46 m 把远景淡下去 | **PASS** |
| 森林背景（不是围墙） | CC0 `mossy_forest` HDRI 天空球，树冠与光斑真实 | **PASS** |
| 逆光/暖调主光 + 冷色补光 | 主光 (−24°,32°) 能量 1.45 暖色、补光 0.38 冷色；地面阴影可见 | **PASS** |
| 景深（近实远虚） | `CameraAttributesPractical` 远景景深开启（本版本支持，`dof=on`） | **PASS** |
| 溪水像浅溪 | 水面是程序化 shader 的**高饱和蓝 + 白沫**，浅看像泳池 | **FAIL**（需真实浅水材质/河床贴图） |
| 溪岸过渡自然 | `WetShore` 深色泥带在画面里读成一条"沥青带"；泥舌太薄 | **FAIL** |
| 前景地面有草/落叶细节 | 前景是一大片平滑褐色地面（只有 3 团脚边草、4 块小石） | **FAIL**（缺地面散布资产） |
| 装饰材质达展板级 | 巨石是 CC0 扫描件（尚可），矮墙/围栏/棚顶仍是旧的低模石皮 | **FAIL** |

**结论：构图、光照、后处理三层已经立起来（这是本阶段真正的产出）；水面/岸线/地面细节/低模石墙仍是
明显差距，故整体环境材质判 FAIL。**

## 4. 过程中修掉的真实缺陷（含一次人为事故）

1. **主体掉出画面**：展示关零碰撞，`CharacterBody3D` 直接下落（首轮实测 y = −0.269）。
   → 取证工具里加 `set_physics_process(false)` + 复位位置。
2. **水面 BoxMesh 侧壁穿帮**：近景能看到那块"水池挡板"的立面。→ 展示关改用 `PlaneMesh` 薄片
   （庭院那边仍保持 BoxMesh，因为 T011 有 `creek_water_mesh_is_box` 断言）。
3. **石墙/围栏被吊到半空**：我一开始猜"glb 原点在中心"，给矮墙 +0.40、围栏 +1.50、立柱 +0.81。
   → 写 `tool_probe_aabb.gd` 实测：**9 件资产 min_y 全是 0.000（原点在脚底）**，偏移全部回退。
   这条经验已写进任务规格。
4. **⚠️ 人为事故（已恢复）**：我用 `Get-Content | -replace | Set-Content -NoNewline` 批量改生成器的
   三个高度常量，结果把整个文件的 UTF-8 与行尾**写坏**（中文注释变成 `玩?`，行被并成一行）。
   因为该文件是新增未跟踪文件，`git checkout --` 无效 → 用 `Write` + `Edit` **整文件重写**恢复，
   之后 `--headless` 重跑生成器与 40 条契约均通过。
   **教训（与 Handoff 里 T029 的同名事故一致）**：工程源码一律用编辑工具改，不用 PowerShell 管道写回。

## 5. 未验证 / 边界

- **没做性能实测**：这张关有 48 个 mesh（含 5 块巨石 ~7.5k tris/块）。`tool_perf_probe.gd` 未跑，
  帧率 `NOT-RUN`；本关不参与正式流程，暂不影响玩法性能预算。
- **没做 960×540 / 其它分辨率取证**：只在 1280×720 下取景。
- **没有真人视觉评审**：vision 服务未调用，以上判读是截图人工对比。
- **未接入正式流程**：`main.tscn` 仍走 `l_courtyard`（契约断言 `main_scene_not_referencing_ravine` 守着）。
- **资产仍卡授权**：写实水面/河床/地表散布/石墙替换属素材升级，需负责人按 `Docs/ART08_CHARACTER_ASSET_REGISTER.md`
  同一套授权门逐项确认。

## 6. 恢复入口

删除本阶段新增的 4 个脚本 + `scenes/maps/l_ravine_board.tscn` + `Art/Probes/art09_board_after/` 即可完全回退；
`l_courtyard.tscn`、`tool_make_courtyard.gd` 与 ART07 未提交改动**未被触碰**。


## 7. A+B 修复轮（2026-10-29 追加）

针对 §3 里判 FAIL 的五项，做了「纯代码（A）+ CC0 贴图（B）」的一轮修复。

### 改了什么

| 项 | 根因 | 修法 | 断言 |
|---|---|---|---|
| 猫占屏 1/6 | 机位太远 + FOV 58 | 斜距 1.45 m、FOV 58→**45**、相机 y 0.58→0.50、`look.y` 降到 −0.10（下俯 ~11°） | 取证工具用 `unproject_position` 量 `SUBJECT\|px_ratio`，超 [0.20, 0.30] 直接 `CAP\|ravine\|FAIL` + 退出码 1；实测 **0.255** |
| WetShore 沥青带 | 一块 16×0.55 纯色直板横贯画面 | 删除该节点，改为 **14 段不规则泥板**（长 0.9–2.5 / 宽 0.28–0.62 / yaw ±13° / 明度 0.150–0.225 抖动，确定性哈希摆放） | `shore_plates_at_least_10`、`legacy_wide_shore_removed` |
| 前景缺草/落叶 | 只有 3 团草 + 4 块石 | 确定性散布 **96 株草**（bush×0.10–0.22，带风摆）+ **34 颗碎石**（boulder×0.05–0.12） | `near_grass_at_least_80`、`near_pebbles_at_least_20` |
| 溪水像泳池 | 又亮又滑（roughness 0.08 / specular 0.55 / 白沫全屏）+ 河床是纯色板 | 去饱和（shallow 0.20/0.30/0.30、deep 0.06/0.11/0.12）、**粗糙度 0.35**、**镜面 0.25**、`base_alpha` 0.55→**0.32**、`ripple_scale` 3→**9**、`foam_strength` 0.55→0.35；河床换 **`dry_river_pebbles` CC0 贴图**（uv 10×3.4） | `water_alpha_le_0_45`、`water_roughness_ge_0_25`、`water_finer_ripples`、`creek_bed_textured` |
| 矮墙/围栏低模石皮 | 旧低模石皮、无贴图 | glb 表面 override 成 **`stone_wall_02`**（diff+normal+ARM；墙 uv 2.4×1.2、围栏 3.0×2.4）；地面换 **`forest_floor`**（uv 22×24，并压一档 albedo 拉回冷绿） | `stone_wall_textured`、`ground_textured` |

### 结果

```text
SUBJECT|px_ratio=0.255|target=0.20..0.30
FRAME_CONTRACT|counts|{ "near_grass": 96, "near_pebbles": 34, "shore_plates": 14,
  "legacy_wide_shore": 0, "walls": 3, "fences": 2, ... }
SUMMARY|checks=48|failures=0
```

- `run_art09_frame_contract.gd`：**48/48**（原 40 条 + 本轮新增 8 条）。
- `tool_capture_art09_board.gd -- ravine`：`SUBJECT|px_ratio=0.255`、4 帧 `save_result=OK`、`CAP|ravine|done`、exit 0。
- 回归：`run_t011_greybox` 229/229、`run_art09_tokens` 15/15、`run_art09_menu_contract` 42/42、
  `run_art09_species_layout` 59/59、`run_art09_hud_layout` 63/63。
- 截图（同名覆盖）：`Art/Probes/art09_board_after/{ravine_tp,ravine_env_creek,ravine_env_roots,ravine_env_far}.png`

### 判读变化

| 项 | 上一轮 | 本轮 |
|---|---|---|
| 猫占屏比 | FAIL（≈1/6） | **PASS**（0.255，展板约 1/4） |
| 岸边「沥青带」 | FAIL | **PASS**（打散成 14 段泥板，不再有单一长条） |
| 前景散布 | FAIL | **PASS**（96 草 + 34 石） |
| 溪水像泳池 | FAIL | **部分改善、仍 FAIL**：颜色/高光/透明度压下来了、水下碎石可见，但**仍是一层平水面**，没有浅溪的折射与岸线白边 |
| 石墙/围栏 | FAIL | **部分改善、仍 FAIL**：已换 CC0 扫描石皮（带法线/粗糙度），但仍是旧几何平铺，模块缝与体量密度不如展板 |
| 地面 | FAIL | **部分改善**：`forest_floor` 是「秋叶+砾石」色系，靠 tint 拉回冷绿，仍偏"秋叶地"；更合适的 `forest_leaves_02/03/04` 未下载（待负责人定） |

### 本轮踩的坑（含我自己的操作事故）

1. **glb 的 `surface_override_material` 不会自动进 `pack()`**：glb 子网格的 `owner` 指向实例根，
   `PackedScene.pack()` 只序列化 owner 指向场景根的节点 → 覆盖材质丢失（`stone_wall_textured` 抓到）。
   修法：套完材质后把整棵子树 `owner` 认领给场景根（`_own_recursive`，**只在展示关这么做**）。
2. **两次按行号区间替换把生成器改坏**（漏掉函数头 / 吃掉相邻函数尾部）。该文件已提交，
   于是 `git checkout -- <file>` 回到 HEAD，再用**唯一锚点**逐条改才稳定。
   教训：大段重写不要猜行号区间；先回退到已提交版本，再小步精确改。
3. `dry_decay_leaves` 想当落叶卡片，实测**没有 alpha 通道**，已删除未入库（见 `Docs/THIRD_PARTY_ASSETS.md` §9）。

### 仍未做（明确边界）

- 展板级水面需要带流动法线/泡沫遮罩的水材质或 Water 插件（C 档，需授权/工时）。
- 落叶卡片需要带 alpha 的素材（CC0 没有现成的；可 Blender 自制 alpha card，属美术工时）。
- 石墙要真正像展板需要重新建模不规则砌体（C 档，1–2 天）。
- 本关性能仍未实测（`tool_perf_probe` 未跑，`NOT-RUN`）；网格数从 48 涨到 189（散布 + 摊平的石墙子树）。
