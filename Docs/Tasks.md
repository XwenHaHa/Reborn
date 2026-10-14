# 任务状态与执行入口

截至 **2026-10-13（引擎切换 Godot 4 后）**：

- **引擎已由 UE5 改为 Godot 4.7.2 + GDScript**（负责人决定）。技术层文档已重写为 Godot 版。
- **T001 = done（Godot 版）**：环境与引擎能力门通过。
- **T002 = done**（视觉部分 awaiting-review）：正式工程建立，无头断言 **18/18 通过**，10 次运行（5 冷启动 + 5 热运行）结果一致。
- **T003 = done**：LFS 生效；**从零克隆的工程可被引擎实际运行**（18/18 通过）。
- **T004 = 部分 done**：Godot 无头闭环实测通过；Blender 资产侧未开始。
- **T005 = done**（静态资产往返）、**T006 = done**（骨骼往返）、**T007 = done**（Windows 导出），均在 2026-10-13。
- T008～T063 全部 pending。**游戏测试除 E01 部分外全部 NOT-RUN，无 PASS 的游戏玩法用例。**

**能力门现状**：Godot 无头运行、`--check-only`、物理体创建与回读**已通过**；
**Windows 导出已解锁并通过**（T007 done）；**Blender 无头 CLI + glTF 资产往返已通过**（T005 done）；
视觉分析可用，已用于 T002/T005/T007 的视觉验收。

**P0 阶段门**：E01 部分通过；**打包通过**（T007）；**E02（静态资产往返）通过**（T005）；**E03（骨骼往返）通过**（T006）→
**P0 完成**（E01 的视觉部分已由 Visual-Verification 补验）。

## 状态规则

pending 未开始；in-progress 正在执行；blocked 有明确前置缺口；awaiting-review 产物已生成但必需验收未做；done 必需验收和证据全部通过。任一任务状态改变，在下表新增覆盖记录，**不删除原历史**。总计划是任务标题和依赖的基准；后续规格不能偷偷扩大产品范围。

## 当前覆盖记录

| 任务 | 状态 | 已有证据 | 下一步 |
|---|---|---|---|
| T001 | **done（Godot 版）** | `Docs/Evidence/T001.md`（环境/硬件/UE 定位）；`Docs/Evidence/T004.md`（Godot 能力） | 已完成 |
| T002 | **done** | `Docs/Evidence/T002.md`；`Visual-Verification.md` | 无头断言 18/18 ×3；**视觉已补验通过**（发现并修复场景无光源缺陷） |
| T003 | **done** | `Docs/Evidence/T003.md`；提交 `b7767ca`、`611a55b` | LFS 生效 + 从零克隆可运行工程（18/18 通过） |
| T004 | **done**（路线决策） | `Docs/Evidence/T004.md`、`BlenderPipeline.md` | **路线已定：用 Blender 自带无头 CLI，不用 MCP**；资产侧并入 T005 |
| 台阶探针 | **done**（T009/T010 前置） | `Docs/Evidence/T009-probe.md`；`tests/probe_step_height.gd` | 6/6 通过；算法已组件化（`scripts/characters/step_climb.gd`）；T009 期间修正两处判据，见 `Docs/Evidence/T009.md` §5 |
| T005 | **done** | `Docs/Evidence/T005.md`；`Docs/Tasks/T005.md`；`Game/Reborn/tests/run_t005_asset.gd`；`Art/Exports/Tests/SM_ProbeCube.glb` | 1 m 往返实测 1.0000 m（50/50 ×3、包内 50/50）；轴向由实测改正文档；运行中碰撞高度差 1.0001 m |
| T006 | **done** | `Docs/Evidence/T006.md`；`Docs/Tasks/T006.md`；`Game/Reborn/tests/run_t006_rig.gd`；`Art/Exports/Tests/SK_RigProbe.glb` | 骨骼往返 65/65 ×3 + 包内 65/65；长度 1.0 s、loop_mode=LOOP_LINEAR、首末闭合 0.000；无根运动/无根骨缩放 |
| T007 | **done**（真实按键 awaiting-review） | `Docs/Evidence/T007.md`；`Builds/P0-Win64/` | 导出/独立运行/干净退出/重启/视觉均通过 |
| T008 | **done** | `Docs/Evidence/T008.md`；`Docs/Tasks/T008.md`；`scripts/data/species_config.gd`；`resources/species/{cat,mouse}.tres`；`scripts/characters/animal_body.gd` + `scenes/characters/animal_body.tscn`；`tests/run_t008_species.gd` | 台阶组件化 + 配置逐字段对照 `Parameters.md`；**配置驱动的物理实测**：猫 12 cm 上/20 cm 挡、鼠 3 cm 上/12 cm 挡；**114/114** ×2、包内 103/103（T009 补了蹲姿/相机轴向断言） |
| T009 | **done（2026-10-13）** | `Docs/Evidence/T009.md`；`Docs/Tasks/T009.md`；`tests/run_t009_cat_movement.gd`；`scenes/maps/l_move_fixtures.tscn`（+`tests/tool_make_move_fixtures.gd`）；`Art/Probes/t009_*.png` | 猫移动：行走/奔跑/潜伏/跳跃 + 相机；斜坡/低顶/落地/相机穿墙全过；**81/81** ×3 + 包内 81/81；lab 玩家已换成正式猫（T002/T005/T006/T007/T008 回归全绿）；过程中修掉 `step_climb` 两处真实判据缺陷 |
| T010 | **done（2026-10-13）** | `Docs/Evidence/T010.md`；`Docs/Tasks/T010.md`；`tests/run_t010_mouse_movement.gd`；`scenes/maps/l_move_fixtures.tscn`（新增鼠洞 + 鼠低顶）；`Art/Probes/t010_*.png` | 鼠移动与通道尺度：**站立**过 24×30 cm 洞、猫（站/蹲）都过不去、禁高跳（`can_jump=false`）、0.15 m 低顶下不扩碰撞；**95/95** ×3 + 包内 95/95；**gameplay 代码零改动**（差异全在 `mouse.tres`） |
| T011～T063 | pending | 无 | **T011（搭建生态灰盒）前置已满足**：移动/台阶/试验世界与两套工具就绪；先写 `Docs/Tasks/T011.md` |

