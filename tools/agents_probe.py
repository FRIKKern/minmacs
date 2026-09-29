#!/usr/bin/env python3
"""Reference implementation of agent detection. Reads registry/agents/*.json and
classifies what is running on this Mac. The Objective-C detector must agree with it.

  tools/agents_probe.py            table
  tools/agents_probe.py --json     machine readable
  tools/agents_probe.py --row registry/agents/codex.json   evaluate one row only
"""
import glob, json, os, re, subprocess, sys, time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout

def processes():
    procs = {}
    for line in sh("ps", "-axo", "pid=,ppid=,pcpu=,tty=,args=").splitlines():
        m = re.match(r"\s*(\d+)\s+(\d+)\s+([\d.,]+)\s+(\S+)\s+(.*)", line)
        if not m: continue
        pid, ppid, cpu, tty, args = m.groups()
        argv = args.split(" ")
        procs[int(pid)] = dict(pid=int(pid), ppid=int(ppid), cpu=float(cpu.replace(",", ".")), tty=tty,
                               args=args, exe=argv[0], name=os.path.basename(argv[0]), argv=argv, kids=[])
    for p in procs.values():
        if p["ppid"] in procs: procs[p["ppid"]]["kids"].append(p["pid"])
    return procs

def tree(procs, pid):
    out, stack = [], [pid]
    while stack:
        p = procs.get(stack.pop())
        if p: out.append(p); stack.extend(p["kids"])
    return out

def matches(surface, p):
    spec = surface.get("process") or {}
    if not spec: return False
    hit = p["name"] in spec.get("names", []) or any(s in p["exe"] for s in spec.get("path_contains", []))
    if not hit: return False
    if any(a in p["argv"] for a in spec.get("exclude_args", [])): return False
    need = spec.get("args_contain", [])
    return all(any(n in a for a in p["argv"]) for n in need)

def session_id(surface, p):
    for flag in surface.get("session_id_args", []):
        for i, a in enumerate(p["argv"]):
            if a == flag and i + 1 < len(p["argv"]): return p["argv"][i + 1]
            if a.startswith(flag + "="): return a[len(flag) + 1:]
    return None

SHELLS = {"bash", "zsh", "sh", "dash", "fish", "-bash", "-zsh", "-sh"}

def assertions():
    """pid -> names of the power assertions it holds, from pmset."""
    out = {}
    for line in sh("pmset", "-g", "assertions").splitlines():
        m = re.match(r'\s*pid (\d+)\(.*?\): .*? named: "(.*)"', line)
        if m: out.setdefault(int(m.group(1)), []).append(m.group(2))
    return out

def transcript_age(row, sid):
    store = row.get("session_store") or {}
    pattern = store.get("per_session", "").replace("{session_id}", sid) if sid and store.get("per_session") else None
    if not pattern: return None, None
    files = glob.glob(os.path.expanduser(pattern))
    if not files: return None, None
    newest = max(files, key=os.path.getmtime)
    return time.time() - os.path.getmtime(newest), newest

def classify(row, surface, p, procs, held):
    t = tree(procs, p["pid"])
    cpu = sum(x["cpu"] for x in t)
    # Direct children only. Descendants include MCP servers, language servers and
    # relaunch children that live as long as the session does.
    kids = [procs[k]["name"] for k in p["kids"] if k in procs]
    sid = session_id(surface, p)
    age, path = transcript_age(row, sid)
    reasons = []
    for s in row["working_signals"]:
        kind = s["signal"]
        if kind == "child_process" and s.get("name") in kids: reasons.append(f"child {s['name']}")
        elif kind == "tree_cpu" and cpu >= s.get("floor_percent", 3): reasons.append(f"cpu {cpu:.0f}%")
        elif kind == "transcript_write" and age is not None and age <= s.get("within_seconds", 30): reasons.append(f"transcript {age:.0f}s ago")
        elif kind == "tool_children" and [k for k in kids if k in SHELLS]: reasons.append("tool shell running")
        elif kind == "power_assertion":
            want = s.get("name")
            names = [n for x in t for n in held.get(x["pid"], []) if x["name"] != "caffeinate"]
            if [n for n in names if not want or want.lower() in n.lower()]: reasons.append("holds a sleep assertion")
    cwd = sh("lsof", "-a", "-p", str(p["pid"]), "-d", "cwd", "-Fn")
    cwd = next((l[1:] for l in cwd.splitlines() if l.startswith("n")), "")
    return dict(harness=row["name"], id=row["id"], surface=surface["kind"], pid=p["pid"], tty=p["tty"],
                state="working" if reasons else "idle", why=", ".join(reasons), cpu=round(cpu, 1),
                children=len(p["kids"]), session=sid, transcript_age=None if age is None else round(age),
                project=cwd.replace(os.path.expanduser("~"), "~"))

def main():
    args = sys.argv[1:]
    rows = [args[args.index("--row") + 1]] if "--row" in args else sorted(glob.glob(os.path.join(ROOT, "registry/agents/*.json")))
    procs, found, held = processes(), [], assertions()
    for path in rows:
        row = json.load(open(path))
        for p in procs.values():
            for surface in row["surfaces"]:
                if matches(surface, p):
                    parent = procs.get(p["ppid"])
                    # a harness that re-executes itself shows up twice; keep the outermost process
                    if parent and any(matches(s, parent) for s in row["surfaces"]): break
                    found.append(classify(row, surface, p, procs, held)); break
    found.sort(key=lambda a: (a["state"] != "working", a["harness"], a["pid"]))
    if "--json" in args:
        print(json.dumps(dict(agents=found, working=sum(a["state"] == "working" for a in found), idle=sum(a["state"] == "idle" for a in found)), indent=1)); return
    print(f"{'harness':<14}{'surface':<8}{'pid':<7}{'state':<9}{'cpu':>5}  {'kids':<5}{'why':<34}project")
    for a in found:
        print(f"{a['harness']:<14}{a['surface']:<8}{a['pid']:<7}{a['state']:<9}{a['cpu']:>5}  {a['children']:<5}{a['why'][:33]:<34}{a['project'][-46:]}")
    w = sum(a["state"] == "working" for a in found)
    print(f"\n{len(found)} agent sessions: {w} working, {len(found) - w} idle")

if __name__ == "__main__":
    main()
