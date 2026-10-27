#!/usr/bin/env python3 -I
"""Is ~/.claude/sessions/<pid>.json stable across Claude Code releases, and what does `shell` mean? Read-only.

Part 1 reads every status file and groups the keys and status values by Claude Code version.
Part 2 reads every installed Claude Code binary and looks for the code that writes the file:
the status list it accepts, the line that turns idle into shell, and the task check behind it.
It never opens the .key files beside the status files.
"""
import collections, glob, json, mmap, os, re, sys

home = os.path.expanduser("~")
sessions = os.environ.get("CLAUDE_SESSIONS", os.path.join(home, ".claude/sessions"))
versions = os.environ.get("CLAUDE_VERSIONS", os.path.join(home, ".local/share/claude/versions"))

print("== status files in", sessions)
by = collections.defaultdict(list)
for f in sorted(glob.glob(os.path.join(sessions, "*.json"))):
    try:
        j = json.load(open(f))
    except Exception as e:
        print("unreadable", os.path.basename(f), e)
        continue
    by[j.get("version")].append(j)
allkeys = set()
for v in sorted(by, key=lambda s: [int(x) for x in re.findall(r"\d+", s or "0")]):
    rows = by[v]
    keys = set().union(*(r.keys() for r in rows))
    allkeys |= keys
    print(f"{v}: {len(rows)} files, status {dict(collections.Counter(r.get('status') for r in rows))}")
    print("   keys:", ",".join(sorted(keys)))
common = set.intersection(*(set(r.keys()) for rs in by.values() for r in rs)) if by else set()
print("keys in every file:", ",".join(sorted(common)))

# The minified names change per build, so each pattern matches the shape of the code, not its names.
pats = {
    "status list": rb'\["busy","shell","idle","waiting"\]',
    "idle to shell": rb'[A-Za-z_$]{1,4}==="idle"&&[A-Za-z_$]{1,4}\?"shell":[A-Za-z_$]{1,4}',
    "running bash task": rb'return [A-Za-z_$]{1,4}\.type==="local_bash"&&![A-Za-z_$]{1,4}\([A-Za-z_$]{1,4}\.status\)',
    "status map from SDK": rb'\{running:"busy",requires_action:"waiting",idle:"idle"\}',
    "waiting reasons": rb'"input needed":"permission prompt"',
    "busy or shell is working": rb'==="busy"\|\|[A-Za-z_$]{1,4}==="shell"',
}
print("\n== binaries in", versions)
for b in sorted(glob.glob(os.path.join(versions, "*")), key=lambda s: [int(x) for x in re.findall(r"\d+", os.path.basename(s))]):
    with open(b, "rb") as fh:
        m = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
        found = {k: len(re.findall(p, m)) for k, p in pats.items()}
        ks = [k for k in ("statusUpdatedAt", "messagingSocketPath", "procStart", "peerProtocol", "waitingFor") if m.find(k.encode()) >= 0]
        print(os.path.basename(b), " ".join(f"{k}={n}" for k, n in found.items()), "| keys in binary:", ",".join(ks))