### T001 判定明细（Godot 版）

| 验收项 | 判定 |
|---|---|
| 读取路径与实际工具列表 | PASS |
| 只读检查版本、硬件与余量 | PASS |
| 定位引擎可执行文件与版本 | PASS（Godot 4.7.2；UE 未发现，已由负责人决策换引擎） |
| 最小场景操作 + 运行验证 | PASS（纯文本手写工程 → 无头运行 → 回读状态） |
| 建立工具能力表 | PASS |
| 不擅自更改技术路线 | PASS（换引擎是负责人决策，非 agent 擅自变更） |

### T002 / T003 判定明细

| 验收项 | 判定 | 证据 |
|---|---|---|
| T002 工程可被引擎加载运行 | PASS | `RESULT\|PASS`，退出码 0 |
| T002 无头断言 | PASS | 18/18，10 次运行（5 冷 + 5 热）一致 |
| T002 地面 1000×1000 cm | PASS | 读回 `BoxShape3D.size` = 10.0000 m |
| T002 出生点无碰撞重叠 | PASS | `intersect_shape` 实测 0 overlaps |
| T002 落地与停止 | PASS | `is_on_floor=true`，落点 y=0.3402（期望 0.34） |
| T002 视觉 | **awaiting-review** | vision 服务 403，未做画面判断 |
| T003 `.gitattributes` + LFS 生效 | PASS | 指针/实体/SHA256 三重验证 |
| T003 **恢复点** | PASS | 从零克隆后引擎实跑 18/18 通过 |

关联用例：**E01 部分 PASS**（工程可加载、脚本保留、无 `SCRIPT ERROR`、`--check-only` 退出码 0）；
E01 的视觉部分**已补验通过**；**E02 本次通过**（`Docs/Evidence/T005.md`）；**E03 已通过**（T006 骨骼往返 65/65）。

## 选择顺序

T001 / T002 / T003 / T005 / T006 / T007 / T008 / T009 / **T010 均已完成**；台阶能力已组件化并修掉两处判据缺陷。
**P0 阶段门完成**；**P1 进行中**（T008/T009/T010 完成 → 下一步 **T011 生态灰盒**）。

下一步可执行（按建议优先级）：

1. **T011（搭建生态灰盒）**：四个简化区域、高台、鼠洞、风险近路、安全绕路与补给位置
   （前置 T009/T010 已满足）。**先写 `Docs/Tasks/T011.md`**。
2. **T012 / T013**：导航可行性（猫/鼠的导航代理尺寸、猫不能进鼠洞）与调试入口 + 移动回归。
   注意 T013 的移动回归里带上遗留项：**单级台阶抬升会水平前移 0.2 m**（`Docs/Evidence/T009.md` §5.3）。
