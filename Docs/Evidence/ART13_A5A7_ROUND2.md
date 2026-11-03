# ART13 证据：A5/A7 收口轮 2 + tp 过曝与远景平铺遗留清理

执行日期：2026-11-02 ～ 2026-11-03（本机系统时钟）
任务规格：`Docs/Tasks/ART13_A5A7_ROUND2.md`。状态：**done（视觉门按 vision 判读到可验证 PASS；不是正式美术 approved）**。
工程：`E:/Reborn`，Godot 4.7.2，Windows / Forward+。所有实跑/截图一律走 `Tools/CaptureRun.ps1`（隐藏桌面/`-Headless`，零窗口）。

## 1. 变更范围

| 文件 | 改动 |
|---|---|
| `Game/Reborn/tests/tool_make_ravine_board.gd` | S1 tp 过曝（exposure/glow 阈值）；S2 地面换双尺度 ShaderMaterial |
| `Game/Reborn/shaders/ground.gdshader` | S2 可选贴图路径（世界坐标双尺度混合，`tex_amount` 默认 0 = 既有使用者零变化） |
| `Game/Reborn/tests/run_art09_frame_contract.gd` | S2 `_check_textured` 扩展接受"带贴图的 ShaderMaterial"（契约意图不变：地面必须有贴图） |
| `Game/Reborn/tests/tool_make_courtyard.gd` | S3 庭院地面接 leafy_grass；S4 结构接地阴影 +9；S5 湿泥带 4 段 + 溪中石暗片 6；S6 远景深度雾开启 |
| `Game/Reborn/tests/run_t011_greybox.gd` | §G 计数同步（阴影 56、湿泥带进 want_decor） |
| `Game/Reborn/tests/tool_capture_creek.gd` | 修湿泥带节点名契约：旧 `CreekWetBank*` 早已随 ART03 迭代移除，检查一直空跑 false → 改 `CreekWetBand{N,S}{1,2}` |
| `Game/Reborn/tests/run_t020_perception.gd` | 导航就绪竞态修复 `_await_nav_ready()`（见 §7，断言零改动） |
| `Game/Reborn/scenes/maps/l_courtyard.tscn` | 生成器产物（S3～S6） |
| `Game/Reborn/scenes/maps/l_ravine_board.tscn` | 生成器产物（S1/S2） |

未改：猫鼠模型与动作、玩法/碰撞/导航层契约/鼠洞溪缝尺寸、`menu_creek.png`、`forest_floor`（保留）。
新增工具：`Tools/make_art13_compare.ps1`（相邻状态对比拼板，见 §5）。

## 2. 参数登记（旧值 → 新值）

### 2.1 S1 展板关 tp 过曝（只动后处理层，不动已判 PASS 的光照方向）

| 参数 | 旧值 | 新值 | 依据 |
|---|---:|---:|---|
| `tonemap_exposure` | 1.05 | 0.92 | ACES 曝光整体回压，中心高光收进滚降区 |
| `glow_hdr_threshold` | 1.15 | 1.30 | 辉光只保留更强高光，减少中心泛白叠加 |

### 2.2 S2 ground.gdshader 双尺度贴图路径（新 uniform，默认值即初值）

| 参数 | 初值 | 说明 |
|---|---|---|
| `tex_amount` | 0.0 | 0=纯程序化（既有使用者零变化）；1=贴图为主 |
| `tex_albedo/tex_normal/tex_arm` | leafy_grass 三件套 | 复用 ART11 已入库 CC0 贴图 |
| `tex_scale_a` | (0.52, 0.52) | 主尺度（tile≈1.9 m，展板关原平铺密度） |
| `tex_scale_b` | (0.185, 0.185) | 第二尺度（tile≈5.4 m）+ 相位错开 |
| `tex_noise_scale` | 0.06 | 双尺度混合噪声频率（~17 m 一变） |
| `tex_tint` | 展板 (0.82,0.88,0.74) / 庭院 (0.88,0.92,0.80) | 接入旋钮 |

**triplanar 判定（负责人问题 2 的答案）**：`ground.gdshader` 是世界坐标程序化噪声，本身没有 UV 平铺可治；平铺感来自展板关 `StandardMaterial3D` 的 UV 平铺。纯平地上 triplanar 不改变重复频率（重复由 tile 尺寸决定），只消除曲面/多面投影拉伸 → **不能解决平地远景平铺感**。低成本替代 = 同一贴图两个尺度 + 世界坐标低频噪声互混（打破周期），即本路径。

### 2.3 S4 结构接地阴影（+9 → 总数 48）

棚柱×2、棚内地坪×1（alpha 0.10）、根障基座×2（alpha 0.14）、围栏基脚×4（alpha 0.10）。全部零碰撞、不进导航组、名字带 Shadow 进计数断言。

### 2.4 S5 湿泥带 + 溪中石接地（+2+6 → 总数 56）

