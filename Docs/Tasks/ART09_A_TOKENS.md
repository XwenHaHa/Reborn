# ART09-A 任务规格：展板视觉令牌与关键图管线

状态：done（2026-10-29）
上位计划：`Docs/Tasks/ART09_BOARD_PARITY.md` §3 阶段 A

## 目标

把展板的颜色、字号阶、栅格、控件尺寸变成**唯一真源**（`BoardTokens`），并建立关键图/天空球的
来源规则，避免 UI 里继续散落魔法数、避免再出现来源不明的图片资产。

## 改动路径

- 新增 `Game/Reborn/scripts/ui/board_tokens.gd`（`class_name BoardTokens`）
- 新增 `Docs/BoardArtPipeline.md`
- 新增 `Game/Reborn/assets/environment/hdri/mossy_forest_2k.hdr`（CC0，Poly Haven）
- 源档另存 `Art/Exports/Env/HDRIs/mossy_forest_2k.hdr`
- 新增 `Game/Reborn/tests/run_art09_tokens.gd`
- 修改 `Docs/THIRD_PARTY_ASSETS.md`（§8 登记 HDRI）

## 内容

1. **令牌**：三段栅格（左栏 430 / 中央 422 / 右栏 380，1280 宽下右栏左边界 = 900）、
   字号阶（104/20/20/14/19/18/12/11/16/11）、颜色（金 `#D89B3C` 系、面板 `#07141D` 系）、
   控件尺寸（按钮 300×52、卡片高 84、缩略图 64、超采样 ×2）。
2. **书法字体**：`title_font()` 返回 `SystemFont`（候选：华文行楷 → 华文新魏 → 楷体 → SimSun），
   进程内缓存。**不把字体文件放进仓库**（商业字体不可再分发）。
3. **关键图规则**：只允许「引擎内渲染产物 / 已登记 CC0 资产 / 记录 prompt 的本机生成图」；
   本机图片生成模型未配置（实测 `IMAGE_NOT_CONFIGURED`），故类型 C 暂不可用。
4. **天空球**：`l_courtyard.tscn` 的程序化天空换为 `PanoramaSkyMaterial`（CC0 `mossy_forest` 2k HDR）；
   生成器 `tool_make_courtyard.gd` 同步（含 HDRI 缺失时回退程序化天空）。

## 验收

- `run_art09_tokens.gd` 全绿（15 条）：栅格、字号阶单调、`SystemFont`、HDRI 在库、
  菜单里的同值别名不漂移。
- 规则：改令牌必须同时改 `run_art09_tokens.gd` 的期望值；不允许"令牌改了测试没跟"。

## 回退

删除 `board_tokens.gd` + `Docs/BoardArtPipeline.md` + `run_art09_tokens.gd`，把
`l_courtyard.tscn` 的 `PanoramaSkyMaterial` 换回 `ProceduralSkyMaterial
（ground_horizon 0.62/0.66/0.70、ground_bottom 0.52/0.55/0.58、energy 0.75）即可；
`tool_make_courtyard.gd` 里的 `SKY_HDRI_PATH` 分支改回原 710–718 行写法。
