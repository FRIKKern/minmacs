#!/bin/sh
# Does Codex `thread_turns.status` show a live turn? Read-only.
# Part 1 reads the turn table. Part 2 reads the SQL that the installed Codex CLI writes to it.
# Usage: check.sh            uses CODEX_HOME or ~/.codex
set -u
H=${CODEX_HOME:-$HOME/.codex}
DB="$H/thread_history_1.sqlite"
# A WAL database with no -wal and -shm file cannot be opened with mode=ro: SQLite must create
# the -shm file first. That is the case whenever no Codex process holds the file open.
# Then nothing writes it, so immutable=1 is safe. While Codex runs, the -shm exists and mode=ro works.
open_mode() { if [ -e "$DB-shm" ]; then echo "mode=ro"; else echo "immutable=1"; fi; }
echo "== files"
ls -la "$DB"* 2>&1
printf 'header write/read version: '; od -An -tu1 -j18 -N2 "$DB"
echo "mode=ro open: $(sqlite3 "file:$DB?mode=ro" 'select count(*) from thread_turns' 2>&1)"
M=$(open_mode); echo "using $M"
echo "== status counts"
sqlite3 "file:$DB?$M" "select status, count(*), sum(completed_at is null) from thread_turns group by 1;"
echo "== newest turns"
sqlite3 "file:$DB?$M" "select status, datetime(started_at,'unixepoch'), datetime(completed_at,'unixepoch') from thread_turns order by started_at desc limit 3;"
echo "== projection is current when its offset equals the rollout size"
sqlite3 "file:$DB?$M" "select thread_id, next_rollout_byte_offset from thread_history_projection_state;" | while IFS='|' read -r t off; do
  f=$(ls "$H"/sessions/*/*/*/rollout-*"$t".jsonl 2>/dev/null | head -1)
  [ -n "$f" ] && [ "$(stat -f %m "$f")" -gt $(( $(date +%s) - 14*86400 )) ] && echo "$t offset $off size $(stat -f %z "$f")"
done
echo "== SQL in the Codex CLI that names inProgress"
B=$(readlink -f "$HOME/.local/bin/codex" 2>/dev/null || command -v codex)
echo "binary $B"
"$B" --version 2>/dev/null
LC_ALL=C grep -a -c "thread_turns.status = 'inProgress'" "$B"
LC_ALL=C grep -a -c "AND status = 'inProgress'" "$B"
