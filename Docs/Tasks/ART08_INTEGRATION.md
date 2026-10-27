# ART08 任务规格：菜单、实玩与展板差距整合验收

状态：awaiting-review（功能与回归通过；展板整体视觉未通过）

## 目标

通过真实入口取证覆盖菜单、猫/鼠物种选择和两种第三人称出生画面，并完成 ART08 相关玩法回归。不得把截图存在或无头断言全绿等同于展板视觉通过。

## 产物

- `Game/Reborn/tests/tool_capture_art08_integration.gd`
- `Art/Probes/art08_integration/`
- `Docs/Evidence/ART08_INTEGRATION.md`
- `Docs/Tasks.md` / `Docs/Handoff.md` 覆盖记录

## 验收

- 五张真实入口截图均 `save_result=0 (OK)` 并输出 `CAP|integration|done`。
- 菜单契约、角色/环境不变量、设置、HUD、生命周期、捕获、AI 和攻击套件全部通过。
- 视觉结果逐项记录 PASS/FAIL/NOT-VERIFIED；没达到展板目标时状态保持 awaiting-review。
- 更新项目证据索引，不覆盖原有未提交 ART07 内容。
