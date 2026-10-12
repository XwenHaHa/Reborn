# 轮生 Reborn

Windows 单机、双物种、硬核生存切片。玩家在 **猫** 与 **鼠** 之间轮回：以猫的身份捕猎，以鼠的身份求生，死亡不是结束而是换一副身体继续。

> **当前状态：仅执行文档与环境发现，尚无游戏工程。**
> 本仓库目前**没有** UE 工程、没有代码、没有可运行的构建产物。已有的是一次完整的环境与工具能力发现，以及 T001～T063 的执行计划。
> 请不要把本仓库当作"可以 clone 下来就跑"的项目。

## 现在有什么

| 目录 | 内容 |
|---|---|
| `轮生_Reborn_游戏策划案_v1.1.md` | 产品规则（权威版本） |
| `轮生_Reborn_开发计划_v1.0.md` | T001～T063 任务范围与依赖 |
| `Docs/TechnicalDesign.md` | 蓝图资产路径、数据契约、事件与状态转换 |
| `Docs/Parameters.md` | 可直接采用的起测参数（速度/感知/消耗/资源容量） |
| `Docs/TestCases.md` | 可重复验收用例（E/M/S/I/A/L/W/D/R/B/U 系列） |
| `Docs/Tasks.md` | 任务状态与选择顺序 |
| `Docs/Tasks/Bootstrap.md` | T001～T007 启动批次规格 |
| `Docs/Environment.md` | 本机已验证环境与工具能力门 |
| `Docs/Commands.md` | 可复现命令（VERIFIED / PENDING 分级） |
| `Docs/Evidence/` | 逐任务的测试证据（命令、退出码、结果） |
| `Docs/Handoff.md` | 真实进度、阻塞与最小解除条件 |
| `Tools/Probes/` | 只读能力探针脚本 |
| `AGENTS.md` / `CLAUDE.md` | AI agent 执行入口与边界规则 |

## 进度实况

- **P0 能力链未通过。** T001 判 `blocked`：本机未发现 Unreal Engine，且 agent 侧无 UE 编辑器自动化通道。
- 已实测通过：Blender 3.3.1 无头 CLI（`--background --python`）。
- 未通过：UE 蓝图自动化、PIE 运行验证、打包、视觉分析（服务端 403）。
- T002～T063 全部 `pending`，无任何 PASS 的游戏用例。

细节与最小解除条件见 [`Docs/Handoff.md`](Docs/Handoff.md)。

## 环境要求（目标，尚未验证）

- Unreal Engine 5.4 / 5.5（蓝图优先；**不需要** C++ 工具链即可开始）
- Blender（资产制作；当前验证版本 3.3.1）
- Git + Git LFS（`.uasset` / `.umap` / `.blend` / `.fbx` 走 LFS — 见 T003，尚未配置）

## 边界声明

本仓库处于早期文档阶段，内容会随实测结果修正。文档中的能力描述均区分"已验证"与"未验证"；**未被实测通过的能力不会被写成已完成**。`Docs/Evidence/` 保留原始命令与退出码，包括失败与被作废的结论。
