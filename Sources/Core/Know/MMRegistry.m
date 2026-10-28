// MMRegistry, patterns P17 and P18. Ported from MMAgents in MinMacs 1.2 Agents.m, branch legacy.
// Matching, presence, hosts, re-exec folding and the row signals follow Agents.m and tools/agents_probe.py.
// New in 2.0: the ranked signals of P18. The status file decides first, then agent events and Codex's SQLite,
// then the row's own signals in the order Agents.m reads them.
#import "Core/Know/MMRegistry.h"
#import "Core/Runtime/MMRuntime.h"
#import "Core/Store/MMStore.h"
#import "Core/Know/MMSessions.h"
#import <glob.h>
#import <sys/stat.h>
#import <mach-o/dyld.h>


@interface MMAgentRow ()
@property (readwrite, copy) NSString *harnessID, *name;
@property (readwrite) NSDictionary *json;
@end
@implementation MMAgentRow
@end

@interface MMAgent ()
@property (readwrite) MMAgentRow *row;
@property (readwrite, copy) NSString *harnessID, *sessionID, *cwd, *why, *surface;
@property (readwrite) MMProcKey key;
@property (readwrite) MMAgentState state;
@property (readwrite) MMAgentSignal signal;
@property (readwrite) double treeCPU;
@property (readwrite) uint64_t treeFootprint;
@property (readwrite) NSArray<MMAgent *> *hosted;
@property (strong) NSArray<NSNumber *> *treePids;
@end
@implementation MMAgent
@end

/// One process that matched a row, with what was read from it.
@interface MMAgentCand : NSObject
@property pid_t pid;
@property (strong) MMAgentRow *row;
@property (strong) NSDictionary *surface;
@property BOOL absent;
@property (strong) NSArray<NSNumber *> *tree;
@property (copy) NSString *sid;
@property (strong) NSArray<NSString *> *reasons;
@property MMAgentSignal topSignal;              // the most trusted row signal that fired
@property (strong) MMAgentCand *root;           // the host this one is folded into, or nil
@end
@implementation MMAgentCand
@end

static NSArray *Strings(id v) { return [v isKindOfClass:NSArray.class] ? v : @[]; }

/// Matching reads the command line only, as tools/agents_probe.py does. names is compared with the base name of
/// argv[0] and path_contains with argv[0] itself. 0 means no match. Otherwise a score, and the more specific row wins.
/// rowAbsent: the row's presence paths are all missing, so a match on a bare name does not count.
static NSInteger Matches(NSDictionary *surface, NSArray<NSString *> *argv, BOOL rowAbsent) {
    NSDictionary *spec = [surface[@"process"] isKindOfClass:NSDictionary.class] ? surface[@"process"] : nil;
    if (!spec.count || !argv.count) return 0;
    NSString *arg0 = argv.firstObject;
    BOOL named = [Strings(spec[@"names"]) containsObject:arg0.lastPathComponent];
    NSUInteger longest = 0; BOOL pathHit = NO;
    for (NSString *s in Strings(spec[@"path_contains"]))
        if ([s isKindOfClass:NSString.class] && [arg0 containsString:s]) { pathHit = YES; longest = MAX(longest, s.length); }
    if (!named && !pathHit) return 0;
    if (named && !pathHit && rowAbsent) return 0;
    for (NSString *x in Strings(spec[@"exclude_args"])) if ([argv containsObject:x]) return 0;
    NSArray *need = Strings(spec[@"args_contain"]);
    for (NSString *n in need) {
        BOOL found = NO;
        for (NSString *a in argv) if ([n isKindOfClass:NSString.class] && [a containsString:n]) { found = YES; break; }
        if (!found) return 0;
    }
    return 1 + (NSInteger)longest + (NSInteger)need.count;
}

static BOOL RowMatches(MMAgentRow *row, BOOL rowAbsent, NSArray<NSString *> *argv) {
    for (NSDictionary *s in Strings(row.json[@"surfaces"])) if ([s isKindOfClass:NSDictionary.class] && Matches(s, argv, rowAbsent)) return YES;
    return NO;
}

