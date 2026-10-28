// The Core wiring checks' tool. test/wire.sh builds it with all of Sources/Core and runs one mode per check.
// Every file it writes is under MINMACS_HOME, and every process it signals is one it started.
//   prefs                    MMSetPref and MMPref under MINMACS_HOME, and what the real domain holds after
//   serve <seconds>          serves core.sock with an echo verb until stdin closes or the time is up
//   ask <json> [timeout]     one request to core.sock
//   another                  MMAnotherInstanceRuns
//   start <sleep copy> <repo> [outside worktree]  MMCoreStart with a test expert, an exit, the repo index, then MMCoreStop
#import <Foundation/Foundation.h>
#import "Core/MMCore.h"
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;

static void Print(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingSortedKeys error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
    fflush(stdout);
}

/// Runs the main run loop until done says YES or seconds pass. YES when done.
static BOOL Spin(double seconds, BOOL (^done)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && end.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return done();
}

#pragma mark - The test expert

/// Reports one finding per fixture process it was told about, while the sample still lists it.
@interface WireExpert : NSObject <MMExpert>
@property (atomic) pid_t watched;
@property (atomic) NSInteger calls;
@property (atomic) BOOL slow;          // each build takes half a second, as one does on a loaded Mac
@end

@implementation WireExpert
- (NSString *)expertID { return @"wiretest"; }
- (NSString *)name { return @"Wire Test"; }
- (NSString *)symbol { return @"circle"; }
- (MMVerdictWords *)words { return [MMVerdictWords keep:@"keep" go:@"go" unsure:@"unsure"]; }
- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    self.calls++;
    if (self.slow) usleep(500000);
    pid_t pid = self.watched;
    MMProc *p = pid > 0 ? [facts.sample proc:pid] : nil;
    if (!p) return @[];
    MMProcKey k = p.key;
    return @[[MMFinding expert:@"wiretest" kind:@"proc" stableKey:@"fixture" build:^(MMFindingBuilder *b) {
        b.title = @"fixture";
        b.procs = @[[NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]];
    }]];
}
- (id<MMExpertPolicy>)policy { return nil; }
- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step { return nil; }
- (NSDictionary *)reviewFactsFor:(MMFinding *)f { return @{}; }
- (NSArray<id<MMRule>> *)rules { return @[]; }
- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s { return nil; }
- (MMMenuSpec *)menuFor:(MMSnapshot *)s { return nil; }
- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s { return nil; }
- (NSString *)badgeFor:(MMSnapshot *)s { return nil; }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return nil; }
- (BOOL)fieldEmptyIn:(MMSnapshot *)s { return NO; }
- (NSArray<MMVerbSpec *> *)verbs { return @[]; }
@end

#pragma mark - Modes

static int Prefs(void) {
    MMSetPref(@"wire.check", @42);
    MMSetPref(@"wire.gone", @"x");
    MMSetPref(@"wire.gone", nil);
    id real = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("wire.check"), CFSTR("no.guerrilla.minmacs")));
    NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:MMPrefsTarget()];
    Print(@{@"got": MMPref(@"wire.check") ?: @"nil", @"gone": MMPref(@"wire.gone") ?: @"nil", @"realDomain": real ?: @"nil",
            @"inFile": file[@"wire.check"] ?: @"nil", @"target": MMPrefsTarget()});
    return 0;
}

static int Serve(double seconds) {
    NSString *why = nil;
    MMCoreSocket *s = [MMCoreSocket serve:^NSDictionary *(NSDictionary *r) {
        return @{@"ok": @YES, @"echo": r[@"n"] ?: @"", @"pid": @(getpid()),
                 @"queue": @(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL))};
    } error:&why];
    if (!s) { Print(@{@"error": why ?: @"nil"}); return 1; }
    Print(@{@"serving": @YES, @"pid": @(getpid())});
    // Serves until stdin closes, as when the shell kills the writer, or until the time is up.
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        char buf[64];
        while (read(0, buf, sizeof buf) > 0) {}
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)));
    [s stop];
    return 0;
}

