// An app row's insides, UI/Window/MMWindowTree.h. The owner asked: "When we press e.g. cmux, an application we should
// know a lot about, we should have all the top-level details in place: its sessions, and what is happening inside
// each." And then: "we should actually see the hierarchy and information architecture in a similarly translated way."
// The made-up day "agents" with cmux where Terminal stood, three workspaces, a pane of two tabs, its agents in their
// tabs as the Agents rows themselves, a server's tab and three idle shells; and cmux that cannot be reached.
// tools/render.m includes this file after render-window-agents.m, whose helpers it uses. It is not built on its own.
#import "UI/Window/MMWindowTree.h"

static NSString *const kCmuxKey = @"minmacs:app:com.cmuxterm.app";
static const uint64_t kInsMB = 1ull << 20;

static MMWindowRow *InsTab(NSString *ref, NSString *title, NSString *state, double cpu, uint64_t mb, NSInteger depth, NSString *parent, NSArray<MMWindowFact *> *facts) {
    MMWindowRow *r = MMWindowInsidesRow([@"insides:cmux:tab:" stringByAppendingString:ref], MMWindowHelper, title, state, cpu, mb * kInsMB, depth, parent);
    r.goTo = @"cmux";
    NSMutableArray *f = [NSMutableArray arrayWithObject:MMWindowFactRunsIn(@"cmux, a workspace")];
    [f addObjectsFromArray:facts];
    r.facts = f;
    MMWindowRowSetInsidesInfo(r, @{@"kind": @"tab", @"ref": ref});
    return r;
}

static MMWindowFact *InsLink(NSString *label, NSString *value, NSString *link) {
    MMWindowFact *f = [MMWindowFact label:label value:value];
    f.link = link;
    return f;
}

