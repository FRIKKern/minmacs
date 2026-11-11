# The removal choice on clutter, issue #62. Sourced at the end of test/noonoo.sh, inside its fixtures: every path
# here is under $nn, which is inside $MINMACS_HOME, the Trash is $nn/Trash, and MMRemovalApply refuses any path
# outside the tool's MINMACS_HOME. Each choice runs on the same items, made again before it:
#   node_modules of the merged worktree   build row, rebuilt, with a package-lock.json beside it
#                                                                   the pip cache      cache row, rebuilt
#   Cursor's Cache folder                 cache row, not rebuilt    a dead scratch     leak row
#   six mktemp siblings                   leak row, a family        simulator Devices  tool row, not rebuilt
#   the fake tool's cache                 tool row, rebuilt for this block
echo "-- the removal choice: smart, trash and delete on the same items"
nnr_cur="$nnh/Library/Application Support/Cursor/Cache"
nnr_pip="$nnh/Library/Caches/pip"
nnr_fam="$nn_T/mv-test-a1B2c3"
nn_rowdirs="$ROOT/registry/clutter:$nn/rows"
# sh keeps an assignment made in front of a function call, so the slow mode of the block above is still set here.
unset NN_FAKE_MODE NN_CMD_TIMEOUT
cat >"$nn/rows/nn-fake-cache.json" <<NNROW
{"id": "nn-fake-cache", "title": "Fake cache", "group": "js", "class": "tool", "paths": ["~/.nnfake/cache"],
 "cleanup": ["$nnx_tool", "cache", "clean"], "dryRun": ["$nnx_tool", "cache", "clean", "--dry-run"],
 "rebuild": "The fake tool downloads it again", "rebuilt": true, "every": 600}
NNROW
nnr_fill() {
  mkdir -p "$nn_wt/node_modules/left-pad" "$nnr_pip/http" "$nnr_cur" "$nn_scr/$nn_dead/scratchpad/run" "$nn_dev/$nn_gone/data"
  printf 'module.exports = 1\n' >"$nn_wt/node_modules/left-pad/index.js"
  printf 'wheel\n' >"$nnr_pip/http/wheel.bin"
  [ -L "$nnr_pip/docs-link" ] || ln -s "$nnh/Documents" "$nnr_pip/docs-link"
  printf 'c\n' >"$nnr_cur/c"
  printf 'scratch\n' >"$nn_scr/$nn_dead/scratchpad/run/out.txt"
  for s in a1B2c3 d4E5f6 g7H8i9 j1K2l3 m4N5o6 p7Q8r9; do mkdir -p "$nn_T/mv-test-$s"; printf 'x\n' >"$nn_T/mv-test-$s/f"; done
  printf 'old phone\n' >"$nn_dev/$nn_gone/data/app.db"; : >"$nn_dev/$nn_gone/unavailable"
  nn_old "$nn_scr/$nn_dead" "$nn_T"/mv-test-*
  nnx_fill
  nnx scan >/dev/null 2>&1
}
# Cleans one path and prints: exit, gone or kept, then the newest record's choice, deleted, trashed count,
# deleted count and canRestore.
nnr_go() {
  nnx verb clean "$1" >/dev/null 2>&1; nnr_x=$?
  echo "$nnr_x $([ -e "$1" ] && echo kept || echo gone) $(nn_undo '"%s %s %d %d %s" % (j[0]["payload"]["removal"]["choice"], j[0]["payload"]["removal"]["deleted"], len(j[0]["payload"].get("trashed", [])), len(j[0]["payload"].get("deleted", [])), j[0]["canRestore"])')"
}
# Undoes the newest record and prints: exit, then back or missing for the path.
nnr_back() {
  nnx verb clean --undo "$(nn_undo 'j[0]["rid"]')" >"$nn/nnr-undo.txt" 2>&1; nnr_x=$?
  echo "$nnr_x $([ -e "$1" ] && echo back || echo missing)"
}
nnr_trash() { ls -A "$nn/Trash" 2>/dev/null | wc -l | tr -d ' '; }

echo "-- smart: what a tool rebuilds is deleted, the rest goes to the Trash"
nn_removal smart >/dev/null
nnr_fill
nnr_t0=$(nnr_trash)
check "noonoo smart: the row's action says Delete for node_modules and Move to Trash for a leftover" "Delete|Move to Trash" \
  "$(nnx_show "$nn_wt/node_modules" 'j["action"]')|$(nnx_show "$nn_scr/$nn_dead" 'j["action"]')"
check "noonoo smart: finished node_modules is deleted at once" "0 gone smart True 0 1 False" "$(nnr_go "$nn_wt/node_modules")"
check "noonoo smart: its record says why and where, and holds the freed bytes" "its tool rebuilds it|$nn_wt/node_modules|int" \
  "$(nn_undo '"%s|%s|%s" % (j[0]["payload"]["removal"]["why"], j[0]["payload"]["deleted"][0]["path"], type(j[0]["freedBytes"]).__name__)')"
