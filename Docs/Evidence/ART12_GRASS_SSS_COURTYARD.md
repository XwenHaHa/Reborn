# ART12 证据：草透光/次表面观感 + 庭院草带成带（2026-11-02）

任务规格：`Docs/Tasks/ART12_GRASS_SSS_COURTYARD.md`（C 阶段，负责人 2026-11-02 批准）。
基线：ART07 收口提交 `1caa7be` + ART11 提交 `d0f33ed` 之后的工作区状态。

## 1. 变更范围

| 文件 | 改动 |
|---|---|
| `Game/Reborn/shaders/grass_wind.gdshader` | fragment 新增 `BACKLIGHT` 透光近似（廉价 SSS，零贴图）；两个 uniform：`sss_tint=vec3(0.55,0.72,0.28)`、`sss_strength=0.55`；梢部透光多根部少：`k = sss_strength * (0.30 + 0.70 * smoothstep(0.25, 1.0, v_h_norm))` |
| `Game/Reborn/tests/tool_make_courtyard.gd` | `SCENERY_BUSHES_FILL` 6→14 株（北墙中部 4 株补 26 m 空档、西墙 2 株、东墙 2 株；坐标/yaw/尺度见任务规格 §2.2）；自检 `shadow_count_is_39` |
| `Game/Reborn/scenes/maps/l_courtyard.tscn` | 生成器重建（39 阴影 / 24 草簇） |
| `Game/Reborn/tests/run_t011_greybox.gd` | §G 计数同步（Fill 14、decor_shadow_count==39） |

不碰玩法/碰撞/导航/鼠洞溪缝尺寸/猫鼠模型/危险区/掩体；新增草簇零碰撞、不进
`nav_source_courtyard`、不进 `danger_zones`（生成器自检断言兜底）。

## 2. 回归（全部经 `Tools/CaptureRun.ps1 -Headless`，2026-11-02）

| 用例 | 结果 | 日志 |
|---|---|---|
| U1 生成器自检 | 全 `VERIFY|...|OK`（39 阴影/草簇计数、危险区/掩体距离/导航组断言） | `tool_make_courtyard` 运行日志（17:0x 前批次） |
| U2 T011 | **229/229 PASS**（§G 计数同步后） | `run_t011_greybox_20261102_170351.log` |
| U3a T012 | **79/79 PASS** | `run_t012_navigation_20261102_170458.log` |
| U3b 帧契约（shader 两关共用） | **48/48 PASS**（RID 泄漏告警为 headless 退出既有噪声） | `run_art09_frame_contract_20261102_171016.log` |
| U4 nav 重烤 | `resources/nav/*.tres` 与改前无 diff（本会话早前批次已验，17:0x 复核 T012 通过佐证） | — |

注：T011/T012/帧契约均在本轮 `project.godot` 加入 `CaptureWindowGuard` autoload 之后复跑
（autoload headless 下 `_ready` 直接 return，零副作用——回归全绿即为佐证）。

## 3. 取证（全部经 `Tools/CaptureRun.ps1`，用户桌面零可见窗口）

改后帧 `Art/Probes/art12_after/`（16:25 前后拍摄，save_result 全 OK）：

- 庭院 `tool_capture_render.gd -- t011` 7 帧；
- 溪区 `tool_capture_creek.gd -- creek` 3 帧（creek_wide_a/b + creek_low_a；water motion 0.0316/45 帧，非黑）；
- 展板关 `tool_capture_art09_board.gd -- ravine` 4 帧（共用 shader 的透光收益）。

改前基线：`art07_after/`（15:17）与 `art11_ground_after/`（16:08），场景状态与提交基线一致。
对比板：`Art/Probes/art12_compare/` 6 张（`Tools/make_art12_compare.ps1` 生成，640×360×2 拼接）。

## 4. vision 前后判读（`node vision.js`，左=改前 右=改后）

| 对比图 | 结论 | 分 |
|---|---|---|
| cmp_t011_map_overview | 草微亮有通透感、灌木围合更完整、无异常；俯视下变化细微 | 7/10 |
| cmp_t011_courtyard | 草透光可感知（黄绿边缘提亮）、墙根灌木围合连贯、无异常 | 8/10 |
| cmp_t011_grass_danger | 迎光叶尖明显微亮、体积感更强、**无过曝**（"最亮叶尖仍是黄绿"） | 8/10 |
| cmp_creek_wide | 草和芦苇叶尖透光、比左侧扁平暗沉更显生动、无泛白 | 8/10 |
| cmp_ravine_env_creek | 黄绿次表面散射、体积感和层次提升、无白色溢出 | 8/10 |
| cmp_ravine_tp | 透光自然、无穿帮；**唯一提示**：部分迎光叶尖"接近泛白"（轻微） | 8.5/10 |

U5 判据核对：①逆光草叶透亮（黄绿）不再哑光——6/6 确认；②墙脚草带连续性提升——
map_overview/courtyard 确认；③无新穿帮——6/6 无异常（仅 ravine_tp 特写有一处"接近泛白"
的轻微提示，其余 5 视图明确无过曝）。

### 参数维持决定

`sss_strength=0.55` 维持不动：6 个视图里 5 个明确"无过曝"、1 个（grass_danger）甚至判读
"再强一点点更出彩"，唯一反例是 ravine_tp 特写的**接近**泛白（非实际溢出）。两向证据冲突、
幅度轻微，按"没有依据时不随机改系统"不调参。

**终审结论（负责人 2026-11-02）：`sss_strength` 定为 0.55。** 0.45 降级为纯记录项
（不再作为待执行备选，不往复调整）；后续若负责人在展板复核中认为特写过亮，再按
参数登记流程（旧值/新值/原因/测试）重新提出。

## 5. 取证工具链（窗口零可见）

本轮取证期间完成"整条链路零可见窗口"最终解（负责人三次反馈）：非 headless 取证默认在
自建隐藏桌面（`winsta0\RebornCapture`）上启动，两次连跑 `visible_hits=0`、截图非黑、
vision 通过。调查全过程与证据见
`Docs/Evidence/ART07_ENVIRONMENT_COMPOSITION_CONTACT.md` §9.4 三次反馈补记与
`Tools/README.md`。

## 6. 结论

- U1–U4（生成器/回归/导航契约）全绿；U5 视觉判读通过（7–8.5/10，无新穿帮）。
- ART10 FAIL 项"草与暖光融合"与 ART07 A5 部分项"草带未成带"在本轮证据下均获改善，
  终审归属负责人展板复核。
- 状态：**awaiting-review**（视觉改善轮，与 ART07/ART10 同类——回归可自动验证的部分
  已全绿，观感终审需负责人过目 `Art/Probes/art12_compare/` 6 张对比板）。

## 7. 未验证与遗留

- 远景草簇像素化是分辨率根本限制（ART07 已记录），本轮不再加密。
- ravine_tp 特写"迎光叶尖接近泛白"：轻微，维持参数（见 §4 参数维持决定），留待终审。
- 隐藏桌面模式的长期稳定性（多显示器/锁屏/驱动差异）只在本机验证过；如遇截图异常，
  用 `-VisibleDesktop` 诊断开关对照（该模式窗口会先可见 ~1.7 秒，仅诊断用）。

## 8. 恢复入口

- shader 单文件 revert（两关共用，回退后重拍即可）；
- 草簇：`tool_make_courtyard.gd` 常量表回退（14→6）后重跑生成器 + nav 重烤；
- T011 §G 计数随生成器常量同步回退。
