// The git checks' tool. It links all of Sources/Core and prints JSON. Every root it gets lies in $MINMACS_HOME.
// Usage: gittool <command> [args]
//   _walk                                 the worker child, as `minmacs _walk`
//   facts <root>                          walk, then the facts of every worktree and the index's counters
//   fresh <path>                          factsFor:wait:YES off main, and what main gets
//   watch <root> <file> <other>           cold scan, FSEvents on, one change to file: what ran, and sizes
//   bench <root> <file> <repo>            cold scan, warm full scan, one file change, one default-branch commit, timed
//   restart-a <root>                      cold scan with FSEvents on, then stop, which saves each root's event id
//   restart-b <root> <path>               a new process: FSEvents from the saved ids, a walk, and what git ran for
//   moves <root> <path> <branch>          FSEvents on, a branch switch and a lock in path: when the index shows each
#import <Foundation/Foundation.h>
#import "Core/Know/MMGit.h"
#import "Core/Runtime/MMWorker.h"
#import <sys/resource.h>

static void Print(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted error:nil];
    printf("%s\n", [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
}

static double Now(void) { return NSDate.date.timeIntervalSince1970; }

/// CPU seconds this process and its reaped children used so far: the git children count too.
static double CPU(void) {
    struct rusage a, b;
    getrusage(RUSAGE_SELF, &a); getrusage(RUSAGE_CHILDREN, &b);
    return a.ru_utime.tv_sec + a.ru_stime.tv_sec + b.ru_utime.tv_sec + b.ru_stime.tv_sec +
           (a.ru_utime.tv_usec + a.ru_stime.tv_usec + b.ru_utime.tv_usec + b.ru_stime.tv_usec) / 1e6;
}

static NSInteger Stat(NSString *k) { return MMRepoIndex.shared.stats[k].integerValue; }

/// Waits for the update passes that are marked now, and for those they queue, to finish.
static void Settle(void) {
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    [MMRepoIndex.shared updateFacts:^(NSUInteger ran) { dispatch_semaphore_signal(s); }];
    dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_SEC));
}

/// A full walk, then its update pass. Returns the seconds it took.
static double Scan(void) {
    double t0 = Now();
    NSInteger done = Stat(@"walksDone");
    [MMRepoIndex.shared refresh:nil];
    while (Stat(@"walksDone") <= done && Now() - t0 < 120) usleep(2000);
    Settle();
    return Now() - t0;
}

static MMWorktree *TreeAt(NSString *path) {
    NSString *p = path.stringByStandardizingPath;
    for (MMWorktree *w in MMRepoIndex.shared.worktrees) if ([w.path isEqualToString:p]) return w;
    return nil;
}

static NSDictionary *AllFacts(void) {
    NSMutableDictionary *out = [NSMutableDictionary new];
    for (MMWorktree *w in MMRepoIndex.shared.worktrees) {
        MMGitFacts *g = [MMRepoIndex.shared factsFor:w wait:NO];
        out[w.path] = g ? g.json : NSNull.null;
    }
    return out;
}

static void Append(NSString *file, NSString *line) {
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:file];
    [h seekToEndOfFile];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

/// Waits until the facts of w show dirty at least n, through wait NO reads only. Returns the seconds, or -1.
static double UntilDirty(MMWorktree *w, NSInteger n, double t0, double limit) {
    while (Now() - t0 < limit) {
        MMGitFacts *g = [MMRepoIndex.shared factsFor:w wait:NO];
        if (g.dirty >= n) return Now() - t0;
        usleep(5000);
    }
    return -1;
}

static void Drain(void) {
    // The caches write their files 0.2 seconds after a change. The next launch reads those files.
    usleep(1000000);
}

static int Facts(NSString *root) {
    MMRepoIndex.shared.roots = @[root.stringByStandardizingPath];
    Scan();
    Drain();
    Print(@{@"facts": AllFacts(), @"stats": MMRepoIndex.shared.stats});
    return 0;
}

