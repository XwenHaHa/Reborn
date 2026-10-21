# -*- coding: utf-8 -*-
"""ART02 · 猫 CAT_BODY_001 **V009 基础形体重建**（Blender 3.3.1 无头 CLI）

为什么另起一套（`modeling3.md` §2/§3）：
  V008 是"放样零件 + voxel remesh 焊接 + decimate + 噪声位移"，被判读为
  「躯干波浪状隆起 / 条纹 / 破面 / 四肢关节模糊 / 眼睛空洞 / 尾巴僵硬」。
  根因不是参数没调好，而是**方法**：remesh/decimate 会把形体磨平并留下周期性台阶，
  噪声位移只是把缺陷包一层"毛"。§2 明确不接受继续细分或只改材质。

V009 的做法（多边形建模，**不使用 voxel remesh / decimate / 噪声位移**）：
  1) 躯干 + 四肢 + 脚趾 + 尾巴 = **一根骨架 + Skin 修改器 + 1 级细分** →
     连续四边形拓扑，四肢/尾巴/脚趾都是**同一张曲面上的分支**，没有"插上去的圆柱"；
  2) 头部 = **逐截面放样 + 剖面调制**（颅骨/眉弓/颊毛/胡须垫/下巴由同一张曲面塑造），
     头部后环缩进颈内，靠曲面交叠过渡（不做布尔、不做 remesh）；
  3) 眼睛 = 眼球 + **上下眼睑环**（有眼皮包覆，不是空洞）；耳朵 = 有厚度的耳壳 + 内耳深色面；
  4) 形体判读通过后再做材质（沿用烘焙 albedo 管线；**不加噪声掩盖几何**）。

坐标与契约同 V008（`Docs/Tasks/ART02.md` §3）：面朝 +Y、+Z 向上、米制、原点在四脚着地中心。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art02_cat_v009.py' -- --version v009 --stage all
"""

import hashlib
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

REPO = "E:/Reborn"
ASSET_NAME = "CAT_BODY_001"
BLEND_DIR = REPO + "/Art/Blender/Cat"
STAGE_DIR = REPO + "/Art/Staging/ART02_V009"
RENDER_DIR = REPO + "/Art/Probes"

MAT_FUR = "MAT_Cat_Fur"
MAT_DETAIL = "MAT_Cat_Detail"

TRI_BUDGET = 10000
CAPSULE_RADIUS = 0.16
CAPSULE_HEIGHT = 0.48
X_LIMIT = CAPSULE_RADIUS + 0.02
Z_LIMIT = CAPSULE_HEIGHT
SYMMETRY_TOL = 0.006

RING_SEG = 24
TEX_SIZE = 2048

COL_BACK = (0.070, 0.048, 0.030, 1.0)
COL_MID = (0.170, 0.108, 0.058, 1.0)
COL_BELLY = (0.430, 0.370, 0.305, 1.0)
COL_STRIPE = (0.045, 0.032, 0.020, 1.0)
COL_MUZZLE = (0.515, 0.470, 0.425, 1.0)
COL_EARTIP = (0.032, 0.024, 0.018, 1.0)

EYE_R = 0.0118
## 第二轮返工：眼睛内收 2 mm（判读：眼球外凸像玩偶）
EYE_POS = (0.0295, 0.2865, 0.3000)
NOSE_POS = (0.0, 0.3255, 0.2665)
EAR_BASE = (0.030, 0.252, 0.312)
EAR_TIP = (0.070, 0.240, 0.380)

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


# ------------------------------------------------------------------ 通用几何

def catmull_rom(points, samples_per_seg=6):
    pts = [Vector(p) for p in points]
    if len(pts) < 3:
        return pts
    ext = [pts[0] - (pts[1] - pts[0])] + pts + [pts[-1] + (pts[-1] - pts[-2])]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for s in range(samples_per_seg):
            t = float(s) / samples_per_seg
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t
                              + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


