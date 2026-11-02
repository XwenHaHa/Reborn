 # ART07 任务规格：庭院环境构图 / 接触感 / 背光可读性试作

状态：**awaiting-review（2026-10-28 收尾轮）** —— A1～A4/A6溪缝/A8/A9 通过；A5 仅部分通过、A7 仍部分失败，见证据文档。**不是** done，**不是** approved。
任务身份：**临时视觉任务**（不是总计划正式 T 任务，不是 P6/T053，不声称森林场景或正式美术 approved）
执行日期：2026-10-28（本机系统时钟）
范围授权：负责人已批准「仅复用现有资产的庭院构图 / 接触感试作」；**T031 暂缓**，本轮结束后仍回 T031。

## 1. 目标

只利用现有庭院资产和 Godot 生成器改善猫庭院的前中后景、溪边构图、接触感与背光可读性；不扩展为森林场景或正式 P6 资产。

本轮最终表现层调整：16 株确定性背景草簇、31 个无碰撞接地阴影、6 块溪心石、5 处泥舌半岛、3 块庭院前景石；草风 shader 增加根部明暗和实例差异；环境启用 SSAO 与 ACES，指数雾关闭，保留远景雾参数但不启用。

**不做**：新资产、下载/购买/上传、换模型、改玩法、森林场景、正式 P6、art approved。

## 1. 目标

只利用**现有**庭院资产 + Godot 生成器，改善猫庭院可玩画面：

1. **前景 / 中景 / 背景层次**：现在的庭院是一层平铺（地面 + 3 m 围墙 + 几丛草），中远景没有分离手段。
2. **溪边不规则视觉构图**：水面是 22×9 直带，靠锯齿泥舌遮边，仍能读出矩形。
3. **现有资产接触感**：草丛 / 巨石 / 树桩 / 碎屑贴地但缺少接地阴影，远处读成"贴纸"。
4. **背光可读性**：北墙、根障、棚内的背光面靠一盏 `SkyFill` 兜底，仍偏暗。

**不做**：新资产、下载/购买/上传、换模型、改玩法、森林场景、正式 P6、art approved。

## 2. 前置与证据

- `Docs/Handoff.md`（ART01 / ART03-②④⑥⑦⑫⑬⑭⑮ / ART06 的资产与生成器现状）
- `Docs/Evidence/ART06.md`、`Docs/Evidence/ART03_{CREEK,ROOT_BARRIER,GREYBOX_B}.md`
- `Docs/ART_ASSET_SPEC.md`（资产硬契约：原点在脚底、零碰撞、不进导航组）
- 基线取证（改前）：`Art/Probes/art07_before/`（`tests/tool_capture_render.gd -- t011` 七机位 + `tests/tool_capture_creek.gd -- creek` 双机位）

## 3. 允许改动的真源路径

| 路径 | 改动 |
|---|---|
| `Game/Reborn/tests/tool_make_courtyard.gd` | 唯一庭院生成入口：新增确定性装饰布置（接地阴影、溪中/岸边石、背景草丛簇、泥舌半岛）、环境（fog）与灯光微调 |
| `Game/Reborn/scenes/maps/l_courtyard.tscn` | 生成产物（只由生成器重建，不手改） |
| `Game/Reborn/tests/tool_capture_render.gd` | **仅** t011 分支：先隔离 `l_movement_lab`（T021 已有的隔离规矩），避免 lab 的 1 m 探针立方体/猫落进庭院取景；不改任何断言路径 |
| `Game/Reborn/shaders/{ground,creek_water,grass_wind}.gdshader` | **仅在确有必要时**（本轮预期不动） |

## 4. 参数前值（从生成器实查，改动必须在此登记 old → new）

| 项 | 现值 | 来源 |
|---|---|---|
| 太阳光 | `rotation_degrees=(-50,-30,0)`、`light_energy=1.2`、`shadow_enabled=true` | `_add_light_and_env` |
| 补光 `SkyFill` | `basis=looking_at(0,-0.55,0.85)`、`energy=0.45`、不投影 | 同上 |
| 环境 | `BG_SKY` + `ProceduralSkyMaterial`、`AMBIENT_SOURCE_SKY`；**无 fog、无 DOF** | 同上 |
| 芦苇 | `REED_SPOTS` 13 处（`yaw`/`s` 逐点手工值） | `REED_SPOTS` |
| 草丛掩体视觉 | `COVERS` 3 处 + `CreekReedCoverMesh`（`yaw` 212°/`s` 1.0） | `_mk_cover_bush` |
| 溪岸细节 | `CreekBed` 砾石层 + 22 段锯齿泥舌（`rim_top=0.142`） | `_add_creek_shore` |
| 巨石 | `CreekBoulder` 1 件 @ `(-14, 0.10, 8)`，`yaw=0` | `_mk_boulder` |
| 碎屑 | `CourtyardDebris1..3`（0.6×0.3×0.6 碰撞盒，`sm_boulder_001` scale 0.40/0.46/0.52） | `_mk_rock_debris` |

