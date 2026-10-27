# Research B: the fastest and cheapest way to know things on macOS

Track B of the MinMacs 2.0 research, GitHub issue FRIKKern/minmacs#2.

**Summary.**
- The whole Senses pass runs from the kernel and IOKit, with no subprocess. One pass over 860 processes, with energy and every socket of this user, costs about 6.3 ms of CPU. Replacing the three private walks in MinMacs, LocoHost and WorkForest with one pass saves two of those every tick.
- Exits are free to watch. kqueue `NOTE_EXIT` registered on all 864 pids, root's included, in 0.4 ms, and idle costs nothing. Launches still need the 5-second pass, because the only push source for them, Endpoint Security, needs an entitlement from Apple.
- Every power, thermal, memory and lid fact reads in 0.2 to 124 microseconds from IOKit or sysctl. The `pmset -g` subprocess that Insomnia runs today to read the lid override costs about 80 ms. The same value is the `SleepDisabled` property on `IOPMrootDomain`.
- For sizing, `getattrlistbulk` with `ATTR_CMNEXT_PRIVATESIZE` knows about APFS clones in one call per directory. On `barkpark/node_modules`, du reports 1.5 GB, and the private size is 2.8 MB, because 73,202 files are clones from the pnpm store. It costs about the same CPU as an fts walk.
- FSEvents delivers in 11 to 13 ms with `NoDefer` or `FileEvents` (unverified). A warm start must replay from a saved event id. Passing 0 replayed the whole store, 494,887 events in 93 s.
- An XPC service inside an ad-hoc signed bundle works: 14 ms cold start, 0.03 ms per round trip. That gives crash isolation for heavy scanners without a developer account.
- App Intents ships only as a Swift module, so it cannot be written with clang alone. Shortcuts can still drive the `minmacs` CLI and the URL schemes.
- Claude Code starts `caffeinate -i -t 300` while it works. Insomnia can read that from the power assertion table without polling any binary.

**How the numbers were taken.** Every number below comes from a small read-only C or Objective-C program in `/private/tmp/claude-501/minmacs-research-B/`, compiled with `clang -O2` (Apple clang 17.0.0) and run on this Mac. This Mac is an Apple M1 Pro with 10 cores and 32 GB, running macOS 27.0.1 build 26A434 (`sw_vers`, `sysctl hw.memsize hw.ncpu machdep.cpu.brand_string`). The programs ran under the Claude Code shell, which may add sandbox overhead. Timings are wall time unless the text says CPU. The program for each fact is named in that fact's section.

## The table

