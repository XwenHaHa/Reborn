# ART14 证据：不换模型的角色质感提升

执行日期：2026-11-04（本机系统时钟）
任务规格：`Docs/Tasks/ART14.md`。状态：**done（视觉门按 vision 判读到可验证 PASS；不是正式美术 approved）**
工程：`E:/Reborn`，Godot 4.7.2 / Forward+ / Windows。取证一律 `Tools/CaptureRun.ps1`（隐藏桌面、`visible_hits=0`、不用 console 版 exe）。

## 1. 变更范围

| 文件 | 改动 |
|---|---|
| `Game/Reborn/scripts/characters/character_material.gd` | **新**：运行时表面覆盖材质（S1～S4 常量与档位 `step_level`） |
| `Game/Reborn/shaders/character_fur.gdshader` | **新**：皮毛面 shader（albedo/normal 贴图透传、`fur_*` 粗糙度镜面、微法线、rim、`BACKLIGHT`） |
| `Game/Reborn/scripts/characters/animal_body.gd` | `_rebuild_visual()` 增加一行 `A14CharacterMaterial.apply_to(...)`（只材质，无玩法改动） |
| `Game/Reborn/tests/tool_capture_art14_material.gd` | **新**：ART14 判读机（固定四灯 + 三机位 + 灰地 + 档位/接触参数） |
| `Game/Reborn/tests/tool_probe_art14_materials.gd` | **新**：材质参数探针（headless 只读，输出 `PROBE|...`） |
| `Tools/make_art14_compare.ps1` | **新**：左右拼板（System.Drawing，640×640×2） |
| `Art/Probes/art14_{baseline,s1,s2,s3,s4,contact0,contact1}/`、`Art/Probes/art14_compare/` | 样张与对比板（36 张板） |

未改：猫/鼠 glb 与动作、`species.tres`、碰撞/导航/玩法/速度参数、游戏场景光照（展板关光照仍为 ART10/ART13 状态）、`menu_creek.png`、`forest_floor`。
**没有新增任何第三方资产/贴图**（本轮全部程序化）。

## 2. 塑料感清单（改前，最终机位）

猫/鼠基线（`art14_baseline`）vision 判读 **2/10**，读作"抛光树脂/塑料手办"。五项读作塑料：
1. 高光锐利且集中（镜面 0.5、粗糙度 0.72/0.80）；
2. 没有次表面（耳朵/鼻不透光，像实心块）；
3. 轮廓硬切（没有毛发边缘过渡）；
4. 表面绝对光滑（无绒毛微观起伏）；
5. 接触处发假（脚底与地面缺少贴合暗部）。

## 3. 逐项判读（每项单独同机位前后对比 + vision）

判读工具：负责人指定 `node E:/claude-vision-skill/vision.js <png> <中文问题>`。分数与结论按模型原话记录。

