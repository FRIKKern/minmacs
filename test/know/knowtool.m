// The Know checks' tool. It links all of Sources/Core, so samples come from the real Senses, and prints JSON.
// Usage: knowtool <command> [args]
//   rows <dir>...                         rows loaded, in order, later folders winning
//   agents [--rows <dir>]... [--hold s] [--events s]   detected agents. --events starts the cmux reader first
//   sessions [--pid n] [--id x] [--latest-in dir] [--open-at epoch --folders a,b]
//   where <pid>                           MMWhereIs with wait YES
//   goto <pid>                            MMWhereIs, then MMGoTo
//   events <seconds>                      the events MMAgentEvents read in that time
//   cache                                 MMFactCache checks, one line each
//   run                                   MMRun checks, one line each
//   where-prune <pid>                     MMWhereIs caches pid's place, ends pid, and the cache drops it
//   sizer quick <path> | exact <path>...  MMSizer in process
#import <Cocoa/Cocoa.h>
#import "Core/Know/MMRegistry.h"
#import "Core/Know/MMSessions.h"
#import "Core/Know/MMWhere.h"
#import "Core/Know/MMGit.h"
#import "Core/Know/MMFactCache.h"
#import "Core/Know/MMSizer.h"
#import <sys/wait.h>

@interface MMFactCache (Drain)
- (void)drain;
@end
BOOL MMWhereCached(MMProcKey key);   // MMWhere.m

/// Two passes half a second apart, so the second has CPU over that time, as the app's 5-second pass does.
static MMSample *LiveSample(void) {
    [MMSenses.shared sampleNow];
    usleep(500000);
    return [MMSenses.shared sampleNow];
}

static NSString *State(MMAgentState s) {
    switch (s) { case MMAgentWorking: return @"working"; case MMAgentWaiting: return @"waiting"; case MMAgentIdle: return @"idle"; default: return @"unknown"; }
}
static NSString *Signal(MMAgentSignal s) {
    NSArray *n = @[@"none", @"status_file", @"event", @"caffeinate", @"child", @"assertion", @"transcript", @"tree_cpu", @"hosted"];
    return (NSUInteger)s < n.count ? n[s] : @"?";
}
static NSString *Kind(MMPlaceKind k) {
    NSArray *n = @[@"unknown", @"cmux", @"tmux", @"terminal", @"iterm", @"app"];
    return (NSUInteger)k < n.count ? n[k] : @"?";
}

static void Print(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
}