static int Fresh(NSString *path) {
    MMWorktree *w = [MMRepoIndex.shared worktreeAt:path];
    __block MMGitFacts *g = nil;
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ g = [MMRepoIndex.shared factsFor:w wait:YES]; dispatch_semaphore_signal(s); });
    dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
    MMGitFacts *onMain = [MMRepoIndex.shared factsFor:w wait:YES];
    int st = 0;
    NSString *gitOnMain = MMGit(path, @[@"rev-parse", @"HEAD"], 5, &st);
    Drain();
    Print(@{@"fresh": g ? g.json : NSNull.null, @"waitOnMain": onMain ? @"facts" : @"nil",
            @"gitOnMain": gitOnMain ?: @"nil", @"gitOnMainStatus": @(st), @"stats": MMRepoIndex.shared.stats});
    return 0;
}

static int Watch(NSString *root, NSString *file, NSString *other) {
    MMRepoIndex *ix = MMRepoIndex.shared;
    ix.roots = @[root.stringByStandardizingPath];
    Scan();
    MMWorktree *w = [ix worktreeAt:file], *o = [ix worktreeAt:other];
    __block NSDictionary *sizeBefore = nil;
    dispatch_semaphore_t sized = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{   // wait YES never runs on main
        sizeBefore = [ix sizeFor:w wait:YES];
        [ix sizeFor:o wait:YES];
        dispatch_semaphore_signal(sized);
    });
    dispatch_semaphore_wait(sized, DISPATCH_TIME_FOREVER);
    [ix startWatching];
    usleep(1500000);   // the streams start
    NSInteger dirty = [ix factsFor:w wait:NO].dirty;
    NSDictionary<NSString *, NSNumber *> *before = ix.stats;
    double t0 = Now();
    Append(file, @"one more line\n");
    double took = UntilDirty(w, dirty + 1, t0, 10);
    usleep(300000);
    NSDictionary<NSString *, NSNumber *> *after = ix.stats;
    NSInteger walks = after[@"sizeWalks"].integerValue;
    NSDictionary *staleSize = [ix sizeFor:w wait:NO];   // the old size now, a walk queued
    [ix sizeFor:o wait:NO];                              // still fresh: no walk
    usleep(300000);
    NSInteger walksAfter = ix.stats[@"sizeWalks"].integerValue;
    // git add writes the worktree's index in its git dir: its fingerprint moves, and no walk starts.
    NSDictionary<NSString *, NSNumber *> *beforeAdd = ix.stats;
    dispatch_semaphore_t added = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        MMGit(w.path, @[@"add", file.lastPathComponent], 10, NULL);
        dispatch_semaphore_signal(added);
    });
    dispatch_semaphore_wait(added, DISPATCH_TIME_FOREVER);
    usleep(1500000);
    Settle();
    NSDictionary<NSString *, NSNumber *> *afterAdd = ix.stats;
    [ix stopWatching];
    Drain();
    Print(@{@"seconds": @(took), @"dirtyBefore": @(dirty), @"dirtyAfter": @([ix factsFor:w wait:NO].dirty),
            @"statusRuns": @(after[@"statusRuns"].integerValue - before[@"statusRuns"].integerValue),
            @"historyRuns": @(after[@"historyRuns"].integerValue - before[@"historyRuns"].integerValue),
            @"otherDirty": @([ix factsFor:o wait:NO].dirty),
            @"sizeFiles": sizeBefore[@"files"] ?: @(-1), @"staleSizeFiles": staleSize[@"files"] ?: @(-1),
            @"sizeWalksQueued": @(walksAfter - walks),
            @"addStatusRuns": @(afterAdd[@"statusRuns"].integerValue - beforeAdd[@"statusRuns"].integerValue),
            @"addWalks": @(afterAdd[@"walks"].integerValue - beforeAdd[@"walks"].integerValue)});
    return 0;
}