| 项 | 对比板 | 判读 | 结论 |
|---|---|---|---|
| **S1 猫** PBR 0.72→0.84 / 镜面 0.5→0.26 | `cmp_s1_cat_front34` | **6.5/10**：塑料油亮明显减少、高光被打散；**没有变糊/变平**；略偏"磨砂绒布" | **PASS** |
| **S1 鼠** | `cmp_s1_mouse_front34` | **3/10**：从"亮面塑料"变成"哑光橡皮泥"，无毛流细节（鼠模型**没有法线贴图**） | 部分（高光治住，肌理天花板） |
| **S2 绒毛微法线** 0.08 | `cmp_s2_cat_front34` | **3/10**：均匀的磨砂砂纸感、略微变脏；斑纹未被破坏 | **FAIL → 默认关闭** |
| **S3 猫轮廓光** 0.28 | `cmp_s3_cat_front34` | **5.5/10**：光晕均匀平滑，读作柔光滤镜、边缘变糊 | 失败 → 降档 |
| **S3 猫轮廓光** 0.16 | `cmp_s3_cat_front34`（最终） | **7/10**：克制自然的暖色边缘提亮，不糊边、不提亮正面、不假 | **PASS** |
| **S3 鼠轮廓光** 0.28 | `cmp_s3_mouse_front34` | **4/10**：读作"毛绒玩具/磨砂塑料光晕" | 失败 |
| **S3 鼠轮廓光** 0.12 | `cmp_s3_mouse_front34` | **2/10**：几乎看不出（**无害但也无收益**） | 天花板（保留 0.12 只因 0.28 会主动变坏） |
| **S4 猫薄处透光** 0.35 | `cmp_s4_cat_back` | **8.5/10**：耳缘/背脊透暖光、像薄皮肤、暗部有散射、无过曝 | **PASS** |
| **S4 猫薄处透光** 0.35 | `cmp_s4_cat_front34` | **7.5/10**：耳尖/鼻口轻微透光，无荧光、无糊、斑纹清楚 | **PASS（偏保守）** |
| **S4 猫薄处透光** 0.60（试验） | `cmp_s4_cat_back`（已废弃样张） | **3.5/10**：发光塑料、斑纹被洗淡 | 回退 0.35 |
| **S4 鼠薄处透光** 0.50（试验） | — | **2/10**：正面几乎看不出 | 上调 |
| **S4 鼠薄处透光** 0.85（试验） | — | **5.5/10**：逆光红光过饱和、尾部像发光塑料、暗部死黑 | 回退 0.45 |
| **S4 鼠薄处透光** 0.45 | `cmp_s4_mouse_back` | **8.5/10**：尾巴根部/耳缘透红棕暖光、有厚度衰减、体积更通透 | **PASS** |
| **S5 接触遮蔽** SSAO 0.30→0.06 / 3.0 | `cmp_s5_cat_front34` | **8/10**：脚底/腹部阴影收拢贴合，"悬浮感"治好，无黑斑/遮蔽环；仅阴影衰减略硬 | **PASS（只用于取证机位）** |

**最终整体**（`cmp_final_*`）：
- 猫：**2/10 → 5.5/10**。治住：高光塑料、硬边、实心树脂、脚底悬浮；剩余：光滑剪影（无毛发几何）。
- 鼠：**2/10 → 4.5~5/10**。治住：油亮、死黑、耳朵/尾巴无透光；剩余：零微观肌理，且**整体被薄处透光轻微提亮/暖化**（判读记为可接受副作用，未过曝）。

## 4. 天花板与最小解除（不用调参掩盖）

1. **毛发绒感（S2）**——现有模型没有毛发方向图/几何毛发，程序化各向同性噪声只能做出"砂纸/磨砂漆"。
   最小解除：**毛发卡片/壳层几何（Hair Cards/Shells，优先做轮廓：腹部下缘、胸、尾、耳缘）**，
   或授权的毛发 tiling 贴图（albedo 方向 + 法线 + 粗糙度三件套）。仅换参数无效。
2. **鼠轮廓光/微观肌理（S3）**——单面材质且无法线贴图，强轮廓读作毛绒光晕、弱轮廓看不出。
   最小解除同 1；另需**拆分眼睛/鼻面**，否则统一粗糙度会让眼睛失去高光（现模型单面材质包含眼鼻）。
3. **真次表面散射（S4）**——`BACKLIGHT` 只是方向性近似，没有厚度图/散射半径，正面效果必然偏弱
   （0.60 在逆光会直接过火）。最小解除：带厚度（thickness）贴图的 SSS 或毛发透光方案。
4. **接触处发假（S5）**——现有游戏环境 SSAO 半径 0.3 m 对 3～6 cm 腿径几乎无效。
   最小解除：把世界环境 SSAO 半径调到角色尺度（~0.06 m）或启用 contact shadow。
   **本轮只改取证机位**；游戏关的光照/后处理已被 ART10/ART13 冻结，改它需要负责人授权。

## 5. 附带修掉的取证 bug（重要）

