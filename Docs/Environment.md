# 环境与工具能力门

检查日期：2026-10-12（T001 执行）。本文件区分三类陈述：**已验证事实**（本机实际执行过，附证据）、**未验证**（有文件但未运行）、**缺失**（已系统排查且未发现）。文档生成不计入能力通过。

证据全文见 `Docs/Evidence/T001.md`；命令见 `Docs/Commands.md`。

## 已验证事实

### 项目与版本工具

- 项目根目录 `E:/Reborn` 存在。**当前不是 Git 仓库**（无 `.git`），未发现 UE 工程、游戏代码、Blender 源资产。
- Node `D:\SoftWare\nvm\nodejs\node.exe` = **v22.18.0**（实测 `node --version`）。
- npm 10.9.3；Git `D:\SoftWare\Git\cmd\git.exe` = **2.42.0.windows.2**；**Git LFS 3.4.0 已安装**（`git-lfs.exe` 实测）。
- Python `C:\Python313\python.exe` = **3.13.1**。
- dotnet SDK 9.0.100 存在；`C:\Program Files\dotnet\dotnet.exe` 可用。
- Visual Studio Community 2022 17.12.1 存在；另有 VS 15 生成工具 2017。
- **Windows SDK 未安装**：`C:\Program Files (x86)\Windows Kits\10\Include` 与 `...\10\bin` 均不存在。

### Blender（能力已实测，非仅"文件存在"）

- 可执行文件 `D:\SoftWare\Blender\blender.exe`，**实测版本 3.3.1**（hash b292cfe5a936，2022-10-05 构建）。
- 内置 Python **3.10.2**。
- **无头 CLI 可用**：`--background --factory-startup --python <脚本>` 实测**退出码 0**，11 s 返回。
- 出厂场景实测 `object_count=3`（`Camera|Cube|Light`）；单位 `METRIC`、`scale_length=1.0`、长度单位 `METERS`。
- 出厂 `Cube` 实测尺寸 **2.000000 m**（即 Blender 默认立方体边长 2 m，不是 1 m）——T005 的 1 m 基准必须显式建模。
- API 可用性实测：`export_scene.fbx`、`import_scene.fbx`、`wm.save_as_mainfile`、`bpy.data.armatures` 全部存在。
- 已启用插件含 `io_scene_fbx`（FBX 往返前提）。
- 另有非项目安装：`D:\blender`、`D:\blender-vie`、`E:\blender-view`（内含用户 `.blend`/`.glb` 文件，**不属本项目，不触碰**）；开始菜单快捷方式指向 `D:\SoftWare\blender-launcher.exe`。

### 硬件与余量（已采集）

- 机型 Dell Precision 3561；CPU Intel Core i7-11800H（16 逻辑处理器）。
- 内存 **31.75 GB**。
- GPU：NVIDIA T600 Laptop GPU（4 GB，驱动 32.0.15.7344）、Intel UHD Graphics（2 GB）。
- 操作系统 Windows 10 专业版 build 19045。
- 磁盘余量：C: 11.9 GB 可用 / 238.1 GB；**D: 159.5 GB 可用**；**E: 227.6 GB 可用**；M: 3035.9 GB 可用（网络/其它卷）。
- 注意：**C: 仅剩 11.9 GB**，UE 类安装不应落在 C:。

### 视觉工具（可运行，服务端拒绝）

- `E:\claude-vision-skill\vision.js` 存在且**能启动并发出请求**（实测）。
- 实测返回 **退出码 1**：`API 403 ... An active OpenCode Go subscription is required to use Go models.`
- 结论：**当前无法产出任何画面判断**，视觉类验收全部 NOT-RUN。
- 已知答案探针图已备好：`Art/Probes/vision_probe_red_blue.png`（左右红蓝，已逐像素核对）。

### Agent 自动化工具

- 本会话可用：shell(`pwsh`)、文件读写与搜索、网络取用、subagent/workflow 编排。
- **不可用**：任何 Unreal 编辑器工具、任何 Blender 工具。
- 依据：DSH 具备 MCP 客户端能力（`dsh-mcp-client`），但 `%DSH_HOME%\settings.yaml` 与 `storages\workspace.json` **无任何 MCP 配置**；项目 `.mcp.json` / `mcp.json` / `mcp_config.json` **均不存在**。

## 缺失（系统排查后未发现）

### Unreal Engine

已执行的**全部为否定结果**（细节见 Evidence/T001.md）：

| 排查点 | 结果 |
|---|---|
| `Get-Command UnrealEditor/UnrealEditor-Cmd/UnrealBuildTool/RunUAT` | 均 not-found |
| 注册表 `HKLM/HKCU ... EpicGames\Unreal Engine`（6 处） | 键不存在 |
| `C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests` | 目录不存在 |
| `LauncherInstalled.dat` | 文件不存在 |
| 卸载注册表（机器级 + 每用户）过滤 `Unreal/Epic/UE_` | 无 UE 条目 |
| `.uproject` 文件关联（HKCR/SOFTWARE\Classes/FileExts） | 均不存在 |
| 开始菜单匹配 `Unreal/Epic` | 无命中 |
| App Paths 匹配 `Unreal/Epic` | 无命中 |
| **全卷确定性遍历** `Tools/Probes/scan_for_ue.py` | C:/D:/E: 共 **484,201 个目录，0 命中** |
| D:/E: 根目录 + `D:\SoftWare` 等列举 | 无 UE/Epic 条目 |

