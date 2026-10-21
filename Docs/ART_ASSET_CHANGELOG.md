# ART_ASSET_CHANGELOG —— 资产与风格变更记录

规则：任何**外形/风格/参考来源**层面的变更都要记一条，写清"为什么"。
单纯修 bug（法线、非流形、命名）记在对应 `Docs/Evidence/Txxx.md`，这里只记资产决策。

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
