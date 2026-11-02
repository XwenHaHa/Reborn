# ART13：A5/A7 收口轮 2 + tp 过曝与远景平铺遗留清理（2026-11-02）

状态：in-progress

## 0. 背景与授权

负责人 2026-11-02 批准"按任务继续执行"：
1. `sss_strength` 定为 0.55，0.45 降级为记录项（ART12 证据补终审结论）；
2. 收遗留：展板关 tp **中心过曝**（只动辉光/曝光/tone mapping，不动已判 PASS 的光照方向）；
   **远景贴图平铺感**（先判断 triplanar 能否低成本落在 `ground.gdshader`，不能则说明原因与替代方案）；
3. 主攻 ART07 **A5/A7**：在现有资产与引擎能力内逐项试（每改一项同机位复判），
   目标判到可验证 PASS；确实做不到的如实写卡点与最小解除条件，不拿调参掩盖。

不做：删 `menu_creek.png`/`forest_floor`、溪水折射焦散、菜单磨砂玻璃、猫鼠模型与动作、
玩法/碰撞/导航/鼠洞溪缝尺寸；不 push。取证一律走 `Tools/CaptureRun.ps1`（隐藏桌面）。

## 1. 目标路径

| 文件 | 改动 | 可回退 |
|---|---|---|
| `Docs/Evidence/ART12_GRASS_SSS_COURTYARD.md` | §4 补终审结论（0.55 定案） | 文档 |
| `Game/Reborn/tests/tool_make_ravine_board.gd` | tp 过曝：exposure/glow 阈值；地面换双尺度贴图材质 | 常量/材质块回退后重跑生成器 |
| `Game/Reborn/shaders/ground.gdshader` | 可选贴图路径（世界坐标双尺度混合，默认 `tex_amount=0` 行为不变） | 单文件 revert（既有使用者零影响） |
| `Game/Reborn/tests/run_art09_frame_contract.gd` | `_check_textured` 扩展接受"带贴图的 ShaderMaterial"（契约意图不变：地面必须有贴图） | 独立断言 |
| `Game/Reborn/tests/tool_make_courtyard.gd` | 庭院地面接 leafy_grass；结构接地阴影（棚柱/棚内地坪/根障基座/围栏基脚）；溪岸湿泥带；远景深度雾开启 | 常量表回退 + 生成器重建 |
| `Game/Reborn/tests/run_t011_greybox.gd` | §G 计数同步（阴影数、湿泥带进 want_decor） | 独立断言 |

## 2. 数据/事件（参数登记）

### 2.1 展板关 tp 过曝（只动后处理层）

| 参数 | 旧值 | 新值 | 依据 |
|---|---:|---:|---|
| `tonemap_exposure` | 1.05 | 0.92 | ACES 曝光整体回压，中心高光收进滚降区 |
| `glow_hdr_threshold` | 1.15 | 1.30 | 辉光只保留更强高光，减少中心泛白叠加 |

### 2.2 ground.gdshader 可选贴图路径（新 uniform，默认值即初值）

| 参数 | 初值 | 说明 |
|---|---|---|
| `tex_amount` | 0.0 | 0=纯程序化（既有使用者零变化）；1=贴图为主 |
| `tex_albedo/tex_normal/tex_arm` | null | 复用已入库 CC0 贴图（leafy_grass） |
| `tex_scale_a` | (0.52, 0.52) | 主尺度（tile≈1.9 m，展板关原平铺密度） |
| `tex_scale_b` | (0.185, 0.185) | 第二尺度（tile≈5.4 m）+ 相位错开 |
| `tex_noise_scale` | 0.06 | 双尺度混合噪声频率（~17 m 一变） |
| `tex_tint` | (1,1,1) | 庭院 (0.88,0.92,0.80) / 展板 (0.82,0.88,0.74) |

