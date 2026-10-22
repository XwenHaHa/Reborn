# Evidence：ART03-⑬ 土墩 / 棚顶换真资产（2026-10-21，本机系统时钟）

任务：`Docs/Tasks/ART03_GREYBOX_B.md` §5 里列的两项（`GrassMoundA/B`、`ShelterRoof`）。
环境：Blender 3.3.1、Godot 4.7.2-stable console。

## 1. 新资产（`Tools/Blender/art10_props_002.py`，确定性 seed）

```
PROBE|mound|tris=198|dims=(2.0015, 1.9853, 0.5175)
PROBE|glb|ENV_MOUND_001|tris=198|bytes=5976|sha256=823c798ff9de91f2
PROBE|roof|tris=228|dims=(3.4376, 3.7713, 0.1519)
PROBE|glb|ENV_ROOF_001|tris=228|bytes=7472|sha256=13639c433b223993
PROBE|done|failures=0
```

- 土丘：径向环 + 低频噪声起伏，最后一圈落到 z=0 贴合地面；**198 tris**。
- 棚顶：9 条木板（沿 X 铺、沿 Z 排，带缝隙与高度抖动）+ 2 根托梁；**228 tris**。

Godot 读回：`mound aabb_size=(2.001494, 0.517505, 1.985267)`、
`roof aabb_size=(3.437582, 0.151886, 3.771297)`，两者 `aabb_pos.y = 0`（原点在底面）。

## 2. 接入（碰撞盒不动）

```
TOOL|prop_visual|GrassMoundAVisual|asset=res://assets/environment/sm_mound_001.glb|scale=(1.0, 1.0, 1.0)|pos=(0.0, -0.25, 0.0)|shader=res://shaders/ground.gdshader
TOOL|prop_visual|GrassMoundBVisual|asset=...|scale=(1.06, 1.0, 0.94)|pos=(0.0, -0.25, 0.0)|shader=res://shaders/ground.gdshader
TOOL|prop_visual|ShelterRoofVisual|asset=res://assets/environment/sm_roof_001.glb|scale=(0.989067, 1.0, 0.954579)|pos=(0.0, -0.1, 0.0)
```

- 土墩：`_mk_box` 的 2.0×0.50×2.0 碰撞盒保留，`Mesh` 隐藏 → 换成圆丘实例，并**复用 `ground.gdshader`**
  （世界坐标斑块），所以土丘和地面是同一套草/土斑块，不会出现"一个绿盒子"。
- 棚顶：3.4×0.2×3.8 碰撞盒保留，`Mesh` 隐藏 → 换成木板条实例（按 3.4/3.4376、3.8/3.7713 微缩到盒内）。

## 3. 回归

**30 套 / 3,173 条 / 0 失败**（T011 的 `grass_mound_*_height_0.50`、`shelter_roof_clearance` 等全部原样通过）。

## 4. 视觉自查

`Art/Probes/art06_shelter.png`：棚顶已是**木板条 + 托梁**（有缝隙与高差），墙面石砌，地面有草/土斑块。

**发现但未修的问题**：庇护棚三面石墙（1.6 m 高，k=0.533）在近距离能看出**石块被压扁 + 深色衬板裸露**，
观感偏"碎"。根因是同一块 3 m 模块被缩到 1.6 m/1.0 m 用；要修得给矮墙单独做一个模块（新资产）。

## 5. 未做

- `RootBarrierWest/East/Lintel`（26 m × 0.5 m 木根屏障本体）仍是灰盒 —— 需要木根资产。
- 庇护棚矮墙的"碎"感（见 §4）。
- 未由负责人视觉验收 → 不写 approved；未推送。
