# ===== Noo-Noo: a temp-folder family judged member by member, and cleaned as one folder in the Trash =====
# Sourced by test/noonoo.sh once its tool is built. Its own home and clutter root, $nn/fam, so its one record and its
# Trash are the only ones there. A stand-in TMPDIR holds a family of 2,000 old empty folders, 3 fresh ones and 1 that
# a fixture process has as its cwd, as clang leaves them with two -arch flags. Then 10,000 members for the timing.
# Fixtures only. The one process this file starts is in procs, and it stops it itself.

nf="$nn/fam"; nfr="$nf/root"; nf_T="$nfr/private/var/folders/zz/yyyy/T"
mkdir -p "$nfr/home" "$nf_T" "$nf/claude" "$nf/codex"
nff() { MINMACS_HOME="$nf" MINMACS_CLUTTER_ROOT="$nfr" MINMACS_CLUTTER_ROWS="$ROOT/registry/clutter" MINMACS_TOOLS="$nn/tools" \
        CLAUDE_CONFIG_DIR="$nf/claude" CODEX_HOME="$nf/codex" NN_PROJECTS= NN_MERGED= "$nn/tool" "$@"; }
nf_item() { nff verb clutter list --json 2>/dev/null | python3 -c "
import json,sys; j=json.load(sys.stdin)
m=[i for i in j['items'] if i['path']==sys.argv[1]]
print(m[0].get(sys.argv[2],'') if m else 'absent')" "$1" "$2"; }
nf_undo() { nff undo | python3 -c "import json,sys; j=json.load(sys.stdin); print($1)" "${2:-}"; }
nf_count() { find "$1" -mindepth 1 -maxdepth 1 -name "$2" 2>/dev/null | wc -l | tr -d ' '; }

echo "-- a temp-folder family, member by member"
(cd "$nf_T" && python3 -c "
import os
for i in range(2000): os.mkdir('ccbuild-%06x' % (0x100000 + i))
os.mkdir('ccbuild-ee0001')")
find "$nf_T" -mindepth 1 -maxdepth 1 -exec touch -h -t 202601010000 {} +
for s in ff0001 ff0002 ff0003; do mkdir "$nf_T/ccbuild-$s"; done   # written just now
(cd "$nf_T/ccbuild-ee0001" && exec sleep 120) &
nf_holder=$!; procs="$procs $nf_holder"
sleep 0.3
nff scan >/dev/null 2>&1
nf_fam="$nf_T/ccbuild-*"
check "noonoo: a family with fresh members is a leftover for its old ones" "leftovers free 2004 2000" \
  "$(nf_item "$nf_fam" section) $(nf_item "$nf_fam" state) $(nf_item "$nf_fam" members) $(nf_item "$nf_fam" leftovers)"
check "noonoo: its why says the split" "2000 old and empty, 3 empty and written in the last 60 minutes, 1 in use" "$(nf_item "$nf_fam" why)"
nff modes >"$nf/modes.txt" 2>/dev/null
check "noonoo: Proactive and Eager take the family's leftovers" "go go" \
  "$(awk '$1=="tmpdir-families" && $2=="leftovers" {print $3" "$4; exit}' "$nf/modes.txt")"
check "noonoo: a dry run names the old ones and what stays" yes \
  "$(nff verb clean "$nf_T/ccbuild-100000" --dry-run 2>/dev/null | grep -q 'would move 2000 folders of .* into one folder in the Trash, and leave 4 folders' && echo yes || echo no)"

nff verb clean "$nf_T/ccbuild-100000" >"$nf/clean.txt" 2>&1
check "noonoo: the clean of a family goes through" 0 "$?"
check "noonoo: the old members left, the fresh and the held one stayed" "4 3 yes" \
  "$(nf_count "$nf_T" 'ccbuild-*') $(nf_count "$nf_T" 'ccbuild-ff*') $([ -d "$nf_T/ccbuild-ee0001" ] && echo yes || echo no)"
check "noonoo: they are one folder in the test home's Trash, holding all 2,000" "1 2000" \
  "$(nf_count "$nf/Trash" '*') $(find "$nf/Trash" -mindepth 2 -maxdepth 2 | wc -l | tr -d ' ')"
check "noonoo: the Trash folder names the family and that it was MinMacs" yes \
  "$(ls "$nf/Trash" | grep -q '^ccbuild (2000 folders old, MinMacs [0-9-]* [0-9.]*)$' && echo yes || echo no)"
check "noonoo: one record for the family, not 2,000" "1 trash 0 2000" \
  "$(nf_undo 'len(j), j[0]["kind"], len(j[0]["payload"].get("trashed", [])), len(j[0]["payload"]["held"]["members"])' | tr -d '(),'"'")"
check "noonoo: MinMacs's own Trash list names the one folder" 1 \
  "$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['items']))" "$nf/core/trashed/$(nf_undo 'j[0]["rid"]').json" 2>/dev/null)"
check "noonoo: the record keeps counts, not each member's audit" "2000 2000 0" \
  "$(nf_undo '"%s %s %s" % (j[0]["payload"]["audit"]["before"]["leftovers"], j[0]["payload"]["audit"]["after"]["moved"], j[0]["payload"]["audit"]["after"]["leftoversStillThere"])')"
check "noonoo: the record can be undone" True "$(nf_undo 'j[0]["canRestore"]')"
nff scan >/dev/null 2>&1
check "noonoo: after the clean its 4 left are too few to be a family" absent "$(nf_item "$nf_fam" section)"

nff verb clean --undo "$(nf_undo 'j[0]["rid"]')" >"$nf/undo.txt" 2>&1
check "noonoo: undo of the family goes through" 0 "$?"
check "noonoo: undo brings every member back to its old name" "2004 restored" \
  "$(nf_count "$nf_T" 'ccbuild-*') $(nf_undo 'j[0]["state"]')"
check "noonoo: the members are the very folders that left" yes \
  "$(nf_undo '"yes" if all(__import__("os").lstat(__import__("os").path.join(sys.argv[1], m["name"])).st_ino == m["ino"] for m in j[0]["payload"]["held"]["members"]) else "no"' "$nf_T")"
check "noonoo: the folder in the Trash is left empty, and nothing was deleted" "1 0" \
  "$(nf_count "$nf/Trash" '*') $(find "$nf/Trash" -mindepth 2 | wc -l | tr -d ' ')"
check "noonoo: and MinMacs's list no longer names it" 0 \
  "$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['items']))" "$nf/core/trashed/$(nf_undo 'j[0]["rid"]').json" 2>/dev/null)"
