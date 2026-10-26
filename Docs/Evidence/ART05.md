# ART05 证据：第三人称相机 + 设置持久化 + 真实输入链路验证 + 打包复验

任务规格：`Docs/Tasks/ART05.md`。引擎：Godot 4.7.2。分支：`art/modeling-pipeline`。
本轮是负责人对 ART04 遗留四项的直接指派：**1 第三人称 / 2 设置持久化 / 3 输入验证 / 4 打包复验**。

---

## 1. 第三人称相机

### 1.1 做法（为什么不是"换个相机位置"了事）

- 视角是**物种数据**：`SpeciesConfig` 新增 `camera_mode`（`CAMERA_FIRST_PERSON` / `CAMERA_THIRD_PERSON`）
  与 `third_person_distance / third_person_aim_height / third_person_down_tilt_deg / third_person_pitch_min_deg / third_person_pitch_max_deg`。
  代码里**仍然没有物种名分支**。
- `AnimalBody` 两条路径：
  - 第一人称：T009 契约原样保留（相机在胶囊内、`camera_offset_z` = 竖直眼高、蹲下按 `crouch_drop()` 降）。
  - 第三人称：枢轴 = 身体中心 + `third_person_aim_height`（蹲下一起降）；相机 = 枢轴 + 臂长 × 方向（本地 +Z 向后），
    俯仰来自 `apply_look()` 的俯仰量再叠加固定下俯角；**每物理帧**从枢轴向相机打一条 `world_static` 射线，
    撞墙时把臂长收到命中点前 0.12 m（下限 0.28 m）。
- **交互原点不跟相机走**：`eye_position()` 现在严格 = 身体中心 + `camera_offset_z`（蹲下减 `crouch_drop()`），
  与相机模式无关。第一人称时它**恰好**等于旧口径（当时就是相机位置），第三人称时相机在身后 1.3 m，
  若用相机判交互会把身后的东西也测进来。
- 物种参数：猫 `1.30 m / 0.18 m`、鼠 `0.55 m / 0.08 m`（鼠小，臂长了只剩几十像素）。

### 1.2 断言（新增 4 条，都在 `run_t008_species.gd`）

```
ASSERT|body_cat_camera_tp_behind|z > 0（相机在身后）|z=1.2716|PASS
ASSERT|body_cat_camera_tp_arm|1.300000 (±0.050000)|1.300000|PASS
ASSERT|body_cat_camera_tp_wall_shrinks|< 配置臂长 1.30|arm=0.289|PASS
ASSERT|body_cat_camera_tp_wall_floor|>= 0.28（不贴脸）|arm=0.289|PASS
ASSERT|body_mouse_camera_tp_behind|z > 0（相机在身后）|z=0.5399|PASS
ASSERT|body_mouse_camera_tp_arm|0.550000 (±0.050000)|0.550000|PASS
ASSERT|body_mouse_camera_tp_wall_shrinks|< 配置臂长 0.55|arm=0.287|PASS
ASSERT|body_mouse_camera_tp_wall_floor|>= 0.28（不贴脸）|arm=0.287|PASS
```

`run_t008_species` 现在 **118 条**（原 114，+4）。

### 1.3 既有套件的口径处理（**没有放宽断言**）

第一人称的相机几何断言属于 T009/T010/T013 的验收口径，正式配置改成第三人称后这些套件**显式钉住第一人称**再跑：

```gdscript
_cat.camera_mode = SpeciesConfig.CAMERA_FIRST_PERSON   # run_t009 / t010 / t013 ×2
```

`run_t008` 则改成**按模式分支**：第三人称断言"在身后 + 臂长 = 配置值 + 撞墙收臂"，第一人称仍断言老口径。

**一处必须修的测试夹具缺陷**：`run_t016_interaction.gd` 的 `_eye()` 以前直接读 `camera.global_position`
去摆目标。第一人称下等价，第三人称下差一个臂长 → 目标被摆错位置，距离/遮挡/优先级 11 条断言连锁失败。
改成读 `_body.eye_position()`（与游戏同一口径）后 118/118 全绿。

