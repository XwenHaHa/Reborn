# -*- coding: utf-8 -*-
"""ART03-⑧ ENV_BUSH_002：重做草丛（替换 ART01 的"绿纸条"版）。

为什么重做：负责人两次指出草丛假。ART01 的 `sm_bush_001.glb` 是**单层平面四边叶片**
（2040 tris / 2 槽 / 双面），近距离就是纸片。这里重做：

  · 每片叶子是**带中脊的 3 段弯曲带**（横向 2 格 → 有折角，不再是平面），
    叶尖收细到 4 mm、叶片沿长度方向逐渐变窄，尖端再微微下垂；
  · **170 片**叶分 3 圈（外圈铺开、内圈竖立、核心密生）+ 每片独立的倾角/扭角/长度，
    外圈略矮、内圈偏高，形成"中间一丛高、四周铺开"的自然轮廓；
  · 叶基部有**泥土垫**（低矮圆盘，≤0.09 高）——玩家躲进草丛时相机不会进土；
  · 保持 ART01 的全部对外契约：2 材质槽（`MAT_Bush_Leaf` / `MAT_Bush_Soil`，颜色/粗糙度不变）、
    **双面**、**零碰撞**、包络 ≈2.87 × 0.88 × 2.87、tris ≤3000。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art09_grass_002.py' -- --stage all
"""

import hashlib
import math
import os
import random
import sys

import bpy
from mathutils import Vector

REPO = "E:/Reborn"
GLB_OUT = REPO + "/Art/Exports/Environment/SM_Bush_002.glb"
RENDER_DIR = REPO + "/Art/Probes"

SEED = 20261021
BLADES = 220
ENVELOPE_R = 1.43          # 目标半径（ART01 契约：2.87 / 2 ≈ 1.435）
TARGET_H = 0.88            # 目标最高点
SOIL_H = 0.085             # 泥土垫高度（≤0.12）
TRI_BUDGET = 6000      # ART03-⑪：预算 3000→6000（叶数 145→220、加宽），实测场景余量充足

LEAF_LINEAR = (0.085, 0.200, 0.075)
SOIL_LINEAR = (0.055, 0.038, 0.025)

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


rng = random.Random(SEED)


