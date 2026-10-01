#import "Agents.h"
#import <libproc.h>
#import <glob.h>
#import <sys/stat.h>
#import <mach-o/dyld.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

@implementation MMAgent
- (BOOL)working { return [self.state isEqualToString:@"working"] || [self.state isEqualToString:@"blocked"]; }   // blocked is still a live turn
- (NSDictionary *)json {
    NSMutableDictionary *j = [@{ @"harness": self.harness, @"id": self.harnessID, @"surface": self.surface, @"pid": @(self.pid),
              @"state": self.state, @"why": self.why ?: @"", @"cpu": @(round(self.cpu * 10) / 10),
              @"memoryBytes": @(self.memory), @"children": @(self.children),
              @"session": self.sessionID ?: NSNull.null,
              @"transcript_age": self.transcriptAge < 0 ? NSNull.null : @(self.transcriptAge),
              @"project": self.project ?: @"" } mutableCopy];
    if (self.hosted.count) j[@"hosted"] = self.hosted;
    return j;
}
@end

/// One process that matched a row, with what was read from it.
@interface MMCand : NSObject
@property pid_t pid;
@property (strong) NSDictionary *row, *surface;
@property BOOL absent;                                  // the row's presence guard failed
@property double cpu; @property uint64_t memory;
@property (strong) NSArray<NSNumber *> *tree;
@property (strong) NSArray<NSString *> *names;          // direct children
@property (copy) NSString *sid;
@property NSInteger age;
@property (strong) NSArray<NSString *> *reasons;        // signals that fired now
@property (strong) MMCand *root;                        // the host this one is folded into, or nil
@end
@implementation MMCand
@end

@implementation MMAgents {
    NSArray<NSDictionary *> *_rows;
    NSMutableDictionary<NSNumber *, NSDate *> *_lastWorking;   // pid -> last time a signal fired
}

+ (NSArray<NSString *> *)defaultRowDirectories {
    NSMutableArray *dirs = [NSMutableArray new];
    // The CLI runs through a symlink, where NSBundle may not resolve; find Resources from the real executable.
    char buf[PATH_MAX]; uint32_t size = sizeof buf; char real[PATH_MAX];
    if (_NSGetExecutablePath(buf, &size) == 0 && realpath(buf, real)) {
        NSString *contents = [[@(real) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        [dirs addObject:[contents stringByAppendingPathComponent:@"Resources/registry/agents"]];
    }
    NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                         stringByAppendingPathComponent:@"MinMacs/agents"];
    [dirs addObject:support];   // the user's own rows win over bundled ones with the same id
    return dirs;
}

- (instancetype)initWithRowDirectories:(NSArray<NSString *> *)dirs {
    if ((self = [super init])) {
        _holdSeconds = 30;   // from the only measurement: 30 s misses 4% of in-turn gaps, 20 s misses 7%
        _lastWorking = [NSMutableDictionary new];
        NSMutableDictionary<NSString *, NSDictionary *> *byID = [NSMutableDictionary new];
        for (NSString *dir in dirs) {
            for (NSString *f in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
                if (![f.pathExtension isEqualToString:@"json"]) continue;
                NSData *d = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:f]];
                NSDictionary *row = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
                if (![row isKindOfClass:NSDictionary.class] || ![row[@"id"] isKindOfClass:NSString.class]) continue;
                if (![row[@"surfaces"] isKindOfClass:NSArray.class] || ![row[@"working_signals"] isKindOfClass:NSArray.class]) continue;
                byID[row[@"id"]] = row;
            }
        }
        _rows = [byID.allValues sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES]]];
    }
    return self;
}

- (NSInteger)rowCount { return _rows.count; }

#pragma mark Process facts

static NSString *WorkingDirectory(pid_t pid) {
    struct proc_vnodepathinfo v;
    if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &v, sizeof v) <= 0) return @"";
    NSString *p = @(v.pvi_cdir.vip_path);
    NSString *home = NSHomeDirectory();
    return [p hasPrefix:home] ? [@"~" stringByAppendingString:[p substringFromIndex:home.length]] : p;
}

static NSArray *Strings(id v) { return [v isKindOfClass:NSArray.class] ? v : @[]; }

