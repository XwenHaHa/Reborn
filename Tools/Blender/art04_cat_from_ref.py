# -*- coding: utf-8 -*-
"""ART03-① 用参考基础模型产出合规的猫资产：CAT_BODY_001（源：Sketchfab cat_fripouille，CC BY 4.0）

  1) 导入参考 FBX（**只读**，不改动 references/ 里的原文件）
  2) 材质并到 2 槽：SHD_frip→毛发（BaseColor + 法线：DirectX 的 G 通道翻转）、SHD_eye/whiskers→细节
  3) 归一化：按**体长 0.58 m** 统一缩放、按眼睛质心转向到"面朝 +Y"、X 居中、脚底贴地
  4) 渲染 6 视角（与 ART02 同一套机位/灯光），便于横向对比
  5) 导出 GLB（保留 33 骨、关闭动画采样）→ Art/Exports/Cat/SM_Cat_002.glb

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art04_cat_from_ref.py' -- --stage all
"""

import hashlib
import math
import os
import sys

import bpy
from mathutils import Vector

REPO = "E:/Reborn"
REF_FBX = REPO + "/references/_downloads/cat_fripouille/src/source/frip_F_export.fbx"
TEX_DIR = REPO + "/references/_downloads/cat_fripouille/src/textures"
GLB_OUT = REPO + "/Art/Exports/Cat/SM_Cat_002.glb"
RENDER_DIR = REPO + "/Art/Probes"

TARGET_LEN = 0.58          # 体长目标（m）
MAX_HEIGHT = 0.48          # 猫胶囊总高
TRI_BUDGET = 40000         # modeling4 §六 猫预算上限

failures = []


def log(line):
    sys.stdout.write("PROBE|" + line + "\n")
    sys.stdout.flush()


def fail(line):
    failures.append(line)
    sys.stdout.write("PROBE|FAIL|" + line + "\n")
    sys.stdout.flush()


def require(cond, msg):
    if not cond:
        fail(msg)
    return cond


def vec(v):
    return "(%.4f, %.4f, %.4f)" % (v[0], v[1], v[2])


