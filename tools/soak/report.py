#!/usr/bin/env python3
"""The soak's report and verdict, issue #56. Reads one run folder of tools/soak/run.sh and prints Markdown.

  report.py <out>

It exits 0 when the run passes: every leaks(1) run worked, found no leak in MinMacs code, and found no more leaks
trees that only system frameworks made at the last sample than at the first. The soak process lived to the stop and
exited 0 on SIGTERM, no crash, hang or spin report names its processes, the watchdog saw no pass of main over 50 ms,
every mode stayed Idle with no undo record and no awake hold, and no fixture was left running. Footprint growth is
judged against 5 MB a day only on a run of 6 hours or more, since a shorter run measures the warm-up more than a trend.
"""
import json
import os
import re
import sys

MB = 1048576.0
GROWTH_LIMIT = 5.0      # MB a day
GROWTH_JUDGED_FROM = 6 * 3600


def load(path, lines=False):
    try:
        with open(path) as f:
            return [json.loads(l) for l in f if l.strip()] if lines else json.load(f)
    except (OSError, ValueError):
        return [] if lines else None


def slope(xs, ys):
    """Least squares slope of ys over xs, or None with fewer than two points."""
    if len(xs) < 2:
        return None
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    d = sum((x - mx) ** 2 for x in xs)
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / d if d else None


def split_leaks(path):
    """Leaks in one leaks(1) report: the leaked blocks of the trees that name a MinMacs class or a function of the soak
    binary, and the number of the other trees, which only system frameworks made. Each tree's root is indented six
    spaces."""
    try:
        text = open(path).read()
    except OSError:
        return 0, 0
    body = text.split("<< TOTAL >>", 1)[-1]
    ours = system = 0
    for block in re.split(r"\n(?= {6}\d+ \()", body):
        m = re.match(r"\s*(\d+) \(", block)
        if not m:
            continue
        if re.search(r"<MM\w+ |\bmmsoak\d+\s+\S*(\[|_block_invoke)", block):
            ours += int(m.group(1))
        else:
            system += 1   # trees, since the nodes of one system tree vary from one read to the next
    return ours, system


