# ART02 证据：猫 CAT_BODY_001 深度重做

任务规格：`Docs/Tasks/ART02.md`。本文只记**跑过什么、读到什么、判读说了什么**。
时间基准：本机系统时钟 2026-10-21。

## 1. 诊断（修改前）

### 1.1 资产清点（`git ls-files` + 场景读回）

| 类别 | 现状 | 问题定性 |
|---|---|---|
| 猫 / 鼠 | `AnimalBody/BodyMesh` = **一个 `CapsuleMesh`**（`radius=0.16 / height=0.48`，材质 `albedo_color=(0.68,0.62,0.55)`、`roughness=0.85`） | **没有模型**。属"基础几何体冒充生物"，`modeling2.md` §一 的第 1、2、3、4 条全中 |
| 草丛掩体 | ART01 真实草叶资产（2040 tris / 2 槽 / 双面） | 有模型，但判读指出"面片感/塑料感/形态高度重复"（见 1.3） |
| 关卡其余 | BoxMesh 灰盒（地面/围栏/树根/庇护棚/补给点） | 灰盒，非本次范围 |

### 1.2 同机位游戏内判读（`vision.js`，1.58 m，鼠玩家第一人称）

- 输入：`Art/Probes/art02_ingame_before.png`（由 `tests/tool_capture_art02.gd` 用真实生态入口拍）
- 判读原话（节选）：「光滑的椭球形（或胶囊形/蛋形）」「**完全看不出是猫**」
  「像一颗浅色的蛋、一块肥皂、一粒胶囊」「逻辑与视觉完全脱节…对第一人称视角的沉浸感破坏极大」

### 1.3 唯一既有资产的判读（对照用）

- 输入：`Art/Probes/art01_preview_corner45_v4.png`
- 结论：「极不自然…草叶像毫无厚度的二维十字面片」「像绿色塑料刷毛」。**但**它不影响"这是什么生物"的识别，
  所以按 `modeling2.md` §一 的优先级，先解决"动物没有模型"。

## 2. 方案与可复现链路

```
& 'D:\SoftWare\Blender\blender.exe' --background --factory-startup `
    --python 'E:\Reborn\Tools\Blender\art02_cat_001.py' -- --version v008 --stage all
