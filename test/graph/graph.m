// Checks for the graph, issue #16. Built by test/graph.sh against Sources/Core/Graph alone.
// Every fact is built by hand here. Nothing is sampled, scanned or started, and no file is read.
// The fake classes answer the same messages as the Senses and Know types, which is all the graph sends.
// Prints one line per check: name, want and got, split by tabs.
#import <Foundation/Foundation.h>
#import <mach/mach_time.h>
#import <stdatomic.h>
#import "Core/Graph/MMGraph.h"
#import "Core/MMExpert.h"

static void Check(NSString *name, id want, id got) {
    printf("%s\t%s\t%s\n", name.UTF8String, [[want description] UTF8String], [[got description] UTF8String]);
}

#pragma mark - Fakes for Senses and Know

@interface TProc : NSObject
@property pid_t pid, ppid; @property uid_t uid; @property uint64_t startSec;
@property (copy) NSString *name, *cwd;
@property double cpuPercent, energyRank; @property uint64_t footprint;
@end
@implementation TProc
- (MMProcKey)key { return (MMProcKey){ self.pid, self.startSec }; }
@end

@interface TSample : NSObject
@property NSDate *at; @property uint64_t generation;
@property NSDictionary<NSNumber *, TProc *> *procs;
@end
@implementation TSample
- (TProc *)proc:(pid_t)pid { return self.procs[@(pid)]; }
- (NSArray *)argsOf:(pid_t)pid { return @[]; }
- (NSString *)cwdOf:(pid_t)pid { return self.procs[@(pid)].cwd; }
- (NSArray *)childrenOf:(pid_t)pid {
    NSMutableArray *k = [NSMutableArray new];
    for (TProc *p in self.procs.allValues) if (p.ppid == pid) [k addObject:@(p.pid)];
    return k;
}
- (NSArray *)ancestorsOf:(pid_t)pid limit:(NSUInteger)hops {
    NSMutableArray *a = [NSMutableArray new];
    for (TProc *p = self.procs[@(self.procs[@(pid)].ppid)]; p && a.count < hops; p = p.pid == 1 ? nil : self.procs[@(p.ppid)]) [a addObject:@(p.pid)];
    return a;
}
@end

@interface TAgent : NSObject
@property (copy) NSString *harnessID, *sessionID, *cwd, *why;
@property MMProcKey key; @property MMAgentState state;
@end
@implementation TAgent @end

@interface TSession : NSObject
@property (copy) NSString *agent, *sessionID, *title, *cwd, *branch, *transcript, *liveStatus;
@property NSDate *started, *lastActive; @property pid_t pid; @property BOOL stillWorking;
@end
@implementation TSession @end

@interface TTree : NSObject
@property (copy) NSString *path, *repo, *branch; @property BOOL isMain, locked, missing;
@end
@implementation TTree @end

@interface TGit : NSObject
@property (copy) NSString *head;
@end
@implementation TGit @end

@interface TClutter : NSObject
@property (copy) NSString *path, *ownerPath; @property BOOL ownerGone; @property MMSize size;
@end
@implementation TClutter @end

#pragma mark - A world built by hand

static NSString *const kRepo = @"/h/repo", *const kFeat = @"/h/repo/.claude/worktrees/feat", *const kOther = @"/h/other";
static NSDate *T0;

static TProc *P(pid_t pid, pid_t ppid, uint64_t start, NSString *name, NSString *cwd) {
    TProc *p = [TProc new]; p.pid = pid; p.ppid = ppid; p.startSec = start; p.name = name; p.cwd = cwd; return p;
}
static TSession *S(NSString *agent, NSString *sid, NSString *cwd, pid_t pid, NSTimeInterval startedAgo) {
    TSession *s = [TSession new]; s.agent = agent; s.sessionID = sid; s.cwd = cwd; s.pid = pid;
    s.started = [T0 dateByAddingTimeInterval:-startedAgo]; s.lastActive = T0; return s;
}
static TAgent *A(NSString *harness, NSString *sid, NSString *cwd, pid_t pid, uint64_t start, MMAgentState st) {
    TAgent *a = [TAgent new]; a.harnessID = harness; a.sessionID = sid; a.cwd = cwd; a.key = (MMProcKey){ pid, start }; a.state = st; return a;
}
static TTree *W(NSString *path, BOOL isMain) { TTree *t = [TTree new]; t.path = path; t.repo = kRepo; t.isMain = isMain; return t; }
static TClutter *C(NSString *path, NSString *ownerPath, uint64_t freed) {
    TClutter *c = [TClutter new]; c.path = path; c.ownerPath = ownerPath; c.size = (MMSize){ freed, freed, 1, 0 }; return c;
}

