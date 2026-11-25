# ===== Window: the menu window's feed, its verb and Fix Everything's runner, issue #62 =====
# Sourced by test.sh after core. It builds test/window/window.m with all of Sources/Core, the feed, runner and
# controller files of Sources/Shell and the plain model of Sources/UI/Window, and runs it on fixture facts inside
# $MINMACS_HOME.
# The runner's actions are fakes that act only on files the tool made in its own fixture folder: a stop or a quit
# writes its key to a list, and a removal goes through MMRemovalApply into $MINMACS_HOME/Trash, since everything
# MinMacs removes keeps a way back. No process starts.
# Fix Everything has no verb, so nothing here could act on a real server, worktree, cache or app.

wn_dir="$(cd "$MINMACS_HOME" && pwd -P)/window.$$"
mkdir -p "$wn_dir/home"
# A home of its own inside the test home, so its prefs, log and Trash are this section's only.
wn_home="$wn_dir/home"
wn_shell="Sources/Shell/MMWindowFeed.m Sources/Shell/MMWindowRows.m Sources/Shell/MMWindowAgent.m Sources/Shell/MMWindowRules.m Sources/Shell/MMWindowJSON.m Sources/Shell/MMFixRunner.m Sources/Shell/MMWindowLog.m Sources/Shell/MMWindowLogRun.m Sources/Shell/MMWindowLogFold.m Sources/Shell/MMAsk.m Sources/Shell/MMAskCLI.m Sources/Shell/MMAskClaude.m Sources/Shell/MMKeepCLI.m"
wn_cc="clang -fobjc-arc -O1 -mmacosx-version-min=14.0 -ISources -Wall -Wextra -Wno-unused-parameter -Wstrict-prototypes -Werror -DMM_TESTS"
$wn_cc $(find Sources/Core -name '*.m' | LC_ALL=C sort) $wn_shell Sources/Shell/MMWindowController.m Sources/UI/Window/MMWindowModel.m Sources/UI/Window/MMWindowAnswer.m Sources/UI/Window/MMWindowFixtureAsk.m Sources/UI/Window/MMWindowCounts.m Sources/UI/Window/MMWindowCollapse.m Sources/UI/Window/MMWindowFixture.m Sources/UI/Window/MMWindowFixtureRows.m Sources/UI/Window/MMWindowFixtureMore.m Sources/UI/Window/MMWindowFixtureLog.m Sources/UI/Window/MMWindowFixtureWeek.m Sources/UI/MMFormat.m test/window/window.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -lsqlite3 -o "$wn_dir/windowtest-$$" >"$wn_dir/build.log" 2>&1
wn_r=$?
check "window: the test binary builds with no warnings" 0 "$wn_r"
[ "$wn_r" = 0 ] || tail -20 "$wn_dir/build.log"

wn_tab=$(printf '\t')
wn_run() { # mode
  MINMACS_HOME="$wn_home" "$wn_dir/windowtest-$$" "$wn_home/fixtures-$1" "$1" >"$wn_dir/$1.out" 2>"$wn_dir/$1.err"
  wn_x=$?
  check "window: $1 ran to the end" "0 END" "$wn_x $(tail -1 "$wn_dir/$1.out")"
  [ "$wn_x" = 0 ] || tail -10 "$wn_dir/$1.err"
  while IFS="$wn_tab" read -r wn_tag wn_name wn_want wn_got; do
    case "$wn_tag" in
      CHECK) check "$wn_name" "$wn_want" "$wn_got" ;;
      info) echo "  info  $wn_name" ;;
    esac
  done <"$wn_dir/$1.out"
}

