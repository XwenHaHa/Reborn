# -*- coding: utf-8 -*-
"""ART03-⑮-3 `ENV_QUOIN_001`：矮墙转角料石（quoin），压住两条墙端在转角处的接缝。

## 为什么需要（实测）
庇护棚西南/西北两个转角：两片矮墙模块都是**平板扫描件**，石排在模块两端有 ±7 cm 的内缩，
于是转角处两边的石头都往回收 → 露出一条 6–10 cm 的**衬板竖带 + 壳体薄边**，
3× 放大图里看得很清楚（`art06_shelter_corner_sw.png`）。
只靠"把衬板铺到端头"只能把"看穿"变成"看到一块灰板"，收边不彻底。

## 做法（v2：四块不同长宽的砌石，不再是四块一样的方块）
一块整高 quoin = **4 皮**，每皮长宽高都不同、相邻层转 90°、错缝摆放（真 quoin 的节奏），
总高 1.60 m ≈ 墙高，所以每转角只放一件，运行时不再叠放/旋转：
  (0.38, 0.38, 0.34) / (0.42, 0.38, 0.42) / (0.38, 0.42, 0.44) / (0.40, 0.38, 0.403)
（皮高之和 1.600 = 墙高；皮间各让 1 mm 缝，所以第 4 皮补到 0.403，总高仍 1.600）
- 皮间留 1 mm 缝，避免共面 z-fighting；四边 12 mm 倒角 + 顶面 3% 收分（料石感）；
- 每皮长宽 ≥ 0.38 → 半宽 ≥ 0.19，比墙轴两侧石块外凸面（±0.151）再多凸 3.9–5.9 cm；
- UV 每皮各取一块**又平整、色调又接近墙石**的贴图方块（`find_patches`），跨砖缝会印出菱形花格；
- 材质：`贴图 × 倍率色 (0.70, 0.78, 0.70)` → `baseColorTexture` + `baseColorFactor`，带法线，roughness 0.85；
- 原点 = 脚印中心 + 底面 z = 0；面数预算 ≤ 400 tris。

源（只读，仅取材质贴图）：references/_downloads/wall_stefan_wr/model.glb
调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art14_quoin.py'
"""

import hashlib
import os
import sys

import bmesh
import bpy
from mathutils import Vector

REPO = "E:/Reborn"
REF = REPO + "/references/_downloads/wall_stefan_wr/model.glb"
GLB_OUT = REPO + "/Art/Exports/Environment/SM_Quoin_001.glb"
MODULE = "wall_stone"
CHAMFER = 0.012
PATCH_CELL = 64
TONE_TARGET = 0.200
TONE_MUL = (0.70, 0.78, 0.70)
JOINT = 0.001
# (宽 W, 深 D, 高 H, 绕 Z 转角, 平移 x, 平移 y)
STONES = [
    (0.38, 0.38, 0.34, 0.0, 0.000, 0.000),
    (0.42, 0.38, 0.42, 90.0, 0.002, -0.002),
    (0.38, 0.42, 0.44, 180.0, -0.002, 0.002),
    (0.40, 0.38, 0.403, 270.0, 0.001, 0.002),
]
TRI_BUDGET = 400
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


def total_height():
    return sum(s[2] for s in STONES) - JOINT * (len(STONES) - 1)


def load_stone_images():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=REF)
    src = None
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name.startswith(MODULE + "_stone_wall_low"):
            src = o
            break
    require(src is not None, "src_module_missing")
    base_img = normal_img = None
    old = src.data.materials[0] if src.data.materials else None
    if old is not None and old.use_nodes:
        for l in old.node_tree.links:
            n = l.from_node
            if n.type != "TEX_IMAGE" or n.image is None:
                continue
            if l.to_node.type == "BSDF_DIFFUSE" and l.to_socket.name == "Color":
                base_img = n.image
            elif l.to_node.type == "NORMAL_MAP" or l.to_node.name.startswith("Normal Map"):
                normal_img = n.image
    require(base_img is not None, "base_color_texture_missing")
    require(normal_img is not None, "normal_texture_missing")
    if base_img is None or normal_img is None:
        sys.exit(1)
    log("images|base=%s|normal=%s|size=%s" % (base_img.name, normal_img.name, base_img.size[:]))
    return base_img, normal_img


