"""T049：给猫补一段 **`AttackCue`**（攻击提示）动画，导出 `SM_Cat_006.glb`。

背景（开发计划 :217）：给 NPC 最小动作反馈，**动画时间要和攻击事件吻合**。
现役 `SM_Cat_005` 只有 `Idle/Walk/Run`；`AttackSettlement` 的前摇是
`SpeciesConfig.attack_telegraph = 0.45 s`（`Parameters.md` 第 69 行），所以这段
提示动画长度取 **0.45 s**（60 fps 下 0..27 帧，恰好 27/60）。

动作内容（**原地**，不加根位移；三段关键姿态：基准 → 蓄势压低抬爪 → 出爪前探）：
- f0  (0.00 s)：静止基准（全零）；
- f8  (0.133 s)：压低——根骨降 1.4 cm、脊/颈前倾、尾巴抬起、四肢弯曲；
- f16 (0.267 s)：蓄势峰值——根骨降 1.8 cm、**左前爪抬起 44°**、后腿蓄力；
- f27 (0.450 s)：出爪——头颈前探、前腿前伸 38°、后腿蹬直，保持到尾帧。
  （竖直压低刻意不超过 2 cm：根骨位移会带着整只猫一起下沉，压低过多会让脚陷进地面。）

不覆盖原资产：输入 `SM_Cat_005.glb`，输出 `SM_Cat_006.glb`（已存在则拒绝）。

用法：
  blender --background --factory-startup --python Tools/Blender/t049_cat_attack_cue.py -- \
      --in Art/Exports/Cat/SM_Cat_005.glb --out Art/Exports/Cat/SM_Cat_006.glb
输出：`T049|...`，末行 `T049|done`。
"""
import sys
import os
import math
import bpy
from mathutils import Euler, Quaternion, Vector

REPO = "E:/Reborn"
FPS = 60
CLIP = "AttackCue"
FRAMES = 27  # 0..27 = 0.45 s

# 骨骼名来自 T046 的骨骼链报告（+X = 头，-X = 尾）
B_ROOT = "Bone"
B_SPINE = "Bone.001"
B_NECK = "Bone.002"
B_HEAD = "Bone.003"
B_HEAD_END = "Bone.004"
B_TAIL1 = "Bone.005"
B_TAIL2 = "Bone.006"
B_FL_L = "Bone.019"
B_FR_R = "Bone.015"
B_HL_L = "Bone.023"
B_HR_R = "Bone.011"

# (frame, {bone: (rx,ry,rz) 度}) + 根骨位移（米）
#
# 幅度教训（2026-11-10 第一版）：spine/neck 只有 6~10°、腿 14~22° 时，
# 帧判读结论是「几乎看不出在发力/前扑，更像站立」。这一段要的是**一眼能读出的提示**，
# 所以按 ~1.8 倍放大，并且加上**单侧前爪抬起**（猫科典型的蓄势信号）。
#
# 三段：0 基准 → 蓄势（压低 + 抬爪）→ 出爪（躯干前探、前腿前伸）。
KEY_POSES = [
    (0, {}, (0.0, 0.0, 0.0)),
    (8, {
        B_SPINE: (-14.0, 0.0, 0.0),
        B_NECK: (-15.0, 0.0, 0.0),
        B_HEAD: (8.0, 0.0, 0.0),
        B_TAIL1: (22.0, 0.0, 0.0),
        B_TAIL2: (16.0, 0.0, 0.0),
        B_FL_L: (28.0, 0.0, 0.0),
        B_FR_R: (28.0, 0.0, 0.0),
        B_HL_L: (-16.0, 0.0, 0.0),
        B_HR_R: (-16.0, 0.0, 0.0),
    }, (0.0, 0.0, -0.014)),
    (16, {
        B_SPINE: (-18.0, 0.0, 0.0),
        B_NECK: (-20.0, 0.0, 0.0),
        B_HEAD: (10.0, 0.0, 0.0),
        B_TAIL1: (30.0, 0.0, 0.0),
        B_TAIL2: (22.0, 0.0, 0.0),
        B_FL_L: (-44.0, 0.0, 0.0),   # 抬起的前爪（蓄势峰值）
        B_FR_R: (32.0, 0.0, 0.0),
        B_HL_L: (-20.0, 0.0, 0.0),
        B_HR_R: (-20.0, 0.0, 0.0),
    }, (0.0, 0.0, -0.018)),
    (FRAMES, {
        # 前腿从 38° 收到 26°：38° 时肩根折痕/穿模被放大（T047 已知缺陷），
        # 26° 仍能读出"前伸 + 出爪"，且不把缺陷推到明显可见。
        B_SPINE: (8.0, 0.0, 0.0),
        B_NECK: (16.0, 0.0, 0.0),
        B_HEAD: (-10.0, 0.0, 0.0),
        B_TAIL1: (12.0, 0.0, 0.0),
        B_TAIL2: (8.0, 0.0, 0.0),
        B_FL_L: (-26.0, 0.0, 0.0),
        B_FR_R: (-26.0, 0.0, 0.0),
        B_HL_L: (16.0, 0.0, 0.0),
        B_HR_R: (16.0, 0.0, 0.0),
    }, (0.0, 0.0, 0.004)),
]


