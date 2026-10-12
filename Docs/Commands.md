# 可复现命令清单

日期：2026-10-12（T001 首次建立）
适用工作目录：`E:/Reborn`

> **本文件的真实性规则**
> 每条命令标注 **VERIFIED**（本机实际执行过，附退出码与真实输出）或 **PENDING**（前置不存在，尚未执行）。
> PENDING 条目只写"解锁后要测什么"和"如何判定成功"，**不写看起来能跑的示例命令**冒充可复现。
> 详见 `Docs/Evidence/T001.md`。

---

## 1. 已锁定路径（绝对路径，实测）

| 工具 | 绝对路径 | 状态 |
|---|---|---|
| Blender | `D:\SoftWare\Blender\blender.exe` | VERIFIED 3.3.1 |
| Node | `D:\SoftWare\nvm\nodejs\node.exe` | VERIFIED v22.18.0 |
| npm | `D:\SoftWare\nvm\nodejs\npm.ps1` | VERIFIED 10.9.3 |
| Git | `D:\SoftWare\Git\cmd\git.exe` | VERIFIED 2.42.0 |
| Git LFS | `D:\SoftWare\Git\cmd\git-lfs.exe` | VERIFIED 3.4.0 |
| Python | `C:\Python313\python.exe` | VERIFIED 3.13.1 |
| dotnet | `C:\Program Files\dotnet\dotnet.exe` | VERIFIED，见 §5 |
| vision 脚本 | `E:\claude-vision-skill\vision.js` | 可运行，服务端拒绝，见 §6 |
| UnrealEditor | **未找到** | BLOCKED，见 §4 |
| UnrealEditor-Cmd | **未找到** | BLOCKED，见 §4 |
| 项目工程 `Reborn.uproject` | **不存在** | 待 T002 创建 |

PowerShell 路径含空格时必须用调用运算符 `&`，全部示例已遵守。

---

## 2. Blender（VERIFIED）

### 2.1 版本与能力探针

```powershell
& 'D:\SoftWare\Blender\blender.exe' --background --factory-startup --python 'E:\Reborn\Tools\Probes\blender_probe.py'
```

- 退出码：**0**
- 耗时：约 11 s
- 日志：stdout（`PROBE|key=value` 逐行），无独立日志文件
- 成功判据：出现 `PROBE|probe_complete=1`，且 `PROBE|object_count=3`
- 实测输出（2026-10-12）：

```
PROBE|blender_version=3.3.1
PROBE|binary_path=D:\SoftWare\Blender\blender.exe
PROBE|python_version=3.10.2
PROBE|unit_system=METRIC
PROBE|unit_scale_length=1.0
PROBE|unit_length_unit=METERS
PROBE|object_count=3
PROBE|object_names=Camera|Cube|Light
PROBE|object.Cube.type_dimensions=MESH|2.000000x2.000000x2.000000
PROBE|has_bpy_ops_export_fbx=True
PROBE|has_bpy_ops_import_fbx=True
PROBE|has_bpy_ops_wm_save_mainfile=True
PROBE|has_bpy_data_armatures=True
PROBE|probe_complete=1
```

### 2.2 通用无头执行形式

```powershell
& 'D:\SoftWare\Blender\blender.exe' --background [--factory-startup] --python '<脚本绝对路径>'
```

- `--factory-startup`：忽略用户配置加载出厂场景，探针与试验用，避免污染/被污染。
- 脚本内用 `sys.stdout.write("PROBE|key=value\n")` 输出机器可读事实。
- **注意**：`--python-expr` 在本机 PowerShell 下会被吞掉内层引号导致 `SyntaxError`（实测），统一改用 `--python <文件>`。

### 2.3 环境事实（T005 尺寸契约的输入）

- 单位制 `METRIC`，`scale_length = 1.0`，长度单位 `METERS`。
- 出厂立方体 `Cube` 实测尺寸 **2.000000 m**（Blender 默认立方体 = 边长 2 m）。
- 因此 T005 的"边长 1 m"目标物体必须**显式**建成 1 m；不能用出厂 Cube 直接当 1 m 基准。

---

## 3. 版本与仓库工具（VERIFIED）

```powershell
& node --version            # v22.18.0
& npm --version             # 10.9.3
& git --version             # git version 2.42.0.windows.2
& git lfs version           # git-lfs/3.4.0 (GitHub; windows amd64; go 1.20.6; git d06d6e9e)
& C:\Python313\python.exe --version   # Python 3.13.1
```

