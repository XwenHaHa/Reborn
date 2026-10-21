# Evidence：ART03-④（鼠换源）mehrus rat 接入（2026-10-21，本机系统时钟）

任务规格：`Docs/Tasks/ART03_MOUSE.md`。环境：Blender 3.3.1、Godot 4.7.2-stable console。

## 1. 选源（可复现，匿名只读 API）

Sketchfab 公开搜索 API：`type=models&q=<mouse|mice|rodent|muridae>&downloadable=true&licenses=cc0,by`
再在本地按 `animationCount>=1`、`500<=faceCount<=20000`、排除鼠标外设关键词过滤。命中：

```
ROW|mouse_cc_mehrus_rat|faces=3602|verts=1808|anim=4|likes=56|lic=CC Attribution|by=Mehrus
ROW|mouse_cc_artise1_rat|faces=1892|verts=977|anim=4|likes=84|lic=CC Attribution|by=Artise1
```

详情（`/v3/models/<uid>`，含缩略图落盘 + sha256 前缀）：
`DETAIL|mehrus_rat|lic=CC Attribution|faces=3602|verts=1808|anim=4|dl=True`
`DESC|mehrus_rat|Practice modelling of a Brown Rat (Rattus Norvegicus). Slightly stylized this time.`

## 2. 下载（用已登录会话取签名直链；令牌未落盘、未入日志）

浏览器内 `fetch('/v3/models/978e06562faa4c95b842d451ed23338c/download')` → 200，
`formats=[source,gltf,usdz,glb]`、`glb.size=470424`。

```
downloaded=470424 bytes     # 与 API 声明的 size 完全一致
sha256=aefd676224f3c873728537ed7105416b05731e5b2ba71eb43c701fdc52ac7be9
```

落盘：`references/_downloads/mouse_cc_mehrus_rat/rat.glb`（该目录已 gitignore）。

## 3. 源件读回（Blender）

```
PROBE|src|tris=3602|verts=2270|slots=1|bones=23|vgroups=23|actions=4
PROBE|bones|_rootJoint,Bone_00,Back_01,Hip_02,Tail1_03,Tail2_04,Tail3_05,Tail4_06,
       FrontLeg1_l_07,FrontLeg2_l_08,BackLeg1_l_09,BackLeg2_l_010,FrontLeg1_r_011,FrontLeg2_r_012,
       BackLeg1_r_013,BackLeg2_r_014,Body_015,Neck_016,Head_017,HeadTop_018,Jaw_019,Eye_l_020,Eye_r_021
PROBE|actions|Armature|Eat_Object_5(0-15),Armature|Iddle_Object_5(0-33),
       Armature|Run_Object_5(0-10),Armature|Walk_Object_5(0-25)
PROBE|material_src|Material|nodes=EMISSION,LIGHT_PATH,BSDF_TRANSPARENT,MIX_SHADER,OUTPUT_MATERIAL,TEX_IMAGE
```

## 4. 处理与产物

```
& 'D:\SoftWare\Blender\blender.exe' --background --factory-startup `
    --python 'E:\Reborn\Tools\Blender\art08_mouse_from_ref.py' -- --stage all      # EXIT=0
```

```
PROBE|material_out|slots=1|name=MAT_Mouse_Fur
PROBE|head_tail|head_verts=639|tail_verts=105|head_y=-0.9045|tail_y=1.9612
PROBE|rotated|180deg_about_z|head_y=0.9045|tail_y=-1.9612
PROBE|scale|body_len_before=2.4015|factor=0.056215|dims_after=(0.0552, 0.2245, 0.0706)
PROBE|final|dims=(0.0552, 0.2245, 0.0706)|min=(-0.0276, -0.1123, -0.0000)|max=(0.0276, 0.1123, 0.0706)
PROBE|action_fcurves|Eat kept=107|Iddle kept=101|Run kept=122|Walk kept=66
PROBE|nla|track=Eat|Idle|Run|Walk
PROBE|prune|removed=7|kept=Eat,Idle,Run,Walk
PROBE|glb|path=E:/Reborn/Art/Exports/Mouse/SM_Mouse_002.glb|bytes=501512|sha256=d27a5534...
PROBE|glb_json|nodes=32|meshes=1|materials=1|images=1|skins=1|animations=4|joints=23
PROBE|done|failures=0
```

## 5. Godot 读回（不猜结构）

```
DUMP|skeleton|bones=23|names=_rootJoint,...Eye_r_021
DUMP|skin|binds=23|joints=...23 根
DUMP|skin_weights|verts=2270|weight_sum_min=1.0000|weight_sum_max=1.0000|max_bones_per_vertex=4
DUMP|anim_player|animations=4|names=Eat,Idle,Run,Walk
DUMP|animation|name=Eat|length=0.625000 / Idle 1.375000 / Run 0.416667 / Walk 1.041667
DUMP|mesh|aabb_size=(0.055227, 0.204321, 0.084965)|tris=3602
DUMP|surface|material=MAT_Mouse_Fur|roughness=0.800|metallic=0.000|emission_enabled=false
```

## 6. 验收套件（新增）

```
& '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' `
    --script 'res://tests/run_art03_mouse.gd' --quit-after 30000
```

```
MEASURE|mesh|tris=3602|aabb_size=(0.055227, 0.204321, 0.084965)|surfaces=1
MEASURE|anims|names=["Eat", "Idle", "Run", "Walk"]
MEASURE|runtime|visual=res://assets/characters/mouse/sm_mouse_002.glb|pos=(0.0, -0.09, 0.0)|cap_h=0.1800|skeleton_bones=23
SUMMARY|checks=39|failures=0
RESULT|PASS
```

## 7. 实机图（`tests/tool_capture_art08.gd`）

```
CAP|art08|body|pos=(2.0, 0.189422, 12.0)|visual=res://assets/characters/mouse/sm_mouse_002.glb|visual_pos=(0.0, -0.09, 0.0)|body_mesh_visible=false
CAP|art08|visual|bones=23|anims=["Eat", "Idle", "Run", "Walk"]
CAP|art08|anim|playing=Idle
CAP|art08|art08_mouse_side|save_result=0 (OK)
CAP|art08|art08_mouse_q34|save_result=0 (OK)
```

**视觉自查（直接 Read PNG）**：鼠在庭院地面上正常渲染——褐色毛、粉爪、长尾、有接触阴影；
X 型四足站姿，前爪抬起（Idle 动画在播），没有浮空/陷地/材质发白。

## 8. 回归与两处断言更新

全量 **30 套 / 3,167 条断言 / 0 失败 / 每套 EXIT=0 / `SCRIPT ERROR` 0**。

首轮跑出 2 条挂（都是"鼠还是胶囊"时代的过时预期，已按设计更新并在任务文档 §5 记录）：
1. `run_art02_cat.gd::mouse_visual_still_placeholder`（当初用来保证 ART02 只动猫）→
   改为 `mouse_visual_is_mouse_asset` + `mouse_visual_not_cat_asset`。
2. `run_t021_capture.gd::D_prey_mesh_visible`（只看 `body_mesh`）→ 改为 `visual_root` 或 `body_mesh` 任一可见。

## 9. 未做 / 未验证

- 动画**没有**接播放逻辑（Godot 里资源存在、能手动 play，但 `AnimalBody` 不会按速度切 Idle/Walk/Run）。
- 未由负责人视觉验收 → 不写 approved；鼠是 **rat 体态**，不是家鼠。
- 未推送、未发布。