## 5. 必须守住的不变量（改动后逐条复核）

几何 / 玩法（一律不得变更）：

- `GROUND_SIZE=(80,0.2,80)`、`GROUND_TOP=0.10`
- 四区域边界与面积（Courtyard 560 / Creek 728 / Roots 728 / Grass 2016，合计 4032 = 72×56 m，无重叠无缝隙）
- `HOLE_W=0.24`、`HOLE_H=0.30`、`HOLE_CENTER_X=26.5`、`CAT_JUMP_LANE_X=30.0`
- `BANK_GAP=0.24`、`BANK_WALL_HEIGHT=1.00`、`BANK_GAP_CENTER_X=-31.73`
- `WATER_SIZE=(22,0.03,9)`、`WATER_TOP=0.13`、`water_bodies` 组 1 个成员、水面 `BoxMesh`、零碰撞
- `cover_volumes`：位置 / `COVER_SIZE` / `visibility_factor=0.4`（5 个：3 处草丛 + 溪边 + `CreekReedCover`）
- `StaticBody3D` / `CollisionShape3D` 的**数量与尺寸/位置不得变化**（新增装饰一律无碰撞 `MeshInstance3D` 或纯 `Node3D` + glb 实例）
- `nav_source_courtyard` 组成员不变；导航资源 `resources/nav/l_courtyard_{mouse,cat}.tres` 不得出现 diff
- 出生→补给四条走廊 0 阻挡；洞口 / 溪缝净空；猫跳路线 `x=30` 不被装饰压住
- 参数确定性：新增数据全部是固定数组常量（无 `randf` / 无时间 seed）

## 6. 实施步骤

1. 基线：非 headless `tool_capture_render.gd -- t011`、`tool_capture_creek.gd -- creek` → 存 `Art/Probes/art07_before/`；vision 判读现状问题。
2. 先建可失败的回归：`run_t011_greybox.gd` 追加"装饰不得带碰撞 / 不得进导航组 / 不得压走廊"的断言集（**先在现有关卡上跑一遍确认它验的是真实节点**）。
3. 最小实现（一轮一项，逐项取证）：
   - 接地阴影（`_mk_ground_shadow`）：贴地薄片，暗色半透明，尺寸随物体脚印；
   - 溪道：水中/岸边非碰撞巨石、泥舌半岛、芦苇疏密与尺度重排；
   - 背景层：围墙脚 / 根障后 / 溪岸的草丛簇（缩小尺度，只做远景剪影）；
   - 环境：`fog`（远雾分层）+ `SkyFill`/环境光微调（记录 old → new）。
4. 重新生成 `l_courtyard.tscn`；**只在 nav 数据实际变化时**才跑 `tool_make_courtyard_nav.gd`（生成器会清掉 `NavigationRegion3D`，必须紧接着重烤）。
5. 全量回归（见 §7），日志扫 `SCRIPT ERROR`。
6. 改后同一机位重拍 → `Art/Probes/art07_after/`，vision 逐图判读。
7. 写 `Docs/Evidence/ART07_ENVIRONMENT_COMPOSITION_CONTACT.md`，更新 `Docs/Tasks.md` / `Docs/Handoff.md`，同一提交提交本任务（**不 push**）。

## 7. 用例（验收）

| 用例 | 判据 |
|---|---|
| A1 生成器 | `tool_make_courtyard.gd` 全部 `VERIFY|…|OK`、`save_result=0`、退出码 0 |
| A2 不变量 | `run_t011_greybox.gd` 全绿（含新增装饰断言）；四区域 / 洞 / 缝 / 水面 / 掩体数值原样 |
| A3 导航 | `run_t012_navigation.gd` 全绿；nav `.tres` `git status` 无改动（无改动则不重烤） |
| A4 移动/感知/掩体/生态 | `run_t010`、`run_t013_movement_regression`、`run_t020`、`run_t026`、`run_t027` 全绿 |
| A5 层次 | 改后关键图 vision 判读：前/中/背景可分辨，远景不再与近景同一亮度与对比 |
| A6 地标可读 | 洞 / 溪缝 / 棚屋 / 补给点 / 猫跳车道在图中可辨认，未被新装饰遮挡 |
| A7 无漂浮 / 穿插 | vision + 机位判读：无悬空草丛、无插进水里的干草、无穿墙石、无异常黑面或高光 |
| A8 仍是庭院切片 | 画面读作"庭院一角的写实化试作"，**不**声称森林/正式场景完成 |
| A9 日志干净 | 全部命令日志 0 条 `SCRIPT ERROR` |

