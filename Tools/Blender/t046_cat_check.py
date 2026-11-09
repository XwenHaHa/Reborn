"""T046：猫资产的拓扑 / UV / 材质检查（Blender 3.3.1 无头）。

用法：
  blender --background --factory-startup --python Tools/Blender/t046_cat_check.py -- <glb|fbx 路径>

输出：每行 `T046|key=value`，最后 `T046|done`。

**为什么报两组拓扑数**：glTF 导入会在 UV/法线接缝处**拆点**（ART03 实测过），
拆点后 `is_manifold` 会大量为假、边界边暴涨 —— 这是导入产物，不是模型缺陷。
所以先按原样报一组（`raw`），再用 1e-5 焊点报一组（`welded`），判据只看 `welded`。

判据（开发计划 T046：无意外非流形、翻面和严重拉伸；材质尽量简单、无复杂毛发）：
- `welded` 的真非流形边（=非流形 − 边界）= 0；退化面 = 0；孤立点 = 0。
- 翻面：焊点后重算法线，方向反转的面应为 0。
- UV 拉伸：逐三角算 UV→三维映射的**边长比各向异性**（≈1 为保形），报中位数/p95/最大值、
  >2× 与 >4× 的面数，并按**主导骨骼**分组给出扁平区间，便于定位到身体部位。
- 材质：槽数 ≤2、贴图 ≤2048²、无粒子/毛发修改器。
"""
import sys
import os
import json
import statistics

import bpy
import bmesh


def arg_path():
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if rest:
            return rest[0]
    raise SystemExit("need asset path after --")


def import_any(path):
    if path.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)


def tri_list(mesh):
    mesh.calc_loop_triangles()
    return [(lt.vertices[:], lt.loops[:]) for lt in mesh.loop_triangles]


def uv_distortion(mesh, uv_layer, obj):
    """逐三角各向异性 + 按主导骨骼分组定位。"""
    uv = uv_layer.data
    groups = {g.index: g.name for g in obj.vertex_groups}
    per_face = []  # (ratio, group_name, [p0,p1,p2])
    for verts, loops in tri_list(mesh):
        if len(verts) != 3:
            continue
        p = [mesh.vertices[i].co for i in verts]
        t = [uv[i].uv for i in loops]
        e1 = p[1] - p[0]
        e2 = p[2] - p[0]
        f1 = t[1] - t[0]
        f2 = t[2] - t[0]
        if abs(f1.x * f2.y - f1.y * f2.x) < 1e-14:
            continue
        l3a = e1.length
        l3b = e2.length
        l2a = f1.length
        l2b = f2.length
        if l2a < 1e-9 or l2b < 1e-9:
            continue
        if (e1.cross(e2)).length * 0.5 < 1e-12:
            continue
        s1 = l2a / l3a if l3a > 1e-9 else 0.0
        s2 = l2b / l3b if l3b > 1e-9 else 0.0
        if s1 <= 0 or s2 <= 0:
            continue
        ratio = max(s1, s2) / min(s1, s2)
        acc = {}
        for vi in verts:
            for g in mesh.vertices[vi].groups:
                acc[g.group] = acc.get(g.group, 0.0) + g.weight
        name = groups.get(max(acc, key=acc.get), "-") if acc else "-"
        per_face.append((ratio, name, [(float(v.x), float(v.y), float(v.z)) for v in p]))

    if not per_face:
        return None
    ratios = sorted(r for r, _, _ in per_face)
    n = len(ratios)

    by_group = {}
    for r, name, pts in per_face:
        d = by_group.setdefault(name, [0, 0.0, [1e9, 1e9, 1e9], [-1e9, -1e9, -1e9]])
        if r > 4.0:
            d[0] += 1
        d[1] = max(d[1], r)
        for v in pts:
            for k in range(3):
                d[2][k] = min(d[2][k], v[k])
                d[3][k] = max(d[3][k], v[k])
    top = sorted(by_group.items(), key=lambda kv: (-kv[1][0], -kv[1][1]))[:6]

    return {
        "faces": n,
        "median": statistics.median(ratios),
        "p95": ratios[min(n - 1, int(n * 0.95))],
        "max": ratios[-1],
        "over_2x": sum(1 for r in ratios if r > 2.0),
        "over_4x": sum(1 for r in ratios if r > 4.0),
        "top": [[name, cnt, round(mx, 3), [round(x, 4) for x in mn], [round(x, 4) for x in mx_b]]
                for name, (cnt, mx, mn, mx_b) in top],
    }


