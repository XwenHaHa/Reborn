"""T055：生成 4 个**自有程序化**行动音效（不下载任何第三方音频）。

为什么自己做：项目至今**没有任何音频设施**（0 个 `AudioStreamPlayer`、0 个音频文件）。
第三方音效要么需授权下载、要么许可不明；这 4 个音是**确定性合成**的（固定种子、
纯 Python 写 WAV），许可归本仓库，不进 `THIRD_PARTY_NOTICES`。

产出（44.1 kHz / 16-bit / 单声道）：
  footstep_walk.wav  0.12 s  低沉短促的脚步（噪声脉冲 + 指数衰减）
  footstep_run.wav   0.10 s  更硬更亮的一步（更快的起音 + 高频更多）
  attack.wav         0.22 s  出爪的"咻"（下扫噪声 + 起音 click）
  hurt.wav           0.26 s  受伤短叫（下滑双音 + 轻微颤音）

用法：
  python E:/Reborn/Tools/make_audio_t055.py --out E:/Reborn/Game/Reborn/assets/audio
"""
import argparse
import math
import os
import random
import struct
import wave

SR = 44100
SEED = 20261110


def _env(n, attack_s, decay_s):
    """线性起音 + 指数衰减包络（0..1）。"""
    a = max(1, int(attack_s * SR))
    out = []
    for i in range(n):
        if i < a:
            v = i / a
        else:
            t = (i - a) / SR
            v = math.exp(-t / max(1e-4, decay_s))
        out.append(v)
    return out


def _noise(n, rng, lp=0.0):
    """白噪声，可选一阶低通（lp=0 全通，越大越闷）。"""
    out = []
    prev = 0.0
    for _ in range(n):
        w = rng.uniform(-1.0, 1.0)
        if lp > 0.0:
            prev = prev * lp + w * (1.0 - lp)
            w = prev
        out.append(w)
    return out


def footstep(path, dur, decay, lp, gain, click=0.0):
    n = int(dur * SR)
    rng = random.Random(SEED + int(dur * 1000))
    noise = _noise(n, rng, lp)
    env = _env(n, 0.002, decay)
    samples = []
    for i in range(n):
        v = noise[i] * env[i]
        if click > 0.0 and i < int(0.004 * SR):
            v += click * math.sin(2.0 * math.pi * 900.0 * i / SR) * (1.0 - i / (0.004 * SR))
        samples.append(max(-1.0, min(1.0, v * gain)))
    _write(path, samples)


def attack(path, dur=0.22, gain=0.85):
    n = int(dur * SR)
    rng = random.Random(SEED + 7)
    noise = _noise(n, rng, 0.35)
    env = _env(n, 0.001, 0.055)
    samples = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        # 下扫的"咻"：中心频率 2.4 kHz → 700 Hz
        f = 2400.0 * math.exp(-t / 0.09) + 700.0
        phase += 2.0 * math.pi * f / SR
        tone = math.sin(phase) * 0.45
        v = (noise[i] * 0.8 + tone) * env[i]
        samples.append(max(-1.0, min(1.0, v * gain)))
    _write(path, samples)


def hurt(path, dur=0.26, gain=0.9):
    n = int(dur * SR)
    env = _env(n, 0.006, 0.09)
    samples = []
    p1 = 0.0
    p2 = 0.0
    for i in range(n):
        t = i / SR
        f1 = 620.0 * math.exp(-t / 0.18) + 210.0
        f2 = f1 * 2.02
        vib = 1.0 + 0.012 * math.sin(2.0 * math.pi * 11.0 * t)
        p1 += 2.0 * math.pi * f1 * vib / SR
        p2 += 2.0 * math.pi * f2 * vib / SR
        v = (math.sin(p1) * 0.75 + math.sin(p2) * 0.22) * env[i]
        samples.append(max(-1.0, min(1.0, v * gain)))
    _write(path, samples)


def _write(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("AUDIO|%s|bytes=%d|dur=%.3f" % (os.path.basename(path), os.path.getsize(path),
                                          len(samples) / float(SR)), flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="E:/Reborn/Game/Reborn/assets/audio")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    footstep(os.path.join(args.out, "footstep_walk.wav"), 0.12, 0.030, 0.55, 0.55, click=0.25)
    footstep(os.path.join(args.out, "footstep_run.wav"), 0.10, 0.022, 0.30, 0.85, click=0.45)
    attack(os.path.join(args.out, "attack.wav"))
    hurt(os.path.join(args.out, "hurt.wav"))
    print("AUDIO|done", flush=True)
    return 0


raise SystemExit(main())
