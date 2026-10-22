# -*- coding: utf-8 -*-
"""ART03-⑮ `ENV_WALL_LOW_001`：矮墙专用石墙模块（v4，从真墙面上"取最密的一皮"）。

## 前几版错在哪（都记下来，免得再走回头路）
- **v1** 用源件里的 `wall_stone_low`（1.622 × 0.774 m）。隔离渲染复查发现它**不是墙**，
  而是一堆**零星石头垒的锥形残堆**（7 颗石头，顶上 1 颗）。当"墙面"平铺 →
  **悬空石头 + 大片透出衬板**。
- **v2** 换同源 `wall_stone_medium`（1.613 × 0.993 m）。它**也是石堆**（4 排梯形，越往上越窄）。
  结论：源件里**只有 `wall_stone`（围栏那件，2.461 × 2.006 m）是真墙面**，
  其余 `*_low / *_medium / *_triplet / *_single_rock` 全是装饰石堆。
- **v3** 取 `wall_stone` 并**把顶点压平**到 0.800 m → 被压的三角面挤成一条、法线翻转被剔除，
  实机出现大片"塌陷空洞"。**压平不可用**。
- **v3.1** 改成"切掉上半、只留下面 0.8 m" → 还是空。原因：源件**下半部是被地面遮挡的扫描区**，
  石块本来就有大缺口；**上半部才是致密砌石**。

## v4 做法
取 `wall_stone` 的**最上面 0.800 m**（两刀切出：上边界不动，下边界切在 2.006 − 0.800 = 1.206 m），
得到 2.39 × 0.236 × 0.800 m 的一皮矮墙：
- 石块**完全不变形**（没有任何缩放/压平），只是被框出一个高度；
- 底面补一块石板盖住切口；运行时 2 皮叠起来 = 1.6 m，正好是庇护棚墙高（`k_y = 1.0`）；
- 段长由生成器按 `k_x = 段长/模块长` 精确贴合，**不重叠也不漏缝**。

源（只读）：references/_downloads/wall_stefan_wr/model.glb
调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art12_short_wall.py'
"""

import hashlib
import os
import sys

import bmesh
import bpy
from mathutils import Vector

REPO = "E:/Reborn"
REF = REPO + "/references/_downloads/wall_stefan_wr/model.glb"
GLB_OUT = REPO + "/Art/Exports/Environment/SM_Wall_Low_001.glb"
MODULE = "wall_stone"    # 源件里唯一的真墙面（= 围栏模块来源）
UNIT_TO_M = 0.01
CUT_TOP = 0.800          # 一皮高度；2 皮 = 1.6 m 正好等于庇护棚墙高（可用 `-- --cut` 覆盖）
for _i, _a in enumerate(sys.argv):
    if _a == "--cut" and _i + 1 < len(sys.argv):
        CUT_TOP = float(sys.argv[_i + 1])
# 围栏模块 1244 tris / 2.46×2.01 m 的面积密度，削到 0.800 m 高后三角面数量不变
# （被削平的部分只是压到同一平面，没有删面），所以上限按整件给 1500。
TRI_BUDGET = 1500
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


