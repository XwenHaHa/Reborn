# ART10 任务规格：展板差距诊断与低风险视觉改进轮

状态：**awaiting-review（2026-11-02 收口）**——B1–B6 全过；B7 视觉复判：氛围/构图项大幅改善（见证据 §4），
水面折射、草融合、磨砂面板等仍 FAIL/部分通过；不是 done，不是 approved。
任务身份：**临时视觉任务**（非总计划 T 任务；上位参照 `Docs/Tasks/ART09_BOARD_PARITY.md` 的"向展板收敛"目标）
范围授权：负责人本轮指令——"缩小实机美术与《轮生：森林生存游戏概念展板》差距"，仅第一阶段（诊断 + 复用现有资产的低风险改进）。

## 1. 目标

1. 用 vision（`node E:/claude-vision-skill/vision.js`）拆解概念展板美术要素，并对实机（主菜单 / 物种选择 / 展板切片关 / 玩法庭院）逐项对比，产出 GAP 表。
2. 只做**复用现有 .glb、shader 参数、引擎后处理与摆放**的改进；不新增外部资产、不改玩法/碰撞/导航、不换猫鼠模型。
3. 改前/改后同一机位取证，vision 复判，如实记录 PASS/FAIL。

## 2. 明确不碰的东西

- **ART07 未提交改动**（`l_courtyard.tscn`、`grass_wind.gdshader`、`run_t011_greybox.gd`、`tool_capture_render.gd`、`tool_make_courtyard.gd` 及其 Docs）：保持原样，不纳入本任务提交。
- `creek_water.gdshader` / `ground.gdshader` **文件本身**（庭院共用）：只在展板关的 **材质实例参数** 上调，不动 shader 源码。
- 玩法场景 `l_courtyard` 的几何/碰撞/导航/灯光。
- HUD 布局与四条状态条语义色（T018 / ART09-D 契约）。

## 3. 改动真源

| 路径 | 改动 |
|---|---|
| `Game/Reborn/tests/tool_make_ravine_board.gd` | 光照改**侧逆光**、体积雾、深度雾/辉光/SSAO 调参、水面材质参数、岸板/泥舌换湿砾石贴图、地面色调、近景草加密放大 |
| `Game/Reborn/scenes/maps/l_ravine_board.tscn` | 生成器产物（重建） |
| `Game/Reborn/tests/tool_capture_art09_board.gd` | TP 机位加**前景近景深**、加强远景深 |
| `Game/Reborn/scripts/core/main_entry.gd` | 菜单展示模型加**暖色轮廓光**（只挂 MenuCamera 下，出生即隐藏，不进玩法） |
| `Game/Reborn/scripts/ui/main_menu.gd` + `board_tokens.gd` | 面板底色从暗青灰向**深灰蓝**收（展板磨砂面板方向） |

## 4. 参数登记（old → new，全部可回退）

### 4.1 展板切片关（tool_make_ravine_board.gd）

| 项 | old | new | 理由（vision 诊断） |
|---|---|---|---|
| BoardSun 旋转 | (-24, 32, 0)（顺光，从镜头侧） | **(-14, 196, 0)**（低角度侧逆光，从溪谷后方射向镜头） | 实机"无方向光、无轮廓光、无长影"；展板是侧逆光+轮廓光 |
| BoardSun 能量/色 | 1.45 / (1.0,0.90,0.72) | 1.60 / (1.0,0.83,0.60) | 逆光下需要更强的暖金主光 |
| BoardSkyFill 能量 | 0.38 | 0.55 | 逆光后主体背光面需抬高，避免黑死 |
| 体积雾 | 无 | `volumetric_fog_enabled`，density 0.016、anisotropy 0.72、albedo 暖灰 | 展板有丁达尔光柱/薄雾；实机"完全没有空气介质" |
| 深度雾 | begin 9 / end 46 / sky_affect 0.10 / 色 (0.68,0.74,0.78) | begin 9 / **end 38** / sky_affect **0.15** / 色 **(0.74,0.71,0.62)** | 远景与中景"清晰度饱和度完全一致" |
| 辉光 | intensity 0.30 / bloom 0.04 | **0.50 / 0.06** | 展板"太阳边上发亮"的水面高光 |
| SSAO | radius 1.1 / intensity 2.4 | **1.35 / 2.8** | 接触感/OE 不足 |
| 水面实例参数 | base_alpha 0.32 / roughness 0.35 / spec 0.25 / ripple 9 / strength 0.18 / foam_width 0.09 / foam_str 0.35 / flow 0.22 | **0.26 / 0.28 / 0.34 / 13 / 0.26 / 0.03 / 0.22 / 0.30** | "塑料板/泳池"；泡沫带把矩形水岸描出来了 |
| 岸板 ShorePlate 材质 | 纯色深灰 (0.15..0.22) | **湿砾石贴图**（dry_river_pebbles，uv 1.4×0.6，tint 0.44 压暗，roughness 0.42） | "灰色悬空板/沥青带"是本轮最刺眼问题 |
| 泥舌 MudTongue 材质 | 纯色 (0.262,0.236,0.202) | 湿砾石贴图（tint 0.40，roughness 0.50） | 同上 |
| 地面 tint / uv | (0.62,0.66,0.58) / 22×24 | **(0.50,0.58,0.46) / 15×17** | "秋叶地毯"与冷绿基调冲；贴图平铺太碎 |
| 近景草 | 96 株 × 0.10–0.22 | **128 株 × 0.16–0.36** | "草的比例和密度与猫完全不匹配" |