if [ "$wn_r" = 0 ]; then
  echo "-- the model: groups, rows, the ring, the fixes and Settings"
  wn_run model
  echo "-- the calm state"
  wn_run calm
  echo "-- Fix Everything, on fixtures"
  wn_run run
  echo "-- stopped after the step under way"
  wn_run stop
  echo "-- stopped inside a fix of two things"
  wn_run inside
  echo "-- an app that will not quit"
  wn_run refused
  echo "-- the controller: open and closed, generations, two presses, stop and what waits for the end"
  wn_run controller
  echo "-- Fix Everything when MinMacs cannot write its own list of what it sends to the Trash"
  wn_run trash-list
  echo "-- Fix Everything with an old Smart or Delete in the pref"
  wn_run smart
  wn_run delete
  echo "-- the welcome of the first launch"
  wn_run welcome
  echo "-- a worktree whose size is not measured yet"
  wn_run unmeasured
  echo "-- the worktrees by project, the most active first"
  wn_run projects
  echo "-- Fix Everything's planned disk with a worktree not measured, issue #83"
  wn_run planned
  echo "-- an agent that serves a port of its own"
  wn_run agentport
  echo "-- a server under an app, both in fixes: memory back counts it once"
  wn_run overlap
  echo "-- near-identical rows as one, DESIGN rule 16: 169 temp-folder families, helpers, and Fix Everything over them"
  wn_run collapse
  wn_run collapse-helpers
  wn_run collapse-run
  echo "-- a worktree's pull request through a fake gh, only on demand"
  wn_run pulls
  echo "-- the strip's 7 days: honest words, the feed, and reads only while open and on the 7 days"
  wn_run week
  wn_run week-controller
  echo "-- an agent row's story, and Claude Code's scratch as the owner's Mac had it"
  wn_run agentstory
  wn_run collapse-real
  MINMACS_HOME="$MINMACS_HOME" "$wn_dir/windowtest-$$" "${TMPDIR:-/tmp}/window-outside-$$" run >/dev/null 2>&1
  check "window: the tool refuses a fixture folder outside the test home" "2 no" "$? $([ -e "${TMPDIR:-/tmp}/window-outside-$$/library" ] && echo yes || echo no)"
  rmdir "${TMPDIR:-/tmp}/window-outside-$$" 2>/dev/null
fi

echo "-- what the closed window holds, and its first frame after it was let go"
# test/window/memory.m makes the panel through MMWindowHolder as the shell does, with a fixture model, and opens it far
# off every screen, so nobody sees it. It reads its own footprint, as the field sampler reads the app, and never starts
# the app, Core or a scan. The panel takes the keyboard for the second each open lasts, as it does for the person.
wn_mem="$wn_dir/windowmemory-$$"
$wn_cc $(find Sources/UI -name '*.m' | LC_ALL=C sort) Sources/Core/MMSpecs.m test/window/memory.m -framework Cocoa -framework QuartzCore \
  -o "$wn_mem" >"$wn_dir/memory-build.log" 2>&1
wn_mr=$?
check "window: the memory check builds with no warnings" 0 "$wn_mr"
[ "$wn_mr" = 0 ] || tail -20 "$wn_dir/memory-build.log"
if [ "$wn_mr" = 0 ]; then
  # A rest of 3 seconds in place of the app's 45, so the section stays short.
  MINMACS_HOME="$wn_home" "$wn_mem" 3 >"$wn_dir/memory.out" 2>"$wn_dir/memory.err"
  wn_x=$?
  check "window: the memory check ran to the end" "0 END" "$wn_x $(tail -1 "$wn_dir/memory.out")"
  [ "$wn_x" = 0 ] || tail -10 "$wn_dir/memory.err"
  while IFS="$wn_tab" read -r wn_tag wn_name wn_want wn_got; do
    case "$wn_tag" in
      CHECK) check "$wn_name" "$wn_want" "$wn_got" ;;
      info) echo "  info  $wn_name" ;;
    esac
  done <"$wn_dir/memory.out"
fi
check "window: the shell holds the panel through MMWindowHolder, which keeps it while a run plays and lets it go 45 s after a close" "1 1 1 0" \
  "$(grep -c 'self.windowHolder = \[\[MMWindowHolder alloc\] initWithHost:self.windowController\];' Sources/Shell/MMShell.m) $(grep -c 'self.windowHolder.busy = ^BOOL { return weak.windowController.running; };' Sources/Shell/MMShell.m) $(grep -c '^const NSTimeInterval MMWindowRestSeconds = 45;$' Sources/UI/Window/MMWindowHolder.m) $(grep -c 'MMWindowPanel alloc' Sources/Shell/MMShell.m)"
