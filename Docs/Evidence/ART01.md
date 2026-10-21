# ART01 证据：AI 建模工作流 + 试点资产 ENV_BUSH_001（草丛掩体）

执行时间：**2026-10-21（本机系统时钟）**。分支 `art/modeling-pipeline`（从 `main` @ `b4a7790` 拉出）。
所有结论都来自本机实测；未做的一律写 NOT-RUN / NOT-VERIFIED。

---

## 1. 环境检查（实测）

| 项 | 实测值 | 判定方式 |
|---|---|---|
| 项目根 | `E:\Reborn`（`Get-Location`） | 存在 `Game/Reborn/project.godot` |
| Godot 工程 | `E:\Reborn\Game\Reborn` | `project.godot` 存在 |
| Godot 版本 | `4.7.2.stable.official.ed1daf0bf` | `Godot_v4.7.2-stable_win64_console.exe --version`，退出码 **0** |
| Godot 可执行 | `E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` | `Test-Path` = True |
| Blender | `D:\SoftWare\Blender\blender.exe`，**3.3.1**（`build hash b292cfe5a936`，Python **3.10.2**） | `blender.exe --version`，退出码 **0** |
| 现存模型目录 | `Art/Blender/Tests/{StaticProbe_v001,RigProbe_v001}.blend`；`Art/Exports/Tests/{SM_ProbeCube,SK_RigProbe}.glb`；`Game/Reborn/assets/tests/{sm_probe_cube,sk_rig_probe}.glb` | 目录列举 |
| **`assets/characters` / `assets/environment`** | 本次之前**都不存在**（全部美术只有 T005/T006 两个探针） | 目录列举 |
| Git 状态（开工前） | 分支 `main`，`main...origin/main` 同步，仅未跟踪 `modeling.md` | `git status --short --branch` |
| 视觉工具 | `E:\claude-vision-skill\vision.js` 可用 | 已知答案图自检："红色，蓝色"，退出码 0 |

## 2. Agent 的 MCP 能力确认（结论：**没有** Blender MCP，走 CLI）

实测排查（全部为"查过且未发现"，不是"没查"）：

| 检查 | 结果 |
|---|---|
| 本会话工具清单（ToolSearch 目录） | 只有 shell/文件/子代理/浏览器预览/插件打包/图像生成等；**没有任何 Blender 或 3D 类 MCP 工具** |
| 仓库内 `.mcp.json` / `mcp.json` / `*mcp*.{json,yaml,yml}` | **0 命中**（扫全仓，排除 `.git`） |
| `~/.pi-desktop/settings.json`、`mcp.json` | **不存在** |
| `~/.claude.json`、`~/.claude/settings.json` | 存在（属别的客户端），**未被本 agent 使用** |
| Blender 侧 `blender_mcp` Python 包 | `importlib.util.find_spec('blender_mcp')` → **None** |
| 全局 npm 里含 mcp 的包 | **0 命中** |

**结论**：本项目 **MCP 侧无可用实现**，继续沿用 `Docs/BlenderPipeline.md` v0.3 的既定路线
——**Blender 3.3.1 自带无头 CLI + 脚本入库**。MCP 不是阻塞项：CLI 链已在 T005/T006 实测，
本次又跑通"带材质的静态道具"。

## 3. 资产审计：最影响观感的模型与依赖（按"玩家看到的时间 × 画面占比"排序）

