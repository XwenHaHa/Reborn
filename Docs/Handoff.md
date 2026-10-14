# 开发交接：2026-10-13（T012 完成 —— **P1 进行中**）

## 真实状态

**引擎**：Godot 4.7.2 + GDScript（UE5 路线已废止）。

**T001 / T002 / T003 / T004（路线决策）/ T005 / T006 / T007 / T008 / T009 / T010 / T011 / T012 全部完成**；台阶与导航能力已落地；技术层文档为 Godot 版。

| 任务 | 状态 | 关键证据 |
|---|---|---|
| T001 | **done** | 环境/硬件采集、UE 定位全否定、Godot 无头闭环实测 |
| T002 | **done** | 无头断言 18/18 ×3；**视觉已补验通过**（修复了场景无光源缺陷） |
| T003 | **done** | LFS 生效；从零克隆的工程可被引擎实跑 18/18 |
| T004 | **done** | **资产路线已定：Blender 3.3.1 自带无头 CLI，不用 MCP** |
| T005 | **done（2026-10-13）** | 1 m 资产往返 = **1.0000 m**；断言 50/50 ×3 + 包内 50/50；运行中碰撞 1.0001 m；视觉已留证 |
| T006 | **done（2026-10-13）** | 骨骼往返 65/65 ×3 + 包内 65/65；长度 1.0 s、`LOOP_LINEAR`、首末闭合 0.000；无根运动/无根骨缩放；两帧视觉留证 |
| T007 | **done**（真实按键 awaiting-review） | 导出/运行/退出/重启/视觉均通过；包内断言 18/18 + 22/22 |
| T008 | **done（2026-10-13）** | 台阶组件化 + `SpeciesConfig`/`AnimalBody`；**配置驱动的物理台阶实测**；**114/114** ×2、包内 103/103 |
| T009 | **done（2026-10-13）** | 猫移动（走/跑/蹲/跳 + 第一人称相机）；斜坡・低顶・落地・相机穿墙全过；**81/81** ×3 + 包内 81/81；lab 玩家换成正式猫，T002/T005/T006/T007/T008 回归全绿；过程中修掉 `step_climb` 两处判据缺陷 |
| T010 | **done（2026-10-13）** | 鼠移动与通道尺度：**站立**过 24×30 cm 洞（胶囊 0.18 不变、0 空中帧）、**猫站立与蹲姿都过不去**、禁高跳、0.15 m 低顶下不扩碰撞；**95/95** ×3 + 包内 95/95；**gameplay 代码零改动**（差异全在 `mouse.tres`）→ 说明 T009 的抽象没漏东西 |
| T011 | **done（2026-10-13）** | 生态灰盒 `l_courtyard.tscn`：四区域**恰好铺满** 72×56 可玩矩形；策划 §8.2 五条结构全部落地并用**两种物种真实胶囊**验证（猫跳越 0.50 屏障、鼠穿 0.24×0.30 洞、猫在洞/溪缝前被挡、鼠穿溪缝）；四条出生点→补给走廊 0 阻挡；**210/210** ×3 + 包内 210/210；**gameplay 代码零改动**；视觉 7 帧 |
| T012 | **done（2026-10-13）** | 导航可行性：**分物种双导航图 + 分层**（鼠 layer1 r=0.07 / 猫 layer2 r=0.17、cell 0.03）；鼠层穿 0.24 洞 9.00 m、穿溪缝 12.00 m；猫层同一对端点 **35.44 m 且不穿洞**、**洞里没有猫的导航面**；真实胶囊行走（鼠进洞 236 帧 0 重叠；猫 900 帧 **0 帧进入洞口走廊**）；**79/79** ×3 + 包内 79/79；**视觉证据 NOT-RUN**（运行时导航调试绘制不可见）；**gameplay 代码零改动** |
| 台阶能力 | **done（已组件化）** | 探针 6/6；组件 `scripts/characters/step_climb.gd`；T009 期间修正"落点高度"与"斜坡误判为台阶"两处判据（`Docs/Evidence/T009.md` §5） |

