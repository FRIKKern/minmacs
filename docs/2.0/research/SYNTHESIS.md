# MinMacs 2.0 research synthesis

Synthesis of the eight research tracks for issue FRIKKern/minmacs#9. Written on 2026-10-27.

**Summary.** The eight tracks agree on the shape of 2.0 and settle most of the plan. One Senses pass costs about 6.3 ms of CPU on this Mac and replaces three private process walks. Every power, lid and memory fact reads from IOKit or sysctl in microseconds, so no tick needs `pmset`, `lsof`, `nettop` or `ps`. Clone-aware sizing with `getattrlistbulk` costs about what an fts walk costs, and it shows that a pnpm `node_modules` that du calls 1.5 GB frees 2.8 MB. Claude Code already writes a per-process status file that matched the `caffeinate` signal in 20 of 20 sessions, so MinMacs needs no hook to know which agent works. The review spends most of its tokens on unchanged worktrees and on thinking, so the fingerprint cache carries the token target. WorkForest's scan is today's largest cost, with a 3.6 GB peak footprint. The plan needs about 60 changes, listed by section below. Eighteen decisions remain for the owner, and a list of phase 0 and phase 1 tests settles the rest.

**How to read this file.**
- Each recommendation is named by track and number, such as A1 for track A's first recommendation. The tracks are [A](A-shared-patterns.md), [B](B-platform.md), [C](C-prior-art.md), [D](D-clutter.md), [E](E-agent-events.md), [F](F-review-economics.md), [G](G-menu-ux.md) and [H](H-architecture.md).
- Each track file ends with a verification pass. This file uses a claim only as the verifier left it. A claim the verifier marked "(unverified)" keeps that mark here.
- A code path is relative to its repo: LH is `~/Documents/GitHub/locohost`, WF is `~/Documents/GitHub/workforest`, MM is `minmacs` on branch `legacy`, IN is the insomnia clone and NN is the noo-noo clone.
- The prefix `MC` in the sketches is a placeholder, as track A says. Decision 17 asks for the real one.

## 1. The Core API

Track A found 42 concepts that our five codebases build more than once. This catalog splits a few of them in two and adds the patterns that tracks B, D, E, F, G and H found missing, such as exit watching, the session status file and the graph snapshot. That gives 66 patterns, P1 to P66, grouped below by the Core folders in PLAN.md section 3.

Each group has a table and one header sketch. The table names the pattern, the code Core starts from and the track that chose it. The sketch shows the interface, not the implementation. A pattern marked "new" has no implementation in our code today.

### 1.1 Runtime: queues, budgets and isolation

| # | Pattern | Start from | Source |
|---|---|---|---|
| P1 | Labeled serial queue per knower, with an autorelease pool per block | New. Today WF runs its scan on global queues with no pool, `Trees.m:296-330` | H 4.1 |
| P2 | Dispatch timer in place of NSTimer, so an open menu does not pause a tick | New. LH ticks from an NSTimer on main, `main.m:862` | H 4.1 |
| P3 | Job with a deadline. A subprocess past it gets `terminate`. An in-process job past it skips its next turn | LH `Where.m:20-22`, WF `Trees.m:406` | H 4.2 |
| P4 | Isolated worker for disk walks, as an XPC service or a child of the same binary | New. B measured an ad-hoc XPC service on this Mac | B, H 4.3 |
| P5 | Crash breadcrumb that names the expert and job that ran last | New | H 4.3 |

```objc
// Runtime/MCRuntime.h
dispatch_queue_t MCQueue(NSString *expert, NSString *job, dispatch_qos_class_t qos);
    // label no.guerrilla.minmacs.<expert>.<job>, DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM
dispatch_source_t MCTimer(dispatch_queue_t q, NSTimeInterval every, NSTimeInterval leeway, dispatch_block_t tick);

@interface MCJob : NSObject
+ (void)run:(NSString *)name expert:(NSString *)expert on:(dispatch_queue_t)q
     budget:(NSTimeInterval)budget work:(void (^)(MCJob *job))work;   // overruns are logged and skip the next turn
@property (readonly) BOOL pastDeadline;
@end

@protocol MCWorker <NSObject>                                   // XPC service or `minmacs _walk`, chosen at build time
- (void)sizeTrees:(NSArray<NSString *> *)roots reply:(void (^)(NSDictionary *sizes, NSError *e))reply;
@end
id<MCWorker> MCSharedWorker(void);

void MCBreadcrumbEnter(NSString *expert, NSString *job);         // Store/running, cleared on exit
NSString *MCBreadcrumbLeftOver(void);                             // read once at launch
```

### 1.2 Senses: processes, sockets, power and folders

| # | Pattern | Start from | Source |
|---|---|---|---|
| P6 | One process pass per 5 s | LH `-[LHScanner sample]`, `Ports.m:439`, with one `KERN_PROC_ALL` sysctl for every pid | A1, B1 |
| P7 | Process facts and identity `pid:start` | LH `Ports.m:71-102`, plus `KInfo` in `Where.m:28` | A2 |
| P8 | Process tree and roll-ups, built once per sample | LH `Ports.m:536`, caps of 500 pids and 20 hops | A3 |
| P9 | Responsible app and owning app | LH `Responsible`, `Ports.m:63`, and `AppOf`, `Where.m:62` | A4 |
| P10 | Socket table for every own pid | LH `ScanSockets`, `Ports.m:326` | A5, B |
| P11 | Process exits pushed by kqueue `NOTE_EXIT` | New | B2 |
| P12 | App launch, quit, sleep and wake from `NSWorkspace` | New. MM reads `runningApplications` but observes nothing | B2 |
| P13 | System signals pushed: memory pressure, thermal, power source, lid | LH `main.m:856`, IN `main.m:259-291` | A6, B |
| P14 | Lid override and assertions read from IOKit, never `pmset` | New. IN runs `pmset -g` on main, `main.m:681` | B5 |
| P15 | Folder watch with FSEvents and a saved event id | New | B3, D9 |
| P16 | Clone-aware sizer in three tiers | NN `internal/sizer`, with `getattrlistbulk` as the periodic tier | A3, B4, D2 |

```objc
// Core/Senses/MCSenses.h
@interface MCProc : NSObject
@property (readonly) pid_t pid, ppid; @property (readonly) uid_t uid; @property (readonly) uint64_t startSec;
@property (readonly, copy) NSString *name;
@property (readonly) double cpuPercent, energyRank;              // energy is a rank, never joules on screen
@property (readonly) uint64_t footprint;
@end

@interface MCSample : NSObject                                     // immutable, one per pass
@property (readonly) NSDate *at; @property (readonly) NSDictionary<NSNumber *, MCProc *> *procs;
- (NSArray<NSString *> *)argsOf:(pid_t)pid;                        // lazy, memoized for this sample, never nil
- (NSString *)cwdOf:(pid_t)pid;
- (NSArray<NSNumber *> *)treeOf:(pid_t)pid limit:(NSUInteger)max;
- (NSArray<NSNumber *> *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops;
- (NSData *)sockets;                                               // packed MCSocket values, LISTEN and ESTABLISHED
@end

typedef struct { pid_t pid; uint64_t startSec; } MCProcKey;
BOOL MCProcAlive(MCProcKey k);
pid_t MCResponsiblePid(pid_t pid);                                 // the pid itself when unknown
NSRunningApplication *MCOwningApp(MCSample *s, pid_t pid);

@interface MCPower : NSObject
@property (readonly) BOOL onAC, lidClosed, lidOverride, lowPowerMode;   // lidOverride: IOPMrootDomain SleepDisabled
@property (readonly) int batteryPercent;                                // -1 without a battery
@property (readonly) NSProcessInfoThermalState thermal;
@property (readonly) NSInteger memoryPressure;                          // normal, warn, critical
@property (readonly) NSDictionary<NSNumber *, NSArray *> *assertionsByPid;   // IOPMCopyAssertionsByProcess
@end

typedef NS_OPTIONS(NSUInteger, MCSignal) { MCSignalMemory = 1, MCSignalDisk = 2, MCSignalThermal = 4,
    MCSignalPower = 8, MCSignalLid = 16, MCSignalExit = 32, MCSignalApp = 64, MCSignalSleep = 128 };

@interface MCSenses : NSObject
+ (instancetype)shared;
- (MCSample *)latest;                                              // never blocks
- (MCPower *)power;
- (id)observe:(MCSignal)mask block:(void (^)(MCSignal changed, id detail))block;   // detail: exited pid, app
@end

// Core/Senses/MCFolders.h
@interface MCFolderWatch : NSObject
+ (instancetype)watch:(NSArray<NSString *> *)roots name:(NSString *)name
              skip:(NSArray<NSString *> *)names changed:(void (^)(NSSet<NSString *> *dirs, BOOL rescan))changed;
    // replays from Store/<name>.eventid, never from 0; skip filters node_modules and .git/objects in the callback
@end

typedef struct { uint64_t allocated, freedIfDeleted; NSInteger files, errors; } MCSize;
@interface MCSizer : NSObject
+ (MCSize)quick:(NSString *)root;                                  // getattrlistbulk, ATTR_CMNEXT_PRIVATESIZE, clone ids
+ (uint64_t)exact:(NSArray<NSString *> *)roots;                    // NN extent union, F_LOG2PHYS_EXT, before an action
+ (int64_t)freedOnVolume:(NSString *)path by:(BOOL (^)(void))action;   // statfs before and after, for the undo record
@end
```

