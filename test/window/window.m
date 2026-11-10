// Checks for the menu window's feed and Fix Everything's runner, issue #62. test/window.sh builds this with all of
// Sources/Core, the feed and runner files of Sources/Shell, and the plain model of Sources/UI/Window.
// The fixture helpers are test/performance/performance.m's own: its fake sample, worktrees, git facts, sessions,
// agents and experts. That file is included below with its main renamed, so the two sections share one world maker.
// Here the facts have the shape the real experts write, and the actions act: on files this tool made inside the
// fixture folder, through MMUndo, so a trashed file lands in $MINMACS_HOME/Trash. A stop or a quit only writes its
// key to a list. No process starts, and no server, worktree, cache or app outside the fixture folder is read.
// Usage: window <fixture dir> model | calm | run | stop
#define main PerformanceMain
#import "../performance/performance.m"
#undef main
#import "Shell/MMWindowFeed.h"
#import "Shell/MMWindowJSON.h"
#import "Shell/MMFixRunner.h"

#pragma mark - Experts whose actions act on fixtures

static NSMutableArray<NSString *> *gRan;        // the finding id of each action that ran, in order
static NSMutableSet<NSString *> *gNowKept;      // finding ids the fresh check keeps: they changed since the snapshot

@interface WAction : TAction
@end
@implementation WAction
- (BOOL)perform:(MMUndoRecord *)record error:(NSString **)error {
    MMFinding *f = self.finding;
    @synchronized (gRan) { [gRan addObject:f.findingID]; }
    NSString *verb = f.proposal.verb;
    // A stop, a quit or a tab close ends nothing here. Only a removal touches the disk, and only inside the fixtures.
    if (![verb isEqualToString:@"remove"]) return YES;
    if (![f.path hasPrefix:gDir]) { if (error) *error = @"not a fixture path"; return NO; }
    if ([f.kind isEqualToString:@"worktree"]) {
        NSString *err = nil;
        if (![MMUndo.shared recover:@[@".env"] from:f.path record:record error:&err]) { if (error) *error = err; return NO; }
    }
    NSError *e = nil;
    if (![MMUndo.shared trash:[NSURL fileURLWithPath:f.path] record:record error:&e]) { if (error) *error = e.localizedDescription; return NO; }
    return YES;
}
@end

/// Keeps what the facts say to keep and what changed since the snapshot. It has a mode rule, as the real ones do.
@interface WPolicy : TPolicy
@end
@implementation WPolicy
- (NSString *)workKeeps:(MMFinding *)f facts:(MMFacts *)facts {
    if ([gNowKept containsObject:f.findingID]) return @"it is in use now";
    return [super workKeeps:f facts:facts];
}
- (NSString *)modeKeeps:(MMFinding *)f mode:(MMMode)m review:(MMReview *)r { return nil; }
@end

@interface WLidPrefs : NSObject
@property BOOL lid;
@end
@implementation WLidPrefs @end
/// The keys of MMINState that the lid switch reads.
@interface WLidState : NSObject
@property WLidPrefs *prefs; @property NSString *pauseReason, *lidProblem; @property BOOL lidLive, otherApp, laptop;
@end
@implementation WLidState @end

@interface WExpert : TExpert
@property WLidState *state;
@end
@implementation WExpert
- (id<MMExpertPolicy>)policy { static WPolicy *p; static dispatch_once_t once; dispatch_once(&once, ^{ p = [WPolicy new]; }); return p; }
- (id<MMAction>)actionFor:(MMFinding *)f step:(MMStopStep)step {
    if (!f.proposal) return nil;
    WAction *a = [WAction new]; a.finding = f; return a;
}
- (NSArray<MMWrapUpPart *> *)wrapUpParts:(MMWrapUpSubject *)subject snapshot:(MMSnapshot *)s {
    NSMutableArray *out = [NSMutableArray new];
    for (MMWrapUpPart *p in [super wrapUpParts:subject snapshot:s]) {
        WAction *a = [WAction new]; a.finding = p.action.finding;
        [out addObject:[MMWrapUpPart step:p.step expert:p.expert title:p.title action:a policy:[self policy]]];
    }
    return out;
}
@end

static WExpert *gLid;

static void RegisterW(void) {
    for (NSString *e in @[@"locohost", @"minmacs", @"workforest", @"noonoo", @"insomnia"]) {
        WExpert *x = [WExpert new]; x.eid = e; MMRegisterExpert(x);
        if ([e isEqualToString:@"insomnia"]) gLid = x;
    }
}

/// Fresh facts are the snapshot's own: nothing in this world moves but gNowKept.
@interface WSource : NSObject <MMFactSource>
@property MMFacts *facts;
@end
@implementation WSource
- (MMFacts *)factsFor:(uint64_t)generation { return self.facts; }
- (MMFacts *)freshFactsFor:(MMFinding *)finding { return self.facts; }
@end

#pragma mark - The world

