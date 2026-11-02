# ART07 证据：庭院环境构图 / 接触感 / 背光可读性试作

执行日期：2026-10-28（本机系统时钟）  
状态：**awaiting-review**，不是 `done`，不是正式美术 `approved`。  
工程：`E:/Reborn`，Godot 4.7.2，Windows / Forward+。

## 1. 变更范围

只复用仓库现有资产，无下载、购买或上传。庭院生成器新增确定性视觉装饰：16 株背景草簇、6 块溪心石、3 块庭院石、5 处泥舌半岛及对应草团；31 个无碰撞接地阴影。草风 shader 增加叶根明暗与确定性实例明暗差。环境关闭此前造成全屏灰幕的指数雾，启用 SSAO 与 ACES tone mapping；溪缝附近的 `CreekRock05` 后移。

修改路径：
- `Game/Reborn/tests/tool_make_courtyard.gd`
- `Game/Reborn/shaders/grass_wind.gdshader`
- `Game/Reborn/scenes/maps/l_courtyard.tscn`（生成器产物）
- `Game/Reborn/tests/run_t011_greybox.gd`
- `Game/Reborn/tests/tool_capture_render.gd`（仅庭院截图隔离）

未改正式猫鼠资产、玩法/AI、区域/鼠洞/溪缝尺寸、碰撞体、cover volumes、导航层契约或 T031。导航 `.tres` 与提交前一致。

## 2. 关键参数

| 项目 | 旧值 | 当前值 | 说明 |
|---|---:|---:|---|
| Exponential fog | enabled / density 0.008 | disabled | density 0.003 仍被判整屏灰雾；关闭后 overview 判读确认均匀雾幕消失 |
| 备选 depth fog | 无 | begin 80 m / end 170 m / sky affect 0 | 当前保留参数但关闭；开启时视觉仍有灰化反馈，需负责人决定是否接受 |
| `SkyFill.light_energy` | 0.45 | 0.62 | 抬升背光可读性，不投影 |
| SSAO | disabled | enabled, radius 1.20, intensity 2.60 | 只影响渲染，不改几何 |
| Tone mapper | 原默认 | ACES | 渲染表现参数 |
| `GROUND_SHADOW_ALPHA_K` | 1.7 | 3.2 | 31 个阴影片仍未被视觉判读稳定识别为自然接触阴影 |
| `CreekRock05` | (-33.2, 12.4) | (-24.5, 19.3) | 离溪缝轴更远，避免固定机位视觉遮挡 |
| Mud peninsula top | 0.152 m | 0.1405 m | 减薄岸边视觉板，仍高于水面 top 0.13 m |

地面 shader、水体尺寸/水位/BoxMesh、Ground、四区域边界、鼠洞、溪缝、StaticBody 与导航源清单均保持契约值。

## 3. 生成与回归

所有 Godot 命令均使用 `--quit-after`。实际执行结果：

| 检查 | 结果 |
|---|---|
| `tool_make_courtyard.gd --check-only` | exit 0 |
| `tool_make_courtyard.gd` 生成与自检 | exit 0；全部 `VERIFY|...|OK`；静态体 20；装饰节点无碰撞/不进导航组；`decor_clear_of_creek_gap_mouth|OK`；当前装饰自检 229/229 PASS |
| `tool_make_courtyard_nav.gd` | exit 0；nav source 20；鼠 mesh 228 polygons，猫 mesh 180 polygons；nav 资源无 diff |
| `run_t011_greybox.gd` | exit 0；229/229，0 failures |
| `run_t012_navigation.gd` | exit 0；79/79，0 failures |
| `run_t020_perception.gd` | exit 0；164/164，0 failures |
| `run_t026_cover.gd` | exit 0；96/96，0 failures |
| `run_t027_ecology.gd` | exit 0；96/96，0 failures |

相关日志未发现 `SCRIPT ERROR`。本轮未运行 T010/T013 和打包版回归；环境表现层变化未改这些系统，但不将未运行项记为通过。`tool_make_courtyard_nav.gd` 输出的 voxel 尺寸精度 WARNING 是既有 Godot 导航烘焙提示，退出码 0 且导航指标/回归通过。

## 4. 非 headless 取证