| Fact | Best API | Cost on this Mac | Permission or entitlement | Works ad-hoc signed? | Objective-C call |
|---|---|---|---|---|---|
| Process list | `proc_listpids(PROC_ALL_PIDS)`, then `proc_pidinfo(PROC_PIDTBSDINFO)` | 16 to 21 µs for the list, about 0.9 ms for bsdinfo on 860 pids (procs.c) | None. bsdinfo fails for the 229 processes of other users | Yes. procs ran with only the linker's ad-hoc signature (`codesign -dv procs` shows `flags=0x20002(adhoc,linker-signed)`) | `proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bi, sizeof bi)` |
| Whole process table, root's included | `sysctl {CTL_KERN, KERN_PROC, KERN_PROC_ALL}` | 0.37 ms for all pids in one call (procs.c) | None | Yes | `sysctl(mib, 3, buf, &len, NULL, 0)` |
| CPU, memory, energy per process | `proc_pid_rusage(RUSAGE_INFO_V6)` | 2.1 to 2.4 ms for 630 own pids (procs.c) | Own processes only. 230 pids refused (energy.c) | Yes | `proc_pid_rusage(pid, RUSAGE_INFO_V6, (rusage_info_t *)&ru)` |
| Process exit | kqueue `EVFILT_PROC` with `NOTE_EXIT` | 0.47 µs per pid to register, nothing while idle. Exit of a `sleep 0.2` child seen 222.7 ms after the spawn (kq.c) | None. Registered on pid 1, owned by root | Yes | `EV_SET(&ev, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL)` |
| Process launch | The 5-second pass. Endpoint Security is the only push source | 6.3 ms CPU per full pass (procs.c) | Endpoint Security needs `com.apple.developer.endpoint-security.client`, which "you must request from Apple" ([Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.endpoint-security.client)) | Pass: yes. ES: no | See Senses below |
| App launch, quit, activate | `NSWorkspace.notificationCenter`, `NSWorkspaceDidLaunchApplicationNotification` and peers | Nothing while idle. `runningApplications` reads 97 apps in 8.7 µs (power.m) | None | Yes. MinMacs 1.2 reads `runningApplications` at legacy `Sources/Scanner.m:138`. It does not observe the notifications (no `notificationCenter` in legacy `Sources`) | `[ws.notificationCenter addObserver:… name:NSWorkspaceDidTerminateApplicationNotification …]` |
| Sockets and ports | `proc_pidinfo(PROC_PIDLISTFDS)`, then `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` | 1.1 to 1.2 ms to list 9,359 fds, 1.3 to 1.4 ms for 812 sockets, 1.6 to 1.7 µs per socket (procs.c) | Own processes only | Yes | LocoHost `Sources/Ports.m:326` |
| Same, through lsof | `lsof -nP -iTCP -sTCP:LISTEN` | 40 to 70 ms wall, 20 to 50 ms CPU per run (`/usr/bin/time -p`) | None | Not applicable | Avoid |
| Bytes per process or socket | ntstat kernel control socket `com.apple.network.statistics` | Connect works. Queries not measured | `nettop` holds `com.apple.private.network.statistics` (`codesign -d --entitlements - /usr/bin/nettop`). The kernel skips the check for classic providers when `net.statistics_privcheck` is 0, which it is here | Connect: yes (nstat.c, `Signature=adhoc`). Queries: not tested | Private structs from XNU `bsd/net/ntstat.h` |
| Folder changed | FSEvents, `FSEventStreamCreate` on a dispatch queue | 11 to 13 ms latency with `NoDefer` or `FileEvents` (unverified). 23.5 ms CPU for 6,463 live events in 20 s on `~/Documents/GitHub` (unverified) (fse.m, fse3.m) | None for folders the user owns. Protected folders such as Desktop or Documents may need consent (guess, not tested from an app bundle) | Yes | See Folders below |
| Size of a tree, clone-aware | `getattrlistbulk` with `ATTR_FILE_ALLOCSIZE` and `ATTR_CMNEXT_PRIVATESIZE` | About 21 µs CPU per file. 78,247 files in 1.6 to 2.2 s CPU (sizer.c) | None | Yes | See Folders below |
| Thermal state | `NSProcessInfo.thermalState` and `NSProcessInfoThermalStateDidChangeNotification` | 0.2 µs per read (power.m) | None | Yes, Insomnia uses it (`Sources/main.m:132`) | `NSProcessInfo.processInfo.thermalState` |
| Memory pressure | `dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE)`, with `kern.memorystatus_vm_pressure_level` as the poll | Nothing while idle. The sysctl reads in 1.4 µs (power.m) | None | Yes, LocoHost uses it (`Sources/main.m:856`) | See Energy and heat below |
| Energy per process | `ri_energy_nj` in `rusage_info_v6` | Part of the rusage call. A 1 s spin read 1.37 J (energy.c) | Own processes only | Yes | `ru.ri_energy_nj` delta over wall time |
| Lid state | `IOPMrootDomain` property `AppleClamshellState`, and `kIOPMMessageClamshellStateChange` | 10.6 µs per read (power.m) | None | Yes, Insomnia uses it (`Sources/main.m:118`, `:283`) | See Power and lid below |
| Lid override is on | `IOPMrootDomain` property `SleepDisabled` | One registry read, about 10 µs (guess from the clamshell read). `pmset -g` costs 80 ms (power.m) | Read: none. Write: root | Yes | Same as the lid read, key `SleepDisabled` |
| Who keeps the Mac awake | `IOPMCopyAssertionsByProcess`, `IOPMCopyAssertionsStatus` | 124 µs and 60 µs. `pmset -g assertions` costs 92 ms (power.m) | None | Yes | `IOPMCopyAssertionsByProcess(&dict)` |
| Keep awake | `IOPMAssertionCreateWithName` | Not measured, to keep the Mac's power state untouched | None | Yes, Insomnia does it (`Sources/main.m:545`) | `IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep, …)` |
| Battery and power source | `IOPSCopyPowerSourcesInfo` and `IOPSGetProvidingPowerSourceType` | 59 µs (power.m) | None | Yes | `IOPSGetProvidingPowerSourceType(info)` |
| Launch at login | `SMAppService.mainAppService` | Not measured | User approval in System Settings | Yes, LocoHost, WorkForest and Insomnia ship ad-hoc and use it (`build.sh:13`, LocoHost `Sources/main.m:1475`) | `[SMAppService.mainAppService registerAndReturnError:&e]` |
| Bundled LaunchAgent or daemon | `+[SMAppService agentServiceWithPlistName:]`, `daemonServiceWithPlistName:` | Not measured | Daemons need notarization and admin approval (SMAppService.h line 55 and line 161) | Agent: not tested. Daemon: no | See Background below |
| Heavy work in its own process | XPC service in `Contents/XPCServices`, `xpc_connection_create` or `NSXPCConnection` | 13.9 ms cold start, 0.03 to 0.04 ms per round trip (xpc/host.c) | None | Yes (tested, `Signature=adhoc`) | See Background below |
| Shortcuts and Siri | App Intents | Not usable from clang | None | Not applicable | Swift only. See Other surfaces below |
| Notification buttons | `UNNotificationCategory` with `UNNotificationAction` | Not measured | User consent for alerts | Not proven on this Mac. See Open questions | See Other surfaces below |

## Senses: processes and sockets

**What the three apps do today.** MinMacs 1.2, LocoHost and WorkForest each walk the process table on their own timers:
- MinMacs 1.2 walks with `proc_listpids` and `proc_pid_rusage(RUSAGE_INFO_V4)` (legacy `Sources/Scanner.m:106` and `:119`).
- LocoHost walks every 5 s (`Sources/main.m:862`) with rusage v6 and energy (`Sources/Ports.m:444` to `:464`). It then scans the sockets of every own process (`Sources/Ports.m:479`).
- WorkForest walks every 60 s (`Sources/main.m:371`) and reads each process's working folder (`Sources/Trees.m:368` to `:378`).

