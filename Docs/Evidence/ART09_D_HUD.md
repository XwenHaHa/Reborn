# ART09-D 证据：HUD 图标 / 技能环 / 罗盘

状态：done / 展板视觉 **部分达标**（图标与技能环是程序化近似，不是美术图标）
日期：2026-10-29
分支：`art/modeling-pipeline`

## 1. 命令与结果

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
& $g --headless --path $proj --script 'res://tests/run_art09_hud_layout.gd' --quit-after 60000
& $g --headless --path $proj --script 'res://tests/run_t018_hud.gd' --quit-after 60000
& $g --path $proj --script 'res://tests/tool_capture_render.gd' --quit-after 20000 -- t018
```

| 套件 | 结果 |
|---|---|
| `run_art09_hud_layout.gd`（新增） | **63/63，0 failures，exit 0** |
| `run_t018_hud.gd`（HUD 老契约） | **73/73，exit 0**（改后跑两次） |
| `run_t022_loop.gd`（死亡重开 + HUD） | 168/168，exit 0 |
| `run_t030_lifecycle.gd` | 111/111，exit 0 |
| `run_art09_menu_contract.gd` | 42/42，exit 0 |
| `run_art09_species_layout.gd` | 59/59，exit 0 |
| `run_art09_tokens.gd` | 15/15，exit 0 |
| `tool_capture_render.gd -- t018`（**非 headless**） | 2 帧 `save_result=0 (OK)`，`CAP|done`，exit 0 |

关键读数：

```text
LAYOUT|vitals=1046,362 210x88|viewport=1280x720
LAYOUT|compass_heading=-1.571|expected=-1.571
SKILL|mouse|pounce_hint=不可用|tooltip=NOT-AVAILABLE：该物种不能扑击
SKILL|cat|sprint_bg=(0.851, 0.588, 0.227, 0.92)
SUMMARY|checks=63|failures=0
RESULT|PASS
```

## 2. 截图

`Art/Probes/art09_hud_after/`

- `t018_hud_warning.png`：鼠在关卡里、饥饿+缺水警告、四条状态（右侧中部）、技能环（扑=不可用）、罗盘
- `t018_hud_interact.png`：同上 + `[进食] t018_seed` 交互提示

## 3. 逐项视觉判读（对比展板第三人称实玩区）

| 展板要素 | 现状 | 判定 |
|---|---|---|
| 四条状态浮在画面右侧中部，带图标 | 右侧中部（x=1046 / 1280），心/肉/水滴/闪电 + 名称 + 条 + 数值 | **PASS**（位置与信息层级） |
| 图标是美术图标 | 程序化几何绘制（`draw_circle` / `polygon` / `line`），14 px 下可辨认 | **PASS（近似）／FAIL（精细度）** |
| Four bars 的数值可读 | `100 / 18 / 12 / 100`（鼠在关卡里掉饥饿/水分） | **PASS** |
| 右下三个圆形技能位 | `冲/Shift`、`潜/Ctrl`、`扑/左键` 圆形指示器；鼠标物种的「扑」显示「不可用」 | **PASS（结构）** |
| 技能位可点击 / 有冷却 | **不是按钮**，纯指示器（`MOUSE_FILTER_IGNORE`，左键留给真实扑击） | **FAIL（展板暗示可操作，本轮不做玩法）** |
| 右上罗盘 | 84×84 圆环 + 四向刻度 + N + 指针，跟随玩家偏航 | **PASS** |
| 罗盘带小地图 | 无（没有小地图数据源） | **FAIL / NOT-IMPLEMENTED** |
| 原有警告与交互提示 | 左下「饥饿+缺水」「[进食] t018_seed」原样保留 | **PASS** |

**结论：HUD 的位置、层级、图标语义与展板对齐；技能位只是指示器、罗盘没有小地图，这两项按 FAIL 记录。**

## 4. 本阶段修掉的真实缺陷

1. **换物种后技能位不恢复**：`_apply_skill()` 只在 `available == false` 时改提示文字，「鼠 → 猫」切回来
   仍停在「不可用」。现在把原始按键提示存进 `hint_text`，可用时还原。
2. （自测中发现的测试侧问题）headless 根视口 64×64 → 布局断言必须先入树再设 `root.size`，
   否则 `vitals_on_right_half` 会假失败（与 ART09-B/C 同一个坑，已写进测试注释）。

## 5. 未验证 / 边界

- **真实按键**没有注入：高亮是靠程序里设 `want_sprint = true` 验证的（与 ART05 的口径一致，禁止盲发按键）。
- 罗盘在真实游玩（鼠标转身）里的观感未录屏核对，只验证了「偏航 90° → heading = −π/2」。
- 960×540 下 HUD 位置未截图核对（锚点会跟随，但没有实测帧）。
- 12 个图标是几何近似，不是美术资产；换正式图标时只改 `_draw_vital_icon()`，断言不受影响。
- 外部 vision 服务本轮未调用，判读由截图人工对比得出。

## 6. 恢复入口

回退 `Game/Reborn/scripts/ui/hud.gd` 的 `_build_vitals_bars()` 与新增函数、删除
`Game/Reborn/scripts/ui/compass_dial.gd`、`Game/Reborn/tests/run_art09_hud_layout.gd` 与
`Art/Probes/art09_hud_after/`。ART07 未提交改动未被触碰。