triplanar 判定（负责人问题 2 的答案，先写结论后实施）：
`ground.gdshader` 是世界坐标程序化噪声，**本身没有 UV 平铺可治**；平铺感来自展板关
StandardMaterial3D 的 UV 平铺。在**纯平地**上 triplanar 不改变重复频率（重复由 tile 尺寸
决定），只消除曲面/多面投影拉伸 → **不能解决平地远景平铺感**。低成本替代 = 同一贴图
两个尺度 + 世界坐标低频噪声互混（打破周期），落在 `ground.gdshader` 的可选贴图路径里，
不新增资产、不新增管线。

### 2.3 庭院结构接地阴影（复用 `_mk_ground_shadow` 机制，+9 块 → 阴影总数 48）

棚柱×2、棚内地坪×1（alpha 0.10）、根障基座×2（alpha 0.14）、围栏基脚×4（alpha 0.10）。
全部零碰撞、不进导航组、名字带 Shadow 进计数断言。

### 2.4 溪岸湿泥带 + 溪中石接地（+2+6 → 阴影总数 56）

湿泥带 4 段（每侧 2 段，缝口 x∈[-33.3,-30.1] 留空，保住"缝口两侧空地"可读性），
unshaded 半透明暗棕（alpha 0.30，径向渐变），贴地 0.107。溪中石脚下暗片×6（水下
接地，读作"泡在水里"）。湿泥带进 T011 want_decor。

### 2.5 远景深度雾（A5 空气透视，ART07 证据 §9 已实测的备选方案）

`fog_enabled=true`（DEPTH 80→170 m、sky_affect=0 不动），`fog_light_energy`
0.75→0.45、颜色压暗到 (0.50,0.55,0.62)——上一轮判"整屏灰白"的头号嫌疑是雾光能量，
先压它。T011 `decor_fog_is_far_depth`（begin≥60）本就允许。若 vision 仍判灰幕 →
回退为关闭并如实记录。

## 3. 步骤（每步：改 → 重建 → 同机位取证 → vision 复判，一次一项）

1. ART12 证据补终审结论（纯文档）；
2. S1 tp 过曝 → 重建展板关 → `tool_capture_art09_board.gd -- ravine` → vision；
3. S2 shader 双尺度 + 展板关地面换材质 + 契约测试扩展 → 重建 → tp/far 帧 → vision（平铺感）；
4. S3 庭院地面贴图 → 重建庭院 + 重烤导航 → `tool_capture_render.gd -- t011` → vision；
5. S4 结构接地阴影 → 重建 → t011/roots_barrier 帧 → vision；
6. S5 湿泥带 + 溪中石暗片 → 重建 → creek/t011 帧 → vision；
7. S6 深度雾 → 重建 → overview/courtyard 帧 → vision（同时查"灰幕是否回来"）；
8. 回归：两生成器自检、T011（计数同步）、T012（nav 重烤后）、帧契约 48、
   T020/T026/T027（庭院场景重建涉及）；
9. 证据（`Docs/Evidence/ART13_A5A7_ROUND2.md`）+ Tasks.md + Handoff.md 同提交。

## 4. 用例

| 用例 | 判据 |
|---|---|
| U1 tp 过曝 | vision：过曝收住且暗部/中景细节没有被压死 |
| U2 平铺感 | vision：远景平铺重复/拼接感减弱，近景观感不劣化 |
| U3 庭院地表 | vision：地表有细节、与草丛割裂感降低；草土区域感仍在 |
| U4 接地 | vision：棚柱/根障/围栏/溪中石"坐住"地面；无新穿帮 |
| U5 水岸 | vision：水岸硬切/矩形感减弱；无"黑线"倒退 |
| U6 A5 雾 | vision：远景更淡有空气透视、**整屏无灰白雾幕** |
| U7 回归 | 生成器自检、T011、T012、帧契约 48、T020/T026/T027 全绿 |

## 5. 失败恢复

- 任一步 vision 判劣化 → 回退该步常量/材质块，重跑生成器，不改其它步；
- shader 贴图路径异常 → `tex_amount=0` 即回到现行为（既有使用者零影响）；
- 雾判灰幕 → `fog_enabled=false` 回退（参数已保留）；
- 全部可回退：生成器常量表 + 单文件 revert + 生成器重建（ART07 证据 §8 恢复入口）。
