# Where a removed worktree goes, issue #62 and D2. Sourced by test/workforest.sh, inside its fixtures: the repo $A and
# the worktrees under $W live in $wf, which is inside $MINMACS_HOME, and every removal names one by its path.
# git removes the folder, with no --force, and git is the way back for what it holds. The files git ignores are always
# saved first, and every record can restore. An old smart or delete in the pref, as an older MinMacs wrote it, changes
# nothing of that.
#   rcm   merged and pushed, with an ignored .env and an ignored node_modules
#   rcu   squash-merged on main, its one commit on no remote
#   rcs   merged and pushed, with one stash on its branch
echo "== removal: every worktree keeps a way back"
wf_removal() { "$MM" removal "$@" 2>/dev/null; }
wf_age() { find "$W/$1" -exec touch -h -t 202501011200 {} +; }
# One expression on the newest remove record r, from Core's restore list.
wf_last() { "$MM" restore --list --json --limit 6 | json "(lambda r: $1)([r for r in j['records'] if r['kind'] == 'remove'][0])"; }
wf_what="'%s %s %s %s' % (r['removal']['choice'], r['removal']['deleted'], r['removal']['ignored']['deleted'], r['canRestore'])"
check "removal: the verb says trash, and sets nothing" "trash 2" "$(wf_removal --json | json "j['removal']") $(wf_removal delete >/dev/null; echo $?)"
wt rcm; commit rcm 1 "rcm work"; G -C "$W/rcm" push -q -u origin rcm 2>/dev/null
G -C "$A" merge -q --ff-only rcm 2>/dev/null; G -C "$A" push -q origin main 2>/dev/null
printf 'RC_SECRET=keep-me\n' > "$W/rcm/.env"; mkdir -p "$W/rcm/node_modules/pkg"; echo x > "$W/rcm/node_modules/pkg/index.js"
wt rcu; commit rcu 1 "rcu only here"
( cd "$A" && G merge -q --squash rcu >/dev/null 2>&1 && G commit -qm "squashed rcu" && G push -q origin main 2>/dev/null )
wt rcs; commit rcs 1 "rcs work"; G -C "$W/rcs" push -q -u origin rcs 2>/dev/null
G -C "$A" merge -q --ff-only rcs 2>/dev/null; G -C "$A" push -q origin main 2>/dev/null
( cd "$W/rcs" && echo stashed >> rcs-1.txt && G stash -q )
RC_HEAD=$(G -C "$W/rcm" rev-parse HEAD)
for n in rcm rcu rcs; do wf_age "$n"; done
L=$("$WF" list --json)
check "the fixtures: merged and pushed, merged with a commit on no remote, merged with a stash" "True 0 0|True 1 0|True 0 1" \
  "$(get rcm "['merged'] is not None") $(get rcm "['unpushed']") $(get rcm "['stashes']")|$(get rcu "['merged'] is not None") $(get rcu "['unpushed']") $(get rcu "['stashes']")|$(get rcs "['merged'] is not None") $(get rcs "['unpushed']") $(get rcs "['stashes']")"

echo "-- an old smart in the pref"
old_removal "$MINMACS_HOME" smart
check "old smart: the dry run saves the ignored files and says Restore recreates it" yes \
  "$("$WF" remove "$W/rcm" --dry-run 2>/dev/null | grep -q 'save its ignored files except caches.*Restore recreates it at' && echo yes || echo no)"
"$WF" remove "$W/rcm" --yes >/dev/null 2>&1;                               check "old smart: a merged, pushed worktree is removed" "0 no" "$? $(wf_has "$W/rcm")"
check "old smart: it is not deleted, its ignored files are not, and it can restore" "trash False False True" "$(wf_last "$wf_what")"
check "old smart: the record says git can give it back" "git can give it back: its branch is merged and every commit is on a remote" "$(wf_last "r['removal']['why']")"
check "old smart: its ignored .env went to the recovery folder, since git does not hold it" "['.env'] git does not hold the files it ignores, so they go to the recovery folder" \
  "$("$WF" removed --json | json "j[0]['saved']") $(wf_last "r['removal']['ignored']['why']")"
"$WF" restore "$W/rcm" >/dev/null 2>&1;                                    check "old smart: restore brings it back at its commit, with .env" "0 $RC_HEAD RC_SECRET=keep-me" \
  "$? $(G -C "$W/rcm" rev-parse HEAD 2>/dev/null) $(cat "$W/rcm/.env" 2>/dev/null)"
