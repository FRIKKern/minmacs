# ===== Migration from the five old apps, issue #37 and PLAN.md section 8 =====
# Sourced by test.sh after core. Builds test/migrate/tool.m with Core, the kit and the CLI under -DMM_TESTS.
# Fixtures only, all inside $MINMACS_HOME:
#   an old home with copies of the old apps' prefs and state files, a fixture repo for WorkForest's removed
#   worktree, Noo-Noo's store.db made with sqlite3, its LaunchAgent plist, and four app bundles with Info.plist only
#   test/migrate/fakecmd.sh in place of sudo, pmset and launchctl, and a fake power source and agent status
# A variable set in front of a shell function stays set after it in sh, so those runs sit in a subshell.
# Every tool run sits in a sandbox that refuses to read or write the real old apps' prefs, state files, LaunchAgent
# and apps, and the person's Trash, so a read that missed the fixture home fails instead of reading the real one.
# The only process this section starts is the restart command of one imported stop, which touches a file and exits.

mg_dir=$(cd "$MINMACS_HOME" && mkdir -p "migrate$$" && cd "migrate$$" && pwd -P)
mg_old="$mg_dir/old"
mg_tool="$mg_dir/tool"
mg_run_id=$$
mg_saved_home="$MINMACS_HOME"
mg_tab=$(printf '\t')

mg_cc="clang -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -DMM_TESTS -ISources"
# shellcheck disable=SC2086
$mg_cc $(find Sources/Core Sources/UI Sources/CLI -name '*.m' | LC_ALL=C sort) test/migrate/tool.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -framework QuartzCore -lsqlite3 \
  -o "$mg_tool" >"$mg_dir/build.log" 2>&1
mg_r=$?
check "migrate: the test tool builds" 0 "$mg_r"
check "migrate: Core builds with no warnings under -Wextra" 0 "$(grep -c 'warning:' "$mg_dir/build.log")"
[ "$mg_r" = 0 ] || tail -20 "$mg_dir/build.log"

# ----- The sandbox around every tool run -----
# The real paths are named from $HOME at run time. The tool may not read or write any of them.
mg_real_files="$HOME/Library/Preferences/no.guerrilla.locohost.plist $HOME/Library/Preferences/no.guerrilla.workforest.plist
$HOME/Library/Preferences/no.guerrilla.insomnia.plist $HOME/Library/Preferences/io.noo-noo.app.plist
$HOME/Library/LaunchAgents/io.noo-noo.d.plist"
mg_real_dirs="$HOME/Library/Application Support/LocoHost|$HOME/Library/Application Support/WorkForest|$HOME/Library/Application Support/noo-noo|$HOME/Library/Application Support/MinMacs|$HOME/.config/noo-noo|$HOME/.Trash|/Applications/LocoHost.app|/Applications/WorkForest.app|/Applications/Insomnia.app|/Applications/Noo-Noo.app|$HOME/Applications/LocoHost.app|$HOME/Applications/WorkForest.app|$HOME/Applications/Insomnia.app|$HOME/Applications/Noo-Noo.app|$mg_dir/denied"
mg_profile="(version 1)(allow default)"
for f in $mg_real_files; do mg_profile="$mg_profile(deny file-read-data file-write* (literal \"$f\"))"; done
mg_ifs=$IFS; IFS='|'
for d in $mg_real_dirs; do mg_profile="$mg_profile(deny file-read-data file-write* (subpath \"$d\"))"; done
IFS=$mg_ifs
mg() { MINMACS_HOME="$mg_home" MINMACS_INSOMNIA_CMD="$ROOT/test/migrate/fakecmd.sh" MINMACS_LAUNCHCTL_CMD="$ROOT/test/migrate/fakecmd.sh" \
  sandbox-exec -p "$mg_profile" "$mg_tool" "$@"; }

