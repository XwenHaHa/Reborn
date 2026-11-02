# ART12：草透光/次表面观感 + 庭院草带成带（C 阶段，2026-11-02）

状态：awaiting-review（U1–U4 全绿、U5 vision 通过；终审见
`Docs/Evidence/ART12_GRASS_SSS_COURTYARD.md` §6）

## 0. 背景与授权

负责人 2026-11-02 批准的主线第三轮（C 阶段）："shader 和关卡解冻后，再做一轮草的
透光/次表面观感与庭院构图，独立前后对比 + vision 判读，写进独立的 ART10 后续证据。"
`grass_wind.gdshader` 与 `l_courtyard.tscn` 已随 ART07 收口提交（`1caa7be`）解冻。

要解决的两个既有判读失败项：

1. **ART10 FAIL「草与暖光融合」**（展板关侧逆光下草是哑光色块，不透光）；
2. **ART07 A5 部分通过「草带未成带」**（收口轮 vision：北墙脚草簇"仍点状散落"，
   北墙中部 -13.2～+13.4 有 26 m 空档，东西墙各有一段 11～16 m 空档）。

## 1. 目标路径

| 文件 | 改动 | 可回退 |
|---|---|---|
| `Game/Reborn/shaders/grass_wind.gdshader` | fragment 加 `BACKLIGHT` 透光近似（廉价 SSS） | 单文件 revert（两关共用，回退后重拍即可） |
| `Game/Reborn/tests/tool_make_courtyard.gd` | `SCENERY_BUSHES_FILL` +8 株补墙脚空档；自检 `shadow_count_is_31`→39 | 常量表回退后重跑生成器 |
| `Game/Reborn/scenes/maps/l_courtyard.tscn` | 生成器产物 | 重建 |
| `Game/Reborn/tests/run_t011_greybox.gd` | §G 计数同步（Fill 6→14、阴影 31→39） | 独立断言 |

**不碰**：玩法/碰撞/导航/鼠洞溪缝尺寸/猫鼠模型/危险区/掩体；新增草簇全部零碰撞、
不进 `nav_source_courtyard`、不进 `danger_zones`（自检有断言兜底）。

## 2. 数据/事件（参数登记）

### 2.1 shader 透光（新增 uniform，默认值即初值）

| 参数 | 初值 | 说明 |
|---|---|---|
| `sss_tint` | `vec3(0.55, 0.72, 0.28)` | 透光色：叶绿素透射偏黄绿 |
| `sss_strength` | `0.55` | 透光强度（BACKLIGHT 项系数） |

梢部（薄）透光多、根部（厚）几乎不透：`k = sss_strength * (0.30 + 0.70 * smoothstep(0.25, 1.0, v_h_norm))`。

### 2.2 墙脚草簇加密（SCENERY_BUSHES_FILL 6 → 14）

| 新增 # | pos (x, z) | yaw | s | 补的空档 |
|---|---|---|---|---|
| 6 | (-8.5, 28.2) | 88 | 0.72 | 北墙中部 |
| 7 | (-3.0, 27.8) | 152 | 0.70 | 北墙中部 |
| 8 | (2.5, 28.3) | 26 | 0.74 | 北墙中部 |
| 9 | (8.0, 27.9) | 214 | 0.71 | 北墙中部 |
| 10 | (-34.2, -16.2) | 300 | 0.70 | 西墙 -24.0～-8.4 |
| 11 | (-34.1, -3.2) | 68 | 0.72 | 西墙 -8.4～2.8 |
| 12 | (34.2, -16.0) | 112 | 0.72 | 东墙 -24.2～-8.0 |
| 13 | (34.1, -2.8) | 246 | 0.70 | 东墙 -8.0～3.0 |

尺度全部 ≤0.74（明显小于掩体草 1.00，不读成"假掩体"）；北墙中部株 z≈28 在
`danger_zones`（z∈[-22,2]）之外。

## 3. 步骤

1. 改 shader（透光）→ 改生成器（草簇 + 计数）→ 改 T011 §G 计数；
2. 重跑 `tool_make_courtyard.gd`（生成 + 自检）→ `tool_make_courtyard_nav.gd`（重烤导航，
   检查 `resources/nav/*.tres` 无 diff）；
3. 回归：生成器自检、T011、T012、`run_art09_frame_contract`（shader 两关共用，48 条）；
4. 取证（全部走 `Tools/CaptureRun.ps1`，零窗口）：庭院 `tool_capture_render.gd -- t011`
   7 帧 + `tool_capture_creek.gd -- creek` 4 帧；展板关 `tool_capture_art09_board.gd -- ravine`
   （共用 shader 的透光收益）；改前基线 = ART07 收口帧（`art07_after/`，15:17）与
   ART11 帧（`art11_ground_after/`，16:08），场景状态与 HEAD 完全一致；
5. vision 前后判读（草透光/插片感/草带连续性）；允许最多两轮有依据的参数修正；
6. 证据 + Tasks.md + Handoff.md 同提交。

## 4. 用例

| 用例 | 判据 |
|---|---|
| U1 生成器自检 | 全 `VERIFY|...|OK`（含新增 8 株的危险区/掩体距离/导航组断言） |
| U2 T011 回归 | 全绿（§G 计数同步后） |
| U3 T012 / 契约 | T012 导航全绿；`run_art09_frame_contract` 48/48（共用 shader 无回归） |
| U4 nav 烤焙 | `resources/nav/*.tres` 与改前无 diff |
| U5 视觉 | vision 前后对比：逆光草叶透亮（黄绿）不再哑光；墙脚草带连续性提升；无新穿帮 |

## 5. 失败恢复

- shader 透光判读"过头/像发光塑料" → 降 `sss_strength`（0.55→0.35）或收窄 smoothstep，
  重拍复判；仍不行则 revert shader 单文件（草带加密不受影响）。
- 草带加密判读"仍点状" → 记录为遗留（远景像素化是根本限制），不继续加株。
- 生成器/T011 计数不一致 → 以数组实际 size 为准同步两处常量。
- 全部可回退：常量表 + 单文件 revert + 生成器重建（见 ART07 证据 §8 恢复入口）。
