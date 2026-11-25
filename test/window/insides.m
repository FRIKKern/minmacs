// An app row's insides: cmux's workspaces, panes and tabs, and what runs in each. Included by window.m.
// The owner asked: "When we press e.g. cmux, an application we should know a lot about, we should have all the
// top-level details in place: its sessions, and what is happening inside each." And D11: "big ambitions for
// understanding significant apps, but strong measures so it doesn't hurt performance."
// cmux here is always test/window/cmux, a fake copied into the fixture folder and named in MINMACS_CMUX. It answers
// with test/window/cmux-top.json, the shape `cmux --json top --all --processes` has in cmux 0.65, and writes one line
// a call, so nothing reaches the real cmux.
#import <objc/runtime.h>
#import "Core/Know/MMAppInsides.h"
#import "Shell/MMWindowControllerInsides.h"

static NSString *gCmux;                                 // the fake's folder
static NSMutableDictionary<NSNumber *, NSString *> *gCwds;

static void CmuxFile(NSString *name, NSString *text) {
    NSString *p = [gCmux stringByAppendingPathComponent:name];
    if (text) [text writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    else [NSFileManager.defaultManager removeItemAtPath:p error:nil];
}
/// The reads of cmux's insides the fake saw. Anything else, such as MMWhere's own `top`, is not counted.
static NSInteger CmuxReads(void) {
    NSString *s = [NSString stringWithContentsOfFile:[gCmux stringByAppendingPathComponent:@"cmux.calls"] encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSInteger n = 0;
    for (NSString *l in [s componentsSeparatedByString:@"\n"]) if ([l hasPrefix:@"--json top --all --processes"]) n++;
    return n;
}

static void CmuxWorld(void) {
    gCmux = Dir(@"cmux");
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *f in @[@"cmux", @"cmux-top.json"]) {
        NSString *to = [gCmux stringByAppendingPathComponent:f];
        [fm removeItemAtPath:to error:nil];
        [fm copyItemAtPath:[@"test/window" stringByAppendingPathComponent:f] toPath:to error:nil];
    }
    setenv("MINMACS_CMUX", [gCmux stringByAppendingPathComponent:@"cmux"].UTF8String, 1);
    CmuxFile(@"cmux.calls", nil); CmuxFile(@"cmux.mode", @"answer");
    [MMAppInsides.shared forget];
    MMAppInsides.shared.limit = 1; MMAppInsides.shared.every = 5;
    // The fake sample reads no folder: here a tab's foreground process says where it runs.
    gCwds = [NSMutableDictionary new];
    method_setImplementation(class_getInstanceMethod(TSample.class, @selector(cwdOf:)),
                             imp_implementationWithBlock(^NSString *(id me, pid_t pid) { return gCwds[@(pid)]; }));
}

static NSData *Fixture(void) { return [NSData dataWithContentsOfFile:[gCmux stringByAppendingPathComponent:@"cmux-top.json"]]; }

static void Named(pid_t pid, NSString *name, double cpu, uint64_t bytes) {
    Proc(pid, bytes);
    gProcs[@(pid)].name = name; gProcs[@(pid)].cpuPercent = cpu;
}

/// The world of window.m with cmux running: its two agents and the :3000 server in its tabs, three idle shells in a
/// workspace of their own, a pane of two tabs, and the worktree the server runs in.
static MMSnapshot *CmuxSnapshot(void) {
    World();
    NSString *w1 = Dir(@"trees/fix-auth-redirect");
    Named(72000, @"cmux", 4.5, 400 * MB);
    NSArray *shells = @[@[@72001, @72002], @[@72003, @72004], @[@72005, @72006], @[@72007, @72009], @[@72011, @72012], @[@72013, @72014], @[@72015, @72016], @[@72021, @72022]];
    NSMutableArray *top = [NSMutableArray new];
    for (NSArray *s in shells) { Named([s[0] intValue], @"login", 0, 0); Named([s[1] intValue], @"zsh", 0, 2 * MB); gChildren[s[0]] = @[s[1]]; [top addObject:s[0]]; }
    gChildren[@72000] = top;
    Named(71010, @"2.1.331", 12.5, 900 * MB); gChildren[@72002] = @[@71010];
    Named(71001, @"node", 3.2, 300 * MB); gChildren[@72004] = @[@71001];
    Named(72008, @"tail", 0.1, 1 * MB); gChildren[@72009] = @[@72008];
    Named(71011, @"2.1.331", 4.0, 200 * MB); gChildren[@72022] = @[@71011];
    gCwds[@71001] = [w1 stringByAppendingPathComponent:@"web"];
    gCwds[@71010] = Dir(@"elsewhere");
    NSMutableArray *mm = [gFindings[@"minmacs"] mutableCopy];
    [mm addObject:Finding(@"minmacs", @"app", MMAppInsidesCmux, @"cmux", nil, 72000, 400 * MB, 0, nil,
                          @{@"bundleID": MMAppInsidesCmux, @"name": @"cmux", @"group": @"spared", @"reason": @"agents work in it"})];
    gFindings[@"minmacs"] = mm;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    gFindings[@"workforest"] = @[Finding(@"workforest", @"worktree", w1, @"repo/fix-auth-redirect", w1, 0, 0, 2500 * MB, nil,
                                         @{@"path": w1, @"repo": Dir(@"repo"), @"branch": @"fix-auth-redirect", @"dirty": @1, @"untracked": @0, @"unpushed": @0, @"lastWorkAt": @(now - 60)})];
    return WorldSnapshot();
}

static MMWindowModel *CmuxModel(MMSnapshot *s, MMInsidesAnswer *a) {
    MMWindowModel *m = MMWindowModelFrom(s, Build(s), nil);
    MMWindowInsidesAttach(m, s, a);
    return m;
}

static MMWindowRow *AppRow(MMWindowModel *m) {
    for (MMWindowGroup *g in m.memoryGroups) for (MMWindowRow *r in g.rows) if (MMWindowInsidesApp(r)) return r;
    return nil;
}

static NSString *Names(NSArray<MMWindowRow *> *rows) {
    NSMutableArray *a = [NSMutableArray new];
    for (MMWindowRow *r in rows) [a addObject:r.name];
    return [a componentsJoinedByString:@" | "];
}
// FactOf, the fact of a row by its label, is collapse.m's.

static MMInsidesAnswer *ReadWith(NSString *mode, NSTimeInterval *took) {
    CmuxFile(@"cmux.mode", mode);
    __block MMInsidesAnswer *a;
    NSDate *t0 = NSDate.date;
    dispatch_sync(MMQueue(@"windowtest", @"insides", QOS_CLASS_USER_INITIATED), ^{ a = [[MMCmuxInsides new] readWithin:1]; });
    if (took) *took = -t0.timeIntervalSinceNow;
    return a;
}

static void Insides(void) {
    CmuxWorld();
    // cmux's answer, parsed: the windows, workspaces, panes and tabs, with their processes and cmux's own words.
    MMInsidesAnswer *a = [MMCmuxInsides parse:Fixture()];
    MMInsidesNode *win = a.root.children.firstObject, *ws = win.children.firstObject, *tab = [ws.children.firstObject children].firstObject;
    NSInteger tabs = 0;
    for (MMInsidesNode *w in win.children) for (MMInsidesNode *p in w.children) tabs += (NSInteger)p.children.count;
    MMInsidesNode *preview = [[win.children[1] children][3] children].firstObject, *docs = [[win.children[1] children][4] children].firstObject;
    T(@"insides: cmux's answer reads as 1 window, 3 workspaces, 10 tabs, its glyph off a tab's title, its foreground agent, cmux's word for it",
      @"found 1 3 10 minmacs Tune the ranking 71010 Waiting 3", [NSString stringWithFormat:@"%@ %lu %lu %ld %@ %@ %d %@ %lu", a.json[@"known"], (unsigned long)a.root.children.count,
      (unsigned long)win.children.count, (long)tabs, ws.title, tab.title, tab.pid, tab.status, (unsigned long)tab.pids.count]);
    T(@"insides: a browser tab keeps an address on this Mac and drops any other", @"http://localhost:3001/ none",
      [NSString stringWithFormat:@"%@ %@", preview.url, docs.url ?: @"none"]);
    T(@"insides: an answer that is no JSON, or has no windows, is an older cmux", @"older older older",
      [NSString stringWithFormat:@"%@ %@ %@", [MMCmuxInsides parse:[@"cmux 0.40" dataUsingEncoding:NSUTF8StringEncoding]].json[@"known"],
       [MMCmuxInsides parse:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]].json[@"known"], [MMCmuxInsides parse:nil].json[@"known"]]);
    T(@"insides: one call asks for the whole tree, read only", @"--json top --all --processes", [MMCmuxInsides.arguments componentsJoinedByString:@" "]);

    // The reader through the fake: an answer, a socket that is not there, an older cmux, no CLI, and one that hangs.
    NSTimeInterval took = 0;
    MMInsidesAnswer *ok = ReadWith(@"answer", NULL), *sock = ReadWith(@"socket", NULL), *old = ReadWith(@"old", NULL), *junk = ReadWith(@"garbage", NULL);
    MMInsidesAnswer *hang = ReadWith(@"sleep", &took);
    T(@"insides: through the fake, found; no socket and a hang are unreachable within the 1 s limit; an older cmux and junk are older",
      @"found unreachable older older unreachable yes", [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", ok.json[@"known"], sock.json[@"known"], old.json[@"known"],
      junk.json[@"known"], hang.json[@"known"], YN(took < 3)]);
    T(@"insides: each says why in one line", @"cmux did not answer on its socket, so MinMacs cannot look inside it. | This cmux is older than what MinMacs reads. Its own process tree shows instead. | cmux did not answer within 1 s.",
      [NSString stringWithFormat:@"%@ | %@ | %@", sock.why, old.why, hang.why]);
    setenv("MINMACS_CMUX", [gCmux stringByAppendingPathComponent:@"no-such-cmux"].UTF8String, 1);
    MMInsidesAnswer *none = ReadWith(@"answer", NULL);
    setenv("MINMACS_CMUX", [gCmux stringByAppendingPathComponent:@"cmux"].UTF8String, 1);
    T(@"insides: with no cmux CLI, unreachable, and it says so", @"unreachable cmux's command line is not there, so MinMacs cannot look inside it.",
      [NSString stringWithFormat:@"%@ %@", none.json[@"known"], none.why]);
    CmuxFile(@"cmux.mode", @"answer");
    CmuxFile(@"cmux.calls", nil);

    // The model: the cmux row holds its workspaces, busiest first, each tab with its agent, worktree and servers.
    MMSnapshot *s = CmuxSnapshot();
    MMWindowModel *m = CmuxModel(s, a);
    MMWindowRow *app = AppRow(m);
    NSArray<MMWindowRow *> *spaces = MMWindowRowInsides(app);
    T(@"insides: the cmux row holds its 3 workspaces, the one that asks first and the idle one last", @"minmacs | Agent story | scratch", Names(spaces));
    MMWindowRow *mine = spaces.firstObject;
    NSArray<MMWindowRow *> *kids = MMWindowRowInsides(mine);
    T(@"insides: a workspace holds its tabs busiest first, its pane of two tabs as one row", @"Tune the ranking | dev server | Pane with 2 tabs", Names(kids));
    MMWindowRow *agentTab = kids.firstObject, *agentRow = [m row:@"minmacs:agent:claude-code:s-71010"], *inTree = MMWindowRowInsides(agentTab).firstObject;
    T(@"insides: a tab with an agent holds that agent's own row: the same key, name and state, so hover and active are one",
      @"yes yes yes yes", [NSString stringWithFormat:@"%@ %@ %@ %@", YN([inTree.key isEqualToString:agentRow.key]), YN([inTree.name isEqualToString:agentRow.name]),
      YN(inTree.state == agentRow.state || [inTree.state isEqualToString:agentRow.state]), YN(agentTab.needsYou == agentRow.needsYou)]);
    T(@"insides: the agent's tab says its agent with its state, links to its row, and has Go to", @"yes cmux yes",
      [NSString stringWithFormat:@"%@ %@ %@", YN([FactOf(agentTab, @"Agent").link isEqualToString:agentRow.key]), agentTab.goTo, YN(FactOf(agentTab, @"Runs in") != nil)]);
    NSMutableArray *agentMenu = [NSMutableArray new], *copyMenu = [NSMutableArray new];
    for (MMWindowMenuItem *i in agentRow.menu) [agentMenu addObject:i.action];
    for (MMWindowMenuItem *i in inTree.menu) [copyMenu addObject:i.action];
    T(@"insides: right-click: the agent under its tab has the agent's own menu, a tab and a workspace have Go to, a pane none",
      @"yes go-to go-to none", [NSString stringWithFormat:@"%@ %@ %@ %@", YN(agentMenu.count > 0 && [agentMenu isEqualToArray:copyMenu]), agentTab.menu.firstObject.action,
      mine.menu.firstObject.action, kids[2].menu.count ? @"some" : @"none"]);
    MMWindowRow *dev = kids[1], *srv = [m row:@"locohost:server:w1#dev"];
    NSString *w1 = Dir(@"trees/fix-auth-redirect");
    T(@"insides: the server's tab links its worktree and its server, holds the server's own row, and counts its processes from MinMacs's sample",
      @"yes yes yes 302.0 MB", [NSString stringWithFormat:@"%@ %@ %@ %.1f MB", YN([FactOf(dev, @"Worktree").link isEqualToString:[@"workforest:worktree:" stringByAppendingString:w1]]),
      YN([FactOf(dev, @"Server").link isEqualToString:srv.key]), YN([MMWindowRowInsides(dev).firstObject.key isEqualToString:srv.key]), dev.bytes / (double)MB]);
    MMWindowRow *scratch = spaces.lastObject;
    MMWindowRow *idle = nil;
    for (MMWindowRow *r in MMWindowRowInsides(scratch)) if ([r.key hasSuffix:@":idle"]) idle = r;
    T(@"insides: three shells that only wait are one row, \"3 idle shells\", that opens onto them", @"3 idle shells 3 yes",
      [NSString stringWithFormat:@"%@ %lu %@", idle.name, (unsigned long)MMWindowRowInsides(idle).count, YN(idle.quiet)]);
    T(@"insides: every row of the tree is found by its key", @"yes yes yes", [NSString stringWithFormat:@"%@ %@ %@", YN([m row:mine.key] == mine), YN([m row:dev.key] == dev),
      YN([m row:MMWindowRowInsides(idle).firstObject.key] != nil)]);
    // The story's section, under the usual header.
    NSMutableArray *told = [NSMutableArray new];
    for (MMWindowFact *f in app.facts) [told addObject:[NSString stringWithFormat:@"%@: %@", f.label, f.value]];
    NSString *story = [told componentsJoinedByString:@" | "];
    T(@"insides: the cmux row's story says its workspaces, agents and idle shells, then each workspace with its busy tabs",
      @"yes yes yes", [NSString stringWithFormat:@"%@ %@ %@", YN([story containsString:@"Inside: 3 workspaces, 2 agents in them, 3 idle shells"]),
      YN([story containsString:@"Workspace: minmacs · 4 tabs"]), YN([story containsString:@"Tab: dev server · node"])]);
    // --json: BarkBot reads the tree from the cmux row.
    NSDictionary *j = app.json[@"insides"];
    NSDictionary *jt = [j[@"workspaces"] firstObject][@"children"][0];
    T(@"insides: --json holds the tree on the cmux row, each tab with its agent, folder and the handles Go to uses", @"found 3 tab minmacs:agent:claude-code:s-71010 surface:1 workspace:1",
      [NSString stringWithFormat:@"%@ %lu %@ %@ %@ %@", j[@"known"], (unsigned long)[j[@"workspaces"] count], jt[@"kind"], jt[@"agent"][@"key"], jt[@"ref"], jt[@"workspace"]]);
    T(@"insides: the JSON names no row twice: the agent under its tab says it is the same row", @"agent minmacs:agent:claude-code:s-71010",
      [NSString stringWithFormat:@"%@ %@", jt[@"children"][0][@"kind"], jt[@"children"][0][@"same"]]);

    // Unreachable and older: one honest line, and the process tree MinMacs knows in place of cmux's.
    for (MMInsidesAnswer *bad in @[sock, old]) {
        MMWindowModel *mb = CmuxModel(s, bad);
        MMWindowRow *ab = AppRow(mb);
        NSArray *under = MMWindowRowInsides(ab);
        T([NSString stringWithFormat:@"insides: %@ cmux says why in its story and shows its process tree: the agents, the server's node and the shells that wait",
           bad.json[@"known"]], [NSString stringWithFormat:@"%@ yes yes yes", bad.why],
          [NSString stringWithFormat:@"%@ %@ %@ %@", FactOf(ab, @"Inside").value, YN([Names(under) containsString:agentRow.name]), YN([Names(under) containsString:@"node"]),
           YN([Names(under) containsString:@"idle shells"])]);
        T([NSString stringWithFormat:@"insides: --json says %@ with why", bad.json[@"known"]], bad.json[@"known"], ab.json[@"insides"][@"known"]);
    }
    // Before any answer: the row still opens, onto one quiet line.
    MMWindowModel *m0 = CmuxModel(s, nil);
    MMWindowRow *a0 = AppRow(m0);
    T(@"insides: before cmux is asked, the row opens onto one quiet line and its story asks nothing of it", @"Looking at cmux nothing",
      [NSString stringWithFormat:@"%@ %@", MMWindowRowInsides(a0).firstObject.name, a0.json[@"insides"][@"known"]]);
    T(@"insides: building models asked cmux nothing", @"0", @(CmuxReads()));
}

