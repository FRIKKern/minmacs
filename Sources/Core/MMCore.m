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
/// Set when a watched process exited. The next rebuild drops it from the last sample, so the process is gone.
@property (atomic) BOOL wantsFreshSample;
/// The keys that exited since the last rebuild. Main adds, the graph queue takes, under @synchronized (self).
@property (strong) NSMutableArray<NSValue *> *exited;
- (void)noteExit:(NSValue *)key;
@end

@implementation MMCoreFactSource

/// Everything but the sample and power, which the caller picks. Git facts come from the index's memory with
/// wait NO, so a rebuild never reads git's files or runs git. A worktree a change marked is brought up to date
/// on the git queue, which asks for another rebuild when its facts moved.
static MMFacts *FactsFrom(uint64_t generation, MMSample *sample, MMPower *power, BOOL fresh) {
    if (!sample) return nil;
    // The session index reads its folders only when FSEvents saw a change, issue #52. Fresh facts read them now.
    if (fresh) [MMSessions.shared refreshAll]; else [MMSessions.shared refresh];
    NSArray<MMAgent *> *agents = [MMRegistry.shared agentsIn:sample power:power] ?: @[];
    NSArray<MMWorktree *> *trees = MMRepoIndex.shared.worktrees;
    NSMutableDictionary<NSString *, MMGitFacts *> *git = [NSMutableDictionary new];
    for (MMWorktree *w in trees) {
        MMGitFacts *g = w.path ? [MMRepoIndex.shared factsFor:w wait:NO] : nil;
        if (g) git[w.path] = g;
    }
    // The clutter items of the last scans. Scans run on their own queue, never in a rebuild.
    return [MMFacts generation:generation sample:sample power:power agents:agents sessions:MMSessions.shared.all
                     worktrees:trees clutter:MMClutterCatalog.shared.items git:git];
}

- (void)noteExit:(NSValue *)key {
    @synchronized (self) { if (!_exited) _exited = [NSMutableArray new]; if (key) [_exited addObject:key]; }
}

- (MMFacts *)factsFor:(uint64_t)generation {
    MMSenses *senses = MMSenses.shared;
    MMSample *s = senses.latest;
    if (!s || self.wantsFreshSample) {
        self.wantsFreshSample = NO;
        NSArray *gone;
        @synchronized (self) { gone = [_exited copy]; [_exited removeAllObjects]; }
        // Issue #52: the last sample without the processes that exited, which costs a copy, not a pass.
        // An exit with no key, or no sample yet, takes a pass. The graph queue may wait on the Senses queue;
        // Senses never waits on the graph.
        s = s && gone.count ? [senses sampleWithout:gone] : [senses sampleNow];
    }
    return FactsFrom(generation, s, senses.power, NO);
}