check "window: the panel is made with its window, and draws and commits its first frame before it is ordered in" "1 1" \
  "$(grep -c 'backing:NSBackingStoreBuffered defer:NO\]' Sources/UI/Window/MMWindowPanel.m) $(awk '/^- \(void\)openInFrame:/,/^}/' Sources/UI/Window/MMWindowPanel.m | grep -A3 'displayIfNeeded' | grep -c 'CATransaction") flush')"

echo "-- the sources"
wn_new="Sources/Shell/MMWindowFeed.h Sources/Shell/MMWindowLog.h $wn_shell Sources/Shell/MMWindowJSON.h Sources/Shell/MMFixRunner.h Sources/Shell/MMWindowController.h Sources/Shell/MMWindowController.m Sources/Shell/MMWindowCLI.h Sources/Shell/MMWindowCLI.m"
check "window: the feed, the JSON and the runner import no AppKit" 0 \
  "$(cat Sources/Shell/MMWindowFeed.h $wn_shell Sources/Shell/MMWindowJSON.h Sources/Shell/MMFixRunner.h | grep -cE '#import <(Cocoa|AppKit)')"
check "window: a press on a row only selects: the list's input names no host and no action" 0 \
  "$(grep -cE 'MMWindowHost|\.host|MMRunAction|window(Run|Stop|Undo|Set|Quit|Welcome)' Sources/UI/Window/MMWindowListInput.m)"
check "window: each file stays under 500 lines" 0 "$(wc -l $wn_new | awk '$2 != "total" && $1 >= 500' | grep -c .)"
check "window: the model stays plain: no Core and no AppKit" 0 "$(grep -cE '#import (<(Cocoa|AppKit)|"Core/)' Sources/UI/Window/MMWindowModel.h Sources/UI/Window/MMWindowModel.m Sources/UI/Window/MMWindowAnswer.m Sources/UI/Window/MMWindowCounts.m Sources/UI/Window/MMWindowCollapse.m | awk -F: '{s+=$2} END {print s+0}')"
check "window: the runner acts only through MMRunAction and MMRunWrapUp" "1 1 0" \
  "$(grep -c 'MMRunAction(a, f.policy, nil, @"manual"' Sources/Shell/MMFixRunner.m) $(grep -c 'MMRunWrapUp(f.wrapUp, @"manual"' Sources/Shell/MMFixRunner.m) $(grep -cE '[^a-zA-Z_]kill\(|removeItemAt|trashItemAt|unlink\(|rmdir\(|NSTask|terminate\]|perform:' Sources/Shell/MMFixRunner.m)"
check "window: the runner and the controller each have a labeled queue" "1 1" \
  "$(grep -c 'MMQueue(@"core", @"fix-everything", QOS_CLASS_USER_INITIATED)' Sources/Shell/MMFixRunner.m) $(grep -c 'MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED)' Sources/Shell/MMWindowController.m)"
check "window: nothing in the window's shell files runs lsof, nettop, ps or pmset, or makes a timer" 0 \
  "$(grep -cE '"[^"]*(lsof|nettop|pmset|/bin/ps)[^"]*"|MMTimer\(|NSTimer|dispatch_source' $wn_new | awk -F: '{s+=$2} END {print s+0}')"
check "window: the 7 days are read by the controller alone, and only when the strip shows them" "Sources/Shell/MMWindowController.m 1" \
  "$(grep -rl 'MMHistoryWeekHours(' Sources/Shell Sources/UI | tr '\n' ' ' | sed 's/ $//') $(grep -c 'if (x.stripWeek) \[self readWeek:x\];' Sources/Shell/MMWindowController.m)"
check "window: one MMPerformance per snapshot, built in the controller only while open" "1 1" \
  "$(cat Sources/Shell/MMWindowController.m Sources/Shell/MMWindowFeed.m Sources/Shell/MMWindowRows.m Sources/Shell/MMWindowRules.m Sources/Shell/MMFixRunner.m | grep -c 'MMPerformance from:') $(grep -c 'if (!self.open || !s || s.generation <= atomic_load(&_wanted)) return;' Sources/Shell/MMWindowController.m)"
check "window: no string in these files names an old app" 0 \
  "$(grep -cE '@"[^"]*(LocoHost|WorkForest|Noo-Noo|NooNoo|Insomnia)[^"]*"' $wn_new | awk -F: '{s+=$2} END {print s+0}')"