/// ~ in a row path names the agent's own home folder, which CLAUDE_CONFIG_DIR and CODEX_HOME move.
static NSString *AgentPath(NSString *path) {
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    NSDictionary *moved = @{ @"~/.claude/": env[@"CLAUDE_CONFIG_DIR"] ?: @"", @"~/.codex/": env[@"CODEX_HOME"] ?: @"" };
    for (NSString *prefix in moved) {
        NSString *to = moved[prefix];
        if (to.length && [path hasPrefix:prefix]) return [[to stringByAppendingString:@"/"] stringByAppendingString:[path substringFromIndex:prefix.length]];
    }
    return path;
}

static NSArray<NSString *> *Glob(NSString *pattern) {
    NSMutableArray *out = [NSMutableArray new];
    glob_t g; memset(&g, 0, sizeof g);
    if (glob(AgentPath(pattern).fileSystemRepresentation, GLOB_TILDE, NULL, &g) == 0)
        for (size_t i = 0; i < g.gl_pathc; i++) [out addObject:@(g.gl_pathv[i])];
    globfree(&g);
    return out;
}

static BOOL AnyPathExists(NSArray *paths) {
    for (NSString *p in paths) if ([p isKindOfClass:NSString.class] && Glob(p).count) return YES;
    return NO;
}

/// A child_process signal's args_contain. For -w the next argument must be the matched pid,
/// because `caffeinate -w <pid>` belongs to that process and nobody else.
static BOOL ChildArgsOK(NSArray *need, NSArray<NSString *> *childArgv, pid_t owner) {
    for (NSString *n in need) {
        NSUInteger at = childArgv.count > 1 ? [childArgv indexOfObject:n inRange:NSMakeRange(1, childArgv.count - 1)] : NSNotFound;
        if (at == NSNotFound) return NO;
        if ([n isEqualToString:@"-w"] && (at + 1 >= childArgv.count || ![childArgv[at + 1] isEqualToString:[NSString stringWithFormat:@"%d", owner]])) return NO;
    }
    return YES;
}

static NSString *SessionIDFromArgs(NSDictionary *surface, NSArray<NSString *> *argv) {
    for (NSString *flag in Strings(surface[@"session_id_args"])) {
        if (![flag isKindOfClass:NSString.class]) continue;
        NSString *eq = [flag stringByAppendingString:@"="];
        for (NSUInteger i = 0; i < argv.count; i++) {
            if ([argv[i] isEqualToString:flag] && i + 1 < argv.count) return argv[i + 1];
            if ([argv[i] hasPrefix:eq]) return [argv[i] substringFromIndex:eq.length];
        }
    }
    return nil;
}

static NSSet<NSString *> *Shells(void) {
    static NSSet *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [NSSet setWithArray:@[@"bash", @"zsh", @"sh", @"dash", @"fish", @"-bash", @"-zsh", @"-sh"]]; });
    return s;
}

/// Seconds since the newest file matching the row's per_session pattern was written, or -1.
static NSInteger TranscriptAge(NSDictionary *row, NSString *sid) {
    NSString *pattern = [row[@"session_store"] isKindOfClass:NSDictionary.class] ? row[@"session_store"][@"per_session"] : nil;
    if (!sid.length || ![pattern isKindOfClass:NSString.class] || [sid containsString:@"/"]) return -1;
    time_t newest = 0;
    for (NSString *f in Glob([pattern stringByReplacingOccurrencesOfString:@"{session_id}" withString:sid])) {
        struct stat st;
        if (stat(f.fileSystemRepresentation, &st) == 0 && st.st_mtime > newest) newest = st.st_mtime;
    }
    return newest ? (NSInteger)(time(NULL) - newest) : -1;
}

