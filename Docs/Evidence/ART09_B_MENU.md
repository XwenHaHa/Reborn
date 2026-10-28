# ART09-B 证据：主菜单展板化

状态：done / 整体展板视觉 **FAIL（未达标）**
日期：2026-10-29
分支：`art/modeling-pipeline`

## 1. 验证命令与结果

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
& $g --path $proj --headless --import
& $g --headless --path $proj --script 'res://tests/run_art09_menu_contract.gd' --quit-after 60000
& $g --path $proj --script 'res://tests/tool_capture_board_visual.gd' --quit-after 30000 -- board
```

| 套件 | 结果 |
|---|---|
| `run_art09_menu_contract.gd`（新增） | **42/42，0 failures，exit 0** |
| `run_art09_tokens.gd` | 15/15，exit 0 |
| `run_art08_board_contract.gd` | 9/9，exit 0 |
| `run_art08_environment_contract.gd` | 9/9，exit 0 |
| `run_art08_character_contract.gd` | 15/15，exit 0 |
| `run_art05_settings.gd` | 20/20，exit 0 |
| `run_art05_input.gd`（**非 headless**） | 20/20，exit 0 |
| `run_t011_greybox.gd` | 229/229，exit 0（天空球换成 Panorama 后两条环境断言仍成立） |
| `run_art02_cat.gd` | 72/72，exit 0 |
| 非 headless `tool_capture_board_visual.gd -- board` | 4 张全部 `save_result=0 (OK)`，`CAP|board|done`，exit 0，`SCRIPT ERROR` 0 条 |

关键输出：

```text
LAYOUT|viewport=1280x720|left=0..430|center=430..900|rail=900..1280
LAYOUT|narrow=960x540|left_right=430|rail_left=580
SUMMARY|checks=42|failures=0
RESULT|PASS
```

## 2. 截图

`Art/Probes/art09_menu_after/`

- `board_menu.png`：主菜单（1280×720）
- `board_species_cat.png`：物种页（猫）
- `board_species_mouse.png`：物种页（鼠）
- `board_settings.png`：设置面板

## 3. 逐项视觉判读（对比 `《轮生：森林生存游戏概念展板》.png` 左上主菜单区）

| 展板要素 | 现状 | 判定 |
|---|---|---|
| 书法「轮生」+ 金色 `R E B O R N` + 细金线 + 两行 slogan | 行楷已生效（本机命中华文行楷），层级与展板同序 | **PASS** |
| 金色主按钮 + 右侧 chevron，次级按钮深色玻璃 | 位置/尺寸/层级一致；主按钮为纯色金（展板略有纵向明暗过渡） | **PASS**（渐变近似扣分） |
| 右栏 5 张卡（名称/定位/描述三层）+ 「未来将拓展更多动物」+ 「更多物种 · 敬请期待」 | 2 可玩 + 3 锁定，版式与展板一致 | **PASS**（结构） |
| 卡内缩略图是**照片** | 仍是实时 3D 预览（取景已收紧，动物填满方框） | **FAIL**（需肖像素材，阶段 F） |
| 右上「初期版本（MVP Demo）」说明块 | 已加，右对齐三行 | **PASS** |
| 背景是森林溪谷照片级画面 | 仍是庭院：石墙 + 直线水面 + 深色地面；天空球只在画面顶部露一条绿叶 | **FAIL**（阶段 E：`l_ravine_board`） |
| 中央主视觉：猫在溪边、景深、逆光 | 猫站在平地、无景深、背景压暗 | **FAIL**（阶段 E/F） |
| 左下版本号 + 底部操作提示 | 已有 | **PASS** |

**整体结论：版式、排版层级、控件观感已与展板对齐；画面素材（背景 / 动物照片）仍是主要差距，
故「达到展板」判定 FAIL，不作达标声明。**

## 4. 已知缺陷与观察

- 左栏 `LeftPanelShade` 用 `GradientTexture2D` 横向渐变压暗；截图里 430 px 处看着像有硬边，
  实际是 3D 地面/水面的边界，不是 UI 边缘（已放大裁剪核对）。
- `_stat_line()` 与 `_menu_panel_style()` 目前无调用方（`_stat_line` 留给阶段 C 的大卡数值行）。
- 上一轮未提交的 `CreekBackground`（`menu_creek.png`）已从代码移除；文件本身未删
  （见 `Docs/BoardArtPipeline.md` §5）。
- 该文件 `main_menu.gd` 里同时吸收了上一轮未提交的菜单微调（颜色/边距/字号），
  本轮已整体重写为展板版式，原有尝试中保留下来的只有数值取向。

## 5. 未验证

- 960×540 只有断言验证（不重叠），**没有截图**；小窗口下的观感 `NOT-VERIFIED`。
- 换机器（无华文行楷时的回退字重）观感 `NOT-VERIFIED`：`SystemFont` 有候选列表 + 系统回退，
  但只在当前机器看过效果。
- 外部 vision 服务本轮未调用，判读由截图人工对比得出（与 ART07/ART08 的证据口径一致）。

## 6. 恢复入口

回退只需还原 `Game/Reborn/scripts/ui/main_menu.gd`，删除 `tests/run_art09_menu_contract.gd`
与 `Art/Probes/art09_menu_after/`。ART07 未提交工作（`l_courtyard.tscn`、`tool_make_courtyard.gd`、
`grass_wind.gdshader`、`run_t011_greybox.gd`、`tool_capture_render.gd` 及 `Art/Probes/art07_*`）
未被本阶段改动或回退。
