"""T047：猫骨骼与权重检查 —— 权重统计 + 极端姿态形变量测 + 姿态渲染。

验收词（开发计划 :215）：极端姿态测试肩、髋、尾；无明显塌陷和拉丝；保存权重前版本。

做法：
1. 导入 `SM_Cat_005.glb`（现役资产，33 骨、权重来自源 FBX）。
2. **权重统计**：每顶点影响数分布、权重和偏离 1 的顶点数、零权重顶点、每根骨骼的影响顶点数
   （0 影响 = 死骨；>4 影响会被 glTF 截断）。
3. **极端姿态**：肩（前腿根）外展 80°、髋（后腿根）外展 80°、尾根 70° + 尾中 60°、颈/头 60° 转；
   对每个姿态用 depsgraph 求值后按面比较"姿态面积 / 静止面积"：
   `ratio < 0.5` 记塌陷面，`ratio > 2.0` 记拉丝/过度拉伸面。
4. 每个姿态用 Cycles CPU 渲一张 3/4 机位图到 `Art/Probes/t047_cat_pose_<tag>.png`（判读用）。

用法：
  blender --background --factory-startup --python Tools/Blender/t047_cat_rig_check.py -- \
      --in Art/Exports/Cat/SM_Cat_005.glb --outdir Art/Probes

输出：`T047|key=value`，最后 `T047|done`。
"""
import sys
import os
import math
import json

import bpy
from mathutils import Euler

REPO = "E:/Reborn"

# 骨骼命名在导入后是 Bone.00x（源 FBX 无意义命名）；以下映射由 T046 的骨骼链端点推出：
#   +X 端是头（眼球材质面落在 x∈[6.08,6.82]），-X 端是尾；
#   四条腿链末端都在 z≈0.15（地面）：Bone.015/Bone.019（x≈+3.2，前）、Bone.011/Bone.023（x≈-2.6，后）。
POSES = {
    "shoulder": [
        ("Bone.015", (0.0, 0.0, math.radians(80.0))),
        ("Bone.019", (0.0, 0.0, math.radians(-80.0))),
    ],
    "hip": [
        ("Bone.011", (0.0, 0.0, math.radians(80.0))),
        ("Bone.023", (0.0, 0.0, math.radians(-80.0))),
    ],
    "tail": [
        ("Bone.005", (math.radians(70.0), 0.0, 0.0)),
        ("Bone.007", (math.radians(60.0), 0.0, 0.0)),
    ],
    "neck": [
        ("Bone.002", (0.0, 0.0, math.radians(45.0))),
        ("Bone.003", (0.0, math.radians(35.0), 0.0)),
    ],
}


def log(msg):
    print("T047|%s" % msg, flush=True)


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
    areas = []
    for tri in me.loop_triangles:
        a, b, c = (me.vertices[i].co for i in tri.vertices)
        areas.append(((b - a).cross(c - a)).length * 0.5)
    return areas


