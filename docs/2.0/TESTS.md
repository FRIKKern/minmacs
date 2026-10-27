# Settling tests

Issue #50, run on 2026-10-27. Each question from [PLAN.md](PLAN.md) section 9 has a test under `test/settling/<name>/`. This file gives, for each one, how it was tested, the raw result, the conclusion and what PLAN.md should do with it.

**The Mac.** MacBookPro18,1, 10 cores, 32 GB, macOS 27.0.1 build 26A434, APFS data volume. Microsoft Defender runs with its Endpoint Security extension. That matters for question 14.

**What ran and what did not.** Ten questions ran here, read-only or on fixtures in `$TMPDIR/minmacs-settling/`. Five need the owner at the screen, because they show a prompt, register something with the system or need someone to look at the menu bar. Their probe app and exact steps are in [test/settling/owner/README.md](../../test/settling/owner/README.md). The idle baseline ran for 11 minutes.

**Rerun.** `./test.sh settling/section` runs the fixture checks, 17 of them, after core. Two of them only check that the XPC probe and the owner probe build with no warnings. The default `./test.sh` does not pick up a subfolder, so the section runs only when named. Two checks read statfs, which other processes change at the same time, so each passes when one of three fresh runs agrees. Each folder's script reruns its own test. Before committing new output, run `test/settling/redact.py` on it, because this repo is public.

## Summary

| # | Question | Result | PLAN.md change |
|---|---|---|---|
| 1 | Notification permission for an ad-hoc app on macOS 27 | Needs the owner at the screen | None until the result |
| 2 | `SMAppService` from an ad-hoc bundle | Needs the owner at the screen | None until the result |
| 3 | Embedded XPC service from an ad-hoc bundle on macOS 14 | Works on macOS 27 with a macOS 14 target. Not run on macOS 14 | Run the check on a `macos-14` CI runner |
| 4 | Menu bar toggle hides all five icons | Needs the owner at the screen | None until the result |
| 5 | One status item opens another's menu at a row | Needs the owner at the screen | None until the result |
| 6 | `.ips` reports name the dispatch queue | Yes, for the crashed thread and the others | The queue label is the breadcrumb's first source |
| 7 | An autorelease pool explains WorkForest's spike | No. Whole `git log -p` output read into memory does | Add a streaming rule, keep the pool |
| 8 | `cmux events` needs a password outside cmux | No, in cmux's default automation mode | Read the mode from cmux's prefs |
| 9 | `~/.claude/sessions/<pid>.json` stable, and `shell` | Same shape in 7 releases. `shell` means idle with a background shell | Map four states, `shell` is not working |
| 10 | Codex `thread_turns.status` shows a live turn | The code writes `inProgress`. No live turn was seen | Fix the read-only open. One owner step left |
| 11 | Clone refcounts exact | Exact for full clones, after a short lag on delete. The clone-id rule is not exact | Change the Sizer rule |
| 12 | FSEvents for `~/Documents` without a prompt | Needs the owner at the screen | None until the result |
| 13 | What `tmp_cleaner` removes, who makes `$TMPDIR` families | Files in `/tmp` older than 3 days by all three times. Families from one test suite and from clang | Fix the clutter rows |
| 14 | What removing one pnpm worktree's `node_modules` frees | 3.2 MB of 1,669.6 MB du | Re-rank Wrap Up and the Sizer tiers |
| 15 | Idle cost of every running app | LocoHost 0.96 %, WorkForest 1.53 %, Insomnia 0.09 % CPU | Use as the phase 1 baseline |

## 1. Notification permission for an ad-hoc app on macOS 27

**How.** `MMSettle.app` mode `notify` asks for permission, posts one passive notification with an Undo action and logs each step. Asking shows a prompt, so it did not run here.

**Read-only check.** `~/Library/Preferences/com.apple.ncprefs.plist` was last written on 3 Nov 2025 and lists none of the current apps, so it no longer holds the answer on macOS 27. WorkForest, ad-hoc signed, calls `requestAuthorizationWithOptions:` at every launch, `workforest/Sources/main.m:369`.

**Result.** Needs the owner at the screen. The steps are in README section 1. The quickest answer is whether System Settings > Notifications lists WorkForest with notifications allowed.

