#!/usr/bin/env python3
"""The regression gate: reads an idle and a menus result from tools/bench/bench and checks them against budgets.json.

Usage: gate.py [--strict] budgets.json idle.json menus.json [startup.json ...] [hangs.json]
A startup or hangs result is known by its kind. A budget whose input is not given is skipped.
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


def values(idle, menus, startups=(), hangs=None):
    """The number each budget key reads. A per-expert budget gives its worst expert."""
    v = {
        "idleCPUPercent": (idle["cpuPercent"], ""),
        "idleFootprintMB": (idle["footprintMB"], ""),
        # The mean tick: the whole process's CPU from one sample signal to the next, issue #52. A tick whose rebuild
        # found nothing changed makes no snapshot, so a sum of pass and rebuild medians would miss it.
        "tickCPUms": tick_cpu(idle),
        # Every wakeup counts, the ones that woke the package from idle among them.
        "wakeupsPerSecond": (idle["interruptWakeupsPerSecond"], ""),
    }
    for key, field in (("menuOpenP95Ms", "menuOpenMs"), ("cardHoverP95Ms", "cardHoverMs")):
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
    return v


def main():
    args = sys.argv[1:]
    strict = "--strict" in args
    args = [a for a in args if a != "--strict"]
    budgets = json.load(open(args[0]))["budgets"]
    idle = json.load(open(args[1]))
    menus = json.load(open(args[2]))
    extra = [json.load(open(a)) for a in args[3:]]
    startups = [x for x in extra if x.get("kind") == "startup"]
    hangs = next((x for x in extra if x.get("kind") == "hangs"), None)
    given = {"startup": bool(startups), "hangs": hangs is not None}
    v = values(idle, menus, startups, hangs)
    failed = 0
    for b in budgets:
        what = b["what"]
        if b.get("measured", True) is False:
            print("skip\t%s\tnot measured: %s\tbudget %s %s\t-" % (what, b["why"], b["max"], b["unit"]))
            continue
        if "input" in b and not given.get(b["input"]):
            print("skip\t%s\tno %s run given\tbudget %s %s\t-" % (what, b["input"], b["max"], b["unit"]))
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