static void Wait(double seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static NSDictionary *AgentJSON(MMAgent *a) {
    NSMutableDictionary *j = [@{ @"id": a.harnessID, @"state": State(a.state), @"signal": Signal(a.signal), @"why": a.why ?: @"",
                                 @"pid": @(a.key.pid), @"surface": a.surface ?: @"", @"cwd": a.cwd ?: @"",
                                 @"session": a.sessionID ?: NSNull.null } mutableCopy];
    NSMutableArray *h = [NSMutableArray new];
    for (MMAgent *x in a.hosted) [h addObject:@{ @"id": x.harnessID, @"state": State(x.state), @"pid": @(x.key.pid) }];
    if (h.count) j[@"hosted"] = h;
    return j;
}

static NSDictionary *SessionJSON(MMSession *s) {
    if (!s) return (id)NSNull.null;
    return @{ @"agent": s.agent ?: @"", @"id": s.sessionID ?: @"", @"title": s.title ?: @"", @"cwd": s.cwd ?: @"",
              @"branch": s.branch ?: @"", @"transcript": s.transcript ?: @"", @"pid": @(s.pid),
              @"live": s.liveStatus ?: NSNull.null, @"stillWorking": @(s.stillWorking),
              @"started": @(round(s.started.timeIntervalSince1970)), @"lastActive": @(round(s.lastActive.timeIntervalSince1970)) };
}

static NSDictionary *PlaceJSON(MMPlace *w) {
    if (!w) return (id)NSNull.null;
    return @{ @"kind": Kind(w.kind), @"app": w.app ?: @"", @"label": w.label ?: @"", @"tab": w.tab ?: @"", @"window": w.window ?: @"",
              @"workspace": w.workspace ?: @"", @"surface": w.surface ?: @"", @"target": w.target ?: @"", @"tty": w.tty ?: @"",
              @"appPid": @(w.appPid) };
}

static NSString *Opt(NSArray *args, NSString *flag) {
    NSUInteger i = [args indexOfObject:flag];
    return i != NSNotFound && i + 1 < args.count ? args[i + 1] : nil;
}

static int Agents(NSArray<NSString *> *args) {
    NSMutableArray *dirs = [NSMutableArray new];
    for (NSUInteger i = 0; i + 1 < args.count; i++) if ([args[i] isEqualToString:@"--rows"]) [dirs addObject:args[i + 1]];
    MMRegistry *r = dirs.count ? [[MMRegistry alloc] initWithRowDirectories:dirs] : MMRegistry.shared;
    if (Opt(args, @"--hold")) r.holdSeconds = Opt(args, @"--hold").doubleValue;
    else r.holdSeconds = 0;
    NSString *ev = Opt(args, @"--events");
    if (ev) { [MMAgentEvents.shared start]; Wait(ev.doubleValue); }
    [MMSessions.shared refresh];
    MMSample *sample = LiveSample();
    NSArray<MMAgent *> *agents = [r agentsIn:sample power:MMSenses.shared.power];
    if (ev) [MMAgentEvents.shared stop];
    NSMutableArray *list = [NSMutableArray new];
    NSInteger w = 0, i = 0, wt = 0, u = 0;
    for (MMAgent *a in agents) {
        [list addObject:AgentJSON(a)];
        if (a.state == MMAgentWorking) w++; else if (a.state == MMAgentIdle) i++; else if (a.state == MMAgentWaiting) wt++; else u++;
    }
    Print(@{ @"agents": list, @"working": @(w), @"idle": @(i), @"waiting": @(wt), @"unknown": @(u),
             @"events": MMAgentEvents.shared.unavailableReason ?: @"reading" });
    return 0;
}

static int Sessions(NSArray<NSString *> *args) {
    MMSessions *s = MMSessions.shared;
    [s refresh];
    NSMutableDictionary *j = [NSMutableDictionary new];
    NSMutableArray *all = [NSMutableArray new];
    for (MMSession *x in s.all) [all addObject:SessionJSON(x)];
    j[@"all"] = all;
    if (Opt(args, @"--pid")) j[@"forPid"] = SessionJSON([s forPid:Opt(args, @"--pid").intValue]);
    if (Opt(args, @"--id")) j[@"withID"] = SessionJSON([s withID:Opt(args, @"--id")]);
    if (Opt(args, @"--latest-in")) j[@"latestIn"] = SessionJSON([s latestIn:Opt(args, @"--latest-in")]);
    if (Opt(args, @"--open-at"))
        j[@"openAt"] = SessionJSON([s openAt:[NSDate dateWithTimeIntervalSince1970:Opt(args, @"--open-at").doubleValue]
                                   inFolders:[Opt(args, @"--folders") componentsSeparatedByString:@","] ?: @[]]);
    Print(j);
    return 0;
}

static MMProcKey KeyFor(pid_t pid) {
    MMProc *p = [[MMSenses.shared sampleNow] proc:pid];
    return (MMProcKey){ pid, p.startSec };
}

static int Events(double seconds) {
    NSMutableArray *got = [NSMutableArray new];
    id token = [MMAgentEvents.shared observe:^(MMAgentEvent *e) {
        @synchronized (got) {
            [got addObject:@{ @"agent": e.agent ?: @"", @"event": e.event ?: @"", @"session": e.sessionID ?: @"", @"cwd": e.cwd ?: @"",
                              @"ppid": @(e.ppid), @"at": @(round(e.at.timeIntervalSince1970)) }];
        }
    }];
    [MMAgentEvents.shared start];
    Wait(seconds);
    [MMAgentEvents.shared stop];
    [MMAgentEvents.shared stopObserving:token];
    @synchronized (got) { Print(@{ @"events": got, @"reason": MMAgentEvents.shared.unavailableReason ?: @"reading" }); }
    return 0;
}

static void Line(NSString *name, id value) { printf("%s=%s\n", name.UTF8String, [value description].UTF8String); }

static int Cache(void) {
    __block int computed = 0;
    MMFactCache<NSString *> *c = [[MMFactCache alloc] initWithName:@"know-check" maxAge:0 persist:YES];
    NSString *(^work)(void) = ^NSString *{ computed++; return [NSString stringWithFormat:@"v%d", computed]; };
    Line(@"wait_yes_computes", [c valueFor:@"a" fingerprint:@"1" orCompute:work wait:YES]);
    Line(@"same_fingerprint_is_cached", [c valueFor:@"a" fingerprint:@"1" orCompute:work wait:YES]);
    Line(@"changed_reports_yes", @([c changed:@"a" fingerprint:@"2"]));
    Line(@"new_fingerprint_recomputes", [c valueFor:@"a" fingerprint:@"2" orCompute:work wait:YES]);
    Line(@"wait_no_miss_returns_nil", [c valueFor:@"b" fingerprint:@"1" orCompute:work wait:NO] ?: @"nil");
    [c drain];
    Line(@"wait_no_fills_in_background", [c peek:@"b"] ?: @"nil");
    Line(@"stale_read_returns_old_value", [c valueFor:@"b" fingerprint:@"9" orCompute:work wait:NO] ?: @"nil");
    [c drain];
    Line(@"then_the_fresh_one", [c peek:@"b"] ?: @"nil");
    [c forget:[NSSet setWithObject:@"a"]];
    Line(@"forget_drops_dead_keys", [c peek:@"b"] ?: @"nil");
    [c drain];
    MMFactCache<NSString *> *again = [[MMFactCache alloc] initWithName:@"know-check" maxAge:0 persist:YES];
    Line(@"persist_survives_a_new_instance", [again valueFor:@"a" fingerprint:@"2" orCompute:^NSString *{ return @"recomputed"; } wait:YES]);
    MMFactCache<NSString *> *aged = [[MMFactCache alloc] initWithName:@"know-aged" maxAge:0.3 persist:NO];
    [aged valueFor:@"k" fingerprint:@"1" orCompute:^NSString *{ return @"first"; } wait:YES];
    usleep(400000);
    Line(@"max_age_expires", [aged valueFor:@"k" fingerprint:@"1" orCompute:^NSString *{ return @"second"; } wait:YES]);
    return 0;
}

static NSString *Out(NSData *d) { return [[[NSString alloc] initWithData:d ?: NSData.data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet]; }

static int Run(void) {
    NSData *o = nil, *e = nil;
    MMRunResult r = MMRun(@"/bin/echo", @[@"hello"], nil, nil, nil, 5, &o, &e);
    Line(@"output", Out(o)); Line(@"status", @(r.status)); Line(@"didRun", @(r.didRun));
    r = MMRun(@"/bin/cat", @[], [@"from stdin" dataUsingEncoding:NSUTF8StringEncoding], nil, nil, 5, &o, NULL);
    Line(@"stdin", Out(o));
    r = MMRun(@"/bin/sh", @[@"-c", @"echo ${MINMACS_HOME:-unset} $ADDED; echo err >&2; exit 3"], nil, @{ @"ADDED": @"added" }, nil, 5, &o, &e);
    Line(@"clean_env", Out(o)); Line(@"stderr", Out(e)); Line(@"exit_status", @(r.status));
    r = MMRun(@"/bin/pwd", @[], nil, nil, @"/usr", 5, &o, NULL);
    Line(@"cwd", Out(o));
    NSDate *t0 = NSDate.date;
    r = MMRun(@"/bin/sleep", @[@"5"], nil, nil, nil, 0.5, &o, NULL);
    Line(@"timed_out", @(r.timedOut)); Line(@"timed_out_status", @(r.status));
    Line(@"stopped_within_2s", @(-t0.timeIntervalSinceNow < 2));
    // A child that ignores SIGTERM gets SIGKILL a second later.
    t0 = NSDate.date;
    r = MMRun(@"/bin/sh", @[@"-c", @"trap '' TERM; sleep 5"], nil, nil, nil, 0.5, &o, NULL);
    Line(@"term_ignored_killed_within_3s", @(r.timedOut && -t0.timeIntervalSinceNow < 3));
    // A child that exits without reading 4 MB of input. Without F_SETNOSIGPIPE, SIGPIPE ends this tool here.
    r = MMRun(@"/usr/bin/true", @[], [NSMutableData dataWithLength:4 * 1024 * 1024], nil, nil, 5, &o, NULL);
    usleep(200000);
    Line(@"unread_input_status", @(r.status));
    // A grandchild that keeps the pipes open past the limit. The call still returns, and stops reading.
    NSString *gpid = [NSProcessInfo.processInfo.environment[@"MINMACS_HOME"] stringByAppendingPathComponent:@"know-grandchild.pid"];
    t0 = NSDate.date;
    r = MMRun(@"/bin/sh", @[@"-c", [NSString stringWithFormat:@"sleep 30 & echo $! > '%@'; exec sleep 30", gpid]], nil, nil, nil, 0.5, &o, NULL);
    Line(@"held_pipes_return_within_3s", @(r.timedOut && -t0.timeIntervalSinceNow < 3));
    pid_t g = [[NSString stringWithContentsOfFile:gpid encoding:NSUTF8StringEncoding error:nil] intValue];
    if (g > 1) kill(g, SIGTERM);   // the grandchild this check started
    r = MMRun(@"/no/such/tool", @[], nil, nil, nil, 1, &o, NULL);
    Line(@"missing_didRun", @(r.didRun)); Line(@"missing_status", @(r.status));
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Fixtures only: every file this tool reads or writes is under MINMACS_HOME and the agent homes test.sh sets.
        if (!NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length) { fprintf(stderr, "knowtool: set MINMACS_HOME\n"); return 2; }
        NSMutableArray<NSString *> *args = [NSMutableArray new];
        for (int i = 1; i < argc; i++) [args addObject:@(argv[i])];
        NSString *cmd = args.firstObject ?: @"";
        NSArray *rest = args.count > 1 ? [args subarrayWithRange:NSMakeRange(1, args.count - 1)] : @[];
        if ([cmd isEqualToString:@"rows"]) {
            MMRegistry *r = [[MMRegistry alloc] initWithRowDirectories:rest];
            NSMutableArray *names = [NSMutableArray new];
            for (MMAgentRow *row in r.rows) [names addObject:[NSString stringWithFormat:@"%@=%@", row.harnessID, row.name]];
            Print(@{ @"count": @(r.rows.count), @"rows": names, @"defaults": MMRegistry.defaultRowDirectories });
            return 0;
        }
        if ([cmd isEqualToString:@"agents"]) return Agents(rest);
        if ([cmd isEqualToString:@"sessions"]) return Sessions(rest);
        if ([cmd isEqualToString:@"where"] && rest.count) { Print(@{ @"place": PlaceJSON(MMWhereIs(KeyFor([rest[0] intValue]), nil, YES)) }); return 0; }
        if ([cmd isEqualToString:@"where-later"] && rest.count) {
            MMProcKey k = KeyFor([rest[0] intValue]);
            MMPlace *first = MMWhereIs(k, nil, NO);
            Wait(2);
            Print(@{ @"first": PlaceJSON(first), @"later": PlaceJSON(MMWhereIs(k, nil, NO)) });
            return 0;
        }
        if ([cmd isEqualToString:@"goto"] && rest.count) {
            NSString *err = nil;
            BOOL ok = MMGoTo(MMWhereIs(KeyFor([rest[0] intValue]), nil, YES), &err);
            Print(@{ @"ok": @(ok), @"error": err ?: @"" });
            return 0;
        }
        if ([cmd isEqualToString:@"events"]) return Events(rest.count ? [rest[0] doubleValue] : 2);
        if ([cmd isEqualToString:@"cache"]) return Cache();
        if ([cmd isEqualToString:@"run"]) return Run();
        if ([cmd isEqualToString:@"where-prune"] && rest.count) {
            pid_t pid = [rest[0] intValue];
            MMProcKey k = KeyFor(pid);
            MMPlace *w = MMWhereIs(k, nil, YES);
            BOOL before = MMWhereCached(k);
            kill(pid, SIGTERM);   // the fixture know.sh started for this check
            for (int i = 0; i < 40 && MMProcAlive(k); i++) usleep(50000);
            MMWhereIs(KeyFor(getpid()), nil, YES);   // any later call prunes
            Print(@{ @"kind": w ? PlaceJSON(w)[@"kind"] : @"none", @"cachedBefore": @(before), @"cachedAfter": @(MMWhereCached(k)) });
            return 0;
        }
        if ([cmd isEqualToString:@"sizer"] && rest.count > 1) {
            NSArray *paths = [rest subarrayWithRange:NSMakeRange(1, rest.count - 1)];
            if ([rest[0] isEqualToString:@"quick"]) {
                MMSize z = [MMSizer quick:paths[0]];
                Print(@{ @"allocated": @(z.allocated), @"freed": @(z.freedIfDeleted), @"files": @(z.files), @"errors": @(z.errors) });
            } else Print(@{ @"freed": @([MMSizer exact:paths]) });
            return 0;
        }
        fprintf(stderr, "usage: knowtool rows|agents|sessions|where|where-later|goto|events|cache|run\n");
        return 2;
    }
}
