# ===== Shell: the app shell, the CLI verbs, core.sock and the old names, issue #20 =====
# Sourced by test.sh after core. It builds test/shell/fixture.m with every .m under Sources except main.m:
# the real CLI, router and shell, with two fixture experts in place of MinMacs and LocoHost and facts made by hand.
# Every verb runs against those experts, cold and through core.sock. The fixture binary and the listener carry
# this run's pid in their names, so no other run can match them. Nothing here opens the app or a status item.

# A support folder of its own, so undo rows other sections wrote never reach these counts.
sh_top="$MINMACS_HOME"
sh_dir="$MINMACS_HOME/shell"
mkdir -p "$sh_dir/bin" "$sh_dir/home"
export MINMACS_HOME="$sh_dir/home"
sh_tag="mmshell$$"
sh_fx="$sh_dir/bin/$sh_tag"
sh_tab=$(printf '\t')
sh_cc="clang -fobjc-arc -O0 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -ISources -DMM_VERSION=\"2.0.0\""
sh_fw="-framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3"
# shellcheck disable=SC2086
$sh_cc $sh_fw $(find Sources -name '*.m' ! -path Sources/main.m ! -path 'Sources/Experts/*' | LC_ALL=C sort) test/shell/fixture.m -o "$sh_fx" >"$sh_dir/build.log" 2>&1
check "shell: the fixture binary builds" 0 "$?"
check "shell: Sources and the fixture have no warnings under -Wextra" 0 "$(grep -c 'warning:' "$sh_dir/build.log")"
clang -O1 -Wall -Werror test/shell/listener.c -o "$sh_dir/bin/${sh_tag}-listen" >>"$sh_dir/build.log" 2>&1
check "shell: the fixture listener builds" 0 "$?"

# Every fixture run starts cold, so no running MinMacs on this Mac can answer. MINMACS_HOME keeps core.sock here.
fx() { "$sh_fx" "$@"; }
mkdir -p "$MINMACS_HOME/fx/app/web" "$MINMACS_HOME/fx/old"
jq_() { python3 -c "import json,sys; j=json.load(sys.stdin); print($1)" 2>/dev/null; }

# The checks the fixture binary runs on the router, the legacy names and the login item guard.
fx _selftest >"$sh_dir/self.txt" 2>&1
check "shell: _selftest runs" 0 "$?"
while IFS="$sh_tab" read -r sh_n sh_w sh_g; do check "shell: $sh_n" "$sh_w" "$sh_g"; done <"$sh_dir/self.txt"

echo "  -- cold, no app"
check "status --json reads cold" "False 2" "$(fx status --json | jq_ 'j["app"], len(j["experts"])' | tr '\n' ' ' | sed 's/ $//')"
check "status --json has each expert's header" "1 apps|2 servers" "$(fx status --json | jq_ '"|".join(e["header"] for e in j["experts"])')"
check "status --json has the badge and the label state" "1 1 idle server" "$(fx status --json | jq_ 'j["experts"][1]["badge"] + " " + j["experts"][1]["state"]')"
check "status prints one line per expert" 3 "$(fx status | wc -l | tr -d ' ')"
check "hosts --json lists the fixture servers" "Vite :3000,Vite :3001" "$(fx hosts --json | jq_ '",".join(h["title"] for h in j["hosts"])')"
check "hosts 3001 explains one port" "Vite :3001" "$(fx hosts 3001)"
fx hosts 9 >/dev/null 2>&1
check "hosts on a free port exits 1" 1 "$?"
check "apps --json lists the fixture app" "Notes" "$(fx apps --json | jq_ 'j["apps"][0]["title"]')"
check "work --json finds the one workstream" "1 working" "$(fx work --json | jq_ 'len(j["workstreams"]), j["workstreams"][0]["agentState"]' | tr '\n' ' ' | sed 's/ $//')"
check "work --here inside the worktree answers for that server" "Vite :3000" \
  "$(cd "$MINMACS_HOME/fx/app" && "$sh_fx" work --here --json | jq_ '",".join(f["title"] for f in j["workstream"]["findings"])')"