已运行窗口取证工具：
- `tool_capture_render.gd -- t011`
- `tool_capture_creek.gd -- creek`

`Art/Probes/art07_after/` 保留 11 张 PNG，包含 7 个庭院固定机位和 creek wide/low 两组双帧。水面动态差：wide `mean_abs_diff=0.02264`、变化像素 27.66%；low `0.00686`、变化像素 8.79%。

最后一轮重拍命令在主 agent 会话中超过 240 秒未完成；因此下面视觉判读针对工作区现存的 11 张 `art07_after` 图，不声称这次超时调用新生成了图片。最后一轮工作区的场景、生成器、nav 与截图目录时间点一致，但无法证明所有 11 张均是在最后一次 shader 微调后重拍；此项保留为限制。

## 5. 当前视觉判读

使用项目指定 `node E:/claude-vision-skill/vision.js <png> <中文问题>`，判读实际截图：

- `t011_map_overview.png`：均匀灰雾滤镜已消失，场景地标清楚；vision 仍称背景层弱，整体像悬浮在灰色空间的沙盘，纵深仅部分成立。
- `t011_courtyard.png`：无雾幕，但地面仍偏平；草丛/石头接地阴影不足，模型仍有贴纸/漂浮观感。
- `t011_grass_danger.png`：近大远小略有改善，但背景区分仍弱；草团仍像纸片草，危险区色块和路线表达不清。
- `t011_creek_gap_lane.png`：中央通道清晰，装饰未封住鼠路线；vision 同时指出左侧靠水高草有遮蔽侧边移动体的可能，固定机位不代表实际鼠视角完全无遮挡。
- `creek_low_a.png`：水面清楚、泥舌边缘较不规则、无明显深度排序错误；接地和岸线融合总体优于宽景判读，但岸边仍像视觉板。
- 之前 `roots_hole_lane` 认为洞口清楚且无明显悬空；`roots_barrier_oblique` 认为背光根障可读，但根与横梁接缝存在生硬穿插。由于最后一轮截图工具超时，这两张并非最后一轮重拍后的新证据。
- `courtyard_shelter` 旧图仍指出棚柱接地/AO弱、硬阴影和局部结构交界生硬；最后一轮没有可靠的新判读。

## 6. 用例结论

| 用例 | 判定 | 依据 |
|---|---|---|
| A1 生成器 | PASS | 229 条生成器自检、save OK |
| A2 碰撞/几何不变量 | PASS | T011 229/229；20 个 StaticBody 名称集合相同 |
| A3 导航 | PASS | T012 79/79；鼠猫双导航图指标与 T012 相同；nav `.tres` 无 diff |
| A4 移动/感知/掩体/生态 | PASS（限定回归） | T020/T026/T027 共 356 条全绿；未运行项见 §3 |
| A5 前中后景与空气透视 | **部分通过 / awaiting-review** | 雾幕移除，overview 地标可辨；背景纵深仍弱，草地机位无足够空气透视差 |
| A6 地标/路线可读 | **部分通过 / awaiting-review** | 溪缝机位通过；其他关键场景未在最后一轮重新判读，不能泛化为全通过 |
| A7 无漂浮/穿插 | **FAIL** | courtyard/grass 判读仍认为部分草和石像贴纸；根障接缝/棚柱 AO 也未完全解决 |
| A8 仍是庭院试作 | PASS | 未新增资产、未声称完成森林/P6 |
| A9 日志 | PASS（已运行命令） | 相关运行日志未发现 `SCRIPT ERROR` |

**总体状态：awaiting-review**。数值/玩法回归通过不代表视觉目标完成，ART07 不得标 done 或 approved。

## 7. 未验证与阻塞

- 最新视觉截图命令在主 agent 会话中超时；最终 shader/参数状态的完整同机位新截图未成功确认。应在有足够窗口时间时重新运行非 headless 两个 capture 工具，再逐图判读。
- P6 正式资产与正式森林环境不在本任务授权范围内；ART03 资产仍未负责人批准。
- 若要继续改善纵深，应由负责人决定是否接受 `FOG_MODE_DEPTH` begin/end 参数，或保持无雾、通过新增授权资产/背景几何建立真实景深。
- 接地感目前靠 shader 根部明暗、SSAO 与地面阴影板仍不足以达到目标；继续堆半透明阴影片会增加“贴片感”，不建议在无新诊断时重复调参。
- `T031` 仍是后续首个 P4 任务，本次环境视觉试作结束后回到 T031。

