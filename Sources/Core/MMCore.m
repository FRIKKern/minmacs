// Core as one running whole: the expert registry, the fact source of the graph, the core socket's verbs,
// and MMCoreStart and MMCoreStop, which start and end them in order.
//
// The fact source reads only what Core already knows: the latest Senses sample and power facts, the agents the
// registry finds in that sample, the session index and the repo index. A rebuild never samples on its own,
// except right after an exit, when the last sample still lists the process that ended.
#import "Core/MMCore.h"
#import <os/log.h>
#import <unistd.h>

static os_log_t CoreLog(void) {
    static os_log_t log; static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("no.guerrilla.minmacs", "core"); });
    return log;
}

#pragma mark - The expert registry

static NSMutableArray<id<MMExpert>> *gExperts;
static NSMutableDictionary<NSString *, MMCoreRequestHandler> *gHandlers;

static void SetUpTables(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gExperts = [NSMutableArray new]; gHandlers = [NSMutableDictionary new]; });
}

void MMRegisterExpert(id<MMExpert> expert) {
    NSString *eid = expert.expertID;
    if (!eid.length) return;
    SetUpTables();
    @synchronized (gExperts) {
        for (id<MMExpert> e in gExperts) if ([e.expertID isEqualToString:eid]) return;   // once per expert
        [gExperts addObject:expert];
    }
    [MMGraph.shared addExpert:expert];
    MMReviewBroker *b = MMReviewBroker.shared;
    [b registerRules:[expert rules] ?: @[] expert:eid];
    __weak id<MMExpert> weak = expert;
    [b setRequestMaker:^MMReviewRequest *(NSString *trigger, MMSnapshot *s) {
        id<MMExpert> e = weak;
        return e && s ? [e reviewRequest:trigger snapshot:s] : nil;
    } expert:eid];
}

NSArray<id<MMExpert>> *MMExperts(void) {
    SetUpTables();
    @synchronized (gExperts) { return [gExperts copy]; }
}

id<MMExpert> MMExpertNamed(NSString *expertID) {
    for (id<MMExpert> e in MMExperts()) if ([e.expertID isEqualToString:expertID]) return e;
    return nil;
}

#pragma mark - The fact source

@interface MMCoreFactSource : NSObject <MMFactSource>
/// Set when a watched process exited. The next rebuild takes a fresh sample, so the process is gone from it.
@property (atomic) BOOL wantsFreshSample;
@end

@implementation MMCoreFactSource

/// Everything but the sample and power, which the caller picks.
static MMFacts *FactsFrom(uint64_t generation, MMSample *sample, MMPower *power) {
    if (!sample) return nil;
    [MMSessions.shared refresh];
    NSArray<MMAgent *> *agents = [MMRegistry.shared agentsIn:sample power:power] ?: @[];
    NSArray<MMWorktree *> *trees = MMRepoIndex.shared.worktrees;
    NSMutableDictionary<NSString *, MMGitFacts *> *git = [NSMutableDictionary new];
    for (MMWorktree *w in trees) {
        MMGitFacts *g = w.path ? [MMRepoIndex.shared factsFor:w wait:NO] : nil;
        if (g) git[w.path] = g;
    }
    // The clutter catalog of P28 comes with Noo-Noo in phase 3, so no item is listed yet.
    return [MMFacts generation:generation sample:sample power:power agents:agents sessions:MMSessions.shared.all
                     worktrees:trees clutter:@[] git:git];
}

- (MMFacts *)factsFor:(uint64_t)generation {
    MMSenses *senses = MMSenses.shared;
    MMSample *s = senses.latest;
    if (!s || self.wantsFreshSample) {
        self.wantsFreshSample = NO;
        s = [senses sampleNow];   // the graph queue may wait on the Senses queue; Senses never waits on the graph
    }
    return FactsFrom(generation, s, senses.power);
}

/// Principle 5: a new sample, the sessions read again, and the git facts of the finding's worktree with wait YES.
- (MMFacts *)freshFactsFor:(MMFinding *)finding {
    if (NSThread.isMainThread) return nil;
    MMSenses *senses = MMSenses.shared;
    MMSample *s = [senses sampleNow];
    MMFacts *f = FactsFrom(MMGraph.shared.latest.generation, s, senses.power);
    if (!f) return nil;
    MMWorktree *w = finding.path.length ? [MMRepoIndex.shared worktreeAt:finding.path] : nil;
    MMGitFacts *g = w ? [MMRepoIndex.shared factsFor:w wait:YES] : nil;
    if (!g) return f;
    NSMutableDictionary *git = [NSMutableDictionary new];
    for (MMWorktree *x in f.worktrees) { MMGitFacts *y = [f gitFor:x]; if (y && x.path) git[x.path] = y; }
    git[w.path] = g;
    NSArray *trees = f.worktrees;
    if (![[trees valueForKey:@"path"] containsObject:w.path]) trees = [trees arrayByAddingObject:w];
    return [MMFacts generation:f.generation sample:f.sample power:f.power agents:f.agents sessions:f.sessions
                     worktrees:trees clutter:f.clutter git:git];
}

