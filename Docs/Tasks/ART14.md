# ART14 任务规格：不换模型的角色质感提升

状态：**done（2026-11-04，视觉门按 vision 判读到可验证 PASS；不是正式美术 approved）**
证据：`Docs/Evidence/ART14_CHARACTER_MATERIAL.md`
范围：猫 `sm_cat_004.glb`、鼠 `sm_mouse_002.glb`（**不换模型、不新建模、不采购**）

## 1. 目标

把现有猫/鼠从"塑料/透明树脂"观感往上推。只允许：
- 材质与 shader（PBR 校正、绒毛微法线、轮廓绒光、薄处透光、接触 AO/阴影过渡）；
- 角色专属光照与相机前呈现参数（展示机位、受光）；
- 程序化/已在 `Docs/THIRD_PARTY_ASSETS.md` 登记的贴图（本轮**没有新增任何贴图**）。

禁止：改玩法、碰撞、导航、动画状态机与速度参数；改资产文件本身；`git add -A`。

## 2. 方法

1. 先列"哪一项读作塑料"（§3 的 S1～S5）；
2. **一项一项**改，每项单独同机位前后对比 + vision 判读，不堆参数；
3. 判读必须写清"改善了什么 / 有没有变糊、变亮、发假"，读不出结论就写 NOT-VERIFIED；
4. 现有模型做不到的，写"天花板 + 最小解除"，不用调参掩盖。

## 3. 分项与实现

| 项 | 内容 | 实现位置 |
|---|---|---|
| S1 | 皮毛 PBR 校正：粗糙度 0.72/0.80 → **0.84**、镜面 0.5 → **0.26**；眼睛等 `roughness<0.45` 的滑面不参与 | `scripts/characters/character_material.gd` |
| S2 | 绒毛高频法线（程序化值噪声扰动切线法线） | `shaders/character_fur.gdshader`，**默认关闭**（判为砂纸） |
| S3 | 轮廓绒光：Fresnel 掠射角 + 噪声调制，猫 0.16 / 鼠 0.12 | 同上 |
| S4 | 薄处透光：引擎 `BACKLIGHT` 近似 SSS，猫 (0.82,0.44,0.30)/0.35、鼠 (0.88,0.48,0.44)/0.45 | 同上 |
| S5 | 接触遮蔽：SSAO 半径按角色尺度（0.30 → 0.06 m、强度 3.0）—— 只在取证机位验证，**未改游戏环境**（展板关光照已被 ART10/ART13 冻结） |

接入口：`AnimalBody._rebuild_visual()` 里 `A14CharacterMaterial.apply_to(visual_root, species_config)`，
运行时挂 `set_surface_override_material`，**不写回 glb、不动碰撞/动画**。

档位（取证用，生产默认 `step_level=4`）：0 原始 / 1 S1 / 2 S1+S2（仅样张）/ 3 S1+S3 / 4 +S4。

## 4. 验收

- 每项有同机位前后对比板（`Art/Probes/art14_compare/`）+ vision 判读分数与结论；
- 猫、鼠最终样张相对原始基线的"真实皮毛感"分数上升；
- 回归：T011、T012、帧契约、以及读 `species.tres` 视觉字段的套件全绿，**gameplay 断言零改动**；
- 取证全部走 `Tools/CaptureRun.ps1`（隐藏桌面、`visible_hits=0`），不用 console 版 exe。

## 5. 失败恢复

- `character_material.gd` 是唯一挂载点，摘掉 `apply_to` 这一行即回到原始 glb 材质；
- 全部常量集中在文件头，按 `Docs/Evidence/ART14_CHARACTER_MATERIAL.md` §3 的判读记录回退。
