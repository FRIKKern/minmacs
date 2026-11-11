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
check "removal: Act deletes a file in one place only, MMRemovalApply" "1 0" \
  "$(grep -cE 'removeItemAt|unlink\(|rmdir\(|removefile\(' Sources/Core/Act/MMRemoval.m) $(grep -nE 'removeItemAt|unlink\(|rmdir\(|removefile\(|emptyTrash|rm -rf' Sources/Core/Act/*.m | grep -vc '^Sources/Core/Act/MMRemoval.m:')"
check "removal: no expert, shell or UI file deletes a person's file itself" 0 \
  "$(grep -nE 'removeItemAt|unlink\(|rmdir\(|removefile\(|trashItemAtURL' Sources/Experts/*/*.m Sources/Shell/MMFixRunner.m Sources/Shell/MMWindow*.m Sources/UI/Window/*.m | grep -c .)"
# The Trash is reached through MMRemovalApply alone. The migration's one move of the old apps asks for the Trash
# in its own confirm and stays there in every choice.
check "removal: only MMRemovalApply and the migration send a thing to the Trash" 0 \
  "$(grep -nE 'MMUndo\.shared trash:|\[u trash:' Sources --include='*.m' -r | grep -vcE '^Sources/Core/Act/MMRemoval\.m:|^Sources/Core/Store/MMMigrate\.m:')"
check "removal: the cache, config-file and worktree paths each ask MMRemovalDecide" "yes yes yes yes" \
  "$(for p in 'MMRemovalDecide(MMRemovalClutter' 'MMRemovalDecide(MMRemovalToolCopy'; do grep -q "$p" Sources/Core/Act/MMClutterAct.m && printf 'yes ' || printf 'no '; done
     for p in 'MMRemovalDecide(MMRemovalWorktree' 'MMRemovalDecide(MMRemovalConfigFiles'; do grep -q "$p" Sources/Experts/WorkForest/MMWorkForest.m && printf 'yes ' || printf 'no '; done | sed 's/ $//')"
check "removal: only MMRemoval.m reads the pref" 0 \
  "$(grep -rnE 'core\.removal|MMRemovalKey' Sources --include='*.m' | grep -vc '^Sources/Core/Act/MMRemoval\.m:')"
check "removal: git worktree remove never gets --force" 0 "$(grep -rnE '"--force"|@"-f"' Sources/Core/Act Sources/Experts/WorkForest | grep -c .)"
check "removal: no shown string says for good" 0 \
  "$(grep -nE '@"[^"]*for good' Sources/Core/Act/MMRemoval.m Sources/Shell/MMWindowRules.m Sources/Shell/MMFixRunner.m | grep -c .)"

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

  echo "-- the CLI"
  rm_home="$rm_dir/cli"; mkdir -p "$rm_home"
  rm_cli() { MINMACS_HOME="$rm_home" "$BIN" "$@" 2>&1; }
  check "removal: the verb shows smart before anything is set" "smart: Deletes what git or its tool can give back. The rest goes to the Trash." "$(rm_cli removal)"
  check "removal: it sets trash and reads it back" "trash trash" "$(rm_cli removal trash --json | json "j['removal']") $(rm_cli removal --json | json "j['removal']")"
  check "removal: it sets delete" "delete: Deletes everything it removes at once. Nothing can be brought back." "$(rm_cli removal delete)"
  check "removal: a dry run names the choice and changes nothing" "smart delete" "$(rm_cli removal smart --dry-run --json | json "j['removal']") $(rm_cli removal --json | json "j['removal']")"
  rm_cli removal shred >/dev/null; rm_x=$?
  check "removal: an unknown word is a usage error and changes nothing" "2 delete" "$rm_x $(rm_cli removal --json | json "j['removal']")"
  check "removal: help lists the verb" 1 "$("$BIN" help --json 2>/dev/null | json "sum(v['verb'] == 'removal' for v in j['verbs'])")"
fi
