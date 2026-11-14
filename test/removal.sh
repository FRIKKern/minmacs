# ===== The removal choice, issue #62: smart, trash or delete =====
# Sourced by test.sh after core. It builds test/removal/removal.m with all of Sources/Core and runs it on fixtures it
# makes inside $MINMACS_HOME/removal<pid>. With MINMACS_HOME set, MMRemovalApply refuses every path outside it, and
# the Trash is $MINMACS_HOME/Trash, so nothing here can reach a real file or the person's Trash.
# The removal paths themselves are checked end to end where their fixtures live: caches and tool rows in
# test/noonoo.sh, worktrees in test/workforest.sh, Wrap Up in test/wrapup.sh and the window in test/window.sh.

rm_dir=$(cd "$MINMACS_HOME" && pwd -P)/removal$$
mkdir -p "$rm_dir/fx" "$rm_dir/inner" "$rm_dir/outer"
rm_cc="clang -fobjc-arc -mmacosx-version-min=14.0 -ISources -Wall -Wextra -Wno-unused-parameter -Wstrict-prototypes -Werror -DMM_TESTS"
# shellcheck disable=SC2046
$rm_cc $(find Sources/Core -name '*.m' | LC_ALL=C sort) test/removal/removal.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -lsqlite3 -o "$rm_dir/removaltest" >"$rm_dir/build.log" 2>&1
rm_r=$?
check "removal: the test binary builds with no warnings" 0 "$rm_r"
[ "$rm_r" = 0 ] || tail -20 "$rm_dir/build.log"

echo "-- one place deletes, and every path asks the one function"
check "removal: Act deletes a file in one place only, one call in MMRemovalApply.m" "1 0" \
  "$(grep -cE 'removeItemAt|unlink\(|rmdir\(|removefile\(' Sources/Core/Act/MMRemovalApply.m) $(grep -nE 'removeItemAt|unlink\(|rmdir\(|removefile\(|emptyTrash|rm -rf' Sources/Core/Act/*.m | grep -vc '^Sources/Core/Act/MMRemovalApply.m:')"
check "removal: that call sits behind the wall: a delete asks WhyNot first, a staged one StagedWhyNot, and the third takes only an empty staging folder" "2 1 1 1 1" \
  "$(grep -c 'Unlink(real' Sources/Core/Act/MMRemovalApply.m) $(grep -c 'WhyNot(path, record, nil, &real)' Sources/Core/Act/MMRemovalApply.m) $(grep -c 'NSString \*real = nil, \*no = StagedWhyNot(x, r, &real);' Sources/Core/Act/MMRemovalApply.m) $(grep -c 'if (!no && !Unlink(real, &e))' Sources/Core/Act/MMRemovalApply.m) $(grep -c 'if (holds.count == 0) Unlink(f, nil);' Sources/Core/Act/MMRemovalApply.m)"
check "removal: the sweep and the person's delete of a waiting item delete only through that same finish" "1 1 1" \
  "$(grep -c '(void)MMRemovalFinishStaged(@\[part\]);' Sources/Core/Act/MMRemovalRecover.m) $(grep -c 'int64_t got = FinishPart(r, stagedAt, &why);' Sources/Core/Act/MMRemovalApply.m) $(grep -c 'return no ?: MMRemovalDeleteStagedItem(' Sources/Core/Act/MMRemovalWaiting.m)"
check "removal: staging is one rename, and nothing in Act copies a person's file to stage it" "1 0" \
  "$(grep -c 'rename(real.fileSystemRepresentation, to.fileSystemRepresentation)' Sources/Core/Act/MMRemovalApply.m) $(grep -cE '[^e]copyItemAt|clonefile|[^e]moveItemAt|copyfile' Sources/Core/Act/MMRemovalApply.m)"
check "removal: a crash is settled at Core's start and before the next Wrap Up, and the start also sweeps what was left staged" "1 1 1" \
  "$(grep -c 'MMRemovalRecoverStaged()' Sources/Core/MMCore.m) $(grep -c '(void)MMRemovalRecoverStaged();' Sources/Core/Act/MMWrapUp.m) $(grep -c 'MMRemovalSweepStaged(&orphans)' Sources/Core/MMCore.m)"
