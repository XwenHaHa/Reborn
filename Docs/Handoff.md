# 开发交接：2026-10-13（T007 打包通过后）

## 真实状态

**引擎已变更**：原定 UE5 蓝图路线**废止**，改为 **Godot 4.7.2 + GDScript**（负责人 2026-10-13 决定）。

**T001 / T002 / T003 / T007 已完成**；台阶能力探针达成；技术层文档已全部重写为 Godot 版。

| 任务 | 状态 | 关键证据 |
|---|---|---|
| T001 | **done** | 环境/硬件采集、UE 定位全否定、Godot 4.7.2 无头闭环实测 |
| T002 | **done**（视觉 awaiting-review） | 工程建立；无头断言 **18/18**，10 次运行一致 |
| T003 | **done** | LFS 生效；**从零克隆的工程可被引擎实跑 18/18** |
| T004 | 部分 done | Godot 侧完成；Blender 资产侧未开始 |
| T005 / T006 | pending | 见阻塞（Blender 路线未定） |
| T007 | **done**（真实按键/画面 awaiting-review） | 导出、独立运行、干净退出、重启均通过；包内断言 18/18 + 22/22 |
| 台阶探针 | **done** | 6/6 通过，5 次运行一致 |

**未完成**：游戏玩法实现（P1 起）、Blender 资产、真实输入验证、视觉验收。**T008～T063 全部 pending。**

**P0 阶段门**：E01 部分通过、打包通过；**E02（资产往返）/ E03（骨骼）未执行** → P0 尚未完成。

## 现有产物

```
Game/Reborn/                       正式 Godot 工程（纯文本，agent 可直接编写）
├── project.godot                  InputMap 10 动作、4 碰撞层、forward_plus
├── export_presets.cfg             两个预设：Windows Desktop（发布）/ SelfTest（含测试）
├── autoload/world_director.gd     世界时间单例
├── scenes/core/main.tscn          主入口
├── scenes/maps/l_movement_lab.tscn  10×10m 地面、PlayerStart、Player、Camera3D、100cm 标尺
├── scripts/characters/player_greybox.gd  临时灰盒玩家（T009 替换）
└── tests/
    ├── run_t002.gd                场景/出生/碰撞断言（18 条）
    ├── run_t007_input.gd          输入链路断言（22 条）
    ├── probe_step_height.gd       台阶能力探针（6 条判定）
    └── debug_stepup.gd            台阶逐条件诊断工具

Builds/P0-Win64/                   导出产物（.gitignore 已排除）
├── Reborn.exe / Reborn.pck / Reborn.console.exe
└── RebornSelfTest.exe / .pck / .console.exe
```

**验收命令**（改完脚本先 `--check-only`）：
```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'

# 工程内断言
& $g --headless --path 'E:\Reborn\Game\Reborn' --script 'res://tests/run_t002.gd' --quit-after 1200
& $g --headless --path 'E:\Reborn\Game\Reborn' --script 'res://tests/run_t007_input.gd' --quit-after 20000

# 包内断言（必须用编辑器二进制，导出产物拒绝 --script）
& $g --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
    --script 'res://tests/run_t002.gd' --quit-after 1200
```
退出码 0 = 通过。**必须加 `--quit-after`**，否则脚本出错会挂死。

## 关键环境事实

