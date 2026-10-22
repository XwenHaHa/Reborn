# Evidence：ART03-⑧ 草丛重做（2026-10-21，本机系统时钟）

任务规格：`Docs/Tasks/ART03_GRASS.md`。环境：Blender 3.3.1、Godot 4.7.2-stable console。

## 1. 旧资产问题确认

从实机图 `Art/Probes/art01_level_west_a_near.png`（改前版本）可见：叶片是**单层平面片**，
近看是"绿纸条"；泥土垫直径 2.87 m，像棕色大饼。

## 2. 生成脚本与产物

```
& 'D:\SoftWare\Blender\blender.exe' --background --factory-startup `
    --python 'E:\Reborn\Tools\Blender\art09_grass_002.py' -- --stage all        # EXIT=0
```

最终一次运行（原样）：

```
PROBE|built|blades=210|tris=2600|verts=2569|dims=(2.7648, 2.9521, 0.8155)|min_z=0.0000
PROBE|glb|path=E:/Reborn/Art/Exports/Environment/SM_Bush_002.glb|bytes=99988|sha256=04401552eb48c7c05841b174982afa530f4f2df8d5b03c66ab3e7fb9f1c6c1bb
PROBE|done|tris=2600|failures=0
```

迭代中修掉的两个自身缺陷：
1. **泥土垫中间是洞**：`build_soil` 只有 2 圈顶点、没有盘心点 → 从上往下透出灰背景。补中心顶点并扇接。
2. **泥土垫比例错**：第一版按包络半径 1.4 m 做，成了直径 2.8 m 的大饼。收到 **0.62 m**。
3. 顺带把叶片从 20–34 mm 加宽到 **30–55 mm**、数量 170 → **210**，并把外圈半径推到 1.26 m
   让包络回到 2.76 × 2.95（覆盖 3×3 掩体体量）。

## 3. Godot 读回

```
DUMP|node|name=sm_bush_002
  DUMP|node|class=MeshInstance3D|name=ENV_BUSH_002
  DUMP|mesh|surface_count=2|aabb_pos=(-1.323380, 0.000000, -1.501926)|aabb_size=(2.764810, 0.815492, 2.952138)|verts=2569|tris=2600
  DUMP|surface|index=0|material=MAT_Bush_Leaf|albedo=(0.3227, 0.4845, 0.3035, 1.0)|roughness=0.850|cull=2
  DUMP|surface|index=1|material=MAT_Bush_Soil|albedo=(0.2601, 0.2151, 0.1718, 1.0)|roughness=0.850|cull=2
```

材质名/线性色/双面/粗糙度与 ART01 契约**完全一致**（`cull_mode=2` = CULL_DISABLED）。

## 4. 断言同步与结果

`run_art01_bush.gd` 改成新资产 + 新 AABB/面数后：

```
ASSET|root_class=Node3D|root_name=sm_bush_002|children=1
ASSET|aabb_pos=(-1.4014, 0.0, -1.4014)|aabb_size=(2.8028, 0.815492, 2.8028)   ← 该次为中间版本
ASSERT|CoverBushWestA_visual_is_asset|sm_bush_002.glb|PASS
ASSERT|CoverBushWestB_visual_is_asset|PASS
ASSERT|CoverBushNorthC_visual_is_asset|PASS
ASSERT|CreekReedCover_visual_is_asset|PASS
SUMMARY|checks=83|failures=0
RESULT|PASS
```

生成器：

```
TOOL|cover_visual|CoverBushWestAMesh|asset=res://assets/environment/sm_bush_002.glb
TOOL|cover_visual|CoverBushWestBMesh|... yaw=63.0|scale=0.94
TOOL|cover_visual|CoverBushNorthCMesh|... yaw=141.0|scale=1.06
TOOL|cover_visual|CreekReedCoverMesh|... yaw=212.0|scale=1.00
TOOL|CreekReeds|count=13|asset=res://assets/environment/sm_bush_002.glb
VERIFY|CoverBush|CoverBushWestA|mesh_size=(2.765, 0.815, 2.952)
VERIFY|CoverBush|CoverBushWestB|mesh_size=(2.765, 0.815, 2.952)
VERIFY|CoverBush|CoverBushNorthC|mesh_size=(2.765, 0.815, 2.952)
```

## 5. 回归

**全量 30 套 / 3,173 条 / 0 失败 / 每套 EXIT=0 / `SCRIPT ERROR` 0**（含 ART01 83 条、T011 210 条、
T026 掩护 96 条）。

## 6. 未做 / 未验证

- 资产仍是**纯色 + 折面**（无贴图）；近看仍有"程序化草"观感。
- 未做逐叶细分，叶尖 3 段有轻微硬折。
- 未由负责人视觉验收 → 不写 approved；未推送、未发布。

## 7. 贴图（ART03-⑨）

见 `Docs/Tasks/ART03_GRASS.md` §7。核验要点：

```
mat[0] MAT_Bush_Leaf baseColorFactor=[0.085, 0.200, 0.075, 1] baseColorTex=True roughness=0.85
mat[1] MAT_Bush_Soil baseColorFactor=[0.055, 0.038, 0.025, 1] baseColorTex=True roughness=0.85
image[0] T_Grass_Leaf 10,063 B / image[1] T_Grass_Soil 13,662 B（均 image/png，内嵌）
```

Godot 抽取：`sm_bush_002_T_Grass_Leaf.png` 10,063 B、`sm_bush_002_T_Grass_Soil.png` 13,662 B（+`.import`）。
`run_art01_bush` 83/83；全量 30 套 3,173 条 0 失败。
