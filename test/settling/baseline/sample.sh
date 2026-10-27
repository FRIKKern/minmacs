#!/bin/sh
# Samples the idle cost of the running LocoHost, WorkForest and Insomnia apps. Read-only.
# Usage: test/settling/baseline/sample.sh [seconds] [outdir]
# It runs ps every 10 seconds and vmmap --summary at the start, the middle and the end.
# It never signals a process. It only reads them.
set -u
SECS=${1:-660}
OUT=${2:-$(cd "$(dirname "$0")" && pwd -P)/raw}
mkdir -p "$OUT"
APPS="LocoHost WorkForest Insomnia MinMacs Noo-Noo"

# One line per app that runs now: name and pid. The pid is fixed for the whole run.
: >"$OUT/pids.txt"
for a in $APPS; do
  p=$(pgrep -x "$a" | head -1)
  [ -n "$p" ] && echo "$a $p" >>"$OUT/pids.txt"
done
pids=$(awk '{print $2}' "$OUT/pids.txt" | paste -sd, -)
[ -n "$pids" ] || { echo "no app runs"; exit 1; }

{ date -u +%Y-%m-%dT%H:%M:%SZ; sw_vers; sysctl -n hw.model hw.ncpu hw.memsize; } >"$OUT/host.txt"

vm() {
  while read -r name pid; do
    echo "=== $name $pid $(date -u +%H:%M:%S)"
    vmmap --summary "$pid" 2>&1
  done <"$OUT/pids.txt"
}
vm >"$OUT/vmmap-start.txt"

# ps columns: time of sample, pid, rss in KB, cumulative CPU time, %cpu as ps reports it, threads are not in ps.
echo "utc pid rss_kb cputime pcpu command" >"$OUT/ps.txt"
start=$(date +%s); half=$((start + SECS / 2)); midone=0
while :; do
  now=$(date +%s)
  [ "$now" -ge $((start + SECS)) ] && break
  t=$(date -u +%H:%M:%S)
  ps -o pid=,rss=,time=,%cpu=,comm= -p "$pids" | sed "s|^|$t |" >>"$OUT/ps.txt"
  if [ "$midone" = 0 ] && [ "$now" -ge "$half" ]; then vm >"$OUT/vmmap-middle.txt"; midone=1; fi
  sleep 10
done
t=$(date -u +%H:%M:%S)
ps -o pid=,rss=,time=,%cpu=,comm= -p "$pids" | sed "s|^|$t |" >>"$OUT/ps.txt"
vm >"$OUT/vmmap-end.txt"
date -u +%Y-%m-%dT%H:%M:%SZ >>"$OUT/host.txt"
echo done
