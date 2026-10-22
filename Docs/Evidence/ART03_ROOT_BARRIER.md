# Evidence：ART03-⑭ 树根屏障本体换成盘根模块（2026-10-21，本机系统时钟）

替换 `RootBarrierWest`（16.38 m）/ `RootBarrierEast`（9.38 m）两块 0 Recently-灰盒。
环境：Blender 3.3.1、Godot 4.7.2-stable console。

## 1. 新资产（`Tools/Blender/art11_root_barrier.py`，确定性 seed）

```
PROBE|start|blender=3.3.1|seed=20261023|module=3.00x0.50x0.80
PROBE|fit|scale=0.7536
PROBE|built|tris=640|verts=400|dims=(2.461, 0.296, 0.480)|min_z=0.0000
PROBE|glb|path=.../SM_RootBarrier_001.glb|bytes=36912|sha256=8d221b4b...
PROBE|done|tris=640|failures=0
```

构成：3 根沿 X 的主根（半径 0.07–0.115，带起伏）+ 4 根斜跨细根 + 3 根入地根须，
每根是 8 边 × 5 段的锥形管；**640 tris / 1 材质槽**（程序化树皮倍率贴图 + 棕色因子）。
正向构建出来是 3.27 × 0.64，脚本按模块上限做了**统一缩放 0.7536** → 2.461 × 0.296 × 0.480。

Godot 读回：`aabb_size=(2.461093, 0.480000, 0.295729)`、`aabb_pos.y = 0`、
`surface_count=1`、`MAT_Root_Bark roughness=0.880`。

## 2. 接入（碰撞盒不动）

```
TOOL|root_barrier_visual|RootBarrierWestRoots|asset=...sm_root_barrier_001.glb|size=(16.38, 0.50, 1.00)|tiles=7|spacing=2.340|k=1.042
TOOL|root_barrier_visual|RootBarrierEastRoots|asset=...|size=(9.38, 0.50, 1.00)|tiles=4|spacing=2.345|k=1.042
```

- 两段的 `Mesh` 隐藏，`Roots` 节点下平铺 7 / 4 个模块实例（交替 180° 翻转减轻重复感）；
- **碰撞盒与洞口的 0.24 × 0.30 净空一字未改**（`RootBarrierWest/East/Lintel` 三块 BoxShape3D 原样）。

## 3. 回归

**30 套 / 3,173 条 / 0 失败**（T010 鼠钻洞、T011 猫跳顶/鼠钻洞/猫被挡、T012 分层导航全部原样通过）。

## 4. 视觉自查与已知瑕疵

`Art/Probes/art07_barrier_wide.png`：原来两段棕色长盒子变成**横卧的盘根 + 斜根 + 入地根须**，
洞口处两根中空树桩仍在，读得出"树根屏障 + 鼠洞"。

瑕疵（未修，记录在此）：
- 单根是**规整的圆管**，近看像"管子/香肠"，缺少分叉、结节与树皮褶皱；
- 段与段之间靠 180° 翻转错开，接缝处仍能看出周期性；
- `RootBarrierLintel`（洞口上方 0.24 × 0.20 × 1.00）**仍是盒子** —— 但它在两根中空树桩内部，
  竖直方向被桩体遮住，实机图里看不到，所以本轮没动。

## 5. 未做

- 树根模块的分叉/结节细化（需要更贵的建模手法或在贴图上加位移）。
- 未由负责人视觉验收 → 不写 approved；未推送。
