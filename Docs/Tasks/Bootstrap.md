# 启动批次执行规格：T001～T007（Godot 4 版）

> **v0.2（2026-10-13）**：引擎由 UE5 改为 **Godot 4.7.2 + GDScript**（负责人决定）。原 UE 版规格废止。
> Agent 逐任务执行，遵循 AGENTS.md；本批次不启动正式动物建模或商业发行。本文只定义实施与验证，不宣称命令/接口已存在。
> 已验证的引擎能力见 `Docs/Evidence/T004.md`；命令见 `Docs/Commands.md`。

**Goal：** 验证 Godot + Blender 可形成可运行、可打包、可恢复的生产链。
**Architecture：** Godot 工程（纯文本场景与脚本），真实无头命令行驱动，独立 Blender 测试场景，Windows 导出。
**Tech Stack：** Godot 4.7.2（GDScript）、Blender 3.3.1、Python 3.13、Node 22、Git 2.42 + LFS 3.4。

## 全局约束（本批次所有任务适用）

1. **无头运行一律加 `--quit-after <N>`**。脚本加载失败时 `get_tree().quit()` 不会被调用，进程会挂死（已实测 180 s 超时）。
2. **改完 GDScript 先跑 `--check-only`** 做静态语法检查，再运行。
3. **单位**：Godot 用米；`Parameters.md` 是厘米，**÷100**。`CapsuleShape3D.height` 是含两端半球的**总高**。
4. **不用文档或编译/解析成功冒充运行验收通过。** 每个任务必须有可复现命令 + 退出码 + 实际输出。
5. 资产必须由真实工具生成；**不得文本伪造** `.blend` 或声称跑过未跑的命令。

---

## T001：环境与引擎能力门 —— **已完成（2026-10-12/13）**

文件：`Docs/Environment.md`、`Docs/Commands.md`、`Docs/Evidence/T001.md`。

- [x] 读取已有路径和实际工具列表；只读检查版本、硬件与余量。
- [x] 定位引擎可执行文件与版本。**UE 未发现**（13 类证据源全否定）→ 已由负责人决策改用 Godot。
- [x] **Godot 4.7.2 能力实测**：纯文本手写工程/场景/脚本 → 无头运行 → 回读引擎真实状态（含 `CharacterBody3D` + `CapsuleShape3D` 尺寸）**闭环通过**。
- [x] 建立工具能力表；不更改技术路线（改引擎是负责人决策，非 agent 擅自变更）。

**通过**：引擎路径/版本、最小场景操作与运行证据均存在，工具 API 名称来自实际清单。
**状态**：**done（Godot 版）**。原 UE 版判定为 blocked，已由引擎切换取代。

---

## T002：最小 Godot 工程

路径：`Game/Reborn/project.godot`、`res://scenes/maps/l_movement_lab.tscn`、`res://scenes/core/main.tscn`、`res://scripts/...`。
这些是**待创建**产物；`.tscn`/`.tres`/`.gd` 是纯文本，必须由 agent 编写**并由引擎实际解析运行**才算存在。

- [ ] 先检查 `Game/Reborn/` 无已有工程。存在则审查并复用，**不覆盖**。
- [ ] 建立 `project.godot`：渲染器 `forward_plus`（T600 4GB 若吃力可退 `mobile`，**需实测后决定**）、关闭初期不必要特效、定义 InputMap 与碰撞层。
- [ ] 创建 `l_movement_lab.tscn`：1000×1000 cm（**10×10 m**）简单地面方块；`PlayerStart`（`Marker3D`）在地面上方**无碰撞重叠**位置。
- [ ] 放置 100 cm 标尺参照物，供 T005 对照。
- [ ] 用最小 `CharacterBody3D` 暂时验证出生与地面碰撞；**T009 会用正式动物控制替换**。
- [ ] 设置主场景；保存、关闭、重开（重新加载工程）。
- [ ] **无头运行验证**：`--headless --quit-after N` 输出断言，确认出生点有效、地面碰撞生效、无脚本错误。
- [ ] 记录：命令、退出码、实际输出、产物路径。

**通过**：真实 `project.godot` 可被引擎加载运行；无头断言通过；**只生成文件不通过**。
**注意**：本任务的"运行"是无头断言，**不是**视觉验收。视觉部分（画面是否正确）在当前 vision 服务 403 下记 `awaiting-review`。

---

## T003：版本、LFS 与备份

文件：`.gitattributes`、`Docs/Evidence/T003.md`。

> 仓库已于 2026-10-12 初始化并推送公开远端 `github.com/XwenHaHa/Reborn`（负责人授权）。

- [x] 仓库已建立（`main` 分支，远端已连通）。
- [ ] 检查 Git LFS 安装（**已确认 3.4.0 存在**）。
- [ ] 建立 `.gitattributes`：`*.blend`、`*.glb`、`*.gltf`、`*.fbx`、`*.png`、`*.wav`、`*.ogg`、`*.exr` 走 LFS。
- [ ] 确认 `.gitignore` 不排除工程必需文件（**已确认 `.tscn`/`.tres`/`.gd` 不被误伤**）。
- [ ] **实测 LFS 对一个真实测试资产生效**（`git lfs ls-files` 显示追踪）。
- [ ] 在**独立恢复目录**验证源文件可恢复、工程可打开，**不删除原工程**。
- [ ] 记录：命令、退出码、实际输出。

