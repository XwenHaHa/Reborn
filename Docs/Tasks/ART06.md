# ART06 任务规格：菜单猫主视觉整理（纵向切片第一个视觉增量）

状态：**done（awaiting 负责人确认是否作为正式基线；不是 P6 approved 美术）**
执行日期：2026-10-27（本机系统时钟）
范围授权：负责人已批准「猫主展示庭院纵向切片」；本任务只做其中的**第一个最小增量**。

## 1. 目标

把「开场/物种选择」画面从「两个物种并排站在同一个机位里」整理成**猫为主视觉**：
当前选中的物种占画面中央当主角，鼠**仍然保留可选卡片**（卡片里本来就有实时 3D 预览）。

用户概念展板（工作区根的 `visual-options.html`）**不是**已实现需求，本任务不按概念图改造环境/森林/菜单功能。

## 2. 前置与证据

- `Docs/Handoff.md`（ART04 菜单、ART05 第三人称/设置）
- `Docs/Evidence/ART04.md` §取景（菜单相机 / 展示模型 / 卡片预览的既有实现）
- 基线取证：`tests/tool_capture_art04.gd`（**非 headless**）在改动前跑一次，留 `Art/Probes/menu_cat_first_before_*.png`

## 3. 允许改动的真源路径

| 路径 | 改动 |
|---|---|
| `Game/Reborn/scripts/core/main_entry.gd` | 菜单相机常量（`MENU_CAM_OFFSET` / `MENU_CAM_LOOK` / `MENU_CAM_H_OFFSET`）；`_build_showcase()` 改为「只展示当前选中物种」；新增 `_hero_config()` / `_max_capsule_height()` / `_on_menu_selection_changed()` / `showcase_nodes()` |
| `Game/Reborn/scripts/ui/main_menu.gd` | 新增信号 `selection_changed`；`select_species()` 发信号；右栏「未来开放」从 3 张占位卡收成一行小字；物种数文案改为按配置推 |
| `Game/Reborn/tests/tool_capture_art04.gd` | 取证机位不变，**新增客观取景量**（脚点/头点投影、UI 栏边界）与**镜像机位**（朝向核对）；不伪造任何结果 |

## 4. 硬约束（不得越界）

- 猫/鼠一律**配置驱动**：不在系统代码写物种名分支；本任务新增代码零物种名。
- 不改玩法资源、`LifeCycle`/`GameState`、关卡几何/导航/碰撞、补给收益、感知/捕获/攻击、解锁规则、`T029` 冲刺默认值。
- 不碰导出预设/包发布/推送；不下载、不购买、不上传、不覆盖既有资产。
- 不换猫的绑定资产：`cat.tres` 仍指 `sm_cat_002.glb`；`sm_cat_004.glb`（步态审计未通过候选）**禁止**切换。
- 视觉结论必须有**非 headless** 截图 + `node E:\claude-vision-skill\vision.js` 判读；无头只能证明脚本/数值。

## 5. 步骤

1. 基线：非 headless 跑 `tool_capture_art04.gd -- art04`，拷图，vision 判读。
2. 只改呈现：展示排序/焦点 + 相机视距；`menu` 排版。
3. 复跑同一取证工具，记录 `CAP|art04|showcase|` 的脚点/头点投影与 `in_gap`。
4. 回归：`run_art05_input`（非 headless）+ `run_t008/t009/t010/t011/t012/t018/t021/t022/t026/t027/t030/art02/art03/art05_settings`。
5. 写 `Docs/Evidence/ART06.md`（命令、退出码、截图、NOT-RUN/NOT-VERIFIED），更新 `Docs/Tasks.md`、`Docs/Handoff.md`。

## 6. 用例（验收）

| 用例 | 判据 |
|---|---|
| A1 猫是主视觉 | `showcase_nodes()` 数量 = 1，`id` = 当前选中物种；默认（启动）= 排序第一的物种（猫） |
| A2 猫更大 | 脚点/头点投影出的 `px_h` 相对基线上升（改动前后同一工具、同一分辨率测量） |
| A3 不压 UI | 投影脚点 x 在左栏右边界与卡片左边界之间；vision 判读「无遮挡」 |
| A4 鼠仍是可选卡片 | 右栏两张卡片都在；切到鼠后主视觉换成鼠（同一套代码，无物种名分支） |
| A5 标题/主按钮可见 | vision 逐字确认「轮生 / REBORN / 开始游戏 / 物种选择 / 设置 / 退出 / 进入世界 / 返回」 |
| A6 回归不破 | 上列套件全绿 + 日志 0 条 `SCRIPT ERROR` |
| A7 无伪造 | 截图由引擎窗口渲染；`NOT-VERIFIED` 项如实标注 |

## 7. 失败恢复

- 改动全部集中在 3 个文件、纯文本：`git diff` 可逐行回退；相机常量改回
  `MENU_CAM_OFFSET=(0.86,0.42,0.80)`、`MENU_CAM_LOOK=(0,0.15,0)`、`MENU_CAM_H_OFFSET=-0.05`、
  并把 `_build_showcase()` 恢复成「每物种一个」即回到 ART04 行为。
- 若画面判读不通过：先只回退相机常量（不动排版），重跑取证；仍不通过则整体回退，只保留基线证据。
- 若窗口渲染不可用（无 GPU/无显示）：记录具体阻塞，本任务降级为 blocked，不用无头结果冒充视觉验收。
