# The answers fakeclaude.py and fakecodex.py give, from the broker's input on stdin. Ported from LocoHost's tools/fakeanswer.py.
# The words come from the schema: its verdict enum lists the expert's keep, go and unsure words in that order.
# Review: a finding whose id names an entry of $RV_TEST_GO gets the go word, of $RV_TEST_UNSURE the unsure word,
# and every other finding the keep word. Each review call is appended to $RV_TEST_SENT, one line per call.
# Judge, known by "decision" in its schema: ids naming an entry of $RV_TEST_KEEP are kept with evidence, every other
# one goes. Its input is saved to $RV_TEST_SENT.judge. The summary call after several batches answers with a count of its lines.
import json, os

def names(var):
    return [n for n in os.environ.get(var, "").split(",") if n]

def named(i, var):
    return any(n in i for n in names(var))

def items(j):
    return [f for b in j.get("blocks", []) for f in b.get("f", [])]

def answer(data, schema):
    j = json.loads(data)
    s = json.loads(schema)
    sent = os.environ["RV_TEST_SENT"]
    if "lines" in j:
        open(sent + ".summary", "w").write(data)
        return {"summary": "Fixture overall summary: %d lines." % len(j["lines"])}
    item = s["properties"]["items"]["items"]["properties"]
    if "decision" in item:
        open(sent + ".judge", "a").write(data + "\n")
        keep, go = item["decision"]["enum"]
        return {"items": [{"id": f["id"], "decision": keep if named(f["id"], "RV_TEST_KEEP") else go, "confidence": 0.9,
                           "evidence": "fixture: a test client still uses it" if named(f["id"], "RV_TEST_KEEP") else "",
                           "reason": "the fixture judge says so"} for f in items(j)]}
    open(sent, "a").write(data + "\n")
    keep, go, unsure = item["verdict"]["enum"]
    def verdict(i):
        return go if named(i, "RV_TEST_GO") else unsure if named(i, "RV_TEST_UNSURE") else keep
    fs = items(j)
    return {"summary": "Fixture summary: %d items." % len(fs),
            "items": [{"id": f["id"], "verdict": verdict(f["id"]), "confidence": 0.5 if verdict(f["id"]) == unsure else 0.95,
                       "about": "fixture", "reason": "fixture says so", "keep_evidence": ""} for f in fs]}
