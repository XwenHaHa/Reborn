# 开发交接：2026-10-13（引擎切换到 Godot 4 后）

## 真实状态

**引擎已变更**：原定 UE5 蓝图路线**废止**，改为 **Godot 4.7.2 + GDScript**（负责人 2026-10-13 决定）。

**已完成（有实测证据）**：

- 策划 v1.1、开发计划 v1.0（T001～T063 范围）、AGENTS/CLAUDE 入口、Environment、TechnicalDesign、Parameters、Tasks、Bootstrap、TestCases、BlenderPipeline 执行文档。
- T001 环境与能力门：软件版本、硬件与磁盘余量、UE 系统性定位（13 类证据源全否定）、Blender 无头 CLI 实测、视觉工具实测、agent 工具清点。
- **T004 Godot 能力实测**：纯文本手写工程/场景/脚本 → 无头执行 → 回读引擎真实状态（含 3D 物理体与碰撞尺寸）**闭环通过**。
- 仓库已建立并推送公开远端 `github.com/XwenHaHa/Reborn`（`main`，commit `e564cc8`）。

**未完成**：正式游戏工程、游戏实现、运行测试、打包、LFS 配置。**没有任何 PASS 的游戏用例。** T002～T063 全部 pending。

**本次未做**：未安装软件、未连接 MCP、未创建正式工程、未运行游戏测试。

## 关键进展：P0 的阻塞性质变了

| | UE5 阶段 | Godot 4 阶段（现在） |
|---|---|---|
| 核心卡点 | agent **无法创建/编辑编辑器资产**（`.uasset`/`.umap` 是二进制，必须有编辑器） | **已消除**——`.tscn`/`.tres`/`.gd`/`project.godot` 全是纯文本，agent 直接写 |
| 是否需要编辑器 MCP | 必需，且不存在 | **不需要**，命令行即闭环 |
| 引擎是否在位 | 未安装（三卷 484,201 目录 0 命中） | **已在位**，172.5 MB，实测 4.7.2 |
| 剩余缺口 | 引擎 + 自动化通道，二者缺一不可 | **仅导出模板未安装** |

**实测能力（`Docs/Evidence/T004.md`）**：`--headless`、`-s/--script`、`--check-only`、`--quit-after`、`--import`、`--export-release/debug/pack` 全部存在且可用；`--check-only` 经对照验证为可信静态门（真实抓到过写出的语法错误）；脚本创建的 `CharacterBody3D` + `CapsuleShape3D` 回读尺寸 16.0 cm / 48.0 cm，与 `Parameters.md` 的 Cat 胶囊一致。

## 关键环境事实（可直接采信）

