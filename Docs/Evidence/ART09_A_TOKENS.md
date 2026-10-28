# ART09-A 证据：展板视觉令牌与关键图管线

状态：done
日期：2026-10-29
分支：`art/modeling-pipeline`

## 命令与结果

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
& $g --path $proj --headless --import
```

| 项目 | 结果 |
|---|---|
| `--import` | exit 0；`mossy_forest_2k.hdr` 与 `menu_creek.png` 各重导入一次；两条 `Ignoring unsupported header information in HDR`（Radiance 头 GAMMA/PRIMARIES，不影响纹理） |
| `run_art09_tokens.gd`（headless） | **15/15，0 failures，exit 0**；`SCRIPT ERROR` 0 条 |

关键输出：

```text
TOKENS|rail_left=900|center_width=422|card=(336.0, 84.0)|thumb=64
ASSERT|title_font_is_system_font|PASS
ASSERT|title_font_prefers_kai|PASS
ASSERT|sky_hdri_registered|PASS
ASSERT|menu_accent_matches_token|PASS
SUMMARY|checks=15|failures=0
RESULT|PASS
```

## 资产事实

| 文件 | 字节 | SHA256 |
|---|---|---|
| `Game/Reborn/assets/environment/hdri/mossy_forest_2k.hdr` | 7.25 MB | `EAC287225A8D012F9DABF706AA4DD411340F681122C66AE88CF3484FBC716080` |

- 许可 CC0（Poly Haven），登记见 `Docs/THIRD_PARTY_ASSETS.md` §8；下载走 API 匿名直链，无需登录。
- 选型依据：对比 `mossy_forest` / `rainforest_trail` / `forest_grove` / `schachen_forest` 的
  tonemapped 预览，`mossy_forest` 的「苔石溪床 + 蕨类 + 斑驳阳光」最接近展板环境基调。

## 未验证 / 边界

- 天空球的实际画面观感：本阶段只证明"资产在库 + 场景引用有效 + T011 环境断言通过"，
  逐项视觉判读放在阶段 B 的截图里（`Art/Probes/art09_menu_after/`）。
- `menu_creek.png` 无来源记录，且已确认只是庭院低质渲染（1280×720 石墙 + 直线水面 + 漂浮灰板），
  现已无引用；**未删除**，处置建议见 `Docs/BoardArtPipeline.md` §5。
- 本机图片生成模型未配置，类型 C（AI 生成关键图）未做任何尝试，不冒充已验证。

## 恢复入口

新增文件：`scripts/ui/board_tokens.gd`、`tests/run_art09_tokens.gd`、`Docs/BoardArtPipeline.md`、
HDRI 两个副本。天空球改动落在 `scenes/maps/l_courtyard.tscn` 与 `tests/tool_make_courtyard.gd`，
这两个文件当前**仍带着 ART07 未提交改动**，因此未单独提交（见 `Docs/Handoff.md`）。