**PLAN.md.** Nothing yet. If the owner's test fails, decision 13 makes the Developer account a requirement for the notifier, and B11's notifier falls back to a line in the expert's summary.

## 2. `SMAppService` from an ad-hoc bundle

**How.** `MMSettle.app` modes `login-on`, `agent-on` and their `-off` pairs register and unregister the main app service and a bundled LaunchAgent. Registering adds a login item, so it did not run here. Mode `login-status` only reads, and did run.

**Raw result.**
```
mode login-status, bundle $TMPDIR/minmacs-settling/owner/MMSettle.app, macOS Version 27.0.1 (Build 26A434)
mainAppService notFound
agent notFound
```

**Result.** Needs the owner at the screen. `notFound` is the state before any registration for a bundle launchd has not seen. LocoHost and WorkForest already call `SMAppService.mainAppService` from ad-hoc bundles behind their Launch at Login switch, `locohost/Sources/main.m:1475` and `workforest/Sources/main.m:984`. If either starts at login today, the main app service works. The agent service is still open.

**PLAN.md.** Nothing yet. Decision 18 depends on the main app service only.

## 3. Embedded XPC service from an ad-hoc bundle on macOS 14

**How.** `test/settling/xpc/build.sh` builds `MMXPCProbe.app` with `MMProbeWorker.xpc` inside, both ad-hoc signed and built with `-mmacosx-version-min=14.0`. The host has no window. It calls the service once cold, 100 times warm, and asks it to walk a fixture folder. It ran from the bundle, through a symlink as the installed CLI runs, and from a fresh bundle reached first through a symlink.

**Raw result.**
```
cold start and first reply: 18.2 ms, service pid 16377
100 warm calls: 0.040 ms per call
walk of .../xpc-fixture in the service: 2 files, 8192 bytes, pid 16377
PASS
    minos 14.0
Signature=adhoc
via symlink: cold start and first reply: 13.5 ms        PASS
fresh bundle, first run via symlink: cold start and first reply: 21.0 ms, 0.058 ms per call   PASS
```
After `invalidate` the service process was gone. Through a symlink `NSBundle.mainBundle` reports the symlink's folder, and the service is still found.

**Conclusion.** An ad-hoc bundle launches its embedded XPC service on macOS 27, also through the CLI symlink. This Mac cannot run macOS 14, so the macOS 14 part is open.

**PLAN.md.** Keep the XPC choice in section 3 conditional, and name the way to settle it. CI runs `./test.sh settling/section` on a `macos-14` runner, whose XPC checks are the four that name the XPC probe. Track B's 13.9 ms cold start holds, at 13.5 to 21.0 ms here.

## 4. Menu bar toggle hides all five icons of one app

**How.** `MMSettle.app` mode `icons` makes five square status items with `autosaveName` `minmacs.settle.<expert>` and removal allowed, as section 7 plans. Every second it logs each item's `isVisible`, whether its window is on screen and its x position.

**Result.** Needs the owner at the screen. The steps are in README section 3.

**PLAN.md.** Nothing yet. The log also shows whether `isVisible` stays true while the system hides an icon, which SYNTHESIS.md section 2 rule 3 assumes.

## 5. One status item opens another's menu at a given row

**How.** `MMSettle.app` mode `crosslink` makes items A and B. It opens B's menu in two ways and logs `menuWillOpen`, `menu:willHighlightItem:` and `menuDidClose`. Way 1 is `popUpMenuPositioningItem:atLocation:inView:` with row 3 at B's button. Way 2 is `performClick:` on B's button, then three Down Arrow events the app posts to itself, which needs no Accessibility right. The menus close themselves after three seconds.

**Result.** Needs the owner at the screen, since a menu opens on the screen and its position has to be seen. The steps are in README section 4.

**PLAN.md.** Nothing yet. If neither way highlights row 3, cross-links open the other expert's menu at the top, and the card the link names is the first row below the header.

## 6. `.ips` crash reports name the dispatch queue

**How.** `test/settling/ips-queue/crash.c` is a command-line tool, so its crash shows no dialog. It parks a block on queue `no.guerrilla.minmacs.settle.idle`, then traps inside a `dispatch_sync` block on `no.guerrilla.minmacs.settle.crash`. `read.py` reads the report.

