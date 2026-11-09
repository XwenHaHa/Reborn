"""T046-A：猫面部 UV 返工 —— 整体重展开 + 从旧贴图烘焙到新 UV。

背景（`Docs/Evidence/T046.md` §3）：现役 `SM_Cat_004.glb` 的面部（`Bone.004` 组）
有 545 个三角的 UV 各向异性 >4×（p95 14×、max 85.8），导致面部贴图被压缩。

做法（只动 UV 与贴图映射，**不动网格、骨骼、权重、动画**）：
1. 导入 `SM_Cat_004.glb`（含 33 骨 + Idle/Walk/Run 三段动画）。
2. 保留旧 UV 为 `UVMap_old`，新建 `UVMap` 并整体 Smart UV Project 重展开。
3. 用 Cycles bake 把**旧 UV 采样到的基础色 / 切线空间法线**写进新 UV 的两张 2048² 贴图。
4. 重建 `MAT_Cat_Fur` 节点（新贴图 + 法线，色彩空间 sRGB / Non-Color），`MAT_Cat_Detail` 保持无贴图。
5. 删掉旧 UV 层（只留一层，避免 glTF 导出 TEXCOORD_1 造成引擎侧歧义），导出 `SM_Cat_005.glb`。

用法：
  blender --background --factory-startup --python Tools/Blender/t046b_cat_head_uv.py -- \
      --in Art/Exports/Cat/SM_Cat_004.glb --out Art/Exports/Cat/SM_Cat_005.glb [--size 2048]

输出：`T046B|key=value`，最后 `T046B|done`。
"""
import sys
import os
import json
import math

import bpy

REPO = "E:/Reborn"


def log(msg):
    print("T046B|%s" % msg, flush=True)


def arg(name, default=None):
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if name in rest:
            i = rest.index(name)
            if i + 1 < len(rest):
                return rest[i + 1]
    return default


