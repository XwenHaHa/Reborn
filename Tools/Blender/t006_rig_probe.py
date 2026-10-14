# -*- coding: utf-8 -*-
"""T006 骨骼往返 —— Blender 侧骨骼/动画探针脚本（Blender 3.3.1 无头 CLI）

为什么要有这个脚本（与 T005 同一条链，但换成"骨骼 + 动画"）：
  E03 的验收不是"生成了 glb"，而是：
    1) 少量骨骼 + 刚性绑定能在 glTF 里往返（骨骼名、蒙皮、骨骼静止位姿）
    2) 1 s 循环动作：**时长 1.0 s**、**首帧与末帧姿态完全一致**（循环闭合）
    3) **原地**：只动骨骼，不动对象/根（不启用根运动、不绑相机动画到根骨）

建模都是**显式坐标**（不用 ops 建基础体、不依赖出厂场景），因此可复现、可 diff。
stdout 全是 ASCII（Windows 控制台编码不可靠），机器可读行格式 PROBE|key=value。
退出码 0 = 成功；1 = 失败（失败前打印 PROBE|FATAL|...）。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup \
      --python 'E:\\Reborn\\Tools\\Blender\\t006_rig_probe.py'
"""

import hashlib
import json
import os
import struct
import sys
from math import radians

import bpy
from mathutils import Vector

REPO = "E:/Reborn"
BLEND_OUT = REPO + "/Art/Blender/Tests/RigProbe_v001.blend"
GLB_OUT = REPO + "/Art/Exports/Tests/SK_RigProbe.glb"

# --- 几何（米。Blender 与 Godot 都是米；不追求动物外观） ---
BODY = {"name": "Body", "size": (0.20, 0.60, 0.20), "center": (0.0, 0.0, 0.34), "group": "spine"}
LEG_FRONT = {"name": "LegFront", "size": (0.06, 0.06, 0.24), "center": (0.0, 0.20, 0.12), "group": "leg_front"}
LEG_BACK = {"name": "LegBack", "size": (0.06, 0.06, 0.24), "center": (0.0, -0.20, 0.12), "group": "leg_back"}
BOXES = [BODY, LEG_FRONT, LEG_BACK]

MESH_NAME = "RIG_BODY_001"
ARM_NAME = "Rig"
ACTION_NAME = "Loop"