/// The parts of one world. Mutable on purpose, so a check can change them after the build.
@interface TWorld : NSObject
@property NSMutableDictionary<NSNumber *, TProc *> *procs;
@property NSMutableArray *agents, *sessions, *trees, *clutter;
@property NSMutableDictionary *git;
@property NSDate *sampledAt;                            // when the sample was taken, T0 unless a check moves it
@end
@implementation TWorld
+ (instancetype)standard {
    TWorld *w = [TWorld new];
    NSArray *ps = @[
        P(1, 0, 1, @"launchd", @"/"),
        P(50, 1, 10, @"Terminal", @"/"),
        P(100, 50, 100, @"claude", kFeat),                         // session s1, working agent
        P(110, 100, 110, @"node", [kFeat stringByAppendingString:@"/web"]),   // a server in the worktree
        P(120, 100, 120, @"node", @"/tmp/x"),                      // a server outside every worktree, under the agent
        P(130, 50, 130, @"node", kOther),                          // a server in a worktree with no session
        P(200, 50, 200, @"claude", kFeat),                         // session s2 in the same worktree, no agent row
        P(210, 200, 210, @"node", @"/tmp/y"),                      // under s2
        P(300, 50, 300, @"codex", @"/h/notes"),                    // a session in a folder that is not a checkout
        P(310, 300, 310, @"python3", @"/h/notes/tool"),
        P(400, 1, 400, @"postgres", @"/"),                         // nothing above it but launchd
    ];
    w.procs = [NSMutableDictionary new];
    for (TProc *p in ps) w.procs[@(p.pid)] = p;
    w.agents = [@[A(@"claude-code", @"s1", kFeat, 100, 100, MMAgentWorking),
                  A(@"codex", @"s3", @"/h/notes", 300, 300, MMAgentIdle)] mutableCopy];
    w.sessions = [@[S(@"claude-code", @"s1", kFeat, 100, 3600),
                    S(@"claude-code", @"s2", kFeat, 200, 600),
                    S(@"codex", @"s3", @"/h/notes", 300, 60),
                    S(@"claude-code", @"s4", kOther, 0, 86400)] mutableCopy];   // ended
    w.trees = [@[W(kRepo, YES), W(kFeat, NO), W(kOther, NO)] mutableCopy];
    w.clutter = [@[C(@"/h/Library/DerivedData/App-abc", kRepo, 5 << 20),
                   C([kFeat stringByAppendingString:@"/.next"], nil, 64 << 20),
                   C(@"/h/Library/ms-playwright/chromium-1", @"/h/gone", 1 << 20)] mutableCopy];
    TGit *g = [TGit new]; g.head = @"abc123";
    w.git = [@{kFeat: g} mutableCopy];
    return w;
}
- (MMFacts *)facts:(uint64_t)gen {
    TSample *s = [TSample new]; s.at = self.sampledAt ?: T0; s.generation = gen; s.procs = [self.procs copy];
    return [MMFacts generation:gen sample:(MMSample *)s power:nil agents:self.agents sessions:self.sessions
                     worktrees:self.trees clutter:self.clutter git:self.git];
}
@end

#pragma mark - A test expert