def rebuild_material(o):
    """源材质是 Sketchfab 旧式 Diffuse+Glossy+Add Shader，glTF 导出器无法映射 → 重建 Principled。"""
    old = o.data.materials[0] if o.data.materials else None
    base_img = normal_img = None
    if old is not None and old.use_nodes:
        for l in old.node_tree.links:
            src = l.from_node
            if src.type != "TEX_IMAGE" or src.image is None:
                continue
            if l.to_node.type == "BSDF_DIFFUSE" and l.to_socket.name == "Color":
                base_img = src.image
            elif l.to_node.type == "NORMAL_MAP" or l.to_node.name.startswith("Normal Map"):
                normal_img = src.image
    require(base_img is not None, "base_color_texture_missing")
    require(normal_img is not None, "normal_texture_missing")
    if base_img is None or normal_img is None:
        sys.exit(1)
    mat = bpy.data.materials.new("MAT_Wall_Low_Stone")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    tb = nt.nodes.new("ShaderNodeTexImage")
    tb.image = base_img
    tb.location = (-520, 260)
    nt.links.new(tb.outputs["Color"], bsdf.inputs["Base Color"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = normal_img
    tn.location = (-520, -160)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-260, -160)
    nt.links.new(tn.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    o.data.materials.clear()
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.material_index = 0
    log("material|slots=%d|base=%s|normal=%s" % (
        len(o.data.materials), base_img.name, normal_img.name))

def z_clusters(me, tol=1.5e-3, min_count=2):
    """把顶点 z 聚成"排"（石排上/下表面往往共面），用来挑一条真正落在石缝里的裁切线。"""
    zs = sorted(v.co.z for v in me.vertices)
    groups = []
    for z in zs:
        if groups and z - groups[-1][0] <= tol:
            groups[-1][1] += 1
        else:
            groups.append([z, 1])
    for z, c in groups:
        if c >= min_count:
            log("zpeak|%.4f|verts=%d" % (z, c))
    prev = None
    for z, c in groups:
        if prev is not None and z - prev > 0.03:
            log("zgap|%.4f..%.4f|height=%.4f" % (prev, z, z - prev))
        prev = z



def z_histogram(me):
    zs = [v.co.z for v in me.vertices]
    lo, hi = min(zs), max(zs)
    span = max(1e-6, hi - lo)
    n = 12
    bins = [0] * n
    for z in zs:
        bins[min(n - 1, int((z - lo) / span * n))] += 1
    for i, c in enumerate(bins):
        log("zhist|%d|%.3f-%.3f|verts=%d" % (i, lo + span * i / n, lo + span * (i + 1) / n, c))
    return lo, hi


def cut_band(o, z_lo, z_hi):
    """只保留 z_lo..z_hi 之间的几何（两端各切一刀，中间石头**完全不变形**）。

    不用"顶点压平"（v3 试过）：压平会把三角面挤成一条、法线随之翻转被剔除，
    实测墙面出现大片"塌陷空洞"。切开则保留部分原样，代价是截面开口 → 用 `add_cap()` 盖住。
    """
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    for z, clear_outer in ((z_hi, True), (z_lo, False)):
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6,
                               plane_co=(0.0, 0.0, z), plane_no=(0.0, 0.0, 1.0),
                               clear_outer=clear_outer,
                               clear_inner=not clear_outer)
    before = len(bm.faces)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-6, edges=list(bm.edges))
    log("cut_band|%.3f..%.3f|faces=%d|verts=%d" % (z_lo, z_hi, len(bm.faces), len(bm.verts)))
    bm.to_mesh(me)
    bm.free()
    me.update()
    log("cut_band|before_faces=%d" % before)


def add_cap(o, cap_h=0.05, inset=0.995, cap_at_bottom=False):
    """在底/顶加一块石板，盖住裁切留下的开口（否则单块俯视/仰视会看穿壳体）。"""
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    zs = [v.co.z for v in o.data.vertices]
    w = (max(xs) - min(xs)) * inset
    d = (max(ys) - min(ys)) * inset
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    z0 = min(zs) if cap_at_bottom else max(zs) - cap_h
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, z0 + cap_h * 0.5))
    cap = bpy.context.active_object
    cap.name = "ENV_WALL_LOW_CAP"
    cap.scale = (w, d, cap_h)
    bpy.context.view_layer.objects.active = cap
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    log("cap|size=(%.4f, %.4f, %.4f)|z=%.4f..%.4f|at=%s" % (
        w, d, cap_h, z0, z0 + cap_h, "bottom" if cap_at_bottom else "top"))
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    cap.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.join()
    log("cap|joined|faces=%d" % len(o.data.polygons))


