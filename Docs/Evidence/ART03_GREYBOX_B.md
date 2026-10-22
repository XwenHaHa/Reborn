# Evidence：ART03-⑫ 地面 / 碎屑 / 溪岸墙（2026-10-21，本机系统时钟）

任务规格：`Docs/Tasks/ART03_GREYBOX_B.md`。环境：Godot 4.7.2-stable console。

## 1. 改动

```
新增  Game/Reborn/shaders/ground.gdshader          地面程序化材质（fbm 草/土/干草 + 高频细粒）
改动  Game/Reborn/tests/tool_make_courtyard.gd
      · Ground：_mk_box 后 _apply_material_override(ground, GROUND_SHADER)
      · CourtyardDebris1..3：_mk_box → _mk_rock_debris（碰撞盒不变，视觉换成 sm_boulder_001）
      · CreekBankWallA/B：_mk_box → _mk_clad_wall（同一套石墙模块，k=0.333）
      · 新增助手 _apply_material_override / _mk_rock_debris 与常量 GROUND_SHADER
产出  scenes/maps/l_courtyard.tscn（+ 重烤 nav，无 diff）
```

## 2. 生成器输出（原样）

```
TOOL|material|ground|shader=res://shaders/ground.gdshader
TOOL|debris_rock|CourtyardDebris1|asset=res://assets/environment/sm_boulder_001.glb|scale=0.40
TOOL|debris_rock|CourtyardDebris2|asset=res://assets/environment/sm_boulder_001.glb|scale=0.46
TOOL|debris_rock|CourtyardDebris3|asset=res://assets/environment/sm_boulder_001.glb|scale=0.52
TOOL|wall_visual|CreekBankWallA|asset=res://assets/environment/sm_fence_module_001.glb|size=(0.300, 1.000, 8.000)|tiles=9|spacing=0.889|k=0.333
TOOL|wall_visual|CreekBankWallB|asset=...|tiles=9|spacing=0.889|k=0.333
TOOL|save_result=0 (OK)|path=res://scenes/maps/l_courtyard.tscn
```

## 3. 实机取证

```
& '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
    --script 'res://tests/tool_capture_creek.gd' --quit-after 3000 -- creek
CREEK|water|material=ShaderMaterial(res://shaders/creek_water.gdshader)|group_water_bodies=true
CREEK|motion|creek_wide|mean_abs_diff=0.02392|changed_px_ratio=0.3127
```

图 `Art/Probes/creek_wide_a.png`：地面不再是纯色灰，出现草/土/干草斑块；溪岸是**石砌岸墙**；
岸边芦苇、湿泥舌与水面相接。**视觉自查（直接 Read PNG）通过**。

## 4. 回归

**30 套 / 3,173 条 / 0 失败**（T011 的溪缝 0.24 / 岸墙高 1.00 / 地面顶面 0.10 / 碎屑存在性全部原样通过）。

## 5. 未做

- `RootBarrierWest/East/Lintel`（26 m × 0.5 m 的木根屏障本体）、`ShelterRoof`、`GrassMoundA/B` 仍是灰盒。
- 岸墙用 3 m 模块缩到 1 m 高（k=0.333），石块被压扁、近看石缝偏密。
- 地面是纯 shader，无法线/细节贴图。
- 未由负责人视觉验收 → 不写 approved；未推送。
