# ART09-B 任务规格：主菜单展板化

状态：done（结构/排版/控件达标；整体展板视觉仍未达标，见证据）
上位计划：`Docs/Tasks/ART09_BOARD_PARITY.md` §3 阶段 B

## 目标

把主菜单从「深色面板 + 系统字体 + 紧凑 3D 小图」改成展板观感：
书法标题、金色主按钮 + chevron、照片式物种卡列（含「未来将拓展更多动物」）、
「初期版本（MVP Demo）」说明块、左栏渐变压暗、右栏深色玻片。

## 改动路径

- `Game/Reborn/scripts/ui/main_menu.gd`
- 复用 `Game/Reborn/scripts/ui/board_tokens.gd`
- 新增 `Game/Reborn/tests/run_art09_menu_contract.gd`
- 截图产物 `Art/Probes/art09_menu_after/`
- 证据 `Docs/Evidence/ART09_B_MENU.md`

## 实现要点

1. **标题块**：`TitleCalligraphy`（`SystemFont` 行楷，104 px）+ `TitleLatin`（`R E B O R N`，金色 20 px）
   + `TitleRule`（240×1 金线）+ 两行 slogan。文本仍是真节点，断言可读。
2. **左栏按钮**：`StartButton` 金色实底 + 亮金边 + 投影 + 右侧 `Chevron`（`›`，忽略鼠标）；
   次级按钮深色玻璃，1 px 暗边。尺寸全部来自 `BoardTokens`（300×52）。
3. **右栏物种卡**：`Card_<id>` 高 84，左侧 `Thumb_<id>` 64×64 圆角方框（内含实时 3D 预览），
   右侧「名字 / 定位 / 一句描述」三层；`Locked_兔/鸟/狐` 60 高、压暗、`MOUSE_FILTER_IGNORE` 不可点；
   底部 `RailFooter` = 「更多物种 · 敬请期待」。
4. **MVP 说明块**：`MvpNote` / `MvpHeading`，右上角、右对齐，三行说明。
5. **背景**：去掉上一轮未提交的 `CreekBackground`（`menu_creek.png` 只是庭院低质渲染），
   改回实时 3D + CC0 森林天空球；左栏用 `GradientTexture2D` 横向渐变压暗（不是硬边矩形面板），
   右栏 `RightRailShade` 用 `BoardTokens.RAIL_BG`（alpha 0.94）。
6. **缩略图取景**：`_make_preview()` 的 `target/h` 与相机距离改为 `h*0.34` / `h*1.50`
   （原来 `h*0.46` / `h*2.20` 让动物只占方框一半，像"迷你模型"）。

## 不改动的契约

- `MainEntry` 的 `MenuCamera` / `MenuFill`、`selection_changed` / `species_committed` / `setting_changed` /
  `quit_requested` 信号、`Page.MAIN` / `Page.SPECIES` 两页、`1`/`2` 数字键与 `Enter`/`Esc` 路径。
- 物种文案真源仍是 `SpeciesConfig.display_*`；本文件不出现 `if species_id == "Cat"` 之类分支。
- `main.tscn` 仍然没有 `CanvasLayer`（T030 A15/A16）。

## 验收

- `run_art09_menu_contract.gd`（42 条）：栅格、标题、按钮、卡片、锁定卡、MVP 块、960×540 不重叠。
- 回归：`run_art08_board_contract` 9/9、`run_art08_environment_contract` 9/9、`run_art05_settings` 20/20、
  非 headless `run_art05_input` 20/20、`run_t011_greybox` 229/229、`run_art02_cat` 72/72、
  `run_art08_character_contract` 15/15。
- 非 headless 截图 4 张，`save_result=0 (OK)` 且 `CAP|board|done`。
- **视觉结论按区域写 PASS/FAIL**：版式与控件 PASS；「整块达到展板」仍 FAIL。

## 回退

只回退 `main_menu.gd` 与新增测试/截图；不动 ART07 未提交改动，不动 `MainEntry` 相机与关卡几何。
