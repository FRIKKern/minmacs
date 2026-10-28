# ===== Store: the support folder, prefs, state files, rules, the SQLite log, the migration and Settings =====
# Sourced by test.sh. Everything runs inside $MINMACS_HOME. The old apps' files are copies of the fixtures
# in test/store/legacy, so the person's own state and prefs are never read or written here.

st_dir="$MINMACS_HOME/store"
mkdir -p "$st_dir"
st_bin="$st_dir/check"
st_real_prefs="$HOME/Library/Preferences/no.guerrilla.minmacs.plist"
st_real_before=$(stat -f '%m %z' "$st_real_prefs" 2>/dev/null || echo none)

if clang -fobjc-arc -Wall -mmacosx-version-min=14.0 -ISources -framework Cocoa -framework IOKit -framework UserNotifications -lsqlite3 \
     $(find Sources/Core -name '*.m' | LC_ALL=C sort) test/store/check.m -o "$st_bin" >"$st_dir/build.log" 2>&1; then
  check "test/store/check.m builds with no warnings" 0 "$(grep -c "warning:" "$st_dir/build.log")"
else
  check "test/store/check.m builds" 0 1
  cat "$st_dir/build.log"
fi
check "the app links libsqlite3" yes "$(otool -L "$BIN" 2>/dev/null | grep -q libsqlite3 && echo yes || echo no)"

# Unit checks, in a fresh home of their own.
st_home="$st_dir/unit"; mkdir -p "$st_home"
st_tab=$(printf '\t')
MINMACS_HOME="$st_home" "$st_bin" unit >"$st_dir/unit.out" 2>"$st_dir/unit.err"
check "test/store/check.m runs" 0 "$?"
while IFS="$st_tab" read -r st_n st_w st_g; do check "$st_n" "$st_w" "$st_g"; done <"$st_dir/unit.out"

db="$st_home/minmacs.sqlite"
check "the log runs in WAL mode" wal "$(sqlite3 "$db" 'PRAGMA journal_mode;' 2>/dev/null)"
# The trigger's error code depends on the SQLite build: 1 here, 19 on the CI runner. Any refusal counts.
sqlite3 "$db" "UPDATE rows SET state = 'x';" >/dev/null 2>&1
check "the log refuses UPDATE" yes "$([ $? -ne 0 ] && echo yes || echo no)"
sqlite3 "$db" "DELETE FROM rows;" >/dev/null 2>&1
check "the log refuses DELETE" yes "$([ $? -ne 0 ] && echo yes || echo no)"
check "the rows are still there" 5 "$(sqlite3 "$db" 'SELECT COUNT(*) FROM rows;' 2>/dev/null)"

# Two processes at once: the lock and the busy timeout lose nothing.
st_home="$st_dir/race"; mkdir -p "$st_home"
MINMACS_HOME="$st_home" "$st_bin" counter 200 & st_p1=$!
MINMACS_HOME="$st_home" "$st_bin" counter 200 & st_p2=$!
MINMACS_HOME="$st_home" "$st_bin" logwrite 300 app & st_p3=$!
MINMACS_HOME="$st_home" "$st_bin" logwrite 300 cli & st_p4=$!
procs="$procs $st_p1 $st_p2 $st_p3 $st_p4"
st_rc=0; for st_p in $st_p1 $st_p2 $st_p3 $st_p4; do wait "$st_p" || st_rc=1; done
check "four writers at once all exit 0" 0 "$st_rc"
check "a state file under flock loses no update" 400 "$(json 'j["n"]' <"$st_home/locktest/counter.json" 2>/dev/null)"
check "two log writers lose no row" 600 "$(sqlite3 "$st_home/minmacs.sqlite" 'SELECT COUNT(*) FROM rows;' 2>/dev/null)"
# An append that leaves its statement open blocks every checkpoint, and the rows then sit in the WAL alone.
check "appends reach the database file, not only the WAL" yes \
  "$([ "$(stat -f %z "$st_home/minmacs.sqlite")" -gt 4096 ] && echo yes || echo no)"
check "each writer kept its own order" 299,299 \
  "$(sqlite3 "$st_home/minmacs.sqlite" "SELECT (SELECT subject FROM rows WHERE expert='app' ORDER BY row DESC LIMIT 1) || ',' || (SELECT subject FROM rows WHERE expert='cli' ORDER BY row DESC LIMIT 1);" 2>/dev/null)"

