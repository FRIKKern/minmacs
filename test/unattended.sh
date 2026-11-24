# ===== D3: no person is ever needed =====
# Sourced by test.sh after core. These Macs run unattended, driven by an agent, often with the lid shut and the display
# asleep. Nothing in MinMacs waits for a person: a failure is a row of the log's notice table and at most one
# notification, a confirm guards only a press a person plainly made, the CLI never reads a terminal nobody sits at,
# and the welcome is skipped on a Mac that runs unattended.
# It builds test/unattended/tool.m with all of Core, the kit, the CLI, the five experts and the window's log and
# controller under -DMM_TESTS, and runs it in homes of its own inside the test home. Nothing here acts on a real
# server, worktree, cache or app: the tool's actions fail their own check, and the CLI runs cold in a test home.

un_dir="$(cd "$MINMACS_HOME" && pwd -P)/unattended.$$"
mkdir -p "$un_dir"
un_limit() { perl -e 'alarm shift; exec @ARGV' "$@"; }   # seconds, then the command; exit 142 past the limit

echo "-- the sources: no modal alert, no read of a terminal nobody sits at"
# The one confirm is MMAskPerson in Sources/UI/MMConfirm.m: it guards a press a person made while plainly there.
un_alerts=$(grep -rlE 'NSAlert|runModal|beginSheet|beginModalSession|NSRunAlertPanel' Sources | grep -v '^Sources/UI/MMConfirm\.[hm]$' | LC_ALL=C sort | paste -sd' ' -)
check "D3: NSAlert and runModal appear only in Sources/UI/MMConfirm, the one allowed confirm" "" "$un_alerts"
check "D3: MMConfirm.m holds one NSAlert and one runModal" "1 1" "$(grep -c '\[NSAlert new\]' Sources/UI/MMConfirm.m) $(grep -c 'runModal\]' Sources/UI/MMConfirm.m)"
# Every caller of the confirm asks only when a person made the press: present, read with MMPersonPresses at the press.
un_callers=$(grep -rl 'MMAskPerson(' Sources --include='*.m' 2>/dev/null | grep -v '^Sources/UI/MMConfirm\.m$' | LC_ALL=C sort | paste -sd' ' -)
check "D3: five files call the confirm" "Sources/Experts/Insomnia/MMInsomniaExpert.m Sources/Experts/LocoHost/MMLocoHost.m Sources/Experts/WorkForest/MMWorkForest.m Sources/Shell/MMShell.m Sources/UI/MMInvestigateUI.m" "$un_callers"
check "D3: each guard reads present: the lid, WorkForest's confirm, and both Investigate confirms" "1 1 2" \
  "$(grep -c 'if (\[what isEqualToString:@"lid"\] && to && present) {' Sources/Experts/Insomnia/MMInsomniaExpert.m) $(grep -c 'return !present || MMAskPerson(title, text, button, nil);' Sources/Experts/WorkForest/MMWorkForest.m) $(grep -h 'if (present) return MMInvestigateConfirm(title, text, placeholder);' Sources/Experts/WorkForest/MMWorkForest.m Sources/Experts/LocoHost/MMLocoHost.m | grep -c .)"
# A link can come from any web page. One that acts asks a person who is here, with the confirm a press gets, and runs
# unasked only while the Mac runs unattended, by "url".
check "D3: workforest://clean-up, locohost://close-idle and run-now confirm unless unattended" "1 1 1" \
  "$(grep -c 'if (!MMUnattended() && !MMAskPerson(\[NSString stringWithFormat:@"Remove %@?", MMPlural(c.count, @"Stale Worktree")\], text, @"Remove Them", nil)) return;' Sources/Experts/WorkForest/MMWorkForest.m) $(grep -c 'if (!MMUnattended() && !MMAskPerson(\[NSString stringWithFormat:@"Stop %@?", MMPlural(c.count, @"Idle Server")\], list, @"Stop Them", nil)) return;' Sources/Experts/LocoHost/MMLocoHost.m) $(grep -c 'if (MMURLWordsAct(r.words) && !MMUnattended() &&' Sources/Shell/MMShell.m)"
