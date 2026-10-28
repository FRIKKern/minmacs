#!/usr/bin/env python3 -I
"""Writes the day fixture of issue #36: what the graph holds at each hourly review of one day, for all five experts.
Usage: dayfix.py <out.json>

The day is made, not taken from a real Mac, with the counts research F measured on the research Mac:
91 linked worktrees in 10 repos, 58 percent of them merged in some way, about 30 with a commit in the day and about
20 made in the day, LocoHost's 5 servers with 2 shared services and two dev servers in one worktree, and the last review's mix of keeps and unsure ones.
Each tick lists every finding as the expert builds it: id, instance key, owner, the expert's facts, its fingerprint
in the expert's own format, its keep reasons and whether it has a proposal. A time is {"$ago": seconds before the tick},
so day.m turns it into a date that is that old when the tick is replayed. The worktrees and sessions of each tick feed
MMReviewContext. Paths live under /Volumes/rvday, which does not exist, so nothing reads them.
The random numbers come from one seeded generator, so the same script writes the same bytes."""
import hashlib, json, random, sys

R = random.Random(36)
DAY, TICKS = 86400, 24
ROOT = "/Volumes/rvday"
REPOS = ["alpha-web", "beta-api", "gamma-cli", "delta-docs", "epsilon-app", "zeta-sdk", "eta-infra", "theta-site", "iota-tools", "kappa-lab"]
D, H, M = 86400, 3600, 60

def sha(*parts):
    return hashlib.sha1("/".join(str(p) for p in parts).encode()).hexdigest()

def U(*parts):
    """A number from 0 to 1 fixed by its parts, so a choice made for one burst holds at every tick."""
    return int(sha(*parts)[:8], 16) / 2.0 ** 32

def ago(tick_at, t):
    return None if t is None else {"$ago": max(0, int(tick_at - t))}

# -------- WorkForest: trees with bursts of work --------

class Tree:
    def __init__(self, i, born):
        self.i = i
        self.repo = REPOS[i % len(REPOS)]
        self.name = "task-%03d" % i
        self.path = "%s/%s-worktrees/%s" % (ROOT, self.repo, self.name)
        self.branch = "agent/" + self.name
        self.born = born                       # replay seconds, negative when made before the day
        self.version = 0
        self.removed_at = None
        self.merged, self.upstream, self.on_remote = None, "origin/" + self.branch, True
        self.unpushed, self.not_in_default, self.dirty, self.untracked = 0, 0, 0, 0
        self.processes, self.locked, self.protected = [], False, False
        self.disk = R.randint(40, 1500) << 20
        self.cache = int(self.disk * R.uniform(0.2, 0.8))
        self.files = R.randint(800, 40000)
        self.bursts = []                       # (start, end) in replay seconds
        self.merge_at = None
        self.session = None                    # (started, last active)

    def head(self):
        return sha(self.path, self.version)

def make_trees():
    trees = []
    for i in range(91):
        quiet = R.choice([R.uniform(0.3, 3), R.uniform(3, 14), R.uniform(14, 60)]) * D
        t = Tree(i, -quiet - R.uniform(0, 10) * D)
        r = R.random()
        t.merged = "ancestor" if r < 0.30 else "squash" if r < 0.47 else "patch" if r < 0.57 else None
        if t.merged:
            t.upstream = "gone" if R.random() < 0.7 else t.upstream
            t.not_in_default = 0 if t.merged == "ancestor" else R.randint(1, 6)
        else:
            t.not_in_default = R.randint(1, 12)
            if R.random() < 0.3: t.unpushed, t.on_remote = R.randint(1, 5), False
            if R.random() < 0.2: t.upstream = "none"
        if R.random() < 0.08: t.dirty = R.randint(1, 6)
        if R.random() < 0.05: t.untracked = R.randint(1, 3)
        if R.random() < 0.03: t.processes = ["node vite"]
        if i == 7: t.locked = True
        if i == 11: t.protected, t.branch = True, "release"
        t.last_commit = -quiet * R.uniform(1.0, 1.3)
        t.touched = -quiet
        if R.random() < 0.85: t.session = (-quiet - R.uniform(1, 6) * H, -quiet * R.uniform(0.9, 1.0))
        trees.append(t)
    # About 30 trees get work in the day: the ones quiet a few days or less, plus the new ones below.
    young = [t for t in trees if not t.merged and t.touched > -5 * D]
    for t in R.sample(young, min(12, len(young))):
        t.bursts = sorted((s, s + R.uniform(20, 120) * M) for s in (R.uniform(0, DAY - 2 * H) for _ in range(R.randint(1, 3))))
    for k in range(20):
        born = R.uniform(0, DAY - 3 * H)
        t = Tree(91 + k, born)
        t.not_in_default = 0
        t.upstream, t.on_remote = "none", False
        t.last_commit = None
        t.touched = born
        t.bursts = [(born, born + R.uniform(30, 150) * M)]
        if R.random() < 0.5: t.bursts.append((born + R.uniform(3, 6) * H, born + R.uniform(6, 8) * H))
        trees.append(t)
    # Eight trees with work merge after their last burst. Ten old merged trees are removed by the person in the day.
    for t in R.sample([t for t in trees if t.bursts], 8):
        t.merge_at = t.bursts[-1][1] + R.uniform(1, 4) * H
    for t in R.sample([t for t in trees if t.merged and t.touched < -14 * D], 10):
        t.removed_at = R.uniform(2 * H, DAY - H)
    return trees