**What one pass costs.** I measured with `procs.c`, 100 passes:
- 867 pids. 638 belong to this user, and 229 refuse `PROC_PIDTBSDINFO` because other users own them.
- The pid list takes 16 µs, bsdinfo for all 875 µs, rusage for own pids 2,381 µs, fd lists 1,247 µs, and socket info 1,438 µs.
- The pass covers 9,359 fds, 812 sockets, 304 TCP sockets and 17 listening ones.
- `/usr/bin/time -l` reports 0.05 s user and 0.58 s system for 100 passes. That is 6.3 ms of CPU per pass, and 3 MB maximum resident.
- At LocoHost's 5-second tick, that is 0.13% of one core.

**The cheap parts and the dear parts.** `proc_pid_rusage` is the largest single cost, at about 3.7 µs per pid. Sockets cost 1.7 µs each. The pid list is nearly free. Guess: the pass gets cheaper if it reads rusage and fds only for processes that are new or have used CPU since the last pass. A cheap test for that, `ri_user_time` from the previous pass, needs rusage itself, so the saving would come from the fd scan only. This needs a measurement in phase 1.

**Root's processes.** `proc_pidinfo` refuses root's processes. One `KERN_PROC_ALL` sysctl returns every process, root's included, in 0.37 ms. LocoHost already uses `KERN_PROC_PID` for this reason (`Sources/Where.m:27`). The core can take ppid, uid, start time and name from the sysctl for everyone, and call `proc_pidinfo` only for its own user's processes.

**lsof.** One `lsof -nP -iTCP -sTCP:LISTEN` costs 40 to 70 ms wall and 20 to 50 ms of CPU, against 1.4 ms for the in-process socket scan. The core should never shell out for sockets.

**Exits.** `kq.c` registered `NOTE_EXIT` on all 864 pids in 403 µs, 0.47 µs each, with no failures. That includes pid 1, which root owns. A child running `sleep 0.2` was reported 222.7 ms after the spawn, with `fflags=0x84000000`, which is `NOTE_EXIT | NOTE_EXITSTATUS`, and `data=0`, its exit status. `sys/event.h` line 265 says the exit status is returned only "for child process or when allowed to signal target pid". A kqueue costs nothing while it waits, so the core learns of exits at once instead of at the next tick.

**Launches.** There is no push source for a new process without Endpoint Security. That needs an entitlement requested from Apple ([Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.endpoint-security.client)). The core therefore keeps the 5-second pass to find new pids, and watches each known pid with kqueue so an exit lands at once.

```objc
// One kqueue for every pid the core knows. The source runs on the Senses queue.
int kq = kqueue();
dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, kq, 0, sensesQueue);
dispatch_source_set_event_handler(src, ^{
    struct kevent ev[64]; struct timespec zero = {0};
    int n = kevent(kq, NULL, 0, ev, 64, &zero);
    for (int i = 0; i < n; i++) [graph processExited:(pid_t)ev[i].ident status:(int)ev[i].data];
});
dispatch_resume(src);
// After each 5-second pass, for each new pid:
struct kevent add; EV_SET(&add, pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT | NOTE_EXITSTATUS, 0, NULL);
kevent(kq, &add, 1, NULL, 0, NULL);   // ESRCH means it already exited
```

**GUI apps.** `NSWorkspace.notificationCenter` posts `NSWorkspaceDidLaunchApplicationNotification`, `NSWorkspaceDidTerminateApplicationNotification` and `NSWorkspaceDidActivateApplicationNotification`. Each carries an `NSRunningApplication` under `NSWorkspaceApplicationKey` (AppKit `NSWorkspace.h` lines 286 to 294). The same header posts `NSWorkspaceWillSleepNotification`, `NSWorkspaceDidWakeNotification` and `NSWorkspaceScreensDidSleepNotification` (lines 322 to 325). These cover apps only, not CLI agents, so they add to the process pass and do not replace it. `runningApplications` reads 97 apps in 8.7 µs (power.m).

```objc
NSNotificationCenter *nc = NSWorkspace.sharedWorkspace.notificationCenter;
[nc addObserverForName:NSWorkspaceDidTerminateApplicationNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
    NSRunningApplication *app = n.userInfo[NSWorkspaceApplicationKey];
    [graph appQuit:app.processIdentifier bundle:app.bundleIdentifier];
}];
```

**Bytes per process.** `nettop` gives bytes per process. One `nettop -P -L 1 -n -x` run costs 20 to 40 ms wall (`/usr/bin/time -p` gave 40 ms on re-run). `nettop` holds the private entitlement `com.apple.private.network.statistics` (`codesign -d --entitlements - /usr/bin/nettop`). The kernel source shows that this entitlement is not always needed on the Mac:
- XNU `bsd/net/ntstat.c` sets `nstat_privcheck = 0` when `XNU_TARGET_OS_OSX` and exposes it as `net.statistics_privcheck` (lines 96 to 102, [source](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/ntstat.c)).
- `nstat_client_handle_add_all` checks `PRIV_NET_PRIVILEGED_NETWORK_STATISTICS` only when `nstat_privcheck != 0`, or for the newer `UDP_SUBFLOW` and `CONN_USERLAND` providers (lines 6897 to 6901).
- Extended fields, which "give away additional privacy information", always need the privilege (lines 6862 to 6866).
- `sysctl net.statistics_privcheck` prints 0 on this Mac.
- `nstat.c` opened and connected the control socket `com.apple.network.statistics` as uid 501 from an ad-hoc signed binary.

The message structs live under `#ifdef PRIVATE` in XNU `bsd/net/ntstat.h`, lines 38 to 1547, and are not in the SDK (`ls $SDK/usr/include/net/ntstat.h` fails). Using them means copying a private ABI that Apple can change in any release. I did not query counts, so cost and field layout on macOS 27 are not verified.