**未完成**：游戏玩法实现（T013 起：捕猎 / 双物种策略 / 轮回 / 存档）、正式角色与骨骼资产（P6）、真实按键输入验证。**T013～T063 全部 pending。**

**P0 阶段门完成**：E01 部分通过（视觉已补验）、打包通过（T007）、**E02 通过**（T005）、**E03 通过**（T006）。
**P1 进行中：T008 + T009 + T010 + T011 + T012 通过**（配置与身体、猫移动与相机、鼠移动与通道尺度、生态灰盒、**导航可行性**）→ 下一步 **T013 调试入口与移动回归**。

> ## ⚠ 本次最重要的教训
>
> **数值断言全过 ≠ 画面正确。** T002 的 18 条断言长期全绿，但场景**没有光源、没有环境、
> 相机未激活**，导出程序窗口是深色空白。视觉工具一接入就发现了。
> 完整经过见 `Docs/Evidence/Visual-Verification.md`。今后"画面正确"必须有视觉证据。

## 现有产物

```
Game/Reborn/                       正式 Godot 工程（纯文本，agent 可直接编写）
├── project.godot                  InputMap 10 动作、4 碰撞层、forward_plus
├── export_presets.cfg             两个预设：Windows Desktop（发布）/ SelfTest（含测试）
├── autoload/world_director.gd     世界时间单例
├── scenes/core/main.tscn          主入口
├── scenes/maps/l_movement_lab.tscn  10×10m 地面、PlayerStart、**Player（= 猫 AnimalBody 实例，T009 换的）**、
│                                    100cm 标尺、**ProbeAsset（T005 资产：1 m 立方体 + BoxShape3D 碰撞）**
├── scenes/maps/l_move_fixtures.tscn  **移动试验世界（25° 坡道 / 猫低顶 42 cm / 墙角 / 50 cm 高台 / T010 加：鼠洞 24×30 cm、鼠低顶 15 cm）**
├── scenes/maps/l_courtyard.tscn       **生态灰盒关卡（T011：80×80 m、四区域、树根屏障 + 鼠洞、溪边缝隙、补给点）**
├── scripts/characters/step_climb.gd      **台阶抬升组件（自实现 MaxStepHeight；T009 修正两处判据）**
├── scripts/characters/animal_body.gd     **身体与移动控制器：成型/走跑蹲跳/相机（配置驱动，无物种名分支）**
├── scripts/data/species_config.gd        **物种配置类（字段按 TechnicalDesign §3）**
├── resources/species/cat.tres / mouse.tres  **物种数据真源（改数值只改这里）**
├── scenes/characters/animal_body.tscn    **身体场景（胶囊 + 灰盒 BodyMesh + 相机；不设 current，由 `make_camera_current` 决定）**
├── assets/tests/sm_probe_cube.glb / sk_rig_probe.glb + .import   资产与导入设置（.import 纯文本）
└── tests/
    ├── run_t002.gd                场景/出生/碰撞断言（18 条）
    ├── run_t005_asset.gd          静态资产往返断言（50 条）
    ├── run_t006_rig.gd            骨骼往返断言（65 条）
    ├── run_t008_species.gd        **物种配置/身体/台阶能力断言（114 条）**
    ├── run_t009_cat_movement.gd   **T009 猫移动与相机断言（81 条：速度/潜伏/斜坡/墙角/跳跃）**
    ├── run_t010_mouse_movement.gd  **T010 鼠移动与通道尺度断言（95 条：三档速度/窄缝/低顶/禁高跳）**
    ├── run_t011_greybox.gd        **T011 生态灰盒断言（210 条：四区域/补给走廊/§8.2 五条结构 + 6 组物理探针）**
    ├── run_t012_navigation.gd     **T012 导航可行性断言（79 条：双图参数/分层路径矩阵/结构判据 + 4 组真实胶囊行走）**
    ├── run_t007_input.gd          输入链路断言（22 条；现在跑在正式猫控制器上）
    ├── probe_step_height.gd       台阶能力探针（6 条判定；**现调用 StepClimb 组件**）
    ├── debug_stepup.gd            台阶逐条件诊断工具
    ├── tool_edit_lab_scene.gd     场景修补工具（不入树 + 无意外变更自检）
    ├── tool_add_probe_asset.gd    把探针资产接入 lab（幂等 + 自检）
    ├── tool_make_move_fixtures.gd **T009 生成移动试验世界（幂等 + 重载核对几何）**
    ├── tool_set_lab_player.gd     **T009 把 lab 的灰盒玩家换成正式猫（幂等 + 无意外变更自检）**
    ├── tool_make_courtyard.gd     **T011 生成生态灰盒关卡（幂等 + 重载核对几何 + 走廊自检）**
    ├── tool_dump_scene_tree.gd    dump 任意 PackedScene 真实结构（含骨骼/动画/蒙皮）
    └── tool_capture_render.gd     引擎侧渲染捕获 + 像素统计（不能 headless；`-- t005` / `-- t006` / `-- t009` / `-- t010` / `-- t011` / `-- t012`）

Art/Blender/Tests/StaticProbe_v001.blend   T005 可编辑源（LFS；**逐字节不可复现**）
Art/Exports/Tests/SM_ProbeCube.glb         T005 导出产物（LFS，sha256 629750364847…，**可复现**）
Art/Blender/Tests/RigProbe_v001.blend      T006 骨骼源（LFS，467,364 B）
Art/Exports/Tests/SK_RigProbe.glb          T006 导出产物（LFS，sha256 446bf3b67c90…）
Tools/Blender/t005_static_probe.py / t006_rig_probe.py   Blender 无头脚本（建模/重开校验/导出/GLB 自检）
Art/Probes/t005_lab_probe_render.png       正交对照帧（T005 视觉证据，LFS）
Art/Probes/t006_rig_t000.png / t050.png    骨骼两帧位姿（T006 视觉证据，LFS）

Builds/P0-Win64/                   导出产物（.gitignore 已排除；**T012 后已重新导出并复验，SelfTest.pck 327,196 B**）
├── Reborn.exe / Reborn.pck / Reborn.console.exe
└── RebornSelfTest.exe / .pck / .console.exe
```