| # | 对象 | 现状（实测） | 依赖/风险 | 归属 |
|---|---|---|---|---|
| 1 | 地面 / 四周围栏 / 树根屏障 / 鼠洞 / 庇护棚 / 石头 | 全是 `BoxMesh`（`l_courtyard.tscn` 共 **75** 个 `MeshInstance3D`） | 改它们要动 `world_static` 碰撞 → 会牵动 T011 几何断言、T012 双导航图、T026 掩体判据 | 环境模块（P6） |
| 2 | **草丛掩体** `CoverBushWestA/B`、`CoverBushNorthC`、`CreekReedCover` | 3×0.9×3 的**半透明绿盒子**；**溪边那处完全没有视觉**（实测 `CreekReedCoverMesh = MISSING`） | **只做视觉**：碰撞/可见性由同名 Area3D 数据体量（3×3×3、`visibility_factor=0.4`）决定 → 换视觉**不影响玩法** | **本次试点** |
| 3 | 鼠 NPC / 猫 NPC 身体 | `CapsuleMesh`（0.06/0.18、0.16/0.48）+ 纯色材质 | 观感收益最大（玩家全程盯着猎物），但属**角色/骨骼资产 = P6 阶段门**，还需权重/动画/原地运动 | **P6，本次不动** |
| 4 | 补给点标记 | `resource_point.gd` 按 kind 建 0.30×0.12×0.30 盒子（食物绿 / 水蓝） | 静态、只视觉，碰撞是固定 `BoxShape3D` | 下一批候选 |
| 5 | 玩家自身身体 | 同 3（第一人称几乎不可见，只影响影子） | 同 3 | P6 |

**试点选择理由**：唯一同时满足"非关键 + 易替换 + 视觉收益明确 + 零玩法耦合"的对象；
碰撞/可见性/导航全部由**别的节点**负责，所以"换视觉"可以做到 `git checkout` 一键回退。

## 4. 资产规格与产物（实测数值）

| 项 | 值 |
|---|---|
| 资产名 | `ENV_BUSH_001`（Blender 对象名 = 网格名根） |
| 生成方式 | `Tools/Blender/art01_bush_001.py`，确定性 `seed=20261031`，无外部贴图 |
| 几何 | 140 片草叶 × **2 条交叉带** × 7 三角形 = 1960 + 泥土垫 80 = **2040 三角形**（预算 ≤3000）；Blender 顶点 2812 |
| 包络 | **2.8723 × 0.8800 × 2.8696 m**，原点在地面中心（`AABB.position.y = 0.0000`） |
| 泥土垫 | 半径 1.05 m，**顶面 0.0900 m**（硬上限 `MOUND_CLEAR = 0.12`） |
| 材质 | `MAT_Bush_Leaf` 线性 (0.085, 0.200, 0.075) → Godot albedo **(0.3227, 0.4845, 0.3035)**；`MAT_Bush_Soil` (0.055, 0.038, 0.025) → **(0.2601, 0.2151, 0.1718)**；两者 `roughness=0.85`、`cull_mode=2 (CULL_DISABLED)` = **双面** |
| 交付 glb | `Art/Exports/Environment/SM_Bush_001.glb`，**156,660 B**，sha256 `35e0f2cb3504b79b586dc6ec43c13edec45cd19668ca6122d5e51847833fc257` |
| Godot 侧 | `Game/Reborn/assets/environment/sm_bush_001.glb`，sha256 **与之逐字节相同** + `.import`（纯文本） |
| 可编辑源 | `ENV_BUSH_001_v001.blend` 530,576 B / `_v002` 556,856 B / `_v003` 636,856 B（sha256 `078787e2…`，交付版） |
| 导入后结构（`tool_dump_scene_tree.gd` 实测） | `Node3D "sm_bush_001"` → `MeshInstance3D "ENV_BUSH_001"`，`ArrayMesh` 2 个 surface，2022 verts / 740 tris（v001 时）→ v003 为 5922 verts / **2040 tris** |

**导出 kwargs（实际生效，`unsupported=none`）**：
`export_format=GLB, export_yup=True, export_apply=True, export_materials=EXPORT, export_normals=True,
export_texcoords=False, export_colors=False, export_skins=False, export_animations=False,
export_cameras=False, export_lights=False, export_extras=False, use_selection=False`

## 5. 命令与退出码（全部为实测）

```powershell
# 1) Blender 建模 + 重开校验 + 导出（本次跑了 4 次，前 3 次都抓到失败，见 §6/§7）
& 'D:\SoftWare\Blender\blender.exe' --background --factory-startup `
    --python 'E:\Reborn\Tools\Blender\art01_bush_001.py'          # 最终 EXIT=0，PROBE|done|failures=0

