"""Makes a fake Codex home for the Know checks: state_5.sqlite and thread_history_1.sqlite in WAL mode.
Usage: codexdb.py <codex home> <cwd> <turn status>        writes both files and closes them, so no -wal or -shm is left
       codexdb.py <codex home> --hold <seconds> <status>  keeps a connection open, so the -shm file exists, and sets
                                                          the newest turn's status while it holds the file
Only the columns MinMacs reads are made, plus archived. Times are in seconds, as Codex writes them."""
import os, sqlite3, sys, time

home = sys.argv[1]
os.makedirs(home, exist_ok=True)
state, hist = os.path.join(home, "state_5.sqlite"), os.path.join(home, "thread_history_1.sqlite")
now = int(time.time())

if sys.argv[2] == "--hold":
    db = sqlite3.connect(hist)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("UPDATE thread_turns SET status=? WHERE thread_id='thread-live' AND turn_id='t2'", (sys.argv[4],))
    db.commit()
    print("held", flush=True)
    time.sleep(float(sys.argv[3]))
    sys.exit(0)

cwd, status = sys.argv[2], sys.argv[3]
for f in (state, hist):
    for x in (f, f + "-wal", f + "-shm"):
        if os.path.exists(x): os.remove(x)
db = sqlite3.connect(state)
db.execute("PRAGMA journal_mode=WAL")
db.execute("""CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL, cwd TEXT NOT NULL, title TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0,
  git_branch TEXT)""")
db.execute("INSERT INTO threads VALUES ('thread-live', '/fixture/rollout-live.jsonl', ?, ?, ?, 'Fixture thread', 0, 'fixture-branch')",
           (now - 600, now - 30, cwd))
db.execute("INSERT INTO threads VALUES ('thread-old', '/fixture/rollout-old.jsonl', ?, ?, ?, 'Archived thread', 1, NULL)",
           (now - 900, now - 800, cwd))
db.commit(); db.execute("PRAGMA wal_checkpoint(TRUNCATE)"); db.close()
db = sqlite3.connect(hist)
db.execute("PRAGMA journal_mode=WAL")
db.execute("""CREATE TABLE thread_turns (thread_id TEXT NOT NULL, turn_id TEXT NOT NULL, rollout_ordinal INTEGER NOT NULL,
  status TEXT NOT NULL, started_at INTEGER, completed_at INTEGER, rollout_end_ordinal INTEGER, PRIMARY KEY (thread_id, turn_id))""")
db.execute("INSERT INTO thread_turns VALUES ('thread-live', 't1', 1, 'completed', ?, ?, 5)", (now - 500, now - 400))
db.execute("INSERT INTO thread_turns VALUES ('thread-live', 't2', 6, ?, ?, NULL, NULL)", (status, now))
db.commit(); db.execute("PRAGMA wal_checkpoint(TRUNCATE)"); db.close()
# Nothing holds the files now, as when no Codex runs, so no -wal or -shm file is left.
for f in (state, hist):
    for x in (f + "-wal", f + "-shm"):
        if os.path.exists(x): os.remove(x)
