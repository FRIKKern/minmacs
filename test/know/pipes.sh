# Issue #96: a session file, a project file or another tool's file that is a named pipe, a socket or a device.
# Sourced by test/know.sh after its sessions checks, with $K, $KT, start, stop, check and json set.
# No writer ever opens these pipes, unless a check starts one, so an open of one for reading waits for ever. Every read
# runs under `knowtool within 2`: one that waits prints "stuck", which fails its check, and the tool ends with it, so
# the run never waits on the stuck thread.

KP="$K/pipes96"; mkdir -p "$KP"
# The session read with one odd file in place, then the file gone. Prints stuck, or three facts: the id the fixture
# transcript still gives, how many sessions the odd file gave (its name holds "96-<pid>"), and how many Codex threads.
kp_sessions() { # path [kind: fifo, the default, or zero for a link to /dev/zero]
  rm -f "$1"; if [ "${2:-fifo}" = zero ]; then ln -s /dev/zero "$1"; else mkfifo "$1"; fi
  kp_out=$("$KT" within 2 sessions --id sess-transcript)
  rm -f "$1"
  [ "$kp_out" = stuck ] && echo stuck || printf '%s' "$kp_out" | json "'%s odd=%d codex=%d' % (j['withID']['id'],
    len([x for x in j['all'] if '96-$$' in x['id']]), len([x for x in j['all'] if x['agent'] == 'codex']))" 2>/dev/null
}
check "a Claude Code transcript that is a named pipe is no session, and the read returns" "sess-transcript odd=0 codex=1" \
  "$(kp_sessions "$CLAUDE_CONFIG_DIR/projects/fixture/pipe96-$$.jsonl")"
check "a Claude Code transcript that links to /dev/zero is no session" "sess-transcript odd=0 codex=1" \
  "$(kp_sessions "$CLAUDE_CONFIG_DIR/projects/fixture/zero96-$$.jsonl" zero)"
check "a Claude Code status file that is a named pipe is skipped" "sess-transcript odd=0 codex=1" \
  "$(kp_sessions "$CLAUDE_CONFIG_DIR/sessions/96096.json")"
check "a pi session file that is a named pipe is no session" "sess-transcript odd=0 codex=1" \
  "$(kp_sessions "$K/pi/sessions/--fixture--/2026-10-27T10-00-00-000Z_pipe96-$$.jsonl")"
mkdir -p "$KP/codex-db"
check "a Codex database that is a named pipe gives no threads" "sess-transcript odd=0 codex=0" \
  "$(CODEX_HOME="$KP/codex-db" kp_sessions "$KP/codex-db/state_5.sqlite")"
python3 test/know/codexdb.py "$KP/codex-shm" "$K/proj" completed
check "a Codex database whose -shm file is a named pipe gives no threads" "sess-transcript odd=0 codex=0" \
  "$(CODEX_HOME="$KP/codex-shm" kp_sessions "$KP/codex-shm/state_5.sqlite-shm")"
# While Codex holds its databases the -shm files exist, so they are read with mode=ro. SQLite's first read then looks
# for a hot journal and opens <db>-journal with no O_NONBLOCK, so a pipe there would wait for ever.
python3 test/know/codexdb.py "$KP/codex-held" "$K/proj" completed
start python3 -u -c 'import sqlite3, sys, time
dbs = [sqlite3.connect(sys.argv[1] + "/" + n) for n in ("state_5.sqlite", "thread_history_1.sqlite")]
for d in dbs: d.execute("PRAGMA journal_mode=WAL"); d.execute("SELECT count(*) FROM sqlite_master").fetchall()
print("held", flush=True); time.sleep(30)' "$KP/codex-held" >"$KP/held.out"; KPH=$LAST
for i in 1 2 3 4 5 6 7 8 9 10; do grep -q held "$KP/held.out" 2>/dev/null && break; sleep 0.3; done
check "  the held databases have their -shm files" yes \
  "$([ -e "$KP/codex-held/state_5.sqlite-shm" ] && [ -e "$KP/codex-held/thread_history_1.sqlite-shm" ] && echo yes || echo no)"