def main():
    log("start|blender=%s|module=%s|cut_top=%.3f" % (bpy.app.version_string, MODULE, CUT_TOP))
    require(os.path.isfile(REF), "src_missing")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.ops.import_scene.gltf(filepath=REF)

    src = None
    for o in bpy.data.objects:
        # 精确到 "wall_stone_stone_wall_low_0"：只用前缀会先命中 wall_stone_low/medium/triplet
        if o.type == "MESH" and o.name.startswith(MODULE + "_stone_wall_low"):
            src = o
            break
    require(src is not None, "module_not_found|%s" % MODULE)
    if src is None:
        sys.exit(1)
    src.data.calc_loop_triangles()
    log("picked|%s|tris=%d|slots=%d" % (src.name, len(src.data.loop_triangles),
                                        len(src.data.materials)))

    mw = src.matrix_world.copy()
    for o in list(bpy.data.objects):
        if o is not src:
            bpy.data.objects.remove(o, do_unlink=True)
    src.parent = None
    src.matrix_world = mw
    bpy.context.view_layer.objects.active = src
    src.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # ① cm → m（源是厘米制）
    for v in src.data.vertices:
        v.co = v.co * UNIT_TO_M
    src.data.update()

    # ② 原点先归到 AABB 中心 + 底面 z=0，再按世界高度裁切
    src.data.calc_loop_triangles()
    xs = [v.co.x for v in src.data.vertices]
    ys = [v.co.y for v in src.data.vertices]
    zs = [v.co.z for v in src.data.vertices]
    off = Vector(((min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5, min(zs)))
    for v in src.data.vertices:
        v.co -= off
    src.data.update()
    log("pre_cut|dims=(%.4f, %.4f, %.4f)" % (
        max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)))
    z_histogram(src.data)
    z_clusters(src.data)

    # ③ 只保留**最上面**的一皮（源件下半部是被地面遮挡的扫描区，石块缺口大；
    #    上半部才是致密砌石）。两端各切一刀，中间石头完全不变形。
    z_hi = max(zs)
    cut_band(src, z_hi - CUT_TOP, z_hi)
    xs = [v.co.x for v in src.data.vertices]
    ys = [v.co.y for v in src.data.vertices]
    zs = [v.co.z for v in src.data.vertices]
    off = Vector(((min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5, min(zs)))
    for v in src.data.vertices:
        v.co -= off
    src.data.update()
    log("recut_origin|dims=(%.4f, %.4f, %.4f)" % (
        max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)))
    # ④ 底面补一块石板，盖住裁切开口（叠起来之后其实看不见，但单块俯视/仰视会透）
    add_cap(src, cap_at_bottom=True)

    # ④ 面朝 +Y（源已经是 +Y 朝外，守住契约，不改朝向）
    rebuild_material(src)

    src.data.calc_loop_triangles()
    xs = [v.co.x for v in src.data.vertices]
    ys = [v.co.y for v in src.data.vertices]
    zs = [v.co.z for v in src.data.vertices]
    dims = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    tris = len(src.data.loop_triangles)
    log("final|tris=%d|dims=(%.4f, %.4f, %.4f)|min_z=%.4f|x=%.4f..%.4f" % (
        tris, dims[0], dims[1], dims[2], min(zs), min(xs), max(xs)))
    require(tris <= TRI_BUDGET, "tri_budget|%d" % tris)
    require(abs(min(zs)) < 5e-4, "not_grounded")
    require(abs(min(xs) + max(xs)) < 2e-2, "x_not_centered")
    require(abs(dims[2] - CUT_TOP) < 2e-2, "cut_height|%.4f" % dims[2])
    # 裁切后必须仍有厚度（不能把壳体裁成一片纸）且不能再是"锥形残堆"（顶部宽度 >= 90% 底宽）
    require(dims[1] > 0.15, "thickness|%.4f" % dims[1])

    src.name = "ENV_WALL_LOW_001"
    bpy.ops.object.select_all(action="DESELECT")
    src.select_set(True)
    bpy.context.view_layer.objects.active = src
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