/// The state a hook event name stands for. The row's waiting_signals of kind hook add their event names.
static MMAgentState EventState(NSString *event, NSDictionary *row) {
    NSMutableSet *waiting = [NSMutableSet setWithArray:@[@"Notification", @"PermissionRequest"]];
    for (NSDictionary *w in Strings(row[@"waiting_signals"]))
        if ([w isKindOfClass:NSDictionary.class] && [w[@"signal"] isEqual:@"hook"] && [w[@"event"] isKindOfClass:NSString.class]) [waiting addObject:w[@"event"]];
    if ([waiting containsObject:event]) return MMAgentWaiting;
    if ([@[@"UserPromptSubmit", @"PreToolUse", @"PostToolUse", @"SubagentStart"] containsObject:event]) return MMAgentWorking;
    if ([@[@"Stop", @"StopFailure", @"SessionEnd", @"SessionStart"] containsObject:event]) return MMAgentIdle;
    return MMAgentUnknown;
}

static NSString *StateWord(MMAgentState s) {
    switch (s) {
        case MMAgentWorking: return @"working";
        case MMAgentWaiting: return @"waiting";
        case MMAgentIdle: return @"idle";
        default: return @"unknown";
    }
}

@implementation MMRegistry {
    NSMutableDictionary<NSNumber *, NSDate *> *_lastWorking;          // pid: last time a row signal fired
    NSMutableDictionary<NSNumber *, NSNumber *> *_lastSignal;         // pid: the signal that fired then
    NSMutableDictionary<NSNumber *, MMAgentEvent *> *_lastEvent;      // agent pid: its newest event
    id _eventToken;
    NSArray<NSNumber *> *_absent;        // under @synchronized (self): absentFlags and when it was read
    NSDate *_absentAt;
}

+ (instancetype)shared {
    static MMRegistry *r; static dispatch_once_t once;
    dispatch_once(&once, ^{ r = [[MMRegistry alloc] initWithRowDirectories:[self defaultRowDirectories]]; });
    return r;
}

+ (NSArray<NSString *> *)defaultRowDirectories {
    NSMutableArray *dirs = [NSMutableArray new];
    // The CLI runs through a symlink, where NSBundle may not resolve. Resources is found from the real executable.
    char buf[PATH_MAX]; uint32_t size = sizeof buf; char real[PATH_MAX];
    if (_NSGetExecutablePath(buf, &size) == 0 && realpath(buf, real)) {
        NSString *contents = [@(real).stringByDeletingLastPathComponent stringByDeletingLastPathComponent];
        [dirs addObject:[contents stringByAppendingPathComponent:@"Resources/registry/agents"]];
    }
    [dirs addObject:[MMSupportDir() stringByAppendingPathComponent:@"registry/agents"]];   // the user's rows win
    return dirs;
}

- (instancetype)initWithRowDirectories:(NSArray<NSString *> *)dirs {
    if ((self = [super init])) {
        _holdSeconds = 30;   // 1.2's measurement: 30 s misses 4% of in-turn gaps, 20 s misses 7%
        _lastWorking = [NSMutableDictionary new];
        _lastSignal = [NSMutableDictionary new];
        _lastEvent = [NSMutableDictionary new];
        NSMutableDictionary<NSString *, MMAgentRow *> *byID = [NSMutableDictionary new];
        for (NSString *dir in dirs) {
            for (NSString *f in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
                if (![f.pathExtension isEqualToString:@"json"]) continue;
                NSData *d = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:f]];
                NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
                if (![j isKindOfClass:NSDictionary.class] || ![j[@"id"] isKindOfClass:NSString.class]) continue;
                if (![j[@"surfaces"] isKindOfClass:NSArray.class] || ![j[@"working_signals"] isKindOfClass:NSArray.class]) continue;
                MMAgentRow *row = [MMAgentRow new];
                row.harnessID = j[@"id"];
                row.name = [j[@"name"] isKindOfClass:NSString.class] ? j[@"name"] : j[@"id"];
                row.json = j;
                byID[row.harnessID] = row;
            }
        }
        _rows = [byID.allValues sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"harnessID" ascending:YES]]];
        __weak MMRegistry *weak = self;
        _eventToken = [MMAgentEvents.shared observe:^(MMAgentEvent *e) { [weak noteEvent:e]; }];
    }
    return self;
}