### 1.4 视觉证据

| 图 | 看到什么 |
|---|---|
| `Art/Probes/art05_tp_cat.png` | 猫玩家：镜头在猫身后上方（臂 1.30 m），能看见完整的猫背影与尾巴、前方地面与远处石墙/溪水；HUD 四条在左下。 |
| `Art/Probes/art05_tp_cat_look_up.png` | 同机位抬视线（`apply_look(0, +0.18)`）：镜头下沉、能看到更多天空 —— 俯仰链路生效。 |
| `Art/Probes/art05_tp_mouse.png` | 鼠玩家：臂 0.55 m，鼠在画面正中偏下，大小约 90 px 高（第一人称时它只有一颗顶在镜头前的鼻子）。 |

---

## 2. 设置持久化

- 新文件 `scripts/core/game_settings.gd`（`GameSettings`）：`ConfigFile` 写 `user://settings.cfg`，只写本作两个键
  （`sensitivity` 倍数、`fov`；`fov = 0` 表示不覆盖物种配置）。缺失/损坏 → 回落默认；越界 → 夹紧（`0.4–3.0` / `60–110`）。
- `MainEntry`：`_ready` 先 `_load_settings()` 再建菜单（滑块回填存盘值）；`menu.setting_changed` → 立刻写盘；
  出生时 `_apply_settings_to()` 把灵敏度（`0.0025 × 倍数`）与 FOV 落到玩家身体上。
- `MainMenu`：`build(configs, initial_settings)` 回填滑块；新增 `settings_values()` / `set_setting()`（面板与测试共用一条路径）。

### 2.1 断言：`tests/run_art05_settings.gd` **20/20 PASS**

```
ASSERT|S1_missing_file_sensitivity|1.00|1.00|PASS          # 没有文件 → 默认
ASSERT|S1_missing_file_fov|0（不覆盖）|0.0|PASS
ASSERT|S1_no_file_created|false|false|PASS                  # 只读不写
ASSERT|S2_save_ok|true|true|PASS
ASSERT|S2_roundtrip_sensitivity|2.00|2.00|PASS
ASSERT|S2_roundtrip_fov|80.0|80.0|PASS
ASSERT|S3_sensitivity_clamped|3.00|3.00|PASS                # 99 → 3.0
ASSERT|S3_fov_clamped|60.0|60.0|PASS                        # 5 → 60
ASSERT|S4_corrupt_defaults|1.00/0.0|1.00/0.0|PASS            # 损坏文件不崩
ASSERT|S5_entry_reads_sensitivity|2.00|2.00|PASS
ASSERT|S5_menu_slider_sensitivity|2.00|2.00|PASS            # 菜单回填
ASSERT|S5_change_persisted_sensitivity|1.50|1.50|PASS        # 改滑块 → 立即落盘
ASSERT|S5_change_persisted_fov|100.0|100.0|PASS
ASSERT|S6_player_spawned|alive|alive|PASS
ASSERT|S6_player_fov_applied|100.0|100.0|PASS                # 出生后真的生效
ASSERT|S6_player_sensitivity_applied|0.00375|0.00375|PASS
ASSERT|S7_restart_reads_saved|1.50|1.50|PASS                 # "重启"（新实例）读到上次的值
```

视觉：`Art/Probes/art05_settings_saved.png` —— 预写 `2.00× / 100°` 后打开菜单设置面板，滑块与读数正是 `2.00×`、`100°`；
同一次会话里出生后玩家相机 `fov=100`（`CAP|tp|spawn|Cat|...|fov=100`）。

---

## 3. 真实输入链路验证

`tests/run_art05_input.gd`：把**真实 `InputEventKey` / `InputEventMouseButton`** 送进引擎自己的输入系统
（键盘 `Input.parse_input_event` → InputMap → `_unhandled_input`；鼠标 `root.push_input` → GUI 命中 → `gui_input`）。
**不出进程、不碰宿主输入队列**（项目规则禁止对别的窗口盲发按键）。

### 3.1 有窗口跑：**20/20 PASS**

