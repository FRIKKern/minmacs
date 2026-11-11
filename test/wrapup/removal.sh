# The removal choice in Wrap Up, issue #62. Sourced by test/wrapup.sh, inside its fixtures: the worktree $F, its
# node_modules, its ignored .env and its untracked .env.local all live under $wu, which is this section's
# MINMACS_HOME, so the Trash is $wu/Trash and MMRemovalApply refuses any path outside $wu.
#   wu_rec <rid>          the Wrap Up record and its parts by step name, as JSON, from the section's own log
#   wu_removal_smart      a run under Smart and its restore: node_modules is deleted, the rest comes back
#   wu_removal_delete     a run under Delete: nothing is kept but the record, and restore says so
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

wu_removal_smart() {
  echo "-- the removal choice: a run under Smart, the default"
  "$T" verb removal smart >/dev/null
  wu_fresh
  J=$("$T" verb work wrap-up "$F" --json); r=$?
  check "wrapup smart: it exits 0 and the record is done" "0 done" "$r $(echo "$J" | json "j['state']")"
  RID3=$(echo "$J" | json "j['rid']")
  U=$(wu_rec "$RID3")
  check "wrapup smart: node_modules was deleted at once, not sent to the Trash" "smart True 0 1" "$(wu_part "$U" caches)"
  check "wrapup smart: its record names the path and why" "yes its tool rebuilds it" \
    "$(echo "$U" | json "('yes' if j['parts']['caches']['payload']['deleted'][0]['path'].endswith('/feat/node_modules') else 'no') + ' ' + j['parts']['caches']['payload']['removal']['why']")"
  check "wrapup smart: the untracked .env.local went to the Trash, since git does not hold it" "smart False 1 0 git does not hold untracked files" \
    "$(wu_part "$U" config) $(echo "$U" | json "j['parts']['config']['payload']['removal']['why']")"
  check "wrapup smart: the merged worktree counts as deleted, since git can give it back" "smart True yes" \
    "$(echo "$U" | json "(lambda r: '%s %s %s' % (r['choice'], r['deleted'], 'yes' if r['why'].startswith('its branch is merged and every commit is on a remote') else r['why']))(j['parts']['worktree']['payload']['removal'])")"
  check "wrapup smart: its ignored .env was still saved to the recovery folder" "False True" \
    "$(echo "$U" | json "str(j['parts']['worktree']['payload']['removal']['ignored']['deleted']) + ' ' + str('.env' in j['parts']['worktree']['payload']['recovery']['saved'])")"
  check "wrapup smart: the worktree and node_modules are gone" "no no" "$(wu_has "$F") $(wu_has "$F/node_modules")"
  L=$("$T" verb restore --list --json --limit 40)
  check "wrapup smart: the restore list says the caches part was deleted and cannot restore" "True False" \
    "$(echo "$L" | json "(lambda r: '%s %s' % (r['deleted'], r['canRestore']))([r for r in j['records'] if r['rid'] == '$(echo "$U" | json "j['parts']['caches']['rid']")'][0])")"
  check "wrapup smart: the plain list shows it as deleted" 1 "$("$T" verb restore --list --limit 40 | grep -c "^$(echo "$U" | json "j['parts']['caches']['rid']") .* deleted ")"
  J=$("$T" verb restore "$RID3" --json); r=$?
  check "wrapup smart: restore exits 0 and counts the one deleted part" "0 True 1" \
    "$r $(echo "$J" | json "str(j['restored'][0]['restored']) + ' ' + str(j['restored'][0].get('deletedParts', 0))")"
  check "wrapup smart: the worktree is back at its commit, with .env and .env.local" "$WU_HEAD DB_PASSWORD=wu-fixture API_URL=http://127.0.0.1" \
    "$(G -C "$F" rev-parse HEAD 2>/dev/null) $(cat "$F/.env" 2>/dev/null) $(cat "$F/.env.local" 2>/dev/null)"
  check "wrapup smart: node_modules did not come back" no "$(wu_has "$F/node_modules")"
  check "wrapup smart: the caches part stays done, and the config and worktree parts say restored" "done restored restored" \
    "$(wu_rec "$RID3" | json "' '.join(j['parts'][s]['state'] for s in ('caches', 'config', 'worktree'))")"
  # The restored server and helper are this section's, and its cleanup stops them by pid file and by port.
  wu_wait '[ "$(wu_listening "$P")" = yes ]'
  wu_wait "[ -s '$wu/pids/helper-1' ] && kill -0 \"\$(cat '$wu/pids/helper-1')\" 2>/dev/null"
  wu_fresh
}