**验收命令**（改完脚本先 `--check-only`）：
```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'

# 工程内断言
& $g --headless --path $proj --script 'res://tests/run_t002.gd' --quit-after 1200
& $g --headless --path $proj --script 'res://tests/run_t005_asset.gd' --quit-after 20000
& $g --headless --path $proj --script 'res://tests/run_t006_rig.gd' --quit-after 20000
& $g --headless --path $proj --script 'res://tests/run_t008_species.gd' --quit-after 20000
& $g --headless --path $proj --script 'res://tests/run_t007_input.gd' --quit-after 20000
& $g --headless --path $proj --script 'res://tests/probe_step_height.gd' --quit-after 20000

# 包内断言（必须用编辑器二进制，导出产物拒绝 --script）
& $g --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
    --script 'res://tests/run_t008_species.gd' --quit-after 20000

# 看导入资产的真实结构（骨骼/动画/蒙皮也能 dump）
& $g --headless --path $proj --script 'res://tests/tool_dump_scene_tree.gd' --quit-after 600 `
    -- 'res://assets/tests/sk_rig_probe.glb'

# 视觉（**不能 headless**；`-- t005` 正交对照，`-- t006` 骨骼两帧）
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 1200 -- t006
```
退出码 0 = 通过。**必须加 `--quit-after`**，否则脚本出错会挂死。

## 关键环境事实

- **Godot**：`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
  （**外层同名项是目录不是文件**）；版本 `4.7.2.stable.official.ed1daf0bf`。
- **单位**：Godot 用**米**，`Parameters.md` 是**厘米** → **÷100**。
  `CapsuleShape3D.height` 是**含两端半球的总高**（Cat：`radius=0.16, height=0.48`）。
- **键码**：手写 `project.godot` 要写裸数字，**必须实测核对**（Esc=4194305、Shift=4194325、Ctrl=4194326）。
- **Git 推送**必须走代理 `127.0.0.1:7897`（直连 github.com 超时），**未写入全局配置**。
- **视觉工具可用**：`E:\claude-vision-skill\vision.js`（先用已知答案图 `Art/Probes/vision_probe_red_blue.png` 自检）。
  已用于 T002/T005/T006/T007 的视觉验收；**遇到工具侧报错（如 max_tokens 截断）要如实记录并重试，不得编造画面判断**。
