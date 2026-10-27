# ART06 证据：菜单猫主视觉整理

执行日期：2026-10-27（本机系统时钟）｜执行者：PI-Desktop fixer（单 agent，无递归委派）
引擎：Godot **4.7.2.stable.official.ed1daf0bf**（`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`）
工程：`E:\Reborn\Game\Reborn`｜分支：`art/modeling-pipeline`｜**未提交、未推送**（提交由主 agent 按授权统一处理）

起点 `git status`：工作区只有一处**他人未跟踪文件** `visual-options.html`（用户视觉选项展板），本任务**未读写/未改动**它，也未 reset / checkout / clean。

## 1. 改了什么（3 个文件，196 insertions / 72 deletions）

| 文件 | 改动 |
|---|---|
| `Game/Reborn/scripts/core/main_entry.gd` | ① `_build_showcase()` 从「每个物种一个、并排」改为「**只展示当前选中的物种**」（主视觉）；② 新增 `_hero_config()`（选中项 → 配置 → 无视觉资产时退回第一个有模型的物种）、`_max_capsule_height()`、`_on_menu_selection_changed()`（选中变了就换主视觉，仅在菜单可见时重建）、`showcase_nodes()`（只读取证接口）；③ 菜单相机常量：`MENU_CAM_OFFSET (0.86,0.42,0.80)→(0.66,0.42,0.61)`、`MENU_CAM_LOOK y 0.15→0.18`、`MENU_CAM_H_OFFSET -0.05→-0.16→**-0.05**`（中间试过 -0.16，实测把猫推到压右栏卡片，回退）、`MENU_SHOWCASE_SPREAD`→`MENU_SHOWCASE_DEPTH_SCALE` |
| `Game/Reborn/scripts/ui/main_menu.gd` | ① 新增信号 `selection_changed(species_id)`，`select_species()` 只在**真的换人**时发；② 右栏「未来开放」从 **3 张 72 px 占位卡**收成**一行小字**（`HFlowContainer` + `_make_future_row()`，原 `_make_locked_card()` 删除、`COLOR_CARD_LOCKED` 随之删除）；③ 「MVP Demo：**2** 个物种」改为按 `_configs.size()` 推 |
| `Game/Reborn/tests/tool_capture_art04.gd` | 新增**客观取景量**：`CAP|art04|layout|`（左栏右边界 / 卡片左边界，从真实控件矩形读）、`CAP|art04|<tag>|showcase|`（每个展示模型的**脚点/头点投影** px、占比、`in_gap`）；新增**镜像机位** `_save_mirrored()`（绕到主视觉另一侧拍一张再原样还原相机）用于朝向核对。原有机位与文件名**未改**，输出仍 `user://art04_*.png` |

**没有**改：`resources/species/*.tres`（猫仍是 `sm_cat_002.glb`，**未**碰 `sm_cat_004.glb`）、玩法/生命周期/存档/关卡几何/导航/碰撞/光照/动画/导出预设。

## 2. 命令与退出码

```powershell
$g    = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'

# 静态门
& $g --headless --path $proj --check-only --script 'res://scripts/core/main_entry.gd'      # exit 0
& $g --headless --path $proj --check-only --script 'res://scripts/ui/main_menu.gd'         # exit 0
& $g --headless --path $proj --check-only --script 'res://tests/tool_capture_art04.gd'     # exit 0

# 视觉取证（**非 headless**，1280×720 窗口）
& $g --path $proj --script 'res://tests/tool_capture_art04.gd' --quit-after 8000 -- art04  # exit 0
```

取证产物（`user://` = `C:/Users/<user>/AppData/Roaming/Godot/app_userdata/Reborn/`）
→ 拷进仓库：`Art/Probes/menu_cat_first_{before,after}_menu.png`、`..._before_species.png`、
`..._after_species.png`、`..._after_species_mouse.png`、`..._after_species_mouse_mirror.png`（PNG 走 LFS）。
每张都打出 `save_result=0 (OK)`；7 张全部 OK，日志 **0 条 `SCRIPT ERROR`**。