check "noonoo: a second undo is refused" 1 "$(nff verb clean --undo "$(nf_undo 'j[0]["rid"]')" >/dev/null 2>&1; echo $?)"
kill "$nf_holder" 2>/dev/null; wait "$nf_holder" 2>/dev/null
procs=$(printf '%s' "$procs" | sed "s/ $nf_holder//")

echo "-- 10,000 members: the scan and the clean stay within budget"
# The scan runs on Core's clutter queue every hour and the clean on Noo-Noo's act queue, never on the 5-second tick
# or main. The budgets are generous for a shared Mac under load: 15 seconds for each. Before members were judged in
# one pass, a scan of 45,000 took 26 seconds and 2.8 GB here.
rm -rf "$nf_T"/ccbuild-*
(cd "$nf_T" && python3 -c "
import os
for i in range(10000): os.mkdir('bigfam-%06x' % (0x200000 + i))")
find "$nf_T" -mindepth 1 -maxdepth 1 -exec touch -h -t 202601010000 {} +
nf_t0=$(python3 -c 'import time; print(time.time())')
nff scan >/dev/null 2>&1
nf_t1=$(python3 -c 'import time; print(time.time())')
nff verb clean "$nf_T/bigfam-200000" >/dev/null 2>&1
nf_t2=$(python3 -c 'import time; print(time.time())')
nf_scan=$(python3 -c "print('%.1f' % ($nf_t1 - $nf_t0))"); nf_clean=$(python3 -c "print('%.1f' % ($nf_t2 - $nf_t1))")
echo "  info  a scan of 10,000 members took ${nf_scan}s, their clean ${nf_clean}s"
check "noonoo: a scan of 10,000 members stays under 15 seconds" yes "$(python3 -c "print('yes' if $nf_scan < 15 else 'no')")"
check "noonoo: their clean stays under 15 seconds" yes "$(python3 -c "print('yes' if $nf_clean < 15 else 'no')")"
check "noonoo: all 10,000 went, as one folder in the Trash" "0 10000" \
  "$(nf_count "$nf_T" 'bigfam-*') $(find "$nf/Trash" -mindepth 2 -maxdepth 2 -name 'bigfam-*' | wc -l | tr -d ' ')"
nff verb clean --undo "$(nf_undo 'j[0]["rid"]')" >/dev/null 2>&1
check "noonoo: and all 10,000 came back" 10000 "$(nf_count "$nf_T" 'bigfam-*')"
