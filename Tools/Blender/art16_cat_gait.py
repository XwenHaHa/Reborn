# -*- coding: utf-8 -*-
"""第三阶段：猫的**分段步态**（支撑相 / 摆动相）生成 —— 候选 `SM_Cat_004.glb`。

## 为什么单独一个脚本
`art15_cat_anim.py` 的步态是"大腿正弦摆 + 膝正弦补"，脚掌相对身体只能摆 0.10 m，
而 1.8 m/s / 0.30 s 周期需要脚掌相对身体退 0.27 m ⇒ 滑步 ~1.8 m/s（第二阶段实测）。
本脚本改成**目标驱动**：先定义每只脚在角色本地空间的轨迹，再用解析 IK 反解腿骨，
让支撑相的脚掌相对世界静止。

## 腿的运动学简化（先读这个）
每条腿 4 节实骨（前肢 .015-.018、后肢 .011-.014；`*_end` 是导出器补的零长度叶骨）。
按两件处理：
- 上段 b1（股/肱），长度 A；
- 下段块 b2+b3（胫/桡 + 跖/掌）保持**静止姿态的相对夹角**，等效向量 V（膝 → 趾根），长度 B2；
- b4（趾/掌）保持**静止姿态的世界朝向** ⇒ 脚掌始终平贴地面，不随小腿翻转。
于是"趾根"(b4 头) → "趾尖"(b4 尾) 是常向量 q4：落点目标先减 q4 得趾根目标，
再用两节解析 IK（L1=A、L2=B2）解髋与膝 ⇒ 趾根精确落到目标，趾尖落在地面。
（不把"跖骨"也算进上两节的原因：实测 A+B 只有 0.1229 m，而静止姿态髋→踝已占 0.1220 m，
只剩 0.0009 m 余量，任何步幅都会拉直 ⇒ 几何上无解。见证据里的对照表。）

## 轨迹（v 玩法速度、T 周期、duty 支撑相占比、S = v*duty*T）
- 支撑相 u in [0,duty)：沿前进反方向匀速后退，速率恰为 v，高度不变（= 相对世界静止）；
- 摆动相：余弦前摆（两端速度为 0，与支撑相不跳变），高度 lift*sin(pi*s)。

## 身体高度
竖直下压 sink + 起伏 bob 只是期望曲线；再用"任何支撑腿的髋→趾根距离不得超过
reach_k*(A+B2)"沿世界竖直解二次方程求每帧允许上限，两者取小 ⇒ 超限时抬身体，
而不是把脚拉离地面。实际高度、最大伸展比、夹紧次数全部打印，不靠公式宣称通过。

## 其他
- 关键帧落在 0..N、N = round(T*60)、NLA strip 从 0 起、末帧=首帧（循环收敛，第二阶段 3.2）。
- armature 局部空间与世界空间朝向不同（归一化时整对象绕 Z 转过角度），
  所以前进/竖直方向用 matrix_world 反算，不硬编码 XYZ。

## 用法
  blender --background --factory-startup --python art16_cat_gait.py -- --stage probe
  blender ... -- --stage all [--out E:/Reborn/Art/Exports/Cat/SM_Cat_004.glb]
              [--set "Walk:T=0.30+Run:duty=0.35"] [--tag exp01]
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

REPO = "E:/Reborn"
sys.path.insert(0, REPO + "/Tools/Blender")
import art15_cat_anim as A15          # noqa: E402  复用建模型/归一化/骨骼分类/导出

GLB_OUT = REPO + "/Art/Exports/Cat/SM_Cat_004.glb"
PROTECTED = (
    REPO + "/Art/Exports/Cat/SM_Cat_002.glb",
    REPO + "/Art/Exports/Cat/SM_Cat_003.glb",
)
FPS = 60                     # 60 fps：0.30 s = 18 帧、0.20 s = 12 帧，周期精确落帧

log = A15.log
require = A15.require
DEG = math.radians
CHECK = False                # --check：导出前用 depsgraph 逐帧回读真实趾尖并校验

# --------------------------------------------------------------------------- 默认参数
# sink/bob/lift 是**世界米**；duty=支撑相占比；pattern 见 PHASE_PATTERNS。
DEFAULTS = {
    "Idle": {
        "T": 2.0, "duty": 1.0, "v": 0.0, "pattern": "stand",
        "sink": 0.0, "bob": 0.002, "bob_cycles": 2.0, "lift": 0.0, "reach_k": 0.995,
        "pitch": DEG(0.0), "bob_pitch": DEG(1.5), "roll": DEG(0.4),
        "tail": DEG(6.0), "tail_lift": DEG(3.0), "tail_pitch": DEG(2.0),
    },
    "Walk": {
        "T": 0.30, "duty": 0.42, "v": 1.8, "pattern": "trot",
        "sink": 0.060, "bob": 0.016, "bob_cycles": 2.0, "lift": 0.045, "reach_k": 0.995,
        "pitch": DEG(1.0), "bob_pitch": DEG(1.5), "roll": DEG(1.5),
        "tail": DEG(7.0), "tail_lift": DEG(6.0), "tail_pitch": DEG(5.0),
    },
    "Run": {
        # duty 取 0.24：后肢够程只有 0.1796 m，duty 再大就顶到可达上限（0.30 时夹到 0.995）
        "T": 0.20, "duty": 0.24, "v": 4.5, "pattern": "gallop",
        "sink": 0.060, "bob": 0.020, "bob_cycles": 1.0, "lift": 0.070, "reach_k": 0.995,
        "pitch": DEG(6.0), "bob_pitch": DEG(3.0), "roll": DEG(3.0),
        "tail": DEG(10.0), "tail_lift": DEG(18.0), "tail_pitch": DEG(10.0),
    },
}

# 相位表：key = (前肢? "F"/"H", 左? 1/-1)，value = 该腿起始相位（0..1）
#   trot   对角两拍（FL+HR 同相、FR+HL 同相）
#   walk   侧序四拍 LH→LF→RH→RF（duty 需 >0.5 才有三脚支撑）
#   gallop 旋转袭步 HL→HR→FL→FR
#   bound  前后两拍
#   stand  全部 0（Idle 站立）
PHASE_PATTERNS = {
    "trot":   {("F", 1): 0.00, ("F", -1): 0.50, ("H", 1): 0.50, ("H", -1): 0.00},
    "walk":   {("H", 1): 0.00, ("F", 1): 0.25, ("H", -1): 0.50, ("F", -1): 0.75},
    "gallop": {("H", 1): 0.00, ("H", -1): 0.10, ("F", 1): 0.45, ("F", -1): 0.55},
    "bound":  {("H", 1): 0.00, ("H", -1): 0.00, ("F", 1): 0.50, ("F", -1): 0.50},
    "stand":  {("F", 1): 0.00, ("F", -1): 0.00, ("H", 1): 0.00, ("H", -1): 0.00},
}


def parse_set(spec):
    """`--set "Walk:T=0.30+Run:duty=0.35,Walk:sink=0.04"` → {clip: {key: float}}。"""
    out = {}
    if not spec:
        return out
    for chunk in spec.split(","):
        chunk = chunk.strip()
        if not chunk or ":" not in chunk:
            continue
        clip, rest = chunk.split(":", 1)
        for kv in rest.split("+"):
            if "=" not in kv:
                continue
            k, val = kv.split("=", 1)
            out.setdefault(clip.strip(), {})[k.strip()] = float(val)
    return out


# --------------------------------------------------------------------------- 腿的静止几何
class Leg:
    """一条腿的静止几何（长度=armature 单位；方向均在 armature 空间）。"""

    def __init__(self, arm, leg, s, fwd, up):
        self.name = leg["chain"][0]
        self.fore = leg["fore"]
        self.side = leg["side"]
        chain = leg["chain"]
        require(len(chain) >= 5 and chain[-1].endswith("_end"),
                "leg_chain_shape|%s|%s" % (self.name, chain))
        self.bones = list(chain[:4])
        db = arm.data.bones
        h = [db[n].head_local for n in self.bones]
        t = [db[n].tail_local for n in self.bones]
        self.hip_rest = h[0]
        self.ball_rest = h[3]                       # 趾根 = b4 头
        self.toe_rest = t[3]                        # 趾尖 = b4 尾
        self.A = (h[1] - h[0]).length               # 上段 b1
        self.V = h[3] - h[1]                        # 下段块 b2+b3（膝 → 趾根），保持相对夹角
        self.B2 = self.V.length
        self.C = (h[3] - h[2]).length
        self.D = (t[3] - h[3]).length
        self.q4 = t[3] - h[3]                       # 趾根 → 趾尖（b4 保持静止朝向 ⇒ 常向量）
        self.reach = self.A + self.B2
        self.rest3 = [db[n].matrix_local.to_3x3() for n in self.bones]
        self.rest_dir1 = (h[1] - h[0]).normalized()
        self.rest_dirV = self.V.normalized()
        # 步幅中心：以"**趾根**在地面的投影"为对称中心（不是静止趾尖、也不是髋）。
        # 趾根才是 IK 的末端（趾尖 = 趾根 + 常向量 q4），以趾尖为中心会让趾根多背
        # q4 的水平分量（后肢 24 mm），支撑相后半段就够不到了（实测需 88 mm 下压）。
        self.center_fwd = (self.ball_rest - self.hip_rest).dot(fwd)
        self.foot0 = self.toe_rest - fwd * self.center_fwd
        u = (h[2] - h[0]).normalized()
        perp = (h[1] - h[0]) - u * (h[1] - h[0]).dot(u)
        self.knee_perp = perp.normalized() if perp.length > 1e-6 else Vector((0.0, 1.0, 0.0))
        self.knee_perp = perp.normalized() if perp.length > 1e-6 else Vector((0.0, 1.0, 0.0))
        self.s = s
        self.MW = arm.matrix_world
        self.fwd = fwd
        self.up = up

    def key(self):
        return ("F" if self.fore >= 0 else "H", 1 if self.side >= 0 else -1)

    def report(self):
        toe_w = self.MW @ self.toe_rest
        hip_w = self.MW @ self.hip_rest
        ball_w = self.MW @ self.ball_rest
        rest_d = (self.ball_rest - self.hip_rest).length
        log("leg|%s|%s%s|A=%.4f|B2=%.4f|C=%.4f|D=%.4f|reach=%.4f|hip_h=%.4f|ball_h=%.4f|toe_world=%s" % (
            self.name, "F" if self.fore >= 0 else "H", "L" if self.side >= 0 else "R",
            self.A * self.s, self.B2 * self.s, self.C * self.s, self.D * self.s,
            self.reach * self.s, hip_w.z - toe_w.z, ball_w.z - toe_w.z, A15.vec(toe_w)))
        log("leg|%s|rest_hip_to_ball=%.4f|rest_extension=%.4f|margin=%.4f" % (
            self.name, rest_d * self.s, rest_d / max(1e-9, self.reach),
            (self.reach - rest_d) * self.s))
        log("leg|%s|center_shift=%.4f m" % (self.name, -self.center_fwd * self.s))


# --------------------------------------------------------------------------- 轨迹
def foot_offset_m(p, t_T):
    """(y_forward, z_up) 米：某腿在相位 t_T 时相对静止脚位的偏移。"""
    duty = p["duty"]
    S = p["v"] * duty * p["T"]
    if p["v"] <= 1e-6 or duty >= 1.0 - 1e-9:
        return 0.0, 0.0
    u = t_T % 1.0
    if u < duty:
        return S * 0.5 - S * (u / duty), 0.0
    sw = (u - duty) / (1.0 - duty)
    # 前摆：(1-cos)/2 为基准（两端水平速度为 0），再叠 A·sw²(1-sw) 把**落地瞬间的水平速度**
    # 往支撑相的 -v 拉（该附加项末端导数为 -1）。A 受够程限制：A 太大会让摆动相前伸超过
    # 腿的可达范围（实测 Run duty=0.24 时 A=3.17 直接把后肢拉出范围）。这里封顶 1.0。
    base = (1.0 - math.cos(math.pi * sw)) * 0.5
    a_corr = min((1.0 - duty) / duty, 1.0)
    f = base + a_corr * (sw * sw * (1.0 - sw))
    y = -S * 0.5 + S * f
    # 高度：sin^0.75 ⇒ 触地前陡降，减少"擦地帧"被算成接触帧
    z = p["lift"] * math.sin(math.pi * sw) ** 0.75
    return y, z


def in_stance(p, t_T):
    if p["duty"] >= 1.0 - 1e-9:
        return True
    return (t_T % 1.0) < p["duty"]


# --------------------------------------------------------------------------- 解析 IK
def solve_two_link(hip, target, a, b, bend_perp):
    """返回 (knee, reach_ratio, clamped)。平面两节 IK：|hip-knee|=a、|knee-target|=b。"""
    d_vec = target - hip
    d = d_vec.length
    if d < 1e-12:
        d_vec = Vector((0.0, 0.0, -1.0))
        d = 1e-12
    u = d_vec / d
    clamped = False
    lo, hi = abs(a - b) + 1e-6, a + b - 1e-6
    if d > hi:
        d = hi
        clamped = True
    elif d < lo:
        d = lo
        clamped = True
    cos_a = (d * d + a * a - b * b) / (2.0 * d * a)
    cos_a = max(-1.0, min(1.0, cos_a))
    sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
    # 弯曲平面：以**固定参考方向**（静止姿态的膝偏移方向）对垂直于髋→目标的方向正交化。
    # 原来用"(0,0,-1) 到 u 的最小旋转"去转它，腿接近竖直时该旋转退化 ⇒ 膝在腿两侧跳变，
    # 骨骼角度出现折点；导出后导入优化把这个折点抹平，脚掌就被带偏 3 mm。
    perp = bend_perp - u * bend_perp.dot(u)
    if perp.length < 1e-6:
        perp = Vector((0.0, 1.0, 0.0)) - u * u.y
    perp.normalize()
    knee = hip + u * (a * cos_a) + perp * (a * sin_a)
    return knee, d / max(1e-9, a + b), clamped


def basis_quat(arm, name, pose3, parent_pose3):
    """给定 armature 空间目标朝向，反算该骨的局部 basis 四元数。"""
    b = arm.data.bones[name]
    rest3 = b.matrix_local.to_3x3()
    if b.parent is not None:
        rel = b.parent.matrix_local.to_3x3().inverted() @ rest3
        basis3 = rel.inverted() @ parent_pose3.inverted() @ pose3
    else:
        basis3 = rest3.inverted() @ pose3
    return basis3.to_quaternion()


# --------------------------------------------------------------------------- 动作生成
def make_gait_action(arm, groups, legs, name, p, n_frames):
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    A15.clear_pose(arm)

    spine = groups["spine"]
    head = groups["head"]
    tail = groups["tail"]
    root = arm.pose.bones[spine[0]] if spine else None
    spine_mid_name = spine[len(spine) // 2] if spine else None
    head_bone = arm.pose.bones[head[-2] if len(head) >= 2 else head[-1]] if head else None
    # 身体下沉会把尾巴整体压低：按"尾长 + 下沉量"算出需要额外抬起的角度，避免尾尖穿地。
    tail_len = 0.0
    for tn in tail:
        db = arm.data.bones[tn]
        tail_len += (db.tail_local - db.head_local).length
    tail_len *= arm.matrix_world.to_scale().x
    sink_m = p["sink"]
    if tail_len > 1e-6 and sink_m > 0.0:
        extra_lift = math.asin(max(-0.9, min(0.9, sink_m / tail_len)))
    else:
        extra_lift = 0.0
    tail_lift_total = p["tail_lift"] + extra_lift
    log("tail|%s|len=%.3f m|sink=%.0fmm|extra_lift=%.1fdeg|total=%.1fdeg" % (
        name, tail_len, sink_m * 1000.0, math.degrees(extra_lift),
        math.degrees(tail_lift_total)))
    MW = arm.matrix_world
    s = MW.to_scale().x
    M3i = MW.to_3x3().inverted().normalized()
    ax_x = M3i @ Vector((1.0, 0.0, 0.0))
    ax_z = M3i @ Vector((0.0, 0.0, 1.0))
    fwd = (M3i @ Vector((0.0, 1.0, 0.0))).normalized()
    up = (M3i @ Vector((0.0, 0.0, 1.0))).normalized()

    phases = PHASE_PATTERNS[p["pattern"]]
    duty = p["duty"]
    reach_k = p["reach_k"]
    sink, bob, cycles, v = p["sink"], p["bob"], p["bob_cycles"], p["v"]
    S_m = v * duty * p["T"]
    stats = {"dz": [], "ext": [], "clamped": 0, "toe_err": 0.0, "swing_min": 0.0, "bind": [],
             "clamp": [], "lift_cap": []}
    # 摆动抬脚上限：两节腿最短只能缩到 |A-B2|，抬太高会在"脚到髋正下方"时折过头
    # （实测后肢会夹紧）。这里按几何算出每腿允许的抬脚高度，取更小值并记录。
    leg_p = {}
    for lg in legs:
        hip_h = (lg.hip_rest.z - lg.toe_rest.z) * s
        ball_h = (lg.ball_rest.z - lg.toe_rest.z) * s
        dmin = abs(lg.A - lg.B2) * s + 0.006
        cap = max(0.0, hip_h - ball_h - sink - dmin)
        p_leg = dict(p)
        p_leg["lift"] = min(p["lift"], cap)
        leg_p[lg.name] = p_leg
        if p_leg["lift"] < p["lift"] - 1e-6:
            stats["lift_cap"].append("%s:lift=%.0fmm (capped from %.0fmm)" % (
                lg.name, p_leg["lift"] * 1000.0, p["lift"] * 1000.0))

    for i in range(n_frames + 1):
        t_T = float(i) / float(n_frames)      # 0..1，末帧 = 首帧
        ph = t_T * 2.0 * math.pi
        accum = {}
        pitch_total = p["pitch"] + math.sin(ph * 2.0) * p["bob_pitch"]
        if spine_mid_name:
            A15.add_rot(arm.pose.bones[spine_mid_name], ax_x, pitch_total, accum)
            A15.add_rot(arm.pose.bones[spine_mid_name], ax_z, math.sin(ph) * p["roll"], accum)
        if head_bone is not None:
            A15.add_rot(head_bone, ax_x, -p["pitch"] * 0.7, accum)
        for k, tn in enumerate(tail):
            tb = arm.pose.bones[tn]
            A15.add_rot(tb, ax_z, math.sin(ph + k * 0.6) * p["tail"] * (1.0 + 0.25 * k), accum)
            A15.add_rot(tb, ax_x, tail_lift_total / float(max(1, len(tail)))
                        + abs(math.sin(ph * 2.0 + k * 0.5)) * p["tail_pitch"] * (1.0 + 0.2 * k) * 0.5,
                        accum)
        A15.apply_rot(arm, accum)
        if root is not None:
            root.location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()

        # ① 髋（dz=0 时）与该腿父骨的姿态朝向
        hips0, parent3 = {}, {}
        for lg in legs:
            pb = arm.pose.bones[lg.name]
            hips0[lg.name] = pb.matrix.translation.copy()
            parent3[lg.name] = (pb.parent.matrix.to_3x3().copy()
                                if pb.parent is not None else Matrix.Identity(3))

        # ② 脚掌目标（支撑相沿反前进方向匀速后退 ⇒ 相对世界静止）
        toe_t, ball_t = {}, {}
        for lg in legs:
            y_m, z_m = foot_offset_m(leg_p[lg.name], t_T + phases[lg.key()])
            toe = lg.foot0 + fwd * (y_m / s) + up * (z_m / s)
            toe_t[lg.name] = toe
            ball_t[lg.name] = toe - lg.q4
        stats.setdefault("btg", {})[i] = dict(ball_t)
        stats.setdefault("tgt", {})[i] = dict(toe_t)

        # ③ 身体竖直位移（armature 单位！）：期望曲线 vs 可达上限，沿世界竖直解二次方程。
        #    sink/bob 是米，先除以 s 换成 armature 单位；dz 始终在 armature 单位里比较。
        dz_des_m = -sink + bob * 0.5 * (1.0 - math.cos(2.0 * math.pi * cycles * t_T))
        dz_des = dz_des_m / s
        dz_max = 1e9
        bind_leg, bind_dz = "", 0.0
        for lg in legs:
            d0 = ball_t[lg.name] - hips0[lg.name]
            rad = reach_k * lg.reach
            proj = d0.dot(up)
            disc = proj * proj - d0.length_squared + rad * rad
            cand = proj + math.sqrt(disc) if disc > 0.0 else proj
            if cand < dz_max:
                dz_max, bind_leg = cand, lg.name
        dz = min(dz_des, dz_max)          # 越往下越容易够到 ⇒ 取更负的那个
        if dz < dz_des - 1e-9 and len(stats["bind"]) < 8:
            stats["bind"].append("t=%.2f|%s|need_dz=%.1fmm|want=%.1fmm" % (
                t_T, bind_leg, dz_max * s * 1000.0, dz_des_m * 1000.0))
        stats["dz"].append(dz * s)
        if root is not None:
            root.location = A15.bone_local_offset(arm, root, Vector((0.0, 0.0, dz * s)))
        bpy.context.view_layer.update()

        # ④ 逐腿解析 IK：b1 指向膝，(b2,b3) 整块朝趾根，b4 保持静止朝向（脚掌平）
        for lg in legs:
            hip = hips0[lg.name] + up * dz
            ball = ball_t[lg.name]
            knee, ratio, clamped = solve_two_link(hip, ball, lg.A, lg.B2, lg.knee_perp)
            stats["ext"].append(ratio)
            if clamped:
                stats["clamped"] += 1
                if len(stats["clamp"]) < 8:
                    stats["clamp"].append("t=%.2f|%s|d=%.4f|hi=%.4f|dz=%.1fmm" % (
                        t_T, lg.name, (ball - hip).length * s, lg.reach * s, dz * s * 1000.0))
            d1 = knee - hip
            dV = ball - knee
            if d1.length < 1e-9 or dV.length < 1e-9:
                continue
            d1.normalize()
            dV.normalize()
            R1 = lg.rest_dir1.rotation_difference(d1).to_matrix()
            RV = lg.rest_dirV.rotation_difference(dV).to_matrix()
            pose3 = [R1 @ lg.rest3[0], RV @ lg.rest3[1], RV @ lg.rest3[2], lg.rest3[3].copy()]
            prev = parent3[lg.name]
            for bi, bn in enumerate(lg.bones):
                pb = arm.pose.bones[bn]
                pb.rotation_mode = "QUATERNION"
                if bi > 0:
                    prev = pose3[bi - 1]
                pb.rotation_quaternion = basis_quat(arm, bn, pose3[bi], prev)
            toe_impl = ball + lg.q4
            stats["toe_err"] = max(stats["toe_err"], (toe_impl - toe_t[lg.name]).length * s)
            if not in_stance(p, t_T + phases[lg.key()]):
                stats["swing_min"] = min(stats["swing_min"], (toe_impl - lg.toe_rest).dot(up) * s)
        if root is not None:
            root.keyframe_insert("location", frame=i)
        for pb in arm.pose.bones:
            A15.key_pose(pb, i)
    for b in stats["bind"]:
        log("bind|%s|%s" % (name, b))

    for c in stats["clamp"]:
        log("clamp|%s|%s" % (name, c))
    for e in stats["lift_cap"]:
        log("liftcap|%s|%s" % (name, e))
    if CHECK:
        arm.animation_data.action = act
        w_toe, w_ball, at = 0.0, 0.0, ""
        for i in range(n_frames + 1):
            bpy.context.scene.frame_set(i)
            for lg in legs:
                b4 = arm.pose.bones[lg.bones[3]]
                ball_a = b4.matrix.translation.copy()
                qloc = lg.rest3[3].inverted() @ lg.q4
                toe_a = ball_a + b4.matrix.to_3x3() @ qloc
                eb = (ball_a - stats["btg"][i][lg.name]).length * s
                et = (toe_a - stats["tgt"][i][lg.name]).length * s
                if max(eb, et) > max(w_toe, w_ball):
                    at = "frame=%d|%s" % (i, lg.name)
                w_ball, w_toe = max(w_ball, eb), max(w_toe, et)
        log("check_toe|%s|ball_err=%.6f m|toe_err=%.6f m|%s" % (name, w_ball, w_toe, at))
        require(w_ball <= 2e-4, "authored_ball_err|%s|%.6f" % (name, w_ball))
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    ext_max = max(stats["ext"]) if stats["ext"] else 0.0
    biss = max(stats["dz"]) < (-sink + bob) - 1e-4
    log("action|%s|N=%d|T=%.4fs|v=%.2f|duty=%.2f|pattern=%s|S=%.4f m|fcurves=%d" % (
        name, n_frames, n_frames / float(FPS), v, duty, p["pattern"], S_m, len(act.fcurves)))
    log("action|%s|sink_des=%.0fmm|dz=[%.1f..%.1f]mm|bob_des=%.0fmm|height_bisected=%s" % (
        name, sink * 1000.0, min(stats["dz"]) * 1000.0, max(stats["dz"]) * 1000.0,
        bob * 1000.0, "yes" if biss else "no"))
    log("action|%s|reach_max=%.4f|clamped=%d|toe_err_max=%.6f m|swing_min_up=%.1fmm" % (
        name, ext_max, stats["clamped"], stats["toe_err"], stats["swing_min"] * 1000.0))
    require(ext_max <= reach_k + 1e-6, "reach_exceeded|%s|%.4f" % (name, ext_max))
    require(stats["clamped"] == 0, "ik_clamped|%s|%d" % (name, stats["clamped"]))
    require(stats["toe_err"] <= 1e-4, "toe_error|%s|%.6f" % (name, stats["toe_err"]))
    return act


# --------------------------------------------------------------------------- 主流程
def build_rig():
    require(os.path.isfile(A15.REF_FBX), "ref_missing|%s" % A15.REF_FBX)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.ops.import_scene.fbx(filepath=A15.REF_FBX)
    # 注意：FBX 导入会把 scene.render.fps 改回文件里的 24 ⇒ 必须在**导入之后**设置，
    # 否则关键帧 0..N 会被当成 24 fps，导出周期变成设计值的 60/24 倍（实测 0.75 s）。
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    log("import|objects=%d|meshes=%d|armatures=%d|bones=%s|fps=%d" % (
        len(bpy.data.objects), len(A15.mesh_objects()), len(arms),
        [len(a.data.bones) for a in arms], bpy.context.scene.render.fps))
    if not require(len(arms) == 1, "armature_count|%d" % len(arms)):
        sys.exit(1)
    arm = arms[0]
    fur, eye = A15.build_materials()
    A15.remap_materials(fur, eye)
    A15.normalize_orientation()
    A15.fit_and_ground(A15.TARGET_LEN)
    obj = A15.join_all("CAT_BODY_001")
    mn, mx = A15.world_bbox()
    groups = A15.classify_bones(arm, mn.z, mx.z)
    s = arm.matrix_world.to_scale().x
    M3i = arm.matrix_world.to_3x3().inverted().normalized()
    fwd = (M3i @ Vector((0.0, 1.0, 0.0))).normalized()
    up = (M3i @ Vector((0.0, 0.0, 1.0))).normalized()
    log("scale|armature=%.6f|fwd_arm=%s|up_arm=%s" % (s, A15.vec(fwd), A15.vec(up)))
    mn2, mx2 = A15.world_bbox()
    log("rest_bbox|min=%s|max=%s" % (A15.vec(mn2), A15.vec(mx2)))
    require(abs(mn2.z) < 0.005, "not_grounded|%.4f" % mn2.z)
    legs = [Leg(arm, lg, s, fwd, up) for lg in groups["legs"]]
    for lg in legs:
        lg.report()
    return arm, obj, groups, legs, s


def main():
    global GLB_OUT, CHECK
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    stage = args[args.index("--stage") + 1] if "--stage" in args else "all"
    if "--out" in args:
        GLB_OUT = args[args.index("--out") + 1].replace(chr(92), "/")
    overrides = parse_set(args[args.index("--set") + 1]) if "--set" in args else {}
    tag = args[args.index("--tag") + 1] if "--tag" in args else ""
    CHECK = "--check" in args
    require(GLB_OUT not in PROTECTED, "refuse_to_overwrite|%s" % GLB_OUT)
    log("start|blender=%s|stage=%s|out=%s|tag=%s" % (bpy.app.version_string, stage, GLB_OUT, tag))

    arm, obj, groups, legs, s = build_rig()
    if stage == "probe":
        log("probe_only|done")
        sys.exit(0 if not A15.failures else 1)

    params = {}
    for clip, d in DEFAULTS.items():
        merged = dict(d)
        merged.update(overrides.get(clip, {}))
        params[clip] = merged
    for clip in ("Idle", "Walk", "Run"):
        p = params[clip]
        log("param|%s|T=%.4f|duty=%.2f|v=%.2f|pattern=%s|sink=%.3f|bob=%.3f|lift=%.3f|reach_k=%.3f" % (
            clip, p["T"], p["duty"], p["v"], p["pattern"], p["sink"], p["bob"], p["lift"],
            p["reach_k"]))
        if p["duty"] < 1.0 - 1e-9:
            log("param|%s|S_stance=%.4f m|D_cycle=%.4f m|D/body_len=%.2f|freq=%.2f Hz" % (
                clip, p["v"] * p["duty"] * p["T"], p["v"] * p["T"],
                p["v"] * p["T"] / A15.TARGET_LEN, 1.0 / p["T"]))

    actions = []
    for clip, n_frames in (("Idle", int(round(2.0 * FPS))),
                           ("Walk", int(round(params["Walk"]["T"] * FPS))),
                           ("Run", int(round(params["Run"]["T"] * FPS)))):
        actions.append(make_gait_action(arm, groups, legs, clip, params[clip], n_frames))
    A15.stash_nla(arm, actions)

    obj.data.calc_loop_triangles()
    tris = len(obj.data.loop_triangles)
    mn, mx = A15.world_bbox()
    log("check|tris=%d|slots=%d|bones=%d|dims=%s|min_z=%.4f" % (
        tris, len(obj.data.materials), len(arm.data.bones), A15.vec(mx - mn), mn.z))
    require(tris <= A15.TRI_BUDGET, "tri_budget|%d" % tris)
    require(len(obj.data.materials) == 2, "slot_count|%d" % len(obj.data.materials))

    A15.GLB_OUT = GLB_OUT
    A15.export_glb()
    A15.report_glb_animations()
    log("done|tris=%d|actions=%d|failures=%d" % (tris, len(actions), len(A15.failures)))
    sys.exit(0 if not A15.failures else 1)


if __name__ == "__main__":
    main()
