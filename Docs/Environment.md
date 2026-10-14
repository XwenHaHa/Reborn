# 环境与工具能力门

检查日期：2026-10-12（T001 执行）；**2026-10-13 引擎切换复核（Godot 4）**。本文件区分三类陈述：**已验证事实**（本机实际执行过，附证据）、**未验证**（有文件但未运行）、**缺失**（已系统排查且未发现）。文档生成不计入能力通过。

证据全文见 `Docs/Evidence/T001.md`、`Docs/Evidence/T004.md`；命令见 `Docs/Commands.md`。

> ## ⚠ 引擎变更：UE5 → Godot 4（2026-10-13，负责人决定）
>
> 原定 UE5 蓝图路线**已废止**。新路线为 **Godot 4.7.2 + GDScript**。
> 理由：轻量、免费开源、无需 Epic Games Launcher、可从官方渠道获取独立编辑器、更适合先验证普通电脑能否流畅开发。
>
> **关键后果：P0 能力链原先最大的阻塞消失了。** UE5 阶段卡在"agent 无法创建/编辑编辑器资产（`.uasset`/`.umap` 是二进制，必须有编辑器）"；Godot 的 `project.godot`/`.tscn`/`.tres`/`.gd` **全是纯文本**，agent 可直接编写，配合 `--headless` 命令行即构成完整闭环。详见 `Docs/Evidence/T004.md`。
>
> 下方 UE 内容保留作为历史记录与对比依据，**不再是当前路线**。

## 已验证事实

### Godot 4（2026-10-13 实测，当前引擎）