static NSString *File(NSString *dir, NSString *name) {
    NSString *p = [Dir(dir) stringByAppendingPathComponent:name];
    [@"fixture\n" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return p;
}

static const uint64_t kDiskTotal = 994ull * 1000 * 1000 * 1000, kDiskFree = 182ull * 1000 * 1000 * 1000;

/// A finished workstream, a merged worktree, servers, an agent that asks, apps, clutter and a tool's own cleanup.
static void World(void) {
    Reset();
    gRan = [NSMutableArray new]; gNowKept = [NSMutableSet new];
    NSString *w1 = Dir(@"trees/fix-auth-redirect"), *w2 = Dir(@"trees/old-spike"), *w3 = Dir(@"repo"), *w4 = Dir(@"trees/wip");
    NSString *lib = Dir(@"library"), *derived = Dir(@"library/DerivedData");
    File(@"trees/old-spike", @".env"); File(@"library/DerivedData", @"index");
    File(@"trees/fix-auth-redirect", @".env"); File(@"trees/fix-auth-redirect/node_modules", @"index.js");
    Tree(w1, NO, MMMergedSquash); Tree(w2, NO, MMMergedAncestor); Tree(w3, YES, MMMergedNone); Tree(w4, NO, MMMergedNone);
    Session(w1);
    Proc(71001, 300 * MB); Proc(71002, 512 * MB); Proc(71003, 100 * MB);
    Proc(71010, 388 * MB); Proc(71011, 200 * MB); Proc(71020, 1536 * MB); Proc(71021, 3 * GB); Proc(71030, 64 * MB);
    gChildren[@71010] = @[@71002];
    Agent(71010, MMAgentWaiting, 900 * MB); Agent(71011, MMAgentWorking, 200 * MB);
    NSNumber *hourAgo = @(NSDate.date.timeIntervalSince1970 - 3600);
    gFindings[@"locohost"] = @[
        Finding(@"locohost", @"server", @"w1#dev", @":3000 Vite fix-auth-redirect", w1, 71001, 300 * MB, 0, P(@"stop", MMReversibleRestart),
                @{@"port": @3000, @"framework": @"Vite", @"project": @"fix-auth-redirect", @"state": @"idle", @"lastActive": hourAgo, @"uptimeSeconds": @7200}),
        Finding(@"locohost", @"server", @"app#dev", @":3001 Next.js app", Dir(@"app"), 71002, 512 * MB, 0, P(@"stop", MMReversibleRestart),
                @{@"port": @3001, @"framework": @"Next.js", @"project": @"app", @"state": @"idle", @"where": @"Ghostty, tab 2", @"agent": @"Claude Code",
                  @"lastActive": hourAgo, @"uptimeSeconds": @86400}),
        Finding(@"locohost", @"server", @"db", @":5432 Postgres db", Dir(@"db"), 71003, 100 * MB, 0, P(@"stop", MMReversibleRestart),
                @{@"port": @5432, @"framework": @"Postgres", @"project": @"db", @"state": @"active", @"protected": @YES, @"keep": @"protected"})];
    gFindings[@"minmacs"] = @[
        Finding(@"minmacs", @"agent", @"claude-code:s-71010", @"Tune the ranking", nil, 71010, 900 * MB, 0, nil,
                @{@"harnessID": @"claude-code", @"name": @"Tune the ranking", @"state": @"waits on you", @"project": Dir(@"app"), @"why": @"a permission prompt is open"}),
        Finding(@"minmacs", @"agent", @"claude-code:s-71011", @"Write the tests", nil, 71011, 200 * MB, 0, nil,
                @{@"harnessID": @"claude-code", @"name": @"Write the tests", @"state": @"working", @"project": Dir(@"app")}),
        Finding(@"minmacs", @"app", @"com.example.chat", @"Chat", nil, 71020, 1536 * MB, 0, P(@"quit", MMReversibleRelaunch),
                @{@"bundleID": @"com.example.chat", @"name": @"Chat", @"group": @"quit"}),
        Finding(@"minmacs", @"app", @"com.example.editor", @"Editor", nil, 71021, 3 * GB, 0, nil,
                @{@"bundleID": @"com.example.editor", @"name": @"Editor", @"group": @"spared", @"reason": @"an agent works in it", @"agent": @"Claude Code"})];
    gParts[w1] = @[
        Finding(@"minmacs", @"helper", [w1 stringByAppendingString:@"#chrome-headless"], @"chrome-headless", w1, 71030, 64 * MB, 0,
                P(@"stop", MMReversibleRestart), @{@"name": @"chrome-headless", @"cwd": w1, @"worktree": w1}),
        Finding(@"minmacs", @"tabs", [w1 stringByAppendingString:@"#com.example.browser"], @"Browser", nil, 0, 0, 0,
                P(@"close-tabs", MMReversibleRelaunch), @{@"bundleID": @"com.example.browser", @"name": @"Browser", @"ports": @[@3000], @"worktree": w1,
                                                         @"urls": @[@"http://localhost:3000/", @"http://localhost:3000/a", @"http://127.0.0.1:3000/b"]})];
    NSDictionary *(^tree)(NSString *, id, NSInteger, NSInteger) = ^(NSString *path, id merged, NSInteger dirty, NSInteger unpushed) {
        return @{@"path": path, @"branch": path.lastPathComponent, @"merged": merged, @"dirty": @(dirty), @"untracked": @0,
                 @"unpushed": @(unpushed), @"quietDays": @12.5};
    };
    gFindings[@"workforest"] = @[
        Finding(@"workforest", @"worktree", w1, @"repo/fix-auth-redirect", w1, 0, 0, 2500 * MB, P(@"remove", MMReversibleRestart), tree(w1, @"squash", 0, 0)),
        Finding(@"workforest", @"worktree", w2, @"repo/old-spike", w2, 0, 0, 5 * GB, P(@"remove", MMReversibleRestart), tree(w2, @"ancestor", 0, 0)),
        Finding(@"workforest", @"worktree", w3, @"repo", w3, 0, 0, 10 * GB, nil, tree(w3, NSNull.null, 0, 0)),
        Finding(@"workforest", @"worktree", w4, @"repo/wip", w4, 0, 0, 1 * GB, P(@"remove", MMReversibleRestart), tree(w4, NSNull.null, 3, 2))];
    gFindings[@"noonoo"] = @[
        Finding(@"noonoo", @"clutter", @"node_modules:w1", @"node_modules", [w1 stringByAppendingPathComponent:@"node_modules"], 0, 0, 1229 * MB,
                P(@"remove", MMReversibleTrash), @{@"kindTitle": @"node_modules", @"name": @"node_modules", @"state": @"free", @"owner": @"fix-auth-redirect"}),
        Finding(@"noonoo", @"clutter", @"derived-data", @"DerivedData", derived, 0, 0, 14 * GB, P(@"remove", MMReversibleTrash),
                @{@"kindTitle": @"Xcode build output", @"name": @"DerivedData", @"state": @"free", @"lastUsed": hourAgo}),
        Finding(@"noonoo", @"clutter", @"pnpm-store", @"pnpm store", [lib stringByAppendingPathComponent:@"pnpm"], 0, 0, 6 * GB,
                P(@"clean", MMReversibleToolCommand), @{@"kindTitle": @"pnpm store", @"name": @"pnpm store", @"state": @"free"}),
        Finding(@"noonoo", @"clutter", @"sims", @"Simulators", [lib stringByAppendingPathComponent:@"Sims"], 0, 0, 3 * GB, nil,
                @{@"kindTitle": @"Simulators", @"name": @"Simulators", @"state": @"live"})];
    gFindings[@"insomnia"] = @[];
}

/// The hour a real snapshot carries: the Mac, the disk and one agent's tree.
static MMHistoryView *WorldHour(void) {
    MMHistory *h = [MMHistory new];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    [h noteMacCPU:10 memoryUsed:8 * GB diskFree:kDiskFree at:now];
    MMHistoryTreeSample *t = [MMHistoryTreeSample new];
    t.kind = MMHistoryAgent; t.key = (MMProcKey){ 71010, 7 }; t.cpuPercent = 20; t.footprint = 900 * MB; t.state = MMAgentWaiting;
    t.label = @"claude-code"; t.ident = @"s-71010";
    [h noteTrees:@[t] at:now];
    return [h viewAt:now];
}

static MMSnapshot *WorldSnapshot(void) {
    MMSnapshot *s = Snapshot(kDiskTotal, kDiskFree, 1);
    [s setValue:WorldHour() forKey:@"history"];
    WSource *src = [WSource new]; src.facts = s.facts;
    MMGraph.shared.source = src;
    return s;
}

static MMPerformance *Build(MMSnapshot *s) {
    __block MMPerformance *p;
    dispatch_sync(MMQueue(@"windowtest", @"build", QOS_CLASS_USER_INITIATED), ^{ p = [MMPerformance from:s history:s.history lookBack:nil]; });
    return p;
}

static NSArray<MMWindowRow *> *Rows(MMWindowModel *m) {
    NSMutableArray *a = [NSMutableArray new];
    for (MMWindowGroup *g in [m.memoryGroups arrayByAddingObjectsFromArray:m.diskGroups]) [a addObjectsFromArray:g.rows];
    return a;
}

/// Every string the window shows, so the checks can read them for words that must not be there.
static NSArray<NSString *> *Shown(MMWindowModel *m) {
    NSMutableArray *a = [NSMutableArray new];
    void (^add)(NSString *) = ^(NSString *s) { if (s.length) [a addObject:s]; };
    add(m.asks); add(m.memoryHour.title); add(m.memoryHour.explain); add(m.diskHour.title); add(m.diskHour.explain);
    for (MMWindowGroup *g in [m.memoryGroups arrayByAddingObjectsFromArray:m.diskGroups]) add(g.title);
    for (MMWindowRow *r in Rows(m)) { add(r.name); add(r.state); for (MMWindowFact *f in r.facts) { add(f.label); add(f.value); } }
    for (MMWindowFix *f in m.fixes) add(f.title);
    add(m.run.step); add(m.run.endTitle); add(m.run.endNote);
    for (MMWindowRule *r in m.settings.rules) { add(r.title); add(r.note); for (MMWindowChoice *c in r.choices) { add(c.title); add(c.explain); } }
    for (MMWindowSwitch *w in m.settings.switches) { add(w.title); add(w.note); }
    return a;
}

static NSString *Bad(NSArray<NSString *> *shown) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"locohost|workforest|noo-?noo|insomnia|is clean|all good|for good|everything is fine"
                                                                        options:NSRegularExpressionCaseInsensitive error:nil];
    NSMutableArray *bad = [NSMutableArray new];
    for (NSString *s in shown) if ([re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)]) [bad addObject:s];
    return [bad componentsJoinedByString:@" | "];
}

