# Research A: shared patterns in our five codebases

**Summary.** The five apps implement 38 concepts more than once (unverified: the catalog below has 42 entries, and the report does not say which 4 it leaves out of the count). Most copies are LocoHost and WorkForest twins that started equal and drifted. Examples are the model call, the menu kit, the hover card, prefs, rules and the keep list. MinMacs 1.2 holds a third process sampler and a third rules file. Insomnia repeats the app shell. Noo-Noo, written in Go, holds the best answers for sizing, audit before delete, recovery bundles and fail-safe probes, and the worst for deletes: it calls `os.RemoveAll` on user data at six call sites in five packages, entry 30. Each entry below names every implementation by repo, file, line and function, picks the one Core should start from, and sketches the Core header. The Core prefix `MC` in the sketches is a placeholder, not a decision.

**Sources.** Every path is relative to its repo, read at these commits:

| Label | Repo | Commit |
|---|---|---|
| LH | `~/Documents/GitHub/locohost` | c48cc39 |
| WF | `~/Documents/GitHub/workforest` | 2a6931f |
| MM | `~/Documents/GitHub/minmacs`, branch `legacy` | 8882121 |
| IN | FRIKKern/insomnia clone | 6d402a9 |
| NN | FRIKKern/noo-noo clone | 1e6dc60 |

Commands run on this Mac, all read-only: `ps -A -o pid= | wc -l` printed 800. `ls ~/Library/Application Support/{LocoHost,WorkForest}` listed the state files named in entry 18. `grep -o 'check "' test.sh | wc -l` gave the test counts in entry 36.

## Catalog

The entries follow PLAN.md section 3: Senses, Know, Store, Review, Act, UI, then the CLI and the tooling around it.

### Senses

#### 1. Process sampling

**Implementations.**
- LH `-[LHScanner sample]`, Sources/Ports.m:439. It uses `proc_listpids`, `PROC_PIDTBSDINFO` and `proc_pid_rusage` with `RUSAGE_INFO_V6`, so it gets CPU, footprint and `ri_energy_nj` (Ports.m:460). It reads rusage only for the user's own uid. The timer runs every 5 s (LH main.m:862).
- MM `-[MMScanner sample]`, Sources/Scanner.m:102. The same loop with `RUSAGE_INFO_V4`, so no energy (Scanner.m:118). It skips any process whose rusage fails, so root processes drop out. The timer runs every 4 s (MM main.m:416). The CLI samples twice with a one-second sleep for CPU% (MM main.m:285).
- WF `ProcessesIn`, Sources/Trees.m:365. Its own `proc_listpids` loop that reads the cwd of every user process on each scan, every 5 minutes (WF main.m:20).
- NN `ParsePS`, internal/procsig/procsig.go:121, parses `ps -axo pid,ppid,uid,etime,command`. NN internal/core/memory.go reads `top` and `vm_stat` for memory posture, per its package comment.

**Best.** LH. It is the only one that reads energy, keeps the start time for identity, and limits rusage calls to the user's processes. This Mac had 800 processes when the research ran and 821 at verification. LocoHost runs on this Mac and walks all of them every 5 seconds. MinMacs 1.2 walks them every 4 seconds while it runs, but `ps` showed no MinMacs process at verification.

**Core API.**
```objc
@interface MCProc : NSObject
@property (readonly) pid_t pid, ppid; @property (readonly) uid_t uid;
@property (readonly) uint64_t startSec;          // with pid, the identity
@property (readonly, copy) NSString *name;
@property (readonly) double cpuPercent, cpuSeconds, energyJoules;
@property (readonly) uint64_t footprint;
@end
@interface MCSample : NSObject                    // immutable, one per pass
@property (readonly) NSDate *at;
@property (readonly) NSDictionary<NSNumber *, MCProc *> *procs;
@property (readonly) double totalCPU;
@end
@interface MCSenses : NSObject
+ (instancetype)shared;
- (MCSample *)latest;                             // never blocks; the 5-second pass replaces it
- (MCSample *)sampleNow;                          // the CLI: two passes one second apart
@end
```

#### 2. Process facts and process identity

**Implementations.**
- LH `ProcessArgs`, `ProcessCwd`, `ProcessPath`, `StartTime`, Sources/Ports.m:71, :91, :97, :102. `+[LHScanner alive:]` at Ports.m:435 checks pid and start time together. The host key is `"pid:start"` (Ports.h, `key`).
- LH Where.m `KInfo`, `ParentOf`, `TTYOf`, `ExecPath`, Sources/Where.m:28 to :43. It uses `sysctl KERN_PROC` because it also reads root-owned processes such as Terminal's login (Where.m:27).
- MM `MMProcessArgs`, Sources/Scanner.m:67, the same KERN_PROCARGS2 parser as LH, but it returns nil on failure where LH returns an empty array. MM `WorkingDirectory`, Sources/Agents.m:81, the same as `ProcessCwd` with `~` for the home folder.
- WF reads `PROC_PIDVNODEPATHINFO` inline in `ProcessesIn` (Trees.m:377) and names processes with `ProcName` (Trees.m:359).
- NN re-verifies a pid's identity before it terminates one, per the comment on `Action.Target` in internal/modules/module.go:64.

**Best.** LH Ports.m for the facts and the `pid:start` identity. Add Where.m's `KInfo` for parent and tty, since it reads root processes too.

**Core API.**
```objc
@interface MCSample (Facts)                       // read lazily, memoized for the life of one sample
- (NSArray<NSString *> *)argsOf:(pid_t)pid;       // empty, never nil
- (NSString *)cwdOf:(pid_t)pid;
- (NSString *)execPathOf:(pid_t)pid;
- (NSString *)ttyOf:(pid_t)pid;
@end
typedef struct { pid_t pid; uint64_t startSec; } MCProcKey;
NSString *MCProcKeyString(MCProcKey k);           // "pid:start", as LocoHost stores it today
BOOL MCProcAlive(MCProcKey k);                    // kill(pid, 0) and the same start time
```

#### 3. The process tree and roll-ups

**Implementations.**
- LH `-[LHScanner sample]` builds a `kids` map and walks it breadth first, capped at 500 pids (Ports.m:536). It walks up 20 hops for wrappers, agents, shells and multiplexers (Ports.m:546), and up 6 hops to fold forked workers into their parent (Ports.m:492).
- MM `-[MMAgents detect:]` builds its own `kids` map from the same sample (Agents.m:200) and its own breadth-first tree (Agents.m:240).
- MM `-[MMScanner sample]` rolls helpers up to an app through the responsible pid, then 12 parent hops (Scanner.m:146 to :157).
- LH Where.m `Chain` walks parents up to 64 hops from the server and from its wrapper (Where.m:52).

**Best.** LH's walk, with its caps, as the one implementation. Build `kids` once per sample, not once per caller.

**Core API.**
```objc
@interface MCSample (Tree)
- (NSArray<NSNumber *> *)childrenOf:(pid_t)pid;
- (NSArray<NSNumber *> *)treeOf:(pid_t)pid limit:(NSUInteger)max;      // the pid and all below it
- (NSArray<NSNumber *> *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops;
- (void)rollUp:(NSArray<NSNumber *> *)pids cpu:(double *)cpu memory:(uint64_t *)mem energy:(double *)joules;
@end
```

#### 4. The responsible app and the owning app

**Implementations.**
- LH `Responsible`, Sources/Ports.m:63. It loads `responsibility_get_pid_responsible_for_pid` through `dlsym` and falls back to the pid itself.
- LH `Responsible`, Sources/Where.m:45. The same lookup in the same app, but it falls back to 0.
- MM `Responsible`, Sources/Scanner.m:12. The same as Ports.m.
- LH `AppOf`, Sources/Where.m:62. The first regular app in the parent chain, then the app whose bundle holds the executable.
- MM `IsBucket`, Sources/Scanner.m:22. Which running apps get their own row: regular apps and third-party accessory apps, not helpers.

**Best.** Ports.m's fallback to the pid, because callers compare the answer against the pid (Ports.m:569 to :575). Keep `AppOf` and `IsBucket` as two named rules on top of it.

**Core API.**
```objc
pid_t MCResponsiblePid(pid_t pid);                              // the pid itself when unknown
NSRunningApplication *MCOwningApp(MCSample *s, pid_t pid);      // AppOf: chain first, then the bundle
BOOL MCAppHasOwnRow(NSRunningApplication *app);                 // IsBucket
```

#### 5. Sockets and ports

**Implementations.**
- LH `ScanSockets`, Sources/Ports.m:326. `PROC_PIDLISTFDS` and `PROC_PIDFDSOCKETINFO` over the user's pids, keeping TCP LISTEN and ESTABLISHED, IPv4, IPv6 and v4-mapped addresses (Ports.m:479).
- MM `MMLoopbackListeners`, Sources/Scanner.m:41. The same calls, LISTEN only, loopback only, for one app's pids.
- LH `LHPortListening`, Ports.m:60, and `PortFree`, LH main.m:474. Connect and bind probes.
- NN `LsofProbe`, internal/leaks/lsof.go:35. Open files under a folder through `lsof`, failing safe to "live" when it cannot tell.

