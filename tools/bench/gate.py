#!/usr/bin/env python3
"""The regression gate: reads results from tools/bench/bench and checks them against budgets.json.

Usage: gate.py [--strict] budgets.json result.json ...
Each result is known by its kind: idle, menus, startup, hangs, scale or history. A budget whose input is not given is skipped.
A budget with no input reads the idle and menus runs. tools/bench/run.sh gives idle, menus, two startups and hangs.
tools/bench/scale.sh gives two scale runs, a launch with no caches and a later one, issue #54.
Prints one line per budget, tab separated: a word, the budget's what, the value, the phase 6 budget, the ceiling.
  ok     within the phase 6 budget
  over   over the phase 6 budget and within today's ceiling, which phase 6 tuning is to close
  FAIL   over the ceiling, or over the budget with --strict
  skip   not measured, with the reason
Exits 1 on any FAIL.
"""
import json
import sys


def tick_cpu(idle):
    w = idle["inWindow"]
    t = w.get("tickCPUms", {})
    if t.get("n"):
        return (t["mean"], "mean")
    return (round(w["passCPUms"]["median"] + w["rebuildCPUms"]["median"], 3), "")


def scale_values(scales):
    """Issue #54. The cold scan is the launch with no caches, from MMCoreStart until a snapshot holds every
    checkout's git facts. The warm scan is the full walk with every fingerprint read again: the median of the
    later launch's runs. The worker's peak is the highest of any phase of any run."""
    v = {}
    cold = [s for s in scales if not s.get("cachesAtLaunch")]
    if cold:
        v["coldScan300Seconds"] = (max(s["launch"]["snapshotSeconds"] for s in cold), "a launch with no caches")
    # The later launch when one is given: the walk the 10-minute timer runs in an app whose launch work is done.
    # The first launch's warm walks share the Mac with its 300 disk walks, and are reported, not gated.
    later = [s for s in scales if s.get("cachesAtLaunch")] or scales
    warm = [(s["warm"]["seconds"]["median"], s) for s in later if s.get("warm", {}).get("seconds", {}).get("n")]
    if warm:
        got, s = max(warm, key=lambda x: x[0])
        v["warmScan300Seconds"] = (got, "the %s, median of %d runs" % (
            "later launch" if s.get("cachesAtLaunch") else "first launch", s["warm"]["seconds"]["n"]))
    peaks = [(p["workerPeakMB"], "the %s phase" % k) for s in scales for k, p in s.get("memory", {}).items() if isinstance(p, dict) and "workerPeakMB" in p]
    if peaks:
        v["workerPeakMB"] = max(peaks)
    return v


def values(idle, menus, startups=(), hangs=None, scales=(), history=None):
    """The number each budget key reads. A per-expert budget gives its worst expert."""
    v = {} if idle is None else {
        "idleCPUPercent": (idle["cpuPercent"], ""),
        "idleFootprintMB": (idle["footprintMB"], ""),
        # The mean tick: the whole process's CPU from one sample signal to the next, issue #52. A tick whose rebuild
        # found nothing changed makes no snapshot, so a sum of pass and rebuild medians would miss it.
        "tickCPUms": tick_cpu(idle),
        # Every wakeup counts, the ones that woke the package from idle among them.
        "wakeupsPerSecond": (idle["interruptWakeupsPerSecond"], ""),
    }
    for key, field in (("menuOpenP95Ms", "menuOpenMs"), ("cardHoverP95Ms", "cardHoverMs")):
        if menus is None:
            break
        worst = None
        for eid, e in sorted(menus["experts"].items()):
            p = e[field].get("p95")
            if p is not None and (worst is None or p > worst[0]):
                worst = (p, eid)
        v[key] = worst if worst else (None, "")
    # The slowest of the startup runs given, a first launch and a later one.
    for key, field in (("iconsAfterLaunchMs", "items"), ("summariesAfterLaunchMs", "summaries")):
        got = [(r["times"].get(field), "first launch" if r.get("firstLaunch") else "later launch") for r in startups]
        got = [g for g in got if g[0] is not None]
        if startups:
            v[key] = max(got) if len(got) == len(startups) else (None, "")
    if hangs is not None:
        v["mainStalls"] = (len(hangs["stalls"]) if hangs.get("finished") else None, "")
    v.update(scale_values(scales))
    if history is not None:
        v["historyKB"] = (history["footprintGrowthKB"], "%d rings, store %s KB and a copy %s KB" % (history["rings"], history["storeKB"], history["copyKB"]))
    return v


def main():
    args = sys.argv[1:]
    strict = "--strict" in args
    args = [a for a in args if a != "--strict"]
    budgets = json.load(open(args[0]))["budgets"]
    results = [json.load(open(a)) for a in args[1:]]
    idle = next((x for x in results if x.get("kind") == "idle"), None)
    menus = next((x for x in results if x.get("kind") == "menus"), None)
    startups = [x for x in results if x.get("kind") == "startup"]
    hangs = next((x for x in results if x.get("kind") == "hangs"), None)
    scales = [x for x in results if x.get("kind") == "scale"]
    history = next((x for x in results if x.get("kind") == "history"), None)
    given = {"startup": bool(startups), "hangs": hangs is not None, "scale": bool(scales), "history": history is not None,
             "": idle is not None and menus is not None}
    v = values(idle, menus, startups, hangs, scales, history)
    failed = 0
    for b in budgets:
        what = b["what"]
        if b.get("measured", True) is False:
            print("skip\t%s\tnot measured: %s\tbudget %s %s\t-" % (what, b["why"], b["max"], b["unit"]))
            continue
        if not given.get(b.get("input", "")):
            print("skip\t%s\tno %s run given\tbudget %s %s\t-" % (what, b.get("input", "idle and menus"), b["max"], b["unit"]))
            continue
        got, where = v.get(b["key"], (None, ""))
        if got is None:
            print("FAIL\t%s\tno value\tbudget %s %s\t-" % (what, b["max"], b["unit"]))
            failed += 1
            continue
        def within(limit):
            return got < limit if b.get("below") else got <= limit
        ceiling = b["max"] if strict else b.get("ceiling", b["max"])
        word = "ok" if within(b["max"]) else ("over" if within(ceiling) else "FAIL")
        failed += word == "FAIL"
        at = " in %s" % where if where else ""
        print("%s\t%s\t%s %s%s\tbudget %s %s\tceiling %s %s" % (word, what, got, b["unit"], at, b["max"], b["unit"], ceiling, b["unit"]))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