static int Ask(NSString *json, double timeout) {
    NSDictionary *req = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSDate *t0 = NSDate.date;
    NSDictionary *r = [MMCoreSocket ask:req ?: @{} timeout:timeout];
    Print(@{@"reply": r ?: @"none", @"ms": @((int)(-t0.timeIntervalSinceNow * 1000))});
    return 0;
}

static pid_t Spawn(NSString *path) {
    pid_t pid = 0;
    char *argv[] = { (char *)path.fileSystemRepresentation, "120", NULL };
    return posix_spawn(&pid, path.fileSystemRepresentation, NULL, NULL, argv, environ) == 0 ? pid : 0;
}

static int Start(NSString *sleepCopy, NSString *repoArg, NSString *outsideArg) {
    NSString *repo = repoArg.stringByStandardizingPath;   // as the worker reports paths
    WireExpert *e = [WireExpert new];
    pid_t kid = Spawn(sleepCopy);
    e.watched = kid;
    MMRegisterExpert(e);
    MMRegisterExpert(e);   // twice is the same as once
    NSDate *t0 = NSDate.date;
    MMCoreStart();
    MMCoreStart();         // safe to call twice
    NSMutableDictionary *out = [NSMutableDictionary new];
    out[@"experts"] = @(MMExperts().count);
    out[@"named"] = MMExpertNamed(@"wiretest") == e ? @"yes" : @"no";
    // The first snapshot arrives on main, with the fixture's finding and the fixture repo's worktree.
    __block NSInteger published = 0;
    id token = [MMGraph.shared observe:^(MMSnapshot *s) { published++; }];
    BOOL first = Spin(10, ^BOOL { MMSnapshot *s = MMGraph.shared.current; return s && [s findingsFor:@"wiretest"].count > 0; });
    MMSnapshot *s = MMGraph.shared.current;
    out[@"firstSnapshot"] = @(first);
    out[@"firstMs"] = @((int)(-t0.timeIntervalSinceNow * 1000));
    out[@"procsInSample"] = @(s.facts.sample.procs.count > 20);
    out[@"powerRead"] = @(s.facts.power != nil);
    // The repo index walks in the worker child; its notification asks for another rebuild.
    BOOL repoSeen = Spin(15, ^BOOL {
        for (MMWorktree *w in MMGraph.shared.current.facts.worktrees) if ([w.path isEqualToString:repo]) return YES;
        return NO;
    });
    out[@"repoInFacts"] = @(repoSeen);
    out[@"repo"] = repo;
    out[@"worktreeAt"] = [MMRepoIndex.shared worktreeAt:[repo stringByAppendingPathComponent:@"sub/dir"]].path ?: @"nil";
    // A linked worktree outside every root is not in the walk, so worktreeAt reads its .git file and commondir.
    if (outsideArg.length) {
        MMWorktree *w = [MMRepoIndex.shared worktreeAt:[outsideArg.stringByStandardizingPath stringByAppendingPathComponent:@"deep"]];
        out[@"outside"] = w ? [NSString stringWithFormat:@"%@|%@|%@", w.path, w.repo, w.branch ?: @"-"] : @"nil";
    }
    // core.sock answers ping and status while Core runs.
    NSDictionary *ping = [MMCoreSocket ask:@{@"verb": @"ping"} timeout:1];
    out[@"ping"] = ping[@"ok"] ?: @"none";
    out[@"pingPid"] = @([ping[@"pid"] intValue] == getpid());
    NSDictionary *status = [MMCoreSocket ask:@{@"verb": @"status"} timeout:1];
    out[@"statusExperts"] = status[@"experts"] ?: @[];
    out[@"unknownVerb"] = [MMCoreSocket ask:@{@"verb": @"no-such"} timeout:1][@"error"] ?: @"none";
    out[@"anotherInstance"] = @(MMAnotherInstanceRuns());
    // An exit of a watched process rebuilds at once, before the next 5-second pass.
    BOOL watchedOK = Spin(3, ^BOOL { return [MMGraph.shared.current findingsFor:@"wiretest"].count > 0; });
    out[@"watchedBeforeKill"] = @(watchedOK);
    usleep(300000);   // the snapshot observer has handed the key to kqueue
    NSDate *killed = NSDate.date;
    kill(kid, SIGTERM);   // the fixture this tool started
    BOOL gone = Spin(4, ^BOOL { return [MMGraph.shared.current findingsFor:@"wiretest"].count == 0; });
    out[@"exitRebuild"] = @(watchedOK && gone);
    out[@"exitMs"] = @((int)(-killed.timeIntervalSinceNow * 1000));
    int st; waitpid(kid, &st, 0);
    // A fresh read for one finding blocks, so it never runs on main.
    out[@"freshOnMain"] = [MMGraph.shared freshFactsFor:[MMFinding expert:@"wiretest" kind:@"x" stableKey:@"y" build:nil]] ? @"facts" : @"nil";
    __block MMFacts *fresh = nil;
    dispatch_semaphore_t got = dispatch_semaphore_create(0);
    dispatch_async(MMQueue(@"wiretest", @"fresh", QOS_CLASS_UTILITY), ^{
        fresh = [MMGraph.shared freshFactsFor:[MMFinding expert:@"wiretest" kind:@"x" stableKey:@"y" build:nil]];
        dispatch_semaphore_signal(got);
    });
    dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    out[@"freshOffMain"] = @(fresh.sample != nil && [fresh.sample.at compare:s.facts.sample.at] == NSOrderedDescending);
    out[@"published"] = @(published > 1);
    [MMGraph.shared stopObserving:token];
    // A build is running when Core stops, as the 5-second pass's build may be on a loaded Mac. It must not land after.
    e.slow = YES;
    NSInteger callsBefore = e.calls;
    [MMGraph.shared rebuild:@"wire: in flight at stop"];
    Spin(2, ^BOOL { return e.calls > callsBefore; });   // the slow build has started and sleeps in findingsFrom:
    out[@"buildInFlightAtStop"] = @(e.calls > callsBefore);
    MMCoreStop();
    NSDate *sampledAt = MMSenses.shared.latest.at;
    out[@"pingAfterStop"] = [MMCoreSocket ask:@{@"verb": @"ping"} timeout:0.3] ? @"answered" : @"none";
    out[@"socketFileAfterStop"] = @([NSFileManager.defaultManager fileExistsAtPath:MMCoreSocketPath()]);
    uint64_t gen = MMGraph.shared.latest.generation;
    Spin(6, ^BOOL { return NO; });
    out[@"stillBuildingAfterStop"] = @(MMGraph.shared.latest.generation != gen);
    out[@"stillSamplingAfterStop"] = @(![MMSenses.shared.latest.at isEqualToDate:sampledAt]);
    MMSnapshot *after = MMGraph.shared.current;
    out[@"publishedAfterStop"] = @(after.generation > gen);
    Print(out);
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (!NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length) { fprintf(stderr, "wire: set MINMACS_HOME\n"); return 2; }
        signal(SIGPIPE, SIG_IGN);
        NSString *mode = argc > 1 ? @(argv[1]) : @"";
        if ([mode isEqualToString:@"_walk"]) return MMWorkerChildMain();   // the worker child is this same binary
        if ([mode isEqualToString:@"prefs"]) return Prefs();
        if ([mode isEqualToString:@"serve"]) return Serve(argc > 2 ? atof(argv[2]) : 10);
        if ([mode isEqualToString:@"ask"] && argc > 2) return Ask(@(argv[2]), argc > 3 ? atof(argv[3]) : 0.2);
        if ([mode isEqualToString:@"another"]) { Print(@{@"another": @(MMAnotherInstanceRuns())}); return 0; }
        if ([mode isEqualToString:@"start"] && argc > 3) return Start(@(argv[2]), @(argv[3]), argc > 4 ? @(argv[4]) : nil);
        fprintf(stderr, "usage: wire prefs|serve|ask|another|start\n");
        return 2;
    }
}
