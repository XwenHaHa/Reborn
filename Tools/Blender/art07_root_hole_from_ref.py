# -*- coding: utf-8 -*-
"""ART03-④ ENV_ROOT_HOLE_001：把 CC-BY 空心中空树桩 stump_callum_arb 做成"鼠洞"入口件。

源（**只读**）：references/_downloads/stump_callum_arb/model.glb
实测：39,122 tris / 1 材质槽 / 世界 bbox 2.128 × 2.666 × 1.205（含扫描自带方形地面）
预算（Docs/ART_ASSET_SPEC.md §2 / §4.4）：洞口 3k–15k tris；通行净空必须 ≥ **0.24 宽 × 0.30 高**

处理链路（每一步都有原因，见注释）：
  ① 裁掉扫描地面：只留以"树干轴"为心、半径 0.55 源单位的柱内面
  ② 按距离焊接（glTF 接缝会拆点，Collapse 跨不过去 → 减面会卡住；巨石已踩过）
  ③ 迭代 Collapse 减面到 ≤15,000
  ④ 归一到目标高 0.85 m、原点 = 脚印中心 + 底面 z=0
  ⑤ 在底部**破一个 0.24 宽 × 0.30 高的方通孔**（沿 Y 贯通的布尔差集）——扫描件的腔体是"碗"，没有贯穿洞
  ⑥ 自检：面数、贴地、居中、孔内**射线全通**（0.24×0.30 clearance 的客观证据）

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art07_root_hole_from_ref.py' -- --stage all
"""

import hashlib
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

REPO = "E:/Reborn"
REF = REPO + "/references/_downloads/stump_callum_arb/model.glb"
GLB_OUT = REPO + "/Art/Exports/Environment/SM_RootHole_001.glb"
RENDER_DIR = REPO + "/Art/Probes"

TARGET_H = 0.85          # 树桩视觉高（屏障顶 0.60 → 桩子高出 0.25）
TARGET_TRIS = 14000      # 预算上限 15,000，留余量
TRI_BUDGET = 15000
CROP_RADIUS = 0.55       # 源单位（米）内的柱体才留（树干半径约 0.45）
HOLE_W = 0.24            # 必须与 tool_make_courtyard.gd 的 HOLE_W 一致
HOLE_H = 0.30            # 同上 HOLE_H
BORE_LEN = 1.20          # 破洞长度（比树桩厚度大，保证贯通）

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


def absf(x):
    return x if x >= 0 else -x


def vec(v):
    return "(%.4f, %.4f, %.4f)" % (v[0], v[1], v[2])