check "work --here outside every workstream says null" "None" "$(cd "$MINMACS_HOME/fx" && "$sh_fx" work --here --json | jq_ 'j["workstream"]')"
check "review before any review says so" "LocoHost    no review yet" "$(fx review locohost)"
check "_review saves a fixture review" saved "$(fx _review)"
check "review --json counts the verdicts in LocoHost's words" "1 1 proactive" \
  "$(fx review locohost --json | jq_ 'j["reviews"][0]["verdicts"]["idle"], j["reviews"][0]["verdicts"]["in_use"], j["reviews"][0]["mode"]' | tr '\n' ' ' | sed 's/ $//')"
fx review nosuch >/dev/null 2>&1
check "review of an unknown expert exits 2" 2 "$?"
fx review locohost --now >/dev/null 2>&1
check "review --now needs the app" 3 "$?"

# A day of watching has passed, so Proactive may act on what the review lets go.
echo $(( $(date +%s) - 200000 )) >"$MINMACS_HOME/watching-since"
check "tidy --dry-run --json acts on the idle server only" "Vite :3001 would stop :3001" \
  "$(fx tidy locohost --dry-run --json | jq_ '" ".join(e["title"] + " " + e["dryRun"] for e in j["experts"][0]["entries"] if e["act"])')"
check "tidy --dry-run keeps the server an agent uses" "an agent works here" \
  "$(fx tidy locohost --dry-run --json | jq_ '[e["why"] for e in j["experts"][0]["entries"] if not e["act"]][0]')"
fx tidy locohost >"$sh_dir/tidy.out" 2>"$sh_dir/tidy.err"
check "tidy without the app refuses with 3" 3 "$?"
check "the refusal says what to do" 1 "$(grep -c 'add --dry-run' "$sh_dir/tidy.err")"
check "the refusal stopped nothing" no "$([ -e "$MINMACS_HOME/fx/stopped-3001" ] && echo yes || echo no)"
fx close 3001 >/dev/null 2>&1
check "an expert verb that mutates refuses cold" 3 "$?"
check "an expert verb that mutates runs with --dry-run" "closed 3001" "$(fx close 3001 --dry-run)"
check "restore --list is empty at first" "0" "$(fx restore --list --json | jq_ 'len(j["records"])')"
check "mode locohost shows the mode" proactive "$(fx mode locohost)"
check "mode locohost eager --dry-run changes nothing" "eager proactive" "$(fx mode locohost eager --dry-run) $(fx mode locohost)"
check "mode locohost eager sets it" "eager" "$(fx mode locohost eager >/dev/null; fx mode locohost)"
fx mode locohost proactive >/dev/null
fx mode locohost loud >/dev/null 2>&1
check "mode with a bad name exits 2" 2 "$?"
check "help lists Core and expert verbs, none hidden" "yes no" \
  "$(fx help >"$sh_dir/help.txt"; grep -q '  hosts \[port\]' "$sh_dir/help.txt" && grep -q '  tidy ' "$sh_dir/help.txt" && echo yes || echo no) $(grep -c '_serve\|_walk\|_review' "$sh_dir/help.txt" | sed 's/^0$/no/')"
check "help --json lists every verb" "yes" "$(fx help --json | jq_ '"yes" if {"status","work","hosts","apps","review","tidy","where","restore"} <= {v["verb"] for v in j["verbs"]} else "no"')"
check "version --json" "2.0.0" "$(fx version --json | jq_ 'j["version"]')"
# With a time limit, so a regression that starts the app instead stops after 5 seconds.
check "-h is help, as in 1.x" 1 "$(perl -e 'alarm 5; exec @ARGV' "$sh_fx" -h | grep -c '^usage: ')"

