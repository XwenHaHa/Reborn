# ART09-F 证据：角色肖像（F1）

状态：**F1 done / F2、F3 NOT-RUN**（2026-10-29）
分支：`art/modeling-pipeline`

## 1. 命令与结果

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
& $g --path $proj --script 'res://tests/tool_render_board_portraits.gd' --quit-after 40000 -- portraits
& $g --path $proj --headless --import
& $g --headless --path $proj --script 'res://tests/run_art09_portrait_contract.gd' --quit-after 60000
& $g --path $proj --script 'res://tests/tool_capture_board_visual.gd' --quit-after 40000 -- board
```

| 项目 | 结果 |
|---|---|
| `tool_render_board_portraits.gd`（新增，**非 headless**） | Cat/Mouse 各出一张 512×512；`save_result=0 (OK)` |
| `run_art09_portrait_contract.gd`（新增） | **24/24，0 failures，exit 0** |
| `run_art09_menu_contract.gd` | 42/42，exit 0 |
| `run_art09_species_layout.gd` | 59/59，exit 0 |
| `run_art08_board_contract.gd` | 9/9，exit 0 |
| `run_art09_tokens.gd` | 15/15，exit 0 |
| `tool_capture_board_visual.gd -- board`（**非 headless**） | 5 张 `save_result=0 (OK)`，`CAP\|board\|done` |

取景闭环实测（工具日志）：

```text
PORTRAIT|species=Cat|iter=1|dist=1.600|fill=0.30|dx=-15|dy=112
PORTRAIT|species=Cat|iter=3|dist=0.871|fill=0.62|dx=-33|dy=1
PORTRAIT|species=Cat|meshes=1|fill=0.62|dist=0.868|save_result=0 (OK)|res://assets/ui/portraits/portrait_cat.png
PORTRAIT|species=Mouse|iter=4|dist=0.236|fill=0.58|dx=-65|dy=-5
PORTRAIT|species=Mouse|meshes=1|fill=0.63|dist=0.224|save_result=0 (OK)|res://assets/ui/portraits/portrait_mouse.png
PORTRAIT_CONTRACT|Cat|512x512
PORTRAIT_CONTRACT|Mouse|512x512
PORTRAIT_CONTRACT|files=2
SUMMARY|checks=24|failures=0
```

## 2. 产物与截图

- 肖像：`Game/Reborn/assets/ui/portraits/portrait_cat.png`、`portrait_mouse.png`（各 512×512）
- 界面：`Art/Probes/art09_portraits_after/{board_menu,board_species_cat,board_species_mouse,board_species_narrow}.png`

## 3. 视觉判读

| 项 | 现状 | 判定 |
|---|---|---|
| 肖像主体完整入画 | 猫、鼠都完整（不切头切脚），填充率 0.62 | **PASS** |
| 肖像背景 | CC0 森林 HDRI，虚化树林，不是纯色 | **PASS** |
| 右栏卡片缩略图 | 换成本物种肖像（不再是灰底 3D 小模型） | **PASS** |
| 物种页缩略图行 | 同肖像；未来物种仍为 `?` 占位 | **PASS** |
| 物种页大卡「卡内大图」 | 用同肖像做**压暗背景**（alpha 0.28），文字仍可读 | **部分 PASS**（不是展板那种独立大图框） |
| 肖像质感 | 受限于现有 `sm_cat_002` / `sm_mouse_002` 模型本身（塑料感、鼠是深色大老鼠） | **FAIL（模型质量，非管线问题）** |
| 四态走态条 | **未做**（F3） | **NOT-RUN** |
| `sm_cat_004` 评估 | **未做**（F2） | **NOT-RUN** |

## 4. 过程中踩到的坑（都已修）

1. **直接实例化 glb 拍不到主体**：`sm_cat_002.glb` 源尺寸远大于真实猫，且 `AnimalBody` 才负责缩放到游戏尺寸 →
   裸实例化时相机贴在模型内部，渲出来只剩背景。改用 `AnimalBody` 承载。
2. **胶囊占位 `BodyMesh` 会出现在画面正中**（白色胶囊）→ 显式 `visible = false`。
3. **`SkinnedMeshInstance.get_aabb()` 不可用**（实测只有 0.02 m）→ 改为「渲一遍、量 alpha 包围盒」的闭环取景。
4. **探针底必须切成 `BG_CLEAR_COLOR` + `transparent_bg`**，否则 `get_used_rect()` 量到的是整张天空（fill=1.0）。

## 5. 边界 / 未验证

- 肖像只覆盖**有模型的物种**（猫、鼠）；兔/狐/鸟无模型 → 卡片仍是 `?`，不伪造。
- F2（`sm_cat_004` 对比）与 F3（四态拼条）本轮**没跑**，状态 `NOT-RUN`，不是"通过"。
- 猫扑击 / 鼠逃跑动作仍缺，界面/文档一律 `NOT-AVAILABLE`。
- 菜单里 `CardPortrait` 是压暗背景，不是展板那种"卡内独立大图框"——属**已知版式偏差**。
- 本机 vision 服务未调用，判读为截图人工对比。

## 6. 恢复入口

删除 `assets/ui/portraits/`、`tests/tool_render_board_portraits.gd`、`tests/run_art09_portrait_contract.gd`；
`cat.tres`/`mouse.tres` 去掉 `display_portrait` 行并把 `load_steps` 改回 4；
`main_menu.gd` 回退 `_make_portrait()` / `CardPortrait` 段后菜单自动回到实时 3D 缩略图。


## 7. F2 / F3 追加（2026-10-29）

### F2：`sm_cat_004` 评估 → **采纳**

用 `tests/tool_cat_gait_eval.gd` 对两个候选做同参数对比（`--clips=Walk,Run`，`dt=0.004167`）：

| 指标（Walk） | `sm_cat_002`（原） | `sm_cat_004`（新） | 判读 |
|---|---|---|---|
| 片段长度 | 1.0417 s | 0.3000 s | 004 更接近真实步频 |
| 根骨垂直起伏 `root_y` | **0.0000**（完全没有） | **0.0155** | 004 有重心起伏 |
| 最小膝角 `knee_angle_min` | **6.7°**（腿几乎笔直） | **51.7°** | 004 有屈膝，读得出"走路" |
| 腿部最大伸展 `stretch_max` | **1.0007**（超伸） | **0.9138** | 004 不超伸 |
| 支撑相占空比 `duty` | 无有效支撑帧 | 0.384–0.397 | 004 有明确支撑相 |

结论：**把 `cat.tres` 的 `visual_scene` 切到 `sm_cat_004.glb`**。
`run_art02_cat.gd` 里两处写死 `sm_cat_002` 的断言（`ASSET` 常量、`asset_root_name`）同步更新为 004 ——
这是"当前正式猫资产"的登记，不是放宽断言；改后 **72/72 PASS**（tris 8376、AABB 0.305×0.310×0.542 不变）。

回归：`run_art08_character_contract` 15/15、`run_t008_species` 118/118、`run_t009_cat_movement` 81/81 全绿。

### F3：四态展示条 → 猫 **PASS**、鼠 **FAIL（未解决）**

- 新工具 `tests/tool_capture_art09_gait.gd`（**非 headless**）：固定侧视机位 + 固定两灯，
  只改动画与采样时间（Idle 0.30 / Walk 0.02 / Walk 0.55 / Run 0.30），4 帧横向拼成 1024×256。
- 取景：先按填充率与**长度**反推一次距离（`k = max(fill_y/0.66, fill_x/0.86)`），再按像素偏差修视线高度；
  四帧共用同一机位，保证"只有姿势不同"。
- 产物：`Art/Probes/art09_gait/gait_cat_row.png`（**PASS**：站立/起步/行走/奔跑四态可辨、头尾完整、同侧视角）、
  `gait_mouse_row.png`（**FAIL**：鼠只有 7 cm 高，单次反推把相机拉到 0.48 m，鼠被压在画面底部且只剩背脊）。
- 已定位鼠条失败的原因：单次测量 + 固定的最小距离，不足以对"极小主体"收敛；需要像肖像那样做 2–3 轮
  「测量→平移→复测」闭环，或直接把 min-dist 与 cell 分辨率按物种尺寸分档。**本轮未修**，记为已知缺陷。

### 本节未验证

- 四态条只在 256 px 单元下产出，放大到展板尺寸会糊；要交付展示图需改用 512 或 768 单元重跑。
- 猫扑击 / 鼠逃跑动作仍缺（`NOT-AVAILABLE`）。
- 本机 vision 服务未调用，判读为截图人工对比。