check "noonoo smart: undo of it is refused, and it stays gone" "1 missing yes" \
  "$(nnr_back "$nn_wt/node_modules") $(grep -q 'it was deleted and cannot be brought back' "$nn/nnr-undo.txt" && echo yes || echo no)"
# The row says rebuilt. Smart still needs the proof on the folder read now: a lockfile beside it, and nothing in it
# that git tracks. Without either, it keeps a way back.
nnr_fill
mv "$nn_wt/package-lock.json" "$nn/lock.aside"
nnx scan >/dev/null 2>&1
check "noonoo smart: node_modules with no lockfile beside it goes to the Trash" "0 gone smart False 1 0 True" "$(nnr_go "$nn_wt/node_modules")"
check "noonoo smart: its record says which file is missing" yes \
  "$(nn_undo '"yes" if j[0]["payload"]["removal"]["why"].startswith("no package-lock.json or npm-shrinkwrap.json or pnpm-lock.yaml") else j[0]["payload"]["removal"]["why"]')"
check "noonoo smart: and undo brings it back" "0 back" "$(nnr_back "$nn_wt/node_modules")"
mv "$nn/lock.aside" "$nn_wt/package-lock.json"
nn_git -C "$nn_wt" add -f node_modules/left-pad/index.js
nnx scan >/dev/null 2>&1
check "noonoo smart: node_modules with a file git tracks goes to the Trash" "0 gone smart False 1 0 True git tracks files in it, so it is part of the project" \
  "$(nnr_go "$nn_wt/node_modules") $(nn_undo 'j[0]["payload"]["removal"]["why"]')"
check "noonoo smart: and undo brings it back" "0 back" "$(nnr_back "$nn_wt/node_modules")"
nn_git -C "$nn_wt" rm -q --cached node_modules/left-pad/index.js
check "noonoo smart: the row's action says Move to Trash while the proof is missing, and Delete once it holds" "Move to Trash|Delete" \
  "$(mv "$nn_wt/package-lock.json" "$nn/lock.aside"; nnx scan >/dev/null 2>&1; nnx_show "$nn_wt/node_modules" 'j["action"]'; mv "$nn/lock.aside" "$nn_wt/package-lock.json")|$(nnx scan >/dev/null 2>&1; nnx_show "$nn_wt/node_modules" 'j["action"]')"
check "noonoo smart: the pip cache is deleted at once" "0 gone smart True 0 1 False" "$(nnr_go "$nnr_pip")"
check "noonoo smart: a symlink inside it went as a link, and the notes it pointed at stay" notes "$(cat "$nnh/Documents/notes.txt" 2>/dev/null)"
check "noonoo smart: nothing deleted went to the Trash" "$nnr_t0" "$(nnr_trash)"
check "noonoo smart: a cache whose row does not say rebuilt goes to the Trash" "0 gone smart False 1 0 True" "$(nnr_go "$nnr_cur")"
check "noonoo smart: its record says why it was kept" "its row does not say that a tool rebuilds it" "$(nn_undo 'j[0]["payload"]["removal"]["why"]')"
check "noonoo smart: and undo brings it back" "0 back" "$(nnr_back "$nnr_cur")"
check "noonoo smart: a leftover goes to the Trash" "0 gone smart False 1 0 True" "$(nnr_go "$nn_scr/$nn_dead")"
check "noonoo smart: its record says it is a leftover" "it is a leftover, and nothing rebuilds a leftover" "$(nn_undo 'j[0]["payload"]["removal"]["why"]')"
check "noonoo smart: and undo brings it back" "0 back" "$(nnr_back "$nn_scr/$nn_dead")"
check "noonoo smart: every member of a leftover family goes to the Trash" "0 gone smart False 6 0 True" "$(nnr_go "$nnr_fam")"
check "noonoo smart: and undo brings them back" "0 back" "$(nnr_back "$nnr_fam")"
check "noonoo smart: a tool row that is not rebuilt still gets its recovery copy" "0 gone smart False 1 True" \
  "$(nnx verb clean "$nn_dev" >/dev/null 2>&1; echo $?) $([ -e "$nn_dev/$nn_gone" ] && echo kept || echo gone) $(nn_undo '"%s %s %d %s" % (j[0]["payload"]["removal"]["choice"], j[0]["payload"]["removal"]["deleted"], len(j[0]["payload"]["recovery"]["saved"]), j[0]["canRestore"])')"
check "noonoo smart: and undo copies the device back" "0 back" "$(nnr_back "$nn_dev/$nn_gone")"
check "noonoo smart: a rebuilt tool row's dry run says no recovery copy is made" yes \
  "$(nnx verb clean "$nnx_c" --dry-run 2>/dev/null | grep -q 'with no recovery copy, since its tool fetches it again. It cannot be brought back.' && echo yes || echo no)"
