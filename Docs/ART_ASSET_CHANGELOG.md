# ART_ASSET_CHANGELOG —— 资产与风格变更记录

规则：任何**外形/风格/参考来源**层面的变更都要记一条，写清"为什么"。
单纯修 bug（法线、非流形、命名）记在对应 `Docs/Evidence/Txxx.md`，这里只记资产决策。

---

## 2026-10-22 · ART03-⑮-2 / ⑮-3 庇护棚收边：门垛立柱 + 转角料石

**变更类型**：环境视觉补件（**零玩法改动**，三面墙碰撞盒与导航一字未动）。

- `ENV_SHELTER_POST_001`（门垛立柱）：0.16 × 1.62 × 0.36 m / **28 tris** / 1 槽，程序化木柱，
  盖住门洞两个直立端、同时给棚顶东侧补支撑（原先东侧无柱、棚顶看着浮空）。
  **这部分接手时已在工作区未提交，非本次所写**；本轮复核后修了两处：材质从 (0.200, 0.125, 0.072)
  压到 **(0.062, 0.040, 0.023)**（原来比棚顶木料亮 4 倍，像塑料），以及一条重复断言 id。
- `ENV_QUOIN_001`（转角料石）：0.36 × 0.40 × 0.36 m / **44 tris** / 1 槽，每个外转角叠 4 皮到 1.70，
  **零碰撞**。用途是压住两片矮墙在转角处各自内缩 ±7 cm 的石排端 —— 否则那里露出一条
  6–10 cm 的衬板竖带 + 壳体薄边。
- 衬板改为**只在敞开的门垛端收进 0.15 m**（`trim_along_end`），转角端铺满：
  "两端都收"会把转角从"看穿"变成"看到一块灰板"，仍不算收边。
- 料石 UV 只在贴图里挑一块**平整且色调接近墙石**的 64×64 方块做投影窗口（跨砖缝会印出菱形花格），
  再用倍率色 (0.70, 0.78, 0.70) 压到墙石亮度 —— 仍守住"贴图 × 倍率色"的材质契约。
- 回归：全量 **30 套 / 3,173 条 / 0 失败**；新增立柱与料石断言共 30 条、衬板断言 3 条。
- 已知瑕疵：料石比毛石墙更规整、略浅（修琢料石 vs 乱石墙的质感差）。
- 未由负责人视觉验收（不写 approved）；未推送、未发布。

---

## 2026-10-22 · ART03-⑮ 庇护棚矮墙专用模块（`ENV_WALL_LOW_001`）

**变更类型**：环境视觉替换（**零玩法改动**，三面墙碰撞盒 `0.20 × 1.60 × 3.40/3.00` 一字未动）。

- 新资产：`Tools/Blender/art12_short_wall.py` → `Art/Exports/Environment/SM_Wall_Low_001.glb`
  = **2.436584 × 0.800000 × 0.302739 m / 663 tris / 1 材质槽**，源件仍是 `wall_stefan_wr`
  （S4，CC-BY，见 `Docs/THIRD_PARTY_ASSETS.md`），**不引入新来源**。
- 做法：取源件 `wall_stone`（围栏那件真墙面）**最上面 0.800 m**，上下各一刀切出，石块**完全不变形**；
  切口用一块**藏在砌体内部**的石板封住（`inset_x 0.90 / inset_y 0.42`、下沉 6 mm；第一版几乎与石块
  同宽同厚，层缝处露出一条偏亮的"找平线"，收进去后消失，仍保持 **1 材质槽**）。
  运行时 2 皮叠起来 = 1.6 m，`k_y = 1.0`（**没有任何竖向压扁**），
  横向 `k_x = 段长 / 2.436584`（3.0 m 段 1.231×、3.4 m 段 1.395×）→ 不重叠也不漏缝。
- 接入：生成器新增 `_mk_low_wall()`（碰撞盒不变，隐藏原 `Mesh`，加不投影的 `Backing` 衬板，
  **衬板色 0.20 → 0.34** 让石缝读成砂浆而不是黑洞），三面 `ShelterWall*` 从 `_mk_clad_wall` 改用它。