check "D3: the links route to those guards and record by url" "1 1 1 1 1" \
  "$(grep -c '\[self cleanUpFromLink:MMGraph.shared.current\]' Sources/Experts/WorkForest/MMWorkForest.m) $(grep -c '\[self closeIdleFromLink:MMGraph.shared.current\]' Sources/Experts/LocoHost/MMLocoHost.m) $(grep -c '\[self remove:c why:@"Clean Up from a link" by:@"url"\]' Sources/Experts/WorkForest/MMWorkForest.m) $(grep -c '\[self closeIdle:c by:@"url" why:@"Close Idle from a link"\]' Sources/Experts/LocoHost/MMLocoHost.m) $(grep -c 'set:m\[0\] value:m\[1\] by:@"url"' Sources/Experts/Insomnia/MMInsomniaExpert.m)"
check "D3: url is a by word MMAct.h lists, the log says it, and it needs no notification" "1 1 1" \
  "$(grep -c '"url" from a link' Sources/Core/Act/MMAct.h) $(grep -c '@"url": @"from a link"' Sources/Shell/MMWindowLog.m) $(grep -c '\[r.by isEqualToString:@"url"\]) return;' Sources/Core/Act/MMAct.m)"
check "D3: run-now is the one link of CLI words that acts" 1 "$(grep -c 'return \[words.firstObject isEqualToString:@"tidy"\];' Sources/Shell/MMShell.m)"
check "D3: the window's lid switch reads present at the press" 1 "$(grep -c 'BOOL present = MMPersonPresses();' Sources/Shell/MMWindowController.m)"
check "D3: each expert's failure helper writes a notice" "1 1 1 1 1" \
  "$(for f in WorkForest/MMWorkForest.m LocoHost/MMLocoHost.m Insomnia/MMInsomniaExpert.m; do grep -c 'static void Notice(NSString \*title, NSString \*text) { MMNotice(kExpert, title, text); }' "Sources/Experts/$f"; done | xargs) $(grep -c 'MMNotice(kExpert, problems.count == 1' Sources/Experts/MinMacs/MMMinMacsExpert.m) $(grep -c 'MMNotice(kExpert, problems.count == 1' Sources/Experts/NooNoo/MMNooNooExpert.m)"
# stdin: the y/N of `locohost close` reads only at a TTY a person sits at. The other reads of stdin are protocols
# between MinMacs processes: the walk worker, the Investigate tools server and a test-only seam.
un_reads=$(grep -rnE 'fgets\([^)]*stdin|getchar\(|scanf\(|getline\([^)]*stdin|read\(0,|readDataToEndOfFile|fileHandleWithStandardInput' Sources | cut -d: -f1 | LC_ALL=C sort | uniq -c | awk '{print $2 ":" $1}' | paste -sd' ' -)
check "D3: stdin is read in four places only" "Sources/CLI/MMInvestigateCLI.m:1 Sources/Core/Act/MMRemovalTrashStranded.m:1 Sources/Core/Runtime/MMWorker.m:1 Sources/Experts/LocoHost/MMLHCLI.m:1" "$un_reads"
check "D3: and the y/N reads only when a person is at a TTY" 1 "$(grep -c 'if (raw.inApp || !isatty(STDIN_FILENO)) {' Sources/Experts/LocoHost/MMLHCLI.m)"
# Two cold runs pass it: the one with no app, and the one for an app older than this CLI that lacks a read verb.
check "D3: the CLI hands the app whether a person is at its terminal" "1 2" \
  "$(grep -c '@"noPerson": @(MMNoPersonAtTerminal())' Sources/CLI/MMCLI.m) $(grep -c 'return Run(spec, resolved, program, cwd, NO, MMNoPersonAtTerminal(), nil, nil);' Sources/CLI/MMCLI.m)"
check "D3: only an explicit turn of the lid to on writes the sudoers rule, behind macOS's prompt" "1 1" \
  "$(grep -rl 'installRule:' Sources --include='*.m' | grep -vc '^Sources/Core/Act/MMLid.m$') $(grep -c 'if (\[what isEqualToString:@"lid"\] && \[value boolValue\] && !\[MMLidOverride ruleInstalled\]) {' Sources/Experts/Insomnia/MMInsomniaExpert.m)"