check "window: no string claims a result or says for good" 0 \
  "$(grep -ciE '@"[^"]*(is clean|all good|for good|everything is fine|nothing needs you)[^"]*"' $wn_new | awk -F: '{s+=$2} END {print s+0}')"
check "window: only MMShell.m names the panel, and the feed names no view" 0 \
  "$(grep -cE 'MMWindowView|MMWindowPanel|MMWindowFixture' $(ls Sources/Shell/*.m Sources/Shell/*.h Sources/CLI/*.m | grep -v 'Shell/MMShell.m') | awk -F: '{s+=$2} END {print s+0}')"
# The sixth MMWindowMode() is the unattended skip of the welcome, D3, which only the menu window has.
check "window: the icon opens the panel while core.window is on, it is on by default, and one function reads it" "1 1 0 6" \
  "$(grep -c 'static NSString \*const kWindowKey = @"core.window";' Sources/Shell/MMShell.m) $(grep -c 'BOOL MMWindowMode(void) { return MMPrefBool(kWindowKey, YES); }' Sources/Shell/MMShell.m) $(grep -c 'MMPrefBool(kWindowKey, NO)' Sources/Shell/MMShell.m) $(grep -c 'MMWindowMode()' Sources/Shell/MMShell.m)"
# The rows read each expert's facts by key, and Settings says what each expert's mode rule does. A rename or a changed
# rule in an expert would leave a line out or make a sentence false with no error, so each string must still be there.
wn_has() { # file string...
  wn_f=$1; shift
  for wn_s in "$@"; do grep -qF -- "$wn_s" "Sources/Experts/$wn_f" && printf '1 ' || printf '0 '; done
}
wn_strings="$(wn_has LocoHost/MMLHHost.m '@"port": @(self.port)' '@"framework": self.framework' '@"project": self.project' '@"lastActive": Time(self.lastActive)' '@"uptimeSeconds"' '@"where": Or(self.placeLabel)' '@"whereApp"' '@"agent": Or(self.agent)' '@"kind": self.kind' '@"agentTitle": Or(self.agentTitle)' '@"launcher"' '@"protected": @(self.isProtected)' '? @"active" : s == MMLHRecent ? @"recent" : @"idle"'
  wn_has LocoHost/MMLocoHost.m 'facts[@"keptUntil"]'
  wn_has MinMacs/MMMinMacsExpert.m '@"harnessID": m.harnessID' '@"name": m.name' '@"state": StateWord(m.state)' '@"project": m.project' '@"why": m.why' 'return @"waits on you"' '@"bundleID": a.bundleID' '@"group": GroupName(g)' 'fx[@"reason"] = reason' 'fx[@"agent"] = a.agentName' 'fx[@"ports"] = a.loopbackPorts' 'fx[@"ports"] = m.ports'
  wn_has MinMacs/MMMinMacsWrapUp.m '@"cwd": cwd' '@"worktree": subject.path' '@"urls": urls' '@"ports": on.array' '@"bundleID": bid'
  wn_has WorkForest/MMWFTree.m '@"branch": Or(self.branch)' '@"merged": Or(self.merged)' '@"dirty": @(self.dirty)' '@"untracked": @(self.untracked)' '@"unpushed": @(self.unpushed)' '@"lastWorkAt": Time(self.lastWork)' '@"protected": @(self.isProtected)' '@"sized": @(self.sized)' '@"missing": @(self.missing)'
  wn_has NooNoo/MMNooNooExpert.m '@"kindTitle": k.title' '@"name": RowName(i)' '? @"free" : i.state == MMClutterLive ? @"live" : @"kept"' 'fx[@"owner"] = ownerName' 'fx[@"lastUsed"]' 'fx[@"keep"]' 'fx[@"why"]' 'fx[@"collapse"] = CollapseWords(k)' '@"kindID": k.kindID' '@"members": @(i.members.count)' '@"path": i.path')"