def tree_at(t, now):
    """The tree's state at now: its bursts so far have run, each ending in a commit."""
    version, dirty, unpushed, live = 0, t.dirty, t.unpushed, False
    last_commit, touched, session, on_remote, upstream = t.last_commit, t.touched, t.session, t.on_remote, t.upstream
    merged, not_in_default = t.merged, t.not_in_default
    for (s, e) in t.bursts:
        if s > now: break
        start = session[0] if session and s - session[1] < 6 * H else s
        if now < e:
            live = U(t.path, s, now, "live") < 0.7
            dirty = max(dirty, 1 + int((now - s) / (20 * M)))
            touched, session = now - U(t.path, now, "t") * 5 * M, (start, now - U(t.path, now, "s") * 4 * M)
        else:
            version += 1
            dirty = 0 if U(t.path, s, "dirty") < 0.85 else 1
            last_commit, touched, session = e, e, (start, e)
            not_in_default += 1
            if U(t.path, s, "push") < 0.5: unpushed, on_remote = 0, True; upstream = "origin/" + t.branch
            else: unpushed += 1; on_remote = False
    if t.merge_at is not None and now >= t.merge_at:
        merged, upstream, unpushed, on_remote, dirty, not_in_default = "squash", "gone", 0, True, 0, 1
    t.version = version
    return dict(version=version, dirty=dirty, unpushed=unpushed, live=live, last_commit=last_commit, touched=touched,
                session=session, on_remote=on_remote, upstream=upstream, merged=merged, not_in_default=not_in_default)

def wf_bucket(age):
    return "h" if age < H else "d" if age < D else "w" if age < 7 * D else "m" if age < 30 * D else "q"