早期样张把 `body.position` 放在 `Vector3.ZERO`，而胶囊是**居中**的（脚底在原点下方 `cap_h/2`）→
模型半截陷进地面：画面只剩一个头、接触处是硬直线、也没有接触阴影。修正为
`body.position.y = capsule_height/2`（与游戏生成一致）后重拍全部档位；**早期被判"整屏像塑料玩具"的 1.5/10 已作废，本文件所有分数均为修正后机位**。
另一个坑：glTF 蒙皮网格 `get_aabb()` 是绑定姿态（猫 2 cm、鼠 1 mm），不能用来取景；
改用"透明底 alpha 闭环 + 平移视线目标"（初始 1.6 m），两物种均收敛到 fill≈0.64。

## 6. 回归（全部走 `Tools/CaptureRun.ps1`，gameplay 断言零改动）

| 套件 | 结果 |
|---|---|
| `run_t008_species` | 118/118 PASS |
| `run_t009_cat_movement` | 81/81 PASS |
| `run_t010_mouse_movement` | 95/95 PASS |
| `run_art02_cat` | 72/72 PASS |
| `run_art03_mouse` | 45/45 PASS |
| `run_art08_character_contract` | 15/15 PASS |
| `run_t033_formal_species` | 53/53 PASS |
| `run_t011_greybox` | 229/229 PASS |
| `run_t012_navigation` | 79/79 PASS |
| `run_t020_perception` | 164/164 PASS |
| `run_art09_frame_contract` | 48/48 PASS |
| `run_art09_portrait_contract` | 24/24 PASS |
| `run_art09_species_layout` | 59/59 PASS |

`run_art09_frame_contract` 退出时出现 Mesh/Material/Texture/Instance 的 RID 泄漏提示（引擎退出告警，非断言失败）。

## 7. 参数登记（旧值 → 新值）

| 参数 | 旧值 | 新值 | 依据 |
|---|---:|---:|---|
| `A14_FUR_ROUGHNESS`（猫） | 0.72（原始） | **0.84** | 0.94 被判"过度矫正、哑光橡皮泥"（5.5/10），0.84 判 6.5/10 |
| `A14_FUR_ROUGHNESS`（鼠） | 0.80（原始） | **0.84** | 同上（同一皮毛常量） |
| `A14_FUR_SPECULAR` | 0.50（原始） | **0.26** | 保留柔和方向性光泽，不做镜面 |
| `A14_FUR_NORMAL_STRENGTH` | — | **0.08 但默认关闭** | 判 3/10 砂纸 |
| `A14_RIM_STRENGTH`（猫） | — | **0.16** | 0.28 判 5.5/10 柔光滤镜；0.16 判 7/10 |
| `A14_RIM_MOUSE_STRENGTH` | — | **0.12** | 0.28 判 4/10 毛绒光晕；0.12 判 2/10（无害） |
| `A14_BACKLIGHT_CAT_STRENGTH` | — | **0.35** | 逆光 8.5/10；0.60 判 3.5/10 发光塑料 |
| `A14_BACKLIGHT_MOUSE_STRENGTH` | — | **0.45** | 逆光 8.5/10；0.85 判 5.5/10 红光过饱和 |
| 取证机位 SSAO | 半径 0.30 / 强度 2.0 | **半径 0.06 / 强度 3.0**（仅 `contact` 参数） | 接触判读 8/10 |

## 8. 边界与待授权

- 不 push；不删 `menu_creek.png` / `forest_floor`；未动 T037 并发文件（`autoload/*`、`main_entry.gd`、`Docs/Evidence/T037.md`）。
- **待授权 1**：把游戏世界环境 SSAO 半径调到角色尺度（或启用 contact shadow）——会改变展板关既有观感，需负责人点头。
- **待授权 2**：毛发卡片/壳层方案（几何毛发）需要建模或采购，超出"不换模型"范围。
- **待授权 3**：鼠面拆分（眼/鼻独立材质）需要资产工作或贴图掩码。
