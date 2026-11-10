"""T049b：查 `SM_Cat_006.glb` 是否有杂散几何（独立岛屿/孤立部件）。

为什么：攻击提示帧的视觉判读提到「腹部下方有一根灰白杆状物」，需要确认它到底是
  (a) 网格里真的多出一块几何（资产缺陷），
  (b) 还是地面板/透视下的腿部切片（渲染设置问题）。
判据是确定性数字，不靠肉眼。

用法：
  blender --background --factory-startup --python Tools/Blender/t049b_geom_probe.py -- \
      --in Art/Exports/Cat/SM_Cat_006.glb
输出：`T049B|obj|...` 逐对象，`T049B|island|...` 逐岛屿（按三角数降序，只报 <=64 面的小块），末行 `T049B|done`
"""
import sys

import bpy
import bmesh

REPO = "E:/Reborn"


def log(m):
    print("T049B|%s" % m, flush=True)


def arg(name, default=None):
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if name in rest and rest.index(name) + 1 < len(rest):
            return rest[rest.index(name) + 1]
    return default


def main():
    src = arg("--in", REPO + "/Art/Exports/Cat/SM_Cat_006.glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=src)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    log("objects|mesh=%d|names=%s" % (len(meshes), [o.name for o in meshes]))
    for o in meshes:
        log("obj|%s|verts=%d|tris=%d|mats=%d|parent=%s" % (
            o.name, len(o.data.vertices), sum(len(p.vertices) - 2 for p in o.data.polygons),
            len(o.data.materials), o.parent.name if o.parent else None))

    main_obj = max(meshes, key=lambda o: len(o.data.polygons))
    bm = bmesh.new()
    bm.from_mesh(main_obj.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    islands = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        seen.add(v.index)
        group = []
        while stack:
            cur = stack.pop()
            group.append(cur)
            for e in cur.link_edges:
                other = e.other_vert(cur)
                if other.index not in seen:
                    seen.add(other.index)
                    stack.append(other)
        islands.append(group)
    islands.sort(key=len, reverse=True)
    log("islands|%s|count=%d|vert_counts=%s" % (
        main_obj.name, len(islands), [len(g) for g in islands[:12]]))
    for i, g in enumerate(islands):
        tris = sum(len(v.link_faces) for v in g) // 3
        if len(g) <= 64:
            xs = [v.co.x for v in g]
            ys = [v.co.y for v in g]
            zs = [v.co.z for v in g]
            log("island|i=%d|verts=%d|faces~%d|bbox=[%.3f,%.3f,%.3f]-[%.3f,%.3f,%.3f]" % (
                i, len(g), tris, min(xs), min(ys), min(zs), max(xs), max(ys), max(zs)))
    log("done")
    return 0


sys.exit(main())
