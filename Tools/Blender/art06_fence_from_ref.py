# -*- coding: utf-8 -*-
"""ART03-③ ENV_FENCE_MODULE_001：把 CC-BY 石墙 wall_stefan_wr 的高模块做成可平铺围栏件。

源（**只读**）：references/_downloads/wall_stefan_wr/model.glb
逐件实测（Blender 导入，模长单位≈厘米）：
  wall_stone_stone_wall_low_0          1,244 tris  2.4607 × 0.3027 × 2.0058  ← 取它（唯一够高的）
  wall_stone_medium_stone_wall_low_0     324 tris  1.6126 × 0.2728 × 0.9929
  wall_stone_low_stone_wall_low_0        238 tris  1.6221 × 0.1989 × 0.7738
  wall_stone_triplet_stone_wall_low_0    106 tris  0.7899 × 0.2246 × 0.5071
  wall_single_rock_{,_2,_2.001}        32/28/28    单块石头
预算（Docs/ART_ASSET_SPEC.md §2 / §4.5）：围栏模块 500–4k tris，模块长建议 2–4 m。

处理：
  ÷100（cm→m）→ 顶点**只在墙面内（X、Z）缩放**到目标高 3.000 m，厚度（Y）保持天然 0.3027 m
  → 原点归一到"脚印中心 + 底面 z=0" → 渲三视图 → 导出 GLB。

  为什么只缩 X/Z：围栏的**碰撞体是玩法权威**（`FENCE_THICK=0.2`、`FENCE_HEIGHT=3.0`）。
  高度缩到 3.000 让视觉与碰撞同高（否则墙顶会有一米看不见的挡板）；厚度保持 0.30 而不是
  硬压到 0.2 —— 猫胶囊半径 0.16，贴墙时眼位距墙心 0.26 m，视觉半厚 0.1515 m，**不会切进石头里**。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art06_fence_from_ref.py' -- --stage all
"""

import hashlib
import os
import sys

import bpy
from mathutils import Vector

REPO = "E:/Reborn"
REF = REPO + "/references/_downloads/wall_stefan_wr/model.glb"
GLB_OUT = REPO + "/Art/Exports/Environment/SM_Fence_Module_001.glb"
RENDER_DIR = REPO + "/Art/Probes"

MODULE_NAME = "wall_stone_stone_wall_low_0"
TARGET_H = 3.0             # = FENCE_HEIGHT
TRI_BUDGET = 4000          # 单模块预算上限
UNIT_TO_M = 0.01           # 源单位是厘米

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


