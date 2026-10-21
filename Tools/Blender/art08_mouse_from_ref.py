# -*- coding: utf-8 -*-
"""ART03-④ 鼠（换源）：把 CC-BY 的 mehrus rat 做成项目合规的 skinned 资产。

源（**只读**）：references/_downloads/mouse_cc_mehrus_rat/rat.glb（470,424 B，sha256 aefd6762…）
实测：3,602 tris / 2,270 verts / 1 材质槽 / 1×1024² 贴图 / **23 骨** / **4 段动作**
      （Armature|Eat / Iddle / Run / Walk）；网格 local bbox 带大偏移（local y≈80–94、z≈356–362）。
预算（Docs/ART_ASSET_SPEC.md §2）：鼠 5k–20k tris；材质槽 ≤2。

处理（每步都写清为什么）：
 ① 材质是 Sketchfab 的 **unlit**（Emission + Transparent + MixShader + LightPath）→ 必须重建为
    Principled（BaseColor=Image_0 / Roughness 0.8 / Metallic 0），否则会变成自发光/透明。
 ② 朝向按项目契约 Blender 面朝 **+Y**（Godot −Z）：用"头/颈骨权重顶点"与"尾骨权重顶点"的 Y 质心
    判朝向，必要时绕 Z 转 180°。
    ⚠ 踩坑：glTF 导入的对象 `rotation_mode` 是 QUATERNION，**写 rotation_euler 完全无效**，
    必须直接左乘旋转矩阵。
 ③ 尺度按**去掉尾巴的身体长度**归一到 0.135 m（家鼠体长量级）。
 ④ 原点 = 脚印中心 + 脚底 z=0（按 Idle 第 0 帧的**实际**包围盒，不是绑定姿势）。
 ⑤ 4 段动作各自塞进一条 **NLA 轨道**后导出 —— Blender 3.3 只有在 `export_nla_strips=True` 时
    才会把每条轨道导成一个 glTF 动画（第一版只出了 1 段 "Animation"）。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art08_mouse_from_ref.py' -- --stage all
"""

import hashlib
import json
import math
import os
import struct
import sys

import bpy
from mathutils import Matrix, Vector

REPO = "E:/Reborn"
REF = REPO + "/references/_downloads/mouse_cc_mehrus_rat/rat.glb"
GLB_OUT = REPO + "/Art/Exports/Mouse/SM_Mouse_002.glb"
RENDER_DIR = REPO + "/Art/Probes"

TARGET_BODY_LEN = 0.135      # 家鼠身体长度（不含尾巴）
TRI_BUDGET = 20000
IDLE_ACTION_HINT = "ddle"    # 源里作者拼成 "Iddle"

failures = []


def log(s):
    sys.stdout.write("PROBE|" + s + "\n")
    sys.stdout.flush()


def fail(s):
    failures.append(s)
    sys.stdout.write("PROBE|FAIL|" + s + "\n")
    sys.stdout.flush()


def require(cond, msg):
    if not cond:
        fail(msg)
    return cond


def vec(v):
    return "(%.4f, %.4f, %.4f)" % (v[0], v[1], v[2])


def pick_mesh():
    return [o for o in bpy.data.objects if o.type == "MESH"][0]


def pick_arm():
    return [o for o in bpy.data.objects if o.type == "ARMATURE"][0]


def roots():
    return [o for o in bpy.data.objects if o.parent is None]