- **导出产物拒绝 `--script` 与位置参数**（官方模板编译时带 `disable_path_overrides=yes`，是 Godot 有意设计）。
  想在包内跑断言只能用 `--main-pack` + 编辑器二进制。
- **`debug/export_console_wrapper` 是枚举**：`No=0 / Debug Only=1 / Debug and Release=2`；写 `1` 时 release 不出 `.console.exe`。
- 硬件：i7-11800H / 31.75 GB / T600 Laptop 4GB / Win10 19045；C: 仅剩 13.7 GB。
- **Play 不能靠返回值判断**：Godot 4.7 的 `AnimationPlayer.play()` 返回 **void**（不是 `Error`）→ 查 `is_playing()` / `current_animation`。
- **动画轨道插值 API**：`Animation.rotation_track_interpolate(track, t)`（**没有**通用的 `track_interpolate`）；
  同族还有 `position_/scale_/blend_shape_/value_/bezier_track_interpolate`。
- **骨骼姿态含静止位姿**：`Skeleton3D.get_bone_pose_rotation()` 返回**含 rest 的**父骨相对旋转
  （实测 t=0 时腿骨就是 −90° = rest），"作者转了多少度"要**从动画轨道数据**算，别直接读姿态角。
- **导入会重采样动画**：按 `animation/fps`（默认 30）重采样并**丢掉部分键**（实测 t=0.5 不是键）→ 源里的极值被削约 1–2%。
- **`.blend` 不可逐字节复现**（Blender 写时间/会话元数据）；**`.glb` 可复现**（两次 SHA256 相同）→ 验收以 `.glb` 为准。
- **新增/修改 `class_name` 脚本后必须先 `--import`**：全局类名缓存在 `.godot/global_script_class_cache.cfg`，
  否则引用方报 `Parse Error: Identifier "Xxx" not declared in the current scope`（2026-10-13 实测踩到）。
- **`AnimalBody` / `SpeciesConfig` / `StepClimb` 已就位（T008/T009）**：物种差异**只在** `resources/species/*.tres`；
  系统代码里不写物种名分支（有静态断言守着）。
- **相机偏移语义（T009 决策 D1）**：`camera_offset_z` 按 **本地 +Y（竖直）** 实现 —— 依据是 `Parameters.md`
  源自 UE 参数表（UE 里 Z 是上方向），第一人称眼高必须竖直；字段名沿契约不变，断言锁死轴向。
- **新增参数（T009 决策 D2）**：`crouch_half_height`（猫 0.15 / 鼠 0.06）—— `Parameters.md` 原本没有蹲姿尺寸，
  **待负责人并入正式起测值**。
- **`StepClimb` 两处判据在 T009 被实测推翻并修正**（详见 `Docs/Evidence/T009.md` §5）：
  ① 落点高度必须来自**接触面**（用 `get_travel()` 会因"形状越小停得越早"把鼠的 3 cm 台阶算成 3.26 cm 而拒绝）；
  ② **斜坡不算台阶**（只按"真正阻挡本次运动的接触面是否可站立"判；`n·dir<0` 这一条不能省，否则连正常台阶都上不去）。
- **包内跑不了源码级静态检查**：`.pck` 里只有编译产物，读不到 `.gd` → 相关检查在包内如实标
  `STATIC|NOT-APPLICABLE`（不假装通过、也不误判为失败）。
- **实例子节点的属性覆盖不会被 `PackedScene.pack()` 序列化**（T009 实测）：改子节点 `Camera3D.current`
  存盘文件里**没有这行**，重载回来相机不 current（视觉捕获会黑屏）；要在场景里表达，就用**节点自己的导出属性**。
- **新关卡尺度常量（T010）**：鼠洞 **0.24 × 0.30 m**、鼠低顶净空 **0.15 m**（属**试验世界设计**，不是物种参数；
  记在 `Docs/Parameters.md`）。改 `tool_make_move_fixtures.gd` 的常量时 T010 的尺度断言会一起失败。
  **`0.15 m` 待负责人确认为关卡设计基线。**
