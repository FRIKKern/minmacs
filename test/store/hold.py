import sqlite3, sys, time
# Makes a new log file in rollback mode and holds a read lock on it, so writers that open it meet a held lock.
c = sqlite3.connect(sys.argv[1], isolation_level=None)
c.execute("PRAGMA user_version=1")
c.execute("BEGIN")
c.execute("SELECT count(*) FROM sqlite_master").fetchall()
open(sys.argv[1] + ".held", "w").close()
time.sleep(float(sys.argv[2]))
c.execute("COMMIT")