def topology_stats(mesh, weld=False):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    if weld:
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bm.faces.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    non_manifold = sum(1 for e in bm.edges if not e.is_manifold)
    boundary = sum(1 for e in bm.edges if e.is_boundary)
    loose = sum(1 for v in bm.verts if not v.link_edges)
    degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-10)
    before = [f.normal.copy() for f in bm.faces]
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    flipped = sum(1 for f, n0 in zip(bm.faces, before) if f.normal.dot(n0) < 0.0)
    vol = bm.calc_volume(signed=True)
    stats = {
        "verts": len(bm.verts),
        "faces": len(bm.faces),
        "non_manifold_edges": non_manifold,
        "non_manifold_excluding_boundary": non_manifold - boundary,
        "boundary_edges": boundary,
        "loose_verts": loose,
        "degenerate_faces": degenerate,
        "flipped_after_recalc": flipped,
        "flipped_ratio": flipped / max(1, len(bm.faces)),
        "signed_volume": vol,
    }
    bm.free()
    return stats


def main():
    path = arg_path()
    print("T046|asset=%s|exists=%s|bytes=%d" % (
        path, os.path.exists(path), os.path.getsize(path) if os.path.exists(path) else -1))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import_any(path)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    print("T046|objects|mesh=%d|armature=%d|names=%s" % (
        len(meshes), len(arms), json.dumps([o.name for o in meshes], ensure_ascii=False)))
    if arms:
        bones = [b.name for b in arms[0].data.bones]
        print("T046|armature|bones=%d|first8=%s" % (len(bones), json.dumps(bones[:8], ensure_ascii=False)))
    if not meshes:
        print("T046|ERROR|no_mesh")
        print("T046|done")
        return

    # 取面数最多的网格（FBX 源里还有眼球等小件；GLB 里已合并为一个）
    obj = max(meshes, key=lambda o: len(o.data.polygons))
    me = obj.data
    me.calc_loop_triangles()
    print("T046|mesh|object=%s|name=%s|verts=%d|tris=%d|polys=%d|materials=%d" % (
        obj.name, me.name, len(me.vertices), len(me.loop_triangles), len(me.polygons), len(me.materials)))

    for tag, weld in (("raw", False), ("welded", True)):
        st = topology_stats(me, weld=weld)
        print(("T046|topology|%s|verts=%d|faces=%d|non_manifold_edges=%d|"
               "non_manifold_excluding_boundary=%d|boundary_edges=%d|loose_verts=%d|"
               "degenerate_faces=%d|flipped_after_recalc=%d|flipped_ratio=%.4f|signed_volume=%.6f") % (
            tag, st["verts"], st["faces"], st["non_manifold_edges"],
            st["non_manifold_excluding_boundary"], st["boundary_edges"], st["loose_verts"],
            st["degenerate_faces"], st["flipped_after_recalc"], st["flipped_ratio"],
            st["signed_volume"]))

    uvs = me.uv_layers
    print("T046|uv|layers=%d|names=%s" % (len(uvs), json.dumps([l.name for l in uvs], ensure_ascii=False)))
    if len(uvs) > 0:
        uv = uvs[0].data
        umin = vmin = 1e9
        umax = vmax = -1e9
        outside = 0
        for d in uv:
            u, v = d.uv
            umin = min(umin, u); umax = max(umax, u)
            vmin = min(vmin, v); vmax = max(vmax, v)
            if u < -1e-6 or u > 1.0 + 1e-6 or v < -1e-6 or v > 1.0 + 1e-6:
                outside += 1
        print("T046|uv|bounds=[%.4f,%.4f]-[%.4f,%.4f]|loops_outside_0_1=%d" % (
            umin, vmin, umax, vmax, outside))
        dist = uv_distortion(me, uvs[0], obj)
        if dist:
            print("T046|uv|distortion|faces=%d|median=%.3f|p95=%.3f|max=%.3f|over_2x=%d|over_4x=%d" % (
                dist["faces"], dist["median"], dist["p95"], dist["max"],
                dist["over_2x"], dist["over_4x"]))
            print("T046|uv|distortion_by_group|%s" % json.dumps(dist["top"], ensure_ascii=False))

    for i, slot in enumerate(obj.material_slots):
        mat = slot.material
        if mat is None:
            print("T046|material|slot=%d|null" % i)
            continue
        imgs = []
        if mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image is not None:
                    im = node.image
                    imgs.append({"name": im.name, "size": list(im.size),
                                 "colorspace": im.colorspace_settings.name})
        print("T046|material|slot=%d|name=%s|images=%s" % (
            i, mat.name, json.dumps(imgs, ensure_ascii=False)))

    hair = [m.type for o in meshes for m in o.modifiers if m.type in ("PARTICLE_SYSTEM", "HAIR")]
    print("T046|fur|particle_or_hair_modifiers=%d|vertex_groups=%d" % (len(hair), len(obj.vertex_groups)))
    print("T046|done")


main()