**Raw result.**
```
report mm-ips-probe-2026-10-27-172513.ips bug_type 309 os macOS 27.0.1 (26A434)
exception EXC_BREAKPOINT SIGTRAP
faultingThread 0
  thread 0: triggered=True queue=no.guerrilla.minmacs.settle.crash name=None
  thread 1: triggered=False queue=no.guerrilla.minmacs.settle.idle name=None
asi null
```
The report is in `~/Library/Logs/DiagnosticReports/`. The owner may delete it. The six older reports on this Mac show the same `queue` field, with `com.apple.main-thread` only.

**Conclusion.** Yes. Each thread's `queue` field holds the label of the queue it was running, for the crashed thread and for the others.

**PLAN.md.** This changes section 3, Threads, and section 10, One process for all. The queue label `no.guerrilla.minmacs.<expert>.<job>` already names the expert and job in every crash report. The crash breadcrumb only needs what the label cannot hold, such as the work item. A job that runs on a global queue loses this, which is one more reason for labeled serial queues.

## 7. An autorelease pool explains WorkForest's memory spike

**How.** Four steps, all read-only.
1. `autorelease/catch-spike.sh` waited for WorkForest's next scan and took `vmmap --summary` at 1.1 GB. `catch-stack.sh` ran `sample` for 3 seconds in the next spike.
2. `autorelease/scan.m` runs WorkForest's disk walk and four of its git calls the way `readAll` does, six worktrees at a time on the global utility queue. It ran with no pool, a pool per worktree and a pool per directory entry, over 7 worktrees with 996,130 files.
3. `autorelease/sessions.m` compiles WorkForest's own `Sessions()` code, taken from `Trees.m` at build time, and runs it over WorkForest's 117 worktrees.
4. The sample pointed at `ReadFacts`, so `log-sizes.sh` measured the `git log -p -n 400` that `DefaultPatchIds()` reads per repo, and `patchids.m` runs that code in three modes.

**Raw result.**
```
vmmap during the spike:  Physical footprint 1.1G, peak 4.1G
  Malloc Large (empty)   1.0G virtual, 987.9M resident, 10 regions
sample during the spike: ReadFacts > dataUsingEncoding > __CFToUTF8                                   298 ms
                         ReadFacts > WFGitInput > __CFStringCreateImmutableFunnel3 > __CFFromUTF8      96 ms
                         ReadFacts > WFGitInput > stringByTrimmingCharactersInSet > memmove           44 ms

scan.m, 7 worktrees, 996,130 files:   none 12 MB   item 11 MB   dir 12 MB   peak footprint
sessions.m, 117 worktrees:            none 28 MB   item 29 MB   pool per log file 16 MB

git log -p -n 400 per repo, bytes:  2,279,287,237   442,746,275   316,776,002   143,550,567   119,291,265 ...
patchids.m on the three repos of 144, 119 and 52 MB:
mode none   ids 878  time 7.7 s  peak 1192 MB  after 3 s 1192 MB
mode item   ids 878  time 4.5 s  peak 1652 MB  after 3 s 1652 MB
mode stream ids 881  time 3.0 s  peak 3 MB     after 3 s 3 MB
```
The repo whose log is 119 MB had its default branch move 4 minutes before the run, so WorkForest's patch-id cache was stale. `SquashMerged()` also reads a whole diff before it checks the 8 MB limit, but the largest diff here was 5.3 MB.

**Conclusion.** No. A missing pool is not what spikes. The walk and the session reader stay under 30 MB with or without a pool. The spike comes from `DefaultPatchIds()`, `workforest/Sources/Trees.m:104-129`. It reads a whole `git log -p` into an `NSData`, decodes it to a string, trims it, appends a newline and encodes it again, so each byte of git output costs several bytes of memory. A pool per repo did not lower the peak. Piping git log straight into git patch-id did, from 1,192 MB to 3 MB. Freed large buffers stay in the footprint as `Malloc Large (empty)` for minutes, which is why WorkForest's RSS falls slowly after each scan.

**PLAN.md.**
- Section 3, Threads. Keep the pool per work item. It halved the session reader's peak. Drop the claim that it explains the spike.
- Section 3, Know, or Runtime. Add a rule that no tool output is read whole. Output that feeds another tool goes through a pipe. Output Core parses is read with a byte limit, and the child is stopped at the limit.
- Phase 2. The WorkForest port replaces `DefaultPatchIds()` with a pipe. Its "Done when" peak of 300 MB is then easy to meet.
- Decision 15 allows bug fixes in the standalone apps. The same pipe fix in WorkForest removes its 4.1 GB peak today. This needs an issue in the WorkForest repo, which this test did not open.

