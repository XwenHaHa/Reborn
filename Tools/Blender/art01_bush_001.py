# -*- coding: utf-8 -*-
"""ART01 试点资产：草丛掩体 ENV_BUSH_001（Blender 3.3.1 无头 CLI）

为什么是这个资产（详见 Docs/Tasks/ART01.md）：
  关卡里的草丛掩体目前是一个 3x0.9x3 m 的半透明绿盒子（`CoverBush*Mesh`），
  玩家躲藏时的**画面主体**就是它。它只做视觉：碰撞/可见性由同名的 Area3D
  数据体量（3x3x3、visibility_factor=0.4）决定，所以换掉视觉**不影响任何玩法逻辑**。

本脚本做四件可复现、可审计的事：
  1) 程序化建模（确定性 seed，不用任何外部资产/贴图）
  2) 保存独立 .blend，再**重开该文件**读回名称/尺寸/面数（证明落盘内容正确）
  3) 导出 glTF 2.0 (.glb) 并打印实际生效的导出设置与 SHA256
  4) 自检：尺寸包络、面数预算、材质槽数、无残留缩放

几何契约（米，Blender 与 Godot 都是米）：
  - 原点在**地面中心**（z=0 贴地），高度上限 0.90 m（= 旧网格盒子的高）
  - 水平包络半径 ≤ 1.45 m（≈ 3 m 见方，与旧网格 ≤ 3.0 m 一致）
  - 三角形 ≤ 3000（BlenderPipeline 静态环境模块预算）
  - 材质槽 = 2（叶片 / 泥土）

朝向：本资产是静态道具，朝向无严格要求；导出前**不旋转**，靠 Godot 侧 yaw 变化。

输出约定（见 Docs/BlenderPipeline.md）：stdout 全 ASCII，机器可读行 `PROBE|key=value`。
退出码 0 = 成功；1 = 失败（失败前打印 `PROBE|FATAL|...`）。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art01_bush_001.py'
"""

import hashlib
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

# --- 路径（Windows 绝对路径；脚本不假设 blender 的工作目录） ---
REPO = "E:/Reborn"
# 版本约定（BlenderPipeline）：每轮返工保存为**新版本文件**，不覆盖上一版可编辑源。
# 导出产物沿用交付名 SM_Bush_001.glb（Godot 侧引用这个路径），历史版本由 .blend 保留。
BLEND_OUT = REPO + "/Art/Blender/Environment/ENV_BUSH_001_v003.blend"
GLB_OUT = REPO + "/Art/Exports/Environment/SM_Bush_001.glb"