### 1.3 Know: agents, sessions, git and clutter

| # | Pattern | Start from | Source |
|---|---|---|---|
| P17 | Agent registry as data | MM `MMAgents`, `Agents.m:38`, 63 rows | A2, A7 |
| P18 | Agent working signal, ranked: status file, then `caffeinate` child, then tree CPU | New ranking. MM `Agents.m:253-279` has no status file | E1, B6 |
| P19 | Session index, one pass for every folder | WF `Sessions`, `Trees.m:545`, refreshed by FSEvents | A2, A8 |
| P20 | Claude Code live state from `~/.claude/sessions/<pid>.json` | New | E1 |
| P21 | Codex state from `state_5.sqlite` and `thread_history_1.sqlite`, read-only | New | E3 |
| P22 | One agent event reader: `cmux events` with a cursor file, plus the hook spool | New. MM reads a 2 MB tail of `workstream.jsonl`, `Hosts.m:142-238` | E2, E 8 |
| P23 | Child process with a time limit | WF `WFGitInput`, `Common.m:78` | A9 |
| P24 | Git runner with `LC_ALL=C` and no locks | WF `Common.m:71-105` | A10 |
| P25 | Repo and worktree discovery, plus "which repo holds this path" with no spawn | WF `Walk`, `Trees.m:57`, and LH `ReadGit`, `Ports.m:265` | A11, E7 |
| P26 | Git facts and merge kinds, plus remote containment and `merge-tree` | WF `Trees.m:134-290`, NN `worktrees.go:192` | A12, C4 |
| P27 | Fact cache keyed by a fingerprint, non-blocking read | WF facts.json keyed by HEAD, with LH's stale-now, fresh-later read | A14 |
| P28 | Clutter registry as data, one JSON row per kind | NN knowledge, seeded from track D's 52 rows | D1, C6 |
| P29 | Owner back-links read from tool files | New. DerivedData `info.plist`, Playwright `.links`, pnpm `.modules.yaml` | D8 |
| P30 | Cache paths from env vars and config files, never by running the tool | New | D5 |

```objc
// Core/Know/MCAgents.h
typedef NS_ENUM(NSInteger, MCAgentState) { MCAgentUnknown, MCAgentWorking, MCAgentWaiting, MCAgentIdle };
@interface MCAgent : NSObject
@property (readonly, copy) NSString *harnessID, *sessionID, *cwd, *why;    // why: "status file busy", "caffeinate child"
@property (readonly) MCAgentState state; @property (readonly) pid_t pid;
@end
@interface MCRegistry : NSObject
+ (instancetype)shared;                                             // bundled rows, then the user's rows
- (NSArray<MCAgent *> *)agentsIn:(MCSample *)s power:(MCPower *)p;  // ranks the signals in P18
- (MCAgent *)agentAbove:(pid_t)pid in:(MCSample *)s;
@end

@interface MCSession : NSObject
@property (readonly, copy) NSString *agent, *sessionID, *title, *cwd, *branch, *transcript;
@property (readonly) NSDate *started, *lastActive;
@end
@interface MCSessions : NSObject
+ (instancetype)shared;          // ~/.claude/sessions, ~/.claude/projects, ~/.codex state, ~/.pi/agent/sessions
- (MCSession *)latestIn:(NSString *)folder;
- (MCSession *)openAt:(NSDate *)t inFolders:(NSArray<NSString *> *)folders;
- (MCSession *)forPid:(pid_t)pid;
@end

@interface MCAgentEvents : NSObject                                 // cmux events and Store/events/*.jsonl
+ (instancetype)shared;
- (id)observe:(void (^)(NSString *agent, NSString *event, NSString *sessionID, NSString *cwd, pid_t ppid))block;
@end

// Core/Know/MCGit.h
typedef struct { int status; BOOL timedOut; } MCRunResult;
MCRunResult MCRun(NSString *path, NSArray<NSString *> *args, NSData *input, NSDictionary *env,
                  NSString *cwd, NSTimeInterval timeout, NSData **outData, NSData **errData);   // never on main
NSString *MCGit(NSString *dir, NSArray<NSString *> *args, NSTimeInterval timeout, int *status);

@interface MCWorktree : NSObject
@property (readonly, copy) NSString *path, *repo, *branch, *owner;     // owner: claude-code, cursor, conductor, nil
@property (readonly) BOOL locked;                                      // git worktree lock
@end
@interface MCGitFacts : NSObject
@property (readonly, copy) NSString *head, *defaultBranch, *merged;   // ancestor | tree | patch | squash | pr | mergetree | nil
@property (readonly) NSInteger dirty, untracked, stashes, unpushed, notInDefault;
@property (readonly) BOOL onRemote;
@end
@interface MCRepoIndex : NSObject
+ (instancetype)shared;
- (NSArray<MCWorktree *> *)worktrees;
- (MCWorktree *)worktreeAt:(NSString *)path;                        // ReadGit, no spawn
- (MCGitFacts *)factsFor:(MCWorktree *)w;                           // through MCFactCache, keyed by HEAD
@end

@interface MCFactCache<V> : NSObject
- (instancetype)initWithName:(NSString *)name maxAge:(NSTimeInterval)age persist:(BOOL)persist;
- (V)valueFor:(NSString *)key fingerprint:(NSString *)fp orCompute:(V (^)(void))work wait:(BOOL)wait;
- (void)forget:(NSSet<NSString *> *)liveKeys;
@end

// Core/Know/MCClutter.h
typedef NS_ENUM(NSInteger, MCClutterClass) { MCClutterCache, MCClutterTool, MCClutterBuild, MCClutterData, MCClutterLeak };
@interface MCClutterKind : NSObject                                 // one row of registry/clutter/*.json
@property (readonly, copy) NSString *kindID, *cleanup, *dryRun; @property (readonly) MCClutterClass klass;
@property (readonly) NSArray<NSString *> *paths, *never;
@end
@interface MCClutterItem : NSObject
@property (readonly) MCClutterKind *kind; @property (readonly, copy) NSString *path, *ownerPath;
@property (readonly) MCSize size; @property (readonly) BOOL ownerGone;
@end
```

### 1.4 Graph: one snapshot for five lenses

| # | Pattern | Start from | Source |
|---|---|---|---|
| P31 | Immutable snapshot with a generation number, built on one queue, published to main | New. WF shares `@synchronized (self)` between scan workers and main, `Trees.m:634-636` | H2 |
| P32 | Workstream: one session, its worktree, servers, processes, caches and keep-awake need | New | PLAN 3, F5 |
| P33 | Reads that replace calls between apps | New. Replaces WF `LocoHosts`, `Trees.m:396`, and IN `MinMacsWorking`, `main.m:165` | A39 |

```objc
// Core/Graph/MCGraph.h
@interface MCWorkstream : NSObject
@property (readonly) MCSession *session; @property (readonly) MCWorktree *worktree; @property (readonly) MCGitFacts *git;
@property (readonly) NSArray *servers, *processes; @property (readonly) NSArray<MCClutterItem *> *clutter;
@property (readonly) MCAgentState agent;
- (NSString *)fingerprint;                                          // HEAD, activity bucket, size bucket
@end
@interface MCSnapshot : NSObject
@property (readonly) uint64_t generation; @property (readonly) NSDate *builtAt;
@property (readonly) NSArray<MCWorkstream *> *workstreams;
- (MCWorkstream *)workstreamAt:(NSString *)path;
- (NSInteger)workingAgents;
@end
@interface MCGraph : NSObject
+ (instancetype)shared;
@property (readonly) MCSnapshot *current;                           // main thread only
@property (readonly, atomic) MCSnapshot *latest;                    // any queue
- (void)holdAwake:(NSString *)reason pid:(pid_t)pid;                 // replaces insomnia://on
@end
```