static int Bench(NSString *root, NSString *file, NSString *repo) {
    MMRepoIndex *ix = MMRepoIndex.shared;
    ix.roots = @[root.stringByStandardizingPath];
    NSMutableDictionary *out = [NSMutableDictionary new];
    double c0 = CPU();
    out[@"coldSeconds"] = @(Scan());
    out[@"coldCPU"] = @(CPU() - c0);
    out[@"worktrees"] = @(ix.worktrees.count);
    out[@"coldStats"] = ix.stats;
    NSInteger known = 0;
    for (MMWorktree *w in ix.worktrees) if ([ix factsFor:w wait:NO]) known++;
    out[@"withFacts"] = @(known);

    // Warm: a full walk that reads every fingerprint again and runs git for none.
    NSDictionary<NSString *, NSNumber *> *s0 = ix.stats;
    c0 = CPU();
    out[@"warmFullSeconds"] = @(Scan());
    out[@"warmFullCPU"] = @(CPU() - c0);
    out[@"warmFullGitRuns"] = @(ix.stats[@"gitRuns"].integerValue - s0[@"gitRuns"].integerValue);
    out[@"warmFullChecked"] = @(ix.stats[@"fingerprintReads"].integerValue - s0[@"fingerprintReads"].integerValue);

    // Warm: one file changes. FSEvents marks its worktree, and one pass runs git for it alone.
    [ix startWatching];
    usleep(1500000);
    MMWorktree *w = [ix worktreeAt:file];
    NSInteger dirty = [ix factsFor:w wait:NO].dirty;
    s0 = ix.stats;
    c0 = CPU();
    double t0 = Now();
    Append(file, @"bench change\n");
    out[@"changeSeconds"] = @(UntilDirty(w, dirty + 1, t0, 10));
    usleep(200000);
    out[@"changeCPU"] = @(CPU() - c0);
    out[@"changePassMs"] = ix.stats[@"lastUpdateMs"];
    out[@"changeRan"] = @(ix.stats[@"statusRuns"].integerValue - s0[@"statusRuns"].integerValue);
    out[@"changeGitRuns"] = @(ix.stats[@"gitRuns"].integerValue - s0[@"gitRuns"].integerValue);
    [ix stopWatching];

    // The default branch of one repo gains a commit: its worktrees' histories run again, with one new patch id.
    s0 = ix.stats;
    int st = 0;
    __block NSString *made = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [@"default moved\n" writeToFile:[repo stringByAppendingPathComponent:@"moved.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        int s1 = 0;
        MMGit(repo, @[@"add", @"moved.txt"], 10, &s1);
        made = MMGit(repo, @[@"-c", @"user.name=fixture", @"-c", @"user.email=fixture@example.invalid", @"commit", @"-q", @"-m", @"moved"], 10, &s1);
        dispatch_semaphore_signal(sem);
    });
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    (void)st; (void)made;
    c0 = CPU();
    t0 = Now();
    [ix invalidate:[NSSet setWithObject:[repo stringByAppendingPathComponent:@".git"]] subtrees:NO];
    Settle();
    out[@"defaultMovedSeconds"] = @(Now() - t0);
    out[@"defaultMovedCPU"] = @(CPU() - c0);
    out[@"defaultMovedHistories"] = @(ix.stats[@"historyRuns"].integerValue - s0[@"historyRuns"].integerValue);
    out[@"defaultMovedPatchIds"] = @(ix.stats[@"patchIdsComputed"].integerValue - s0[@"patchIdsComputed"].integerValue);
    out[@"defaultMovedSquashChecks"] = @(ix.stats[@"squashChecks"].integerValue - s0[@"squashChecks"].integerValue);
    struct rusage ru; getrusage(RUSAGE_SELF, &ru);
    out[@"peakRSSMB"] = @(ru.ru_maxrss / 1048576.0);
    NSMutableDictionary *kinds = [NSMutableDictionary new];
    for (MMWorktree *x in ix.worktrees) {
        NSString *k = [ix factsFor:x wait:NO].json[@"merged"] ?: @"unknown";
        kinds[k] = @([kinds[k] integerValue] + 1);
    }
    out[@"merged"] = kinds;
    Drain();
    Print(out);
    return 0;
}

