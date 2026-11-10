"""T056：生成环境音（自有合成，可无缝循环）—— 溪流 + 风。

为什么自己合成：第三方环境音需授权下载、循环点常常听得出来；这里用**周期性构造**
（整数频率 + 循环边界交叉淡化）保证首尾相接处连续，Godot 侧再设 `LOOP_FORWARD`。

产出（44.1 kHz / 16-bit / 单声道）：
  creek_loop.wav  4.0 s  溪流：多层带通噪声 + 缓慢起伏（水面涌动）
  wind_loop.wav   6.0 s  风：极低频噪声 + 缓慢包络

用法：
  python E:/Reborn/Tools/make_audio_t056.py --out E:/Reborn/Game/Reborn/assets/audio
"""
import argparse
import math
import os
import random
import struct
import wave

SR = 44100
SEED = 20261111


def _crossfade_loop(samples, fade_s=0.25):
    """把尾部淡入到头部，保证循环点连续（不是简单截断）。"""
    n = len(samples)
    f = min(int(fade_s * SR), n // 4)
    if f <= 0:
        return samples
    out = list(samples)
    for i in range(f):
        t = i / f
        # 尾部第 i 个样本与头部第 i 个样本线性交叉
        a = samples[i]
        b = samples[n - f + i]
        out[i] = a * t + b * (1.0 - t)
        out[n - f + i] = b * (1.0 - t) + a * t
    return out


def creek(path, dur=4.0, gain=0.62):
    n = int(dur * SR)
    rng = random.Random(SEED + 1)
    samples = []
    lp1 = 0.0
    lp2 = 0.0
    for i in range(n):
        t = i / SR
        # 两层低通白噪声（水流主体 + 细碎水花）
        w = rng.uniform(-1.0, 1.0)
        lp1 = lp1 * 0.86 + w * 0.14
        lp2 = lp2 * 0.55 + w * 0.45
        body = lp1 * 0.85 + lp2 * 0.25
        # 周期性涌动（整数频率 → 循环天然连续）
        surge = 1.0 + 0.22 * math.sin(2.0 * math.pi * 0.5 * t) + 0.12 * math.sin(2.0 * math.pi * 1.0 * t + 0.7)
        samples.append(body * surge)
    samples = _crossfade_loop(samples, 0.35)
    peak = max(1e-6, max(abs(s) for s in samples))
    _write(path, [max(-1.0, min(1.0, s / peak * gain)) for s in samples])


def wind(path, dur=6.0, gain=0.30):
    n = int(dur * SR)
    rng = random.Random(SEED + 2)
    samples = []
    lp = 0.0
    for i in range(n):
        t = i / SR
        w = rng.uniform(-1.0, 1.0)
        lp = lp * 0.97 + w * 0.03          # 很低的低通 → 风底噪
        gust = 0.55 + 0.45 * math.sin(2.0 * math.pi * (1.0 / dur) * t)  # 一个循环一个起伏
        samples.append(lp * gust)
    samples = _crossfade_loop(samples, 0.5)
    peak = max(1e-6, max(abs(s) for s in samples))
    _write(path, [max(-1.0, min(1.0, s / peak * gain)) for s in samples])


def _write(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print("AMBIENT|%s|bytes=%d|dur=%.3f" % (os.path.basename(path), os.path.getsize(path),
                                            len(samples) / float(SR)), flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="E:/Reborn/Game/Reborn/assets/audio")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    creek(os.path.join(args.out, "creek_loop.wav"))
    wind(os.path.join(args.out, "wind_loop.wav"))
    print("AMBIENT|done", flush=True)
    return 0


raise SystemExit(main())