```
ASSERT|K1_menu_visible|true|true|PASS
ASSERT|K1_state_selecting|selecting|selecting|PASS
ASSERT|K1_default_selected|Cat|Cat|PASS
ASSERT|K2_key_selects_second|Mouse|Mouse|PASS               # 按 "2"
ASSERT|K2_key_switches_page|1 (species)|1|PASS
ASSERT|K2_no_spawn_on_select|selecting|selecting|PASS        # 选物种不等于出生
ASSERT|K3_enter_spawns|alive|alive|PASS                      # 按 Enter
ASSERT|K3_spawned_species|Mouse|Mouse|PASS
ASSERT|K3_menu_hidden|false|false|PASS
ASSERT|K3_hud_visible|true|true|PASS
ASSERT|K3_player_camera|Camera3D|Camera3D|PASS
ASSERT|K4_back_to_select|selecting|selecting|PASS
ASSERT|K4_menu_visible_again|true|true|PASS
ASSERT|K4_record_text_present|含 上一世|上一世：L0001 Mouse 存活 0.2 s｜…|PASS
ASSERT|M1_click_selects|Cat|Cat|PASS                         # 鼠标点卡片
ASSERT|M1_click_species_page|1 (species)|1|PASS
ASSERT|K5_esc_back_to_main|0 (main)|0|PASS                   # Esc
ASSERT|M2_start_opens_species_page|1 (species)|1|PASS         # 鼠标点「开始游戏」
ASSERT|M2_start_no_spawn|selecting|selecting|PASS
ASSERT|M3_enter_after_click_spawns|alive|alive|PASS
SUMMARY|checks=20|failures=0
```

### 3.2 一个必须记录的引擎限制（**不是我们的 bug**）

同一套件加 `--headless` 跑会挂 2 条（`M2`/`M3`，即"点按钮"）。原因实测：

```
PROBE|rect=[P: (64.0, 321.0), S: (384.0, 47.0)]|hovered=false|filter=0
PROBE|center=(256.0, 344.5)|viewport=(64.0, 64.0)     ← 无头根视口只有 64×64
PROBE|A_hover_after_motion=false                      ← 鼠标进入事件不来
```

`BaseButton` 只有在 `is_hovered()` 为真时才发 `pressed`；无头模式（dummy DisplayServer）根视口 64×64 且没有鼠标进入事件，
所以**按钮点击只能有窗口验证**。卡片用的是自己的 `gui_input`，两种模式都能命中（headless 下 M1 也是 PASS）。
→ 套件已注明"必须不加 `--headless`"，跑法写进 `Docs/Tasks/ART05.md`。

---

## 4. 打包复验

```
& $g --headless --path Game\Reborn --export-debug "Windows Desktop"        Builds\P0-Win64\Reborn.exe          → exit 0
& $g --headless --path Game\Reborn --export-debug "Windows Desktop SelfTest" Builds\P0-Win64\RebornSelfTest.exe  → exit 0
```

包内断言（编辑器二进制 + `--main-pack`）：

| 套件 | 源码 | 包内 |
|---|---|---|
| run_t002 | 18/18 | **18/18** |
| run_t008_species | 118/118 | **107/107**（11 条是读 `.gd` 源码的静态检查，包内按既有口径标 NOT-APPLICABLE） |
| run_t018_hud | 73/73 | **73/73** |
| run_t030_lifecycle | 111/111 | **111/111** |
| run_art02_cat | 72/72 | **72/72** |
| run_art05_settings | 20/20 | **20/20** |

### 4.1 一个**必须报告的**体积变化（不是本轮引入的缺陷，但以前没暴露）

| 文件 | 复验前（2026-10-20 构建） | 本轮复验后 |
|---|---|---|
| `Reborn.pck` | 289,832 B | **30,044,160 B** |
| `RebornSelfTest.pck` | 968,900 B | **30,834,120 B** |