check "removal: staging, finish, recovery, the sweep and the waiting list read a record only through the checked reader" "0 0 0" \
  "$(grep -c 'payload\[@' Sources/Core/Act/MMRemovalApply.m) $(grep -c 'payload\[@' Sources/Core/Act/MMRemovalRecover.m) $(grep -c 'payload\[@' Sources/Core/Act/MMRemovalWaiting.m)"
check "removal: LocoHost's restore and restart read a stop's restart through the checked reader" 0 "$(grep -c 'payload\[@' Sources/Experts/LocoHost/MMLHCLI.m)"
check "removal: the device number is recorded and never compared" 0 "$(grep -c 'st_dev [!=]=' Sources/Core/Act/MMUndo.m)"
check "removal: a Wrap Up's record names the process that owns it" 1 "$(grep -c '@\"owner\": MMRemovalOwner()' Sources/Core/Act/MMWrapUp.m)"
check "removal: put-back and staging ask whether a thing is there with lstat, never a check that follows links" "0 0" \
  "$(grep -c 'fileExistsAtPath' Sources/Core/Act/MMRemovalApply.m) $(sed -n '/^- (NSString \*)moveBack:/,/^}/p' Sources/Core/Act/MMUndo.m | grep -c 'fileExistsAtPath')"
check "removal: MinMacs's own scans never walk into a staging folder beside a worktree" "1 1" \
  "$(grep -c 'hasPrefix:@\".minmacs-staged-\"' Sources/Core/Know/MMClutter.m) $(grep -c 'strncmp(e->fts_name, \".minmacs-staged-\", 16)' Sources/Core/Know/MMTreeDisk.m)"
check "removal: no expert, shell or UI file deletes a person's file itself" 0 \
  "$(grep -nE 'removeItemAt|unlink\(|rmdir\(|removefile\(|trashItemAtURL' Sources/Experts/*/*.m Sources/Shell/MMFixRunner.m Sources/Shell/MMWindow*.m Sources/UI/Window/*.m | grep -c .)"
# The Trash is reached through MMRemovalApply alone. The migration's one move of the old apps asks for the Trash
# in its own confirm and stays there in every choice.
check "removal: only MMRemovalApply and the migration send a thing to the Trash" 0 \
  "$(grep -nE 'MMUndo\.shared trash:|\[u trash:' Sources --include='*.m' -r | grep -vcE '^Sources/Core/Act/MMRemovalApply\.m:|^Sources/Core/Store/MMMigrate\.m:')"
check "removal: the cache, config-file and worktree paths each ask MMRemovalDecide" "yes yes yes yes" \
  "$(for p in 'MMRemovalDecide(MMRemovalClutter' 'MMRemovalDecide(MMRemovalToolCopy'; do grep -q "$p" Sources/Core/Act/MMClutterAct.m && printf 'yes ' || printf 'no '; done
     for p in 'MMRemovalDecide(MMRemovalWorktree' 'MMRemovalDecide(MMRemovalConfigFiles'; do grep -q "$p" Sources/Experts/WorkForest/MMWorkForest.m && printf 'yes ' || printf 'no '; done | sed 's/ $//')"
check "removal: only MMRemoval.m reads the pref" 0 \
  "$(grep -rnE 'core\.removal|MMRemovalKey' Sources --include='*.m' | grep -vc '^Sources/Core/Act/MMRemoval\.m:')"
check "removal: each path lists what the fresh finding named before anything goes, and says deleted only after" "2 4" \
  "$(cat Sources/Core/Act/MMClutterAct.m Sources/Experts/WorkForest/MMWorkForest.m | grep -c 'MMRemovalAsk(record, ') $(cat Sources/Core/Act/MMClutterAct.m Sources/Experts/WorkForest/MMWorkForest.m | grep -c 'MMRemovalDone(record, nil);')"