**Best.** LH `ScanSockets`, run once per sample for every user pid. MM's question, whether an app serves on loopback, is a filter over that table. NN's open-file probe is a different fact and stays a separate, on-demand check.

**Core API.**
```objc
typedef struct { pid_t pid; uint8_t state; uint16_t lport, fport; BOOL remoteLoopback; char laddr[46]; } MCSocket;
@interface MCSample (Sockets)
- (NSData *)sockets;                                            // packed MCSocket values
- (NSArray<NSNumber *> *)listenPortsOf:(NSArray<NSNumber *> *)pids loopbackOnly:(BOOL)loop;
@end
BOOL MCPortAnswers(NSInteger port);
BOOL MCPortFree(NSInteger port);
BOOL MCFolderHasOpenFiles(NSString *dir, NSString **proof);    // NN's lsof probe, fails toward YES
```

#### 6. System signals: memory pressure, disk, heat, power, load

**Implementations.**
- LH memory pressure through `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`, main.m:856, and load through `getloadavg`, main.m:891.
- WF low disk through `NSURLVolumeAvailableCapacityForImportantUsageKey`, main.m:403, below 10% or 15 GB.
- IN `PowerState`, `LidClosed`, `Thermal`, `Online`, Sources/main.m:82, :113, :129, :137, with IOPS, IORegistry, thermal-state and reachability notifications set up in `applicationDidFinishLaunching:` (IN main.m:259 to :291).
- MM `AssertionsByPid`, Sources/Agents.m:181, through `IOPMCopyAssertionsByProcess`.
- NN `VMStatSampler.Sample`, internal/pressure/vmstat.go:27, runs `/usr/bin/vm_stat` each sample. NN `DiskSampler`, internal/pressure/disk.go:13.

**Best.** The event sources in LH and IN: the dispatch memory-pressure source, IOPS and IOKit notifications, `NSProcessInfoThermalStateDidChangeNotification`. They cost nothing between events. NN's `vm_stat` polling spawns a process per sample and should not move to Core.

**Core API.**
```objc
typedef NS_OPTIONS(NSUInteger, MCSignal) { MCSignalMemory = 1, MCSignalDisk = 2, MCSignalThermal = 4,
                                           MCSignalPower = 8, MCSignalLid = 16, MCSignalNetwork = 32, MCSignalLoad = 64 };
@interface MCPower : NSObject
@property (readonly) BOOL onAC, lidClosed, online; @property (readonly) int batteryPercent;   // -1 without a battery
@property (readonly) NSProcessInfoThermalState thermal;
@property (readonly) uint64_t diskFree, diskTotal; @property (readonly) BOOL memoryWarning, memoryCritical;
@end
@interface MCSenses (Signals)
- (MCPower *)power;
- (id)observe:(MCSignal)mask block:(void (^)(MCSignal changed))block;   // main queue
@end
```

### Know

#### 7. Agent recognition

**Implementations.**
- MM `MMAgents`, Sources/Agents.m:38 and `-detect:` at :198. 63 JSON rows in registry/agents, matched on argv with scores, presence paths and working signals. The user's own rows load after the bundled ones (Agents.m:43).
- LH `AgentNames`, Sources/Ports.m:225. A dictionary of 18 process names, plus a check for `/.claude/shell-snapshots/` in the args (Ports.m:563).
- IN `MinMacsWorking`, Sources/main.m:165. It runs `minmacs agents --json` with a 10-second limit, every 15 seconds while the mode is on (IN main.m:502).
- NN `SessionProbeFor`, internal/leaks/session.go:28. An agent session is alive when `ps` args carry `--session-id <uuid>` or its transcript changed recently.

**Best.** MM's registry. It is data, MM build.sh:15 copies only the rows that pass tools/validate_row.py, and it already answers "working" for IN. LH's 18 names and NN's probe become registry lookups.

**Core API.**
```objc
@interface MCAgent : NSObject
@property (readonly, copy) NSString *harness, *harnessID, *state, *why, *sessionID, *project;   // state: working | idle | blocked | unknown
@property (readonly) pid_t pid; @property (readonly) NSArray<NSNumber *> *tree;
@end
@interface MCRegistry : NSObject
+ (instancetype)shared;                                         // bundled rows, then the user's rows
- (NSArray<MCAgent *> *)agentsIn:(MCSample *)s;
- (MCAgent *)agentAbove:(pid_t)pid in:(MCSample *)s;           // LocoHost's "agent above the server"
- (MCAgent *)workingAgentOwning:(pid_t)pid in:(MCSample *)s;
@end
```

#### 8. Agent session lookup from transcripts

**Implementations.**
- LH `Session`, Sources/Intel.m:308, with `Consider` (:274) and `NamedBetween` (:245). Per server: Claude Code, Codex and pi logs whose session was open when the server started.
- WF `Sessions`, Sources/Trees.m:545, with `Mentions` (:511). For all worktrees in one pass: logs in the folder, logs in parent folders that name the folder within 14 days (Trees.m:12), and Codex logs by date for 30 days.
- MM `TranscriptAge`, Sources/Agents.m:168. Seconds since a row's per-session transcript was written.
- NN `transcriptMtime` in internal/leaks/session.go.
- Copied helpers. `FirstPrompt`, `ISODate` and `Match` are byte-identical between LH Intel.m and WF Trees.m, checked with `diff`. `HeadText` differs: LH reads through its own `Head`, WF through `readDataUpToLength:`.

**Best.** One index, built the WF way: one pass over the log folders for every folder Core cares about. LH's start-time test then becomes a query on that index. Both apps read the same logs on their own timers today.

**Core API.**
```objc
@interface MCSession : NSObject
@property (readonly, copy) NSString *agent, *title, *firstPrompt, *file, *match;
@property (readonly) NSDate *started, *lastActive;
@end
@interface MCSessions : NSObject
+ (instancetype)shared;                                          // refreshed by FSEvents on the log folders
- (MCSession *)latestIn:(NSString *)folder;                      // WF: ran in it, or named it
- (MCSession *)openAt:(NSDate *)t inFolders:(NSArray<NSString *> *)folders;   // LH: open when the server started
@end
```

#### 9. Running a child process with a time limit

**Implementations.**
- LH `Run`, Sources/Where.m:13, 3 seconds. LH `Git`, Sources/Intel.m:56, 5 seconds. LH `Run`, Sources/Review.m:184, 240 seconds, with stdin and a filtered environment. LH `Restart`, main.m:313, through `zsh -lc`.
- WF `WFGitInput`, Sources/Common.m:78, any limit, with stdin. WF `Run`, Sources/Review.m:167. WF `LocoHosts`, Trees.m:396, 20 seconds.
- LH and WF `FindTool`, Review.m:163 and :146. It falls back to `zsh -lc "whence -p name"` with no time limit.
- IN `Run`, Sources/main.m:65, with no time limit. IN calls it for `pmset -g` and `sudo -n pmset` from `syncLid` (main.m:648, :679, :687), which a 60-second main-thread timer drives (main.m:272). PLAN.md section 2 names this as "pmset on the main thread".
- NN `ExecGit`, internal/worktrees/worktrees.go:48, uses `context` timeouts.

**Best.** WF `WFGitInput`. It has a time limit, stdin, reads stdout on another queue so a full pipe cannot deadlock, and returns the exit status. Generalize it from git to any tool.

**Core API.**
```objc
typedef struct { int status; BOOL timedOut; } MCRunResult;
MCRunResult MCRun(NSString *path, NSArray<NSString *> *args, NSData *stdinData, NSDictionary *env,
                  NSString *cwd, NSTimeInterval timeout, NSData **outData, NSData **errData);   // never on the main thread
NSString *MCFindTool(NSString *name, NSString *envKey, NSArray<NSString *> *paths);            // the login-shell fallback gets a limit too
```

#### 10. The git runner

**Implementations.**
- LH `GitPath` and `Git`, Sources/Intel.m:48 and :56. 5 seconds, `GIT_OPTIONAL_LOCKS=0`, `GIT_TERMINAL_PROMPT=0`.
- WF `WFGitPath`, `WFGitInput`, `WFGit`, Sources/Common.m:71 to :105. The same path list, plus `--no-pager` and `LC_ALL=C`.
- NN `ExecGit`, internal/worktrees/worktrees.go:48. NN `tarDirty`, internal/worktrees/judge.go:118, calls bare `git` from PATH.

**Best.** WF. `LC_ALL=C` keeps output parseable on a Norwegian locale, and the caller sets the limit.

**Core API.**
```objc
NSString *MCGitPath(void);                     // nil when only the /usr/bin/git stub exists
NSString *MCGit(NSString *dir, NSArray<NSString *> *args, NSTimeInterval timeout, int *status);
NSString *MCGitInput(NSString *dir, NSArray<NSString *> *args, NSData *input, NSTimeInterval timeout, int *status);
```

#### 11. Repo and worktree discovery

