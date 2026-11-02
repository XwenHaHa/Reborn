# ART11：地表贴图选型（forest_leaves_02/03/04 + 补充候选 → leafy_grass）

状态：**done（选型+接入+回归+取证完成；美术效果部分达标，遗留项见证据 §6）**
日期：2026-11-02。负责人授权：ART10 证据 §6"地表青苔/森林叶层（forest_leaves_02/03/04）"选型请求
+ 二次指示"必要时再补 1–2 个同类"。

## 1. 目标

展板关 `l_ravine_board.tscn` 的地面（ART10 GAP 表 G5"地面平铺落叶地毯"）换用更接近
概念展板地表（"暖棕泥土与鲜活苔绿交织、苔藓密覆、落叶零星、湿润、明度较高"）的 CC0 贴图。
**只动地面材质与贴图资产，不动几何/碰撞/导航/玩法。**

## 2. 约束

- 只用 Poly Haven CC0；源文件放 `references/_downloads/`（gitignored，不进包），
  选定的工作副本（1K 三件套）按既有模式入 `Game/Reborn/assets/environment/tex/` 并登记
  `Docs/THIRD_PARTY_ASSETS.md` §9.1。
- 候选都不合适就如实报"都不合适"，不硬选。
- 所有实跑/截图走 `Tools/CaptureRun.ps1`（窗口屏幕外、不弹前台）。
- vision 串行调用（15 s 间隔），单次失败记 NOT-VERIFIED 或重试一次。

## 3. 步骤（实际执行）

1. `Tools/download_ground_tex_candidates.ps1`：经 `api.polyhaven.com/files/<id>` 匿名直链下载
   forest_leaves_02/03/04 的 1K diff/nor_gl/arm 到 `references/_downloads/`，
   字节与 API size、md5 逐一校验通过，另记 SHA256。
2. 候选拷入临时目录 `assets/environment/tex_candidates/`（比对用，选型后已删除），
   `--headless --import` 导入后写 `tests/tool_capture_ground_compare.gd`：
   同机位两视图（ground 近景 / scene=ravine_env_creek 同参）渲 4 变体（baseline + 3 候选）。
3. vision 判读：贴图单独看与场景内看结论不一致（fl02 贴图 9/10 但场景 4/10），
   按"必要时补 1–2 个同类"授权扩搜苔藓向候选：6 个新候选 diffuse 拼 9 宫格
   （`Tools/make_tex_preview_sheet.ps1` → `preview_sheet.png`）一次 vision 短名单 →
   forest_leaves_02 与 leafy_grass 入围。
4. leafy_grass 三件套补齐下载 → 加入对比工具重跑同机位 → 并排 2×2 图
   （`Tools/make_gtex_side_by_side.ps1`）一次 vision 终审 → **选 leafy_grass**。
5. 接入：`tool_make_ravine_board.gd` 地面常量换 `TEX_GROUND_*`（leafy_grass），
   tint (0.82,0.88,0.74)、uv 24x26、roughness 1.0；重建 `l_ravine_board.tscn`。
6. 回归 + 取证 + 1 轮有依据修正（详见证据 §5）。

## 4. 参数登记（old → new）

| 参数 | old（forest_floor，ART10 后） | new（leafy_grass，ART11） | 依据 |
|---|---|---|---|
| 地面贴图三件套 | `forest_floor_{diff,nor_gl,arm}_1k.jpg` | `leafy_grass_{diff,nor_gl,arm}_1k.jpg` | 选型判读（证据 §3/§4） |
| `albedo_color` | (0.50, 0.58, 0.46) | **(0.82, 0.88, 0.74)** | vision：leafy_grass 有粉/紫灰偏，往暖棕-苔绿拉且保持较亮 |
| `uv1_scale` | 15x17 | **24x26** | 第 1 轮修正：近景大图案重复 → 加密平铺（单 tile ~1.9 m） |
| roughness | 0.96 | **1.0** | 第 1 轮修正：tp 判读"高反光像水面" → 漫反射回归 |

## 5. 用例与验收

- U1 契约：`run_art09_frame_contract` **48/48 PASS**（ground_textured 等 20 StaticBody 断言不含贴图名，通用判定）。
- U2 选型：vision 多轮判读可复现（证据 §3/§4）；落选者保留下载与哈希记录。
- U3 接入后视觉：tp 主视角 6/10 → 修正后 **7.5/10**（"反光显著减轻、平铺重复大幅减弱、
  已像长苔藓的泥地"）；遗留：中景强光过曝（ART10 已知项）、远景平地仍有轻度平铺感、
  草根接触阴影（C 阶段/另案）。
- U4 资产登记：THIRD_PARTY_ASSETS §9.1（来源/许可/字节/SHA256）。

## 6. 失败恢复

- 回退贴图：`tool_make_ravine_board.gd` 把 `TEX_GROUND_*` 三行改回 `TEX_FLOOR_*`、
  参数改回 §4 的 old 列，重跑生成器即可（forest_floor 三件套仍在库）。
- 源文件重取：按 THIRD_PARTY_ASSETS §9.1 的资产页 + `Tools/download_ground_tex_candidates.ps1` 模式。
