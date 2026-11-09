"""T051 取证渲染：鼠的动画极值帧 + 尾/颈极端姿态，**每帧按求值后包围盒重新构图**。

为什么必须按求值后 bbox 构图（2026-11-09 两次踩坑）：
1. 只按静止网格 bbox 算机位 → 拍到"空场景"（蒙皮网格的渲染位置由骨骼决定，不等于静止顶点位置）；
2. 按原点算机位 → 拍到"远处一坨 + 地上碎块"（源资产节点带偏移，本资产 world min y≈-5.19、z≈-1.35）。

用法：
  blender --background --factory-startup --python Tools/Blender/t051c_render.py -- \
      --in Art/Exports/Mouse/SM_Mouse_002.glb --outdir Art/Probes
输出：`Art/Probes/t051_mouse_{anim_<clip>_f<N>,pose_tail,pose_neck}.png`
"""
import sys
import os
import math

import bpy
from mathutils import Euler, Vector

REPO = "E:/Reborn"
ANIM_FRAMES = [("Eat", 0), ("Walk", 25), ("Run", 10)]
POSES = {
    "tail": [("Tail1_03", (70.0, 0.0, 0.0)), ("Tail2_04", (60.0, 0.0, 0.0))],
    "neck": [("Neck_016", (0.0, 0.0, 45.0)), ("Head_017", (0.0, 0.0, 35.0))],
}


def log(m):
    print("T051C|%s" % m, flush=True)


def arg(name, default=None):
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if name in rest and rest.index(name) + 1 < len(rest):
            return rest[rest.index(name) + 1]
    return default


def evaluated_bbox(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for v in me.vertices:
        w = obj.matrix_world @ v.co
        for k in range(3):
            mn[k] = min(mn[k], w[k])
            mx[k] = max(mx[k], w[k])
    ev.to_mesh_clear()
    return mn, mx


def frame_camera(cam, mn, mx):
    center = Vector(((mn[0] + mx[0]) * 0.5, (mn[1] + mx[1]) * 0.5, (mn[2] + mx[2]) * 0.5))
    radius = max(mx[k] - mn[k] for k in range(3)) * 0.5
    dist = max(radius * 4.2, 0.25)
    cam.location = center + Vector((dist * 0.62, -dist * 0.80, dist * 0.42))
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    return center, radius


def main():
    src = arg("--in", REPO + "/Art/Exports/Mouse/SM_Mouse_002.glb")
    outdir = arg("--outdir", REPO + "/Art/Probes")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    bpy.ops.import_scene.gltf(filepath=src)
    obj = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: len(o.data.polygons))
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    if arm.animation_data is None:
        arm.animation_data_create()

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600

    world = bpy.data.worlds.new("T051CWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs[0].default_value = (0.22, 0.23, 0.25, 1.0)
        bg.inputs[1].default_value = 1.0

    cam_data = bpy.data.cameras.new("T051CCam")
    cam = bpy.data.objects.new("T051CCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam_data.lens = 50.0
    scene.camera = cam

    sun_data = bpy.data.lights.new("T051CSun", type="SUN")
    sun_data.energy = 4.0
    sun = bpy.data.objects.new("T051CSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(55.0), math.radians(12.0), math.radians(35.0))

    # 地面：先建好，每帧按求值 mn.z 抬到脚下
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.active_object
    mat = bpy.data.materials.new("T051CGround")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.18, 0.18, 0.19, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
    plane.data.materials.append(mat)

    os.makedirs(outdir, exist_ok=True)

    def shoot(tag):
        mn, mx = evaluated_bbox(obj)
        center, radius = frame_camera(cam, mn, mx)
        plane.scale = (radius * 12.0, radius * 12.0, 1.0)
        plane.location = (center.x, center.y, mn[2] - 0.002 * max(radius, 1e-3))
        area = bpy.data.lights.get("T051CFill")
        if area is None:
            light_data = bpy.data.lights.new("T051CFill", type="AREA")
            light_data.energy = 30.0
            light_data.size = max(radius * 4.0, 0.3)
            fill = bpy.data.objects.new("T051CFill", light_data)
            bpy.context.collection.objects.link(fill)
            fill.location = center + Vector((-radius * 3.0, -radius * 2.5, radius * 3.0))
            fill.rotation_euler = (math.radians(55.0), 0.0, math.radians(-45.0))
        path = os.path.join(outdir, "t051_mouse_%s.png" % tag)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        log("render|%s|center=(%.3f,%.3f,%.3f)|r=%.3f|%s" % (
            tag, center.x, center.y, center.z, radius, path))

    def reset_pose():
        for pb in arm.pose.bones:
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = Euler((0.0, 0.0, 0.0), "XYZ")
        bpy.context.view_layer.update()

    for clip, frame in ANIM_FRAMES:
        act = None
        for a in bpy.data.actions:
            if a.name.startswith(clip):
                act = a
                break
        if act is None:
            log("ERROR|action_missing|%s" % clip)
            continue
        arm.animation_data.action = act
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        shoot("anim_%s_f%d" % (clip, frame))

    arm.animation_data.action = None
    for tag, rots in POSES.items():
        reset_pose()
        for bone, deg in rots:
            pb = arm.pose.bones.get(bone)
            if pb is None:
                log("ERROR|bone_missing|%s" % bone)
                continue
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = Euler((math.radians(deg[0]), math.radians(deg[1]),
                                       math.radians(deg[2])), "XYZ")
        bpy.context.view_layer.update()
        shoot("pose_%s" % tag)
    reset_pose()

    log("done")
    return 0


sys.exit(main())