check "removal: a Wrap Up deletes what its parts staged only after the last part, and puts it back when one fails" "1 1" \
  "$(grep -c 'freed += MMRemovalFinishStaged(ran);' Sources/Core/Act/MMWrapUp.m) $(grep -c 'MMRemovalPutBack(ran);' Sources/Core/Act/MMWrapUp.m)"
check "removal: git worktree remove never gets --force" 0 "$(grep -rnE '"--force"|@"-f"' Sources/Core/Act Sources/Experts/WorkForest | grep -c .)"
check "removal: no string in the code says for good" 0 "$(grep -rnE '@"[^"]*for good' Sources --include='*.m' --include='*.h' | grep -c .)"

if [ "$rm_r" = 0 ]; then
  echo "-- the pref, the decision, the delete and the records"
  "$rm_dir/removaltest" "$rm_dir/fx" "$ROOT/registry/clutter" >"$rm_dir/out.txt" 2>"$rm_dir/err.txt"
  rm_x=$?
  check "removal: the checks ran to the end" "0 END" "$rm_x $(tail -1 "$rm_dir/out.txt")"
  [ "$rm_x" = 0 ] || tail -10 "$rm_dir/err.txt"
  rm_tab=$(printf '\t')
  while IFS="$rm_tab" read -r rm_tag rm_name rm_want rm_got; do
    [ "$rm_tag" = CHECK ] && check "$rm_name" "$rm_want" "$rm_got"
  done <"$rm_dir/out.txt"

  echo "-- a check deletes only inside its own MINMACS_HOME"
  # The binary runs with MINMACS_HOME set to inner, and is asked to delete a fixture beside it and inner itself.
  printf 'outside\n' >"$rm_dir/outer/file.txt"
  rm_out=$(MINMACS_HOME="$rm_dir/inner" "$rm_dir/removaltest" --wall "$rm_dir/outer/file.txt" 2>/dev/null); rm_x=$?
  check "removal: a path outside MINMACS_HOME is refused" \
    "1 refused: MinMacs never deletes it: it is outside MINMACS_HOME, and a check deletes only its own fixtures" "$rm_x $rm_out"
  check "removal: and it is still there" outside "$(cat "$rm_dir/outer/file.txt" 2>/dev/null)"
  check "removal: MINMACS_HOME itself is refused" yes \
    "$(MINMACS_HOME="$rm_dir/inner" "$rm_dir/removaltest" --wall "$rm_dir/inner" 2>/dev/null | grep -q '^refused: MinMacs never deletes it' && [ -d "$rm_dir/inner" ] && echo yes || echo no)"
  check "removal: a link out of MINMACS_HOME is removed as a link, and its target stays" "0 gone outside" \
    "$(ln -s "$rm_dir/outer" "$rm_dir/inner/out-link"; MINMACS_HOME="$rm_dir/inner" "$rm_dir/removaltest" --wall "$rm_dir/inner/out-link" >/dev/null 2>&1; echo $?) $([ -L "$rm_dir/inner/out-link" ] && echo kept || echo gone) $(cat "$rm_dir/outer/file.txt" 2>/dev/null)"
  check "removal: a path that reaches out through a link is refused" "1 outside" \
    "$(ln -s "$rm_dir/outer" "$rm_dir/inner/via"; MINMACS_HOME="$rm_dir/inner" "$rm_dir/removaltest" --wall "$rm_dir/inner/via/file.txt" >/dev/null 2>&1; echo $?) $(cat "$rm_dir/outer/file.txt" 2>/dev/null)"

  echo "-- other spellings of a protected folder, with a fixture home"
  # CFFIXED_USER_HOME makes a folder inside the test home the home folder. On a disk that folds case, HOME names it too.
  mkdir -p "$rm_dir/inner/sub/home/Documents"; printf 'mine\n' >"$rm_dir/inner/sub/home/Documents/notes.txt"
  rm_wall() { CFFIXED_USER_HOME="$rm_dir/inner/sub/home" MINMACS_HOME="$rm_dir/inner" "$rm_dir/removaltest" --wall "$1" 2>/dev/null; }
  check "removal: the fixture home is refused by name" "refused: MinMacs never deletes it: it holds the home folder" "$(rm_wall "$rm_dir/inner/sub/home")"
  rm_wall "$rm_dir/inner/sub/HOME" >/dev/null; rm_x=$?
  check "removal: another spelling of it is refused too, and the notes stay" "1 mine" "$rm_x $(cat "$rm_dir/inner/sub/home/Documents/notes.txt" 2>/dev/null)"
  rm_wall "$rm_dir/inner/SUB" >/dev/null; rm_x=$?
  check "removal: so is another spelling of the folder that holds it" "1 mine" "$rm_x $(cat "$rm_dir/inner/sub/home/Documents/notes.txt" 2>/dev/null)"
  check "removal: a folder at the top of the fixture home is refused" "refused: MinMacs never deletes it: it is a folder at the top of the home folder mine" \
    "$(rm_wall "$rm_dir/inner/sub/home/Documents") $(cat "$rm_dir/inner/sub/home/Documents/notes.txt" 2>/dev/null)"
  mkdir -p "$rm_dir/inner/sub/home/Library/Caches/thing"
  check "removal: two levels down in the fixture home goes when named" "0 gone" \
    "$(rm_wall "$rm_dir/inner/sub/home/Library/Caches" >/dev/null; echo $?) $([ -e "$rm_dir/inner/sub/home/Library/Caches" ] && echo kept || echo gone)"
  check "removal: a path that is not a full path is refused, and nothing in the folder it ran in goes" "1 yes" \
    "$(cd "$rm_dir/inner/sub/home" && rm_wall Documents >/dev/null; echo $?) $([ -f "$rm_dir/inner/sub/home/Documents/notes.txt" ] && echo yes || echo no)"

  echo "-- the CLI"
  rm_home="$rm_dir/cli"; mkdir -p "$rm_home"
  rm_cli() { MINMACS_HOME="$rm_home" "$BIN" "$@" 2>&1; }
  check "removal: the verb shows smart before anything is set, and says nothing is chosen yet" \
    "smart: Deletes what git or its tool can give back. The rest goes to the Trash. Not chosen yet. Until you pick one, what MinMacs removes on its own goes to the Trash." "$(rm_cli removal)"
  check "removal: --json says not chosen" "smart False" "$(rm_cli removal --json | json "j['removal'] + ' ' + str(j['chosen'])")"
  check "removal: setting smart chooses it" "smart True smart: Deletes what git or its tool can give back. The rest goes to the Trash." \
    "$(rm_cli removal smart --json | json "j['removal'] + ' ' + str(j['chosen'])") $(rm_cli removal)"
  check "removal: it sets trash and reads it back" "trash trash" "$(rm_cli removal trash --json | json "j['removal']") $(rm_cli removal --json | json "j['removal']")"
  check "removal: it sets delete" "delete: Deletes everything it removes at once. Nothing can be brought back." "$(rm_cli removal delete)"
  check "removal: a dry run names the choice and changes nothing" "smart delete" "$(rm_cli removal smart --dry-run --json | json "j['removal']") $(rm_cli removal --json | json "j['removal']")"
  rm_cli removal shred >/dev/null; rm_x=$?
  check "removal: an unknown word is a usage error and changes nothing" "2 delete" "$rm_x $(rm_cli removal --json | json "j['removal']")"
  check "removal: help lists the verb" 1 "$("$BIN" help --json 2>/dev/null | json "sum(v['verb'] == 'removal' for v in j['verbs'])")"
  rm_cli removal delete abc:0.x >/dev/null; rm_x=$?
  check "removal: a second word is a usage error, so an id never sets the choice" "2 delete" "$rm_x $(rm_cli removal --json | json "j['removal']")"
  rm_cli removal --delete abc:0.x >/dev/null; rm_x=$?
  check "removal: --delete without --waiting is a usage error" 2 "$rm_x"
  check "removal: help names the forms that change things" "--delete --put-back" "$("$BIN" help --json 2>/dev/null | json "' '.join([v for v in j['verbs'] if v['verb'] == 'removal'][0]['mutatingForms'])")"

  echo "-- what still waits in the staging folder, issue #67"
  check "removal: with nothing waiting, it says so" "Nothing waits in MinMacs's staging folder. 0" "$(rm_cli removal --waiting) $(rm_cli removal --waiting --json | json "len(j['waiting'])")"
  rm_ids=$(MINMACS_HOME="$rm_home" "$rm_dir/removaltest" --leave-waiting "$rm_home/fx" 2>/dev/null)
  rm_i1=$(echo "$rm_ids" | sed -n 1p); rm_i2=$(echo "$rm_ids" | sed -n 2p); rm_old=$(echo "$rm_ids" | sed -n 3p); rm_i3=$(echo "$rm_ids" | sed -n 4p)
  rm_j=$(rm_cli removal --waiting --json)
  check "removal: --waiting --json lists a delete that failed, an old path that is taken and a damaged record, each with its id and old path" "damaged delete-failed old-path-taken|$(printf '%s\n%s\n%s\n' "$rm_i1" "$rm_i2" "$rm_i3" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')|yes" \
    "$(echo "$rm_j" | json "' '.join(sorted(w['why'] for w in j['waiting'])) + '|' + ' '.join(sorted(w['id'] for w in j['waiting'])) + '|' + ('yes' if '$rm_old' in [w['oldPath'] for w in j['waiting']] else 'no')")"
  check "removal: the text list counts them and says what can be done with each" "3 items wait in MinMacs's staging folder for you to decide:|2|1" \
    "$(rm_cli removal --waiting | head -1)|$(rm_cli removal --waiting | grep -c 'Delete it with --delete, or put it back with --put-back.')|$(rm_cli removal --waiting | grep -c 'Put it back with --put-back.$')"
  rm_at=$(echo "$rm_j" | json "[w['stagedAt'] for w in j['waiting'] if w['id'] == '$rm_i1'][0]")
  rm_cli removal --waiting --delete "$rm_i1" >/dev/null; rm_x=$?
  check "removal: a delete needs the running app, and nothing goes" "3 yes" "$rm_x $([ -d "$rm_at" ] && echo yes || echo no)"
  check "removal: a dry run says what it would delete, and nothing goes" "Would delete node_modules yes" \
    "$(rm_cli removal --waiting --delete "$rm_i1" --dry-run | cut -d, -f1) $([ -d "$rm_at" ] && echo yes || echo no)"
  check "removal: a dry run of a put-back names where it would go" "Would put .env back at $rm_home/aside.env. Dry run. Nothing was changed." \
    "$(rm_cli removal --waiting --put-back "$rm_i2" --to "$rm_home/aside.env" --dry-run)"
  rm_out=$(rm_cli removal --waiting --delete "$rm_i3" --dry-run 2>&1); rm_x=$?
  check "removal: a dry run refuses as the real run would, for a damaged record" "1 yes" "$rm_x $(echo "$rm_out" | grep -q 'its record is damaged, so MinMacs does not delete it' && echo yes || echo no)"
  rm_out=$(rm_cli removal --waiting --put-back "$rm_i2" --dry-run 2>&1); rm_x=$?
  check "removal: a dry run refuses a put-back onto a taken old path" "1 yes" "$rm_x $(echo "$rm_out" | grep -q 'something already exists at' && echo yes || echo no)"
  rm_cli removal --waiting --delete --dry-run >/dev/null; rm_x=$?
  check "removal: --dry-run is never taken for an id" 2 "$rm_x"
  rm_cli removal --waiting --delete nope:0.x >/dev/null; rm_x=$?
  check "removal: an id that names nothing fails" 1 "$rm_x"
  rm_cli removal --waiting --to "$rm_home/x" >/dev/null; rm_x=$?
  check "removal: --to without --put-back is a usage error" 2 "$rm_x"
fi