3. ~~T005 / T006 / T007 / T008 / T009 / T010~~ **已完成**。
2. **T011～T013**（生态灰盒 / 导航可行性 / 调试入口与移动回归）。
   注意 T013 的移动回归里带上一条遗留项：单级台阶会前移 0.2 m（`Docs/Evidence/T009.md` §5.3）。
3. ~~T005 / T006 / T007 / T008 / T009~~ **已完成**。

**做角色资产时必须遵守 T005/T006 实测的两条约定**：
① 在 Blender 里**面朝 `+Y`**（导入 Godot 后才朝 `-Z` 前方）；
② 骨骼动画**原地、无根运动**；导入会让极值削减约 1–2%（见 T006 证据 §3.2）。

**T006 已解除，不再阻塞**：骨骼链往返已被实测证明，正式骨骼资产可以开始（但仍属 P6，需按阶段门排期）。
T028 若只有自测，则 awaiting-review，不冒充真实玩家验证。

P4 前先阅读 TechnicalDesign 数据契约，T036 是契约实现检查与持久化准备，不是首次想数据结构。

## 当前阻塞与最小解除条件

| 阻塞 | 影响 | 最小解除条件 |
|---|---|---|
| ~~Godot 导出模板未安装~~ | ~~T007~~ | **已解除** |
| ~~技术层文档仍是 UE5 版~~ | ~~T002 起~~ | **已解除** |
| ~~台阶 MaxStepHeight 能力未达成~~ | ~~T009/T010~~ | **已解除**（6/6 通过） |
| ~~vision 服务 403~~ | ~~全部视觉验收~~ | **已解除**（换用负责人提供的网关并验证；T002/T007 视觉已补验通过） |
| ~~Blender 资产路线未定~~ | ~~T005/T006~~ | **已解除**（负责人决定：用 Blender 3.3.1 自带无头 CLI） |
| 真实按键输入无安全自动化手段 | T007 的"输入"项、P7 试玩 | 受审查的输入自动化工具（**需授权**），或真人操作录像。**禁止盲发按键**；合成输入已覆盖 |
| C: 仅剩 13.7 GB | 产物落盘 | 确认工程与产物落 D:/E: |
| Godot 渲染器（T600 4GB 能否跑 Forward+） | P1 起的画质与性能 | 渲染器**已确认可用**（T009 捕获工具实测 `renderer=forward_plus`、1280×720 正常出图）；**帧率仍未测**，不宣称性能基线 |
| 相机轴语义 D1 / 蹲姿高度 D2 待确认 | T010 起沿用同一套实现 | 负责人确认即可（改回只需改一行实现 + 1 条断言，见 `Docs/Evidence/T009.md` §4/§9） |
| 台阶抬升会前移 0.2 m（单级"跳一下"的手感） | 关卡手感与窄台阶（T011/T013） | 改成"只抬起 y、由 `move_and_slide()` 推进"，并重跑 T008/T009 断言 |

> ## ⚠ 一条重要教训（2026-10-13）
>
> **数值断言全过 ≠ 画面正确。** T002 的 18 条断言长期全绿，但场景**完全没有光源、
> 没有环境、相机未激活**，导出程序窗口是一片深色空白。视觉检查一接入就发现了。
> 今后任何"画面正确"的结论都必须有视觉证据，见 `Docs/Evidence/Visual-Verification.md`。

## 后续单任务规格格式

路径 `Docs/Tasks/Txxx.md`。包含：任务目标、必须通过的前置及证据、创建/修改的真实路径、现有对象检查、所用参数版本、接口/状态转换、逐步实现、对应 TestCases 步骤及预期、失败回退、所需确认事项。

每个开始任务最多细化一个可验证增量。未知工具签名先查真实工具，**不写伪 API**。资源或场景新建后**保存重开验证**。任何产物不存在就写"待创建"，不得引用成现有文件。

## 证据格式

`Docs/Evidence/Txxx.md`：实际日期/工具版本、操作或命令、**退出码**、资产路径、用例预期与实际、PASS/FAIL/NOT-RUN、图像/录像/日志路径、已知限制、恢复位置。**不包含密钥与完整个人配置。**

只有日志中的成功信息不能代替交互、视觉或存档实际验证。完成后同步 Handoff，列出最早可执行任务与阻塞。

**Godot 特有要求**：无头运行的证据必须包含实际 stdout（`ASSERT|` 行）与退出码，不能只写"运行成功"。视觉未验证的部分标 `awaiting-review`，**不得因无头断言通过就宣称画面正确**。
