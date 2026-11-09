"""T047 辅助：把**动画本身最差形变的帧**渲出来，供视觉判读（不是人造姿态）。

用法：
  blender --background --factory-startup --python Tools/Blender/t047d_render_frames.py -- --in Art/Exports/Cat/SM_Cat_005.glb --outdir Art/Probes
输出：`Art/Probes/t047_cat_anim_<clip>_f<N>.png`，日志 `T047D|...`。
"""
import sys
import os
import math

import bpy

REPO = "E:/Reborn"
FRAMES = [("Run", 0), ("Walk", 2)]


def log(m):
    print("T047D|%s" % m, flush=True)


def arg(name, default=None):
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if name in rest and rest.index(name) + 1 < len(rest):
            return rest[rest.index(name) + 1]
    return default


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600

    world = bpy.data.worlds.new("T047DWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs[0].default_value = (0.22, 0.23, 0.25, 1.0)
        bg.inputs[1].default_value = 1.0

    cam_data = bpy.data.cameras.new("T047DCam")
    cam = bpy.data.objects.new("T047DCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam_data.lens = 50.0
    # 侧前方低机位：肩/髋折痕最容易看出来的角度
    cam.location = (0.95, -1.05, 0.42)
    cam.rotation_euler = (math.radians(78.0), 0.0, math.radians(42.0))
    scene.camera = cam

    sun_data = bpy.data.lights.new("T047DSun", type="SUN")
    sun_data.energy = 3.5
    sun = bpy.data.objects.new("T047DSun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(55.0), math.radians(12.0), math.radians(35.0))

    area_data = bpy.data.lights.new("T047DFill", type="AREA")
    area_data.energy = 40.0
    area_data.size = 2.0
    fill = bpy.data.objects.new("T047DFill", area_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (-1.2, -1.2, 1.2)
    fill.rotation_euler = (math.radians(60.0), 0.0, math.radians(-50.0))

    bpy.ops.mesh.primitive_plane_add(size=6.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.active_object
    mat = bpy.data.materials.new("T047DGround")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.18, 0.18, 0.19, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
    plane.data.materials.append(mat)


def main():
    src = arg("--in", REPO + "/Art/Exports/Cat/SM_Cat_005.glb")
    outdir = arg("--outdir", REPO + "/Art/Probes")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    bpy.ops.import_scene.gltf(filepath=src)
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    if arm.animation_data is None:
        arm.animation_data_create()
    setup_render()
    os.makedirs(outdir, exist_ok=True)

    for clip, frame in FRAMES:
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
        path = os.path.join(outdir, "t047_cat_anim_%s_f%d.png" % (clip, frame))
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        log("render|%s|frame=%d|%s" % (clip, frame, path))

    log("done")
    return 0


sys.exit(main())