def wf_finding(t, now):
    st = tree_at(t, now)
    head = sha(t.path, st["version"])
    sess = None
    if st["session"]:
        sess = {"agent": "Claude Code", "harness": "claude-code", "live": st["live"], "title": "Work on %s in %s" % (t.name, t.repo),
                "id": sha("session", t.path)[:16], "startedAt": ago(now, st["session"][0]), "lastActiveAt": ago(now, st["session"][1])}
    facts = {"path": t.path, "repo": "%s/%s" % (ROOT, t.repo), "branch": t.branch, "findingID": "workforest:worktree:" + t.path,
             "main": False, "locked": t.locked, "missing": False, "maker": "claude-code", "gitKnown": True, "head": head,
             "defaultBranch": "origin/main", "merged": st["merged"], "upstream": st["upstream"], "dirty": st["dirty"],
             "untracked": t.untracked, "stashes": 0, "unpushed": st["unpushed"], "notInDefault": st["not_in_default"],
             "onRemote": st["on_remote"], "lastCommitAt": ago(now, st["last_commit"]), "sized": True, "diskBytes": t.disk,
             "freedBytes": t.disk - (t.disk >> 4), "cacheBytes": t.cache, "files": t.files, "touchedAt": ago(now, st["touched"]),
             "createdAt": ago(now, t.born), "processes": t.processes, "session": sess, "protected": t.protected}
    last_work = max(x for x in (st["last_commit"] if st["last_commit"] is not None else t.born, st["touched"],
                                st["session"][1] if st["session"] else None) if x is not None)
    # MMWFWorkKeeps, MMWFTree.m, in its order, with WorkForest's 24 hours for a recent session, file or tree.
    keep = None
    if t.protected: keep = "release is a long-lived branch"
    elif t.locked: keep = "locked"
    elif st["dirty"] > 0: keep = "%d changes not committed" % st["dirty"]
    elif t.untracked > 0: keep = "%d untracked files not committed" % t.untracked
    elif st["unpushed"] > 0 and not st["merged"]: keep = "%d commits on no remote and not in main" % st["unpushed"]
    elif t.processes: keep = t.processes[0] + " running inside"
    elif sess and st["live"]: keep = "Claude Code session is working in it"
    elif st["session"] and now - st["session"][1] < D: keep = "Claude Code session active today"
    elif now - st["touched"] < D: keep = "files changed today"
    elif now - t.born < D: keep = "made today"
    sess_age = now - st["session"][1] if st["session"] else None
    # WorkForest's Fingerprint, MMWorkForest.m.
    fp = "%s|%s|%s|d%d|u%d|p%d|r%d|x%d|s%s|q%s|k%d|l%d" % (head, st["merged"] or "-", st["upstream"] or "-", st["dirty"], t.untracked,
         st["unpushed"], st["on_remote"], len(t.processes) > 0, wf_bucket(sess_age) if sess_age is not None else "-",
         wf_bucket(now - last_work), t.protected, t.locked)
    kind = 0 if st["session"] and now - st["session"][1] < D else 2
    return {"expert": "workforest", "kind": "worktree", "stableKey": t.path, "instance": head, "title": "%s/%s" % (t.repo, t.name),
            "path": t.path, "owner": {"kind": kind, "key": t.path, "name": t.name, "path": t.path}, "facts": facts, "fingerprint": fp,
            "keep": [keep] if keep else [], "proposal": "remove", "freed": t.disk - (t.disk >> 4)}, st

# -------- LocoHost: five servers --------

def lh_bucket(age):
    return "-" if age is None else "0" if age < 15 * M else "1" if age < 2 * H else "2" if age < D else "3"

def lh_hosts(trees):
    active = [t for t in trees if t.bursts and t.born < 0]
    old = [t for t in trees if t.merged and -6 * D < t.touched < -3 * D] or [t for t in trees if t.merged]
    return [
        {"name": "postgres", "kind": "service", "framework": "PostgreSQL", "port": 47432, "tree": None, "pid": 401, "start": -9 * D},
        {"name": "epmd", "kind": "other", "framework": "epmd", "port": 47369, "tree": None, "pid": 402, "start": -9 * D},
        {"name": "node", "kind": "dev", "framework": "Vite", "port": 47173, "tree": active[0], "pid": 501, "start": -2 * H},
        {"name": "node", "kind": "dev", "framework": "Express", "port": 47300, "tree": active[0], "pid": 502, "start": -5 * H, "restart": 10 * H},
        {"name": "python3", "kind": "dev", "framework": "Django", "port": 47800, "tree": old[0], "pid": 503, "start": -3 * D},
    ]