- **Godot**：`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
  （**外层同名项是目录不是文件**）；版本 `4.7.2.stable.official.ed1daf0bf`。
- **单位**：Godot 用**米**，`Parameters.md` 是**厘米** → **÷100**。
  `CapsuleShape3D.height` 是**含两端半球的总高**（Cat：`radius=0.16, height=0.48`）。
- **键码**：手写 `project.godot` 要写裸数字，**必须实测核对**（Esc=4194305、Shift=4194325、Ctrl=4194326）。
- **Git 推送**必须走代理 `127.0.0.1:7897`（直连 github.com 超时），**未写入全局配置**。
- **视觉工具不可用**：`vision.js` 实测 403 → 所有画面判断保持 NOT-RUN。
  已存待分析截图：`Art/Probes/vision_probe_red_blue.png`（已知答案自检图）、
  `Art/Probes/t007_release_window.png`（T007 导出程序窗口）。
- **导出产物拒绝 `--script` 与位置参数**（官方模板编译时带 `disable_path_overrides=yes`，是 Godot 有意设计）。
  想在包内跑断言只能用 `--main-pack` + 编辑器二进制。
- **`debug/export_console_wrapper` 是枚举**：`No=0 / Debug Only=1 / Debug and Release=2`；写 `1` 时 release 不出 `.console.exe`。
- 硬件：i7-11800H / 31.75 GB / T600 Laptop 4GB / Win10 19045；C: 仅剩 13.7 GB。

## 下一步（按建议优先级）

1. **T008 最小物种配置与身体**：前置早已满足。动手前先写 `Docs/Tasks/T008.md` 规格。
   建议把 `SpeciesConfig.max_step_height` 与已验证的台阶算法一起接入。
2. **台阶算法组件化**：把 `tests/probe_step_height.gd` 里验证过的算法移到
   `scripts/characters/step_climb.gd`，T009 直接调用（现在它还躺在 `tests/` 里）。
3. **T005 静态资产往返**：需先定 Blender 路线（**建议用自带无头 CLI**，已实测可用）。
4. **T006 骨骼往返**：依赖 T005。

## 待负责人处理

| 事项 | 说明 |
|---|---|
| ~~安装 Godot 导出模板~~ | **已完成**（2026-10-13），T007 已通过 |
| **确认 Blender 路线** | 指定 MCP 实现并授权，**或**确认改用 Blender 3.3.1 自带无头 CLI（建议） |
| **恢复 vision 订阅** | 否则 T002 画面项、T007 画面项、T005/T006 外观验收都无法完成。恢复后先用两张待分析截图补验 |
| 确认脚本语言 | 默认 GDScript（无需额外工具链）。改 C# 需追加 .NET 配置 |
| 真实按键输入验证方式 | 需受审查的输入自动化工具（需授权），或真人操作录像。**不要盲发按键** |

## 本次边界声明

- **未安装/卸载任何软件**（导出模板由**负责人本人在编辑器内**安装）。
- 未连接 MCP；未改 git 全局配置；未删除源资产。
- **执行了导出与启动程序**：这是 T007 的验收要求，产物写在项目内 `Builds/`（已 gitignore）。
  启动游戏会创建窗口并**捕获鼠标**（`Input.MOUSE_MODE_CAPTURED`，按 ESC 可释放）——执行时已留意。
- 试验目录 `E:\Reborn-RecoveryTest`（工作区之外）与 `Art/Probes/godot_docs/`（API 文档，1036 文件）已在验证后删除。
- Git 提交与推送**经负责人授权**执行；历史重写用 `--force-with-lease`（先确认远端无他人提交）。

## 可直接发给下一个 agent

> 请在 E:/Reborn 工作。先读 AGENTS.md、Docs/Handoff.md、Docs/Environment.md、Docs/Evidence/T007.md、Docs/TechnicalDesign.md。
> **引擎是 Godot 4.7.2 / GDScript**，不是 UE5（UE5 路线已废止，技术层文档已全部重写）。
> 工程在 `Game/Reborn/`，纯文本可直接编辑。工具：`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（**外层同名项是目录不是文件**）。
> 改完脚本**先跑 `--check-only`**，再跑 `--headless ... --quit-after N`（**不加 `--quit-after` 会挂死**）。
> Godot 用**米**，Parameters.md 是**厘米**，需 ÷100。`CapsuleShape3D.height` 是含半球的总高。
> 现有验收脚本可作模板：`tests/run_t002.gd`（18 条）、`tests/run_t007_input.gd`（22 条）、`tests/probe_step_height.gd`（6 条判定）。
> 打包：`export_presets.cfg` 有两个预设；**导出产物拒绝 `--script`**，包内断言要用 `--main-pack` + 编辑器二进制。
> 已知阻塞：vision 403（**视觉验收不得编造**）；Blender 路线未定（T005/T006）；真实按键输入无安全自动化手段。
> 建议下一个动作：**T008 最小物种配置与身体** + 把台阶算法组件化到 `scripts/characters/step_climb.gd`。
> 不要在没有实测证据时把任何游戏任务标为 done；不要因无头断言通过就宣称画面正确。

