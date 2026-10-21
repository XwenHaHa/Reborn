# Evidence：ART03-② 溪边巨石接入（2026-10-21，本机系统时钟）

任务规格：`Docs/Tasks/ART03_BOULDER.md`。环境：Blender 3.3.1（`D:\SoftWare\Blender\blender.exe`）、
Godot 4.7.2-stable console（`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`）。

## 1. 源件事实（**只读**，未改动 `references/`）

| 项 | 实测值 | 来源 |
|---|---|---|
| 文件 | `references/environment/boulder/candidates/boulder_01_polyhaven_gltf_1k/boulder_01.gltf` | Poly Haven，CC0 |
| 三角形 | 66,122 | Blender 导入后 `loop_triangles` 计数 |
| 尺度 | 1.2721 × 1.8303 × 1.0038 m | 同上（顶点重算 bbox） |
| 材质槽 | 1 | 同上 |
| 贴图 | 3 × 1024²（diffuse / normal / arm） | GLB JSON chunk 解析 |

> 第 1 轮曾据 API 元数据写"12.7 m，需要缩到 1.2 m"。**该结论已被实测推翻**：源就是米制 1.27 m，**本任务不缩放**。

## 2. 处理脚本与产物

命令（EXIT=0）：

```
& 'D:\SoftWare\Blender\blender.exe' --background --factory-startup `
    --python 'E:\Reborn\Tools\Blender\art05_boulder_001.py' -- --stage all
```

关键 PROBE 行（原样）：

```
PROBE|weld|verts 67042->33063
PROBE|src|obj=ENV_BOULDER_001|tris=66122|dims=(1.2721, 1.8303, 1.0038)|slots=1
PROBE|decimate|pass=1|ratio=0.1134|66122->7500
PROBE|final|tris=7500|dims=(1.2686, 1.8292, 1.0042)|min=(-0.6343, -0.9146, 0.0000)|max=(0.6343, 0.9146, 1.0042)|slots=1
PROBE|glb|path=E:/Reborn/Art/Exports/Environment/SM_Boulder_001.glb|bytes=3048844|sha256=dc9a00e4632141db76011011e0ded05b59f97b645825654462d2eadd5bf5288c
PROBE|done|tris=7500|failures=0
```

- 交付：`Art/Exports/Environment/SM_Boulder_001.glb`，3,048,844 B，sha256 `dc9a00e4…288c`。
- Godot 侧副本 sha256 **完全相同**（两次 `Get-FileHash`：均为 `dc9a00e4632141db76011011e0ded05b59f97b645825654462d2eadd5bf5288c`）。
- GLB 结构（自写 JSON chunk 解析器）：1 节点 `ENV_BOULDER_001` / 1 网格 / 1 材质（`metallic=0`，粗糙度走 ARM 贴图）/
  3 张 jpeg 1K / 7,500 tris、5,365 verts。

## 3. Godot 导入读回（**不猜结构**）

```
& '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' --import
    → "[ 0% ] reimport | sm_boulder_001.glb"，EXIT=0

& '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
    --script 'res://tests/tool_dump_scene_tree.gd' -- 'res://assets/environment/sm_boulder_001.glb'
```

```
DUMP|node|class=Node3D|name=sm_boulder_001|pos=(0,0,0)|rot_deg=(0,0,0)|scale=(1,1,1)
  DUMP|node|class=MeshInstance3D|name=ENV_BOULDER_001|pos=(0,0,0)
  DUMP|mesh|class=ArrayMesh|surface_count=1|aabb_pos=(-0.634278, 0.000000, -0.914591)|aabb_size=(1.268556, 1.004233, 1.829183)|verts=5365|tris=7500
  DUMP|surface|index=0|material=class=StandardMaterial3D|res_name=boulder_01|roughness=1.000|metallic=0.000
