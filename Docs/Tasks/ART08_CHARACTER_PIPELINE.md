# ART08 任务规格：角色资产授权门与统一接入

状态：awaiting-review / blocked（现有猫鼠接入通过；展板级新资产未授权）

## 目标

验证菜单与第三人称共用 `SpeciesConfig.visual_scene`，视觉网格不替代玩法胶囊，并为猫、鼠、兔、狐狸、鸟建立可追溯的资产授权记录。

## 产物

- `Docs/ART08_CHARACTER_ASSET_REGISTER.md`
- `Game/Reborn/tests/run_art08_character_contract.gd`
- `Docs/Evidence/ART08_CHARACTER_PIPELINE.md`

## 结论范围

- 猫保留 `sm_cat_002.glb`，已有 Idle/Walk/Run；无 AttackCue。
- 鼠保留 `sm_mouse_002.glb`，已有 Eat/Idle/Run/Walk。
- 猫鼠视觉网格无碰撞，胶囊契约由 `AnimalBody` 继续负责。
- 兔、狐狸、鸟没有授权的新资产和可玩配置，继续显示为未来开放占位。

## 停止条件

未获负责人逐项确认来源、许可证、商业使用、修改和下载授权前，不下载、不购买、不登录、不导入新资产，不替换正式 `.tres`。