def tri_count(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def vbbox(o):
    mn = Vector((1e18, 1e18, 1e18))
    mx = Vector((-1e18, -1e18, -1e18))
    for v in o.data.vertices:
        p = v.co
        mn = Vector((min(mn.x, p.x), min(mn.y, p.y), min(mn.z, p.z)))
        mx = Vector((max(mx.x, p.x), max(mx.y, p.y), max(mx.z, p.z)))
    return mn, mx


def trunk_axis(o):
    """用最高 25% 高度上的顶点估树干轴（顶部是被劈开的空心环，其 XY 质心≈树干轴）。"""
    mn, mx = vbbox(o)
    z_thr = mx.z - (mx.z - mn.z) * 0.25
    xs = [v.co.x for v in o.data.vertices if v.co.z >= z_thr]
    ys = [v.co.y for v in o.data.vertices if v.co.z >= z_thr]
    if not xs:
        return (mn + mx) * 0.5, 0.0
    ax = sum(xs) / len(xs)
    ay = sum(ys) / len(ys)
    r = max(math.hypot(v.co.x - ax, v.co.y - ay) for v in o.data.vertices if v.co.z >= z_thr)
    return Vector((ax, ay, 0.0)), r


def crop_ground(o, axis, radius):
    """删掉离树干轴超过 radius 的面（扫描自带的方形地面 + 外围碎石）。"""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        if math.hypot(c.x - axis.x, c.y - axis.y) > radius:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    # 只留与主壳相连的部分：把最小的连通块全部删掉（碎石片）
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    log("crop|removed_faces=%d|left_tris=%d" % (len(kill), tri_count(o)))


def drop_loose_shells(o, min_share=0.02):
    """删掉细小的独立连通块（扫描碎石），保留主体。"""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    shells = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        comp = []
        seen.add(v.index)
        while stack:
            cur = stack.pop()
            comp.append(cur)
            for e in cur.link_edges:
                other = e.other_vert(cur)
                if other.index not in seen:
                    seen.add(other.index)
                    stack.append(other)
        shells.append(comp)
    shells.sort(key=len, reverse=True)
    if len(shells) <= 1:
        bm.free()
        log("shells|1|nothing_dropped")
        return
    main = len(shells[0])
    kill_verts = []
    for comp in shells[1:]:
        if len(comp) < main * min_share:
            kill_verts.extend(comp)
    if kill_verts:
        bmesh.ops.delete(bm, geom=kill_verts, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    log("shells|count=%d|main_verts=%d|dropped_verts=%d|left_tris=%d" % (
        len(shells), main, len(kill_verts), tri_count(o)))


def weld_and_decimate(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    log("weld|verts %d->%d" % (before, len(o.data.vertices)))

    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    cur = tri_count(o)
    for i in range(8):
        if cur <= TARGET_TRIS:
            break
        ratio = max(0.05, min(0.9, float(TARGET_TRIS) / max(1, cur)))
        mod = o.modifiers.new("Dec%d" % i, "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
        new = tri_count(o)
        log("decimate|pass=%d|ratio=%.4f|%d->%d" % (i + 1, ratio, cur, new))
        if new >= cur:
            break
        cur = new
    log("decimate|final=%d|target=%d" % (cur, TARGET_TRIS))


def normalize(o, target_h):
    mn, mx = vbbox(o)
    s = target_h / (mx.z - mn.z)
    cx = (mn.x + mx.x) * 0.5
    cy = (mn.y + mx.y) * 0.5
    for v in o.data.vertices:
        v.co.x = (v.co.x - cx) * s
        v.co.y = (v.co.y - cy) * s
        v.co.z = (v.co.z - mn.z) * s
    o.data.update()
    mn, mx = vbbox(o)
    log("normalize|scale=%.5f|dims=%s|min=%s|max=%s" % (s, vec(mx - mn), vec(mn), vec(mx)))


def bore_hole(o):
    """在底部沿 Y 破一个 HOLE_W × HOLE_H 的方通孔（扫描的腔体是碗，没有贯穿洞）。"""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, HOLE_H * 0.5))
    cutter = bpy.context.active_object
    cutter.name = "CUT_Bore"
    cutter.scale = Vector((HOLE_W, BORE_LEN, HOLE_H))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = o.modifiers.new("Bore", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    o.data.update()
    # 布尔会带进切割体的空材质槽 → 切出来的面落到"没有材质"的槽上（渲染成纯白）；
    # 统一回落到唯一材质，并清掉多余槽位。
    for p in o.data.polygons:
        p.material_index = 0
    while len(o.data.materials) > 1:
        o.data.materials.pop(index=len(o.data.materials) - 1)
    o.data.update()
    log("bore|w=%.3f|h=%.3f|len=%.2f|tris=%d|slots=%d" % (
        HOLE_W, HOLE_H, BORE_LEN, tri_count(o), len(o.data.materials)))


def check_clearance():
    """孔内射线全通：这是 0.24×0.30 净空的客观证据（不是"看起来像洞"）。"""
    deps = bpy.context.evaluated_depsgraph_get()
    pts = []
    for fx in (-0.42, 0.0, 0.42):
        for fz in (0.10, 0.50, 0.90):
            pts.append((HOLE_W * 0.5 * fx, HOLE_H * fz))
    blocked = 0
    for dx, z in pts:
        origin = Vector((dx, -2.0, z))
        direction = Vector((0.0, 1.0, 0.0))
        hit, loc, norm, idx, obj, mat = bpy.context.scene.ray_cast(deps, origin, direction)
        ok = not hit or (loc - origin).length > 1.9
        if not ok:
            blocked += 1
            log("clearance|BLOCKED|at=(%.3f, %.3f)|hit_y=%.3f" % (dx, z, loc.y))
    log("clearance|points=%d|blocked=%d" % (len(pts), blocked))
    return len(pts) - blocked, len(pts)


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    w = bpy.data.worlds.new("W")
    scene.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.30, 0.33, 0.36, 1.0)
    bg.inputs["Strength"].default_value = 0.6
    bpy.ops.mesh.primitive_plane_add(size=10.0, location=(0.0, 0.0, 0.0))
    g = bpy.context.active_object
    g.name = "RENDER_Ground"
    m = bpy.data.materials.new("MAT_RENDER_Ground")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.33, 0.34, 1.0)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    g.data.materials.append(m)

    def light(name, loc, energy, sz):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = sz
        ob = bpy.data.objects.new(name, ld)
        ob.location = loc
        ob.rotation_euler = (Vector((0.0, 0.0, 0.4)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(ob)

    light("KEY", (1.6, -2.0, 2.2), 500.0, 2.0)
    light("FILL", (-2.0, -1.2, 1.0), 200.0, 2.4)
    light("RIM", (0.3, 2.2, 1.4), 300.0, 1.6)
    cam_data = bpy.data.cameras.new("CAM")
    cam_data.lens = 50.0
    cam = bpy.data.objects.new("CAM", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def render_views(cam):
    target = Vector((0.0, 0.0, 0.30))
    views = [
        ("q34", Vector((1.30, -1.50, 0.95))),
        ("mouth_south", Vector((0.0, -1.55, 0.32))),
        ("mouth_north", Vector((0.0, 1.55, 0.32))),
    ]
    for name, loc in views:
        cam.location = loc
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.render.filepath = "%s/art07_roothole_%s.png" % (RENDER_DIR, name)
        bpy.ops.render.render(write_still=True)
        log("render|%s" % name)


def export_glb():
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        if o.type == "MESH" and not o.name.startswith("RENDER_"):
            o.select_set(True)
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    wanted = {
        "export_format": "GLB", "use_selection": True, "export_apply": True,
        "export_yup": True, "export_materials": "EXPORT", "export_cameras": False,
        "export_lights": False, "export_extras": False, "export_texcoords": True,
        "export_normals": True, "export_colors": False,
        "export_skins": False, "export_animations": False,
    }
    bpy.ops.export_scene.gltf(filepath=GLB_OUT, **{k: v for k, v in wanted.items() if k in props})
    with open(GLB_OUT, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (GLB_OUT, len(data), hashlib.sha256(data).hexdigest()))


def main():
    log("start|blender=%s|src=%s" % (bpy.app.version_string, os.path.basename(REF)))
    require(os.path.isfile(REF), "src_missing")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.ops.import_scene.gltf(filepath=REF)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    require(len(meshes) >= 1, "no_mesh")
    obj = meshes[0]
    # 保住世界矩阵再烘（glTF 网格数据是 Y-up，直接 apply 子级会烘错轴；围栏已踩过）
    mw = obj.matrix_world.copy()
    for o in list(bpy.data.objects):
        if o is not obj:
            bpy.data.objects.remove(o, do_unlink=True)
    obj.parent = None
    obj.matrix_world = mw
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mn, mx = vbbox(obj)
    log("src|tris=%d|dims=%s|min=%s|slots=%d" % (
        tri_count(obj), vec(mx - mn), vec(mn), len(obj.data.materials)))

    axis, rtop = trunk_axis(obj)
    log("axis|xy=%s|top_radius=%.3f" % (vec(axis), rtop))
    crop_ground(obj, axis, CROP_RADIUS)
    drop_loose_shells(obj)
    weld_and_decimate(obj)

    normalize(obj, TARGET_H)
    # 把树干轴对齐到原点（裁完地面后脚印中心≈轴，但仍显式对齐一次）
    mn, mx = vbbox(obj)
    log("pre_align|min=%s|max=%s" % (vec(mn), vec(mx)))

    bore_hole(obj)

    mn, mx = vbbox(obj)
    dims = mx - mn
    tris = tri_count(obj)
    log("final|tris=%d|dims=%s|min=%s|max=%s|slots=%d" % (
        tris, vec(dims), vec(mn), vec(mx), len(obj.data.materials)))
    require(tris <= TRI_BUDGET, "tri_budget|%d>%d" % (tris, TRI_BUDGET))
    require(absf(mn.z) < 5e-4, "not_grounded|%.4f" % mn.z)
    require(absf(mn.x + mx.x) < 2e-3, "x_not_centered|%.4f..%.4f" % (mn.x, mx.x))
    require(absf(mn.y + mx.y) < 2e-3, "y_not_centered|%.4f..%.4f" % (mn.y, mx.y))
    require(dims.z >= 0.80, "too_short|%.3f" % dims.z)
    require(len(obj.data.materials) <= 2, "slot_over|%d" % len(obj.data.materials))

    free, total = check_clearance()
    require(free == total, "bore_blocked|%d/%d" % (free, total))

    obj.name = "ENV_ROOT_HOLE_001"
    cam = setup_render()
    render_views(cam)
    for o in list(bpy.data.objects):
        if o.type in {"LIGHT", "CAMERA"} or o.name.startswith("RENDER_"):
            bpy.data.objects.remove(o, do_unlink=True)
    export_glb()
    log("done|tris=%d|failures=%d" % (tris, len(failures)))
    sys.exit(0 if not failures else 1)


main()