## 8. 恢复入口

- 任务规格记录每个变化的旧值和理由；关键值位于 `tool_make_courtyard.gd` 的 ART07 常量/`_add_light_and_env` 与 `grass_wind.gdshader` 的 ART07 根部明暗逻辑。
- 庭院场景由 `tool_make_courtyard.gd` 重建；重建后必须立即运行 `tool_make_courtyard_nav.gd` 恢复导航节点/分组，再运行 T011/T012 回归。
- 不要使用 `git reset`、`git clean` 或覆盖未跟踪文件。保留 `visual-options.html`、`task_plan.md`、`findings.md`、`progress.md`。

本任务未提交、未推送；因 A5/A7 视觉门未全部通过且最后一轮捕获超时，不能创建“完成”提交。

---

## 9. 收口轮证据（2026-11-02，负责人授权审阅收口）

### 9.1 审阅与回归

五个未提交改动的逐项审阅结论（问题→方案→可回退性全部成立，无死路）：

| 文件 | 改动解决什么 | 与 ART10 冲突? | 可回退 |
|---|---|---|---|
| `tool_make_courtyard.gd`（+539/-4） | 构图装饰五件套（31 接地阴影/16 背景草簇/6 溪中石/3 庭院石/5 泥舌半岛）+ SSAO/ACES/HDRI 天空/关雾/补光 0.62 | 无文件重叠；语义正向（shader 共用见下行） | 纯文本常量，按 §2 表回退后重跑生成器 |
| `grass_wind.gdshader`（+17/-1） | 草根部压暗 45% + 逐实例明暗差 ±0.09（解决"贴纸感"） | **共用 shader**：ART10 展板关同用它；两关都不设 `height_ref`（同用默认 0.88），行为一致、属正向（展板关草也获得接地 AO）；`run_art09_frame_contract` 48/48 复跑通过 | 单文件 revert |
| `run_t011_greybox.gd`（+137） | 新增 §G 装饰断言集（静态体 20 锁 / 装饰零碰撞不进导航组 / 阴影贴地 / 缝口净空 / 环境防回归锁） | 无 | 独立测试段 |
| `tool_capture_render.gd`（+45） | t011 取景前隔离 lab（可视物/环境/灯），消除"测试靶场"误读 | 无（ART10 用的是另一个 capture 工具） | 独立函数 |
| `l_courtyard.tscn` | 生成器产物 | — | 由生成器重建 |

本轮微修：`env.fog_mode = Environment.FOG_MODE_DEPTH` 重复两行 → 一行（同值，无行为差异）；随后**重新生成 + 重烤导航**，`resources/nav/*.tres` 无 diff。

回归（全部 2026-11-02 重跑，退出码 0，0 条 `SCRIPT ERROR`）：
生成器自检全 `VERIFY|...|OK`、T011 **229/229**、T012 **79/79**、T010 **95/95**、T013 **73/73**、
T020 **164/164**、T026 **96/96**、T027 **96/96**、T030 **111/111**、`run_art09_frame_contract` **48/48**。

### 9.2 "取证超时"根因 + 完整重拍（解除 §4/§7 的限制）

上一轮 240 s+ 超时的根因**不是渲染慢**：Godot 的 `print()` 写入"读端已死"的管道会阻塞主线程；
前台命令超时被移入后台时管道断裂，工具就停在某个 view 永远不存图（本轮 14:45 复现：卡在
`t011_map_overview`；改为后台运行+输出落文件后 15:17 全部完成）。

2026-11-02 完整重拍（`Art/Probes/art07_after/` 11 帧全部刷新，时间戳 15:17/15:19）：
`tool_capture_render.gd -- t011` 7 帧 + `tool_capture_creek.gd -- creek` 4 帧，全部 `save_result=OK`。
水面动态差复测：wide `mean_abs_diff=0.0329`（27.66%→28.14% 像素变化）、low `0.0095`（8.79%→9.44%）。

