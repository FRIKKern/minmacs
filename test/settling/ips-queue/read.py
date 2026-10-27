#!/usr/bin/env python3 -I
"""Prints each thread's queue and name from the newest mm-ips-probe crash report, and the
crash-breadcrumb fields MinMacs could use. Read-only."""
import glob, json, os, sys
d = os.path.expanduser("~/Library/Logs/DiagnosticReports")
files = sorted(glob.glob(os.path.join(d, sys.argv[1] if len(sys.argv) > 1 else "mm-ips-probe*.ips")), key=os.path.getmtime)
if not files:
    print("no report yet"); sys.exit(1)
p = files[-1]
t = open(p, errors="replace").read()
i = t.find("\n")
hdr, body = json.loads(t[:i]), json.loads(t[i + 1:])
print("report", os.path.basename(p), "bug_type", hdr.get("bug_type"), "os", hdr.get("os_version"))
print("exception", body.get("exception", {}).get("type"), body.get("exception", {}).get("signal"))
print("faultingThread", body.get("faultingThread"))
for n, th in enumerate(body.get("threads", [])):
    print(f"  thread {n}: triggered={th.get('triggered', False)} queue={th.get('queue')} name={th.get('name')}")
print("asi", json.dumps(body.get("asi"))[:200])