- 为什么换：旧做法把 **3 m 高的围栏模块压到 1.6 m**（k=0.533）→ 石块比例走样 + 源件下半部本来就是
  **被地面遮挡的扫描区**（石块有大缺口）→ 近看是"石块悬空 + 大片深色衬板"，即上一轮记录的已知瑕疵。
- 选材弯路（都试过，记下来）：① `wall_stone_low` 隔离渲染后被证伪 —— 它是**7 块零星石头的锥形残堆**；
  ② `wall_stone_medium` 是 4 排梯形石堆；③ `wall_stone_triplet` 只有 3 块石头。源件里**只有 `wall_stone` 是真墙面**；
  ④ 用"顶点压平"削高会让三角面挤成一条、法线翻转被剔除 → 实机出现塌陷空洞，改为"切开 + 补帽"。
- 回归：全量 **30 套 / 3,173 条 / 0 失败**；新增 9 条矮墙断言 ×3 面（资产来源、无碰撞、层数、
  层高、厚度同比、宽度=间距、不出段、竖向精确踩地到顶、衬板存在）。
- 已知瑕疵：模块两端石排有源件自带的小台阶（±7 cm）；`k_x` 有 1.23–1.40 的横向拉伸（石块略宽）；
  个别石排缺口处仍会露出小亮块（藏起来的封口石板）。

---

## 2026-10-21 · ART03-⑭ 树根屏障本体换盘根模块

**变更类型**：环境视觉替换（**零玩法改动**，碰撞盒与洞口净空未动）。

- 新资产 `Tools/Blender/art11_root_barrier.py`（确定性 seed）：`ENV_ROOT_BARRIER_001`
  = 3 根沿 X 的主根 + 4 根斜跨细根 + 3 根入地根须（锥形管，8 边 × 5 段），
  **640 tris / 1 材质槽**（程序化树皮倍率贴图 + 棕色因子）。正向构建 3.27×0.64，
  按模块上限统一缩放 0.7536 → **2.461 × 0.296 × 0.480**。
- 接入：`_mk_root_barrier_visual()` 在 `RootBarrierWest`（16.38 m → 7 块）与
  `RootBarrierEast`（9.38 m → 4 块）上平铺，交替 180° 翻转；原 `Mesh` 隐藏。
- **碰撞盒（0.50 × 1.00）与洞口 0.24 × 0.30 净空一字未改** → T010 鼠钻洞、T011 猫跳顶/鼠钻洞、
  T012 分层导航全部原样通过。
- 回归：全量 **30 套 / 3,173 条 / 0 失败**；实机图 `Art/Probes/art07_barrier_wide.png` 显示横卧盘根 + 洞口树桩。
- 瑕疵：单根是规整圆管（缺分叉/结节），段间接缝有周期性；`RootBarrierLintel` 仍是盒子（被树桩遮住）。

---

## 2026-10-21 · ART03-⑬ 土墩 / 棚顶换真资产

**变更类型**：环境视觉替换（**零玩法改动**，碰撞盒未动）。

- 新资产 `Tools/Blender/art10_props_002.py`（确定性 seed）：
  - `ENV_MOUND_001`：径向环 + 低频噪声起伏、边缘落到 z=0 的**低模圆丘，198 tris**；
  - `ENV_ROOF_001`：**9 条木板（带缝隙与高差）+ 2 根托梁，228 tris**。
- 接入：生成器新增 `_mk_prop_visual()`（保留 StaticBody3D 与碰撞盒，隐藏原 `Mesh`，换 glb 实例）；
  土墩复用 `ground.gdshader`（世界坐标草/土斑块），棚顶按盒尺寸微缩到 3.4×3.8 内。
- 碰撞盒 2.0×0.50×2.0 与 3.4×0.2×3.8 **一字未改**，T011 的土墩高度 / 棚顶净空断言原样通过。
- 回归：全量 **30 套 / 3,173 条 / 0 失败**；实机图 `Art/Probes/art06_shelter.png` 显示板条棚顶。
- 仍为灰盒：`RootBarrierWest/East/Lintel`（木根屏障本体）。
- 已知瑕疵：庇护棚矮墙把 3 m 模块缩到 1.6 m，石块被压扁、深色衬板在石缝处裸露，近看偏"碎"。

---

## 2026-10-21 · ART03-⑫ 地面 / 碎屑 / 溪岸墙：再换三处灰盒