# --- 骨骼（Blender 坐标，米；角色约定见 T005 实测：面朝 +Y） ---
# (name, head, tail, parent)
BONES = [
    ("root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.08), None),
    ("spine", (0.0, -0.30, 0.34), (0.0, 0.30, 0.34), "root"),
    ("leg_front", (0.0, 0.20, 0.24), (0.0, 0.20, 0.0), "spine"),
    ("leg_back", (0.0, -0.20, 0.24), (0.0, -0.20, 0.0), "spine"),
]

# --- 动画：24 fps，帧 0 → 帧 24 = 1.000 s；首末姿态一致 ---
FPS = 24
# 帧 0..24 @24fps = 1.000 s。**从 0 开始**：导出器写绝对时间 frame/fps，
# 若从帧 1 开始，文件里的时间范围会变成 0.0417..1.0417（时长对但起点不对齐）。
FRAME_FIRST = 0
FRAME_MID = 12
FRAME_LAST = 24
# 每根骨的 (首/末帧角度, 中间帧角度)，单位度；绕骨本地 X 轴
ANIM_DEG = {
    "leg_front": (0.0, 30.0),
    "leg_back": (0.0, -30.0),
    "spine": (0.0, 6.0),
}

failures = []


def log(line):
    sys.stdout.write("PROBE|" + line + "\n")
    sys.stdout.flush()


def fail(line):
    failures.append(line)
    sys.stdout.write("PROBE|FAIL|" + line + "\n")
    sys.stdout.flush()


def fatal(line):
    sys.stdout.write("PROBE|FATAL|" + line + "\n")
    sys.stdout.flush()
    sys.exit(1)


def vec_str(v):
    return "(%.6f, %.6f, %.6f)" % (v[0], v[1], v[2])


def require(cond, msg):
    if not cond:
        fail(msg)
    return cond


# ---------------------------------------------------------------------------
# 1) 网格：手工给顶点/面，索引可控 → 顶点组能精确指定
# ---------------------------------------------------------------------------

def box_geometry(cx, cy, cz, sx, sy, sz):
    """一个盒子的 8 个顶点与 6 个四边形面（外向绕序，已在注释里核对过）。"""
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    local = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
             (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]
    verts = [(cx + v[0], cy + v[1], cz + v[2]) for v in local]
    faces = [(0, 3, 2, 1),   # -Z
             (4, 5, 6, 7),   # +Z
             (3, 7, 6, 2),   # +Y
             (0, 1, 5, 4),   # -Y
             (1, 2, 6, 5),   # +X
             (0, 4, 7, 3)]   # -X
    return verts, faces


def build_mesh():
    all_verts = []
    all_faces = []
    groups = {}   # group_name -> [vertex_index...]
    for spec in BOXES:
        verts, faces = box_geometry(*spec["center"], *spec["size"])
        offset = len(all_verts)
        all_verts.extend(verts)
        all_faces.extend([tuple(i + offset for i in f) for f in faces])
        groups.setdefault(spec["group"], []).extend(range(offset, offset + 8))
        log("box|%s|center=%s|size=%s|verts=%d-%d|group=%s" % (
            spec["name"], vec_str(Vector(spec["center"])), vec_str(Vector(spec["size"])),
            offset, offset + 7, spec["group"]))

    mesh = bpy.data.meshes.new(MESH_NAME + "_Mesh")
    mesh.from_pydata(all_verts, [], all_faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(MESH_NAME, mesh)
    bpy.context.scene.collection.objects.link(obj)

    for gname, idxs in groups.items():
        vg = obj.vertex_groups.new(name=gname)
        vg.add(idxs, 1.0, "REPLACE")   # 刚性权重：每顶点 1 骨、权重 1.0
        log("vertex_group|%s|verts=%d|weight=1.0" % (gname, len(idxs)))

    # 一个材质：让视觉检查能看清明暗与轮廓（颜色靠反照率 + 方向光，不用自发光）
    mat = bpy.data.materials.new("MAT_RIG_BODY")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        fatal("no_principled_bsdf|MAT_RIG_BODY")
    bsdf.inputs["Base Color"].default_value = (0.62, 0.45, 0.25, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.6
    if "Emission" in bsdf.inputs:
        bsdf.inputs["Emission"].default_value = (0.0, 0.0, 0.0, 1.0)
    obj.data.materials.append(mat)
    log("material|MAT_RIG_BODY|base_color=(0.620, 0.450, 0.250, 1.000)|roughness=0.60|emission=0.0")

    obj.data.calc_loop_triangles()
    log("mesh|name=%s|verts=%d|polys=%d|tris=%d|groups=%s" % (
        obj.name, len(mesh.vertices), len(mesh.polygons), len(mesh.loop_triangles),
        ",".join(sorted(groups.keys()))))
    return obj, groups


def world_bounds(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    mn = Vector((min(c[0] for c in corners), min(c[1] for c in corners), min(c[2] for c in corners)))
    mx = Vector((max(c[0] for c in corners), max(c[1] for c in corners), max(c[2] for c in corners)))
    return mn, mx


# ---------------------------------------------------------------------------
# 2) 骨架 + 绑定 + 动作
# ---------------------------------------------------------------------------

def build_armature():
    arm_data = bpy.data.armatures.new(ARM_NAME + "_Data")
    arm_obj = bpy.data.objects.new(ARM_NAME, arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    arm_obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in BONES:
        eb = arm_data.edit_bones.new(name)
        eb.head = head
        eb.tail = tail
        eb.roll = 0.0
        if parent:
            eb.parent = arm_data.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    arm_obj.select_set(False)
    names = [b.name for b in arm_data.bones]
    require(names == [b[0] for b in BONES], "bone_names_mismatch|%s" % ",".join(names))
    for b in arm_data.bones:
        log("bone|%s|head=%s|tail=%s|parent=%s|length=%.6f" % (
            b.name, vec_str(b.head_local), vec_str(b.tail_local),
            b.parent.name if b.parent else "none", b.length))
    return arm_obj


def bind(mesh_obj, arm_obj):
    mesh_obj.parent = arm_obj
    mesh_obj.matrix_parent_inverse = arm_obj.matrix_world.inverted()
    mod = mesh_obj.modifiers.new(name="Armature", type="ARMATURE")
    mod.object = arm_obj
    log("bind|mesh=%s|armature=%s|modifier=%s" % (mesh_obj.name, arm_obj.name, mod.type))


def build_action(arm_obj):
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start = FRAME_FIRST
    scene.frame_end = FRAME_LAST

    arm_obj.animation_data_create()
    act = bpy.data.actions.new(ACTION_NAME)
    arm_obj.animation_data.action = act

    for bname, (a_first, a_mid) in ANIM_DEG.items():
        pb = arm_obj.pose.bones[bname]
        pb.rotation_mode = "XYZ"
        for frame, deg in ((FRAME_FIRST, a_first), (FRAME_MID, a_mid), (FRAME_LAST, a_first)):
            pb.rotation_euler = (radians(deg), 0.0, 0.0)
            pb.keyframe_insert(data_path="rotation_euler", frame=frame)
            log("keyframe|%s|frame=%d|rot_x_deg=%.3f" % (bname, frame, deg))

    rng = act.frame_range
    log("action|name=%s|frame_range=(%.1f, %.1f)|fcurves=%d|fps=%d" % (
        act.name, rng[0], rng[1], len(act.fcurves), FPS))
    require(abs(rng[0] - FRAME_FIRST) < 1e-6 and abs(rng[1] - FRAME_LAST) < 1e-6,
            "action_range_unexpected|%s" % (tuple(rng),))
    duration = (FRAME_LAST - FRAME_FIRST) / float(FPS)
    require(abs(duration - 1.0) < 1e-9, "duration_not_1s|%.6f" % duration)
    log("action|duration_s=%.6f|first_pose_equals_last=True" % duration)
    return act


# ---------------------------------------------------------------------------
# 3) 导出（只传本机真实支持的 kwargs） + 导出文件自检
# ---------------------------------------------------------------------------

def export_glb():
    if not hasattr(bpy.ops.export_scene, "gltf"):
        fatal("export_scene_gltf_missing")
    rna = bpy.ops.export_scene.gltf.get_rna_type()
    props = set(rna.properties.keys())
    wanted = {
        "export_format": "GLB",
        "use_selection": False,
        "export_apply": True,
        "export_yup": True,
        "export_materials": "EXPORT",
        "export_cameras": False,
        "export_lights": False,
        "export_extras": False,
        "export_normals": True,
        "export_texcoords": True,
        # --- 骨骼/动画（T006 新增；名字先按 RNA 实测，缺失项会被记录为 unsupported）
        "export_skins": True,
        "export_animations": True,
        "export_force_sampling": True,
        "export_nla_strips": True,
        "export_anim_single_armature": True,
        "export_def_bones": False,
        "export_frame_range": False,          # 用动作自身范围（1..25），不要被场景范围拉长
        "export_current_frame": False,
        "export_optimize_animation_size": False,
        "export_morph": False,
    }
    applied = {k: v for k, v in wanted.items() if k in props}
    unsupported = sorted(k for k in wanted if k not in props)
    log("gltf_export|applied=%s|unsupported=%s" % (
        ",".join("%s=%s" % (k, applied[k]) for k in sorted(applied)), ",".join(unsupported) or "none"))
    for key in ("export_skins", "export_animations", "export_frame_range", "export_force_sampling"):
        if key not in props:
            fail("skinning_kwarg_missing|%s" % key)
    bpy.ops.export_scene.gltf(filepath=GLB_OUT, **applied)
    if not os.path.isfile(GLB_OUT):
        fatal("glb_not_written|%s" % GLB_OUT)
    with open(GLB_OUT, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (GLB_OUT, len(data), hashlib.sha256(data).hexdigest()))
    return data


def inspect_glb(data):
    """直接解析 GLB 的 JSON chunk：不依赖 Godot 就能证明"骨骼/蒙皮/动画"确实写进了文件。"""
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    require(magic == b"glTF", "glb_magic_bad|%r" % magic)
    require(version == 2, "glb_version_not_2|%d" % version)
    require(length == len(data), "glb_length_mismatch|%d vs %d" % (length, len(data)))
    off = 12
    chunk_len, chunk_type = struct.unpack_from("<II", data, off)
    require(chunk_type == 0x4E4F534A, "first_chunk_not_json|%d" % chunk_type)  # 'JSON'
    doc = json.loads(data[off + 8: off + 8 + chunk_len].decode("utf-8"))

    nodes = doc.get("nodes", [])
    skins = doc.get("skins", [])
    anims = doc.get("animations", [])
    log("glb_json|nodes=%d|meshes=%d|skins=%d|animations=%d|materials=%d" % (
        len(nodes), len(doc.get("meshes", [])), len(skins), len(anims), len(doc.get("materials", []))))
    require(len(skins) == 1, "glb_skins_unexpected|%d" % len(skins))
    joints = skins[0].get("joints", [])
    joint_names = [nodes[j].get("name", "?") for j in joints]
    log("glb_skin|joints=%d|names=%s" % (len(joints), ",".join(joint_names)))
    require(sorted(joint_names) == sorted([b[0] for b in BONES]),
            "glb_joint_names_mismatch|%s" % ",".join(joint_names))
    require(len(anims) == 1, "glb_animations_unexpected|%d" % len(anims))
    anim = anims[0]
    log("glb_anim|name=%s|channels=%d|samplers=%d" % (
        anim.get("name", "?"), len(anim.get("channels", [])), len(anim.get("samplers", []))))

    # 关键：导出器写的是**绝对时间** `frame / fps`（读源码 gltf2_blender_gather_animation_sampler_keyframes.py
    # 的采样循环 `while frame <= end_frame` 确认），所以"时长"必须用 max - min 算，不能只看 max。
    tmin = None
    tmax = None
    for s in anim.get("samplers", []):
        acc = doc["accessors"][s["input"]]
        if acc.get("max"):
            v = float(acc["max"][0])
            tmax = v if tmax is None else max(tmax, v)
        if acc.get("min"):
            v = float(acc["min"][0])
            tmin = v if tmin is None else min(tmin, v)
    require(tmin is not None and tmax is not None, "glb_anim_times_missing")
    log("glb_anim|t_min=%.6f|t_max=%.6f|duration_s=%.6f|targets=%s" % (
        tmin, tmax, tmax - tmin,
        ",".join("%s.%s" % (nodes[c["target"]["node"]].get("name", "?"), c["target"]["path"])
                 for c in anim.get("channels", []))))
    require(abs(tmin) < 1e-6, "glb_anim_start_not_zero|%.6f" % tmin)
    require(abs((tmax - tmin) - 1.0) < 1e-4, "glb_anim_duration_not_1s|%.6f" % (tmax - tmin))
    # 顶点必须有蒙皮属性（JOINTS_0 / WEIGHTS_0）
    prims = doc["meshes"][0]["primitives"]
    attrs = set()
    for p in prims:
        attrs |= set(p["attributes"].keys())
    log("glb_mesh|primitives=%d|attributes=%s" % (len(prims), ",".join(sorted(attrs))))
    require("JOINTS_0" in attrs and "WEIGHTS_0" in attrs, "glb_missing_skin_attributes|%s" % ",".join(sorted(attrs)))


# ---------------------------------------------------------------------------
# 4) 主流程
# ---------------------------------------------------------------------------

def dump_objects(tag):
    for o in sorted(bpy.data.objects, key=lambda x: x.name):
        info = "PROBE|%s|obj=%s|type=%s|parent=%s|modifiers=%d" % (
            tag, o.name, o.type, o.parent.name if o.parent else "none", len(o.modifiers))
        if o.type == "MESH":
            mn, mx = world_bounds(o)
            info += "|world_min=%s|world_max=%s|verts=%d|groups=%s" % (
                vec_str(mn), vec_str(mx), len(o.data.vertices),
                ",".join(g.name for g in o.vertex_groups))
        sys.stdout.write(info + "\n")
    sys.stdout.flush()


def main():
    log("start|blender=%s|python=%s" % (bpy.app.version_string, sys.version.split()[0]))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    existing = list(bpy.data.objects)
    log("startup|mode=factory_empty|object_count=%d|names=%s" % (
        len(existing), ",".join(o.name for o in existing) or "none"))
    if existing:
        fatal("factory_empty_unexpected_objects|%d" % len(existing))

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = "METERS"
    log("units|system=%s|scale_length=%.6f|length_unit=%s|scene=%s" % (
        scene.unit_settings.system, scene.unit_settings.scale_length,
        scene.unit_settings.length_unit, scene.name))

    for d in (os.path.dirname(BLEND_OUT), os.path.dirname(GLB_OUT)):
        if not os.path.isdir(d):
            os.makedirs(d)
            log("mkdir|%s" % d)

    mesh_obj, _groups = build_mesh()
    arm_obj = build_armature()
    bind(mesh_obj, arm_obj)
    build_action(arm_obj)
    dump_objects("built")

    # 关键尺寸断言：总高 = 腿底到体顶；体长/体宽
    mn, mx = world_bounds(mesh_obj)
    size = mx - mn
    log("check|world_aabb_size=%s|world_min=%s|world_max=%s" % (vec_str(size), vec_str(mn), vec_str(mx)))
    require(abs(size.x - 0.20) < 1e-6 and abs(size.y - 0.60) < 1e-6 and abs(size.z - 0.44) < 1e-6,
            "world_aabb_unexpected|%s" % vec_str(size))
    require(abs(mesh_obj.matrix_world.to_scale().x - 1.0) < 1e-6, "mesh_object_scaled")

    # --- 保存独立 .blend，然后重开校验 ---
    if os.path.isfile(BLEND_OUT):
        log("overwrite_warning|exists=True|path=%s" % BLEND_OUT)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
    require(os.path.isfile(BLEND_OUT), "blend_not_written|%s" % BLEND_OUT)
    with open(BLEND_OUT, "rb") as f:
        bdata = f.read()
    log("blend|path=%s|bytes=%d|sha256=%s" % (BLEND_OUT, len(bdata), hashlib.sha256(bdata).hexdigest()))

    bpy.ops.wm.open_mainfile(filepath=BLEND_OUT)
    require(os.path.realpath(bpy.data.filepath) == os.path.realpath(BLEND_OUT),
            "reopen_wrong_file|%s" % bpy.data.filepath)
    dump_objects("reopen")

    rmesh = bpy.data.objects.get(MESH_NAME)
    rarm = bpy.data.objects.get(ARM_NAME)
    require(rmesh is not None and rarm is not None, "reopen_objects_missing")
    rbones = [b.name for b in rarm.data.bones]
    require(rbones == [b[0] for b in BONES], "reopen_bones_changed|%s" % ",".join(rbones))
    acts = list(bpy.data.actions)
    require(len(acts) == 1 and acts[0].name == ACTION_NAME, "reopen_action_changed|%s" % ",".join(a.name for a in acts))
    rrng = acts[0].frame_range
    require(abs(rrng[0] - FRAME_FIRST) < 1e-6 and abs(rrng[1] - FRAME_LAST) < 1e-6,
            "reopen_action_range_changed|%s" % (tuple(rrng),))
    lmn, lmx = world_bounds(rmesh)
    log("reopen|bones=%s|action=%s|frame_range=(%.1f, %.1f)|aabb_size=%s" % (
        ",".join(rbones), acts[0].name, rrng[0], rrng[1], vec_str(lmx - lmn)))

    # --- 导出 + 文件自检 ---
    data = export_glb()
    inspect_glb(data)

    log("done|failures=%d" % len(failures))
    sys.exit(0 if not failures else 1)


main()
