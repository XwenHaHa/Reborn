# ART_STYLE_GUIDE —— 《轮生 Reborn》美术风格与生产规则

版本 1.0（2026-10-21）｜强制文件｜配套 `Docs/ART_ASSET_SPEC.md`、`references/reference_manifest.json`

## 1. 风格基线（默认，待负责人确认）

**写实偏风格化（stylized-realistic）**，理由：
- 游戏是硬核生存、第一人称/近第三人称、动物对峙；卡通比例会削弱"捕食者/猎物"的压迫感；
- 现有关卡是灰盒 + 自然材质方向（草、土、树根、溪岸），写实环境支撑叙事；
- 已在使用的两件资产（草丛、猫 V008）都走写实配色路线，换成卡通会造成风格断裂。

**三条硬约束**：
1. **不用纯基元冒充成品**：Box/Sphere/Cylinder 拼接只能出现在灰盒阶段，必须有 `灰盒/占位` 标注。
2. **不用"塑料感"材质**：任何资产必须给出 albedo + roughness 变化（贴图或顶点色），单一纯色视为未完成。
3. **形体优先**：形体未通过评审前不得进入材质打磨；不得用贴图/打光掩盖几何缺陷。

## 2. 尺度与比例

| 类别 | 基准 |
|---|---|
| 世界 | 1 单位 = 1 米；猫咪视觉高 ≈0.39 m（≤0.48 胶囊）、鼠 ≈0.12 m（≤0.18 胶囊） |
| 角色比例 | 以真实家猫/家鼠解剖为参考：短毛猫 肩高:体长 ≈ 1 : 1.6；鼠 头身比更圆、耳/眼相对更大 |
| 环境 | 围栏高 2.4 m、厚 0.3 m；掩体 3×3×3 m 数据体量；洞口净空 ≥0.24×0.30 m |

## 3. 材质与贴图规范

| 项 | 规范 |
|---|---|
| 材质槽 | 动物 ≤2、环境模块 ≤2（超过需在 SPEC 里写明例外理由） |
| 贴图 | albedo ≤2048²；法线/粗糙度同尺寸或更小；**打包进 GLB**，不散落外部依赖 |
| 颜色空间 | glTF baseColor 是线性值；Godot `albedo_color` 是 sRGB 编码 → 断言要比对编码后的值 |
| 粗糙度 | 毛皮 0.6–0.85；石头 0.7–0.95；木头 0.6–0.9；湿润处可降 0.2–0.3 |
| 双面 | 只有"玩家会站进去"的植被/草叶允许 `CULL_DISABLED`，其它一律单面 |
| 禁止 | 程序化噪声位移冒充毛发；用 emission/自发光遮瑕；大理石式高光 |

## 4. 拓扑与 LOD

- 静态环境：四边形优先，允许三角；**单一壳体**（除刻意分离的部件，如眼睛/耳内）。
- 角色：以可绑定为前提（环状边线在肩/肘/髋/膝/口部）；**面部、四肢、脚掌、尾巴必须有独立结构**。
- LOD：≥5000 面的资产需提供 LOD0/LOD1（可用 Blender `Decimate`，但 LOD0 不得是 decimate 产物）。
- 法线：统一朝外，无翻转；`Shade Smooth` + 硬边按需。

## 5. 命名与目录

```
Art/Blender/<Category>/<ASSET_ID>_v00N.blend      # 源（每轮新版本）
Art/Exports/<Category>/SM_<Name>.glb | SK_<Name>.glb
Game/Reborn/assets/<category>/<name>.glb          # 与导出逐字节相同
references/<kind>/<asset_id>/candidates/          # 参考（**不进 Game/**）
```

- `SM_` = 静态网格；`SK_` = 含骨骼。
- 资产 ID：`CAT_BODY_001` / `MOUSE_BODY_001` / `ENV_ROOT_HOLE_001` / `ENV_BOULDER_001` / `ENV_FENCE_MODULE_001` / `ENV_BUSH_001`。

## 6. 生产流程（Reference Lock）

```
reference_pending → reference_confirmed → modeling → review → approved
```

- **reference_confirmed 的门槛**：许可允许商用+修改+随游戏分发；真实网格已打开检查（拓扑/UV/尺度/朝向）；manifest 有 sha256。
- **review 必须附**：正/侧/背/45° 截图、面部/关键结构近景、线框、`vision.js` 判读原文、与参考同角度对比、Godot 断言结果。
- **approved 只能由负责人确认**；agent 只能提交 review 结论。
- 每轮返工：先写缺陷清单 → 再改 → 再出图；**同一失败最多两次有依据的修复尝试**。

## 7. 评分（`modeling4.md` §六）

| 维度 | 分值 |
|---|---|
| 轮廓与比例 | 30 |
| 结构与细节 | 25 |
| 材质与风格 | 20 |
| Godot 集成 | 15 |
| 性能与资源规范 | 10 |

门槛：**≥85 分**，且授权、关键结构、Godot 集成三项必过。

## 8. 参考资产使用规则

- `references/**` 内的模型/贴图**只作参考**，默认 `reference_only`，**不得**直接进入 `Game/Reborn/`。
- 若要把参考资产转为正式资产，必须：① 许可允许（商用+修改+分发）；② 在 `Docs/THIRD_PARTY_ASSETS.md` 登记署名义务；
  ③ 通过 `Docs/ART_ASSET_SPEC.md` 的全部规格与断言；④ 负责人确认。
- 已批准参考为**只读**：不得覆盖、不得"顺手修一下"，变更走 `Docs/ART_ASSET_CHANGELOG.md`。