vision 复判（6 个关键机位，`node E:/claude-vision-skill/vision.js`）：

| 机位 | 判读摘要 |
|---|---|
| t011_map_overview | 三层**能分辨**（暗调 HDRI 森林 vs 亮场地对比拉开）、灰雾感减轻；但沙盘感仍在（场地切边生硬、地面受光均匀）、墙脚草带**仍点状散落** |
| t011_courtyard | 草根部压暗"锚定"有效、**仍像插片**（面片草+分布均匀+地面无细节）；棚平台读作"木纹卡片"无厚度；水边缘黑线生硬 |
| t011_grass_danger | 草有体积感改善+**逐实例明暗差确认存在**；危险区标记 0.10 "完全不抢戏"（新隐患：过于隐蔽）；最刺眼=地表贴图糊脏与植被割裂 |
| t011_roots_barrier_oblique | 背光面**死黑已解决**（横梁结构/树皮纹理可读）；但补光过匀失体积感、接缝硬穿插、接触阴影缺 |
| t011_creek_gap_lane | 缝口清晰可见、**无石头/草封堵**（几何断言+判读双确认）；视觉上草岸边缘有"缩口感"（仅观感，非物理） |
| creek_wide | 水岸**仍读出矩形**、泥舌"仍像悬空板（稍掩饰）"、溪中石"摆在灰板上不像泡在水里" |

### 9.3 收口结论（awaiting-review 提交）

| 用例 | 上轮 | 本轮 |
|---|---|---|
| A1–A4, A8, A9 | PASS | **PASS**（回归全绿，含 T010/T013/T030 补跑） |
| A5 层次 | 部分通过 | **部分通过**（灰幕消失+三层可辨；缺光影纵深/空气透视差/草带未成带） |
| A6 地标 | 部分通过 | **部分通过**（溪缝 PASS；洞口机位 vision 判读与上轮相反"被树桩遮挡"，固定机位判读反复，**需负责人人工复核**） |
| A7 无漂浮/穿插 | FAIL | **FAIL**（草插片感、棚柱/屏障接地与接缝、水岸硬切、泥舌板感、树桩底部悬浮） |

**未过项的已知根因与后续路线**（均超出"复用现有资产"边界）：
- 地表细节（"糊脏迷彩"）→ B 阶段地表贴图选型（forest_leaves 候选）；
- 草插片感 → C 阶段草透光/次表面 + 分布团簇化（需 shader 与布置改进）；
- 水岸硬切/泥舌板感 → 需湿泥过渡材质与岸线破形（shader 大改或新资产）；
- 棚/屏障接地 → 需接触阴影机制（SDFGI/contact shadow 实测）或资产改造。

### 9.4 工具链副产物

"窗口不弹前台 + print 不挂死"已固化为统一包装 `Tools/CaptureRun.ps1`（见 `Tools/README.md`），
2026-11-02 15:28 用 creek 工具实测验证（窗口 (-2400,-2400) 屏幕外、截图非黑、vision 可判读）。

**补记（2026-11-02 二次反馈）——console 版 exe 是隐藏的弹窗来源**：
渲染窗口已挪到屏幕外后负责人仍看到窗口弹出，根因是部分调用走了
`Godot_v4.7.2-stable_win64_console.exe`——**控制台版即使参数全对、`--headless` 也照样在桌面
弹一个黑色终端窗口**。修正：包装新增 `-Headless` 开关，headless 调用也统一走 GUI 版
`Godot_v4.7.2-stable_win64.exe`（日志由 `Start-Process -RedirectStandardOutput/-RedirectStandardError`
在调用层取得，与 exe 类型无关）。**取证/实跑一律不要用 console 版 exe。**
零窗口验证（`Tools/verify_no_window.ps1`，16:08）：连续 2 次运行并轮询 Godot 进程
`MainWindowHandle`——headless 回归 12 次采样 **0 个窗口句柄**（48/48 PASS）；非 headless 截图
的渲染窗口存在但始终在屏幕外，4 帧产出、非黑、vision 复判通过。详见
`Docs/Evidence/ART11_GROUND_TEXTURE.md` §7 与 `Tools/README.md`。