**变更类型**：环境视觉替换（**零玩法改动**，碰撞盒一字未改）。

- **Ground**（80×80，场景最大面积）：纯色 → 新 `shaders/ground.gdshader` 程序化材质
  （低频 fbm 混「草 / 土 / 干草」三色 + 高频细粒），无贴图依赖、缺文件自动退回纯色。
- **CourtyardDebris1..3**：0.6×0.3×0.6 纯色盒子 → **缩小版 `sm_boulder_001` 真石头**
  （复用 CC0 巨石；scale 0.40/0.46/0.52 + 绕 Y 随机转角），碰撞盒不变。
- **CreekBankWallA/B**（各 8 m）：0.30×1.00×8.00 纯色盒子 → **与围栏同一套石墙模块平铺**
  （`_mk_clad_wall`，k=0.333 → 每道 9 块），碰撞盒与溪缝 0.24 不变。
- 复用而非新建资产：碎屑与巨石共用 `sm_boulder_001.glb`，岸墙与围栏共用 `sm_fence_module_001.glb`。
- 回归：全量 **30 套 / 3,173 条 / 0 失败**。
- 仍为灰盒（下一批）：`RootBarrierWest/East/Lintel`（26 m × 0.5 m 木根屏障本体）、`ShelterRoof`、`GrassMoundA/B`。

---

## 2026-10-21 · ART03-⑪ 草丛面数预算 3k → 6k（叶片 220）

**变更类型**：资产规格调整 + 资产迭代（**零玩法改动**）。

- 负责人选择「A：把面数预算提到 6k、叶片加回 200+ 并加宽」。
- 依据（实测而非感觉）：`tool_perf_probe.gd` 测得本关卡 **1.643 ms/帧（p95 1.969）≈609 fps @720p**，
  升级后场景 **178,068 primitives / 53 draw call** 仍不是瓶颈。
- 改动：`TRI_BUDGET 3000 → 6000`；叶片 145 → **220**（96/72/52 三圈）；基部宽 30–55 → **34–62 mm**。
  结果 **4,480 tris**，AABB 2.800434 × 0.815600 × 2.929748。
- 同步：`run_art01_bush.gd` 的 `EXPECT_TRIS=4480` / `EXPECT_MESH_*` 与预算断言 `≤6000`；
  `Docs/ART_ASSET_SPEC.md` 新增「草丛掩体 3k–6k」预算行（旧 3,000 是 ART01 时期的保守值）。
- 颜色/法线贴图、双面法线、双材质、零碰撞等契约不变。
- 回归：`run_art01_bush` **83/83**；全量 **30 套 / 3,173 条 / 0 失败**。

---

## 2026-10-21 · ART03-⑩ 草丛叶片细分 / 法线贴图 / 双面法线

**变更类型**：环境资产迭代（**零玩法改动**，材质颜色契约不变）。

- **细分**：叶片 3 段 → **5 段**（叶尖不再硬折）；为守住 ART01 的 ≤3000 tris 预算，
  叶片数 210 → **145**，总计 **2,980 tris**。
- **法线贴图** `T_Grass_Leaf_N`（128×256，Non-Color）：由"中脊凹槽 + 叶脉细棱 + 斑驳 + 叶缘下卷"
  的高度场做有限差分生成切线空间法线，接 `Normal Map → Principled Normal`，导出开 `export_tangents`
  → GLB `normalTex=True`。
- **双面法线修正**：`grass_wind.gdshader` 里 `NORMAL = FRONT_FACING ? NORMAL : -NORMAL;`
  —— 草叶是单面网格 + `cull_disabled`，背面不翻法线会让**草丛内部发黑**（蹲在草里最明显）。
- 同步：`run_art01_bush` 的 `EXPECT_MESH_X/Y/Z` 与 `EXPECT_TRIS=2980`；生成器体积下界
  `y ≥ 0.80 → 0.78`（0.797 仍远高于猫 0.48，掩体语义不变，已在注释标明）。
- 回归：`run_art01_bush` **83/83**；全量 **30 套 / 3,173 条 / 0 失败**。
- 局限：法线贴图程序化生成、近景仍有程序化底子；叶片数量减少后密度略降。

---

## 2026-10-21 · ART03-⑨ 草丛叶片/泥土贴图

