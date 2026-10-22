# ART03-④（鼠）：换 CC-BY 源 → `SM_Mouse_002.glb`（带 23 骨 / 4 段动画）

**状态**：done（视觉已接入关卡，实机图已自查）——**不是**正式美术 approved。
**编号**：ART03 是美术流水线任务。**注意**：鼠是**关键角色**，本任务只做了"视觉替换"，
**没有**接动画播放逻辑，也没有动任何玩法数值；正式 `approved` 只能由负责人置位。

## 1. 为什么换源（负责人 2026-10-21 决策：选 C）

| 候选 | 结论 |
|---|---|
| `mouse_arribadaclub`（原登记） | **展平的老鼠标本扫描件**：没腿、头身糊在一起 → 不能当活体角色 |
| `mouse_charliecatling` | 最像家鼠，但许可 **Free Standard（限制再分发）+ NoAI** → 与"资产入库 + AI 参与处理"冲突，弃用 |
| **`mouse_cc_mehrus_rat`** | **CC-BY**、3,602 tris、**4 段动画** → 选定 |
| `mouse_cc_artise1_rat` | CC-BY、1,892 tris、4 段动画；更像塑料玩具 → 备选未用 |

> 搜源方法可复现：Sketchfab 公开搜索 API，硬条件 `licenses=cc0,by` + `downloadable` +
> `animationCount>=1` + `500<=faces<=20000` + 排除鼠标外设关键词。命中只有这 2 个真正的鼠类。

**已知风格落差**：这是 **rat（大鼠）** 体态（头钝身厚），不是家鼠"圆脸大耳尖吻"。
负责人已知情并选择按 ① 走。

## 2. 源件实测（Blender 3.3.1 读回）

| 项 | 值 |
|---|---|
| 文件 | `references/_downloads/mouse_cc_mehrus_rat/rat.glb`，**470,424 B**（与 Sketchfab API 的 size 一致），sha256 `aefd6762…` |
| 网格 | 3,602 tris / 2,270 verts / **1 材质槽** / 1×1024² 贴图 |
| 骨骼 | **23 骨**（`_rootJoint` 起；含 Tail1–4、四肢各 2 段、Body/Neck/Head/HeadTop/Jaw/Eye_l/Eye_r），23 个顶点组 |
| 动画 | **4 段**：`Iddle`(0–33f) / `Walk`(0–25f) / `Run`(0–10f) / `Eat`(0–15f) |
| 材质 | **unlit**：`Emission + Transparent + MixShader + LightPath`（必须重建，见下） |
| 网格坐标 | 数据里带巨大偏移（local y≈80–94、z≈356–362），父级链带 2.6e‑3 与 100× 缩放 |

## 3. 处理（`Tools/Blender/art08_mouse_from_ref.py`）

1. 保住 `matrix_world` 再烘（glTF 网格 Y-up；围栏/洞口已踩过）。
2. **重建材质**：unlit → `Principled BSDF`（BaseColor=Image_0 / Roughness 0.8 / Metallic 0），1 槽。
3. **判朝向**：用"头/颈骨权重顶点"与"尾骨权重顶点"的 Y 质心 —— 实测 head_y=−0.90、tail_y=+1.96
   → 头朝 −Y，**绕 Z 转 180°** 后 head_y=+0.90（项目契约：Blender 面朝 +Y = Godot −Z）。
   ⚠ 踩坑：glTF 导入对象 `rotation_mode` 是 **QUATERNION**，写 `rotation_euler` **完全无效**（第一版白跑），
   必须 `o.matrix_world = Matrix.Rotation(pi,4,'Z') @ o.matrix_world`。
4. **归一尺度**：按"去掉尾巴的身体长度"= 2.4015 → 目标 **0.135 m**，`factor=0.056215`；
   结果 `dims=(0.0552, 0.2245, 0.0706)`（含尾巴 0.2245，身高 0.0706）。
5. **原点**：脚印中心 + 脚底 `z=0`（Idle 第 0 帧实测包围盒）。
6. **导出 4 段动画**：把 4 个 action 各塞进一条 **NLA 轨道**，`export_nla_strips=True`。
   但 Blender 3.3 会**按节点**额外吐 7 段常量动画（Sketchfab_model / RootNode / Rat …，各 3 通道）
   → 脚本在 GLB 的 JSON 块里裁掉，只留 `Eat,Idle,Run,Walk`。轨道名也规范成这 4 个。

产物：`Art/Exports/Mouse/SM_Mouse_002.glb`，**501,512 B**，sha256 `d27a5534…`；
读回校验 `nodes=32|meshes=1|materials=1|images=1|skins=1|animations=4|joints=23`。

## 4. 接入

- `Game/Reborn/assets/characters/mouse/sm_mouse_002.glb`（+贴图 `.import`）。
- `resources/species/mouse.tres`：`load_steps 3→4`，新增 `[ext_resource ... id="3_vis"]` +
  `visual_scene = ExtResource("3_vis")`。**胶囊数值一字未改**（r=0.06 / half_height=0.09 / can_jump=false /
  can_use_mouse_tunnel=true）。
