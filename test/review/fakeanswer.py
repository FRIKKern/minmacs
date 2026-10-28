# The answers fakeclaude.py and fakecodex.py give, from the broker's input on stdin. Ported from LocoHost's tools/fakeanswer.py.
# The words come from the schema: its verdict enum lists the expert's keep, go and unsure words in that order.
# Review: a finding whose id names an entry of $RV_TEST_GO gets the go word, of $RV_TEST_UNSURE the unsure word,
# and every other finding the keep word. Each review call is appended to $RV_TEST_SENT, one line per call.
# With $RV_TEST_FACTS set, the verdict comes from the facts instead, by decide() below, so two layouts of the same
# facts get the same answer. The day replay of test/review/day.m uses that.
# Judge, known by "decision" in its schema: ids naming an entry of $RV_TEST_KEEP are kept with evidence, every other
# one goes. Its input is saved to $RV_TEST_SENT.judge. The summary call after several batches answers with a count of its lines.
import json, os

def names(var):
    return [n for n in os.environ.get(var, "").split(",") if n]

def named(i, var):
    return any(n in i for n in names(var))

def items(j):
    """Each finding with the facts of its block and of the call, as the system prompt's note says to read them.
    The 1.x layout of the day replay's baseline, a plain list under worktrees or hosts, reads as it is."""
    out = []
    common = j.get("all", {})
    for b in j.get("blocks", []):
        for f in b.get("f", []):
            x = dict(common)
            x.update(b.get("ws", {}))
            x.update(f)
            out.append(x)
    for key in ("worktrees", "hosts"):
        if isinstance(j.get(key), list):
            for f in j[key]:
                x = dict(f)
                if "quiet_after_minutes" in j: x.setdefault("quiet_after_minutes", j["quiet_after_minutes"])
                out.append(x)
    return out

def num(x, k):
    v = x.get(k)
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None

def decide(x, words):
    """A stand-in for the model, from the facts alone: (kind, confidence), kind one of keep, go, unsure.
    It follows the evidence lists of the old WorkForest and LocoHost prompts. A fact that is missing counts as 0 or false."""
    keep, go, unsure = words
    s = x.get("agent_session") or {}
    if go == "stale":
        quiet = num(x, "quiet_days") or 0
        if (num(x, "dirty_files") or 0) > 0 or (num(x, "untracked_files") or 0) > 0 or x.get("processes") or x.get("servers"):
            return "keep", 0.9
        if s.get("working_now") or (num(s, "last_active_minutes_ago") is not None and s["last_active_minutes_ago"] < 1440):
            return "keep", 0.85
        if x.get("locked") or x.get("protected"):
            return "keep", 0.9
        if (num(x, "unpushed_commits") or 0) > 0 and not x.get("merged"):
            return ("unsure", 0.5) if quiet >= 14 else ("keep", 0.75)
        if (x.get("merged") or x.get("upstream") == "gone") and quiet >= 3:
            return "go", 0.85
        if quiet >= 30:
            return "go", 0.65
        return ("keep", 0.7) if quiet < 1 else ("unsure", 0.5)
    if go == "idle":
        if x.get("kind") not in (None, "dev"):
            return "keep", 0.8
        quiet_after = num(x, "quiet_after_minutes") or 30
        since = num(x, "minutes_since_activity")
        if since is not None and since < quiet_after:
            return "keep", 0.9
        if (num(x, "new_connections_now") or 0) > 0 or x.get("cpu_busy_now"):
            return "keep", 0.9
        if num(s, "last_active_minutes_ago") is not None and s["last_active_minutes_ago"] < 60:
            return "keep", 0.8
        if x.get("parent_exited") and (since is None or since >= 120):
            return "go", 0.85
        return "unsure", 0.5
    return "keep", 0.7

def prose(name, kind):
    """Text of the length research F measured for each answer field: the routine fields are short, and the
    prose fields of the 1.x schemas are one sentence of about 25 words."""
    if name == "about": return "fixture %s worktree of a test repo, merged some days ago" % kind
    if name in ("reason",): return "The fixture facts decided it: the activity, the git state and the session are as listed above."
    if name in ("keep_evidence", "evidence"): return "an agent session was active in it today" if kind == "keep" else ""
    return "One plain sentence of about twenty five words built only from the facts, as the 1.x prompts asked for every field here."

def answer(data, schema):
    j = json.loads(data)
    s = json.loads(schema)
    sent = os.environ["RV_TEST_SENT"]
    if "lines" in j:
        open(sent + ".summary", "w").write(data)
        return {"summary": "Fixture overall summary: %d lines." % len(j["lines"])}
    list_key = [k for k in s["properties"] if k != "summary"][0]   # items, or trees and hosts in the 1.x schemas
    item = s["properties"][list_key]["items"]["properties"]
    if "decision" in item:
        open(sent + ".judge", "a").write(data + "\n")
        keep, go = item["decision"]["enum"]
        return {list_key: [{"id": f["id"], "decision": keep if named(f["id"], "RV_TEST_KEEP") else go, "confidence": 0.9,
                            "evidence": "fixture: a test client still uses it" if named(f["id"], "RV_TEST_KEEP") else "",
                            "reason": "the fixture judge says so"} for f in items(j)]}
    open(sent, "a").write(data + "\n")
    words = item["verdict"]["enum"]
    keep, go, unsure = words
    fs = items(j)
    if os.environ.get("RV_TEST_CLOCK"):   # the day replay: which ids each review call got, at which tick
        open(sent + ".ids", "a").write(json.dumps({"clock": float(os.environ["RV_TEST_CLOCK"]), "ids": [f["id"] for f in fs]}) + "\n")
    if os.environ.get("RV_TEST_FACTS"):
        out = []
        for f in fs:
            kind, conf = decide(f, words)
            a = {"id": f["id"], "verdict": {"keep": keep, "go": go, "unsure": unsure}[kind], "confidence": conf}
            for name, spec in item.items():
                if name not in a and spec.get("type") == "string": a[name] = prose(name, kind)
            out.append(a)
        return {"summary": "Fixture summary: %d items." % len(fs), list_key: out}
    def verdict(i):
        return go if named(i, "RV_TEST_GO") else unsure if named(i, "RV_TEST_UNSURE") else keep
    return {"summary": "Fixture summary: %d items." % len(fs),
            list_key: [{"id": f["id"], "verdict": verdict(f["id"]), "confidence": 0.5 if verdict(f["id"]) == unsure else 0.95,
                        "about": "fixture", "reason": "fixture says so", "keep_evidence": ""} for f in fs]}