def eval_verts_world(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ev.matrix_world
    pts = [mw @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    return pts


def bbox(pts):
    mn = Vector((1e18, 1e18, 1e18))
    mx = Vector((-1e18, -1e18, -1e18))
    for p in pts:
        mn = Vector((min(mn.x, p.x), min(mn.y, p.y), min(mn.z, p.z)))
        mx = Vector((max(mx.x, p.x), max(mx.y, p.y), max(mx.z, p.z)))
    return mn, mx


def group_mass(obj, keyword):
    """返回"权重主要落在含 keyword 的顶点组里"的顶点下标集合。"""
    idx = {g.index for g in obj.vertex_groups if keyword in g.name.lower()}
    if not idx:
        return set()
    out = set()
    for v in obj.data.vertices:
        w = sum(g.weight for g in v.groups if g.group in idx)
        if w >= 0.5:
            out.add(v.index)
    return out


def rebuild_material(obj):
    old = obj.data.materials[0] if obj.data.materials else None
    img = None
    if old is not None and old.use_nodes:
        for n in old.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image is not None:
                img = n.image
                break
    require(img is not None, "base_color_texture_missing")
    if img is None and bpy.data.images:
        img = bpy.data.images[0]
    log("material_src|%s|nodes=%s|image=%s|size=%s" % (
        old.name if old else None,
        ",".join(n.type for n in old.node_tree.nodes) if old and old.use_nodes else "-",
        img.name if img else None,
        ("%dx%d" % (img.size[0], img.size[1])) if img else "-"))

    mat = bpy.data.materials.new("MAT_Mouse_Fur")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.8
    bsdf.inputs["Metallic"].default_value = 0.0
    if img is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.material_index = 0
    log("material_out|slots=%d|name=%s" % (len(obj.data.materials), mat.name))


def stash_actions(arm):
    """4 段动作各自塞进一条 NLA 轨道，轨道名规范成 Godot 侧要用的 Idle/Walk/Run/Eat。"""
    name_map = [("eat", "Eat"), ("iddle", "Idle"), ("idle", "Idle"), ("run", "Run"), ("walk", "Walk")]
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    # 每个 action 里除了骨骼姿态还混着空物体/根节点的定位 fcurve（glTF 导入的产物），
    # 导出器会**按目标节点**拆成多段动画（实测 4 段变 11 段，多出来的名字就是那些节点名）。
    # 只保留 pose.bones 通道，动画才干净地是 4 段。
    for act in bpy.data.actions:
        for fc in list(act.fcurves):
            if not fc.data_path.startswith("pose.bones["):
                act.fcurves.remove(fc)
        log("action_fcurves|%s|kept=%d" % (act.name, len(act.fcurves)))
    for act in bpy.data.actions:
        low = act.name.lower()
        nice = act.name
        for k, v in name_map:
            if k in low:
                nice = v
                break
        tr = ad.nla_tracks.new()
        tr.name = nice
        strip = tr.strips.new(nice, int(act.frame_range[0]), act)
        strip.name = nice
        tr.mute = False
        log("nla|track=%s|strip=%s|frames=%.0f..%.0f" % (
            nice, strip.name, act.frame_range[0], act.frame_range[1]))

    # NLA 模式下导出器会**按对象**生成动画：空物体（Sketchfab_model / RootNode / Rat …）
    # 身上残留导入时的 object-level fcurve，会额外冒出 7 段空动画（实测 4 → 11 段）。
    # 这里把除骨架以外所有对象的动画数据清掉，只留骨架的 4 条轨道。
    for o in bpy.data.objects:
        if o is not arm and o.type != "ARMATURE":
            o.animation_data_clear()
    log("cleared_object_anim|kept=%s" % arm.name)


def read_glb_json(path):
    with open(path, "rb") as f:
        data = f.read()
    off = 12
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        if ctype == 0x4E4F534A:
            return json.loads(data[off:off + clen].decode("utf-8"))
        off += clen
    return None


def prune_animations(path, keep):
    """在 GLB 容器里裁掉不要的动画条目（只动 JSON 块，BIN 块原样保留）。

    为什么不靠导出参数：Blender 3.3 没有 `export_animation_mode`，NLA 模式下
    **每个节点**都会附带一段 1 关键帧常量动画（实测 4 段真动画 + 7 段垃圾）。
    直接改 JSON 是最小、可验证的修法：条目删掉后无人引用的 accessor 留着无害。
    """
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _total = struct.unpack_from("<III", data, 0)
    off = 12
    js = None
    bin_chunk = b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            bin_chunk = chunk
    if js is None:
        return (0, [])
    anims = js.get("animations", [])
    kept = [a for a in anims if a.get("name") in keep]
    js["animations"] = kept
    jbytes = json.dumps(js, separators=(",", ":")).encode("utf-8")
    while len(jbytes) % 4:
        jbytes += b" "
    bbytes = bin_chunk
    while len(bbytes) % 4:
        bbytes += b"\x00"
    total = 12 + 8 + len(jbytes) + (8 + len(bbytes) if bbytes else 0)
    out = struct.pack("<III", magic, version, total)
    out += struct.pack("<II", len(jbytes), 0x4E4F534A) + jbytes
    if bbytes:
        out += struct.pack("<II", len(bbytes), 0x004E4942) + bbytes
    with open(path, "wb") as f:
        f.write(out)
    return (len(anims) - len(kept), [a.get("name", "?") for a in kept])


def export_glb():
    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    wanted = {
        "export_format": "GLB", "use_selection": True, "export_apply": False,
        "export_yup": True, "export_materials": "EXPORT", "export_cameras": False,
        "export_lights": False, "export_extras": False, "export_texcoords": True,
        "export_normals": True, "export_skins": True, "export_animations": True,
        "export_anim_single_armature": True, "export_bake_animation": False,
        "export_current_frame": False, "export_nla_strips": True,
        "export_optimize_animation_size": False, "export_frame_range": False,
        "export_rest_position_armature": True,
    }
    if "export_animation_mode" in props:
        wanted["export_animation_mode"] = "NLA_TRACKS"
    bpy.ops.export_scene.gltf(filepath=GLB_OUT, **{k: v for k, v in wanted.items() if k in props})

    # Blender 3.3 的 NLA 导出会把"每个节点的常量变换"也写成一段 1 关键帧动画
    # （实测多出 7 段：Sketchfab_model / RootNode / Armature / Rat …，各 3 通道）。
    # 这些对 Godot 没用且会污染 AnimationPlayer 列表 → 直接在 GLB 的 JSON 块里裁掉。
    pruned = prune_animations(GLB_OUT, keep=("Eat", "Idle", "Run", "Walk"))
    log("prune|removed=%d|kept=%s" % (pruned[0], ",".join(pruned[1])))

    with open(GLB_OUT, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (GLB_OUT, len(data), hashlib.sha256(data).hexdigest()))

    js = read_glb_json(GLB_OUT)
    if js is None:
        require(False, "glb_json_unreadable")
        return
    anims = js.get("animations", [])
    log("glb_json|nodes=%d|meshes=%d|materials=%d|images=%d|skins=%d|animations=%d|joints=%d" % (
        len(js.get("nodes", [])), len(js.get("meshes", [])), len(js.get("materials", [])),
        len(js.get("images", [])), len(js.get("skins", [])), len(anims),
        len(js["skins"][0]["joints"]) if js.get("skins") else 0))
    log("glb_anims|%s" % ",".join(a.get("name", "?") for a in anims))
    require(len(js.get("skins", [])) >= 1, "no_skin_in_glb")
    require(len(anims) == 4, "anim_count|%d" % len(anims))
    require(len(js.get("images", [])) >= 1, "no_texture_in_glb")


def main():
    log("start|blender=%s|src=%s" % (bpy.app.version_string, os.path.basename(REF)))
    require(os.path.isfile(REF), "src_missing")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.ops.import_scene.gltf(filepath=REF)

    obj = pick_mesh()
    arm = pick_arm()
    obj.data.calc_loop_triangles()
    tris = len(obj.data.loop_triangles)
    log("src|tris=%d|verts=%d|slots=%d|bones=%d|vgroups=%d|actions=%d" % (
        tris, len(obj.data.vertices), len(obj.data.materials), len(arm.data.bones),
        len(obj.vertex_groups), len(bpy.data.actions)))
    log("bones|%s" % ",".join(b.name for b in arm.data.bones))
    log("actions|%s" % ",".join("%s(%.0f-%.0f)" % (a.name, a.frame_range[0], a.frame_range[1])
                                for a in bpy.data.actions))

    idle = None
    for a in bpy.data.actions:
        if IDLE_ACTION_HINT in a.name.lower():
            idle = a
            break
    require(idle is not None, "idle_action_missing")
    if arm.animation_data is None:
        arm.animation_data_create()
    if idle is not None:
        arm.animation_data.action = idle
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    log("idle_action|%s" % (idle.name if idle else None))

    rebuild_material(obj)

    head_set = group_mass(obj, "head") | group_mass(obj, "neck")
    tail_set = group_mass(obj, "tail")
    pts = eval_verts_world(obj)


def avg(vals):
    return sum(vals) / len(vals) if vals else None


def finish():
    pass


def main2():
    obj = pick_mesh()
    arm = pick_arm()
    head_set = group_mass(obj, "head") | group_mass(obj, "neck")
    tail_set = group_mass(obj, "tail")
    pts = eval_verts_world(obj)
    hy = avg([pts[i].y for i in head_set if i < len(pts)])
    ty = avg([pts[i].y for i in tail_set if i < len(pts)])
    log("head_tail|head_verts=%d|tail_verts=%d|head_y=%s|tail_y=%s" % (
        len(head_set), len(tail_set),
        ("%.4f" % hy) if hy is not None else "-", ("%.4f" % ty) if ty is not None else "-"))

    if hy is not None and ty is not None and hy < ty:
        rot = Matrix.Rotation(math.pi, 4, "Z")
        for o in roots():
            o.matrix_world = rot @ o.matrix_world
        bpy.context.view_layer.update()
        pts = eval_verts_world(obj)
        hy = avg([pts[i].y for i in head_set if i < len(pts)])
        ty = avg([pts[i].y for i in tail_set if i < len(pts)])
        log("rotated|180deg_about_z|head_y=%.4f|tail_y=%.4f" % (hy, ty))
        require(hy > ty, "facing_not_+Y|head_y=%.4f tail_y=%.4f" % (hy, ty))

    body_pts = [p for i, p in enumerate(pts) if i not in tail_set] or pts
    bmn, bmx = bbox(body_pts)
    body_len = bmx.y - bmn.y
    s = TARGET_BODY_LEN / body_len if body_len > 1e-6 else 1.0
    for o in roots():
        o.scale = o.scale * s
    bpy.context.view_layer.update()
    pts = eval_verts_world(obj)
    mn, mx = bbox(pts)
    log("scale|body_len_before=%.4f|factor=%.6f|dims_after=%s" % (
        body_len, s, vec(mx - mn)))

    center = Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z))
    for o in roots():
        o.location = o.location - center
    bpy.context.view_layer.update()
    pts = eval_verts_world(obj)
    mn, mx = bbox(pts)
    dims = mx - mn
    log("final|dims=%s|min=%s|max=%s" % (vec(dims), vec(mn), vec(mx)))
    require(tris_of(obj) <= TRI_BUDGET, "tri_budget|%d" % tris_of(obj))
    require(len(obj.data.materials) <= 2, "slot_over|%d" % len(obj.data.materials))
    require(abs(mn.z) < 1e-3, "not_grounded|%.4f" % mn.z)
    require(abs(mn.x + mx.x) < 2e-3, "x_not_centered|%.4f..%.4f" % (mn.x, mx.x))
    require(abs(dims.z) >= 0.05, "too_flat|%.4f" % dims.z)
    require(0.10 <= dims.y <= 0.60, "length_out_of_range|%.4f" % dims.y)

    stash_actions(arm)
    export_glb()


def tris_of(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


main()
main2()
log("done|failures=%d" % len(failures))
sys.exit(0 if not failures else 1)
