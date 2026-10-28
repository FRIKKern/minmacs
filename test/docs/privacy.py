#!/usr/bin/env python3
# Checks docs/PRIVACY.md against the code that builds what the review sends to the model.
# Usage: python3 -I test/docs/privacy.py [repo root] [--keys]
# For each expert it reads the body of the function its reviewRequest uses for factsFor, and for the broker the
# functions that wrap those facts into a call. It collects every key those bodies write: x[@"key"] = ...,
# @{@"key": ...} and the lists in for (NSString *k in @[...]). Then it checks, per section of PRIVACY.md:
#   - every key the code writes is the first key named in a table row of that section
#   - every key a table row names first is one the code writes, so no row is stale
# An expert's function may write keys only as literals or from a for-list of literals, so none is missed.
# It prints one line per check as "ok <name>" or "FAIL <name>: <what>", and exits 1 on a failure.
import os, re, sys

ROOT = next((a for a in sys.argv[1:] if not a.startswith("--")), os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# section heading in PRIVACY.md: [(file, the line that opens the function), ...]
SOURCES = {
    "Every review call": [
        ("Sources/Core/Review/MMReview.m", "static NSDictionary *BatchInput("),
        ("Sources/Core/Review/MMReview.m", "- (void)judge:(NSArray<MMFinding *> *)findings request:(MMReviewRequest *)q into:(MMReview *)r {"),
        ("Sources/Core/Review/MMReview.m", "- (NSString *)summarize:(MMReview *)r counts:"),
    ],
    "MinMacs": [("Sources/Experts/MinMacs/MMMinMacsExpert.m", "- (NSDictionary *)reviewFactsFor:(MMFinding *)f {")],
    "LocoHost": [("Sources/Experts/LocoHost/MMLocoHost.m", "static NSDictionary *ReviewFacts(MMFinding *f) {")],
    "WorkForest": [("Sources/Experts/WorkForest/MMWorkForest.m", "static NSDictionary *ReviewFacts(MMFinding *f, NSArray<NSString *> *servers) {")],
    "Noo-Noo": [("Sources/Experts/NooNoo/MMNooNooExpert.m", "- (NSDictionary *)reviewFactsFor:(MMFinding *)f {")],
}
# The factsFor block each reviewRequest sets, so a check fails when an expert starts sending through another function.
FACTS_FOR = {
    "MinMacs": ("Sources/Experts/MinMacs/MMMinMacsExpert.m", "r.factsFor = ^NSDictionary *(MMFinding *f) { return [me reviewFactsFor:f]; };"),
    "LocoHost": ("Sources/Experts/LocoHost/MMLocoHost.m", "q.factsFor = ^NSDictionary *(MMFinding *f) { return ReviewFacts(f); };"),
    "WorkForest": ("Sources/Experts/WorkForest/MMWorkForest.m", "q.factsFor = ^NSDictionary *(MMFinding *f) { return ReviewFacts(f, [servers[f.findingID] valueForKey:@\"value\"]); };"),
    "Noo-Noo": ("Sources/Experts/NooNoo/MMNooNooExpert.m", "r.factsFor = ^NSDictionary *(MMFinding *f) { return [me reviewFactsFor:f]; };"),
}
INSOMNIA = ("Sources/Experts/Insomnia/MMInsomniaExpert.m", "- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s { return nil; }")

failed = 0


def report(ok, name, what=""):
    global failed
    if ok:
        print("ok %s" % name)
    else:
        failed += 1
        print("FAIL %s: %s" % (name, what))


def read(path):
    return open(os.path.join(ROOT, path)).read()


def body(path, opener):
    text = read(path)
    i = text.find(opener)
    if i < 0:
        return None
    j = text.index("{", i + len(opener) - 1 if opener.endswith("{") else i)
    depth = 0
    for k in range(j, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return text[j:k + 1]
    return None


def keys_in(code):
    code = re.sub(r"//[^\n]*", "", code)
    keys = set(re.findall(r'\w+\[@"(\w+)"\]\s*=(?!=)', code))
    keys |= set(re.findall(r'@"(\w+)"\s*:(?!:)', code))
    for lst in re.findall(r"for \(NSString \*\w+ in @\[(.*?)\]\)", code):
        keys |= set(re.findall(r'@"(\w+)"', lst))
    return keys


def unread_writes(code):
    """Writes keys_in cannot name: a key from a variable outside a for-list, or a merge of another dictionary."""
    code = re.sub(r"//[^\n]*", "", code)
    loop_vars = set(re.findall(r"for \(NSString \*(\w+) in @\[", code))
    out = ["[%s] = " % k for k in re.findall(r'\w+\[(\w+)\]\s*=(?!=)', code) if k not in loop_vars]
    out += [m for m in ("addEntriesFromDictionary", "setObject:", "setValue:", "setDictionary:") if m in code]
    return out


def doc_sections():
    text = open(os.path.join(ROOT, "docs", "PRIVACY.md")).read()
    out, name = {}, None
    for line in text.splitlines():
        m = re.match(r"^## (.+)$", line)
        if m:
            name = m.group(1).strip()
            out[name] = set()
            continue
        if name and line.startswith("|") and not re.match(r"^\|\s*-", line):
            first = line.split("|")[1]
            m = re.search(r"`([\w]+)`", first)
            if m:
                out[name].add(m.group(1))
    return out


docs = doc_sections()
found = {}
for section, parts in SOURCES.items():
    keys = set()
    for path, opener in parts:
        b = body(path, opener)
        report(b is not None, "%s: finds the function in %s" % (section, path), "no line starts %r" % opener)
        if b:
            keys |= keys_in(b)
            if section != "Every review call":
                odd = unread_writes(b)
                report(not odd, "%s: every key in %s is a literal the reader can name" % (section, path), "found %s" % ", ".join(odd))
    found[section] = keys
for section, (path, line) in FACTS_FOR.items():
    report(line in read(path), "%s: its reviewRequest sends the facts of the function read here" % section, "factsFor changed in %s" % path)
report(INSOMNIA[1] in read(INSOMNIA[0]), "Insomnia: its reviewRequest returns nil, so it sends nothing", "it changed in %s" % INSOMNIA[0])

if "--keys" in sys.argv:
    for s in found:
        print("%s: %s" % (s, " ".join(sorted(found[s]))))

for section, keys in found.items():
    listed = docs.get(section)
    report(listed is not None, "PRIVACY.md has a section %s" % section, "no heading '## %s'" % section)
    if listed is None:
        continue
    missing = sorted(keys - listed)
    report(not missing, "PRIVACY.md lists every key %s sends" % section, "not listed: %s" % ", ".join(missing))
    stale = sorted(listed - keys)
    report(not stale, "PRIVACY.md lists no key %s does not send" % section, "not sent: %s" % ", ".join(stale))
    report(len(keys) >= 3, "%s: the reader found its keys" % section, "only %d" % len(keys))

sys.exit(1 if failed else 0)
