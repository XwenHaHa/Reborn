# ART11 证据：地表贴图选型与接入（2026-11-02）

任务规格：`Docs/Tasks/ART11_GROUND_TEXTURE.md`。全部实跑/截图走 `Tools/CaptureRun.ps1`
（窗口屏幕外 -2400,-2400；headless 走 GUI exe + `-Headless` 开关，零窗口）。

## 1. 候选下载与校验

`Tools/download_ground_tex_candidates.ps1`（含 BOM）经 `api.polyhaven.com/files/<id>` 匿名直链下载，
字节与 API `size` 一致、`md5` 一致（`md5_ok=True`），SHA256 登记如下。源文件在
`references/_downloads/`（gitignored，不进包不进库）。

| 候选 | map | 字节 | SHA256 |
|---|---|---|---|
| forest_leaves_02 | diff | 437,891 | 2BAC85CDC76927FA…A68C9AA5 |
| forest_leaves_02 | nor_gl | 577,163 | CF6A40AB24F44D3E…DA0805E290 |
| forest_leaves_02 | arm | 313,980 | AF70DCAA5F6C8770…FFF2BD6EB |
| forest_leaves_03 | diff | 1,000,751 | 9E6604B5958DFA46…D7D9D92C |
| forest_leaves_03 | nor_gl | 1,404,719 | B3055048B1F1EF26…AB102F9D9 |
| forest_leaves_03 | arm | 1,044,455 | 6E712345B46D7642…AFF38856A |
| forest_leaves_04 | diff | 423,500 | A898E6EF0668A40F…D013C9DADE |
| forest_leaves_04 | nor_gl | 581,919 | 6B7C4086FC28B7B1…092C1BB0C |
| forest_leaves_04 | arm | 355,419 | E253BA0615D1DA23…2AE53BE |
| leafy_grass（补充） | diff | 1,195,394 | CFA40BC9D9417D18…39BC05E4A |
| leafy_grass（补充） | nor_gl | 1,466,049 | 832328216ADC0A7E…C4B2EBD6 |
| leafy_grass（补充） | arm | 1,010,081 | 95432451CB269379…1703F089D |
| forest_ground_04（短名单陪跑） | diff | 1,113,899 | 50A4DDA30875020C…AE73CBD2C |
| forest_ground_05（同上） | diff | 655,934 | 9A2C6D085F05CEE4…DBB00558 |
| forest_ground_06（同上） | diff | 851,532 | 2BCFE6E3DE263E50…10AFA7E18 |
| leaves_forest_ground（同上） | diff | 1,135,712 | E4AA2BE8F8019237…861A01B7A |
| mud_forest（同上） | diff | 952,076 | 6B874EF298DD0667…5CD099EB |

许可：全部 Poly Haven **CC0 1.0**。注意：`api.polyhaven.com/assets/<id>` 元数据端点对部分
候选 404（forest_ground_04 等），但 `files/<id>` 端点正常——下载与校验不受影响。
落选候选只下载了 diffuse（短名单陪跑）或三件套（fl02/03/04），均未入库。

## 2. 同机位对比方法

`tests/tool_capture_ground_compare.gd`（新工具，committed）：加载 `l_ravine_board.tscn`，
两个**固定机位**（ground 近景 pos (3.50,0.50,3.20)→(6.00,0.08,-0.80) fov40；
scene = `tool_capture_art09_board.gd` 的 ravine_env_creek 同参），
逐变体换 `Ground.material_override` 渲帧。候选材质参数与生成器一致
（uv 15x17→后改、roughness、ARM 通道），**候选不加 tint**（选型看贴图本色，调色是接入旋钮）。
产物：`Art/Probes/ground_tex_compare/gtex_{ground,scene}_{baseline,fl02,fl03,fl04,lgrass}.png`
（baseline = ART10 后的 forest_floor+tint 现状）。
两次运行日志：`.capture_logs/tool_capture_ground_compare_20261102_{154621,155526}.log`，exit 0、全帧 OK。

## 3. vision 判读（串行，间隔 ≥15 s）

**展板锚点**（先问展板原图"游戏内场景"的地表）：偏暖棕大地色与鲜活苔绿交织、苔藓密覆、
泥土碎石小径、落叶零星不成地毯、湿润、明度较高、斑驳光影。

场景内逐候选（ground 近景，同问法）：

