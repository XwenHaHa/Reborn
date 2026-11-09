"""T047 辅助：判定"外展(abduction)"到底该绕哪根骨骼轴，并给出两种摆幅下的形变量。

为什么需要：`Bone.00x` 是源 FBX 的无意义命名，骨骼 roll 未知；盲猜欧拉轴会把"外展"
做成"扭转(twist)"，得到'像触手/糖果纸'的假缺陷。这里对同一根骨骼分别绕本地 X/Y/Z
转 +45°，用**链末端骨骼的世界位移**判方向（Y 方向位移最大 = 侧向外展），再按该轴
跑 40° 与 80° 两档，报塌陷/拉丝面数。

用法：
  blender --background --factory-startup --python Tools/Blender/t047b_axis_probe.py -- --in Art/Exports/Cat/SM_Cat_005.glb
输出：`T047B|...`，最后 `T047B|done`。
"""
import sys
import os
import math

import bpy
from mathutils import Euler

REPO = "E:/Reborn"

# 腿链：肩根 → 链末端；髋根 → 链末端（末端骨骼名取自 T046 的骨骼链报告）
CHAINS = {
    "shoulder_R": ("Bone.015", "Bone.018_end"),
    "shoulder_L": ("Bone.019", "Bone.022_end"),
    "hip_R": ("Bone.011", "Bone.014_end"),
    "hip_L": ("Bone.023", "Bone.026_end"),
}


def log(m):
    print("T047B|%s" % m, flush=True)


def arg(name, default=None):
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if name in rest and rest.index(name) + 1 < len(rest):
            return rest[rest.index(name) + 1]
    return default


def face_areas(obj):
    me = obj.data
    me.calc_loop_triangles()
    out = []
    for t in me.loop_triangles:
        a, b, c = (me.vertices[i].co for i in t.vertices)
        out.append(((b - a).cross(c - a)).length * 0.5)
    return out


def posed_areas(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    out = []
    for t in me.loop_triangles:
        a, b, c = (me.vertices[i].co for i in t.vertices)
        out.append(((b - a).cross(c - a)).length * 0.5)
    ev.to_mesh_clear()
    return out


def reset(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler((0.0, 0.0, 0.0), "XYZ")
    bpy.context.view_layer.update()


def tip_world(arm, name):
    pb = arm.pose.bones.get(name)
    return (arm.matrix_world @ pb.head).copy()


def main():
    src = arg("--in", REPO + "/Art/Exports/Cat/SM_Cat_005.glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    obj = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: len(o.data.polygons))
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    rest = face_areas(obj)
    bpy.context.view_layer.objects.active = arm

    for tag, (root, tip) in CHAINS.items():
        reset(arm)
        base = tip_world(arm, tip)
        best_axis, best_dy, best_info = None, -1.0, None
        for axis in ("X", "Y", "Z"):
            reset(arm)
            pb = arm.pose.bones[root]
            eul = [0.0, 0.0, 0.0]
            eul["XYZ".index(axis)] = math.radians(45.0)
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = Euler(eul, "XYZ")
            bpy.context.view_layer.update()
            d = tip_world(arm, tip) - base
            log("axis|%s|%s|d=(%.4f,%.4f,%.4f)|dx=%.4f|dy=%.4f|dz=%.4f" % (
                tag, axis, d.x, d.y, d.z, abs(d.x), abs(d.y), abs(d.z)))
            if abs(d.y) > best_dy:
                best_dy, best_axis = abs(d.y), axis

        for ang in (40.0, 80.0):
            reset(arm)
            pb = arm.pose.bones[root]
            eul = [0.0, 0.0, 0.0]
            eul["XYZ".index(best_axis)] = math.radians(ang)
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = Euler(eul, "XYZ")
            bpy.context.view_layer.update()
            areas = posed_areas(obj)
            ratios = sorted(a / r for r, a in zip(rest, areas) if r > 1e-12)
            n = len(ratios)
            log("pose|%s|axis=%s|deg=%.0f|min=%.4f|p1=%.4f|max=%.4f|collapse=%d|tear=%d" % (
                tag, best_axis, ang, ratios[0], ratios[max(0, int(n * 0.01))], ratios[-1],
                sum(1 for x in ratios if x < 0.5), sum(1 for x in ratios if x > 2.0)))
        reset(arm)

    log("done")
    return 0


sys.exit(main())