**Implementations.**
- WF `Walk`, Sources/Trees.m:57, then `Worktrees`, :76, which parses `git worktree list --porcelain`, then `Discover`, :647.
- NN `DiscoverRepos` and `walk`, internal/worktrees/worktrees.go:262. NN `ParseWorktreeList`, worktrees.go:75. NN `scanRepos`, internal/scan/repos.go. Two repo walks inside NN alone.
- LH `ReadGit`, Sources/Ports.m:265. It finds the repo above a server's cwd by reading `.git`, `HEAD` and the index time straight from disk, with no git process. LH `GitInfo`, Ports.m:302, caches it for 30 seconds.

**Best.** WF's walk for discovery, since it skips cache folders and hidden folders and keeps searching a root that is itself a repo. LH's `ReadGit` for "which repo holds this path", since it spawns nothing.

**Core API.**
```objc
@interface MCRepoIndex : NSObject
+ (instancetype)shared;                                  // roots from rules, warm updates from FSEvents
- (NSArray<NSString *> *)repos;
- (NSArray<MCWorktree *> *)worktreesOf:(NSString *)repo;
- (MCWorktree *)worktreeAt:(NSString *)path;            // the deepest one holding the path
- (NSDictionary *)headOf:(NSString *)path;               // ReadGit: repo, root, branch, worktree, touched
@end
```

#### 12. Git facts and merge detection

**Implementations.**
- LH `GitFacts`, Sources/Intel.m:178. Last commit, dirty count, upstream and ahead or behind, the default branch, and `commits_not_in_default`. Intel.h:8 lists a `merged` key, but `GitFacts` never sets one.
- WF `RepoFacts`, `SquashMerged`, `MergedPR`, `ReadFacts`, `ReadStatus`, Sources/Trees.m:134 to :290. Merged by ancestor, tree, patch, squash or a merged pull request, plus stashes, unpushed and orphan commits.
- NN `gatherFacts`, internal/worktrees/worktrees.go:192. Remote containment through `git branch -r --contains HEAD`, and ahead of upstream.
- The default-branch lookup is copied: LH Intel.m:202 to :209 and WF Trees.m:138 to :144.

**Best.** WF for merge state. Add NN's remote containment as its own fact, because NN's comment says local-only merges have stranded work before (worktrees.go:208).

**Core API.**
```objc
@interface MCGitFacts : NSObject
@property (readonly, copy) NSString *branch, *head, *defaultBranch, *upstream, *merged;   // merged: ancestor | tree | patch | squash | pr | nil
@property (readonly) NSInteger dirty, untracked, stashes, unpushed, ahead, behind, notInDefault, orphanCommits;
@property (readonly) BOOL onRemote;                     // NN's remote containment
@property (readonly) NSDate *lastCommit, *fetched;
@end
MCGitFacts *MCGitFactsFor(NSString *worktree, BOOL checkPRs);   // cached by HEAD, entry 14
```

#### 13. Disk sizing

**Implementations.**
- WF `WalkDisk`, Sources/Trees.m:296. `fts` over `st_blocks * 512`, cache folders summed apart, nested repos skipped. Hard links are counted once per name.
- WF `SizeOf`, Sources/Forest.m:241. Logical `fileSize`, for the save limit.
- NN `sizer.Blocks`, internal/sizer/sizer.go:87, dedupes hard links by device and inode. NN `UniqueAllocated`, internal/sizer/extent_darwin.go:199, unions physical extents from `F_LOG2PHYS_EXT`, so APFS clones count once. NN `FreedByDelete`, internal/sizer/freed_darwin.go:17, measures `statfs` before and after.
- NN `core.DirSize`, internal/core/walk.go:11, sums logical sizes. NN `autoclean.DefaultDeleter` reports freed bytes from it (apply.go:57). Further walks sit in internal/leaks/family.go, internal/modules/orphanapps, internal/modules/dev and internal/modules/offload/sizes.go.

**Best.** NN's three tiers. The package comment gives the evidence: `du` called 65 Chrome clone folders 129 GB, and deleting 64 of them freed about 3 GB, and `UniqueAllocated` costs about 34 µs per file (sizer.go:1 to :35). WF's walk becomes the Blocks tier with NN's hard-link dedupe added.

**Core API.**
```objc
typedef struct { uint64_t logical, blocks, unique; NSInteger files, errors; NSDate *newest; } MCSize;
@interface MCSizer : NSObject
+ (MCSize)blocks:(NSString *)root cacheNames:(NSSet<NSString *> *)caches cacheBytes:(uint64_t *)cache;   // periodic
+ (MCSize)unique:(NSArray<NSString *> *)roots;                  // on demand, before a claim
+ (int64_t)freedOnVolume:(NSString *)path by:(BOOL (^)(void))action;   // the audit number
@end
```

#### 14. Fact caches with freshness

**Implementations.**
- LH `GitInfo`, Ports.m:302, 30 seconds. LH `LHIntel`, Intel.m:386, 5 minutes. LH `LHWhere` and `LHWhereRefresh`, Where.m:221 and :233. All three return the last answer at once and refresh on a serial queue.
- WF facts in facts.json, keyed by HEAD and 10 minutes (Trees.m:9, :688). Git status kept by a signature of HEAD, index time and newest file (Trees.m:720). Sizes in sizes.json for 6 hours, quick walks after 15 minutes (Trees.m:10, :11). Patch ids in patch-ids.json, keyed by the default branch tip (Trees.m:101, :103).

**Best.** WF's idea of a fingerprint key, such as HEAD or a status signature, with LH's non-blocking read. This is also the fingerprint cache PLAN.md section 4 asks for, so the review broker can use the same object.

**Core API.**
```objc
@interface MCFactCache<V> : NSObject
- (instancetype)initWithName:(NSString *)name maxAge:(NSTimeInterval)age persist:(BOOL)persist;   // persist: Store/<name>.json
- (V)valueFor:(NSString *)key fingerprint:(NSString *)fp;                   // nil when missing or the fingerprint moved
- (V)valueFor:(NSString *)key fingerprint:(NSString *)fp orCompute:(V (^)(void))work wait:(BOOL)wait;   // wait NO: stale now, fresh later
- (void)forget:(NSSet<NSString *> *)liveKeys;                               // drop keys that are gone
@end
```

### Store

#### 15. The support folder and the test home

**Implementations.**
- LH `LHSupportDir`, Sources/Ports.m:32, honors `$LOCOHOST_HOME`.
- WF `WFSupportDir`, Sources/Common.m:17, honors `$WORKFOREST_HOME`.
- MM `-[MMRules fileURL]`, Sources/Rules.m:83, creates `MinMacs` under `NSApplicationSupportDirectory` on every call. MM `defaultRowDirectories`, Agents.m:43, adds `MinMacs/agents`.
- NN `config.go:143` to `:164`: `~/Library/Application Support/noo-noo` for the socket, `store.db` and `worktree-graves`, and `~/.config/noo-noo/config.toml` for settings (internal/cli/worktrees_cmd.go:20).
- IN keeps no folder. All its state lives in prefs.

**Best.** LH and WF: one function, one environment override for tests.

**Core API.**
```objc
NSString *MCSupportDir(void);                    // ~/Library/Application Support/MinMacs, or $MINMACS_HOME
NSString *MCExpertDir(NSString *expert);         // Store/<expert>, created on first use
```

#### 16. Preferences

**Implementations.**
- LH `PrefGet`, `PrefSet`, `PrefBool`, `PrefInt`, main.m:34 to :41, on `CFPreferences` domain `no.guerrilla.locohost`.
- WF `WFPref`, `WFSetPref`, `WFPrefBool`, `WFPrefInt`, Sources/Forest.m:12 to :19, domain `no.guerrilla.workforest`. `FindTool` reads the same domain with its own `CFPreferencesCopyAppValue` call (WF Review.m:150).
- MM `PrefGet` and `PrefSet`, main.m:30 to :38, domain `no.guerrilla.minmacs`. The comment says the explicit domain lets the CLI, run through a symlink, share prefs with the app.
- IN `-[Insomnia d]`, Sources/main.m:219, uses `NSUserDefaults.standardUserDefaults`, which only works from inside the bundle (unverified). MM main.m:28 says a CLI run through a symlink may not resolve the bundle.
- Test overrides through the environment: LH `EnvMinutes`, main.m:59. WF `EnvHours`, Forest.m:29.
- NN loads TOML over compiled defaults, internal/config/config.go.

**Best.** The CFPreferences helpers in LH, WF and MM, with one domain. Keys keep an expert prefix, as they already do.

**Core API.**
```objc
id MCPref(NSString *key);                        // domain no.guerrilla.minmacs, keys like "locohost.mode"
void MCSetPref(NSString *key, id value);
BOOL MCPrefBool(NSString *key, BOOL dflt);
NSInteger MCPrefInt(NSString *key, NSInteger dflt);
NSTimeInterval MCEnvSeconds(NSString *envKey, NSTimeInterval dflt);   // test overrides
```

#### 17. Rules files

