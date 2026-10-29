# 关键图管线（Board Art Pipeline）

状态：v1（2026-10-29，ART09 阶段 A 建立）
依据：`Docs/Tasks/ART09_BOARD_PARITY.md` 阶段 A、`Docs/THIRD_PARTY_ASSETS.md`

## 1. 为什么要这份文档

展板（`《轮生：森林生存游戏概念展板》.png`）里有大量"照片级"画面：森林溪谷背景、5 张动物肖像、
环境五件套缩略图。这些不是 UI 代码能画出来的，必须来自**有来源、可复现、许可清楚**的图片资产。

本仓库已经出现过一次反例：`Game/Reborn/assets/ui/menu_creek.png`（1280×720，910 KB）是上一轮
未提交的尝试，内容是当前庭院的低质渲染截图（石墙 + 直线水面 + 漂浮灰板），**没有任何来源记录**，
而且作为菜单底图反而比实时 3D 更差。ART09 起该文件**不再被任何代码引用**，保留在原处待负责人处置
（见 §5）。

## 2. 关键图的三种合法来源

| 类型 | 允许的用途 | 硬要求 |
|---|---|---|
| **A. 引擎内渲染产物** | 菜单底图、走态展示条、环境缩略图 | 必须由 `res://tests/tool_capture_*.gd` 生成；命令、机位、分辨率、生成时间写进 `Docs/Evidence/`；同一命令可复现同一画面 |
| **B. 已登记的 CC0 第三方资产** | 天空球、材质、模型、必要的环境照片 | 必须先进 `Docs/THIRD_PARTY_ASSETS.md`（来源页、作者、许可、署名义务、字节数/SHA256）；下载前需负责人授权（2026-10-29 已授权 CC0） |
| **C. 本机图片生成的图** | 菜单关键图、动物肖像 | 必须记录 prompt、模型名、生成日期、后处理步骤，落在 `Art/Generated/Board/`，并在 `Docs/THIRD_PARTY_ASSETS.md` 备注"AI 生成" |

**禁止**：来源不明的网图、需要登录/付费而未授权的资源、Sketchfab Free Standard / NoAI 许可资产、
把展板图本身当游戏截图。

> 现状（2026-10-29）：本机图片生成模型**未配置**（`GenerateImages` 返回 `IMAGE_NOT_CONFIGURED`），
> 所以类型 C 目前不可用。菜单背景与肖像在阶段 B 先用「实时 3D + CC0 天空球」顶住，
> 阶段 E（`l_ravine_board`）与阶段 F（肖像卡）再决定是走 A 还是 C。

## 3. 落地位置

| 内容 | 仓库路径 | LFS |
|---|---|---|
| 运行时用到的图/HDRI | `Game/Reborn/assets/ui/`、`Game/Reborn/assets/environment/hdri/` | 是（`.png` / `.hdr` 已配） |
| 渲染/生成源档 | `Art/Generated/Board/`、`Art/Exports/Env/HDRIs/` | 是 |
| 验收截图 | `Art/Probes/art09_*/` | 是 |
| 来源登记 | `Docs/THIRD_PARTY_ASSETS.md` | 否（文本） |

## 4. 导入与引用规则

1. 图片放好先跑 `& $g --path $proj --headless --import`，确认无 reimport 报错。
2. 代码里只写 `res://` 路径，**不写绝对路径**；字体同理（见 §6）。
3. 每张关键图都要有一条断言守着"文件在库"：`ResourceLoader.exists()`（见
   `Game/Reborn/tests/run_art09_tokens.gd`），避免"图没进库但代码引用"的静默失败。
4. 天空球必须保持 `Environment.BG_SKY` + 非空 `Sky`：T011 的 `world_environment_with_sky` /
   `decor_sky_background_kept` 两条断言依赖它。

## 5. 已知遗留

| 文件 | 状态 | 处置 |
|---|---|---|
| `Game/Reborn/assets/ui/menu_creek.png` | 未被引用；庭院低质渲染，无来源记录 | 建议负责人确认后删除；未获确认前不动 |

## 6. 字体（书法标题）

- 展板标题「轮生」是毛笔书法体。仓库**不放字体文件**：华文行楷等商业字体不可再分发。
- 实现：`BoardTokens.title_font()` 用 `SystemFont` + 候选列表
  `["华文行楷", "STXingkai", "华文新魏", …, "SimSun"]`，运行时取系统字体。
  本机实测命中「华文行楷」（`C:\Windows\Fonts\STXINGKA.TTF`），截图见 `Art/Probes/art09_menu_after/board_menu.png`。
- 换机器没有这些字体时**自动退回默认字重**，仍然可读，只是没有笔锋——
  `run_art09_menu_contract.gd` 的 `title_uses_system_font` 断言的是"用的是 SystemFont 机制"，
  不是"一定命中行楷"，所以换机不会假红。
- 正式发行前若要求稳定观感，需采购可商用的书法字体（授权门，负责人决定），
  届时改为 `FontFile` 资源并在此登记许可。


## 7. 物种肖像（ART09-F1，引擎渲染）

- **产物**：`Game/Reborn/assets/ui/portraits/portrait_<species_id>.png`（512×512，属 §2 的 A 类：引擎内渲染）。
- **工具**：`Game/Reborn/tests/tool_render_board_portraits.gd`（非 headless，`-- portraits`）。
  对 `resources/species/*.tres` 逐个渲染，**不需要任何外部素材或授权**。
- **取景**：闭环自校正 —— 透明底渲一遍 → 用 alpha `get_used_rect()` 量「填充率 + 偏心」→ 修距离/平移相机，
  最多 5 轮；目标填充率 0.62、偏心 ≤4%。不依赖胶囊尺寸，也不猜骨骼网格 AABB（`SkinnedMesh.get_aabb()` 实测 0.02 m）。
- **接线**：`SpeciesConfig.display_portrait`（`Texture2D`，可空）→ 菜单右栏卡、物种页缩略图槽、物种页大卡背景。
  配置为空时自动回退实时 3D 预览，所以旧配置与未来物种都不会坏。
- **重跑时机**：换角色模型、改光照/配色、加新物种时重跑一次；`run_art09_portrait_contract.gd` 守着产物与接线。
- **注意**：肖像只能覆盖**有模型**的物种；兔/狐/鸟没有模型时卡片保持 `?`，**不得**用别名或占位图冒充。