### 1.5 Store: one folder, one prefs domain, safe writes

| # | Pattern | Start from | Source |
|---|---|---|---|
| P34 | Support folder with a test override | LH `LHSupportDir`, `Ports.m:32` | A4, A15 |
| P35 | Prefs on one CFPreferences domain | LH, WF and MM helpers, domain `no.guerrilla.minmacs` | A16 |
| P36 | Rules file, synchronized, additive defaults, wildcard match, no removal bug | WF `WFRules`, with MM's wildcards | A17 |
| P37 | State file with lock, read, change and atomic write | LH `SaveActivity`, `Ports.m:376` | A18 |
| P38 | Append-only log for undo, review history and trends | NN audit JSONL, `audit.go:44` | C2, F8 |

```objc
// Core/Store/MCStore.h
NSString *MCSupportDir(void);                                       // ~/Library/Application Support/MinMacs or $MINMACS_HOME
NSString *MCExpertDir(NSString *expert);
id MCPref(NSString *key); void MCSetPref(NSString *key, id value);  // keys like "locohost.mode"
BOOL MCPrefBool(NSString *key, BOOL dflt);

@interface MCRules : NSObject
+ (instancetype)rulesFor:(NSString *)expert defaults:(NSDictionary *)defaults;
- (BOOL)list:(NSString *)group key:(NSString *)key matches:(NSString *)value;     // exact, prefix*, *contains*
- (void)set:(BOOL)on value:(id)value inList:(NSString *)group key:(NSString *)key; // this exact entry only
@end

@interface MCStateFile : NSObject
+ (instancetype)fileNamed:(NSString *)name expert:(NSString *)expert;
- (id)read;
- (void)update:(id (^)(id disk))change;                             // flock, read, change, write atomically
@end

@interface MCLog : NSObject                                         // JSONL, one line per record
+ (instancetype)logNamed:(NSString *)name;
- (void)append:(NSDictionary *)record;
- (NSArray<NSDictionary *> *)tail:(NSUInteger)n;
@end
```

### 1.6 Review: one broker

| # | Pattern | Start from | Source |
|---|---|---|---|
| P39 | Model call on the user's login, temp files per call | WF `Review.m:146-351` | A19 |
| P40 | Usage split per call: input, cache write by TTL, cache read, output, thinking, cost | New. Both apps add cache reads at full weight, WF `Review.m:220-223` | F7 |
| P41 | One review record with an expert field and keep, go or unsure | LH and WF `Review.h` | A20 |
| P42 | Redaction and clipping, nil-safe | WF `WFRedact`, `Common.m:29` | A21 |
| P43 | Batches in parallel | WF `Batches`, `Review.m:410`, 25 per call, 3 at a time | A22 |
| P44 | Judge, where a failed judge keeps | WF judge through `Batches`, NN's keep-on-failure rule | A23 |
| P45 | Summary: numbers from code, words from the model | WF `Review.m:457` | A24 |
| P46 | Wake queue with a minimum gap and age marks | LH and WF `-watchEvents` | A25 |
| P47 | Rules first, each rule counted | New | F2 |

```objc
// Core/Review/MCReview.h
@interface MCUsage : NSObject
@property (readonly) NSInteger input, cacheWrite5m, cacheWrite1h, cacheRead, output, thinking;
@property (readonly) double costUSD, seconds;
@end
@interface MCAnswer : NSObject
@property (readonly) NSDictionary *json; @property (readonly, copy) NSString *model, *error;
@property (readonly) MCUsage *usage;
@end
@interface MCModel : NSObject
+ (MCAnswer *)ask:(NSString *)model system:(NSString *)system schema:(NSDictionary *)schema
            input:(NSDictionary *)input effort:(NSString *)effort;   // compact JSON, sorted keys, nulls dropped
@end

typedef NS_ENUM(NSInteger, MCVerdictKind) { MCVerdictKeep, MCVerdictGo, MCVerdictUnsure };
@interface MCVerdict : NSObject
@property MCVerdictKind kind; @property double confidence; @property BOOL judged;
@property (copy) NSString *about, *reason, *keepEvidence, *decidedBy;   // decidedBy: a rule id or "model"
@end
@interface MCReview : NSObject
@property (copy) NSString *expert, *trigger, *summary; @property NSDate *at;
@property NSDictionary<NSString *, MCVerdict *> *verdicts; @property NSArray<MCUsage *> *calls;
- (void)save;                                                      // also appends to the review history log
@end

NSString *MCRedact(NSString *s); NSString *MCClip(NSString *s, NSUInteger max);

@protocol MCRule <NSObject>
@property (readonly) NSString *ruleID;
- (MCVerdict *)decide:(MCWorkstream *)w;                            // nil when the rule cannot tell
@end
@interface MCReviewBroker : NSObject
+ (instancetype)shared;
- (void)registerRules:(NSArray<id<MCRule>> *)rules expert:(NSString *)expert;
- (void)wake:(NSString *)reason expert:(NSString *)expert;          // coalesced, at least minGap apart
@property NSTimeInterval minGap;                                    // 10 minutes
- (BOOL)run:(NSArray *)subjects batch:(NSUInteger)size parallel:(NSUInteger)n schema:(NSDictionary *)schema
       into:(MCReview *)r;                                          // skips subjects whose fingerprint did not move
- (void)judge:(NSArray *)subjects review:(MCReview *)r goWord:(NSString *)go;
@end
extern const double MCMinConfidence, MCSureConfidence;              // 0.6 and 0.8, as LH and WF use today
```

### 1.7 Act: modes, plans, keeps, actions and undo

| # | Pattern | Start from | Source |
|---|---|---|---|
| P48 | Modes Idle, Proactive and Eager, with a day of watching | WF `Forest.m:22-56` | A8, A26 |
| P49 | Work keeps on fresh facts, review keeps from the review | WF `WFWorkKeeps` and `WFPlan` | A10, A27 |
| P50 | Timed keep by a stable key, and protect lists | WF `WFKeptUntil`, keyed by path | A28 |
| P51 | Stop and quit, checked fresh, force as a second step | LH `StopHostsBy`, `main.m:301`, MM `QuitApps`, `main.m:141` | A29, C3 |
| P52 | Undo record written before acting, Trash, git bundle, restore | WF `WFRemove` and `WFRestore`, NN record-first and `Grave` | A9, A30 |
| P53 | Removal through the tool's own command for tool rows | New | D3 |
| P54 | Keep-awake assertion tied to a working agent | IN `main.m:542-545`, plus `caffeinate -w` style end on pid exit | B6, C8 |
| P55 | Notification after an unasked action, with Undo | LH and WF `-notify:mode:`, plus `UNNotificationAction` | A31, B11, G8 |

```objc
// Core/Act/MCAct.h
typedef NS_ENUM(NSInteger, MCMode) { MCModeIdle, MCModeProactive, MCModeEager };
MCMode MCModeFor(NSString *expert);                                 // Proactive by default
BOOL MCWatchedLongEnough(NSString *expert);                         // a day after first launch

@protocol MCSubject <NSObject> @property (readonly) NSString *key, *stableKey, *expert; @end
@protocol MCExpertPolicy <NSObject>
- (NSString *)workKeeps:(id<MCSubject>)s;                           // fresh facts; nil when free; "cannot verify" keeps
- (NSString *)reviewKeeps:(id<MCSubject>)s review:(MCReview *)r;
@end
@interface MCPlanEntry : NSObject
@property (readonly) id<MCSubject> subject; @property (readonly) BOOL act; @property (readonly, copy) NSString *why;
@end
NSArray<MCPlanEntry *> *MCPlan(NSArray<id<MCSubject>> *subjects, MCReview *r, MCMode m, id<MCExpertPolicy> p);

@interface MCKeep : NSObject
+ (NSDate *)keptUntil:(NSString *)stableKey expert:(NSString *)expert;
+ (void)keep:(NSString *)stableKey expert:(NSString *)expert until:(NSDate *)until;
@end

@protocol MCAction <NSObject>
- (NSString *)recheck;                                              // nil to go ahead
- (BOOL)perform:(MCUndoRecord *)record error:(NSString **)error;
@end
NSArray<NSNumber *> *MCTerminate(NSArray<NSNumber *> *pids, MCProcKey owner, NSTimeInterval grace, BOOL force);

@interface MCUndoRecord : NSObject
@property (readonly, copy) NSString *rid, *expert, *kind, *subject, *why, *state;   // pending | done | failed | restored
@property (readonly) NSDictionary *payload;                          // restart command, git bundle, trashed URLs, dry-run text
@property (readonly) int64_t freedBytes;
@end
@interface MCUndo : NSObject
+ (instancetype)shared;
- (MCUndoRecord *)begin:(NSString *)expert kind:(NSString *)kind subject:(NSString *)s why:(NSString *)why payload:(NSDictionary *)p;
- (void)finish:(MCUndoRecord *)r ok:(BOOL)ok freed:(int64_t)bytes;
- (NSURL *)trash:(NSURL *)item record:(MCUndoRecord *)r error:(NSError **)e;   // never empties the Trash
- (NSString *)restore:(NSString *)rid;
@end

@interface MCAwake : NSObject
+ (void)holdFor:(pid_t)agentPid reason:(NSString *)why;              // released on NOTE_EXIT of that pid
+ (void)releaseAll;
@end

void MCNotify(NSString *expert, NSString *title, NSString *body, NSString *undoRid);   // asks permission on first use
```