## 8. `cmux events` needs a password outside a cmux terminal

**How.** `cmux-events/run.sh` reads one replayed event in four ways. It reads from inside this cmux shell, with every `CMUX_*` variable removed, the same without `CMUX_SOCKET_PATH`, and from a reader whose parent exits first, so launchd adopts it and no cmux process is among its ancestors. It never passes a password.

**Raw result.**
```
inside                 exit 0  first bytes: {"boot_id":"F45068D3-...","filters":{...},"heartbeat_interval_seconds":15
bare-env               exit 0  first bytes: {"boot_id":"F45068D3-...",...
bare-env-default-path  exit 0  first bytes: {"boot_id":"F45068D3-...",...
orphan                 exit 0  first bytes: {"boot_id":"F45068D3-...",...
orphan parent: ppid 1
  "access_mode" : "automation",
```
Each output holds the ack frame and one replayed `window.keyed` event. The reader asked for any category. E2 plans `--category agent`, and that filter was not run. `defaults read com.cmuxterm.app` shows `socketControlMode = automation`.

**Conclusion.** No password is needed in cmux's automation mode, the mode this Mac runs. A process with no cmux ancestor and no cmux variables reads the stream, and the CLI finds the socket without `CMUX_SOCKET_PATH`. cmux version 0.64.22. In password mode the CLI takes `--password`, `CMUX_SOCKET_PASSWORD` or the password saved in cmux's settings, so a reader would then need one.

**PLAN.md.** Section 3, Know, Agents, keeps E2's single `cmux events` reader. Core reads `socketControlMode` from the `com.cmuxterm.app` prefs domain, without running cmux. In any mode other than automation the cmux source is unavailable, and the reason shows dimmed in place, as decision 12 says.

## 9. `~/.claude/sessions/<pid>.json` across releases, and what `shell` means

**How.** `claude-sessions/check.py` groups the live status files by version and key set. It then searches every installed Claude Code binary for the code that writes the file. The patterns match the shape of the minified code, not its names.

**Raw result.**
```
2.1.300: 12 files, status {'idle': 11, 'busy': 1}      2.1.301: 2 files, idle 2
2.1.302: 1 file, busy 1      2.1.306: 2 files, idle 2      2.1.310: 2 files, busy 1 idle 1      2.1.311: 1 file, shell 1
keys in every file: cwd,entrypoint,kind,messagingSocketPath,name,nameSince,nameSource,peerFeatures,peerProtocol,pid,
                    pidDomain,procStart,sessionId,startedAt,status,statusUpdatedAt,updatedAt,version
one 2.1.300 file adds bridgeSessionId

binaries 2.1.300 2.1.301 2.1.302 2.1.306 2.1.307 2.1.310 2.1.311, each:
  status list=1 idle to shell=1 running bash task=1 status map from SDK=1 waiting reasons=1 busy or shell is working=3
```
The code in 2.1.311, minified names as they are:
```
var p=["busy","shell","idle","waiting"];function c(n){return p.includes(n)?n:void 0}
let qo=V(tUo),un=go==="idle"&&qo?"shell":go          tUo: Object.values(tasks).some(t => t.type==="local_bash" && !done(t.status))
{running:"busy",requires_action:"waiting",idle:"idle"}   waitingFor: "input needed" or "permission prompt"
if(R==="busy"||R==="shell")return{word:Ao.working,...}
```
In a live check, the one session in `shell` had a child `zsh` running `npm run desktop` for 1 hour 53 minutes.

**Conclusion.**
- The file has four states. `busy` is a running turn. `waiting` is a turn blocked on the person, and `waitingFor` says whether on input or on a permission prompt. `idle` is no turn. `shell` is no turn while a background shell task that Claude Code started still runs.
- The key set and the status code are the same in all 7 releases installed here, 2.1.300 to 2.1.311, from 14 to 26 October. That is 12 days of releases. The file is still undocumented.
- Claude Code itself counts `shell` as working in its agent list. For MinMacs it is not, because a dev server started from a session can run for hours.