def tri_count(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def vbbox(o):
    """从顶点算世界包围盒（`bound_box` 是缓存，改过顶点后不可信）。"""
    mw = o.matrix_world
    mn = Vector((1e18, 1e18, 1e18))
    mx = Vector((-1e18, -1e18, -1e18))
    for v in o.data.vertices:
        w = mw @ v.co
        mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
        mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return mn, mx


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    w = bpy.data.worlds.new("W")
    scene.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.28, 0.30, 0.33, 1.0)
    bg.inputs["Strength"].default_value = 0.55
    bpy.ops.mesh.primitive_plane_add(size=24.0, location=(0.0, 0.0, 0.0))
    g = bpy.context.active_object
    g.name = "RENDER_Ground"
    m = bpy.data.materials.new("MAT_RENDER_Ground")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.30, 0.31, 0.33, 1.0)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    g.data.materials.append(m)

    def light(name, loc, energy, sz):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = sz
        ob = bpy.data.objects.new(name, ld)
        ob.location = loc
        ob.rotation_euler = (Vector((0.0, 0.0, 1.4)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(ob)

    light("KEY", (4.0, -5.0, 6.0), 2200.0, 4.0)
    light("FILL", (-5.0, -2.0, 3.0), 800.0, 5.0)
    light("RIM", (0.5, 5.0, 4.0), 1100.0, 3.0)
    cam_data = bpy.data.cameras.new("CAM")
    cam_data.lens = 50.0
    cam = bpy.data.objects.new("CAM", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def rebuild_material(o):
    """把 Sketchfab 的旧式节点（Diffuse + Glossy + Add Shader）重建成 Principled BSDF。

    ⚠ 实测踩到：源材质不是 Principled，`export_scene.gltf` **无法映射** → 导出的 GLB
    `images=0 / baseColorTex=False`（首个版本 33 KB 就是这个原因）。glTF 只认标准的
    Metallic-Roughness 接线，所以这里显式重建：Base Color ← diffuse 贴图、
    Normal ← normal 贴图、Roughness 用常量 0.85（`ART_STYLE_GUIDE.md` 石头 0.7–0.95）。
    源里的第三张（glossy color/alpha）属于 specular 工作流，不强行塞进 Metallic-Roughness。
    """
    old = o.data.materials[0] if o.data.materials else None
    base_img = None
    normal_img = None
    if old is not None and old.use_nodes:
        for l in old.node_tree.links:
            src = l.from_node
            if src.type != "TEX_IMAGE" or src.image is None:
                continue
            if l.to_node.type == "BSDF_DIFFUSE" and l.to_socket.name == "Color":
                base_img = src.image
            elif l.to_node.type == "NORMAL_MAP" and l.to_socket.name == "Color":
                normal_img = src.image
    require(base_img is not None, "base_color_texture_missing")
    require(normal_img is not None, "normal_texture_missing")
    if base_img is None or normal_img is None:
        sys.exit(1)
    log("rebuild_material|base=%s|normal=%s" % (base_img.name, normal_img.name))

    mat = bpy.data.materials.new("MAT_Fence_Stone")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0

    tex_b = nt.nodes.new("ShaderNodeTexImage")
    tex_b.image = base_img
    tex_b.location = (-520, 260)
    nt.links.new(tex_b.outputs["Color"], bsdf.inputs["Base Color"])

    tex_n = nt.nodes.new("ShaderNodeTexImage")
    tex_n.image = normal_img
    tex_n.location = (-520, -160)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-260, -160)
    nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    o.data.materials.clear()
    o.data.materials.append(mat)
    log("material|slots=%d|name=%s" % (len(o.data.materials), mat.name))


def render_views(cam):
    target = Vector((0.0, 0.0, 1.5))
    for name, loc in [("q34", (5.2, -6.0, 3.4)), ("face", (0.0, -7.5, 2.6)), ("end", (7.0, -1.5, 2.2))]:
        cam.location = Vector(loc)
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.render.filepath = "%s/art06_fence_%s.png" % (RENDER_DIR, name)
        bpy.ops.render.render(write_still=True)
        log("render|%s" % name)


def export_glb():
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        if o.type == "MESH" and not o.name.startswith("RENDER_"):
            o.select_set(True)
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    wanted = {
        "export_format": "GLB", "use_selection": True, "export_apply": True,
        "export_yup": True, "export_materials": "EXPORT", "export_cameras": False,
        "export_lights": False, "export_extras": False, "export_texcoords": True,
        "export_normals": True, "export_colors": False,
        "export_skins": False, "export_animations": False,
    }
    bpy.ops.export_scene.gltf(filepath=GLB_OUT, **{k: v for k, v in wanted.items() if k in props})
    with open(GLB_OUT, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (GLB_OUT, len(data), hashlib.sha256(data).hexdigest()))


def main():
    log("start|blender=%s|src=%s" % (bpy.app.version_string, os.path.basename(REF)))
    require(os.path.isfile(REF), "src_missing|%s" % REF)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.ops.import_scene.gltf(filepath=REF)

    src = None
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name.startswith(MODULE_NAME):
            src = o
            break
    require(src is not None, "module_not_found|%s" % MODULE_NAME)
    if src is None:
        sys.exit(1)
    log("picked|%s|tris=%d|verts=%d|slots=%d" % (
        src.name, tri_count(src), len(src.data.vertices), len(src.data.materials)))

    # 只留这一件（其余 6 个模块、空物体父级全部丢掉）。
    # ⚠ 实测踩到：glTF 导入后**网格数据本身是 Y-up**（Sketchfab 根节点带 −90°X 旋转），
    # 直接 `transform_apply` 只烘对象自己的局部变换 → 顶点仍是 Y-up，于是把"厚度"当成高度缩放了
    # （首次运行得到 24.38 × 0.02 × 3.00）。必须先保住世界矩阵、再烘，坐标才是 Z-up 的米制世界坐标。
    mw = src.matrix_world.copy()
    for o in list(bpy.data.objects):
        if o is not src:
            bpy.data.objects.remove(o, do_unlink=True)
    src.parent = None
    src.matrix_world = mw
    bpy.context.view_layer.objects.active = src
    src.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mn, mx = vbbox(src)
    dims0 = mx - mn
    log("src|dims=%s|min=%s" % (vec(dims0), vec(mn)))
    require(dims0.z > dims0.y * 3.0, "axis_guess|z(%.3f) 应远大于厚度 y(%.3f)" % (dims0.z, dims0.y))

    # ① ÷100（cm → m）② 只在墙面内（X 长、Z 高）缩放到目标高；厚度（Y）保持天然值
    s_unit = UNIT_TO_M
    s_plane = TARGET_H / (dims0.z * s_unit)
    for v in src.data.vertices:
        v.co.x = v.co.x * s_unit * s_plane
        v.co.y = v.co.y * s_unit
        v.co.z = v.co.z * s_unit * s_plane
    src.data.update()
    log("scale|unit=%.4f|plane=%.5f|thickness_kept" % (s_unit, s_plane))

    # ③ 原点 = 脚印中心 + 底面 z=0
    mn, mx = vbbox(src)
    center = (mn + mx) * 0.5
    for v in src.data.vertices:
        v.co -= Vector((center.x, center.y, mn.z))
    src.data.update()

    mn, mx = vbbox(src)
    dims = mx - mn
    tris = tri_count(src)
    log("final|name=%s|tris=%d|dims=%s|min=%s|max=%s|slots=%d" % (
        src.name, tris, vec(dims), vec(mn), vec(mx), len(src.data.materials)))
    require(tris <= TRI_BUDGET, "tri_budget|%d>%d" % (tris, TRI_BUDGET))
    require(2.0 <= dims.x <= 4.0, "module_len|%.3f" % dims.x)
    require(absf(dims.z - TARGET_H) < 1e-3, "height|%.4f != %.4f" % (dims.z, TARGET_H))
    require(absf(mn.z) < 5e-4, "not_grounded|%.4f" % mn.z)
    require(absf(mn.x + mx.x) < 5e-4, "x_not_centered|%.4f..%.4f" % (mn.x, mx.x))
    require(absf(mn.y + mx.y) < 5e-4, "y_not_centered|%.4f..%.4f" % (mn.y, mx.y))
    require(len(src.data.materials) <= 2, "slot_over|%d" % len(src.data.materials))
    src.name = "ENV_FENCE_MODULE_001"

    rebuild_material(src)

    cam = setup_render()
    render_views(cam)
    for o in list(bpy.data.objects):
        if o.type in {"LIGHT", "CAMERA"} or o.name.startswith("RENDER_"):
            bpy.data.objects.remove(o, do_unlink=True)
    export_glb()
    log("done|tris=%d|failures=%d" % (tris, len(failures)))
    sys.exit(0 if not failures else 1)

def absf(x):
    return x if x >= 0 else -x


main()
