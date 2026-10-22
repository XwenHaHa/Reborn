# -*- coding: utf-8 -*-
"""ART03-⑬ 两个小道具资产：`ENV_MOUND_001`（土丘）+ `ENV_ROOF_001`（木板棚顶）。

为什么要新资产：土墩和棚顶是纯 BoxMesh，靠 shader 救不回来（形状本身就是错的）。
两者都保持**极低面数**：土丘 ~300 tris、棚顶 ~400 tris。

约定（与既有静态资产一致）：
  · 原点 = 脚印中心 + 底面 z=0；
  · 1 材质槽、无骨骼；
  · 土丘的颜色交给生成器用 `ground.gdshader` 覆盖（世界坐标斑块），所以这里只导纯色底。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art10_props_002.py' -- --stage all
"""

import hashlib
import math
import os
import random
import sys

import bpy
from mathutils import Vector

REPO = "E:/Reborn"
OUT_DIR = REPO + "/Art/Exports/Environment"
SEED = 20261022
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


def make_material(name, linear_rgb, roughness=0.85):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (linear_rgb[0], linear_rgb[1], linear_rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def new_object(name, verts, faces, mat, glossy=0.85, linear=(0.1, 0.1, 0.1)):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        poly.use_smooth = True
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index
            co = mesh.vertices[vi].co
            uv.data[li].uv = (0.5 + 0.5 * co.x, 0.5 + 0.5 * co.y)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.materials.append(mat)
    return obj


def build_mound(rng, radius=1.0, height=0.5, rings=5, seg=22):
    """低模土丘：径向环 + 噪声起伏，边缘落到 z=0（贴合地面）。"""
    verts, faces = [], []
    verts.append((0.0, 0.0, height))               # 顶点
    for r in range(1, rings + 1):
        t = float(r) / float(rings)
        rr = radius * (t ** 0.85)
        for i in range(seg):
            a = 2.0 * math.pi * float(i) / float(seg)
            # 起伏：越低频越好，避免"尖刺"
            n = (math.sin(a * 3.0 + t * 5.1) * 0.5 + math.sin(a * 7.0 - t * 3.7) * 0.3
                 + rng.uniform(-0.12, 0.12))
            z = height * max(0.0, (1.0 - t * t)) * (1.0 + 0.10 * n)
            if r == rings:
                z = 0.0                              # 最后一圈贴地
            verts.append((math.cos(a) * rr * (1.0 + 0.06 * n), math.sin(a) * rr * (1.0 + 0.06 * n), z))
    for i in range(seg):
        j = (i + 1) % seg
        faces.append((0, 1 + i, 1 + j))
    for r in range(rings - 1):
        for i in range(seg):
            j = (i + 1) % seg
            i0 = 1 + r * seg + i
            i1 = 1 + r * seg + j
            i2 = 1 + (r + 1) * seg + i
            i3 = 1 + (r + 1) * seg + j
            faces.append((i0, i1, i3, i2))
    return verts, faces


def build_plank_roof(rng, sx=3.4, sz=3.8, thickness=0.05, plank_w=0.20, gap=0.022):
    """木板棚顶：一排沿 X 的板条（沿 Z 排布）+ 两根托梁，原点在脚印中心、底面 z=0。"""
    verts, faces = [], []
    board_h = thickness

    def add_box(cx, cy, cz, hx, hy, hz):
        base = len(verts)
        for dx in (-hx, hx):
            for dy in (-hy, hy):
                for dz in (-hz, hz):
                    verts.append((cx + dx, cy + dy, cz + dz))
        # 8 顶点 → 12 三角形（用四边形面，导出时三角化）
        idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
               (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        for f in idx:
            faces.append(tuple(base + k for k in f))

    # 板条：沿 Z 铺满，长度沿 X
    n = max(4, int(round(sz / (plank_w + gap))))
    step = sz / float(n)
    for i in range(n):
        cy = -sz * 0.5 + step * (float(i) + 0.5)
        jitter = rng.uniform(-0.012, 0.012)
        yaw_off = rng.uniform(-0.02, 0.02)
        add_box(yaw_off, cy, board_h * 0.5 + rng.uniform(0.0, 0.012),
                sx * 0.5, step * 0.5 - gap * 0.5 + jitter, board_h * 0.5)
    # 两根托梁（沿 Z），放在板条下面
    for x in (-sx * 0.32, sx * 0.32):
        add_box(x, 0.0, -0.055, 0.075, sz * 0.48, 0.035)
    return verts, faces


def export(obj, name, path):
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
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, **{k: v for k, v in wanted.items() if k in props})
    with open(path, "rb") as f:
        data = f.read()
    obj.data.calc_loop_triangles()
    log("glb|%s|name=%s|tris=%d|bytes=%d|sha256=%s" % (
        name, obj.name, len(obj.data.loop_triangles), len(data),
        hashlib.sha256(data).hexdigest()[:16]))


def normalize(obj):
    """原点 → 脚印中心；底面 z=0。"""
    vs = [v.co.copy() for v in obj.data.vertices]
    mnx = min(v.x for v in vs)
    mxx = max(v.x for v in vs)
    mny = min(v.y for v in vs)
    mxy = max(v.y for v in vs)
    mnz = min(v.z for v in vs)
    cx = (mnx + mxx) * 0.5
    cy = (mny + mxy) * 0.5
    for v in obj.data.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= mnz
    obj.data.update()
    dims = (mxx - mnx, mxy - mny, max(v.z for v in vs) - mnz)
    return dims


def main():
    rng = random.Random(SEED)
    log("start|blender=%s|seed=%d" % (bpy.app.version_string, SEED))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"

    # ---------- 土丘 ----------
    verts, faces = build_mound(rng)
    soil = make_material("MAT_Mound_Soil", (0.072, 0.082, 0.048), 0.92)
    mound = new_object("ENV_MOUND_001", verts, faces, soil)
    dims = normalize(mound)
    mound.data.calc_loop_triangles()
    log("mound|tris=%d|dims=(%.4f, %.4f, %.4f)" % (len(mound.data.loop_triangles), *dims))
    require(len(mound.data.loop_triangles) <= 800, "mound_tris|%d" % len(mound.data.loop_triangles))
    require(abs(dims[2] - 0.5) < 0.06, "mound_height|%.3f" % dims[2])
    export(mound, "ENV_MOUND_001", OUT_DIR + "/SM_Mound_001.glb")

    # ---------- 木板棚顶 ----------
    bpy.ops.object.delete(use_global=False)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    verts, faces = build_plank_roof(rng)
    wood = make_material("MAT_Roof_Plank", (0.048, 0.030, 0.017), 0.85)
    roof = new_object("ENV_ROOF_001", verts, faces, wood)
    dims = normalize(roof)
    roof.data.calc_loop_triangles()
    log("roof|tris=%d|dims=(%.4f, %.4f, %.4f)" % (len(roof.data.loop_triangles), *dims))
    require(len(roof.data.loop_triangles) <= 1200, "roof_tris|%d" % len(roof.data.loop_triangles))
    require(abs(dims[0] - 3.4) < 0.05 and abs(dims[1] - 3.8) < 0.05,
            "roof_dims|%.2fx%.2f" % (dims[0], dims[1]))
    export(roof, "ENV_ROOF_001", OUT_DIR + "/SM_Roof_001.glb")

    log("done|failures=%d" % len(failures))
    sys.exit(0 if not failures else 1)


main()
