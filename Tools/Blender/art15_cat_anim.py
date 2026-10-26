# -*- coding: utf-8 -*-
"""ART02-ext `CAT_BODY_001` 的动作：用现有 33 根骨程序化生成 Idle / Walk / Run，补上"猫没有动画"。

## 背景
ART02 把猫换成 `cat_fripouille`（CC BY 4.0）的蒙皮模型：**33 骨、但有骨无动画**。
`animal_body.gd` 的动画接线（按名字找 Idle/Walk/Run、按速度调速）早就在，
鼠有 4 段 clip 所以会走，猫没有 → 一直保持一个姿势在地面平移，看起来极硬。

## 做法
复用 `art04_cat_from_ref.py` 的**同一套归一化**（材质并 2 槽 → 按眼睛质心转成面朝 +Y
→ 按体长 0.58 m 统一缩放 → X 居中、脚底 z=0 → 合并网格），保证模型本体与 ART02 完全一致；
然后只加"骨骼动作"，不动网格：
- 骨骼是自动名 `Bone.xxx`，按**世界坐标**分类：腿 = 链条末端接近地面且下半身的链；
  按 (X 侧, Y 前后) 分到前左/前右/后左/后右；另外识别脊椎链、颈/头、尾链；
- 三段动作全程序化（正弦），绕**骨架空间轴**旋转（不依赖骨骼局部朝向）：
  - `Idle` 48 帧：呼吸（脊椎俯仰 ±1.5°）、头微动、尾摆 ±6°、身体上下 4 mm；
  - `Walk` 24 帧：对角步态，大腿 ±18°，膝部反向补 10°，身体每循环两次起伏，尾反向摆；
  - `Run`  16 帧：幅度 ±30°，脊椎前倾 6°，身体起伏更大。
- 三段各自塞进一条 NLA 轨道（轨道名 = 动作名），Blender 3.3 只有 `export_nla_strips=True`
  才会把每条轨道导成一个 glTF 动画（鼠那边已踩过这个坑）。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art15_cat_anim.py' -- --stage probe
  & ... --stage all
"""

import hashlib
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

REPO = "E:/Reborn"
REF_FBX = REPO + "/references/_downloads/cat_fripouille/src/source/frip_F_export.fbx"
TEX_DIR = REPO + "/references/_downloads/cat_fripouille/src/textures"
GLB_OUT = REPO + "/Art/Exports/Cat/SM_Cat_002.glb"

TARGET_LEN = 0.58
MAX_HEIGHT = 0.48
TRI_BUDGET = 40000
FPS = 24
failures = []


def log(line):
    sys.stdout.write("PROBE|" + line + "\n")
    sys.stdout.flush()


def require(cond, msg):
    if not cond:
        failures.append(msg)
        sys.stdout.write("PROBE|FAIL|" + msg + "\n")
        sys.stdout.flush()
    return cond


def vec(v):
    return "(%.4f, %.4f, %.4f)" % (v[0], v[1], v[2])


def mesh_objects():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def root_objects():
    return [o for o in bpy.data.objects if o.parent is None]


def world_bbox():
    mn = Vector((1e18, 1e18, 1e18))
    mx = Vector((-1e18, -1e18, -1e18))
    for o in mesh_objects():
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return mn, mx


def centroid_of_material(mat_names):
    acc = Vector((0.0, 0.0, 0.0))
    n = 0
    for o in mesh_objects():
        slots = [m.name for m in o.data.materials if m]
        if not any(s in mat_names for s in slots):
            continue
        for v in o.data.vertices:
            acc += o.matrix_world @ v.co
            n += 1
    return (acc / n) if n else None


