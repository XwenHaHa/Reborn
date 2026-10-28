# ART09-C 证据：物种选择页重排

状态：done / 整体展板视觉 **仍 FAIL（大卡内没有动物大图）**
日期：2026-10-29
分支：`art/modeling-pipeline`

## 1. 命令与结果

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
& $g --headless --path $proj --script 'res://tests/run_art09_species_layout.gd' --quit-after 60000
& $g --path $proj --script 'res://tests/tool_capture_board_visual.gd' --quit-after 40000 -- board
```

| 套件 | 结果 |
|---|---|
| `run_art09_species_layout.gd`（新增） | **59/59，0 failures，exit 0** |
| `run_art09_menu_contract.gd` | 42/42，exit 0 |
| `run_art09_tokens.gd` | 15/15，exit 0 |
| `run_art08_board_contract.gd` | 9/9，exit 0 |
| `run_art05_settings.gd` | 20/20，exit 0 |
| `run_art05_input.gd`（**非 headless**） | 20/20，exit 0 |
| `run_t030_lifecycle.gd` | 111/111，exit 0（菜单→选种→出生链路未受页切换改动影响） |
| `tool_capture_board_visual.gd -- board` | 5 张全部 `save_result=0 (OK)`，`CAP|board|done`，`SCRIPT ERROR` 0 条 |

关键读数：

```text
LAYOUT|species_card=40,96 430x468
LAYOUT|strip_slots=5|configs=2|locked=3
LAYOUT|narrow=960x540|card=40,96 430x428
SUMMARY|checks=59|failures=0
RESULT|PASS
```

## 2. 截图

`Art/Probes/art09_species_after/`

- `board_species_cat.png`：物种页（猫选中）
- `board_species_mouse.png`：物种页（鼠选中）
- `board_species_narrow.png`：960×540 物种页（大卡收进视口）
- `board_menu.png` / `board_settings.png`：主菜单与设置（本阶段回归顺带重拍）

## 3. 逐项视觉判读（对比展板「物种选择界面（示例）」）

| 展板要素 | 现状 | 判定 |
|---|---|---|
| 左侧大卡：名字（大字）+ 定位 + 一句描述 | `猫` 38 px + 金色「敏捷的捕食者」+「擅长攀爬与伏击」 | **PASS** |
| 四条状态（生命/饥饿/水分/体力，带色标与数值） | 色块 + 名称 + 进度条 + `100 / 100`，颜色与 HUD 同源 | **PASS**（图标为色块非图形） |
| 底部 5 缩略图行（可玩 2 + 未来 3 加 `?`） | 5 槽 64 px；选中槽 2 px 金边；未来槽不可点 | **PASS** |
| 卡内金色「开始游戏」按钮 | 在大卡底部、金色 + chevron；「返回」为次级按钮 | **PASS** |
| 卡内右侧的动物大图 | 由中央 3D 主视觉承担，不在卡内 | **FAIL**（已知版式偏差，见任务 §偏差） |
| 背景是森林溪谷 | 卡片背后是 CC0 森林天空球 + 庭院几何；石墙与直线水面仍在 | **FAIL**（阶段 E） |
| 右栏与 MVP 说明不在本页 | 已按展板隐藏（含 `RightRailShade` 底板，第一版漏隐藏导致右侧出现一块暗板，已修） | **PASS** |

**整体结论：物种页的版面结构与信息层级已对上展板；"卡内大图 + 森林溪谷背景"两项仍缺，故整体仍记 FAIL。**

## 4. 本阶段修掉的真实缺陷

1. **960×540 下大卡压出视口**：初版固定 468 高、底部到 564 > 540 → 加 `_layout_species_card()`
   并在 `Viewport.size_changed` 上重排（实测收成 430×428）。
2. **物种页右侧残留一块暗板**：`RightRailShade` 是 `_build_scrim()` 里的独立 Panel，不在 `SpeciesRail` 下，
   只隐藏 `SpeciesRail` 时它还在 → 加 `_rail_shade` 成员并在 `show_page()` 一起切可见性。
3. **底部提示压住「返回」按钮**：物种页把提示文字左边界推到卡右侧 +16 px。

## 5. 未验证 / 边界

- 960×540 的**文字是否换行**未逐字核对：只验证了矩形不越界（截图可见「返回」按钮贴近卡底）。
- 缩略图槽点击只在断言层验证 `gui_input` 连接与 `MOUSE_FILTER_STOP`，**没有真实鼠标点击注入**
  （与 ART05 的输入验证口径一致：合成事件可测，真实按键仍需人工）。
- 卡内四条状态是**初始上限**，不要读成运行时状态（HUD 才是运行时）。
- 外部 vision 服务本轮未调用，判读由截图人工对比得出。

## 6. 恢复入口

回退：还原 `scripts/ui/main_menu.gd` 的物种卡段与 `board_tokens.gd` 的大卡常量到 `b25d129`，
删除 `tests/run_art09_species_layout.gd` 与 `Art/Probes/art09_species_after/`。
ART07 未提交改动（`l_courtyard.tscn`、`tool_make_courtyard.gd`、`grass_wind.gdshader`、
`run_t011_greybox.gd`、`tool_capture_render.gd`、`Art/Probes/art07_*`）未被触碰。