### 4.2 取证机位（tool_capture_art09_board.gd）

| 项 | old | new |
|---|---|---|
| TP 远景深 | distance 7 / transition 5 / amount 0.06 | **8 / 4 / 0.10** |
| TP 近景深 | 无 | **near enabled，distance 0.7 / transition 0.45**（前景草虚化，展板前景失焦） |

### 4.3 菜单（main_entry.gd / main_menu.gd / board_tokens.gd）

| 项 | old | new |
|---|---|---|
| 菜单轮廓光 | 无 | `MenuRim`（MenuCamera 子节点，暖金 0.85，从主体后方打向镜头，出生即隐藏） |
| COLOR_PANEL | (0.035,0.047,0.049,0.90) | **(0.043,0.055,0.075,0.90)** |
| COLOR_PANEL_SEL | (0.090,0.103,0.093,0.965) | **(0.085,0.105,0.135,0.965)** |
| 物种页卡底/槽底 | (0.028,0.040,0.042,0.72) / (0.020,0.030,0.030,0.90) | **(0.032,0.043,0.060,0.76) / (0.024,0.034,0.048,0.90)** |
| BoardTokens.PANEL 族 | PANEL `07141ddd` / SEL `16211ff2` / RAIL_BG `08141af0` | **`0a1018dd` / `16202af2` / `0a1018f0`**（暗青→深灰蓝） |

## 5. 用例（验收）

| 用例 | 判据 |
|---|---|
| B1 生成器 | `tool_make_ravine_board.gd` 退出码 0，`TOOL|save_result=0 (OK)` |
| B2 契约 | `run_art09_frame_contract.gd` 全绿（逆光后 `sun_is_warm`/能量区间/水面三参数仍满足） |
| B3 菜单/物种回归 | `run_art09_tokens` 15/15、`run_art09_menu_contract` 42/42、`run_art09_species_layout` 59/59、`run_art09_portrait_contract` 24/24 |
| B4 玩法不受影响 | `run_t030_lifecycle` 111/111、`run_t018_hud` 73/73；`main.tscn` 仍不引用 ravine |
| B5 取证 | 非 headless `tool_capture_art09_board -- ravine`：`SUBJECT|px_ratio` 在 0.20–0.30、全部 `save_result=OK` |
| B6 菜单取证 | 非 headless `tool_capture_art08_integration -- integration` 五图 `save_result=OK` |
| B7 视觉复判 | 改后 ravine_tp / env_creek / env_far / menu 用 vision 复判，与改前逐项对比并如实记录 |
| B8 日志干净 | 无 `SCRIPT ERROR` |

## 6. 失败回退

- 生成器/工具全部是纯文本常量改动，按 §4 表逐项回退后重跑生成器即可。
- `l_ravine_board.tscn` 由生成器重建，不手改。
- 菜单改动集中在 3 个文件的常量/一个新灯节点，`git checkout --` 即可整体回退。
- vision 不可用或取证超时：记 NOT-VERIFIED，状态最多 awaiting-review。

## 7. 需要负责人授权的差距（本轮明确不解决）

见 Evidence 文档 §"复用现有资产也补不上的差距"。
