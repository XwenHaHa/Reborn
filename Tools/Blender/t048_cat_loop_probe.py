"""T048：猫的循环动画检查 —— Idle / Walk / Run 的**首末帧闭合**与**根运动**。

验收词（开发计划 :216）：两段动画可循环；优先**原地动画**，避免根运动与 CharacterMovement 重复位移。

判据（关键区别）：
- **首末帧闭合**：所有骨骼的本地四元数在 `f0` 与 `fN` 上一致（阈值 1°）。
- **水平根漂移**：根骨（`Bone`，脊椎根）在**地面平面（x,y）**上相对首帧的最大位移——> 5 mm 说明有根运动，会和 `CharacterBody3D` 的位移叠加。
- **竖向起伏**：`|dz|` 只记录不判负——那是刻意的身体 bob（art16 的 `bob` 0.016/0.020 m）。
- **净位移**：`fN` 与 `f0` 的根骨位移应≈0（原地动画）。
- **location 轨道**：任何**单调累加**的 `location` 曲线都视为真根运动。

用法：
  blender --background --factory-startup --python Tools/Blender/t048_cat_loop_probe.py -- \
      --in Art/Exports/Cat/SM_Cat_005.glb
输出：`T048|...`，末行 `T048|done`。
"""
import sys
import math

import bpy

REPO = "E:/Reborn"
CLIPS = ["Idle", "Walk", "Run"]
ROOT_BONE = "Bone"
LOOP_ANGLE_TOL_DEG = 1.0
HORIZONTAL_DRIFT_TOL_M = 0.005


def log(m):
    print("T048|%s" % m, flush=True)


def arg(name, default=None):
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if name in rest and rest.index(name) + 1 < len(rest):
            return rest[rest.index(name) + 1]
    return default


def sample(arm):
    q = {b.name: b.rotation_quaternion.copy() for b in arm.pose.bones}
    p = (arm.matrix_world @ arm.pose.bones[ROOT_BONE].head).copy()
    return q, p


def main():
    src = arg("--in", REPO + "/Art/Exports/Cat/SM_Cat_005.glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    bpy.ops.import_scene.gltf(filepath=src)

    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    if arm.animation_data is None:
        arm.animation_data_create()
    log("rig|bones=%d|actions=%s" % (len(arm.data.bones), [a.name for a in bpy.data.actions]))

    for clip in CLIPS:
        act = None
        for a in bpy.data.actions:
            if a.name.startswith(clip):
                act = a
                break
        if act is None:
            log("ERROR|action_missing|%s" % clip)
            continue
        arm.animation_data.action = act
        f0 = int(math.floor(act.frame_range[0]))
        f1 = int(math.ceil(act.frame_range[1]))

        bpy.context.scene.frame_set(f0)
        bpy.context.view_layer.update()
        first_q, root0 = sample(arm)

        max_pose = 0.0
        worst_bone = "-"
        max_h = 0.0
        max_v = 0.0
        end_q, end_p = first_q, root0
        for f in range(f0, f1 + 1):
            bpy.context.scene.frame_set(f)
            bpy.context.view_layer.update()
            q, p = sample(arm)
            for name, qq in q.items():
                qa = first_q.get(name)
                if qa is None:
                    continue
                ang = math.degrees(qa.rotation_difference(qq).angle)
                if ang > max_pose:
                    max_pose = ang
                    worst_bone = name
            d = p - root0
            max_h = max(max_h, math.sqrt(d.x * d.x + d.y * d.y))
            max_v = max(max_v, abs(d.z))
            if f == f1:
                end_q, end_p = q, p

        end_angle = 0.0
        end_worst = "-"
        for name, qq in end_q.items():
            qa = first_q.get(name)
            if qa is None:
                continue
            ang = math.degrees(qa.rotation_difference(qq).angle)
            if ang > end_angle:
                end_angle = ang
                end_worst = name
        root_delta = (end_p - root0).length

        loc_mono = 0
        for fc in act.fcurves:
            if not fc.data_path.endswith("location"):
                continue
            vals = [kp.co[1] for kp in fc.keyframe_points]
            if len(vals) >= 3:
                net = vals[-1] - vals[0]
                span = max(vals) - min(vals)
                if abs(net) > 1e-4 and abs(net) > 0.5 * span:
                    loc_mono += 1

        log("clip|%s|frames=%d..%d|closure_deg=%.3f|closure_worst=%s|"
            "max_pose_deg=%.2f|max_pose_bone=%s|drift_horizontal_m=%.4f|drift_vertical_m=%.4f|"
            "net_root_delta_m=%.4f|monotonic_location_curves=%d" % (
                clip, f0, f1, end_angle, end_worst, max_pose, worst_bone,
                max_h, max_v, root_delta, loc_mono))

        verdict = "PASS"
        if end_angle > LOOP_ANGLE_TOL_DEG:
            verdict = "FAIL_CLOSURE"
        elif max_h > HORIZONTAL_DRIFT_TOL_M:
            verdict = "FAIL_ROOT_MOTION"
        elif root_delta > HORIZONTAL_DRIFT_TOL_M:
            verdict = "FAIL_NET_DRIFT"
        elif loc_mono > 0:
            verdict = "FAIL_MONOTONIC_LOCATION"
        log("verdict|%s|%s" % (clip, verdict))

    arm.animation_data.action = None
    log("done")
    return 0


sys.exit(main())
