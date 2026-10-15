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

### 2.6 T009 / T010 移动验收与试验世界（VERIFIED — 2026-10-13）

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$p = 'E:\Reborn\Game\Reborn'

# 1) 生成/重建移动试验世界（幂等；改完会重新加载并核对几何）
& $g --headless --path $p --script 'res://tests/tool_make_move_fixtures.gd'
#    -> TOOL|make_move_fixtures|done，全部 VERIFY|...|OK

# 2) 把 lab 场景的灰盒玩家换成正式猫（幂等；带"无意外变更"自检）
& $g --headless --path $p --script 'res://tests/tool_set_lab_player.gd'
#    -> TOOL|set_lab_player|done

# 3) T009 / T010 断言（81 条 / 95 条）
& $g --headless --path $p --script 'res://tests/run_t009_cat_movement.gd' --quit-after 40000
#    -> SUMMARY|checks=81|failures=0  RESULT|PASS   EXIT=0
& $g --headless --path $p --script 'res://tests/run_t010_mouse_movement.gd' --quit-after 40000
#    -> SUMMARY|checks=95|failures=0  RESULT|PASS   EXIT=0

# 4) 视觉捕获（**不能加 --headless**：无头是 dummy 渲染器，没有画面；`--quit-after` 见下方提示）
& $g --path $p --script 'res://tests/tool_capture_render.gd' --quit-after 60000 -- t009
#    -> user://t009_{ramp,low_ceiling,platform}_{tp,fp}.png
& $g --path $p --script 'res://tests/tool_capture_render.gd' --quit-after 60000 -- t010
#    -> user://t010_{tunnel,mouse_low}_{tp,fp}.png
#       （%APPDATA%\Godot\app_userdata\Reborn\，本仓库拷贝到 Art/Probes/）

# 5) 包内复验（导出产物见 §5.1；包内断言必须用编辑器二进制 + --main-pack）
& $g --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
    --script 'res://tests/run_t009_cat_movement.gd' --quit-after 40000
#    -> SUMMARY|checks=81|failures=0  EXIT=0
& $g --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
    --script 'res://tests/run_t010_mouse_movement.gd' --quit-after 40000
#    -> SUMMARY|checks=95|failures=0  EXIT=0
```

- 试验世界 `scenes/maps/l_move_fixtures.tscn` 的**六个区**分道布置（坡道 x∈[−1,1]、猫低顶 x=−6、墙角 x/z≈−6、
  50 cm 高台 x=6.5、**鼠洞 x=2.5**、**鼠低顶 x=−3.5**）；**改几何前先看 `tool_make_move_fixtures.gd` 头部的分道说明**。
- T009/T010 断言脚本会**从场景节点读几何**（触发距离、洞的开口、低顶净空……），但把"设计意图常量"
  （50 cm / 42 cm / 25° / 0.24×0.30 / 0.15）写死在断言里：谁改了试验世界而没改设计，测试直接失败。
- 捕获模式用 `-- t009` / `-- t010` 选择场景组；**`--quit-after` 要给足**：实测非 headless 下 12000 只拍完 2 个场景，
  30000/60000 才完整 —— 迭代上限按"场景数 × 每场景帧数"给余量。

---


---

## 2.7 T011 生态灰盒关卡（VERIFIED — 2026-10-13）

```powershell
# 1) 生成/重建灰盒关卡（幂等：四区域铺满 + 走廊 0 阻挡 + 尺寸判据 自检）
& $g --headless --path $p --script 'res://tests/tool_make_courtyard.gd'
#    -> TOOL|make_courtyard|done，0 个 VERIFY|...|FAIL
#       res://scenes/maps/l_courtyard.tscn（80×80 m、四区域、树根屏障 + 鼠洞、溪边缝隙、补给点）

# 2) T011 断言（210 条：几何 + 尺寸判据 + 6 组真实动物物理探针）
& $g --headless --path $p --script 'res://tests/run_t011_greybox.gd' --quit-after 60000
#    -> SUMMARY|checks=210|failures=0  RESULT|PASS   EXIT=0

# 3) 关卡视觉（7 个视角；**不能加 --headless**）
& $g --path $p --script 'res://tests/tool_capture_render.gd' --quit-after 60000 -- t011
#    -> user://t011_{map_overview,courtyard,courtyard_shelter,grass_danger,roots_hole_lane,roots_barrier_oblique,creek_gap_lane}.png

# 4) 包内复验
& $g --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
    --script 'res://tests/run_t011_greybox.gd' --quit-after 60000