check "window: the experts still write the facts the rows read" "1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1" "${wn_strings% }"
wn_rules="$(wn_has LocoHost/MMLHScan.m 'EnvMinutes(@"LOCOHOST_PROACTIVE_MINUTES", 6 * 60)'
  wn_has LocoHost/MMLocoHost.m 'if (m != MMModeProactive) return nil;' 'if (h.agent.length && !h.orphaned) return'
  wn_has WorkForest/MMWFTree.m 'EnvHours("WORKFOREST_PROACTIVE_HOURS", 7 * 24)' 'self.merged.length > 0 || [self.upstream isEqualToString:@"gone"]'
  wn_has WorkForest/MMWorkForest.m 'if (!t.done) return @"not merged and the remote branch still exists";'
  wn_has MinMacs/MMMinMacsExpert.m 'if (m != MMModeEager) return @"Proactive never quits an app on its own";' 'return @"Eager quits apps only while memory pressure or heat is high";'
  wn_has NooNoo/MMNooNooExpert.m 'if ([sec isEqual:@"finished"] || [sec isEqual:@"leftovers"]) return nil;' 'if (m == MMModeEager && [f.facts[@"class"] isEqual:@"cache"]) return nil;' 'return @"Noo-Noo runs a tool'"'"'s own cleanup only when you ask";')"
check "window: each mode rule is still what Settings says it is" "1 1 1 1 1 1 1 1 1 1 1" "${wn_rules% }"
# D2: there is no removal choice to offer. Neither the feed nor the render's fixture draws a card for it.
check "window: neither the feed's Settings nor the render's offers a removal card" "0 0 0" \
  "$(grep -c 'RemovalRule\|MMWindowRemovalRuleID' Sources/Shell/MMWindowRules.m) $(grep -c 'Card(@"removal"' Sources/UI/Window/MMWindowFixture.m) $(grep -rc 'MMRemovalChoiceTitle\|MMRemovalChoiceExplain' Sources/Shell Sources/UI | awk -F: '{s+=$2} END {print s+0}')"
# The render's made-up rows may only use the words the feed can put on a row. tools/render-window-words.m holds the
# rows to these lists; here each word is held to the feed's own source, so a word the feed drops fails.
wn_words=$(for wn_s in '@"kept"' '@"idle"' '@"asks"' '@"left behind"' '@"changed"' '@"merged"' '@"in use"' '@"will close"'; do
  grep -qF -- "$wn_s" Sources/Shell/MMWindowRows.m Sources/Shell/MMWindowFeed.m && printf '1' || printf '0(%s)' "$wn_s"; done
  # The fact labels are the model's, one function a fact. The feed and the fixtures both call those and write no label of their own.
  for wn_s in Port Project 'Runs in' 'Started by' Idle 'Last used' Running Kept Agent Session State 'Used by' Serves Stays 'Left by' Folder Open On Branch Files 'Not pushed' Untouched Changed Kind; do
  grep -qF -- "Fact(@\"$wn_s\"," Sources/UI/Window/MMWindowModel.m && printf '1' || printf '0(%s)' "$wn_s"; done
  printf ' %s' "$(grep -cE 'MMWindowFact label:|\[MMWindowFact new\]' Sources/Shell/MMWindowRows.m Sources/UI/Window/MMWindowFixtureRows.m Sources/UI/Window/MMWindowFixtureMore.m | awk -F: '{n += $2} END {print n}')")
check "window: every state word is one the feed writes, every fact label is the model's, and neither the feed nor the made-up rows word a fact themselves" "11111111111111111111111111111111 0" "$wn_words"
check "window: the removal title is gone, and the first-look line is written once" "0 1" \
  "$(grep -rF '@"When MinMacs removes things"' Sources | grep -c .) $(grep -rF '@"MinMacs is taking its first look. It takes a few seconds."' Sources | grep -c .)"
# The welcome: the login item is added in two places only, the old first launch and -setLogin:, and the window reaches
# -setLogin: from the Settings switch and from Start alone. Under MINMACS_HOME -setLogin: returns before SMAppService.
check "window: with the menu window the first launch adds no login item, and -setLogin: stops first in a test home" "1 1 1" \
  "$(grep -c 'if (!self.headless && MMFirstLaunchAddsLogin(MMWindowMode()) &&' Sources/Shell/MMShell.m) $(grep -c 'BOOL MMFirstLaunchAddsLogin(BOOL windowMode) { return !windowMode; }' Sources/Shell/MMShell.m) $(grep -A1 -- '^- (void)setLogin:(BOOL)on {' Sources/Shell/MMShell.m | grep -c 'if (!MMMayRegisterLoginItem(NSProcessInfo.processInfo.environment, NSBundle.mainBundle.bundlePath)) return;')"
