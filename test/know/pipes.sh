# Issue #96: a session file, a project file or another tool's file that is a named pipe, a socket or a device.
# Sourced by test/know.sh after its sessions checks, with $K, $KT, start, stop, check and json set.
# No writer ever opens these pipes, unless a check starts one, so an open of one for reading waits for ever. Every read
# runs under `knowtool within 2`: one that waits prints "stuck", which fails its check, and the tool ends with it, so
# the run never waits on the stuck thread.

KP="$K/pipes96"; mkdir -p "$KP"
# The session read with one pipe in place, then the pipe gone. Prints stuck, or the id the fixture transcript still gives.
kp_sessions() { # pipe path
  rm -f "$1"; mkfifo "$1"
  kp_out=$("$KT" within 2 sessions --id sess-transcript)
  rm -f "$1"
  [ "$kp_out" = stuck ] && echo stuck || printf '%s' "$kp_out" | json "j['withID']['id']" 2>/dev/null
}
check "a Claude Code transcript that is a named pipe is no session, and the read returns" sess-transcript \
  "$(kp_sessions "$CLAUDE_CONFIG_DIR/projects/fixture/pipe96-$$.jsonl")"
check "a Claude Code status file that is a named pipe is skipped" sess-transcript \
  "$(kp_sessions "$CLAUDE_CONFIG_DIR/sessions/96096.json")"
check "a pi session file that is a named pipe is skipped" sess-transcript \
  "$(kp_sessions "$K/pi/sessions/--fixture--/2026-10-27T10-00-00-000Z_pipe96-$$.jsonl")"
mkdir -p "$KP/codex-db"
check "a Codex database that is a named pipe gives no threads" sess-transcript \
  "$(CODEX_HOME="$KP/codex-db" kp_sessions "$KP/codex-db/state_5.sqlite")"
python3 test/know/codexdb.py "$KP/codex-shm" "$K/proj" completed
check "a Codex database whose -shm file is a named pipe gives no threads" sess-transcript \
  "$(CODEX_HOME="$KP/codex-shm" kp_sessions "$KP/codex-shm/state_5.sqlite-shm")"

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