/// Reads facts only, like a real expert. Servers from node processes, worktrees from git, clutter from the catalog.
@interface TExpert : NSObject <MMExpert>
@property (copy) NSString *expertID;
@property NSMutableDictionary *extraFacts;              // a mutable value handed to a builder, changed later
@end
@implementation TExpert
- (NSString *)name { return self.expertID; }
- (NSString *)symbol { return @"circle"; }
- (MMVerdictWords *)words { return nil; }
- (NSArray<MMFinding *> *)findingsFrom:(MMFacts *)facts {
    NSMutableArray *out = [NSMutableArray new];
    TSample *s = (TSample *)facts.sample;
    if ([self.expertID isEqual:@"locohost"]) {
        NSArray *pids = [s.procs.allKeys sortedArrayUsingSelector:@selector(compare:)];
        for (NSNumber *n in pids) {
            TProc *p = s.procs[n];
            if (![p.name isEqual:@"node"] && ![p.name isEqual:@"postgres"] && ![p.name isEqual:@"python3"]) continue;
            NSString *stable = [NSString stringWithFormat:@"%@#dev", [p.name isEqual:@"postgres"] ? @"postgres" : p.cwd];
            [out addObject:[MMFinding expert:@"locohost" kind:@"server" stableKey:stable build:^(MMFindingBuilder *b) {
                b.instanceKey = [NSString stringWithFormat:@"%d:%llu", p.pid, p.startSec];
                b.title = p.name;
                MMProcKey k = p.key;
                b.procs = @[[NSValue valueWithBytes:&k objCType:@encode(MMProcKey)]];
                b.facts = self.extraFacts;
            }]];
        }
    } else if ([self.expertID isEqual:@"workforest"]) {
        for (TTree *t in facts.worktrees)
            [out addObject:[MMFinding expert:@"workforest" kind:@"worktree" stableKey:t.path build:^(MMFindingBuilder *b) { b.path = t.path; }]];
    } else if ([self.expertID isEqual:@"noonoo"]) {
        for (TClutter *c in facts.clutter)
            [out addObject:[MMFinding expert:@"noonoo" kind:@"clutter" stableKey:c.path build:^(MMFindingBuilder *b) {
                b.path = c.path; b.ownerPath = c.ownerPath;
                b.cost = (MMCost){ .diskFreed = c.size.freedIfDeleted, .cpuPercent = -1 };
            }]];
    }
    return out;
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

static NSArray<TExpert *> *Experts(void) {
    NSMutableArray *a = [NSMutableArray new];
    for (NSString *e in @[@"locohost", @"workforest", @"noonoo"]) { TExpert *x = [TExpert new]; x.expertID = e; [a addObject:x]; }
    return a;
}

#pragma mark - Helpers

/// Everything a reader can see in a snapshot, as one string. Equal strings mean nothing changed.
static NSString *Dump(MMSnapshot *s) {
    NSMutableString *d = [NSMutableString stringWithFormat:@"gen %llu at %f facts %p\n", s.generation, s.builtAt.timeIntervalSince1970, s.facts];
    for (MMFinding *f in s.findings)
        [d appendFormat:@"%@ %@ %@ %@ %@ %@ %llu %@\n", f.findingID, f.instanceKey, f.title, f.owner.ownerID, f.owner.parent.ownerID,
                        f.fingerprint, f.cost.diskFreed, f.facts];
    for (MMWorkstream *w in s.workstreams)
        [d appendFormat:@"ws %@ %@ %ld %@ %lu %lu\n", w.owner.ownerID, w.session.sessionID, (long)w.agentState, w.fingerprint,
                        (unsigned long)w.findings.count, (unsigned long)w.clutter.count];
    [d appendFormat:@"facts %lu %lu %lu %lu holds %@\n", (unsigned long)s.facts.agents.count, (unsigned long)s.facts.sessions.count,
                    (unsigned long)s.facts.worktrees.count, (unsigned long)s.facts.clutter.count, s.awakeHolds];
    return d;
}

static NSString *Owners(MMSnapshot *s) {
    NSMutableArray *a = [NSMutableArray new];
    for (MMFinding *f in s.findings) [a addObject:[NSString stringWithFormat:@"%@=%@<%@", f.findingID, f.owner.ownerID, f.owner.parent.ownerID]];
    for (MMWorkstream *w in s.workstreams) [a addObject:[NSString stringWithFormat:@"%@ lead %@", w.owner.ownerID, w.session.sessionID]];
    [a sortUsingSelector:@selector(compare:)];
    return [a componentsJoinedByString:@"\n"];
}

static NSString *OwnerOf(MMSnapshot *s, NSString *fid) {
    MMFinding *f = [s finding:fid];
    return f ? (f.owner.parent ? [NSString stringWithFormat:@"%@ in %@", f.owner.ownerID, f.owner.parent.ownerID] : f.owner.ownerID) : @"missing";
}

static void Shuffle(NSMutableArray *a) {
    for (NSUInteger i = a.count; i > 1; i--) [a exchangeObjectAtIndex:i - 1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
}

static double Ms(uint64_t t0, uint64_t t1) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    return (double)(t1 - t0) * tb.numer / tb.denom / 1e6;
}

/// A source with a slow first build, so main has time to show it does not wait.
@interface TSource : NSObject <MMFactSource>
@property TWorld *world;
@property NSTimeInterval delay;
@property (atomic) NSInteger calls;
@property (atomic) BOOL onMain;
@end
@implementation TSource
- (MMFacts *)factsFor:(uint64_t)generation {
    self.calls++;
    if (NSThread.isMainThread) self.onMain = YES;
    if (self.delay > 0) [NSThread sleepForTimeInterval:self.delay];
    return [self.world facts:generation];
}
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return [self.world facts:0]; }
@end

