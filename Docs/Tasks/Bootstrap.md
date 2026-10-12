# 启动批次执行规格：T001～T007

> Agent 逐任务执行，遵循 AGENTS.md；本批次不启动正式动物建模或商业发行。本文只定义实施与验证，不宣称命令/接口已存在。

**Goal：** 验证 UE + Blender-MCP 可形成可运行和可恢复的生产链。
**Architecture：** 蓝图工程，真实编辑器资产工具，独立 Blender 测试场景，Windows 打包。
**Tech Stack：** 本机确认后的 UE5、Blender、指定 Blender-MCP、Node/Git。

## T001：环境与 UE 能力门

文件：更新 `Docs/Environment.md`；创建 `Docs/Commands.md`、`Docs/Evidence/T001.md`。

- [ ] 读取已有路径和实际工具列表；只读检查版本、硬件与余量。每周投入未提供可记录未知，不作为环境检查阻塞。
- [ ] 定位 UE 可执行文件和版本。未找到请求路径；不得用猜测目录继续。
- [ ] 用现有受支持 UE 工具验证能创建蓝图、设置变量、连接事件节点、编译并保存重开。试验在独立能力测试工程或负责人提供的空工程中，不覆盖正式工程。
- [ ] 验证运行、停止、日志、读取运行状态或操控输入的能力；只有截图工具不等于自动化游戏输入。
- [ ] 建立工具能力表；UE 路径或节点编辑无法验证则记录 blocked，继续独立 Blender 检查，不更改技术路线。

通过：UE路径/版本、最小资产操作与运行证据均存在，工具 API 名称来自实际清单。硬件信息缺少时不能宣称性能基线已通过。

## T002：最小蓝图工程

路径：`Game/Reborn/Reborn.uproject`，`Content/Reborn/Maps/L_MovementLab.umap`、`Core/BP_RebornGameMode.uasset`，`Config/DefaultEngine.ini`。这些是待创建产物，不可直接伪造二进制文件。

- [ ] 先检查目标目录无已有工程。存在则审查并复用，不覆盖。
- [ ] 通过 UE 编辑器建立 Blank 蓝图工程，关闭初期不必要特效；创建 MovementLab。
- [ ] 地面放1000×1000cm简单方块，PlayerStart 在地面上方无碰撞重叠位置；用模板可运行玩家暂时验证出生。
- [ ] 设置默认地图和 GameMode；保存、关闭、重开。
- [ ] PIE验证有效出生、地面碰撞、停止无错误。记录后在 T009 用动物控制替换模板玩家。

通过：真正的 uproject/umap 可重开运行；只生成目录不通过。

## T003：版本和备份

文件：`.gitignore`、`.gitattributes`（初始化需权限）；`Docs/Evidence/T003.md`。

- [ ] 若 Git 未获初始化权限，先在项目内建立命名备份并记录，向负责人请求版本管理授权。不能标完整 Git 验收通过。
- [ ] 获批后初始化，检查 Git LFS 安装；配置 uasset/umap/blend/fbx/大贴图追踪，排除 Binaries/Intermediate/DerivedDataCache/Builds 临时产物。
- [ ] 查看生成规则确认不排除工程必需插件与配置；检查 LFS 对一个真实测试资产生效。
- [ ] 在独立恢复目录验证源文件可恢复、工程可打开，不删除原工程。没有 Git 提交授权不提交，保留本地文件。

通过：一个可验证的恢复点；正式版本管理欠缺明确记录，不能用“有 Git exe”替代恢复测试。

## T004：Blender-MCP

文件：`Art/Blender/Tests/MCPProbe_v001.blend`；`Docs/Evidence/T004.md`、`Docs/BlenderPipeline.md`。

- [ ] 列出当前 MCP 工具，记录具体实现、客户端和插件版本。不存在时请求实现/配置，不选择任意第三方仓库。
- [ ] 检查现有 Blender 3.3 与实现支持范围；不兼容提出升级方案，未经确认不安装。
- [ ] 开新测试场景，查询对象列表；创建命名 ProbeCube，边长1m。
- [ ] 保存独立 blend，再重开查询名称和尺寸；连接断开时只做有诊断的重连。
- [ ] 记录实际使用的工具名、输入/返回字段及保存方式，脱敏。

通过：查询→创建→保存→重开均实测，不仅是服务显示连接。

## T005：静态往返

文件：`Art/Exports/Tests/SM_ProbeCube.fbx`；UE `/Game/Reborn/Environment/Tests/SM_ProbeCube`。

- [ ] 在 Blender 查看单位与对象实测尺寸，保存源版本。
- [ ] 使用可用的 FBX 导出接口导出所选测试物体；记录缩放、轴向、单位设置。
- [ ] UE导入静态网格并保存；记录真实导入设置，关闭非必要复杂碰撞。
- [ ] 在 MovementLab 对照100cm标尺，检查长宽高，误差≤1cm；加方向标记检查朝向。
- [ ] 玩家走上物体测试简单碰撞；检查材质与法线，保留图像验证结果。

通过：源1m物体在UE是100cm而非1cm或100m；素材和碰撞在运行中正确。

## T006：骨骼往返

文件：`Art/Blender/Tests/RigProbe_v001.blend`、`Art/Exports/Tests/SK_RigProbe.fbx`；UE Characters/Tests 测试骨骼与动画资产。

- [ ] 创建不追求动物外观的躯干/肢体和少量骨骼，测试绑定。
- [ ] 制作1s动作循环，首末姿态一致；使用原地动画，不启用根运动。
- [ ] 导出、导入骨骼网格和动画，检查方向、缩放、动画长度和循环。
- [ ] 在编辑器与运行场景播放，查看是否变形/滑动或根骨缩放异常。
- [ ] 保存导入/导出预设和测试证据；失败可留作 blocked，允许灰盒移动任务推进，不允许正式骨骼批量生产。

通过：循环实际播放，尺寸与 T005 标尺一致；只生成 FBX 文件不通过。

## T007：首次打包

文件：更新 `Docs/Commands.md`，`Docs/Evidence/T007.md`；输出 `Builds/P0-Win64/`。

- [ ] 确认所选 UE 的 Win64 打包依赖，使用实际版本要求，不一概要求 C++ 工具链或假定完全不需要 SDK。
- [ ] 生成本机可复制的 UAT/编辑器打包命令并记录环境；地图包含 MovementLab。
- [ ] 执行 Development Win64 打包，保留日志；成功需退出码和明确成功结果，无 Cook/Package 错误。
- [ ] 从打包目录启动独立程序，验证出生、碰撞、输入、正常退出。
- [ ] 重启一次并记录结果；没有 GUI/运行工具时记 awaiting-review。

通过：非编辑器程序实际运行，不能以打包命令被启动算通过。

## 批次结束

更新 Tasks/Handoff，说明 UE 和 Blender 哪些能力已通过。下一任务为前置满足的 T008；任何执行能力门未通过时请求最小解除动作，不承诺自动完成全项目。
