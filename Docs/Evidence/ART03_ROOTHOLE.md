# Evidence：ART03-④ 鼠洞树桩接入（2026-10-21，本机系统时钟）

任务规格：`Docs/Tasks/ART03_ROOTHOLE.md`。环境：Blender 3.3.1、Godot 4.7.2-stable console。

## 1. 源件实测（只读）

```
PROBE|meshes=1 objects=3
PROBE|src|tris=39122|min=(-0.981, -0.932, -0.651)|max=(1.147, 1.734, 0.554)|dims=(2.128, 2.666, 1.205)
PROBE|mesh|Object_2|tris=39122|slots=1
PROBE|ray|z+0.10|  0:7.46  45:7.70 ... 315:7.23      # 从 8 m 外朝中心打的射线都在 0.3~0.8 m 处命中
```

射线诊断的结论：**中心是实心的、没有贯通空腔**；把 bbox 当净空（早前写的 0.238 × 0.173）是错的。
取景正确的 4 视图（`Art/Probes/art07_stump_ref_{q34,front,side,top}.png`）确认：
**空心中空树干 + 扫描自带方形地面**，腔体是"碗"，顶部被劈开。

## 2. 处理脚本与产物

```
& 'D:\SoftWare\Blender\blender.exe' --background --factory-startup `
    --python 'E:\Reborn\Tools\Blender\art07_root_hole_from_ref.py' -- --stage all        # EXIT=0
```

```
PROBE|axis|xy=(0.1216, 0.1128, 0.0000)|top_radius=0.379
PROBE|crop|removed_faces=14883|left_tris=24239
PROBE|shells|count=528|main_verts=1036|dropped_verts=1846|left_tris=23160
PROBE|weld|verts 15562->12120
PROBE|decimate|pass=1|ratio=0.6045|23160->13999
PROBE|normalize|scale=0.73578|dims=(0.8232, 0.8220, 0.8500)|min=(-0.4116, -0.4110, 0.0000)
PROBE|bore|w=0.240|h=0.300|len=1.20|tris=12555|slots=1
PROBE|clearance|points=9|blocked=0
PROBE|glb|path=E:/Reborn/Art/Exports/Environment/SM_RootHole_001.glb|bytes=3102320|sha256=d983a1e186bb2fb19f7bf5958d08913bc03d986e87eb8130f1ab29fc2ff62be5
PROBE|done|tris=12555|failures=0
```

GLB 结构（自写 JSON chunk 解析器）：1 节点 / 1 网格 / 1 材质（baseColor + normal，`metallic=0`）/ 2 张内嵌贴图。

## 3. Godot 导入读回

```
DUMP|node|class=Node3D|name=sm_root_hole_001
  DUMP|node|class=MeshInstance3D|name=ENV_ROOT_HOLE_001
  DUMP|mesh|class=ArrayMesh|surface_count=1|aabb_pos=(-0.411622, 0.000000, -0.389539)|aabb_size=(0.823243, 0.850000, 0.778105)|verts=8550|tris=12555
  DUMP|surface|index=0|material=res_name=poly_0|roughness=1.000|metallic=0.000
