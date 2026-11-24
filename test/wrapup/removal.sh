# Where Wrap Up's removed things go, issue #62 and D2. Sourced by test/wrapup.sh, inside its fixtures: the worktree $F, its
# node_modules, its ignored .env and its untracked .env.local all live under $wu, which is this section's
# MINMACS_HOME, so the Trash is $wu/Trash and MMRemovalApply refuses any path outside $wu.
#   wu_rec <rid>          the Wrap Up record and its parts by step name, as JSON, from the section's own log
#   wu_removal_old <v>    a run with an old smart or delete in the pref: every part keeps a way back, and restore
#                         brings all of it back
#   wu_removal_refused    a run git refuses at its last part: everything the parts moved goes back
wu_rec() {
  python3 - "$wu/minmacs.sqlite" "$1" <<'PY'
import json, sqlite3, sys
c = sqlite3.connect(sys.argv[1])
latest = {}
for (b,) in c.execute("select body from rows where tbl='undo' order by rowid"):
    b = json.loads(b); latest[b['rid']] = b
parent = latest[sys.argv[2]]
steps = {p['part']: p['step'] for p in parent['payload']['parts']}
parts = {steps[b['payload']['part']]: b for b in latest.values() if b.get('parentRid') == sys.argv[2]}
print(json.dumps({'parent': parent, 'parts': parts}))
PY
}
# choice, deleted, trashed count and deleted count of one part.
wu_part() { echo "$1" | json "(lambda p: '%s %s %d %d' % (p['removal']['choice'], p['removal']['deleted'], len(p.get('trashed', [])), len(p.get('deleted', []))))(j['parts']['$2']['payload'])"; }
wu_fresh() {
  mkdir -p "$F/node_modules/pkg" && printf 'module.exports = 1\n' >"$F/node_modules/pkg/index.js"
  for f in "$F" "$F/node_modules" "$F/node_modules/pkg" "$F/node_modules/pkg/index.js" "$F/.env.local"; do touch -h -t 202601010000 "$f" 2>/dev/null; done
}

# D2: an old Smart or Delete in the pref is ignored. The run keeps a way back for every part, and restore brings all
# of it back, node_modules too.
wu_removal_old() {   # the old value
  echo "-- an old $1 in the pref: every part keeps a way back"
  old_removal "$wu" "$1"
  wu_fresh
  J=$("$T" verb work wrap-up "$F" --dry-run --json)
  check "wrapup old $1: the plan's titles say the Trash" "Move node_modules to the Trash|Move untracked config files to the Trash" \
    "$(echo "$J" | json "'|'.join(p['title'] for p in j['parts'] if p['step'] in ('caches', 'config'))")"
  check "wrapup old $1: the worktree part's dry run saves the ignored files and says Restore brings it back" yes \
    "$(echo "$J" | json "'yes' if 'save its ignored files except caches' in j['parts'][-1]['dryRun'] and 'Restore recreates it at' in j['parts'][-1]['dryRun'] else j['parts'][-1]['dryRun']")"
  check "wrapup old $1: no dry run says delete" 0 "$(echo "$J" | json "sum(('would delete' in p['dryRun'] or 'cannot be brought back' in p['dryRun']) for p in j['parts'])")"
  J=$("$T" verb work wrap-up "$F" --json); r=$?
  check "wrapup old $1: it exits 0 and the record is done" "0 done" "$r $(echo "$J" | json "j['state']")"
  RID3=$(echo "$J" | json "j['rid']")
  U=$(wu_rec "$RID3")
  check "wrapup old $1: node_modules went to the Trash, and nothing was deleted" "trash False 1 0" "$(wu_part "$U" caches)"
  check "wrapup old $1: the untracked .env.local went to the Trash" "trash False 1 0" "$(wu_part "$U" config)"
  check "wrapup old $1: the merged worktree is not deleted, since git gives it back" "trash False yes" \
    "$(echo "$U" | json "(lambda r: '%s %s %s' % (r['choice'], r['deleted'], 'yes' if r['why'].startswith('git can give it back: its branch is merged') else r['why']))(j['parts']['worktree']['payload']['removal'])")"
  check "wrapup old $1: its ignored .env was saved to the recovery folder" "False True" \
    "$(echo "$U" | json "str(j['parts']['worktree']['payload']['removal']['ignored']['deleted']) + ' ' + str('.env' in j['parts']['worktree']['payload']['recovery']['saved'])")"
  check "wrapup old $1: nothing was staged, and no part lists a deleted path" "0 0 0" \
    "$(ls -A "$wu/staged" 2>/dev/null | wc -l | tr -d ' ') $(ls -Ad "$W"/.minmacs-staged-* 2>/dev/null | wc -l | tr -d ' ') $(echo "$U" | json "sum(len(j['parts'][s]['payload'].get('deleted', [])) for s in ('caches', 'config', 'worktree'))")"
  check "wrapup old $1: the worktree and node_modules are gone" "no no" "$(wu_has "$F") $(wu_has "$F/node_modules")"
  L=$("$T" verb restore --list --json --limit 40)
  check "wrapup old $1: every removal part can restore, and none says deleted" "False True|False True|False True" \
    "$(echo "$L" | json "'|'.join('%s %s' % (r['deleted'], r['canRestore']) for r in j['records'] if r['rid'] in [$(echo "$U" | json "', '.join(repr(j['parts'][s]['rid']) for s in ('caches', 'config', 'worktree'))")])")"
  J=$("$T" verb restore "$RID3" --json); r=$?
  check "wrapup old $1: restore exits 0 and counts no deleted part" "0 True 0" \
    "$r $(echo "$J" | json "str(j['restored'][0]['restored']) + ' ' + str(j['restored'][0].get('deletedParts', 0))")"
  check "wrapup old $1: the worktree is back at its commit, with .env and .env.local" "$WU_HEAD DB_PASSWORD=wu-fixture API_URL=http://127.0.0.1" \
    "$(G -C "$F" rev-parse HEAD 2>/dev/null) $(cat "$F/.env" 2>/dev/null) $(cat "$F/.env.local" 2>/dev/null)"
  check "wrapup old $1: node_modules came back from the Trash" "module.exports = 1" "$(cat "$F/node_modules/pkg/index.js" 2>/dev/null)"
  check "wrapup old $1: the caches, config and worktree parts say restored" "restored restored restored" \
    "$(wu_rec "$RID3" | json "' '.join(j['parts'][s]['state'] for s in ('caches', 'config', 'worktree'))")"
  # The restored server and helper are this section's, and its cleanup stops them by pid file and by port.
  wu_wait '[ "$(wu_listening "$P")" = yes ]'
  wu_wait "[ -s '$wu/pids/helper-1' ] && kill -0 \"\$(cat '$wu/pids/helper-1')\" 2>/dev/null"
  wu_fresh
}