# Settings in window mode is the window turned over. The old Settings window is made in one place, behind that check.
check "window: every way to Settings waits for the launch, then goes by core.window alone, and the old Settings window is made only past that" "1 1 1 5 1 1" \
  "$(grep -A2 -- '^- (void)showSettings:(id)sender {' Sources/Shell/MMShell.m | grep -c 'if (!self.launched) { self.settingsWaits = YES; return; }') $(grep -c 'if (MMWindowMode()) { \[self showWindowSettings\]; return; }' Sources/Shell/MMShell.m) $(grep -c 'if (MMPrefBool(MMWindowWelcomedKey, NO)) self.windowPanel.view.showsSettings = YES;' Sources/Shell/MMShell.m) $(grep -c '\[self showSettings:nil\]\|\[self.shell showSettings:sender\]' Sources/Shell/MMShell.m) $(grep -c '\[MMSettings new\]' Sources/Shell/MMShell.m) $(grep -l 'MMSettings new\]' $(find Sources -name '*.m') | grep -c .)"
# The window has no Hide Icon, so its icon is shown at every start, whatever was saved. A way to Settings brings MinMacs
# to the front and holds the panel open while a second copy quits.
check "window: the window's icon is made visible whatever was saved, and a way to Settings activates MinMacs and holds the panel" "1 1 1" \
  "$(grep -A6 'if (!self.expert && MMWindowMode()) {' Sources/Shell/MMShell.m | grep -c 'self.item.visible = YES;') $(grep -A6 -- '^- (BOOL)showWindowSettings {' Sources/Shell/MMShell.m | grep -c '\[NSApp activateIgnoringOtherApps:YES\];') $(grep -c '\[self.windowPanel holdOpen:MMWindowRouteHold\];' Sources/Shell/MMShell.m)"
check "window: the controller asks for the login item from the Settings switch and from Start only, and Start only for a change" "2 1 1" \
  "$(grep -c 'self.shell setLogin:' Sources/Shell/MMWindowController.m) $(grep -c '\[self.shell setLogin:on\];' Sources/Shell/MMWindowController.m) $(grep -c 'if (before != openAtLogin) \[self.shell setLogin:openAtLogin\];' Sources/Shell/MMWindowController.m)"
check "window: a first launch that leaves the login item alone says so, and any -setLogin: takes the mark away" "1 1 1" \
  "$(grep -c 'if (!MMFirstLaunchAddsLogin(MMWindowMode())) MMSetPref(MMWindowLoginNotAskedKey, @YES);' Sources/Shell/MMShell.m) $(grep -c 'MMSetPref(MMWindowLoginNotAskedKey, nil);' Sources/Shell/MMShell.m) $(grep -c 'MMSetPref(MMWindowLoginNotAskedKey, nil);' Sources/Shell/MMWindowRules.m)"
check "window: SMAppService is registered in MMShell.m only" 0 "$(grep -lE 'registerAndReturnError|unregisterAndReturnError' $(find Sources -name '*.m') | grep -vc '^Sources/Shell/MMShell.m$')"
# The render's welcome cannot link Core or the feed, so it holds the facts as its own strings.
check "window: the render's welcome says the feed's three facts for a new person" "1 1 1 1 1 1" \
  "$(for wn_s in '@"It waits a day" value:@"For its first day MinMacs stops, quits and removes nothing on its own."' '@"You set every rule" value:' '@"Each rule can be Off, Careful or Eager. Each starts on Careful."' '@"No permission is asked at launch. The Mac stays awake while agents work."'; do
       grep -qF -- "$wn_s" Sources/Shell/MMWindowRules.m && grep -qF -- "$wn_s" Sources/UI/Window/MMWindowFixture.m && printf '1 ' || printf '0 '; done
     grep -qF 'MMWindowRemovalTitle' Sources/UI/Window/MMWindowModel.m Sources/UI/Window/MMWindowModel.h && printf '0 ' || printf '1 '
     grep -qF 'c requestAuthorizationWithOptions' Sources/Core/Act/MMAct.m && [ "$(grep -rl 'requestAuthorization' Sources | grep -c .)" = 1 ] && printf '1' || printf '0')"