`E:/Reborn` **当前不是 Git 仓库**（无 `.git`）。T003 需要版本管理授权后才 `git init`，本文件不提供未授权的初始化命令。

---

## 4. Unreal Engine（PENDING / BLOCKED）

### 4.1 已执行的定位检查及结果（全部为"未发现"）

| 检查 | 命令要点 | 结果 |
|---|---|---|
| 命令搜索路径 | `Get-Command UnrealEditor, UnrealEditor-Cmd, UnrealBuildTool, RunUAT` | 均 not-found |
| 注册表安装项 | `HKLM/HKCU:\SOFTWARE\EpicGames\Unreal Engine` 等 6 处 | 键不存在 |
| Epic 启动器清单 | `C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests\*.item` | 目录不存在 |
| LauncherInstalled | `C:\ProgramData\Epic\UnrealEngineLauncher\LauncherInstalled.dat` | 文件不存在 |
| 卸载注册表 | `...\Uninstall\*` 过滤 `Unreal\|Epic\|UE_` | 无 UE 条目 |
| `.uproject` 关联 | `HKCR:\.uproject`、`HKLM:\SOFTWARE\Classes\.uproject`、Explorer FileExts | 均不存在 |
| 开始菜单 | `%ProgramData%` / `%APPDATA%` Start Menu 递归匹配 `Unreal\|Epic` | 无命中 |
| App Paths | `HKLM:\...\App Paths` 匹配 `Unreal\|Epic` | 无命中 |
| 目录扫描 | `python -u E:\Reborn\Tools\Probes\scan_for_ue.py C D E` | 退出码 **0**；三卷共 484,201 个目录，**0 命中**（C: 194 s / E: 584 s / D: 459 s） |
| 卷类型 | `Get-CimInstance Win32_LogicalDisk` | C:/D:/E: 为本地固定 NTFS；**M: 是网络盘**（`\\szhmx.com\file`），不属本机 |
| 软件目录列举 | `Get-ChildItem D:\SoftWare, 'D:\Program Files', D:\ProgramData` | 无 UE/Epic 条目 |
| 每用户卸载注册表 | 遍历 `HKEY_USERS\S-1-5-21-*\...\Uninstall` | 无 UE/Epic 条目 |

### 4.1.1 排查方法坑（已踩，直接复用）

- **不要用** `Get-ChildItem -Recurse -Include 'UnrealEditor.exe'`：`-Include` 未配合 `-Path` 通配符时**不按文件名过滤**，实测返回 231 个无关文件并抛 `Win32Exception`，结果无效。
- **不要用** `Get-ChildItem -LiteralPath C:\ -Recurse`：在特殊路径上抛 `The system cannot find the file specified` 后中断。
- **不要用** `where.exe /r <卷>\ ...` 传尾随反斜杠的根：实测 C: 需 494 s，D:/E: 数十分钟未完成，不可控。
- **不要用** `cmd /c "dir /s /b"`：466 GB 卷上 >10 min 未完成。
- **绝对不要用 Windows Search 索引代替文件遍历**：本机索引**只覆盖 C: 的部分目录**，按名查 `blender.exe`（确知存在于 D:）**0 命中**。用索引的 0 命中推断"文件不存在"是**错误推理**，本项目已作废过一次这样的结论（见 Evidence/T001.md §3.1.1）。
- **推荐**：`python -u Tools/Probes/scan_for_ue.py`（`os.walk`，只读，带 `PROGRESS|` 进度与 `RESULT|` 汇总）。实测比 `where /r` 快一个数量级。

### 4.2 解锁后必须补齐的命令（现在**不能**写具体路径）

一旦负责人给出真实安装路径 `UE_ROOT`，按下列顺序实测，并把**实际**结果回填本文件：

1. **版本确认**：读取 `UE_ROOT\Engine\Binaries\Win64\UnrealEditor.exe` 文件版本，或首次启动日志中的 engine version。
2. **编辑器启动**：`& "<UE_ROOT>\Engine\Binaries\Win64\UnrealEditor.exe" "<PROJECT>.uproject"`
   - 判据：进程存活、`Saved/Logs/` 生成日志、无 fatal 错误。
