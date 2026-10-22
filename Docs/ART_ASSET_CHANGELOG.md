# ART_ASSET_CHANGELOG —— 资产与风格变更记录

规则：任何**外形/风格/参考来源**层面的变更都要记一条，写清"为什么"。
单纯修 bug（法线、非流形、命名）记在对应 `Docs/Evidence/Txxx.md`，这里只记资产决策。

---

## 2026-10-21 · ART03-⑥ 溪水与溪边视觉打磨

**变更类型**：环境视觉（**零玩法改动**）。

- 触发：负责人看图指出「草丛和溪边很假、水都不带动的」。
- 水面：`StandardMaterial3D`（纯色、无时间项）→ **程序化 `creek_water.gdshader`**：
  三层随时间滚动的 value-noise + 域扭曲 + 有限差分求法线 + 菲涅尔 + 岸边泡沫；`roughness 0.08` 出高光斑。
- 形状：`WATER_SIZE.z 20 → 9`，从"占满 Creek 区的池塘"收成 **22×9 溪带**（仍覆盖 `WaterPoint_Creek`）。
- 溪边：新增 `_add_creek_dressing()` —— **13 丛芦苇**沿两岸（yaw/scale 打散）+ 4 条**湿泥岸带**，
  把"蓝面硬切草地"改成"草 → 湿泥 → 水"。
- 硬约束未破：水面仍是 `MeshInstance3D + BoxMesh`、`water_depth=0.03`、`water_bodies` 组=1、零碰撞；
  新增节点全为 `MeshInstance3D`（零碰撞、不进导航组）。
- 取证：新增 `tool_capture_creek.gd`，同机位相隔 45 帧两帧：`mean_abs_diff 0.021/0.031`、
  `changed_px_ratio 0.31/0.43` ⇒ 水确实在动。
- 回归：全量 **30 套 / 3,173 条 / 0 失败**。
- 明确未做：草丛网格仍是 ART01 的**平面叶片**资产（近距离"绿纸条"），也没有风摆 —— 要改属独立任务。

---

## 2026-10-21 · ART03-⑤ 鼠动画接线 + 场景渲染实测

**变更类型**：行为接线（**视觉层**，不改玩法数值）+ 性能实测。

- `animal_body.gd`：`_bind_visual_animation()` / `_update_visual_animation(speed)` —— 按**实际水平速度**
  在 `Idle/Walk/Run` 之间切换，`speed_scale` 跟速度挂钩；只读速度与冲刺意图，**不写** `velocity`/`move_intent`；
  clip 缺失保持不动；没有 `AnimationPlayer` 的物种（猫）零影响。
- 验证：`run_art03_mouse.gd` 新增 6 条断言（静止→Idle、走→Walk、冲刺→Run、跑比走快、停下→Idle、绑定成功）。
- 实测（`tests/tool_perf_probe.gd`，720p / 关 vsync / 墙钟 240 帧）：
  **1.662 ms/帧（p95 2.407）≈600 fps、111,028 primitives、32 draw call、112 objects**
  → 石墙平铺 90 件的 **120,668 tris 不是瓶颈**。
- **测量陷阱记录**：首次用 `Performance.TIME_PROCESS` 采样得到 240 帧全为 `84.077 ms`，
  是窗口被节流造成的假象；改用墙钟计时后才是真实分布。
- 来源说明：`animal_body.gd` 的动画代码**在接手收尾时已在工作区未提交**（非本人所写），
  本次做的是复核、补断言与提交。

---

## 2026-10-21 · ART03-④（鼠）换源：CC-BY mehrus rat → `SM_Mouse_002.glb`

**变更类型**：**关键角色视觉替换**（胶囊 → 带骨骼/动画的参考模型），玩法数值零改动。

- 弃用：`mouse_arribadaclub`（展平标本扫描件，无腿）；`mouse_charliecatling`（**Free Standard + NoAI**，
  与"资产入库 + AI 参与处理"冲突）。负责人 2026-10-21 决策：只找 CC0/CC-BY。
- 采用：`mouse_cc_mehrus_rat`（**CC Attribution**，作者 Mehrus，3,602 tris / **23 骨** / **4 段动画**）。
- 处理要点：unlit 材质重建 Principled；头朝 −Y → 绕 Z 180°（项目契约 Blender 面朝 +Y）；
  去尾体长 0.135 m 归一；原点=脚印中心+脚底；4 段动作塞 NLA 轨道导出 + 裁掉 Blender 3.3 多吐的 7 段常量动画。
