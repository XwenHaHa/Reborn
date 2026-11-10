"""T049 取证渲染：猫的 `AttackCue` 攻击提示片段逐帧判读。

只看一件事：**提示动作是否"能看出在蓄势→出爪"**，以及**没有塌陷/拉丝/穿模**。
机位沿用 T051 的教训：**每帧按求值后包围盒重新构图**（静止 bbox / 原点都会拍空景）。

用法：
  blender --background --factory-startup --python Tools/Blender/t049_render_cue.py -- \
      --in Art/Exports/Cat/SM_Cat_006.glb --outdir Art/Probes
输出：`Art/Probes/t049_cue_f<N>.png`
"""
import sys
import os
import math

import bpy
from mathutils import Vector

REPO = "E:/Reborn"
FRAMES = [0, 4, 7, 11, 14]      # AttackCue 0..14 @30fps = 0.450 s

FRAMES = [0, 4, 8, 12, 14]      # glTF 导入后按 30 fps 铺开：0.450 s ≈ 13.5 帧，故 14 帧≈末帧
def log(m):
    print("T049|%s" % m, flush=True)


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
    dist = max(radius * 4.0, 0.35)
    # 侧前方 3/4 视角：能同时看到前爪伸展与躯干压缩
    cam.location = center + Vector((dist * 0.70, -dist * 0.78, dist * 0.30))
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    return center, radius


def main():
    src = arg("--in", REPO + "/Art/Exports/Cat/SM_Cat_006.glb")
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

    world = bpy.data.worlds.new("T049World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs[0].default_value = (0.22, 0.23, 0.25, 1.0)
        bg.inputs[1].default_value = 1.0

    cam_data = bpy.data.cameras.new("T049Cam")
    cam = bpy.data.objects.new("T049Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam_data.lens = 50.0
    scene.camera = cam

    sun_data = bpy.data.lights.new("T049Sun", type="SUN")
    sun_data.energy = 4.0
    sun = bpy.data.objects.new("T049Sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(55.0), math.radians(12.0), math.radians(35.0))

    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.active_object
    mat = bpy.data.materials.new("T049Ground")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.18, 0.18, 0.19, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
    plane.data.materials.append(mat)

    os.makedirs(outdir, exist_ok=True)

    act = None
    for a in bpy.data.actions:
        if a.name.startswith("AttackCue"):
            act = a
            break
    if act is None:
        log("ERROR|action_missing|AttackCue")
        return 2
    arm.animation_data.action = act
    log("action|%s|frames=%d..%d" % (act.name, int(act.frame_range[0]), int(act.frame_range[1])))

    for frame in FRAMES:
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        mn, mx = evaluated_bbox(obj)
        center, radius = frame_camera(cam, mn, mx)
        plane.scale = (radius * 12.0, radius * 12.0, 1.0)
        plane.location = (center.x, center.y, mn[2] - 0.002 * max(radius, 1e-3))
        fill = bpy.data.objects.get("T049Fill")
        if fill is None:
            light_data = bpy.data.lights.new("T049Fill", type="AREA")
            light_data.energy = 45.0
            light_data.size = max(radius * 4.0, 0.4)
            fill = bpy.data.objects.new("T049Fill", light_data)
            bpy.context.collection.objects.link(fill)
            fill.location = center + Vector((-radius * 3.0, -radius * 2.5, radius * 3.0))
            fill.rotation_euler = (math.radians(55.0), 0.0, math.radians(-45.0))
        path = os.path.join(outdir, "t049_cue_f%d.png" % frame)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        log("render|f%d|center=(%.3f,%.3f,%.3f)|r=%.3f|bbox=[%.3f,%.3f,%.3f]-[%.3f,%.3f,%.3f]|%s" % (
            frame, center.x, center.y, center.z, radius,
            mn[0], mn[1], mn[2], mx[0], mx[1], mx[2], path))

    log("done")
    return 0


sys.exit(main())
