# ART08 证据：展板式菜单与物种选择布局

状态：awaiting-review（布局/交互通过；展板整体视觉未通过）
日期：2026-10-28
分支：`art/modeling-pipeline`

## 改动

- `Game/Reborn/scripts/ui/main_menu.gd`：左侧根节点改为 `LeftPanel`，按钮组命名为 `MainButtons` / `SpeciesButtons`；右侧列表根节点改为 `SpeciesRail`；微调左侧垂直间距和右侧栏宽度/上下边距。
- `Game/Reborn/tests/run_art08_board_contract.gd`：递归查找 UI 节点，并按 `MainEntry` 实际属性检查菜单相机和补光。
- `Game/Reborn/tests/tool_capture_board_visual.gd`：真实入口 1280x720 非 headless 取证。
- 四张改后窗口图：`Art/Probes/art08_after_menu/`。

未改 `MainEntry` 的相机参数、正式角色资产、关卡几何、玩法、碰撞、导航或 ART07 文件。

## 验证

| 命令 | 结果 |
|---|---|
| `run_art08_board_contract.gd --check-only` | exit 0 |
| `run_art08_board_contract.gd` | 9/9，0 failures，exit 0 |
| `run_art05_settings.gd` | 20/20，0 failures，exit 0；日志有损坏配置文件测试预期的 parse error/warning |
| 非 headless `run_art05_input.gd` | 20/20，0 failures，exit 0 |
| 非 headless `tool_capture_board_visual.gd -- board` | `board_menu`、`board_species_cat`、`board_species_mouse`、`board_settings` 四张均 `save_result=0 (OK)`；`CAP|board|done`；exit 0 |

## 视觉结论

改前图：`Art/Probes/art08_before/board_menu.png`。改后图：`Art/Probes/art08_after_menu/board_menu.png`。

改后图确认 1280x720 下左侧品牌/四按钮、中央猫主视觉和右侧猫鼠信息列表均可见，未出现布局重叠。右栏仍叠在现有庭院场景上，背景是石墙、直线水面和草带；猫仍为当前 `sm_cat_002` 模型。它与展板的森林溪谷环境、猫鼠角色质量和右侧动物照片栏仍有明显差距，因此整体展板视觉判定 **FAIL / 尚未达到**。本证据不把结构测试通过解释为美术通过。

## 未验证 / 阻塞

- vision 服务未在本阶段调用；截图做了人工对比，外部视觉判读状态为 `NOT-RUN`。
- 猫鼠高质量模型及动作资产仍需授权，不在本阶段替换。
- 溪谷环境资产和构图需 Task 4 处理；现有庭院未达到展板目标。

## 恢复入口

本阶段提交只包含菜单脚本、ART08 菜单契约/取证工具、证据文档和 `art08_after_menu` 图片。ART07 的未提交工作保持不变。