def build_materials():
    def tex(path, non_color=False):
        img = bpy.data.images.load(path, check_existing=True)
        if non_color:
            img.colorspace_settings.name = "Non-Color"
        return img

    fur = bpy.data.materials.new("MAT_Cat_Fur")
    fur.use_nodes = True
    nt = fur.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.72
    if "Specular" in bsdf.inputs:
        bsdf.inputs["Specular"].default_value = 0.25
    base_path = os.path.join(TEX_DIR, "SHD_frip_Base_Color.tga.png")
    nrm_path = os.path.join(TEX_DIR, "SHD_frip_Normal_DirectX.tga.png")
    if os.path.isfile(base_path):
        n_base = nt.nodes.new("ShaderNodeTexImage")
        n_base.image = tex(base_path)
        n_base.location = (-600, 200)
        nt.links.new(n_base.outputs["Color"], bsdf.inputs["Base Color"])
        nt.nodes.active = n_base
    else:
        bsdf.inputs["Base Color"].default_value = (0.24, 0.19, 0.15, 1.0)
    if os.path.isfile(nrm_path):
        n_nrm = nt.nodes.new("ShaderNodeTexImage")
        n_nrm.image = tex(nrm_path, non_color=True)
        n_nrm.location = (-600, -200)
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.location = (-260, -200)
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        sep.location = (-480, -380)
        nt.links.new(n_nrm.outputs["Color"], sep.inputs["Color"])
        inv = nt.nodes.new("ShaderNodeMath")
        inv.operation = "SUBTRACT"
        inv.inputs[0].default_value = 1.0
        inv.location = (-380, -520)
        nt.links.new(sep.outputs["Green"], inv.inputs[1])
        comb = nt.nodes.new("ShaderNodeCombineColor")
        comb.location = (-330, -380)
        nt.links.new(sep.outputs["Red"], comb.inputs["Red"])
        nt.links.new(inv.outputs["Value"], comb.inputs["Green"])
        nt.links.new(sep.outputs["Blue"], comb.inputs["Blue"])
        nt.links.new(comb.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    eye = bpy.data.materials.new("MAT_Cat_Detail")
    eye.use_nodes = True
    ebsdf = eye.node_tree.nodes["Principled BSDF"]
    ebsdf.inputs["Base Color"].default_value = (0.03, 0.035, 0.03, 1.0)
    ebsdf.inputs["Roughness"].default_value = 0.28
    return fur, eye


def remap_materials(fur, eye):
    for o in mesh_objects():
        old = list(o.data.materials)
        if not old:
            o.data.materials.append(fur)
            o.data.materials.append(eye)
            continue
        mapping = {}
        for i, m in enumerate(old):
            name = (m.name.lower() if m else "")
            mapping[i] = 1 if ("eye" in name or "whisker" in name) else 0
        o.data.materials.clear()
        o.data.materials.append(fur)
        o.data.materials.append(eye)
        for poly in o.data.polygons:
            poly.material_index = mapping.get(poly.material_index, 0)
        o.data.update()
    log("materials|remapped_to_slots=2")


def normalize_orientation():
    eye_c = centroid_of_material({"MAT_Cat_Detail"})
    log("orient|eye_centroid=%s" % (vec(eye_c) if eye_c else "none"))
    if eye_c is None:
        return
    ex, ey = abs(eye_c.x), abs(eye_c.y)
    if ex > ey:
        ang = math.radians(90.0 if eye_c.x > 0 else -90.0)
    elif eye_c.y < 0:
        ang = math.radians(180.0)
    else:
        ang = 0.0
    log("orient|rotate_z_deg=%.1f|abs_eye=(%.3f, %.3f)" % (math.degrees(ang), ex, ey))
    for o in root_objects():
        o.rotation_euler.rotate_axis("Z", ang)
    bpy.context.view_layer.update()


def fit_and_ground(target_len=TARGET_LEN):
    mn, mx = world_bbox()
    dims = mx - mn
    s = target_len / max(1e-6, dims.y)
    for o in root_objects():
        o.scale = (o.scale.x * s, o.scale.y * s, o.scale.z * s)
    bpy.context.view_layer.update()
    mn, mx = world_bbox()
    center = (mn + mx) * 0.5
    dx, dy, dz = -center.x, -center.y, -mn.z
    for o in root_objects():
        o.location = (o.location.x + dx, o.location.y + dy, o.location.z + dz)
    bpy.context.view_layer.update()
    mn, mx = world_bbox()
    log("fit|scale=%.5f|dims=%s|min=%s|max=%s" % (s, vec(mx - mn), vec(mn), vec(mx)))


def join_all(name):
    meshes = mesh_objects()
    main = meshes[0]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = main
    bpy.ops.object.join()
    main.name = name
    log("join|meshes=%d|result=%s" % (len(meshes), main.name))
    return main


# ---------------------------------------------------------------------------
# 骨骼分组（世界坐标）：归一化后 +Y = 前方，+X = 侧向，+Z = 上
# ---------------------------------------------------------------------------

def bone_world(arm, b):
    return arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local


def classify_bones(arm, mesh_min_z, mesh_max_z):
    """按世界坐标把 33 根自动命名骨骼分成：4 条腿 / 脊椎 / 颈头 / 尾。

    关键：腿链要从**分叉点往下**取（含髋那节），否则会把脊椎和腿混在一起。
    """
    low = mesh_min_z + (mesh_max_z - mesh_min_z) * 0.45
    info = {}
    for b in arm.data.bones:
        h, t = bone_world(arm, b)
        info[b.name] = {"head": h, "tail": t,
                        "parent": b.parent.name if b.parent else None,
                        "children": [c.name for c in b.children]}

    def chain_down_from_branch(tip):
        """从 tip 往上走到"父级出现分叉"为止，返回从髋到尾的顺序。"""
        chain = []
        cur = tip
        while cur is not None and cur in info:
            chain.append(cur)
            p = info[cur]["parent"]
            if p is None:
                break
            if len(info[p]["children"]) > 1:
                break                      # p 是分叉点，p 本身不算这条腿
            cur = p
        return chain[::-1]

    leaves = [n for n, d in info.items() if not d["children"]]
    leg_tips = [n for n in leaves if info[n]["tail"].z <= low]
    leg_tips.sort(key=lambda n: info[n]["tail"].z)
    legs = []
    used = set()
    for tip_name in leg_tips[:4]:
        chain = chain_down_from_branch(tip_name)
        if len(chain) < 3:
            continue
        hip = info[chain[0]]["head"]
        foot = info[chain[-1]]["tail"]
        legs.append({"tip": tip_name, "chain": chain, "foot": foot,
                     "fore": 1 if hip.y >= 0 else -1})
        used.update(chain)
    require(len(legs) == 4, "leg_chains|%d" % len(legs))
    # 左右：扫描模型的静止姿态本身不对称，所以不按绝对 x 判，
    # 而是**同一前后对内部按脚尖 x 排序**（大的记为 +1）——对角步态只需要相对关系。
    for fore in (1, -1):
        pair = [l for l in legs if l["fore"] == fore]
        pair.sort(key=lambda l: l["foot"].x)
        for k, l in enumerate(pair):
            l["side"] = 1 if k == len(pair) - 1 else -1
    for l in legs:
        log("leg|%s|fore=%s|side=%s|foot=(%.3f, %.3f, %.3f)" % (
            l["chain"][0], "F" if l["fore"] > 0 else "B",
            "L" if l["side"] > 0 else "R", l["foot"].x, l["foot"].y, l["foot"].z))

    # 其余叶子 = 颈头 / 尾（+Y 是前方：更靠前的是头）
    rest = [n for n in leaves if n not in used]
    rest.sort(key=lambda n: info[n]["tail"].y)
    tail_tip = rest[0] if rest else None
    head_tip = rest[-1] if len(rest) > 1 else None
    chain_tail = chain_down_from_branch(tail_tip) if tail_tip else []
    chain_head = chain_down_from_branch(head_tip) if head_tip else []
    used.update(chain_tail)
    used.update(chain_head)

    # 脊椎 = 颈头链髋部的祖先（从根往下），排除腿/尾
    spine = []
    if chain_head:
        cur = info[chain_head[0]]["parent"]
        while cur is not None and cur in info:
            spine.append(cur)
            cur = info[cur]["parent"]
        spine = [n for n in spine[::-1] if n not in used]

    log("group|legs=%d|spine=%s|head=%s|tail=%s" % (
        len(legs), spine, chain_head, chain_tail))
    require(len(spine) >= 2, "spine_chain|%d" % len(spine))
    require(len(chain_head) >= 2, "head_chain|%d" % len(chain_head))
    require(len(chain_tail) >= 2, "tail_chain|%d" % len(chain_tail))
    return {"legs": legs, "spine": spine, "head": chain_head, "tail": chain_tail}


# ---------------------------------------------------------------------------
# 动作生成
# ---------------------------------------------------------------------------

def rot_about(pb, axis_arm, angle):
    """把骨骼绕**骨架空间**的一个轴旋转 angle（与骨骼自身朝向无关）。"""
    rest = pb.bone.matrix_local
    R = Matrix.Rotation(angle, 4, axis_arm)
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = (rest.inverted() @ R @ rest).to_quaternion()


def key_pose(pb, frame):
    pb.keyframe_insert("rotation_quaternion", frame=frame)


def clear_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)