#pragma mark - The model

static void WindowModel(void) {
    World();
    MMSetMode(@"locohost", MMModeEager); MMSetMode(@"minmacs", MMModeIdle);
    WLidState *lid = [WLidState new]; lid.prefs = [WLidPrefs new]; lid.prefs.lid = YES; lid.laptop = YES; lid.pauseReason = @"battery under 20%";
    gLid.state = lid;
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, [MMWindowExtras readWithLogin:YES]);
    NSDictionary *j = m.json;

    // The groups and their order.
    NSString *(^titles)(NSArray<MMWindowGroup *> *) = ^(NSArray<MMWindowGroup *> *gs) {
        NSMutableArray *a = [NSMutableArray new];
        for (MMWindowGroup *g in gs) [a addObject:[NSString stringWithFormat:@"%@=%@:%lu", g.key, g.title, (unsigned long)g.rows.count]];
        return [a componentsJoinedByString:@" "];
    };
    T(@"window: memory groups, in order, with their rows", @"servers=Servers:3 agents=Agents:2 apps=Apps and helpers:4", titles(m.memoryGroups));
    T(@"window: disk groups, in order, with their rows", @"worktrees=Worktrees:4 caches=Caches:4", titles(m.diskGroups));
    BOOL sides = YES, sorted = YES;
    for (MMWindowGroup *g in m.memoryGroups) if (g.side != MMWindowMemory) sides = NO;
    for (MMWindowGroup *g in m.diskGroups) if (g.side != MMWindowDisk) sides = NO;
    for (MMWindowGroup *g in [m.memoryGroups arrayByAddingObjectsFromArray:m.diskGroups])
        for (NSUInteger i = 1; i < g.rows.count; i++) if (g.rows[i - 1].bytes < g.rows[i].bytes) sorted = NO;
    T(@"window: each group sits on its side, rows biggest first", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN(sides), YN(sorted)]);
    T(@"window: apps, helpers and tabs share a group and keep their kinds", @"app,app,helper,tabs",
      [[[m.memoryGroups[2].rows valueForKey:@"json"] valueForKey:@"kind"] componentsJoinedByString:@","]);

    // The rows.
    NSSet *keys = [NSSet setWithArray:[Rows(m) valueForKey:@"key"]];
    NSMutableSet *want = [NSMutableSet new];
    for (MMPerformanceGroup *g in [p.memoryGroups arrayByAddingObjectsFromArray:p.diskGroups]) [want addObjectsFromArray:[g.rows valueForKey:@"key"]];
    T(@"window: every row has its own key, the Performance row's", @"17 yes", [NSString stringWithFormat:@"%lu %@", (unsigned long)keys.count,
      YN([keys isEqualToSet:want] && keys.count == Rows(m).count)]);
    T(@"window: a server is named by its port and framework", @":3001 Next.js,:3000 Vite,:5432 Postgres", [[m.memoryGroups[0].rows valueForKey:@"name"] componentsJoinedByString:@","]);
    T(@"window: an agent by its name, a worktree by its branch", @"Tune the ranking | fix-auth-redirect",
      [NSString stringWithFormat:@"%@ | %@", m.memoryGroups[1].rows[0].name, [m row:[@"workforest:worktree:" stringByAppendingString:Dir(@"trees/fix-auth-redirect")]].name]);
    MMWindowRow *next = [m row:@"locohost:server:app#dev"], *db = [m row:@"locohost:server:db"], *asks = [m row:@"minmacs:agent:claude-code:s-71010"];
    MMWindowRow *chat = [m row:@"minmacs:app:com.example.chat"], *editor = [m row:@"minmacs:app:com.example.editor"];
    MMWindowRow *wip = [m row:[@"workforest:worktree:" stringByAppendingString:Dir(@"trees/wip")]], *spike = [m row:[@"workforest:worktree:" stringByAppendingString:Dir(@"trees/old-spike")]];
    MMWindowRow *sims = [m row:@"noonoo:clutter:sims"], *tabs = nil, *helper = nil;
    for (MMWindowRow *r in m.memoryGroups[2].rows) { if (r.kind == MMWindowTabs) tabs = r; if (r.kind == MMWindowHelper) helper = r; }
    T(@"window: icon hints are the framework, the harness and the bundle id", @"Next.js claude-code com.example.chat com.example.browser",
      [NSString stringWithFormat:@"%@ %@ %@ %@", next.iconHint, asks.iconHint, chat.iconHint, tabs.iconHint]);
    T(@"window: one quiet word where a fact gives one", @"idle kept asks will close kept changed merged in use left behind",
      [@[next.state ?: @"-", db.state ?: @"-", asks.state ?: @"-", chat.state ?: @"-", editor.state ?: @"-", wip.state ?: @"-", spike.state ?: @"-",
         sims.state ?: @"-", helper.state ?: @"-"] componentsJoinedByString:@" "]);
    T(@"window: a row with no such fact has no word", @"(nil)", [m row:[@"workforest:worktree:" stringByAppendingString:Dir(@"repo")]].state);
    T(@"window: a tabs row counts tabs and holds no bytes", @"3 0", [NSString stringWithFormat:@"%ld %llu", (long)tabs.tabs, tabs.bytes]);
    T(@"window: the agent that asks needs you, and only it", @"1", @([[Rows(m) filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"needsYou == YES"]] count]));
    T(@"window: needsYou sits on the asking agent", @"yes", YN(asks.needsYou));
    T(@"window: CPU is unknown where Core has no reading", @"-1 -1", [NSString stringWithFormat:@"%g %g", next.cpuPercent, spike.cpuPercent]);
    T(@"window: only an agent or a server whose tree Core follows has an hour", @"60 no no", [NSString stringWithFormat:@"%lu %@ %@",
      (unsigned long)asks.hour.count, YN(next.hour != nil), YN(spike.hour != nil || chat.hour != nil)]);
    T(@"window: the row's hour ends on its newest minute, in bytes", @(900 * MB), asks.hour.lastObject);
    NSString *(^story)(MMWindowRow *) = ^(MMWindowRow *r) {
        NSMutableArray *a = [NSMutableArray new];
        for (MMWindowFact *f in r.facts) [a addObject:[NSString stringWithFormat:@"%@=%@", f.label, f.value]];
        return [a componentsJoinedByString:@"; "];
    };
    T(@"window: a server's story", @"Port=3001; Project=app; Runs in=Ghostty, tab 2; Started by=Claude Code; Idle=1h; Up=1d", story(next));
    T(@"window: an agent's story", @"Project=app; State=waits on you; Why=a permission prompt is open", story(asks));
    T(@"window: a kept app's story says why it stays", @"Used by=Claude Code; Stays=an agent works in it", story(editor));
    T(@"window: a worktree's story", [NSString stringWithFormat:@"Branch=wip; Files=3 changed; Not pushed=2 commits; Quiet=12d; Folder=%@", Dir(@"trees/wip").stringByAbbreviatingWithTildeInPath], story(wip));

    // The asks line.
    T(@"window: the asks line", @"1 agent asks you", m.asks);

    // The ring and the hours. Memory and disk are two numbers.
    T(@"window: the ring's memory is the Performance model's", @"yes", YN(m.ring.memoryUsed == p.memory.used && m.ring.memoryTotal == p.memory.total));
    T(@"window: the ring's disk is free and total", @"182 994", [NSString stringWithFormat:@"%llu %llu", m.ring.diskFree / 1000000000, m.ring.diskTotal / 1000000000]);
    T(@"window: memory slices in ring order", @"servers,agents,apps,other", [[m.ring.memory valueForKey:@"group"] componentsJoinedByString:@","]);
    T(@"window: disk slices in ring order", @"worktrees,caches,other", [[m.ring.disk valueForKey:@"group"] componentsJoinedByString:@","]);
    uint64_t ms = 0, ds = 0;
    for (MMWindowSlice *x in m.ring.memory) ms += x.bytes;
    for (MMWindowSlice *x in m.ring.disk) ds += x.bytes;
    T(@"window: the slices of each side add up to what is used", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN(ms == m.ring.memoryUsed), YN(ds == m.ring.diskTotal - m.ring.diskFree)]);
    T(@"window: the helpers' part is in the apps slice", @(([p.memory.parts[MMPerformanceApps] unsignedLongLongValue] + [p.memory.parts[MMPerformanceHelpers] unsignedLongLongValue])), @(m.ring.memory[2].bytes));
    NSString *total = [NSString stringWithFormat:@"%.0f GB", round((double)NSProcessInfo.processInfo.physicalMemory / (double)GB)];
    T(@"window: the memory hour, with the Mac's real total", [NSString stringWithFormat:@"Memory in use | Higher means more of the %@ is in use | 60", total],
      [NSString stringWithFormat:@"%@ | %@ | %lu", m.memoryHour.title, m.memoryHour.explain, (unsigned long)m.memoryHour.values.count]);
    T(@"window: the disk hour, with the disk's real size", @"Disk free | Lower means less room left on the 994 GB disk | 60",
      [NSString stringWithFormat:@"%@ | %@ | %lu", m.diskHour.title, m.diskHour.explain, (unsigned long)m.diskHour.values.count]);
    T(@"window: a minute with no value is null, the newest is bytes", @"yes yes", [NSString stringWithFormat:@"%@ %@",
      YN(m.memoryHour.values[0] == NSNull.null), YN([m.memoryHour.values[59] isEqual:@(8 * GB)])]);
    NSString *w = Words(j);
    uint64_t sums[] = { m.ring.memoryUsed + (m.ring.diskTotal - m.ring.diskFree), m.ring.memoryTotal + m.ring.diskTotal,
                        m.ring.memoryUsed + m.ring.diskFree, m.memoryBack + m.diskBack };
    BOOL summed = NO;
    for (int i = 0; i < 4; i++) if ([w rangeOfString:[NSString stringWithFormat:@":%llu", sums[i]]].location != NSNotFound) { summed = YES; Info([NSString stringWithFormat:@"sum %d is in the JSON: %llu", i, sums[i]]); }
    for (MMWindowFix *f in m.fixes)
        if (f.memoryBack && f.diskBack && [w rangeOfString:[NSString stringWithFormat:@":%llu", f.memoryBack + f.diskBack]].location != NSNotFound) { summed = YES; Info([@"a fix's sum is in the JSON: " stringByAppendingString:f.title]); }
    T(@"window: memory and disk are never summed into one number", @"no", YN(summed));

    // The fixes.
    T(@"window: the fixes are the Performance model's, in its order", [[p.fixes valueForKey:@"key"] componentsJoinedByString:@","], [[m.fixes valueForKey:@"key"] componentsJoinedByString:@","]);
    T(@"window: each fix has a title in plain words",
      @"Clean pnpm store | Move 1 leftover to the Trash | Quit 1 app | Remove 1 merged worktree | Stop 1 idle server | Wrap Up fix-auth-redirect",
      [[[m.fixes valueForKey:@"title"] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" | "]);
    uint64_t mb = 0, db2 = 0; NSInteger n = 0, needs = 0;
    for (MMPerformanceFix *f in p.fixes) { if (f.needsYou) { needs++; continue; } n++; mb += f.memoryBack; db2 += f.diskBack; }
    T(@"window: Fix Everything counts the fixes that need no press of their own, each side apart", [NSString stringWithFormat:@"%ld %llu %llu 1", (long)n, mb, db2],
      [NSString stringWithFormat:@"%ld %llu %llu %ld", (long)m.fixCount, m.memoryBack, m.diskBack, (long)needs]);
    NSMutableSet *marked = [NSMutableSet new], *touched = [NSMutableSet new];
    for (MMWindowRow *r in Rows(m)) if (r.inFix) [marked addObject:r.key];
    for (MMPerformanceFix *f in p.fixes) [touched addObjectsFromArray:f.rows];
    T(@"window: inFix marks the rows the fixes touch, and no other", @"yes 10", [NSString stringWithFormat:@"%@ %lu", YN([marked isEqualToSet:touched]), (unsigned long)marked.count]);

    // Settings.
    MMWindowSettings *st = m.settings;
    T(@"window: one rule per expert that has modes", @"servers,apps,worktrees,caches", [[st.rules valueForKey:@"ruleID"] componentsJoinedByString:@","]);
    BOOL three = YES;
    for (MMWindowRule *r in st.rules) {
        if (![[[r.choices valueForKey:@"title"] componentsJoinedByString:@","] isEqualToString:@"Off,Careful,Eager"]) three = NO;
        for (MMWindowChoice *c in r.choices) if (!c.explain.length) three = NO;
    }
    T(@"window: each rule has three choices, each with what it does", @"yes", YN(three));
    T(@"window: picked follows each expert's mode", @"2,0,1,1", [[st.rules valueForKey:@"picked"] componentsJoinedByString:@","]);
    T(@"window: a rule that is off says what waits for the press", @"1 ready. It waits for your press.", st.rules[1].note);
    T(@"window: a rule maps back to its expert", @"locohost minmacs workforest noonoo (null)", [NSString stringWithFormat:@"%@ %@ %@ %@ %@",
      MMWindowRuleExpert(@"servers"), MMWindowRuleExpert(@"apps"), MMWindowRuleExpert(@"worktrees"), MMWindowRuleExpert(@"caches"), MMWindowRuleExpert(@"icons")]);
    T(@"window: the switches are the lid and Open at login, and no other", @"lid=Keep working with the lid closed:1,login=Open at login:1", ({
        NSMutableArray *a = [NSMutableArray new];
        for (MMWindowSwitch *x in st.switches) [a addObject:[NSString stringWithFormat:@"%@=%@:%d", x.switchID, x.title, x.on]];
        [a componentsJoinedByString:@","]; }));
    T(@"window: the lid switch says the guard that pauses it", @"Paused, battery under 20%.", st.switches[0].note);
    lid.pauseReason = nil; lid.lidLive = YES;
    T(@"window: and when it is live", @"On now. The Mac keeps running with the lid shut.", [MMWindowExtras readWithLogin:NO].lidNote);
    gLid.state = nil;
    T(@"window: before the first pass the lid switch reads the pref", @"no", YN([MMWindowExtras readWithLogin:NO].lidOn));

    // The JSON and the words.
    T(@"window: the JSON's keys", @"asks disk diskHour fixEverything fixes generation memory memoryHour ring run settings",
      [[j.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]);
    T(@"window: a row's JSON keys", @"bytes cpuPercent facts hour iconHint inFix key kind name needsYou state tabs",
      [[[next.json allKeys] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]);
    T(@"window: the JSON is valid and keeps the ring's sides apart", @"yes disk memory", [NSString stringWithFormat:@"%@ %@", YN([NSJSONSerialization isValidJSONObject:j]),
      [[[j[@"ring"] allKeys] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]]);
    T(@"window: no shown string names an old app or claims a result", @"", Bad(Shown(m)));
    MMSetMode(@"locohost", MMModeProactive); MMSetMode(@"minmacs", MMModeProactive);
}

static void WindowCalm(void) {
    World();
    for (NSString *e in gFindings.allKeys) {
        NSMutableArray *a = [NSMutableArray new];
        for (MMFinding *f in gFindings[e]) if (!f.proposal) [a addObject:f];
        gFindings[e] = a;
    }
    [gGit enumerateKeysAndObjectsUsingBlock:^(NSString *k, TGit *g, BOOL *stop) { g.merged = MMMergedNone; }];
    for (TAgent *a in gAgents) a.state = MMAgentWorking;
    MMSnapshot *s = Snapshot(kDiskTotal, kDiskFree, 1);   // built by hand: no history
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, nil);
    T(@"calm: no asks line, no fix, and no row marked", @"(nil) 0 0", [NSString stringWithFormat:@"%@ %ld %lu", m.asks ?: @"(nil)", (long)m.fixCount,
      (unsigned long)[[Rows(m) filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"inFix == YES"]] count]]);
    T(@"calm: before the first fill there is no hour to draw", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN(m.memoryHour == nil), YN(m.diskHour == nil)]);
    T(@"calm: every group is still there", @"3 2", [NSString stringWithFormat:@"%lu %lu", (unsigned long)m.memoryGroups.count, (unsigned long)m.diskGroups.count]);
    T(@"calm: no shown string names an old app or claims a result", @"", Bad(Shown(m)));
    for (TAgent *a in gAgents) a.state = MMAgentWaiting;
    MMSnapshot *s2 = Snapshot(kDiskTotal, kDiskFree, 1);
    T(@"calm: two agents that ask", @"2 agents ask you", MMWindowModelFrom(s2, Build(s2), nil).asks);
}