# --- 资产契约 ---
ASSET_NAME = "ENV_BUSH_001"
SEED = 20261031
BLADE_COUNT = 140            # v003：170 → 140（每片草叶改成交叉双面带，实际几何量翻倍）
SEGMENTS = 4                 # 每片草叶 4 段 → 8 三角形 × 2 条带 = 16 三角形
FOOT_RADIUS = 1.35           # 草叶分布半径（米）
MAX_HEIGHT = 0.90            # 最高草叶（米）= 旧网格盒子高度
MOUND_RX = 1.05              # 泥土垫半径（v002：1.30 → 1.05）
MOUND_RZ = 0.045             # 泥土垫**半高**（v002：0.16 → 0.045）
MOUND_CLEAR = 0.12           # 泥土垫顶面上限（米）—— 必须低于蹲下的鼠/猫相机高度
DROOP_FACTOR = 0.22          # 草叶下垂量 / 总长（v003 弯曲用；叶尖最终高度由它反推总长）
TRI_BUDGET = 3000
ENVELOPE_R = 1.45            # 水平包络上限（米，居中）
MAT_LEAF = "MAT_Bush_Leaf"
MAT_SOIL = "MAT_Bush_Soil"
MATERIALS = {
    # 与关卡既有的草色 (0.24,0.42,0.26) 同一色相；线性值，Godot 侧会做 sRGB 编码
    MAT_LEAF: (0.085, 0.200, 0.075, 1.0),
    MAT_SOIL: (0.055, 0.038, 0.025, 1.0),
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


def require(cond, msg):
    if not cond:
        fail(msg)
    return cond


def vec_str(v):
    return "(%.6f, %.6f, %.6f)" % (v[0], v[1], v[2])


def world_bounds(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    mn = Vector((min(c[0] for c in corners), min(c[1] for c in corners), min(c[2] for c in corners)))
    mx = Vector((max(c[0] for c in corners), max(c[1] for c in corners), max(c[2] for c in corners)))
    return mn, mx


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def build_materials():
    mats = {}
    for name, color in MATERIALS.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf is None:
            fatal("no_principled_bsdf|%s" % name)
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.85
        if "Specular" in bsdf.inputs:
            bsdf.inputs["Specular"].default_value = 0.15
        if "Emission" in bsdf.inputs:
            bsdf.inputs["Emission"].default_value = (0.0, 0.0, 0.0, 1.0)
        # 关键：**保持双面**（Blender 默认不背面剔除 → glTF doubleSided=true → Godot cull_disabled）。
        # 玩家会站在草丛**里面**，单面草叶会从内侧消失。
        mat.use_backface_culling = False
        log("material|%s|base_color=(%.4f, %.4f, %.4f, %.2f)|roughness=0.85|double_sided=True" % (
            name, color[0], color[1], color[2], color[3]))
        mats[name] = mat
    return mats


def add_blade(bm, base, plane_dir, height, width, lean):
    """一片草叶：带**收尖叶尖**的弯曲带状三角化。

    v003 修掉的真实缺陷（视觉判读原话）：草叶是"直立的细长柱子/板条"、"顶部平截"。
      1) **弯曲**：中心线加二次下垂项（droop），叶尖向外、向下弯成弧线；
      2) **收尖**：最后一段不再是两根顶点，而是收成**一个尖点**（旧版叶尖宽度 1.5 mm 仍是平截）；
      3) **交叉双面**：每片草叶两条互相垂直的带子（副带 lean*0.35），
         单面带子从"正对带面"的方向看会退化成一条线，交叉后任何角度都有体积。
    高度参数含义是**叶尖最终高度**（下垂量先补偿掉），保证契约上限不被下垂悄悄吃掉。
    """
    up = Vector((0.0, 0.0, 1.0))
    side = plane_dir.cross(up)
    if side.length < 1e-6:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    height = height / (1.0 - DROOP_FACTOR)
    droop = DROOP_FACTOR * height

    def center_at(t):
        return (base + plane_dir * (lean * (t ** 1.5))
                + up * (height * t - droop * t * t))

    rings = []
    for k in range(SEGMENTS):          # 0 .. SEGMENTS-1，最后一段单独收尖
        t = float(k) / SEGMENTS
        center = center_at(t)
        w = max(0.0008, width * ((1.0 - t) ** 0.75))
        rings.append((bm.verts.new(center - side * (w * 0.5)),
                      bm.verts.new(center + side * (w * 0.5))))
    tip = bm.verts.new(center_at(1.0))

    faces = []
    for k in range(SEGMENTS - 1):
        l0, r0 = rings[k]
        l1, r1 = rings[k + 1]
        faces.append(bm.faces.new((l0, r0, r1)))
        faces.append(bm.faces.new((l0, r1, l1)))
    l_last, r_last = rings[-1]
    faces.append(bm.faces.new((l_last, r_last, tip)))
    for f in faces:
        f.material_index = 0  # 叶片
    return faces


def build_bush(mats):
    rng = random.Random(SEED)
    bm = bmesh.new()

    heights = []
    radii = []
    for i in range(BLADE_COUNT):
        ang = rng.uniform(0.0, 2.0 * math.pi)
        # 半径偏向外部（sqrt 反比分布会让中心最密；这里用 0.22 + 0.78*sqrt 使外围更密、
        # 中心留出空档 —— 玩家躲在里面时视线不会被叶片糊死）
        r = FOOT_RADIUS * (0.22 + 0.78 * math.sqrt(rng.random()))
        out_dir = Vector((math.cos(ang), math.sin(ang), 0.0))
        # 半径越大越矮 → 形成穹顶轮廓，而不是一排一样高的柱子
        dome = 1.0 - 0.45 * (r / FOOT_RADIUS) ** 2
        # v002：高度不再单一。原先全部落在 0.62~0.95*dome，视觉上像"一排等高的草"。
        # 现在主体降到 0.50~0.90*dome，另有约 18% 的**高草穗**拉高 35%（封顶 ≤ MAX_HEIGHT-0.02），
        # 形成前后层次 —— 这是视觉判读里"轮廓单调"的直接修法。
        h = (0.50 + 0.40 * rng.random()) * dome
        if rng.random() < 0.18:
            h = min(MAX_HEIGHT - 0.02, h * 1.35)
        # v003：叶片变窄（0.030~0.045 → 0.024~0.038）。视觉判读把旧宽度读成"板条"。
        width = 0.024 + 0.014 * rng.random()
        # v003：倾倒量随半径增加 —— 中心直立、外围自然外倾（旧版与半径无关，很"机械"）
        lean = (0.10 + 0.55 * (r / FOOT_RADIUS) + 0.15 * rng.random()) * h
        # 包络约束：叶尖的径向位置 ≈ r + lean，必须留在 ENVELOPE_R 内。
        # 第一版没有这一步 → 自检抓到 max |y| = 1.497 > 1.45（超出 3 m 见方的旧网格包络）。
        # 修法：超出时只削减该叶片的倾倒量，不改分布（否则草丛密度会不均）。
        lean = min(lean, max(0.0, ENVELOPE_R - 0.01 - r))
        base = Vector((out_dir.x * r, out_dir.y * r, 0.0))
        # 交叉双面：主带 + 水平垂直方向的副带（更矮、更窄、倾倒更小）
        side_dir = Vector((-out_dir.y, out_dir.x, 0.0))
        add_blade(bm, base, out_dir, h, width, lean)
        add_blade(bm, base, side_dir, h * 0.96, width * 0.90, lean * 0.35)
        heights.append(h)
        radii.append(r)

    # 泥土垫：压扁的 icosphere（subdiv=1 → 80 三角形），只给草丛一个"从地里长出来"的底座。
    # v002 修掉的真实缺陷：原来是半径 1.30 m / 高 0.32 m 的实心穹顶 —— 玩家躲进草丛时
    # **相机在土里**（内部视角整屏发黑，视觉判读实拍到了），俯视还占掉 50~70% 的投影面积。
    # 现在半高 0.045 m、顶面 ≤ MOUND_CLEAR，且法线朝上，只当"土垫"看。
    before = set(bm.faces)
    mtx = Matrix.Translation((0.0, 0.0, MOUND_RZ)) @ Matrix.Diagonal(
        (MOUND_RX, MOUND_RX, MOUND_RZ, 1.0)).to_4x4()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0, matrix=mtx)
    for f in bm.faces:
        if f not in before:
            f.material_index = 1  # 泥土

    bm.normal_update()
    mesh = bpy.data.meshes.new(ASSET_NAME + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(ASSET_NAME, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for key in (MAT_LEAF, MAT_SOIL):
        mesh.materials.append(mats[key])
    # 平滑着色只给泥土（草叶保持平面，低多边形风格下轮廓更清楚）
    for poly in mesh.polygons:
        poly.use_smooth = (poly.material_index == 1)
    mesh.update()

    log("build|blades=%d|ribbons_per_blade=2|segments=%d|seed=%d|mound_subdiv=1|"
        "max_blade_h=%.6f|max_radius=%.6f" % (
            BLADE_COUNT, SEGMENTS, SEED, max(heights), max(radii)))
    return obj


def per_material_tris(obj):
    counts = {}
    for poly in obj.data.polygons:
        idx = poly.material_index
        counts[idx] = counts.get(idx, 0) + (len(poly.vertices) - 2)
    return counts


def self_check(obj, tag):
    mn, mx = world_bounds(obj)
    tris = tri_count(obj)
    counts = per_material_tris(obj)
    log("%s|obj=%s|type=%s|dims=%s|scale=%s|loc=%s|world_min=%s|world_max=%s|verts=%d|tris=%d" % (
        tag, obj.name, obj.type, vec_str(obj.dimensions), vec_str(obj.scale),
        vec_str(obj.location), vec_str(mn), vec_str(mx), len(obj.data.vertices), tris))
    log("%s|slot_count=%d|slots=%s|tris_by_slot=%s" % (
        tag, len(obj.data.materials),
        ",".join(m.name if m else "none" for m in obj.data.materials),
        ",".join("%d:%d" % (k, counts[k]) for k in sorted(counts))))

    require(obj.name == ASSET_NAME, "%s|wrong_name|%s" % (tag, obj.name))
    require(len(bpy.data.objects) == 1, "%s|object_count_not_1|%d" % (tag, len(bpy.data.objects)))
    require(len(obj.data.materials) == 2, "%s|slot_count_not_2|%d" % (tag, len(obj.data.materials)))
    require(tris <= TRI_BUDGET, "%s|tri_budget_exceeded|%d>%d" % (tag, tris, TRI_BUDGET))
    require(tris >= 200, "%s|too_few_tris|%d" % (tag, tris))
    require(set(counts.keys()) == {0, 1}, "%s|material_index_missing|%s" % (tag, sorted(counts.keys())))
    require(max(abs(obj.scale[i] - 1.0) for i in range(3)) < 1e-6,
            "%s|residual_scale|%s" % (tag, vec_str(obj.scale)))
    require(abs(mn.z) < 1e-4, "%s|not_grounded|min_z=%.6f" % (tag, mn.z))
    require(mx.z <= MAX_HEIGHT + 1e-4, "%s|too_tall|max_z=%.6f>%.2f" % (tag, mx.z, MAX_HEIGHT))
    require(max(abs(mn.x), abs(mx.x), abs(mn.y), abs(mx.y)) <= ENVELOPE_R + 1e-4,
            "%s|envelope_exceeded|x=[%.3f,%.3f]|y=[%.3f,%.3f]" % (tag, mn.x, mx.x, mn.y, mx.y))
    log("%s|envelope_ok|height=%.6f|width_x=%.6f|width_y=%.6f" % (
        tag, mx.z - mn.z, mx.x - mn.x, mx.y - mn.y))

    # v002 新增硬判据：泥土垫顶面必须低于"躲进去时的相机高度"，否则内部视角拍出来是土。
    soil_z = 0.0
    for poly in obj.data.polygons:
        if poly.material_index == 1:
            for vi in poly.vertices:
                soil_z = max(soil_z, obj.data.vertices[vi].co.z)
    log("%s|soil_pad_top_z=%.6f|clear_limit=%.3f" % (tag, soil_z, MOUND_CLEAR))
    require(soil_z <= MOUND_CLEAR + 1e-4,
            "%s|soil_pad_too_tall|%.4f>%.3f" % (tag, soil_z, MOUND_CLEAR))


def export_glb():
    if not hasattr(bpy.ops.export_scene, "gltf"):
        fatal("export_scene_gltf_missing")
    # 必须取**算子**的 RNA（get_rna_type），不能用 bpy.types.EXPORT_SCENE_OT_gltf.bl_rna
    # —— 后者只有 14 个基础键，会把真实 kwargs 误判为不支持（T005 实测踩到）。
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
        "export_texcoords": False,   # 无贴图，省带宽
        "export_normals": True,
        "export_colors": False,
        "export_skins": False,
        "export_animations": False,
    }
    applied = {k: v for k, v in wanted.items() if k in props}
    unsupported = sorted(k for k in wanted if k not in props)
    log("gltf_export|op_found=True|applied=%s|unsupported=%s" % (
        ",".join("%s=%s" % (k, applied[k]) for k in sorted(applied)),
        ",".join(unsupported) or "none"))
    if "export_format" not in applied:
        fatal("export_format_kwarg_unsupported")

    bpy.ops.export_scene.gltf(filepath=GLB_OUT, **applied)
    if not os.path.isfile(GLB_OUT):
        fatal("glb_not_written|%s" % GLB_OUT)
    with open(GLB_OUT, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (GLB_OUT, len(data), hashlib.sha256(data).hexdigest()))


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
    log("units|system=%s|scale_length=%.6f|length_unit=%s" % (
        scene.unit_settings.system, scene.unit_settings.scale_length,
        scene.unit_settings.length_unit))

    for d in (os.path.dirname(BLEND_OUT), os.path.dirname(GLB_OUT)):
        if not os.path.isdir(d):
            os.makedirs(d)
            log("mkdir|%s" % d)

    mats = build_materials()
    obj = build_bush(mats)
    self_check(obj, "built")

    if os.path.isfile(BLEND_OUT):
        log("overwrite_warning|exists=True|path=%s" % BLEND_OUT)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
    require(os.path.isfile(BLEND_OUT), "blend_not_written|%s" % BLEND_OUT)
    with open(BLEND_OUT, "rb") as f:
        bdata = f.read()
    log("blend|path=%s|bytes=%d|sha256=%s" % (BLEND_OUT, len(bdata), hashlib.sha256(bdata).hexdigest()))

    # 重开该文件，读回落盘内容（证明不是只在内存里对）
    bpy.ops.wm.open_mainfile(filepath=BLEND_OUT)
    require(os.path.realpath(bpy.data.filepath) == os.path.realpath(BLEND_OUT),
            "reopen_wrong_file|%s" % bpy.data.filepath)
    rp = bpy.data.objects.get(ASSET_NAME)
    require(rp is not None, "reopen_asset_missing|%s" % ",".join(o.name for o in bpy.data.objects))
    if rp is not None:
        self_check(rp, "reopen")

    export_glb()

    log("done|failures=%d" % len(failures))
    sys.exit(0 if not failures else 1)


main()