- (void)dealloc { if (_eventToken) [MMAgentEvents.shared stopObserving:_eventToken]; }

- (void)noteEvent:(MMAgentEvent *)e {
    if (e.ppid <= 1) return;
    @synchronized (_lastEvent) {
        MMAgentEvent *old = _lastEvent[@(e.ppid)];
        if (!old || [e.at compare:old.at] != NSOrderedAscending) _lastEvent[@(e.ppid)] = e;
    }
}

#pragma mark Matching

/// Which rows' presence paths are all missing. Each path is a glob, so this is read at most every 30 seconds,
/// issue #52: a rebuild asks it once for the registry and once for each process above every server.
- (NSArray<NSNumber *> *)absentFlags {
    static const NSTimeInterval kAbsentEvery = 30;
    @synchronized (self) {
        if (_absent && -_absentAt.timeIntervalSinceNow < kAbsentEvery) return _absent;
    }
    NSMutableArray *a = [NSMutableArray new];
    for (MMAgentRow *r in _rows) { NSArray *pr = Strings(r.json[@"presence"]); [a addObject:@(pr.count && !AnyPathExists(pr))]; }
    NSArray *out = [a copy];
    @synchronized (self) { _absent = out; _absentAt = NSDate.date; }
    return out;
}

- (MMAgentCand *)bestFor:(NSArray<NSString *> *)argv absent:(NSArray<NSNumber *> *)absent {
    MMAgentCand *c = nil; NSInteger top = 0;
    for (NSUInteger i = 0; i < _rows.count; i++)
        for (NSDictionary *s in Strings(_rows[i].json[@"surfaces"])) {
            if (![s isKindOfClass:NSDictionary.class]) continue;
            NSInteger score = Matches(s, argv, [absent[i] boolValue]);
            if (score > top) { top = score; c = [MMAgentCand new]; c.row = _rows[i]; c.surface = s; c.absent = [absent[i] boolValue]; }
        }
    return c;
}

- (MMAgentRow *)rowMatching:(MMProc *)p sample:(MMSample *)s {
    return p ? [self bestFor:[s argsOf:p.pid] absent:[self absentFlags]].row : nil;
}

#pragma mark Detection

