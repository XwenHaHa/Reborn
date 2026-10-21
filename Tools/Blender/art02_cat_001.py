# -*- coding: utf-8 -*-
"""ART02 试点资产：猫 CAT_BODY_001（Blender 3.3.1 无头 CLI）

为什么是这个资产（详见 Docs/Tasks/ART02.md）：
  整个游戏里**观感最差**的不是草丛（ART01 已换成真实草叶），而是猫与鼠 ——
  它们的"模型"至今只是 `AnimalBody/BodyMesh` 上的一个 **CapsuleMesh**
  （半径 0.16 / 高 0.48，纯色 albedo，无耳朵/四肢/尾巴/眼睛）。
  猫是鼠线的追捕者、也是猫线的玩家本体，出现频率与画面占比最高，
  所以选它做**唯一**试点（modeling2.md §三 只允许一个）。

几何思路（为什么不用几何体堆叠）：
  1) 骨架线 → 变截面放样（generalized cylinder）：躯干/颈/头/四肢/尾都是
     沿**解剖轴线**的连续截面，胸腔深、腰细、髋宽、腿部三段关节角度真实；
  2) 所有部件先做成**闭合流形**，再 Voxel Remesh 焊接成一个整体面 + 平滑，
     接缝不是"两个圆柱插在一起"，而是网格级的连续过渡；
  3) 网格级噪声位移给出毛发的形体起伏；颜色/斑纹/腹部浅色/耳尖深色
     由程序化材质**烘焙成一张 albedo 贴图**（不用外部贴图，确定性可复现）。

坐标约定（Docs/BlenderPipeline.md）：Blender 里面朝 **+Y**、**+Z** 向上、米制；
导出 glTF 后即 Godot 的"面朝 -Z"。原点在**四脚着地的地面中心**（min_z ≈ 0），
Godot 侧把视觉节点放到 y = -capsule_half_height 即可贴地。

契约（本脚本自检，失败即退出码 1）：
  - 三角形 ≤ 10000（BlenderPipeline 动物预算）、材质槽 ≤ 2
  - min_z ≈ 0（贴地）、max_z ≤ 0.48（= 猫胶囊总高，竖向不与碰撞矛盾）
  - |x| ≤ 0.16 + 0.02（胶囊半径 + 允许的体侧外扩）
  - 单一连通壳（remesh 后不许留孤岛）、非流形边 = 0
  - X 轴左右对称（|min_x + max_x| < 5 mm）

输出约定：stdout 全 ASCII，机器可读行 `PROBE|key=value`。

调用：
  & 'D:\\SoftWare\\Blender\\blender.exe' --background --factory-startup `
      --python 'E:\\Reborn\\Tools\\Blender\\art02_cat_001.py' -- --version v001 --stage all
"""

import hashlib
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

REPO = "E:/Reborn"
ASSET_NAME = "CAT_BODY_001"
MESH_NAME = "CAT_BODY_001_Mesh"
MAT_FUR = "MAT_Cat_Fur"
MAT_DETAIL = "MAT_Cat_Detail"

TRI_BUDGET = 10000
CAPSULE_RADIUS = 0.16
CAPSULE_HEIGHT = 0.48
X_LIMIT = CAPSULE_RADIUS + 0.02
Z_LIMIT = CAPSULE_HEIGHT
SYMMETRY_TOL = 0.005

# 毛发噪声位移：给"塑料光滑"的表面一点网格级起伏
DISPLACE_STRENGTH = 0.0032
DISPLACE_SCALE = 0.013

# 程序化配色（线性空间；Godot 侧是 sRGB 编码，见 BlenderPipeline.md）
COL_BACK = (0.062, 0.043, 0.026, 1.0)      # 背部深褐
COL_MID = (0.155, 0.098, 0.052, 1.0)       # 体侧黄褐
COL_BELLY = (0.430, 0.360, 0.290, 1.0)     # 腹部/胸口米白
COL_STRIPE = (0.035, 0.024, 0.015, 1.0)    # 虎斑暗纹
COL_MUZZLE = (0.520, 0.470, 0.420, 1.0)    # 口鼻浅色
COL_EARTIP = (0.028, 0.020, 0.014, 1.0)    # 耳尖深色
COL_DETAIL = (0.020, 0.016, 0.014, 1.0)    # 眼睛/鼻头

TEX_SIZE = 2048
RENDER_DIR = REPO + "/Art/Probes"

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


# ---------------------------------------------------------------- 几何工具

def catmull_rom(points, samples_per_seg=6):
    """把控制点串成平滑路径（首尾重复端点，保证过点）。"""
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


def frame_at(tangent, hint=Vector((1.0, 0.0, 0.0))):
    t = tangent.normalized()
    side = hint - t * hint.dot(t)
    if side.length < 1e-5:
        side = Vector((0.0, 1.0, 0.0)) - t * t.y
    side.normalize()
    up = side.cross(t)
    up.normalize()
    return side, up


