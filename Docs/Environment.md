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

### 视觉工具（可运行，服务端拒绝）

- `E:\claude-vision-skill\vision.js` 能启动并发请求，但两次实测均 **退出码 1**：`API 403 ... An active OpenCode Go subscription is required to use Go models.`
- **当前无法产出任何画面判断**，视觉类验收全部 NOT-RUN。
- 已知答案探针图 `Art/Probes/vision_probe_red_blue.png` 已备好，恢复后先自检。

### Agent 自动化工具

- 可用：shell(`pwsh`)、文件读写与搜索、网络取用、subagent/workflow 编排。
- DSH 具备 MCP 客户端能力（`dsh-mcp-client`），但 `settings.yaml` 与 `workspace.json` **无任何 MCP 配置**，项目侧 `.mcp.json` 等**均不存在**。
- **对 Godot 而言这不构成阻塞**：纯文本 + 命令行已足够，不需要编辑器 MCP。

## 缺失（系统排查后未发现）

### Godot 导出模板（当前阻塞 T007）

- `%APPDATA%\Godot\export_templates\` **目录存在但为空**。导出 Windows exe 需要 `4.7.2.stable` 模板（约 1 GB）。
- 实测 `--export-release` 退出码 1，报错为缺 `export_presets.cfg`（可手写）**且**缺模板（必须下载）。
- **最小解除条件**：安装与引擎版本匹配的导出模板。属"下载第三方内容"，需负责人授权或自行安装（编辑器内 `编辑器 → 管理导出模板 → 下载并安装`，一次点击）。

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
| Windows 导出/打包 | **未验证（阻塞）** | 缺 `export_presets.cfg`（可写）+ **缺导出模板（须下载）** |
| 打包版实际启动 | **未验证（阻塞）** | 依赖上一条 |
| Blender 启动与版本 | **通过** | 3.3.1 实测，退出码 0 |
| Blender 无头脚本执行 | **通过** | `--background --python` 实测，PROBE 键值输出 |
| Blender-MCP | **未指定/不存在** | 无 MCP 配置；但 Blender CLI 已可独立验证 |
| MCP 保存、导出 | **未验证** | 依赖未确定的 MCP 实现；Blender CLI 侧 API 已确认存在 |
| Godot 导入 Blender 资产 | **未验证** | 需 T005 实测（建议 glTF） |
| 视觉/录屏 | **可运行但被服务端拒绝** | vision.js 实测 403（订阅缺失） |
| Git/LFS/备份 | 仓库已建立，**LFS 未验收** | 已推送；`.gitattributes` 与 LFS 追踪未配置 |
| 硬件与磁盘余量 | **通过** | CPU/GPU/RAM/磁盘已采集 |

## 阶段门现状

**P0 未通过**：E01（原为"新建测试蓝图"，须改写为 Godot 等价用例）**未执行**；E02（资产往返）未执行；E03（骨骼）未执行；打包未通过。

但**与 UE5 阶段相比，P0 的性质变了**：从"缺少必要的编辑器自动化能力、无法开始"变为"自动化能力已齐备，只缺导出模板，且尚未创建正式工程"。

## 阻塞与最小解除条件

| 阻塞 | 影响任务 | 最小解除条件 |
|---|---|---|
| Godot 导出模板未安装 | T007、打包版启动验收 | 安装 `4.7.2.stable` 导出模板（约 1 GB，需授权或自行安装） |
| 技术层文档与任务规格仍是 UE5 版 | T002 起全部任务 | 授权按 `Docs/Evidence/T004.md` §4.3 的映射表重写 |
| Git LFS 未配置 | T003、未来大二进制资产 | 建立 `.gitattributes` 与 LFS 追踪，并做恢复试验 |
| vision 订阅失效（OpenCode Go 403） | 全部视觉验收 | 恢复订阅或改配可用的 `DASHSCOPE_BASE_URL` + `VISION_MODEL` |
| C: 仅剩 11.8 GB | 产物落盘 | 确认工程与产物落 D:/E: |

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

## 运行命令规则

命令事实以 `Docs/Commands.md` 为准，该文件区分 VERIFIED 与 PENDING，不得把 PENDING 写成可执行示例。路径含空格时 PowerShell 用调用运算符 `&`。

**Godot 无头运行一律加 `--quit-after <N>`**：脚本加载失败时 `get_tree().quit()` 不会被调用，进程会挂死（已实测，180 s 超时）。