- 接入：`mouse.tres` 加 `visual_scene`（胶囊 r=0.06 / half_height=0.09 **未改**）。
- 顺带更新两处过时断言（`run_art02_cat` 的"鼠仍是占位"、`run_t021_capture` 的 `body_mesh.visible`）。
- 视觉状态：`generated + 实机 2 图`，**未 approved**；鼠是 **rat 体态**不是家鼠。
  证据：`Docs/Tasks/ART03_MOUSE.md`、`Docs/Evidence/ART03_MOUSE.md`。

---

## 2026-10-21 · ART03-④ 鼠洞入口换成真实树桩（`stump_callum_arb`）

**变更类型**：**正式关卡资产替换**（灰盒洞口 → 参考基础模型 + 自建贯通孔）。

- 源：Sketchfab `stump_callum_arb`（**CC-BY**），39,122 tris（超预算 2.6 倍）、1 材质槽，
  世界 bbox 2.128 × 2.666 × 1.205 —— **含扫描自带的方形地面**，网格是 **528 个连通块**。
- **关键实测**：腔体是"碗"形、**没有任何贯穿洞**。早前"腔体净空 0.238×0.173 m"是按包围盒猜的，已作废。
- 处理：裁半径 0.55 m 外的面（39,122→24,239）→ 删小连通块（→23,160）→ 焊接后单轮减面（→13,999）
  → 归一高 0.85 m → **布尔破 0.24 × 0.30 贯通方孔**（→12,555）→ 清空材质槽。
- 接入：`_mk_root_hole_visual()`，**南北各一桩**贴住屏障两面（z=18.111 / z=19.889），
  资产里的孔与玩法孔首尾相接；**零碰撞**、不进导航组，通行仍由 `RootBarrier*` 的 BoxShape3D 决定。
- 为什么这么放：首版把桩心放在 z=19（屏障正中、屏障深 1.0 m）→ 整桩被灰盒吞掉、只剩顶部露出。
- 视觉状态：`generated + 4 机位实机图`，**未 approved**（负责人判读）。
  证据：`Docs/Tasks/ART03_ROOTHOLE.md`、`Docs/Evidence/ART03_ROOTHOLE.md`。

---

## 2026-10-21 · ART03-③ 围栏与庇护棚墙换成石墙模块（`wall_stefan_wr`）

**变更类型**：**正式关卡资产替换**（灰盒 → 参考基础模型）+ **一处关卡打光变更**（见最后一条）。

- 源：Sketchfab `wall_stefan_wr`（**CC-BY**，作者 Stefan），7 个模块件、2,000 tris 合计。
  取 `wall_stone` 件（1,244 tris，源尺寸 246.07 × 30.27 × 200.58，单位≈厘米）。
- 处理：÷100 → 墙面内等比缩放到**高 3.000 m**（厚保持天然 0.302739）→ 原点归一到脚印中心 + 脚底；
  材质从源里的 `Diffuse+Glossy+Add Shader` 旧式节点**重建为 Principled BSDF**（BaseColor + Normal + Roughness 0.85），
  否则导出的 GLB 完全没有贴图。
- 接入：`tool_make_courtyard.gd` 新增 `_mk_clad_wall()`，4 段边界围栏 + 庇护棚三面墙共 **90 个模块实例**；
  **碰撞盒尺寸/位置一字未改**（仍是 `BoxShape3D`）；新增深色 `Backing` 衬板遮住石块间的真实通孔；
  相邻模块重叠 ≥20% 并交替 180° 翻转。
- **打光变更（真缺陷修复）**：北墙内表面朝 −Z、与主光同向 → 整面近乎全黑，3 m 石墙读不出材质。
  新增一盏**不投影**的 `SkyFill`（朝下 +Z，能量 0.45）；主光方向与阴影方向不变。
- 为什么做：`modeling4.md` 要求逐个替换灰盒；围栏是**玩法边界**，视觉必须与碰撞一致（3.0 m 高）。
- 代价：墙类合计 **120,668 tris**（本关卡最大开销，未做帧率实测）。
- 视觉状态：`generated + 4 机位实机图`，**未 approved**（负责人判读）。证据：`Docs/Tasks/ART03_FENCE.md`、`Docs/Evidence/ART03_FENCE.md`。

