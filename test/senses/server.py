# A fixture for test/senses.sh: one TCP listener on 127.0.0.1, one connection to it from this
# same process, and one child process. It writes its port to the file named in argv[1], then waits.
# It exits when its parent shell ends it, or after 120 seconds at most.
import os, socket, subprocess, sys, time

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.bind(("127.0.0.1", 0))
srv.listen(4)
port = srv.getsockname()[1]
cli = socket.create_connection(("127.0.0.1", port))
conn, _ = srv.accept()
kid = subprocess.Popen(["/bin/sleep", "120"])
with open(sys.argv[1] + ".tmp", "w") as f:
    f.write("%d %d\n" % (port, kid.pid))
os.rename(sys.argv[1] + ".tmp", sys.argv[1])
try:
    time.sleep(120)
finally:
    kid.terminate()
