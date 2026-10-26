# ART04 证据：主菜单 / 物种选择 / HUD 条 / 动画过渡

任务规格：`Docs/Tasks/ART04.md`。引擎：Godot 4.7.2 / GDScript。工作分支：`art/modeling-pipeline`。
结论：**开场与物种选择从"一行文字"变成"真实 3D 场景 + 数据驱动卡片"**；HUD 换成四项指标条；动画状态切换加了交叉淡入；
玩法代码（生存 / 移动 / AI / 捕获 / 攻击 / 生命周期）**未改动语义**，29 套断言套件 + 2 套 ART 套件全绿（见 §5）。

---

## 1. 阶段 1：审计报告（先看，再改）

### 1.1 改前实测画面（两次取景，均为真实引擎渲染）

| 取景 | 事实 |
|---|---|
| `Art/Probes/art04_before_select.png`（`tool_capture_render.gd -- t030`，改前） | 选物种时**只有**：一块褐色地面 + 远处石墙 + 一只猫 + 屏幕顶部一行 `选择物种：1=Cat  2=Mouse` + 左下角 `生命 — / —` 四行占位。**没有标题、没有按钮、没有卡片、没有选中态**。 |
| `Art/Probes/art04_before_alive.png`（同上，改前） | 出生后：天空 + 地面 + 石墙 + 栅栏；HUD 是左下角纯文字四行；**玩家自己的鼠模型顶在镜头前**（鼠头占画面下方约 1/5）。 |

### 1.2 根因（不是"美术不够好"，是缺结构）

1. **没有主菜单/物种选择界面**：`MainEntry._build_status()` 只建了一个 `Label`，选物种靠 `1`/`2` 两个动作。
   依据 `Docs/Evidence/T030.md`：状态栏当时只为断言最小可见。
2. **选物种时没有相机**：`l_courtyard.tscn` 里没有 `current` 相机，`MainEntry` 也没建；T030 的取证图是靠**取景工具**临时建的 `T030OverviewCamera`。
   真实运行（`Tools/RunGame.cmd`）此时看到的是**默认清屏色** —— 这正是负责人说的"深灰背景"。
3. **物种信息没有任何数据字段**：`SpeciesConfig` 只有玩法字段，没有显示名/定位语，UI 只能写死物种名（违反 `配套要求.md` §1）。
4. **动画状态硬切**：`animal_body._update_visual_animation()` 里是 `visual_anim.play(want)`，Idle↔Walk↔Run 之间没有任何混合。
5. **HUD 只有文字**：四项指标是一行 `生命 100 / 100`，和概念展板的条状差距最大，其次是缺少颜色语义。

### 1.3 现有可复用资产（不新造）

- 关卡几何/光照：`scenes/maps/l_courtyard.tscn`（石墙、溪水 shader、草丛、巨石、树根洞口、庇护棚都已落地）。
- 猫/鼠视觉模型：`assets/characters/{cat,sm_cat_002,mouse/sm_mouse_002}.glb`（猫 33 骨、鼠 23 骨，含 Idle/Walk/Run）。
- HUD 文案与信号通道：`scripts/ui/hud.gd`（信号驱动、只读）。
- 生命周期与档案：`scripts/core/life_cycle.gd` + `autoload/game_state.gd`（T030）。

### 1.4 资源缺口（本轮**没有**解决的）

- **没有 UI 字体/图标/九宫格素材**：所有面板、按钮、条形都是 `StyleBoxFlat` 程序化绘制（无外部图片、无授权问题，但也没有"精致感"）。
- **没有专门的菜单摆件**：展示用地面就是关卡里的溪东岸干燥地，没有额外摆苔石/落叶。
- **鼠的体态与猫的皮毛仍是程序化/扫描资产**（ART02/ART03 遗留，P6 阶段门）。

---

## 2. 实施内容（逐文件）