**变更类型**：环境资产迭代（**零玩法改动**，颜色/材质契约不变）。

- `art09_grass_002.py` 新增 `make_leaf_image` / `make_soil_image`：程序化生成
  **叶片 128×256**（根暗 0.78 → 中上部 1.10 → 叶尖 0.90，中脊高光，叶脉纵纹，斑驳，轻微色偏）与
  **泥土 128×128**（两级斑驳 + 边缘压暗），全部 `pack()` 进 GLB。
- **关键设计**：贴图是**倍率图（均值≈1）**，节点用 `MixRGB(MULTIPLY)`：`image × 线性色 → Base Color`。
  这样 glTF 同时导出 `baseColorTexture` 与 `baseColorFactor`，ART01 的
  "albedo ≈ sRGB(线性色)" 契约**不需要放宽**（实测 factor = [0.085, 0.200, 0.075]）。
- Godot 侧自动抽取 `sm_bush_002_T_Grass_{Leaf,Soil}.png` 并生成 `.import`；`albedo_color` 不变。
- 回归：`run_art01_bush` **83/83**；全量 **30 套 / 3,173 条 / 0 失败**。
- 局限：远处（>6 m）增益有限；**没有法线贴图**；叶片仍是 3 段，近景有轻微硬折。

---

## 2026-10-21 · ART03-⑧ 草丛重做（`ENV_BUSH_002`）

**变更类型**：环境资产替换（**零玩法改动**，掩体 Area3D/碰撞契约不变）。

- 旧资产 `sm_bush_001`：单层平面四边叶片（2,040 tris）→ 近距离是"绿纸条"；土垫直径 2.87 m 像棕色大饼。
- 新资产 `sm_bush_002`（`Tools/Blender/art09_grass_002.py`，确定性 seed）：
  **带中脊折面的 3 段弯曲叶片**（横向 2 格 → 有折角）、基部 30–55 mm、尖端收细下垂；
  **210 片**分 3 圈 + 各自独立倾角/扭角/长度；土垫收到半径 0.62 m 并补盘心；**2,600 tris**。
- 契约不变：2 材质槽（`MAT_Bush_Leaf` / `MAT_Bush_Soil` 同名同线性色）、**双面**、roughness 0.85、**零碰撞**；
  包络 2.7648 × 0.8155 × 2.9521（覆盖 3×3 掩体、高于猫 0.48）。
- 4 处掩体 + 13 丛芦苇 + 岸线草全部随之换新；ART03-⑦ 的风摆 shader 继续作用于 leaf 表面。
- 同步更新 `run_art01_bush.gd` 里"记录资产事实"的常量（根名/mesh 名/AABB/面数）；
  **材质名/颜色/双面/零碰撞/高度覆盖等契约型断言没有放宽**，全部原样通过。
- 回归：`run_art01_bush` **83/83**；全量 **30 套 / 3,173 条 / 0 失败**。
- 旧 `sm_bush_001.glb` 保留在仓库，可一键回退。
- 未解决：仍无贴图（纯色 + 折面）；叶尖 3 段有轻微硬折。

---

## 2026-10-21 · ART03-⑦ 溪道岸线 / 水下砾石 / 草丛风摆

**变更类型**：环境视觉（**零玩法改动**，全部 `MeshInstance3D` + shader）。

- **锯齿泥舌**：22 段低矮湿泥板（顶面 0.142）沿水面四边、每段探进水里或退回岸上 ±0.4 m，
  尺寸/朝向/明暗按段号确定性抖动 → 把"矩形直边"遮成弯岸线。
  原理说明：水位 0.13 与地面 0.10 都被 T011 钉死，无法靠抬高岸做岸线，只能"让陆地探进水里"。
- **水下砾石层** `CreekBed`（顶面 0.106）：水 alpha 0.62，没有它透出来是灰色地面。
- **草丛风摆** `shaders/grass_wind.gdshader`：顶点位移 ∝ (y/0.88)^1.7、双频正弦、相位含世界坐标；
  `_apply_grass_wind()` 只替换名字含 `leaf` 的表面（土墩面不动），albedo/roughness 继承原材质。
