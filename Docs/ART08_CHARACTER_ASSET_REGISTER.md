# ART08 角色资产登记与授权门

状态：blocked（展板级新角色资产未获负责人逐项授权）

| 角色 | 当前仓库资产 | 来源/许可 | 骨骼/动作 | 当前用途 | 状态 |
|---|---|---|---|---|---|
| 猫 | `Game/Reborn/assets/characters/cat/sm_cat_002.glb` | 已入库候选，许可资料见 ART03 登记 | 33 骨；Idle/Walk/Run；无 AttackCue | 可玩猫与菜单主视觉 | awaiting-review，未达展板级 |
| 鼠 | `Game/Reborn/assets/characters/mouse/sm_mouse_002.glb` | CC-BY 候选，许可资料见 ART03 登记 | 23 骨；Eat/Idle/Run/Walk | 可玩鼠与菜单卡片 | awaiting-review，体态与展板不同 |
| 兔 | 无正式 `SpeciesConfig` | 未授权新资产 | 无 | 右栏未来开放占位 | blocked |
| 狐狸 | 无正式 `SpeciesConfig` | 未授权新资产 | 无 | 右栏未来开放占位 | blocked |
| 鸟 | 无正式 `SpeciesConfig` | 未授权新资产 | 无 | 右栏未来开放占位 | blocked |

## 授权门

负责人必须为每个新增资产确认来源、作者、许可证、商业使用、修改权限、下载/购买授权、骨骼、动画和面数预算后，才能下载或导入正式资源。未确认前禁止 Cline 自行下载、购买、登录、替换 `.tres` 或把静态占位宣称为可玩物种。

## 接入硬契约

- Blender 面朝 `+Y`，导入 Godot 后面朝 `-Z`。
- 原点在脚底，模型贴地，动画原地无根运动。
- 视觉网格不承载玩法碰撞，胶囊尺寸和导航不改。
- 猫/鼠现有资产保留为回退；攻击/逃跑动作缺失时写 `NOT-AVAILABLE`。
