// Checks for the Performance tab's model, Core/MMPerformance.h. test/performance.sh builds this with all of Sources/Core.
// Every fact is a fixture: a fake sample, fake worktrees, git facts, sessions and agents, and five fake experts whose
// findings, policies and actions are data. No action runs, no process starts, and the only folders it reads are the
// ones it made inside $MINMACS_HOME. The gains rows go to the table in $MINMACS_HOME.
// Usage: performance <fixture dir> model | calm | lookback | bench
// Prints one line per check, CHECK<tab>name<tab>want<tab>got, or info<tab>text.
#import <mach/mach.h>
#import "Core/MMCore.h"

static void T(NSString *name, id want, id got) {
    printf("CHECK\t%s\t%s\t%s\n", name.UTF8String, [want description].UTF8String ?: "", [got description].UTF8String ?: "(nil)");
    fflush(stdout);
}
static void Info(NSString *s) { printf("info\t%s\n", s.UTF8String); fflush(stdout); }
static NSString *YN(BOOL b) { return b ? @"yes" : @"no"; }
static const uint64_t MB = 1ull << 20, GB = 1ull << 30;
static NSValue *V(pid_t pid, uint64_t start) { MMProcKey k = { pid, start }; return [NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]; }

#pragma mark - Fake facts

@interface TProc : NSObject
@property pid_t pid, ppid; @property uid_t uid; @property uint64_t startSec, footprint; @property NSString *name;
@property double cpuPercent, energyRank;
@end
@implementation TProc
- (MMProcKey)key { return (MMProcKey){ self.pid, self.startSec }; }
@end

