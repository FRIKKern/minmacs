#!/bin/sh
# Waits for WorkForest's next scan and takes one vmmap summary while its RSS is above a limit.
# Read-only: ps and vmmap only. It never signals WorkForest.
# Usage: catch-spike.sh <pid> [limit MB] [seconds] [outfile]
set -u
PID=$1; LIMIT=${2:-1000}; SECS=${3:-900}; OUT=${4:-spike-vmmap.txt}
end=$(( $(date +%s) + SECS ))
: >"$OUT.rss"
while [ "$(date +%s)" -lt "$end" ]; do
  rss=$(ps -o rss= -p "$PID" | tr -d ' ')
  [ -n "$rss" ] || { echo "pid $PID is gone"; exit 1; }
  echo "$(date -u +%T) $rss" >>"$OUT.rss"
  if [ "$rss" -gt $((LIMIT * 1024)) ]; then
    { date -u +%FT%TZ; echo "rss_kb $rss"; vmmap --summary "$PID"; } >"$OUT" 2>&1
    echo "caught at rss $rss KB"; exit 0
  fi
  sleep 1
done
echo "no spike in $SECS s"