### 1.8 UI: status items, menu kit and cards

| # | Pattern | Start from | Source |
|---|---|---|---|
| P56 | App shell: one delegate, up to five status items, login item, reopen | LH and WF `main()` and `-toggleLogin` | A32, G1, G3 |
| P57 | Menu kit with one width | WF `main.m:476-590` | A33 |
| P58 | Hover card with one label column and links to other experts | WF `-cardFor:`, `main.m:633` | A34 |
| P59 | Render tool for every expert, light, dark and Increase Contrast | WF `tools/render.m` and `render.sh` | A35, G10 |
| P60 | Words and numbers: bytes, durations, plurals, tail cuts | WF duration, LH plural | A36 |

```objc
// UI/MCUI.h
@protocol MCExpert <NSObject>
@property (readonly) NSString *name, *symbol;                       // "LocoHost", "server.rack"
- (NSString *)badge;                                                // at most 3 characters, nil when nothing asks to act
- (NSString *)accessibilityState;                                   // "2 idle servers"
- (void)buildMenu:(NSMenu *)menu kit:(MCMenuKit *)kit snapshot:(MCSnapshot *)s;
@end
@interface MCApp : NSObject <NSApplicationDelegate>
- (void)registerExpert:(id<MCExpert>)e;    // autosaveName minmacs.<expert>, NSStatusItemBehaviorRemovalAllowed
@property BOOL oneIcon;
@end

@interface MCMenuKit : NSObject
@property (readonly) CGFloat width, labelColumn;                    // one value for every expert
- (NSMenuItem *)header:(NSString *)big unit:(NSString *)unit line:(NSString *)line;
- (NSMenuItem *)text:(NSString *)text lines:(NSInteger)n;            // a view, never a disabled item
- (void)section:(NSString *)title in:(NSMenu *)m;
- (NSMenuItem *)row:(NSString *)name facts:(NSArray<NSString *> *)facts mark:(NSString *)stateShape;
- (NSMenuItem *)action:(NSString *)title tail:(NSString *)gray alternate:(NSString *)optionTitle;
@end
@interface MCCard : NSObject
@property (copy) NSString *title, *statusWord, *statusText, *note; @property (strong) NSColor *statusColor;
- (void)fact:(NSString *)label value:(NSString *)value;             // empty values left out, at most five
- (void)link:(NSString *)label expert:(NSString *)expert key:(NSString *)key;
- (NSMenuItem *)menuItem:(MCMenuKit *)kit;
@end
void MCRenderMenu(NSMenu *menu, NSString *path, NSAppearance *appearance, BOOL increaseContrast);

NSString *MCBytes(uint64_t b); NSString *MCDuration(NSTimeInterval s);
NSString *MCPlural(NSInteger n, NSString *word); NSString *MCCut(NSString *s, NSUInteger n);
```

### 1.9 CLI, socket, hooks and tooling

| # | Pattern | Start from | Source |
|---|---|---|---|
| P61 | Verb registry, `--json` and `--dry-run` on every verb, `argv[0]` picks the expert | NN `Register`, `cli.go:25` | A13, A37, C11 |
| P62 | URL router that owns login and quit | New. Today copied four times | A38 |
| P63 | Core socket for the CLI with a flock instance lock and a same-uid check | NN `internal/ipc/server.go:82-160` | H6 |
| P64 | Hook ingest: `minmacs hook <agent>` appends one line and sends one datagram | New | E 8 |
| P65 | One build, test and release script set; CI runs tests and renders | LH and WF build.sh, NN CI | A40, A42 |
| P66 | Test isolation: env homes, fake model CLIs, fixture processes, a fake power source | LH and WF test.sh and tools | A41 |

```objc
// CLI/MCCLI.h
@interface MCArgs : NSObject
@property (readonly) NSString *verb, *arg1; @property (readonly) BOOL json, yes, dryRun, force;
- (NSString *)option:(NSString *)name;
@end
void MCRegisterCommand(NSString *expert, NSString *verb, NSString *usage, BOOL mutates, int (^cmd)(MCArgs *a));
int MCRunCLI(int argc, const char **argv);       // asks core.sock first, 200 ms; mutating verbs run in the app
void MCRegisterURLCommand(NSString *scheme, NSString *host, void (^run)(NSURL *url));
int MCHookIngest(NSString *agent);               // reads stdin, appends <= 512 bytes, one datagram, always exits 0

// Tests only, compiled with -DMC_TESTS
@protocol MCPowerSource <NSObject> - (MCPower *)read; @end
void MCUsePowerSource(id<MCPowerSource> src);
```

## 2. Changes to PLAN.md, section by section

Each row names a track recommendation, the change it asks for and the verdict. "Adopt" means take it as written. "Adopt, changed" means take it with the change in the reason. "Reject" means leave it out. "Owner" means section 5 asks for a decision.

### Header and introduction

No change. Every track supports the five experts in one app.

### Section 1, Principles

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| C1 | Principle 5 adds "cannot verify means keep" and "MinMacs never empties the Trash" | Adopt | Claude Code asks instead of removing when it cannot verify a worktree, and Mole skips what it cannot prove safe. The Trash is our undo, so emptying it breaks principle 5 |
| G2 | Principle 6 adds that opening MinMacs again shows a window, because the app cannot know whether its icons are visible | Adopt, changed | `isVisible` stays YES when the system hides an icon, and the System Settings toggle is not readable by the app, per forum 788101. The reopen window is the Settings window from section 7 with an overview first pane, so 2.0 adds no second window |

### Section 2, What each app brings

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| H8 | Leave behind: main-thread sampling in MinMacs and LocoHost, NSTimer ticks that pause while a menu is open, WorkForest's `@synchronized (self)` shared with main and its `locohost list --json` spawn | Adopt | Each is in the code at the cited lines in track H. The tick pause is an inference from Apple's run loop guide, and dispatch timers remove the doubt either way |
| A14, B5 | Insomnia: read the lid override from `IOPMrootDomain` `SleepDisabled` and keep `sudo -n pmset` only for the write, off main with a time limit. Replace `insomnia.debug.*` prefs with a test-only power source | Adopt | `pmset -g` costs 80 ms per read, and the IOKit read matches its value on this Mac. Debug prefs in a release build are already on the plan's leave-behind list |
| B, section "Assertion types" | Insomnia: keep both assertion types, and do not rely on `PreventSystemSleep` on battery | Adopt | `IOPMLib.h` calls it deprecated, yet powerd still counts it, and `man caffeinate` says `-s` works only on AC |
| E6 | MinMacs registry: split `socket_activity` into `net_bytes` and `local_status`, add a `session_status_file` signal, fix the README's count of verified rows from 1 to 2, add `/Applications/Codex.app` to the codex row | Adopt | No detector evaluates `socket_activity` today, `Agents.m:253-279`, and its 9 rows mean two different things |
| A, entry 12 | LocoHost leaves behind the `merged` key that `Intel.h:8` lists and `GitFacts` never sets | Adopt | WorkForest's merge detection replaces it through the graph |

### Section 3, The shared core

**Threads and graph.**

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| H1 | Add a Threads paragraph: AppKit on main only, one labeled serial queue per knower, dispatch timers, `DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM` | Adopt | WorkForest's scan peaked at 3.6 GB on global queues with no pool. Whether the pool is the cause is a guess, and phase 0 measures it |
| H2 | Write the snapshot rule: one builder, main the only writer of `current`, immutable snapshots with a generation number | Adopt | It removes the lock that WorkForest's main thread shares with six scan workers |