# Two writers open a new log while another reader holds it in rollback mode, as a first launch can meet.
# Setting WAL mode then needs an exclusive lock, and SQLite refuses one of the two at once, without the busy timeout.
# Each round must still keep every row and log no schema error.
st_lost=0; st_errs=0
for st_k in 1 2 3; do
  st_home="$st_dir/held$st_k"; mkdir -p "$st_home"
  python3 test/store/hold.py "$st_home/minmacs.sqlite" 1.5 & st_hp=$!; procs="$procs $st_hp"
  st_i=0; while [ ! -e "$st_home/minmacs.sqlite.held" ] && [ $st_i -lt 100 ]; do sleep 0.05; st_i=$((st_i+1)); done
  MINMACS_HOME="$st_home" "$st_bin" logwrite 50 app 2>"$st_home/a.err" & st_p1=$!
  MINMACS_HOME="$st_home" "$st_bin" logwrite 50 cli 2>"$st_home/b.err" & st_p2=$!
  procs="$procs $st_p1 $st_p2"
  wait "$st_p1"; wait "$st_p2"; wait "$st_hp"
  st_n=$(sqlite3 "$st_home/minmacs.sqlite" 'SELECT COUNT(*) FROM rows;' 2>/dev/null || echo 0)
  st_lost=$((st_lost + 100 - ${st_n:-0}))
  st_errs=$((st_errs + $(cat "$st_home/a.err" "$st_home/b.err" | grep -c 'log schema\|log append')))
done
check "two writers that meet a held lock on a new log lose no row" 0 "$st_lost"
check "and neither logs a schema or append error" 0 "$st_errs"

