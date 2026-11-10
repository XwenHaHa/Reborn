"""T049c：量出「根骨本地位移 → 世界竖直位移」的真实比例。

现象（2026-11-10）：`AttackCue` 里给根骨写 0.045 的位移，渲染包围盒只降了 ~3 mm。
需要确定性比例，不能靠猜。同时打印骨架对象的世界矩阵/缩放与根骨静置矩阵。
"""
import sys

import bpy
from mathutils import Vector

REPO = "E:/Reborn"


def log(m):
    print("T049C|%s" % m, flush=True)


def arg(name, default=None):
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if name in rest and rest.index(name) + 1 < len(rest):
            return rest[rest.index(name) + 1]
    return default


def bbox_z(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    mn = 1e9
    mx = -1e9
    for v in me.vertices:
        w = obj.matrix_world @ v.co
        mn = min(mn, w.z)
        mx = max(mx, w.z)
    ev.to_mesh_clear()
    return mn, mx


def main():
    src = arg("--in", REPO + "/Art/Exports/Cat/SM_Cat_006.glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=src)
    obj = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: len(o.data.polygons))
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    if arm.animation_data is None:
        arm.animation_data_create()

    s = arm.matrix_world.to_scale()
    log("armature|%s|world_scale=(%.5f,%.5f,%.5f)|obj_scale=(%.5f,%.5f,%.5f)" % (
        arm.name, s.x, s.y, s.z, obj.matrix_world.to_scale().x, obj.matrix_world.to_scale().y,
        obj.matrix_world.to_scale().z))
    root = arm.pose.bones["Bone"]
    m = root.bone.matrix_local
    log("root_rest|basis_x=(%.4f,%.4f,%.4f)|basis_y=(%.4f,%.4f,%.4f)|basis_z=(%.4f,%.4f,%.4f)" % (
        m[0][0], m[1][0], m[2][0], m[0][1], m[1][1], m[2][1], m[0][2], m[1][2], m[2][2]))
    log("root_head|(%.4f,%.4f,%.4f)|length=%.4f" % (m[0][3], m[1][3], m[2][3], root.bone.length))

    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    mn0, mx0 = bbox_z(obj)
    log("rest|z_min=%.5f|z_max=%.5f" % (mn0, mx0))

    inv = root.bone.matrix_local.to_3x3().inverted()
    for dz in (-0.05, -0.10):
        root.location = inv @ Vector((0.0, 0.0, dz))
        bpy.context.view_layer.update()
        mn, mx = bbox_z(obj)
        log("local_dz=%.3f|z_min=%.5f|z_max=%.5f|world_drop_max=%.5f|world_drop_min=%.5f" % (
            dz, mn, mx, mx0 - mx, mn0 - mn))

    for axis, vec in (("X", (1.0, 0.0, 0.0)), ("Y", (0.0, 1.0, 0.0)), ("Z", (0.0, 0.0, 1.0))):
        root.location = vec
        bpy.context.view_layer.update()
        mn, mx = bbox_z(obj)
        log("unit_%s|z_min=%.5f|z_max=%.5f|dz_max=%.5f" % (axis, mn, mx, mx0 - mx))
    root.location = (0.0, 0.0, 0.0)
    log("done")
    return 0


sys.exit(main())