# 2) 资产入工程 + 导入
Copy-Item Art\Exports\Environment\SM_Bush_001.glb Game\Reborn\assets\environment\sm_bush_001.glb
& $g --headless --path 'E:\Reborn\Game\Reborn' --import --quit-after 2000   # EXIT=0，0 条 ERROR

# 3) 读回真实导入结构（不猜）
& $g --headless --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_dump_scene_tree.gd' `
    --quit-after 600 -- 'res://assets/environment/sm_bush_001.glb'          # EXIT=0

# 4) 视觉捕获（不能加 --headless；--quit-after 必须给足，2400 帧会在第 3 个机位前被掐断）
& $g --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_capture_art01.gd' `
    --quit-after 8000 -- art01-preview        # EXIT=0，CAP|art01|done
& $g --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_capture_art01.gd' `
    --quit-after 8000 -- art01-level          # EXIT=0（改造前后各一次）

# 5) 关卡接入（改生成器，不手改 .tscn）+ **重烤导航**
& $g --headless --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_make_courtyard.gd' --quit-after 20000     # EXIT=0
& $g --headless --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_make_courtyard_nav.gd' --quit-after 40000 # EXIT=0

# 6) 断言 + 全量回归
& $g --headless --path 'E:\Reborn\Game\Reborn' --script 'res://tests/run_art01_bush.gd' --quit-after 30000        # EXIT=0，83/83
```

## 6. 视觉验收（3 轮返工，判读原文引用）

工具：`node E:\claude-vision-skill\vision.js <png> "<中文问题>"`。先跑已知答案自检图（答对：红色/蓝色），
再判读资产图。图像内另附**客观像素统计**（`PIX|` 行），避免只靠形容词。

### 6.1 v001 → 判读发现的缺陷

| 机位 | 判读原文（节选） | 对应缺陷 |
|---|---|---|
| `art01_preview_top.png` | "棕色区域大约占整个草丛总面积的 **50% - 70%**…草叶的密度看起来是**稀疏**" | 泥土墩过大 + 草叶太稀 |
| `art01_preview_inside.png` | "画面整体**非常暗**…存在极其巨大的**纯黑色色块**…像是一个巨大的黑洞或未渲染的区域" | **相机在泥土墩内部**（半高 0.16 m × 半径 1.30 m 的实心穹顶） |
| `art01_preview_front.png` | "植被的高度大约相当于旁边白色立方体的 **三分之一到二分之一**" | **取景缺陷**：参照物在 z=1.6（比草丛近 1.6 m），透视比值失真 |

客观量（同机位、同光照）：

| 机位 | v001 `mean_lum` / `green_ratio` | v002 | v003(交付) |
|---|---|---|---|
| inside（草丛内部） | **0.1846 / 0.0065** | 0.5477 / 0.0414 | 0.5552 / 0.0174 |
| top（俯视） | 0.4056 / 0.0115 | 0.4107 / 0.0213 | 0.4138 / 0.0245 |
| front（正面） | 0.5890 / 0.0129 | 0.5970 / 0.0170 | 0.5970 / 0.0179 |

（v003 的 `green_ratio` 比 v002 低是**预期**：草叶从宽板条改成细窄叶，覆盖像素变少但形状正确。）

### 6.2 v002 → 修好泥土墩与密度，但仍被判"像板条"

- 判读原文（`art01_preview_scale_v2.png`）："草的高度大约相当于 1 米立方体的 **70%–85%**"（真值 88%，比例判读已可信）；
  "草叶看起来是**直立的细长柱子/板条状**，边缘较硬直，不是明显弯曲的草叶"。
- 另一次判读（`art01_preview_scale_v3.png`）："顶部也没有自然的收尖（而是**平截**的）…**不像**一丛草"。

### 6.3 v003（交付）→ 叶形近景判读通过

新增近景机位 `art01_preview_blade_close`（相机 1.55 m、fov 30 —— 单片草叶只有 1–3 cm 宽，
远景点位下仅 1–3 像素，**远端机位在物理上不可能判读叶形**）。判读原文：

> "单根草叶的顶端**是尖的**…呈现倾斜、向外弯曲的姿态，部分尖端有明显的**下垂感**…
> 粗细是从根部到尖端**逐渐变细**的…整体看起来**很像一丛草**"

### 6.4 关卡内实景（改造前 / 改造后）

| 机位 | 改造前 | 改造后 |
|---|---|---|
| `art01_level_west_a` | 节点 `MeshInstance3D`（半透明盒子），green_ratio 0.0192 | 节点 `Node3D` + `scene_file_path=res://assets/environment/sm_bush_001.glb` |
| `art01_level_west_a_near` | 0.0701 | 0.0263（大块半透明绿换成细草叶 → 覆盖像素必然变少，**不是变差**） |
| `art01_level_creek` | **green_px = 0 / ratio 0.0000**，且 `cover_visual|CreekReedCoverMesh|MISSING` | green_px **240** / 0.0042（从"什么都没有"到"有草"） |