- (NSArray<MMAgent *> *)agentsIn:(MMSample *)s power:(MMPower *)power {
    NSDictionary<NSNumber *, MMProc *> *procs = s.procs;
    NSDate *now = NSDate.date;
    pid_t me = getpid();
    NSArray<NSNumber *> *absent = [self absentFlags];

    // 1. The most specific row and surface for every process.
    NSMutableDictionary<NSNumber *, MMAgentCand *> *best = [NSMutableDictionary new];
    for (MMProc *p in procs.objectEnumerator) {
        if (p.pid == me || p.pid <= 1) continue;
        MMAgentCand *c = [self bestFor:[s argsOf:p.pid] absent:absent];
        if (c) { c.pid = p.pid; best[@(p.pid)] = c; }
    }

    // 2. A harness that re-executes itself appears twice. The outermost process is the agent.
    NSMutableDictionary<NSNumber *, MMAgentCand *> *cands = [NSMutableDictionary new];
    for (MMAgentCand *c in best.allValues) {
        MMProc *p = procs[@(c.pid)];
        if (procs[@(p.ppid)] && RowMatches(c.row, c.absent, [s argsOf:p.ppid])) continue;
        cands[@(c.pid)] = c;
    }

    // 3. The row signals each one shows right now, most trusted first.
    for (MMAgentCand *c in cands.allValues) {
        c.tree = [s treeOf:c.pid limit:500];
        double cpu = [s treeCPU:c.pid];
        NSArray<NSNumber *> *kids = [s childrenOf:c.pid];
        c.sid = SessionIDFromArgs(c.surface, [s argsOf:c.pid]);
        NSMutableArray<NSString *> *reasons = [NSMutableArray new];
        __block MMAgentSignal top = MMAgentSignalNone;
        void (^fire)(MMAgentSignal, NSString *) = ^(MMAgentSignal sig, NSString *why) {
            [reasons addObject:why];
            if (top == MMAgentSignalNone || sig < top) top = sig;
        };
        for (NSDictionary *sig in Strings(c.row.json[@"working_signals"])) {
            if (![sig isKindOfClass:NSDictionary.class]) continue;
            NSString *kind = sig[@"signal"];
            if ([kind isEqualToString:@"child_process"]) {
                if (![sig[@"name"] isKindOfClass:NSString.class]) continue;
                NSArray *need = Strings(sig[@"args_contain"]);
                for (NSNumber *k in kids)
                    if ([procs[k].name isEqualToString:sig[@"name"]] && (!need.count || ChildArgsOK(need, [s argsOf:k.intValue], c.pid))) {
                        fire([sig[@"name"] isEqualToString:@"caffeinate"] ? MMAgentSignalCaffeinate : MMAgentSignalChild,
                             [NSString stringWithFormat:@"child %@", sig[@"name"]]);
                        break;
                    }
            } else if ([kind isEqualToString:@"tree_cpu"]) {
                double floor = sig[@"floor_percent"] ? [sig[@"floor_percent"] doubleValue] : 3;
                if (cpu >= floor) fire(MMAgentSignalTreeCPU, [NSString stringWithFormat:@"cpu %.0f%%", cpu]);
            } else if ([kind isEqualToString:@"transcript_write"]) {
                NSInteger within = sig[@"within_seconds"] ? [sig[@"within_seconds"] integerValue] : 30;
                NSInteger age = TranscriptAge(c.row.json, c.sid);
                if (age >= 0 && age <= within) fire(MMAgentSignalTranscript, [NSString stringWithFormat:@"transcript %lds ago", (long)age]);
            } else if ([kind isEqualToString:@"tool_children"]) {
                for (NSNumber *k in kids) if ([Shells() containsObject:procs[k].name ?: @""]) { fire(MMAgentSignalChild, @"tool shell running"); break; }
            } else if ([kind isEqualToString:@"power_assertion"]) {
                NSString *want = [sig[@"name"] isKindOfClass:NSString.class] ? [sig[@"name"] lowercaseString] : nil;
                BOOL hit = NO;
                for (NSNumber *pid in c.tree) {
                    if ([procs[pid].name isEqualToString:@"caffeinate"]) continue;   // that is the child_process signal
                    for (NSDictionary *a in power.assertionsByPid[pid]) {
                        NSString *n = [a isKindOfClass:NSDictionary.class] && [a[@"AssertName"] isKindOfClass:NSString.class] ? a[@"AssertName"] : @"";
                        if (!want || [n.lowercaseString containsString:want]) hit = YES;
                    }
                }
                if (hit) fire(MMAgentSignalAssertion, @"holds a sleep assertion");
            }
        }
        c.reasons = reasons;
        c.topSignal = top;
    }

    // 4. A process with a host of another row above it belongs to that host, which is reported once.
    for (MMAgentCand *c in cands.allValues) {
        MMAgentCand *cur = c;
        for (int hops = 0; hops < 64; hops++) {
            MMAgentCand *host = nil; pid_t a = procs[@(cur.pid)].ppid;
            for (int d = 0; d < 4096 && a > 1 && procs[@(a)]; d++, a = procs[@(a)].ppid) {
                MMAgentCand *m = best[@(a)];
                if (m && ![m.row.harnessID isEqual:cur.row.harnessID] && [m.surface[@"hosts_agents"] boolValue]) { host = m; break; }
            }
            if (!host) break;
            pid_t topPid = host.pid;
            for (int d = 0; d < 4096; d++) {
                pid_t up = procs[@(topPid)].ppid;
                if (!procs[@(up)] || !RowMatches(host.row, host.absent, [s argsOf:up])) break;
                topPid = up;
            }
            MMAgentCand *root = cands[@(topPid)];
            if (!root || ![root.row.harnessID isEqual:host.row.harnessID]) root = cands[@(host.pid)];
            if (!root) break;
            cur = root;
        }
        if (cur != c) c.root = cur;
    }
    NSMutableDictionary<NSNumber *, NSMutableArray<MMAgentCand *> *> *hostedBy = [NSMutableDictionary new];
    for (MMAgentCand *c in cands.allValues) if (c.root) {
        if (!hostedBy[@(c.root.pid)]) hostedBy[@(c.root.pid)] = [NSMutableArray new];
        [hostedBy[@(c.root.pid)] addObject:c];
    }

    // 5. One agent per remaining process, with the ranked signals of P18.
    NSMutableArray<MMAgent *> *found = [NSMutableArray new];
    for (MMAgentCand *c in cands.allValues) {
        if (c.root) continue;
        MMAgent *a = [self agentFor:c sample:s now:now];
        NSMutableArray *hosted = [NSMutableArray new];
        NSMutableArray<NSString *> *busy = [NSMutableArray new];
        for (MMAgentCand *h in [hostedBy[@(c.pid)] sortedArrayUsingComparator:^NSComparisonResult(MMAgentCand *x, MMAgentCand *y) {
                 return x.pid < y.pid ? NSOrderedAscending : NSOrderedDescending; }]) {
            MMAgent *ha = [self agentFor:h sample:s now:now];
            [hosted addObject:ha];
            if (ha.state == MMAgentWorking && ![busy containsObject:h.row.name]) [busy addObject:h.row.name];
        }
        a.hosted = hosted;
        // A hosted agent that works keeps its host working, so what it started stays protected.
        if (busy.count && a.state != MMAgentWorking && a.signal != MMAgentSignalStatusFile) {
            a.state = MMAgentWorking;
            a.signal = MMAgentSignalHosted;
            a.why = [NSString stringWithFormat:@"hosted %@ working", [busy componentsJoinedByString:@", "]];
        }
        [found addObject:a];
    }
    @synchronized (self) {
        for (NSNumber *pid in _lastWorking.allKeys) if (!procs[pid]) { [_lastWorking removeObjectForKey:pid]; [_lastSignal removeObjectForKey:pid]; }
    }
    @synchronized (_lastEvent) {
        for (NSNumber *pid in _lastEvent.allKeys) if (!procs[pid]) [_lastEvent removeObjectForKey:pid];
    }
    [found sortUsingComparator:^NSComparisonResult(MMAgent *x, MMAgent *y) {
        BOOL wx = x.state == MMAgentWorking, wy = y.state == MMAgentWorking;
        if (wx != wy) return wx ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult n = [x.row.name compare:y.row.name];
        return n != NSOrderedSame ? n : (x.key.pid < y.key.pid ? NSOrderedAscending : NSOrderedDescending);
    }];
    return found;
}

