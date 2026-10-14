# -*- coding: utf-8 -*-
"""T005 静态资产往返 —— Blender 侧探针建模脚本（Blender 3.3.1 无头 CLI）

为什么要有这个脚本：
  T005 的验收不是"生成了一个 .glb"，而是"Blender 里 1 m 的物体，到 Godot 里仍是 1.0 m"。
  因此本脚本做三件可复现、可审计的事：
    1) 显式建模（**不拿出厂 Cube** —— 出厂 Cube 实测 2.000000 m，不能当 1 m 基准）
    2) 保存独立 .blend，再**重开该文件**读回名称与尺寸（证明落盘内容真的正确）
    3) 导出 glTF 2.0 (.glb)，并打印实际生效的导出设置与文件 SHA256

输出约定（见 Docs/BlenderPipeline.md）：
  stdout 全是 ASCII（Windows 控制台编码不可靠），机器可读行格式 PROBE|key=value
  退出码 0 = 成功；1 = 失败（失败前打印 PROBE|FATAL|...）

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup \
      --python 'E:\\Reborn\\Tools\\Blender\\t005_static_probe.py'
"""

import hashlib
import os
import sys

import bpy
from mathutils import Vector

# --- 路径（Windows 绝对路径，脚本不在 blender 工作目录假设之下） ---
REPO = "E:/Reborn"
BLEND_OUT = REPO + "/Art/Blender/Tests/StaticProbe_v001.blend"
GLB_OUT = REPO + "/Art/Exports/Tests/SM_ProbeCube.glb"

# --- 几何契约（单位：米。Blender 与 Godot 都是米） ---
CUBE_EDGE = 1.0        # 探针立方体边长，T005 的基准
MARKER_EDGE = 0.1      # 方向标记边长
# 标记位置：分别检验 Blender 的 -Y(前) / +Z(上) / +X(右) 在 Godot 里映射到哪
MARKERS = {
    "Marker_Front": (0.0, -2.0, 0.0),
    "Marker_Top": (0.0, 0.0, 2.0),
    "Marker_Right": (2.0, 0.0, 0.0),
}
# 材质：区分方向靠**反照率 + 方向光**，不用自发光
# （自发光会冲掉明暗面，见 Docs/Evidence/Visual-Verification.md 3.2）
MATERIALS = {
    "MAT_Probe": (0.55, 0.58, 0.60, 1.0),        # 灰
    "MAT_Marker_Front": (0.85, 0.10, 0.10, 1.0),  # 红
    "MAT_Marker_Top": (0.10, 0.20, 0.85, 1.0),    # 蓝
    "MAT_Marker_Right": (0.90, 0.75, 0.10, 1.0),  # 黄
}

failures = []


def log(line):
    """机器可读事实行（ASCII）。"""
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


def world_bounds(obj):
    """对象在世界空间的 AABB（min, max），单位米。"""
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    mn = Vector((min(c[0] for c in corners), min(c[1] for c in corners), min(c[2] for c in corners)))
    mx = Vector((max(c[0] for c in corners), max(c[1] for c in corners), max(c[2] for c in corners)))
    return mn, mx


def dump_objects(tag):
    """打印当前场景的对象清单与实测数据。"""
    objs = sorted([o for o in bpy.data.objects], key=lambda o: o.name)
    log("%s|object_count=%d|names=%s" % (tag, len(objs), ",".join(o.name for o in objs)))
    for o in objs:
        mn, mx = world_bounds(o)
        tris = 0
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            tris = len(o.data.loop_triangles)
        log("%s|obj=%s|type=%s|dims=%s|scale=%s|loc=%s|world_min=%s|world_max=%s|verts=%d|tris=%d" % (
            tag, o.name, o.type, vec_str(o.dimensions), vec_str(o.scale),
            vec_str(o.location), vec_str(mn), vec_str(mx),
            len(o.data.vertices) if o.type == "MESH" else 0, tris,
        ))
    return objs


def require(cond, msg):
    if not cond:
        fail(msg)
    return cond


def make_cube(name, edge, location, material):
    """建一个边长精确为 edge 米的立方体，名称确定，无残留缩放。"""
    if bpy.data.objects.get(name) is not None:
        fatal("object_exists_before_create|%s" % name)  # 不允许出现 Cube.001 式重复
    bpy.ops.mesh.primitive_cube_add(size=edge, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name + "_Mesh"
    # 显式钉死尺寸并应用缩放，杜绝残余 scale 影响后续导入
    obj.dimensions = (edge, edge, edge)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)
    require(abs(obj.scale[0] - 1.0) < 1e-6 and abs(obj.dimensions[0] - edge) < 1e-6,
            "cube_scale_not_applied|%s|scale=%s|dims=%s" % (name, vec_str(obj.scale), vec_str(obj.dimensions)))
    obj.data.materials.append(material)
    return obj