## Folders: FSEvents and clone-aware sizing

**Latency.** `fse.m` writes 5 files 50 ms apart in a watched folder. The three numbers below are from the original run only (unverified), because re-running fse.m writes files:
- With directory events and latency 1.0 s, the first callback came 503 ms after the first write.
- With latency 0.1 s and `kFSEventStreamCreateFlagNoDefer`, it came after 11.3 ms.
- With latency 0 and `kFSEventStreamCreateFlagFileEvents`, it came after 13.3 ms.

Guess: the 503 ms instead of 1 s comes from the latency timer starting when the stream starts, 0.5 s before the first write. I did not check this.

**Cost on the real tree.** A live stream on `~/Documents/GitHub` saw 6,463 events in 224 callbacks over 20 s, and used 23.5 ms of CPU (fse3.m) (unverified). That is about 1.2 ms of CPU a second while agents work. Most events came from one folder, `barkpark/api` with 6,292 events (unverified). A re-run of fse3 on 2026-10-27 saw 17 events in 9 callbacks and 0.8 ms of CPU in 20 s, so the live cost depends on what agents do at the time. Busy folders such as `node_modules` dominate. `FSEventStreamSetExclusionPaths` can exclude "a maximum of 8 directories" (`FSEvents.h` lines 1420 to 1435). That is too few for 99 worktrees, so the core must filter paths in the callback.

**Warm start.** FSEvents can replay what changed while the app was not running. This is the mechanism behind PLAN.md's "warm scan under one second":
- `FSEventsGetLastEventIdForDeviceBeforeTime` returned 0 for both "one hour ago" and "ten minutes ago" on this Mac (fse2.m, fse3.m).
- Passing 0 as `sinceWhen` replayed the whole store: 494,887 events in 17,324 callbacks, 93.4 s and 2.4 s of CPU before `HistoryDone`.
- `FSEvents.h` lines 752 to 761 warn about exactly this: "Do not pass zero for sinceWhen, unless you want to receive events for every directory modified since the beginning of time".
- The fix is to save `FSEventStreamGetLatestEventId()` to the Store on each tick and at quit, and replay from that id on launch.
- When history is lost, the stream sets `kFSEventStreamEventFlagMustScanSubDirs` (`FSEvents.h` line 398). The core then rescans that folder only.

```objc
FSEventStreamContext ctx = { .info = (__bridge void *)self };
FSEventStreamRef s = FSEventStreamCreate(NULL, Changed, &ctx, (__bridge CFArrayRef)roots,
    savedEventId ?: kFSEventStreamEventIdSinceNow, 0.5,
    kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot);
FSEventStreamSetDispatchQueue(s, foldersQueue);
FSEventStreamStart(s);
// In Changed(): skip paths under node_modules/.git/objects unless a sizer asked for them,
// mark the owning worktree or cache dirty, and save FSEventStreamGetLatestEventId(s).
```

**Clone-aware size.** `man getattrlist` gives the key attribute for clone-aware sizing. `ATTR_CMNEXT_PRIVATESIZE` is "the number of bytes that are not trapped inside a clone or snapshot, and which would be freed immediately if the file were deleted". `ATTR_CMNEXT_EXT_FLAGS` carries `EF_MAY_SHARE_BLOCKS` and `EF_SHARES_ALL_BLOCKS` (`sys/stat.h` lines 368 and 374). `ATTR_CMNEXT_CLONEID` identifies "files that are pure clones of each other". `getattrlistbulk` returns these only with `FSOPT_ATTR_CMN_EXTENDED` (`man getattrlistbulk`, "forkattrs are reinterpreted as a set of extended common attributes").

**Measured, sizer.c, second warm run of each.**

| Tree | Files | fts with lstat, du style | getattrlistbulk, allocated only | getattrlistbulk with private size and flags | Allocated | Private |
|---|---|---|---|---|---|---|
| `client-app/node_modules`, npm | 26,112 | 339 ms CPU | not run | 461 ms CPU | 336.5 MB | 336.5 MB |
| `barkpark/node_modules`, pnpm | 78,247 | 1,720 to 2,055 ms CPU | 1,252 to 1,423 ms CPU | 1,629 to 2,174 ms CPU | 1,502.9 MB | 2.8 MB |
| `du -sk barkpark/node_modules` | | 2.26 s CPU | | | 1,467,720 KB | |

In the pnpm tree, 73,202 of 78,247 files have `EF_SHARES_ALL_BLOCKS`. du says 1.5 GB, and deleting the tree would free 2.8 MB. Noo-Noo calls this gap "APFS-clone fiction" and stores it as `du_fiction_bytes` (noo-noo `internal/cli/leaks_cmd.go` lines 120 and 121). It measures the gap today with one `fcntl(F_LOG2PHYS_EXT)` per file extent and a union of physical extents (noo-noo `internal/sizer/extent_darwin.go` lines 20 to 120). That needs an open file per file. PRIVATESIZE needs no open file and comes in the same batch as the name.

**The catch.** PRIVATESIZE is per file. When a whole clone family sits inside the deleted set, each member reports 0 private bytes, yet deleting them all frees the full size. I made three 50 MB files in my temp folder with `cp -c` and changed 2 bytes of the third (cloneid.c):
- a.bin and b.bin report private 0, the same clone id 148935669, flags 0x41, and clone refcount 2.
- c.bin reports private 16,384, one block, and its own clone id.