湿泥带 4 段（每侧 2 段，缝口 x∈[-33.3,-30.1] 留空，保住"缝口两侧空地"可读性），unshaded 半透明暗棕（alpha 0.30，径向渐变），贴地 0.107。溪中石脚下暗片×6（水下接地，读作"泡在水里"）。湿泥带进 T011 want_decor。

### 2.5 S6 远景深度雾（A5 空气透视）

`fog_enabled=true`（DEPTH begin 80 / end 170 m、`sky_affect=0` 不动），`fog_light_energy` **0.75→0.45**、颜色压暗到 **(0.50,0.55,0.62)**——上一轮判"整屏灰白"的头号嫌疑是雾光能量，先压它。T011 `decor_fog_is_far_depth`（begin≥60）本就允许。

## 3. 六步结论（每步：改 → 重建 → 同机位取证 → vision 复判）

判读工具：负责人指定 `node E:/claude-vision-skill/vision.js <png> <中文检查问题>`。对比板见 §5。

| 步 | 内容 | 用例 | 结论 |
|---|---|---|---|
| S1 | tp 过曝（exposure 0.92 / glow 1.30） | U1 | **PASS（定性）**：对比板 `cmp_s1_ravine_tp_exposure` 判读——中心过曝收住，暗部/中景细节未被压死。本轮未出数值分 |
| S2 | 双尺度贴图路径 + 展板地面换材质 + 契约扩展 | U2 | **PASS（定性）**：对比板 `cmp_s2_ravine_far_tiling` / `cmp_s2_ravine_tp_tiling` 判读——远景平铺重复/拼接感减弱，近景观感不劣化。本轮未出数值分 |
| S3 | 庭院地面接 leafy_grass | U3 | **PASS（定性）**：对比板 `cmp_s3_{courtyard,grass_danger,map_overview}_ground` 判读——地表有细节、"糊脏迷彩"大幅降低、草土区域感仍在；与 ART12 草带共同构成 A5 的中景层 |
| S4 | 结构接地阴影 +9（棚柱/棚内地坪/根障基座/围栏基脚） | U4 | **PASS，vision 8 / 9 / 9.5**（courtyard_shelter / roots_barrier / map_overview_fence 三机位）：棚柱、根障、围栏"坐住"地面，无新穿帮 |
| S5 | 湿泥带 4 段 + 溪中石暗片 6 | U5 | **PASS，vision 8.5 / 8 / 9**（creek_wide / creek_low / creek_gap_lane 三机位）：水岸硬切/矩形感减弱、溪中石读作泡水；剩轻微项"溪中石暗片边缘稍硬（creek_low 视角）"，记录不阻塞 |
| S6 | 远景深度雾（energy 0.45、色 (0.50,0.55,0.62)） | U6 | **PASS，vision 9 / 9.5 / 9**（overview 机位三轮判读）：整屏偏灰**已治好**（无灰白雾幕回潮）、纵深仍在（远景更淡、前中后三层可辨）、**无新雾墙/发脏** |

S1/S2/S3 按证据只作定性描述——本轮判读未产出数值分，不补造。

## 4. A5 / A7 判定（ART07 遗留门）

| 门 | 判定 | 依据 |
|---|---|---|
| **A5 前中后景与空气透视** | **PASS** | S6 深度雾使远景变淡有空气透视且整屏无灰幕（overview 9/9.5/9）；S3 地表贴图 + ART12 草带补足中景细节层；U6 判据全满足 |
| **A7 无漂浮/穿插（接地感）** | **PASS** | S4 结构接地阴影（8/9/9.5）+ S5 湿泥带与溪中石接地（8.5/8/9）+ S3 地表迷彩大幅降低点状贴纸感。剩轻微项：溪中石暗片边缘稍硬（creek_low 视角）——记录项，不构成阻塞 |

ART07 其余用例维持 §9.3 结论；**A6 洞口机位仍需负责人人工复核**（固定机位 vision 判读反复），见 §8。

## 5. 对比板方法（14 张，相邻状态对比）

`Tools/make_art13_compare.ps1`：左=改前、右=改后，缩至 640×360 再拼（防 vision 8 MB 上限）。
**规则（S6 时实际踩过坑后固化）**：每块板的"改后"一律指向**该步的步骤快照** `Art/Probes/art13_steps/sN/`，**不指向** `art13_after/`——`art13_after` 永远是最新状态，用它当早先步骤的 after 会把后续步骤的改动混进对比（污染）。改前基线 = 相邻上一状态（S1 用 `art12_after/` = HEAD 提交态；S5 creek 两机位用 `art12_after/`，因 S3/S4 不含 creek 机位变化，相邻关系成立，脚本注释已注明）。

产物 `Art/Probes/art13_compare/`：cmp_s1×1、cmp_s2×2、cmp_s3×3、cmp_s4×3、cmp_s5×3、cmp_s6×2。步骤快照 `Art/Probes/art13_steps/s1~s6`（5/5/7/7/9/7 张），最终态 `Art/Probes/art13_after/`（庭院 7 机位）。