| 文件 | 改动 |
|---|---|
| `scripts/data/species_config.gd` | 新增 `Display` 组：`display_name` / `display_tagline` / `display_note` + `display_title()`（留空回退 `species_id`）。**纯新增字段**，玩法字段与 `validate_config()` 未动。 |
| `resources/species/cat.tres` / `mouse.tres` | 追加三条显示文案（`猫 / 敏捷的捕食者 / 擅长攀爬与伏击`，`鼠 / 灵活的生存者 / 善于躲藏与探索`）。删掉这三行即回退。 |
| `scripts/ui/main_menu.gd`（**新文件**） | `class_name MainMenu extends Control`：标题 `轮生 / R E B O R N` + 两句定位语 + 4 个按钮（开始游戏 / 物种选择 / 设置 / 退出）；右侧物种卡片（每物种一个 `SubViewport` **实时 3D 预览**、选中态琥珀色左边框）+ 3 个「未来开放」占位卡；设置面板（灵敏度倍数 / FOV，**真的会作用到玩家**）；键盘 `1`/`2` 选中、`Enter` 进入、`Esc` 返回。**只发信号，不建玩家、不写 GameState**。 |
| `scripts/core/main_entry.gd` | 运行期建 `MainMenu`（`main.tscn` 仍是"只有根节点 + 脚本"，T030 A15/A16 断言继续成立）；新增菜单相机（`MENU_FOCUS` + 偏移 + `h_offset` 把主体推到卡片左侧空区）；按物种展示模型（沿相机右方向并排、面朝观众、按体型差**前移**让鼠不至于只有十几像素）；**只用于菜单的补光**（出生即关）；`_present_menu()` / `_dismiss_menu()` / `_apply_settings_to()`；`status_label` 与 HUD 在选物种时隐藏。 |
| `scripts/ui/hud.gd` | 新增 `VitalsBars`（4 行 = 名字 + `ProgressBar` + 数值；颜色 生命红/饥饿橙/水分蓝/体力绿），挂在 `Margin/VBox` 第 0 位；原 `VitalLabel` **保留但隐藏**（`status_lines()` / `hud_text()` / 73 条断言全部不变）。 |
| `scripts/characters/animal_body.gd` | `_update_visual_animation()` 改为 `play(want, blend)`：站↔走/跑 0.18 s、走↔跑 0.10 s（`VISUAL_ANIM_BLEND*`）；`speed_scale` 逻辑不变 → **不影响位移**。 |
| `tests/tool_capture_art04.gd`（**新文件**） | 取证工具：菜单页 / 物种页 / 设置页 / 切换第二个物种 / 出生后 HUD / 低值 HUD，共 6 帧。 |

### 2.1 实现过程中修掉的 3 个真实缺陷（都是自己踩到并实测确认的）

1. **卡片预览全黑**：`Camera3D.look_at()` 在节点入树前调用 → `Node not inside tree`，返回单位变换。
   改为手算 `Basis`（`MainMenu._look_transform()`），预览立刻出图。
2. **取景用 `global_transform` 算 AABB** 同样因为"未入树"报错并返回单位变换 → 相机位置算错（只拍到一条腿）。
   改为按 `SpeciesConfig.capsule_height()` 取景：**数据驱动**，两个物种在卡片里看起来一样大，也不受 glb 内部缩放影响。
3. **鼠在菜单里只有十几像素**（真按同一深度摆位）→ 按体型差把它往相机方向前移（`depth = (h_max − h) × 1.10`）。

---

## 3. 视觉证据（`Art/Probes/`，1280×720，引擎真实渲染）

| 图 | 判读（我在这张图上看到什么） |
|---|---|
| `art04_menu.png` | 左侧：`轮生` 大标题 + `R E B O R N` + 两句定位语 + 四个按钮（开始游戏为琥珀色主按钮）+ `v0.1.0 · MVP Demo` + 底部按键提示。中景：溪水、芦苇、石墙；猫与鼠站在干燥地上、面朝镜头。右侧：`可玩物种` 两张卡片（猫=琥珀边框选中、鼠=普通），每张含 3D 缩略图、名字、定位语、备注、`速度/视距/体力`；下方 `兔/鸟/狐` 三张灰色「未来开放」卡。 |
| `art04_species.png` | 同一场景，左列按钮切成 `进入世界` + `返回`，底部提示变成 `1 / 2 选择物种 · Enter 进入世界 · Esc 返回`。 |
| `art04_species_second.png` | 选中鼠：鼠卡片变琥珀边框、名字变琥珀色；猫卡片回到普通态。 |
| `art04_settings.png` | 居中设置面板：`鼠标灵敏度 1.00×` / `视野 (FOV) 90°` 两个滑块 + `关闭`。 |
| `art04_alive.png` | 出生后：菜单消失、玩家相机（fov 90）接管、HUD 指标条出现在左下（生命满、其余满）。 |
| `art04_hud_low.png` | 强设 `饥饿 18 / 水分 12 / 体力 40`：饥饿橙条约 18%、水分蓝条约 12%、体力绿条约 45%、生命红条满；下方橙字 `饥饿 + 缺水`。 |
| `art04_before_select.png` / `art04_before_alive.png` | 改前对照（见 §1.1）。 |