- **Godot**：`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（**外层同名项是目录不是文件**，易误判为解压失败）；`--version` = `4.7.2.stable.official.ed1daf0bf`。
- **必须加 `--quit-after <N>`**：脚本加载失败时 `quit()` 不被调用，进程会挂死（已实测 180 s 超时）。
- **改脚本后先跑 `--check-only`**：静态语法检查，退出码可判定。
- **导出模板为空**：`%APPDATA%\Godot\export_templates\` 存在但无内容 → T007 阻塞。
- **Blender 3.3.1**：`D:\SoftWare\Blender\blender.exe`，无头 CLI 通过；出厂 `Cube` 是 **2 m** 不是 1 m；**Godot 建议用 glTF 而非 FBX**。
- **单位换算是本次切换最容易出错的地方**：UE 用厘米，**Godot 用米**，`Parameters.md` 全部数值需 ÷100。`CapsuleShape3D.height` 是**含两端半球的总高**（= 2×半高），半径 16 cm / 半高 24 cm → `radius=0.16`, `height=0.48`。
- **硬件**：i7-11800H / 31.75 GB / T600 Laptop 4 GB + Intel UHD / Win10 build 19045；C: 仅剩 **11.8 GB**，D: 159.5 GB，E: 227.6 GB。
- **Git 推送必须走代理**：直连 `github.com:443` 失败；用 `127.0.0.1:7897`，**未写入全局配置**。
- **视觉工具不可用**：`vision.js` 两次实测均 403（`An active OpenCode Go subscription is required`）→ 所有画面判断保持 NOT-RUN。

## 下一次从这里开始（需负责人先决策）

**必须先确认范围，再动 T002。** 待决事项：

1. **授权重写技术层文档**：`TechnicalDesign.md`、`Bootstrap.md`（T001～T007 改 Godot 版）、`Commands.md`、`Tasks.md`、`TestCases.md`。
   - 映射基准见 `Docs/Evidence/T004.md` §4.3（蓝图→GDScript、`.umap`→`.tscn`、`DA_*`→`Resource`、Enhanced Input→InputMap、cm→m 等）。
   - **不需要改**：策划案 v1.1（产品规则）、开发计划的任务编号与依赖结构、`Parameters.md` 的数值本身（换算单位即可）。
2. **安装 Godot 导出模板**（`4.7.2.stable`，约 1 GB）以解锁 T007。属下载第三方内容，需授权或自行安装。
3. **确认脚本语言**：默认 **GDScript**（无额外工具链）。改用 C# 需追加 .NET 配置，本机有 .NET 9 但会增加复杂度，**建议先用 GDScript**。
4. **T002 的目标形态**：建议改为 `Game/Reborn/project.godot` + `scenes/L_MovementLab.tscn` + 一个可跑的 `CharacterBody3D` 玩家，验收方式为**无头运行并输出断言**（而非 UE 的 PIE 视觉验收），这样 agent 可独立完成并留证据。

**先做 T003 的理由**：T002 产生的场景/脚本量很小，但一旦引入 Blender 资产（glTF/贴图）就会变大。`.gitattributes` + LFS 现在建立成本最低。

## 尚需确认或实测

- 视觉工具是否恢复（影响所有画面/比例/形变验收）。
- 导出模板安装后，实际导出与打包版启动是否成功（T007）。
- Godot 导入 Blender 资产的首选格式与单位换算，需 T005 实测确认。
- T600 4 GB 显存下 Godot Forward+ 的实际帧率（**P0 不测性能，P1 起再测**；不要现在宣称性能基线）。
- 每周投入与发行目标：**未提供，记为未知**，不阻塞、不编造。

## 本次操作边界声明

未安装/卸载任何软件；未连接 MCP；未创建正式游戏工程；未运行游戏测试；未改全局配置；未删除或覆盖任何源资产。
`Tools/Probes/GodotProbe/` 是**能力探针**，不是游戏工程，不纳入 T002 交付；其 `.godot/` 缓存已加入 `.gitignore`。
导出尝试**未产生任何输出文件**（已核实 `_export_probe.exe` / `.pck` 均不存在）。
Git 提交与推送**经负责人明确授权**后执行（负责人提供远端地址并指示提交）。

## 可直接发给下一个 agent

> 请在 E:/Reborn 工作。先读 AGENTS.md、Docs/Handoff.md、Docs/Environment.md、Docs/Evidence/T004.md、Docs/Commands.md。
> **引擎已改为 Godot 4.7.2（GDScript），UE5 路线废止**；技术层文档（TechnicalDesign / Bootstrap / Commands / Tasks / TestCases）**仍是 UE5 版、尚未重写**，动手前必须确认范围，不要把两套说法混用。
> 关键工具：`E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（外层同名项是目录）。
> 无头运行**必须**加 `--quit-after <N>`，否则脚本出错会挂死。改脚本后先跑 `--check-only` 静态检查。
> Godot 用**米**，Parameters.md 是**厘米**，参数需 ÷100。`CapsuleShape3D.height` 是含半球的总高。
> 已知阻塞：导出模板未安装（T007）；vision 服务 403（所有视觉验收 NOT-RUN，**不得编造画面判断**）；Git LFS 未配置。
> 不要在没有实测证据时把任何游戏任务标为 done。