## 3. 客观取景量（同一工具、同一分辨率，改动前后）
| 量 | 改动前 | 改动后 | 说明 |
|---|---|---|---|
| `showcase|count` | **2**（Cat + Mouse 并排） | **1**（仅选中物种） | 鼠的信息改由右栏卡片（每个卡片一个 `SubViewport` 实时 3D 预览）承担 |
| 猫 `pos` | `(-11.0, 0.0, 16.0)` | 同 | 仍锚在 `MENU_FOCUS` 吸地射线的落点 |
| 相机→主体距离 | **1.260 m** | **0.992 m** | 机位更近 |
| 猫 脚点/头点投影 | feet (572,437) / head (565,175) | feet **(673,476)** / head **(678,139)** | |
| 猫 `px_h`（胶囊契约高度 0.48 m 的投影） | **261 px = 0.363 屏高** | **336 px = 0.467 屏高** | +28.7% |
| 猫 脚点 x 是否在 UI 空档内（480…828） | true（572，偏左） | **true（673，接近空档中心 654）** | |
| 选到鼠后的主视觉 | 不适用（两只同时在） | `Showcase_Mouse`，dist 0.707，feet (689,616)，`in_gap=true` | 同一套代码换人，**零物种名分支** |

**注意（实测口径）**：`px_h` 用的是 `SpeciesConfig.capsule_height()`（0.48 / 0.18 m 的**契约高度**），
猫的实际模型高 0.310 m → 屏幕上真实高度约为 `px_h × 0.310/0.48`（改后 ≈ 217 px ≈ 0.30 屏高，改前 ≈ 168 px ≈ 0.23）。
所以 `px_h` 是**相对可比**的指标，不是模型真实像素高。

**踩过的口径坑（已写进工具注释）**：先用网格 AABB 投影，蒙皮网格的节点 AABB 带骨骼缩放
（`CAP|art04|mesh|CAT_BODY_001|local=(0.305,0.310,0.542)|world=(0.023,0.011,0.020)`）→ 会把 0.31 m 的猫算成 1 cm。
该口径已废弃，改用脚点/头点投影。

## 4. 视觉判读（`node E:\claude-vision-skill\vision.js`，逐字引用关键结论）

| 图 | 判读结论（摘要） | 判定 |
|---|---|---|
| `menu_cat_first_before_menu.png` | 3D 动物 **2 只**：猫（屏高 35%~40%，中偏左）+ 鼠（约 5%，偏暗）；标题/四按钮完整；视觉重心偏左 | 基线 |
| `menu_cat_first_before_species.png` | 猫 + 鼠都在场；猫 35%~40%、鼠 2%~3%；无重叠/遮挡 | 基线 |
| `menu_cat_first_after_menu.png` | **「画面中仅有 1 只 3D 动物实体模型，是一只橘白相间的猫」**，位于**画面正中央偏下**；标题「轮生/REBORN」与**四个按钮（开始游戏/物种选择/设置/退出）完整可见、无遮挡**；右侧**猫与鼠两张卡片都在**；**「没有压到」**左按钮或右卡片；视觉重心 = **中央 3D 猫** | **PASS**（A1/A3/A4/A5） |
| `menu_cat_first_after_species.png` | 中央 1 只猫（35%~40%）；「进入世界/返回」与两张卡片文字完整；**「未来开放」已变成一行灰色小字**（兔/鸟/狐）；**「无明显排版缺陷」** | **PASS** |
| `menu_cat_first_after_species_mouse.png` | 选到鼠后主视觉换成鼠卡片高亮；鼠**能看出是鼠**、贴地不悬空；但**「占比不到 10%，作为视觉中心略显单薄」** | PASS（功能）/ 观感偏差已记录（见 §6） |
| `menu_cat_first_after_species_mouse_mirror.png` | 镜像机位朝向核对 | **NOT-VERIFIED**（两次判读互相矛盾，见 §6） |

## 5. 回归（全部 `exit 0`、`failures=0`、日志 `SCRIPT ERROR` 计数 0）