/// Matching reads the command line only, exactly like tools/agents_probe.py:
/// names against the base name of argv[0], path_contains against argv[0] itself.
/// The executable path is deliberately ignored: a harness may ship helper tools inside
/// its own binary and run them under another name (Claude Code runs ugrep that way).
/// 0 when the surface does not match. Otherwise a score: how specific the match was.
/// A process that matches two rows belongs to the more specific one, so the claude binary
/// that Xcode ships is an Xcode agent, not a terminal session.
/// rowAbsent: the row has a presence list and none of its paths exists. A match that rests on
/// a bare name (no path_contains entry hit) then does not count: another program has that name.
static NSInteger Matches(NSDictionary *surface, NSArray<NSString *> *argv, BOOL rowAbsent) {
    NSDictionary *spec = [surface[@"process"] isKindOfClass:NSDictionary.class] ? surface[@"process"] : nil;
    if (!spec.count || !argv.count) return 0;
    NSString *arg0 = argv.firstObject;
    BOOL named = [Strings(spec[@"names"]) containsObject:arg0.lastPathComponent];
    NSUInteger longest = 0; BOOL pathHit = NO;
    for (NSString *s in Strings(spec[@"path_contains"])) if ([arg0 containsString:s]) { pathHit = YES; longest = MAX(longest, s.length); }
    if (!named && !pathHit) return 0;
    if (named && !pathHit && rowAbsent) return 0;
    for (NSString *x in Strings(spec[@"exclude_args"])) if ([argv containsObject:x]) return 0;
    NSArray *need = Strings(spec[@"args_contain"]);
    for (NSString *n in need) {
        BOOL found = NO;
        for (NSString *a in argv) if ([a containsString:n]) { found = YES; break; }
        if (!found) return 0;
    }
    return 1 + longest + need.count;
}

static BOOL RowMatches(NSDictionary *row, BOOL rowAbsent, NSArray<NSString *> *argv) {
    for (NSDictionary *s in row[@"surfaces"]) if (Matches(s, argv, rowAbsent)) return YES;
    return NO;
}

/// True when at least one of the paths exists (~ and globs allowed).
static BOOL AnyPathExists(NSArray *paths) {
    for (NSString *path in paths) {
        if (![path isKindOfClass:NSString.class]) continue;
        glob_t g; memset(&g, 0, sizeof g);
        BOOL hit = glob(path.fileSystemRepresentation, GLOB_TILDE, NULL, &g) == 0 && g.gl_pathc > 0;
        globfree(&g);
        if (hit) return YES;
    }
    return NO;
}

/// A child_process signal's args_contain: every entry must be an argument of the child. For -w
/// the argument after it must be the pid of the matched process (caffeinate -w <pid> ends when
/// that process does, so it is that process's own inhibitor and nobody else's).
static BOOL ChildArgsOK(NSArray *need, NSArray<NSString *> *childArgv, pid_t owner) {
    for (NSString *n in need) {
        NSUInteger at = childArgv.count > 1 ? [childArgv indexOfObject:n inRange:NSMakeRange(1, childArgv.count - 1)] : NSNotFound;
        if (at == NSNotFound) return NO;
        if ([n isEqualToString:@"-w"]) {
            if (at + 1 >= childArgv.count || ![childArgv[at + 1] isEqualToString:[NSString stringWithFormat:@"%d", owner]]) return NO;
        }
    }
    return YES;
}