def lh_finding(h, now, wf_states):
    t = h["tree"]
    pid, start = h["pid"], h["start"]
    if h.get("restart") and now >= h["restart"]: pid, start = pid + 1000, h["restart"]
    key = "%d:%d" % (pid, int(start) + 1800000000)
    last, state, conns, new = None, "idle", 0, 0
    sess = None
    st = wf_states.get(t.path) if t else None
    if h["kind"] != "dev":
        last, state, conns = now - (1 + 39 * U(h["port"], now, "svc")) * M, "recent", 2
    elif st:
        busy = any(s <= now < e for (s, e) in t.bursts)
        if busy:
            last = now - U(h["port"], now, "last") * 10 * M
            state = "active" if U(h["port"], now, "state") < 0.4 else "recent"
            new = 1 if state == "active" else 0
        else:
            ends = [e for (s, e) in t.bursts if e <= now]
            last = max(ends) if ends else start + 20 * M
        conns = 1
        if st["session"]: sess = {"agent": "claude-code", "title": "Work on %s" % t.name, "startedAt": ago(now, st["session"][0]),
                                  "lastActiveAt": ago(now, st["session"][1]), "match": "cwd"}
    else:
        last = now - 3 * D
    last = max(last, start) if last is not None else None
    orphaned = h["kind"] == "dev" and not (st and st["session"] and now - st["session"][1] < 2 * H)
    cwd = t.path if t else "/usr/local/var/" + h["name"]
    stable = "%s#%s" % (cwd, h["framework"].lower() if h["kind"] == "dev" else h["name"])
    facts = {"key": key, "stableKey": stable, "findingID": "locohost:server:" + stable, "pid": pid, "ppid": 1 if orphaned else 300,
             "startSec": int(start) + 1800000000, "name": h["name"], "execPath": "/opt/rvday/bin/" + h["name"], "cwd": cwd,
             "args": [h["name"], "serve", "--port", str(h["port"])], "started": ago(now, start), "ports": [h["port"]], "port": h["port"],
             "bind": "127.0.0.1", "url": "http://127.0.0.1:%d" % h["port"], "kind": h["kind"], "framework": h["framework"],
             "project": t.name if t else h["name"], "repo": t.repo if t else None, "repoRoot": ("%s/%s" % (ROOT, t.repo)) if t else None,
             "branch": t.branch if t else None, "worktree": t.name if t else None, "repoTouched": ago(now, st["touched"]) if st else None,
             "cpu": 0.4 if state == "active" else 0.0, "energyRank": 0.05, "memoryBytes": R.randint(80, 400) << 20, "processes": 3,
             "command": "%s serve --port %d" % (h["name"], h["port"]), "launcher": "zsh" if not orphaned else "launchd",
             "agent": "claude" if h["kind"] == "dev" and not orphaned else None, "orphaned": orphaned, "connections": conns,
             "newConnections": new, "busy": state == "active", "clients": ["browser"] if conns else [], "firstSeen": ago(now, max(start, -12 * H)),
             "lastActive": ago(now, last), "idleCPUSeconds": 12.0, "duplicates": [], "state": state, "protected": False,
             "projectFacts": {"name": t.name, "description": "Fixture project " + t.repo, "script": "dev"} if t else {},
             "session": sess}
    sess_age = now - st["session"][1] if sess else None
    # LocoHost's Fingerprint, MMLocoHost.m.
    fp = "%s|%s|%s|c%d|d0|p0|s%s|q%s" % (key, h["kind"], state, conns > 0, lh_bucket(sess_age), lh_bucket(now - last if last is not None else None))
    owner = None
    if t:
        kind = 0 if st and st["session"] and now - st["session"][1] < D else 2
        owner = {"kind": kind, "key": t.path, "name": t.name, "path": t.path}
    return {"expert": "locohost", "kind": "server", "stableKey": stable, "instance": key, "title": ":%d %s" % (h["port"], h["framework"]),
            "path": cwd, "owner": owner, "facts": facts, "fingerprint": fp, "keep": [], "proposal": "stop", "freed": 0}

# -------- MinMacs, Noo-Noo and Insomnia: decided by rules --------

APPS = [("Notes", "kept"), ("Mail", "kept"), ("Finder", "kept"), ("Terminal", "kept"), ("Calendar", "kept"), ("Music", "kept"),
        ("Preview", "quit"), ("TextEdit", "quit"), ("Numbers", "quit"), ("Keynote", "quit"), ("Safari", "trim"), ("Firefox", "trim"),
        ("Chrome", "trim"), ("Simulator", "spared"), ("Docker", "spared"), ("Figma", "unsorted"), ("Zoom", "unsorted"),
        ("Slack", "unsorted"), ("Postman", "unsorted"), ("Photos", "unsorted")]

