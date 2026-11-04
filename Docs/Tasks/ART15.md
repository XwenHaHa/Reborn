# ART15：角色接地感（环境 SSAO / 接触阴影）

状态：**done（2026-11-04；视觉门按 vision 判读到可验证 PASS，不是正式美术 approved）**
工程：`E:/Reborn`，Godot 4.7.2 + GDScript（Forward+）。

## 1. 目标

负责人已授权对 ART10/ART13 冻结的场景光照做**最小范围**的 SSAO / 接触阴影调整，
专治"角色像贴纸浮在地上"。范围严格限定：

- 只调 SSAO（半径/强度）与接触阴影相关（阴影偏移），使其在**角色尺度**
  （猫 0.48 m / 鼠 0.18 m）有效；
- 不改主光方向、色温、体积雾、DOF、色调映射；不改玩法、碰撞、导航、几何；
- 不新增模型/第三方资产；场景结构与节点树不动（只改参数）；
- 猫和鼠分别看，不只为猫调。

## 2. 做法（一步一类参数）

| 步 | 改动 | 只改 | 取证 |
|---|---|---|---|
| S0 | 改前基线 | — | `Art/Probes/art15_before/`（8 图） |
| S1 | `ssao_radius 1.2 → 0.45`（强度/幂次/锐度/细节不动） | SSAO 半径 | `Art/Probes/art15_ssao/`（8 图） |
| S2 | `shadow_normal_bias 默认 2.0 → 0.8`（偏置/模糊/方向不动） | 接触阴影 | `Art/Probes/art15_contact/`（8 图） |

每步同机位前后对比板在 `Art/Probes/art15_compare/`（`cmp_ssao_*`、`cmp_contact_*`），
判读统一用三问：①脚底/腹部与地面是否"咬住" ②有无黑块/脏边/光晕 ③轮廓是否清晰。

## 3. 机位（固定，距离按物种胶囊高缩放）

| 机位 | 位置 | 说明 |
|---|---|---|
| stand | (1.0, 0.10, 6.0) | 开阔地站立 |
| walk | 同上，Walk 定格 0.28 s | 鼠有 Walk clip；猫也含同名 clip，姿态定格避免漂移 |
| wall | z = 30.0 − 胶囊半径，x=0 | 北侧围栏墙面；身体与墙脚接触缝 |
| rock | (-14.0, 1.104233, 8.0) | 溪中巨石 CreekBoulder 碰撞盒顶面 |

## 4. 验收

- 四机位 × 两物种的 vision 判读均给出"咬住改善 + 无黑块脏边 + 轮廓清晰"；
- 改前/改后平均帧时间实测并给出回退档位；
- 回归：`run_art09_frame_contract`、`run_t011_greybox`、`run_t012_navigation`、
  `run_art08_character_contract`、`run_art09_species_layout`、`run_art02_cat`、
  `run_art03_mouse`、`run_art08_board_contract`、`run_art08_environment_contract`、
  `run_art09_menu_contract`、`run_art09_portrait_contract` 全绿；
- gameplay 断言零改动。

## 5. 失败恢复

- 观感退化：只回退 `l_courtyard.tscn` 的 `ssao_radius` / `shadow_normal_bias` 两行，
  并同步 `tests/tool_make_courtyard.gd` 两处（`env.ssao_radius`、`light.shadow_normal_bias`）；
- 性能不可接受：先回退 `shadow_normal_bias`（成本≈0），再回退 SSAO 半径；
- 场景不得整体重新生成：当前生成器不写导航资源，重生成会丢 `l_courtyard_{mouse,cat}.tres`
  的引用并刷新全部 `unique_id`，因此 ART15 只直接改 tscn 参数行。