| 变体 | 分 | 摘要 |
|---|---|---|
| baseline（forest_floor+tint） | 3/10 | 冷灰绿、地毯化、平如瓷砖、无湿润感 |
| forest_leaves_02 | 4/10 | 黄褐灰绿、平铺重复+接缝、干瘪、苔藓稀疏 |
| forest_leaves_03 | 2/10 | 冷暗灰褐、落叶铺满高度重复、无苔藓 |
| forest_leaves_04 | 3/10 | 暖干秋棕、枝蔓 UV 拉伸、无苔藓 |
| leafy_grass | 4/10 | 灰冷带粉紫、网格状平铺、草底盘突兀（注：无 tint+侧逆光下） |

**贴图单独看**（9 宫格 `preview_sheet.png`，短名单筛选）：forest_leaves_02 **9**、
leafy_grass **8**、forest_leaves_04 6、forest_ground_06 5、forest_ground_05/mud_forest 4、
forest_leaves_03/forest_ground_04 3、leaves_forest_ground 2。
→ 短名单 forest_leaves_02 + leafy_grass（补测 leafy_grass 三件套同机位重跑）。

scene 机位（整体融合）：fl02 6/10（冷灰蓝、缺暖棕苔绿、岸板接缝）、lgrass 6/10（冷青反光过强、
但湿润氛围达标）。

**终审（2×2 并排 `gtex_side_by_side.png`）**：选 **leafy_grass**。核心理由：
①内容契合"苔藓密覆、落叶零星"比例（fl02 落叶主导、干燥秋叶性格）；②小尺度碎屑平铺隐蔽好
（fl02 大叶片在俯视/远景下图案化拼接刺眼）；③侧逆光下微层次能出苔藓立体感与湿润感；
④与 3D 草丛融合最佳（可当草根过渡层）。调色建议：粉/紫灰往暖棕拉、提亮绿相、稍加对比。

（过程坑：vision 一次 413（并排图 >8MB → 缩半重建）、一次 503（服务暂不可用，45 s 后重试成功）；
9 宫格与并排图由 `Tools/make_tex_preview_sheet.ps1` / `make_gtex_side_by_side.ps1` 本地拼板。）

## 4. 接入与回归

- `tool_make_ravine_board.gd`：新增 `TEX_GROUND_*`（leafy_grass）；`_add_ground` 换用，
  初版 tint (0.82,0.88,0.74) / uv 15x17 / rough 0.96。重建 `l_ravine_board.tscn`
  （`TOOL|Ground|material=leafy_grass...`、save OK、exit 0）。
- 契约：`run_art09_frame_contract` **48/48 PASS**（断言为通用 `albedo_texture!=null and normal_enabled`，
  不锁贴图名）。
- 工作副本入库：`Game/Reborn/assets/environment/tex/leafy_grass_{diff,nor_gl,arm}_1k.jpg`
  （+ .import），登记 THIRD_PARTY_ASSETS §9.1；临时比对目录 `tex_candidates/` 已删除。

## 5. 取证与第 1 轮修正

初版取证（`Art/Probes/art11_ground_after/`，`tool_capture_art09_board -- ravine`，CaptureRun 屏幕外）：
tp 判读 **6/10**——色调方向找准，但"高反光像水面、平铺重复强、中心过曝"（过曝为 ART10 已知遗留）。

第 1 轮有依据修正：roughness 0.96→**1.0**、uv 15x17→**24x26**。重建+重拍后 tp 判读 **7.5/10**：
"反光显著减轻、平铺重复大幅减弱、已像长有苔藓的泥地；中景强光过曝仍略削弱写实感"。
far 机位复判：帧有效非黑（完整场景内容），远景平地仍可观察到**轻度**平铺重复与拼接痕迹。

## 6. 遗留与移交

| 项 | 状态 | 说明 |
|---|---|---|
| 中景/中心强光过曝 | ART10 已知（两轮修正已用尽） | 非贴图问题 |
| far 机位平地轻度平铺感 | 遗留 | 需 triplanar/多材质混合或顶点色渐变，超出本轮 |
| 草根接触阴影缺失 | 归 C 阶段/另案 | ART10 已列 |
| 庭院关地面仍是程序化 | 未动 | B 授权范围是展板关；庭院是否换同款由负责人定 |
| `forest_floor` 三件套去留 | 待负责人 | 已无使用点，仍在库 |

## 7. 工具链副产物（零可见窗口验证，负责人二次反馈）

`CaptureRun.ps1` 新增 `-Headless` 开关（GUI exe + `--headless` + Start-Process 重定向 = 零窗口），
**禁止再用 console 版 exe**（会弹黑色终端）。验证（`Tools/verify_no_window.ps1`，2026-11-02 16:08）：
- headless 回归 12 次轮询采样 **0 个窗口句柄**，48/48 PASS；
- 非 headless 截图渲染窗口存在（标题 `Reborn (DEBUG)`，`--position -2400,-2400` 屏幕外不可见），
  4 帧全部产出，vision 复判非黑有效。