/// The day "agents" with cmux and its insides, as Shell/MMWindowInsides.m builds them. reach: found, unreachable, looking.
static MMWindowModel *InsidesModel(NSString *reach) {
    MMWindowModel *m = MMWindowFixture(@"agents");
    MMWindowGroup *apps = m.memoryGroups[2], *agentsGroup = m.memoryGroups[1];
    NSMutableArray<MMWindowRow *> *rows = [apps.rows mutableCopy];
    MMWindowRow *app = rows[1];
    app.key = kCmuxKey; app.name = @"cmux"; app.iconHint = @"com.cmuxterm.app"; app.state = @"kept";
    NSArray<MMWindowRow *> *agents = agentsGroup.rows;
    MMWindowRow *asks = nil, *lane = [m row:@"agent:3"] ?: agents[3], *codex = [m row:@"agent:2"] ?: agents[2];
    for (MMWindowRow *a in agents) if (a.needsYou && !asks) asks = a;
    MMWindowRow *srv = [m row:@"server:5175"] ?: m.memoryGroups[0].rows.firstObject;
    NSMutableArray<MMWindowFact *> *section = [NSMutableArray new];
    NSMutableArray<MMWindowRow *> *spaces = [NSMutableArray new];
    if ([reach isEqualToString:@"unreachable"]) {
        NSString *why = @"cmux did not answer on its socket, so MinMacs cannot look inside it.";
        MMWindowRowSetInsidesState(app, @{@"app": @"cmux", @"known": @"unreachable", @"looking": @NO, @"why": why});
        [section addObject:[MMWindowFact label:@"Inside" value:why]];
        [spaces addObject:MMWindowInsidesSame(lane, 1, kCmuxKey)];
        MMWindowRow *node = MMWindowInsidesRow(@"insides:cmux:proc:72003", MMWindowHelper, @"node", nil, 3.2, 310 * kInsMB, 1, kCmuxKey);
        node.facts = @[[MMWindowFact label:@"Processes" value:@"3 processes"]];
        [spaces addObject:node];
        MMWindowRow *idle = MMWindowInsidesRow(@"insides:cmux:procs:idle", MMWindowHelper, MMWindowIdleShells(4), nil, 0, 8 * kInsMB, 1, kCmuxKey);
        idle.quiet = YES;
        MMWindowRowSetInsides(idle, @[]);
        [spaces addObject:idle];
    } else {
        NSString *ws1 = @"insides:cmux:ws:AAAA", *ws2 = @"insides:cmux:ws:CCCC", *ws3 = @"insides:cmux:ws:BBBB", *pane = @"insides:cmux:pane:pane:3";
        MMWindowRow *t1 = InsTab(@"surface:1", @"Sort lane C by due", lane.state, 18.4, 940, 2, ws1,
                                 @[InsLink(@"Agent", [NSString stringWithFormat:@"%@ · %@", lane.shownName, lane.state], lane.key), InsLink(@"Recently", @"42 tool uses, 6 files edited in the last hour", nil),
                                   MMWindowFactWorktree(@"barkbot · lane-c", @"worktree:lane-c"), MMWindowFactServer(srv.shownName, srv.key)]);
        MMWindowRowSetInsides(t1, @[MMWindowInsidesSame(lane, 3, t1.key), MMWindowInsidesSame(srv, 3, t1.key)]);
        MMWindowRow *t2 = InsTab(@"surface:2", @"dev server", @"node", 3.2, 310, 2, ws1, @[InsLink(@"Runs", @"node", nil), MMWindowFactFolder(@"~/code/barkbot/web")]);
        MMWindowRow *t3 = InsTab(@"surface:3", @"logs", @"tail", 0.1, 2, 3, pane, @[InsLink(@"Runs", @"tail", nil)]);
        MMWindowRow *t4 = InsTab(@"surface:4", @"zsh", @"zsh", 0, 2, 3, pane, @[InsLink(@"Runs", @"zsh", nil)]);
        MMWindowRow *p = MMWindowInsidesRow(pane, MMWindowHelper, @"Pane with 2 tabs", nil, 0.1, 4 * kInsMB, 2, ws1);
        p.facts = @[[MMWindowFact label:@"Holds" value:@"2 tabs"]];
        MMWindowRowSetInsides(p, @[t3, t4]);
        MMWindowRow *s1 = MMWindowInsidesRow(ws1, MMWindowApp, @"barkbot", @"4 tabs", 21.7, 1254 * kInsMB, 1, kCmuxKey);
        s1.facts = @[InsLink(@"Tab", @"Sort lane C by due · working", t1.key), InsLink(@"Tab", @"dev server · node", t2.key), InsLink(@"Tab", @"logs · tail", t3.key)];
        MMWindowRowSetInsides(s1, @[t1, t2, p]);
        MMWindowRow *t5 = InsTab(@"surface:5", asks.shownName ?: @"Tune the ranking", @"asks you", 0.4, 610, 2, ws2,
                                 @[InsLink(@"Agent", [NSString stringWithFormat:@"%@ · asks you", asks.shownName], asks.key)]);
        t5.needsYou = YES;
        MMWindowRowSetInsides(t5, @[MMWindowInsidesSame(asks, 3, t5.key)]);
        MMWindowRow *t6 = InsTab(@"surface:6", @"Match studio views", codex.state, 0.2, 180, 2, ws2,
                                 @[InsLink(@"Agent", [NSString stringWithFormat:@"%@ · %@", codex.shownName, codex.state], codex.key)]);
        MMWindowRowSetInsides(t6, @[MMWindowInsidesSame(codex, 3, t6.key)]);
        MMWindowRow *s2 = MMWindowInsidesRow(ws2, MMWindowApp, @"atlas", @"2 tabs", 0.6, 790 * kInsMB, 1, kCmuxKey);
        s2.needsYou = YES;
        s2.facts = @[InsLink(@"Tab", [NSString stringWithFormat:@"%@ · asks you", t5.name], t5.key), InsLink(@"Tab", @"Match studio views · idle", t6.key)];
        MMWindowRowSetInsides(s2, @[t5, t6]);
        NSMutableArray *idleTabs = [NSMutableArray new];
        for (NSString *t in @[@"~", @"~/code", @"zsh"]) [idleTabs addObject:InsTab([@"surface:x" stringByAppendingString:t], t, @"zsh", 0, 2, 3, [ws3 stringByAppendingString:@":idle"], @[InsLink(@"Runs", @"zsh", nil)])];
        MMWindowRow *idle = MMWindowInsidesRow([ws3 stringByAppendingString:@":idle"], MMWindowHelper, MMWindowIdleShells(3), nil, 0, 6 * kInsMB, 2, ws3);
        idle.quiet = YES;
        idle.facts = @[[MMWindowFact label:@"Holds" value:@"3 tabs where only a shell waits"]];
        MMWindowRowSetInsides(idle, idleTabs);
        MMWindowRow *s3 = MMWindowInsidesRow(ws3, MMWindowApp, @"scratch", @"3 tabs", 0, 6 * kInsMB, 1, kCmuxKey);
        s3.facts = @[InsLink(@"Idle", MMWindowIdleShells(3), idle.key)];
        MMWindowRowSetInsides(s3, @[idle]);
        [spaces addObjectsFromArray:@[s1, s2, s3]];
        BOOL looking = [reach isEqualToString:@"looking"];
        MMWindowRowSetInsidesState(app, @{@"app": @"cmux", @"known": @"found", @"looking": @(looking), @"why": NSNull.null});
        [section addObject:[MMWindowFact label:@"Inside" value:looking ? MMWindowInsidesLooking(@"cmux") : @"3 workspaces, 3 agents in them, 3 idle shells"]];
        for (MMWindowRow *s in spaces) {
            [section addObject:InsLink(@"Workspace", [NSString stringWithFormat:@"%@ · %@", s.name, s.state], s.key)];
            [section addObjectsFromArray:s.facts];
        }
    }
    MMWindowRowSetInsides(app, spaces);
    app.facts = [@[MMWindowFactStays(@"agents work in it")] arrayByAddingObjectsFromArray:section];
    apps.rows = rows;
    return m;
}

