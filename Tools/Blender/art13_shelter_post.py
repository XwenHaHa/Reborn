# -*- coding: utf-8 -*-
"""ART03-⑮-2 `ENV_SHELTER_POST_001`：庇护棚东侧门框立柱（同时给棚顶补上支撑）。

## 为什么需要
1. **结构**：棚顶（3.4 × 0.2 × 3.8）东侧是敞开的大门洞，原先**没有任何支撑**，看起来浮在半空。
2. **收边**：矮墙模块是**平板扫描件**，两端是开口壳体；门洞两侧的直立端露在外面，
   近景能看到端面壳与石缝的"薄片感"。门框立柱正好把这两处端头压住。
   第一版试过用堆石（压角石）收边，实机像"随手一堆石头"且砂岩色与墙石不搭，已废弃。

## 做法
程序化建模（不依赖第三方件）：截面 0.16 × 0.36 m（覆盖矮墙 0.20 厚 + 两侧石块外凸 0.30）、
高 1.62 m 的木立柱，四条竖棱做 45° 倒角、顶部略收，原点 = 脚印中心 + 底面 z = 0。
材质 `MAT_Shelter_Post_Wood`：深棕 (0.062, 0.040, 0.023) linear、roughness 0.85、无贴图
（比 `SM_Roof_001` 的 `MAT_Roof_Plank` (0.048, 0.030, 0.017) 亮约 1.3 倍，同一套木料观感；
第一版用了 4 倍亮的中棕，实机看着像塑料立柱，已压暗对齐棚顶）。
面数预算 ≤ 120 tris。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art13_shelter_post.py'
"""

import hashlib
import os
import sys

import bmesh
import bpy
from mathutils import Vector

REPO = "E:/Reborn"
GLB_OUT = REPO + "/Art/Exports/Environment/SM_Shelter_Post_001.glb"
POST_W = 0.16          # X：沿墙厚之外的宽度（把墙端整片压住）
POST_D = 0.36          # Y：覆盖矮墙 0.20 厚 + 两侧石块外凸（石块 0.30）
POST_H = 1.62          # Z：地面 0.10 → 棚顶下沿 1.70，略咬进棚顶 2 cm
CHAMFER = 0.012
TRI_BUDGET = 120
failures = []


def log(s):
    sys.stdout.write("PROBE|" + s + "\n")
    sys.stdout.flush()


def require(cond, msg):
    if not cond:
        failures.append(msg)
        sys.stdout.write("PROBE|FAIL|" + msg + "\n")
        sys.stdout.flush()
    return cond


def main():
    log("start|blender=%s" % bpy.app.version_string)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, POST_H * 0.5))
    obj = bpy.context.active_object
    obj.name = "ENV_SHELTER_POST_001"
    obj.scale = (POST_W, POST_D, POST_H)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # 四条竖棱倒角；顶部再收 4%（木柱常见的锥度）
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    vertical = []
    for e in bm.edges:
        d = (e.verts[0].co - e.verts[1].co)
        if abs(d.x) < 1e-6 and abs(d.y) < 1e-6 and abs(d.z) > 0.5:
            vertical.append(e)
    log("edges|vertical=%d" % len(vertical))
    bmesh.ops.bevel(bm, geom=vertical, offset=CHAMFER, segments=1, affect="EDGES")
    top_z = max(v.co.z for v in bm.verts)
    for v in bm.verts:
        if v.co.z > top_z - 1e-6:
            v.co.x *= 0.96
            v.co.y *= 0.96
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()

    mat = bpy.data.materials.new("MAT_Shelter_Post_Wood")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.062, 0.040, 0.023, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.material_index = 0

    # 原点 = 脚印中心 + 底面 z=0
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    off = Vector(((min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5, min(zs)))
    for v in obj.data.vertices:
        v.co -= off
    obj.data.update()

    obj.data.calc_loop_triangles()
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    dims = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    tris = len(obj.data.loop_triangles)
    log("final|tris=%d|dims=(%.4f, %.4f, %.4f)|min_z=%.4f|slots=%d" % (
        tris, dims[0], dims[1], dims[2], min(zs), len(obj.data.materials)))
    require(tris <= TRI_BUDGET, "tri_budget|%d" % tris)
    require(abs(min(zs)) < 5e-4, "not_grounded")
    require(abs(dims[2] - POST_H) < 1e-2, "height|%.4f" % dims[2])
    require(abs(dims[0] - POST_W) < 1e-3, "width|%.4f" % dims[0])
    require(abs(dims[1] - POST_D) < 1e-3, "depth|%.4f" % dims[1])
    require(len(obj.data.materials) == 1, "slots|%d" % len(obj.data.materials))

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    wanted = {
        "export_format": "GLB", "use_selection": True, "export_apply": True,
        "export_yup": True, "export_materials": "EXPORT", "export_cameras": False,
        "export_lights": False, "export_extras": False, "export_texcoords": True,
        "export_normals": True, "export_colors": False,
        "export_skins": False, "export_animations": False,
    }
    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=GLB_OUT, **{k: v for k, v in wanted.items() if k in props})
    with open(GLB_OUT, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (GLB_OUT, len(data), hashlib.sha256(data).hexdigest()))
    log("done|tris=%d|failures=%d" % (tris, len(failures)))
    sys.exit(0 if not failures else 1)


main()