def mesh_objects():
    return [o for o in bpy.data.objects if o.type == "MESH"]


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
    """使用指定材质的网格顶点世界质心（用来判断"眼睛/头在哪一侧"）。"""
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
        # DirectX 法线：G 通道翻转后再进 Normal Map
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
        nt.links.new(inv.outputs[0], comb.inputs["Green"])
        nt.links.new(sep.outputs["Blue"], comb.inputs["Blue"])
        nt.links.new(comb.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    fur.use_backface_culling = True

    eye = bpy.data.materials.new("MAT_Cat_Detail")
    eye.use_nodes = True
    ebsdf = eye.node_tree.nodes["Principled BSDF"]
    ebsdf.inputs["Roughness"].default_value = 0.28
    eye_path = os.path.join(TEX_DIR, "eye_3.tga.png")
    if os.path.isfile(eye_path):
        n_eye = eye.node_tree.nodes.new("ShaderNodeTexImage")
        n_eye.image = tex(eye_path)
        eye.node_tree.links.new(n_eye.outputs["Color"], ebsdf.inputs["Base Color"])
    else:
        ebsdf.inputs["Base Color"].default_value = (0.30, 0.22, 0.05, 1.0)
    eye.use_backface_culling = True
    log("materials|built=2|base_tex=%s|normal_tex=%s" % (
        os.path.isfile(base_path), os.path.isfile(nrm_path)))
    return fur, eye


def remap_materials(fur, eye):
    """把原 3 槽（SHD_frip / SHD_eye / whiskers）并到 2 槽。"""
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


def root_objects():
    return [o for o in bpy.data.objects if o.parent is None]


def normalize_orientation():
    """按"细节材质（眼睛）质心"判断头在哪一侧，旋转到面朝 +Y。"""
    eye_c = centroid_of_material({"MAT_Cat_Detail"})
    log("orient|eye_centroid=%s" % (vec(eye_c) if eye_c else "none"))
    if eye_c is None:
        return
    ex, ey = abs(eye_c.x), abs(eye_c.y)
    if ex > ey:
        # 头在 +X → 需要 +90°（+X→+Y）；头在 -X → -90°
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
    """按体长（Y）统一缩放到目标值，然后 X 居中 + 脚底贴地（min_z=0）。"""
    mn, mx = world_bbox()
    dims = mx - mn
    s = target_len / max(1e-6, dims.y)
    for o in root_objects():            # 只缩放根对象：网格是子级，会自动跟随
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
    return mn, mx


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


def self_check(obj):
    obj.data.calc_loop_triangles()
    tris = len(obj.data.loop_triangles)
    mn, mx = world_bbox()
    dims = mx - mn
    slots = len(obj.data.materials)
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    bones = sum(len(a.data.bones) for a in arm)
    log("check|tris=%d|verts=%d|slots=%d|bones=%d|dims=%s|min=%s|max=%s" % (
        tris, len(obj.data.vertices), slots, bones, vec(dims), vec(mn), vec(mx)))
    require(tris <= TRI_BUDGET, "tri_budget|%d>%d" % (tris, TRI_BUDGET))
    require(slots == 2, "slot_count|%d!=2" % slots)
    require(bones > 0, "no_armature")
    require(abs(mn.z) < 0.005, "not_grounded|%.4f" % mn.z)
    require(mx.z <= MAX_HEIGHT + 0.01, "too_tall|%.4f" % mx.z)
    require(abs(dims.y - TARGET_LEN) < 0.02, "length_off|%.4f" % dims.y)
    require(abs(mn.x + mx.x) < 0.02, "not_centered_x|[%.4f,%.4f]" % (mn.x, mx.x))
    return tris


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.28, 0.30, 0.33, 1.0)
    bg.inputs["Strength"].default_value = 0.55
    bpy.ops.mesh.primitive_plane_add(size=4.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object
    ground.name = "RENDER_Ground"
    gm = bpy.data.materials.new("MAT_RENDER_Ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.30, 0.31, 0.33, 1.0)
    gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    ground.data.materials.append(gm)

    def add_light(name, loc, energy, size, rot):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = size
        ob = bpy.data.objects.new(name, ld)
        ob.location = loc
        ob.rotation_euler = rot
        scene.collection.objects.link(ob)

    add_light("KEY", (0.55, 0.75, 0.85), 110.0, 0.8,
              (math.radians(52.0), 0.0, math.radians(140.0)))
    add_light("FILL", (-0.75, 0.45, 0.55), 40.0, 1.1,
              (math.radians(62.0), 0.0, math.radians(-130.0)))
    add_light("RIM", (0.0, -0.95, 0.70), 70.0, 0.6, (math.radians(115.0), 0.0, 0.0))
    cam_data = bpy.data.cameras.new("CAM")
    cam_data.lens = 60.0
    cam = bpy.data.objects.new("CAM", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def point_camera(cam, location, target):
    cam.location = Vector(location)
    cam.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()


def render_views():
    scene = bpy.context.scene
    cam = scene.camera
    target = Vector((0.0, 0.02, 0.21))
    mn, mx = world_bbox()
    head_y = mx.y - 0.06          # 头在 +Y 端
    mid_z = (mn.z + mx.z) * 0.5
    for name, loc in [("front", (0.0, 1.05, 0.34)), ("side", (1.05, 0.02, 0.32)),
                      ("back", (0.0, -1.05, 0.34)), ("corner45", (0.80, 0.80, 0.46)),
                      ("top", (0.0, 0.06, 1.15)),
                      ("face", (0.26, mx.y + 0.80, mid_z + 0.16))]:
        if name == "face":
            cam.data.lens = 85.0
            aim = Vector((0.0, head_y, mid_z + 0.04))
        else:
            cam.data.lens = 60.0
            aim = target
        point_camera(cam, loc, aim)
        scene.render.filepath = "%s/art04_cat_ref_%s.png" % (RENDER_DIR, name)
        bpy.ops.render.render(write_still=True)
        log("render|view=%s" % name)


def export_glb():
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        if o.type in {"MESH", "ARMATURE"} and not o.name.startswith("RENDER_"):
            o.select_set(True)   # 渲染辅助物（地面/灯/相机）不得进资产
    rna = bpy.ops.export_scene.gltf.get_rna_type()
    props = set(rna.properties.keys())
    wanted = {
        "export_format": "GLB", "use_selection": True, "export_apply": False,
        "export_yup": True, "export_materials": "EXPORT", "export_cameras": False,
        "export_lights": False, "export_extras": False, "export_texcoords": True,
        "export_normals": True, "export_colors": False,
        "export_skins": True, "export_animations": False,
    }
    applied = {k: v for k, v in wanted.items() if k in props}
    bpy.ops.export_scene.gltf(filepath=GLB_OUT, **applied)
    with open(GLB_OUT, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (GLB_OUT, len(data), hashlib.sha256(data).hexdigest()))
    log("glb|unsupported=%s" % (",".join(sorted(k for k in wanted if k not in props)) or "none"))


def main():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    stage = args[args.index("--stage") + 1] if "--stage" in args else "all"
    log("start|blender=%s|ref=%s|stage=%s" % (
        bpy.app.version_string, os.path.basename(REF_FBX), stage))
    require(os.path.isfile(REF_FBX), "ref_missing|%s" % REF_FBX)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.ops.import_scene.fbx(filepath=REF_FBX)
    log("import|objects=%d|meshes=%d|armatures=%d" % (
        len(bpy.data.objects), len(mesh_objects()),
        len([o for o in bpy.data.objects if o.type == "ARMATURE"])))

    fur, eye = build_materials()
    remap_materials(fur, eye)
    normalize_orientation()
    fit_and_ground(TARGET_LEN)
    obj = join_all("CAT_BODY_001")
    tris = self_check(obj)

    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    setup_render()
    render_views()
    if stage == "all":
        export_glb()
    log("done|tris=%d|failures=%d" % (tris, len(failures)))
    sys.exit(0 if not failures else 1)


main()
