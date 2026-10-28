# ART09-C 任务规格：物种选择页重排

状态：done（2026-10-29）
上位计划：`Docs/Tasks/ART09_BOARD_PARITY.md` §3 阶段 C

## 目标

把物种选择页从「主菜单同款左栏 + 右栏卡片」改成展板第二块的样子：
**左侧大卡**（名字 / 定位 / 一句描述 / 四条状态）+ **底部缩略图行**（可玩可点、未来加 `?`）+ **金色开始按钮**。

## 改动路径

- `Game/Reborn/scripts/ui/main_menu.gd`（`_build_species_card` 及配套）
- `Game/Reborn/scripts/ui/board_tokens.gd`（大卡几何 + `VITAL_ROWS`）
- `Game/Reborn/tests/run_art09_species_layout.gd`（新增，59 条）
- `Game/Reborn/tests/tool_capture_board_visual.gd`（新增 960×540 物种页截图标签）
- `Art/Probes/art09_species_after/`、`Docs/Evidence/ART09_C_SPECIES.md`

## 实现要点

1. **大卡**：`SpeciesCard`（430×468，锚点 40,96），内边距 24/20；`CardName`（38 px）、`CardTagline`（金 15 px）、
   `CardNote`（13 px）、`CardStats`（`_stat_line()` 的速度/视距/体力）、`SpeciesButtons`（金色 `EnterButton`
   「开始游戏」+ `BackButton`「返回」）。
2. **四条状态**：`Vital_health/hunger/thirst/stamina`，每条 = 10×10 色块 + 名称 + `ProgressBar` + `100 / 100`。
   **只展示物种初始上限**（出生即满），不读 `SurvivalState`、不参与生存计算；上限取 `SpeciesConfig.max_*`。
3. **缩略图行**：`SpeciesStrip` 5 槽（`STRIP_SLOT` = 64）；可玩物种 `Strip_<id>` 复用实时 3D 预览、可点选中
   （**只选中，不开局**）；未来物种 `StripLocked_兔/鸟/狐` 为 `?`、`MOUSE_FILTER_IGNORE` 不可点。
   选中态 = 名字变金 + 缩略图槽 2 px 金边。
4. **页面切换**：物种页隐藏 `LeftPanel`（主菜单标题栏）、`SpeciesRail`、`RightRailShade`、`MvpNote`，
   显示 `SpeciesCard`；底部提示文字右移到大卡之外，避免压在「返回」上。
5. **窄窗口**：`_layout_species_card()` 挂在 `Viewport.size_changed`，把大卡收进视口
   （960×540 实测 430×428，不越界）。

## 与展板的已知偏差

- 展板把动物大图放在卡内右侧；这里那张图由 `MainEntry` 的中央 3D 主视觉承担（菜单相机是世界空间节点，
  塞进 `Control` 会破坏 ART08 的 `MenuCamera` / `MenuFill` 契约）。**这属于版式差异，视觉那项仍记 FAIL。**
- 状态条前的图标用色块代替（无图标资源；不做伪图标）。

## 不改动的契约

- 信号（`selection_changed` / `species_committed` / `setting_changed` / `quit_requested`）、
  `Page.MAIN` / `Page.SPECIES`、键盘 `1`/`2` 与 `Enter`/`Esc`、`MainEntry` 的相机与主视觉、关卡几何。
- `main.tscn` 仍无 `CanvasLayer`；`SpeciesButtons` / `EnterButton` / `BackButton` 节点名保留（ART08 契约）。

## 验收

- `run_art09_species_layout.gd` 59/59。
- 回归：`run_art09_menu_contract` 42/42、`run_art09_tokens` 15/15、`run_art08_board_contract` 9/9、
  `run_art05_settings` 20/20、非 headless `run_art05_input` 20/20、`run_t030_lifecycle` 111/111。
- 窗口截图：`board_species_cat` / `board_species_mouse` / `board_species_narrow`（960×540），均 `save_result=OK`。
- 视觉判读按区域写 PASS/FAIL。

## 回退

只回退 `main_menu.gd`（物种卡相关段）+ `board_tokens.gd` 的大卡常量 + 新增测试/截图；
`SpeciesButtons` 恢复到左栏即可（原实现见提交 `b25d129`）。