# A Wrap Up whose last part git refuses, the review's must-fix. The worktree holds a submodule, which
# `git worktree remove` never takes without --force, and nothing before that part can see it. So the caches and
# config parts run first and the worktree part fails. Nothing they moved may stay away: the worktree stays, so its
# .env.local and node_modules come back from the Trash.
wu_refused_fixture() {
  SUBR="$wu/sublib"; SW="$W/subw"
  G init -q "$SUBR" && ( cd "$SUBR" && echo lib >lib.txt && G add -A && G commit -qm lib )
  ( cd "$A" && G -c protocol.file.allow=always submodule add -q "$SUBR" lib >/dev/null 2>&1 && G commit -qm "add lib" && G push -q origin main 2>/dev/null )
  G -C "$A" worktree add -q -b subw "$SW" main 2>/dev/null
  ( cd "$SW" && G -c protocol.file.allow=always submodule update -q --init >/dev/null 2>&1 )
  printf 'SUB_SECRET=1\n' >"$SW/.env"
  wu_session "$SW" subw
}
wu_refused_fresh() {
  printf 'KEEP=me\n' >"$SW/.env.local"
  mkdir -p "$SW/node_modules/pkg" && printf 'module.exports = 2\n' >"$SW/node_modules/pkg/index.js"
  find "$SW" -exec touch -h -t 202601010000 {} + 2>/dev/null
}
wu_removal_refused() {   # an old value of the pref
  echo "-- a Wrap Up git refuses at the last part, with an old $1 in the pref: everything goes back"
  old_removal "$wu" "$1"
  wu_refused_fresh
  J=$("$T" verb work wrap-up "$SW" --dry-run --json)
  check "wrapup refused $1: the plan is ready, with caches, config and worktree parts" "True caches config worktree" \
    "$(echo "$J" | json "str(j['ready']) + ' ' + ' '.join(p['step'] for p in j['parts'])")"
  wu_t0=$(ls -A "$wu/Trash" 2>/dev/null | wc -l | tr -d ' ')
  wu_ino0="$(stat -f %i "$SW/.env.local") $(stat -f %i "$SW/node_modules/pkg/index.js")"
  J=$("$T" verb work wrap-up "$SW" --json); r=$?
  check "wrapup refused $1: git refuses the worktree part, and the run fails there" "1 failed worktree yes" \
    "$r $(echo "$J" | json "j['state'] + ' ' + j['failedPart']['step'] + (' yes' if 'git worktree remove refused' in j['error'] else ' ' + j['error'])")"
  check "wrapup refused $1: the worktree is still there" yes "$(wu_has "$SW/lib/lib.txt")"
  check "wrapup refused $1: its .env.local is still there, as it was" "KEEP=me" "$(cat "$SW/.env.local" 2>/dev/null)"
  check "wrapup refused $1: its node_modules is still there, as it was" "module.exports = 2" "$(cat "$SW/node_modules/pkg/index.js" 2>/dev/null)"
  check "wrapup refused $1: both came back by a rename, the same files and not copies" "$wu_ino0" \
    "$(stat -f %i "$SW/.env.local" 2>/dev/null) $(stat -f %i "$SW/node_modules/pkg/index.js" 2>/dev/null)"
  check "wrapup refused $1: its ignored .env is still there" "SUB_SECRET=1" "$(cat "$SW/.env" 2>/dev/null)"
  check "wrapup refused $1: nothing of it is left in the Trash" "$wu_t0" "$(ls -A "$wu/Trash" 2>/dev/null | wc -l | tr -d ' ')"
  check "wrapup refused $1: the staging folder is gone, and the worktree holds no trace of it" "0 clean" \
    "$(ls -A "$wu/staged" 2>/dev/null | wc -l | tr -d ' ') $([ -z "$(G -C "$SW" status --porcelain --ignore-submodules=none | grep -v '^?? .env.local$')" ] && echo clean || G -C "$SW" status --porcelain)"
  U=$(wu_rec "$(echo "$J" | json "j['rid']")")
  check "wrapup refused $1: no part's record says deleted, and none lists a deleted path" "False False False 0" \
    "$(echo "$U" | json "' '.join(str(j['parts'][s]['payload']['removal']['deleted']) for s in ('caches', 'config', 'worktree')) + ' ' + str(sum(len(j['parts'][s]['payload'].get('deleted', [])) for s in ('caches', 'config', 'worktree')))")"
  check "wrapup refused $1: the worktree part failed, and the parts before it were put back" "failed" "$(echo "$U" | json "j['parts']['worktree']['state']")"
}

