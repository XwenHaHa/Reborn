"""T051：鼠骨骼与权重检查 —— 权重统计 + 动画极值帧形变 + 极端姿态矩阵 + 渲染。

验收词（开发计划 :219）：尾、四肢与躯干变形可用，骨骼命名稳定。

与 T047（猫）的区别：鼠的骨骼是**语义命名**（`Back_01` / `FrontLeg1_l_07` / `Tail1_03` …），
所以不需要像猫那样靠链末端位移反推轴；这里直接对每条腿根**三个轴各转 70°**，把
"哪个轴有问题"一次报全，避免盲猜。

用法：
  blender --background --factory-startup --python Tools/Blender/t051_mouse_rig_check.py -- \
      --in Art/Exports/Mouse/SM_Mouse_002.glb --outdir Art/Probes
输出：`T051|...`，末行 `T051|done`。
"""
import sys
import os
import math
import json

import bpy
from mathutils import Euler, Vector

REPO = "E:/Reborn"
LEG_ROOTS = {
    "front_l": "FrontLeg1_l_07",
    "front_r": "FrontLeg1_r_011",
    "back_l": "BackLeg1_l_09",
    "back_r": "BackLeg1_r_013",
}
LEG_TIPS = {
    "front_l": "FrontLeg2_l_08",
    "front_r": "FrontLeg2_r_012",
    "back_l": "BackLeg2_l_010",
    "back_r": "BackLeg2_r_014",
}
TAIL = ["Tail1_03", "Tail2_04"]
NECK = ["Neck_016", "Head_017"]


def log(m):
    print("T051|%s" % m, flush=True)


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
    return [((me.vertices[t.vertices[1]].co - me.vertices[t.vertices[0]].co).cross(
        me.vertices[t.vertices[2]].co - me.vertices[t.vertices[0]].co)).length * 0.5
        for t in me.loop_triangles]


