# ART09-E 任务规格：展板切片关（溪谷）与第三人称构图

状态：done / 环境材质 **FAIL（未达展板级）**
上位计划：`Docs/Tasks/ART09_BOARD_PARITY.md` §3 阶段 E

## 目标

按路径 C 做「构图 + 光照 + 后处理接近展板，材质承认不达标」：
在**独立展示关**里复现展板第三人称实玩区的构图（猫在下三分之一、视线进溪谷、逆光、景深、空气透视），
并且**不碰 `l_courtyard`**（T011–T027 的几何/碰撞/导航都在那张关上）。

## 改动路径

- 新增生成器 `Game/Reborn/tests/tool_make_ravine_board.gd` → 新增 `Game/Reborn/scenes/maps/l_ravine_board.tscn`
- 新增取证工具 `Game/Reborn/tests/tool_capture_art09_board.gd`
- 新增资产锚点探针 `Game/Reborn/tests/tool_probe_aabb.gd`
- 新增契约 `Game/Reborn/tests/run_art09_frame_contract.gd`（40 条）
- 截图 `Art/Probes/art09_board_after/`（5 帧）
- `Docs/Evidence/ART09_E_RAVINE.md`

## 场景内容（全部程序化放置，固定常量）

1. 地面 46×0.2×50（`ground.gdshader`，`patch_scale` 0.34 / `grain_strength` 0.18，近景才看得见斑块）
   + 溪床碎石层 16×0.02×5。
2. 溪流 `CreekWater`：**`PlaneMesh`（薄片）** 16×4.6 @ (2.4, 0.12, −2.6)，`creek_water.gdshader`；
   进 `water_bodies` 组、**零碰撞**。
3. `WetShore` 湿泥带 + 4 条泥舌（水陆交界的硬线用它们打散）。
4. 5 块巨石（前中后三档）+ 10 团草丛（近溪 5 / 中景 5）+ 4 块脚边小石 + 3 团脚边草。
5. 树根洞口（中景焦点）+ 6 段盘根屏障平铺。
6. 远景框景：3 段矮石墙（左）+ 2 段围栏（右）+ 庇护棚（4 立柱 + 棚顶 + 土墩）。
7. 光照：暖色低角度主光（`BoardSun`，−24°/32°、能量 1.45、开阴影）+ 冷色天光补光（`BoardSkyFill` 0.38、不投影）。
8. 后处理：CC0 森林 HDRI 天空球 + 天光环境光 + SSAO(1.1/2.4) + ACES(曝光 1.05) +
   深度雾(9→46 m, sky_affect 0.10) + 轻辉光(0.30)。
9. `BoardSubjectAnchor`(0, 0.10, 2.4)：第三人称取证时把主体放在这里。

## 第三人称机位（`tool_capture_art09_board.gd`）

相机 = 主体 + (0.45, 0.58, 1.35)，看向 主体 + (0.02, 0.14, −2.60)，FOV 58，`CameraAttributesPractical` 远景景深
（`dof_blur_far_enabled`，实测本版本支持）。另外 4 个环境机位（宽景/溪流特写/洞口/远景框景）同为固定常量。

## 硬约束

- **零碰撞、零导航区、零玩法**：`run_art09_frame_contract.gd` 断言场景里 `StaticBody3D` / `CollisionShape3D` /
  `NavigationRegion3D` 计数全为 0，`main.tscn` 不引用本关（正式流程不变）。
- 摆件高度一律 `GROUND_TOP`：`tool_probe_aabb.gd` 实测所有 glb 原点在脚底（min_y = 0），**不要猜中心偏移**
  （首轮猜 +0.40/+1.50 把石墙和围栏吊到了半空，见证据 §4）。
- 展示关的水面用 `PlaneMesh`：`BoxMesh` 的侧壁在近景会被看穿成"水池挡板"。

## 验收

- `run_art09_frame_contract.gd` 40/40；`run_t011_greybox` 229/229（庭院未受影响）。
- 非 headless 5 帧 `save_result=OK` + `CAP|ravine|done`。
- 视觉按区域写 PASS/FAIL：构图/光照/后处理 PASS；水面、地面细节、装饰材质 FAIL。

## 回退

删除 `tool_make_ravine_board.gd`、`tool_capture_art09_board.gd`、`tool_probe_aabb.gd`、
`run_art09_frame_contract.gd`、`scenes/maps/l_ravine_board.tscn` 与 `Art/Probes/art09_board_after/` 即可；
`l_courtyard`、`tool_make_courtyard.gd` 未被本阶段改动。