# The migration, on copies of the old apps' files and prefs.
st_home="$st_dir/migrate"; st_old="$st_home/old"
mkdir -p "$st_old/Library/Application Support/LocoHost" "$st_old/Library/Application Support/MinMacs" "$st_old/Library/Preferences"
cp test/store/legacy/locohost/*.json "$st_old/Library/Application Support/LocoHost/"
cp test/store/legacy/minmacs/rules.json "$st_old/Library/Application Support/MinMacs/"
cp test/store/legacy/prefs/*.plist "$st_old/Library/Preferences/"
st_sum() { (cd "$st_old" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum | shasum | cut -d' ' -f1); }
st_before=$(st_sum)
st_new="$st_home/new"; mkdir -p "$st_new"
MINMACS_HOME="$st_new" "$st_bin" plan "$st_old" >"$st_dir/plan.json"
check "the plan reads every old file and domain" 8 "$(json 'len(j["sources"])' <"$st_dir/plan.json")"
check "the plan writes nothing" 0 "$(find "$st_new" -name '*.json' -o -name '*.sqlite' | grep -c .)"
MINMACS_HOME="$st_new" "$st_bin" import "$st_old" >"$st_dir/import.json"
check "the import exits 0" 0 "$?"
check "the old files and prefs are unchanged" "$st_before" "$(st_sum)"
st_pref() { /usr/libexec/PlistBuddy -c "Print :'$1'" "$st_new/Preferences/no.guerrilla.minmacs.plist" 2>/dev/null; }
check "locohost.mode carries over" idle "$(st_pref locohost.mode)"
check "locohost.idleMinutes carries over" 45 "$(st_pref locohost.idleMinutes)"
check "locohost.model becomes review.model" haiku "$(st_pref review.model)"
check "LocoHost's hidden icon stays hidden" false "$(st_pref 'NSStatusItem Visible minmacs.locohost')"
check "MinMacs 1.2's visible icon stays visible" true "$(st_pref 'NSStatusItem Visible minmacs.minmacs')"
check "minmacs.askBeforeClosing carries over" false "$(st_pref minmacs.askBeforeClosing)"
check "a key of no old app is left out" "" "$(st_pref unrelated.key)"
check "the restore prefs are not copied as prefs" "" "$(st_pref minmacs.closedBundleIDs)"
check "LocoHost rules become flat named lists" "5432,8080" \
  "$(json '",".join(str(x) for x in j["protect.ports"])' <"$st_new/locohost/rules.json")"
check "MinMacs 1.2 rules keep their wildcards" "com.apple.Terminal,com.jetbrains.*,*noo-noo*" \
  "$(json '",".join(j["keep"])' <"$st_new/minmacs/rules.json")"
check "MinMacs 1.2 tab lists become tabs.noise and tabs.work" "youtube.com github.com,localhost" \
  "$(json '",".join(j["tabs.noise"])+" "+",".join(j["tabs.work"])' <"$st_new/minmacs/rules.json")"
check "LocoHost activity carries over" 1793100000 "$(json 'j["hosts"]["dev:3000:/tmp/acme-web"]["lastActive"]' <"$st_new/locohost/activity.json")"
check "LocoHost keep.json becomes kept.json" 1893456000 "$(json 'j["dev:3000:/tmp/acme-web"]' <"$st_new/locohost/kept.json")"
st_db="$st_new/minmacs.sqlite"
check "each LocoHost stop becomes an undo row, oldest first" ":3001 acme-web|:4251 orbit-api" \
  "$(sqlite3 "$st_db" "SELECT group_concat(subject, '|') FROM (SELECT subject FROM rows WHERE tbl='undo' AND expert='locohost' ORDER BY row);")"
check "an undo row keeps its restart command" "cd /tmp/orbit-api && mix phx.server" \
  "$(sqlite3 "$st_db" "SELECT json_extract(body, '\$.payload.restart.command') FROM rows WHERE subject=':4251 orbit-api';")"
# The body is what MMUndoRecord in Act reads: its own rid, a done state, a stop by the mode that did it.
check "an undo row's body has the shape Act's undo record reads" "legacy.locohost.1793115056.4251 done stop eager 1793115056" \
  "$(sqlite3 -separator ' ' "$st_db" "SELECT json_extract(body, '\$.rid'), json_extract(body, '\$.state'), json_extract(body, '\$.kind'), json_extract(body, '\$.by'), CAST(json_extract(body, '\$.at') AS INTEGER) FROM rows WHERE subject=':4251 orbit-api';")"
check "a stop the person asked for is by manual" manual \
  "$(sqlite3 "$st_db" "SELECT json_extract(body, '\$.by') FROM rows WHERE subject=':3001 acme-web';")"
check "each app MinMacs 1.2 quit becomes a relaunch row" "com.apple.Music|com.google.Chrome" \
  "$(sqlite3 "$st_db" "SELECT group_concat(subject, '|') FROM (SELECT subject FROM rows WHERE tbl='undo' AND expert='minmacs' ORDER BY row);")"
check "a relaunch row keeps its tabs" 2 \
  "$(sqlite3 "$st_db" "SELECT json_array_length(body, '\$.payload.relaunch.tabs') FROM rows WHERE subject='com.google.Chrome';")"
check "a relaunch row names its app for Act's restore" "com.google.Chrome quit done" \
  "$(sqlite3 -separator ' ' "$st_db" "SELECT json_extract(body, '\$.payload.relaunch.bundleID'), json_extract(body, '\$.kind'), json_extract(body, '\$.state') FROM rows WHERE subject='com.google.Chrome';")"
check "the last LocoHost review joins the review history" 1 "$(sqlite3 "$st_db" "SELECT COUNT(*) FROM rows WHERE tbl='review';")"
MINMACS_HOME="$st_new" "$st_bin" import "$st_old" >"$st_dir/import2.json"
check "a second import does nothing" "0 0 0" "$(json '"%d %d %d" % (len(j["prefs"]), len(j["files"]), len(j["rows"]))' <"$st_dir/import2.json")"
check "a second import adds no row" 5 "$(sqlite3 "$st_db" 'SELECT COUNT(*) FROM rows;')"
# A 2.0 file that exists already wins over the old one.
st_new2="$st_home/new2"; mkdir -p "$st_new2/locohost"
printf '{"protect.ports":[1]}' >"$st_new2/locohost/rules.json"
MINMACS_HOME="$st_new2" "$st_bin" import "$st_old" >/dev/null
check "an existing 2.0 file is left as it is" 1 "$(json 'j["protect.ports"][0]' <"$st_new2/locohost/rules.json")"
MINMACS_HOME="$st_new2" "$st_bin" import "$st_dir/no-such-home" >"$st_dir/import3.json"
check "a home with no old apps plans nothing" 0 "$(json 'len(j["sources"])' <"$st_dir/import3.json")"

# The Settings window: its controls, then its panes through the render tool, in light, dark and Increase Contrast.
if clang -fobjc-arc -Wall -mmacosx-version-min=14.0 -ISources -framework Cocoa \
     $(find Sources/UI -name '*.m' | LC_ALL=C sort) Sources/Core/MMSpecs.m test/store/settings.m -o "$st_dir/settings" >"$st_dir/settings.log" 2>&1; then
  check "test/store/settings.m builds with no warnings" 0 "$(grep -c "warning:" "$st_dir/settings.log")"
  "$st_dir/settings" >"$st_dir/settings.out" 2>&1
  check "test/store/settings.m runs" 0 "$?"
  while IFS="$st_tab" read -r st_n st_w st_g; do check "$st_n" "$st_w" "$st_g"; done <"$st_dir/settings.out"
else
  check "test/store/settings.m builds" 0 1
  cat "$st_dir/settings.log"
fi
st_out="$ROOT/build/render"
BUILD_DIR="$st_dir/render" "$ROOT/tools/render.sh" "$st_out" >"$st_dir/render.log" 2>&1
check "tools/render.sh renders the Settings panes" 0 "$?"
st_ok=yes
for st_p in overview experts general insomnia; do for st_m in light dark contrast-light contrast-dark; do
  [ -s "$st_out/settings/settings-$st_p-$st_m.png" ] || st_ok=no
done; done
check "each Settings pane in light, dark and Increase Contrast" yes "$st_ok"
check "the Settings panes have the window's width" "1080 " \
  "$(for f in "$st_out"/settings/*.png; do sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/ {print $2}'; done | sort -u | tr '\n' ' ')"
check "the render's Settings checks all pass" "0 13" \
  "$(grep -c '^FAIL  settings' "$st_out/checks.txt") $(grep -c '^ok    settings' "$st_out/checks.txt")"

check "the person's own prefs file was not touched" "$st_real_before" "$(stat -f '%m %z' "$st_real_prefs" 2>/dev/null || echo none)"
# ===== end of Store =====