def main():
    src = arg("--in", "Art/Exports/Cat/SM_Cat_004.glb")
    dst = arg("--out", "Art/Exports/Cat/SM_Cat_005.glb")
    size = int(arg("--size", "2048"))
    for p in (src, dst):
        if not os.path.isabs(p):
            p = os.path.join(REPO, p)
    src = src if os.path.isabs(src) else os.path.join(REPO, src)
    dst = dst if os.path.isabs(dst) else os.path.join(REPO, dst)
    if os.path.exists(dst):
        log("ERROR|out_exists|%s" % dst)
        log("done")
        return 1

    bpy.ops.wm.read_factory_settings(use_empty=True)
    # fps 必须在**导入之前**设：glTF 导入会把秒换算成帧，导入后再改 fps 只会改变
    # 导出时的帧→秒换算，动画会被整体缩短（2026-11-09 实测：Run 0.208 → 0.167 → 0.133 s，
    # 直接把 run_art02_cat 的 anim_run_length（>0.2 s）判红）。
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    obj = max(meshes, key=lambda o: len(o.data.polygons))
    me = obj.data
    me.calc_loop_triangles()
    log("import|meshes=%d|armatures=%d|obj=%s|tris=%d|slots=%d|bones=%d|actions=%d" % (
        len(meshes), len(arms), obj.name, len(me.loop_triangles), len(me.materials),
        len(arms[0].data.bones) if arms else 0, len(bpy.data.actions)))

    # ---- 1) 旧 UV 备份 + 新 UV 层 -------------------------------------------
    old_layer = me.uv_layers[0] if len(me.uv_layers) > 0 else None
    if old_layer is None:
        log("ERROR|no_uv_layer")
        log("done")
        return 1
    old_layer.name = "UVMap_old"
    new_layer = me.uv_layers.new(name="UVMap")
    for i, d in enumerate(old_layer.data):
        new_layer.data[i].uv = d.uv
    me.uv_layers.active = new_layer
    new_layer.active_render = True
    log("uv|layers=%d|old=%s|new=%s" % (len(me.uv_layers), old_layer.name, new_layer.name))

    # ---- 2) 整体重展开（Smart UV Project） ----------------------------------
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.004,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    log("unwrap|smart_project|angle=66|margin=0.004")

    # ---- 3) 准备烘焙目标 ----------------------------------------------------
    fur = None
    for slot in obj.material_slots:
        if slot.material and "Fur" in slot.material.name:
            fur = slot.material
    if fur is None:
        log("ERROR|no_fur_material")
        log("done")
        return 1

    base_img = bpy.data.images.new("Cat_BaseColor_005", size, size, alpha=False)
    base_img.colorspace_settings.name = "sRGB"
    nrm_img = bpy.data.images.new("Cat_Normal_005", size, size, alpha=False, float_buffer=False)
    nrm_img.colorspace_settings.name = "Non-Color"

    nt = fur.node_tree
    nodes = nt.nodes
    links = nt.links

    # 旧贴图改走 UVMap_old，保证"从旧映射采样"
    uv_old = nodes.new("ShaderNodeUVMap")
    uv_old.uv_map = "UVMap_old"
    uv_old.location = (-900, 0)
    for node in list(nodes):
        if node.type == "TEX_IMAGE":
            links.new(uv_old.outputs["UV"], node.inputs["Vector"])

    tex_base = nodes.new("ShaderNodeTexImage")
    tex_base.image = base_img
    tex_base.location = (-600, 400)
    tex_base.select = True
    nodes.active = tex_base

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 1
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    scene.render.bake.margin = 8
    bpy.ops.object.bake(type="DIFFUSE")
    log("bake|base|size=%d|ok" % size)

    tex_nrm = nodes.new("ShaderNodeTexImage")
    tex_nrm.image = nrm_img
    tex_nrm.location = (-600, 0)
    tex_base.select = False
    tex_nrm.select = True
    nodes.active = tex_nrm
    scene.render.bake.normal_space = "TANGENT"
    bpy.ops.object.bake(type="NORMAL")
    log("bake|normal|size=%d|ok" % size)

    # ---- 4) 重建 Fur 材质 ---------------------------------------------------
    for node in list(nodes):
        if node.type in ("TEX_IMAGE", "NORMAL_MAP", "UVMAP", "INVERT"):
            nodes.remove(node)
    bsdf = None
    out = None
    for node in nodes:
        if node.type == "BSDF_PRINCIPLED":
            bsdf = node
        if node.type == "OUTPUT_MATERIAL":
            out = node
    if bsdf is None or out is None:
        log("ERROR|missing_bsdf")
        log("done")
        return 1

    n_base = nodes.new("ShaderNodeTexImage")
    n_base.image = base_img
    n_base.location = (-500, 300)
    links.new(n_base.outputs["Color"], bsdf.inputs["Base Color"])

    n_nrm = nodes.new("ShaderNodeTexImage")
    n_nrm.image = nrm_img
    n_nrm.location = (-500, 0)
    n_map = nodes.new("ShaderNodeNormalMap")
    n_map.location = (-250, 0)
    links.new(n_nrm.outputs["Color"], n_map.inputs["Color"])
    links.new(n_map.outputs["Normal"], bsdf.inputs["Normal"])
    if "Roughness" in bsdf.inputs:
        bsdf.inputs["Roughness"].default_value = 0.72
    if "Specular" in bsdf.inputs:
        bsdf.inputs["Specular"].default_value = 0.25
    log("material|%s|base=%s|normal=%s" % (fur.name, base_img.name, nrm_img.name))

    # ---- 5) 只留一层 UV -----------------------------------------------------
    names = [l.name for l in me.uv_layers]
    if "UVMap_old" in names:
        me.uv_layers.remove(me.uv_layers[names.index("UVMap_old")])
    me.uv_layers[0].name = "UVMap"
    me.uv_layers[0].active_render = True
    log("uv|final_layers=%d|name=%s" % (len(me.uv_layers), me.uv_layers[0].name))

    # ---- 6) 导出 -----------------------------------------------------------
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=dst,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_texcoords=True,
        export_normals=True,
        export_skins=True,
        export_animations=True,
        export_apply=False,
    )
    me.calc_loop_triangles()
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for v in me.vertices:
        w = obj.matrix_world @ v.co
        for k in range(3):
            mn[k] = min(mn[k], w[k])
            mx[k] = max(mx[k], w[k])
    log("export|%s|bytes=%d" % (dst, os.path.getsize(dst)))
    log("check|tris=%d|slots=%d|actions=%d|dims=(%.4f,%.4f,%.4f)|min=(%.4f,%.4f,%.4f)" % (
        len(me.loop_triangles), len(me.materials), len(bpy.data.actions),
        mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2], mn[0], mn[1], mn[2]))
    log("done")
    return 0


sys.exit(main())
