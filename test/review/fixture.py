#!/usr/bin/env python3 -I
"""Writes a review fixture for rv: five LocoHost-style findings in two workstreams, plus a service with no owner.
Usage: fixture.py <out.json> <expert> <folder> [--move <id part>]... [--keep <id part>]... [--restart <id part>]... [--head <x>]
--move changes the fingerprint of findings whose id holds the part. --keep gives them a work keep. --restart changes
their instance key and leaves the fingerprint. --head sets the HEAD of the first workstream's worktree, which is abc by default.
The two servers of the first workstream share a branch, and every finding shares quiet_after_minutes.
The folder is the first workstream's. Its findings carry the secrets LocoHost's checks look for."""
import json, os, sys

out, expert, folder = sys.argv[1:4]
opts = {"--move": [], "--keep": [], "--restart": [], "--head": []}
rest = sys.argv[4:]
for i in range(0, len(rest) - 1, 2):
    opts[rest[i]].append(rest[i + 1])
move, keep, restart = opts["--move"], opts["--keep"], opts["--restart"]
head = (opts["--head"] or ["abc"])[-1]
home = os.path.expanduser("~")
ws1 = {"kind": 0, "key": "ws1", "name": "fixture-app", "path": folder}
ws2 = {"kind": 0, "key": "ws2", "name": "other-app", "path": home + "/Documents/other-app"}
cmd = "python3 -m http.server 47100 --api-key SUPERSECRET123 DATABASE_URL=postgres://user:hunter2@db/x"
session = {"title": "Fixture session", "first_prompt": "Start the fixture server, password=HUNTER77 is fine"}
findings = [
    {"id": "%s:server:%s#dev" % (expert, folder), "title": "fixture-app dev", "owner": ws1,
     "facts": {"kind": "dev", "ports": [47100], "command": cmd, "project": {"name": "fixture-app", "description": "Fixture project"},
               "agent_session": session, "folder": home + "/Documents/fixture-app", "locked": False, "dirty": 0, "pr": None, "branch": "main"}},
    {"id": "%s:server:%s#api" % (expert, folder), "title": "fixture-app api", "owner": ws1,
     "facts": {"kind": "dev", "ports": [47101], "command": "python3 -m http.server 47101", "uptime_minutes": 90, "branch": "main"}},
    {"id": "%s:server:%s#docs" % (expert, home + "/Documents/other-app"), "title": "other-app docs", "owner": ws2,
     "facts": {"kind": "dev", "ports": [47102], "command": "python3 -m http.server 47102"}},
    {"id": "%s:server:%s#web" % (expert, home + "/Documents/other-app"), "title": "other-app web", "owner": ws2,
     "facts": {"kind": "dev", "ports": [47103], "command": "python3 -m http.server 47103"}},
    {"id": "%s:service:postgres" % expert, "title": "PostgreSQL",
     "facts": {"kind": "service", "ports": [47104], "command": "postgres -D data"}},
]
for n, f in enumerate(findings):
    f["fingerprint"] = "fp-moved" if any(m in f["id"] for m in move) else "fp-1"
    f["instance"] = "%d:%d" % (900 + n, 2 if any(r in f["id"] for r in restart) else 1)
    f["facts"]["quiet_after_minutes"] = 30
    if any(k in f["id"] for k in keep):
        f["keep_reasons"] = ["3 uncommitted files"]
facts = {"worktrees": [{"path": folder, "head": head}], "sessions": [{"cwd": folder, "ago": 7200, "working": False}]}
json.dump({"expert": expert, "words": ["in_use", "idle", "unsure"], "system": "You review fixture servers.", "findings": findings, "facts": facts},
          open(out, "w"), indent=1)
