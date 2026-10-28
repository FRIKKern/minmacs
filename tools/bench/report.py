#!/usr/bin/env python3
"""Turns one bench run into Markdown tables: 2.0 against the old apps over the same window, the tick, and the menus.

Usage: report.py idle.json menus.json [host.txt] [startup.json ...] [hangs.json]
"""
import json
import sys
import time


def fmt(x, places=2):
    return ("%%.%df" % places) % x if isinstance(x, (int, float)) else str(x)


def main():
    idle = json.load(open(sys.argv[1]))
    menus = json.load(open(sys.argv[2]))
    host, startups, hangs = [], [], None
    for a in sys.argv[3:]:
        if not a.endswith(".json"):
            host = open(a).read().strip().splitlines()
            continue
        x = json.load(open(a))
        if x.get("kind") == "startup":
            startups.append(x)
        elif x.get("kind") == "hangs":
            hangs = x
    start = time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime(idle["startedAt"]))
    out = []
    out.append("Window: %s minutes from %s, after %s seconds of warm-up." % (fmt(idle["windowSeconds"] / 60, 1), start, fmt(idle["warmupSeconds"], 0)))
    if host:
        out.append("Host: %s. Load at the start and end: %s" % (", ".join(host[1:4]), " / ".join(h.split("load averages:")[-1].strip() for h in host if "load averages" in h)))
    out.append("")
    out.append("| App | CPU % | CPU s a minute | Footprint MB | Resident MB | Peak footprint MB | Wakeups a second | Idle wakeups a second |")
    out.append("|---|---|---|---|---|---|---|---|")
    out.append("| MinMacs 2.0, %d experts, headless | %s | %s | %s | %s | %s | %s | %s |" % (
        idle["experts"], fmt(idle["cpuPercent"], 3), fmt(idle["cpuSecondsPerMinute"], 3), fmt(idle["footprintMB"]), fmt(idle["residentMB"]),
        fmt(idle["peakFootprintMB"]), fmt(idle["interruptWakeupsPerSecond"], 3), fmt(idle["idleWakeupsPerSecond"], 3)))
    for a in idle["oldApps"]:
        if "error" in a:
            out.append("| %s | %s | | | | | | |" % (a["app"], a["error"]))
            continue
        out.append("| %s %s | %s | %s | %s | %s | %s | %s | %s |" % (
            a["app"], a["version"], fmt(a["cpuPercent"], 3), fmt(a["cpuSecondsPerMinute"], 3), fmt(a["footprintMB"]), fmt(a["residentMB"]),
            fmt(a["peakFootprintMB"]), fmt(a["interruptWakeupsPerSecond"], 3), fmt(a["idleWakeupsPerSecond"], 3)))
    old = [a for a in idle["oldApps"] if "error" not in a]
    if old:
        out.append("| The old apps together | %s | %s | %s | %s | | %s | %s |" % (
            fmt(sum(a["cpuPercent"] for a in old), 3), fmt(sum(a["cpuSecondsPerMinute"] for a in old), 3),
            fmt(sum(a["footprintMB"] for a in old)), fmt(sum(a["residentMB"] for a in old)),
            fmt(sum(a["interruptWakeupsPerSecond"] for a in old), 3), fmt(sum(a["idleWakeupsPerSecond"] for a in old), 3)))
    out.append("")
    out.append("ps at the window's start and end:")
    out.append("")
    out.append("| App | pid | RSS KB start | RSS KB end | CPU time start | CPU time end | Running for |")
    out.append("|---|---|---|---|---|---|---|")
    for a in old:
        s, e = a.get("psStart", {}), a.get("psEnd", {})
        out.append("| %s | %s | %s | %s | %s | %s | %s |" % (a["app"], a["pid"], s.get("rssKB", ""), e.get("rssKB", ""), s.get("cputime", ""), e.get("cputime", ""), e.get("etime", "")))
    out.append("")
    w = idle["inWindow"]
    t = idle["tickCost"]
    p = t.get("parts", {})
    out.append("The tick, in CPU ms. In the window: %d samples, %d snapshots, %d pids, %s s between samples at the median." % (
        idle["samples"], idle["snapshots"], idle["pids"], fmt(idle["tickSeconds"].get("median", 0), 3)))
    out.append("")
    out.append("| Part | Median | p95 | Max | Runs |")
    out.append("|---|---|---|---|---|")
    rows = [("In the window: the whole process, one sample to the next", w.get("tickCPUms", {})),
            ("In the window: sample signal, from the last snapshot", w["passCPUms"]),
            ("In the window: rebuild, sample signal to snapshot on main", w["rebuildCPUms"]),
            ("In the window: rebuild wall time", w["rebuildWallms"]),
            ("Alone: Senses pass", t["passCPUms"]), ("Alone: Senses pass, wall time", t["passWallms"]),
            ("Alone: the facts of a rebuild", t["factsCPUms"]), ("Alone: the snapshot from those facts", t["snapshotCPUms"])]
    if "prepareCPUms" in t:
        rows += [("Alone: what each menu reads, prepared on the graph queue", t["prepareCPUms"])]
    if p:
        rows += [("Alone, own sample: registry agentsIn", p["registryAgentsCPUms"]), ("Alone, own sample: sessions refresh", p["sessionsRefreshCPUms"])]
        rows += [("Alone, own sample: %s findings" % k, v) for k, v in sorted(p["findingsCPUms"].items())]
        if "registryAgentsWarmCPUms" in p:
            rows += [("Again, same sample: registry agentsIn", p["registryAgentsWarmCPUms"])]
            rows += [("Again, same sample: %s findings" % k, v) for k, v in sorted(p["findingsWarmCPUms"].items())]
    for name, s in rows:
        out.append("| %s | %s | %s | %s | %s |" % (name, s.get("median", ""), s.get("p95", ""), s.get("max", ""), s.get("n", 0)))
    sn, gr = idle.get("senses"), idle.get("graph")
    if sn and gr:
        out.append("")
        out.append("Issue #52, in the window. The Senses pass ran %d times at %s, %s ms CPU each." % (sn["passes"], sn["interval"], fmt(sn["passCPUms"], 3)))
        out.append("Each pass carried the args of %s processes and the cwd of %s, read the sockets of %s and carried those of %s." % (
            fmt(sn["argsCarriedPerPass"], 0), fmt(sn["cwdsCarriedPerPass"], 0), fmt(sn["socketPidsReadPerPass"], 0), fmt(sn["socketPidsCarriedPerPass"], 0)))
        out.append("The graph built %d snapshots and skipped %d builds whose facts did not change. The session index read its folders %d times and skipped %d refreshes." % (
            gr["builds"], gr["skipped"], gr["sessionReads"], gr["sessionSkips"]))
        if gr.get("reusedFindings"):
            out.append("Experts that handed back their last findings: %s." % ", ".join("%s %d times" % (k, v) for k, v in sorted(gr["reusedFindings"].items())))
        sig = idle.get("signals", {})
        if sig:
            out.append("Signals besides the tick: %s." % ", ".join("%s %d" % (k, v) for k, v in sorted(sig.items()) if ":" not in k))
        out.append("")
        out.append("| Part | CPU ms each |")
        out.append("|---|---|")
        for k, v in sorted(sn.get("partsCPUms", {}).items()):
            out.append("| Pass: %s | %s |" % (k, v))
        for k, v in sorted(gr["perBuildCPUms"].items()):
            if k.startswith("reused."):
                continue
            out.append("| Build: %s | %s |" % (k, v))
    out.append("")
    out.append("Menus, in wall ms on main, %d builds each from a fixture snapshot. Prepare runs on the graph queue, before main sees the snapshot:" % menus["iterations"])
    out.append("")
    out.append("| Expert | Fixture | Rows | Cards | Prepare median | Spec median | Menu open median | Menu open p95 | Card build p95 | Card hover median | Card hover p95 |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|")
    for eid, e in sorted(menus["experts"].items()):
        out.append("| %s | %s | %d | %d | %s | %s | %s | %s | %s | %s | %s |" % (
            eid, e["fixture"], e["rows"], e.get("cards", 0), e.get("prepareMs", {}).get("median", ""), e["specMs"].get("median"),
            e["menuOpenMs"].get("median"), e["menuOpenMs"].get("p95"),
            e["cardBuildMs"].get("p95"), e["cardHoverMs"].get("median"), e["cardHoverMs"].get("p95")))
    out.append("| One Icon, every expert | | | | | | %s | %s | | | |" % (menus["oneIconMs"].get("median"), menus["oneIconMs"].get("p95")))
    out.append("")
    if "cardsBuiltAtOpen" in menus:
        out.append("Cards built while a menu opened: %d. Log queries on main: %d. Keep file reads on main: %d." % (
            menus["cardsBuiltAtOpen"], menus.get("logQueriesOnMain", 0), menus.get("keepReadsOnMain", 0)))
        out.append("")
    if startups:
        out.append("Startup, headless, in ms from where MMMain starts:")
        out.append("")
        out.append("| Launch | Core started | Items made | First snapshot | Every summary | Made at launch | Left for later |")
        out.append("|---|---|---|---|---|---|---|")
        for r in startups:
            t = r["times"]
            out.append("| %s | %s | %s | %s | %s | %s | %s |" % ("first" if r.get("firstLaunch") else "later", t.get("core", ""), t.get("items", ""),
                       t.get("snapshot", ""), t.get("summaries", ""), ", ".join(t.get("made", [])), ", ".join(t.get("deferred", [])) or "none"))
        out.append("")
    if hangs:
        out.append("Watchdog: %d menu opens and %d card hovers in %d passes of main, %d of them on the live snapshot. %d stalls over %s ms." % (
            hangs["opens"] + hangs["liveOpens"], hangs["hovers"], hangs["passes"], hangs["liveOpens"], len(hangs["stalls"]), hangs["limitMs"]))
        for st in hangs["stalls"]:
            out.append("- %s ms, %s ms CPU, %s, in %s" % (st["ms"], st["cpuMs"], st["state"], st["what"]))
        out.append("")
    out.append("Nothing acted: %d undo records, every mode %s. Child process CPU in the window: %s s." % (idle["undoRecords"], idle["modes"], idle["childCPUSeconds"]))
    print("\n".join(out))


if __name__ == "__main__":
    main()
