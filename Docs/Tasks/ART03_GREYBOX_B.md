# ART03-⑫：再换三处灰盒（地面 / 碎屑 / 溪岸墙）

**状态**：done（已接入关卡，实机图已自查）——**不是**正式美术 approved。
**触发**：负责人选 B「换掉剩下的灰盒」。

## 1. 这一轮换了哪三处（其余仍列在 §5）

| 灰盒 | 原来 | 现在 | 碰撞 |
|---|---|---|---|
| `Ground`（80×80） | 纯色 `Color(0.32,0.34,0.36)` 平面 —— 场景最大的一块"假" | **程序化 `ground.gdshader`**：低频 fbm 做**草/土/干草**三色斑块 + 高频细粒 | 不动（T011 断言 top=0.10 / 80×80 照旧） |
| `CourtyardDebris1..3`（×3） | 0.6×0.3×0.6 纯色盒子 | **缩小版 `sm_boulder_001` 真石头**（scale 0.40/0.46/0.52，绕 Y 随机转角） | 不动（仍是 0.6×0.3×0.6 BoxShape3D） |
| `CreekBankWallA/B`（2×8 m） | 0.30×1.00×8.00 纯色盒子 | **与围栏同一套石墙模块**平铺（`_mk_clad_wall`，k=0.333 → 每道 9 块） | 不动（0.30 × 1.00 × 8.00，溪缝 0.24 不变） |

**复用而不是新建资产**：碎屑和大石头共用 `sm_boulder_001.glb`；岸墙和围栏共用 `sm_fence_module_001.glb`。
新东西只有一张 `shaders/ground.gdshader`。

## 2. 为什么这么做（而不是各做新资产）

- 地面是**最大面积**的视觉，但**不需要新几何**——一个程序化材质就能把"灰色水泥地"变成草地/土斑，成本几乎为零；
- 碎屑本质就是小石头，已有 CC0 巨石资产，缩放复用比新做一个碎石资产更省、风格也更统一；
- 岸墙和围栏本来就该是同一种砌体（同一条溪的护岸与庭院围墙），复用模块顺带统一了材质语言。

## 3. 契约与断言

- `Ground` / `CourtyardDebris*` / `CreekBankWall*` 的**碰撞盒尺寸与位置一个字没改**，
  所以 T011 的 `ground_top_is_0.10`、`ground_is_80_wide/deep`、`courtyard_debris*_exists`、
  `creek_gap_w_0.24`、`creek_wall_h_1.00`、`mouse_fits_creek_gap`、`cat_blocked_by_creek_gap_width`
  全部原样通过；
- 新增节点（`Rock`、`Backing`、`Tiles`）都是纯视觉，零碰撞、不进 `nav_source_courtyard`；
- shader 缺失时 `_apply_material_override` 打印 `FALLBACK_PLAIN` 并保留原纯色 → 生成器仍可在缺文件机器上跑通。

## 4. 验证

- 生成器输出：
  `TOOL|material|ground|shader=res://shaders/ground.gdshader`、
  `TOOL|debris_rock|CourtyardDebris{1,2,3}|scale=0.40/0.46/0.52`、
  `TOOL|wall_visual|CreekBankWall{A,B}|tiles=9|spacing=0.889|k=0.333`；
- 全量回归：**30 套 / 3,173 条 / 0 失败**；
- 实机图 `Art/Probes/creek_wide_a.png`：地面出现草/土斑块，岸墙是石砌，溪岸芦苇与湿泥过渡可见。

## 5. 还没换的灰盒（下一批候选）

| 项 | 现状 | 备注 |
|---|---|---|
| `RootBarrierWest/East/Lintel` | 0.50 m 高的三块盒子（26 m 长） | 洞口树桩只是**入口装饰**；整道屏障要木根资产，属新资产任务 |
| `ShelterRoof` | 0.2 厚薄板 | 缺"木板/茅草"资产 |
| `GrassMoundA/B` | 2×0.5×2 绿色盒子 | 缺"土丘"资产（可考虑用 ground shader + 低模圆丘） |
| `CreekWater` 的岸线 | 已是石墙 + 锯齿泥舌 | 溪道走向仍是直的 |
| 食物/水源交互物 | BoxMesh + 纯色 | 玩法道具，需与 T017 一起设计 |

## 6. 边界

- 岸墙平铺用的是 3 m 模块缩到 1 m 高（k=0.333），石块被压扁；远看没问题，近看石缝偏密。
- 地面是纯 shader、没有法线/细节贴图，近看仍是程序化的。
- 未 approved、未推送。