# The act forms of `removal --waiting`, issue #67, run as the app runs a verb. The tool leaves one item a done Wrap Up
# could not delete and one whose old path is taken, under $wu.
wu_removal_waiting() {
  echo "-- what still waits in the staging folder, deleted or put back as the app runs it"
  wu_ids=$("$T" leave-waiting "$wu/waiting")
  wu_i1=$(echo "$wu_ids" | sed -n 1p); wu_i2=$(echo "$wu_ids" | sed -n 2p)
  check "wrapup waiting: both are listed" 2 "$("$T" verb removal --waiting --json | json "len([w for w in j['waiting'] if w['id'] in ('$wu_i1', '$wu_i2')])")"
  J=$("$T" verb removal --waiting --delete "$wu_i1" --json); r=$?
  check "wrapup waiting: the delete runs in the app, and the item is gone and not put back" "0 True no no" \
    "$r $(echo "$J" | json "str(j['done'])") $([ -e "$(echo "$J" | json "j['item']['stagedAt']")" ] && echo yes || echo no) $(wu_has "$wu/waiting/wt/cache")"
  J=$("$T" verb removal --waiting --put-back "$wu_i2" --json); r=$?
  check "wrapup waiting: a put-back onto its taken old path is refused, and nothing is written over" "1 False NEWER=1" "$r $(echo "$J" | json "str(j['done'])") $(cat "$wu/waiting/wt/.env")"
  "$T" verb removal --waiting --put-back "$wu_i2" --to "$wu/waiting/aside.env" >"$wu/waiting/put.txt" 2>&1; r=$?
  check "wrapup waiting: a put-back to a path of the person's own moves it there" "0 Put .env back at $wu/waiting/aside.env. B=1 NEWER=1" \
    "$r $(cat "$wu/waiting/put.txt") $(cat "$wu/waiting/aside.env") $(cat "$wu/waiting/wt/.env")"
  wu_odd=$(echo "$wu_ids" | sed -n 3p)
  J=$("$T" verb removal --waiting --close "$wu_odd" --json); r=$?
  check "wrapup waiting: a Wrap Up whose state cannot be read is closed in the app, and is named no more" "0 True 0" \
    "$r $(echo "$J" | json "str(j['done'])") $("$T" verb removal --waiting --json | json "len([u for u in j['unread'] if u['rid'] == '$wu_odd'])")"
  "$T" verb removal --waiting --close "$wu_odd" >"$wu/waiting/close.txt" 2>&1; r=$?
  check "wrapup waiting: a second close is refused, since it has ended" "1 The Wrap Up $wu_odd was not closed: it has ended already" "$r $(cat "$wu/waiting/close.txt")"
  check "wrapup waiting: nothing of them waits any more" 0 "$("$T" verb removal --waiting --json | json "len([w for w in j['waiting'] if w['id'] in ('$wu_i1', '$wu_i2')])")"
}
