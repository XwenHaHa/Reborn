# ART09-D 任务规格：HUD 图标 / 技能环 / 罗盘

状态：done（2026-10-29）
上位计划：`Docs/Tasks/ART09_BOARD_PARITY.md` §3 阶段 D

## 目标

把 HUD 从「左下四条文字条」改成展板样式：**四条状态带图标、浮在画面右侧中部**，
补上展板的**右下三个圆形技能位**与**右上罗盘**，同时**不新增任何玩法数值**、不改 T018 契约。

## 改动路径

- `Game/Reborn/scripts/ui/hud.gd`
- `Game/Reborn/scripts/ui/compass_dial.gd`（新增，程序化绘制罗盘）
- `Game/Reborn/tests/run_art09_hud_layout.gd`（新增，63 条）
- `Art/Probes/art09_hud_after/`（`tool_capture_render.gd -- t018` 实机帧）
- `Docs/Evidence/ART09_D_HUD.md`

## 实现要点

1. **四条状态**：`VitalsBars` 改为独立锚点容器（`anchor_left/right = 1`、`anchor_top/bottom = 0.5`，
   `offset_right = -24`，`offset_top = 46-44`），每行 = `Icon_<key>`（14×14 程序化图标）+ `Name_<key>`
   + `Bar_<key>`（108×8）+ `Value_<key>`。颜色与 `VITAL_ROWS` 一致（红/橙/蓝/绿）。
2. **图标程序化绘制**：`_draw_vital_icon()` 用 `draw_circle` / `draw_colored_polygon` / `draw_line`
   画心形、肉块、水滴、闪电。**不是图标素材**，因此没有第三方许可问题，也没有新增图片文件。
3. **技能环** `SkillRing`：右下角三个圆形 `Skill_<key>`（`Panel` + 圆角 stylebox），内容 `Glyph` + `Hint`：
   `冲/Shift`、`潜/Ctrl`、`扑/左键`。**纯指示器**（`MOUSE_FILTER_IGNORE`，左键要留给真实扑击），
   高亮 = `want_sprint` / `is_crouching` / `action_state() == POUNCING`；物种没有该能力（鼠无扑击）时
   转禁用态、提示文字改「不可用」并把 tooltip 写成 `NOT-AVAILABLE：该物种不能扑击`。
4. **罗盘** `Compass`：右上角 84×84，`compass_dial.gd` 画圆环 + 四向刻度 + N + 指针；
   `hud.gd` 每帧把 `-玩家偏航` 传进去（只读），没有玩家时指针朝上。
5. **契约保持**：`Margin/VBox/{VitalLabel,WarningLabel,InteractLabel}` 三条老路径与 `hud_text()` /
   `status_lines()` / `interaction_visible()` 全不变；`VitalLabel` 仍 `visible = false`。

## 不改动的契约

- 不写任何生存/AI/捕获状态；不出现 `apply_damage()` / `commit_interaction()` 之类调用。
- 不新增输入动作、不改 `project.godot`；技能环的三个动作都是**已有**的 `sprint` / `crouch` / `pounce`。
- `hud.tscn` 未改（节点仍在运行期构建），T013/T018/T022/T030 的路径读法不受影响。

## 验收

- `run_art09_hud_layout.gd` 63/63（锚点/图标/技能环/罗盘/鼠不可扑击/猫可扑击/冲刺高亮）。
- `run_t018_hud.gd` 73/73、`run_t022_loop.gd` 168/168、`run_t030_lifecycle.gd` 111/111。
- art09 菜单 42/42、物种页 59/59、令牌 15/15。
- 非 headless `tool_capture_render.gd -- t018` 两帧 `save_result=OK`。
- 视觉判读按区域写 PASS/FAIL（图标与技能环是"程序化近似"，不等于美术图标）。

## 回退

回退 `hud.gd` 的 `_build_vitals_bars()` 与新增的三个构建/刷新函数、删除 `compass_dial.gd` 与
`run_art09_hud_layout.gd` 即可回到 ART04 的左下条状 HUD（`VitalsBars` 回到 `Margin/VBox` 首位）。
