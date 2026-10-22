# -*- coding: utf-8 -*-
"""ART03-⑭ `ENV_ROOT_BARRIER_001`：可平铺的"盘根横墙"模块。

替换 `RootBarrierWest/East`（16.38 m / 9.38 m × 0.50 高 × 1.00 深）的灰盒。
设计：沿 X 方向 3 m 一段，由**交错的粗根 + 斜跨的细根 + 入地的根须**组成，
      外轮廓控制在 3.0 × 0.50 × 0.80 内（碰撞盒仍是 0.50 × 1.00，视觉略薄以避免相机切进去）。

约束：
  · 原点 = 脚印中心 + 底面 z=0；模块长轴沿 **X**（与屏障走向一致）；
  · 1 材质槽（程序化树皮倍率贴图 + 棕色因子）；
  · 面数目标 ≤ 1200/模块（沿 26 m 平铺约 9 段 → ~9k tris）。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art11_root_barrier.py' -- --stage all
"""

import hashlib
import math
import os
import random
import sys

import bpy

REPO = "E:/Reborn"
GLB_OUT = REPO + "/Art/Exports/Environment/SM_RootBarrier_001.glb"
SEED = 20261023
MOD_LEN = 3.0
MOD_H = 0.50
MOD_D = 0.80
TRI_BUDGET = 1400

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


def srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def vhash(u, v, seed):
    x = math.sin(u * 127.1 + v * 311.7 + seed * 19.7) * 43758.5453
    return x - math.floor(x)


