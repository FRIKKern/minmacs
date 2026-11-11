# The removal choice on worktrees, issue #62. Sourced by test/workforest.sh, inside its fixtures: the repo $A and the
# worktrees under $W live in $wf, which is inside $MINMACS_HOME, and every removal names one by its path.
# git removes the folder in every choice, with no --force, and git is the way back for what it holds. So the choice
# changes two things here: whether the files git ignores are saved first, and whether the record can restore.
#   rcm   merged and pushed, with an ignored .env and an ignored node_modules
#   rcu   squash-merged on main, its one commit on no remote
#   rcs   merged and pushed, with one stash on its branch
echo "== the removal choice: smart, trash and delete"
wf_removal() { "$MM" removal "$@" 2>/dev/null; }
wf_age() { find "$W/$1" -exec touch -h -t 202501011200 {} +; }
# One expression on the newest remove record r, from Core's restore list.
wf_last() { "$MM" restore --list --json --limit 6 | json "(lambda r: $1)([r for r in j['records'] if r['kind'] == 'remove'][0])"; }
wf_what="'%s %s %s %s' % (r['removal']['choice'], r['removal']['deleted'], r['removal']['ignored']['deleted'], r['canRestore'])"
check "the removal choice starts as smart" smart "$(wf_removal --json | json "j['removal']")"
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

echo "-- smart"
check "smart: the dry run saves the ignored files and says Restore recreates it" yes \
  "$("$WF" remove "$W/rcm" --dry-run 2>/dev/null | grep -q 'save its ignored files except caches.*Restore recreates it at' && echo yes || echo no)"
"$WF" remove "$W/rcm" --yes >/dev/null 2>&1;                               check "smart: a merged, pushed worktree is removed" "0 no" "$? $(wf_has "$W/rcm")"
check "smart: it counts as deleted, its ignored files do not, and git can still restore it" "smart True False True" "$(wf_last "$wf_what")"
check "smart: the record says why" "its branch is merged and every commit is on a remote, so git can give it back" "$(wf_last "r['removal']['why']")"
check "smart: its ignored .env went to the recovery folder, since git does not hold it" "['.env'] git does not hold the files it ignores" \
  "$("$WF" removed --json | json "j[0]['saved']") $(wf_last "r['removal']['ignored']['why']")"
"$WF" restore "$W/rcm" >/dev/null 2>&1;                                    check "smart: restore brings it back at its commit, with .env" "0 $RC_HEAD RC_SECRET=keep-me" \
  "$? $(G -C "$W/rcm" rev-parse HEAD 2>/dev/null) $(cat "$W/rcm/.env" 2>/dev/null)"
"$WF" remove "$W/rcu" --yes >/dev/null 2>&1;                               check "smart: a merged worktree with a commit on no remote is removed" "0 no" "$? $(wf_has "$W/rcu")"
check "smart: it does not count as deleted, and says the commit is on no remote" "smart False True 1 commit is on no remote" "$(wf_last "'%s %s %s %s' % (r['removal']['choice'], r['removal']['deleted'], r['canRestore'], r['removal']['why'])")"
check "smart: a git bundle was taken for it" True "$("$WF" removed --json | json "j[0]['bundle']")"
"$WF" restore "$W/rcu" >/dev/null 2>&1;                                    check "smart: and restore brings its commit back" "0 rcu only here" "$? $(G -C "$W/rcu" log -1 --format=%s 2>/dev/null)"
"$WF" remove "$W/rcs" --yes >/dev/null 2>&1;                               check "smart: a merged worktree with a stash is removed" "0 no" "$? $(wf_has "$W/rcs")"
check "smart: it does not count as deleted, and says it has a stash" "smart False True it has 1 stash" "$(wf_last "'%s %s %s %s' % (r['removal']['choice'], r['removal']['deleted'], r['canRestore'], r['removal']['why'])")"
check "smart: the stash is still in the repo" 1 "$(G -C "$A" stash list 2>/dev/null | grep -c 'rcs')"
"$WF" restore "$W/rcs" >/dev/null 2>&1;                                    check "smart: and restore brings it back" "0 yes" "$? $(wf_has "$W/rcs")"
"$WF" remove "$W/untracked" --yes >/dev/null 2>&1;                         check "smart: a worktree with an untracked file is refused and stays" "1 yes new" "$? $(wf_has "$W/untracked") $(cat "$W/untracked/new.txt" 2>/dev/null)"