```

`--stage mesh`（只建模+自检）/ `shot`（+渲染，不烘焙/不导出）/ `all`（+UV+烘焙+渲染+导出）。

自检（不过就退出码 1、不写 `.glb`）：三角形 ≤10000、材质槽 ≤2、`min_z≈0`、`max_z≤0.48`、
`|x|≤0.18`、X 轴对称 ±5 mm、毛发槽**单一连通壳**、非流形边 = 0。

## 3. 五轮返工（每轮：判读缺陷 → 具体改法 → 复验）

| 轮 | 视觉判读提出的缺陷（原话节选） | 具体改法 | 复验 |
|---|---|---|---|
| **v001** | 「更像猪或豚鼠」「耳朵是圆柱体/截断圆锥」「面部结构完全缺失」「像融化的蜡」「存在几何体强行融合的球状凸起」 | 首次全量重建：放样躯干/颈/头/四肢/尾 + remesh 焊接 | 自检 0 失败；判读仍判"不是猫" |
| **v002** | 「耳朵像两片薄三角刀片直插头顶」「躯干呈圆筒状」「腿像鹿腿」「后肢 Z 字折叠像骨折」「眼睛是灰玻璃弹珠」「拼接生硬」 | 耳高 0.128→0.108、耳根盘；胸腔加深、腰收窄；后肢跗关节收回 8 mm；前脚趾（3 小椭球）；眼窝垫 + 眉弓；**眼/鼻/耳内改为 remesh 之后才贴**；软化 3 处硬阈值配色 | 首轮出现"眼窝 + 琥珀虹膜"；判读改口"能认出是猫科，但像狗/兔子" |
| **v003** | 「瞳孔/虹膜没有瞳孔」「鼻子像金属扣子」「耳朵太厚太长」「颈部"分段"」「背上有两条硬转折」 | 瞳色 ramp 扩到 0.0055；鼻头改双件（鼻垫+鼻中隔）；上眼睑棱；胡须垫；**取消 superellipse**（背脊硬棱的来源）；remesh 0.0045 + smooth 4 | 自检 0 失败；判读"第一眼能认出是猫" |
| **v004/v005** | 「躯干像由几个圆润几何块拼成」「大腿根像单独两个球贴在骨盆上」「菱形折痕」「尾巴像直管插着」 | 体型收窄（髋 0.060/0.062、胸 0.062/0.080、腰 0.042/0.047）；大腿肌群内收 + 收小；尾根直径 0.018→0.0135、锥度加强；**抽面后追加轻修 ×2** 消除长条三角；贴图升到 2048² | 判读"四个模型完整进画、第一眼是猫"；仍指出拼接/塑料感 |
| **v006/v007/v008** | 「耳朵像兔耳」、「头太小」、「四肢像牙签」 | 头整体加宽加高约 8%（`HEAD_STATIONS`）、耳高 0.404→0.378 且基部 0.026→0.038、耳尖更外张、四肢末端半径 +15% | 自检 0 失败；游戏内判读"勉强能认出是猫（四足 + 耳 + 尾轮廓）" |

每轮中间产物：`Art/Blender/Cat/CAT_BODY_001_v00N.blend`（**不覆盖**上一轮）+ `Art/Probes/art02_v00N_*.png`。
为控制仓库体积，只保留 v001(全 7 张)/v005(全 8 张)/v008(全 8 张) 与每轮的 sheet/face；
其余可用脚本命令重出：`--version v00N --stage shot`。

## 4. 最终资产数据（v008，PROBE 实测）

```
built|verts=4798|tris=9568|slots=2|aabb_min=(-0.092334, -0.270270, 0.000400)|aabb_max=(0.092570, 0.330812, 0.389809)|islands=7|non_manifold=0
built|height=0.3894|length=0.6011|width=0.1849
bake|diffuse=OK|size=2048x2048
glb|path=E:/Reborn/Art/Exports/Cat/SM_Cat_001.glb|bytes=1744408|sha256=b5ae013ba8965f193bd5d9ccde07af33f6661a34f1c05f2667cad4441eab5a5e
```

`islands=7` = 毛发壳 1（断言 `fur_islands=1`）+ 眼 2 + 鼻 2 + 耳内 2（都是刻意独立的贴面件）。

Godot 侧读回（`tests/tool_dump_scene_tree.gd`）：

```
Node3D "sm_cat_001"
└── MeshInstance3D "CAT_BODY_001"  surface_count=2  aabb_pos=(-0.092334, 0.000400, -0.330812)
    aabb_size=(0.184903, 0.389409, 0.601082)  verts=6956  tris=9568
surface 0 = MAT_Cat_Fur (roughness 0.78, albedo_texture 已挂)
surface 1 = MAT_Cat_Detail (roughness 0.32, albedo_texture 已挂)
skin = NONE
```

## 5. Godot 接入与验收

### 5.1 代码改动（**只有接入所必需的三处**）

| 文件 | 改动 |
|---|---|
| `scripts/data/species_config.gd` | 新增 `@export var visual_scene: PackedScene`（留空 = 继续用胶囊；**不写物种名分支**） |
| `scripts/characters/animal_body.gd` | `_rebuild_visual()` / `_sync_visual()` / `VISUAL_MIN_SQUASH`；`apply_config()` 调用一次；蹲/站切换与捕获时同步；`mark_captured()` 隐藏视觉 |
| `resources/species/cat.tres` | `visual_scene = ExtResource("3_vis") → res://assets/characters/cat/sm_cat_001.glb` |

**胶囊契约完全没变**：`BodyMesh` 仍是 `CapsuleMesh(0.16/0.48)`，只是 `visible=false`；
T009/T013 的 `mesh == capsule` 断言照旧成立（`run_art02_cat.gd` B 层专门守这两条）。

### 5.2 自动用例

| 套件 | 结果 |
|---|---|
| `run_art02_cat.gd`（新增） | **46/46 PASS**（A 资产 23 / B 接线 19 / C 运行 4） |
| `run_t008_species.gd` | 114/114 PASS |
| `run_t009_cat_movement.gd` | 81/81 PASS |
| `run_t010_mouse_movement.gd` | 95/95 PASS |
| `run_t013_debug_entry.gd` | 159/159 PASS |
| `run_t013_movement_regression.gd` | 73/73 PASS |
| `run_t026_cover.gd` | 96/96 PASS |
| `run_t027_ecology.gd` | 96/96 PASS |
| `run_t021_capture.gd` | 279/279 PASS |
| `run_art01_bush.gd` | 83/83 PASS |

合计 **1122 条断言全绿**（10 套），退出码全 0。

命令（逐条 `--headless --path Game/Reborn --script res://tests/<name> --quit-after N`）：