```

## 4. 关卡接入

```
--check-only tool_make_courtyard.gd      EXIT=0
tool_make_courtyard.gd                   EXIT=0
tool_make_courtyard_nav.gd（必跑）        EXIT=0
```

```
TOOL|root_hole_visual|RootHoleStumpS|asset=…sm_root_hole_001.glb|pos=(26.50, 0.10, 18.11)|size=(0.823, 0.850, 0.778)
TOOL|root_hole_visual|RootHoleStumpN|asset=…sm_root_hole_001.glb|pos=(26.50, 0.10, 19.89)|size=(0.823, 0.850, 0.778)
VERIFY|root_hole_stump_s_exists|OK            VERIFY|root_hole_stump_n_exists|OK
VERIFY|root_hole_stump_s_is_asset|OK          VERIFY|root_hole_stump_n_is_asset|OK
VERIFY|root_hole_stump_s_no_collision|OK      VERIFY|root_hole_stump_n_no_collision|OK
VERIFY|root_hole_stump_s_not_in_nav_group|OK  VERIFY|root_hole_stump_n_not_in_nav_group|OK
VERIFY|root_hole_stump_s_on_ground|OK         VERIFY|root_hole_stump_n_on_ground|OK
VERIFY|root_hole_stump_s_axis_x|OK            VERIFY|root_hole_stump_n_axis_x|OK
VERIFY|root_hole_stump_s_abuts_barrier|OK     VERIFY|root_hole_stump_n_abuts_barrier|OK
VERIFY|root_hole_stump_s_unrotated|OK         VERIFY|root_hole_stump_n_unrotated|OK
```

原有洞口几何断言（0.24 / 0.30 / 屏障顶 +0.50 / 跨区 / 鼠过猫不过）**全部照旧 OK** —— 碰撞一字未改。

## 5. 实机捕获

```
& '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
    --script 'res://tests/tool_capture_art07.gd' --quit-after 2400 -- art07-level
```

```
CAP|art07|stump|RootHoleStumpS|pos=(26.5, 0.1, 18.11095)|rot_deg=(0,0,0)|scale=(1,1,1)|aabb_size=(0.823243, 0.85, 0.778105)|shapes=0
CAP|art07|stump|RootHoleStumpN|pos=(26.5, 0.1, 19.88905)|rot_deg=(0,0,0)|scale=(1,1,1)|aabb_size=(0.823243, 0.85, 0.778105)|shapes=0
CAP|art07|barrier|RootBarrierWest|box=(16.38, 0.5, 1.0)|pos=(18.19, 0.35, 19.0)
CAP|art07|barrier|RootBarrierEast|box=(9.38, 0.5, 1.0)|pos=(31.31, 0.35, 19.0)
CAP|art07|barrier|RootBarrierLintel|box=(0.24, 0.2, 1.0)|pos=(26.5, 0.5, 19.0)
四张图 save_result=0 (OK)
```

**视觉自查**（直接 Read PNG）：
- `art07_roothole_mouth_south.png`：底部 0.24 × 0.30 方孔**确实贯通**，能看到对面亮部。
- `art07_hole_approach.png`：站在洞口正前方，树桩贴着屏障、孔里能看进去 → 读法是"从树桩底部钻过去"。
- `art07_hole_approach.png`（**第一版**）：桩子被 1.0 m 深的灰盒屏障吞掉，只露出顶部 —— 见 §6。

## 6. 两个真缺陷（本次发现并修掉）

1. **整桩被灰盒吃掉**：首版桩心放在 `z = 19`（屏障正中，屏障深 1.0 m、桩深 0.778 m），
   实机图里只剩 0.35 m 桩顶露在灰盒上，读起来像"树桩长在墙里面"。
   **修法**：桩子内端面贴住屏障面（南 `z = 18.11095`、北 `z = 19.88905`），并改成**南北各一桩**，
   资产里的贯通孔与玩法孔首尾相接，两侧都能读出"从洞里钻出来"。
2. **布尔留下空材质槽**：`slots=2` 时切割面落到没有材质的槽上（渲染成纯白）。
   修法：`material_index = 0` + 清多余槽（`slots=1`）。

## 7. 回归

**全量 29 套 / 3,127 条断言 / 0 失败 / 每套 EXIT=0 / `SCRIPT ERROR` 0**（T011 210、T012 79、T026 96 等均含在内）。

## 8. 未验证 / 未做

- 未由负责人视觉验收；**不写 approved**。整道树根屏障（`RootBarrierWest/East/Lintel`）**仍是灰盒**。
- 桩子外壳零碰撞（靠屏障挡）；桩底有布尔切面，未做贴图修饰。
- 未推送、未发布。