echo "-- trash"
wf_removal trash >/dev/null
wf_age rcm
"$WF" remove "$W/rcm" --yes >/dev/null 2>&1;                               check "trash: a merged, pushed worktree is removed" "0 no" "$? $(wf_has "$W/rcm")"
check "trash: it keeps its way back, and .env is saved" "trash False False True ['.env']" "$(wf_last "$wf_what") $("$WF" removed --json | json "j[0]['saved']")"
"$WF" restore "$W/rcm" >/dev/null 2>&1;                                    check "trash: restore brings it back with .env" "0 RC_SECRET=keep-me" "$? $(cat "$W/rcm/.env" 2>/dev/null)"

echo "-- delete"
wf_removal delete >/dev/null
for n in rcm rcu; do wf_age "$n"; done
check "delete: the dry run leaves the ignored files unsaved and says it cannot be brought back" yes \
  "$("$WF" remove "$W/rcm" --dry-run 2>/dev/null | grep -q 'leave its ignored files unsaved.*You chose Delete, so it cannot be brought back.' && echo yes || echo no)"
"$WF" remove "$W/untracked" --yes >/dev/null 2>&1;                         check "delete: a worktree with an untracked file is still refused and stays" "1 yes new" "$? $(wf_has "$W/untracked") $(cat "$W/untracked/new.txt" 2>/dev/null)"
"$WF" remove "$W/dirty" --yes >/dev/null 2>&1;                             check "delete: a worktree with uncommitted changes is still refused and stays" "1 yes" "$? $(wf_has "$W/dirty")"
wf_recovery_before=$(ls -A "$MINMACS_HOME/workforest/recovery" 2>/dev/null | wc -l | tr -d ' ')
"$WF" remove "$W/rcm" --yes >"$wf/rc-delete.txt" 2>&1;                     check "delete: a merged, pushed worktree is removed" "0 no" "$? $(wf_has "$W/rcm")"
check "delete: the CLI says it cannot be brought back" yes "$(grep -q 'You chose Delete, so it cannot be brought back' "$wf/rc-delete.txt" && echo yes || echo no)"
check "delete: the record says deleted, ignored files too, and cannot restore" "delete True True False" "$(wf_last "$wf_what")"
check "delete: no recovery copy was made, and the removed list says so" "$wf_recovery_before [] False True" \
  "$(ls -A "$MINMACS_HOME/workforest/recovery" 2>/dev/null | wc -l | tr -d ' ') $("$WF" removed --json | json "'%s %s %s' % (j[0]['saved'], j[0]['canRestore'], j[0]['deleted'])")"
"$WF" restore "$W/rcm" >"$wf/rc-restore.txt" 2>&1;                         check "delete: restore is refused and says it was deleted" "1 yes no" \
  "$? $(grep -q 'it was deleted and cannot be brought back' "$wf/rc-restore.txt" && echo yes || echo no) $(wf_has "$W/rcm")"
check "delete: git still holds its commit, and removed the folder itself" "0 0" \
  "$(G -C "$A" cat-file -e "$RC_HEAD^{commit}" 2>/dev/null; echo $?) $(G -C "$A" worktree list | grep -c "$W/rcm")"
"$WF" remove "$W/rcu" --yes >/dev/null 2>&1;                               check "delete: a worktree with a commit on no remote is removed" "0 no" "$? $(wf_has "$W/rcu")"
RC_BUNDLE=$("$MM" restore --list --json --limit 6 | python3 -c "
import json, sqlite3, sys
rid = [r for r in json.load(sys.stdin)['records'] if r['kind'] == 'remove'][0]['rid']
c = sqlite3.connect(sys.argv[1])
b = json.loads(c.execute(\"select body from rows where tbl='undo' and rid=? order by rowid desc limit 1\", (rid,)).fetchone()[0])
print(b['payload'].get('bundle', {}).get('path', ''))" "$MINMACS_HOME/minmacs.sqlite")
check "delete: the git bundle for its commit is still written and verifies" "yes 0" \
  "$([ -s "$RC_BUNDLE" ] && echo yes || echo no) $(G -C "$A" bundle verify "$RC_BUNDLE" >/dev/null 2>&1; echo $?)"
"$WF" restore "$W/rcu" >"$wf/rc-restore.txt" 2>&1;                         check "delete: its restore is refused and names the bundle" "1 yes" \
  "$? $(grep -q "cannot be brought back. Its commits on no remote are in the git bundle $RC_BUNDLE" "$wf/rc-restore.txt" && echo yes || echo no)"
wf_removal smart >/dev/null