改造后判读（`art01_level_west_a_after.png`）："画面里有绿色植被。主要是**草叶状**的…同时植被后方还有一个
绿色的**方块状**物体" ← 那个方块是**既有**的 `GrassMoundA/B`（猫的观察点 2×0.5×2 盒子），属本次未动的灰盒。

## 7. 缺陷与修复清单（**全部为本轮实测抓到并修掉**）

| # | 缺陷 | 证据 | 修法 |
|---|---|---|---|
| D1 | 草叶倾角把包络推到 **1.511 m > 1.45 上限** | Blender 自检 `FAIL|built|envelope_exceeded` | 超限时只削减该叶片的 `lean`（不改分布） |
| D2 | **泥土墩是半径 1.30 / 高 0.32 m 的实心穹顶** → 玩家躲进草丛时相机在土里 | inside 图 mean_lum 0.1846 + 判读"巨大纯黑色块" | 半高 0.16→**0.045**、顶面 0.09 ≤ 0.12（新增硬判据）、半径 1.30→1.05、subdiv 2→1 |
| D3 | 草叶太稀，俯视能看穿 | 判读"稀疏"、棕色占 50–70% | 110→170 片（v003 再改结构时降到 140 片 × 交叉双带） |
| D4 | **取景缺陷**：比例参照物与草丛不同深度 → 比例判读失真 | 判读"1/3～1/2"（真值 0.88 m / 1 m） | 参照物全部移到 z=0，新增 `art01_preview_scale` 机位；改后判读 70–85% |
| D5 | 草叶是"直立板条 + 平截叶尖" | v002/v003 判读原文 | 下垂弧线（`DROOP_FACTOR=0.22` 且**补偿总长**）、锥度 `(1-t)^0.75`、**单顶点收尖**、交叉双面带、倾角随半径、宽度 0.024–0.038 |
| D6 | **溪边掩体完全没有视觉**（审计发现的关卡缺陷） | `CAP|art01|cover_visual|CreekReedCoverMesh|MISSING` + `green_px=0` | 生成器里补 `_mk_cover_bush("CreekReedCoverMesh", …)` |
| D7 | 捕获工具：`add_child` 后立刻 `look_at` 报 "Node not inside tree"，**第一个机位静默用默认朝向** | 日志 `ERROR: Node not inside tree. Use look_at_from_position()` | 改 `look_at_from_position()` + 先 `await process_frame` |
| D8 | 验收套件：`CharacterBody3D` **不会自己下落**（运动学体不是刚体）→ 4 条断言 FAIL（landed == start = 0.7000） | `ASSERT|…_probe_rests_on_ground|0.3400|0.7000|FAIL` | 逐帧喂重力 + `move_and_slide()`；修后 landed = **0.3401** |
| D9 | **流程缺陷**：重跑 `tool_make_courtyard.gd` 会**清掉** `NavigationRegion3D`（`NavigationMesh` ext_resource 消失） | 生成后 `git diff` 里两条 `ext_resource NavigationMesh` 被删 | 按既有流程紧接着跑 `tool_make_courtyard_nav.gd`；重烤后 `git status` 显示 nav `.tres` **无改动** ⇒ 几何确实没变 |