**PLAN.md.** In section 3, Know, Agents, and E1, map `busy` to working, `waiting` to waiting with the reason from `waitingFor`, `idle` to idle, and `shell` to idle with a background shell. Insomnia does not keep the Mac awake for `shell` alone. LocoHost links the shell's child server to the session. An unknown value maps to unknown, as Claude Code's own parser does. Keep the `caffeinate` fallback, since the format has no promise behind it.

## 10. Codex `thread_turns.status` shows a live turn

**How.** `codex-turns/check.sh` reads the turn table and the SQL inside the installed Codex CLI 0.154.0. No Codex process ran, and starting a turn would use the owner's account, so `codex-turns/watch.sh` is the owner step. It prints the newest turn's status once a second while the owner runs a turn.

**Raw result.**
```
header write/read version: 2 2                      (WAL)
mode=ro open: unable to open database file (14)
using immutable=1
completed|591|0     failed|1|0     interrupted|8|4      (status, count, rows with no completed_at)
projection offset equals the rollout size for all 26 threads written in the last 14 days
SQL in the Codex CLI that names inProgress: 5 + 10
  INSERT INTO thread_turns ... ON CONFLICT(thread_id, turn_id) DO UPDATE SET ... status = excluded.status ...
  WHERE thread_turns.rollout_end_ordinal IS NULL AND thread_turns.status = 'inProgress'
  UPDATE thread_turns SET final_agent_item_id = ? WHERE ... AND status = 'inProgress'
```

**Conclusion.**
- The CLI's SQL writes a turn row with status `inProgress` and updates it in place while `rollout_end_ordinal` is null. So a live turn should show `inProgress`. No live turn was seen, so this is still the code's word, not an observation.
- The table keeps up with the rollout files. Each thread's projection offset equals its rollout file's size.
- The plan did not expect this one. `mode=ro` fails on this file. The database is in WAL mode and has no `-wal` or `-shm` file when no Codex runs, and a read-only connection cannot create the `-shm`. `immutable=1` works then, and is safe only while nothing writes.

**PLAN.md.** In section 3, Know, Agents, Codex's SQLite is opened with `mode=ro` when the `-shm` file exists, which means Codex has it open, and with `immutable=1` when it does not. The owner runs `watch.sh` once during a Codex turn to close the question.

## 11. Clone refcounts on a volume with clone mapping valid but not set

**How.** `clone-refcounts/clones.c` works in a fixture folder. It makes a 16 MB random file, two clones, a clone of a clone and a hard link, changes one 4 KB block of one clone, clones that clone, and deletes files step by step. After each step it prints clone id, refcount, private size and flags. For seven sets it compares three answers to "what does deleting this free": the private size sum, the rule SYNTHESIS.md A3 proposes, which counts a clone id's size once when every holder is in the set, and the truth from the extent union of every fixture file. It reads the statfs delta of each real delete. Its `lag` mode measures how soon refcounts change after `clonefile` and after `unlink`.

**Raw result.**
```
volume /System/Volumes/Data (apfs): clone valid 1 set 1, clone mapping valid 1 set 0
-- base, c1 and c2 are clones of base        each: cloneid 149511592 refcnt 3 flags 0x41
-- c3 is a clone of c1                       each: refcnt 4
-- hl is a hard link to base                 each: refcnt 4, hl has the same inode as base
-- one block of c2 changed                   c2: private 0.02 MB, new cloneid, refcnt 1, flags 0x1. The others: refcnt 3
-- c4 is a clone of c2                       c2 and c4: refcnt 2, flags 0x41
-- what deleting each set frees               priv     rule    truth MB
   {c2,c4}                                    0.00    16.00     0.02
   {base,hl,c1,c3}                            0.00    16.00     0.02
   {all}                                      0.00    32.00    16.02
-- after c1, c3 and c4 are deleted
   {base,hl,c2}                               0.03     0.03    16.02
-- statfs delta:  delete c3  0.00 MB    delete c4  0.00 MB    delete base and hl  16.00 MB
lag: 0 of 300 trials read a stale refcount right after clonefile
lag: 51 of 300 trials read a stale refcount right after unlink; longest wait 11.4 ms
```