- **视觉判读的取景前提（T010 实测）**：相机要**正对**主体所在通道，否则洞口侧壁会把主体完全遮住、
  模型只会答"洞里是空的"（详见 `Docs/Commands.md` §8 与 `Docs/Evidence/T010.md` §5.1）。

## 下一步（按建议优先级）
1. **T013（调试入口与移动回归）**（P1，2～4h，前置 T009～T012）：测试切换两种玩家、显示碰撞与路径、记录移动参数与问题视频；
   带上两条遗留项：**单级台阶抬升会水平前移 0.2 m**（`Docs/Evidence/T009.md` §5.3）与
   **猫跨 0.50 屏障在导航层不可达**（`Docs/Evidence/T012.md` §9；是否加 `NavigationLink3D` 由负责人定）。
   **先写 `Docs/Tasks/T013.md`**。
2. ~~T008 / T009 / T010 / T011 / T012~~ **已完成**；正式角色/骨骼资产仍属 **P6** 阶段门，不得提前。

## 待负责人处理

| 事项 | 说明 |
|---|---|
| **Git 提交** | 已获授权并执行：**每完成一个任务提交一次**（T005~T009 分 4 个提交：`562fba4`/`0a7442b`/`bcc65be`/`44eb062`，提交策略 `965120a`，T010 → `8140d6f`，T011 → `1f71f46`）；当前 `main` 比 `origin/main` **ahead 8，未推送** |
| **Git 推送 / 发布** | 仍需确认。推送要经本机代理 `127.0.0.1:7897`（`Docs/Commands.md` §4.1），推送前先确认远端无他人提交 |
| 是否发布新构建 | `Builds/P0-Win64/` 已按 T012 改动**重新导出并再复验**（SelfTest.pck **327,196 B**；包内 T008 103/103、T009 81/81、T010 95/95、T011 210/210、T012 79/79）；是否对外发布请确认 |
| 真实按键输入验证方式 | 需受审查的输入自动化工具（**需授权**），或真人操作录像。**不要盲发按键** |
| 相机轴语义 D1 / 蹲姿高度 D2 | 见上方"关键事实"：D1 已按竖直偏移实现并断言锁定；D2 需并入 `Parameters.md` 正式起测值 |
| 50 cm 高台的跳跃余量 | 净空 0.5502 m vs 台高 0.50 m（端到端实跳已通过，窗口窄）；是否提高 `JumpZVelocity` 由负责人定 |
| 确认脚本语言 | 默认 GDScript（无需额外工具链）。改 C# 需追加 .NET 配置 |
| Godot 渲染器 | **Forward+ 已确认可渲染**（T009 捕获工具实测 `renderer=forward_plus`、1280×720 出图正常）；**帧率未测** |

## 本次边界声明（T012）

- **未安装/卸载任何软件**；未连接 MCP；未改 git 全局配置；**未删除任何源资产**。
- **已按任务提交 Git**（…T010 → `8140d6f`；T011 → `1f71f46`）；T012 按"每任务一次"**单独提交一次**（哈希由下一次交接回填）；
  **未推送**（推送需另行授权）。
- 运行过的受限程序：Godot **非 headless** 渲染捕获（创建窗口并短暂捕获鼠标，工具立即放开）。
- **未做真实按键注入**（禁止盲发按键）；输入验证仍是合成输入。
- 临时诊断脚本全部写在 `$env:PI_SCRATCH_DIR`，**没有落入工程**。
- 新增的 `.tres` / `.tscn` / `.gd` 都不走 LFS（保持纯文本可 diff）；视觉 PNG 走 LFS。

## 可直接发给下一个 agent