- 水面：菲涅尔权重 0.45 → 0.30（远处掠射角原来过曝成灰白）。
- 取证：同机位两帧 `mean_abs_diff 0.0222 / 0.0248`、变化像素 29%。
- 回归：全量 **30 套 / 3,173 条 / 0 失败**。
- 未解决：草叶仍是平面片（需重做草丛网格 + 更新 ART01 断言）；泥舌是矩形板；溪道仍是直线带。

---

## 2026-10-21 · ART03-⑥ 溪水与溪边视觉打磨

**变更类型**：环境视觉（**零玩法改动**）。

- 触发：负责人看图指出「草丛和溪边很假、水都不带动的」。
- 水面：`StandardMaterial3D`（纯色、无时间项）→ **程序化 `creek_water.gdshader`**：
  三层随时间滚动的 value-noise + 域扭曲 + 有限差分求法线 + 菲涅尔 + 岸边泡沫；`roughness 0.08` 出高光斑。
- 形状：`WATER_SIZE.z 20 → 9`，从"占满 Creek 区的池塘"收成 **22×9 溪带**（仍覆盖 `WaterPoint_Creek`）。
- 溪边：新增 `_add_creek_dressing()` —— **13 丛芦苇**沿两岸（yaw/scale 打散）+ 4 条**湿泥岸带**，
  把"蓝面硬切草地"改成"草 → 湿泥 → 水"。
- 硬约束未破：水面仍是 `MeshInstance3D + BoxMesh`、`water_depth=0.03`、`water_bodies` 组=1、零碰撞；
  新增节点全为 `MeshInstance3D`（零碰撞、不进导航组）。
- 取证：新增 `tool_capture_creek.gd`，同机位相隔 45 帧两帧：`mean_abs_diff 0.021/0.031`、
  `changed_px_ratio 0.31/0.43` ⇒ 水确实在动。
- 回归：全量 **30 套 / 3,173 条 / 0 失败**。
- 明确未做：草丛网格仍是 ART01 的**平面叶片**资产（近距离"绿纸条"），也没有风摆 —— 要改属独立任务。

---

## 2026-10-21 · ART03-⑤ 鼠动画接线 + 场景渲染实测

**变更类型**：行为接线（**视觉层**，不改玩法数值）+ 性能实测。

- `animal_body.gd`：`_bind_visual_animation()` / `_update_visual_animation(speed)` —— 按**实际水平速度**
  在 `Idle/Walk/Run` 之间切换，`speed_scale` 跟速度挂钩；只读速度与冲刺意图，**不写** `velocity`/`move_intent`；
  clip 缺失保持不动；没有 `AnimationPlayer` 的物种（猫）零影响。
- 验证：`run_art03_mouse.gd` 新增 6 条断言（静止→Idle、走→Walk、冲刺→Run、跑比走快、停下→Idle、绑定成功）。
- 实测（`tests/tool_perf_probe.gd`，720p / 关 vsync / 墙钟 240 帧）：
  **1.662 ms/帧（p95 2.407）≈600 fps、111,028 primitives、32 draw call、112 objects**
  → 石墙平铺 90 件的 **120,668 tris 不是瓶颈**。
- **测量陷阱记录**：首次用 `Performance.TIME_PROCESS` 采样得到 240 帧全为 `84.077 ms`，
  是窗口被节流造成的假象；改用墙钟计时后才是真实分布。
- 来源说明：`animal_body.gd` 的动画代码**在接手收尾时已在工作区未提交**（非本人所写），
  本次做的是复核、补断言与提交。

---

## 2026-10-21 · ART03-④（鼠）换源：CC-BY mehrus rat → `SM_Mouse_002.glb`

**变更类型**：**关键角色视觉替换**（胶囊 → 带骨骼/动画的参考模型），玩法数值零改动。

- 弃用：`mouse_arribadaclub`（展平标本扫描件，无腿）；`mouse_charliecatling`（**Free Standard + NoAI**，
  与"资产入库 + AI 参与处理"冲突）。负责人 2026-10-21 决策：只找 CC0/CC-BY。
- 采用：`mouse_cc_mehrus_rat`（**CC Attribution**，作者 Mehrus，3,602 tris / **23 骨** / **4 段动画**）。
- 处理要点：unlit 材质重建 Principled；头朝 −Y → 绕 Z 180°（项目契约 Blender 面朝 +Y）；
  去尾体长 0.135 m 归一；原点=脚印中心+脚底；4 段动作塞 NLA 轨道导出 + 裁掉 Blender 3.3 多吐的 7 段常量动画。