A sizer can count each clone id once when every holder of that id is inside the set, using `ATTR_CMNEXT_CLONE_REFCNT`. This volume reports `VOL_CAP_FMT_CLONE_MAPPING` valid but not set, and still returned clone ids and refcounts. The header says that flag means "full clone tracking" (`sys/attr.h` lines 260 to 264). Whether refcounts are exact without it is not proven. Keep Noo-Noo's extent union as the exact tier for the few items that matter, such as a leak family before a delete.

```objc
struct attrlist al = { .bitmapcount = ATTR_BIT_MAP_COUNT,
    .commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_NAME | ATTR_CMN_ERROR | ATTR_CMN_OBJTYPE,
    .fileattr = ATTR_FILE_ALLOCSIZE,
    .forkattr = ATTR_CMNEXT_PRIVATESIZE | ATTR_CMNEXT_EXT_FLAGS };   // read as CMNEXT with the option below
int n = getattrlistbulk(dirfd, &al, buf, 256 * 1024, FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW);
// Each entry: uint32 length, attribute_set_t returned, [uint32 error], attrreference name, fsobj_type_t,
// then off_t allocsize, off_t privatesize, uint64 ext flags, in that order. Use a buffer per directory
// level when recursing, and read every field with memcpy, because entries are only 4-byte aligned.
```

## Energy and heat

**Energy.** `ri_energy_nj` and `ri_penergy_nj` sit in `struct rusage_info_v6` (`sys/resource.h` lines 410 and 411), which is `RUSAGE_INFO_CURRENT` (line 193). The header gives no unit beyond the name. `energy.c` spun one core for 1 s: CPU 0.998 s, `ri_energy_nj` delta 1.372 J, `ri_penergy_nj` the same, 1.94 G instructions and 3.05 G cycles. `ri_billed_energy` stayed 0. All 571 own processes reported energy above 0, and 230 were refused. Guess: the number is the CPU energy model behind Activity Monitor's energy column. Apple does not document it, so MinMacs should show it as a relative rank, "uses the most energy", and not as watts.

**Thermal state.** `NSProcessInfo.thermalState` reads in 0.2 µs. `NSProcessInfoThermalStateDidChangeNotification` pushes changes (`NSProcessInfo.h` line 233). `NSProcessInfoPowerStateDidChangeNotification` pushes low power mode changes (line 242). Insomnia already observes the thermal notification (`Sources/main.m:275`).

**Memory pressure.** `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` pushes warn and critical (`dispatch/source.h` lines 136 to 143, 235 to 241). LocoHost uses it (`Sources/main.m:856`). For a reading on demand, `sysctlbyname("kern.memorystatus_vm_pressure_level")` takes 1.4 µs and returned 1, normal. `kern.memorystatus_level` returned 66, the percent free. `host_statistics64(HOST_VM_INFO64)` takes 0.8 µs (power.m).

```objc
dispatch_source_t mp = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
    DISPATCH_MEMORYPRESSURE_NORMAL | DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL, sensesQueue);
dispatch_source_set_event_handler(mp, ^{ [graph memoryPressure:dispatch_source_get_data(mp)]; });
dispatch_resume(mp);
[NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil
    queue:nil usingBlock:^(NSNotification *n) { [graph thermal:NSProcessInfo.processInfo.thermalState]; }];
```

## Power and lid

**Reads.** All reads come from IOKit, with no subprocess (power.m):
- `AppleClamshellState` takes 10.6 µs. `AppleClamshellCausesSleep` reads "no" here, with an external display attached.
- `IOPMCopyAssertionsStatus` takes 60 µs, `IOPMCopyAssertionsByProcess` 124 µs, and `IOPSCopyPowerSourcesInfo` 59 µs.
- `pmset -g` costs 80 ms through NSTask and `pmset -g assertions` 92 ms.

**The lid override.** Insomnia reads the lid override with `pmset -g` on every `syncLid` (`Sources/main.m:679` to `:684`), and PLAN.md section 2 lists "`pmset` on the main thread" under Leave behind. `IOPMrootDomain` has a `SleepDisabled` property. It reads 1 here in power.m, and `ioreg -r -c IOPMrootDomain -d 1` shows `"SleepDisabled" = Yes`, matching `pmset -g` `SleepDisabled 1`. Reading that property replaces the read. Writing the override still needs root, through the sudoers rule (`Sources/main.m:688`).

**Lid events.** `kIOPMMessageClamshellStateChange` carries `kClamshellStateBit` and `kClamshellSleepBit` (`IOPM.h` lines 426 to 435). Insomnia registers for it with `IOServiceAddInterestNotification` (`Sources/main.m:283` to `:289`). That is already push-based.

**Assertion types.** Insomnia creates `kIOPMAssertionTypePreventUserIdleSystemSleep` and `kIOPMAssertionTypePreventSystemSleep` (`Sources/main.m:542`). `IOPMLib.h` lines 1013 to 1023 call `kIOPMAssertionTypePreventSystemSleep` "Deprecated in 10.9. This assertion is not supported in any OS X releases". Yet `pmset -g assertions` lists Insomnia's `PreventSystemSleep` assertion, and the system-wide status shows `PreventSystemSleep 1`, so powerd still counts it. `man caffeinate` says `-s` is "valid only when system is running on AC power". Keep the pair, and do not rely on the deprecated one on battery.