echo "  -- old names"
ln -sf "$sh_fx" "$sh_dir/bin/locohost"
check "locohost list runs LocoHost's hosts" "hosts locohost" "$("$sh_dir/bin/locohost" list --json | jq_ '"hosts", j["program"]' | tr '\n' ' ' | sed 's/ $//')"
check "locohost list --json is minmacs hosts --json" "$(fx hosts --json | jq_ 'j["hosts"]')" "$("$sh_dir/bin/locohost" list --json | jq_ 'j["hosts"]')"
check "locohost explain 3000 explains one port" "Vite :3000" "$("$sh_dir/bin/locohost" explain 3000)"
check "locohost hosts is the 2.0 verb too" "Vite :3001" "$("$sh_dir/bin/locohost" hosts 3001)"
check "locohost idle is tidy locohost --dry-run" "Vite :3001" \
  "$("$sh_dir/bin/locohost" idle --json | jq_ '" ".join(e["title"] for e in j["experts"][0]["entries"] if e["act"])')"
fx mode locohost idle >/dev/null
check "locohost idle lists the confirmed idle server in Idle mode too, as 1.x did" "Vite :3001" \
  "$("$sh_dir/bin/locohost" idle --json | jq_ '" ".join(e["title"] for e in j["experts"][0]["entries"] if e["act"])')"
fx mode locohost proactive >/dev/null
"$sh_dir/bin/locohost" close-idle >/dev/null 2>&1
check "locohost close-idle needs the app, as tidy does" 3 "$?"
check "locohost mode is LocoHost's mode" proactive "$("$sh_dir/bin/locohost" mode)"
check "locohost stopped lists LocoHost's undo records" 0 "$("$sh_dir/bin/locohost" stopped --json | jq_ 'len(j["records"])')"
check "locohost help names the program" 1 "$("$sh_dir/bin/locohost" help | grep -c '^usage: locohost')"
check "MinMacs 1.x plan is tidy minmacs --dry-run" "minmacs" "$(fx plan --json | jq_ 'j["experts"][0]["expert"]')"
check "MinMacs 1.x agents is work" "1" "$(fx agents --json | jq_ 'j["workingAgents"]')"
fx run >/dev/null 2>&1
check "MinMacs 1.x run needs the app, as tidy does" 3 "$?"

echo "  -- through core.sock"
"$sh_fx" _serve >"$sh_dir/serve.out" 2>"$sh_dir/serve.err" &
sh_srv=$!; procs="$procs $sh_srv"
sh_i=0; while [ ! -S "$MINMACS_HOME/core.sock" ] && [ $sh_i -lt 50 ]; do sleep 0.1; sh_i=$((sh_i+1)); done
check "_serve makes core.sock" yes "$([ -S "$MINMACS_HOME/core.sock" ] && echo yes || echo no)"
check "core.sock has mode 600" 600 "$(stat -f %Lp "$MINMACS_HOME/core.sock" 2>/dev/null)"
"$sh_fx" _serve >/dev/null 2>"$sh_dir/serve2.err"
check "a second server is refused by the instance lock" "1 1" "$? $(grep -c 'instance lock' "$sh_dir/serve2.err")"
check "status --json now comes from the app" True "$(fx status --json | jq_ 'j["app"]')"
check "hosts --json from the app is the cold answer" "$(MINMACS_COLD=1 fx hosts --json | jq_ 'j["hosts"]')" "$(fx hosts --json | jq_ 'j["hosts"]')"
check "hosts --json ran in the app" True "$(fx hosts --json | jq_ 'j["inApp"]')"
check "MINMACS_COLD=1 skips the app" False "$(MINMACS_COLD=1 fx status --json | jq_ 'j["app"]')"
check "the app sees the CLI's folder" "Vite :3000" \
  "$(cd "$MINMACS_HOME/fx/app" && "$sh_fx" work --here --json | jq_ '",".join(f["title"] for f in j["workstream"]["findings"])')"
