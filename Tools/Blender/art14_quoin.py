# -*- coding: utf-8 -*-
"""ART03-⑮-3 `ENV_QUOIN_001`：矮墙转角石（quoin），压住两条墙端在转角处的接缝。

## 为什么需要（本轮实测）
庇护棚西南/西北两个转角：两片矮墙模块都是**平板扫描件**，石排在模块两端有 ±7 cm 的内缩，
于是转角处两边的石头都往回收 → 露出一条 6–10 cm 的**衬板竖带 + 壳体薄边**，
3× 放大图里看得很清楚（`art06_shelter_corner_sw.png`）。
只靠"把衬板铺到端头"只能把"看穿"变成"看到一块灰板"，收边不彻底。

## 做法
一块**方正料石**，按 4 皮叠到 1.6 m，每皮旋转 90°，形成砌体转角的节奏。
- 尺寸 0.36 × 0.40 × 0.36 m：比墙轴两侧石块外凸面（±0.151）再多凸 0.029，正好"压住"转角；
- 四边 12 mm 倒角 + 顶面 3% 收分，避免像贴片；
- UV 只在贴图里挑一块**既平整、色调又接近墙石**的方块做投影窗口
  （贴图是整面墙的照片，直接按米数取窗口会跨过砖缝 → 会出现菱形花格，本轮踩过）；
- 材质：`贴图 × 倍率色` → Base Color（导出为 `baseColorTexture` + `baseColorFactor`），
  再压到墙石平均亮度，避免转角一竖条发白；roughness 0.85；
- 原点 = 脚印中心 + 底面 z = 0；面数预算 ≤ 200 tris。

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
QUOIN_W = 0.36
QUOIN_D = 0.36
QUOIN_H = 0.40
CHAMFER = 0.012
PATCH_CELL = 64                          # 平整贴图窗口边长（像素）
TONE_TARGET = 0.200                      # 目标亮度（墙石的平均观感）
TONE_MUL = (0.70, 0.78, 0.70)            # 倍率色：略偏绿，贴近墙石
TRI_BUDGET = 200
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


def load_stone_images():
    """从源件里取 base / normal 贴图（与 art12 同一套提取逻辑）。"""
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


def find_flat_patch(img, cell=PATCH_CELL):
    """挑一块**又平整、色调又接近墙石**的方块，返回 (u0, v0, span)。"""
    w, h = img.size
    px = list(img.pixels)
    best = None
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
                continue                    # 避开黑洞与高光
            score = var + 0.60 * (mean - TONE_TARGET) ** 2
            if best is None or score < best[0]:
                best = (score, mean, gx, gy)
    require(best is not None, "flat_patch_not_found")
    if best is None:
        sys.exit(1)
    score, mean, gx, gy = best
    log("patch|cell=%d|px=(%d,%d)|score=%.5f|mean=%.3f" % (cell, gx, gy, score, mean))
    return (gx / float(w), gy / float(h), cell / float(w))


def build_stone(base_img, normal_img, patch):
    me = bpy.data.meshes.new("ENV_QUOIN_001")
    obj = bpy.data.objects.new("ENV_QUOIN_001", me)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * QUOIN_W, v.co.y * QUOIN_D, v.co.z * QUOIN_H))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=CHAMFER, segments=1, affect="EDGES")
    top_z = max(v.co.z for v in bm.verts)
    for v in bm.verts:
        if v.co.z > top_z - 1e-6:
            v.co.x *= 0.97
            v.co.y *= 0.97
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    me.update()

    # UV：每个面都压进"石块内部那块平整贴图"，不跨砖缝
    u0, v0, span = patch
    uv_layer = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if abs(n.x) >= abs(n.y) and abs(n.x) >= abs(n.z):
                pu, pv = co.y / QUOIN_D + 0.5, co.z / QUOIN_H
            elif abs(n.y) >= abs(n.z):
                pu, pv = co.x / QUOIN_W + 0.5, co.z / QUOIN_H
            else:
                pu, pv = co.x / QUOIN_W + 0.5, co.y / QUOIN_D + 0.5
            uv_layer.data[li].uv = (u0 + pu * span, v0 + pv * span)
    log("uv|u0=%.4f|v0=%.4f|span=%.4f" % (u0, v0, span))

    mat = bpy.data.materials.new("MAT_Quoin_Stone")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0

    tb = nt.nodes.new("ShaderNodeTexImage")
    tb.image = base_img
    tb.location = (-620, 260)
    # 项目约定：贴图 × 倍率色 → Base Color（导出成 baseColorTexture + baseColorFactor）
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
    nmap.location = (-360, -160)
    nt.links.new(tn.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    me.materials.clear()
    me.materials.append(mat)
    for p in me.polygons:
        p.material_index = 0
    return obj


def main():
    log("start|blender=%s|target=%.3f×%.3f×%.3f" % (
        bpy.app.version_string, QUOIN_W, QUOIN_H, QUOIN_D))
    require(os.path.isfile(REF), "src_missing")
    if not os.path.isfile(REF):
        sys.exit(1)
    base_img, normal_img = load_stone_images()
    patch = find_flat_patch(base_img)

    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    obj = build_stone(base_img, normal_img, patch)

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
    log("final|tris=%d|dims=(%.4f, %.4f, %.4f)|min_z=%.4f|slots=%d|uv_layers=%d" % (
        tris, dims[0], dims[1], dims[2], min(zs), len(obj.data.materials),
        len(obj.data.uv_layers)))
    require(tris <= TRI_BUDGET, "tri_budget|%d" % tris)
    require(abs(min(zs)) < 5e-4, "not_grounded")
    require(abs(dims[0] - QUOIN_W) < 1e-3, "width|%.4f" % dims[0])
    require(abs(dims[1] - QUOIN_D) < 1e-3, "depth|%.4f" % dims[1])
    require(abs(dims[2] - QUOIN_H) < 1e-2, "height|%.4f" % dims[2])
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