**Implementations.**
- LH `LHRules`, Sources/Rules.m. `Defaults` at :4, `reload` at :46 merges new defaults in and never removes an entry. Not synchronized.
- WF `WFRules`, Sources/Rules.m. The same `Defaults` and `List` helpers, with `@synchronized` around every read and write (Rules.m:39 to :105).
- MM `MMRules`, Sources/Rules.m. Defaults as C arrays, a `version` that gates `mergeDefaults` (:126). `setVerdict:forBundleID:` at :159 removes every pattern that matches the bundle id, so marking one app drops a wildcard rule that other apps relied on. PLAN.md section 2 names this bug.
- NN's equivalent is TOML config plus code-defined signatures.

**Best.** WF: synchronized, additive merge of defaults, one `List` helper. MM's wildcard match is worth keeping, without the removal in `setVerdict:`.

**Core API.**
```objc
@interface MCRules : NSObject
+ (instancetype)rulesFor:(NSString *)expert defaults:(NSDictionary *)defaults;   // Store/<expert>/rules.json
- (NSArray *)list:(NSString *)group key:(NSString *)key;
- (BOOL)list:(NSString *)group key:(NSString *)key matches:(NSString *)value;     // exact, prefix*, *contains*
- (void)set:(BOOL)on value:(id)value inList:(NSString *)group key:(NSString *)key; // touches only this exact entry
- (void)reload;
@end
```

#### 18. State files

**Implementations.**
- LH activity.json with `LoadActivity` and `SaveActivity`, Ports.m:367 and :376. Save merges with what is on disk so the CLI and the app never erase each other, and forgets hosts after a week.
- LH keep.json, `KeepList` and `SetKeep`, main.m:92 to :107. LH closed.json, `Closed` and `SetClosed`, main.m:279 to :289. LH review.json, Review.m:23. All three read, change and write without a merge.
- WF kept.json, Forest.m:87. WF removed.json, Forest.m:222. WF review.json, Review.m:25. WF facts.json, sizes.json and patch-ids.json, Trees.m:333, :334, :101. WF watching-since, Forest.m:37.
- MM keeps restore state in prefs, `kClosedKey` and `kClosedTabsKey`, main.m:16 and :17, cleared on restore.
- IN keeps timestamps in prefs: `insomnia.unpluggedAt`, `offlineAt`, `agents.workingAt` (main.m:17, :21, :27).
- NN uses SQLite in WAL mode with versioned migrations, internal/store/store.go:37, and append-only JSONL for audit, internal/audit/audit.go:44.
- On this Mac, `ls` shows LocoHost's folder holds activity.json, closed.json, review.json, rules.json, and leftover review-answer.json and review-schema.json. WorkForest's holds facts.json at 70 KB, 58 KB at verification since the app rewrites it, patch-ids.json at 142 KB, review.json at 81 KB, rules.json, sizes.json and watching-since.

**Best.** LH's merge-on-save from activity.json for every shared file. Only it is safe when the CLI and the app write the same file. That the other files can lose a write when both run at once is a guess, not tested. NN's SQLite is the strongest store, but it adds a dependency that clang-only Objective-C would have to take on as libsqlite3.

**Core API.**
```objc
@interface MCStateFile : NSObject
+ (instancetype)fileNamed:(NSString *)name expert:(NSString *)expert;
- (id)read;                                                     // JSON, or nil
- (void)update:(id (^)(id disk))change;                         // flock, read, change, write atomically
@end
```

### Review

#### 19. The model call

**Implementations.**
- LH `FindTool`, `Run`, `AskClaude`, `LunaModels`, `TOMLString`, `CodexMessage`, `AskCodexModel`, `AskCodex`, `Ask`, Sources/Review.m:163 to :363.
- WF the same functions, Sources/Review.m:146 to :351. After renaming the prefixes, `diff` finds one real difference. LH writes the codex schema and answer to fixed names, review-schema.json and review-answer.json, and never deletes them (LH Review.m:283). WF tags each file with a UUID, because batches run side by side, and deletes both after reading (WF Review.m:266, :303, :304). The two leftover files sit in LocoHost's support folder on this Mac.
- NN `Judge`, internal/worktrees/judge.go:69. It runs a user-configured `judge_cmd` through `/bin/sh -c` with a 5-minute limit and parses the first JSON object with a valid verdict.

**Best.** WF. It is safe to run in parallel and cleans up after itself. Both keep the user's own login by dropping API keys from the environment, and run in the support folder so no project CLAUDE.md or AGENTS.md is read (WF Review.m:176, :209).

**Core API.**
```objc
@interface MCAnswer : NSObject
@property (readonly) NSDictionary *json; @property (readonly, copy) NSString *model, *note, *error;
@property (readonly) NSInteger tokens; @property (readonly) double costUSD, seconds;
@end
@interface MCModel : NSObject
+ (NSArray<NSArray<NSString *> *> *)models;          // [alias, label]
+ (NSString *)labelFor:(NSString *)alias;
+ (MCAnswer *)ask:(NSString *)model system:(NSString *)system schema:(NSDictionary *)schema input:(NSDictionary *)input;   // blocks; "auto" is Haiku, then Luna
@end
```

#### 20. The review record and the verdict

**Implementations.**
- LH `LHReview` and `LHVerdict`, Sources/Review.h. Verdicts `in_use | idle | unsure`, fields what, how, why, waste, recommendation, keepEvidence, judged, confidence.
- WF `WFReview` and `WFVerdict`, Sources/Review.h. Verdicts `active | stale | unsure`, fields what, why, state, recommendation, keepEvidence, judged, confidence. `+load` and `-save` store the same top-level fields. They differ in the verdict fields listed above, in `hostCount` and `treeCount`, and in the `hosts` and `trees` keys, and WF also checks that each entry is a dictionary.
- NN `Verdict`, internal/worktrees/judge.go: `remove | keep` and a reason.

**Best.** One record with an expert field. The verdict words differ, but each expert has a keep word, a go word and unsure.

**Core API.**
```objc
typedef NS_ENUM(NSInteger, MCVerdictKind) { MCVerdictKeep, MCVerdictGo, MCVerdictUnsure };
@interface MCVerdict : NSObject
@property MCVerdictKind kind; @property double confidence; @property BOOL judged;
@property (copy) NSString *about, *reason, *keepEvidence;
@property (copy) NSDictionary<NSString *, NSString *> *notes;      // what, how, why, waste, state, recommendation
@end
@interface MCReview : NSObject
@property (copy) NSString *expert, *model, *note, *error, *judgeError, *summary, *trigger, *mode;
@property NSDate *at; @property NSInteger tokens, subjectCount; @property double seconds, costUSD;
@property NSDictionary<NSString *, MCVerdict *> *verdicts; @property NSArray<NSDictionary *> *actions;
+ (instancetype)loadFor:(NSString *)expert; - (void)save;
@end
```

#### 21. Facts sent to the model, and redaction

**Implementations.**
- LH `LHRedact`, Sources/Review.m:74. WF `WFRedact`, Sources/Common.m:29. The same four regular expressions. WF returns nil for nil input, LH does not check.
- LH `Clip`, Sources/Intel.m:9. WF `WFClip`, Common.m:62.
- LH `CommandFor`, Review.m:90: redacted, home as `~`, 400 characters at most. LH `+factsFor:scanner:`, Review.m:377. WF `+factsFor:`, Review.m:369. Both drop the session file path as "a local path, not evidence".
- NN `Dossier`, internal/worktrees/judge.go: a fixed struct of facts.

**Best.** WF's nil-safe `WFRedact` and `WFClip`. Facts stay per expert, but every string goes through one redactor.

**Core API.**
```objc
NSString *MCRedact(NSString *s);                 // nil in, nil out
NSString *MCClip(NSString *s, NSUInteger max);   // one line, redacted, ~ for home
NSString *MCTilde(NSString *path);
```

#### 22. Batching and parallel calls

**Implementations.**
- WF `Batches`, Sources/Review.m:410. 25 worktrees per call (Review.m:5) and 3 calls at a time (Review.m:6), through `dispatch_apply` and a semaphore. Each batch gets a scratch review whose tokens fold into the total.
- LH `+review:scanner:model:`, Review.m:406. One call for every host.
- NN asks the judge about one dossier per call. Its comment says batch judging invites cross-contamination of reasoning (judge.go:54).

**Best.** WF's `Batches`, with batch size per expert. NN's concern is an argument for small batches, not for one call per item. That is a guess until Research F measures it.

**Core API.**
```objc
@interface MCReviewBroker (Batches)
- (BOOL)run:(NSArray *)subjects batch:(NSUInteger)size parallel:(NSUInteger)n
      model:(NSString *)model system:(NSString *)system schema:(NSDictionary *)schema
      input:(NSDictionary *(^)(NSArray *batch))input parse:(void (^)(NSDictionary *json, NSArray *batch))parse into:(MCReview *)r;
@end
```

#### 23. The judge