static MMWindowView *InsidesView(NSString *reach) {
    MMWindowView *v = [[MMWindowView alloc] initWithFrame:NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height)];
    v.drawsBacking = YES;
    v.model = InsidesModel(reach);
    return v;
}

/// shot: state names, each opens what it shows.
static void InsidesShotState(MMWindowView *v, NSString *state) {
    MMWindowTreeCloseAll();
    MMWindowRow *agentRow = [v.model row:@"agent:3"];
    if ([state isEqualToString:@"collapsed"]) { v.model = v.model; return; }
    MMWindowTreeSetOpen(kCmuxKey, YES);
    if ([state isEqualToString:@"open"] || [state isEqualToString:@"tab-hover"] || [state isEqualToString:@"tab-active"] || [state isEqualToString:@"agent-hover"]) {
        MMWindowTreeSetOpen(@"insides:cmux:ws:AAAA", YES);
        MMWindowTreeSetOpen(@"insides:cmux:tab:surface:1", YES);
    }
    [v treeShow];
    if ([state isEqualToString:@"story"] || [state isEqualToString:@"unreachable"] || [state isEqualToString:@"looking"]) v.pointedRow = kCmuxKey;
    if ([state isEqualToString:@"tab-hover"]) v.pointedRow = @"insides:cmux:tab:surface:1";
    if ([state isEqualToString:@"tab-active"]) v.activeRow = @"insides:cmux:tab:surface:1";
    if ([state isEqualToString:@"agent-hover"]) v.pointedRow = agentRow.key;
}

