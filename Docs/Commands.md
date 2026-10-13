# 可复现命令清单

日期：2026-10-12 建立；**2026-10-13 引擎切换为 Godot 4 后重写**
适用工作目录：`E:/Reborn`

> **本文件的真实性规则**
> 每条命令标注 **VERIFIED**（本机实际执行过，附退出码与真实输出）或 **PENDING**（前置不存在，尚未执行）。
> PENDING 条目只写"解锁后要测什么"和"如何判定成功"，**不写看起来能跑的示例命令**冒充可复现。
> 证据全文见 `Docs/Evidence/T001.md`、`Docs/Evidence/T004.md`。

---

## 1. 已锁定路径（绝对路径，实测）

| 工具 | 绝对路径 | 状态 |
|---|---|---|
| **Godot（命令行）** | `E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` | VERIFIED 4.7.2 |
| Godot（GUI） | `E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe` | VERIFIED 存在 |
| Blender | `D:\SoftWare\Blender\blender.exe` | VERIFIED 3.3.1 |
| Node | `D:\SoftWare\nvm\nodejs\node.exe` | VERIFIED v22.18.0 |
| npm | `D:\SoftWare\nvm\nodejs\npm.ps1` | VERIFIED 10.9.3 |
| Git | `D:\SoftWare\Git\cmd\git.exe` | VERIFIED 2.42.0 |
| Git LFS | `D:\SoftWare\Git\cmd\git-lfs.exe` | VERIFIED 3.4.0 |
| Python | `C:\Python313\python.exe` | VERIFIED 3.13.1 |
| vision 脚本 | `E:\claude-vision-skill\vision.js` | 可运行，服务端拒绝，见 §6 |
| Godot 导出模板 | `%APPDATA%\Godot\export_templates\` | **目录存在但为空 → T007 阻塞** |

> ⚠ **陷阱**：`E:\Godot_v4.7.2-stable_win64.exe` 是**目录**，不是文件。命令行必须用**里层**的 `_console.exe`。

PowerShell 路径含空格时必须用调用运算符 `&`，全部示例已遵守。

---

## 2. Godot 4（VERIFIED）

### 2.1 版本查询

```powershell
& 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --version
```

- 退出码：**0**
- 输出：`4.7.2.stable.official.ed1daf0bf`

### 2.2 无头运行工程（**本项目的主力验收手段**）

```powershell
& 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path 'E:\Reborn\Game\Reborn' --quit-after 300
```

- 退出码：**0**（探针工程实测）
- 成功判据：退出码 0，且 stdout 出现预期的 `PROBE|` / 断言行
- **`--quit-after <N>` 不是可选项**：脚本加载失败时 `get_tree().quit()` 不会被调用，进程会挂死。
  实测过一次 180 s 超时后才被终止。它同时是防止自动化卡死的硬上限。

### 2.3 GDScript 静态语法检查（**改完脚本先跑这个**）

```powershell
& 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --path '<proj>' --check-only --script 'res://<script>.gd'
```

- 语法正确时退出码 **0**；有错时退出码 **1** 并打印 `SCRIPT ERROR: Parse Error: ...` + 行号。
- **已对照验证为可信静态门**：它真实抓到过写出的 GDScript 语法错误（见 `Docs/Evidence/T004.md` §2.4）。

### 2.4 命令行能力清单（`--help` 实测摘录）

```
--headless                        Enable headless mode (--display-driver headless --audio-driver Dummy).
--path <directory>                Path to a project (must contain a "project.godot").
-s, --script <script>             Run a script.
--check-only                      Only parse for errors and quit (use with --script).
--quit                            Quit after the first iteration.
--quit-after <int>                Quit after the given number of iterations.
--import                          Import resources then quit.
--export-release <preset> <path>  Export the project in release mode.
--export-debug <preset> <path>    Export in debug mode.
--export-pack <preset> <path>     Export project data only.
-e, --editor                      Start the editor instead of running the scene.
```

### 2.5 关键工程事实

- 工程文件、场景、资源、脚本**全部是纯文本**（`project.godot` / `.tscn` / `.tres` / `.gd`）→ **agent 可直接编写**，无需编辑器。
- 首次运行会在工程目录生成 `.godot/` 缓存（已加入 `.gitignore`）。
- **单位是米**；`Parameters.md` 是厘米，代码中 ÷100。
- `CapsuleShape3D.height` 是**含两端半球的总高**（= 2 × 半高）。

---

## 3. Blender（VERIFIED）

### 3.1 版本与能力探针

```powershell
& 'D:\SoftWare\Blender\blender.exe' --background --factory-startup --python 'E:\Reborn\Tools\Probes\blender_probe.py'
```

- 退出码：**0**，耗时约 11 s
- 成功判据：出现 `PROBE|probe_complete=1`
- 实测关键输出：

```
PROBE|blender_version=3.3.1
PROBE|python_version=3.10.2
PROBE|unit_system=METRIC
PROBE|unit_scale_length=1.0
PROBE|object.Cube.type_dimensions=MESH|2.000000x2.000000x2.000000
PROBE|has_bpy_ops_export_fbx=True
PROBE|has_bpy_data_armatures=True
```

### 3.2 通用无头执行形式

```powershell
& 'D:\SoftWare\Blender\blender.exe' --background [--factory-startup] --python '<脚本绝对路径>'
```

- **坑**：`--python-expr` 在本机 PowerShell 下会被吞掉内层引号导致 `SyntaxError`（实测）。**统一用 `--python <文件>`。**
- 出厂立方体 `Cube` 实测 **2.000000 m**；T005 的 1 m 基准**必须显式建模**。

---

## 4. 版本与仓库工具（VERIFIED）

```powershell
& node --version            # v22.18.0
& npm --version             # 10.9.3
& git --version             # git version 2.42.0.windows.2
& git lfs version           # git-lfs/3.4.0 (GitHub; windows amd64; go 1.20.6; git d06d6e9e)
& C:\Python313\python.exe --version   # Python 3.13.1
```

### 4.1 仓库状态与推送（VERIFIED）

- 仓库 `E:/Reborn`，分支 `main`，远端 `https://github.com/XwenHaHa/Reborn.git`（**公开**）。
- 提交作者 `XwenHaHa <929716663@qq.com>`；`credential.helper = store`（凭据在用户级 `.git-credentials`，**不入库**）。
- **网络**：直连 `github.com:443` 失败（21 s 超时）。必须经本机 clash-verge 代理 `127.0.0.1:7897`：