**Implementations.**
- LH `+judge:review:scanner:model:`, Review.m:464, with `kJudge` at :441 and `JudgeSchema` at :456. Decisions `keep | stop`.
- WF `+judge:review:model:`, Review.m:487, through `Batches`. Decisions `keep | remove`.
- LH `JudgeSubjects`, main.m:177. WF `WFJudgeSubjects`, Forest.m:182. Same rule: free to decide, not judged, and not already sure.
- The thresholds are copied: `kMinConfidence = 0.6` and `kSureConfidence = 0.8` in LH main.m:26 and :27 and WF Forest.m:5 and :6.
- NN `Judge`, judge.go:69. Any failure to get a ruling means keep.

**Best.** WF's batched judge, with NN's rule made explicit: a failed judge keeps. LH and WF already fall back to the first verdict on failure through `judgeError`.

**Core API.**
```objc
@interface MCReviewBroker (Judge)
- (void)judge:(NSArray *)subjects review:(MCReview *)r prompt:(NSString *)system goWord:(NSString *)go;
@end
extern const double MCMinConfidence;   // 0.6
extern const double MCSureConfidence;  // 0.8
```

#### 24. The summary

**Implementations.**
- LH takes `summary` from the one review answer, Review.m:437.
- WF keeps one summary per batch. With several batches it makes one more call with `kSummary` (Review.m:117) over a line per worktree. It prepends totals it counts itself, because the model "miscounted 99 worktrees as 92 in a real run" (Review.m:457).
- The menu fits the summary to three lines of whole sentences: LH `FitSentences`, main.m:1055, used at :1256. WF `FitSentences`, main.m:573, used at :787.

**Best.** WF: numbers from code, words from the model. For Core, one summary per workstream across experts. PLAN.md section 4 proposes one block of facts per workstream. A summary per workstream is this report's extension of that.

**Core API.**
```objc
@interface MCReviewBroker (Summary)
- (NSString *)summaryFor:(MCReview *)r totals:(NSString *)countedByCode;
@end
NSString *MCFitSentences(NSString *text, NSFont *font, CGFloat width, NSInteger lines);
```

#### 25. What wakes a review

**Implementations.**
- LH `-watchEvents`, main.m:870. A new dev server after 2 minutes up, uptime marks of a day, 3 days and a week, load above the core count for 30 seconds. Memory pressure through the dispatch source. Schedule every 60 minutes (main.m:902). Event reviews at least 10 minutes apart (main.m:30).
- WF `-watchEvents`, main.m:387. A new worktree, quiet marks of a week, a month and 3 months, low disk. Schedule every 120 minutes (main.m:409). Event reviews at least 30 minutes apart (main.m:19).
- NN `pressure` package: a trigger fires after a sustained breach for `DebounceSeconds` (config.go `PressureCfg`).
- PLAN.md section 4 says events are "spaced at least ten minutes apart". WF uses 30 minutes today.

**Best.** The shared shape of LH and WF: learn on the first pass, then wake on a new subject, an age mark or a pressure signal, with a minimum gap. In Core this becomes one wake queue that all experts post to.

**Core API.**
```objc
@interface MCReviewBroker (Wake)
- (void)wake:(NSString *)reason expert:(NSString *)expert;     // coalesced, at least minGap apart
@property NSTimeInterval minGap;                                // 10 minutes, PLAN.md section 4
- (void)markAges:(NSArray *)subjects key:(NSString *(^)(id))key age:(NSTimeInterval (^)(id))age
           marks:(NSArray<NSNumber *> *)marks expert:(NSString *)expert;
@end
```

### Act

#### 26. Modes and the watching period

**Implementations.**
- LH `LHMode`, `ModeNames`, `ModeLabel`, `ModeFrom`, `Mode`, main.m:52 to :56. WF `WFMode` and the same five functions, Forest.m:22 to :26. Both default to Eager (LH main.m:56, WF Forest.m:25).
- WF `WFGraceOver`, `WFStartWatching`, `WFGraceLeft`, Forest.m:37 to :56. No mode acts in the first 24 hours (Forest.m:35). LH has no such period. Its closest rule is `MinUptime`, 30 minutes per server (main.m:63).
- LH and MM `ForceMode`, `Never | Ask | Always`, LH main.m:24 and MM main.m:23. A second, separate setting for what to do when a stop is refused.
- NN auto-clean and auto-apply need a switch and a risk-acknowledged timestamp, the "two-key opt-in" (config.go `OffloadCfg` comment).

**Best.** The WF set: the same three modes plus the watching period. PLAN.md section 5 says experts start in Proactive and act "after a day of watching". Both apps default to Eager today, and only WF has the day of watching.

**Core API.**
```objc
typedef NS_ENUM(NSInteger, MCMode) { MCModeIdle, MCModeProactive, MCModeEager };
MCMode MCModeFor(NSString *expert);                          // Proactive by default
void MCSetMode(NSString *expert, MCMode m);
BOOL MCWatchedLongEnough(NSString *expert);                  // a day after first launch
typedef NS_ENUM(NSInteger, MCForce) { MCForceNever, MCForceAsk, MCForceAlways };
```

#### 27. MustKeep and the plan

**Implementations.**
- LH `MustKeep`, main.m:115, then `Plan`, :134, `Candidates`, :76, and `RunReview`, :189.
- WF `WFWorkKeeps`, Forest.m:110, `WFMustKeep`, :134, `WFPlan`, :144, `WFCandidates`, :193, `WFRunReview`, :203.
- NN `Classify`, internal/worktrees/worktrees.go:156: active, obvious or judgment. Obvious needs clean, on a remote, idle and no open files.
- The plan entry shape is the same in LH and WF: subject, act yes or no, and one line of why. `Plan` and `WFPlan` test their branches in the same order, and the Eager branches match line for line. The Proactive branch differs: LH needs a sure idle verdict, WF needs merged or upstream gone. WF also needs merged or upstream gone when the judge failed, and it adds the watching-period check (Forest.m:176).

**Best.** WF. It splits the work reasons, which are checked again on fresh facts right before any removal, from the review reasons. LH mixes both in one function.

**Core API.**
```objc
@protocol MCSubject <NSObject>
@property (readonly) NSString *key, *expert;
@end
@protocol MCExpertPolicy <NSObject>
- (NSString *)workKeeps:(id<MCSubject>)s;                     // fresh facts only; nil when free
- (NSString *)reviewKeeps:(id<MCSubject>)s review:(MCReview *)r;
@end
@interface MCPlanEntry : NSObject
@property (readonly) id<MCSubject> subject; @property (readonly) BOOL act; @property (readonly, copy) NSString *why;
@end
NSArray<MCPlanEntry *> *MCPlan(NSArray<id<MCSubject>> *subjects, MCReview *r, MCMode mode, id<MCExpertPolicy> policy);
```

#### 28. Keep and protect

**Implementations.**
- Keep for a while. LH `KeptUntil` and `SetKeep`, main.m:100 and :102, 4 hours from the menu (main.m:1451), keyed by host key `pid:start`. A restarted server gets a new key, so the keep does not follow it. WF `WFKeptUntil` and `WFSetKept`, Forest.m:95 and :100, a week from the menu (WF main.m:956), keyed by path.
- Protect for good. LH rules `protect.names`, `ports`, `paths`, Rules.m:8. WF rules `protect.paths` and `branches`, Rules.m:9. MM rules `keep`, by bundle id with wildcards, Rules.m:153.
- Ignore. LH `ignore.names` and `devApps`, Rules.m:15. WF `ignore.paths`, Rules.m:13. MM `ignoreServing`, Rules.m:190.

**Best.** WF's keep keyed by a stable identity. Core keys keeps by what the user sees, such as the project folder and port for a server.

**Core API.**
```objc
@interface MCKeep : NSObject
+ (NSDate *)keptUntil:(NSString *)stableKey expert:(NSString *)expert;
+ (void)keep:(NSString *)stableKey expert:(NSString *)expert until:(NSDate *)until;   // nil ends it
@end
BOOL MCProtected(NSString *expert, NSString *list, NSString *value);   // over MCRules
```

#### 29. Stopping and quitting, checked fresh

**Implementations.**
- LH `StopHostsBy`, main.m:301. It skips any pid that is no longer the same process, records the stop, sends SIGTERM to the tree and the package-manager wrapper (`Targets`, :260), and waits 6 seconds (main.m:25). `KillHosts`, :331, sends SIGKILL. `-escalate:`, :1391, asks before force.
- MM `QuitApps`, main.m:141, `ForceQuitApps`, :148, and `-escalate:`, :661. The same flow for apps with an 8-second grace (main.m:24).
- `StillRunning` is the same polling loop in LH main.m:267 and MM main.m:129.
- Checked fresh. LH samples again on the main queue before `AutoStop` (main.m:939, and :1367 for Close Idle). WF `WFRemove` reads the worktree again with `+[WFScanner fresh:]` and runs `WFWorkKeeps` on it (Forest.m:276 to :278). NN re-verifies a pid at apply time (modules/module.go:64) and gates obvious worktrees on `lsof` (worktrees.go:182).

**Best.** LH's stopper for processes and MM's for apps, behind one interface, with WF's rule that every action re-reads its subject first.