**Conclusion.**
- Refcounts are exact for full clones on this volume, even with clone mapping not set. A refcount counts the file itself and every full clone. A hard link is the same inode and does not count. Changing one block takes a file out of its family at once.
- After `unlink`, the other clones still show the old refcount for up to 11.4 ms, in 51 of 300 trials. After `clonefile` the count was right every time.
- The clone-id rule is not exact. A partial clone shares blocks with a family it no longer belongs to, and no flag shows that. The rule said 16 MB where 0.02 MB is freed, and 0.03 MB where 16.02 MB is freed. The extent union matched statfs within 0.02 MB every time.
- The rule is exact when no file in play is a partial clone. A pnpm store never edits its files, so pnpm families meet that.

**PLAN.md.** In section 3, Know, Sizes, tier 1, and A3, count a clone id once when all its holders are in the set, by refcount, and call the result an estimate. A size is "what deleting frees" only from the extent union or after the action, from the statfs delta. Read refcounts again when a delete happened in the last 100 ms. Question 14 shows the extent union is too slow for large trees on this Mac.

## 12. FSEvents for `~/Documents` without a privacy prompt

**How.** `MMSettle.app` mode `fsevents` watches `~/Documents` with file events for 60 seconds and logs each batch. It must start as its own app through `open`. A tool started from a terminal borrows the terminal's rights and proves nothing, so it did not run here.

**Result.** Needs the owner at the screen. The steps are in README section 5.

**PLAN.md.** Nothing yet. If a prompt appears, section 1 principle 2 needs the stream to start on the first function that needs it, not at launch. WorkForest already walks `~/Documents/GitHub` from an ad-hoc bundle, so the owner may already have granted that right to WorkForest. That grant does not carry over to MinMacs.

## 13. What `tmp_cleaner` removes, and who makes the `$TMPDIR` families

**How.** `tmp-cleaner/check.sh` prints the launchd job and the script, counts files in `/private/tmp` by which of their three times are old, and groups `$TMPDIR` by name with the random suffix cut off. `fixture.sh make` left a fixture that the owner checks after four nights, because a file's ctime cannot be set back. The family names were searched in the code under `~/Documents/GitHub` with `rg`, and a MinMacs build was diffed against `$TMPDIR`.

**Raw result.**
```
com.apple.tmp_cleaner: /usr/libexec/tmp_cleaner, StartCalendarInterval Hour 0, Nice 1, LowPriorityIO
the script, in short:
  daily_clean_tmps_dirs="/tmp"  daily_clean_tmps_days="3"
  find -dx . -fstype local -type f -atime +3 -mtime +3 -ctime +3 ! -name .X*-lock ... -delete
  find -dx . -fstype local ! -name . -type d -empty -mtime +3 ! -name .vfs_rsrc_streams_* ... -delete
/private/tmp at 2026-10-27T16:03:51Z
files:                           209843
all of atime mtime ctime > 3d:        8     all from 23 Oct, due at the next run
all three > 4d:                       0
mtime > 3d, atime newer:          11215
mtime, atime > 3d, ctime newer:     5104
survivors with an old mtime: 16320 in claude-501, 7 in com.microsoft.autoupdate.fba.*
com.apple.bsd.dirhelper: CLEAN_FILES_OLDER_THAN_DAYS=3, daily at 03:35. It owns $TMPDIR, not tmp_cleaner.
$TMPDIR families                  count  oldest      newest      size
   server-budget                    745  2026-10-07  2026-10-27  11880 KB
   collapse-fixpoint                606  2026-10-09  2026-10-27    180 KB
   mv-test                          404  2026-10-09  2026-10-27    120 KB
   main                             322  2026-10-05  2026-10-27      0 KB
   full-pipeline-test               202  2026-10-09  2026-10-27    180 KB
   full-pipeline-missing            202  2026-10-05  2026-10-27      0 KB
   Rules, Review, Ports, Trees, Forest, Common, Intel     58 to 150 each, 0 KB
one MinMacs build added: main-844910 main-9d7184 MMCLI-730159 MMCLI-8de592 MMCard-242475 ... MMStatusItem-e75b3e
```