def add_loft(bm, stations, n=RING_SEG, cap_start=True, cap_end=True, modulate=None):
    """stations = [(center, side, up, rw, rh), ...]。"""
    rings = []
    total = max(1, len(stations) - 1)
    for idx, (c, side, up, rw, rh) in enumerate(stations):
        t = float(idx) / total
        ring = []
        for i in range(n):
            a = 2.0 * math.pi * float(i) / n
            cs, sn = math.cos(a), math.sin(a)
            mw, mh = (1.0, 1.0) if modulate is None else modulate(idx, t, a, cs, sn)
            ring.append(bm.verts.new(c + side * (cs * rw * mw) + up * (sn * rh * mh)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    if cap_start:
        bm.faces.new(list(reversed(rings[0])))
    if cap_end:
        bm.faces.new(list(rings[-1]))
    return rings


def add_tube_along(bm, path, radii, n=10, cap_start=True, cap_end=True):
    stations = []
    for i, p in enumerate(path):
        if i == 0:
            tan = path[1] - path[0]
        elif i == len(path) - 1:
            tan = path[-1] - path[-2]
        else:
            tan = path[i + 1] - path[i - 1]
        tan = tan.normalized()
        side = Vector((1.0, 0.0, 0.0)) - tan * tan.x
        if side.length < 1e-5:
            side = Vector((0.0, 1.0, 0.0)) - tan * tan.y
        side.normalize()
        up = side.cross(tan).normalized()
        stations.append((p, side, up, radii[i][0], radii[i][1]))
    return add_loft(bm, stations, n=n, cap_start=cap_start, cap_end=cap_end)


def add_quad_sphere(bm, center, rx, ry, rz, n=16, rings=10):
    c = Vector(center)
    stations = []
    for k in range(rings + 1):
        a = math.pi * float(k) / rings
        r = math.sin(a)
        h = math.cos(a)
        stations.append((c + Vector((0.0, 0.0, rz * h)), Vector((1.0, 0.0, 0.0)),
                         Vector((0.0, 1.0, 0.0)), max(1e-5, rx * r), max(1e-5, ry * r)))
    return add_loft(bm, stations, n=n, cap_start=True, cap_end=True)


def new_object(name, mesh_name, bm):
    mesh = bpy.data.meshes.new(mesh_name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def activate(obj):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_all_modifiers(obj):
    activate(obj)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


# ------------------------------------------------------------------ 骨架：躯干+四肢+脚趾+尾巴

## 关节名 -> (位置, 皮肤半径 rx, ry, 是否皮肤根)；R 结尾的关节会自动镜像出 L
## v009-r2（第二轮返工）：判读指出"胸腔不够深/背腹线不连续/髋方正/前腿无肘腕/后腿折角像折纸/
## 尾巴几乎不收束/脖子过粗"→ 增加 spine 中间关节、加深胸腔、收腰收髋、前腿做出关节起伏、
## 后肢跗关节前移、尾巴全段连续收束、颈部收细。
SKELETON = {
    "pelvis":    ((0.000, -0.152, 0.238), 0.049, 0.055, True),
    "hipjoint":  ((0.000, -0.108, 0.244), 0.044, 0.050, False),
    "lumbar":    ((0.000, -0.048, 0.246), 0.038, 0.043, False),
    "midback":   ((0.000, 0.020, 0.242), 0.046, 0.055, False),
    "withers":   ((0.000, 0.080, 0.238), 0.053, 0.063, False),
    "chest":     ((0.000, 0.136, 0.242), 0.048, 0.060, False),
    "neck_base": ((0.000, 0.176, 0.254), 0.034, 0.038, False),
    "neck_end":  ((0.000, 0.214, 0.270), 0.028, 0.032, False),

    # 前肢：肩(粗) → 上臂(收) → 肘(略鼓) → 前臂(收) → 腕(细) → 掌 → 趾部
    "scapulaR":  ((0.040, 0.102, 0.236), 0.034, 0.033, False),
    "upperarmR": ((0.044, 0.096, 0.196), 0.026, 0.026, False),
    "elbowR":    ((0.046, 0.086, 0.156), 0.0235, 0.0235, False),
    "forearmR":  ((0.047, 0.100, 0.110), 0.0190, 0.0190, False),
    "wristR":    ((0.048, 0.114, 0.056), 0.0140, 0.0140, False),
    "pawR":      ((0.048, 0.124, 0.022), 0.0165, 0.0145, False),
    "pasternR":  ((0.048, 0.142, 0.014), 0.0125, 0.0115, False),
    "pawtipR":   ((0.048, 0.158, 0.011), 0.0120, 0.0105, False),

    # 后肢：髋(粗) → 大腿(最粗) → 膝(鼓) → 小腿(收) → 跗(转折) → 跖 → 掌 → 趾部
    "hipR":      ((0.044, -0.116, 0.228), 0.038, 0.042, False),
    "thighR":    ((0.048, -0.100, 0.196), 0.032, 0.034, False),
    "stifleR":   ((0.050, -0.078, 0.158), 0.026, 0.026, False),
    "shankR":    ((0.050, -0.108, 0.120), 0.0205, 0.0205, False),
    "hockR":     ((0.051, -0.132, 0.082), 0.0155, 0.0155, False),
    "archR":     ((0.052, -0.120, 0.036), 0.0135, 0.0135, False),
    "hpawR":     ((0.052, -0.112, 0.020), 0.0160, 0.0140, False),
    "hpasternR": ((0.052, -0.098, 0.014), 0.0120, 0.0110, False),
    "hpawtipR":  ((0.052, -0.082, 0.011), 0.0115, 0.0100, False),

    # 尾巴：尾根粗（埋进臀部）→ 全程连续收束，不是"到尖端才变细"
    "tail0":     ((0.000, -0.160, 0.240), 0.0225, 0.0225, False),
    "tail1":     ((0.000, -0.198, 0.248), 0.0175, 0.0175, False),
    "tail2":     ((0.000, -0.226, 0.264), 0.0145, 0.0145, False),
    "tail3":     ((0.000, -0.248, 0.290), 0.0115, 0.0115, False),
    "tail4":     ((0.000, -0.260, 0.320), 0.0092, 0.0092, False),
    "tail5":     ((0.000, -0.262, 0.352), 0.0072, 0.0072, False),
    "tail6":     ((0.000, -0.256, 0.380), 0.0054, 0.0054, False),
    "tail7":     ((0.000, -0.246, 0.402), 0.0036, 0.0036, False),
}

SKELETON_EDGES = [
    ("pelvis", "hipjoint"), ("hipjoint", "lumbar"), ("lumbar", "midback"),
    ("midback", "withers"), ("withers", "chest"),
    ("chest", "neck_base"), ("neck_base", "neck_end"),
    ("chest", "scapulaR"), ("scapulaR", "upperarmR"), ("upperarmR", "elbowR"),
    ("elbowR", "forearmR"), ("forearmR", "wristR"),
    ("wristR", "pawR"), ("pawR", "pasternR"), ("pasternR", "pawtipR"),
    ("pelvis", "hipR"), ("hipR", "thighR"), ("thighR", "stifleR"),
    ("stifleR", "shankR"), ("shankR", "hockR"),
    ("hockR", "archR"), ("archR", "hpawR"), ("hpawR", "hpasternR"),
    ("hpasternR", "hpawtipR"),
    ("pelvis", "tail0"), ("tail0", "tail1"), ("tail1", "tail2"), ("tail2", "tail3"),
    ("tail3", "tail4"), ("tail4", "tail5"), ("tail5", "tail6"), ("tail6", "tail7"),
]


def mirrored(name):
    """右→左。约定：肩/肘/腕/掌/髋/膝/跗等以 R 结尾；脚趾以 toeR/htoeR 前缀。"""
    if name.endswith("R"):
        return name[:-1] + "L"
    if name.startswith("htoeR"):
        return "htoeL" + name[5:]
    if name.startswith("toeR"):
        return "toeL" + name[4:]
    return name


def build_skeleton_mesh():
    bm = bmesh.new()
    order = []          # [(name, rx, ry, root), ...] 与 bmesh.verts 顺序一一对应
    for name, (co, rx, ry, root) in SKELETON.items():
        bm.verts.new(Vector(co))
        order.append((name, rx, ry, root))
        if mirrored(name) != name:
            bm.verts.new(Vector((-co[0], co[1], co[2])))
            order.append((mirrored(name), rx, ry, root))
    bm.verts.ensure_lookup_table()
    idx = {n: i for i, (n, _rx, _ry, _root) in enumerate(order)}
    for a, b in SKELETON_EDGES:
        bm.edges.new((bm.verts[idx[a]], bm.verts[idx[b]]))
        if a.endswith("R") or b.endswith("R"):
            bm.edges.new((bm.verts[idx[mirrored(a)]], bm.verts[idx[mirrored(b)]]))
    mesh = bpy.data.meshes.new("CAT_BODY_001_SKELETON")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("CAT_BODY_001_BODY", mesh)
    bpy.context.scene.collection.objects.link(obj)
    log("skeleton|joints=%d|edges=%d" % (len(order), len(mesh.edges)))
    return obj, order


def apply_skin(obj, order, subsurf_levels=1):
    activate(obj)
    mod = obj.modifiers.new("Skin", "SKIN")
    mod.use_smooth_shade = True
    sv = obj.data.skin_vertices[0].data
    for i, (_name, rx, ry, root) in enumerate(order):
        sv[i].radius = (rx, ry)
        sv[i].use_root = bool(root)
    log("skin|radii_set=%d|subsurf=%d" % (len(order), subsurf_levels))
    sub = obj.modifiers.new("Subdivision", "SUBSURF")
    sub.levels = subsurf_levels
    sub.render_levels = subsurf_levels
    apply_all_modifiers(obj)
    log("skin|applied|verts=%d|tris=%d" % (len(obj.data.vertices), tri_count(obj)))
    return obj


def relax_mesh(obj, iterations=2, factor=0.4):
    """Skin+细分会在肢体上留下横向"环状台阶"（判读把它读成条纹）。
    这里用 bmesh 平滑把环状起伏压平——**不是** remesh，不改拓扑、不抽面。"""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for _ in range(iterations):
        bmesh.ops.smooth_vert(bm, verts=bm.verts[:], factor=factor,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    log("relax|iterations=%d|factor=%.2f" % (iterations, factor))


def anatomy_pass(obj):
    """干净拓扑上的**宽高斯**解剖塑形（全低频，不产生条纹/台阶）。"""
    bumps = [
        ((0.0, 0.105, 0.176), 0.065, 0.012),      # 前胸/胸骨下缘
        ((0.0, 0.010, 0.192), 0.060, -0.008),     # 腹部上收（腹线）
        ((0.0, -0.100, 0.230), 0.055, -0.005),    # 臀部下方收
        ((0.046, 0.100, 0.272), 0.032, 0.007),    # 肩胛（右）
        ((-0.046, 0.100, 0.272), 0.032, 0.007),
        ((0.048, -0.105, 0.215), 0.042, 0.009),   # 大腿肌群（右）
        ((-0.048, -0.105, 0.215), 0.042, 0.009),
        ((0.0, -0.030, 0.292), 0.045, -0.004),    # 背部微凹（脊柱走向）
        ((0.0, 0.165, 0.286), 0.038, -0.004),     # 颈背下凹（分出颈部）
    ]
    # 脚掌趾部：3 个趾垫 + 2 道趾缝（四只脚）
    for sign in (-1.0, 1.0):
        for (px, py) in ((0.048 * sign, 0.150), (0.052 * sign, -0.090)):
            for dx in (-0.0105, 0.0, 0.0105):
                bumps.append(((px + dx, py, 0.010), 0.0090, 0.0080))
            for dx in (-0.0052, 0.0052):
                bumps.append(((px + dx, py + 0.004, 0.012), 0.0042, -0.0038))
    mesh = obj.data
    normals = [v.normal.copy() for v in mesh.vertices]
    for v, nrm in zip(mesh.vertices, normals):
        d = 0.0
        for c, sigma, amp in bumps:
            dv = v.co - Vector(c) if not isinstance(c, Vector) else v.co - c
            d += amp * math.exp(-dv.length_squared / (2.0 * sigma * sigma))
        if abs(d) > 1e-9:
            v.co = v.co + nrm * d
    mesh.update()
    log("anatomy|bumps=%d" % len(bumps))
    return obj


# ------------------------------------------------------------------ 头部 / 眼睑 / 耳 / 鼻

HEAD_RINGS = [
    (0.186, 0.258, 0.030, 0.032),
    (0.204, 0.264, 0.040, 0.042),
    (0.222, 0.270, 0.048, 0.048),
    (0.240, 0.276, 0.054, 0.051),
    (0.256, 0.278, 0.0565, 0.0525),
    (0.270, 0.276, 0.0560, 0.0520),
    (0.282, 0.272, 0.0515, 0.0475),
    (0.292, 0.268, 0.0450, 0.0405),
    (0.302, 0.265, 0.0370, 0.0330),
    (0.311, 0.264, 0.0310, 0.0285),
    (0.318, 0.264, 0.0255, 0.0240),
    (0.324, 0.265, 0.0185, 0.0185),
]


def head_modulate(idx, t, a, cs, sn):
    mw, mh = 1.0, 1.0
    if 0.30 < t < 0.62:
        cheek = math.exp(-((t - 0.46) ** 2) / (2 * 0.055 ** 2))
        mw += 0.16 * cheek * max(0.0, -sn)
    if t > 0.55:
        pad = math.exp(-((t - 0.74) ** 2) / (2 * 0.07 ** 2))
        below = max(0.0, -sn) ** 1.5
        mw += 0.20 * pad * below
        mh += 0.10 * pad * below
    if t < 0.45 and sn > 0.35:
        mh -= 0.05 * (sn - 0.35)
    if t > 0.72 and sn < -0.6:
        mh += 0.05
    return mw, mh


def build_head():
    bm = bmesh.new()
    stations = []
    for (y, cz, rw, rh) in HEAD_RINGS:
        stations.append((Vector((0.0, y, cz)), Vector((1.0, 0.0, 0.0)),
                         Vector((0.0, 0.0, 1.0)), rw, rh))
    add_loft(bm, stations, n=RING_SEG, modulate=head_modulate)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    obj = new_object("CAT_BODY_001_HEAD", "CAT_Body_001_HeadMesh", bm)
    log("head|rings=%d|seg=%d" % (len(HEAD_RINGS), RING_SEG))
    return obj


def build_details_bmesh():
    """眼球 / 上下眼睑 / 鼻头 / 耳内。深色材质槽；眼睛不再是空洞。"""
    bm = bmesh.new()
    for sign in (-1.0, 1.0):
        eye_c = Vector((sign * EYE_POS[0], EYE_POS[1], EYE_POS[2]))
        add_quad_sphere(bm, eye_c, EYE_R, EYE_R * 0.96, EYE_R, n=16, rings=10)
        # 上下眼睑环
        n_dir = Vector((sign * 0.60, 0.78, 0.14)).normalized()
        t1 = Vector((0.0, 0.0, 1.0)) - n_dir * n_dir.z
        t1.normalize()
        t2 = n_dir.cross(t1).normalized()
        for span, tilt in ((118.0, 12.0), (96.0, -14.0)):
            pts, radii = [], []
            steps = 11
            for i in range(steps):
                frac = float(i) / (steps - 1)
                ang = math.radians(-span * 0.5 + span * frac + tilt)
                r = EYE_R * 1.14
                pts.append(eye_c + (t1 * math.cos(ang) + t2 * math.sin(ang)) * r
                           + n_dir * (EYE_R * 0.12))
                f = 1.0 - abs(2.0 * frac - 1.0) ** 1.4
                rt = 0.0016 + 0.0024 * f
                radii.append((rt, rt))
            add_tube_along(bm, pts, radii, n=8)
    # 鼻头（倒三角感的扁楔）+ 人中起始
    add_quad_sphere(bm, NOSE_POS, 0.0115, 0.0072, 0.0068, n=14, rings=8)
    add_quad_sphere(bm, (0.0, NOSE_POS[1] - 0.0035, NOSE_POS[2] - 0.0060),
                    0.0052, 0.0048, 0.0042, n=10, rings=6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    log("details|verts=%d|faces=%d" % (len(bm.verts), len(bm.faces)))
    return bm


def build_ear(sign):
    """耳壳：外/内两张曲面 + 边缘厚度，内耳深色。"""
    bm = bmesh.new()
    base = Vector((sign * EAR_BASE[0], EAR_BASE[1], EAR_BASE[2]))
    tip = Vector((sign * EAR_TIP[0], EAR_TIP[1], EAR_TIP[2]))
    u = (tip - base).normalized()
    th = Vector((1.0, 0.0, 0.0)) - u * u.x
    th.normalize()                     # 厚度方向（朝外）
    w = th.cross(u).normalized()       # 耳宽方向（前后）
    rows, cols = 9, 9
    outer, inner = [], []
    for r in range(rows):
        fr = float(r) / (rows - 1)
        center = base.lerp(tip, fr) + w * (-0.006 * fr * fr)
        half_w = 0.039 * (1.0 - fr) ** 0.8 + 0.0030
        thick = 0.0095 * (1.0 - fr) ** 0.65 + 0.0016
        ro, ri = [], []
        for cidx in range(cols):
            fc = float(cidx) / (cols - 1) * 2.0 - 1.0
            # 截面是"扁弧"：中间比边缘薄（内耳凹陷）
            bulge = math.sqrt(max(0.0, 1.0 - fc * fc))
            inner_dip = 0.78 * bulge
            p = center + w * (fc * half_w)
            ro.append(bm.verts.new(p + th * (thick * bulge)))
            ri.append(bm.verts.new(p - th * (thick * bulge * inner_dip)))
        outer.append(ro)
        inner.append(ri)
    for r in range(rows - 1):
        for cidx in range(cols - 1):
            bm.faces.new((outer[r][cidx], outer[r][cidx + 1],
                          outer[r + 1][cidx + 1], outer[r + 1][cidx]))
            bm.faces.new((inner[r][cidx + 1], inner[r][cidx],
                          inner[r + 1][cidx], inner[r + 1][cidx + 1]))
    # 边缘缝合（左右两侧 + 底面）
    for r in range(rows - 1):
        bm.faces.new((outer[r][0], inner[r][0], inner[r + 1][0], outer[r + 1][0]))
        bm.faces.new((inner[r][cols - 1], outer[r][cols - 1],
                      outer[r + 1][cols - 1], inner[r + 1][cols - 1]))
    for cidx in range(cols - 1):
        bm.faces.new((inner[0][cidx], outer[0][cidx], outer[0][cidx + 1], inner[0][cidx + 1]))
    # 顶端封口（否则顶部留一圈开口边 → 非流形）
    for cidx in range(cols - 1):
        bm.faces.new((outer[rows - 1][cidx], inner[rows - 1][cidx],
                      inner[rows - 1][cidx + 1], outer[rows - 1][cidx + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    obj = new_object("CAT_BODY_001_EAR_%s" % ("R" if sign > 0 else "L"),
                     "CAT_Body_001_EarMesh_%s" % ("R" if sign > 0 else "L"), bm)
    return obj


# ------------------------------------------------------------------ 材质 / UV / 烘焙

def build_materials():
    fur = bpy.data.materials.new(MAT_FUR)
    fur.use_nodes = True
    nt = fur.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:
        fatal("no_principled_bsdf")
    bsdf.inputs["Roughness"].default_value = 0.80
    if "Specular" in bsdf.inputs:
        bsdf.inputs["Specular"].default_value = 0.18

    coord = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Object"], sep.inputs["Vector"])

    zramp = nodes.new("ShaderNodeValToRGB")
    zramp.color_ramp.elements[0].position = 0.115
    zramp.color_ramp.elements[0].color = COL_BELLY
    zramp.color_ramp.elements[1].position = 0.300
    zramp.color_ramp.elements[1].color = COL_MID
    links.new(sep.outputs["Z"], zramp.inputs["Fac"])
    zramp2 = nodes.new("ShaderNodeValToRGB")
    zramp2.color_ramp.elements[0].position = 0.255
    zramp2.color_ramp.elements[0].color = COL_MID
    zramp2.color_ramp.elements[1].position = 0.340
    zramp2.color_ramp.elements[1].color = COL_BACK
    links.new(sep.outputs["Z"], zramp2.inputs["Fac"])
    back_mix = nodes.new("ShaderNodeMixRGB")
    back_mix.blend_type = "MIX"
    links.new(zramp.outputs["Color"], back_mix.inputs[1])
    links.new(zramp2.outputs["Color"], back_mix.inputs[2])
    links.new(zramp2.outputs["Color"], back_mix.inputs["Fac"])

    ymul = nodes.new("ShaderNodeMath")
    ymul.operation = "MULTIPLY"
    ymul.inputs[1].default_value = 58.0
    links.new(sep.outputs["Y"], ymul.inputs[0])
    sine = nodes.new("ShaderNodeMath")
    sine.operation = "SINE"
    links.new(ymul.outputs[0], sine.inputs[0])
    sramp = nodes.new("ShaderNodeValToRGB")
    sramp.color_ramp.interpolation = "EASE"
    sramp.color_ramp.elements[0].position = 0.42
    sramp.color_ramp.elements[0].color = (1.0, 1.0, 1.0, 1.0)
    sramp.color_ramp.elements[1].position = 0.80
    sramp.color_ramp.elements[1].color = (0.0, 0.0, 0.0, 1.0)
    links.new(sine.outputs[0], sramp.inputs["Fac"])
    sfac = nodes.new("ShaderNodeMath")
    sfac.operation = "MULTIPLY"
    sfac.inputs[1].default_value = 0.28
    links.new(sramp.outputs["Color"], sfac.inputs[0])
    smix = nodes.new("ShaderNodeMixRGB")
    smix.blend_type = "MIX"
    links.new(back_mix.outputs["Color"], smix.inputs[1])
    smix.inputs[2].default_value = COL_STRIPE
    links.new(sfac.outputs[0], smix.inputs["Fac"])

    yramp = nodes.new("ShaderNodeValToRGB")
    yramp.color_ramp.elements[0].position = 0.296
    yramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    yramp.color_ramp.elements[1].position = 0.322
    yramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    links.new(sep.outputs["Y"], yramp.inputs["Fac"])
    mmix = nodes.new("ShaderNodeMixRGB")
    mmix.blend_type = "MIX"
    links.new(smix.outputs["Color"], mmix.inputs[1])
    mmix.inputs[2].default_value = COL_MUZZLE
    links.new(yramp.outputs["Color"], mmix.inputs["Fac"])

    eramp = nodes.new("ShaderNodeValToRGB")
    eramp.color_ramp.elements[0].position = 0.320
    eramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    eramp.color_ramp.elements[1].position = 0.372
    eramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    links.new(sep.outputs["Z"], eramp.inputs["Fac"])
    emix = nodes.new("ShaderNodeMixRGB")
    emix.blend_type = "MIX"
    links.new(mmix.outputs["Color"], emix.inputs[1])
    emix.inputs[2].default_value = COL_EARTIP
    links.new(eramp.outputs["Color"], emix.inputs["Fac"])

    img = bpy.data.images.new("CAT_BODY_001_BaseColor_v009", TEX_SIZE, TEX_SIZE, alpha=False)
    img.colorspace_settings.name = "sRGB"
    tex_fur = nodes.new("ShaderNodeTexImage")
    tex_fur.image = img
    nt.nodes.active = tex_fur
    links.new(emix.outputs["Color"], bsdf.inputs["Base Color"])
    fur.use_backface_culling = True

    # 细节材质：用"距眼心距离"画虹膜/瞳孔，不额外占材质槽
    detail = bpy.data.materials.new(MAT_DETAIL)
    detail.use_nodes = True
    dnt = detail.node_tree
    dn, dl = dnt.nodes, dnt.links
    dbsdf = dn.get("Principled BSDF")
    dbsdf.inputs["Roughness"].default_value = 0.30
    if "Specular" in dbsdf.inputs:
        dbsdf.inputs["Specular"].default_value = 0.6
    dcoord = dn.new("ShaderNodeTexCoord")

    def dist_to(target):
        sub = dn.new("ShaderNodeVectorMath")
        sub.operation = "SUBTRACT"
        sub.inputs[1].default_value = Vector(target)
        dl.new(dcoord.outputs["Object"], sub.inputs[0])
        ln = dn.new("ShaderNodeVectorMath")
        ln.operation = "LENGTH"
        dl.new(sub.outputs["Vector"], ln.inputs[0])
        return ln.outputs["Value"]

    d1 = dist_to((EYE_POS[0], EYE_POS[1], EYE_POS[2]))
    d2 = dist_to((-EYE_POS[0], EYE_POS[1], EYE_POS[2]))
    dmin = dn.new("ShaderNodeMath")
    dmin.operation = "MINIMUM"
    dl.new(d1, dmin.inputs[0])
    dl.new(d2, dmin.inputs[1])
    eye_ramp = dn.new("ShaderNodeValToRGB")
    eye_ramp.color_ramp.interpolation = "EASE"
    edges = [(0.0, (0.004, 0.004, 0.005, 1.0)),
             (0.0050, (0.004, 0.004, 0.005, 1.0)),
             (0.0062, (0.470, 0.265, 0.035, 1.0)),
             (0.0088, (0.150, 0.085, 0.022, 1.0)),
             (0.0104, (0.022, 0.017, 0.014, 1.0)),
             (0.0600, (0.022, 0.017, 0.014, 1.0))]
    eye_ramp.color_ramp.elements[0].position = edges[0][0]
    eye_ramp.color_ramp.elements[0].color = edges[0][1]
    eye_ramp.color_ramp.elements[1].position = edges[-1][0]
    eye_ramp.color_ramp.elements[1].color = edges[-1][1]
    for pos, col in edges[1:-1]:
        e = eye_ramp.color_ramp.elements.new(pos)
        e.color = col
    dl.new(dmin.outputs[0], eye_ramp.inputs["Fac"])
    dnose = dist_to(NOSE_POS)
    nramp = dn.new("ShaderNodeValToRGB")
    nramp.color_ramp.elements[0].position = 0.000
    nramp.color_ramp.elements[0].color = (0.235, 0.110, 0.105, 1.0)
    nramp.color_ramp.elements[1].position = 0.0105
    nramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    dl.new(dnose, nramp.inputs["Fac"])
    dmix = dn.new("ShaderNodeMixRGB")
    dmix.blend_type = "MIX"
    dmix.inputs[1].default_value = (0.022, 0.017, 0.014, 1.0)
    dl.new(eye_ramp.outputs["Color"], dmix.inputs[2])
    dl.new(nramp.outputs["Color"], dmix.inputs["Fac"])
    tex_det = dn.new("ShaderNodeTexImage")
    tex_det.image = img
    dnt.nodes.active = tex_det
    dl.new(dmix.outputs["Color"], dbsdf.inputs["Base Color"])
    detail.use_backface_culling = True

    log("material|%s|roughness=0.80|textured=True" % MAT_FUR)
    log("material|%s|iris_by_distance=True|roughness=0.30" % MAT_DETAIL)
    return {MAT_FUR: fur, MAT_DETAIL: detail}, img, [tex_fur, tex_det]


def setup_uv(obj):
    activate(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    log("uv|layers=%d" % len(obj.data.uv_layers))
    require(len(obj.data.uv_layers) >= 1, "uv_missing")


def bake_albedo(obj, nodes_list, png_path):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 6
    scene.render.bake.margin = 8
    scene.render.bake.use_clear = True
    img = nodes_list[0].image
    for mat_name in (MAT_FUR, MAT_DETAIL):
        m = bpy.data.materials.get(mat_name)
        for nd in nodes_list:
            if nd.id_data == m.node_tree:
                m.node_tree.nodes.active = nd
    activate(obj)
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True)
    img.filepath_raw = png_path
    img.file_format = "PNG"
    img.save()
    log("bake|diffuse=OK|size=%dx%d|png=%s" % (img.size[0], img.size[1], png_path))
    for mat_name in (MAT_FUR, MAT_DETAIL):
        m = bpy.data.materials.get(mat_name)
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        for nd in nodes_list:
            if nd.id_data != m.node_tree:
                continue
            for l in list(m.node_tree.links):
                if l.to_socket == bsdf.inputs["Base Color"]:
                    m.node_tree.links.remove(l)
            m.node_tree.links.new(nd.outputs["Color"], bsdf.inputs["Base Color"])
    log("bake|linked=True")


def export_glb(glb_out):
    rna = bpy.ops.export_scene.gltf.get_rna_type()
    props = set(rna.properties.keys())
    wanted = {
        "export_format": "GLB", "use_selection": False, "export_apply": True,
        "export_yup": True, "export_materials": "EXPORT", "export_cameras": False,
        "export_lights": False, "export_extras": False, "export_texcoords": True,
        "export_normals": True, "export_colors": False, "export_skins": False,
        "export_animations": False,
    }
    applied = {k: v for k, v in wanted.items() if k in props}
    log("gltf_export|unsupported=%s" % (",".join(sorted(k for k in wanted if k not in props)) or "none"))
    bpy.ops.export_scene.gltf(filepath=glb_out, **applied)
    if not os.path.isfile(glb_out):
        fatal("glb_not_written|%s" % glb_out)
    with open(glb_out, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (glb_out, len(data), hashlib.sha256(data).hexdigest()))


# ------------------------------------------------------------------ 渲染（机位/灯光与 V008 完全一致，便于同角度对比）

def setup_render_scene():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.film_transparent = False
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
    add_light("RIM", (0.0, -0.95, 0.70), 70.0, 0.6,
              (math.radians(115.0), 0.0, 0.0))
    cam_data = bpy.data.cameras.new("CAM")
    cam_data.lens = 60.0
    cam = bpy.data.objects.new("CAM", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    log("render|engine=%s|samples=%d" % (scene.render.engine, scene.cycles.samples))
    return cam


def point_camera(cam, location, target):
    cam.location = Vector(location)
    cam.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()


def render_views(obj, tag):
    scene = bpy.context.scene
    cam = scene.camera
    target = Vector((0.0, 0.02, 0.21))
    views = [
        ("front", (0.0, 0.95, 0.30)),
        ("side", (0.95, 0.02, 0.28)),
        ("back", (0.0, -0.95, 0.30)),
        ("corner45", (0.72, 0.72, 0.42)),
        ("top", (0.0, 0.06, 1.05)),
        ("face", (0.09, 0.50, 0.32)),
    ]
    for name, loc in views:
        aim = Vector((0.0, 0.29, 0.295)) if name == "face" else target
        point_camera(cam, loc, aim)
        scene.render.filepath = "%s/art02_v009_%s.png" % (RENDER_DIR, name)
        bpy.ops.render.render(write_still=True)
        log("render|view=%s" % name)


def render_sheet(obj, tag):
    scene = bpy.context.scene
    src = obj.copy()
    src.data = obj.data.copy()
    scene.collection.objects.link(src)
    clones = []
    for i, ang in enumerate([0.0, 95.0, 180.0, 235.0]):
        c = src if i == 0 else src.copy()
        if i != 0:
            c.data = src.data
            scene.collection.objects.link(c)
        c.rotation_euler = (0.0, 0.0, math.radians(ang))
        c.location = Vector(((i - 1.5) * 0.70, 0.0, 0.0))
        clones.append(c)
    obj.hide_render = True
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 620
    scene.camera.data.lens = 35.0
    point_camera(scene.camera, (0.0, 2.70, 0.50), Vector((0.0, 0.0, 0.20)))
    scene.render.filepath = "%s/art02_v009_sheet.png" % RENDER_DIR
    bpy.ops.render.render(write_still=True)
    log("render|view=sheet")
    obj.hide_render = False
    for c in clones:
        bpy.data.objects.remove(c, do_unlink=True)
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.camera.data.lens = 60.0


def render_wireframe(obj, tag):
    scene = bpy.context.scene
    wf = obj.copy()
    wf.data = obj.data.copy()
    scene.collection.objects.link(wf)
    m = wf.modifiers.new("Wire", "WIREFRAME")
    m.thickness = 0.0012
    m.use_replace = True
    activate(wf)
    bpy.ops.object.modifier_apply(modifier=m.name)
    wmat = bpy.data.materials.new("MAT_Wire")
    wmat.use_nodes = True
    wmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.02, 0.02, 1.0)
    wmat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.4
    wf.data.materials.clear()
    wf.data.materials.append(wmat)
    obj.hide_render = True
    point_camera(scene.camera, (0.80, 0.82, 0.45), Vector((0.0, 0.02, 0.21)))
    scene.render.filepath = "%s/art02_v009_wire.png" % RENDER_DIR
    bpy.ops.render.render(write_still=True)
    log("render|view=wire")
    obj.hide_render = False
    bpy.data.objects.remove(wf, do_unlink=True)


# ------------------------------------------------------------------ 自检

def mesh_stats(obj, mat_index):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    faces = [f for f in bm.faces if f.material_index == mat_index]
    seen, islands = set(), 0
    for f in faces:
        if f.index in seen:
            continue
        islands += 1
        stack = [f]
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen and nf.material_index == mat_index:
                        seen.add(nf.index)
                        stack.append(nf)
    non_manifold = sum(1 for e in bm.edges if not e.is_manifold)
    quads = sum(1 for f in bm.faces if len(f.verts) == 4)
    total = len(bm.faces)
    bm.free()
    return islands, non_manifold, quads, total


def cleanup_mesh(obj, tag):
    """焊接重合点 + 统一法线（Skin 修改器在分叉处会留下未焊接的顶点）。"""
    activate(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=1e-4)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    log_islands(obj, "%s|after_cleanup" % tag)


def island_report(obj):
    """逐壳打印 bbox，便于定位多出来的壳。"""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    seen = set()
    groups = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, group = [f], []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            group.append(cur)
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        vs = {v for f2 in group for v in f2.verts}
        mn = Vector((min(v.co.x for v in vs), min(v.co.y for v in vs), min(v.co.z for v in vs)))
        mx = Vector((max(v.co.x for v in vs), max(v.co.y for v in vs), max(v.co.z for v in vs)))
        groups.append((len(group), mn, mx))
    bm.free()
    for i, (n, mn, mx) in enumerate(groups):
        log("island|%d|faces=%d|min=%s|max=%s" % (i, n, vec_str(mn), vec_str(mx)))


def snap_to_ground(obj):
    """把最低点对齐到 z=0（平滑/塑形会让脚底略微偏移）。"""
    mn = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    for v in obj.data.vertices:
        v.co.z -= mn
    obj.data.update()
    log("ground|shift=%.6f" % (-mn))
    return obj


def log_islands(obj, tag):
    islands, non_manifold, quads, faces = mesh_stats(obj, 0)
    log("%s|verts=%d|faces=%d|islands=%d|non_manifold=%d" % (
        tag, len(obj.data.vertices), faces, islands, non_manifold))


def self_check(obj, tag):
    obj.data.calc_loop_triangles()
    tris = len(obj.data.loop_triangles)
    coords = [obj.matrix_world @ v.co for v in obj.data.vertices]
    mn = Vector((min(c.x for c in coords), min(c.y for c in coords), min(c.z for c in coords)))
    mx = Vector((max(c.x for c in coords), max(c.y for c in coords), max(c.z for c in coords)))
    fur_islands, non_manifold, quads, faces = mesh_stats(obj, 0)
    log("%s|verts=%d|tris=%d|faces=%d|quads=%d(%.1f%%)|slots=%d" % (
        tag, len(obj.data.vertices), tris, faces, quads, 100.0 * quads / max(1, faces),
        len(obj.data.materials)))
    log("%s|aabb_min=%s|aabb_max=%s|fur_islands=%d|non_manifold=%d" % (
        tag, vec_str(mn), vec_str(mx), fur_islands, non_manifold))
    log("%s|height=%.4f|length=%.4f|width=%.4f" % (tag, mx.z - mn.z, mx.y - mn.y, mx.x - mn.x))
    log("%s|pipeline=skin+subsurf+loft|remesh=False|decimate=False|noise_displace=False" % tag)

    require(tris <= TRI_BUDGET, "%s|tri_budget|%d>%d" % (tag, tris, TRI_BUDGET))
    require(tris >= 3000, "%s|too_few_tris|%d" % (tag, tris))
    require(len(obj.data.materials) <= 2, "%s|slot_over|%d" % (tag, len(obj.data.materials)))
    require(abs(mn.z) < 0.006, "%s|not_grounded|%.4f" % (tag, mn.z))
    require(mx.z <= Z_LIMIT, "%s|too_tall|%.4f" % (tag, mx.z))
    require(max(abs(mn.x), abs(mx.x)) <= X_LIMIT, "%s|too_wide|%.4f" % (tag, max(abs(mn.x), abs(mx.x))))
    require(abs(mn.x + mx.x) < 0.012, "%s|not_symmetric|[%.4f,%.4f]" % (tag, mn.x, mx.x))
    require(non_manifold == 0, "%s|non_manifold|%d" % (tag, non_manifold))
    require(fur_islands == 4, "%s|fur_islands|%d(expect 4: body+head+2ears)" % (tag, fur_islands))
    require(len(obj.modifiers) == 0, "%s|modifiers_left|%d" % (tag, len(obj.modifiers)))
    return tris


# ------------------------------------------------------------------ main

def main():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    version = "v009"
    stage = "all"
    i = 0
    while i < len(args):
        if args[i] == "--version":
            version = args[i + 1]
            i += 2
        elif args[i] == "--stage":
            stage = args[i + 1]
            i += 2
        else:
            i += 1
    log("start|blender=%s|python=%s|version=%s|stage=%s" % (
        bpy.app.version_string, sys.version.split()[0], version, stage))

    blend_out = "%s/CAT_BODY_001_%s.blend" % (BLEND_DIR, version)
    glb_stage = "%s/SM_Cat_001_v009.glb" % STAGE_DIR
    png_stage = "%s/CAT_BODY_001_BaseColor_v009.png" % STAGE_DIR
    for d in (BLEND_DIR, STAGE_DIR, RENDER_DIR):
        if not os.path.isdir(d):
            os.makedirs(d)
            log("mkdir|%s" % d)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0

    mats, img, tex_nodes = build_materials()

    body, order = build_skeleton_mesh()
    body.data.materials.append(mats[MAT_FUR])
    body.data.materials.append(mats[MAT_DETAIL])
    apply_skin(body, order, subsurf_levels=1)
    cleanup_mesh(body, "body")
    relax_mesh(body, iterations=6, factor=0.5)
    log_islands(body, "body")
    anatomy_pass(body)
    log_islands(body, "body")
    for poly in body.data.polygons:
        poly.use_smooth = True
        poly.material_index = 0

    head = build_head()
    head.data.materials.append(mats[MAT_FUR])
    head.data.materials.append(mats[MAT_DETAIL])
    for poly in head.data.polygons:
        poly.use_smooth = True
        poly.material_index = 0

    ears = []
    for sign in (1.0, -1.0):
        ear = build_ear(sign)
        ear.data.materials.append(mats[MAT_FUR])
        ear.data.materials.append(mats[MAT_DETAIL])
        for poly in ear.data.polygons:
            poly.use_smooth = True
            poly.material_index = 0
        log_islands(ear, "ear|%s" % ("R" if sign > 0 else "L"))
        ears.append(ear)

    details = new_object("CAT_BODY_001_DETAIL", "CAT_Body_001_DetailMesh", build_details_bmesh())
    details.data.materials.append(mats[MAT_FUR])
    details.data.materials.append(mats[MAT_DETAIL])
    for poly in details.data.polygons:
        poly.use_smooth = True
        poly.material_index = 1

    activate(body)
    for o in [head] + ears + [details]:
        o.select_set(True)
    bpy.ops.object.join()
    body.name = ASSET_NAME
    activate(body)
    snap_to_ground(body)
    self_check(body, "built")

    if stage in ("mesh", "shot"):
        bpy.ops.wm.save_as_mainfile(filepath=blend_out)
        log("blend|path=%s|bytes=%d" % (blend_out, os.path.getsize(blend_out)))
    if stage == "shot":
        setup_render_scene()
        render_views(body, version)
        render_sheet(body, version)
        render_wireframe(body, version)
    if stage == "shot":
        log("done|stage=shot|failures=%d" % len(failures))
        sys.exit(0 if not failures else 1)
    if stage == "mesh":
        log("done|stage=mesh|failures=%d" % len(failures))
        sys.exit(0 if not failures else 1)

    setup_uv(body)
    bake_albedo(body, tex_nodes, png_stage)
    bpy.ops.wm.save_as_mainfile(filepath=blend_out)
    log("blend|path=%s|bytes=%d" % (blend_out, os.path.getsize(blend_out)))
    setup_render_scene()
    render_views(body, version)
    render_sheet(body, version)
    render_wireframe(body, version)
    for ob in list(bpy.data.objects):
        if ob.type in {"LIGHT", "CAMERA"} or ob.name.startswith("RENDER_"):
            bpy.data.objects.remove(ob, do_unlink=True)
    export_glb(glb_stage)
    log("done|stage=all|failures=%d" % len(failures))
    sys.exit(0 if not failures else 1)


main()
