#!/usr/bin/env python3 -I
"""Redacts saved results before they go into this public repo. It rewrites files in place:
the home folder becomes ~, and every repo under ~/Documents/GitHub other than the MinMacs family
becomes repo-NN, numbered in order of first appearance across the files given.
The folder right below such a repo is often a worktree named after a client task, so it becomes
dir-NN. A hidden folder such as .claude stays, since tools name those, not people.
A file that was redacted before keeps its repo-NN labels. Run it again after the rule changes.
Usage: redact.py <file>..."""
import os, re, sys

home = os.path.expanduser("~")
keep = {"minmacs", "locohost", "workforest", "insomnia", "noo-noo"}
names, dirs = {}, {}
pat = re.compile(r"~/Documents/GitHub/([^/\s:]+)(/[^/\s:]+)?")
done = re.compile(r"(?:repo|dir)-\d\d")

def label(m):
    n, sub = m.group(1), m.group(2) or ""
    if n in keep:
        return m.group(0)
    if not done.fullmatch(n):
        n = names.setdefault(n, f"repo-{len(names) + 1:02d}")
    s = sub[1:]
    if s and not s.startswith(".") and not done.fullmatch(s):
        sub = "/" + dirs.setdefault(s, f"dir-{len(dirs) + 1:02d}")
    return f"~/Documents/GitHub/{n}{sub}"

for p in sys.argv[1:]:
    s = open(p, errors="replace").read()
    s = s.replace(home, "~").replace("/Users/USER", "~")
    s = pat.sub(label, s)
    open(p, "w").write(s)
print(f"redacted {len(sys.argv) - 1} files, {len(names)} repo names, {len(dirs)} folder names")