**Core API.**
```objc
@protocol MCAction <NSObject>
- (NSString *)recheck;                       // nil to go ahead, else why it now stays
- (BOOL)perform:(NSString **)error;          // records undo first, entry 30
@end
NSArray<NSNumber *> *MCTerminate(NSArray<NSNumber *> *pids, MCProcKey owner, NSTimeInterval grace, MCForce force);
NSArray<NSRunningApplication *> *MCQuitApps(NSArray<NSRunningApplication *> *apps, NSTimeInterval grace, MCForce force);
```

#### 30. Undo records and restore

**Implementations.**
- LH closed.json, `RememberClosed`, main.m:291, keeps 20 records with the restart command (main.m:296). `Restart`, main.m:313, runs it through `zsh -lc`.
- WF removed.json, `WFRemove`, Forest.m:274. It saves ignored files that are not caches, such as `.env.local`, up to 20 MB each and 100 MB in all (`SaveIgnored`, :252, limits at :8). It runs `git worktree remove` without `--force` and `git branch -d` only when merged. It keeps 50 records. `WFRestore`, :307, recreates the worktree and puts the files back.
- MM `RememberClosed` and `RememberTabs`, main.m:155 and :160, in prefs with no limit. `RestoreAll`, :184, reopens every app and tab, then clears both lists.
- NN audit JSONL, internal/audit/audit.go:44. The auto-clean row is written before the delete as `in_progress`, so a crash leaves a trail (internal/autoclean/apply.go:16 to :21). `Grave`, internal/worktrees/module.go:206, makes a `git bundle` of HEAD and a tarball of dirty files before a judged removal. Offload renames the target to a backup and renames it back on failure (internal/modules/offload/offload.go:366 to :376).
- NN deletes for good with `os.RemoveAll` in internal/modules/caches/caches.go:152, internal/modules/dev/syscalls.go:14, internal/leaks/module.go:200, internal/leaks/family.go:393, internal/modules/orphanapps/orphanapps.go:291 and internal/autoclean/apply.go:59. Offload also calls it on its backup after a verified move (internal/modules/offload/offload.go:385) and on partial copies.

**Best.** WF's record shape and restore, plus two rules from NN: write the record before acting, and take a git bundle when commits could be lost. Files go to the Trash, as PLAN.md principle 5 says, instead of NN's `RemoveAll`.

**Core API.**
```objc
@interface MCUndoRecord : NSObject
@property (readonly, copy) NSString *rid, *expert, *kind, *subject, *by, *why, *state;   // state: pending | done | failed | restored
@property (readonly) NSDate *at; @property (readonly) NSDictionary *payload;             // restart command, head, saved files, trashed URLs
@end
@interface MCUndo : NSObject
+ (instancetype)shared;
- (MCUndoRecord *)begin:(NSString *)expert kind:(NSString *)kind subject:(NSString *)s why:(NSString *)why payload:(NSDictionary *)p;
- (void)finish:(MCUndoRecord *)r ok:(BOOL)ok freedBytes:(int64_t)freed;
- (NSURL *)trash:(NSURL *)item record:(MCUndoRecord *)r error:(NSError **)e;   // NSFileManager trashItemAtURL
- (NSString *)restore:(NSString *)rid;                                           // nil on success
- (NSArray<MCUndoRecord *> *)recent:(NSString *)expert;
@end
```

#### 31. Notifications

**Implementations.**
- LH `-notify:mode:`, main.m:948, and WF `-notify:mode:`, main.m:454. Both use `UNUserNotificationCenter` with a title of what the mode did and how much it freed, and a body that names the undo place. Both ask for permission at launch (LH main.m:861, WF main.m:369).
- NN `Notifier.Send`, internal/notify/notify.go:33, runs `osascript display notification`.

**Best.** LH and WF. One function in Core.

**Core API.**
```objc
void MCNotify(NSString *expert, NSString *title, NSString *body, NSString *undoRid);   // later: a Restore action
```

### UI

#### 32. The app shell: status item, click, login item

**Implementations.**
- Status item and click. LH main.m:850, WF main.m:364, MM main.m:411, IN main.m:263. Each sends both mouse buttons to `handleClick:`. LH and WF build the menu on click and pop it with `performClick:` (LH main.m:1358, WF main.m:749). IN toggles on left click and shows the menu on right click (IN main.m:323).
- Launch at login. `-toggleLogin` with `SMAppService.mainAppService` is the same four lines in LH main.m:1474, WF main.m:983, MM main.m:713 and IN `toggleLaunchAtLogin`, main.m:342.
- `main()`. LH main.m:1497, WF main.m:1007 and MM main.m:737 are identical apart from the class: an argument that does not start with `-` runs the CLI, otherwise the app starts as an accessory.

**Best.** The LH and WF click handler, which builds a fresh menu on each click. One app delegate in Core owns up to five status items.

**Core API.**
```objc
@protocol MCExpert <NSObject>
@property (readonly) NSString *name, *symbol;                 // "LocoHost", "server.rack"
- (NSString *)buttonTitle;                                    // " 4 · 1 idle"
- (NSMenu *)buildMenu:(MCMenuKit *)kit;
- (int)runCLI:(NSArray<NSString *> *)args;
- (BOOL)handleURL:(NSURL *)url;
@end
@interface MCApp : NSObject <NSApplicationDelegate>
- (void)registerExpert:(id<MCExpert>)e;                       // its status item shows unless hidden in Settings
- (void)setLaunchAtLogin:(BOOL)on;
@end
```

#### 33. The menu kit

**Implementations.**
- `Item`, `Header`, `Sub`. LH main.m:964 to :969, WF main.m:468 to :473. MM has `Item` and `Header` only, main.m:441 and :445. IN has `Item`, main.m:352.
- `Titled`, `Para`, `Rich`, `TextItem`, `Sentence`, `Section`, `FitSentences`, `MenuHeader`. LH main.m:997 to :1081, WF main.m:476 to :590. `diff` finds drift in widths and words. `TextItem` is 302 points inside 330 in LH and 312 inside 340 in WF. WF `Para` sets word wrapping, LH does not. WF `Sentence` also accepts a final `?`.
- Shared name prefix left out of rows. LH `self.prefix`, main.m:1243. WF `Prefixes`, main.m:731.
- LH `ModernMenu`, main.m:1006, gates subtitles and badges on macOS 14.4. WF checks `@available(macOS 14.4, *)` inline (main.m:700).

**Best.** WF's versions, as the newer pass. LH's commit is "Hold the menu to the shared standard" and WF's is "A quieter menu, held to a written standard", so both had the same goal. One kit with one width fixes the drift.

**Core API.**
```objc
@interface MCMenuKit : NSObject
@property (readonly) CGFloat width, textWidth;                // one width for every expert
- (NSMenuItem *)item:(NSString *)title action:(SEL)a target:(id)t on:(BOOL)on in:(NSMenu *)m;
- (NSMenuItem *)sub:(NSString *)title menu:(NSMenu *)sub in:(NSMenu *)m;
- (void)section:(NSString *)title in:(NSMenu *)m;
- (NSMenuItem *)header:(NSString *)big unit:(NSString *)unit line:(NSString *)line;   // two lines
- (NSMenuItem *)text:(NSString *)text lines:(NSInteger)n;                             // cut at a whole sentence
- (NSMenuItem *)row:(NSString *)name facts:(NSArray<NSString *> *)facts badge:(NSString *)badge;   // at most three facts
- (NSAttributedString *)title:(NSString *)t tail:(NSString *)grayTail;
@end
NSString *MCSentence(NSString *s);
NSDictionary<NSString *, NSString *> *MCSharedPrefixes(NSArray<NSString *> *names, NSArray<NSString *> *groups);
```

#### 34. The hover card

**Implementations.**
- LH `-statusFor:`, main.m:1083, and `-cardFor:`, main.m:1116. Inner width 350 (main.m:1117), label column 50 (main.m:1163).
- WF `-statusFor:`, main.m:596, and `-cardFor:`, main.m:633. Inner width 360 (main.m:634), label column 62 (main.m:675). WF turns off the fixed height on the status line so it wraps as it draws (main.m:646). LH sets the constant by hand (main.m:1129).
- Both share the title, colored status, fact grid and the check that the model's note does not repeat the status.
- MM has no cards. It puts actions in submenus (MM main.m:447).

**Best.** WF's card. Core fixes one label column, so facts line up across experts, as DESIGN.md asks for between cards.

**Core API.**
```objc
@interface MCCard : NSObject
@property (copy) NSString *title, *statusHead, *statusText, *note;
@property (strong) NSColor *statusColor;
- (void)fact:(NSString *)label value:(NSString *)value;       // empty values are left out; at most five
- (void)link:(NSString *)label toExpert:(NSString *)expert key:(NSString *)key;   // "worktree speed-3-base, merged"
- (NSMenuItem *)menuItem:(MCMenuKit *)kit;
@end
```

#### 35. The render harness