def posed_face_areas(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    areas = []
    for tri in me.loop_triangles:
        a, b, c = (me.vertices[i].co for i in tri.vertices)
        areas.append(((b - a).cross(c - a)).length * 0.5)
    ev.to_mesh_clear()
    return areas


def setup_render(outdir):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False

    world = bpy.data.worlds.new("T047World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs[0].default_value = (0.22, 0.23, 0.25, 1.0)
        bg.inputs[1].default_value = 1.0

    cam_data = bpy.data.cameras.new("T047Cam")
    cam = bpy.data.objects.new("T047Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam_data.lens = 50.0
    cam.location = (1.05, -1.15, 0.55)
    cam.rotation_euler = (math.radians(74.0), 0.0, math.radians(42.0))
    scene.camera = cam

    sun_data = bpy.data.lights.new("T047Sun", type="SUN")
    sun_data.energy = 3.5
    sun = bpy.data.objects.new("T047Sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(55.0), math.radians(12.0), math.radians(35.0))

    area_data = bpy.data.lights.new("T047Fill", type="AREA")
    area_data.energy = 40.0
    area_data.size = 2.0
    fill = bpy.data.objects.new("T047Fill", area_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (-1.2, -1.0, 1.2)
    fill.rotation_euler = (math.radians(60.0), 0.0, math.radians(-50.0))

    # 地面，便于判读接地与投影
    bpy.ops.mesh.primitive_plane_add(size=6.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.active_object
    mat = bpy.data.materials.new("T047Ground")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.18, 0.18, 0.19, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
    plane.data.materials.append(mat)
    return scene


def main():
    src = arg("--in", REPO + "/Art/Exports/Cat/SM_Cat_005.glb")
    outdir = arg("--outdir", REPO + "/Art/Probes")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if not meshes or not arms:
        log("ERROR|missing_mesh_or_armature")
        log("done")
        return 1
    obj = max(meshes, key=lambda o: len(o.data.polygons))
    arm = arms[0]
    me = obj.data
    me.calc_loop_triangles()
    log("asset|%s|tris=%d|verts=%d|bones=%d|groups=%d" % (
        src, len(me.loop_triangles), len(me.vertices), len(arm.data.bones), len(obj.vertex_groups)))

    # ---- 权重统计 -----------------------------------------------------------
    infl_hist = {}
    zero_weight = 0
    sum_dev = 0
    bone_counts = {}
    for v in me.vertices:
        gs = [g for g in v.groups if g.weight > 1e-6]
        n = len(gs)
        infl_hist[n] = infl_hist.get(n, 0) + 1
        s = sum(g.weight for g in gs)
        if n == 0:
            zero_weight += 1
        elif abs(s - 1.0) > 1e-3:
            sum_dev += 1
        for g in gs:
            name = obj.vertex_groups[g.group].name
            bone_counts[name] = bone_counts.get(name, 0) + 1
    log("weights|influence_hist=%s|zero_weight_verts=%d|sum_not_1_verts=%d|max_influences=%d" % (
        json.dumps({str(k): v for k, v in sorted(infl_hist.items())}),
        zero_weight, sum_dev, max(infl_hist.keys()) if infl_hist else 0))
    bone_names = {b.name for b in arm.data.bones}
    dead = sorted(n for n in bone_names if bone_counts.get(n, 0) == 0)
    log("weights|bones_without_influence=%d|names=%s" % (len(dead), json.dumps(dead)))
    top = sorted(bone_counts.items(), key=lambda kv: -kv[1])[:6]
    log("weights|top_bones=%s" % json.dumps([[n, c] for n, c in top]))

    # ---- 极端姿态 -----------------------------------------------------------
    rest = face_areas(obj)
    scene = setup_render(outdir)
    os.makedirs(outdir, exist_ok=True)

    bpy.context.view_layer.objects.active = arm
    for tag, rots in POSES.items():
        for pb in arm.pose.bones:
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = Euler((0.0, 0.0, 0.0), "XYZ")
        for bone_name, euler in rots:
            pb = arm.pose.bones.get(bone_name)
            if pb is None:
                log("ERROR|bone_missing|%s" % bone_name)
                continue
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = Euler(euler, "XYZ")
        bpy.context.view_layer.update()

        areas = posed_face_areas(obj)
        ratios = []
        for r, a in zip(rest, areas):
            if r <= 1e-12:
                continue
            ratios.append(a / r)
        ratios.sort()
        n = len(ratios)
        collapse = sum(1 for x in ratios if x < 0.5)
        tear = sum(1 for x in ratios if x > 2.0)
        log("pose|%s|faces=%d|area_ratio_min=%.4f|p1=%.4f|p50=%.4f|p99=%.4f|max=%.4f|"
            "collapse_faces(%s0.5)=%d|tear_faces(>2.0)=%d" % (
                tag, n, ratios[0], ratios[max(0, int(n * 0.01))], ratios[int(n * 0.5)],
                ratios[min(n - 1, int(n * 0.99))], ratios[-1], "&lt;" if False else "<",
                collapse, tear))

        scene.render.filepath = os.path.join(outdir, "t047_cat_pose_%s.png" % tag)
        bpy.ops.render.render(write_still=True)
        log("render|%s|%s" % (tag, scene.render.filepath))

    # 复位
    for pb in arm.pose.bones:
        pb.rotation_euler = Euler((0.0, 0.0, 0.0), "XYZ")
    bpy.context.view_layer.update()
    log("done")
    return 0


sys.exit(main())