- 走的是猫那套既有机制：`AnimalBody._rebuild_visual()` 实例化 `visual_scene`，
  `body_mesh` 退化为隐藏的尺寸代理，`_sync_visual()` 把视觉下沉 `−capsule_height/2` 并做蹲姿压缩。
- **没有**接动画播放（鼠的 Idle/Walk/Run 选播属 P6/后续任务）；本轮 Godot 侧只证明动画资源真的在。

## 5. 测试与证据

| 项 | 结果 |
|---|---|
| `tests/run_art03_mouse.gd` | **39/39 通过**（资产 25 条 + 配置 7 条 + 运行 7 条） |
| 实机图 | `Art/Probes/art08_mouse_side.png`、`art08_mouse_q34.png`（工具 `tests/tool_capture_art08.gd`） |
| 实机事实 | `visual=sm_mouse_002.glb`、`body_mesh_visible=false`、`bones=23`、`anims=["Eat","Idle","Run","Walk"]`、`playing=Idle` |
| Blender 侧取图 | `Art/Probes/art08_mehrus_v3_{q34,side,front,top}.png` |
| 全量回归 | **30 套 / 3,167 条 / 0 失败** |

**顺带更新的两处过时断言**（行为已按设计改变，不是"改测试凑绿"）：
1. `run_art02_cat.gd`：`mouse_visual_still_placeholder` → 改为
   `mouse_visual_is_mouse_asset` + `mouse_visual_not_cat_asset`（"各物种指向自己的资产、不串台"）。
2. `run_t021_capture.gd`：`D_prey_mesh_visible` 原来只看 `body_mesh`（有 `visual_scene` 后它恒隐藏）
   → 改为"`visual_root` 或 `body_mesh` 任一可见"。

## 6. 边界（不算完成的事）

- **不是 approved**；鼠是**大鼠**剪影，不是家鼠。
- **动画还没播**：Godot 里 `AnimationPlayer` 有 4 段，但 `AnimalBody` 没有选播逻辑（Idle/Walk/Run 切换、动画速率跟速度对齐都未做）。
- 视觉比胶囊略长（0.2245 m 含尾巴 vs 胶囊直径 0.12 m）→ 尾巴会伸出碰撞体，属预期。
- 蹲姿仍用 `_sync_visual()` 的竖向压缩近似（无蹲姿动画）。
- 未推送、未发布。

## 7. 动画接线（ART03-⑤，本轮收尾）

> **来源说明**：`animal_body.gd` 里这段视觉动画代码在我接手"本轮收尾"时**已经在工作区里未提交**
> （不是我写的）。我做了三件事：① 逐行复核（只读速度、缺动画不崩、不写玩法状态）；
> ② 补 6 条断言把它验成事实；③ 与我的改动一起提交，提交信息里写明来源。

- 实现：`_bind_visual_animation()` 在 `_rebuild_visual()` 末尾绑定子树里的 `AnimationPlayer`；
  把 `Idle/Walk/Run` 的 `loop_mode` 设为 `LOOP_LINEAR`（glTF 导进来是 `NONE`）；
  `_update_visual_animation(speed)` 每物理帧按**实际水平速度**选 clip，并把 `speed_scale`
  按 `speed / walk_speed`（Run 用 `sprint_speed`）夹到 [0.5, 1.8] / [0.6, 1.6]。
- 硬约束：**不写** `velocity` / `move_intent`；找不到 clip 就保持不动；没有 `AnimationPlayer` 的物种
  （猫的 glb 没有动画）完全不受影响。
- 验证（`run_art03_mouse.gd` 新增 6 条）：`anim_bound` / 静止→`Idle` / 走动→`Walk` /
  冲刺→`Run` / 跑比走快 / 停下回 `Idle`；实测 `walk_speed=1.100 | run_speed=3.000`。

## 8. 场景渲染实测基线（本轮补的客观数字）

工具：`tests/tool_perf_probe.gd`（**非 headless**，关 vsync、不限帧，按墙钟测 240 帧）。

```
PERF|res=1280x720|warmup=60|sample=240
PERF|frame_ms|avg=1.662|p50=1.514|p95=2.407|max=2.613|avg_fps=601.6
PERF|primitives|avg=111028|peak=111028
PERF|draw_calls|avg=32|peak=32
PERF|objects_in_frame|peak=112
```

结论：石墙平铺 90 件后**墙体三角形 ≈111k / 32 draw call，在 1280×720 下单帧 1.5–2.6 ms**，
不是瓶颈。**注意口径**：单机单视角、无动态角色、非正式发行构建；第一次用
`Performance.TIME_PROCESS` 采样得到"恒定 84.077 ms"是**测量假象**（窗口被合成器节流），
已改成墙钟计时。
