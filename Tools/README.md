# Tools 目录说明

Reborn 项目的辅助工具脚本。运行游戏的正式入口是 `RunGame.cmd` / `OpenEditor.cmd`。

## 零窗口启动器（2026-11-05 起强制）

**所有自动化调用**（导出、打包、headless 回归、包内断言、批量脚本、取证截图）**一律经
`Tools\NoWindow.vbs` 启动**；禁止直接 `powershell -File ...`，禁止任何自动化使用
`*_console.exe`。

```bat
wscript.exe E:\Reborn\Tools\NoWindow.vbs ^
  E:\Reborn\Tools\Probes\export_outer.log ^
  "powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\t043_package.ps1"
```

- `NoWindow.vbs` 用 `WScript.Shell.Run(cmd, 0, True)` 以 `windowStyle=0` 起 `cmd.exe`，
  stdout/stderr 重定向到日志，并回传子进程退出码。`wscript.exe` 是 GUI 子系统，
  `cmd`/`powershell`/`python`/`godot` 全部共享同一个**隐藏控制台**，不会新增可见窗口。
- 需要“整段过程可见窗口 = 0”的证据时，使用 `Tools\ZeroWindowRun.ps1`（同样经
  `NoWindow.vbs` 启动）：它运行目标脚本并全程 5 ms 轮询用户桌面，任何**新出现的可见
  顶层窗口**都记 `HIT|...`，末尾 `WINDOWWATCH|summary|visible_hits=N|other_windows=M`。
  `visible_hits` 只统计自动化链自己的进程（godot/python/cmd/powershell/wscript/conhost/
  reborn）；用户桌面上的第三方窗口（Chrome、企业微信等）记为 `OTHER|...` 并单独计数。
- **GUI 子系统 exe 不能用 `&` 直接调用**：PowerShell 对 GUI exe 不等待、不捕获 stdout，
  `$LASTEXITCODE` 为空（2026-11-05 全量批处理因此 54 套全部空跑、checks=0）。必须用
  `Start-Process -Wait -RedirectStandardOutput/-RedirectStandardError`，或走
  `CaptureRun.ps1`（内部 CreateProcessW + 等待）。
- 头less 统一用 **GUI exe + `--headless`**。`*_console.exe` 是控制台程序，即使
  `--headless` 也会弹终端，任何自动化都不得使用。

## CaptureRun.ps1 —— 实跑/取证的统一启动包装（2026-11-02 起生效，含 headless）

**所有 Godot 实跑（渲染截图与 headless 导入/生成器/回归）一律通过本包装启动，
不要再直接 `& godot.exe ...`。**

```bat
rem 非 headless（渲染截图，窗口在自建隐藏桌面上，用户桌面零可见）
rem 外层一律先经 NoWindow.vbs，不得直接 powershell -File
wscript.exe E:\Reborn\Tools\NoWindow.vbs E:\Reborn\Tools\Probes\capture_creek.log ^
  "powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_creek.gd -UserArgs creek -TimeoutSec 300"

rem headless（导入 / 生成器 / 回归，零窗口，日志落文件）
wscript.exe E:\Reborn\Tools\NoWindow.vbs E:\Reborn\Tools\Probes\capture_headless.log ^
  "powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\CaptureRun.ps1 -Headless -Script tests/run_art09_frame_contract.gd -TimeoutSec 300"
```

| 参数 | 说明 |
|---|---|
| `-Script` | 相对 `Game/Reborn` 的工具脚本路径（如 `tests/tool_capture_creek.gd`） |
| `-UserArgs` | 传给工具的用户参数（自动拼到 `--` 之后），如 `ravine`、`integration` |
| `-QuitAfter` | `--quit-after` 帧数保险丝（默认 200000） |
| `-TimeoutSec` | 外层等待上限（默认 900；超时杀进程、报 TIMEOUT=124、日志保留） |
| `-Headless` | 加 `--headless`（跳过 `--position`）。用于导入/生成器/回归 |
| `-VisibleDesktop` | **诊断用**：不在隐藏桌面启动，退回"屏幕外+autoload+监视器"模式
  （该模式实测窗口会先在左上角可见 ~1.7 秒，见下）。平时不要用 |

### 为什么必须走包装（四个实测坑，2026-11-02）

1. **渲染窗口零可见 = 自建隐藏桌面**：非 headless 默认在
   `CreateDesktopW("RebornCapture")` 建的桌面上 `CreateProcessW` 启动——子进程的
   所有窗口只能建在那个桌面上，**用户桌面按定义不可见**（验收实测 `visible_hits=0`）。
   - **为什么不能只靠 `--position`/屏幕外**：实测 Godot 在 Windows 上主窗口**显式**建在
     客户区 (0,0)（矩形 (-7,-30,1031,584)），且启动期主线程 ~2 秒不泵消息——
     `--position`、project `initial_position_type`、`override.cfg`、autoload
     （t≈2.4 秒才跑，引擎内部位置仍 (0,0)）、外部 `SetWindowPos` **全部要等引擎泵消息
     后才生效**，窗口会先在左上角可见 ~1.7-1.9 秒（负责人三次反馈的"闪一下"）。
   - `CreateProcessW + STARTF_USEPOSITION` 也无效（实测）：Godot 显式传坐标建窗。
   - **不要**改回最小化/隐藏窗口：最小化会停止渲染，截图会拿到黑帧（Godot 已知行为）。
   - 隐藏桌面上的渲染经实测与可见桌面**逐字节同级**：water motion 0.0316→0.0320、
     亮度一致、vision 判读通过（2026-11-02 两次连跑，见下"验证记录"）。
