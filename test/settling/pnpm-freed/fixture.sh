#!/bin/sh
# Checks freed against the truth on a fixture: a fake pnpm store, and a node_modules made of
# clones of store files plus files of its own. Deleting node_modules must free what freed said.
# Everything lives in one temp folder. Usage: fixture.sh <freed binary> <empty folder>
set -eu
FREED=$1; F=$2; BULK=${3:-}
mkdir -p "$F/store" "$F/wt/node_modules/.pnpm" "$F/wt/node_modules/own"
# 200 store files of 256 KB. node_modules clones 150 of them, as pnpm's clone import does.
i=0; while [ $i -lt 200 ]; do head -c 262144 /dev/urandom >"$F/store/f$i"; i=$((i+1)); done
i=0; while [ $i -lt 150 ]; do cp -c "$F/store/f$i" "$F/wt/node_modules/.pnpm/f$i"; i=$((i+1)); done
# 40 MB of build output that only node_modules holds, and one clone changed in one block.
i=0; while [ $i -lt 40 ]; do head -c 1048576 /dev/urandom >"$F/wt/node_modules/own/b$i"; i=$((i+1)); done
printf 'x%.0s' $(seq 1 4096) | dd of="$F/wt/node_modules/.pnpm/f0" bs=4096 seek=10 conv=notrunc 2>/dev/null
sync
"$FREED" "$F/wt/node_modules" -- "$F/store"
[ -n "$BULK" ] && "$BULK" "$F/wt/node_modules" -- "$F/store"
before=$(df -k "$F" | awk 'NR==2 {print $4}')
rm -rf "$F/wt/node_modules"; sync
after=$(df -k "$F" | awk 'NR==2 {print $4}')
echo "statfs delta on delete: $(( (after - before) / 1024 )) MB ($((after - before)) KB)"
