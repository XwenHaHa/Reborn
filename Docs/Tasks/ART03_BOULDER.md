# ART03-②：溪边巨石换成参考基础模型（`boulder_01`）

**状态**：done（灰盒替换完成，视觉待负责人判读）——**不是**正式美术 approved。
**编号说明**：ART03 是**美术流水线任务**（Reference Lock 之后的"逐个替换灰盒"），不属于 T001～T063；
不改变 P0～P6 顺序，**没有**越过 **P6 正式角色/骨骼资产阶段门**（巨石是环境静物）。

## 1. 目标与验收

| 项 | 内容 |
|---|---|
| 目标 | 把 T011 灰盒里 `CreekBoulder`（1.2 m `BoxMesh`）换成真实岩石资产，且**不改玩法几何契约** |
| 源 | `references/environment/boulder/candidates/boulder_01_polyhaven_gltf_1k/boulder_01.gltf`（Poly Haven，CC0） |
| 验收层 | A 资产层（面数预算/材质槽/尺度/贴地）· B 关卡层（生成器接入、碰撞盒匹配视觉、无玩法回归）· C 运行层（实机关卡截图） |
| 回归 | 全量 29 套断言套件全绿 |

## 2. 路径与产物（全部新增，仅改生成器与其产物）

```
Tools/Blender/art05_boulder_001.py                  处理脚本（导入源 → 焊接 → 减面 → 归一 → 渲染 → 导出）
Art/Exports/Environment/SM_Boulder_001.glb          交付产物（3,048,844 B，sha256 dc9a00e4…）
Game/Reborn/assets/environment/sm_boulder_001.glb   Godot 侧（与上者逐字节相同）+ 3 张 1K jpg + .import
Game/Reborn/tests/tool_capture_art05.gd             实机关卡捕获工具（4 机位 + 节点事实打印）
Art/Probes/art05_boulder_{q34,side,front}.png       Blender 侧三视图
Art/Probes/art05_level_boulder_{wide,front,corner,close}.png   Godot 实机关卡四机位
```

改动：
- `Game/Reborn/tests/tool_make_courtyard.gd`：新增 `BOULDER_ASSET` / `BOULDER_SIZE` / `_mk_boulder()`，
  并把 `_add_creek_structures()` 里原来的 `_mk_box("CreekBoulder", 1.2³)` 换成 `_mk_boulder(...)`；`_verify()` 新增 7 条断言。
- `Game/Reborn/scenes/maps/l_courtyard.tscn`（生成器产物）+ `resources/nav/l_courtyard_{cat,mouse}.tres`（**几何变了必须重烤**）。
- `Game/Reborn/tests/run_t012_navigation.gd`：溪缝断言改为经缝内航点逐腿查询（原因见 §6）。

## 3. 数据/接口契约（不要随手改）

| 契约 | 值 | 谁在依赖 |
|---|---|---|
| 资产尺度 | 1.268556 × 1.004233 × 1.829183 m（**源码就是米制，未缩放**） | `BOULDER_SIZE`；`_verify` 的碰撞盒断言 |
| 资产原点 | 脚底中心（`AABB.position.y = 0`） | 生成器把实例下沉 `−BOULDER_SIZE.y/2` |
| 朝向 | 生成器 `yaw = 0`（**不转**） | `_box()` 用 body 的 position/size 推 AABB、**不读旋转**；给 body 加 yaw 会让测试读到的包围盒小于真实碰撞 |
| 面数 | 7,500（预算 1k–8k） | `Docs/ART_ASSET_SPEC.md` §2 |
| 材质槽 | 1（`boulder_01`，metallic 0，粗糙度来自 ARM 贴图） | 环境静物预算 ≤2 槽 |
| 碰撞 | **.glb 不带碰撞**；Godot 侧 `BoxShape3D` 尺寸 = 视觉 AABB | `Docs/ART_ASSET_SPEC.md` §3；T011 的 `_box()` 只认 `Shape` 子节点 + `BoxShape3D` |
| 分组 | **不进** `nav_source_courtyard` | 视觉实例不是碰撞体，烘焙只读 StaticBody3D 的 shape |

## 4. 关键工序（可复现）

1. 导入 glTF → 合并网格 → **按距离焊接**（`remove_doubles 1e-5`，67,042 → 33,063 顶点）。
2. 迭代 Collapse 减面（每轮 `ratio = 7500/当前`，最多 8 轮，实测 1 轮即达标）。
3. 原点归一到"脚底中心"，自检 `tris ≤ 8000`、槽 ≤2、`min.z = 0`、X/Y 居中、三轴不超限。
4. Cycles 渲三视图 → 删渲染辅助物（`RENDER_*`/灯/相机）→ 导出 GLB（`use_selection`、不含灯相机）。
5. 复制进工程 → `--headless --import` → `tool_dump_scene_tree.gd` **读回**真实结构 → 再改生成器。

## 5. 失败恢复

| 症状 | 处置 |
|---|---|
| 减面停在 ~26,147 tris 不再下降 | glTF 会沿 UV/法线接缝拆点，Collapse 无法跨断缝合并。**先焊接再减面**（本次即此事） |
| 贴地/居中假失败 | `obj.bound_box` 是缓存，改顶点后不可信 → 用顶点重算 bbox |
| 重跑生成器后导航面消失 | **必须**紧接着跑 `tests/tool_make_courtyard_nav.gd` |
| 视觉整块浮起 | glb 原点在脚底；实例必须 `y = −BOULDER_SIZE.y/2` |
| 需要回退 | `git checkout -- Game/Reborn/scenes/maps/l_courtyard.tscn Game/Reborn/resources/nav/*.tres` 即回到 1.2 m 盒子 |

## 6. 实测踩到的两个真缺陷（已修，见 Evidence）

1. **减面停滞**：焊接前 66,122 → 26,615 → 26,147 就停；焊接后 1 轮降到 7,500。
2. **T012 溪缝断言假失败**：换巨石后导航面重烤，单段 A→B 查询从"穿缝 12.00 m"翻到"绕岸墙 B 东端 ≈12.1 m"。
   实测证明**缝本身仍可穿**（缝内航点 `(−31.73, 10)` 与南北两侧逐腿都连通），
   原断言依赖全局 tie-break → 改为经缝内航点逐腿查询，能力语义不变、结果稳定。

## 7. 边界（不算完成的事）

- 巨石视觉**未**由负责人判定为正式基线；`approved` 只能由负责人置位。
- 碰撞用**外包盒**近似：岩石有凹陷，盒内会挡到"空气"（0.2 m 量级）。要更贴合需换 `ConvexPolygonShape3D` 或多盒，属后续优化。
- 关卡其余部分（地面/围栏/树根屏障/庇护棚/补给点）仍是灰盒。
- 未推送、未发布。