check "a held Codex database whose -journal is a named pipe gives no threads" "sess-transcript odd=0 codex=0" \
  "$(CODEX_HOME="$KP/codex-held" kp_sessions "$KP/codex-held/state_5.sqlite-journal")"
check "a held turn history whose -journal is a named pipe is not read, and the threads stay" "sess-transcript odd=0 codex=1" \
  "$(CODEX_HOME="$KP/codex-held" kp_sessions "$KP/codex-held/thread_history_1.sqlite-journal")"
stop "$KPH"; procs=$(printf '%s' "$procs" | sed "s/ $KPH\$//;s/ $KPH / /")

echo "-- MMReadPlain, the one read of a file whose path comes from the disk"
kp_plain() { # path max part: nil:length:text, or stuck
  kp_out=$("$KT" within 2 plain "$1" "$2" "$3")
  [ "$kp_out" = stuck ] && echo stuck || printf '%s' "$kp_out" | json "'%s:%d:%s' % (j['nil'], j['length'], j['text'])" 2>/dev/null
}
printf 'hello world' >"$KP/plain"
check "a plain file reads whole" "False:11:hello world" "$(kp_plain "$KP/plain" 100 whole)"
check "  its head" "False:5:hello" "$(kp_plain "$KP/plain" 5 head)"
check "  its tail" "False:5:world" "$(kp_plain "$KP/plain" 5 tail)"
check "  and whole past max is nil" "True:0:" "$(kp_plain "$KP/plain" 10 whole)"
: >"$KP/empty"
check "an empty plain file reads as no bytes, not nil" "False:0:" "$(kp_plain "$KP/empty" 100 whole)"
ln -sf "$KP/plain" "$KP/to-plain"
check "a link to a plain file reads as the file" "False:11:hello world" "$(kp_plain "$KP/to-plain" 100 whole)"
check "a missing file is nil" "True:0:" "$(kp_plain "$KP/none" 100 whole)"
check "a folder is nil" "True:0:" "$(kp_plain "$KP" 100 whole)"
rm -f "$KP/fifo"; mkfifo "$KP/fifo"; ln -sf "$KP/fifo" "$KP/to-fifo"
check "a named pipe with no writer is nil, at once" "True:0:" "$(kp_plain "$KP/fifo" 100 head)"
check "a link to it is nil" "True:0:" "$(kp_plain "$KP/to-fifo" 100 whole)"
# A writer waits in its open until a reader comes, and marks the moment it got through. MMReadPlain never opens the
# pipe, so the writer still waits after, and no mark is made.
start sh -c 'exec 3>"$0" && : >"$1"; exec sleep 30' "$KP/fifo" "$KP/opened"; KPW=$LAST
sleep 0.3
check "a named pipe with a writer waiting is nil" "True:0:" "$(kp_plain "$KP/fifo" 100 tail)"
sleep 0.3
check "  and the writer still waits: the pipe was never opened" no "$([ -e "$KP/opened" ] && echo yes || echo no)"
stop "$KPW"; procs=$(printf '%s' "$procs" | sed "s/ $KPW\$//;s/ $KPW / /")
python3 -c "import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])" "$KP/sock"
ln -sf "$KP/sock" "$KP/to-sock"
check "a socket is nil" "True:0:" "$(kp_plain "$KP/sock" 100 whole)"
check "a link to a socket is nil" "True:0:" "$(kp_plain "$KP/to-sock" 100 whole)"
ln -sf /dev/zero "$KP/to-zero"
check "a device is nil, never read" "True:0:" "$(kp_plain /dev/zero 100 head)"
check "a link to a device is nil" "True:0:" "$(kp_plain "$KP/to-zero" 100 head)"
# A sparse file of 3 GB, which takes no room on the disk: head and tail read only max bytes, whole refuses it.
mkfile -n 3g "$KP/huge"
check "a huge file's head reads max bytes" "False:16:" "$(kp_plain "$KP/huge" 16 head | tr -d '\000')"
check "  its tail too" "False:16:" "$(kp_plain "$KP/huge" 16 tail | tr -d '\000')"
check "  and whole past max is nil, with nothing read" "True:0:" "$(kp_plain "$KP/huge" 1048576 whole)"
rm -rf "$KP"
