#import "Agents.h"
#import <libproc.h>
#import <glob.h>
#import <sys/stat.h>
#import <mach-o/dyld.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

@implementation MMAgent
- (BOOL)working { return [self.state isEqualToString:@"working"]; }
- (NSDictionary *)json {
    return @{ @"harness": self.harness, @"id": self.harnessID, @"surface": self.surface, @"pid": @(self.pid),
              @"state": self.state, @"why": self.why ?: @"", @"cpu": @(round(self.cpu * 10) / 10),
              @"memoryBytes": @(self.memory), @"children": @(self.children),
              @"session": self.sessionID ?: NSNull.null,
              @"transcript_age": self.transcriptAge < 0 ? NSNull.null : @(self.transcriptAge),
              @"project": self.project ?: @"" };
}
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
static NSInteger Matches(NSDictionary *surface, NSArray<NSString *> *argv) {
    NSDictionary *spec = [surface[@"process"] isKindOfClass:NSDictionary.class] ? surface[@"process"] : nil;
    if (!spec.count || !argv.count) return 0;
    NSString *arg0 = argv.firstObject;
    BOOL named = [Strings(spec[@"names"]) containsObject:arg0.lastPathComponent];
    NSUInteger longest = 0; BOOL pathHit = NO;
    for (NSString *s in Strings(spec[@"path_contains"])) if ([arg0 containsString:s]) { pathHit = YES; longest = MAX(longest, s.length); }
    if (!named && !pathHit) return 0;
    for (NSString *x in Strings(spec[@"exclude_args"])) if ([argv containsObject:x]) return 0;
    NSArray *need = Strings(spec[@"args_contain"]);
    for (NSString *n in need) {
        BOOL found = NO;
        for (NSString *a in argv) if ([a containsString:n]) { found = YES; break; }
        if (!found) return 0;
    }
    return 1 + longest + need.count;
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
    NSMutableArray<MMAgent *> *found = [NSMutableArray new];
    pid_t me = getpid();

    {
        for (MMProc *p in procs.allValues) {
            if (p.pid == me) continue;
            NSDictionary *row = nil, *surface = nil; NSInteger best = 0;
            for (NSDictionary *r in _rows)
                for (NSDictionary *s in r[@"surfaces"]) {
                    NSInteger score = Matches(s, argvOf(p.pid));
                    if (score > best) { best = score; row = r; surface = s; }
                }
            if (!surface) continue;
            // A harness that re-executes itself appears twice; keep the outermost process.
            BOOL nested = NO;
            if (procs[@(p.ppid)]) for (NSDictionary *s in row[@"surfaces"]) if (Matches(s, argvOf(p.ppid))) nested = YES;
            if (nested) continue;

            NSMutableArray<NSNumber *> *tree = [NSMutableArray arrayWithObject:@(p.pid)];
            for (NSUInteger i = 0; i < tree.count; i++) [tree addObjectsFromArray:kids[tree[i]] ?: @[]];
            double cpu = 0; uint64_t mem = 0;
            for (NSNumber *pid in tree) { MMProc *q = procs[pid]; if (q) { cpu += q.cpuPercent; mem += q.footprint; } }
            // Direct children only. Descendants include MCP servers, language servers and
            // relaunch children that live as long as the session does.
            NSMutableArray<NSString *> *names = [NSMutableArray new];
            for (NSNumber *pid in kids[@(p.pid)]) if (procs[pid]) [names addObject:procs[pid].name];
            NSString *sid = SessionID(surface, argvOf(p.pid));
            NSInteger age = TranscriptAge(row, sid);

            NSMutableArray<NSString *> *reasons = [NSMutableArray new];
            for (NSDictionary *sig in row[@"working_signals"]) {
                NSString *kind = sig[@"signal"];
                if ([kind isEqualToString:@"child_process"]) {
                    if (sig[@"name"] && [names containsObject:sig[@"name"]]) [reasons addObject:[NSString stringWithFormat:@"child %@", sig[@"name"]]];
                } else if ([kind isEqualToString:@"tree_cpu"]) {
                    double floor = sig[@"floor_percent"] ? [sig[@"floor_percent"] doubleValue] : 3;
                    if (cpu >= floor) [reasons addObject:[NSString stringWithFormat:@"cpu %.0f%%", cpu]];
                } else if ([kind isEqualToString:@"transcript_write"]) {
                    NSInteger within = sig[@"within_seconds"] ? [sig[@"within_seconds"] integerValue] : 30;
                    if (age >= 0 && age <= within) [reasons addObject:[NSString stringWithFormat:@"transcript %lds ago", (long)age]];
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
            if (reasons.count) _lastWorking[@(p.pid)] = now;
            NSDate *last = _lastWorking[@(p.pid)];
            BOOL held = !reasons.count && last && self.holdSeconds > 0 && [now timeIntervalSinceDate:last] <= self.holdSeconds;

            MMAgent *a = [MMAgent new];
            a.harness = row[@"name"] ?: row[@"id"]; a.harnessID = row[@"id"]; a.surface = surface[@"kind"] ?: @"tui";
            a.pid = p.pid; a.cpu = cpu; a.memory = mem; a.children = [kids[@(p.pid)] count]; a.treePids = tree;
            a.sessionID = sid; a.transcriptAge = age; a.project = WorkingDirectory(p.pid);
            a.state = (reasons.count || held) ? @"working" : @"idle";
            a.why = reasons.count ? [reasons componentsJoinedByString:@", "]
                  : held ? [NSString stringWithFormat:@"working %.0fs ago", [now timeIntervalSinceDate:last]] : @"";
            [found addObject:a];
        }
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