**Senses.**

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| A1, B1 | One pass: `KERN_PROC_ALL` for every pid, `RUSAGE_INFO_V6` for own pids, LocoHost's socket scan. Never `lsof`, `nettop`, `ps` or `pmset` in a tick | Adopt | 6.3 ms of CPU per pass, 5.4 ms at verification, against 40 to 70 ms for one `lsof` |
| B2 | kqueue `NOTE_EXIT` on every pid the graph holds, `NSWorkspace` notifications for apps. No Endpoint Security | Adopt | Registration costs 0.47 µs per pid and nothing while idle. Endpoint Security needs an entitlement from Apple |
| B3, D9 | FSEvents with a saved event id, filter `node_modules` and `.git/objects` in the callback, treat `MustScanSubDirs` as a rescan of that folder. Watch `~/Library/Caches`, `~/.npm`, the pnpm store, `/private/tmp`, `$TMPDIR` and the scan roots | Adopt | Passing 0 replayed 494,887 events in 93 s. Exclusion paths stop at 8, per `FSEvents.h` |
| E5 | Run `nettop` once per Senses pass for per-process bytes | Reject | `nettop` costs 20 to 40 ms wall per run, several times the whole pass, and B1 bans it from a tick. No row that needs `net_bytes`, such as `aider`, runs on this Mac. Sample bytes on demand when such an agent runs, and measure the cost then |
| B12 | Energy is a rank from `ri_energy_nj` deltas, never joules or watts | Adopt | Apple does not document the unit |

**Know.**

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| A2 | The registry is the only agent recognizer. LocoHost's 18 names become registry lookups. One session index for every expert | Adopt | Both apps read the same logs on their own timers today, with byte-identical helpers |
| E1 | `~/.claude/sessions/<pid>.json` is the first Claude Code source, ranked above `caffeinate` and far above tree CPU | Adopt | It matched `caffeinate` in 20 of 20 sessions. It is undocumented, so the `caffeinate` signal stays as the fallback |
| B6 | A `caffeinate` child of a registry agent counts as that agent working | Adopt | `IOPMCopyAssertionsByProcess` returns it in 124 µs, and Claude Code starts `caffeinate -i -t 300` while it works |
| E2 | One `cmux events --category agent --cursor-file … --reconnect` reader replaces the 2 MB tail of `workstream.jsonl`. Keep only the event name, session id, cwd, ppid and time | Adopt | cmux already injects hooks into 19 of 20 sessions. Phase 1 must test whether the stream needs a password outside a cmux terminal |
| E3 | Read Codex threads and turns from SQLite with `mode=ro` or `immutable=1`. Stop walking 30 days of rollout folders. Never write `notify` | Adopt | `state_5.sqlite` has `cwd` and `git_branch`. This links `libsqlite3`, which macOS ships, whatever decision 5 says about our own store |
| E7 | Add `<repo>/.claude/worktrees/*`, `~/.cursor/worktrees/*/*` and `~/conductor/workspaces/*/*` as worktree roots. Never install a `WorktreeCreate` hook | Adopt | 23 Claude Code worktrees and 2 Cursor worktrees exist on this Mac. A `WorktreeCreate` hook replaces Claude Code's own git step |
| C4 | Add worktrunk's simulated-merge check with `git merge-tree` | Adopt | `grep merge-tree` finds nothing in WorkForest. It catches merges the other five checks miss |
| C5 | Honor `git worktree lock` and Claude Code's ownership marker as "in use" | Adopt | Claude Code holds the lock while an agent runs. Whether MinMacs may act on worktrees other tools own is decision 6 |
| A12 | Add remote containment as its own git fact | Adopt | NN's comment says local-only merges have stranded work. Whether it overrides a squash merge is decision 7 |
| A3, B4, D2 | The Sizer has three tiers: `getattrlistbulk` with allocated and private size for every periodic walk, NN's extent union right before an action, and a statfs delta for the undo record. Count a clone id once when all its holders are in the set | Adopt, changed | Tracks A and D proposed st_blocks for the periodic tier. B measured `getattrlistbulk` at about the CPU of an fts walk, and it shows 2.8 MB freed for a tree du calls 1.5 GB, so st_blocks loses its reason to exist |
| D1, C6 | Ship the clutter catalog as `registry/clutter/*.json` with a schema, beside `registry/agents/`. Include protected paths and a list of apps to quit before their cache is cleared | Adopt | A rule list that users and verifiers can read avoids CleanMyMac's closed database |
| D5 | Never find a cache path by running the tool. Read env vars and config files | Adopt | `yarn cache dir` started Corepack and downloaded Yarn during research D |
| D6 | Port fixes: the simulator dyld cache sits at `/Library/Developer/CoreSimulator/Caches/dyld`, root-owned, so it is report-only. Skip `dist` and `build` when `git ls-files` shows them tracked | Adopt | LocoHost and WorkForest keep their app bundles in `build/` |
| D8 | Back-links in tool files are owner facts: DerivedData `WorkspacePath`, Playwright `.links`, pnpm `storeDir`, simulator `device.plist` | Adopt | Each is one file read. Three of six Playwright links point at missing installs on this Mac |

**Store.**

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| A4 | One support folder, one prefs domain, rules from WorkForest with MinMacs's wildcards and without the `setVerdict:` removal, merge-on-write for every state file | Adopt | Only LocoHost's activity.json merges today. SQLite against JSON is decision 5 |
| C2, F8 | One append-only log is the undo history, the restore list and the review history | Adopt | Each review.json keeps only the last review, so track F had to compute daily tokens from cadence |

**Review, Act and Notify.** The rows for section 4 sit under that section below.

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| A9 | Undo from WorkForest's records and restore. Write the record before acting. Take a git bundle when commits exist on no remote. Trash in place of NN's six `os.RemoveAll` calls | Adopt | It is principle 5 in code |
| A10 | Split work keeps from review keeps. Key timed keeps by a stable key | Adopt | LocoHost's `pid:start` key ends a keep when the server restarts. The server key is decision 8 |
| C3 | SIGTERM, then SIGKILL only on a second request. Check pid and start time before both | Adopt | LocoHost's 6-second grace and Force setting already do most of this. The Option alternate in G11 is the second request |
| D3 | Every "tool" row is cleaned through the tool's own command, run first in its dry-run form, with the dry-run output kept in the undo record | Adopt | uv says direct edits are "never safe", and Go's module cache is read-only on this Mac |
| B7, H3 | Heavy walks run out of process behind one `MCWorker` protocol | Adopt, changed | H called the XPC path unproven. B built an ad-hoc signed XPC service on this Mac: 13.9 ms cold start, 0.03 ms per call. Phase 0 runs B's test on the oldest supported macOS. If it passes, the worker is an XPC service. If not, it is H's `minmacs _walk` child |
| B11, G8 | One notifier in Act, after an unasked action, one per review, with an Undo action | Adopt | Phase 1 must first prove that an ad-hoc `MinMacs.app` gets notification permission. None of the three current apps appear in `com.apple.ncprefs` |

