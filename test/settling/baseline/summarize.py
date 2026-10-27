#!/usr/bin/env python3 -I
"""Summarizes the raw baseline samples in raw/: CPU percent from the cumulative CPU time,
RSS range from ps, and physical footprint from each vmmap summary. Prints a table."""
import os, re, sys

raw = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")
names = dict(l.split()[::-1] for l in open(os.path.join(raw, "pids.txt")) if l.strip())

def secs(t):  # ps time is [[hh:]mm:]ss.cc
    parts = [float(x) for x in t.split(":")]
    s = 0.0
    for p in parts:
        s = s * 60 + p
    return s

def clock(t):
    h, m, s = (int(x) for x in t.split(":"))
    return h * 3600 + m * 60 + s

rows = {}
for line in open(os.path.join(raw, "ps.txt")).readlines()[1:]:
    f = line.split()
    if len(f) < 5:
        continue
    rows.setdefault(f[1], []).append((clock(f[0]), int(f[2]), secs(f[3])))

foot = {}
for stage in ("start", "middle", "end"):
    p = os.path.join(raw, f"vmmap-{stage}.txt")
    if not os.path.exists(p):
        continue
    pid = None
    for line in open(p):
        m = re.match(r"=== (\S+) (\d+)", line)
        if m:
            pid = m.group(2)
        m = re.match(r"Physical footprint:\s+(\S+)", line)
        if m and pid:
            foot.setdefault(pid, {})[stage] = m.group(1)
        m = re.match(r"Physical footprint \(peak\):\s+(\S+)", line)
        if m and pid:
            foot.setdefault(pid, {})["peak"] = m.group(1)

print(f"{'app':<11} {'samples':>7} {'minutes':>7} {'cpu s':>7} {'cpu %':>6} {'rss MB min-max':>15} {'footprint start/mid/end':>24} {'peak':>7}")
quiet = []
for pid, r in rows.items():
    r.sort()
    wall = r[-1][0] - r[0][0]
    cpu = r[-1][2] - r[0][2]
    rss = [x[1] / 1024 for x in r]
    fp = foot.get(pid, {})
    print(f"{names.get(pid, pid):<11} {len(r):>7} {wall / 60:>7.1f} {cpu:>7.2f} {100 * cpu / wall:>6.2f} "
          f"{min(rss):>7.1f}-{max(rss):<7.1f} {fp.get('start', '?'):>8}/{fp.get('middle', '?')}/{fp.get('end', '?'):<7} {fp.get('peak', '?'):>7}")
    # The quietest 5 minutes: idle cost between WorkForest's scans, which run every 5 to 6 minutes.
    best = None
    for i in range(len(r)):
        for j in range(i, len(r)):
            if r[j][0] - r[i][0] >= 300:
                c = (r[j][2] - r[i][2]) / (r[j][0] - r[i][0])
                if best is None or c < best[0]:
                    best = (c, r[i][0], r[j][0])
                break
    if best:
        hm = lambda t: f"{t // 3600:02d}:{t % 3600 // 60:02d}:{t % 60:02d}"
        quiet.append(f"{names.get(pid, pid):<11} quietest 5 min {hm(best[1])}-{hm(best[2])} UTC: {100 * best[0]:.2f} % CPU")
print()
print("\n".join(quiet))
