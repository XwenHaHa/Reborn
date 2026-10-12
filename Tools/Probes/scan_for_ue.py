# Reborn / T001 - full-volume filename scan for Unreal Engine executables
#
# Why this exists: ad-hoc PowerShell recursive enumeration failed on this machine
# (Get-ChildItem -Include silently does not filter by filename; -LiteralPath -Recurse
# aborts on special paths; 'dir /s /b' exceeds 10 min on a 466 GB volume; where.exe /r
# with a trailing-backslash root never completes). The Windows Search index is NOT a
# substitute: on this machine it covers only C: and misses KNOWN-present files
# (blender.exe at D:\SoftWare\Blender\ was absent from the index). So a real,
# deterministic filesystem walk is required to state anything about UE presence.
#
# Usage:
#   python E:\Reborn\Tools\Probes\scan_for_ue.py            # scans C:, D:, E:
#   python E:\Reborn\Tools\Probes\scan_for_ue.py D E        # scans selected volumes
#
# Read-only: opens directories only, never modifies anything.

import os
import sys
import time

TARGETS = {
    "unrealeditor.exe",
    "unrealeditor-cmd.exe",
    "unrealbuildtool.exe",
    "unrealserver.exe",
    "runuat.bat",
}

# Directory names pruned during the walk. Unreal Engine is never extracted inside a
# JavaScript dependency tree, a VCS object store, or a package-manager cache, so
# descending into these only burns time on this machine (the node_modules/.pnpm trees
# on D: alone account for hundreds of thousands of directories).
#
# Pruning is a deliberate, DISCLOSED reduction in coverage: it is sound for locating an
# *engine installation* (which always sits at a normal install root), but it means this
# scan must not be described as an exhaustive byte-for-byte enumeration of every path.
PRUNE_DIRS = {
    "node_modules",
    ".pnpm-store",
    ".git",
    ".hg",
    ".svn",
    "__pycache__",
    ".venv",
    "venv",
    ".cache",
    "site-packages",
    "dist-packages",
    "$recycle.bin",
    "system volume information",
}


def scan(volume: str) -> list:
    root = volume.rstrip("\\/") + "\\"
    hits = []
    dirs_seen = 0
    pruned = 0
    started = time.time()
    last_report = started

    for dirpath, dirnames, filenames in os.walk(root, onerror=lambda e: None):
        dirs_seen += 1

        # Prune in place so os.walk does not descend (see PRUNE_DIRS rationale).
        keep = []
        for d in dirnames:
            if d.lower() in PRUNE_DIRS:
                pruned += 1
            else:
                keep.append(d)
        dirnames[:] = keep

        for name in filenames:
            if name.lower() in TARGETS:
                hits.append(os.path.join(dirpath, name))
                print("FOUND|{0}".format(hits[-1]), flush=True)

        now = time.time()
        if now - last_report >= 20:
            last_report = now
            print(
                "PROGRESS|{0}|dirs={1}|pruned={2}|hits={3}|elapsed={4:.0f}s|at={5}".format(
                    root, dirs_seen, pruned, len(hits), now - started, dirpath
                ),
                flush=True,
            )

    print(
        "RESULT|{0}|dirs={1}|pruned={2}|hits={3}|elapsed={4:.0f}s".format(
            root, dirs_seen, pruned, len(hits), time.time() - started
        ),
        flush=True,
    )
    return hits


def main() -> int:
    args = sys.argv[1:]
    volumes = [a if a.endswith(":") else a + ":" for a in args] or ["C:", "D:", "E:"]
    all_hits = []
    for vol in volumes:
        if not os.path.isdir(vol + "\\"):
            print("SKIP|{0}|not-present".format(vol), flush=True)
            continue
        print("SCAN-START|{0}".format(vol), flush=True)
        all_hits += scan(vol)

    print("TOTAL-HITS|{0}".format(len(all_hits)), flush=True)
    for h in all_hits:
        print("HIT|{0}".format(h), flush=True)
    if not all_hits:
        print("CONCLUSION|no-unreal-executable-found-on:{0}".format(",".join(volumes)), flush=True)
    print("SCAN-COMPLETE", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