static NSString *SessionID(NSDictionary *surface, NSArray<NSString *> *argv) {
    for (NSString *flag in Strings(surface[@"session_id_args"])) {
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

/// Seconds since the newest file matching the row's per-session pattern was written, or -1.
static NSInteger TranscriptAge(NSDictionary *row, NSString *sid) {
    NSString *pattern = [row[@"session_store"] isKindOfClass:NSDictionary.class] ? row[@"session_store"][@"per_session"] : nil;
    if (!sid.length || ![pattern isKindOfClass:NSString.class]) return -1;
    pattern = [pattern stringByReplacingOccurrencesOfString:@"{session_id}" withString:sid];
    glob_t g; time_t newest = 0;
    if (glob(pattern.fileSystemRepresentation, GLOB_TILDE, NULL, &g) == 0) {
        for (size_t i = 0; i < g.gl_pathc; i++) { struct stat st; if (stat(g.gl_pathv[i], &st) == 0 && st.st_mtime > newest) newest = st.st_mtime; }
    }
    globfree(&g);
    return newest ? (NSInteger)(time(NULL) - newest) : -1;
}

/// pid -> names of the power assertions it holds.
static NSDictionary<NSNumber *, NSArray<NSString *> *> *AssertionsByPid(void) {
    CFDictionaryRef byPid = NULL;
    NSMutableDictionary *out = [NSMutableDictionary new];
    if (IOPMCopyAssertionsByProcess(&byPid) == kIOReturnSuccess && byPid) {
        NSDictionary *d = (__bridge NSDictionary *)byPid;
        for (NSNumber *pid in d) {
            NSMutableArray *names = [NSMutableArray new];
            for (NSDictionary *a in d[pid]) [names addObject:a[@"AssertName"] ?: @""];
            out[pid] = names;
        }
        CFRelease(byPid);
    }
    return out;
}

#pragma mark Detection

- (NSArray<MMAgent *> *)detect:(MMScanner *)scanner {
    NSDictionary<NSNumber *, MMProc *> *procs = scanner.processes;
    NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *> *kids = [NSMutableDictionary new];
    for (MMProc *p in procs.allValues) {
        if (!kids[@(p.ppid)]) kids[@(p.ppid)] = [NSMutableArray new];
        [kids[@(p.ppid)] addObject:@(p.pid)];
    }
    NSMutableDictionary<NSNumber *, NSArray *> *argv = [NSMutableDictionary new];
    NSArray *(^argvOf)(pid_t) = ^(pid_t pid) { if (!argv[@(pid)]) argv[@(pid)] = MMProcessArgs(pid) ?: @[]; return argv[@(pid)]; };
    NSDictionary<NSNumber *, NSArray<NSString *> *> *asserting = nil;
    NSDate *now = NSDate.date;
    pid_t me = getpid();

    // Rows with a presence list where none of the paths exists: their bare-name matches do not count.
    NSMutableArray<NSNumber *> *absent = [NSMutableArray new];
    for (NSDictionary *r in _rows) { NSArray *pr = Strings(r[@"presence"]); [absent addObject:@(pr.count && !AnyPathExists(pr))]; }

    // 1. The most specific row and surface for every process.
    NSMutableDictionary<NSNumber *, MMCand *> *best = [NSMutableDictionary new];
    for (MMProc *p in procs.allValues) {
        if (p.pid == me) continue;
        NSArray *av = argvOf(p.pid);
        MMCand *c = nil; NSInteger top = 0;
        for (NSUInteger i = 0; i < _rows.count; i++)
            for (NSDictionary *s in _rows[i][@"surfaces"]) {
                NSInteger score = Matches(s, av, [absent[i] boolValue]);
                if (score > top) { top = score; c = [MMCand new]; c.pid = p.pid; c.row = _rows[i]; c.surface = s; c.absent = [absent[i] boolValue]; }
            }
        if (c) best[@(p.pid)] = c;
    }

    // 2. A harness that re-executes itself appears twice; keep the outermost process.
    NSMutableDictionary<NSNumber *, MMCand *> *cands = [NSMutableDictionary new];
    for (MMCand *c in best.allValues) {
        MMProc *p = procs[@(c.pid)];
        if (procs[@(p.ppid)] && RowMatches(c.row, c.absent, argvOf(p.ppid))) continue;
        cands[@(c.pid)] = c;
    }

    // 3. What each one shows right now.
    for (MMCand *c in cands.allValues) {
        MMProc *p = procs[@(c.pid)];
        NSMutableArray<NSNumber *> *tree = [NSMutableArray arrayWithObject:@(p.pid)];
        for (NSUInteger i = 0; i < tree.count; i++) [tree addObjectsFromArray:kids[tree[i]] ?: @[]];
        double cpu = 0; uint64_t mem = 0;
        for (NSNumber *pid in tree) { MMProc *q = procs[pid]; if (q) { cpu += q.cpuPercent; mem += q.footprint; } }
        // Direct children only. Descendants include MCP servers, language servers and
        // relaunch children that live as long as the session does.
        NSMutableArray<NSString *> *names = [NSMutableArray new];
        for (NSNumber *pid in kids[@(p.pid)]) if (procs[pid]) [names addObject:procs[pid].name];
        c.tree = tree; c.cpu = cpu; c.memory = mem; c.names = names;
        c.sid = SessionID(c.surface, argvOf(p.pid));
        c.age = TranscriptAge(c.row, c.sid);

        NSMutableArray<NSString *> *reasons = [NSMutableArray new];
        for (NSDictionary *sig in c.row[@"working_signals"]) {
            NSString *kind = sig[@"signal"];
            if ([kind isEqualToString:@"child_process"]) {
                if (![sig[@"name"] isKindOfClass:NSString.class]) continue;
                NSArray *need = Strings(sig[@"args_contain"]);
                BOOL hit = NO;
                for (NSNumber *pid in kids[@(p.pid)])
                    if ([procs[pid].name isEqualToString:sig[@"name"]] && (!need.count || ChildArgsOK(need, argvOf(pid.intValue), p.pid))) { hit = YES; break; }
                if (hit) [reasons addObject:[NSString stringWithFormat:@"child %@", sig[@"name"]]];
            } else if ([kind isEqualToString:@"tree_cpu"]) {
                double floor = sig[@"floor_percent"] ? [sig[@"floor_percent"] doubleValue] : 3;
                if (cpu >= floor) [reasons addObject:[NSString stringWithFormat:@"cpu %.0f%%", cpu]];
            } else if ([kind isEqualToString:@"transcript_write"]) {
                NSInteger within = sig[@"within_seconds"] ? [sig[@"within_seconds"] integerValue] : 30;
                if (c.age >= 0 && c.age <= within) [reasons addObject:[NSString stringWithFormat:@"transcript %lds ago", (long)c.age]];
            } else if ([kind isEqualToString:@"tool_children"]) {
                for (NSString *n in names) if ([Shells() containsObject:n]) { [reasons addObject:@"tool shell running"]; break; }
            } else if ([kind isEqualToString:@"power_assertion"]) {
                if (!asserting) asserting = AssertionsByPid();
                NSString *want = [sig[@"name"] isKindOfClass:NSString.class] ? [sig[@"name"] lowercaseString] : nil;
                BOOL hit = NO;
                for (NSNumber *pid in tree) {
                    if ([procs[pid].name isEqualToString:@"caffeinate"]) continue;   // that is the child_process signal
                    for (NSString *n in asserting[pid]) if (!want || [n.lowercaseString containsString:want]) hit = YES;
                }
                if (hit) [reasons addObject:@"holds a sleep assertion"];
            }
        }
        c.reasons = reasons;
    }

    // 4. A process with a host or orchestrator of another row above it belongs to that host: report
    // the host once. Its tree already holds the child's CPU and memory, so nothing is added twice.
    // The owner's own sessions under a multiplexer that is not a row (cmux) have no such ancestor.
    for (MMCand *c in cands.allValues) {
        MMCand *cur = c;
        for (int hops = 0; hops < 64; hops++) {
            MMCand *host = nil; pid_t a = procs[@(cur.pid)].ppid;
            for (int d = 0; d < 4096 && a > 1 && procs[@(a)]; d++, a = procs[@(a)].ppid) {
                MMCand *m = best[@(a)];
                if (m && ![m.row[@"id"] isEqual:cur.row[@"id"]] && [m.surface[@"hosts_agents"] boolValue]) { host = m; break; }
            }
            if (!host) break;
            pid_t top = host.pid;
            for (int d = 0; d < 4096; d++) {
                pid_t up = procs[@(top)].ppid;
                if (!procs[@(up)] || !RowMatches(host.row, host.absent, argvOf(up))) break;
                top = up;
            }
            MMCand *root = cands[@(top)];
            if (!root || ![root.row[@"id"] isEqual:host.row[@"id"]]) root = cands[@(host.pid)];
            if (!root) break;
            cur = root;
        }
        if (cur != c) c.root = cur;
    }
    NSMutableDictionary<NSNumber *, NSMutableArray<MMCand *> *> *hostedBy = [NSMutableDictionary new];
    for (MMCand *c in cands.allValues) if (c.root) {
        if (!hostedBy[@(c.root.pid)]) hostedBy[@(c.root.pid)] = [NSMutableArray new];
        [hostedBy[@(c.root.pid)] addObject:c];
    }

    // 5. One agent per remaining process.
    NSMutableArray<MMAgent *> *found = [NSMutableArray new];
    for (MMCand *c in cands.allValues) {
        if (c.root) continue;
        NSMutableArray<NSString *> *reasons = [c.reasons mutableCopy];
        NSMutableArray<NSDictionary *> *hosted = [NSMutableArray new];
        NSMutableArray<NSString *> *busy = [NSMutableArray new];
        for (MMCand *h in [hostedBy[@(c.pid)] sortedArrayUsingComparator:^NSComparisonResult(MMCand *x, MMCand *y) { return x.pid < y.pid ? NSOrderedAscending : NSOrderedDescending; }]) {
            NSString *name = h.row[@"name"] ?: h.row[@"id"];
            if (h.reasons.count && ![busy containsObject:name]) [busy addObject:name];
            [hosted addObject:@{ @"harness": name, @"id": h.row[@"id"], @"pid": @(h.pid),
                                 @"state": h.reasons.count ? @"working" : ([h.row[@"no_outside_signal"] boolValue] ? @"unknown" : @"idle") }];
        }
        // A hosted agent that is working keeps its host working: what it started stays protected.
        if (busy.count) [reasons addObject:[NSString stringWithFormat:@"hosted %@ working", [busy componentsJoinedByString:@", "]]];
        if (reasons.count) _lastWorking[@(c.pid)] = now;
        NSDate *last = _lastWorking[@(c.pid)];
        BOOL held = !reasons.count && last && self.holdSeconds > 0 && [now timeIntervalSinceDate:last] <= self.holdSeconds;

        MMAgent *a = [MMAgent new];
        a.harness = c.row[@"name"] ?: c.row[@"id"]; a.harnessID = c.row[@"id"]; a.surface = c.surface[@"kind"] ?: @"tui";
        a.pid = c.pid; a.cpu = c.cpu; a.memory = c.memory; a.children = [kids[@(c.pid)] count]; a.treePids = c.tree;
        a.sessionID = c.sid; a.transcriptAge = c.age; a.project = WorkingDirectory(c.pid);
        a.hosted = hosted;
        // No signal fired: idle, unless the row says nothing outside the process can tell (unknown).
        a.state = (reasons.count || held) ? @"working" : ([c.row[@"no_outside_signal"] boolValue] ? @"unknown" : @"idle");
        a.why = reasons.count ? [reasons componentsJoinedByString:@", "]
              : held ? [NSString stringWithFormat:@"working %.0fs ago", [now timeIntervalSinceDate:last]] : @"";
        NSString *ov = self.overrides[@(c.pid)];
        if (ov && ([ov isEqualToString:@"blocked"] || [ov isEqualToString:@"unknown"] || [a.state isEqualToString:@"idle"])) {
            a.state = ov;
            a.why = self.overrideReasons[@(c.pid)] ?: ov;
        }
        [found addObject:a];
    }
    // Forget sessions that ended.
    for (NSNumber *pid in _lastWorking.allKeys) if (!procs[pid]) [_lastWorking removeObjectForKey:pid];
    [found sortUsingComparator:^NSComparisonResult(MMAgent *a, MMAgent *b) {
        if (a.working != b.working) return a.working ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult n = [a.harness compare:b.harness];
        return n != NSOrderedSame ? n : (a.pid < b.pid ? NSOrderedAscending : NSOrderedDescending);
    }];
    return found;
}

- (MMAgent *)workingAgentOwning:(pid_t)pid in:(NSArray<MMAgent *> *)agents {
    for (MMAgent *a in agents) if (a.working && [a.treePids containsObject:@(pid)]) return a;
    return nil;
}

@end