## 8. 预期与失败回退

- 预期：层次与接触感提升可被 vision 在**同一机位同分辨率**下指出；数值断言零变化。
- 回退：所有改动集中在 `tool_make_courtyard.gd`（纯文本，`git diff` 可逐行回退）+ 一次重新生成；环境/灯光为 6 个常量级赋值，改回 §4 的前值即可。若 nav 被重烤且出现 diff，`git checkout -- resources/nav/` 恢复到 T012 数据。
- 若 vision 不可用：记 `NOT-VERIFIED`，不写画面结论；状态最多 `awaiting-review`。
- 同一问题最多两次有依据的修复尝试，之后停下来记录。

## 9. 视觉机位与 vision 问题（固定，改前改后同一套）

机位即 `tests/tool_capture_render.gd` 的 `T011_VIEWS`（7 个）与 `tests/tool_capture_creek.gd` 的 `VIEWS`（2 个）。
逐图问 vision：

1. overview：能否分辨前景（近地）/ 中景（棚屋与草团）/ 背景（围墙外天际）三层？有没有漂浮物？
2. courtyard / shelter：棚屋是否坐实在地面、墙脚有无黑缝或漏光？
3. grass_danger：草丛是否像"贴纸"？远处草团是否有大小/朝向差异？
4. roots_hole_lane：洞口可读吗？树桩与屏障是否贴合、有无穿模？
5. roots_barrier_oblique：屏障背光面是否仍是一整片黑？
6. creek_gap_lane：缝是否可读、两岸墙是否挡住视线？
7. creek_wide / creek_low：水边是否还是直线矩形？水里/岸边的石头是否像"放上去的"？

## 10. 收尾轮记录（2026-10-27，本机系统时钟）

（原记录保留，见上）

## 11. 收口轮记录（2026-11-02，负责人授权审阅收口）

负责人 2026-11-02 批准"先 ART07 收口"。本轮动作：

1. **逐项审阅**五个未提交改动 + 两份未跟踪文档（见证据 §9）：全部有明确问题-方案-实测记录，无死路改动；与 ART10 已提交改动**无文件重叠**，唯一语义交互是 `grass_wind.gdshader`（ART10 展板关与庭院共用，两关都不设 `height_ref`、同用默认 0.88，接触 AO 对两关一致生效，属正向交互，`run_art09_frame_contract` 48/48 复跑确认）。
2. **微修一处**：`_add_light_and_env` 里 `env.fog_mode = Environment.FOG_MODE_DEPTH` 重复赋值两行 → 删一行（同值无行为差异），重跑生成器 + nav 烘焙（`resources/nav/*.tres` 无 diff）。
3. **重跑全量回归**（2026-11-02）：生成器自检通过、T011 **229/229**、T012 **79/79**、T010 **95/95**、T013 **73/73**、T020 **164/164**、T026 **96/96**、T027 **96/96**、T030 **111/111**、`run_art09_frame_contract` **48/48**，0 条 `SCRIPT ERROR`。
4. **解决了上一轮的"取证超时"**：根因不是渲染慢，是 Godot `print()` 写入断裂管道会阻塞主线程（前台命令超时转后台时管道断）。用后台运行 + 输出落文件的方式完整重拍 7+4 帧（该经验已固化为 `Tools/CaptureRun.ps1` 统一包装，见 `Tools/README.md`）。
5. **vision 全套复判**（证据 §9.2）：A5 部分通过（三层可辨、灰幕消失、但缺光影纵深、草带点状）；A6 部分通过（溪缝可读无封堵；洞口机位判读反复，需人工复核）；A7 **仍 FAIL**（草仍像插片、棚/屏障接地与接缝、水岸硬切、泥舌仍读作板）。

**收口结论：改动有效但视觉门（A5/A7）未全过 → 以 awaiting-review 状态连同证据一起提交**（负责人 2026-11-02 授权的三种处置中的第二种）。未过项与后续路线见证据 §9.3。