"$WF" remove "$W/rcu" --yes >/dev/null 2>&1;                               check "old smart: a merged worktree with a commit on no remote is removed" "0 no" "$? $(wf_has "$W/rcu")"
check "old smart: it is not deleted, and says the commit is on no remote" "trash False True a way back is kept, since 1 commit is on no remote" "$(wf_last "'%s %s %s %s' % (r['removal']['choice'], r['removal']['deleted'], r['canRestore'], r['removal']['why'])")"
check "old smart: a git bundle was taken for it" True "$("$WF" removed --json | json "j[0]['bundle']")"
"$WF" restore "$W/rcu" >/dev/null 2>&1;                                    check "old smart: and restore brings its commit back" "0 rcu only here" "$? $(G -C "$W/rcu" log -1 --format=%s 2>/dev/null)"
"$WF" remove "$W/rcs" --yes >/dev/null 2>&1;                               check "old smart: a merged worktree with a stash is removed" "0 no" "$? $(wf_has "$W/rcs")"
check "old smart: it is not deleted, and says it has a stash" "trash False True a way back is kept, since it has 1 stash" "$(wf_last "'%s %s %s %s' % (r['removal']['choice'], r['removal']['deleted'], r['canRestore'], r['removal']['why'])")"
check "old smart: the stash is still in the repo" 1 "$(G -C "$A" stash list 2>/dev/null | grep -c 'rcs')"
"$WF" restore "$W/rcs" >/dev/null 2>&1;                                    check "old smart: and restore brings it back" "0 yes" "$? $(wf_has "$W/rcs")"
"$WF" remove "$W/untracked" --yes >/dev/null 2>&1;                         check "old smart: a worktree with an untracked file is refused and stays" "1 yes new" "$? $(wf_has "$W/untracked") $(cat "$W/untracked/new.txt" 2>/dev/null)"

# A mode's own removal keeps the same way back.
wf_age rcm
RV_TEST_GO=/rcm "$WF" review --model haiku --mode eager --fresh >/dev/null 2>&1
"$WF" auto --mode eager --path "$W/rcm" >/dev/null 2>&1
check "old smart: a mode's removal of a merged, pushed worktree keeps a way back" "no eager trash False False True" \
  "$(wf_has "$W/rcm") $(wf_last "r['by']") $(wf_last "$wf_what")"
"$WF" restore "$W/rcm" >/dev/null 2>&1;                                    check "old smart: restore brings it back with .env" "0 RC_SECRET=keep-me" "$? $(cat "$W/rcm/.env" 2>/dev/null)"

echo "-- an old delete in the pref"
old_removal "$MINMACS_HOME" delete
for n in rcm rcu; do wf_age "$n"; done
check "old delete: the dry run still saves the ignored files and says Restore recreates it" yes \
  "$("$WF" remove "$W/rcm" --dry-run 2>/dev/null | grep -q 'save its ignored files except caches.*Restore recreates it at' && echo yes || echo no)"
"$WF" remove "$W/untracked" --yes >/dev/null 2>&1;                         check "old delete: a worktree with an untracked file is still refused and stays" "1 yes new" "$? $(wf_has "$W/untracked") $(cat "$W/untracked/new.txt" 2>/dev/null)"
"$WF" remove "$W/dirty" --yes >/dev/null 2>&1;                             check "old delete: a worktree with uncommitted changes is still refused and stays" "1 yes" "$? $(wf_has "$W/dirty")"
wf_recovery_before=$(ls -A "$MINMACS_HOME/workforest/recovery" 2>/dev/null | wc -l | tr -d ' ')
"$WF" remove "$W/rcm" --yes >"$wf/rc-delete.txt" 2>&1;                     check "old delete: a merged, pushed worktree is removed" "0 no" "$? $(wf_has "$W/rcm")"
check "old delete: the CLI never says it cannot be brought back" no "$(grep -q 'cannot be brought back' "$wf/rc-delete.txt" && echo yes || echo no)"
check "old delete: the record is not deleted, ignored files neither, and can restore" "trash False False True" "$(wf_last "$wf_what")"
check "old delete: a recovery copy was made, and the removed list says it can restore" "$((wf_recovery_before + 1)) ['.env'] True False" \
  "$(ls -A "$MINMACS_HOME/workforest/recovery" 2>/dev/null | wc -l | tr -d ' ') $("$WF" removed --json | json "'%s %s %s' % (j[0]['saved'], j[0]['canRestore'], j[0]['deleted'])")"
"$WF" restore "$W/rcm" >/dev/null 2>&1;                                    check "old delete: restore brings it back at its commit, with .env" "0 $RC_HEAD RC_SECRET=keep-me" \
  "$? $(G -C "$W/rcm" rev-parse HEAD 2>/dev/null) $(cat "$W/rcm/.env" 2>/dev/null)"
"$WF" remove "$W/rcu" --yes >/dev/null 2>&1;                               check "old delete: a worktree with a commit on no remote is removed" "0 no" "$? $(wf_has "$W/rcu")"
RC_BUNDLE=$("$MM" restore --list --json --limit 6 | python3 -c "
import json, sqlite3, sys
rid = [r for r in json.load(sys.stdin)['records'] if r['kind'] == 'remove'][0]['rid']
c = sqlite3.connect(sys.argv[1])
b = json.loads(c.execute(\"select body from rows where tbl='undo' and rid=? order by rowid desc limit 1\", (rid,)).fetchone()[0])
print(b['payload'].get('bundle', {}).get('path', ''))" "$MINMACS_HOME/minmacs.sqlite")
check "old delete: the git bundle for its commit is written and verifies" "yes 0" \
  "$([ -s "$RC_BUNDLE" ] && echo yes || echo no) $(G -C "$A" bundle verify "$RC_BUNDLE" >/dev/null 2>&1; echo $?)"
"$WF" restore "$W/rcu" >/dev/null 2>&1;                                    check "old delete: and restore brings its commit back" "0 rcu only here" "$? $(G -C "$W/rcu" log -1 --format=%s 2>/dev/null)"