另外记录一次**我自己的操作失误**：给 `Tools/Blender/art01_bush_001.py` 和 `tool_capture_art01.gd`
做行号编辑时，两次把范围写宽，误删了 `self_check()` 尾部与 `PREVIEW_VIEWS` 前半段；
均当次用 Read 定位后修复，最终文件经 `python -m py_compile` 与 `--check-only` 双通过。
教训：改这两类文件前先 Read 取真实行号，不要凭偏移猜。

## 8. 回归结果

| 层 | 结果 |
|---|---|
| Blender 自检 | `PROBE|done|failures=0`，退出码 0（重建 + 重开 `.blend` 两次自检都过） |
| ART01 套件 | `SUMMARY|checks=83|failures=0` / `RESULT|PASS`，退出码 0 |
| 全量回归 | **29 套、3081 条断言全绿**，每套退出码 0、`SCRIPT ERROR` 计数 **0**：T002 18、T005 50、T006 65、T007 22、台阶探针（退出码 0）、T008 114、T009 81、T010 95、T011 210、T012 79、T013 159、T013-移动回归 73、T014 106、T015 93、T016 118、T017 128、T018 73、T019 72、T020 164、T021 279、T022 168、T023 178、T024 136、T025 175、T026 96、T027 96、T029 39、T030 111、ART01 83 |

关键点：**T011（几何 210 条）、T012（双导航图 79 条）、T026（掩护 96 条）全部照旧通过**
—— 说明"换视觉"确实没有碰到碰撞、导航与掩护逻辑。

## 9. 边界声明

- **没有**安装/卸载任何软件；**没有**连接 MCP；**没有**改 git 全局配置；**没有**删除任何源资产。
- **没有**推送、**没有**发布。
- 改动范围：新增 `Tools/Blender/art01_bush_001.py`、`Game/Reborn/tests/{run_art01_bush,tool_capture_art01}.gd`、
  资产与 3 个 `.blend`、`Art/Probes/art01_*.png`；**修改**只有 `tests/tool_make_courtyard.gd` 与它生成的
  `scenes/maps/l_courtyard.tscn`。**gameplay 脚本零改动**。
- **未做**：角色/骨骼资产（P6 阶段门）、其余灰盒方块（地面/围栏/树根屏障/庇护棚/补给点标记）、
  真实按键输入验证、打包复验（本次未重导 `Builds/`，属"是否发布新构建"的负责人决策）。
- **视觉判读的能力边界**：720p 下单片草叶只占 1–3 像素，**远景机位无法判读叶形**；相关结论只在
  `art01_preview_blade_close` 近景成立。判读模型对"颜色/大形状/文字"较准，对"这是我预期的几何吗"会附和提问措辞，
  所以结论一律配 `PIX|` 客观量与实测尺寸。

## 10. 待负责人处理

| 事项 | 说明 |
|---|---|
| 草丛是否作为正式基线 | 现在轴：可编辑 `.blend` v003 + `SM_Bush_001.glb` + 关卡 4 处接入，多角度视觉已判读、返工 3 轮。是否 `approved` 由负责人定（本记录不自行批准） |
| 下一批资产优先级 | 建议：① 补给点标记（食物/水，静态、零耦合）→ ② 树根屏障 + 鼠洞（结构，需要与 T012 导航一起验）→ ③ 庇护棚 → ④ **猫/鼠角色与骨骼（P6 阶段门，必须先解除阶段门）** |
| 草丛观感是否够"高" | 现在 0.88 m（旧盒子 0.9 m）。猫 0.48 m 躲在里面只露出上半身；若希望"完全看不见"，需要提高草高或加密 —— 属玩法/观感平衡，需负责人定 |
| 关卡生成流程提醒 | 任何人重跑 `tool_make_courtyard.gd` 后**必须**再跑 `tool_make_courtyard_nav.gd`，否则导航面丢失（本次实测踩到） |
| 文档日期差异 | 本机系统时钟为 2026-10-21，而仓库内 T028/T029/T030 标注为 10-25～10-27。未改动他人日期记录，仅在本文件标注时钟来源 |