### Section 4, The review

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| F, section 1.6 | "Today" uses the measured numbers: 14,175 tokens for one LocoHost review of 5 hosts, 243,061 for one WorkForest review of 91 worktrees, about 3.26M a day on the schedule alone | Adopt | The plan's 18k an hour and 190k every two hours give 2.7M. Track F says the figures differ because WorkForest's worktree count changes |
| F7 | Record the full usage split per call and report cost next to tokens | Adopt | The apps count a cache read at full weight, and it costs a tenth of an input token on Haiku 5.5. Which number the target uses is decision 10 |
| A5, F1 | Build the fingerprint cache first, on the same fact-cache object that git facts and sizes use | Adopt | Under track F's model, sending only changed worktrees cuts 1,092 tree reviews a day to about 80, before rules |
| F2 | Write rules as data and log how many findings each decides | Adopt | Then the share rules decide becomes a measured number |
| A6 | Start the broker from WorkForest's Review.m. Fix LocoHost's fixed temp names. A failed judge keeps | Adopt | `diff` found one real difference between the two model calls, and WorkForest's version is the parallel-safe one |
| A7 | One wake queue with a 10-minute gap | Adopt | The plan says 10 minutes and WorkForest uses 30 today. Neither app logs event reviews, so phase 4 counts them |
| F3 | Pass `--effort low` to `claude -p` and measure the thinking cut against the fixture | Adopt | Thinking was 85 and 76 percent of output in two test calls. The cut is not measured, so the target must not rely on it until phase 4 does |
| F4 | `CLAUDE_CODE_PROMPT_CACHE_TTL=5m` when one expert's calls run more than an hour apart | Adopt | The one-hour TTL writes one-shot facts at 2 times input, against 1.25 times for five minutes, and both test calls reproduce those prices |
| F5 | Compact JSON, null, false and zero fields dropped, keys sorted with stable facts first | Adopt | The 30 percent saving is unverified, because the script was not saved. The change is cheap either way |
| F6 | The routine schema holds verdict, confidence, about, reason and keep_evidence. Prose fields are built from facts or asked for when a card opens | Adopt | Prose fields are 61 to 66 percent of answer text today |
| F9 | Investigate runs with a custom `--system-prompt` and only Read, Grep and Glob, scoped to the workstream | Adopt | A default Claude Code first turn reads 7k to 28k tokens from cache on this Mac |
| A, open question 3 | Batch size is measured at 1, 5 and 25 per call before the broker fixes one | Owner | This needs paid calls beyond the research budget. Decision 16 |
| Target line | "A fifth of today's tokens or less" | Adopt, changed | Track F's model, not a measurement, gives about 150k a day and about 680k on a bad day with 3 times the churn, no rules and no thinking cut. The bad day misses the target, so the fingerprint cache must work from day one |

### Section 5, Out of the box

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| A8 | Every mode defaults to Proactive, and every expert gets WorkForest's day of watching | Adopt | LocoHost and WorkForest both default to Eager today, and only WorkForest has the watching period |
| E4 | Ship with zero hooks. Offer hooks as an opt-in per agent, written as async command hooks that call `minmacs hook <agent>` | Adopt | The status file, cmux events, Codex SQLite and power assertions cover Claude Code and Codex with nothing installed. Coverage of Cursor, omp, Warp and Zed is unverified. Whether to ship a plugin is decision 11 |
| G3 | No permission prompt at launch. A first-day summary line in place of onboarding. Experts with an empty field start with the icon hidden | Adopt | Apple's Onboarding page says to ask for a permission when the function that needs it is first used. LocoHost and WorkForest ask at launch today |
| G3, Insomnia | Pick Insomnia's first-launch default | Owner | Insomnia's README says it starts on, and the plan says "while agents work". Decision 4 |
| C7, D4 | Noo-Noo's known caches in Proactive | Owner | C says the Trash. D says the Trash frees nothing until it is emptied, and proposes the tool's own command for cache and tool rows. Decision 1 |
| Model line | "The model is found: claude or codex login" | No change | No track tested login detection |

### Section 6, Sophistication

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| D7 | Rank clutter by owner state, merged worktree first, then by freed size. Wrap Up includes `.next` and `node_modules` of the worktree | Adopt | `node_modules` and `.next` in worktree folders total 34.24 GiB by du on this Mac, an upper bound because of clones |
| C8 | Insomnia ends on low battery, offers off on battery, and ties each assertion to the working agent's pid | Adopt | Amphetamine and Lungo have both guards. `caffeinate -w` shows the pid tie |
| E8 | A Claude Code `Stop` with non-empty `background_tasks` or `session_crons` counts as still working, and `StopFailure` counts as idle | Adopt | The hooks docs say these fields tell a finished session from a paused one. MinMacs reads them from cmux events, or from the opt-in hook |
| Trends line | "The pnpm store grew 9 GB this month" | Adopt, changed | The example is not a measurement. Replace it with a measured one in phase 3. Trend storage depends on decision 5 |

### Section 7, Menus and CLI

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| A11 | Extract the menu kit and card from WorkForest with one width and one label column | Adopt | The two apps differ by 10 points of width and 12 points of label column today |
| G1 | Each icon is square, a template symbol, named `minmacs.<expert>` with `autosaveName`, and removal is allowed | Adopt | `NSStatusItem.h:61` says an app with several status items should set an autosave name. None of our apps does |
| C10, G4 | "One Icon" in Settings gives one flat menu with a section per expert | Adopt | Nesting experts as submenus would put cards two levels deep, and the HIG asks for one level. The default is decision 3 |
| G5 | Footer items are "Hide Icon", "Settings…" and "Quit MinMacs". One Settings window replaces the nested Settings submenus | Adopt | Quit in one expert quits all five. LocoHost's Settings goes two levels down today |
| C9 | The first card action runs on a plain click of the row | Reject | In an NSMenu a row with a hover card is a submenu item, and a click opens the card. The card's first action is one more click. This is AppKit behavior and was not tested in research |
| A16 | One set of formatters for bytes, durations and plurals in Core | Adopt | Three identical byte formatters exist, and WorkForest alone has two plural rules |
| D10 | Data rows such as Cursor's `state.vscdb` and Claude Code transcripts stay with their owners, and the card names the owner's setting | Adopt | These are user state, not clutter. DESIGN.md edit 6 holds the wording rule |
| G11 | Rare power actions are Option alternates and do not count against the action limit | Adopt | `NSMenuItem.alternate` gives this with no new UI. Nothing may be reachable only through Option |
| A13 | A verb registry in place of three `RunCLI` if-chains, and one URL router | Adopt | The login and quit URL cases are copied four times |
| C11 | Every verb has `--json` and `--dry-run`. `minmacs hosts 3000` explains one port | Adopt | Mole, npkill and LeftOpen do this, and agents read JSON |
| H6 | The CLI talks to the app over `core.sock` in the support folder, with a flock lock and a same-uid check, and runs the core cold when no app answers. Mutating verbs go through the app | Adopt | A warm answer skips LocoHost's one-second double sample. The socket path is 63 bytes, inside the 104-byte limit |
| B10 | Shortcuts use "Run Shell Script" with the CLI and the URL schemes. No App Intents | Adopt | App Intents ships only as a Swift module |
| Cross-links | "A server's card opens WorkForest's card" | Adopt, changed | Opening a second status item's menu at a given row is untested. Phase 0 tests it. In one-icon mode the link stays inside one menu |

### Section 8, Migration

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| B9 | Check Noo-Noo's agent with `+[SMAppService statusForLegacyURL:]` before asking to remove it | Adopt | It reads the plist installed the old way without touching it |
| G8 | Carry each old app's hidden or visible icon state onto `minmacs.<expert>` | Adopt | A person who hid Insomnia should not see it come back |
| Prefs line | Domain names | Adopt, changed | The full domains are `no.guerrilla.locohost`, `no.guerrilla.workforest`, `no.guerrilla.minmacs` and Insomnia's bundle domain. Noo-Noo keeps `~/.config/noo-noo/config.toml` and `store.db`, per track A entry 15 |

### Section 9, Phases

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| A12 | Phase 0 ports WorkForest's `tools/render.m` into Core | Adopt | DESIGN.md names a LocoHost render step that LocoHost's repo does not hold |
| H7 | Phase 0 tests: XPC launch from an ad-hoc bundle on the oldest supported macOS, queue labels in `.ips` reports, and the autorelease pool against WorkForest's spike with `heap` on a fixture | Adopt | Each settles an architecture choice before code depends on it |
| G6 | Phase 0 applies the readable-text rule and state shapes when it extracts the kit | Adopt | The macOS floor is decision 2 |
| H4 | Phase 1 "Done when" uses numbers: idle footprint at or under 50 MB, idle CPU at or under 0.5 percent over 10 minutes, peak footprint in the app at or under 100 MB | Adopt, changed | MinMacs 1.2 is not installed and has no baseline. Track H's idle footprints of 30.3 MB and 50.2 MB are unverified, so phase 0 re-measures all running apps with saved output first |
| A15 | CI runs build.sh, test.sh against fixtures and the render tool, and keeps the PNGs | Adopt | No Objective-C app runs its test.sh in CI today |
| E9 | Phase 1 adds a fixture where a session with `status: idle` and 4 percent tree CPU must come out idle | Adopt | 1.2 counts any tree CPU at or above the floor as working, `Agents.m:262-264` |
| G7 | Phase 1 render check adds Increase Contrast, keyboard focus with Control-F8 and an accessibility label test. Measure all five icons in the bar on this Mac with an app's menus open | Adopt | The width claim in track G is a guess until measured |
| C13 | Publish the measured idle cost in the README | Adopt | Users of Stats show they care about a monitor's own cost |
| H5 | Phase 2 adds "a full scan peaks at or under 300 MB in the worker, and the app returns to idle" | Adopt | One scan today raised RSS to 2,166,432 KB |
| Phase 2 count | "WorkForest's 62 checks pass" | Adopt, changed | `grep -o 'check "'` finds 55 calls. Write "every check in WorkForest's test.sh passes" until a fixture run gives the count |
| Phase 4 test | "Tokens a day against 2.7M" | Adopt, changed | Use the measured 3.26M schedule figure as the base, and report cost next to tokens, per F7 |