- 接入：`mouse.tres` 加 `visual_scene`（胶囊 r=0.06 / half_height=0.09 **未改**）。
- 顺带更新两处过时断言（`run_art02_cat` 的"鼠仍是占位"、`run_t021_capture` 的 `body_mesh.visible`）。
- 视觉状态：`generated + 实机 2 图`，**未 approved**；鼠是 **rat 体态**不是家鼠。
  证据：`Docs/Tasks/ART03_MOUSE.md`、`Docs/Evidence/ART03_MOUSE.md`。

---

## 2026-10-21 · ART03-④ 鼠洞入口换成真实树桩（`stump_callum_arb`）

**变更类型**：**正式关卡资产替换**（灰盒洞口 → 参考基础模型 + 自建贯通孔）。

- 源：Sketchfab `stump_callum_arb`（**CC-BY**），39,122 tris（超预算 2.6 倍）、1 材质槽，
  世界 bbox 2.128 × 2.666 × 1.205 —— **含扫描自带的方形地面**，网格是 **528 个连通块**。
- **关键实测**：腔体是"碗"形、**没有任何贯穿洞**。早前"腔体净空 0.238×0.173 m"是按包围盒猜的，已作废。
- 处理：裁半径 0.55 m 外的面（39,122→24,239）→ 删小连通块（→23,160）→ 焊接后单轮减面（→13,999）
  → 归一高 0.85 m → **布尔破 0.24 × 0.30 贯通方孔**（→12,555）→ 清空材质槽。
- 接入：`_mk_root_hole_visual()`，**南北各一桩**贴住屏障两面（z=18.111 / z=19.889），
  资产里的孔与玩法孔首尾相接；**零碰撞**、不进导航组，通行仍由 `RootBarrier*` 的 BoxShape3D 决定。
- 为什么这么放：首版把桩心放在 z=19（屏障正中、屏障深 1.0 m）→ 整桩被灰盒吞掉、只剩顶部露出。
- 视觉状态：`generated + 4 机位实机图`，**未 approved**（负责人判读）。
  证据：`Docs/Tasks/ART03_ROOTHOLE.md`、`Docs/Evidence/ART03_ROOTHOLE.md`。

---

## 2026-10-21 · ART03-③ 围栏与庇护棚墙换成石墙模块（`wall_stefan_wr`）

**变更类型**：**正式关卡资产替换**（灰盒 → 参考基础模型）+ **一处关卡打光变更**（见最后一条）。

- 源：Sketchfab `wall_stefan_wr`（**CC-BY**，作者 Stefan），7 个模块件、2,000 tris 合计。
  取 `wall_stone` 件（1,244 tris，源尺寸 246.07 × 30.27 × 200.58，单位≈厘米）。
- 处理：÷100 → 墙面内等比缩放到**高 3.000 m**（厚保持天然 0.302739）→ 原点归一到脚印中心 + 脚底；
  材质从源里的 `Diffuse+Glossy+Add Shader` 旧式节点**重建为 Principled BSDF**（BaseColor + Normal + Roughness 0.85），
  否则导出的 GLB 完全没有贴图。
- 接入：`tool_make_courtyard.gd` 新增 `_mk_clad_wall()`，4 段边界围栏 + 庇护棚三面墙共 **90 个模块实例**；
  **碰撞盒尺寸/位置一字未改**（仍是 `BoxShape3D`）；新增深色 `Backing` 衬板遮住石块间的真实通孔；
  相邻模块重叠 ≥20% 并交替 180° 翻转。
- **打光变更（真缺陷修复）**：北墙内表面朝 −Z、与主光同向 → 整面近乎全黑，3 m 石墙读不出材质。
  新增一盏**不投影**的 `SkyFill`（朝下 +Z，能量 0.45）；主光方向与阴影方向不变。
- 为什么做：`modeling4.md` 要求逐个替换灰盒；围栏是**玩法边界**，视觉必须与碰撞一致（3.0 m 高）。
- 代价：墙类合计 **120,668 tris**（本关卡最大开销，未做帧率实测）。
- 视觉状态：`generated + 4 机位实机图`，**未 approved**（负责人判读）。证据：`Docs/Tasks/ART03_FENCE.md`、`Docs/Evidence/ART03_FENCE.md`。