2. **永远用 GUI 版 exe（`Godot_v4.7.2-stable_win64.exe`），不要用 console 版**：
   `..._console.exe` 是控制台程序，即使 `--headless`/参数全对，它**本身也会在桌面弹一个
   黑色终端窗口**（负责人 2026-11-02 二次反馈的晃眼来源）。日志一律由
   `CreateProcessW` 的 `STARTF_USESTDHANDLES` 重定向获得，与 exe 类型无关；
   headless 场景用 `-Headless` 开关走 GUI exe。**取证/实跑一律不要用 console 版 exe。**
3. **print() 断管道挂死**：Godot 的 `print()` 写入"读端已死"的管道会**阻塞主线程**。
   前台命令超时被移到后台时管道即断裂，症状是工具卡在某个 view 永远不存图
   （ART07 上一轮"取证超时 240s+"的真实根因，不是渲染慢）。
   包装的输出重定向天然免疫。
4. **Win32 监视器两个坑**（诊断 `-VisibleDesktop` 模式/兜底时相关）：
   - 监视器挪窗**必须** `SWP_ASYNCWINDOWPOS`：同步 `SetWindowPos` 要等目标窗口处理
     消息，Godot 启动期不泵消息，同步调用会把监视器阻塞 ~1.4 秒、期间"失明"
     （这就是早期误判"窗口只闪 20ms"的原因，实测可见 ~1.7 秒）。
   - 轮询要 `timeBeginPeriod(1)`：Windows 默认定时器精度 ~15.6ms，不设的话
     `Thread.Sleep(2)` 实际睡 ~15.6ms（轮询被撑到 ~20ms；设后 ~3ms）。
   - 每次运行把两个桌面的窗口矩形/时间戳写进 `<log>.winmon.log`
     （`visible_hits` 应为 0；隐藏桌面窗口记 `hidden_desk_*` 行，只留证不计可见）。

### 验证记录

- **2026-11-02 15:28（首次）**：`tool_capture_creek.gd -- creek` 窗口位于 (-2400,-2400)，
  全程未出现在前台（当时结论，后被 16:4x 的监视器时间线修正为"先可见 ~1.7 秒再挪走"）；
  4 张 PNG 产出、水面在动非黑帧；vision 判读通过。
- **2026-11-02 16:08（console 版坑修复后，`Tools/verify_no_window.ps1`）**：
  连续 2 次运行并轮询 Godot 进程窗口句柄——headless 回归 12 次采样 **0 个窗口句柄**
  （48/48 PASS）；非 headless 截图的渲染窗口存在（标题 `Reborn (DEBUG)`）但在屏幕外，
  4 帧产出、vision 复判非黑有效。详见 `Docs/Evidence/ART11_GROUND_TEXTURE.md` §7。
- **2026-11-02 17:02/17:03（隐藏桌面最终验收）**：连续 2 次
  `tool_capture_creek.gd -- creek`：
  - 170233 跑：用户桌面 `windows_seen=0|visible_hits=0`；隐藏桌面 4 窗（主窗首见
    rect=(-7,-30,1031,584) t=315ms，2330ms 挪至 (-3207,-3230)，全程用户不可见）；
  - 170303 跑：同样 `visible_hits=0`；
  - 两次截图均非黑（water motion 0.0316/0.0320、亮度 0.5954）、exit=0、stderr 空，
    vision 判读"非全黑、可见水面/植被/石墙、亮度正常"通过；
  - 同日 headless 回归：T011 229/229、T012 79/79（新启动器 + autoload 在场）。
  证据：`Art/Probes/.capture_logs/tool_capture_creek_20261102_170233.log.winmon.log`、
  `..._170303.log.winmon.log`；调查全过程见
  `Docs/Evidence/ART07_ENVIRONMENT_COMPOSITION_CONTACT.md` §9.4 三次反馈补记。

### 已知小坑（PS 5.1）

- 本文件与所有含中文注释的 `.ps1` 必须是 **UTF-8 with BOM**：无 BOM 会被 PS5 按 GBK
  误读，中文注释字节可能吞掉换行/后续字符导致解析错乱（2026-11-02 实际踩过：
  下载脚本把 `Copy-Item` 目标吞成了盘根路径）。补 BOM：
  `[IO.File]::WriteAllText($p, (Get-Content -Raw $p), (New-Object Text.UTF8Encoding $true))`。
- Poly Haven 下载：`api.polyhaven.com/assets/<id>` 元数据端点对部分资产 404，
  用 `files/<id>` 端点拿直链+size+md5 即可（`download_ground_tex_candidates.ps1` 模式）。

## 其他脚本（2026-11-02，ART11 选型副产物）

- `download_ground_tex_candidates.ps1`：Poly Haven CC0 贴图候选下载+校验（size/md5/sha256）。
- `make_tex_preview_sheet.ps1`：候选 diffuse 拼 9 宫格对比板（vision 短名单用）。
- `make_gtex_side_by_side.ps1`：候选渲染帧拼 2×2 并排图（vision 终审用，注意 8MB 上限要缩图）。
- `verify_no_window.ps1`："零可见窗口"验证（轮询 Godot 进程 MainWindowHandle）。