---

## 2026-10-21 · ART03-② 溪边巨石换成真实岩石（`boulder_01`）

**变更类型**：**正式关卡资产替换**（灰盒 → 参考基础模型），玩法几何契约不变。

- 源：Poly Haven `boulder_01`（**CC0**，glTF 1K），实测 66,122 tris / **1.2721 × 1.8303 × 1.0038 m（米制）** / 1 材质槽 / 3×1K 贴图。
- 处理：焊接（`remove_doubles 1e-5`，67,042→33,063 顶点）→ 单轮 Collapse 减面到 **7,500 tris**（预算 1k–8k）→ 原点归一到脚底中心。
- 接入：`tool_make_courtyard.gd` 新增 `_mk_boulder()`，替换 `CreekBoulder` 的 1.2³ BoxMesh；**视觉来自 .glb，碰撞仍是 Godot 侧 `BoxShape3D`**（尺寸 = 视觉 AABB）；**不缩放**。
- 为什么换：`modeling4.md` 要求"先选对基础模型"；巨石是**非关键环境静物**，风险最低，先把"参考件 → 合规资产 → 接入 → 回归"闭环跑通，再碰围栏/洞口/鼠。
- 顺带修掉的真缺陷：① glTF 接缝拆点导致 Collapse 减面卡在 26,147（先焊接解决）；② T012 溪缝断言依赖导航 tie-break（改为经缝内航点逐腿查询）。
- 视觉状态：`generated + 4 机位实机图`，**未 approved**（负责人判读）。证据：`Docs/Tasks/ART03_BOULDER.md`、`Docs/Evidence/ART03_BOULDER.md`。

---

## 2026-10-21 · Reference Lock 第 1 轮（本轮）

**变更类型**：流程与参考库（**未改动任何正式游戏资产**）

- 新增强制流程 `reference_pending → reference_confirmed → modeling → review → approved`（见 `Docs/ART_ASSET_SPEC.md` §5）。
- 新增 `references/` 参考库：`ART_STYLE_GUIDE.md`、`reference_manifest.json`、
  `characters/{cat,mouse}/candidates/`、`environment/{root_hole,boulder,fence}/candidates/`。
- 新增 `Docs/ART_ASSET_SPEC.md`（逐资产规格 + 面数预算 + 五项评分 ≥85）、`Docs/ART_ASSET_AUDIT.md`（现状审计）、
  `Docs/THIRD_PARTY_ASSETS.md`（第三方登记 + 署名义务）。
- **风格基线定为"写实偏风格化"**（理由：硬核生存 + 近距动物对峙 + 现有关卡的自然材质方向；换卡通会造成风格断裂）。
  → **待负责人确认**；若改为卡通，`cat/candidates/cat_toon_omabuarts` 与 Kenney Nature Kit 会重新进入候选。
- **实际下载**：Poly Haven `boulder_01`（CC0）glTF 1K 五个文件，字节数与 API 一致；隔离存放于 `references/`。
- **未下载**：全部 Sketchfab 候选（需登录）；状态 `reference_pending`，附人工下载步骤。

**为什么**：`modeling3.md` 的重建（V009）证明"脚本化建模"无法达到专业动物形体；
`modeling4.md` 要求先选对基础模型、建立可验证参考标准，再谈建模。

---

## 2026-10-21 · ART02-V009 基础形体重建：**not-accepted**

- 方法变更：从"放样零件 + voxel remesh + decimate + 噪声位移"改为
  "一根骨架 + Skin 修改器 + 1 级细分 + bmesh 松弛 + 宽高斯解剖塑形"（**不再使用 remesh/decimate/噪声**）。
- 结果：5296 tris / 99.3% 四边形 / 0 非流形 / 4 毛发壳 / min_z=0；但**横向环状台阶、四肢关节不可辨、脚掌无趾部**。
- 决策：按 `modeling3.md` §6 **停止迭代**；**正式资产保持 V008**，V009 未接入 Godot。
- 证据：`Docs/Evidence/ART02_V009.md`；对比图 `Art/Staging/ART02_V009/ART02_V008_vs_V009_views.png`。

---