```powershell
# 只在命令上临时指定，未写入 git 全局配置
& git -c http.proxy=http://127.0.0.1:7897 -c https.proxy=http://127.0.0.1:7897 push origin main
```

- **T003 仍未完成**：`.gitattributes` 与 LFS 追踪**尚未建立**。在 T002 产生二进制资产**之前**必须先做。

---

## 5. Windows 导出（PENDING — 阻塞）

### 5.1 当前阻塞

```powershell
& '<godot_console.exe>' --headless --path '<proj>' --export-release "Windows Desktop" '<out>.exe'
```

实测退出码 **1**：

```
ERROR: This project doesn't have an `export_presets.cfg` file at its root.
```

排查后确认**两个缺失**：
1. `export_presets.cfg` 缺失 —— **纯文本，agent 可写，不构成实质阻塞**。
2. **导出模板未安装** —— `%APPDATA%\Godot\export_templates\` 存在但**为空**。这是真阻塞。

### 5.2 解锁后必须补齐的记录

1. 确认模板版本为 **`4.7.2.stable`**（与引擎一致）。
2. 记录 `export_presets.cfg` 实际内容与 preset 名。
3. 导出的**退出码**与目标 `.exe` 的**实际存在与大小**（不能只看命令返回）。
4. 从导出目录**启动独立程序**，验证出生、碰撞、输入、正常退出，并重启一次。
5. 无 GUI/输入自动化工具时记 `awaiting-review`，**不冒充通过**。

### 5.3 最小解除条件

安装与引擎版本匹配的 **Godot 导出模板**（约 1 GB）。
编辑器内 `编辑器 → 管理导出模板 → 下载并安装`。属"下载第三方内容"，需负责人授权或自行安装。

---

## 6. 视觉验证（可运行，服务端当前拒绝）

```powershell
& node "E:\claude-vision-skill\vision.js" "<图片绝对路径>" "<中文检查问题>"
```

- 脚本存在且**能启动并发出请求**（实测）。
- 实测结果：**退出码 1**，服务端返回
  `API 403: {"error":{"type":"server_error","message":"Upstream request failed: An active OpenCode Go subscription is required to use Go models."}}`
- 配置（只记键名，不记值）：`E:\claude-vision-skill\.env` 含 `DASHSCOPE_API_KEY`、`VISION_MODEL=mimo-v2.5`；**未设置 `DASHSCOPE_BASE_URL`**。
- 结论：调用链已打通到"服务端鉴权"这一步；**当前不能产出任何画面判断**。所有视觉验收保持 NOT-RUN。
- 已知答案探针图：`Art/Probes/vision_probe_red_blue.png`（64×32，左半纯红右半纯蓝；已用 Blender 解码器逐像素核对）。恢复订阅后用它第一时间确认工具可用。
- 生成命令：`& C:\Python313\python.exe 'E:\Reborn\Tools\Probes\make_probe_image.py'`

**影响**：Godot 的画面验收（T002 视觉部分、T005 比例/朝向、T006 变形）在恢复前记 `awaiting-review`。
**数据断言（无头运行 + 读回数值）不依赖视觉工具，可以照常通过。**

---

## 7. Agent 自动化能力门

本会话实测可用：`pwsh`(shell)、文件读写与搜索、`web_fetch`/`web_search`、subagent/workflow 编排。

**不可用**：任何 Unreal 编辑器工具、任何 Blender MCP 工具。依据：

- DSH 具备 MCP 客户端能力（`%DSH_HOME%\profiles\node_modules\@deepseek-ai\dsh-mcp-client`），但
- `%DSH_HOME%\settings.yaml` 与 `storages\workspace.json` **不含任何 `mcpServers` 配置**；
- 项目侧 `E:/Reborn/.mcp.json`、`mcp.json`、`mcp_config.json` **均不存在**。

**对 Godot 而言这不构成阻塞**：纯文本工程 + `--headless` 命令行已构成完整闭环（T004 实测）。

---

## 8. 环境排查方法坑（已踩，直接复用）

- **不要用** `Get-ChildItem -Recurse -Include 'X.exe'`：`-Include` 未配合 `-Path` 通配符时**不按文件名过滤**，实测返回 231 个无关文件并抛 `Win32Exception`。
- **不要用** `Get-ChildItem -LiteralPath C:\ -Recurse`：特殊路径上抛 `The system cannot find the file specified` 后中断。
- **不要用** `where.exe /r <卷>\ ...` 传尾随反斜杠根目录：C: 需 494 s，D:/E: 数十分钟未完成。
- **绝对不要用 Windows Search 索引代替文件遍历**：本机索引**只覆盖 C: 的部分目录**，按名查确知存在于 D: 的 `blender.exe` **0 命中**。用索引 0 命中推断"文件不存在"是**错误推理**（本项目已作废过一次这样的结论）。
- **判断文件是否损坏前先看 `PSIsContainer`**：Godot 那个"0 字节 exe"实际是目录。
- **推荐**：`python -u Tools/Probes/scan_for_ue.py`（`os.walk`，只读，带进度与汇总）。

---

## 9. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-12 | 首次建立。锁定 Blender/Node/Git/Python 路径与版本；UE 相关全部标 PENDING/BLOCKED。 |
| 2026-10-13 | **引擎切换 Godot 4**。新增 §2 Godot 命令（无头运行、`--check-only`、能力清单）；§5 导出改为 PENDING 并定位真阻塞为导出模板缺失；新增 §8 排查方法坑；§4.1 记录代理推送路径。 |