**Implementations.**
- WF tools/render.m and tools/render.sh. render.sh compiles main.m with `-Dmain=xx_main`, links the sources and render.m, and renders the menu and five cards to PNG in light and dark, plus a first-day state from a fresh `watching-since` (render.sh:8 to :16). WF docs/RENDER.md describes it.
- LH docs/DESIGN.md:36 tells you to compile `main.m` with `-Dmain=lh_main` into a harness. LH exports `LHMenuPlan` "so a snapshot harness can build the same card" (main.m:169). `git ls-files` shows no render tool in the LH repo.

**Best.** WF's. In Core it renders every expert's header and cards from fixture subjects.

**Core API.**
```objc
// tools/render.m links Core and the experts with no app delegate.
void MCRenderMenu(NSMenu *menu, NSString *path, NSAppearance *appearance, CGFloat width);
void MCRenderView(NSView *view, NSString *path, NSAppearance *appearance, CGFloat width);
```

#### 36. Words and number formatting

**Implementations.**
- Bytes. `LHFormatBytes`, Ports.m:18. `WFFormatBytes`, Common.m:3. `MMFormatBytes`, Scanner.m:35. All three identical. NN `core.Bytes.String`, internal/core/size.go:21.
- Durations. `LHDuration`, Ports.m:24. `WFDuration`, Common.m:9, drops the hours beyond 7 days. IN `FormatDuration`, main.m:105, writes "3 h 04 min".
- Plurals. LH main.m:66 and WF main.m:22 add "es" after a final s. WF Forest.m:60 and MM main.m:125 do not, so WF has two plural rules in one app.
- `Cut`, LH main.m:360 and WF main.m:24. `Tokens`, LH main.m:68 and WF main.m:23. `LHShellQuote`, Ports.m:38, and `WFShellQuote`, Common.m:23.

**Best.** WF's duration and LH's plural. Core has one of each. DESIGN.md rule 2 says only that a number appears once, not that it reads the same everywhere.

**Core API.**
```objc
NSString *MCBytes(uint64_t b);
NSString *MCDuration(NSTimeInterval s);
NSString *MCShortDuration(NSTimeInterval s);       // "5d"
NSString *MCPlural(NSInteger n, NSString *word);
NSString *MCCut(NSString *s, NSUInteger n);        // tail only
NSString *MCShellQuote(NSString *s);
```

### CLI, scripts and tests

#### 37. The CLI parser and the one binary

**Implementations.**
- LH `RunCLI`, main.m:483. WF `RunCLI`, main.m:112. MM `RunCLI`, main.m:261. Each opens the same way: argv to an array, `--json`, `--yes`, an `opt` block for `--name value`, then a chain of `if ([cmd isEqualToString:...])`. LH's `Usage` lists 19 verbs (main.m:422).
- LH `Confirm`, main.m:402, and WF `Confirm`, main.m:79. LH `PrintJSON`, main.m:355, and WF `PrintJSON`, main.m:54.
- NN `Register` and `App.Run`, internal/cli/cli.go:25 and :30. A map from verb to handler, filled from each command file's `init`.

**Best.** NN's registry shape in Objective-C: each expert registers its verbs, and Core owns `--json`, `--yes`, `--dry-run`, usage and exit codes. PLAN.md section 7 keeps the names `locohost`, `workforest`, `noo-noo` and `insomnia` for the same binary. Picking the expert by `argv[0]` is this report's proposal for how.

**Core API.**
```objc
@interface MCArgs : NSObject
@property (readonly) NSString *verb, *arg1; @property (readonly) BOOL json, yes, dryRun, force;
- (NSString *)option:(NSString *)name;
@end
typedef int (^MCCommand)(MCArgs *args);
void MCRegisterCommand(NSString *expert, NSString *verb, NSString *usage, MCCommand cmd);
int MCRunCLI(int argc, const char **argv);         // argv[0] picks the expert for the old names
BOOL MCConfirm(NSString *question);
void MCPrintJSON(id obj);
```

#### 38. URL schemes

**Implementations.**
- LH `application:openURLs:`, main.m:1482: review, close-idle, login-on, login-off, quit.
- WF main.m:991: review, clean-up, rescan, login-on, login-off, quit.
- MM main.m:721: run, run-now, restore, login-on, login-off, quit.
- IN main.m:302: on, off, toggle, agents-on, agents-off, lid-on, lid-off, login-on, login-off, update, quit.
- Each reads `url.host` as the command. The login and quit cases are copied four times.

**Best.** One handler in Core that routes by scheme to the expert and owns login and quit. PLAN.md section 7 keeps the old schemes.

**Core API.**
```objc
void MCRegisterURLCommand(NSString *scheme, NSString *host, void (^run)(NSURL *url));   // main queue
```

#### 39. Calls between the apps today

**Implementations.**
- WF `LocoHosts`, Trees.m:396, runs `~/.local/bin/locohost list --json` on every scan, with a 20-second limit.
- IN `MinMacsWorking`, main.m:165, runs `minmacs agents --json` every 15 seconds in agent mode (main.m:502). That CLI samples twice with a 1-second sleep (MM main.m:285).
- MM opens `insomnia://on` before a run when its Insomnia setting is on and Insomnia is installed (MM main.m:651, `InsomniaInstalled` at :220).
- LH ignores listeners named `Insomnia` and `MinMacs` (LH Rules.m:21).
- NN talks to its own daemon over a Unix socket with JSON RPC (internal/ipc).

**Best.** None of them. PLAN.md principle 3 replaces all of these with reads from the shared graph. They are listed so the port deletes them.

**Core API.** The graph, which Research H designs. A sketch of the reads these calls become:
```objc
@interface MCGraph : NSObject
- (NSArray *)serversIn:(NSString *)folder;          // replaces locohost list --json
- (NSInteger)workingAgents;                          // replaces minmacs agents --json
- (void)holdAwake:(NSString *)reason until:(NSDate *)until;   // replaces insomnia://on
@end
```

#### 40. Build, install, uninstall and release scripts

**Implementations.**
- build.sh in LH, WF, MM and IN use the same clang line: `-fobjc-arc -O2 -Wall -mmacosx-version-min=13.0 -arch arm64 -arch x86_64`, ad-hoc `codesign --sign -` and install to `~/Applications`. LH, WF and MM also link a CLI in `~/.local/bin`. IN has no CLI link. LH and WF also re-register with `lsregister` so URLs reach the installed copy. MM copies only registry rows that pass tools/validate_row.py.
- install.sh in LH and IN are nearly the same script with names changed. IN drops the CLI link, adds `INSOMNIA_LID`, and verifies through `pmset -g assertions`. Both check for macOS 13 and the Command Line Tools, fetch a tarball with curl, build, quit the running copy through its URL, install, launch, verify.
- uninstall.sh in LH and WF are the same, except that WF moves removed.json and saved files to `~/WorkForest-removed-<date>` first. IN's also clears the lid override and the sudoers rule.
- release.sh in IN and MM. NN uses a Makefile and build/release scripts.

**Best.** The shared build.sh with WF's uninstall rule that undo data is never deleted. One script set for MinMacs.app.

**Core API.** Not code. One build.sh that compiles Core/, Experts/ and UI/ into one binary, and links the four old CLI names to it.

#### 41. Test harness, fakes and debug hooks

