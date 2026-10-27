# ART08 证据：展板视觉基线与菜单验收夹具

状态：awaiting-review
日期：2026-10-28

## 工作区

执行前分支：`art/modeling-pipeline`。
执行前已有 ART07 未提交改动：`Docs/Handoff.md`、`Docs/Tasks.md`、庭院生成/场景/草风 shader、T011 断言、ART07 取证图与证据文档，以及其他工作区文件。本任务未回退这些改动。

## 基线命令

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
& $g --headless --path $proj --script 'res://tests/run_t008_species.gd' --quit-after 20000
& $g --headless --path $proj --check-only --script 'res://tests/run_art08_board_contract.gd' --quit-after 30000
& $g --headless --path $proj --script 'res://tests/run_art08_board_contract.gd' --quit-after 30000
```

## 实际结果

- `run_t008_species.gd`：PASS，118 checks，0 failures，退出码 0。
- `run_art08_board_contract.gd --check-only`：退出码 0，脚本可解析。
- `run_art08_board_contract.gd`：FAIL，9 checks，6 failures，退出码 1。
- 通过：主场景加载、菜单存在、默认猫。
- 当前缺口：`LeftPanel`、`SpeciesRail`、菜单相机、菜单补光不存在；headless 根视口为 64x64，因此未作视觉结论。

关键输出：

```text
ASSERT|main_scene_loads|PASS
ASSERT|menu_exists|PASS
ASSERT|main_page_exists|FAIL
ASSERT|species_page_exists|FAIL
ASSERT|left_panel_exists|FAIL
ASSERT|species_rail_exists|FAIL
ASSERT|menu_camera_exists|FAIL
ASSERT|menu_fill_exists|FAIL
ASSERT|default_cat|PASS
LAYOUT|viewport=64x64|left_panel=false|species_rail=false
SUMMARY|checks=9|failures=6
RESULT|FAIL
```

## 未运行

非 headless `tool_capture_board_visual.gd` 尚未运行，因此 `Art/Probes/art08_before/` 尚无可信窗口截图；视觉状态为 `NOT-RUN`，不是通过。

## 恢复入口

新增夹具文件：

- `Game/Reborn/tests/run_art08_board_contract.gd`
- `Game/Reborn/tests/tool_capture_board_visual.gd`
- `Docs/Tasks/ART08_BOARD_BASELINE.md`
- `Docs/Evidence/ART08_BOARD_BASELINE.md`

下一步为 ART08 菜单布局实现；在实现前不修改已验证玩法代码。