wu_removal_delete() {
  echo "-- the removal choice: a run under Delete"
  "$T" verb removal delete >/dev/null
  wu_fresh
  J=$("$T" verb work wrap-up "$F" --dry-run --json)
  check "wrapup delete: the plan's titles say Delete" "Delete node_modules|Delete untracked config files" \
    "$(echo "$J" | json "'|'.join(p['title'] for p in j['parts'] if p['step'] in ('caches', 'config'))")"
  check "wrapup delete: the worktree part's dry run says it cannot be brought back" yes \
    "$(echo "$J" | json "'yes' if 'leave its ignored files unsaved' in j['parts'][-1]['dryRun'] and 'You chose Delete, so it cannot be brought back.' in j['parts'][-1]['dryRun'] else j['parts'][-1]['dryRun']")"
  wu_t0=$(ls -A "$wu/Trash" 2>/dev/null | wc -l | tr -d ' ')
  J=$("$T" verb work wrap-up "$F" --json); r=$?
  check "wrapup delete: it exits 0 and the record is done" "0 done" "$r $(echo "$J" | json "j['state']")"
  RID4=$(echo "$J" | json "j['rid']")
  U=$(wu_rec "$RID4")
  check "wrapup delete: node_modules was deleted" "delete True 0 1" "$(wu_part "$U" caches)"
  check "wrapup delete: .env.local was deleted, not sent to the Trash" "delete True 0 1 yes" \
    "$(wu_part "$U" config) $(echo "$U" | json "'yes' if j['parts']['config']['payload']['deleted'][0]['path'].endswith('/feat/.env.local') else 'no'")"
  check "wrapup delete: nothing new is in the Trash" "$wu_t0" "$(ls -A "$wu/Trash" 2>/dev/null | wc -l | tr -d ' ')"
  check "wrapup delete: the worktree went with no recovery copy, and the record names the ignored file that went with it" "delete True True no .env" \
    "$(echo "$U" | json "(lambda p: '%s %s %s %s %s' % (p['removal']['choice'], p['removal']['deleted'], p['removal']['ignored']['deleted'], 'yes' if 'recovery' in p else 'no', ' '.join(p.get('ignoredDeleted', []))))(j['parts']['worktree']['payload'])")"
  check "wrapup delete: no recovery folder was made for it" no "$([ -e "$wu/workforest/recovery/$(echo "$U" | json "j['parts']['worktree']['rid']")" ] && echo yes || echo no)"
  check "wrapup delete: the worktree is gone, removed by git with no --force" "no no" "$(wu_has "$F") $(G -C "$A" worktree list | grep -q "$F" && echo yes || echo no)"
  check "wrapup delete: git still holds its commit" 0 "$(G -C "$A" cat-file -e "$WU_HEAD^{commit}" 2>/dev/null; echo $?)"
  L=$("$T" verb restore --list --json --limit 40)
  check "wrapup delete: no removal part of the run can restore" "True False|True False|True False" \
    "$(echo "$L" | json "'|'.join('%s %s' % (r['deleted'], r['canRestore']) for r in j['records'] if r['rid'] in [$(echo "$U" | json "', '.join(repr(j['parts'][s]['rid']) for s in ('caches', 'config', 'worktree'))")])")"
  "$T" verb restore "$(echo "$U" | json "j['parts']['worktree']['rid']")" >"$wu/restore-deleted.txt" 2>&1
  check "wrapup delete: restore of the worktree part says it was deleted" "1 yes" \
    "$? $(grep -q 'it was deleted and cannot be brought back' "$wu/restore-deleted.txt" && echo yes || echo no)"
  check "wrapup delete: and the worktree stays gone" no "$(wu_has "$F")"
  "$T" verb removal smart >/dev/null
}