def posed_areas(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    out = [((me.vertices[t.vertices[1]].co - me.vertices[t.vertices[0]].co).cross(
        me.vertices[t.vertices[2]].co - me.vertices[t.vertices[0]].co)).length * 0.5
        for t in me.loop_triangles]
    ev.to_mesh_clear()
    return out


def stats(rest, areas):
    ratios = sorted(a / r for r, a in zip(rest, areas) if r > 1e-12)
    n = len(ratios)
    return {
        "min": ratios[0], "p1": ratios[max(0, int(n * 0.01))], "max": ratios[-1],
        "collapse": sum(1 for x in ratios if x < 0.5),
        "tear": sum(1 for x in ratios if x > 2.0),
        "n": n,
    }


def weight_stats(obj):
    me = obj.data
    hist, zero, dev = {}, 0, 0
    counts = {}
    for v in me.vertices:
        gs = [g for g in v.groups if g.weight > 1e-6]
        hist[len(gs)] = hist.get(len(gs), 0) + 1
        if not gs:
            zero += 1
        elif abs(sum(g.weight for g in gs) - 1.0) > 1e-3:
            dev += 1
        for g in gs:
            name = obj.vertex_groups[g.group].name
            counts[name] = counts.get(name, 0) + 1
    return hist, zero, dev, counts


def reset(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler((0.0, 0.0, 0.0), "XYZ")
    bpy.context.view_layer.update()


def setup_render(target_size, center):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600

    world = bpy.data.worlds.new("T051World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs[0].default_value = (0.22, 0.23, 0.25, 1.0)
        bg.inputs[1].default_value = 1.0

    d = max(target_size) * 2.4
    cam_data = bpy.data.cameras.new("T051Cam")
    cam = bpy.data.objects.new("T051Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam_data.lens = 50.0
    # 主体在世界坐标里不在原点（源资产节点带偏移，实测 bbox min=(-0.03,-5.19,-1.35)）→
    # 机位必须按 bbox 中心算，否则会拍到"远处一坨 + 地上的碎块"（2026-11-09 踩过）
    target = Vector((center[0], center[1], center[2]))
    cam_loc = target + Vector((d * 0.62, -d * 0.78, target_size[2] * 0.55))
    cam.location = cam_loc
    cam.rotation_euler = (target - cam_loc).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.camera = cam

    sun_data = bpy.data.lights.new("T051Sun", type="SUN")
    sun_data.energy = 3.5
    sun = bpy.data.objects.new("T051Sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(55.0), math.radians(12.0), math.radians(35.0))

    area = bpy.data.lights.new("T051Fill", type="AREA")
    area.energy = 40.0
    area.size = max(target_size) * 2.0
    fill = bpy.data.objects.new("T051Fill", area)
    bpy.context.collection.objects.link(fill)
    fill.location = (center[0] - d * 0.6, center[1] - d * 0.5, center[2] + target_size[2] * 1.2)
    fill.rotation_euler = (math.radians(60.0), 0.0, math.radians(-50.0))

    bpy.ops.mesh.primitive_plane_add(size=max(target_size) * 8.0,
                                     location=(center[0], center[1], center[2] - target_size[2] * 0.5))
    plane = bpy.context.active_object
    mat = bpy.data.materials.new("T051Ground")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.18, 0.18, 0.19, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
    plane.data.materials.append(mat)
    return scene


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
    me = obj.data
    me.calc_loop_triangles()
    log("asset|%s|tris=%d|verts=%d|bones=%d|groups=%d|actions=%s" % (
        src, len(me.loop_triangles), len(me.vertices), len(arm.data.bones),
        len(obj.vertex_groups), [a.name for a in bpy.data.actions]))

    hist, zero, dev, counts = weight_stats(obj)
    log("weights|influence_hist=%s|zero_weight_verts=%d|sum_not_1_verts=%d|max_influences=%d" % (
        json.dumps({str(k): v for k, v in sorted(hist.items())}), zero, dev,
        max(hist.keys()) if hist else 0))
    bone_names = {b.name for b in arm.data.bones}
    dead = sorted(n for n in bone_names if counts.get(n, 0) == 0)
    log("weights|bones_without_influence=%d|names=%s" % (len(dead), json.dumps(dead)))

    # 世界包围盒（用于机位）
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for v in me.vertices:
        w = obj.matrix_world @ v.co
        for k in range(3):
            mn[k] = min(mn[k], w[k])
            mx[k] = max(mx[k], w[k])
    size = [mx[k] - mn[k] for k in range(3)]
    log("bbox|size=(%.3f,%.3f,%.3f)|min=(%.3f,%.3f,%.3f)" % (size[0], size[1], size[2], mn[0], mn[1], mn[2]))

    rest = face_areas(obj)
    center = [(mn[k] + mx[k]) * 0.5 for k in range(3)]
    scene = setup_render(size, center)
    os.makedirs(outdir, exist_ok=True)

    # ---- 动画：摆幅 + 极值帧形变 -------------------------------------------------
    for act in sorted(bpy.data.actions, key=lambda a: a.name):
        arm.animation_data.action = act
        f0, f1 = act.frame_range
        max_deg = {k: 0.0 for k in LEG_ROOTS}
        tail_deg = {k: 0.0 for k in TAIL}
        worst = {"frame": -1, "collapse": -1, "tear": -1, "min": 9.9}
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
            for bone in TAIL:
                pb = arm.pose.bones.get(bone)
                if pb is None:
                    continue
                e = pb.rotation_quaternion.to_euler("XYZ")
                tail_deg[bone] = max(tail_deg[bone], max(abs(math.degrees(e.x)),
                                                         abs(math.degrees(e.y)),
                                                         abs(math.degrees(e.z))))
            st = stats(rest, posed_areas(obj))
            if st["collapse"] + st["tear"] > worst["collapse"] + worst["tear"]:
                worst = {"frame": f, "collapse": st["collapse"], "tear": st["tear"], "min": st["min"]}
            f += 1
        log("anim|%s|frames=%d..%d|leg_deg=%s|tail_deg=%s" % (
            act.name, int(f0), last,
            json.dumps({k: round(v, 1) for k, v in max_deg.items()}),
            json.dumps({k: round(v, 1) for k, v in tail_deg.items()})))
        log("deform|%s|worst_frame=%d|collapse=%d|tear=%d|min_area_ratio=%.4f" % (
            act.name, worst["frame"], worst["collapse"], worst["tear"], worst["min"]))

    # ---- 极端姿态矩阵（每条腿根三轴各 70°；尾/颈） -------------------------------
    reset(arm)
    for tag, bone in LEG_ROOTS.items():
        for axis in ("X", "Y", "Z"):
            reset(arm)
            pb = arm.pose.bones[bone]
            eul = [0.0, 0.0, 0.0]
            eul["XYZ".index(axis)] = math.radians(70.0)
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = Euler(eul, "XYZ")
            bpy.context.view_layer.update()
            st = stats(rest, posed_areas(obj))
            log("pose|%s|axis=%s|deg=70|collapse=%d|tear=%d|min=%.4f|max=%.4f" % (
                tag, axis, st["collapse"], st["tear"], st["min"], st["max"]))
    reset(arm)
    for bone, deg in ((TAIL[0], 70.0), (TAIL[1], 60.0)):
        pb = arm.pose.bones[bone]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler((math.radians(deg), 0.0, 0.0), "XYZ")
    bpy.context.view_layer.update()
    st = stats(rest, posed_areas(obj))
    log("pose|tail|collapse=%d|tear=%d|min=%.4f|max=%.4f" % (st["collapse"], st["tear"], st["min"], st["max"]))
    scene.render.filepath = os.path.join(outdir, "t051_mouse_pose_tail.png")
    bpy.ops.render.render(write_still=True)

    reset(arm)
    for bone, deg in ((NECK[0], 45.0), (NECK[1], 35.0)):
        pb = arm.pose.bones[bone]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler((0.0, 0.0, math.radians(deg)), "XYZ")
    bpy.context.view_layer.update()
    st = stats(rest, posed_areas(obj))
    log("pose|neck|collapse=%d|tear=%d|min=%.4f|max=%.4f" % (st["collapse"], st["tear"], st["min"], st["max"]))
    scene.render.filepath = os.path.join(outdir, "t051_mouse_pose_neck.png")
    bpy.ops.render.render(write_still=True)
    reset(arm)

    log("done")
    return 0


sys.exit(main())
