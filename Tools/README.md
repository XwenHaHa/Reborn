# Tools 目录说明

Reborn 项目的辅助工具脚本。运行游戏的正式入口是 `RunGame.cmd` / `OpenEditor.cmd`。

## CaptureRun.ps1 —— 实跑/取证的统一启动包装（2026-11-02 起生效，含 headless）

**所有 Godot 实跑（渲染截图与 headless 导入/生成器/回归）一律通过本包装启动，
不要再直接 `& godot.exe ...`。**

```powershell
# 非 headless（渲染截图，窗口在屏幕外）
powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\CaptureRun.ps1 `
    -Script tests/tool_capture_creek.gd -UserArgs creek -TimeoutSec 300
# headless（导入 / 生成器 / 回归，零窗口，日志落文件）
powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\CaptureRun.ps1 `
    -Headless -Script tests/run_art09_frame_contract.gd -TimeoutSec 300
```

| 参数 | 说明 |
|---|---|
| `-Script` | 相对 `Game/Reborn` 的工具脚本路径（如 `tests/tool_capture_creek.gd`） |
| `-UserArgs` | 传给工具的用户参数（自动拼到 `--` 之后），如 `ravine`、`integration` |
| `-QuitAfter` | `--quit-after` 帧数保险丝（默认 200000） |
| `-TimeoutSec` | 外层等待上限（默认 900；超时杀进程、报 TIMEOUT=124、日志保留） |
| `-Headless` | 加 `--headless`（跳过 `--position`）。用于导入/生成器/回归 |

### 为什么必须走包装（三个实测坑，2026-11-02）

1. **渲染窗口不弹前台**：包装用 Godot `--position X,Y` 把渲染窗口直接创建在
   **虚拟屏幕外**（当前为 (-2400,-2400)），窗口从头到尾不出现在任何显示器上。
   - 负责人 2026-11-02 反馈"每次取证窗口弹到前台很晃眼"，本包装即为其解。
   - **不要**改回最小化/隐藏窗口：最小化会停止渲染，截图会拿到黑帧（Godot 已知行为）。
2. **永远用 GUI 版 exe（`Godot_v4.7.2-stable_win64.exe`），不要用 console 版**：
   `..._console.exe` 是控制台程序，即使 `--headless`/参数全对，它**本身也会在桌面弹一个
   黑色终端窗口**（负责人 2026-11-02 二次反馈的晃眼来源）。日志一律由包装的
   `Start-Process -RedirectStandardOutput/-RedirectStandardError` 获得，与 exe 类型无关；
   headless 场景用 `-Headless` 开关走 GUI exe。
3. **print() 断管道挂死**：Godot 的 `print()` 写入"读端已死"的管道会**阻塞主线程**。
   前台命令超时被移到后台时管道即断裂，症状是工具卡在某个 view 永远不存图
   （ART07 上一轮"取证超时 240s+"的真实根因，不是渲染慢）。
   包装的输出重定向天然免疫。

### 验证记录

- **2026-11-02 15:28（首次）**：`tool_capture_creek.gd -- creek` 窗口位于 (-2400,-2400)，
  全程未出现在前台；4 张 PNG 产出、水面在动非黑帧；vision 判读通过。
- **2026-11-02 16:08（console 版坑修复后，`Tools/verify_no_window.ps1`）**：
  连续 2 次运行并轮询 Godot 进程窗口句柄——headless 回归 12 次采样 **0 个窗口句柄**
  （48/48 PASS）；非 headless 截图的渲染窗口存在（标题 `Reborn (DEBUG)`）但在屏幕外，
  4 帧产出、vision 复判非黑有效。详见 `Docs/Evidence/ART11_GROUND_TEXTURE.md` §7。

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