## 2026-10-21 · ART02 V008（猫）：`modeling`（在用，未 approved）

- 猫的视觉由 `CapsuleMesh` 换成真实模型：9568 tris / 2 材质槽 / 2048² 烘焙 albedo；配置驱动接入（`SpeciesConfig.visual_scene`）。
- 5 轮返工（v001→v008），视觉判读从"完全看不出是猫"提升到"轮廓可辨认为猫"；**未达正式美术水准**。
- 证据：`Docs/Tasks/ART02.md`、`Docs/Evidence/ART02.md`。

---

## 2026-10-21 · ART01（草丛掩体 `ENV_BUSH_001`）：`modeling`（在用，未 approved）

- 半透明绿盒子 → 2040 tris 真实草叶，双面、零碰撞；3 轮返工。
- 证据：`Docs/Tasks/ART01.md`、`Docs/Evidence/ART01.md`。

---

## 2026-10-21 · Reference Lock 第 1 轮（续）：实际下载 + 真实网格检查

**变更类型**：参考资产取得与测量（**仍未改动任何正式游戏资产**）

- 使用**负责人已登录的浏览器会话**的 API token 取得 Sketchfab 签名直链，实际下载并校验了 4 个候选：
  `cat_fripouille`（FBX + 4 张 PBR 贴图）、`mouse_arribadaclub`（glb）、`stump_callum_arb`（glb）、`wall_stefan_wr`（glb）。
  加上此前 Poly Haven `boulder_01`（CC0 glTF 1K），五类资产**每类都有一份可离线检查的文件**。
- 用 Blender 3.3.1 逐个导入读回真实网格（`references/reference_measurements.json`）：
  四个 Sketchfab 文件的 `faces` 与 API 完全一致；猫**带 33 骨但 0 动作**；鼠/桩/墙**无骨骼**；
  猫与墙的**尺度不是米**、需要归一化；洞口腔体实测 ≈0.238×0.173 m，**未达 0.24×0.30 m 要求**。
- 未取得：`mouse_charliecatling`（403/400）、`cat_bigcat_gbarzu`（未下）。已在 manifest/measurements 里如实记录。
- `references/_downloads/`（第三方原始下载，20+ MB）加入 `.gitignore`；来源 URL + 许可 + 大小/哈希前缀已登记在
  `Docs/THIRD_PARTY_ASSETS.md` §6。

**为什么**：`modeling4.md` §三要求"不要因为渲染图好看就直接选用，必须检查真实网格"；这一步把选型从"看截图"变成"看数据"。

---

## 2026-10-21 · 负责人决策：猫用 `cat_fripouille`，其余取已下载候选

- 五类资产在 `references/reference_manifest.json` 里全部置为 **`reference_confirmed`**，猫另进 **`modeling`**：
  猫 `cat_fripouille` / 鼠 `mouse_arribadaclub` / 洞口 `stump_callum_arb` / 围栏 `wall_stefan_wr` / 巨石 `boulder_01`（CC0）。
- 新增 `Tools/Blender/art04_cat_from_ref.py`：导入参考 FBX → 并 2 材质槽 → 按体长 0.58 m 归一 → 按眼睛质心转向 → 贴地 →
  导出 `Art/Exports/Cat/SM_Cat_002.glb`（8,376 tris / 2 槽 / 33 骨 / 高 0.307 m / min_z=0）。
- **未接入 Godot**：`cat.tres` 仍指 V008；等视觉确认后再切（`modeling4.md` §五 要求关键角色最终批准由负责人给）。
- **猫已接入游戏**（2026-10-21 后续）：`cat.tres` → `res://assets/characters/cat/sm_cat_002.glb`；
  **46/46 ART02 断言全过**；游戏内同机位实拍 `Art/Probes/art02_ingame_after_v2.png`（+ `_crop.png` 放大）
  —— 橙色虎斑 + 白腿的真猫，正面朝向玩家、四脚落地。
- **多模态已可用**：直接 `Read` PNG 即可看图（不再依赖 `vision.js`）；本次据此发现并修掉了**朝向反 180°**的问题
  （原旋转符号取反，X→-Y）与**渲染地面混进 GLB**（导出未排除 `RENDER_*`）。
- 仍需注意：`Art/Probes/art04_cat_ref_face.png` 是 85mm 近景，用于看面部结构。