**Agents that keep the Mac awake.** `pmset -g assertions` lists three `caffeinate` processes holding `PreventUserIdleSystemSleep` for 300 s. `ps` shows each one's args as `caffeinate -i -t 300` and its parent as `~/.local/bin/claude`. `IOPMCopyAssertionsByProcess` returns these in 124 µs. Insomnia can treat "an agent's caffeinate child holds an assertion" as one more working signal, from the same table that tells it who else keeps the Mac awake.

```objc
CFDictionaryRef byPid = NULL;
if (IOPMCopyAssertionsByProcess(&byPid) == kIOReturnSuccess) {
    NSDictionary *d = CFBridgingRelease(byPid);   // pid -> array of assertion dictionaries
    // Join each pid with Graph's process tree: a caffeinate whose parent is a known agent means that agent works.
}
io_service_t rd = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
CFTypeRef off = IORegistryEntryCreateCFProperty(rd, CFSTR("SleepDisabled"), kCFAllocatorDefault, 0);
BOOL lidOverride = off && CFBooleanGetValue(off); if (off) CFRelease(off); IOObjectRelease(rd);
```

## Running in the background

**Login item.** `SMAppService.mainAppService` needs macOS 13 (`SMAppService.h` line 91). LocoHost, WorkForest and Insomnia all use it (LocoHost `Sources/main.m:1475`) and all sign ad-hoc (`build.sh:13`, `codesign --force --sign -`). `codesign -dv ~/Applications/LocoHost.app` shows `Signature=adhoc`. That shows the call works from an ad-hoc app. I did not read the Background Task Management database to confirm the registration, because `sfltool dumpbtm` may ask for admin rights.

**Bundled agents and daemons.** The header gives the rules:
- An agent's plist must sit in `Contents/Library/LaunchAgents` (line 103), a daemon's in `Contents/Library/LaunchDaemons` (line 121), and a login item in `Contents/Library/LoginItems` (line 79).
- "Apps that contain LaunchDaemons must be notarized" (line 55).
- A daemon is not started "until an admin approves the LaunchDaemon in System Settings" (line 161).
- "If the app bundle is not properly code signed, this API will return error kSMErrorInvalidSignature" (line 168).
- `statusForLegacyURL:` reports the status of a plist installed the old way in `~/Library/LaunchAgents` (lines 251 to 270).

