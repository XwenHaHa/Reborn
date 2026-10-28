# ART09-E 证据：展板切片关（溪谷）与第三人称构图

状态：done / 环境材质 **FAIL（未达展板级，按路径 C 预期）**
日期：2026-10-29
分支：`art/modeling-pipeline`

## 1. 命令与结果

```powershell
$g = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$proj = 'E:\Reborn\Game\Reborn'
& $g --headless --path $proj --script 'res://tests/tool_probe_aabb.gd' --quit-after 60000
& $g --headless --path $proj --script 'res://tests/tool_make_ravine_board.gd' --quit-after 60000
& $g --headless --path $proj --script 'res://tests/run_art09_frame_contract.gd' --quit-after 60000
& $g --path $proj --script 'res://tests/tool_capture_art09_board.gd' --quit-after 60000 -- ravine
```

| 套件 | 结果 |
|---|---|
| `tool_probe_aabb.gd`（新增） | 9 件资产 AABB 全部 `min_y = 0.000`（**原点在脚底**） |
| `tool_make_ravine_board.gd`（新增） | `save_result=0 (OK)`；巨石 5 / 草丛 10 / 泥舌 4 / 盘根 6 / 矮墙 3 / 围栏 2 / 立柱 4 / 脚边石 4 / 脚边草 3 |
| `run_art09_frame_contract.gd`（新增） | **40/40，0 failures，exit 0** |
| `run_t011_greybox.gd` | 229/229，exit 0（庭院geometry/导航未受影响） |
| `run_art09_tokens / menu / species / hud` | 15/15、42/42、59/59、63/63 全绿 |
| `tool_capture_art09_board.gd -- ravine`（**非 headless**） | 5 帧全部 `save_result=0 (OK)`，`CAP|ravine|done`，exit 0 |

关键读数：

```text
FRAME_CONTRACT|env|tonemap=3|ssao=true|fog=9..46|exposure=1.05|sky=panorama
FRAME_CONTRACT|sun|energy=1.45|color=(1.0, 0.9, 0.72, 1.0)|rot=(-24.0, 32.0, 0.0)
FRAME_CONTRACT|counts|{ "boulders": 5, "bushes": 10, "mud_tongues": 4, "root_barrier": 6,
  "walls": 3, "fences": 2, "shelter_posts": 4, "near_rocks": 4, "near_bushes": 3 }
FRAME_CONTRACT|meshes=48
FRAME|TPCamera|pos=(0.45, 0.68, 3.75)|pitch=6.3|fov=58|dof=on
SUMMARY|checks=40|failures=0
```

## 2. 截图

`Art/Probes/art09_board_after/`

- `ravine_tp.png`：第三人称主帧（猫在左下、面向溪谷、远景景深开）
- `ravine_tp_wide.png`：宽景
- `ravine_env_creek.png`：溪流特写
- `ravine_env_roots.png`：树根洞口
- `ravine_env_far.png`：远景框景（矮墙/围栏/庇护棚）

## 3. 逐项视觉判读（对比展板第三人称实玩区）

| 展板要素 | 现状 | 判定 |
|---|---|---|
| 动物在下三分之一、背对镜头、视线进景 | 猫站在 (0, 0.36, 2.4) 面朝 −Z，占屏高约 1/6，位于左下 | **PASS**（位置）；**FAIL**（占比偏小，展板约 1/4） |
| 画面纵深：前景地面 → 溪流 → 中景石/洞 → 远景林 | 四层齐备，深度雾 9→46 m 把远景淡下去 | **PASS** |
| 森林背景（不是围墙） | CC0 `mossy_forest` HDRI 天空球，树冠与光斑真实 | **PASS** |
| 逆光/暖调主光 + 冷色补光 | 主光 (−24°,32°) 能量 1.45 暖色、补光 0.38 冷色；地面阴影可见 | **PASS** |
| 景深（近实远虚） | `CameraAttributesPractical` 远景景深开启（本版本支持，`dof=on`） | **PASS** |
| 溪水像浅溪 | 水面是程序化 shader 的**高饱和蓝 + 白沫**，浅看像泳池 | **FAIL**（需真实浅水材质/河床贴图） |
| 溪岸过渡自然 | `WetShore` 深色泥带在画面里读成一条"沥青带"；泥舌太薄 | **FAIL** |
| 前景地面有草/落叶细节 | 前景是一大片平滑褐色地面（只有 3 团脚边草、4 块小石） | **FAIL**（缺地面散布资产） |
| 装饰材质达展板级 | 巨石是 CC0 扫描件（尚可），矮墙/围栏/棚顶仍是旧的低模石皮 | **FAIL** |

**结论：构图、光照、后处理三层已经立起来（这是本阶段真正的产出）；水面/岸线/地面细节/低模石墙仍是
明显差距，故整体环境材质判 FAIL。**

## 4. 过程中修掉的真实缺陷（含一次人为事故）

1. **主体掉出画面**：展示关零碰撞，`CharacterBody3D` 直接下落（首轮实测 y = −0.269）。
   → 取证工具里加 `set_physics_process(false)` + 复位位置。
2. **水面 BoxMesh 侧壁穿帮**：近景能看到那块"水池挡板"的立面。→ 展示关改用 `PlaneMesh` 薄片
   （庭院那边仍保持 BoxMesh，因为 T011 有 `creek_water_mesh_is_box` 断言）。
3. **石墙/围栏被吊到半空**：我一开始猜"glb 原点在中心"，给矮墙 +0.40、围栏 +1.50、立柱 +0.81。
   → 写 `tool_probe_aabb.gd` 实测：**9 件资产 min_y 全是 0.000（原点在脚底）**，偏移全部回退。
   这条经验已写进任务规格。
4. **⚠️ 人为事故（已恢复）**：我用 `Get-Content | -replace | Set-Content -NoNewline` 批量改生成器的
   三个高度常量，结果把整个文件的 UTF-8 与行尾**写坏**（中文注释变成 `玩?`，行被并成一行）。
   因为该文件是新增未跟踪文件，`git checkout --` 无效 → 用 `Write` + `Edit` **整文件重写**恢复，
   之后 `--headless` 重跑生成器与 40 条契约均通过。
   **教训（与 Handoff 里 T029 的同名事故一致）**：工程源码一律用编辑工具改，不用 PowerShell 管道写回。

## 5. 未验证 / 边界

- **没做性能实测**：这张关有 48 个 mesh（含 5 块巨石 ~7.5k tris/块）。`tool_perf_probe.gd` 未跑，
  帧率 `NOT-RUN`；本关不参与正式流程，暂不影响玩法性能预算。
- **没做 960×540 / 其它分辨率取证**：只在 1280×720 下取景。
- **没有真人视觉评审**：vision 服务未调用，以上判读是截图人工对比。
- **未接入正式流程**：`main.tscn` 仍走 `l_courtyard`（契约断言 `main_scene_not_referencing_ravine` 守着）。
- **资产仍卡授权**：写实水面/河床/地表散布/石墙替换属素材升级，需负责人按 `Docs/ART08_CHARACTER_ASSET_REGISTER.md`
  同一套授权门逐项确认。

## 6. 恢复入口

删除本阶段新增的 4 个脚本 + `scenes/maps/l_ravine_board.tscn` + `Art/Probes/art09_board_after/` 即可完全回退；
`l_courtyard.tscn`、`tool_make_courtyard.gd` 与 ART07 未提交改动**未被触碰**。