#pragma mark - The runner

static NSString *Steps(NSArray<MMWindowRun *> *runs) {
    NSMutableArray *a = [NSMutableArray new];
    for (MMWindowRun *r in runs) if (r.step) [a addObject:r.step];
    return [[a sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" | "];
}

static void RunAll(void) {
    World();
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMWindowModel *m = MMWindowModelFrom(s, p, nil);
    NSString *derived = Dir(@"library/DerivedData"), *spike = Dir(@"trees/old-spike");
    // The chat app is in use by the time its turn comes.
    [gNowKept addObject:@"minmacs:app:com.example.chat"];

    MMFixRunner *onMain = [[MMFixRunner alloc] initWithPerformance:p];
    MMWindowRun *refused = [onMain run];
    T(@"run: on the main thread nothing runs", @"0 fixes done 0", [NSString stringWithFormat:@"%@ %lu", refused.endTitle, (unsigned long)gRan.count]);

    MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
    NSMutableArray<MMWindowRun *> *seen = [NSMutableArray new];
    __block BOOL offMain = YES;
    runner.onProgress = ^(MMWindowRun *r) { if (NSThread.isMainThread) offMain = NO; @synchronized (seen) { [seen addObject:r]; } };
    dispatch_semaphore_t ended = dispatch_semaphore_create(0);
    __block MMWindowRun *end = nil;
    void (^inner)(MMWindowRun *) = runner.onProgress;
    runner.onProgress = ^(MMWindowRun *r) { inner(r); if (!r.running) { end = r; dispatch_semaphore_signal(ended); } };
    [runner start];
    long timedOut = dispatch_semaphore_wait(ended, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
    T(@"run: the run ends, off main, on its own labeled queue", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN(!timedOut), YN(offMain)]);
    if (timedOut) return;

    NSArray<MMFixResult *> *res = runner.results;
    NSMutableDictionary<NSString *, NSString *> *by = [NSMutableDictionary new];
    for (MMFixResult *x in res) by[x.name] = x.outcome;
    for (MMFixResult *x in res) if (![x.outcome isEqualToString:@"done"]) Info([NSString stringWithFormat:@"%@ %@: %@", x.outcome, x.name, x.why]);
    T(@"run: each step in plain words", @"Moving DerivedData to the Trash | Quitting Chat | Removing old-spike | Stopping :3001 Next.js | Wrapping up fix-auth-redirect", Steps(seen));
    T(@"run: what each step did", @":3001 Next.js=done Chat=kept DerivedData=done fix-auth-redirect=done old-spike=done", ({
        NSMutableArray *a = [NSMutableArray new];
        for (NSString *k in [by.allKeys sortedArrayUsingSelector:@selector(compare:)]) [a addObject:[NSString stringWithFormat:@"%@=%@", k, by[k]]];
        [a componentsJoinedByString:@" "]; }));
    T(@"run: the thing that changed since the snapshot was kept, and its action never ran", @"no", YN([gRan containsObject:@"minmacs:app:com.example.chat"]));
    T(@"run: the fix that needs your own press was skipped", @"no", YN([gRan containsObject:@"noonoo:clutter:pnpm-store"]));
    T(@"run: the end", @"no 4 5 4 of 5 fixes done", [NSString stringWithFormat:@"%@ %ld %ld %@", YN(end.running), (long)end.done, (long)end.total, end.endTitle]);
    T(@"run: the end note says what was skipped and where deletes went",
      @"Skipped 1 agent that asks you, 1 fix that needs your own press and 1 kept since it changed or is in use. "
      @"Deletes went to the Trash, and files git ignores were saved in a recovery folder.", end.endNote);
    T(@"run: the planned totals are the window's own, each side apart", @"yes", YN(end.memoryPlanned == m.memoryBack && end.diskPlanned == m.diskBack));
    // The server outside the Wrap Up, plus the Wrap Up's server and helper. The kept app gave nothing back.
    T(@"run: memory back counts only what ran", @(512 * MB + 364 * MB), @(end.memoryBack));
    BOOL grew = YES, steady = YES;
    for (NSUInteger i = 1; i < seen.count; i++) {
        if (seen[i].done < seen[i - 1].done || seen[i].memoryBack < seen[i - 1].memoryBack) grew = NO;
        if (seen[i].total != 5 || seen[i].memoryPlanned != end.memoryPlanned) steady = NO;
    }
    T(@"run: progress only grows, and the plan holds still", @"yes yes", [NSString stringWithFormat:@"%@ %@", YN(grew), YN(steady)]);

    // Invariant 1: every step left an undo record by "manual", and what it deleted can come back.
    BOOL records = YES; NSString *trashRid = nil, *treeRid = nil;
    for (MMFixResult *x in res) {
        if (![x.outcome isEqualToString:@"done"]) continue;
        MMUndoRecord *r = x.rid ? [MMUndo.shared record:x.rid] : nil;
        if (!r || r.state != MMUndoDone || ![r.by isEqualToString:@"manual"]) records = NO;
        if ([x.name isEqualToString:@"DerivedData"]) trashRid = x.rid;
        if ([x.name isEqualToString:@"old-spike"]) treeRid = x.rid;
    }
    T(@"run: every step that ran has a finished undo record by manual", @"yes", YN(records));
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *trash = MMTrashFolder();
    T(@"run: the deleted folders left their place for the test Trash", @"no no yes", [NSString stringWithFormat:@"%@ %@ %@", YN([fm fileExistsAtPath:derived]),
      YN([fm fileExistsAtPath:spike]), YN(trash.length && [fm contentsOfDirectoryAtPath:trash error:nil].count >= 2)]);
    MMUndoRecord *tree = treeRid ? [MMUndo.shared record:treeRid] : nil;
    NSString *saved = [tree.payload[@"recovery"] isKindOfClass:NSDictionary.class] ? tree.payload[@"recovery"][@"dir"] : nil;
    T(@"run: the worktree's ignored file is in its recovery folder", @"yes", YN(saved.length && [fm fileExistsAtPath:[saved stringByAppendingPathComponent:@".env"]]));
    __block NSString *problem = @"not run";
    dispatch_sync(MMQueue(@"windowtest", @"restore", QOS_CLASS_USER_INITIATED), ^{ problem = trashRid ? [MMUndo.shared restore:trashRid] : @"no record"; });
    T(@"run: undo brings a deleted folder back", @"(nil) yes", [NSString stringWithFormat:@"%@ %@", problem ?: @"(nil)", YN([fm fileExistsAtPath:[derived stringByAppendingPathComponent:@"index"]])]);
    T(@"run: no shown string names an old app or says for good", @"", Bad(@[end.endTitle ?: @"", end.endNote ?: @"", Steps(seen)]));
}

static void RunStopped(void) {
    World();
    MMSnapshot *s = WorldSnapshot();
    MMPerformance *p = Build(s);
    MMFixRunner *runner = [[MMFixRunner alloc] initWithPerformance:p];
    __weak MMFixRunner *weak = runner;
    __block MMWindowRun *end = nil;
    // The press on the button while the first step plays.
    dispatch_semaphore_t ended = dispatch_semaphore_create(0);
    runner.onProgress = ^(MMWindowRun *r) { if (r.running) [weak stop]; else { end = r; dispatch_semaphore_signal(ended); } };
    [runner start];
    if (dispatch_semaphore_wait(ended, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) { T(@"stop: the run ends", @"yes", @"no"); return; }
    T(@"stop: the step under way finishes, and the rest never start", @"1 1 of 5 fixes done 1", [NSString stringWithFormat:@"%ld %@ %lu", (long)end.done, end.endTitle,
      (unsigned long)[[runner.results filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"outcome == 'done'"]] count]]);
    T(@"stop: the end note counts what you stopped", @"yes", YN([end.endNote containsString:@"4 fixes you stopped"]));
    T(@"stop: the runner can be asked again once it ended", @"no", YN(runner.running));
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: window <dir> model|calm|run|stop\n"); return 2; }
        char real[PATH_MAX];
        [NSFileManager.defaultManager createDirectoryAtPath:@(argv[1]) withIntermediateDirectories:YES attributes:nil error:nil];
        gDir = realpath(argv[1], real) ? @(real) : @(argv[1]);
        // Every path this tool touches is under its fixture folder, which must be inside the test home.
        NSString *home = NSProcessInfo.processInfo.environment[@"MINMACS_HOME"];
        if (!home.length || !realpath(home.fileSystemRepresentation, real) || ![gDir hasPrefix:@(real)]) {
            fprintf(stderr, "window: the fixture folder must be inside MINMACS_HOME\n"); return 2;
        }
        RegisterW();
        NSString *mode = @(argv[2]);
        if ([mode isEqualToString:@"model"]) WindowModel();
        else if ([mode isEqualToString:@"calm"]) WindowCalm();
        else if ([mode isEqualToString:@"run"]) RunAll();
        else if ([mode isEqualToString:@"stop"]) RunStopped();
        else return 2;
        printf("END\n");
    }
    return 0;
}