```
run_art02_cat.gd 30000 | run_t008_species.gd 20000 | run_t009_cat_movement.gd 300000
run_t010_mouse_movement.gd 300000 | run_t013_debug_entry.gd 300000
run_t013_movement_regression.gd 300000 | run_t026_cover.gd 300000
run_t027_ecology.gd 300000 | run_art01_bush.gd 20000
```

### 5.3 游戏内同机位对比（**不是渲染图**，是真实游戏相机）

`tests/tool_capture_art02.gd`（真实生态入口 + 鼠玩家第一人称 + 猫固定在正前方 1.58 m；
同一帧先退回胶囊占位拍 before，再装回模型拍 after）：

| | 判读（`vision.js`） |
|---|---|
| `art02_ingame_before.png` | 「光滑的椭球形/蛋形」「**完全看不出是猫**」「像肥皂、一粒胶囊」 |
| `art02_ingame_after.png`（v008） | 「**勉强能认出是猫**：四条腿、翘起的尾巴、尖耳朵轮廓都在」「不是胶囊/圆柱这类基本几何体」；**仍**指出「耳朵偏长偏圆像兔耳」「头偏小、颈身细长」「表面像哑光塑料」 |

另外用既有预设 `tool_capture_render.gd -- t028` 复拍同一机位（`art02_before_t028_*` / `art02_after_t028_*`），
判读：before「胶囊体，像掉在地上的药丸」→ after「低多边形猫，四足/尾巴/尖耳轮廓清晰」。

**结论（可观察的提升）**：从"完全不像任何动物"到"轮廓可辨认为猫"；材质从单色塑料到有斑纹/腹部浅色/眼鼻细节。
**没有**达到"专业动物模型"水准。

## 6. 多角度/线框/合影（每轮）

`Art/Probes/art02_v008_{front,side,back,corner45,top,face,sheet,wire}.png`
（Blender Cycles CPU，48 samples，720²；sheet 1600×620 四向并排；wire 用 Wireframe 修改器渲染）。

## 7. 仍未解决的问题与下一步建议

1. **形体上限**：程序化"放样 + voxel remesh + 抽面"能解决"没有模型/有明显拼接"，但解决不了
   "肌肉走向、骨骼标志点、毛发的层次"。四轮独立判读都指向同一组缺陷（耳比例、四肢像棍、颈胸过渡、表面塑料感）。
   → 下一步建议（**需要负责人授权/预算**）：
   - **方案 A（推荐）**：引入一份**有版权的专业猫基础模型**（sculpt 基底，最好带现成 UV），
     本脚本的"接入/烘焙/验收/回归"链路可直接复用；
   - **方案 B**：请美术在 Blender 里手工雕刻 + 拓扑（本仓库已能自动导链、断言、出图，美术只需交付基底）；
   - **方案 C**：继续程序化，但改用**雕刻式位移贴图 + 多层毛发壳**（面数与渲染成本都会显著上升，
     且仍需专业基础形体，否则只是把"塑料"变成"毛塑料"）。
2. ~~**没有骨骼/动画**~~ → **已部分解决（见 §8，2026-10-26）**：33 骨在 ART03-① 就有了，
   本轮补了程序化的 `Idle/Walk/Run` 并接进游戏；仍缺 `AttackCue` / 扑击姿态 / 蹲伏姿态，
   蹲姿目前仍靠竖向压缩（0.625×）近似。
3. **胶囊与四足的包络不匹配**：视觉长 0.60 m，碰撞是 0.32 m 直径的竖直胶囊。
   改胶囊会牵动导航烘焙（`tool_make_courtyard_nav.gd`）与玩法数值 → **需负责人决定**（建议 T031 之后单独评估）。
4. **接触阴影**：灰盒关卡没有实时阴影配置，模型"落地感弱"部分是场景光照问题，不在资产侧。
5. **鼠仍是胶囊**：按 `modeling2.md` §五，试点验收通过前不批量替换。

---

## 8. ART02-ext（2026-10-26）：猫有了 Idle/Walk/Run + NPC 转向限速

### 现象与两个根因（用户反馈"猫的动作生硬、不自然"）
1. **猫一段动画都没有**：`sm_cat_002.glb` 有 33 骨、有 skin，但 `animations=0`；
   而鼠有 4 段（Idle/Walk/Run/Eat）→ 猫是"摆好的姿势贴地平移"，对比之下尤其假。