def main(out):
    samples = load(os.path.join(out, "samples.jsonl"), lines=True)
    status = load(os.path.join(out, "status.jsonl"), lines=True)
    summary = load(os.path.join(out, "summary.json")) or {}
    churn = load(os.path.join(out, "churn.json")) or {}
    try:
        reports = [l.strip() for l in open(os.path.join(out, "reports.txt")) if l.strip()]
    except OSError:
        reports = ["reports.txt is missing"]
    host = open(os.path.join(out, "host.txt")).read().split("\n") if os.path.exists(os.path.join(out, "host.txt")) else []

    good = [s for s in samples if s.get("proc")]
    p = lambda s, k: s["proc"][k]
    xs = [s["elapsed"] for s in good]
    foot = [p(s, "footprintBytes") / MB for s in good]
    per_sec = slope(xs, foot)
    growth = per_sec * 86400 if per_sec is not None else None
    span = xs[-1] - xs[0] if len(xs) > 1 else 0

    checks = []
    def check(name, ok, got):
        checks.append((name, ok, got))

    leak_runs = [s for s in samples if s["leaksExit"] in (0, 1) and s["leaks"] is not None]
    check("every leaks(1) run worked", bool(samples) and len(leak_runs) == len(samples), "%d of %d" % (len(leak_runs), len(samples)))
    for s in leak_runs:
        s["ours"], s["system"] = split_leaks(os.path.join(out, "leaks-%d.txt" % s["n"]))
    check("no leak in MinMacs code", bool(leak_runs) and all(s["ours"] == 0 for s in leak_runs),
          ", ".join("%d" % s["ours"] for s in leak_runs) or "none")
    sys_counts = [s["system"] for s in leak_runs]
    check("system framework leak trees do not grow", bool(sys_counts) and sys_counts[-1] <= sys_counts[0],
          ", ".join("%d" % c for c in sys_counts) or "none")
    check("the soak lived to the stop", not churn.get("died"), churn.get("died") or "yes")
    check("it exited 0 on SIGTERM", churn.get("soakExit") == 0 and summary.get("stoppedBy") == "SIGTERM",
          "%s, %s" % (churn.get("soakExit"), summary.get("stoppedBy")))
    check("no crash, hang or spin report", not reports, ", ".join(reports) or "none")
    # leaks(1) suspends the whole process while it reads the heap, so a pass of main that overlaps a leaks window is
    # the sampler's, not the app's. It is listed apart. Every other pass over 50 ms fails the run.
    windows = [(s["leaksFrom"] - 1, s["leaksTo"] + 1) for s in samples if "leaksFrom" in s]
    def during_leaks(st):
        end = st.get("at", 0); start = end - st.get("ms", 0) / 1000.0
        return any(start <= b and end >= a for a, b in windows)
    stalls = [st for st in summary.get("stalls", []) if not during_leaks(st)]
    sampler = [st for st in summary.get("stalls", []) if during_leaks(st)]
    words = lambda xs: "; ".join("%s ms, %s ms CPU, in %s" % (st.get("ms"), st.get("cpuMs"), st.get("what")) for st in xs)
    check("no pass of main over 50 ms", bool(summary) and not stalls, words(stalls) or "none")
    checks.append(("passes over 50 ms while leaks(1) held the process", None, "%d%s" % (len(sampler), ": " + words(sampler) if sampler else "")))
    check("every mode Idle and nothing acted", bool(summary) and summary.get("notIdle") == [] and summary.get("undoRecords") == 0,
          "%s not Idle, %s undo records" % (summary.get("notIdle"), summary.get("undoRecords")))
    check("no awake hold", summary.get("peakAwakeHolds") == 0, summary.get("peakAwakeHolds"))
    check("no fixture left running", churn.get("fixturesLeft") == 0, churn.get("fixturesLeft"))
    if span >= GROWTH_JUDGED_FROM and growth is not None:
        check("footprint growth under %g MB a day" % GROWTH_LIMIT, growth < GROWTH_LIMIT, "%.2f MB a day" % growth)
    else:
        checks.append(("footprint growth, not judged on %d s" % span, None, "%.2f MB a day" % growth if growth is not None else "n/a"))

    w = sys.stdout.write
    w("# Soak run\n\n")
    if host:
        w("Started %s on %s, macOS %s, %s cores, at %s. Load at start: %s.\n\n" % (
            host[0], host[2] if len(host) > 2 else "?", host[1] if len(host) > 1 else "?",
            host[3] if len(host) > 3 else "?", host[5] if len(host) > 5 else "?",
            host[4].split("load averages:")[-1].strip() if len(host) > 4 else "?"))
    w("%s seconds, a sample every %s seconds, a churn step every %s seconds, tag %s.\n\n" % (
        churn.get("seconds"), churn.get("sampleEvery"), churn.get("churnEvery"), churn.get("tag")))
    w("| Sample | Elapsed s | Footprint MB | Peak MB | Resident MB | CPU % since last | Threads | Fds | Leaks, MinMacs | Leak trees, system | leaks s |\n")
    w("|---|---|---|---|---|---|---|---|---|---|---|\n")
    prev = None
    for s in samples:
        if not s.get("proc"):
            w("| %d | %d | gone | | | | | | %s | %s | %d |\n" % (s["n"], s["elapsed"], s.get("ours"), s.get("system"), s["leaksSeconds"]))
            continue
        cpu = ""
        if prev:
            dt = s["elapsed"] - prev["elapsed"]
            if dt > 0:
                cpu = "%.3f" % ((p(s, "cpuNs") - p(prev, "cpuNs")) / 1e9 / dt * 100)
        w("| %d | %d | %.2f | %.2f | %.2f | %s | %d | %d | %s | %s | %d |\n" % (
            s["n"], s["elapsed"], p(s, "footprintBytes") / MB, p(s, "peakFootprintBytes") / MB,
            p(s, "residentBytes") / MB, cpu, p(s, "threads"), p(s, "fds"), s.get("ours"), s.get("system"), s["leaksSeconds"]))
        prev = s
    w("\n")
    if len(good) > 1:
        a, b = good[0], good[-1]
        dt = b["elapsed"] - a["elapsed"]
        w("From the first sample to the last, %d s: footprint %+.2f MB, %s; CPU %.3f %%; threads %d to %d, most %d; "
          "fds %d to %d, most %d.\n\n" % (
              dt, foot[-1] - foot[0], "%.2f MB a day by least squares" % growth if growth is not None else "no slope",
              (p(b, "cpuNs") - p(a, "cpuNs")) / 1e9 / dt * 100 if dt else 0,
              p(a, "threads"), p(b, "threads"), max(p(s, "threads") for s in good),
              p(a, "fds"), p(b, "fds"), max(p(s, "fds") for s in good)))
    w("Churn: %s steps, %s worktrees made and %s removed, %s servers started and %s stopped, %s agents started and "
      "%s stopped. The soak published %s snapshots, opened %s menus and hovered %s cards in %s rounds. The most "
      "findings at once: %s. The most agents %s and sessions %s.\n\n" % (
          churn.get("steps"), churn.get("worktreesMade"), churn.get("worktreesRemoved"),
          churn.get("serversStarted"), churn.get("serversStopped"), churn.get("agentsStarted"), churn.get("agentsStopped"),
          summary.get("snapshots"), summary.get("menusOpened"), summary.get("cardsHovered"), summary.get("menuRounds"),
          ", ".join("%s %s" % kv for kv in sorted((summary.get("peakFindings") or {}).items())),
          summary.get("peakAgents"), summary.get("peakSessions")))
    w("| Check | Result | Got |\n|---|---|---|\n")
    for name, ok, got in checks:
        w("| %s | %s | %s |\n" % (name, "pass" if ok else ("not judged" if ok is None else "FAIL"), got))
    w("\n%d status lines.\n" % len(status))
    return 0 if all(ok or ok is None for _, ok, _ in checks) else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.stderr.write("usage: report.py <out>\n")
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