### Section 10, Risks

| Rec | Change | Verdict | Reason |
|---|---|---|---|
| H3 | "One process for all" names the out-of-process worker and the crash breadcrumb | Adopt | Code inside the process cannot be stopped from outside, so long walks must run elsewhere |
| B8 | Lid mode keeps the sudoers rule until a notarized build exists | Adopt | `SMAppService.h` line 55 says apps that contain LaunchDaemons must be notarized |
| C12 | Privacy: ask for no Screen Recording or Accessibility rights, list every host the app contacts, send no telemetry | Adopt | Bartender's sale added an analytics framework to an app with Screen Recording rights. docs/REVIEW.md, which the plan names, does not exist in this repo yet, so phase 1 writes it |
| D, note | Asking a package manager for a path can install things | Adopt | Add it to the AGENTS.md test rules for 2.0 |

### Section 11, Open questions

Replace the four questions with the decisions in section 5 of this file. Questions 1 to 4 of the plan appear there as decisions 14, 13, 1 and 15.

## 3. Proposed update to DESIGN.md

These are edits to the current file, in its order. New text is quoted in full.

**Edit 1, section "The menu is native".** Replace the last sentence with this text.

> Text that should be read is never a disabled item, because macOS greys those out. Section titles use `+[NSMenuItem sectionHeaderWithTitle:]` where the macOS floor allows it, and the menu kit's text view otherwise. A sentence that explains a mode or a setting goes in a hover card or the Settings window.

Source: G5, `NSMenuItem.h:29-32`. LocoHost's `Header()` at `main.m:968` breaks the current rule.

**Edit 2, new section "The menu bar", after "The menu is native".**

> 1. Each expert's icon is a square template symbol at one point size, with no text. A number shows beside it only when it asks the person to act, and then at most three characters.
> 2. Each status item sets `autosaveName` to `minmacs.<expert>` and allows removal. Settings shows the same visible or hidden state.
> 3. Never rely on the icon. The system hides icons that do not fit and still reports them visible. Opening MinMacs again opens the Settings window on its overview pane, and the CLI and notifications carry the rest.
> 4. "One Icon" mode is flat. The MinMacs menu holds one section per visible expert, with its header line and top rows. Experts never nest as submenus, so a card is never two levels deep.
> 5. Each status item's accessibility label names the expert and its state, such as "LocoHost, 2 idle servers", never a symbol name.

Source: G1 to G4 and G6, `NSStatusItem.h:26, :61, :84-86`, the HIG menu bar page, the `isVisible` documentation.

**Edit 3, rule 3 under "Every line earns its place".** Replace the footer line and add two lines.

> - a footer of at most three items: Hide Icon, Settings… and Quit MinMacs. Recently Stopped and its peers move into the expert's More item.
>
> The two actions stay hidden when they cannot act. This breaks the HIG's advice to dim, on purpose, because dimmed text cannot be read. An Option alternate of an action does not count against the limit, and nothing is reachable only through Option.

Source: G9 and G11. Track G's open question 5 on dim against hide is decision 12. If the owner picks dim, this paragraph changes.

**Edit 4, rule 4.** Append this text.

> A row's state mark differs in shape as well as color. Every expert uses the kit's one width.

Source: G6, A11. LocoHost marks state by color alone at `main.m:974`.

**Edit 5, rule 5, the hover card.** Change the second bullet and add one bullet.

> - a colored status of at most two lines that starts with a word, such as "Stays" or "Goes at 18:00", and says in plain words why the item stays or when it goes, and what happens next
> - a fact that belongs to another expert links there, such as "Worktree   speed-3-base, merged", and counts as one of the five facts

Source: G6, PLAN.md section 7.

**Edit 6, section "Words".** Add four bullets.

> - Menu items use title-style capitalization and no articles. An item that opens more input ends in an ellipsis. Summaries, cards and notification bodies use sentence case.
> - A size is what deleting frees. When du says more, show du's figure only beside the freed figure, such as "2.8 MB freed, 1.5 GB on disk".
> - Energy is a rank, such as "uses the most energy". Never show joules or watts.
> - A protected or owned item says who owns it and where its setting lives, such as "Claude Code keeps transcripts for 30 days".

Source: G10, B4, B12, D10. The freed-against-du example is the `barkpark/node_modules` measurement in track B.

**Edit 7, new section "First launch", after "Words".**

> No window and no wizard. On the first day each expert's summary says what it watches and when it will first act, such as "Watching 6 servers. Acts on nothing until tomorrow." An expert asks for notification permission the first time it acts on its own, never at launch. An expert whose field is empty on this Mac starts with its icon hidden and shows it once, when the field appears.

Source: G7, the HIG Onboarding page. The example line is track G's.

**Edit 8, new section "Notifications", after "First launch".**

> A notification is sent only after an expert acted without being asked, one per review across all experts. The title is short, in title case, with no app name and no final period, such as "Stopped 2 Servers, Freed 1.2 GB". The body is full sentences in sentence case. It carries one Undo action and uses the passive interruption level unless the disk is nearly full. The body never sends the person somewhere in the menu. An error goes in an alert, not a notification.

Source: G8, the HIG Notifications and Managing notifications pages. LocoHost's body at `main.m:953-957` breaks two of these lines today.

**Edit 9, section "Checked, not assumed".** Replace the first sentence and add three checks.

> After any change to a menu, run `tools/render.m` from Core. It renders every expert's header, menu and hover cards from fixture subjects to PNG in light, dark and Increase Contrast. CI runs it and keeps the PNGs. Look at them and check that:
>
> - each status item's accessibility label is not a symbol name
> - the menu opens from the keyboard with Control-F8
> - a card's status starts with a word and its state mark has a shape

Source: A12, A15, G10. The current text describes a LocoHost harness that LocoHost's repo does not hold.

## 4. Cost and performance summary

Every number below was measured on this Mac by a track and kept by its verifier. This Mac is an Apple M1 Pro, 10 cores, 32 GB, macOS 27.0.1. A number the verifier marked unverified keeps that mark. Track F's daily targets are a model, not a measurement, so they are left out of this section.

### 4.1 Today's apps

| App | CPU in a 131 s window | CPU since launch | Footprint | Peak footprint |
|---|---|---|---|---|
| LocoHost | 0.79 percent of one core | 1.30 percent | 30.3 MB, unverified. 37.8 MB at rerun | 56.1 MB |
| WorkForest | 4.47 percent. 0.35 percent outside the scan | 3.83 percent | 50.2 MB, unverified. 2.6 GB at rerun | 3.6 GB |
| Insomnia | 0.29 percent | 0.073 percent over 22.2 days | 47.0 MB | 52.1 MB |

- One WorkForest scan used 5.41 s of CPU in about 16 s, with up to 23 threads. RSS went from 58,688 KB to 2,166,432 KB, and compressed memory from 106 MB to 1,358 MB. Source: track H section 2.
- The idle CPU of the three apps adds up to about 1.4 percent of one core. The idle footprint sum of 127.5 MB rests on the two unverified readings above.
- MinMacs 1.2 is not installed on this Mac, so it has no baseline.

### 4.2 What each fact costs