2. **NPC 朝向每帧硬切**：`animal_ai.gd` 用 `body.look_at(...)` 直接设朝向，没有角速度上限，
   转身一帧到位 → 配静止姿势 = 道具在滑。

### 谁做的（重要）
`Tools/Blender/art15_cat_anim.py` 与"带动画的 `SM_Cat_002.glb`"**接手时已在工作区未提交，非本次所写**。
本轮做的是：复核 → 把动画**接进游戏**（游戏里那份还是 10/21 的无动画旧档）→ 补断言 → 转向限速。

### 资产（`Art/Exports/Cat/SM_Cat_002.glb`，art15 产出）
- 网格/材质与 ART02 完全一致：**8,376 tris / 2 槽 / AABB 0.304614 × 0.310051 × 0.542281**（回归里逐条复验）
- 新增 **3 段动画**：`Idle`(48 帧) / `Walk`(24 帧) / `Run`(16 帧)，各 **99 通道**（33 骨 × TRS）
- 导入后每段保留 **18 条轨道**（导入设置 `remove_immutable_tracks=true` 会丢掉恒定不变的骨骼轨）
- 材质变化：眼睛槽由"贴图"变成**纯色** (0.03, 0.03, 0.03)、roughness 0.28（art15 重建材质时不再挂 `eye_3.png`）。
  因此把原来那条粗断言 `asset_materials_textured == 2` 换成三条更精确的：
  `asset_fur_albedo_textured` / `asset_fur_normal_textured` / `asset_detail_slot_is_flat`。

### 接线（游戏侧）
- 把 Art/Exports 的导出覆盖到 `Game/Reborn/assets/characters/cat/sm_cat_002.glb`（旧档 10/21、无动画），
  删 `.godot/imported/sm_cat_002*` 后**连跑两次 `--import`**（第一次只重建贴图，`.scn` 仍缺）。
- `animal_body.gd` 的接线本来就按名字找 `Idle/Walk/Run` 并按实际速度调 `speed_scale`，无需改代码。

### 转向限速（`scripts/ai/animal_ai.gd`）
```gdscript
const NPC_TURN_RATE_DEG_PER_SEC := 540.0   # 实现默认，待并入 Docs/Parameters.md
const NPC_TURN_STOP_ANGLE := 75.0          # 偏差大于它先站定转身，避免倒着冲
func _face_and_move(dir: Vector3) -> void  # 逐帧按角速度上限逼近目标 yaw
```
- 只改**表现朝向**（`rotation.y`）；路径点选择、到达判定、视线与攻击朝向仍读同一份真实朝向，只是连续变化。
- 540°/s ⇒ 掉头 180° 约 **0.33 s（20 帧 @60 Hz）**，正常巡视的小角度转向几乎无感。

### 新增断言（`run_art02_cat.gd`：47 → **72** 条）
- 资产层：`animation_player_exists` / `anim_count_3` / 三段各自 `present + length + track(≥12)`；
- 运行时：`runtime_anim_bound`、`Idle→Walk→Run→Idle` 切换、`run > walk`；
- 转向：`turn_rate_limited`（每帧 ≤ 540°/s·dt）、`turn_not_instant`（≥ 3 帧）、
  `turn_reaches_target`（≤ 5°）、`turn_stops_while_rotating`、`turn_moves_after_aligned`。
- 实测：`MEASURE|anim_switch|walk=1.800|run=4.500`；
  `MEASURE|turn|end=180.0°|worst_step=9.00°|max_step=11.00°|frames=20|gap=0.00°`。

### 证据图
`tests/tool_capture_cat_anim.gd`（新）→ `Art/Probes/catanim_walk_0..3.png`（一个步行周期的 4 个相位）、
`catanim_run_0..1.png`、`catanim_turn.png`。直接 Read 复核：四个相位里**前后爪位置互换、尾巴角度变化**，
猫沿地面推进 —— 不是静止滑行。

### 回归
全量 **30 套 / 3,198 条 / 0 失败 / 每套 EXIT=0 / `SCRIPT ERROR` 0**（较上轮 +25 条，全部来自 `run_art02_cat`）。

### 仍未做
- `AttackCue`、扑击/蹲伏姿态：没有专门 clip（蹲姿仍靠竖向压缩）；
- `Run` 是"加速版 Walk"（不是真正的 gallop），`Idle` 没有耳朵/眨眼等细节；
- 转向没有身体侧倾（视觉打磨项）；
- 转向角速度是**新的实现默认值**，未并入 `Docs/Parameters.md`（需负责人确认）。
