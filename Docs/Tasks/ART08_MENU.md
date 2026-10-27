# ART08 任务规格：展板式菜单与物种选择布局

状态：awaiting-review（布局结构通过，整体展板视觉未通过）

## 目标

在保持 ART04/ART05 菜单信号、键鼠操作、设置持久化和物种数据驱动的前提下，为展板构图建立稳定的菜单结构节点，并调整左右栏信息层级。

## 改动路径

- `Game/Reborn/scripts/ui/main_menu.gd`
- `Game/Reborn/tests/run_art08_board_contract.gd`
- `Game/Reborn/tests/tool_capture_board_visual.gd`
- `Art/Probes/art08_after_menu/`

## 实现范围

- 左侧根节点命名为 `LeftPanel`，主菜单按钮和物种页按钮分别稳定命名。
- 右侧物种列表根节点命名为 `SpeciesRail`。
- 保留 `MainEntry` 的菜单相机、补光、物种主视觉和现有生命周期。
- 保留卡片数据来自 `SpeciesConfig`，不改菜单按钮/键盘行为。
- 本任务没有替换环境背景或角色模型，不声称达到展板最终效果。

## 验收与回归

- `run_art08_board_contract.gd`：9/9。
- `run_art05_settings.gd`：20/20。
- 非 headless `run_art05_input.gd`：20/20。
- `tool_capture_board_visual.gd -- board`：四张窗口图均 `save_result=0 (OK)` 且输出 `CAP|board|done`。
- 视觉基线比较见 `Docs/Evidence/ART08_MENU.md`；自然溪谷和猫鼠模型差距仍存在。

## 回退

保留 ART06 行为信号和 `MainEntry` 相机/主视觉实现。若需回退本阶段，只回退本提交涉及的菜单布局文件，不回退 ART07 或其他未提交工作。