static void Spin(NSTimeInterval seconds, BOOL (^done)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!(done && done()) && [until timeIntervalSinceNow] > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
}

#pragma mark - Checks

static atomic_bool stop;
static atomic_long changed, backwards, reads;

int main(int argc, char **argv) {
    @autoreleasepool {
        T0 = [NSDate dateWithTimeIntervalSince1970:1800000000];
        BOOL stressOnly = argc > 1 && strcmp(argv[1], "stress") == 0;
        NSArray *experts = Experts();

        if (!stressOnly) {
            // Owners and workstreams.
            TWorld *w = [TWorld standard];
            MMSnapshot *s = [MMSnapshot snapshotFrom:[w facts:1] experts:experts reviews:nil holds:nil];
            NSString *web = [NSString stringWithFormat:@"locohost:server:%@/web#dev", kFeat];
            Check(@"a finding id is expert:kind:stableKey", web, [s finding:web].findingID ?: @"missing");
            Check(@"a server in a worktree with a live session belongs to its workstream",
                  [@"workstream:" stringByAppendingString:kFeat], OwnerOf(s, web));
            Check(@"a server outside every worktree belongs to the agent above it",
                  [@"workstream:" stringByAppendingString:kFeat], OwnerOf(s, @"locohost:server:/tmp/x#dev"));
            Check(@"a server under a second session is that session, under the workstream",
                  [NSString stringWithFormat:@"session:s2 in workstream:%@", kFeat], OwnerOf(s, @"locohost:server:/tmp/y#dev"));
            Check(@"a server in a worktree whose session ended belongs to the worktree",
                  [@"worktree:" stringByAppendingString:kOther], OwnerOf(s, [NSString stringWithFormat:@"locohost:server:%@#dev", kOther]));
            Check(@"a process with no folder or agent belongs to the app at its top", @"app:postgres", OwnerOf(s, @"locohost:server:postgres#dev"));
            Check(@"the deepest worktree wins over the repo that holds it",
                  [@"workstream:" stringByAppendingString:kFeat], OwnerOf(s, [@"workforest:worktree:" stringByAppendingString:kFeat]));
            Check(@"the main checkout with no session is a worktree owner",
                  [@"worktree:" stringByAppendingString:kRepo], OwnerOf(s, [@"workforest:worktree:" stringByAppendingString:kRepo]));
            Check(@"clutter goes to the owner its back-link names",
                  [@"worktree:" stringByAppendingString:kRepo], OwnerOf(s, @"noonoo:clutter:/h/Library/DerivedData/App-abc"));
            Check(@"clutter whose back-link is gone is a project owner", @"project:/h/gone",
                  OwnerOf(s, @"noonoo:clutter:/h/Library/ms-playwright/chromium-1"));
            NSInteger noOwner = 0;
            for (MMFinding *f in s.findings) if (!f.owner) noOwner++;
            Check(@"every finding has exactly one owner", @0, @(noOwner));

            Check(@"live sessions make two workstreams, the ended one none", @2, @(s.workstreams.count));
            MMWorkstream *feat = [s workstreamAt:[kFeat stringByAppendingString:@"/web/src"]];
            Check(@"workstreamAt finds the worktree's workstream", [@"workstream:" stringByAppendingString:kFeat], feat.owner.ownerID ?: @"nil");
            Check(@"the working session leads the workstream", @"s1", feat.session.sessionID ?: @"nil");
            Check(@"the workstream carries its agent state", @(MMAgentWorking), @(feat.agentState));
            Check(@"the workstream carries its git facts", @"abc123", feat.git.head ?: @"nil");
            Check(@"a workstream holds what it and its sessions own", @5, @(feat.findings.count));
            Check(@"a workstream holds its clutter", @1, @(feat.clutter.count));
            Check(@"the workstream fingerprint is HEAD, activity and size", @"abc123|10|4", feat.fingerprint ?: @"nil");
            Check(@"a session outside any checkout is a session workstream", @"session:s3", [s workstreamAt:@"/h/notes/a.md"].owner.ownerID ?: @"nil");
            Check(@"the session's process belongs to its session", @"session:s3", OwnerOf(s, @"locohost:server:/h/notes/tool#dev"));
            Check(@"the main checkout has no workstream", @"nil", [s workstreamAt:[kRepo stringByAppendingString:@"/src"]].owner.ownerID ?: @"nil");
            Check(@"workingAgents counts working agents", @1, @([s workingAgents]));
            Check(@"findingsFor gives one expert's findings", @3, @([s findingsFor:@"noonoo"].count));
            Check(@"findingsOwnedBy filters by owner and expert", @3,
                  @([s findingsOwnedBy:feat.owner expert:@"locohost"].count));

            // Owner choice is stable: the input order never matters.
            NSString *want = Owners(s);
            NSInteger differ = 0;
            for (int i = 0; i < 50; i++) {
                TWorld *x = [TWorld standard];
                Shuffle(x.agents); Shuffle(x.sessions); Shuffle(x.trees); Shuffle(x.clutter);
                NSMutableArray *ex = [experts mutableCopy];
                if (![Owners([MMSnapshot snapshotFrom:[x facts:2] experts:ex reviews:nil holds:nil]) isEqualToString:want]) differ++;
            }
            Check(@"50 shuffled inputs give the same owners", @0, @(differ));

            // Two working sessions in one worktree: the earliest started leads, whatever changes in activity.
            TWorld *two = [TWorld standard];
            [two.agents addObject:A(@"claude-code", @"s2", kFeat, 200, 200, MMAgentWorking)];
            NSString *lead = nil; NSInteger leadChanges = 0;
            for (int i = 0; i < 30; i++) {
                Shuffle(two.agents); Shuffle(two.sessions);
                for (TSession *x in two.sessions) x.lastActive = [T0 dateByAddingTimeInterval:-(double)arc4random_uniform(600)];
                NSString *l = [[MMSnapshot snapshotFrom:[two facts:3] experts:experts reviews:nil holds:nil] workstreamAt:kFeat].session.sessionID;
                if (lead && ![l isEqual:lead]) leadChanges++;
                lead = l;
            }
            Check(@"two working sessions: the earliest started leads", @"s1", lead ?: @"nil");
            Check(@"the lead never moves when activity changes", @0, @(leadChanges));

            // Two agents with no session record in one worktree share a link key. The earlier process leads.
            TWorld *twin = [TWorld standard];
            twin.procs[@600] = P(600, 50, 600, @"codex", kOther);
            twin.procs[@610] = P(610, 600, 610, @"node", @"/tmp/z");
            twin.procs[@700] = P(700, 50, 700, @"codex", kOther);
            twin.procs[@710] = P(710, 700, 710, @"node", @"/tmp/w");
            [twin.agents addObject:A(@"codex", nil, kOther, 600, 600, MMAgentIdle)];
            [twin.agents addObject:A(@"codex", nil, kOther, 700, 700, MMAgentIdle)];
            NSString *twinWant = nil; NSInteger twinDiffer = 0;
            for (int i = 0; i < 30; i++) {
                Shuffle(twin.agents);
                MMSnapshot *ts = [MMSnapshot snapshotFrom:[twin facts:3] experts:experts reviews:nil holds:nil];
                NSString *o = [NSString stringWithFormat:@"%@ / %@", OwnerOf(ts, @"locohost:server:/tmp/z#dev"), OwnerOf(ts, @"locohost:server:/tmp/w#dev")];
                if (twinWant && ![o isEqualToString:twinWant]) twinDiffer++;
                if (!twinWant) twinWant = o;
            }
            Check(@"two agents without sessions in one worktree: the earlier leads",
                  [NSString stringWithFormat:@"workstream:%@ / session:codex@%@ in workstream:%@", kOther, kOther, kOther], twinWant ?: @"nil");
            Check(@"their owners never move when the input order does", @0, @(twinDiffer));

            // A restart: a new session id and pid in the same worktree, and the server restarted under it.
            TWorld *r = [TWorld standard];
            [r.procs removeObjectForKey:@100]; [r.procs removeObjectForKey:@110];
            r.procs[@500] = P(500, 50, 900, @"claude", kFeat);
            r.procs[@510] = P(510, 500, 910, @"node", [kFeat stringByAppendingString:@"/web"]);
            r.procs[@120].ppid = 500;
            r.agents[0] = A(@"claude-code", @"s9", kFeat, 500, 900, MMAgentWorking);
            r.sessions[0] = S(@"claude-code", @"s9", kFeat, 500, 10);
            MMSnapshot *after = [MMSnapshot snapshotFrom:[r facts:4] experts:experts reviews:nil holds:nil];
            MMFinding *f0 = [s finding:web], *f1 = [after finding:web];
            Check(@"a restarted server keeps its finding id", web, f1.findingID ?: @"missing");
            Check(@"a restarted server gets a new instance key", @"110:110 then 510:910",
                  [NSString stringWithFormat:@"%@ then %@", f0.instanceKey, f1.instanceKey]);
            Check(@"a restarted session keeps its workstream owner", f0.owner.ownerID, f1.owner.ownerID ?: @"nil");
            Check(@"the finding ids are the same set after a restart",
                  [[[s.findings valueForKey:@"findingID"] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","],
                  [[[after.findings valueForKey:@"findingID"] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]);

            // Holds for keep-awake: a live pid stays, an exited one is dropped.
            MMSnapshot *h = [MMSnapshot snapshotFrom:[w facts:5] experts:experts reviews:nil
                                               holds:@{@"110:110": @"agent works", @"999:1": @"gone", @"110:5": @"pid reused"}];
            Check(@"a hold on a live process stays, exited and reused pids go", @"110:110", [h.awakeHolds.allKeys componentsJoinedByString:@","]);

            // A snapshot never changes after it is built, even when every input it came from changes.
            TWorld *m = [TWorld standard];
            TExpert *lh = experts[0];
            lh.extraFacts = [@{@"port": @3000, @"tags": [@[@"a"] mutableCopy]} mutableCopy];
            MMSnapshot *frozen = [MMSnapshot snapshotFrom:[m facts:6] experts:experts reviews:nil holds:@{@"110:110": @"x"}];
            NSString *before = Dump(frozen);
            [m.agents removeAllObjects]; [m.sessions removeLastObject]; [m.trees removeObjectAtIndex:0]; [m.clutter removeAllObjects];
            [m.git removeAllObjects]; [m.procs removeAllObjects];
            lh.extraFacts[@"port"] = @4000; [lh.extraFacts[@"tags"] addObject:@"b"];
            for (int i = 0; i < 20; i++) [MMSnapshot snapshotFrom:[[TWorld standard] facts:7 + i] experts:experts reviews:nil holds:nil];
            Check(@"a snapshot is unchanged after its inputs change", @"same", [Dump(frozen) isEqualToString:before] ? @"same" : @"changed");
            lh.extraFacts = nil;
            BOOL mutableSeen = NO;
            for (id c in @[frozen.findings, frozen.workstreams, frozen.facts.agents, frozen.facts.sessions, frozen.facts.worktrees,
                           frozen.facts.clutter, frozen.awakeHolds])
                if ([c isKindOfClass:NSMutableArray.class] || [c isKindOfClass:NSMutableDictionary.class]) mutableSeen = YES;
            for (MMFinding *f in frozen.findings)
                if ([f.facts isKindOfClass:NSMutableDictionary.class] || [f.procs isKindOfClass:NSMutableArray.class] ||
                    [f.facts[@"tags"] isKindOfClass:NSMutableArray.class]) mutableSeen = YES;
            for (MMWorkstream *x in frozen.workstreams)
                if ([x.findings isKindOfClass:NSMutableArray.class] || [x.clutter isKindOfClass:NSMutableArray.class]) mutableSeen = YES;
            Check(@"no collection a snapshot hands out is mutable", @NO, @(mutableSeen));
            Check(@"MMFinding has no setters", @NO, @([MMFinding instancesRespondToSelector:@selector(setOwner:)] ||
                                                      [MMFinding instancesRespondToSelector:@selector(setTitle:)]));
        }

        // The live graph: built off main, published to main, and main never waits.
        MMGraph *g = [MMGraph new];
        for (TExpert *e in experts) [g addExpert:e];
        TSource *src = [TSource new];
        src.world = [TWorld standard];
        src.delay = 0.2;
        g.source = src;
        __block NSInteger published = 0, offMain = 0, outOfOrder = 0;
        __block uint64_t lastGen = 0;
        [g observe:^(MMSnapshot *snap) {
            published++;
            if (!NSThread.isMainThread) offMain++;
            if (snap.generation <= lastGen) outOfOrder++;
            lastGen = snap.generation;
        }];

        if (!stressOnly) {
            uint64_t t0 = mach_absolute_time();
            [g start];
            for (int i = 0; i < 1000; i++) [g rebuild:@"burst"];
            double callMs = Ms(t0, mach_absolute_time());
            Check(@"start and 1000 rebuild calls return at once on main", @"yes", callMs < 20 ? @"yes" : [NSString stringWithFormat:@"%.1f ms", callMs]);
            Check(@"current is nil before the first build ends", @"nil", g.current ? @"set" : @"nil");
            // Main keeps turning its run loop while the build sleeps.
            __block uint64_t last = mach_absolute_time(); __block double worst = 0;
            NSTimer *tick = [NSTimer scheduledTimerWithTimeInterval:0.005 repeats:YES block:^(NSTimer *t) {
                uint64_t now = mach_absolute_time();
                worst = MAX(worst, Ms(last, now)); last = now;
            }];
            Spin(3, ^BOOL { return published >= 1 && published == src.calls && g.current.generation == g.latest.generation; });
            Spin(0.5, nil);
            [tick invalidate];
            Check(@"the main run loop never stalls while a 200 ms build runs", @"yes", worst < 50 ? @"yes" : [NSString stringWithFormat:@"%.1f ms", worst]);
            Check(@"1000 rebuild calls coalesce into at most two builds", @"yes", src.calls <= 2 ? @"yes" : [NSString stringWithFormat:@"%ld", (long)src.calls]);
            Check(@"the source never runs on main", @NO, @(src.onMain));
            Check(@"observers run on main", @0, @(offMain));
            Check(@"current is the latest after publish", @"yes", g.current && g.current == g.latest ? @"yes" : @"no");
            // Since issue #52 a call to the source can end in a skipped build, so the source's count can run ahead.
            // The generation counts the snapshots the graph published.
            Check(@"the generation is the graph's count", @(published), @(g.current.generation));
            Check(@"freshFactsFor never runs on main", @"nil", [g freshFactsFor:[g.current.findings firstObject]] ? @"facts" : @"nil");
            __block BOOL freshOff = NO;
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                freshOff = [g freshFactsFor:[g.latest.findings firstObject]] != nil;
                dispatch_semaphore_signal(sem);
            });
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
            Check(@"freshFactsFor answers off main", @YES, @(freshOff));
            NSInteger before = published;
            [g holdAwake:@"agent works" pid:(MMProcKey){ 110, 110 }];
            Spin(3, ^BOOL { return published > before; });
            Check(@"holdAwake lands in the next snapshot", @"agent works", g.current.awakeHolds[@"110:110"] ?: @"nil");

            // A hold on a process the sample is too old to know, such as one started a moment ago, stays.
            // It goes only when a sample taken after the hold no longer has the process.
            src.world.sampledAt = [NSDate dateWithTimeIntervalSinceNow:-5];
            before = published;
            [g holdAwake:@"just started" pid:(MMProcKey){ 777, 7 }];
            Spin(3, ^BOOL { return published > before; });
            Check(@"a hold newer than the sample stays", @"just started", g.current.awakeHolds[@"777:7"] ?: @"nil");
            before = published;
            [g rebuild:@"same old sample"];
            Spin(3, ^BOOL { return published > before; });
            Check(@"it stays through rebuilds on that old sample", @"just started", g.current.awakeHolds[@"777:7"] ?: @"nil");
            src.world.sampledAt = [NSDate dateWithTimeIntervalSinceNow:1];
            before = published;
            [g rebuild:@"new sample"];
            Spin(3, ^BOOL { return published > before; });
            Check(@"a sample after the hold without the process drops it", @"nil", g.current.awakeHolds[@"777:7"] ?: @"nil");
            Check(@"the live hold stays beside it", @"agent works", g.current.awakeHolds[@"110:110"] ?: @"nil");
            src.world.sampledAt = nil;
        }

        // Readers on other queues read latest while main publishes, with no lock.
        src.delay = 0;
        dispatch_group_t readers = dispatch_group_create();
        for (int r = 0; r < 4; r++)
            dispatch_group_async(readers, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                uint64_t seen = 0;
                while (!atomic_load(&stop)) @autoreleasepool {
                    MMSnapshot *snap = g.latest;
                    if (!snap) continue;
                    if (snap.generation < seen) atomic_fetch_add(&backwards, 1);
                    seen = snap.generation;
                    NSString *a = Dump(snap);
                    [NSThread sleepForTimeInterval:0.001];
                    if (![Dump(snap) isEqualToString:a]) atomic_fetch_add(&changed, 1);
                    atomic_fetch_add(&reads, 1);
                }
            });
        uint64_t genBefore = g.latest.generation;
        NSTimer *poke = [NSTimer scheduledTimerWithTimeInterval:0.002 repeats:YES block:^(NSTimer *t) { [g rebuild:@"stress"]; }];
        Spin(1.5, nil);
        [poke invalidate];
        atomic_store(&stop, true);
        dispatch_group_wait(readers, DISPATCH_TIME_FOREVER);
        Spin(0.3, nil);
        Check(@"main published many snapshots while readers ran", @"yes", g.latest.generation - genBefore > 20 ? @"yes" :
              [NSString stringWithFormat:@"%llu", g.latest.generation - genBefore]);
        Check(@"readers on other queues read many snapshots", @"yes", atomic_load(&reads) > 100 ? @"yes" : [NSString stringWithFormat:@"%ld", atomic_load(&reads)]);
        Check(@"a snapshot a reader holds never changes", @0, @(atomic_load(&changed)));
        Check(@"latest never goes back a generation", @0, @(atomic_load(&backwards)));
        Check(@"main publishes generations in order", @0, @(outOfOrder));
    }
    return 0;
}