def build_material(mat_name):
    mat = bpy.data.materials.new(mat_name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        fatal("no_principled_bsdf|%s" % mat_name)
    color = MATERIALS[mat_name]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.55
    # 明确不设自发光
    if "Emission" in bsdf.inputs:
        bsdf.inputs["Emission"].default_value = (0.0, 0.0, 0.0, 1.0)
    return mat


def export_glb():
    """导出 glTF 2.0；只传**本机 Blender 真实支持**的 kwargs，并记录实际生效项。"""
    if not hasattr(bpy.ops.export_scene, "gltf"):
        fatal("export_scene_gltf_missing")
    # 注意：必须取**算子的 RNA**（get_rna_type），不能用 bpy.types.EXPORT_SCENE_OT_gltf.bl_rna。
    # 后者只是 Operator 基类，实测只有 14 个基础键，会把全部真实 kwargs 误判为"不支持"
    # （已实测踩到：误判 → FATAL export_format_kwarg_unsupported，导出根本没执行）。
    rna = bpy.ops.export_scene.gltf.get_rna_type()
    props = set(rna.properties.keys())
    wanted = {
        "export_format": "GLB",
        "use_selection": False,
        "export_apply": True,      # 应用修改器
        "export_yup": True,        # Blender +Z-up -> glTF +Y-up（Godot 一致）
        "export_materials": "EXPORT",
        "export_cameras": False,
        "export_lights": False,
        "export_extras": False,
        "export_texcoords": True,
        "export_normals": True,
    }
    applied = {k: v for k, v in wanted.items() if k in props}
    unsupported = sorted(k for k in wanted if k not in props)
    log("gltf_export|op_found=True|applied=%s|unsupported=%s" % (
        ",".join("%s=%s" % (k, applied[k]) for k in sorted(applied)), ",".join(unsupported) or "none"))

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

    # --- 0) 空文件起步：不删除任何"不属于本次资产"的对象 ---
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

    # --- 1) 建模 ---
    mats = {name: build_material(name) for name in MATERIALS}
    for name in MATERIALS:
        c = MATERIALS[name]
        log("material|%s|base_color=(%.3f, %.3f, %.3f, %.3f)|roughness=%.2f|emission=0.0" % (
            name, c[0], c[1], c[2], c[3], 0.55))

    make_cube("ProbeCube", CUBE_EDGE, (0.0, 0.0, 0.0), mats["MAT_Probe"])
    for name, loc in MARKERS.items():
        mat_key = "MAT_" + name
        make_cube(name, MARKER_EDGE, loc, mats[mat_key])

    dump_objects("built")

    # 关键断言：探针边长必须是 1.000000 m，且三个标记的位置就是设计值
    probe = bpy.data.objects["ProbeCube"]
    require(max(abs(probe.dimensions[i] - CUBE_EDGE) for i in range(3)) < 1e-6,
            "probe_cube_not_1m|dims=%s" % vec_str(probe.dimensions))
    log("check|probe_named=%s|edge_m=%.6f" % (probe.name, probe.dimensions.x))
    for name, loc in MARKERS.items():
        o = bpy.data.objects[name]
        require(max(abs(o.location[i] - loc[i]) for i in range(3)) < 1e-6,
                "marker_moved|%s|loc=%s" % (name, vec_str(o.location)))

    # --- 2) 保存独立 .blend ---
    if os.path.isfile(BLEND_OUT):
        log("overwrite_warning|exists=True|path=%s" % BLEND_OUT)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
    require(os.path.isfile(BLEND_OUT), "blend_not_written|%s" % BLEND_OUT)
    with open(BLEND_OUT, "rb") as f:
        bdata = f.read()
    log("blend|path=%s|bytes=%d|sha256=%s" % (BLEND_OUT, len(bdata), hashlib.sha256(bdata).hexdigest()))

    # --- 3) 重开该文件，读回名称与尺寸（证明落盘内容正确，而非只在内存里对） ---
    bpy.ops.wm.open_mainfile(filepath=BLEND_OUT)
    require(os.path.realpath(bpy.data.filepath) == os.path.realpath(BLEND_OUT),
            "reopen_wrong_file|%s" % bpy.data.filepath)
    reopened = dump_objects("reopen")
    names = sorted(o.name for o in reopened)
    require(names == sorted(["ProbeCube"] + list(MARKERS.keys())),
            "reopen_names_changed|%s" % ",".join(names))
    rp = bpy.data.objects.get("ProbeCube")
    require(rp is not None and max(abs(rp.dimensions[i] - CUBE_EDGE) for i in range(3)) < 1e-6,
            "reopen_probe_wrong_size|%s" % (vec_str(rp.dimensions) if rp else "missing"))
    log("reopen|probe_edge_m=%.6f|names=%s" % (rp.dimensions.x, ",".join(names)))

    # --- 4) 导出 glb（导出的就是刚重开确认过的文件状态） ---
    export_glb()

    log("done|failures=%d" % len(failures))
    sys.exit(0 if not failures else 1)


main()