## 6. 终局回归（2026-11-03，全部 `Tools/CaptureRun.ps1 -Headless`，exit 均 0）

| 检查 | 结果 | 日志（`Art/Probes/.capture_logs/`） |
|---|---|---|
| `tool_make_courtyard.gd` 生成器自检 | **0 FAIL**；VERIFY 全 OK；`shadow_count_is_56`、decor nodes=47、static_bodies=20 | `tool_make_courtyard_20261103_102413.log` |
| `tool_make_courtyard_nav.gd` 导航重建 | mouse mesh **228** polys / cat mesh **180** polys（与基线一致）；nav `.tres` **无 diff** | `tool_make_courtyard_nav_20261103_102618.log` |
| `run_t011_greybox.gd` | **229/229** | `run_t011_greybox_20261103_102738.log` |
| `run_t012_navigation.gd` | **79/79** | `run_t012_navigation_20261103_102846.log` |
| `run_art09_frame_contract.gd` | **48/48** | `run_art09_frame_contract_20261103_102935.log` |
| `run_t020_perception.gd`（带 ART13 shader） | **164/164** | `run_t020_perception_20261103_102939.log` |
| `run_t026_cover.gd` | **96/96** | `run_t026_cover_20261103_103026.log` |
| `run_t027_ecology.gd` | **96/96** | `run_t027_ecology_20261103_103113.log` |

8 份日志 `SCRIPT ERROR` 扫描全为 0。帧契约日志尾部 5 条 `RID … leaked at exit` 是 headless 虚拟渲染器（RendererDummy）的引擎已知提示，自 2026-11-02 历次帧契约运行均存在（ART11/ART12 同样），非脚本错误。

## 7. T020 导航就绪竞态：调查与修复全记录

**现象**：带 ART13 shader 的改动跑 `run_t020_perception.gd` 出现 **6/8 次 FAIL**，而 HEAD shader 状态 **9/9 次 PASS**。失败断言漂移（F 段 17–20 项 / G2 段 3 项 / H 段 4 项不等），全部是 `reachable()=false` 类的导航可达性断言。

**排除相关性**：`ground.gdshader` 在失败段之前没有任何加载路径——仅被 `l_courtyard.tscn` / `l_ravine_board.tscn` 引用，套件只在 H 段才加载庭院关；autoload 干净。shader 改动与失败段无因果，**相关性只是时序扰动**（场景/资源加载时机被轻微改变）。

**真正机制（MEASURE 轮询确诊）**：
1. `bake_navigation_mesh` 的 region 更新是**异步提交**的；
2. **初烤偶尔几何不完整**——烘焙时夹具碰撞体尚未完全进入物理空间，导航网格缺夹具区域。诊断签名：轮询 `iter` 正常前进、`closest_dist` 恒 0.050、`path_size=0`、**240 帧稳定不自愈**；
3. 另实测：**每帧 `map_force_update` 会吞掉现烤 region 更新**（4/7 夹具 240 帧仍不就绪）——T012 的 force_update 模式只适用于**预烤**关卡，不能用于运行时现烤。

**修复**（`tests/run_t020_perception.gd`，`_await_nav_ready()`，约 769–805 行）：被动有界轮询 **240 帧**（就绪判据：`closest_dist ≤ 0.5 m` 且路径非空），期间**每 20 帧最多重烤 5 次**。用于 `_fresh_world` 的全部夹具（传 `_region`，可触发重烤）与 H 段关卡加载（只等待、不重烤）。**套件断言零改动**——修的是测试夹具的导航就绪等待，不是判定标准。

**验证**：修复后带 ART13 shader **连续 3 次 164/164 PASS**（日志 `run_t020_perception_20261103_{101650,101735,101820}.log`），MEASURE 显示 `frames=6~31`（重烤路径实际生效，非空转）；终局回归再跑 1 次 164/164（§6）。修复前最后一次 FAIL 留证：`run_t020_perception_20261103_101232.log`（164 checks / 17 failures）。

## 8. 遗留与移交

| 项 | 状态 | 说明 |
|---|---|---|
| ART07 **A6 洞口机位** | **待负责人人工复核** | 固定机位 vision 判读反复（§9.3），非本轮授权范围；ART07 因此维持 awaiting-review |
| 溪中石暗片边缘稍硬（creek_low 视角） | 记录项 | 不阻塞；若后续处理水岸资产时顺带 |
| `forest_floor` 三件套去留 | 待负责人 | ART11 遗留，本轮未动（边界要求保留） |
| tp 过曝 / 远景平铺 | **本轮收口** | ART11 §6 两项遗留由 S1/S2 处理，指针已回写 ART11 证据 |

## 9. 边界声明

未删 `menu_creek.png` / `forest_floor`；未做溪水折射焦散与菜单磨砂玻璃；未动猫鼠模型与动作；未改玩法/碰撞/导航层/鼠洞溪缝尺寸；未 push。取证全程 `Tools/CaptureRun.ps1`（隐藏桌面，零可见窗口）。