check "window: the render's watched welcome says what the feed says for every rule on Careful" "1 1" \
  "$(grep -cF '@"It has watched a day" value:@"MinMacs may now stop servers, remove worktrees and clean up leftovers on its own."' Sources/UI/Window/MMWindowFixture.m) $(grep -cF '@"It has watched a day: MinMacs may now stop servers, remove worktrees and clean up leftovers on its own."' test/window/welcome.m)"
# The facts name rules of the experts and of Core. A changed rule would make a sentence false with no error.
check "window: the code still makes each welcome fact true" "1 1 1 1 1 1" \
  "$(grep -qF 'static const NSTimeInterval kWatchDay = 24 * 3600;' Sources/Core/Act/MMAct.m && printf '1 ' || printf '0 '
     grep -qF 'if (act && !MMWatchedLongEnough(f.expert)) { act = NO;' Sources/Core/Act/MMAct.m && printf '1 ' || printf '0 '
     grep -qF 'else if (!MMWatchedLongEnough(f.expert)) problem' Sources/Core/Act/MMAct.m && printf '1 ' || printf '0 '
     grep -qF 'return m < 0 ? MMModeProactive : (MMMode)m;' Sources/Core/Act/MMAct.m && printf '1 ' || printf '0 '
     grep -qF 'p.manual = NO; p.agents = YES; p.lid = NO;' Sources/Experts/Insomnia/MMINMenu.m && printf '1 ' || printf '0 '
     grep -qF 'p.agents = Bool(@"insomnia.agents", d.agents);' Sources/Experts/Insomnia/MMINGuards.m && printf '1' || printf '0')"
check "window: the keep-awake state still has the keys the lid switch reads" 8 \
  "$(grep -cE '^@property (BOOL (lid|lidLive|laptop|otherApp);|\(copy\) (MMINPrefs \*prefs|NSString \*(pauseReason|lidProblem));)' Sources/Experts/Insomnia/MMInsomnia.h)"

# A pull request is asked for on demand only: the controller asks MMPulls for a story that shows, and nothing else asks
# it. gh runs on its own queue, through MMRun with a time limit, and nowhere else.
check "window: only the controller asks gh for a pull request, on the prs queue, through MMRun with a time limit" "Sources/Shell/MMWindowController.m 1 1 0" \
  "$(grep -rl 'MMPulls.shared want:' Sources | tr '\n' ' ' | sed 's/ $//') $(grep -c 'MMQueue(@"workforest", @"prs", QOS_CLASS_UTILITY)' Sources/Core/Know/MMPulls.m) $(grep -c 'r = MMRun(gh, MMPullArguments(w\[@"branch"\]), nil, GhEnvironment(gh), w\[@"folder"\], self.timeout, &out, &err);' Sources/Core/Know/MMPulls.m) $(grep -rlE 'MMPullArguments\(' Sources | grep -vc 'Core/Know/MMPulls')"
wn_p1=$(MINMACS_HOME="$wn_home" "$BIN" trees prs off 2>/dev/null)
wn_p2=$(MINMACS_HOME="$wn_home" "$BIN" trees prs --json 2>/dev/null | json "j['pullRequests']")
MINMACS_HOME="$wn_home" "$BIN" trees prs on >/dev/null 2>&1
wn_p3=$(MINMACS_HOME="$wn_home" "$BIN" trees prs --json 2>/dev/null | json "j['pullRequests']")
check "window: trees prs off and on set the pref, and --json says it" "off: MinMacs asks GitHub nothing about pull requests|False|True" "$wn_p1|$wn_p2|$wn_p3"
MINMACS_HOME="$wn_home" "$BIN" trees prs maybe >/dev/null 2>&1
check "window: trees prs takes on or off only" 2 "$?"

echo "-- minmacs window"
# The verb runs cold here, read only, as performance does: the Mac's own processes, and no worktree walk.
wn_json=$(MINMACS_HOME="$wn_home" "$BIN" window --json 2>/dev/null)
check "window: window --json runs" 0 "$?"
check "window: --json has the asks line, both sides, the ring, the fixes and Settings" "app asks backToday disk diskHour fixEverything fixes generation memory memoryHour ring run settings" \
  "$(printf '%s' "$wn_json" | json "' '.join(sorted(j))")"