原因：预设 `export_filter="all_resources"`，而 `Game/Reborn/assets/` 里的 **`.glb` 与贴图源文件**（猫 6.9 MB、巨石 3.0 MB、
洞口 3.1 MB、围栏/矮墙/料石各 1.8 MB…）现在都算"资源"，会被**连同已导入的产物一起**打进包里。
上一次构建是 2026-10-20，**早于 ART03 的一批美术资产**，所以那时只有 289 KB。
**这不是我改出来的**，但按现在的预设重新打包就会是 30 MB。

可选修法（**需负责人决定，本轮未动预设**）：把预设改成 `export_filter="resources"`，或加 `exclude_filter` 排除 `*.glb`/`*.png`。

---

## 5. 回归（源码 `--headless`，全部单独跑）

| 套件 | checks | failures |
|---|---|---|
| run_t002 / run_t005_asset / run_t006_rig / run_t007_input / probe_step_height | 18 / 50 / 65 / 22 / 6 | 0 |
| run_t008_species | 118 | 0 |
| run_t009_cat_movement / run_t010_mouse_movement | 81 / 95 | 0 |
| run_t011_greybox / run_t012_navigation | 210 / 79 | 0 |
| run_t013_debug_entry / run_t013_movement_regression | 159 / 73 | 0 |
| run_t014…run_t022（survival/costs/interaction/food/hud/mouse_ai/perception/capture/loop） | 106/93/118/128/73/72/164/279/168 | 0 |
| run_t023_cat_ai / run_t024_chase_search / run_t025_attack | 178 / 136 / 175 | 0 |
| run_t026_cover / run_t027_ecology / run_t029_sprint_chase / run_t030_lifecycle | 96 / 96 / 39 / 111 | 0 |
| run_art01_bush / run_art02_cat / run_art03_mouse | 83 / 72 / 45 | 0 |
| **新增** `run_art05_settings`（headless 可跑） | 20 | 0 |
| **新增** `run_art05_input`（**非 headless**） | 20 | 0 |

合计 **34 套 / 3,566 条断言，0 失败**（`run_art05_input` 需窗口，见 §3.2）。

`tests/tool_t028_walkthrough.gd`（走查工具，非断言套件）：`W1/W2/W3 PASS`、`W4_players_survived FAIL` ——
与 ART04 §5.1 相同，**改前基线同样失败**，属 T029 §6① 既有缺陷（洞里能被咬），未在本轮改平衡。

---

## 6. 未做 / 未验证

1. **第三人称的撞墙视觉证据**：只有数值断言（臂长 1.30 → 0.289）+ 代码路径，**没有**"贴墙时的实拍帧"。要补就得搭一个贴墙机位。
2. **无头模式下的按钮点击**：引擎限制（§3.2），只能有窗口验证；CI 若要跑必须给窗口。
3. **打包体积**（§4.1）未处理，等负责人定预设策略。
4. 第三人称没有做**镜头平滑/弹簧插值**（当前是硬跟），快速转向时会有跟随感生硬 —— 与"动作生硬"同类问题，值得下一轮做。
5. 设置持久化只覆盖两项（灵敏度 / FOV）；音量、按键重映射、分辨率都没有。
6. 没有做真人试玩（U01 仍 NOT-RUN）。

---

## 7. 边界声明

- 未安装/卸载软件；未连接 MCP；未改 git 全局配置；未删除源资产；未推送、未发布。
- 改动的生产文件：`scripts/data/species_config.gd`、`scripts/characters/animal_body.gd`、`scripts/core/main_entry.gd`、
  `scripts/ui/main_menu.gd`、`resources/species/{cat,mouse}.tres`；新增 `scripts/core/game_settings.gd`。
- 改动的测试：`run_t008`（按模式分支 + 4 条新断言）、`run_t009` / `run_t010` / `run_t013×2`（显式钉第一人称）、
  `run_t016`（`_eye()` 改用 `eye_position()`，修夹具缺陷）；新增 `run_art05_input.gd`、`run_art05_settings.gd`、`tool_capture_tp.gd`。
- 未改：关卡 `.tscn`、导航 `.tres`、导出预设、`project.godot`、生存/AI/捕获/攻击/生命周期逻辑。
- 视觉 PNG 走 LFS；新增 `.gd` / `.tres` / `.md` 保持纯文本可 diff。