> 说明：本轮取景用的是引擎自渲染 PNG + 我直接读图判读，没有用 `vision.js`（Handoff 记录该工具曾 503，且 Read 已可多模态读图）。
> 判读只描述**图上确实能看到的东西**，没有对模型质量作"合格"结论。

---

## 4. 玩家可见行为（运行时实测，非断言语义）

```
CAP|art04|state=selecting|menu=true|species=[&"Cat", &"Mouse"]|status=选择物种：1=Cat  2=Mouse
CAP|art04|active_camera=MenuCamera|pos=(-9.64, 0.52, 16.8)|fov=58.0
CAP|art04|selected=Mouse|card=鼠|灵活的生存者|善于躲藏与探索
CAP|art04|after_commit|state=alive|life=L0001|player=true|menu_visible=false|hud_visible=true
CAP|art04|player_camera=Camera3D|fov=90.0
CAP|art04|hud_text=生命 100 / 100 / 饥饿 18 / 100 / 水分 12 / 100 / 体力 45 / 100 / 饥饿 + 缺水
```

- 选物种时 `MenuCamera` 成为活动相机（因此不再出现默认清屏色）。
- 进入世界后菜单 `visible=false`、HUD `visible=true`、活动相机是玩家 `Camera3D`（fov 90 = `species_config.fov`）。
- 取景全程**零 `SCRIPT ERROR`**（改前有 2 次 `Node not inside tree`，见 §2.1）。

---

## 5. 回归结果（`--headless`，退出码 0 = 通过）

| 套件 | checks | failures | SCRIPT ERROR |
|---|---|---|---|
| run_t002 | 18 | 0 | 0 |
| run_t005_asset | 50 | 0 | 0 |
| run_t006_rig | 65 | 0 | 0 |
| run_t007_input | 22 | 0 | 0 |
| probe_step_height | 6 | 0 | 0 |
| run_t008_species | 114 | 0 | 0 |
| run_t009_cat_movement | 81 | 0 | 0 |
| run_t010_mouse_movement | 95 | 0 | 0 |
| run_t011_greybox | 210 | 0 | 0 |
| run_t012_navigation | 79 | 0 | 0 |
| run_t013_debug_entry | 159 | 0 | 0 |
| run_t013_movement_regression | 73 | 0 | 0 |
| run_t014_survival | 106 | 0 | 0 |
| run_t015_costs | 93 | 0 | 0 |
| run_t016_interaction | 118 | 0 | 0 |
| run_t017_food_water | 128 | 0 | 0 |
| run_t018_hud | 73 | 0 | 0 |
| run_t019_mouse_ai | 72 | 0 | 0 |
| run_t020_perception | 164 | 0 | 0 |
| run_t021_capture | 279 | 0 | 0 |
| run_t022_loop | 168 | 0 | 0 |
| run_t023_cat_ai | 178 | 0 | 0 |
| run_t024_chase_search | 136 | 0 | 0 |
| run_t025_attack | 175 | 0 | 0 |
| run_t026_cover | 96 | 0 | 0 |
| run_t027_ecology | 96 | 0 | 0 |
| run_t029_sprint_chase | 39 | 0 | 0 |
| run_t030_lifecycle | 111 | 0 | 0 |
| run_art01_bush | 83 | 0 | 0 |
| run_art02_cat | 72 | 0 | 0 |
| run_art03_mouse | 45 | 0 | 0 |

合计 **31 套 / 3,525 条断言，0 失败，0 条 `SCRIPT ERROR`**（每套件单独跑，日志在 `$env:PI_SCRATCH_DIR`）。

### 5.1 一个**改前就存在**的失败（不是本任务引入）

`tests/tool_t028_walkthrough.gd`（T028 走查工具，不是断言套件）：

