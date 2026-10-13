# 开发交接：2026-10-13（T002/T003 完成后）

## 真实状态

**引擎已变更**：原定 UE5 蓝图路线**废止**，改为 **Godot 4.7.2 + GDScript**（负责人 2026-10-13 决定）。

**T001 / T002 / T003 已完成**；技术层文档已全部重写为 Godot 版。

| 任务 | 状态 | 关键证据 |
|---|---|---|
| T001 | **done** | 环境/硬件采集、UE 定位全否定、Godot 4.7.2 无头闭环实测 |
| T002 | **done**（视觉 awaiting-review） | 工程建立；无头断言 **18/18**，10 次运行一致 |
| T003 | **done** | LFS 生效；**从零克隆的工程可被引擎实跑 18/18** |
| T004 | 部分 done | Godot 侧完成；Blender 资产侧未开始 |
| T005 / T006 / T007 | pending | 见阻塞 |

**未完成**：游戏玩法实现、Blender 资产、打包、视觉验收。**T008～T063 全部 pending。**

## 现有产物

```
Game/Reborn/                       正式 Godot 工程（纯文本，agent 可直接编写）
├── project.godot                  InputMap 10 动作、4 碰撞层、forward_plus
├── autoload/world_director.gd     世界时间单例
├── scenes/core/main.tscn          主入口
├── scenes/maps/l_movement_lab.tscn  10×10m 地面、PlayerStart、Player、Camera3D、100cm 标尺
├── scripts/characters/player_greybox.gd  临时灰盒玩家（T009 替换）
└── tests/run_t002.gd              无头断言，退出码 0/1 可判定
```

**验收命令**（改完脚本先 `--check-only`）：
```powershell
& 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path 'E:\Reborn\Game\Reborn' --script 'res://tests/run_t002.gd' --quit-after 1200
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
- 硬件：i7-11800H / 31.75 GB / T600 Laptop 4GB / Win10 19045；C: 仅剩 11.8 GB。

## 下一步（按建议优先级）

1. **台阶能力探针（建议先做）** —— Godot `CharacterBody3D` **没有** UE `MaxStepHeight` 的等价物。
   猫需上 12 cm、鼠需上 3 cm，且低于阈值才抬升、高于则被挡。这是 **P1 最高技术风险**，
   先小成本验证，避免 T009/T010 卡死。
2. **T008** 最小物种配置与身体（前置已满足）。动手前先写 `Docs/Tasks/T008.md` 规格。
3. **T005** 静态资产往返 —— 需先定 Blender 路线（**建议用自带无头 CLI**，已实测可用）。
4. **T007** 打包 —— 需先装导出模板。

## 待负责人处理

| 事项 | 说明 |
|---|---|
| **安装 Godot 导出模板** | `%APPDATA%\Godot\export_templates\` 为空。编辑器内 `编辑器 → 管理导出模板 → 下载并安装`（约 1 GB）。解锁 T007 |
| **确认 Blender 路线** | 指定 MCP 实现并授权，**或**确认改用 Blender 3.3.1 自带无头 CLI（建议） |
| **恢复 vision 订阅** | 否则 T002 视觉部分与 T005/T006 外观验收永远无法通过 |
| 确认脚本语言 | 默认 GDScript（无需额外工具链）。改 C# 需追加 .NET 配置 |

## 本次边界声明

未安装/卸载任何软件；未连接 MCP；未改全局配置；未删除源资产。
`Tools/Probes/GodotProbe/` 是**能力探针**，不是游戏工程。
T003 恢复试验目录 `E:\Reborn-RecoveryTest`（工作区之外）已在验证后删除。
Git 提交与推送**经负责人授权**执行；历史重写用 `--force-with-lease`（先确认远端无他人提交）。

## 可直接发给下一个 agent

> 请在 E:/Reborn 工作。先读 AGENTS.md、Docs/Handoff.md、Docs/Environment.md、Docs/Evidence/T002.md、Docs/Evidence/T003.md、Docs/TechnicalDesign.md。
> **引擎是 Godot 4.7.2 / GDScript**，不是 UE5（UE5 路线已废止，技术层文档已全部重写）。
> 工程在 `Game/Reborn/`，纯文本可直接编辑。工具：`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`。
> 改完脚本**先跑 `--check-only`**，再跑 `--headless ... --quit-after N`（**不加 `--quit-after` 会挂死**）。
> Godot 用**米**，Parameters.md 是**厘米**，需 ÷100。`CapsuleShape3D.height` 是含半球的总高。
> 现有验收脚本 `res://tests/run_t002.gd`（18 断言，退出码可判定）可作为后续任务的模板。
> 已知阻塞：导出模板未安装（T007）；vision 403（视觉验收不得编造）；Blender 路线未定（T005/T006）。
> 建议下一个动作：**台阶（MaxStepHeight）能力探针**，这是 P1 最高技术风险。
> 不要在没有实测证据时把任何游戏任务标为 done；不要因无头断言通过就宣称画面正确。

