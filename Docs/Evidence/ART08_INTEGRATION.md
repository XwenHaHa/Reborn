# ART08 证据：菜单、实玩与展板差距整合验收

状态：awaiting-review（系统功能回归通过；展板整体视觉未通过）
日期：2026-10-28
分支：`art/modeling-pipeline`

## 真实窗口取证

命令：

```powershell
& $g --headless --path $proj --check-only --script 'res://tests/tool_capture_art08_integration.gd' --quit-after 90000
& $g --path $proj --script 'res://tests/tool_capture_art08_integration.gd' --quit-after 90000 -- integration
```

结果：exit 0；五张图均 `save_result=0 (OK)`；最终输出 `CAP|integration|done`。截图位于 `Art/Probes/art08_integration/`：

- `integration_menu_cat.png`
- `integration_species_cat.png`
- `integration_species_mouse.png`
- `integration_alive_mouse.png`
- `integration_alive_cat.png`

## 回归结果

| 套件 | 结果 |
|---|---|
| `run_art08_board_contract.gd` | 9/9 PASS |
| `run_art08_character_contract.gd` | 15/15 PASS；兔/狐/鸟资产授权阻塞如实输出 |
| `run_art08_environment_contract.gd` | 9/9 PASS；20 StaticBody、20 nav source、1 water body、装饰碰撞/导航均 0 |
| `run_art05_settings.gd` | 20/20 PASS |
| `run_t018_hud.gd` | 73/73 PASS |
| `run_t030_lifecycle.gd` | 111/111 PASS |
| `run_t021_capture.gd` | 279/279 PASS |
| `run_t022_loop.gd` | 168/168 PASS |
| `run_t023_cat_ai.gd` | 178/178 PASS |
| `run_t024_chase_search.gd` | 136/136 PASS |
| `run_t025_attack.gd` | 175/175 PASS |
| `run_t029_sprint_chase.gd` | 39/39 PASS |

另外，非 headless `run_art05_input.gd` 20/20 PASS；`run_art02_cat.gd` 72/72、`run_art03_mouse.gd` 45/45、`run_t008_species.gd` 118/118 PASS。ART07 环境相关 T011/T012/T020/T026/T027 基线也全通过。测试产生的预期 warning 包括坏配置回退、非法生命周期迁移和 NavigationMesh voxel 精度提示；没有发现与 ART08 改动相关的新脚本错误。

## 展板视觉验收

- 菜单和物种选择有真实窗口截图，布局结构和输入工作。
- 截图仍显示庭院围墙、直线溪水和稀疏草带；不是展板里的自然溪谷。
- 猫仍是 `sm_cat_002.glb`，鼠仍是 `sm_mouse_002.glb`；模型与展板展示的动物不同。
- 右栏目前是实时 3D 预览卡，不是展板的动物照片列表。
- 猫攻击/扑击和鼠逃跑展示帧没有新增资产支持。

总体结论：**FAIL / 尚未达到用户展板目标**。本次完成的是菜单结构、验收工具、授权登记和不变量保护，不是全套美术升级。当前外部 vision 服务未运行，视觉外部判读为 `NOT-RUN`；人工截图对比已足以确认环境/角色差异仍明显，不作“达到”结论。

## 阻塞

- 猫鼠展板级模型、猫扑击、鼠逃跑动作、兔/狐狸/鸟模型需负责人明确资产来源与许可授权。
- 环境需先确定真实溪谷资产/构景方案及对应授权；ART07 现存证据 A5/A7 未通过。
- 整体纵切片不能标 done/approved，直到新资产获批、环境/角色真实窗口视觉验收通过。

## 提交与恢复

ART08 本轮独立提交：`d493cc6`（基线）、`c0ae0e9`（菜单）、`6090559`（角色授权门）、`07c1bc5`（环境不变量）。未 push。原有 ART07 和规划未提交文件均未纳入这些提交，也未被回退。