echo "-- the tool: notices, each former alert path, and the welcome"
un_cc="clang -fobjc-arc -O1 -mmacosx-version-min=14.0 -ISources -Wall -Wextra -Wno-unused-parameter -Wstrict-prototypes -Werror -DMM_TESTS"
un_shell="Sources/Shell/MMWindowFeed.m Sources/Shell/MMWindowRows.m Sources/Shell/MMWindowRules.m Sources/Shell/MMWindowJSON.m Sources/Shell/MMFixRunner.m Sources/Shell/MMWindowLog.m Sources/Shell/MMWindowLogRun.m Sources/Shell/MMWindowLogFold.m Sources/Shell/MMWindowController.m"
# shellcheck disable=SC2086
$un_cc $(find Sources/Core Sources/UI Sources/CLI Sources/Experts -name '*.m' | LC_ALL=C sort) $un_shell test/unattended/tool.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -framework QuartzCore -framework ServiceManagement -lsqlite3 \
  -o "$un_dir/tool-$$" >"$un_dir/build.log" 2>&1
un_r=$?
check "D3: the test tool builds with no warnings" 0 "$un_r"
[ "$un_r" = 0 ] || tail -20 "$un_dir/build.log"

un_tab=$(printf '\t')
un_run() { # mode
  mkdir -p "$un_dir/home-$1"
  # Past the limit a confirm would be waiting on nobody, so the run fails.
  un_limit 60 env MINMACS_HOME="$un_dir/home-$1" "$un_dir/tool-$$" "$1" </dev/null >"$un_dir/$1.out" 2>"$un_dir/$1.err"
  un_x=$?
  check "D3: tool $1 ran to the end, within a minute" "0 END" "$un_x $(tail -1 "$un_dir/$1.out")"
  [ "$un_x" = 0 ] || tail -10 "$un_dir/$1.err"
  while IFS="$un_tab" read -r un_tag un_name un_want un_got; do
    [ "$un_tag" = CHECK ] && check "D3: $un_name" "$un_want" "$un_got"
  done <"$un_dir/$1.out"
}
if [ "$un_r" = 0 ]; then
  un_run notice
  un_run paths
  un_run welcome
  # The lid's commands go to the Insomnia checks' fake, which writes the rule when its osascript runs.
  MINMACS_INSOMNIA_CMD="$ROOT/test/insomnia/fakecmd.sh"; export MINMACS_INSOMNIA_CMD
  un_run lid
  unset MINMACS_INSOMNIA_CMD
fi

echo "-- the CLI with nobody at the terminal: every verb ends within its limit"
un_home="$un_dir/cli"; mkdir -p "$un_home"
un_bin() { un_limit 60 env MINMACS_HOME="$un_home" MINMACS_COLD=1 "$BIN" "$@"; }
un_verbs=$(un_bin help --json </dev/null | json "' '.join(v['verb'] for v in j['verbs'])")
check "D3: help lists the unattended verb" yes "$(printf '%s\n' $un_verbs | grep -qx unattended && echo yes || echo no)"
for un_env in "" "MINMACS_UNATTENDED=1"; do
  un_slow=""
  for un_v in $un_verbs; do
    # Each verb alone, as a script would run it with no terminal. Mutating verbs need the app, which does not run here.
    # shellcheck disable=SC2086
    un_limit 60 env $un_env MINMACS_HOME="$un_home" MINMACS_COLD=1 "$BIN" "$un_v" </dev/null >/dev/null 2>&1
    [ $? -ge 128 ] && un_slow="$un_slow $un_v"
  done
  check "D3: with stdin not a TTY${un_env:+ and $un_env}, no verb blocks" "" "$un_slow"
done
# The y/N forms, given nothing to act on, still end at once.
un_slow=""
for un_w in "trees clean-up" "trees remove $un_home/none" "investigate $un_home" "unattended on --dry-run"; do
  # shellcheck disable=SC2086
  un_bin $un_w </dev/null >/dev/null 2>&1; [ $? -ge 128 ] && un_slow="$un_slow [$un_w]"