def mm_findings(now, k):
    out = []
    for i, (name, group) in enumerate(APPS):
        mem = (R.randint(60, 900) + 40 * k) << 20
        reason = {"kept": "it is on the keep list", "spared": name + " started it and is working"}.get(group)
        bundle = "rvday.app." + name.lower()
        instance = "%d:%d" % (600 + i, 1800000000 - i)
        facts = {"bundleID": bundle, "name": name, "pid": 600 + i, "group": group, "verdict": group, "memoryBytes": mem,
                 "cpu": R.choice([0, 0, 1, 3]), "processes": R.randint(1, 6), "browser": group == "trim", "canTrim": group == "trim",
                 "pressure": 1, "thermal": 0}
        if reason: facts["reason"] = reason
        out.append({"expert": "minmacs", "kind": "app", "stableKey": bundle, "instance": instance, "title": name,
                    "path": None, "owner": None, "facts": facts, "fingerprint": "%s|%s|%d" % (group, reason or "", mem >> 28),
                    "keep": [reason] if group in ("kept", "spared") else [], "proposal": "quit" if group in ("quit", "trim") else None,
                    "freed": 0})
    return out

def nn_findings(now, k, trees):
    out = []
    sections = ["finished"] * 8 + ["leftovers"] * 6 + ["caches"] * 10 + ["kept"] * 6
    for i, sec in enumerate(sections):
        t = trees[i * 3 % len(trees)]
        freed = (R.randint(30, 3000) + (25 * k if sec == "caches" else 0)) << 20
        cls = "cache" if sec == "caches" else "build" if sec == "finished" else "leftover"
        owner_state = {"finished": "merged", "leftovers": "gone", "caches": "active", "kept": "active"}[sec]
        facts = {"kindID": "rvday." + cls, "kindTitle": cls, "class": cls, "path": t.path + "/node_modules", "members": 1,
                 "state": "kept" if sec == "kept" else "free", "section": sec, "allocated": freed, "freed": freed,
                 "name": "node_modules", "ownerState": owner_state, "why": "its project is " + owner_state}
        keep = ["an agent works in its project"] if sec == "kept" else []
        out.append({"expert": "noonoo", "kind": "clutter", "stableKey": "%s#%d" % (t.path, i), "instance": "%s#%d" % (t.path, i),
                    "title": "node_modules in " + t.name, "path": t.path + "/node_modules",
                    "owner": {"kind": 2, "key": t.path, "name": t.name, "path": t.path}, "facts": facts,
                    "fingerprint": "rvday.%s|%s|%s|%d" % (cls, facts["state"], owner_state, freed >> 28),
                    "keep": keep, "proposal": None if sec == "kept" else "remove", "freed": freed})
    return out

def in_findings(now):
    out = []
    for i in range(3):
        key = "%d:%d" % (700 + i, 1800000000 + i)
        out.append({"expert": "insomnia", "kind": "agent", "stableKey": "rvday-agent-%d" % i, "instance": key, "title": "agent %d" % i,
                    "path": None, "owner": None, "facts": {"name": "claude", "pid": 700 + i, "working": i == 0}, "fingerprint": "%s|%d" % (key, i == 0),
                    "keep": [], "proposal": None, "freed": 0})
    return out

def main():
    trees = make_trees()
    hosts = lh_hosts(trees)
    ticks = []
    for k in range(TICKS):
        now = 60 + k * H
        wf, states = [], {}
        live_trees = [t for t in trees if t.born <= now and (t.removed_at is None or now < t.removed_at)]
        for t in live_trees:
            f, st = wf_finding(t, now)
            wf.append(f); states[t.path] = st
        worktrees = [{"path": t.path, "head": sha(t.path, states[t.path]["version"])} for t in live_trees]
        sessions = [{"cwd": t.path, "ago": int(now - states[t.path]["session"][1]), "working": states[t.path]["live"]}
                    for t in live_trees if states[t.path]["session"]]
        lh = [lh_finding(h, now, states) for h in hosts]
        ticks.append({"at": now, "worktrees": worktrees, "sessions": sessions,
                      "findings": wf + lh + mm_findings(now, k) + nn_findings(now, k, trees) + in_findings(now)})
    day = {"about": "one generated day of findings for the five experts, issue #36; see test/review/dayfix.py",
           "schedule": {"broker": {e: 3600 for e in ("minmacs", "locohost", "workforest", "noonoo", "insomnia")},
                        "legacy": {"locohost": 3600, "workforest": 7200}},
           "ticks": ticks}
    with open(sys.argv[1], "w") as fh:
        json.dump(day, fh, sort_keys=True, separators=(",", ":"))

main()
