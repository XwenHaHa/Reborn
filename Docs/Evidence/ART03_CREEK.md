# Evidence：ART03-⑥ 溪水/溪边视觉打磨（2026-10-21，本机系统时钟）

任务规格：`Docs/Tasks/ART03_CREEK.md`。环境：Godot 4.7.2-stable console。

## 1. 改前取证（先证明问题存在）

```
& '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
    --script 'res://tests/tool_capture_art01.gd' --quit-after 2400 -- art01-level
→ Art/Probes/art01_level_creek_cur.png
```

图上看得很清楚：整块**纯蓝平板** + 一小丛草 + 灰盒岸墙；材质 `StandardMaterial3D`，无任何时间项。

## 2. 代码改动

```
新增  Game/Reborn/shaders/creek_water.gdshader         程序化水面（滚动 noise + 域扭曲 + 菲涅尔 + 岸边泡沫）
新增  Game/Reborn/tests/tool_capture_creek.gd          溪边取证（材质类型/芦苇数/两帧像素差）
改动  Game/Reborn/tests/tool_make_courtyard.gd
      · WATER_SIZE.z 20 → 9（溪带）
      · _add_creek_structures() 用 ShaderMaterial（shader 缺失自动退回旧纯色 + 打印 FALLBACK）
      · 新增 const WATER_SHADER / REED_SPOTS 与 _add_creek_dressing()
产出  scenes/maps/l_courtyard.tscn（生成器产物）+ resources/nav/*.tres（重烤）
```

生成器输出：

```
TOOL|CreekWater|material=shader|res://shaders/creek_water.gdshader
TOOL|CreekReeds|count=13|asset=res://assets/environment/sm_bush_001.glb|via=_add_creek_dressing
TOOL|save_result=0 (OK)|path=res://scenes/maps/l_courtyard.tscn
```

## 3. 实机取证（`tool_capture_creek.gd -- creek`）

```
CREEK|water|node=CreekWater|mesh=BoxMesh|material=ShaderMaterial(shader=res://shaders/creek_water.gdshader)|group_water_bodies=true
CREEK|reeds|count=15
CREEK|wetband|CreekWetBankSouth=true / North=true / West=true / East=true
CREEK|motion|creek_wide|frames_apart=45|mean_abs_diff=0.02142|changed_px_ratio=0.3144|water_region_lum_a=0.4641|water_region_lum_b=0.4661
CREEK|motion|creek_low|frames_apart=45|mean_abs_diff=0.03073|changed_px_ratio=0.4279|water_region_lum_a=0.4895|water_region_lum_b=0.4825
```

图片：`Art/Probes/creek_wide_a.png`、`Art/Probes/creek_low_a.png`（另有 `_b` 为 0.75 s 后的第二帧）。

**视觉自查（直接 Read PNG）**：
- `creek_low_a.png`：水面有涟漪纹理与太阳高光斑，两岸芦苇成排，溪心还有一丛；
  比改前（纯蓝平板 + 一小丛草）明显像"溪"。
- 仍可见**低频规律感**（噪声明暗块），比首版（sin-hash 造成的硬方块）好很多但没彻底消除。

## 4. 踩到并修掉的坑

1. **第一版 shader 出现硬方块色带**：根因是 `hash12` 用 `sin(dot(p, ...))*43758`，而 `p = 世界坐标 × ripple_scale`
   可达上百，sin 精度退化 → 规则网格块。修法：换整数型 hash + 加域扭曲 + `ripple_scale` 3.4 → 14。
2. **一度把 shader 的三行误改进了 `tool_make_courtyard.gd`**（同一次编辑里给错了文件路径），
   立刻按上下文修回（`REGIONS` 的 Grass 行、`CAT_SPAWN` 行），并用 `--check-only` + 全量回归确认没留伤。
   教训：跨文件改同一批行号时，**先 Read 目标文件再定行号**。

## 5. 回归

**全量 30 套 / 3,173 条断言 / 0 失败 / 每套 EXIT=0 / `SCRIPT ERROR` 0**。

关键不变量未被破坏：`CreekWater` 仍是 `MeshInstance3D + BoxMesh`、`water_depth=0.03`、
`water_bodies` 组仍为 1、零碰撞（`creek_water_has_no_collision` PASS）；新增节点全是 `MeshInstance3D`。

## 6. 未做 / 未验证

- 草丛网格本身没重做、也没加风摆动（草丛"假"的根因是 ART01 那颗**平面叶片**资产）。
- 水面仍有低频规律感；溪的形状仍是矩形。
- 未由负责人视觉验收 → 不写 approved；未推送、未发布。