fx hosts 9 >/dev/null 2>"$sh_dir/hosts9.err"
check "an exit status and stderr come back from the app" "1 1" "$? $(grep -c 'nothing listens on :9' "$sh_dir/hosts9.err")"
fx nosuch >/dev/null 2>&1
check "an unknown verb still exits 2" 2 "$?"
# A hidden verb such as the worker never runs in the app, whoever asks. The CLI never sends one, so ask directly.
check "the app refuses a hidden verb over core.sock" "2 False" "$(python3 test/shell/ask.py "$MINMACS_HOME/core.sock" _walk)"
check "locohost list through the app" "Vite :3000,Vite :3001" "$("$sh_dir/bin/locohost" list --json | jq_ '",".join(h["title"] for h in j["hosts"])')"
check "review --now runs in the app" "locohost" "$(fx review locohost --now --json | jq_ '",".join(j["started"])')"
fx tidy locohost --json >"$sh_dir/tidy.json" 2>"$sh_dir/tidy.err"
check "tidy in the app exits 0" 0 "$?"
check "tidy stopped the idle server only" "yes no" \
  "$([ -e "$MINMACS_HOME/fx/stopped-3001" ] && echo yes || echo no) $([ -e "$MINMACS_HOME/fx/stopped-3000" ] && echo yes || echo no)"
sh_rid=$(jq_ '[e["rid"] for e in j["experts"][0]["entries"] if e.get("rid")][0]' <"$sh_dir/tidy.json")
check "tidy wrote an undo record by the CLI" "cli stop done" "$(fx restore --list --json | jq_ 'j["records"][0]["by"], j["records"][0]["kind"], j["records"][0]["state"]' | tr '\n' ' ' | sed 's/ $//')"
check "restore --dry-run names what it would restore" "Vite :3001 False" \
  "$(fx restore --dry-run --json | jq_ 'j["restored"][0]["subject"], "restored" in j["restored"][0]' | tr '\n' ' ' | sed 's/ $//')"
check "restore --dry-run restarted nothing" no "$([ -e "$MINMACS_HOME/fx/restarted-3001" ] && echo yes || echo no)"
check "restore undoes the last run" "True" "$(fx restore --json | jq_ 'j["restored"][0]["restored"]')"
sh_i=0; while [ ! -e "$MINMACS_HOME/fx/restarted-3001" ] && [ $sh_i -lt 50 ]; do sleep 0.1; sh_i=$((sh_i+1)); done
check "restore ran the record's restart command" restarted "$(cat "$MINMACS_HOME/fx/restarted-3001" 2>/dev/null)"
check "the record is restored" restored "$(fx restore --list --json | jq_ 'j["records"][0]["state"]')"
fx restore "$sh_rid" >/dev/null 2>&1
check "restoring it again fails" 1 "$?"
check "restore with nothing left says so" "Nothing to restore." "$(fx restore)"
kill "$sh_srv" 2>/dev/null; wait "$sh_srv" 2>/dev/null
check "with the app gone the CLI runs cold again" False "$(fx status --json | jq_ 'j["app"]')"