> 请在 E:/Reborn 工作。先读 AGENTS.md、Docs/Handoff.md、Docs/Environment.md、Docs/Evidence/T011.md、Docs/Evidence/T010.md、Docs/Evidence/T009.md、Docs/Evidence/T008.md、Docs/Tasks.md、Docs/BlenderPipeline.md。
> **引擎是 Godot 4.7.2 / GDScript**，不是 UE5（UE5 路线已废止）。工程在 `Game/Reborn/`，纯文本可直接编辑。
> 工具：`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（**外层同名项是目录不是文件**）；
> Blender：`D:\SoftWare\Blender\blender.exe`（3.3.1，`--background --factory-startup --python <脚本>`）。
> 改完脚本**先跑 `--check-only`**，再跑 `--headless ... --quit-after N`（**不加 `--quit-after` 会挂死**）；
> **新增/修改 `class_name` 脚本后先跑一次 `--import`**（否则引用方报 "Identifier not declared"）。
> Godot 用**米**，Parameters.md 是**厘米**，需 ÷100。`CapsuleShape3D.height` 是含半球的总高。
> **验收脚本模板**：`run_t002.gd`(18)、`run_t005_asset.gd`(50)、`run_t006_rig.gd`(65)、`run_t008_species.gd`(114)、`run_t009_cat_movement.gd`(81)、`run_t010_mouse_movement.gd`(95)、`run_t011_greybox.gd`(210)、`run_t012_navigation.gd`(79)、`run_t007_input.gd`(22)、`probe_step_height.gd`(6)。
> **资产链已打通**：Blender → `.glb` → Godot（T005 静态 / T006 骨骼）；脚本在 `Tools/Blender/`；
> 结构 dump 用 `tests/tool_dump_scene_tree.gd`（支持骨骼/动画/蒙皮）。
> **资产约定（全部实测）**：轴向 `(x,y,z)_Blender → (x,z,−y)_Godot`——**角色在 Blender 里要面朝 `+Y`**；
> glb 只带视觉、碰撞在 Godot 侧用简单形状建；材质 albedo 是 sRGB；骨骼动画**原地无根运动**；导入削极值 1–2%。
> **数据结构已落地（T008）**：`SpeciesConfig`（`scripts/data/species_config.gd`）+ `resources/species/{cat,mouse}.tres`
> 是**唯一数据真源**；身体 `AnimalBody`（`scenes/characters/animal_body.tscn`）按配置成型；
> **移动已落地（T009）**：同一个 `AnimalBody` 就是控制器（走/跑/蹲/跳/相机），
> 台阶用 `scripts/characters/step_climb.gd`（每帧 `climb.update_base_y()`，移动时 `climb.step_or_slide(motion, dt)`）。
> **关卡**：试验世界 `scenes/maps/l_move_fixtures.tscn`（生成器 `tests/tool_make_move_fixtures.gd`）；
> **生态灰盒 `scenes/maps/l_courtyard.tscn`（T011：80×80 m、四区域 + 树根屏障/鼠洞/溪边缝隙；生成器 `tests/tool_make_courtyard.gd`）**；
> **导航数据（T012）**：`resources/nav/l_courtyard_{mouse,cat}.tres`（**鼠 layer1 / 猫 layer2**，生成器 `tests/tool_make_courtyard_nav.gd`）；
> **视觉捕获**：`tests/tool_capture_render.gd -- t009` / `-- t010` / `-- t011` / `-- t012`（**不能加 `--headless`**，`--quit-after` 给到 30000+；
> **必须检查 `CAP|done` 与每张 `save_result=OK`** —— T011 实测遇到过一次"中途静默退出、退出码却仍是 0"）。
> **不要写物种名分支**：能力差异走配置字段（`can_jump` / `can_pounce` / `can_use_mouse_tunnel`），有静态断言守着。
> 打包：`export_presets.cfg` 两个预设；**导出产物拒绝 `--script`**，包内断言用 `--main-pack` + 编辑器二进制。
> **P0 已完成；P1 进行中（T008 + T009 + T010 + T011 + T012 done）**。下一个动作：**写 `Docs/Tasks/T013.md` 并做调试入口与移动回归**
> （切换两种玩家、显示碰撞与路径；带上**单级台阶前移 0.2 m** 与 **猫跨屏障需跳跃链接**两条遗留项）。
> 已知阻塞：真实按键输入无安全自动化手段（**禁止盲发按键**）。
> 不要在没有实测证据时把任何游戏任务标为 done；不要因无头断言通过就宣称画面正确。