mkdir -p "$mg_dir/denied"; echo probe >"$mg_dir/denied/probe"
mg_home="$mg_dir/probe-home"; mkdir -p "$mg_home"
check "migrate: the sandbox refuses a denied file" no "$(mg readable "$mg_dir/denied/probe" 2>/dev/null)"
check "migrate: and allows a fixture file" yes "$(mg readable "$ROOT/test/migrate/fakecmd.sh" 2>/dev/null)"

# ----- The old home -----
mg_git() { git -c user.name=Fixture -c user.email=fixture@example.com -c commit.gpgsign=false -c init.defaultBranch=main \
  -c advice.detachedHead=false "$@" >/dev/null 2>&1; }
mg_lib="$mg_old/Library"
mkdir -p "$mg_lib/Preferences" "$mg_lib/Application Support/LocoHost" "$mg_lib/Application Support/WorkForest" \
  "$mg_lib/Application Support/noo-noo" "$mg_lib/LaunchAgents" "$mg_old/.config/noo-noo" "$mg_old/Applications"
cp test/migrate/legacy/prefs/*.plist "$mg_lib/Preferences/"
cp test/migrate/legacy/locohost/rules.json "$mg_lib/Application Support/LocoHost/"
cp test/migrate/legacy/workforest/*.json "$mg_lib/Application Support/WorkForest/"
cp test/migrate/legacy/noonoo/config.toml "$mg_old/.config/noo-noo/"
# LocoHost's closed.json: one stop whose restart command touches a file inside the fixture folder.
mg_restarted="$mg_dir/restarted-$mg_run_id"
printf '[{"at": 1793115056, "port": 4251, "project": "orbit-api", "restart": "touch %s", "by": "Eager", "why": "quiet 1h"}]\n' \
  "$mg_restarted" >"$mg_lib/Application Support/LocoHost/closed.json"
# WorkForest 0.1's removed.json: a worktree that 0.1 removed, with the .env it saved, from a fixture repo.
mg_repo="$mg_dir/repo"; mg_wt="$mg_dir/wt-feature"
mg_git init -q "$mg_repo"
( cd "$mg_repo" && printf '.env\n' >.gitignore && echo one >a.txt && mg_git add -A && mg_git commit -qm first )
mg_git -C "$mg_repo" worktree add -q -b feature "$mg_wt"
( cd "$mg_wt" && echo two >b.txt && mg_git add -A && mg_git commit -qm second )
mg_head=$(git -C "$mg_wt" rev-parse HEAD)
mg_git -C "$mg_repo" worktree remove "$mg_wt"
mkdir -p "$mg_lib/Application Support/WorkForest/removed/wf01/files"
echo "SECRET=fixture" >"$mg_lib/Application Support/WorkForest/removed/wf01/files/.env"
printf '[{"id": "wf01", "path": "%s", "repo": "%s", "branch": "feature", "head": "%s", "merged": "no", "at": 1793100000, "by": "you", "why": "done", "saved": [".env"], "skipped": [], "diskBytes": 1000, "branchDeleted": false}]\n' \
  "$mg_wt" "$mg_repo" "$mg_head" >"$mg_lib/Application Support/WorkForest/removed.json"
# Noo-Noo's store.db, two of its tables as schema.sql makes them.
sqlite3 "$mg_lib/Application Support/noo-noo/store.db" <<'SQL'
CREATE TABLE actions (id INTEGER PRIMARY KEY AUTOINCREMENT, ts DATETIME NOT NULL, module TEXT NOT NULL, op TEXT NOT NULL,
  target TEXT NOT NULL, size_bytes INTEGER NOT NULL DEFAULT 0, evidence_json TEXT NOT NULL DEFAULT '{}', outcome TEXT NOT NULL);
CREATE TABLE auto_clean_events (id INTEGER PRIMARY KEY AUTOINCREMENT, started_at_unix INTEGER NOT NULL, ended_at_unix INTEGER,
  trigger TEXT NOT NULL, outcome TEXT NOT NULL, skip_reason TEXT, target_path TEXT NOT NULL, module TEXT NOT NULL,
  target_size_bytes INTEGER NOT NULL, freed_bytes INTEGER NOT NULL DEFAULT 0, idle_days_at_decision INTEGER NOT NULL DEFAULT 0,
  suggestion_id TEXT NOT NULL, error_msg TEXT);
INSERT INTO actions (ts, module, op, target, size_bytes, outcome) VALUES ('2026-05-02 03:00:00+00:00', 'clean', 'clean', '/tmp/nn-fixture/node_modules', 2048, 'accepted');
INSERT INTO actions (ts, module, op, target, size_bytes, outcome) VALUES ('2026-05-03 03:00:00+00:00', 'clean', 'clean', '/tmp/nn-fixture/dist', 1024, 'dry-run');
INSERT INTO auto_clean_events (started_at_unix, trigger, outcome, target_path, module, target_size_bytes, freed_bytes, suggestion_id)
  VALUES (1793000000, 'daily', 'deleted', '/tmp/nn-fixture/.next', 'dev', 4096, 4096, 's1');
SQL
# Noo-Noo's LaunchAgent, as its install writes it.
cat >"$mg_lib/LaunchAgents/io.noo-noo.d.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>io.noo-noo.d</string>
<key>ProgramArguments</key><array><string>/usr/local/bin/noo-nood</string></array></dict></plist>
PL
# Four old apps, and one with an old name that is another app: only the four are offered.
mg_app() {
  mkdir -p "$mg_old/Applications/$1.app/Contents"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string></dict></plist>\n' \
    "$2" >"$mg_old/Applications/$1.app/Contents/Info.plist"
}
mg_app LocoHost no.guerrilla.locohost; mg_app WorkForest no.guerrilla.workforest
mg_app Insomnia no.guerrilla.insomnia; mg_app Noo-Noo com.example.not-noo-noo
mg_sum() { (cd "$mg_old" && find . -type f ! -path './Applications/*' ! -path './Library/LaunchAgents/*' -print0 | LC_ALL=C sort -z | xargs -0 shasum | shasum | cut -d' ' -f1); }
mg_before=$(mg_sum)

# ----- The plan and the import -----
mg_home="$mg_dir/new"; mkdir -p "$mg_home"
mg plan "$mg_old" >"$mg_dir/plan.json" 2>"$mg_dir/plan.err"
check "migrate: the plan reads every old domain and file" 11 "$(json 'len(j["sources"])' <"$mg_dir/plan.json")"
check "migrate: the plan names each source it found" "insomnia,locohost,noonoo,workforest" "$(json '",".join(j["names"])' <"$mg_dir/plan.json")"
check "migrate: the plan writes nothing" 0 "$(find "$mg_home" -name '*.json' -o -name '*.sqlite' -o -name '*.plist' | grep -c .)"
mg import "$mg_old" >"$mg_dir/import.json" 2>"$mg_dir/import.err"
check "migrate: the import exits 0" 0 "$?"
check "migrate: the old files and prefs are unchanged" "$mg_before" "$(mg_sum)"
check "migrate: store.db gets no journal, WAL or shm file" 0 "$(ls "$mg_lib/Application Support/noo-noo" | grep -c -- '-')"
mg_pref() { /usr/libexec/PlistBuddy -c "Print :'$1'" "$mg_home/Preferences/no.guerrilla.minmacs.plist" 2>/dev/null; }
check "migrate: workforest.mode carries over" eager "$(mg_pref workforest.mode)"
check "migrate: workforest.reviewMinutes carries over" 90 "$(mg_pref workforest.reviewMinutes)"
check "migrate: workforest.model becomes review.model" sonnet "$(mg_pref review.model)"
check "migrate: WorkForest's fetch and CLI paths are left out" "" "$(mg_pref workforest.fetch)$(mg_pref workforest.claudePath)"
check "migrate: WorkForest's visible icon stays visible" true "$(mg_pref 'NSStatusItem Visible minmacs.workforest')"
check "migrate: Insomnia's lid mode carries over" true "$(mg_pref insomnia.lid)"
check "migrate: insomnia.lid.minBattery carries over" 30 "$(mg_pref insomnia.lid.minBattery)"
check "migrate: insomnia.lid.screenOff carries over" false "$(mg_pref insomnia.lid.screenOff)"
check "migrate: Insomnia's debug prefs, clocks and update check stay out" "" \
  "$(mg_pref insomnia.debug.lid)$(mg_pref insomnia.unpluggedAt)$(mg_pref insomnia.updateCheckedAt)"
check "migrate: Insomnia's hidden icon stays hidden" false "$(mg_pref 'NSStatusItem Visible minmacs.insomnia')"
check "migrate: Noo-Noo's hidden icon stays hidden" false "$(mg_pref 'NSStatusItem Visible minmacs.noonoo')"
check "migrate: LocoHost's hidden icon stays hidden" false "$(mg_pref 'NSStatusItem Visible minmacs.locohost')"
check "migrate: auto_clean off makes Noo-Noo idle" idle "$(mg_pref noonoo.mode)"
check "migrate: WorkForest's protect.paths becomes protect" "~/work/keep-this" "$(json '",".join(j["protect"])' <"$mg_home/workforest/rules.json")"
check "migrate: protect.branches keeps the person's own" "main,release-train" "$(json '",".join(j["protect.branches"])' <"$mg_home/workforest/rules.json")"
check "migrate: ignore.paths becomes ignore, caches stay" "~/work/scratch node_modules,.next" \
  "$(json '",".join(j["ignore"])+" "+",".join(j["caches"])' <"$mg_home/workforest/rules.json")"
check "migrate: WorkForest's and Noo-Noo's roots join the core rules" "~/code,~/Documents/GitHub,~/conductor/workspaces,~/work/forest-root" \
  "$(json '",".join(j["roots"])' <"$mg_home/core/rules.json")"
check "migrate: config.toml is kept whole" "45 524288000 2.5 ~/Library/Caches two" \
  "$(json '"%s %s %s %s %s" % (j["heuristics"]["idle_repos"]["min_idle_days"], j["heuristics"]["idle_repos"]["min_node_modules_bytes"], j["heuristics"]["cache_velocity"]["growth_multiplier"], j["scan"]["cache_roots"][0], j["offload"]["inline"]["b"])' <"$mg_home/noonoo/legacy-config.json")"
check "migrate: a comment inside an array is no value" "~/code,~/Documents/GitHub" "$(json '",".join(j["scan"]["roots"])' <"$mg_home/noonoo/legacy-config.json")"
mg_db="$mg_home/minmacs.sqlite"
check "migrate: Noo-Noo's actions and auto cleans join the log as history" "3 0" \
  "$(sqlite3 -separator ' ' "$mg_db" "SELECT (SELECT COUNT(*) FROM rows WHERE tbl='legacy' AND expert='noonoo'), (SELECT COUNT(*) FROM rows WHERE tbl='undo' AND expert='noonoo');")"
check "migrate: a history row keeps its time and outcome" "1777690800 accepted" \
  "$(sqlite3 -separator ' ' "$mg_db" "SELECT CAST(json_extract(body, '\$.at') AS INTEGER), state FROM rows WHERE rid='legacy.noonoo.action.1';")"
check "migrate: the last WorkForest review joins the review history" 1 "$(sqlite3 "$mg_db" "SELECT COUNT(*) FROM rows WHERE tbl='review' AND expert='workforest';")"
check "migrate: the WorkForest removal becomes an undo row" "remove done manual" \
  "$(sqlite3 -separator ' ' "$mg_db" "SELECT json_extract(body, '\$.kind'), state, json_extract(body, '\$.by') FROM rows WHERE rid='legacy.workforest.wf01';")"
check "migrate: the expert's own import will skip it" legacy.workforest.wf01 "$(json 'j["wf01"]' <"$mg_home/workforest/legacy-removed.json")"
check "migrate: the LocoHost stop becomes an undo row" "stop eager" \
  "$(sqlite3 -separator ' ' "$mg_db" "SELECT json_extract(body, '\$.kind'), json_extract(body, '\$.by') FROM rows WHERE rid='legacy.locohost.1793115056.4251';")"
mg_marks=$(/usr/libexec/PlistBuddy -c "Print :core.migrated" "$mg_home/Preferences/no.guerrilla.minmacs.plist" 2>/dev/null | grep -c ' = ')
check "migrate: each source is recorded" 4 "$mg_marks"

# ----- Every old restore record restores through MMUndo -----
check "migrate: the LocoHost record can restore" "stop True" "$(mg record legacy.locohost.1793115056.4251 | json '"%s %s" % (j["kind"], j["canRestore"])')"
check "migrate: restore of the LocoHost stop runs its command" ok "$(mg restore legacy.locohost.1793115056.4251)"
mg_i=0; while [ ! -e "$mg_restarted" ] && [ $mg_i -lt 100 ]; do sleep 0.1; mg_i=$((mg_i+1)); done
check "migrate: and the server's command ran" yes "$([ -e "$mg_restarted" ] && echo yes || echo no)"
check "migrate: restore of the WorkForest removal" ok "$(mg restore legacy.workforest.wf01)"
check "migrate: the worktree is back at its commit" "$mg_head" "$(git -C "$mg_wt" rev-parse HEAD 2>/dev/null)"
check "migrate: with the .env 0.1 saved" "SECRET=fixture" "$(cat "$mg_wt/.env" 2>/dev/null)"
check "migrate: and 0.1's copy stays where it was" yes "$([ -f "$mg_lib/Application Support/WorkForest/removed/wf01/files/.env" ] && echo yes || echo no)"
check "migrate: the record is restored" restored "$(mg record legacy.workforest.wf01 | json 'j["state"]')"

# ----- The follow-up: the lid, the LaunchAgent and the old apps -----
mkdir -p "$mg_home/migrate-fake"; echo 1 >"$mg_home/migrate-fake/lid"
(MIGRATE_AGENT_STATUS=1 mg followup "$mg_old" yes "$mg_dir/asked.log") >"$mg_dir/follow.json" 2>"$mg_dir/follow.err"
check "migrate: the follow-up exits 0" 0 "$?"
check "migrate: a live lid override the old lid mode set goes off" off "$(json 'j["insomnia.lid"]["state"]' <"$mg_dir/follow.json")"
check "migrate: through the one pmset command, and nothing touches the sudoers rule" "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0" \
  "$(grep -v launchctl "$mg_home/migrate-fake/log")"
mg_lidrid=$(json 'j["insomnia.lid"]["rid"]' <"$mg_dir/follow.json")
check "migrate: the lid write has an undo record" "lid insomnia done guard" "$(mg record "$mg_lidrid" | json '"%s %s %s %s" % (j["kind"], j["expert"], j["state"], j["by"])')"
check "migrate: one confirm for the agent and one for the apps" 2 "$(grep -c . "$mg_dir/asked.log")"
check "migrate: the agent's status comes from SMAppService" 1 "$(json 'j["noonoo.agent"]["status"]' <"$mg_dir/follow.json")"
check "migrate: on yes the agent is stopped with launchctl bootout" "/bin/launchctl bootout gui/$(id -u) $mg_lib/LaunchAgents/io.noo-noo.d.plist" \
  "$(grep launchctl "$mg_home/migrate-fake/log")"
check "migrate: and its plist goes to the test Trash" "no yes" \
  "$([ -e "$mg_lib/LaunchAgents/io.noo-noo.d.plist" ] && echo yes || echo no) $(ls "$mg_home/Trash" 2>/dev/null | grep -q 'io.noo-noo.d' && echo yes || echo no)"
check "migrate: the apps confirm names the old apps" "Move the Old Apps to the Trash?" "$(sed -n 2p "$mg_dir/asked.log" | cut -f1)"
check "migrate: and only the three with their own bundle id" "Insomnia,LocoHost,WorkForest" \
  "$(json '",".join(sorted(a["name"] for a in j["apps"]))' <"$mg_dir/follow.json")"
check "migrate: each goes to the test Trash" "trashed trashed trashed" "$(json '" ".join(a["state"] for a in j["apps"])' <"$mg_dir/follow.json")"
check "migrate: the app with another bundle id stays" yes "$([ -d "$mg_old/Applications/Noo-Noo.app" ] && echo yes || echo no)"
check "migrate: the follow-up writes no error" "" "$(cat "$mg_dir/follow.err")"
mg_ok=""
for mg_rid in $(json '" ".join(a["rid"] for a in j["apps"])' <"$mg_dir/follow.json"); do mg_ok="$mg_ok $(mg restore "$mg_rid")"; done
check "migrate: restore puts each app back" " ok ok ok" "$mg_ok"
check "migrate: the three apps are back" "yes yes yes" "$(for a in LocoHost WorkForest Insomnia; do [ -f "$mg_old/Applications/$a.app/Contents/Info.plist" ] && echo yes || echo no; done | xargs)"
mg_agentrid=$(json 'j["noonoo.agent"]["rid"]' <"$mg_dir/follow.json")
check "migrate: restore puts the agent's plist back" ok "$(mg restore "$mg_agentrid")"
check "migrate: the plist is back" yes "$([ -f "$mg_lib/LaunchAgents/io.noo-noo.d.plist" ] && echo yes || echo no)"
check "migrate: the old files and prefs are still unchanged" "$mg_before" "$(mg_sum)"

# ----- A second launch does nothing -----
cp "$mg_home/migrate-fake/log" "$mg_dir/log.before"
echo 1 >"$mg_home/migrate-fake/lid"
mg_rows=$(sqlite3 "$mg_db" 'SELECT COUNT(*) FROM rows;')
mg import "$mg_old" >"$mg_dir/import2.json" 2>/dev/null
check "migrate: a second import plans nothing" "0 0 0 0" "$(json '"%d %d %d %d" % (len(j["prefs"]), len(j["files"]), len(j["rows"]), len(j["sources"]))' <"$mg_dir/import2.json")"
(MIGRATE_AGENT_STATUS=1 mg followup "$mg_old" yes "$mg_dir/asked.log") >"$mg_dir/follow2.json" 2>/dev/null
check "migrate: a second follow-up asks nothing" "2 []" "$(grep -c . "$mg_dir/asked.log") $(json 'json.dumps(j["asked"])' <"$mg_dir/follow2.json")"
check "migrate: and writes no lid override, even with it on" "" "$(diff "$mg_dir/log.before" "$mg_home/migrate-fake/log")"
check "migrate: and does not touch the agent or the apps again" "yes yes" \
  "$([ -f "$mg_lib/LaunchAgents/io.noo-noo.d.plist" ] && echo yes || echo no) $([ -d "$mg_old/Applications/LocoHost.app" ] && echo yes || echo no)"
check "migrate: and adds no log row" "$mg_rows" "$(sqlite3 "$mg_db" 'SELECT COUNT(*) FROM rows;')"

# ----- No: the person keeps the agent and the apps, and is not asked again -----
mg_home="$mg_dir/new-no"; mkdir -p "$mg_home/migrate-fake"; echo 0 >"$mg_home/migrate-fake/lid"
: >"$mg_dir/asked-no.log"
mg import "$mg_old" >/dev/null 2>&1
(MIGRATE_AGENT_STATUS=2 mg followup "$mg_old" no "$mg_dir/asked-no.log") >"$mg_dir/follow-no.json" 2>/dev/null
check "migrate: an override that is already off is left alone" "already off" "$(json 'j["insomnia.lid"]["state"]' <"$mg_dir/follow-no.json")"
check "migrate: and no lid command runs" no "$([ -s "$mg_home/migrate-fake/log" ] && echo yes || echo no)"
check "migrate: on no the agent and the apps stay" "kept kept,kept,kept" \
  "$(json 'j["noonoo.agent"]["state"] + " " + ",".join(a["state"] for a in j["apps"])' <"$mg_dir/follow-no.json")"
check "migrate: the LocoHost and Insomnia apps are still there" "yes yes" \
  "$([ -d "$mg_old/Applications/LocoHost.app" ] && echo yes || echo no) $([ -d "$mg_old/Applications/Insomnia.app" ] && echo yes || echo no)"
(MIGRATE_AGENT_STATUS=2 mg followup "$mg_old" yes "$mg_dir/asked-no.log") >/dev/null 2>&1
check "migrate: no is asked once too" 2 "$(grep -c . "$mg_dir/asked-no.log")"

# ----- A lid the old lid mode never set, and a failed write -----
mg_home="$mg_dir/new-other"; mkdir -p "$mg_home/migrate-fake" "$mg_dir/other/Library/Preferences"; echo 1 >"$mg_home/migrate-fake/lid"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>insomnia.lid</key><false/></dict></plist>\n' \
  >"$mg_dir/other/Library/Preferences/no.guerrilla.insomnia.plist"
mg followup "$mg_dir/other" no >"$mg_dir/follow-other.json" 2>/dev/null
check "migrate: an override another tool set stays on" "lid mode was off 1" \
  "$(json 'j["insomnia.lid"]["state"]' <"$mg_dir/follow-other.json") $(cat "$mg_home/migrate-fake/lid")"
mg_home="$mg_dir/new-runs"; mkdir -p "$mg_home/migrate-fake"; echo 1 >"$mg_home/migrate-fake/lid"
mkdir -p "$mg_dir/lid-home/Library/Preferences"; cp test/migrate/legacy/prefs/no.guerrilla.insomnia.plist "$mg_dir/lid-home/Library/Preferences/"
(MIGRATE_RUNNING=no.guerrilla.insomnia mg followup "$mg_dir/lid-home" no) >"$mg_dir/follow-runs.json" 2>/dev/null
check "migrate: while Insomnia.app runs it keeps its override" "waits 1" \
  "$(json 'j["insomnia.lid"]["state"]' <"$mg_dir/follow-runs.json") $(cat "$mg_home/migrate-fake/lid")"
mg_home="$mg_dir/new-fail"; mkdir -p "$mg_home/migrate-fake"; echo 1 >"$mg_home/migrate-fake/lid"; touch "$mg_home/migrate-fake/fail"
mg followup "$mg_dir/lid-home" no >"$mg_dir/follow-fail.json" 2>/dev/null
check "migrate: a refused write waits for the next launch" waits "$(json 'j["insomnia.lid"]["state"]' <"$mg_dir/follow-fail.json")"
rm -f "$mg_home/migrate-fake/fail"
mg followup "$mg_dir/lid-home" no >"$mg_dir/follow-fail2.json" 2>/dev/null
check "migrate: and the next launch turns it off" off "$(json 'j["insomnia.lid"]["state"]' <"$mg_dir/follow-fail2.json")"

# ----- The app -----
mg_home="$mg_dir/probe-home"
check "migrate: only the real app migrates, never a test home" "no no no" "$(mg wanted)"
check "migrate: Info.plist adds the insomnia scheme" insomnia \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:2' "$APP/Contents/Info.plist" 2>/dev/null)"
check "migrate: insomnia:// goes to the Insomnia expert" "expert insomnia" "$(mg route 'insomnia://lid-off')"
check "migrate: the shell runs the follow-up off main" 1 "$(grep -c 'MMMigrateFollowUp(nil' Sources/Shell/MMShell.m)"
check "migrate: the shell skips it in a test home and headless" 1 "$(grep -c '!self.headless && MMMigrateWanted' Sources/Shell/MMShell.m)"
check "migrate: nothing in the migration deletes a file for good" 0 \
  "$(grep -nE 'removeItemAt|unlink\(|rmdir\(|emptyTrash|rm -rf' Sources/Core/Store/MMMigrate.m | grep -c .)"
check "migrate: the release binary has no agent status fake" 0 "$(nm "$BIN" 2>/dev/null | grep -c MMUseNooNooAgentStatus)"

MINMACS_HOME="$mg_saved_home"
