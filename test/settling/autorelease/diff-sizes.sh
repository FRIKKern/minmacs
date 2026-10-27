#!/bin/sh
# Measures the git diff that WorkForest's SquashMerged() reads into memory for each worktree,
# Trees.m:155-165. Read-only: git runs with GIT_OPTIONAL_LOCKS=0 and only reads.
# It uses WorkForest's own facts.json for the list of worktrees and their default branch.
set -u
export GIT_OPTIONAL_LOCKS=0 LC_ALL=C
FACTS="$HOME/Library/Application Support/WorkForest/facts.json"
python3 -I -c '
import json,sys
for p,f in json.load(open(sys.argv[1])).items():
    if f.get("defaultBranch") and f.get("notInDefault",0) > 0 and not f.get("merged"): print(p+"\t"+f["defaultBranch"])
' "$FACTS" | while IFS="$(printf '\t')" read -r dir def; do
  [ -d "$dir" ] || continue
  base=$(git -C "$dir" merge-base "$def" HEAD 2>/dev/null) || continue
  bytes=$(git -C "$dir" --no-pager diff --no-color --no-ext-diff "$base" HEAD 2>/dev/null | wc -c | tr -d ' ')
  printf '%12s  %s\n' "$bytes" "$dir"
done | sort -rn
