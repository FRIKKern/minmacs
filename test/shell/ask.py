# Sends one CLI request over core.sock, as the CLI does, and prints the status and whether the verb printed.
#   ask.py <socket> <word> ...
import json
import socket
import sys

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(sys.argv[1])
s.sendall(json.dumps({"cli": sys.argv[2:]}).encode())
s.shutdown(socket.SHUT_WR)
d = b""
while True:
    b = s.recv(65536)
    if not b:
        break
    d += b
r = json.loads(d)
print(r["status"], bool(r.get("out")))
