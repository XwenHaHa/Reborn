# ART05 第三人称 / 设置持久化 / 输入验证 / 打包复验（ART04 四项遗留的落实）

> 指派：负责人对 `Docs/Evidence/ART04.md` §6 的四条遗留逐项决定（1 第三人称 / 2 做 / 3 验证 / 4 复验）。
> 证据：`Docs/Evidence/ART05.md`。

## 1. 目标

1. **第三人称**成为正式玩法视角（代言生物要看得到自己的身体与步态），但**不删**第一人称契约（T009/T010/T013 的验收口径仍是它）。
2. **设置持久化**：鼠标灵敏度 / 视野真正写盘，重启后还在。
3. **输入链路验证**：用引擎自己的输入系统验证"数字键 / 回车 / Esc / 鼠标点卡片 / 鼠标点按钮"，取代此前"只调 API 截图"的间接验证。
4. **打包复验**：两个导出预设重跑 + 包内断言。

## 2. 目标路径

| 角色 | 路径 |
|---|---|
| 相机模式数据 | `scripts/data/species_config.gd`（`CAMERA_FIRST_PERSON/THIRD_PERSON`、`camera_mode`、`third_person_*`）+ `resources/species/{cat,mouse}.tres` |
| 第三人称相机 | `scripts/characters/animal_body.gd`（`_update_third_person_camera()` / `eye_position()` / `is_third_person()`） |
| 设置读写 | `scripts/core/game_settings.gd`（**新**，`ConfigFile` → `user://settings.cfg`） |
| 设置装配 | `scripts/core/main_entry.gd`（`settings_path` / `_load_settings()` / `current_settings()` / `_apply_settings_to()`） |
| 设置面板 | `scripts/ui/main_menu.gd`（`build(configs, initial_settings)` / `settings_values()` / `set_setting()`） |
| 新断言 | `tests/run_art05_settings.gd`、`tests/run_art05_input.gd`（**非 headless**） |
| 新取证 | `tests/tool_capture_tp.gd`（**非 headless**）→ `Art/Probes/art05_tp_*.png`、`art05_settings_saved.png` |

## 3. 数据与事件

- **相机**：`camera_mode` 决定 `AnimalBody` 走哪条相机路径；第三人称用
  `third_person_distance`（臂长）、`third_person_aim_height`（枢轴高度）、`third_person_down_tilt_deg`（固定下俯）、
  `third_person_pitch_min/max_deg`（俯仰限制）。**代码里没有物种名分支**。
- **交互原点**：`eye_position() = 身体中心 + camera_offset_z（蹲下减 crouch_drop）`，与相机模式无关。
  第一人称下它等于相机位置（旧口径不变），第三人称下它是"头部眼睛"。
- **设置**：`{sensitivity: 倍数（1.0 = 0.0025）, fov: 0|60–110}`；`0` = 不覆盖物种 `fov`。
  写盘时机 = 菜单滑块变化；读盘时机 = `MainEntry._ready()`（先读再建菜单，滑块回填）。
- **信号**：沿用 `MainMenu.setting_changed(key, value)`（不新增跨层耦合）。

## 4. 步骤

1. `SpeciesConfig` 加相机模式与第三人称参数 + `validate_config()` 校验（模式合法、第三人称臂长 > 0）。
2. `AnimalBody`：`is_third_person()`、`apply_look()` 按模式夹俯仰、`_update_camera()` 分派、
   `_update_third_person_camera(with_collision)`（每物理帧 + 撞墙收臂）、`eye_position()` 与模式解耦。
3. 两个 `.tres` 设第三人称参数（猫 1.30/0.18，鼠 0.55/0.08）。
4. 既有套件按口径处理：T009/T010/T013×2 显式钉第一人称；T008 按模式分支并加 4 条第三人称断言；
   T016 的 `_eye()` 改用 `eye_position()`（修夹具缺陷）。
5. `GameSettings` + `MainEntry` + `MainMenu` 三处接线（读 → 回填 → 改 → 写 → 出生生效）。
6. 两个新断言套件 + 一个取证工具；跑全量回归。
7. 两个预设重导出 + 包内断言（`--main-pack`）。

## 5. 验收用例

| 用例 | 判据 |
|---|---|
| U1 第三人称 | 猫/鼠出生后相机在身后、臂长 = 配置值；撞墙时收臂且 ≥ 0.28 m |
| U2 第一人称不回退 | T009/T010/T013×2 钉住第一人称后仍全绿（相机在胶囊内、眼高 = `camera_offset_z`） |
| U3 交互口径 | T016 118/118（交互原点与相机解耦） |
| U4 设置往返 | 默认/往返/夹紧/损坏四条全过 |
| U5 设置生效 | 出生后玩家 `camera.fov` = 存盘 FOV、`mouse_sensitivity` = 0.0025 × 倍数 |
| U6 输入链路 | 数字键选中、回车出生、Esc 返回、鼠标点卡片、鼠标点按钮 —— 20/20（**需窗口**） |
| U7 打包 | 两预设 exit 0；包内 t002/t008/t018/t030/art02/art05_settings 全绿 |

## 6. 跑法（关键差异）

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'

# 普通断言（无头）
& $g --headless --path $proj --script 'res://tests/run_art05_settings.gd' --quit-after 60000

# 输入链路：**必须不能加 --headless**（无头根视口 64×64、没有鼠标进入事件 → 按钮不发 pressed）
& $g --path $proj --script 'res://tests/run_art05_input.gd' --quit-after 6000

# 第三／第一人称取证（非 headless）
& $g --path $proj --script 'res://tests/tool_capture_tp.gd' --quit-after 9000 -- tp

# 打包 + 包内复验
& $g --headless --path $proj --export-debug "Windows Desktop" "E:\Reborn\Builds\P0-Win64\Reborn.exe"
& $g --headless --path $proj --export-debug "Windows Desktop SelfTest" "E:\Reborn\Builds\P0-Win64\RebornSelfTest.exe"
& $g --headless --main-pack 'E:\Reborn\Builds\P0-Win64\RebornSelfTest.pck' `
    --script 'res://tests/run_t008_species.gd' --quit-after 300000
```

## 7. 失败恢复

- 第三人称出问题 → 两个 `.tres` 改成 `camera_mode = 0`（或整个删掉该行取默认第三人称的相反值）即回第一人称；断言会跟着分支走。
- 设置文件坏了 → `GameSettings` 自动回落默认值（不崩）；想彻底忽略存盘，把 `MainEntry.settings_path` 置空即可。
- 输入套件在 CI 无窗口跑 → 预期失败 2 条（按钮），改用 `--headless` 只跑 `run_art05_settings`；UI 命中验证必须有窗口。
- 打包体积 30 MB → **未处理**，属预设策略（`export_filter`），需负责人定。

## 8. 不做（本轮边界）

- 不做第三人称镜头平滑/弹簧插值（硬跟；下一轮）。
- 不做音量/键位重映射/分辨率等其它设置项。
- 不改导出预设（体积问题只报告，不擅自改策略）。
- 不做真人试玩（U01）。
