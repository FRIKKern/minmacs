# Settling tests that need the owner at the screen

These five questions need someone at the Mac. Each one shows a prompt, registers something with the system, or needs a look at the menu bar. No agent runs them.

All five use one probe app, `MMSettle.app`. It is ad-hoc signed like MinMacs, has the bundle id `no.guerrilla.minmacs.settle`, and targets macOS 14. Each mode writes a log to `/tmp/mm-settle/<mode>.log`. Paste the log into `docs/2.0/TESTS.md` under the question, or give it to an agent.

## Build once

```sh
cd ~/Documents/GitHub/minmacs
test/settling/owner/build.sh ~/Applications/MMSettle
```

The tests use `~/Applications/MMSettle/MMSettle.app`, because MinMacs installs to `~/Applications` too. Always start a mode with `open -n`, so the app runs as its own app and not as a child of the terminal. A child of the terminal borrows the terminal's permissions and proves nothing.

```sh
P=~/Applications/MMSettle/MMSettle.app
```

## 1. Does an ad-hoc signed app get notification permission on macOS 27?

1. Run `open -n $P --args notify`.
2. A prompt asks to allow notifications from MMSettle. Click Allow.
3. A notification "Stopped 2 Servers" arrives. Hover it and click Undo.
4. Wait for the app to quit, about 90 seconds, then run `cat /tmp/mm-settle/notify.log`.

**Pass** when the log shows `granted 1`, `authorizationStatus 2`, `addNotificationRequest error (null)` and `response action undo`.

**Quick check first.** WorkForest asks for notification permission at every launch, in `workforest/Sources/main.m:369`, and it is ad-hoc signed too. If System Settings > Notifications lists WorkForest with Allow Notifications on, the answer is already yes. Write down what it shows.

Afterwards, remove MMSettle from System Settings > Notifications if you like. It sends nothing else.

## 2. Does `SMAppService` register from an ad-hoc bundle?

1. Run `open -n $P --args login-status`. The log shows the starting state.
2. Run `open -n $P --args login-on`. macOS may show a notice that a login item was added.
3. Open System Settings > General > Login Items & Extensions. Look for MMSettle under Open at Login.
4. Run `open -n $P --args agent-on`. This registers the bundled LaunchAgent. MMSettle may appear under Allow in the Background. If it needs approval, turn it on there.
5. Run `cat /tmp/mm-settle/agent-run.log`. A line "the LaunchAgent ran" means launchd started the agent from the ad-hoc bundle.
6. To clean up, run `open -n $P --args login-off`, then `open -n $P --args agent-off`, then `open -n $P --args login-status`.
7. Run `cat /tmp/mm-settle/login-*.log /tmp/mm-settle/agent-*.log`.

**Pass** when `login-on` reports `ok 1` and status `enabled`, and the agent ran. `requiresApproval` is a partial pass. It works after a click in Settings.

**Quick check.** LocoHost and WorkForest already use `SMAppService.mainAppService` from ad-hoc bundles, behind their Launch at Login switch. If either is on and starts at login, that is a yes for the main app service. The agent service is still open.

An agent run of `login-status` from `/private/tmp` returned `notFound` for both services. That is expected for a bundle outside the Applications folders that launchd has never seen.

## 3. Does the System Settings menu bar toggle hide all five icons of one app at once?

1. Run `open -n $P --args icons`. Five icons appear. They are a gauge, a network globe, a tree, a trash can and a moon.
2. Open System Settings > Menu Bar. Find MMSettle under Allow in the Menu Bar, and turn it off. Write down whether one switch covers all five icons, or each has its own.
3. Wait five seconds. Turn it on again.
4. Command-drag one icon out of the menu bar to remove it. Wait five seconds.
5. The app quits by itself after five minutes. Then run `cat /tmp/mm-settle/icons.log`.

**Pass** when one switch hides all five, and the log shows each icon's `onscreen` going to 0 and back. The log also shows what `isVisible` reports while hidden, which tells whether MinMacs can notice a hidden icon. Step 4 shows what removal by drag looks like in the same log.

## 4. Can one status item open another's menu at a given row?

1. Run `open -n $P --args crosslink`. Two icons appear, A and B.
2. Keep your hands off the mouse and keyboard. After two seconds B's menu opens twice, three seconds each time.
3. The app quits by itself. Run `cat /tmp/mm-settle/crosslink.log`.

**What the log says.** Way 1 pops up B's menu with row 3 placed at B's icon. Way 2 clicks B's icon in code, then posts three Down Arrow key events to the app itself. `willHighlightItem b row 3` means the row was highlighted. Write down where each menu appeared on screen: under B's icon, or somewhere else.

**Pass** when either way opens B's menu under B's icon with row 3 highlighted.

## 5. Do FSEvents for `~/Documents` reach an ad-hoc app without a privacy prompt?

1. Run `open -n $P --args fsevents`.
2. Watch for a prompt that asks to let MMSettle access files in your Documents folder. Do not click it yet. Write down whether it appeared and its exact words. Then click Don't Allow, so the test shows what the stream gets without the right.
3. Save any file under `~/Documents`, or wait. Git repos there change on their own.
4. After 60 seconds run `cat /tmp/mm-settle/fsevents.log`.

**Pass** when no prompt appeared and the log shows events with paths under `~/Documents`. If events arrive after Don't Allow, FSEvents is not gated by the Documents right, and only reading files is.

To run it again from the start, reset only this probe's right with `tccutil reset SystemPolicyDocumentsFolder no.guerrilla.minmacs.settle`.

## Clean up

```sh
rm -rf ~/Applications/MMSettle /tmp/mm-settle
```

Also remove MMSettle from System Settings > Notifications and from Login Items, if it is still there.