@end

#pragma mark - The core socket's verbs

void MMCoreServe(NSString *verb, MMCoreRequestHandler handler) {
    if (!verb.length) return;
    SetUpTables();
    @synchronized (gHandlers) {
        if (handler) gHandlers[verb] = [handler copy]; else [gHandlers removeObjectForKey:verb];
    }
}

NSDictionary *MMCoreHandleRequest(NSDictionary *request) {
    NSString *verb = [request[@"verb"] isKindOfClass:NSString.class] ? request[@"verb"] : nil;
    if (!verb.length) return @{@"error": @"the request names no verb"};
    MMCoreRequestHandler h;
    SetUpTables();
    @synchronized (gHandlers) { h = gHandlers[verb]; }
    if (!h) return @{@"error": [NSString stringWithFormat:@"no verb %@ in the running app", verb]};
    return h(request) ?: @{@"error": @"no reply"};
}

#ifndef MM_VERSION
#define MM_VERSION "0.0.0"
#endif

/// The verbs Core answers itself: ping, so the CLI knows an app runs, and status, a short summary of the graph.
static void ServeCoreVerbs(void) {
    MMCoreServe(@"ping", ^NSDictionary *(NSDictionary *r) {
        return @{@"ok": @YES, @"pid": @(getpid()), @"version": @MM_VERSION};
    });
    MMCoreServe(@"status", ^NSDictionary *(NSDictionary *r) {
        MMSnapshot *s = MMGraph.shared.latest;
        NSMutableArray *experts = [NSMutableArray new];
        for (id<MMExpert> e in MMExperts()) [experts addObject:e.expertID];
        return @{@"ok": @YES, @"generation": @(s.generation), @"findings": @(s.findings.count),
                 @"workstreams": @(s.workstreams.count), @"workingAgents": @(s.workingAgents),
                 @"worktrees": @(MMRepoIndex.shared.worktrees.count), @"experts": experts};
    });
}

#pragma mark - Start and stop

static BOOL gStarted;
static id gSensesToken, gGraphToken, gReposToken;
static MMFolderWatch *gReposWatch;
static dispatch_source_t gReposTimer, gReviewTimer;
static MMCoreSocket *gSocket;
static NSMutableSet<NSString *> *gWatchedExits;   // main only: the pid:start keys handed to watchExits

static const NSTimeInterval kReposEvery = 600;    // a full walk every 10 minutes, besides FSEvents
static const NSTimeInterval kReviewEvery = 3600;  // a scheduled review wake per expert every hour
static const NSTimeInterval kReviewFirst = 60;    // and the first one a minute after launch

/// Main only. Watches the exit of every agent and every process a finding names, each key once.
static void WatchExitsIn(MMSnapshot *snap) {
    NSMutableDictionary<NSString *, NSValue *> *now = [NSMutableDictionary new];
    for (MMAgent *a in snap.facts.agents) {
        MMProcKey k = a.key;
        now[MMProcKeyString(k)] = [NSValue valueWithBytes:&k objCType:@encode(MMProcKey)];
    }
    for (MMFinding *f in snap.findings)
        for (NSValue *v in f.procs) {
            MMProcKey k; [v getValue:&k size:sizeof k];
            now[MMProcKeyString(k)] = v;
        }
    NSMutableArray<NSValue *> *add = [NSMutableArray new];
    for (NSString *k in now) if (![gWatchedExits containsObject:k]) [add addObject:now[k]];
    // A key gone from the snapshot is forgotten, so the set never grows with processes that are gone.
    [gWatchedExits intersectSet:[NSSet setWithArray:now.allKeys]];
    [gWatchedExits addObjectsFromArray:now.allKeys];
    if (add.count) [MMSenses.shared watchExits:add];
}

static void StartRepos(void) {
    MMRepoIndex *index = MMRepoIndex.shared;
    [index refresh:nil];
    NSArray *roots = index.roots;
    if (roots.count)
        gReposWatch = [MMFolderWatch watch:roots name:@"repos" skip:@[@"node_modules", @".git/objects", @"DerivedData", @".next", @"target"]
                                   changed:^(NSSet<NSString *> *dirs, BOOL rescan) { [index refresh:rescan ? nil : dirs]; }];
    gReposTimer = MMTimer(MMQueue(@"core", @"repos", QOS_CLASS_UTILITY), kReposEvery, 30, ^{ [index refresh:nil]; });
    gReposToken = [NSNotificationCenter.defaultCenter addObserverForName:MMRepoIndexDidChangeNotification object:index queue:nil
                                                              usingBlock:^(NSNotification *n) { [MMGraph.shared rebuild:@"worktrees"]; }];
}

