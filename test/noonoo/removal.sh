# Where removed clutter goes, issue #62 and D2. Sourced at the end of test/noonoo.sh, inside its fixtures: every path
# here is under $nn, which is inside $MINMACS_HOME, the Trash is $nn/Trash, and MMRemovalApply refuses any path
# outside the tool's MINMACS_HOME. Each old value of the pref runs on the same items, made again before it:
#   node_modules of the merged worktree   build row, rebuilt, with a package-lock.json beside it
#                                                                   the pip cache      cache row, rebuilt
#   Cursor's Cache folder                 cache row, not rebuilt    a dead scratch     leak row
#   six mktemp siblings                   leak row, a family        simulator Devices  tool row, not rebuilt
#   the fake tool's cache                 tool row, rebuilt for this block
echo "-- an old removal choice in the pref, on the same items"
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

# D2: with an old smart or delete in the pref, as an older MinMacs wrote it, everything still keeps a way back.
nnr_old() {   # the old value
  echo "-- an old $1 in the pref: everything goes to the Trash or a recovery copy"
  old_removal "$nn" "$1"
  nnr_fill
  nnr_t0=$(nnr_trash)
  check "noonoo old $1: the row's action says Move to Trash for node_modules and for a leftover" "Move to Trash|Move to Trash" \
    "$(nnx_show "$nn_wt/node_modules" 'j["action"]')|$(nnx_show "$nn_scr/$nn_dead" 'j["action"]')"
  check "noonoo old $1: no dry run says delete or cannot be brought back" "no no no" \
    "$(for p in "$nn_wt/node_modules" "$nn_scr/$nn_dead" "$nnx_c"; do nnx verb clean "$p" --dry-run 2>/dev/null | grep -qE 'would delete|cannot be brought back' && printf 'yes ' || printf 'no '; done | sed 's/ $//')"
  check "noonoo old $1: finished node_modules, which a tool rebuilds, goes to the Trash" "0 gone trash False 1 0 True" "$(nnr_go "$nn_wt/node_modules")"
  check "noonoo old $1: its record says so" "it goes to the Trash, so Restore moves it back" "$(nn_undo 'j[0]["payload"]["removal"]["why"]')"
  check "noonoo old $1: and undo brings it back" "0 back" "$(nnr_back "$nn_wt/node_modules")"
  check "noonoo old $1: the pip cache goes to the Trash" "0 gone trash False 1 0 True" "$(nnr_go "$nnr_pip")"
  check "noonoo old $1: the notes a symlink inside it pointed at stay" notes "$(cat "$nnh/Documents/notes.txt" 2>/dev/null)"
  check "noonoo old $1: and undo brings it back, the link as a link" "0 back yes" "$(nnr_back "$nnr_pip") $([ -L "$nnr_pip/docs-link" ] && echo yes || echo no)"
  check "noonoo old $1: a cache whose row does not say rebuilt goes to the Trash" "0 gone trash False 1 0 True" "$(nnr_go "$nnr_cur")"
  check "noonoo old $1: and undo brings it back" "0 back" "$(nnr_back "$nnr_cur")"
  check "noonoo old $1: a leftover goes to the Trash" "0 gone trash False 1 0 True" "$(nnr_go "$nn_scr/$nn_dead")"
  check "noonoo old $1: and undo brings it back" "0 back" "$(nnr_back "$nn_scr/$nn_dead")"
  check "noonoo old $1: every member of a leftover family goes to the Trash" "0 gone trash False 6 0 True" "$(nnr_go "$nnr_fam")"
  check "noonoo old $1: and undo brings them back" "0 back" "$(nnr_back "$nnr_fam")"
  check "noonoo old $1: everything removed went to the Trash and came back out of it" "$nnr_t0" "$(nnr_trash)"
  check "noonoo old $1: a tool row that is not rebuilt gets its recovery copy, and only its own target goes" "0 gone kept trash False 1 True" \
    "$(nnx verb clean "$nn_dev" >/dev/null 2>&1; echo $?) $([ -e "$nn_dev/$nn_gone" ] && echo kept || echo gone) $([ -e "$nn_dev/$nn_keep" ] && echo kept || echo gone) $(nn_undo '"%s %s %d %s" % (j[0]["payload"]["removal"]["choice"], j[0]["payload"]["removal"]["deleted"], len(j[0]["payload"]["recovery"]["saved"]), j[0]["canRestore"])')"
  check "noonoo old $1: and undo copies the device back" "0 back" "$(nnr_back "$nn_dev/$nn_gone")"
  check "noonoo old $1: a rebuilt tool row's dry run says a recovery copy is made first" yes \
    "$(nnx verb clean "$nnx_c" --dry-run 2>/dev/null | grep -q 'to the recovery folder, then run' && echo yes || echo no)"
  nnx verb clean "$nnx_c" >/dev/null 2>&1
  check "noonoo old $1: a rebuilt tool row still gets its recovery copy, and can restore" "0 clean False yes True" \
    "$(nnx_files cache) $(nn_undo '"%s %s %s %s" % (j[0]["kind"], j[0]["payload"]["removal"]["deleted"], "yes" if "recovery" in j[0]["payload"] else "no", j[0]["canRestore"])')"
  check "noonoo old $1: its recovery folder was made" yes "$([ -e "$nn/noonoo/recovery/$(nn_undo 'j[0]["rid"]')" ] && echo yes || echo no)"
  check "noonoo old $1: the walls still hold: an unlisted cache and the home folder stay" "1 1 yes yes" \
    "$(nnx verb clean "$nnh/Library/Caches/random-app" >/dev/null 2>&1; echo $?) $(nnx verb clean "$nnh" >/dev/null 2>&1; echo $?) $([ -f "$nnh/Library/Caches/random-app/c" ] && echo yes || echo no) $([ -f "$nnh/Documents/notes.txt" ] && echo yes || echo no)"
  check "noonoo old $1: a kept item stays: the transcripts and the tracked dist folder" "yes yes" \
    "$(nnx verb clean "$nn/claude/projects/-code-acme" >/dev/null 2>&1; [ -d "$nn/claude/projects/-code-acme" ] && echo yes || echo no) $(nnx verb clean "$nn_main/dist" >/dev/null 2>&1; [ -f "$nn_main/dist/app.js" ] && echo yes || echo no)"
}
nnr_old smart
nnr_old delete
check "noonoo: the CLI never says a removed item cannot be brought back" no \
  "$(nnr_fill; nnx verb clean "$nnr_cur" 2>/dev/null | grep -q 'cannot be brought back' && echo yes || echo no)"
nn_rowdirs=""