def find_patches(img, want, cell=PATCH_CELL):
    """挑 `want` 块**又平整、色调又接近墙石**的贴图方块（互不重叠），返回 [(u0, v0, span)]。"""
    w, h = img.size
    px = list(img.pixels)
    cands = []
    step = 4
    for gy in range(0, h - cell + 1, cell):
        for gx in range(0, w - cell + 1, cell):
            s = s2 = 0.0
            n = 0
            for y in range(gy, gy + cell, step):
                base = (y * w + gx) * 4
                for x in range(0, cell, step):
                    i = base + x * 4
                    lum = 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2]
                    s += lum
                    s2 += lum * lum
                    n += 1
            mean = s / max(1, n)
            var = max(0.0, s2 / max(1, n) - mean * mean)
            if not (0.10 < mean < 0.45):
                continue
            cands.append((var + 0.60 * (mean - TONE_TARGET) ** 2, mean, gx, gy))
    require(len(cands) >= want, "patch_candidates|%d" % len(cands))
    cands.sort()
    out = []
    for score, mean, gx, gy in cands:
        if any(abs(gx - o[2]) < cell and abs(gy - o[3]) < cell for o in out):
            continue
        out.append((score, mean, gx, gy))
        log("patch|%d|px=(%d,%d)|score=%.5f|mean=%.3f" % (len(out) - 1, gx, gy, score, mean))
        if len(out) >= want:
            break
    require(len(out) >= want, "patches_found|%d" % len(out))
    if len(out) < want:
        sys.exit(1)
    return [(gx / float(w), gy / float(h), cell / float(w)) for _, _, gx, gy in out]


def make_stone(idx, w, d, h, patch):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * w * 0.995, v.co.y * d * 0.995, v.co.z * h))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=CHAMFER, segments=1, affect="EDGES")
    top_z = max(v.co.z for v in bm.verts)
    for v in bm.verts:
        if v.co.z > top_z - 1e-6:
            v.co.x *= 0.97
            v.co.y *= 0.97
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("Q%d" % idx)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("Q%d" % idx, me)
    bpy.context.scene.collection.objects.link(obj)
    me.update()

    u0, v0, span = patch
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if abs(n.x) >= abs(n.y) and abs(n.x) >= abs(n.z):
                pu, pv = co.y / d + 0.5, co.z / h
            elif abs(n.y) >= abs(n.z):
                pu, pv = co.x / w + 0.5, co.z / h
            else:
                pu, pv = co.x / w + 0.5, co.y / d + 0.5
            uv.data[li].uv = (u0 + pu * span, v0 + pv * span)
    return obj


def make_material(base_img, normal_img):
    mat = bpy.data.materials.new("MAT_Quoin_Stone")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    tb = nt.nodes.new("ShaderNodeTexImage")
    tb.image = base_img
    tb.location = (-620, 260)
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs["Fac"].default_value = 1.0
    mix.inputs["Color2"].default_value = (TONE_MUL[0], TONE_MUL[1], TONE_MUL[2], 1.0)
    mix.location = (-360, 260)
    nt.links.new(tb.outputs["Color"], mix.inputs["Color1"])
    nt.links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = normal_img
    tn.location = (-620, -160)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    # 法线贴图取自整面墙的照片，平整区里仍可能带石棱 → 强度压到 0.35，
    # 只留颗粒、不出现"斜刀痕"（0.5 以上时料石上会出现明显的 V 形阴影）
    nmap.inputs["Strength"].default_value = 0.35
    nmap.location = (-360, -160)
    nt.links.new(tn.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def main():
    log("start|blender=%s|stones=%d|h_total=%.4f" % (
        bpy.app.version_string, len(STONES), total_height()))
    require(os.path.isfile(REF), "src_missing")
    if not os.path.isfile(REF):
        sys.exit(1)
    base_img, normal_img = load_stone_images()
    patches = find_patches(base_img, len(STONES))

    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)

    objs = []
    z_cursor = 0.0
    for i, (w, d, h, yaw, dx, dy) in enumerate(STONES):
        obj = make_stone(i, w, d, h, patches[i])
        obj.location = Vector((dx, dy, z_cursor + h * 0.5))
        obj.rotation_euler = (0.0, 0.0, yaw * 3.141592653589793 / 180.0)
        z_cursor += h - JOINT
        objs.append(obj)
    log("built|stones=%d|z_top=%.4f" % (len(objs), z_cursor + JOINT))

    # 合并成一件
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = "ENV_QUOIN_001"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # 归原点（脚印中心 + 底面 z = 0）
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    off = Vector(((min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5, min(zs)))
    for v in obj.data.vertices:
        v.co -= off
    obj.data.update()

    mat = make_material(base_img, normal_img)
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.material_index = 0

    obj.data.calc_loop_triangles()
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    dims = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    tris = len(obj.data.loop_triangles)
    log("final|tris=%d|dims=(%.4f, %.4f, %.4f)|min_z=%.4f|slots=%d|uv_layers=%d" % (
        tris, dims[0], dims[1], dims[2], min(zs), len(obj.data.materials),
        len(obj.data.uv_layers)))
    require(tris <= TRI_BUDGET, "tri_budget|%d" % tris)
    require(abs(min(zs)) < 5e-4, "not_grounded")
    # 每皮长宽 ≥ 0.34、总高 = 1.60（生成器按这个值断言）
    require(abs(dims[2] - total_height()) < 5e-3, "height|%.4f" % dims[2])
    require(min(s[0] for s in STONES) >= 0.38, "min_width")
    require(min(s[1] for s in STONES) >= 0.38, "min_depth")
    require(len(obj.data.materials) == 1, "slots|%d" % len(obj.data.materials))
    require(len(obj.data.uv_layers) == 1, "uv_layers|%d" % len(obj.data.uv_layers))

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