/// Principle 5: a new sample, the sessions read again, and the git facts of the finding's worktree with wait YES.
- (MMFacts *)freshFactsFor:(MMFinding *)finding {
    if (NSThread.isMainThread) return nil;
    MMSenses *senses = MMSenses.shared;
    MMSample *s = [senses sampleNow];
    MMFacts *f = FactsFrom(MMGraph.shared.latest.generation, s, senses.power, YES);
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
static id gSensesToken, gGraphToken, gReposToken, gGitToken, gClutterToken, gSessionsToken;
static dispatch_source_t gReposTimer, gReviewTimer;
static MMCoreSocket *gSocket;
static NSMutableSet<NSString *> *gWatchedExits;   // main only: the pid:start keys handed to watchExits
static BOOL gExitRebuildQueued;                    // main only: a rebuild for exits waits to gather more
static const NSTimeInterval kExitGather = 0.3;     // how long an exit's rebuild waits for more exits
static const NSTimeInterval kExitPassNear = 0.5;   // a pass due sooner than this after that rebuilds for them

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

/// The repo index: a walk now, one FSEvents stream per root, and a full walk every 10 minutes.
/// A change marks the worktrees it touched, and the index runs git for those alone, then asks for a rebuild.
/// A rebuild reads git facts from memory, so a 5-second pass never reads git's files or runs git.
static void StartRepos(void) {
    MMRepoIndex *index = MMRepoIndex.shared;
    [index refresh:nil];
    [index startWatching];   // on the repos queue, since each stream reads its saved event id
    gReposTimer = MMTimer(MMQueue(@"core", @"repos", QOS_CLASS_UTILITY), kReposEvery, 30, ^{ [index refresh:nil]; });
    gReposToken = [NSNotificationCenter.defaultCenter addObserverForName:MMRepoIndexDidChangeNotification object:index queue:nil
                                                              usingBlock:^(NSNotification *n) { [MMGraph.shared rebuild:@"worktrees"]; }];
    gGitToken = [NSNotificationCenter.defaultCenter addObserverForName:MMRepoIndexFactsDidChangeNotification object:index queue:nil
                                                            usingBlock:^(NSNotification *n) { [MMGraph.shared rebuild:@"git"]; }];
}

/// The clutter catalog scans each row at most as often as the row says, on its own queue, sizing through the worker.
static void StartClutter(void) {
    MMClutterCatalog *c = MMClutterCatalog.shared;
    c.sizeWithWorker = YES;
    c.projectsProvider = ^NSArray<NSString *> *{
        NSMutableArray *out = [NSMutableArray new];
        for (MMWorktree *w in MMRepoIndex.shared.worktrees) if (w.path.length && !w.missing) [out addObject:w.path];
        return out;
    };
    gClutterToken = [NSNotificationCenter.defaultCenter addObserverForName:MMClutterDidChangeNotification object:c queue:nil
                                                                usingBlock:^(NSNotification *n) { [MMGraph.shared rebuild:@"clutter"]; }];
    [c start];
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

    // 1. Store: the log, opened off main, the support folder, what the last run left, and the one migration from
    // the old apps. Opening the log may wait 15 seconds for a lock, so main never does it.
    MMLogOpenOffMain();
    NSString *dir = MMSupportDir();
    dispatch_async(MMQueue(@"core", @"store", QOS_CLASS_UTILITY), ^{
        for (NSString *name in MMRemoveStaleFiles()) os_log(CoreLog(), "removed the old %{public}@", name);
        // The breadcrumbs the last run left, read off main: the first read lists and reads the running folder.
        // On main it was a 130 ms stall in bench hangs on a busy disk, issue #54.
        NSString *crashed = MMBreadcrumbLeftOver();
        if (crashed) os_log(CoreLog(), "the last run ended inside %{public}@", crashed);
    });
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
                [source noteExit:detail];
            }
            source.wantsFreshSample = YES;
            // Issue #52. Exits come in bursts, such as a server and its workers, so one rebuild waits a moment for
            // the rest. When the next pass is due by then, its rebuild drops them. Either way within a second.
            if (changed == MMSignalExit) {
                if (gExitRebuildQueued) return;
                gExitRebuildQueued = YES;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kExitGather * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    gExitRebuildQueued = NO;
                    if (!gStarted) return;
                    NSTimeInterval next = MMSenses.shared.untilNextPass;
                    if (next > 0.05 && next < kExitPassNear) return;   // the pass about to run rebuilds without it
                    [MMGraph.shared rebuild:@"exit"];
                });
                return;
            }
        }
        [MMGraph.shared rebuild:(changed & MMSignalSample) ? @"sample" : @"signal"];
    }];
    [senses start];

    // 3. Know: agent events behind their flag, the session folders' FSEvents watch, the repo index with its own,
    // and the clutter scans.
    [MMAgentEvents.shared start];
    [MMHistory.shared start];   // subagent starts from the events above; each graph build fills the rest
    [MMSessions.shared startWatching];
    gSessionsToken = [NSNotificationCenter.defaultCenter addObserverForName:MMSessionsDidChangeNotification object:MMSessions.shared
                                                                    queue:nil usingBlock:^(NSNotification *n) { [MMGraph.shared rebuild:@"sessions"]; }];
    StartRepos();
    StartClutter();

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
    // The graph first: a build that a sample or a notification started a moment ago publishes nothing after this.
    [MMGraph.shared stop];
    [gSocket stop]; gSocket = nil;
    if (gReviewTimer) { dispatch_source_cancel(gReviewTimer); gReviewTimer = nil; }
    if (gReposTimer) { dispatch_source_cancel(gReposTimer); gReposTimer = nil; }
    [MMRepoIndex.shared stopWatching];
    if (gReposToken) { [NSNotificationCenter.defaultCenter removeObserver:gReposToken]; gReposToken = nil; }
    if (gGitToken) { [NSNotificationCenter.defaultCenter removeObserver:gGitToken]; gGitToken = nil; }
    [MMClutterCatalog.shared stop];
    if (gClutterToken) { [NSNotificationCenter.defaultCenter removeObserver:gClutterToken]; gClutterToken = nil; }
    [MMGraph.shared stopObserving:gGraphToken]; gGraphToken = nil;
    [MMSenses.shared stopObserving:gSensesToken]; gSensesToken = nil;
    [MMSenses.shared stop];
    [MMHistory.shared stop];
    [MMAgentEvents.shared stop];
    [MMSessions.shared stopWatching];
    if (gSessionsToken) { [NSNotificationCenter.defaultCenter removeObserver:gSessionsToken]; gSessionsToken = nil; }
    [gWatchedExits removeAllObjects];
    os_log(CoreLog(), "Core stopped");
}
