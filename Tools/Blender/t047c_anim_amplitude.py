"""T047 辅助：量**游戏内三段动画实际用到的摆幅**，并在动画自身的极值帧上量形变。

两个问题必须分开回答：
1. 动画里的腿根到底转了多少度？（决定"80° 极限测试"是否属于发货范围）
2. 动画自身的极值帧上，有没有面积塌陷/拉丝？（决定发货质量）

做法：导入 `SM_Cat_005.glb`，逐动画逐帧：
- 读腿根 `pose_bone.rotation_quaternion` → 欧拉角，取各轴绝对值最大；
- 用 depsgraph 求值网格，逐三角比较"姿态面积 / 静止面积"：`<0.5` 记塌陷、`>2.0` 记拉丝；
- 记录爪尖世界位移幅度与最差帧号。

用法：
  blender --background --factory-startup --python Tools/Blender/t047c_anim_amplitude.py -- --in Art/Exports/Cat/SM_Cat_005.glb
输出：`T047C|...`，最后 `T047C|done`。
"""
import sys
import math

import bpy

REPO = "E:/Reborn"

LEG_ROOTS = {
    "shoulder_R": "Bone.015",
    "shoulder_L": "Bone.019",
    "hip_R": "Bone.011",
    "hip_L": "Bone.023",
}
TIP = {
    "shoulder_R": "Bone.018_end",
    "shoulder_L": "Bone.022_end",
    "hip_R": "Bone.014_end",
    "hip_L": "Bone.026_end",
}
TAIL_ROOTS = ["Bone.005", "Bone.007"]


def log(m):
    print("T047C|%s" % m, flush=True)


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


def main():
    src = arg("--in", REPO + "/Art/Exports/Cat/SM_Cat_005.glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    bpy.ops.import_scene.gltf(filepath=src)
    obj = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: len(o.data.polygons))
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    if arm.animation_data is None:
        arm.animation_data_create()
    rest = face_areas(obj)
    actions = sorted(bpy.data.actions, key=lambda a: a.name)
    log("actions=%s" % [a.name for a in actions])

    for act in actions:
        arm.animation_data.action = act
        f0, f1 = act.frame_range
        max_deg = {k: 0.0 for k in LEG_ROOTS}
        max_tail = {k: 0.0 for k in TAIL_ROOTS}
        travel = {k: 0.0 for k in LEG_ROOTS}
        prev = {}
        worst = {"frame": -1, "collapse": -1, "tear": -1, "min_ratio": 9.9}
        f = int(math.floor(f0))
        last = int(math.ceil(f1))
        while f <= last:
            bpy.context.scene.frame_set(f)
            bpy.context.view_layer.update()
            for tag, bone in LEG_ROOTS.items():
                pb = arm.pose.bones.get(bone)
                if pb is None:
                    continue
                e = pb.rotation_quaternion.to_euler("XYZ")
                max_deg[tag] = max(max_deg[tag], max(abs(math.degrees(e.x)),
                                                     abs(math.degrees(e.y)),
                                                     abs(math.degrees(e.z))))
                tip = arm.matrix_world @ arm.pose.bones[TIP[tag]].head
                if tag in prev:
                    travel[tag] += (tip - prev[tag]).length
                prev[tag] = tip
            for bone in TAIL_ROOTS:
                pb = arm.pose.bones.get(bone)
                if pb is None:
                    continue
                e = pb.rotation_quaternion.to_euler("XYZ")
                max_tail[bone] = max(max_tail[bone], max(abs(math.degrees(e.x)),
                                                         abs(math.degrees(e.y)),
                                                         abs(math.degrees(e.z))))
            areas = posed_areas(obj)
            ratios = [a / r for r, a in zip(rest, areas) if r > 1e-12]
            collapse = sum(1 for x in ratios if x < 0.5)
            tear = sum(1 for x in ratios if x > 2.0)
            min_ratio = min(ratios) if ratios else 0.0
            if collapse + tear > worst["collapse"] + worst["tear"]:
                worst = {"frame": f, "collapse": collapse, "tear": tear, "min_ratio": min_ratio}
            f += 1

        log("anim|%s|frames=%d..%d|duration_s=%.3f" % (act.name, int(f0), last, (last - int(f0)) / 30.0))
        for tag in LEG_ROOTS:
            log("anim|%s|%s|max_bone_rot_deg=%.1f|paw_travel_m=%.3f" % (
                act.name, tag, max_deg[tag], travel[tag]))
        for bone in TAIL_ROOTS:
            log("anim|%s|tail|%s|max_bone_rot_deg=%.1f" % (act.name, bone, max_tail[bone]))
        log("deform|%s|worst_frame=%d|collapse_faces=%d|tear_faces=%d|min_area_ratio=%.4f" % (
            act.name, worst["frame"], worst["collapse"], worst["tear"], worst["min_ratio"]))

    log("done")
    return 0


sys.exit(main())