static int RestartA(NSString *root) {
    MMRepoIndex *ix = MMRepoIndex.shared;
    ix.roots = @[root.stringByStandardizingPath];
    [ix startWatching];
    Scan();
    usleep(1000000);
    [ix stopWatching];
    Drain();
    Print(@{@"worktrees": @(ix.worktrees.count), @"stats": ix.stats});
    return 0;
}

static int RestartB(NSString *root, NSString *path) {
    MMRepoIndex *ix = MMRepoIndex.shared;
    ix.roots = @[root.stringByStandardizingPath];
    [ix startWatching];   // replays from each root's saved event id
    Scan();
    usleep(1500000);      // the replay lands within the stream's latency
    Settle();
    MMWorktree *w = TreeAt(path);
    NSDictionary *g = [ix factsFor:w wait:NO].json;
    [ix stopWatching];
    Drain();
    Print(@{@"stats": ix.stats, @"facts": g ?: NSNull.null, @"worktrees": @(ix.worktrees.count)});
    return 0;
}

/// Off main, as every git run must be.
static void GitOff(NSString *dir, NSArray *args) {
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ MMGit(dir, args, 10, NULL); dispatch_semaphore_signal(s); });
    dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
}

/// A branch switch and a lock in one worktree, with FSEvents on: how long until the index's worktree shows each,
/// and how many walks ran meanwhile. A known repo's git dir starts no walk, so the update pass must carry both.
static int Moves(NSString *root, NSString *path, NSString *branch) {
    MMRepoIndex *ix = MMRepoIndex.shared;
    ix.roots = @[root.stringByStandardizingPath];
    Scan();
    [ix startWatching];
    usleep(1500000);
    NSInteger walks = Stat(@"walks");
    double t0 = Now(), branchAt = -1, lockAt = -1;
    GitOff(path, @[@"checkout", @"-q", @"-b", branch]);
    while (Now() - t0 < 10) {
        if ([TreeAt(path).branch isEqualToString:branch]) { branchAt = Now() - t0; break; }
        usleep(5000);
    }
    double t1 = Now();
    GitOff(path, @[@"worktree", @"lock", @"--reason", @"fixture", path]);
    while (Now() - t1 < 10) {
        if (TreeAt(path).locked) { lockAt = Now() - t1; break; }
        usleep(5000);
    }
    [ix stopWatching];
    Drain();
    Print(@{@"branchSeconds": @(branchAt), @"lockSeconds": @(lockAt), @"walks": @(Stat(@"walks") - walks),
            @"branch": TreeAt(path).branch ?: NSNull.null, @"factsBranch": [ix factsFor:TreeAt(path) wait:NO].branch ?: NSNull.null});
    return 0;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: gittool <command> [args]\n"); return 2; }
        NSString *cmd = @(argv[1]);
        NSMutableArray<NSString *> *a = [NSMutableArray new];
        for (int i = 2; i < argc; i++) [a addObject:@(argv[i])];
        if ([cmd isEqualToString:@"_walk"]) return MMWorkerChildMain();
        if ([cmd isEqualToString:@"facts"] && a.count == 1) return Facts(a[0]);
        if ([cmd isEqualToString:@"fresh"] && a.count == 1) return Fresh(a[0]);
        if ([cmd isEqualToString:@"watch"] && a.count == 3) return Watch(a[0], a[1], a[2]);
        if ([cmd isEqualToString:@"bench"] && a.count == 3) return Bench(a[0], a[1], a[2]);
        if ([cmd isEqualToString:@"restart-a"] && a.count == 1) return RestartA(a[0]);
        if ([cmd isEqualToString:@"restart-b"] && a.count == 2) return RestartB(a[0], a[1]);
        if ([cmd isEqualToString:@"moves"] && a.count == 3) return Moves(a[0], a[1], a[2]);
        fprintf(stderr, "unknown command\n");
        return 2;
    }
}