echo "  -- the real binary, cold"
# Where asks cmux and tmux through their CLIs. Fakes that answer nothing keep this Mac's own sessions out.
export MINMACS_CMUX=/usr/bin/false MINMACS_TMUX=/usr/bin/false
check "minmacs version through the bundle" "MinMacs 2.0.0 (phase 1)" "$("$BIN" version)"
# One expert per folder under Sources/Experts that holds code.
sh_linked=$(ls Sources/Experts/*/*.m 2>/dev/null | xargs -n1 dirname | sort -u | wc -l | tr -d ' ')
check "minmacs status lists the linked experts" "$sh_linked" "$("$BIN" status --json | jq_ 'len(j["experts"])')"
check "minmacs status --json is JSON" False "$("$BIN" status --json | jq_ 'j["app"]')"
check "minmacs work --json is JSON" yes "$("$BIN" work --json | jq_ '"yes" if "workstreams" in j else "no"')"
check "minmacs restore --list reads the undo log the fixture wrote" "restored" "$("$BIN" restore --list --json | jq_ 'j["records"][0]["state"]')"
check "minmacs tidy --dry-run changes nothing" "Dry run. Nothing was changed." "$("$BIN" tidy --dry-run | tail -1)"
"$BIN" hosts >/dev/null 2>&1
check "hosts runs with the LocoHost expert linked" 0 "$?"
ln -sf "$BIN" "$sh_dir/bin/locohost-real"; ln -sf "$BIN" "$sh_dir/bin/locohost"
check "a locohost symlink to the bundle runs as locohost" 1 "$("$sh_dir/bin/locohost" help | grep -c '^usage: locohost')"
rm -f "$sh_dir/bin/locohost" "$sh_dir/bin/locohost-real"
# A fixture listener on a high port this run picks. where finds its pid by the socket table of one cold sample.
sh_port=""; sh_l=""
for sh_try in 0 1 2 3 4 5 6 7; do
  sh_p=$(( 40000 + ($$ * 7 + sh_try * 131) % 20000 ))
  "$sh_dir/bin/${sh_tag}-listen" "$sh_p" & sh_l=$!
  sleep 0.3
  if kill -0 "$sh_l" 2>/dev/null; then sh_port=$sh_p; procs="$procs $sh_l"; break; fi
done
check "the fixture listener holds a high port" yes "$([ -n "$sh_port" ] && echo yes || echo no)"
check "where --port finds the listener's pid" "$sh_l" "$("$BIN" where --port "$sh_port" --json | jq_ 'j["pid"]')"
check "where :port is the same" "$sh_l" "$("$BIN" where ":$sh_port" --json | jq_ 'j["pid"]')"
check "where <pid> names the process" "$(printf %s "${sh_tag}-listen" | cut -c1-15)" "$("$BIN" where "$sh_l" --json | jq_ 'j["name"]' | cut -c1-15)"
"$BIN" where --port 9 >/dev/null 2>&1
check "where on a port nobody holds exits 1" 1 "$?"
"$BIN" where >/dev/null 2>&1
check "where with no pid exits 2" 2 "$?"
kill "$sh_l" 2>/dev/null; wait "$sh_l" 2>/dev/null
unset MINMACS_CMUX MINMACS_TMUX

check "Info.plist keeps the minmacs scheme" minmacs "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$APP/Contents/Info.plist" 2>/dev/null)"
check "Info.plist adds the locohost scheme" locohost "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:1' "$APP/Contents/Info.plist" 2>/dev/null)"
check "no status item is made outside Sources/Shell and Sources/UI" 0 \
  "$(grep -rln 'statusItemWithLength' Sources | grep -v '^Sources/UI/' | grep -v '^Sources/Shell/' | grep -c .)"
check "SMAppService registers only behind MMMayRegisterLoginItem" 2 \
  "$(grep -c 'MMMayRegisterLoginItem(NSProcessInfo' Sources/Shell/MMShell.m)"

echo "  -- legacy fix #48: registry rows"
check "registry rows pass the validator" 0 "$(python3 tools/validate_row.py registry/agents/*.json >/dev/null 2>&1; echo $?)"
# Every working signal a row declares must be one that both detectors evaluate, as test.sh on legacy checks.
sh_unread=$(python3 - <<'PY'
import glob, json, re
cli = set(re.findall(r'isEqualToString:@"(\w+)"', open("Sources/Core/Know/MMRegistry.m").read()))
ref = set(re.findall(r'kind == "(\w+)"', open("tools/agents_probe.py").read()))
used = {s["signal"] for f in glob.glob("registry/agents/*.json") + glob.glob("tools/fixtures/**/*.json", recursive=True)
        for s in json.load(open(f)).get("working_signals", [])}
print(" ".join(sorted(used - (cli & ref))) or "none")
PY
)
check "no row declares a signal the detectors ignore" none "$sh_unread"

echo "  -- menus drawn from specs"
BUILD_DIR="$sh_dir/render-build" tools/render.sh "$sh_dir/render" >"$sh_dir/render.log" 2>&1
check "the render tool draws the shell's subjects" 0 "$?"
check "every shell PNG is there, in four appearances" 28 "$(ls "$sh_dir/render/shell/"*.png 2>/dev/null | wc -l | tr -d ' ')"
check "the shell's DESIGN.md checks all pass" 0 "$(grep '^FAIL' "$sh_dir/render/checks.txt" 2>/dev/null | grep -c 'shell')"
check "the shell's checks ran" yes "$([ "$(grep -c 'shell' "$sh_dir/render/checks.txt" 2>/dev/null)" -ge 15 ] && echo yes || echo no)"
export MINMACS_HOME="$sh_top"
# ===== end of Shell =====
