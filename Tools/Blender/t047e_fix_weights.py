"""T047 修复尝试：对肩/髋折痕做**权重平滑 + 归一 + 限 4 影响**，导出 SM_Cat_006.glb。

依据（T047 量测）：`SM_Cat_005` 在动画自身的极值帧上出现折痕塌陷
（Run f0：塌陷 236 面 / 拉丝 120 面；Walk f2：182 / 159，最小面积比 0.067~0.075），
根因是源权重在腿根折痕处过于"硬"（单骨主导、过渡带窄）。

做法（只动权重，不动网格/UV/动画）：
1. 导入 `SM_Cat_005.glb`（fps 必须先设 30，否则动画时长被压）；
2. 对四条腿根骨骼（`Bone.011/015/019/023`）的权重组做 `vertex_group_smooth`
   （factor 0.5、repeat 2、expand 0.35），把过渡带撑宽；
3. `vertex_group_normalize_all` + `vertex_group_limit_total(limit=4)`（glTF 上限）；
4. 打印权重统计（零权重/和≠1/影响数分布）后导出 `SM_Cat_006.glb`。

用法：
  blender --background --factory-startup --python Tools/Blender/t047e_fix_weights.py -- \
      --in Art/Exports/Cat/SM_Cat_005.glb --out Art/Exports/Cat/SM_Cat_006.glb
"""
import sys
import os
import json

import bpy

REPO = "E:/Reborn"
LEG_ROOTS = ["Bone.011", "Bone.015", "Bone.019", "Bone.023"]
# 折痕另一侧：躯干/骨盆/胸（让过渡带能"拉"过来）
TRUNK = ["Bone", "Bone.001", "Bone.002"]


def log(m):
    print("T047E|%s" % m, flush=True)


def arg(name, default=None):
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if name in rest and rest.index(name) + 1 < len(rest):
            return rest[rest.index(name) + 1]
    return default


def weight_stats(obj):
    me = obj.data
    hist = {}
    zero = 0
    dev = 0
    for v in me.vertices:
        gs = [g for g in v.groups if g.weight > 1e-6]
        hist[len(gs)] = hist.get(len(gs), 0) + 1
        if not gs:
            zero += 1
        elif abs(sum(g.weight for g in gs) - 1.0) > 1e-3:
            dev += 1
    return {"hist": {str(k): v for k, v in sorted(hist.items())}, "zero": zero, "sum_dev": dev}


def main():
    src = arg("--in", REPO + "/Art/Exports/Cat/SM_Cat_005.glb")
    dst = arg("--out", REPO + "/Art/Exports/Cat/SM_Cat_006.glb")
    if os.path.exists(dst):
        log("ERROR|out_exists|%s" % dst)
        log("done")
        return 1

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    bpy.ops.import_scene.gltf(filepath=src)
    obj = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: len(o.data.polygons))
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    log("import|obj=%s|groups=%d|before=%s" % (obj.name, len(obj.vertex_groups), json.dumps(weight_stats(obj))))

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")

    names = [g.name for g in obj.vertex_groups]
    targets = [n for n in LEG_ROOTS + TRUNK if n in names]
    for name in targets:
        idx = names.index(name)
        obj.vertex_groups.active_index = idx
        bpy.ops.object.vertex_group_smooth(group_select_mode="ACTIVE", factor=0.5,
                                           repeat=2, expand=0.35)
        log("smooth|%s|ok" % name)

    # 顺序很重要：先限 4（glTF 上限，会丢掉多余影响）再归一，否则归一后被截断的顶点
    # 权重和会重新 <1（第一版实测 408 个顶点和≠1）。
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    log("after|%s" % json.dumps(weight_stats(obj)))

    bpy.ops.export_scene.gltf(
        filepath=dst, export_format="GLB", use_selection=False, export_yup=True,
        export_materials="EXPORT", export_cameras=False, export_lights=False,
        export_extras=False, export_texcoords=True, export_normals=True,
        export_skins=True, export_animations=True, export_apply=False,
    )
    log("export|%s|bytes=%d" % (dst, os.path.getsize(dst)))
    log("done")
    return 0


sys.exit(main())
