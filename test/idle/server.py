# A fixture for test/idle.sh: one TCP listener on 127.0.0.1 that accepts connections and holds them open.
# It writes its port to the file named in argv[1], then blocks in select, so it uses no CPU time while nothing
# connects. It exits after 120 seconds at most, or when the test ends it.
import os, select, socket, sys, time

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.bind(("127.0.0.1", 0))
srv.listen(8)
port = srv.getsockname()[1]
with open(sys.argv[1] + ".tmp", "w") as f:
    f.write("%d\n" % port)
os.rename(sys.argv[1] + ".tmp", sys.argv[1])
held = []
end = time.time() + 120
while time.time() < end:
    r, _, _ = select.select([srv], [], [], max(0.0, end - time.time()))
    if r:
        conn, _ = srv.accept()
        held.append(conn)