An Apple forum thread reports `kSMErrorInvalidSignature` after switching to `BundleProgram`, without saying how the app was signed ([forum 775490](https://developer.apple.com/forums/thread/775490)). Whether an ad-hoc agent registers is not tested here.

**XPC services.** I built `Host.app` with `Contents/XPCServices/no.research.Scanner.xpc` and signed both with `codesign --sign -`. The host reached the service by name:
- The first reply came in 13.88 ms, which includes launchd starting the service.
- The next replies took 0.03 and 0.04 ms.
- The service ran as its own pid, 19141, and was gone 2 s after the host exited (`ps`).

A heavy scanner, such as the sizer on a 78k-file tree, can run in its own process. A crash there does not take down the menus. This needs no developer account.

```objc
NSXPCConnection *c = [[NSXPCConnection alloc] initWithServiceName:@"no.guerrilla.minmacs.Sizer"];
c.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(MMSizer)];
c.interruptionHandler = ^{ [graph sizerCrashed]; };   // launchd restarts the service on the next call
[c resume];
[[c remoteObjectProxyWithErrorHandler:^(NSError *e) { … }] sizeTrees:paths reply:^(NSDictionary *sizes) { … }];
```

## Other surfaces

**App Intents.** The SDK's `AppIntents.framework/Headers/AppIntents.h` imports Foundation and declares nothing. The framework's types, such as `AppShortcutsProvider`, exist only in `Modules/AppIntents.swiftmodule/*.swiftinterface`. The toolchain also ships `appintentsmetadataprocessor`, which reads the metadata from Swift code at build time (`ls …/XcodeDefault.xctoolchain/usr/bin`). App Intents therefore cannot be written with clang alone. Apple calls it a "Swift framework" and says "We've gone all in on Swift" ([WWDC22 10032](https://developer.apple.com/wwdc22/10032)).

The Objective-C routes into Shortcuts are these:
- Shortcuts' "Run Shell Script" action calling `minmacs … --json`.
- The URL schemes that PLAN.md section 7 keeps.
- Cocoa Scripting through an `.sdef`, which Shortcuts runs through "Run AppleScript". This is a guess, not tested.

**Notification buttons.** `UNNotificationAction` and `UNNotificationCategory` exist since macOS 10.14 (`UNNotificationAction.h` lines 24 to 53), with icons since macOS 12 (line 46). LocoHost and WorkForest already ask for alert permission and post requests (LocoHost `Sources/main.m:861` and `:958`). Whether an ad-hoc app is allowed to show them is not settled here:
- None of the bundle ids `no.guerrilla.locohost`, `no.guerrilla.workforest` or `no.guerrilla.insomnia` appear among the 60 apps in `defaults export com.apple.ncprefs`.
- A read-only query of the usernoted database returned no rows (unverified).
- `log show --last 3d` for usernoted found no line naming them (unverified).

This does not prove that delivery fails. A Bitcoin Core discussion says the app must be bundled and signed, and proposes `codesign -s -`. Nobody in it confirms that notifications then appeared ([bitcoin-core-gui #112](https://mirror.b10c.me/bitcoin-core-gui/112/)). A Xojo report says an app was granted permission yet never appeared in System Settings. Its author only guesses the app was signed ad-hoc ([Xojo forum](https://forum.xojo.com/t/macos-unusernotificationcentermbs-user-notifications-works-during-debug-but-dont-work-for-build-app/83588)).

```objc
UNNotificationAction *stop = [UNNotificationAction actionWithIdentifier:@"stop" title:@"Stop Server" options:UNNotificationActionOptionDestructive];
UNNotificationAction *keep = [UNNotificationAction actionWithIdentifier:@"keep" title:@"Keep" options:UNNotificationActionOptionNone];
[UNUserNotificationCenter.currentNotificationCenter setNotificationCategories:[NSSet setWithObject:
    [UNNotificationCategory categoryWithIdentifier:@"idle-server" actions:@[stop, keep] intentIdentifiers:@[] options:0]]];
// content.categoryIdentifier = @"idle-server"; the delegate's
// userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler: routes response.actionIdentifier to Act, which checks fresh first.
```

## Recommendations

1. **One Senses pass in one place.** PLAN.md section 3, "One sampler". Build the 5-second pass from:
   - one `KERN_PROC_ALL` sysctl for every process, 0.37 ms
   - `proc_pid_rusage(RUSAGE_INFO_V6)` for own pids only
   - the socket scan from LocoHost `Ports.m`

   Keep the phase 1 budget at 6.3 ms of CPU per pass or less, measured on this Mac with `procs.c` as the reference. Never call `lsof`, `nettop`, `ps` or `pmset` from a Senses tick.
2. **kqueue for exits, the pass for launches.** PLAN.md section 3, "Event-driven, not polling". Register `NOTE_EXIT` on each pid the graph holds. The graph then drops a server, an agent or a caffeinate child the moment it ends. Add the `NSWorkspace` launch, terminate, sleep and wake notifications for apps. Do not plan on Endpoint Security, because it needs an entitlement from Apple.
3. **FSEvents with a saved event id.** PLAN.md section 3, "Event-driven", and section 9, phase 2's "warm scan under one second":
   - Save `FSEventStreamGetLatestEventId()` in Store and replay from it on launch.
   - Never pass 0, and never trust `FSEventsGetLastEventIdForDeviceBeforeTime`, which returned 0 here.
   - Filter `node_modules` and `.git/objects` in the callback, because exclusion paths stop at 8.
   - Treat `MustScanSubDirs` as "rescan that folder".
4. **One Sizer on getattrlistbulk with PRIVATESIZE.** PLAN.md section 3, "Sizer (APFS-aware, cached)", and section 6, "Clutter that knows its owner":
   - Report two numbers per item, allocated and freed-if-deleted, with the private size as the default.
   - Count a clone id once when all its holders are in the set.
   - Keep Noo-Noo's `F_LOG2PHYS_EXT` extent union as the exact check that Act runs right before a delete.
   - Replace WorkForest's `NSDirectoryEnumerator` `fileSize` sum (`Forest.m:243` to `:246`), which counts logical bytes, not disk.
5. **Power facts from IOKit, never pmset, for reads.** PLAN.md section 2, Insomnia's "`pmset` on the main thread". Read `SleepDisabled` and `AppleClamshellState` from `IOPMrootDomain`, and assertions from `IOPMCopyAssertionsByProcess`. Keep `sudo -n pmset -a disablesleep` only for the write, off the main thread.
6. **Agent caffeinate as a working signal.** PLAN.md section 3, Graph, and section 1, principle 4, where Insomnia knows which agent works. Join `IOPMCopyAssertionsByProcess` with the process tree. A `caffeinate -i -t 300` child of a registry agent counts as that agent working.
7. **Heavy scanners in an XPC service.** PLAN.md section 10, "One process for all", and Track H. Put the Sizer, and later Noo-Noo's leak scan, in `Contents/XPCServices`. It works ad-hoc and costs 14 ms to start and 0.03 ms per call. A crash restarts the service, not the menus.
8. **Lid mode helper waits for notarization.** PLAN.md section 10, "Lid mode", and section 11, question 2. `SMAppService.h` line 55 requires notarization for a bundled LaunchDaemon. That needs an Apple Developer account. Until then, keep Insomnia's sudoers rule with its two exact commands, as PLAN.md section 8 says.
9. **Migration checks with statusForLegacyURL.** PLAN.md section 8. Use `+[SMAppService statusForLegacyURL:]` on `~/Library/LaunchAgents/io.noo-noo.d.plist` to see Noo-Noo's agent before asking to remove it.
10. **Shortcuts through the CLI, not App Intents.** PLAN.md section 7, CLI. Document "Run Shell Script: `minmacs work --here --json`" and the URL schemes as the Shortcuts route. App Intents would bring Swift into a clang-only build.
11. **Notification actions behind a check.** PLAN.md section 7, Menus, and section 1, principle 5. Use `UNNotificationAction` only for actions that Act re-checks fresh, such as Stop Server or Keep. Phase 1 must first prove that an ad-hoc `MinMacs.app` appears in System Settings, Notifications.
12. **Energy as a rank.** PLAN.md section 6, "Heat and battery aware". Use `ri_energy_nj` deltas to rank processes, and thermal state and memory pressure as push events. Do not show joules or watts in menus, because Apple does not document the unit.

## Open questions

1. Does an ad-hoc signed `MinMacs.app` in `~/Applications` get notification permission on macOS 27? None of the three current apps appear in `com.apple.ncprefs`. Test in phase 1 by opening the app with `open`, then reading System Settings, Notifications.
2. Does `+[SMAppService agentServiceWithPlistName:]` register from an ad-hoc bundle, or does it return `kSMErrorInvalidSignature`? Not tested, because registering a LaunchAgent changes this Mac's settings.
3. Are `ATTR_CMNEXT_CLONE_REFCNT` counts exact on a volume that reports `VOL_CAP_FMT_CLONE_MAPPING` valid but not set? That is the case on `/System/Volumes/Data` here.
4. Can the ntstat socket give per-process byte counts for LocoHost's "who uses it" without the private entitlement, and how much does a query cost? Connect works. Queries need private structs copied from XNU, which can change in any macOS release.
5. Why did `FSEventsGetLastEventIdForDeviceBeforeTime` return 0 for times 10 and 60 minutes ago on this Mac? The saved-id approach avoids it, but the cause is unknown.
6. How much does the Senses pass save if it reads fds only for processes that are new or used CPU since the last pass? This needs a phase 1 measurement against the 6.3 ms baseline.
7. Do FSEvents for `~/Documents` reach an ad-hoc app bundle without a privacy prompt? The test programs ran as plain binaries from a terminal, which may carry the terminal's access.
8. What exactly does `ri_energy_nj` measure, and does it match Activity Monitor's energy column? It is undocumented. A side-by-side reading with Activity Monitor would settle the rank use.

## Verification

Checked on 2026-10-27 on the same Mac. Counts: 117 claims confirmed, 14 corrected, 5 marked unsupported.

**How each kind of claim was checked.**
- Code citations. Re-opened each file and line in LocoHost at c48cc39, WorkForest at 2a6931f, the `legacy` branch of minmacs, and the insomnia and noo-noo clones.
- Apple headers. Re-read each cited line in the SDK from `xcrun --show-sdk-path`, plus `man getattrlist`, `man getattrlistbulk` and `man caffeinate`.
- XNU. Downloaded `bsd/net/ntstat.c` and `bsd/net/ntstat.h` from apple-oss-distributions/xnu main and re-read lines 96 to 102, 6862 to 6866, 6897 to 6901, and 38 to 1547.
- Web sources. Re-fetched the Endpoint Security entitlement page through its JSON form, which says "You must request this entitlement from Apple". Also re-fetched WWDC22 10032, forum thread 775490, bitcoin-core-gui #112 and the Xojo thread.
- Measurements. Re-ran procs (20 and 100 passes), kq, energy, nstat, power, cloneid, sizer on both trees, fse2, fse3 and the XPC Host. Also re-ran `du -sk`, `lsof`, `nettop`, `ioreg`, `pmset -g`, `pmset -g assertions`, `ps`, `codesign -dv` and `defaults export com.apple.ncprefs`. The re-runs gave numbers in the stated ranges. Examples: 5.4 ms CPU per pass, 831 pids registered in 430 µs, 1.379 J for the 1 s spin, 12.5 ms XPC cold start, and 501,272 replayed events in 99.6 s with id 0 for "10 minutes ago".

**Corrected.**
1. bsdinfo for all pids is about 0.9 ms, from the 875 µs in the text, not 0.8 ms.
2. procs did not run unsigned. It carries the linker's ad-hoc signature.
3. The kq table cell said the exit came 22 ms after the child ended. The program measures 222.7 ms from the spawn.
4. Legacy `Scanner.m:138` reads `runningApplications`. MinMacs 1.2 never observes the NSWorkspace notifications.
5. lsof costs 40 to 70 ms wall and 20 to 50 ms CPU, not 60 to 70 and 50.
6. The sizer uses 1.6 to 2.2 s CPU on 78,247 files, not 1.6 s.
7. Insomnia reads `AppleClamshellState` at `Sources/main.m:118`, not `:116`.
8. nettop took 40 ms on re-run, so the range is 20 to 40 ms.
9. Noo-Noo's phrase is "APFS-clone fiction" with the key `du_fiction_bytes`, not "du fiction".
10. `DISPATCH_MEMORYPRESSURE_CRITICAL` is documented at `dispatch/source.h` line 241, so the range is 235 to 241.
11. WWDC22 10032 does not say "designed natively for Swift". It says "Swift framework" and "We've gone all in on Swift".
12. The Bitcoin Core thread proposes `codesign -s -` but nobody confirms that notifications then appeared.
13. The Xojo author only guesses that the app was signed ad-hoc.
14. WorkForest's `fileSize` sum sits at `Forest.m:243` to `:246`, not `:241`.

**Unsupported, marked "(unverified)".**
1. The fse.m latencies of 503, 11.3 and 13.3 ms. Re-running fse.m writes files, which this check may not do.
2. The 6,463 live events and 23.5 ms CPU in 20 s. A re-run of fse3 saw 17 events and 0.8 ms, so the earlier run cannot be reproduced.
3. `barkpark/api` as the source of 6,292 of those events.
4. The usernoted database query with no rows. No query or path is given.
5. The `log show --last 3d` search for usernoted. It was not re-run.

**Not changed.** Claims already marked as guesses stay as guesses. Load-dependent numbers stay as written when a re-run fell near them, such as 178.6 µs against 124 µs for `IOPMCopyAssertionsByProcess`, and 663 against 812 sockets.