---

## 2026-10-21 · ART03-② 溪边巨石换成真实岩石（`boulder_01`）

**变更类型**：**正式关卡资产替换**（灰盒 → 参考基础模型），玩法几何契约不变。

- 源：Poly Haven `boulder_01`（**CC0**，glTF 1K），实测 66,122 tris / **1.2721 × 1.8303 × 1.0038 m（米制）** / 1 材质槽 / 3×1K 贴图。
- 处理：焊接（`remove_doubles 1e-5`，67,042→33,063 顶点）→ 单轮 Collapse 减面到 **7,500 tris**（预算 1k–8k）→ 原点归一到脚底中心。
- 接入：`tool_make_courtyard.gd` 新增 `_mk_boulder()`，替换 `CreekBoulder` 的 1.2³ BoxMesh；**视觉来自 .glb，碰撞仍是 Godot 侧 `BoxShape3D`**（尺寸 = 视觉 AABB）；**不缩放**。
- 为什么换：`modeling4.md` 要求"先选对基础模型"；巨石是**非关键环境静物**，风险最低，先把"参考件 → 合规资产 → 接入 → 回归"闭环跑通，再碰围栏/洞口/鼠。
- 顺带修掉的真缺陷：① glTF 接缝拆点导致 Collapse 减面卡在 26,147（先焊接解决）；② T012 溪缝断言依赖导航 tie-break（改为经缝内航点逐腿查询）。
- 视觉状态：`generated + 4 机位实机图`，**未 approved**（负责人判读）。证据：`Docs/Tasks/ART03_BOULDER.md`、`Docs/Evidence/ART03_BOULDER.md`。

---

## 2026-10-21 · Reference Lock 第 1 轮（本轮）

**变更类型**：流程与参考库（**未改动任何正式游戏资产**）

- 新增强制流程 `reference_pending → reference_confirmed → modeling → review → approved`（见 `Docs/ART_ASSET_SPEC.md` §5）。
- 新增 `references/` 参考库：`ART_STYLE_GUIDE.md`、`reference_manifest.json`、
  `characters/{cat,mouse}/candidates/`、`environment/{root_hole,boulder,fence}/candidates/`。
- 新增 `Docs/ART_ASSET_SPEC.md`（逐资产规格 + 面数预算 + 五项评分 ≥85）、`Docs/ART_ASSET_AUDIT.md`（现状审计）、
  `Docs/THIRD_PARTY_ASSETS.md`（第三方登记 + 署名义务）。
- **风格基线定为"写实偏风格化"**（理由：硬核生存 + 近距动物对峙 + 现有关卡的自然材质方向；换卡通会造成风格断裂）。
  → **待负责人确认**；若改为卡通，`cat/candidates/cat_toon_omabuarts` 与 Kenney Nature Kit 会重新进入候选。
- **实际下载**：Poly Haven `boulder_01`（CC0）glTF 1K 五个文件，字节数与 API 一致；隔离存放于 `references/`。
- **未下载**：全部 Sketchfab 候选（需登录）；状态 `reference_pending`，附人工下载步骤。

**为什么**：`modeling3.md` 的重建（V009）证明"脚本化建模"无法达到专业动物形体；
`modeling4.md` 要求先选对基础模型、建立可验证参考标准，再谈建模。

---

## 2026-10-21 · ART02-V009 基础形体重建：**not-accepted**

- 方法变更：从"放样零件 + voxel remesh + decimate + 噪声位移"改为
  "一根骨架 + Skin 修改器 + 1 级细分 + bmesh 松弛 + 宽高斯解剖塑形"（**不再使用 remesh/decimate/噪声**）。
- 结果：5296 tris / 99.3% 四边形 / 0 非流形 / 4 毛发壳 / min_z=0；但**横向环状台阶、四肢关节不可辨、脚掌无趾部**。
- 决策：按 `modeling3.md` §6 **停止迭代**；**正式资产保持 V008**，V009 未接入 Godot。
- 证据：`Docs/Evidence/ART02_V009.md`；对比图 `Art/Staging/ART02_V009/ART02_V008_vs_V009_views.png`。

---

## 2026-10-21 · ART02 V008（猫）：`modeling`（在用，未 approved）