**Conclusion.**
- `tmp_cleaner` is a 35-line shell script. Every night at 00:00 it deletes files under `/tmp`, which is `/private/tmp`, whose atime, mtime and ctime are all more than 3 days old. Then it deletes empty folders whose mtime is more than 3 days old. It stays on the local volume and skips a few X11 names. Noo-Noo's comment that macOS never sweeps `/private/tmp` is wrong.
- It does run. No file left in `/private/tmp` has all three times older than 4 days.
- A file that something keeps reading or touching never goes. 16,320 such files sit under `claude-501`, the temp folder of Claude Code sessions. What reads them was not traced.
- A folder goes only once it is empty, and the night its last file goes counts as a change to the folder. So by the script, an empty folder goes about three nights after its last file, and each level of a nested tree adds about three nights. This was read from the script, not seen yet.
- The large `$TMPDIR` families come from two places. `server-budget`, `collapse-fixpoint`, `mv-test` and `full-pipeline-*` come from one client repo's vitest suite, which calls `mkdtempSync` and never removes the folder. A code search outside `node_modules` found all four in 2.5 seconds. `main-*` and the source-named families are empty folders that clang leaves, one per source file and arch, on every universal build. The MinMacs build itself adds two per source file.

**PLAN.md.**
- Section 3, Know, Clutter, and the D-clutter `private-tmp` row. The system sweeps `/private/tmp`. Noo-Noo reports only what the sweep will not reach, which is files kept alive by reads and full folders older than 3 days. It never removes what the sweep removes the same night.
- The `tmpdir-families` row. The family's owner comes from a code search outside `node_modules`, as D4 proposes. It found every large family on this Mac. Empty clang folders are their own row, report-only, since they hold no bytes.
- The owner checks the fixture with `test/settling/tmp-cleaner/fixture.sh check`. It was made on 27 October at 17:42, so its files and `emptydir` are due at the 00:00 run on 31 October. `full/deep` is due about three nights later and `full` about three nights after that. The fixture sits inside `claude-501`, where most old survivors are, so a file there that is kept may be kept by the same unknown reader. A second fixture made with `MM_TMP_FIXTURE=/private/tmp/mm-tmp-cleaner-fixture fixture.sh make` rules that out.

## 14. What removing one pnpm worktree's `node_modules` frees

**How.** The set is the 17 `node_modules` folders of one pnpm worktree, with `.next` left out. pnpm imports by clone here, and its store is `~/Library/pnpm/store/v10`.
- `pnpm-freed/freed.c` is the extent union. It maps every file's physical extents with `F_LOG2PHYS_EXT` and counts what no file outside the set holds.
- `pnpm-freed/bulk.c` opens no file. It reads private size, clone id and refcount for every file with `getattrlistbulk`, and checks per clone id whether every holder is in the set.
- `pnpm-freed/opens.py` times one open per file against one lstat per file, to show what an on-access scanner adds.
- `pnpm-freed/fixture.sh` checks both against a real delete on a fixture. It has a fake store of 200 files, a `node_modules` of 150 clones and 40 MB of its own files, and one clone with a changed block.

**Raw result.**
```
fixture   freed.c freed 40.0 MB    bulk.c estimate 40.0 MB    statfs delta on delete 40,812 KB
real set: 124019 files in 18484 folders, 123262 share all blocks, 2 share some, 0 hard-linked
du                                     1669.6 MB
private, freed for sure                   3.2 MB
clone ids held only by the set            0.0 MB  (0 ids)
clone ids also held elsewhere          1476.7 MB  (96491 ids, all 96491 also in the store or the sibling worktrees)
estimate freed = private + ids held only by the set: 3.2 MB
bulk.c time: 22.3 s with the store, 51.3 us per file. With the store and 7 sibling worktrees: 82.0 s, 62.8 us per file

file opens, builder's run, output not saved: 3000 files in 18.99 s, 6.33 ms per open. lstat of the same files: 0.014 s
freed.c on the set and the store was stopped after 22 minutes, still opening files

opens.py, review rerun on 3000 store files, saved in pnpm-freed/opens-result.txt:
  first pass   4.91 ms per open, lstat 0.450 s
  second pass  0.34 ms per open, lstat 0.013 s
  1000 new files of 2 bytes in a temp folder: 0.40 ms per open
```

