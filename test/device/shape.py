#!/usr/bin/env python3
# Checks the shape of `minmacs device --json` on stdin: every field docs/CLI.md names, with its type.
# Prints "ok" or each field that is missing or of another type, one per line, and exits 1 then.
import json, sys

B, I, S, N, L, D = bool, "int", str, "number", list, dict
O = "null"   # may also be null

SHAPE = {
    "schema": I, "at": I, "inApp": B,
    "identity": {"computerName": (S, O), "localHostName": (S, O), "model": (S, O), "chip": (S, O),
                 "cores": {"physical": (I, O), "logical": (I, O), "performance": (I, O), "efficiency": (I, O)},
                 "memoryBytes": (I, O), "macOS": {"version": S, "build": (S, O)}, "minmacs": {"version": S, "build": (S, O)}},
    "power": {"onAC": B, "batteryPercent": (I, O), "lowPowerMode": B, "thermal": S, "online": B},
    "lid": {"closed": B, "insomniaLidMode": B, "insomniaLidLive": B, "screenOff": B, "keepsScreenLit": B},
    "display": {"active": S, "canCaptureScreen": B, "known": B, "builtinLit": B, "externalAwake": B, "displays": L},
    "awake": {"held": B, "manual": B, "manualHeld": B, "agentsMode": B, "agents": L, "holds": L, "quiet": L, "others": L,
              "displaySleepMinutes": (I, O)},
    "load": {"memoryPressure": S, "memoryUsedBytes": I, "memoryTotalBytes": (I, O), "swapUsedBytes": I, "cpuPercent": (N, O),
             "loadAverage": (L, O), "diskFreeBytes": I, "diskTotalBytes": I},
    "agents": {"working": I, "total": I, "workingNames": L, "list": L},
    "quiet": {"active": B, "holders": L},
    "minmacs": (D, O),
}
DISPLAY = {"id": I, "builtin": B, "asleep": B, "active": B, "main": B, "mirrored": B, "vendor": I, "model": I, "width": I, "height": I}
AGENT = {"pid": I, "name": S, "harness": S, "state": S, "working": B, "ports": L}
HOLDER = {"pid": I, "reason": S, "since": I, "by": S, "rid": S, "awake": B}
WORDS = {("display", "active"): {"builtin", "external", "none", "asleep", "unknown"},
         ("power", "thermal"): {"nominal", "fair", "serious", "critical"},
         ("load", "memoryPressure"): {"normal", "warn", "critical"}}

bad = []


def is_type(v, t):
    if t == O: return v is None
    if t == I: return isinstance(v, int) and not isinstance(v, bool)
    if t == N: return isinstance(v, (int, float)) and not isinstance(v, bool)
    if t is B: return isinstance(v, bool)
    return isinstance(v, t)


def walk(j, shape, path):
    for k, t in shape.items():
        p = path + [k]
        if not isinstance(j, dict) or k not in j:
            bad.append("missing " + ".".join(p)); continue
        v = j[k]
        if isinstance(t, dict):
            walk(v, t, p); continue
        ts = t if isinstance(t, tuple) else (t,)
        if not any(is_type(v, x) for x in ts):
            bad.append("%s is %s" % (".".join(p), type(v).__name__))
        words = WORDS.get(tuple(p))
        if words and v not in words:
            bad.append("%s is %r" % (".".join(p), v))


j = json.load(sys.stdin)
walk(j, SHAPE, [])
for d in j.get("display", {}).get("displays", []): walk(d, DISPLAY, ["display", "displays[]"])
for a in j.get("agents", {}).get("list", []): walk(a, AGENT, ["agents", "list[]"])
for h in j.get("quiet", {}).get("holders", []): walk(h, HOLDER, ["quiet", "holders[]"])
la = j.get("load", {}).get("loadAverage")
if isinstance(la, list) and (len(la) != 3 or not all(is_type(x, N) for x in la)): bad.append("load.loadAverage is not three numbers")
m = j.get("minmacs")
if isinstance(m, dict):
    walk(m, {"pid": I, "runningSeconds": N, "sinceLaunch": {"cpuPercent": N, "idleWakeupsPerSecond": N},
             "memory": {"footprintBytes": I, "peakBytes": I}, "budgets": D, "over": L}, ["minmacs"])
print("\n".join(bad) if bad else "ok")
sys.exit(1 if bad else 0)