nnx verb clean "$nnx_c" >/dev/null 2>&1
check "noonoo smart: a rebuilt tool row runs its command with no recovery copy" "0 clean True no False" \
  "$(nnx_files cache) $(nn_undo '"%s %s %s %s" % (j[0]["kind"], j[0]["payload"]["removal"]["deleted"], "yes" if "recovery" in j[0]["payload"] else "no", j[0]["canRestore"])')"
check "noonoo smart: no recovery folder was made for it" no "$([ -e "$nn/noonoo/recovery/$(nn_undo 'j[0]["rid"]')" ] && echo yes || echo no)"
check "noonoo smart: its record says it cannot be brought back" yes \
  "$(nn_undo '"yes" if "no recovery copy" in j[0]["payload"].get("undo", "") and "cannot be brought back" in j[0]["payload"]["undo"] else "no"')"

echo "-- trash: everything keeps a way back"
nn_removal trash >/dev/null
nnr_fill
check "noonoo trash: the row's action says Move to Trash for node_modules" "Move to Trash" "$(nnx_show "$nn_wt/node_modules" 'j["action"]')"
check "noonoo trash: finished node_modules goes to the Trash" "0 gone trash False 1 0 True" "$(nnr_go "$nn_wt/node_modules")"
check "noonoo trash: and undo brings it back" "0 back" "$(nnr_back "$nn_wt/node_modules")"
nnx verb clean "$nnx_c" >/dev/null 2>&1
check "noonoo trash: a rebuilt tool row still gets its recovery copy" "0 trash False yes True" \
  "$(nnx_files cache) $(nn_undo '"%s %s %s %s" % (j[0]["payload"]["removal"]["choice"], j[0]["payload"]["removal"]["deleted"], "yes" if "recovery" in j[0]["payload"] else "no", j[0]["canRestore"])')"

echo "-- delete: everything it removes is deleted at once"
nn_removal delete >/dev/null
nnr_fill
nnr_t0=$(nnr_trash)
check "noonoo delete: a leftover's dry run says it is deleted, since you chose Delete" yes \
  "$(nnx verb clean "$nn_scr/$nn_dead" --dry-run 2>/dev/null | grep -q 'would delete .*, since you chose Delete, so it is deleted at once. It cannot be brought back.' && echo yes || echo no)"
check "noonoo delete: the row's action says Delete for a leftover" Delete "$(nnx_show "$nn_scr/$nn_dead" 'j["action"]')"
check "noonoo delete: a leftover is deleted" "0 gone delete True 0 1 False" "$(nnr_go "$nn_scr/$nn_dead")"
check "noonoo delete: undo of it is refused" "1 missing" "$(nnr_back "$nn_scr/$nn_dead")"
check "noonoo delete: every member of a leftover family is deleted" "0 gone delete True 0 6 False" "$(nnr_go "$nnr_fam")"
check "noonoo delete: a cache that is not rebuilt is deleted" "0 gone delete True 0 1 False" "$(nnr_go "$nnr_cur")"
check "noonoo delete: finished node_modules is deleted" "0 gone delete True 0 1 False" "$(nnr_go "$nn_wt/node_modules")"
check "noonoo delete: nothing went to the Trash" "$nnr_t0" "$(nnr_trash)"
nnx verb clean "$nn_dev" >/dev/null 2>&1
check "noonoo delete: a tool row runs with no recovery copy, and only its own target goes" "gone kept delete True no False" \
  "$([ -e "$nn_dev/$nn_gone" ] && echo kept || echo gone) $([ -e "$nn_dev/$nn_keep" ] && echo kept || echo gone) $(nn_undo '"%s %s %s %s" % (j[0]["payload"]["removal"]["choice"], j[0]["payload"]["removal"]["deleted"], "yes" if "recovery" in j[0]["payload"] else "no", j[0]["canRestore"])')"
check "noonoo delete: the walls still hold: an unlisted cache and the home folder stay" "1 1 yes yes" \
  "$(nnx verb clean "$nnh/Library/Caches/random-app" >/dev/null 2>&1; echo $?) $(nnx verb clean "$nnh" >/dev/null 2>&1; echo $?) $([ -f "$nnh/Library/Caches/random-app/c" ] && echo yes || echo no) $([ -f "$nnh/Documents/notes.txt" ] && echo yes || echo no)"
check "noonoo delete: a kept item stays: the transcripts and the tracked dist folder" "yes yes" \
  "$(nnx verb clean "$nn/claude/projects/-code-acme" >/dev/null 2>&1; [ -d "$nn/claude/projects/-code-acme" ] && echo yes || echo no) $(nnx verb clean "$nn_main/dist" >/dev/null 2>&1; [ -f "$nn_main/dist/app.js" ] && echo yes || echo no)"
check "noonoo: the CLI says a deleted item cannot be brought back" yes \
  "$(nnr_fill; nnx verb clean "$nnr_cur" 2>/dev/null | grep -q '^deleted .*\. It cannot be brought back\.$' && echo yes || echo no)"
nn_removal smart >/dev/null
nn_rowdirs=""
