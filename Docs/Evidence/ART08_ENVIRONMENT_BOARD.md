# ART08 证据：溪谷表现层与庭院玩法几何

状态：awaiting-review（不变量通过；整体展板视觉未通过）
日期：2026-10-28

## 起始状态

保留 ART07 工作区的未提交改动，不重建、不覆盖、不清理。

## 基线回归

在 ART07 工作区状态下运行：

| 套件 | 结果 |
|---|---|
| `run_t011_greybox.gd` | 229/229，0 failures，exit 0 |
| `run_t012_navigation.gd` | 79/79，0 failures，exit 0 |
| `run_t020_perception.gd` | 164/164，0 failures，exit 0 |
| `run_t026_cover.gd` | 96/96，0 failures，exit 0 |
| `run_t027_ecology.gd` | 全量执行，exit 0；stdout 超过工具返回上限，原始输出保存在本会话 scratch 日志；该套件既有 96 项，在可见输出中关键生态判据均 PASS |

T020 产生 Godot NavigationMesh 属性精度 warning（agent_height/agent_radius/region_min_size 转换），是既有烘焙提示；没有对应失败。未见新 `SCRIPT ERROR`。

## 环境不变量契约

新增 `Game/Reborn/tests/run_art08_environment_contract.gd`，检查真实 `l_courtyard.tscn`：

- 20 个 `StaticBody3D`。
- 20 个 `nav_source_courtyard` 成员。
- 溪水节点存在、没有碰撞形状，`water_bodies` 组恰有 1 个成员。
- 树根洞口标记存在。
- 非静态、非 Area3D 的装饰无实体碰撞，装饰不进入导航源。

运行结果：`9/9`，0 failures，exit 0。实际读数 `static_bodies=20|nav_source=20|water=1|decor_collision=0|decor_nav=0`。

## 视觉结论与边界

本阶段没有改 ART07 生成器、shader、庭院场景、导航或任何资产；因此没有生成新的改后环境截图，也没有宣称环境视觉通过。当前 ART07 证据已明确：A5 前中后景仅部分通过、A7 无漂浮/贴纸感仍失败；宏观背景仍是庭院围墙和直线水带，与展板溪谷差距明显。

视觉整体判定：FAIL / 未达到目标。需要新的真实环境资产/构景方案和负责人资产授权或审阅，不能通过继续添加随机装饰声称达标。

## 阻塞与恢复入口

- 资产授权登记见 `Docs/ART08_CHARACTER_ASSET_REGISTER.md`；环境资产授权尚未逐项确认。
- ART07 的视觉限制和现有参数事实见 `Docs/Evidence/ART07_ENVIRONMENT_COMPOSITION_CONTACT.md`。
- 本阶段唯一新增代码是环境不变量测试，没有修改 ART07 用户工作区改动。