static NSArray<NSArray<NSString *> *> *InsidesShots(void) {
    return @[@[@"found", @"collapsed"], @[@"found", @"open"], @[@"found", @"story"], @[@"found", @"tab-hover"], @[@"found", @"tab-active"],
             @[@"found", @"agent-hover"], @[@"looking", @"looking"], @[@"unreachable", @"unreachable"]];
}

static void RenderWindowInsides(NSString *dir, NSDictionary<NSString *, NSAppearance *> *appearances, NSMutableArray *unwritten) {
    for (NSString *mode in @[@"dark", @"contrast-dark"]) {
        NSAppearance *ap = appearances[mode];
        if (!ap) continue;
        MMWindowForceContrast([mode hasPrefix:@"contrast"]);
        for (NSArray<NSString *> *shot in InsidesShots()) {
            MMWindowView *v = InsidesView(shot[0]);
            InsidesShotState(v, shot[1]);
            NSString *path = [dir stringByAppendingFormat:@"/cmux-%@-%@.png", shot[1], mode];
            if (!MMRenderView(v, path, ap)) [unwritten addObject:path.lastPathComponent];
        }
        // The side runs out of room: the deepest levels close first, the workspaces stay.
        MMWindowView *tight = InsidesView(@"found");
        InsidesShotState(tight, @"open");
        MMWindowTreeSetOpen(@"insides:cmux:ws:CCCC", YES); MMWindowTreeSetOpen(@"insides:cmux:ws:BBBB", YES); MMWindowTreeSetOpen(@"insides:cmux:ws:BBBB:idle", YES);
        MMWindowListView *left = WindowLists(tight).firstObject;
        left.frame = NSMakeRect(left.frame.origin.x, left.frame.origin.y, left.frame.size.width, 330);
        [tight treeShow];
        [left reveal:kCmuxKey];
        NSString *path = [dir stringByAppendingFormat:@"/cmux-tight-%@.png", mode];
        if (!MMRenderView(tight, path, ap)) [unwritten addObject:path.lastPathComponent];
        MMWindowForceContrast(NO);
    }
    MMWindowTreeCloseAll();
}

/// The keys the left list shows, in order.
static NSArray<NSString *> *InsidesKeys(MMWindowView *v) { return WindowLists(v).firstObject.rowKeys; }

