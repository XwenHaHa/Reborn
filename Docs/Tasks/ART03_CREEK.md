# ART03-⑥：溪水与溪边的视觉打磨（水真的会动）

**状态**：done（改动已接入并在实机取证）——**不是**正式美术 approved。
**触发**：负责人看图后直接指出「这个草丛和溪边很假啊，水都不带动的」。

## 1. 问题到底是什么（先看再改）

用 `tool_capture_art01.gd -- art01-level` 的既有溪边机位拍了一张，确认三件事：

| 现象 | 实测原因 |
|---|---|
| 水**完全不动** | `CreekWater` 的材质是 `StandardMaterial3D`：纯色 + `roughness 0.15` + alpha 0.6，**没有任何时间项** |
| 溪像"池塘" | `WATER_SIZE = 22 × 20 m`，占满整个 Creek 区域（x −36..−10、z 2..30） |
| 岸边假 | 水面是硬边矩形直接切到草地；芦苇只有**一小丛**（ART01 补的 `CreekReedCoverMesh`） |

## 2. 改了什么

| 项 | 改法 | 为什么这么改 |
|---|---|---|
| 水面材质 | 新增 `Game/Reborn/shaders/creek_water.gdshader`：三层 value-noise **随时间滚动** + 域扭曲 + 有限差分求法线 + 菲涅尔 + 岸边泡沫 | 无贴图依赖；运动必须来自 `TIME`，否则永远"像一块蓝漆" |
| noise hash | 用**整数型 hash**（`fract(vec3(p.xyx)*0.1031)` 那套），不用 `sin(dot(...))*43758` | 世界坐标×频率后可达上百，sin-hash 精度退化会冒出**方块状色带**（第一版实机就是这样） |
| 水面尺寸 | `WATER_SIZE.z: 20 → 9`（22 × 9 的溪带，仍覆盖 `WaterPoint_Creek` 的 z=16） | 从"池塘"收成"溪"；T011 只断言**深度 0.03 / 顶面 0.13 / BoxMesh / group**，不查 X/Z 尺寸（已核） |
| 岸边过渡 | 四条**湿泥带**（`CreekWetBank{N/S/W/E}`，`_mk_surface_marker`，无碰撞）straddle 水边 | 把"蓝面硬切草地"变成"草 → 湿泥 → 水" |
| 芦苇 | `REED_SPOTS` 13 处沿两岸 + 溪心一处，yaw/scale 打散（`CreekReed*` 实例） | 原来是"一小丛草立在蓝漆里"，读不出"溪边" |

**硬约束（未破）**：水面节点仍是 `MeshInstance3D + BoxMesh`、`water_depth=0.03` meta、
`water_bodies` 组仍只有 1 个、零碰撞；新增的芦苇/湿泥全是 `MeshInstance3D`（零碰撞、不进导航组）。

## 3. 客观取证：水**确实在动**

新增 `tests/tool_capture_creek.gd`：同机位采两帧（相隔 45 帧 ≈ 0.75 s），直接算像素差。

```
CREEK|water|node=CreekWater|mesh=BoxMesh|material=ShaderMaterial(shader=res://shaders/creek_water.gdshader)|group_water_bodies=true
CREEK|reeds|count=15
CREEK|motion|creek_wide|frames_apart=45|mean_abs_diff=0.02142|changed_px_ratio=0.3144
CREEK|motion|creek_low|frames_apart=45|mean_abs_diff=0.03073|changed_px_ratio=0.4279
```

31%–43% 的采样像素在 0.75 s 内发生变化 ⇒ 不是静态材质。

## 4. 回归

**全量 30 套 / 3,173 条 / 0 失败**（含 T011 的 210 条溪水/洞口/围栏几何断言；水面尺寸变化未触发任何失败）。

## 5. 边界（没解决 / 没做的）

- **草丛本身还是"假"**：ART01 的 `sm_bush_001.glb` 是**平面细长叶片**（双面、2040 tris），近距离看是"绿纸条"。
  这是**资产本身的表现力上限**，本轮没重做草丛网格，也没加风摆动（风摆需要给 2 个材质槽分别做 shader，
  或加 AnimationPlayer 轨道，属独立任务）。
- 水面近距离仍能看出**低频规律感**（域扭曲压住了大部分，但没有彻底消除）。
- 溪的**形状**仍是矩形（没有弯曲河道）；要真做弯曲得改水面网格 + 岸线几何，属关卡设计改动。
- 未由负责人视觉验收 → 不写 approved。未推送。
