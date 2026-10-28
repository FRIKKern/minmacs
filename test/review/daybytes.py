#!/usr/bin/env python3 -I
"""Research F's compression, measured on the day replay's own 1.x calls: the same inputs in each encoding.
Usage: daybytes.py <legacy sent.json>
The file holds each input the 1.x replay sent, one after the other, pretty-printed. It is encoded four ways and the bytes are summed:
pretty: as sent, pretty-printed as WorkForest 0.1 and LocoHost 0.1 did. compact: no spaces, sorted keys.
dropped: compact, with null, false, zero and empty values dropped, as MMCompactFacts does.
blocks: dropped, with every value all findings of the call share sent once in all, as the broker's BatchInput does.
Tokens are bytes over 4, as fakecount.py counts them."""
import json, sys

def drop(v):
    if v is None or v is False: return None
    if isinstance(v, bool): return v
    if isinstance(v, (int, float)): return None if v == 0 else v
    if isinstance(v, str): return v or None
    if isinstance(v, list):
        l = [x for x in (drop(i) for i in v) if x is not None]
        return l or None
    if isinstance(v, dict):
        d = {k: x for k, x in ((k, drop(i)) for k, i in v.items()) if x is not None}
        return d or None
    return v

def compact(o):
    return json.dumps(o, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

def hoist(o):
    key = "worktrees" if "worktrees" in o else "hosts"
    fs = o.get(key) or []
    if len(fs) < 2: return o
    same = {k: v for k, v in fs[0].items() if k != "id" and all(k in f and f[k] == v for f in fs)}
    return dict(o, all=same, **{key: [{k: v for k, v in f.items() if k not in same} for f in fs]}) if same else o

sums = {"pretty": 0, "compact": 0, "dropped": 0, "blocks": 0, "calls": 0}
text, dec, i = open(sys.argv[1]).read(), json.JSONDecoder(), 0
while True:
    while i < len(text) and text[i].isspace(): i += 1
    if i >= len(text): break
    o, end = dec.raw_decode(text, i)
    raw, i = text[i:end], end
    if "lines" in o: continue   # the summary call
    sums["calls"] += 1
    sums["pretty"] += len(raw.encode())
    sums["compact"] += len(compact(o).encode())
    d = drop(o)
    sums["dropped"] += len(compact(d).encode())
    sums["blocks"] += len(compact(hoist(d)).encode())
print(json.dumps(sums, sort_keys=True))