**Conclusion.**
- Deleting this worktree's `node_modules` frees about 3.2 MB. du says 1,669.6 MB. Every shared clone id is also held by the store or by sibling worktrees, so the clones free nothing. Folder records come on top and were not measured.
- The clone accounting from question 11 agrees with the extent union and with statfs on the fixture.
- The extent union cannot run before an action on a tree this size on this Mac. The first open of a file costs 4.9 to 6.3 ms. A second open of the same file costs 0.34 ms, so the cost is a check on first open. Microsoft Defender's Endpoint Security extension is the likely cause. It was not turned off to prove it. freed.c opens the store's 311,096 files as well as the set's 124,019, so a run needs 36 to 46 minutes. That is why it was still opening files at 22 minutes. `getattrlistbulk` opens only folders and is not slowed.

**PLAN.md.**
- Section 3, Know, Sizes. Tier 2 runs the extent union only on small sets, such as one leak family, under a time budget. A large set uses the clone accounting from question 11, called an estimate. The statfs delta in the undo record stays as the measured number.
- Section 6, Wrap Up, and D7. On a pnpm clone install a worktree's `node_modules` frees almost nothing. Ranking by freed size puts it last, and the menu shows the freed size, not du. The space sits in the pnpm store, which `pnpm store prune` cleans under decision 1.
- Section 10, Risks. Macs with an on-access scanner make every file open slow. No periodic job opens files one by one.

## 15. Idle cost of every running app

**How.** `baseline/sample.sh` ran for 11.1 minutes, from 15:54:35 to 16:05:52 UTC. It took `ps` every 10 seconds and `vmmap --summary` at the start, the middle and the end, for each app that ran. `baseline/summarize.py` turns the cumulative CPU time into a percent. The raw output is in `test/settling/baseline/raw/`. LocoHost, WorkForest and Insomnia ran. MinMacs 1.2 and Noo-Noo did not, so they have no baseline.

**Raw result.**
```
app         samples minutes   cpu s  cpu %  rss MB min-max  footprint start/mid/end    peak
LocoHost         66    11.1    6.38   0.96    70.3-83.9       32.8M/36.7M/33.2M     56.1M
WorkForest       66    11.1   10.20   1.53    68.7-3006.1     51.2M/51.3M/114.4M     4.1G
Insomnia         66    11.1    0.60   0.09    31.8-33.9       47.0M/47.0M/47.0M     52.1M

LocoHost    quietest 5 min 15:59:45-16:04:46 UTC: 0.93 % CPU
WorkForest  quietest 5 min 15:55:22-16:00:33 UTC: 0.08 % CPU
Insomnia    quietest 5 min 16:00:33-16:05:37 UTC: 0.06 % CPU
```
WorkForest scanned twice in the window. Its RSS went from 93 MB to 3,006 MB at 15:55:01 with 6.5 s of CPU, and fell back to 86 MB by 15:57:13. The second scan, at 16:01:03, peaked at 285 MB.

**Conclusion.**
- Together the three apps use 2.58 % CPU over 11 minutes and 131 MB of footprint at rest.
- LocoHost costs about 0.95 % CPU all the time, which is above the phase 1 target of 0.5 % on its own.
- WorkForest is cheap between scans, at 0.08 % CPU, and very expensive during one. Its 4.1 GB lifetime peak is question 7's patch log.
- Insomnia is the quietest, at 0.09 % CPU and 47 MB.

**PLAN.md.** Phase 1's numbers in section 9 stand: 50 MB idle footprint and 0.5 % idle CPU, from H4. This table is the baseline they are measured against. LocoHost alone uses 0.96 % CPU today, so phase 1 must about halve LocoHost's CPU while it also does MinMacs 1.2's work. LocoHost's 33 MB footprint is under the 50 MB target. The README figure for C13 comes from rerunning `sample.sh` against MinMacs 2.0.

## Left open

- Questions 1, 2, 4, 5 and 12 need the owner, with the steps in `test/settling/owner/README.md`.
- Question 3 needs a run on macOS 14, best on a `macos-14` CI runner.
- Question 10 needs one Codex turn with `codex-turns/watch.sh` running.
- Question 13's fixture is checked from 31 October for its files and its empty folder, and again later for `full/deep` and `full`. A second fixture outside `claude-501` would rule out the unknown reader.
- What keeps reading the files under `/private/tmp/claude-501` was not traced.
- The 6.33 ms open time and the 22-minute freed.c run have no saved output. The review rerun of `opens.py` is saved and gives 4.91 ms.
