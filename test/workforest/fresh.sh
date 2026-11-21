# Issue #125: the keep check right before a removal reads git now, under a root that is a link. Sourced by
# test/workforest.sh once $MM is built. Fixtures only, all inside $wf/fresh: two copies of one repo, each under a root
# that is a link, one link longer than its target, as ~/Documents/github leads to /Volumes/SATECHI/github, and one
# shorter. Each holds twelve merged, clean worktrees, one per run: the app's source or the cold CLI's, the finding by
# the resolved path or by the path through the link, and one change after the plan. The index keeps a linked worktree
# under both names, and the fresh read refreshed only the name the finding gave, while WorkForest's keep check took
# the first name of the folder: a longer path first. So with the long link and the resolved finding, or the short link
# and the finding through it, the check read the plan's facts and let a worktree go that git status now calls dirty.
# Recent work keeps for a day, which would hide that, so these runs set that day to 0 hours. Every run is a read: the
# tool asks MMMustKeep and removes nothing. It starts no process but git and sh.
echo "-- the keep check before a removal reads git now, under a root that is a link"
fk=$(mkdir -p "$wf/fresh" && cd "$wf/fresh" && pwd -P)
mkdir -p "$fk/claude" "$fk/codex"
fk_kinds="app cli"; fk_forms="real link"; fk_changes="dirty untracked commit"
fk_tree() { # shape code root: the repo in code, every run's worktree merged into main, and root a link to code
  mkdir -p "$2" "$(dirname "$3")"; ln -s "$2" "$3"
  G init -q "$2/shop"; ( cd "$2/shop" && echo one >a.txt && G add -A && G commit -qm first )
  for k in $fk_kinds; do for m in $fk_forms; do for c in $fk_changes; do
    G -C "$2/shop" worktree add -q -b "$k-$m-$c" "$2/shop.wt/$k-$m-$c" main 2>/dev/null
    ( cd "$2/shop.wt/$k-$m-$c" && echo "$c" >"$k-$m-$c.txt" && G add -A && G commit -qm "$k $m $c" )
    G -C "$2/shop" merge -q --ff-only "$k-$m-$c"
  done; done; done
}
fk_tree long "$fk/long/code" "$fk/long/my/documents/github"
fk_tree short "$fk/short/volumes/drive/github" "$fk/short/g"
fk_change() { # change worktree
  case "$1" in
    dirty) printf 'echo more >>"%s/a.txt"' "$2" ;;
    untracked) printf 'echo new >"%s/new.txt"' "$2" ;;
    commit) printf 'cd "%s" && echo after >after.txt && git -c user.name=Fixture -c user.email=fixture@example.com -c commit.gpgsign=false add after.txt && git -c user.name=Fixture -c user.email=fixture@example.com -c commit.gpgsign=false commit -qm "after the plan"' "$2" ;;
  esac
}
fk_want() { case "$1" in dirty) echo "go, then 1 change not committed" ;; untracked) echo "go, then 1 untracked file not committed" ;;
  commit) echo "go, then cannot verify: its HEAD moved since it was listed" ;; esac; }
for fk_shape in long short; do
  case $fk_shape in long) fk_code="$fk/long/code"; fk_root="$fk/long/my/documents/github" ;;
                    short) fk_code="$fk/short/volumes/drive/github"; fk_root="$fk/short/g" ;; esac
  for k in $fk_kinds; do for m in $fk_forms; do for c in $fk_changes; do
    fk_wt="$fk_code/shop.wt/$k-$m-$c"
    if [ "$m" = real ]; then fk_named="$fk_wt"; else fk_named="$fk_root/shop.wt/$k-$m-$c"; fi
    mkdir -p "$fk/home-$fk_shape-$k-$m-$c"
    fk_out=$(MINMACS_HOME="$fk/home-$fk_shape-$k-$m-$c" MINMACS_ROOTS="$fk_root" WORKFOREST_RECENT_HOURS=0 \
      CLAUDE_CONFIG_DIR="$fk/claude" CODEX_HOME="$fk/codex" "$MM" _freshkeep "$k" "$fk_wt" "$fk_named" "$(fk_change "$c" "$fk_wt")" 2>&1)
    fk_got=$(printf '%s' "$fk_out" | json "j['plan'] + ', then ' + j['fresh']" 2>/dev/null || printf '%s' "$fk_out" | tail -1)
    check "fresh keep: link $fk_shape, $k, finding $m, $c after the plan" "$(fk_want "$c")" "$fk_got"
    # Both names of the folder, each once, hand over the one fresh answer.
    check "  and both names hand over the fresh read, each once" "2 names, 1 answer" "$(printf '%s' "$fk_out" |
      json "(lambda e: '%d names, %d answer' % (len(e), len(set(x.split(' ', 1)[1] for x in e))))(j['entries'].split(' | '))" 2>/dev/null)"
  done; done; done
done
