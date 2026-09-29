#!/usr/bin/env python3
"""Structural check of a registry row against registry/schema.json. No dependencies.
   tools/validate_row.py registry/agents/codex.json [...]   exit 0 when every row passes"""
import json, os, re, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
S = json.load(open(os.path.join(ROOT, "registry/schema.json")))

def check(node, schema, path, errs):
    t = schema.get("type")
    if "enum" in schema and node not in schema["enum"]: errs.append(f"{path}: {node!r} not in {schema['enum']}")
    if t == "object":
        if not isinstance(node, dict): errs.append(f"{path}: expected object"); return
        for k in schema.get("required", []):
            if k not in node: errs.append(f"{path}: missing {k}")
        for k, v in node.items():
            if k in schema.get("properties", {}): check(v, schema["properties"][k], f"{path}.{k}", errs)
    elif t == "array":
        if not isinstance(node, list): errs.append(f"{path}: expected array"); return
        if len(node) < schema.get("minItems", 0): errs.append(f"{path}: needs at least {schema['minItems']} item(s)")
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
    if row.get("confidence") == "verified-locally" and not any(s.get("kind") == "local-observation" for s in row.get("sources", [])):
        errs.append("confidence verified-locally needs at least one local-observation source")
    if any(not s.get("evidence", "").strip() for s in row.get("sources", [])): errs.append("every source needs evidence")
    print(("FAIL " if errs else "ok   ") + f); [print("     " + e) for e in errs]; bad += bool(errs)
sys.exit(1 if bad else 0)
