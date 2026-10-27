# ART08 任务规格：溪谷表现层与庭院玩法几何

状态：awaiting-review（环境不变量通过；展板视觉仍未通过）

## 目标

验证当前 ART07 庭院表现层可以作为 ART08 的安全基线，并建立表现层不变量测试。环境视觉目标仍要求后续负责人审阅或授权新资产，不把数值回归当成展板美术完成。

## 产物

- `Game/Reborn/tests/run_art08_environment_contract.gd`
- `Docs/Evidence/ART08_ENVIRONMENT_BOARD.md`

## 必须保持

- 20 个现有 `StaticBody3D` 和 `nav_source_courtyard` 集合不变。
- 溪水 1 个、无碰撞、仍在 `water_bodies` 组。
- 树根洞口和现有鼠洞路线保留。
- 装饰不带实体碰撞、不进入导航源。
- 生成器重建后先检查导航资源差异，再决定是否重烤。

## 当前停止点

ART07 已经增加确定性装饰、SSAO、ACES 和无雾配置，但其证据中 A5/A7 仍为部分通过/失败，草石贴纸感、接地感和远景层次还没有达到展板。没有新的资产授权或明确视觉诊断前，不继续盲目堆半透明阴影和装饰节点。