def log(m):
    print("T049|%s" % m, flush=True)


def arg(name, default=None):
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if name in rest and rest.index(name) + 1 < len(rest):
            return rest[rest.index(name) + 1]
    return default


def main():
    src = arg("--in", REPO + "/Art/Exports/Cat/SM_Cat_005.glb")
    dst = arg("--out", REPO + "/Art/Exports/Cat/SM_Cat_006.glb")
    if os.path.exists(dst):
        log("ERROR|out_exists|%s" % dst)
        log("done")
        return 1

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0
    bpy.ops.import_scene.gltf(filepath=src)

    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    if arm.animation_data is None:
        arm.animation_data_create()
    log("import|bones=%d|actions=%s" % (
        len(arm.data.bones), [a.name for a in bpy.data.actions]))

    missing = [b for b in (B_ROOT, B_SPINE, B_NECK, B_HEAD, B_TAIL1, B_FL_L, B_HR_R)
               if arm.pose.bones.get(b) is None]
    if missing:
        log("ERROR|bones_missing|%s" % missing)
        log("done")
        return 1

    # 新建 action（先把所有骨骼清零，避免带进已有姿态）
    act = bpy.data.actions.new(CLIP)
    arm.animation_data.action = act
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))

    # 世界位移 → 骨骼本地位移的换算：骨架对象带 0.0366 缩放（骨骼空间比世界大 27 倍），
    # 只乘静置矩阵逆会漏掉这一层（第一版 0.045 m 只落 1.8 mm，实测见 t049c_drop_probe）。
    scale = arm.matrix_world.to_scale()
    root_pb = arm.pose.bones[B_ROOT]
    to_local = root_pb.bone.matrix_local.to_3x3().inverted()

    for frame, rots, root_loc in KEY_POSES:
        bpy.context.scene.frame_set(frame)
        for pb in arm.pose.bones:
            pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
            pb.location = (0.0, 0.0, 0.0)
        for bone_name, deg in rots.items():
            pb = arm.pose.bones.get(bone_name)
            if pb is None:
                log("WARN|bone_missing_in_pose|%s" % bone_name)
                continue
            e = Euler((math.radians(deg[0]), math.radians(deg[1]), math.radians(deg[2])), "XYZ")
            pb.rotation_quaternion = e.to_quaternion()
        world_drop = Vector((0.0, 0.0, root_loc[2]))
        root_pb.location = to_local @ Vector(
            (world_drop.x / scale.x, world_drop.y / scale.y, world_drop.z / scale.z))
        # 打关键帧：所有骨骼的旋转 + 根骨位置
        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
        root_pb.keyframe_insert("location", frame=frame)
        log("key|frame=%d|bones_rotated=%d|root_dz=%.3f" % (frame, len(rots), root_loc[2]))

    act.use_fake_user = True
    # 存进 NLA（glTF 导出器按 NLA strip 输出多段动画）
    track = arm.animation_data.nla_tracks.new()
    track.name = CLIP
    strip = track.strips.new(CLIP, 0, act)
    strip.name = CLIP
    arm.animation_data.action = None

    bpy.ops.export_scene.gltf(
        filepath=dst, export_format="GLB", use_selection=False, export_yup=True,
        export_materials="EXPORT", export_cameras=False, export_lights=False,
        export_extras=False, export_texcoords=True, export_normals=True,
        export_skins=True, export_animations=True, export_nla_strips=True,
        export_frame_range=False, export_apply=False,
    )
    log("export|%s|bytes=%d|length_s=%.3f" % (dst, os.path.getsize(dst), FRAMES / float(FPS)))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    log("done")
    return 0


sys.exit(main())