- 改后：`W1/W2/W3 PASS`、**`W4_players_survived FAIL`**（鼠玩家 `hp 100→0`，猫追到洞口 0.79 m 并攻击）。
- **改前基线**：`git stash` 掉本任务全部改动后重跑 → **同样 FAIL**（`hole_gap 0.25`、`cat_min_to_hole 0.82`、`hp 100→0`）。
- 结论：与 T029 §6 ① 记录的既有缺陷一致 —— **"鼠洞不是安全区"（洞里能被咬）**，交负责人 / U01 决策，本任务不擅自改平衡。

---

## 6. 未完成 / 未验证

1. **T028 的 U01 真人半边**仍 NOT-RUN（本任务不涉及，但 W4 失败会让真人试玩更容易死亡）。
2. **第三人称视角未做**：概念展板的"游戏内"是第三人称，本轮保持第一人称（T009 决策 D1 锁了 `camera_offset_z` 的竖直语义与相机断言）。
   因此**玩家自己的模型仍可能顶在镜头前**（`art04_before_alive.png` / `art04_hud_low.png` 可见鼠背/鼻）。这是**已知外观问题**，改法有两条，需负责人选：
   ① 第一人称时隐藏自己模型（`SpeciesConfig` 加 `hide_visual_in_first_person`，风险是影响 `tool_capture_art02/art08` 的既有取证图）；
   ② 做第三人称相机（改动 T009 断言，工作量属一个独立任务）。
3. **设置项不持久化**（只作用于本次运行）；正式解锁链仍是 `test_mode=true`（T031）。
4. **没有真实鼠标点击的人机验证**：本轮用工具直接调 `select_species()` / `commit()` 与截图验证渲染，
   **鼠标/键盘真实按键路径（`Enter`/`Esc`/点击卡片）未做输入注入验证**（项目禁止盲发按键）。
5. 卡片缩略图是"同一帧静态视角 + 慢速自转"，**没有做动画预览**（预览里播的是模型自带的 Idle）。
6. 未打包复验（`export_presets` 两个预设未重跑）；本轮只做编辑器侧 `--headless` 断言与非 headless 取景。

---

## 7. 新增物种接入步骤（`配套要求.md` §2 / §5 明确要求）

1. 准备资产：模型 `.glb`（原点在脚底、**面朝 −Z**、零碰撞；骨骼动画命名 `Idle` / `Walk` / `Run`，无根运动）→ 放 `Game/Reborn/assets/characters/<species>/`。
2. 复制一份 `resources/species/mouse.tres` 改名为新物种，逐字段填：
   - `species_id`（稳定 ID）、`visual_scene`（指向新 `.glb`）、`ai_script`（可选）；
   - 移动/感知/生存/能力字段（未给的字段保持 `mouse.tres` 的值即可先跑起来）；
   - `display_name` / `display_tagline` / `display_note`（卡片文案）。
3. `can_pounce` / `can_attack` / `can_use_mouse_tunnel` 决定建不建 `CaptureSettlement` / `AttackSettlement`，**不需要改系统代码**。
4. 跑 `--import`（新 `class_name`/新资源），再跑 `run_t008_species.gd`（配置自校验）与 `tool_capture_art04.gd -- art04`（卡片/展示自动出现）。
5. 若要让它出现在关卡导航里：在 `tool_make_courtyard_nav.gd` 按该物种的胶囊半径加一层，并重烤导航（T012 的做法）。

---

## 8. 边界声明

- **未安装/卸载任何软件**；未连接 MCP；未改 git 全局配置；未删除源资产；未推送、未发布。
- 改动的生产文件：`scripts/data/species_config.gd`、`scripts/ui/hud.gd`、`scripts/ui/main_menu.gd`（新）、
  `scripts/core/main_entry.gd`、`scripts/characters/animal_body.gd`、`resources/species/{cat,mouse}.tres`。
  新增测试/工具：`tests/tool_capture_art04.gd`。
- 未改：关卡 `.tscn`、导航 `.tres`、生存/AI/捕获/攻击/生命周期逻辑、`project.godot`、导出预设。
- 运行过的受限程序：Godot **非 headless** 渲染捕获（创建窗口，工具立即把鼠标模式改回 `VISIBLE`）。
- 视觉 PNG 走 LFS；新增 `.gd` / `.tres` / `.md` 保持纯文本可 diff。