**通过**：**一个可验证的恢复点** + LFS 实际追踪证据。不能用"有 git.exe"或"仓库已推送"替代恢复测试。

---

## T004：Blender 与资产链接入

> **路线已定（负责人 2026-10-13）**：使用 **Blender 3.3.1 自带无头 CLI**，**不使用 Blender-MCP**。
> 因此原"等待 MCP 实现确认"的阻塞已解除，T004 的资产侧可立即执行。

文件：`Art/Blender/Tests/` 测试场景；`Docs/Evidence/T004.md`、`Docs/BlenderPipeline.md`。

- [x] 列出当前可用工具，记录实现与版本。**结论：无任何 MCP 配置**；Blender 与 Godot 均由 CLI 独立驱动。
- [x] 检查 Blender 3.3.1 支持范围；无头 CLI 实测通过（`--background --python`，退出码 0）。
- [x] 记录实际使用的接口名、输入/返回字段及保存方式（见 `BlenderPipeline.md` 的 CLI 调用契约）。
- [ ] **待做**：开新测试场景，查询对象列表；创建命名 `ProbeCube`，边长 **1 m**（注意 Blender 出厂 Cube 是 2 m）。
- [ ] **待做**：保存独立 `.blend`，再重开查询名称和尺寸。
- [ ] **待做**：导出 **glTF 2.0（`.glb`）** 并在 Godot 导入，实测确认单位与轴向（T005 的主体工作）。

**通过**：查询 → 创建 → 保存 → 重开均实测。
**状态**：引擎侧与路线决策 **done**；Blender 资产侧**未开始**（属 T005 范围）。

---

## T005：静态资产往返（Blender → Godot）

文件：`Art/Blender/Tests/StaticProbe_v001.blend`、`Art/Exports/Tests/SM_ProbeCube.glb`；Godot `res://assets/tests/sm_probe_cube.glb`。

- [ ] 在 Blender 查看单位与对象实测尺寸，保存源版本。
- [ ] 导出 **glTF 2.0（`.glb`）**；记录缩放、轴向、单位设置。
- [ ] Godot 导入静态网格并保存；记录真实导入设置。
- [ ] 在 `l_movement_lab` 对照 **100 cm 标尺**，检查长宽高，误差 ≤1 cm；加方向标记检查朝向。
- [ ] 玩家走上物体测试简单碰撞；检查材质与法线，**保留图像验证结果**。
- [ ] **无头验证**：用脚本加载场景，读取导入体的 `AABB`/`mesh.get_aabb()` 尺寸并断言，输出到日志。

**通过**：源 1 m 物体在 Godot 是 **1.0 m**（不是 0.01 或 100）；素材与碰撞在运行中正确。
**注意**：Godot `+Y` 向上与 glTF 一致，Blender `+Z` 向上——导出器负责转换，**不要手工旋转**。

---

## T006：骨骼往返

文件：`Art/Blender/Tests/RigProbe_v001.blend`、`Art/Exports/Tests/SK_RigProbe.glb`；Godot 测试骨骼与动画资源。

- [ ] 创建不追求动物外观的躯干/肢体和少量骨骼，测试绑定。
- [ ] 制作 1 s 动作循环，**首末姿态一致**；**原地动画，不启用根运动**。
- [ ] 导出、导入骨骼网格和动画，检查方向、缩放、动画长度和循环。
- [ ] 在编辑器与运行场景播放，查看是否变形/滑动或根骨缩放异常。
- [ ] Godot 侧用 `AnimationPlayer` / `AnimationTree`；`--headless` 下可断言动画长度与循环。
- [ ] 保存导入/导出预设和测试证据；失败可留作 **blocked**，允许灰盒移动任务推进，**不允许正式骨骼批量生产**。

**通过**：循环实际播放，尺寸与 T005 标尺一致；**只生成 glb 文件不通过**。

---

## T007：首次 Windows 导出

文件：`export_presets.cfg`、`Docs/Evidence/T007.md`；输出 `Builds/P0-Win64/`。

- [ ] **前置检查（当前阻塞）**：`%APPDATA%\Godot\export_templates\` 目前**为空**，需安装 `4.7.2.stable` 导出模板（约 1 GB）。**属下载第三方内容，需负责人授权或自行安装。**
- [ ] 编写 `export_presets.cfg`（纯文本，agent 可写）：preset 名 `Windows Desktop`，x86_64。
- [ ] 执行导出并保留日志：
      `& '<godot_console.exe>' --headless --path '<proj>' --export-release "Windows Desktop" '<out>.exe'`
- [ ] 成功判据：**退出码 0** 且目标 `.exe` 实际存在且大小合理。
- [ ] 从导出目录启动独立程序，验证出生、碰撞、输入、正常退出；**重启一次**并记录结果。
- [ ] 没有 GUI/输入自动化工具时记 **awaiting-review**，不冒充通过。

**通过**：**非编辑器程序实际运行**，不能以导出命令被启动算通过。

---

## 批次结束

更新 Tasks/Handoff，说明 Godot 与 Blender 哪些能力已通过。
**任何执行能力门未通过时请求最小解除动作，不承诺自动完成全项目。**
下一任务为前置满足者；不要跳过未通过的阶段门批量制作正式资产。