| Fact | API | Cost |
|---|---|---|
| Full Senses pass, about 860 pids | `proc_listpids`, `PROC_PIDTBSDINFO`, `RUSAGE_INFO_V6`, fd and socket info | 6.3 ms CPU per pass, 5.4 ms at rerun, 3 MB max resident. 0.13 percent of a core at a 5 s tick |
| Parts of that pass | pid list, bsdinfo, rusage for own pids, fd lists, socket info | 16 µs, 875 µs, 2,381 µs, 1,247 µs, 1,438 µs |
| Every process, root's included | `KERN_PROC_ALL` sysctl | 0.37 ms |
| Exit watch | kqueue `NOTE_EXIT` | 0.47 µs per pid to register, 864 pids in 0.4 ms, nothing while idle |
| Running apps | `runningApplications` | 8.7 µs for 97 apps |
| Thermal, memory pressure, VM stats | `thermalState`, `kern.memorystatus_vm_pressure_level`, `host_statistics64` | 0.2 µs, 1.4 µs, 0.8 µs |
| Lid, assertions, battery | `AppleClamshellState`, `IOPMCopyAssertionsByProcess`, `IOPMCopyAssertionsStatus`, `IOPSCopyPowerSourcesInfo` | 10.6 µs, 124 µs, 60 µs, 59 µs |
| The same through subprocesses | `pmset -g`, `pmset -g assertions`, `lsof -iTCP -sTCP:LISTEN`, `nettop -P -L 1` | 80 ms, 92 ms, 40 to 70 ms wall and 20 to 50 ms CPU, 20 to 40 ms wall |
| Clone-aware size, 78,247 files | `getattrlistbulk` with private size and flags | 1.6 to 2.2 s CPU, about 21 µs per file |
| Same tree, other ways | fts with lstat, `du -sk` | 1.72 to 2.06 s CPU, 2.26 s CPU |
| What the size shows | `barkpark/node_modules`, pnpm | 1,502.9 MB allocated, 2.8 MB private, 73,202 of 78,247 files share all blocks |
| Exact unique size | NN extent union | about 34 µs per file, from NN `sizer.go:28-35` |
| FSEvents replay from id 0 | `FSEventStreamCreate` with `sinceWhen` 0 | 494,887 events in 93.4 s and 2.4 s CPU. 501,272 in 99.6 s at rerun |
| FSEvents latency and live load | `NoDefer`, `FileEvents` | 11.3 and 13.3 ms, unverified. A rerun saw 17 events and 0.8 ms CPU in 20 s |
| XPC service, ad-hoc signed | `NSXPCConnection` | 13.9 ms cold start, 12.5 ms at rerun. 0.03 to 0.04 ms per call |
| A hook process | `/bin/sh -c "cat >/dev/null"` | about 12 ms per run, 200 runs in 2.44 s |
| Energy of a 1 s spin | `ri_energy_nj` | 1.37 J, 1.379 J at rerun, unit undocumented |

### 4.3 The review

| | LocoHost | WorkForest |
|---|---|---|
| Last review | 5 hosts, 14,175 tokens, $0.0047, 29.6 s | 91 worktrees, 243,061 tokens, $0.0693, 143.1 s |
| Tokens per item | 2,835 | 2,671 |
| Schedule | every 60 min | every 120 min |
| Tokens a day, schedule only | 340,200 | 2,916,732 |
| List cost a day, schedule only | about $0.11 | about $0.83 |

- Together that is 3,256,932 tokens a day before event reviews.
- Two test calls with WorkForest's flags: the fixed prefix is 1,470 tokens and is read from cache on the next call. Thinking was 788 of 925 output tokens and 1,277 of 1,689.
- The last WorkForest review gave 38 active, 20 stale and 33 unsure. 37 of 91 verdicts had confidence 0.8 or more.
- In WorkForest's facts.json, 66 of 114 entries are merged in some way, 30 had a commit in the last 24 hours and 28 were created in that time.

### 4.4 Disk on this Mac

| What | du size |
|---|---|
| Developer clutter in all | about 178 GiB, on a data volume using 334.9 GiB |
| `node_modules`, 447 folders | 53.78 GiB, an upper bound because pnpm clones |
| `.next`, 55 folders | 32.53 GiB |
| `node_modules` and `.next` inside worktree folders | 34.24 GiB |
| pnpm store | 19.14 GiB, of which `v11`, the layout projects use, is 5.48 GiB |
| Claude Desktop `vm_bundles` | 12.06 GiB |
| Chrome code-sign clones, 8 folders | 11.94 GiB, an upper bound |
| Cursor | 10.96 GiB, of which `state.vscdb` is 6.29 GiB |
| Kinds Proactive could take through each tool's command | 5.37 GiB over six measured items |
| `brew cleanup -n` | would free about 507.5 MB |

### 4.5 Agents

- 20 Claude Code status files matched the `caffeinate` signal in 20 of 20 sessions: 3 busy with `caffeinate`, 16 idle without, 1 `shell` without.
- 19 of 20 Claude Code sessions run with cmux's injected `--settings`.
- 1 of 63 registry rows runs on this Mac, and 6 more have local session data.

## 5. Decisions for the owner

Research could not settle these. Each one is phrased as a choice, with what the tracks found.

1. **Noo-Noo's removal method for known caches.** Trash every known cache in Proactive, as the plan proposes and track C supports, or clean cache and tool rows through each tool's own command and keep the Trash for build and leak rows, as track D proposes? Track D notes that the Trash frees nothing until emptied, and the tracks agree MinMacs never empties it. A tool command cannot be undone, so its undo is "the tool downloads it again".
2. **The macOS floor.** Stay at macOS 13, or raise it to 14 for `sectionHeaderWithTitle:`, menu badges, palette menus and `xpc_listener_create`? All four Objective-C apps set 13.0 today.
3. **One icon or five by default.** Ship five icons with "One Icon" as a choice, or one icon with five as a choice? The HIG says people decide, and nothing in the sources picks a default. This Mac has a notched display.
4. **Insomnia's first-launch default.** Keep the Mac awake from the first launch, as Insomnia does today, or only while an agent works, as the plan says?
5. **Our own store.** Link `libsqlite3` for undo, review history and disk trends, or keep JSON with merge-on-write? The Codex reader links `libsqlite3` either way.
6. **Worktrees other tools own.** May MinMacs act on worktrees that Claude Code, Cursor or Conductor created, or only show them and link to the owner's own command?
7. **Remote containment.** Does a worktree whose HEAD is on no remote always stay, as Noo-Noo rules, even when WorkForest finds it squash-merged into the local default branch?
8. **The keep key for a server.** Key a server's timed keep by project folder and port, or by project folder and script?
9. **Verdict words.** Do the experts keep their own words, such as `idle`, `stale` and `remove`, in prompts and in `--json` output, while Core stores keep, go and unsure? Scripts may read `locohost review --json` today.
10. **The review target's unit.** Measure the one-fifth target in tokens as the apps count them today, with cache reads at full weight, in tokens without cache reads, or in list cost? And is a bad day at about a quarter of today acceptable, as track F's model allows?
11. **Hooks.** Ship nothing, offer per-agent hooks written to the agent's settings file, or ship a Claude Code plugin with hooks?
12. **Dim or hide.** Keep the two action slots hidden when they cannot act, as DESIGN.md says, or dim them in place with a readable gray tail, as the HIG advises?
13. **An Apple Developer account.** Pay for one to notarize, which a bundled LaunchDaemon for lid mode requires and which may decide whether notifications work, or stay source-built with the sudoers rule?
14. **Noo-Noo's offload.** Port moving big folders to an external drive in phase 3, or later? No track studied it.
15. **The standalone apps.** Freeze them now, or keep fixing them until 2.0 ships? No track studied it.
16. **Paid calls for phase 4.** Approve a budget of paid model calls to measure `--effort low`, batch sizes of 1, 5 and 25, and Luna against Haiku 5.5 on the fixture? Track F's budget allowed two calls.
17. **The Core prefix.** Keep `MC` for Core symbols, or pick another before phase 0 writes the headers?
18. **Login item.** Register MinMacs as a login item on first launch, so the CLI almost always finds a warm app, or leave it to a Settings switch, as the HIG's "let people decide" suggests?

**Tests that settle the rest.** These need no decision, only approval to add them to phase 0 and phase 1:
- Does an ad-hoc signed `MinMacs.app` get notification permission on macOS 27?
- Does `SMAppService agentServiceWithPlistName:` register from an ad-hoc bundle?
- Does an embedded XPC service launch from an ad-hoc bundle on the oldest supported macOS?
- Does the System Settings menu bar toggle hide all five icons of one app at once?
- Can the core open a second status item's menu at a given row?
- Do `.ips` crash reports name the dispatch queue?
- Does the missing autorelease pool explain WorkForest's memory spike?
- Does `cmux events` need a password outside a cmux terminal?
- Is `~/.claude/sessions/<pid>.json` stable across Claude Code releases, and what does `shell` mean?
- Does Codex `thread_turns.status` show `inProgress` during a live turn?
- Are clone refcounts exact on a volume that reports clone mapping valid but not set?
- Do FSEvents for `~/Documents` reach an ad-hoc app without a privacy prompt?
- What does `/usr/libexec/tmp_cleaner` remove, and who creates the large `$TMPDIR` families?
- How much does removing one pnpm worktree's `node_modules` free, measured with the extent union?