#    -> SUMMARY|checks=210|failures=0  EXIT=0
```

- 关卡几何的**唯一真源**是 `tool_make_courtyard.gd` 的常量；断言从场景几何 + `resources/species/*.tres` **算**判据
  （谁改了不一致就红）。常量表见 `Docs/Parameters.md`「生态灰盒关卡常量」与 `Docs/Tasks/T011.md` §4。
- 结构特写要**低角度、正对开口**拍：纯俯瞰会被顶板挡住"三面墙 + 开口"（T011 踩过，见 §8 取景坑）。


---

## 2.8 T012 导航数据与导航可行性（VERIFIED — 2026-10-13）

```powershell
# 1) 生成导航数据（三步：不入树加分组/区域 → 入树烘焙 → 不入树赋回 .tres；约 15 s）
& $g --headless --path $p --script 'res://tests/tool_make_courtyard_nav.gd'
#    -> resources/nav/l_courtyard_mouse.tres（layer 1）/ l_courtyard_cat.tres（layer 2）
#       scenes/maps/l_courtyard.tscn 里出现 NavRegion_Mouse / NavRegion_Cat

# 2) T012 断言（79 条：双图参数 + 分层路径矩阵 + 结构判据 + 4 组真实胶囊行走）
& $g --headless --path $p --script 'res://tests/run_t012_navigation.gd' --quit-after 60000
#    -> SUMMARY|checks=79|failures=0  RESULT|PASS   EXIT=0

# 3) 包内复验
& $g --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
    --script 'res://tests/run_t012_navigation.gd' --quit-after 60000
#    -> SUMMARY|checks=79|failures=0  EXIT=0
```

- **分层**：鼠层（`navigation_layers = 1`）能穿 0.24 树根洞 / 溪边缝；猫层（`= 2`）同端点只能绕行，
  且**洞里没有猫的导航面**（结构判据）。
- **禁止**用瞬移或直接设位置"让寻路看起来成功"（`Docs/TechnicalDesign.md` §5）：断言必须包含真实 `AnimalBody` 逐帧行走。
- 视觉：`-- t012` 已实现，但运行时导航调试绘制**看不到**（见 §8）→ 记 NOT-RUN，别拿重复图当证据。


## 2.9 T013 调试入口与移动回归（VERIFIED — 2026-10-15）

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$p = 'E:\Reborn\Game\Reborn'

# 1) 断言：调试入口 159 条 + 移动回归 73 条
& $g --headless --path $p --script 'res://tests/run_t013_debug_entry.gd' --quit-after 60000
#    -> SUMMARY|checks=159|failures=0  RESULT|PASS   EXIT=0
& $g --headless --path $p --script 'res://tests/run_t013_movement_regression.gd' --quit-after 60000
#    -> SUMMARY|checks=73|failures=0   RESULT|PASS   EXIT=0

# 2) 截图 6 张（**不能加 --headless**）
& $g --path $p --script 'res://tests/tool_capture_render.gd' --quit-after 60000 -- t013
#    -> user://t013_{collision_on,collision_off,collision_player,path_cat,path_mouse,debug_hud}.png
#       成功判据：结尾有 CAP|done 且每张 save_result=0 (OK)（见 §8 静默退出坑）

# 3) 包内复验（用最终包；包内文本读取会退化，见 §8）
& $g --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
    --script 'res://tests/run_t013_debug_entry.gd' --quit-after 60000
#    -> SUMMARY|checks=159|failures=0   EXIT=0
```

- **调试按键**：`F1` 切猫 / `F2` 切鼠 / `F3` 碰撞线框 / `F4` 导航路径 / `F5` 调试 HUD
  （`project.godot` 里 5 个 `debug_*` 动作；断言用引擎常量 `KEY_F1..KEY_F5` 核对，并检查不与 WASD/空格/Shift/Ctrl 冲突）。
- **调试入口是独立场景**：`scenes/debug/debug_entry.tscn`；`l_courtyard.tscn` / `main.tscn` 里**不允许**出现调试节点
  （断言守着：0 个调试节点、0 个 `CanvasLayer`）。正式 HUD 属 T018。
- **改完 `project.godot` 立刻核对**：`git diff -- Game/Reborn/project.godot` + 跑 `run_t007_input.gd`（22/22 才算好）。
  本任务踩过：该文件被外部写成非引擎格式，`InputMap` 全空 → 五个套件大面积失败（详见 `Docs/Evidence/T013.md` §9）。
## 2.10 T014 生存状态与统一时间入口（VERIFIED — 2026-10-15）

 ```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$p = 'E:\Reborn\Game\Reborn'
$out = 'E:\Reborn\Builds\P0-Win64'

# 0) 新增了 class_name → 先 import（见 §8），再逐脚本 check-only
& $g --headless --path $p --import
& $g --headless --path $p --check-only --script 'res://scripts/systems/survival_controller.gd'   # 0

# 1) 断言 106 条
& $g --headless --path $p --script 'res://tests/run_t014_survival.gd' --quit-after 60000
#    -> SUMMARY|checks=106|failures=0  RESULT|PASS   EXIT=0

# 2) 包内复验
& $g --headless --main-pack "$out\RebornSelfTest.pck" `
    --script 'res://tests/run_t014_survival.gd' --quit-after 60000
#    -> SUMMARY|checks=106|failures=0   EXIT=0
 ```

- **统一时间入口**：按时间的系统只从 `WorldDirector.world_time` 取差（`SurvivalController.tick_to()`），
  **不要各自累加 `delta`** —— 一个渲染帧可能跑 0/1/2 次物理帧，各自累加会与世界时间漂移。
- **暂停不消耗**：世界时间由 `WorldDirector._process` 推进；树暂停（`get_tree().paused`）或显式门闩
  （`WorldDirector.time_advancing = false`）都会让它停 → `dt = 0` → 不消耗。
- **帧率无关**：`SurvivalController.UPDATE_INTERVAL = 0.2 s` 批量结算，但用**累计到的实际时间**；
  实测 30 / 60 / 144 Hz 跑 60 s 世界时间，饥渴消耗**完全一致**。
## 2.11 T015 消耗、警告与基础伤害（VERIFIED — 2026-10-15）

 ```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$p = 'E:\Reborn\Game\Reborn'
$out = 'E:\Reborn\Builds\P0-Win64'

& $g --headless --path $p --import
& $g --headless --path $p --check-only --script 'res://tests/run_t015_costs.gd'          # 0

# 1) 断言 93 条
& $g --headless --path $p --script 'res://tests/run_t015_costs.gd' --quit-after 60000
#    -> SUMMARY|checks=93|failures=0  RESULT|PASS   EXIT=0

# 2) 包内复验
& $g --headless --main-pack "$out\RebornSelfTest.pck" `
    --script 'res://tests/run_t015_costs.gd' --quit-after 60000
#    -> SUMMARY|checks=93|failures=0   EXIT=0
 ```

- **冲刺代价**：`sprint_stamina_per_sec` × **世界时间差**（不读 physics `delta`）；`spend_stamina()` 会重置
  "消耗后延迟"，所以**冲刺期间不回复**（与 `RegenDelay` 语义一致）。
- **双门控**：`Stamina ≥ sprint_min_stamina(5)` 才能**开始**冲刺；已经开始后跑到 **0** 才转行走（**保留基础移动**）。
- **警告 / 危机**：`≤ low_stat_threshold(25)` 只是警告（不扣血）；任一归零后各扣 1/s、两项均零 2/s；`Health` 不自动恢复。
- **跌落**：只算**落地前垂直速度**；`≤ fall_safe_vertical_speed(7 m/s)` 无伤，超过 `(v−7) × fall_damage_scale(10)`，上限 `max_health`。

- **测试侧两条坑**（写测试时踩到）：① `spend_stamina(x)` 是**扣减**不是赋值 —— 想把体力设成某值要用
  `spend_stamina(当前 − 目标)`，或直接赋值但要知道"消耗后延迟"从**上次 spend** 起算（直接赋值不重置延迟 → 测试期间体力会自动回复）；
  ② 期望位移要扣**加速段**：`walk_speed×t − 0.5·walk_speed²/max_acceleration`（实测 0.963 vs 期望 0.930）。
## 2.12 T016 交互检测与动作接口（VERIFIED — 2026-10-15）

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$p = 'E:\Reborn\Game\Reborn'
$out = 'E:\Reborn\Builds\P0-Win64'

& $g --headless --path $p --import          # 新增 class_name 后**必须**先 import，否则测试报 Identifier ... not declared
& $g --headless --path $p --check-only --script 'res://tests/run_t016_interaction.gd'   # 0

# 1) 断言 118 条（连续三次一致）
& $g --headless --path $p --script 'res://tests/run_t016_interaction.gd' --quit-after 90000
#    -> SUMMARY|checks=118|failures=0  RESULT|PASS   EXIT=0

# 2) 包内复验
& $g --headless --main-pack "$out\RebornSelfTest.pck" `
    --script 'res://tests/run_t016_interaction.gd' --quit-after 90000
#    -> SUMMARY|checks=118|failures=0   EXIT=0
```

- **目标接口是鸭子类型**：只 `has_method("query_/commit_/cancel_interaction")`，**不做类型转换**；`Interactable` 只是默认实现。
- **只查 `interactable` 层**：`intersect_shape`（球半径 = `interaction_range + probe_extra_range(0.5)`）+ `collide_with_areas = true` + **显式 mask**；
  **不要改动物的 `collision_mask`**（那是移动用的，T009/T010 断言锁定为只有 `world_static`）。
- **遮挡只认 `world_static`**：一次 `intersect_ray`（`collide_with_areas = false`）；草叶视觉遮挡、`safe_spot` 层都不算物理遮挡。
- **排序确定性**：`interaction_priority` 降序 → 距离升序 → ID 字典序；对外**只暴露一个** `current_target()`。
- **时长走世界时间**：`detector.tick(world_time)` 由身体每物理帧喂；暂停（`time_advancing = false`）时喂进来的值不前进 → 进度自然冻结。
- **事务幂等**：同一 `transaction_id` 第二次 `commit` **直接返回既有结果、不再调用目标**（`commit_call_count()` 保持 1）。

### 本任务踩到的坑（**会污染别的测试**）

1. **`Area3D` 自带 native `priority`（float）** → `@export var priority: int` 直接报 `Member "priority" redefined`。用 `interaction_priority` 这类带前缀的名字。
2. **`add_child()` 之后再设 `global_position`，物体会在原点存在一帧**：新节点与地面/身体重叠 → 引擎把**身体** depenetrate 推开。
   实测：加一个 2 m 外、根本碰不到的 `StaticBody3D`，身体仍从 `(0, 0.240127, 0)` 被推到 `(0, 0.238788, 0.187743)`（**0.1877 m**），
   于是"0.90 m 的目标"变成 1.09 m —— 断言看到 `range` 而不是 `occluded`。
   **修法：先设 `position` 再 `add_child()`。** 所有"平地 + 生成物"的夹具都要照做。
3. **组件每物理帧 `detect()` 时，`target_changed` 事件数不能硬断言"恰好 1 次"**（目标分两次加入就有两次切换）。
   改成"最后一次事件 = 当前目标" + "同目标重复检测事件数不变"。
4. **不要混用合成 `tick()` 与真实物理帧**：`press_interact()` 后用假时间推进、再让真实帧喂时间，`_last_world_time` 会被拉回 → 进度**倒退**。
   要证明"暂停不推进"，用真实时间推进一段（记进度）→ 关 `time_advancing` → 再推一段 → 比对。
5. **进度基准要可读**：暴露 `interaction_start_time()`；否则断言只能用"身体当前时间"近似（差一帧就差 0.03 进度）。

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

- **T003 已完成**（2026-10-13）：`.gitattributes` 与 LFS 追踪已建立，并做过"从零克隆 → 引擎实跑"的恢复点试验。见 `Docs/Evidence/T003.md`。
  注意：`migrate import` 会重写历史，推送需 `--force-with-lease`（推送前先用 `git log --oneline origin/main --not main` 确认远端无他人提交）。

---

## 5. Windows 导出（VERIFIED — 2026-10-13 解锁）

> 原阻塞（导出模板未安装）已由负责人在编辑器内安装解除。证据见 `Docs/Evidence/T007.md`。

### 5.1 导出命令

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
$out  = 'E:\Reborn\Builds\P0-Win64'

# 发布版（排除 tests/*）
& $g --headless --path $proj --export-release "Windows Desktop" "$out\Reborn.exe"

# 自检版（包含 tests/*，用于包内断言）
& $g --headless --path $proj --export-debug "Windows Desktop SelfTest" "$out\RebornSelfTest.exe"
```

- 退出码：**0**（两个预设）
- 成功判据：退出码 0 **且**产物实际存在（`Reborn.exe` 109,127,680 B、`Reborn.pck` 12,904 B）
- 日志：stdout（`savepack` 进度）

### 5.2 包内断言验证（**必须用编辑器二进制**）

```powershell
& $g --headless --main-pack "$out\RebornSelfTest.pck" `
    --script 'res://tests/run_t002.gd' --quit-after 1200
# -> SUMMARY|checks=18|failures=0  RESULT|PASS   EXIT=0

& $g --headless --main-pack "$out\RebornSelfTest.pck" `
    --script 'res://tests/run_t007_input.gd' --quit-after 20000
# -> SUMMARY|checks=22|failures=0  RESULT|PASS   EXIT=0
```

### 5.3 启动独立程序

```powershell
Start-Process "$out\Reborn.exe"      # 开窗口
# 关闭： (Get-Process Reborn).CloseMainWindow()  -> 退出码 0
```

### 5.4 ⚠ 导出产物的命令行限制（实测，重要）

**导出产物会拒绝 `--script` 与位置参数**，引擎自己给出的原因：

```
ERROR: Scene path was specified on the command line, but this Godot binary was
compiled without support for path overrides. Aborting.
To be able to use it, use the `disable_path_overrides=no` SCons option when compiling Godot.
```

即**官方导出模板编译时带了 `disable_path_overrides=yes`**，这是 Godot 的**有意设计**。

对照证据：

| 场景 | 退出码 | 报错 |
|---|---:|---|
| 编辑器 + 无效脚本路径 | **1** | `Can't load script` ✅ 有效 |
| 导出产物 + 无效脚本路径 | **0** | 无 ❌ **静默忽略** |
| 导出产物 + 位置场景参数 | **1** | `compiled without support for path overrides` |

**后果**：想在打包产物内跑断言，只能用 §5.2 的 `--main-pack` + 编辑器二进制方案；
或改成"自检场景/autoload"写进包内（未采用）。

### 5.5 ⚠ `debug/export_console_wrapper` 是枚举

Godot 4.7 中该选项为 `No=0 / Debug Only=1 / Debug and Release=2`。
**写 `1` 时 release 导出不会生成 `.console.exe`**（已实测踩到）。需要 release 的控制台包装必须写 `2`。

### 5.6 其它导出注意

- `binary_format/embed_pck=false` → exe 必须与 `.pck` 同目录。
- 发布预设正式对外时应把 `export_console_wrapper` 改回 `0`。
- `application/icon` 当前为空，用 Godot 默认图标。

---

## 6. 视觉验证（VERIFIED — 2026-10-13 可用）

```powershell
& node "E:\claude-vision-skill\vision.js" "<图片绝对路径>" "<中文检查问题>"
```

- 退出码：**0**（可用）
- **可信性已验证**：对已知答案图 `Art/Probes/vision_probe_red_blue.png`（64×32 左红右蓝）提问，答对
  （"红色，蓝色"）。**先用已知答案验证工具，再用它下结论。**
- 配置在 `E:\claude-vision-skill\.env`（该目录 `.gitignore` 含 `.env`）：
  `DASHSCOPE_BASE_URL` / `DASHSCOPE_API_KEY` / `VISION_MODEL` / `VISION_MAX_TOKENS`。
  **key 不记录、不入库、不进日志。**
- ⚠ **`DASHSCOPE_BASE_URL` 必须带 `/v1`**。实测：

  | 请求 | 结果 |
  |---|---|
  | `POST /chat/completions` | **404** |
  | `POST /v1/chat/completions` | **200** |
  | `GET /v1/models` | **200** |

- 该网关用 `http://`（非 https）直连 IP；**排除代理**（`NO_PROXY=<ip>`），否则被拦。
- 原配置（opencode.ai 网关 + `mimo-v2.5`）实测 403 订阅失效，已备份为 `.env.bak_before_reborn`。

### 6.1 ⚠ 不要用屏幕截图做视觉验证

实测踩到：屏幕截图依赖**窗口可见、在前台、未被遮挡、DPI 缩放正确**。
游戏窗口曾处于 `(-25600,-25600)` 且客户区 `0x0`（Windows 最小化位置），
截到的是桌面背景，导致两次视觉分析**结论互相矛盾**。

**改用引擎自己导出渲染帧**（`Game/Reborn/tests/tool_capture_render.gd`）：

```powershell
# 注意：不能用 --headless（无头是 dummy 渲染器，没有真实画面）
& 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
  --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_capture_render.gd' --quit-after 400
# 输出 user://render_capture.png -> %APPDATA%\Godot\app_userdata\Reborn\render_capture.png
```

同时打印**客观像素统计**（`unique_colors` / 亮度跨度 / 与 clear color 的相似像素占比），
比语义描述更可靠。实测判据：修复后 `unique_colors=2151`、`range=0.5776`、`clear_color_like_ratio=0.0000`。

**影响**：Godot 的画面验收（T002/T005/T006/T007）现可正常进行。
**数据断言（无头运行 + 读回数值）不依赖视觉工具，一直可照常通过。**

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
- **新增/修改带 `class_name` 的脚本后，无头运行前必须先跑一次 `--import`**：全局类名注册在
  `.godot/global_script_class_cache.cfg`，否则引用它的脚本会报
  `Parse Error: Identifier "Xxx" not declared in the current scope`（2026-10-13 实测踩到）。
- **`AnimationPlayer.play()` 在 Godot 4.7 返回 void**：判断是否在播要查 `is_playing()` / `current_animation`，
  不要读返回值（`var e := ap.play(...)` 会报 "Cannot get return value of call to play() because it returns void"）。
- **动画轨道插值的真实 API 是 `Animation.rotation_track_interpolate(track, t)`**（同族还有
  `position_/scale_/blend_shape_/value_/bezier_track_interpolate`）；**没有**通用的 `track_interpolate`（实测报错）。
- **`Skeleton3D.get_bone_pose_rotation()` 返回"含静止位姿"的父骨相对旋转**：t=0 时腿骨就已经是 rest（实测 −90°），
  想断言"作者转了多少度"要读**动画轨道键值**，不要读姿态角。

---

- **读渲染帧前必须等"真正画完的那一帧"**：只 `await process_frame` 若干次，读到的内容可能仍是**上一帧** ——
  实测在**切换相机**后，`tp`/`fp` 两张图**文件名不同、内容 MD5 完全相同**（而日志里活动相机已切换）。
  正确写法：`await RenderingServer.frame_post_draw`（等 2 次更稳）再 `get_texture().get_image()`。
  **判据：换机位/换视角后先用 MD5 或像素差确认两图真的不同，再拿去视觉判读**（"文件存在 + 名字对"不代表内容对）。
- **场景实例的"子节点属性覆盖"不会被 `PackedScene.pack()` 序列化**（T009 实测）：脚本里给实例的子节点
  （如 `Player/Camera3D.current`）赋值，工具自检通过、但存出的 `.tscn` 里**没有这一行**，重载回来就丢了。
  要在场景里表达，就用**该节点自己的导出属性**（T009 的 `AnimalBody.make_camera_current` 就是为此加的）。
- **不要对"未入树"的节点调用 `Node.get_path()`**：会刷满 `Cannot get path of node as it is not in a scene tree.`，
  而且返回空串会让"节点集合比对"变成**永远相等**的假通过。自己用父路径拼（见 `tool_set_lab_player.gd`）。
- **视觉工具会漏小/暗目标**：T009 低顶那张 1280×720 帧里，蹲姿猫只占约 150 px 且在阴影中，
  视觉模型两次都回答"板下是空的"。**不要就此下"看不见"的结论** —— 客观做法：
  同一机位拍"有/无主体"两张、逐像素求差拿到变化区域的外接框，再把该框裁出来单独提问（T009 就是这么做的）。
- **台阶（自实现 MaxStepHeight）两个实测坑**（详见 `Docs/Evidence/T009.md` §5，代码里也有注释）：
  ① 落点高度**不能**用运动测试的 `get_travel()`：它会在接触前停下，且形状越小停得越早
     （3 cm 台阶：鼠高 2.655 mm、猫 0.249 mm）→ 小物种的台阶会被算高而拒绝；
  ② **可站立面的阻挡不算台阶**（斜坡）：判据必须只看"真正阻挡本次运动"的接触（`n·dir < 0` 且 `n.y ≥ cos45°`），
     少了 `n·dir < 0` 这一条，连正常台阶都上不去（脚下地面的接触会被误判）。
- **试验世界要分道布置**：T009 第一次把低顶和 50 cm 高台放在同一条 x=6 线上，
  平台助跑直接撞进低顶里（猫被压在地面、用例全废）。分区之前先看 `tool_make_move_fixtures.gd` 头部说明。
- **取景决定能否判读：相机要"正对"主体所在的通道**（T010 实测）：`t010_tunnel_tp` 第一版相机横向偏了 1.6 m，
  视线在洞面处的 x = 2.78 落在洞口（2.38–2.62）之外 → **主体被洞口侧壁完全遮住**，视觉模型两次都答"洞里是空的"。
  判据不是"图存在 / 文件名对"，而是**"视线几何能不能真的看到主体"**；改成正对洞口（x 偏移 0）后立刻判读成功。
- **不许为了过测试改产品参数**：T010 的鼠洞是硬约束（鼠过得去、猫过不去）。若鼠过不去，先查台阶/胶囊判据
  （T009 的两个坑），**拿到亲测依据才动判据或车道对中**；`resources/species/*.tres` 绝不因测试而改。
- **`Node.add_to_group(g)` 默认 `persistent = false`** → **不会被 `PackedScene` 序列化**：T011 生成器写在节点上的分组
  存进 `.tscn` 后全丢（断言读到 `[]`）。要用分组做数据标记（区域/掩体/补给点），必须写 `add_to_group(g, true)`。
- **非 headless 捕获可能"静默半途退出"**：T011 实测同一命令只拍完前 3 个视角就结束，**退出码仍是 0**、也没有 `CAP|done`；
  重跑即完整。**捕获的成功判据 = 打印出 `CAP|done` 且每张都有 `save_result=0 (OK)`**，只看退出码会漏掉"只拍了一半"。
- **大坐标下的浮点容差**：关卡尺度到 36 m 时 float32 的间隔约 4e-6，用 `1e-6` 做"严格相等"会误杀自己。
  统一用 `GEO_EPS = 1e-4`（0.1 mm）。另外**出生点那种"正好站在地面上"的位置**做 `intersect_shape` 会把地面接触算 1 次重叠，
  探测胶囊要**收紧 1 cm**（`shrink`）。
- **导航烘焙的几何源**：`NavigationRegion3D.bake_navigation_mesh()` 按 `geometry_source_geometry_mode` 取几何 ——
  `ROOT_NODE_CHILDREN`（默认）只认**区域自己的子节点**（把几何放在兄弟节点上烘出 **0 面**）；
  要让**多张图烘同一套几何**，用 `GROUPS_WITH_CHILDREN` + `geometry_source_group_name`（T012 用分组 `nav_source_courtyard`）。
- **烘焙格必须与地图格一致，且不能太粗**：不一致会刷 `cell size mismatch … rasterization errors`；
  `cell 0.05` 会把 **0.24 的窄缝吃掉**（路径改绕行），`region_min_size` 相对 cell 太小还会让 `map_get_path` **恒空**。
  T012 口径：`cell 0.03 / rmin 0.02` + `project.godot` 的 `[navigation] 3d/default_cell_size/height` 同步。
- **运行期换 navmesh 后同进程查询不可靠**：给 region 换 navmesh 再烘，**同进程等 600 帧仍 0 路径点**；
  **落盘 `.tres` 后新进程加载**第 **1** 帧就有路径 → 烘焙与断言必须**分开进程**做（工具只烘焙+落盘，断言脚本另跑）。
- **导航调试绘制在运行时看不到**：`NavigationServer3D.set_debug_enabled(true)` 调用成功，但捕获出的鼠/猫两张图 **MD5 逐字节相同**
  → 不要拿"名字不同"当视觉证据；T012 的判定改用**结构判据**（洞里有没有导航面）+ 路径矩阵 + 真实胶囊行走。

- **引擎的"显示碰撞形状"在命令行运行下画不出来**（T013）：`Viewport.DEBUG_DRAW_*` **没有碰撞形状项**
  （只有 DISABLED/UNSHADED/LIGHTING/OVERDRAW/WIREFRAME）、`PhysicsServer3D` **没有任何 debug 方法**；
  唯一相关开关是 `SceneTree.debug_collisions_hint`，但打开它之后**同机位两张截图逐字节相同**（MD5 `64DC75C7…`）。
  要在本环境看到碰撞形状只能**自己画线框**（并如实标注"不是引擎调试视图"）；编辑器"调试运行"下是否有画面本环境无法验证。
- **`NavigationAgent3D` 是 `Node`，不是 `Node3D`**（T013）：它没有自己的变换，位置取自**父节点**；直接给它
  `global_position` 赋值会报 `Invalid assignment of property or key 'global_position' on NavigationAgent3D`。
  要控制起点就挂一个定位用的 `Node3D` 锚点，把代理挂在锚点下。
- **代理路径可能短暂为空，而同一时刻服务端查询有完整路径**（T013）：切完物种或只跑 `process` 帧时实测 `raw_path=0`。
  调试可视化要兜底：路径点数 < 2 时退回 `NavigationServer3D.map_get_path()`（同图同层、起点=玩家位置），否则线会一闪一闪。
- **`.pck` 里的场景不是可读文本**（T013）：包内 `FileAccess.open("res://x.tscn")` 读到 **0 字节**，
  所以"读文件文本做断言"在包内**退化成恒真**。主判据要用**运行期结构**（实例化后数节点、查 `get_script().resource_path`），
  文本判据只作补充并把 `len=` 打出来。
- **"站稳"判据必须要求连续若干帧**（T013）：只判一帧会被"出生瞬间刚好落地、下一帧又被顶回空中"骗过去 ——
  T013 实测因此拿到过"上了台阶 y 反而下降 0.2 m"的假数据。写成"连续 10 帧在地面且速度≈0"，站不稳就**报错并打印轨迹**。
- **并发写手会持续改同一个文件**（T013）：本任务遇到 `project.godot` 被外部写成非引擎格式（`debug_switch_cat=4194332 # F1`）→
  InputMap 全空、T007/T009/T010/T011/T012 大面积失败；连续 3 次 `EDIT_TAG_MISMATCH` 后宿主会**停止该路径编辑**。
  正确做法：先 `git status/diff` + 读文件看**当前真实内容**，别硬重试；改完配置类文件立刻跑一条对应断言（`run_t007_input.gd` 22/22）。

- **不要用"等世界时间前进"的循环去测暂停**（T014）：树暂停时 `world_time` **根本不走**，
  这种循环会死等到 `--quit-after` 才退出（现象：日志停在半路、退出码仍是 0）。
  测暂停要**按固定帧数等待**，并同时断言"**世界时间增量为 0**"与"**数值不变**"（两条都查，避免假通过）。
- **新增 `class_name` 的脚本必须先 `--import`**（T014 再次踩到）：否则逐个 `--check-only` 会报
  `Identifier "Xxx" not declared in the current scope`，看着像自己写错了，其实是全局类还没注册。

---

## 9. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-12 | 首次建立。锁定 Blender/Node/Git/Python 路径与版本；UE 相关全部标 PENDING/BLOCKED。 |
| 2026-10-13 | **引擎切换 Godot 4**。新增 §2 Godot 命令（无头运行、`--check-only`、能力清单）；§5 导出改为 PENDING 并定位真阻塞为导出模板缺失；新增 §8 排查方法坑；§4.1 记录代理推送路径。 |
| 2026-10-13 | **T009 完成**。新增 §2.6 移动验收与试验世界命令（含"捕获不能加 `--headless`"）；§8 补 5 条实测坑（pack 不序列化实例子节点覆盖、`get_path()` 未入树报错导致假通过、视觉工具漏小目标→改用差异像素法、台阶两处判据坑、试验世界必须分道）。 |
| 2026-10-13 | **T010 完成**。§2.6 改名并补 `-- t010` 捕获与包内两条命令（含"捕获的 `--quit-after` 要给足"）；§8 补 2 条实测坑（取景/视线几何决定可判读性；不许为了过测试改产品参数）。 |
| 2026-10-13 | **T011 完成**。新增 §2.7 生态灰盒关卡命令（生成器 + 210 条断言 + `-- t011` 捕获 7 视角 + 包内复验）；§8 补 3 条实测坑（`add_to_group` 默认非持久 → 分组不会被序列化；非 headless 捕获可能半途静默退出、必须看 `CAP|done`；大坐标浮点容差用 `GEO_EPS = 1e-4`）。 |
| 2026-10-13 | **T012 完成**。新增 §2.8 导航数据与导航可行性命令（烘焙工具 + 79 条断言 + 包内复验）；§8 补 3 条实测坑（烘焙几何源只认区域子节点/分组模式、烘焙格与地图格必须一致且过小的 cell 会吃掉窄缝、运行期换 navmesh 后同进程查询不可靠要分进程）。 |
| 2026-10-15 | **T013 完成**。新增 §2.9 调试入口与移动回归命令（159+73 条断言 + `-- t013` 六张截图 + 包内复验）；§8 补 6 条实测坑（引擎碰撞显示运行时画不出来→MD5 判据、`NavigationAgent3D` 无变换、代理路径短暂为空要服务端兜底、`.pck` 内文本不可读导致断言退化、站稳判据必须连续帧、并发写手覆盖 `project.godot`）。 |
| 2026-10-15 | **T014 完成**。新增 §2.10 生存状态与统一时间入口命令（106 条断言 + 包内复验）；§8 补 2 条实测坑（测暂停不能用"等世界时间前进"的循环、`class_name` 新脚本先 `--import`）。 |
| 2026-10-15 | **T015 完成**。新增 §2.11 消耗、警告与基础伤害命令（93 条断言 + 包内复验 + 两条测试侧坑：`spend_stamina` 是**扣减**不是赋值；期望位移要扣**加速段**）。 |
| 2026-10-15 | **T016 完成**。新增 §2.12 交互检测与动作接口命令（118 条断言 + 包内复验 + 五条实测坑：`Area3D` 自带 native `priority`；`add_child` 后设 `global_position` 会让物理体在原点存在一帧、把身体推开 0.1877 m；每帧 `detect()` 让事件计数不能硬断言；合成 `tick()` 与真实帧混用会让进度倒退；进度基准要可读）。 |
