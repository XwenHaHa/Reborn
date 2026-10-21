# Art/Staging：新资产暂存区

新做的资产先在**这里**落地、过完 Godot 侧与视觉验收，再决定是否并入正式目录。
目的是让"半成品"和"正式资产"物理分开，任何时候都能一眼看出哪些还没验收。

约定：
- 目录名 = 资产名（例如 `ENV_BUSH_001/`）。
- 只放**本轮新做的**东西；已验收的资产按 `Docs/BlenderPipeline.md` 的路径规则
  落到 `Art/Blender/<分类>/`、`Art/Exports/<分类>/`、`Game/Reborn/assets/<分类>/`。
- **不要**在这里放覆盖旧资产的同名文件；替换旧资产要先备份并留证据。

当前状态：ART01 的草丛掩体已直接走正式路径（`Art/Blender/Environment/`、`Art/Exports/Environment/`、
`Game/Reborn/assets/environment/`），本目录暂空，留给下一批资产（补给点标记 / 树根屏障 / 庇护棚）。