- 可执行文件（负责人已自行下载）：
  - `E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`（172.5 MB，GUI）
  - `E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（0.2 MB，**命令行自动化用这个**）
  - 注意：外层的 `Godot_v4.7.2-stable_win64.exe` 是**目录**不是文件，易误判为"解压失败"。
- 版本实测：`4.7.2.stable.official.ed1daf0bf`，退出码 0。
- **无头 CLI 闭环实测通过**（退出码 0）：`--headless`、`-s/--script`、`--check-only`、`--quit-after`、`--import`、`--export-release/debug/pack` 全部存在。
- agent **纯文本手写** `project.godot` + `main.tscn` + `main.gd`，未经编辑器即被引擎解析运行。
- 脚本创建 3D 物理体并**回读真实碰撞尺寸**：`CharacterBody3D` + `CapsuleShape3D` 半径 16.0 cm / 总高 48.0 cm。
- `--check-only` 经对照验证为**可信静态门**：它真实抓到了我写出的 GDScript 语法错误并返回退出码 1。

### 硬件与系统

- 机型 Dell Precision 3561；CPU Intel Core i7-11800H（16 逻辑处理器）；内存 **31.75 GB**。
- GPU：NVIDIA T600 Laptop GPU（4 GB，驱动 32.0.15.7344）、Intel UHD Graphics（2 GB）。
- 操作系统 Windows 10 专业版 build 19045。
- 磁盘：C: **11.8 GB 可用**/238.1 GB；D: 159.5 GB；E: 227.6 GB；M: 3035.9 GB（**网络盘** `\\szhmx.com\file`，非本机）。
- **C: 空间紧张**，工程与产物应落 D:/E:。Godot 体积小（172.5 MB），压力远小于 UE。

### 项目与版本工具

- 项目根目录 `E:/Reborn` 存在。**已是 Git 仓库**，已推送 `main` 到公开远端 `github.com/XwenHaHa/Reborn`（commit `e564cc8`）。
- Node **v22.18.0**；npm 10.9.3；Git **2.42.0**；**Git LFS 3.4.0**；Python **3.13.1**。
- Visual Studio Community 2022 17.12.1 存在；**Windows SDK 未安装**（Godot + GDScript **不需要**）。
- **网络**：直连 `github.com:443` 失败；须经本机 clash-verge 代理 `127.0.0.1:7897`。

### Blender（能力已实测）

- `D:\SoftWare\Blender\blender.exe`，实测 **3.3.1**，内置 Python 3.10.2。
- 无头 CLI 通过：`--background --factory-startup --python <脚本>`，退出码 0。
- 单位 METRIC / `scale_length=1.0` / METERS；出厂 `Cube` 实测 **2.000000 m**。
- API 存在：`export_scene.fbx`、`import_scene.fbx`、`wm.save_as_mainfile`、`bpy.data.armatures`。
- **Godot 导入建议用 glTF 而非 FBX**（Godot 对 FBX 支持较弱），T005 步骤需相应改写。
- **glTF 导出实测通过（T005）**：`bpy.ops.export_scene.gltf` 可用；kwargs 签名必须从
  `bpy.ops.export_scene.gltf.get_rna_type().properties` 读——`bpy.types.EXPORT_SCENE_OT_gltf.bl_rna` 只有 14 个基础键，会把参数误判为不支持。
- **1 m 往返实测（T005）**：Blender 1.000000 m → Godot `AABB.size = (1.000000, 1.000000, 1.000000)`；
  轴向实测映射 `(x, y, z) → (x, z, −y)`（即 Blender 的 −Y 前 → Godot 的 +Z）。详见 `Docs/Evidence/T005.md`。
- **骨骼/动画往返实测（T006）**：`export_skins`/`export_animations`/`export_force_sampling` 均被 Blender 3.3.1 接受；
  导出器写**绝对时间 `frame/fps`**（所以动作要从帧 0 开始，否则文件时间范围不在 0 起点）；
  Godot 导入按 `animation/fps`（默认 30）**重采样并丢部分键** ⇒ 源里的极值会被削掉约 1–2%（实测 30°→29.53°）。
  详见 `Docs/Evidence/T006.md`。

### 视觉工具（**已可用**，2026-10-13）

- `E:\claude-vision-skill\vision.js` **实测可用**（退出码 0）。
- **可信性已验证**：对已知答案探针图 `Art/Probes/vision_probe_red_blue.png`（左红右蓝）提问，
  答对（"红色，蓝色"）。**先验证工具、再用工具下结论。**
- 配置（只记键名与非密值，**key 不记录**）：`E:\claude-vision-skill\.env`
  含 `DASHSCOPE_BASE_URL`、`DASHSCOPE_API_KEY`、`VISION_MODEL`、`VISION_MAX_TOKENS`。
  - `DASHSCOPE_BASE_URL` **必须带 `/v1`**（实测：`POST /chat/completions` → 404；
    `POST /v1/chat/completions` → 200）。
  - 原配置（opencode.ai 网关 + `mimo-v2.5`）实测 403 订阅失效，已备份为
    `.env.bak_before_reborn`。该目录 `.gitignore` 含 `.env`，凭据**不入任何仓库**。
- **首次使用即发现真实渲染缺陷**（场景无光源/无环境/相机未激活），见
  `Docs/Evidence/Visual-Verification.md`。

### Agent 自动化工具

- 可用：shell(`pwsh`)、文件读写与搜索、网络取用、subagent/workflow 编排。
- DSH 具备 MCP 客户端能力（`dsh-mcp-client`），但 `settings.yaml` 与 `workspace.json` **无任何 MCP 配置**，项目侧 `.mcp.json` 等**均不存在**。
- **对 Godot 而言这不构成阻塞**：纯文本 + 命令行已足够，不需要编辑器 MCP。

## 缺失（系统排查后未发现）

### Godot 导出模板 —— **已解除（2026-10-13）**

`%APPDATA%\Godot\export_templates\4.7.2.stable\` 已安装（负责人于编辑器内 `编辑器 → 管理导出模板` 安装）：

```
windows_debug_x86_64.exe           98.4 MB
windows_debug_x86_64_console.exe    0.2 MB
windows_release_x86_64.exe        104.2 MB
windows_release_x86_64_console.exe  0.2 MB
```

- 目录名与引擎版本前两段一致（`4.7.2.stable`），这是引擎定位模板的依据。
- 只装单平台时**不会**生成 `version.txt`；实测无影响。
- 未装 mono（C#）模板：本项目用 GDScript。
- 结果：T007 导出通过。见 `Docs/Evidence/T007.md`。

### Unreal Engine（历史记录，当前路线不使用）

13 类证据源全部否定：`Get-Command`、注册表 Epic 键（6 处）、Epic 启动器清单、`LauncherInstalled.dat`、机器级与每用户卸载注册表、`.uproject` 关联（3 处）、开始菜单、App Paths、候选安装根浅扫、`D:\SoftWare` 等列举、卷类型确认，以及 **C:/D:/E: 三卷确定性遍历共 484,201 个目录，0 命中**。

**未采信的证据（已作废）**：Windows Search 索引查询曾返回 0 命中，但对照实验证明本机索引**只覆盖 C: 的部分目录**（按名查确知存在的 `D:\SoftWare\Blender\blender.exe` 也为 0 命中），故该结果**不构成证据**。

## 能力矩阵

| 能力 | 当前状态 | 通过证据 |
|---|---|---|
| Godot 版本与路径 | **通过** | 4.7.2.stable 实测，退出码 0 |
| Godot 无头脚本执行 | **通过** | `--headless --path` 退出码 0，PROBE 键值输出 |
| agent 纯文本创建工程/场景/脚本 | **通过** | 手写 `project.godot`+`.tscn`+`.gd` 被引擎解析运行 |
| GDScript 静态语法检查 | **通过** | `--check-only` 抓到真实语法错误并返回 1 |
| 3D 物理体与碰撞创建/回读 | **通过** | `CharacterBody3D`+`CapsuleShape3D` 回读 16.0/48.0 cm |
| 场景运行与结果读回 | **通过** | `--quit-after` 限额下正常退出并输出 |
| Windows 导出/打包 | **通过** | 两个预设导出退出码 0；产物存在（exe 109,127,680 B + pck） |
| 打包版实际启动 | **通过**（含 1 项 awaiting-review） | 独立程序创建窗口、响应、`CloseMainWindow` 后退出码 0；**真实按键输入**未验证 |
| Blender 启动与版本 | **通过** | 3.3.1 实测，退出码 0 |
| Blender 无头脚本执行 | **通过** | `--background --python` 实测，PROBE 键值输出 |
| Blender-MCP | **未指定/不存在** | 无 MCP 配置；但 Blender CLI 已可独立验证 |
| MCP 保存、导出 | **未验证** | 依赖未确定的 MCP 实现；Blender CLI 侧 API 已确认存在 |
| Godot 导入 Blender 资产 | **通过** | T005 静态：1.0000 m 往返（50/50）；**T006 骨骼**：65/65 ×3 + 包内 65/65，长度 1.0 s、LOOP_LINEAR、无根运动（`Docs/Evidence/T005.md`、`T006.md`） |
| 物种配置与身体（Cat/Mouse） | **通过** | T008：**102/102** ×2（逐字段对照 `Parameters.md`、配置驱动的台阶物理实测、无物种名分支静态检查）；包内 91/91（静态检查如实标 N/A） |
| 台阶自实现组件 `StepClimb` | **通过** | 探针 **6/6**（组件抽取后行为不变）；T008 用**配置驱动**复测：猫 12 cm 上/20 cm 挡、鼠 3 cm 上/12 cm 挡 |
| 视觉/录屏 | **通过** | vision.js 实测可用；已知答案图答对；已用于发现并修复渲染缺陷 |
| Git/LFS/备份 | **通过** | LFS 生效；从零克隆后引擎实跑 18/18 |
| 硬件与磁盘余量 | **通过** | CPU/GPU/RAM/磁盘已采集 |

## 阶段门现状

**P0 完成**：E01 部分通过（视觉已补验）、**打包通过**（T007）、**E02 通过**（T005）、**E03 通过**（T006）；
四类能力门（无头闭环 / 打包 / 视觉 / 资产往返）全部有实测证据。

**P1 已开工**：**T008 通过**（物种配置与身体；台阶算法组件化后探针 6/6 不变）→ 下一步 T009（猫移动）/ T010（鼠移动）。

## 阻塞与最小解除条件

| 阻塞 | 影响任务 | 最小解除条件 |
|---|---|---|
| ~~Godot 导出模板未安装~~ | ~~T007~~ | **已解除**（2026-10-13 安装 `4.7.2.stable`） |
| ~~技术层文档仍是 UE5 版~~ | ~~T002 起~~ | **已解除**（文档已重写为 Godot 版） |
| ~~Git LFS 未配置~~ | ~~T003~~ | **已解除**（LFS 生效 + 从零克隆恢复试验通过） |
| ~~台阶 MaxStepHeight 能力未达成~~ | ~~T009/T010~~ | **已解除**（探针 6/6 通过） |
| ~~vision 订阅失效（403）~~ | ~~全部视觉验收~~ | **已解除**（2026-10-13 换用负责人提供的网关并验证） |
| 真实按键输入无安全自动化手段 | T007 的"输入"项、P7 试玩 | 受审查的输入自动化工具（**需授权**），或真人操作录像。**禁止盲发按键**（可能打进用户焦点窗口）；合成输入已由 `run_t007_input.gd` 覆盖 |
| Blender 资产路线未定 | T005/T006 的 Blender 侧 | 指定已确认 MCP 实现并授权；或确认改用 Blender 自带无头 CLI（已实测可用） |
| C: 仅剩 13.7 GB | 产物落盘 | 确认工程与产物落 D:/E: |

## 与 2026-10-12 首次检查的差异

1. 补全了软件**实际版本**（此前只读文件版本、未运行版本命令）。
2. 新增**硬件与磁盘余量**采集（此前明确缺失）。
3. 新增**注册表、卸载项、文件关联、开始菜单、App Paths** 五类 UE 排查，并完成 **C:/D:/E: 三卷确定性遍历（484,201 目录，0 命中）**，把 UE 状态从"不能断言"推进到"未发现"。
4. 实测了 **Blender 无头 CLI**（新通过能力），并发现 `--python-expr` 在本机 PowerShell 下不可用、必须用 `--python <文件>`。
5. 实测了 **vision.js**，发现服务端 403 订阅问题（此前"未运行验证"）。
6. 确认**本会话不存在任何 UE 或 Blender MCP 工具**（此前"用户级 MCP 状态未知"）。
7. 发现**Windows SDK 未安装**。
8. **主动作废了一条自己产出的错误证据**：Windows Search 索引的 0 命中，经对照实验证明该索引在本机不可靠（详见 Commands.md §4.1.1 与 Evidence §4.1.1）。
9. 发现 `M:` 是**网络盘**（`\\szhmx.com\file`）而非本机磁盘。
10. **2026-10-13 引擎切换**：改 Godot 4.7.2；实测纯文本编写 + 无头执行闭环通过，原先"无编辑器自动化"的阻塞消除；新增阻塞仅剩导出模板未安装。
11. **2026-10-13 导出模板安装后**：T007 打包通过（导出、独立运行、干净退出、重启），包内断言 18/18 + 22/22；并把"导出产物拒绝 `--script`"这一官方设计限制记录进 Commands §5.4。

## 运行命令规则

命令事实以 `Docs/Commands.md` 为准，该文件区分 VERIFIED 与 PENDING，不得把 PENDING 写成可执行示例。路径含空格时 PowerShell 用调用运算符 `&`。

**Godot 无头运行一律加 `--quit-after <N>`**：脚本加载失败时 `get_tree().quit()` 不会被调用，进程会挂死（已实测，180 s 超时）。