static void StartReviews(void) {
    __block NSTimeInterval first = kReviewFirst;
    dispatch_queue_t q = MMQueue(@"core", @"review.schedule", QOS_CLASS_UTILITY);
    gReviewTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(gReviewTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(first * NSEC_PER_SEC)),
                              (uint64_t)(kReviewEvery * NSEC_PER_SEC), 60ull * NSEC_PER_SEC);
    dispatch_source_set_event_handler(gReviewTimer, ^{
        // The broker coalesces wakes and keeps to its budget, so a wake with nothing new costs nothing.
        for (id<MMExpert> e in MMExperts()) [MMReviewBroker.shared wake:@"schedule" expert:e.expertID];
    });
    dispatch_resume(gReviewTimer);
}

void MMCoreStart(void) {
    if (!NSThread.isMainThread) { dispatch_sync(dispatch_get_main_queue(), ^{ MMCoreStart(); }); return; }
    if (gStarted) return;
    gStarted = YES;
    SetUpTables();
    gWatchedExits = [NSMutableSet new];

    // 1. Store: the support folder, what the last run left, and the one migration from the old apps.
    NSString *dir = MMSupportDir();
    NSString *crashed = MMBreadcrumbLeftOver();
    if (crashed) os_log(CoreLog(), "the last run ended inside %{public}@", crashed);
    // A test home never reads the person's old apps.
    if (!NSProcessInfo.processInfo.environment[@"MINMACS_HOME"].length) MMImportLegacy(nil);
    MMStartWatching();
    os_log(CoreLog(), "Core starts in %{public}@", dir);

    // 2. Senses: the 5-second pass, and a rebuild on every signal it pushes.
    MMCoreFactSource *source = [MMCoreFactSource new];
    MMSenses *senses = MMSenses.shared;
    gSensesToken = [senses observe:MMSignalSample | MMSignalExit | MMSignalApp | MMSignalPower | MMSignalLid |
                                   MMSignalMemory | MMSignalThermal | MMSignalSleep | MMSignalDisk
                             block:^(MMSignal changed, id detail) {
        if (changed & MMSignalExit) {
            if ([detail isKindOfClass:NSValue.class]) {
                MMProcKey k; [(NSValue *)detail getValue:&k size:sizeof k];
                [gWatchedExits removeObject:MMProcKeyString(k)];
            }
            source.wantsFreshSample = YES;
        }
        [MMGraph.shared rebuild:(changed & MMSignalSample) ? @"sample" : @"signal"];
    }];
    [senses start];

    // 3. Know: agent events behind their flag, and the repo index with its FSEvents watch.
    [MMAgentEvents.shared start];
    StartRepos();

    // 4. The graph with its fact source. Each new snapshot names the processes whose exits to watch.
    MMGraph *graph = MMGraph.shared;
    graph.source = source;
    gGraphToken = [graph observe:^(MMSnapshot *snap) { WatchExitsIn(snap); }];
    [graph start];

    // 5. The review broker: a scheduled wake per expert.
    StartReviews();

    // 6. The core socket, so a CLI call reaches this app.
    ServeCoreVerbs();
    NSString *why = nil;
    gSocket = [MMCoreSocket serve:^NSDictionary *(NSDictionary *request) { return MMCoreHandleRequest(request); } error:&why];
    if (!gSocket) os_log(CoreLog(), "core.sock does not serve: %{public}@", why);
}

void MMCoreStop(void) {
    if (!NSThread.isMainThread) { dispatch_sync(dispatch_get_main_queue(), ^{ MMCoreStop(); }); return; }
    if (!gStarted) return;
    gStarted = NO;
    [gSocket stop]; gSocket = nil;
    if (gReviewTimer) { dispatch_source_cancel(gReviewTimer); gReviewTimer = nil; }
    if (gReposTimer) { dispatch_source_cancel(gReposTimer); gReposTimer = nil; }
    [gReposWatch stop]; gReposWatch = nil;
    if (gReposToken) { [NSNotificationCenter.defaultCenter removeObserver:gReposToken]; gReposToken = nil; }
    [MMGraph.shared stopObserving:gGraphToken]; gGraphToken = nil;
    [MMSenses.shared stopObserving:gSensesToken]; gSensesToken = nil;
    [MMSenses.shared stop];
    [MMAgentEvents.shared stop];
    [gWatchedExits removeAllObjects];
    os_log(CoreLog(), "Core stopped");
}