/// D11: nothing while the window is closed or the row collapsed; asked when its story shows or it opens, once in 5 s,
/// off main, and reused.
static void InsidesController(void) {
    CmuxWorld();
    MMSetPref(MMWindowWelcomedKey, @YES);
    (void)CmuxSnapshot();
    NSString *appKey = [@"minmacs:app:" stringByAppendingString:MMAppInsidesCmux];
    dispatch_queue_t window = MMQueue(@"core", @"window", QOS_CLASS_USER_INITIATED);
    void (^settle)(void) = ^{ dispatch_sync(window, ^{}); dispatch_sync(MMQueue(@"core", @"insides", QOS_CLASS_UTILITY), ^{}); dispatch_sync(window, ^{}); };
    MMWindowController *c = [MMWindowController new];
    NSMutableArray<MMWindowModel *> *models = [NSMutableArray new];
    c.onModel = ^(MMWindowModel *m) { [models addObject:m]; };

    // Closed: a story, an open row and snapshots ask nothing.
    [c windowShowsStory:appKey];
    [c windowInsides:appKey open:YES];
    for (int i = 0; i < 3; i++) { MMSnapshot *s = WorldSnapshot(); (void)MMWindowModelFrom(s, Build(s), nil); }
    settle();
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    settle();
    T(@"D11: with the window closed, cmux is asked nothing and nothing is kept", @"0 no", [NSString stringWithFormat:@"%ld %@", (long)CmuxReads(),
      YN([MMAppInsides.shared knownFor:MMAppInsidesCmux] != nil)]);

    // Open with the row closed: snapshot after snapshot, and stories of other rows, ask nothing.
    [c setOpen:YES];
    for (uint64_t g = 2; g <= 5; g++) { [c take:SnapshotAt(g)]; Spin(20, ^BOOL { return models.lastObject.generation == g; }); }
    [c windowShowsStory:@"minmacs:agent:claude-code:s-71010"];
    [c windowInsides:appKey open:NO];
    settle();
    T(@"D11: open, with the cmux row closed and no story of it, cmux is asked nothing", @"0", @(CmuxReads()));

    // Its story: one read, off main, and the model that follows holds the tree.
    NSDate *t0 = NSDate.date;
    [c windowShowsStory:appKey];
    NSTimeInterval onMain = -t0.timeIntervalSinceNow;
    BOOL got = Spin(10, ^BOOL { return MMWindowRowInsides(AppRow(models.lastObject)).count == 3; });
    T(@"insides: the cmux row's story asks once, without waiting on main, and the next model holds its 3 workspaces", @"yes 1 yes",
      [NSString stringWithFormat:@"%@ %ld %@", YN(got), (long)CmuxReads(), YN(onMain < 0.2)]);
    [c windowShowsStory:appKey];
    [c windowShowsStory:@"insides:cmux:tab:surface:2"];
    settle();
    T(@"insides: a second story within 5 s is told from what is kept", @"1", @(CmuxReads()));

    // Opened in the list: asked again at most once in 5 s while it stays open, and an answer that did not change is reused.
    NSInteger before = CmuxReads();
    NSDictionary *stats0 = MMAppInsides.shared.stats;
    [c windowInsides:appKey open:YES];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:11.5]];
    settle();
    NSInteger during = CmuxReads() - before;
    NSInteger reused = [MMAppInsides.shared.stats[@"reused"] integerValue] - [stats0[@"reused"] integerValue];
    T(@"D11: opened for 11.5 s, cmux is asked 2 or 3 times, no more than once in 5 s, and the same answer is reused", @"yes yes",
      [NSString stringWithFormat:@"%@ %@", YN(during >= 2 && during <= 3), YN(reused >= 1)]);
    // Closed again: no more reads.
    [c windowInsides:appKey open:NO];
    settle();
    NSInteger closedAt = CmuxReads();
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:6]];
    settle();
    T(@"D11: once the row is closed again, cmux is asked nothing more", @"0", @(CmuxReads() - closedAt));
    // A hang: a look shows "Looking at cmux", an earlier answer stands, and the look ends within its limit.
    CmuxFile(@"cmux.mode", @"sleep");
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    [c windowShowsStory:appKey];
    BOOL looking = Spin(3, ^BOOL { return [MMWindowRowInsidesState(AppRow(models.lastObject))[@"looking"] boolValue]; });
    MMWindowRow *during2 = AppRow(models.lastObject);
    T(@"insides: while cmux is asked, the story says \"Looking at cmux\" and the earlier tree stands", @"yes Looking at cmux 3",
      [NSString stringWithFormat:@"%@ %@ %lu", YN(looking), FactOf(during2, @"Inside").value, (unsigned long)MMWindowRowInsides(during2).count]);
    BOOL ended = Spin(4, ^BOOL { return ![MMWindowRowInsidesState(AppRow(models.lastObject))[@"looking"] boolValue]; });
    T(@"insides: a cmux that hangs is let go within its limit, and the story says it did not answer", @"yes unreachable",
      [NSString stringWithFormat:@"%@ %@", YN(ended), MMWindowRowInsidesState(AppRow(models.lastObject))[@"known"]]);
    // Closed window: everything is let go, and a story asks nothing.
    CmuxFile(@"cmux.mode", @"answer");
    [c setOpen:NO];
    settle();
    NSInteger shut = CmuxReads();
    [c windowShowsStory:appKey];
    [c windowInsides:appKey open:YES];
    settle();
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    T(@"D11: closed again, nothing is kept and nothing is asked", @"no 0", [NSString stringWithFormat:@"%@ %ld",
      YN([MMAppInsides.shared knownFor:MMAppInsidesCmux] != nil), (long)(CmuxReads() - shut)]);
    // Never on main: the CLI's read refuses main, and the window's want only queues.
    T(@"insides: a read never runs on main", @"nil", [MMAppInsides.shared readNow:MMAppInsidesCmux] ? @"answer" : @"nil");
}