def make_action(arm, groups, name, frames, amp):
    """amp 里放各段动作的幅度参数；返回 action。"""
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    clear_pose(arm)
    ax_x = arm.matrix_world.inverted().to_3x3().normalized() @ Vector((1.0, 0.0, 0.0))
    ax_z = arm.matrix_world.inverted().to_3x3().normalized() @ Vector((0.0, 0.0, 1.0))
    legs = groups["legs"]
    spine = groups["spine"]
    head = groups["head"]
    tail = groups["tail"]
    for i in range(frames + 1):
        t = float(i) / float(frames)          # 0..1，末帧 = 首帧，保证循环
        ph = t * 2.0 * math.pi
        clear_pose(arm)
        # 腿：对角步态（前左 + 后右 同相）
        for leg in legs:
            phase = ph if leg["fore"] * leg["side"] > 0 else ph + math.pi
            upper = leg["chain"][0]
            lower = leg["chain"][2] if len(leg["chain"]) >= 3 else leg["chain"][-1]
            rot_about(arm.pose.bones[upper], ax_x, math.sin(phase) * amp["leg"])
            rot_about(arm.pose.bones[lower], ax_x, -abs(math.sin(phase)) * amp["knee"])
        # 脊椎：俯仰 + 轻微左右；跑步再前倾
        if spine:
            rot_about(arm.pose.bones[spine[len(spine) // 2]], ax_x,
                      amp["pitch"] + math.sin(ph * 2.0) * amp["bob_pitch"])
            rot_about(arm.pose.bones[spine[len(spine) // 2]], ax_z,
                      math.sin(ph) * amp["roll"])
        # 头：反向补偿一点，别跟着甩
        if head:
            rot_about(arm.pose.bones[head[-1]], ax_x, -amp["pitch"] * 0.7)
        # 尾：左右摆（频率 1×），幅度按动作
        for k, tn in enumerate(tail):
            rot_about(arm.pose.bones[tn], ax_z,
                      math.sin(ph + k * 0.6) * amp["tail"] * (1.0 + 0.25 * k))
        # 身体起伏：根骨沿骨架 Z 平移
        root = arm.pose.bones[spine[0]] if spine else None
        if root is not None:
            root.location = Vector((0.0, 0.0, math.sin(ph * 2.0) * amp["bob"]))
            root.keyframe_insert("location", frame=i + 1)
        for pb in arm.pose.bones:
            key_pose(pb, i + 1)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
    log("action|%s|frames=%d|fcurves=%d" % (name, frames, len(act.fcurves)))
    return act


def stash_nla(arm, actions):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    for act in actions:
        tr = ad.nla_tracks.new()
        tr.name = act.name
        strip = tr.strips.new(act.name, 1, act)
        strip.name = act.name
        log("nla|track=%s|action=%s|frames=%.0f..%.0f" % (
            tr.name, act.name, act.frame_range[0], act.frame_range[1]))
    for o in bpy.data.objects:          # 非骨架对象不要有动画数据（否则导出器会多出常量动画）
        if o.type != "ARMATURE":
            o.animation_data_clear()


def export_glb():
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        if o.type in {"MESH", "ARMATURE"} and not o.name.startswith("RENDER_"):
            o.select_set(True)
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    wanted = {
        "export_format": "GLB", "use_selection": True, "export_apply": False,
        "export_yup": True, "export_materials": "EXPORT", "export_cameras": False,
        "export_lights": False, "export_extras": False, "export_texcoords": True,
        "export_normals": True, "export_colors": False,
        "export_skins": True, "export_animations": True,
        "export_nla_strips": True, "export_frame_range": False,
        "export_anim_single_armature": True, "export_force_sampling": True,
    }
    applied = {k: v for k, v in wanted.items() if k in props}
    log("export|unsupported=%s" % (",".join(sorted(k for k in wanted if k not in props)) or "none"))
    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=GLB_OUT, **applied)
    with open(GLB_OUT, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (GLB_OUT, len(data), hashlib.sha256(data).hexdigest()))


def report_glb_animations():
    import json
    import struct
    with open(GLB_OUT, "rb") as f:
        data = f.read()
    _, _, total = struct.unpack_from("<III", data, 0)
    off = 12
    js = None
    while off < total:
        clen, ctype = struct.unpack_from("<II", data, off)
        if ctype == 0x4E4F534A:
            js = json.loads(data[off + 8:off + 8 + clen].decode())
        off += 8 + clen
    anims = [(a.get("name"), len(a.get("channels", []))) for a in js.get("animations", [])]
    log("glb|animations=%s" % anims)
    require(len(anims) == 3, "animation_count|%d" % len(anims))
    names = {a[0] for a in anims}
    for want in ("Idle", "Walk", "Run"):
        require(want in names, "missing_animation|%s" % want)


def main():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    stage = args[args.index("--stage") + 1] if "--stage" in args else "all"
    log("start|blender=%s|stage=%s" % (bpy.app.version_string, stage))
    require(os.path.isfile(REF_FBX), "ref_missing|%s" % REF_FBX)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.fbx(filepath=REF_FBX)
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    log("import|objects=%d|meshes=%d|armatures=%d|bones=%s" % (
        len(bpy.data.objects), len(mesh_objects()), len(armatures),
        [len(a.data.bones) for a in armatures]))
    if not require(len(armatures) == 1, "armature_count|%d" % len(armatures)):
        sys.exit(1)
    arm = armatures[0]

    fur, eye = build_materials()
    remap_materials(fur, eye)
    normalize_orientation()
    fit_and_ground(TARGET_LEN)
    obj = join_all("CAT_BODY_001")

    mn, mx = world_bbox()
    groups = classify_bones(arm, mn.z, mx.z)
    if stage == "probe":
        log("probe_only|done")
        sys.exit(0 if not failures else 1)

    amps = {
        "Walk": {"leg": math.radians(18.0), "knee": math.radians(10.0), "pitch": math.radians(1.0),
                 "bob_pitch": math.radians(1.5), "roll": math.radians(1.5),
                 "tail": math.radians(7.0), "bob": 0.006},
        "Run": {"leg": math.radians(30.0), "knee": math.radians(18.0), "pitch": math.radians(6.0),
                "bob_pitch": math.radians(3.0), "roll": math.radians(3.0),
                "tail": math.radians(10.0), "bob": 0.012},
        "Idle": {"leg": math.radians(1.0), "knee": math.radians(1.0), "pitch": math.radians(0.0),
                 "bob_pitch": math.radians(1.5), "roll": math.radians(0.4),
                 "tail": math.radians(6.0), "bob": 0.004},
    }
    actions = []
    for name, frames in (("Idle", 48), ("Walk", 24), ("Run", 16)):
        actions.append(make_action(arm, groups, name, frames, amps[name]))
    stash_nla(arm, actions)

    obj.data.calc_loop_triangles()
    tris = len(obj.data.loop_triangles)
    mn, mx = world_bbox()
    dims = mx - mn
    log("check|tris=%d|slots=%d|bones=%d|dims=%s|min_z=%.4f" % (
        tris, len(obj.data.materials), len(arm.data.bones), vec(dims), mn.z))
    require(tris <= TRI_BUDGET, "tri_budget|%d" % tris)
    require(len(obj.data.materials) == 2, "slot_count|%d" % len(obj.data.materials))
    require(abs(mn.z) < 0.005, "not_grounded|%.4f" % mn.z)
    require(mx.z <= MAX_HEIGHT + 0.01, "too_tall|%.4f" % mx.z)
    require(abs(dims.y - TARGET_LEN) < 0.02, "length_off|%.4f" % dims.y)

    export_glb()
    report_glb_animations()
    log("done|tris=%d|actions=%d|failures=%d" % (tris, len(actions), len(failures)))
    sys.exit(0 if not failures else 1)


main()