3. **工程创建与测试入口**：T002 建立 `Game/Reborn/Reborn.uproject` 后，记录一次可重开的启动命令。
4. **PIE/运行控制**：必须有**实测可用的编辑器自动化工具**（见 §7 能力门）；仅有截图不算输入自动化。
5. **打包**：`RunUAT.bat BuildCookRun -project=... -noP4 -platform=Win64 -clientconfig=Development -cook -build -stage -pak -archive -archivedirectory=...`
   - 判据：退出码 0，`Builds/P0-Win64/` 下存在可独立启动的 exe。**打包命令被启动不算通过**，必须启动该 exe。
6. **打包版启动**：从归档目录启动独立程序，验证出生、碰撞、输入、正常退出，并重启一次。
7. 每条命令记录：绝对路径、工作目录、完整命令行、退出码、日志绝对路径、成功判据。

### 4.3 阻塞的最小解除条件

- **要什么**：本机 UE5 的**实际安装路径与版本号**（例如 `D:\Program Files\Epic Games\UE_5.x`）。
- **或者**：明确"本机未安装"，由负责人决定安装版本与位置（安装属需授权动作，agent 不擅自执行）。

---

## 5. C++/SDK 工具链（VERIFIED，为 T007 打包能力评估）

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe' -products * -format value -property displayName
& dotnet --list-runtimes
```

- 实测：Visual Studio Community 2022 17.12.1 存在；另有 VS 15 生成工具 2017、Microsoft Visual Studio Installer 3.12。
- **Windows SDK 未安装**：`C:\Program Files (x86)\Windows Kits\10\Include` 与 `...\10\bin` 均不存在。
- 影响：T007 打包依赖尚未确认。**不能一概断言需要或不需要 C++ 工具链**；需在 T001/T007 按所选 UE 版本的实际要求核对后再判定。

---

## 6. 视觉验证（可运行，服务端当前拒绝）

```powershell
& node "E:\claude-vision-skill\vision.js" "<图片绝对路径>" "<中文检查问题>"
```

- 脚本存在且**能启动并发出请求**（实测）。
- 实测结果：**退出码 1**，服务端返回
  `API 403: {"error":{"type":"server_error","message":"Upstream request failed: An active OpenCode Go subscription is required to use Go models."}}`
- 配置（只记键名，不记值）：`E:\claude-vision-skill\.env` 含 `DASHSCOPE_API_KEY`、`VISION_MODEL=mimo-v2.5`；**未设置 `DASHSCOPE_BASE_URL`**，脚本回退到默认值。
- 结论：调用链已打通到"服务端鉴权"这一步；**当前不能产出任何画面判断**。所有视觉验收保持 NOT-RUN。
- 已知答案探针图：`Art/Probes/vision_probe_red_blue.png`（64×32，左半纯红右半纯蓝；已用 Blender 解码器逐像素核对）。恢复订阅后用它第一时间确认工具可用。
- 生成命令：`& C:\Python313\python.exe 'E:\Reborn\Tools\Probes\make_probe_image.py'`

---

## 7. Agent 自动化能力门（决定 T001 剩余项）

本会话实测可用工具：`pwsh`(shell)、文件读写/搜索、`web_fetch`/`web_search`、subagent/workflow、goal/todo 等编排工具。

**不可用**：任何 Unreal 编辑器工具、任何 Blender 工具。依据：

- DSH 具备 MCP 客户端能力（`%DSH_HOME%\profiles\node_modules\@deepseek-ai\dsh-mcp-client`），但
- `%DSH_HOME%\settings.yaml` 与 `storages\workspace.json` **不含任何 `mcpServers`/`mcp` 配置**；
- 项目侧 `E:/Reborn/.mcp.json`、`mcp.json`、`mcp_config.json` **均不存在**；
- 因此本会话**不存在**可由 agent 调用的 UE 或 Blender MCP 工具。

含义：
- **能**用 shell 调用 Blender 无头 CLI（§2，已实测）。
- **不能**驱动 UE 编辑器创建蓝图、连事件节点、编译保存、控制 PIE。
- 这一缺口**不能**由 Blender 能力推断补齐（AGENTS.md 明令）。在它解除前，T002 与一切运行验收无法开始。

---

## 8. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-12 | 首次建立。锁定 Blender/Node/Git/Python 路径与版本；写入 Blender 无头实测命令；UE 相关全部标 PENDING/BLOCKED 并给出解锁检查表。 |
