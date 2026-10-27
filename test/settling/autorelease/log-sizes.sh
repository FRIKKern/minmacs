#!/bin/sh
# Measures the `git log -p -n 400` that WorkForest's DefaultPatchIds() reads into memory per repo,
# Trees.m:104-129, and pipes back into git patch-id. It runs again whenever the default branch moves.
# Read-only: GIT_OPTIONAL_LOCKS=0, and git only reads.
set -u
export GIT_OPTIONAL_LOCKS=0 LC_ALL=C
python3 -I -c '
import json,sys,os
seen=set()
for p,f in json.load(open(sys.argv[1])).items():
    d=f.get("defaultBranch")
    if not d or not os.path.isdir(p): continue
    print(p+"\t"+d)
' "$HOME/Library/Application Support/WorkForest/facts.json" | while IFS="$(printf '\t')" read -r dir def; do
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
  echo "$common	$dir	$def"
done | sort -u -k1,1 | while IFS="$(printf '\t')" read -r common dir def; do
  bytes=$(git -C "$dir" --no-pager log -p --no-merges --no-color --no-ext-diff -n 400 --format='commit %H' "$def" 2>/dev/null | wc -c | tr -d ' ')
  tip=$(git -C "$dir" log -1 --format=%cr "$def" 2>/dev/null)
  printf '%12s  %-40s tip %s\n' "$bytes" "$(dirname "$common")" "$tip"
done | sort -rn