static void WindowInsidesChecks(void) {
    MMWindowView *v = InsidesView(@"found");
    MMWindowTreeCloseAll();
    [v treeShow];
    NSArray *closed = InsidesKeys(v);
    MMWindowRow *app = [v.model row:kCmuxKey], *lane = [v.model row:@"agent:3"];
    Check(![closed containsObject:@"insides:cmux:ws:AAAA"] && MMWindowTreeOpens(app), @"window insides: the cmux row is closed at first and opens", @"");

    // The keyboard: → on the active cmux row opens it, → on a workspace opens that, ← closes, ← on a tab goes up.
    v.activeRow = kCmuxKey;
    BOOL opened = [v treeArrow:124];
    NSArray *open1 = InsidesKeys(v);
    NSUInteger at = [open1 indexOfObject:kCmuxKey];
    BOOL under = at != NSNotFound && at + 3 < open1.count && [open1[at + 1] isEqualToString:@"insides:cmux:ws:AAAA"] && [open1[at + 2] isEqualToString:@"insides:cmux:ws:CCCC"]
                 && [open1[at + 3] isEqualToString:@"insides:cmux:ws:BBBB"];
    Check(opened && under, @"window insides: → opens the cmux row onto its workspaces, busiest first, right under it", [open1 componentsJoinedByString:@" "]);
    v.activeRow = @"insides:cmux:ws:AAAA";
    [v treeArrow:124];
    v.activeRow = @"insides:cmux:tab:surface:1";
    [v treeArrow:124];
    NSArray *open2 = InsidesKeys(v);
    NSInteger twice = 0;
    for (NSString *k in open2) if ([k isEqualToString:lane.key]) twice++;
    Check([open2 containsObject:@"insides:cmux:tab:surface:2"] && [open2 containsObject:@"insides:cmux:pane:pane:3"] && twice == 2,
          @"window insides: a workspace opens onto its tabs and pane, and a tab onto its agent, the Agents row itself, drawn in both places", [NSString stringWithFormat:@"%ld", (long)twice]);
    // The agent in the tree is the Agents row: pointing at it washes both, and its story is the agent's.
    v.pointedRow = lane.key;
    MMWindowListView *left = WindowLists(v).firstObject;
    MMWindowMiddleView *middle = WordViews(v, MMWindowMiddleView.class).firstObject;
    Check([left.hoverKey isEqualToString:lane.key] && middle.row == lane, @"window insides: the agent under its tab and in Agents are one row: one hover, one story", left.hoverKey ?: @"none");
    v.pointedRow = nil;
    BOOL up = [v treeArrow:123];
    Check(up && [v.activeRow isEqualToString:@"insides:cmux:tab:surface:1"] && !MMWindowTreeIsOpen(@"insides:cmux:tab:surface:1"),
          @"window insides: ← closes an open tab", v.activeRow ?: @"none");
    [v treeArrow:123];
    Check([v.activeRow isEqualToString:@"insides:cmux:ws:AAAA"], @"window insides: ← on a closed tab goes up to its workspace", v.activeRow ?: @"none");

    // VoiceOver reads an outline: each row of the tree its level, and whether it is open.
    NSDictionary *levels = nil;
    NSMutableDictionary *seen = [NSMutableDictionary new];
    for (NSAccessibilityElement *el in left.accessibilityChildren) {
        NSString *k = [(id)el valueForKey:@"key"];
        if ([k isEqualToString:kCmuxKey] || [k hasPrefix:@"insides:cmux:ws:AAAA"] || [k isEqualToString:@"insides:cmux:tab:surface:2"])
            seen[k] = [NSString stringWithFormat:@"%@ %ld %@", el.accessibilityRole, (long)el.accessibilityDisclosureLevel, el.isAccessibilityDisclosed ? @"open" : @"closed"];
    }
    levels = @{kCmuxKey: @"AXRow 0 open", @"insides:cmux:ws:AAAA": @"AXRow 1 open", @"insides:cmux:tab:surface:2": @"AXRow 2 closed"};
    Check([seen isEqualToDictionary:levels], @"window insides: VoiceOver reads the tree as an outline, with each row's level and whether it is open", seen.description);

    // A press on the disclosure or with Option opens; any other press only picks the row. Out of a window the pointer is
    // nowhere, so here only the keys and a direct toggle are held.
    [v treeToggle:@"insides:cmux:ws:BBBB"];
    Check([InsidesKeys(v) containsObject:@"insides:cmux:ws:BBBB:idle"], @"window insides: three idle shells are one row, \"3 idle shells\", which opens", @"");

    // Room runs out: on a short side the deepest levels close first, and the workspaces stay.
    MMWindowTreeSetOpen(@"insides:cmux:tab:surface:1", YES); MMWindowTreeSetOpen(@"insides:cmux:ws:CCCC", YES); MMWindowTreeSetOpen(@"insides:cmux:ws:BBBB:idle", YES);
    MMWindowTreeSetOpen(@"insides:cmux:ws:AAAA", YES);
    NSArray<MMWindowGroup *> *roomy = MMWindowTreeGroups(v.model.memoryGroups, 1200), *tight = MMWindowTreeGroups(v.model.memoryGroups, 330);
    NSInteger (^deepest)(NSArray<MMWindowGroup *> *) = ^NSInteger(NSArray<MMWindowGroup *> *gs) {
        NSInteger d = 0;
        for (MMWindowRow *r in gs[2].rows) d = MAX(d, MMWindowRowDepth(r));
        return d;
    };
    NSInteger spaces = 0;
    for (MMWindowRow *r in tight[2].rows) if (MMWindowRowDepth(r) == 1) spaces++;
    Check(deepest(roomy) == 3 && deepest(tight) < 3 && spaces == 3, @"window insides: with room the tree shows to its tabs' agents; short of room the deepest levels close first, all 3 workspaces stay",
          [NSString stringWithFormat:@"%ld %ld %ld", (long)deepest(roomy), (long)deepest(tight), (long)spaces]);

    // The words: no ellipsis and no aside in anything the tree or its stories show, found, looking or unreachable.
    NSMutableArray *bad = [NSMutableArray new];
    for (NSString *reach in @[@"found", @"looking", @"unreachable"]) {
        MMWindowView *w = InsidesView(reach);
        InsidesShotState(w, @"open");
        for (NSString *key in @[kCmuxKey, @"insides:cmux:ws:AAAA", @"insides:cmux:tab:surface:1", @"insides:cmux:pane:pane:3"]) {
            if (![w.model row:key]) continue;
            w.pointedRow = key;
            NSArray *all = [CachesDrawn(w) arrayByAddingObjectsFromArray:CachesDrawn(WindowLists(w).firstObject)];
            for (NSString *s in all) if ([s containsString:@"…"] || [s containsString:@"..."] || [s containsString:@"("]) [bad addObject:s];
        }
    }
    Check(!bad.count, @"window insides: no row or story of the tree holds an ellipsis or an aside", [bad componentsJoinedByString:@" | "]);
    MMWindowView *u = InsidesView(@"unreachable");
    InsidesShotState(u, @"unreachable");
    NSString *told = [CachesDrawn(u) componentsJoinedByString:@" | "];
    Check([told containsString:@"cmux did not answer on its socket"] && [told containsString:@"4 idle shells"], @"window insides: cmux unreachable says so in one line and shows its process tree", told);
    MMWindowView *l = InsidesView(@"looking");
    InsidesShotState(l, @"looking");
    Check([[CachesDrawn(l) componentsJoinedByString:@" | "] containsString:@"Looking at cmux"], @"window insides: while cmux is asked, one quiet line says Looking at cmux", @"");
    MMWindowTreeCloseAll();
}