@interface TSample : NSObject
@property NSDate *at; @property uint64_t generation;
@property NSDictionary<NSNumber *, TProc *> *procs;
@property NSDictionary<NSNumber *, NSArray<NSNumber *> *> *children;
@end
@implementation TSample
- (id)proc:(pid_t)pid { return self.procs[@(pid)]; }
- (NSArray *)argsOf:(pid_t)pid { return @[]; }
- (NSString *)cwdOf:(pid_t)pid { return nil; }
- (NSArray *)childrenOf:(pid_t)pid { return self.children[@(pid)] ?: @[]; }
- (NSArray *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops { return @[]; }
- (NSArray *)treeOf:(pid_t)pid limit:(NSUInteger)max {
    NSMutableArray *out = [NSMutableArray arrayWithObject:@(pid)];
    for (NSUInteger i = 0; i < out.count && out.count < max; i++) [out addObjectsFromArray:self.children[out[i]] ?: @[]];
    return out;
}
- (double)treeCPU:(pid_t)pid { return 0; }
- (uint64_t)treeFootprint:(pid_t)pid { uint64_t n = 0; for (NSNumber *p in [self treeOf:pid limit:500]) n += self.procs[p].footprint; return n; }
- (const MMSocket *)sockets:(NSUInteger *)count { if (count) *count = 0; return NULL; }
- (NSArray *)socketsOf:(pid_t)pid { return @[]; }
- (BOOL)unchanged:(pid_t)pid { return YES; }
@end

@interface TWorktree : NSObject
@property NSString *path, *repo, *branch, *lockReason, *makerSession; @property BOOL isMain, locked, missing; @property MMWorktreeMaker maker;
@end
@implementation TWorktree @end

@interface TGit : NSObject
@property NSString *branch, *head, *defaultBranch, *upstream; @property MMMergeKind merged;
@property NSInteger dirty, untracked, stashes, notInDefault, unpushed, ahead, behind; @property BOOL onRemote, upstreamGone;
@property NSDate *lastCommit;
@end
@implementation TGit
- (NSDictionary *)json { return @{@"merged": self.merged ? @"ancestor" : @"none"}; }
@end

@interface TSession : NSObject
@property NSString *agent, *sessionID, *title, *cwd, *branch, *transcript, *liveStatus; @property NSDate *started, *lastActive;
@property pid_t pid; @property BOOL stillWorking;
@end
@implementation TSession @end

@interface TAgent : NSObject
@property id row; @property NSString *harnessID, *sessionID, *cwd, *surface, *why; @property MMProcKey key;
@property MMAgentState state; @property MMAgentSignal signal; @property double treeCPU; @property uint64_t treeFootprint;
@property NSArray *hosted;
@end
@implementation TAgent @end

#pragma mark - Fake experts

@interface TAction : NSObject <MMAction>
@property MMFinding *finding;
@end
@implementation TAction
- (NSString *)kind { return self.finding.proposal.verb ?: @"stop"; }
- (NSString *)recheck { return nil; }
- (NSString *)dryRun { return @"fixture"; }
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error { if (error) *error = @"a fixture never acts"; return NO; }
@end

/// Keeps a finding whose facts say keep.
@interface TPolicy : NSObject <MMExpertPolicy>
@end
@implementation TPolicy
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts { return f.facts[@"keep"]; }
- (NSString *)reviewKeeps:(MMFinding *)f review:(MMReview *)r { return nil; }
@end

static NSMutableDictionary<NSString *, NSArray<MMFinding *> *> *gFindings;   // by expert
static NSMutableDictionary<NSString *, NSArray<MMFinding *> *> *gParts;      // helper and tabs findings by worktree path

@interface TExpert : NSObject <MMExpert>
@property NSString *eid;
@end
@implementation TExpert
- (NSString *)expertID { return self.eid; }
- (NSString *)name { return self.eid; }
- (NSString *)symbol { return @"circle"; }
- (MMVerdictWords *)words { return nil; }
- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts { return gFindings[self.eid] ?: @[]; }
- (id<MMExpertPolicy>)policy { static TPolicy *p; static dispatch_once_t once; dispatch_once(&once, ^{ p = [TPolicy new]; }); return p; }
- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step {
    if (!f.proposal) return nil;
    TAction *a = [TAction new]; a.finding = f; return a;
}
- (NSDictionary *)reviewFactsFor:(MMFinding *)f { return @{}; }
- (NSArray<id<MMRule>> *)rules { return @[]; }
- (MMReviewRequest *)reviewRequest:(NSString *)trigger snapshot:(MMSnapshot *)s { return nil; }
- (MMMenuSpec *)menuFor:(MMSnapshot *)s { return nil; }
- (MMCardSpec *)cardFor:(MMFinding *)f snapshot:(MMSnapshot *)s { return nil; }
- (NSString *)badgeFor:(MMSnapshot *)s { return nil; }
- (NSString *)accessibilityStateFor:(MMSnapshot *)s { return nil; }
- (BOOL)fieldEmptyIn:(MMSnapshot *)s { return NO; }
- (NSArray<MMVerbSpec *> *)verbs { return @[]; }
- (NSArray<MMWrapUpPart *> *)wrapUpParts:(MMWrapUpSubject *)subject snapshot:(MMSnapshot *)s {
    NSMutableArray *out = [NSMutableArray new];
    MMWrapUpPart *(^part)(MMWrapUpStep, MMFinding *) = ^(MMWrapUpStep step, MMFinding *f) {
        TAction *a = [TAction new]; a.finding = f;
        return [MMWrapUpPart step:step expert:self.eid title:f.title action:a policy:[self policy]];
    };
    if ([self.eid isEqualToString:@"locohost"])
        for (MMFinding *f in gFindings[@"locohost"]) { if ([subject holds:f.path]) [out addObject:part(MMWrapUpServers, f)]; }
    if ([self.eid isEqualToString:@"noonoo"])
        for (MMFinding *f in gFindings[@"noonoo"]) { if ([subject holds:f.path]) [out addObject:part(MMWrapUpCaches, f)]; }
    if ([self.eid isEqualToString:@"workforest"])
        for (MMFinding *f in gFindings[@"workforest"]) { if ([f.path isEqualToString:subject.path]) [out addObject:part(MMWrapUpWorktree, f)]; }
    if ([self.eid isEqualToString:@"minmacs"])
        for (MMFinding *f in gParts[subject.path]) [out addObject:part([f.kind isEqualToString:@"helper"] ? MMWrapUpHelpers : MMWrapUpTabs, f)];
    return out;
}
@end

#pragma mark - The fixture world

static NSString *gDir;
static NSMutableDictionary<NSNumber *, TProc *> *gProcs;
static NSMutableDictionary<NSNumber *, NSArray *> *gChildren;

static NSString *Dir(NSString *name) {
    NSString *p = [gDir stringByAppendingPathComponent:name];
    [NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
    char real[PATH_MAX];
    return realpath(p.fileSystemRepresentation, real) ? @(real) : p;
}
static void Proc(pid_t pid, uint64_t bytes) {
    TProc *p = [TProc new]; p.pid = pid; p.startSec = 7; p.footprint = bytes; p.uid = getuid(); p.name = @"fixture";
    gProcs[@(pid)] = p;
}

static MMFinding *Finding(NSString *expert, NSString *kind, NSString *key, NSString *title, NSString *path, pid_t pid,
                          uint64_t ram, uint64_t disk, MMProposal *proposal, NSDictionary *facts) {
    return [MMFinding expert:expert kind:kind stableKey:key build:^(MMFindingBuilder *b) {
        b.title = title; b.path = path; b.instanceKey = pid ? [NSString stringWithFormat:@"%d:7", pid] : key;
        if (pid) b.procs = @[V(pid, 7)];
        b.cost = (MMCost){ .ramBytes = ram, .cpuPercent = -1, .diskFreed = disk };
        b.proposal = proposal; b.facts = facts ?: @{};
    }];
}
static MMProposal *P(NSString *verb, MMReversibility r) { return [MMProposal verb:verb title:verb reversibility:r]; }

static NSMutableArray *gTrees, *gSessions, *gAgents;
static NSMutableDictionary *gGit;

static void Tree(NSString *path, BOOL main, MMMergeKind merged) {
    TWorktree *w = [TWorktree new]; w.path = path; w.repo = Dir(@"repo"); w.branch = path.lastPathComponent; w.isMain = main;
    [gTrees addObject:w];
    TGit *g = [TGit new]; g.merged = merged; g.head = @"abc123"; g.branch = w.branch; g.defaultBranch = @"main";
    gGit[path] = g;
}
static void Session(NSString *cwd) {
    TSession *e = [TSession new]; e.agent = @"claude-code"; e.sessionID = [NSUUID UUID].UUIDString; e.cwd = cwd; e.title = @"fixture";
    e.started = [NSDate dateWithTimeIntervalSinceNow:-7200]; e.lastActive = [NSDate dateWithTimeIntervalSinceNow:-3600];
    [gSessions addObject:e];
}
static void Agent(pid_t pid, MMAgentState st, uint64_t bytes) {
    TAgent *a = [TAgent new]; a.harnessID = @"claude-code"; a.sessionID = [NSString stringWithFormat:@"s-%d", pid];
    a.cwd = Dir(@"elsewhere"); a.key = (MMProcKey){ pid, 7 }; a.state = st; a.treeFootprint = bytes; a.hosted = @[];
    [gAgents addObject:a];
}

static void Reset(void) {
    gFindings = [NSMutableDictionary new]; gParts = [NSMutableDictionary new];
    gProcs = [NSMutableDictionary new]; gChildren = [NSMutableDictionary new];
    gTrees = [NSMutableArray new]; gSessions = [NSMutableArray new]; gAgents = [NSMutableArray new]; gGit = [NSMutableDictionary new];
}

static MMSnapshot *Snapshot(uint64_t diskTotal, uint64_t diskFree, NSInteger pressure) {
    TSample *sample = [TSample new]; sample.at = NSDate.date; sample.generation = 1; sample.procs = gProcs; sample.children = gChildren;
    MMPower *power = MMPowerFrom(@{@"diskTotal": @(diskTotal), @"diskFree": @(diskFree), @"memoryPressure": @(pressure), @"onAC": @YES});
    MMFacts *facts = [MMFacts generation:1 sample:(MMSample *)sample power:power agents:(NSArray *)gAgents sessions:(NSArray *)gSessions
                               worktrees:(NSArray *)gTrees clutter:@[] git:(NSDictionary *)gGit];
    return [MMSnapshot snapshotFrom:facts experts:MMExperts() reviews:nil holds:nil];
}

static MMHistoryView *Hour(uint64_t used) {
    MMHistory *h = [MMHistory new];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    [h noteMacCPU:10 memoryUsed:used diskFree:0 at:now];
    return [h viewAt:now];
}

static void Register(void) {
    for (NSString *e in @[@"locohost", @"minmacs", @"workforest", @"noonoo", @"insomnia"]) { TExpert *x = [TExpert new]; x.eid = e; MMRegisterExpert(x); }
}

/// The busy world: two finished worktrees, servers, agents, apps, a helper and tabs left behind, and clutter.
static void Busy(void) {
    Reset();
    NSString *w1 = Dir(@"trees/w1"), *w2 = Dir(@"trees/w2"), *w3 = Dir(@"repo"), *w4 = Dir(@"trees/w4"), *lib = Dir(@"library");
    Tree(w1, NO, MMMergedSquash); Tree(w2, NO, MMMergedAncestor); Tree(w3, YES, MMMergedNone); Tree(w4, NO, MMMergedNone);
    Session(w1);   // w1 is a finished workstream; w2 had no session, so it is a merged worktree with no Wrap Up
    Proc(70001, 300 * MB); Proc(70002, 512 * MB); Proc(70003, 100 * MB);
    Proc(70010, 388 * MB); Proc(70011, 200 * MB); Proc(70020, 1536 * MB); Proc(70021, 3 * GB); Proc(70030, 64 * MB);
    gChildren[@70010] = @[@70002];   // the waiting agent started the server on :3001
    Agent(70010, MMAgentWaiting, 900 * MB); Agent(70011, MMAgentWorking, 200 * MB);
    gFindings[@"locohost"] = @[
        Finding(@"locohost", @"server", @"w1#dev", @":3000 vite w1", w1, 70001, 300 * MB, 0, P(@"stop", MMReversibleRestart), nil),
        Finding(@"locohost", @"server", @"app#dev", @":3001 next app", Dir(@"app"), 70002, 512 * MB, 0, P(@"stop", MMReversibleRestart), nil),
        Finding(@"locohost", @"server", @"db", @":5432 postgres", Dir(@"db"), 70003, 100 * MB, 0, P(@"stop", MMReversibleRestart), @{@"keep": @"in use"})];
    gFindings[@"minmacs"] = @[
        Finding(@"minmacs", @"agent", @"claude-code:s-70010", @"Claude Code", nil, 70010, 900 * MB, 0, nil, nil),
        Finding(@"minmacs", @"agent", @"claude-code:s-70011", @"Claude Code", nil, 70011, 200 * MB, 0, nil, nil),
        Finding(@"minmacs", @"app", @"com.example.chat", @"Chat", nil, 70020, 1536 * MB, 0, P(@"quit", MMReversibleRelaunch), nil),
        Finding(@"minmacs", @"app", @"com.example.editor", @"Editor", nil, 70021, 3 * GB, 0, nil, nil),
        Finding(@"minmacs", @"app", @"com.example.browser", @"Browser", nil, 0, 0, 0, P(@"trim", MMReversibleRelaunch), nil)];
    gParts[w1] = @[
        Finding(@"minmacs", @"helper", [w1 stringByAppendingString:@"#chrome-headless"], @"chrome-headless", w1, 70030, 64 * MB, 0,
                P(@"stop", MMReversibleRestart), nil),
        Finding(@"minmacs", @"tabs", [w1 stringByAppendingString:@"#com.example.browser"], @"Browser", nil, 0, 0, 0,
                P(@"close-tabs", MMReversibleRelaunch), @{@"urls": @[@"http://localhost:3000/", @"http://localhost:3000/a", @"http://127.0.0.1:3000/b"]})];
    gFindings[@"workforest"] = @[
        Finding(@"workforest", @"worktree", w1, @"repo/w1", w1, 0, 0, 2 * GB, P(@"remove", MMReversibleRestart), nil),
        Finding(@"workforest", @"worktree", w2, @"repo/w2", w2, 0, 0, 5 * GB, P(@"remove", MMReversibleRestart), nil),
        Finding(@"workforest", @"worktree", w3, @"repo", w3, 0, 0, 10 * GB, nil, nil),
        Finding(@"workforest", @"worktree", w4, @"repo/w4", w4, 0, 0, 1 * GB, P(@"remove", MMReversibleRestart), nil)];
    gFindings[@"noonoo"] = @[
        Finding(@"noonoo", @"clutter", @"node_modules:w1", @"node_modules in w1", [w1 stringByAppendingPathComponent:@"node_modules"], 0, 0,
                1229 * MB, P(@"remove", MMReversibleTrash), nil),
        Finding(@"noonoo", @"clutter", @"node_modules:w2", @"node_modules in w2", [w2 stringByAppendingPathComponent:@"node_modules"], 0, 0,
                512 * MB, P(@"remove", MMReversibleTrash), nil),
        Finding(@"noonoo", @"clutter", @"derived-data", @"DerivedData", [lib stringByAppendingPathComponent:@"DerivedData"], 0, 0,
                14 * GB, P(@"remove", MMReversibleTrash), nil),
        Finding(@"noonoo", @"clutter", @"pnpm-store", @"pnpm store", [lib stringByAppendingPathComponent:@"pnpm"], 0, 0,
                6 * GB, P(@"clean", MMReversibleToolCommand), nil),
        Finding(@"noonoo", @"clutter", @"trash", @"The Trash", [lib stringByAppendingPathComponent:@"Trash"], 0, 0, 3 * GB, nil, nil)];
    gFindings[@"insomnia"] = @[Finding(@"insomnia", @"lid", @"override", @"Lid override", nil, 0, 0, 0, nil, nil)];
}

#pragma mark - Checks

static NSArray<MMPerformanceRow *> *AllRows(MMPerformance *p) {
    NSMutableArray *a = [NSMutableArray new];
    for (MMPerformanceGroup *g in [p.memoryGroups arrayByAddingObjectsFromArray:p.diskGroups]) [a addObjectsFromArray:g.rows];
    return a;
}
static uint64_t Sum(NSDictionary<NSString *, NSNumber *> *d) { uint64_t n = 0; for (NSNumber *v in d.allValues) n += v.unsignedLongLongValue; return n; }
static NSString *Keys(NSArray *objs) { return [[objs valueForKey:@"key"] componentsJoinedByString:@","]; }
static NSString *Words(id j) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:NSJSONWritingSortedKeys error:nil];
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}
static void Strings(id j, NSMutableArray *keys, NSMutableArray *values) {
    if ([j isKindOfClass:NSDictionary.class]) for (NSString *k in j) { [keys addObject:k]; Strings(j[k], keys, values); }
    else if ([j isKindOfClass:NSArray.class]) for (id x in j) Strings(x, keys, values);
    else if ([j isKindOfClass:NSString.class]) [values addObject:j];
}
static BOOL NamesLid(NSString *s) {
    return [s rangeOfString:@"\\blid\\b" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound;
}

static void Model(void) {
    Busy();
    MMSnapshot *s = Snapshot(1000 * GB, 300 * GB, 1);
    __block MMPerformance *p;
    dispatch_sync(MMQueue(@"perftest", @"build", QOS_CLASS_USER_INITIATED), ^{ p = [MMPerformance from:s history:Hour(8 * GB) lookBack:nil]; });
    NSDictionary *j = p.json;

    // The ring.
    T(@"performance: memory total is the Mac's physical memory", @(NSProcessInfo.processInfo.physicalMemory), @(p.memory.total));
    T(@"performance: memory used is the Mac ring's newest minute", @(8 * GB), @(p.memory.used));
    T(@"performance: disk total and used come from MMPower", @"1000 700", [NSString stringWithFormat:@"%llu %llu", p.disk.total / GB, p.disk.used / GB]);
    T(@"performance: memory parts in ring order, other last", @"servers,agents,apps,helpers,other", [p.memory.order componentsJoinedByString:@","]);
    T(@"performance: disk parts in ring order, other last", @"worktrees,clutter,other", [p.disk.order componentsJoinedByString:@","]);
    T(@"performance: memory parts and other add up to memory used", @(p.memory.used), @(Sum(p.memory.parts)));
    uint64_t holders = Sum(p.memory.parts) - [p.memory.parts[MMPerformanceOther] unsignedLongLongValue];
    T(@"performance: the holder parts add up to no more than memory used", @"yes", YN(holders <= p.memory.used));
    T(@"performance: disk parts and other add up to disk used", @(p.disk.used), @(Sum(p.disk.parts)));
    T(@"performance: a process counts once: the server an agent started counts in servers only", @"912 588",
      [NSString stringWithFormat:@"%llu %llu", [p.memory.parts[MMPerformanceServers] unsignedLongLongValue] / MB,
       [p.memory.parts[MMPerformanceAgents] unsignedLongLongValue] / MB]);
    T(@"performance: helpers and apps by their processes", @"64 4608",
      [NSString stringWithFormat:@"%llu %llu", [p.memory.parts[MMPerformanceHelpers] unsignedLongLongValue] / MB,
       [p.memory.parts[MMPerformanceApps] unsignedLongLongValue] / MB]);
    T(@"performance: a cache inside a worktree counts in clutter, not twice", @"16 24",
      [NSString stringWithFormat:@"%llu %llu", [p.disk.parts[MMPerformanceWorktrees] unsignedLongLongValue] / GB,
       [p.disk.parts[MMPerformanceClutter] unsignedLongLongValue] / GB]);
    T(@"performance: nothing was cut", @"0 0", [NSString stringWithFormat:@"%llu %llu", p.memory.cut, p.disk.cut]);
    // Memory and disk are never summed: no number in the JSON equals memory plus disk.
    NSString *w = Words(j);
    uint64_t sums[] = { p.memory.used + p.disk.used, p.memory.total + p.disk.total };
    BOOL summed = NO;
    for (int i = 0; i < 2; i++) if ([w rangeOfString:[NSString stringWithFormat:@":%llu", sums[i]]].location != NSNotFound) summed = YES;
    for (MMPerformanceFix *f in p.fixes)
        if (f.memoryBack && f.diskBack && [w rangeOfString:[NSString stringWithFormat:@":%llu", f.memoryBack + f.diskBack]].location != NSNotFound) summed = YES;
    T(@"performance: memory and disk are never summed into one number", @"no", YN(summed));
    T(@"performance: the ring keeps memory and disk apart", @"disk memory", [[[j[@"ring"] allKeys] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]);

    // The sides.
    T(@"performance: memory groups in 132-a's order", @"servers,agents,apps,tabs,helpers", Keys(p.memoryGroups));
    T(@"performance: disk groups in 132-a's order", @"worktrees,clutter", Keys(p.diskGroups));
    NSMutableArray *folds = [NSMutableArray new];
    for (MMPerformanceGroup *g in [p.memoryGroups arrayByAddingObjectsFromArray:p.diskGroups]) [folds addObject:@(g.fold)];
    T(@"performance: each group carries 132-a's fold count", @"6,1,2,0,0,12,10", [folds componentsJoinedByString:@","]);
    T(@"performance: the rows of each group", @"3 2 3 1 1 4 5", ({
        NSMutableArray *n = [NSMutableArray new];
        for (MMPerformanceGroup *g in [p.memoryGroups arrayByAddingObjectsFromArray:p.diskGroups]) [n addObject:@(g.rows.count)];
        [n componentsJoinedByString:@" "]; }));
    BOOL sorted = YES, one = YES;
    NSSet *rowKeys = [NSSet setWithArray:@[@"expert", @"findingID", @"group", @"key", @"name", @"needsYou", @"number", @"unit"]];
    for (MMPerformanceGroup *g in [p.memoryGroups arrayByAddingObjectsFromArray:p.diskGroups]) {
        for (NSUInteger i = 1; i < g.rows.count; i++) if (g.rows[i - 1].number < g.rows[i].number) sorted = NO;
        for (MMPerformanceRow *r in g.rows) {
            NSDictionary *rj = r.json;
            NSUInteger nums = 0;
            for (NSString *k in rj) if ([rj[k] isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)rj[k]) != CFBooleanGetTypeID()) nums++;
            if (nums != 1 || ![[NSSet setWithArray:rj.allKeys] isEqualToSet:rowKeys]) one = NO;
        }
    }
    T(@"performance: rows are biggest first in every group", @"yes", YN(sorted));
    T(@"performance: each row has one number", @"yes", YN(one));
    T(@"performance: servers biggest first", @":3001 next app,:3000 vite w1,:5432 postgres", [[p.memoryGroups[0].rows valueForKey:@"name"] componentsJoinedByString:@","]);
    MMPerformanceRow *tabs = p.memoryGroups[3].rows.firstObject;
    T(@"performance: a tabs row counts its tabs", @"3 tabs", [NSString stringWithFormat:@"%llu %@", tabs.number, tabs.json[@"unit"]]);
    T(@"performance: the agent that waits needs you, and only it", @"1 yes no", [NSString stringWithFormat:@"%ld %@ %@", (long)p.needsYou,
      YN(p.memoryGroups[1].rows[0].needsYou), YN(p.memoryGroups[1].rows[1].needsYou)]);
    BOOL links = YES;
    for (MMPerformanceRow *r in AllRows(p)) if (![r.findingID hasPrefix:[r.expert stringByAppendingString:@":"]]) links = NO;
    T(@"performance: each row names the finding it comes from", @"yes", YN(links));
    T(@"performance: Insomnia's finding is no row", @"no", YN([p row:@"insomnia:lid:override"] != nil));

    // The fixes.
    T(@"performance: one fix per Wrap Up and per kind of action", @"clean,quit,remove,stop,trash,wrapup",
      [[[[p.fixes valueForKey:@"kind"] sortedArrayUsingSelector:@selector(compare:)] valueForKey:@"description"] componentsJoinedByString:@","]);
    BOOL ranked = YES, apart = YES, exist = YES;
    double mw = 1, dw = 1;
    for (NSUInteger i = 0; i < p.fixes.count; i++) {
        MMPerformanceFix *f = p.fixes[i];
        double share = MAX((double)f.memoryBack / p.memory.total * mw, (double)f.diskBack / p.disk.total * dw);
        if (fabs(share - f.share) > 1e-12) ranked = NO;
        if (i && p.fixes[i - 1].share < f.share) ranked = NO;
        NSDictionary *fj = f.json;
        if (!fj[@"memoryBack"] || !fj[@"diskBack"] || fj[@"back"] || fj[@"total"]) apart = NO;
        for (NSString *k in f.rows) if (![p row:k]) exist = NO;
        if (!f.rows.count) exist = NO;
    }
    T(@"performance: fixes are ranked by the larger share of what they give back", @"yes", YN(ranked));
    T(@"performance: each fix keeps memory back and disk back apart", @"yes", YN(apart));
    T(@"performance: a fix's parts point at rows that exist", @"yes", YN(exist));
    MMPerformanceFix *wrap = nil, *stop = nil, *quit = nil, *rem = nil, *trash = nil, *clean = nil;
    for (MMPerformanceFix *f in p.fixes) {
        if ([f.kind isEqualToString:@"wrapup"]) wrap = f; else if ([f.kind isEqualToString:@"stop"]) stop = f;
        else if ([f.kind isEqualToString:@"quit"]) quit = f; else if ([f.kind isEqualToString:@"remove"]) rem = f;
        else if ([f.kind isEqualToString:@"trash"]) trash = f; else if ([f.kind isEqualToString:@"clean"]) clean = f;
    }
    T(@"performance: the Wrap Up gives back its server and helper memory and its worktree's disk", @"364 2048",
      [NSString stringWithFormat:@"%llu %llu", wrap.memoryBack / MB, wrap.diskBack / MB]);
    T(@"performance: the Wrap Up runs its plan, with its parts as rows", @"yes 5 0", [NSString stringWithFormat:@"%@ %lu %lu",
      YN(wrap.wrapUp != nil && !wrap.wrapUp.whyNot), (unsigned long)wrap.rows.count, (unsigned long)wrap.actions.count]);
    T(@"performance: stop holds the idle server outside the Wrap Up, and not the kept one", @"locohost:server:app#dev 512",
      [NSString stringWithFormat:@"%@ %llu", [stop.rows componentsJoinedByString:@","], stop.memoryBack / MB]);
    T(@"performance: quit holds the close-list app, and no tab trim is a fix", @"minmacs:app:com.example.chat 1536 1",
      [NSString stringWithFormat:@"%@ %llu %lu", [quit.rows componentsJoinedByString:@","], quit.memoryBack / MB, (unsigned long)quit.actions.count]);
    T(@"performance: remove holds the merged worktree outside the Wrap Up only", @"1 5",
      [NSString stringWithFormat:@"%lu %llu", (unsigned long)rem.rows.count, rem.diskBack / GB]);
    T(@"performance: trash leaves out caches inside a Wrap Up or a removed worktree", @"noonoo:clutter:derived-data 14",
      [NSString stringWithFormat:@"%@ %llu", [trash.rows componentsJoinedByString:@","], trash.diskBack / GB]);
    T(@"performance: a tool's own cleanup needs you, the others do not", @"yes no no",
      [NSString stringWithFormat:@"%@ %@ %@", YN(clean.needsYou), YN(wrap.needsYou), YN(trash.needsYou)]);
    BOOL runs = YES;
    for (MMPerformanceFix *f in p.fixes) if (!f.wrapUp && (!f.actions.count || !f.policy)) runs = NO;
    T(@"performance: every other fix holds the actions and the policy MMRunAction takes", @"yes", YN(runs));

    // Pressure weighs memory more, and low disk weighs disk more.
    MMSnapshot *tight = Snapshot(1000 * GB, 50 * GB, 4);
    __block MMPerformance *q;
    dispatch_sync(MMQueue(@"perftest", @"build", QOS_CLASS_USER_INITIATED), ^{ q = [MMPerformance from:tight history:Hour(8 * GB) lookBack:nil]; });
    BOOL weighed = YES;
    for (NSUInteger i = 0; i < q.fixes.count; i++) {
        MMPerformanceFix *f = q.fixes[i];
        double share = MAX((double)f.memoryBack / q.memory.total * 2.5, (double)f.diskBack / q.disk.total * 3);
        if (fabs(share - f.share) > 1e-12 || (i && q.fixes[i - 1].share < f.share)) weighed = NO;
    }
    T(@"performance: critical pressure and under 100 GB free weigh as 132-a does", @"yes", YN(weighed));

    // A footprint can pass memory used. The parts are cut to fit.
    __block MMPerformance *c;
    dispatch_sync(MMQueue(@"perftest", @"build", QOS_CLASS_USER_INITIATED), ^{ c = [MMPerformance from:s history:Hour(2 * GB) lookBack:nil]; });
    T(@"performance: parts past memory used are cut, and still add up to used", @"yes yes", [NSString stringWithFormat:@"%@ %@",
      YN(c.memory.cut > 0), YN(Sum(c.memory.parts) == c.memory.used && [c.memory.parts[MMPerformanceOther] unsignedLongLongValue] == 0)]);

    // Nothing names the lid.
    T(@"performance: nothing in the model names the lid", @"no", YN(NamesLid(w)));
}

static void Calm(void) {
    Busy();
    // Nothing to fix: every proposal is gone or kept.
    for (NSString *e in gFindings.allKeys) {
        NSMutableArray *a = [NSMutableArray new];
        for (MMFinding *f in gFindings[e]) {
            if (!f.proposal) { [a addObject:f]; continue; }
            [a addObject:Finding(f.expert, f.kind, f.stableKey, f.title, f.path, f.procs.count ? ({ MMProcKey k; [f.procs.firstObject getValue:&k size:sizeof k]; k.pid; }) : 0, f.cost.ramBytes, f.cost.diskFreed, nil, nil)];
        }
        gFindings[e] = a;
    }
    [gGit enumerateKeysAndObjectsUsingBlock:^(NSString *k, TGit *g, BOOL *stop) { g.merged = MMMergedNone; }];
    [gAgents.firstObject setState:MMAgentWorking];
    MMSnapshot *s = Snapshot(1000 * GB, 300 * GB, 1);
    __block MMPerformance *p;
    dispatch_sync(MMQueue(@"perftest", @"build", QOS_CLASS_USER_INITIATED), ^{
        p = [MMPerformance from:s history:Hour(8 * GB) lookBack:[MMPerformanceLookBack read:MMGains.shared now:NSDate.date]];
    });
    NSDictionary *j = p.json;
    T(@"calm: no fix and nobody needs you", @"0 0", [NSString stringWithFormat:@"%lu %ld", (unsigned long)p.fixes.count, (long)p.needsYou]);
    NSMutableArray *keys = [NSMutableArray new], *values = [NSMutableArray new];
    Strings(j, keys, values);
    NSMutableSet *data = [NSMutableSet setWithArray:@[@"bytes", @"tabs", MMPerformanceServers, MMPerformanceAgents, MMPerformanceApps,
                                                      MMPerformanceTabsGroup, MMPerformanceHelpers, MMPerformanceWorktrees, MMPerformanceClutter,
                                                      MMPerformanceOther]];
    for (MMPerformanceRow *r in AllRows(p)) [data addObjectsFromArray:@[r.key, r.findingID, r.expert, r.name]];
    NSMutableArray *text = [NSMutableArray new];
    for (NSString *v in values) if (![data containsObject:v]) [text addObject:v];
    T(@"calm: the model holds no text, only numbers and the names and keys of its rows", @"", [text componentsJoinedByString:@" | "]);
    NSSet *words = [NSSet setWithArray:@[@"text", @"say", @"line", @"summary", @"title", @"words", @"sentence", @"message", @"status"]];
    NSMutableArray *bad = [NSMutableArray new];
    for (NSString *k in keys) if ([words containsObject:k.lowercaseString]) [bad addObject:k];
    T(@"calm: no key holds a sentence", @"", [bad componentsJoinedByString:@","]);
    T(@"calm: the look-back is numbers only", @"today week", [[[j[@"lookBack"] allKeys] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]);
    T(@"calm: nothing names the lid", @"no", YN(NamesLid(Words(j))));
}

static void LookBack(void) {
    MMGains *g = MMGains.shared;
    // A row at the very instant of the read can be stored a hair after it, so today's rows are a second earlier.
    NSDate *now = NSDate.date, *just = [now dateByAddingTimeInterval:-1];
    NSDate *(^ago)(double) = ^(double days) { return [now dateByAddingTimeInterval:-days * 86400]; };
    BOOL ok = YES;
    ok &= [g add:@"perf-1" run:nil kind:MMGainServer part:nil who:MMGainByYou by:@"manual" expert:@"locohost" subject:@":3000"
         workstream:nil at:just memory:100 * MB disk:0 diskState:MMGainDiskNone trashed:nil items:1];
    ok &= [g add:@"perf-2" run:nil kind:MMGainCache part:nil who:MMGainByAuto by:@"proactive" expert:@"noonoo" subject:@"cache"
         workstream:nil at:just memory:0 disk:7 * MB diskState:MMGainDiskFreed trashed:nil items:1];
    ok &= [g add:@"perf-3" run:nil kind:MMGainApp part:nil who:MMGainByYou by:@"manual" expert:@"minmacs" subject:@"Chat"
         workstream:nil at:ago(3) memory:50 * MB disk:0 diskState:MMGainDiskNone trashed:nil items:1];
    ok &= [g add:@"perf-4" run:nil kind:MMGainApp part:nil who:MMGainByYou by:@"manual" expert:@"minmacs" subject:@"Old"
         workstream:nil at:ago(10) memory:1 * GB disk:0 diskState:MMGainDiskNone trashed:nil items:1];
    ok &= [g add:@"perf-5" run:nil kind:MMGainServer part:nil who:MMGainByYou by:@"manual" expert:@"locohost" subject:@":4000"
         workstream:nil at:just memory:999 * MB disk:0 diskState:MMGainDiskNone trashed:nil items:1];
    [g takeBack:@"perf-5"];
    T(@"lookback: the fixture rows are written", @"yes", YN(ok));
    MMPerformanceLookBack *b = [MMPerformanceLookBack read:g now:now];
    T(@"lookback: this week and today match the rows, the undone and the old one left out", @"150 7 100 7",
      [NSString stringWithFormat:@"%llu %llu %llu %llu", b.weekMemory / MB, b.weekDisk / MB, b.todayMemory / MB, b.todayDisk / MB]);
    NSDictionary *sum = [g summary:7 now:now];
    T(@"lookback: the same numbers as the gains log's 7-day summary", YN(YES), YN(
      b.weekMemory == [sum[@"total"][@"memoryBack"] unsignedLongLongValue] && b.weekDisk == [sum[@"total"][@"diskBack"] unsignedLongLongValue] &&
      b.todayMemory == [sum[@"today"][@"memoryBack"] unsignedLongLongValue] && b.todayDisk == [sum[@"today"][@"diskBack"] unsignedLongLongValue]));
}

static uint64_t ThreadNs(void) {
    struct timespec t; clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t);
    return (uint64_t)t.tv_sec * NSEC_PER_SEC + (uint64_t)t.tv_nsec;
}

static void Bench(void) {
    Busy();
    MMSnapshot *s = Snapshot(1000 * GB, 300 * GB, 1);
    MMHistoryView *h = Hour(8 * GB);
    MMPerformanceLookBack *b = [MMPerformanceLookBack fromSummary:@{}];
    __block uint64_t ns = 0;
    __block NSUInteger fixes = 0;
    const int n = 400;
    dispatch_sync(MMQueue(@"perftest", @"build", QOS_CLASS_USER_INITIATED), ^{
        for (int i = 0; i < 20; i++) (void)[MMPerformance from:s history:h lookBack:b];
        uint64_t t0 = ThreadNs();
        for (int i = 0; i < n; i++) @autoreleasepool { fixes += [MMPerformance from:s history:h lookBack:b].fixes.count; }
        ns = ThreadNs() - t0;
    });
    Info([NSString stringWithFormat:@"one build at fixture scale, %lu findings and 2 merged worktrees: %.3f ms CPU, mean of %d",
          (unsigned long)s.findings.count, ns / 1e6 / n, n]);
    printf("BENCH\t%.4f\n", ns / 1e6 / n);
    T(@"bench: every build made the same fixes", @(6 * n), @(fixes));
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: performance <dir> model|calm|lookback|bench\n"); return 2; }
        gDir = @(argv[1]);
        Register();
        NSString *mode = @(argv[2]);
        if ([mode isEqualToString:@"model"]) Model();
        else if ([mode isEqualToString:@"calm"]) Calm();
        else if ([mode isEqualToString:@"lookback"]) LookBack();
        else if ([mode isEqualToString:@"bench"]) Bench();
        else return 2;
        printf("END\n");
    }
    return 0;
}
