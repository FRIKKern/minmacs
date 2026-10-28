#!/usr/bin/env python3 -I
"""Compares the day replay's two runs: tokens and verdicts on the same fixture. Prints one JSON object.
Usage: daycompare.py <legacy.json> <broker.json>
A verdict is compared where both runs reviewed the same finding at the same tick: LocoHost every hour, WorkForest
every two hours, the 0.1 cadence. Experts whose 0.1 app asked no model have no verdicts to compare."""
import json, sys
from collections import Counter

old, new = (json.load(open(p)) for p in sys.argv[1:3])
def total(run, key):
    return sum(e[key] for e in run["experts"].values())
same, diff, by = 0, 0, Counter()
pairs = Counter()
for k, v in old["verdicts"].items():
    w = new["verdicts"].get(k)
    if not w: continue
    if w["word"] == v["word"]: same += 1
    else:
        diff += 1
        by[w["by"]] += 1
        pairs["%s to %s" % (v["word"], w["word"])] += 1
per = {}
for e in sorted(set(old["experts"]) | set(new["experts"])):
    o, n = old["experts"].get(e, {}), new["experts"].get(e, {})
    per[e] = {"before": o.get("as_counted_before", 0), "before_uncached": o.get("uncached", 0), "after_uncached": n.get("uncached", 0),
              "after_as_counted_before": n.get("as_counted_before", 0), "findings": n.get("findings", 0), "sent": n.get("sent", 0),
              "decided": n.get("decided", {}), "before_cost": o.get("list_cost_usd", 0), "after_cost": n.get("list_cost_usd", 0)}
before, after = total(old, "uncached"), total(new, "uncached")
reviewed = sum(sum(v for k, v in p["decided"].items()) for p in per.values())
model = sum(p["decided"].get("model", 0) + p["decided"].get("judge", 0) for p in per.values())
cache = sum(p["decided"].get("cache", 0) for p in per.values())
print(json.dumps({"before_uncached": before, "after_uncached": after, "ratio": round(after / before, 4) if before else None,
                  "before_as_counted": total(old, "as_counted_before"), "after_as_counted": total(new, "as_counted_before"),
                  "before_cost": round(total(old, "list_cost_usd"), 6), "after_cost": round(total(new, "list_cost_usd"), 6),
                  "decided": reviewed, "by_model": model, "by_cache": cache, "by_rules": reviewed - model - cache,
                  "verdicts_compared": same + diff, "verdicts_same": same, "verdicts_differ": diff,
                  "differ_by": dict(by), "differ_as": dict(pairs), "experts": per}, indent=1, sort_keys=True))