```

→ Blender `min.z = 0` 在 Godot 变成 `aabb_pos.y = 0`（原点在脚底）；`Blender +Y（1.8292）` 对应 `Godot Z`。

## 4. 关卡接入（改生成器，不手改 .tscn）

```
& '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' --check-only --script 'res://tests/tool_make_courtyard.gd'   # EXIT=0
& '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_make_courtyard.gd' --quit-after 20000   # EXIT=0
& '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_make_courtyard_nav.gd' --quit-after 40000   # EXIT=0（必跑）
```

生成器输出 + 新增断言（原样）：

```
TOOL|creek_boulder|CreekBoulder|asset=res://assets/environment/sm_boulder_001.glb|size=(1.269, 1.004, 1.829)|pos=(-14.00, 0.10, 8.00)|yaw=0.0
VERIFY|creek_boulder_box_ok|OK
VERIFY|creek_boulder_collision_matches_asset|OK
VERIFY|creek_boulder_rests_on_ground|OK
VERIFY|creek_boulder_visual_exists|OK
VERIFY|creek_boulder_visual_is_asset|OK
VERIFY|creek_boulder_visual_sunk|OK
VERIFY|creek_boulder_visual_no_collision|OK
```

导航 `.tres` 两个都变了（**这是应该变的**：巨石从 1.2³ 变成 1.269 × 1.004 × 1.829，几何确实变了）。
`git diff --numstat` 每个 nav `.tres` 只有 2 行（顶点数组 + 多边形数组整体重写）。

## 5. 实机关卡捕获（`tool_capture_art05.gd`，**非 headless**）

```
& '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' --script 'res://tests/tool_capture_art05.gd' --quit-after 2400 -- art05-level
```

节点事实（原样）：

```
CAP|art05|boulder|body=CreekBoulder|class=StaticBody3D|pos=(-14.0, 0.602117, 8.0)|rot_deg=(0.0, 0.0, 0.0)|visual_scene=res://assets/environment/sm_boulder_001.glb|visual_pos=(0.0, -0.502117, 0.0)
CAP|art05|boulder_visual|mesh=ArrayMesh|aabb_size=(1.268556, 1.004233, 1.829183)|surfaces=1
CAP|art05|boulder_collision|BoxShape3D|size=(1.268556, 1.004233, 1.829183)|shape_count=1
```

四张图 `save_result=0 (OK)`：`Art/Probes/art05_level_boulder_{wide,front,corner,close}.png`。

**视觉自查**（直接 Read PNG 判读，本机 `vision.js` 服务 502/503 不可用，故不声称用过它）：
- `art05_level_boulder_front.png`：岩石是真实多面体剪影、有接触阴影、坐落在溪水面（水面 0.13 > 底面 0.10，3 cm 浸水）；
  颜色暖棕带白，**不是**大理石式高光（符合 `ART_STYLE_GUIDE.md` "禁止大理石式高光"）。
- `art05_level_boulder_wide.png`：与两侧草丛、涂地区块的相对尺度正常；没有浮空、没有陷地。

## 6. 回归

| 套件 | 结果 |
|---|---|
| T011 灰盒 | 210 条 / 0 失败 / EXIT=0（含 `P5_mouse_crosses_creek_gap` 猫不能过、鼠能过，实测 z=5.547） |
| T012 导航 | 79 条 / 0 失败 / EXIT=0（改法见 §7） |
| T026 掩护 | 96 条 / 0 失败 |
| ART01 草丛 | 83 条 / 0 失败 |
| **全量 29 套** | **3,127 条断言 / 0 失败 / 每套 EXIT=0 / `SCRIPT ERROR` 计数 0** |

全量逐套计数：ART01 83、ART02 46、T002 18、T005 50、T006 65、T007 22、T008 114、T009 81、T010 95、
T011 210、T012 79、T013 159、T013-移动回归 73、T014 106、T015 93、T016 118、T017 128、T018 73、
T019 72、T020 164、T021 279、T022 168、T023 178、T024 136、T025 175、T026 96、T027 96、T029 39、T030 111。

## 7. 真实缺陷与修法（本次发现）

### 7.1 减面停滞在 26,147 tris（已修）

- 现象：单次 Collapse `ratio=0.1134` 后 66,122 → 26,615，再迭代也只到 26,147，不再下降。
- 成因：glTF 导入沿 **UV/法线接缝把顶点拆开**，网格在每条缝上拓扑断开，Collapse 无法跨缝合并。
- 修法：减面前 `bmesh.ops.remove_doubles(dist=1e-5)`（loop 级 UV 保留），67,042 → 33,063 顶点。
- 结果：1 轮即 66,122 → 7,500。

### 7.2 T012 `mouse_creek_gap_path_crosses_gap` 假失败（已修，附证明）

- 现象：换巨石后该断言 `false|FAIL`，`SUMMARY|checks=79|failures=1`。
- 用**基线对照**确认是本次改动引起：把 4 个被改文件 `git stash` 后在 HEAD 状态跑同一套件 → `mouse_creek_gap|points=16|length=12.00|crosses_gap=true|PASS`。
- 临时探针（已删除，未提交）实测路径点：换后单段 A→B 查询走 **x=−31.21**（岸墙 B 东侧，`|x+31.73|=0.52 > 0.14`），
  长度 ≈12.1 m；换前走 **x=−31.73**、长度 12.00 m。**两条路线近乎等长**，导航面重烤后 A* 翻了边。
- **能力仍然完好**（探针原样）：
  ```
  PROBE|leg_north|points=10|last=(-31.7300, 0.1400, 10.0016)
  PROBE|leg_south|points=8|first=(-31.7300, 0.1400, 10.0016)
  PROBE|closest_to_gap_center=(-31.7300, 0.1400, 10.0000)
  ```
  即缝内航点 `(−31.73, 10)` 与南北两侧都连通。
- 修法：`run_t012_navigation.gd` 新增 `_query_via(a, m, b, layer)`，溪缝断言改为**经缝内航点逐腿查询**，
  断言语义（鼠能穿 0.24 m 缝）不变，但不再依赖全局 tie-break。修后 `length=12.00|crosses_gap=true|17 点|PASS`。
- 另：T011 的**真实胶囊行走** `P5_mouse_crosses_creek_gap` 仍实测从北向南穿过缝隙（终点 z=5.547），
  与"缝可穿"互为独立证据。

## 8. 未验证 / 未做

- 未由负责人做视觉验收；巨石状态 = **generated + 4 机位实机图**，不写 approved。
- 碰撞外包盒对凹陷处会挡"空气"（未做 ConvexPolygonShape3D 精修）。
- 未推送、未发布。
