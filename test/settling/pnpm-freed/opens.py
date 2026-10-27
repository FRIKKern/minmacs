#!/usr/bin/env python3 -I
"""Times one open and close per file against one lstat per file, over the first N files under a root.
It shows what an on-access scanner adds to each open. Read-only: files are opened for reading and closed.
Usage: opens.py <root> [n]    n defaults to 3000"""
import os, sys, time

root = sys.argv[1]
n = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
paths = []
for d, _, files in os.walk(root):
    for f in files:
        paths.append(os.path.join(d, f))
        if len(paths) >= n:
            break
    if len(paths) >= n:
        break

# lstat first, so the open pass cannot be the one that warms the metadata cache.
t = time.perf_counter()
for p in paths:
    os.lstat(p)
st = time.perf_counter() - t

t = time.perf_counter()
for p in paths:
    fd = os.open(p, os.O_RDONLY)
    os.close(fd)
op = time.perf_counter() - t

print(f"files {len(paths)}  lstat {st:.3f} s  open {op:.2f} s, {op / len(paths) * 1000:.2f} ms per open")