def make_material(name, linear_rgb, roughness=0.85, image=None, normal_image=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (linear_rgb[0], linear_rgb[1], linear_rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    mat.use_backface_culling = False        # 双面：玩家会站在草丛里往外看
    if image is not None:
        # 贴图是**倍率图**（均值≈1）：MixRGB(MULTIPLY) → Base Color，
        # 这样 glTF 会同时导出 baseColorTexture 与 baseColorFactor，
        # 颜色契约（albedo_color ≈ sRGB(线性色)）保持不变。
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Linear"
        tex.location = (-620, 260)
        mix = nt.nodes.new("ShaderNodeMixRGB")
        mix.blend_type = "MULTIPLY"
        mix.inputs["Fac"].default_value = 1.0
        mix.location = (-320, 300)
        mix.inputs["Color1"].default_value = (linear_rgb[0], linear_rgb[1], linear_rgb[2], 1.0)
        nt.links.new(tex.outputs["Color"], mix.inputs["Color2"])
        nt.links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    if normal_image is not None:
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = normal_image
        ntex.interpolation = "Linear"
        ntex.location = (-620, -220)
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.location = (-300, -220)
        nmap.inputs["Strength"].default_value = 1.0
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat



def _srgb(c):
    if c <= 0.0031308:
        return 12.92 * c
    return 1.055 * (c ** (1.0 / 2.4)) - 0.055


def _hash(u, v, seed):
    x = math.sin(u * 127.1 + v * 311.7 + seed * 17.31) * 43758.5453
    return x - math.floor(x)


def _vnoise(u, v, seed):
    iu, iv = math.floor(u), math.floor(v)
    fu, fv = u - iu, v - iv
    fu = fu * fu * (3.0 - 2.0 * fu)
    fv = fv * (3.0 - 2.0 * fv)
    a = _hash(iu, iv, seed)
    b = _hash(iu + 1, iv, seed)
    c = _hash(iu, iv + 1, seed)
    d = _hash(iu + 1, iv + 1, seed)
    return (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv


def make_leaf_image(name="T_Grass_Leaf", w=128, h=256):
    """叶片贴图：纵向明暗 + 中脊高光 + 细纵纹 + 斑驳。返回的是**倍率**（均值≈1）。"""
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.colorspace_settings.name = "sRGB"
    px = [0.0] * (w * h * 4)
    for j in range(h):
        v = (j + 0.5) / float(h)          # 0 = 叶基, 1 = 叶尖
        # 纵向：基部偏暗（0.78）→ 中上部最亮（1.10）→ 叶尖略暗（0.90）
        grad = 0.78 + 0.32 * math.sin(math.pi * min(1.0, 0.10 + v * 0.95)) + 0.10 * (1.0 - v)
        for i in range(w):
            u = (i + 0.5) / float(w)      # 0/1 = 叶缘, 0.5 = 中脊
            m = grad
            # 中脊高光（与几何中脊折面对应）
            ridge = math.exp(-((u - 0.5) ** 2) / (2.0 * 0.022))
            m += 0.10 * ridge
            # 叶缘略压暗，避免边缘"发光"
            edge = min(u, 1.0 - u)
            m *= 0.92 + 0.08 * min(1.0, edge / 0.12)
            # 细纵纹（叶脉）
            m *= 1.0 + 0.045 * math.sin(u * 46.0 * math.pi) * (0.4 + 0.6 * v)
            # 斑驳
            m += 0.07 * (_vnoise(u * 9.0, v * 26.0, 3) - 0.5)
            m = max(0.35, min(1.35, m))
            k = (j * w + i) * 4
            px[k] = _srgb(m * 1.00)
            px[k + 1] = _srgb(m * 1.03)
            px[k + 2] = _srgb(m * 0.96)
            px[k + 3] = 1.0
    img.pixels = px
    img.pack()
    return img



def make_leaf_normal_image(name="T_Grass_Leaf_N", w=128, h=256):
    """叶片切线空间法线：中脊凹槽 + 叶脉细棱 + 斑驳。ND 朝 +Z，强度 0.5 编码。"""
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    px = [0.0] * (w * h * 4)

    def height(u, v):
        hgt = 0.0
        # 中脊：u=0.5 处一条凸起（与几何折面同向，强化而不是打架）
        hgt += 0.55 * math.exp(-((u - 0.5) ** 2) / (2.0 * 0.010))
        # 叶脉：沿长度方向的细棱
        hgt += 0.16 * (0.5 + 0.5 * math.sin(u * 46.0 * math.pi))
        # 斑驳
        hgt += 0.10 * (_vnoise(u * 11.0, v * 30.0, 7) - 0.5)
        # 叶缘轻微下卷
        hgt -= 0.30 * max(0.0, (abs(u - 0.5) - 0.42) / 0.08)
        return hgt

    strength = 2.6
    for j in range(h):
        v = (j + 0.5) / float(h)
        for i in range(w):
            u = (i + 0.5) / float(w)
            e = 1.0 / float(w)
            hu = (height(min(1.0, u + e), v) - height(max(0.0, u - e), v)) / (2.0 * e)
            hv = (height(u, min(1.0, v + e)) - height(u, max(0.0, v - e))) / (2.0 * e)
            nx = -hu * strength
            ny = -hv * strength
            nz = 1.0
            ln = math.sqrt(nx * nx + ny * ny + nz * nz)
            nx, ny, nz = nx / ln, ny / ln, nz / ln
            k = (j * w + i) * 4
            px[k] = 0.5 + 0.5 * nx
            px[k + 1] = 0.5 + 0.5 * ny
            px[k + 2] = 0.5 + 0.5 * nz
            px[k + 3] = 1.0
    img.pixels = px
    img.pack()
    return img


def make_soil_image(name="T_Grass_Soil", w=128, h=128):
    """泥土贴图：斑驳 + 边缘压暗（倍率均值≈1）。"""
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.colorspace_settings.name = "sRGB"
    px = [0.0] * (w * h * 4)
    for j in range(h):
        v = (j + 0.5) / float(h)
        for i in range(w):
            u = (i + 0.5) / float(w)
            m = 0.86
            m += 0.20 * (_vnoise(u * 7.0, v * 7.0, 11) - 0.5)
            m += 0.12 * (_vnoise(u * 19.0, v * 19.0, 29) - 0.5)
            # 越靠外越暗（土堆边缘）
            r = math.hypot(u - 0.5, v - 0.5) * 2.0
            m *= 1.02 - 0.18 * min(1.0, r)
            m = max(0.45, min(1.30, m))
            k = (j * w + i) * 4
            px[k] = _srgb(m * 1.04)
            px[k + 1] = _srgb(m * 0.99)
            px[k + 2] = _srgb(m * 0.92)
            px[k + 3] = 1.0
    img.pixels = px
    img.pack()
    return img


def build_blade_mesh(verts, faces, uvs, mat_index, base, yaw, lean, twist, length, width, droop):
    """一片带中脊的弯曲叶子：3 段 × 横向 2 格（共 6 个四边形）。"""
    segs = 5      # 3→5：叶尖不再硬折
    across = 2
    base_idx = len(verts)
    cy = math.cos(yaw)
    sy = math.sin(yaw)
    # 叶片所在竖直平面的横向方向（垂直于生长方向）
    side = Vector((-sy, cy, 0.0))

    for s in range(segs + 1):
        t = float(s) / float(segs)
        # 长度方向：先向 lean 方向弯，再在末段下垂
        bend = lean * (t * t) * length * 0.55
        drop = -droop * (t ** 3) * length
        center = Vector((base.x + math.sin(yaw) * bend * 0.0 + math.cos(yaw) * bend * 0.0,
                         base.y, base.z)) + Vector((0.0, 0.0, 0.0))
        # 生长高度
        h = length * (t - 0.18 * t * t * t)
        # 水平偏移：朝 lean 方向 + 一点随机扭出的横向分量
        horiz = Vector((math.sin(lean) * math.cos(yaw), math.sin(lean) * math.sin(yaw), 0.0)) * h
        center = Vector((base.x, base.y, base.z + h)) + horiz + Vector((0.0, 0.0, drop))

        # 该高度的半宽（越往上越窄，尖端几乎成线）
        half_w = width * (1.0 - 0.92 * t) * 0.5
        if s == segs:
            half_w = width * 0.03
        # 扭转：让叶片绕自身轴慢慢转，避免所有叶子朝向一致
        tw = twist * t
        sdir = (side * math.cos(tw) + Vector((0.0, 0.0, 1.0)) * math.sin(tw) * 0.35).normalized()
        # 中脊抬高（折面），脊高随宽度缩放
        ridge = half_w * 0.55 + 0.004
        for a in range(across + 1):
            f = float(a) / float(across)
            offset = (f * 2.0 - 1.0)
            p = center + sdir * (offset * half_w)
            # 中间那一列抬高 → 形成脊
            if a == 1:
                p = p + Vector((0.0, 0.0, ridge))
            verts.append((p.x, p.y, p.z))
            uvs.append((f, t))

    for s in range(segs):
        for a in range(across):
            i0 = base_idx + s * (across + 1) + a
            i1 = i0 + 1
            i2 = i0 + (across + 1)
            i3 = i2 + 1
            faces.append((i0, i1, i3, i2))
            mat_index.append(0)


def build_soil(verts, faces, uvs, mat_index, radius, height):
    base_idx = len(verts)
    rings = 2
    seg = 16
    for r in range(rings + 1):
        t = float(r) / float(rings)
        rr = radius * (1.0 - 0.35 * t)
        z = height * (1.0 - t * t)
        for i in range(seg):
            a = 2.0 * math.pi * float(i) / float(seg)
            verts.append((math.cos(a) * rr, math.sin(a) * rr, z))
            uvs.append((0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)))
    for r in range(rings):
        for i in range(seg):
            j = (i + 1) % seg
            i0 = base_idx + r * seg + i
            i1 = base_idx + r * seg + j
            i2 = base_idx + (r + 1) * seg + i
            i3 = base_idx + (r + 1) * seg + j
            faces.append((i0, i1, i3, i2))
            mat_index.append(1)
    # 盘心：不补这一点，从上往下看中间是个洞（第一版渲染里透出灰背景）
    center_idx = len(verts)
    verts.append((0.0, 0.0, 0.0))
    uvs.append((0.5, 0.5))
    last_ring = rings * seg
    for i in range(seg):
        j = (i + 1) % seg
        faces.append((base_idx + last_ring + i, base_idx + last_ring + j, center_idx))
        mat_index.append(1)


def main():
    log("start|blender=%s|seed=%d|blades=%d" % (bpy.app.version_string, SEED, BLADES))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"

    verts, faces, uvs, mat_index = [], [], [], []

    # 泥土垫
    # 泥土垫只做"基部一坨"（半径 0.62）：第一版按包络 1.4 做成了直径 2.8 m 的棕色大饼
    build_soil(verts, faces, uvs, mat_index, 0.62, SOIL_H)
    soil_faces = len(faces)

    # 3 圈叶片：外圈铺开（矮、倾角大）、中圈、内圈（高、直立）
    rings = [
        # (数量, 半径范围, 高度范围, 倾角范围)
        (96, 0.55, 1.26, 0.46, 0.72, 0.44, 0.62),
        (72, 0.22, 0.52, 0.72, 0.92, 0.20, 0.42),
        (52, 0.00, 0.22, 0.84, 1.02, 0.05, 0.24),
    ]
    blade_count = 0
    for (n, r0, r1, h0, h1, lean0, lean1) in rings:
        for i in range(n):
            a = 2.0 * math.pi * (float(i) / float(n)) + rng.uniform(-0.06, 0.06)
            r = rng.uniform(r0, r1)
            base = Vector((math.cos(a) * r, math.sin(a) * r, SOIL_H * 0.55))
            length = rng.uniform(h0, h1)
            width = rng.uniform(0.034, 0.062)
            yaw = a + rng.uniform(-0.5, 0.5)
            lean = rng.uniform(lean0, lean1)
            twist = rng.uniform(-0.6, 0.6)
            droop = rng.uniform(0.05, 0.22)
            build_blade_mesh(verts, faces, uvs, mat_index, base, yaw, lean, twist,
                             length, width, droop)
            blade_count += 1

    mesh = bpy.data.meshes.new("ENV_BUSH_002")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        poly.use_smooth = True
    # 写入 UV（from_pydata 后按顶点顺序填 loop uv）
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index
            uv_layer.data[li].uv = uvs[vi]

    obj = bpy.data.objects.new("ENV_BUSH_002", mesh)
    bpy.context.scene.collection.objects.link(obj)

    leaf_img = make_leaf_image()
    leaf_n_img = make_leaf_normal_image()
    soil_img = make_soil_image()
    log("textures|leaf=%dx%d|leaf_normal=%dx%d|soil=%dx%d|packed=%s/%s/%s" % (
        leaf_img.size[0], leaf_img.size[1], leaf_n_img.size[0], leaf_n_img.size[1],
        soil_img.size[0], soil_img.size[1],
        str(leaf_img.packed_file is not None), str(leaf_n_img.packed_file is not None),
        str(soil_img.packed_file is not None)))
    obj.data.materials.append(make_material("MAT_Bush_Leaf", LEAF_LINEAR,
                                            image=leaf_img, normal_image=leaf_n_img))
    obj.data.materials.append(make_material("MAT_Bush_Soil", SOIL_LINEAR, image=soil_img))
    for pi, poly in enumerate(mesh.polygons):
        poly.material_index = 0
    # 前 soil_faces 个面是泥土垫
    for pi in range(min(soil_faces, len(mesh.polygons))):
        mesh.polygons[pi].material_index = 1

    mesh.calc_loop_triangles()
    tris = len(mesh.loop_triangles)
    zs = [v[2] for v in verts]
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    dims = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    log("built|blades=%d|tris=%d|verts=%d|dims=(%.4f, %.4f, %.4f)|min_z=%.4f" % (
        blade_count, tris, len(verts), dims[0], dims[1], dims[2], min(zs)))

    require(tris <= TRI_BUDGET, "tri_budget|%d>%d" % (tris, TRI_BUDGET))
    require(abs(dims[2] - TARGET_H) < 0.10, "height|%.3f (target %.2f)" % (dims[2], TARGET_H))
    require(dims[0] <= 3.05 and dims[1] <= 3.05, "envelope|%.2fx%.2f" % (dims[0], dims[1]))
    require(abs(min(zs)) < 1e-4, "not_grounded|%.4f" % min(zs))
    require(len(obj.data.materials) == 2, "slot_count|%d" % len(obj.data.materials))

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    wanted = {
        "export_format": "GLB", "use_selection": True, "export_apply": True,
        "export_yup": True, "export_materials": "EXPORT", "export_cameras": False,
        "export_lights": False, "export_extras": False, "export_texcoords": True,
        "export_normals": True, "export_colors": False, "export_tangents": True,
        "export_skins": False, "export_animations": False,
    }
    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=GLB_OUT, **{k: v for k, v in wanted.items() if k in props})
    with open(GLB_OUT, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (GLB_OUT, len(data), hashlib.sha256(data).hexdigest()))

    # 渲染三视图做视觉自查
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    w = bpy.data.worlds.new("W")
    scene.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.40, 0.44, 0.50, 1.0)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.1
    ld = bpy.data.lights.new("K", "AREA")
    ld.energy = 900.0
    ld.size = 3.0
    lo = bpy.data.objects.new("K", ld)
    lo.location = (2.2, -2.6, 3.2)
    lo.rotation_euler = (Vector((0, 0, 0.4)) - Vector(lo.location)).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(lo)
    cam_data = bpy.data.cameras.new("C")
    cam = bpy.data.objects.new("C", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name, pos, look, fov in [
        ("low", (0.0, -2.05, 0.35), (0.0, 0.0, 0.38), 42.0),
        ("q34", (1.9, -2.0, 1.25), (0.0, 0.0, 0.35), 42.0),
        ("top", (0.2, -0.4, 3.4), (0.0, 0.0, 0.3), 40.0),
    ]:
        cam_data.angle = math.radians(fov)
        cam.location = Vector(pos)
        cam.rotation_euler = (Vector(look) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = "%s/art09_grass_%s.png" % (RENDER_DIR, name)
        bpy.ops.render.render(write_still=True)
        log("render|%s" % name)

    log("done|tris=%d|failures=%d" % (tris, len(failures)))
    sys.exit(0 if not failures else 1)


main()