/// The ranked state of one candidate. The highest signal that has an answer decides:
/// 1. the status file, 2. an agent event or Codex's newest turn, 3. the row's own signals, held for holdSeconds.
- (MMAgent *)agentFor:(MMAgentCand *)c sample:(MMSample *)s now:(NSDate *)now {
    MMProc *p = [s proc:c.pid];
    MMAgent *a = [MMAgent new];
    a.row = c.row; a.harnessID = c.row.harnessID; a.surface = c.surface[@"kind"] ?: @"tui";
    a.key = p.key; a.treeCPU = [s treeCPU:c.pid]; a.treeFootprint = [s treeFootprint:c.pid];
    a.treePids = c.tree; a.sessionID = c.sid; a.cwd = [s cwdOf:c.pid];
    a.hosted = @[];

    // 1. P20. Claude Code's status file for this very process, matched by pid and start time in MMSessions.
    MMSession *live = [MMSessions.shared forPid:c.pid];
    if (live.liveStatus.length && [live.agent isEqualToString:@"claude-code"]) {
        a.sessionID = a.sessionID ?: live.sessionID;
        a.cwd = a.cwd ?: live.cwd;
        a.signal = MMAgentSignalStatusFile;
        NSString *st = live.liveStatus;
        if ([st isEqualToString:@"busy"]) { a.state = MMAgentWorking; a.why = @"status file busy"; }
        else if ([st isEqualToString:@"waiting"]) { a.state = MMAgentWaiting; a.why = @"status file waiting"; }
        else if ([st isEqualToString:@"idle"]) { a.state = MMAgentIdle; a.why = @"status file idle"; }
        // TESTS.md question 9: shell is no turn while a background shell runs, so it is idle.
        else if ([st isEqualToString:@"shell"]) { a.state = MMAgentIdle; a.why = @"status file shell: idle with a background shell"; }
        else { a.state = MMAgentUnknown; a.why = [NSString stringWithFormat:@"status file %@", st]; }
        return a;
    }

    // 2. P21 and P22. Codex's newest turn, then the newest hook event from cmux for this pid.
    if ([c.row.harnessID isEqualToString:@"codex"]) {
        MMSession *t = c.sid ? [MMSessions.shared withID:c.sid] : nil;
        if (!t && a.cwd) {
            for (MMSession *x in MMSessions.shared.all)
                if ([x.agent isEqualToString:@"codex"] && [x.cwd isEqualToString:a.cwd] && (!t || [x.lastActive compare:t.lastActive] == NSOrderedDescending)) t = x;
        }
        if ([t.liveStatus isEqualToString:@"inProgress"] && (!p.startSec || t.lastActive.timeIntervalSince1970 >= p.startSec)) {
            a.sessionID = a.sessionID ?: t.sessionID;
            a.state = MMAgentWorking; a.signal = MMAgentSignalEvent; a.why = @"codex turn in progress";
            return a;
        }
    }
    MMAgentEvent *e;
    @synchronized (_lastEvent) { e = _lastEvent[@(c.pid)]; }
    // An event from before this process started belongs to an earlier process with the same pid.
    if (e && (!p.startSec || e.at.timeIntervalSince1970 + 1 >= p.startSec)) {
        MMAgentState st = EventState(e.event, c.row.json);
        if (st != MMAgentUnknown) {
            a.sessionID = a.sessionID ?: e.sessionID;
            a.state = st; a.signal = MMAgentSignalEvent;
            a.why = [NSString stringWithFormat:@"event %@: %@", e.event, StateWord(st)];
            return a;
        }
    }

    // 3. The row's own signals, as Agents.m reads them. A state holds for holdSeconds after its last signal.
    NSDate *last; MMAgentSignal lastSig;
    @synchronized (self) {
        if (c.reasons.count) { _lastWorking[@(c.pid)] = now; _lastSignal[@(c.pid)] = @(c.topSignal); }
        last = _lastWorking[@(c.pid)];
        lastSig = (MMAgentSignal)[_lastSignal[@(c.pid)] integerValue];
    }
    BOOL held = !c.reasons.count && last && self.holdSeconds > 0 && [now timeIntervalSinceDate:last] <= self.holdSeconds;
    if (c.reasons.count) {
        a.state = MMAgentWorking; a.signal = c.topSignal; a.why = [c.reasons componentsJoinedByString:@", "];
    } else if (held) {
        a.state = MMAgentWorking; a.signal = lastSig;
        a.why = [NSString stringWithFormat:@"working %.0fs ago", [now timeIntervalSinceDate:last]];
    } else {
        // No signal fired: idle, unless the row says nothing outside the process can tell.
        a.state = [c.row.json[@"no_outside_signal"] boolValue] ? MMAgentUnknown : MMAgentIdle;
        a.signal = MMAgentSignalNone; a.why = @"";
    }
    return a;
}

- (MMAgent *)agentAbove:(pid_t)pid in:(NSArray<MMAgent *> *)agents sample:(MMSample *)s {
    for (MMAgent *a in agents) if ([a.treePids containsObject:@(pid)]) return a;
    // A pid that started after the agent's tree was read: walk its ancestors.
    NSArray<NSNumber *> *up = [s ancestorsOf:pid limit:20];
    for (MMAgent *a in agents) for (NSNumber *x in up) if (x.intValue == a.key.pid) return a;
    return nil;
}

@end