**结论：本机未发现 Unreal Engine。** 十类独立机制全部否定。

**未采信的证据（已作废）**：Windows Search 索引查询曾返回 0 命中，但对照实验证明本机索引**只覆盖 C: 的部分目录**（按名查确知存在的 `D:\SoftWare\Blender\blender.exe` 为 0 命中），故该结果**不构成证据**，已从结论剔除。

## 能力矩阵

| 能力 | 当前状态 | 通过证据 |
|---|---|---|
| UE 版本与路径 | **缺失** | 十类证据源全否定；全卷 484,201 目录 0 命中 |
| 蓝图/关卡创建与编辑 | **未验证（阻塞）** | 无 UE，且无任何编辑器自动化工具 |
| PIE/游戏运行控制 | **未验证（阻塞）** | 同上；仅截图工具不等于输入自动化 |
| Windows 打包 | **未验证（阻塞）** | 无 UE；且 Windows SDK 缺失，依赖未确认 |
| Blender 启动与版本 | **通过** | 3.3.1 实测，退出码 0 |
| Blender 无头脚本执行 | **通过** | `--background --python` 实测，PROBE 键值输出 |
| Blender-MCP | **未指定/不存在（阻塞）** | 无 MCP 配置、无工具清单；实现与客户端均未确定 |
| MCP 保存、导出 | **未验证（阻塞）** | 依赖未确定的 MCP 实现；Blender CLI 侧保存/导出 API 已确认存在 |
| UE FBX 导入 | **未验证（阻塞）** | 无 UE |
| 视觉/录屏 | **可运行但被服务端拒绝** | vision.js 实测 403（订阅缺失） |
| Git/LFS/备份 | Git 与 LFS 文件可用，**未验收** | 未初始化仓库；无恢复点试验 |
| 硬件与磁盘余量 | **通过** | CPU/GPU/RAM/磁盘已采集（见上） |

## 阶段门现状

**P0 完全未通过**：E01/E02/E03 全部 NOT-RUN，无打包能力。当前停在 **P0 能力链门口**，原因不是"环境模糊"，而是两个具体缺口（见下）。

## 阻塞与最小解除条件

| 阻塞 | 影响任务 | 最小解除条件 |
|---|---|---|
| 本机未发现 UE；agent 无 UE 编辑器自动化工具 | T001 蓝图/运行项、T002、T005 后半、T006 后半、T007、全部运行验收 | 负责人提供 **UE5 实际安装路径与版本**，或确认"未安装"并授权安装（含版本与位置）；**并且**提供可用的编辑器自动化通道（UE MCP 工具 / 受审查的自动化工具 / 明确同意 C++ 混合路线） |
| Blender-MCP 实现未确定；Blender 3.3.1 兼容性未知 | T004、T005、T006 | 负责人给出**已确认实现**的仓库/客户端/插件与版本，或确认改用 **Blender 3.3.1 自带无头 CLI**（已实测可用） |
| vision 订阅失效（OpenCode Go 403） | 所有视觉验收、T005/T006 外观与比例检查 | 恢复有效订阅或改配可用的 `DASHSCOPE_BASE_URL` + 可用 `VISION_MODEL`；恢复后先用 `Art/Probes/vision_probe_red_blue.png` 自检 |
| C: 仅剩 11.9 GB | T002/T007 产物落盘 | 确认工程与打包输出落在 D:/E: 等有空间卷 |
| Git 无初始化/提交授权 | T003 | 明确授权范围（仅 init？含 commit？） |

## 与 2026-10-12 首次检查的差异

1. 补全了软件**实际版本**（此前只读文件版本、未运行版本命令）。
2. 新增**硬件与磁盘余量**采集（此前明确缺失）。
3. 新增**注册表、卸载项、文件关联、开始菜单、App Paths** 五类 UE 排查，并完成 **C:/D:/E: 三卷确定性遍历（484,201 目录，0 命中）**，把 UE 状态从"不能断言"推进到"未发现"。
4. 实测了 **Blender 无头 CLI**（新通过能力），并发现 `--python-expr` 在本机 PowerShell 下不可用、必须用 `--python <文件>`。
5. 实测了 **vision.js**，发现服务端 403 订阅问题（此前"未运行验证"）。
6. 确认**本会话不存在任何 UE 或 Blender MCP 工具**（此前"用户级 MCP 状态未知"）。
7. 发现**Windows SDK 未安装**。
8. **主动作废了一条自己产出的错误证据**：Windows Search 索引的 0 命中，经对照实验证明该索引在本机不可靠（详见 Commands.md §4.1.1 与 Evidence §3.1.1）。
9. 发现 `M:` 是**网络盘**（`\\szhmx.com\file`）而非本机磁盘。

## 运行命令规则

命令事实以 `Docs/Commands.md` 为准，该文件区分 VERIFIED 与 PENDING，不得把 PENDING 写成可执行示例。引擎路径含空格时 PowerShell 用调用运算符 `&`。