check "window: --json groups in the window's order" "servers agents apps worktrees caches" \
  "$(printf '%s' "$wn_json" | json "' '.join(g['key'] for g in j['memory'] + j['disk'])")"
check "window: --json keeps memory and disk apart in the ring and in Fix Everything" "disk memory | diskBack diskBackPartial fixes memoryBack" \
  "$(printf '%s' "$wn_json" | json "' '.join(sorted(j['ring'])) + ' | ' + ' '.join(sorted(j['fixEverything']))")"
check "window: --json memory slices add up to memory in use" yes \
  "$(printf '%s' "$wn_json" | json "'yes' if sum(p['bytes'] for p in j['ring']['memory']['slices']) == j['ring']['memory']['used'] else 'no'")"
check "window: --json rows say whether their size is measured, and one that is not holds null and no 0" yes \
  "$(printf '%s' "$wn_json" | json "(lambda rows: 'yes' if all((r['bytes'] is None) != r['measured'] for r in rows) else 'no')([r for g in j['memory'] + j['disk'] for r in g['rows']])")"
check "window: --json rows carry a kind and their own key" yes \
  "$(printf '%s' "$wn_json" | json "(lambda rows: 'yes' if len(set(r['key'] for r in rows)) == len(rows) and all(r['kind'] in ('server','agent','app','helper','tabs','worktree','cache') for r in rows) else 'no')([r for g in j['memory'] + j['disk'] for r in g['rows']])")"
check "window: --json has a rule per expert with modes, three choices each, no removal card, and the six switches" "servers,apps,worktrees,caches 3 awake,agents,lid,login,prs,askclaude" \
  "$(printf '%s' "$wn_json" | json "','.join(r['ruleID'] for r in j['settings']['rules']) + ' ' + str(max(len(r['choices']) for r in j['settings']['rules'])) + ' ' + ','.join(s['switchID'] for s in j['settings']['switches'])")"
wn_text=$(MINMACS_HOME="$wn_home" "$BIN" window 2>/dev/null)
check "window: the text form runs to its end" 0 "$?"
check "window: the text prints memory and disk on their own lines" "1 1" \
  "$(printf '%s\n' "$wn_text" | grep -c '^Memory ') $(printf '%s\n' "$wn_text" | grep -c '^Disk ')"
check "window: the text names no old app and claims no result" 0 "$(printf '%s\n' "$wn_text" | grep -ciE 'locohost|workforest|noo-noo|insomnia|is clean|all good')"
# A home with an old removal choice in its pref, as an older MinMacs wrote it: no card shows, and the verb still runs.
wn_fresh="$wn_dir/fresh-home"; mkdir -p "$wn_fresh"
old_removal "$wn_fresh" delete
wn_text=$(MINMACS_HOME="$wn_fresh" "$BIN" window 2>/dev/null)
check "window: with an old delete in the pref the text form still exits 0" 0 "$?"
check "window: and names no removal rule, then prints the switches" "0 4 6" \
  "$(printf '%s\n' "$wn_text" | grep -c 'When MinMacs removes things') $(printf '%s\n' "$wn_text" | grep -c '^Rule ') $(printf '%s\n' "$wn_text" | grep -c '^Switch ')"
wn_json=$(MINMACS_HOME="$wn_fresh" "$BIN" window --json 2>/dev/null)
check "window: with an old delete in the pref --json exits 0 and has no removal rule" "0 0" "$? $(printf '%s' "$wn_json" | json "len([r for r in j['settings']['rules'] if r['ruleID'] == 'removal'])")"
MINMACS_HOME="$wn_home" "$BIN" window fix --all >/dev/null 2>&1
check "window: the verb has no form that runs a fix" 2 "$?"
check "window: help --json lists it as a verb that reads only" "False []" \
  "$("$BIN" help --json | json '[str(v["mutates"]) + " " + str(v["mutatingForms"]) for v in j["verbs"] if v["verb"] == "window"][0]')"

# ===== end of window =====