| 套件 | 断言 | 退出码 | 备注 |
|---|---|---|---|
| `run_t008_species` | 118/118 | 0 | |
| `run_t009_cat_movement` | 81/81 | 0 | |
| `run_t010_mouse_movement` | 95/95 | 0 | |
| `run_t011_greybox` | 210/210 | 0 | |
| `run_t012_navigation` | 79/79 | 0 | |
| `run_t018_hud` | 73/73 | 0 | |
| `run_t021_capture` | 279/279 | 0 | |
| `run_t022_loop` | 168/168 | 0 | |
| `run_t026_cover` | 96/96 | 0 | |
| `run_t027_ecology` | 96/96 | 0 | |
| `run_t030_lifecycle` | 111/111 | 0 | `main.tscn` 仍是「只有根节点 + MainEntry」不受影响 |
| `run_art02_cat` | 72/72 | 0 | |
| `run_art03_mouse` | 45/45 | 0 | |
| `run_art05_settings` | 20/20 | 0 | 菜单设置面板链路 |
| `run_art05_input`（**非 headless**） | 20/20 | 0 | 键盘/鼠标真实 GUI 命中；`Card_<id>` 名字与按钮文案未变，点击坐标取动态矩形 |

合计 **1,463 条**断言，0 失败。

**NOT-RUN（本轮未重跑，原因）**：`run_t002/t005/t006/t007/t013×2/t014～t017/t019/t020/t023/t024/t025/t029`、
`tool_t028_walkthrough` —— 本任务未触碰它们依赖的代码路径（关卡几何/导航/物理/感知/捕获/攻击/生命周期），
上一轮全量 34 套为绿（`Docs/Handoff.md`）。`tool_t028_walkthrough` 的 `W4_players_survived` 是**既有失败**（Handoff 已记录，与本次无关）。

## 6. 未验证 / 发现 / 阻塞

1. **NOT-VERIFIED：鼠作主视觉时的模型朝向。**
   选到鼠后 vision 对同一张图判「尾部/背部朝向镜头（高置信）」；把相机镜像到另一侧再判，仍答「尾部/背部（高置信）」——
   **两次互相矛盾**，说明该尺度（<10% 屏高、偏暗）下视觉判读不可靠。
   连续两次修复尝试后按规则停止：**不编造结论**。若确为「背对观众」，成因是 `visual_scene` 的本地前向与
   `look_at` 假设的「模型面朝 −Z」不一致（猫符合该假设：两张猫图都判为正面），修法要么重导资产、要么加
   `SpeciesConfig` 方向的配置字段 —— 两者都超出本任务范围，交后续任务。
2. **观感偏差：鼠当主视觉偏小。** 已用 `MENU_SHOWCASE_DEPTH_SCALE`（体型差前移）把它从「几乎看不见」提到
   `<10% 屏高`，但鼠本身只有 0.135 m 体长，进一步放大就要改相机或改模型比例 —— 未做。
3. **NOT-RUN：真实按键输入**（项目禁止盲发按键）；菜单交互只用引擎内注入（`run_art05_input`，非 headless）。
4. **未做**（本次范围外）：环境密度/纵深、动态光照/接触阴影、HUD 与结算页细节、第三人称镜头平滑、猫的攻击/扑击动画（P6）。
5. **P6 阻塞不变**：猫只有 `Idle/Walk/Run`（`sm_cat_002.glb`）；`sm_cat_004.glb` 是**未通过步态审计**的候选，**禁止切换**；
   正式猫骨骼与攻击动作仍需有授权美术资源 → **blocked（需负责人授权资产/美术）**，本轮不伪装达标。
6. **用户概念展板** `visual-options.html` 未纳入需求，也未改动。

## 7. 恢复入口

- 仅回退相机：`MENU_CAM_OFFSET=(0.86,0.42,0.80)`、`MENU_CAM_LOOK=(0.0,0.15,0.0)`、`MENU_CAM_H_OFFSET=-0.05`，重跑 §2 取证命令。
- 完全回退到 ART04 行为：`git checkout -- Game/Reborn/scripts/core/main_entry.gd Game/Reborn/scripts/ui/main_menu.gd`（会一并丢弃本次展示改动；
  取证工具新增的度量函数可保留，不影响生产逻辑）。
- 复现证据：§2 两条命令 + §4 的 5 张 PNG + vision 命令
  `node E:\claude-vision-skill\vision.js Art\Probes\menu_cat_first_after_menu.png "<问题>"`。