/// D11's bench: the window opened on the day "agents" with cmux closed, and with cmux and a workspace and a tab open.
/// Printed beside issue #53's timings, for docs/2.0/BENCH.md.
static void InsidesOpenTiming(NSAppearance *ap) {
    if (!ap) return;
    NSRect frame = NSMakeRect(0, 0, MMWindowSize.width, MMWindowSize.height);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)(frame.size.width * 2)
        pixelsHigh:(NSInteger)(frame.size.height * 2) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    rep.size = frame.size;
    NSMutableArray<NSString *> *said = [NSMutableArray new];
    for (NSString *state in @[@"collapsed", @"open"]) {
        NSMutableArray<NSNumber *> *ms = [NSMutableArray new];
        for (NSInteger i = 0; i < 31; i++) {
            MMWindowModel *m = InsidesModel(@"found");
            uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            MMWindowView *v = [[MMWindowView alloc] initWithFrame:frame];
            v.drawsBacking = YES;
            v.model = m;
            InsidesShotState(v, state);
            [ap performAsCurrentDrawingAppearance:^{ [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep]; }];
            if (i) [ms addObject:@((clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0) / 1e6)];
        }
        NSArray<NSNumber *> *sorted = [ms sortedArrayUsingSelector:@selector(compare:)];
        [said addObject:[NSString stringWithFormat:@"%@ p50 %.1f ms, p95 %.1f ms", state, sorted[sorted.count / 2].doubleValue, sorted[(NSUInteger)(sorted.count * 0.95)].doubleValue]];
    }
    MMWindowTreeCloseAll();
    printf("window open with cmux, D11: %s, n 30\n", [said componentsJoinedByString:@"; "].UTF8String);
}
