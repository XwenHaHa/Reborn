# Tools 目录说明

Reborn 项目的辅助工具脚本。运行游戏的正式入口是 `RunGame.cmd` / `OpenEditor.cmd`。

## CaptureRun.ps1 —— 非 headless 实跑/取证的统一启动包装（2026-11-02 起生效）

**所有需要弹渲染窗口的实跑与截图，一律通过本包装启动 Godot，不要再直接 `& godot.exe ...`。**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:\Reborn\Tools\CaptureRun.ps1 `
    -Script tests/tool_capture_creek.gd -UserArgs creek -TimeoutSec 300
```

| 参数 | 说明 |
|---|---|
| `-Script` | 相对 `Game/Reborn` 的工具脚本路径（如 `tests/tool_capture_creek.gd`） |
| `-UserArgs` | 传给工具的用户参数（自动拼到 `--` 之后），如 `ravine`、`integration` |
| `-QuitAfter` | `--quit-after` 帧数保险丝（默认 200000） |
| `-TimeoutSec` | 外层等待上限（默认 900；超时杀进程、报 TIMEOUT=124、日志保留） |

### 为什么必须走包装（两个实测坑，2026-11-02）

1. **窗口不弹前台**：包装用 Godot `--position X,Y` 把渲染窗口直接创建在
   **虚拟屏幕外**（当前为 (-2400,-2400)），窗口从头到尾不出现在任何显示器上。
   - 负责人 2026-11-02 反馈"每次取证窗口弹到前台很晃眼"，本包装即为其解。
   - **不要**改回最小化/隐藏窗口：最小化会停止渲染，截图会拿到黑帧（Godot 已知行为）。
   - 注意：进程启动瞬间可能仍有一瞬间的焦点切换（窗口不可见），但不闪画面。
2. **print() 断管道挂死**：Godot 的 `print()` 写入"读端已死"的管道会**阻塞主线程**。
   前台命令超时被移到后台时管道即断裂，症状是工具卡在某个 view 永远不存图
   （ART07 上一轮"取证超时 240s+"的真实根因，不是渲染慢）。
   包装用 `Start-Process -RedirectStandardOutput` 把输出写进日志文件，天然免疫。

### 验证记录（2026-11-02 15:28，负责人要求）

- 用包装跑 `tool_capture_creek.gd -- creek`：窗口位于 (-2400,-2400)，全程未出现在前台；
  4 张 PNG 全部产出，`water_region_lum≈0.59/0.48`、`mean_abs_diff≈0.032`（水面在动、非黑帧）；
  vision 判读确认"画面不是全黑、庭院场景清晰、亮度正常"。
- 产物：`C:/Users/<user>/AppData/Roaming/Godot/app_userdata/Reborn/creek_*.png`；
  日志：`Art/Probes/.capture_logs/tool_capture_creek_*.log`。

### 已知小坑（PS 5.1）

- 本文件是 **UTF-8 with BOM**：中文注释 + 无 BOM 会被 PS5 按 GBK 误读导致解析错乱。
  编辑后若报奇怪的 `Unexpected token '}'`，用
  `[IO.File]::WriteAllText($p, (Get-Content -Raw $p), (New-Object Text.UTF8Encoding $true))` 补 BOM。