def vnoise(u, v, seed):
    iu, iv = math.floor(u), math.floor(v)
    fu, fv = u - iu, v - iv
    fu = fu * fu * (3 - 2 * fu)
    fv = fv * (3 - 2 * fv)
    a = vhash(iu, iv, seed)
    b = vhash(iu + 1, iv, seed)
    c = vhash(iu, iv + 1, seed)
    d = vhash(iu + 1, iv + 1, seed)
    return (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv


def make_bark_image(name="T_Bark", w=128, h=128):
    """树皮倍率贴图：纵向条纹 + 斑驳（均值≈1，颜色仍由 baseColorFactor 给）。"""
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.colorspace_settings.name = "sRGB"
    px = [0.0] * (w * h * 4)
    for j in range(h):
        v = (j + 0.5) / float(h)
        for i in range(w):
            u = (i + 0.5) / float(w)
            m = 1.0
            m += 0.16 * math.sin(u * 34.0 * math.pi) * (0.5 + 0.5 * v)   # 纵纹
            m += 0.22 * (vnoise(u * 8.0, v * 22.0, 5) - 0.5)
            m += 0.12 * (vnoise(u * 26.0, v * 40.0, 11) - 0.5)
            m = max(0.45, min(1.45, m))
            k = (j * w + i) * 4
            px[k] = srgb(m * 1.03)
            px[k + 1] = srgb(m * 0.98)
            px[k + 2] = srgb(m * 0.92)
            px[k + 3] = 1.0
    img.pixels = px
    img.pack()
    return img


def build():
    rng = random.Random(SEED)
    verts, faces, uvs = [], [], []
    seg = 8                     # 每根根的圆周分段

    def add_tube(p0, p1, r0, r1, sag=0.0, twist=0.0):
        """沿 p0→p1 的锥形管（sag 让中段下垂/上拱，像真根）。"""
        base = len(verts)
        steps = 4
        axis = []
        for s in range(steps + 1):
            t = float(s) / steps
            x = p0[0] + (p1[0] - p0[0]) * t
            y = p0[1] + (p1[1] - p0[1]) * t
            z = p0[2] + (p1[2] - p0[2]) * t + sag * math.sin(math.pi * t)
            axis.append((x, y, z))
        for s in range(steps + 1):
            t = float(s) / steps
            r = r0 + (r1 - r0) * t
            cx, cy, cz = axis[s]
            # 用相邻段做局部坐标系（近似即可）
            if s < steps:
                d = (axis[s + 1][0] - cx, axis[s + 1][1] - cy, axis[s + 1][2] - cz)
            else:
                d = (cx - axis[s - 1][0], cy - axis[s - 1][1], cz - axis[s - 1][2])
            dl = math.sqrt(d[0] ** 2 + d[1] ** 2 + d[2] ** 2) or 1.0
            dx, dy, dz = d[0] / dl, d[1] / dl, d[2] / dl
            # 任取一个垂直向量
            ux, uy, uz = (0.0, 0.0, 1.0) if abs(dz) < 0.9 else (1.0, 0.0, 0.0)
            nx = dy * uz - dz * uy
            ny = dz * ux - dx * uz
            nz = dx * uy - dy * ux
            nl = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            nx, ny, nz = nx / nl, ny / nl, nz / nl
            bx = ny * dz - nz * dy
            by = nz * dx - nx * dz
            bz = nx * dy - ny * dx
            for i in range(seg):
                a = 2.0 * math.pi * float(i) / seg + twist * math.sin(math.pi * t)
                ca, sa = math.cos(a), math.sin(a)
                verts.append((cx + (nx * ca + bx * sa) * r,
                              cy + (ny * ca + by * sa) * r,
                              cz + (nz * ca + bz * sa) * r))
                uvs.append((float(i) / seg, t))
        for s in range(steps):
            for i in range(seg):
                j = (i + 1) % seg
                i0 = base + s * seg + i
                i1 = base + s * seg + j
                i2 = base + (s + 1) * seg + i
                i3 = base + (s + 1) * seg + j
                faces.append((i0, i1, i3, i2))

    # 3 根主根：沿 X 走，高度/深度各不相同，带轻微起伏
    mains = [
        (-MOD_LEN * 0.5, 0.0, -0.10, MOD_LEN * 0.5, 0.0, -0.10, 0.115, 0.095, 0.02),
        (-MOD_LEN * 0.5, 0.02, 0.12, MOD_LEN * 0.5, -0.02, 0.10, 0.100, 0.085, -0.03),
        (-MOD_LEN * 0.5, -0.04, 0.32, MOD_LEN * 0.5, 0.03, 0.30, 0.080, 0.070, 0.04),
    ]
    for (x0, y0, z0, x1, y1, z1, r0, r1, sag) in mains:
        add_tube((x0, y0, z0), (x1, y1, z1), r0, r1, sag=sag, twist=0.5)

    # 4 根斜跨的细根：让模块看起来是"缠"的而不是"三根管子"
    for i in range(4):
        t0 = -MOD_LEN * 0.5 + MOD_LEN * (float(i) + 0.2) / 4.4
        t1 = t0 + MOD_LEN * rng.uniform(0.35, 0.62)
        z0 = rng.uniform(0.02, 0.34)
        z1 = rng.uniform(0.02, 0.34)
        y0 = rng.uniform(-0.16, 0.16)
        y1 = rng.uniform(-0.16, 0.16)
        add_tube((t0, y0, z0), (t1, y1, z1), rng.uniform(0.035, 0.055),
                 rng.uniform(0.03, 0.045), sag=rng.uniform(-0.05, 0.05), twist=rng.uniform(-1, 1))

    # 3 根入地的短根须
    for i in range(3):
        x = -MOD_LEN * 0.5 + MOD_LEN * (float(i) + 0.5) / 3.0
        y = rng.uniform(-0.2, 0.2)
        add_tube((x, y, 0.18), (x + rng.uniform(-0.25, 0.25), y + rng.uniform(-0.1, 0.1), -0.02),
                 rng.uniform(0.045, 0.06), 0.03, sag=rng.uniform(-0.02, 0.02))

    return verts, faces, uvs


def main():
    log("start|blender=%s|seed=%d|module=%.2fx%.2fx%.2f" % (
        bpy.app.version_string, SEED, MOD_LEN, MOD_H, MOD_D))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"

    verts, faces, uvs = build()
    mesh = bpy.data.meshes.new("ENV_ROOT_BARRIER_001")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        poly.use_smooth = True
        for li in poly.loop_indices:
            uv.data[li].uv = uvs[mesh.loops[li].vertex_index]

    obj = bpy.data.objects.new("ENV_ROOT_BARRIER_001", mesh)
    bpy.context.scene.collection.objects.link(obj)

    bark = make_bark_image()
    mat = bpy.data.materials.new("MAT_Root_Bark")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    base = (0.105, 0.068, 0.040)
    bsdf.inputs["Base Color"].default_value = (base[0], base[1], base[2], 1.0)
    bsdf.inputs["Roughness"].default_value = 0.88
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bark
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs["Fac"].default_value = 1.0
    mix.inputs["Color1"].default_value = (base[0], base[1], base[2], 1.0)
    nt.links.new(tex.outputs["Color"], mix.inputs["Color2"])
    nt.links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    mesh.materials.append(mat)

    # 统一缩放到模块尺寸内（正向缩放会超：管子半径让长度变成 3.27、高度 0.64）
    vs0 = [v.co.copy() for v in mesh.vertices]
    dx0 = max(v.x for v in vs0) - min(v.x for v in vs0)
    dz0 = max(v.z for v in vs0) - min(v.z for v in vs0)
    k = min(1.0, (MOD_LEN - 0.04) / dx0, (MOD_H - 0.02) / dz0)
    for v in mesh.vertices:
        v.co *= k
    log('fit|scale=%.4f' % k)

    # 原点：脚印中心 + 底面 z=0
    vs = [v.co.copy() for v in mesh.vertices]
    cx = (min(v.x for v in vs) + max(v.x for v in vs)) * 0.5
    cy = (min(v.y for v in vs) + max(v.y for v in vs)) * 0.5
    mnz = min(v.z for v in vs)
    for v in mesh.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= mnz
    mesh.update()

    vs = [v.co for v in mesh.vertices]
    dims = (max(v.x for v in vs) - min(v.x for v in vs),
            max(v.y for v in vs) - min(v.y for v in vs),
            max(v.z for v in vs) - min(v.z for v in vs))
    mesh.calc_loop_triangles()
    tris = len(mesh.loop_triangles)
    log("built|tris=%d|verts=%d|dims=(%.3f, %.3f, %.3f)|min_z=%.4f" % (
        tris, len(mesh.vertices), dims[0], dims[1], dims[2], min(v.z for v in vs)))
    require(tris <= TRI_BUDGET, "tri_budget|%d>%d" % (tris, TRI_BUDGET))
    require(2.2 <= dims[0] <= 3.2, "module_len|%.3f" % dims[0])
    require(dims[2] <= MOD_H + 0.02, "module_height|%.3f" % dims[2])
    require(abs(min(v.z for v in vs)) < 1e-4, "not_grounded")

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