- 猫的视觉由 `CapsuleMesh` 换成真实模型：9568 tris / 2 材质槽 / 2048² 烘焙 albedo；配置驱动接入（`SpeciesConfig.visual_scene`）。
- 5 轮返工（v001→v008），视觉判读从"完全看不出是猫"提升到"轮廓可辨认为猫"；**未达正式美术水准**。
- 证据：`Docs/Tasks/ART02.md`、`Docs/Evidence/ART02.md`。

---

## 2026-10-21 · ART01（草丛掩体 `ENV_BUSH_001`）：`modeling`（在用，未 approved）

- 半透明绿盒子 → 2040 tris 真实草叶，双面、零碰撞；3 轮返工。
- 证据：`Docs/Tasks/ART01.md`、`Docs/Evidence/ART01.md`。

---

## 2026-10-21 · Reference Lock 第 1 轮（续）：实际下载 + 真实网格检查

**变更类型**：参考资产取得与测量（**仍未改动任何正式游戏资产**）

- 使用**负责人已登录的浏览器会话**的 API token 取得 Sketchfab 签名直链，实际下载并校验了 4 个候选：
  `cat_fripouille`（FBX + 4 张 PBR 贴图）、`mouse_arribadaclub`（glb）、`stump_callum_arb`（glb）、`wall_stefan_wr`（glb）。
  加上此前 Poly Haven `boulder_01`（CC0 glTF 1K），五类资产**每类都有一份可离线检查的文件**。
- 用 Blender 3.3.1 逐个导入读回真实网格（`references/reference_measurements.json`）：
  四个 Sketchfab 文件的 `faces` 与 API 完全一致；猫**带 33 骨但 0 动作**；鼠/桩/墙**无骨骼**；
  猫与墙的**尺度不是米**、需要归一化；洞口腔体实测 ≈0.238×0.173 m，**未达 0.24×0.30 m 要求**。
- 未取得：`mouse_charliecatling`（403/400）、`cat_bigcat_gbarzu`（未下）。已在 manifest/measurements 里如实记录。
- `references/_downloads/`（第三方原始下载，20+ MB）加入 `.gitignore`；来源 URL + 许可 + 大小/哈希前缀已登记在
  `Docs/THIRD_PARTY_ASSETS.md` §6。

**为什么**：`modeling4.md` §三要求"不要因为渲染图好看就直接选用，必须检查真实网格"；这一步把选型从"看截图"变成"看数据"。

---

## 2026-10-21 · 负责人决策：猫用 `cat_fripouille`，其余取已下载候选

- 五类资产在 `references/reference_manifest.json` 里全部置为 **`reference_confirmed`**，猫另进 **`modeling`**：
  猫 `cat_fripouille` / 鼠 `mouse_arribadaclub` / 洞口 `stump_callum_arb` / 围栏 `wall_stefan_wr` / 巨石 `boulder_01`（CC0）。
- 新增 `Tools/Blender/art04_cat_from_ref.py`：导入参考 FBX → 并 2 材质槽 → 按体长 0.58 m 归一 → 按眼睛质心转向 → 贴地 →
  导出 `Art/Exports/Cat/SM_Cat_002.glb`（8,376 tris / 2 槽 / 33 骨 / 高 0.307 m / min_z=0）。
- **未接入 Godot**：`cat.tres` 仍指 V008；等视觉确认后再切（`modeling4.md` §五 要求关键角色最终批准由负责人给）。
- **猫已接入游戏**（2026-10-21 后续）：`cat.tres` → `res://assets/characters/cat/sm_cat_002.glb`；
  **46/46 ART02 断言全过**；游戏内同机位实拍 `Art/Probes/art02_ingame_after_v2.png`（+ `_crop.png` 放大）
  —— 橙色虎斑 + 白腿的真猫，正面朝向玩家、四脚落地。
- **多模态已可用**：直接 `Read` PNG 即可看图（不再依赖 `vision.js`）；本次据此发现并修掉了**朝向反 180°**的问题
  （原旋转符号取反，X→-Y）与**渲染地面混进 GLB**（导出未排除 `RENDER_*`）。
- 仍需注意：`Art/Probes/art04_cat_ref_face.png` 是 85mm 近景，用于看面部结构。