def add_loft(bm, stations, n=20, cap_start=True, cap_end=True):
    """stations: [(center, side, up, rw, rh, exp), ...] —— 逐截面放样。"""
    rings = []
    for (c, side, up, rw, rh, e) in stations:
        ring = []
        for i in range(n):
            a = 2.0 * math.pi * float(i) / n
            cs, sn = math.cos(a), math.sin(a)
            # superellipse：e=1 椭圆，e<1 更方（用于胸腔/髋部的平侧面）
            u = math.copysign(abs(cs) ** e, cs) if cs != 0.0 else 0.0
            v = math.copysign(abs(sn) ** e, sn) if sn != 0.0 else 0.0
            ring.append(bm.verts.new(c + side * (u * rw) + up * (v * rh)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    if cap_start:
        bm.faces.new(list(rings[0]))
    if cap_end:
        bm.faces.new(list(rings[-1]))
    return rings


def add_tube(bm, path, radii, n=14, exp=1.0, scale_side=1.0, cap_start=True, cap_end=True):
    """沿路径的变半径管（四肢/尾）。radii: [(rw, rh), ...] 与 path 等长。"""
    stations = []
    for i, p in enumerate(path):
        if i == 0:
            tan = path[1] - path[0]
        elif i == len(path) - 1:
            tan = path[-1] - path[-2]
        else:
            tan = path[i + 1] - path[i - 1]
        side, up = frame_at(tan)
        rw, rh = radii[i]
        stations.append((p, side, up, rw * scale_side, rh, exp))
    return add_loft(bm, stations, n=n, cap_start=cap_start, cap_end=cap_end)


def add_ellipsoid(bm, center, rx, ry, rz, n=16, rings=9):
    c = Vector(center)
    stations = []
    for k in range(rings + 1):
        a = math.pi * float(k) / rings
        r = math.sin(a)
        h = math.cos(a)
        stations.append((c + Vector((0.0, 0.0, rz * h)), Vector((1.0, 0.0, 0.0)),
                         Vector((0.0, 1.0, 0.0)), max(1e-5, rx * r), max(1e-5, ry * r), 1.0))
    # 用极小的首尾半径做"闭合球"，避免极点非流形
    return add_loft(bm, stations, n=n, cap_start=True, cap_end=True)


def sample_path(control, count_scale=3.0):
    return catmull_rom(control, samples_per_seg=max(3, int(count_scale)))


def radii_along(path, keys):
    """keys: [(t, rw, rh), ...] 按弧长参数插值的半径序列。"""
    total = 0.0
    acc = [0.0]
    for i in range(1, len(path)):
        total += (path[i] - path[i - 1]).length
        acc.append(total)
    out = []
    for d in acc:
        t = (d / total) if total > 1e-9 else 0.0
        ks = sorted(keys, key=lambda k: k[0])
        if t <= ks[0][0]:
            rw, rh = ks[0][1], ks[0][2]
        elif t >= ks[-1][0]:
            rw, rh = ks[-1][1], ks[-1][2]
        else:
            rw, rh = ks[-1][1], ks[-1][2]
            for a, b in zip(ks, ks[1:]):
                if a[0] <= t <= b[0]:
                    f = (t - a[0]) / max(1e-9, b[0] - a[0])
                    f = f * f * (3.0 - 2.0 * f)      # smoothstep：半径变化更自然
                    rw = a[1] + (b[1] - a[1]) * f
                    rh = a[2] + (b[2] - a[2]) * f
                    break
        out.append((rw, rh))
    return out


# ---------------------------------------------------------------- 解剖结构

## 躯干脊柱控制点（y 前后向 / z 高度）。三轮返工后的取值：
## v002 修"平背"、v003 修"圆筒+鹿腿"、v004 再收腰收胸、髋低于颈。
SPINE = [
    (0.0, -0.186, 0.248),   # 臀部后缘
    (0.0, -0.120, 0.260),   # 髋结
    (0.0, -0.045, 0.255),   # 腰椎
    (0.0, 0.030, 0.244),
    (0.0, 0.095, 0.238),    # 肩胛后方（略低）
    (0.0, 0.150, 0.240),
    (0.0, 0.192, 0.252),    # 颈根（抬起）
]
SPINE_RADII = [
    (0.00, 0.038, 0.044),
    (0.10, 0.056, 0.062),   # 髋
    (0.34, 0.042, 0.047),   # 腰（收）
    (0.58, 0.062, 0.080),   # 胸腔
    (0.82, 0.055, 0.070),
    (1.00, 0.040, 0.044),
]

NECK = [(0.0, 0.188, 0.246), (0.0, 0.210, 0.266), (0.0, 0.234, 0.282)]
NECK_RADII = [(0.0, 0.046, 0.052), (0.5, 0.040, 0.045), (1.0, 0.036, 0.040)]

## 头：沿 +Y 的连续截面（颅骨 → 眉弓/颊 → 吻部 → 鼻梁）
## v008：整体加宽/加高约 8% —— 四轮判读都说"头太小、耳太长"，猫的辨识度靠**头身比**。
HEAD_STATIONS = [
    (0.228, 0.043, 0.041, 0.280),
    (0.246, 0.056, 0.051, 0.282),
    (0.264, 0.060, 0.053, 0.279),   # 最宽处（颧/眉弓）
    (0.282, 0.056, 0.049, 0.274),
    (0.296, 0.046, 0.039, 0.270),   # 吻部起点（stop）
    (0.308, 0.036, 0.030, 0.267),
    (0.320, 0.026, 0.023, 0.266),   # 鼻端
]

# ---- 面部/耳内等"必须在 remesh 之后才加"的特征零件（深色材质槽）----
EYE_R = 0.0120
EYE_POS = [(0.029, 0.2930, 0.3040)]
NOSE_POS = (0.0, 0.3235, 0.2685)
# v007/v008：耳高 0.404 → 0.378（相对头高更短）、基部 0.026 → 0.038（更像三角帆而不是刀片）、耳尖更外张
EAR_BASE = (0.032, 0.248, 0.308)
EAR_TIP = (0.072, 0.236, 0.378)


def mirror_pts(pts, sign):
    return [(sign * p[0], p[1], p[2]) for p in pts]


def build_cat_bmesh():
    bm = bmesh.new()
    log("geom|spine_control=%d|head_stations=%d" % (len(SPINE), len(HEAD_STATIONS)))

    # ---- 躯干 ----
    spine = catmull_rom(SPINE, samples_per_seg=5)
    radii = radii_along(spine, SPINE_RADII)
    stations = []
    for i, p in enumerate(spine):
        if i == 0:
            tan = spine[1] - spine[0]
        elif i == len(spine) - 1:
            tan = spine[-1] - spine[-2]
        else:
            tan = spine[i + 1] - spine[i - 1]
        side, up = frame_at(tan, Vector((1.0, 0.0, 0.0)))
        t = float(i) / (len(spine) - 1)
        rw, rh = radii[i]
        # v006：**取消** superellipse（e=0.85 时棱角落在正上/正侧方向，
        # 视觉判读把背上的那两条硬转折读成"拼接折痕"）。纯椭圆截面 + 半径变化足够。
        e = 1.0
        stations.append((p, side, up, rw, rh, e))
    add_loft(bm, stations, n=22)

    # ---- 颈 ----
    neck = catmull_rom(NECK, samples_per_seg=4)
    neck_r = radii_along(neck, NECK_RADII)
    nstations = []
    for i, p in enumerate(neck):
        tan = neck[min(i + 1, len(neck) - 1)] - neck[max(i - 1, 0)]
        side, up = frame_at(tan, Vector((1.0, 0.0, 0.0)))
        rw, rh = neck_r[i]
        nstations.append((p, side, up, rw, rh, 0.95))
    add_loft(bm, nstations, n=20)

    # ---- 头 ----
    hstations = []
    for (y, rw, rh, cz) in HEAD_STATIONS:
        c = Vector((0.0, y, cz))
        hstations.append((c, Vector((1.0, 0.0, 0.0)), Vector((0.0, 0.0, 1.0)), rw, rh, 0.9))
    add_loft(bm, hstations, n=22)

    # 颊部毛团（猫的脸宽来自颊毛，不是颅骨）：v003 收小，别把脸撑成"史莱姆"
    for sign in (-1.0, 1.0):
        add_ellipsoid(bm, (sign * 0.043, 0.276, 0.266), 0.019, 0.022, 0.022, n=14, rings=8)
        # 眼窝垫：给眼睛一个"包在头里"的基座（v002 判读：眼睛像弹珠贴在脸上）
        add_ellipsoid(bm, (sign * 0.029, 0.289, 0.2985), 0.018, 0.019, 0.015, n=12, rings=7)
        # 眉弓
        add_ellipsoid(bm, (sign * 0.028, 0.283, 0.3070), 0.014, 0.016, 0.011, n=12, rings=7)
        # 上眼睑棱：v003 判读"像没眼皮的黄半球被硬塞进坑里" → 加一道眼皮
        add_ellipsoid(bm, (sign * 0.029, 0.2885, 0.3120), 0.016, 0.014, 0.007, n=12, rings=7)
        # 胡须垫（八字形脸颊隆起）：v003 判读"吻部像平滑半球"
        add_ellipsoid(bm, (sign * 0.0155, 0.3115, 0.2635), 0.011, 0.013, 0.010, n=12, rings=7)
    # 下颌 / 吻垫 / 下巴：猫脸的"短而圆的嘴"
    add_ellipsoid(bm, (0.0, 0.286, 0.2500), 0.026, 0.030, 0.015, n=14, rings=8)
    add_ellipsoid(bm, (0.0, 0.302, 0.2620), 0.024, 0.018, 0.017, n=14, rings=8)
    add_ellipsoid(bm, (0.0, 0.310, 0.2520), 0.017, 0.014, 0.011, n=12, rings=7)

    # ---- 耳朵：沿耳轴的扁锥（厚度沿 X、宽度沿 Y）----
    for sign in (-1.0, 1.0):
        base = Vector((sign * EAR_BASE[0], EAR_BASE[1], EAR_BASE[2]))
        tip = Vector((sign * EAR_TIP[0], EAR_TIP[1], EAR_TIP[2]))
        mid = base.lerp(tip, 0.45) + Vector((0.0, -0.003, 0.0))
        ear_path = catmull_rom([base, mid, tip], samples_per_seg=5)
        ear_r = radii_along(ear_path, [(0.0, 0.0105, 0.038), (0.5, 0.0080, 0.027), (1.0, 0.0042, 0.006)])
        add_tube(bm, ear_path, ear_r, n=12)
        # 耳根盘（让耳朵不是"直接插在头顶"）
        add_ellipsoid(bm, (sign * 0.033, 0.250, 0.312), 0.017, 0.021, 0.014, n=12, rings=7)

    # ---- 四肢 ----
    for sign in (-1.0, 1.0):
        front = mirror_pts([
            (0.046, 0.112, 0.250),
            (0.048, 0.106, 0.200),
            (0.046, 0.096, 0.152),   # 肘（向后）
            (0.048, 0.112, 0.104),
            (0.048, 0.124, 0.050),   # 腕（向前）
            (0.048, 0.126, 0.028),
        ], sign)
        front_path = catmull_rom(front, samples_per_seg=4)
        front_r = radii_along(front_path, [
            (0.0, 0.041, 0.041), (0.28, 0.033, 0.033),
            (0.60, 0.027, 0.027), (0.86, 0.0200, 0.0200), (1.0, 0.0190, 0.0190)])
        add_tube(bm, front_path, front_r, n=12)
        add_ellipsoid(bm, (sign * 0.048, 0.134, 0.014), 0.021, 0.027, 0.014, n=14, rings=8)
        for dx in (-0.012, 0.0, 0.012):
            add_ellipsoid(bm, (sign * (0.048 + dx), 0.149, 0.010),
                          0.009, 0.011, 0.009, n=10, rings=6)
        # 肩胛（**埋进躯干里**，不再从背上鼓包）
        add_ellipsoid(bm, (sign * 0.038, 0.104, 0.256), 0.022, 0.034, 0.024, n=14, rings=8)

        hind = mirror_pts([
            (0.052, -0.140, 0.250),
            (0.056, -0.108, 0.200),
            (0.050, -0.086, 0.148),   # 膝（向前）
            (0.048, -0.122, 0.106),
            (0.050, -0.150, 0.066),   # 跗（向后）
            (0.052, -0.132, 0.034),
            (0.052, -0.126, 0.020),
        ], sign)
        hind_path = catmull_rom(hind, samples_per_seg=4)
        hind_r = radii_along(hind_path, [
            (0.0, 0.042, 0.042), (0.20, 0.036, 0.036), (0.44, 0.027, 0.027),
            (0.64, 0.022, 0.022), (0.84, 0.018, 0.018), (1.0, 0.017, 0.017)])
        add_tube(bm, hind_path, hind_r, n=12)
        add_ellipsoid(bm, (sign * 0.052, -0.118, 0.014), 0.021, 0.029, 0.014, n=14, rings=8)
        for dx in (-0.012, 0.0, 0.012):
            add_ellipsoid(bm, (sign * (0.052 + dx), -0.100, 0.010),
                          0.009, 0.011, 0.009, n=10, rings=6)
        # 大腿肌群（髋部体量）：v004 收小并内收，v003 判读为"两个球贴在骨盆上"
        add_ellipsoid(bm, (sign * 0.046, -0.112, 0.192), 0.021, 0.044, 0.042, n=14, rings=9)

    # ---- 尾巴：向上翘起的曲线，逐段收细，尾根有肌肉过渡 ----
    tail_ctrl = [
        (0.0, -0.190, 0.244),
        (0.0, -0.226, 0.256),
        (0.0, -0.252, 0.284),
        (0.0, -0.262, 0.322),
        (0.0, -0.254, 0.364),
        (0.0, -0.240, 0.394),
    ]
    tail_path = catmull_rom(tail_ctrl, samples_per_seg=4)
    tail_r = radii_along(tail_path, [
        (0.0, 0.0135, 0.0135), (0.28, 0.0120, 0.0120), (0.58, 0.0095, 0.0095),
        (0.82, 0.0072, 0.0072), (1.0, 0.0035, 0.0035)])
    add_tube(bm, tail_path, tail_r, n=12)
    add_ellipsoid(bm, (0.0, -0.184, 0.246), 0.020, 0.024, 0.024, n=14, rings=8)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    log("geom|verts=%d|faces=%d" % (len(bm.verts), len(bm.faces)))
    return bm


def build_features_bmesh():
    """眼睛 / 鼻头 / 耳内：**remesh 之后**才加的零件（remesh+平滑会把它们吃掉）。

    这些件用深色材质槽（`MAT_Cat_Detail`），是"猫脸可辨识"的关键：
    没有它们，头部只是一块平滑钝面（v001 视觉判读原话）。
    """
    bm = bmesh.new()
    for sign in (-1.0, 1.0):
        x, y, z = EYE_POS[0]
        add_ellipsoid(bm, (sign * x, y, z), EYE_R, EYE_R * 0.92, EYE_R, n=16, rings=9)
    add_ellipsoid(bm, NOSE_POS, 0.0115, 0.0075, 0.0070, n=14, rings=8)
    add_ellipsoid(bm, (0.0, NOSE_POS[1] - 0.0035, NOSE_POS[2] - 0.0062),
                  0.0055, 0.0050, 0.0045, n=10, rings=6)   # 鼻中隔/人中起始
    # 耳内：贴在耳朵**前侧**的薄片（深色），给出耳廓内凹的视觉
    for sign in (-1.0, 1.0):
        base = Vector((sign * (EAR_BASE[0] + 0.002), EAR_BASE[1] + 0.008, EAR_BASE[2] + 0.006))
        tip = Vector((sign * (EAR_TIP[0] - 0.002), EAR_TIP[1] + 0.006, EAR_TIP[2] - 0.020))
        mid = base.lerp(tip, 0.5)
        path = catmull_rom([base, mid, tip], samples_per_seg=4)
        r = radii_along(path, [(0.0, 0.0016, 0.026), (0.5, 0.0014, 0.017), (1.0, 0.0008, 0.002)])
        add_tube(bm, path, r, n=10)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    log("features|verts=%d|faces=%d" % (len(bm.verts), len(bm.faces)))
    return bm


# ---------------------------------------------------------------- 网格收尾

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


def finalize_body(obj, voxel, smooth_iter, target_tris):
    """Voxel Remesh 焊接 → 平滑 → 抽面到预算 → 噪声位移（毛发起伏）。"""
    activate(obj)
    m = obj.modifiers.new("Remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel
    m.adaptivity = 0.0
    m.use_smooth_shade = True
    log("modifier|remesh_voxel=%.5f" % voxel)
    apply_all_modifiers(obj)
    log("after_remesh|verts=%d|tris=%d" % (len(obj.data.vertices), tri_count(obj)))

    m = obj.modifiers.new("Smooth", "SMOOTH")
    m.factor = 0.55
    m.iterations = smooth_iter
    log("modifier|smooth_iter=%d" % smooth_iter)
    apply_all_modifiers(obj)

    tris = tri_count(obj)
    ratio = min(0.95, float(target_tris) / max(1, tris))
    m = obj.modifiers.new("Decimate", "DECIMATE")
    m.decimate_type = "COLLAPSE"
    m.ratio = ratio
    m.use_collapse_triangulate = True
    log("modifier|decimate_ratio=%.4f|from_tris=%d" % (ratio, tris))
    apply_all_modifiers(obj)

    # v004：抽面会在平滑曲面上留下长条三角（判读为"菱形折痕"）→ 抽面后再轻修一次
    m = obj.modifiers.new("PostSmooth", "SMOOTH")
    m.factor = 0.30
    m.iterations = 2
    log("modifier|post_decimate_smooth=0.30x2")
    apply_all_modifiers(obj)

    tex = bpy.data.textures.new("TEX_Cat_FurNoise", "CLOUDS")
    tex.noise_scale = DISPLACE_SCALE
    tex.noise_depth = 2
    m = obj.modifiers.new("FurDisplace", "DISPLACE")
    m.texture = tex
    m.texture_coords = "LOCAL"
    m.strength = DISPLACE_STRENGTH
    m.mid_level = 0.5
    log("modifier|displace_strength=%.5f|scale=%.4f" % (DISPLACE_STRENGTH, DISPLACE_SCALE))
    apply_all_modifiers(obj)

    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.data.update()
    log("finalize|verts=%d|tris=%d" % (len(obj.data.vertices), tri_count(obj)))
    return obj


def join_objects(main, others):
    activate(main)
    for o in others:
        o.select_set(True)
    bpy.ops.object.join()
    activate(main)
    return main


def mesh_islands(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    seen = set()
    islands = 0
    for f in bm.faces:
        if f.index in seen:
            continue
        islands += 1
        stack = [f]
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            for e in cur.edges:
                for nf in e.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
    non_manifold = sum(1 for e in bm.edges if not e.is_manifold)
    bm.free()
    return islands, non_manifold


# ---------------------------------------------------------------- 材质 / UV / 烘焙

def build_materials():
    fur = bpy.data.materials.new(MAT_FUR)
    fur.use_nodes = True
    nt = fur.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:
        fatal("no_principled_bsdf|%s" % MAT_FUR)
    bsdf.inputs["Roughness"].default_value = 0.78
    if "Specular" in bsdf.inputs:
        bsdf.inputs["Specular"].default_value = 0.20

    coord = nodes.new("ShaderNodeTexCoord")
    coord.location = (-1400, 0)
    sep = nodes.new("ShaderNodeSeparateXYZ")
    sep.location = (-1200, 0)
    links.new(coord.outputs["Object"], sep.inputs["Vector"])

    # 背深腹浅：按 z 做渐变
    zramp = nodes.new("ShaderNodeValToRGB")
    zramp.location = (-1000, 200)
    zramp.color_ramp.elements[0].position = 0.10
    zramp.color_ramp.elements[0].color = COL_BELLY
    zramp.color_ramp.elements[1].position = 0.32
    zramp.color_ramp.elements[1].color = COL_MID
    links.new(sep.outputs["Z"], zramp.inputs["Fac"])
    zramp2 = nodes.new("ShaderNodeValToRGB")
    zramp2.location = (-1000, 0)
    zramp2.color_ramp.elements[0].position = 0.26
    zramp2.color_ramp.elements[0].color = COL_MID
    zramp2.color_ramp.elements[1].position = 0.36
    zramp2.color_ramp.elements[1].color = COL_BACK
    links.new(sep.outputs["Z"], zramp2.inputs["Fac"])

    # 虎斑：沿 y 的周期性暗纹（低频包络 × 高频条纹，避免规则的斑马线）
    m1 = nodes.new("ShaderNodeMath")
    m1.operation = "MULTIPLY"
    m1.inputs[1].default_value = 62.0
    m1.location = (-1000, -250)
    links.new(sep.outputs["Y"], m1.inputs[0])
    sine = nodes.new("ShaderNodeMath")
    sine.operation = "SINE"
    sine.location = (-850, -250)
    links.new(m1.outputs[0], sine.inputs[0])
    striperamp = nodes.new("ShaderNodeValToRGB")
    striperamp.location = (-680, -250)
    striperamp.color_ramp.elements[0].position = 0.35
    striperamp.color_ramp.elements[0].color = (1.0, 1.0, 1.0, 1.0)
    striperamp.color_ramp.elements[1].position = 0.72
    striperamp.color_ramp.elements[1].color = (0.0, 0.0, 0.0, 1.0)
    links.new(sine.outputs[0], striperamp.inputs["Fac"])

    # 毛发细噪声（打散颜色，去掉"纯色塑料感"）
    noise = nodes.new("ShaderNodeTexNoise")
    noise.location = (-1000, -520)
    noise.inputs["Scale"].default_value = 55.0
    noise.inputs["Detail"].default_value = 4.0
    links.new(coord.outputs["Object"], noise.inputs["Vector"])
    nramp = nodes.new("ShaderNodeValToRGB")
    nramp.location = (-820, -520)
    nramp.color_ramp.elements[0].position = 0.42
    nramp.color_ramp.elements[0].color = (0.72, 0.72, 0.72, 1.0)
    nramp.color_ramp.elements[1].position = 0.62
    nramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    links.new(noise.outputs["Fac"], nramp.inputs["Fac"])

    # 侧面与背部的混合：|x| 越大越浅（体侧过渡）
    absx = nodes.new("ShaderNodeMath")
    absx.operation = "ABSOLUTE"
    absx.location = (-1000, 400)
    links.new(sep.outputs["X"], absx.inputs[0])
    sidefac = nodes.new("ShaderNodeMath")
    sidefac.operation = "MULTIPLY"
    sidefac.inputs[1].default_value = 9.0
    sidefac.location = (-850, 400)
    links.new(absx.outputs[0], sidefac.inputs[0])
    sidefac2 = nodes.new("ShaderNodeMath")
    sidefac2.operation = "MINIMUM"
    sidefac2.inputs[1].default_value = 1.0
    sidefac2.location = (-700, 400)
    links.new(sidefac.outputs[0], sidefac2.inputs[0])

    back_mix = nodes.new("ShaderNodeMixRGB")
    back_mix.blend_type = "MIX"
    back_mix.location = (-500, 100)
    links.new(zramp.outputs["Color"], back_mix.inputs[1])
    links.new(zramp2.outputs["Color"], back_mix.inputs[2])
    links.new(zramp2.outputs["Color"], back_mix.inputs["Fac"])

    stripe_mix = nodes.new("ShaderNodeMixRGB")
    stripe_mix.blend_type = "MIX"
    stripe_mix.location = (-320, 0)
    links.new(back_mix.outputs["Color"], stripe_mix.inputs[1])
    stripe_mix.inputs[2].default_value = COL_STRIPE
    s_fac = nodes.new("ShaderNodeMath")
    s_fac.operation = "MULTIPLY"
    s_fac.inputs[1].default_value = 0.32
    s_fac.location = (-500, -250)
    links.new(striperamp.outputs["Color"], s_fac.inputs[0])
    links.new(s_fac.outputs[0], stripe_mix.inputs["Fac"])

    noise_mix = nodes.new("ShaderNodeMixRGB")
    noise_mix.blend_type = "MULTIPLY"
    noise_mix.location = (-150, 0)
    noise_mix.inputs["Fac"].default_value = 0.45
    links.new(stripe_mix.outputs["Color"], noise_mix.inputs[1])
    links.new(nramp.outputs["Color"], noise_mix.inputs[2])

    # 口鼻浅色：y 越大越浅（吻部/下巴）
    yramp = nodes.new("ShaderNodeValToRGB")
    yramp.location = (-500, -650)
    yramp.color_ramp.elements[0].position = 0.292
    yramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    yramp.color_ramp.elements[1].position = 0.322
    yramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    links.new(sep.outputs["Y"], yramp.inputs["Fac"])
    muzzle_mix = nodes.new("ShaderNodeMixRGB")
    muzzle_mix.blend_type = "MIX"
    muzzle_mix.location = (50, 0)
    links.new(noise_mix.outputs["Color"], muzzle_mix.inputs[1])
    muzzle_mix.inputs[2].default_value = COL_MUZZLE
    links.new(yramp.outputs["Color"], muzzle_mix.inputs["Fac"])

    # 耳尖深色：**渐变**而不是硬阈值（v001 是 GREATER_THAN，判读为"生硬的色块切换"）
    eartip = nodes.new("ShaderNodeValToRGB")
    eartip.location = (50, -300)
    eartip.color_ramp.elements[0].position = 0.330
    eartip.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    eartip.color_ramp.elements[1].position = 0.400
    eartip.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    links.new(sep.outputs["Z"], eartip.inputs["Fac"])
    tip_mix = nodes.new("ShaderNodeMixRGB")
    tip_mix.blend_type = "MIX"
    tip_mix.location = (220, 0)
    links.new(muzzle_mix.outputs["Color"], tip_mix.inputs[1])
    tip_mix.inputs[2].default_value = COL_EARTIP
    links.new(eartip.outputs["Color"], tip_mix.inputs["Fac"])

    img = bpy.data.images.new("CAT_BODY_001_BaseColor", TEX_SIZE, TEX_SIZE, alpha=False)
    img.colorspace_settings.name = "sRGB"
    tex_node = nodes.new("ShaderNodeTexImage")
    tex_node.location = (420, 0)
    tex_node.image = img

    # 烘焙目标节点：**先不连接**（否则烘焙读到的是空贴图 → 全黑），
    # 程序化颜色直接进 Base Color；烘完再把贴图接到 Base Color（见 bake_albedo）。
    nt.nodes.active = tex_node
    links.new(tip_mix.outputs["Color"], bsdf.inputs["Base Color"])
    fur.use_backface_culling = True

    # ---- 细节材质（眼睛/鼻头/耳内）----
    # v003：v002 的眼睛被判读为"灰玻璃弹珠"。这里用**空间距离**在材质里画出
    # 瞳孔/虹膜/鼻头粉色：不增加材质槽（仍是 2 个），并且一起烘进同一张贴图。
    detail = bpy.data.materials.new(MAT_DETAIL)
    detail.use_nodes = True
    dnt = detail.node_tree
    dnodes, dlinks = dnt.nodes, dnt.links
    dbsdf = dnodes.get("Principled BSDF")
    dbsdf.inputs["Roughness"].default_value = 0.32
    if "Specular" in dbsdf.inputs:
        dbsdf.inputs["Specular"].default_value = 0.6

    dcoord = dnodes.new("ShaderNodeTexCoord")
    dcoord.location = (-1200, 0)

    def dist_to(target):
        sub = dnodes.new("ShaderNodeVectorMath")
        sub.operation = "SUBTRACT"
        sub.inputs[1].default_value = Vector(target)
        dlinks.new(dcoord.outputs["Object"], sub.inputs[0])
        ln = dnodes.new("ShaderNodeVectorMath")
        ln.operation = "LENGTH"
        dlinks.new(sub.outputs["Vector"], ln.inputs[0])
        return ln.outputs["Value"]

    d_eye = dist_to((EYE_POS[0][0], EYE_POS[0][1], EYE_POS[0][2]))
    d_eye2 = dist_to((-EYE_POS[0][0], EYE_POS[0][1], EYE_POS[0][2]))
    dmin = dnodes.new("ShaderNodeMath")
    dmin.operation = "MINIMUM"
    dlinks.new(d_eye, dmin.inputs[0])
    dlinks.new(d_eye2, dmin.inputs[1])

    eye_ramp = dnodes.new("ShaderNodeValToRGB")
    eye_ramp.color_ramp.interpolation = "EASE"
    edges = [(0.0, (0.003, 0.003, 0.004, 1.0)),        # 瞳孔（近黑）
             (0.0055, (0.003, 0.003, 0.004, 1.0)),
             (0.0068, (0.480, 0.270, 0.035, 1.0)),     # 虹膜（琥珀）
             (0.0092, (0.160, 0.090, 0.022, 1.0)),
             (0.0106, (0.020, 0.015, 0.012, 1.0)),     # 眼睑/耳内底色
             (0.0500, (0.020, 0.015, 0.012, 1.0))]
    eye_ramp.color_ramp.elements[0].position = edges[0][0]
    eye_ramp.color_ramp.elements[0].color = edges[0][1]
    eye_ramp.color_ramp.elements[1].position = edges[-1][0]
    eye_ramp.color_ramp.elements[1].color = edges[-1][1]
    for pos, col in edges[1:-1]:
        e = eye_ramp.color_ramp.elements.new(pos)
        e.color = col
    dlinks.new(dmin.outputs[0], eye_ramp.inputs["Fac"])

    d_nose = dist_to(NOSE_POS)
    nose_ramp = dnodes.new("ShaderNodeValToRGB")
    nose_ramp.color_ramp.elements[0].position = 0.000
    nose_ramp.color_ramp.elements[0].color = (0.230, 0.105, 0.100, 1.0)   # 鼻头粉
    nose_ramp.color_ramp.elements[1].position = 0.011
    nose_ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    dlinks.new(d_nose, nose_ramp.inputs["Fac"])

    mix = dnodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MIX"
    mix.inputs[1].default_value = (0.020, 0.015, 0.012, 1.0)
    dlinks.new(eye_ramp.outputs["Color"], mix.inputs[2])
    dlinks.new(nose_ramp.outputs["Color"], mix.inputs["Fac"])

    dimg_node = dnodes.new("ShaderNodeTexImage")
    dimg_node.image = img
    dimg_node.location = (420, 0)
    dnt.nodes.active = dimg_node
    dlinks.new(mix.outputs["Color"], dbsdf.inputs["Base Color"])
    detail.use_backface_culling = True

    log("material|%s|roughness=0.78|textured=True" % MAT_FUR)
    log("material|%s|iris_by_distance=True|roughness=0.32" % MAT_DETAIL)
    return {MAT_FUR: fur, MAT_DETAIL: detail}, img, [tex_node, dimg_node]


def setup_uv(obj):
    activate(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    uv = obj.data.uv_layers[0] if obj.data.uv_layers else None
    log("uv|layers=%d|name=%s" % (len(obj.data.uv_layers), uv.name if uv else "none"))
    require(uv is not None, "uv_missing")


def material_island(obj, mat_index):
    """只统计某个材质槽的连通壳数（眼睛/鼻头是刻意独立的部件，不算"孤岛"）。"""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    faces = [f for f in bm.faces if f.material_index == mat_index]
    seen = set()
    islands = 0
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
    bm.free()
    return islands
def bake_albedo(obj, img_nodes):
    """把两个材质槽的程序化颜色一起烘进同一张 albedo（眼睛/鼻头也走贴图）。"""
    if isinstance(img_nodes, list):
        nodes = img_nodes
    else:
        raise RuntimeError("img_nodes must be a list")
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 6
    scene.render.bake.margin = 8
    scene.render.bake.use_clear = True
    img = nodes[0].image
    for mat_name in (MAT_FUR, MAT_DETAIL):
        m = bpy.data.materials.get(mat_name)
        for nd in nodes:
            if nd.id_data == m.node_tree:
                m.node_tree.nodes.active = nd
                log("bake|active_node|mat=%s|node=%s" % (mat_name, nd.name))
    activate(obj)
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True)
    img.filepath_raw = REPO + "/Art/Exports/Cat/CAT_BODY_001_BaseColor.png"
    img.file_format = "PNG"
    img.save()
    log("bake|diffuse=OK|size=%dx%d|png=%s" % (img.size[0], img.size[1], img.filepath_raw))
    # 烘焙完成后把贴图接到各自的 Base Color（导出 glTF 时即 baseColorTexture）
    for mat_name in (MAT_FUR, MAT_DETAIL):
        m = bpy.data.materials.get(mat_name)
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        for nd in nodes:
            if nd.id_data != m.node_tree:
                continue
            for l in list(m.node_tree.links):
                if l.to_socket == bsdf.inputs["Base Color"]:
                    m.node_tree.links.remove(l)
            m.node_tree.links.new(nd.outputs["Color"], bsdf.inputs["Base Color"])
    log("bake|linked_to_base_color=True|materials=2")

def export_glb(glb_out):
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
        "export_texcoords": True,
        "export_normals": True,
        "export_colors": False,
        "export_skins": False,
        "export_animations": False,
    }
    applied = {k: v for k, v in wanted.items() if k in props}
    unsupported = sorted(k for k in wanted if k not in props)
    log("gltf_export|applied=%s|unsupported=%s" % (
        ",".join("%s=%s" % (k, applied[k]) for k in sorted(applied)),
        ",".join(unsupported) or "none"))
    bpy.ops.export_scene.gltf(filepath=glb_out, **applied)
    if not os.path.isfile(glb_out):
        fatal("glb_not_written|%s" % glb_out)
    with open(glb_out, "rb") as f:
        data = f.read()
    log("glb|path=%s|bytes=%d|sha256=%s" % (glb_out, len(data), hashlib.sha256(data).hexdigest()))


# ---------------------------------------------------------------- 渲染

def setup_render_scene():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.28, 0.30, 0.33, 1.0)
    bg.inputs["Strength"].default_value = 0.55

    # 地面：与关卡灰盒同一灰色，便于判断贴地与阴影
    bpy.ops.mesh.primitive_plane_add(size=4.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object
    ground.name = "RENDER_Ground"
    gm = bpy.data.materials.new("MAT_RENDER_Ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.30, 0.31, 0.33, 1.0)
    gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    ground.data.materials.append(gm)
    def add_light(name, kind, loc, energy, size, rot):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        if kind == "AREA":
            ld.size = size
        ob = bpy.data.objects.new(name, ld)
        ob.location = loc
        ob.rotation_euler = rot
        bpy.context.scene.collection.objects.link(ob)
        return ob

    add_light("KEY", "AREA", (0.55, 0.75, 0.85), 110.0, 0.8,
              (math.radians(52.0), 0.0, math.radians(140.0)))
    add_light("FILL", "AREA", (-0.75, 0.45, 0.55), 40.0, 1.1,
              (math.radians(62.0), 0.0, math.radians(-130.0)))
    add_light("RIM", "AREA", (0.0, -0.95, 0.70), 70.0, 0.6,
              (math.radians(115.0), 0.0, 0.0))

    cam_data = bpy.data.cameras.new("CAM")
    cam_data.lens = 60.0
    cam = bpy.data.objects.new("CAM", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    scene.camera = cam
    log("render|engine=%s|device=%s|samples=%d|res=%dx%d" % (
        scene.render.engine, scene.cycles.device, scene.cycles.samples,
        scene.render.resolution_x, scene.render.resolution_y))
    return cam


def point_camera(cam, location, target):
    cam.location = Vector(location)
    direction = Vector(target) - Vector(location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


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
    paths = []
    for name, loc in views:
        aim = Vector((0.0, 0.29, 0.295)) if name == "face" else target
        point_camera(cam, loc, aim)
        out = "%s/art02_%s_%s.png" % (RENDER_DIR, tag, name)
        scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        log("render|view=%s|path=%s" % (name, out))
        paths.append(out)
    return paths


def render_sheet(obj, tag):
    """四向合影：正/侧/背/45 并排 —— 一次判读拿到整体形体的全部问题。"""
    scene = bpy.context.scene
    src = obj.copy()
    src.data = obj.data.copy()
    scene.collection.objects.link(src)
    clones = []
    angles = [0.0, 95.0, 180.0, 235.0]
    spacing = 0.70
    for i, ang in enumerate(angles):
        c = src if i == 0 else src.copy()
        if i != 0:
            c.data = src.data
            bpy.context.scene.collection.objects.link(c)
        c.rotation_euler = (0.0, 0.0, math.radians(ang))
        c.location = Vector(((i - 1.5) * spacing, 0.0, 0.0))
        clones.append(c)
    obj.hide_render = True
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 620
    cam = scene.camera
    # 相机拉远 + 覆盖 4 个模型；v004：60mm → 35mm，否则只有中间两个进画
    scene.camera.data.lens = 35.0
    point_camera(cam, (0.0, 2.70, 0.50), Vector((0.0, 0.0, 0.20)))
    out = "%s/art02_%s_sheet.png" % (RENDER_DIR, tag)
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    log("render|view=sheet|path=%s" % out)
    obj.hide_render = False
    for c in clones:
        bpy.data.objects.remove(c, do_unlink=True)
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.camera.data.lens = 60.0
    return out


def render_wireframe(obj, tag):
    scene = bpy.context.scene
    wf = obj.copy()
    wf.data = obj.data.copy()
    scene.collection.objects.link(wf)
    m = wf.modifiers.new("Wire", "WIREFRAME")
    m.thickness = 0.0016
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
    cam = scene.camera
    point_camera(cam, (0.80, 0.82, 0.45), Vector((0.0, 0.02, 0.21)))
    out = "%s/art02_%s_wire.png" % (RENDER_DIR, tag)
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    log("render|view=wireframe|path=%s" % out)
    obj.hide_render = False
    bpy.data.objects.remove(wf, do_unlink=True)
    return out


# ---------------------------------------------------------------- 自检

def self_check(obj, tag):
    obj.data.calc_loop_triangles()
    tris = len(obj.data.loop_triangles)
    coords = [obj.matrix_world @ v.co for v in obj.data.vertices]
    mn = Vector((min(c.x for c in coords), min(c.y for c in coords), min(c.z for c in coords)))
    mx = Vector((max(c.x for c in coords), max(c.y for c in coords), max(c.z for c in coords)))
    islands, non_manifold = mesh_islands(obj)
    fur_islands = material_island(obj, 0)
    log("%s|fur_islands=%d|all_islands=%d" % (tag, fur_islands, islands))
    log("%s|verts=%d|tris=%d|slots=%d|aabb_min=%s|aabb_max=%s|islands=%d|non_manifold=%d" % (
        tag, len(obj.data.vertices), tris, len(obj.data.materials),
        vec_str(mn), vec_str(mx), islands, non_manifold))
    log("%s|height=%.4f|length=%.4f|width=%.4f" % (tag, mx.z - mn.z, mx.y - mn.y, mx.x - mn.x))

    require(tris <= TRI_BUDGET, "%s|tri_budget_exceeded|%d>%d" % (tag, tris, TRI_BUDGET))
    require(tris >= 3000, "%s|too_few_tris|%d" % (tag, tris))
    require(len(obj.data.materials) <= 2, "%s|slot_over_budget|%d" % (tag, len(obj.data.materials)))
    require(abs(mn.z) < 0.004, "%s|not_grounded|min_z=%.4f" % (tag, mn.z))
    require(mx.z <= Z_LIMIT, "%s|too_tall|max_z=%.4f>%.2f" % (tag, mx.z, Z_LIMIT))
    require(max(abs(mn.x), abs(mx.x)) <= X_LIMIT,
            "%s|too_wide|x=[%.3f,%.3f]>%.3f" % (tag, mn.x, mx.x, X_LIMIT))
    require(abs(mn.x + mx.x) < SYMMETRY_TOL,
            "%s|not_symmetric|x=[%.4f,%.4f]" % (tag, mn.x, mx.x))
    require(fur_islands == 1, "%s|fur_island_count|%d" % (tag, fur_islands))
    require(non_manifold == 0, "%s|non_manifold_edges|%d" % (tag, non_manifold))
    return tris


def main():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    version = "v001"
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

    blend_out = "%s/Art/Blender/Cat/CAT_BODY_001_%s.blend" % (REPO, version)
    glb_out = REPO + "/Art/Exports/Cat/SM_Cat_001.glb"
    for d in (os.path.dirname(blend_out), os.path.dirname(glb_out), RENDER_DIR):
        if not os.path.isdir(d):
            os.makedirs(d)
            log("mkdir|%s" % d)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = "METERS"

    mats, img, img_node = build_materials()
    body = new_object(ASSET_NAME, MESH_NAME, build_cat_bmesh())
    body.data.materials.append(mats[MAT_FUR])
    body.data.materials.append(mats[MAT_DETAIL])
    finalize_body(body, voxel=0.0042, smooth_iter=8, target_tris=8200)

    detail = new_object("CAT_BODY_001_Detail", "CAT_BODY_001_DetailMesh", build_features_bmesh())
    detail.data.materials.append(mats[MAT_FUR])
    detail.data.materials.append(mats[MAT_DETAIL])
    for poly in detail.data.polygons:
        poly.use_smooth = True
        poly.material_index = 1
    join_objects(body, [detail])
    for poly in body.data.polygons:
        if poly.material_index not in (0, 1):
            poly.material_index = 1
    body.data.update()

    self_check(body, "built")
    if stage in ("mesh", "shot"):
        bpy.ops.wm.save_as_mainfile(filepath=blend_out)
        log("blend|path=%s|bytes=%d" % (blend_out, os.path.getsize(blend_out)))
    if stage == "mesh":
        log("done|stage=mesh|failures=%d" % len(failures))
        sys.exit(0 if not failures else 1)
    if stage == "shot":
        setup_render_scene()
        render_views(body, version)
        render_sheet(body, version)
        render_wireframe(body, version)
        log("done|stage=shot|failures=%d" % len(failures))
        sys.exit(0 if not failures else 1)

    setup_uv(body)
    bake_albedo(body, img_node)
    body.update_tag()
    bpy.ops.wm.save_as_mainfile(filepath=blend_out)
    log("blend|path=%s|bytes=%d" % (blend_out, os.path.getsize(blend_out)))

    setup_render_scene()
    render_views(body, version)
    render_sheet(body, version)
    render_wireframe(body, version)

    # 导出前把渲染辅助物移出场景，避免 glb 里混进灯光/相机/地面
    for ob in list(bpy.data.objects):
        if ob.type in {"LIGHT", "CAMERA"} or ob.name.startswith("RENDER_"):
            bpy.data.objects.remove(ob, do_unlink=True)
    export_glb(glb_out)

    log("done|stage=all|failures=%d" % len(failures))
    sys.exit(0 if not failures else 1)


main()
