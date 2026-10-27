#!/bin/sh
# Owner step for the Codex question. Read-only.
# Start this in one terminal, then start any Codex turn in another, for example
#   codex exec "count to 20 slowly, one number per line"
# It prints the newest turn's status once a second for 120 seconds.
# The question is settled when a line shows inProgress while the turn runs.
set -u
H=${CODEX_HOME:-$HOME/.codex}
DB="$H/thread_history_1.sqlite"
i=0
while [ $i -lt 120 ]; do
  if [ -e "$DB-shm" ]; then M=mode=ro; else M=immutable=1; fi
  printf '%s %s ' "$(date +%T)" "$M"
  sqlite3 "file:$DB?$M" "select status, rollout_end_ordinal is null, started_at, completed_at from thread_turns order by started_at desc limit 1;" 2>&1
  sleep 1; i=$((i+1))
done
