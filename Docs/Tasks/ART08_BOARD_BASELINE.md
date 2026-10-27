# ART08 任务规格：展板视觉基线与菜单验收夹具

状态：in-progress

## 目标

为用户提供的展板图建立真实游戏菜单的可重复基线、布局契约和非 headless 截图入口。此任务只建立验收夹具，不修改菜单视觉实现。

## 前置

- Godot 4.7.2 + GDScript。
- `main.tscn` 是当前正式入口。
- ART07 有未提交改动，执行者不得回退或覆盖。

## 产物

- `Game/Reborn/tests/run_art08_board_contract.gd`
- `Game/Reborn/tests/tool_capture_board_visual.gd`
- `Art/Probes/art08_before/`
- `Docs/Evidence/ART08_BOARD_BASELINE.md`

## 验收

1. 菜单、默认物种、主场景可以加载。
2. 契约明确记录展板目标节点 `LeftPanel`、`SpeciesRail`、菜单相机和补光的当前状态。
3. 非 headless 取证支持菜单、猫物种页、鼠物种页和设置页四张截图。
4. 截图只来自真实 `main.tscn`，不使用合成展板图。

## 回退

本任务新增测试和文档，不改变玩法或正式场景；删除本任务新增文件即可回到任务前状态。不得使用破坏性 Git 回退命令清理 ART07 改动。
