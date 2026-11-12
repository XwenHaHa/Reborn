#!/usr/bin/env python3
"""T043：PCK 包内文件清单审计。

用法：
  python Tools/t043_pck_audit.py <pack.pck> [--deny tests/ --deny references/ ...]

退出码：0 = 无泄露；1 = 发现禁止路径/解析失败。
只读；不修改包。
"""
import argparse
import struct
import sys


def read_u32(data, off):
    return struct.unpack_from("<I", data, off)[0], off + 4


def read_u64(data, off):
    return struct.unpack_from("<Q", data, off)[0], off + 8


def parse_pck(path):
    """Godot 4.7 的 PCK：头部给出 file_base 与 dir_offset（目录块在文件尾部），
    目录块自身以 u32 条目数开头，每条目为 u32 名称长度 + 名称 + u64 偏移 +
    u64 大小 + 16 字节 md5 + u32 flags。（实测 2026-11-05，旧解析把 3506 当成条目数，
    与实际 409 条不符。）"""
    with open(path, "rb") as f:
        data = f.read()
    magic, off = read_u32(data, 0)
    if magic != 0x43504447:
        raise ValueError("不是 PCK（magic=0x%08x）" % magic)
    fmt, off = read_u32(data, off)
    major, off = read_u32(data, off)
    minor, off = read_u32(data, off)
    patch, off = read_u32(data, off)
    flags, off = read_u32(data, off)
    file_base, off = read_u64(data, off)
    dir_offset, off = read_u64(data, off)
    count, off = read_u32(data, dir_offset)
    entries = []
    for _ in range(count):
        name_len, off = read_u32(data, off)
        name = data[off:off + name_len].decode("utf-8", "replace").rstrip("\x00")
        off += name_len
        offset, off = read_u64(data, off)
        size, off = read_u64(data, off)
        off += 16  # md5
        eflags, off = read_u32(data, off)
        entries.append((name, offset, size, eflags))
    return {
        "format": fmt,
        "engine": "%d.%d.%d" % (major, minor, patch),
        "flags": flags,
        "file_base": file_base,
        "count": count,
        "entries": entries,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pck")
    ap.add_argument("--deny", action="append", default=[])
    ap.add_argument("--allow-prefix", action="append", default=[])
    # T062：候选版要**证明必需内容真的在包里**（不只是"没泄露"）
    ap.add_argument("--require", action="append", default=[])
    ap.add_argument("--list", action="store_true", help="打印包内条目（证据用）")
    args = ap.parse_args()
    deny = args.deny or ["tests/", "references/", "Docs/", ".uid", "tool_capture_", "tool_make_"]
    try:
        info = parse_pck(args.pck)
    except Exception as exc:  # 解析失败也是审计失败
        print("AUDIT|FAIL|parse|%s" % exc)
        return 1
    names = [name for name, _off, _size, _flags in info["entries"]]
    leak = []
    for name in names:
        # 以 "/" 结尾的规则只匹配**根级目录前缀**（避免把 assets/tests/ 误判成项目 tests/）；
        # 其余规则（.uid、tool_capture_ 等）按子串匹配。
        hit = any((name.startswith(p) if p.endswith("/") else p in name) for p in deny)
        if hit:
            leak.append(name)
    print("AUDIT|pack=%s|format=%d|engine=%s|files=%d|leak=%d" % (
        args.pck, info["format"], info["engine"], info["count"], len(leak)))
    if args.list:
        for name in sorted(names):
            print("ENTRY|%s" % name)
    for name in leak:
        print("LEAK|%s" % name)
    if leak:
        return 1
    missing = []
    for prefix in args.require:
        if not any(n == prefix or n.startswith(prefix) for n in names):
            missing.append(prefix)
    for prefix in missing:
        print("MISSING|%s" % prefix)
    if missing:
        print("AUDIT|FAIL|missing_required=%d" % len(missing))
        return 1
    print("AUDIT|PASS|no_denied_paths|required_ok=%d" % len(args.require))
    return 0


if __name__ == "__main__":
    sys.exit(main())
