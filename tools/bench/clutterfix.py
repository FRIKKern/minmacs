#!/usr/bin/env python3
"""Makes the clutter fixture of issue #54: about 20 GB that du sees, at little real disk cost.

Usage: clutterfix.py <clutter root> <bench roots> [gigabytes]
<clutter root> stands in for / and must lie inside $MINMACS_HOME. <bench roots> is what test/git/benchfix.py made.
It refuses, with exit status 3, when the volume has under 50 GB free, before it writes anything.

  home/Library/Developer/Xcode/DerivedData   40 folders, each with an info.plist that names a fixture repo and
                                             8 APFS clones of one base file. The clones hold the gigabytes: du counts
                                             each in full, and they share one copy of the base file's blocks.
                                             Each folder also holds one sparse file of 1 GB with one page written.
  home/Library/Caches/pip, go-build, .npm    2,000 small files each, in 20 folders
  <repo>/node_modules                        300 small files in each of the fixture's main checkouts, with a
                                             package.json beside it. Both go in the repo's .git/info/exclude,
                                             so git status stays as benchfix.py left it.
Prints what it made as JSON, with the free space before and after.
"""
import ctypes
import json
import os
import sys

FLOOR = 50e9
root, bench = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
target = float(sys.argv[3]) * 1e9 if len(sys.argv) > 3 else 20e9
home_env = os.environ.get("MINMACS_HOME", "")
os.makedirs(root, exist_ok=True)
if not home_env or not (os.path.realpath(root) + "/").startswith(os.path.realpath(home_env).rstrip("/") + "/"):
    sys.exit("clutterfix: the clutter root must lie inside MINMACS_HOME")


def free(path):
    s = os.statvfs(path)
    return s.f_bavail * s.f_frsize


before = free(root)
if before < FLOOR:
    print("clutterfix: %.1f GB free, under the 50 GB floor; nothing made" % (before / 1e9), file=sys.stderr)
    sys.exit(3)

libc = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
libc.clonefile.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint32]


def clone(src, dst):
    if libc.clonefile(src.encode(), dst.encode(), 0) != 0:
        e = ctypes.get_errno()
        raise OSError(e, "clonefile %s: %s" % (dst, os.strerror(e)))


home = os.path.join(root, "home")
dd = os.path.join(home, "Library/Developer/Xcode/DerivedData")
os.makedirs(dd, exist_ok=True)
folders, per = 40, 8
size = -(-int(target / (folders * per)) // (1 << 20)) * (1 << 20)   # rounded up to a MiB
base = os.path.join(root, "clone-base.bin")
chunk = os.urandom(1 << 20)
with open(base, "wb") as f:
    for _ in range(size // len(chunk)):
        f.write(chunk)
repos = sorted(d for d in os.listdir(bench) if d.startswith("r") and os.path.isdir(os.path.join(bench, d, ".git")))
clones = sparse = 0
for i in range(folders):
    d = os.path.join(dd, "App%d-fixture%02dhash" % (i, i))
    obj = os.path.join(d, "Build/Intermediates.noindex")
    os.makedirs(obj, exist_ok=True)
    repo = os.path.join(bench, repos[i % len(repos)]) if repos else d
    with open(os.path.join(d, "info.plist"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>WorkspacePath</key>'
                '<string>%s/App.xcodeproj</string></dict></plist>\n' % repo)
    for j in range(per):
        clone(base, os.path.join(obj, "part%d.o" % j))
        clones += 1
    with open(os.path.join(d, "Build/sparse.dmg"), "wb") as f:
        f.truncate(1 << 30)
        f.seek((1 << 30) - 4096)
        f.write(b"x" * 4096)
        sparse += 1
small = 0
for cache in ("Library/Caches/pip/http", "Library/Caches/go-build", ".npm/_cacache"):
    for k in range(20):
        d = os.path.join(home, cache, "%02x" % k)
        os.makedirs(d, exist_ok=True)
        for n in range(100):
            with open(os.path.join(d, "e%03d" % n), "w") as f:
                f.write("cache entry %d %d\n" % (k, n))
            small += 1
modules = 0
for r in repos:
    repo = os.path.join(bench, r)
    with open(os.path.join(repo, "package.json"), "w") as f:
        f.write('{"name": "%s", "private": true}\n' % r)
    for p in range(30):
        d = os.path.join(repo, "node_modules", "pkg%02d" % p, "lib")
        os.makedirs(d, exist_ok=True)
        for n in range(10):
            with open(os.path.join(d, "m%d.js" % n), "w") as f:
                f.write("module.exports = %d;\n" % n)
            modules += 1
    with open(os.path.join(repo, ".git/info/exclude"), "a") as f:
        f.write("node_modules/\npackage.json\n")
os.sync()
after = free(root)
print(json.dumps({"root": root, "cloneBytes": size, "clones": clones, "cloneGB": round(clones * size / 1e9, 2),
                  "sparseFiles": sparse, "smallFiles": small, "nodeModulesFiles": modules, "repos": len(repos),
                  "freeBeforeGB": round(before / 1e9, 2), "freeAfterGB": round(after / 1e9, 2)}))
