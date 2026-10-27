#!/usr/bin/env python3
"""Checks each clutter row against registry/clutter-schema.json and the catalog's own rules. No dependencies.
   test/noonoo/validate_clutter.py registry/clutter/*.json     exit 0 when every row passes"""
import json, os, re, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
S = json.load(open(os.path.join(ROOT, "registry/clutter-schema.json")))
WALLS = ("/System", "/Library", "/usr", "/bin", "/sbin", "/private/etc", "/Applications")

def check(node, schema, path, errs):
    if "enum" in schema and node not in schema["enum"]: errs.append(f"{path}: {node!r} not in {schema['enum']}")
    t = schema.get("type")
    if t == "object":
        if not isinstance(node, dict): errs.append(f"{path}: expected object"); return
        for k in schema.get("required", []):
            if k not in node: errs.append(f"{path}: missing {k}")
        for k, v in node.items():
            if k not in schema.get("properties", {}) and path == "row": errs.append(f"{path}: unknown field {k}")
            elif k in schema.get("properties", {}): check(v, schema["properties"][k], f"{path}.{k}", errs)
    elif t == "array":
        if not isinstance(node, list): errs.append(f"{path}: expected array"); return
        for i, v in enumerate(node): check(v, schema.get("items", {}), f"{path}[{i}]", errs)
    elif t == "string":
        if not isinstance(node, str): errs.append(f"{path}: expected string")
        elif "pattern" in schema and not re.match(schema["pattern"], node): errs.append(f"{path}: {node!r} does not match {schema['pattern']}")
    elif t == "boolean" and not isinstance(node, bool): errs.append(f"{path}: expected boolean")
    elif t == "number" and not isinstance(node, (int, float)): errs.append(f"{path}: expected number")

bad = 0
for f in sys.argv[1:]:
    errs = []
    try: row = json.load(open(f))
    except Exception as e: print(f"FAIL {f}: not JSON: {e}"); bad += 1; continue
    check(row, S, "row", errs)
    if row.get("id") != os.path.splitext(os.path.basename(f))[0]: errs.append("row.id must equal the file name")
    c = row.get("class")
    if not row.get("paths") and not row.get("names"): errs.append("a row needs paths or names")
    if c == "tool" and not row.get("cleanup"): errs.append("a tool row needs its own cleanup command")
    if c != "tool" and "cleanup" in row: errs.append("only a tool row runs a command")
    if c == "leak" and not row.get("signature"): errs.append("a leak row needs a signature")
    if c in ("data", "report") and not row.get("ownerSetting") and c == "data": errs.append("a data row says who keeps it in ownerSetting")
    if row.get("every", 0) < 600: errs.append("every must be at least 600 seconds")
    for p in row.get("paths", []):
        if p in ("~", "/", "~/") or (not p.startswith("${") and p.rstrip("/").count("/") < 1): errs.append(f"{p}: a row never names the home folder or /")
        acts = c in ("cache", "build", "leak", "tool")
        if acts and p.startswith(WALLS) and row.get("reportOnlyWhen") != "root-owned":
            errs.append(f"{p}: a path under a wall is never acted on")
    if row.get("names") and c != "build": errs.append("names are for build rows")
    print(("FAIL " if errs else "ok   ") + f); [print("     " + e) for e in errs]; bad += bool(errs)
sys.exit(1 if bad else 0)