done
check "D3: the forms that once asked end at once" "" "$un_slow"
check "D3: investigate with nobody there runs no model, and says --yes runs it" 1 \
  "$(un_bin investigate "$un_home" </dev/null 2>&1 | grep -c 'Run it with --yes to confirm the cost.')"

echo "-- minmacs unattended on|off"
check "D3: unattended is off on a new Mac" "False False" "$(un_bin unattended --json </dev/null | json "'%s %s' % (j['unattended'], j['pref'])")"
un_bin unattended on </dev/null >/dev/null 2>&1
check "D3: unattended on sets the pref" "0 True" "$? $(un_bin unattended --json </dev/null | json "j['unattended']")"
check "D3: MINMACS_UNATTENDED=0 decides over the pref for one process" "False True 0" \
  "$(un_limit 60 env MINMACS_UNATTENDED=0 MINMACS_HOME="$un_home" MINMACS_COLD=1 "$BIN" unattended --json </dev/null | json "'%s %s %s' % (j['unattended'], j['pref'], j['env'])")"
un_bin unattended off </dev/null >/dev/null 2>&1
check "D3: unattended off clears it" False "$(un_bin unattended --json </dev/null | json "j['pref']")"
un_bin unattended maybe </dev/null >/dev/null 2>&1
check "D3: anything but on or off is a usage error" 2 "$?"
check "D3: each change is a setting row by the command line, and the log says it" \
  "Unattended turned off.|from the command line Unattended turned on. Nothing waits for a person, and nothing asks to be confirmed.|from the command line" \
  "$(un_bin log --json </dev/null | json "' '.join(e['sentence'] + '|' + (e['who'] or '') for e in j['entries'] if e['kind'] == 'setting')")"

echo "-- minmacs device --json: what a fleet Mac still needs a person for"
un_dev() { un_limit 60 env MINMACS_HOME="$1" MINMACS_COLD=1 MINMACS_INSOMNIA_CMD="$ROOT/test/insomnia/fakecmd.sh" "$BIN" device --json </dev/null; }
un_dh="$un_dir/device"; mkdir -p "$un_dh"
un_dev "$un_dh" >"$un_dir/device.json" 2>/dev/null
check "D3: device --json has a provision object with every field" "lidRuleInstalled loginItem loginItemApproved needsPerson notificationsAuthorized unattended" \
  "$(json "' '.join(sorted(j['provision'].keys()))" <"$un_dir/device.json")"
check "D3: with no sudoers rule, lidRuleInstalled is false and lidRule is needed" "False True" \
  "$(json "'%s %s' % (j['provision']['lidRuleInstalled'], 'lidRule' in j['provision']['needsPerson'])" <"$un_dir/device.json")"
check "D3: the CLI cannot read the notification permission, so it is null" None "$(json "j['provision']['notificationsAuthorized']" <"$un_dir/device.json")"
check "D3: the login item is one of its words, read without asking" yes \
  "$(json "'yes' if j['provision']['loginItem'] in (None, 'enabled', 'requiresApproval', 'notRegistered', 'notFound') else j['provision']['loginItem']" <"$un_dir/device.json")"
mkdir -p "$un_dh/insomnia-fake"; : >"$un_dh/insomnia-fake/rule"
un_dev "$un_dh" >"$un_dir/device-rule.json" 2>/dev/null
check "D3: with the rule in place, lidRuleInstalled is true and lidRule is not needed" "True False" \
  "$(json "'%s %s' % (j['provision']['lidRuleInstalled'], 'lidRule' in j['provision']['needsPerson'])" <"$un_dir/device-rule.json")"
check "D3: the rule is read with sudo -n only, which never prompts" "/usr/bin/sudo -n -l /usr/bin/pmset -a disablesleep 1" "$(sort -u "$un_dh/insomnia-fake/log")"
un_limit 60 env MINMACS_HOME="$un_dh" MINMACS_COLD=1 MINMACS_UNATTENDED=1 "$BIN" device --json </dev/null >"$un_dir/device-un.json" 2>/dev/null
check "D3: provision says when the Mac runs unattended" True "$(json "j['provision']['unattended']" <"$un_dir/device-un.json")"
