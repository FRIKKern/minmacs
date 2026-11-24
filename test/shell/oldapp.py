# A fake MinMacs app of an older build on core.sock: it answers ping with its version and build, and every CLI
# request as an app from before "unknownVerb" did, with exit 2 and only the error line. It runs nothing.
#   oldapp.py <socket> <log>      each request it took goes to <log>, one JSON line each
import json
import os
import socket
import sys

os.setsid()
path, log = sys.argv[1], sys.argv[2]
# It listens under another name first, so the socket shows at its path only once it takes connections.
tmp = path + ".new"
for p in (path, tmp):
    if os.path.exists(p):
        os.unlink(p)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(tmp)
os.chmod(tmp, 0o600)
srv.listen(8)
os.rename(tmp, path)
while True:
    c, _ = srv.accept()
    c.settimeout(5)
    d = b""
    try:
        while b"\n" not in d:
            b = c.recv(65536)
            if not b:
                break
            d += b
        req = json.loads(d.split(b"\n")[0] or b"{}")
    except (OSError, ValueError):
        c.close()
        continue
    with open(log, "a") as f:
        f.write(json.dumps(req) + "\n")
    if req.get("verb") == "ping":
        rep = {"ok": True, "pid": os.getpid(), "version": "1.9.0", "build": "41"}
    elif req.get("verb") == "cli":
        w = (req.get("cli") or [""])[0]
        rep = {"status": 2, "out": "", "err": "minmacs: unknown verb '%s'. Try 'minmacs help'.\n" % w, "inApp": True}
    else:
        rep = {"error": "no verb %s in the running app" % req.get("verb")}
    try:
        c.sendall((json.dumps(rep) + "\n").encode())
    except OSError:
        pass
    c.close()