**Implementations.**
- A `check name want got` shell helper starts LH test.sh, WF test.sh, MM test.sh and IN test.sh. `grep -o 'check "'` counts 54, 55, 54 and 43 calls. PLAN.md section 9 says WorkForest has 62 checks. Checks inside loops may explain the gap. That is not verified.
- Fake model CLIs. LH and WF tools/fakeclaude.py, fakecodex.py and fakeanswer.py. The first two are the same shape. fakeanswer.py differs in its verdict rules.
- Fixture processes. MM tools/fakeagent.c, fakehost.c, stubborn.m and tools/fixtures. LH test.sh starts Python HTTP servers above port 47100 that it owns.
- Isolation through the environment: `LOCOHOST_HOME`, `WORKFOREST_HOME`, `WORKFOREST_ROOTS`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME` (LH test.sh:11 to :13, WF test.sh:12 to :15).
- Debug hooks in release code. IN reads `insomnia.debug.power`, `lid`, `thermal`, `net` and `agents` from prefs (IN main.m:83, :114, :130, :138, :512), and test.sh drives the running app through them. MM reads `minmacs.debug.cmuxDir` (MM main.m:21). PLAN.md section 2 asks to leave these out of release builds.
- NN Go tests inject `Runner` interfaces for some shell-outs (internal/notify/notify.go, internal/launchd/install.go). Others, such as `ExecGit` in internal/worktrees/worktrees.go:48, call `exec` directly.

**Best.** LH and WF: environment-isolated homes, fake CLIs, fixture-only processes. For Insomnia's guards, a fake `MCPower` passed in by the test, in place of prefs read by the release app.

**Core API.**
```objc
@protocol MCPowerSource <NSObject> - (MCPower *)read; @end      // tests pass a fixture
void MCUsePowerSource(id<MCPowerSource> src);                    // compiled only with -DMC_TESTS
```

#### 42. CI

**Implementations.**
- LH, WF, MM and IN .github/workflows/ci.yml build with `sh build.sh --no-install` and check script syntax with `sh -n`. None of them runs test.sh.
- NN ci.yml runs `gofmt`, `go vet`, `go test -race ./...` and golangci-lint.

**Best.** NN's: tests run on every push to main and every pull request (NN .github/workflows/ci.yml). PLAN.md section 9 asks for this from phase 1.

**Core API.** Not code. CI runs build.sh, then test.sh against fixtures, then the render harness, and keeps the PNGs as artifacts.

## Recommendations

1. **PLAN.md section 3, one sampler.** Build `MCSenses` from LH `-[LHScanner sample]` with `RUSAGE_INFO_V6`, one `kids` map and one socket table per pass. Make process args and cwd lazy per sample. This removes the MM 4-second walk, the WF per-scan walk and the IN 15-second `minmacs agents --json` spawn (entries 1 to 5, 39).
2. **PLAN.md section 3, Know.** Make MM's registry the only agent recognizer and drop LH's 18-name list. Build one `MCSessions` index the WF way, refreshed by FSEvents on `~/.claude/projects`, `~/.codex/sessions` and `~/.pi/agent/sessions` (entries 7, 8).
3. **PLAN.md section 3, Sizer.** Port NN's three tiers: blocks for periodic walks with hard-link dedupe, unique extents before any claim, and `statfs` before and after for the audit number (entry 13).
4. **PLAN.md section 3, Store.** One support folder, one prefs domain, `MCRules` from WF with MM's wildcards and without the removal in `setVerdict:`, and merge-on-write for every state file, as LH activity.json does (entries 15 to 18).
5. **PLAN.md section 4, fingerprint cache.** Build the review fingerprint on `MCFactCache`, which generalizes WF's HEAD-keyed facts.json and status signature. The same object then serves git facts, sizes and the review (entry 14).
6. **PLAN.md section 4, one broker.** Start the broker from WF Review.m: per-call temp files, `Batches`, judge through `Batches`, totals counted by code. Fix LH's fixed temp file names when porting. Make "a failed judge keeps" explicit, from NN (entries 19 to 24).
7. **PLAN.md section 4, wake events.** One wake queue with a 10-minute gap, as the plan says. WF uses 30 minutes today. LH's and WF's age marks become one `markAges` helper (entry 25).
8. **PLAN.md section 5, safe defaults.** Default every mode to Proactive and give every expert WF's day of watching. Both LH and WF default to Eager today, and only WF has the watching period (entry 26).
9. **PLAN.md principle 5 and section 3, Act.** Build `MCUndo` from WF removed.json and `WFRestore`, write each record before acting as NN's auto-clean does, take NN's git bundle before removing anything with commits on no remote, and use the Trash in place of NN's six `os.RemoveAll` calls on user data (entries 29, 30).
10. **PLAN.md section 3, Act.** Split every expert's keep reasons the WF way: `workKeeps` on fresh facts right before acting, `reviewKeeps` from the review. Key timed keeps by a stable key, not LH's `pid:start` (entries 27, 28).
11. **PLAN.md section 7, menus.** Extract `MCMenuKit` and `MCCard` from WF main.m with one width and one label column for all experts. Today LH and WF differ by 10 points of width and 12 points of label column (entries 33, 34).
12. **PLAN.md section 9, phase 0.** Port WF tools/render.m into Core in phase 0, since LH documents a harness it does not have (entry 35).
13. **PLAN.md section 7, CLI.** Replace the three `RunCLI` if-chains with a verb registry shaped like NN's `Register`, and one URL router that owns login and quit (entries 37, 38).
14. **PLAN.md section 9 and section 2, Insomnia.** Run `pmset` through `MCRun` off the main thread with a limit, and replace the `insomnia.debug.*` pref hooks with a test-only `MCPowerSource` (entries 9, 41).
15. **PLAN.md section 9, CI.** CI runs test.sh and the render harness on every push, as NN's CI runs its tests (entry 42).
16. **PLAN.md section 3, Words.** One set of formatters in Core. WF alone has two plural rules today (entry 36).

## Open questions

1. **SQLite or JSON.** NN keeps history in SQLite with migrations. The Objective-C apps use JSON files. Disk trends over weeks, PLAN.md section 6, may need a table. Does Core link `libsqlite3`, which ships with macOS, or keep JSON with merge-on-write?
2. **Verdict words.** Do the experts keep their own verdict words in prompts and the CLI, such as `idle`, `stale` and `remove`, while Core stores keep, go and unsure? Scripts may read `locohost review --json` today.
3. **Batch size.** NN judges one dossier per call to avoid cross-contamination. WF uses 25 per call. Research F should measure verdict agreement at 1, 5 and 25 per batch before the broker fixes a size.
4. **Keep key for servers.** What stable key should a server keep use: project folder and port, or folder and script? A guess is folder and port. LH's `pid:start` key ends the keep on restart.
5. **Merge rules for state files.** Merge-on-write is clear for activity.json. What is the merge rule for undo records written by the CLI and the app at the same moment? A file lock per file is the simple answer, untested here.
6. **Remote containment as a keep reason.** Should a worktree whose HEAD is on no remote always stay, as NN rules, even when WF finds it squash-merged into the local default branch?
7. **Test counts.** PLAN.md section 9 cites WorkForest's 62 checks. A grep finds 55 `check` calls. The verifier should run test.sh in a fixture home to get the real count.

## Verification

Checked on 2026-10-27 against the same commits: LH c48cc39, WF 2a6931f, MM `legacy` 8882121, IN 6d402a9, NN 1e6dc60. MM was read from `git archive legacy` into a scratch folder, because `main` now holds 7c3fe60. All commands were read-only. No test.sh was run, because test.sh builds fixtures and starts servers, so open question 7 stays open.

**Method.** A script read every cited file at every cited line and looked for the named symbol on that line. Every miss was then read by hand with its surrounding lines. Prose claims were checked by reading the code, diffing the copied functions after renaming the prefixes, and re-running the read-only commands.

**Counts.**

| Result | Count |
|---|---|
| Confirmed | 395 |
| Corrected | 17 |
| Unsupported, marked "(unverified)" | 3 |

The 395 confirmed claims are 351 file-and-line citations and 44 prose or command claims. The prose checks cover the commit hashes, the state files from `ls`, the test counts 54, 55, 54 and 43, the rusage versions and timers, the 18 agent names in LH, the 63 registry rows in MM, the byte-identical `FirstPrompt`, `ISODate` and `Match`, the single difference in the model-call code, the copied thresholds and default-branch lookup, the WF merge kinds and removal rules, the NN sizer, judge, store, audit and grave code, the event gaps and schedules, the menu and card widths, the identical `-toggleLogin` and `main()`, the 19 LH verbs, the URL verbs, the CI and build scripts, the render harness, and every PLAN.md and DESIGN.md reference except the ones corrected below.

**Corrected.**
1. Entry 3. The 500-pid cap sits at Ports.m:536, not :535.
2. Summary, entry 30 and recommendation 9. NN calls `os.RemoveAll` on user data at six sites, not five. The report missed internal/leaks/family.go:393. Offload also removes its backup after a verified move, offload.go:385.
3. Entry 1. `ps` counted 821 processes at verification. No MinMacs process was running, so only LocoHost walks the table today.
4. Entry 7. validate_row.py does not test the registry. MM build.sh:15 copies only the rows that pass it.
5. Entry 13. The NN comment says deleting 64 of the 65 clone folders freed about 3 GB.
6. Entry 20. LH and WF `+load` and `-save` differ in more than the `hosts` and `trees` keys.
7. Entry 24. PLAN.md section 4 proposes one block of facts per workstream, not one summary.
8. Entry 27. `Plan` and `WFPlan` share their branch order, but the Proactive and judge-failed branches differ.
9. Entry 33. MM has `Item` and `Header`, but no `Sub`.
10. Entry 36. DESIGN.md says a number appears once. It does not say a number reads the same everywhere.
11. Entry 37. PLAN.md section 7 keeps the old names. It does not mention `argv[0]`.
12. Entry 39. MM opens `insomnia://on` only when its Insomnia setting is on, as well as when Insomnia is installed.
13. Entry 40. IN build.sh makes no `~/.local/bin` link.
14. Entry 40. IN install.sh differs from LH's in three ways: the CLI link, the lid option and the check after install.
15. Entry 41. NN injects `Runner` for some shell-outs, not every one.
16. Entry 42. NN CI runs on pushes to main and on pull requests, not on every push.
17. Entry 18. facts.json measured 58 KB at verification. The app rewrites it, so the 70 KB figure was true only when the research ran.

**Unsupported.**
1. The summary's count of 38 concepts. The catalog has 42 entries, and nothing says which 4 the count leaves out.
2. Entry 16. Nothing shown here proves that `NSUserDefaults.standardUserDefaults` only works inside the bundle.
3. Entry 41. The idea that checks inside loops explain 55 against 62 was already marked as not verified. It stays open.

**Left as written.** The guesses that the report marks as guesses stay as they are. They cover lost writes to the state files in entry 18 and the batch size in entry 22. The Core API sketches and the recommendations are proposals, so this pass did not count them as claims.
