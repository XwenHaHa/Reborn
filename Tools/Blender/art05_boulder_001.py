# -*- coding: utf-8 -*-
"""ART03-② ENV_BOULDER_001：把 Poly Haven CC0 巨石 boulder_01 做成合规静态资产。

源（**只读**）：references/environment/boulder/candidates/boulder_01_polyhaven_gltf_1k/boulder_01.gltf
实测源：66,122 tris / 1.272 × 1.830 × 1.004 m（**米制，无需缩放**）
预算（Docs/ART_ASSET_SPEC.md §2）：巨石 1k–8k tris

处理：减面到预算内 → 原点移到"脚印中心 + 底面 z=0" → 渲染 → 导出 GLB。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art05_boulder_001.py' -- --stage all
"""

import hashlib
import math
import os
import sys

import bpy
from mathutils import Vector

REPO = "E:/Reborn"
REF = REPO + "/references/environment/boulder/candidates/boulder_01_polyhaven_gltf_1k/boulder_01.gltf"
GLB_OUT = REPO + "/Art/Exports/Environment/SM_Boulder_001.glb"
RENDER_DIR = REPO + "/Art/Probes"

TARGET_TRIS = 7500        # 预算上限 8000，留余量
TRI_BUDGET = 8000

failures = []


def log(s):
    sys.stdout.write("PROBE|" + s + "\n")
    sys.stdout.flush()


def fail(s):
    failures.append(s)
    sys.stdout.write("PROBE|FAIL|" + s + "\n")
    sys.stdout.flush()


def require(cond, msg):
    if not cond:
        fail(msg)
    return cond


def vec(v):
    return "(%.4f, %.4f, %.4f)" % (v[0], v[1], v[2])


def meshes():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def bbox():
    """从顶点算（`bound_box` 是缓存，改过顶点后不可信）。"""
    mn = Vector((1e18, 1e18, 1e18))
    mx = Vector((-1e18, -1e18, -1e18))
    for o in meshes():
        mw = o.matrix_world
        for v in o.data.vertices:
            w = mw @ v.co
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return mn, mx


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    w = bpy.data.worlds.new("W")
    scene.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.28, 0.30, 0.33, 1.0)
    bg.inputs["Strength"].default_value = 0.55
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    g = bpy.context.active_object
    g.name = "RENDER_Ground"
    m = bpy.data.materials.new("MAT_RENDER_Ground")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.30, 0.31, 0.33, 1.0)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    g.data.materials.append(m)

    def light(name, loc, energy, sz):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = sz
        ob = bpy.data.objects.new(name, ld)
        ob.location = loc
        ob.rotation_euler = (Vector((0.0, 0.0, 0.5)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(ob)

    light("KEY", (2.0, -2.0, 2.6), 900.0, 2.0)
    light("FILL", (-2.4, -1.2, 1.2), 350.0, 2.4)
    light("RIM", (0.4, 2.6, 1.8), 500.0, 1.6)
    cam_data = bpy.data.cameras.new("CAM")
    cam_data.lens = 55.0
    cam = bpy.data.objects.new("CAM", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def render_views(cam):
    target = Vector((0.0, 0.0, 0.45))
    for name, loc in [("q34", (2.6, -2.8, 1.7)), ("side", (0.0, -3.4, 1.2)), ("front", (3.4, 0.0, 1.2))]:
        cam.location = Vector(loc)
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.render.filepath = "%s/art05_boulder_%s.png" % (RENDER_DIR, name)
        bpy.ops.render.render(write_still=True)
        log("render|%s" % name)


def export_glb():
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        if o.type == "MESH" and not o.name.startswith("RENDER_"):
            o.select_set(True)
    rna = bpy.ops.export_scene.gltf.get_rna_type()
    props = set(rna.properties.keys())
    wanted = {
        "export_format": "GLB", "use_selection": True, "export_apply": True,
        "export_yup": True, "export_materials": "EXPORT", "export_cameras": False,
        "export_lights": False, "export_extras": False, "export_texcoords": True,
        "export_normals": True, "export_colors": False,
        "export_skins": False, "export_animations": False,
    }
    applied = {k: v for k, v in wanted.items() if k in props}
    bpy.ops.export_scene.gltf(filepath=GLB_OUT, **applied)
    with open(GLB_OUT, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (GLB_OUT, len(data), hashlib.sha256(data).hexdigest()))


def main():
    log("start|blender=%s|src=%s" % (bpy.app.version_string, os.path.basename(REF)))
    require(os.path.isfile(REF), "src_missing|%s" % REF)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.ops.import_scene.gltf(filepath=REF)

    ms = meshes()
    require(len(ms) >= 1, "no_mesh_imported")
    obj = ms[0]
    if len(ms) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for o in ms:
            o.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.join()
    obj.name = "ENV_BOULDER_001"

    # glTF 导入会沿 UV/法线接缝把顶点拆开 → 网格拓扑被打断，Collapse 减面到 ~40% 就停。
    # 先按距离焊回（loop 级 UV 保留），再减面。
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    log("weld|verts %d->%d" % (before, len(obj.data.vertices)))

    src_tris = tri_count(obj)
    mn, mx = bbox()
    log("src|obj=%s|tris=%d|dims=%s|slots=%d" % (
        obj.name, src_tris, vec(mx - mn), len(obj.data.materials)))

    # 单次 Collapse 在扫描网格上会提前停（实测 ratio 0.1134 只降到 26,615）→ 迭代减面
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    cur = src_tris
    for i in range(8):
        if cur <= TARGET_TRIS:
            break
        ratio = max(0.05, min(0.9, float(TARGET_TRIS) / max(1, cur)))
        mod = obj.modifiers.new("Decimate%d" % i, "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
        new = tri_count(obj)
        log("decimate|pass=%d|ratio=%.4f|%d->%d" % (i + 1, ratio, cur, new))
        if new >= cur:
            break
        cur = new
    log("decimate|final_tris=%d|target=%d" % (cur, TARGET_TRIS))

    # 原点 = 脚印中心 + 底面 z=0
    mn, mx = bbox()
    center = (mn + mx) * 0.5
    for v in obj.data.vertices:
        v.co -= Vector((center.x, center.y, mn.z))
    obj.data.update()
    mn, mx = bbox()
    dims = mx - mn
    tris = tri_count(obj)
    log("final|tris=%d|dims=%s|min=%s|max=%s|slots=%d" % (
        tris, vec(dims), vec(mn), vec(mx), len(obj.data.materials)))
    require(tris <= TRI_BUDGET, "tri_budget|%d>%d" % (tris, TRI_BUDGET))
    require(len(obj.data.materials) <= 2, "slot_over|%d" % len(obj.data.materials))
    require(abs(mn.z) < 0.005, "not_grounded|%.4f" % mn.z)
    require(abs(mn.x + mx.x) < 0.02, "x_not_centered|%.3f..%.3f" % (mn.x, mx.x))
    require(abs(mn.y + mx.y) < 0.02, "y_not_centered|%.3f..%.3f" % (mn.y, mx.y))
    require(dims.x <= 1.6 and dims.y <= 2.0 and dims.z <= 1.4,
            "too_big|%s" % vec(dims))

    cam = setup_render()
    render_views(cam)
    for o in list(bpy.data.objects):
        if o.type in {"LIGHT", "CAMERA"} or o.name.startswith("RENDER_"):
            bpy.data.objects.remove(o, do_unlink=True)
    export_glb()
    log("done|tris=%d|failures=%d" % (tris, len(failures)))
    sys.exit(0 if not failures else 1)


main()
